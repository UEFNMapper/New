--!strict
--[[
	HUD : l'interface permanente, volontairement minimale.
	┌ Bits / Chips / collecteur            Benchmark · Gen · effets actifs            toasts ┐
	│                                                                      Carte OBJECTIF   │
	│ Bulle d'Anga (tutoriel)                                              (1 seul CTA)     │
	└ Jauges ⚡ / 🌡                 [Composants][Nanobots][Quêtes][Boutique][Étages][Menu] ┘
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Zones = require(Shared.Config.Zones)
local GameConfig = require(Shared.Config.GameConfig)
local Modules = require(Shared.Config.Modules)
local Formulas = require(Shared.Economy.Formulas)
local NumberFormat = require(Shared.Util.NumberFormat)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Icon = require(script.Parent.Parent.Components.Icon)
local Dialogue = require(script.Parent.Dialogue)
local App = require(script.Parent.Parent.App)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)

local New = Create.New

local HUD = {}

HUD.BitsPill = nil :: any -- cible des particules de collecte
HUD.OnObjective = nil :: ((action: string, arg: any) -> ())?

local bitsValue: TextLabel
local bitsRate: TextLabel
local chipsValue: TextLabel
local collectorCard: Frame
local collectorBar: Widgets.Bar
local collectorText: TextLabel
local benchValue: TextLabel
local genLabel: TextLabel
local effectsRow: Frame
local objectiveTitle: TextLabel
local objectiveText: TextLabel
local objectiveBar: Widgets.Bar
local objectiveKey: Keycap.Keycap
local objectiveCard: Frame
local powerBar: Widgets.Bar
local heatBar: Widgets.Bar
local powerText: TextLabel
local heatText: TextLabel
local heatRow: Frame
local gauges: Frame
local badges: { [string]: Frame } = {}
local objectiveAction: string = ""
local objectiveArg: any = nil
local lastBits = 0
local lastChips = -1
local warnedHeat = false
local warnedPower = false

local function formatBits(n: number): string
	return NumberFormat.Compact(n)
end

------------------------------------------------------------------------------------
-- Objectif : le prochain but du joueur, calculé à partir de l'état
------------------------------------------------------------------------------------

type Objective = {
	Title: string,
	Text: string,
	Ratio: number?,
	Button: string?,
	Action: string,
	Arg: any,
	Ready: boolean,
}

local TUTORIAL_TEXT = {
	[2] = "Tu vois ces paquets de lumière ? Ce sont tes données ! Suis le faisceau et marche sur le collecteur doré pour encaisser tes Bits.",
	[3] = "Joli ! Maintenant on améliore ta Cellule VoltCore. Plus de niveaux, plus de Bits. Clique sur « AMÉLIORER » à droite.",
	[4] = "Encore une ! Petit secret : aux niveaux 10, 25, 50… la production DOUBLE.",
	[5] = "Prochaine étape : débloquer Memory Lanes, l'étage de la RAM. Collecte et améliore jusqu'à 25K Bits !",
	[6] = "Bienvenue dans la RAM ! Va au terminal violet et ouvre ta première capsule de Nanobot.",
}

local function computeObjective(state: any): Objective
	local data = state.Data
	local production = state.Production
	local bits = Store.Bits()
	if not data.PoweredOn then
		-- Le CTA d'allumage est l'écran central (Moments) : pas de second bouton ici.
		return {
			Title = "DÉMARRAGE",
			Text = "Allume ton PC pour lancer la production.",
			Action = "PowerOn",
			Arg = nil,
			Ready = true,
		}
	end
	if data.Tutorial == 2 then
		local pending = Store.Pending()
		return {
			Title = "TUTORIEL",
			Text = "Marche sur le collecteur doré pour encaisser.",
			Ratio = math.min(pending / 10, 1),
			Action = "",
			Arg = nil,
			Ready = false,
		}
	end
	if data.Tutorial == 3 or data.Tutorial == 4 then
		local def = Modules.Get("Z1M1")
		local level = data.Levels.Z1M1 or 0
		local cost = if def then Formulas.UpgradeCost(def.BaseCost, level, GameConfig.LevelGrowth) else 0
		return {
			Title = "TUTORIEL",
			Text = "Améliore la Cellule VoltCore.",
			Ratio = math.min(bits / math.max(cost, 1), 1),
			Button = "AMÉLIORER",
			Action = "OpenModule",
			Arg = "Z1M1",
			Ready = bits >= cost,
		}
	end
	-- Alertes matérielles prioritaires
	if production.ThermalEfficiency < 0.9 then
		if data.Zone >= GameConfig.Cooling.UnlockZone then
			return {
				Title = "SURCHAUFFE",
				Text = `Ton PC tourne à {NumberFormat.Percent(production.ThermalEfficiency)}. Améliore tes radiateurs.`,
				Button = "REFROIDIR",
				Action = "OpenZone",
				Arg = GameConfig.Cooling.UnlockZone,
				Ready = true,
			}
		end
		return {
			Title = "SURCHAUFFE",
			Text = "Le ventirad d'origine ne suffit plus : débloque la Cryo Tower.",
			Button = "VOIR",
			Action = "OpenZone",
			Arg = data.Zone,
			Ready = true,
		}
	end
	if production.PowerEfficiency < 0.9 then
		return {
			Title = "ALIMENTATION",
			Text = `Pas assez de Watts ({NumberFormat.Percent(production.PowerEfficiency)}). Améliore ton bloc d'alimentation.`,
			Button = "ALIMENTER",
			Action = "OpenZone",
			Arg = 1,
			Ready = true,
		}
	end
	if data.Tutorial == 6 then
		return {
			Title = "TUTORIEL",
			Text = "Ouvre ta première capsule de Nanobot.",
			Button = "CAPSULES",
			Action = "OpenNanobots",
			Arg = "Capsules",
			Ready = true,
		}
	end
	local nextZone = Zones[data.Zone + 1]
	if nextZone then
		local ratio = bits / nextZone.UnlockCost
		return {
			Title = "OBJECTIF",
			Text = `Débloque {nextZone.Name} ({NumberFormat.Compact(nextZone.UnlockCost)} Bits)`,
			Ratio = math.min(ratio, 1),
			Button = if ratio >= 1 then "DÉBLOQUER" else nil,
			Action = "Unlock",
			Arg = data.Zone + 1,
			Ready = ratio >= 1,
		}
	end
	local phases = GameConfig.SingularityPhases
	if data.SingularityPhase < #phases then
		local cost = phases[data.SingularityPhase + 1]
		return {
			Title = "SINGULARITÉ",
			Text = `Phase {data.SingularityPhase + 1}/{#phases} : {NumberFormat.Compact(cost)} Bits`,
			Ratio = math.min(bits / cost, 1),
			Button = "CONSTRUIRE",
			Action = "OpenBios",
			Arg = "Singularity",
			Ready = bits >= cost,
		}
	end
	return {
		Title = "PRESTIGE",
		Text = `Reboot : +{state.FirmwarePreview} Firmware pour la Génération {data.Generation + 1}.`,
		Button = "REBOOT",
		Action = "OpenBios",
		Arg = "Reboot",
		Ready = true,
	}
end

------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------

local function buildTopLeft(layer: Frame)
	local column: Frame = New("Frame", {
		Name = "Wallet",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(280, 320),
		BackgroundTransparency = 1,
		Parent = layer,
	}, {
		Create.List(Enum.FillDirection.Vertical, 8),
	})
	local bits = Widgets.Pill("Bits", "TextBits", 270, column, true)
	bits.Root.LayoutOrder = 1
	Material.RgbEdge(bits.Root, 1.2, 0.45, 25)
	bitsValue = bits.Value
	bitsRate = bits.Sub :: TextLabel
	HUD.BitsPill = bits.Root

	local chips = Widgets.Pill("Chips", "TextChips", 170, column, false)
	chips.Root.LayoutOrder = 2
	chipsValue = chips.Value

	collectorCard = New("Frame", {
		Name = "Collector",
		Size = UDim2.fromOffset(230, 46),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		Tag = { "Glass", "RoundM" },
		Parent = column,
	})
	collectorText = New("TextLabel", {
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundTransparency = 1,
		Text = "Collecteur",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextCaption",
		Parent = collectorCard,
	})
	collectorBar = Widgets.Bar(UDim2.new(1, -24, 0, 10), Style.Color("CurrencyBits"), collectorCard)
	collectorBar.Root.Position = UDim2.fromOffset(12, 26)
end

local function buildTopCenter(layer: Frame)
	local center: Frame = New("Frame", {
		Name = "Benchmark",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(300, 56),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundPill" },
		Parent = layer,
	})
	Material.RgbEdge(center, 1.2, 0.35, 30)
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 6),
		Size = UDim2.new(1, -110, 0, 14),
		BackgroundTransparency = 1,
		Text = "BENCHMARK",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextCaption",
		Parent = center,
	})
	benchValue = New("TextLabel", {
		Position = UDim2.fromOffset(24, 20),
		Size = UDim2.new(1, -110, 0, 28),
		BackgroundTransparency = 1,
		Text = "0 FLOPS",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextNumber",
		Parent = center,
	})
	local gen: Frame = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(76, 36),
		BorderSizePixel = 0,
		Tag = { "FillViolet", "RoundPill" },
		Parent = center,
	})
	genLabel = New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "GEN 1",
		Tag = "TextKey",
		Parent = gen,
	})
	effectsRow = New("Frame", {
		Name = "Effects",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(600, 30),
		BackgroundTransparency = 1,
		Parent = layer,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
end

local function buildObjective(layer: Frame)
	objectiveCard = New("Frame", {
		Name = "Objective",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.46, 0),
		Size = UDim2.fromOffset(300, 150),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	}, {
		New("UIShadow", {
			BlurRadius = UDim.new(0, 18),
			Transparency = 0.5,
			Offset = UDim2.fromOffset(0, 6),
			Color = Style.Color("BgDeep"),
		}),
	})
	Material.Glass(objectiveCard, true)
	Material.RgbEdge(objectiveCard, 1.5, 0.25)
	objectiveTitle = New("TextLabel", {
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 16),
		BackgroundTransparency = 1,
		Text = "OBJECTIF",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextCaption",
		Parent = objectiveCard,
	})
	objectiveText = New("TextLabel", {
		Position = UDim2.fromOffset(16, 30),
		Size = UDim2.new(1, -32, 0, 44),
		BackgroundTransparency = 1,
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Tag = "TextHeading",
		Parent = objectiveCard,
	})
	objectiveBar = Widgets.Bar(UDim2.new(1, -32, 0, 8), Style.Color("AccentViolet"), objectiveCard)
	objectiveBar.Root.Position = UDim2.fromOffset(16, 80)
	objectiveKey = Keycap.new({
		Text = "",
		Variant = "Primary",
		Size = UDim2.new(1, -32, 0, 46),
		Position = UDim2.fromOffset(16, 96),
		OnClick = function()
			if HUD.OnObjective then
				HUD.OnObjective(objectiveAction, objectiveArg)
			end
		end,
		Parent = objectiveCard,
	})
