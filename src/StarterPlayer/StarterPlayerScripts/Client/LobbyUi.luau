-- Everything on screen that is not the match board.
--
-- The original plan had a fullscreen PLAY menu. The lobby now has physical
-- matchmaking pads, so a menu that duplicates them would be two front doors to
-- the same room: this handles the states the world cannot show — searching,
-- results, settings, help — and leaves "start a match" to the pads.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)
local BlitzScoring = require(Shared.BlitzScoring)
local TitleData = require(Shared.TitleData)

local LobbyUi = {}
LobbyUi.__index = LobbyUi

local function screen(parent: Instance, name: string)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Theme.C.bg
	f.BackgroundTransparency = 0.35
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.Visible = false
	f.Parent = parent
	return f
end

local function card(parent: Instance, w: number, h: number)
	local c = Theme.panel(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 0,
	})
	Theme.pad(c, 26)
	return c
end

function LobbyUi.new(parent: Instance, hooks: any)
	local self = setmetatable({ hooks = hooks or {}, settings = {} }, LobbyUi)

	-- ── Persistent chrome ─────────────────────────────────────────────────
	local chrome = Instance.new("Frame")
	chrome.Name = "Chrome"
	chrome.BackgroundTransparency = 1
	chrome.Size = UDim2.fromScale(1, 1)
	chrome.Parent = parent
	self.chrome = chrome

	-- Same inset trap as the touch pad: the header sat behind the Roblox top
	-- bar, so nobody ever saw their own rating in the lobby.
	local top = Theme.panel(chrome, {
		BackgroundTransparency = 0.15,
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(460, 42),
	})
	Theme.label(top, "BLOCK <font color='#E23CBE'>ARENA</font>", {
		Font = Theme.F.display, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(180, 42),
	})
	Theme.pinTop(top, parent, 14)
	self.countLabel = Theme.label(top, "", {
		TextColor3 = Theme.C.muted, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(240, 0), Size = UDim2.fromOffset(200, 42),
	})

	local bar = Instance.new("Frame")
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.new(1, -18, 1, -18)
	bar.Size = UDim2.fromOffset(150, 138)
	bar.Parent = chrome
	Theme.list(bar, 8)
	local help = Theme.button(bar, "HOW TO PLAY", nil, { Size = UDim2.fromOffset(150, 38), LayoutOrder = 1 })
	local settingsBtn = Theme.button(bar, "SETTINGS", nil, { Size = UDim2.fromOffset(150, 38), LayoutOrder = 2 })
	local titlesBtn = Theme.button(bar, "TITLES", nil, { Size = UDim2.fromOffset(150, 38), LayoutOrder = 3 })
	self.bar = bar

	-- Pad prompt. Appears when the player is standing on a station.
	local prompt = Theme.panel(chrome, {
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -26),
		Size = UDim2.fromOffset(320, 62),
		Visible = false,
	})
	self.promptTitle = Theme.label(prompt, "", {
		Font = Theme.F.display, TextSize = 18, TextColor3 = Theme.C.cy,
		Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(320, 22),
	})
	self.promptSub = Theme.label(prompt, "", {
		TextColor3 = Theme.C.muted, TextSize = 13,
		Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(320, 18),
	})
	local dwell = Theme.frame(prompt, {
		BackgroundColor3 = Theme.C.cy, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0, 0, 0, 3),
	})
	self.prompt, self.dwellBar = prompt, dwell

	-- ── Queue ─────────────────────────────────────────────────────────────
	local queue = screen(parent, "Queue")
	local qc = card(queue, 380, 230)
	Theme.eyebrow(qc, "MATCHMAKING", Theme.C.cy, { Size = UDim2.fromOffset(340, 18) })
	self.queueTitle = Theme.label(qc, "SEARCHING", {
		Font = Theme.F.display, TextSize = 34, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 26), Size = UDim2.fromOffset(340, 42),
	})
	self.queueSub = Theme.label(qc, "", {
		TextColor3 = Theme.C.muted, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 72), Size = UDim2.fromOffset(340, 40),
	})
	local qbar = Theme.frame(qc, {
		BackgroundColor3 = Theme.C.panelHi,
		Position = UDim2.fromOffset(0, 122), Size = UDim2.fromOffset(340, 4),
	})
	self.queueBar = Theme.frame(qbar, {
		BackgroundColor3 = Theme.C.cy, Size = UDim2.fromScale(0, 1),
	})
	local cancel = Theme.button(qc, "CANCEL", nil, {
		Position = UDim2.fromOffset(0, 142), Size = UDim2.fromOffset(340, 42),
	})
	self.queue = queue
	self.cancelBtn = cancel

	-- ── Results ───────────────────────────────────────────────────────────
	local results = screen(parent, "Results")
	local rc = card(results, 460, 400)
	self.resultTitle = Theme.label(rc, "", {
		Font = Theme.F.display, TextSize = 52, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(408, 60),
	})
	self.resultSub = Theme.label(rc, "", {
		TextColor3 = Theme.C.muted, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 58), Size = UDim2.fromOffset(408, 22),
	})
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(0, 94)
	grid.Size = UDim2.fromOffset(408, 150)
	grid.Parent = rc
	self.resultStats = {}
	local rows = { "LINES", "ATTACK SENT", "PIECES", "APM", "QUADS", "BEST COMBO" }
	for i, name in ipairs(rows) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.Position = UDim2.fromOffset(col * 204, row * 50)
		cell.Size = UDim2.fromOffset(196, 44)
		cell.Parent = grid
		Theme.label(cell, name, {
			TextColor3 = Theme.C.dim, TextSize = 11, Font = Theme.F.display,
			TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(196, 16),
		})
		self.resultStats[name] = Theme.label(cell, "0", {
			TextColor3 = Theme.C.text, TextSize = 22, Font = Theme.F.display,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(0, 16), Size = UDim2.fromOffset(196, 26),
		})
	end
	local rematch = Theme.button(rc, "REMATCH", Theme.C.cy, {
		Position = UDim2.fromOffset(0, 256), Size = UDim2.fromOffset(196, 46),
	})
	local backBtn = Theme.button(rc, "BACK TO LOBBY", nil, {
		Position = UDim2.fromOffset(212, 256), Size = UDim2.fromOffset(196, 46),
	})
	self.rematchBtn = rematch
	self.backBtn = backBtn
	self.results = results

	-- ── How to play ───────────────────────────────────────────────────────
	local howto = screen(parent, "HowTo")
	local hc = card(howto, 520, 430)
	Theme.label(hc, "HOW TO PLAY", {
		Font = Theme.F.display, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(468, 40),
	})
	local body = table.concat({
		"<b>1.</b>  Clear lines by filling a full row.",
		"<b>2.</b>  Clearing 2 or more sends garbage to your opponent.",
		"<b>3.</b>  Your own clears cancel garbage coming at you.",
		"<b>4.</b>  If a piece cannot spawn, you are knocked out.",
		"",
		"<b>MOVE</b>  ←  →  or  A  D",
		"<b>SOFT DROP</b>  ↓  or  S",
		"<b>HARD DROP</b>  Space",
		"<b>ROTATE</b>  Z  (left)   X or ↑  (right)   V  (180)",
		"<b>HOLD</b>  C  or  Left Shift",
		"<b>FORFEIT</b>  F",
		"",
		"<font color='#9A9EAC'>A four-line clear is a QUAD and sends the most.",
		"Chain quads back to back for a bonus.</font>",
	}, "\n")
	Theme.label(hc, body, {
		TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Theme.C.text,
		Position = UDim2.fromOffset(0, 46), Size = UDim2.fromOffset(468, 290),
	})
	local howClose = Theme.button(hc, "CLOSE", nil, {
		Position = UDim2.fromOffset(0, 342), Size = UDim2.fromOffset(468, 42),
	})
	self.howto = howto

	-- ── Settings ──────────────────────────────────────────────────────────
	local settings = screen(parent, "Settings")
	local sc = card(settings, 460, 400)
	Theme.label(sc, "SETTINGS", {
		Font = Theme.F.display, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(408, 40),
	})
	self.sliders = {}
	local defs = {
		{ key = "das", label = "DAS", suffix = " ms", min = 40, max = 300, get = function() return Tuning.DAS * 1000 end },
		{ key = "arr", label = "ARR", suffix = " ms", min = 0, max = 100, get = function() return Tuning.ARR * 1000 end },
		{ key = "music", label = "MUSIC", suffix = "%", min = 0, max = 100, get = function() return 60 end },
		{ key = "sfx", label = "SFX", suffix = "%", min = 0, max = 100, get = function() return 80 end },
	}
	for i, d in ipairs(defs) do
		local y = 50 + (i - 1) * 52
		Theme.label(sc, d.label, {
			Font = Theme.F.display, TextSize = 13, TextColor3 = Theme.C.muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(120, 18),
		})
		local value = Theme.label(sc, "", {
			Font = Theme.F.display, TextSize = 13, TextColor3 = Theme.C.cy,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(288, y), Size = UDim2.fromOffset(120, 18),
		})
		local track = Theme.frame(sc, {
			BackgroundColor3 = Theme.C.panelHi,
			Position = UDim2.fromOffset(0, y + 24), Size = UDim2.fromOffset(408, 8),
		})
		Theme.corner(track, 4)
		local fill = Theme.frame(track, { BackgroundColor3 = Theme.C.cy, Size = UDim2.fromScale(0.5, 1) })
		Theme.corner(fill, 4)
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency, hit.Text = 1, ""
		hit.Size = UDim2.fromScale(1, 4)
		hit.Position = UDim2.fromScale(0, -1.5)
		hit.Parent = track
		self.sliders[d.key] = { def = d, fill = fill, value = value, track = track, hit = hit }
	end
	local cbRow = Theme.button(sc, "COLOURBLIND PALETTE:  OFF", nil, {
		Position = UDim2.fromOffset(0, 268), Size = UDim2.fromOffset(408, 40),
	})
	self.cbButton = cbRow
	local setClose = Theme.button(sc, "DONE", Theme.C.cy, {
		Position = UDim2.fromOffset(0, 318), Size = UDim2.fromOffset(408, 44),
	})
	self.settingsScreen = settings

	-- ── Wiring ────────────────────────────────────────────────────────────
	help.Activated:Connect(function()
		howto.Visible = true
		self:_select(howClose)
	end)
	howClose.Activated:Connect(function()
		howto.Visible = false
		self:_select(nil)
	end)
	settingsBtn.Activated:Connect(function()
		self:_refreshSliders()
		settings.Visible = true
	end)
	setClose.Activated:Connect(function()
		settings.Visible = false
		if self.hooks.onSaveSettings then self.hooks.onSaveSettings(self.settings) end
	end)
	cancel.Activated:Connect(function()
		if self.hooks.onCancelQueue then self.hooks.onCancelQueue() end
	end)
	rematch.Activated:Connect(function()
		if self.hooks.onRematch then self.hooks.onRematch() end
	end)
	backBtn.Activated:Connect(function()
		results.Visible = false
		if self.hooks.onBackToLobby then self.hooks.onBackToLobby() end
	end)
	cbRow.Activated:Connect(function()
		self.settings.colourblind = not self.settings.colourblind
		cbRow.Text = "COLOURBLIND PALETTE:  " .. (self.settings.colourblind and "ON" or "OFF")
		if self.hooks.onPaletteChanged then self.hooks.onPaletteChanged(self.settings.colourblind) end
	end)

	for key, s in pairs(self.sliders) do
		local dragging = false
		local function setFromX(x: number)
			local abs = s.track.AbsolutePosition.X
			local width = math.max(s.track.AbsoluteSize.X, 1)
			local frac = math.clamp((x - abs) / width, 0, 1)
			local v = s.def.min + frac * (s.def.max - s.def.min)
			self.settings[key] = v
			s.fill.Size = UDim2.fromScale(frac, 1)
			s.value.Text = string.format("%d%s", math.floor(v + 0.5), s.def.suffix)
			if self.hooks.onSettingChanged then self.hooks.onSettingChanged(key, v) end
		end
		s.hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				setFromX(input.Position.X)
			end
		end)
		s.hit.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				setFromX(input.Position.X)
			end
		end)
		s.hit.InputEnded:Connect(function() dragging = false end)
	end

	-- ── Titles ────────────────────────────────────────────────────────────
	local titles = screen(parent, "Titles")
	local tc = card(titles, 520, 470)
	Theme.label(tc, "TITLES", {
		Font = Theme.F.display, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(468, 40),
	})
	Theme.label(tc, "Cosmetic only. Nothing here changes how the game plays.", {
		TextColor3 = Theme.C.muted, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 34), Size = UDim2.fromOffset(468, 18),
	})
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 60)
	list.Size = UDim2.fromOffset(468, 340)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.Parent = tc
	Theme.list(list, 6)
	local titleClose = Theme.button(tc, "CLOSE", nil, {
		Position = UDim2.fromOffset(0, 408), Size = UDim2.fromOffset(468, 42),
	})
	self.titles = titles
	self.titleRows = {}

	-- One row per catalog entry, built once. Repopulating rewrites text and
	-- colour rather than rebuilding instances, so opening this panel does not
	-- churn the GUI.
	for i, title in ipairs(TitleData.ordered()) do
		local row = Theme.panel(list, {
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 0, 52),
			LayoutOrder = i,
		})
		local name = Theme.label(row, title.name, {
			Font = Theme.F.display, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(250, 20),
		})
		local sub = Theme.label(row, title.description, {
			TextColor3 = Theme.C.muted, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 27), Size = UDim2.fromOffset(300, 16),
		})
		local state = Theme.button(row, "", nil, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(120, 32),
		})
		state.Activated:Connect(function()
			if self.hooks.onEquipTitle then self.hooks.onEquipTitle(title.id) end
		end)
		self.titleRows[title.id] = { row = row, name = name, sub = sub, state = state, def = title }
	end

	titlesBtn.Activated:Connect(function()
		titles.Visible = true
		self:_select(titleClose)
	end)
	titleClose.Activated:Connect(function()
		titles.Visible = false
		self:_select(nil)
	end)

	self:_refreshSliders()

	-- A player who puts the mouse down and picks up a pad mid-screen should get
	-- a selection without having to close and reopen anything.
	UserInputService.LastInputTypeChanged:Connect(function(kind)
		if kind == Enum.UserInputType.Gamepad1 and self.selected then
			GuiService.SelectedObject = self.selected
		end
	end)
	return self
