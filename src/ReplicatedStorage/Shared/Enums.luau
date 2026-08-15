-- Shared string constants. Plain strings rather than numeric ids so anything
-- that leaks into a log or an attribute is readable.

return {
	State = {
		Idle = "idle",
		Queued = "queued",
		Countdown = "countdown",
		Playing = "playing",
		Results = "results",
	},

	Mode = {
		Quick = "quick",
		Ranked = "ranked",
		Private = "private",
		Practice = "practice",
		Sprint = "sprint",
		Blitz = "blitz",
		Emote = "emote",
	},

	TopOut = {
		Block = "block",     -- a piece spawned into occupied cells
		Lock = "lock",       -- a piece came to rest entirely above the field
		Garbage = "garbage", -- rising garbage pushed the stack out of the buffer
	},

	Result = {
		Win = "win",
		Loss = "loss",
		Draw = "draw",
		Forfeit = "forfeit",
		Left = "left",     -- opponent disconnected: a win, but not a KO
		Timeout = "timeout", -- match cap reached; most garbage sent wins
	},

	Difficulty = {
		Rookie = "rookie",
		Neon = "neon",
		Overdrive = "overdrive",
	},
}
