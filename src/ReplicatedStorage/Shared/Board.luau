-- The board simulation.
--
-- No Roblox API: no Instances, no tick(), no Random.new(), nothing that reads
-- the outside world. It takes a seed and a stream of inputs and produces the
-- same result every time, which is what lets the identical module run as client
-- prediction, as server authority, and inside the bot — and be tested headlessly.
--
-- Coordinates: column 1..w left to right, row 1..h from the BOTTOM. Rows 1..20
-- are visible; 21..40 are buffer. The piece's (x, y) is its bounding-box origin,
-- x zero-indexed from the left wall and y a field row.

local Tuning = require(script.Parent.Tuning)
local Pieces = require(script.Parent.Pieces)
local SRS = require(script.Parent.SRS)
local Bag = require(script.Parent.Bag)
local Attack = require(script.Parent.Attack)

local Board = {}
Board.__index = Board

-- Corners of the T's 3x3 box, and which two count as "front" per rotation.
-- Three corners filled makes it a T-spin; both front corners filled makes it a
-- full one rather than a mini.
local T_CORNERS = { { 0, 0 }, { 2, 0 }, { 0, 2 }, { 2, 2 } }
local T_FRONT = {
	{ { 0, 2 }, { 2, 2 } }, -- spawn, pointing up
	{ { 2, 2 }, { 2, 0 } }, -- right
	{ { 0, 0 }, { 2, 0 } }, -- 180
	{ { 0, 0 }, { 0, 2 } }, -- left
}

function Board.new(seed: number, opts: any?)
	opts = opts or {}
	local self = setmetatable({}, Board)
	self.w, self.h, self.visible = Tuning.WIDTH, Tuning.HEIGHT, Tuning.VISIBLE
	self.cells = table.create(self.w * self.h, 0)
	self.seed = seed
	self.bag = Bag.new(seed)
	-- Garbage columns come off a separate stream. Sharing the piece RNG would
	-- mean the sequence depended on when garbage landed, and client and server
	-- would drift apart the moment their timing differed by a frame.
	self.garbageBag = Bag.new(bit32.bxor(seed, 0x9E3779B9))

	self.piece = nil
	self.hold = nil
	self.holdUsed = false
	self.gravity = opts.gravity or Tuning.GRAVITY
	self.softDropping = false
	self.gravityAcc = 0
	self.lockTimer = 0
	self.lockResets = 0
	self.grounded = false
	self.spawnDelay = 0
	self.lastKick = false -- last successful action was a rotation
	self.lastSpin = nil  -- the rotation itself, for the server to replay
	self.combo = 0
	self.b2b = false
	self.incoming = {}
	self.garbageCol = nil
	self.alive = true
	self.topOut = nil
	self.time = 0
	self.events = {}
	self.stats = { pieces = 0, lines = 0, attack = 0, sent = 0, received = 0,
		quads = 0, tspins = 0, perfects = 0 }

	self:spawn()
	return self
end

-- ── Cells ─────────────────────────────────────────────────────────────────

function Board:at(col: number, row: number): number
	if col < 1 or col > self.w or row < 1 or row > self.h then return 0 end
	return self.cells[(row - 1) * self.w + col]
end

-- Walls and the floor count as solid; open air above the buffer does not.
function Board:solid(col: number, row: number): boolean
	if col < 1 or col > self.w or row < 1 then return true end
	if row > self.h then return false end
	return self.cells[(row - 1) * self.w + col] ~= 0
end

function Board:collides(kind: number, rot: number, x: number, y: number): boolean
	local shape = Pieces.SHAPES[kind][rot]
	for i = 1, 4 do
		local c = shape[i]
		local col, row = x + c[1] + 1, y + c[2]
		if col < 1 or col > self.w or row < 1 then return true end
		if row <= self.h and self.cells[(row - 1) * self.w + col] ~= 0 then return true end
	end
	return false
end

function Board:emit(kind: string, data: any)
	table.insert(self.events, { kind = kind, data = data })
end

function Board:drain(): { any }
	local e = self.events
	self.events = {}
	return e
end

