--!strict
--[[
	Cooling : règles de l'épreuve du monde 4, « La surchauffe » (étape 4 du guide).
	La lave monte dans le bassin de la salle (sol rouge) : on passe de socle en socle, on relance les
	trois ventilateurs bouchés, puis on passe le plan d'alimentation de « Performances max » à
	« Équilibré ». Chaque ventilateur relancé ralentit la lave ; le plan la fait redescendre.
	La lave reste toujours sous le dessus des socles (LAVA_MAX) : elle ne tue que sur le sol du bassin.
	Hauteurs en studs au-dessus du plancher de la salle.
]]

local Cooling = {}

Cooling.FANS = 3
Cooling.LAVA_START = -0.6
Cooling.LAVA_MAX = 3.2
Cooling.PEDESTAL_MIN_TOP = 4 -- dessus du socle le plus bas (tests : LAVA_MAX < PEDESTAL_MIN_TOP)
Cooling.RISE = 0.22 -- studs / s, sans ventilateur
Cooling.FAN_SLOW = 0.25 -- part de la montée retirée par ventilateur relancé
Cooling.DRAIN = 0.9 -- studs / s une fois le plan équilibré
Cooling.TEMP_START = 97
Cooling.TEMP_PER_FAN = 12
Cooling.TEMP_PLAN = 16

-- Salle du terminal du monde 4, coordonnées de salle (u, v) : le bassin de lave (le pad d'arrivée,
-- en (0, 0), et la borne, en (12, -36), restent hors du bassin) et ses socles (dessus en studs au-dessus
-- du plancher). Fan = ventilateur à relancer, Plan = pupitre du plan d'alimentation.
Cooling.BASIN = table.freeze({ Min = Vector2.new(8, -30), Max = Vector2.new(28, 4) })
Cooling.PEDESTAL_SIZE = 5
export type Pedestal = { U: number, V: number, Top: number, Fan: number?, Plan: boolean? }
Cooling.PEDESTALS = table.freeze({
	{ U = 12.5, V = -1, Top = 4 },
	{ U = 18.5, V = 1.5, Top = 5 },
	{ U = 24.5, V = -3.5, Top = 6, Fan = 1 },
	{ U = 21, V = -10.5, Top = 5 },
	{ U = 14.5, V = -14, Top = 4.5, Fan = 2 },
	{ U = 20.5, V = -20, Top = 5.5 },
	{ U = 25.5, V = -26, Top = 6.5, Fan = 3 },
	{ U = 13.5, V = -25, Top = 5, Plan = true },
} :: { Pedestal })

-- Le point (u, v) est-il dans le bassin, hors des socles ?
function Cooling.InLava(u: number, v: number): boolean
	local basin = Cooling.BASIN
	if u < basin.Min.X or u > basin.Max.X or v < basin.Min.Y or v > basin.Max.Y then
		return false
	end
	local half = Cooling.PEDESTAL_SIZE / 2
	for _, ped in Cooling.PEDESTALS do
		if math.abs(u - ped.U) <= half and math.abs(v - ped.V) <= half then
			return false
		end
	end
	return true
end

export type State = {
	Lava: number,
	Fans: { boolean },
	Balanced: boolean,
	Done: boolean,
	Time: number,
}

function Cooling.new(): State
	local fans = {}
	for i = 1, Cooling.FANS do
		fans[i] = false
	end
	return { Lava = Cooling.LAVA_START, Fans = fans, Balanced = false, Done = false, Time = 0 }
end

function Cooling.FansOn(state: State): number
	local count = 0
	for _, on in state.Fans do
		if on then
			count += 1
		end
	end
	return count
end

function Cooling.Temperature(state: State): number
	return Cooling.TEMP_START
		- Cooling.TEMP_PER_FAN * Cooling.FansOn(state)
		- (if state.Balanced then Cooling.TEMP_PLAN else 0)
end

function Cooling.Step(state: State, dt: number)
	if state.Done then
		return
	end
	local step = math.max(dt, 0)
	state.Time += step
	if state.Balanced then
		state.Lava -= Cooling.DRAIN * step
		if state.Lava <= Cooling.LAVA_START then
			state.Lava = Cooling.LAVA_START
			state.Done = true
		end
		return
	end
	local rate = Cooling.RISE * math.max(0, 1 - Cooling.FAN_SLOW * Cooling.FansOn(state))
	state.Lava = math.min(Cooling.LAVA_MAX, state.Lava + rate * step)
end

function Cooling.Restart(state: State, fan: number): boolean
	if state.Balanced or state.Fans[fan] ~= false then
		return false
	end
	state.Fans[fan] = true
	return true
end

export type PlanResult = "Ok" | "FansFirst" | "Already"

function Cooling.SetBalanced(state: State): PlanResult
	if state.Balanced then
		return "Already"
	end
	if Cooling.FansOn(state) < Cooling.FANS then
		return "FansFirst"
	end
	state.Balanced = true
	return "Ok"
end

-- Le joueur à `height` studs au-dessus du plancher (pieds), dans le bassin : touché par la lave ?
function Cooling.Burns(state: State, feetHeight: number): boolean
	return not state.Done and feetHeight < state.Lava + 0.2
end

return table.freeze(Cooling)
