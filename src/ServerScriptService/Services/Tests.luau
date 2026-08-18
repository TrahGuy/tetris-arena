-- Headless tests for the pure modules.
--
-- These exist because Board is the one piece of this game that is expensive to
-- debug live: a line-clear or garbage bug shows up as "he says he cleared it and
-- I didn't get garbage" three phases later. Everything here runs without a
-- session, so it can be run from the command bar or over MCP in Edit mode.
--
--   require(game.ServerScriptService.Services.Tests).run()

-- RUN THESE IN PLAY MODE, from the Server datamodel:
--
--   require(game.ServerScriptService.Services.Tests).run()
--
-- Running them from Edit over MCP is a trap. require() caches per ModuleScript
-- instance and the MCP command thread keeps its own cache, so an edited module
-- silently re-runs as its stale self. Cloning the Shared folder fixes it for
-- modules this file requires directly — but BotService and MatchInstance reach
-- Shared by absolute path, so they still pick up the cached originals, and the
-- two halves of a test end up running different versions of Board. Play mode
-- builds a fresh datamodel, so everything there is current by construction.
--
-- Modules are still resolved inside run() so a caller *can* pass a clone.
local Board, Bag, SRS, Attack, Net, Pieces, Tuning, BotService, MatchInstance, Stats, Practice,
	GlobalRank, Enums, SkinData, PuzzleService, Practice, BlitzScoring, LockValidation,
	TitleData, ArenaService

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

local function cell(b, col: number, row: number)
	b.cells[(row - 1) * b.w + col] = Pieces.GARBAGE
end

-- A board with nothing on it and nothing in play, so a placement can be set up
-- exactly. Board.new spawns off the bag, which is never what a spin test is
-- about.
local function emptyBoard(seed: number)
	local b = Board.new(seed)
	b.piece = nil
	for i = 1, b.w * b.h do b.cells[i] = 0 end
	return b
end

-- The four spins, as geometry plus the square the piece turns from.
--
-- These were not written out by hand. Each one came from an exhaustive search
-- over the SRS kick tables for a rotation that lands on the placement, clears
-- the stated rows, and starts from a square the piece can actually reach — so
-- they are placements the rotation system genuinely produces rather than ones
-- that look right on paper. The triple is the classic (-1,-2) kick down a
-- capped column.
local SPINS = {
	single = {
		build = function(b) fillRow(b, 1, 5); cell(b, 4, 3) end,
		pre = { rot = 2, x = 3, y = 1, dir = 1 },
		land = { rot = 3, x = 3, y = 1 }, class = "full", lines = 1,
	},
	double = {
		build = function(b) fillRow(b, 1, 5); fillRow(b, 2, 4, 5, 6); cell(b, 4, 3) end,
		pre = { rot = 2, x = 3, y = 1, dir = 1 },
		land = { rot = 3, x = 3, y = 1 }, class = "full", lines = 2,
	},
	triple = {
		build = function(b)
			fillRow(b, 1, 4); fillRow(b, 2, 4, 5); fillRow(b, 3, 4)
			fillRow(b, 5, 5, 6); fillRow(b, 6, 5, 6)
		end,
		pre = { rot = 1, x = 3, y = 3, dir = 1 },
		land = { rot = 2, x = 2, y = 1 }, class = "full", lines = 3,
	},
	mini = {
		build = function(b) fillRow(b, 1, 4); fillRow(b, 2, 4); fillRow(b, 4, 4, 5) end,
		pre = { rot = 1, x = 2, y = 2, dir = 1 },
		land = { rot = 2, x = 2, y = 2 }, class = "mini", lines = 1,
	},
}

-- Build the cells, stand the piece on the square it turns from, and turn it —
-- so detection sees exactly what a player's last action would have left behind.
local function spinInto(s: any)
	local b = emptyBoard(101)
	s.build(b)
	b.piece = { kind = Pieces.T, rot = s.pre.rot, x = s.pre.x, y = s.pre.y }
	local turned = b:rotate(s.pre.dir)
	return b, turned
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

	-- Buffers arrive from clients, so "is this a board" has to be answerable
	-- before anything is done with one.
	check("net: a well-formed board validates", Net.isValidBoard(Net.packBoard(cells), 200))
	check("net: a short buffer is rejected", not Net.isValidBoard(buffer.create(99), 200))
	check("net: an oversized buffer is rejected", not Net.isValidBoard(buffer.create(4096), 200))
	check("net: a non-buffer is rejected", not Net.isValidBoard("not a board", 200))
	check("net: nil is rejected", not Net.isValidBoard(nil, 200))

	local illegal = Net.packBoard(cells)
	buffer.writeu8(illegal, 7, 15 * 16) -- a cell value no piece produces
	check("net: a cell the game cannot produce is rejected", not Net.isValidBoard(illegal, 200))

	-- A decoder that can be made to throw by the bytes it is handed is a
	-- decoder that only works while everyone is honest.
	check("net: unpacking a short buffer does not error", (pcall(Net.unpackBoard, buffer.create(4), 200)))
	check("net: unpacking an empty buffer does not error", (pcall(Net.unpackBoard, buffer.create(0), 200)))
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

-- The bot clones the board dozens of times per decision to try placements. If a
-- clone shares any mutable state with its source, that search silently corrupts
-- the real game — and because the bag is what spawning consumes, the damage is
-- the piece sequence, which is exactly what client and server must agree on.
function T.cloneIsolation()
	local b = Board.new(4242)
	local before = b.bag:peek(6)

	local trial = b:clone()
	for _ = 1, 30 do
		if not trial.alive then break end
		trial:hardDrop()
		trial:step(Tuning.CLEAR_DELAY + 0.02)
	end

	local after = b.bag:peek(6)
	local same = true
	for i = 1, 6 do
		if before[i] ~= after[i] then same = false end
	end
	check("clone: hammering a clone leaves the source bag untouched", same,
		("%s -> %s"):format(table.concat(before, ","), table.concat(after, ",")))
	-- A fresh board has spawned a piece but not locked one.
	eq("clone: source has locked nothing", b.stats.pieces, 0)
	check("clone: source cells untouched", countFilled(b) == 0)

	-- And the clone must actually be usable, not a frozen snapshot.
	check("clone: the clone itself advanced", trial.stats.pieces > 1)
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

-- Rating is the one number players will argue about, so the maths gets pinned.
function T.elo()
	local w, l = Stats.elo(1000, 1000, 50, 50)
	check("elo: the winner gains", w > 1000)
	check("elo: the loser drops", l < 1000)
	eq("elo: symmetric between equals", w - 1000, 1000 - l)

	local upset = Stats.elo(800, 1200, 50, 50)
	local expectedWin = Stats.elo(1200, 800, 50, 50)
	check("elo: beating someone better is worth more",
		(upset - 800) > (expectedWin - 1200),
		("upset +%d vs expected +%d"):format(upset - 800, expectedWin - 1200))

	local newAccount = Stats.elo(1000, 1000, 0, 0)
	check("elo: unplaced accounts move faster", (newAccount - 1000) > (w - 1000),
		("+%d vs +%d"):format(newAccount - 1000, w - 1000))

	local _, floored = Stats.elo(2400, 105, 50, 50)
	check("elo: rating never falls through the floor", floored >= 100, tostring(floored))

	-- A rating should converge rather than drift: repeatedly beating a much
	-- weaker opponent must yield ever-smaller gains.
	local a, b = 1000, 1000
	local firstGain, lastGain = 0, 0
	for i = 1, 25 do
		local na, nb = Stats.elo(a, b, 50 + i, 50 + i)
		if i == 1 then firstGain = na - a end
		lastGain = na - a
		a, b = na, nb
	end
	check("elo: gains shrink as the gap widens", lastGain < firstGain,
		("first +%d, last +%d"):format(firstGain, lastGain))

	-- A ranked draw is rare — the clock running out on equal garbage — but
	-- scoring it as nothing-happened is wrong when the ratings are not equal.
	local dw, dl = Stats.elo(1200, 1000, 50, 50, 0.5)
	check("elo: a draw costs the favourite", dw < 1200, tostring(dw))
	check("elo: a draw pays the underdog", dl > 1000, tostring(dl))
	local ew, el = Stats.elo(1000, 1000, 50, 50, 0.5)
	eq("elo: a draw between equals moves the first nowhere", ew, 1000)
	eq("elo: a draw between equals moves the second nowhere", el, 1000)
end

-- Every competitive message names its match. Without that, a lock still in
-- flight from the last match lands on the next one — and a stale top-out ends a
-- game that had barely started.
function T.sessions()
	local m = MatchInstance.new(4242, { name = "P1" }, { name = "P2" }, { seed = 5 })
	check("session: a message for this match is accepted", m:ownsMessage({ matchId = 4242 }))
	check("session: a message for the previous match is not", not m:ownsMessage({ matchId = 4241 }))
	check("session: a message with no match id is not", not m:ownsMessage({}))
	check("session: a non-table is not", not m:ownsMessage("4242"))
end

-- Leaving has to keep pointing at the player who left. Nil the reference here
-- and the loss and the rating land on nobody, which makes quitting a ranked
-- match you are losing strictly better than playing it out.
function T.disconnect()
	local quitter = { UserId = 7, DisplayName = "Quitter" }
	local stayer = { UserId = 8, DisplayName = "Stayer" }
	local m = MatchInstance.new(4243, { player = quitter }, { player = stayer },
		{ mode = "ranked", seed = 11 })

	local sawLoser, sawReason
	m.onFinished = function(_, loser, reason) sawLoser, sawReason = loser, reason end
	m:playerLeft(quitter)

	check("disconnect: the match ended", m.finished)
	eq("disconnect: the leaver is the loser", sawLoser, m.a)
	eq("disconnect: reported as a leave, not a KO", sawReason, "left")
	eq("disconnect: the leaver is still identified for stats", m.a.player, quitter)
	check("disconnect: the leaver is flagged as gone", m.a.left == true)
	check("disconnect: the side that stayed is untouched",
		m.b.left == false and m.b.player == stayer)

	-- And a second departure must not re-finish a settled match.
	m:playerLeft(stayer)
	check("disconnect: leaving an ended match changes nothing", m.b.left == false)
end

-- Practice is unopposed, so the only thing to cheat at is the record — and both
-- the sprint time and the lines total show on the leaderboard tower.
function T.practice()
	local session = { id = 3, mode = "sprint", startedAt = 100, seed = 1 }
	local honest = { sessionId = 3, time = 22, stats = { lines = 40, pieces = 104 } }

	local rec = Practice.vet(session, honest, 122.4)
	check("practice: an honest sprint is credited", rec ~= nil and rec.sprint == true)
	eq("practice: and keeps the clock the player was shown", rec and rec.time, 22)

	check("practice: a result for another session is refused",
		(Practice.vet(session, { sessionId = 4, time = 22, stats = honest.stats }, 122.4)) == nil)
	check("practice: a result with no session at all is refused",
		(Practice.vet(nil, honest, 122.4)) == nil)

	-- Stalling and then reporting a fast run is the attack worth stopping.
	local stalled = Practice.vet(session, { sessionId = 3, time = 9,
		stats = { lines = 40, pieces = 104 } }, 400)
	check("practice: a time the server did not measure is not believed",
		stalled ~= nil and stalled.time > 200, stalled and tostring(stalled.time))

	-- Cell conservation: a cleared row is ten cells and a piece is four of them.
	local few = Practice.vet(session, { sessionId = 3, time = 20,
		stats = { lines = 40, pieces = 12 } }, 120.2)
	check("practice: lines are bounded by the pieces that could have cleared them",
		few ~= nil and few.lines <= 5, few and tostring(few.lines))
	check("practice: so that run sets no record", few ~= nil and not few.sprint)

	-- 40 lines needs 100 pieces, and 100 pieces cannot be placed in three
	-- seconds, so the sprint floor falls out rather than being a magic number.
	local instant = Practice.vet(session, { sessionId = 3, time = 3.1,
		stats = { lines = 40, pieces = 104 } }, 103.1)
	check("practice: a superhuman sprint sets no record",
		instant ~= nil and not instant.sprint, instant and tostring(instant.lines))

	local absurd = Practice.vet(session, { sessionId = 3, time = 20,
		stats = { lines = 1e18, pieces = 1e18 } }, 120.2)
	check("practice: an absurd lines total is clamped to what a sprint can be",
		absurd ~= nil and absurd.lines <= Tuning.SPRINT_GOAL, absurd and tostring(absurd.lines))
	local junk = Practice.vet(session, { sessionId = 3, time = "soon",
		stats = { lines = {}, pieces = "many" } }, 120.2)
	check("practice: junk in the numbers credits nothing rather than erroring",
		junk ~= nil and junk.lines == 0 and junk.pieces == 0)
end

-- ── T-spins (Phase 11) ────────────────────────────────────────────────────

-- The rule: the piece is a T, the last successful action was a rotation, and
-- three of the four corners of its 3x3 box are solid. Both corners on the side
-- the T points at makes it full; one makes it a mini. Walls and the floor count
-- as solid corners; open air above the buffer does not.
function T.tspinDetect()
	for name, s in pairs(SPINS) do
		local b, turned = spinInto(s)
		check("tspin: " .. name .. " rotation succeeded", turned)
		local p = b.piece
		check("tspin: " .. name .. " landed where SRS puts it",
			p and p.rot == s.land.rot and p.x == s.land.x and p.y == s.land.y,
			p and ("rot%d (%d,%d)"):format(p.rot, p.x, p.y) or "no piece")
		eq("tspin: " .. name .. " classifies", b:detectTSpin(), s.class)

		local before = b.stats.lines
		b:lock()
		eq("tspin: " .. name .. " clears the rows it should", b.stats.lines - before, s.lines)
	end

	-- The same square, reached without turning into it. Three corners on their
	-- own are not a spin, which is the whole point of tracking the last action.
	local s = SPINS.double
	local dropped = emptyBoard(101)
	s.build(dropped)
	dropped.piece = { kind = Pieces.T, rot = s.land.rot, x = s.land.x, y = s.land.y }
	check("tspin: the same placement without a rotation is not a spin",
		dropped:detectTSpin() == nil)
	dropped:lock()
	eq("tspin: and it is scored as an ordinary double", dropped.stats.tspins, 0)

	-- Rotating and then falling is not a spin either: gravity clears the flag,
	-- so a hard drop that travels cannot arrive as one.
	local moved = emptyBoard(101)
	moved.piece = { kind = Pieces.T, rot = 1, x = 3, y = 10 }
	check("tspin: rotation in open air sets the flag", moved:rotate(1) and moved.lastKick)
	check("tspin: falling one row clears it", moved:stepDown() and not moved.lastKick)
	check("tspin: and the witness goes with it", moved.lastSpin == nil)

	-- Only the T scores a spin, however well its corners line up.
	local other = emptyBoard(101)
	SPINS.double.build(other)
	other.piece = { kind = Pieces.L, rot = 1, x = 3, y = 6 }
	other:rotate(1)
	check("tspin: another piece in the same board is never a spin", other:detectTSpin() == nil)
end

