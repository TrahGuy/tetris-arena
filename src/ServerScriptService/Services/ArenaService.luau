-- The battle dimension: one isolated arena per running match.
--
-- A match used to happen while both players stood in the lobby, which made the
-- most important thing the game does look like the least. Now the two of them
-- leave: the server moves their characters into a private arena high above the
-- hall, they play there, and it puts them back where it found them.
--
-- Same place, same server, no TeleportService. The board is still the ScreenGui
-- and nothing here touches it. This service owns geometry and where a character
-- is standing, and it owns nothing else -- it does not know who won, what the
-- score was, or what a rating is.
--
-- Everything is keyed by matchId rather than by slot. A release from a match
-- that finished ten seconds ago cannot tear down the match now standing in the
-- same slot, which is the same rule Phase 10 applies to every competitive
-- message and for the same reason.
--
-- The template is built in code rather than stored in the place file. That is
-- how the museum pads, the puzzle prompts and the Blitz pad already work here:
-- a live server picks the arena up without the .rbxl being edited, and the
-- source of truth stays in the repository where it can be read and diffed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)

local ArenaService = {}

-- Far above the lobby, which tops out around 100 studs, and far enough apart
-- that two matches cannot see or reach each other.
ArenaService.ORIGIN = Vector3.new(0, 5000, 0)
ArenaService.SLOT_SPACING = 1200
ArenaService.MAX_SLOTS = 12
ArenaService.FALL_LIMIT = 60 -- studs below the floor before a character is put back

local PLATFORM = 78          -- the arena floor is this wide
local SPAWN_OFFSET = 22      -- how far each player stands from the middle

local ACCENTS = {
	[Enums.Mode.Quick] = { Color3.fromRGB(0, 216, 232), Color3.fromRGB(158, 122, 255) },
	[Enums.Mode.Ranked] = { Color3.fromRGB(226, 60, 190), Color3.fromRGB(255, 61, 94) },
	[Enums.Mode.Private] = { Color3.fromRGB(255, 198, 96), Color3.fromRGB(158, 122, 255) },
}
local DEFAULT_ACCENT = ACCENTS[Enums.Mode.Quick]

local arenas: { [number]: any } = {}   -- matchId -> arena record
local slots: { [number]: number? } = {} -- slotIndex -> matchId
local root: Instance? = nil
local enabled = false

-- ── Building one ──────────────────────────────────────────────────────────

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame,
	colour: Color3, material: Enum.Material, opts: any?)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = opts.collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.Transparency = opts.transparency or 0
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- The arena itself. Deliberately small: a floor, a rim, two pads, a handful of
-- floating blocks and four lights. A board game does not need a stadium, and
-- every part here is replicated to both clients at the moment they most need
-- their frame rate.
local function build(container: Instance, accent: Color3, accent2: Color3)
	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = container
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = container

	-- Floor: a dark slab with a glowing inlay grid on top.
	part(geometry, "Floor", Vector3.new(PLATFORM, 3, PLATFORM), CFrame.new(0, -1.5, 0),
		Color3.fromRGB(12, 12, 18), Enum.Material.SmoothPlastic, { collide = true })
	part(geometry, "Rim", Vector3.new(PLATFORM + 3, 0.5, PLATFORM + 3), CFrame.new(0, 0.2, 0),
		accent, Enum.Material.Neon, { transparency = 0.35 })
	for i = -3, 3 do
		local at = i * (PLATFORM / 7)
		part(geometry, "GridX", Vector3.new(PLATFORM, 0.12, 0.35), CFrame.new(0, 0.06, at),
			accent, Enum.Material.Neon, { transparency = 0.82 })
		part(geometry, "GridZ", Vector3.new(0.35, 0.12, PLATFORM), CFrame.new(at, 0.06, 0),
			accent, Enum.Material.Neon, { transparency = 0.82 })
	end

	-- Two pads, facing each other across the middle.
	local spawns = {}
	for _, def in ipairs({ { "A", -SPAWN_OFFSET, accent }, { "B", SPAWN_OFFSET, accent2 } }) do
		local side, z, colour = def[1], def[2], def[3]
		part(geometry, "Pad" .. side, Vector3.new(14, 0.6, 14), CFrame.new(0, 0.3, z),
			colour:Lerp(Color3.new(0, 0, 0), 0.75), Enum.Material.SmoothPlastic, { collide = true })
		part(geometry, "PadRing" .. side, Vector3.new(15.5, 0.25, 15.5), CFrame.new(0, 0.75, z),
			colour, Enum.Material.Neon, { transparency = 0.3 })
		-- The marker the service teleports to. Rotated to look at the middle,
		-- so nobody arrives facing out into the void.
		local spawn = Instance.new("Part")
		spawn.Name = "Spawn" .. side
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.CanQuery = false
		spawn.CanTouch = false
		spawn.Transparency = 1
		spawn.Size = Vector3.new(2, 2, 2)
		spawn.CFrame = CFrame.lookAt(Vector3.new(0, 3.5, z), Vector3.new(0, 3.5, 0))
		spawn.Parent = container
		spawns[side] = spawn

		local light = Instance.new("PointLight")
		light.Color = colour
		light.Range = 34
		light.Brightness = 1.4
		light.Shadows = false
		light.Parent = spawn
	end

	-- Floating silhouettes: the tetromino motif, far enough out to read as
	-- scenery rather than clutter.
	local rng = Random.new(20250)
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2
		local radius = rng:NextNumber(70, 120)
		local at = Vector3.new(math.cos(angle) * radius, rng:NextNumber(-30, 45),
			math.sin(angle) * radius)
		part(decor, "Block", Vector3.new(6, 6, 6) * rng:NextNumber(0.5, 1.4),
			CFrame.new(at) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			(i % 2 == 0) and accent or accent2, Enum.Material.Neon,
			{ transparency = 0.86 })
	end

	-- Branding, on the floor where it is visible but never in the way.
	local sign = part(decor, "Brand", Vector3.new(40, 0.2, 10), CFrame.new(0, 0.1, 0),
		Color3.fromRGB(10, 10, 14), Enum.Material.SmoothPlastic, { transparency = 1 })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 26
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "BLOCK ARENA"
	label.TextColor3 = accent
	label.TextScaled = true
	label.TextTransparency = 0.45
	label.Parent = gui

	-- Bounds. Character controls are disabled during a match, but a respawn or
	-- a race can hand them back, and falling out of the world should not be one
	-- of the ways a match can end.
	local bounds = Instance.new("Folder")
	bounds.Name = "Bounds"
	bounds.Parent = container
	for _, def in ipairs({ { PLATFORM + 3, 0, (PLATFORM + 3) / 2 }, { PLATFORM + 3, 0, -(PLATFORM + 3) / 2 },
		{ 0, (PLATFORM + 3) / 2, 0 }, { 0, -(PLATFORM + 3) / 2, 0 } }) do
		local sizeX = def[1] > 0 and def[1] or 1
		local sizeZ = def[1] > 0 and 1 or (PLATFORM + 3)
		part(bounds, "Wall", Vector3.new(sizeX, 30, sizeZ),
			CFrame.new(def[2], 15, def[3]), Color3.new(), Enum.Material.SmoothPlastic,
			{ collide = true, transparency = 1 })
	end

	return spawns
