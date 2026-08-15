-- Block Arena lobby — 06: finish pass, wayfinding and props.
--
-- 01-04 build geometry. This file owns the material language, so the art
-- direction lives in one place instead of being scattered across five builders.
--
-- The de-neon rule: an outline of light around every object is a wireframe
-- look, not a place. Emissive is reserved for things that are genuinely signs
-- or genuinely interactive; every other neon strip becomes brushed metal, which
-- still catches the light and reads as trim without glowing.

local Lobby = workspace:WaitForChild("Lobby")
-- Cleared so a re-run replaces the signs and props instead of doubling them.
Lobby.Signage:ClearAllChildren()
Lobby.Props:ClearAllChildren()

local C = {
	metal = Color3.fromRGB(112, 114, 124),
	metalDark = Color3.fromRGB(66, 68, 78),
	concrete = Color3.fromRGB(64, 63, 68),
	concreteDark = Color3.fromRGB(46, 45, 50),
	wood = Color3.fromRGB(92, 64, 42),
	leaf = Color3.fromRGB(38, 62, 44),
	soil = Color3.fromRGB(34, 30, 28),
	panel = Color3.fromRGB(38, 38, 46),
	white = Color3.fromRGB(238, 242, 250),
	muted = Color3.fromRGB(158, 162, 176),
	cy = Color3.fromRGB(0, 216, 232),
	mg = Color3.fromRGB(226, 60, 190),
}
local CONCRETE, METAL, WOOD, GRASS, NEON, PLASTIC =
	Enum.Material.Concrete, Enum.Material.Metal, Enum.Material.WoodPlanks,
	Enum.Material.LeafyGrass, Enum.Material.Neon, Enum.Material.SmoothPlastic

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

-- ══ De-neon ══════════════════════════════════════════════════════════════
-- Stays fully emissive: piece cells, block cores, station faces, the puzzle
-- slots, city windows and the ceiling lenses. Everything here is either a sign,
-- a light fixture, or the thing a player is meant to look at.
local KEEP = {
	Cell = true, Core = true, Heart = true, Crown = true, PadFace = true,
	Slot = true, Beacon = true, FixtureLens = true, Uplight = true,
	PortalPlane = true, TableOrb = true,
}
-- Stays emissive but pulled right back: cove strips, spinning station rings and
-- the city windows read as light sources, not as outlines.
local function isDim(name)
	return name:match("^Ring_") ~= nil or name == "Cove" or name == "PadGlow"
		or name == "Windows" or name == "PortalGlow" or name == "CrownHalo"
		or name == "ChairGlow" or name == "Lantern"
end

local converted, dimmed = 0, 0
for _, d in ipairs(Lobby:GetDescendants()) do
	if d:IsA("BasePart") and d.Material == NEON and not d:IsDescendantOf(Lobby.FX) then
		if KEEP[d.Name] then
			-- left alone
		elseif isDim(d.Name) then
			d.Transparency = math.max(d.Transparency, 0.55)
			d.Color = d.Color:Lerp(C.white, 0.3)
			dimmed += 1
		else
			d.Material = METAL
			d.Color = d.Color:Lerp(C.metal, 0.76)
			d.Transparency = 0
			d.Reflectance = 0.08
			converted += 1
		end
	end
end

-- ══ Wayfinding ═══════════════════════════════════════════════════════════
-- Hung from the beam soffit at 94 down to head-clearing height, the way an
-- arena concourse signs its zones. Double-sided so they work on the way back.
-- No sign for the arena: the marquee is 150 studs wide and says BLOCK ARENA in
-- letters two storeys tall. A hanging sign in front of it was both redundant
-- and sitting directly across the title.
local SIGNS = {
	{ x = 0, z = -16, w = 30, text = "MATCHMAKING", accent = C.cy },
	{ x = -60, z = -20, w = 26, text = "MUSEUM", accent = C.mg },
	{ x = 60, z = -8, w = 28, text = "LEADERBOARD", accent = C.cy },
	{ x = -48, z = 66, w = 26, text = "TRAINING", accent = C.cy },
	{ x = 48, z = 66, w = 24, text = "LOUNGE", accent = C.mg },
}
for _, s in ipairs(SIGNS) do
	local y = 40
	for _, dx in ipairs({ -s.w / 2 + 3, s.w / 2 - 3 }) do
		mk("SignRod", Lobby.Signage, V(0.5, 94 - y - 3, 0.5), P(s.x + dx, (94 + y + 3) / 2, s.z),
			C.metalDark, METAL)
	end
	local panel = mk("SignPanel", Lobby.Signage, V(s.w, 7, 1), P(s.x, y, s.z), C.panel, METAL,
		{ shadow = true })
	mk("SignTrim", Lobby.Signage, V(s.w + 0.6, 0.5, 1.4), P(s.x, y + 3.7, s.z), s.accent, METAL)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face, sg.SizingMode, sg.PixelsPerStud = face, Enum.SurfaceGuiSizingMode.PixelsPerStud, 40
		sg.LightInfluence, sg.Brightness = 0, 1.4
		sg.Parent = panel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency, l.Size, l.Position = 1, UDim2.fromScale(0.9, 0.62), UDim2.fromScale(0.05, 0.19)
		l.Font, l.Text, l.TextColor3, l.TextScaled = Enum.Font.GothamBold, s.text, C.white, true
		l.Parent = sg
	end
