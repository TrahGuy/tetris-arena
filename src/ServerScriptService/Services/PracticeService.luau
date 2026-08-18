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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)

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

-- One live session per player. Starting another abandons the first, which is
-- also what stops two runs being reported against one stretch of wall clock.
function PracticeService.begin(player: Player, mode: any, now: number): any
	nextId += 1
	local session = {
		id = nextId,
		seed = math.random(1, 2 ^ 31 - 1),
		mode = (mode == Enums.Mode.Sprint) and Enums.Mode.Sprint or Enums.Mode.Practice,
		startedAt = now,
	}
	sessions[player.UserId] = session
	return session
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
