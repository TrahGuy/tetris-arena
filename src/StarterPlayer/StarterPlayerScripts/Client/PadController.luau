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

-- `describe` may override the prompt for a pad whose label is not fixed — the
-- museum's, which has to say what the skin is and whether you own it. It gets
-- the pad record and returns title, subtitle, or nothing to fall back to
-- LABELS above.
function PadController.new(onActivate: (string, any) -> (), describe: ((any) -> (string?, string?))?)
	local self = setmetatable({
		onActivate = onActivate,
		describe = describe,
		pads = {},
		current = nil,
		dwell = 0,
		enabled = true,
		fired = false,
	}, PadController)
	self:rescan()
	self:_watch()
	return self
end

-- Pads can arrive after this controller does. The museum's are built by the
-- server at boot and replicate whenever they replicate, so scanning once at
-- startup is a race the client loses about as often as it wins — and losing it
-- means an exhibit that silently does nothing forever.
function PadController:_watch()
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then return end
	self.watcher = lobby.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and d:GetAttribute("PadMode") then
			self:rescan()
		end
	end)
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
				-- Set by MuseumService on the museum pads; nil everywhere else.
				skinId = d:GetAttribute("SkinId"),
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

	local title, sub
	if self.describe then
		title, sub = self.describe(pad)
	end
	if not title then
		local label = LABELS[pad.mode] or { string.upper(tostring(pad.mode)), "" }
		title, sub = label[1], label[2]
	end
	if self.dwell >= DWELL and not self.fired then
		self.fired = true
		self.onActivate(pad.mode, pad)
	end
	return title, sub, self.dwell / DWELL
end

return PadController
