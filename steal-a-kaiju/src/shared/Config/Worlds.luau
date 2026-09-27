--!strict
-- Les 5 mondes. Le cratère central reste le monde de départ et le lieu social ;
-- les 4 autres sont des îles-arènes visibles à l'horizon, reliées par portails.
-- Chaque monde a ses œufs (poids de rareté), ses espèces, sa mutation locale,
-- son décor et sa lumière.

export type MutationBonus = { Id: string, Chance: number }

export type Palette = {
	Ground: Color3,
	GroundMaterial: Enum.Material,
	Rim: Color3,
	Rock: Color3,
	Accent: Color3,
	Glow: Color3,
	Lava: Color3, -- lac central
	Sky: Color3, -- couleur du brouillard / de l'atmosphère
	Ambient: Color3,
	Tint: Color3, -- ColorCorrection
	Particle: string, -- clé Vfx des particules d'ambiance
	Music: string,
}

export type World = {
	Id: string,
	Name: string,
	Order: number,
	Icon: string, -- clé d'icône
	Tagline: string,
	Level: number,
	Rebirths: number,
	Toll: number, -- péage unique en cash
	Weights: { [string]: number }, -- rareté -> poids
	Species: { string }, -- espèces natives (tirées en priorité)
	Mutations: { MutationBonus }, -- mutations locales à l'éclosion
	Palette: Palette,
	Angle: number, -- position de l'île-arène autour de la carte (degrés)
}

local rgb = Color3.fromRGB

local Worlds = {}

Worlds.ArenaRadius = 88 -- rayon de l'arène
Worlds.ArenaDistance = 860 -- distance au centre de la carte
Worlds.PadCount = 6
Worlds.MeteorInterval = 12 -- un météore toutes les ~12 s quand quelqu'un est dans le monde

Worlds.List = {
	{
		Id = "Crater",
		Name = "Kaiju Crater",
		Order = 1,
		Icon = "meteor",
		Tagline = "Where every tamer starts.",
		Level = 1,
		Rebirths = 0,
		Toll = 0,
		Weights = { Common = 620, Rare = 270, Epic = 95, Legendary = 14, Mythic = 1, Celestial = 0.1 },
		Species = { "Gloop", "Pinchy", "DinoNugget", "Wormzy", "Pigeonator", "Sharkapillar", "BeepBoop", "Robotank", "Crabzooka", "Rexplosion" },
		Mutations = {},
		Palette = {
			Ground = rgb(92, 84, 96),
			GroundMaterial = Enum.Material.Basalt,
			Rim = rgb(255, 200, 40),
			Rock = rgb(80, 70, 90),
			Accent = rgb(124, 255, 79),
			Glow = rgb(255, 120, 40),
			Lava = rgb(255, 100, 20),
			Sky = rgb(200, 220, 255),
			Ambient = rgb(140, 140, 150),
			Tint = rgb(255, 255, 255),
			Particle = "Sparkle",
			Music = "Main",
		},
		Angle = 0,
	},
	{
		Id = "Candy",
		Name = "Candy Coast",
		Order = 2,
		Icon = "candy",
		Tagline = "Sweet beaches, sweeter kaijus.",
		Level = 5,
		Rebirths = 0,
		Toll = 2500,
		Weights = { Common = 250, Rare = 450, Epic = 250, Legendary = 45, Mythic = 4.5, Celestial = 0.5 },
		Species = { "Toastzilla", "Croissantosaurus", "Kebabzilla", "SushiRex", "Bananadon", "Pizzapocalypse", "Donutron", "KawaiiKraken", "Hydroblob" },
		Mutations = { { Id = "Rainbow", Chance = 0.015 } },
		Palette = {
			Ground = rgb(255, 190, 220),
			GroundMaterial = Enum.Material.SmoothPlastic,
			Rim = rgb(255, 255, 255),
			Rock = rgb(255, 120, 190),
			Accent = rgb(120, 230, 255),
			Glow = rgb(255, 90, 180),
			Lava = rgb(255, 120, 200),
			Sky = rgb(255, 210, 235),
			Ambient = rgb(170, 140, 160),
			Tint = rgb(255, 240, 250),
			Particle = "Confetti",
			Music = "Main",
		},
		Angle = 45,
	},
	{
		Id = "Frost",
		Name = "Frost Peaks",
		Order = 3,
		Icon = "frost",
		Tagline = "Frozen giants sleep under the snow.",
		Level = 9,
		Rebirths = 0,
		Toll = 2000000,
		Weights = { Rare = 420, Epic = 420, Legendary = 140, Mythic = 18, Celestial = 2 },
		Species = { "Frostodon", "ThunderSquid", "Pengwing", "Snowgoon", "Yetitan", "ThunderGoose", "Kaijumbo", "Glacirex" },
		Mutations = { { Id = "Diamond", Chance = 0.035 } },
		Palette = {
			Ground = rgb(235, 245, 255),
			GroundMaterial = Enum.Material.Snow,
			Rim = rgb(150, 220, 255),
			Rock = rgb(170, 200, 230),
			Accent = rgb(90, 200, 255),
			Glow = rgb(140, 230, 255),
			Lava = rgb(120, 220, 255),
			Sky = rgb(210, 235, 255),
			Ambient = rgb(140, 160, 190),
			Tint = rgb(230, 245, 255),
			Particle = "Snow",
			Music = "Main",
		},
		Angle = 135,
	},
	{
		Id = "Volcano",
		Name = "Volcano Core",
		Order = 4,
		Icon = "volcano",
		Tagline = "Only evolved tamers survive the heat.",
		Level = 15,
		Rebirths = 1,
		Toll = 25000000,
		Weights = { Epic = 480, Legendary = 400, Mythic = 110, Celestial = 10 },
		Species = { "Magmadillo", "Magmapus", "Drakonda", "Cinderwing", "Crabageddon", "Emberwyrm", "SolarisRex" },
		Mutations = { { Id = "Blood", Chance = 0.02 } },
		Palette = {
			Ground = rgb(50, 36, 40),
			GroundMaterial = Enum.Material.Basalt,
			Rim = rgb(255, 120, 30),
			Rock = rgb(40, 30, 34),
			Accent = rgb(255, 170, 40),
			Glow = rgb(255, 80, 20),
			Lava = rgb(255, 90, 10),
			Sky = rgb(255, 150, 110),
			Ambient = rgb(170, 110, 90),
			Tint = rgb(255, 225, 205),
			Particle = "Ember",
			Music = "Event",
		},
		Angle = 225,
	},
	{
		Id = "Cosmic",
		Name = "Cosmic Rift",
		Order = 5,
		Icon = "cosmic",
		Tagline = "A tear in the sky. Kaijus from the stars.",
		Level = 24,
		Rebirths = 3,
		Toll = 5000000000,
		Weights = { Legendary = 560, Mythic = 360, Celestial = 80 },
		Species = { "Starpinch", "Nebulodon", "Astrolotl", "LunarSquid", "CosmoGoose", "Voidling" },
		Mutations = { { Id = "Galaxy", Chance = 0.02 }, { Id = "Shadow", Chance = 0.004 } },
		Palette = {
			Ground = rgb(40, 28, 80),
			GroundMaterial = Enum.Material.SmoothPlastic,
			Rim = rgb(170, 120, 255),
			Rock = rgb(60, 45, 110),
			Accent = rgb(80, 255, 230),
			Glow = rgb(150, 90, 255),
			Lava = rgb(120, 80, 255),
			Sky = rgb(80, 60, 140),
			Ambient = rgb(110, 100, 160),
			Tint = rgb(225, 215, 255),
			Particle = "Stars",
			Music = "Event",
		},
		Angle = 315,
	},
} :: { World }

