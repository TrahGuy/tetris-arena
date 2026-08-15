-- Block Arena lobby — 02: the Block Battle Portal.
-- The biggest structure in the lobby: a shallow-V cabinet front with a doorway
-- cut through it, the BLOCK ARENA title above, demo boards on the wings, and a
-- block door that LobbyFX dissolves when a player steps on the threshold.

local Lobby = workspace:WaitForChild("Lobby")
local F = Lobby.Portal
F:ClearAllChildren()

local C = {
	cy = Color3.fromRGB(0, 245, 255), mg = Color3.fromRGB(255, 43, 214),
	mid = Color3.fromRGB(150, 60, 255), violet = Color3.fromRGB(176, 130, 255),
	white = Color3.fromRGB(234, 246, 255), panel = Color3.fromRGB(30, 25, 45),
	inset = Color3.fromRGB(24, 19, 38), ground = Color3.fromRGB(18, 15, 28),
	empty = Color3.fromRGB(28, 24, 46), seam = Color3.fromRGB(112, 78, 190),
}
local SMOOTH, NEON, FF = Enum.Material.SmoothPlastic, Enum.Material.Neon, Enum.Material.ForceField

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
local function ramp(t)
	-- Straight cyan->magenta washes out to white under bloom; route it through
	-- a saturated violet waypoint instead.
	if t < 0.5 then return C.cy:Lerp(C.mid, t * 2) end
	return C.mid:Lerp(C.mg, (t - 0.5) * 2)
end

local FZ = -122

-- ── Facade: the opening is x -15..15, y 0..42, so the panel is three slabs ─
mk("SlabL", F, V(40, 84, 3), P(-35, 42, FZ), C.panel, SMOOTH, { collide = true, shadow = true, ref = 0.04 })
mk("SlabR", F, V(40, 84, 3), P(35, 42, FZ), C.panel, SMOOTH, { collide = true, shadow = true, ref = 0.04 })
mk("Lintel", F, V(30, 42, 3), P(0, 63, FZ), C.panel, SMOOTH, { collide = true, shadow = true, ref = 0.04 })
mk("Inset", F, V(104, 34, 0.3), P(0, 60, FZ + 1.65), C.inset, SMOOTH)

mk("JambL", F, V(1.6, 44, 1.6), P(-15.8, 21, FZ + 1.8), C.cy, NEON)
mk("JambR", F, V(1.6, 44, 1.6), P(15.8, 21, FZ + 1.8), C.mg, NEON)
mk("Head", F, V(16.8, 1.6, 1.6), P(-7.6, 42.8, FZ + 1.8), C.cy, NEON)
mk("Head", F, V(16.8, 1.6, 1.6), P(7.6, 42.8, FZ + 1.8), C.mg, NEON)

-- Course lines, so the facade reads as something built out of blocks rather
-- than as a black rectangle. Without these the doorway does not read as a hole.
for _, s in ipairs({ -1, 1 }) do
	for _, y in ipairs({ 12, 26, 40, 54, 68 }) do
		mk("Course", F, V(40, 0.35, 0.4), P(35 * s, y, FZ + 1.7), C.seam, NEON, { tr = 0.55 })
	end
	for _, dx in ipairs({ 15, 25, 35, 45 }) do
		mk("Course", F, V(0.35, 84, 0.4), P(dx * s, 42, FZ + 1.7), C.seam, NEON, { tr = 0.72 })
	end
end

-- ── Wings ─────────────────────────────────────────────────────────────────
local COS, SIN = math.cos(math.rad(25)), math.sin(math.rad(25))
local wings = {}
for _, s in ipairs({ -1, 1 }) do
	local hinge = V(55 * s, 42, FZ)
	local dir = V(COS * s, 0, SIN)     -- outward along the wing, swinging forward
	local normal = V(-SIN * s, 0, COS) -- perpendicular, facing into the lobby
	local pos = hinge + dir * 20
	local cf = CFrame.lookAt(pos, pos + normal)
	local panel = mk(s < 0 and "WingL" or "WingR", F, V(40, 84, 3), cf, C.panel, SMOOTH,
		{ collide = true, shadow = true, ref = 0.04 })
	wings[s] = panel
	-- RightVector points outward on one wing and inward on the other.
	local outer = (panel.CFrame.RightVector:Dot(dir) > 0) and 20.6 or -20.6
	local accent = s < 0 and C.cy or C.mg
	mk("WingTrim", F, V(40, 1.2, 1.2), cf * CFrame.new(0, 42.5, -1.9), accent, NEON)
	mk("WingEdge", F, V(1.2, 84, 1.2), cf * CFrame.new(outer, 0, -1.9), accent, NEON)
	mk("WingFoot", F, V(40, 1, 1), cf * CFrame.new(0, -41.5, -1.9), C.violet, NEON)
	mk("Seam", F, V(1, 84, 1), P(55 * s, 42, FZ + 1.9), C.violet, NEON)
	mk("TrimTop", F, V(55, 1.2, 1.2), P(27.5 * s, 84.6, FZ + 1.6), accent, NEON)
	mk("TrimFoot", F, V(40, 1, 1), P(35 * s, 0.5, FZ + 1.9), accent, NEON)
