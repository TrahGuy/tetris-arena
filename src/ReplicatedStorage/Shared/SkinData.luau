-- Every board skin in the game, defined once.
--
-- One catalog, shared by the server that owns entitlement, the renderer that
-- draws with it, and the museum that displays it. Duplicating these numbers
-- into a second table anywhere is how a skin ends up looking different in the
-- museum than it does on the board.
--
-- Ids are stable and machine-readable; names are not. A name is a label that
-- gets rewritten the first time someone decides GOLDEN T should be GOLD RUSH,
-- and profiles that stored the label would be storing entitlement in a string
-- somebody is going to edit. Profiles store ids.
--
-- The three unlockable skins are the museum's existing exhibits rather than
-- inventions: the lobby has been displaying GOLDEN T, DIAMOND I and GALAXY CUBE
-- under glass since Phase 1 with nothing behind them.

local SkinData = {}

-- Owned by everyone, always, and never removable. There is no "no skin" state:
-- the board has to be renderable before any entitlement question is asked.
SkinData.DEFAULT_ID = "classic"

-- Palettes are indexed by piece id: I O T S Z J L, then garbage at 8.
--
-- Every one of them keeps the seven hues separated. A skin is allowed to change
-- the character of the board — warm, icy, deep — but it is not allowed to make
-- two pieces hard to tell apart, because a misread piece loses matches and no
-- cosmetic is worth that.
local SKINS = {
	{
		id = "classic",
		name = "CLASSIC",
		description = "The arcade palette. Bright, separated, honest.",
		sortOrder = 1,
		defaultOwned = true,
		exhibit = nil, -- not in the museum: everybody already has it
		palette = {
			Color3.fromRGB(34, 228, 245),  -- I
			Color3.fromRGB(255, 216, 77),  -- O
			Color3.fromRGB(194, 77, 255),  -- T
			Color3.fromRGB(61, 232, 107),  -- S
			Color3.fromRGB(255, 61, 94),   -- Z
			Color3.fromRGB(77, 130, 255),  -- J
			Color3.fromRGB(255, 154, 43),  -- L
			Color3.fromRGB(110, 103, 144), -- garbage
		},
		board = Color3.fromRGB(15, 15, 20),
		cellEmpty = Color3.fromRGB(26, 26, 34),
		accent = Color3.fromRGB(56, 57, 70),
		ghostTransparency = 0.82,
		shellDarken = 0.5,
	},
	{
		id = "golden",
		name = "GOLDEN T",
		description = "Struck metal on a bronze field.",
		sortOrder = 2,
		defaultOwned = false,
		exhibit = "GOLDEN T",
		palette = {
			Color3.fromRGB(120, 220, 200),
			Color3.fromRGB(255, 214, 92),
			Color3.fromRGB(226, 150, 255),
			Color3.fromRGB(150, 230, 90),
			Color3.fromRGB(255, 96, 72),
			Color3.fromRGB(140, 160, 255),
			Color3.fromRGB(255, 168, 56),
			Color3.fromRGB(128, 112, 86),
		},
		board = Color3.fromRGB(20, 16, 10),
		cellEmpty = Color3.fromRGB(36, 28, 17),
		accent = Color3.fromRGB(255, 198, 96),
		ghostTransparency = 0.8,
		shellDarken = 0.55,
	},
	{
		id = "diamond",
		name = "DIAMOND I",
		description = "Cut glass. Cold light, long edges.",
		sortOrder = 3,
		defaultOwned = false,
		exhibit = "DIAMOND I",
		-- The first draft of this made I an icy cyan and S a mint green, which
		-- looked right and failed the separation check in the suite: two pale
		-- cool pieces a player has to tell apart at speed. S is pulled down
		-- into a real green and I left on cyan.
		palette = {
			Color3.fromRGB(120, 235, 255),
			Color3.fromRGB(235, 240, 250),
			Color3.fromRGB(185, 165, 255),
			Color3.fromRGB(110, 235, 175),
			Color3.fromRGB(255, 140, 170),
			Color3.fromRGB(105, 150, 250),
			Color3.fromRGB(255, 200, 140),
			Color3.fromRGB(120, 140, 160),
		},
		board = Color3.fromRGB(10, 16, 22),
		cellEmpty = Color3.fromRGB(22, 32, 42),
		accent = Color3.fromRGB(198, 240, 255),
		ghostTransparency = 0.86,
		shellDarken = 0.45,
	},
	{
		id = "galaxy",
		name = "GALAXY CUBE",
		description = "Deep field. Jewel tones on void.",
		sortOrder = 4,
		defaultOwned = false,
		exhibit = "GALAXY CUBE",
		palette = {
			Color3.fromRGB(90, 220, 255),
			Color3.fromRGB(255, 200, 120),
			Color3.fromRGB(200, 120, 255),
			Color3.fromRGB(110, 240, 160),
			Color3.fromRGB(255, 90, 140),
			Color3.fromRGB(110, 130, 255),
			Color3.fromRGB(255, 150, 90),
			Color3.fromRGB(95, 85, 140),
		},
		board = Color3.fromRGB(12, 7, 20),
		cellEmpty = Color3.fromRGB(26, 16, 48),
		accent = Color3.fromRGB(158, 122, 255),
		ghostTransparency = 0.84,
		shellDarken = 0.5,
	},
}