end

function LobbyUi:_refreshSliders()
	for key, s in pairs(self.sliders) do
		local v = self.settings[key] or s.def.get()
		self.settings[key] = v
		local frac = (v - s.def.min) / (s.def.max - s.def.min)
		s.fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
		s.value.Text = string.format("%d%s", math.floor(v + 0.5), s.def.suffix)
	end
end

function LobbyUi:applyProfile(profile: any)
	if not profile then return end
	for _, key in ipairs({ "das", "arr", "music", "sfx" }) do
		if profile[key] then self.settings[key] = profile[key] end
	end
	if profile.colourblind ~= nil then
		self.settings.colourblind = profile.colourblind
		self.cbButton.Text = "COLOURBLIND PALETTE:  " .. (profile.colourblind and "ON" or "OFF")
	end
	if profile.rating then
		self.rating = profile.rating
		self:setPlayerCount(self.playerCount or 1)
	end
	self:_refreshSliders()
end

local RARITY_COLOUR = {
	COMMON = Theme.C.muted,
	RARE = Theme.C.cy,
	EPIC = Theme.C.violet,
	LEGENDARY = Theme.C.gold,
	SECRET = Theme.C.mg,
}

-- Redraws the panel from the profile the server last sent. Ownership is read,
-- never decided: a locked row shows progress the server already reported.
function LobbyUi:applyTitles(owned: any, equipped: string?, profile: any)
	self.equippedTitle = equipped
	-- The header is built from this, and applyProfile has usually already run
	-- for this push -- so without redrawing it here it shows the title from the
	-- push before, which looks exactly like an equip that did not take.
	self:setPlayerCount(self.playerCount or 1)
	for id, row in pairs(self.titleRows) do
		local isOwned = type(owned) == "table" and owned[id] == true
		local colour = RARITY_COLOUR[row.def.rarity] or Theme.C.text
		row.name.Text = row.def.name
		row.name.TextColor3 = isOwned and colour or Theme.C.dim
		row.row.BackgroundTransparency = isOwned and 0.25 or 0.55

		if id == equipped then
			row.state.Text = "EQUIPPED"
			row.state.BackgroundColor3 = colour
			row.state.TextColor3 = Theme.C.bg
			row.sub.Text = row.def.description
		elseif isOwned then
			row.state.Text = "EQUIP"
			row.state.BackgroundColor3 = Theme.C.panelHi
			row.state.TextColor3 = Theme.C.text
			row.sub.Text = row.def.description
		else
			row.state.Text = "LOCKED"
			row.state.BackgroundColor3 = Theme.C.panelHi
			row.state.TextColor3 = Theme.C.dim
			-- Progress where a number helps. The secret one deliberately gets
			-- none: a counter would give away that there is something to count.
			local progress = profile and TitleData.progress(row.def, profile)
			row.sub.Text = progress and (row.def.description .. "   ·   " .. progress)
				or row.def.description
		end
	end
