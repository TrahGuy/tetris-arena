-- The match HUD: hold, next, board, incoming meter, opponent, readouts.
--
-- Laid out at a fixed pixel size inside a centred container and scaled as a
-- whole by Theme.autoScale, so the arrangement never reflows between
-- resolutions — a Tetris HUD that moves its own board around is unplayable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Pieces = require(Shared.Pieces)
local Tuning = require(Shared.Tuning)
local BoardRenderer = require(script.Parent.BoardRenderer)

local Hud = {}
Hud.__index = Hud

local BOARD_W, BOARD_H = 330, 660
local SIDE = 132
local MINI_W, MINI_H = 165, 330
local GAP = 14

-- A 4x4 preview cell grid, reused for hold and for every next slot.
local function makeMini(parent: Instance, size: number)
	local box = Theme.panel(parent, {
		BackgroundColor3 = Theme.C.board,
		Size = UDim2.fromOffset(size, size),
	})
	local cells = {}
	for r = 1, 4 do
		for c = 1, 4 do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundTransparency = 1
			f.Position = UDim2.new((c - 1) / 4, 2, (4 - r) / 4, 2)
			f.Size = UDim2.new(1 / 4, -4, 1 / 4, -4)
			f.Parent = box
			cells[(r - 1) * 4 + c] = f
		end
	end
	return box, cells
end

local function paintMini(cells: { Frame }, kind: number?, palette: { Color3 })
	for i = 1, 16 do
		cells[i].BackgroundTransparency = 1
	end
	if not kind then return end
	local shape = Pieces.SHAPES[kind][1]
	-- Centre the shape in the 4x4 box.
	local minX, maxX, minY, maxY = 9, -9, 9, -9
	for _, c in ipairs(shape) do
		minX, maxX = math.min(minX, c[1]), math.max(maxX, c[1])
		minY, maxY = math.min(minY, c[2]), math.max(maxY, c[2])
	end
	local ox = math.floor((4 - (maxX - minX + 1)) / 2) - minX
	local oy = math.floor((4 - (maxY - minY + 1)) / 2) - minY
	for _, c in ipairs(shape) do
		local col, row = c[1] + ox + 1, c[2] + oy + 1
		if col >= 1 and col <= 4 and row >= 1 and row <= 4 then
			local f = cells[(row - 1) * 4 + col]
			f.BackgroundColor3 = palette[kind]
			f.BackgroundTransparency = 0
		end
	end
end

