--!nonstrict
-- État local : copie des données du joueur reçues du serveur + valeurs dérivées.
-- State.Observe(clé, fn) appelle fn tout de suite puis à chaque changement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local State = {}

local values: { [string]: any } = {}
local signals: { [string]: any } = {}
State.Loaded = false
State.LoadedSignal = Signal.new()
State.AnyChanged = Signal.new()

local function signalFor(key: string)
	local s = signals[key]
	if not s then
		s = Signal.new()
		signals[key] = s
	end
	return s
end

function State.Get(key: string): any
	return values[key]
end

function State.Set(key: string, value: any)
	values[key] = value
	signalFor(key):Fire(value)
	State.AnyChanged:Fire(key, value)
end

function State.Changed(key: string)
	return signalFor(key)
end

function State.Observe(key: string, fn: (any) -> ())
	if values[key] ~= nil then
		task.spawn(fn, values[key])
	end
	return signalFor(key):Connect(fn)
end

function State.WaitLoaded()
	if not State.Loaded then
		State.LoadedSignal:Wait()
	end
end

function State.Init()
	Net.Event("Data").OnClientEvent:Connect(function(patch, full)
		for key, value in patch do
			State.Set(key, value)
		end
		if full and not State.Loaded then
			State.Loaded = true
			State.LoadedSignal:Fire()
		end
	end)
end

return State
