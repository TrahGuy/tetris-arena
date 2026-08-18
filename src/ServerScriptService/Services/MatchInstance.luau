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
--
-- Every message in and out of a match names the match it belongs to. Matches
-- are back to back — rematch, requeue — and a lock, a forfeit or a garbage line
-- still in flight from the last one has no business landing on the next.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Board = require(Shared.Board)
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)
local Attack = require(Shared.Attack)
local Net = require(Shared.Net)
local LockValidation = require(Shared.LockValidation)
local Remotes = require(Shared.Remotes)
local BotService = require(script.Parent.BotService)

local MatchInstance = {}
MatchInstance.__index = MatchInstance

local MISMATCHES_BEFORE_RESYNC = 3
local SNAPSHOT_CELLS = Tuning.WIDTH * Tuning.VISIBLE

-- The Player still on the other end of a side, or nil.
--
-- A side keeps its Player after a disconnect, because the result is recorded
-- against it and someone who walks out of a ranked match owes the rating. The
-- `left` flag is what stops anything being fired at a client that has gone.
local function client(side: any): Player?
	if side.left then return nil end
	local p = side.player
	return (p and p.Parent) and p or nil
end

local function makeSide(spec: any, seed: number)
	local side = {
		player = spec.player,
		-- spec.name lets a side exist without a Player behind it, which is what
		-- makes a two-player match testable without two clients.
		name = spec.name or (spec.player and spec.player.DisplayName) or nil,
		-- Cosmetic, for the opponent's VS card. Nothing reads it again.
		titleName = spec.titleName,
		alive = true,
		left = false,
		lastIndex = 0,
		lastLockAt = 0,
		mismatches = 0,
		rejects = 0,
		accepted = 0,
		badSnapshots = 0,
		lastReject = "",
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
		snapTimer = 0,
	}, MatchInstance)

	self.a = makeSide(specA, seed)
	self.b = makeSide(specB, seed)
	self.a.other, self.b.other = self.b, self.a

	for _, side in ipairs({ self.a, self.b }) do
		local p = client(side)
		if p then
			Remotes.MatchUpdate:FireClient(p, {
				state = Enums.State.Countdown,
				matchId = id,
				seed = seed,
				mode = self.mode,
				opponent = side.other.name,
				-- Presentation for the VS card, set by Matchmaking before the
				-- match starts. Cosmetic: nothing downstream reads it.
				opponentTitle = side.other.titleName,
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
		return ("%s[ok %d rej %d%s%s p%d L%d%s%s%s]"):format(
			tostring(side.name),
			side.accepted, side.rejects,
			side.badSnapshots > 0 and (" bad " .. side.badSnapshots) or "",
			side.lastReject ~= "" and (" '" .. side.lastReject .. "'") or "",
			side.board.stats.pieces, side.board.stats.lines,
			-- Spins the SERVER derived, which is the number worth watching: it
			-- is what the attack was actually paid on.
			side.board.stats.tspins > 0 and (" T" .. side.board.stats.tspins) or "",
			side.alive and "" or " DEAD",
			side.left and " LEFT" or "")
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
		matchId = self.id,
		cells = b.cells,
		piece = b.piece and table.clone(b.piece) or nil,
		hold = b.hold,
		holdUsed = b.holdUsed,
		bag = b.bag:save(),
		combo = b.combo,
		b2b = b.b2b,
		index = side.lastIndex,
	}
	local p = client(side)
	if p then
		Remotes.Resync:FireClient(p, payload)
	end
	if self.onResync then
		self.onResync(side, payload)
	end
	side.mismatches = 0
end

-- Does this message belong to this match?
--
-- Without the check, a lock still in flight from the previous match lands on
-- the next one. A fresh match starts its lock index at zero, so the mildest
-- outcome is a spurious resync — and the worst is a stale `topout` ending a
-- game that had barely started.
function MatchInstance:ownsMessage(msg: any): boolean
	return type(msg) == "table" and tonumber(msg.matchId) == self.id
end

-- The untrusted boundary. Everything a client sends arrives here; applyLock is
-- the internal path bots and tests drive directly.
function MatchInstance:onLock(player: Player, msg: any)
	if not self:ownsMessage(msg) then return end
	local side = self:sideFor(player)
	if not side or side.left then return end
	self:applyLock(side, msg)
end

-- Split from onLock so a side can be driven without a Player attached.
function MatchInstance:applyLock(side: any, msg: any)
	if self.finished or type(msg) ~= "table" then return end

	-- The client's own view of its board. It is never forwarded to anyone — see
	-- _publishSnapshots — and exists only so the server can tell whether the two
	-- boards have drifted apart.
	if msg.snapshot ~= nil then
		if not Net.isValidBoard(msg.snapshot, SNAPSHOT_CELLS) then
			-- Wrong type, wrong length, or cells the game cannot produce. There
			-- is nothing here to compare against and a resync would not fix
			-- whatever produced it, so it is counted and dropped.
			side.badSnapshots += 1
			side.lastReject = "malformed snapshot"
			if side.badSnapshots % 20 == 1 then
				warn(("[Match %d] discarded a malformed snapshot from %s"):format(
					self.id, tostring(side.name)))
			end
			return
		end
		local mine = Net.packBoard(side.board:snapshot())
		local ok = true
		for i = 0, buffer.len(mine) - 1 do
			if buffer.readu8(mine, i) ~= buffer.readu8(msg.snapshot, i) then
				ok = false
				break
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
		-- Only while the match is actually running. A top-out reported during
		-- the countdown or after the result is either stale or a client ending
		-- a game it is not playing.
		if self.state == Enums.State.Playing and side.alive then
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

	-- Shared with the solo Blitz shadow, so a ranked placement and a score-attack
	-- placement are judged by one piece of code rather than two that agree today.
	local b = side.board
	local ok, why = LockValidation.accept(b, msg)
	if not ok then
		return self:_reject(side, why)
	end

	side.lastIndex = index
	side.lastLockAt = now
	side.accepted += 1
	b.time = self.elapsed
	b:lock()
	LockValidation.respawn(b)
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
	local p = client(target)
	if p then
		Remotes.Garbage:FireClient(p, { matchId = self.id, rows = rows, gapCol = gap })
	end
	-- Same information the client gets, for anything else that needs it — the
	-- two-player test mirrors it onto its stand-in client boards.
	if self.onGarbage then
		self.onGarbage(target, rows, gap)
	end
end

-- ── Loop ──────────────────────────────────────────────────────────────────

-- Each player's view of the other is drawn from the shadow board, never
-- forwarded from the client that owns it.
--
-- It costs no freshness: cells only move when a piece locks or garbage lands,
-- and the shadow does both at the same moments the real board does. What it
-- buys is that nobody can draw whatever they like on their opponent's screen —
-- or hide their stack by simply not sending. Bots never had a client to forward
-- from in the first place, so this is now one path instead of two.
--
-- `incoming` is the server's own count of charged garbage, for the same reason.
function MatchInstance:_publishSnapshots()
	for _, side in ipairs({ self.a, self.b }) do
		local watcher = client(side.other)
		if watcher then
			Remotes.Snapshot:FireClient(watcher, Net.packBoard(side.board:snapshot()), {
				matchId = self.id,
				incoming = Attack.pending(side.board.incoming),
			})
		end
	end
end

function MatchInstance:update(dt: number)
	if self.finished or self.state ~= Enums.State.Playing then return end
	self.elapsed += dt
	self.a.board.time = self.elapsed
	self.b.board.time = self.elapsed

	for _, side in ipairs({ self.a, self.b }) do
		if side.bot and side.alive then
			side.bot:update(dt)
			self:_drain(side)
		end
	end

	self.snapTimer += dt
	if self.snapTimer >= 1 / Tuning.SNAPSHOT_HZ then
		self.snapTimer = 0
		self:_publishSnapshots()
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
				local p = client(side)
				if p then
					Remotes.Garbage:FireClient(p, { matchId = self.id, rows = 1, gapCol = gap })
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

-- The Player reference deliberately survives a disconnect. Clearing it here was
-- why leaving a ranked match cost nothing: recordMatch finds the profile that
-- owes the loss through this field, so by the time it ran there was nobody left
-- to charge, and the rating hit the comment there promises never happened. The
-- `left` flag is what stops anything being fired at them. It holds a departed
-- Player for at most RESULTS_TIME, until the match drops out of the list.
function MatchInstance:playerLeft(player: Player)
	local side = self:sideFor(player)
	if not side or self.finished then return end
	side.alive = false
	side.left = true
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

	-- Stats and rating are settled before the results go out, so the card can
	-- show what this match did to a rating rather than what it was worth
	-- beforehand. Guarded: a stats failure must not cost both players their
	-- result screen as well.
	if self.onFinished then
		local ok, err = pcall(self.onFinished, self, loser, reason)
		if not ok then
			warn(("[Match %d] finish handler failed: %s"):format(self.id, tostring(err)))
		end
	end

	for _, side in ipairs({ self.a, self.b }) do
		local p = client(side)
		if p then
			local outcome
			if loser == nil then
				outcome = Enums.Result.Draw
			elseif side == loser then
				outcome = Enums.Result.Loss
			else
				outcome = Enums.Result.Win
			end
			Remotes.Result:FireClient(p, {
				matchId = self.id,
				outcome = outcome,
				reason = reason,
				stats = statsOf(side),
				opponent = side.other.name,
				-- Both set by recordMatch. The title is presentation carried on
				-- the result message only; nothing about it reaches the
				-- simulation, and no other match packet mentions it.
				title = side.title,
				elo = side.elo,
				rating = side.elo and side.elo.after or nil,
				-- Nothing to rematch against if the other side walked out.
				canRematch = reason ~= Enums.Result.Left,
			})
		end
	end
end

return MatchInstance