function Hud.new(parent: Instance, opts: any?)
	opts = opts or {}
	local palette = opts.colourblind and Pieces.COLOURS_HC or Pieces.COLOURS
	local self = setmetatable({ palette = palette, nextCells = {} }, Hud)

	local root = Instance.new("Frame")
	root.Name = "Match"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = parent
	self.root = root

	local total = SIDE + GAP + BOARD_W + GAP + SIDE + GAP * 3 + MINI_W
	local rig = Instance.new("Frame")
	rig.Name = "Rig"
	rig.BackgroundTransparency = 1
	rig.AnchorPoint = Vector2.new(0.5, 0.5)
	rig.Position = UDim2.fromScale(0.5, 0.5)
	rig.Size = UDim2.fromOffset(total, BOARD_H + 96)
	rig.Parent = root
	self.rig = rig

	local x = 0

	-- ── Hold and the incoming meter ───────────────────────────────────────
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Position = UDim2.fromOffset(x, 48)
	left.Size = UDim2.fromOffset(SIDE, BOARD_H)
	left.Parent = rig
	x += SIDE + GAP

	Theme.eyebrow(left, "HOLD", Theme.C.muted, {
		Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(SIDE, 16),
	})
	local holdBox, holdCells = makeMini(left, SIDE - 8)
	holdBox.Position = UDim2.fromOffset(4, 20)
	self.holdCells = holdCells
	self.holdBox = holdBox

	Theme.eyebrow(left, "INCOMING", Theme.C.red, {
		Position = UDim2.fromOffset(4, SIDE + 30), Size = UDim2.fromOffset(SIDE, 16),
	})
	local meterBg = Theme.frame(left, {
		BackgroundColor3 = Theme.C.panel,
		Position = UDim2.fromOffset(4, SIDE + 50),
		Size = UDim2.fromOffset(22, BOARD_H - SIDE - 60),
	})
	Theme.corner(meterBg, 4)
	local meterFill = Theme.frame(meterBg, {
		BackgroundColor3 = Theme.C.red,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
	})
	Theme.corner(meterFill, 4)
	self.meterFill = meterFill
	self.meterLabel = Theme.label(left, "0", {
		Font = Theme.F.display, TextColor3 = Theme.C.red, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(32, SIDE + 50), Size = UDim2.fromOffset(60, 22),
	})

	-- ── Board ─────────────────────────────────────────────────────────────
	local boardHolder = Instance.new("Frame")
	boardHolder.BackgroundTransparency = 1
	boardHolder.Position = UDim2.fromOffset(x, 48)
	boardHolder.Size = UDim2.fromOffset(BOARD_W, BOARD_H)
	boardHolder.Parent = rig
	self.boardHolder = boardHolder
	x += BOARD_W + GAP

	self.renderer = BoardRenderer.new(boardHolder, {
		aspect = false,
		accent = Theme.C.cy,
		colourblind = opts.colourblind,
	})

	-- Banner for combo / back-to-back / spin callouts.
	self.banner = Theme.label(boardHolder, "", {
		Font = Theme.F.display, TextSize = 30, TextColor3 = Theme.C.gold,
		Position = UDim2.fromOffset(0, -44), Size = UDim2.fromOffset(BOARD_W, 40),
		TextTransparency = 1,
	})

	-- Countdown / KO overlay, drawn over the board only.
	self.overlay = Theme.label(boardHolder, "", {
		Font = Theme.F.display, TextSize = 96, TextColor3 = Theme.C.text,
		Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20,
	})

	-- ── Next ──────────────────────────────────────────────────────────────
	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromOffset(x, 48)
	right.Size = UDim2.fromOffset(SIDE, BOARD_H)
	right.Parent = rig
	x += SIDE + GAP * 3

	Theme.eyebrow(right, "NEXT", Theme.C.muted, {
		Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(SIDE, 16),
	})
	local slot = SIDE - 8
	for i = 1, Tuning.PREVIEW do
		local box, cells = makeMini(right, slot)
		box.Position = UDim2.fromOffset(4, 20 + (i - 1) * (slot + 6))
		self.nextCells[i] = cells
	end

	-- ── Opponent ──────────────────────────────────────────────────────────
	local opp = Instance.new("Frame")
	opp.BackgroundTransparency = 1
	opp.Position = UDim2.fromOffset(x, 48)
	opp.Size = UDim2.fromOffset(MINI_W, BOARD_H)
	opp.Parent = rig
	self.oppHolder = opp

	self.oppName = Theme.eyebrow(opp, "OPPONENT", Theme.C.mg, {
		Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(MINI_W, 16),
	})
	local oppBoard = Instance.new("Frame")
	oppBoard.BackgroundTransparency = 1
	oppBoard.Position = UDim2.fromOffset(0, 20)
	oppBoard.Size = UDim2.fromOffset(MINI_W, MINI_H)
	oppBoard.Parent = opp
	self.oppRenderer = BoardRenderer.new(oppBoard, {
		aspect = false,
		accent = Theme.C.mg,
		gutter = 1,
		strokeThickness = 1,
		colourblind = opts.colourblind,
	})
	self.oppStatus = Theme.label(opp, "", {
		TextColor3 = Theme.C.muted, TextSize = 14,
		Position = UDim2.fromOffset(0, MINI_H + 26), Size = UDim2.fromOffset(MINI_W, 20),
	})

	-- ── Readouts ──────────────────────────────────────────────────────────
	local stats = Instance.new("Frame")
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(SIDE + GAP, BOARD_H + 54)
	stats.Size = UDim2.fromOffset(BOARD_W, 34)
	stats.Parent = rig
	self.statFields = {}
	local names = { "APM", "PPS", "ATK", "LINES" }
	for i, name in ipairs(names) do
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.Position = UDim2.fromScale((i - 1) / #names, 0)
		cell.Size = UDim2.fromScale(1 / #names, 1)
		cell.Parent = stats
		Theme.label(cell, name, {
			TextColor3 = Theme.C.dim, TextSize = 11, Font = Theme.F.display,
			Size = UDim2.fromScale(1, 0.42),
		})
		self.statFields[name] = Theme.label(cell, "0", {
			TextColor3 = Theme.C.text, TextSize = 18, Font = Theme.F.display,
			Position = UDim2.fromScale(0, 0.42), Size = UDim2.fromScale(1, 0.58),
		})
	end

	self.hint = Theme.label(rig, "MOVE ←→   ROTATE Z / X   HOLD C   HARD DROP SPACE   FORFEIT F", {
		TextColor3 = Theme.C.dim, TextSize = 12,
		Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(total, 18),
	})
	return self
end

function Hud:show(on: boolean)
	self.root.Visible = on
end

function Hud:setOpponentVisible(on: boolean)
	self.oppHolder.Visible = on
end

function Hud:render(board: any)
	self.renderer:render(board)
	paintMini(self.holdCells, board.hold, self.palette)
	local upcoming = board:next(Tuning.PREVIEW)
	for i = 1, Tuning.PREVIEW do
		paintMini(self.nextCells[i], upcoming[i], self.palette)
	end
end

function Hud:setIncoming(rows: number)
	local frac = math.clamp(rows / 12, 0, 1)
	self.meterFill.Size = UDim2.fromScale(1, frac)
	self.meterLabel.Text = tostring(rows)
	self.meterFill.BackgroundColor3 = rows >= 8 and Theme.C.red or Theme.C.gold
end

function Hud:setOpponent(name: string, accent: Color3?)
	self.oppName.Text = string.upper(name)
	if accent then self.oppName.TextColor3 = accent end
end

function Hud:renderOpponent(cells: { number })
	self.oppRenderer:renderCells(cells)
end

function Hud:setOpponentStatus(text: string)
	self.oppStatus.Text = text
end

function Hud:setStats(apm: number, pps: number, attack: number, lines: number)
	self.statFields.APM.Text = string.format("%.0f", apm)
	self.statFields.PPS.Text = string.format("%.2f", pps)
	self.statFields.ATK.Text = tostring(attack)
	self.statFields.LINES.Text = tostring(lines)
end

-- Combo, back-to-back and spin callouts share one banner: stacking three
-- separate labels next to a board that needs reading is noise.
function Hud:flash(text: string, colour: Color3?)
	local b = self.banner
	b.Text = text
	b.TextColor3 = colour or Theme.C.gold
	b.TextTransparency = 0
	b.TextSize = 34
	TweenService:Create(b, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextSize = 26,
	}):Play()
end

function Hud:setOverlay(text: string?, colour: Color3?)
	if not text then
		self.overlay.Visible = false
		return
	end
	self.overlay.Text = text
	self.overlay.TextColor3 = colour or Theme.C.text
	self.overlay.Visible = true
end

function Hud:reset()
	self.renderer:clear()
	self.oppRenderer:clear()
	self:setIncoming(0)
	self:setStats(0, 0, 0, 0)
	self:setOverlay(nil)
	self.oppStatus.Text = ""
	paintMini(self.holdCells, nil, self.palette)
	for i = 1, Tuning.PREVIEW do
		paintMini(self.nextCells[i], nil, self.palette)
	end
end

return Hud
