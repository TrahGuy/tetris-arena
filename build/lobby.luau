-- Block Arena — Phase 1 lobby world builder.
--
-- Idempotent: destroys and rebuilds workspace.Arena from scratch. Run in Edit
-- mode from the command bar or MCP execute_luau. This file is the source of
-- truth for the lobby geometry — the .rbxl is just its output.
--
-- Convention: the deck top sits at y = 0. Cyan owns -X and magenta owns +X;
-- that split is the 1v1 read and it runs through the floor grid, the rim, the
-- pylons, the overhead frame and the marquee.

local C = {
	cy = Color3.fromRGB(0, 245, 255),
	mg = Color3.fromRGB(255, 43, 214),
	mid = Color3.fromRGB(150, 60, 255), -- saturated waypoint; a straight cyan->magenta
	                                    -- lerp washes out to white under bloom
	cyDim = Color3.fromRGB(0, 78, 86),
	mgDim = Color3.fromRGB(88, 15, 74),
	dark = Color3.fromRGB(11, 7, 20),
	darker = Color3.fromRGB(7, 4, 13),
	deep = Color3.fromRGB(5, 3, 10),
	panel = Color3.fromRGB(10, 6, 18),
	inset = Color3.fromRGB(17, 11, 30),
	violet = Color3.fromRGB(176, 130, 255),
	pad = Color3.fromRGB(16, 11, 28),
	ground = Color3.fromRGB(13, 9, 24),
	empty = Color3.fromRGB(28, 24, 46),
}
local SMOOTH, NEON = Enum.Material.SmoothPlastic, Enum.Material.Neon

local old = workspace:FindFirstChild("Arena")
if old then old:Destroy() end
local Arena = Instance.new("Folder")
Arena.Name = "Arena"
Arena.Parent = workspace

local F = {}
for _, n in ipairs({ "Island", "Neon", "Barriers", "Spawn", "Marquee", "Title", "Boards", "Lights" }) do
	local f = Instance.new("Folder"); f.Name = n; f.Parent = Arena; F[n] = f
end

