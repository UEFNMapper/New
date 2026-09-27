--!strict
-- Événements mondiaux : ils changent l'ambiance de toute la map et
-- les règles du jeu pendant quelques minutes.

export type WorldEvent = {
	Id: string,
	Name: string,
	Tagline: string,
	Icon: string,
	Color: Color3,
	Duration: number,
	Weight: number, -- poids de tirage dans la rotation automatique
	MeteorRate: number, -- multiplicateur de fréquence des météores
	Luck: number, -- chance serveur (météores du cratère)
	CashMult: number,
	Mutation: string?, -- mutation offerte par l'événement
	MutationChance: number?, -- chance à l'éclosion pendant l'événement
	InfectChance: number?, -- chance/10s qu'un kaiju en base soit touché
	Music: string?,
	Lighting: { [string]: any },
}

local rgb = Color3.fromRGB

local Events = {}

Events.FirstDelay = 150 -- premier événement après le démarrage du serveur
Events.Gap = { 330, 480 } -- pause aléatoire entre deux événements

Events.List = {
	{
		Id = "MeteorShower",
		Name = "METEOR SHOWER",
		Tagline = "The sky is falling! x3 meteors & x2 luck",
		Icon = "🌠",
		Color = rgb(255, 106, 31),
		Duration = 150,
		Weight = 30,
		MeteorRate = 3,
		Luck = 2,
		CashMult = 1,
		Music = "music_event",
		Lighting = { ClockTime = 20.5, Ambient = rgb(90, 50, 60), Tint = rgb(255, 200, 170), FogColor = rgb(80, 40, 60), FogEnd = 1400 },
	},
	{
		Id = "BloodMoon",
		Name = "BLOOD MOON",
		Tagline = "Blood mutations appear on hatch and in bases",
		Icon = "🌕",
		Color = rgb(220, 30, 50),
		Duration = 150,
		Weight = 18,
		MeteorRate = 1.5,
		Luck = 1.3,
		CashMult = 1,
		Mutation = "Blood",
		MutationChance = 0.25,
		InfectChance = 0.012,
		Music = "music_event",
		Lighting = { ClockTime = 0.2, Ambient = rgb(120, 20, 30), Tint = rgb(255, 150, 150), FogColor = rgb(90, 0, 10), FogEnd = 900 },
	},
	{
		Id = "Radioactive",
		Name = "RADIOACTIVE STORM",
		Tagline = "Toxic rain! Radioactive mutations (x6)",
		Icon = "☢️",
		Color = rgb(110, 255, 60),
		Duration = 120,
		Weight = 12,
		MeteorRate = 1.3,
		Luck = 1.2,
		CashMult = 1,
		Mutation = "Radioactive",
		MutationChance = 0.18,
		InfectChance = 0.008,
		Music = "music_event",
		Lighting = { ClockTime = 17.8, Ambient = rgb(40, 110, 30), Tint = rgb(200, 255, 170), FogColor = rgb(40, 90, 20), FogEnd = 700 },
	},
	{
		Id = "GoldenHour",
		Name = "GOLDEN HOUR",
		Tagline = "x2 cash for everyone!",
		Icon = "🌅",
		Color = rgb(255, 196, 40),
		Duration = 180,
		Weight = 22,
		MeteorRate = 1,
		Luck = 1,
		CashMult = 2,
		Mutation = "Gold",
		MutationChance = 0.12,
		Lighting = { ClockTime = 17.6, Ambient = rgb(140, 100, 40), Tint = rgb(255, 220, 160), FogColor = rgb(255, 190, 120), FogEnd = 2500 },
	},
	{
		Id = "Aurora",
		Name = "COSMIC AURORA",
		Tagline = "Galaxy mutations (x8) rain from the sky",
		Icon = "🌌",
		Color = rgb(120, 60, 255),
		Duration = 120,
		Weight = 8,
		MeteorRate = 1.5,
		Luck = 1.5,
		CashMult = 1,
		Mutation = "Galaxy",
		MutationChance = 0.12,
		InfectChance = 0.005,
		Music = "music_event",
		Lighting = { ClockTime = 23.5, Ambient = rgb(60, 40, 140), Tint = rgb(200, 180, 255), FogColor = rgb(30, 10, 70), FogEnd = 1600 },
	},
	{
		Id = "Stampede",
		Name = "CASH STAMPEDE",
		Tagline = "Grab the orbs dropped in the crater!",
		Icon = "🦖",
		Color = rgb(90, 220, 110),
		Duration = 90,
		Weight = 18,
		MeteorRate = 1,
		Luck = 1,
		CashMult = 1,
		Lighting = { ClockTime = 13, Ambient = rgb(100, 120, 90), Tint = rgb(230, 255, 220), FogColor = rgb(200, 230, 200), FogEnd = 3000 },
	},
	{
		Id = "BossRaid",
		Name = "COLOSSAL RAID",
		Tagline = "A giant kaiju attacks the crater! Bonk it before it escapes!",
		Icon = "👹",
		Color = rgb(255, 45, 110),
		Duration = 180,
		Weight = 10,
		MeteorRate = 0,
		Luck = 1,
		CashMult = 1,
		Music = "music_boss",
		Lighting = { ClockTime = 19, Ambient = rgb(90, 30, 60), Tint = rgb(255, 190, 210), FogColor = rgb(60, 10, 40), FogEnd = 1200 },
	},
} :: { WorldEvent }

Events.ById = {} :: { [string]: WorldEvent }
for _, e in Events.List do
	Events.ById[e.Id] = e
end

-- Raid de boss
Events.Boss = {
	Health = 320, -- PV par joueur présent (mis à l'échelle au lancement)
	MinHealth = 380, -- faisable en solo en ~1 minute de bonks
	DamagePerBonk = 10,
	RewardGems = 30,
	TopEggRarity = "Mythic",
	EggChance = 0.25, -- chance d'œuf Légendaire pour chaque participant
}

-- Orbes de la Stampede
Events.Stampede = {
	OrbsPerWave = 14,
	WaveEvery = 6,
	OrbCashSeconds = 12, -- secondes de revenu par orbe
	OrbMinCash = 25,
}

return Events
