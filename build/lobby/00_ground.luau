-- Block Arena lobby — 00: ground plan, zone pads, perimeter, skyline.
-- Run first; it creates workspace.Lobby and every zone folder the later
-- scripts write into. Idempotent.
--
-- Convention: deck top sits at y = 0. Cyan owns -X and magenta owns +X — the
-- 1v1 split is the lobby's spine and runs through floor grid, rim and pylons.

for _, n in ipairs({ "Arena", "Lobby" }) do
	local old = workspace:FindFirstChild(n)
	if old then old:Destroy() end
end

local Lobby = Instance.new("Folder"); Lobby.Name = "Lobby"; Lobby.Parent = workspace
local F = {}
for _, n in ipairs({ "Ground", "Perimeter", "Skyline", "Core", "Portal", "Matchmaking",
	"Leaderboard", "Museum", "Training", "Social", "Secret", "Lights", "FX" }) do
	local f = Instance.new("Folder"); f.Name = n; f.Parent = Lobby; F[n] = f
end

local C = {
	cy = Color3.fromRGB(0, 245, 255), mg = Color3.fromRGB(255, 43, 214),
	orange = Color3.fromRGB(255, 154, 43), gold = Color3.fromRGB(255, 205, 74),
	purple = Color3.fromRGB(139, 43, 255), violet = Color3.fromRGB(176, 130, 255),
	white = Color3.fromRGB(234, 246, 255),
	cyDim = Color3.fromRGB(0, 70, 78), mgDim = Color3.fromRGB(80, 14, 68),
	dark = Color3.fromRGB(11, 7, 20), darker = Color3.fromRGB(7, 4, 13),
	deep = Color3.fromRGB(5, 3, 10), glass = Color3.fromRGB(20, 32, 58),
	tower = Color3.fromRGB(9, 6, 16),
}
local SMOOTH, NEON, GLASS = Enum.Material.SmoothPlastic, Enum.Material.Neon, Enum.Material.Glass

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

-- ── Deck ──────────────────────────────────────────────────────────────────
mk("Deck", F.Ground, V(300, 6, 300), P(0, -3, 0), C.dark, SMOOTH,
	{ collide = true, shadow = true, ref = 0.15 })
mk("Tier2", F.Ground, V(270, 24, 270), P(0, -18, 0), C.darker, SMOOTH, { collide = true })
mk("Tier3", F.Ground, V(212, 30, 212), P(0, -45, 0), C.deep, SMOOTH, { collide = true })

for i = -5, 5 do
	local x = i * 25
	if i ~= 0 then
		mk("GridZ", F.Ground, V(0.35, 0.06, 300), P(x, 0.03, 0), x < 0 and C.cyDim or C.mgDim, NEON)
	end
	mk("GridX", F.Ground, V(150, 0.06, 0.35), P(-75, 0.03, i * 25), C.cyDim, NEON)
	mk("GridX", F.Ground, V(150, 0.06, 0.35), P(75, 0.03, i * 25), C.mgDim, NEON)
end
mk("Spine", F.Ground, V(0.9, 0.08, 300), P(0, 0.04, 0), C.violet, NEON)

mk("RimL", F.Ground, V(1.6, 1.4, 300), P(-149.2, -0.5, 0), C.cy, NEON)
mk("RimR", F.Ground, V(1.6, 1.4, 300), P(149.2, -0.5, 0), C.mg, NEON)
for _, z in ipairs({ -149.2, 149.2 }) do
	mk("RimZ", F.Ground, V(149.2, 1.4, 1.6), P(-74.6, -0.5, z), C.cy, NEON)
	mk("RimZ", F.Ground, V(149.2, 1.4, 1.6), P(74.6, -0.5, z), C.mg, NEON)
end

