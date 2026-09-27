--!nonstrict
-- KAIJUDEX : collection de toutes les espèces (silhouettes tant qu'elles ne sont
-- pas découvertes), filtres par rareté, points de mutations trouvées et fiche
-- détaillée (aperçu 3D, recette des Secrets, liste des mutations).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Worlds = require(Shared.Config.Worlds)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Parent.Kit)
local Viewport = require(script.Parent.Parent.Viewport)
local Controllers = script.Parent.Parent.Parent.Controllers
local State = require(Controllers.State)
local Audio = require(Controllers.Audio)

local C = Kit.Colors
local F = Kit.Fonts

local Index = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 90)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(124, 255, 79)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(61, 224, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 61, 139)),
})

local CARD_W, CARD_H = 124, 162
local DETAIL_W = 322

----------------------------------------------------------------------------
-- Aides
----------------------------------------------------------------------------

local function rainbow(parent: Instance, period: number?): UIGradient
	local g = parent:FindFirstChild("Rainbow") :: UIGradient?
	if not g then
		g = Kit.new("UIGradient", { Name = "Rainbow", Color = RAINBOW, Parent = parent })
		Kit.Tween(g :: UIGradient, period or 2.5, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	end
	return g :: UIGradient
end

local function clearRainbow(parent: Instance)
	local g = parent:FindFirstChild("Rainbow")
	if g then
		g:Destroy()
	end
end

local function rarityColor(id: string): Color3
	return if id == "Secret" then C.Ink else Rarities.Get(id).Color
end

local function inkText(props: { [string]: any }): TextLabel
	props.Stroke = false
	props.FontFace = props.FontFace or F.Body
	props.TextColor3 = props.TextColor3 or C.Ink
	return Kit.Text(props)
end

local function indexData(): { [string]: { [string]: boolean } }
	return State.Get("Index") or {}
end

local function discoveredCount(): number
	local n = 0
	for id in indexData() do
		if Kaijus.Get(id) then
			n += 1
		end
	end
	return n
end

-- Espèces triées par rareté puis ordre du roster.
local sorted: { any } = table.clone(Kaijus.List)
table.sort(sorted, function(a, b)
	local ra, rb = Rarities.Get(a.Rarity).Order, Rarities.Get(b.Rarity).Order
	if ra ~= rb then
		return ra < rb
	end
	return (a :: any).Index < (b :: any).Index
end)

----------------------------------------------------------------------------
-- État
----------------------------------------------------------------------------

local win: any = nil
local ui: { [string]: any } = {}
local cards: { [string]: any } = {} -- [speciesId] = { Button, Vp, Name, Dots, ... }
local cardsBuilt = false
local filter = "All"
local selected: string? = nil
local detailOpen = false
local detailVp: any = nil
local detailMutation: string? = nil
local lastKnown: { [string]: boolean } = {}

----------------------------------------------------------------------------
-- Cartes
----------------------------------------------------------------------------

local function refreshCard(card: any, animateNew: boolean)
	local species = card.Species
	local entry = indexData()[species.Id]
	local found = entry ~= nil
	local secret = species.Rarity == "Secret"
	card.Name.Text = if found then species.Name else "???"
	card.Name.TextColor3 = if found then C.Ink else C.InkSoft
	card.Question.Visible = not found and not secret
	card.Hint.Visible = not found and secret
	if card.Vp then
		card.Vp:SetSilhouette(not found)
	end
	for mutId, dot in card.Dots do
		local lit = entry ~= nil and entry[mutId] == true
		local m = Mutations.Get(mutId)
		dot.BackgroundColor3 = if lit and m then m.Color else C.PaperDark
		dot.BackgroundTransparency = if lit then 0 else 0.2
		local stroke = dot:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = if lit then 0 else 0.6
		end
		if lit and mutId == "Rainbow" then
			rainbow(dot, 1.5)
		end
	end
	if found and not lastKnown[species.Id] and animateNew then
		Kit.Punch(card.Button, 0.35)
		Kit.Tween(card.Select, 0.1, { Transparency = 0, Color = C.Radioactive })
		task.delay(0.9, function()
			Kit.Tween(card.Select, 0.4, { Transparency = if selected == species.Id then 0 else 1, Color = C.Magma })
		end)
	end
	lastKnown[species.Id] = found
end

local function setHover(card: any, on: boolean)
	local scale = Kit.ScaleOf(card.Button)
	if on then
		Audio.Play("ui_hover", { Cooldown = 0.06 })
		Kit.Tween(scale, 0.25, { Scale = 1.07 }, Enum.EasingStyle.Back)
		Kit.Tween(card.Button, 0.25, { Rotation = card.Tilt }, Enum.EasingStyle.Back)
	else
		Kit.Tween(scale, 0.2, { Scale = 1 })
		Kit.Tween(card.Button, 0.2, { Rotation = 0 })
	end
	if card.Vp then
		card.Vp.Spin = on
		card.Vp.Speed = 1.4
	end
end

local showDetail -- déclarée plus bas

local function buildCard(species: any, order: number): any
	local rarity = Rarities.Get(species.Rarity)
	local secret = species.Rarity == "Secret"
	local button = Kit.new("TextButton", {
		Name = species.Id,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
		ZIndex = 6,
		Parent = ui.Grid,
	})
	Kit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = C.Ink,
		ZIndex = 6,
		Parent = button,
	}, { Kit.Corner(14) })
	local body = Kit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		ZIndex = 7,
		Parent = button,
	}, { Kit.Corner(14), Kit.Stroke(3), Kit.Gradient("Paper") })
	-- projecteur coloré derrière le kaiju
	local spot = Kit.new("Frame", {
		Name = "Spot",
		Size = UDim2.new(1, -10, 0, 92),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = C.White,
		ZIndex = 8,
		Parent = body,
	}, {
		Kit.Corner(10),
		Kit.Stroke(2.5),
		Kit.Gradient(if secret then { C.InkSoft, C.Ink } else { rarity.Glow, rarity.Color:Lerp(C.Ink, 0.15) }, 90),
	})
	Kit.new("Frame", {
		Name = "Halo",
		Size = UDim2.fromOffset(74, 74),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = if secret then C.Gold else C.White,
		BackgroundTransparency = 0.55,
		ZIndex = 8,
		Parent = spot,
	}, { Kit.Round() })
	local vpHolder = Kit.new("Frame", {
		Name = "VpHolder",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = spot,
	})
	local question = Kit.Text({
		Name = "Question",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(1, -4, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		Text = "?",
		TextColor3 = C.Gold,
		FontFace = F.Impact,
		Stroke = 3,
		Rotation = 12,
		ZIndex = 11,
		Parent = spot,
	})
	local hint = Kit.Text({
		Name = "Hint",
		Size = UDim2.new(1, -8, 0, 30),
		Position = UDim2.new(0.5, 0, 1, -3),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = '"' .. (species.Hint or "???") .. '"',
		FontFace = F.Body,
		TextColor3 = C.Gold,
		TextWrapped = true,
		MaxTextSize = 13,
		Stroke = 1.5,
		ZIndex = 11,
		Parent = spot,
	})
	local name = inkText({
		Name = "KName",
		Size = UDim2.new(1, -10, 0, 22),
		Position = UDim2.fromOffset(5, 100),
		Text = species.Name,
		FontFace = F.Title,
		MaxTextSize = 18,
		ZIndex = 8,
		Parent = body,
	})
	local chip = Kit.Chip({
		Name = "Rarity",
		Text = string.upper(species.Rarity),
		Color = rarityColor(species.Rarity),
		Size = UDim2.fromOffset(96, 18),
		Position = UDim2.new(0.5, 0, 0, 124),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 8,
		Parent = body,
	})
	if secret then
		rainbow(chip, 2)
	end
	local dotRow = Kit.new("Frame", {
		Name = "Dots",
		Size = UDim2.new(1, -12, 0, 10),
		Position = UDim2.new(0.5, 0, 0, 146),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = body,
	}, { Kit.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local dots = {}
	for i, m in Mutations.List do
		dots[m.Id] = Kit.new("Frame", {
			Name = m.Id,
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = C.PaperDark,
			LayoutOrder = i,
			ZIndex = 9,
			Parent = dotRow,
		}, { Kit.Round(), Kit.Stroke(1.5) })
	end
	-- surlignage de sélection
	local ring = Kit.new("UIStroke", {
		Name = "Selected",
		Thickness = 5,
		Transparency = 1,
		Color = C.Magma,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = Kit.new("Frame", {
			Name = "SelectRing",
			Size = UDim2.new(1, 8, 1, 8),
			Position = UDim2.fromOffset(-4, -4),
			BackgroundTransparency = 1,
			ZIndex = 12,
			Parent = button,
		}, { Kit.Corner(17) }),
	})

	local card = {
		Species = species,
		Button = button,
		VpHolder = vpHolder,
		Vp = nil :: any,
		Name = name,
		Question = question,
		Hint = hint,
		Dots = dots,
		Select = ring,
		Tilt = if order % 2 == 0 then 2.5 else -2.5,
	}
	button.MouseEnter:Connect(function()
		setHover(card, true)
	end)
	button.MouseLeave:Connect(function()
		setHover(card, false)
	end)
	button.Activated:Connect(function()
		Audio.Play("ui_click")
		Kit.Punch(button, 0.12)
		if selected == species.Id and detailOpen then
			Index._HideDetail()
		else
			showDetail(species.Id)
		end
	end)
	refreshCard(card, false)
	return card
end

-- Crée les aperçus 3D progressivement (pas de gros à-coup à l'ouverture).
local function buildViewports()
	local n = 0
	for _, species in sorted do
		local card = cards[species.Id]
		if card and not card.Vp then
			card.Vp = Viewport.new({
				Species = species.Id,
				Parent = card.VpHolder,
				ZIndex = 10,
				Spin = false,
				Angle = 0.55,
			})
			refreshCard(card, false)
			Kit.Pop(card.Vp.Frame, 0.2, 0.4)
			n += 1
			if n % 5 == 0 then
				task.wait()
			end
		end
	end
end

local function refreshHeader(animate: boolean)
	local count = discoveredCount()
	local total = #Kaijus.List
	local prev = ui.Count:GetAttribute("Value")
	if animate then
		ui.Count:SetAttribute("Value", 0)
		ui.SetProgress(0, true)
	end
	if animate or prev ~= count then
		Kit.CountTo(ui.Count, count, function(v)
			return ("%d / %d"):format(math.floor(v + 0.5), total)
		end, if animate then 0.9 else 0.5)
		if prev ~= nil and prev ~= count then
			Kit.Punch(ui.CountHolder, 0.25)
			Kit.Punch(ui.BonusHolder, 0.3)
		end
	end
	ui.SetProgress(count / math.max(total, 1))
	ui.Bonus.Text = ("+%s%% CASH"):format(Format.Short(count * Economy.IndexBoostPerSpecies * 100))

	-- sous-titre du filtre actuel
	local shownN, foundN = 0, 0
	local data = indexData()
	for _, species in sorted do
		if filter == "All" or species.Rarity == filter then
			shownN += 1
			if data[species.Id] then
				foundN += 1
			end
		end
	end
	local label = if filter == "All" then "ALL KAIJUS" else string.upper(filter)
	ui.Sub.Text = ("%s · <b>%d / %d</b> found"):format(label, foundN, shownN)
end

local function applyFilter(id: string, animate: boolean)
	filter = id
	local order = 0
	for _, species in sorted do
		local card = cards[species.Id]
		if card then
			local visible = id == "All" or species.Rarity == id
			card.Button.Visible = visible
			if visible and animate then
				order += 1
				if order <= 30 then
					local s = Kit.ScaleOf(card.Button)
					s.Scale = 0.01
					task.delay(order * 0.025, function()
						Kit.Pop(card.Button, 0.3, 0.4)
					end)
				end
			end
		end
	end
	ui.Grid.CanvasPosition = Vector2.zero
	refreshHeader(false)
end

----------------------------------------------------------------------------
-- Fiche détaillée
----------------------------------------------------------------------------

local function setDetailOpen(open: boolean)
	if detailOpen == open then
		return
	end
	detailOpen = open
	local gridSize = if open then UDim2.new(1, -(DETAIL_W + 10), 1, -110) else UDim2.new(1, 0, 1, -110)
	Kit.Tween(ui.Grid, 0.28, { Size = gridSize }, Enum.EasingStyle.Quad)
	if open then
		ui.Detail.Visible = true
		ui.Detail.Position = UDim2.new(1, 40, 0, 110)
		Kit.Tween(ui.Detail, 0.45, { Position = UDim2.new(1, 0, 0, 110) }, Enum.EasingStyle.Back)
		if detailVp then
			detailVp.Spin = true
		end
	else
		Kit.Tween(ui.Detail, 0.2, { Position = UDim2.new(1, DETAIL_W + 60, 0, 110) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			if not detailOpen then
				ui.Detail.Visible = false
			end
		end)
		if detailVp then
			detailVp.Spin = false
		end
	end
end

local function renderDetail(speciesId: string, pop: boolean)
	local species = Kaijus.Get(speciesId)
	if not species then
		return
	end
	local rarity = Rarities.Get(species.Rarity)
	local secret = species.Rarity == "Secret"
	local entry = indexData()[species.Id]
	local found = entry ~= nil
	local d = ui.D

	-- aperçu
	if not detailVp then
		detailVp = Viewport.new({ Parent = d.VpHolder, ZIndex = 8, Speed = 0.8 })
	end
	if detailMutation and not (entry and entry[detailMutation]) then
		detailMutation = nil
	end
	detailVp:Set(species.Id, detailMutation)
	detailVp:SetSilhouette(not found)
	detailVp.Spin = true
	d.StageGradient.Color = if secret
		then ColorSequence.new(C.InkSoft, C.Ink)
		else ColorSequence.new(rarity.Glow, rarity.Color:Lerp(C.Ink, 0.2))
	for _, ray in d.Burst:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = if secret then C.Gold else C.White
		end
	end

	d.Name.Text = if found then species.Name else "???"
	if secret and found then
		d.Name.TextColor3 = C.White
		rainbow(d.Name, 2.5)
	else
		clearRainbow(d.Name)
		d.Name.TextColor3 = if found then rarity.Color:Lerp(C.White, 0.2) else C.PaperDark
	end
	d.Rarity.BackgroundColor3 = rarityColor(species.Rarity)
	d.Rarity.Text.Text = string.upper(species.Rarity)
	if secret then
		rainbow(d.Rarity, 2)
	else
		clearRainbow(d.Rarity)
	end
	local variants = 0
	if entry then
		for _ in entry do
			variants += 1
		end
	end
	d.Variants.Text.Text = ("%d / %d VARIANTS"):format(variants, #Mutations.List + 1)

	d.Flavor.Text = if found then '"' .. species.Flavor .. '"' else "Discover this kaiju to read its file."
	d.Income.Text = ("💵 Base income  <b>%s/s</b>"):format(Format.Cash(species.Income))
	local home = nil
	for _, w in Worlds.List do
		if table.find(w.Species, species.Id) then
			home = w
		end
	end
	d.Price.Text = if species.Price > 0
		then ("☄️ Found in <b>%s</b>  •  egg %s"):format(if home then string.upper(home.Name) else "METEORS", Format.Cash(species.Price))
		else "🧪 <b>Fusion only</b> — not sold in meteors"

	-- recette (Secrets)
	d.Recipe.Visible = secret
	if secret then
		local recipe = species.Recipe or {}
		if found then
			local a = Kaijus.Get(recipe[1] or "")
			local b = Kaijus.Get(recipe[2] or "")
			d.RecipeText.Text = ("<b>%s</b>  +  <b>%s</b>"):format(if a then a.Name else "?", if b then b.Name else "?")
		else
			d.RecipeText.Text = ("<b>???  +  ???</b>\n<i>%s</i>"):format(species.Hint or "")
		end
	end

	-- mutations
	for mutId, row in d.MutRows do
		local have = entry ~= nil and entry[mutId] == true
		row.Status.Text = if have then "✓ FOUND" else "🔒"
		row.Status.TextColor3 = if have then C.RadioactiveDark else C.InkSoft
		row.Frame.BackgroundTransparency = if have then 0.15 else 0.55
		row.Frame.BackgroundColor3 = if (detailMutation or "Normal") == mutId and have then C.Gold else C.Paper
	end

	if pop then
		Kit.Pop(d.Stage, 0.6, 0.5)
		Kit.Pop(d.Name, 0.3, 0.45)
		Kit.Punch(ui.Detail, 0.05)
	end
end

showDetail = function(speciesId: string)
	if selected and cards[selected] then
		local old = cards[selected]
		Kit.Tween(old.Select, 0.15, { Transparency = 1 })
	end
	selected = speciesId
	detailMutation = nil
	local card = cards[speciesId]
	if card then
		card.Select.Transparency = 1
		Kit.Tween(card.Select, 0.25, { Transparency = 0 })
		Kit.Punch(card.Button, 0.15)
	end
	renderDetail(speciesId, true)
	setDetailOpen(true)
end

function Index._HideDetail()
	if selected and cards[selected] then
		Kit.Tween(cards[selected].Select, 0.15, { Transparency = 1 })
	end
	selected = nil
	setDetailOpen(false)
end

----------------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------------

local function buildDetail(root: Frame)
	local holder, body = Kit.Panel({
		Name = "Detail",
		Size = UDim2.new(0, DETAIL_W, 1, -114),
		Position = UDim2.new(1, DETAIL_W + 60, 0, 110),
		AnchorPoint = Vector2.new(1, 0),
		Rotation = 1.2,
		ZIndex = 20,
		Parent = root,
	})
	holder.Visible = false
	ui.Detail = holder
	local d: { [string]: any } = {}
	ui.D = d

	-- scène : rayons + kaiju géant
	local stage = Kit.new("Frame", {
		Name = "Stage",
		Size = UDim2.new(1, -16, 0, 150),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = C.White,
		ZIndex = 21,
		Parent = body,
	}, { Kit.Corner(12), Kit.Stroke(3) })
	d.Stage = stage
	d.StageGradient = Kit.Gradient({ C.White, C.White }, 90)
	d.StageGradient.Parent = stage
	local clip = Kit.new("CanvasGroup", {
		Name = "Clip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = stage,
	}, { Kit.Corner(12) })
	d.Burst = Kit.Starburst({
		Size = UDim2.fromOffset(460, 460),
		Position = UDim2.fromScale(0.5, 0.55),
		Rays = 14,
		Color = C.White,
		Transparency = 0.6,
		Period = 16,
		ZIndex = 21,
		Parent = clip,
	})
	d.VpHolder = Kit.new("Frame", {
		Name = "VpHolder",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = stage,
	})
	Kit.Button({
		Name = "CloseDetail",
		Text = "X",
		Color = "Red",
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.new(1, 8, 0, -8),
		AnchorPoint = Vector2.new(1, 0),
		Corner = 19,
		HoverTilt = 10,
		Sound = "ui_close",
		ZIndex = 30,
		Parent = holder,
		OnClick = function()
			Index._HideDetail()
		end,
	})

	d.Name = Kit.Text({
		Name = "DName",
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 162),
		Text = "",
		MaxTextSize = 30,
		Stroke = 3,
		ZIndex = 22,
		Parent = body,
	})
	local chips = Kit.new("Frame", {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 198),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = body,
	}, { Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	d.Rarity = Kit.Chip({ AutoWidth = true, Size = UDim2.fromOffset(0, 24), TextSize = 15, LayoutOrder = 1, ZIndex = 23, Parent = chips })
	d.Variants = Kit.Chip({ AutoWidth = true, Size = UDim2.fromOffset(0, 24), TextSize = 14, Color = C.InkSoft, LayoutOrder = 2, ZIndex = 23, Parent = chips })

	local scroll = Kit.Scroll({
		Name = "Info",
		Size = UDim2.new(1, -12, 1, -236),
		Position = UDim2.fromOffset(6, 228),
		ZIndex = 22,
		Parent = body,
	})
	scroll.ScrollBarThickness = 6
	Kit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center).Parent = scroll
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 8),
		Parent = scroll,
	})
	local function para(name: string, order: number, size: number?): TextLabel
		return inkText({
			Name = name,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextScaled = false,
			TextSize = size or 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			LayoutOrder = order,
			ZIndex = 23,
			Parent = scroll,
		})
	end
	d.Flavor = para("Flavor", 1, 16)
	d.Flavor.TextColor3 = C.InkSoft
	d.Income = para("Income", 2)
	d.Price = para("Price", 3)

	-- encart recette
	local recipe = Kit.new("Frame", {
		Name = "Recipe",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Ink,
		LayoutOrder = 4,
		ZIndex = 23,
		Parent = scroll,
	}, { Kit.Corner(10), Kit.Stroke(2.5), Kit.Padding(8, 6), Kit.List(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left) })
	d.Recipe = recipe
	local rt = Kit.Text({
		Size = UDim2.new(1, 0, 0, 18),
		Text = "🧪 FUSION RECIPE",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Gold,
		MaxTextSize = 16,
		Stroke = 2,
		LayoutOrder = 1,
		ZIndex = 24,
		Parent = recipe,
	})
	rainbow(rt, 3)
	d.RecipeText = Kit.Text({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		LayoutOrder = 2,
		ZIndex = 24,
		Parent = recipe,
	})

	inkText({
		Size = UDim2.new(1, 0, 0, 20),
		Text = "MUTATIONS",
		FontFace = F.Title,
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 5,
		ZIndex = 23,
		Parent = scroll,
	})
	d.MutRows = {}
	local rows = { { Id = "Normal", Name = "Normal", Mult = 1, Color = C.PaperDark } }
	for _, m in Mutations.List do
		table.insert(rows, { Id = m.Id, Name = m.Name, Mult = m.Mult, Color = m.Color })
	end
	for i, m in rows do
		local row = Kit.new("TextButton", {
			Name = m.Id,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = C.Paper,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = 10 + i,
			ZIndex = 23,
			Parent = scroll,
		}, { Kit.Corner(8), Kit.Stroke(2) })
		local dot = Kit.new("Frame", {
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = m.Color,
			ZIndex = 24,
			Parent = row,
		}, { Kit.Round(), Kit.Stroke(2) })
		if m.Id == "Rainbow" then
			rainbow(dot, 1.5)
		end
		inkText({
			Size = UDim2.new(0.5, 0, 0, 18),
			Position = UDim2.new(0, 32, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Text = ("<b>%s</b>  x%s"):format(m.Name, tostring(m.Mult)),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 24,
			Parent = row,
		})
		local status = inkText({
			Size = UDim2.new(0.34, 0, 0, 16),
			Position = UDim2.new(1, -8, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Text = "🔒",
			FontFace = F.Title,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 24,
			Parent = row,
		})
		d.MutRows[m.Id] = { Frame = row, Status = status }
		-- aperçu de la variante (si découverte)
		row.Activated:Connect(function()
			local id = selected
			if not id then
				return
			end
			local entry = indexData()[id]
			if entry and entry[m.Id] then
				Audio.Play("ui_tab")
				detailMutation = if m.Id == "Normal" then nil else m.Id
				renderDetail(id, false)
				Kit.Pop(d.Stage, 0.85, 0.35)
				Kit.Punch(row, 0.1)
			else
				Audio.Play("ui_error")
				Kit.Punch(row, -0.06)
			end
		end)
	end
end

local function build()
	win = Kit.Window({
		Name = "Index",
		Title = "KAIJUDEX",
		Icon = "📖",
		Color = "Radioactive",
		Size = UDim2.fromOffset(900, 580),
		RibbonWidth = 330,
		Rotation = -1,
	})
	local root: Frame = win.Frame

	------------------------------------------------------------------ en-tête
	local countHolder, countBody = Kit.Panel({
		Name = "Count",
		Size = UDim2.fromOffset(300, 44),
		Position = UDim2.fromOffset(0, -4),
		Rotation = -1.5,
		Gradient = "Ink",
		ShadowOffset = 4,
		Parent = root,
	})
	ui.CountHolder = countHolder
	Kit.Text({
		Size = UDim2.fromOffset(110, 16),
		Position = UDim2.fromOffset(12, 4),
		Text = "DISCOVERED",
		TextColor3 = C.Radioactive,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 14,
		Stroke = 1.5,
		ZIndex = 3,
		Parent = countBody,
	})
	ui.Count = Kit.Text({
		Name = "Value",
		Size = UDim2.fromOffset(110, 22),
		Position = UDim2.fromOffset(12, 19),
		Text = "0 / 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Stroke = 2,
		ZIndex = 3,
		Parent = countBody,
	})
	local _, setProgress = Kit.ProgressBar({
		Size = UDim2.fromOffset(160, 16),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = "Radioactive",
		ZIndex = 3,
		Parent = countBody,
	})
	ui.SetProgress = setProgress

	ui.Sub = inkText({
		Name = "Sub",
		Size = UDim2.fromOffset(236, 20),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		ZIndex = 3,
		Parent = root,
	})

	local bonusHolder, bonusBody = Kit.Panel({
		Name = "Bonus",
		Size = UDim2.fromOffset(210, 44),
		Position = UDim2.new(1, 0, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		Rotation = 2,
		Gradient = "Gold",
		ShadowOffset = 4,
		Parent = root,
	})
	ui.BonusHolder = bonusHolder
	Kit.Text({
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.fromOffset(8, 4),
		Text = "INDEX BONUS",
		MaxTextSize = 13,
		Stroke = 1.5,
		ZIndex = 3,
		Parent = bonusBody,
	})
	ui.Bonus = Kit.Text({
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 18),
		Text = "+0% CASH",
		MaxTextSize = 22,
		Stroke = 2.5,
		ZIndex = 3,
		Parent = bonusBody,
	})

	------------------------------------------------------------------ onglets
	local tabs = { { Id = "All", Text = "ALL", Width = 68 } }
	for _, r in Rarities.List do
		table.insert(tabs, { Id = r.Id, Text = string.upper(r.Id), Width = 100 })
	end
	local bar, selectTab = Kit.Tabs({
		Tabs = tabs,
		ActiveColor = "Magma",
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.fromOffset(0, 48),
		Parent = root,
		OnSelect = function(id)
			if id ~= filter then
				applyFilter(id, true)
			end
		end,
	})
	ui.Tabs = bar
	ui.SelectTab = selectTab
	-- libellés teintés de la couleur de rareté
	for _, r in Rarities.List do
		local b = bar:FindFirstChild(r.Id)
		local label = b and b:FindFirstChild("Label", true)
		if label then
			(label :: any).TextColor3 = if r.Id == "Secret" then C.White else r.Color:Lerp(C.White, 0.3)
			if r.Id == "Secret" then
				rainbow(label, 2)
			end
		end
	end

	------------------------------------------------------------------ grille
	local grid = Kit.Scroll({
		Name = "Grid",
		Size = UDim2.new(1, 0, 1, -110),
		Position = UDim2.fromOffset(0, 110),
		ZIndex = 6,
		Parent = root,
	})
	ui.Grid = grid
	local layout = Kit.Grid(UDim2.fromOffset(CARD_W, CARD_H), 12)
	layout.Parent = grid
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 12),
		Parent = grid,
	})

	buildDetail(root)
end

-- Premier affichage : cartes créées une seule fois, aperçus progressifs.
local function ensureCards()
	if cardsBuilt then
		return
	end
	cardsBuilt = true
	for i, species in sorted do
		cards[species.Id] = buildCard(species, i)
	end
	task.spawn(buildViewports)
end

local function refreshAll(animateNew: boolean)
	for _, card in cards do
		refreshCard(card, animateNew)
	end
	refreshHeader(false)
	if selected and detailOpen then
		renderDetail(selected, false)
	end
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

function Index.Init()
	build()
	ui.SelectTab("All")
	for id in indexData() do
		lastKnown[id] = true
	end
	State.Changed("Index"):Connect(function()
		if cardsBuilt then
			refreshAll(win.IsOpen)
		end
	end)
	win.Closed:Connect(function()
		for _, card in cards do
			if card.Vp then
				card.Vp.Spin = false
			end
			local s = Kit.ScaleOf(card.Button)
			s.Scale = 1
			card.Button.Rotation = 0
		end
		if detailVp then
			detailVp.Spin = false
		end
	end)
end

function Index.Open(args: any?)
	if args == Index then
		args = nil
	end
	ensureCards()
	refreshAll(false)
	win:Open()
	-- en-tête et onglets en cascade
	Kit.Pop(ui.CountHolder, 0.4, 0.5)
	task.delay(0.08, function()
		Kit.Pop(ui.BonusHolder, 0.4, 0.5)
	end)
	for i, tab in ui.Tabs:GetChildren() do
		if tab:IsA("GuiButton") then
			Kit.ScaleOf(tab).Scale = 0.01
			task.delay(0.05 + i * 0.03, function()
				Kit.Pop(tab, 0.3, 0.4)
			end)
		end
	end
	refreshHeader(true)
	-- sélection éventuelle d'une espèce
	local species = if type(args) == "table" then args.Species else nil
	if species and Kaijus.Get(species) then
		if filter ~= "All" then
			ui.SelectTab("All") -- déclenche applyFilter via OnSelect
		else
			applyFilter("All", true)
		end
		showDetail(species)
	else
		applyFilter(filter, true)
		if detailOpen and detailVp then
			detailVp.Spin = true
		end
	end
end

function Index.Close()
	if win then
		win:Close()
	end
end

return Index
