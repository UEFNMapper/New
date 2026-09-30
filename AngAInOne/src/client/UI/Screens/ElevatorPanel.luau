--!strict
--[[
	ElevatorPanel : se déplacer entre les étages débloqués de sa tour, ou revenir au hub.
	Le serveur valide (étage débloqué, 1 trajet par seconde).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Panel = require(script.Parent.Parent.Components.Panel)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local App = require(script.Parent.Parent.App)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local ElevatorPanel = {}

-- Branché par le contrôleur de transitions (fondu + son) avant le déplacement.
ElevatorPanel.BeforeTravel = nil :: ((floor: number) -> ())?

local panel: Panel.Panel
local keys: { [number]: Keycap.Keycap } = {}

local function travel(floor: number)
	if ElevatorPanel.BeforeTravel then
		ElevatorPanel.BeforeTravel(floor)
	end
	Net.Fire("Travel", floor)
	App.Close()
end

local function refresh()
	local data = Store.Data()
	if not data then
		return
	end
	for floor, key in keys do
		if floor > 0 then
			local zone = Zones[floor]
			local unlocked = floor <= data.Zone
			key:SetEnabled(unlocked)
			key:SetText(if unlocked then `{floor}  ·  {zone.Name}` else `{floor}  ·  Verrouillé`)
		end
	end
end

function ElevatorPanel.Mount(layer: Frame)
	panel = Panel.new({
		Name = "ElevatorPanel",
		Title = "ASCENSEUR",
		Subtitle = "Choisis ton étage",
		Size = UDim2.fromOffset(460, 620),
		Parent = layer,
		Accent = Style.Color("AccentCyan"),
	})
	local scroll = Widgets.Scroll(panel.Body, 8)
	for floor = #Zones, 1, -1 do
		local zone = Zones[floor]
		local key = Keycap.new({
			Text = zone.Name,
			Variant = "Secondary",
			Size = UDim2.new(1, -4, 0, 56),
			LayoutOrder = #Zones - floor + 1,
			Small = true,
			OnClick = function()
				travel(floor)
			end,
			Parent = scroll,
		})
		New("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, -2),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Color3.fromHex(zone.Primary),
			BorderSizePixel = 0,
			Tag = "RoundPill",
			Parent = key.Button:FindFirstChild("Cap"),
		})
		keys[floor] = key
	end
	keys[0] = Keycap.new({
		Text = "Hub · Carte mère",
		Variant = "Ghost",
		Size = UDim2.new(1, -4, 0, 56),
		LayoutOrder = 100,
		Small = true,
		OnClick = function()
			travel(0)
		end,
		Parent = scroll,
	})
	Store.Changed:Connect(function()
		if panel:IsOpen() then
			refresh()
		end
	end)
	App.RegisterPanel("Elevator", {
		Panel = panel,
		OnOpen = function(_arg: any)
			refresh()
		end,
	})
end

return ElevatorPanel