-- Decoration is non-colliding and shadowless by default; structure opts in.
local function mk(name, parent, size, cf, colour, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cf, colour, mat
	p.Anchored = true
	p.CanCollide = o.collide == true
	p.CastShadow = o.shadow == true
	p.Transparency = o.tr or 0
	p.Reflectance = o.ref or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function V(x, y, z) return Vector3.new(x, y, z) end
local function P(x, y, z) return CFrame.new(x, y, z) end
local function ramp(t)
	if t < 0.5 then return C.cy:Lerp(C.mid, t * 2) end
	return C.mid:Lerp(C.mg, (t - 0.5) * 2)
end

-- ── Island ────────────────────────────────────────────────────────────────
mk("Deck", F.Island, V(110, 4, 76), P(0, -2, 0), C.dark, SMOOTH, { collide = true, shadow = true, ref = 0.12 })
mk("Tier2", F.Island, V(98, 18, 64), P(0, -13, 0), C.darker, SMOOTH, { collide = true })
mk("Tier3", F.Island, V(74, 22, 46), P(0, -33, 0), C.deep, SMOOTH, { collide = true })

mk("RimL", F.Neon, V(1.2, 1.0, 76), P(-54.4, -0.4, 0), C.cy, NEON)
mk("RimR", F.Neon, V(1.2, 1.0, 76), P(54.4, -0.4, 0), C.mg, NEON)
for _, z in ipairs({ -37.4, 37.4 }) do
	mk("RimZ", F.Neon, V(54.4, 1.0, 1.2), P(-27.2, -0.4, z), C.cy, NEON)
	mk("RimZ", F.Neon, V(54.4, 1.0, 1.2), P(27.2, -0.4, z), C.mg, NEON)
end

for _, x in ipairs({ -50, -40, -30, -20, -10, 10, 20, 30, 40, 50 }) do
	mk("GridZ", F.Neon, V(0.3, 0.06, 76), P(x, 0.03, 0), x < 0 and C.cyDim or C.mgDim, NEON)
end
for _, z in ipairs({ -30, -20, -10, 0, 10, 20, 30 }) do
	mk("GridX", F.Neon, V(55, 0.06, 0.3), P(-27.5, 0.03, z), C.cyDim, NEON)
	mk("GridX", F.Neon, V(55, 0.06, 0.3), P(27.5, 0.03, z), C.mgDim, NEON)
end
mk("Seam", F.Neon, V(0.7, 0.08, 76), P(0, 0.04, 0), C.violet, NEON)

-- Invisible, so the deck still reads as an island floating in the void.
mk("BarrierL", F.Barriers, V(2, 44, 80), P(-56, 22, 0), C.dark, SMOOTH, { collide = true, tr = 1 })
mk("BarrierR", F.Barriers, V(2, 44, 80), P(56, 22, 0), C.dark, SMOOTH, { collide = true, tr = 1 })
mk("BarrierB", F.Barriers, V(116, 44, 2), P(0, 22, -39), C.dark, SMOOTH, { collide = true, tr = 1 })
mk("BarrierF", F.Barriers, V(116, 44, 2), P(0, 22, 39), C.dark, SMOOTH, { collide = true, tr = 1 })

for _, s in ipairs({ { -52, 34 }, { 52, 34 }, { -52, 2 }, { 52, 2 } }) do
	local col = s[1] < 0 and C.cy or C.mg
	mk("PylonBase", F.Island, V(3, 1.4, 3), P(s[1], 0.7, s[2]), C.darker, SMOOTH, { collide = true, shadow = true })
	mk("Pylon", F.Neon, V(1.3, 30, 1.3), P(s[1], 16.4, s[2]), col, NEON)
	mk("PylonCap", F.Neon, V(2.4, 0.5, 2.4), P(s[1], 31.6, s[2]), C.violet, NEON)
end

-- Overhead frame sits at y=40 with its rear bar pulled to z=-14; any lower or
-- further back and it cuts across the title from eye level.
for _, z in ipairs({ -14, 24 }) do
	mk("FrameX", F.Neon, V(46, 0.9, 0.9), P(-23, 40, z), C.cy, NEON)
	mk("FrameX", F.Neon, V(46, 0.9, 0.9), P(23, 40, z), C.mg, NEON)
end
mk("FrameZ", F.Neon, V(0.9, 0.9, 38), P(-46, 40, 5), C.cy, NEON)
mk("FrameZ", F.Neon, V(0.9, 0.9, 38), P(46, 40, 5), C.mg, NEON)
-- Front drops only — a rear pair would sit on the sightline to the boards.
mk("Drop", F.Neon, V(0.5, 40, 0.5), P(-46, 20, 24), C.cy, NEON, { tr = 0.25 })
mk("Drop", F.Neon, V(0.5, 40, 0.5), P(46, 20, 24), C.mg, NEON, { tr = 0.25 })

-- ── Spawn ─────────────────────────────────────────────────────────────────
local spawn = Instance.new("SpawnLocation")
spawn.Name = "LobbySpawn"
spawn.Size = V(16, 0.6, 16)
spawn.CFrame = P(0, 0.3, 18) -- default LookVector is -Z, so players face the marquee
spawn.Anchored, spawn.CanCollide, spawn.Neutral = true, true, true
spawn.AllowTeamChangeOnTouch = false
spawn.Duration = 0 -- no forcefield bubble
spawn.Color, spawn.Material = C.pad, SMOOTH
spawn.TopSurface, spawn.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
spawn.Parent = F.Spawn

for _, z in ipairs({ 9.7, 26.3 }) do
	mk("Ring", F.Spawn, V(17.2, 0.16, 0.6), P(0, 0.68, z), C.violet, NEON)
end
for _, x in ipairs({ -8.3, 8.3 }) do
	mk("Ring", F.Spawn, V(0.6, 0.16, 17.2), P(x, 0.68, 18), C.violet, NEON)
end

-- ── Marquee: shallow V hinged at x = +/-34 ────────────────────────────────
mk("PanelC", F.Marquee, V(68, 44, 2.5), P(0, 22, -34), C.panel, SMOOTH, { collide = true, shadow = true })

local COS, SIN = math.cos(math.rad(25)), math.sin(math.rad(25))
local wings = {}
for _, s in ipairs({ -1, 1 }) do
	local hinge = V(34 * s, 22, -34)
	local dir = V(COS * s, 0, SIN)     -- outward along the wing, swinging forward
	local normal = V(-SIN * s, 0, COS) -- perpendicular, facing into the room
	local pos = hinge + dir * 11
	local cf = CFrame.lookAt(pos, pos + normal)
	local panel = mk(s < 0 and "PanelL" or "PanelR", F.Marquee, V(22, 44, 2.5), cf, C.panel, SMOOTH,
		{ collide = true, shadow = true })
	wings[s] = panel
	-- RightVector points outward on one wing and inward on the other.
	local outer = (panel.CFrame.RightVector:Dot(dir) > 0) and 11.4 or -11.4
	local accent = s < 0 and C.cy or C.mg
	mk("WingTrim", F.Marquee, V(22, 0.8, 0.8), cf * CFrame.new(0, 22.4, -1.6), accent, NEON)
	mk("WingEdge", F.Marquee, V(0.8, 44, 0.8), cf * CFrame.new(outer, 0, -1.6), accent, NEON)
	mk("WingFoot", F.Marquee, V(22, 0.7, 0.7), cf * CFrame.new(0, -21.6, -1.6), C.violet, NEON)
	mk("Seam", F.Marquee, V(0.7, 44, 0.7), P(34 * s, 22, -32.4), C.violet, NEON)
	mk("TrimTop", F.Marquee, V(34, 0.8, 0.8), P(17 * s, 44.4, -32.6), accent, NEON)
	mk("TrimFoot", F.Marquee, V(34, 0.7, 0.7), P(17 * s, 0.4, -32.6), accent, NEON)
end
mk("Inset", F.Marquee, V(62, 34, 0.3), P(0, 25.5, -32.6), C.inset, SMOOTH)

-- ── Title: 5x7 block font ─────────────────────────────────────────────────
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
local CELL, GAP, DEPTH, TZ = 2.0, 0.2, 2.0, -31.4
local ADV = 5 * CELL + 2.2

-- One solid colour per letter — a per-cell ramp speckles the middle glyphs.
-- Runs of filled cells in a row collapse into one part (~108 total, not ~340).
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
					mk("Cell", F.Title, V(w * CELL - GAP, CELL - GAP, DEPTH),
						P(lx + (c - 1 + w / 2) * CELL, centreY + (4 - r) * CELL, TZ), colour, NEON)
					c = run + 1
				else
					c += 1
				end
			end
		end
	end
end
drawWord("BLOCK", 33.1)
drawWord("ARENA", 15.9)

-- ── Demo boards ───────────────────────────────────────────────────────────
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

local function frame(parent, name, pos, size, colour)
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
	local p = Instance.new("Part")
	p.Name = "Board_" .. title
	p.Size = V(18, 38, 0.3)
	p.CFrame = panel.CFrame * CFrame.new(0, 1, -1.4)
	p.Anchored, p.CanCollide, p.CastShadow, p.Transparency = true, false, false, 1
	p.Parent = F.Boards

	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front -- the face the wing's CFrame looks along, into the room
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 36
	sg.LightInfluence = 0
	sg.Brightness = 2
	sg.Parent = p

	local root = frame(sg, "Root", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), C.ground)
	stroke(root, accent, 5, 0.15)

	local head = Instance.new("TextLabel")
	head.Name = "Header"
	head.BackgroundTransparency = 1
	head.Position, head.Size = UDim2.fromOffset(52, 20), UDim2.fromOffset(568, 88)
	head.Font, head.Text, head.TextColor3 = Enum.Font.GothamBold, title, accent
	head.TextScaled, head.TextXAlignment = true, Enum.TextXAlignment.Left
	head.Parent = root

	-- Incoming-garbage meter: the mechanic Phase 6 will drive for real.
	local meter = frame(root, "Meter", UDim2.fromOffset(24, 132), UDim2.fromOffset(20, 1136),
		Color3.fromRGB(26, 20, 40))
	if incoming > 0 then
		local fill = frame(meter, "Fill", UDim2.new(0, 0, 1 - incoming, 0), UDim2.fromScale(1, incoming),
			Color3.fromRGB(255, 46, 92))
		fill.ZIndex = 2
	end

	local well = frame(root, "Grid", UDim2.fromOffset(52, 132), UDim2.fromOffset(568, 1136), C.ground)
	stroke(well, accent, 3, 0.35)

	for r = 1, 20 do
		for c = 1, 10 do
			local key = grid[r][c]
			local cell = frame(well, "C", UDim2.new((c - 1) * 0.1, 2, (r - 1) * 0.05, 2),
				UDim2.new(0.1, -4, 0.05, -4), C.empty)
			if key then
				local col = PAL[key]
				cell.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.5)
				local core = frame(cell, "Core", UDim2.fromScale(0.17, 0.17), UDim2.fromScale(0.66, 0.66), col)
				core.ZIndex = 2
			end
		end
	end
