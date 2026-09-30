--!strict
--[[
	Point d'entrée serveur d'AngAInOne.
	Ordre : remotes -> services (qui s'abonnent aux événements) -> chargement des joueurs.
	DataService démarre EN DERNIER pour que tous les services reçoivent Session.Added.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

Remotes.Setup()

local Services = script.Parent.Services
local ORDER = {
	"StateService",
	"ProgressService",
	"IncidentService",
	"ShopService",
	"MonetizationService",
	"MinigameService",
	"MissionService",
	"LeaderboardService",
	"SocialService",
	"DevService",
	"DataService",
}

for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `Service introuvable : {name}`)
	local service = (require :: any)(module)
	local ok, err = pcall(service.Start)
	if not ok then
		warn(`[AngAInOne] Échec du démarrage de {name} :`, err)
	end
end

print("[AngAInOne] Serveur prêt.")
