--!strict
--[[
	ElevatorPanel : la CARTE DU PC (dock « Carte », touche T, pads téléporteurs).
	Une grande carte vue de dessus : on touche une zone débloquée pour s'y téléporter.
	Zone verrouillée : on explique simplement où l'ouvrir. Le serveur valide chaque voyage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Config.WorldLayout)
local NumberFormat = require(Shared.Util.NumberFormat)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Panel = require(script.Parent.Parent.Components.Panel)
local MapView = require(script.Parent.Parent.Components.MapView)
local App = require(script.Parent.Parent.App)
local Toasts = require(script.Parent.Toasts)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)
local WorldFx = require(script.Parent.Parent.Parent.Controllers.WorldFx)
local Guide = require(script.Parent.Parent.Parent.Controllers.Guide)

local New = Create.New

local ElevatorPanel = {}

-- Branché par le contrôleur de transitions (son) avant le déplacement.
ElevatorPanel.BeforeTravel = nil :: ((zone: number) -> ())?

local panel: Panel.Panel
local map: MapView.MapView
local hint: TextLabel

local function travel(zone: number)
	local data = Store.Data()
	if not data then
		return
	end
	if zone > data.Zone then
		local layout = WorldLayout.Zones[zone]
		local from = if layout.Parent == 0 then "le hub" else Zones[layout.Parent].Name
		Toasts.Show(
			"Info",
			`{Zones[zone].Name} est fermée. Ouvre-la au portail dans {from} ({NumberFormat.Compact(
				Zones[zone].UnlockCost
			)} Bits).`
		)
		return
	end
	if zone == WorldFx.CurrentZone then
		App.Close()
		return
	end
	if ElevatorPanel.BeforeTravel then
		ElevatorPanel.BeforeTravel(zone)
	end
	Net.Fire("Travel", zone)
	App.Close()
end

local function refresh()
	local data = Store.Data()
	if data then
		map:Refresh(data.Zone, WorldFx.CurrentZone)
	end
end

function ElevatorPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "ElevatorPanel",
		Title = "CARTE DU PC",
		Subtitle = "Touche une zone pour y aller !",
		Size = UDim2.fromScale(0.72, 0.86),
		Parent = layer,
		Accent = Style.Color("AccentCyan"),
	})
	map = MapView.new({
		Parent = panel.Body,
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Compact = false,
		OnSelect = travel,
	})
	hint = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Text = "⭐ = ton objectif   ·   ● = toi",
		TextScaled = true,
		TextColor3 = Style.Color("TextMuted"),
		Tag = "FontBold",
		Parent = panel.Body,
	}, { New("UITextSizeConstraint", { MaxTextSize = 18 }) :: Instance })

	-- Joueur et objectif sur la carte, tant qu'elle est ouverte
	task.spawn(function()
		while true do
			task.wait(0.1)
			if panel:IsOpen() then
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local camera = Workspace.CurrentCamera
				map:SetPlayer(
					if root and root:IsA("BasePart") then root.Position else nil,
					if camera then camera.CFrame.LookVector else nil
				)
				map:SetTarget(Guide.Target)
			end
		end
	end)
	Store.Changed:Connect(function()
		if panel:IsOpen() then
			refresh()
		end
	end)
	App.RegisterPanel("Elevator", {
		Panel = panel,
		OnOpen = function(_arg: any)
			refresh()
			hint.Visible = true
		end,
	})
end

return ElevatorPanel
