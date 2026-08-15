-- Every feel constant in the game. Nothing else may hardcode these numbers.
--
-- Mirrored onto attributes by Tuning.mirror() so they can be retuned live from
-- the command bar or over MCP while Play mode is running — module tables read
-- from outside the running game are a different copy, attributes are not.

local Tuning = {}

-- ── Board ─────────────────────────────────────────────────────────────────
Tuning.WIDTH = 10
Tuning.HEIGHT = 40   -- 20 visible plus 20 of buffer; garbage push-up needs the headroom
Tuning.VISIBLE = 20
Tuning.PREVIEW = 5

-- ── Timing (seconds unless noted) ─────────────────────────────────────────
Tuning.TICK = 1 / 120        -- fixed sim step; never tie gravity to frames
Tuning.DAS = 0.133           -- delay before a held left/right repeats
Tuning.ARR = 0               -- repeat interval once DAS fires; 0 = slide to the wall
Tuning.GRAVITY = 1.0         -- cells per second at match start
Tuning.SOFT_DROP_G = 1200    -- 20G: effectively instant while Down is held
Tuning.LOCK_DELAY = 0.5
Tuning.LOCK_RESETS = 15      -- without a cap you can spin forever and never top out
Tuning.ARE = 0               -- spawn delay after a lock
Tuning.CLEAR_DELAY = 0.12    -- pause for the line-clear animation

-- ── Garbage ───────────────────────────────────────────────────────────────
Tuning.GARBAGE_DELAY = 0.5   -- counter window before charged garbage lands
Tuning.GARBAGE_RECOLUMN = 0.7 -- chance a new batch re-rolls its gap column
Tuning.GARBAGE_CAP = 12      -- most rows that can land in one go

-- ── Match ─────────────────────────────────────────────────────────────────
Tuning.COUNTDOWN = 3
Tuning.SUDDEN_DEATH = 150    -- gravity ramps and rows rise after this
Tuning.SUDDEN_ROW_EVERY = 10
Tuning.MATCH_CAP = 300       -- hard stop; most garbage sent wins
Tuning.RESULTS_TIME = 12
Tuning.BOT_AFTER = 20        -- queue this long with no human -> offer a bot

-- ── Networking ────────────────────────────────────────────────────────────
Tuning.SNAPSHOT_HZ = 10
Tuning.MIN_LOCK_INTERVAL = 0.03 -- anything faster than this is not a human

-- ── Scoring readout ───────────────────────────────────────────────────────
Tuning.APM_WINDOW = 20

-- Live-tunable subset. Only numbers that are safe to change mid-session.
local LIVE = {
	"DAS", "ARR", "GRAVITY", "SOFT_DROP_G", "LOCK_DELAY", "LOCK_RESETS",
	"ARE", "CLEAR_DELAY", "GARBAGE_DELAY", "SUDDEN_DEATH", "MATCH_CAP", "BOT_AFTER",
}

-- Publishes the live subset as attributes and keeps the table in step with any
-- edits made to them. Call once, server side.
function Tuning.mirror(host: Instance)
	for _, key in ipairs(LIVE) do
		host:SetAttribute(key, Tuning[key])
		host:GetAttributeChangedSignal(key):Connect(function()
			local v = host:GetAttribute(key)
			if type(v) == "number" then
				Tuning[key] = v
			end
		end)
	end
end

return Tuning
