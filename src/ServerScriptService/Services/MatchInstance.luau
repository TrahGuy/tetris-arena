-- One 1v1 match. Owns both shadow boards, the garbage routing and the result.
--
-- Authority model: a player's shadow board never runs gravity of its own. It
-- advances only when that client reports a lock, and every lock is checked for
-- (a) a piece the player could legally be holding, (b) a placement actually
-- reachable from spawn on the server's own cells, and (c) plausible timing.
-- Clears, attack and KO are then computed from the shadow, never from anything
-- the client claims.
--
-- On disagreement the server resyncs the client rather than kicking. Treating
-- every mismatch as cheating turns our own desync bugs into bans, and the false
-- positives land on honest players with bad connections.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Board = require(Shared.Board)
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)
local Net = require(Shared.Net)
local Remotes = require(Shared.Remotes)
local BotService = require(script.Parent.BotService)

local MatchInstance = {}
MatchInstance.__index = MatchInstance

local MISMATCHES_BEFORE_RESYNC = 3

local function makeSide(spec: any, seed: number)
	local side = {
		player = spec.player,
		-- spec.name lets a side exist without a Player behind it, which is what
		-- makes a two-player match testable without two clients.
		name = spec.name or (spec.player and spec.player.DisplayName) or nil,
		alive = true,
		lastIndex = 0,
		lastLockAt = 0,
		mismatches = 0,
		rejects = 0,
		accepted = 0,
		lastReject = "",
		snapshot = nil,
		incoming = 0,
	}
	if spec.bot then
		side.bot = BotService.new(seed, spec.bot)
		side.board = side.bot.board
		side.name = side.bot.name
		side.isBot = true
	else
		side.board = Board.new(seed)
	end
	return side
end

function MatchInstance.new(id: number, specA: any, specB: any, opts: any?)
	opts = opts or {}
	local seed = opts.seed or math.random(1, 2 ^ 31 - 1)
	local self = setmetatable({
		id = id,
		seed = seed,
		mode = opts.mode or Enums.Mode.Quick,
		state = Enums.State.Countdown,
		elapsed = 0,
		rng = Random.new(seed),
		finished = false,
		onFinished = nil,
		suddenTimer = 0,
	}, MatchInstance)

	self.a = makeSide(specA, seed)
	self.b = makeSide(specB, seed)
	self.a.other, self.b.other = self.b, self.a

	for _, side in ipairs({ self.a, self.b }) do
		if side.player then
			Remotes.MatchUpdate:FireClient(side.player, {
				state = Enums.State.Countdown,
				seed = seed,
				mode = self.mode,
				opponent = side.other.name,
				isBot = side.other.isBot == true,
				gravity = Tuning.GRAVITY,
			})
		end
	end

	task.delay(Tuning.COUNTDOWN, function()
		if not self.finished then
			self.state = Enums.State.Playing
		end
	end)
	return self
end

-- One line per match, published to an attribute by Bootstrap. Attributes are
-- the only state a live server shares with the command bar or with MCP —
-- module tables read from outside are a different copy — so this is how a
-- running match gets inspected at all.
function MatchInstance:summary(): string
	local function s(side: any)
		return ("%s[ok %d rej %d%s p%d L%d%s]"):format(
			tostring(side.name),
			side.accepted, side.rejects,
			side.lastReject ~= "" and (" '" .. side.lastReject .. "'") or "",
			side.board.stats.pieces, side.board.stats.lines,
			side.alive and "" or " DEAD")
	end
	return ("#%d %s t%.0f %s vs %s"):format(self.id, self.state, self.elapsed,
		s(self.a), s(self.b))
end

function MatchInstance:sideFor(player: Player)
	if self.a.player == player then return self.a end
	if self.b.player == player then return self.b end
	return nil
end

function MatchInstance:hasPlayer(player: Player): boolean
	return self:sideFor(player) ~= nil
end

-- ── Locks ─────────────────────────────────────────────────────────────────

function MatchInstance:_reject(side: any, why: string)
	side.rejects += 1
	side.lastReject = why
	if side.rejects % 5 == 1 then
		warn(("[Match %d] rejected a lock from %s: %s"):format(
			self.id, tostring(side.name), why))
	end
	self:_resync(side)
end

