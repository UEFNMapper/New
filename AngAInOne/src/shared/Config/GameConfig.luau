--!strict
--[[
	GameConfig : toutes les constantes d'équilibrage et de gameplay au même endroit.
	Les valeurs économiques sont vérifiées par tests/pacing.spec.luau.
]]

local GameConfig = {}

GameConfig.DataStoreName = "AngAInOne_PlayerData_v1"

-- Économie de base
GameConfig.LevelGrowth = 1.12
GameConfig.Milestones = table.freeze({ 10, 25, 50, 100, 150, 200 })
GameConfig.MaxModuleLevel = 250
GameConfig.TickSeconds = 1
GameConfig.CollectorCapSeconds = 900 -- le collecteur stocke au maximum 15 min de production
GameConfig.StartingBits = 0

-- Énergie (bloc d'alimentation, amélioré dans La Centrale)
GameConfig.Power = table.freeze({
	BaseCapacity = 60,
	CapacityGrowth = 1.2,
	BaseCost = 15,
	CostGrowth = 1.45,
	MaxLevel = 120,
})

-- Refroidissement : ventirad d'origine + radiateurs améliorés dans la Cryo Tower
GameConfig.Cooling = table.freeze({
	BaseCapacity = 2500,
	CapacityGrowth = 1.2,
	BaseCost = 2e8,
	CostGrowth = 1.45,
	UnlockZone = 4,
	MaxLevel = 120,
	HeatStartsAtZone = 3, -- la chaleur n'est comptée qu'à partir du SSD (tutoriel progressif)
})

-- Prestige
GameConfig.Reboot = table.freeze({
	RequiredZone = 6, -- GPU débloqué
	FirmwareDivisor = 1e11,
	FirmwarePerPoint = 0.1,
	MinFirmwareGain = 1,
})
-- La Singularité se construit en 5 phases dans l'AI Core (un objectif régulier en fin de run).
GameConfig.SingularityPhases = table.freeze({ 1e16, 5e16, 1.5e17, 3e17, 5e17 })
GameConfig.SingularityCost = 1e18 -- ≈ somme des phases, utilisé par la simulation de pacing

-- Hors ligne
GameConfig.Offline = table.freeze({
	BaseCapSeconds = 2 * 3600,
	BaseRatio = 0.5,
	PassCapSeconds = 8 * 3600,
	PassRatio = 1.0,
	MinSecondsToReport = 60,
})

-- Overclock (débloqué avec le CPU)
GameConfig.Overclock = table.freeze({
	RequiredZone = 5,
	Duration = 180,
	Cooldown = 300,
	ProPassDurationMult = 1.5,
	ProPassCooldownMult = 0.5,
	PerfectMult = 2,
	GoodMult = 1.5,
	HeatMult = 1.3,
	NeedlePeriod = 1.6, -- secondes pour un aller-retour complet de l'aiguille
	GoodHalfWidth = 0.14, -- demi-largeur de la zone "bien" (en fraction de jauge)
	PerfectHalfWidth = 0.05,
	MaxAttemptSeconds = 12,
})

-- Virus / Glitches
GameConfig.Virus = table.freeze({
	MinInterval = 90,
	MaxInterval = 150,
	MaxAlive = 3,
	LifeSeconds = 120,
	RewardProductionSeconds = 25,
	ChipChance = 0.12,
	ChipReward = 5,
	ZapDistance = 14,
})

-- Nanobots
GameConfig.Nanobots = table.freeze({
	BaseSlots = 3,
	PassExtraSlots = 2,
	MaxInventory = 150,
	FuseCount = 5,
	GoldenMult = 1.5,
})

-- Social et bonus
GameConfig.FriendBoostPer = 0.10
GameConfig.FriendBoostMax = 0.30
GameConfig.PremiumBoost = 0.10
GameConfig.VipChipBonus = 0.10
GameConfig.FragmentBonus = 0.01 -- +1 % par fragment trouvé
GameConfig.ServerBoostSeconds = 15 * 60
GameConfig.BitsBoostPotionSeconds = 30 * 60
GameConfig.GroupId = 0 -- ID du groupe Roblox pour le bonus de groupe (0 = désactivé)
GameConfig.GroupBoost = 0.05

-- Téléchargements (rendez-vous)
export type DownloadKind = { Id: string, Name: string, Seconds: number, ProductionSeconds: number, Chips: number }
GameConfig.Downloads = table.freeze({
	table.freeze({ Id = "Patch", Name = "Patch rapide", Seconds = 30 * 60, ProductionSeconds = 20 * 60, Chips = 10 }),
	table.freeze({
		Id = "Driver",
		Name = "Pilote graphique",
		Seconds = 4 * 3600,
		ProductionSeconds = 100 * 60,
		Chips = 40,
	}),
	table.freeze({
		Id = "OS",
		Name = "Mise à jour système",
		Seconds = 8 * 3600,
		ProductionSeconds = 180 * 60,
		Chips = 80,
	}),
} :: { DownloadKind })
GameConfig.DownloadRequiredZone = 3

-- Anti-abus (limites par joueur et par remote)
GameConfig.RateLimits = table.freeze({
	Default = table.freeze({ Rate = 4, Burst = 8 }),
	Upgrade = table.freeze({ Rate = 12, Burst = 20 }),
	Settings = table.freeze({ Rate = 1, Burst = 3 }),
})
GameConfig.InteractDistance = 40 -- distance max (studs) pour interagir avec un module

-- Onboarding (étapes loggées dans le funnel AnalyticsService)
GameConfig.TutorialSteps = table.freeze({
	"Spawn",
	"PowerOn",
	"FirstCollect",
	"FirstUpgrade",
	"SecondUpgrade",
	"UnlockRam",
	"FirstCapsule",
	"Done",
})

return table.freeze(GameConfig)
