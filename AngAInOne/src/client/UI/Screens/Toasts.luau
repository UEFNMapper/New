--!strict
--[[
	Toasts : notifications non bloquantes en haut à droite (max 4, 3,5 s).
	Chaque toast : barre d'accent colorée, icône, texte. Glisse depuis la droite.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)
local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Icon = require(script.Parent.Parent.Components.Icon)

local New = Create.New

local Toasts = {}

local container: Frame
local MAX = 4
local order = 0

local KINDS: { [string]: { Color: string, Icon: string } } = {
	Success = { Color = "Success", Icon = "Check" },
	Error = { Color = "Danger", Icon = "Close" },
	Info = { Color = "AccentCyan", Icon = "Cpu" },
	Quest = { Color = "AccentViolet", Icon = "Quest" },
	Milestone = { Color = "CurrencyBits", Icon = "Star" },
	Boost = { Color = "BrandAnga", Icon = "Bolt" },
	Like = { Color = "BrandAnga", Icon = "Heart" },
	Reward = { Color = "CurrencyChips", Icon = "Gift" },
	Fragment = { Color = "AccentViolet", Icon = "Star" },
}

function Toasts.Mount(layer: Frame)
	container = New("Frame", {
		Name = "ToastStack",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 70),
		Size = UDim2.fromOffset(340, 400),
		BackgroundTransparency = 1,
		Parent = layer,
	}, {
		Create.List(Enum.FillDirection.Vertical, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Right }),
	})
end

function Toasts.Show(kind: string, text: string)
	if not container then
		return
	end
	local style = KINDS[kind] or KINDS.Info
	local accent = Style.Color(style.Color)
	local toasts = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts >= MAX then
		table.sort(toasts, function(a: Frame, b: Frame): boolean
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	order += 1

	local holder: Frame = New("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(340, 58),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = container,
	})
	local card: Frame = New("Frame", {
		Name = "Card",
		Position = UDim2.fromOffset(360, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundM" },
		Parent = holder,
	}, {
		New("UIStroke", { Color = accent, Transparency = 0.55, Thickness = 1 }),
		New("UIShadow", {
			BlurRadius = UDim.new(0, 14),
			Transparency = 0.5,
			Offset = UDim2.fromOffset(0, 4),
			Color = Style.Color("BgDeep"),
		}),
	})
	New("Frame", {
		Name = "Accent",
		Position = UDim2.fromOffset(6, 10),
		Size = UDim2.new(0, 4, 1, -20),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Tag = "RoundPill",
		Parent = card,
	})
	local icon = Icon.new(style.Icon, 24, style.Color)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 20, 0.5, 0)
	icon.Parent = card
	New("TextLabel", {
		Position = UDim2.fromOffset(54, 0),
		Size = UDim2.new(1, -64, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextBody",
		Parent = card,
	})

	Motion.Tween(card, { Position = UDim2.fromOffset(0, 0) }, 0.3, Enum.EasingStyle.Back)
	task.delay(3.5, function()
		if card.Parent then
			local out = Motion.Tween(
				card,
				{ Position = UDim2.fromOffset(360, 0) },
				0.25,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			out.Completed:Once(function()
				holder:Destroy()
			end)
		end
	end)
end

return Toasts
