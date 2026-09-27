--!nonstrict
-- Sons et musique. Utilise la version uploadée du pack original si configurée,
-- sinon le son public par défaut. Légère variation de hauteur à chaque lecture.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)

local State = require(script.Parent.State)

local Audio = {}

-- Volumes de base (les barres des réglages multiplient ces valeurs) : les effets
-- sont volontairement discrets pour ne pas couvrir la musique ni fatiguer.
Audio.SfxBase = 0.7
Audio.MusicBase = 0.8

local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "SFX"
sfxGroup.Volume = 1
sfxGroup.Parent = SoundService
local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Volume = 1
musicGroup.Parent = SoundService

local templates: { [string]: Sound } = {}
local currentMusic: Sound? = nil
local currentMusicKey: string? = nil
local lastPlayed: { [string]: number } = {}

local function idFor(key: string): string?
	local def = Sounds[key]
	if not def then
		return nil
	end
	if def.Uploaded and def.Uploaded ~= 0 then
		return "rbxassetid://" .. def.Uploaded
	end
	return def.Default
end

local function template(key: string): Sound?
	if templates[key] then
		return templates[key]
	end
	local def = Sounds[key]
	local id = idFor(key)
	if not def or not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = id
	s.Volume = def.Volume
	s.PlaybackSpeed = def.Speed or 1
	s.Looped = def.Looped == true
	templates[key] = s
	return s
end

-- Joue un effet. opts : { Pitch, Volume, Parent (3D), NoVary, Cooldown }
function Audio.Play(key: string, options: { [string]: any }?): Sound?
	local opts: { [string]: any } = options or {}
	local t = template(key)
	if not t then
		return nil
	end
	local cooldown = opts.Cooldown or 0.06 -- évite l'empilement du même son
	local now = os.clock()
	if (lastPlayed[key] or 0) + cooldown > now then
		return nil
	end
	lastPlayed[key] = now
	local s = t:Clone()
	local vary = if opts.NoVary then 1 else (0.94 + math.random() * 0.12)
	s.PlaybackSpeed = t.PlaybackSpeed * (opts.Pitch or 1) * vary
	s.Volume = t.Volume * (opts.Volume or 1)
	s.SoundGroup = sfxGroup
	if opts.Parent then
		s.RollOffMaxDistance = opts.MaxDistance or 180
		s.RollOffMinDistance = 12
		s.Parent = opts.Parent
	else
		s.Parent = SoundService
	end
	s:Play()
	if not s.Looped then
		s.Ended:Once(function()
			s:Destroy()
		end)
		task.delay(12, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
	return s
end

-- Son en boucle (alarme…) : renvoie le Sound à arrêter soi-même.
function Audio.Loop(key: string, opts: { [string]: any }?): Sound?
	local t = template(key)
	if not t then
		return nil
	end
	local s = t:Clone()
	s.Looped = true
	s.Volume = t.Volume * ((opts and opts.Volume) or 1)
	s.SoundGroup = sfxGroup
	s.Parent = (opts and opts.Parent) or SoundService
	s:Play()
	return s
end

-- Musique en cours (clé), pour la restaurer après un mode spécial.
function Audio.CurrentMusic(): string?
	return currentMusicKey
end

function Audio.Music(key: string?)
	if key == currentMusicKey then
		return
	end
	currentMusicKey = key
	local old = currentMusic
	if old then
		TweenService:Create(old, TweenInfo.new(1.5), { Volume = 0 }):Play()
		task.delay(1.6, function()
			old:Destroy()
		end)
	end
	currentMusic = nil
	if not key then
		return
	end
	local t = template(key)
	if not t then
		return
	end
	local s = t:Clone()
	s.Looped = true
	s.SoundGroup = musicGroup
	local target = t.Volume
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	TweenService:Create(s, TweenInfo.new(2), { Volume = target }):Play()
	currentMusic = s
end

function Audio.Init()
	State.Observe("Settings", function(settings)
		if not settings then
			return
		end
		local sfx = if settings.Sfx == false then 0 else (settings.SfxVolume or 0.6)
		local music = if settings.Music == false then 0 else (settings.MusicVolume or 0.6)
		sfxGroup.Volume = sfx * Audio.SfxBase
		musicGroup.Volume = music * Audio.MusicBase
	end)
	-- Pré-chargement léger des sons les plus fréquents
	task.defer(function()
		local ContentProvider = game:GetService("ContentProvider")
		local list = {}
		for _, key in { "ui_click", "ui_hover", "cash_collect", "coin_tick", "meteor_impact", "egg_crack", "bonk" } do
			local t = template(key)
			if t then
				table.insert(list, t)
			end
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
end

return Audio
