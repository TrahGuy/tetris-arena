-- On-screen controls for touch devices.
--
-- Most of Roblox plays on a phone. Without this the game is not "missing a
-- convenience" on mobile, it is unplayable — there is no keyboard to press.
--
-- Buttons rather than swipe gestures: a swipe cannot be held, and holding left
-- to slide a piece to the wall is core to how the game is played. These drive
-- InputController's press/release directly, so DAS, countdown arming and the
-- sound cues behave exactly as they do on a keyboard.
--
-- Glyphs are drawn from rotated Frames, not text. Gotham renders arrow and
-- dingbat characters as blank boxes, so any control relying on "↺" or "▶"
-- would ship as an empty square on the one platform that needs it most.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local TouchControls = {}
TouchControls.__index = TouchControls

local SIZE = 74
local GAP = 10

local function pad(parent: Instance, name: string, pos: UDim2, size: UDim2, accent: Color3?)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = Theme.C.panel
	b.BackgroundTransparency = 0.18
	b.BorderSizePixel = 0
	b.Position = pos
	b.Size = size
	b.Parent = parent
	Theme.corner(b, 14)
	Theme.stroke(b, accent or Theme.C.line, 1.5, 0.25)
	return b
end

-- A chevron built from two rotated bars. Points: -1 left, 1 right, 2 down.
local function chevron(parent: Instance, dir: number, colour: Color3)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(30, 30)
	holder.Parent = parent
	for i = 1, 2 do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = colour
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Size = UDim2.fromOffset(19, 5)
		bar.Parent = holder
		local sign = (i == 1) and 1 or -1
		if dir == 2 then -- down
			bar.Position = UDim2.fromScale(0.5 + sign * 0.17, 0.5)
			bar.Rotation = sign * 45
		else
			bar.Position = UDim2.fromScale(0.5, 0.5 + sign * 0.17)
			bar.Rotation = sign * 45 * dir
		end
		Theme.corner(bar, 2)
	end
	return holder
end

local function caption(parent: Instance, text: string, colour: Color3)
	return Theme.label(parent, text, {
		Font = Theme.F.display,
		TextSize = 15,
		TextColor3 = colour,
		Size = UDim2.fromScale(1, 1),
	})
end

function TouchControls.new(parent: Instance, input: any)
	local self = setmetatable({ input = input, buttons = {} }, TouchControls)

	local root = Instance.new("Frame")
	root.Name = "TouchControls"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.ZIndex = 30
	root.Parent = parent
	self.root = root

	-- Left thumb: move and soft drop. Right thumb: rotate, hold, hard drop.
	-- Both clusters hug the bottom corners so neither hand covers the board.
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.AnchorPoint = Vector2.new(0, 1)
	left.Position = UDim2.new(0, 22, 1, -22)
	left.Size = UDim2.fromOffset(SIZE * 2 + GAP, SIZE * 2 + GAP)
	left.Parent = root

	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.AnchorPoint = Vector2.new(1, 1)
	right.Position = UDim2.new(1, -22, 1, -22)
	right.Size = UDim2.fromOffset(SIZE * 2 + GAP, SIZE * 2 + GAP)
	right.Parent = root

	local sq = UDim2.fromOffset(SIZE, SIZE)
	local defs = {
		{ p = left, n = "BA_Left", pos = UDim2.fromOffset(0, SIZE + GAP), size = sq,
			glyph = -1, accent = Theme.C.cy },
		{ p = left, n = "BA_Right", pos = UDim2.fromOffset(SIZE + GAP, SIZE + GAP), size = sq,
			glyph = 1, accent = Theme.C.cy },
		{ p = left, n = "BA_Soft", pos = UDim2.fromOffset(0, 0), size = UDim2.fromOffset(SIZE * 2 + GAP, SIZE),
			glyph = 2, accent = Theme.C.cy },
		{ p = right, n = "BA_CCW", pos = UDim2.fromOffset(0, SIZE + GAP), size = sq, text = "CCW",
			accent = Theme.C.violet },
		{ p = right, n = "BA_CW", pos = UDim2.fromOffset(SIZE + GAP, SIZE + GAP), size = sq, text = "CW",
			accent = Theme.C.violet },
		{ p = right, n = "BA_Hold", pos = UDim2.fromOffset(0, 0), size = sq, text = "HOLD",
			accent = Theme.C.gold },
		{ p = right, n = "BA_Hard", pos = UDim2.fromOffset(SIZE + GAP, 0), size = sq, text = "DROP",
			accent = Theme.C.mg },
	}

	for _, d in ipairs(defs) do
		local b = pad(d.p, d.n, d.pos, d.size, d.accent)
		if d.text then
			caption(b, d.text, d.accent)
		else
			chevron(b, d.glyph, d.accent)
		end
		self.buttons[d.n] = b

		-- InputBegan/Ended rather than Activated: a press has to be holdable,
		-- and Activated only fires on release.
		b.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch
				or io.UserInputType == Enum.UserInputType.MouseButton1 then
				b.BackgroundTransparency = 0
				if self.input then self.input:pressAction(d.n) end
			end
		end)
		local function release(io)
			if io.UserInputType == Enum.UserInputType.Touch
				or io.UserInputType == Enum.UserInputType.MouseButton1 then
				b.BackgroundTransparency = 0.18
				if self.input then self.input:releaseAction(d.n) end
			end
		end
		b.InputEnded:Connect(release)
		-- A finger that slides off the button must still release it, or the
		-- piece keeps sliding after the thumb has gone.
		b.MouseLeave:Connect(function()
			b.BackgroundTransparency = 0.18
			if self.input then self.input:releaseAction(d.n) end
		end)
	end

	local forfeit = pad(root, "BA_Forfeit", UDim2.new(0, 22, 0, 22), UDim2.fromOffset(84, 34), Theme.C.red)
	forfeit.AnchorPoint = Vector2.new(0, 0)
	caption(forfeit, "FORFEIT", Theme.C.red)
	forfeit.Activated:Connect(function()
		if self.input then self.input:pressAction("BA_Forfeit") end
	end)

	return self
end

-- A fresh InputController is built for every match, so the pad is re-pointed
-- rather than rebuilt.
function TouchControls:setInput(input: any)
	self.input = input
end

function TouchControls.shouldShow(): boolean
	-- Touch present and no keyboard: a Windows laptop with a touchscreen should
	-- keep the keyboard layout rather than losing half its screen to buttons.
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function TouchControls:setVisible(on: boolean)
	self.root.Visible = on and TouchControls.shouldShow()
end

return TouchControls