end

local function gauge(parent: Frame, iconKind: string, color: string, order: number): (Frame, Widgets.Bar, TextLabel)
	local row: Frame = New("Frame", {
		Name = `Gauge_{iconKind}`,
		Size = UDim2.fromOffset(226, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local icon = Icon.new(iconKind, 20, color)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 0, 0.5, 0)
	icon.Parent = row
	local bar = Widgets.Bar(UDim2.new(1, -96, 0, 8), Style.Color(color), row)
	bar.Root.AnchorPoint = Vector2.new(0, 0.5)
	bar.Root.Position = UDim2.new(0, 28, 0.5, 0)
	local text: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(60, 20),
		BackgroundTransparency = 1,
		Text = "0 %",
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "TextCaption",
		Parent = row,
	})
	return row, bar, text
end

local function buildBottomLeft(layer: Frame)
	-- Jauges dans la colonne du portefeuille (haut gauche) : jamais sous le dock, même sur petit écran.
	local wallet = layer:FindFirstChild("Wallet")
	gauges = New("Frame", {
		Name = "Gauges",
		Size = UDim2.fromOffset(250, 74),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		LayoutOrder = 4,
		Tag = { "Glass", "RoundM" },
		Parent = wallet or layer,
	}, {
		Create.List(Enum.FillDirection.Vertical, 4, { VerticalAlignment = Enum.VerticalAlignment.Center }) :: Instance,
		Create.Padding(8, 12),
	})
	local _powerRow: Frame
	_powerRow, powerBar, powerText = gauge(gauges, "Bolt", "CurrencyBits", 1)
	heatRow, heatBar, heatText = gauge(gauges, "Heat", "AccentCyan", 2)
