--!strict
--[[
	StateService : réplique l'état d'un joueur vers SON client uniquement (au plus 4 fois/s).
	Le client ne fait que lire : toute modification passe par des remotes validées.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)

local StateService = {}

local FLUSH_INTERVAL = 0.25
local dirty: { [Session.Session]: boolean } = {}

-- Branché par ProgressService (évite un require circulaire) : le joueur est-il au lobby ?
StateService.AtLobby = nil :: ((session: Session.Session) -> boolean)?
local stateRemote: RemoteEvent

-- Chrono de l'ascension en cours (secondes), segment actif compris.
function StateService.RunTime(session: Session.Session): number
	local running = if session.ClockSince > 0 then os.clock() - session.ClockSince else 0
	return session.Data.RunElapsed + running
end

local function buildSnapshot(session: Session.Session): { [string]: any }
	local copy: { [string]: any } = {}
	for key, value in session.Data :: any do
		if key ~= "Receipts" then
			copy[key] = value
		end
	end
	return {
		Data = copy,
		ServerTime = Workspace:GetServerTimeNow(),
		UnixTime = os.time(),
		RunTime = StateService.RunTime(session),
		ClockRunning = session.ClockSince > 0,
		AtLobby = if StateService.AtLobby then StateService.AtLobby(session) else true,
		Passes = session.Passes,
		ShieldUntil = session.ShieldUntil,
		Multiplier = Wallet.Multiplier(session),
		FriendsInServer = session.FriendsInServer,
		IsPremium = session.IsPremium,
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

function StateService.Start()
	stateRemote = Remotes.Get("State")

	Session.Removing:Connect(function(session: Session.Session)
		dirty[session] = nil
	end)
	GameEvents.StateChanged:Connect(function(player: Player)
		local session = Session.Get(player)
		if session then
			StateService.Push(session)
		end
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
