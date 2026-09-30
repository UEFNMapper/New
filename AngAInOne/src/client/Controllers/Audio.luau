--!strict
--[[
	Audio : musique adaptative par zone (fondu enchaîné) + effets sonores.
	SoundGroups Music / SFX réglables dans les paramètres. Ducking léger de la
	musique pendant les gros gains pour que la récompense "sonne".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Audio)

local Audio = {}

local musicGroup: SoundGroup
local sfxGroup: SoundGroup
local tracks: { Sound } = {}
local active = 1
local currentId = ""
local sfxPool: { [string]: Sound } = {}
local musicVolume = AudioConfig.MusicVolume

local function makeGroup(name: string, volume: number): SoundGroup
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = volume
	group.Parent = SoundService
	return group
end

function Audio.SetVolumes(music: number, sfx: number)
	musicVolume = music
	musicGroup.Volume = music / AudioConfig.MusicVolume
	sfxGroup.Volume = sfx
end

-- Joue la musique d'une zone (index) ou du hub ("Hub"), en fondu enchaîné.
function Audio.PlayZone(key: number | string)
	local id = (AudioConfig.Music :: any)[key]
	if type(id) ~= "string" or id == currentId then
		return
	end
	currentId = id
	local fadeOut = tracks[active]
	active = if active == 1 then 2 else 1
	local fadeIn = tracks[active]
	fadeIn.SoundId = id
	fadeIn.Volume = 0
	fadeIn.TimePosition = 0
	fadeIn:Play()
	local info = TweenInfo.new(AudioConfig.CrossfadeSeconds, Enum.EasingStyle.Sine)
	TweenService:Create(fadeIn, info, { Volume = AudioConfig.MusicVolume }):Play()
	local out = TweenService:Create(fadeOut, info, { Volume = 0 })
	out:Play()
	out.Completed:Once(function()
		if tracks[active] ~= fadeOut then
			fadeOut:Stop()
		end
	end)
end

function Audio.Play(name: string, pitch: number?)
	local def = (AudioConfig.Sfx :: any)[name]
	if not def then
		return
	end
	local sound = sfxPool[name]
	if not sound then
		local created = Instance.new("Sound")
		created.Name = name
		created.SoundId = def.Id
		created.Volume = def.Volume
		created.SoundGroup = sfxGroup
		created.Parent = SoundService
		sfxPool[name] = created
		sound = created
	end
	if pitch then
		sound.PlaybackSpeed = pitch
	end
	-- PlayOnRemove permettrait des superpositions ; ici on relance simplement le son.
	sound.TimePosition = 0
	sound:Play()
end

-- Baisse brièvement la musique (gros gain, cinématique).
function Audio.Duck(seconds: number)
	local info = TweenInfo.new(0.2)
	TweenService:Create(musicGroup, info, { Volume = musicGroup.Volume * 0.55 }):Play()
	task.delay(seconds, function()
		TweenService:Create(musicGroup, TweenInfo.new(0.8), { Volume = musicVolume / AudioConfig.MusicVolume }):Play()
	end)
end

function Audio.Start()
	musicGroup = makeGroup("Music", 1)
	sfxGroup = makeGroup("SFX", 0.7)
	for i = 1, 2 do
		local track = Instance.new("Sound")
		track.Name = `MusicTrack{i}`
		track.Looped = true
		track.Volume = 0
		track.SoundGroup = musicGroup
		track.Parent = SoundService
		tracks[i] = track
	end
end

return Audio
