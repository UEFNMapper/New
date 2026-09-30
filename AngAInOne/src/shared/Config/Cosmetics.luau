--!strict
--[[
	Cosmetics : traînées lumineuses et effets de mort (purement visuels, aucun avantage).
	Price = prix en Bits ; 0 = gratuit / offert (VIP, calendrier).
]]

export type Kind = "Trail" | "DeathFx"

export type CosmeticDef = {
	Id: string,
	Kind: Kind,
	Name: string,
	Price: number,
	Colors: { string }, -- hex ; plusieurs couleurs = dégradé / animation RGB
	Rainbow: boolean?,
	Source: string?, -- "VIP" | "Daily" : non achetable, obtenu autrement
	Order: number,
}

local list: { CosmeticDef } = {
	-- Traînées
	{ Id = "TrailNone", Kind = "Trail", Name = "Aucune", Price = 0, Colors = {}, Order = 0 },
	{
		Id = "TrailCyan",
		Kind = "Trail",
		Name = "Fibre optique",
		Price = 150,
		Colors = { "4FD1C5", "63B3ED" },
		Order = 1,
	},
	{
		Id = "TrailAmber",
		Kind = "Trail",
		Name = "Courant ambré",
		Price = 250,
		Colors = { "F6AD55", "F0565B" },
		Order = 2,
	},
	{
		Id = "TrailViolet",
		Kind = "Trail",
		Name = "Onde violette",
		Price = 400,
		Colors = { "8B7CFF", "C084FC" },
		Order = 3,
	},
	{ Id = "TrailGold", Kind = "Trail", Name = "Or massif", Price = 800, Colors = { "F6E05E", "FBD38D" }, Order = 4 },
	{
		Id = "TrailRgb",
		Kind = "Trail",
		Name = "RGB Gamer",
		Price = 1500,
		Colors = { "F0565B", "F6E05E", "48BB78", "4FD1C5", "8B7CFF" },
		Rainbow = true,
		Order = 5,
	},
	{
		Id = "TrailCalendar",
		Kind = "Trail",
		Name = "Fidèle au poste",
		Price = 0,
		Colors = { "48BB78", "F6E05E" },
		Source = "Daily",
		Order = 6,
	},
	{
		Id = "TrailVip",
		Kind = "Trail",
		Name = "VIP AngaTV",
		Price = 0,
		Colors = { "F0565B", "FFFFFF" },
		Source = "VIP",
		Order = 7,
	},
	{
		Id = "TrailUsb",
		Kind = "Trail",
		Name = "Anti-Lag Légendaire",
		Price = 0,
		Colors = { "F6E05E", "FFFFFF", "F6E05E" },
		Source = "Usb",
		Order = 8,
	},
	-- Effets de mort
	{ Id = "DeathGlitch", Kind = "DeathFx", Name = "Glitch", Price = 0, Colors = { "ED64A6", "8B7CFF" }, Order = 0 },
	{ Id = "DeathPixels", Kind = "DeathFx", Name = "Pixels", Price = 200, Colors = { "48BB78", "4FD1C5" }, Order = 1 },
	{
		Id = "DeathZap",
		Kind = "DeathFx",
		Name = "Court-circuit",
		Price = 350,
		Colors = { "F6E05E", "FFFFFF" },
		Order = 2,
	},
	{
		Id = "DeathConfetti",
		Kind = "DeathFx",
		Name = "Confettis",
		Price = 600,
		Colors = { "F0565B", "F6E05E", "48BB78", "8B7CFF" },
		Order = 3,
	},
}

local byId: { [string]: CosmeticDef } = {}
for _, def in list do
	byId[def.Id] = def
end

return table.freeze({
	List = list,
	ById = byId,
	DefaultTrail = "TrailNone",
	DefaultDeathFx = "DeathGlitch",
})