end

local DOCK = {
	{ Name = "Components", Text = "Composants", Icon = "Cpu", Key = Enum.KeyCode.C },
	{ Name = "Nanobots", Text = "Nanobots", Icon = "Bot", Key = Enum.KeyCode.N },
	{ Name = "Quests", Text = "Quêtes", Icon = "Quest", Key = Enum.KeyCode.Q },
	{ Name = "Shop", Text = "Boutique", Icon = "Shop", Key = Enum.KeyCode.B },
	{ Name = "Elevator", Text = "Étages", Icon = "Elevator", Key = Enum.KeyCode.T },
	{ Name = "Menu", Text = "Menu", Icon = "Menu", Key = Enum.KeyCode.M },
}

local function buildDock(layer: Frame)
	local dock: Frame = New("Frame", {
		Name = "Dock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(6 * 96 + 5 * 8 + 24, 96),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}) :: Instance,
		New("UIShadow", {
			BlurRadius = UDim.new(0, 18),
			Transparency = 0.45,
			Offset = UDim2.fromOffset(0, 6),
			Color = Style.Color("BgDeep"),
		}),
	})
	Material.RgbEdge(dock, 1.2, 0.4, 20)
	for index, item in DOCK do
		local key = Keycap.new({
			Text = item.Text,
			Icon = item.Icon,
			Variant = "Secondary",
			Size = UDim2.fromOffset(96, 76),
			LayoutOrder = index,
			Small = true,
			OnClick = function()
				App.Toggle(item.Name)
			end,
			Parent = dock,
		})
		-- Icône au-dessus du texte dans les keycaps du dock
		local content = key.Button:FindFirstChild("Content", true)
		local layout = content and content:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.Padding = UDim.new(0, 4)
		end
		key.Label.Size = UDim2.new(0, 0, 0, 16)
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

