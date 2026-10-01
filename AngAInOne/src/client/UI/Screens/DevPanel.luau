--!strict
--[[
	DevPanel : panneau de test visible UNIQUEMENT dans Roblox Studio (touche F8 ou bouton « DEV »
	en haut à gauche). Le serveur ignore ces commandes en ligne.
	- Test rapide : Bits, étapes, terminal, sommet, bouclier, remise à zéro.
	- Nouveautés (Config/DevFeatures) : un bouton par nouveauté, qui t'y emmène (monde encore
	  infecté) ou la lance directement (BIOS, Stream Deck, mini-jeux sans récompense, rôles, jauges).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DevFeatures = require(ReplicatedStorage:WaitForChild("Shared").Config.DevFeatures)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local App = require(script.Parent.Parent.App)
local Toasts = require(script.Parent.Toasts)
local MinigamePanel = require(script.Parent.MinigamePanel)
local Moments = require(script.Parent.Moments)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local DevPanel = {}

local LOBBY_SPAWN = Vector3.new(-30, 4, -290)

local function lobby(): Instance?
	local tower = Workspace:FindFirstChild("Tower")
	return if tower then tower:FindFirstChild("Lobby") else nil
end

-- Va au lobby si besoin, puis téléporte le personnage (les pieds 3 studs sous `position`).
local function teleport(position: Vector3)
	local player = Players.LocalPlayer
	task.spawn(function()
		local state = Store.State
		if state and not state.AtLobby then
			Net.Fire("ToLobby")
			task.wait(1.2)
		end
		pcall(function()
			player:RequestStreamAroundAsync(position)
		end)
		local character = player.Character
		if character then
			character:PivotTo(CFrame.new(position))
		end
	end)
end

local function find(name: string): BasePart?
	local root = lobby()
	local found = if root then root:FindFirstChild(name, true) else nil
	return if found and found:IsA("BasePart") then found else nil
end

-- Contrôleur des mécaniques (chargé après l'UI ; nil tant qu'il n'a pas démarré).
local function mechanics(): any
	local ok, module = pcall(function()
		return require(script.Parent.Parent.Parent.Controllers.Mechanics) :: any
	end)
	return if ok then module else nil
end

-- Contrôleur des épreuves (chargé après l'UI).
local function epreuves(): any
	local ok, module = pcall(function()
		return require(script.Parent.Parent.Parent.Controllers.Epreuves) :: any
	end)
	return if ok then module else nil
end

local CLIENT_ACTIONS: { [string]: () -> () } = {
	Intrusion = function()
		App.Close()
		Moments.Intrusion(function()
			Moments.Intro(function() end)
		end)
	end,
	Investigation = function()
		local e = epreuves()
		if
			e
			and not e.Start(7, function()
				Toasts.Show("Success", "[DEV] Enquête terminée : en jeu, la quarantaine lance le Firewall boss.")
			end)
		then
			Toasts.Show("Info", "[DEV] Va d'abord dans la salle du monde 7 (Aller au sommet).")
		end
	end,
	Bios = function()
		local root = lobby()
		local bios = if root then root:FindFirstChild("Bios") else nil
		local spawn = if bios then bios:GetAttribute("Spawn") else nil
		if typeof(spawn) == "Vector3" then
			teleport(spawn)
		else
			Toasts.Show("Info", "[DEV] Salle du BIOS introuvable.")
		end
	end,
	BiosKey = function()
		local key = find("BiosKey")
		if key then
			teleport(key.Position + Vector3.new(0, 3, 7))
		end
	end,
	Deck = function()
		local root = lobby()
		local deck = if root then root:FindFirstChild("StreamDeck", true) else nil
		local key = if deck then deck:FindFirstChild("StreamDeckKey", true) else nil
		if key and key:IsA("BasePart") then
			local toSpawn = (LOBBY_SPAWN - key.Position) * Vector3.new(1, 0, 1)
			teleport(key.Position + toSpawn.Unit * 14 + Vector3.new(0, 4, 0))
		end
	end,
	PlayTri = function()
		MinigamePanel.Play("Tri", 3, function() end)
	end,
	PlayDefense = function()
		MinigamePanel.Play("Defense", 3, function() end)
	end,
	Roles = function()
		App.Open("Menu", "Role")
	end,
	Ram90 = function()
		local m = mechanics()
		if m and m.ActiveWorld() == 2 then
			m.DevSet("Ram", 90)
		else
			Toasts.Show("Info", "[DEV] Va d'abord dans le monde 2 (bouton « RAM + boutons »).")
		end
	end,
	Heat90 = function()
		local m = mechanics()
		if m and m.ActiveWorld() == 4 then
			m.DevSet("Heat", 90)
		else
			Toasts.Show("Info", "[DEV] Va d'abord dans le monde 4 (bouton « Chaleur »).")
		end
	end,
}

function DevPanel.Mount(layer: Frame)
	if not RunService:IsStudio() then
		return
	end
	local panel: Frame = New("Frame", {
		Name = "DevPanel",
		Position = UDim2.fromOffset(270, 172),
		Size = UDim2.fromOffset(300, 520),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 49,
		Tag = { "Glass", "RoundM" },
		Parent = layer,
	}, {
		New("UIStroke", { Color = Style.Color("Outline"), Thickness = 1 }),
	})
	local scroll: ScrollingFrame = New("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 50,
		Parent = panel,
	}, {
		Create.List(Enum.FillDirection.Vertical, 6) :: Instance,
		New("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})

	local order = 0
	local function heading(text: string)
		order += 1
		New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			ZIndex = 51,
			Tag = "TextHeading",
			Parent = scroll,
		})
	end
	local function button(label: string, variant: Keycap.Variant, run: () -> ())
		order += 1
		local key = Keycap.new({
			Text = label,
			Variant = variant,
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = order,
			Small = true,
			OnClick = run,
			Parent = scroll,
		})
		key.Button.ZIndex = 51
	end
	local function stage(): number
		local data = Store.Data()
		return if data then data.Stage else 0
	end

	heading("NOUVEAUTÉS À TESTER")
	for index, feature in DevFeatures.List do
		button(feature.Label, "Primary", function()
			local client = feature.Client
			if client then
				local action = CLIENT_ACTIONS[client]
				if action then
					action()
				end
			else
				Net.Fire("DevCommand", "Feature", index)
				local world = feature.World
				if feature.Epreuve and world then
					-- Lancement automatique une fois arrivé devant la borne
					task.delay(2, function()
						local e = epreuves()
						if e and not e.IsRunning() then
							e.Start(world)
						end
					end)
				end
			end
			if client ~= "Roles" and client ~= "Ram90" and client ~= "Heat90" then
				panel.Visible = false
			end
		end)
	end

	heading("TEST RAPIDE")
	button("+1 000 Bits", "Secondary", function()
		Net.Fire("DevCommand", "Bits", 1000)
	end)
	button("Étape suivante", "Secondary", function()
		Net.Fire("DevCommand", "Stage", stage() + 1)
	end)
	button("Monde suivant", "Secondary", function()
		Net.Fire("DevCommand", "Stage", (math.floor(stage() / 5) + 1) * 5)
	end)
	button("Réussir le terminal", "Secondary", function()
		Net.Fire("DevCommand", "Clear", 0)
	end)
	button("Aller au sommet", "Secondary", function()
		Net.Fire("DevCommand", "Stage", 35)
	end)
	button("Bouclier 30 s", "Secondary", function()
		Net.Fire("DevCommand", "Shield", 30)
	end)
	button("RESET sauvegarde", "Ghost", function()
		Net.Fire("DevCommand", "Reset", 0)
	end)

	Keycap.new({
		Text = "DEV",
		Variant = "Primary",
		Size = UDim2.fromOffset(72, 40),
		Position = UDim2.fromOffset(270, 128),
		Small = true,
		OnClick = function()
			panel.Visible = not panel.Visible
		end,
		Parent = layer,
	}).Button.ZIndex =
		50
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then
			panel.Visible = not panel.Visible
		end
	end)
end

return DevPanel
