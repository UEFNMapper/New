--!strict
--[[
	StreamMonitor : l'écran d'Anga dans le lobby (docs/SCENARIO.md §6), pour le joueur local.
	Pièces taguées "StreamMonitor" (face avant) :
	- En-tête AngaTV + pastille « LIVE DANS mm:ss » : le compte à rebours descend avec la
	  progression du joueur (60:00 au départ -> 00:00 quand LAGZ est vaincu)
	- Aperçu du stream : Anga, état du PC (FPS / ping / °C) ; « EN DIRECT 🔴 » après la victoire
	- Chat qui défile : impatient avant (« ça rame 😭 »), en fête après (« GG ! »)
	Compatible StreamingEnabled (reconstruit quand la pièce réapparaît) ; mis à jour 2 fois par
	seconde et seulement quand l'écran est proche de la caméra.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Branding = require(Shared.Config.Branding)
local Tower = require(Shared.Config.Tower)
local PcHealth = require(Shared.Util.PcHealth)

local Store = require(script.Parent.Store)
local Style = require(script.Parent.Parent.UI.Style)
local Create = require(script.Parent.Parent.UI.Create)

local New = Create.New

local StreamMonitor = {}

type View = {
	Part: BasePart,
	Badge: Frame,
	BadgeText: TextLabel,
	Headline: TextLabel,
	Status: TextLabel,
	Viewers: TextLabel,
	Lines: { TextLabel },
}

type Message = { Name: string, Text: string }

local player = Players.LocalPlayer
local views: { [BasePart]: View } = {}
local history: { Message } = {}

local CHAT_LINES = 7
local VIEW_DISTANCE = 450
local CANVAS_WIDTH = 960

local RED = Color3.fromHex("F0565B")
local BG = Color3.fromHex("0E0E14")
local PANEL = Color3.fromHex("1A1A24")

local NAME_COLORS = { "F6AD55", "4FD1C5", "8B7CFF", "68D391", "ED64A6", "63B3ED", "F6E05E" }

local WAITING: { Message } = {
	{ Name = "PixelPanda", Text = "c'est quand le live ??" },
	{ Name = "Nova_08", Text = "ça rame trop 😭" },
	{ Name = "TitoGamer", Text = "allez Anga !!" },
	{ Name = "LunaBits", Text = "le ping est à 999 mdr" },
	{ Name = "RoboChips", Text = "j'ai ramené du popcorn 🍿" },
	{ Name = "Kiwi_12", Text = "LAGZ va-t'en !" },
	{ Name = "ZigZag", Text = "on croit en toi {name} !" },
	{ Name = "MiniMax", Text = "F5 F5 F5" },
	{ Name = "Choco", Text = "il reste combien de temps ?" },
	{ Name = "Sunny", Text = "{name} répare le PC, trop fort" },
}

local LIVE: { Message } = {
	{ Name = "PixelPanda", Text = "GG !!!" },
	{ Name = "Nova_08", Text = "merci l'antivirus ! 🙏" },
	{ Name = "TitoGamer", Text = "144 FPS 🔥🔥" },
	{ Name = "LunaBits", Text = "{name} le héros !" },
	{ Name = "RoboChips", Text = "LET'S GOOO" },
	{ Name = "Kiwi_12", Text = "trop fluide le live" },
	{ Name = "ZigZag", Text = "GG {name} !" },
	{ Name = "MiniMax", Text = "bye bye LAGZ 👋" },
	{ Name = "Choco", Text = "enfin le live !!!" },
}

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function nameColor(name: string): string
	local sum = 0
	for i = 1, #name do
		sum += string.byte(name, i)
	end
	return NAME_COLORS[sum % #NAME_COLORS + 1]
end

local function text(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.TextScaled = true
	props.FontFace = props.FontFace or Style.Fonts.Bold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	return New("TextLabel", props)
end

------------------------------------------------------------------------------------
-- État du joueur
------------------------------------------------------------------------------------

-- LAGZ vaincu : terminal final réussi, ou victoire et pas encore de nouvelle ascension.
local function isLive(data: any): boolean
	if not data then
		return false
	end
	if data.Cleared >= Tower.WORLD_COUNT then
		return true
	end
	return data.Wins > 0 and data.Stage == 0 and not data.RunStarted
end

local targetSeconds = PcHealth.LIVE_SECONDS
local targetSince = os.clock()

local function countdown(data: any): number
	local target = if data then PcHealth.LiveCountdown(data.Stage, data.Cleared) else PcHealth.LIVE_SECONDS
	if target ~= targetSeconds then
		targetSeconds = target
		targetSince = os.clock()
	end
	-- Les secondes défilent un peu pour que l'écran vive, sans passer sous la minute suivante.
	return math.max(target - math.min(os.clock() - targetSince, 59), 0)
end

local function pushMessage(live: boolean)
	local pool = if live then LIVE else WAITING
	local message = pool[math.random(1, #pool)]
	local last = history[#history]
	if last and last.Text == message.Text then
		message = pool[(table.find(pool, message) or 0) % #pool + 1]
	end
	local name = escape(player.DisplayName)
	table.insert(history, { Name = message.Name, Text = (string.gsub(message.Text, "{name}", name)) })
	while #history > CHAT_LINES do
		table.remove(history, 1)
	end
end

------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------

local function build(part: BasePart): View
	local existing = part:FindFirstChild("AngaStream")
	if existing then
		existing:Destroy()
	end
	local ratio = math.clamp(part.Size.Y / math.max(part.Size.X, 0.1), 0.3, 1.4)
	local gui: SurfaceGui = New("SurfaceGui", {
		Name = "AngaStream",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(CANVAS_WIDTH, math.floor(CANVAS_WIDTH * ratio)),
		LightInfluence = 0,
		Brightness = 1.6,
		ZOffset = 1,
		Parent = part,
	})
	local root: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Parent = gui,
	})

	-- En-tête : logo AngaTV + pastille du live
	local logo: Frame = New("Frame", {
		Position = UDim2.fromScale(0.02, 0.025),
		Size = UDim2.fromScale(0.075, 0.1),
		BackgroundColor3 = RED,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0.25, 0) }) :: Instance,
		New("UIAspectRatioConstraint", { AspectRatio = 1 }) :: Instance,
	})
	text({ Size = UDim2.fromScale(1, 1), Text = "A", FontFace = Style.Fonts.Display, Parent = logo })
	text({
		Position = UDim2.fromScale(0.12, 0.03),
		Size = UDim2.fromScale(0.36, 0.09),
		Text = Branding.ChannelName,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Style.Fonts.Display,
		Parent = root,
	})
	local badge: Frame = New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.98, 0.025),
		Size = UDim2.fromScale(0.36, 0.1),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		Parent = root,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance })
	local badgeText = text({
		Position = UDim2.fromScale(0.06, 0.15),
		Size = UDim2.fromScale(0.88, 0.7),
		Text = "",
		FontFace = Style.Fonts.Heavy,
		Parent = badge,
	})

	-- Aperçu du stream
	local stage: Frame = New("Frame", {
		Position = UDim2.fromScale(0.02, 0.16),
		Size = UDim2.fromScale(0.63, 0.81),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		Parent = root,
	}, { New("UICorner", { CornerRadius = UDim.new(0.04, 0) }) :: Instance })
	local avatar: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.4, 0.4),
		BackgroundColor3 = RED,
		BorderSizePixel = 0,
		Parent = stage,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		New("UIAspectRatioConstraint", { AspectRatio = 1 }) :: Instance,
		New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 4 }) :: Instance,
	})
	if Branding.AngaImageId ~= "" then
		New("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = Branding.AngaImageId,
			ScaleType = Enum.ScaleType.Crop,
			Parent = avatar,
		}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance })
	else
		text({
			Position = UDim2.fromScale(0.2, 0.2),
			Size = UDim2.fromScale(0.6, 0.6),
			Text = "A",
			FontFace = Style.Fonts.Display,
			Parent = avatar,
		})
	end
	local headline = text({
		Position = UDim2.fromScale(0.05, 0.62),
		Size = UDim2.fromScale(0.9, 0.12),
		Text = "",
		FontFace = Style.Fonts.Heavy,
		Parent = stage,
	})
	local status = text({
		Position = UDim2.fromScale(0.05, 0.77),
		Size = UDim2.fromScale(0.9, 0.09),
		Text = "",
		RichText = true,
		FontFace = Style.Fonts.Bold,
		Parent = stage,
	})
	local viewers = text({
		Position = UDim2.fromScale(0.05, 0.89),
		Size = UDim2.fromScale(0.9, 0.07),
		Text = "",
		FontFace = Style.Fonts.Medium,
		TextColor3 = Color3.fromHex("C5C5C5"),
		Parent = stage,
	})

	-- Chat
	local chat: Frame = New("Frame", {
		Position = UDim2.fromScale(0.67, 0.16),
		Size = UDim2.fromScale(0.31, 0.81),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		Parent = root,
	}, { New("UICorner", { CornerRadius = UDim.new(0.06, 0) }) :: Instance })
	text({
		Position = UDim2.fromScale(0.08, 0.02),
		Size = UDim2.fromScale(0.84, 0.08),
		Text = "CHAT",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Style.Fonts.Heavy,
		TextColor3 = Color3.fromHex("C5C5C5"),
		Parent = chat,
	})
	local lines: { TextLabel } = {}
	for i = 1, CHAT_LINES do
		table.insert(
			lines,
			text({
				Position = UDim2.fromScale(0.06, 0.12 + (i - 1) * 0.125),
				Size = UDim2.fromScale(0.9, 0.11),
				Text = "",
				RichText = true,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = Style.Fonts.Medium,
				Parent = chat,
			})
		)
	end
	return {
		Part = part,
		Badge = badge,
		BadgeText = badgeText,
		Headline = headline,
		Status = status,
		Viewers = viewers,
		Lines = lines,
	}
