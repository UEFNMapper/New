--!strict
-- Formules de l'économie (pures, partagées client/serveur, testées).

local Config = script.Parent.Parent.Config
local Kaijus = require(Config.Kaijus)
local Growth = require(Config.Growth)
local Mutations = require(Config.Mutations)
local Economy = require(Config.Economy)
local Levels = require(Config.Levels)

local Calc = {}

export type KaijuRecord = {
	Uid: string,
	Species: string?,
	Rarity: string,
	Mutation: string?,
	Growth: number,
	Nest: number,
	Egg: boolean?,
	HatchAt: number?,
	Born: number?,
	World: string?, -- monde d'origine de l'œuf
}

export type Multipliers = {
	Rebirths: number,
	Reactor: number,
	VIP: boolean,
	DoubleCash: boolean,
	Friends: number,
	Premium: boolean,
	Group: boolean,
	IndexCount: number,
	CashPotion: boolean,
	EventCash: number,
	Level: number?,
}

function Calc.DefaultMultipliers(): Multipliers
	return {
		Rebirths = 0,
		Reactor = 0,
		VIP = false,
		DoubleCash = false,
		Friends = 0,
		Premium = false,
		Group = false,
		IndexCount = 0,
		CashPotion = false,
		EventCash = 1,
	}
end

function Calc.RebirthMult(rebirths: number): number
	if rebirths <= 0 then
		return 1
	end
	local r = Economy.Rebirths[math.min(rebirths, #Economy.Rebirths)]
	return r.Mult
end

function Calc.RebirthLuck(rebirths: number): number
	if rebirths <= 0 then
		return 1
	end
	return Economy.Rebirths[math.min(rebirths, #Economy.Rebirths)].Luck
end

-- Multiplicateur global de cash d'un joueur.
function Calc.CashMultiplier(m: Multipliers): number
	local additive = 1
	additive += m.Reactor * Economy.UpgradesById.Reactor.PerLevel
	additive += math.min(m.Friends * Economy.FriendBoostPer, Economy.FriendBoostMax)
	if m.VIP then
		additive += 0.2
	end
	if m.Premium then
		additive += Economy.PremiumBoost
	end
	if m.Group then
		additive += Economy.GroupBoost
	end
	additive += m.IndexCount * Economy.IndexBoostPerSpecies
	additive += math.max(0, (m.Level or 1) - 1) * Levels.CashPerLevel

	local mult = additive * Calc.RebirthMult(m.Rebirths)
	if m.DoubleCash then
		mult *= 2
	end
	if m.CashPotion then
		mult *= 2
	end
	mult *= m.EventCash
	return mult
end

-- Revenu brut d'un kaiju (sans les multiplicateurs du joueur).
function Calc.BaseIncome(rec: KaijuRecord): number
	if rec.Egg or not rec.Species then
		return 0
	end
	local species = Kaijus.Get(rec.Species)
	if not species then
		return 0
	end
	local stage = Growth.Get(Growth.StageFor(rec.Growth, species.Rarity))
	return species.Income * stage.IncomeMult * Mutations.Mult(rec.Mutation)
end

function Calc.Stage(rec: KaijuRecord): number
	if rec.Egg or not rec.Species then
		return 1
	end
	return Growth.StageFor(rec.Growth, rec.Rarity)
end

-- Valeur de revente.
function Calc.SellValue(rec: KaijuRecord): number
	if rec.Egg or not rec.Species then
		return 0
	end
	local species = Kaijus.Get(rec.Species)
	if not species then
		return 0
	end
	local base = if species.Price > 0 then species.Price else species.Income * 250
	local stage = Growth.Get(Growth.StageFor(rec.Growth, species.Rarity))
	return math.floor(base * Economy.SellBase * stage.SellMult * Mutations.Mult(rec.Mutation))
end

-- Prix d'une nourriture pour ce kaiju.
function Calc.FoodPrice(rec: KaijuRecord, foodId: string): number
	local food = Economy.FoodsById[foodId]
	if not food then
		return math.huge
	end
	local skipped = Growth.Remaining(rec.Growth, rec.Rarity) * food.Cut
	return math.max(food.MinPrice, math.floor(Calc.BaseIncome(rec) * skipped * food.Ratio))
end

-- Secondes de croissance gagnées en mangeant.
function Calc.FoodGrowth(rec: KaijuRecord, foodId: string): number
	local food = Economy.FoodsById[foodId]
	if not food or not rec.Species then
		return 0
	end
	local remaining = Growth.Remaining(rec.Growth, rec.Rarity)
	return remaining * food.Cut
end

-- Montant d'une récompense « Cash » exprimée en secondes de revenu.
function Calc.CashReward(seconds: number, incomePerSecond: number, minCash: number?): number
	return math.max(minCash or 0, math.floor(seconds * incomePerSecond))
end

-- Puissance d'un kaiju en combat (défense de l'île, Rampage, compagnon) :
-- grandir le rend plus fort, la rareté et la mutation aussi.
function Calc.Power(rec: KaijuRecord): number
	if rec.Egg or not rec.Species then
		return 0
	end
	local stage = Growth.Get(Calc.Stage(rec))
	local rarityPower = Growth.RarityTimeMult[rec.Rarity] or 1
	local mutation = 1 + 0.1 * (Mutations.Mult(rec.Mutation) - 1)
	return math.sqrt(stage.IncomeMult) * rarityPower * mutation
end

-- Coût du prochain rebirth (nil si max atteint).
function Calc.NextRebirth(rebirths: number): Economy.Rebirth?
	return Economy.Rebirths[rebirths + 1]
end

function Calc.MaxNests(baseNests: number, hasPass: boolean): number
	return baseNests + (if hasPass then Economy.PassBonusNests else 0)
end

return Calc
