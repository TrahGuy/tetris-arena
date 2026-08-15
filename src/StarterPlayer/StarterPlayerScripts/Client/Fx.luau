-- Match juice: screen flash, board shake, clear pops, KO.
--
-- All of it is decoration on top of a board that must stay readable, so the
-- rule throughout is short and small: shake is a few pixels for a fifth of a
-- second, the flash never fully whites out the field, and nothing here ever
-- moves a cell the player is reading.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)

local Fx = {}
Fx.__index = Fx

function Fx.new(hud: any, screenParent: Instance)
	local self = setmetatable({ hud = hud, shake = 0, shakeSeed = 0 }, Fx)

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 50
	flash.Active = false
	flash.Parent = screenParent
	self.flash = flash

	self.home = hud.boardHolder.Position
	self.conn = RunService.RenderStepped:Connect(function(dt)
		if self.shake <= 0 then return end
		self.shake = math.max(0, self.shake - dt * 5)
		self.shakeSeed += dt * 60
		local mag = self.shake * 9
		hud.boardHolder.Position = self.home + UDim2.fromOffset(
			math.sin(self.shakeSeed * 1.7) * mag,
			math.cos(self.shakeSeed * 2.3) * mag)
		if self.shake <= 0 then
			hud.boardHolder.Position = self.home
		end
	end)
	return self
end

function Fx:kick(amount: number)
	self.shake = math.clamp(math.max(self.shake, amount), 0, 1)
end

function Fx:flashScreen(colour: Color3, strength: number, time: number?)
	self.flash.BackgroundColor3 = colour
	self.flash.BackgroundTransparency = 1 - math.clamp(strength, 0, 1)
	TweenService:Create(self.flash, TweenInfo.new(time or 0.32, Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- Called on every lock, so the response scales with what actually happened
-- rather than firing the same effect for a single and for a quad.
function Fx:onClear(info: any)
	local n = info.lines
	if n <= 0 then return end
	if n >= 4 then
		self:kick(0.85)
		self:flashScreen(Theme.C.cy, 0.42)
		self.hud:flash(info.b2b and "QUAD  ·  BACK-TO-BACK" or "QUAD", Theme.C.cy)
	elseif info.tspin then
		self:kick(0.5)
		self:flashScreen(Theme.C.violet, 0.3)
		self.hud:flash((info.tspin == "mini" and "T-SPIN MINI" or "T-SPIN"), Theme.C.violet)
	elseif n >= 2 then
		self:kick(0.28)
	end
	if info.perfect then
		self:kick(1)
		self:flashScreen(Theme.C.gold, 0.6, 0.5)
		self.hud:flash("PERFECT CLEAR", Theme.C.gold)
	elseif info.combo and info.combo >= 3 then
		self.hud:flash(("COMBO ×%d"):format(info.combo), Theme.C.gold)
	end
end

function Fx:onGarbage(rows: number)
	self:kick(math.clamp(rows / 8, 0.15, 0.6))
	self:flashScreen(Theme.C.red, 0.22, 0.25)
end

function Fx:onWarning()
	self:flashScreen(Theme.C.red, 0.14, 0.4)
end

function Fx:onKo(win: boolean)
	self:kick(1)
	self:flashScreen(win and Theme.C.cy or Theme.C.red, 0.75, 0.7)
end

function Fx:destroy()
	if self.conn then self.conn:Disconnect() end
	self.hud.boardHolder.Position = self.home
	self.flash:Destroy()
end

return Fx
