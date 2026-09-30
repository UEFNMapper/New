--!strict
--[[
	LeaderboardService : deux classements globaux (OrderedDataStore).
	- "Légendes" : Bits produits depuis toujours (TotalBitsEarned)
	- "Cette semaine" : Bits de la semaine (reset chaque lundi 00:00 UTC)
	Les valeurs dépassant 2^63 sont stockées en échelle logarithmique (log10 x 1e8).
	Sans accès aux DataStores (Studio), on affiche les joueurs du serveur.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Economy.Formulas)
local Remotes = require(Shared.Net.Remotes)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)

local LeaderboardService = {}

local SCALE = 1e8
local TOP = 20
local UPDATE_INTERVAL = 90
local FETCH_INTERVAL = 120

export type Entry = { UserId: number, Name: string, Value: number }
export type Boards = { Legends: { Entry }, Weekly: { Entry }, WeekIndex: number }

local boards: Boards = { Legends = {}, Weekly = {}, WeekIndex = 0 }
local names: { [number]: string } = {}
local leaderboardRemote: RemoteEvent

local function encode(value: number): number
	return math.floor(math.log10(math.max(value, 0) + 1) * SCALE)
end

local function decode(stored: number): number
	return 10 ^ (stored / SCALE) - 1
end

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

local function stores(): (OrderedDataStore?, OrderedDataStore?, number)
	local week = Formulas.WeekIndex(os.time())
	local ok, legends, weekly = pcall(function()
		return DataStoreService:GetOrderedDataStore("Legends_v1"),
			DataStoreService:GetOrderedDataStore(`Weekly_v1_{week}`)
	end)
	if ok then
		return legends, weekly, week
	end
	return nil, nil, week
end

local function pushScores()
	local legends, weekly, week = stores()
	for _, session in Session.All() do
		local key = tostring(session.UserId)
		if legends then
			pcall(function()
				legends:SetAsync(key, encode(session.Data.TotalBitsEarned))
			end)
		end
		if weekly and session.Data.WeeklyIndex == week then
			pcall(function()
				weekly:SetAsync(key, encode(session.Data.WeeklyBits))
			end)
		end
	end
end

local function read(store: OrderedDataStore?): { Entry }?
	if not store then
		return nil
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, TOP):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		return nil
	end
	local entries: { Entry } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { UserId = userId, Name = nameOf(userId), Value = decode(item.value) })
		end
	end
	return entries
end

-- Repli local (Studio sans API) : classe les joueurs présents.
local function localBoard(field: "TotalBitsEarned" | "WeeklyBits"): { Entry }
	local entries: { Entry } = {}
	for _, session in Session.All() do
		table.insert(entries, {
			UserId = session.UserId,
			Name = session.Player.DisplayName,
			Value = if field == "TotalBitsEarned" then session.Data.TotalBitsEarned else session.Data.WeeklyBits,
		})
	end
	table.sort(entries, function(a: Entry, b: Entry): boolean
		return a.Value > b.Value
	end)
	return entries
end

local function refresh()
	local legends, weekly, week = stores()
	boards = {
		Legends = read(legends) or localBoard("TotalBitsEarned"),
		Weekly = read(weekly) or localBoard("WeeklyBits"),
		WeekIndex = week,
	}
	leaderboardRemote:FireAllClients(boards)
end

function LeaderboardService.Start()
	leaderboardRemote = Remotes.Get("Leaderboard")
	GameEvents.ClientReady:Connect(function(player: Player)
		leaderboardRemote:FireClient(player, boards)
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			pushScores()
			refresh()
			task.wait(UPDATE_INTERVAL)
		end
	end)
	-- Rafraîchissement plus fréquent de la lecture si le serveur est calme.
	task.spawn(function()
		while true do
			task.wait(FETCH_INTERVAL)
			refresh()
		end
	end)
end

return LeaderboardService
