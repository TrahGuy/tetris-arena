-- Block Arena lobby — 04: museum, training zone, social lounge, secret nook.
--
-- All four are physically complete and none of them are wired: the museum
-- exhibits are display-only until skins exist, the training board is an
-- animation until the real sim lands in Phase 3, and the secret puzzle has
-- geometry plus attributes but no solve logic yet.

local Lobby = workspace:WaitForChild("Lobby")
local FU, FT, FS, FE = Lobby.Museum, Lobby.Training, Lobby.Social, Lobby.Secret
for _, f in ipairs({ FU, FT, FS }) do
	for _, c in ipairs(f:GetChildren()) do
		if c.Name ~= "Glow" and c.Name ~= "Glass" and c.Name ~= "Edge" then c:Destroy() end
	end
end
FE:ClearAllChildren()

local C = {
	purple = Color3.fromRGB(139, 43, 255), gold = Color3.fromRGB(255, 205, 74),
	cy = Color3.fromRGB(0, 245, 255), mg = Color3.fromRGB(255, 43, 214),
	white = Color3.fromRGB(234, 246, 255), violet = Color3.fromRGB(176, 130, 255),
	muted = Color3.fromRGB(150, 142, 178), dark = Color3.fromRGB(11, 7, 20),
	darker = Color3.fromRGB(7, 4, 13), panel = Color3.fromRGB(14, 9, 25),
	ground = Color3.fromRGB(13, 9, 24), empty = Color3.fromRGB(28, 24, 46),
	galaxy = Color3.fromRGB(74, 24, 140), secret = Color3.fromRGB(18, 14, 30),
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
	if o.shape then p.Shape = o.shape end
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
local function surface(part, face, pps)
	local sg = Instance.new("SurfaceGui")
	sg.Face, sg.SizingMode, sg.PixelsPerStud = face, Enum.SurfaceGuiSizingMode.PixelsPerStud, pps
	sg.LightInfluence, sg.Brightness = 0, 2
	sg.Parent = part
	return sg
end
local function lamp(pos, colour, range, brightness)
	local n = mk("Lamp", Lobby.Lights, V(0.2, 0.2, 0.2), CFrame.new(pos), C.white, SMOOTH, { tr = 1 })
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
	l.Parent = n
end

-- ══ BLOCK MUSEUM ═════════════════════════════════════════════════════════
for _, z in ipairs({ -40, 0 }) do
	mk("ArchPost", FU, V(3, 26, 3), P(-70, 14, z), C.panel, SMOOTH, { collide = true })
	mk("ArchPostTrim", FU, V(3.6, 1, 3.6), P(-70, 27, z), C.purple, NEON)
end
mk("ArchBeam", FU, V(3, 4, 43), P(-70, 28.5, -20), C.panel, SMOOTH)
local arch = mk("ArchSign", FU, V(0.4, 5, 40), CFrame.lookAt(V(-69.5, 28.5, -20), V(0, 28.5, -20)),
	C.panel, SMOOTH, { tr = 1 })
label(surface(arch, Enum.NormalId.Front, 30), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
	"B L O C K   M U S E U M", Enum.Font.GothamBold, C.purple)

local EXHIBITS = {
	{ name = "GOLDEN T", rarity = "LEGENDARY", z = -36, col = C.gold, ref = 0.35, mat = NEON,
		cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } } },
	{ name = "DIAMOND I", rarity = "MYTHIC", z = -20, col = Color3.fromRGB(198, 240, 255), ref = 0.6, mat = GLASS,
		cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } } },
	{ name = "GALAXY CUBE", rarity = "SECRET", z = -4, col = C.galaxy, ref = 0.2, mat = FF, cells = false },
}
for _, ex in ipairs(EXHIBITS) do
	local px = -95
	mk("Pedestal", FU, V(10, 6, 10), P(px, 4, ex.z), C.darker, SMOOTH, { collide = true, shadow = true })
	mk("PedestalTop", FU, V(11, 0.5, 11), P(px, 7.2, ex.z), ex.col, NEON)
	mk("Dome", FU, V(13, 13, 13), P(px, 13, ex.z), C.white, GLASS,
		{ tr = 0.82, ref = 0.3, shape = Enum.PartType.Ball })

	local model = Instance.new("Model"); model.Name = "Exhibit_" .. ex.name; model.Parent = FU
	local origin = Vector3.new(px, 13, ex.z)
	model.PrimaryPart = mk("Root", model, V(0.4, 0.4, 0.4), CFrame.new(origin), C.white, SMOOTH, { tr = 1 })
	if ex.cells then
		local mx, mz = 0, 0
		for _, c in ipairs(ex.cells) do mx += c[1]; mz += c[2] end
		mx, mz = mx / 4, mz / 4
		for _, c in ipairs(ex.cells) do
			local off = Vector3.new((c[1] - mx) * 2.6, 0, (c[2] - mz) * 2.6)
			mk("Cell", model, V(2.6, 2.6, 2.6), CFrame.new(origin + off), ex.col, ex.mat, { ref = ex.ref })
		end
	else
		mk("Shell", model, V(6.5, 6.5, 6.5), CFrame.new(origin), ex.col, FF, { tr = 0.35 })
		mk("Heart", model, V(3.4, 3.4, 3.4), CFrame.new(origin), C.mg, NEON)
		local rng = Random.new(9001)
		for _ = 1, 10 do
			local o = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3))
			mk("Star", model, V(0.45, 0.45, 0.45), CFrame.new(origin + o), C.white, NEON)
		end
	end
	model.WorldPivot = CFrame.new(origin)
	model:SetAttribute("SpinSpeed", 0.5)

	local plaque = mk("Plaque", FU, V(9, 3.4, 0.3),
		CFrame.lookAt(V(px + 5.2, 5.4, ex.z), V(px + 40, 4.2, ex.z)), C.panel, SMOOTH)
	local sg = surface(plaque, Enum.NormalId.Front, 40)
	label(sg, UDim2.fromScale(0, 0.02), UDim2.fromScale(1, 0.58), ex.name, Enum.Font.GothamBold, ex.col)
	label(sg, UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.34), ex.rarity, Enum.Font.Gotham, C.muted)
	lamp(V(px, 15, ex.z), ex.col, 34, 2.4)
