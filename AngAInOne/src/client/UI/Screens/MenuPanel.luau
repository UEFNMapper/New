--!strict
--[[
	MenuPanel : réglages (volumes, animations réduites), classements (victoires, meilleur
	temps, étape max), joueurs du serveur (leur étape), statistiques et crédits.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local NumberFormat = require(Shared.Util.NumberFormat)
local Time = require(Shared.Util.Time)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Panel = require(script.Parent.Parent.Components.Panel)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local App = require(script.Parent.Parent.App)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local MenuPanel = {}

-- Appliqué immédiatement côté client (le contrôleur audio s'y branche).
MenuPanel.OnSettings = nil :: ((music: number, sfx: number, reduced: boolean) -> ())?

local panel: Panel.Panel
local tab = "Settings"
local tabKeys: { [string]: Keycap.Keycap } = {}
local body: Frame
local settings = { Music = 0.35, Sfx = 0.7, ReducedMotion = false }
local saveToken = 0
-- Connexions globales des curseurs : nettoyées à chaque reconstruction (pas de fuite).
local connections: { RBXScriptConnection } = {}

local TABS = {
	{ Id = "Settings", Text = "Réglages" },
	{ Id = "Boards", Text = "Classements" },
	{ Id = "Players", Text = "Joueurs" },
	{ Id = "Stats", Text = "Stats" },
}

local function scheduleSave()
	if MenuPanel.OnSettings then
		MenuPanel.OnSettings(settings.Music, settings.Sfx, settings.ReducedMotion)
	end
	saveToken += 1
	local token = saveToken
	task.delay(1, function()
		if token == saveToken then
			Net.Fire("SaveSettings", settings.Music, settings.Sfx, settings.ReducedMotion)
		end
	end)
end

-- Curseur glissant (souris, tactile, manette via les boutons -/+).
local function slider(parent: Instance, order: number, label: string, value: number, onChange: (number) -> ())
	local row = Widgets.Card(UDim2.new(1, -4, 0, 70), parent, order)
	New("TextLabel", {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 22),
		BackgroundTransparency = 1,
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = row,
	})
	local track: TextButton = New("TextButton", {
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -110, 0, 12),
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Tag = { "GlassSunken", "RoundPill" },
		Parent = row,
	})
	-- Manette : gauche/droite règlent la valeur au lieu de déplacer la sélection.
	track.NextSelectionLeft = track
	track.NextSelectionRight = track
	local fill: Frame = New("Frame", {
		Size = UDim2.fromScale(value, 1),
		BorderSizePixel = 0,
		Tag = { "FillViolet", "RoundPill" },
		Parent = track,
	})
	local knob: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(value, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BorderSizePixel = 0,
		Tag = { "FillWhite", "RoundPill" },
		Parent = track,
	}, {
		New("UIStroke", { Color = Style.Color("AccentViolet"), Thickness = 3 }),
	})
	local valueLabel: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 36),
		Size = UDim2.fromOffset(70, 24),
		BackgroundTransparency = 1,
		Text = NumberFormat.Percent(value),
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "TextCaption",
		Parent = row,
	})
	local function set(v: number)
		v = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(v, 1)
		knob.Position = UDim2.fromScale(v, 0.5)
		valueLabel.Text = NumberFormat.Percent(v)
		onChange(v)
	end
	local dragging = false
	local function fromInput(input: InputObject)
		local x = (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
		set(x)
	end
	track.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			fromInput(input)
		end
	end)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if
				dragging
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				fromInput(input)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = false
			end
		end)
	)
	-- Manette : curseur sélectionné + croix gauche/droite
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if GuiService.SelectedObject == track then
				local current = fill.Size.X.Scale
				if input.KeyCode == Enum.KeyCode.DPadLeft then
					set(current - 0.1)
				elseif input.KeyCode == Enum.KeyCode.DPadRight then
					set(current + 0.1)
				end
			end
		end)
	)
end

