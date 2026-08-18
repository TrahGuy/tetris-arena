-- Every player title, defined once.
--
-- Deliberately the same shape as SkinData: one catalog, stable machine ids,
-- profiles that store nothing but those ids. That architecture went through
-- release hardening intact, so this reuses it rather than inventing a second
-- progression philosophy for the same problem.
--
-- A title is cosmetic and nothing else. Nothing in this file is read by the
-- board, the attack table, matchmaking or a rating; the only thing owning one
-- changes is what other players see next to your name.
--
-- Requirements are declared here rather than buried in service branches, so
-- what a title costs is readable in the same place as what it is called, and
-- retuning a threshold is a one-line edit with a test that notices.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkinData = require(ReplicatedStorage:WaitForChild("Shared").SkinData)

local TitleData = {}

-- Owned by everyone, always. There is no untitled state: something has to be
-- displayable before any entitlement question is asked.
TitleData.DEFAULT_ID = "rookie"

-- Presentation only. Rarity never decides an unlock, a reward or a match.
TitleData.RARITY = {
	COMMON = "COMMON",
	RARE = "RARE",
	EPIC = "EPIC",
	LEGENDARY = "LEGENDARY",
	SECRET = "SECRET",
}

-- Every requirement reads one authoritative profile field the server owns.
-- `compare` is how it is read: at-least for counters, at-most for times, and
-- flag for the one boolean.
local ATLEAST, ATMOST, FLAG = "atleast", "atmost", "flag"

local TITLES = {
	{
		id = "rookie",
		name = "ROOKIE",
		description = "Everyone starts here.",
		rarity = TitleData.RARITY.COMMON,
		sortOrder = 1,
		defaultOwned = true,
	},
	{
		id = "first_blood",
		name = "FIRST WIN",
		description = "Win your first match",
		rarity = TitleData.RARITY.COMMON,
		sortOrder = 2,
		defaultOwned = false,
		field = "wins", compare = ATLEAST, threshold = 1,
	},
	{
		id = "contender",
		name = "CONTENDER",
		description = "Win 10 Ranked matches",
		rarity = TitleData.RARITY.RARE,
		sortOrder = 3,
		defaultOwned = false,
		field = "rankedWins", compare = ATLEAST, threshold = 10,
	},
	{
		id = "streaker",
		name = "HOT STREAK",
		description = "Reach a 5-win streak",
		rarity = TitleData.RARITY.RARE,
		sortOrder = 4,
		defaultOwned = false,
		field = "bestStreak", compare = ATLEAST, threshold = 5,
	},
	{
		id = "quad_machine",
		name = "QUAD MACHINE",
		description = "Clear 100 Quads",
		rarity = TitleData.RARITY.EPIC,
		sortOrder = 5,
		defaultOwned = false,
		field = "quads", compare = ATLEAST, threshold = 100,
		-- GOLDEN T had no way to be earned until this existed.
		rewardSkin = "golden",
	},
	{
		id = "veteran",
		name = "BLOCK VETERAN",
		description = "Play 100 matches",
		rarity = TitleData.RARITY.EPIC,
		sortOrder = 6,
		defaultOwned = false,
		field = "matches", compare = ATLEAST, threshold = 100,
	},
	{
		id = "sprinter",
		name = "SPEED DEMON",
		description = "Finish Sprint in 60 seconds or less",
		rarity = TitleData.RARITY.EPIC,
		sortOrder = 7,
		defaultOwned = false,
		-- Lower is better, and zero means never finished one.
		field = "bestSprint", compare = ATMOST, threshold = 60,
	},
	{
		id = "blitz_master",
		name = "BLITZ MASTER",
		description = "Score 25,000 in Blitz",
		rarity = TitleData.RARITY.EPIC,
		sortOrder = 8,
		defaultOwned = false,
		-- Provisional. A quad is 800 and a back-to-back quad 1200, so this is
		-- roughly twenty good clears in two minutes: reachable by a decent
		-- player, not by an accident. There is no real play data yet, which is
		-- exactly why the number lives here and not in a service.
		field = "bestBlitz", compare = ATLEAST, threshold = 25000,
	},
	{
		id = "elite",
		name = "ELITE",
		description = "Reach 1500 rating",
		rarity = TitleData.RARITY.LEGENDARY,
		sortOrder = 9,
		defaultOwned = false,
		-- peakRating, not rating. A title earned by reaching a milestone should
		-- not evaporate the next time the player loses a match.
		field = "peakRating", compare = ATLEAST, threshold = 1500,
		-- DIAMOND I had no way to be earned until this existed.
		rewardSkin = "diamond",
	},
	{
		id = "secret_solver",
		name = "SECRET SOLVER",
		-- Deliberately says nothing. The nook is unsigned and stays that way.
		description = "Find what is hidden",
		rarity = TitleData.RARITY.SECRET,
		sortOrder = 10,
		defaultOwned = false,
		-- The completion flag, never ownership of what it pays out: an account
		-- can hold GALAXY CUBE from a grant without ever having found the nook.
		field = "secretPuzzleSolved", compare = FLAG,
		secret = true,
	},
}

