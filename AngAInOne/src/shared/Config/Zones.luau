--!strict
--[[
	Zones : les 7 étages de la tour PC. Index 1 = étage du bas (PSU).
	Les coûts viennent du GDD et sont validés par tests/pacing.spec.luau.
]]

export type ZoneDef = {
	Index: number,
	Id: string,
	Name: string,
	Component: string,
	Tagline: string,
	UnlockCost: number,
	Primary: string, -- hex, couleur néon principale
	Secondary: string, -- hex, couleur d'accent
	Tint: string, -- hex, teinte ColorCorrection appliquée quand on est dans la zone
	Feature: string, -- ce que la zone débloque (affiché à l'ouverture)
}

local Zones: { ZoneDef } = {
	{
		Index = 1,
		Id = "PSU",
		Name = "La Centrale",
		Component = "Alimentation",
		Tagline = "Là où tout s'allume.",
		UnlockCost = 0,
		Primary = "F6AD55",
		Secondary = "F0565B",
		Tint = "FFF3E6",
		Feature = "Capacité électrique (Watts)",
	},
	{
		Index = 2,
		Id = "RAM",
		Name = "Memory Lanes",
		Component = "Mémoire vive",
		Tagline = "Des gratte-ciels de données.",
		UnlockCost = 2.5e4,
		Primary = "8B7CFF",
		Secondary = "C084FC",
		Tint = "F1EEFF",
		Feature = "Capsules de Nanobots",
	},
	{
		Index = 3,
		Id = "SSD",
		Name = "Data Vault",
		Component = "Stockage NVMe",
		Tagline = "Chaque cellule garde un secret.",
		UnlockCost = 2.5e7,
		Primary = "38B2AC",
		Secondary = "4FD1C5",
		Tint = "E9FFFB",
		Feature = "Téléchargements",
	},
	{
		Index = 4,
		Id = "Cooling",
		Name = "Cryo Tower",
		Component = "Refroidissement",
		Tagline = "Le calme avant la puissance.",
		UnlockCost = 2.5e9,
		Primary = "7FDBFF",
		Secondary = "BEE3F8",
		Tint = "EAF6FF",
		Feature = "Radiateurs (capacité thermique)",
	},
	{
		Index = 5,
		Id = "CPU",
		Name = "The Core",
		Component = "Processeur",
		Tagline = "Le temple du silicium.",
		UnlockCost = 7.5e10,
		Primary = "F6C453",
		Secondary = "FFFFFF",
		Tint = "FFF9E8",
		Feature = "Overclock",
	},
	{
		Index = 6,
		Id = "GPU",
		Name = "Render Canyon",
		Component = "Carte graphique",
		Tagline = "Là où naissent les pixels.",
		UnlockCost = 3e12,
		Primary = "48BB78",
		Secondary = "ED64A6",
		Tint = "F0FFF4",
		Feature = "Reboot (prestige)",
	},
	{
		Index = 7,
		Id = "AI",
		Name = "Neural Nexus",
		Component = "AI Core",
		Tagline = "Ton PC commence à rêver.",
		UnlockCost = 1e14,
		Primary = "E9D8FD",
		Secondary = "8B7CFF",
		Tint = "F7F2FF",
		Feature = "La Singularité",
	},
}

for _, zone in Zones do
	table.freeze(zone)
end

return table.freeze(Zones)
