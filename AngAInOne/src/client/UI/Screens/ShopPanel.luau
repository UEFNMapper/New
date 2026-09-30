--!strict
--[[
	ShopPanel : Game Passes, Chips et boosts (Developer Products).
	Les articles dont l'ID vaut 0 (pas encore créés dans le Creator Dashboard) sont masqués.
	Aucune pression artificielle : pas de faux compte à rebours, prix clairs en Robux.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Panel = require(script.Parent.Parent.Components.Panel)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Icon = require(script.Parent.Parent.Components.Icon)
local App = require(script.Parent.Parent.App)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)

local New = Create.New

local ShopPanel = {}

local panel: Panel.Panel
local tab = "Passes"
local tabKeys: { [string]: Keycap.Keycap } = {}
local scroll: ScrollingFrame
local lastKey = ""

local TABS = {
	{ Id = "Passes", Text = "Pass" },
	{ Id = "Chips", Text = "Chips" },
	{ Id = "Boosts", Text = "Boosts" },
}

local function item(
	order: number,
	iconKind: string,
	iconColor: string,
	name: string,
	description: string,
	price: number,
	owned: boolean,
	onBuy: () -> ()
)
	local card = Widgets.Card(UDim2.new(1, -4, 0, 88), scroll, order)
	local tile: Frame = New("Frame", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(64, 64),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Tag = { "GlassSunken", "RoundM" },
		Parent = card,
	})
	local icon = Icon.new(iconKind, 40, iconColor)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = tile
	New("TextLabel", {
		Position = UDim2.fromOffset(90, 12),
		Size = UDim2.new(1, -290, 0, 24),
		BackgroundTransparency = 1,
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(90, 38),
		Size = UDim2.new(1, -290, 0, 40),
		BackgroundTransparency = 1,
		Text = description,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Tag = "TextMuted",
		Parent = card,
	})
	local key = Keycap.new({
		Text = if owned then "POSSÉDÉ" else `R$ {price}`,
		Variant = if owned then "Secondary" else "Gold",
		Size = UDim2.fromOffset(170, 52),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Small = true,
		OnClick = onBuy,
		Parent = card,
	})
	key:SetEnabled(not owned)
end

local function emptyNotice(order: number)
	local card = Widgets.Card(UDim2.new(1, -4, 0, 90), scroll, order)
	New("TextLabel", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 1, 0),
		BackgroundTransparency = 1,
		Text = if RunService:IsStudio()
			then "Studio : aucun article configuré. Crée tes pass/produits dans le Creator Dashboard et colle leurs IDs dans src/shared/Config/Products.luau."
			else "La boutique ouvre très bientôt !",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextBody",
		Parent = card,
	})
end

local KIND_ICON: { [string]: { string } } = {
	Bits = { "Bits", "CurrencyBits" },
	Chips = { "Chips", "CurrencyChips" },
	ServerBoost = { "Bolt", "BrandAnga" },
	SkipDownload = { "Download", "AccentCyan" },
	RebootBoost = { "Power", "AccentViolet" },
	StarterPack = { "Gift", "BrandAnga" },
}

local PASS_ICON: { [string]: string } = {
	DoubleBits = "Bits",
	VIP = "Star",
	AutoCollect = "Download",
	ExtraNanobots = "Bot",
	OverclockPro = "Bolt",
	OfflineMax = "Power",
	RgbStudio = "Heart",
}

local function rebuild(force: boolean?)
	local state = Store.State
	if not state or not panel:IsOpen() then
		return
	end
	local owned = {}
	for key in state.Passes do
		table.insert(owned, key)
	end
	table.sort(owned)
	local key = `{tab}|{table.concat(owned, ",")}|{state.Data.StarterPackBought}`
	if key == lastKey and not force then
		return
	end
	lastKey = key
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for name, tabKey in tabKeys do
		tabKey:SetVariant(if name == tab then "Primary" else "Secondary")
	end
	local player = Players.LocalPlayer
	local count = 0
	if tab == "Passes" then
		for _, pass in Products.Passes do
			if pass.Id ~= 0 then
				count += 1
				item(
					pass.Order,
					PASS_ICON[pass.Key] or "Star",
					"CurrencyBits",
					pass.Name,
					pass.Description,
					pass.Price,
					state.Passes[pass.Key] == true,
					function()
						MarketplaceService:PromptGamePassPurchase(player, pass.Id)
					end
				)
			end
		end
	else
		for _, product in Products.Products do
			local isChips = product.Kind == "Chips"
			local inTab = if tab == "Chips" then isChips else not isChips
			local hidden = product.Id == 0 or (product.OneTime and state.Data.StarterPackBought)
			if inTab and not hidden then
				count += 1
				local visual = KIND_ICON[product.Kind] or { "Gift", "TextPrimary" }
				item(
					product.Order,
					visual[1],
					visual[2],
					product.Name,
					product.Description,
					product.Price,
					false,
					function()
						MarketplaceService:PromptProductPurchase(player, product.Id)
					end
				)
			end
		end
	end
	if count == 0 then
		emptyNotice(1)
	end
end

function ShopPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "ShopPanel",
		Title = "BOUTIQUE",
		Subtitle = "Soutiens AngAInOne et booste ton PC",
		Size = UDim2.fromScale(0.78, 0.84),
		Parent = layer,
		Accent = Style.Color("CurrencyBits"),
	})
	local tabs: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8),
	})
	for index, info in TABS do
		tabKeys[info.Id] = Keycap.new({
			Text = info.Text,
			Variant = "Secondary",
			Size = UDim2.fromOffset(150, 44),
			LayoutOrder = index,
			Small = true,
			OnClick = function()
				tab = info.Id
				rebuild(true)
			end,
			Parent = tabs,
		})
	end
	local holder: Frame = New("Frame", {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	})
	scroll = Widgets.Scroll(holder, 10)
	Store.Changed:Connect(function()
		rebuild(false)
	end)
	App.RegisterPanel("Shop", {
		Panel = panel,
		OnOpen = function(arg: any)
			if arg == "Passes" or arg == "Chips" or arg == "Boosts" then
				tab = arg
			end
			task.defer(rebuild, true)
		end,
	})
end

return ShopPanel
