--!strict
--[[
	HUD du deathrun : très peu d'éléments, lisibles par un enfant sur téléphone (v4 « HUD allégé »).
	Style de l'app AngAInOne : verre Fluent (Glass) et accent violet (AccentViolet).
	Canevas de conception 1280 × 620 au pire (voir App.computeScale) :
	┌ [Bits]        ┌ MONDE 2 · Memory Lanes                  ⏱ 4:07.3 ┐           [⋯] ┐ y 12..108
	│ [passes]      │ ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░    Étape 7/35 │   ┌──────────┐│
	│ [bouclier]    │ « ton but en une phrase »  [⚡ 144][≋ 8 ms][🌡 40°] │   │Restaurer ││ menu « ⋯ »
	│               └───────────────────────────────────────────────────┘   │Passer    ││ y 100..372
	│                          [🔑 clés USB]  (y 114..140)                   │Lobby     ││ fermé par
	│                   bandeau d'incident / notifications à y = 148         └──────────┘│ défaut
	│                        [   JOUER / CONTINUER   ] (au lobby)                        │
	└                    [Boutique]  [Missions]  [Menu]                                ┘
	- Le widget « PC d'Anga » (FPS / ping / °C) est une rangée de 3 pastilles DANS la carte de
	  progression : valeurs de PcHealth + pics des incidents (voir refreshPerf).
	- Les actions de course (Restaurer = revenir au dernier point de restauration, Passer l'étape,
	  Lobby) sont rangées derrière le bouton « ⋯ » en haut à droite, visible seulement en course ;
  le menu se referme à la mort du joueur local (HUD.CloseMenu).
- Ping : « 48 ms », puis « 2,4 s » au-delà de 999 ms (UI/HudFormat).
	- Colonne de gauche (x 16..256) : Bits, passes, bouclier, jusqu'à y = 204 au plus ; la carte
  « plantage » (Controllers/CrashLog) s'affiche dessous (x 16..312, y 216..308), au-dessus de la
  barre du boss (y ≥ 344) et à gauche de la carte de progression (x ≥ 320).
- Cibles tactiles ≥ 80 px de conception (≥ 42 px réels sur le plus petit téléphone).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Tower = require(Shared.Config.Tower)
local Products = require(Shared.Config.Products)
local NumberFormat = require(Shared.Util.NumberFormat)
local Time = require(Shared.Util.Time)
local PcHealth = require(Shared.Util.PcHealth)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Icon = require(script.Parent.Parent.Components.Icon)
local App = require(script.Parent.Parent.App)
local HudFormat = require(script.Parent.Parent.HudFormat)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)
local IncidentController = require(script.Parent.Parent.Parent.Controllers.IncidentController)
local Dialogue = require(script.Parent.Dialogue)

local New = Create.New

local HUD = {}

HUD.BitsPill = nil :: any -- cible des particules de Bits

-- Dimensions (pixels de conception)
local CARD_WIDTH = 640 -- x 320..960 : loin de la colonne de gauche (≤ 216) et du menu « ⋯ » (≥ 1048)
local CARD_HEIGHT = 96 -- la carte finit à y = 108 : pastille des clés dessous, bandeau à 148
local CHIP_WIDTH = 88
local CHIP_GAP = 6
local TOUCH = 80 -- plus petite cible tactile
local MENU_TOP = 12 + TOUCH + 8 -- le menu « ⋯ » s'ouvre sous son bouton
local MENU_AUTO_CLOSE = 8 -- secondes sans choix avant que le menu se referme

local bitsValue: TextLabel
local worldLabel: TextLabel
local stageLabel: TextLabel
local towerBar: Widgets.Bar
local timerLabel: TextLabel
local goalLabel: TextLabel
local progressCard: Frame
local keyLabel: TextLabel
local playKey: Keycap.Keycap
local actions: Frame
local skipKey: Keycap.Keycap
local menuKey: Keycap.Keycap
local menuDots: Frame
local menuClose: Frame
local menuStroke: UIStroke
local menuOpen = false
local menuToken = 0
local inRun = false
local shieldPill: Frame
local gaugeCard: Frame
local gaugeStroke: UIStroke
local gaugeLabel: TextLabel
local gaugeBar: Widgets.Bar
local shieldLabel: TextLabel
local toggleKeys: { [string]: Keycap.Keycap } = {}
local badges: { [string]: Frame } = {}
local lastBits = -1
local perfRow: Frame
local refreshPerf: (data: any) -> ()
local perfChips: { [string]: { Value: TextLabel, Stroke: UIStroke } } = {}
local lastCleared = -1

------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------

local function label(parent: Instance, props: { [string]: any }, maxSize: number): TextLabel
	props.BackgroundTransparency = 1
	props.TextScaled = true
	props.Parent = parent
	return New("TextLabel", props, { New("UITextSizeConstraint", { MaxTextSize = maxSize }) :: Instance })
end

local function buildTopLeft(layer: Frame)
	local column: Frame = New("Frame", {
		Name = "Wallet",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(240, 320),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Create.List(Enum.FillDirection.Vertical, 8) })
	local bits = Widgets.Pill("Bits", "TextBits", 200, column, false)
	bits.Root.LayoutOrder = 1
	Material.RgbEdge(bits.Root, 1.2, 0.45, 25)
	bitsValue = bits.Value
	HUD.BitsPill = bits.Root
	-- Passes activables (visibles seulement si le joueur les possède)
	for order, key in { "LowGravity", "SpeedChip" } do
		local pass = Products.PassByKey[key]
		local toggle = Keycap.new({
			Text = pass.Name,
			Variant = "Secondary",
			Size = UDim2.fromOffset(200, 44),
			LayoutOrder = 1 + order,
			Small = true,
			OnClick = function()
				local data = Store.Data()
				if data then
					Net.Fire("ToggleAssist", key, not (data.Toggles :: any)[key])
				end
			end,
			Parent = column,
		})
		toggle.Button.Visible = false
		toggleKeys[key] = toggle
	end
	-- Bouclier actif : dans la colonne de gauche (le haut à droite est au menu « ⋯ »), au-dessus
	-- de la barre du boss (BossController, y ≥ 344).
	shieldPill = New("Frame", {
		Name = "Shield",
		Size = UDim2.fromOffset(200, 40),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		LayoutOrder = 10,
		Visible = false,
		Tag = { "Glass", "RoundPill" },
		Parent = column,
	}, { New("UIStroke", { Color = Style.Color("AccentCyan"), Thickness = 2 }) :: Instance })
	shieldLabel = label(shieldPill, {
		Size = UDim2.new(1, -24, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		Text = "",
		TextColor3 = Style.Color("AccentCyan"),
		Tag = "FontHeavy",
	}, 18)
	-- Jauge du monde (RAM au monde 2, chaleur au monde 4) : Controllers/Mechanics via HUD.SetGauge.
	gaugeCard = New("Frame", {
		Name = "Gauge",
		Size = UDim2.fromOffset(200, 60),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		LayoutOrder = 9,
		Visible = false,
		Tag = { "Glass", "RoundM" },
		Parent = column,
	})
	gaugeStroke = New("UIStroke", { Color = Style.Color("Outline"), Thickness = 1.5, Parent = gaugeCard })
	gaugeLabel = label(gaugeCard, {
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.fromOffset(12, 6),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontHeavy",
	}, 18)
	gaugeBar = Widgets.Bar(UDim2.new(1, -24, 0, 12), Style.Color("Success"), gaugeCard)
	gaugeBar.Root.Position = UDim2.fromOffset(12, 38)
end

local GAUGE_GRADES: { [string]: string } = { Good = "Success", Warn = "Warning", Bad = "Danger" }

-- Jauge contextuelle du monde : `text` (ex. « RAM 72 % »), `fraction` 0..1, `grade` Good | Warn | Bad ;
-- `text` nil = jauge cachée.
function HUD.SetGauge(text: string?, fraction: number, grade: string)
	if not gaugeCard then
		return
	end
	gaugeCard.Visible = text ~= nil
	if not text then
		return
	end
	local color = Style.Color(GAUGE_GRADES[grade] or "Success")
	gaugeLabel.Text = text
	gaugeLabel.TextColor3 = if grade == "Good" then Style.Color("TextPrimary") else color
	gaugeStroke.Color = if grade == "Bad" then color else Style.Color("Outline")
	gaugeBar:SetColor(color)
	gaugeBar:Set(math.clamp(fraction, 0, 1), false)
end

-- Pastille de mesure du PC d'Anga (icône + valeur), verre sombre bordé de la couleur de la note.
local function perfChip(key: string, iconKind: string, order: number)
	local chip: Frame = New("Frame", {
		Name = `Perf{key}`,
		Size = UDim2.fromOffset(CHIP_WIDTH, 28),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Tag = { "GlassSunken", "RoundPill" },
		Parent = perfRow,
	})
	local stroke: UIStroke = New("UIStroke", {
		Color = Style.Color("TextMuted"),
		Transparency = 0.45,
		Thickness = 1.5,
		Parent = chip,
	})
	local icon = Icon.new(iconKind, 16, "TextMuted")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.Parent = chip
	local value = label(chip, {
		Position = UDim2.fromOffset(28, 4),
		Size = UDim2.new(1, -36, 1, -8),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontHeavy",
	}, 16)
	perfChips[key] = { Value = value, Stroke = stroke }
end

local function buildProgress(layer: Frame)
	progressCard = New("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	})
	Material.RgbEdge(progressCard, 1.2, 0.35, 30)
	-- Ligne 1 : monde (gauche) · chrono (droite)
	worldLabel = label(progressCard, {
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.new(1, -(36 + 150 + 8), 0, 26),
		Text = "LOBBY",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontHeavy",
	}, 22)
	timerLabel = label(progressCard, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 8),
		Size = UDim2.fromOffset(150, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontHeavy",
	}, 20)
	-- Ligne 2 : barre de la tour · étape
	towerBar = Widgets.Bar(UDim2.new(1, -(36 + 110), 0, 12), Style.Color("AccentViolet"), progressCard)
	towerBar.Root.Position = UDim2.fromOffset(18, 42)
	-- Repères des mondes sur la barre de la tour
	for world = 1, Tower.WORLD_COUNT - 1 do
		New("Frame", {
			Position = UDim2.new(world / Tower.WORLD_COUNT, -1, 0, -2),
			Size = UDim2.new(0, 2, 1, 4),
			BackgroundColor3 = Style.Color("BgDeep"),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = towerBar.Root,
		})
	end
	stageLabel = label(progressCard, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 38),
		Size = UDim2.fromOffset(104, 20),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Style.Color("CurrencyBits"),
		Tag = "FontHeavy",
	}, 17)
	-- Ligne 3 : but du moment (gauche) · PC d'Anga en 3 pastilles (droite)
	local chipsWidth = 3 * CHIP_WIDTH + 2 * CHIP_GAP
	goalLabel = label(progressCard, {
		Position = UDim2.fromOffset(18, 62),
		Size = UDim2.new(1, -(36 + chipsWidth + 12), 0, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontBold",
	}, 18)
	perfRow = New("Frame", {
		Name = "PcPerformance",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 61),
		Size = UDim2.fromOffset(chipsWidth, 28),
		BackgroundTransparency = 1,
		Parent = progressCard,
	}, {
		Create.List(Enum.FillDirection.Horizontal, CHIP_GAP, {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}) :: Instance,
	})
	perfChip("Fps", "Bolt", 1)
	perfChip("Ping", "Elevator", 2)
	perfChip("Temp", "Heat", 3)
	-- Clés USB dorées : petite pastille sous la carte (monde courant + total)
	keyLabel = label(progressCard, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(220, 26),
		BackgroundTransparency = Theme.Alpha.Glass,
		Text = "",
		TextColor3 = Style.Color("CurrencyBits"),
		Tag = { "FontBold", "Glass", "RoundL" },
	}, 16)
	keyLabel.BackgroundTransparency = Theme.Alpha.Glass -- `label` met un fond transparent