end
lamp(V(-82, 24, -20), C.purple, 60, 1.6)

-- ══ TRAINING ZONE ════════════════════════════════════════════════════════
local TX, TZ = -75, 95
mk("ScreenBack", FT, V(38, 48, 2), P(TX, 25, TZ + 33), C.panel, SMOOTH, { collide = true, shadow = true })
mk("ScreenTrim", FT, V(39.6, 1.2, 1.2), P(TX, 49.4, TZ + 33), C.cy, NEON)
for _, s in ipairs({ -1, 1 }) do
	mk("ScreenPost", FT, V(1.2, 48, 1.2), P(TX + s * 19.4, 25, TZ + 33), C.cy, NEON)
end
local board = mk("MiniBoard", FT, V(20, 40, 0.4), P(TX, 26, TZ + 31.8), C.ground, SMOOTH, { tr = 1 })
local bsg = surface(board, Enum.NormalId.Front, 30)
local root = Instance.new("Frame")
root.Size, root.BackgroundColor3, root.BorderSizePixel = UDim2.fromScale(1, 1), C.ground, 0
root.Parent = bsg
local bstroke = Instance.new("UIStroke"); bstroke.Color, bstroke.Thickness = C.cy, 6; bstroke.Parent = root
label(root, UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.07), "TRAINING BOARD",
	Enum.Font.GothamBold, C.cy, Enum.TextXAlignment.Left)
local well = Instance.new("Frame")
well.Name, well.Position, well.Size = "Grid", UDim2.fromScale(0.08, 0.11), UDim2.fromScale(0.84, 0.84)
well.BackgroundColor3, well.BorderSizePixel = C.ground, 0
well.Parent = root
-- Cells are named so LobbyFX can walk a piece down the board.
for r = 1, 20 do
	for c = 1, 10 do
		local cell = Instance.new("Frame")
		cell.Name = ("C_%d_%d"):format(r, c)
		cell.Position = UDim2.new((c - 1) * 0.1, 2, (r - 1) * 0.05, 2)
		cell.Size = UDim2.new(0.1, -4, 0.05, -4)
		cell.BackgroundColor3, cell.BorderSizePixel = C.empty, 0
		cell.Parent = well
	end
end

