--!strict
--[[
	StateService : réplique l'état d'un joueur vers SON client uniquement.
	- État complet ("State") quand quelque chose de structurel change (au plus 4 fois/s)
	- Petit "Tick" non fiable chaque seconde (Bits, collecteur, production)
	Le client ne fait que lire : toute modification passe par des remotes validées.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Nanobots = require(Shared.Config.Nanobots)
local Modules = require(Shared.Config.Modules)
local Formulas = require(Shared.Economy.Formulas)
local Remotes = require(Shared.Net.Remotes)
local Session = require(script.Parent.Parent.Core.Session)
local ServerState = require(script.Parent.Parent.Core.ServerState)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)

local StateService = {}

local FLUSH_INTERVAL = 0.25
local dirty: { [Session.Session]: boolean } = {}
local stateRemote: RemoteEvent
local tickRemote: UnreliableRemoteEvent

local zoneOf: { [string]: number } = {}
for _, def in Modules.List do
	zoneOf[def.Id] = def.Zone
end

function StateService.Benchmark(session: Session.Session): number
	return Formulas.Benchmark(session.Data.Levels, zoneOf)
end

function StateService.CapsuleCost(session: Session.Session, capsuleId: string): number
	local capsule = Nanobots.CapsuleById[capsuleId]
	if not capsule then
		return math.huge
	end
	if capsule.Currency == "Chips" then
		return capsule.ChipsCost
	end
	return math.max(
		capsule.MinBits,
		math.floor(session.Snapshot.RawRate * session.Snapshot.PowerEfficiency * capsule.ProductionSeconds)
	)
end

function StateService.NanobotSlots(session: Session.Session): number
	return GameConfig.Nanobots.BaseSlots
		+ (if session.Passes.ExtraNanobots then GameConfig.Nanobots.PassExtraSlots else 0)
end

local function buildSnapshot(session: Session.Session): { [string]: any }
	local data = session.Data
	local copy: { [string]: any } = {}
	for key, value in data :: any do
		if key ~= "Receipts" then
			copy[key] = value
		end
	end
	local capsuleCosts = {}
	for _, capsule in Nanobots.Capsules do
		capsuleCosts[capsule.Id] = StateService.CapsuleCost(session, capsule.Id)
	end
	local firmwareGain = Formulas.FirmwareGain(data.RunBitsEarned, GameConfig.Reboot.FirmwareDivisor)
	if data.RebootBoostPending then
		firmwareGain = math.floor(firmwareGain * 1.5)
	end
	return {
		Data = copy,
		ServerTime = Workspace:GetServerTimeNow(),
		-- Bits et collecteur incluent la production jusqu'au dernier tick : sert de base à la prédiction.
		TickTime = if session.LastTick > 0 then session.LastTick else Workspace:GetServerTimeNow(),
		UnixTime = os.time(),
		Production = session.Snapshot,
		Bonus = session.Bonus,
		Passes = session.Passes,
		PaidRandomAllowed = session.PaidRandomAllowed,
		Overclock = {
			Until = session.OverclockUntil,
			Mult = session.OverclockMult,
			CooldownUntil = session.OverclockCooldownUntil,
		},
		ServerBoostUntil = ServerState.ServerBoostUntil,
		CapsuleCosts = capsuleCosts,
		FirmwarePreview = firmwareGain,
		Benchmark = StateService.Benchmark(session),
		NanobotSlots = StateService.NanobotSlots(session),
		IsPremium = session.IsPremium,
		FriendsInServer = session.FriendsInServer,
	}
end

-- Demande l'envoi de l'état complet (regroupé au prochain flush).
function StateService.Push(session: Session.Session)
	dirty[session] = true
end

function StateService.PushNow(session: Session.Session)
	dirty[session] = nil
	if session.Ready and session.Player.Parent then
		stateRemote:FireClient(session.Player, buildSnapshot(session))
	end
end

function StateService.SendTick(session: Session.Session)
	if session.Ready then
		tickRemote:FireClient(
			session.Player,
			session.Data.Bits,
			session.Data.Pending,
			session.Snapshot.Rate,
			if session.LastTick > 0 then session.LastTick else Workspace:GetServerTimeNow()
		)
	end
end

function StateService.Start()
	stateRemote = Remotes.Get("State")
	tickRemote = Remotes.GetUnreliable("Tick")

	Session.Removing:Connect(function(session: Session.Session)
		dirty[session] = nil
	end)

	-- Le client signale qu'il a construit son UI : on lui envoie tout de suite son état.
	RemoteGuard.On("ClientReady", { Args = {} }, function(session: Session.Session)
		session.Ready = true
		StateService.PushNow(session)
		GameEvents.ClientReady:Fire(session.Player)
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			for session in dirty do
				StateService.PushNow(session)
			end
		end
	end)
end

return StateService