end

-- Ouvre / ferme le menu « ⋯ » des actions de course (refermé tout seul après un moment).
local function setMenu(open: boolean)
	open = open and inRun
	if menuOpen == open then
		return
	end
	menuOpen = open
	menuToken += 1
	actions.Visible = open
	menuDots.Visible = not open
	menuClose.Visible = open
	menuStroke.Transparency = if open then 0.05 else 0.45
	if open then
		Motion.Pop(actions, 0.05)
		local token = menuToken
		task.delay(MENU_AUTO_CLOSE, function()
			if token == menuToken then
				setMenu(false)
			end
		end)
	end
end

local function buildRight(layer: Frame)
	-- Bouton « ⋯ » : verre de l'app, liseré violet ; trois points (fermé) ou croix (ouvert).
	menuKey = Keycap.new({
		Variant = "Ghost",
		IconOnly = true,
		Size = UDim2.fromOffset(TOUCH, TOUCH),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		OnClick = function()
			setMenu(not menuOpen)
		end,
		Parent = layer,
	})
	menuKey.Button.Name = "RunMenu"
	menuKey.Button.Visible = false
	local cap = menuKey.Button:FindFirstChild("Cap") :: Frame
	local content = cap:FindFirstChild("Content") :: Frame
	menuStroke = New("UIStroke", {
		Color = Style.Color("AccentViolet"),
		Thickness = 2,
		Transparency = 0.45,
		Parent = cap,
	})
	menuDots = New("Frame", {
		Name = "Dots",
		Size = UDim2.fromOffset(44, 12),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = content,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 6, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}) :: Instance,
	})
	for _ = 1, 3 do
		New("Frame", {
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Style.Color("TextPrimary"),
			BorderSizePixel = 0,
			Parent = menuDots,
		}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance })
	end
	menuClose = Icon.new("Close", 28, "TextPrimary")
	menuClose.LayoutOrder = 4
	menuClose.Visible = false
	menuClose.Parent = content

	-- Menu déroulant : panneau de verre bordé de violet, sous le bouton, aligné à droite.
	actions = New("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, MENU_TOP),
		Size = UDim2.fromOffset(216, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	}, {
		Create.List(Enum.FillDirection.Vertical, 8) :: Instance,
		Create.Padding(8) :: Instance,
		New("UIStroke", { Color = Style.Color("AccentViolet"), Thickness = 1.5, Transparency = 0.35 }) :: Instance,
	})
	local function pick(action: () -> ()): () -> ()
		return function()
			setMenu(false)
			action()
		end
	end
	-- « Restaurer » : les checkpoints sont des points de restauration (v3).
	Keycap.new({
		Text = "Restaurer",
		Icon = "Check",
		Variant = "Ghost",
		Size = UDim2.fromOffset(200, TOUCH),
		LayoutOrder = 1,
		Small = true,
		OnClick = pick(function()
			Net.Fire("ToCheckpoint")
		end),
		Parent = actions,
	})
	skipKey = Keycap.new({
		Text = "Passer l'étape",
		Icon = "Bolt",
		Variant = "Gold",
		Size = UDim2.fromOffset(200, TOUCH),
		LayoutOrder = 2,
		Small = true,
		OnClick = pick(function()
			local product = Products.ProductByKey.Skip
			if product and product.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.Id)
			end
		end),
		Parent = actions,
	})
	skipKey.Button.Visible = false
	Keycap.new({
		Text = "Lobby",
		Icon = "Elevator",
		Variant = "Ghost",
		Size = UDim2.fromOffset(200, TOUCH),
		LayoutOrder = 3,
		Small = true,
		OnClick = pick(function()
			Net.Fire("ToLobby")
		end),
		Parent = actions,
	})
