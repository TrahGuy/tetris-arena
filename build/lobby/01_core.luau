-- Block Arena lobby — 01: the Tetris Core.
-- A floating wireframe cube with the seven tetrominoes orbiting it, over four
-- spawn platforms each shaped like a piece. Movement is driven by LobbyFX on
-- the client; this script only places the geometry and tags it.

local Lobby = workspace:WaitForChild("Lobby")
-- The plaza itself is 00_shell's; this folder holds only the core.
local F = Lobby.Core
F:ClearAllChildren()

local C = {
	violet = Color3.fromRGB(176, 130, 255), white = Color3.fromRGB(234, 246, 255),
	dark = Color3.fromRGB(46, 45, 50), darker = Color3.fromRGB(58, 60, 68),
	metal = Color3.fromRGB(112, 114, 124),
}
local PIECE = {
	I = { col = Color3.fromRGB(34, 228, 245), cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } } },
	O = { col = Color3.fromRGB(255, 216, 77), cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } },
	T = { col = Color3.fromRGB(194, 77, 255), cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } } },
	S = { col = Color3.fromRGB(61, 232, 107), cells = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } } },
	Z = { col = Color3.fromRGB(255, 61, 94), cells = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } } },
	J = { col = Color3.fromRGB(77, 130, 255), cells = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } } },
	L = { col = Color3.fromRGB(255, 154, 43), cells = { { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } } },
}
local ORDER = { "I", "O", "T", "S", "Z", "J", "L" }
local SMOOTH, NEON, FF = Enum.Material.SmoothPlastic, Enum.Material.Neon, Enum.Material.ForceField
local METAL = Enum.Material.Metal

