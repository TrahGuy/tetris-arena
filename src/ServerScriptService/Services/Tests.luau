-- Headless tests for the pure modules.
--
-- These exist because Board is the one piece of this game that is expensive to
-- debug live: a line-clear or garbage bug shows up as "he says he cleared it and
-- I didn't get garbage" three phases later. Everything here runs without a
-- session, so it can be run from the command bar or over MCP in Edit mode.
--
--   require(game.ServerScriptService.Services.Tests).run()

-- Modules are resolved inside run() rather than at require time so a caller can
-- hand in a freshly cloned Shared folder. require() caches per ModuleScript
-- instance and the MCP command thread keeps its own cache, so editing a module
-- and re-running would otherwise silently re-run the stale copy.
local Board, Bag, SRS, Attack, Net, Pieces, Tuning, BotService

local T = {}
local passed, failed, log = 0, 0, {}

local function check(name: string, cond: any, detail: string?)
	if cond then
		passed += 1
	else
		failed += 1
		table.insert(log, ("FAIL  %s%s"):format(name, detail and ("  — " .. detail) or ""))
	end
end

local function eq(name: string, got: any, want: any)
	check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

-- Fill a whole row except the listed columns.
local function fillRow(b, row: number, ...)
	local skip = {}
	for _, c in ipairs({ ... }) do skip[c] = true end
	for col = 1, b.w do
		if not skip[col] then
			b.cells[(row - 1) * b.w + col] = Pieces.GARBAGE
		end
	end
end

local function countFilled(b): number
	local n = 0
	for i = 1, b.w * b.h do
		if b.cells[i] ~= 0 then n += 1 end
	end
	return n
end

function T.bag()
	local a, c = Bag.new(12345), Bag.new(12345)
	local same = true
	for _ = 1, 40 do
		if a:pop() ~= c:pop() then same = false end
	end
	check("bag: same seed gives the same sequence", same)

	local d = Bag.new(999)
	local seen = {}
	for _ = 1, 7 do
		local k = d:pop()
		check("bag: piece id in range", k >= 1 and k <= 7)
		check("bag: no repeat inside a bag", not seen[k])
		seen[k] = true
	end

	local e = Bag.new(4242)
	local peek = e:peek(5)
	eq("bag: peek does not consume", e:pop(), peek[1])

	-- Different seeds must not collapse to the same stream.
	local f, g = Bag.new(1), Bag.new(2)
	local differs = false
	for _ = 1, 14 do
		if f:pop() ~= g:pop() then differs = true end
	end
	check("bag: different seeds differ", differs)

	-- A zero seed is a fixed point for xorshift and would emit only zeroes.
	local z = Bag.new(0)
	check("bag: zero seed still produces valid pieces", z:pop() >= 1)
end