local byId = {}
for _, title in ipairs(TITLES) do
	byId[title.id] = title
end

function TitleData.get(id: any): any?
	if type(id) ~= "string" then return nil end
	return byId[id]
end

function TitleData.exists(id: any): boolean
	return TitleData.get(id) ~= nil
end

function TitleData.default(): any
	return byId[TitleData.DEFAULT_ID]
end

function TitleData.ordered(): { any }
	local out = table.clone(TITLES)
	table.sort(out, function(a, b) return a.sortOrder < b.sortOrder end)
	return out
end

-- An id can outlive its title. Falling back beats erroring in front of a
-- player who did nothing wrong.
function TitleData.resolve(id: any): any
	return TitleData.get(id) or TitleData.default()
end

-- Has this profile earned it? Reads the profile and nothing else — there is no
-- argument here a client could supply.
function TitleData.earned(title: any, profile: any): boolean
	if type(title) ~= "table" or type(profile) ~= "table" then return false end
	if title.defaultOwned then return true end
	if not title.field then return false end
	local value = profile[title.field]
	if title.compare == FLAG then
		return value == true
	end
	local n = tonumber(value)
	if not n then return false end
	if title.compare == ATMOST then
		-- Zero is "never set", not "instant".
		return n > 0 and n <= title.threshold
	end
	return n >= title.threshold
end

-- What to show under a locked title. Numbers only where a number helps; the
-- secret one gets nothing, because a progress bar would give it away.
function TitleData.progress(title: any, profile: any): string?
	if type(title) ~= "table" or type(profile) ~= "table" then return nil end
	if title.defaultOwned or not title.field or title.secret then return nil end
	local value = tonumber(profile[title.field])
	if title.compare == FLAG then return nil end
	if title.compare == ATMOST then
		if not value or value <= 0 then
			return ("-- / %ds"):format(title.threshold)
		end
		return ("%.2fs / %ds"):format(value, title.threshold)
	end
	return ("%d / %d"):format(math.floor(value or 0), title.threshold)
end

-- Checked by the suite rather than trusted, so a half-written title fails in a
-- test run instead of in front of a player.
function TitleData.validate(): (boolean, { string })
	local problems = {}
	local seenId, seenOrder, defaults = {}, {}, 0
	for _, t in ipairs(TITLES) do
		local where = tostring(t.id)
		if type(t.id) ~= "string" or t.id == "" then
			table.insert(problems, "a title has no id")
		elseif seenId[t.id] then
			table.insert(problems, "duplicate id " .. where)
		end
		seenId[t.id] = true
		if type(t.name) ~= "string" or t.name == "" then
			table.insert(problems, where .. " has no name")
		end
		if type(t.description) ~= "string" or t.description == "" then
			table.insert(problems, where .. " has no description")
		end
		if not TitleData.RARITY[t.rarity] then
			table.insert(problems, where .. " has an unknown rarity")
		end
		if type(t.sortOrder) ~= "number" then
			table.insert(problems, where .. " has no sort order")
		elseif seenOrder[t.sortOrder] then
			table.insert(problems, where .. " reuses sort order " .. t.sortOrder)
		end
		seenOrder[t.sortOrder] = true
		if t.defaultOwned then
			defaults += 1
			if t.field then
				table.insert(problems, where .. " is owned by default and also has a requirement")
			end
		else
			if not t.field then
				table.insert(problems, where .. " can never be earned")
			end
			if t.compare ~= FLAG and type(t.threshold) ~= "number" then
				table.insert(problems, where .. " has no usable threshold")
			end
			if t.compare ~= ATLEAST and t.compare ~= ATMOST and t.compare ~= FLAG then
				table.insert(problems, where .. " has an unknown comparison")
			end
		end
		if t.rewardSkin ~= nil and not SkinData.exists(t.rewardSkin) then
			table.insert(problems, where .. " rewards a skin that does not exist")
		end
	end
	if not byId[TitleData.DEFAULT_ID] then
		table.insert(problems, "the default title is not in the catalog")
	elseif not byId[TitleData.DEFAULT_ID].defaultOwned then
		table.insert(problems, "the default title is not owned by default")
	end
	if defaults ~= 1 then
		table.insert(problems, ("exactly one title may be owned by default, found %d"):format(defaults))
	end
	return #problems == 0, problems
end

return TitleData