end

-- ── Title: 5x7 block font, runs of filled cells merged into single parts ──
local GLYPH = {
	B = { "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####." },
	L = { "#....", "#....", "#....", "#....", "#....", "#....", "#####" },
	O = { ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
	C = { ".####", "#....", "#....", "#....", "#....", "#....", ".####" },
	K = { "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#" },
	A = { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
	R = { "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" },
	E = { "#####", "#....", "#....", "####.", "#....", "#....", "#####" },
	N = { "#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#" },
}
local CELL, GAP, DEPTH, TZ = 2.0, 0.2, 2.2, FZ + 2.7
local ADV = 5 * CELL + 2.2
-- One solid colour per letter — a per-cell ramp speckles the middle glyphs.
local function drawWord(word, centreY)
	local total = #word * ADV - 2.2
	for i = 1, #word do
		local rows = GLYPH[word:sub(i, i)]
		local lx = -total / 2 + (i - 1) * ADV
		local colour = ramp((i - 1) / (#word - 1))
		for r = 1, 7 do
			local row, c = rows[r], 1
			while c <= 5 do
				if row:sub(c, c) == "#" then
					local run = c
					while run < 5 and row:sub(run + 1, run + 1) == "#" do run += 1 end
					local w = run - c + 1
					mk("Cell", F, V(w * CELL - GAP, CELL - GAP, DEPTH),
						P(lx + (c - 1 + w / 2) * CELL, centreY + (4 - r) * CELL, TZ), colour, NEON)
					c = run + 1
				else
					c += 1
				end
			end
		end
	end
end
drawWord("BLOCK", 67.5)
drawWord("ARENA", 50.3)

local band = mk("HeaderBand", F, V(104, 7, 0.3), P(0, 80, FZ + 1.7), C.panel, SMOOTH, { tr = 1 })
local bg = Instance.new("SurfaceGui")
bg.Face, bg.SizingMode, bg.PixelsPerStud = Enum.NormalId.Back, Enum.SurfaceGuiSizingMode.PixelsPerStud, 28
bg.LightInfluence, bg.Brightness = 0, 2
bg.Parent = band
local bl = Instance.new("TextLabel")
bl.BackgroundTransparency, bl.Size = 1, UDim2.fromScale(1, 1)
bl.Font, bl.Text, bl.TextColor3 = Enum.Font.GothamBold, "B L O C K   B A T T L E   P O R T A L", C.violet
bl.TextScaled = true
bl.Parent = bg

-- ── The door: a 6x8 lattice LobbyFX scatters upward on approach ───────────
local door = Instance.new("Folder"); door.Name = "Door"; door.Parent = F
local BW, BH = 5, 5.25
for col = 0, 5 do
	for row = 0, 7 do
		local x, y = -15 + BW / 2 + col * BW, BH / 2 + row * BH
		local colour = ramp(col / 5)
		mk("Block", door, V(BW - 0.35, BH - 0.35, 2.4), P(x, y, FZ),
			colour:Lerp(Color3.new(0, 0, 0), 0.62), SMOOTH, { collide = true })
			:SetAttribute("Home", CFrame.new(x, y, FZ))
		mk("Core", door, V(BW - 2.4, BH - 2.6, 2.7), P(x, y, FZ), colour, NEON)
			:SetAttribute("Home", CFrame.new(x, y, FZ))
	end
end
mk("PortalPlane", F, V(30, 42, 0.6), P(0, 21, FZ - 1.6), C.violet, FF, { tr = 0.4 })
mk("PortalGlow", F, V(30, 42, 0.3), P(0, 21, FZ - 2.2), C.mid, NEON, { tr = 0.55 })
mk("Threshold", F, V(34, 0.3, 22), P(0, 0.2, FZ + 13), C.violet, NEON, { tr = 0.55 })
	:SetAttribute("Radius", 22)

-- ── Demo boards on the wings ─────────────────────────────────────────────
local PAL = {
	Color3.fromRGB(34, 228, 245), Color3.fromRGB(255, 216, 77), Color3.fromRGB(194, 77, 255),
	Color3.fromRGB(61, 232, 107), Color3.fromRGB(255, 61, 94), Color3.fromRGB(77, 130, 255),
	Color3.fromRGB(255, 154, 43), Color3.fromRGB(110, 103, 144), -- 8 = garbage
}
-- Fill each column from the bottom so nothing floats, and colour in 2x2 clumps
-- so it reads as locked pieces rather than noise.
local function stack(heights, holes, garbage)
	local g = {}
	for r = 1, 20 do
		g[r] = {}
		for c = 1, 10 do g[r][c] = false end
	end
	for c = 1, 10 do
		for k = 0, heights[c] - 1 do
			local r = 20 - k
			if r >= 1 then g[r][c] = (math.floor((c - 1) / 2) + math.floor(k / 2) * 3) % 7 + 1 end
		end
	end
	for _, h in ipairs(holes) do g[20 - h[2]][h[1]] = false end
	for _, gr in ipairs(garbage) do
		for c = 1, 10 do g[gr[1]][c] = (c ~= gr[2]) and 8 or false end
	end
	return g
end
local function fr(parent, name, pos, size, colour)
	local f = Instance.new("Frame")
	f.Name, f.Position, f.Size, f.BackgroundColor3 = name, pos, size, colour
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end
local function stroke(parent, colour, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.Transparency = colour, thickness, transparency or 0
	s.Parent = parent
end
local function buildBoard(panel, accent, title, grid, incoming)
	local p = mk("Board_" .. title, F, V(30, 62, 0.4), panel.CFrame * CFrame.new(0, 2, -1.9),
		C.ground, SMOOTH, { tr = 1 })
	local sg = Instance.new("SurfaceGui")
	sg.Face, sg.SizingMode, sg.PixelsPerStud = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 24
	sg.LightInfluence, sg.Brightness = 0, 2
	sg.Parent = p
	local root = fr(sg, "Root", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), C.ground)
	stroke(root, accent, 6, 0.15)
	local head = Instance.new("TextLabel")
	head.Name, head.BackgroundTransparency = "Header", 1
	head.Position, head.Size = UDim2.fromOffset(64, 28), UDim2.fromOffset(592, 100)
	head.Font, head.Text, head.TextColor3 = Enum.Font.GothamBold, title, accent
	head.TextScaled, head.TextXAlignment = true, Enum.TextXAlignment.Left
	head.Parent = root
	local meter = fr(root, "Meter", UDim2.fromOffset(28, 160), UDim2.fromOffset(24, 1240),
		Color3.fromRGB(26, 20, 40))
	if incoming > 0 then
		fr(meter, "Fill", UDim2.new(0, 0, 1 - incoming, 0), UDim2.fromScale(1, incoming),
			Color3.fromRGB(255, 46, 92)).ZIndex = 2
	end
	local well = fr(root, "Grid", UDim2.fromOffset(64, 160), UDim2.fromOffset(620, 1240), C.ground)
	stroke(well, accent, 4, 0.35)
	for r = 1, 20 do
		for c = 1, 10 do
			local key = grid[r][c]
			local cell = fr(well, "C", UDim2.new((c - 1) * 0.1, 2, (r - 1) * 0.05, 2),
				UDim2.new(0.1, -4, 0.05, -4), C.empty)
			if key then
				local col = PAL[key]
				cell.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.5)
				fr(cell, "Core", UDim2.fromScale(0.17, 0.17), UDim2.fromScale(0.66, 0.66), col).ZIndex = 2
			end
		end
	end
end
-- P1 stacking cleanly with a well open; P2 buried and taking garbage. The two
-- boards say what the game is before anyone presses anything.
buildBoard(wings[-1], C.cy, "PLAYER 1", stack({ 7, 8, 9, 8, 7, 8, 9, 8, 4, 0 }, { { 3, 2 }, { 7, 4 } }, {}), 0)
buildBoard(wings[1], C.mg, "PLAYER 2",
	stack({ 12, 13, 14, 13, 12, 13, 14, 13, 12, 11 }, { { 5, 3 } }, { { 19, 7 }, { 20, 3 } }), 0.45)

local function lamp(pos, colour, range, brightness)
	local n = mk("Lamp", Lobby.Lights, V(0.2, 0.2, 0.2), CFrame.new(pos), C.white, SMOOTH, { tr = 1 })
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
	l.Parent = n
end
lamp(V(-34, 60, FZ + 14), C.cy, 90, 2.6)
lamp(V(34, 60, FZ + 14), C.mg, 90, 2.6)
lamp(V(0, 18, FZ + 8), C.violet, 60, 2.4)
lamp(V(-34, 20, FZ + 14), C.cy, 64, 1.6)
lamp(V(34, 20, FZ + 14), C.mg, 64, 1.6)
for _, s in ipairs({ -1, 1 }) do
	lamp((wings[s].CFrame * CFrame.new(0, 4, -16)).Position, s < 0 and C.cy or C.mg, 70, 2.2)
end

return ("portal — %d instances, door %d blocks"):format(#F:GetDescendants(), #door:GetChildren())
