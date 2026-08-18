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
local Museum = require(Services.MuseumService)
local PuzzleService = require(Services.PuzzleService)

Matchmaking.setStatsService(Stats)

-- Tags the museum's existing exhibits with the skins they represent and gives
-- each one an interaction pad. Idempotent, and a no-op if the lobby is absent.
do
	local wired, missing = Museum.wire()
	if missing > 0 then
		warn(("[Museum] %d catalog skins have no exhibit in the world"):format(missing))
	end
	print(("[BlockArena] museum: %d exhibits wired"):format(wired))
end

-- The secret nook. Discovers the unfinished board Phase 1 built and hangs
-- prompts on it; if the geometry is not what it expects it warns once and stays
-- switched off rather than taking the lobby down with it.
local Puzzle = PuzzleService.new({ stats = Stats, matchmaking = Matchmaking, solo = Practice })
do
	local lobby = workspace:FindFirstChild("Lobby")
	local ok, why = Puzzle:bind(lobby and lobby:FindFirstChild("Secret"))
	print(("[BlockArena] secret puzzle: %s"):format(ok and "ready" or why))
end

-- The Training Zone shipped with one pad. Blitz gets its own, beside it.
do
	local lobby = workspace:FindFirstChild("Lobby")
	local wired = Practice.wirePads(lobby and lobby:FindFirstChild("Training"))
	print(("[BlockArena] blitz pad: %s"):format(wired and "ready" or "no training zone"))
end

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

-- One place a Blitz run ends, whoever noticed first: the deadline, a top-out,
-- or the player disconnecting. PracticeService.finalize is idempotent, so the
-- races between those three cannot pay out twice.
local function finishBlitz(player, result)
	if not result then return end
	local verdict = Stats.recordBlitz(player, result)
	Practice.forget(player)
	Stats.refreshLeaderboard()
	if player.Parent then
		Remotes.Practice:FireClient(player, {
			sessionId = result.sessionId,
			finished = true,
			result = result,
			record = verdict == "record",
		})
	end
end

-- One routing rule, and it is exclusive.
--
-- A competitive lock names its match; a solo Blitz lock names its session. A
-- message carrying both is not ambiguous so much as dishonest -- there is no
-- legitimate client that would send one -- and letting it through would be the
-- one way a lock meant for a score attack could reach a ranked match.
Remotes.Lock.OnServerEvent:Connect(function(player, msg)
	if not limits.lock:allow(player) then return end
	if type(msg) ~= "table" then return end
	local hasMatch, hasSession = msg.matchId ~= nil, msg.sessionId ~= nil
	if hasMatch == hasSession then return end -- both, or neither
	if hasMatch then
		Matchmaking.onLock(player, msg)
		return
	end
	local verdict, payload = Practice.onLock(player, msg, workspace:GetServerTimeNow())
	if verdict == "score" then
		Remotes.Practice:FireClient(player, payload)
	elseif verdict == "finished" then
		finishBlitz(player, payload)
	end
end)

Remotes.Forfeit.OnServerEvent:Connect(function(player, msg)
	if not limits.ui:allow(player) then return end
	Matchmaking.forfeit(player, msg)
end)

Remotes.SaveSettings.OnServerEvent:Connect(function(player, msg)
	if not limits.ui:allow(player) then return end
	Stats.applySettings(player, msg)
end)

