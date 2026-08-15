-- Client entry point: owns the screen, the state machine and the match loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Tuning = require(Shared.Tuning)
local Enums = require(Shared.Enums)
local Attack = require(Shared.Attack)
local Bag = require(Shared.Bag)
local Net = require(Shared.Net)
local Remotes = require(Shared.Remotes)

local Sim = require(script.Parent.Sim)
local Hud = require(script.Parent.Hud)
local LobbyUi = require(script.Parent.LobbyUi)
local InputController = require(script.Parent.InputController)
local PadController = require(script.Parent.PadController)
local TouchControls = require(script.Parent.TouchControls)
local SoundKit = require(script.Parent.Sound)
local Fx = require(script.Parent.Fx)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The ArenaGui placeholder was made by hand before any of this existed.
local stale = playerGui:FindFirstChild("ArenaGui")
if stale then stale:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "BlockArena"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 20
gui.Parent = playerGui
Theme.autoScale(gui)

-- A dark backdrop behind the match rig: the 3D hall is busy and the board has
-- to be the only thing worth looking at while you are playing.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.BackgroundColor3 = Theme.C.bg
backdrop.BackgroundTransparency = 0.12
backdrop.BorderSizePixel = 0
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Visible = false
backdrop.Parent = gui

SoundKit.init()

local state = Enums.State.Idle
local sim, input, fx = nil, nil, nil
local matchInfo = nil
local queueStart, queueMode = 0, nil
local lastSnapshot, matchStart = 0, 0
local bestCombo = 0
local settings = {}

local hud = Hud.new(gui, {})
local ui
local touch = TouchControls.new(gui, nil)
-- The keyboard hint is wrong on a device with no keyboard.
if TouchControls.shouldShow() then
	hud.hint.Text = "TAP AND HOLD TO MOVE  ·  DROP TO PLACE"
end

local function setState(next_: string)
	state = next_
	local playing = (state == Enums.State.Playing or state == Enums.State.Countdown)
	hud:show(playing)
	backdrop.Visible = playing
	touch:setVisible(playing)
	ui:showQueue(state == Enums.State.Queued)
	if state == Enums.State.Idle then
		ui:setChromeVisible(true)
	end
end

local function teardownMatch()
	if input then input:disable(); input = nil end
	touch:setInput(nil)
	if fx then fx:destroy(); fx = nil end
	sim = nil
	matchInfo = nil
	hud:reset()
end

-- ── Starting a board ──────────────────────────────────────────────────────

-- `info` is assigned here rather than by the caller: teardownMatch() clears
-- matchInfo, so setting it before calling this silently wiped it and every lock
-- was then dropped instead of being sent to the server.
local function startSim(seed: number, opts: any, info: any?)
	teardownMatch()
	matchInfo = info
	sim = Sim.new(seed, opts)
	fx = Fx.new(hud, gui)
	matchStart = os.clock()
	bestCombo = 0

	sim.onLock = function(payload)
		if payload.info then
			fx:onClear(payload.info)
			if payload.info.combo > bestCombo then bestCombo = payload.info.combo end
			if payload.info.lines >= 4 then
				SoundKit.play("quad")
			elseif payload.info.lines > 0 then
				SoundKit.play("clear")
			else
				SoundKit.play("lock")
			end
		end
		if matchInfo and matchInfo.networked then
			Remotes.Lock:FireServer({
				index = payload.index,
				tick = payload.tick,
				kind = payload.kind,
				rot = payload.rot,
				x = payload.x,
				y = payload.y,
				send = payload.send,
				lines = payload.info and payload.info.lines or 0,
			})
		end
	end

	sim.onEvent = function(e)
		if e.kind == "garbage" then
			fx:onGarbage(e.data.rows)
			SoundKit.play("garbage")
		elseif e.kind == "topout" then
			SoundKit.play("ko")
			fx:onKo(false)
			hud:setOverlay("KO", Theme.C.red)
			if matchInfo and matchInfo.networked then
				Remotes.Lock:FireServer({ topout = true, reason = e.data.reason })
			elseif matchInfo and matchInfo.practice then
				Remotes.Practice:FireServer({
					finished = true,
					mode = matchInfo.mode,
					stats = sim.board.stats,
					time = os.clock() - matchStart,
				})
				task.delay(1.6, function()
					if state == Enums.State.Playing then
						ui:showResults({
							outcome = Enums.Result.Draw,
							reason = "practice",
							stats = {
								lines = sim.board.stats.lines, sent = sim.board.stats.sent,
								pieces = sim.board.stats.pieces, quads = sim.board.stats.quads,
								apm = 0, bestCombo = bestCombo,
							},
						}, false)
						setState(Enums.State.Results)
					end
				end)
			end
		end
	end

	input = InputController.new(sim, {
		onForfeit = function()
			if matchInfo and matchInfo.networked then
				Remotes.Forfeit:FireServer()
			else
				teardownMatch()
				setState(Enums.State.Idle)
			end
		end,
	})
	input:enable()
	touch:setInput(input)
	hud:setOpponentVisible(matchInfo ~= nil and matchInfo.networked == true)
