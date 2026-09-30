--!strict
--[[
	Nanobots : les compagnons à collectionner, et les capsules qui les contiennent.
	Les probabilités sont affichées au joueur telles quelles (obligation Roblox pour les
	objets aléatoires payants, et bonne pratique pour tous les autres).
]]

export type Rarity = string -- "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type BonusKind = string -- "Bits" | "Power" | "Cooling" | "Speed"

export type NanobotDef = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Capsule: string,
	Bonus: BonusKind,
	Value: number, -- Bits : +x (0.05 = +5 %) ; Power/Cooling : -x ; Speed : +studs/s
	Color: string, -- hex
}

export type CapsuleDef = {
	Id: string,
	Name: string,
	RequiredZone: number,
	Currency: string, -- "Bits" | "Chips"
	-- Bits : coût = ProductionSeconds x production actuelle (avec un plancher) ; Chips : coût fixe.
	ProductionSeconds: number,
	MinBits: number,
	ChipsCost: number,
	Paid: boolean, -- true si achetable (même indirectement) avec des Robux -> soumis à PolicyService
	Odds: { { key: string, weight: number } },
}

local RARITY_ORDER: { Rarity } = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
local RARITY_NAMES: { [string]: string } = {
	Common = "Commun",
	Rare = "Rare",
	Epic = "Épique",
	Legendary = "Légendaire",
	Mythic = "Mythique",
}

local BONUS_BY_RARITY: { [string]: { [string]: number } } = {
	Bits = { Common = 0.05, Rare = 0.12, Epic = 0.25, Legendary = 0.5, Mythic = 1.0 },
	Power = { Common = 0.03, Rare = 0.06, Epic = 0.1, Legendary = 0.15, Mythic = 0.25 },
	Cooling = { Common = 0.03, Rare = 0.06, Epic = 0.1, Legendary = 0.15, Mythic = 0.25 },
	Speed = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 6 },
}

local STANDARD_ODDS = {
	{ key = "Common", weight = 60 },
	{ key = "Rare", weight = 28 },
	{ key = "Epic", weight = 9 },
	{ key = "Legendary", weight = 2.7 },
	{ key = "Mythic", weight = 0.3 },
}

local PREMIUM_ODDS = {
	{ key = "Rare", weight = 50 },
	{ key = "Epic", weight = 35 },
	{ key = "Legendary", weight = 12 },
	{ key = "Mythic", weight = 3 },
}

local capsules: { CapsuleDef } = {
	{
		Id = "Bronze",
		Name = "Capsule Mémoire",
		RequiredZone = 2,
		Currency = "Bits",
		ProductionSeconds = 300,
		MinBits = 1500,
		ChipsCost = 0,
		Paid = false,
		Odds = STANDARD_ODDS,
	},
	{
		Id = "Vault",
		Name = "Capsule NAND",
		RequiredZone = 3,
		Currency = "Bits",
		ProductionSeconds = 300,
		MinBits = 1e6,
		ChipsCost = 0,
		Paid = false,
		Odds = STANDARD_ODDS,
	},
	{
		Id = "Cryo",
		Name = "Capsule Cryo",
		RequiredZone = 4,
		Currency = "Bits",
		ProductionSeconds = 300,
		MinBits = 1e8,
		ChipsCost = 0,
		Paid = false,
		Odds = STANDARD_ODDS,
	},
	{
		Id = "Neural",
		Name = "Capsule Neural",
		RequiredZone = 6,
		Currency = "Bits",
		ProductionSeconds = 300,
		MinBits = 1e11,
		ChipsCost = 0,
		Paid = false,
		Odds = STANDARD_ODDS,
	},
	{
		Id = "Premium",
		Name = "Capsule Prisme",
		RequiredZone = 2,
		Currency = "Chips",
		ProductionSeconds = 0,
		MinBits = 0,
		ChipsCost = 150,
		Paid = true,
		Odds = PREMIUM_ODDS,
	},
}

