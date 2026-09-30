--!strict
--[[
	LeaderboardService : trois classements globaux (OrderedDataStore).
	- "Wins"     : nombre d'ascensions réussies
	- "BestTime" : meilleur temps (sans assistance), stocké en centièmes, trié du plus petit
	- "Stage"    : étape la plus haute atteinte
	Sans accès aux DataStores (Studio), on affiche les joueurs du serveur.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)

local LeaderboardService = {}

local TOP = 10
local UPDATE_INTERVAL = 90

export type Entry = { UserId: number, Name: string, Value: number }
export type Boards = { Wins: { Entry }, BestTime: { Entry }, Stage: { Entry } }

type BoardDef = { Key: string, Store: string, Ascending: boolean, Read: (Session.Session) -> number }

local BOARDS: { BoardDef } = {
	{
		Key = "Wins",
		Store = "Deathrun_Wins_v1",
		Ascending = false,
		Read = function(session)
			return session.Data.Wins
		end,
	},
	{
		Key = "BestTime",
		Store = "Deathrun_BestTime_v1",
		Ascending = true,
		Read = function(session)
			return math.floor(session.Data.BestTime * 100)
		end,
	},
	{
		Key = "Stage",
		Store = "Deathrun_Stage_v1",
		Ascending = false,
		Read = function(session)
			return session.Data.BestStage
		end,
	},
}

local boards: Boards = { Wins = {}, BestTime = {}, Stage = {} }
local names: { [number]: string } = {}
local leaderboardRemote: RemoteEvent

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else "???"
	names[userId] = result
	return result
end

local function storeFor(def: BoardDef): OrderedDataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(def.Store)
	end)
	return if ok then store else nil
end

local function pushSession(def: BoardDef, store: OrderedDataStore, session: Session.Session)
	local value = def.Read(session)
	if value > 0 then
		pcall(function()
			store:SetAsync(tostring(session.UserId), value)
		end)
	end
end

local function push(def: BoardDef)
	local store = storeFor(def)
	if not store then
		return
	end
	for _, session in Session.All() do
		pushSession(def, store, session)
	end
end

-- Envoie tout de suite les scores d'un joueur (victoire, départ).
local function pushOne(session: Session.Session)
	for _, def in BOARDS do
		local store = storeFor(def)
		if store then
			pushSession(def, store, session)
		end
	end
end

local function read(def: BoardDef): { Entry }?
	local store = storeFor(def)
	if not store then
		return nil
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(def.Ascending, TOP, 1):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		return nil
	end
	local entries: { Entry } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId then
			local value = if def.Key == "BestTime" then item.value / 100 else item.value
			table.insert(entries, { UserId = userId, Name = nameOf(userId), Value = value })
		end
	end
	return entries
end

-- Repli local (Studio sans API) : classe les joueurs présents.
local function localBoard(def: BoardDef): { Entry }
	local entries: { Entry } = {}
	for _, session in Session.All() do
		local value = def.Read(session)
		if value > 0 then
			table.insert(entries, {
				UserId = session.UserId,
				Name = session.Player.DisplayName,
				Value = if def.Key == "BestTime" then value / 100 else value,
			})
		end
	end
	table.sort(entries, function(a: Entry, b: Entry): boolean
		return if def.Ascending then a.Value < b.Value else a.Value > b.Value
	end)
	return entries
end

local function refresh()
	local result: any = {}
	for _, def in BOARDS do
		result[def.Key] = read(def) or localBoard(def)
	end
	boards = result
	leaderboardRemote:FireAllClients(boards)
end

function LeaderboardService.Start()
	leaderboardRemote = Remotes.Get("Leaderboard")
	GameEvents.ClientReady:Connect(function(player: Player)
		leaderboardRemote:FireClient(player, boards)
	end)
	GameEvents.Victory:Connect(function(player: Player, _time: number)
		local session = Session.Get(player)
		if session then
			task.spawn(pushOne, session)
		end
	end)
	Session.Removing:Connect(function(session: Session.Session)
		task.spawn(pushOne, session)
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			for _, def in BOARDS do
				push(def)
			end
			refresh()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return LeaderboardService
