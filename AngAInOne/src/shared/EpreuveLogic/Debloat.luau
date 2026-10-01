--!strict
--[[
	Debloat : règles de l'épreuve du monde 3, « L'invasion du Bloatware » (étape 2 du guide).
	Des bloatware, gros et lents, se promènent dans la salle. Maintenir « Debloat » à côté d'un
	bloatware l'aspire dans la Corbeille. Un bloatware laissé tranquille trop longtemps s'installe
	encore : il crée une copie (au plus MAX_COPIES en tout). Le preset « Performance » (pad au sol,
	une fois) aspire tous ceux qui sont à portée. Quand il n'en reste plus : vider la Corbeille.
]]

local Debloat = {}

Debloat.NAMES = table.freeze({
	"Barre d'outils Super-Recherche",
	"Assistant Météo Plus",
	"Coupons Express",
	"Optimiseur 3000 GRATUIT",
	"Nettoyeur Miracle",
})
Debloat.COPY_AFTER = 14 -- s sans être aspiré avant de se copier
Debloat.MAX_COPIES = 3
Debloat.PRESET_RADIUS = 18

export type Monster = { Id: number, Name: string, Age: number, Copy: boolean }

export type Event = { Kind: "Copy" | "Captured" | "AllCaptured" | "Emptied", Monster: Monster? }

export type State = {
	Monsters: { Monster },
	Captured: number,
	Copies: number,
	NextId: number,
	PresetUsed: boolean,
	Emptied: boolean,
}

function Debloat.new(): State
	local state: State = { Monsters = {}, Captured = 0, Copies = 0, NextId = 0, PresetUsed = false, Emptied = false }
	for _, name in Debloat.NAMES do
		state.NextId += 1
		table.insert(state.Monsters, { Id = state.NextId, Name = name, Age = 0, Copy = false })
	end
	return state
end

function Debloat.Find(state: State, id: number): (Monster?, number?)
	for index, monster in state.Monsters do
		if monster.Id == id then
			return monster, index
		end
	end
	return nil, nil
end

function Debloat.Step(state: State, dt: number): { Event }
	local events: { Event } = {}
	for _, monster in table.clone(state.Monsters) do
		monster.Age += math.max(dt, 0)
		if monster.Age >= Debloat.COPY_AFTER and state.Copies < Debloat.MAX_COPIES and not monster.Copy then
			monster.Age = 0
			state.Copies += 1
			state.NextId += 1
			local copy = { Id = state.NextId, Name = `{monster.Name} (2)`, Age = 0, Copy = true }
			table.insert(state.Monsters, copy)
			table.insert(events, { Kind = "Copy", Monster = copy })
		end
	end
	return events
end

function Debloat.Capture(state: State, id: number): { Event }
	local events: { Event } = {}
	local monster, index = Debloat.Find(state, id)
	if not monster or not index then
		return events
	end
	table.remove(state.Monsters, index)
	state.Captured += 1
	table.insert(events, { Kind = "Captured", Monster = monster })
	if #state.Monsters == 0 then
		table.insert(events, { Kind = "AllCaptured" })
	end
	return events
end

-- Preset « Performance » : aspire d'un coup les bloatware `ids` (ceux à portée, choisis par le client).
function Debloat.Preset(state: State, ids: { number }): { Event }
	local events: { Event } = {}
	if state.PresetUsed then
		return events
	end
	state.PresetUsed = true
	for _, id in ids do
		for _, event in Debloat.Capture(state, id) do
			table.insert(events, event)
		end
	end
	return events
end

function Debloat.CanEmpty(state: State): boolean
	return #state.Monsters == 0 and not state.Emptied
end

function Debloat.Empty(state: State): boolean
	if not Debloat.CanEmpty(state) then
		return false
	end
	state.Emptied = true
	return true
end

-- Score : 100, −10 par copie qu'on a laissé s'installer (au moins 60).
function Debloat.Score(state: State): number
	return math.max(60, 100 - 10 * state.Copies)
end

return table.freeze(Debloat)
