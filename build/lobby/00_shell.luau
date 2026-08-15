-- Block Arena lobby — 00: the hall.
--
-- Replaces the flat slab-in-a-void. This is an actual building: concrete floor
-- with inlay banding, a three-step sunken plaza for the core, a colonnade of
-- real columns, full-height glazing onto the city, and a beamed coffer ceiling.
--
-- Vertical datum:
--   -4.5  sunken plaza floor
--    0    main concourse floor
--    1.5  zone platform tops
--   16    glazing sill
--   86    glazing head
--   94    beam soffit  (portal facade tops out at 84, leaderboard crown at 93)
--  102    ceiling slab underside
--
-- Nothing here is emissive except the coffer fixtures. Neon is signage only.

for _, n in ipairs({ "Arena", "Lobby" }) do
	local old = workspace:FindFirstChild(n)
	if old then old:Destroy() end
end

local Lobby = Instance.new("Folder"); Lobby.Name = "Lobby"; Lobby.Parent = workspace
local F = {}
for _, n in ipairs({ "Shell", "Ceiling", "Plaza", "Skyline", "Core", "Portal", "Matchmaking",
	"Leaderboard", "Museum", "Training", "Social", "Secret", "Lights", "Holo", "Signage", "Props", "FX" }) do
	local f = Instance.new("Folder"); f.Name = n; f.Parent = Lobby; F[n] = f
end

-- Dark concrete, not grey concrete. Under the ceiling rig these read as a lit
-- dark hall; any lighter and the whole room washes out to pale blue-grey.
local C = {
	floor = Color3.fromRGB(46, 45, 51),
	floorDark = Color3.fromRGB(33, 32, 37),
	floorLight = Color3.fromRGB(60, 59, 65),
	wall = Color3.fromRGB(37, 36, 42),
	wallDark = Color3.fromRGB(27, 27, 32),
	metal = Color3.fromRGB(96, 98, 108),
	metalDark = Color3.fromRGB(50, 52, 60),
	glass = Color3.fromRGB(44, 58, 78),
	tower = Color3.fromRGB(22, 22, 29),
	cy = Color3.fromRGB(0, 216, 232),
	mg = Color3.fromRGB(226, 60, 190),
	warm = Color3.fromRGB(255, 244, 224),
}
local CONCRETE, SLATE, METAL, GLASS, PLASTIC, NEON =
	Enum.Material.Concrete, Enum.Material.Slate, Enum.Material.Metal,
	Enum.Material.Glass, Enum.Material.SmoothPlastic, Enum.Material.Neon

