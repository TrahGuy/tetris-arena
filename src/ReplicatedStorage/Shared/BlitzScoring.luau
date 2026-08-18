-- What a clear is worth in Blitz.
--
-- Pure: it takes the ClearInfo that Board already derived and returns a number.
-- No Instances, no clock, no state. That matters because the only place this is
-- ever called is the server, against its own shadow board — the client never
-- sends a score, and there is nothing here that could accept one.
--
-- Blitz scores CLEARING, not playing. There are deliberately no points for hard
-- drop distance, soft drop distance, movement or rotation: the shadow validates
-- final placements, not every input, so paying for inputs would mean either
-- trusting the client's account of them or streaming every keypress to the
-- server to be counted. Neither is worth it for a solo score attack.

local BlitzScoring = {}

-- All three tables are indexed by LINES + 1, so entry one is a clear of
-- nothing. A spin that clears nothing scores nothing here on purpose: Phase 11
-- already declines to count it as a T-spin in the stats, and paying for it
-- would make repeatedly rotating a T in a notch a better use of two minutes
-- than clearing lines.
local BASE = { 0, 100, 300, 500, 800 }
local TSPIN = { 0, 800, 1200, 1600 }
local MINI = { 0, 200, 400 }

BlitzScoring.B2B_MULTIPLIER = 1.5
BlitzScoring.COMBO_STEP = 50
BlitzScoring.PERFECT_CLEAR = 3500

-- `info` is Attack.ClearInfo: lines, tspin, b2b, combo, perfect.
--
-- Order is fixed and each part applies once: the base value for what was
-- cleared, multiplied if the chain was already alive, then the combo step, then
-- the perfect clear.
function BlitzScoring.score(info: any): number
	if type(info) ~= "table" then return 0 end
	local lines = tonumber(info.lines) or 0
	if lines <= 0 then return 0 end

	local base
	if info.tspin == "full" then
		base = TSPIN[math.min(lines, 3) + 1] or 0
	elseif info.tspin == "mini" then
		base = MINI[math.min(lines, 2) + 1] or 0
	else
		base = BASE[math.min(lines, 4) + 1] or 0
	end

	-- Only when the authoritative clear says the chain was alive. There is no
	-- second back-to-back state machine here; Board and Attack own that.
	if info.b2b then
		base = math.floor(base * BlitzScoring.B2B_MULTIPLIER)
	end

	local total = base
	local combo = tonumber(info.combo) or 0
	if combo >= 2 then
		total += BlitzScoring.COMBO_STEP * (combo - 1)
	end
	if info.perfect then
		total += BlitzScoring.PERFECT_CLEAR
	end
	return total
end

-- 12450 reads as 12,450 wherever a score is shown. One formatter, because the
-- alternative is three places quietly disagreeing about thousands separators.
function BlitzScoring.format(n: any): string
	local value = math.floor(tonumber(n) or 0)
	local sign = value < 0 and "-" or ""
	local digits = tostring(math.abs(value))
	local out = digits
	while true do
		local swapped
		out, swapped = out:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if swapped == 0 then break end
	end
	return sign .. out
end

return BlitzScoring
