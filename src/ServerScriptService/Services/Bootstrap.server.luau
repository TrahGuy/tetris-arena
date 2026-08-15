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

Remotes.Forfeit.OnServerEvent:Connect(function(player)
	if not limits.ui:allow(player) then return end
	Matchmaking.forfeit(player)
end)

Remotes.SaveSettings.OnServerEvent:Connect(function(player, msg)
	if not limits.ui:allow(player) then return end
	Stats.applySettings(player, msg)
end)

-- Practice is local to the client: the server only issues a seed and records
-- the result, because there is nothing to cheat at when nobody is opposing you.
Remotes.Practice.OnServerEvent:Connect(function(player, msg)
	if not limits.ui:allow(player) then return end
	if type(msg) ~= "table" then return end
	if msg.finished then
		Stats.recordPractice(player, msg.mode or Enums.Mode.Practice, msg.stats,
			tonumber(msg.time) or 0)
		Stats.refreshLeaderboard()
		return
	end
	if Matchmaking.matchFor(player) then return end
	Remotes.Practice:FireClient(player, {
		seed = math.random(1, 2 ^ 31 - 1),
		mode = msg.mode or Enums.Mode.Practice,
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
	Matchmaking.playerLeaving(player)
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
