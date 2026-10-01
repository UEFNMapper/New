--!strict
--[[
	ShopPanel : 3 onglets simples.
	- Traînées  : achetées avec des Bits (ramassés dans la tour), équipables
	- Effets    : effets de mort, idem
	- Robux     : passes (VIP, bottes, puce) et produits (passer l'étape, bouclier, Bits)
	Les articles Robux dont l'ID vaut 0 (pas encore créés) sont masqués. Aucune pression :
	pas de faux compte à rebours, prix clairs.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local Cosmetics = require(Shared.Config.Cosmetics)
local Tower = require(Shared.Config.Tower)
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

local ShopPanel = {}

local panel: Panel.Panel
local tab = "Trail"
local scroll: ScrollingFrame
local lastKey = ""

local TABS = {
	{ Id = "Trail", Text = "Traînées", Icon = "Bolt" },
	{ Id = "DeathFx", Text = "Effets", Icon = "Star" },
	{ Id = "Robux", Text = "Robux", Icon = "Chips" },
}

type Visual = { Kind: "Icon", Icon: string, Color: string } | { Kind: "Swatch", Colors: { string } }

local function tileFor(card: Frame, visual: Visual)
	local tile: Frame = New("Frame", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(64, 64),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Tag = { "GlassSunken", "RoundM" },
		Parent = card,
	})
	if visual.Kind == "Icon" then
		local icon = Icon.new(visual.Icon, 40, visual.Color)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = tile
	else
		-- Aperçu des couleurs : une bande dégradée
		local colors = visual.Colors
		local swatch: Frame = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = if #colors > 0 then Color3.fromHex(colors[1]) else Style.Color("SurfaceSunken"),
			BorderSizePixel = 0,
			Tag = "RoundPill",
			Parent = tile,
		})
		if #colors > 1 then
			local points = {}
			for index, hex in colors do
				table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), Color3.fromHex(hex)))
			end
			New("UIGradient", { Color = ColorSequence.new(points), Rotation = 45, Parent = swatch })
			swatch.BackgroundColor3 = Style.Color("TextPrimary")
		end
	end
end

local function item(
	order: number,
	visual: Visual,
	name: string,
	description: string,
	buttonText: string,
	variant: Keycap.Variant,
	enabled: boolean,
	onClick: () -> ()
)
	local card = Widgets.Card(UDim2.new(1, -4, 0, 88), scroll, order)
	tileFor(card, visual)
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
		Text = buttonText,
		Variant = variant,
		Size = UDim2.fromOffset(170, 52),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Small = true,
		OnClick = onClick,
		Parent = card,
	})
	key:SetEnabled(enabled)
end

local function notice(order: number, text: string)
	local card = Widgets.Card(UDim2.new(1, -4, 0, 70), scroll, order)
	New("TextLabel", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextBody",
		Parent = card,
	})
end

local function owns(state: any, def: Cosmetics.CosmeticDef): boolean
	if def.Source == "VIP" then
		return state.Passes.VIP == true
	end
	return (def.Price == 0 and def.Source == nil) or table.find(state.Data.Cosmetics.Owned, def.Id) ~= nil
end

local function buildCosmetics(state: any, kind: string)
	local data = state.Data
	local equipped = if kind == "Trail" then data.Cosmetics.Trail else data.Cosmetics.DeathFx
	local list = {}
	for _, def in Cosmetics.List do
		if def.Kind == kind then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	for _, def in list do
		local have = owns(state, def)
		local text: string, variant: Keycap.Variant, enabled: boolean
		if def.Id == equipped then
			text, variant, enabled = "ÉQUIPÉ ✓", "Success", false
		elseif have then
			text, variant, enabled = "ÉQUIPER", "Primary", true
		elseif def.Source == "VIP" then
			text, variant, enabled = "Pass VIP", "Secondary", false
		elseif def.Source == "Daily" then
			text, variant, enabled = "Jour 7 🎁", "Secondary", false
		elseif def.Source == "Usb" then
			local found = 0
			for _ in data.UsbKeys do
				found += 1
			end
			text, variant, enabled = `🔑 {found}/{Tower.WORLD_COUNT * Tower.USB_KEYS_PER_WORLD}`, "Secondary", false
		else
			text, variant, enabled = `{NumberFormat.Compact(def.Price)} Bits`, "Gold", data.Bits >= def.Price
		end
		local description = if def.Source == "VIP"
			then "Offerte avec le pass VIP."
			elseif def.Source == "Daily" then "Cadeau du 7ᵉ jour du calendrier."
			elseif def.Source == "Usb" then "Trouve TOUTES les clés USB dorées cachées dans la tour !"
			elseif kind == "Trail" then "Une traînée lumineuse derrière toi."
			else "L'effet quand un piège t'attrape."
		item(
			def.Order,
			{ Kind = "Swatch", Colors = def.Colors },
			def.Name,
			description,
			text,
			variant,
			enabled,
			function()
				if have then
					Net.Fire("EquipCosmetic", def.Id)
				else
					Net.Fire("BuyCosmetic", def.Id)
				end
			end
		)
	end
