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
local SkinData = require(Shared.SkinData)
local GlobalRank = require(script.Parent.GlobalRank)

local StatsService = {}

local STORE_NAME = "BlockArenaProfiles_v1"
local store = nil
local profiles: { [number]: any } = {}
local dirty: { [number]: boolean } = {}

-- The global ranked index. Derived from the profiles below, never the other way
-- round: nothing in this file ever reads a rating out of it.
local global = GlobalRank.new(GlobalRank.liveBackend())

local DEFAULT = {
	wins = 0, losses = 0, streak = 0, bestStreak = 0,
	lines = 0, quads = 0, matches = 0, bestSprint = 0,
	rating = 1000, peakRating = 1000, rankedWins = 0, rankedLosses = 0,
	-- Ranked draws were already possible — the clock running out on equal
	-- garbage — and already moved both ratings, but nothing recorded that the
	-- match happened. Without this, a player whose only ranked game was a draw
	-- has a rating a ranked result produced and no evidence they ever ranked,
	-- which is exactly the account the global board has to decide about.
	rankedDraws = 0,
	das = 133, arr = 0, music = 60, sfx = 80, colourblind = false,
	-- Cosmetics. Ids only, never skin definitions: the catalog lives in
	-- SkinData and a profile that stored palettes would be a second, stale
	-- copy of it. ownedSkins is rebuilt per profile by mergeSkins below --
	-- DEFAULT is shallow-cloned, so a table left here would be SHARED by
	-- every player on the server.
	ownedSkins = {},
	equippedSkin = SkinData.DEFAULT_ID,
	-- Solving the secret nook is its own fact, separate from owning what it
	-- pays out. An account can hold galaxy from a debug grant, an event or a
	-- future purchase without ever having found the puzzle, and solving it
	-- while already owning the skin still counts as having solved it.
	secretPuzzleSolved = false,
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
--
-- `scoreW` is what the first player scored: 1 for a win, 0.5 for a draw. A
-- ranked match that runs the clock out on equal garbage is rare, but scoring it
-- as nothing-happened is wrong in the one case it matters — the favourite
-- should still have given something up.
function StatsService.elo(ratingW: number, ratingL: number, playedW: number, playedL: number,
	scoreW: number?)
	local s = scoreW or 1
	local kw, kl = kFactor(playedW), kFactor(playedL)
	local ew = expectedScore(ratingW, ratingL)
	local el = expectedScore(ratingL, ratingW)
	return math.max(100, math.floor(ratingW + kw * (s - ew) + 0.5)),
		math.max(100, math.floor(ratingL + kl * ((1 - s) - el) + 0.5))
end

-- Applies the change and reports what each rating did, so the result card can
-- show it. Draws still do not count toward the K factor's match total — that is
-- meant to settle as a player is placed, and a draw places nobody — but they
-- are recorded, because having played a ranked match is a different question
-- from having been placed by one.
--
-- This is the only function in the game that moves a ranked rating, which is
-- why the global index is told here rather than at any of the call sites: there
-- is then no way to change a rating without the index hearing about it.
function StatsService.applyElo(winner: Player, loser: Player, scoreW: number?): (any?, any?)
	local w, l = profiles[winner.UserId], profiles[loser.UserId]
	if not w or not l then return nil, nil end
	local beforeW, beforeL = w.rating, l.rating
	w.rating, l.rating = StatsService.elo(beforeW, beforeL,
		w.rankedWins + w.rankedLosses, l.rankedWins + l.rankedLosses, scoreW)
	w.peakRating = math.max(w.peakRating, w.rating)
	if (scoreW or 1) >= 1 then
		w.rankedWins += 1
		l.rankedLosses += 1
	else
		w.rankedDraws += 1
		l.rankedDraws += 1
	end
	dirty[winner.UserId] = true
	dirty[loser.UserId] = true
	-- Queued, not written: this runs while both players are waiting for a
	-- result, and the index is never worth a round trip in front of that.
	global:publish(winner.UserId, w.rating)
	global:publish(loser.UserId, l.rating)
	return { before = beforeW, after = w.rating, delta = w.rating - beforeW },
		{ before = beforeL, after = l.rating, delta = l.rating - beforeL }
end

-- Tests inject a fake index; production uses the one built above.
function StatsService.setGlobalRank(rank: any)
	global = rank
end

function StatsService.globalRank(): any
	return global
end

-- Small enough to sit on a Debug attribute, which is all a live server can show
-- the command bar.
function StatsService.globalStatus(now: number): any
	local rows = global:top()
	return {
		status = global.status,
		rows = rows and #rows or 0,
		age = math.floor(global:age(now)),
		lastError = global.lastError,
		reads = global.reads,
		writes = global.writes,
	}
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

-- Entitlement, rebuilt from what was saved rather than adopted from it.
--
-- Four things have to hold no matter what came back from the store, including
-- nothing at all: the default is owned, the equipped skin is one the player
-- owns, ids that are no longer in the catalog are quietly dropped, and the
-- table is this profile's own rather than one shared with every other player on
-- the server — which is what a shallow clone of DEFAULT would hand out.
--
-- Retiring a cosmetic must never need a migration script. An id that has left
-- the catalog simply stops being presented; if it comes back, so does the
-- ownership, because dropping it here does not erase it from the store.
local function mergeSkins(p: any, saved: any?)
	local owned = {}
	if type(saved) == "table" and type(saved.ownedSkins) == "table" then
		for id, value in pairs(saved.ownedSkins) do
			if value == true and SkinData.exists(id) then
				owned[id] = true
			end
		end
	end
	owned[SkinData.DEFAULT_ID] = true
	p.ownedSkins = owned

	local equipped = type(saved) == "table" and saved.equippedSkin or nil
	if type(equipped) == "string" and owned[equipped] then
		p.equippedSkin = equipped
	else
		p.equippedSkin = SkinData.DEFAULT_ID
	end
end

-- Ownership is a UNION on save, not a last-write-wins table.
--
-- There is no session lock, so two servers can hold the same profile. If one
-- grants a skin and the other saves afterward with an older view, writing this
-- server's table wholesale would take the grant back — and an entitlement that
-- silently disappears is the worst kind of bug to be on the receiving end of. A
-- union can only ever be too generous, and it can only be generous about skins
-- some server actually granted, because nothing else ever reaches this table.
--
-- Equipped is a preference, so it follows the settings rule: last writer wins.
local function unionProgress(merged: any, profile: any): any
	local owned = type(merged.ownedSkins) == "table" and merged.ownedSkins or {}
	if type(profile.ownedSkins) == "table" then
		for id, value in pairs(profile.ownedSkins) do
			if value == true then owned[id] = true end
		end
	end
	owned[SkinData.DEFAULT_ID] = true
	merged.ownedSkins = owned
	merged.equippedSkin = owned[profile.equippedSkin] and profile.equippedSkin
		or SkinData.DEFAULT_ID
	-- Completion only ever moves one way. With no session lock an older server
	-- can save after a newer one, and finding the secret is not something a
	-- stale write gets to undo.
	merged.secretPuzzleSolved = (merged.secretPuzzleSolved or profile.secretPuzzleSolved) == true
	return merged
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
	mergeSkins(p, saved)
	return p
end

local function grantCore(p: any, userId: number, skinId: any): string
	if not SkinData.exists(skinId) then return "unknown skin" end
	if p.ownedSkins[skinId] then return "already" end
	p.ownedSkins[skinId] = true
	dirty[userId] = true
	return "granted"
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
	-- A profile that solved the puzzle but does not own what it pays out has
	-- lost the entitlement somewhere, not the achievement. Put it back before
	-- the client is told anything, so it sees one coherent profile.
	if profiles[id].secretPuzzleSolved then
		grantCore(profiles[id], id, SkinData.SECRET_ID)
	end
	if player.Parent then
		Remotes.Profile:FireClient(player, profiles[id])
	end

	-- Migration, and self-healing, in one line.
	--
	-- Accounts with ranked history predate the index and have no key in it;
	-- accounts whose rating moved on another server leave the key stale. Both
	-- are fixed by republishing what the canonical profile says, every join.
	-- The queue collapses duplicates, so this is at most one write per join,
	-- and only for accounts that have actually played ranked.
	if GlobalRank.eligible(profiles[id]) then
		global:publish(id, profiles[id].rating)
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
				"rankedWins", "rankedLosses", "rankedDraws" }) do
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

			unionProgress(merged, profile)
			return merged
		end)
	end)
