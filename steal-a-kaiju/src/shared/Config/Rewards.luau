--!strict
-- Récompenses : quotidiennes, temps de jeu, roue, quêtes, codes, groupe.
-- Une récompense est une table { Kind, Amount?, Id?, Rarity? } :
--   Cash (Amount = secondes de revenu, min MinCash) | Gems | Potion (Id) | Egg (Rarity) | Spins

export type Reward = {
	Kind: string,
	Amount: number?,
	Id: string?,
	Rarity: string?,
	MinCash: number?,
}

local Rewards = {}

-- Série quotidienne (7 jours, en boucle ; l'œuf du jour 7 monte en rareté à chaque cycle)
Rewards.Daily = {
	{ Kind = "Cash", Amount = 120, MinCash = 250 },
	{ Kind = "Gems", Amount = 15 },
	{ Kind = "Potion", Id = "Luck", Amount = 1 },
	{ Kind = "Gems", Amount = 30 },
	{ Kind = "Potion", Id = "Growth", Amount = 2 },
	{ Kind = "Cash", Amount = 900, MinCash = 3000 },
	{ Kind = "Egg", Rarity = "Epic" },
} :: { Reward }
Rewards.DailyEggByCycle = { "Epic", "Legendary", "Legendary", "Mythic" }

-- Cadeaux de temps de jeu (minutes de session)
Rewards.Playtime = {
	{ Minutes = 1, Reward = { Kind = "Cash", Amount = 60, MinCash = 100 } },
	{ Minutes = 3, Reward = { Kind = "Gems", Amount = 5 } },
	{ Minutes = 6, Reward = { Kind = "Potion", Id = "Growth", Amount = 1 } },
	{ Minutes = 10, Reward = { Kind = "Cash", Amount = 300, MinCash = 800 } },
	{ Minutes = 15, Reward = { Kind = "Gems", Amount = 15 } },
	{ Minutes = 20, Reward = { Kind = "Potion", Id = "Luck", Amount = 1 } },
	{ Minutes = 30, Reward = { Kind = "Egg", Rarity = "Epic" } },
	{ Minutes = 40, Reward = { Kind = "Spins", Amount = 2 } },
	{ Minutes = 50, Reward = { Kind = "Gems", Amount = 40 } },
	{ Minutes = 60, Reward = { Kind = "Egg", Rarity = "Legendary" } },
} :: { { Minutes: number, Reward: Reward } }

-- Roue de la fortune : Weight = poids (les chances sont affichées en jeu)
Rewards.Wheel = {
	{ Weight = 26, Label = "Cash", Color = Color3.fromRGB(90, 220, 110), Reward = { Kind = "Cash", Amount = 300, MinCash = 500 } },
	{ Weight = 20, Label = "10 Gems", Color = Color3.fromRGB(80, 200, 255), Reward = { Kind = "Gems", Amount = 10 } },
	{ Weight = 14, Label = "Luck", Color = Color3.fromRGB(120, 255, 140), Reward = { Kind = "Potion", Id = "Luck", Amount = 1 } },
	{ Weight = 14, Label = "Growth", Color = Color3.fromRGB(190, 255, 90), Reward = { Kind = "Potion", Id = "Growth", Amount = 1 } },
	{ Weight = 10, Label = "Big Cash", Color = Color3.fromRGB(40, 180, 70), Reward = { Kind = "Cash", Amount = 1500, MinCash = 4000 } },
	{ Weight = 8, Label = "40 Gems", Color = Color3.fromRGB(60, 120, 255), Reward = { Kind = "Gems", Amount = 40 } },
	{ Weight = 5, Label = "Legendary Egg", Color = Color3.fromRGB(255, 176, 32), Reward = { Kind = "Egg", Rarity = "Legendary" } },
	{ Weight = 2.4, Label = "Mythic Egg", Color = Color3.fromRGB(255, 45, 110), Reward = { Kind = "Egg", Rarity = "Mythic" } },
	{ Weight = 0.6, Label = "CELESTIAL", Color = Color3.fromRGB(80, 255, 230), Reward = { Kind = "Egg", Rarity = "Celestial" } },
} :: { { Weight: number, Label: string, Color: Color3, Reward: Reward } }

-- Quêtes quotidiennes : 3 tirées chaque jour dans ce pool
export type QuestDef = { Id: string, Text: string, Stat: string, Goal: number, Reward: Reward, MinLevel: number? }
Rewards.Quests = {
	{ Id = "Buy3", Text = "Buy %d meteor eggs", Stat = "EggsBought", Goal = 3, Reward = { Kind = "Gems", Amount = 10 } },
	{ Id = "Buy8", Text = "Buy %d meteor eggs", Stat = "EggsBought", Goal = 8, Reward = { Kind = "Gems", Amount = 25 } },
	{ Id = "Waves3", Text = "Defend your island %d times", Stat = "SiegeWaves", Goal = 3, Reward = { Kind = "Gems", Amount = 15 } },
	{ Id = "Kills30", Text = "Defeat %d invaders", Stat = "SiegeKills", Goal = 30, Reward = { Kind = "Potion", Id = "Luck", Amount = 1 } },
	{ Id = "Rampage2", Text = "Play %d Rampages", Stat = "Rampages", Goal = 2, Reward = { Kind = "Gems", Amount = 20 } },
	{ Id = "Smash80", Text = "Smash %d buildings", Stat = "Smashed", Goal = 80, Reward = { Kind = "Cash", Amount = 600, MinCash = 1500 } },
	{ Id = "Dig3", Text = "Dig up %d treasures", Stat = "Digs", Goal = 3, Reward = { Kind = "Spins", Amount = 1 } },
	{ Id = "Feed5", Text = "Feed your kaijus %d times", Stat = "Feeds", Goal = 5, Reward = { Kind = "Potion", Id = "Growth", Amount = 1 } },
	{ Id = "Grow3", Text = "Grow kaijus %d stages", Stat = "StageUps", Goal = 3, Reward = { Kind = "Gems", Amount = 15 } },
	{ Id = "Fuse1", Text = "Fuse %d kaijus", Stat = "Fusions", Goal = 1, Reward = { Kind = "Gems", Amount = 25 }, MinLevel = 6 },
	{ Id = "Collect", Text = "Collect cash %d times", Stat = "Collects", Goal = 10, Reward = { Kind = "Cash", Amount = 600, MinCash = 1500 } },
	{ Id = "Hatch", Text = "Hatch %d eggs", Stat = "Hatches", Goal = 5, Reward = { Kind = "Spins", Amount = 1 } },
} :: { QuestDef }
Rewards.QuestsPerDay = 3
Rewards.AllQuestsBonus = { Kind = "Egg", Rarity = "Legendary" } :: Reward

-- Codes (à mettre à jour à chaque mise à jour du jeu)
Rewards.Codes = {
	RELEASE = { { Kind = "Gems", Amount = 50 } },
	KAIJU = { { Kind = "Potion", Id = "Luck", Amount = 2 } },
	STOMP = { { Kind = "Cash", Amount = 600, MinCash = 2000 } },
	METEOR = { { Kind = "Egg", Rarity = "Epic" } },
} :: { [string]: { Reward } }

-- Groupe Roblox (0 = désactivé)
Rewards.GroupId = 0
Rewards.GroupReward = { { Kind = "Gems", Amount = 100 }, { Kind = "Potion", Id = "Cash", Amount = 1 } } :: { Reward }

return Rewards
