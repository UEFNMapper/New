--!strict
--[[
	DefenseLogic : règles PURES du mini-jeu « Défense du CPU » (arcade, testables dans Lune).

	Trois bus de données mènent au processeur (à gauche). Des virus arrivent par la droite et
	avancent vers lui. On installe des antivirus sur les emplacements (3 bus × 4 colonnes) avec
	l'énergie, qui se recharge toute seule et à chaque virus éliminé. Un antivirus tire sur le
	virus le plus avancé de SON bus, devant lui et à portée. Un virus qui atteint le processeur
	lui retire un point de vie. Gagné à `Target` virus éliminés ; perdu si le processeur tombe à 0
	(ou si le temps maximal est écoulé).

	Coordonnées : terrain Core.FIELD_W × Core.FIELD_H (900 × 500).
]]

local Core = require(script.Parent.Core)

local DefenseLogic = {}

DefenseLogic.LANES = 3
DefenseLogic.COLUMNS = 4
DefenseLogic.LANE_Y = table.freeze({ 140, 265, 390 })
DefenseLogic.SLOT_X = table.freeze({ 250, 380, 510, 640 })
DefenseLogic.CPU_X = 80
DefenseLogic.LEAK_X = 130 -- un virus qui passe ce point touche le processeur
DefenseLogic.SPAWN_X = 930
DefenseLogic.MAX_ENERGY = 20
DefenseLogic.KILL_ENERGY = 1

export type Params = {
	Target: number, -- virus à éliminer
	Duration: number, -- garde-fou (secondes)
	SpawnEvery: number, -- secondes entre deux virus au début (de plus en plus vite)
	Speed: number, -- unités / s
	ToughChance: number, -- virus casqué : 2 points de vie
	StartEnergy: number,
	EnergyPerSecond: number,
	Cost: number, -- prix d'un antivirus
	Rate: number, -- tirs / s d'un antivirus
	Range: number, -- portée devant l'antivirus
	CpuHp: number,
}

local ROWS: { Params } = {
	{
		Target = 12,
		Duration = 90,
		SpawnEvery = 2.4,
		Speed = 55,
		ToughChance = 0,
		StartEnergy = 8,
		EnergyPerSecond = 1.0,
		Cost = 4,
		Rate = 1.2,
		Range = 520,
		CpuHp = 5,
	},
	{
		Target = 14,
		Duration = 90,
		SpawnEvery = 2.2,
		Speed = 60,
		ToughChance = 0.05,
		StartEnergy = 8,
		EnergyPerSecond = 1.0,
		Cost = 4,
		Rate = 1.2,
		Range = 520,
		CpuHp = 5,
	},
	{
		Target = 16,
		Duration = 90,
		SpawnEvery = 2.0,
		Speed = 65,
		ToughChance = 0.12,
		StartEnergy = 8,
		EnergyPerSecond = 1.0,
		Cost = 4,
		Rate = 1.25,
		Range = 500,
		CpuHp = 5,
	},
	{
		Target = 18,
		Duration = 90,
		SpawnEvery = 1.8,
		Speed = 70,
		ToughChance = 0.18,
		StartEnergy = 8,
		EnergyPerSecond = 1.05,
		Cost = 4,
		Rate = 1.3,
		Range = 500,
		CpuHp = 4,
	},
	{
		Target = 20,
		Duration = 90,
		SpawnEvery = 1.6,
		Speed = 75,
		ToughChance = 0.24,
		StartEnergy = 8,
		EnergyPerSecond = 1.05,
		Cost = 4,
		Rate = 1.3,
		Range = 480,
		CpuHp = 4,
	},
	{
		Target = 22,
		Duration = 90,
		SpawnEvery = 1.45,
		Speed = 80,
		ToughChance = 0.3,
		StartEnergy = 8,
		EnergyPerSecond = 1.1,
		Cost = 4,
		Rate = 1.35,
		Range = 480,
		CpuHp = 4,
	},
	{
		Target = 24,
		Duration = 90,
		SpawnEvery = 1.3,
		Speed = 85,
		ToughChance = 0.35,
		StartEnergy = 8,
		EnergyPerSecond = 1.1,
		Cost = 4,
		Rate = 1.4,
		Range = 460,
		CpuHp = 4,
	},
}

DefenseLogic.FIRST_SPAWN = 1.5
DefenseLogic.RAMP = 0.35 -- l'intervalle de spawn baisse de 35 % au fil des virus éliminés

export type Virus = { Id: number, Lane: number, X: number, Hp: number, Tough: boolean }
export type Turret = { Slot: number, Cooldown: number }

export type Event = {
	Kind: "Spawn" | "Shot" | "Kill" | "Leak" | "Build" | "NoEnergy" | "Occupied" | "Win" | "Lose" | "Timeout",
	Id: number?,
	Lane: number?,
	Slot: number?,
	Tough: boolean?,
}

export type State = {
	Params: Params,
	Rng: Core.Rng,
	Time: number,
	NextSpawn: number,
	Energy: number,
	CpuHp: number,
	Viruses: { Virus },
	Turrets: { [number]: Turret },
	Kills: number,
	Leaks: number,
	Spawned: number,
	LaneHistory: { number },
	Done: boolean,
	Success: boolean,
}

function DefenseLogic.Params(difficulty: number): Params
	return Core.Row(ROWS, difficulty)
end