-- ── Piece lifecycle ───────────────────────────────────────────────────────

function Board:spawn(kind: number?): boolean
	kind = kind or self.bag:pop()
	local sp = Pieces.SPAWN[kind]
	self.holdUsed = false
	self.gravityAcc, self.lockTimer, self.lockResets, self.grounded = 0, 0, 0, false
	self.lastKick = false
	self.lastSpin = nil

	if self:collides(kind, 1, sp.x, sp.y) then
		self.piece = nil
		self.alive = false
		self.topOut = "block"
		self:emit("topout", { reason = "block" })
		return false
	end
	self.piece = { kind = kind, rot = 1, x = sp.x, y = sp.y }
	self:emit("spawn", { kind = kind })
	return true
end

-- Refreshing lock delay is capped, or a piece can be spun on the floor forever
-- and the match never ends.
function Board:touchLock()
	if self.grounded and self.lockResets < Tuning.LOCK_RESETS then
		self.lockTimer = 0
		self.lockResets += 1
	end
end

function Board:move(dx: number): boolean
	local p = self.piece
	if not p or not self.alive then return false end
	if self:collides(p.kind, p.rot, p.x + dx, p.y) then return false end
	p.x += dx
	self.lastKick = false
	self.lastSpin = nil
	self:touchLock()
	return true
end

function Board:rotate(dir: number): boolean
	local p = self.piece
	if not p or not self.alive then return false end
	local fromRot, fromX, fromY = p.rot, p.x, p.y
	local to = SRS.turn(p.rot, dir)
	for _, k in ipairs(SRS.kicks(p.kind, p.rot, to)) do
		local nx, ny = p.x + k[1], p.y + k[2]
		if not self:collides(p.kind, to, nx, ny) then
			p.rot, p.x, p.y = to, nx, ny
			self.lastKick = true
			-- Where the piece was before this rotation. The server never runs
			-- the player's rotations, so this travels with the lock and is
			-- replayed there against the server's own cells — see verifySpin.
			self.lastSpin = { rot = fromRot, x = fromX, y = fromY, dir = dir }
			self:touchLock()
			return true
		end
	end
	return false
end

-- Could this placement have been reached by the rotation described in `spin`?
--
-- The shadow board is advanced by reported placements, never by the player's
-- inputs, so it cannot observe that the last action was a rotation — and a
-- T-spin is defined by exactly that. What the server can do is replay the
-- claimed rotation on its own cells: the piece must have fitted where the
-- client says it was, that position must be one the piece could actually have
-- got to, and the SRS kick table applied from there must land precisely here.
--
-- This is a witness the server checks, not a claim it believes. Nothing about
-- the spin — full or mini, the lines, the attack — is taken from the client; a
-- verified witness only sets the same `lastKick` flag the player's own rotation
-- would have set, and detection proceeds from the server's board as usual. A
-- forged witness that fails any step buys nothing, and one that passes
-- describes a rotation the player could legitimately have performed.
function Board:verifySpin(kind: number, rot: number, x: number, y: number, spin: any): boolean
	if type(spin) ~= "table" then return false end
	local fromRot, fromX, fromY, dir =
		tonumber(spin.rot), tonumber(spin.x), tonumber(spin.y), tonumber(spin.dir)
	if not (fromRot and fromX and fromY and dir) then return false end
	if fromRot % 1 ~= 0 or fromX % 1 ~= 0 or fromY % 1 ~= 0 then return false end
	if fromRot < 1 or fromRot > 4 then return false end
	if dir ~= 1 and dir ~= -1 then return false end
	if SRS.turn(fromRot, dir) ~= rot then return false end
	-- The piece has to have fitted where it says it was standing.
	if self:collides(kind, fromRot, fromX, fromY) then return false end
	for _, k in ipairs(SRS.kicks(kind, fromRot, rot)) do
		local nx, ny = fromX + k[1], fromY + k[2]
		if not self:collides(kind, rot, nx, ny) then
			-- SRS takes the first offset that fits, so the landing square is
			-- forced: either it is the one claimed or the claim is false.
			return nx == x and ny == y and self:reachable(kind, fromRot, fromX, fromY)
		end
	end
	return false
