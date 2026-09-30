--!strict
--[[
	AppScreen : l'écran géant du hub reproduit le "Tableau de bord" du logiciel partenaire
	AngAInOne (gris Fluent + accent violet), alimenté par la partie DU JOUEUR LOCAL :
	- Barre latérale : une section de l'app par monde de la tour ; ✓ quand le virus du
	  monde est éliminé, 🔒 tant qu'on ne l'a pas atteint ; pastille de la meilleure médaille
	  du monde (bronze / argent / or, WorldBest)
	- Santé du PC : Progression, Virus, Victoires, Record
	- État en direct : 3 graphes (60 derniers relevés, 1 par seconde)
	    CPU = progression dans la tour · GPU = Bits (relatifs au max récent) · RAM = mondes nettoyés
	Tout est côté client ; mis à jour 1 fois par seconde et seulement quand l'écran est proche.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local NumberFormat = require(Shared.Util.NumberFormat)
local Time = require(Shared.Util.Time)
local Medals = require(Shared.Config.Medals)
local MedalLogic = require(Shared.Util.MedalLogic)

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
-- Medal : pastille de la meilleure médaille du monde (cachée tant qu'il n'y en a pas).
type SidebarEntry = { Row: Frame, Label: TextLabel, Zone: number, Medal: Frame?, MedalName: string }
type View = {
	Sidebar: { SidebarEntry },
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
	for index, world in Tower.Worlds do
		table.insert(items, { Name = world.AppSection, Zone = index })
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
			Size = UDim2.fromScale(if item.Zone > 0 then 0.72 else 0.86, 0.6),
			Text = item.Name,
			Parent = row,
		})
		-- Pastille de médaille du monde (dégradé, comme la carte de médaille).
		local medal: Frame? = nil
		if item.Zone > 0 then
			medal = New("Frame", {
				Name = "Medal",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(0.95, 0.5),
				Size = UDim2.fromScale(0, 0.55),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Visible = false,
				Parent = row,
			}, {
				New("UIAspectRatioConstraint", {
					AspectRatio = 1,
					DominantAxis = Enum.DominantAxis.Height,
				}) :: Instance,
				New("UICorner", { CornerRadius = UDim.new(1, 0) }),
				New("UIGradient", { Rotation = 45 }),
				New("UIStroke", { Thickness = 2 }),
			})
		end
		table.insert(sidebar, { Row = row, Label = label, Zone = item.Zone, Medal = medal, MedalName = "" })
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
	for index, name in { "Progression", "Virus", "Victoires", "Record" } do
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

-- Meilleure médaille sauvegardée d'un monde ("" = aucune).
local function bestMedal(data: any, world: number): string
	local bests = data.WorldBest
	local best = if type(bests) == "table" then bests[MedalLogic.Key(world)] else nil
	return if type(best) == "table" and type(best.Medal) == "string" then best.Medal else ""
end

-- Colore la pastille de médaille d'une section (seulement quand elle change).
local function paintMedal(entry: SidebarEntry, medal: string)
	local dotFrame = entry.Medal
	if not dotFrame or entry.MedalName == medal then
		return
	end
	entry.MedalName = medal
	local colors = (Medals.Colors :: any)[medal]
	dotFrame.Visible = colors ~= nil
	if not colors then
		return
	end
	local gradient = dotFrame:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color(colors[1])),
			ColorSequenceKeypoint.new(0.5, color(colors[2])),
			ColorSequenceKeypoint.new(1, color(colors[3])),
		})
	end
	local stroke = dotFrame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color(colors[3])
	end
end

local function update(view: View)
	local state = Store.State
	if not state then
		return
	end
	local data = state.Data
	local current = Tower.WorldOf(data.Stage)
	for _, entry in view.Sidebar do
		if entry.Zone == 0 then
			entry.Label.Text = APP.Sidebar[1]
			entry.Label.TextColor3 = TEXT
			entry.Label.TextTransparency = 0
		else
			local section = Tower.Worlds[entry.Zone].AppSection
			local cleaned = entry.Zone <= data.Cleared
			local reached = entry.Zone <= math.max(current, 1)
			entry.Label.TextColor3 = if cleaned then GOOD elseif reached then TEXT else DIM
			entry.Label.TextTransparency = if reached or cleaned then 0 else 0.45
			entry.Label.Text = if cleaned then `✓ {section}` elseif reached then section else `🔒 {section}`
			paintMedal(entry, bestMedal(data, entry.Zone))
		end
	end
	view.User.Text = `{Players.LocalPlayer.DisplayName}  ·  🏆 {data.Wins}`

	-- Santé du PC (= ta partie)
	setCard(view, "Progression", `Étape {data.Stage}/{Tower.TOTAL_STAGES}`, if data.Stage > 0 then GOOD else WARN)
	setCard(
		view,
		"Virus",
		`{data.Cleared}/{Tower.WORLD_COUNT} mondes nettoyés`,
		if data.Cleared >= Tower.WORLD_COUNT then GOOD elseif data.Cleared > 0 then WARN else BAD
	)
	setCard(
		view,
		"Victoires",
		`{data.Wins} ascension{if data.Wins > 1 then "s" else ""}`,
		if data.Wins > 0 then GOOD else WARN
	)
	setCard(
		view,
		"Record",
		if data.BestTime > 0 then Time.Clock(data.BestTime) else "Aucun",
		if data.BestTime > 0 then GOOD else WARN
	)

	-- État en direct
	push(view.Graphs.CPU, data.Stage / Tower.TOTAL_STAGES * 100, `Étape {data.Stage}`)
	maxRate = math.max(maxRate * 0.995, data.Bits, 1)
	push(view.Graphs.GPU, data.Bits / maxRate * 100, `{NumberFormat.Compact(data.Bits)} Bits`)
	push(view.Graphs.RAM, data.Cleared / Tower.WORLD_COUNT * 100, `{data.Cleared}/{Tower.WORLD_COUNT} terminaux`)
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
