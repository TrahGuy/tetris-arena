-- Turns the physical lobby stations into input.
--
-- Every pad in the world carries a PadMode attribute; this watches the local
-- character's feet against their footprints. Standing still on one for DWELL
-- seconds activates it — a dwell rather than an instant trigger, so walking
-- across the concourse does not queue you into a ranked match by accident.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage:WaitForChild("Shared").Enums)

local PadController = {}
PadController.__index = PadController

local DWELL = 0.8

local LABELS = {
	[Enums.Mode.Quick] = { "QUICK MATCH", "Stand here to queue for a 1v1" },
	[Enums.Mode.Ranked] = { "RANKED", "Competitive queue" },
	[Enums.Mode.Private] = { "CREATE ROOM", "Private match with a friend" },
	[Enums.Mode.Practice] = { "PRACTICE", "Solo board, no stakes" },
	[Enums.Mode.Emote] = { "EMOTE ZONE", "Dance / idle rewards" },
}

function PadController.new(onActivate: (string) -> ())
	local self = setmetatable({
		onActivate = onActivate,
		pads = {},
		current = nil,
		dwell = 0,
		enabled = true,
		fired = false,
	}, PadController)
	self:rescan()
	return self
end

function PadController:rescan()
	table.clear(self.pads)
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then return end
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("PadMode") then
			table.insert(self.pads, {
				part = d,
				mode = d:GetAttribute("PadMode"),
				accent = d:GetAttribute("Accent"),
			})
		end
	end
end

function PadController:setEnabled(on: boolean)
	self.enabled = on
	if not on then
		self.current, self.dwell, self.fired = nil, 0, false
	end
end

function PadController:_padUnder(pos: Vector3)
	for _, pad in ipairs(self.pads) do
		local p = pad.part
		local half = p.Size * 0.5
		local local_ = p.CFrame:PointToObjectSpace(pos)
		if math.abs(local_.X) <= half.X
			and math.abs(local_.Z) <= half.Z
			and local_.Y > -half.Y
			and local_.Y < half.Y + 8 then
			return pad
		end
	end
	return nil
end

-- Returns title, subtitle, progress for the prompt, or nil when off any pad.
function PadController:update(dt: number): (string?, string?, number?)
	if not self.enabled then return nil end
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		self.current, self.dwell, self.fired = nil, 0, false
		return nil
	end

	local pad = self:_padUnder(root.Position)
	if not pad then
		self.current, self.dwell, self.fired = nil, 0, false
		return nil
	end

	if pad ~= self.current then
		self.current, self.dwell, self.fired = pad, 0, false
	end
	self.dwell = math.min(DWELL, self.dwell + dt)

	local label = LABELS[pad.mode] or { string.upper(tostring(pad.mode)), "" }
	if self.dwell >= DWELL and not self.fired then
		self.fired = true
		self.onActivate(pad.mode)
	end
	return label[1], label[2], self.dwell / DWELL
end

return PadController
