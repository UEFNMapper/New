--!nonstrict
-- Appels au serveur. Remote.Call affiche l'erreur en toast (sauf silent).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Remote = {}

local action = Net.Function("Action")
local input = Net.Event("Input")

Remote.OnError = nil :: ((msg: string) -> ())?

function Remote.Call(name: string, payload: { [string]: any }?, silent: boolean?): { ok: boolean, msg: string?, [string]: any }
	local ok, result = pcall(action.InvokeServer, action, name, payload or {})
	if not ok or type(result) ~= "table" then
		result = { ok = false, msg = "Connection problem" }
	end
	if not result.ok and result.msg and not silent and Remote.OnError then
		Remote.OnError(result.msg)
	end
	return result
end

function Remote.Input(kind: string, payload: any?)
	input:FireServer(kind, payload)
end

return Remote