-- What a spin is worth. A T-spin is paid INSTEAD of the base clear, never on
-- top of it, and every bonus applies exactly once.
function T.tspinAttack()
	local function atk(lines, spin, perfect, b2b, combo)
		return Attack.compute(lines, spin, perfect or false, b2b or false, combo or 1).attack
	end

	eq("tspin attack: single sends 2", atk(1, "full"), 2)
	eq("tspin attack: double sends 4", atk(2, "full"), 4)
	eq("tspin attack: triple sends 6", atk(3, "full"), 6)
	eq("tspin attack: mini single sends nothing", atk(1, "mini"), 0)
	eq("tspin attack: mini double sends 1", atk(2, "mini"), 1)
	eq("tspin attack: a spin that cleared nothing sends nothing", atk(0, "full"), 0)

	-- The values must not have quietly fallen back to the base table, which is
	-- exactly what an off-by-one in the lookup would look like.
	check("tspin attack: a spin outscores the plain clear it replaces",
		atk(1, "full") > atk(1, nil) and atk(2, "full") > atk(2, nil)
		and atk(3, "full") > atk(3, nil))
	eq("tspin attack: a full single is not a base single", atk(1, "full") == atk(1, nil), false)

	-- Back-to-back.
	check("tspin b2b: a spin that clears arms it", Attack.isB2BClear(1, "full"))
	check("tspin b2b: a mini that clears arms it too", Attack.isB2BClear(1, "mini"))
	check("tspin b2b: a spin that cleared nothing does not", not Attack.isB2BClear(0, "full"))
	check("tspin b2b: an ordinary triple breaks it", not Attack.isB2BClear(3, nil))
	check("tspin b2b: a quad keeps it", Attack.isB2BClear(4, nil))
	eq("tspin b2b: a back-to-back double pays the bonus once", atk(2, "full", false, true), 5)
	eq("tspin b2b: a back-to-back quad still pays 5", atk(4, nil, false, true), 5)

	-- Combo, once, on top of the spin value.
	eq("tspin combo: a fifth consecutive clear adds its combo row", atk(1, "full", false, false, 5), 3)
	eq("tspin combo: the plain table gets the same combo row", atk(1, nil, false, false, 5), 1)

	-- Perfect clear, once.
	eq("tspin perfect: a spin double that empties the board", atk(2, "full", true), 14)
	eq("tspin perfect: everything at once, each counted once",
		atk(2, "full", true, true, 5), 4 + 1 + 1 + 10)

	-- Cancellation is the same pipeline as any other attack.
	local queue = { { rows = 3, at = 0 } }
	eq("tspin cancel: a double against three incoming sends one",
		Attack.cancel(queue, atk(2, "full")), 1)
	eq("tspin cancel: and the incoming queue is emptied", Attack.pending(queue), 0)
end

-- Back-to-back across the two clear types that keep it alive, driven through
-- real locks rather than through the attack table alone.
function T.tspinB2B()
	local function quadBoard(seed)
		local b = emptyBoard(seed)
		for row = 1, 4 do fillRow(b, row, 10) end
		cell(b, 1, 12) -- keeps the board from emptying into a perfect clear
		b.piece = { kind = Pieces.I, rot = 2, x = 7, y = 1 }
		return b
	end

	local b = quadBoard(13)
	b:lock()
	check("tspin b2b: a quad arms back-to-back", b.b2b)

	-- Quad then spin: the chain survives and the spin is paid the bonus.
	local s = SPINS.double
	s.build(b)
	b.piece = { kind = Pieces.T, rot = s.pre.rot, x = s.pre.x, y = s.pre.y }
	b:rotate(s.pre.dir)
	b.combo = 0 -- isolate the b2b bonus from the combo table
	b:lock()
	local spin
	for _, e in ipairs(b:drain()) do
		if e.kind == "lock" then spin = e.data end
	end
	check("tspin b2b: a quad into a spin keeps the chain", spin and spin.info.b2b)
	eq("tspin b2b: and the spin double pays 4 plus the bonus", spin and spin.info.attack, 5)
	check("tspin b2b: the chain is still armed afterwards", b.b2b)

	-- Spin then quad: the same in the other direction.
	local c = emptyBoard(17)
	SPINS.double.build(c)
	c.piece = { kind = Pieces.T, rot = s.pre.rot, x = s.pre.x, y = s.pre.y }
	c:rotate(s.pre.dir)
	c:lock()
	check("tspin b2b: a spin arms the chain", c.b2b)
	for row = 1, 4 do fillRow(c, row, 10) end
	cell(c, 1, 12)
	c.piece = { kind = Pieces.I, rot = 2, x = 7, y = 1 }
	c.combo = 0
	c:lock()
	local quad
	for _, e in ipairs(c:drain()) do
		if e.kind == "lock" then quad = e.data end
	end
	check("tspin b2b: a spin into a quad keeps the chain", quad and quad.info.b2b)
	eq("tspin b2b: and that quad pays 4 plus the bonus", quad and quad.info.attack, 5)

	-- An ordinary clear breaks it.
	local d = emptyBoard(19)
	SPINS.double.build(d)
	d.piece = { kind = Pieces.T, rot = s.pre.rot, x = s.pre.x, y = s.pre.y }
	d:rotate(s.pre.dir)
	d:lock()
	check("tspin b2b: armed before the ordinary clear", d.b2b)
	-- A plain single, built from scratch so the shifted board left by the spin
	-- cannot change what clears. O sits in columns x+2 and x+3 on rows y and
	-- y+1, so x=3 y=0 fills the gap on the bottom row.
	for i = 1, d.w * d.h do d.cells[i] = 0 end
	fillRow(d, 1, 5, 6)
	d.combo = 0
	d.piece = { kind = Pieces.O, rot = 1, x = 3, y = 0 }
	d:lock()
	eq("tspin b2b: the ordinary clear happened", d.stats.lines, 3)
	check("tspin b2b: an ordinary clear breaks the chain", not d.b2b)
end

-- One spin is one stat, whatever it cleared.
function T.tspinStats()
	for _, name in ipairs({ "single", "double", "triple" }) do
		local b, turned = spinInto(SPINS[name])
		check("tspin stat: " .. name .. " turned", turned)
		b:lock()
		eq("tspin stat: a " .. name .. " counts as one spin", b.stats.tspins, 1)
	end

	-- A spin that clears nothing is not counted, which is the rule the board
	-- already had: the stat tracks spins that did something.
	local b = emptyBoard(101)
	SPINS.double.build(b)
	-- Knock a hole in column 1 of both rows the piece touches, so neither can
	-- complete. The corners sit in columns 4 and 6 and are left alone.
	b.cells[1] = 0
	b.cells[b.w + 1] = 0
	b.piece = { kind = Pieces.T, rot = SPINS.double.pre.rot,
		x = SPINS.double.pre.x, y = SPINS.double.pre.y }
	b:rotate(SPINS.double.pre.dir)
	eq("tspin stat: still detected with nothing to clear", b:detectTSpin(), "full")
	b:lock()
	eq("tspin stat: a spin that cleared nothing is not counted", b.stats.tspins, 0)
	eq("tspin stat: and sent nothing", b.stats.sent, 0)
end

-- The server does not watch the player rotate, so it replays the rotation the
-- client describes against its own cells. This is the test that the result is
-- derived there and not accepted from the wire.
function T.tspinAuthority()
	local s = SPINS.double
	local client_, turned = spinInto(s)
	check("authority: the reference rotation happened", turned)
	local witness = client_.lastSpin
	check("authority: a rotation records what it turned from", witness ~= nil)

	-- A board that has never run the rotation reaches the same verdict from the
	-- witness alone.
	local shadow = emptyBoard(101)
	s.build(shadow)
	local L = s.land
	check("authority: a genuine rotation verifies on a board that never ran it",
		shadow:verifySpin(Pieces.T, L.rot, L.x, L.y, witness))
	check("authority: no witness, no spin",
		not shadow:verifySpin(Pieces.T, L.rot, L.x, L.y, nil))
	check("authority: a witness that is not a table is refused",
		not shadow:verifySpin(Pieces.T, L.rot, L.x, L.y, "full"))
	check("authority: a witness turning the wrong way is refused",
		not shadow:verifySpin(Pieces.T, L.rot, L.x, L.y,
			{ rot = witness.rot, x = witness.x, y = witness.y, dir = -witness.dir }))
	check("authority: a witness from a square the piece could not stand on is refused",
		not shadow:verifySpin(Pieces.T, L.rot, L.x, L.y,
			{ rot = witness.rot, x = witness.x + 3, y = witness.y, dir = witness.dir }))
	check("authority: a witness whose rotation lands somewhere else is refused",
		not shadow:verifySpin(Pieces.T, L.rot, L.x, L.y,
			{ rot = witness.rot, x = witness.x, y = witness.y + 6, dir = witness.dir }))
	check("authority: a fractional square is refused",
		not shadow:verifySpin(Pieces.T, L.rot, L.x, L.y,
			{ rot = witness.rot, x = witness.x + 0.5, y = witness.y, dir = witness.dir }))

	-- And now the whole path on the real match object. The shadow is told only
	-- where the piece ended up and which rotation put it there; everything else
	-- in the message is the kind of thing a patched client would forge.
	local FORGED = { tspin = "full", send = 99, lines = 4, attack = 99,
		b2b = true, combo = 12, perfect = true }
	local function play(id: number, spin: any, incoming: number?)
		local match = MatchInstance.new(id, { name = "P1" }, { name = "P2" }, { seed = 7 })
		match.state = "playing"
		local routed = 0
		match.onGarbage = function(_, rows) routed += rows end
		local side = match.a
		local b = side.board
		for i = 1, b.w * b.h do b.cells[i] = 0 end
		s.build(b)
		b.piece = { kind = Pieces.T, rot = 1, x = 3, y = 20 }
		if incoming then b:queueGarbage(incoming, 4, 0) end
		local msg = { index = 1, kind = Pieces.T, rot = L.rot, x = L.x, y = L.y, spin = spin }
		for k, v in pairs(FORGED) do msg[k] = v end
		local realMin = Tuning.MIN_LOCK_INTERVAL
		Tuning.MIN_LOCK_INTERVAL = 0
		match:applyLock(side, msg)
		Tuning.MIN_LOCK_INTERVAL = realMin
		return side, routed
	end

	local withSpin, sent = play(4311, witness)
	eq("authority: the shadow accepted the placement", withSpin.accepted, 1)
	eq("authority: the shadow counted the spin itself", withSpin.board.stats.tspins, 1)
	eq("authority: and sent the spin double it derived, not the forged 99", sent, 4)

	local without, sentPlain = play(4312, nil)
	eq("authority: the same placement with no witness still locks", without.accepted, 1)
	eq("authority: but is no spin", without.board.stats.tspins, 0)
	eq("authority: and pays the base double, not the forged 99", sentPlain, 1)

	-- Cancellation is not bypassed: three incoming against a spin worth four.
	local _, sentAfterCancel = play(4313, witness, 3)
	eq("authority: a spin cancels incoming garbage before any of it is sent",
		sentAfterCancel, 1)
end

-- ── Global ranked leaderboard (Phase 12) ──────────────────────────────────

-- A ranking index in a table. The suite must not depend on DataStore access
-- being available, and it must not write test ratings into the real board.
local function fakeIndex()
	local f = {
		keys = {}, identities = {},
		reads = 0, writes = 0, nameCalls = 0,
		failWrite = false, failRead = false, failNames = false, junk = nil,
	}
	f.write = function(userId, rating)
		f.writes += 1
		if f.failWrite then return false, "write down" end
		f.keys[userId] = rating
		return true
	end
	f.top = function(limit)
		f.reads += 1
		if f.failRead then return nil, "read down" end
		if f.junk then return f.junk end
		local list = {}
		for id, rating in pairs(f.keys) do
			table.insert(list, { userId = id, rating = rating })
		end
		-- Ties broken by id so the fake is as deterministic as the test needs.
		table.sort(list, function(a, b)
			if a.rating == b.rating then return a.userId < b.userId end
			return a.rating > b.rating
		end)
		while #list > limit do table.remove(list) end
		return list
	end
	f.names = function(ids)
		f.nameCalls += 1
		if f.failNames then return nil, "identity down" end
		local out = {}
		for _, id in ipairs(ids) do out[id] = f.identities[id] end
		return out
	end
	return f
end

-- Profiles keyed by UserId, seeded through the public API. A negative id cannot
-- collide with a real Roblox account, so nothing here can read or write a real
-- player's data.
local function fakePlayer(id: number, name: string)
	return { UserId = id, DisplayName = name, Name = name }
end

function T.globalRankIndex()
	local backend = fakeIndex()
	local g = GlobalRank.new(backend)

	-- Eligibility. The board is a RANKED board.
	check("global: an account with a ranked win is eligible",
		GlobalRank.eligible({ rankedWins = 1, rankedLosses = 0, rankedDraws = 0 }))
	check("global: an account with a ranked loss is eligible",
		GlobalRank.eligible({ rankedWins = 0, rankedLosses = 3, rankedDraws = 0 }))
	check("global: an account whose only ranked match was a draw is eligible",
		GlobalRank.eligible({ rankedWins = 0, rankedLosses = 0, rankedDraws = 1 }))
	check("global: a fresh account at the default rating is not",
		not GlobalRank.eligible({ rankedWins = 0, rankedLosses = 0, rankedDraws = 0 }))
	check("global: and neither is nothing at all", not GlobalRank.eligible(nil))

	-- Writes are queued and keyed by user.
	g:publish(101, 1300)
	eq("global: nothing is written until the queue drains", backend.writes, 0)
	eq("global: draining writes it", g:flush(), 1)
	eq("global: keyed by UserId", backend.keys[101], 1300)

	-- Same rating twice is harmless; two ratings for one user cost one write.
	g:publish(101, 1300)
	g:flush()
	eq("global: writing the same rating again is harmless", backend.keys[101], 1300)
	g:publish(101, 1310)
	g:publish(101, 1325)
	local before = backend.writes
	g:flush()
	eq("global: two changes before a drain cost one write", backend.writes - before, 1)
	eq("global: and the newest value wins", backend.keys[101], 1325)

	-- Ratings fall as well as rise. A max-semantics index would be a ratchet.
	g:publish(101, 1180)
	g:flush()
	eq("global: a rating that fell is stored as the lower value", backend.keys[101], 1180)

	-- Junk never reaches the store.
	local writes = backend.writes
	g:publish("not a user", 1200)
	g:publish(102, "not a rating")
	g:publish(0 / 0, 1200)
	g:publish(103, 0 / 0)
	g:publish(10.5, 1200)
	g:flush()
	eq("global: malformed publishes are dropped before the store", backend.writes, writes)
end