local sign = mk("Sign", FT, V(34, 6, 0.4), P(TX, 54, TZ + 32), C.panel, SMOOTH, { tr = 1 })
label(surface(sign, Enum.NormalId.Front, 32), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
	"LEARN BEFORE YOU BATTLE", Enum.Font.GothamBold, C.cy)

local pad = mk("Pad_practice", FT, V(20, 1.6, 20), P(TX, 1.8, TZ - 22),
	C.cy:Lerp(Color3.new(0, 0, 0), 0.72), SMOOTH, { collide = true })
pad:SetAttribute("PadMode", "practice")
pad:SetAttribute("Accent", C.cy)
mk("PadFace", FT, V(17.8, 0.18, 17.8), P(TX, 2.7, TZ - 22), C.cy, NEON, { tr = 0.35 })
for _, q in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
	mk("Post", FT, V(1.3, 9, 1.3), P(TX + q[1] * 10, 5.5, TZ - 22 + q[2] * 10), C.cy, NEON)
end
mk("Ring_practice", FT, V(23, 0.5, 23), P(TX, 11.5, TZ - 22), C.cy, NEON, { tr = 0.3 })
	:SetAttribute("SpinSeed", 7)
local psign = mk("Sign_practice", FT, V(24, 8, 0.5), P(TX, 18, TZ - 22), C.cy, FF, { tr = 0.55 })
local psg = surface(psign, Enum.NormalId.Front, 32)
label(psg, UDim2.fromScale(0, 0.05), UDim2.fromScale(1, 0.55), "PRACTICE", Enum.Font.GothamBold, C.cy)
label(psg, UDim2.fromScale(0, 0.62), UDim2.fromScale(1, 0.3), "SOLO / NO STAKES", Enum.Font.Gotham, C.muted)

-- BLOCK BOT: the tutorial NPC. Head is a T piece LobbyFX spins.
local bot = Instance.new("Model"); bot.Name = "BlockBot"; bot.Parent = FT
local BX, BZ = TX + 26, TZ + 4
local body = mk("Body", bot, V(6, 8, 4.5), P(BX, 7, BZ), C.panel, SMOOTH, { collide = true, shadow = true })
bot.PrimaryPart = body
for _, s in ipairs({ -1, 1 }) do
	mk("Eye", bot, V(1.2, 1.2, 0.4), P(BX + s * 1.4, 9, BZ - 2.4), C.cy, NEON)
	mk("Arm", bot, V(1.8, 4, 1.8), P(BX + s * 4.6, 7, BZ), C.cy:Lerp(Color3.new(0, 0, 0), 0.6), SMOOTH)
	mk("Foot", bot, V(2.2, 2, 3), P(BX + s * 1.8, 1.8, BZ), C.cy:Lerp(Color3.new(0, 0, 0), 0.7), SMOOTH)
end
mk("Belt", bot, V(6.4, 0.5, 4.9), P(BX, 4.6, BZ), C.cy, NEON)

local head = Instance.new("Model"); head.Name = "BotHead"; head.Parent = bot
local hOrigin = Vector3.new(BX, 14.5, BZ)
head.PrimaryPart = mk("Root", head, V(0.4, 0.4, 0.4), CFrame.new(hOrigin), C.white, SMOOTH, { tr = 1 })
for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } }) do
	local off = Vector3.new((c[1] - 1) * 2.2, 0, (c[2] - 0.25) * 2.2)
	mk("Cell", head, V(2.2, 2.2, 2.2), CFrame.new(hOrigin + off), C.cy, NEON)
end
head.WorldPivot = CFrame.new(hOrigin)
head:SetAttribute("SpinSpeed", 1.1)

local tag = Instance.new("BillboardGui")
tag.Name, tag.Size, tag.StudsOffset = "Tag", UDim2.fromScale(9, 2.2), Vector3.new(0, 6, 0)
tag.AlwaysOnTop, tag.MaxDistance, tag.Adornee = false, 220, body
tag.Parent = body
label(tag, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "TRAINER", Enum.Font.GothamBold, C.cy)

lamp(V(TX, 26, TZ + 26), C.cy, 70, 2.4)
lamp(V(TX, 10, TZ - 22), C.cy, 44, 2.0)
lamp(V(BX, 14, BZ - 4), C.cy, 30, 1.8)

