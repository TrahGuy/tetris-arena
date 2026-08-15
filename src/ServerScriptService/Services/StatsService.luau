-- Profiles, settings persistence and the leaderboard tower.
--
-- The original v1 scope ruled out DataStores. Settings alone overturn that: if
-- DAS, ARR, volume and the colourblind palette reset on every join, players
-- re-tune every session and eventually stop. Once a profile exists, win/loss
-- and a best sprint come almost free.
--
-- UpdateAsync rather than SetAsync, so two servers writing the same profile
-- merge instead of clobbering. Full session locking is deliberately not here —
-- for this game the odds of one account playing on two servers at once are low,
-- and the failure it prevents is losing a few wins, not corruption.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)

local StatsService = {}

local STORE_NAME = "BlockArenaProfiles_v1"
local store = nil
local profiles: { [number]: any } = {}
local dirty: { [number]: boolean } = {}

local DEFAULT = {
	wins = 0, losses = 0, streak = 0, bestStreak = 0,
	lines = 0, quads = 0, matches = 0, bestSprint = 0,
	rating = 1000, peakRating = 1000, rankedWins = 0, rankedLosses = 0,
	das = 133, arr = 0, music = 60, sfx = 80, colourblind = false,
}

-- Elo. The RANKED pad was queuing exactly like quick play, which made the label
-- a lie; this is the smallest thing that makes it true.
local function expectedScore(a: number, b: number): number
	return 1 / (1 + 10 ^ ((b - a) / 400))
end

-- K falls as a player settles. A new account should find its level in a few
-- matches; an established one should not swing 40 points on a single game.
local function kFactor(played: number): number
	if played < 10 then return 48 end
	if played < 30 then return 32 end
	return 20
end

-- The maths on its own, so it can be tested without a profile or a DataStore.
-- Returns the winner's and loser's new ratings. Floored at 100, so a losing
-- streak cannot bottom out into meaninglessness.
function StatsService.elo(ratingW: number, ratingL: number, playedW: number, playedL: number)
	local kw, kl = kFactor(playedW), kFactor(playedL)
	local ew = expectedScore(ratingW, ratingL)
	local el = expectedScore(ratingL, ratingW)
	return math.max(100, math.floor(ratingW + kw * (1 - ew) + 0.5)),
		math.max(100, math.floor(ratingL + kl * (0 - el) + 0.5))
end

function StatsService.applyElo(winner: Player, loser: Player)
	local w, l = profiles[winner.UserId], profiles[loser.UserId]
	if not w or not l then return end
	w.rating, l.rating = StatsService.elo(w.rating, l.rating,
		w.rankedWins + w.rankedLosses, l.rankedWins + l.rankedLosses)
	w.peakRating = math.max(w.peakRating, w.rating)
	w.rankedWins += 1
	l.rankedLosses += 1
	dirty[winner.UserId] = true
	dirty[loser.UserId] = true
end

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	-- API access can be off in Studio; everything below still works in memory.
	store = ok and result or nil
	if not store then
		warn("[Stats] DataStore unavailable — profiles will not persist this session")
	end
end

local function key(userId: number): string
	return "u_" .. userId
end

local function merge(saved: any?): any
	local p = table.clone(DEFAULT)
	if type(saved) == "table" then
		for k, v in pairs(saved) do
			if DEFAULT[k] ~= nil and type(v) == type(DEFAULT[k]) then
				p[k] = v
			end
		end
	end
	return p
end

function StatsService.load(player: Player)
	local id = player.UserId
	local saved = nil
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync(key(id))
			end)
			if ok then
				saved = result
				break
			end
			task.wait(attempt * 0.6)
		end
	end
	profiles[id] = merge(saved)
	if player.Parent then
		Remotes.Profile:FireClient(player, profiles[id])
	end
end

function StatsService.get(player: Player): any
	return profiles[player.UserId]
end

