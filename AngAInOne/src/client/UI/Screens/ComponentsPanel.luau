--!strict
--[[
	ComponentsPanel : améliorations de modules, capacité (Watts / refroidissement)
	et déblocage de zone. Les cartes sont construites une fois par onglet puis
	mises à jour en place (pas de scintillement, l'état de survol est conservé).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Zones = require(Shared.Config.Zones)
local Modules = require(Shared.Config.Modules)
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Economy.Formulas)
local NumberFormat = require(Shared.Util.NumberFormat)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Panel = require(script.Parent.Parent.Components.Panel)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Icon = require(script.Parent.Parent.Components.Icon)
local App = require(script.Parent.Parent.App)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local ComponentsPanel = {}

local TIERS = {
	{ Min = 100, Name = "Prisme", Color = "BrandAnga" },
	{ Min = 50, Name = "Diamant", Color = "CurrencyChips" },
	{ Min = 25, Name = "Or", Color = "CurrencyBits" },
	{ Min = 10, Name = "Argent", Color = "TextPrimary" },
	{ Min = 1, Name = "Bronze", Color = "AccentAmber" },
}

function ComponentsPanel.Tier(level: number): (string, string)
	for _, tier in TIERS do
		if level >= tier.Min then
			return tier.Name, tier.Color
		end
	end
	return "Non acheté", "TextMuted"
end

local function nextMilestone(level: number): number?
	for _, milestone in GameConfig.Milestones do
		if level < milestone then
			return milestone
		end
	end
	return nil
end

type Updater = () -> ()

local panel: Panel.Panel
local tabsList: ScrollingFrame
local content: ScrollingFrame
local selectedZone = 1
local tabKeys: { Keycap.Keycap } = {}
local updaters: { Updater } = {}
local focusModule: string? = nil
local builtAtZone = 0 -- zone débloquée au moment de la construction de l'onglet

local function smallKey(text: string, variant: Keycap.Variant, order: number, onClick: () -> ()): Keycap.Keycap
	return Keycap.new({
		Text = text,
		Variant = variant,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = order,
		Small = true,
		OnClick = onClick,
	})
end

local function buttonsColumn(parent: Frame): Frame
	return New("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(170, 120),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Create.List(Enum.FillDirection.Vertical, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
end

-- Étoiles de tier (1 à 5) : plus parlant qu'un nom de matériau pour un enfant.
local function starsFor(level: number): string
	local count = 0
	for _, tier in TIERS do
		if level >= tier.Min then
			count = #TIERS - table.find(TIERS, tier) :: number + 1
			break
		end
	end
	return string.rep("★", count) .. string.rep("☆", #TIERS - count)
end

-- Carte d'une machine : nom, niveau + étoiles, barre « x2 », UN gros bouton AMÉLIORER (+ MAX).
local function moduleCard(def: Modules.ModuleDef, order: number)
	local zone = Zones[def.Zone]
	local card = Widgets.Card(UDim2.new(1, 0, 0, 120), content, order)
	card.Name = def.Id
	local tile: Frame = New("Frame", {
		Position = UDim2.fromOffset(12, 14),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = Color3.fromHex(zone.Primary),
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Tag = "RoundM",
		Parent = card,
	}, {
		New("UIStroke", { Color = Color3.fromHex(zone.Primary), Transparency = 0.2, Thickness = 2 }),
	})
	local icon = Icon.new("Cpu", 44, nil)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.42)
	icon.Parent = tile
	local levelBadge: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -8, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextColor3 = Style.Color("TextPrimary"),
		TextStrokeTransparency = 0.5,
		Tag = "FontHeavy",
		Parent = tile,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(110, 12),
		Size = UDim2.new(1, -330, 0, 26),
		BackgroundTransparency = 1,
		Text = def.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Tag = "TextHeading",
		Parent = card,
	})
	local stars: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(110, 40),
		Size = UDim2.new(1, -330, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("CurrencyBits"),
		Tag = "FontHeavy",
		Parent = card,
	}, { New("UITextSizeConstraint", { MaxTextSize = 22 }) :: Instance })
	local milestoneLabel: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(110, 70),
		Size = UDim2.new(1, -330, 0, 16),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextCaption",
		Parent = card,
	})
	local bar = Widgets.Bar(UDim2.new(1, -330, 0, 10), Color3.fromHex(zone.Primary), card)
	bar.Root.Position = UDim2.fromOffset(110, 92)

	local column = buttonsColumn(card)
	column.Size = UDim2.fromOffset(200, 100)
	local upgrade = Keycap.new({
		Text = "",
		Variant = "Success",
		Size = UDim2.new(1, 0, 0, 58),
		LayoutOrder = 1,
		OnClick = function()
			Net.Fire("Upgrade", def.Id, 1)
		end,
		Parent = column,
	})
	local max = smallKey("", "Gold", 2, function()
		Net.Fire("Upgrade", def.Id, -1)
	end)
	max.Button.Parent = column

	table.insert(updaters, function()
		local data = Store.Data()
		if not data then
			return
		end
		local level = data.Levels[def.Id] or 0
		local bits = Store.Bits()
		levelBadge.Text = if level > 0 then `Niv. {level}` else "NEUF"
		stars.Text = starsFor(level)
		local nextM = nextMilestone(level)
		if nextM then
			local previous = 0
			for _, m in GameConfig.Milestones do
				if m < nextM then
					previous = m
				end
			end
			milestoneLabel.Text = `Bonus x2 au niveau {nextM} !`
			bar:Set((level - previous) / (nextM - previous), false)
		else
			milestoneLabel.Text = "Machine au maximum de ses bonus !"
			bar:Set(1, false)
		end
		local remaining = GameConfig.MaxModuleLevel - level
		local cost1 = Formulas.UpgradeCost(def.BaseCost, level, GameConfig.LevelGrowth)
		local maxCount = Formulas.MaxAffordable(def.BaseCost, level, bits, GameConfig.LevelGrowth, remaining)
		upgrade:SetText(
			if remaining <= 0
				then "MAXIMUM"
				elseif level == 0 then `ACHETER · {NumberFormat.Compact(cost1)}`
				else `AMÉLIORER · {NumberFormat.Compact(cost1)}`
		)
		upgrade:SetEnabled(remaining > 0 and bits >= cost1)
		max:SetText(if maxCount > 1 then `TOUT · +{maxCount}` else "TOUT")
		max:SetEnabled(maxCount > 1)
		max.Button.Visible = level > 0
	end)