end

------------------------------------------------------------------------------------
-- Rendu
------------------------------------------------------------------------------------

local function gradeColor(metric: string, value: number): string
	local grade = PcHealth.Grade(metric, value)
	return if grade == "Good" then "68D391" elseif grade == "Warn" then "F6E05E" else "FC8181"
end

local function render(view: View, data: any, live: boolean, seconds: number, blink: boolean)
	local cleared = if data then data.Cleared else 0
	local stats = PcHealth.Stats(if live then Tower.WORLD_COUNT else cleared)
	if live then
		view.Badge.BackgroundColor3 = RED
		view.BadgeText.Text = if blink then "EN DIRECT 🔴" else "EN DIRECT ⚪"
		view.Headline.Text = "LE LIVE COMMENCE !"
		view.Viewers.Text = "👀 12 408 spectateurs · merci l'antivirus !"
	else
		view.Badge.BackgroundColor3 = PANEL
		view.BadgeText.Text = `LIVE DANS {PcHealth.Clock(seconds)}`
		view.Headline.Text = if cleared == 0 then "Le PC rame… LAGZ est là !" else "Le PC se répare…"
		view.Viewers.Text = `👀 {1200 + cleared * 1500} personnes attendent`
	end
	view.Status.Text = string.format(
		'PC : <font color="#%s">%d FPS</font> · <font color="#%s">%d ms</font> · <font color="#%s">%d °C</font>',
		gradeColor("Fps", stats.Fps),
		stats.Fps,
		gradeColor("Ping", stats.Ping),
		stats.Ping,
		gradeColor("Temp", stats.Temp),
		stats.Temp
	)
	for i, line in view.Lines do
		local message = history[i]
		if message then
			line.Text = `<font color="#{nameColor(message.Name)}"><b>{message.Name}</b></font> {message.Text}`
		else
			line.Text = ""
		end
	end
end

local function track(instance: Instance)
	if instance:IsA("BasePart") and not views[instance] then
		views[instance] = build(instance)
	end
end

function StreamMonitor.Start()
	for _, instance in CollectionService:GetTagged("StreamMonitor") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("StreamMonitor"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("StreamMonitor"):Connect(function(instance: Instance)
		local view = views[instance :: any]
		if view then
			views[instance :: any] = nil
			local gui = instance:FindFirstChild("AngaStream")
			if gui then
				gui:Destroy()
			end
		end
	end)

	task.spawn(function()
		local chatClock = 0
		local blink = false
		while true do
			task.wait(0.5)
			local data = Store.Data()
			local live = isLive(data)
			blink = not blink
			chatClock += 0.5
			if chatClock >= 2.4 or #history == 0 then
				chatClock = 0
				pushMessage(live)
			end
			if next(views) then
				local seconds = countdown(data)
				local camera = Workspace.CurrentCamera
				local eye = if camera then camera.CFrame.Position else Vector3.zero
				for part, view in views do
					if part.Parent == nil then
						views[part] = nil
					elseif (part.Position - eye).Magnitude < VIEW_DISTANCE then
						render(view, data, live, seconds, blink)
					end
				end
			end
		end
	end)
end

return StreamMonitor