end

local function buildPlay(layer: Frame)
	playKey = Keycap.new({
		Text = "JOUER",
		Variant = "Primary",
		Size = UDim2.fromOffset(380, 84),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -128),
		OnClick = function()
			Net.Fire("Resume")
		end,
		Parent = layer,
	})
	playKey.Button.Visible = false
end

local DOCK = {
	{ Name = "Shop", Text = "Boutique", Icon = "Shop", Key = Enum.KeyCode.B },
	{ Name = "Missions", Text = "Missions", Icon = "Quest", Key = Enum.KeyCode.Q },
	{ Name = "Menu", Text = "Menu", Icon = "Menu", Key = Enum.KeyCode.M },
}

local function buildDock(layer: Frame)
	local width = #DOCK * 110 + (#DOCK - 1) * 8 + 24
	local dock: Frame = New("Frame", {
		Name = "Dock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(width, 96),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}) :: Instance,
		New("UIStroke", { Color = Style.Color("Outline"), Thickness = 1 }) :: Instance,
	})
	for index, item in DOCK do
		local key = Keycap.new({
			Text = item.Text,
			Icon = item.Icon,
			Variant = "Secondary",
			Size = UDim2.fromOffset(110, 76),
			LayoutOrder = index,
			Small = true,
			OnClick = function()
				App.Toggle(item.Name)
			end,
			Parent = dock,
		})
		-- Icône au-dessus du texte : toute la largeur est disponible pour le mot.
		local content = key.Button:FindFirstChild("Content", true)
		local layout = content and content:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.Padding = UDim.new(0, 4)
		end
		key.Label.Size = UDim2.new(0, 0, 0, 18)
		local limit = key.Label:FindFirstChildOfClass("UISizeConstraint")
		if limit then
			limit.MaxSize = Vector2.new(90, math.huge)
		end
		if index == 1 then
			App.DockFocus = key.Button
		end
		badges[item.Name] = Widgets.Badge(key.Button)
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		for _, item in DOCK do
			if input.KeyCode == item.Key then
				App.Toggle(item.Name)
			end
		end
	end)