function StatsService.save(player: Player)
	local id = player.UserId
	local profile = profiles[id]
	if not profile or not store or not dirty[id] then return end
	dirty[id] = nil
	pcall(function()
		store:UpdateAsync(key(id), function(old)
			local merged = merge(old)
			-- Counters accumulate across servers; settings are last-write-wins.
			for _, k in ipairs({ "wins", "losses", "lines", "quads", "matches",
				"rankedWins", "rankedLosses" }) do
				merged[k] = math.max(merged[k], profile[k])
			end
			merged.bestStreak = math.max(merged.bestStreak, profile.bestStreak)
			merged.peakRating = math.max(merged.peakRating, profile.peakRating)
			merged.streak = profile.streak
			-- Rating has to be the live value, not a max: it is meant to fall.
			merged.rating = profile.rating
			if profile.bestSprint > 0 then
				merged.bestSprint = merged.bestSprint > 0
					and math.min(merged.bestSprint, profile.bestSprint)
					or profile.bestSprint
			end
			for _, k in ipairs({ "das", "arr", "music", "sfx", "colourblind" }) do
				merged[k] = profile[k]
			end
			return merged
		end)
	end)
end

function StatsService.release(player: Player)
	StatsService.save(player)
	profiles[player.UserId] = nil
	dirty[player.UserId] = nil
end

function StatsService.applySettings(player: Player, s: any)
	local p = profiles[player.UserId]
	if not p or type(s) ~= "table" then return end
	local function num(v, lo, hi, fallback)
		v = tonumber(v)
		if not v then return fallback end
		return math.clamp(v, lo, hi)
	end
	p.das = num(s.das, 40, 300, p.das)
	p.arr = num(s.arr, 0, 100, p.arr)
	p.music = num(s.music, 0, 100, p.music)
	p.sfx = num(s.sfx, 0, 100, p.sfx)
	if type(s.colourblind) == "boolean" then p.colourblind = s.colourblind end
	dirty[player.UserId] = true
end

function StatsService.recordMatch(match: any, loser: any?, reason: string?)
	for _, side in ipairs({ match.a, match.b }) do
		local player = side.player
		local p = player and profiles[player.UserId]
		if p then
			p.matches += 1
			p.lines += side.board.stats.lines
			p.quads += side.board.stats.quads
			if loser == nil then
				-- draw: streak survives
			elseif side == loser then
				p.losses += 1
				p.streak = 0
			else
				p.wins += 1
				p.streak += 1
				p.bestStreak = math.max(p.bestStreak, p.streak)
			end
			dirty[player.UserId] = true
		end
	end

	-- Leaving a ranked match still costs rating. Otherwise the way to protect a
	-- rating is to quit whenever you are behind.
	if match.mode == Enums.Mode.Ranked and loser and loser.player then
		local winner = loser.other
		if winner and winner.player then
			StatsService.applyElo(winner.player, loser.player)
		end
	end

	-- Push the updated profile so the rating on screen is the new one, not the
	-- one from when they joined.
	for _, side in ipairs({ match.a, match.b }) do
		local player = side.player
		if player and player.Parent and profiles[player.UserId] then
			Remotes.Profile:FireClient(player, profiles[player.UserId])
		end
	end

	StatsService.refreshLeaderboard()
end

function StatsService.recordPractice(player: Player, mode: string, stats: any, time: number)
	local p = profiles[player.UserId]
	if not p then return end
	p.lines += (stats and stats.lines or 0)
	if mode == Enums.Mode.Sprint and stats and stats.lines >= 40 then
		p.bestSprint = (p.bestSprint > 0) and math.min(p.bestSprint, time) or time
	end
	dirty[player.UserId] = true
end

-- ── Leaderboard tower ─────────────────────────────────────────────────────
-- 03_stations.luau builds the panels with placeholder rows; this replaces their
-- contents from live data, so the geometry never has to change again.