-- ── Zone pads: glass over a coloured underglow ────────────────────────────
-- Matchmaking is deliberately wide and close to the core: PLAY should be a
-- short walk, not a hunt across 300 studs.
local ZONES = {
	{ n = "Core", x = 0, z = 20, w = 60, d = 60, c = C.violet },
	{ n = "Matchmaking", x = 0, z = -40, w = 120, d = 50, c = C.orange },
	{ n = "Museum", x = -95, z = -20, w = 50, d = 50, c = C.purple },
	{ n = "Leaderboard", x = 95, z = -10, w = 40, d = 80, c = C.gold },
	{ n = "Training", x = -75, z = 95, w = 80, d = 80, c = C.cy },
	{ n = "Social", x = 75, z = 95, w = 60, d = 60, c = C.mg },
}
for _, z in ipairs(ZONES) do
	local dest = F[z.n]
	mk("Glow", dest, V(z.w - 3, 0.2, z.d - 3), P(z.x, 0.3, z.z), z.c, NEON, { tr = 0.55 })
	mk("Glass", dest, V(z.w, 0.6, z.d), P(z.x, 0.7, z.z), C.glass, GLASS,
		{ collide = true, tr = 0.6, ref = 0.25 })
	local hw, hd = z.w / 2, z.d / 2
	mk("Edge", dest, V(z.w + 1.4, 0.9, 1.4), P(z.x, 0.85, z.z - hd), z.c, NEON)
	mk("Edge", dest, V(z.w + 1.4, 0.9, 1.4), P(z.x, 0.85, z.z + hd), z.c, NEON)
	mk("Edge", dest, V(1.4, 0.9, z.d + 1.4), P(z.x - hw, 0.85, z.z), z.c, NEON)
	mk("Edge", dest, V(1.4, 0.9, z.d + 1.4), P(z.x + hw, 0.85, z.z), z.c, NEON)
end

-- ── Paths ─────────────────────────────────────────────────────────────────
local function path(x1, z1, x2, z2, colour)
	local a, b = Vector3.new(x1, 0.05, z1), Vector3.new(x2, 0.05, z2)
	local mid = (a + b) / 2
	mk("Path", F.Ground, V(3.2, 0.1, (b - a).Magnitude), CFrame.lookAt(mid, mid + (b - a).Unit),
		colour, NEON, { tr = 0.45 })
end
path(0, -10, 0, -95, C.orange)
path(0, -80, 0, -118, C.cy)
path(-30, 20, -70, -10, C.purple)
path(30, 20, 75, 10, C.gold)
path(-25, 45, -60, 80, C.cy)
path(25, 45, 60, 80, C.mg)

-- ── Perimeter ─────────────────────────────────────────────────────────────
for i = 0, 15 do
	local a = math.rad(i * 22.5)
	local x, z = math.sin(a) * 142, math.cos(a) * 142
	mk("PylonBase", F.Perimeter, V(5, 1.6, 5), P(x, 0.8, z), C.darker, SMOOTH, { collide = true })
	mk("Pylon", F.Perimeter, V(2, 46, 2), P(x, 24, z), x < 0 and C.cy or C.mg, NEON)
	mk("PylonCap", F.Perimeter, V(3.6, 0.8, 3.6), P(x, 47.4, z), C.white, NEON)
end
mk("BarL", F.Perimeter, V(3, 70, 306), P(-151, 35, 0), C.dark, SMOOTH, { collide = true, tr = 1 })
mk("BarR", F.Perimeter, V(3, 70, 306), P(151, 35, 0), C.dark, SMOOTH, { collide = true, tr = 1 })
mk("BarB", F.Perimeter, V(306, 70, 3), P(0, 35, -151), C.dark, SMOOTH, { collide = true, tr = 1 })
mk("BarF", F.Perimeter, V(306, 70, 3), P(0, 35, 151), C.dark, SMOOTH, { collide = true, tr = 1 })

-- ── Skyline ───────────────────────────────────────────────────────────────
-- The deck's corners reach 212 studs out, so anything nearer than that stands
-- on the lobby floor. Start clear of it and drop the bases into the void.
local rng = Random.new(20260815)
local BASE = -70
for i = 0, 39 do
	local a = math.rad(i * 9 + rng:NextNumber(-3.5, 3.5))
	local r = rng:NextNumber(232, 360)
	local x, z = math.sin(a) * r, math.cos(a) * r
	local h, w = rng:NextNumber(90, 240), rng:NextNumber(20, 46)
	local col = x < 0 and C.cy or C.mg
	mk("Tower", F.Skyline, V(w, h, w), P(x, BASE + h / 2, z), C.tower, SMOOTH)
	for k = 1, math.floor(h / 26) do
		mk("Windows", F.Skyline, V(w + 0.5, 1.4, w + 0.5), P(x, BASE + k * 26, z), col, NEON, { tr = 0.4 })
	end
	mk("Spire", F.Skyline, V(1.4, 14, 1.4), P(x, BASE + h + 7, z), col, NEON, { tr = 0.2 })
	mk("Beacon", F.Skyline, V(3, 3, 3), P(x, BASE + h + 15, z), C.white, NEON)
end

return ("ground plan — %d parts, %d zones"):format(#Lobby:GetDescendants(), #ZONES)
