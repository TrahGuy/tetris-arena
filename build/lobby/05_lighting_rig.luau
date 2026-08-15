-- Block Arena lobby — 05: the lighting rig.
--
-- One file owns every light in the hall. 01-04 each dropped their own lamps as
-- they built; this clears all of that and rebuilds from a single plan, so the
-- room has a coherent lighting scheme instead of forty unrelated point lights.
--
-- The scheme is architectural: the ceiling coffers are the ambient source and
-- they are warm and neutral, columns get uplights, and colour appears only as
-- small accent spots on the things that own a colour. Neon lights nothing in
-- Roblox — it only glows — which is exactly why the first pass looked bright
-- and lit nothing.

local Lobby = workspace:WaitForChild("Lobby")
local F = Lobby:FindFirstChild("Lights") or Instance.new("Folder")
F.Name, F.Parent = "Lights", Lobby
F:ClearAllChildren()
local H = Lobby:FindFirstChild("Holo")
if H then H:ClearAllChildren() end

-- Every lamp 01-04 parented elsewhere goes too.
for _, d in ipairs(Lobby:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == "Lamp" then d:Destroy() end
end

local WARM = Color3.fromRGB(255, 240, 214)
local NEUTRAL = Color3.fromRGB(226, 232, 244)
local COOL = Color3.fromRGB(176, 206, 255)
local CY = Color3.fromRGB(0, 216, 232)
local MG = Color3.fromRGB(226, 60, 190)
local GOLD = Color3.fromRGB(255, 198, 96)
local METAL_D = Color3.fromRGB(66, 68, 78)
local METAL, NEON = Enum.Material.Metal, Enum.Material.Neon

local function mk(name, parent, size, cf, colour, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cf, colour, mat
	p.Anchored, p.CanCollide, p.CastShadow = true, false, false
	p.Transparency = o.tr or 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function V(x, y, z) return Vector3.new(x, y, z) end
local function P(x, y, z) return CFrame.new(x, y, z) end

local lampCount = 0
local function lamp(pos, colour, range, brightness, parent)
	local n = mk("Lamp", parent or F, V(0.2, 0.2, 0.2), CFrame.new(pos), NEUTRAL, METAL, { tr = 1 })
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
	l.Parent = n
	lampCount += 1
	return n
end
local function spot(pos, target, colour, range, brightness, angle)
	local n = mk("Lamp", F, V(0.2, 0.2, 0.2), CFrame.lookAt(pos, target), NEUTRAL, METAL, { tr = 1 })
	local l = Instance.new("SpotLight")
	l.Color, l.Range, l.Brightness, l.Angle, l.Shadows = colour, range, brightness, angle or 60, false
	l.Face = Enum.NormalId.Front -- CFrame.lookAt aims local -Z, which is Front
	l.Parent = n
	lampCount += 1
	return n
end

-- ── Ceiling coffers: the hall's ambient source ───────────────────────────
-- Every bay gets a fixture so the ceiling reads as designed; every other bay
-- gets an actual light, which is plenty at this range and keeps the count sane.
local BAYS = { -125, -75, -25, 25, 75, 125 }
local fixtures = 0
for xi, x in ipairs(BAYS) do
	for zi, z in ipairs(BAYS) do
		mk("FixtureFrame", F, V(30, 0.7, 30), P(x, 100.1, z), METAL_D, METAL)
		mk("FixtureLens", F, V(27, 0.5, 27), P(x, 99.9, z), WARM, NEON, { tr = 0.58 })
		fixtures += 1
		-- Deliberately short-range: overlapping 150-stud lights washed the hall
		-- flat. These want to read as pools under the fixtures.
		if (xi + zi) % 2 == 0 then
			lamp(V(x, 90, z), WARM, 112, 0.8)
		end
	end
end

-- ── Colonnade uplights ───────────────────────────────────────────────────
-- Every other column, washing the concrete so the walls have vertical form.
local COLS = {}
for _, v in ipairs({ -125, -25, 75 }) do
	table.insert(COLS, { -146, v }); table.insert(COLS, { 146, v })
	table.insert(COLS, { v, -146 }); table.insert(COLS, { v, 146 })
end
for _, c in ipairs(COLS) do
	mk("Uplight", F, V(5, 0.5, 5), P(c[1], 3.3, c[2]), WARM, NEON, { tr = 0.55 })
	spot(V(c[1], 4, c[2]), V(c[1], 60, c[2]), WARM, 70, 1.6, 44)
end

-- ── Plaza ────────────────────────────────────────────────────────────────
-- Downlights on the rim so the steps read, and a cool fill under the core.
for _, c in ipairs({ { -34, -14 }, { 34, -14 }, { -34, 54 }, { 34, 54 },
	{ 0, -20 }, { 0, 60 }, { -40, 20 }, { 40, 20 } }) do
	spot(V(c[1], 88, c[2]), V(c[1], -4.5, c[2]), NEUTRAL, 110, 1.05, 34)
end
lamp(V(0, 8, 20), COOL, 60, 1.1)
lamp(V(0, 36, 20), COOL, 70, 1.6)

-- ── Portal wall wash ─────────────────────────────────────────────────────
spot(V(-34, 80, -100), V(-34, 30, -120), CY, 90, 1.7, 46)
spot(V(34, 80, -100), V(34, 30, -120), MG, 90, 1.7, 46)
spot(V(0, 74, -96), V(0, 24, -120), NEUTRAL, 90, 1.5, 40)
lamp(V(0, 16, -112), COOL, 46, 1.4)
for _, s in ipairs({ -1, 1 }) do
	lamp(V(s * 74, 42, -113), s < 0 and CY or MG, 56, 1.0)
end

-- ── Zone accents ─────────────────────────────────────────────────────────
-- Matchmaking: one spot per station, in the station's own colour.
for _, s in ipairs({ { 0, Color3.fromRGB(255, 154, 43) }, { -42, Color3.fromRGB(255, 58, 74) },
	{ 42, Color3.fromRGB(43, 107, 255) } }) do
	spot(V(s[1], 60, -40), V(s[1], 2, -40), s[2], 74, 1.5, 30)
end
-- Museum: a tight spot per pedestal. Galleries are lit object-by-object.
for _, z in ipairs({ -36, -20, -4 }) do
	spot(V(-95, 52, z), V(-95, 13, z), NEUTRAL, 60, 2.2, 20)
end
lamp(V(-78, 20, -20), MG, 46, 0.6)
-- Leaderboard: gold up the tower, neutral on the panels.
spot(V(78, 70, -10), V(95, 50, -10), GOLD, 80, 1.6, 40)
lamp(V(95, 92, -10), GOLD, 50, 1.7)
lamp(V(80, 34, -6), NEUTRAL, 46, 1.0)
-- Training: the screen wall and the practice pad.
spot(V(-75, 62, 105), V(-75, 26, 126), NEUTRAL, 80, 1.5, 40)
lamp(V(-75, 12, 73), CY, 44, 1.1)
lamp(V(-49, 14, 99), CY, 28, 0.9)
-- Lounge: warm, low and pooled. The one place in the hall that is not cool.
lamp(V(75, 14, 95), WARM, 54, 1.5)
lamp(V(75, 18, 121), MG, 44, 0.8)
lamp(V(99, 14, 95), WARM, 36, 1.0)
-- The nook stays nearly dark on purpose.
lamp(V(130, 12, -142), COOL, 22, 0.55)

return ("lighting rig — %d fixtures, %d lights"):format(fixtures, lampCount)
