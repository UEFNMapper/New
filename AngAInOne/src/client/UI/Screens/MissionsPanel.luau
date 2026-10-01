--!strict
--[[
	MissionsPanel : calendrier de connexion (7 jours) + 3 missions du jour.
	Aucune popup forcée : un badge sur le bouton du dock signale qu'il y a un cadeau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Missions = require(Shared.Config.Missions)
local Time = require(Shared.Util.Time)

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

local MissionsPanel = {}

local panel: Panel.Panel
local scroll: ScrollingFrame
local lastKey = ""

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

local function calendar(data: any, order: number)
	local today = Time.DayIndex(Store.UnixNow())
	local canClaim = data.Daily.LastClaimDay ~= today
	-- Même calcul que le serveur : un jour manqué fait reculer la série d'un jour.
	local missed = if data.Daily.LastClaimDay < 0 then 0 else today - data.Daily.LastClaimDay - 1
	local nextStreak = math.max(data.Daily.Streak - missed, 0) + 1
	local count = #GameConfig.DailyRewards
	local currentDay = if canClaim then (nextStreak - 1) % count + 1 else (data.Daily.Streak - 1) % count + 1

	local row: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = scroll,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	for _, reward in GameConfig.DailyRewards do
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
			if claimed then "Check" elseif reward.Cosmetic then "Gift" else "Bits",
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

local function missionRow(mission: any, order: number)
	local template = Missions.ById[mission.Id]
	if not template then
		return
	end
	local card = Widgets.Card(UDim2.new(1, -4, 0, 78), scroll, order)
	New("TextLabel", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -220, 0, 24),
		BackgroundTransparency = 1,
		Text = (string.gsub(template.Text, "{n}", tostring(mission.Target))),
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = card,
	})
	local bar = Widgets.Bar(UDim2.new(1, -300, 0, 10), Style.Color("AccentViolet"), card)
	bar.Root.Position = UDim2.fromOffset(16, 48)
	bar:Set(mission.Progress / math.max(mission.Target, 1), false)
	New("TextLabel", {
		Position = UDim2.new(1, -276, 0, 40),
		Size = UDim2.fromOffset(60, 24),
		BackgroundTransparency = 1,
		Text = `{mission.Progress}/{mission.Target}`,
		Tag = "TextCaption",
		Parent = card,
	})
	local done = mission.Progress >= mission.Target
	local key = Keycap.new({
		Text = if mission.Claimed then "FAIT ✓" elseif done then `+{template.Bits} Bits` else `{template.Bits} Bits`,
		Variant = if done and not mission.Claimed then "Gold" else "Secondary",
		Size = UDim2.fromOffset(170, 52),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Small = true,
		OnClick = function()
			Net.Fire("ClaimMission", mission.Id)
		end,
		Parent = card,
	})
	key:SetEnabled(done and not mission.Claimed)
end

local function rebuild(force: boolean?)
	local state = Store.State
	if not state or not panel:IsOpen() then
		return
	end
	local data = state.Data
	local parts = { tostring(data.Daily.LastClaimDay), tostring(data.Daily.Streak) }
	for _, mission in data.Missions.List do
		table.insert(parts, `{mission.Id}:{mission.Progress}:{mission.Claimed}`)
	end
	local key = table.concat(parts, "|")
	if key == lastKey and not force then
		return
	end
	lastKey = key
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	section("CADEAU DU JOUR", 1)
	calendar(data, 2)
	section("MISSIONS DU JOUR", 3)
	for index, mission in data.Missions.List do
		missionRow(mission, 3 + index)
	end
end

function MissionsPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "MissionsPanel",
		Title = "Missions",
		Subtitle = "Des cadeaux à gagner chaque jour !",
		Size = UDim2.fromScale(0.8, 0.86),
		Parent = layer,
		Accent = Style.Color("AccentViolet"),
	})
	scroll = Widgets.Scroll(panel.Body, 10)
	Store.Changed:Connect(function()
		rebuild(false)
	end)
	App.RegisterPanel("Missions", {
		Panel = panel,
		OnOpen = function(_arg: any)
			task.defer(rebuild, true)
		end,
	})
end

return MissionsPanel
