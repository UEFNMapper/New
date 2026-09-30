--!strict
--[[
	HUD du deathrun : très peu d'éléments, lisibles par un enfant.
	┌ [Bits]                 MONDE 2 · Memory Lanes · Étape 7/35          [⚙]   ┐
	│ [passes activables]    ▓▓▓▓▓░░░░░░░ tour     ⏱ 4:07.3          [bouclier] │
	│ [PC d'Anga : FPS /     « ton but en une phrase »          [↺ Checkpoint]   │
	│  ping / °C]                                                                 │
	│                                                           [⏭ Passer]      │
	│                        [   JOUER / CONTINUER   ] (au lobby) [⌂ Lobby]      │
	└                    [Boutique]  [Missions]  [Menu]                          ┘
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
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)
local IncidentController = require(script.Parent.Parent.Parent.Controllers.IncidentController)
local Dialogue = require(script.Parent.Dialogue)

local New = Create.New

local HUD = {}

HUD.BitsPill = nil :: any -- cible des particules de Bits

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
local shieldPill: Frame
local shieldLabel: TextLabel
local toggleKeys: { [string]: Keycap.Keycap } = {}
local badges: { [string]: Frame } = {}
local lastBits = -1
local perfCard: Frame
local refreshPerf: (data: any) -> ()
local perfValues: { [string]: TextLabel } = {}
local lastCleared = -1

------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------

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
	-- « Performance du PC » d'Anga (docs/SCENARIO.md §3) : sous le portefeuille (et les passes),
	-- à gauche, loin de la carte de progression, des actions et du joystick.
	perfCard = New("Frame", {
		Name = "PcPerformance",
		Size = UDim2.fromOffset(200, 112),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		LayoutOrder = 10,
		Tag = { "Glass", "RoundM" },
		Parent = column,
	}, {
		New("UIStroke", { Color = Style.Color("Stroke"), Transparency = Theme.Alpha.StrokeSoft, Thickness = 1 }),
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 16),
		BackgroundTransparency = 1,
		Text = "PC D'ANGA",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextCaption",
		Parent = perfCard,
	})
	for index, row in
		{
			{ Key = "Fps", Label = "FPS", Icon = "Bolt" },
			{ Key = "Ping", Label = "Ping", Icon = "Elevator" },
			{ Key = "Temp", Label = "Temp.", Icon = "Heat" },
		}
	do
		local y = 26 + (index - 1) * 28
		local icon = Icon.new(row.Icon, 20, "TextMuted")
		icon.Position = UDim2.fromOffset(12, y + 2)
		icon.Parent = perfCard
		New("TextLabel", {
			Position = UDim2.fromOffset(40, y),
			Size = UDim2.fromOffset(60, 24),
			BackgroundTransparency = 1,
			Text = row.Label,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
			TextColor3 = Style.Color("TextMuted"),
			Tag = "FontBold",
			Parent = perfCard,
		})
		perfValues[row.Key] = New("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, y),
			Size = UDim2.fromOffset(92, 24),
			BackgroundTransparency = 1,
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = 20,
			TextColor3 = Style.Color("TextPrimary"),
			Tag = "FontHeavy",
			Parent = perfCard,
		})
	end
end

local function label(parent: Instance, props: { [string]: any }, maxSize: number): TextLabel
	props.BackgroundTransparency = 1
	props.TextScaled = true
	props.Parent = parent
	return New("TextLabel", props, { New("UITextSizeConstraint", { MaxTextSize = maxSize }) :: Instance })
end

local function buildProgress(layer: Frame)
	progressCard = New("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(460, 96),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	})
	Material.RgbEdge(progressCard, 1.2, 0.35, 30)
	worldLabel = label(progressCard, {
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.new(1, -170, 0, 26),
		Text = "LOBBY",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontHeavy",
	}, 22)
	stageLabel = label(progressCard, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 8),
		Size = UDim2.fromOffset(140, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Style.Color("CurrencyBits"),
		Tag = "FontHeavy",
	}, 22)
	towerBar = Widgets.Bar(UDim2.new(1, -36, 0, 12), Style.Color("AccentViolet"), progressCard)
	towerBar.Root.Position = UDim2.fromOffset(18, 40)
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
	goalLabel = label(progressCard, {
		Position = UDim2.fromOffset(18, 60),
		Size = UDim2.new(1, -170, 0, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontBold",
	}, 18)
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
	timerLabel = label(progressCard, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 60),
		Size = UDim2.fromOffset(140, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Style.Color("TextPrimary"),
		Tag = "FontHeavy",
	}, 20)