end

------------------------------------------------------------------------------------
-- Rafraîchissement
------------------------------------------------------------------------------------

-- Le but du moment, en une phrase simple.
local function goalText(state: any): string
	local data = state.Data
	if state.AtLobby then
		return if data.Stage > 0 then "Appuie sur CONTINUER !" else "Appuie sur JOUER pour grimper !"
	end
	if not data.RunStarted then
		return "Passe la ligne de départ !"
	end
	local world = Tower.WorldOf(data.Stage)
	if data.Stage > 0 and data.Stage == Tower.TerminalStage(world) and data.Cleared < world then
		return "Élimine les virus au terminal 💻"
	end
	if data.Stage == Tower.TOTAL_STAGES and data.Cleared >= Tower.WORLD_COUNT then
		return "Touche le cœur de la puce pour gagner !"
	end
	return "Va au prochain point de restauration !"
end

local function refreshFull(state: any)
	local data = state.Data
	local world = if data.Stage > 0 then Tower.RunWorld(data.Stage, data.Cleared) else 0
	local def = Tower.Worlds[math.max(world, 1)]
	if state.AtLobby then
		worldLabel.Text = "LOBBY · Salle de démarrage"
	elseif data.Stage == 0 then
		worldLabel.Text = `DÉPART · {def.Name}`
	else
		worldLabel.Text = `MONDE {world} · {def.Name}`
	end
	stageLabel.Text = `Étape {data.Stage}/{Tower.TOTAL_STAGES}`
	towerBar:Set(data.Stage / Tower.TOTAL_STAGES)
	towerBar:SetColor(if state.AtLobby then Style.Color("AccentViolet") else Color3.fromHex(def.Primary))
	goalLabel.Text = goalText(state)
	local keysTotal, keysHere = 0, 0
	local inWorld = world > 0 and not state.AtLobby
	for id in data.UsbKeys do
		keysTotal += 1
		if inWorld and string.match(id, "^W(%d+)K") == tostring(world) then
			keysHere += 1
		end
	end
	keyLabel.Text = if inWorld
		then `🔑 {keysHere}/{Tower.USB_KEYS_PER_WORLD} ici · {keysTotal}/{Tower.WORLD_COUNT * Tower.USB_KEYS_PER_WORLD}`
		else `🔑 Clés USB : {keysTotal}/{Tower.WORLD_COUNT * Tower.USB_KEYS_PER_WORLD}`
	keyLabel.Visible = keysTotal > 0 or inWorld
	playKey.Button.Visible = state.AtLobby
	Dialogue.SetLift(if state.AtLobby then 84 + 10 else 0) -- la boîte ne recouvre pas JOUER
	playKey:SetText(if data.Stage > 0 then `CONTINUER · Étape {data.Stage}` else "JOUER")
	-- Menu « ⋯ » : seulement en course (au lobby, rien à restaurer ni à passer).
	inRun = not state.AtLobby
	menuKey.Button.Visible = inRun
	if not inRun then
		setMenu(false)
	end
	-- Même règle que ProgressService.CanSkip : le repaire de LAGZ ne se passe pas.
	skipKey.Button.Visible = Products.ProductByKey.Skip.Id ~= 0 and data.Stage < Tower.TOTAL_STAGES - 1
	for key, toggle in toggleKeys do
		local owned = state.Passes[key] == true
		toggle.Button.Visible = owned
		if owned then
			local on = (data.Toggles :: any)[key] == true
			toggle:SetVariant(if on then "Success" else "Secondary")
			toggle:SetText(`{Products.PassByKey[key].Name} : {if on then "ON" else "OFF"}`)
		end
	end
	-- Pastille : récompense quotidienne ou mission prête
	local today = math.floor(Store.UnixNow() / 86400)
	local missionReady = data.Daily.LastClaimDay ~= today
	for _, mission in data.Missions.List do
		if not mission.Claimed and mission.Progress >= mission.Target then
			missionReady = true
		end
	end
	badges.Missions.Visible = missionReady
