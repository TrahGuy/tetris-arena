-- Practice runs: the server issues them and vets what comes back.
--
-- Nobody is opposing you in practice, so there is nothing to cheat at except
-- the record — and a sprint time and a lines total both land on the leaderboard
-- tower. The client used to be believed outright: one hand-written remote call
-- was a 0.001-second sprint and a lines counter of whatever you typed.
--
-- The server cannot replay a run without simulating it, so it does the next
-- best thing and checks the claim against limits it can prove:
--
--   * it knows when it handed out the seed, so the wall clock since then is the
--     most the run can honestly have taken — and, within a round trip, the
--     least as well;
--   * pieces cannot be placed faster than MAX_PPS on average;
--   * a cleared row is ten cells and a piece is four, so a run cannot have
--     cleared more than two fifths of a line per piece placed;
--   * a sprint stops at SPRINT_GOAL lines, so no run can be worth more.
--
-- What survives all four is a claim consistent with the time the player
-- actually spent in a session the server opened. That is the honest ceiling
-- without input replay: a cheater can still claim any run they could have
-- played, but not one they could not have.

-- Blitz is different, and deliberately so. A two-minute score attack has a
-- number worth cheating for and a deadline worth lying about, so it does not
-- get the treatment above: the server keeps a shadow board, validates every
-- placement through the same LockValidation a ranked match uses, derives the
-- clear itself and scores it. The client reports where it put a piece and
-- nothing else. Sprint keeps the vetted-claim path, because rewriting a working
-- mode to prove a point is how working modes stop working.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)
local Board = require(Shared.Board)
local BlitzScoring = require(Shared.BlitzScoring)
local LockValidation = require(Shared.LockValidation)

local PracticeService = {}

-- How much of the wall clock may go unaccounted for before the client's own
-- timer stops being believed. The client starts counting when the seed lands,
-- so a round trip plus the first frame is the honest gap.
PracticeService.CLOCK_GRACE = 1.5

local sessions: { [number]: any } = {}
local nextId = 0

local function finite(v: any): number?
	local n = tonumber(v)
	if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
	return n
end

local function count(v: any): number
	local n = finite(v)
	if not n or n < 0 then return 0 end
	return math.floor(n)
end

-- Pure, so the rules can be tested without a Player, a session or a DataStore.
-- Returns the record to credit, or nil and why it was thrown out.
function PracticeService.vet(session: any, msg: any, now: number): (any?, string?)
	if type(session) ~= "table" then return nil, "no session" end
	if type(msg) ~= "table" then return nil, "malformed" end
	if tonumber(msg.sessionId) ~= session.id then return nil, "wrong session" end

	local elapsed = now - session.startedAt
	if elapsed <= 0 then return nil, "clock went backwards" end

	local stats = (type(msg.stats) == "table") and msg.stats or {}
	local pieces = math.min(count(stats.pieces), math.floor(elapsed * Tuning.MAX_PPS) + 1)
	local lines = math.min(count(stats.lines), math.floor(pieces * 0.4), Tuning.SPRINT_GOAL)

	-- The client's clock is preferred when it agrees with the server's window,
	-- because it is the number the player was shown and it excludes the round
	-- trip. Claiming a time the server did not measure — the whole point of
	-- stalling and then reporting a fast run — falls back to the wall clock.
	local claimed = finite(msg.time)
	local time = elapsed
	if claimed and claimed <= elapsed and claimed >= elapsed - PracticeService.CLOCK_GRACE then
		time = claimed
	end

	return {
		mode = session.mode,
		lines = lines,
		pieces = pieces,
		time = time,
		sprint = session.mode == Enums.Mode.Sprint and lines >= Tuning.SPRINT_GOAL,
	}
end

local function resolveMode(mode: any): string
	if mode == Enums.Mode.Sprint then return Enums.Mode.Sprint end
	if mode == Enums.Mode.Blitz then return Enums.Mode.Blitz end
	return Enums.Mode.Practice
end

