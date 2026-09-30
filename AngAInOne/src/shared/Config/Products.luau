--!strict
--[[
	Products : Game Passes et Developer Products du deathrun.

	⚠️ À FAIRE DANS LE CREATOR DASHBOARD (create.roblox.com) :
	crée chaque pass/produit avec le prix indiqué, puis colle son ID ci-dessous.
	Un ID à 0 = objet désactivé : il est masqué dans la boutique et refusé par le serveur.

	Éthique : rien n'est obligatoire pour finir la tour. Les passes « avantage » sont
	activables/désactivables et une course assistée n'entre pas au classement des temps.
]]

export type PassDef = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Price: number, -- prix de référence en Robux (le vrai prix vient de MarketplaceService)
	Order: number,
	Toggle: boolean, -- activable/désactivable en jeu
}

export type ProductKind = "Skip" | "Shield" | "Bits"

export type ProductDef = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Price: number,
	Kind: ProductKind,
	Amount: number, -- Bits : quantité
	Order: number,
}

local passes: { PassDef } = {
	{
		Key = "VIP",
		Id = 0,
		Name = "VIP",
		Description = "Bits x2 pour toujours et la traînée VIP AngaTV.",
		Price = 249,
		Order = 1,
		Toggle = false,
	},
	{
		Key = "LowGravity",
		Id = 0,
		Name = "Bottes anti-gravité",
		Description = "Saute plus haut ! (activable quand tu veux)",
		Price = 149,
		Order = 2,
		Toggle = true,
	},
	{
		Key = "SpeedChip",
		Id = 0,
		Name = "Puce de vitesse",
		Description = "Cours plus vite ! (activable quand tu veux)",
		Price = 149,
		Order = 3,
		Toggle = true,
	},
}

local products: { ProductDef } = {
	{
		Key = "Skip",
		Id = 0,
		Name = "Passer l'étape",
		Description = "Téléporte au checkpoint suivant.",
		Price = 19,
		Kind = "Skip",
		Amount = 1,
		Order = 1,
	},
	{
		Key = "Shield",
		Id = 0,
		Name = "Bouclier 30 s",
		Description = "Invincible pendant 30 secondes.",
		Price = 29,
		Kind = "Shield",
		Amount = 1,
		Order = 2,
	},
	{
		Key = "BitsSmall",
		Id = 0,
		Name = "500 Bits",
		Description = "Pour la boutique de traînées.",
		Price = 49,
		Kind = "Bits",
		Amount = 500,
		Order = 3,
	},
	{
		Key = "BitsMedium",
		Id = 0,
		Name = "2 000 Bits",
		Description = "Le meilleur rapport.",
		Price = 149,
		Kind = "Bits",
		Amount = 2000,
		Order = 4,
	},
	{
		Key = "BitsLarge",
		Id = 0,
		Name = "6 000 Bits",
		Description = "Pour tout débloquer.",
		Price = 399,
		Kind = "Bits",
		Amount = 6000,
		Order = 5,
	},
}

local passById: { [number]: PassDef } = {}
local passByKey: { [string]: PassDef } = {}
for _, pass in passes do
	passByKey[pass.Key] = pass
	if pass.Id ~= 0 then
		passById[pass.Id] = pass
	end
end

local productById: { [number]: ProductDef } = {}
local productByKey: { [string]: ProductDef } = {}
for _, product in products do
	productByKey[product.Key] = product
	if product.Id ~= 0 then
		productById[product.Id] = product
	end
end

return table.freeze({
	Passes = passes,
	Products = products,
	PassById = passById,
	PassByKey = passByKey,
	ProductById = productById,
	ProductByKey = productByKey,
})
