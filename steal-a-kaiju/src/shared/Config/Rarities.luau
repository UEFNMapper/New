--!strict
-- Raretés des kaijus : ordre, couleurs, poids de tirage des météores, temps d'éclosion.

export type Rarity = {
	Id: string,
	Name: string,
	Order: number,
	Color: Color3,
	Glow: Color3,
	Weight: number, -- poids de tirage d'un météore (0 = introuvable dans le ciel)
	HatchTime: number, -- secondes
	PriceMult: number,
	TrailWidth: number,
	Announce: boolean, -- annonce serveur à l'apparition
}

local Rarities = {}

Rarities.List = {
	{
		Id = "Common",
		Name = "Common",
		Order = 1,
		Color = Color3.fromRGB(188, 196, 206),
		Glow = Color3.fromRGB(235, 240, 245),
		Weight = 600,
		HatchTime = 8,
		PriceMult = 1,
		TrailWidth = 3,
		Announce = false,
	},
	{
		Id = "Rare",
		Name = "Rare",
		Order = 2,
		Color = Color3.fromRGB(61, 170, 255),
		Glow = Color3.fromRGB(140, 210, 255),
		Weight = 260,
		HatchTime = 15,
		PriceMult = 1,
		TrailWidth = 4,
		Announce = false,
	},
	{
		Id = "Epic",
		Name = "Epic",
		Order = 3,
		Color = Color3.fromRGB(176, 76, 255),
		Glow = Color3.fromRGB(214, 160, 255),
		Weight = 100,
		HatchTime = 25,
		PriceMult = 1,
		TrailWidth = 5,
		Announce = false,
	},
	{
		Id = "Legendary",
		Name = "Legendary",
		Order = 4,
		Color = Color3.fromRGB(255, 176, 32),
		Glow = Color3.fromRGB(255, 225, 120),
		Weight = 30,
		HatchTime = 40,
		PriceMult = 1,
		TrailWidth = 7,
		Announce = true,
	},
	{
		Id = "Mythic",
		Name = "Mythic",
		Order = 5,
		Color = Color3.fromRGB(255, 45, 110),
		Glow = Color3.fromRGB(255, 140, 180),
		Weight = 8,
		HatchTime = 60,
		PriceMult = 1,
		TrailWidth = 9,
		Announce = true,
	},
	{
		Id = "Celestial",
		Name = "Celestial",
		Order = 6,
		Color = Color3.fromRGB(80, 255, 230),
		Glow = Color3.fromRGB(200, 255, 250),
		Weight = 1.2,
		HatchTime = 90,
		PriceMult = 1,
		TrailWidth = 12,
		Announce = true,
	},
	{
		Id = "Secret",
		Name = "SECRET",
		Order = 7,
		Color = Color3.fromRGB(20, 20, 24),
		Glow = Color3.fromRGB(255, 255, 255),
		Weight = 0, -- uniquement par fusion
		HatchTime = 120,
		PriceMult = 1,
		TrailWidth = 14,
		Announce = true,
	},
} :: { Rarity }

Rarities.ById = {} :: { [string]: Rarity }
for _, r in Rarities.List do
	Rarities.ById[r.Id] = r
end

function Rarities.Get(id: string): Rarity
	return Rarities.ById[id] or Rarities.ById.Common
end

function Rarities.Next(id: string): Rarity?
	local r = Rarities.Get(id)
	for _, other in Rarities.List do
		if other.Order == r.Order + 1 and other.Weight > 0 then
			return other
		end
	end
	return nil
end

return Rarities
