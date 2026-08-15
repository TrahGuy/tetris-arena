-- Block Arena lobby — 05: white hologram light rig.
--
-- Neon strips glow but they light almost nothing, so the first pass had plenty
-- of colour and no illumination. These are white and they exist to put value on
-- the carbon deck and the glass: overhead panels wash the open spans, pillars
-- fill the gaps between zones at eye level.
--
-- White on purpose. Every zone already owns an accent colour; adding more
-- coloured light muddies them. White reads as "hologram" and lets the accents
-- stay legible against it.

local Lobby = workspace:WaitForChild("Lobby")
local F = Lobby:FindFirstChild("Holo") or Instance.new("Folder")
F.Name, F.Parent = "Holo", Lobby
F:ClearAllChildren()

local WHITE = Color3.fromRGB(234, 246, 255)
local COOL = Color3.fromRGB(198, 216, 255)
local BASE = Color3.fromRGB(22, 19, 33)
local SMOOTH, NEON, FF = Enum.Material.SmoothPlastic, Enum.Material.Neon, Enum.Material.ForceField

local function mk(name, size, cf, colour, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cf, colour, mat
	p.Anchored = true
	p.CanCollide = o.collide == true
	p.CastShadow = false
	p.Transparency = o.tr or 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = F
	return p
end
local function V(x, y, z) return Vector3.new(x, y, z) end
local function P(x, y, z) return CFrame.new(x, y, z) end
local function lamp(pos, colour, range, brightness)
	local n = mk("Lamp", V(0.2, 0.2, 0.2), CFrame.new(pos), WHITE, SMOOTH, { tr = 1 })
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
	l.Parent = n
end

-- ── Overhead panels ───────────────────────────────────────────────────────
-- Placed over the areas people actually stand in, high enough to clear the
-- portal facade (84) and the leaderboard crown (93) without sitting on them.
local PANELS = {
	{ x = 0, z = 20 }, { x = 0, z = -45 }, { x = 0, z = 100 },
	{ x = -95, z = 5 }, { x = 95, z = 5 },
	{ x = -75, z = 95 }, { x = 75, z = 95 },
}
for _, p in ipairs(PANELS) do
	mk("HoloPanel", V(46, 0.8, 46), P(p.x, 56, p.z), WHITE, FF, { tr = 0.84 })
	mk("HoloCore", V(38, 0.35, 38), P(p.x, 56, p.z), WHITE, NEON, { tr = 0.62 })
	for _, e in ipairs({ { 0, -23, 47.4, 0.9 }, { 0, 23, 47.4, 0.9 }, { -23, 0, 0.9, 47.4 }, { 23, 0, 0.9, 47.4 } }) do
		mk("HoloRim", V(e[3], 0.9, e[4]), P(p.x + e[1], 56, p.z + e[2]), COOL, NEON, { tr = 0.25 })
	end
	-- A very faint shaft; any more opaque and it reads as a solid box.
	mk("HoloShaft", V(30, 50, 30), P(p.x, 30, p.z), WHITE, FF, { tr = 0.95 })
	lamp(V(p.x, 48, p.z), COOL, 130, 1.5)
end

-- ── Pillars ───────────────────────────────────────────────────────────────
-- Sited in the gaps between zones, and in pairs flanking the spawn->portal
-- walk rather than standing in the middle of it.
local PILLARS = {
	{ -53, 28 }, { 53, 28 },
	{ -18, 92 }, { 18, 92 },
	{ -18, -82 }, { 18, -82 },
	{ -132, 40 }, { 132, 40 },
	{ -105, -80 }, { 105, -80 },
}
for _, s in ipairs(PILLARS) do
	local x, z = s[1], s[2]
	mk("PillarBase", V(4.4, 1.6, 4.4), P(x, 1.6, z), BASE, SMOOTH, { collide = true })
	mk("PillarFoot", V(5, 0.4, 5), P(x, 2.6, z), COOL, NEON, { tr = 0.3 })
	mk("PillarShell", V(2.8, 24, 2.8), P(x, 15, z), WHITE, FF, { tr = 0.66 })
	mk("PillarCore", V(0.9, 24, 0.9), P(x, 15, z), WHITE, NEON)
	mk("PillarCap", V(4, 0.6, 4), P(x, 27.4, z), COOL, NEON, { tr = 0.2 })
	lamp(V(x, 22, z), COOL, 46, 1.7)
end

return ("holo rig — %d panels, %d pillars, %d instances")
	:format(#PANELS, #PILLARS, #F:GetChildren())