local function rebuildPanel(part: BasePart, title: string, accent: Color3, rows: { any })
	local sg = part:FindFirstChildOfClass("SurfaceGui")
	if not sg then return end
	local root = sg:FindFirstChild("Root")
	if not root then return end
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("TextLabel") or c:IsA("Frame") then c:Destroy() end
	end
	Theme.label(root, title, {
		Font = Theme.F.display, TextColor3 = accent, TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.04, 0.04), Size = UDim2.fromScale(0.92, 0.17),
	})
	local rule = Instance.new("Frame")
	rule.Position, rule.Size = UDim2.fromScale(0.04, 0.235), UDim2.new(0.92, 0, 0, 3)
	rule.BackgroundColor3, rule.BackgroundTransparency, rule.BorderSizePixel = accent, 0.4, 0
	rule.Parent = root

	local n = math.max(#rows, 1)
	for i, row in ipairs(rows) do
		local y, h = 0.29 + (i - 1) * (0.66 / n), (0.66 / n) - 0.02
		Theme.label(root, tostring(row[1]), {
			Font = Theme.F.display, TextColor3 = accent, TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromScale(0.05, y), Size = UDim2.fromScale(0.14, h),
		})
		Theme.label(root, tostring(row[2]), {
			TextColor3 = Theme.C.text, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromScale(0.21, y), Size = UDim2.fromScale(0.5, h),
		})
		Theme.label(root, tostring(row[3]), {
			Font = Theme.F.display, TextColor3 = Theme.C.muted, TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.72, y), Size = UDim2.fromScale(0.23, h),
		})
	end
end

-- Server-local rankings. A global leaderboard needs OrderedDataStores and a
-- moderation story for names; this is honest about being the current lobby.
function StatsService.refreshLeaderboard()
	local lobby = workspace:FindFirstChild("Lobby")
	local tower = lobby and lobby:FindFirstChild("Leaderboard")
	if not tower then return end

	local ranked = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local p = profiles[player.UserId]
		if p then
			table.insert(ranked, { name = player.DisplayName, p = p })
		end
	end

	-- Ranked by rating now that ranked play means something.
	table.sort(ranked, function(a, b) return a.p.rating > b.p.rating end)
	local world = {}
	for i = 1, 5 do
		local e = ranked[i]
		table.insert(world, { i, e and e.name or "—", e and e.p.rating or "—" })
	end

	table.sort(ranked, function(a, b) return a.p.streak > b.p.streak end)
	local streak = {}
	for i = 1, 3 do
		local e = ranked[i]
		table.insert(streak, { i, e and e.name or "—", e and e.p.streak or 0 })
	end

	local bestLines, bestQuads, bestSprint = 0, 0, 0
	local nameLines, nameQuads, nameSprint = "—", "—", "—"
	for _, e in ipairs(ranked) do
		if e.p.lines > bestLines then bestLines, nameLines = e.p.lines, e.name end
		if e.p.quads > bestQuads then bestQuads, nameQuads = e.p.quads, e.name end
		if e.p.bestSprint > 0 and (bestSprint == 0 or e.p.bestSprint < bestSprint) then
			bestSprint, nameSprint = e.p.bestSprint, e.name
		end
	end
	local scores = {
		{ "LINES", nameLines, bestLines },
		{ "QUADS", nameQuads, bestQuads },
		{ "SPRINT", nameSprint, bestSprint > 0 and string.format("%.1fs", bestSprint) or "—" },
		{ "PLAYERS", "", #ranked },
	}

	for _, part in ipairs(tower:GetChildren()) do
		if part:IsA("BasePart") and part.Name:match("^Panel_") then
			local which = part.Name:sub(7)
			if which == "WORLD RANK" then
				rebuildPanel(part, "WORLD RANK", Theme.C.gold, world)
			elseif which == "WIN STREAK" then
				rebuildPanel(part, "WIN STREAK", Color3.fromRGB(255, 154, 43), streak)
			elseif which == "TOP SCORES" then
				rebuildPanel(part, "TOP SCORES", Theme.C.violet, scores)
			end
		end
	end
end

-- Periodic flush so a server crash costs at most a minute of progress.
function StatsService.startAutosave()
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				StatsService.save(player)
			end
		end
	end)
end

function StatsService.markDirty(player: Player)
	dirty[player.UserId] = true
end

return StatsService
