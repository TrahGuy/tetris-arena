-- Draws a board into a Frame.
--
-- Three rules keep this cheap, and all three came from getting it wrong first:
--   * the cell pool is built once at construction, never during play
--   * no UIStroke per cell — 200 strokes is a real cost, and the 2px gutter
--     between cells already reads as the grid
--   * cells are diffed against the last frame, so a quiet board writes nothing
--
-- Cells are drawn as a dark shell with a bright core, which reads as a lit block
-- rather than a flat square.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pieces = require(Shared.Pieces)
local SkinData = require(Shared.SkinData)
local Theme = require(Shared.Theme)
local Tuning = require(Shared.Tuning)

local BoardRenderer = {}
BoardRenderer.__index = BoardRenderer

local GHOST = 100 -- display codes at and above this are ghost cells

function BoardRenderer.new(parent: Instance, opts: any?)
	opts = opts or {}
	local w, h = Tuning.WIDTH, Tuning.VISIBLE
	local self = setmetatable({
		w = w,
		h = h,
		skinId = opts.skinId or SkinData.DEFAULT_ID,
		colourblind = opts.colourblind == true,
		shells = table.create(w * h),
		cores = table.create(w * h),
		last = table.create(w * h, -1),
		gutter = opts.gutter or 2,
		-- The board frame's own colours are the skin's too, but this renderer
		-- may be a small opponent preview with a caller-chosen accent, so that
		-- one stays overridable.
		accentOverride = opts.accent,
	}, BoardRenderer)
	self.skin = SkinData.resolve(self.skinId)
	self.palette = SkinData.paletteFor(self.skinId, self.colourblind)

	local root = Instance.new("Frame")
	root.Name = "Board"
	root.BackgroundColor3 = self.skin.board
	root.BorderSizePixel = 0
	root.Size = opts.size or UDim2.fromScale(1, 1)
	root.Position = opts.position or UDim2.fromScale(0, 0)
	root.AnchorPoint = opts.anchor or Vector2.new(0, 0)
	root.Parent = parent
	self.root = root

	if opts.aspect ~= false then
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = w / h
		ar.Parent = root
	end
	Theme.corner(root, 6)
	self.stroke = Theme.stroke(root, opts.accent or self.skin.accent, opts.strokeThickness or 2, 0.2)

	-- Absolute-scale placement rather than a UIGridLayout: a grid layout reflows
	-- on every change and buys nothing for a fixed board.
	local g = self.gutter
	for row = 1, h do
		for col = 1, w do
			local i = (row - 1) * w + col
			local shell = Instance.new("Frame")
			shell.Name = "c"
			shell.BorderSizePixel = 0
			shell.BackgroundColor3 = self.skin.cellEmpty
			-- row 1 is the bottom of the board, so the top of the screen is row h.
			shell.Position = UDim2.new((col - 1) / w, g, (h - row) / h, g)
			shell.Size = UDim2.new(1 / w, -g * 2, 1 / h, -g * 2)
			shell.Parent = root
			self.shells[i] = shell

			local core = Instance.new("Frame")
			core.Name = "k"
			core.BorderSizePixel = 0
			core.BackgroundTransparency = 1
			core.Position = UDim2.fromScale(0.17, 0.17)
			core.Size = UDim2.fromScale(0.66, 0.66)
			core.ZIndex = 2
			core.Parent = shell
			self.cores[i] = core
		end
	end
	return self
end

-- Recomputes everything the skin decides and forces a full repaint.
--
-- Cheap on purpose: it swaps a cached palette table and a handful of scalars,
-- then invalidates the diff so the next paint rewrites every cell once. No
-- per-cell object is created, destroyed or tweened — the cell pool built above
-- is the same pool for every skin.
function BoardRenderer:_apply()
	self.skin = SkinData.resolve(self.skinId)
	self.palette = SkinData.paletteFor(self.skinId, self.colourblind)
	self.root.BackgroundColor3 = self.skin.board
	if self.stroke then
		self.stroke.Color = self.accentOverride or self.skin.accent
	end
	table.clear(self.last)
	for i = 1, self.w * self.h do self.last[i] = -1 end
end

function BoardRenderer:setSkin(skinId: string?)
	self.skinId = SkinData.exists(skinId) and skinId or SkinData.DEFAULT_ID
	self:_apply()
end

function BoardRenderer:setPalette(colourblind: boolean)
	self.colourblind = colourblind == true
	self:_apply()
end

-- Builds the display array: locked cells, then ghost, then the live piece on top.
function BoardRenderer:compose(board: any, showGhost: boolean?): { number }
	local w, h = self.w, self.h
	local disp = table.create(w * h, 0)
	for i = 1, w * h do
		disp[i] = board.cells[i]
	end

	local p = board.piece
	if p then
		local shape = Pieces.SHAPES[p.kind][p.rot]
		if showGhost ~= false then
			local gy = board:ghostY()
			if gy and gy ~= p.y then
				for i = 1, 4 do
					local c = shape[i]
					local col, row = p.x + c[1] + 1, gy + c[2]
					if col >= 1 and col <= w and row >= 1 and row <= h then
						disp[(row - 1) * w + col] = GHOST + p.kind
					end
				end
			end
		end
		for i = 1, 4 do
			local c = shape[i]
			local col, row = p.x + c[1] + 1, p.y + c[2]
			if col >= 1 and col <= w and row >= 1 and row <= h then
				disp[(row - 1) * w + col] = p.kind
			end
		end
	end
	return disp
end

function BoardRenderer:paint(disp: { number })
	local last = self.last
	for i = 1, self.w * self.h do
		local v = disp[i]
		if v ~= last[i] then
			last[i] = v
			local shell, core = self.shells[i], self.cores[i]
			if v == 0 then
				shell.BackgroundColor3 = self.skin.cellEmpty
				shell.BackgroundTransparency = 0
				core.BackgroundTransparency = 1
			elseif v >= GHOST then
				local colour = self.palette[v - GHOST] or Theme.C.muted
				shell.BackgroundColor3 = colour
				shell.BackgroundTransparency = self.skin.ghostTransparency
				core.BackgroundTransparency = 1
			else
				local colour = self.palette[v] or Theme.C.muted
				shell.BackgroundColor3 = colour:Lerp(Color3.new(0, 0, 0), self.skin.shellDarken)
				shell.BackgroundTransparency = 0
				core.BackgroundColor3 = colour
				core.BackgroundTransparency = 0
			end
		end
	end
end

function BoardRenderer:render(board: any, showGhost: boolean?)
	self:paint(self:compose(board, showGhost))
end

-- For the opponent board, which arrives as a flat array with no live piece.
function BoardRenderer:renderCells(cells: { number })
	self:paint(cells)
end

function BoardRenderer:clear()
	local blank = table.create(self.w * self.h, 0)
	self:paint(blank)
end

function BoardRenderer:destroy()
	self.root:Destroy()
end

return BoardRenderer
