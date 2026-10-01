--!strict
--[[
	CpuDefense : règles de l'épreuve du monde 5, « Défense du CPU » (tour de défense du guide : le
	virus envoie des vagues de processus vers le CPU ; on pose des « optimisations » comme tourelles).
	Plan 2D (x, y) en studs : les processus suivent des bus (lignes brisées) jusqu'au processeur ; une
	optimisation tire sur le processus le plus avancé à portée. Énergie : se recharge, +KILL_ENERGY par
	processus arrêté, COST par optimisation. Gagné à Target processus arrêtés ; perdu si le processeur
	tombe à 0.
]]

local CpuDefense = {}

export type Params = {
	Target: number,
	SpawnEvery: number,
	Speed: number,
	ToughChance: number,
	StartEnergy: number,
	EnergyPerSecond: number,
	Cost: number,
	Rate: number,
	Range: number,
	CpuHp: number,
	Duration: number,
}

CpuDefense.PARAMS = table.freeze({
	Target = 16,
	SpawnEvery = 1.7,
	Speed = 3.4,
	ToughChance = 0.25,
	StartEnergy = 8,
	EnergyPerSecond = 0.9,
	Cost = 4,
	Rate = 1.4,
	Range = 8.5,
	CpuHp = 4,
	Duration = 120,
} :: Params)

CpuDefense.MAX_ENERGY = 16
CpuDefense.KILL_ENERGY = 1
CpuDefense.FIRST_SPAWN = 2
CpuDefense.RAMP = 0.35