local effectPills: { [string]: { Frame: Frame, Label: TextLabel } } = {}

-- Crée ou met à jour la pilule `key` (nil = la retirer). Aucune recréation à chaque seconde.
local function effectPill(key: string, text: string?, colorName: string, order: number)
	local existing = effectPills[key]
	if not text then
		if existing then
			existing.Frame:Destroy()
			effectPills[key] = nil
		end
		return
	end
	if existing then
		existing.Label.Text = text
		return
	end
	local pill: Frame = New("Frame", {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Tag = { "Glass", "RoundPill" },
		Parent = effectsRow,
	}, {
		New("UIStroke", { Color = Style.Color(colorName), Transparency = 0.3, Thickness = 1.2 }) :: Instance,
		Create.Padding(4, 12),
	})
	local label: TextLabel = New("TextLabel", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = text,
		Tag = "TextCaption",
		Parent = pill,
	})
	effectPills[key] = { Frame = pill, Label = label }
	Motion.Pop(pill, 0.1)
end

local function refreshEffects()
	local state = Store.State
	if not state then
		return
	end
	local now = Store.UnixNow()
	effectPill(
		"Overclock",
		if state.Overclock.Until > now
			then `OVERCLOCK x{state.Overclock.Mult} · {NumberFormat.Duration(state.Overclock.Until - now)}`
			else nil,
		"BrandAnga",
		1
	)
	effectPill(
		"Server",
		if state.ServerBoostUntil > now
			then `SERVER BOOST x2 · {NumberFormat.Duration(state.ServerBoostUntil - now)}`
			else nil,
		"CurrencyBits",
		2
	)
	effectPill(
		"Personal",
		if state.Data.Boosts.BitsX2Until > now
			then `BITS x2 · {NumberFormat.Duration(state.Data.Boosts.BitsX2Until - now)}`
			else nil,
		"AccentCyan",
		3
	)
	effectPill(
		"Friends",
		if state.FriendsInServer > 0 then `AMIS +{math.min(state.FriendsInServer * 10, 30)} %` else nil,
		"Success",
		4
	)
end

local function refreshBadges(state: any)
	local data = state.Data
	local today = Formulas.DayIndex(Store.UnixNow())
	local questReady = data.Daily.LastClaimDay ~= today
	for _, list in { data.Quests.Daily, data.Quests.Weekly } do
		for _, quest in list do
			if not quest.Claimed and quest.Progress >= quest.Target then
				questReady = true
			end
		end
	end
	if data.Download.Kind ~= "" then
		for _, kind in GameConfig.Downloads do
			if kind.Id == data.Download.Kind and Store.UnixNow() >= data.Download.StartedAt + kind.Seconds then
				questReady = true
			end
		end
	end
	badges.Quests.Visible = questReady
end

