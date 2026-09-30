--!strict
--[[
	ShellGlow : la tour qui s'allume monde par monde (docs/AUDIT_V3.md, C2), logique PURE.
	Utilisée par Controllers/TowerGlow (néons de la coque tagués ShellLight, attribut World).
	- World 1..7 : bande de hauteur du monde ; World 0 : toute la tour (bouton d'alimentation…)
	- Infecté : rouge / violet terne qui clignote et « glitche » ; nettoyé : couleur du monde
	- Victoire : arc-en-ciel qui monte le long de la tour
]]

local Tower = require(script.Parent.Parent.Config.Tower)

local ShellGlow = {}

ShellGlow.BAND = 100 -- hauteur d'un monde (World/Tower/Common)
ShellGlow.HEIGHT = ShellGlow.BAND * Tower.WORLD_COUNT + 50 -- plafond de la tour
ShellGlow.WAVE_SECONDS = 1.6 -- vague « monde nettoyé »
ShellGlow.CASCADE_SECONDS = 4 -- cascade arc-en-ciel de la victoire

ShellGlow.InfectedRed = Color3.fromRGB(255, 46, 84)
ShellGlow.InfectedViolet = Color3.fromRGB(150, 60, 255)

-- Monde de la bande de hauteur `y` (1..WORLD_COUNT).
function ShellGlow.BandOf(y: number): number
	return math.clamp(math.floor(y / ShellGlow.BAND) + 1, 1, Tower.WORLD_COUNT)
end

-- Découpe une bande verticale [y0, y1] aux limites des mondes (espace `gap` entre deux morceaux).
function ShellGlow.Segments(y0: number, y1: number, gap: number): { { World: number, Y0: number, Y1: number } }
	local out = {}
	for w = ShellGlow.BandOf(y0), ShellGlow.BandOf(y1) do
		local base = (w - 1) * ShellGlow.BAND
		local top = if w == Tower.WORLD_COUNT then math.huge else base + ShellGlow.BAND
		local a = math.max(y0, base + (if w > 1 then gap / 2 else 0))
		local b = math.min(y1, top - (if w < Tower.WORLD_COUNT then gap / 2 else 0))
		if b - a > 0.5 then
			table.insert(out, { World = w, Y0 = a, Y1 = b })
		end
	end
	return out
end

-- Le néon du monde `world` est-il propre pour ce joueur ? (World 0 = toute la tour)
function ShellGlow.IsClean(world: number, cleared: number): boolean
	if world <= 0 then
		return cleared >= Tower.WORLD_COUNT
	end
	return cleared >= world
end

-- Tour entière nettoyée après une victoire (Cleared reste à WORLD_COUNT jusqu'au départ suivant).
function ShellGlow.IsVictory(cleared: number, stage: number, runStarted: boolean): boolean
	return cleared >= Tower.WORLD_COUNT and stage == 0 and not runStarted
end

local function frac(x: number): number
	return x - math.floor(x)
end

-- Bruit déterministe 0..1 (même résultat pour un même temps / une même graine).
local function hash(x: number): number
	return frac(math.sin(x * 12.9898) * 43758.5453)
end

-- Luminosité 0..1 d'un néon infecté : faible, qui vacille, avec des coupures « glitch ».
-- `reduced` (ReducedMotion) : lumière fixe, sans clignotement.
function ShellGlow.InfectedLevel(t: number, seed: number, reduced: boolean): number
	if reduced then
		return 0.45
	end
	local tick = math.floor(t * 12)
	if hash(tick + seed * 97.13) > 0.92 then
		return 0.05 -- coupure
	end
	local wobble = 0.5 + 0.5 * math.sin(t * 7 + seed * 6.28)
	return 0.3 + 0.3 * wobble + 0.15 * hash(tick * 0.37 + seed)
end

-- Mélange rouge -> violet 0..1 d'un néon infecté (fixe en ReducedMotion).
function ShellGlow.InfectedMix(t: number, seed: number, reduced: boolean): number
	if reduced then
		return 0.3
	end
	return 0.5 + 0.5 * math.sin(t * 1.3 + seed * 11)
end

-- Intensité 0..1 de la vague « monde nettoyé » sur un néon placé à `along` (0..1) dans sa bande,
-- `elapsed` secondes après le nettoyage. La crête balaie la bande d'un bout à l'autre.
function ShellGlow.Wave(elapsed: number, along: number): number
	if elapsed < 0 or elapsed > ShellGlow.WAVE_SECONDS then
		return 0
	end
	local front = elapsed / ShellGlow.WAVE_SECONDS * 1.4 - 0.2
	local k = 1 - math.abs(front - math.clamp(along, 0, 1)) / 0.2
	return math.clamp(k, 0, 1)
end

-- Teinte arc-en-ciel (0..1) d'un néon à la hauteur relative `height` (0..1) au temps `t`.
function ShellGlow.RainbowHue(t: number, height: number): number
	return frac(height * 0.85 - t * 0.12)
end

-- Cascade de victoire : 0 = pas encore atteint, 1 = arc-en-ciel ; crête blanche au front.
-- Renvoie (atteint, éclat du front 0..1).
function ShellGlow.Cascade(elapsed: number, height: number): (boolean, number)
	if elapsed < 0 then
		return false, 0
	end
	local front = elapsed / ShellGlow.CASCADE_SECONDS * 1.15
	local h = math.clamp(height, 0, 1)
	if h > front then
		return false, 0
	end
	return true, math.clamp(1 - (front - h) / 0.08, 0, 1)
end

return table.freeze(ShellGlow)
