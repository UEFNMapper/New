--!strict
-- Canaux réseau. Le serveur les crée, le client les attend.
--
--   Action (RemoteFunction, client -> serveur) : toutes les requêtes du joueur,
--          sous la forme Action:InvokeServer(nom, données) -> { ok, msg?, ... }
--   Data   (RemoteEvent, serveur -> client)   : champs de données modifiés
--   Fx     (RemoteEvent, serveur -> client)   : effets à jouer (nom, args)
--   Notify (RemoteEvent, serveur -> client)   : toast (texte, type)
--   Feed   (RemoteEvent, serveur -> tous)     : annonces serveur (vols, raretés…)
--   Input  (RemoteEvent, client -> serveur)   : actions fréquentes sans réponse (bonk, orbes)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local EVENTS = { "Data", "Fx", "Notify", "Feed", "Input" }
local FUNCTIONS = { "Action" }

local folder: Folder

if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in EVENTS do
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
		for _, name in FUNCTIONS do
			local f = Instance.new("RemoteFunction")
			f.Name = name
			f.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
