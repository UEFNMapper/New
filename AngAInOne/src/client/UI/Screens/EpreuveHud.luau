--!strict
--[[
	EpreuveHud : la carte de l'épreuve en cours, en haut au centre (à la place de la carte de
	progression), au style de l'app : fil d'Ariane « AngAInOne › Page », titre, liste à cocher,
	ligne d'état, barre de progression, bouton « Abandonner ».
	API (Controllers/Epreuves) : Show(def, onQuit), Hide(), Step(i, done, text?), Status(text),
	Bar(fraction?, label?).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)
local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Keycap = require(script.Parent.Parent.Components.Keycap)

local New = Create.New
local F = Style.Fonts

local EpreuveHud = {}

local WIDTH = 600
local root: Frame? = nil
local crumb: TextLabel
local title: TextLabel
local list: Frame
local status: TextLabel
local barTrack: Frame
local barFill: Frame
local barLabel: TextLabel
local quitKey: Keycap.Keycap
local onQuit: (() -> ())? = nil
local rows: { { Check: TextLabel, Label: TextLabel } } = {}

local function label(parent: Instance, props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextColor3 = props.TextColor3 or Style.Color("TextPrimary")
	props.Parent = parent
	return New("TextLabel", props)
end

function EpreuveHud.Mount(layer: Frame)
	local card: Frame = New("Frame", {
		Name = "Epreuve",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Style.Color("Surface"),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = layer,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, Theme.Radius.L) }),
		New("UIStroke", { Color = Style.Color("Outline"), Thickness = 1 }),
		New("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 18),
			PaddingRight = UDim.new(0, 18),
		}),
		Create.List(Enum.FillDirection.Vertical, 6) :: Instance,
	})
	root = card
	crumb = label(card, {
		Size = UDim2.new(1, -150, 0, 22),
		RichText = true,
		Text = "",
		FontFace = F.Medium,
		TextSize = 18,
		LayoutOrder = 1,
		ZIndex = 6,
	})
	quitKey = Keycap.new({
		Text = "Abandonner",
		Variant = "Ghost",
		Size = UDim2.fromOffset(136, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		Small = true,
		OnClick = function()
			if onQuit then
				onQuit()
			end
		end,
	})
	-- Le bouton flotte en haut à droite (hors de la liste verticale).
	local corner: Frame = New("Frame", {
		Name = "Corner",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		ZIndex = 6,
		Parent = card,
	})
	quitKey.Button.Parent = corner
	title = label(card, {
		Size = UDim2.new(1, -150, 0, 30),
		Text = "",
		FontFace = F.Heavy,
		TextSize = 26,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		ZIndex = 6,
	})
	list = New("Frame", {
		Name = "Steps",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ZIndex = 6,
		Parent = card,
	}, { Create.List(Enum.FillDirection.Vertical, 4) :: Instance })
	status = label(card, {
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		FontFace = F.Bold,
		TextSize = 18,
		TextColor3 = Style.Color("TextMuted"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 4,
		ZIndex = 6,
	})
	local bar: Frame = New("Frame", {
		Name = "Bar",
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 5,
		ZIndex = 6,
		Parent = card,
	})
	barTrack = New("Frame", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Style.Color("SurfaceRaised"),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = bar,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	barFill = New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Style.Color("AppAccent"),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = barTrack,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	barLabel = label(bar, {
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		FontFace = F.Medium,
		TextSize = 18,
		TextColor3 = Style.Color("TextMuted"),
		ZIndex = 6,
	})
end

function EpreuveHud.Show(def: any, quit: (() -> ())?)
	local card = root
	if not card then
		return
	end
	onQuit = quit
	crumb.Text = `<font color="#{Theme.Colors.TextDim}">AngAInOne   ›   </font>{def.Page}`
	title.Text = `{def.Step} · {def.Name}`
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(rows)
	for index, text in def.Steps do
		local row: Frame = New("Frame", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			ZIndex = 6,
			Parent = list,
		})
		local check = label(row, {
			Size = UDim2.fromOffset(28, 28),
			Text = "○",
			FontFace = F.Heavy,
			TextSize = 22,
			TextColor3 = Style.Color("TextDim"),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
		})
		local text_ = label(row, {
			Position = UDim2.fromOffset(36, 0),
			Size = UDim2.new(1, -36, 1, 0),
			Text = text,
			FontFace = F.Medium,
			TextSize = 20,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 6,
		})
		rows[index] = { Check = check, Label = text_ }
	end
	status.Text = ""
	EpreuveHud.Bar(nil)
	quitKey.Button.Visible = quit ~= nil
	card.Visible = true
	Motion.Pop(card, 0.08)
end

function EpreuveHud.Hide()
	if root then
		root.Visible = false
	end
	onQuit = nil
end

function EpreuveHud.Step(index: number, done: boolean, text: string?)
	local row = rows[index]
	if not row then
		return
	end
	row.Check.Text = if done then "✓" else "○"
	row.Check.TextColor3 = Style.Color(if done then "Success" else "TextDim")
	row.Label.TextColor3 = Style.Color(if done then "TextMuted" else "TextPrimary")
	if text then
		row.Label.Text = text
	end
	if done then
		Motion.Pop(row.Check, 0.3)
	end
end

function EpreuveHud.Status(text: string)
	if status then
		status.Text = text
	end
end

-- Barre de progression (nil = cachée).
function EpreuveHud.Bar(fraction: number?, text: string?)
	if not barFill then
		return
	end
	local bar = barTrack.Parent :: Frame
	bar.Visible = fraction ~= nil
	if fraction then
		barFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		barLabel.Text = text or ""
	end
end

return EpreuveHud