end

function StatsService.release(player: Player)
	StatsService.save(player)
	profiles[player.UserId] = nil
	dirty[player.UserId] = nil
end

-- ── Skins ─────────────────────────────────────────────────────────────────

-- Server-only. There is no remote that reaches this, and there must never be
-- one: a client that can call grant is a client that owns the catalog.
--
-- This is the seam every future unlock hangs off — achievements, the secret
-- puzzle, an event, and eventually a purchase. Granting twice is harmless, so
-- callers never have to check first.
--
-- Returns one of "granted", "already", "unknown skin", "no profile".
function StatsService.grantSkin(player: Player, skinId: any): string
	local p = profiles[player.UserId]
	if not p then return "no profile" end
	local result = grantCore(p, player.UserId, skinId)
	if result == "granted" and player.Parent then
		Remotes.Profile:FireClient(player, p)
	end
	return result
end

-- The secret nook's payout, as one transaction.
--
-- Completion and entitlement move together and the client is told once, so it
-- can never see a profile that has solved the puzzle but does not own the skin
-- — or the reverse. Idempotent: a duplicate solve changes nothing and pushes
-- nothing.
--
-- Returns "completed", "already solved" or "no profile".
function StatsService.completeSecretPuzzle(player: Player): string
	local p = profiles[player.UserId]
	if not p then return "no profile" end
	if p.secretPuzzleSolved then return "already solved" end
	p.secretPuzzleSolved = true
	grantCore(p, player.UserId, SkinData.SECRET_ID)
	dirty[player.UserId] = true
	if player.Parent then
		Remotes.Profile:FireClient(player, p)
	end
	return "completed"