end

-- ══ Props ════════════════════════════════════════════════════════════════
-- Benches around the plaza rim: concrete plinth, timber slats. The one warm
-- material in the hall, and the reason the plaza edge reads as somewhere to be.
local BENCHES = {
	{ -30, -20, 0 }, { 0, -20, 0 }, { 30, -20, 0 },
	{ -30, 60, 0 }, { 0, 60, 0 }, { 30, 60, 0 },
	{ -52, 20, 90 }, { 52, 20, 90 },
}
for _, b in ipairs(BENCHES) do
	local cf = P(b[1], 0, b[2]) * CFrame.Angles(0, math.rad(b[3]), 0)
	mk("BenchPlinth", Lobby.Props, V(14, 2.2, 4.4), cf * CFrame.new(0, 1.1, 0), C.concreteDark, CONCRETE,
		{ collide = true, shadow = true })
	for _, dz in ipairs({ -1.3, 0, 1.3 }) do
		mk("BenchSlat", Lobby.Props, V(14.6, 0.45, 1.1), cf * CFrame.new(0, 2.4, dz), C.wood, WOOD,
			{ collide = true })
	end
end

-- Planters. Foliage keeps the hall from being entirely mineral.
local PLANTERS = {
	{ -62, -46 }, { 62, -46 }, { -62, 86 }, { 62, 86 },
	{ -120, 46 }, { 120, 46 }, { -120, -66 }, { 120, -66 },
}
for _, p in ipairs(PLANTERS) do
	mk("PlanterBox", Lobby.Props, V(12, 4.5, 12), P(p[1], 2.25, p[2]), C.concrete, CONCRETE,
		{ collide = true, shadow = true })
	mk("PlanterRim", Lobby.Props, V(13, 0.6, 13), P(p[1], 4.6, p[2]), C.metalDark, METAL)
	mk("Soil", Lobby.Props, V(10.6, 0.6, 10.6), P(p[1], 4.4, p[2]), C.soil, PLASTIC)
	local rng = Random.new(p[1] * 31 + p[2])
	for _ = 1, 5 do
		local h = rng:NextNumber(5, 11)
		mk("Foliage", Lobby.Props, V(rng:NextNumber(2.4, 4.4), h, rng:NextNumber(2.4, 4.4)),
			P(p[1] + rng:NextNumber(-3, 3), 4.6 + h / 2, p[2] + rng:NextNumber(-3, 3)) *
			CFrame.Angles(0, rng:NextNumber(0, 6), 0), C.leaf, GRASS, { shadow = true })
	end
end

-- Stanchions channelling the approach to the portal.
for _, s in ipairs({ -1, 1 }) do
	for i = 0, 3 do
		local z = -96 - i * 8
		mk("Stanchion", Lobby.Props, V(1.1, 5, 1.1), P(s * 22, 2.5, z), C.metalDark, METAL,
			{ collide = true })
		mk("StanchionTop", Lobby.Props, V(1.8, 0.7, 1.8), P(s * 22, 5.2, z), C.metal, METAL)
		if i < 3 then
			mk("Rope", Lobby.Props, V(0.35, 0.35, 8), P(s * 22, 4.2, z - 4), C.mg, PLASTIC, { tr = 0.15 })
		end
	end
end

return ("finish — %d neon parts converted to metal, %d dimmed, %d signs, %d props")
	:format(converted, dimmed, #SIGNS, #Lobby.Props:GetChildren())