end

-- ── Startup ───────────────────────────────────────────────────────────────

function ArenaService.init(): boolean
	root = workspace:FindFirstChild("MatchDimensions")
	if not root then
		local folder = Instance.new("Folder")
		folder.Name = "MatchDimensions"
		folder.Parent = workspace
		root = folder
	end
	-- Anything left by a previous run of this script in Edit mode.
	for _, child in ipairs((root :: Instance):GetChildren()) do
		child:Destroy()
	end
	table.clear(arenas)
	table.clear(slots)

	-- Prove the builder produces what the service needs before any match
	-- depends on it, and say so loudly if it does not.
	local probe = Instance.new("Model")
	local spawns = build(probe, DEFAULT_ACCENT[1], DEFAULT_ACCENT[2])
	local ok = spawns.A ~= nil and spawns.B ~= nil
		and spawns.A:IsA("BasePart") and spawns.B:IsA("BasePart")
		and (spawns.A.Position - spawns.B.Position).Magnitude > 1
		and probe:FindFirstChild("Geometry") ~= nil
	probe:Destroy()
	enabled = ok
	if not ok then
		warn("[Arena] template is malformed; matches will run in the lobby")
	end
	return ok
end

function ArenaService.isEnabled(): boolean
	return enabled
end

-- What a malformed template leaves behind, without having to ship one.
--
-- init() decides `enabled` by building a probe and looking at it, so the only
-- other way to reach the degraded path is to break the builder on purpose. The
-- path matters more than the way in: matches have to keep starting when there
-- is no arena to put them in.
function ArenaService.disableForTest()
	for matchId in pairs(arenas) do
		ArenaService.release(matchId)
	end
	table.clear(arenas)
	table.clear(slots)
	enabled = false
end

-- ── Slots ─────────────────────────────────────────────────────────────────

local function takeSlot(): number?
	for i = 1, ArenaService.MAX_SLOTS do
		if slots[i] == nil then return i end
	end
	return nil
end

local function slotCFrame(index: number): CFrame
	return CFrame.new(ArenaService.ORIGIN + Vector3.new((index - 1) * ArenaService.SLOT_SPACING, 0, 0))
end

-- ── Allocation ────────────────────────────────────────────────────────────

