-- Line clears to garbage. Every number the balance depends on lives here.

local Attack = {}

-- A single is deliberately worth nothing: it pushes players toward stacking
-- rather than shaving one row at a time.
local BASE = { 0, 1, 2, 4 } -- single, double, triple, quad

-- Indexed by consecutive clears. Past the end, the last value repeats.
local COMBO = { 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5 }

Attack.B2B_BONUS = 1
Attack.PERFECT_CLEAR = 10

Attack.NONE, Attack.SINGLE, Attack.DOUBLE, Attack.TRIPLE, Attack.QUAD = 0, 1, 2, 3, 4

-- T-spins pay out as of Phase 11. They were detected and displayed but scored
-- nothing until the base game was proven, and until the server could derive one
-- for itself — see Board.verifySpin.
Attack.TSPIN_ENABLED = true

-- Indexed by LINES + 1, so entry one is a spin that cleared nothing. That is
-- not a stylistic choice: read as { single, double, triple, quad } the way BASE
-- is, these tables pay a T-spin single nothing, a double 2, a triple 4, and
-- reserve 6 for a four-line T-spin that a three-wide piece cannot produce —
-- a dead entry and a worthless single. Read from zero they are exactly the
-- guideline values, 2 / 4 / 6, with the 0-line spin the table plainly starts
-- with. The second reading is the one that makes every entry mean something.
local TSPIN = { 0, 2, 4, 6 }        -- 0, 1, 2, 3 lines
local TSPIN_MINI = { 0, 0, 1, 2 }   -- a mini single is deliberately worth nothing

export type ClearInfo = {
	lines: number,
	tspin: string?, -- "full" | "mini" | nil
	perfect: boolean,
	b2b: boolean,
	combo: number,
	attack: number,
}

-- A clear keeps a back-to-back chain alive when it is a quad or a T-spin.
-- Anything else of 1-3 lines breaks it; a non-clearing lock leaves it alone.
function Attack.isB2BClear(lines: number, tspin: string?): boolean
	return lines >= 4 or (tspin ~= nil and lines > 0)
end

-- combo is the count of consecutive clears INCLUDING this one, so a first
-- clear arrives as 1.
function Attack.compute(lines: number, tspin: string?, perfect: boolean, b2b: boolean, combo: number): ClearInfo
	local info: ClearInfo = {
		lines = lines,
		tspin = tspin,
		perfect = perfect,
		b2b = false,
		combo = combo,
		attack = 0,
	}
	if lines <= 0 then
		return info
	end

	-- A T-spin is paid INSTEAD of the base clear, never on top of it.
	local n = 0
	if tspin and Attack.TSPIN_ENABLED then
		n = (tspin == "mini" and TSPIN_MINI or TSPIN)[math.min(lines, 3) + 1] or 0
	else
		n = BASE[math.min(lines, 4)] or 0
	end

	if b2b and Attack.isB2BClear(lines, tspin) then
		n += Attack.B2B_BONUS
		info.b2b = true
	end

	if combo >= 2 then
		n += COMBO[math.min(combo, #COMBO)]
	end

	if perfect then
		n += Attack.PERFECT_CLEAR
	end

	info.attack = n
	return info
end

-- Cancelling. Outgoing attack eats the incoming queue before any of it is sent,
-- which is the whole of battle Tetris defence — without it there is no defence
-- and every match is a pure race.
--
-- `queue` is a list of { rows = n, at = time }, mutated in place. Returns how
-- many rows survive to be sent at the opponent.
function Attack.cancel(queue: { { rows: number, at: number } }, outgoing: number): number
	local left = outgoing
	while left > 0 and #queue > 0 do
		local head = queue[1]
		if head.rows > left then
			head.rows -= left
			left = 0
		else
			left -= head.rows
			table.remove(queue, 1)
		end
	end
	return left
end

function Attack.pending(queue: { { rows: number, at: number } }): number
	local n = 0
	for _, item in ipairs(queue) do
		n += item.rows
	end
	return n
end

return Attack