end

function Board:stepDown(): boolean
	local p = self.piece
	if not p then return false end
	if self:collides(p.kind, p.rot, p.x, p.y - 1) then return false end
	p.y -= 1
	self.lastKick = false
	self.lastSpin = nil
	return true
end

function Board:hardDrop(): number
	if not self.piece or not self.alive then return 0 end
	local n = 0
	while self:stepDown() do n += 1 end
	self:lock()
	return n
end

function Board:swapHold(): boolean
	if self.holdUsed or not self.piece or not self.alive then return false end
	local cur = self.piece.kind
	local swap = self.hold
	self.hold = cur
	self:spawn(swap) -- nil pulls the next from the bag
	self.holdUsed = true -- spawn() clears the flag, so set it after
	self:emit("hold", { kind = cur })
	return true
end

function Board:ghostY(): number?
	local p = self.piece
	if not p then return nil end
	local y = p.y
	while not self:collides(p.kind, p.rot, p.x, y - 1) do
		y -= 1
	end
	return y
end

-- ── Clearing and locking ──────────────────────────────────────────────────

function Board:detectTSpin(): string?
	local p = self.piece
	if not p or p.kind ~= Pieces.T or not self.lastKick then return nil end
	local filled = 0
	for _, c in ipairs(T_CORNERS) do
		if self:solid(p.x + c[1] + 1, p.y + c[2]) then filled += 1 end
	end
	if filled < 3 then return nil end
	local front = 0
	for _, c in ipairs(T_FRONT[p.rot]) do
		if self:solid(p.x + c[1] + 1, p.y + c[2]) then front += 1 end
	end
	return front >= 2 and "full" or "mini"
end

function Board:clearLines(): { number }
	local rows = {}
	for row = 1, self.h do
		local full = true
		local base = (row - 1) * self.w
		for col = 1, self.w do
			if self.cells[base + col] == 0 then
				full = false
				break
			end
		end
		if full then table.insert(rows, row) end
	end
	if #rows == 0 then return rows end

	local isCleared = {}
	for _, r in ipairs(rows) do isCleared[r] = true end
	local write = 1
	for read = 1, self.h do
		if not isCleared[read] then
			if write ~= read then
				local wb, rb = (write - 1) * self.w, (read - 1) * self.w
				for col = 1, self.w do
					self.cells[wb + col] = self.cells[rb + col]
				end
			end
			write += 1
		end
	end
	for row = write, self.h do
		local base = (row - 1) * self.w
		for col = 1, self.w do
			self.cells[base + col] = 0
		end
	end
	return rows
end

function Board:isEmpty(): boolean
	for i = 1, self.w * self.h do
		if self.cells[i] ~= 0 then return false end
	end
	return true
end