end

function LobbyUi:setPlayerCount(n: number)
	self.playerCount = n
	local title = self.equippedTitle and TitleData.get(self.equippedTitle)
	self.countLabel.Text = string.format("%d IN LOBBY  ·  %s%s%s", n,
		Players.LocalPlayer.DisplayName,
		title and ("  ·  " .. title.name) or "",
		self.rating and string.format("  ·  %d ELO", self.rating) or "")
end

function LobbyUi:setPrompt(title: string?, sub: string?, progress: number?)
	if not title then
		self.prompt.Visible = false
		return
	end
	self.prompt.Visible = true
	self.promptTitle.Text = title
	self.promptSub.Text = sub or ""
	self.dwellBar.Size = UDim2.new(progress or 0, 0, 0, 3)
end

-- A small, brief thing in the corner. The reward for a hidden puzzle should
-- feel found rather than sold, so this is deliberately not a modal, not
-- centred, and not something the player has to dismiss.
function LobbyUi:toast(title: string, sub: string?, colour: Color3?)
	if not self.toastCard then
		local card_ = Theme.panel(self.chrome, {
			BackgroundTransparency = 0.05,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 18, 1, -18),
			Size = UDim2.fromOffset(300, 62),
			Visible = false,
		})
		self.toastTitle = Theme.label(card_, "", {
			Font = Theme.F.display, TextSize = 18, TextColor3 = Theme.C.violet,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(268, 22),
		})
		self.toastSub = Theme.label(card_, "", {
			TextColor3 = Theme.C.muted, TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(16, 30), Size = UDim2.fromOffset(268, 18),
		})
		self.toastCard = card_
	end
	self.toastTitle.Text = title
	self.toastTitle.TextColor3 = colour or Theme.C.violet
	self.toastSub.Text = sub or ""
	self.toastCard.Visible = true
	self.toastSeq = (self.toastSeq or 0) + 1
	local mine = self.toastSeq
	task.delay(6, function()
		if self.toastSeq == mine and self.toastCard then
			self.toastCard.Visible = false
		end
	end)
