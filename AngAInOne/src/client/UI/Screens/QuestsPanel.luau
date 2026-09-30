--!strict
--[[
	QuestsPanel : récompense quotidienne (calendrier 7 jours), quêtes du jour et de la
	semaine, téléchargements. Aucune popup forcée : un badge sur le bouton du dock
	signale qu'il y a quelque chose à récupérer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local GameConfig = require(Shared.Config.GameConfig)
local Products = require(Shared.Config.Products)
local Formulas = require(Shared.Economy.Formulas)
local NumberFormat = require(Shared.Util.NumberFormat)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Panel = require(script.Parent.Parent.Components.Panel)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Icon = require(script.Parent.Parent.Components.Icon)
local App = require(script.Parent.Parent.App)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local QuestsPanel = {}

local panel: Panel.Panel
local scroll: ScrollingFrame
local lastKey = ""
local downloadLabel: TextLabel? = nil
local downloadBar: Widgets.Bar? = nil
-- Lignes de quêtes mises à jour EN PLACE (progression) sans reconstruire le panneau.
type LiveRow = { Id: string, Bar: Widgets.Bar, Label: TextLabel, Kind: string, Target: number }
local liveRows: { LiveRow } = {}

local function section(title: string, order: number)
	New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = order,
		Tag = "TextTitle",
		Parent = scroll,
	})
end

local function dailyCalendar(state: any, order: number)
	local data = state.Data
	local today = Formulas.DayIndex(Store.UnixNow())
	local canClaim = data.Daily.LastClaimDay ~= today
	-- Jour qui sera réclamé (ou vient de l'être)
	local streakIfClaim = if data.Daily.LastClaimDay == today - 1
		then data.Daily.Streak + 1
		else math.max(data.Daily.Streak - 1, 0) + 1
	local currentDay = if canClaim then ((streakIfClaim - 1) % 7) + 1 else ((data.Daily.Streak - 1) % 7) + 1

	local row: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = scroll,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	for _, reward in Quests.DailyRewards do
		local isToday = reward.Day == currentDay
		local claimed = reward.Day < currentDay or (reward.Day == currentDay and not canClaim)
		local cell: Frame = New("Frame", {
			Size = UDim2.fromOffset(92, 110),
			BackgroundTransparency = if isToday then 0.05 else 0.35,
			BorderSizePixel = 0,
			LayoutOrder = reward.Day,
			Tag = { if isToday then "GlassRaised" else "GlassSunken", "RoundM" },
			Parent = row,
		}, {
			New("UIStroke", {
				Color = Style.Color(if isToday then "BrandAnga" else "Stroke"),
				Transparency = if isToday then 0.1 else 0.85,
				Thickness = if isToday then 2 else 1,
			}),
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = `JOUR {reward.Day}`,
			Tag = "TextCaption",
			Parent = cell,
		})
		local icon = Icon.new(
			if claimed
				then "Check"
				elseif reward.Kind == "Chips" then "Chips"
				elseif reward.Kind == "Bits" then "Bits"
				else "Gift",
			36,
			if claimed then "Success" else nil
		)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 28)
		icon.Parent = cell
		New("TextLabel", {
			Position = UDim2.fromOffset(4, 70),
			Size = UDim2.new(1, -8, 0, 34),
			BackgroundTransparency = 1,
			Text = reward.Label,
			TextWrapped = true,
			Tag = "TextCaption",
			Parent = cell,
		})
	end
	local claim = Keycap.new({
		Text = if canClaim then "RÉCUPÉRER" else "À DEMAIN",
		Variant = "Primary",
		Size = UDim2.fromOffset(150, 56),
		LayoutOrder = 99,
		Small = true,
		OnClick = function()
			Net.Fire("ClaimDaily")
		end,
		Parent = row,
	})
	claim:SetEnabled(canClaim)
end