function Board:lock()
	local p = self.piece
	if not p or not self.alive then return end

	local tspin = self:detectTSpin()
	-- Where it actually came to rest. Reported on the lock event so callers
	-- never have to reconstruct it — the server validates against this, and
	-- guessing it from the piece state one step earlier is off by a row
	-- whenever gravity moved the piece during the same tick.
	-- `spin` is the rotation that put it here, when a rotation is what put it
	-- here. The server replays it to reach the same T-spin verdict on its own
	-- board; it is evidence, not a result.
	local placed = { kind = p.kind, rot = p.rot, x = p.x, y = p.y,
		spin = self.lastKick and self.lastSpin or nil }
	local shape = Pieces.SHAPES[p.kind][p.rot]
	local lowest = math.huge
	for i = 1, 4 do
		local c = shape[i]
		local col, row = p.x + c[1] + 1, p.y + c[2]
		if col >= 1 and col <= self.w and row >= 1 and row <= self.h then
			self.cells[(row - 1) * self.w + col] = p.kind
		end
		if row < lowest then lowest = row end
	end
	self.stats.pieces += 1
	self.piece = nil

	-- Lock out: it came to rest entirely above the visible field.
	if lowest > self.visible then
		self.alive = false
		self.topOut = "lock"
		self:emit("topout", { reason = "lock" })
		return
	end

	local cleared = self:clearLines()
	local n = #cleared
	if n > 0 then
		self.combo += 1
		self.stats.lines += n
	else
		self.combo = 0
	end

	local perfect = n > 0 and self:isEmpty()
	local info = Attack.compute(n, tspin, perfect, self.b2b, self.combo)
	if n > 0 then
		self.b2b = Attack.isB2BClear(n, tspin)
		if n >= 4 then self.stats.quads += 1 end
		if tspin then self.stats.tspins += 1 end
		if perfect then self.stats.perfects += 1 end
	end

	-- Outgoing eats the incoming queue before any of it is sent. This is the
	-- whole of battle Tetris defence.
	local send = 0
	if info.attack > 0 then
		send = Attack.cancel(self.incoming, info.attack)
		self.stats.attack += info.attack
		self.stats.sent += send
	end

	-- Garbage only lands on a lock that cleared nothing.
	local took = 0
	if n == 0 then
		took = self:applyReadyGarbage()
	end

	self:emit("lock", { info = info, send = send, cleared = cleared, garbage = took, placed = placed })

	if self.alive then
		self.spawnDelay = (n > 0) and Tuning.CLEAR_DELAY or Tuning.ARE
		if self.spawnDelay <= 0 then self:spawn() end
	end
end

-- ── Garbage ───────────────────────────────────────────────────────────────

-- Charged, not instant: it sits in the queue for GARBAGE_DELAY so the receiver
-- has a window to cancel it.
function Board:queueGarbage(rows: number, gapCol: number?, at: number?)
	if rows <= 0 then return end
	table.insert(self.incoming, {
		rows = rows,
		gapCol = gapCol,
		at = at or (self.time + Tuning.GARBAGE_DELAY),
	})
end

function Board:applyReadyGarbage(): number
	local total = 0
	local i = 1
	while i <= #self.incoming and total < Tuning.GARBAGE_CAP do
		local item = self.incoming[i]
		if item.at <= self.time then
			local take = math.min(item.rows, Tuning.GARBAGE_CAP - total)
			self:addGarbage(take, item.gapCol)
			total += take
			item.rows -= take
			if item.rows <= 0 then
				table.remove(self.incoming, i)
			else
				i += 1
			end
			if not self.alive then break end
		else
			i += 1
		end
	end
	return total
end

function Board:addGarbage(rows: number, gapCol: number?)
	if rows <= 0 or not self.alive then return end

	-- One gap per batch, re-rolled with a bias on each new batch. A fixed column
	-- is farmable; a fully random one is unreadable.
	if gapCol then
		self.garbageCol = gapCol
	elseif self.garbageCol == nil
		or self.garbageBag:_next(100) <= Tuning.GARBAGE_RECOLUMN * 100 then
		self.garbageCol = self.garbageBag:_next(self.w)
	end
	local col = self.garbageCol

	-- Push-out: anything already in the top `rows` of the buffer has nowhere to go.
	for row = self.h - rows + 1, self.h do
		local base = (row - 1) * self.w
		for c = 1, self.w do
			if self.cells[base + c] ~= 0 then
				self.alive = false
				self.topOut = "garbage"
				self:emit("topout", { reason = "garbage" })
				return
			end
		end
	end

	for row = self.h, rows + 1, -1 do
		local dst, src = (row - 1) * self.w, (row - rows - 1) * self.w
		for c = 1, self.w do
			self.cells[dst + c] = self.cells[src + c]
		end
	end
	for row = 1, rows do
		local base = (row - 1) * self.w
		for c = 1, self.w do
			self.cells[base + c] = (c == col) and 0 or Pieces.GARBAGE
		end
	end

	-- The active piece rides up with the field rather than being buried.
	local p = self.piece
	if p and not self:collides(p.kind, p.rot, p.x, p.y + rows) then
		p.y += rows
	end

	self.stats.received += rows
	self:emit("garbage", { rows = rows, gapCol = col })
end

-- ── Stepping ──────────────────────────────────────────────────────────────

