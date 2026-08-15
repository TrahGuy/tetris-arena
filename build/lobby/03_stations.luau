-- Block Arena lobby — 03: matchmaking stations and the leaderboard tower.
--
-- The pads are physically complete: they light, they spin, they are labelled.
-- Nothing queues yet. Phase 5 reads the PadMode attribute; Phase 8 replaces the
-- placeholder leaderboard rows. Neither needs the geometry to change.

local Lobby = workspace:WaitForChild("Lobby")
local FM, FL = Lobby.Matchmaking, Lobby.Leaderboard
FM:ClearAllChildren(); FL:ClearAllChildren()

local C = {
	orange = Color3.fromRGB(255, 154, 43), gold = Color3.fromRGB(255, 205, 74),
	red = Color3.fromRGB(255, 58, 74), blue = Color3.fromRGB(43, 107, 255),
	violet = Color3.fromRGB(176, 130, 255), white = Color3.fromRGB(234, 246, 255),
	dark = Color3.fromRGB(28, 23, 42), darker = Color3.fromRGB(20, 17, 30),
	glass = Color3.fromRGB(34, 52, 84), panel = Color3.fromRGB(30, 25, 45),
	muted = Color3.fromRGB(150, 142, 178),
}
local SMOOTH, NEON, FF, GLASS =
	Enum.Material.SmoothPlastic, Enum.Material.Neon, Enum.Material.ForceField, Enum.Material.Glass

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
local function label(parent, pos, size, text, font, colour, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency, l.Position, l.Size = 1, pos, size
	l.Font, l.Text, l.TextColor3, l.TextScaled = font, text, colour, true
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

-- ── Matchmaking ───────────────────────────────────────────────────────────
local MZ = -40
mk("Glow", FM, V(117, 0.2, 47), P(0, 0.3, MZ), C.orange, NEON, { tr = 0.55 })
mk("Glass", FM, V(120, 0.6, 50), P(0, 0.7, MZ), C.glass, GLASS, { collide = true, tr = 0.6, ref = 0.25 })
for _, e in ipairs({ { 0, -25, 121.4, 1.4 }, { 0, 25, 121.4, 1.4 }, { -60, 0, 1.4, 51.4 }, { 60, 0, 1.4, 51.4 } }) do
	mk("Edge", FM, V(e[3], 0.9, e[4]), P(e[1], 0.85, MZ + e[2]), C.orange, NEON)
end

-- PLAY sits dead centre on the spawn->portal axis and is the largest pad; the
-- other two are pushed out to +/-42 so their signs clear the demo boards.
local STATIONS = {
	{ mode = "quick", x = 0, w = 24, c = C.orange, title = "PLAY", sub = "QUICK MATCH", signY = 16, signH = 9 },
	{ mode = "ranked", x = -42, w = 18, c = C.red, title = "RANKED", sub = "COMPETITIVE", signY = 12.5, signH = 7.5 },
	{ mode = "private", x = 42, w = 18, c = C.blue, title = "CREATE ROOM", sub = "PRIVATE MATCH", signY = 12.5, signH = 7.5 },
}
for _, s in ipairs(STATIONS) do
	local h = s.w / 2
	local pad = mk("Pad_" .. s.mode, FM, V(s.w, 1.6, s.w), P(s.x, 1.8, MZ),
		s.c:Lerp(Color3.new(0, 0, 0), 0.72), SMOOTH, { collide = true })
	pad:SetAttribute("PadMode", s.mode)
	pad:SetAttribute("Accent", s.c)
	mk("PadFace", FM, V(s.w - 2.2, 0.18, s.w - 2.2), P(s.x, 2.7, MZ), s.c, NEON, { tr = 0.35 })
	for _, q in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
		mk("Post", FM, V(1.3, 9, 1.3), P(s.x + q[1] * h, 5.5, MZ + q[2] * h), s.c, NEON)
	end
	mk("Beam", FM, V(s.w - 4, 12, s.w - 4), P(s.x, 8.6, MZ), s.c, FF, { tr = 0.72 })
	mk("Ring_" .. s.mode, FM, V(s.w + 3, 0.5, s.w + 3), P(s.x, 11.5, MZ), s.c, NEON, { tr = 0.3 })
		:SetAttribute("SpinSeed", s.x)

	local sign = mk("Sign_" .. s.mode, FM, V(s.w + 6, s.signH, 0.5), P(s.x, s.signY, MZ), s.c, FF, { tr = 0.55 })
	local sg = Instance.new("SurfaceGui")
	sg.Face, sg.SizingMode, sg.PixelsPerStud = Enum.NormalId.Back, Enum.SurfaceGuiSizingMode.PixelsPerStud, 32
	sg.LightInfluence, sg.Brightness = 0, 2
	sg.Parent = sign
	label(sg, UDim2.fromScale(0, 0.05), UDim2.fromScale(1, 0.55), s.title, Enum.Font.GothamBold, s.c)
	label(sg, UDim2.fromScale(0, 0.62), UDim2.fromScale(1, 0.3), s.sub, Enum.Font.Gotham, C.muted)
end

-- ── Leaderboard tower ─────────────────────────────────────────────────────
local LX, LZ = 95, -10
mk("Base", FL, V(38, 4, 78), P(LX, 2, LZ), C.darker, SMOOTH, { collide = true, shadow = true })
mk("BaseTrim", FL, V(39.6, 1, 79.6), P(LX, 4.3, LZ), C.gold, NEON)
mk("Column", FL, V(16, 80, 16), P(LX, 44, LZ), C.panel, SMOOTH, { collide = true, shadow = true })

local rng = Random.new(4242)
for i = 0, 13 do
	local y = 8 + i * 5.6
	local ox, oz = rng:NextInteger(-1, 1) * 11, rng:NextInteger(-2, 2) * 11
	if ox ~= 0 or oz ~= 0 then
		mk("Block", FL, V(11, 5.2, 11), P(LX + ox, y, LZ + oz), C.panel, SMOOTH, { collide = true })
		mk("BlockTop", FL, V(11.4, 0.3, 11.4), P(LX + ox, y + 2.7, LZ + oz), C.gold, NEON, { tr = 0.45 })
	end
end
mk("Crown", FL, V(9, 9, 9), P(LX, 88, LZ), C.gold, NEON)
mk("CrownHalo", FL, V(15, 0.6, 15), P(LX, 93, LZ), C.white, NEON, { tr = 0.35 })

-- Placeholder rows. Phase 8's StatsService replaces the tables, not the layout.
-- No emoji in the headers: Gotham renders a lot of them as blank boxes.
local PANELS = {
	{ y = 62, title = "WORLD RANK", accent = C.gold, rows = {
		{ "1", "—", "0" }, { "2", "—", "0" }, { "3", "—", "0" }, { "4", "—", "0" }, { "5", "—", "0" } } },
	{ y = 40, title = "WIN STREAK", accent = C.orange, rows = {
		{ "1", "—", "0" }, { "2", "—", "0" }, { "3", "—", "0" } } },
	{ y = 18, title = "TOP SCORES", accent = C.violet, rows = {
		{ "LINES", "—", "0" }, { "COMBO", "—", "0" }, { "WINS", "—", "0" }, { "FASTEST", "—", "—" } } },
}
local toCore = (Vector3.new(0, 0, 20) - Vector3.new(LX, 0, LZ)).Unit
for _, pn in ipairs(PANELS) do
	local pos = Vector3.new(LX, pn.y, LZ) + toCore * 9
	local part = mk("Panel_" .. pn.title, FL, V(34, 19, 0.5), CFrame.lookAt(pos, pos + toCore),
		C.panel, SMOOTH, { tr = 0.15 })
	local sg = Instance.new("SurfaceGui")
	sg.Face, sg.SizingMode, sg.PixelsPerStud = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 28
	sg.LightInfluence, sg.Brightness = 0, 2
	sg.Parent = part

	local root = Instance.new("Frame")
	root.Size, root.BackgroundColor3, root.BorderSizePixel = UDim2.fromScale(1, 1), C.panel, 0
	root.Parent = sg
	local st = Instance.new("UIStroke"); st.Color, st.Thickness = pn.accent, 5; st.Parent = root

	label(root, UDim2.fromScale(0.04, 0.04), UDim2.fromScale(0.92, 0.17), pn.title,
		Enum.Font.GothamBold, pn.accent, Enum.TextXAlignment.Left)
	local rule = Instance.new("Frame")
	rule.Position, rule.Size = UDim2.fromScale(0.04, 0.235), UDim2.new(0.92, 0, 0, 3)
	rule.BackgroundColor3, rule.BackgroundTransparency, rule.BorderSizePixel = pn.accent, 0.4, 0
	rule.Parent = root

	local n = #pn.rows
	for i, row in ipairs(pn.rows) do
		local y, hgt = 0.29 + (i - 1) * (0.66 / n), (0.66 / n) - 0.02
		label(root, UDim2.fromScale(0.05, y), UDim2.fromScale(0.14, hgt), row[1],
			Enum.Font.GothamBold, pn.accent, Enum.TextXAlignment.Left)
		label(root, UDim2.fromScale(0.21, y), UDim2.fromScale(0.5, hgt), row[2],
			Enum.Font.Gotham, C.white, Enum.TextXAlignment.Left)
		label(root, UDim2.fromScale(0.72, y), UDim2.fromScale(0.23, hgt), row[3],
			Enum.Font.GothamBold, C.muted, Enum.TextXAlignment.Right)
	end
end

local function lamp(pos, colour, range, brightness)
	local n = mk("Lamp", Lobby.Lights, V(0.2, 0.2, 0.2), CFrame.new(pos), C.white, SMOOTH, { tr = 1 })
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
	l.Parent = n
end
for _, s in ipairs(STATIONS) do lamp(V(s.x, 10, MZ), s.c, 46, 2.2) end
lamp(V(LX - 14, 60, LZ + 6), C.gold, 70, 2.2)
lamp(V(LX - 14, 24, LZ + 6), C.violet, 60, 1.8)
lamp(V(LX, 90, LZ), C.gold, 60, 2.6)

return ("matchmaking %d stations, leaderboard %d instances"):format(#STATIONS, #FL:GetDescendants())
