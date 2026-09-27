--!nonstrict
-- Point d'entrée serveur : construit la carte puis démarre les services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Crée les RemoteEvents avant tout (le client les attend)
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Services = script.Parent:WaitForChild("Services")
local Registry = require(Services.Registry)
local MapBuilder = require(script.Parent.World.MapBuilder)

local map = MapBuilder.Build()

local order = {
	"DataService",
	"Router",
	"Notify",
	"ShopService",
	"PlotService",
	"KaijuService",
	"MeteorService",
	"StealService",
	"EventService",
	"RewardService",
	"ProgressionService",
	"LeaderboardService",
	"LevelService",
	"WorldService",
	"SiegeService",
	"RampageService",
	"BuddyService",
	"TutorialService",
}

for _, name in order do
	Registry[name] = require(Services:WaitForChild(name)) :: any
end

Registry.PlotService.SetMap(map)
Registry.MeteorService.SetWorlds(map.Worlds)
Registry.WorldService.SetWorlds(map.Worlds)

-- Init dans l'ordre inverse des dépendances de données : DataService en
-- dernier pour que tous les services soient abonnés à Loaded avant le 1er joueur.
for _, name in order do
	local service = Registry[name]
	if name ~= "DataService" and service.Init then
		service.Init()
	end
end
Registry.DataService.Init()

Registry.MeteorService.Start()
Registry.EventService.Start()
Registry.LeaderboardService.Start(map.Boards)

Players.CharacterAutoLoads = true
print(("[Steal a Kaiju] serveur prêt — %d services"):format(#order))
