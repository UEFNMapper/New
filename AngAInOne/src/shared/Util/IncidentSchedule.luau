--!strict
--[[
	IncidentSchedule : la programmation des incidents de LAGZ, monde par monde (logique PURE,
	testée dans Lune ; IncidentService s'occupe de l'horloge et de la publication).

	Cycle d'un monde :
	- personne dans le monde : rien ne se passe (le prochain incident est repoussé d'une petite
	  marge, pour ne jamais tomber pile à l'arrivée d'un joueur) ;
	- quelqu'un y court : un incident est annoncé toutes les IntervalMin..IntervalMax secondes
	  (monde 7 : BossIntervalMin..Max). Annonce -> Start = Warn + WarningSeconds -> End ;
	- un incident annoncé va toujours jusqu'au bout (l'horloge des pièges reste continue) ;
	- fin d'un FREEZE : Offset += End - Start et Kind = "" dans la même étape.
]]

local Incidents = require(script.Parent.Parent.Config.Incidents)
local Tower = require(script.Parent.Parent.Config.Tower)

local IncidentSchedule = {}

-- Marge minimale (s) entre l'arrivée d'un joueur dans un monde vide et le prochain incident.
IncidentSchedule.ENTRY_GRACE = 20

export type State = {
	Kind: string, -- "" = aucun incident annoncé ni en cours
	Warn: number,
	Start: number,
	End: number,
	Offset: number, -- secondes de FREEZE déjà écoulées (TrapClock)
	NextAt: number, -- heure de la prochaine annonce (0 = pas encore programmée)
	Last: string, -- dernier type joué (évite deux fois le même au monde 7)
}

export type Event = "Warn" | "End"

-- Tirage aléatoire dans [0, 1[ (Random:NextNumber côté serveur, suite fixe dans les tests).
export type Roll = () -> number

function IncidentSchedule.NewState(): State
	return { Kind = "", Warn = 0, Start = 0, End = 0, Offset = 0, NextAt = 0, Last = "" }
end

-- Délai avant la prochaine annonce dans ce monde.
function IncidentSchedule.Interval(world: number, roll: Roll): number
	local boss = world >= Tower.WORLD_COUNT
	local low = if boss then Incidents.BossIntervalMin else Incidents.IntervalMin
	local high = if boss then Incidents.BossIntervalMax else Incidents.IntervalMax
	return low + (high - low) * roll()
end

-- Type d'incident du monde : son incident vedette, ou n'importe lequel ("Any", monde 7)
-- sans jamais répéter le précédent.
function IncidentSchedule.PickKind(world: number, roll: Roll, last: string): string
	local def = Tower.Worlds[world]
	local featured = if def then def.Incident else "Any"
	if featured ~= "Any" and Incidents.ByKind[featured] then
		return featured
	end
	local pool: { string } = {}
	for _, incident in Incidents.List do
		if incident.Kind ~= last then
			table.insert(pool, incident.Kind)
		end
	end
	local index = math.clamp(math.floor(roll() * #pool) + 1, 1, #pool)
	return pool[index]
end

-- Annonce un incident maintenant (utilisé aussi pour un déclenchement forcé : boss, Studio).
function IncidentSchedule.Announce(state: State, now: number, kind: string)
	local def = Incidents.ByKind[kind]
	assert(def, `Incident inconnu : {kind}`)
	state.Kind = kind
	state.Warn = now
	state.Start = now + Incidents.WarningSeconds
	state.End = state.Start + def.Duration
	state.Last = kind
	state.NextAt = 0
end

-- Fait avancer le monde à l'heure `now`. `occupied` : au moins un joueur y court (hors lobby
-- et hors mini-jeu). Renvoie l'événement à publier, s'il y en a un.
function IncidentSchedule.Step(state: State, world: number, now: number, occupied: boolean, roll: Roll): Event?
	if state.Kind ~= "" then
		if now < state.End then
			return nil
		end
		if state.Kind == "Freeze" then
			state.Offset += state.End - state.Start
		end
		state.Kind = ""
		state.NextAt = if occupied then now + IncidentSchedule.Interval(world, roll) else 0
		return "End"
	end
	if not occupied then
		if state.NextAt > 0 then
			state.NextAt = math.max(state.NextAt, now + IncidentSchedule.ENTRY_GRACE)
		end
		return nil
	end
	if state.NextAt <= 0 then
		state.NextAt = now + IncidentSchedule.Interval(world, roll)
		return nil
	end
	if now < state.NextAt then
		return nil
	end
	IncidentSchedule.Announce(state, now, IncidentSchedule.PickKind(world, roll, state.Last))
	return "Warn"
end

-- Phase d'un incident vue à l'heure `now` : "Warn" (annonce), "Active" ou "" (rien).
function IncidentSchedule.Phase(kind: string, warn: number, start: number, finish: number, now: number): string
	if kind == "" or now < warn or now >= finish then
		return ""
	end
	return if now < start then "Warn" else "Active"
end

return table.freeze(IncidentSchedule)