Worlds.ById = {} :: { [string]: World }
for _, w in Worlds.List do
	Worlds.ById[w.Id] = w
end

Worlds.Default = "Crater"

function Worlds.Get(id: string?): World
	return Worlds.ById[id or ""] or Worlds.ById[Worlds.Default]
end

-- Centre de l'île-arène d'un monde (le cratère est au centre de la carte).
function Worlds.Origin(id: string): Vector3
	local w = Worlds.Get(id)
	if w.Id == Worlds.Default then
		return Vector3.zero
	end
	local a = math.rad(w.Angle)
	return Vector3.new(math.sin(a) * Worlds.ArenaDistance, 0, math.cos(a) * Worlds.ArenaDistance)
end

-- Position d'une plateforme à météore dans une arène.
function Worlds.PadPosition(id: string, i: number): Vector3
	local a = (i - 0.5) / Worlds.PadCount * math.pi * 2
	return Worlds.Origin(id) + Vector3.new(math.sin(a) * 40, 0, math.cos(a) * 40)
end

-- Direction (à plat) du centre de l'arène vers le cratère : c'est le côté
-- « entrée » de l'arène (arrivée des voyageurs, portail du retour).
function Worlds.EntryDirection(id: string): Vector3
	local origin = Worlds.Origin(id)
	if origin.Magnitude < 1 then
		return Vector3.new(0, 0, 1)
	end
	return -origin.Unit
end

-- Point d'arrivée des joueurs qui voyagent vers ce monde : côté entrée, face au centre.
function Worlds.SpawnPoint(id: string): CFrame
	local origin = Worlds.Origin(id)
	local pos = origin + Worlds.EntryDirection(id) * (Worlds.ArenaRadius - 22) + Vector3.new(0, 4, 0)
	return CFrame.lookAt(pos, Vector3.new(origin.X, pos.Y, origin.Z))
end

-- Portail d'un monde dans le cratère central (dans l'axe de son île-arène).
function Worlds.HubPortal(id: string): CFrame
	local w = Worlds.Get(id)
	local a = math.rad(w.Angle - 22.5)
	local pos = Vector3.new(math.sin(a) * 60, 0, math.cos(a) * 60)
	return CFrame.lookAt(pos, Vector3.new(0, 0, 0))
end

-- Le monde où se trouve une position (nil = carte principale hors arènes).
function Worlds.At(position: Vector3): string?
	for _, w in Worlds.List do
		if w.Id ~= Worlds.Default then
			local o = Worlds.Origin(w.Id)
			local flat = Vector3.new(position.X - o.X, 0, position.Z - o.Z)
			if flat.Magnitude <= Worlds.ArenaRadius + 30 and math.abs(position.Y - o.Y) < 150 then
				return w.Id
			end
		end
	end
	return nil
end

-- Vrai si le joueur remplit les conditions (hors péage).
function Worlds.MeetsGate(w: World, level: number, rebirths: number): boolean
	return level >= w.Level and rebirths >= w.Rebirths
end

-- Meilleur monde débloqué (pour le météore perso).
function Worlds.Best(unlocked: { [string]: boolean }): World
	local best = Worlds.ById[Worlds.Default]
	for _, w in Worlds.List do
		if unlocked[w.Id] and w.Order > best.Order then
			best = w
		end
	end
	return best
end

return Worlds
