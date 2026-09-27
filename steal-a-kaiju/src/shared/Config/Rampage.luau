--!strict
-- RAMPAGE : deviens ton kaiju et écrase une ville en jouet.
-- Tous les réglages chiffrés du mode (partagés client/serveur).
-- Les récompenses sont en « secondes de revenu » (IS) : elles restent justes à
-- tous les niveaux de progression.

export type BuildingDef = {
	Id: string,
	Name: string,
	Count: number, -- nombre par ville
	HP: number, -- PV au quartier 1
	Value: number, -- valeur en IS
	Size: Vector3, -- largeur, hauteur, profondeur (studs)
}

export type District = {
	Index: number,
	Name: string,
	HpMult: number,
	RewardMult: number,
	Egg: { { Rarity: string, Weight: number } }, -- œuf de l'immeuble doré
	Ground: Color3, -- trottoirs
	Palette: { Color3 }, -- couleurs des immeubles
	Accent: Color3,
	Icon: string,
}

local rgb = Color3.fromRGB

local Rampage = {}

-- Partie ------------------------------------------------------------------
Rampage.Duration = 75 -- secondes
Rampage.Cooldown = 20 -- secondes entre deux parties (couvert par l'écran de résultats)
Rampage.EndDelay = 2.5 -- bannière « TIME'S UP! » avant le retour sur l'île
Rampage.WalkSpeed = 22 -- + améliorations Sneakers
Rampage.ModelScale = 1.3 -- échelle visuelle = échelle du stade x 1.3
Rampage.TutorialHpMult = 0.5 -- 1re partie pendant le tutoriel : ville plus fragile

-- Actions -------------------------------------------------------------------
Rampage.Stomp = {
	Cooldown = 0.4,
	Damage = 10, -- x Power
	Radius = 6, -- + RadiusPerScale x échelle du stade
	RadiusPerScale = 2,
}
Rampage.Roar = {
	Cooldown = 6,
	Damage = 30, -- x Power
	Angle = 40, -- ouverture du cône (degrés)
	Length = 25, -- + LengthPerScale x échelle du stade
	LengthPerScale = 5,
}
Rampage.CrushMult = 3 -- marcher dans un immeuble dont PV <= 3 x Power le détruit
Rampage.CrushMargin = 1.5 -- + CrushPerScale x échelle : distance de contact
Rampage.CrushPerScale = 1.2
Rampage.InputTolerance = 0.08 -- latence tolérée sur les temps de recharge (s)

-- Combo : +1 par immeuble détruit à moins de Window s du précédent
Rampage.Combo = { Window = 2.5, Step = 0.1, Max = 3 }

-- Étoiles : part des PV de la ville détruits
Rampage.Stars = { 0.4, 0.7, 1 }
Rampage.StarGems = 5 -- par nouvelle étoile
Rampage.UnlockStars = 2 -- étoiles au quartier N pour ouvrir N+1

-- Récompenses -----------------------------------------------------------------
Rampage.CashSecondsPerPoint = 0.3 -- 1 point = 0,3 s de revenu (quartier 1 rasé ≈ 1,5 à 3 min de revenu)
Rampage.MinCashPerPoint = 5 -- plancher : $5 par point x numéro du quartier
Rampage.GrowthCap = 0.25 -- croissance max : 25 % du temps restant dans le stade
Rampage.GoldenValueMult = 5
Rampage.GoldenEggChance = 0.1

-- Tanks-jouets ------------------------------------------------------------------
Rampage.Tanks = {
	StartAt = 25, -- secondes après le début
	Interval = 7, -- un nouveau tank toutes les 7 s
	MaxAlive = 3,
	MaxTotal = 8,
	HP = 15, -- x HpMult du quartier
	Value = 5, -- IS
	Speed = 12, -- studs/s sur la route
	Radius = 3.5, -- rayon de la zone touchable
	StopDistance = 26, -- s'arrête à cette distance du joueur
	MinSpawnDistance = 45,
	FireDelay = 1.5, -- premier tir après l'arrivée
	FireEvery = 3,
	Range = 110,
	DartSpeed = 34, -- studs/s
	DartMinTime = 1, -- temps de vol minimum (esquivable)
	DartRadius = 4, -- + DartPerScale x échelle
	DartPerScale = 1.2,
	HitPenalty = 1, -- secondes retirées au chrono
	KillBonus = 3, -- secondes ajoutées
}

-- Ville ----------------------------------------------------------------------------
Rampage.Block = 30 -- côté d'un pâté de maisons
Rampage.Road = 12 -- largeur des routes
Rampage.Blocks = 4 -- pâtés par côté
Rampage.Half = (Rampage.Blocks * Rampage.Block + (Rampage.Blocks + 1) * Rampage.Road) / 2
Rampage.BoundsMargin = 40 -- sortir de la ville au-delà : fin de partie

Rampage.Buildings = {
	{ Id = "Shack", Name = "Shack", Count = 20, HP = 10, Value = 2, Size = Vector3.new(5, 4, 5) },
	{ Id = "House", Name = "House", Count = 12, HP = 25, Value = 3, Size = Vector3.new(7, 6, 7) },
	{ Id = "Shop", Name = "Shop", Count = 8, HP = 60, Value = 6, Size = Vector3.new(10, 6, 8) },
	{ Id = "Tower", Name = "Tower", Count = 4, HP = 150, Value = 12, Size = Vector3.new(8, 18, 8) },
	{ Id = "HQ", Name = "Toy HQ", Count = 1, HP = 400, Value = 30, Size = Vector3.new(14, 24, 14) },
} :: { BuildingDef }

Rampage.Districts = {
	{
		Index = 1,
		Name = "Toy Town",
		HpMult = 1,
		RewardMult = 1,
		Egg = { { Rarity = "Rare", Weight = 1 } },
		Ground = rgb(255, 236, 200),
		Palette = { rgb(255, 170, 190), rgb(150, 215, 255), rgb(255, 225, 120), rgb(170, 235, 160), rgb(210, 180, 255) },
		Accent = rgb(255, 110, 150),
		Icon = "home",
	},
	{
		Index = 2,
		Name = "Candy Suburbs",
		HpMult = 2.5,
		RewardMult = 1.5,
		Egg = { { Rarity = "Epic", Weight = 1 } },
		Ground = rgb(255, 222, 238),
		Palette = { rgb(255, 140, 200), rgb(255, 200, 120), rgb(160, 240, 220), rgb(255, 250, 170), rgb(200, 160, 255) },
		Accent = rgb(255, 61, 139),
		Icon = "gifts",
	},
	{
		Index = 3,
		Name = "Block City",
		HpMult = 6,
		RewardMult = 2,
		Egg = { { Rarity = "Legendary", Weight = 1 } },
		Ground = rgb(225, 235, 255),
		Palette = { rgb(255, 90, 90), rgb(70, 160, 255), rgb(255, 210, 60), rgb(90, 210, 110), rgb(255, 150, 60) },
		Accent = rgb(61, 160, 255),
		Icon = "package",
	},
	{
		Index = 4,
		Name = "Neon Downtown",
		HpMult = 14,
		RewardMult = 3,
		Egg = { { Rarity = "Mythic", Weight = 1 } },
		Ground = rgb(200, 190, 230),
		Palette = { rgb(120, 90, 255), rgb(61, 224, 255), rgb(255, 61, 180), rgb(124, 255, 79), rgb(255, 200, 40) },
		Accent = rgb(150, 80, 255),
		Icon = "lightning",
	},
	{
		Index = 5,
		Name = "Mega Metropolis",
		HpMult = 30,
		RewardMult = 4,
		Egg = { { Rarity = "Mythic", Weight = 7 }, { Rarity = "Celestial", Weight = 3 } },
		Ground = rgb(235, 225, 205),
		Palette = { rgb(255, 200, 40), rgb(255, 106, 31), rgb(240, 240, 250), rgb(80, 255, 230), rgb(255, 61, 139) },
		Accent = rgb(255, 176, 32),
		Icon = "crown",
	},
} :: { District }

function Rampage.District(index: number): District
	return Rampage.Districts[math.clamp(index, 1, #Rampage.Districts)]
end

-- Origine (centre, niveau du sol) de la ville privée de l'île i : loin de
-- tout (îles à 250 studs, arènes des mondes à 860 studs du centre).
function Rampage.CityOrigin(plotIndex: number): Vector3
	return Vector3.new(-2800 + plotIndex * 700, 0, 2600)
end

-- Rayons d'action selon l'échelle du stade du kaiju.
function Rampage.StompRadius(scale: number): number
	return Rampage.Stomp.Radius + Rampage.Stomp.RadiusPerScale * scale
end

function Rampage.RoarLength(scale: number): number
	return Rampage.Roar.Length + Rampage.Roar.LengthPerScale * scale
end

function Rampage.CrushRadius(scale: number): number
	return Rampage.CrushMargin + Rampage.CrushPerScale * scale
end

function Rampage.DartRadius(scale: number): number
	return Rampage.Tanks.DartRadius + Rampage.Tanks.DartPerScale * scale
end

-- Multiplicateur de combo (1 + 0.1 x combo, plafonné).
function Rampage.ComboMult(combo: number): number
	return math.min(Rampage.Combo.Max, 1 + Rampage.Combo.Step * combo)
end

-- Étoiles pour une part détruite (0..1). La 3e demande une ville rasée.
function Rampage.StarsFor(destruction: number, flattened: boolean): number
	local stars = 0
	for i, threshold in Rampage.Stars do
		if destruction >= threshold - 1e-6 and (i < #Rampage.Stars or flattened) then
			stars = i
		end
	end
	return stars
end

-- Pourcentage affiché : arrondi par défaut (100 % seulement ville rasée),
-- mais au moins 1 % dès la première casse.
function Rampage.Percent(destruction: number): number
	if destruction <= 0 then
		return 0
	end
	return math.max(1, math.floor(destruction * 100 + 1e-6))
end

-- Un quartier est ouvert si le précédent a au moins UnlockStars étoiles.
function Rampage.Unlocked(stars: { number }, index: number): boolean
	if index <= 1 then
		return true
	end
	if index > #Rampage.Districts then
		return false
	end
	return (stars[index - 1] or 0) >= Rampage.UnlockStars
end

return Rampage
