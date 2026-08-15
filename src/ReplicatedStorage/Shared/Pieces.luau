-- The seven tetrominoes, as explicit cell lists per rotation state.
--
-- Written out rather than computed. Rotating a matrix in code looks tidy and
-- then quietly disagrees with SRS about where the O piece sits or which way S
-- faces; the kick tables in SRS.luau are indexed against exactly these shapes.
--
-- Coordinates are (x, y) inside the piece's bounding box, x rightward and
-- y UPWARD, matching the convention the published SRS kick tables use.
-- Rotation states: 1 = spawn, 2 = right (CW), 3 = 180, 4 = left (CCW).

local Pieces = {}

Pieces.I, Pieces.O, Pieces.T, Pieces.S, Pieces.Z, Pieces.J, Pieces.L = 1, 2, 3, 4, 5, 6, 7
Pieces.GARBAGE = 8

Pieces.NAMES = { "I", "O", "T", "S", "Z", "J", "L", "G" }

-- Neon-tuned for a dark board. Index matches the ids above.
Pieces.COLOURS = {
	Color3.fromRGB(34, 228, 245),  -- I
	Color3.fromRGB(255, 216, 77),  -- O
	Color3.fromRGB(194, 77, 255),  -- T
	Color3.fromRGB(61, 232, 107),  -- S
	Color3.fromRGB(255, 61, 94),   -- Z
	Color3.fromRGB(77, 130, 255),  -- J
	Color3.fromRGB(255, 154, 43),  -- L
	Color3.fromRGB(110, 103, 144), -- garbage
}

-- High-contrast alternative. Roughly 8% of male players cannot reliably
-- separate the S and Z above, and in a game where a misread piece loses the
-- match that is not a nicety.
Pieces.COLOURS_HC = {
	Color3.fromRGB(80, 220, 255),
	Color3.fromRGB(255, 236, 120),
	Color3.fromRGB(235, 130, 255),
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(120, 160, 255),
	Color3.fromRGB(255, 190, 100),
	Color3.fromRGB(150, 148, 170),
}

-- SHAPES[kind][rot] = { {x, y}, ... } — always four cells.
Pieces.SHAPES = {
	-- I, in a 4x4 box
	{
		{ { 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 2 } },
		{ { 2, 3 }, { 2, 2 }, { 2, 1 }, { 2, 0 } },
		{ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } },
		{ { 1, 3 }, { 1, 2 }, { 1, 1 }, { 1, 0 } },
	},
	-- O, identical in every state so rotation never nudges it
	{
		{ { 1, 2 }, { 2, 2 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 2 }, { 2, 2 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 2 }, { 2, 2 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 2 }, { 2, 2 }, { 1, 1 }, { 2, 1 } },
	},
	-- T, in a 3x3 box
	{
		{ { 1, 2 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 2 }, { 1, 1 }, { 2, 1 }, { 1, 0 } },
		{ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 1, 0 } },
		{ { 1, 2 }, { 0, 1 }, { 1, 1 }, { 1, 0 } },
	},
	-- S
	{
		{ { 1, 2 }, { 2, 2 }, { 0, 1 }, { 1, 1 } },
		{ { 1, 2 }, { 1, 1 }, { 2, 1 }, { 2, 0 } },
		{ { 1, 1 }, { 2, 1 }, { 0, 0 }, { 1, 0 } },
		{ { 0, 2 }, { 0, 1 }, { 1, 1 }, { 1, 0 } },
	},
	-- Z
	{
		{ { 0, 2 }, { 1, 2 }, { 1, 1 }, { 2, 1 } },
		{ { 2, 2 }, { 1, 1 }, { 2, 1 }, { 1, 0 } },
		{ { 0, 1 }, { 1, 1 }, { 1, 0 }, { 2, 0 } },
		{ { 1, 2 }, { 0, 1 }, { 1, 1 }, { 0, 0 } },
	},
	-- J
	{
		{ { 0, 2 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 2 }, { 2, 2 }, { 1, 1 }, { 1, 0 } },
		{ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 2, 0 } },
		{ { 1, 2 }, { 1, 1 }, { 0, 0 }, { 1, 0 } },
	},
	-- L
	{
		{ { 2, 2 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 2 }, { 1, 1 }, { 1, 0 }, { 2, 0 } },
		{ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 0, 0 } },
		{ { 0, 2 }, { 1, 2 }, { 1, 1 }, { 1, 0 } },
	},
}

-- Bounding-box origin at spawn, in field coordinates (column 0-indexed from the
-- left, row 1-indexed from the BOTTOM). Chosen so every piece's lowest cell
-- lands on row 21, the first row above the visible field.
Pieces.SPAWN = {
	{ x = 3, y = 19 }, -- I  occupies columns 4..7
	{ x = 3, y = 20 }, -- O  occupies columns 5..6
	{ x = 3, y = 20 }, -- T
	{ x = 3, y = 20 }, -- S
	{ x = 3, y = 20 }, -- Z
	{ x = 3, y = 20 }, -- J
	{ x = 3, y = 20 }, -- L
}

-- Box size, needed for the T-spin corner check.
Pieces.BOX = { 4, 4, 3, 3, 3, 3, 3 }

return Pieces
