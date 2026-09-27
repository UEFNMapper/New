--!strict
-- Tous les réglages chiffrés de l'économie, en un seul endroit.

local Economy = {}

Economy.StartCash = 100
Economy.StartGems = 10

-- Nids --------------------------------------------------------------------
-- Les nids se gagnent avec les niveaux (Config/Levels : NestLevels).
Economy.StartNests = 6
Economy.PassBonusNests = 3

-- Améliorations (achetées en cash) ----------------------------------------
export type Upgrade = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	MaxLevel: number,
	BasePrice: number,
	Growth: number,
	PerLevel: number,
}

Economy.Upgrades = {
	{ Id = "Shield", Name = "Shield Generator", Description = "+10s base shield duration", Icon = "🛡️", MaxLevel = 6, BasePrice = 900, Growth = 4.5, PerLevel = 10 },
	{ Id = "Sneakers", Name = "Rocket Sneakers", Description = "+2 walk speed", Icon = "👟", MaxLevel = 6, BasePrice = 600, Growth = 4, PerLevel = 2 },
	{ Id = "Muscles", Name = "Kaiju Muscles", Description = "+8% speed while carrying", Icon = "💪", MaxLevel = 6, BasePrice = 1200, Growth = 4.2, PerLevel = 0.08 },
	{ Id = "Bonker", Name = "Mega Bonker", Description = "+1.5 bonk range, faster swings", Icon = "🔨", MaxLevel = 6, BasePrice = 1000, Growth = 4, PerLevel = 1.5 },
	{ Id = "Reactor", Name = "Cash Reactor", Description = "+10% cash from all kaijus", Icon = "⚛️", MaxLevel = 10, BasePrice = 2500, Growth = 3.6, PerLevel = 0.1 },
} :: { Upgrade }

Economy.UpgradesById = {} :: { [string]: Upgrade }
for _, u in Economy.Upgrades do
	Economy.UpgradesById[u.Id] = u
end

function Economy.UpgradePrice(id: string, level: number): number
	local u = Economy.UpgradesById[id]
	return math.floor(u.BasePrice * u.Growth ^ level)
end

-- Bouclier ------------------------------------------------------------------
Economy.ShieldBase = 50
Economy.ShieldCooldown = 20 -- après la fin du bouclier avant de pouvoir le réactiver
Economy.NewPlayerProtection = 150 -- secondes de protection à l'arrivée

-- Vol -----------------------------------------------------------------------
Economy.StealMaxCarryTime = 75 -- au-delà, le kaiju rentre chez lui
Economy.HelperMaxDistance = 22 -- porteurs d'un Titan trop éloignés = il tombe
Economy.LiftWaitTime = 12 -- temps pour qu'un deuxième voleur aide à soulever
Economy.HelperCut = 0.2 -- part (en secondes de revenu x 60) donnée à l'aide
Economy.StealCooldown = 3

-- Bonk ----------------------------------------------------------------------
Economy.BonkRange = 9
Economy.BonkCooldown = 0.9
Economy.BonkKnockback = 70

-- Météores ------------------------------------------------------------------
Economy.MeteorInterval = 14 -- secondes entre deux météores dans le cratère
Economy.MeteorLifetime = 45 -- durée de vie d'un œuf non acheté
Economy.MeteorPads = 6
Economy.PersonalMeteorInterval = 150 -- météore perso sur ton île
Economy.PersonalMeteorLifetime = 60
Economy.FreeFirstEggMaxOrder = 2 -- le tout premier œuf acheté est offert s'il est Commun ou Rare

-- Collecteur ----------------------------------------------------------------
Economy.OfflineMaxHours = 3
Economy.OfflineMaxHoursPass = 8
Economy.OfflineRate = 0.5

-- Nourriture : saute une partie (Cut) du temps restant du stade.
-- Prix = revenu/s actuel x secondes sautées x Ratio (moins cher en gros).
export type Food = { Id: string, Name: string, Icon: string, Ratio: number, Cut: number, MinPrice: number }
Economy.Foods = {
	{ Id = "Snack", Name = "Kaiju Snack", Icon = "🍖", Ratio = 1, Cut = 0.15, MinPrice = 40 },
	{ Id = "Feast", Name = "Monster Feast", Icon = "🍗", Ratio = 0.9, Cut = 0.4, MinPrice = 250 },
	{ Id = "Steak", Name = "Meteor Steak", Icon = "🥩", Ratio = 0.8, Cut = 1, MinPrice = 1200 },
} :: { Food }

Economy.FoodsById = {} :: { [string]: Food }
for _, f in Economy.Foods do
	Economy.FoodsById[f.Id] = f
end

-- Vente -------------------------------------------------------------------
Economy.SellBase = 0.6 -- x prix d'achat (ou revenu x 250 pour les Secrets)

-- Rebirth (Évolution) -------------------------------------------------------
export type Rebirth = { Cost: number, NeedRarity: string, Mult: number, Luck: number, Gems: number, EggRarity: string }
Economy.Rebirths = {} :: { Rebirth }
do
	local needs = { "Epic", "Epic", "Legendary", "Legendary", "Legendary", "Mythic", "Mythic", "Mythic", "Celestial", "Celestial" }
	local eggs = { "Rare", "Epic", "Epic", "Legendary", "Legendary", "Legendary", "Mythic", "Mythic", "Mythic", "Celestial" }
	for i = 1, 25 do
		table.insert(Economy.Rebirths, {
			Cost = math.floor(8000000 * 6 ^ (i - 1)),
			NeedRarity = needs[math.min(i, #needs)],
			Mult = 1 + 0.5 * i, -- multiplicateur cumulé après ce rebirth
			Luck = 1 + 0.1 * i,
			Gems = 25 * i,
			EggRarity = eggs[math.min(i, #eggs)],
		})
	end
end

-- Chance & multiplicateurs -------------------------------------------------
Economy.FriendBoostPer = 0.1
Economy.FriendBoostMax = 0.4
Economy.PremiumBoost = 0.1
Economy.GroupBoost = 0.05
Economy.IndexBoostPerSpecies = 0.01

-- Potions (achetées en gemmes) -------------------------------------------
export type Potion = { Id: string, Name: string, Icon: string, Duration: number, GemPrice: number, Description: string }
Economy.Potions = {
	{ Id = "Luck", Name = "Luck Potion", Icon = "🍀", Duration = 600, GemPrice = 15, Description = "x2 personal luck for 10 min" },
	{ Id = "Growth", Name = "Growth Potion", Icon = "🌱", Duration = 600, GemPrice = 20, Description = "x2 growth speed for 10 min" },
	{ Id = "Cash", Name = "Cash Potion", Icon = "💸", Duration = 600, GemPrice = 25, Description = "x2 cash for 10 min" },
} :: { Potion }
Economy.PotionsById = {} :: { [string]: Potion }
for _, p in Economy.Potions do
	Economy.PotionsById[p.Id] = p
end

-- Roue ----------------------------------------------------------------------
Economy.FreeSpinCooldown = 4 * 3600
Economy.SpinGemPrice = 12

return Economy
