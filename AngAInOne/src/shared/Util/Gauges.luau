--!strict
--[[
	Gauges : la logique PURE des jauges de PC qui changent la façon de jouer (docs/SCENARIO.md §9),
	calquées sur le Tableau de bord de l'app AngAInOne :
	- RAM (monde 2, Memory Lanes) : la mémoire se remplit tant qu'on est dans le monde ; au-delà de
	  RAM_SLOW_FROM, le joueur ralentit (jusqu'à RAM_MIN_FACTOR à 100 %). Les boutons géants
	  « Libérer la RAM » la vident d'un coup (cooldown par bouton).
	- Chaleur (monde 4, Cryo Tower) : le CPU chauffe quand on court, refroidit à l'arrêt, plus vite
	  près d'un ventilateur relancé ; à HEAT_MAX, plantage thermique (mort « Overheat »).
	Le client applique ces valeurs (Controllers/Gauges) ; tout est testé dans tests/gauges.spec.luau.
]]

local Gauges = {}

-- RAM (en %)
Gauges.RAM_FILL_PER_SECOND = 2.2 -- 0 → 100 % en ≈ 45 s
Gauges.RAM_SLOW_FROM = 70 -- en dessous : vitesse normale
Gauges.RAM_MIN_FACTOR = 0.55 -- vitesse à 100 %
Gauges.RAM_FLUSH_COOLDOWN = 12 -- s, par bouton

-- Chaleur (en °C)
Gauges.HEAT_IDLE = 40
Gauges.HEAT_WARN = 85
Gauges.HEAT_MAX = 100
Gauges.HEAT_RUN_PER_SECOND = 2.6 -- en mouvement : 40 → 100 en ≈ 23 s de course continue
Gauges.HEAT_REST_PER_SECOND = 9 -- à l'arrêt
Gauges.HEAT_COOL_PER_SECOND = 22 -- près d'un ventilateur relancé (zone fraîche)
Gauges.COOL_ZONE_RADIUS = 14 -- studs

local function clamp(value: number, low: number, high: number): number
	return math.max(low, math.min(high, value))
end

-- RAM : nouvelle valeur après `dt` secondes passées dans le monde.
function Gauges.RamStep(ram: number, dt: number): number
	return clamp(ram + Gauges.RAM_FILL_PER_SECOND * dt, 0, 100)
end

-- RAM : facteur de vitesse (1 = normal) pour un remplissage donné.
function Gauges.RamSpeedFactor(ram: number): number
	if ram <= Gauges.RAM_SLOW_FROM then
		return 1
	end
	local t = (clamp(ram, Gauges.RAM_SLOW_FROM, 100) - Gauges.RAM_SLOW_FROM) / (100 - Gauges.RAM_SLOW_FROM)
	return 1 - t * (1 - Gauges.RAM_MIN_FACTOR)
end

-- RAM : peut-on appuyer sur ce bouton ? (`lastFlush` = dernier appui sur CE bouton, nil = jamais)
function Gauges.CanFlush(now: number, lastFlush: number?): boolean
	return lastFlush == nil or now - lastFlush >= Gauges.RAM_FLUSH_COOLDOWN
end

-- Chaleur : nouvelle valeur après `dt` secondes (moving = le joueur court ; cool = près d'une zone fraîche).
function Gauges.HeatStep(heat: number, dt: number, moving: boolean, cool: boolean): number
	local rate = if cool
		then -Gauges.HEAT_COOL_PER_SECOND
		elseif moving then Gauges.HEAT_RUN_PER_SECOND
		else -Gauges.HEAT_REST_PER_SECOND
	return clamp(heat + rate * dt, Gauges.HEAT_IDLE, Gauges.HEAT_MAX)
end

-- Chaleur : état lisible pour l'interface.
function Gauges.HeatState(heat: number): string
	if heat >= Gauges.HEAT_MAX then
		return "Crash"
	elseif heat >= Gauges.HEAT_WARN then
		return "Warn"
	elseif heat >= 65 then
		return "Hot"
	end
	return "Ok"
end

return Gauges