end

function StatsService.hasSolvedSecret(player: Player): boolean
	local p = profiles[player.UserId]
	return (p and p.secretPuzzleSolved == true) or false
end

-- PuzzleService needs to know a profile is loaded before it reserves the nook.
function StatsService.getProfile(player: Player): any?
	return profiles[player.UserId]
end

-- The two seams the suite needs: what a stored profile becomes on load, and
-- what two servers' ownership becomes on save. Both are the real functions,
-- exposed rather than reimplemented, so a test cannot pass against a copy.
function StatsService.migrateForTest(saved: any?): any
	return merge(saved)
end

function StatsService.mergeProgressForTest(stored: any, profile: any): any
	return unionProgress(merge(stored), profile)
end

function StatsService.ownsSkin(player: Player, skinId: any): boolean
	local p = profiles[player.UserId]
	return (p and type(skinId) == "string" and p.ownedSkins[skinId] == true) or false
end

-- The client asks; this decides. A request names a skin and nothing else — the
-- server never takes ownership, or an equipped state, off the wire.
--
-- Returns one of "equipped", "no change", "not owned", "unknown skin",
-- "no profile", "in a match".
function StatsService.equipSkin(player: Player, skinId: any, inMatch: boolean?): string
	local p = profiles[player.UserId]
	if not p then return "no profile" end
	if not SkinData.exists(skinId) then return "unknown skin" end
	if not p.ownedSkins[skinId] then return "not owned" end
	-- Cosmetics change between matches, not during one. The board is the thing
	-- the player is reading, and repainting it mid-stack is a distraction at
	-- best; keeping the renderer's palette fixed for the length of a match also
	-- means there is no visual state to get wrong when a resync arrives.
	if inMatch then return "in a match" end
	-- Spamming equip must not spam persistence. An unchanged choice is a
	-- success that writes nothing and does not mark the profile dirty.
	if p.equippedSkin == skinId then return "no change" end
	p.equippedSkin = skinId
	dirty[player.UserId] = true
	if player.Parent then
		Remotes.Profile:FireClient(player, p)
	end
	return "equipped"
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

-- Runs while a disconnecting player's profile is still loaded: PlayerRemoving
-- calls playerLeaving synchronously and only then spawns the release. A side
-- that has left still carries its Player, which is how the loss finds them.
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
	-- rating is to quit whenever you are behind — and this is reached on a
	-- disconnect precisely because the side kept hold of its Player.
	if match.mode == Enums.Mode.Ranked then
		if loser == nil then
			if match.a.player and match.b.player then
				match.a.elo, match.b.elo = StatsService.applyElo(match.a.player, match.b.player, 0.5)
			end
		else
			local winner = loser.other
			if loser.player and winner and winner.player then
				winner.elo, loser.elo = StatsService.applyElo(winner.player, loser.player, 1)
			end
		end
		-- The board this server is showing can be corrected from what it
		-- already knows, so a player who just took the top spot does not have
		-- to watch themselves sit at number four until the next fetch. The
		-- fetch is asked for too, and throttled, so a busy server settling ten
		-- ranked matches a minute still reads the index once.
		for _, side in ipairs({ match.a, match.b }) do
			if side.elo and side.player then
				global:patch(side.player.UserId, side.elo.after, side.player.DisplayName)
			end
		end
		global:request()
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