end

local function capacityCard(kind: string, order: number)
	local isPower = kind == "Power"
	local params = if isPower then GameConfig.Power else GameConfig.Cooling
	local card = Widgets.Card(UDim2.new(1, 0, 0, 110), content, order)
	local accent = if isPower then "CurrencyBits" else "AccentCyan"
	local icon = Icon.new(if isPower then "Bolt" else "Heat", 40, accent)
	icon.Position = UDim2.fromOffset(24, 20)
	icon.Parent = card
	New("TextLabel", {
		Position = UDim2.fromOffset(90, 10),
		Size = UDim2.new(1, -290, 0, 22),
		BackgroundTransparency = 1,
		Text = if isPower then "Énergie du PC" else "Refroidissement",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = card,
	})
	local info: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(90, 34),
		Size = UDim2.new(1, -290, 0, 40),
		BackgroundTransparency = 1,
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Tag = "TextMuted",
		Parent = card,
	})
	local bar = Widgets.Bar(UDim2.new(1, -290, 0, 8), Style.Color(accent), card)
	bar.Root.Position = UDim2.fromOffset(90, 84)
	local column = buttonsColumn(card)
	local plus = smallKey("", "Secondary", 1, function()
		Net.Fire("UpgradeCapacity", kind, 1)
	end)
	plus.Button.Parent = column
	local max = smallKey("TOUT", "Gold", 2, function()
		Net.Fire("UpgradeCapacity", kind, -1)
	end)
	max.Button.Parent = column

	table.insert(updaters, function()
		local state = Store.State
		if not state then
			return
		end
		local data = state.Data
		local production = state.Production
		local level = if isPower then data.PsuLevel else data.CoolingLevel
		local capacity = if isPower then production.PowerCapacity else production.HeatCapacity
		local demand = if isPower then production.PowerDemand else production.HeatDemand
		info.Text = if demand > capacity
			then (if isPower then "⚡ Pas assez d'énergie ! Améliore-moi." else "🌡 Trop chaud ! Améliore-moi.")
			else (if isPower then `⚡ Énergie OK (niveau {level})` else `❄ Température OK (niveau {level})`)
		bar:Set(demand / math.max(capacity, 1), false)
		bar:SetColor(Style.Color(if demand > capacity then "Danger" else accent))
		local cost = Formulas.CapacityUpgradeCost(params, level)
		local bits = Store.Bits()
		plus:SetText(`AMÉLIORER · {NumberFormat.Compact(cost)}`)
		plus:SetEnabled(bits >= cost and level < params.MaxLevel)
		max:SetEnabled(bits >= cost and level < params.MaxLevel)
	end)
end