-- Noms affichés des optimisations (une par emplacement, dans l'ordre) : de vrais réglages de l'app.
CpuDefense.OPTIMISATIONS = table.freeze({
	"Mode jeu",
	"Plan Performances",
	"Nettoyage RAM",
	"Télémétrie coupée",
	"Priorité au jeu",
	"Démarrage allégé",
})

export type Layout = { Paths: { { Vector2 } }, Slots: { Vector2 } }

-- Plan de la salle du terminal du monde 5, en coordonnées de salle (u, v) : u le long de F, v le long
-- de R (voir Common.House ; le pad d'arrivée est en (0, 0), la borne en (12, -36)). Les processus
-- sortent des ports du mur intérieur (v = 6) et descendent vers le processeur (16, -27).
CpuDefense.CPU = Vector2.new(16, -27)
CpuDefense.ROOM_LAYOUT = table.freeze({
	Paths = {
		{ Vector2.new(10, 5), Vector2.new(10, -18), Vector2.new(14.5, -24) },
		{ Vector2.new(16, 5), Vector2.new(16, -24) },
		{ Vector2.new(22, 5), Vector2.new(22, -18), Vector2.new(17.5, -24) },
	},
	Slots = {
		Vector2.new(7, -6),
		Vector2.new(13, -2),
		Vector2.new(19, -2),
		Vector2.new(25, -6),
		Vector2.new(13, -15),
		Vector2.new(19, -15),
	},
} :: Layout)

export type Virus = { Id: number, Path: number, Distance: number, Hp: number, Tough: boolean }

export type Event = {
	Kind: "Spawn" | "Shot" | "Kill" | "Leak" | "Build" | "NoEnergy" | "Occupied" | "Win" | "Lose" | "Timeout",
	Id: number?,
	Slot: number?,
	Path: number?,
	Tough: boolean?,
}

export type State = {
	Params: Params,
	Layout: Layout,
	Lengths: { number },
	Seed: number,
	Time: number,
	NextSpawn: number,
	Energy: number,
	CpuHp: number,
	Viruses: { Virus },
	Turrets: { [number]: number }, -- emplacement -> recharge restante
	Kills: number,
	Leaks: number,
	Spawned: number,
	Done: boolean,
	Success: boolean,
}

local function pathLength(points: { Vector2 }): number
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	return total
end

-- Générateur déterministe (Park-Miller) : même graine, même partie.
local function rand(state: State): number
	state.Seed = (state.Seed * 16807) % 2147483647
	return state.Seed / 2147483647
end

function CpuDefense.new(layout: Layout, seed: number, params: Params?): State
	local lengths = {}
	for index, points in layout.Paths do
		lengths[index] = pathLength(points)
	end
	local p = params or CpuDefense.PARAMS
	return {
		Params = p,
		Layout = layout,
		Lengths = lengths,
		Seed = math.max(1, math.floor(seed) % 2147483646),
		Time = 0,
		NextSpawn = CpuDefense.FIRST_SPAWN,
		Energy = p.StartEnergy,
		CpuHp = p.CpuHp,
		Viruses = {},
		Turrets = {},
		Kills = 0,
		Leaks = 0,
		Spawned = 0,
		Done = false,
		Success = false,
	}
end

-- Position d'un processus sur son bus.
function CpuDefense.Position(state: State, virus: Virus): Vector2
	local points = state.Layout.Paths[virus.Path]
	local left = virus.Distance
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local length = (b - a).Magnitude
		if left <= length then
			return a + (b - a) * (left / math.max(length, 1e-6))
		end
		left -= length
	end
	return points[#points]
end

function CpuDefense.Build(state: State, slot: number): { Event }
	local events: { Event } = {}
	if state.Done or not state.Layout.Slots[slot] then
		return events
	end
	if state.Turrets[slot] then
		table.insert(events, { Kind = "Occupied", Slot = slot })
	elseif state.Energy < state.Params.Cost then
		table.insert(events, { Kind = "NoEnergy", Slot = slot })
	else
		state.Energy -= state.Params.Cost
		state.Turrets[slot] = 0
		table.insert(events, { Kind = "Build", Slot = slot })
	end
	return events
end

function CpuDefense.Step(state: State, dt: number): { Event }
	local events: { Event } = {}
	if state.Done then
		return events
	end
	local p = state.Params
	local step = math.clamp(dt, 0, 0.1)
	state.Time += step
	if state.Time >= p.Duration then
		state.Done = true
		table.insert(events, { Kind = "Timeout" })
		return events
	end
	state.Energy = math.min(CpuDefense.MAX_ENERGY, state.Energy + p.EnergyPerSecond * step)
	if state.Time >= state.NextSpawn then
		state.Spawned += 1
		local path = math.floor(rand(state) * #state.Layout.Paths) + 1
		local tough = state.Spawned > 3 and rand(state) < p.ToughChance
		table.insert(
			state.Viruses,
			{ Id = state.Spawned, Path = path, Distance = 0, Hp = if tough then 2 else 1, Tough = tough }
		)
		table.insert(events, { Kind = "Spawn", Id = state.Spawned, Path = path, Tough = tough })
		local progress = math.clamp(state.Kills / p.Target, 0, 1)
		state.NextSpawn = state.Time + p.SpawnEvery * (1 - CpuDefense.RAMP * progress)
	end
	for i = #state.Viruses, 1, -1 do
		local virus = state.Viruses[i]
		virus.Distance += p.Speed * step
		if virus.Distance >= state.Lengths[virus.Path] then
			table.remove(state.Viruses, i)
			state.CpuHp -= 1
			state.Leaks += 1
			table.insert(events, { Kind = "Leak", Id = virus.Id, Path = virus.Path })
			if state.CpuHp <= 0 then
				state.Done = true
				table.insert(events, { Kind = "Lose" })
				return events
			end
		end
	end
	for slot, cooldown in state.Turrets do
		local left = cooldown - step
		if left <= 0 then
			local origin = state.Layout.Slots[slot]
			local best: Virus? = nil
			for _, virus in state.Viruses do
				if (CpuDefense.Position(state, virus) - origin).Magnitude <= p.Range then
					if not best or virus.Distance > best.Distance then
						best = virus
					end
				end
			end
			if best then
				left = 1 / p.Rate
				best.Hp -= 1
				table.insert(events, { Kind = "Shot", Slot = slot, Id = best.Id })
				if best.Hp <= 0 then
					local index = table.find(state.Viruses, best)
					if index then
						table.remove(state.Viruses, index)
					end
					state.Kills += 1
					state.Energy = math.min(CpuDefense.MAX_ENERGY, state.Energy + CpuDefense.KILL_ENERGY)
					table.insert(events, { Kind = "Kill", Id = best.Id })
					if state.Kills >= p.Target then
						state.Done = true
						state.Success = true
						table.insert(events, { Kind = "Win" })
						return events
					end
				end
			else
				left = 0
			end
		end
		state.Turrets[slot] = left
	end
	return events
end

-- Score : santé du processeur restante, sur 100.
function CpuDefense.Score(state: State): number
	return math.floor(100 * state.CpuHp / state.Params.CpuHp + 0.5)
end

return table.freeze(CpuDefense)
