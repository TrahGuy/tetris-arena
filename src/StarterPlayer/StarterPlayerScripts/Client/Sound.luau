-- Audio.
--
-- Every id below is from a source Roblox licenses for use in experiences:
-- ProSoundEffects (Roblox's official free SFX library) and DistrokidOfficial
-- (its licensed music partner). Nothing here is a rip of another game's audio,
-- which most of the free search results turn out to be — several openly say so
-- in their own descriptions. All of them were checked to load with a real
-- duration before being wired in.
--
-- These are general-purpose effects, not sounds authored for a block game, so
-- each cue carries its own volume and pitch: a raw one-second beep on every
-- piece move would be unbearable, and at 2.6x speed and 18% volume the same
-- asset is a tick. Swap any id freely — that is the only line that needs to
-- change.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local SoundKit = {}

type Cue = { id: number, vol: number, pitch: number, music: boolean? }

local CUES: { [string]: Cue } = {
	-- ProSoundEffects "Electronic Beeps", pitched and trimmed per use.
	move = { id = 9114282006, vol = 0.16, pitch = 2.7 },
	rotate = { id = 9114282163, vol = 0.2, pitch = 2.2 },
	hold = { id = 9114282122, vol = 0.28, pitch = 1.8 },
	clear = { id = 9114282278, vol = 0.5, pitch = 1.5 },
	countdown = { id = 9114281883, vol = 0.5, pitch = 1.0 },
	go = { id = 9114282371, vol = 0.65, pitch = 1.3 },
	queue = { id = 9114282371, vol = 0.4, pitch = 1.6 },
	uiHover = { id = 9114282006, vol = 0.1, pitch = 3.0 },
	uiPress = { id = 9114282163, vol = 0.3, pitch = 1.9 },

	-- Impacts. Short and dry for a lock; heavier as the stakes rise.
	lock = { id = 9113573976, vol = 0.3, pitch = 1.5 },  -- Boxing Hits 14
	garbage = { id = 9113524447, vol = 0.5, pitch = 1.3 }, -- Body Impact 3
	quad = { id = 9120271166, vol = 0.7, pitch = 1.1 },  -- Truck Interior Impact 3
	ko = { id = 9113378451, vol = 0.8, pitch = 0.9 },    -- Battering Ram 3

	-- DistrokidOfficial, licensed music.
	musicLobby = { id = 115065003388211, vol = 0.35, pitch = 1, music = true },
	musicMatch = { id = 109757873299431, vol = 0.4, pitch = 1, music = true },
}

local groups: { [string]: SoundGroup } = {}
local sounds: { [string]: Sound } = {}
local current: Sound? = nil
local volumes = { music = 0.6, sfx = 0.8 }

local function group(name: string): SoundGroup
	if groups[name] then return groups[name] end
	local g = SoundService:FindFirstChild(name) :: SoundGroup?
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
	end
	groups[name] = g :: SoundGroup
	return g :: SoundGroup
end

function SoundKit.init()
	group("SFX").Volume = volumes.sfx
	group("Music").Volume = volumes.music

	local preload = {}
	for name, cue in pairs(CUES) do
		if cue.id and cue.id > 0 then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = "rbxassetid://" .. cue.id
			s.Volume = cue.vol
			s.PlaybackSpeed = cue.pitch
			s.SoundGroup = group(cue.music and "Music" or "SFX")
			s.Looped = cue.music == true
			s.Parent = SoundService
			sounds[name] = s
			table.insert(preload, s)
		end
	end
	-- Behind the countdown, or the first quad of the match hitches while the
	-- asset is still being fetched.
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, preload)
	end)
end

function SoundKit.play(name: string, pitchScale: number?)
	local s = sounds[name]
	if not s then return end
	local cue = CUES[name]
	s.PlaybackSpeed = cue.pitch * (pitchScale or 1)
	s.TimePosition = 0
	s:Play()
end

function SoundKit.setMusic(name: string?)
	local next_ = name and sounds[name] or nil
	if current == next_ then return end
	if current then current:Stop() end
	current = next_
	if current then current:Play() end
end

function SoundKit.setVolume(kind: string, value: number)
	volumes[kind] = math.clamp(value, 0, 1)
	group(kind == "music" and "Music" or "SFX").Volume = volumes[kind]
end

function SoundKit.hasAudio(): boolean
	return next(sounds) ~= nil
end

return SoundKit