end

local GRADE_COLOR: { [string]: string } = { Good = "Success", Warn = "Warning", Bad = "Danger" }

local function setPerf(key: string, value: string, grade: string)
	local chip = perfChips[key]
	local color = Style.Color(GRADE_COLOR[grade] or "TextMuted")
	chip.Value.Text = value
	chip.Value.TextColor3 = color
	chip.Stroke.Color = color
end

-- Valeurs du tableau du scénario, qui « vivent » un peu, avec les pics des incidents.
refreshPerf = function(data: any)
	local cleared = if type(data.Cleared) == "number" then data.Cleared else 0
	if cleared ~= lastCleared then
		if lastCleared >= 0 and cleared > lastCleared then
			Motion.Pop(perfRow, 0.12)
		end
		lastCleared = cleared
	end
	local base = PcHealth.Stats(cleared)
	local t = os.clock()
	local fps = base.Fps * (1 + math.noise(t * 0.7, 1.3) * 0.2)
	local ping = base.Ping * (1 + math.noise(t * 0.9, 7.1) * 0.25)
	local temp = base.Temp + math.noise(t * 0.3, 3.7) * 2
	local kind, phase = IncidentController.Current()
	if phase == "Active" then
		if kind == "Freeze" then
			fps = 0
		elseif kind == "Lag" then
			ping = math.max(ping, 800) + (math.noise(t * 4, 2.2) + 0.5) * 1600
			fps *= 0.5
		elseif kind == "Popups" then
			fps *= 0.5
			ping += 200
		elseif kind == "Overheat" then
			temp = math.min(temp + 18, 115)
			fps *= 0.7
		end
		if kind == "Blackout" then
			-- Plus de courant : plus de mesures.
			setPerf("Fps", "--", "Bad")
			setPerf("Ping", "--", "Bad")
			setPerf("Temp", "--", "Bad")
			return
		elseif kind == "Corruption" then
			setPerf("Fps", "ERR?!", "Bad")
		else
			fps = math.max(math.floor(fps + 0.5), 0)
			setPerf("Fps", `{fps} FPS`, PcHealth.Grade("Fps", fps))
		end
	else
		fps = math.max(math.floor(fps + 0.5), 1)
		setPerf("Fps", `{fps} FPS`, PcHealth.Grade("Fps", fps))
	end
	ping = math.max(math.floor(ping + 0.5), 1)
	temp = math.floor(temp + 0.5)
	setPerf("Ping", HudFormat.Ping(ping), PcHealth.Grade("Ping", ping))
	setPerf("Temp", `{temp} °C`, PcHealth.Grade("Temp", temp))
