-- The secret nook: four loose blocks, four missing cells, one skin.
--
-- None of this geometry is new. Phase 1 built an unfinished 5x5 board in the
-- far corner with a T-shaped hole in it and four blocks lying on the floor, and
-- then left it there. This wires up what is already in the world: it discovers
-- the slots and pieces by their attributes rather than carrying its own copy of
-- the layout, so the built world stays the source of truth for where anything
-- is.
--
-- Interaction is a server-owned ProximityPrompt per piece and per slot.
-- Triggered fires on the server with the Player, so there is no puzzle remote
-- at all — nothing for a client to forge, and no request to validate beyond the
-- one the engine already attributes to a player. It is also the interaction
-- Roblox already makes work on a keyboard, a controller and a phone.
--
-- The puzzle is one shared physical object in a shared world, so exactly one
-- player may be holding it at a time; everything else about the session exists
-- to make sure that reservation cannot be held forever.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkinData = require(Shared.SkinData)

local PuzzleService = {}
PuzzleService.__index = PuzzleService

PuzzleService.TIMEOUT = 45   -- seconds a reservation may sit idle before release
PuzzleService.REACH = 18     -- studs; the top row of slots sits well above head height
PuzzleService.CELEBRATE = 4  -- seconds the solved board stays lit before resetting
PuzzleService.PUZZLE = "T"
PuzzleService.SLOTS = 4

