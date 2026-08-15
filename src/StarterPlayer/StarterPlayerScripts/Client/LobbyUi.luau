-- Everything on screen that is not the match board.
--
-- The original plan had a fullscreen PLAY menu. The lobby now has physical
-- matchmaking pads, so a menu that duplicates them would be two front doors to
-- the same room: this handles the states the world cannot show — searching,
-- results, settings, help — and leaves "start a match" to the pads.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)

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
	self.countLabel = Theme.label(top, "", {
		TextColor3 = Theme.C.muted, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(240, 0), Size = UDim2.fromOffset(200, 42),
	})

	local bar = Instance.new("Frame")
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.new(1, -18, 1, -18)
	bar.Size = UDim2.fromOffset(150, 92)
	bar.Parent = chrome
	Theme.list(bar, 8)
	local help = Theme.button(bar, "HOW TO PLAY", nil, { Size = UDim2.fromOffset(150, 38), LayoutOrder = 1 })
	local settingsBtn = Theme.button(bar, "SETTINGS", nil, { Size = UDim2.fromOffset(150, 38), LayoutOrder = 2 })
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
	help.Activated:Connect(function() howto.Visible = true end)
	howClose.Activated:Connect(function() howto.Visible = false end)
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

	self:_refreshSliders()
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

function LobbyUi:setPlayerCount(n: number)
	self.playerCount = n
	self.countLabel.Text = string.format("%d IN LOBBY  ·  %s%s", n, Players.LocalPlayer.DisplayName,
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

function LobbyUi:showQueue(on: boolean)
	self.queue.Visible = on
	self.chrome.Visible = not on
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
	if payload.rating then
		self.rating = payload.rating
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
	self.chrome.Visible = false
end

function LobbyUi:hideResults()
	self.results.Visible = false
	self.chrome.Visible = true
end

function LobbyUi:setChromeVisible(on: boolean)
	self.chrome.Visible = on
end

return LobbyUi
