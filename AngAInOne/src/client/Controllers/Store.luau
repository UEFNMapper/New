--!strict
--[[
	Store : miroir en lecture seule de l'état du joueur envoyé par le serveur.
	- Changed : nouvel état complet
	- RunTime() : chrono de l'ascension, prédit localement entre deux états (affichage fluide)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Packages.Signal)
local Net = require(script.Parent.Net)

local Store = {}

Store.State = nil :: any
Store.Changed = Signal.new() :: Signal.Signal<any>
Store.Ready = false
Store.Boards = nil :: any -- classements { Wins, BestTime, Stage }
Store.BoardsChanged = Signal.new() :: Signal.Signal<any>

local unixOffset = 0 -- os.time() serveur - horloge synchronisée
local runTimeBase = 0
local runTimeAt = 0 -- os.clock() local à la réception

function Store.Data(): any
	return if Store.State then Store.State.Data else nil
end

-- Heure "unix" côté serveur (compteurs : bouclier, calendrier).
function Store.UnixNow(): number
	return Workspace:GetServerTimeNow() + unixOffset
end

function Store.Bits(): number
	local data = Store.Data()
	return if data then data.Bits else 0
end

-- Chrono de l'ascension (secondes), qui avance tout seul quand il tourne.
function Store.RunTime(): number
	local state = Store.State
	if not state then
		return 0
	end
	if state.ClockRunning then
		return runTimeBase + (os.clock() - runTimeAt)
	end
	return runTimeBase
end

function Store.Start()
	Net.On("State", function(snapshot: any)
		Store.State = snapshot
		unixOffset = snapshot.UnixTime - snapshot.ServerTime
		runTimeBase = snapshot.RunTime
		runTimeAt = os.clock()
		Store.Ready = true
		Store.Changed:Fire(snapshot)
	end)
	Net.On("Leaderboard", function(boards: any)
		Store.Boards = boards
		Store.BoardsChanged:Fire(boards)
	end)
end

return Store