-- A full restatement of the board, not just the cells.
--
-- The bag matters most: if the piece sequences drifted apart, sending only
-- cells leaves the client playing a different piece to the one the server
-- expects and every subsequent lock is rejected. `index` matters nearly as
-- much — the client keeps numbering its locks while a rejected one leaves the
-- server's counter behind, so without realigning it here a single rejection
-- would cascade into a permanently broken player.
function MatchInstance:_resync(side: any)
	local b = side.board
	local payload = {
		cells = b.cells,
		piece = b.piece and table.clone(b.piece) or nil,
		hold = b.hold,
		holdUsed = b.holdUsed,
		bag = b.bag:save(),
		combo = b.combo,
		b2b = b.b2b,
		index = side.lastIndex,
	}
	if side.player then
		Remotes.Resync:FireClient(side.player, payload)
	end
	if self.onResync then
		self.onResync(side, payload)
	end
	side.mismatches = 0
end

function MatchInstance:onLock(player: Player, msg: any)
	local side = self:sideFor(player)
	if not side then return end
	self:applyLock(side, msg)
end

-- Split from onLock so a side can be driven without a Player attached.
function MatchInstance:applyLock(side: any, msg: any)
	if self.finished or type(msg) ~= "table" then return end

	-- Cosmetic snapshot relay, and the divergence check.
	if msg.snapshot then
		side.snapshot = msg.snapshot
		side.incoming = tonumber(msg.incoming) or 0
		local other = side.other
		if other.player then
			Remotes.Snapshot:FireClient(other.player, msg.snapshot, { incoming = side.incoming })
		end
		local mine = Net.packBoard(side.board:snapshot())
		local ok = buffer.len(mine) == buffer.len(msg.snapshot)
		if ok then
			for i = 0, buffer.len(mine) - 1 do
				if buffer.readu8(mine, i) ~= buffer.readu8(msg.snapshot, i) then
					ok = false
					break
				end
			end
		end
		-- Garbage landing a frame apart is a legitimate transient difference, so
		-- only a persistent disagreement is worth correcting.
		side.mismatches = ok and 0 or (side.mismatches + 1)
		if side.mismatches >= MISMATCHES_BEFORE_RESYNC then
			self:_resync(side)
		end
		return
	end

	if msg.topout then
		if side.alive then
			side.alive = false
			self:_finish(side, Enums.Result.Win)
		end
		return
	end

	if self.state ~= Enums.State.Playing or not side.alive then return end

	local index = tonumber(msg.index)
	if index ~= side.lastIndex + 1 then
		return self:_reject(side, "out of order index")
	end
	local now = os.clock()
	if now - side.lastLockAt < Tuning.MIN_LOCK_INTERVAL then
		return self:_reject(side, "locking faster than physically possible")
	end

	local b = side.board
	if not b.piece then return self:_reject(side, "no active piece") end

	local kind, rot, x, y = tonumber(msg.kind), tonumber(msg.rot), tonumber(msg.x), tonumber(msg.y)
	if not (kind and rot and x and y) or rot < 1 or rot > 4 then
		return self:_reject(side, "malformed placement")
	end

	-- The claimed piece must be one the player could actually have: the active
	-- one, or a legal hold swap into it.
	if kind ~= b.piece.kind then
		local canSwap = not b.holdUsed
			and (b.hold == kind or (b.hold == nil and b.bag:peek(1)[1] == kind))
		if not canSwap then
			return self:_reject(side, "piece is not the one in play")
		end
		b:swapHold()
	end
	if not b:reachable(kind, rot, x, y) then
		return self:_reject(side, "placement is not reachable")
	end

	side.lastIndex = index
	side.lastLockAt = now
	side.accepted += 1
	b.piece.rot, b.piece.x, b.piece.y = rot, x, y
	b.time = self.elapsed
	b:lock()

	-- The shadow does not run gravity, so it never spawns on its own.
	if b.alive and not b.piece then
		b.spawnDelay = 0
		b:applyReadyGarbage()
		if b.alive then b:spawn() end
	end
	self:_drain(side)
end

-- Turns a side's board events into garbage on the other side and KOs.
function MatchInstance:_drain(side: any)
	for _, e in ipairs(side.board:drain()) do
		if e.kind == "lock" and e.data.send > 0 then
			self:_send(side, e.data.send)
		elseif e.kind == "topout" then
			side.alive = false
		end
	end
	if not side.alive and not self.finished then
		self:_finish(side, Enums.Result.Win)
	end