local function questRow(quest: any, order: number)
	local template = Quests.ById[quest.Id]
	if not template then
		return
	end
	local card = Widgets.Card(UDim2.new(1, -4, 0, 72), scroll, order)
	local target = if template.Kind == "Collect" then NumberFormat.Compact(quest.Target) else tostring(quest.Target)
	New("TextLabel", {
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -220, 0, 22),
		BackgroundTransparency = 1,
		Text = (string.gsub(template.Text, "{n}", target)),
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = card,
	})
	local bar = Widgets.Bar(UDim2.new(1, -320, 0, 10), Style.Color("AccentViolet"), card)
	bar.Root.Position = UDim2.fromOffset(14, 44)
	bar:Set(quest.Progress / math.max(quest.Target, 1), false)
	local progress = if template.Kind == "Collect"
		then NumberFormat.Compact(quest.Progress)
		else tostring(math.floor(quest.Progress))
	local progressLabel: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -196, 0, 38),
		Size = UDim2.fromOffset(100, 20),
		BackgroundTransparency = 1,
		Text = `{progress}/{target}`,
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "TextCaption",
		Parent = card,
	})
	table.insert(
		liveRows,
		{ Id = quest.Id, Bar = bar, Label = progressLabel, Kind = template.Kind :: string, Target = quest.Target } :: LiveRow
	)
	local done = quest.Progress >= quest.Target
	local key = Keycap.new({
		Text = if quest.Claimed then "RÉCUPÉRÉ" else `+{template.Chips} CHIPS`,
		Variant = if done and not quest.Claimed then "Cyan" else "Secondary",
		Size = UDim2.fromOffset(170, 48),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Small = true,
		OnClick = function()
			Net.Fire("ClaimQuest", quest.Id)
		end,
		Parent = card,
	})
	key:SetEnabled(done and not quest.Claimed)
end

