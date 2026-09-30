--!strict
--[[
	IncidentService : les « attaques » de LAGZ (docs/SCENARIO.md §4), autorité serveur.
	- Programme les incidents MONDE PAR MONDE, seulement là où au moins un joueur court
	  (monde de son étape, hors lobby, hors mini-jeu) ; logique pure dans Util/IncidentSchedule
	- Publie l'état dans ReplicatedStorage.IncidentState (contrat docs/ROADMAP.md) :
	  Kind{w}, Warn{w}, Start{w} = Warn + WarningSeconds, End{w}, Offset{w} (heures serveur).
	  Fin d'un FREEZE : Offset{w} += durée et Kind{w} = "" dans la même étape.
	- Prévient les joueurs du monde (Fx "Incident" : { World, Kind, Phase = "Warn" | "End" })
	  pour les sons et les répliques de LAGZ.

	Studio (barre de commande, côté serveur) :
		require(game.ServerScriptService.Server.Services.IncidentService).Trigger(1, "Blackout")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Incidents = require(Shared.Config.Incidents)
local IncidentSchedule = require(Shared.Util.IncidentSchedule)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local ProgressService = require(script.Parent.ProgressService)

local IncidentService = {}

local TICK = 0.2

local folder: Folder? = nil
local states: { [number]: IncidentSchedule.State } = {}
local random = Random.new()

local function roll(): number
	return random:NextNumber()
end

-- Monde où le joueur court (0 = lobby, départ, mini-jeu, pas encore chargé).
function IncidentService.RunningWorld(session: Session.Session): number
	local data = session.Data
	if not data.RunStarted or data.Stage <= 0 or session.Minigame ~= nil then
		return 0
	end
	if ProgressService.IsAtLobby(session) then
		return 0
	end
	return Tower.WorldOf(data.Stage)
end

local function publish(world: number, state: IncidentSchedule.State)
	local target = folder
	if not target then
		return
	end
	-- Offset et heures d'abord, Kind en dernier : un client qui réagit au changement de Kind
	-- lit toujours un état complet.
	target:SetAttribute(`Offset{world}`, state.Offset)
	target:SetAttribute(`Warn{world}`, state.Warn)
	target:SetAttribute(`Start{world}`, state.Start)
	target:SetAttribute(`End{world}`, state.End)
	target:SetAttribute(`Kind{world}`, state.Kind)
end

local function notify(world: number, kind: string, phase: string)
	for _, session in Session.All() do
		if session.Ready and IncidentService.RunningWorld(session) == world then
			Wallet.Fx(session, "Incident", { World = world, Kind = kind, Phase = phase })
		end
	end
end

-- Incident en cours (ou annoncé) dans un monde : "" si aucun.
function IncidentService.Current(world: number): string
	local state = states[world]
	return if state then state.Kind else ""
end

-- Déclenche tout de suite un incident (boss, tests en Studio). Refusé si un incident est
-- déjà annoncé ou en cours dans ce monde.
function IncidentService.Trigger(world: number, kind: string): boolean
	local state = states[world]
	if not state or state.Kind ~= "" or not Incidents.ByKind[kind] then
		return false
	end
	IncidentSchedule.Announce(state, Workspace:GetServerTimeNow(), kind)
	publish(world, state)
	notify(world, kind, "Warn")
	return true
end

local function step()
	local occupied: { [number]: boolean } = {}
	for _, session in Session.All() do
		local world = IncidentService.RunningWorld(session)
		if world > 0 then
			occupied[world] = true
		end
	end
	local now = Workspace:GetServerTimeNow()
	for world, state in states do
		local finished = state.Kind
		local event = IncidentSchedule.Step(state, world, now, occupied[world] == true, roll)
		if event == "Warn" then
			publish(world, state)
			notify(world, state.Kind, "Warn")
		elseif event == "End" then
			publish(world, state)
			notify(world, finished, "End")
		end
	end
end

function IncidentService.Start()
	local created = Instance.new("Folder")
	created.Name = Incidents.StateFolder
	for world = 1, Tower.WORLD_COUNT do
		local state = IncidentSchedule.NewState()
		states[world] = state
		created:SetAttribute(`Kind{world}`, "")
		created:SetAttribute(`Warn{world}`, 0)
		created:SetAttribute(`Start{world}`, 0)
		created:SetAttribute(`End{world}`, 0)
		created:SetAttribute(`Offset{world}`, 0)
	end
	created.Parent = ReplicatedStorage
	folder = created

	task.spawn(function()
		while true do
			task.wait(TICK)
			xpcall(step, function(err: any)
				warn("[IncidentService]", err)
			end)
		end
	end)
end

return IncidentService
