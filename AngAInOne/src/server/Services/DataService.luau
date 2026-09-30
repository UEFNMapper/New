--!strict
--[[
	DataService : charge et sauvegarde les données joueur avec ProfileStore.
	- Verrouillage de session (pas de duplication entre deux serveurs)
	- Sauvegarde auto (ProfileStore, toutes les 5 min) + sauvegarde à l'arrêt (BindToClose géré par ProfileStore)
	- Migration versionnée du schéma (DataSchema.Migrate)
	- En Studio sans accès API, bascule automatiquement sur ProfileStore.Mock
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local DataSchema = require(Shared.Data.DataSchema)
local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)
local Session = require(script.Parent.Parent.Core.Session)

local DataService = {}

local store: any = ProfileStore.New(GameConfig.DataStoreName, DataSchema.Template() :: any)

local function profileStoreFor(): any
	-- En Studio, si "Enable Studio Access to API Services" est désactivé, on utilise un store simulé.
	if RunService:IsStudio() and ProfileStore.DataStoreState ~= "Access" then
		return store.Mock
	end
	return store
end

local function onPlayerAdded(player: Player)
	-- Laisse ProfileStore découvrir l'état du DataStore (rapide).
	local waited = 0
	while ProfileStore.DataStoreState == "NotReady" and waited < 5 do
		waited += task.wait(0.1)
	end

	local profile = profileStoreFor():StartSessionAsync(
		`Player_{player.UserId}`,
		{
			Cancel = function(): boolean
				return player.Parent ~= Players
			end,
		} :: any
	)

	if profile == nil then
		player:Kick("Impossible de charger ta sauvegarde. Réessaie dans un instant.")
		return
	end

	profile:AddUserId(player.UserId)
	if not DataSchema.Migrate(profile.Data) then
		-- Données d'une version plus récente : ce serveur est obsolète, on ne touche à rien.
		profile:EndSession()
		player:Kick("Une mise à jour est disponible, rejoins un nouveau serveur.")
		return
	end

	profile.OnSessionEnd:Connect(function()
		local session = Session.Get(player)
		if session and session.OfflineHandled then
			session.Data.Stats.LastOnline = os.time()
		end
		Session.Remove(player)
		-- Seulement si la session a été reprise par un autre serveur (pas à l'arrêt du serveur).
		if not ProfileStore.IsClosing and player.Parent == Players then
			player:Kick("Ta session a été ouverte ailleurs. Reconnecte-toi.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local data = profile.Data :: DataSchema.PlayerData
	if data.CreatedAt == 0 then
		data.CreatedAt = os.time()
	end
	Session.Create(player, profile)
end

local function onPlayerRemoving(player: Player)
	local session = Session.Get(player)
	if not session then
		return
	end
	if session.OfflineHandled then
		session.Data.Stats.LastOnline = os.time()
	end
	local profile = session.Profile
	Session.Remove(player)
	profile:EndSession()
end

function DataService.Start()
	Players.PlayerAdded:Connect(function(player: Player)
		onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Force une sauvegarde immédiate (après un achat Robux par exemple).
function DataService.SaveNow(session: Session.Session)
	if session.Profile:IsActive() then
		session.Profile:Save()
	end
end

return DataService
