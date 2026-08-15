-- Keyboard input for a match.
--
-- Bound through ContextActionService and sinking, or Space makes the character
-- jump and the arrow keys walk them off the platform. The player's own control
-- module is disabled outright for the duration — WalkSpeed 0 alone still allows
-- jumping and still fires movement state changes.
--
-- Escape is deliberately not used for forfeit. Roblox reserves it for its own
-- menu and the input cannot be sunk, so binding it there would open the Roblox
-- overlay mid-match every single time. Forfeit is F, plus an on-screen button.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared").Tuning)
local SoundKit = require(script.Parent.Sound)

local InputController = {}
InputController.__index = InputController

-- Gamepad bindings sit alongside the keys: ContextActionService takes both in
-- one BindAction, so a controller needs no separate code path.
local ACTIONS = {
	{ name = "BA_Left", keys = { Enum.KeyCode.Left, Enum.KeyCode.A, Enum.KeyCode.DPadLeft } },
	{ name = "BA_Right", keys = { Enum.KeyCode.Right, Enum.KeyCode.D, Enum.KeyCode.DPadRight } },
	{ name = "BA_Soft", keys = { Enum.KeyCode.Down, Enum.KeyCode.S, Enum.KeyCode.DPadDown } },
	{ name = "BA_Hard", keys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.KeyCode.DPadUp } },
	{ name = "BA_CW", keys = { Enum.KeyCode.Up, Enum.KeyCode.X, Enum.KeyCode.ButtonB } },
	{ name = "BA_CCW", keys = { Enum.KeyCode.Z, Enum.KeyCode.ButtonX } },
	{ name = "BA_Flip", keys = { Enum.KeyCode.V, Enum.KeyCode.ButtonY } },
	{ name = "BA_Hold", keys = { Enum.KeyCode.C, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1 } },
	{ name = "BA_Forfeit", keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonSelect } },
}

function InputController.new(sim: any, hooks: any?)
	return setmetatable({
		sim = sim,
		hooks = hooks or {},
		enabled = false,
		dir = 0,        -- -1, 0, 1 — the direction currently held
		dasTimer = 0,
		arrTimer = 0,
		charged = false,
		heldLeft = false,
		heldRight = false,
		-- Keys already down when the countdown ends must not fire on frame one.
		armed = false,
	}, InputController)
end

-- Cues fire on the initial press only. Playing one per DAS repeat turns a slide
-- to the wall into a machine gun.
function InputController:_press(action: string)
	local sim = self.sim
	if action == "BA_Left" then
		self.heldLeft = true
		self:_setDir(-1)
		sim:push("left")
		SoundKit.play("move")
	elseif action == "BA_Right" then
		self.heldRight = true
		self:_setDir(1)
		sim:push("right")
		SoundKit.play("move")
	elseif action == "BA_Soft" then
		sim:setSoftDrop(true)
	elseif action == "BA_Hard" then
		sim:push("hardDrop")
	elseif action == "BA_CW" then
		sim:push("cw")
		SoundKit.play("rotate")
	elseif action == "BA_CCW" then
		sim:push("ccw")
		SoundKit.play("rotate", 0.9)
	elseif action == "BA_Flip" then
		sim:push("flip")
		SoundKit.play("rotate", 0.8)
	elseif action == "BA_Hold" then
		sim:push("hold")
		SoundKit.play("hold")
	elseif action == "BA_Forfeit" then
		if self.hooks.onForfeit then self.hooks.onForfeit() end
	end
end

function InputController:_release(action: string)
	local sim = self.sim
	if action == "BA_Left" then
		self.heldLeft = false
		self:_setDir(self.heldRight and 1 or 0)
	elseif action == "BA_Right" then
		self.heldRight = false
		self:_setDir(self.heldLeft and -1 or 0)
	elseif action == "BA_Soft" then
		sim:setSoftDrop(false)
	end
end

-- Pressing the opposite direction takes over immediately and re-arms DAS, which
-- is what players expect when tapping back the other way.
function InputController:_setDir(d: number)
	if self.dir ~= d then
		self.dir = d
		self.dasTimer = 0
		self.arrTimer = 0
		self.charged = false
	end
end

-- Public entry points for the on-screen touch pad, which drives exactly the
-- same actions as a key so DAS, arming and sound all behave identically.
function InputController:pressAction(name: string)
	if self.enabled and self.armed then self:_press(name) end
end

function InputController:releaseAction(name: string)
	if self.enabled then self:_release(name) end
end

function InputController:update(dt: number)
	if not self.enabled or not self.armed or self.dir == 0 then return end
	if not self.charged then
		self.dasTimer += dt
		if self.dasTimer >= Tuning.DAS then
			self.charged = true
			self.arrTimer = 0
			self.sim:push(self.dir < 0 and "left" or "right")
		end
		return
	end
	-- ARR 0 means "slide to the wall": push until the move stops succeeding.
	if Tuning.ARR <= 0 then
		for _ = 1, Tuning.WIDTH do
			self.sim:push(self.dir < 0 and "left" or "right")
		end
		return
	end
	self.arrTimer += dt
	while self.arrTimer >= Tuning.ARR do
		self.arrTimer -= Tuning.ARR
		self.sim:push(self.dir < 0 and "left" or "right")
	end
end

function InputController:enable()
	if self.enabled then return end
	self.enabled = true

	local function handler(actionName, state, _input)
		if not self.enabled then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then
			if self.armed then self:_press(actionName) end
		elseif state == Enum.UserInputState.End then
			self:_release(actionName)
		end
		return Enum.ContextActionResult.Sink
	end

	for _, a in ipairs(ACTIONS) do
		ContextActionService:BindAction(a.name, handler, false, table.unpack(a.keys))
	end
	self:_setCharacterControls(false)
end

-- Called when the countdown reaches zero. Anything already held at that moment
-- is ignored until it is released and pressed again, so resting on Left during
-- "3, 2, 1" does not hand out a free slide.
function InputController:arm()
	self.armed = true
	self.heldLeft, self.heldRight, self.dir = false, false, 0
	self.sim:setSoftDrop(false)
end

function InputController:disable()
	if not self.enabled then return end
	self.enabled = false
	self.armed = false
	for _, a in ipairs(ACTIONS) do
		ContextActionService:UnbindAction(a.name)
	end
	self.sim:setSoftDrop(false)
	self:_setCharacterControls(true)
end

function InputController:_setCharacterControls(on: boolean)
	local player = Players.LocalPlayer
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if module then
		local ok, controls = pcall(function()
			return require(module):GetControls()
		end)
		if ok and controls then
			if on then controls:Enable() else controls:Disable() end
		end
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = on and 16 or 0
		hum.JumpPower = on and 50 or 0
		hum.AutoRotate = on
	end
end

return InputController