local function refreshFull(state: any)
	local data = state.Data
	local production = state.Production
	genLabel.Text = `GEN {data.Generation}`
	benchValue.Text = NumberFormat.Flops(state.Benchmark)
	if data.Chips ~= lastChips then
		if lastChips >= 0 and data.Chips > lastChips then
			Motion.Pop(chipsValue.Parent :: GuiObject, 0.08)
		end
		Motion.CountTo(chipsValue, math.max(lastChips, 0), data.Chips, NumberFormat.Compact, 0.5)
		lastChips = data.Chips
	end
	-- Jauges
	local powerRatio = production.PowerDemand / math.max(production.PowerCapacity, 1)
	powerBar:Set(powerRatio)
	powerBar:SetColor(
		Style.Color(if powerRatio > 1 then "Danger" elseif powerRatio > 0.85 then "Warning" else "CurrencyBits")
	)
	powerText.Text = NumberFormat.Percent(powerRatio)
	heatRow.Visible = data.Zone >= GameConfig.Cooling.HeatStartsAtZone
	gauges.Size = UDim2.fromOffset(250, if heatRow.Visible then 74 else 44)
	local heatRatio = production.HeatDemand / math.max(production.HeatCapacity, 1)
	heatBar:Set(heatRatio)
	heatBar:SetColor(
		Style.Color(if heatRatio > 1 then "Danger" elseif heatRatio > 0.85 then "Warning" else "AccentCyan")
	)
	heatText.Text = NumberFormat.Percent(heatRatio)
	Material.SetThermalStress(if heatRow.Visible then math.clamp((heatRatio - 0.8) * 2.5, 0, 1) else 0)
	if heatRatio > 1 and heatRow.Visible and not warnedHeat then
		warnedHeat = true
		Dialogue.Say(
			"Aïe, ça chauffe ! Quand la jauge dépasse 100 %, ton PC ralentit. Il faut plus de refroidissement !",
			6
		)
	end
	if powerRatio > 1 and not warnedPower then
		warnedPower = true
		Dialogue.Say("Oups, pas assez de Watts ! Améliore le bloc d'alimentation au terminal doré de La Centrale.", 6)
	end
	-- Collecteur
	collectorCard.Visible = data.PoweredOn and not state.Passes.AutoCollect
	-- Tutoriel
	-- Anga guide le tutoriel dans sa boîte de dialogue (avant l'allumage, c'est l'écran central qui parle).
	local tip = TUTORIAL_TEXT[data.Tutorial]
	Dialogue.SetPersistent(if data.PoweredOn and data.Tutorial < 8 then tip else nil)
	refreshBadges(state)
	refreshEffects()
end

local lastObjectiveKey = ""
local function refreshFast()
	local state = Store.State
	if not state then
		return
	end
	local bits = Store.Bits()
	if math.abs(bits - lastBits) >= 1 or bits < lastBits then
		bitsValue.Text = formatBits(bits)
		lastBits = bits
	end
	bitsRate.Text = `+{NumberFormat.Compact(Store.Rate())}/s`
	local pending = Store.Pending()
	local cap = Store.Rate() * GameConfig.CollectorCapSeconds
	collectorBar:Set(if cap > 0 then pending / cap else 0, false)
	collectorText.Text =
		`Collecteur · {NumberFormat.Compact(pending)}{if cap > 0 and pending >= cap * 0.999 then " (plein)" else ""}`

	local objective = computeObjective(state)
	objectiveAction = objective.Action
	objectiveArg = objective.Arg
	objectiveTitle.Text = objective.Title
	objectiveText.Text = objective.Text
	objectiveBar.Root.Visible = objective.Ratio ~= nil
	if objective.Ratio then
		objectiveBar:Set(objective.Ratio, false)
	end
	local key = `{objective.Title}|{objective.Button or ""}|{objective.Ready}`
	if key ~= lastObjectiveKey then
		lastObjectiveKey = key
		objectiveKey.Button.Visible = objective.Button ~= nil
		objectiveKey:SetText(objective.Button or "")
		objectiveKey:SetEnabled(objective.Ready)
		objectiveCard.Size = UDim2.fromOffset(300, if objective.Button then 150 else 100)
		if objective.Ready and objective.Button then
			Motion.Pop(objectiveCard, 0.06)
		end
	end
end

function HUD.Mount(layer: Frame)
	buildTopLeft(layer)
	buildTopCenter(layer)
	buildObjective(layer)
	buildBottomLeft(layer)
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
	task.spawn(function()
		while true do
			task.wait(1)
			if Store.State then
				refreshEffects()
			end
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