local function mk(name, parent, size, cf, colour, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cf, colour, mat
	p.Anchored = true
	p.CanCollide = o.collide == true
	p.CastShadow = false
	p.Transparency = o.tr or 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function V(x, y, z) return Vector3.new(x, y, z) end
local function P(x, y, z) return CFrame.new(x, y, z) end

local CX, CY, CZ = 0, 36, 20
-- The plaza floor sits 4.5 below the concourse, so everything at ground level
-- inside it drops with it. The cube itself stays where it was.
local PLAZA = -4.5

mk("Dais", F, V(26, 3, 26), P(CX, PLAZA + 1.5, CZ), C.darker, METAL,
	{ collide = true, shadow = true })
mk("DaisTop", F, V(22, 0.2, 22), P(CX, PLAZA + 3.1, CZ), C.dark, SMOOTH)
for _, s in ipairs({ { 13, 0 }, { -13, 0 }, { 0, 13 }, { 0, -13 } }) do
	mk("DaisEdge", F, V(s[2] == 0 and 1.6 or 27.4, 1, s[2] == 0 and 27.4 or 1.6),
		P(CX + s[1], PLAZA + 3.2, CZ + s[2]), C.metal, METAL)
end
-- Barely there: at 0.72 this column washed straight over the marquee behind it.
mk("Beam", F, V(6, 29.5, 6), P(CX, PLAZA + 14.75, CZ), C.violet, FF, { tr = 0.9 })

local H, T = 11, 1.2
for _, s in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
	mk("EdgeX", F, V(2 * H + T, T, T), P(CX, CY + H * s[1], CZ + H * s[2]), C.white, NEON)
	mk("EdgeY", F, V(T, 2 * H, T), P(CX + H * s[1], CY, CZ + H * s[2]), C.white, NEON)
	mk("EdgeZ", F, V(T, T, 2 * H + T), P(CX + H * s[1], CY + H * s[2], CZ), C.white, NEON)
end
-- No solid hologram shell: it sat directly on the sightline from spawn to the
-- marquee and fogged the title. Twelve thin edges crossing it reads as layering;
-- a translucent 17-stud cube reads as a smear.
mk("Heart", F, V(6, 6, 6), P(CX, CY, CZ), C.white, NEON)
mk("HeartCage", F, V(9, 9, 9), P(CX, CY, CZ), C.violet, FF, { tr = 0.62 })

-- Each piece is a Model so LobbyFX can PivotTo it; the orbit phase lives on an
-- attribute so the script needs no table of its own.
local CELL, RADIUS = 3, 26
for i, key in ipairs(ORDER) do
	local def = PIECE[key]
	local model = Instance.new("Model"); model.Name = "Piece_" .. key; model.Parent = F

	local mx, mz = 0, 0
	for _, c in ipairs(def.cells) do mx += c[1]; mz += c[2] end
	mx, mz = mx / 4, mz / 4

	local angle = (i - 1) * (2 * math.pi / 7)
	local origin = Vector3.new(CX + math.sin(angle) * RADIUS, CY, CZ + math.cos(angle) * RADIUS)

	local root = mk("Root", model, V(0.4, 0.4, 0.4), CFrame.new(origin), C.white, SMOOTH, { tr = 1 })
	model.PrimaryPart = root
	for _, c in ipairs(def.cells) do
		local off = Vector3.new((c[1] - mx) * CELL, 0, (c[2] - mz) * CELL)
		mk("Shell", model, V(CELL, CELL, CELL), CFrame.new(origin + off),
			def.col:Lerp(Color3.new(0, 0, 0), 0.62), SMOOTH)
		mk("Core", model, V(CELL - 1.1, CELL - 1.1, CELL - 1.1), CFrame.new(origin + off), def.col, NEON)
	end
	model.WorldPivot = CFrame.new(origin)
	model:SetAttribute("Orbit", angle)
	model:SetAttribute("Piece", key)
end
F:SetAttribute("CoreCentre", Vector3.new(CX, CY, CZ))
F:SetAttribute("OrbitRadius", RADIUS)

-- ── Spawn platforms, each shaped like a tetromino ─────────────────────────
local PADS = {
	{ key = "T", x = -19, z = 3 }, { key = "L", x = 19, z = 3 },
	{ key = "S", x = -19, z = 37 }, { key = "O", x = 19, z = 37 },
}
local PCELL = 5
for _, pad in ipairs(PADS) do
	local def = PIECE[pad.key]
	local mx, mz = 0, 0
	for _, c in ipairs(def.cells) do mx += c[1]; mz += c[2] end
	mx, mz = mx / 4, mz / 4
	for _, c in ipairs(def.cells) do
		local x, z = pad.x + (c[1] - mx) * PCELL, pad.z + (c[2] - mz) * PCELL
		mk("PadCell", F, V(PCELL, 1.4, PCELL), P(x, PLAZA + 1.7, z),
			def.col:Lerp(C.dark, 0.62), METAL, { collide = true, shadow = true })
		mk("PadGlow", F, V(PCELL - 1.6, 0.16, PCELL - 1.6), P(x, PLAZA + 2.48, z), def.col, NEON, { tr = 0.3 })
	end
	-- Non-colliding, so it never gets in the way of the platform it sits on.
	local sp = Instance.new("SpawnLocation")
	sp.Name = "Spawn_" .. pad.key
	sp.Size = Vector3.new(6, 0.4, 6)
	-- Face the core, so the first thing a new player sees is the cube.
	sp.CFrame = CFrame.lookAt(Vector3.new(pad.x, PLAZA + 2.7, pad.z), Vector3.new(CX, PLAZA + 2.7, CZ))
	sp.Anchored, sp.CanCollide, sp.Transparency = true, false, 1
	sp.Neutral, sp.AllowTeamChangeOnTouch, sp.Duration = true, false, 0
	sp.Parent = F
end

-- Falling-block pool; LobbyFX drives these. Cleared first so a re-run replaces
-- the pool instead of doubling it.
Lobby.FX:ClearAllChildren()
for i = 1, 26 do
	mk("Faller", Lobby.FX, V(2.2, 2.2, 2.2), P(0, -80, 0), C.white, NEON, { tr = 1 })
		:SetAttribute("Slot", i)
end

local function lamp(pos, colour, range, brightness)
	local n = mk("Lamp", Lobby.Lights, V(0.2, 0.2, 0.2), CFrame.new(pos), C.white, SMOOTH, { tr = 1 })
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
	l.Parent = n
end
lamp(Vector3.new(CX, CY, CZ), C.violet, 90, 3)
lamp(Vector3.new(CX, 6, CZ), C.violet, 46, 1.8)

return ("core — %d instances, 7 pieces, %d spawn pads"):format(#F:GetDescendants(), #PADS)