-- Equipping is a UI action: rate limited like the rest, and the payload carries
-- one id. Ownership is never read from the message — Stats decides.
Remotes.EquipSkin.OnServerEvent:Connect(function(player, msg)
	if not limits.ui:allow(player) then return end
	if type(msg) ~= "table" then return end
	Stats.equipSkin(player, msg.skinId, Matchmaking.matchFor(player) ~= nil)
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
	-- Starting a run gives up the nook: a player cannot be two minutes into a
	-- score attack and holding the shared puzzle at the same time.
	Puzzle:playerLeaving(player)
	local session = Practice.begin(player, msg.mode, os.clock(), workspace:GetServerTimeNow())
	Remotes.Practice:FireClient(player, {
		sessionId = session.id,
		seed = session.seed,
		mode = session.mode,
		gravity = Tuning.GRAVITY,
		-- Blitz only. Both ends read workspace:GetServerTimeNow(), so the run
		-- starts and ends at the same instant for the server and the player
		-- whatever the round trip cost.
		startAt = session.startAt,
		endAt = session.endAt,
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
	-- A solver who disconnects must not leave the nook reserved, or its blocks
	-- stuck in the wall.
	Puzzle:playerLeaving(player)
	for _, limiter in pairs(limits) do
		limiter:forget(player)
	end
	task.spawn(function()
		Stats.release(player)
		Stats.refreshLeaderboard()
	end)
end)

-- Anyone already here before this script ran, which in Studio is everyone. The
-- redraw matters: without it the tower keeps whatever it painted before the
-- profiles arrived, and PlayerAdded never fires to correct it.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		Stats.load(player)
		Stats.refreshLeaderboard()
	end)
end

Stats.startAutosave()
Stats.startGlobalRank()
task.defer(Stats.refreshLeaderboard)

RunService.Heartbeat:Connect(function(dt)
	Matchmaking.step(dt)
	-- Timeout, a solver who wandered off to queue, a character that vanished:
	-- one place decides the session is over.
	Puzzle:step(os.clock())
	-- Blitz ends when the server says so, with or without the client.
	for _, done in ipairs(Practice.step(workspace:GetServerTimeNow())) do
		finishBlitz(done.player, done.result)
	end
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
		-- Attributes rather than prints: this loop ticks twice a second.
		debugFolder:SetAttribute("Solo", Practice.debugSummary(workspace:GetServerTimeNow()))
		local q = Puzzle:status(os.clock())
		debugFolder:SetAttribute("PuzzleStatus", q.status)
		debugFolder:SetAttribute("PuzzleSolver", q.solver)
		debugFolder:SetAttribute("PuzzlePlaced", q.placed)
		debugFolder:SetAttribute("PuzzleHeld", q.held)
		debugFolder:SetAttribute("PuzzleSessionAge", q.age)
		-- Whether the global board is live, how old its page is, and why not.
		local g = Stats.globalStatus(os.clock())
		debugFolder:SetAttribute("GlobalRankStatus", g.status)
		debugFolder:SetAttribute("GlobalRankRows", g.rows)
		debugFolder:SetAttribute("GlobalRankAge", g.age)
		debugFolder:SetAttribute("GlobalRankLastError", g.lastError)
	end
end)

-- Development grant path, Studio only.
--
-- Unlocks have no source yet — achievements, the secret puzzle and a shop are
-- all later phases — so there has to be some way to put a skin on an account
-- and see the museum change. This is an attribute on ServerStorage, which a
-- client cannot write and cannot even see, driven from the command bar:
--
--   game.ServerStorage.Debug:SetAttribute("GrantSkin", "12345678:golden")
--
-- Gated on IsStudio so it does not exist in a published place at all. There is
-- deliberately no remote anywhere near StatsService.grantSkin.
if RunService:IsStudio() then
	debugFolder:GetAttributeChangedSignal("GrantSkin"):Connect(function()
		local request = debugFolder:GetAttribute("GrantSkin")
		if type(request) ~= "string" or request == "" then return end
		local idText, skinId = request:match("^(-?%d+):(.+)$")
		local userId = tonumber(idText)
		local player = userId and Players:GetPlayerByUserId(userId)
		if not player then
			debugFolder:SetAttribute("GrantSkinResult", "no such player: " .. request)
			return
		end
		debugFolder:SetAttribute("GrantSkinResult",
			("%s %s -> %s"):format(player.Name, tostring(skinId), Stats.grantSkin(player, skinId)))
	end)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		Stats.save(player)
	end
end)

print("[BlockArena] server ready")