-- ══ BLOCK LOUNGE ═════════════════════════════════════════════════════════
local SX, SZ = 75, 95
mk("Table", FS, V(15, 2.4, 15), P(SX, 2.2, SZ), C.darker, SMOOTH, { collide = true, shadow = true })
mk("TableTop", FS, V(16, 0.4, 16), P(SX, 3.6, SZ), C.mg, NEON, { tr = 0.3 })
mk("TableStem", FS, V(4, 8, 4), P(SX, 7.4, SZ), C.panel, SMOOTH)
mk("TableOrb", FS, V(5, 5, 5), P(SX, 13.5, SZ), C.mg, NEON, { tr = 0.25 })

-- Six block chairs, each with a real Seat so players can actually sit.
for i = 0, 5 do
	local a = math.rad(i * 60 + 15)
	local facing = CFrame.lookAt(V(SX + math.sin(a) * 15, 3.2, SZ + math.cos(a) * 15), V(SX, 3.2, SZ))
	local seat = Instance.new("Seat")
	seat.Name, seat.Size, seat.CFrame = "Chair", V(5, 1.6, 5), facing
	seat.Anchored, seat.CanCollide = true, true
	seat.Color, seat.Material = C.mg:Lerp(Color3.new(0, 0, 0), 0.66), SMOOTH
	seat.TopSurface, seat.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	seat.Parent = FS
	mk("ChairBack", FS, V(5, 5.5, 1.5), facing * CFrame.new(0, 2.8, 2.2),
		C.mg:Lerp(Color3.new(0, 0, 0), 0.66), SMOOTH, { collide = true })
	mk("ChairGlow", FS, V(5.2, 0.3, 1.7), facing * CFrame.new(0, 5.4, 2.2), C.mg, NEON)
	mk("ChairLeg", FS, V(4, 2.4, 4), facing * CFrame.new(0, -1.9, 0), C.darker, SMOOTH, { collide = true })
end

local SCREENS = {
	{ dx = -22, title = "TOP PLAYS", body = "—", accent = C.mg },
	{ dx = 0, title = "BLOCK ARENA", body = "1V1 BATTLE", accent = C.violet },
	{ dx = 22, title = "IN QUEUE", body = "0", accent = C.cy },
}
for _, s in ipairs(SCREENS) do
	local pos = V(SX + s.dx, 17, SZ + 26)
	mk("ScreenFrame", FS, V(20, 12, 0.6), CFrame.new(pos), s.accent, FF, { tr = 0.62 })
	mk("ScreenPost", FS, V(1, 15, 1), P(pos.X, 8.5, pos.Z), s.accent, NEON)
	local panel = mk("Screen_" .. s.title, FS, V(19, 11, 0.3), P(pos.X, pos.Y, pos.Z - 0.5),
		C.panel, SMOOTH, { tr = 0.1 })
	local sg = surface(panel, Enum.NormalId.Front, 32)
	label(sg, UDim2.fromScale(0, 0.08), UDim2.fromScale(1, 0.34), s.title, Enum.Font.GothamBold, s.accent)
	label(sg, UDim2.fromScale(0, 0.46), UDim2.fromScale(1, 0.42), s.body, Enum.Font.Gotham, C.white)
end

local ep = mk("Pad_emote", FS, V(18, 1.6, 18), P(SX, 1.8, SZ - 22),
	C.mg:Lerp(Color3.new(0, 0, 0), 0.72), SMOOTH, { collide = true })
ep:SetAttribute("PadMode", "emote")
ep:SetAttribute("Accent", C.mg)
mk("PadFace", FS, V(15.8, 0.18, 15.8), P(SX, 2.7, SZ - 22), C.mg, NEON, { tr = 0.35 })
mk("Ring_emote", FS, V(21, 0.5, 21), P(SX, 9.5, SZ - 22), C.mg, NEON, { tr = 0.3 })
	:SetAttribute("SpinSeed", 3)
local esign = mk("Sign_emote", FS, V(22, 7, 0.5), P(SX, 15, SZ - 22), C.mg, FF, { tr = 0.55 })
local esg = surface(esign, Enum.NormalId.Front, 32)
label(esg, UDim2.fromScale(0, 0.05), UDim2.fromScale(1, 0.55), "EMOTE ZONE", Enum.Font.GothamBold, C.mg)
label(esg, UDim2.fromScale(0, 0.62), UDim2.fromScale(1, 0.3), "DANCE / IDLE REWARDS", Enum.Font.Gotham, C.muted)

