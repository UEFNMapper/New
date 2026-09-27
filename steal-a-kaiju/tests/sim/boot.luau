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

-- Fait marcher un ou plusieurs joueurs vers une cible à leur vitesse réelle.
-- `group` : liste de { player, offset } qui se déplacent ensemble.
function Boot.WalkTo(group, target)
	local roblox = require("@lune/roblox")
	for _ = 1, 4000 do
		local lead = group[1][1]
		local root = lead.Character.HumanoidRootPart
		local pos = root.Position
		local delta = roblox.Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
		if delta.Magnitude < 1 then
			return true
		end
		local speed = math.max(lead.Character.Humanoid.WalkSpeed, 1)
		local step = math.min(delta.Magnitude, speed * 0.1)
		local newPos = pos + delta.Unit * step
		for _, member in group do
			local offset = member[2] or roblox.Vector3.new()
			member[1].Character.HumanoidRootPart.CFrame = roblox.CFrame.new(newPos + offset)
		end
		Runtime.Advance(0.1)
		if (lead:GetAttribute("Carrying") or "") == "" then
			return false -- plus rien à porter (livré ou lâché)
		end
	end
	return false
end

return Boot
