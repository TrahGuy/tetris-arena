-- Strips the default Roblox HUD so the arcade UI is the only thing on screen.
-- SetCoreGuiEnabled can fail on the first frames, so each call retries.
local StarterGui = game:GetService("StarterGui")

local function set(coreGuiType, enabled)
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreGuiType, enabled) then return end
		task.wait(0.15)
	end
	warn("[CoreGuiSetup] gave up on " .. tostring(coreGuiType))
end

set(Enum.CoreGuiType.Health, false)
set(Enum.CoreGuiType.Backpack, false)
set(Enum.CoreGuiType.PlayerList, false)
set(Enum.CoreGuiType.EmotesMenu, false)
set(Enum.CoreGuiType.Chat, true) -- kept for the lobby; hidden during a match later
