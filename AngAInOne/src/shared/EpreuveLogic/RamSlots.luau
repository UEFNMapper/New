--!strict
--[[
	RamSlots : règles de l'épreuve du monde 2, « La RAM saturée » (étape 3 du guide).
	1. Les deux barrettes sont en A1 et B1 : avec deux barrettes, la carte mère attend A2 + B2 (double
	   canal). On retire une barrette (on la porte), on l'insère dans un emplacement libre.
	2. Une fois en A2 + B2, la mémoire se remplit de déchets ; le gros bouton « Libérer la RAM » la vide
	   (recharge entre deux appuis). Trois libérations : réussi. Au-delà de SLOW_FROM %, le joueur ralentit.
]]

local RamSlots = {}

RamSlots.SLOTS = table.freeze({ "A1", "A2", "B1", "B2" })
RamSlots.START = table.freeze({ 1, 3 }) -- barrette 1 en A1, barrette 2 en B1
RamSlots.TARGET = table.freeze({ [2] = true, [4] = true }) -- A2 et B2
RamSlots.FLUSHES = 3
RamSlots.COOLDOWN = 4 -- s entre deux libérations
RamSlots.FILL_START = 55 -- % au début de l'étape 2
RamSlots.FILL_PER_SECOND = 7
RamSlots.FLUSH_TO = 15
RamSlots.SLOW_FROM = 85
RamSlots.SLOW_FACTOR = 0.6

export type Phase = "Slots" | "Flush" | "Done"

export type State = {
	Sticks: { number }, -- emplacement de chaque barrette (0 = portée par le joueur)
	Carrying: number?, -- barrette portée
	Phase: Phase,
	Ram: number, -- %
	Flushes: number,
	LastFlush: number,
	Moves: number,
}

function RamSlots.new(): State
	return {
		Sticks = { RamSlots.START[1], RamSlots.START[2] },
		Carrying = nil,
		Phase = "Slots",
		Ram = 98,
		Flushes = 0,
		LastFlush = -math.huge,
		Moves = 0,
	}
end

-- Barrette posée dans l'emplacement `slot` (nil = vide).
function RamSlots.StickIn(state: State, slot: number): number?
	for stick, at in state.Sticks do
		if at == slot then
			return stick
		end
	end
	return nil
end

function RamSlots.DualChannel(state: State): boolean
	for _, at in state.Sticks do
		if not RamSlots.TARGET[at] then
			return false
		end
	end
	return true
end

-- Retire la barrette `stick` (les mains doivent être libres).
function RamSlots.Take(state: State, stick: number): boolean
	if state.Phase ~= "Slots" or state.Carrying ~= nil or state.Sticks[stick] == nil or state.Sticks[stick] == 0 then
		return false
	end
	state.Sticks[stick] = 0
	state.Carrying = stick
	return true
end

-- Insère la barrette portée dans l'emplacement libre `slot`. Passe à l'étape 2 en double canal.
function RamSlots.Insert(state: State, slot: number): boolean
	local stick = state.Carrying
	if state.Phase ~= "Slots" or not stick or slot < 1 or slot > #RamSlots.SLOTS or RamSlots.StickIn(state, slot) then
		return false
	end
	state.Sticks[stick] = slot
	state.Carrying = nil
	state.Moves += 1
	if RamSlots.DualChannel(state) then
		state.Phase = "Flush"
		state.Ram = RamSlots.FILL_START
	end
	return true
end

-- Remplissage de la mémoire pendant l'étape 2.
function RamSlots.Step(state: State, dt: number)
	if state.Phase == "Flush" then
		state.Ram = math.min(100, state.Ram + RamSlots.FILL_PER_SECOND * math.max(dt, 0))
	end
end

export type FlushResult = "Ok" | "Cooldown" | "NotYet"

function RamSlots.Flush(state: State, now: number): FlushResult
	if state.Phase ~= "Flush" then
		return "NotYet"
	end
	if now - state.LastFlush < RamSlots.COOLDOWN then
		return "Cooldown"
	end
	state.LastFlush = now
	state.Flushes += 1
	state.Ram = RamSlots.FLUSH_TO
	if state.Flushes >= RamSlots.FLUSHES then
		state.Phase = "Done"
	end
	return "Ok"
end

function RamSlots.SpeedFactor(state: State): number
	return if state.Phase == "Flush" and state.Ram >= RamSlots.SLOW_FROM then RamSlots.SLOW_FACTOR else 1
end

-- Score : 100 avec le minimum de déplacements (2), −10 par déplacement en trop (au moins 50).
function RamSlots.Score(state: State): number
	return math.max(50, 100 - 10 * math.max(0, state.Moves - 2))
end

return table.freeze(RamSlots)