local function mk(name, parent, size, cf, colour, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cf, colour, mat
	p.Anchored = true
	p.CanCollide = o.collide == true
	p.CastShadow = o.shadow == true
	p.Transparency = o.tr or 0
	p.Reflectance = o.ref or 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function V(x, y, z) return Vector3.new(x, y, z) end
local function P(x, y, z) return CFrame.new(x, y, z) end

-- ── Floor: four slabs around the sunken plaza void ───────────────────────
-- Void is 92x92 centred on (0,20), which is where the plaza drops in.
mk("FloorN", F.Shell, V(300, 6, 124), P(0, -3, -88), C.floor, CONCRETE, { collide = true, shadow = true })
mk("FloorS", F.Shell, V(300, 6, 84), P(0, -3, 108), C.floor, CONCRETE, { collide = true, shadow = true })
mk("FloorW", F.Shell, V(104, 6, 92), P(-98, -3, 20), C.floor, CONCRETE, { collide = true, shadow = true })
mk("FloorE", F.Shell, V(104, 6, 92), P(98, -3, 20), C.floor, CONCRETE, { collide = true, shadow = true })

-- Inlay banding. Replaces the old neon floor grid: same job — breaking up a
-- 300-stud span — done with a change of material instead of a change of light.
for _, x in ipairs({ -125, -75, -25, 25, 75, 125 }) do
	mk("Joint", F.Shell, V(1.6, 0.12, 300), P(x, 0.06, 0), C.floorDark, SLATE)
end
for _, z in ipairs({ -125, -75, -25, 25, 75, 125 }) do
	mk("Joint", F.Shell, V(300, 0.12, 1.6), P(0, 0.06, z), C.floorDark, SLATE)
end
-- Broad walkways from the plaza out to each zone, in a lighter concrete.
local WALKS = {
	{ 0, -85, 26, 62 }, { 0, 108, 26, 60 },
	{ -84, 20, 62, 22 }, { 84, 20, 62, 22 },
	{ -62, 84, 24, 44 }, { 62, 84, 24, 44 },
}
for _, w in ipairs(WALKS) do
	mk("Walk", F.Shell, V(w[3], 0.16, w[4]), P(w[1], 0.08, w[2]), C.floorLight, CONCRETE)
	mk("WalkEdge", F.Shell, V(w[3] + 1.2, 0.2, 0.7), P(w[1], 0.1, w[2] - w[4] / 2), C.metalDark, METAL)
	mk("WalkEdge", F.Shell, V(w[3] + 1.2, 0.2, 0.7), P(w[1], 0.1, w[2] + w[4] / 2), C.metalDark, METAL)
end

-- ── Sunken plaza: three steps down to the core ───────────────────────────
-- Risers of 1.5 so the default humanoid walks them without jumping.
local PX, PZ = 0, 20
for i, ring in ipairs({ { 46, 6, -4.5 }, { 40, 6, -6.0 } }) do
	local half, tread, cy = ring[1], ring[2], ring[3]
	local outer = half * 2
	local inset = half - tread / 2
	mk("Step", F.Plaza, V(outer, 6, tread), P(PX, cy, PZ - inset), C.floor, CONCRETE, { collide = true })
	mk("Step", F.Plaza, V(outer, 6, tread), P(PX, cy, PZ + inset), C.floor, CONCRETE, { collide = true })
	mk("Step", F.Plaza, V(tread, 6, outer - tread * 2), P(PX - inset, cy, PZ), C.floor, CONCRETE, { collide = true })
	mk("Step", F.Plaza, V(tread, 6, outer - tread * 2), P(PX + inset, cy, PZ), C.floor, CONCRETE, { collide = true })
	-- Metal nosing on each tread: the detail that makes a step read as a step.
	local top = cy + 3
	mk("Nosing", F.Plaza, V(outer, 0.25, 0.8), P(PX, top + 0.05, PZ - half + 0.4), C.metal, METAL)
	mk("Nosing", F.Plaza, V(outer, 0.25, 0.8), P(PX, top + 0.05, PZ + half - 0.4), C.metal, METAL)
	mk("Nosing", F.Plaza, V(0.8, 0.25, outer), P(PX - half + 0.4, top + 0.05, PZ), C.metal, METAL)
	mk("Nosing", F.Plaza, V(0.8, 0.25, outer), P(PX + half - 0.4, top + 0.05, PZ), C.metal, METAL)
	local _ = i
end
mk("PlazaFloor", F.Plaza, V(68, 6, 68), P(PX, -7.5, PZ), C.floorLight, CONCRETE, { collide = true, shadow = true })
-- Concentric inlay in the plaza floor, centred under the core.
for _, s in ipairs({ 56, 44, 32 }) do
	mk("PlazaInlay", F.Plaza, V(s, 0.14, s), P(PX, -4.43, PZ), C.floorDark, SLATE)
	mk("PlazaInlay", F.Plaza, V(s - 2, 0.16, s - 2), P(PX, -4.42, PZ), C.floorLight, CONCRETE)
end
mk("PlazaMedallion", F.Plaza, V(20, 0.2, 20), P(PX, -4.4, PZ), C.metalDark, METAL, { ref = 0.15 })

-- ── Colonnade ─────────────────────────────────────────────────────────────
local COLS = {}
for _, v in ipairs({ -125, -75, -25, 25, 75, 125 }) do
	table.insert(COLS, { -146, v }); table.insert(COLS, { 146, v })
	table.insert(COLS, { v, -146 }); table.insert(COLS, { v, 146 })
end
for _, v in ipairs({ { -146, -146 }, { -146, 146 }, { 146, -146 }, { 146, 146 } }) do
	table.insert(COLS, v)
end
for _, c in ipairs(COLS) do
	local x, z = c[1], c[2]
	mk("ColumnBase", F.Shell, V(12, 3, 12), P(x, 1.5, z), C.metalDark, METAL, { collide = true, shadow = true })
	mk("Column", F.Shell, V(8.5, 91, 8.5), P(x, 48.5, z), C.wall, CONCRETE, { collide = true, shadow = true })
	mk("ColumnReveal", F.Shell, V(9.2, 88, 1.2), P(x, 48.5, z), C.metalDark, METAL)
	mk("ColumnReveal", F.Shell, V(1.2, 88, 9.2), P(x, 48.5, z), C.metalDark, METAL)
	mk("ColumnCap", F.Shell, V(12, 3, 12), P(x, 92.5, z), C.metalDark, METAL, { shadow = true })
end

-- ── Perimeter wall: solid base, glazing, fascia ──────────────────────────
local WALLS = {
	{ p = V(0, 0, -152), s = "z" }, { p = V(0, 0, 152), s = "z" },
	{ p = V(-152, 0, 0), s = "x" }, { p = V(152, 0, 0), s = "x" },
}
for _, w in ipairs(WALLS) do
	local long = w.s == "z" and V(312, 1, 8) or V(8, 1, 312)
	mk("WallBase", F.Shell, V(long.X, 16, long.Z), CFrame.new(w.p.X, 8, w.p.Z),
		C.wall, CONCRETE, { collide = true, shadow = true })
	mk("WallSill", F.Shell, V(long.X + 1, 1.4, long.Z + 1), CFrame.new(w.p.X, 16.6, w.p.Z), C.metalDark, METAL)
	mk("Fascia", F.Shell, V(long.X, 16, long.Z), CFrame.new(w.p.X, 94, w.p.Z),
		C.wall, CONCRETE, { collide = true, shadow = true })
	mk("FasciaTrim", F.Shell, V(long.X + 1, 1.4, long.Z + 1), CFrame.new(w.p.X, 85.6, w.p.Z), C.metalDark, METAL)
	-- Glazing: one pane per side, mullioned. Kept collidable so nobody walks out.
	local pane = w.s == "z" and V(304, 70, 1.4) or V(1.4, 70, 304)
	mk("Glazing", F.Shell, pane, CFrame.new(w.p.X, 51, w.p.Z), C.glass, GLASS,
		{ collide = true, tr = 0.72, ref = 0.28 })
	for _, v in ipairs({ -140, -115, -90, -65, -40, -15, 10, 35, 60, 85, 110, 135 }) do
		local mp = w.s == "z" and V(v, 51, w.p.Z) or V(w.p.X, 51, v)
		mk("Mullion", F.Shell, w.s == "z" and V(1.4, 70, 2.2) or V(2.2, 70, 1.4),
			CFrame.new(mp), C.metalDark, METAL)
	end
	for _, y in ipairs({ 40, 63 }) do
		mk("Transom", F.Shell, w.s == "z" and V(304, 1.2, 2.2) or V(2.2, 1.2, 304),
			CFrame.new(w.p.X, y, w.p.Z), C.metalDark, METAL)
	end
end

-- ── Ceiling: beams, coffers, slab ────────────────────────────────────────
mk("CeilingSlab", F.Ceiling, V(312, 6, 312), P(0, 105, 0), C.wallDark, CONCRETE, { shadow = true })
for _, v in ipairs({ -150, -100, -50, 0, 50, 100, 150 }) do
	mk("Beam", F.Ceiling, V(7, 8, 312), P(v, 98, 0), C.wall, CONCRETE, { shadow = true })
	mk("Beam", F.Ceiling, V(312, 8, 7), P(0, 98, v), C.wall, CONCRETE, { shadow = true })
	mk("BeamTrim", F.Ceiling, V(8, 0.8, 312), P(v, 93.8, 0), C.metalDark, METAL)
	mk("BeamTrim", F.Ceiling, V(312, 0.8, 8), P(0, 93.8, v), C.metalDark, METAL)
end
-- One recessed panel per 50x50 bay. Fixtures go in these (see 05_lighting_rig).
local BAYS = { -125, -75, -25, 25, 75, 125 }
for _, x in ipairs(BAYS) do
	for _, z in ipairs(BAYS) do
		mk("Coffer", F.Ceiling, V(44, 1.2, 44), P(x, 101, z), C.wallDark, CONCRETE)
		mk("CofferReveal", F.Ceiling, V(45.6, 0.6, 45.6), P(x, 100.2, z), C.metalDark, METAL)
	end
end

-- ── Zone platforms: concrete pads with a metal lip, 1.5 up from the floor ─
-- The Core has no platform any more; it sits in the plaza.
local ZONES = {
	{ n = "Matchmaking", x = 0, z = -40, w = 120, d = 50, c = C.cy },
	{ n = "Museum", x = -95, z = -20, w = 50, d = 50, c = C.mg },
	{ n = "Leaderboard", x = 95, z = -10, w = 40, d = 80, c = C.cy },
	{ n = "Training", x = -75, z = 95, w = 80, d = 80, c = C.cy },
	{ n = "Social", x = 75, z = 95, w = 60, d = 60, c = C.mg },
}
for _, z in ipairs(ZONES) do
	local dest = F[z.n]
	mk("Platform", dest, V(z.w, 3, z.d), P(z.x, 0, z.z), C.floorLight, CONCRETE,
		{ collide = true, shadow = true })
	mk("PlatformInlay", dest, V(z.w - 10, 0.14, z.d - 10), P(z.x, 1.57, z.z), C.floorDark, SLATE)
	local hw, hd = z.w / 2, z.d / 2
	mk("Lip", dest, V(z.w + 1.4, 0.7, 1.4), P(z.x, 1.3, z.z - hd), C.metal, METAL)
	mk("Lip", dest, V(z.w + 1.4, 0.7, 1.4), P(z.x, 1.3, z.z + hd), C.metal, METAL)
	mk("Lip", dest, V(1.4, 0.7, z.d + 1.4), P(z.x - hw, 1.3, z.z), C.metal, METAL)
	mk("Lip", dest, V(1.4, 0.7, z.d + 1.4), P(z.x + hw, 1.3, z.z), C.metal, METAL)
	-- Cove light tucked under the lip. The only emissive thing on a platform.
	mk("Cove", dest, V(z.w + 0.6, 0.35, 0.5), P(z.x, 0.5, z.z - hd - 0.4), z.c, NEON, { tr = 0.45 })
	mk("Cove", dest, V(z.w + 0.6, 0.35, 0.5), P(z.x, 0.5, z.z + hd + 0.4), z.c, NEON, { tr = 0.45 })
	mk("Cove", dest, V(0.5, 0.35, z.d + 0.6), P(z.x - hw - 0.4, 0.5, z.z), z.c, NEON, { tr = 0.45 })
	mk("Cove", dest, V(0.5, 0.35, z.d + 0.6), P(z.x + hw + 0.4, 0.5, z.z), z.c, NEON, { tr = 0.45 })
end

-- ── City outside the glazing ─────────────────────────────────────────────
-- Dimmer and sparser than the old skyline: it is scenery seen through glass,
-- not a light source, and it should not compete with the hall.
local rng = Random.new(20260815)
for i = 0, 43 do
	local a = math.rad(i * 8.2 + rng:NextNumber(-3, 3))
	local r = rng:NextNumber(300, 620)
	local x, z = math.sin(a) * r, math.cos(a) * r
	local h, w = rng:NextNumber(120, 400), rng:NextNumber(34, 78)
	mk("Tower", F.Skyline, V(w, h, w), P(x, -120 + h / 2, z), C.tower, CONCRETE)
	for k = 1, math.floor(h / 34) do
		mk("Windows", F.Skyline, V(w + 0.6, 1.6, w + 0.6), P(x, -120 + k * 34, z),
			(i % 3 == 0) and C.warm or C.metal, NEON, { tr = 0.62 })
	end
	mk("Beacon", F.Skyline, V(3.4, 3.4, 3.4), P(x, -120 + h + 4, z), Color3.fromRGB(255, 96, 96), NEON, { tr = 0.3 })
end

return ("hall shell — %d parts (%d shell, %d ceiling, %d plaza)")
	:format(#Lobby:GetDescendants(), #F.Shell:GetChildren(), #F.Ceiling:GetChildren(), #F.Plaza:GetChildren())
