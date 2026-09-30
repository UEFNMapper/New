--!strict
--[[
	AmbiencePresets : l'ambiance lumineuse de chaque monde (v4, docs/AUDIT_V3.md § E).
	Données pures (testables avec Lune) lues par le contrôleur client `Ambience` :
	- Lighting : Brightness, Ambient, OutdoorAmbient ;
	- Atmosphere : Density, Color, Decay, Glare, Haze ;
	- Bloom : Intensity, Threshold ;
	- Particules d'ambiance autour du joueur (discrètes, peu nombreuses : mobile).
	Le preset 0 (lobby) reprend EXACTEMENT l'éclairage de default.project.json (soirée chaude).
	La teinte ColorCorrection n'est pas ici : elle appartient à Feedback.applyWorld.

	Couleurs : { r, g, b } entre 0 et 1 (comme default.project.json) ; Color3.new côté client.
	Le rouge est réservé au danger : aucune particule rouge / magenta vif.
]]

local Tower = require(script.Parent.Tower)

local AmbiencePresets = {}

export type Rgb = { number }

export type Particles = {
	Kind: string, -- nom lisible (étincelles, bits de données…)
	Texture: string, -- texture intégrée de Roblox (rbxasset://)
	Colors: { Rgb }, -- dégradé sur la vie de la particule (1 à 3 couleurs)
	Rate: number, -- particules par seconde (faible : mobile)
	Lifetime: { number }, -- { min, max } secondes
	Speed: { number }, -- { min, max } studs/s
	Size: number, -- taille max (studs)
	Acceleration: { number }, -- { x, y, z } (chute des étincelles, montée de la chaleur…)
	Spread: number, -- angle de dispersion (degrés)
	LightEmission: number, -- 0..1
	RotSpeed: number, -- rotation max (degrés/s), 0 = aucune
	Flicker: boolean, -- scintille (pixels, synapses) au lieu d'un simple fondu
}

export type Preset = {
	Name: string,
	Brightness: number,
	Ambient: Rgb,
	OutdoorAmbient: Rgb,
	Atmosphere: {
		Density: number,
		Color: Rgb,
		Decay: Rgb,
		Glare: number,
		Haze: number,
	},
	Bloom: { Intensity: number, Threshold: number },
	Particles: Particles?,
}

-- Durée des fondus d'un monde à l'autre (secondes).
AmbiencePresets.TWEEN = 2.5
-- Après un BLACKOUT, IncidentController fait clignoter puis restaure l'éclairage qu'il avait
-- sauvegardé (≈ 0,4 s de clignotement + 0,6 s de fondu) : on attend avant de reprendre la main.
AmbiencePresets.BLACKOUT_GRACE = 1.6

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SPARK = "rbxasset://textures/particles/fire_sparks_main.dds"

AmbiencePresets.Presets = table.freeze({
	[0] = {
		Name = "Lobby · soirée chaude",
		Brightness = 2.6,
		Ambient = { 0.44, 0.39, 0.42 },
		OutdoorAmbient = { 0.58, 0.49, 0.46 },
		Atmosphere = {
			Density = 0.22,
			Color = { 0.98, 0.8, 0.66 },
			Decay = { 0.62, 0.42, 0.52 },
			Glare = 0.2,
			Haze = 0.8,
		},
		Bloom = { Intensity = 0.35, Threshold = 1.5 },
		Particles = nil,
	},
	[1] = {
		Name = "La Centrale · orange électrique",
		Brightness = 2.3,
		Ambient = { 0.42, 0.31, 0.22 },
		OutdoorAmbient = { 0.56, 0.41, 0.28 },
		Atmosphere = {
			Density = 0.3,
			Color = { 1, 0.74, 0.46 },
			Decay = { 0.62, 0.32, 0.16 },
			Glare = 0.6,
			Haze = 1.4,
		},
		Bloom = { Intensity = 0.5, Threshold = 1.2 },
		Particles = {
			Kind = "Étincelles",
			Texture = SPARK,
			Colors = { { 1, 0.92, 0.6 }, { 1, 0.68, 0.33 } },
			Rate = 6,
			Lifetime = { 0.8, 1.5 },
			Speed = { 3, 7 },
			Size = 0.22,
			Acceleration = { 0, -14, 0 },
			Spread = 60,
			LightEmission = 1,
			RotSpeed = 0,
			Flicker = true,
		},
	},
	[2] = {
		Name = "Memory Lanes · données violettes",
		Brightness = 2.1,
		Ambient = { 0.34, 0.3, 0.48 },
		OutdoorAmbient = { 0.43, 0.37, 0.62 },
		Atmosphere = {
			Density = 0.3,
			Color = { 0.74, 0.66, 1 },
			Decay = { 0.38, 0.28, 0.64 },
			Glare = 0.3,
			Haze = 1.6,
		},
		Bloom = { Intensity = 0.45, Threshold = 1.3 },
		Particles = {
			Kind = "Bits de données",
			Texture = SPARKLE,
			Colors = { { 0.55, 0.49, 1 }, { 0.75, 0.52, 0.99 } },
			Rate = 6,
			Lifetime = { 3, 5 },
			Speed = { 0.5, 1.5 },
			Size = 0.28,
			Acceleration = { 0, 1.2, 0 },
			Spread = 180,
			LightEmission = 0.8,
			RotSpeed = 0,
			Flicker = false,
		},
	},
	[3] = {
		Name = "Data Vault · coffre turquoise",
		Brightness = 2.4,
		Ambient = { 0.28, 0.42, 0.44 },
		OutdoorAmbient = { 0.36, 0.55, 0.56 },
		Atmosphere = {
			Density = 0.24,
			Color = { 0.72, 0.95, 0.93 },
			Decay = { 0.22, 0.5, 0.52 },
			Glare = 0.2,
			Haze = 0.9,
		},
		Bloom = { Intensity = 0.35, Threshold = 1.4 },
		Particles = {
			Kind = "Poussière de données propre",
			Texture = SPARKLE,
			Colors = { { 0.31, 0.82, 0.77 }, { 0.8, 1, 0.97 } },
			Rate = 4,
			Lifetime = { 3, 5 },
			Speed = { 0.3, 1 },
			Size = 0.22,
			Acceleration = { 0, 0.3, 0 },
			Spread = 180,
			LightEmission = 0.7,
			RotSpeed = 0,
			Flicker = false,
		},
	},
	[4] = {
		Name = "Cryo Tower · brume glacée",
		Brightness = 2.5,
		Ambient = { 0.36, 0.44, 0.56 },
		OutdoorAmbient = { 0.5, 0.6, 0.74 },
		Atmosphere = {
			Density = 0.36,
			Color = { 0.82, 0.92, 1 },
			Decay = { 0.45, 0.62, 0.85 },
			Glare = 0.1,
			Haze = 2.6,
		},
		Bloom = { Intensity = 0.4, Threshold = 1.4 },
		Particles = {
			Kind = "Flocons de givre",
			Texture = SPARKLE,
			Colors = { { 0.92, 0.97, 1 }, { 0.75, 0.89, 0.97 } },
			Rate = 8,
			Lifetime = { 4, 6 },
			Speed = { 0.5, 1.5 },
			Size = 0.3,
			Acceleration = { 0.4, -1.5, 0 },
			Spread = 180,
			LightEmission = 0.5,
			RotSpeed = 60,
			Flicker = false,
		},
	},
	[5] = {
		Name = "The Core · chaleur jaune",
		Brightness = 2.8,
		Ambient = { 0.48, 0.42, 0.26 },
		OutdoorAmbient = { 0.62, 0.54, 0.32 },
		Atmosphere = {
			Density = 0.32,
			Color = { 1, 0.9, 0.56 },
			Decay = { 0.7, 0.5, 0.2 },
			Glare = 1,
			Haze = 1.8,
		},
		Bloom = { Intensity = 0.55, Threshold = 1.1 },
		Particles = {
			Kind = "Points de chaleur",
			Texture = SPARKLE,
			Colors = { { 1, 0.92, 0.5 }, { 1, 0.75, 0.4 } },
			Rate = 7,
			Lifetime = { 2, 3.5 },
			Speed = { 1, 2.5 },
			Size = 0.2,
			Acceleration = { 0, 3, 0 },
			Spread = 30,
			LightEmission = 0.9,
			RotSpeed = 0,
			Flicker = false,
		},
	},
	[6] = {
		Name = "Render Canyon · rendu vert et rose",
		Brightness = 2.3,
		Ambient = { 0.3, 0.42, 0.34 },
		OutdoorAmbient = { 0.4, 0.56, 0.45 },
		Atmosphere = {
			Density = 0.28,
			Color = { 0.72, 1, 0.8 },
			Decay = { 0.62, 0.34, 0.54 },
			Glare = 0.4,
			Haze = 1.2,
		},
		Bloom = { Intensity = 0.5, Threshold = 1.25 },
		Particles = {
			Kind = "Pixels",
			Texture = SPARKLE,
			-- Rose clair (pas le magenta des dangers) et vert du GPU.
			Colors = { { 0.28, 0.73, 0.47 }, { 1, 0.66, 0.86 }, { 0.28, 0.73, 0.47 } },
			Rate = 6,
			Lifetime = { 2, 3.5 },
			Speed = { 0.5, 1.5 },
			Size = 0.3,
			Acceleration = { 0.8, 0, 0 },
			Spread = 180,
			LightEmission = 0.8,
			RotSpeed = 0,
			Flicker = true,
		},
	},
	[7] = {
		Name = "Neural Nexus · lilas neuronal",
		Brightness = 2.1,
		Ambient = { 0.4, 0.34, 0.5 },
		OutdoorAmbient = { 0.52, 0.44, 0.66 },
		Atmosphere = {
			Density = 0.3,
			Color = { 0.9, 0.84, 1 },
			Decay = { 0.5, 0.36, 0.72 },
			Glare = 0.5,
			Haze = 1.5,
		},
		Bloom = { Intensity = 0.55, Threshold = 1.2 },
		Particles = {
			Kind = "Synapses",
			Texture = SPARKLE,
			Colors = { { 0.91, 0.85, 0.99 }, { 0.62, 0.48, 0.92 } },
			Rate = 5,
			Lifetime = { 2.5, 4 },
			Speed = { 0.5, 2 },
			Size = 0.35,
			Acceleration = { 0, 0.5, 0 },
			Spread = 180,
			LightEmission = 1,
			RotSpeed = 0,
			Flicker = true,
		},
	},
} :: { [number]: Preset })

-- Preset d'un monde (0 = lobby) ; tout monde inconnu retombe sur le lobby.
function AmbiencePresets.Get(world: number): Preset
	return AmbiencePresets.Presets[world] or AmbiencePresets.Presets[0]
end

export type RunState = {
	AtLobby: boolean,
	Stage: number,
	Cleared: number,
	RunStarted: boolean,
}

-- Monde dont on affiche l'ambiance : 0 au lobby (et avant la ligne de départ), sinon le monde
-- que le joueur est en train de parcourir (Tower.RunWorld, comme le HUD et les incidents).
function AmbiencePresets.WorldFor(state: RunState): number
	if state.AtLobby or (state.Stage <= 0 and not state.RunStarted) then
		return 0
	end
	return math.clamp(Tower.RunWorld(state.Stage, state.Cleared), 1, Tower.WORLD_COUNT)
end

-- L'éclairage appartient-il à l'ambiance ? Non pendant un BLACKOUT (annonce comprise :
-- IncidentController sauvegarde l'éclairage au début de l'incident) ni pendant sa restauration.
function AmbiencePresets.LightingFree(incidentKind: string, secondsSinceBlackout: number): boolean
	if incidentKind == "Blackout" then
		return false
	end
	return secondsSinceBlackout >= AmbiencePresets.BLACKOUT_GRACE
end

return table.freeze(AmbiencePresets)
