-- One place that names every remote, so nothing anywhere else types a string.
--
-- The server creates them on first require; the client waits. Cosmetic,
-- self-correcting traffic uses UnreliableRemoteEvent — a dropped opponent-board
-- snapshot is replaced by the next one 100ms later and nobody notices.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RELIABLE = {
	"QueueRequest",  -- c->s  { mode }
	"QueueCancel",   -- c->s  ()
	"MatchUpdate",   -- s->c  { state, ... }
	"Lock",          -- c->s  { tick, index, kind, rot, x, y, held }
	"Garbage",       -- s->c  { rows, gapCol, at }
	"Result",        -- s->c  { outcome, reason, stats, opponent }
	"Resync",        -- s->c  { cells, piece, ... } after an authority mismatch
	"Forfeit",       -- c->s  ()
	"Practice",      -- c->s  { mode } / s->c { seed }
	"Profile",       -- s->c  { wins, losses, settings, ... }
	"SaveSettings",  -- c->s  { das, arr, volume, colourblind }
	-- c->s { skinId }. A request, never a claim: ownership lives in the profile
	-- and is decided server side. There is deliberately no remote that grants.
	"EquipSkin",
}

local UNRELIABLE = {
	"Snapshot", -- s->c  opponent board, packed
}

local Remotes = {}
local folder: Instance

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	for _, name in ipairs(RELIABLE) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in ipairs(UNRELIABLE) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("UnreliableRemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes", 30)
end

setmetatable(Remotes, {
	__index = function(_, key)
		local r = folder and folder:WaitForChild(key, 15)
		if not r then
			error("[Remotes] no remote named " .. tostring(key), 2)
		end
		return r
	end,
})

return Remotes