local function downloads(state: any, order: number)
	local data = state.Data
	downloadLabel = nil
	downloadBar = nil
	if data.Zone < GameConfig.DownloadRequiredZone then
		local card = Widgets.Card(UDim2.new(1, -4, 0, 56), scroll, order)
		New("TextLabel", {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			BackgroundTransparency = 1,
			Text = "Débloque le Data Vault (SSD) pour lancer des téléchargements.",
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextMuted",
			Parent = card,
		})
		return
	end
	if data.Download.Kind ~= "" then
		local kind = nil
		for _, k in GameConfig.Downloads do
			if k.Id == data.Download.Kind then
				kind = k
			end
		end
		if not kind then
			return
		end
		local card = Widgets.Card(UDim2.new(1, -4, 0, 84), scroll, order)
		local icon = Icon.new("Download", 36, "AccentCyan")
		icon.Position = UDim2.fromOffset(16, 22)
		icon.Parent = card
		New("TextLabel", {
			Position = UDim2.fromOffset(66, 10),
			Size = UDim2.new(1, -300, 0, 22),
			BackgroundTransparency = 1,
			Text = kind.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextHeading",
			Parent = card,
		})
		local label: TextLabel = New("TextLabel", {
			Position = UDim2.fromOffset(66, 34),
			Size = UDim2.new(1, -300, 0, 18),
			BackgroundTransparency = 1,
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextMuted",
			Parent = card,
		})
		local bar = Widgets.Bar(UDim2.new(1, -300, 0, 10), Style.Color("AccentCyan"), card)
		bar.Root.Position = UDim2.fromOffset(66, 60)
		downloadLabel = label
		downloadBar = bar
		local remaining = data.Download.StartedAt + kind.Seconds - Store.UnixNow()
		if remaining <= 0 then
			Keycap.new({
				Text = "RÉCUPÉRER",
				Variant = "Cyan",
				Size = UDim2.fromOffset(200, 52),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Small = true,
				OnClick = function()
					Net.Fire("ClaimDownload")
				end,
				Parent = card,
			})
		else
			local skip = Products.ProductByKey.SkipDownload
			if skip and skip.Id ~= 0 then
				Keycap.new({
					Text = `TERMINER · R$ {skip.Price}`,
					Variant = "Gold",
					Size = UDim2.fromOffset(200, 52),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Small = true,
					OnClick = function()
						MarketplaceService:PromptProductPurchase(Players.LocalPlayer, skip.Id)
					end,
					Parent = card,
				})
			end
		end
		return
	end
	for index, kind in GameConfig.Downloads do
		local card = Widgets.Card(UDim2.new(1, -4, 0, 70), scroll, order + index)
		New("TextLabel", {
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -250, 0, 22),
			BackgroundTransparency = 1,
			Text = `{kind.Name} · {NumberFormat.Duration(kind.Seconds)}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextHeading",
			Parent = card,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -250, 0, 18),
			BackgroundTransparency = 1,
			Text = `Récompense : {NumberFormat.Duration(kind.ProductionSeconds)} de production + {kind.Chips} Chips`,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextMuted",
			Parent = card,
		})
		Keycap.new({
			Text = "LANCER",
			Variant = "Secondary",
			Size = UDim2.fromOffset(150, 46),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Small = true,
			OnClick = function()
				Net.Fire("StartDownload", kind.Id)
			end,
			Parent = card,
		})
	end
end

local function signature(state: any): string
	local data = state.Data
	local parts =
		{ tostring(data.Daily.LastClaimDay), tostring(data.Daily.Streak), data.Download.Kind, tostring(data.Zone) }
	for _, list in { data.Quests.Daily, data.Quests.Weekly } do
		for _, quest in list do
			-- Seul le passage à "terminée" change la mise en page ; la progression est mise à jour en place.
			table.insert(parts, `{quest.Id}:{quest.Progress >= quest.Target}:{quest.Claimed}`)
		end
	end
	return table.concat(parts, "|")
end

local function updateLive(state: any)
	local byId: { [string]: any } = {}
	for _, list in { state.Data.Quests.Daily, state.Data.Quests.Weekly } do
		for _, quest in list do
			byId[quest.Id] = quest
		end
	end
	for _, row in liveRows do
		local quest = byId[row.Id]
		if quest then
			row.Bar:Set(quest.Progress / math.max(row.Target, 1))
			local progress = if row.Kind == "Collect"
				then NumberFormat.Compact(quest.Progress)
				else tostring(math.floor(quest.Progress))
			local target = if row.Kind == "Collect" then NumberFormat.Compact(row.Target) else tostring(row.Target)
			row.Label.Text = `{progress}/{target}`
		end
	end
end

local function rebuild(force: boolean?)
	local state = Store.State
	if not state or not panel:IsOpen() then
		return
	end
	local key = signature(state)
	if key == lastKey and not force then
		updateLive(state)
		return
	end
	lastKey = key
	table.clear(liveRows)
	local canvas = scroll.CanvasPosition
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	section("RÉCOMPENSE DU JOUR", 1)
	dailyCalendar(state, 2)
	section("QUÊTES DU JOUR", 10)
	for index, quest in state.Data.Quests.Daily do
		questRow(quest, 10 + index)
	end
	section("QUÊTES DE LA SEMAINE", 30)
	for index, quest in state.Data.Quests.Weekly do
		questRow(quest, 30 + index)
	end
	section("TÉLÉCHARGEMENTS", 50)
	downloads(state, 51)
	task.defer(function()
		scroll.CanvasPosition = canvas
	end)
end

local function tickDownload()
	local state = Store.State
	local label = downloadLabel
	local bar = downloadBar
	if not state or not label or not bar or state.Data.Download.Kind == "" then
		return
	end
	for _, kind in GameConfig.Downloads do
		if kind.Id == state.Data.Download.Kind then
			local elapsed = Store.UnixNow() - state.Data.Download.StartedAt
			local remaining = kind.Seconds - elapsed
			label.Text = if remaining > 0 then `Encore {NumberFormat.Duration(remaining)}` else "Terminé !"
			bar:Set(elapsed / kind.Seconds, false)
			if remaining <= 0 and remaining > -1.5 then
				rebuild(true)
			end
		end
	end
end

function QuestsPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "QuestsPanel",
		Title = "MISSIONS",
		Subtitle = "Des cadeaux à gagner chaque jour !",
		Size = UDim2.fromScale(0.8, 0.86),
		Parent = layer,
		Accent = Style.Color("CurrencyChips"),
	})
	scroll = Widgets.Scroll(panel.Body, 10)
	Store.Changed:Connect(function()
		rebuild(false)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if panel:IsOpen() then
				tickDownload()
			end
		end
	end)
	App.RegisterPanel("Quests", {
		Panel = panel,
		OnOpen = function(_arg: any)
			task.defer(rebuild, true)
		end,
	})
end

return QuestsPanel
