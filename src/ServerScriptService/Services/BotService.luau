-- The bot opponent.
--
-- This is not a stretch goal. A new Roblox game with 8-16 slots is empty almost
-- all of the time; without an AI the first hundred people press PLAY, watch
-- "Searching…" spin, and leave — and the queue never fills because it never
-- filled. The bot is what makes the game playable on day one.
--
-- Difficulty comes from think delay, move speed and a deliberate error rate,
-- never from a worse evaluator. A bot that stacks badly is unsatisfying to
-- beat; a bot that stacks well but slowly is a good opponent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Board = require(Shared.Board)
local Pieces = require(Shared.Pieces)
local Enums = require(Shared.Enums)

local BotService = {}
local Bot = {}
Bot.__index = Bot

-- Well-known weights: reward clearing, punish height, holes and a jagged
-- surface. Holes are the expensive one — a covered gap costs more than the
-- height it saves.
local W = {
	lines = 0.76,
	height = -0.51,
	holes = -0.36,
	bumpiness = -0.18,
}

local PROFILES = {
	[Enums.Difficulty.Rookie] = { think = 0.85, error_ = 0.28, name = "ROOKIE BOT" },
	[Enums.Difficulty.Neon] = { think = 0.42, error_ = 0.08, name = "NEON BOT" },
	[Enums.Difficulty.Overdrive] = { think = 0.16, error_ = 0.0, name = "OVERDRIVE BOT" },
}

local function evaluate(b: any): number
	local heights = table.create(b.w, 0)
	local holes, total, bumpiness = 0, 0, 0
	for col = 1, b.w do
		local h = 0
		local seen = false
		for row = b.h, 1, -1 do
			local v = b.cells[(row - 1) * b.w + col]
			if v ~= 0 then
				if not seen then
					seen = true
					h = row
				end
			elseif seen then
				holes += 1
			end
		end
		heights[col] = h
		total += h
	end
	for col = 1, b.w - 1 do
		bumpiness += math.abs(heights[col] - heights[col + 1])
	end
	return W.height * total + W.holes * holes + W.bumpiness * bumpiness
end

-- Every placement of a piece: each rotation, every column it fits in.
local function placements(b: any, kind: number): { any }
	local out = {}
	local spawnY = Pieces.SPAWN[kind].y
	for rot = 1, 4 do
		for x = -3, b.w do
			if not b:collides(kind, rot, x, spawnY) then
				local trial = b:clone()
				trial.piece = { kind = kind, rot = rot, x = x, y = spawnY }
				local before = trial.stats.lines
				trial:hardDrop()
				local cleared = trial.stats.lines - before
				if trial.alive then
					table.insert(out, {
						rot = rot,
						x = x,
						score = evaluate(trial) + W.lines * cleared * 10,
					})
				end
			end
		end
		-- O is identical in all four states; evaluating it four times just
		-- multiplies the work.
		if kind == Pieces.O then break end
	end
	table.sort(out, function(a, c) return a.score > c.score end)
	return out
end

function BotService.new(seed: number, difficulty: string, opts: any?)
	local profile = PROFILES[difficulty] or PROFILES[Enums.Difficulty.Neon]
	return setmetatable({
		board = Board.new(seed, opts),
		profile = profile,
		name = profile.name,
		timer = 0,
		plan = nil,
		planFor = -1,
		stuck = 0,
		rng = Random.new(seed),
	}, Bot)
end

function Bot:_choose()
	local b = self.board
	local p = b.piece
	if not p then return end

	-- The bot deliberately does not use hold. Evaluating the swap doubles the
	-- search and opens a class of bugs around holdUsed for a gain that does not
	-- show at these difficulties; a bot that never holds still plays well.
	local options = placements(b, p.kind)
	if #options == 0 then return end

	local pick = options[1]
	-- A deliberate mistake now and then, rather than a permanently worse brain.
	if self.rng:NextNumber() < self.profile.error_ and #options > 3 then
		pick = options[self.rng:NextInteger(2, math.min(6, #options))]
	end
	self.plan = pick
end

function Bot:update(dt: number)
	local b = self.board
	if not b.alive then return end
	b:step(dt)
	if not b.piece then return end

	-- A piece that locked under gravity while the bot was still manoeuvring
	-- leaves its plan behind, and the NEXT piece then gets aimed at the previous
	-- piece's target column. That cascade is what tops the bot out; keying the
	-- plan to the piece counter is what stops it.
	if self.planFor ~= b.stats.pieces then
		self.plan, self.planFor, self.stuck = nil, b.stats.pieces, 0
	end

	self.timer += dt
	if not self.plan then
		self:_choose()
		self.timer = 0
		return
	end
	if self.timer < self.profile.think then return end

	local p = b.piece
	if p.rot ~= self.plan.rot then
		if not b:rotate(1) then
			self.stuck += 1
			-- Wedged. Stop fighting it and take the drop rather than sitting
			-- there while gravity decides for us.
			if self.stuck > 4 then
				b:hardDrop()
				self.plan = nil
				return
			end
		end
		self.timer = self.profile.think * 0.55
		return
	end
	if p.x ~= self.plan.x then
		if not b:move(p.x < self.plan.x and 1 or -1) then
			b:hardDrop()
			self.plan = nil
			return
		end
		self.timer = self.profile.think * 0.55
		return
	end
	b:hardDrop()
	self.plan = nil
	self.timer = 0
end

BotService.Bot = Bot
BotService.PROFILES = PROFILES
BotService.evaluate = evaluate
BotService.placements = placements

return BotService
