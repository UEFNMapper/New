--!strict
-- Compagnon (Buddy) : un de tes kaijus éclos te suit en version mini, attire
-- les orbes, flaire un trésor régulièrement et t'aide au combat. Il a son
-- propre niveau (XP séparée de celle du joueur).

export type Loot = { Kind: string, Weight: number }

local Buddy = {}

-- Apparence et suivi (client)
Buddy.Scale = 0.6 -- échelle du modèle au niveau 1 (un bébé kaiju fait 1)
Buddy.ScalePerLevel = 0.005 -- il grandit un peu avec son niveau
Buddy.FollowOffset = Vector3.new(3, 0, 5) -- à droite / derrière le joueur (repère du HRP)
Buddy.FollowSharpness = 7 -- vitesse de rattrapage (interpolation exponentielle)
Buddy.SnapDistance = 60 -- au-delà, il se téléporte à côté du joueur
Buddy.HopHeight = 0.8
Buddy.HopSpeed = 10
Buddy.Roll = 0.15 -- roulis en marchant (radians)
Buddy.AnimDistance = 170 -- au-delà de la caméra, on ne l'anime plus
Buddy.PounceTime = 0.45

-- Changement de compagnon
Buddy.SwapCooldown = 10

-- Niveau : floor(sqrt(Xp / 10)) + 1, plafonné
Buddy.MaxLevel = 50
Buddy.XpDivisor = 10
Buddy.Xp = {
	Orb = 1,
	Dig = 5,
	SiegeKill = 2,
	RampageBuilding = 1,
}

function Buddy.Level(xp: number): number
	return math.min(Buddy.MaxLevel, math.floor(math.sqrt(math.max(0, xp) / Buddy.XpDivisor)) + 1)
end

-- XP totale nécessaire pour atteindre un niveau.
function Buddy.XpFor(level: number): number
	return Buddy.XpDivisor * (level - 1) ^ 2
end

-- Progression (0..1) vers le niveau suivant.
function Buddy.Progress(xp: number): number
	local level = Buddy.Level(xp)
	if level >= Buddy.MaxLevel then
		return 1
	end
	local from, to = Buddy.XpFor(level), Buddy.XpFor(level + 1)
	return math.clamp((xp - from) / (to - from), 0, 1)
end

function Buddy.ModelScale(level: number): number
	return Buddy.Scale + (level - 1) * Buddy.ScalePerLevel
end

-- Aimant : rayon autour du joueur (studs), vérifié par le serveur.
Buddy.MagnetTick = 0.5
function Buddy.MagnetRadius(level: number): number
	return 12 + 2 * math.sqrt(level)
end

-- Trésors
Buddy.TreasureFirstDelay = 20 -- premier trésor après l'arrivée d'un compagnon
Buddy.TreasureLifetime = 45
Buddy.DigHold = 1.5
Buddy.DigDistance = 8
Buddy.DigHoldTolerance = 0.25 -- latence réseau tolérée sur le maintien
function Buddy.TreasureInterval(level: number): number
	return math.max(35, 50 - (level - 1) * 0.3)
end

Buddy.Loot = {
	{ Kind = "Cash", Weight = 68 },
	{ Kind = "Potion", Weight = 20 },
	{ Kind = "Gems", Weight = 9 },
	{ Kind = "Egg", Weight = 3 },
} :: { Loot }
Buddy.CashSeconds = 30 -- secondes de revenu
Buddy.CashMin = 50
Buddy.PotionId = "Growth"
Buddy.Gems = { 2, 5 }
Buddy.EggWeights = { Rare = 60, Epic = 30, Legendary = 10 } :: { [string]: number }

-- Points de fouille (repère local de l'île : -Z regarde le cratère)
Buddy.IslandSpots = {
	-- avant de l'île, entre la porte et la cour des nids
	Vector3.new(-40, 0, -45),
	Vector3.new(-24, 0, -49),
	Vector3.new(-8, 0, -44),
	Vector3.new(8, 0, -49),
	Vector3.new(24, 0, -44),
	Vector3.new(40, 0, -48),
	-- arrière, entre le réacteur, le bouton et le pad perso
	Vector3.new(-44, 0, 52),
	Vector3.new(-15, 0, 54),
	Vector3.new(15, 0, 54),
	Vector3.new(44, 0, 52),
} :: { Vector3 }
-- Points proches du spawn (15 à 25 studs) pour le trésor du tutoriel
Buddy.TutorialSpots = {
	Vector3.new(-15, 0, 54),
	Vector3.new(15, 0, 54),
	Vector3.new(-19, 0, 46),
	Vector3.new(19, 0, 46),
} :: { Vector3 }
Buddy.BridgeFractions = { 0.2, 0.4, 0.6, 0.8 } -- le long de ton pont (0 = cratère)
Buddy.BridgeSide = 5 -- décalage latéral alterné sur le pont
Buddy.RimInner = 64 -- dans le cratère, au pied des rochers
Buddy.RimOuter = 86 -- sur l'île centrale, derrière les rochers
-- Poids par catégorie (proches de l'île du joueur en priorité)
Buddy.SpotWeights = {
	Island = 3,
	Bridge = 3,
	Rim = 2,
	OtherBridge = 1,
} :: { [string]: number }
-- Dans une île-arène : entre les plateformes à météores
Buddy.ArenaRadius = { 22, 70 }

-- Aide au combat
Buddy.AssistTick = 1.5
Buddy.AssistRange = 18
Buddy.AssistPower = 4 -- dégâts = AssistPower x puissance du kaiju
function Buddy.BossDamage(power: number): number
	return math.clamp(2 + power, 2, 12)
end

return Buddy
