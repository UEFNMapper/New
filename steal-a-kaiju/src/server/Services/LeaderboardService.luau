--!nonstrict
-- Classements : leaderstats (liste des joueurs) + tableaux mondiaux
-- (OrderedDataStore) affichés autour du cratère.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local Theme = require(Shared.Config.Theme)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local BOARDS = {
	{ Key = "TotalEarned", Title = "💰 RICHEST TYCOONS", Store = "LB_Earned_v1", Format = Format.Cash, Color = Theme.Colors.Cash },
	{ Key = "Steals", Title = "🦹 MASTER THIEVES", Store = "LB_Steals_v1", Format = Format.Short, Color = Theme.Colors.Pink },
	{ Key = "Rebirths", Title = "🧬 TOP EVOLVERS", Store = "LB_Rebirths_v1", Format = Format.Short, Color = Theme.Colors.Radioactive },
}

local stores: { [string]: OrderedDataStore? } = {}
local boardGuis: { [string]: Frame } = {}

local function statOf(data: any, key: string): number
	if key == "Steals" then
		return data.Stats.Steals
	end
	return data[key] or 0
end

function LeaderboardService.Update(player: Player)
	local data = DataService.Get(player)
	local stats = player:FindFirstChild("leaderstats")
	if not data or not stats then
		return
	end
	local cash = stats:FindFirstChild("Cash") :: StringValue?
	local steals = stats:FindFirstChild("Steals") :: IntValue?
	local rebirths = stats:FindFirstChild("Evolution") :: IntValue?
	if cash then
		cash.Value = Format.Cash(data.Cash)
	end
	if steals then
		steals.Value = data.Stats.Steals
	end
	if rebirths then
		rebirths.Value = data.Rebirths
	end
end

local function buildBoard(cf: CFrame, board: typeof(BOARDS[1]), parent: Instance)
	local part = Instance.new("Part")
	part.Name = "Board_" .. board.Key
	part.Anchored = true
	part.Size = Vector3.new(26, 32, 1.4)
	part.CFrame = cf * CFrame.new(0, 17, 0)
	part.Color = Theme.Colors.Ink
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	-- cadre lumineux aux couleurs du tableau
	for _, edge in {
		{ Vector3.new(27.6, 1.2, 1.8), CFrame.new(0, 16.6, 0) },
		{ Vector3.new(27.6, 1.2, 1.8), CFrame.new(0, -16.6, 0) },
		{ Vector3.new(1.2, 34.4, 1.8), CFrame.new(13.4, 0, 0) },
		{ Vector3.new(1.2, 34.4, 1.8), CFrame.new(-13.4, 0, 0) },
	} do
		local trim = Instance.new("Part")
		trim.Anchored = true
		trim.CanCollide = false
		trim.Size = edge[1]
		trim.CFrame = part.CFrame * edge[2]
		trim.Color = board.Color
		trim.Material = Enum.Material.Neon
		trim.Parent = parent
	end
	for _, side in { -1, 1 } do
		local leg = Instance.new("Part")
		leg.Anchored = true
		leg.Size = Vector3.new(1.6, 18, 1.6)
		leg.CFrame = cf * CFrame.new(side * 10, 1, 0.9)
		leg.Color = board.Color
		leg.Material = Enum.Material.Metal
		leg.Parent = parent
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(520, 640)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = part
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 80)
	title.BackgroundColor3 = board.Color
	title.FontFace = Theme.Fonts.Title
	title.TextScaled = true
	title.TextColor3 = Theme.Colors.Ink
	title.Text = board.Title
	title.Parent = gui
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(0, 90)
	list.Size = UDim2.new(1, 0, 1, -90)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	boardGuis[board.Key] = list
end

local function renderBoard(board: typeof(BOARDS[1]), entries: { { name: string, value: number } })
	local list = boardGuis[board.Key]
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for rank, entry in entries do
		local row = Instance.new("TextLabel")
		row.LayoutOrder = rank
		row.Size = UDim2.new(1, -16, 0, 50)
		row.BackgroundTransparency = if rank % 2 == 0 then 0.85 else 0.92
		row.BackgroundColor3 = Theme.Colors.Paper
		row.FontFace = Theme.Fonts.Body
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		local medal = if rank == 1 then "🥇" elseif rank == 2 then "🥈" elseif rank == 3 then "🥉" else "#" .. rank
		row.Text = ("  %s  %s — %s"):format(medal, entry.name, board.Format(entry.value))
		row.TextColor3 = if rank <= 3 then board.Color else Theme.Colors.Paper
		row.Parent = list
	end
	if #entries == 0 then
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 50)
		row.BackgroundTransparency = 1
		row.FontFace = Theme.Fonts.Body
		row.TextScaled = true
		row.TextColor3 = Theme.Colors.Paper
		row.Text = "Be the first!"
		row.Parent = list
	end
end

local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = if ok and name then name else "???"
	nameCache[userId] = result
	return result
end

local function refreshGlobal()
	for _, board in BOARDS do
		local store = stores[board.Key]
		if store then
			for _, player in Players:GetPlayers() do
				local data = DataService.Get(player)
				if data then
					-- les OrderedDataStore n'acceptent que des entiers 64 bits
					local value = math.clamp(math.floor(statOf(data, board.Key)), 0, 9e18)
					pcall(store.SetAsync, store, tostring(player.UserId), value)
				end
			end
			local ok, pages = pcall(store.GetSortedAsync, store, false, 10)
			if ok and pages then
				local entries = {}
				for _, item in (pages :: DataStorePages):GetCurrentPage() do
					local userId = tonumber(item.key) or 0
					table.insert(entries, { name = nameOf(userId), value = item.value })
				end
				renderBoard(board, entries)
			end
		end
	end
end

function LeaderboardService.Init()
	Players.PlayerAdded:Connect(function(player)
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		local cash = Instance.new("StringValue")
		cash.Name = "Cash"
		cash.Value = "$0"
		cash.Parent = stats
		local steals = Instance.new("IntValue")
		steals.Name = "Steals"
		steals.Parent = stats
		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Evolution"
		rebirths.Parent = stats
		stats.Parent = player
	end)
	DataService.Loaded:Connect(function(player)
		LeaderboardService.Update(player)
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				LeaderboardService.Update(player)
			end
		end
	end)
end

function LeaderboardService.Start(boardCFrames: { CFrame })
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = Workspace:WaitForChild("Map")
	for i, board in BOARDS do
		local cf = boardCFrames[i]
		if cf then
			buildBoard(cf, board, folder)
		end
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, board.Store)
		stores[board.Key] = if ok then store else nil
		renderBoard(board, {})
	end
	task.spawn(function()
		task.wait(10)
		while true do
			pcall(refreshGlobal)
			task.wait(120)
		end
	end)
end

return LeaderboardService