local function unlockCard(zoneIndex: number, order: number)
	local zone = Zones[zoneIndex]
	local card = Widgets.Card(UDim2.new(1, 0, 0, 96), content, order)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Color3.fromHex(zone.Primary)
		stroke.Transparency = 0.2
	end
	local icon = Icon.new("Lock", 36, nil)
	icon.Position = UDim2.fromOffset(26, 30)
	icon.Parent = card
	New("TextLabel", {
		Position = UDim2.fromOffset(90, 14),
		Size = UDim2.new(1, -290, 0, 24),
		BackgroundTransparency = 1,
		Text = `Nouvelle zone : {zone.Name}`,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(90, 40),
		Size = UDim2.new(1, -290, 0, 40),
		BackgroundTransparency = 1,
		Text = `{zone.Tagline}\nNouveau : {zone.Feature}`,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Tag = "TextMuted",
		Parent = card,
	})
	local key = Keycap.new({
		Text = `OUVRIR · {NumberFormat.Compact(zone.UnlockCost)}`,
		Variant = "Primary",
		Size = UDim2.fromOffset(190, 48),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Small = true,
		OnClick = function()
			Net.Fire("UnlockZone", zoneIndex)
		end,
		Parent = card,
	})
	table.insert(updaters, function()
		key:SetEnabled(Store.Bits() >= zone.UnlockCost)
	end)
end

local function header(zoneIndex: number, order: number)
	local zone = Zones[zoneIndex]
	local frame: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = content,
	})
	New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Text = string.upper(zone.Name),
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextTitle",
		Parent = frame,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = zone.Tagline,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextMuted",
		Parent = frame,
	})
end

local function updateAll()
	for _, update in updaters do
		update()
	end
end

local function buildZone(zoneIndex: number)
	selectedZone = zoneIndex
	updaters = {}
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local zone = Zones[zoneIndex]
	panel:SetAccent(Color3.fromHex(zone.Primary))
	header(zoneIndex, 0)
	local order = 1
	for _, def in Modules.ForZone(zoneIndex) do
		moduleCard(def, order)
		order += 1
	end
	if zoneIndex == 1 then
		capacityCard("Power", order)
		order += 1
	elseif zoneIndex == GameConfig.Cooling.UnlockZone then
		capacityCard("Cooling", order)
		order += 1
	end
	local data = Store.Data()
	builtAtZone = if data then data.Zone else 0
	if data and zoneIndex == data.Zone and Zones[zoneIndex + 1] then
		unlockCard(zoneIndex + 1, order)
	end
	updateAll()
	-- Met en avant le module demandé (prompt dans le monde). Position calculée depuis la mise
	-- en page (en-tête 56 + cartes de 120, espacement 10), donc indépendante des UIScale.
	if focusModule then
		local def = Modules.Get(focusModule)
		local card = content:FindFirstChild(focusModule)
		if def and card and card:IsA("GuiObject") then
			content.CanvasPosition = Vector2.new(0, math.max(66 + (def.Slot - 1) * 130 - 10, 0))
			task.delay(Theme.Motion.Panel, function()
				Motion.Pop(card, 0.04)
			end)
		end
		focusModule = nil
	end
	for index, key in tabKeys do
		key:SetVariant(if index == zoneIndex then "Primary" else "Secondary")
	end
end

local function refreshTabs()
	local data = Store.Data()
	if not data then
		return
	end
	for index, key in tabKeys do
		local unlocked = index <= data.Zone
		key:SetEnabled(unlocked)
		key:SetText(if unlocked then Zones[index].Name else `🔒 {Zones[index].Component}`)
	end
end

function ComponentsPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "ComponentsPanel",
		Title = "AMÉLIORER",
		Subtitle = "Rends tes machines plus fortes = plus de Bits !",
		Size = UDim2.fromScale(0.82, 0.84),
		Parent = layer,
	})
	tabsList = New("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(0, 170, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel.Body,
	}, {
		Create.List(Enum.FillDirection.Vertical, 8),
	})
	for index, zone in Zones do
		local key = Keycap.new({
			Text = zone.Name,
			Variant = "Secondary",
			Size = UDim2.new(1, -6, 0, 50),
			LayoutOrder = index,
			Small = true,
			OnClick = function()
				buildZone(index)
			end,
			Parent = tabsList,
		})
		table.insert(tabKeys, key)
	end
	local right: Frame = New("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(186, 0),
		Size = UDim2.new(1, -186, 1, 0),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	})
	content = Widgets.Scroll(right, 10)

	Store.Changed:Connect(function()
		if panel:IsOpen() then
			refreshTabs()
			local data = Store.Data()
			-- Reconstruit l'onglet si une zone a été débloquée (ou après un Reboot).
			if data and (data.Zone ~= builtAtZone or selectedZone > data.Zone) then
				buildZone(math.min(selectedZone, data.Zone))
			else
				updateAll()
			end
		end
	end)
	Store.Ticked:Connect(function()
		if panel:IsOpen() then
			updateAll()
		end
	end)

	App.RegisterPanel("Components", {
		Panel = panel,
		OnOpen = function(arg: any)
			refreshTabs()
			local data = Store.Data()
			local zone = if data then data.Zone else 1
			if type(arg) == "number" then
				zone = math.clamp(arg, 1, zone)
			elseif type(arg) == "string" then
				local def = Modules.Get(arg)
				if def then
					zone = def.Zone
					focusModule = arg
				end
			end
			buildZone(zone)
		end,
	})
end

return ComponentsPanel