end

local function refreshFast()
	local state = Store.State
	if not state then
		return
	end
	local bits = Store.Bits()
	if bits ~= lastBits then
		if lastBits >= 0 and bits > lastBits then
			Motion.Pop(bitsValue.Parent :: GuiObject, 0.06)
		end
		bitsValue.Text = NumberFormat.Compact(bits)
		lastBits = bits
	end
	timerLabel.Text = if state.Data.RunStarted then `⏱ {Time.Clock(Store.RunTime())}` else ""
	refreshPerf(state.Data)
	local shieldLeft = state.ShieldUntil - Store.UnixNow()
	shieldPill.Visible = shieldLeft > 0
	if shieldLeft > 0 then
		shieldLabel.Text = `🛡 Bouclier {math.ceil(shieldLeft)} s`
	end
end

-- Referme le menu « ⋯ » (mort du joueur, écran plein…).
function HUD.CloseMenu()
	if actions then
		setMenu(false)
	end
end

-- Mort du joueur local : le menu « ⋯ » ne reste pas ouvert par-dessus la réapparition.
local function watchDeaths()
	local player = Players.LocalPlayer
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(HUD.CloseMenu)
		end
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function HUD.Mount(layer: Frame)
	buildTopLeft(layer)
	buildProgress(layer)
	buildRight(layer)
	buildPlay(layer)
	buildDock(layer)
	watchDeaths()
	Store.Changed:Connect(refreshFull)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			refreshFast()
		end
	end)
end

function HUD.SetBadge(name: string, visible: boolean)
	local badge = badges[name]
	if badge then
		badge.Visible = visible
	end
end

return HUD
