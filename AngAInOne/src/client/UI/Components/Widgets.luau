--!strict
--[[
	Widgets : petits composants réutilisables.
	- Bar      : barre de progression lumineuse (avec balayage de reflet)
	- Pill     : capsule de verre (monnaies, effets actifs)
	- Avatar   : pastille d'Anga (image importée ou monogramme "A")
	- Badge    : pastille de notification sur un bouton
	- Card     : carte de liste en verre surélevé
	- Text     : raccourci TextLabel
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Branding = require(Shared.Config.Branding)
local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Icon = require(script.Parent.Icon)

local New = Create.New

local Widgets = {}

export type Bar = {
	Root: Frame,
	Fill: Frame,
	Set: (self: Bar, ratio: number, animate: boolean?) -> (),
	SetColor: (self: Bar, color: Color3) -> (),
}

function Widgets.Text(props: { [string]: any }): TextLabel
	local label: TextLabel = New("TextLabel", {
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	for key, value in props do
		if key == "Tag" then
			if type(value) == "table" then
				for _, tag in value do
					label:AddTag(tag)
				end
			else
				label:AddTag(value)
			end
		elseif key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	if props.Parent then
		label.Parent = props.Parent
	end
	return label
end

function Widgets.Bar(size: UDim2, color: Color3, parent: Instance?): Bar
	local root: Frame = New("Frame", {
		Name = "Bar",
		Size = size,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Tag = { "GlassSunken", "RoundPill" },
		Parent = parent,
	})
	local fill: Frame = New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Tag = "RoundPill",
		Parent = root,
	}, {
		New("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210)),
		}),
	})
	local bar = { Root = root, Fill = fill }
	function bar.Set(_self: Bar, ratio: number, animate: boolean?)
		local target = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		if animate == false then
			fill.Size = target
		else
			Motion.Tween(fill, { Size = target }, 0.35)
		end
	end
	function bar.SetColor(_self: Bar, value: Color3)
		fill.BackgroundColor3 = value
	end
	return (bar :: any) :: Bar
end

export type Pill = { Root: Frame, Value: TextLabel, Sub: TextLabel? }

function Widgets.Pill(iconKind: string, valueTag: string, width: number, parent: Instance?, withSub: boolean?): Pill
	local height = if withSub then 52 else 40
	local root: Frame = New("Frame", {
		Name = `Pill_{iconKind}`,
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundPill" },
		Parent = parent,
	}, {
		New("UIStroke", { Color = Style.Color("Stroke"), Transparency = Theme.Alpha.StrokeSoft, Thickness = 1 }),
	})
	local icon = Icon.new(iconKind, 26, nil)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Parent = root
	local value: TextLabel = New("TextLabel", {
		Name = "Value",
		Position = UDim2.new(0, 44, 0, if withSub then 5 else 0),
		Size = UDim2.new(1, -54, 0, if withSub then 26 else height),
		BackgroundTransparency = 1,
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = valueTag,
		Parent = root,
	})
	local sub: TextLabel? = nil
	if withSub then
		sub = New("TextLabel", {
			Name = "Sub",
			Position = UDim2.new(0, 44, 0, 30),
			Size = UDim2.new(1, -54, 0, 16),
			BackgroundTransparency = 1,
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextCaption",
			Parent = root,
		})
	end
	return { Root = root, Value = value, Sub = sub }
end

-- Pastille de la mascotte : image importée si Branding.AngaImageId est rempli.
function Widgets.Avatar(size: number, parent: Instance?): Frame
	local root: Frame = New("Frame", {
		Name = "AngaAvatar",
		Size = UDim2.fromOffset(size, size),
		BorderSizePixel = 0,
		Tag = { "FillBrand", "RoundPill" },
		Parent = parent,
	}, {
		New("UIStroke", { Color = Style.Color("TextPrimary"), Thickness = 2, Transparency = 0.2 }),
	})
	if Branding.AngaImageId ~= "" then
		New("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = Branding.AngaImageId,
			ScaleType = Enum.ScaleType.Crop,
			Tag = "RoundPill",
			Parent = root,
		})
	else
		New("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "A",
			TextScaled = true,
			Tag = "TextTitle",
			Parent = root,
		}, {
			Create.Padding(math.floor(size * 0.2)),
		})
	end
	return root
end

function Widgets.Badge(parent: GuiObject): Frame
	local badge: Frame = New("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(14, 14),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 30,
		Tag = { "FillBrand", "RoundPill" },
		Parent = parent,
	}, {
		New("UIStroke", { Color = Style.Color("BgDeep"), Thickness = 2 }),
	})
	return badge
end

function Widgets.Card(size: UDim2, parent: Instance?, layoutOrder: number?): Frame
	local card: Frame = New("Frame", {
		Name = "Card",
		Size = size,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder or 0,
		Tag = { "GlassRaised", "RoundS" },
		Parent = parent,
	}, {
		New("UIStroke", { Color = Style.Color("Outline"), Transparency = 0, Thickness = 1 }),
	})
	return card
end

-- Liste défilante verticale prête à l'emploi (padding + layout).
function Widgets.Scroll(parent: Instance, padding: number?): ScrollingFrame
	local scroll: ScrollingFrame = New("ScrollingFrame", {
		Name = "Scroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Style.Color("TextMuted"),
		ScrollBarImageTransparency = 0.4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 21,
		Parent = parent,
	}, {
		Create.List(Enum.FillDirection.Vertical, padding or 10),
		New(
			"UIPadding",
			{ PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingTop = UDim.new(0, 2) }
		),
	})
	return scroll
end

return Widgets