-- Contenu : [capsule] = { {nom, bonus, couleur} x 5 raretés (dans l'ordre RARITY_ORDER) }
local CONTENT: { [string]: { { string } } } = {
	Bronze = {
		{ "Octet", "Bits", "A0AEC0" },
		{ "Pixel", "Speed", "4FD1C5" },
		{ "Kilo", "Power", "8B7CFF" },
		{ "Méga", "Bits", "F6C453" },
		{ "Giga-Anga", "Bits", "F0565B" },
	},
	Vault = {
		{ "Cache", "Power", "A0AEC0" },
		{ "Sector", "Bits", "4FD1C5" },
		{ "Raid", "Speed", "8B7CFF" },
		{ "Crypto", "Bits", "F6C453" },
		{ "Nova", "Power", "F0565B" },
	},
	Cryo = {
		{ "Givre", "Cooling", "A0AEC0" },
		{ "Blizzard", "Cooling", "4FD1C5" },
		{ "Pingouin 2.0", "Bits", "8B7CFF" },
		{ "Zéro Absolu", "Cooling", "F6C453" },
		{ "Aurora", "Bits", "F0565B" },
	},
	Neural = {
		{ "Neurone", "Bits", "A0AEC0" },
		{ "Axone", "Power", "4FD1C5" },
		{ "Dendrite", "Cooling", "8B7CFF" },
		{ "Cortex", "Bits", "F6C453" },
		{ "Singulier", "Bits", "F0565B" },
	},
	Premium = {
		{ "Prisme", "Bits", "A0AEC0" },
		{ "Spectre", "Speed", "4FD1C5" },
		{ "Hologramme", "Cooling", "8B7CFF" },
		{ "Quasar", "Bits", "F6C453" },
		{ "Anga Prime", "Bits", "F0565B" },
	},
}

local list: { NanobotDef } = {}
local byId: { [string]: NanobotDef } = {}
local byCapsuleRarity: { [string]: { [string]: { NanobotDef } } } = {}

for _, capsule in capsules do
	byCapsuleRarity[capsule.Id] = {}
	for index, entry in CONTENT[capsule.Id] do
		local rarity = RARITY_ORDER[index]
		local bonus = entry[2] :: BonusKind
		local def: NanobotDef = table.freeze({
			Id = `{capsule.Id}_{index}`,
			Name = entry[1],
			Rarity = rarity,
			Capsule = capsule.Id,
			Bonus = bonus,
			Value = BONUS_BY_RARITY[bonus][rarity],
			Color = entry[3],
		})
		table.insert(list, def)
		byId[def.Id] = def
		byCapsuleRarity[capsule.Id][rarity] = byCapsuleRarity[capsule.Id][rarity] or {}
		table.insert(byCapsuleRarity[capsule.Id][rarity], def)
	end
	table.freeze(capsule)
end

local capsuleById: { [string]: CapsuleDef } = {}
for _, capsule in capsules do
	capsuleById[capsule.Id] = capsule
end

local Nanobots = {
	List = table.freeze(list),
	ById = table.freeze(byId),
	Capsules = table.freeze(capsules),
	CapsuleById = table.freeze(capsuleById),
	RarityOrder = table.freeze(RARITY_ORDER),
	RarityNames = table.freeze(RARITY_NAMES),
}

function Nanobots.Pool(capsuleId: string, rarity: string): { NanobotDef }
	local byRarity = byCapsuleRarity[capsuleId]
	return if byRarity then byRarity[rarity] or {} else {}
end

-- Probabilités en pourcentage, pour l'affichage.
function Nanobots.OddsPercent(capsuleId: string): { { rarity: string, percent: number } }
	local capsule = capsuleById[capsuleId]
	local out = {}
	if not capsule then
		return out
	end
	local total = 0
	for _, entry in capsule.Odds do
		total += entry.weight
	end
	for _, entry in capsule.Odds do
		table.insert(out, { rarity = entry.key, percent = entry.weight / total * 100 })
	end
	return out
end

function Nanobots.BonusText(def: NanobotDef, golden: boolean): string
	local mult = if golden then 1.5 else 1
	local value = def.Value * mult
	if def.Bonus == "Bits" then
		return `+{math.floor(value * 100 + 0.5)} % Bits`
	elseif def.Bonus == "Power" then
		return `-{math.floor(value * 100 + 0.5)} % Watts`
	elseif def.Bonus == "Cooling" then
		return `-{math.floor(value * 100 + 0.5)} % chaleur`
	end
	return `+{value} vitesse`
end

return table.freeze(Nanobots)
