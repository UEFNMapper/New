--!strict
-- Structure des données sauvegardées d'un joueur.

local Config = script.Parent.Parent.Config
local Economy = require(Config.Economy)

local DataTemplate = {
	Version = 1,

	Cash = Economy.StartCash,
	Gems = Economy.StartGems,
	TotalEarned = 0,
	Rebirths = 0,
	Nests = Economy.StartNests, -- nids achetés (ancienne V1) ; les niveaux en donnent aussi
	Xp = 0, -- XP cumulée (le niveau s'en déduit, jamais remis à zéro)
	Level = 1,
	Worlds = { Crater = true }, -- mondes débloqués
	Siege = { Wave = 1, Best = 0, Cleared = 0 }, -- défense de l'île
	Rampage = { Stars = {}, Best = 0, Runs = 0 }, -- [quartier] = étoiles
	Buddy = { Uid = "", Xp = 0 }, -- compagnon
	Stored = 0, -- cash en attente dans le réacteur de la base

	Kaijus = {}, -- { KaijuRecord }
	PendingEggs = {}, -- raretés en attente d'un nid libre
	NextUid = 1,

	Upgrades = { Shield = 0, Sneakers = 0, Muscles = 0, Bonker = 0, Reactor = 0 },
	Potions = { Luck = 0, Growth = 0, Cash = 0 },
	Boosts = { Luck = 0, Growth = 0, Cash = 0 }, -- fin (os.time)

	Index = {}, -- [speciesId] = { [mutationId | "Normal"] = true }

	Daily = { Streak = 0, LastDay = 0, Cycle = 0 },
	Quests = { Day = 0, List = {}, BonusClaimed = false },
	Codes = {},

	Stats = {
		Steals = 0,
		Stolen = 0,
		EggsBought = 0,
		Hatches = 0,
		Fusions = 0,
		Bonks = 0,
		Saves = 0,
		Feeds = 0,
		StageUps = 0,
		Collects = 0,
		Orbs = 0,
		BossDamage = 0,
		PlaySeconds = 0,
		Locks = 0,
		SiegeWaves = 0,
		SiegeKills = 0,
		Rampages = 0,
		Smashed = 0,
		Digs = 0,
		Worlds = 0,
	},

	Settings = { Music = true, Sfx = true, LowFx = false, MusicVolume = 0.6, SfxVolume = 0.6 },

	Spins = 1,
	FreeSpinAt = 0,
	Tutorial = 0,
	GoldenCount = 0, -- météores perso tombés (1 sur 5 est doré)
	LastOnline = 0,
	GroupClaimed = false,
	StarterPack = false,
	Receipts = {},
	StudioPasses = {}, -- gamepasses simulés dans Studio (tests)
}

return DataTemplate
