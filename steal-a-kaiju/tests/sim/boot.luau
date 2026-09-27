--!nocheck
-- Démarrage minimal du serveur simulé (sert de base aux scénarios).
local Harness = require("../Harness")
local Runtime = require("./Runtime")
local FakeProfileStore = require("./FakeProfileStore")

local Boot = {}

function Boot.Start()
	FakeProfileStore.Signal = Runtime.Signal
	Runtime.Globals.Random = Harness.Random
	local S = Runtime.Services
	Runtime.Mount("src/shared", S.ReplicatedStorage, "Shared")
	local server = Runtime.Mount("src/server", S.ServerScriptService, "Server")
	Runtime.Overrides["game.ServerScriptService.Server.Vendor.ProfileStore"] = FakeProfileStore
	Runtime.RunScript(server:FindFirstChild("Main"))
	Runtime.Advance(1)
	return Runtime
end

-- Appelle une action comme le ferait le client.
function Boot.Call(player, action, payload)
	local remotes = Runtime.Services.ReplicatedStorage:FindFirstChild("Remotes")
	local fn = remotes:FindFirstChild("Action").OnServerInvoke
	local result
	Runtime.task.spawn(function()
		result = fn(player, action, payload or {})
	end)
	return result
end

function Boot.Input(player, kind, payload)
	local remotes = Runtime.Services.ReplicatedStorage:FindFirstChild("Remotes")
	remotes:FindFirstChild("Input").OnServerEvent:Fire(player, kind, payload)
end

-- Effets (Fx) reçus par un joueur depuis l'index `from` du journal.
function Boot.FxFor(player, name, from)
	local out = {}
	for i = from or 1, #Runtime.ClientLog do
		local e = Runtime.ClientLog[i]
		if e.remote == "Fx" and (e.player == player or e.player == "all") and e.args[1] == name then
			table.insert(out, e.args[2])
		end
	end
	return out
end

return Boot
