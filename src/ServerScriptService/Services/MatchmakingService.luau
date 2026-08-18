-- Queue, pairing, bot fallback, and the lifetime of every running match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local MatchInstance = require(script.Parent.MatchInstance)
local ArenaService = require(script.Parent.ArenaService)
local TitleData = require(Shared.TitleData)

local MatchmakingService = {}

local queue: { { player: Player, mode: string, since: number } } = {}
local matches: { any } = {}
local nextId = 1
local statsService = nil

function MatchmakingService.setStatsService(s)
	statsService = s
end

local function indexOf(player: Player): number?
	for i, entry in ipairs(queue) do
		if entry.player == player then return i end
	end
	return nil
end

function MatchmakingService.matchFor(player: Player)
	for _, m in ipairs(matches) do
		if not m.finished and m:hasPlayer(player) then return m end
	end
	return nil
end

-- How long the winner gets to stand in the arena and read the result before
-- the server puts everybody back. Instantly snapping away at the KO makes the
-- battle dimension feel like a loading screen rather than a place.
local RETURN_AFTER = 2.5

local function start(specA: any, specB: any, mode: string)
	local matchId = nextId

	-- The arena comes first. A match that cannot get one is a match that would
	-- run in the lobby with a countdown nobody understands, so it does not
	-- start at all -- the callers put the players back in the queue.
	local arena, why = ArenaService.allocate(matchId, mode)
	if not arena and ArenaService.isEnabled() then
		warn(("[Matchmaking] no arena for match %d: %s"):format(matchId, tostring(why)))
		return nil
	end

	-- Whatever each side is presenting as, for the other side's VS card. Has to
	-- be on the specs: MatchInstance.new sends the countdown before it returns,
	-- so anything set afterwards would arrive too late to be shown.
	if statsService then
		for _, spec in ipairs({ specA, specB }) do
			if spec.player then
				local profile = statsService.getProfile(spec.player)
				local titleId = profile and profile.equippedTitle
				local title = titleId and TitleData.get(titleId)
				spec.titleName = title and title.name or nil
			end
		end
	end

	local m = MatchInstance.new(matchId, specA, specB, { mode = mode })
	nextId += 1

	m.arenaId = arena and matchId or nil

	-- Into the arena immediately, which is the whole of the countdown before
	-- input arms. Both sides are moved by the same call, so neither is playing
	-- while the other is still travelling.
	if arena then
		for _, pair in ipairs({ { m.a, "A" }, { m.b, "B" } }) do
			local side, letter = pair[1], pair[2]
			if side.player then
				ArenaService.enter(matchId, side.player, letter)
			end
		end
	end

	m.onFinished = function(match, loser, reason)
		if statsService then
			statsService.recordMatch(match, loser, reason)
		end
		if match.arenaId then
			task.delay(RETURN_AFTER, function()
				for _, side in ipairs({ match.a, match.b }) do
					if side.player and side.player.Parent then
						ArenaService.returnPlayer(match.arenaId, side.player)
					end
				end
			end)
		end
		task.delay(Tuning.RESULTS_TIME, function()
			if match.arenaId then
				-- Keyed by this match. If the slot has since been handed to
				-- another match, that one is untouched.
				ArenaService.release(match.arenaId)
			end
			for i, other in ipairs(matches) do
				if other == match then
					table.remove(matches, i)
					break
				end
			end
		end)
	end
	table.insert(matches, m)
	return m
end

function MatchmakingService.enqueue(player: Player, mode: string)
	if MatchmakingService.matchFor(player) then return end -- already playing
	if indexOf(player) then return end                     -- already queued

	table.insert(queue, { player = player, mode = mode, since = os.clock() })
	Remotes.MatchUpdate:FireClient(player, { state = Enums.State.Queued })

	-- Pair with the first other player waiting in the same mode.
	for i = 1, #queue - 1 do
		local other = queue[i]
		if other.mode == mode and other.player ~= player and other.player.Parent then
			-- Both come out of the queue only if the match actually starts.
			local pairedA, pairedB = other.player, player
			table.remove(queue, #queue)
			table.remove(queue, i)
			if not start({ player = pairedA }, { player = pairedB }, mode) then
				-- No arena. Put them back rather than dropping them into
				-- nothing, and let the next tick try again.
				table.insert(queue, { player = pairedA, mode = mode, since = os.clock() })
				table.insert(queue, { player = pairedB, mode = mode, since = os.clock() })
			end
			return
		end
	end
end

function MatchmakingService.isQueued(player: Player): boolean
	return indexOf(player) ~= nil
end

function MatchmakingService.cancel(player: Player)
	local i = indexOf(player)
	if i then
		table.remove(queue, i)
		-- playerLeaving cancels too, and by then there is nobody to tell.
		if player.Parent then
			Remotes.MatchUpdate:FireClient(player, { state = Enums.State.Idle })
		end
	end
end

function MatchmakingService.playerLeaving(player: Player)
	MatchmakingService.cancel(player)
	local m = MatchmakingService.matchFor(player)
	if m then m:playerLeft(player) end
	-- Before the match settles, not after: cleanup must never wait on somebody
	-- who has already gone.
	ArenaService.forgetPlayer(player)
end

-- A forfeit names its match for the same reason a lock does: one still in
-- flight from the last match would otherwise throw away the next one.
function MatchmakingService.forfeit(player: Player, msg: any)
	local m = MatchmakingService.matchFor(player)
	if m and m:ownsMessage(msg) then m:forfeit(player) end
end

function MatchmakingService.onLock(player: Player, msg: any)
	local m = MatchmakingService.matchFor(player)
	if m then m:onLock(player, msg) end
end

-- Difficulty follows how long they waited: someone who queued into an empty
-- server gets the middle tier, not the hardest.
local function botFor(_player: Player): string
	return Enums.Difficulty.Neon
end

function MatchmakingService.step(dt: number)
	for _, m in ipairs(matches) do
		m:update(dt)
	end

	-- Nobody to pair with for long enough: give them a bot rather than an
	-- indefinite spinner. This is the difference between a playable game at
	-- 1 CCU and a dead one.
	local now = os.clock()
	local i = 1
	while i <= #queue do
		local entry = queue[i]
		if not entry.player.Parent then
			table.remove(queue, i)
		-- Quick play only. Ranked against a bot would be meaningless rating, and
		-- a "private" room that silently seats a bot instead of the friend you
		-- are waiting for is worse than an empty queue.
		elseif entry.mode == Enums.Mode.Quick and now - entry.since >= Tuning.BOT_AFTER then
			local waiting = entry.player
			table.remove(queue, i)
			if not start({ player = waiting }, { bot = botFor(waiting) }, entry.mode) then
				table.insert(queue, { player = waiting, mode = entry.mode, since = now })
			end
		else
			i += 1
		end
	end
end

function MatchmakingService.queueSize(): number
	return #queue
end

function MatchmakingService.debugSummary(): string
	local parts = { ("queue:%d"):format(#queue) }
	for _, m in ipairs(matches) do
		table.insert(parts, m:summary())
	end
	return table.concat(parts, "  ||  ")
end

function MatchmakingService.activeMatches(): number
	local n = 0
	for _, m in ipairs(matches) do
		if not m.finished then n += 1 end
	end
	return n
end

return MatchmakingService
