--!strict
--[[
	ScanLogic : règles PURES du mini-jeu "Scan" (testables dans Lune).

	Des virus surgissent dans les cases d'une grille puis s'enfuient au bout de
	`Lifetime` secondes. Il faut en toucher `Target` avant la fin du chrono.
	Parfois, un gentil fichier apparaît à la place : le toucher retire un point.

	Utilisation (interface) :
		local sim = ScanLogic.new(difficulté, graine)
		chaque image : for _, e in ScanLogic.Step(sim, dt) do ... end
		au toucher d'une case : ScanLogic.Tap(sim, index) -> événements
]]

local Core = require(script.Parent.Core)

local ScanLogic = {}

export type Params = {
	Cols: number,
	Rows: number,
	Duration: number, -- secondes de jeu
	Target: number, -- virus à toucher pour gagner
	Lifetime: number, -- secondes avant qu'un virus s'enfuie
	SpawnEvery: number, -- secondes entre deux apparitions (en moyenne)
	MaxAlive: number, -- objets visibles en même temps au maximum
	FileChance: number, -- probabilité qu'une apparition soit un fichier (piège)
}

-- Réglages par difficulté (1 = 8 ans tranquille, 7 = vrai défi).
local ROWS: { Params } = {
	{
		Cols = 3,
		Rows = 3,
		Duration = 35,
		Target = 15,
		Lifetime = 2.0,
		SpawnEvery = 1.1,
		MaxAlive = 2,
		FileChance = 0.1,
	},
	{
		Cols = 3,
		Rows = 3,
		Duration = 35,
		Target = 16,
		Lifetime = 1.75,
		SpawnEvery = 0.95,
		MaxAlive = 2,
		FileChance = 0.14,
	},
	{
		Cols = 3,
		Rows = 3,
		Duration = 33,
		Target = 18,
		Lifetime = 1.55,
		SpawnEvery = 0.82,
		MaxAlive = 3,
		FileChance = 0.18,
	},
	{
		Cols = 4,
		Rows = 3,
		Duration = 32,
		Target = 20,
		Lifetime = 1.4,
		SpawnEvery = 0.72,
		MaxAlive = 3,
		FileChance = 0.2,
	},
	{
		Cols = 4,
		Rows = 3,
		Duration = 32,
		Target = 22,
		Lifetime = 1.25,
		SpawnEvery = 0.64,
		MaxAlive = 3,
		FileChance = 0.24,
	},
	{
		Cols = 4,
		Rows = 4,
		Duration = 30,
		Target = 24,
		Lifetime = 1.1,
		SpawnEvery = 0.56,
		MaxAlive = 4,
		FileChance = 0.27,
	},
	{
		Cols = 4,
		Rows = 4,
		Duration = 30,
		Target = 26,
		Lifetime = 0.95,
		SpawnEvery = 0.5,
		MaxAlive = 4,
		FileChance = 0.3,
	},
}

ScanLogic.FIRST_SPAWN = 0.5 -- délai avant le premier virus
ScanLogic.SAFE_SPAWNS = 2 -- les premières apparitions sont toujours des virus
ScanLogic.CELL_COOLDOWN = 0.3 -- une case libérée reste vide un court instant
ScanLogic.FILE_LIFETIME_FACTOR = 1.3 -- un fichier reste un peu plus longtemps

export type Kind = "Empty" | "Virus" | "File"

export type Cell = {
	Kind: Kind,
	Id: number, -- identifiant unique de l'occupant (0 si vide)
	Born: number,
	Dies: number,
	FreeAt: number, -- instant à partir duquel la case peut resservir
}

export type Event = {
	Kind: "Spawn" | "Escape" | "Hit" | "Oops" | "Win" | "Timeout",
	Cell: number, -- 0 pour Win / Timeout
	What: Kind?, -- occupant concerné (Spawn, Escape)
	Id: number?,
	Life: number?, -- durée de vie (Spawn)
}

export type State = {
	Params: Params,
	Rng: Core.Rng,
	Time: number,
	NextSpawn: number,
	Cells: { Cell },
	Hits: number,
	Oops: number,
	Escaped: number,
	Spawned: number,
	NextId: number,
	Combo: number, -- virus touchés d'affilée (ni fuite ni fichier)
	Done: boolean,
	Success: boolean,
}

function ScanLogic.Params(difficulty: number): Params
	return Core.Row(ROWS, difficulty)
end

