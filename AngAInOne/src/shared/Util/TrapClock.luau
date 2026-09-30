--!strict
--[[
	TrapClock : l'heure des pièges d'un monde, partagée par tous les clients.
	= Workspace:GetServerTimeNow() moins le temps passé figé (FREEZE), et par à-coups pendant
	un LAG SPIKE. Lit ReplicatedStorage.IncidentState (publié par IncidentService).
	Compute() est pure (testée dans Lune) ; Now() lit l'état répliqué.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Incidents = require(script.Parent.Parent.Config.Incidents)

local TrapClock = {}

-- base : heure serveur ; kind/start/finish : incident en cours du monde ; offset : FREEZE passés.
function TrapClock.Compute(base: number, kind: string, start: number, finish: number, offset: number): number
	if kind == "Freeze" and base >= start then
		-- Le temps est suspendu pendant le freeze ; après la fin (avant que le serveur n'ait
		-- reporté la durée dans offset), on retire déjà la durée : aucune discontinuité.
		return base - offset - math.min(base - start, finish - start)
	end
	local t = base - offset
	if kind == "Lag" and base >= start and base < finish then
		local step = Incidents.LagStep
		return start - offset + math.floor((base - start) / step) * step
	end
	return t
end

local state: Instance? = nil

function TrapClock.Now(world: number): number
	local base = Workspace:GetServerTimeNow()
	if not state then
		state = ReplicatedStorage:FindFirstChild(Incidents.StateFolder)
		if not state then
			return base
		end
	end
	local folder = state :: Instance
	local kind = folder:GetAttribute(`Kind{world}`)
	local start = folder:GetAttribute(`Start{world}`)
	local finish = folder:GetAttribute(`End{world}`)
	local offset = folder:GetAttribute(`Offset{world}`)
	return TrapClock.Compute(
		base,
		if type(kind) == "string" then kind else "",
		if type(start) == "number" then start else 0,
		if type(finish) == "number" then finish else 0,
		if type(offset) == "number" then offset else 0
	)
end

-- Incident actif dans ce monde ("" si aucun), pour les effets (BLACKOUT, CORRUPTION, SURCHAUFFE).
function TrapClock.Incident(world: number): string
	local folder = state or ReplicatedStorage:FindFirstChild(Incidents.StateFolder)
	if not folder then
		return ""
	end
	state = folder
	local kind = folder:GetAttribute(`Kind{world}`)
	local start = folder:GetAttribute(`Start{world}`)
	local finish = folder:GetAttribute(`End{world}`)
	local now = Workspace:GetServerTimeNow()
	if
		type(kind) == "string"
		and type(start) == "number"
		and type(finish) == "number"
		and now >= start
		and now < finish
	then
		return kind
	end
	return ""
end

return TrapClock