local function toggle(parent: Instance, order: number, label: string, value: boolean, onChange: (boolean) -> ())
	local row = Widgets.Card(UDim2.new(1, -4, 0, 64), parent, order)
	New("TextLabel", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -200, 1, 0),
		BackgroundTransparency = 1,
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = row,
	})
	local state = value
	local key: Keycap.Keycap
	key = Keycap.new({
		Text = if state then "ACTIVÉ" else "DÉSACTIVÉ",
		Variant = if state then "Success" else "Secondary",
		Size = UDim2.fromOffset(150, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Small = true,
		OnClick = function()
			state = not state
			key:SetText(if state then "ACTIVÉ" else "DÉSACTIVÉ")
			key:SetVariant(if state then "Success" else "Secondary")
			onChange(state)
		end,
		Parent = row,
	})
end

local function buildSettings()
	local scroll = Widgets.Scroll(body, 10)
	slider(scroll, 1, "Musique", settings.Music, function(v: number)
		settings.Music = v
		scheduleSave()
	end)
	slider(scroll, 2, "Effets sonores", settings.Sfx, function(v: number)
		settings.Sfx = v
		scheduleSave()
	end)
	toggle(scroll, 3, "Réduire les animations", settings.ReducedMotion, function(v: boolean)
		settings.ReducedMotion = v
		Motion.SetReduced(v)
		scheduleSave()
	end)
	local credits = Widgets.Card(UDim2.new(1, -4, 0, 70), scroll, 10)
	New("TextLabel", {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 1, -16),
		BackgroundTransparency = 1,
		Text = "AngAInOne — un jeu d'Anga.\nMusique : bibliothèque APM Music (licence Roblox). Sons : Pro Sound Effects.",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextMuted",
		Parent = credits,
	})
end

