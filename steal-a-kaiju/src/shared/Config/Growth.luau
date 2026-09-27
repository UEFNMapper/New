--!strict
-- Croissance : 5 stades. La taille grandit physiquement, les revenus aussi,
-- mais plus un kaiju est gros, plus il est lent (et difficile) à voler.

export type Stage = {
	Index: number,
	Name: string,
	Scale: number, -- échelle du modèle
	IncomeMult: number,
	Carriers: number, -- joueurs nécessaires pour le porter
	CarrySpeed: number, -- multiplicateur de vitesse du porteur
	ToNext: number, -- secondes (à vitesse x1, rareté Commune) pour passer au stade suivant
	SellMult: number,
}

local Growth = {}

Growth.Stages = {
	{ Index = 1, Name = "Baby", Scale = 1, IncomeMult = 1, Carriers = 1, CarrySpeed = 0.85, ToNext = 60, SellMult = 0.5 },
	{ Index = 2, Name = "Teen", Scale = 1.45, IncomeMult = 2.5, Carriers = 1, CarrySpeed = 0.72, ToNext = 180, SellMult = 1.1 },
	{ Index = 3, Name = "Adult", Scale = 2.05, IncomeMult = 6, Carriers = 1, CarrySpeed = 0.58, ToNext = 600, SellMult = 2.4 },
	{ Index = 4, Name = "Titan", Scale = 2.9, IncomeMult = 15, Carriers = 2, CarrySpeed = 0.5, ToNext = 1800, SellMult = 5.5 },
	{ Index = 5, Name = "Colossus", Scale = 4, IncomeMult = 40, Carriers = 2, CarrySpeed = 0.42, ToNext = math.huge, SellMult = 13 },
} :: { Stage }

-- Les raretés élevées grandissent plus lentement.
Growth.RarityTimeMult = {
	Common = 1,
	Rare = 1.3,
	Epic = 1.7,
	Legendary = 2.2,
	Mythic = 3,
	Celestial = 4,
	Secret = 5,
} :: { [string]: number }

Growth.MaxStage = #Growth.Stages

function Growth.Get(stage: number): Stage
	return Growth.Stages[math.clamp(stage, 1, Growth.MaxStage)]
end

-- Secondes de croissance cumulées nécessaires pour atteindre `stage`.
function Growth.Threshold(stage: number, rarity: string): number
	local mult = Growth.RarityTimeMult[rarity] or 1
	local total = 0
	for i = 1, stage - 1 do
		total += Growth.Stages[i].ToNext * mult
	end
	return total
end

-- Stade atteint pour `growth` secondes cumulées.
function Growth.StageFor(growth: number, rarity: string): number
	local stage = 1
	for i = 2, Growth.MaxStage do
		if growth >= Growth.Threshold(i, rarity) then
			stage = i
		else
			break
		end
	end
	return stage
end

-- Progression 0..1 vers le prochain stade.
function Growth.Progress(growth: number, rarity: string): number
	local stage = Growth.StageFor(growth, rarity)
	if stage >= Growth.MaxStage then
		return 1
	end
	local a = Growth.Threshold(stage, rarity)
	local b = Growth.Threshold(stage + 1, rarity)
	return math.clamp((growth - a) / (b - a), 0, 1)
end

-- Secondes restantes avant le prochain stade (à vitesse x1).
function Growth.Remaining(growth: number, rarity: string): number
	local stage = Growth.StageFor(growth, rarity)
	if stage >= Growth.MaxStage then
		return 0
	end
	return math.max(0, Growth.Threshold(stage + 1, rarity) - growth)
end

return Growth
