--!strict
--[[
	AppScreen : l'écran géant du hub reproduit le "Tableau de bord" du logiciel partenaire
	AngAInOne (gris Fluent + accent violet), alimenté par le PC DU JOUEUR LOCAL :
	- Barre latérale : une section de l'app par zone ; verrouillée tant que la zone l'est
	- Santé du PC : Alimentation, Températures, Nanobots, Firmware
	- État en direct : 3 graphes (60 derniers relevés, 1 par seconde)
	    CPU = production (Bits/s, relative au max récent) · GPU = remplissage du collecteur
	    RAM = charge électrique (Watts demandés / capacité)
	Tout est côté client ; mis à jour 1 fois par seconde et seulement quand l'écran est proche.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Branding = require(Shared.Config.Branding)
local GameConfig = require(Shared.Config.GameConfig)
local NumberFormat = require(Shared.Util.NumberFormat)

local Store = require(script.Parent.Store)
local Style = require(script.Parent.Parent.UI.Style)
local Create = require(script.Parent.Parent.UI.Create)

local New = Create.New
local APP = Branding.PartnerApp

local AppScreen = {}

local SAMPLES = 60
local PIXELS_PER_STUD = 12
local VIEW_DISTANCE = 260

local function color(hex: string): Color3
	return Color3.fromHex(hex)
end

local SURFACE = color(APP.Surface)
local CARD = color(APP.Card)
local TEXT = color(APP.Text)
local DIM = color(APP.TextDim)
local ACCENT = color(APP.Accent)
local GOOD = color(APP.Good)
local WARN = color(APP.Warn)
local BAD = color(APP.Bad)

type Graph = { Bars: { Frame }, Value: TextLabel, Footer: TextLabel, Color: Color3, History: { number } }
type Card = { Dot: Frame, Status: TextLabel }
type View = {
	Sidebar: { { Row: Frame, Label: TextLabel, Zone: number } },
	Cards: { [string]: Card },
	Graphs: { [string]: Graph },
	User: TextLabel,
}

local views: { [BasePart]: View } = {}
local maxRate = 1

local function text(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.FontFace = props.FontFace or Style.Fonts.Medium
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextScaled = true
	return New("TextLabel", props)
end

local function card(parent: Instance, position: UDim2, size: UDim2): Frame
	return New("Frame", {
		Position = position,
		Size = size,
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Create.Corner(10) :: Instance })
end

local function dot(parent: Instance, position: UDim2, tint: Color3): Frame
	return New("Frame", {
		Position = position,
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = tint,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Create.Corner(7) :: Instance })
end

local function build(screen: BasePart): View
	local gui: SurfaceGui = New("SurfaceGui", {
		Name = "AngAInOneApp",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS_PER_STUD,
		LightInfluence = 0,
		Brightness = 1.4,
		Parent = screen,
	})
	local root: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = SURFACE,
		BorderSizePixel = 0,
		Parent = gui,
	})

	-- Barre latérale
	local side: Frame = New("Frame", {
		Size = UDim2.fromScale(0.21, 1),
		BackgroundColor3 = Color3.fromRGB(28, 28, 28),
		BorderSizePixel = 0,
		Parent = root,
	})
	text({
		Position = UDim2.fromScale(0.08, 0.02),
		Size = UDim2.fromScale(0.84, 0.035),
		Text = APP.Name,
		TextColor3 = DIM,
		Parent = side,
	})
	local user = text({
		Position = UDim2.fromScale(0.08, 0.075),
		Size = UDim2.fromScale(0.84, 0.045),
		Text = Players.LocalPlayer.DisplayName,
		FontFace = Style.Fonts.Bold,
		Parent = side,
	})
	local search = card(side, UDim2.fromScale(0.06, 0.14), UDim2.fromScale(0.88, 0.055))
	text({
		Position = UDim2.fromScale(0.06, 0.2),
		Size = UDim2.fromScale(0.88, 0.6),
		Text = "Rechercher une page…",
		TextColor3 = DIM,
		Parent = search,
	})
	local sidebar = {}
	local items: { { Name: string, Zone: number } } = { { Name = APP.Sidebar[1], Zone = 0 } }
	for index, zone in Zones do
		table.insert(items, { Name = zone.AppSection, Zone = index })
	end
	for order, item in items do
		local row: Frame = New("Frame", {
			Position = UDim2.fromScale(0.03, 0.22 + (order - 1) * 0.07),
			Size = UDim2.fromScale(0.94, 0.06),
			BackgroundColor3 = color(APP.CardHover),
			BackgroundTransparency = if order == 1 then 0 else 1,
			BorderSizePixel = 0,
			Parent = side,
		}, { Create.Corner(6) :: Instance })
		if order == 1 then
			New("Frame", {
				Position = UDim2.fromScale(0, 0.25),
				Size = UDim2.new(0, 5, 0.5, 0),
				BackgroundColor3 = ACCENT,
				BorderSizePixel = 0,
				Parent = row,
			}, { Create.Corner(3) :: Instance })
		end
		local label = text({
			Position = UDim2.fromScale(0.1, 0.2),
			Size = UDim2.fromScale(0.86, 0.6),
			Text = item.Name,
			Parent = row,
		})
		table.insert(sidebar, { Row = row, Label = label, Zone = item.Zone })
	end

	-- Contenu principal
	local main: Frame = New("Frame", {
		Position = UDim2.fromScale(0.24, 0),
		Size = UDim2.fromScale(0.74, 1),
		BackgroundTransparency = 1,
		Parent = root,
	})
	text({
		Position = UDim2.fromScale(0, 0.03),
		Size = UDim2.fromScale(0.6, 0.075),
		Text = "Tableau de bord",
		FontFace = Style.Fonts.Bold,
		Parent = main,
	})
	local sync = New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0.13),
		Size = UDim2.fromScale(0.17, 0.055),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Parent = main,
	}, { Create.Corner(6) :: Instance })
	text({
		Size = UDim2.fromScale(1, 0.7),
		Position = UDim2.fromScale(0, 0.15),
		Text = "Synchroniser",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = sync,
	})
	for index, info in
		{
			{ `Application {APP.Name}`, `À jour — {APP.Version}` },
			{ `Service {APP.Name}`, "Service connecté" },
			{ Branding.GameName, APP.Pitch },
		}
	do
		local x = (index - 1) * 0.27
		dot(main, UDim2.new(x, 0, 0.135, 4), GOOD)
		text({
			Position = UDim2.fromScale(x + 0.02, 0.125),
			Size = UDim2.fromScale(0.24, 0.035),
			Text = info[1],
			Parent = main,
		})
		text({
			Position = UDim2.fromScale(x + 0.02, 0.16),
			Size = UDim2.fromScale(0.24, 0.03),
			Text = info[2],
			TextColor3 = DIM,
			Parent = main,
		})
	end

	-- Santé du PC
	text({
		Position = UDim2.fromScale(0, 0.23),
		Size = UDim2.fromScale(0.4, 0.04),
		Text = "Santé du PC",
		FontFace = Style.Fonts.Bold,
		Parent = main,
	})
	local cards: { [string]: Card } = {}
	for index, name in { "Alimentation", "Températures", "Nanobots", "Firmware" } do
		local frame = card(main, UDim2.fromScale((index - 1) * 0.25, 0.285), UDim2.fromScale(0.235, 0.13))
		text({
			Position = UDim2.fromScale(0.08, 0.14),
			Size = UDim2.fromScale(0.84, 0.28),
			Text = name,
			FontFace = Style.Fonts.Bold,
			Parent = frame,
		})
		local status = text({
			Position = UDim2.fromScale(0.2, 0.52),
			Size = UDim2.fromScale(0.76, 0.26),
			Text = "…",
			TextColor3 = DIM,
			Parent = frame,
		})
		cards[name] = { Dot = dot(frame, UDim2.new(0.08, 0, 0.55, 2), GOOD), Status = status }
	end

	-- État en direct
	text({
		Position = UDim2.fromScale(0, 0.45),
		Size = UDim2.fromScale(0.5, 0.04),
		Text = `État en direct   ·   {SAMPLES} derniers relevés`,
		FontFace = Style.Fonts.Bold,
		Parent = main,
	})
	local graphs: { [string]: Graph } = {}
	for index, info in { { "CPU", "4A90E2" }, { "GPU", "3FB27F" }, { "RAM", "9B7CE0" } } do
		local frame = card(main, UDim2.fromScale((index - 1) * 0.335, 0.51), UDim2.fromScale(0.32, 0.42))
		text({
			Position = UDim2.fromScale(0.06, 0.07),
			Size = UDim2.fromScale(0.4, 0.1),
			Text = info[1],
			Parent = frame,
		})
		local value = text({
			Position = UDim2.fromScale(0.5, 0.05),
			Size = UDim2.fromScale(0.44, 0.14),
			Text = "0 %",
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Style.Fonts.Bold,
			TextColor3 = GOOD,
			Parent = frame,
		})
		local plot: Frame = New("Frame", {
			Position = UDim2.fromScale(0.06, 0.25),
			Size = UDim2.fromScale(0.88, 0.55),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = frame,
		})
		local tint = color(info[2])
		local bars = {}
		for i = 1, SAMPLES do
			table.insert(
				bars,
				New("Frame", {
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale((i - 1) / SAMPLES, 1),
					Size = UDim2.new(1 / SAMPLES, 1, 0, 0),
					BackgroundColor3 = tint,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
					Parent = plot,
				}) :: Frame
			)
		end
		local footer = text({
			Position = UDim2.fromScale(0.06, 0.84),
			Size = UDim2.fromScale(0.88, 0.1),
			Text = "",
			TextColor3 = DIM,
			Parent = frame,
		})
		graphs[info[1]] =
			{ Bars = bars, Value = value, Footer = footer, Color = tint, History = table.create(SAMPLES, 0) }
	end
	return { Sidebar = sidebar, Cards = cards, Graphs = graphs, User = user }
