--!strict
--[[
	Keycap : le bouton de l'UI, dans le style de l'app AngAInOne (Fluent sombre).
	Plat, coins 8 px, liseré fin ; un voile s'éclaircit au survol et s'assombrit à l'appui, avec un
	léger zoom (Motion.Pressable). Variantes : Primary (violet de l'app), Secondary (gris), Ghost
	(transparent + liseré), Gold (Bits), Success, Cyan. Texte ≥ 18 px de conception (16 en « Small »).
	Le nom « Keycap » est historique (les boutons étaient des touches de clavier mécanique).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)
local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Icon = require(script.Parent.Icon)

local New = Create.New

export type Variant = "Primary" | "Secondary" | "Ghost" | "Gold" | "Success" | "Cyan"

export type Keycap = {
	Button: TextButton,
	Label: TextLabel,
	SetText: (self: Keycap, text: string) -> (),
	SetEnabled: (self: Keycap, enabled: boolean) -> (),
	SetVariant: (self: Keycap, variant: Variant) -> (),
	Destroy: (self: Keycap) -> (),
}

export type Props = {
	Text: string?,
	Variant: Variant?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Icon: string?,
	IconOnly: boolean?,
	LayoutOrder: number?,
	Parent: Instance?,
	OnClick: (() -> ())?,
	Small: boolean?, -- texte compact (listes, onglets)
}

local Keycap = {}

-- Son de clic (branché par Main.client : Audio.Play("Click")).
Keycap.ClickSound = nil :: (() -> ())?

-- Cap : tag de couleur de fond ; Alpha : transparence du fond ; Stroke : liseré visible ;
-- Text : tag du libellé (clair ou sombre).
local VARIANTS: { [string]: { Cap: string, Text: string, Stroke: boolean, Alpha: number } } = {
	Primary = { Cap = "FillAccent", Text = "TextKey", Stroke = false, Alpha = 0 },
	Secondary = { Cap = "GlassRaised", Text = "TextKey", Stroke = true, Alpha = 0 },
	Ghost = { Cap = "GlassRaised", Text = "TextKey", Stroke = true, Alpha = 1 },
	Gold = { Cap = "FillGold", Text = "TextKeyDark", Stroke = false, Alpha = 0 },
	Success = { Cap = "FillSuccess", Text = "TextKeyDark", Stroke = false, Alpha = 0 },
	Cyan = { Cap = "FillCyan", Text = "TextKeyDark", Stroke = false, Alpha = 0 },
}
local CAP_TAGS = { "FillAccent", "GlassRaised", "FillGold", "FillSuccess", "FillCyan" }
local TEXT_TAGS = { "TextKey", "TextKeyDark", "TextKeySmall", "TextKeySmallDark" }

local HOVER = 0.9 -- transparence du voile blanc au survol
local PRESS = 0.75 -- … et du voile noir à l'appui

function Keycap.new(props: Props): Keycap
	local variantName: string = props.Variant or "Secondary"
	local enabled = true

	local button: TextButton = New("TextButton", {
		Name = props.Text or props.Icon or "Keycap",
		Size = props.Size or UDim2.fromOffset(160, 52),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = props.LayoutOrder or 0,
		Selectable = true,
	})
	local cap: Frame = New("Frame", {
		Name = "Cap",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Tag = "RoundS",
		Parent = button,
	})
	local stroke: UIStroke = New("UIStroke", {
		Color = Style.Color("Outline"),
		Thickness = 1,
		Transparency = 0,
		Parent = cap,
	})
	-- Voile de survol / d'appui (blanc clair au survol, noir à l'appui)
	local shade: Frame = New("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Tag = "RoundS",
		Parent = cap,
	})

	local content: Frame = New("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = cap,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 8, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}) :: Instance,
		Create.Padding(4, 12),
	})

	if props.Icon then
		local iconSize = if props.IconOnly then 24 else 20
		local icon = Icon.new(
			props.Icon,
			iconSize,
			if VARIANTS[variantName].Text == "TextKeyDark" then "BgDeep" else "TextPrimary"
		)
		icon.LayoutOrder = 1
		icon.Parent = content
	end

	local label: TextLabel = New("TextLabel", {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = props.Text or "",
		Visible = not props.IconOnly and props.Text ~= nil,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = content,
	})
	-- Le libellé ne déborde jamais du bouton (il est tronqué « … » au besoin).
	local labelLimit: UISizeConstraint = New("UISizeConstraint", { Parent = label })
	local function limitLabel()
		local width = button.AbsoluteSize.X - 24 - (if props.Icon and not props.IconOnly then 28 else 0)
		labelLimit.MaxSize = Vector2.new(math.max(width, 20), math.huge)
	end
	if props.Size and props.Size.X.Scale == 0 then
		labelLimit.MaxSize = Vector2.new(
			math.max(props.Size.X.Offset - 24 - (if props.Icon and not props.IconOnly then 28 else 0), 20),
			math.huge
		)
	else
		button:GetPropertyChangedSignal("AbsoluteSize"):Connect(limitLabel)
	end

	local function applyVariant()
		local v = VARIANTS[variantName]
		for _, name in CAP_TAGS do
			cap:RemoveTag(name)
		end
		cap:AddTag(v.Cap)
		cap.BackgroundTransparency = if enabled then v.Alpha else math.max(v.Alpha, 0.5)
		stroke.Transparency = if v.Stroke then (if enabled then 0 else 0.5) else 1
		for _, tag in TEXT_TAGS do
			label:RemoveTag(tag)
		end
		local dark = v.Text == "TextKeyDark"
		if props.Small then
			label:AddTag(if dark then "TextKeySmallDark" else "TextKeySmall")
		else
			label:AddTag(v.Text)
		end
		label.TextTransparency = if enabled then 0 else 0.45
		Style.ApplyTo(cap)
	end
	applyVariant()

	local hovering = false
	local function restShade()
		if not enabled then
			shade.BackgroundTransparency = 1
			return
		end
		shade.BackgroundColor3 = Color3.new(1, 1, 1)
		Motion.Tween(shade, { BackgroundTransparency = if hovering then HOVER else 1 }, Theme.Motion.Fast)
	end
	local function press(down: boolean)
		if not enabled then
			return
		end
		if down then
			shade.BackgroundColor3 = Color3.new(0, 0, 0)
			Motion.Tween(shade, { BackgroundTransparency = PRESS }, 0.06)
		else
			restShade()
		end
	end

	local cleanup = Motion.Pressable(button)
	button.MouseEnter:Connect(function()
		hovering = true
		restShade()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		restShade()
	end)
	button.MouseButton1Down:Connect(function()
		press(true)
		Motion.TrackPress(button, function()
			press(false)
			Motion.Tween(Motion.ScaleOf(button), { Scale = 1 }, 0.2)
		end)
	end)
	button.MouseButton1Up:Connect(function()
		press(false)
	end)
	button.Activated:Connect(function()
		if not enabled then
			return
		end
		local sound = Keycap.ClickSound
		if sound then
			sound()
		end
		if props.OnClick then
			props.OnClick()
		end
	end)

	if props.Parent then
		button.Parent = props.Parent
	end

	local self = {
		Button = button,
		Label = label,
	}

	function self.SetText(_self: Keycap, text: string)
		label.Text = text
		label.Visible = text ~= "" and not props.IconOnly
	end

	function self.SetEnabled(_self: Keycap, value: boolean)
		if enabled == value then
			return
		end
		enabled = value
		button.Active = value
		applyVariant()
		restShade()
	end

	function self.SetVariant(_self: Keycap, variant: Variant)
		if variantName == variant then
			return
		end
		variantName = variant
		applyVariant()
	end

	function self.Destroy(_self: Keycap)
		cleanup()
		button:Destroy()
	end

	return (self :: any) :: Keycap
end

return Keycap
