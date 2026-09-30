--!strict
--[[
	Keycap : bouton façon touche de clavier mécanique.
	Un socle sombre + un capuchon qui s'enfonce à l'appui (et un léger zoom au survol).
	Variantes : Primary (rouge Anga, CTA unique par écran), Secondary (métal brossé),
	Ghost (verre), Gold, Success, Cyan.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)
local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
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
	Small: boolean?, -- texte compact (listes, onglets) ; couleur claire/foncée selon la variante
}

local Keycap = {}

-- Son de clic, branché par le contrôleur audio.
Keycap.ClickSound = nil :: (() -> ())?

local VARIANTS: { [string]: { Cap: string, Base: string, Text: string, Brushed: boolean, Alpha: number } } = {
	Primary = { Cap = "FillBrand", Base = "BrandAngaDark", Text = "TextKey", Brushed = false, Alpha = 0 },
	Secondary = { Cap = "Metal", Base = "MetalDark", Text = "TextKey", Brushed = true, Alpha = 0 },
	Ghost = {
		Cap = "GlassRaised",
		Base = "SurfaceSunken",
		Text = "TextKey",
		Brushed = false,
		Alpha = Theme.Alpha.Glass,
	},
	Gold = { Cap = "FillGold", Base = "AccentAmber", Text = "TextKeyDark", Brushed = false, Alpha = 0 },
	Success = { Cap = "FillSuccess", Base = "BgDeep", Text = "TextKeyDark", Brushed = false, Alpha = 0 },
	Cyan = { Cap = "FillCyan", Base = "BgDeep", Text = "TextKeyDark", Brushed = false, Alpha = 0 },
}

local DEPTH = 4

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
	local base: Frame = New("Frame", {
		Name = "Base",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Tag = "RoundM",
		Parent = button,
	})
	local cap: Frame = New("Frame", {
		Name = "Cap",
		Size = UDim2.new(1, 0, 1, -DEPTH),
		BorderSizePixel = 0,
		Tag = "RoundM",
		Parent = button,
	})
	-- Reflet supérieur du capuchon
	New("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -8, 0.45, 0),
		Position = UDim2.fromOffset(4, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.88,
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
		Create.Padding(4, 10),
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
	-- Borne la largeur du texte à celle de la touche (sinon AutomaticSize.X empêche la troncature).
	local labelLimit = Instance.new("UISizeConstraint")
	labelLimit.Parent = label
	local function limitLabel()
		local iconWidth = if props.Icon and not props.IconOnly then 28 else 0
		-- AbsoluteSize inclut les UIScale des ancêtres : on revient en pixels de conception.
		local cumulative = 1
		local current: Instance? = button
		while current do
			local uiScale = current:FindFirstChildOfClass("UIScale")
			if uiScale then
				cumulative *= uiScale.Scale
			end
			current = current.Parent
		end
		local width = button.AbsoluteSize.X / math.max(cumulative, 0.01)
		labelLimit.MaxSize = Vector2.new(math.max(width - 24 - iconWidth, 20), math.huge)
	end
	if props.Size and props.Size.X.Scale == 0 then
		labelLimit.MaxSize = Vector2.new(
			math.max(props.Size.X.Offset - 24 - (if props.Icon and not props.IconOnly then 28 else 0), 20),
			math.huge
		)
	else
		button:GetPropertyChangedSignal("AbsoluteSize"):Connect(limitLabel)
	end

	local brushed: UIGradient? = nil

	local function applyVariant()
		local v = VARIANTS[variantName]
		for _, name in { "FillBrand", "Metal", "GlassRaised", "FillGold", "FillSuccess", "FillCyan" } do
			cap:RemoveTag(name)
		end
		cap:AddTag(v.Cap)
		cap.BackgroundTransparency = if enabled then v.Alpha else 0.45
		base.BackgroundColor3 = Style.Color(v.Base)
		base.BackgroundTransparency = if enabled then 0 else 0.5
		for _, tag in { "TextKey", "TextKeyDark", "TextKeySmall", "TextKeySmallDark" } do
			label:RemoveTag(tag)
		end
		local dark = v.Text == "TextKeyDark"
		if props.Small then
			label:AddTag(if dark then "TextKeySmallDark" else "TextKeySmall")
		else
			label:AddTag(v.Text)
		end
		label.TextTransparency = if enabled then 0 else 0.45
		if v.Brushed and not brushed then
			Material.Brushed(cap)
			brushed = cap:FindFirstChildOfClass("UIGradient")
		elseif not v.Brushed and brushed then
			brushed:Destroy()
			brushed = nil
		end
		Style.ApplyTo(cap)
	end
	applyVariant()

	local function press(down: boolean)
		if not enabled then
			return
		end
		Motion.Tween(
			cap,
			{ Position = UDim2.fromOffset(0, if down then DEPTH - 1 else 0) },
			if down then 0.06 else 0.18
		)
	end

	local cleanup = Motion.Pressable(button)
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
	button.MouseLeave:Connect(function()
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
