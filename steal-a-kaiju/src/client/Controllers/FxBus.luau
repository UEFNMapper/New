--!nonstrict
-- Distribue les événements « Fx » du serveur à tous les abonnés du client.
-- FxBus.On("Hatch", function(args) ... end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local FxBus = {}

local handlers: { [string]: { (any) -> () } } = {}

function FxBus.On(name: string, fn: (any) -> ())
	handlers[name] = handlers[name] or {}
	table.insert(handlers[name], fn)
end

-- Déclenche localement (ex. effets purement client).
function FxBus.Emit(name: string, args: any?)
	local list: { (any) -> () } = handlers[name] or {}
	for _, fn in list do
		task.spawn(fn, args or {})
	end
end

function FxBus.Init()
	Net.Event("Fx").OnClientEvent:Connect(function(name, args)
		FxBus.Emit(name, args)
	end)
end

return FxBus