-- The high-contrast palette, which every skin shares.
--
-- Colourblind mode overrides skin colours outright rather than asking each skin
-- to supply its own accessible variant. A cosmetic must never be able to switch
-- accessibility off, and a per-skin high-contrast palette is a per-skin chance
-- to get one wrong. The board, ghost and empty-cell treatment still change with
-- the skin, so an equipped skin is still visibly equipped.
SkinData.COLOURBLIND = {
	Color3.fromRGB(80, 220, 255),
	Color3.fromRGB(255, 236, 120),
	Color3.fromRGB(235, 130, 255),
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(120, 160, 255),
	Color3.fromRGB(255, 190, 100),
	Color3.fromRGB(150, 148, 170),
}

local byId = {}
for _, skin in ipairs(SKINS) do
	byId[skin.id] = skin
end

function SkinData.get(id: any): any?
	if type(id) ~= "string" then return nil end
	return byId[id]
end

function SkinData.exists(id: any): boolean
	return SkinData.get(id) ~= nil
end

function SkinData.default(): any
	return byId[SkinData.DEFAULT_ID]
end

-- Catalog order, for the museum and anything else that lists skins.
function SkinData.ordered(): { any }
	local out = table.clone(SKINS)
	table.sort(out, function(a, b) return a.sortOrder < b.sortOrder end)
	return out
end

-- Falls back to the default rather than erroring: an id can outlive its skin,
-- and a retired cosmetic must not be able to stop a board being drawn.
function SkinData.resolve(id: any): any
	return SkinData.get(id) or SkinData.default()
end

-- Colourblind wins. Always.
function SkinData.paletteFor(id: any, colourblind: boolean?): { Color3 }
	if colourblind then return SkinData.COLOURBLIND end
	return SkinData.resolve(id).palette
end

-- Checked by the test suite rather than trusted, so a half-written skin fails
-- in a test run instead of on somebody's board.
function SkinData.validate(): (boolean, { string })
	local problems = {}
	local seen, defaults = {}, 0
	for _, skin in ipairs(SKINS) do
		local where = tostring(skin.id)
		if type(skin.id) ~= "string" or skin.id == "" then
			table.insert(problems, "a skin has no id")
		elseif seen[skin.id] then
			table.insert(problems, "duplicate id " .. where)
		end
		seen[skin.id] = true
		if type(skin.name) ~= "string" or skin.name == "" then
			table.insert(problems, where .. " has no name")
		end
		if type(skin.sortOrder) ~= "number" then
			table.insert(problems, where .. " has no sort order")
		end
		if skin.defaultOwned then defaults += 1 end
		if type(skin.palette) ~= "table" or #skin.palette ~= 8 then
			table.insert(problems, where .. " needs eight palette entries, seven pieces and garbage")
		else
			for i, c in ipairs(skin.palette) do
				if typeof(c) ~= "Color3" then
					table.insert(problems, ("%s palette entry %d is not a colour"):format(where, i))
				end
			end
		end
		for _, field in ipairs({ "board", "cellEmpty", "accent" }) do
			if typeof(skin[field]) ~= "Color3" then
				table.insert(problems, ("%s is missing %s"):format(where, field))
			end
		end
		if type(skin.ghostTransparency) ~= "number"
			or skin.ghostTransparency < 0 or skin.ghostTransparency > 1 then
			table.insert(problems, where .. " has an unusable ghost transparency")
		end
		if type(skin.shellDarken) ~= "number"
			or skin.shellDarken < 0 or skin.shellDarken > 1 then
			table.insert(problems, where .. " has an unusable shell darken")
		end
	end
	if not byId[SkinData.DEFAULT_ID] then
		table.insert(problems, "the default skin is not in the catalog")
	elseif not byId[SkinData.DEFAULT_ID].defaultOwned then
		table.insert(problems, "the default skin is not owned by default")
	end
	if defaults ~= 1 then
		table.insert(problems, ("exactly one skin may be owned by default, found %d"):format(defaults))
	end
	if #SkinData.COLOURBLIND ~= 8 then
		table.insert(problems, "the colourblind palette needs eight entries")
	end
	return #problems == 0, problems
end

return SkinData