function ScanLogic.new(difficulty: number, seed: number): State
	local params = ScanLogic.Params(difficulty)
	local cells: { Cell } = {}
	for i = 1, params.Cols * params.Rows do
		cells[i] = { Kind = "Empty", Id = 0, Born = 0, Dies = 0, FreeAt = 0 }
	end
	return {
		Params = params,
		Rng = Core.Rng(seed),
		Time = 0,
		NextSpawn = ScanLogic.FIRST_SPAWN,
		Cells = cells,
		Hits = 0,
		Oops = 0,
		Escaped = 0,
		Spawned = 0,
		NextId = 1,
		Combo = 0,
		Done = false,
		Success = false,
	}
end

function ScanLogic.TimeLeft(sim: State): number
	return math.max(0, sim.Params.Duration - sim.Time)
end

function ScanLogic.Alive(sim: State): number
	local count = 0
	for _, cell in sim.Cells do
		if cell.Kind ~= "Empty" then
			count += 1
		end
	end
	return count
end

local function clear(cell: Cell, now: number)
	cell.Kind = "Empty"
	cell.Id = 0
	cell.FreeAt = now + ScanLogic.CELL_COOLDOWN
end

-- Fait apparaître un virus (ou un fichier) dans une case libre ; renvoie l'événement ou nil.
local function spawn(sim: State): Event?
	local free = {}
	for index, cell in sim.Cells do
		if cell.Kind == "Empty" and cell.FreeAt <= sim.Time then
			table.insert(free, index)
		end
	end
	if #free == 0 or ScanLogic.Alive(sim) >= sim.Params.MaxAlive then
		return nil
	end
	local index = free[sim.Rng:Int(1, #free)]
	local isFile = sim.Spawned >= ScanLogic.SAFE_SPAWNS and sim.Rng:Chance(sim.Params.FileChance)
	local kind: Kind = if isFile then "File" else "Virus"
	local life = sim.Params.Lifetime * (if isFile then ScanLogic.FILE_LIFETIME_FACTOR else 1)
	local cell = sim.Cells[index]
	cell.Kind = kind
	cell.Id = sim.NextId
	cell.Born = sim.Time
	cell.Dies = sim.Time + life
	sim.NextId += 1
	sim.Spawned += 1
	return { Kind = "Spawn", Cell = index, What = kind, Id = cell.Id, Life = life }
end

-- Avance la partie de `dt` secondes. Renvoie les événements survenus, dans l'ordre.
function ScanLogic.Step(sim: State, dt: number): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	sim.Time += math.clamp(dt, 0, Core.MAX_STEP)

	-- Fuites : les virus (et fichiers) dont le temps est écoulé disparaissent.
	for index, cell in sim.Cells do
		if cell.Kind ~= "Empty" and sim.Time >= cell.Dies then
			local what: Kind = cell.Kind
			local id = cell.Id
			if what == "Virus" then
				sim.Escaped += 1
				sim.Combo = 0
			end
			clear(cell, sim.Time)
			table.insert(events, { Kind = "Escape", Cell = index, What = what, Id = id })
		end
	end

	if sim.Time >= sim.Params.Duration then
		sim.Done = true
		sim.Success = false
		table.insert(events, { Kind = "Timeout", Cell = 0 })
		return events
	end

	-- Apparitions (léger aléa sur le rythme pour ne pas être mécanique).
	if sim.Time >= sim.NextSpawn then
		local event = spawn(sim)
		if event then
			table.insert(events, event)
			sim.NextSpawn = sim.Time + sim.Params.SpawnEvery * sim.Rng:Range(0.8, 1.2)
		else
			sim.NextSpawn = sim.Time + 0.1
		end
	end
	return events
end

-- Toucher une case. Renvoie les événements (Hit / Oops, éventuellement Win).
function ScanLogic.Tap(sim: State, index: number): { Event }
	local events: { Event } = {}
	local cell = sim.Cells[index]
	if sim.Done or not cell or cell.Kind == "Empty" then
		return events
	end
	local id = cell.Id
	if cell.Kind == "Virus" then
		sim.Hits += 1
		sim.Combo += 1
		clear(cell, sim.Time)
		table.insert(events, { Kind = "Hit", Cell = index, What = "Virus", Id = id })
		if sim.Hits >= sim.Params.Target then
			sim.Done = true
			sim.Success = true
			table.insert(events, { Kind = "Win", Cell = 0 })
		end
	else
		sim.Oops += 1
		sim.Combo = 0
		sim.Hits = math.max(0, sim.Hits - 1)
		clear(cell, sim.Time)
		table.insert(events, { Kind = "Oops", Cell = index, What = "File", Id = id })
	end
	return events
end

return table.freeze(ScanLogic)
