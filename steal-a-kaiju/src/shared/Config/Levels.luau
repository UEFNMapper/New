--!strict
-- Niveau du joueur : la colonne vertébrale de la progression solo.
-- Le niveau n'est jamais remis à zéro (pas même par l'Évolution). Chaque action
-- donne de l'XP ; chaque niveau donne une récompense et parfois un déblocage.

export type Unlock = {
	Level: number,
	Kind: string, -- "Nest" | "World" | "Menu" | "Feature"
	Id: string?,
	Text: string,
	Icon: string,
}

local Worlds = require(script.Parent.Worlds)

local Levels = {}

Levels.Max = 100

-- XP pour passer du niveau L au niveau L+1.
function Levels.XpToNext(level: number): number
	return math.floor(40 * level * 1.08 ^ level)
end

-- XP cumulée nécessaire pour atteindre `level`.
function Levels.TotalFor(level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += Levels.XpToNext(l)
	end
	return total
end

-- Niveau atteint pour une XP cumulée + progression 0..1 vers le suivant.
function Levels.FromXp(xp: number): (number, number, number, number)
	local level = 1
	local spent = 0
	while level < Levels.Max do
		local need = Levels.XpToNext(level)
		if xp < spent + need then
			return level, (xp - spent) / need, xp - spent, need
		end
		spent += need
		level += 1
	end
	return Levels.Max, 1, 0, 0
end

-- XP gagnée par action -------------------------------------------------------
Levels.HatchXp = {
	Common = 10,
	Rare = 20,
	Epic = 40,
	Legendary = 100,
	Mythic = 250,
	Celestial = 600,
	Secret = 1500,
} :: { [string]: number }

-- Multiplicateur de l'XP d'éclosion quand un kaiju atteint ce stade.
Levels.StageXpMult = { [2] = 0.5, [3] = 1, [4] = 2, [5] = 4 } :: { [number]: number }
Levels.NewSpeciesMult = 5 -- bonus : première fois qu'on obtient une espèce
Levels.NewMutationXp = 50

Levels.Xp = {
	Mission = 60,
	Quest = 150,
	QuestBonus = 500,
	Dig = 8,
	SiegeKill = 1,
	SiegeWave = 20, -- + 3 x numéro de vague
	SiegeAlpha = 120,
	RampageStar = 30,
	Steal = 60,
	Save = 60,
	BossHit = 2,
	BossWin = 200,
	WorldUnlock = 400,
	Fusion = 150,
	Rebirth = 1000,
}

-- Nids gagnés avec les niveaux (6 au départ, 16 au niveau 30).
Levels.NestLevels = { 2, 4, 6, 8, 10, 13, 16, 20, 25, 30 }
Levels.StartNests = 6

function Levels.NestsFor(level: number): number
	local n = Levels.StartNests
	for _, l in Levels.NestLevels do
		if level >= l then
			n += 1
		end
	end
	return n
end

-- Menus débloqués par le niveau (en plus du tutoriel).
Levels.MenuLevels = {
	Worlds = 3,
	Fusion = 6,
	Rebirth = 10,
} :: { [string]: number }

-- Bonus permanent de cash par niveau (additif).
Levels.CashPerLevel = 0.01

-- Récompense de chaque niveau : gemmes, et un œuf tous les 5 niveaux.
function Levels.Reward(level: number): { Gems: number, Egg: string? }
	local egg: string? = nil
	if level % 5 == 0 then
		if level >= 40 then
			egg = "Mythic"
		elseif level >= 25 then
			egg = "Legendary"
		elseif level >= 10 then
			egg = "Epic"
		else
			egg = "Rare"
		end
	end
	return { Gems = 4 + level, Egg = egg }
end

-- Liste des déblocages, pour l'écran et la barre « NEXT GOAL ».
Levels.Unlocks = {} :: { Unlock }
do
	for _, l in Levels.NestLevels do
		table.insert(Levels.Unlocks, { Level = l, Kind = "Nest", Text = "+1 NEST", Icon = "nest" })
	end
	table.insert(Levels.Unlocks, { Level = 3, Kind = "Menu", Id = "Worlds", Text = "WORLD MAP", Icon = "worlds" })
	table.insert(Levels.Unlocks, { Level = 6, Kind = "Menu", Id = "Fusion", Text = "FUSION LAB", Icon = "fusion" })
	table.insert(Levels.Unlocks, { Level = 10, Kind = "Menu", Id = "Rebirth", Text = "EVOLUTION", Icon = "evolve" })
	for _, w in Worlds.List do
		if w.Level > 1 then
			table.insert(Levels.Unlocks, { Level = w.Level, Kind = "World", Id = w.Id, Text = string.upper(w.Name), Icon = "worlds" })
		end
	end
	-- les mondes d'abord quand plusieurs déblocages tombent au même niveau
	local rank = { World = 1, Menu = 2, Feature = 3, Nest = 4 }
	table.sort(Levels.Unlocks, function(a, b)
		if a.Level == b.Level then
			return (rank[a.Kind] or 9) < (rank[b.Kind] or 9)
		end
		return a.Level < b.Level
	end)
end

-- Déblocages obtenus exactement à ce niveau.
function Levels.UnlocksAt(level: number): { Unlock }
	local out = {}
	for _, u in Levels.Unlocks do
		if u.Level == level then
			table.insert(out, u)
		end
	end
	return out
end

-- Prochain déblocage strictement après `level`.
function Levels.NextUnlock(level: number): Unlock?
	for _, u in Levels.Unlocks do
		if u.Level > level then
			return u
		end
	end
	return nil
end

return Levels