function T.srs()
	local dirs = { "1>2", "2>1", "2>3", "3>2", "3>4", "4>3", "4>1", "1>4" }
	for _, kind in ipairs({ Pieces.T, Pieces.I }) do
		for _, key in ipairs(dirs) do
			local from, to = tonumber(key:sub(1, 1)), tonumber(key:sub(3, 3))
			local k = SRS.kicks(kind, from, to)
			eq("srs: five offsets for " .. Pieces.NAMES[kind] .. " " .. key, #k, 5)
			check("srs: first offset is identity " .. key, k[1][1] == 0 and k[1][2] == 0)
		end
	end
	eq("srs: O never kicks", #SRS.kicks(Pieces.O, 1, 2), 1)
	eq("srs: turn cw wraps", SRS.turn(4, 1), 1)
	eq("srs: turn ccw wraps", SRS.turn(1, -1), 4)

	-- Every shape must have exactly four cells in every state.
	for kind = 1, 7 do
		for rot = 1, 4 do
			eq(("pieces: %s rot %d has 4 cells"):format(Pieces.NAMES[kind], rot),
				#Pieces.SHAPES[kind][rot], 4)
		end
	end
	-- O must not shift when rotated, or it wobbles in the well.
	local o1, o3 = Pieces.SHAPES[Pieces.O][1], Pieces.SHAPES[Pieces.O][3]
	local stable = true
	for i = 1, 4 do
		if o1[i][1] ~= o3[i][1] or o1[i][2] ~= o3[i][2] then stable = false end
	end
	check("pieces: O is identical in every rotation", stable)
end

function T.spawnAndDrop()
	local b = Board.new(7)
	check("board: spawns a piece", b.piece ~= nil)
	check("board: spawns above the visible field", b.piece.y >= Tuning.VISIBLE)
	check("board: starts alive", b.alive)

	local dropped = b:hardDrop()
	check("board: hard drop travels", dropped > 0)
	eq("board: one piece placed", b.stats.pieces, 1)
	eq("board: four cells written", countFilled(b), 4)
	check("board: a new piece spawned", b.piece ~= nil or b.spawnDelay > 0)
end

function T.lineClear()
	local b = Board.new(11)
	fillRow(b, 1, 5, 6)
	fillRow(b, 2, 5, 6)
	eq("clear: setup filled 16 cells", countFilled(b), 16)

	-- O occupies box cells (1,1),(2,1),(1,2),(2,2), so x=3 lands it in columns
	-- 5 and 6, and y=0 puts it on rows 1 and 2.
	b.piece = { kind = Pieces.O, rot = 1, x = 3, y = 0 }
	b:lock()

	eq("clear: two rows cleared", b.stats.lines, 2)
	eq("clear: board is empty afterwards", countFilled(b), 0)
	check("clear: still alive", b.alive)

	local locked
	for _, e in ipairs(b:drain()) do
		if e.kind == "lock" then locked = e.data end
	end
	check("clear: lock event fired", locked ~= nil)
	check("clear: flagged as a perfect clear", locked and locked.info.perfect)
	eq("clear: perfect clear pays out", locked and locked.info.attack, 1 + Attack.PERFECT_CLEAR)
end

function T.quadAndB2B()
	local b = Board.new(13)
	for row = 1, 4 do fillRow(b, row, 10) end
	-- A stray cell high enough to survive both clears. Without it the board ends
	-- up empty, which is a perfect clear worth +10 and swamps what is under test.
	b.cells[(12 - 1) * b.w + 1] = Pieces.GARBAGE
	-- Vertical I in column 10: rot 2 has all cells at box x=2, so x=7.
	b.piece = { kind = Pieces.I, rot = 2, x = 7, y = 1 }
	b:lock()
	eq("quad: four lines", b.stats.lines, 4)
	check("quad: back-to-back armed", b.b2b)

	local first
	for _, e in ipairs(b:drain()) do
		if e.kind == "lock" then first = e.data end
	end
	check("quad: not a perfect clear", first and not first.info.perfect)
	eq("quad: first quad sends 4", first and first.info.attack, 4)

	-- Second quad in a row: same shape again, now with b2b live.
	for row = 1, 4 do fillRow(b, row, 10) end
	b.piece = { kind = Pieces.I, rot = 2, x = 7, y = 1 }
	b.combo = 0 -- isolate the b2b bonus from the combo table
	b:lock()
	local second
	for _, e in ipairs(b:drain()) do
		if e.kind == "lock" then second = e.data end
	end
	eq("quad: back-to-back quad sends 5", second and second.info.attack, 5)
end

function T.garbage()
	local b = Board.new(17)
	fillRow(b, 1) -- a solid row that should ride upward
	b:addGarbage(2, 4)

	eq("garbage: gap column recorded", b.garbageCol, 4)
	eq("garbage: original row pushed to row 3", b:at(1, 3), Pieces.GARBAGE)
	eq("garbage: row 1 is garbage", b:at(1, 1), Pieces.GARBAGE)
	eq("garbage: gap left open on row 1", b:at(4, 1), 0)
	eq("garbage: gap left open on row 2", b:at(4, 2), 0)
	eq("garbage: received counted", b.stats.received, 2)

	-- Charged, not instant: it must not land before the delay elapses.
	local c = Board.new(19)
	c:queueGarbage(3, 2)
	eq("garbage: queued but not applied", c.stats.received, 0)
	eq("garbage: pending reported", Attack.pending(c.incoming), 3)
	c.time = Tuning.GARBAGE_DELAY + 0.01
	c:applyReadyGarbage()
	eq("garbage: lands once due", c.stats.received, 3)

	-- Push-out: a stack that reaches the top of the buffer has nowhere to go.
	local d = Board.new(23)
	for row = 1, d.h do fillRow(d, row, 3) end
	d:addGarbage(1, 5)
	check("garbage: push-out tops the board out", not d.alive)
	eq("garbage: push-out reason", d.topOut, "garbage")
end

function T.topOuts()
	-- Block out: the spawn cells are already occupied.
	local b = Board.new(29)
	for row = 20, 24 do fillRow(b, row) end
	b:spawn(Pieces.T)
	check("topout: block out detected", not b.alive)
	eq("topout: block out reason", b.topOut, "block")

	-- Lock out: the piece comes to rest entirely above the visible field.
	local c = Board.new(31)
	for row = 1, Tuning.VISIBLE + 1 do fillRow(c, row) end
	c.piece = { kind = Pieces.O, rot = 1, x = 3, y = Tuning.VISIBLE + 1 }
	c:lock()
	check("topout: lock out detected", not c.alive)
	eq("topout: lock out reason", c.topOut, "lock")
end

function T.attack()
	eq("attack: single sends nothing", Attack.compute(1, nil, false, false, 1).attack, 0)
	eq("attack: double sends 1", Attack.compute(2, nil, false, false, 1).attack, 1)
	eq("attack: triple sends 2", Attack.compute(3, nil, false, false, 1).attack, 2)
	eq("attack: quad sends 4", Attack.compute(4, nil, false, false, 1).attack, 4)
	eq("attack: b2b quad sends 5", Attack.compute(4, nil, false, true, 1).attack, 5)
	eq("attack: combo of 1 adds nothing", Attack.compute(2, nil, false, false, 1).attack, 1)
	eq("attack: combo of 5 adds 1", Attack.compute(2, nil, false, false, 5).attack, 2)
	eq("attack: no clear sends nothing", Attack.compute(0, nil, false, true, 9).attack, 0)
	check("attack: quad keeps b2b alive", Attack.isB2BClear(4, nil))
	check("attack: a triple breaks b2b", not Attack.isB2BClear(3, nil))
	check("attack: a t-spin keeps b2b alive", Attack.isB2BClear(1, "full"))

	local q = { { rows = 3, at = 0 }, { rows = 2, at = 0 } }
	eq("cancel: 4 against 5 sends nothing", Attack.cancel(q, 4), 0)
	eq("cancel: 1 row survives in the queue", Attack.pending(q), 1)
	eq("cancel: 10 against 1 sends 9", Attack.cancel(q, 10), 9)
	eq("cancel: queue drained", #q, 0)
end

function T.net()
	local cells = table.create(200, 0)
	for i = 1, 200 do cells[i] = (i * 7) % 9 end
	local round = Net.unpackBoard(Net.packBoard(cells), 200)
	local same = true
	for i = 1, 200 do
		if round[i] ~= cells[i] then same = false end
	end
	check("net: board survives a pack/unpack round trip", same)
	eq("net: 200 cells pack into 100 bytes", buffer.len(Net.packBoard(cells)), 100)
end

function T.tspin()
	-- Detection only: whether SRS can actually reach the slot is covered above.
	-- Three corners filled plus a rotation as the last action is a T-spin.
	local b = Board.new(37)
	b.piece = { kind = Pieces.T, rot = 1, x = 3, y = 2 }
	b.lastKick = true
	b.cells[(2 - 1) * b.w + 4] = Pieces.GARBAGE -- box (0,0)
	b.cells[(2 - 1) * b.w + 6] = Pieces.GARBAGE -- box (2,0)
	b.cells[(4 - 1) * b.w + 4] = Pieces.GARBAGE -- box (0,2)
	check("tspin: three corners plus a kick detects", b:detectTSpin() ~= nil)

	b.lastKick = false
	check("tspin: a plain drop is not a spin", b:detectTSpin() == nil)

	b.lastKick = true
	b.cells[(4 - 1) * b.w + 4] = 0
	check("tspin: two corners is not a spin", b:detectTSpin() == nil)
end

function T.determinism()
	-- The whole networking model rests on this: same seed and same inputs must
	-- give byte-identical boards, or client prediction drifts from the server.
	local function play(seed: number)
		local b = Board.new(seed)
		local script_ = { -1, -1, 1, 0, 1, -1, 0, 1, 1, -1 }
		for i = 1, 40 do
			b:move(script_[(i % #script_) + 1])
			if i % 3 == 0 then b:rotate(1) end
			b:hardDrop()
			b:step(Tuning.CLEAR_DELAY + 0.02)
		end
		return b
	end
	local a, c = play(555), play(555)
	local same = #a.cells == #c.cells
	if same then
		for i = 1, #a.cells do
			if a.cells[i] ~= c.cells[i] then same = false break end
		end
	end
	check("determinism: identical seed and inputs give identical boards", same)
	eq("determinism: same piece count", a.stats.pieces, c.stats.pieces)
	eq("determinism: same lines", a.stats.lines, c.stats.lines)

	local d = play(556)
	local differs = false
	for i = 1, #a.cells do
		if a.cells[i] ~= d.cells[i] then differs = true break end
	end
	check("determinism: a different seed diverges", differs)
end

function T.gravityAndLock()
	local b = Board.new(41)
	b.gravity = 1000 -- fall to the floor almost immediately
	for _ = 1, 20 do b:step(Tuning.TICK) end
	check("gravity: piece reaches the floor", b.grounded)

	local before = b.stats.pieces
	for _ = 1, math.ceil(Tuning.LOCK_DELAY / Tuning.TICK) + 4 do b:step(Tuning.TICK) end
	check("lock delay: locks once the delay elapses", b.stats.pieces > before)

	-- The reset cap is what stops a piece being spun on the floor forever.
	local c = Board.new(43)
	c.gravity = 1000
	for _ = 1, 20 do c:step(Tuning.TICK) end
	local spins = 0
	for _ = 1, 400 do
		c:rotate(1)
		c:step(Tuning.TICK)
		if c.stats.pieces > 0 then break end
		spins += 1
	end
	check("lock delay: reset cap forces a lock", c.stats.pieces > 0,
		("survived %d spins"):format(spins))
end

function T.holdAndReach()
	local b = Board.new(47)
	local first = b.piece.kind
	check("hold: first hold succeeds", b:swapHold())
	eq("hold: piece went to hold", b.hold, first)
	check("hold: second hold in a row is refused", not b:swapHold())
	b:hardDrop()
	b:step(Tuning.ARE + 0.01)
	check("hold: allowed again after a lock", b:swapHold())

	local c = Board.new(53)
	local p = c.piece
	local restY = c:ghostY()
	check("ghost: ghost sits at or below the piece", restY <= p.y)
	check("reachable: a hard-drop resting place is reachable",
		c:reachable(p.kind, p.rot, p.x, restY))
	check("reachable: floating in mid-air is not a resting place -- but is reachable",
		c:reachable(p.kind, p.rot, p.x, p.y))
	check("reachable: outside the wall is rejected",
		not c:reachable(p.kind, p.rot, 99, restY))
end

-- reachable() runs on the server for every lock the client reports, so it has
-- to stay cheap on a realistically messy board, not just an empty one.
function T.reachCost()
	local b = Board.new(61)
	for row = 1, 12 do
		fillRow(b, row, (row % 7) + 1, ((row * 3) % 9) + 1)
	end
	local p = b.piece
	local start = os.clock()
	local hits = 0
	for _ = 1, 200 do
		if b:reachable(p.kind, p.rot, p.x, b:ghostY()) then hits += 1 end
	end
	local per = (os.clock() - start) / 200
	eq("reach: a real resting place is always reachable", hits, 200)
	check("reach: under 3ms per call on a messy board", per < 0.003,
		("%.3f ms"):format(per * 1000))
end

-- Two bots, garbage routed between them, run to a conclusion. This is the
-- cheapest test that exercises board, attack, cancelling and garbage together,
-- and the only one that catches a match which never ends.
function T.bots()
	local a = BotService.new(101, "neon")
	local c = BotService.new(202, "neon")
	local dt, t = 1 / 60, 0
	local routed = 0

	while t < 240 and a.board.alive and c.board.alive do
		t += dt
		a.board.time, c.board.time = t, t
		a:update(dt)
		c:update(dt)
		for _, pair in ipairs({ { a, c }, { c, a } }) do
			for _, e in ipairs(pair[1].board:drain()) do
				if e.kind == "lock" and e.data.send > 0 then
					pair[2].board:queueGarbage(e.data.send, nil, t + Tuning.GARBAGE_DELAY)
					routed += e.data.send
				end
			end
		end
	end

	check("bots: the match reached a conclusion", not (a.board.alive and c.board.alive),
		("ran %ds with both alive"):format(math.floor(t)))
	-- Deliberately a high bar. A bot that self-destructs still "reaches a
	-- conclusion", which is how a stale-plan bug slipped past a weaker
	-- assertion: it topped itself out in well under a minute against nobody.
	local worst = math.min(a.board.stats.pieces, c.board.stats.pieces)
	check("bots: neither bot collapsed early", worst > 70, ("worst survived %d pieces"):format(worst))
	check("bots: both bots cleared lines",
		a.board.stats.lines > 0 and c.board.stats.lines > 0,
		("%d / %d"):format(a.board.stats.lines, c.board.stats.lines))
	check("bots: garbage was routed between them", routed > 0, tostring(routed))

	-- A broken evaluator shows up as a board full of covered holes.
	local survivor = a.board.alive and a.board or c.board
	local holes = 0
	for col = 1, survivor.w do
		local seen = false
		for row = survivor.h, 1, -1 do
			local v = survivor.cells[(row - 1) * survivor.w + col]
			if v ~= 0 then
				seen = true
			elseif seen then
				holes += 1
			end
		end
	end
	check("bots: the survivor's stack is not riddled with holes", holes < 40,
		("%d holes"):format(holes))
end

function T.run(root: Instance?, services: Instance?)
	root = root or game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	services = services or game:GetService("ServerScriptService"):WaitForChild("Services")
	Board = require((root :: any).Board)
	Bag = require((root :: any).Bag)
	SRS = require((root :: any).SRS)
	Attack = require((root :: any).Attack)
	Net = require((root :: any).Net)
	Pieces = require((root :: any).Pieces)
	Tuning = require((root :: any).Tuning)
	BotService = require((services :: any).BotService)

	passed, failed, log = 0, 0, {}
	local order = { "bag", "srs", "spawnAndDrop", "lineClear", "quadAndB2B", "garbage",
		"topOuts", "attack", "net", "tspin", "determinism", "gravityAndLock", "holdAndReach",
		"reachCost", "bots" }
	for _, name in ipairs(order) do
		local ok, err = pcall(T[name])
		if not ok then
			failed += 1
			table.insert(log, ("ERROR %s — %s"):format(name, tostring(err)))
		end
	end
	local head = ("%d passed, %d failed"):format(passed, failed)
	if failed == 0 then
		return head .. "  — all green"
	end
	return head .. "\n" .. table.concat(log, "\n")
end

return T