-- Is the thing we found in the world actually the puzzle?
--
-- Pure, so a malformed nook can be tested without one. `found` is what bind()
-- collected: the Puzzle attribute, and the slot and piece indices in the order
-- they were discovered.
function PuzzleService.validate(found: any): (boolean, string)
	if type(found) ~= "table" then return false, "nothing found" end
	if found.puzzle ~= PuzzleService.PUZZLE then
		return false, "board is not the " .. PuzzleService.PUZZLE .. " puzzle"
	end
	for _, kind in ipairs({ "slots", "pieces" }) do
		local list = found[kind]
		if type(list) ~= "table" then return false, "no " .. kind end
		if #list ~= PuzzleService.SLOTS then
			return false, ("expected %d %s, found %d"):format(PuzzleService.SLOTS, kind, #list)
		end
		local seen = {}
		for _, index in ipairs(list) do
			if type(index) ~= "number" or index % 1 ~= 0 then
				return false, "a " .. kind:sub(1, #kind - 1) .. " index is not a whole number"
			end
			if seen[index] then
				return false, ("duplicate %s index %d"):format(kind:sub(1, #kind - 1), index)
			end
			seen[index] = true
		end
	end
	return true, "ok"
end

function PuzzleService.new(deps: any?)
	deps = deps or {}
	return setmetatable({
		stats = deps.stats,
		matchmaking = deps.matchmaking,
		enabled = false,
		reason = "not bound",
		board = nil,
		slots = {},   -- slotIndex -> Part
		pieces = {},  -- pieceIndex -> Part
		slotPrompts = {},
		piecePrompts = {},
		home = {},    -- pieceIndex -> the look and place it started in
		prompts = {},
		session = nil,
		solvedAt = nil,
	}, PuzzleService)
end

-- ── Binding to the world ──────────────────────────────────────────────────

local function remember(part: BasePart): any
	return {
		cframe = part.CFrame,
		color = part.Color,
		material = part.Material,
		transparency = part.Transparency,
		canCollide = part.CanCollide,
	}
end

local function restore(part: BasePart, state: any)
	part.CFrame = state.cframe
	part.Color = state.color
	part.Material = state.material
	part.Transparency = state.transparency
	part.CanCollide = state.canCollide
end

function PuzzleService:_prompt(part: BasePart, action: string, object: string, distance: number)
	local existing = part:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = part
	table.insert(self.prompts, prompt)
	return prompt
end

-- Discovers the puzzle in `container`, validates it, and hangs prompts on it.
-- Safe to call again: a lobby rebuild in Edit mode replaces the geometry, and
-- rebinding has to be able to drop everything it knew.
function PuzzleService:bind(container: Instance?): (boolean, string)
	self.enabled = false
	self.session = nil
	self.solvedAt = nil
	for _, prompt in ipairs(self.prompts) do
		if prompt.Parent then prompt:Destroy() end
	end
	self.prompts, self.slots, self.pieces, self.home = {}, {}, {}, {}
	self.slotPrompts, self.piecePrompts = {}, {}

	if not container then
		self.reason = "no secret nook in the world"
		return false, self.reason
	end
	local board = container:FindFirstChild("Board")
	if not board then
		self.reason = "no board"
		return false, self.reason
	end

	local found = { puzzle = board:GetAttribute("Puzzle"), slots = {}, pieces = {} }
	local slotParts, pieceParts = {}, {}
	for _, d in ipairs(board:GetChildren()) do
		local index = d:GetAttribute("SlotIndex")
		if index ~= nil and d:IsA("BasePart") then
			table.insert(found.slots, index)
			slotParts[index] = d
		end
	end
	for _, d in ipairs(container:GetChildren()) do
		local index = d:GetAttribute("PieceIndex")
		if index ~= nil and d:IsA("BasePart") then
			table.insert(found.pieces, index)
			pieceParts[index] = d
		end
	end

	local ok, why = PuzzleService.validate(found)
	if not ok then
		-- Warned once, then left alone. A nook that was built wrong is a
		-- development problem, not a reason for the lobby to stop working.
		warn("[Puzzle] disabled: " .. why)
		self.reason = why
		return false, why
	end

	self.board = board
	self.slots, self.pieces = slotParts, pieceParts
	for index, part in pairs(pieceParts) do
		self.home[index] = remember(part)
		local prompt = self:_prompt(part, "Take", "Loose Block", 12)
		self.piecePrompts[index] = prompt
		prompt.Triggered:Connect(function(player)
			self:takePiece(player, index)
		end)
	end
	for index, part in pairs(slotParts) do
		local prompt = self:_prompt(part, "Place", "Empty Cell", PuzzleService.REACH)
		self.slotPrompts[index] = prompt
		prompt.Triggered:Connect(function(player)
			self:placePiece(player, index)
		end)
	end
	board:SetAttribute("Solved", false)
	self.enabled = true
	self.reason = "ok"
	return true, "ok"
end

-- ── Who may touch it ──────────────────────────────────────────────────────

local function rootOf(player: any): BasePart?
	local char = player and player.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

-- Even with a ProximityPrompt enforcing its own distance on the client, the
-- server checks again. The prompt is a request like any other.
function PuzzleService:_within(player: any, part: BasePart, distance: number): boolean
	local root = rootOf(player)
	if not root then return false end
	return (root.Position - part.Position).Magnitude <= distance
end

-- Returns nil when this player may start a session, or why they may not.
function PuzzleService:_mayClaim(player: any): string?
	if not self.enabled then return "puzzle disabled" end
	if not self.stats then return "no stats service" end
	if not self.stats.getProfile(player) then return "no profile" end
	-- Nothing left to win. The shared nook is not reserved for a replay that
	-- cannot pay anything, so the next player who has not solved it can.
	if self.stats.hasSolvedSecret(player) then return "already solved" end
	if self.matchmaking then
		if self.matchmaking.matchFor(player) then return "in a match" end
		-- Queued players get pulled into a match mid-placement, which would
		-- strand the pieces and burn the timeout for everyone else.
		if self.matchmaking.isQueued(player) then return "queued" end
	end
	if not rootOf(player) then return "no character" end
	return nil
end

function PuzzleService:_isSolver(player: any): boolean
	return self.session ~= nil and self.session.player == player
end

-- ── The session ───────────────────────────────────────────────────────────

function PuzzleService:_claim(player: any, now: number): string?
	if self.session then
		-- Written as `isSolver and nil or "..."` first, which always returns the
		-- string: nil is falsy, so the and/or idiom collapses. The session owner
		-- was being told someone else owned it.
		if self:_isSolver(player) then return nil end
		return "someone else is solving it"
	end
	local why = self:_mayClaim(player)
	if why then return why end
	self.session = {
		player = player,
		startedAt = now,
		touchedAt = now,
		held = nil,
		placed = {},   -- pieceIndex -> slotIndex
		occupied = {}, -- slotIndex -> pieceIndex
		count = 0,
	}
	return nil
end

function PuzzleService:takePiece(player: any, pieceIndex: number, now: number?): string
	now = now or os.clock()
	local part = self.pieces[pieceIndex]
	if not part then return "no such piece" end
	-- Before the reservation, not after: claiming first meant someone across
	-- the lobby took the puzzle and was only then told they were too far from
	-- it, leaving the nook locked until the timeout.
	if not self:_within(player, part, 12) then return "too far away" end
	local why = self:_claim(player, now)
	if why then return why end
	local s = self.session
	if s.placed[pieceIndex] then return "already placed" end
	-- One block at a time. Refusing is simpler than juggling a return, and it
	-- makes the state a player is in unambiguous: they are carrying something
	-- or they are not.
	if s.held then return "already holding one" end

	s.held = pieceIndex
	s.touchedAt = now
	-- Lifted and lit, so it is obvious which block is in hand. The block stays
	-- anchored: these are puzzle tokens, not physics props, and handing one to
	-- a character controller only invents ways for it to end up in a wall.
	part.CFrame = self.home[pieceIndex].cframe * CFrame.new(0, 2.4, 0)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(158, 122, 255)
	return "held"
end

function PuzzleService:placePiece(player: any, slotIndex: number, now: number?): string
	now = now or os.clock()
	local slot = self.slots[slotIndex]
	if not slot then return "no such slot" end
	if not self.session then return "nothing in hand" end
	if not self:_isSolver(player) then return "someone else is solving it" end
	local s = self.session
	if not s.held then return "nothing in hand" end
	if s.occupied[slotIndex] then return "slot is full" end
	if not self:_within(player, slot, PuzzleService.REACH) then return "too far away" end

	local pieceIndex = s.held
	local part = self.pieces[pieceIndex]
	-- The server knows where the slot is. It does not need telling.
	part.CFrame = CFrame.new(slot.Position + Vector3.new(0, 0, 0.6))
	part.CanCollide = false
	s.occupied[slotIndex] = pieceIndex
	s.placed[pieceIndex] = slotIndex
	s.held = nil
	-- A cell that is full has nothing left to offer, and a block in the wall is
	-- not lying on the floor any more. Leaving both prompts up meant standing in
	-- front of the board and being offered a slot that was already filled.
	if self.slotPrompts[slotIndex] then self.slotPrompts[slotIndex].Enabled = false end
	if self.piecePrompts[pieceIndex] then self.piecePrompts[pieceIndex].Enabled = false end
	s.count += 1
	s.touchedAt = now

	if s.count >= PuzzleService.SLOTS then
		return self:_solve(now)
	end
	return "placed"
end

-- ── Solving ───────────────────────────────────────────────────────────────

function PuzzleService:_solve(now: number): string
	local s = self.session
	local player = s.player
	-- Counted here, from placements this server made. There is no message that
	-- says the puzzle is finished.
	self.board:SetAttribute("Solved", true)
	for _, pieceIndex in pairs(s.occupied) do
		local part = self.pieces[pieceIndex]
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(226, 60, 190)
	end
	for _, slot in pairs(self.slots) do
		slot.Transparency = 0.35
	end

	local result = "no stats service"
	if self.stats then
		-- One call: it records the completion, grants the skin and pushes the
		-- profile once, so the client never sees a half-finished reward.
		result = self.stats.completeSecretPuzzle(player)
	end
	self.solvedAt = now
	return "solved:" .. result
end

-- ── Resetting ─────────────────────────────────────────────────────────────

-- Puts the nook back exactly as it was built, whatever happened to it.
function PuzzleService:release(why: string?)
	if self.board then self.board:SetAttribute("Solved", false) end
	for index, part in pairs(self.pieces) do
		local state = self.home[index]
		if state then restore(part, state) end
	end
	for _, slot in pairs(self.slots) do
		slot.Transparency = 0.85
	end
	for _, prompt in pairs(self.slotPrompts) do
		if prompt.Parent then prompt.Enabled = true end
	end
	for _, prompt in pairs(self.piecePrompts) do
		if prompt.Parent then prompt.Enabled = true end
	end
	self.session = nil
	self.solvedAt = nil
	self.lastRelease = why
end

-- The one place the session can end. Timeout, a solver who wandered into a
-- match or a queue, a character that disappeared, and the pause after a solve
-- all land here rather than being scattered through the handlers.
function PuzzleService:step(now: number)
	if not self.enabled then return end
	if self.solvedAt then
		if now - self.solvedAt >= PuzzleService.CELEBRATE then
			self:release("celebrated")
		end
		return
	end
	local s = self.session
	if not s then return end
	if now - s.touchedAt >= PuzzleService.TIMEOUT then
		self:release("timed out")
		return
	end
	local player = s.player
	if not player.Parent then
		self:release("left")
		return
	end
	if not rootOf(player) then
		self:release("no character")
		return
	end
	if self.matchmaking
		and (self.matchmaking.matchFor(player) or self.matchmaking.isQueued(player)) then
		self:release("went to play")
	end
end

function PuzzleService:playerLeaving(player: any)
	if self:_isSolver(player) then
		self:release("left")
	end
end

-- ── Diagnostics ───────────────────────────────────────────────────────────

function PuzzleService:status(now: number): any
	local s = self.session
	return {
		status = self.enabled and (s and "held" or (self.solvedAt and "solved" or "idle"))
			or ("disabled: " .. tostring(self.reason)),
		solver = s and tostring(s.player.Name) or "",
		placed = s and s.count or 0,
		held = s and (s.held or 0) or 0,
		age = s and math.floor(now - s.startedAt) or -1,
	}
end

PuzzleService.REWARD = SkinData.SECRET_ID

return PuzzleService
