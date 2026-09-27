--!strict
-- Tirages pondérés (raretés, espèces, mutations, roue). Pur et déterministe si
-- on lui passe un Random seedé.

local Config = script.Parent.Parent.Config
local Rarities = require(Config.Rarities)
local Kaijus = require(Config.Kaijus)
local Mutations = require(Config.Mutations)

local Roll = {}

export type Rng = { NextNumber: (self: any, min: number?, max: number?) -> number }

local function rand(rng: Rng?): number
	if rng then
		return rng:NextNumber()
	end
	return math.random()
end

-- Choisit un index selon des poids.
function Roll.Weighted(weights: { number }, rng: Rng?): number
	local total = 0
	for _, w in weights do
		total += math.max(0, w)
	end
	if total <= 0 then
		return 1
	end
	local pick = rand(rng) * total
	for i, w in weights do
		pick -= math.max(0, w)
		if pick <= 0 then
			return i
		end
	end
	return #weights
end

-- Poids effectifs des raretés avec un facteur de chance : la chance multiplie
-- les poids des raretés Épique et au-delà (plus fortement pour les plus rares).
function Roll.RarityWeights(luck: number): { number }
	local weights = {}
	for i, r in Rarities.List do
		local w = r.Weight
		if r.Order >= 3 and luck > 1 then
			w *= luck ^ (1 + (r.Order - 3) * 0.25)
		end
		weights[i] = w
	end
	return weights
end

-- Chances (0..1) par rareté pour l'affichage.
function Roll.RarityOdds(luck: number): { [string]: number }
	local weights = Roll.RarityWeights(luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local odds = {}
	for i, r in Rarities.List do
		odds[r.Id] = if total > 0 then weights[i] / total else 0
	end
	return odds
end

function Roll.Rarity(luck: number, rng: Rng?): string
	local index = Roll.Weighted(Roll.RarityWeights(luck), rng)
	return Rarities.List[index].Id
end

-- Espèce aléatoire d'une rareté donnée (les moins chères sont plus fréquentes).
function Roll.Species(rarity: string, rng: Rng?): string
	local pool = Kaijus.ByRarity[rarity]
	if not pool or #pool == 0 then
		pool = Kaijus.ByRarity.Common
	end
	local weights = {}
	for i, s in pool do
		weights[i] = 1 / math.sqrt(math.max(s.Income, 1))
	end
	return pool[Roll.Weighted(weights, rng)].Id
end

-- Mutation à l'éclosion. `bonus` = mutation d'événement { Id, Chance } éventuelle.
function Roll.Mutation(luck: number, bonus: { Id: string, Chance: number }?, rng: Rng?): string?
	if bonus and rand(rng) < math.min(0.9, bonus.Chance * math.sqrt(luck)) then
		return bonus.Id
	end
	-- Des plus rares aux plus communes
	for i = #Mutations.List, 1, -1 do
		local m = Mutations.List[i]
		if m.Chance > 0 and rand(rng) < math.min(0.5, m.Chance * luck) then
			return m.Id
		end
	end
	return nil
end

return Roll
