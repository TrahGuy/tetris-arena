-- Audio plumbing.
--
-- The mixer, the volume settings and the preloading are all here and working.
-- The asset ids are NOT: uploading audio needs a Roblox account and I will not
-- invent ids, because a wrong one is either a silent 404 or somebody else's
-- sound playing in your game. Drop ids into IDS below and everything else
-- already works — play() is a safe no-op for any cue with no id.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local SoundKit = {}

-- Fill these in. Cue names are referenced from Main/Fx; adding an id is the
-- only change needed to make one audible.
local IDS: { [string]: string } = {
	move = "",
	rotate = "",
	lock = "",
	clear = "",
	quad = "",
	garbage = "",
	hold = "",
	ko = "",
	countdown = "",
	go = "",
	uiHover = "",
	uiPress = "",
	queue = "",
	musicLobby = "",
	musicMatch = "",
}

local groups: { [string]: SoundGroup } = {}
local cues: { [string]: Sound } = {}
local music: Sound? = nil
local volumes = { music = 0.6, sfx = 0.8 }

local function group(name: string): SoundGroup
	if groups[name] then return groups[name] end
	local g = SoundService:FindFirstChild(name) :: SoundGroup?
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
	end
	groups[name] = g
	return g
end

function SoundKit.init()
	group("SFX").Volume = volumes.sfx
	group("Music").Volume = volumes.music

	local preload = {}
	for name, id in pairs(IDS) do
		if id ~= "" then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = id
			s.SoundGroup = group(name:match("^music") and "Music" or "SFX")
			s.Parent = SoundService
			cues[name] = s
			table.insert(preload, s)
		end
	end
	-- Preloading behind the countdown, or the first quad of the match hitches.
	if #preload > 0 then
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, preload)
		end)
	end
end

function SoundKit.play(name: string, pitch: number?)
	local s = cues[name]
	if not s then return end
	s.PlaybackSpeed = pitch or 1
	s:Play()
end

function SoundKit.setMusic(name: string?)
	if music then
		music:Stop()
		music = nil
	end
	if not name then return end
	local s = cues[name]
	if not s then return end
	s.Looped = true
	s:Play()
	music = s
end

function SoundKit.setVolume(kind: string, value: number)
	volumes[kind] = math.clamp(value, 0, 1)
	local g = groups[kind == "music" and "Music" or "SFX"]
	if g then g.Volume = volumes[kind] end
end

function SoundKit.hasAudio(): boolean
	return next(cues) ~= nil
end

return SoundKit
