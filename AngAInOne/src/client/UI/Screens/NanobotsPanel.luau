--!strict
--[[
	NanobotsPanel : collection (équiper / fusionner) et capsules (probabilités affichées).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Nanobots = require(Shared.Config.Nanobots)
local Zones = require(Shared.Config.Zones)
local GameConfig = require(Shared.Config.GameConfig)
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

local NanobotsPanel = {}

local panel: Panel.Panel
local tab = "Collection"
local tabKeys: { [string]: Keycap.Keycap } = {}
local body: Frame
local selectedUid: string? = nil

local function rarityColor(rarity: string): Color3
	return Color3.fromHex((Theme.Rarity :: any)[rarity] or Theme.Rarity.Common)
end

local function clear()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function buildCollection(state: any)
	local data = state.Data
	local owned = data.Nanobots.Owned
	local equipped = data.Nanobots.Equipped

	local top: Frame = New("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = body })
	New("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = `Équipés {#equipped}/{state.NanobotSlots}  ·  Inventaire {#owned}/{GameConfig.Nanobots.MaxInventory}  ·  Bonus Bits total : x{string.format(
			"%.2f",
			state.Bonus.Total
		)}`,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextMuted",
		Parent = top,
	})

	local grid: ScrollingFrame = New("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -110),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, {
		New("UIGridLayout", {
			CellSize = UDim2.fromOffset(118, 140),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	if #owned == 0 then
		New("TextLabel", {
			Size = UDim2.fromOffset(500, 40),
			BackgroundTransparency = 1,
			Text = "Aucun Nanobot pour l'instant. Ouvre une capsule !",
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextBody",
			Parent = grid,
		})
	end

	-- Tri : équipés d'abord, puis par rareté décroissante
	local rarityRank: { [string]: number } = {}
	for index, rarity in Nanobots.RarityOrder do
		rarityRank[rarity] = index
	end
	local list = table.clone(owned)
	table.sort(list, function(a: any, b: any): boolean
		local ea = table.find(equipped, a.Uid) ~= nil
		local eb = table.find(equipped, b.Uid) ~= nil
		if ea ~= eb then
			return ea
		end
		local da, db = Nanobots.ById[a.Id], Nanobots.ById[b.Id]
		local ra = if da then rarityRank[da.Rarity] else 0
		local rb = if db then rarityRank[db.Rarity] else 0
		if ra ~= rb then
			return ra > rb
		end
		return a.Uid < b.Uid
	end)

	local detailName: TextLabel
	local detailInfo: TextLabel
	local equipKey: Keycap.Keycap
	local fuseKey: Keycap.Keycap

	local function refreshDetail()
		local entry = nil
		for _, item in owned do
			if item.Uid == selectedUid then
				entry = item
			end
		end
		if not entry then
			detailName.Text = "Sélectionne un Nanobot"
			detailInfo.Text = "Les Nanobots équipés boostent ta production, tes Watts, ta chaleur ou ta vitesse."
			equipKey.Button.Visible = false
			fuseKey.Button.Visible = false
			return
		end
		local def = Nanobots.ById[entry.Id]
		if not def then
			return
		end
		local isEquipped = table.find(equipped, entry.Uid) ~= nil
		local copies = 0
		for _, item in owned do
			if item.Id == entry.Id and not item.Golden then
				copies += 1
			end
		end
		detailName.Text =
			`{def.Name}{if entry.Golden then " ★ doré" else ""}  ·  {Nanobots.RarityNames[def.Rarity]}`
		detailName.TextColor3 = rarityColor(def.Rarity)
		detailInfo.Text = Nanobots.BonusText(def, entry.Golden)
		equipKey.Button.Visible = true
		equipKey:SetText(if isEquipped then "RETIRER" else "ÉQUIPER")
		equipKey:SetVariant(if isEquipped then "Secondary" else "Primary")
		equipKey:SetEnabled(isEquipped or #equipped < state.NanobotSlots)
		fuseKey.Button.Visible = not entry.Golden
		fuseKey:SetText(`FUSIONNER {copies}/{GameConfig.Nanobots.FuseCount}`)
		fuseKey:SetEnabled(copies >= GameConfig.Nanobots.FuseCount)
	end

	for index, entry in list do
		local def = Nanobots.ById[entry.Id]
		if def then
			local color = rarityColor(def.Rarity)
			local isEquipped = table.find(equipped, entry.Uid) ~= nil
			local cell: TextButton = New("TextButton", {
				Name = entry.Uid,
				BackgroundTransparency = 0.3,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = index,
				Tag = { "GlassRaised", "RoundM" },
				Parent = grid,
			}, {
				New(
					"UIStroke",
					{ Color = color, Thickness = if selectedUid == entry.Uid then 2.5 else 1.2, Transparency = 0.15 }
				),
			})
			local halo: Frame = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 12),
				Size = UDim2.fromOffset(64, 64),
				BackgroundColor3 = Color3.fromHex(def.Color),
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				Tag = "RoundPill",
				Parent = cell,
			})
			local bot = Icon.new("Bot", 44, nil)
			bot.AnchorPoint = Vector2.new(0.5, 0.5)
			bot.Position = UDim2.fromScale(0.5, 0.5)
			bot.Parent = halo
			New("TextLabel", {
				Position = UDim2.fromOffset(6, 82),
				Size = UDim2.new(1, -12, 0, 20),
				BackgroundTransparency = 1,
				Text = def.Name,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Tag = "TextBody",
				Parent = cell,
			})
			New("TextLabel", {
				Position = UDim2.fromOffset(6, 104),
				Size = UDim2.new(1, -12, 0, 16),
				BackgroundTransparency = 1,
				Text = Nanobots.BonusText(def, entry.Golden),
				Tag = "TextCaption",
				Parent = cell,
			})
			if entry.Golden then
				local star = Icon.new("Star", 18, "CurrencyBits")
				star.Position = UDim2.fromOffset(8, 8)
				star.Parent = cell
			end
			if isEquipped then
				local check: Frame = New("Frame", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -6, 0, 6),
					Size = UDim2.fromOffset(22, 22),
					BorderSizePixel = 0,
					Tag = { "FillSuccess", "RoundPill" },
					Parent = cell,
				})
				local icon = Icon.new("Check", 16, "BgDeep")
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.Position = UDim2.fromScale(0.5, 0.5)
				icon.Parent = check
			end
			cell.Activated:Connect(function()
				selectedUid = entry.Uid
				for _, other in grid:GetChildren() do
					local stroke = other:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Thickness = if other.Name == selectedUid then 2.5 else 1.2
					end
				end
				refreshDetail()
			end)
		end
	end

	local detail: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Tag = { "GlassSunken", "RoundM" },
		Parent = body,
	})
	detailName = New("TextLabel", {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -380, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "DynHeading",
		TextColor3 = Style.Color("TextPrimary"),
		Parent = detail,
	})
	detailInfo = New("TextLabel", {
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -380, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Tag = "TextMuted",
		Parent = detail,
	})
	equipKey = Keycap.new({
		Text = "ÉQUIPER",
		Variant = "Primary",
		Size = UDim2.fromOffset(160, 48),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -186, 0.5, 0),
		Small = true,
		OnClick = function()
			if selectedUid then
				Net.Fire("EquipNanobot", selectedUid, not table.find(equipped, selectedUid))
			end
		end,
		Parent = detail,
	})
	fuseKey = Keycap.new({
		Text = "FUSIONNER",
		Variant = "Gold",
		Size = UDim2.fromOffset(166, 48),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Small = true,
		OnClick = function()
			for _, item in owned do
				if item.Uid == selectedUid then
					Net.Fire("FuseNanobots", item.Id)
				end
			end
		end,
		Parent = detail,
	})
	refreshDetail()
end

local function buildCapsules(state: any)
	local data = state.Data
	local scroll = Widgets.Scroll(body, 10)
	for index, capsule in Nanobots.Capsules do
		if capsule.Paid and not state.PaidRandomAllowed then
			continue
		end
		local locked = data.Zone < capsule.RequiredZone
		local card = Widgets.Card(UDim2.new(1, -4, 0, 104), scroll, index)
		local tile: Frame = New("Frame", {
			Position = UDim2.fromOffset(12, 14),
			Size = UDim2.fromOffset(76, 76),
			BorderSizePixel = 0,
			Tag = { if capsule.Currency == "Chips" then "FillCyan" else "FillViolet", "RoundL" },
			Parent = card,
		})
		local icon = Icon.new(if locked then "Lock" else "Gift", 42, "BgDeep")
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = tile
		New("TextLabel", {
			Position = UDim2.fromOffset(104, 12),
			Size = UDim2.new(1, -310, 0, 24),
			BackgroundTransparency = 1,
			Text = capsule.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextHeading",
			Parent = card,
		})
		local odds = {}
		for _, entry in Nanobots.OddsPercent(capsule.Id) do
			table.insert(
				odds,
				`{Nanobots.RarityNames[entry.rarity]} {string.format("%g", math.floor(entry.percent * 10 + 0.5) / 10)} %`
			)
		end
		New("TextLabel", {
			Position = UDim2.fromOffset(104, 38),
			Size = UDim2.new(1, -310, 0, 36),
			BackgroundTransparency = 1,
			Text = "Probabilités : " .. table.concat(odds, " · "),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Tag = "TextMuted",
			Parent = card,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(104, 76),
			Size = UDim2.new(1, -310, 0, 18),
			BackgroundTransparency = 1,
			Text = if locked
				then `Se débloque avec {Zones[capsule.RequiredZone].Name}`
				else "Contient 5 Nanobots de raretés différentes",
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextCaption",
			Parent = card,
		})
		local cost = state.CapsuleCosts[capsule.Id] or 0
		local affordable = if capsule.Currency == "Chips" then data.Chips >= cost else Store.Bits() >= cost
		Keycap.new({
			Text = `OUVRIR · {NumberFormat.Compact(cost)} {if capsule.Currency == "Chips" then "Chips" else "Bits"}`,
			Variant = if capsule.Currency == "Chips" then "Cyan" else "Primary",
			Size = UDim2.fromOffset(190, 52),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Small = true,
			OnClick = function()
				Net.Fire("OpenCapsule", capsule.Id)
			end,
			Parent = card,
		}):SetEnabled(not locked and affordable)
	end
end

local lastKey = ""

-- Signature de ce qui influence l'affichage : évite de tout reconstruire à chaque état.
local function signature(state: any): string
	local data = state.Data
	local parts =
		{ tab, tostring(data.Zone), tostring(data.Chips), tostring(#data.Nanobots.Owned), tostring(state.NanobotSlots) }
	for _, entry in data.Nanobots.Owned do
		table.insert(parts, entry.Uid .. (if entry.Golden then "g" else ""))
	end
	table.insert(parts, table.concat(data.Nanobots.Equipped, ","))
	if tab == "Capsules" then
		for _, capsule in Nanobots.Capsules do
			local cost = state.CapsuleCosts[capsule.Id] or 0
			local have = if capsule.Currency == "Chips" then data.Chips else Store.Bits()
			table.insert(parts, if have >= cost then "1" else "0")
		end
	end
	return table.concat(parts, "|")
end

local function rebuild(force: boolean?)
	local state = Store.State
	if not state or not panel:IsOpen() then
		return
	end
	local key = signature(state)
	if key == lastKey and not force then
		return
	end
	lastKey = key
	clear()
	for name, tabKey in tabKeys do
		tabKey:SetVariant(if name == tab then "Primary" else "Secondary")
	end
	if tab == "Collection" then
		buildCollection(state)
	else
		buildCapsules(state)
	end
end

function NanobotsPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "NanobotsPanel",
		Title = "NANOBOTS",
		Subtitle = "Tes compagnons de silicium",
		Size = UDim2.fromScale(0.8, 0.84),
		Parent = layer,
		Accent = Style.Color("AccentViolet"),
	})
	local tabs: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8),
	})
	for index, name in { "Collection", "Capsules" } do
		tabKeys[name] = Keycap.new({
			Text = name,
			Variant = "Secondary",
			Size = UDim2.fromOffset(170, 44),
			LayoutOrder = index,
			Small = true,
			OnClick = function()
				tab = name
				rebuild(true)
			end,
			Parent = tabs,
		})
	end
	body = New("Frame", {
		Name = "TabBody",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	})
	Store.Changed:Connect(function()
		rebuild(false)
	end)
	Store.Ticked:Connect(function()
		if tab == "Capsules" then
			rebuild(false)
		end
	end)
	App.RegisterPanel("Nanobots", {
		Panel = panel,
		OnOpen = function(arg: any)
			if arg == "Capsules" or arg == "Collection" then
				tab = arg
			end
			task.defer(rebuild, true)
		end,
	})
end

return NanobotsPanel
