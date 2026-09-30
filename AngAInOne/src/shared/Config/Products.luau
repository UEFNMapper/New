--!strict
--[[
	Products : Game Passes et Developer Products.

	⚠️ À FAIRE DANS LE CREATOR DASHBOARD (create.roblox.com) :
	crée chaque pass/produit avec le prix indiqué, puis colle son ID ci-dessous.
	Un ID à 0 = objet désactivé : il est masqué dans la boutique et refusé par le serveur.
]]

export type PassDef = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Price: number, -- prix de référence en Robux (le vrai prix vient de MarketplaceService)
	Order: number,
}

export type ProductKind = "Bits" | "Chips" | "Capsule" | "ServerBoost" | "SkipDownload" | "RebootBoost" | "StarterPack"

export type ProductDef = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Price: number,
	Kind: ProductKind,
	Amount: number, -- Bits : secondes de production ; Chips : quantité ; Capsule : nombre
	Order: number,
	OneTime: boolean,
}

local passes: { PassDef } = {
	{
		Key = "DoubleBits",
		Id = 0,
		Name = "Bits x2",
		Description = "Double définitivement tous tes Bits.",
		Price = 399,
		Order = 1,
	},
	{
		Key = "VIP",
		Id = 0,
		Name = "VIP",
		Description = "Tag VIP, lounge VIP, thème RGB exclusif et +10 % de Chips quotidiens.",
		Price = 249,
		Order = 2,
	},
	{
		Key = "AutoCollect",
		Id = 0,
		Name = "Auto-Collect",
		Description = "Tes Bits arrivent directement, sans passer par le collecteur.",
		Price = 149,
		Order = 3,
	},
	{
		Key = "ExtraNanobots",
		Id = 0,
		Name = "+2 slots Nanobots",
		Description = "Équipe 5 Nanobots au lieu de 3.",
		Price = 199,
		Order = 4,
	},
	{
		Key = "OverclockPro",
		Id = 0,
		Name = "Overclock Pro",
		Description = "Recharge 2x plus rapide, durée +50 %.",
		Price = 179,
		Order = 5,
	},
	{
		Key = "OfflineMax",
		Id = 0,
		Name = "Hors ligne max",
		Description = "8 h de gains hors ligne à 100 %.",
		Price = 199,
		Order = 6,
	},
	{
		Key = "RgbStudio",
		Id = 0,
		Name = "RGB Studio",
		Description = "Choisis la couleur des néons de ton PC.",
		Price = 99,
		Order = 7,
	},
}

local products: { ProductDef } = {
	{
		Key = "BitsS",
		Id = 0,
		Name = "Petit cache",
		Description = "10 min de ta production actuelle.",
		Price = 39,
		Kind = "Bits",
		Amount = 600,
		Order = 1,
		OneTime = false,
	},
	{
		Key = "BitsM",
		Id = 0,
		Name = "Gros cache",
		Description = "1 h de ta production actuelle.",
		Price = 149,
		Kind = "Bits",
		Amount = 3600,
		Order = 2,
		OneTime = false,
	},
	{
		Key = "BitsL",
		Id = 0,
		Name = "Datacenter",
		Description = "6 h de ta production actuelle.",
		Price = 499,
		Kind = "Bits",
		Amount = 21600,
		Order = 3,
		OneTime = false,
	},
	{
		Key = "Chips100",
		Id = 0,
		Name = "100 Chips",
		Description = "Pour les cosmétiques et boosts.",
		Price = 49,
		Kind = "Chips",
		Amount = 100,
		Order = 4,
		OneTime = false,
	},
	{
		Key = "Chips550",
		Id = 0,
		Name = "550 Chips",
		Description = "+10 % offerts.",
		Price = 249,
		Kind = "Chips",
		Amount = 550,
		Order = 5,
		OneTime = false,
	},
	{
		Key = "Chips1200",
		Id = 0,
		Name = "1 200 Chips",
		Description = "+20 % offerts.",
		Price = 499,
		Kind = "Chips",
		Amount = 1200,
		Order = 6,
		OneTime = false,
	},
	{
		Key = "Chips2600",
		Id = 0,
		Name = "2 600 Chips",
		Description = "+30 % offerts.",
		Price = 999,
		Kind = "Chips",
		Amount = 2600,
		Order = 7,
		OneTime = false,
	},
	{
		Key = "ServerBoost",
		Id = 0,
		Name = "Server Boost",
		Description = "x2 Bits pour TOUT le serveur pendant 15 min.",
		Price = 149,
		Kind = "ServerBoost",
		Amount = 900,
		Order = 8,
		OneTime = false,
	},
	{
		Key = "SkipDownload",
		Id = 0,
		Name = "Téléchargement instantané",
		Description = "Termine ton téléchargement en cours.",
		Price = 25,
		Kind = "SkipDownload",
		Amount = 1,
		Order = 9,
		OneTime = false,
	},
	{
		Key = "RebootBoost",
		Id = 0,
		Name = "Reboot Boost",
		Description = "Firmware x1,5 au prochain Reboot.",
		Price = 149,
		Kind = "RebootBoost",
		Amount = 1,
		Order = 10,
		OneTime = false,
	},
	{
		Key = "StarterPack",
		Id = 0,
		Name = "Starter Pack",
		Description = "1 Nanobot Rare, 300 Chips et 30 min de Bits x2. Une seule fois.",
		Price = 99,
		Kind = "StarterPack",
		Amount = 1,
		Order = 11,
		OneTime = true,
	},
}

local passByKey: { [string]: PassDef } = {}
local passById: { [number]: PassDef } = {}
for _, pass in passes do
	passByKey[pass.Key] = table.freeze(pass)
	if pass.Id ~= 0 then
		passById[pass.Id] = pass
	end
end

local productByKey: { [string]: ProductDef } = {}
local productById: { [number]: ProductDef } = {}
for _, product in products do
	productByKey[product.Key] = table.freeze(product)
	if product.Id ~= 0 then
		productById[product.Id] = product
	end
end

return table.freeze({
	Passes = table.freeze(passes),
	PassByKey = table.freeze(passByKey),
	PassById = table.freeze(passById),
	Products = table.freeze(products),
	ProductByKey = table.freeze(productByKey),
	ProductById = table.freeze(productById),
})