-- `record` comes from PracticeService.vet, never straight off the wire. Every
-- number here has already been bounded by the wall clock the server measured,
-- so this credits rather than judges.
function StatsService.recordPractice(player: Player, record: any)
	local p = profiles[player.UserId]
	if not p or type(record) ~= "table" then return end
	p.lines += record.lines
	if record.sprint then
		p.bestSprint = (p.bestSprint > 0) and math.min(p.bestSprint, record.time) or record.time
	end
	dirty[player.UserId] = true
end

-- ── Leaderboard tower ─────────────────────────────────────────────────────
-- 03_stations.luau builds the panels with placeholder rows; this replaces their
-- contents from live data, so the geometry never has to change again.

local function rebuildPanel(part: BasePart, title: string, accent: Color3, rows: { any })
	local sg = part:FindFirstChildOfClass("SurfaceGui")
	if not sg then return end
	-- The fallback is for places built before 03_stations named this frame:
	-- the lookup missed, this returned early, and the tower showed its
	-- placeholder rows for good. Tolerating both spellings means live servers
	-- do not need the world rebuilt to get a working leaderboard.
	local root = sg:FindFirstChild("Root") or sg:FindFirstChildOfClass("Frame")
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

-- The top rows the WORLD RANK panel should show, and the title to show them
-- under.
--
-- Reads the cache only. refreshLeaderboard runs on every join, every departure
-- and every match result, and turning each of those into a GetSortedAsync would
-- burn the server's request budget on redrawing a sign nobody is looking at.
-- The fetch happens on its own clock; this renders whatever it last brought
-- back.
--
-- With no good page the panel falls back to this server and says so. Showing
-- the players in one lobby under the words WORLD RANK would be the kind of
-- wrong that nobody ever catches, because it looks exactly like the truth.
local function worldPanel(localRanked: { any }): (string, { any })
	local rows = global:top()
	local out = {}
	-- An empty global page is truthful but dead: until the first ranked match
	-- anywhere, the tower would show five dashes to a lobby full of people.
	-- Falling back to this server is more use and stays honest, because the
	-- title falls back with it.
	if rows and #rows > 0 then
		for i = 1, GlobalRank.LIMIT do
			local e = rows[i]
			table.insert(out, { i, e and e.name or "—", e and e.rating or "—" })
		end
		return "WORLD RANK", out
	end
	for i = 1, GlobalRank.LIMIT do
		local e = localRanked[i]
		table.insert(out, { i, e and e.name or "—", e and e.p.rating or "—" })
	end
	return "SERVER RANK", out
end

-- Which title the panel would carry right now. Exposed so the fallback can be
-- tested without a lobby to render into: the title is the honesty guarantee.
function StatsService.worldPanelForTest(): (string, { any })
	return worldPanel({})
end

-- The auxiliary panels stay server-local by design; only their titles had to
-- change, because next to a global WORLD RANK an unqualified TOP SCORES reads
-- as global too.
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

	table.sort(ranked, function(a, b) return a.p.rating > b.p.rating end)
	local worldTitle, world = worldPanel(ranked)

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
				rebuildPanel(part, worldTitle, Theme.C.gold, world)
			elseif which == "WIN STREAK" then
				rebuildPanel(part, "WIN STREAK  ·  SERVER", Color3.fromRGB(255, 154, 43), streak)
			elseif which == "TOP SCORES" then
				rebuildPanel(part, "TOP SCORES  ·  SERVER", Theme.C.violet, scores)
			end
		end
	end
end

-- The one task that talks to the ranking index.
--
-- Everything else queues a write or asks for a fetch and returns immediately,
-- so no gameplay path can ever be waiting on a DataStore. A read failure keeps
-- the last good page; a write failure drops that write and lets the next ranked
-- result or join republish it. Neither can reach a match.
function StatsService.startGlobalRank()
	task.spawn(function()
		if global:refresh(os.clock()) then
			StatsService.refreshLeaderboard()
		end
		while true do
			task.wait(5)
			global:flush()
			if global:shouldFetch(os.clock()) then
				if global:refresh(os.clock()) then
					StatsService.refreshLeaderboard()
				end
			end
		end
	end)
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