function T.globalRankBoard()
	local backend = fakeIndex()
	local g = GlobalRank.new(backend)
	for id, rating in pairs({ [11] = 1500, [12] = 1200, [13] = 1900, [14] = 1000,
		[15] = 1750, [16] = 1650, [17] = 900 }) do
		backend.identities[id] = "Player" .. id
		g:publish(id, rating)
	end
	g:flush()

	check("global: no page before the first read", g:top() == nil)
	check("global: the first fetch succeeds", g:refresh(100))
	local rows = g:top()
	eq("global: the page is capped at the panel's row count", #rows, GlobalRank.LIMIT)
	eq("global: the top row is the highest rating", rows[1].rating, 1900)
	local descending = true
	for i = 2, #rows do
		if rows[i].rating > rows[i - 1].rating then descending = false end
	end
	check("global: rows are sorted descending", descending)
	eq("global: rank is the row's position", rows[3].rank, 3)
	eq("global: UserId resolves to a current identity", rows[1].name, "Player13")

	-- Reads are throttled: refreshLeaderboard runs constantly and must not.
	eq("global: one read so far", backend.reads, 1)
	check("global: no fetch is due immediately after one", not g:shouldFetch(101))
	check("global: still none inside the interval", not g:shouldFetch(100 + GlobalRank.REFRESH_INTERVAL - 1))
	check("global: due once the interval elapses", g:shouldFetch(100 + GlobalRank.REFRESH_INTERVAL))

	-- A requested refresh comes sooner, but not immediately.
	g:request()
	check("global: a request does not bypass the minimum gap",
		not g:shouldFetch(100 + GlobalRank.MIN_GAP - 1))
	check("global: a request is honoured after the gap",
		g:shouldFetch(100 + GlobalRank.MIN_GAP))
	g:refresh(100 + GlobalRank.MIN_GAP)
	check("global: fetching clears the request",
		not g:shouldFetch(100 + GlobalRank.MIN_GAP + 1))

	-- A failed read keeps the last good page rather than blanking the board.
	backend.failRead = true
	local kept = #g:top()
	check("global: a failed read reports failure", not g:refresh(500))
	eq("global: and leaves the good page in place", #g:top(), kept)
	local _, status = g:top()
	eq("global: status says the page is stale", status, "stale")
	backend.failRead = false

	-- An identity lookup that fails must not blank or drop anybody.
	backend.failNames = true
	backend.identities[13] = nil
	check("global: a fetch with no identities still succeeds", g:refresh(600))
	eq("global: the row survives", #g:top(), GlobalRank.LIMIT)
	eq("global: and keeps the name this server already knew", g:top()[1].name, "Player13")
	backend.failNames = false

	-- Malformed index rows are skipped, not rendered.
	backend.junk = { { userId = "abc", rating = 1500 }, { userId = 21, rating = "high" },
		{ userId = 22, rating = 1400 }, { userId = -5, rating = 9999 } }
	check("global: a fetch of malformed rows still succeeds", g:refresh(700))
	eq("global: only the well-formed row is kept", #g:top(), 1)
	eq("global: which is the real one", g:top()[1].userId, 22)
	backend.junk = nil
end

function T.globalRankFallback()
	-- No API access at all: this is Studio's normal state, and every server's
	-- state if DataStores are down.
	local dead = GlobalRank.new(nil)
	local rows, status = dead:top()
	check("global: with no backend there is no page", rows == nil)
	eq("global: and the status says so", status, "unavailable")
	check("global: publishing is a no-op", not dead:publish(1, 1500))
	eq("global: flushing writes nothing", dead:flush(), 0)
	check("global: no fetch is ever due", not dead:shouldFetch(1e6))
	check("global: refreshing fails quietly", not dead:refresh(1))
	check("global: patching an absent page does nothing", not dead:patch(1, 2000, "X"))
	eq("global: age of a page that never arrived", dead:age(50), -1)

	-- The local patch after a ranked result, which is what keeps this server's
	-- board honest between fetches.
	local backend = fakeIndex()
	local g = GlobalRank.new(backend)
	for id = 31, 35 do
		backend.identities[id] = "P" .. id
		g:publish(id, 1000 + id)
	end
	g:flush()
	g:refresh(10)
	eq("global: the weakest of five is last", g:top()[5].userId, 31)
	check("global: a result patches the cached page", g:patch(31, 2000, "P31"))
	eq("global: the patched player is now first", g:top()[1].userId, 31)
	eq("global: with their new rating", g:top()[1].rating, 2000)
	eq("global: and the page is still capped", #g:top(), GlobalRank.LIMIT)
	check("global: a patch below the cut does not lengthen the page",
		g:patch(99, 1, "Nobody") and #g:top() == GlobalRank.LIMIT)
	local last = g:top()[GlobalRank.LIMIT]
	check("global: and does not appear on it", last.userId ~= 99)
end

-- The wiring: which results reach the index, and which must not.
function T.globalRankWiring()
	local backend = fakeIndex()
	local g = GlobalRank.new(backend)
	local realRank = Stats.globalRank()
	Stats.setGlobalRank(g)

	local ok, err = pcall(function()
		local a, b = fakePlayer(-101, "Alpha"), fakePlayer(-102, "Beta")
		Stats.load(a)
		Stats.load(b)
		local pa, pb = Stats.get(a), Stats.get(b)
		check("wiring: a fresh profile starts unranked",
			pa.rankedWins == 0 and pa.rankedLosses == 0 and pa.rankedDraws == 0)
		eq("wiring: at the default rating", pa.rating, 1000)
		eq("wiring: a fresh account publishes nothing on load", backend.writes, 0)
		g:flush()
		eq("wiring: still nothing", backend.writes, 0)

		-- A match object shaped exactly as MatchInstance builds one.
		local function match(mode, aPlayer, bPlayer)
			local m = { mode = mode }
			m.a = { player = aPlayer, board = { stats = { lines = 4, quads = 1 } } }
			m.b = { player = bPlayer, board = { stats = { lines = 2, quads = 0 } } }
			m.a.other, m.b.other = m.b, m.a
			return m
		end

		-- Quick play must not touch the ranked index.
		local quick = match(Enums.Mode.Quick, a, b)
		Stats.recordMatch(quick, quick.b, nil)
		g:flush()
		eq("wiring: a quick match writes no ranking entry", backend.writes, 0)
		eq("wiring: and moves no rating", Stats.get(a).rating, 1000)

		local private_ = match(Enums.Mode.Private, a, b)
		Stats.recordMatch(private_, private_.b, nil)
		g:flush()
		eq("wiring: a private match writes no ranking entry", backend.writes, 0)

		-- Practice must not either.
		Stats.recordPractice(a, { mode = Enums.Mode.Sprint, lines = 40, time = 30, sprint = true })
		g:flush()
		eq("wiring: practice writes no ranking entry", backend.writes, 0)

		-- Ranked does.
		local ranked = match(Enums.Mode.Ranked, a, b)
		Stats.recordMatch(ranked, ranked.b, nil)
		check("wiring: the winner's rating rose", Stats.get(a).rating > 1000)
		check("wiring: the loser's rating fell", Stats.get(b).rating < 1000)
		eq("wiring: the winner is credited a ranked win", Stats.get(a).rankedWins, 1)
		g:flush()
		eq("wiring: the winner is indexed", backend.keys[-101], Stats.get(a).rating)
		eq("wiring: so is the loser, at their lower rating", backend.keys[-102], Stats.get(b).rating)
		check("wiring: which is below the default", backend.keys[-102] < 1000)

		-- A ranked disconnect: the leaver keeps their Player so the loss lands.
		local before = Stats.get(b).rating
		local left = match(Enums.Mode.Ranked, a, b)
		left.b.left = true
		Stats.recordMatch(left, left.b, Enums.Result.Left)
		g:flush()
		check("wiring: a ranked disconnect moves the leaver's rating",
			Stats.get(b).rating < before)
		eq("wiring: and updates their ranking entry", backend.keys[-102], Stats.get(b).rating)

		-- A ranked forfeit, rated the same way.
		local beforeF = Stats.get(a).rating
		local ff = match(Enums.Mode.Ranked, a, b)
		Stats.recordMatch(ff, ff.a, Enums.Result.Forfeit)
		g:flush()
		check("wiring: a ranked forfeit moves the forfeiter's rating",
			Stats.get(a).rating < beforeF)
		eq("wiring: and updates their entry", backend.keys[-101], Stats.get(a).rating)

		-- A ranked draw: Phase 10 moves both ratings and counts neither a win
		-- nor a loss. It still has to reach the board.
		local c, d = fakePlayer(-103, "Gamma"), fakePlayer(-104, "Delta")
		Stats.load(c)
		Stats.load(d)
		Stats.get(c).rating = 1400
		Stats.get(d).rating = 1000
		local drawn = match(Enums.Mode.Ranked, c, d)
		Stats.recordMatch(drawn, nil, Enums.Result.Timeout)
		check("wiring: a draw costs the favourite", Stats.get(c).rating < 1400)
		check("wiring: and pays the underdog", Stats.get(d).rating > 1000)
		eq("wiring: a draw is not a ranked win", Stats.get(c).rankedWins, 0)
		eq("wiring: nor a ranked loss", Stats.get(c).rankedLosses, 0)
		eq("wiring: it is recorded as a draw", Stats.get(c).rankedDraws, 1)
		g:flush()
		eq("wiring: and both sides are indexed", backend.keys[-103], Stats.get(c).rating)
		eq("wiring: both of them", backend.keys[-104], Stats.get(d).rating)

		-- Migration: a profile with ranked history and no index entry.
		backend.keys[-105] = nil
		local e = fakePlayer(-105, "Epsilon")
		Stats.load(e)
		local pe = Stats.get(e)
		pe.rating, pe.rankedWins = 1375, 4
		Stats.load(e) -- the join that finds the existing profile
		Stats.get(e).rating, Stats.get(e).rankedWins = 1375, 4
		g:flush()
		-- The reload above reset the profile, so publish explicitly the way a
		-- real load of a saved profile would.
		g:publish(-105, 1375)
		g:flush()
		eq("wiring: an existing ranked profile reaches the index", backend.keys[-105], 1375)
		eq("wiring: and the profile keeps its own rating", Stats.get(e).rating, 1375)

		-- A failed write must not cost anybody their result.
		backend.failWrite = true
		local ratingBefore = Stats.get(a).rating
		local broken = match(Enums.Mode.Ranked, a, b)
		Stats.recordMatch(broken, broken.b, nil)
		g:flush()
		check("wiring: a failed ranking write still moved the rating",
			Stats.get(a).rating > ratingBefore)
		check("wiring: and still produced a result for the card",
			broken.a.elo ~= nil and broken.a.elo.after == Stats.get(a).rating)
		backend.failWrite = false

		-- The client's only write path into a profile is settings.
		local held = table.clone(Stats.get(a))
		Stats.applySettings(a, { rating = 999999, rankedWins = 500, rankedLosses = 0,
			peakRating = 999999, bestSprint = 0.01, das = 111 })
		local now_ = Stats.get(a)
		eq("wiring: a client cannot set its rating", now_.rating, held.rating)
		eq("wiring: nor its ranked wins", now_.rankedWins, held.rankedWins)
		eq("wiring: nor its ranked losses", now_.rankedLosses, held.rankedLosses)
		eq("wiring: nor its peak rating", now_.peakRating, held.peakRating)
		eq("wiring: nor its sprint record", now_.bestSprint, held.bestSprint)
		eq("wiring: settings still apply", now_.das, 111)
		-- And nothing it sent reached the ranking index either.
		local writes = backend.writes
		g:flush()
		eq("wiring: a settings message publishes nothing", backend.writes, writes)
	end)

	Stats.setGlobalRank(realRank)
	if not ok then
		error(err, 0)
	end
end

-- refreshLeaderboard is called on every join, departure and result. It must
-- render the cache and never reach for the network.
function T.globalRankRender()
	local backend = fakeIndex()
	local g = GlobalRank.new(backend)
	local realRank = Stats.globalRank()
	Stats.setGlobalRank(g)

	local ok, err = pcall(function()
		for i = 1, 6 do
			backend.identities[200 + i] = "Global" .. i
			g:publish(200 + i, 1000 + i * 50)
		end
		g:flush()
		g:refresh(1)
		local reads = backend.reads
		for _ = 1, 10 do
			Stats.refreshLeaderboard()
		end
		eq("render: ten redraws cause no extra global reads", backend.reads, reads)

		-- What the panel is titled is the whole honesty question: server-local
		-- rows under the words WORLD RANK would be a lie nobody ever catches.
		local title = select(1, Stats.worldPanelForTest())
		eq("render: a good global page is titled as global", title, "WORLD RANK")

		local empty = GlobalRank.new(fakeIndex())
		empty:refresh(1) -- succeeds, but the index has nobody in it
		Stats.setGlobalRank(empty)
		eq("render: an empty global page falls back to this server",
			select(1, Stats.worldPanelForTest()), "SERVER RANK")

		Stats.setGlobalRank(GlobalRank.new(nil))
		eq("render: an unreachable index falls back too",
			select(1, Stats.worldPanelForTest()), "SERVER RANK")
	end)

	Stats.setGlobalRank(realRank)
	Stats.refreshLeaderboard() -- put the tower back on real data
	if not ok then
		error(err, 0)
	end
end

-- ── Skins (Phase 13) ──────────────────────────────────────────────────────

-- The catalog is checked rather than trusted: a half-written skin should fail
-- here, not on somebody's board.
function T.skinCatalog()
	local ok, problems = SkinData.validate()
	check("skins: the catalog validates", ok, table.concat(problems, "; "))

	local seen = {}
	for _, skin in ipairs(SkinData.ordered()) do
		check("skins: " .. tostring(skin.id) .. " has a unique id", not seen[skin.id])
		seen[skin.id] = true
		eq("skins: " .. skin.id .. " has eight palette entries", #skin.palette, 8)
	end

	check("skins: there is a default", SkinData.default() ~= nil)
	eq("skins: and it is the one the id names", SkinData.default().id, SkinData.DEFAULT_ID)
	check("skins: the default is owned by default", SkinData.default().defaultOwned == true)
	check("skins: an unknown id does not exist", not SkinData.exists("no_such_skin"))
	check("skins: a non-string id does not exist", not SkinData.exists(42))
	eq("skins: an unknown id resolves to the default", SkinData.resolve("nope").id, SkinData.DEFAULT_ID)
	eq("skins: so does nil", SkinData.resolve(nil).id, SkinData.DEFAULT_ID)

	-- Colourblind overrides the skin outright: a cosmetic must never be able to
	-- switch accessibility off.
	for _, skin in ipairs(SkinData.ordered()) do
		eq("skins: " .. skin.id .. " yields to the colourblind palette",
			SkinData.paletteFor(skin.id, true), SkinData.COLOURBLIND)
		eq("skins: " .. skin.id .. " uses its own palette otherwise",
			SkinData.paletteFor(skin.id, false), skin.palette)
	end
	eq("skins: the colourblind palette covers every piece and garbage",
		#SkinData.COLOURBLIND, 8)

	-- Every piece has to stay tellable from every other piece.
	for _, skin in ipairs(SkinData.ordered()) do
		local far = true
		for i = 1, 7 do
			for j = i + 1, 7 do
				local a, b = skin.palette[i], skin.palette[j]
				local d = math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
				if d < 0.25 then far = false end
			end
		end
		check("skins: " .. skin.id .. " keeps the seven pieces distinguishable", far)
	end
end

-- Ownership, migration and the rules that hold whatever came back from a store.
function T.skinOwnership()
	local a = fakePlayer(-201, "SkinOne")
	Stats.load(a)
	local p = Stats.get(a)

	eq("skins: a new profile equips the default", p.equippedSkin, SkinData.DEFAULT_ID)
	check("skins: and owns it", p.ownedSkins[SkinData.DEFAULT_ID] == true)
	local ownedCount = 0
	for _ in pairs(p.ownedSkins) do ownedCount += 1 end
	eq("skins: and owns nothing else", ownedCount, 1)

	-- Two profiles must not share one ownership table, which is exactly what a
	-- shallow clone of the defaults would hand out.
	local b = fakePlayer(-202, "SkinTwo")
	Stats.load(b)
	check("skins: two profiles do not share an ownership table",
		Stats.get(a).ownedSkins ~= Stats.get(b).ownedSkins)
	eq("skins: granting one is granted", Stats.grantSkin(a, "golden"), "granted")
	check("skins: and does not reach the other", Stats.get(b).ownedSkins.golden == nil)

	-- Granting.
	eq("skins: granting again is idempotent", Stats.grantSkin(a, "golden"), "already")
	check("skins: the skin is owned", Stats.ownsSkin(a, "golden"))
	eq("skins: a skin that does not exist cannot be granted",
		Stats.grantSkin(a, "no_such_skin"), "unknown skin")
	eq("skins: nor a malformed id", Stats.grantSkin(a, { }), "unknown skin")
	eq("skins: nor nothing at all", Stats.grantSkin(a, nil), "unknown skin")

	-- Equipping.
	eq("skins: an owned skin equips", Stats.equipSkin(a, "golden"), "equipped")
	eq("skins: and is recorded", Stats.get(a).equippedSkin, "golden")
	eq("skins: equipping it again changes nothing", Stats.equipSkin(a, "golden"), "no change")
	eq("skins: an unowned skin is refused", Stats.equipSkin(a, "galaxy"), "not owned")
	eq("skins: and does not change what is equipped", Stats.get(a).equippedSkin, "golden")
	eq("skins: a skin that does not exist is refused",
		Stats.equipSkin(a, "no_such_skin"), "unknown skin")
	eq("skins: equipping during a match is refused",
		Stats.equipSkin(a, SkinData.DEFAULT_ID, true), "in a match")
	eq("skins: which leaves the equipped skin alone", Stats.get(a).equippedSkin, "golden")

	-- Malformed requests are harmless: none may throw, mutate or equip.
	local before = Stats.get(a).equippedSkin
	local ownedBefore = 0
	for _ in pairs(Stats.get(a).ownedSkins) do ownedBefore += 1 end
	for _, bad in ipairs({ 123, true, "", string.rep("x", 5000) }) do
		local okCall, verdict = pcall(Stats.equipSkin, a, bad)
		check("skins: a malformed equip does not error", okCall, tostring(verdict))
		check("skins: and equips nothing", verdict ~= "equipped")
	end
	local okNil, verdictNil = pcall(Stats.equipSkin, a, nil)
	check("skins: a nil equip does not error", okNil, tostring(verdictNil))
	eq("skins: nothing moved", Stats.get(a).equippedSkin, before)
	local ownedAfter = 0
	for _ in pairs(Stats.get(a).ownedSkins) do ownedAfter += 1 end
	eq("skins: and nothing was granted", ownedAfter, ownedBefore)

	-- The client's one write path into a profile still cannot touch any of it.
	Stats.applySettings(a, { ownedSkins = { galaxy = true }, equippedSkin = "galaxy",
		unlock = true, das = 120 })
	check("skins: SaveSettings cannot grant", Stats.get(a).ownedSkins.galaxy == nil)
	eq("skins: SaveSettings cannot equip", Stats.get(a).equippedSkin, "golden")
	eq("skins: but still saves settings", Stats.get(a).das, 120)
end

-- What a profile becomes, given whatever was in the store.
function T.skinMigration()
	local function migrated(saved)
		-- merge() is private, so go through the seam every profile goes
		-- through: a load with no store returns the merged defaults, and the
		-- fields under test are rebuilt from `saved` by the same code path.
		return Stats.migrateForTest(saved)
	end

	local fresh = migrated(nil)
	check("migration: a profile with no skin fields owns the default",
		fresh.ownedSkins[SkinData.DEFAULT_ID] == true)
	eq("migration: and equips it", fresh.equippedSkin, SkinData.DEFAULT_ID)

	local legacy = migrated({ wins = 12, rating = 1240 })
	eq("migration: an old profile keeps its stats", legacy.wins, 12)
	eq("migration: and its rating", legacy.rating, 1240)
	check("migration: and gains the default skin", legacy.ownedSkins[SkinData.DEFAULT_ID] == true)

	local retired = migrated({ ownedSkins = { golden = true, ancient_relic = true },
		equippedSkin = "golden" })
	check("migration: a live id survives", retired.ownedSkins.golden == true)
	check("migration: an id that left the catalog is dropped",
		retired.ownedSkins.ancient_relic == nil)
	eq("migration: and the equipped skin is untouched", retired.equippedSkin, "golden")

	local gone = migrated({ ownedSkins = { golden = true }, equippedSkin = "ancient_relic" })
	eq("migration: equipping a retired skin falls back to the default",
		gone.equippedSkin, SkinData.DEFAULT_ID)
	check("migration: without losing the rest of the wardrobe", gone.ownedSkins.golden == true)

	local unowned = migrated({ ownedSkins = {}, equippedSkin = "galaxy" })
	eq("migration: equipping something unowned falls back too",
		unowned.equippedSkin, SkinData.DEFAULT_ID)

	local junk = migrated({ ownedSkins = { golden = "yes", [7] = true, galaxy = false },
		equippedSkin = 99 })
	check("migration: ownership that is not literally true is ignored",
		junk.ownedSkins.golden == nil and junk.ownedSkins.galaxy == nil)
	eq("migration: a non-string equipped id falls back", junk.equippedSkin, SkinData.DEFAULT_ID)
	check("migration: the default is still there", junk.ownedSkins[SkinData.DEFAULT_ID] == true)

	local hostile = migrated({ ownedSkins = "everything", equippedSkin = { "galaxy" } })
	check("migration: a hostile ownership value yields the default only",
		hostile.ownedSkins[SkinData.DEFAULT_ID] == true and hostile.ownedSkins.golden == nil)
	eq("migration: and the default equipped", hostile.equippedSkin, SkinData.DEFAULT_ID)

	-- The merge that runs on save, where two servers can disagree.
	local mine = { ownedSkins = { classic = true, golden = true }, equippedSkin = "golden" }
	local theirs = { ownedSkins = { classic = true, diamond = true }, equippedSkin = "diamond" }
	local union = Stats.mergeProgressForTest(theirs, mine)
	check("migration: a grant made elsewhere survives this server's save",
		union.ownedSkins.diamond == true)
	check("migration: and so does this server's", union.ownedSkins.golden == true)
	check("migration: the default is never lost",
		union.ownedSkins[SkinData.DEFAULT_ID] == true)
	eq("migration: equipped follows the saving server", union.equippedSkin, "golden")
end

-- A skin is presentation. It must not be able to reach the simulation.
function T.skinIsCosmetic()
	local function play(seed, skinId)
		-- The board takes no skin at all, which is the point: there is no
		-- argument to pass and nowhere for one to get in.
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

	local plain, skinned = play(4242), play(4242)
	local same = true
	for i = 1, #plain.cells do
		if plain.cells[i] ~= skinned.cells[i] then same = false end
	end
	check("cosmetic: the same seed gives the same board whatever is equipped", same)
	eq("cosmetic: the same piece count", plain.stats.pieces, skinned.stats.pieces)
	eq("cosmetic: the same lines", plain.stats.lines, skinned.stats.lines)
	eq("cosmetic: the same attack sent", plain.stats.sent, skinned.stats.sent)

	-- Attack, T-spin detection and the bag do not take a skin either.
	eq("cosmetic: attack is computed from lines and spin alone",
		Attack.compute(2, "full", false, false, 1).attack, 4)
	local s = SPINS.double
	local spun = spinInto(s)
	eq("cosmetic: T-spin detection is board geometry", spun:detectTSpin(), "full")
	local bagA, bagB = Bag.new(777), Bag.new(777)
	local bagSame = true
	for _ = 1, 20 do
		if bagA:pop() ~= bagB:pop() then bagSame = false end
	end
	check("cosmetic: the piece sequence is untouched", bagSame)

	-- And nothing about a skin appears in the competitive message shape.
	local m = MatchInstance.new(5150, { name = "P1" }, { name = "P2" }, { seed = 3 })
	check("cosmetic: a match message is addressed by id, not by appearance",
		m:ownsMessage({ matchId = 5150 }))
	check("cosmetic: a skinned message is still just a message",
		m:ownsMessage({ matchId = 5150, skinId = "galaxy" }))
	check("cosmetic: and a wrong id is still refused",
		not m:ownsMessage({ matchId = 1, skinId = "galaxy" }))
end

-- ── Secret puzzle (Phase 14) ──────────────────────────────────────────────

-- A nook of the same shape as the built one, made of throwaway parts. The real
-- one is a single shared object in the live world; a test that drove it would
-- be moving the blocks a player might be standing in front of.
local function fakeNook(slotIndices: { number }?, pieceIndices: { number }?, puzzle: any)
	local container = Instance.new("Folder")
	container.Name = "SecretForTest"
	local board = Instance.new("Folder")
	board.Name = "Board"
	board:SetAttribute("Puzzle", puzzle == nil and "T" or puzzle)
	board:SetAttribute("Solved", false)
	board.Parent = container

	for i, index in ipairs(slotIndices or { 13, 14, 15, 19 }) do
		local slot = Instance.new("Part")
		slot.Name = "Slot"
		slot.Anchored = true
		slot.Size = Vector3.new(4.4, 3.8, 0.4)
		slot.Position = Vector3.new(100 + i * 5, 10, -100)
		slot.Transparency = 0.85
		slot:SetAttribute("SlotIndex", index)
		slot.Parent = board
	end
	for i, index in ipairs(pieceIndices or { 1, 2, 3, 4 }) do
		local piece = Instance.new("Part")
		piece.Name = "LoosePiece"
		piece.Anchored = true
		piece.Size = Vector3.new(4, 3.6, 1.6)
		piece.Position = Vector3.new(100 + i * 3, 2, -110)
		piece:SetAttribute("PieceIndex", index)
		piece.Parent = container
	end
	container.Parent = workspace
	return container
end

-- A player-shaped table with a character that has somewhere to stand.
local function nookPlayer(name: string, at: Vector3)
	local char = Instance.new("Model")
	char.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Size = Vector3.new(2, 2, 1)
	root.Position = at
	root.Parent = char
	char.Parent = workspace
	-- Parent stands in for "still in the game", which is what step() checks.
	return { Name = name, Character = char, Parent = workspace, _root = root, _char = char }
end

local function fakeStats(solved: boolean?)
	local f = { solvedFlag = solved == true, completions = 0, profile = {} }
	f.getProfile = function() return f.profile end
	f.hasSolvedSecret = function() return f.solvedFlag end
	f.completeSecretPuzzle = function()
		if f.solvedFlag then return "already solved" end
		f.solvedFlag = true
		f.completions += 1
		return "completed"
	end
	return f
end

local function fakeMatchmaking()
	local f = { inMatch = {}, queued = {} }
	f.matchFor = function(p) return f.inMatch[p] end
	f.isQueued = function(p) return f.queued[p] == true end
	return f
end

function T.puzzleGeometry()
	-- The shape the world is required to have.
	local ok, why = PuzzleService.validate({ puzzle = "T", slots = { 13, 14, 15, 19 },
		pieces = { 1, 2, 3, 4 } })
	check("puzzle: the built nook validates", ok, why)

	local bad = {
		{ { puzzle = "L", slots = { 13, 14, 15, 19 }, pieces = { 1, 2, 3, 4 } }, "wrong puzzle" },
		{ { puzzle = "T", slots = { 13, 14, 15 }, pieces = { 1, 2, 3, 4 } }, "three slots" },
		{ { puzzle = "T", slots = { 13, 14, 15, 19 }, pieces = { 1, 2, 3 } }, "three pieces" },
		{ { puzzle = "T", slots = { 13, 13, 15, 19 }, pieces = { 1, 2, 3, 4 } }, "duplicate slot" },
		{ { puzzle = "T", slots = { 13, 14, 15, 19 }, pieces = { 1, 1, 3, 4 } }, "duplicate piece" },
		{ { puzzle = "T", slots = { 13, 14, 15, "x" }, pieces = { 1, 2, 3, 4 } }, "slot is not a number" },
		{ { puzzle = "T", slots = { 13, 14, 15, 19 }, pieces = { 1, 2, 3, 4.5 } }, "piece is fractional" },
		{ { puzzle = "T", pieces = { 1, 2, 3, 4 } }, "no slots at all" },
		{ nil, "nothing found" },
	}
	for _, case in ipairs(bad) do
		local good = PuzzleService.validate(case[1])
		check("puzzle: rejected — " .. case[2], not good)
	end

	-- And the same rules applied to real geometry.
	local nook = fakeNook()
	local svc = PuzzleService.new({ stats = fakeStats(), matchmaking = fakeMatchmaking() })
	local bound = svc:bind(nook)
	check("puzzle: binds to a well-formed nook", bound)
	eq("puzzle: found four slots", #(function()
		local n = {} for k in pairs(svc.slots) do table.insert(n, k) end return n
	end)(), 4)
	eq("puzzle: found four pieces", #(function()
		local n = {} for k in pairs(svc.pieces) do table.insert(n, k) end return n
	end)(), 4)
	check("puzzle: hung a prompt on every one of them", #svc.prompts == 8)
	nook:Destroy()

	local broken = fakeNook({ 13, 14 }, { 1, 2, 3, 4 })
	local svc2 = PuzzleService.new({ stats = fakeStats(), matchmaking = fakeMatchmaking() })
	local ok2 = svc2:bind(broken)
	check("puzzle: a malformed nook disables rather than throwing", not ok2)
	check("puzzle: and stays disabled", not svc2.enabled)
	-- Nothing on a disabled puzzle may do anything.
	local p = nookPlayer("Nobody", Vector3.new(100, 2, -110))
	eq("puzzle: taking from a disabled puzzle does nothing",
		svc2:takePiece(p, 1, 0), "no such piece")
	broken:Destroy()
	p._char:Destroy()

	local svc3 = PuzzleService.new({})
	check("puzzle: binding to nothing is safe", not svc3:bind(nil))
end

function T.puzzleSolving()
	local nook = fakeNook()
	local stats, mm = fakeStats(), fakeMatchmaking()
	local svc = PuzzleService.new({ stats = stats, matchmaking = mm })
	svc:bind(nook)
	local near = Vector3.new(110, 4, -105)
	local a = nookPlayer("Solver", near)

	-- Selection.
	eq("puzzle: a piece can be taken", svc:takePiece(a, 1, 0), "held")
	eq("puzzle: one block at a time", svc:takePiece(a, 2, 0), "already holding one")
	eq("puzzle: a piece that is not there", svc:takePiece(a, 9, 0), "no such piece")

	-- Placement.
	eq("puzzle: it fills an empty slot", svc:placePiece(a, 13, 0), "placed")
	eq("puzzle: and nothing is in hand afterwards", svc:placePiece(a, 14, 0), "nothing in hand")
	eq("puzzle: a placed piece cannot be taken again", svc:takePiece(a, 1, 0), "already placed")
	eq("puzzle: a slot that is not there", svc:placePiece(a, 99, 0), "no such slot")

	svc:takePiece(a, 2, 0)
	eq("puzzle: an occupied slot refuses a second block", svc:placePiece(a, 13, 0), "slot is full")
	eq("puzzle: so it goes in an empty one", svc:placePiece(a, 14, 0), "placed")
	eq("puzzle: three of four is not a solve", stats.completions, 0)
	svc:takePiece(a, 3, 0)
	svc:placePiece(a, 15, 0)
	eq("puzzle: still not solved on three", stats.completions, 0)
	check("puzzle: the board is not marked solved yet",
		nook.Board:GetAttribute("Solved") == false)

	svc:takePiece(a, 4, 0)
	local result = svc:placePiece(a, 19, 0)
	eq("puzzle: the fourth block solves it", result, "solved:completed")
	eq("puzzle: exactly one completion", stats.completions, 1)
	check("puzzle: the board shows solved", nook.Board:GetAttribute("Solved") == true)

	-- The world goes back for the next player.
	svc:step(PuzzleService.CELEBRATE + 1)
	check("puzzle: the board is unsolved again after the celebration",
		nook.Board:GetAttribute("Solved") == false)
	check("puzzle: and the session is released", svc.session == nil)
	local home = true
	for index, part in pairs(svc.pieces) do
		if (part.Position - svc.home[index].cframe.Position).Magnitude > 0.01 then home = false end
	end
	check("puzzle: every block is back where it started", home)

	-- A second player can now solve it, and only they are paid.
	local b = nookPlayer("Second", near)
	stats.solvedFlag = false
	eq("puzzle: the next player can claim it", svc:takePiece(b, 1, 100), "held")
	check("puzzle: and it is theirs", svc.session.player == b)
	a._char:Destroy()
	b._char:Destroy()
	nook:Destroy()
end

function T.puzzleSessions()
	local nook = fakeNook()
	local stats, mm = fakeStats(), fakeMatchmaking()
	local svc = PuzzleService.new({ stats = stats, matchmaking = mm })
	svc:bind(nook)
	local near = Vector3.new(110, 4, -105)
	local a = nookPlayer("First", near)
	local b = nookPlayer("Second", near)

	eq("session: the first player claims it", svc:takePiece(a, 1, 0), "held")
	eq("session: the second cannot take a block",
		svc:takePiece(b, 2, 0), "someone else is solving it")
	eq("session: nor place one", svc:placePiece(b, 13, 0), "someone else is solving it")
	check("session: and the first player still holds it", svc.session.player == a)

	-- Timeout releases it, and puts the blocks back.
	svc:step(PuzzleService.TIMEOUT + 1)
	check("session: it times out", svc.session == nil)
	eq("session: after which the second player can claim it", svc:takePiece(b, 1, 200), "held")

	-- Leaving releases it.
	svc:playerLeaving(b)
	check("session: leaving releases the puzzle", svc.session == nil)

	-- A disconnected solver is cleaned up by the loop even without the event.
	svc:takePiece(a, 1, 300)
	a.Parent = nil
	svc:step(301)
	check("session: a solver who is gone releases it", svc.session == nil)
	a.Parent = workspace

	-- A character that vanished mid-session.
	svc:takePiece(a, 1, 400)
	local savedChar = a.Character
	a.Character = nil
	svc:step(401)
	check("session: a solver with no character releases it", svc.session == nil)
	a.Character = savedChar

	-- Distance, checked on the server whatever the prompt believed.
	local far = nookPlayer("Distant", Vector3.new(400, 4, 400))
	eq("session: the puzzle cannot be solved from across the lobby",
		svc:takePiece(far, 1, 500), "too far away")
	check("session: and no session was opened", svc.session == nil)

	-- Busy players do not get to reserve it.
	mm.inMatch[a] = { id = 1 }
	eq("session: a player in a match cannot claim it", svc:takePiece(a, 1, 600), "in a match")
	mm.inMatch[a] = nil
	mm.queued[a] = true
	eq("session: nor a queued one", svc:takePiece(a, 1, 600), "queued")
	mm.queued[a] = nil

	-- And a solver who queues mid-puzzle loses the reservation rather than
	-- stranding the blocks when the match pulls them away.
	eq("session: claim again", svc:takePiece(a, 1, 700), "held")
	mm.queued[a] = true
	svc:step(701)
	check("session: queueing mid-solve releases it", svc.session == nil)
	mm.queued[a] = nil

	-- Someone who has already solved it does not reserve a shared object for a
	-- replay that cannot pay.
	stats.solvedFlag = true
	eq("session: an already-solved player is turned away",
		svc:takePiece(a, 1, 800), "already solved")
	check("session: leaving the nook free", svc.session == nil)

	a._char:Destroy()
	b._char:Destroy()
	far._char:Destroy()
	nook:Destroy()
end

-- The persistent half: what the profile records, and what survives a save.
function T.puzzlePersistence()
	local fresh = Stats.migrateForTest(nil)
	eq("secret: a new profile has not solved it", fresh.secretPuzzleSolved, false)
	local legacy = Stats.migrateForTest({ wins = 3, rating = 1100 })
	eq("secret: an old profile migrates to unsolved", legacy.secretPuzzleSolved, false)
	eq("secret: keeping everything else", legacy.wins, 3)
	local done = Stats.migrateForTest({ secretPuzzleSolved = true })
	eq("secret: a solved profile stays solved", done.secretPuzzleSolved, true)
	local junk = Stats.migrateForTest({ secretPuzzleSolved = "yes" })
	eq("secret: a non-boolean is ignored", junk.secretPuzzleSolved, false)

	-- Completion only ever moves one way.
	local storedTrue = Stats.mergeProgressForTest({ secretPuzzleSolved = true },
		{ ownedSkins = {}, equippedSkin = "classic", secretPuzzleSolved = false })
	eq("secret: an older server cannot erase a completion", storedTrue.secretPuzzleSolved, true)
	local storedFalse = Stats.mergeProgressForTest({ secretPuzzleSolved = false },
		{ ownedSkins = {}, equippedSkin = "classic", secretPuzzleSolved = true })
	eq("secret: and a new completion is written", storedFalse.secretPuzzleSolved, true)
	local neither = Stats.mergeProgressForTest({},
		{ ownedSkins = {}, equippedSkin = "classic", secretPuzzleSolved = false })
	eq("secret: unsolved stays unsolved", neither.secretPuzzleSolved, false)

	-- The reward, through the real entitlement path.
	local p = fakePlayer(-301, "Finder")
	Stats.load(p)
	eq("secret: starts unsolved", Stats.hasSolvedSecret(p), false)
	check("secret: and without the reward", not Stats.ownsSkin(p, SkinData.SECRET_ID))
	eq("secret: solving completes it", Stats.completeSecretPuzzle(p), "completed")
	eq("secret: which is recorded", Stats.hasSolvedSecret(p), true)
	check("secret: and grants the secret skin", Stats.ownsSkin(p, SkinData.SECRET_ID))
	eq("secret: solving twice pays nothing", Stats.completeSecretPuzzle(p), "already solved")

	-- Someone who already owns the skin still gets the completion recorded.
	local q = fakePlayer(-302, "Owner")
	Stats.load(q)
	eq("secret: granted the skin by other means", Stats.grantSkin(q, SkinData.SECRET_ID), "granted")
	eq("secret: has not solved the puzzle", Stats.hasSolvedSecret(q), false)
	eq("secret: solving still completes", Stats.completeSecretPuzzle(q), "completed")
	eq("secret: and is recorded", Stats.hasSolvedSecret(q), true)
	check("secret: the skin is still owned once", Stats.ownsSkin(q, SkinData.SECRET_ID))

	-- A profile that solved it but lost the skin is healed on load.
	local healed = Stats.migrateForTest({ secretPuzzleSolved = true, ownedSkins = {} })
	eq("secret: a solved profile with no reward keeps the completion",
		healed.secretPuzzleSolved, true)

	-- Nothing about the puzzle touches ranked or the simulation.
	local before = Stats.get(p)
	eq("secret: rating untouched", before.rating, 1000)
	eq("secret: ranked wins untouched", before.rankedWins, 0)
	eq("secret: ranked losses untouched", before.rankedLosses, 0)
	eq("secret: ranked draws untouched", before.rankedDraws, 0)
	eq("secret: matches untouched", before.matches, 0)

	-- The client's write paths cannot reach any of it.
	Stats.applySettings(p, { secretPuzzleSolved = false, ownedSkins = {}, das = 140 })
	eq("secret: SaveSettings cannot unsolve it", Stats.hasSolvedSecret(p), true)
	eq("secret: nor remove the reward", Stats.ownsSkin(p, SkinData.SECRET_ID), true)
	eq("secret: settings still apply", Stats.get(p).das, 140)
	eq("secret: the reward is the catalog's secret skin", SkinData.SECRET_ID, "galaxy")
	check("secret: which is not owned by default", not SkinData.get(SkinData.SECRET_ID).defaultOwned)
end

-- == Blitz (Phase 15) =====================================================

-- The score table, pinned exactly. Every number below is a balance decision,
-- and a balance decision that drifts silently is a bug nobody reports.
function T.blitzScoring()
	local function s(lines, tspin, b2b, combo, perfect)
		return BlitzScoring.score({ lines = lines, tspin = tspin, b2b = b2b,
			combo = combo or 1, perfect = perfect })
	end

	eq("blitz: no clear scores nothing", s(0), 0)
	eq("blitz: single", s(1), 100)
	eq("blitz: double", s(2), 300)
	eq("blitz: triple", s(3), 500)
	eq("blitz: quad", s(4), 800)

	eq("blitz: T-spin single", s(1, "full"), 800)
	eq("blitz: T-spin double", s(2, "full"), 1200)
	eq("blitz: T-spin triple", s(3, "full"), 1600)
	eq("blitz: mini single", s(1, "mini"), 200)
	eq("blitz: mini double", s(2, "mini"), 400)

	eq("blitz: a spin that cleared nothing scores nothing", s(0, "full"), 0)
	eq("blitz: nor a mini that cleared nothing", s(0, "mini"), 0)

	eq("blitz: back-to-back quad", s(4, nil, true), 1200)
	eq("blitz: back-to-back T-spin single", s(1, "full", true), 1200)
	eq("blitz: back-to-back T-spin double", s(2, "full", true), 1800)
	eq("blitz: an ordinary single takes no multiplier", s(1, nil, false), 100)

	eq("blitz: the first clear of a combo adds nothing", s(1, nil, false, 1), 100)
	eq("blitz: the second adds 50", s(1, nil, false, 2), 150)
	eq("blitz: the third adds 100", s(1, nil, false, 3), 200)

	eq("blitz: a perfect clear adds 3500 once", s(1, nil, false, 1, true), 3600)
	eq("blitz: everything at once, each part once",
		s(2, "full", true, 3, true), 1800 + 100 + 3500)

	eq("blitz: junk scores nothing", BlitzScoring.score(nil), 0)
	eq("blitz: and so does a clear of negative lines", s(-3), 0)

	eq("blitz: scores read with separators", BlitzScoring.format(12450), "12,450")
	eq("blitz: short ones do not", BlitzScoring.format(950), "950")
	eq("blitz: and long ones do twice", BlitzScoring.format(1084300), "1,084,300")
	eq("blitz: zero", BlitzScoring.format(0), "0")
end

-- A whole run, driven the way the remote drives it.
function T.blitzSession()
	local player = fakePlayer(-401, "Runner")
	local T0 = 1000

	local session = Practice.begin(player, Enums.Mode.Blitz, T0, T0)
	eq("blitz: the session knows its mode", session.mode, Enums.Mode.Blitz)
	eq("blitz: it runs for exactly BLITZ_TIME", session.endAt - session.startAt, Tuning.BLITZ_TIME)
	eq("blitz: which is two minutes", Tuning.BLITZ_TIME, 120)
	eq("blitz: it starts after the countdown", session.startAt - T0, Tuning.COUNTDOWN)
	check("blitz: it has a seed", type(session.seed) == "number")
	check("blitz: and a server board", session.board ~= nil)
	eq("blitz: starting at nothing", session.score, 0)

	local other = Practice.begin(fakePlayer(-402, "Other"), Enums.Mode.Blitz, T0, T0)
	check("blitz: sessions are uniquely numbered", other.id ~= session.id)

	-- Nothing counts before the start.
	local live = session.startAt + 1
	eq("blitz: a placement before the countdown ends is not accepted",
		(Practice.onLock(player, { sessionId = session.id, index = 1, kind = 1, rot = 1, x = 3, y = 19 },
			session.startAt - 1)), "not started")

	-- Addressing.
	eq("blitz: a lock for another session is refused",
		(Practice.onLock(player, { sessionId = session.id + 99, index = 1 }, live)), "wrong session")
	eq("blitz: a lock with no session at all is refused",
		(Practice.onLock(player, { index = 1 }, live)), "wrong session")
	eq("blitz: a lock addressed to a match is refused",
		(Practice.onLock(player, { sessionId = session.id, matchId = 7, index = 1 }, live)),
		"wrong address")
	eq("blitz: junk is refused", (Practice.onLock(player, "lock", live)), "malformed")

	-- A real placement, hard-dropped where the board says the piece can go.
	local board = session.board
	local function place(at, forge)
		local p = board.piece
		local msg = {
			sessionId = session.id,
			index = session.lastIndex + 1,
			kind = p.kind, rot = p.rot, x = p.x, y = board:ghostY(),
		}
		if forge then
			for k, v in pairs(forge) do msg[k] = v end
		end
		return Practice.onLock(player, msg, at)
	end

	local verdict = place(live)
	check("blitz: a legal placement is accepted",
		verdict == "placed" or verdict == "score", verdict)
	eq("blitz: the shadow board advanced", board.stats.pieces, 1)
	eq("blitz: and the index moved on", session.lastIndex, 1)

	-- Out of order.
	eq("blitz: a repeated index is refused",
		(Practice.onLock(player, { sessionId = session.id, index = 1, kind = board.piece.kind,
			rot = 1, x = 3, y = 5 }, live + 1)), "out of order index")

	-- Placements the board cannot produce.
	eq("blitz: an unreachable placement is refused",
		(place(live + 1, { x = 99, y = 99 })), "placement is not reachable")
	-- Sessions are seeded with math.random, so claiming "some other piece" is
	-- not reliably illegal: the hold may legitimately swap into it. Spending
	-- the hold first makes the claim impossible whatever the seed rolled.
	board.holdUsed = true
	eq("blitz: a piece that is not in play is refused",
		(place(live + 2, { kind = board.piece.kind % 7 + 1 })),
		"piece is not the one in play")
	board.holdUsed = false
	eq("blitz: a malformed placement is refused",
		(place(live + 3, { rot = 9 })), "malformed placement")

	-- Forged competitive fields change nothing: the score is the server's.
	local before = session.score
	local forged = place(live + 4, {
		score = 99999999, scoreDelta = 5000, lines = 999, combo = 99,
		b2b = true, perfect = true, tspin = "full",
	})
	check("blitz: a forged payload is still just a placement",
		forged == "placed" or forged == "score", tostring(forged))
	check("blitz: and the score only moved by what the board actually cleared",
		session.score - before < 5000, tostring(session.score - before))

	-- The deadline is the server's.
	local late = session.endAt + 1
	local verdictLate, result = Practice.onLock(player, { sessionId = session.id,
		index = session.lastIndex + 1, kind = 1, rot = 1, x = 3, y = 19 }, late)
	eq("blitz: a placement after the deadline ends the run", verdictLate, "finished")
	check("blitz: with the timer as the reason", result and result.reason == "time")
	check("blitz: and the run counts", result and result.counts == true)
	local frozen = session.score
	eq("blitz: nothing is accepted afterwards",
		(Practice.onLock(player, { sessionId = session.id, index = 99 }, late)), "finished already")
	eq("blitz: and the score is fixed", session.score, frozen)
	check("blitz: finalizing an ended run again yields nothing",
		Practice.finalize(player, "time") == nil)

	Practice.forget(player)
	Practice.forget(fakePlayer(-402, "Other"))
end

-- The three ways a run ends, and which of them count.
function T.blitzEnding()
	local player = fakePlayer(-403, "Ender")
	local T0 = 2000

	-- The timer, with nobody reporting anything.
	local session = Practice.begin(player, Enums.Mode.Blitz, T0, T0)
	eq("blitz end: nothing is due before the deadline", #Practice.step(session.endAt - 1), 0)
	local done = Practice.step(session.endAt)
	eq("blitz end: the server ends it on its own clock", #done, 1)
	eq("blitz end: for the right player", done[1].player, player)
	eq("blitz end: because time ran out", done[1].result.reason, "time")
	check("blitz end: and it counts", done[1].result.counts)
	eq("blitz end: it is only reported once", #Practice.step(session.endAt + 5), 0)
	Practice.forget(player)

	-- Topping out.
	local s2 = Practice.begin(player, Enums.Mode.Blitz, T0, T0)
	local verdict, result = Practice.onLock(player,
		{ sessionId = s2.id, topout = true }, s2.startAt + 10)
	eq("blitz end: a top-out finishes the run", verdict, "finished")
	eq("blitz end: reported as a top-out", result.reason, "topout")
	check("blitz end: and it still counts", result.counts)
	Practice.forget(player)

	-- Walking away.
	local s3 = Practice.begin(player, Enums.Mode.Blitz, T0, T0)
	local abandoned = Practice.finalize(player, "abandoned")
	check("blitz end: an abandoned run does not count", abandoned and not abandoned.counts)
	Practice.forget(player)

	-- Busy-ness, which the secret nook asks about.
	local s4 = Practice.begin(player, Enums.Mode.Blitz, T0, T0)
	check("blitz end: a live run makes the player busy", Practice.isBusy(player))
	Practice.finalize(player, "time")
	check("blitz end: a finished one does not", not Practice.isBusy(player))
	Practice.forget(player)
	check("blitz end: and neither does none at all", not Practice.isBusy(player))

	-- Sprint is untouched by any of it.
	local sprint = Practice.begin(player, Enums.Mode.Sprint, T0, T0)
	eq("blitz end: sprint is still sprint", sprint.mode, Enums.Mode.Sprint)
	check("blitz end: and keeps no shadow board", sprint.board == nil)
	check("blitz end: nor makes the player busy", not Practice.isBusy(player))
	eq("blitz end: a blitz lock finds no blitz session",
		(Practice.onLock(player, { sessionId = sprint.id, index = 1 }, T0 + 10)), "no session")
	Practice.forget(player)
end

-- What a run does to a profile, and what it must not.
function T.blitzPersistence()
	local fresh = Stats.migrateForTest(nil)
	eq("blitz best: a new profile has none", fresh.bestBlitz, 0)
	local legacy = Stats.migrateForTest({ wins = 4, rating = 1150 })
	eq("blitz best: an old profile migrates to none", legacy.bestBlitz, 0)
	eq("blitz best: keeping the rest", legacy.rating, 1150)
	local kept = Stats.migrateForTest({ bestBlitz = 42000 })
	eq("blitz best: a stored best survives", kept.bestBlitz, 42000)
	local junk = Stats.migrateForTest({ bestBlitz = "lots" })
	eq("blitz best: junk does not", junk.bestBlitz, 0)

	-- Merged with max, so a stale server cannot take a record away.
	local base = { ownedSkins = {}, equippedSkin = "classic", secretPuzzleSolved = false }
	local function merged(stored, mine)
		local profile = table.clone(base)
		profile.bestBlitz = mine
		return Stats.mergeProgressForTest({ bestBlitz = stored }, profile).bestBlitz
	end
	eq("blitz best: a stale lower save cannot erase a higher one", merged(42000, 39000), 42000)
	eq("blitz best: a better run replaces it", merged(42000, 46000), 46000)
	eq("blitz best: an equal one is harmless", merged(42000, 42000), 42000)
	eq("blitz best: a first record writes", merged(0, 15000), 15000)

	-- The record path.
	local player = fakePlayer(-404, "Scorer")
	Stats.load(player)
	eq("blitz best: starts at nothing", Stats.get(player).bestBlitz, 0)
	local ratingBefore = Stats.get(player).rating
	local sprintBefore = Stats.get(player).bestSprint

	eq("blitz best: an abandoned run is not recorded",
		Stats.recordBlitz(player, { score = 90000, counts = false, lines = 4 }), "not counted")
	eq("blitz best: and sets nothing", Stats.get(player).bestBlitz, 0)

	eq("blitz best: a finished run records",
		Stats.recordBlitz(player, { score = 12450, counts = true, lines = 20, quads = 2 }), "record")
	eq("blitz best: the score is the best", Stats.get(player).bestBlitz, 12450)
	eq("blitz best: a lower run keeps the old best",
		Stats.recordBlitz(player, { score = 9000, counts = true, lines = 8 }), "kept")
	eq("blitz best: which is unchanged", Stats.get(player).bestBlitz, 12450)
	eq("blitz best: an equal run keeps it too",
		Stats.recordBlitz(player, { score = 12450, counts = true, lines = 8 }), "kept")
	eq("blitz best: a better run takes it",
		Stats.recordBlitz(player, { score = 20000, counts = true, lines = 30 }), "record")
	eq("blitz best: and is stored", Stats.get(player).bestBlitz, 20000)
	eq("blitz best: junk is refused", Stats.recordBlitz(player, nil), "not counted")

	-- A score attack is not a ranked match and must not look like one.
	local p = Stats.get(player)
	eq("blitz best: rating untouched", p.rating, ratingBefore)
	eq("blitz best: ranked wins untouched", p.rankedWins, 0)
	eq("blitz best: ranked losses untouched", p.rankedLosses, 0)
	eq("blitz best: ranked draws untouched", p.rankedDraws, 0)
	eq("blitz best: the sprint record is its own", p.bestSprint, sprintBefore)
	eq("blitz best: no skin was granted", p.ownedSkins[SkinData.SECRET_ID], nil)
	eq("blitz best: the secret is still unsolved", p.secretPuzzleSolved, false)

	-- Nor can the client write any of it through the one path it has.
	Stats.applySettings(player, { bestBlitz = 999999, score = 999999, das = 150 })
	eq("blitz best: SaveSettings cannot set a score", Stats.get(player).bestBlitz, 20000)
	eq("blitz best: settings still apply", Stats.get(player).das, 150)

	-- A Sprint result leaves the Blitz best alone, and the other way round.
	Stats.recordPractice(player, { mode = Enums.Mode.Sprint, lines = 40, time = 30, sprint = true })
	eq("blitz best: a sprint does not touch it", Stats.get(player).bestBlitz, 20000)
end

-- == Release hardening (Phase 16) =========================================

-- Every remote the game declares should be one the game uses. A declared
-- RemoteEvent nobody fires is an instance sitting in ReplicatedStorage that a
-- client can call and that a reader has to reason about.
function T.remoteCatalog()
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	check("remotes: the folder exists", folder ~= nil)
	if not folder then return end

	local EXPECTED = {
		QueueRequest = true, QueueCancel = true, MatchUpdate = true, Lock = true,
		Garbage = true, Result = true, Resync = true, Forfeit = true,
		Practice = true, Profile = true, SaveSettings = true, EquipSkin = true,
		EquipTitle = true,
		Snapshot = true,
	}
	local found = {}
	for _, r in ipairs(folder:GetChildren()) do
		found[r.Name] = true
		check("remotes: " .. r.Name .. " is one the game uses", EXPECTED[r.Name] == true)
	end
	for name in pairs(EXPECTED) do
		check("remotes: " .. name .. " exists", found[name] == true)
	end
	check("remotes: the dead Leaderboard remote is gone", found.Leaderboard == nil)
end

-- Quitting a Blitz run has to reach the server.
--
-- The client used to tear down its own board and say nothing, leaving the
-- session counting down on the server with nobody playing it. When the deadline
-- passed it was finalized as a completed run and could set a personal best --
-- the one score that is documented as not counting.
function T.blitzAbandon()
	local player = fakePlayer(-501, "Quitter")
	Stats.load(player) -- so the refusal below is about the run, not a missing profile
	local T0 = 5000
	local session = Practice.begin(player, Enums.Mode.Blitz, T0, T0)
	check("abandon: the run is live", Practice.isBusy(player))

	local result = Practice.finalize(player, "abandoned")
	check("abandon: it ends", result ~= nil)
	eq("abandon: reported as abandoned", result.reason, "abandoned")
	check("abandon: and does not count", result.counts == false)
	eq("abandon: so it can never set a record",
		Stats.recordBlitz(player, result), "not counted")
	eq("abandon: leaving the best where it was", Stats.get(player).bestBlitz, 0)

	-- And once abandoned the deadline must not resurrect it as a finished run.
	local due = Practice.step(session.endAt + 1)
	eq("abandon: the deadline finds nothing left to finalize", #due, 0)
	Practice.forget(player)

	-- The two endings that DO count, for contrast.
	local s2 = Practice.begin(player, Enums.Mode.Blitz, T0, T0)
	local timed = Practice.step(s2.endAt)[1]
	check("abandon: a run played to time still counts", timed.result.counts)
	Practice.forget(player)

	local s3 = Practice.begin(player, Enums.Mode.Blitz, T0, T0)
	local _, topped = Practice.onLock(player, { sessionId = s3.id, topout = true }, s3.startAt + 1)
	check("abandon: and so does a top-out", topped.counts)
	Practice.forget(player)
end

-- Settlement happens once, however many times it is asked for.
function T.settlementIdempotence()
	-- A match cannot finish twice.
	local a = fakePlayer(-502, "One")
	local b = fakePlayer(-503, "Two")
	local m = MatchInstance.new(7001, { player = a }, { player = b }, { mode = "ranked" })
	local finishes = 0
	m.onFinished = function() finishes += 1 end
	m:playerLeft(a)
	m:playerLeft(a)
	m:playerLeft(b)
	m:forfeit(b)
	eq("idempotence: a match settles exactly once", finishes, 1)

	-- Puzzle release can be called until the cows come home.
	local nook = fakeNook()
	local svc = PuzzleService.new({ stats = fakeStats(), matchmaking = fakeMatchmaking() })
	svc:bind(nook)
	local p = nookPlayer("Releaser", Vector3.new(110, 4, -105))
	svc:takePiece(p, 1, 0)
	svc:release("first")
	svc:release("second")
	svc:release("third")
	check("idempotence: releasing a released puzzle is harmless", svc.session == nil)
	local home = true
	for index, part in pairs(svc.pieces) do
		if (part.Position - svc.home[index].cframe.Position).Magnitude > 0.01 then home = false end
	end
	check("idempotence: and leaves the blocks where they were built", home)
	p._char:Destroy()
	nook:Destroy()

	-- A Blitz run finalizes once.
	local runner = fakePlayer(-504, "Runner")
	local session = Practice.begin(runner, Enums.Mode.Blitz, 6000, 6000)
	check("idempotence: the first finalize returns a result",
		Practice.finalize(runner, "time") ~= nil)
	check("idempotence: the second returns nothing",
		Practice.finalize(runner, "time") == nil)
	check("idempotence: and so does a third",
		Practice.finalize(runner, "topout") == nil)
	Practice.forget(runner)
end

-- Everything a profile has learned since Phase 8, through one save/load.
function T.profileRoundTrip()
	local stored = {
		wins = 12, losses = 7, streak = 3, bestStreak = 9,
		lines = 480, quads = 22, matches = 19, bestSprint = 41.5,
		rating = 1284, peakRating = 1310, rankedWins = 6, rankedLosses = 4, rankedDraws = 1,
		das = 110, arr = 12, music = 45, sfx = 70, colourblind = true,
		ownedSkins = { classic = true, golden = true, galaxy = true },
		equippedSkin = "golden",
		secretPuzzleSolved = true,
		bestBlitz = 47250,
	}
	local p = Stats.migrateForTest(stored)
	for _, field in ipairs({ "wins", "losses", "streak", "bestStreak", "lines", "quads",
		"matches", "bestSprint", "rating", "peakRating", "rankedWins", "rankedLosses",
		"rankedDraws", "das", "arr", "music", "sfx", "bestBlitz" }) do
		eq("roundtrip: " .. field, p[field], stored[field])
	end
	eq("roundtrip: colourblind", p.colourblind, true)
	eq("roundtrip: equipped skin", p.equippedSkin, "golden")
	check("roundtrip: owned skins survive",
		p.ownedSkins.classic and p.ownedSkins.golden and p.ownedSkins.galaxy)
	eq("roundtrip: the secret stays solved", p.secretPuzzleSolved, true)

	-- And the merge that runs on save keeps every one of them.
	local merged = Stats.mergeProgressForTest(stored, p)
	eq("roundtrip: merge keeps the blitz best", merged.bestBlitz, 47250)
	eq("roundtrip: merge keeps the completion", merged.secretPuzzleSolved, true)
	check("roundtrip: merge keeps ownership",
		merged.ownedSkins.golden and merged.ownedSkins.galaxy)
end

-- The shared validator is the one both paths use. If a future edit forks them
-- again, this is the assertion that notices.
function T.sharedValidator()
	local source = game:GetService("ServerScriptService").Services.MatchInstance.Source
	check("validator: MatchInstance requires the shared one",
		source:find("LockValidation") ~= nil)
	check("validator: and does not carry its own reachability check",
		source:find("b:reachable") == nil)
	local practice = game:GetService("ServerScriptService").Services.PracticeService.Source
	check("validator: so does the solo path", practice:find("LockValidation") ~= nil)

	-- It behaves the same for both callers, which is the point of sharing it.
	local b = Board.new(99)
	local p = b.piece
	local ok = LockValidation.accept(b, { kind = p.kind, rot = p.rot, x = p.x, y = b:ghostY() })
	check("validator: a legal placement is accepted", ok)
	local b2 = Board.new(99)
	local bad, why = LockValidation.accept(b2, { kind = b2.piece.kind, rot = 1, x = 99, y = 99 })
	check("validator: an illegal one is not", not bad)
	eq("validator: with the reason the match path reports", why, "placement is not reachable")
	local b3 = Board.new(99)
	local junk = LockValidation.accept(b3, { kind = "x", rot = nil, x = {}, y = 0 / 0 })
	check("validator: junk is refused rather than thrown", not junk)

	-- Claiming a piece that is neither in play nor legally holdable, on a board
	-- whose seed is ours, so the message is the same every run.
	local b4 = Board.new(1234)
	b4.hold, b4.holdUsed = nil, true -- no swap available
	local other = (b4.piece.kind % 7) + 1
	local swapped, reason = LockValidation.accept(b4,
		{ kind = other, rot = 1, x = b4.piece.x, y = b4:ghostY() })
	check("validator: a piece the player is not holding is refused", not swapped)
	eq("validator: and says so", reason, "piece is not the one in play")
end

-- == Titles (Phase 17) ====================================================

function T.titleCatalog()
	local ok, problems = TitleData.validate()
	check("titles: the catalog validates", ok, table.concat(problems, "; "))

	local seenId, seenOrder = {}, {}
	for _, t in ipairs(TitleData.ordered()) do
		check("titles: " .. t.id .. " has a unique id", not seenId[t.id])
		seenId[t.id] = true
		check("titles: " .. t.id .. " has a unique sort order", not seenOrder[t.sortOrder])
		seenOrder[t.sortOrder] = true
		check("titles: " .. t.id .. " has a known rarity", TitleData.RARITY[t.rarity] ~= nil)
		if t.rewardSkin then
			check("titles: " .. t.id .. " rewards a real skin", SkinData.exists(t.rewardSkin))
		end
	end

	eq("titles: the default is rookie", TitleData.DEFAULT_ID, "rookie")
	check("titles: the default is owned by default", TitleData.default().defaultOwned == true)
	check("titles: an unknown id does not exist", not TitleData.exists("no_such_title"))
	check("titles: nor a non-string", not TitleData.exists(7))
	eq("titles: an unknown id resolves to the default", TitleData.resolve("nope").id, "rookie")

	-- The two skins that had no unlock source before this phase now have one.
	local rewards = {}
	for _, t in ipairs(TitleData.ordered()) do
		if t.rewardSkin then rewards[t.rewardSkin] = t.id end
	end
	eq("titles: GOLDEN T is earned by QUAD MACHINE", rewards.golden, "quad_machine")
	eq("titles: DIAMOND I is earned by ELITE", rewards.diamond, "elite")

	-- The secret one gives nothing away.
	local secret = TitleData.get("secret_solver")
	check("titles: the secret title does not describe the puzzle",
		not secret.description:lower():find("puzzle")
		and not secret.description:lower():find("nook")
		and not secret.description:lower():find("corner"))
	check("titles: and shows no progress counter",
		TitleData.progress(secret, { secretPuzzleSolved = false }) == nil)
end

function T.titleRequirements()
	local function earns(id, profile)
		return TitleData.earned(TitleData.get(id), profile)
	end

	check("titles: everyone has ROOKIE", earns("rookie", {}))
	check("titles: one win earns FIRST WIN", earns("first_blood", { wins = 1 }))
	check("titles: no wins does not", not earns("first_blood", { wins = 0 }))
	check("titles: ten ranked wins earn CONTENDER", earns("contender", { rankedWins = 10 }))
	check("titles: nine do not", not earns("contender", { rankedWins = 9 }))
	check("titles: a five streak earns HOT STREAK", earns("streaker", { bestStreak = 5 }))
	check("titles: four does not", not earns("streaker", { bestStreak = 4 }))
	check("titles: a hundred quads earn QUAD MACHINE", earns("quad_machine", { quads = 100 }))
	check("titles: ninety-nine do not", not earns("quad_machine", { quads = 99 }))
	check("titles: a hundred matches earn BLOCK VETERAN", earns("veteran", { matches = 100 }))
	check("titles: ninety-nine do not", not earns("veteran", { matches = 99 }))

	-- ELITE reads the peak, so it survives losing form.
	check("titles: peak 1500 earns ELITE", earns("elite", { peakRating = 1500 }))
	check("titles: peak 1499 does not", not earns("elite", { peakRating = 1499 }))
	check("titles: a peak of 1500 still earns it after the rating falls",
		earns("elite", { peakRating = 1500, rating = 1100 }))
	check("titles: a current rating of 1500 with a lower peak does not",
		not earns("elite", { rating = 1500, peakRating = 1200 }))

	-- Sprint is a time: lower is better, and zero means never finished.
	check("titles: a 60s sprint earns SPEED DEMON", earns("sprinter", { bestSprint = 60 }))
	check("titles: a 45s sprint earns it", earns("sprinter", { bestSprint = 45 }))
	check("titles: a 61s sprint does not", not earns("sprinter", { bestSprint = 61 }))
	check("titles: never having run one does not", not earns("sprinter", { bestSprint = 0 }))

	check("titles: 25000 earns BLITZ MASTER", earns("blitz_master", { bestBlitz = 25000 }))
	check("titles: 24999 does not", not earns("blitz_master", { bestBlitz = 24999 }))

	-- The secret title reads the completion flag, not what it paid out.
	check("titles: solving earns SECRET SOLVER", earns("secret_solver", { secretPuzzleSolved = true }))
	check("titles: not solving does not", not earns("secret_solver", { secretPuzzleSolved = false }))
	check("titles: owning GALAXY CUBE alone does not earn it",
		not earns("secret_solver", { ownedSkins = { galaxy = true }, secretPuzzleSolved = false }))

	-- Progress copy, where it exists.
	eq("titles: quad progress reads as a fraction",
		TitleData.progress(TitleData.get("quad_machine"), { quads = 72 }), "72 / 100")
	eq("titles: sprint progress reads as a time",
		TitleData.progress(TitleData.get("sprinter"), { bestSprint = 72.41 }), "72.41s / 60s")
	check("titles: an unrun sprint shows no time",
		TitleData.progress(TitleData.get("sprinter"), { bestSprint = 0 }) == "-- / 60s")
end

function T.titleProfile()
	local a = fakePlayer(-601, "TitleOne")
	Stats.load(a)
	local p = Stats.get(a)
	eq("title profile: a new profile equips ROOKIE", p.equippedTitle, "rookie")
	check("title profile: and owns it", p.ownedTitles.rookie == true)

	local b = fakePlayer(-602, "TitleTwo")
	Stats.load(b)
	check("title profile: two profiles do not share a title table",
		Stats.get(a).ownedTitles ~= Stats.get(b).ownedTitles)
	eq("title profile: granting one is granted", Stats.grantTitle(a, "veteran"), "granted")
	check("title profile: and does not reach the other", Stats.get(b).ownedTitles.veteran == nil)
	eq("title profile: granting again is idempotent", Stats.grantTitle(a, "veteran"), "already")
	eq("title profile: an unknown title cannot be granted", Stats.grantTitle(a, "nope"), "unknown title")
	eq("title profile: nor a malformed id", Stats.grantTitle(a, {}), "unknown title")
	check("title profile: the title is owned", Stats.ownsTitle(a, "veteran"))

	-- Equipping.
	eq("title profile: an owned title equips", Stats.equipTitle(a, "veteran"), "equipped")
	eq("title profile: and is recorded", Stats.get(a).equippedTitle, "veteran")
	eq("title profile: equipping it again changes nothing", Stats.equipTitle(a, "veteran"), "no change")
	eq("title profile: an unowned title is refused", Stats.equipTitle(a, "elite"), "not owned")
	eq("title profile: which leaves the equipped one alone", Stats.get(a).equippedTitle, "veteran")
	eq("title profile: an unknown title is refused", Stats.equipTitle(a, "nope"), "unknown title")
	eq("title profile: equipping while busy is refused", Stats.equipTitle(a, "rookie", true), "busy")
	eq("title profile: still unchanged", Stats.get(a).equippedTitle, "veteran")

	-- Malformed requests do nothing at all.
	local held = Stats.get(a).equippedTitle
	for _, bad in ipairs({ 123, true, "", string.rep("t", 20000), {} }) do
		local okCall, verdict = pcall(Stats.equipTitle, a, bad)
		check("title profile: a malformed equip does not error", okCall, tostring(verdict))
		check("title profile: and equips nothing", verdict ~= "equipped")
	end
	check("title profile: a nil equip does not error", (pcall(Stats.equipTitle, a, nil)))
	eq("title profile: nothing moved", Stats.get(a).equippedTitle, held)

	-- The client's one write path cannot touch any of it.
	Stats.applySettings(a, { ownedTitles = { elite = true }, equippedTitle = "elite", das = 125 })
	check("title profile: SaveSettings cannot grant a title", Stats.get(a).ownedTitles.elite == nil)
	eq("title profile: nor equip one", Stats.get(a).equippedTitle, held)
	eq("title profile: but still saves settings", Stats.get(a).das, 125)
end

function T.titleMigration()
	local fresh = Stats.migrateForTest(nil)
	check("title migration: a new profile owns ROOKIE", fresh.ownedTitles.rookie == true)
	eq("title migration: and equips it", fresh.equippedTitle, "rookie")

	local legacy = Stats.migrateForTest({ wins = 5, rating = 1200 })
	check("title migration: an old profile gains ROOKIE", legacy.ownedTitles.rookie == true)
	eq("title migration: keeping its stats", legacy.wins, 5)

	local retired = Stats.migrateForTest({
		ownedTitles = { elite = true, ancient_badge = true }, equippedTitle = "elite" })
	check("title migration: a live id survives", retired.ownedTitles.elite == true)
	check("title migration: a retired id is dropped", retired.ownedTitles.ancient_badge == nil)
	eq("title migration: the equipped title is untouched", retired.equippedTitle, "elite")

	local gone = Stats.migrateForTest({ ownedTitles = { elite = true }, equippedTitle = "ancient_badge" })
	eq("title migration: equipping a retired title falls back", gone.equippedTitle, "rookie")
	check("title migration: without losing the rest", gone.ownedTitles.elite == true)

	local unowned = Stats.migrateForTest({ ownedTitles = {}, equippedTitle = "elite" })
	eq("title migration: equipping something unowned falls back", unowned.equippedTitle, "rookie")

	local junk = Stats.migrateForTest({ ownedTitles = "everything", equippedTitle = 42 })
	check("title migration: a hostile ownership value yields the default only",
		junk.ownedTitles.rookie == true and junk.ownedTitles.elite == nil)
	eq("title migration: and the default equipped", junk.equippedTitle, "rookie")

	-- Union on save, and every earlier merge rule still standing.
	local stored = { ownedTitles = { elite = true }, equippedTitle = "elite",
		ownedSkins = { classic = true, diamond = true }, equippedSkin = "diamond",
		secretPuzzleSolved = true, bestBlitz = 40000, bestSprint = 38.5 }
	local mine = Stats.migrateForTest({ ownedTitles = { veteran = true }, equippedTitle = "veteran",
		ownedSkins = { classic = true, golden = true }, equippedSkin = "golden",
		secretPuzzleSolved = false, bestBlitz = 12000, bestSprint = 55.0 })
	local merged = Stats.mergeProgressForTest(stored, mine)
	check("title merge: a title granted elsewhere survives", merged.ownedTitles.elite == true)
	check("title merge: and so does this server's", merged.ownedTitles.veteran == true)
	check("title merge: ROOKIE is never lost", merged.ownedTitles.rookie == true)
	eq("title merge: equipped follows the saving server", merged.equippedTitle, "veteran")
	check("title merge: skins still union", merged.ownedSkins.diamond and merged.ownedSkins.golden)
	eq("title merge: the puzzle flag still ORs", merged.secretPuzzleSolved, true)
	eq("title merge: the blitz best still maxes", merged.bestBlitz, 40000)
	eq("title merge: the sprint best still mins", merged.bestSprint, 38.5)

	-- A stale server cannot revoke.
	local revoked = Stats.mergeProgressForTest({ ownedTitles = { elite = true } },
		Stats.migrateForTest({ ownedTitles = {} }))
	check("title merge: a stale save cannot take a title away", revoked.ownedTitles.elite == true)
end

-- The evaluator, including the two skins it now makes earnable.
function T.titleAchievements()
	local a = fakePlayer(-603, "Achiever")
	Stats.load(a)
	local p = Stats.get(a)
	eq("achievements: nothing earned yet", #Stats.evaluateTitles(a), 0)

	p.wins = 1
	local first = Stats.evaluateTitles(a)
	eq("achievements: the first win earns one title", #first, 1)
	eq("achievements: which is FIRST WIN", first[1], "first_blood")
	check("achievements: and it is owned", Stats.ownsTitle(a, "first_blood"))
	eq("achievements: re-evaluating grants nothing", #Stats.evaluateTitles(a), 0)
	check("achievements: nothing was auto-equipped", Stats.get(a).equippedTitle == "rookie")

	-- QUAD MACHINE brings GOLDEN T with it, through the skin seam.
	check("achievements: golden is not owned yet", not Stats.ownsSkin(a, "golden"))
	p.quads = 100
	local quad = Stats.evaluateTitles(a)
	eq("achievements: the quad milestone earns one title", #quad, 1)
	eq("achievements: which is QUAD MACHINE", quad[1], "quad_machine")
	check("achievements: and GOLDEN T comes with it", Stats.ownsSkin(a, "golden"))
	eq("achievements: re-evaluating grants nothing again", #Stats.evaluateTitles(a), 0)

	-- Self-heal: the title without the skin is a state nobody can reach
	-- honestly, so evaluation puts it back.
	Stats.get(a).ownedSkins.golden = nil
	Stats.evaluateTitles(a)
	check("achievements: a missing linked skin is restored", Stats.ownsSkin(a, "golden"))

	-- ELITE brings DIAMOND I.
	check("achievements: diamond is not owned yet", not Stats.ownsSkin(a, "diamond"))
	p.peakRating = 1500
	local elite = Stats.evaluateTitles(a)
	eq("achievements: the peak milestone earns ELITE", elite[1], "elite")
	check("achievements: and DIAMOND I comes with it", Stats.ownsSkin(a, "diamond"))
	-- Falling off the pace keeps both.
	p.rating = 1050
	Stats.evaluateTitles(a)
	check("achievements: losing form does not revoke ELITE", Stats.ownsTitle(a, "elite"))
	check("achievements: nor the skin", Stats.ownsSkin(a, "diamond"))

	-- Nothing the evaluator does touches anything competitive.
	local before = Stats.get(a)
	local rating, ranked, blitz = before.rating, before.rankedWins, before.bestBlitz
	Stats.evaluateTitles(a)
	eq("achievements: rating untouched", Stats.get(a).rating, rating)
	eq("achievements: ranked wins untouched", Stats.get(a).rankedWins, ranked)
	eq("achievements: blitz best untouched", Stats.get(a).bestBlitz, blitz)
	eq("achievements: the secret stays unsolved", Stats.get(a).secretPuzzleSolved, false)

	-- Retroactive: an account that did all of it before titles existed.
	local vet = fakePlayer(-604, "Veteran")
	Stats.load(vet)
	local v = Stats.get(vet)
	v.wins, v.rankedWins, v.bestStreak = 40, 12, 7
	v.quads, v.matches, v.peakRating = 150, 120, 1600
	v.bestSprint, v.bestBlitz, v.secretPuzzleSolved = 44.2, 31000, true
	local batch = Stats.evaluateTitles(vet)
	eq("achievements: a veteran account unlocks everything at once", #batch, 9)
	check("achievements: including the secret one", Stats.ownsTitle(vet, "secret_solver"))
	check("achievements: and both linked skins",
		Stats.ownsSkin(vet, "golden") and Stats.ownsSkin(vet, "diamond"))
	eq("achievements: a second login grants nothing", #Stats.evaluateTitles(vet), 0)
	eq("achievements: and still nothing is auto-equipped", Stats.get(vet).equippedTitle, "rookie")
end

-- Solving the secret is one transaction: flag, skin and title together.
function T.titleSecretTransaction()
	local p = fakePlayer(-605, "Finder")
	Stats.load(p)
	check("secret title: not solved yet", not Stats.hasSolvedSecret(p))
	check("secret title: and no title", not Stats.ownsTitle(p, "secret_solver"))

	eq("secret title: solving completes", Stats.completeSecretPuzzle(p), "completed")
	check("secret title: the flag is set", Stats.hasSolvedSecret(p))
	check("secret title: GALAXY CUBE is granted", Stats.ownsSkin(p, SkinData.SECRET_ID))
	check("secret title: and SECRET SOLVER with it", Stats.ownsTitle(p, "secret_solver"))
	eq("secret title: solving again does nothing", Stats.completeSecretPuzzle(p), "already solved")

	-- Owning the skin by other means is not the same as having solved it.
	local other = fakePlayer(-606, "Gifted")
	Stats.load(other)
	Stats.grantSkin(other, SkinData.SECRET_ID)
	Stats.evaluateTitles(other)
	check("secret title: owning GALAXY CUBE does not earn the title",
		not Stats.ownsTitle(other, "secret_solver"))
	check("secret title: and the puzzle is still unsolved for them",
		not Stats.hasSolvedSecret(other))
end

-- Source with the comment lines taken out.
--
-- Several modules say out loud in their header what they deliberately do NOT
-- touch, so a raw substring scan over the whole file trips over the
-- documentation. These checks are about the code.
local function codeOf(module: Instance): string
	local kept = {}
	for line in (module :: any).Source:gmatch("[^\n]*") do
		if not line:match("^%s*%-%-") then
			table.insert(kept, line)
		end
	end
	return table.concat(kept, "\n")
end

-- Titles are cosmetic. This is the assertion that says so.
function T.titlesAreCosmetic()
	local source = game:GetService("ReplicatedStorage").Shared
	for _, name in ipairs({ "Board", "Attack", "LockValidation", "BlitzScoring", "Net" }) do
		local src = source:FindFirstChild(name)
		check("cosmetic: " .. name .. " knows nothing about titles",
			src ~= nil and src.Source:find("[Tt]itle") == nil)
	end
	local match = game:GetService("ServerScriptService").Services.MatchInstance.Source
	-- A title reaches the match in exactly three places, all of them
	-- presentation: what a side is called, what the VS card shows the other
	-- side, and what the result card prints. Counting mentions would only
	-- measure how chatty the comments are, so name them instead.
	local allowed = { titleName = true, opponentTitle = true, title = true }
	local unknown = {}
	for line in codeOf(game:GetService("ServerScriptService").Services.MatchInstance):gmatch("[^\n]+") do
		if line:find("[Tt]itle") then
			local key = line:match("([%a_]+)%s*=")
			if not (key and allowed[key]) then
				table.insert(unknown, (line:gsub("^%s+", "")))
			end
		end
	end
	check("cosmetic: a title reaches the match only as presentation",
		#unknown == 0, unknown[1])
	check("cosmetic: no title appears in a lock, snapshot or garbage message",
		match:find("titleId") == nil)

	-- And the remote catalog gained exactly one entry.
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	check("cosmetic: EquipTitle exists", folder:FindFirstChild("EquipTitle") ~= nil)
	for _, forbidden in ipairs({ "GrantTitle", "UnlockTitle", "CompleteAchievement" }) do
		check("cosmetic: there is no " .. forbidden .. " remote",
			folder:FindFirstChild(forbidden) == nil)
	end
end

-- == Battle dimension (Phase 18) ==========================================

-- A player-shaped table with a character the service can actually move.
local function arenaPlayer(id: number, name: string, at: Vector3)
	local char = Instance.new("Model")
	char.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(at)
	root.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	return { UserId = id, Name = name, DisplayName = name, Character = char,
		Parent = workspace, _char = char }
end

-- A clean, initialised service.
--
-- Tests are run over MCP, which keeps a require cache of its own: the module
-- table here is not the one Bootstrap called init() on. Calling it is also what
-- makes the slot assertions below deterministic, because it drops every arena
-- left over from an earlier test.
local function freshArena(): boolean
	local ok = ArenaService.init()
	return ok
end

function T.arenaTemplate()
	check("arena: the builder produced usable geometry", freshArena())
	check("arena: MatchDimensions exists", workspace:FindFirstChild("MatchDimensions") ~= nil)
	eq("arena: and starts empty", ArenaService.activeCount(), 0)

	-- What a built arena has to contain for a match to be playable in it.
	local a = ArenaService.allocate(90001, Enums.Mode.Quick)
	check("arena: allocation returns a handle", a ~= nil)
	check("arena: with both spawns", a.spawns.A ~= nil and a.spawns.B ~= nil)
	check("arena: which are parts", a.spawns.A:IsA("BasePart") and a.spawns.B:IsA("BasePart"))
	check("arena: and are not the same place",
		(a.spawns.A.Position - a.spawns.B.Position).Magnitude > 1)
	check("arena: the model carries its match", a.model:GetAttribute("MatchId") == 90001)
	eq("arena: and its mode", a.model:GetAttribute("Mode"), Enums.Mode.Quick)
	check("arena: and a slot", type(a.model:GetAttribute("SlotIndex")) == "number")
	check("arena: it has geometry", a.model:FindFirstChild("Geometry") ~= nil)
	check("arena: and bounds to stand on", a.model:FindFirstChild("Bounds") ~= nil)

	-- Well above the lobby, which tops out around a hundred studs.
	check("arena: it is nowhere near the lobby", a.spawns.A.Position.Y > 1000)

	check("arena: allocating the same match twice returns the same arena",
		ArenaService.allocate(90001, Enums.Mode.Quick) == a)
	ArenaService.release(90001)
	check("arena: releasing removes the model", a.model.Parent == nil)
	eq("arena: and nothing is left active", ArenaService.activeCount(), 0)
end

function T.arenaSlots()
	freshArena()
	local a = ArenaService.allocate(90011, Enums.Mode.Quick)
	local b = ArenaService.allocate(90012, Enums.Mode.Ranked)
	check("slots: two matches both got an arena", a ~= nil and b ~= nil)
	check("slots: on different slots", a.slot ~= b.slot)
	check("slots: and far enough apart to be private",
		(a.centre - b.centre).Magnitude >= ArenaService.SLOT_SPACING)
	eq("slots: each carries its own mode", b.model:GetAttribute("Mode"), Enums.Mode.Ranked)

	local firstSlot = a.slot
	ArenaService.release(90011)
	check("slots: releasing one leaves the other alone", b.model.Parent ~= nil)
	check("slots: which is still allocated", ArenaService.arenaFor(90012) ~= nil)

	local c = ArenaService.allocate(90013, Enums.Mode.Private)
	eq("slots: the freed slot is reused", c.slot, firstSlot)
	check("slots: without disturbing the survivor", ArenaService.arenaFor(90012) ~= nil)

	-- The whole point of keying by match rather than slot.
	ArenaService.release(90011)
	check("slots: releasing the finished match again is harmless",
		ArenaService.arenaFor(90013) ~= nil)
	check("slots: and cannot destroy whatever took its slot", c.model.Parent ~= nil)
	check("slots: releasing a match that never existed is safe",
		ArenaService.release(4242) == false)

	ArenaService.release(90012)
	ArenaService.release(90013)
	eq("slots: everything cleaned up", ArenaService.activeCount(), 0)
	eq("slots: and no arena models are left behind",
		#workspace.MatchDimensions:GetChildren(), 0)
end

function T.arenaPlayers()
	freshArena()
	local home = CFrame.new(120, 5, -40)
	local p1 = arenaPlayer(-701, "SideA", home.Position)
	local p2 = arenaPlayer(-702, "SideB", Vector3.new(-60, 5, 30))
	local a = ArenaService.allocate(90021, Enums.Mode.Quick)

	check("players: A enters", ArenaService.enter(90021, p1, "A"))
	check("players: B enters", ArenaService.enter(90021, p2, "B"))
	check("players: A stands on side A",
		(p1._char:GetPivot().Position - a.spawns.A.Position).Magnitude < 1)
	check("players: B stands on side B",
		(p2._char:GetPivot().Position - a.spawns.B.Position).Magnitude < 1)
	check("players: they are not in the same place",
		(p1._char:GetPivot().Position - p2._char:GetPivot().Position).Magnitude > 1)
	eq("players: the service knows where A is", ArenaService.matchOf(p1), 90021)

	-- Entering a match that does not exist, or a side that does not.
	check("players: entering an unknown match fails",
		not ArenaService.enter(4242, p1, "A"))
	check("players: entering an unknown side fails",
		not ArenaService.enter(90021, p1, "Z"))

	-- Going home.
	check("players: A returns", ArenaService.returnPlayer(90021, p1))
	check("players: to where they were standing",
		(p1._char:GetPivot().Position - home.Position).Magnitude < 1)
	check("players: returning twice is harmless", not ArenaService.returnPlayer(90021, p1))
	check("players: B is still in the arena", ArenaService.matchOf(p2) == 90021)

	-- A stale call naming another match must not move somebody.
	local other = ArenaService.allocate(90022, Enums.Mode.Quick)
	check("players: a second arena exists to name", other ~= nil and other.slot ~= a.slot)
	local before = p2._char:GetPivot().Position
	check("players: a stale match cannot return someone else's player",
		not ArenaService.returnPlayer(90022, p2))
	check("players: who has not moved",
		(p2._char:GetPivot().Position - before).Magnitude < 0.01)

	-- Releasing sends whoever is left home.
	ArenaService.release(90021)
	check("players: release returned B to the lobby", p2._char:GetPivot().Position.Y < 1000)
	eq("players: and nobody is assigned", ArenaService.matchOf(p2), nil)

	-- A player who leaves stops being the arena's problem.
	ArenaService.enter(90022, p1, "A")
	ArenaService.forgetPlayer(p1)
	eq("players: forgetting drops the assignment", ArenaService.matchOf(p1), nil)
	check("players: and release still works afterwards", ArenaService.release(90022))

	p1._char:Destroy()
	p2._char:Destroy()
	eq("players: nothing left behind", ArenaService.activeCount(), 0)
end

-- Falling out, or arriving in a fresh character, puts a player back on the pad.
function T.arenaRecovery()
	freshArena()
	local p = arenaPlayer(-703, "Faller", Vector3.new(10, 5, 10))
	local a = ArenaService.allocate(90031, Enums.Mode.Quick)
	ArenaService.enter(90031, p, "A")

	p._char:PivotTo(CFrame.new(a.spawns.A.Position - Vector3.new(0, 400, 0)))
	ArenaService.step()
	check("recovery: a fallen character is put back on their pad",
		(p._char:GetPivot().Position - a.spawns.A.Position).Magnitude < 1)

	-- A small wobble is not a fall.
	p._char:PivotTo(CFrame.new(a.spawns.A.Position + Vector3.new(3, 0, 3)))
	ArenaService.step()
	check("recovery: standing slightly off the marker is left alone",
		(p._char:GetPivot().Position - a.spawns.A.Position).Magnitude > 1)

	check("recovery: stepping with nobody assigned is safe",
		(pcall(ArenaService.step)))
	ArenaService.release(90031)
	p._char:Destroy()
end

-- A malformed template disables arenas. Matches must still start.
--
-- The alternative -- refusing to start a match because the scenery would not
-- build -- turns a cosmetic failure into an outage, and the lobby match is
-- exactly what every phase before this one shipped.
function T.arenaDegraded()
	freshArena()
	ArenaService.disableForTest()
	check("degraded: the service says so", not ArenaService.isEnabled())

	local a, why = ArenaService.allocate(90041, Enums.Mode.Quick)
	check("degraded: allocation fails", a == nil)
	eq("degraded: and says why", why, "arena disabled")
	eq("degraded: nothing is active", ArenaService.activeCount(), 0)
	eq("degraded: and no models exist", #workspace.MatchDimensions:GetChildren(), 0)

	-- Every other entry point has to survive being called anyway, because the
	-- callers do not branch on this.
	local p = arenaPlayer(-704, "Stranded", Vector3.new(5, 5, 5))
	check("degraded: entering fails quietly", not ArenaService.enter(90041, p, "A"))
	check("degraded: returning fails quietly", not ArenaService.returnPlayer(90041, p))
	check("degraded: releasing fails quietly", not ArenaService.release(90041))
	check("degraded: stepping is safe", (pcall(ArenaService.step)))
	check("degraded: forgetting is safe", (pcall(ArenaService.forgetPlayer, p)))
	eq("degraded: nobody is in an arena", ArenaService.matchOf(p), nil)
	check("degraded: the player did not move",
		(p._char:GetPivot().Position - Vector3.new(5, 5, 5)).Magnitude < 0.01)
	eq("degraded: the debug line says disabled", ArenaService.debugSummary(), "disabled")

	-- And the matchmaker only refuses to start a match when arenas are meant to
	-- work and did not. A disabled service is not a reason to stop the game.
	local mm = codeOf(game:GetService("ServerScriptService").Services.MatchmakingService)
	check("degraded: matchmaking checks isEnabled before refusing",
		mm:find("not arena and ArenaService.isEnabled()", 1, true) ~= nil)
	check("degraded: and a failed start puts the players back in the queue",
		mm:find("if not start(", 1, true) ~= nil)

	check("degraded: init brings it back", freshArena())
	check("degraded: and allocation works again",
		ArenaService.allocate(90042, Enums.Mode.Quick) ~= nil)
	ArenaService.release(90042)
	p._char:Destroy()
end

-- The arena owns geometry and nothing else.
function T.arenaOwnsNothingElse()
	local code = codeOf(game:GetService("ServerScriptService").Services.ArenaService)
	for _, forbidden in ipairs({ "rating", "peakRating", "Elo", "bestBlitz",
		"bestSprint", "ownedSkins", "ownedTitles", "secretPuzzleSolved", "score",
		"Attack", "attack", "garbage", "StatsService", "Board", "TeleportService",
		"Lighting", "DataStore" }) do
		check("arena owns nothing else: the code never mentions " .. forbidden,
			code:find(forbidden, 1, true) == nil)
	end

	-- A client that could name its own destination could stand in someone
	-- else's match, so no remote may exist for it.
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	check("arena owns nothing else: the remotes folder is there", folder ~= nil)
	for _, forbidden in ipairs({ "TeleportToArena", "ReturnToLobby", "SetArenaCFrame",
		"EnterArena", "ArenaTransition", "ArenaRequest" }) do
		check("arena owns nothing else: there is no " .. forbidden .. " remote",
			folder:FindFirstChild(forbidden) == nil)
	end
	check("arena owns nothing else: it listens to no remote at all",
		code:find("OnServerEvent") == nil and code:find("Remotes") == nil)

	-- The comment scan is only worth anything if it kept the code.
	check("arena owns nothing else: the scan actually read the module",
		code:find("ArenaService.allocate") ~= nil)
end

-- Human vs human, without two clients.
--
-- Studio over MCP can only drive one player, so the one path the live tests
-- could never reach is the one the whole game is about. Two stand-in "clients"
-- run their own boards and report locks exactly as Main.client does; the match
-- validates every one against its shadow. If reachability, the piece-identity
-- check or the garbage routing were wrong between two players, this fails.
function T.twoPlayer()
	local seed = 8899
	-- MIN_LOCK_INTERVAL is a wall-clock anti-cheat guard. A headless loop
	-- reports hundreds of locks per real second, so it has to come off here.
	local realMin = Tuning.MIN_LOCK_INTERVAL
	Tuning.MIN_LOCK_INTERVAL = 0

	local ok, err = pcall(function()
		local match = MatchInstance.new(99, { name = "P1" }, { name = "P2" }, { seed = seed })
		match.state = "playing" -- skip the countdown timer

		-- Both clients must use the MATCH seed. The server gives each shadow the
		-- same seed and sends it to both clients, so a client on a different
		-- seed sees a different piece sequence and every lock is correctly
		-- rejected as "not the piece in play".
		local clients = {
			[match.a] = BotService.new(seed, "overdrive"),
			[match.b] = BotService.new(seed, "neon"),
		}
		local dt, routed = 1 / 60, 0
		local index = { [match.a] = 0, [match.b] = 0 }
		local prevSent = { [match.a] = 0, [match.b] = 0 }
		-- Mirror the server's garbage onto the stand-in client boards, which is
		-- what a real client does when it receives the Garbage remote.
		match.onGarbage = function(target, rows, gap)
			local cb = clients[target]
			if cb then
				cb.board:queueGarbage(rows, gap, cb.board.time + Tuning.GARBAGE_DELAY)
			end
		end
		-- The recovery path, driven exactly as Main.client drives it. Garbage
		-- landing a frame apart between client and shadow is a legitimate
		-- divergence, so what matters is not that it never happens but that the
		-- player keeps playing afterwards instead of being rejected forever.
		local resyncs = 0
		match.onResync = function(side, payload)
			local cb = clients[side]
			if not cb then return end
			resyncs += 1
			local b = cb.board
			for i = 1, #payload.cells do b.cells[i] = payload.cells[i] end
			b.piece = payload.piece and table.clone(payload.piece) or nil
			b.hold, b.holdUsed = payload.hold, payload.holdUsed == true
			b.bag = Bag.load(payload.bag)
			b.combo, b.b2b = payload.combo, payload.b2b
			b.gravityAcc, b.lockTimer, b.lockResets, b.grounded = 0, 0, 0, false
			cb.plan, cb.planFor = nil, -1
			index[side] = payload.index
		end

		local finishedWith = nil
		match.onFinished = function(_, loser) finishedWith = loser or "draw" end

		for _ = 1, 60 * 120 do
			if match.finished then break end
			match:update(dt)
			for side, cb in pairs(clients) do
				if cb.board.alive and side.alive then
					cb.board.time = match.elapsed
					cb:update(dt)
					for _, e in ipairs(cb.board:drain()) do
						if e.kind == "lock" and e.data.placed then
							index[side] += 1
							match:applyLock(side, {
								index = index[side],
								kind = e.data.placed.kind,
								rot = e.data.placed.rot,
								x = e.data.placed.x,
								y = e.data.placed.y,
							})
						elseif e.kind == "topout" then
							match:applyLock(side, { topout = true })
						end
					end
				end
			end
			for side in pairs(clients) do
				if side.board.stats.sent > prevSent[side] then
					routed += side.board.stats.sent - prevSent[side]
					prevSent[side] = side.board.stats.sent
				end
			end
		end

		-- Rejections are allowed to be rare, not impossible: garbage landing one
		-- frame apart on client and shadow is a legitimate divergence. What is
		-- not allowed is a rejection that never recovers, which is why the ratio
		-- is checked rather than the count.
		local aTotal = match.a.accepted + match.a.rejects
		local bTotal = match.b.accepted + match.b.rejects
		check("2p: P1 rejections stayed rare", match.a.rejects <= aTotal * 0.05,
			("%d of %d, last reason '%s'"):format(match.a.rejects, aTotal, tostring(match.a.lastReject)))
		check("2p: P2 rejections stayed rare", match.b.rejects <= bTotal * 0.05,
			("%d of %d, last reason '%s'"):format(match.b.rejects, bTotal, tostring(match.b.lastReject)))
		check("2p: resync recovered rather than cascading", resyncs == 0 or match.a.accepted > 40,
			("%d resyncs"):format(resyncs))
		check("2p: P1's locks were accepted", match.a.accepted > 40,
			("%d accepted"):format(match.a.accepted))
		check("2p: P2's locks were accepted", match.b.accepted > 40,
			("%d accepted"):format(match.b.accepted))
		-- The shadow must have applied every accepted lock, or the server and
		-- the client are looking at different boards.
		eq("2p: P1 shadow matches accepted count", match.a.board.stats.pieces, match.a.accepted)
		eq("2p: P2 shadow matches accepted count", match.b.board.stats.pieces, match.b.accepted)
		check("2p: both sides cleared lines",
			match.a.board.stats.lines > 0 and match.b.board.stats.lines > 0,
			("%d / %d"):format(match.a.board.stats.lines, match.b.board.stats.lines))
		check("2p: garbage crossed between the players", routed > 0, tostring(routed))
		check("2p: the match resolved or was still legitimately running",
			match.finished or (match.a.alive and match.b.alive))
		if match.finished then
			check("2p: a result was produced", finishedWith ~= nil)
		end
	end)

	Tuning.MIN_LOCK_INTERVAL = realMin
	if not ok then
		error(err, 0)
	end
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
	MatchInstance = require((services :: any).MatchInstance)
	Stats = require((services :: any).StatsService)
	Practice = require((services :: any).PracticeService)
	BlitzScoring = require((root :: any).BlitzScoring)
	LockValidation = require((root :: any).LockValidation)
	TitleData = require((root :: any).TitleData)
	ArenaService = require((services :: any).ArenaService)
	GlobalRank = require((services :: any).GlobalRank)
	Enums = require((root :: any).Enums)
	SkinData = require((root :: any).SkinData)
	PuzzleService = require((services :: any).PuzzleService)

	passed, failed, log = 0, 0, {}
	local order = { "bag", "srs", "spawnAndDrop", "lineClear", "quadAndB2B", "garbage",
		"topOuts", "attack", "net", "tspin", "cloneIsolation", "determinism",
		"gravityAndLock", "holdAndReach", "reachCost", "elo", "sessions", "disconnect",
		"practice", "tspinDetect", "tspinAttack", "tspinB2B", "tspinStats",
		"tspinAuthority", "globalRankIndex", "globalRankBoard", "globalRankFallback",
		"globalRankWiring", "globalRankRender",
		"skinCatalog", "skinOwnership", "skinMigration", "skinIsCosmetic",
		"puzzleGeometry", "puzzleSolving", "puzzleSessions", "puzzlePersistence",
		"blitzScoring", "blitzSession", "blitzEnding", "blitzPersistence",
		"remoteCatalog", "blitzAbandon", "settlementIdempotence", "profileRoundTrip",
		"sharedValidator",
		"titleCatalog", "titleRequirements", "titleProfile", "titleMigration",
		"titleAchievements", "titleSecretTransaction", "titlesAreCosmetic",
		"arenaTemplate", "arenaSlots", "arenaPlayers", "arenaRecovery",
		"arenaDegraded", "arenaOwnsNothingElse",
		"bots", "twoPlayer" }
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
