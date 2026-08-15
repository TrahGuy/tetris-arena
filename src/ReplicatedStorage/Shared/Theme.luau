-- The UI system. One place for colour, type and the handful of constructors
-- every screen is built from, so the whole product looks like one thing.
--
-- The lobby is a dark hall lit by its own ceiling; the UI matches it. Panels are
-- near-opaque dark surfaces with a hairline stroke, accents are used sparingly,
-- and nothing glows except the thing you are meant to press.

local Theme = {}

Theme.C = {
	bg = Color3.fromRGB(11, 11, 15),
	panel = Color3.fromRGB(23, 23, 30),
	panelHi = Color3.fromRGB(33, 33, 42),
	line = Color3.fromRGB(56, 57, 70),
	text = Color3.fromRGB(238, 240, 248),
	muted = Color3.fromRGB(150, 154, 172),
	dim = Color3.fromRGB(102, 106, 124),

	cy = Color3.fromRGB(0, 216, 232),
	mg = Color3.fromRGB(226, 60, 190),
	violet = Color3.fromRGB(158, 122, 255),
	gold = Color3.fromRGB(255, 198, 96),
	red = Color3.fromRGB(255, 76, 92),
	green = Color3.fromRGB(64, 220, 132),
	blue = Color3.fromRGB(72, 132, 255),

	cellEmpty = Color3.fromRGB(26, 26, 34),
	board = Color3.fromRGB(15, 15, 20),
}

Theme.F = {
	display = Enum.Font.GothamBold,
	body = Enum.Font.Gotham,
	mono = Enum.Font.Code,
}

Theme.R = { sm = 4, md = 8, lg = 14 }

local function apply(inst: Instance, props: { [string]: any }?)
	if props then
		for k, v in pairs(props) do
			(inst :: any)[k] = v
		end
	end
	return inst
end

function Theme.frame(parent: Instance?, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Theme.C.panel
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	apply(f, props)
	f.Parent = parent
	return f
end

function Theme.corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.R.md)
	c.Parent = parent
	return c
end

function Theme.stroke(parent: Instance, colour: Color3?, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = colour or Theme.C.line
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Theme.pad(parent: Instance, n: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop, p.PaddingBottom = UDim.new(0, n), UDim.new(0, n)
	p.PaddingLeft, p.PaddingRight = UDim.new(0, n), UDim.new(0, n)
	p.Parent = parent
	return p
end

function Theme.list(parent: Instance, gap: number, dir: Enum.FillDirection?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap)
	l.FillDirection = dir or Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Parent = parent
	return l
end

function Theme.label(parent: Instance?, text: string, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Theme.F.body
	l.Text = text
	l.TextColor3 = Theme.C.text
	l.TextSize = 16
	l.RichText = true
	l.Size = UDim2.fromScale(1, 1)
	apply(l, props)
	l.Parent = parent
	return l
end

-- A panel: dark surface, rounded, hairline stroke. Every screen is made of these.
function Theme.panel(parent: Instance?, props: { [string]: any }?): Frame
	local f = Theme.frame(parent, props)
	Theme.corner(f, Theme.R.lg)
	Theme.stroke(f, Theme.C.line, 1, 0.35)
	return f
end

-- The one glowing element on screen. `accent` fills it; a secondary button is
-- the same shape in panel colour with an accent stroke.
function Theme.button(parent: Instance?, text: string, accent: Color3?, props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = accent or Theme.C.panelHi
	b.BorderSizePixel = 0
	b.Font = Theme.F.display
	b.Text = text
	b.TextColor3 = accent and Theme.C.bg or Theme.C.text
	b.TextSize = 18
	b.Size = UDim2.new(1, 0, 0, 44)
	apply(b, props)
	b.Parent = parent
	Theme.corner(b, Theme.R.md)
	if not accent then
		Theme.stroke(b, Theme.C.line, 1, 0.2)
	end

	local base = b.BackgroundColor3
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.16)
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = base
	end)
	return b
end

-- Uppercase caption with tracking. Used for every section heading.
function Theme.eyebrow(parent: Instance?, text: string, colour: Color3?, props: { [string]: any }?): TextLabel
	return Theme.label(parent, text, {
		Font = Theme.F.display,
		TextColor3 = colour or Theme.C.muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel
end

-- Scales the whole UI off a 1080p reference so it holds up on any resolution.
function Theme.autoScale(gui: Instance): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local cam = workspace.CurrentCamera
	local function update()
		local v = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		scale.Scale = math.clamp(math.min(v.X / 1600, v.Y / 900), 0.62, 1.5)
	end
	update()
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

return Theme
