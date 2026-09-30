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
local Production = require(Shared.Economy.Production)
local Bonuses = require(Shared.Economy.Bonuses)

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
	PaidRandomAllowed: boolean,
	Snapshot: Production.Snapshot,
	Bonus: Bonuses.Breakdown,
	OverclockUntil: number,
	OverclockMult: number,
	OverclockCooldownUntil: number,
	OverclockAttemptStart: number, -- 0 = pas de tentative en cours
	JoinedAt: number,
	PlaytimeCarry: number,
	FunnelDone: { [number]: boolean },
	Trove: Cleaner,
	Ready: boolean, -- le client a signalé qu'il est prêt à recevoir l'état
	EffectsKey: string, -- effets temporaires actifs au dernier calcul (détecte les expirations)
	PassesLoaded: boolean, -- les Game Passes ont été vérifiés (MonetizationService)
	OfflineHandled: boolean, -- les gains hors ligne de cette connexion ont été versés
	LastTick: number, -- heure serveur (synchronisée) du dernier ajout de production
}

local Session = {}

local sessions: { [Player]: Session } = {}

Session.Added = Signal.new() :: Signal.Signal<Session>
Session.Removing = Signal.new() :: Signal.Signal<Session>

local EMPTY_SNAPSHOT: Production.Snapshot = {
	RawRate = 0,
	Rate = 0,
	PowerDemand = 0,
	PowerCapacity = 1,
	PowerEfficiency = 1,
	HeatDemand = 0,
	HeatCapacity = 1,
	ThermalEfficiency = 1,
	Multiplier = 1,
}

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
		PaidRandomAllowed = false,
		Snapshot = EMPTY_SNAPSHOT,
		Bonus = { Total = 1, WattsReduction = 0, HeatReduction = 0, SpeedBonus = 0, Lines = {} },
		OverclockUntil = 0,
		OverclockMult = 1,
		OverclockCooldownUntil = 0,
		OverclockAttemptStart = 0,
		JoinedAt = os.time(),
		PlaytimeCarry = 0,
		FunnelDone = {},
		Trove = Trove.new() :: any,
		Ready = false,
		EffectsKey = "",
		PassesLoaded = false,
		OfflineHandled = false,
		LastTick = 0,
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