-- One live session per player. Starting another abandons the first, which is
-- also what stops two runs being reported against one stretch of wall clock --
-- and, for Blitz, what makes PLAY AGAIN a genuinely new run rather than a
-- second attempt at the same one.
--
-- `serverNow` is workspace:GetServerTimeNow(), the clock both ends share. Blitz
-- start and end are decided here and sent out, so a slow round trip costs the
-- player nothing and a fast one buys them nothing.
function PracticeService.begin(player: Player, mode: any, now: number, serverNow: number?): any
	nextId += 1
	local session = {
		id = nextId,
		seed = math.random(1, 2 ^ 31 - 1),
		mode = resolveMode(mode),
		startedAt = now,
		userId = player.UserId,
		player = player,
	}
	if session.mode == Enums.Mode.Blitz then
		serverNow = serverNow or now
		session.board = Board.new(session.seed)
		session.startAt = serverNow + Tuning.COUNTDOWN
		session.endAt = session.startAt + Tuning.BLITZ_TIME
		session.score = 0
		session.lastIndex = 0
		session.lastLockAt = 0
		session.bestCombo = 0
		session.finished = false
	end
	sessions[player.UserId] = session
	return session
end

function PracticeService.sessionFor(player: Player): any?
	return sessions[player.UserId]
end

-- True while a solo run is in progress, which is what the secret nook asks
-- before it lets anyone reserve it: a player two minutes into a score attack is
-- not idle in the lobby.
function PracticeService.isBusy(player: Player): boolean
	local s = sessions[player.UserId]
	return s ~= nil and s.mode == Enums.Mode.Blitz and not s.finished
end

-- == Blitz ================================================================

-- The result of a run, built from the shadow board and nothing else.
--
-- `counts` is what decides whether this can become a personal best. A run ends
-- for three reasons and only two of them are a run played out: the timer
-- expiring and topping out. Abandoning means the player walked away, and a
-- score that only counts when you like the look of it is not a score.
local function buildResult(session: any, reason: string): any
	local st = session.board.stats
	return {
		mode = Enums.Mode.Blitz,
		sessionId = session.id,
		reason = reason,
		score = session.score,
		lines = st.lines,
		pieces = st.pieces,
		quads = st.quads,
		tspins = st.tspins,
		bestCombo = session.bestCombo,
		counts = reason == "time" or reason == "topout",
	}
end

-- Ends a Blitz run once. Returns the result, or nil when there was nothing to
-- end -- so calling it twice is harmless, which matters because the timer, a
-- top-out and a disconnect can all race for the same run.
function PracticeService.finalize(player: Player, reason: string): any?
	local session = sessions[player.UserId]
	if not session or session.mode ~= Enums.Mode.Blitz or session.finished then
		return nil
	end
	session.finished = true
	return buildResult(session, reason)
end

-- Called every tick. The server ends Blitz on its own clock: a client that
-- stops talking, crashes, or is simply told to stop sending does not get to
-- leave a run open, and nothing has to be reported for the deadline to arrive.
function PracticeService.step(serverNow: number): { any }
	local done = {}
	for _, session in pairs(sessions) do
		if session.mode == Enums.Mode.Blitz and not session.finished
			and session.endAt and serverNow >= session.endAt then
			session.finished = true
			table.insert(done, {
				player = session.player,
				result = buildResult(session, "time"),
			})
		end
	end
	return done
end

-- A reported placement in a Blitz run.
--
-- Returns a verdict and, when something happened worth telling the client
-- about, a payload. Every competitive number in that payload is derived here
-- from the server board; the message is read for where the piece went and for
-- nothing else at all.
function PracticeService.onLock(player: Player, msg: any, serverNow: number): (string, any?)
	if type(msg) ~= "table" then return "malformed" end
	local session = sessions[player.UserId]
	if not session or session.mode ~= Enums.Mode.Blitz then return "no session" end
	if session.finished then return "finished already" end
	-- Solo runs are addressed by session, matches by match. A message carrying
	-- both is not one either of them should act on.
	if msg.matchId ~= nil then return "wrong address" end
	if tonumber(msg.sessionId) ~= session.id then return "wrong session" end

	if msg.topout then
		session.finished = true
		return "finished", buildResult(session, "topout")
	end

	-- The deadline belongs to the server. A placement arriving after it is late
	-- whatever the client believes, and it cannot add a point.
	if serverNow >= session.endAt then
		session.finished = true
		return "finished", buildResult(session, "time")
	end
	if serverNow < session.startAt then return "not started" end

	local index = tonumber(msg.index)
	if index ~= session.lastIndex + 1 then return "out of order index" end
	if serverNow - session.lastLockAt < Tuning.MIN_LOCK_INTERVAL then
		return "too fast"
	end

	local board = session.board
	local ok, why = LockValidation.accept(board, msg)
	if not ok then return why end

	session.lastIndex = index
	session.lastLockAt = serverNow
	board.time = serverNow - session.startAt
	board:lock()

	local delta = 0
	local topped = false
	for _, e in ipairs(board:drain()) do
		if e.kind == "lock" and e.data.info then
			-- BlitzScoring reads the ClearInfo the board produced: lines, spin,
			-- back-to-back, combo and perfect clear are all its verdict.
			delta += BlitzScoring.score(e.data.info)
			local combo = e.data.info.combo or 0
			if combo > session.bestCombo then session.bestCombo = combo end
		elseif e.kind == "topout" then
			topped = true
		end
	end
	session.score += delta
	LockValidation.respawn(board)

	if topped or not board.alive then
		session.finished = true
		return "finished", buildResult(session, "topout")
	end
	if delta > 0 then
		return "score", {
			sessionId = session.id,
			score = session.score,
			delta = delta,
			lines = board.stats.lines,
		}
	end
	return "placed"
