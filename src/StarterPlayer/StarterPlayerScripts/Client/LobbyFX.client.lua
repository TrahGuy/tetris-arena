-- Lobby FX. Everything here is cosmetic and runs entirely on the client: every
-- part it touches is anchored, so local CFrame writes never replicate and the
-- server pays nothing for any of it.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Lobby = workspace:WaitForChild("Lobby", 30)
if not Lobby then return end

local PIECE = {
	Color3.fromRGB(34, 228, 245), Color3.fromRGB(255, 216, 77), Color3.fromRGB(194, 77, 255),
	Color3.fromRGB(61, 232, 107), Color3.fromRGB(255, 61, 94), Color3.fromRGB(77, 130, 255),
	Color3.fromRGB(255, 154, 43),
}
local SHAPES = {
	{ { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } }, { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } },
	{ { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } }, { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } },
	{ { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } }, { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
	{ { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
}
local EMPTY = Color3.fromRGB(28, 24, 46)

local core = Lobby:WaitForChild("Core")
local portal = Lobby:WaitForChild("Portal")
local CENTRE = core:GetAttribute("CoreCentre")
local RADIUS = core:GetAttribute("OrbitRadius")

-- ── Gather everything once ────────────────────────────────────────────────
local orbiters, spinners, rings = {}, {}, {}
for _, d in ipairs(Lobby:GetDescendants()) do
	if d:IsA("Model") then
		if d:GetAttribute("Orbit") then
			table.insert(orbiters, d)
		elseif d:GetAttribute("SpinSpeed") then
			table.insert(spinners, { model = d, home = d:GetPivot(), speed = d:GetAttribute("SpinSpeed") })
		end
	elseif d:IsA("BasePart") and d:GetAttribute("SpinSeed") then
		table.insert(rings, { part = d, home = d.CFrame, seed = d:GetAttribute("SpinSeed") })
	end
end

local fallers = {}
for _, p in ipairs(Lobby.FX:GetChildren()) do
	if p:IsA("BasePart") then table.insert(fallers, { part = p, y = -200, speed = 0, spin = 0 }) end
end
local function respawnFaller(f, high)
	f.x, f.z = (math.random() - 0.5) * 280, (math.random() - 0.5) * 280
	f.y = high and (70 + math.random() * 70) or (math.random() * 110)
	f.speed = 13 + math.random() * 24
	f.spin = (math.random() - 0.5) * 2.6
	f.part.Color = PIECE[math.random(#PIECE)]
	f.part.Size = Vector3.one * (1.5 + math.random() * 1.9)
end
for _, f in ipairs(fallers) do respawnFaller(f, false) end

local door, threshold = {}, portal:WaitForChild("Threshold")
for _, p in ipairs(portal.Door:GetChildren()) do
	table.insert(door, {
		part = p,
		home = p:GetAttribute("Home"),
		shell = p.Name == "Block",
		scatter = CFrame.new((math.random() - 0.5) * 30, 34 + math.random() * 30, (math.random() - 0.5) * 12)
			* CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3),
	})
end
local OPEN_RADIUS = threshold:GetAttribute("Radius") or 22
local doorAlpha, doorSettled = 0, true

-- ── Spawn burst ───────────────────────────────────────────────────────────
-- Parented under the Camera so the debris never enters the replicated tree.
local function burst(origin)
	local bin = Instance.new("Folder")
	bin.Parent = workspace.CurrentCamera
	for _ = 1, 18 do
		local p = Instance.new("Part")
		p.Size = Vector3.one * (0.7 + math.random() * 1.3)
		p.Anchored, p.CanCollide, p.CastShadow = true, false, false
		p.Material, p.Color = Enum.Material.Neon, PIECE[math.random(#PIECE)]
		p.CFrame = CFrame.new(origin) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		p.Parent = bin
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9, math.random() - 0.5).Unit
		TweenService:Create(p, TweenInfo.new(0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(origin + dir * (10 + math.random() * 9))
				* CFrame.Angles(math.random() * 8, math.random() * 8, math.random() * 8),
			Transparency = 1,
			Size = Vector3.one * 0.2,
		}):Play()
	end
	task.delay(1.1, function() bin:Destroy() end)
end

local function onCharacter(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if hrp then burst(hrp.Position) end
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

-- ── Training board: a real falling-and-locking stack, not a loop of frames ─
task.spawn(function()
	local board = Lobby.Training:FindFirstChild("MiniBoard")
	local sg = board and board:FindFirstChildWhichIsA("SurfaceGui")
	local well = sg and sg:FindFirstChild("Grid", true)
	if not well then return end

	local cells = {}
	for r = 1, 20 do
		cells[r] = {}
		for c = 1, 10 do cells[r][c] = well:FindFirstChild(("C_%d_%d"):format(r, c)) end
	end
	local heights = {}
	local function reset()
		for r = 1, 20 do
			for c = 1, 10 do
				if cells[r][c] then cells[r][c].BackgroundColor3 = EMPTY end
			end
		end
		for c = 1, 10 do heights[c] = 0 end
	end
	local function paint(shape, col, row, colour)
		for _, cc in ipairs(shape) do
			local r, c = row + cc[2], col + cc[1]
			if r >= 1 and r <= 20 and c >= 1 and c <= 10 and cells[r][c] then
				cells[r][c].BackgroundColor3 = colour
			end
		end
	end

	reset()
	while true do
		local idx = math.random(#SHAPES)
		local shape, colour = SHAPES[idx], PIECE[idx]
		local w = 0
		for _, cc in ipairs(shape) do w = math.max(w, cc[1] + 1) end
		local col = math.random(1, 10 - w + 1)
		local rest = 0
		for _, cc in ipairs(shape) do rest = math.max(rest, heights[col + cc[1]]) end
		local landing = 20 - rest - 1

		for row = 1, landing do
			paint(shape, col, row, colour)
			task.wait(0.055)
			if row < landing then paint(shape, col, row, EMPTY) end
		end
		for _, cc in ipairs(shape) do
			heights[col + cc[1]] = math.max(heights[col + cc[1]], 20 - (landing + cc[2]) + 1)
		end
		local tallest = 0
		for c = 1, 10 do tallest = math.max(tallest, heights[c]) end
		if tallest >= 13 then
			task.wait(0.5)
			reset()
		end
		task.wait(0.18)
	end
end)

-- ── Per-frame ─────────────────────────────────────────────────────────────
local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt

	for _, m in ipairs(orbiters) do
		local a = m:GetAttribute("Orbit") + t * 0.17
		local pos = Vector3.new(
			CENTRE.X + math.sin(a) * RADIUS,
			CENTRE.Y + math.sin(t * 0.8 + a * 2) * 2.8,
			CENTRE.Z + math.cos(a) * RADIUS)
		m:PivotTo(CFrame.new(pos) * CFrame.Angles(t * 0.33, t * 0.48 + a, t * 0.19))
	end

	for _, s in ipairs(spinners) do
		s.model:PivotTo(s.home
			* CFrame.new(0, math.sin(t * 1.1 + s.speed) * 0.5, 0)
			* CFrame.Angles(0, t * s.speed, 0))
	end

	for _, r in ipairs(rings) do
		r.part.CFrame = r.home
			* CFrame.new(0, math.sin(t * 1.4 + r.seed) * 0.9, 0)
			* CFrame.Angles(0, t * 0.8 + r.seed, 0)
	end

	for _, f in ipairs(fallers) do
		f.y -= f.speed * dt
		if f.y < -4 then respawnFaller(f, true) end
		local fade = math.clamp(f.y / 14, 0, 1) * math.clamp((120 - f.y) / 16, 0, 1)
		f.part.Transparency = 1 - 0.7 * fade
		f.part.CFrame = CFrame.new(f.x, f.y, f.z) * CFrame.Angles(t * f.spin, t * f.spin * 1.4, 0)
	end

	-- Door opens when anyone stands on the threshold, and settles to a stop so
	-- 96 parts are not being written every frame while nobody is there.
	local want = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - threshold.Position).Magnitude < OPEN_RADIUS then
			want = 1
			break
		end
	end
	if math.abs(want - doorAlpha) > 0.002 or not doorSettled then
		doorAlpha += (want - doorAlpha) * math.min(1, dt * 5)
		doorSettled = math.abs(want - doorAlpha) <= 0.002
		if doorSettled then doorAlpha = want end
		local solid = doorAlpha < 0.5
		for _, b in ipairs(door) do
			b.part.CFrame = b.home:Lerp(b.home * b.scatter, doorAlpha)
			b.part.Transparency = doorAlpha
			if b.shell then b.part.CanCollide = solid end
		end
	end
end)