local function boardColumn(
	parent: Instance,
	title: string,
	entries: { any },
	position: UDim2,
	format: (number) -> string
)
	local column: Frame = New("Frame", {
		Position = position,
		Size = UDim2.new(1 / 3, -8, 1, 0),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Tag = { "GlassSunken", "RoundM" },
		Parent = parent,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 26),
		BackgroundTransparency = 1,
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextTitle",
		Parent = column,
	})
	local list: Frame = New("Frame", {
		Position = UDim2.fromOffset(10, 46),
		Size = UDim2.new(1, -20, 1, -56),
		BackgroundTransparency = 1,
		Parent = column,
	})
	local scroll = Widgets.Scroll(list, 4)
	local me = Players.LocalPlayer.UserId
	for rank, entry in entries do
		local row: Frame = New("Frame", {
			Size = UDim2.new(1, -4, 0, 30),
			BackgroundTransparency = if entry.UserId == me then 0.4 else 1,
			BorderSizePixel = 0,
			LayoutOrder = rank,
			Tag = { "FillViolet", "RoundS" },
			Parent = scroll,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(0, 36, 1, 0),
			BackgroundTransparency = 1,
			Text = `#{rank}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "FontHeavy",
			TextSize = 16,
			TextColor3 = Style.Color(if rank <= 3 then "CurrencyBits" else "TextMuted"),
			Parent = row,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(46, 0),
			Size = UDim2.new(1, -140, 1, 0),
			BackgroundTransparency = 1,
			Text = entry.Name,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextBody",
			Parent = row,
		})
		New("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.fromOffset(90, 30),
			BackgroundTransparency = 1,
			Text = format(entry.Value),
			TextXAlignment = Enum.TextXAlignment.Right,
			Tag = "TextCaption",
			Parent = row,
		})
	end
end

local function buildBoards()
	local boards = Store.Boards
	if not boards then
		New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = "Chargement des classements…",
			Tag = "TextMuted",
			Parent = body,
		})
		return
	end
	boardColumn(body, "VICTOIRES", boards.Wins or {}, UDim2.fromScale(0, 0), NumberFormat.Compact)
	boardColumn(body, "MEILLEUR TEMPS", boards.BestTime or {}, UDim2.new(1 / 3, 4, 0, 0), Time.Clock)
	boardColumn(body, "ÉTAPE MAX", boards.Stage or {}, UDim2.new(2 / 3, 8, 0, 0), function(value: number): string
		return `{value}/{Tower.TOTAL_STAGES}`
	end)
end

local function buildPlayers()
	local scroll = Widgets.Scroll(body, 10)
	local me = Players.LocalPlayer.UserId
	local count = 0
	for _, other in Players:GetPlayers() do
		if other.UserId ~= me then
			count += 1
			local card = Widgets.Card(UDim2.new(1, -4, 0, 64), scroll, count)
			local stage = other:GetAttribute("Stage")
			local wins = other:GetAttribute("Wins")
			local stageNumber = if type(stage) == "number" then stage else 0
			local world = Tower.Worlds[math.max(Tower.WorldOf(stageNumber), 1)]
			New("TextLabel", {
				Position = UDim2.fromOffset(16, 8),
				Size = UDim2.new(1, -32, 0, 24),
				BackgroundTransparency = 1,
				Text = other.DisplayName,
				TextXAlignment = Enum.TextXAlignment.Left,
				Tag = "TextHeading",
				Parent = card,
			})
			New("TextLabel", {
				Position = UDim2.fromOffset(16, 34),
				Size = UDim2.new(1, -32, 0, 20),
				BackgroundTransparency = 1,
				Text = `Étape {stageNumber}/{Tower.TOTAL_STAGES} · {world.Name} · 🏆 {if type(wins)
						== "number"
					then wins
					else 0}`,
				TextXAlignment = Enum.TextXAlignment.Left,
				Tag = "TextMuted",
				Parent = card,
			})
		end
	end
	if count == 0 then
		New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = "Tu es seul sur ce serveur… invite des amis : +10 % de Bits par ami !",
			TextWrapped = true,
			Tag = "TextMuted",
			Parent = scroll,
		})
	end
end

local function buildStats()
	local state = Store.State
	if not state then
		return
	end
	local data = state.Data
	local lines = {
		{ "Temps de jeu", NumberFormat.Duration(data.Stats.Playtime) },
		{ "Victoires", tostring(data.Wins) },
		{ "Meilleur temps", if data.BestTime > 0 then Time.Clock(data.BestTime) else "—" },
		{ "Étape la plus haute", `{data.BestStage}/{Tower.TOTAL_STAGES}` },
		{ "Terminaux antivirus réussis", tostring(data.MinigamesWon) },
		{ "Orbes de Bits ramassées", tostring(data.Stats.CoinsCollected) },
		{ "Chutes et pièges", tostring(data.Deaths) },
		{ "Bits gagnés (total)", NumberFormat.Compact(data.TotalBits) },
	}
	local scroll = Widgets.Scroll(body, 6)
	for index, line in lines do
		local row: Frame = New("Frame", {
			Size = UDim2.new(1, -4, 0, 40),
			BackgroundTransparency = if index % 2 == 0 then 1 else 0.5,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Tag = { "GlassSunken", "RoundS" },
			Parent = scroll,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(0.6, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = line[1],
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextBody",
			Parent = row,
		})
		New("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0.4, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = line[2],
			TextXAlignment = Enum.TextXAlignment.Right,
			Tag = "TextHeading",
			Parent = row,
		})
	end
end

local function rebuild()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for id, key in tabKeys do
		key:SetVariant(if id == tab then "Primary" else "Secondary")
	end
	if tab == "Settings" then
		buildSettings()
	elseif tab == "Boards" then
		buildBoards()
	elseif tab == "Players" then
		buildPlayers()
	else
		buildStats()
	end
end

-- Charge les réglages sauvegardés (appelé une fois au premier état reçu).
function MenuPanel.LoadSettings(saved: any)
	settings.Music = saved.Music
	settings.Sfx = saved.Sfx
	settings.ReducedMotion = saved.ReducedMotion
	Motion.SetReduced(saved.ReducedMotion)
	if MenuPanel.OnSettings then
		MenuPanel.OnSettings(settings.Music, settings.Sfx, settings.ReducedMotion)
	end
end

function MenuPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "MenuPanel",
		Title = "MENU",
		Subtitle = "Réglages, classements et joueurs",
		Size = UDim2.fromScale(0.78, 0.84),
		Parent = layer,
		Accent = Style.Color("AccentCyan"),
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
				rebuild()
			end,
			Parent = tabs,
		})
	end
	body = New("Frame", {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	})
	Store.BoardsChanged:Connect(function()
		if panel:IsOpen() and tab == "Boards" then
			rebuild()
		end
	end)
	App.RegisterPanel("Menu", {
		Panel = panel,
		OnOpen = function(arg: any)
			if type(arg) == "string" then
				tab = arg
			end
			task.defer(rebuild)
		end,
	})
end

return MenuPanel
