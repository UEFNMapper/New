--!strict
--[[
	Panel : fenêtre "boîtier de PC" en matériau dynamique.
	Verre fumé + reflet animé, plaque de métal brossé en en-tête, bordure RGB réactive
	à la chaleur, vis aux coins, pistes de circuit, ombre native (UIShadow).
	Ouverture : zoom Back + glissement + voile (0,28 s) ; fermeture rapide (0,18 s).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)
local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Keycap)

local New = Create.New

export type Panel = {
	Window: Frame,
	Body: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	OnClose: (() -> ())?,
	IsOpen: (self: Panel) -> boolean,
	Open: (self: Panel) -> (),
	Close: (self: Panel) -> (),
	SetTitle: (self: Panel, title: string, subtitle: string?) -> (),
	SetAccent: (self: Panel, color: Color3) -> (),
}

export type Props = {
	Name: string,
	Title: string,
	Subtitle: string?,
	Size: UDim2,
	Parent: Instance,
	Accent: Color3?,
}

local Panel = {}

local HEADER = 60

function Panel.new(props: Props): Panel
	local accent = props.Accent or Style.Color("AccentViolet")

	local window: Frame = New("Frame", {
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = props.Size,
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Tag = { "Glass", "RoundL" },
		Parent = props.Parent,
	}, {
		New("UISizeConstraint", { MaxSize = Vector2.new(980, 640) }),
		New("UIShadow", {
			BlurRadius = UDim.new(0, 28),
			Color = Style.Color("BgDeep"),
			Transparency = 0.35,
			Offset = UDim2.fromOffset(0, 10),
		}),
	})
	Material.Glass(window, true)
	Material.RgbEdge(window, 1.5, 0.2)
	Material.Screws(window, 9)

	-- Plaque d'en-tête en métal brossé (coins supérieurs arrondis uniquement)
	local header: Frame = New("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, HEADER - 10),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 22,
		Tag = "MetalDark",
		Parent = window,
	}, {
		New("UICorner", {
			TopLeftRadius = UDim.new(0, Theme.Radius.M),
			TopRightRadius = UDim.new(0, Theme.Radius.M),
			BottomLeftRadius = UDim.new(0, 4),
			BottomRightRadius = UDim.new(0, 4),
		}),
	})
	Material.Brushed(header)

	-- LED d'état + titre
	local led: Frame = New("Frame", {
		Name = "Led",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 23,
		Tag = "RoundPill",
		Parent = header,
	}, {
		New("UIStroke", { Color = accent, Thickness = 3, Transparency = 0.6 }),
	})
	local title: TextLabel = New("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(36, 6),
		Size = UDim2.new(1, -110, 0, 24),
		BackgroundTransparency = 1,
		Text = props.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Tag = "TextTitle",
		Parent = header,
	})
	local subtitle: TextLabel = New("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(36, 28),
		Size = UDim2.new(1, -110, 0, 16),
		BackgroundTransparency = 1,
		Text = props.Subtitle or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Tag = "TextMuted",
		Parent = header,
	})
	-- Liseré néon sous l'en-tête
	local neon: Frame = New("Frame", {
		Name = "Neon",
		Position = UDim2.new(0, 10, 0, HEADER),
		Size = UDim2.new(1, -20, 0, 2),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = window,
	}, {
		New("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.9),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 0.9),
			}),
		}),
	})

	local panel = {
		Window = window,
		Body = nil :: any,
		Title = title,
		Subtitle = subtitle,
		OnClose = nil :: (() -> ())?,
	}

	local closeKey = Keycap.new({
		Icon = "Close",
		IconOnly = true,
		Variant = "Ghost",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		OnClick = function()
			(panel :: any):Close()
		end,
	})
	closeKey.Button.ZIndex = 24
	closeKey.Button.Parent = header

	-- Pistes de circuit décoratives (coin bas-gauche)
	Material.Trace(window, UDim2.new(0, 14, 1, -40), UDim2.new(0, 90, 0, 1), false, accent)
	Material.Trace(window, UDim2.new(0, 14, 1, -120), UDim2.new(0, 1, 0, 80), true, accent)

	local body: Frame = New("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(18, HEADER + 14),
		Size = UDim2.new(1, -36, 1, -(HEADER + 30)),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = window,
	})
	panel.Body = body

	-- Voile d'ouverture (donne un fondu sans CanvasGroup)
	local veil: Frame = New("Frame", {
		Name = "Veil",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 60,
		Tag = { "Backdrop", "RoundL" },
		Parent = window,
	})

	local scale = Motion.ScaleOf(window)
	local open = false

	function panel.IsOpen(_self: Panel): boolean
		return open
	end

	function panel.Open(_self: Panel)
		if open then
			return
		end
		open = true
		window.Visible = true
		scale.Scale = 0.9
		window.Position = UDim2.new(0.5, 0, 0.5, 24)
		veil.BackgroundTransparency = 0
		Motion.Tween(scale, { Scale = 1 }, Theme.Motion.Panel, Enum.EasingStyle.Back)
		Motion.Tween(window, { Position = UDim2.fromScale(0.5, 0.5) }, Theme.Motion.Panel)
		Motion.Tween(veil, { BackgroundTransparency = 1 }, 0.22)
	end

	function panel.Close(self: Panel)
		if not open then
			return
		end
		open = false
		Motion.Tween(scale, { Scale = 0.94 }, 0.16, Enum.EasingStyle.Quad)
		local fade = Motion.Tween(veil, { BackgroundTransparency = 0 }, 0.16, Enum.EasingStyle.Quad)
		fade.Completed:Once(function()
			if not open then
				window.Visible = false
			end
		end)
		if self.OnClose then
			self.OnClose()
		end
	end

	function panel.SetTitle(_self: Panel, text: string, sub: string?)
		title.Text = text
		subtitle.Text = sub or ""
	end

	function panel.SetAccent(_self: Panel, color: Color3)
		led.BackgroundColor3 = color
		neon.BackgroundColor3 = color
	end

	return (panel :: any) :: Panel
end

return Panel