end

-- Gamepad reachability.
--
-- Every screen here is made of TextButtons, which Roblox will happily navigate
-- between with a stick -- but only once something is selected to navigate FROM.
-- Nothing ever selected anything, so a player on a pad could play the board and
-- then not be able to press BACK TO LOBBY. This picks the obvious button when a
-- screen opens and lets go when it closes.
--
-- Only while a gamepad is actually the input in use: setting SelectedObject for
-- a mouse player draws a selection box around a button they did not ask to
-- highlight.
function LobbyUi:_select(button: Instance?)
	self.selected = button
	if not button then
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.chrome.Parent) then
			GuiService.SelectedObject = nil
		end
		return
	end
	if UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
		GuiService.SelectedObject = button
	end
end

-- The moment between the lobby and the arena.
--
-- Deliberately short and screen-based: two lines over a fade, no camera moves,
-- nothing to sit through. A player who queues ten times an evening should never
-- learn to dread this.
function LobbyUi:transition(title: string?, sub: string?, colour: Color3?)
	if not self.transitionCard then
		local screenFade = Instance.new("Frame")
		screenFade.Name = "Transition"
		screenFade.BackgroundColor3 = Theme.C.bg
		screenFade.BackgroundTransparency = 1
		screenFade.BorderSizePixel = 0
		screenFade.Size = UDim2.fromScale(1, 1)
		screenFade.ZIndex = 40
		screenFade.Visible = false
		screenFade.Parent = self.chrome.Parent
		self.transitionTitle = Theme.label(screenFade, "", {
			Font = Theme.F.display, TextSize = 46, TextColor3 = Theme.C.cy,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(700, 56),
			ZIndex = 41,
		})
		self.transitionSub = Theme.label(screenFade, "", {
			TextColor3 = Theme.C.muted, TextSize = 16,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(700, 24),
			ZIndex = 41,
		})
		self.transitionCard = screenFade
	end

	self.transitionSeq = (self.transitionSeq or 0) + 1
	local mine = self.transitionSeq
	if not title then
		-- Fade out rather than snapping: the arena is already there behind it.
		TweenService:Create(self.transitionCard, TweenInfo.new(0.35), {
			BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.transitionTitle, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		TweenService:Create(self.transitionSub, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		task.delay(0.4, function()
			if self.transitionSeq == mine and self.transitionCard then
				self.transitionCard.Visible = false
			end
		end)
		return
	end

	self.transitionTitle.Text = title
	self.transitionTitle.TextColor3 = colour or Theme.C.cy
	self.transitionTitle.TextTransparency = 0
	self.transitionSub.Text = sub or ""
	self.transitionSub.TextTransparency = 0
	self.transitionCard.BackgroundTransparency = 0.15
	self.transitionCard.Visible = true
end

function LobbyUi:showQueue(on: boolean)
	self.queue.Visible = on
	self.chrome.Visible = not on
	self:_select(on and self.cancelBtn or nil)
end

function LobbyUi:setQueueInfo(elapsed: number, botIn: number?, note: string?, title: string?)
	self.queueTitle.Text = title or "SEARCHING"
	self.queueSub.Text = note
		or (botIn and botIn > 0
			and string.format("No opponent yet. Matching you with a bot in %ds.", math.ceil(botIn))
			or string.format("Looking for an opponent…  %ds", math.floor(elapsed)))
	-- With no bot fallback there is nothing to count down to, so the bar just
	-- shows the queue is alive rather than pretending to have a deadline.
	local frac = botIn and (1 - math.clamp(botIn / Tuning.BOT_AFTER, 0, 1)) or ((elapsed % 2) / 2)
	self.queueBar.Size = UDim2.fromScale(frac, 1)
end

function LobbyUi:showResults(payload: any, canRematch: boolean)
	local win = payload.outcome == Enums.Result.Win
	if payload.reason == "sprint" then
		self.resultTitle.Text = "SPRINT CLEAR"
		self.resultTitle.TextColor3 = Theme.C.cy
		self.resultSub.Text = payload.sprintTime
			and string.format("40 lines in %.2f seconds.", payload.sprintTime)
			or "40 lines cleared."
	elseif payload.reason == "blitz" then
		self.resultTitle.Text = payload.topout and "BLITZ \u{00B7} TOP OUT" or "BLITZ COMPLETE"
		self.resultTitle.TextColor3 = payload.record and Theme.C.gold or Theme.C.mg
		self.resultSub.Text = ("SCORE %s   \u{00B7}   BEST %s%s"):format(
			BlitzScoring.format(payload.score or 0),
			BlitzScoring.format(payload.best or 0),
			payload.record and "   \u{00B7}   NEW BEST" or "")
	elseif payload.reason == "practice" then
		self.resultTitle.Text = "PRACTICE OVER"
		self.resultTitle.TextColor3 = Theme.C.violet
		self.resultSub.Text = "No stakes. Step back on the pad to go again."
	else
		self.resultTitle.Text = win and "YOU WIN"
			or (payload.outcome == Enums.Result.Draw and "DRAW" or "DEFEAT")
		self.resultTitle.TextColor3 = win and Theme.C.cy or Theme.C.mg
		local reasons = {
			[Enums.Result.Left] = "Your opponent left the match.",
			[Enums.Result.Forfeit] = "Forfeited.",
			[Enums.Result.Timeout] = "Time limit reached — most garbage sent wins.",
		}
		self.resultSub.Text = reasons[payload.reason]
			or (win and "Opponent topped out." or "You topped out.")
	end
	-- Ranked only. A rating that moved without being shown is a rating players
	-- assume is broken, and the disconnect case is exactly where they look.
	if payload.title then
		self.resultSub.Text = ("%s   ·   %s"):format(self.resultSub.Text, payload.title)
	end
	if payload.elo then
		self.resultSub.Text = ("%s   ·   %d ELO (%+d)"):format(
			self.resultSub.Text, payload.elo.after, payload.elo.delta)
	end
	if payload.rating then
		self.rating = payload.rating
		self:setPlayerCount(self.playerCount or 1)
	end
	local s = payload.stats or {}
	self.resultStats["LINES"].Text = tostring(s.lines or 0)
	self.resultStats["ATTACK SENT"].Text = tostring(s.sent or 0)
	self.resultStats["PIECES"].Text = tostring(s.pieces or 0)
	self.resultStats["APM"].Text = string.format("%.0f", s.apm or 0)
	self.resultStats["QUADS"].Text = tostring(s.quads or 0)
	self.resultStats["BEST COMBO"].Text = tostring(s.bestCombo or 0)
	self.rematchBtn.Visible = canRematch
	self.results.Visible = true
	self:_select(canRematch and self.rematchBtn or self.backBtn)
	self.chrome.Visible = false
end

function LobbyUi:hideResults()
	self.results.Visible = false
	self:_select(nil)
	self.chrome.Visible = true
end

function LobbyUi:setChromeVisible(on: boolean)
	self.chrome.Visible = on
end

return LobbyUi