function DefenseLogic.new(difficulty: number, seed: number): State
	local p = DefenseLogic.Params(difficulty)
	return {
		Params = p,
		Rng = Core.Rng(seed),
		Time = 0,
		NextSpawn = DefenseLogic.FIRST_SPAWN,
		Energy = p.StartEnergy,
		CpuHp = p.CpuHp,
		Viruses = {},
		Turrets = {},
		Kills = 0,
		Leaks = 0,
		Spawned = 0,
		LaneHistory = {},
		Done = false,
		Success = false,
	}
end

-- Emplacement -> (bus, colonne), et position du centre.
function DefenseLogic.SlotLane(slot: number): (number, number)
	local lane = (slot - 1) // DefenseLogic.COLUMNS + 1
	local column = (slot - 1) % DefenseLogic.COLUMNS + 1
	return lane, column
end

function DefenseLogic.SlotPosition(slot: number): (number, number)
	local lane, column = DefenseLogic.SlotLane(slot)
	return DefenseLogic.SLOT_X[column], DefenseLogic.LANE_Y[lane]
end

function DefenseLogic.TimeLeft(sim: State): number
	return math.max(0, sim.Params.Duration - sim.Time)
end

local function spawnVirus(sim: State): Virus
	local p = sim.Params
	local lane = sim.Rng:Int(1, DefenseLogic.LANES)
	local n = #sim.LaneHistory
	-- Pas trois fois de suite le même bus.
	if n >= 2 and sim.LaneHistory[n] == lane and sim.LaneHistory[n - 1] == lane then
		lane = lane % DefenseLogic.LANES + 1
	end
	table.insert(sim.LaneHistory, lane)
	sim.Spawned += 1
	local tough = sim.Spawned > 3 and sim.Rng:Chance(p.ToughChance)
	local virus: Virus =
		{ Id = sim.Spawned, Lane = lane, X = DefenseLogic.SPAWN_X, Hp = if tough then 2 else 1, Tough = tough }
	table.insert(sim.Viruses, virus)
	return virus
end

local function interval(sim: State): number
	local progress = math.clamp(sim.Kills / sim.Params.Target, 0, 1)
	return sim.Params.SpawnEvery * (1 - DefenseLogic.RAMP * progress)
end

-- Installe un antivirus sur l'emplacement `slot` (1..12).
function DefenseLogic.Build(sim: State, slot: number): { Event }
	local events: { Event } = {}
	if sim.Done or slot < 1 or slot > DefenseLogic.LANES * DefenseLogic.COLUMNS then
		return events
	end
	if sim.Turrets[slot] then
		table.insert(events, { Kind = "Occupied", Slot = slot })
		return events
	end
	if sim.Energy < sim.Params.Cost then
		table.insert(events, { Kind = "NoEnergy", Slot = slot })
		return events
	end
	sim.Energy -= sim.Params.Cost
	sim.Turrets[slot] = { Slot = slot, Cooldown = 0 }
	table.insert(events, { Kind = "Build", Slot = slot })
	return events
end

-- Avance la partie de `dt` secondes.
function DefenseLogic.Step(sim: State, dt: number): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	local p = sim.Params
	local step = math.clamp(dt, 0, Core.MAX_STEP)
	sim.Time += step
	if sim.Time >= p.Duration then
		sim.Done = true
		sim.Success = false
		table.insert(events, { Kind = "Timeout" })
		return events
	end
	sim.Energy = math.min(DefenseLogic.MAX_ENERGY, sim.Energy + p.EnergyPerSecond * step)
	-- Apparitions
	if sim.Time >= sim.NextSpawn then
		local virus = spawnVirus(sim)
		sim.NextSpawn = sim.Time + interval(sim)
		table.insert(events, { Kind = "Spawn", Id = virus.Id, Lane = virus.Lane, Tough = virus.Tough })
	end
	-- Déplacement, fuites vers le processeur
	for i = #sim.Viruses, 1, -1 do
		local virus = sim.Viruses[i]
		virus.X -= p.Speed * step
		if virus.X <= DefenseLogic.LEAK_X then
			table.remove(sim.Viruses, i)
			sim.CpuHp -= 1
			sim.Leaks += 1
			table.insert(events, { Kind = "Leak", Id = virus.Id, Lane = virus.Lane })
			if sim.CpuHp <= 0 then
				sim.Done = true
				sim.Success = false
				table.insert(events, { Kind = "Lose" })
				return events
			end
		end
	end
	-- Tirs : le virus le plus avancé du bus, devant l'antivirus et à portée
	for slot, turret in sim.Turrets do
		turret.Cooldown -= step
		if turret.Cooldown <= 0 then
			local lane = DefenseLogic.SlotLane(slot)
			local x = DefenseLogic.SlotPosition(slot)
			local best: Virus? = nil
			for _, virus in sim.Viruses do
				if virus.Lane == lane and virus.X > x - 20 and virus.X - x <= p.Range then
					if not best or virus.X < best.X then
						best = virus
					end
				end
			end
			if best then
				turret.Cooldown = 1 / p.Rate
				best.Hp -= 1
				table.insert(events, { Kind = "Shot", Slot = slot, Id = best.Id, Lane = lane })
				if best.Hp <= 0 then
					local index = table.find(sim.Viruses, best)
					if index then
						table.remove(sim.Viruses, index)
					end
					sim.Kills += 1
					sim.Energy = math.min(DefenseLogic.MAX_ENERGY, sim.Energy + DefenseLogic.KILL_ENERGY)
					table.insert(events, { Kind = "Kill", Id = best.Id, Lane = lane })
					if sim.Kills >= p.Target then
						sim.Done = true
						sim.Success = true
						table.insert(events, { Kind = "Win" })
						return events
					end
				end
			end
		end
	end
	return events
end

return table.freeze(DefenseLogic)