end

local function buildRight(layer: Frame)
	Keycap.new({
		Icon = "Menu",
		IconOnly = true,
		Variant = "Secondary",
		-- Tailles de conception ≥ 80 : ≥ 42 px réels sur le plus petit téléphone (échelle 0,52).
		Size = UDim2.fromOffset(80, 80),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		OnClick = function()
			App.Toggle("Menu")
		end,
		Parent = layer,
	})
	shieldPill = New("Frame", {
		Name = "Shield",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 102),
		Size = UDim2.fromOffset(190, 40),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Visible = false,
		Tag = { "Glass", "RoundPill" },
		Parent = layer,
	}, { New("UIStroke", { Color = Style.Color("AccentCyan"), Thickness = 2 }) :: Instance })
	shieldLabel = label(shieldPill, {
		Size = UDim2.new(1, -24, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		Text = "",
		TextColor3 = Style.Color("AccentCyan"),
		Tag = "FontHeavy",
	}, 18)

	-- Actions pendant l'ascension
	actions = New("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 10),
		Size = UDim2.fromOffset(200, 3 * 84 + 2 * 10),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Create.List(Enum.FillDirection.Vertical, 10) })
	Keycap.new({
		Text = "Checkpoint",
		Variant = "Secondary",
		Size = UDim2.fromOffset(200, 84),
		LayoutOrder = 1,
		Small = true,
		OnClick = function()
			Net.Fire("ToCheckpoint")
		end,
		Parent = actions,
	})
	skipKey = Keycap.new({
		Text = "Passer l'étape",
		Variant = "Gold",
		Size = UDim2.fromOffset(200, 84),
		LayoutOrder = 2,
		Small = true,
		OnClick = function()
			local product = Products.ProductByKey.Skip
			if product and product.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.Id)
			end
		end,
		Parent = actions,
	})
	skipKey.Button.Visible = false
	Keycap.new({
		Text = "Lobby",
		Variant = "Ghost",
		Size = UDim2.fromOffset(200, 84),
		LayoutOrder = 3,
		Small = true,
		OnClick = function()
			Net.Fire("ToLobby")
		end,
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
	})
	Material.RgbEdge(dock, 1.2, 0.4, 20)
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
		key.Label.Size = UDim2.new(0, 0, 0, 16)
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
	return "Atteins le prochain checkpoint !"
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
	actions.Visible = not state.AtLobby
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
	local target = perfValues[key]
	target.Text = value
	target.TextColor3 = Style.Color(GRADE_COLOR[grade] or "TextMuted")
end

-- Valeurs du tableau du scénario, qui « vivent » un peu, avec les pics des incidents.
refreshPerf = function(data: any)
	local cleared = if type(data.Cleared) == "number" then data.Cleared else 0
	if cleared ~= lastCleared then
		if lastCleared >= 0 and cleared > lastCleared then
			Motion.Pop(perfCard, 0.1)
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
			setPerf("Fps", tostring(fps), PcHealth.Grade("Fps", fps))
		end
	else
		fps = math.max(math.floor(fps + 0.5), 1)
		setPerf("Fps", tostring(fps), PcHealth.Grade("Fps", fps))
	end
	ping = math.max(math.floor(ping + 0.5), 1)
	temp = math.floor(temp + 0.5)
	setPerf("Ping", `{NumberFormat.Grouped(ping)} ms`, PcHealth.Grade("Ping", ping))
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

function HUD.Mount(layer: Frame)
	buildTopLeft(layer)
	buildProgress(layer)
	buildRight(layer)
	buildPlay(layer)
	buildDock(layer)
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
