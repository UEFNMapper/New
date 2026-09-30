--!strict
--[[
	Session : état d'exécution d'un joueur connecté (non sauvegardé), plus un accès
	à ses données sauvegardées (session.Data = profile.Data).
	Aucune dépendance vers les services : tout le monde peut le lire sans cycle de require.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Packages.Signal)
local Trove = require(Shared.Packages.Trove)
local DataSchema = require(Shared.Data.DataSchema)

-- Sous-ensemble de Trove utilisé par les services (le type complet de Trove est trop
-- générique pour l'analyseur et casse la comparaison de types entre modules).
export type Cleaner = {
	Connect: (self: Cleaner, signal: any, fn: (...any) -> ()) -> any,
	Add: (self: Cleaner, object: any, cleanupMethod: string?) -> any,
	Destroy: (self: Cleaner) -> (),
}

export type Session = {
	Player: Player,
	UserId: number,
	Profile: any, -- ProfileStore Profile
	Data: DataSchema.PlayerData,
	Passes: { [string]: boolean },
	IsPremium: boolean,
	InGroup: boolean,
	FriendsInServer: number,
	JoinedAt: number,
	PlaytimeCarry: number,
	Trove: Cleaner,
	Ready: boolean, -- le client a signalé qu'il est prêt à recevoir l'état
	PassesLoaded: boolean, -- les Game Passes ont été vérifiés (MonetizationService)
	-- Ascension (non sauvegardé)
	ClockSince: number, -- os.clock() du début du segment de chrono en cours (0 = arrêté)
	LastCheckpointAt: number, -- os.clock() du dernier checkpoint validé (anti-triche)
	LastTeleportAt: number,
	ShieldUntil: number, -- os.time() de fin du bouclier
	Minigame: { World: number, Kind: string, StartedAt: number }?, -- partie en cours (0 = arcade)
	Alive: boolean,
}

local Session = {}

local sessions: { [Player]: Session } = {}

Session.Added = Signal.new() :: Signal.Signal<Session>
Session.Removing = Signal.new() :: Signal.Signal<Session>

function Session.Create(player: Player, profile: any): Session
	local session: Session = {
		Player = player,
		UserId = player.UserId,
		Profile = profile,
		Data = profile.Data,
		Passes = {},
		IsPremium = player.MembershipType == Enum.MembershipType.Premium,
		InGroup = false,
		FriendsInServer = 0,
		JoinedAt = os.time(),
		PlaytimeCarry = 0,
		Trove = Trove.new() :: any,
		Ready = false,
		PassesLoaded = false,
		ClockSince = 0,
		LastCheckpointAt = 0,
		LastTeleportAt = 0,
		ShieldUntil = 0,
		Minigame = nil,
		Alive = false,
	}
	sessions[player] = session
	Session.Added:Fire(session)
	return session
end

function Session.Remove(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	Session.Removing:Fire(session)
	sessions[player] = nil
	session.Trove:Destroy()
end

function Session.Get(player: Player): Session?
	return sessions[player]
end

function Session.All(): { Session }
	local list = {}
	for _, session in sessions do
		table.insert(list, session)
	end
	return list
end

function Session.ByUserId(userId: number): Session?
	for _, session in sessions do
		if session.UserId == userId then
			return session
		end
	end
	return nil
end

return Session