-- Returns the arena record, or nil and a reason. A caller that cannot get one
-- must not start the match: half a battle dimension is worse than none.
function ArenaService.allocate(matchId: number, mode: string?): (any?, string?)
	if not enabled then return nil, "arena disabled" end
	if not root then return nil, "not initialised" end
	if arenas[matchId] then return arenas[matchId] end
	local slot = takeSlot()
	if not slot then return nil, "no free arena slot" end

	local accent = ACCENTS[mode] or DEFAULT_ACCENT
	local model = Instance.new("Model")
	model.Name = "Match_" .. matchId
	local spawns = build(model, accent[1], accent[2])
	model:PivotTo(slotCFrame(slot))
	model:SetAttribute("MatchId", matchId)
	model:SetAttribute("Mode", mode or Enums.Mode.Quick)
	model:SetAttribute("SlotIndex", slot)
	model:SetAttribute("Active", true)
	model.Parent = root

	local arena = {
		matchId = matchId,
		mode = mode,
		slot = slot,
		model = model,
		spawns = spawns,
		centre = slotCFrame(slot).Position,
		players = {},  -- userId -> { player = , side = , home = CFrame }
	}
	arenas[matchId] = arena
	slots[slot] = matchId
	return arena
end

-- ── Moving people ─────────────────────────────────────────────────────────

local function pivotOf(player: any): CFrame?
	local char = player and player.Character
	if not char then return nil end
	local ok, cf = pcall(function() return char:GetPivot() end)
	return ok and cf or nil
end

-- Puts one player on their side of the arena and remembers where they were.
--
-- The destination is never anything a client said: it is the marker the server
-- built, on the side the match assigned.
function ArenaService.enter(matchId: number, player: any, side: string): boolean
	local arena = arenas[matchId]
	if not arena then return false end
	local spawn = arena.spawns[side]
	if not spawn then return false end
	local char = player and player.Character
	if not char then return false end

	local home = pivotOf(player)
	arena.players[player.UserId] = { player = player, side = side, home = home }
	local ok = pcall(function()
		char:PivotTo(spawn.CFrame)
	end)
	return ok
end

-- Puts one player back where they were standing, or somewhere safe.
function ArenaService.returnPlayer(matchId: number, player: any): boolean
	local arena = arenas[matchId]
	if not arena then return false end
	local record = arena.players[player.UserId]
	-- A stale call naming a match this player is no longer in must not move
	-- them out of the one they are in now.
	if not record then return false end
	arena.players[player.UserId] = nil

	local char = player and player.Character
	if not char then return false end
	local home = record.home
	if not home or home.Position.Y > ArenaService.ORIGIN.Y - 500 then
		-- Either nothing was captured or the captured spot is inside another
		-- arena, which can happen if a match somehow started from one.
		home = ArenaService.lobbySpawn()
	end
	local ok = pcall(function()
		char:PivotTo(home)
	end)
	return ok
end

function ArenaService.lobbySpawn(): CFrame
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.CFrame * CFrame.new(0, 4, 0)
	end
	return CFrame.new(0, 8, 20)
end

-- ── Release ───────────────────────────────────────────────────────────────

-- Sends everyone home and takes the arena away. Safe to call twice, safe to
-- call for a match that never had one, and -- because it is keyed by matchId --
-- unable to touch whatever is standing in the same slot now.
function ArenaService.release(matchId: number): boolean
	local arena = arenas[matchId]
	if not arena then return false end
	for _, record in pairs(arena.players) do
		if record.player and record.player.Parent then
			ArenaService.returnPlayer(matchId, record.player)
		end
	end
	arenas[matchId] = nil
	if slots[arena.slot] == matchId then
		slots[arena.slot] = nil
	end
	if arena.model and arena.model.Parent then
		arena.model:Destroy()
	end
	return true
end

-- A player who disconnects stops being this arena's problem immediately: their
-- match may not settle for another moment, and cleanup must not wait.
function ArenaService.forgetPlayer(player: any)
	for _, arena in pairs(arenas) do
		arena.players[player.UserId] = nil
	end
end

function ArenaService.arenaFor(matchId: number): any?
	return arenas[matchId]
end

-- Is this player standing in an arena right now, and which?
function ArenaService.matchOf(player: any): number?
	for matchId, arena in pairs(arenas) do
		if arena.players[player.UserId] then return matchId end
	end
	return nil
end

-- Character controls are off during a match, but a respawn hands them back and
-- a new character arrives in the lobby rather than the arena. Both cases end up
-- here: whoever is still assigned to a live arena gets put back on their pad.
function ArenaService.step()
	for _, arena in pairs(arenas) do
		for _, record in pairs(arena.players) do
			local char = record.player and record.player.Character
			local spawn = arena.spawns[record.side]
			if char and spawn then
				local cf = pivotOf(record.player)
				if cf and (cf.Position - spawn.Position).Magnitude > ArenaService.FALL_LIMIT then
					pcall(function() char:PivotTo(spawn.CFrame) end)
				end
			end
		end
	end
end

function ArenaService.debugSummary(): string
	local parts = {}
	for matchId, arena in pairs(arenas) do
		local n = 0
		for _ in pairs(arena.players) do n += 1 end
		table.insert(parts, ("#%d slot %d %s %dp"):format(matchId, arena.slot,
			tostring(arena.mode), n))
	end
	if #parts == 0 then return enabled and "idle" or "disabled" end
	table.sort(parts)
	return table.concat(parts, "  ||  ")
end

function ArenaService.activeCount(): number
	local n = 0
	for _ in pairs(arenas) do n += 1 end
	return n
end

return ArenaService