end

-- ── UI hooks ──────────────────────────────────────────────────────────────

ui = LobbyUi.new(gui, {
	onCancelQueue = function()
		Remotes.QueueCancel:FireServer()
		setState(Enums.State.Idle)
	end,
	onRematch = function()
		ui:hideResults()
		if queueMode then
			Remotes.QueueRequest:FireServer({ mode = queueMode })
			queueStart = os.clock()
			setState(Enums.State.Queued)
		end
	end,
	onBackToLobby = function()
		teardownMatch()
		setState(Enums.State.Idle)
	end,
	onSettingChanged = function(key, value)
		settings[key] = value
		if key == "das" then Tuning.DAS = value / 1000 end
		if key == "arr" then Tuning.ARR = value / 1000 end
		if key == "music" then SoundKit.setVolume("music", value / 100) end
		if key == "sfx" then SoundKit.setVolume("sfx", value / 100) end
	end,
	onPaletteChanged = function(on)
		settings.colourblind = on
		hud.renderer:setPalette(on)
		hud.oppRenderer:setPalette(on)
	end,
	onSaveSettings = function(s)
		Remotes.SaveSettings:FireServer(s)
	end,
})

local pads = PadController.new(function(mode)
	if state ~= Enums.State.Idle then return end
	if mode == Enums.Mode.Practice then
		Remotes.Practice:FireServer({ mode = Enums.Mode.Practice })
	elseif mode == Enums.Mode.Emote then
		-- Nothing to queue; the lounge pad is decorative until Phase 7 emotes.
	else
		queueMode = mode
		queueStart = os.clock()
		Remotes.QueueRequest:FireServer({ mode = mode })
		setState(Enums.State.Queued)
		SoundKit.play("queue")
	end
end)

-- ── Server messages ───────────────────────────────────────────────────────

Remotes.MatchUpdate.OnClientEvent:Connect(function(msg)
	if msg.state == Enums.State.Countdown then
		startSim(msg.seed, { gravity = msg.gravity }, {
			networked = true,
			opponent = msg.opponent,
			isBot = msg.isBot,
			mode = msg.mode,
		})
		hud:setOpponent(msg.opponent or "OPPONENT")
		hud:setOpponentStatus(msg.isBot and "BOT" or "")
		setState(Enums.State.Countdown)
		task.spawn(function()
			for i = Tuning.COUNTDOWN, 1, -1 do
				if state ~= Enums.State.Countdown then return end
				hud:setOverlay(tostring(i))
				SoundKit.play("countdown")
				task.wait(1)
			end
			if state ~= Enums.State.Countdown then return end
			hud:setOverlay("GO")
			SoundKit.play("go")
			SoundKit.setMusic("musicMatch")
			setState(Enums.State.Playing)
			if input then input:arm() end
			matchStart = os.clock()
			task.delay(0.5, function() hud:setOverlay(nil) end)
		end)
	elseif msg.state == Enums.State.Queued then
		setState(Enums.State.Queued)
	elseif msg.state == Enums.State.Idle then
		teardownMatch()
		setState(Enums.State.Idle)
	end
end)

Remotes.Garbage.OnClientEvent:Connect(function(msg)
	if sim then
		sim.board:queueGarbage(msg.rows, msg.gapCol)
	end
end)

Remotes.Snapshot.OnClientEvent:Connect(function(packed, meta)
	if state ~= Enums.State.Playing and state ~= Enums.State.Countdown then return end
	local cells = Net.unpackBoard(packed, Tuning.WIDTH * Tuning.VISIBLE)
	hud:renderOpponent(cells)
	if meta then
		hud:setOpponentStatus(("%d incoming"):format(meta.incoming or 0))
	end
end)