end

function MatchInstance:_send(from: any, rows: number)
	local target = from.other
	local gap = self.rng:NextInteger(1, Tuning.WIDTH)
	target.board:queueGarbage(rows, gap, self.elapsed + Tuning.GARBAGE_DELAY)
	if target.player then
		Remotes.Garbage:FireClient(target.player, { rows = rows, gapCol = gap })
	end
	-- Same information the client gets, for anything else that needs it — the
	-- two-player test mirrors it onto its stand-in client boards.
	if self.onGarbage then
		self.onGarbage(target, rows, gap)
	end
end

-- ── Loop ──────────────────────────────────────────────────────────────────

function MatchInstance:update(dt: number)
	if self.finished or self.state ~= Enums.State.Playing then return end
	self.elapsed += dt
	self.a.board.time = self.elapsed
	self.b.board.time = self.elapsed

	for _, side in ipairs({ self.a, self.b }) do
		if side.bot and side.alive then
			side.bot:update(dt)
			self:_drain(side)
			-- Bots have no client, so the server produces their snapshots.
			side.snapTimer = (side.snapTimer or 0) + dt
			if side.snapTimer >= 1 / Tuning.SNAPSHOT_HZ then
				side.snapTimer = 0
				local packed = Net.packBoard(side.board:snapshot())
				if side.other.player then
					Remotes.Snapshot:FireClient(side.other.player, packed, { incoming = 0 })
				end
			end
		end
	end

	-- Two defensive players can otherwise sit there forever.
	if self.elapsed > Tuning.SUDDEN_DEATH then
		self.a.board.gravity = math.min(20, self.a.board.gravity * 1.0008)
		self.b.board.gravity = math.min(20, self.b.board.gravity * 1.0008)
		self.suddenTimer += dt
		if self.suddenTimer >= Tuning.SUDDEN_ROW_EVERY then
			self.suddenTimer = 0
			for _, side in ipairs({ self.a, self.b }) do
				local gap = self.rng:NextInteger(1, Tuning.WIDTH)
				side.board:queueGarbage(1, gap, self.elapsed)
				if side.player then
					Remotes.Garbage:FireClient(side.player, { rows = 1, gapCol = gap })
				end
			end
		end
	end

	if self.elapsed >= Tuning.MATCH_CAP then
		local sa, sb = self.a.board.stats.sent, self.b.board.stats.sent
		if sa == sb then
			self:_finish(nil, Enums.Result.Draw, Enums.Result.Timeout)
		else
			self:_finish(sa > sb and self.b or self.a, Enums.Result.Win, Enums.Result.Timeout)
		end
	end
end

-- ── Ending ────────────────────────────────────────────────────────────────

function MatchInstance:playerLeft(player: Player)
	local side = self:sideFor(player)
	if not side or self.finished then return end
	side.alive = false
	side.player = nil
	self:_finish(side, Enums.Result.Win, Enums.Result.Left)
end

function MatchInstance:forfeit(player: Player)
	local side = self:sideFor(player)
	if not side or self.finished then return end
	side.alive = false
	self:_finish(side, Enums.Result.Win, Enums.Result.Forfeit)
end

local function statsOf(side: any)
	local s = side.board.stats
	return {
		lines = s.lines, sent = s.sent, pieces = s.pieces,
		quads = s.quads, tspins = s.tspins, received = s.received,
	}
end

-- `loser` nil means a draw.
function MatchInstance:_finish(loser: any?, _winOutcome: string, reason: string?)
	if self.finished then return end
	self.finished = true
	self.state = Enums.State.Results

	for _, side in ipairs({ self.a, self.b }) do
		if side.player then
			local outcome
			if loser == nil then
				outcome = Enums.Result.Draw
			elseif side == loser then
				outcome = Enums.Result.Loss
			else
				outcome = Enums.Result.Win
			end
			Remotes.Result:FireClient(side.player, {
				outcome = outcome,
				reason = reason,
				stats = statsOf(side),
				opponent = side.other.name,
				-- Nothing to rematch against if the other side walked out.
				canRematch = reason ~= Enums.Result.Left,
			})
		end
	end

	if self.onFinished then
		self.onFinished(self, loser, reason)
	end
end

return MatchInstance
