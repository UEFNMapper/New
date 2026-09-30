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
		Position = UDim2.fromOffset(270, 12),
		Size = UDim2.fromOffset(200, 400),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
		Tag = { "Backdrop", "RoundM" },
		Parent = layer,
	}, {
		Create.List(Enum.FillDirection.Vertical, 6) :: Instance,
		Create.Padding(8),
	})
	local function stage(): number
		local data = Store.Data()
		return if data then data.Stage else 0
	end
	local actions: { { Label: string, Run: () -> () } } = {
		{
			Label = "+1 000 Bits",
			Run = function()
				Net.Fire("DevCommand", "Bits", 1000)
			end,
		},
		{
			Label = "Étape suivante",
			Run = function()
				Net.Fire("DevCommand", "Stage", stage() + 1)
			end,
		},
		{
			Label = "Monde suivant",
			Run = function()
				Net.Fire("DevCommand", "Stage", (math.floor(stage() / 5) + 1) * 5)
			end,
		},
		{
			Label = "Réussir le terminal",
			Run = function()
				Net.Fire("DevCommand", "Clear", 0)
			end,
		},
		{
			Label = "Aller au sommet",
			Run = function()
				Net.Fire("DevCommand", "Stage", 35)
			end,
		},
		{
			Label = "Bouclier 30 s",
			Run = function()
				Net.Fire("DevCommand", "Shield", 30)
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
		Position = UDim2.fromOffset(270, 130),
		Small = true,
		OnClick = function()
			panel.Visible = not panel.Visible
		end,
		Parent = layer,
	}).Button.ZIndex =
		50
	panel.Position = UDim2.fromOffset(270, 172)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then
			panel.Visible = not panel.Visible
		end
	end)
end

return DevPanel