function Board:step(dt: number)
	if not self.alive then return end
	self.time += dt

	if not self.piece then
		self.spawnDelay -= dt
		if self.spawnDelay <= 0 then
			self:applyReadyGarbage()
			if self.alive then self:spawn() end
		end
		return
	end

	local g = self.softDropping and math.max(self.gravity, Tuning.SOFT_DROP_G) or self.gravity
	self.gravityAcc += g * dt
	while self.gravityAcc >= 1 do
		self.gravityAcc -= 1
		if not self:stepDown() then
			self.gravityAcc = 0
			break
		end
	end

	local p = self.piece
	if self:collides(p.kind, p.rot, p.x, p.y - 1) then
		if not self.grounded then
			self.grounded = true
			self.lockTimer = 0
		end
		self.lockTimer += dt
		if self.lockTimer >= Tuning.LOCK_DELAY then
			self:lock()
		end
	else
		self.grounded = false
		self.lockTimer = 0
	end
end

-- ── Views ─────────────────────────────────────────────────────────────────

-- Visible field only, for rendering and for the opponent's mini board.
function Board:snapshot(): { number }
	local out = table.create(self.w * self.visible, 0)
	for i = 1, self.w * self.visible do
		out[i] = self.cells[i]
	end
	return out
end

function Board:next(count: number): { number }
	return self.bag:peek(count or Tuning.PREVIEW)
end

function Board:columnHeight(col: number): number
	for row = self.h, 1, -1 do
		if self.cells[(row - 1) * self.w + col] ~= 0 then return row end
	end
	return 0
end

-- ── Authority ─────────────────────────────────────────────────────────────

-- Could a piece of this kind actually get from spawn to this resting place?
-- BFS over (rot, x, y); the state space is 4 x 10 x 40, so this is cheap enough
-- to run on every lock the server receives.
function Board:reachable(kind: number, rot: number, x: number, y: number): boolean
	local sp = Pieces.SPAWN[kind]
	if self:collides(kind, 1, sp.x, sp.y) then return false end
	if self:collides(kind, rot, x, y) then return false end

	local seen = {}
	local function key(r, cx, cy) return ((r * 128) + (cx + 16)) * 128 + (cy + 16) end
	local queue = { { 1, sp.x, sp.y } }
	seen[key(1, sp.x, sp.y)] = true

	local head = 1
	while head <= #queue do
		local s = queue[head]
		head += 1
		local r, cx, cy = s[1], s[2], s[3]
		if r == rot and cx == x and cy == y then return true end

		local function push(nr, nx, ny)
			if self:collides(kind, nr, nx, ny) then return end
			local k = key(nr, nx, ny)
			if seen[k] then return end
			seen[k] = true
			table.insert(queue, { nr, nx, ny })
		end

		push(r, cx - 1, cy)
		push(r, cx + 1, cy)
		push(r, cx, cy - 1)
		for _, dir in ipairs({ 1, -1 }) do
			local to = SRS.turn(r, dir)
			for _, k in ipairs(SRS.kicks(kind, r, to)) do
				if not self:collides(kind, to, cx + k[1], cy + k[2]) then
					push(to, cx + k[1], cy + k[2])
					break -- SRS takes the first kick that fits, so only that one is reachable
				end
			end
		end
	end
	return false
end

-- A copy safe to mutate. Used by the bot to try a placement without touching
-- the real board.
--
-- The bags MUST be copied, not shared. A trial board that hard-drops locks and
-- spawns, and spawning pops the bag — so a shared bag means the bot's search
-- eats the real piece sequence, dozens of pieces per decision. That desyncs the
-- board from every other copy running the same seed, which is the one invariant
-- the whole networking model rests on.
function Board:clone()
	local c = setmetatable({}, Board)
	for k, v in pairs(self) do c[k] = v end
	c.cells = table.clone(self.cells)
	c.bag = Bag.load(self.bag:save())
	c.garbageBag = Bag.load(self.garbageBag:save())
	c.incoming = {}
	c.events = {}
	c.stats = table.clone(self.stats)
	c.piece = self.piece and table.clone(self.piece) or nil
	return c
end

return Board