end

-- One line per live solo run, for the Debug attributes. A running server shares
-- nothing else with the command bar.
function PracticeService.debugSummary(serverNow: number): string
	local parts = {}
	for _, s in pairs(sessions) do
		if s.mode == Enums.Mode.Blitz then
			table.insert(parts, ("#%d %s score %d p%d L%d %.1fs%s"):format(
				s.id, tostring(s.player and s.player.Name), s.score,
				s.board.stats.pieces, s.board.stats.lines,
				math.max(0, s.endAt - serverNow), s.finished and " DONE" or ""))
		else
			table.insert(parts, ("#%d %s"):format(s.id, tostring(s.mode)))
		end
	end
	return #parts > 0 and table.concat(parts, "  ||  ") or "idle"
end

-- == Training zone entry ==================================================

-- The Training Zone was built with one pad, wired to Sprint. Blitz needs its
-- own front door, because the lobby pads are how this game starts anything.
--
-- Created here rather than in build/lobby/04_zones.luau for the same reason the
-- museum pads are: a live place picks it up without the world being rebuilt,
-- and it is idempotent, so booting twice changes nothing. Sized and coloured
-- from the Sprint pad beside it so the pair reads as one station.
function PracticeService.wirePads(training: Instance?): boolean
	if not training then return false end
	local sprintPad = training:FindFirstChild("Pad_practice")
	if not sprintPad then return false end

	local at = sprintPad.Position + Vector3.new(sprintPad.Size.X + 4, 0, 0)
	local accent = Color3.fromRGB(226, 60, 190)

	local pad = training:FindFirstChild("Pad_blitz")
	local fresh = pad == nil
	if fresh then
		pad = Instance.new("Part")
		pad.Name = "Pad_blitz"
		pad.Anchored = true
		pad.Size = sprintPad.Size
		pad.Material = Enum.Material.SmoothPlastic
		pad.Color = accent:Lerp(Color3.new(0, 0, 0), 0.72)
		pad.Position = at
	end
	pad:SetAttribute("PadMode", Enums.Mode.Blitz)
	pad:SetAttribute("Accent", accent)
	-- Parented LAST, with PadMode already on it. The client picks pads up from
	-- DescendantAdded, and a part that arrives before its mode does is a part
	-- the client ignores for the rest of the session. The museum pads learned
	-- this in Phase 13 and this one repeated it.
	if fresh then
		pad.Parent = training
	end

	local face = training:FindFirstChild("PadFace_blitz")
	if not face then
		face = Instance.new("Part")
		face.Name = "PadFace_blitz"
		face.Anchored = true
		face.CanCollide = false
		face.Size = Vector3.new(sprintPad.Size.X - 2.2, 0.18, sprintPad.Size.Z - 2.2)
		face.Material = Enum.Material.Neon
		face.Color = accent
		face.Transparency = 0.35
		face.Position = at + Vector3.new(0, sprintPad.Size.Y / 2 + 0.1, 0)
		face.Parent = training
	end
	return true
end

-- The session is spent whatever the verdict: a rejected result must not leave
-- it open to try again with better numbers.
function PracticeService.finish(player: Player, msg: any, now: number): (any?, string?)
	local session = sessions[player.UserId]
	sessions[player.UserId] = nil
	return PracticeService.vet(session, msg, now)
end

function PracticeService.forget(player: Player)
	sessions[player.UserId] = nil
end

return PracticeService