end

local PASS_ICON: { [string]: string } = { VIP = "Star", LowGravity = "Bolt", SpeedChip = "Cpu" }
local PRODUCT_ICON: { [string]: { string } } = {
	Skip = { "Star", "CurrencyBits" },
	Shield = { "Heart", "AccentCyan" },
	Bits = { "Bits", "CurrencyBits" },
}

local function buildRobux(state: any)
	local player = Players.LocalPlayer
	local count = 0
	for _, pass in Products.Passes do
		if pass.Id ~= 0 then
			count += 1
			local have = state.Passes[pass.Key] == true
			item(
				pass.Order,
				{ Kind = "Icon", Icon = PASS_ICON[pass.Key] or "Star", Color = "CurrencyBits" },
				pass.Name,
				pass.Description,
				if have then "POSSÉDÉ" else `R$ {pass.Price}`,
				if have then "Secondary" else "Gold",
				not have,
				function()
					MarketplaceService:PromptGamePassPurchase(player, pass.Id)
				end
			)
		end
	end
	for _, product in Products.Products do
		if product.Id ~= 0 then
			count += 1
			local visual = PRODUCT_ICON[product.Kind] or { "Gift", "TextPrimary" }
			item(
				10 + product.Order,
				{ Kind = "Icon", Icon = visual[1], Color = visual[2] },
				product.Name,
				product.Description,
				`R$ {product.Price}`,
				"Gold",
				true,
				function()
					MarketplaceService:PromptProductPurchase(player, product.Id)
				end
			)
		end
	end
	if count == 0 then
		notice(
			1,
			if RunService:IsStudio()
				then "Studio : crée tes pass/produits dans le Creator Dashboard et colle leurs IDs dans src/shared/Config/Products.luau."
				else "La boutique Robux ouvre très bientôt !"
		)
	end
end

local function rebuild(force: boolean?)
	local state = Store.State
	if not state or not panel:IsOpen() then
		return
	end
	local data = state.Data
	local passes = {}
	for key in state.Passes do
		table.insert(passes, key)
	end
	table.sort(passes)
	local key =
		`{tab}|{data.Bits}|{table.concat(data.Cosmetics.Owned, ",")}|{data.Cosmetics.Trail}|{data.Cosmetics.DeathFx}|{table.concat(
			passes,
			","
		)}`
	if key == lastKey and not force then
		return
	end
	lastKey = key
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	panel:SetPage(tab)
	if tab == "Robux" then
		buildRobux(state)
	else
		buildCosmetics(state, tab)
	end
end

function ShopPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "ShopPanel",
		Title = "Boutique",
		Subtitle = "Dépense tes Bits pour avoir du style !",
		Size = UDim2.fromScale(0.8, 0.86),
		Parent = layer,
		Accent = Style.Color("CurrencyBits"),
		Pages = TABS,
		OnPage = function(id: string)
			tab = id
			rebuild(true)
		end,
	})
	scroll = Widgets.Scroll(panel.Body, 10)
	Store.Changed:Connect(function()
		rebuild(false)
	end)
	App.RegisterPanel("Shop", {
		Panel = panel,
		OnOpen = function(arg: any)
			if arg == "Trail" or arg == "DeathFx" or arg == "Robux" then
				tab = arg
			end
			task.defer(rebuild, true)
		end,
	})
end

return ShopPanel