end

-- P1 is stacking cleanly with a well open on the right; P2 is buried and taking
-- garbage. The two boards say what the game is before you press anything.
buildBoard(wings[-1], C.cy, "PLAYER 1", stack({ 7, 8, 9, 8, 7, 8, 9, 8, 4, 0 }, { { 3, 2 }, { 7, 4 } }, {}), 0)
buildBoard(wings[1], C.mg, "PLAYER 2",
	stack({ 12, 13, 14, 13, 12, 13, 14, 13, 12, 11 }, { { 5, 3 } }, { { 19, 7 }, { 20, 3 } }), 0.45)

local sub = Instance.new("Part")
sub.Name = "Subtitle"
sub.Size = V(50, 6, 0.2)
sub.CFrame = P(0, 5, -32.2)
sub.Anchored, sub.CanCollide, sub.CastShadow, sub.Transparency = true, false, false, 1
sub.Parent = F.Boards

local sgui = Instance.new("SurfaceGui")
sgui.Face = Enum.NormalId.Back -- unrotated part, so +Z is the room side
sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
sgui.PixelsPerStud = 36
sgui.LightInfluence = 0
sgui.Brightness = 2
sgui.Parent = sub

local lbl = Instance.new("TextLabel")
lbl.BackgroundTransparency = 1
lbl.Size = UDim2.fromScale(1, 1)
lbl.Font, lbl.Text, lbl.TextColor3 = Enum.Font.GothamBold, "1 V 1   B A T T L E", C.violet
lbl.TextScaled = true
lbl.Parent = sgui

-- ── Light rig ─────────────────────────────────────────────────────────────
local function lamp(name, pos, colour, range, brightness)
	local node = Instance.new("Part")
	node.Name = name
	node.Size = V(0.2, 0.2, 0.2)
	node.CFrame = CFrame.new(pos)
	node.Anchored, node.CanCollide, node.CastShadow, node.Transparency = true, false, false, 1
	node.Parent = F.Lights
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
	l.Parent = node
end

lamp("TitleL", V(-22, 26, -26), C.cy, 58, 2.2)
lamp("TitleR", V(22, 26, -26), C.mg, 58, 2.2)
for _, s in ipairs({ -1, 1 }) do
	local accent = s < 0 and C.cy or C.mg
	lamp("Wing", (wings[s].CFrame * CFrame.new(0, 2, -9)).Position, accent, 48, 2.0)
	for _, z in ipairs({ -12, 12 }) do
		lamp("Overhead", V(23 * s, 31, z), accent, 46, 1.4)
	end
end
lamp("Spawn", V(0, 11, 18), C.violet, 36, 1.7)

return ("Arena rebuilt — %d descendants"):format(#Arena:GetDescendants())
