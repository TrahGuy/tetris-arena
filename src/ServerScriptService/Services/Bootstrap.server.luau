-- Server entry point. Wires every remote to a service, behind a rate limiter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)

local Services = script.Parent
local RateLimiter = require(Services.RateLimiter)
local Matchmaking = require(Services.MatchmakingService)
local Stats = require(Services.StatsService)
local Practice = require(Services.PracticeService)

Matchmaking.setStatsService(Stats)

-- Live-tunable constants land on a folder so they can be adjusted from the
-- command bar mid-session; module tables read from outside are a different copy.
local tuningHost = ServerStorage:FindFirstChild("Tuning") or Instance.new("Folder")
tuningHost.Name = "Tuning"
tuningHost.Parent = ServerStorage
Tuning.mirror(tuningHost)

-- Locks are the hot path: a couple per second in normal play, plus a snapshot
-- at SNAPSHOT_HZ. The rest are user actions and can be far tighter.
local limits = {
	lock = RateLimiter.new(40, 60),
	queue = RateLimiter.new(1, 4),
	ui = RateLimiter.new(2, 6),
}

Remotes.QueueRequest.OnServerEvent:Connect(function(player, msg)
	if not limits.queue:allow(player) then return end
	local mode = type(msg) == "table" and msg.mode or Enums.Mode.Quick
	if type(mode) ~= "string" then return end
	Matchmaking.enqueue(player, mode)
end)

Remotes.QueueCancel.OnServerEvent:Connect(function(player)
	if not limits.queue:allow(player) then return end
	Matchmaking.cancel(player)
end)

Remotes.Lock.OnServerEvent:Connect(function(player, msg)
	if not limits.lock:allow(player) then return end
	Matchmaking.onLock(player, msg)
end)

Remotes.Forfeit.OnServerEvent:Connect(function(player, msg)
	if not limits.ui:allow(player) then return end
	Matchmaking.forfeit(player, msg)
end)

Remotes.SaveSettings.OnServerEvent:Connect(function(player, msg)
	if not limits.ui:allow(player) then return end
	Stats.applySettings(player, msg)
end)

-- Practice runs on the client, but the result is not taken on trust: it goes
-- to a sprint record and a lines total that both show on the leaderboard.
-- PracticeService issues the session and vets what comes back against the wall
-- clock it measured.
Remotes.Practice.OnServerEvent:Connect(function(player, msg)
	if not limits.ui:allow(player) then return end
	if type(msg) ~= "table" then return end
	if msg.finished then
		-- Nobody finishes a practice run from inside a match.
		if Matchmaking.matchFor(player) then return end
		local record, why = Practice.finish(player, msg, os.clock())
		if not record then
			-- "no session" is just a duplicate or late submission; the rest are
			-- worth seeing.
			if why ~= "no session" then
				warn(("[Practice] discarded a result from %s: %s"):format(
					player.Name, tostring(why)))
			end
			return
		end
		Stats.recordPractice(player, record)
		Stats.refreshLeaderboard()
		return
	end
	-- A practice board must not overlap a real one in either direction, or the
	-- same stretch of wall clock backs two runs.
	if Matchmaking.matchFor(player) or Matchmaking.isQueued(player) then return end
	local session = Practice.begin(player, msg.mode, os.clock())
	Remotes.Practice:FireClient(player, {
		sessionId = session.id,
		seed = session.seed,
		mode = session.mode,
		gravity = Tuning.GRAVITY,
	})
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		Stats.load(player)
		Stats.refreshLeaderboard()
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Before the release below: playerLeaving settles the match, and the loss
	-- and the rating need the profile to still be loaded.
	Matchmaking.playerLeaving(player)
	Practice.forget(player)
	for _, limiter in pairs(limits) do
		limiter:forget(player)
	end
	task.spawn(function()
		Stats.release(player)
		Stats.refreshLeaderboard()
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(Stats.load, player)
end

Stats.startAutosave()
task.defer(Stats.refreshLeaderboard)

RunService.Heartbeat:Connect(function(dt)
	Matchmaking.step(dt)
end)

-- Live match state on an attribute. A running server shares nothing else with
-- the command bar or with MCP tooling: a module table required from outside is
-- a separate copy, so without this a live match cannot be inspected at all.
local debugFolder = ServerStorage:FindFirstChild("Debug") or Instance.new("Folder")
debugFolder.Name = "Debug"
debugFolder.Parent = ServerStorage
task.spawn(function()
	while true do
		task.wait(0.5)
		debugFolder:SetAttribute("Matchmaking", Matchmaking.debugSummary())
		debugFolder:SetAttribute("Players", #Players:GetPlayers())
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		Stats.save(player)
	end
end)

print("[BlockArena] server ready")
