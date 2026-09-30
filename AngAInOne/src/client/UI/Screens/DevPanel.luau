--!strict
--[[
	DevPanel : petit panneau de test visible UNIQUEMENT dans Roblox Studio (touche F8
	ou bouton "DEV" en haut à gauche). Le serveur ignore ces commandes en ligne.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Store = require(script.Parent.Parent.Parent.Controllers.Store)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local DevPanel = {}

function DevPanel.Mount(layer: Frame)
	if not RunService:IsStudio() then
		return
	end
	local panel: Frame = New("Frame", {
		Name = "DevPanel",
		Position = UDim2.fromOffset(310, 12),
		Size = UDim2.fromOffset(200, 420),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
		Tag = { "Backdrop", "RoundM" },
		Parent = layer,
	}, {
		Create.List(Enum.FillDirection.Vertical, 6) :: Instance,
		Create.Padding(8),
	})
	local function bits(multiplier: number): number
		return math.max(Store.Rate(), 1) * multiplier
	end
	local actions: { { Label: string, Run: () -> () } } = {
		{
			Label = "+10 min de Bits",
			Run = function()
				Net.Fire("DevCommand", "Bits", bits(600))
			end,
		},
		{
			Label = "+1 h de Bits",
			Run = function()
				Net.Fire("DevCommand", "Bits", bits(3600))
			end,
		},
		{
			Label = "+1e15 Bits",
			Run = function()
				Net.Fire("DevCommand", "Bits", 1e15)
			end,
		},
		{
			Label = "+500 Chips",
			Run = function()
				Net.Fire("DevCommand", "Chips", 500)
			end,
		},
		{
			Label = "Étage suivant",
			Run = function()
				local data = Store.Data()
				Net.Fire("DevCommand", "Zone", if data then data.Zone + 1 else 2)
			end,
		},
		{
			Label = "Finir le tutoriel",
			Run = function()
				Net.Fire("DevCommand", "Tutorial", 8)
			end,
		},
		{
			Label = "Activer les virus",
			Run = function()
				Net.Fire("DevCommand", "Virus", 0)
			end,
		},
		{
			Label = "RESET sauvegarde",
			Run = function()
				Net.Fire("DevCommand", "Reset", 0)
			end,
		},
	}
	for index, action in actions do
		Keycap.new({
			Text = action.Label,
			Variant = if index == #actions then "Primary" else "Secondary",
			Size = UDim2.new(1, 0, 0, 42),
			LayoutOrder = index,
			Small = true,
			OnClick = action.Run,
			Parent = panel,
		})
	end
	Keycap.new({
		Text = "DEV",
		Variant = "Ghost",
		Size = UDim2.fromOffset(64, 36),
		Position = UDim2.fromOffset(310, 12),
		Small = true,
		OnClick = function()
			panel.Visible = not panel.Visible
		end,
		Parent = layer,
	}).Button.ZIndex =
		50
	panel.Position = UDim2.fromOffset(310, 54)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then
			panel.Visible = not panel.Visible
		end
	end)
end

return DevPanel
