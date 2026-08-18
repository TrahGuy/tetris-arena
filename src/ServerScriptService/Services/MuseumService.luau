-- Wires the Block Museum's existing exhibits to the skin catalog.
--
-- The museum has been physically complete since Phase 1: three pedestals under
-- glass, each with a plaque, none of them attached to anything. This does not
-- rebuild any of it. It finds the exhibits that are already there, tags them
-- with the skin they represent, and drops one interaction pad in front of each
-- so the existing dwell-to-activate pattern picks them up like any other
-- station.
--
-- Why here and not in build/lobby/04_zones.luau, which owns museum scenery: a
-- pad is an invisible interaction volume rather than something anyone looks at,
-- and doing it at runtime means a live place gets a working museum without a
-- world rebuild. Idempotent, so it can run on every boot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkinData = require(Shared.SkinData)

local MuseumService = {}

MuseumService.PAD_MODE = "skin"

-- The pad sits between the pedestal and the concourse, where a player walking
-- up to look at the exhibit already stands.
local PAD_SIZE = Vector3.new(8, 1, 10)
local PAD_OFFSET = 9 -- studs toward the middle of the hall, +X from the pedestal

-- Returns how many exhibits were wired, and how many catalog skins found none.
function MuseumService.wire(): (number, number)
	local lobby = workspace:FindFirstChild("Lobby")
	local museum = lobby and lobby:FindFirstChild("Museum")
	if not museum then return 0, 0 end

	local wired, missing = 0, 0
	for _, skin in ipairs(SkinData.ordered()) do
		if skin.exhibit then
			local model = museum:FindFirstChild("Exhibit_" .. skin.exhibit)
			local root = model and (model.PrimaryPart or model:FindFirstChild("Root"))
			if not root then
				missing += 1
			else
				-- The exhibit itself carries its id, so anything that walks the
				-- museum can ask what it is looking at.
				model:SetAttribute("SkinId", skin.id)

				local at = root.Position
				local pad = museum:FindFirstChild("SkinPad_" .. skin.id)
				local fresh = pad == nil
				if fresh then
					pad = Instance.new("Part")
					pad.Name = "SkinPad_" .. skin.id
					pad.Anchored = true
					pad.CanCollide = false
					pad.CanQuery = false
					pad.CanTouch = false
					-- Invisible: the pedestal and its lamp are the visual cue.
					-- A glowing slab in a gallery would fight the exhibit.
					pad.Transparency = 1
					pad.Size = PAD_SIZE
				end
				pad.CFrame = CFrame.new(at.X + PAD_OFFSET, 1.5, at.Z)
				pad:SetAttribute("PadMode", MuseumService.PAD_MODE)
				pad:SetAttribute("SkinId", skin.id)
				pad:SetAttribute("Accent", skin.accent)
				-- Parented LAST, with its attributes already on it. The client
				-- picks pads up from DescendantAdded, and a part that arrives
				-- before its PadMode does is a part the client ignores forever.
				if fresh then
					pad.Parent = museum
				end
				wired += 1
			end
		end
	end
	return wired, missing
end

return MuseumService
