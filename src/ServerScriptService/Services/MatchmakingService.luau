-- Queue, pairing, bot fallback, and the lifetime of every running match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local MatchInstance = require(script.Parent.MatchInstance)

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

local function start(specA: any, specB: any, mode: string)
	local m = MatchInstance.new(nextId, specA, specB, { mode = mode })
	nextId += 1
	m.onFinished = function(match, loser, reason)
		if statsService then
			statsService.recordMatch(match, loser, reason)
		end
		task.delay(Tuning.RESULTS_TIME, function()
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

	-- Private rooms are not a queue: they pair by invite, which needs a friend
	-- flow that does not exist yet. Treated as quick play so the pad still works.
	if mode == Enums.Mode.Private then
		mode = Enums.Mode.Quick
	end

	table.insert(queue, { player = player, mode = mode, since = os.clock() })
	Remotes.MatchUpdate:FireClient(player, { state = Enums.State.Queued })

	-- Pair with the first other player waiting in the same mode.
	for i = 1, #queue - 1 do
		local other = queue[i]
		if other.mode == mode and other.player ~= player and other.player.Parent then
			table.remove(queue, #queue)
			table.remove(queue, i)
			start({ player = other.player }, { player = player }, mode)
			return
		end
	end
end

function MatchmakingService.cancel(player: Player)
	local i = indexOf(player)
	if i then
		table.remove(queue, i)
		Remotes.MatchUpdate:FireClient(player, { state = Enums.State.Idle })
	end
end

function MatchmakingService.playerLeaving(player: Player)
	MatchmakingService.cancel(player)
	local m = MatchmakingService.matchFor(player)
	if m then m:playerLeft(player) end
end

function MatchmakingService.forfeit(player: Player)
	local m = MatchmakingService.matchFor(player)
	if m then m:forfeit(player) end
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
		elseif entry.mode ~= Enums.Mode.Ranked and now - entry.since >= Tuning.BOT_AFTER then
			table.remove(queue, i)
			start({ player = entry.player }, { bot = botFor(entry.player) }, entry.mode)
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
