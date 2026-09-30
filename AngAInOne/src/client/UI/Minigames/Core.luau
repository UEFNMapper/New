--!strict
--[[
	Core : outils PURS partagés par la logique des mini-jeux antivirus (aucune instance
	Roblox : testable dans Lune).

	- Terrain logique : FIELD_W x FIELD_H unités. L'interface affiche le terrain dans une
	  zone au même rapport largeur/hauteur (UIAspectRatioConstraint) : 1 unité = même
	  distance à l'horizontale et à la verticale, les cercles restent des cercles.
	- Difficulté : entier 1..7 (index du monde). Level() borne et arrondit.
	  8 (BOSS_LEVEL) = combat final contre LAGZ : IsBoss() le repère ; les jeux sans
	  variante dédiée jouent alors avec les réglages du niveau 7.
	- Rng : générateur pseudo-aléatoire déterministe (Park-Miller) : même graine = même
	  partie, ce qui rend les tests reproductibles.
]]

local Core = {}

Core.FIELD_W = 900
Core.FIELD_H = 500
Core.MIN_LEVEL = 1
Core.MAX_LEVEL = 7
Core.BOSS_LEVEL = 8 -- phase 3 du boss LAGZ (monde 7)

-- Pas de simulation maximal : après un gel d'image (onglet en arrière-plan, chargement),
-- la partie ne "saute" jamais plus de 1/20 s d'un coup.
Core.MAX_STEP = 1 / 20

-- Difficulté bornée et arrondie (1..7). Une valeur invalide donne 1.
function Core.Level(difficulty: number?): number
	if type(difficulty) ~= "number" or difficulty ~= difficulty then
		return Core.MIN_LEVEL
	end
	return math.clamp(math.floor(difficulty + 0.5), Core.MIN_LEVEL, Core.MAX_LEVEL)
end

-- Difficulté 8 = combat final contre LAGZ (valeur exacte, après arrondi).
function Core.IsBoss(difficulty: number?): boolean
	return type(difficulty) == "number" and difficulty == difficulty and math.floor(difficulty + 0.5) == Core.BOSS_LEVEL
end

-- Ligne de la table de réglages correspondant à la difficulté.
function Core.Row<T>(rows: { T }, difficulty: number?): T
	return rows[math.min(Core.Level(difficulty), #rows)]
end

function Core.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Nombre de secondes affiché sur le chrono (arrondi au-dessus, jamais négatif).
function Core.DisplaySeconds(seconds: number): number
	return math.max(0, math.ceil(seconds - 1e-6))
end

------------------------------------------------------------------------------------
-- Générateur pseudo-aléatoire déterministe
------------------------------------------------------------------------------------

export type Rng = {
	Next: (self: Rng) -> number, -- [0, 1[
	Range: (self: Rng, low: number, high: number) -> number, -- [low, high[
	Int: (self: Rng, low: number, high: number) -> number, -- entier dans [low, high]
	Chance: (self: Rng, probability: number) -> boolean,
	Shuffle: (self: Rng, list: { any }) -> (),
}

local MODULUS = 2147483647 -- 2^31 - 1
local MULTIPLIER = 48271 -- produit < 2^53 : calcul exact en double précision

local RngMethods = {}
RngMethods.__index = RngMethods

function RngMethods.Next(self: any): number
	self._state = (self._state * MULTIPLIER) % MODULUS
	return (self._state - 1) / (MODULUS - 1)
end

function RngMethods.Range(self: any, low: number, high: number): number
	return low + (high - low) * self:Next()
end

function RngMethods.Int(self: any, low: number, high: number): number
	if high <= low then
		return low
	end
	return math.min(low + math.floor(self:Next() * (high - low + 1)), high)
end

function RngMethods.Chance(self: any, probability: number): boolean
	return self:Next() < probability
end

-- Mélange de Fisher-Yates, sur place.
function RngMethods.Shuffle(self: any, list: { any })
	for i = #list, 2, -1 do
		local j = self:Int(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

function Core.Rng(seed: number): Rng
	local start = math.floor(math.abs(seed)) % (MODULUS - 1) + 1
	local rng = setmetatable({ _state = start }, RngMethods)
	-- Quelques tours à vide : deux graines proches donnent vite des suites différentes.
	for _ = 1, 3 do
		rng:Next()
	end
	return (rng :: any) :: Rng
end

return table.freeze(Core)
