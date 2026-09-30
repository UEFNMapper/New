--!strict
--[[
	Net : envoi des requêtes au serveur. Le client ne décide de rien :
	il demande, le serveur valide et renvoie l'état.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Net.Remotes)

local Net = {}

local cache: { [string]: RemoteEvent } = {}

local function remote(name: string): RemoteEvent
	local existing = cache[name]
	if existing then
		return existing
	end
	local found = Remotes.Get(name)
	cache[name] = found
	return found
end

function Net.Fire(name: string, ...: any)
	remote(name):FireServer(...)
end

function Net.On(name: string, handler: (...any) -> ()): RBXScriptConnection
	return remote(name).OnClientEvent:Connect(handler)
end

function Net.OnUnreliable(name: string, handler: (...any) -> ()): RBXScriptConnection
	return Remotes.GetUnreliable(name).OnClientEvent:Connect(handler)
end

return Net