for _, s in ipairs({ -1, 1 }) do
	mk("PhotoPost", FS, V(1.6, 20, 1.6), P(SX + 24, 10, SZ + s * 9), C.violet, NEON)
end
mk("PhotoBeam", FS, V(1.6, 1.6, 19.6), P(SX + 24, 20.8, SZ), C.violet, NEON)
mk("Backdrop", FS, V(1, 20, 18), P(SX + 26.5, 10, SZ), C.panel, SMOOTH, { collide = true })
local ps = mk("PhotoSign", FS, V(0.3, 4, 18), CFrame.lookAt(V(SX + 23.2, 18, SZ), V(0, 18, SZ)),
	C.panel, SMOOTH, { tr = 1 })
label(surface(ps, Enum.NormalId.Front, 34), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
	"PHOTO SPOT", Enum.Font.GothamBold, C.violet)

local rng = Random.new(777)
for i = 1, 9 do
	local a = math.rad(i * 40)
	mk("Lantern", FS, V(1.8, 1.8, 1.8),
		P(SX + math.sin(a) * rng:NextNumber(10, 26), rng:NextNumber(10, 22), SZ + math.cos(a) * rng:NextNumber(10, 26)),
		i % 2 == 0 and C.mg or C.violet, NEON, { tr = 0.25 })
end
lamp(V(SX, 14, SZ), C.mg, 60, 2.2)
lamp(V(SX, 16, SZ + 22), C.violet, 46, 1.6)
lamp(V(SX + 22, 14, SZ), C.violet, 40, 1.8)

-- ══ SECRET: an unfinished board in the far corner, no signage ═════════════
local EX, EZ = 130, -132
mk("NookL", FE, V(2, 22, 30), P(EX - 15, 11, EZ), C.secret, SMOOTH, { collide = true })
mk("NookB", FE, V(32, 22, 2), P(EX, 11, EZ - 15), C.secret, SMOOTH, { collide = true })
mk("NookFloor", FE, V(30, 0.3, 28), P(EX, 0.2, EZ), C.secret, SMOOTH)

local MISSING = { [13] = true, [14] = true, [15] = true, [19] = true } -- a T-shaped gap
local grid = Instance.new("Folder"); grid.Name = "Board"; grid.Parent = FE
for r = 1, 5 do
	for c = 1, 5 do
		local idx = (r - 1) * 5 + c
		local x, y = EX - 10 + (c - 1) * 5, 20 - (r - 1) * 4.2
		if not MISSING[idx] then
			mk("Filled", grid, V(4.4, 3.8, 1.6), P(x, y, EZ - 13.6), C.panel, SMOOTH)
			mk("FilledEdge", grid, V(4.6, 0.25, 1.8), P(x, y + 1.9, EZ - 13.6), C.violet, NEON, { tr = 0.5 })
		else
			mk("Slot", grid, V(4.4, 3.8, 0.4), P(x, y, EZ - 14.2), C.violet, NEON, { tr = 0.85 })
				:SetAttribute("SlotIndex", idx)
		end
	end
end
grid:SetAttribute("Puzzle", "T")
grid:SetAttribute("Solved", false)

local rng2 = Random.new(31337)
for i = 1, 4 do
	mk("LoosePiece", FE, V(4, 3.6, 1.6),
		CFrame.new(EX + rng2:NextNumber(-8, 10), 1.9, EZ + rng2:NextNumber(-8, 10))
			* CFrame.Angles(0, rng2:NextNumber(0, 6), 0),
		C.violet:Lerp(Color3.new(0, 0, 0), 0.5), SMOOTH, { collide = true })
		:SetAttribute("PieceIndex", i)
end
lamp(V(EX, 14, EZ - 10), C.violet, 26, 0.9) -- deliberately faint; it should be found, not signposted

return ("museum %d, training %d, social %d, secret %d")
	:format(#FU:GetDescendants(), #FT:GetDescendants(), #FS:GetDescendants(), #FE:GetDescendants())