end

local function levelColor(percent: number): Color3
	return if percent >= 90 then BAD elseif percent >= 75 then WARN else GOOD
end

local function push(graph: Graph, percent: number, footer: string)
	table.remove(graph.History, 1)
	table.insert(graph.History, math.clamp(percent, 0, 100))
	for i, bar in graph.Bars do
		bar.Size = UDim2.new(1 / SAMPLES, 1, graph.History[i] / 100, 0)
	end
	graph.Value.Text = `{math.floor(percent + 0.5)} %`
	graph.Value.TextColor3 = levelColor(percent)
	graph.Footer.Text = footer
end

local function setCard(view: View, name: string, status: string, tint: Color3)
	local c = view.Cards[name]
	c.Status.Text = status
	c.Dot.BackgroundColor3 = tint
end

local function update(view: View)
	local state = Store.State
	if not state then
		return
	end
	local data = state.Data
	local production = state.Production
	for _, entry in view.Sidebar do
		local unlocked = entry.Zone <= data.Zone
		entry.Label.TextColor3 = if unlocked then TEXT else DIM
		entry.Label.TextTransparency = if unlocked then 0 else 0.45
		entry.Label.Text = if unlocked or entry.Zone == 0
			then (if entry.Zone == 0 then APP.Sidebar[1] else Zones[entry.Zone].AppSection)
			else `🔒 {Zones[entry.Zone].AppSection}`
	end
	view.User.Text = `{Players.LocalPlayer.DisplayName}  ·  Gen {data.Generation}`

	-- Santé du PC
	local powerPct = if production.PowerCapacity > 0 then production.PowerDemand / production.PowerCapacity * 100 else 0
	setCard(
		view,
		"Alimentation",
		if production.PowerEfficiency < 1 then "Watts insuffisants !" else `{math.floor(powerPct)} % de la capacité`,
		if production.PowerEfficiency < 1 then BAD else GOOD
	)
	local heatRatio = if production.HeatCapacity > 0 then production.HeatDemand / production.HeatCapacity else 0
	local cpuTemp = math.floor(34 + math.min(heatRatio, 1.4) * 50)
	setCard(
		view,
		"Températures",
		`CPU {cpuTemp} °C · GPU {cpuTemp + 2} °C`,
		if production.ThermalEfficiency < 1 then BAD elseif heatRatio > 0.8 then WARN else GOOD
	)
	local equipped = #data.Nanobots.Equipped
	setCard(
		view,
		"Nanobots",
		`{equipped} équipé{if equipped > 1 then "s" else ""}`,
		if equipped > 0 then GOOD else WARN
	)
	setCard(view, "Firmware", `{data.Firmware} point{if data.Firmware > 1 then "s" else ""}`, GOOD)

	-- État en direct
	local rate = Store.Rate()
	maxRate = math.max(maxRate * 0.995, rate, 1)
	push(view.Graphs.CPU, rate / maxRate * 100, `{NumberFormat.Compact(rate)} Bits/s`)
	local cap = rate * GameConfig.CollectorCapSeconds
	local pending = Store.Pending()
	push(view.Graphs.GPU, if cap > 0 then pending / cap * 100 else 0, `Collecteur : {NumberFormat.Compact(pending)}`)
	push(
		view.Graphs.RAM,
		powerPct,
		`{NumberFormat.Compact(production.PowerDemand)} W / {NumberFormat.Compact(production.PowerCapacity)} W`
	)
end

function AppScreen.Start()
	local function add(instance: Instance)
		if instance:IsA("BasePart") and not views[instance] then
			views[instance] = build(instance)
		end
	end
	for _, instance in CollectionService:GetTagged("AppScreen") do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal("AppScreen"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("AppScreen"):Connect(function(instance: Instance)
		views[instance :: any] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local camera = Workspace.CurrentCamera
			for screen, view in views do
				if camera and (screen.Position - camera.CFrame.Position).Magnitude < VIEW_DISTANCE then
					update(view)
				end
			end
		end
	end)
end

return AppScreen
