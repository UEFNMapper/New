--!nonstrict
-- Sauvegarde des joueurs (ProfileStore, verrou de session anti-duplication)
-- et réplication des données vers le client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local DataTemplate = require(Shared.Logic.DataTemplate)
local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)

local DataService = {}

DataService.Loaded = Signal.new() :: Signal.Signal<Player, any>
DataService.Releasing = Signal.new() :: Signal.Signal<Player, any>

local STORE_NAME = "StealAKaiju_v1"

local store = ProfileStore.New(STORE_NAME, DataTemplate)
-- Dans Studio sans accès API, ProfileStore bascule tout seul en mode simulé.
-- On force le mode simulé si l'attribut UseMockData est coché sur le script serveur.
local useMock = RunService:IsStudio() and (script.Parent.Parent:GetAttribute("UseMockData") == true)
local activeStore = if useMock then store.Mock else store

local profiles: { [Player]: any } = {}
local dataEvent = Net.Event("Data")

local function deepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in t :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function onPlayerAdded(player: Player)
	local profile = activeStore:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		player:Kick("Your data could not be loaded. Please rejoin!")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your save was opened on another server. Please rejoin!")
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	-- Envoi complet initial
	dataEvent:FireClient(player, deepCopy(profile.Data), true)
	DataService.Loaded:Fire(player, profile.Data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		DataService.Releasing:Fire(player, profile.Data)
		-- Laisse les services écrire leurs dernières valeurs
		task.wait()
		profile.Data.LastOnline = os.time()
		profile:EndSession()
		profiles[player] = nil
	end
end

function DataService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Données du joueur (nil tant que pas chargées).
function DataService.Get(player: Player): any
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.Profile(player: Player): any
	return profiles[player]
end

function DataService.WaitFor(player: Player, timeout: number?): any
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.Get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

-- Réplique les champs de premier niveau indiqués vers le client.
function DataService.Replicate(player: Player, ...: string)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local patch = {}
	for _, key in { ... } do
		patch[key] = deepCopy(data[key])
	end
	dataEvent:FireClient(player, patch, false)
end

-- Envoie une valeur calculée (non sauvegardée) au client, ex. Income.
function DataService.SendDerived(player: Player, key: string, value: any)
	dataEvent:FireClient(player, { [key] = value }, false)
end

function DataService.AddCash(player: Player, amount: number, countsAsEarned: boolean?)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Cash += amount
	if countsAsEarned ~= false and amount > 0 then
		data.TotalEarned += amount
	end
	DataService.Replicate(player, "Cash", "TotalEarned")
end

function DataService.Spend(player: Player, currency: string, amount: number): boolean
	local data = DataService.Get(player)
	if not data or amount < 0 or data[currency] == nil or data[currency] < amount then
		return false
	end
	data[currency] -= amount
	DataService.Replicate(player, currency)
	return true
end

function DataService.AddGems(player: Player, amount: number)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Gems += amount
	DataService.Replicate(player, "Gems")
end

function DataService.Save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

return DataService
