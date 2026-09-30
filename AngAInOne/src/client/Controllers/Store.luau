--!strict
--[[
	Store : miroir en lecture seule de l'état du joueur envoyé par le serveur.
	- Changed : nouvel état complet
	- Ticked  : mise à jour légère (Bits, collecteur, production) chaque seconde
	- Bits()/Pending() : valeurs prédites entre deux ticks pour des compteurs fluides
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Packages.Signal)
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(script.Parent.Net)

local Store = {}

Store.State = nil :: any
Store.Changed = Signal.new() :: Signal.Signal<any>
Store.Ticked = Signal.new() :: Signal.Signal<>
Store.Ready = false
Store.Boards = nil :: any -- classements { Legends, Weekly, WeekIndex }
Store.BoardsChanged = Signal.new() :: Signal.Signal<any>

local tickBits, tickPending, tickRate, tickTime = 0, 0, 0, 0
local unixOffset = 0 -- os.time() serveur - horloge synchronisée

function Store.Data(): any
	return if Store.State then Store.State.Data else nil
end

-- Heure "unix" côté serveur (pour les compteurs : téléchargements, boosts, overclock).
function Store.UnixNow(): number
	return Workspace:GetServerTimeNow() + unixOffset
end

function Store.Rate(): number
	return tickRate
end

function Store.Bits(): number
	local state = Store.State
	if not state then
		return 0
	end
	if state.Passes.AutoCollect and state.Data.PoweredOn then
		return tickBits + tickRate * math.max(0, Workspace:GetServerTimeNow() - tickTime)
	end
	return tickBits
end

function Store.Pending(): number
	local state = Store.State
	if not state or state.Passes.AutoCollect or not state.Data.PoweredOn then
		return 0
	end
	local cap = tickRate * GameConfig.CollectorCapSeconds
	return math.min(tickPending + tickRate * math.max(0, Workspace:GetServerTimeNow() - tickTime), cap)
end

function Store.Start()
	Net.On("State", function(snapshot: any)
		Store.State = snapshot
		unixOffset = snapshot.UnixTime - snapshot.ServerTime
		tickBits = snapshot.Data.Bits
		tickPending = snapshot.Data.Pending
		tickRate = snapshot.Production.Rate
		tickTime = snapshot.ServerTime
		Store.Ready = true
		Store.Changed:Fire(snapshot)
	end)
	Net.On("Leaderboard", function(boards: any)
		Store.Boards = boards
		Store.BoardsChanged:Fire(boards)
	end)
	Net.On("ServerInfo", function(info: any)
		if Store.State and type(info) == "table" and type(info.ServerBoostUntil) == "number" then
			Store.State.ServerBoostUntil = info.ServerBoostUntil
		end
	end)
	Net.OnUnreliable("Tick", function(bits: number, pending: number, rate: number, serverTime: number)
		if serverTime < tickTime then
			return -- paquet en retard
		end
		tickBits, tickPending, tickRate, tickTime = bits, pending, rate, serverTime
		if Store.State then
			Store.State.Data.Bits = bits
			Store.State.Data.Pending = pending
		end
		Store.Ticked:Fire()
	end)
end

return Store
