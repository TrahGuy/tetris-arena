-- Super Rotation System wall kicks.
--
-- This is data, not logic — which is exactly why it belongs in v1. "Basic wall
-- kicks" feel wrong within thirty seconds to anyone who has played, and
-- retrofitting SRS later invalidates every hour of feel-testing done before it.
--
-- Offsets are (x, y) with y UPWARD, matching Pieces.luau and the published
-- tables. Each list is tried in order; the first that fits wins.

local Pieces = require(script.Parent.Pieces)

local SRS = {}

-- Rotation states 1..4 = spawn, right, 180, left.
-- Key is "from>to".
local JLSTZ = {
	["1>2"] = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { 0, -2 }, { -1, -2 } },
	["2>1"] = { { 0, 0 }, { 1, 0 }, { 1, -1 }, { 0, 2 }, { 1, 2 } },
	["2>3"] = { { 0, 0 }, { 1, 0 }, { 1, -1 }, { 0, 2 }, { 1, 2 } },
	["3>2"] = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { 0, -2 }, { -1, -2 } },
	["3>4"] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, -2 }, { 1, -2 } },
	["4>3"] = { { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, 2 }, { -1, 2 } },
	["4>1"] = { { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, 2 }, { -1, 2 } },
	["1>4"] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, -2 }, { 1, -2 } },
}

local I = {
	["1>2"] = { { 0, 0 }, { -2, 0 }, { 1, 0 }, { -2, -1 }, { 1, 2 } },
	["2>1"] = { { 0, 0 }, { 2, 0 }, { -1, 0 }, { 2, 1 }, { -1, -2 } },
	["2>3"] = { { 0, 0 }, { -1, 0 }, { 2, 0 }, { -1, 2 }, { 2, -1 } },
	["3>2"] = { { 0, 0 }, { 1, 0 }, { -2, 0 }, { 1, -2 }, { -2, 1 } },
	["3>4"] = { { 0, 0 }, { 2, 0 }, { -1, 0 }, { 2, 1 }, { -1, -2 } },
	["4>3"] = { { 0, 0 }, { -2, 0 }, { 1, 0 }, { -2, -1 }, { 1, 2 } },
	["4>1"] = { { 0, 0 }, { 1, 0 }, { -2, 0 }, { 1, -2 }, { -2, 1 } },
	["1>4"] = { { 0, 0 }, { -1, 0 }, { 2, 0 }, { -1, 2 }, { 2, -1 } },
}

-- O never needs a kick; it occupies the same cells in every state.
local NONE = { { 0, 0 } }

function SRS.kicks(kind: number, from: number, to: number): { { number } }
	if kind == Pieces.O then
		return NONE
	end
	local key = from .. ">" .. to
	local table_ = (kind == Pieces.I) and I or JLSTZ
	return table_[key] or NONE
end

-- Next rotation state. dir 1 = clockwise, -1 = counter-clockwise.
function SRS.turn(rot: number, dir: number): number
	return ((rot - 1 + dir) % 4) + 1
end

return SRS
