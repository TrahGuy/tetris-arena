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
local SkinData = require(Shared.SkinData)
local TitleData = require(Shared.TitleData)

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

-- The server vets sprint records against this too, so it lives in Tuning.
local SPRINT_GOAL = Tuning.SPRINT_GOAL

local state = Enums.State.Idle
local sim, input, fx = nil, nil, nil
local matchInfo = nil
local queueStart, queueMode = 0, nil
local lastSnapshot, matchStart = 0, 0
local bestCombo = 0
local settings = {}
-- Display state only. The server decides both of these; this is the last thing
-- it told us, used to draw the board and to label the museum.
local ownedSkins, equippedSkin = { [SkinData.DEFAULT_ID] = true }, SkinData.DEFAULT_ID
-- nil until the first profile arrives, so a player who solved the nook in an
-- earlier session is not congratulated again the moment they log in.
local secretSolved = nil
local seenProfile = false
-- Everything about a Blitz run that the client is allowed to know: the deadline
-- the server set, and the score the server last told us. Neither is computed
-- here.
local blitz = nil
-- Display state. The server owns both; this is the last thing it said.
local ownedTitles, equippedTitle = { [TitleData.DEFAULT_ID] = true }, TitleData.DEFAULT_ID
local bestBlitz = 0

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
			elseif payload.info.tspin and payload.info.lines > 0 then
				-- No dedicated spin cue exists, and every id in Sound.luau comes
				-- from a source Roblox licenses. This is the quad hit pitched
				-- up: the same family, audibly not a quad.
				SoundKit.play("quad", 1.3)
			elseif payload.info.lines > 0 then
				SoundKit.play("clear")
			else
				SoundKit.play("lock")
			end
		end
		if matchInfo and matchInfo.blitz then
			-- A solo run is addressed by session. The payload carries where the
			-- piece went and the rotation that put it there; the score, the lines
			-- and the clear are all the server's to work out.
			Remotes.Lock:FireServer({
				sessionId = matchInfo.sessionId,
				index = payload.index,
				tick = payload.tick,
				kind = payload.kind,
				rot = payload.rot,
				x = payload.x,
				y = payload.y,
				spin = payload.spin,
			})
		elseif matchInfo and matchInfo.networked then
			Remotes.Lock:FireServer({
				-- Every competitive message names its match. The server drops
				-- anything addressed to a match it is no longer running.
				matchId = matchInfo.matchId,
				index = payload.index,
				tick = payload.tick,
				kind = payload.kind,
				rot = payload.rot,
				x = payload.x,
				y = payload.y,
				-- The rotation that placed the piece, which the server replays
				-- on its own board to reach its own T-spin verdict. `send` and
				-- `lines` used to ride along here; they were never read, and a
				-- competitive number travelling from client to server is a
				-- standing invitation to start trusting it.
				spin = payload.spin,
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
			if matchInfo and matchInfo.blitz then
				-- Ends the run early. The score already earned is the server's and
				-- it keeps it.
				Remotes.Lock:FireServer({ sessionId = matchInfo.sessionId, topout = true })
			elseif matchInfo and matchInfo.networked then
				Remotes.Lock:FireServer({
					matchId = matchInfo.matchId, topout = true, reason = e.data.reason,
				})
			elseif matchInfo and matchInfo.practice then
				Remotes.Practice:FireServer({
					finished = true,
					sessionId = matchInfo.sessionId,
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
				Remotes.Forfeit:FireServer({ matchId = matchInfo.matchId })
			elseif matchInfo and matchInfo.blitz then
				-- Quitting has to reach the server, or the run keeps counting
				-- down without anybody playing it and is recorded as a finished
				-- one when the deadline arrives -- which is exactly the score
				-- that is not supposed to count.
				Remotes.Practice:FireServer({ sessionId = matchInfo.sessionId, abandon = true })
				teardownMatch()
				setState(Enums.State.Idle)
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
		hud:setColourblind(on)
	end,
	onSaveSettings = function(s)
		Remotes.SaveSettings:FireServer(s)
	end,
	onEquipTitle = function(titleId)
		-- A request. The server checks ownership and whether we are mid-match.
		Remotes.EquipTitle:FireServer({ titleId = titleId })
		SoundKit.play("uiPress")
	end,
})

local pads = PadController.new(function(mode, pad)
	if state ~= Enums.State.Idle then return end
	if mode == "skin" then
		-- A request. If it is not owned the server says no, and the prompt has
		-- already said LOCKED, so nothing is lost by asking.
		if pad and pad.skinId then
			Remotes.EquipSkin:FireServer({ skinId = pad.skinId })
			SoundKit.play("uiPress")
		end
	elseif mode == Enums.Mode.Practice then
		-- The practice pad runs a sprint, so the result can be recorded against
		-- a best time instead of vanishing.
		Remotes.Practice:FireServer({ mode = Enums.Mode.Sprint })
	elseif mode == Enums.Mode.Blitz then
		-- Solo, so it asks for a session rather than joining a queue. There is
		-- nobody to wait for.
		Remotes.Practice:FireServer({ mode = Enums.Mode.Blitz })
		SoundKit.play("queue")
	elseif mode == Enums.Mode.Emote then
		-- Nothing to queue; the lounge pad is decorative until Phase 7 emotes.
	else
		queueMode = mode
		queueStart = os.clock()
		Remotes.QueueRequest:FireServer({ mode = mode })
		setState(Enums.State.Queued)
		SoundKit.play("queue")
	end
end, function(pad)
	-- The museum plaque already says what the exhibit is; the prompt says what
	-- you can do about it.
	if pad.mode ~= "skin" or not pad.skinId then return nil end
	local skin = SkinData.get(pad.skinId)
	if not skin then return nil end
	if equippedSkin == pad.skinId then
		return skin.name, "EQUIPPED  ·  " .. skin.description
	elseif ownedSkins[pad.skinId] then
		return skin.name, "OWNED  ·  stand here to equip"
	end
	return skin.name, "LOCKED  ·  " .. skin.description
end)

-- Already-solved players get told so where they would otherwise get a prompt
-- that can no longer pay anything. Written on the client only: a local change to
-- a replicated instance never leaves this machine, so it relabels the nook for
-- this player without touching anyone else's.
local function markNookSolved()
	local lobby = workspace:FindFirstChild("Lobby")
	local secret = lobby and lobby:FindFirstChild("Secret")
	if not secret then return end
	for _, d in ipairs(secret:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d.ActionText = "Solved"
			d.ObjectText = "Secret"
		end
	end
end

-- ── Server messages ───────────────────────────────────────────────────────

Remotes.MatchUpdate.OnClientEvent:Connect(function(msg)
	if msg.state == Enums.State.Countdown then
		startSim(msg.seed, { gravity = msg.gravity }, {
			networked = true,
			matchId = msg.matchId,
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

-- Anything that touches the board has to be for the match on screen. A garbage
-- line or a resync from the match before this one would land on a board that
-- never earned it.
local function forThisMatch(msg: any): boolean
	return matchInfo ~= nil and matchInfo.networked == true
		and type(msg) == "table" and msg.matchId == matchInfo.matchId
end

Remotes.Garbage.OnClientEvent:Connect(function(msg)
	if sim and forThisMatch(msg) then
		sim.board:queueGarbage(msg.rows, msg.gapCol)
	end
end)

Remotes.Snapshot.OnClientEvent:Connect(function(packed, meta)
	if state ~= Enums.State.Playing and state ~= Enums.State.Countdown then return end
	if not forThisMatch(meta) then return end
	local cells = Net.unpackBoard(packed, Tuning.WIDTH * Tuning.VISIBLE)
	hud:renderOpponent(cells)
	hud:setOpponentStatus(("%d incoming"):format(math.floor(tonumber(meta.incoming) or 0)))
end)

-- The server disagreed with our board. Snap to its version rather than kick:
-- treating every mismatch as cheating turns our own desync bugs into bans.
--
-- The bag and the lock index have to be adopted too, not just the cells. A
-- drifted piece sequence means every following placement is "not the piece in
-- play", and a stale index means every following lock is "out of order" — so a
-- resync that only fixed cells would leave the player permanently rejected.
Remotes.Resync.OnClientEvent:Connect(function(msg)
	if not sim or not forThisMatch(msg) then return end
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

-- Deliberately looser than forThisMatch: a result is the end of a match, not a
-- change to a board, and dropping one leaves the player staring at a dead
-- screen. Only an explicit mismatch — a result for a match we have already left
-- behind — is ignored.
Remotes.Result.OnClientEvent:Connect(function(payload)
	if matchInfo and matchInfo.networked and payload.matchId ~= matchInfo.matchId then return end
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
	-- A running score, straight from the server. The client never adds anything
	-- to it; it only shows what it was told.
	if msg.score and blitz then
		blitz.score = msg.score
		return
	end
	if msg.finished and msg.result then
		local r = msg.result
		if input then input:disable() end
		if fx then fx:onKo(msg.record == true) end
		SoundKit.setMusic("musicLobby")
		SoundKit.play(msg.record and "go" or "ko")
		hud:setBlitz(nil)
		hud:setOverlay(nil)
		ui:showResults({
			outcome = Enums.Result.Draw,
			reason = "blitz",
			topout = r.reason == "topout",
			record = msg.record == true,
			score = r.score,
			best = math.max(r.score or 0, bestBlitz),
			stats = {
				lines = r.lines, sent = r.score, pieces = r.pieces, quads = r.quads,
				apm = r.tspins, bestCombo = r.bestCombo,
			},
		}, false)
		blitz = nil
		setState(Enums.State.Results)
		return
	end
	if msg.seed and msg.mode == Enums.Mode.Blitz then
		-- The server decided when this starts and ends. Both ends read the same
		-- clock, so a slow round trip costs the player none of their two minutes.
		blitz = { sessionId = msg.sessionId, startAt = msg.startAt, endAt = msg.endAt, score = 0 }
		startSim(msg.seed, { gravity = msg.gravity }, {
			blitz = true, sessionId = msg.sessionId, mode = msg.mode,
		})
		hud:setOpponentVisible(false)
		setState(Enums.State.Countdown)
		task.spawn(function()
			local last = nil
			while blitz and workspace:GetServerTimeNow() < blitz.startAt do
				local left = math.ceil(blitz.startAt - workspace:GetServerTimeNow())
				if left ~= last and left > 0 then
					last = left
					hud:setOverlay(tostring(left))
					SoundKit.play("countdown")
				end
				task.wait(0.05)
			end
			if not blitz then return end
			hud:setOverlay("GO")
			SoundKit.play("go")
			SoundKit.setMusic("musicMatch")
			setState(Enums.State.Playing)
			if input then input:arm() end
			matchStart = os.clock()
			task.delay(0.5, function() hud:setOverlay(nil) end)
		end)
		return
	end
	if msg.seed then
		-- The session id goes back with the result: the server times the run
		-- from when it issued this seed.
		startSim(msg.seed, { gravity = msg.gravity }, {
			practice = true, mode = msg.mode, sessionId = msg.sessionId,
		})
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
	if profile.colourblind ~= nil then
		hud:setColourblind(profile.colourblind)
	end
	-- Entitlement arrives with the profile and is never decided here. A patched
	-- client can paint its own board any colour it likes; what it cannot do is
	-- make the server persist a skin it does not own.
	if type(profile.ownedSkins) == "table" then
		ownedSkins = profile.ownedSkins
	end
	if type(profile.bestBlitz) == "number" then
		bestBlitz = profile.bestBlitz
	end

	-- Titles arrive with the profile like every other entitlement. A newly
	-- granted one is never equipped automatically: owning and choosing are
	-- different, and a player may well prefer SECRET SOLVER to ELITE.
	local before = ownedTitles
	if type(profile.ownedTitles) == "table" then
		ownedTitles = profile.ownedTitles
	end
	if type(profile.equippedTitle) == "string" then
		equippedTitle = profile.equippedTitle
	end
	ui:applyTitles(ownedTitles, equippedTitle, profile)

	-- Say so when something is earned mid-session. Historical unlocks arrive in
	-- the very first push, when `before` is still the bare default, and those
	-- are summarised rather than announced one at a time.
	if seenProfile then
		local fresh = {}
		for id in pairs(ownedTitles) do
			if not before[id] then table.insert(fresh, id) end
		end
		if #fresh == 1 then
			local t = TitleData.get(fresh[1])
			ui:toast("TITLE UNLOCKED", t and t.name or fresh[1], Theme.C.gold)
			SoundKit.play("go", 0.9)
		elseif #fresh > 1 then
			ui:toast("TITLES UNLOCKED", ("%d new titles"):format(#fresh), Theme.C.gold)
			SoundKit.play("go", 0.9)
		end
	end
	seenProfile = true
	if type(profile.equippedSkin) == "string" then
		equippedSkin = profile.equippedSkin
		hud:setSkin(equippedSkin)
	end

	-- The secret nook pays out through the profile like everything else, so
	-- there is no reward remote to fake: the moment this flips is the moment
	-- the server recorded it.
	local solvedNow = profile.secretPuzzleSolved == true
	if solvedNow and secretSolved == false then
		local skin = SkinData.get(SkinData.SECRET_ID)
		ui:toast("SECRET SOLVED", (skin and skin.name or "A skin") .. " unlocked", Theme.C.mg)
		SoundKit.play("go", 0.8)
	end
	if solvedNow and secretSolved ~= true then
		markNookSolved()
	end
	secretSolved = solvedNow
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
		-- Only quick play falls back to a bot, so only quick play has a deadline.
		local botIn = (queueMode == Enums.Mode.Quick) and math.max(0, Tuning.BOT_AFTER - elapsed) or nil
		local note, title
		if queueMode == Enums.Mode.Ranked then
			title = "RANKED QUEUE"
			note = string.format("Humans only — no bot fallback in ranked.  %ds", math.floor(elapsed))
		elseif queueMode == Enums.Mode.Private then
			title = "PRIVATE ROOM"
			note = string.format("Waiting for someone else to stand on CREATE ROOM.  %ds",
				math.floor(elapsed))
		end
		ui:setQueueInfo(elapsed, botIn, note, title)
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

	-- The Blitz clock is the server's deadline minus the shared clock, not a
	-- local stopwatch: a client whose frame loop stalls loses no time and gains
	-- none. Reading two numbers per frame; the label is written, not rebuilt.
	if blitz and matchInfo and matchInfo.blitz then
		hud:setBlitz(blitz.endAt - workspace:GetServerTimeNow(), blitz.score)
	end

	-- Practice is a 40-line sprint, so it has a goal and a clock rather than
	-- being a board that goes nowhere.
	if matchInfo and matchInfo.practice and state == Enums.State.Playing then
		hud.hint.Text = string.format("SPRINT  ·  %d / %d LINES  ·  %.1fs",
			math.min(b.stats.lines, SPRINT_GOAL), SPRINT_GOAL, elapsed)
		if b.stats.lines >= SPRINT_GOAL and not matchInfo.done then
			matchInfo.done = true
			if input then input:disable() end
			Remotes.Practice:FireServer({
				finished = true, sessionId = matchInfo.sessionId,
				mode = Enums.Mode.Sprint, stats = b.stats, time = elapsed,
			})
			SoundKit.play("go")
			hud:setOverlay(string.format("%.2fs", elapsed), Theme.C.cy)
			ui:showResults({
				outcome = Enums.Result.Win, reason = "sprint", sprintTime = elapsed,
				stats = { lines = b.stats.lines, sent = b.stats.sent, pieces = b.stats.pieces,
					quads = b.stats.quads, apm = b.stats.pieces / elapsed * 60,
					bestCombo = bestCombo },
			}, false)
			setState(Enums.State.Results)
		end
	end

	-- Our own board goes to the opponent on a fixed budget, not every frame.
	if matchInfo and matchInfo.networked and state == Enums.State.Playing then
		local now = os.clock()
		if now - lastSnapshot >= 1 / Tuning.SNAPSHOT_HZ then
			lastSnapshot = now
			-- Not what the opponent sees — the server draws that from its own
			-- shadow. This is the divergence probe: the server compares it to
			-- the shadow and resyncs us if they have drifted apart.
			Remotes.Lock:FireServer({
				matchId = matchInfo.matchId,
				snapshot = Net.packBoard(b:snapshot()),
			})
		end
	end
end)

pcall(function()
	StarterGui:SetCore("ResetButtonCallback", false)
end)