-- The server disagreed with our board. Snap to its version rather than kick:
-- treating every mismatch as cheating turns our own desync bugs into bans.
--
-- The bag and the lock index have to be adopted too, not just the cells. A
-- drifted piece sequence means every following placement is "not the piece in
-- play", and a stale index means every following lock is "out of order" — so a
-- resync that only fixed cells would leave the player permanently rejected.
Remotes.Resync.OnClientEvent:Connect(function(msg)
	if not sim then return end
	local b = sim.board
	for i = 1, #msg.cells do
		b.cells[i] = msg.cells[i]
	end
	b.piece = msg.piece
	b.hold, b.holdUsed = msg.hold, msg.holdUsed == true
	if msg.bag then b.bag = Bag.load(msg.bag) end
	b.combo, b.b2b = msg.combo or 0, msg.b2b or false
	b.gravityAcc, b.lockTimer, b.lockResets, b.grounded = 0, 0, 0, false
	if msg.index then sim.lockIndex = msg.index end
	if fx then fx:flashScreen(Theme.C.gold, 0.25) end
end)

Remotes.Result.OnClientEvent:Connect(function(payload)
	if input then input:disable() end
	if fx then fx:onKo(payload.outcome == Enums.Result.Win) end
	SoundKit.setMusic("musicLobby")
	local stats = payload.stats or {}
	local elapsed = math.max(os.clock() - matchStart, 1)
	stats.apm = (stats.sent or 0) / elapsed * 60
	stats.bestCombo = bestCombo
	ui:showResults(payload, payload.canRematch ~= false)
	setState(Enums.State.Results)
end)

Remotes.Practice.OnClientEvent:Connect(function(msg)
	if msg.seed then
		startSim(msg.seed, { gravity = msg.gravity }, { practice = true, mode = msg.mode })
		hud:setOpponentVisible(false)
		setState(Enums.State.Playing)
		hud:setOverlay("GO")
		if input then input:arm() end
		matchStart = os.clock()
		task.delay(0.5, function() hud:setOverlay(nil) end)
	end
end)

Remotes.Profile.OnClientEvent:Connect(function(profile)
	ui:applyProfile(profile)
	if profile.das then Tuning.DAS = profile.das / 1000 end
	if profile.arr then Tuning.ARR = profile.arr / 1000 end
	if profile.colourblind then
		hud.renderer:setPalette(true)
		hud.oppRenderer:setPalette(true)
	end
end)

-- ── Frame loop ────────────────────────────────────────────────────────────

local function refreshCount()
	ui:setPlayerCount(#Players:GetPlayers())
end
Players.PlayerAdded:Connect(refreshCount)
Players.PlayerRemoving:Connect(refreshCount)
refreshCount()
SoundKit.setMusic("musicLobby")

RunService.RenderStepped:Connect(function(dt)
	if state == Enums.State.Idle then
		local title, sub, progress = pads:update(dt)
		ui:setPrompt(title, sub, progress)
	else
		ui:setPrompt(nil)
	end

	if state == Enums.State.Queued then
		local elapsed = os.clock() - queueStart
		local botIn = (queueMode == Enums.Mode.Quick) and math.max(0, Tuning.BOT_AFTER - elapsed) or nil
		ui:setQueueInfo(elapsed, botIn)
	end

	if not sim then return end

	if state == Enums.State.Playing then
		input:update(dt)
		sim:update(dt)
	end

	local b = sim.board
	hud:render(b)
	hud:setIncoming(Attack.pending(b.incoming))

	local elapsed = math.max(os.clock() - matchStart, 0.001)
	hud:setStats(b.stats.sent / elapsed * 60, b.stats.pieces / elapsed, b.stats.sent, b.stats.lines)

	-- Our own board goes to the opponent on a fixed budget, not every frame.
	if matchInfo and matchInfo.networked and state == Enums.State.Playing then
		local now = os.clock()
		if now - lastSnapshot >= 1 / Tuning.SNAPSHOT_HZ then
			lastSnapshot = now
			Remotes.Lock:FireServer({
				snapshot = Net.packBoard(b:snapshot()),
				incoming = Attack.pending(b.incoming),
			})
		end
	end
end)

pcall(function()
	StarterGui:SetCore("ResetButtonCallback", false)
end)
