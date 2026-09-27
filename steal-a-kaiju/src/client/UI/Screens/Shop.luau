--!nonstrict
-- Boutique « KAIJU MART » : passes, gemmes, cash, boosts & potions, améliorations.
-- Chaque onglet est reconstruit à la sélection (apparition en cascade) ; les
-- changements d'état ne font que rafraîchir les cartes via des « updaters ».

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Theme = require(Shared.Config.Theme)
local Economy = require(Shared.Config.Economy)
local Levels = require(Shared.Config.Levels)
local Rarities = require(Shared.Config.Rarities)
local Events = require(Shared.Config.Events)
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Logic.Format)
local Roll = require(Shared.Logic.Roll)

local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)
local Remote = require(script.Parent.Parent.Parent.Controllers.Remote)
local Audio = require(script.Parent.Parent.Parent.Controllers.Audio)
local UIRegistry = require(script.Parent.Parent.Parent.Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts

local Shop = {}

local TABS = {
	{ Id = "Passes", Text = "PASSES", Icon = "🎫", Width = 150 },
	{ Id = "Gems", Text = "GEMS", Icon = "💎", Width = 140 },
	{ Id = "Cash", Text = "CASH", Icon = "💵", Width = 140 },
	{ Id = "Boosts", Text = "BOOSTS", Icon = "⚡", Width = 150 },
	{ Id = "Upgrades", Text = "UPGRADES", Icon = "⬆️", Width = 170 },
}

local POTION_COLORS = { Luck = "Radioactive", Growth = "Gold", Cash = "Magma" }
local STARTER_ITEMS = {
	{ Text = "🥚 Legendary Egg", Color = Color3.fromRGB(255, 176, 32) },
	{ Text = "💎 150 Gems", Color = Color3.fromRGB(60, 160, 255) },
	{ Text = "🍀 2 Luck Potions", Color = Color3.fromRGB(40, 170, 60) },
}

local window
local content: Frame
local tabBar: Frame
local selectTab: (string) -> ()
local scroll: CanvasGroup? = nil
local currentTab = "Passes"
local updaters: { () -> () } = {}
local tickers: { () -> () } = {}
local popCount = 0
local loopToken = 0
local busy: { [string]: any } = {}
local priceCache: { [string]: number } = {}

----------------------------------------------------------------------------
-- Aides locales
----------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function restricted(): boolean
	return State.Get("RandomRestricted") == true
end

local function allowed(item: any): boolean
	return not (item.Random == true and restricted())
end

local function robux(key: string, fallback: number): string
	return "R$ " .. Format.Comma(priceCache[key] or fallback)
end

-- Apparition élastique en cascade (l'élément doit être centré sur son ancre).
local function popIn(inst: GuiObject)
	popCount += 1
	local s = Kit.ScaleOf(inst)
	s.Scale = 0
	task.delay(0.04 + popCount * 0.045, function()
		if inst.Parent then
			Kit.Pop(inst, 0.25, 0.5)
		end
	end)
end

local function cell(parent: Instance, size: UDim2, order: number): Frame
	return Kit.new("Frame", { Name = "Cell", Size = size, BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
end

-- Carte BD centrée dans sa cellule.
local function card(parent: Instance, props: { [string]: any }): (Frame, Frame)
	return Kit.Panel({
		Name = props.Name or "Card",
		Size = props.Size or UDim2.new(1, -12, 1, -12),
		Position = UDim2.new(0.5, -3, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = props.Rotation or 0,
		Gradient = props.Gradient,
		Clip = props.Clip,
		Parent = parent,
	})
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	return Kit.Text(props)
end

-- Bouton dans un emplacement : l'emplacement suit le layout, le « souffle »
-- et le survol partent du centre.
local function slotButton(parent: Instance, props: { [string]: any }): (Frame, TextButton, Frame)
	local slot = Kit.new("Frame", {
		Name = (props.Name or "Button") .. "Slot",
		Size = props.Size or UDim2.fromOffset(160, 50),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 5,
		Parent = parent,
	})
	local breather = Kit.new("Frame", {
		Name = "Breather",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 5,
		Parent = slot,
	})
	local bp = table.clone(props)
	bp.Size = UDim2.new(1, 0, 1, -6)
	bp.Position = UDim2.new(0.5, 0, 0.5, -3)
	bp.AnchorPoint = Vector2.new(0.5, 0.5)
	bp.LayoutOrder = nil
	bp.Parent = breather
	local button = Kit.Button(bp)
	return slot, button, breather
end

local function setBreathe(inst: GuiObject, on: boolean)
	if (inst:GetAttribute("Breathing") == true) == on then
		return
	end
	inst:SetAttribute("Breathing", on)
	if on then
		Kit.Breathe(inst, 0.06, 0.7)
	else
		Kit.Tween(Kit.ScaleOf(inst), 0.2, { Scale = 1 })
	end
end

local function styleButton(button: GuiObject, color: string, disabled: boolean?)
	Kit.SetDisabled(button, false)
	Kit.SetButtonColor(button, color)
	if disabled then
		Kit.SetDisabled(button, true)
	end
end

local function chip(parent: Instance, props: { [string]: any }): Frame
	props.Parent = parent
	return Kit.Chip(props)
end

-- Titre de section : ruban incliné + rayures de danger.
local function section(parent: Instance, title: string, color: string, order: number): Frame
	local row = cell(parent, UDim2.new(1, 0, 0, 50), order)
	Kit.Hazard({ Size = UDim2.new(1, -40, 0, 10), Position = UDim2.new(0, 30, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = row })
	Kit.Ribbon({
		Text = title,
		Color = color,
		Size = UDim2.fromOffset(math.max(200, #title * 17 + 40), 42),
		Position = UDim2.fromOffset(8, 2),
		AnchorPoint = Vector2.zero,
		Rotation = -2,
		ZIndex = 4,
		Parent = row,
	})
	return row
end

local function grid(parent: Instance, cellSize: UDim2, order: number): Frame
	local g = Kit.new("Frame", {
		Name = "Grid",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Grid(cellSize, 14).Parent = g
	return g
end

-- Bandeau coloré avec icône en haut d'une carte.
local function band(body: Frame, color: Color3, icon: string, height: number): Frame
	local b = Kit.new("Frame", {
		Name = "Band",
		Size = UDim2.new(1, -14, 0, height),
		Position = UDim2.fromOffset(7, 7),
		BackgroundColor3 = C.White,
		ZIndex = 2,
		ClipsDescendants = true,
		Parent = body,
	}, { Kit.Corner(10), Kit.Stroke(3), Kit.Gradient({ color:Lerp(C.White, 0.35), color:Lerp(C.Ink, 0.12) }) })
	-- points de trame BD
	for i = 0, 5 do
		Kit.new("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(0.08 + i * 0.17, 0, 0.18 + (i % 2) * 0.55, 0),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.78,
			ZIndex = 2,
			Parent = b,
		}, { Kit.Round() })
	end
	local iconLabel = text(b, {
		Name = "Icon",
		Size = UDim2.new(1, 0, 0.9, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = icon,
		FontFace = F.Body,
		Stroke = false,
		MaxTextSize = 64,
		ZIndex = 3,
	})
	Kit.Wobble(iconLabel, 5, 1.6 + math.random() * 0.6)
	return b
end

local function title(parent: Instance, str: string, y: number, h: number?, color: Color3?): TextLabel
	return text(parent, {
		Name = "Name",
		Size = UDim2.new(1, -16, 0, h or 28),
		Position = UDim2.fromOffset(8, y),
		Text = str,
		TextColor3 = color or C.White,
		Stroke = 2.5,
		MaxTextSize = 26,
		ZIndex = 3,
	})
end

local function body(parent: Instance, str: string, y: number, h: number, color: Color3?): TextLabel
	return text(parent, {
		Name = "Desc",
		Size = UDim2.new(1, -20, 0, h),
		Position = UDim2.fromOffset(10, y),
		Text = str,
		FontFace = F.Body,
		TextColor3 = color or C.InkSoft,
		TextWrapped = true,
		Stroke = false,
		MaxTextSize = 17,
		ZIndex = 3,
	})
end

-- Achat Robux (pass ou produit).
local function buyRobux(kind: string, key: string)
	if busy[key] then
		return
	end
	busy[key] = true
	local r = Remote.Call("Buy", { Kind = kind, Key = key })
	busy[key] = nil
	if r.ok and r.msg then
		Audio.Play("purchase")
		UIRegistry.Toast(r.msg, "Good")
	end
end

local function emptyState(parent: Instance, msg: string, order: number)
	local c = cell(parent, UDim2.new(1, 0, 0, 180), order)
	local box, b = card(c, { Rotation = -1 })
	text(b, { Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 30), Text = "🌍", FontFace = F.Body, Stroke = false, MaxTextSize = 60 })
	text(b, { Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 104), Text = msg, TextColor3 = C.Ink, Stroke = false, MaxTextSize = 28 })
	popIn(box)
end

-- Rayons « aura » derrière une carte (la cellule passe sous ses voisines).
local function aura(c: Frame, color: Color3, size: number)
	c.ZIndex = 0
	Kit.Starburst({ Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(0.5, 0.5), Color = color, Transparency = 0.35, ZIndex = 0, Parent = c })
end

-- Œuf BD dessiné en frames : coque, taches, reflet.
local function drawEgg(parent: Instance, color: Color3, height: number, pos: UDim2): Frame
	local egg = Kit.new("Frame", {
		Name = "Egg",
		Size = UDim2.fromOffset(math.floor(height * 0.78), height),
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 4,
		Parent = parent,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Kit.Stroke(4),
		Kit.Gradient({ color:Lerp(C.White, 0.45), color:Lerp(C.Ink, 0.1) }),
	})
	for i, spot in { { 0.3, 0.55, 0.2 }, { 0.68, 0.4, 0.16 }, { 0.55, 0.75, 0.13 } } do
		Kit.new("Frame", {
			Name = "Spot" .. i,
			Size = UDim2.fromScale(spot[3] * 1.3, spot[3]),
			Position = UDim2.fromScale(spot[1], spot[2]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color:Lerp(C.White, 0.7),
			ZIndex = 5,
			Parent = egg,
		}, { Kit.Round(), Kit.Stroke(2) })
	end
	Kit.new("Frame", {
		Size = UDim2.fromScale(0.22, 0.14),
		Position = UDim2.fromScale(0.3, 0.2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -30,
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.25,
		ZIndex = 5,
		Parent = egg,
	}, { Kit.Round() })
	text(egg, {
		Size = UDim2.fromScale(0.5, 0.3),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "?",
		Stroke = 2.5,
		MaxTextSize = 40,
		ZIndex = 6,
	})
	return egg
end

----------------------------------------------------------------------------
-- Onglet PASSES
----------------------------------------------------------------------------

local function passOwned(key: string): boolean
	local passes = State.Get("Passes")
	return passes ~= nil and passes[key] == true
end

local function featuredPass(parent: Instance, pass: any, order: number, index: number)
	local c = cell(parent, UDim2.new(0.5, -8, 1, 0), order)
	local accent = pass.Color
	local box, b = card(c, {
		Rotation = if index % 2 == 1 then -1.5 else 1.2,
		Gradient = { accent:Lerp(C.White, 0.3), accent:Lerp(C.Ink, 0.25) },
	})
	-- (pas de ClipsDescendants : la fenêtre est inclinée, donc rayons à la taille de la carte)
	Kit.Starburst({ Size = UDim2.fromOffset(190, 190), Position = UDim2.new(0.21, 0, 0.5, 0), Color = C.White, Transparency = 0.6, Rays = 12, Period = 14, Parent = b })
	local icon = text(b, {
		Size = UDim2.fromOffset(120, 120),
		Position = UDim2.new(0.21, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = pass.Icon,
		FontFace = F.Body,
		Stroke = false,
		MaxTextSize = 96,
		ZIndex = 3,
	})
	Kit.Wobble(icon, 7, 1.4)
	local tag = chip(b, {
		Text = if pass.Key == "VIP" then "★ FEATURED" else "★ BEST SELLER",
		Color = C.Red,
		Size = UDim2.fromOffset(150, 28),
		Position = UDim2.fromOffset(10, 10),
		ZIndex = 4,
	})
	tag.Rotation = -8
	text(b, {
		Size = UDim2.new(0.56, 0, 0, 46),
		Position = UDim2.new(0.42, 0, 0, 16),
		Text = string.upper(pass.Name),
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 3,
		MaxTextSize = 42,
		ZIndex = 3,
	})
	text(b, {
		Size = UDim2.new(0.55, 0, 0, 58),
		Position = UDim2.new(0.42, 0, 0, 64),
		Text = pass.Description,
		FontFace = F.Body,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Stroke = 1.8,
		MaxTextSize = 18,
		ZIndex = 3,
	})
	Kit.Hazard({ Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), ZIndex = 2, Parent = b })
	local slot, button, breather = slotButton(b, {
		Name = "Buy",
		Text = robux(pass.Key, pass.Robux),
		Color = if pass.Key == "VIP" then "Pink" else "Radioactive",
		Size = UDim2.fromOffset(190, 58),
		Position = UDim2.new(0.42, 0, 1, -76),
		MaxTextSize = 28,
		ZIndex = 6,
		OnClick = function()
			buyRobux("Pass", pass.Key)
		end,
	})
	local owned = chip(b, {
		Text = "OWNED ✓",
		Color = C.RadioactiveDark,
		Size = UDim2.fromOffset(170, 40),
		Position = UDim2.new(0.42, 0, 1, -70),
		ZIndex = 6,
	})
	local was: boolean? = nil
	table.insert(updaters, function()
		local has = passOwned(pass.Key)
		slot.Visible = not has
		owned.Visible = has
		setBreathe(breather, not has)
		Kit.SetButtonText(button, robux(pass.Key, pass.Robux))
		if was == false and has then
			Kit.Punch(box, 0.12)
			Audio.Play("purchase")
		end
		was = has
	end)
	popIn(box)
end

local function passCard(parent: Instance, pass: any, order: number)
	local c = cell(parent, UDim2.fromOffset(190, 244), order)
	local box, b = card(c, { Rotation = if order % 2 == 0 then 1.2 else -1.2 })
	band(b, pass.Color, pass.Icon, 84)
	title(b, pass.Name, 98, 28, C.White)
	body(b, pass.Description, 128, 50)
	local slot, button = slotButton(b, {
		Name = "Buy",
		Text = robux(pass.Key, pass.Robux),
		Color = "Radioactive",
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.new(0.5, 0, 1, -60),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 24,
		OnClick = function()
			buyRobux("Pass", pass.Key)
		end,
	})
	local owned = chip(b, {
		Text = "OWNED ✓",
		Color = C.RadioactiveDark,
		Size = UDim2.new(1, -40, 0, 36),
		Position = UDim2.new(0.5, 0, 1, -54),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 6,
	})
	local was: boolean? = nil
	table.insert(updaters, function()
		local has = passOwned(pass.Key)
		slot.Visible = not has
		owned.Visible = has
		Kit.SetButtonText(button, robux(pass.Key, pass.Robux))
		if was == false and has then
			Kit.Punch(box, 0.15)
		end
		was = has
	end)
	popIn(box)
end

local function buildPasses(list: ScrollingFrame)
	local featured = Kit.new("Frame", { Name = "Featured", Size = UDim2.new(1, 0, 0, 218), BackgroundTransparency = 1, LayoutOrder = 1, Parent = list }, {
		Kit.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local i = 0
	for _, pass in Monetization.Passes do
		if pass.Featured and allowed(pass) then
			i += 1
			featuredPass(featured, pass, i, i)
		end
	end
	section(list, "ALL PASSES", "Purple", 2)
	local g = grid(list, UDim2.fromOffset(190, 244), 3)
	local n = 0
	for _, pass in Monetization.Passes do
		if not pass.Featured and allowed(pass) then
			n += 1
			passCard(g, pass, n)
		end
	end
end

----------------------------------------------------------------------------
-- Onglets GEMS et CASH
----------------------------------------------------------------------------

local function gemCard(parent: Instance, product: any, order: number, total: number)
	local c = cell(parent, UDim2.fromOffset(190, 268), order)
	local best = order == total
	if best then
		aura(c, C.Gold, 330)
	end
	local box, b = card(c, { Rotation = if order % 2 == 0 then 1.4 else -1.4 })
	local b2 = band(b, product.Color, string.rep("💎", math.min(order, 3)), 92)
	local iconLabel = b2:FindFirstChild("Icon") :: TextLabel?
	if iconLabel then
		iconLabel.Size = UDim2.new(1, -10, 0.4 + order * 0.12, 0)
	end
	local amount = text(b, {
		Size = UDim2.new(1, -16, 0, 50),
		Position = UDim2.fromOffset(8, 104),
		Text = Format.Comma(product.Amount or 0),
		FontFace = F.Impact,
		TextColor3 = C.Gem,
		Stroke = 3,
		MaxTextSize = 50,
		ZIndex = 3,
	})
	text(b, { Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 152), Text = "GEMS", TextColor3 = C.Ink, Stroke = false, MaxTextSize = 20, ZIndex = 3 })
	if product.Description ~= "" then
		local tag = chip(b, {
			Text = product.Description,
			Color = if best then C.Red else C.Purple,
			Size = UDim2.new(1, -30, 0, 26),
			Position = UDim2.new(0.5, 0, 0, 178),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 4,
		})
		tag.Rotation = -3
	end
	local _, button, breather = slotButton(b, {
		Name = "Buy",
		Text = robux(product.Key, product.Robux),
		Color = "Cyan",
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.new(0.5, 0, 1, -60),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 24,
		OnClick = function()
			buyRobux("Product", product.Key)
		end,
	})
	if best then
		setBreathe(breather, true)
	end
	table.insert(updaters, function()
		Kit.SetButtonText(button, robux(product.Key, product.Robux))
	end)
	popIn(box)
	task.delay(0.3 + order * 0.08, function()
		if amount.Parent then
			Kit.Punch(amount, 0.3)
		end
	end)
end

local function buildGems(list: ScrollingFrame)
	local items = {}
	for _, p in Monetization.Products do
		if p.Category == "Gems" and allowed(p) then
			table.insert(items, p)
		end
	end
	if #items == 0 then
		emptyState(list, "Gem packs aren't available in your region", 1)
		return
	end
	section(list, "GEM PACKS", "Cyan", 1)
	local g = grid(list, UDim2.fromOffset(190, 268), 2)
	for i, p in items do
		gemCard(g, p, i, #items)
	end
	text(list, {
		Size = UDim2.new(1, -20, 0, 26),
		LayoutOrder = 3,
		Text = "Gems buy potions, spins and more!",
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		Stroke = false,
		MaxTextSize = 18,
	})
end

local function cashAmount(product: any): number
	local income = State.Get("Income") or 0
	return math.max(1000, math.floor(income * (product.Amount or 600)))
end

local function cashCard(parent: Instance, product: any, order: number)
	local c = cell(parent, UDim2.fromOffset(250, 290), order)
	if order == 3 then
		aura(c, C.Cash, 380)
	end
	local box, b = card(c, { Rotation = if order == 2 then 0.8 else -1.2 })
	band(b, product.Color, product.Icon, 100)
	title(b, string.upper(product.Name), 112, 28, C.White)
	local amount = text(b, {
		Name = "Amount",
		Size = UDim2.new(1, -16, 0, 50),
		Position = UDim2.fromOffset(8, 142),
		Text = Format.Cash(cashAmount(product)),
		FontFace = F.Impact,
		TextColor3 = C.Cash,
		Stroke = 3,
		MaxTextSize = 50,
		ZIndex = 3,
	})
	body(b, product.Description, 192, 24)
	slotButton(b, {
		Name = "Buy",
		Text = robux(product.Key, product.Robux),
		Color = "Radioactive",
		Size = UDim2.new(1, -30, 0, 54),
		Position = UDim2.new(0.5, 0, 1, -64),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 26,
		OnClick = function()
			buyRobux("Product", product.Key)
		end,
	})
	local last = cashAmount(product)
	table.insert(updaters, function()
		local v = cashAmount(product)
		if v ~= last then
			last = v
			Kit.CountTo(amount, v, Format.Cash, 0.6)
			Kit.Punch(amount, 0.12)
		end
	end)
	popIn(box)
end

local function buildCash(list: ScrollingFrame)
	local items = {}
	for _, p in Monetization.Products do
		if p.Category == "Cash" and allowed(p) then
			table.insert(items, p)
		end
	end
	if #items == 0 then
		emptyState(list, "Cash packs aren't available in your region", 1)
		return
	end
	section(list, "INSTANT CASH", "Radioactive", 1)
	local g = grid(list, UDim2.fromOffset(250, 290), 2)
	for i, p in items do
		cashCard(g, p, i)
	end
	text(list, {
		Size = UDim2.new(1, -20, 0, 26),
		LayoutOrder = 3,
		Text = "Amounts grow with your income ($/s)!",
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		Stroke = false,
		MaxTextSize = 18,
	})
end

----------------------------------------------------------------------------
-- Onglet BOOSTS
----------------------------------------------------------------------------

local function rarePlus(odds: { [string]: number }, minOrder: number): number
	local sum = 0
	for _, r in Rarities.List do
		if r.Order >= minOrder then
			sum += odds[r.Id] or 0
		end
	end
	return sum
end

-- Explique numériquement l'effet d'un produit serveur (avant / après).
local function showServerOdds(key: string)
	local crater = tonumber(Workspace:GetAttribute("CraterLuck")) or 1
	local serverLuck = math.max(1, tonumber(Workspace:GetAttribute("ServerLuck")) or 1)
	local eventLuck = crater / serverLuck
	local after = crater
	local heading = ""
	local rows = {}
	if key == "ServerLuck" then
		after = eventLuck * math.max(serverLuck, 2)
		heading = "Server Luck x2 · 15 min · everyone"
	elseif key == "MeteorShower" then
		local e = Events.ById.MeteorShower
		after = serverLuck * e.Luck
		heading = string.format("Meteor Shower · x%g meteors · %s", e.MeteorRate, Format.Duration(e.Duration))
	elseif key == "BloodMoon" then
		local e = Events.ById.BloodMoon
		after = serverLuck * e.Luck
		heading = string.format("Blood Moon · %s", Format.Duration(e.Duration))
		local blood = Mutations.Get("Blood")
		table.insert(rows, {
			Label = string.format("Blood mutation on hatch (x%g cash)", if blood then blood.Mult else 4),
			Chance = e.MutationChance or 0,
			Color = if blood then blood.TextColor else C.Red,
		})
	end
	local before = Roll.RarityOdds(crater)
	local boosted = Roll.RarityOdds(after)
	table.insert(rows, { Label = "Rare+ meteor odds · now", Chance = rarePlus(before, 2) })
	table.insert(rows, { Label = "Rare+ meteor odds · boosted", Chance = rarePlus(boosted, 2), Color = C.RadioactiveDark })
	for _, id in { "Epic", "Legendary", "Mythic", "Celestial" } do
		local r = Rarities.Get(id)
		table.insert(rows, { Label = id .. " · now", Chance = before[id] or 0 })
		table.insert(rows, { Label = id .. " · boosted", Chance = boosted[id] or 0, Color = r.Color })
	end
	UIRegistry.ShowOdds(heading, rows)
end

local function starterBanner(list: ScrollingFrame, order: number)
	local c = cell(list, UDim2.new(1, 0, 0, 200), order)
	aura(c, C.Gold, 520)
	local box, b = card(c, { Rotation = -1, Gradient = "Pink" })
	Kit.Starburst({ Size = UDim2.fromOffset(186, 186), Position = UDim2.new(0, 120, 0.5, 0), Color = C.Gold, Transparency = 0.3, Parent = b })
	Kit.Hazard({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 0), ZIndex = 2, Parent = b })
	Kit.Hazard({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), ZIndex = 2, Parent = b })
	-- œuf dessiné (pas de ViewportFrame dans un CanvasGroup)
	local egg = drawEgg(b, Rarities.Get("Legendary").Color, 130, UDim2.new(0, 120, 0.5, 0))
	Kit.Wobble(egg, 7, 0.9)
	text(b, {
		Size = UDim2.new(0.5, 0, 0, 54),
		Position = UDim2.fromOffset(240, 22),
		Text = "STARTER PACK",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Gold,
		Stroke = 3.5,
		MaxTextSize = 50,
		ZIndex = 4,
	})
	local items = Kit.new("Frame", {
		Size = UDim2.new(0, 330, 0, 90),
		Position = UDim2.fromOffset(240, 82),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = b,
	}, { Kit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left) })
	for i, item in STARTER_ITEMS do
		local ch = chip(items, { Text = item.Text, Color = item.Color, AutoWidth = true, Size = UDim2.fromOffset(0, 26), TextSize = 18, LayoutOrder = i, ZIndex = 4 })
		ch.Rotation = (i % 2 == 0) and 1.5 or -1.5
	end
	local stamp = chip(b, {
		Text = "ONE TIME ONLY!",
		Color = C.Red,
		Size = UDim2.fromOffset(180, 32),
		Position = UDim2.new(1, -120, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 5,
	})
	stamp.Rotation = 8
	Kit.Wobble(stamp, 3, 0.8)
	local product = Monetization.ProductByKey.StarterPack
	local _, button, breather = slotButton(b, {
		Name = "BuyStarter",
		Text = robux("StarterPack", product.Robux),
		Color = "Gold",
		Size = UDim2.fromOffset(200, 64),
		Position = UDim2.new(1, -120, 1, -66),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 30,
		ZIndex = 6,
		OnClick = function()
			buyRobux("Product", "StarterPack")
		end,
	})
	setBreathe(breather, true)
	table.insert(updaters, function()
		Kit.SetButtonText(button, robux("StarterPack", product.Robux))
	end)
	popIn(box)
end

local function productCard(parent: Instance, product: any, order: number, withOdds: boolean)
	local c = cell(parent, UDim2.fromOffset(250, 246), order)
	local box, b = card(c, { Rotation = if order % 2 == 0 then 1 else -1.3 })
	band(b, product.Color, product.Icon, 82)
	title(b, string.upper(product.Name), 94, 26, C.White)
	body(b, product.Description, 122, 48)
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, -20, 0, 54),
		Position = UDim2.new(0.5, 0, 1, -62),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = b,
	}, { Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	if withOdds then
		slotButton(row, {
			Name = "Details",
			Text = "ODDS",
			Icon = "🎲",
			IconSize = 22,
			TextSize = 18,
			Color = "Cyan",
			Size = UDim2.new(0.42, 0, 1, 0),
			LayoutOrder = 1,
			OnClick = function()
				showServerOdds(product.Key)
			end,
		})
	end
	local _, button = slotButton(row, {
		Name = "Buy",
		Text = robux(product.Key, product.Robux),
		Color = if product.Category == "Server" then "Magma" else "Radioactive",
		Size = UDim2.new(if withOdds then 0.55 else 0.9, 0, 1, 0),
		LayoutOrder = 2,
		MaxTextSize = 24,
		OnClick = function()
			buyRobux("Product", product.Key)
		end,
	})
	table.insert(updaters, function()
		Kit.SetButtonText(button, robux(product.Key, product.Robux))
	end)
	popIn(box)
end

local function potionCard(parent: Instance, potion: any, order: number)
	local c = cell(parent, UDim2.fromOffset(250, 300), order)
	local colorName = POTION_COLORS[potion.Id] or "Radioactive"
	local box, b = card(c, { Rotation = if order % 2 == 0 then 1.2 else -1 })
	band(b, Theme.Gradients[colorName][2], potion.Icon, 78)
	title(b, string.upper(potion.Name), 90, 26, C.White)
	body(b, potion.Description, 116, 22)
	local count = chip(b, {
		Name = "Count",
		Text = "OWNED x0",
		Color = C.Ink,
		Size = UDim2.fromOffset(130, 28),
		Position = UDim2.new(0.5, 0, 0, 144),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 4,
	})
	local bar, setBar = Kit.ProgressBar({
		Size = UDim2.new(1, -40, 0, 16),
		Position = UDim2.new(0.5, 0, 0, 182),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = colorName,
		ZIndex = 4,
		Parent = b,
	})
	local timer = text(b, {
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 202),
		Text = "NOT ACTIVE",
		TextColor3 = C.InkSoft,
		Stroke = false,
		MaxTextSize = 18,
		ZIndex = 4,
	})
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, -20, 0, 54),
		Position = UDim2.new(0.5, 0, 1, -62),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = b,
	}, { Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local _, buyButton = slotButton(row, {
		Name = "Buy",
		Text = potion.GemPrice .. " 💎",
		Color = "Cyan",
		Size = UDim2.new(0.5, -4, 1, 0),
		LayoutOrder = 1,
		MaxTextSize = 24,
		OnClick = function()
			local key = "potion_buy_" .. potion.Id
			if busy[key] then
				return
			end
			busy[key] = true
			local r = Remote.Call("BuyPotion", { Id = potion.Id })
			busy[key] = nil
			if r.ok then
				Audio.Play("purchase")
				Kit.Punch(count, 0.3)
			end
		end,
	})
	local _, useButton, useBreather = slotButton(row, {
		Name = "Use",
		Text = "USE",
		Color = "Radioactive",
		Size = UDim2.new(0.5, -4, 1, 0),
		LayoutOrder = 2,
		MaxTextSize = 24,
		OnClick = function()
			local key = "potion_use_" .. potion.Id
			if busy[key] then
				return
			end
			busy[key] = true
			local r = Remote.Call("UsePotion", { Id = potion.Id })
			busy[key] = nil
			if r.ok then
				Audio.Play("reward_claim")
				Kit.Punch(box, 0.08)
				Kit.Punch(timer, 0.4)
			end
		end,
	})
	local lastOwned: number? = nil
	table.insert(updaters, function()
		local owned = (State.Get("Potions") or {})[potion.Id] or 0
		local gems = State.Get("Gems") or 0
		local label = count:FindFirstChild("Text") :: TextLabel?
		if label then
			label.Text = "OWNED x" .. owned
		end
		if lastOwned and owned ~= lastOwned then
			Kit.Punch(count, 0.25)
		end
		lastOwned = owned
		styleButton(buyButton, if gems >= potion.GemPrice then "Cyan" else "Grey")
		styleButton(useButton, "Radioactive", owned <= 0)
		setBreathe(useBreather, owned > 0)
	end)
	table.insert(tickers, function()
		local ends = (State.Get("Boosts") or {})[potion.Id] or 0
		local left = ends - now()
		if left > 0 then
			timer.Text = "⏱ ACTIVE " .. Format.Clock(left)
			timer.TextColor3 = C.RadioactiveDark
			setBar(math.min(1, left / potion.Duration), true)
			bar.Visible = true
		else
			timer.Text = "NOT ACTIVE"
			timer.TextColor3 = C.InkSoft
			bar.Visible = false
		end
	end)
	popIn(box)
end

local function buildBoosts(list: ScrollingFrame)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	if State.Get("StarterPack") ~= true and allowed(Monetization.ProductByKey.StarterPack) then
		starterBanner(list, nextOrder())
	end
	local servers = {}
	for _, key in { "ServerLuck", "MeteorShower", "BloodMoon" } do
		local p = Monetization.ProductByKey[key]
		if p and allowed(p) then
			table.insert(servers, p)
		end
	end
	if #servers > 0 then
		section(list, "SERVER BOOSTS", "Magma", nextOrder())
		local g = grid(list, UDim2.fromOffset(250, 246), nextOrder())
		for i, p in servers do
			productCard(g, p, i, true)
		end
	end
	local kaiju = {}
	for _, key in { "InstantHatch", "ShieldNow", "Spins3" } do
		local p = Monetization.ProductByKey[key]
		if p and allowed(p) then
			table.insert(kaiju, p)
		end
	end
	if #kaiju > 0 then
		section(list, "KAIJU BOOSTS", "Radioactive", nextOrder())
		local g = grid(list, UDim2.fromOffset(250, 246), nextOrder())
		for i, p in kaiju do
			productCard(g, p, i, false)
		end
	end
	section(list, "POTIONS", "Purple", nextOrder())
	local wallet = chip(list, { Text = "💎 0", Color = C.Ink, AutoWidth = true, Size = UDim2.fromOffset(0, 30), TextSize = 20, LayoutOrder = nextOrder() })
	local walletLabel = wallet:FindFirstChild("Text") :: TextLabel
	table.insert(updaters, function()
		Kit.CountTo(walletLabel, State.Get("Gems") or 0, function(v)
			return "YOU HAVE 💎 " .. Format.Comma(v)
		end, 0.5)
	end)
	local g = grid(list, UDim2.fromOffset(250, 300), nextOrder())
	for i, potion in Economy.Potions do
		potionCard(g, potion, i)
	end
end

----------------------------------------------------------------------------
-- Onglet UPGRADES
----------------------------------------------------------------------------

local function effectText(u: any, level: number): string
	local v = u.PerLevel * level
	if u.Id == "Shield" then
		return string.format("+%ds shield", v)
	elseif u.Id == "Sneakers" then
		return string.format("+%d speed", v)
	elseif u.Id == "Muscles" then
		return string.format("+%d%% carry speed", math.floor(v * 100 + 0.5))
	elseif u.Id == "Bonker" then
		return string.format("+%g bonk range", v)
	elseif u.Id == "Reactor" then
		return string.format("+%d%% cash", math.floor(v * 100 + 0.5))
	end
	return "+" .. tostring(v)
end

-- Rangée de pastilles de niveau ; renvoie une fonction set(niveau).
local function pips(parent: Instance, count: number, props: { [string]: any }): (number) -> ()
	local holder = Kit.new("Frame", {
		Name = "Pips",
		Size = props.Size,
		Position = props.Position,
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = parent,
	}, { Kit.List(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local list = {}
	for i = 1, count do
		local slot = Kit.new("Frame", { Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, LayoutOrder = i, Parent = holder })
		list[i] = Kit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = C.PaperDark,
			ZIndex = 4,
			Parent = slot,
		}, { Kit.Corner(4), Kit.Stroke(2.5) })
	end
	local last: number? = nil
	return function(level: number)
		for i, pip in list do
			local on = i <= level
			pip.BackgroundColor3 = if on then (props.Color or C.Radioactive) else C.PaperDark
			if on and last ~= nil and i > last then
				task.delay((i - last - 1) * 0.08, function()
					Kit.Pop(pip, 2.2, 0.5)
				end)
			end
		end
		last = level
	end
end

local function upgradeRow(list: Instance, u: any, order: number)
	local c = cell(list, UDim2.new(1, 0, 0, 104), order)
	local box, b = card(c, { Rotation = if order % 2 == 0 then 0.5 else -0.5 })
	local badge = Kit.new("Frame", {
		Size = UDim2.fromOffset(74, 74),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 3,
		Parent = b,
	}, { Kit.Round(), Kit.Stroke(3), Kit.Gradient("Magma") })
	text(badge, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Text = u.Icon, FontFace = F.Body, Stroke = false, MaxTextSize = 44, ZIndex = 4 })
	text(b, {
		Size = UDim2.new(0, 330, 0, 30),
		Position = UDim2.fromOffset(102, 10),
		Text = string.upper(u.Name),
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 2.5,
		MaxTextSize = 26,
		ZIndex = 3,
	})
	local levelLabel = text(b, {
		Size = UDim2.new(0, 90, 0, 26),
		Position = UDim2.fromOffset(372, 12),
		Text = "LV 0",
		FontFace = F.Impact,
		TextColor3 = C.Magma,
		Stroke = 2,
		MaxTextSize = 26,
		ZIndex = 3,
	})
	text(b, {
		Size = UDim2.new(0, 360, 0, 20),
		Position = UDim2.fromOffset(102, 40),
		Text = u.Description,
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		MaxTextSize = 17,
		ZIndex = 3,
	})
	local setPips = pips(b, u.MaxLevel, { Size = UDim2.fromOffset(260, 26), Position = UDim2.fromOffset(104, 64) })
	local effect = text(b, {
		Size = UDim2.new(0, 200, 0, 22),
		Position = UDim2.new(1, -412, 0, 66),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.RadioactiveDark,
		TextXAlignment = Enum.TextXAlignment.Right,
		Stroke = false,
		MaxTextSize = 17,
		ZIndex = 3,
	})
	local slot, button, breather = slotButton(b, {
		Name = "Buy",
		Text = "$0",
		Color = "Radioactive",
		Size = UDim2.fromOffset(180, 60),
		Position = UDim2.new(1, -110, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 28,
		OnClick = function()
			local key = "upgrade_" .. u.Id
			if busy[key] then
				return
			end
			busy[key] = true
			local r = Remote.Call("BuyUpgrade", { Id = u.Id })
			busy[key] = nil
			if r.ok then
				Audio.Play("purchase")
				Kit.Punch(box, 0.06)
			end
		end,
	})
	local maxed = chip(b, {
		Text = "MAXED ★",
		Color = C.Gold,
		TextColor = C.White,
		Size = UDim2.fromOffset(150, 40),
		Position = UDim2.new(1, -110, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 5,
	})
	local lastLevel: number? = nil
	table.insert(updaters, function()
		local level = (State.Get("Upgrades") or {})[u.Id] or 0
		local cash = State.Get("Cash") or 0
		setPips(level)
		levelLabel.Text = string.format("LV %d/%d", level, u.MaxLevel)
		if lastLevel and level ~= lastLevel then
			Kit.Punch(levelLabel, 0.5)
			Kit.Punch(effect, 0.3)
		end
		lastLevel = level
		local isMax = level >= u.MaxLevel
		slot.Visible = not isMax
		maxed.Visible = isMax
		if isMax then
			effect.Text = effectText(u, level)
			setBreathe(breather, false)
		else
			local price = Economy.UpgradePrice(u.Id, level)
			effect.Text = (if level > 0 then effectText(u, level) .. "  →  " else "") .. effectText(u, level + 1)
			Kit.SetButtonText(button, Format.Cash(price))
			local can = cash >= price
			styleButton(button, if can then "Radioactive" else "Grey")
			setBreathe(breather, can)
		end
	end)
	popIn(box)
end

local function nestRow(list: Instance, order: number)
	local c = cell(list, UDim2.new(1, 0, 0, 104), order)
	local box, b = card(c, { Rotation = -0.6, Gradient = "Gold" })
	local badge = Kit.new("Frame", {
		Size = UDim2.fromOffset(74, 74),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 3,
		Parent = b,
	}, { Kit.Round(), Kit.Stroke(3), Kit.Gradient("Radioactive") })
	local icon = text(badge, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Text = "🪺", FontFace = F.Body, Stroke = false, MaxTextSize = 44, ZIndex = 4 })
	Kit.Wobble(icon, 6, 1.1)
	text(b, {
		Size = UDim2.new(0, 330, 0, 30),
		Position = UDim2.fromOffset(102, 10),
		Text = "NESTS",
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 2.5,
		MaxTextSize = 26,
		ZIndex = 3,
	})
	local countLabel = text(b, {
		Size = UDim2.new(0, 110, 0, 26),
		Position = UDim2.fromOffset(352, 12),
		Text = "",
		FontFace = F.Impact,
		TextColor3 = C.Ink,
		Stroke = false,
		MaxTextSize = 26,
		ZIndex = 3,
	})
	text(b, {
		Size = UDim2.new(0, 360, 0, 20),
		Position = UDim2.fromOffset(102, 40),
		Text = "Level up to get more nests!",
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		MaxTextSize = 17,
		ZIndex = 3,
	})
	local setPips = pips(b, #Levels.NestLevels, { Size = UDim2.fromOffset(300, 26), Position = UDim2.fromOffset(104, 64), Color = C.Magma })
	local nextChip = chip(b, {
		Text = "NEXT AT LV 2",
		Color = C.MagmaDark,
		Size = UDim2.fromOffset(180, 44),
		Position = UDim2.new(1, -110, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 5,
	})
	table.insert(updaters, function()
		local level = State.Get("Level") or 1
		local nests = math.max(State.Get("Nests") or Economy.StartNests, Levels.NestsFor(level))
		setPips(nests - Levels.StartNests)
		countLabel.Text = string.format("%d / %d", nests, Levels.NestsFor(Levels.Max))
		local nextLevel = nil
		for _, l in Levels.NestLevels do
			if l > level then
				nextLevel = l
				break
			end
		end
		local chipText = nextChip:FindFirstChild("Text") :: TextLabel
		chipText.Text = if nextLevel then ("NEXT AT LEVEL %d"):format(nextLevel) else "ALL UNLOCKED ★"
		nextChip.BackgroundColor3 = if nextLevel then C.MagmaDark else C.RadioactiveDark
	end)
	popIn(box)
end

local function buildUpgrades(list: ScrollingFrame)
	local head = cell(list, UDim2.new(1, 0, 0, 50), 1)
	Kit.Ribbon({ Text = "UPGRADES", Color = "Magma", Size = UDim2.fromOffset(230, 42), Position = UDim2.fromOffset(8, 2), AnchorPoint = Vector2.zero, Rotation = -2, ZIndex = 4, Parent = head })
	local wallet = chip(head, {
		Text = "$0",
		Color = C.RadioactiveDark,
		Size = UDim2.fromOffset(220, 34),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 22,
	})
	local walletLabel = wallet:FindFirstChild("Text") :: TextLabel
	table.insert(updaters, function()
		Kit.CountTo(walletLabel, State.Get("Cash") or 0, function(v)
			return "💵 " .. Format.Cash(v)
		end, 0.5)
	end)
	nestRow(list, 2)
	for i, u in Economy.Upgrades do
		upgradeRow(list, u, 2 + i)
	end
end

----------------------------------------------------------------------------
-- Onglets & cycle de vie
----------------------------------------------------------------------------

local BUILDERS: { [string]: (ScrollingFrame) -> () } = {
	Passes = buildPasses,
	Gems = buildGems,
	Cash = buildCash,
	Boosts = buildBoosts,
	Upgrades = buildUpgrades,
}

local function runUpdaters()
	for _, fn in updaters do
		task.spawn(fn)
	end
	for _, fn in tickers do
		task.spawn(fn)
	end
end

-- Onglets Gems / Cash entièrement « hasard payant » : masqués si restreints.
local function tabVisible(id: string): boolean
	if id == "Gems" or id == "Cash" then
		for _, p in Monetization.Products do
			if p.Category == id and allowed(p) then
				return true
			end
		end
		return false
	end
	return true
end

local function refreshTabs()
	for _, tab in TABS do
		local button = tabBar:FindFirstChild(tab.Id) :: GuiObject?
		if button then
			button.Visible = tabVisible(tab.Id)
		end
	end
end

local function showPage(id: string)
	if not BUILDERS[id] or not tabVisible(id) then
		id = "Passes"
	end
	currentTab = id
	updaters = {}
	tickers = {}
	popCount = 0
	if scroll then
		scroll:Destroy()
	end
	-- CanvasGroup : seul moyen de découper proprement sous une fenêtre inclinée
	local clip = Kit.new("CanvasGroup", {
		Name = "PageClip",
		Size = UDim2.new(1, 0, 1, -62),
		Position = UDim2.fromOffset(0, 62),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = content,
	})
	local list = Kit.Scroll({ Name = "Page", Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = clip })
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 16),
		Parent = list,
	})
	Kit.List(Enum.FillDirection.Vertical, 12).Parent = list
	scroll = clip
	BUILDERS[id](list)
	runUpdaters()
	-- glissement d'entrée de la page (découpé par le CanvasGroup)
	list.Position = UDim2.fromOffset(60, 0)
	Kit.Tween(list, 0.4, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
end

local function startLoop()
	loopToken += 1
	local token = loopToken
	task.spawn(function()
		while window.IsOpen and token == loopToken do
			for _, fn in tickers do
				fn()
			end
			task.wait(0.25)
		end
	end)
end

-- Prix réels (si les identifiants sont configurés), en arrière-plan.
local function fetchPrices()
	task.spawn(function()
		for _, pass in Monetization.Passes do
			if pass.Id ~= 0 then
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(pass.Id, Enum.InfoType.GamePass)
				end)
				if ok and info and info.PriceInRobux then
					priceCache[pass.Key] = info.PriceInRobux
				end
			end
		end
		for _, product in Monetization.Products do
			if product.Id ~= 0 then
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(product.Id, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					priceCache[product.Key] = info.PriceInRobux
				end
			end
		end
		if window and window.IsOpen then
			runUpdaters()
		end
	end)
end

function Shop.Init()
	window = Kit.Window({ Name = "Shop", Title = "KAIJU MART", Icon = "🛒", Color = "Magma", Size = UDim2.fromOffset(900, 580), RibbonWidth = 360 })
	content = window.Frame
	local bar, select = Kit.Tabs({
		Tabs = TABS,
		ActiveColor = "Magma",
		Size = UDim2.new(1, 0, 0, 54),
		OnSelect = function(id)
			if window.IsOpen then
				showPage(id)
			else
				currentTab = id
			end
		end,
		Parent = content,
	})
	tabBar = bar
	selectTab = select
	refreshTabs()

	-- Rafraîchissements ciblés
	for _, key in { "Cash", "Gems", "Passes", "Potions", "Boosts", "Upgrades", "Nests", "Income" } do
		State.Changed(key):Connect(function()
			if window.IsOpen then
				runUpdaters()
			end
		end)
	end
	-- Changements structurels : reconstruction de la page
	for _, key in { "RandomRestricted", "StarterPack" } do
		State.Changed(key):Connect(function()
			refreshTabs()
			if window.IsOpen then
				selectTab(if tabVisible(currentTab) then currentTab else "Passes")
			end
		end)
	end

	window.Opened:Connect(startLoop)
	window.Closed:Connect(function()
		loopToken += 1
	end)
	fetchPrices()
end

function Shop.Open(args: any?)
	local tab = if type(args) == "string" then args else currentTab
	if not BUILDERS[tab] then
		tab = "Passes"
	end
	refreshTabs()
	window:Open()
	selectTab(tab)
end

function Shop.Close()
	window:Close()
end

return Shop
