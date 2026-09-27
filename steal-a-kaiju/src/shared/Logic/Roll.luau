--!strict
-- Tirages pondérés (raretés, espèces, mutations, roue). Pur et déterministe si
-- on lui passe un Random seedé.

local Config = script.Parent.Parent.Config
local Rarities = require(Config.Rarities)
local Kaijus = require(Config.Kaijus)
local Mutations = require(Config.Mutations)
local Worlds = require(Config.Worlds)

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
-- `worldId` : poids propres au monde (sinon ceux du cratère).
function Roll.RarityWeights(luck: number, worldId: string?): { number }
	local world = Worlds.Get(worldId)
	local weights = {}
	for i, r in Rarities.List do
		local w = world.Weights[r.Id] or 0
		if r.Order >= 3 and luck > 1 then
			w *= luck ^ (1 + (r.Order - 3) * 0.25)
		end
		weights[i] = w
	end
	return weights
end

-- Chances (0..1) par rareté pour l'affichage.
function Roll.RarityOdds(luck: number, worldId: string?): { [string]: number }
	local weights = Roll.RarityWeights(luck, worldId)
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

function Roll.Rarity(luck: number, rng: Rng?, worldId: string?): string
	local index = Roll.Weighted(Roll.RarityWeights(luck, worldId), rng)
	return Rarities.List[index].Id
end

-- Tirage « doré » : comme Roll.Rarity mais sans la rareté la plus fréquente du
-- monde (rareté supérieure garantie).
function Roll.GoldenRarity(luck: number, rng: Rng?, worldId: string?): string
	local weights = Roll.RarityWeights(luck, worldId)
	local top, topW = 0, -1
	for i, w in weights do
		if w > topW then
			top, topW = i, w
		end
	end
	weights[top] = 0
	return Rarities.List[Roll.Weighted(weights, rng)].Id
end

-- Espèces d'une rareté pour un monde : ses natives d'abord, sinon toutes celles
-- de cette rareté (un jackpot peut venir d'ailleurs).
function Roll.SpeciesPool(rarity: string, worldId: string?): { Kaijus.Species }
	local all = Kaijus.ByRarity[rarity] or {}
	if worldId then
		local native = {}
		for _, id in Worlds.Get(worldId).Species do
			local s = Kaijus.Get(id)
			if s and s.Rarity == rarity then
				table.insert(native, s)
			end
		end
		if #native > 0 then
			return native
		end
	end
	return all
end

-- Espèce aléatoire d'une rareté donnée (les moins chères sont plus fréquentes).
function Roll.Species(rarity: string, rng: Rng?, worldId: string?): string
	local pool = Roll.SpeciesPool(rarity, worldId)
	if #pool == 0 then
		pool = Kaijus.ByRarity.Common
	end
	local weights = {}
	for i, s in pool do
		weights[i] = 1 / math.sqrt(math.max(s.Income, 1))
	end
	return pool[Roll.Weighted(weights, rng)].Id
end

-- Mutation à l'éclosion. `bonus` = mutation d'événement { Id, Chance } éventuelle,
-- `local_` = mutations propres au monde d'origine de l'œuf.
function Roll.Mutation(luck: number, bonus: { Id: string, Chance: number }?, rng: Rng?, local_: { { Id: string, Chance: number } }?): string?
	if bonus and rand(rng) < math.min(0.9, bonus.Chance * math.sqrt(luck)) then
		return bonus.Id
	end
	if local_ then
		-- de la plus rare à la plus commune
		for i = #local_, 1, -1 do
			local m = local_[i]
			if rand(rng) < math.min(0.5, m.Chance * luck) then
				return m.Id
			end
		end
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
