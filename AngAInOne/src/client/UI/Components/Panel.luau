--!strict
--[[
	Panel : fenêtre « app AngAInOne », dans le style du vrai logiciel (Fluent sombre).
	- surface plate gris anthracite, coins 10 px, liseré fin, ombre douce (plus de verre ni de RGB) ;
	- barre de titre : logo, fil d'Ariane « AngAInOne › Page », boutons de fenêtre, croix rouge au survol ;
	- pages (facultatives) : colonne de navigation à gauche (icône + libellé, barre d'accent sur la page
	  active) ; sur téléphone (échelle < 0,75) elles deviennent une rangée d'onglets en haut ;
	- en-tête de page : titre et sous-titre gris, puis le contenu (`Body`).
	Ouverture : zoom + fondu (0,22 s) ; fermeture rapide (0,16 s).
	Lisibilité : aucun texte sous 18 px de conception, croix de 64 × 44 px.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)
local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Icon = require(script.Parent.Icon)
local Keycap = require(script.Parent.Keycap)

local New = Create.New

export type Page = { Id: string, Text: string, Icon: string? }

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
	SetPage: (self: Panel, id: string) -> (),
}

export type Props = {
	Name: string,
	Title: string,
	Subtitle: string?,
	Size: UDim2,
	Parent: Instance,
	Accent: Color3?,
	Pages: { Page }?,
	OnPage: ((id: string) -> ())?,
}

local Panel = {}

local TITLEBAR = 44
local HEADER = 84 -- en-tête de page (titre + sous-titre)
local HEADER_COMPACT = 48 -- téléphone : titre seul
local TABS = 48 -- rangée d'onglets (téléphone)
local SIDEBAR = 220
local ROW = 44
local PAD = 24
local COMPACT_SCALE = 0.75
local CLOSE_RED = Color3.fromRGB(196, 43, 28)
local F = Style.Fonts

-- Échelle de l'UI (UIScale du Root) : sous COMPACT_SCALE, on est sur téléphone.
local function rootScale(object: GuiObject): number
	local node: Instance? = object.Parent
	while node do
		local scale = node:FindFirstChildOfClass("UIScale")
		if scale then
			return scale.Scale
		end
		node = node.Parent
	end
	return 1
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.Parent = parent
	if props.TextXAlignment == nil then
		props.TextXAlignment = Enum.TextXAlignment.Left
	end
	return New("TextLabel", props)
end

-- Voile sombre qui s'assombrit au survol / à l'appui (même recette que les boutons).
local function shade(parent: GuiObject): Frame
	return New("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex,
		Tag = "RoundS",
		Parent = parent,
	})
end

function Panel.new(props: Props): Panel
	local accent = props.Accent or Style.Color("AppAccent")
	local pages: { Page } = props.Pages or {}
	local hasPages = #pages > 0

	local window: Frame = New("Frame", {
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = props.Size,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Visible = false,
		-- Active : la fenêtre absorbe les clics (sinon ils traversent jusqu'au fond qui ferme).
		Active = true,
		ClipsDescendants = true,
		ZIndex = 20,
		Tag = { "Glass", "RoundL" },
		Parent = props.Parent,
	}, {
		New("UISizeConstraint", { MaxSize = Vector2.new(1040, 660), MinSize = Vector2.new(320, 240) }),
		New("UIStroke", { Color = Style.Color("Outline"), Thickness = 1, Transparency = 0 }),
		New("UIShadow", {
			BlurRadius = UDim.new(0, 32),
			Color = Color3.new(0, 0, 0),
			Transparency = 0.4,
			Offset = UDim2.fromOffset(0, 12),
		}),
	})

	------------------------------------------------------------------------------------------
	-- Barre de titre
	------------------------------------------------------------------------------------------
	local titlebar: Frame = New("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, TITLEBAR),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = window,
	})
	local logo: Frame = New("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 23,
		Tag = "RoundS",
		Parent = titlebar,
	})
	label(logo, {
		Size = UDim2.fromScale(1, 1),
		Text = "A",
		FontFace = F.Heavy,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 24,
	})
	local crumb: TextLabel = label(titlebar, {
		Name = "Crumb",
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -46 - 170, 1, 0),
		RichText = true,
		Text = "",
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 23,
		Tag = "TextBody",
	})
	-- Boutons de fenêtre décoratifs (réduire, agrandir) puis la vraie croix
	for index, glyph in { "—", "☐" } do
		label(titlebar, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -64 - (3 - index) * 48, 0, 0),
			Size = UDim2.fromOffset(48, TITLEBAR),
			Text = glyph,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 23,
			Tag = "TextMuted",
		})
	end
	local closeButton: TextButton = New("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(64, TITLEBAR),
		BackgroundColor3 = CLOSE_RED,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "✕",
		FontFace = F.Bold,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 23,
		Parent = titlebar,
	}, {
		New("UICorner", { TopRightRadius = UDim.new(0, Theme.Radius.L) }),
	})
	closeButton.MouseEnter:Connect(function()
		Motion.Tween(closeButton, { BackgroundTransparency = 0 }, Theme.Motion.Fast)
	end)
	closeButton.MouseLeave:Connect(function()
		Motion.Tween(closeButton, { BackgroundTransparency = 1 }, Theme.Motion.Fast)
	end)
	-- Trait sous la barre de titre
	New("Frame", {
		Name = "Rule",
		Position = UDim2.fromOffset(0, TITLEBAR),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Style.Color("Outline"),
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = window,
	})

	------------------------------------------------------------------------------------------
	-- Colonne de navigation (pages) et onglets compacts
	------------------------------------------------------------------------------------------
	local side: Frame = New("Frame", {
		Name = "Side",
		Position = UDim2.fromOffset(0, TITLEBAR + 1),
		Size = UDim2.new(0, SIDEBAR, 1, -(TITLEBAR + 1)),
		BackgroundTransparency = 1,
		Visible = hasPages,
		ZIndex = 21,
		Parent = window,
	}, {
		New("Frame", {
			Name = "Divider",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = Style.Color("Outline"),
			BorderSizePixel = 0,
			ZIndex = 21,
		}),
		New("Frame", {
			Name = "Rows",
			Position = UDim2.fromOffset(12, 14),
			Size = UDim2.new(1, -25, 1, -28),
			BackgroundTransparency = 1,
			ZIndex = 21,
		}, { Create.List(Enum.FillDirection.Vertical, 4) :: Instance }),
	})
	local rows = side:FindFirstChild("Rows") :: Frame

	local content: Frame = New("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(if hasPages then SIDEBAR else 0, TITLEBAR + 1),
		Size = UDim2.new(1, if hasPages then -SIDEBAR else 0, 1, -(TITLEBAR + 1)),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = window,
	}, {
		New("UIPadding", {
			PaddingLeft = UDim.new(0, PAD),
			PaddingRight = UDim.new(0, PAD),
			PaddingTop = UDim.new(0, 14),
			PaddingBottom = UDim.new(0, PAD - 6),
		}),
	})

	local title: TextLabel = label(content, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 34),
		Text = props.Title,
		FontFace = F.Heavy,
		TextSize = 28,
		TextColor3 = Style.Color("TextPrimary"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 22,
	})
	local subtitle: TextLabel = label(content, {
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 24),
		Text = props.Subtitle or "",
		FontFace = F.Medium,
		TextSize = 18,
		TextColor3 = Style.Color("TextMuted"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 22,
	})
	local tabs: Frame = New("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, HEADER_COMPACT),
		Size = UDim2.new(1, 0, 0, TABS - 8),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 22,
		Parent = content,
	}, { Create.List(Enum.FillDirection.Horizontal, 8) :: Instance })

	local body: Frame = New("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, HEADER),
		Size = UDim2.new(1, 0, 1, -HEADER),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = content,
	})

	local panel = {
		Window = window,
		Body = body,
		Title = title,
		Subtitle = subtitle,
		OnClose = nil :: (() -> ())?,
	}

	local function setCrumb(text: string)
		local dim = Theme.Colors.TextDim
		crumb.Text = `<font color="#{dim}">AngAInOne   ›   </font>{text}`
	end
	setCrumb(props.Title)

	-- Pages : une ligne par page dans la colonne, un onglet par page sur téléphone
	local currentPage: string? = if hasPages then pages[1].Id else nil
	local rowItems: { [string]: { Row: TextButton, Bar: Frame, Label: TextLabel, Shade: Frame } } = {}
	local tabItems: { [string]: { Tab: TextButton, Label: TextLabel, Stroke: UIStroke } } = {}

	local function refreshPages()
		for id, item in rowItems do
			local on = id == currentPage
			item.Bar.Visible = on
			item.Shade.BackgroundTransparency = if on then 0.94 else 1
			item.Label.TextColor3 = Style.Color(if on then "TextPrimary" else "TextMuted")
		end
		for id, item in tabItems do
			local on = id == currentPage
			item.Tab.BackgroundTransparency = if on then 0 else 1
			item.Stroke.Transparency = if on then 0 else 0.6
			item.Label.TextColor3 = Style.Color(if on then "TextPrimary" else "TextMuted")
		end
	end

	local function choose(id: string)
		if currentPage == id then
			return
		end
		currentPage = id
		refreshPages()
		local sound = Keycap.ClickSound
		if sound then
			sound()
		end
		if props.OnPage then
			props.OnPage(id)
		end
	end

	for index, page in pages do
		-- Ligne de la colonne
		local row: TextButton = New("TextButton", {
			Name = page.Id,
			Size = UDim2.new(1, 0, 0, ROW),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			Selectable = true,
			ZIndex = 22,
			Parent = rows,
		})
		local rowShade = shade(row)
		rowShade.ZIndex = 22
		local bar: Frame = New("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(3, 20),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			ZIndex = 23,
			Tag = "RoundPill",
			Parent = row,
		})
		if page.Icon then
			local icon = Icon.new(page.Icon, 20, "TextPrimary")
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 16, 0.5, 0)
			icon.ZIndex = 23
			icon.Parent = row
		end
		local rowLabel = label(row, {
			Position = UDim2.fromOffset(if page.Icon then 48 else 16, 0),
			Size = UDim2.new(1, if page.Icon then -56 else -24, 1, 0),
			Text = page.Text,
			FontFace = F.Medium,
			TextSize = 18,
			TextColor3 = Style.Color("TextMuted"),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 23,
		})
		row.MouseEnter:Connect(function()
			if currentPage ~= page.Id then
				Motion.Tween(rowShade, { BackgroundTransparency = 0.96 }, Theme.Motion.Fast)
			end
		end)
		row.MouseLeave:Connect(function()
			if currentPage ~= page.Id then
				Motion.Tween(rowShade, { BackgroundTransparency = 1 }, Theme.Motion.Fast)
			end
		end)
		row.Activated:Connect(function()
			choose(page.Id)
		end)
		rowItems[page.Id] = { Row = row, Bar = bar, Label = rowLabel, Shade = rowShade }

		-- Onglet compact
		local tab: TextButton = New("TextButton", {
			Name = page.Id,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			Selectable = true,
			ZIndex = 23,
			Tag = { "GlassRaised", "RoundS" },
			Parent = tabs,
		}, {
			New("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		})
		local stroke: UIStroke = New("UIStroke", { Color = accent, Thickness = 1, Transparency = 0.6, Parent = tab })
		local tabLabel = label(tab, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			Text = page.Text,
			FontFace = F.Bold,
			TextSize = 18,
			TextColor3 = Style.Color("TextMuted"),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 24,
		})
		tab.Activated:Connect(function()
			choose(page.Id)
		end)
		tabItems[page.Id] = { Tab = tab, Label = tabLabel, Stroke = stroke }
	end
	refreshPages()

	-- Disposition selon l'échelle : colonne de pages sur grand écran, onglets en haut sur téléphone.
	local function relayout()
		local compact = rootScale(window) < COMPACT_SCALE
		local sideVisible = hasPages and not compact
		side.Visible = sideVisible
		content.Position = UDim2.fromOffset(if sideVisible then SIDEBAR else 0, TITLEBAR + 1)
		content.Size = UDim2.new(1, if sideVisible then -SIDEBAR else 0, 1, -(TITLEBAR + 1))
		subtitle.Visible = not compact and props.Subtitle ~= nil and props.Subtitle ~= ""
		title.TextSize = if compact then 24 else 28
		tabs.Visible = hasPages and compact
		local top = if compact then HEADER_COMPACT else HEADER
		if hasPages and compact then
			top += TABS
		end
		body.Position = UDim2.fromOffset(0, top)
		body.Size = UDim2.new(1, 0, 1, -top)
	end
	relayout()

	local closeKeyHandler = function()
		(panel :: any):Close()
	end
	closeButton.Activated:Connect(function()
		local sound = Keycap.ClickSound
		if sound then
			sound()
		end
		closeKeyHandler()
	end)

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
		relayout()
		window.Visible = true
		scale.Scale = 0.96
		window.Position = UDim2.new(0.5, 0, 0.5, 12)
		veil.BackgroundTransparency = 0
		Motion.Tween(scale, { Scale = 1 }, Theme.Motion.Base, Enum.EasingStyle.Quad)
		Motion.Tween(window, { Position = UDim2.fromScale(0.5, 0.5) }, Theme.Motion.Base)
		Motion.Tween(veil, { BackgroundTransparency = 1 }, Theme.Motion.Base)
	end

	function panel.Close(self: Panel)
		if not open then
			return
		end
		open = false
		Motion.Tween(scale, { Scale = 0.97 }, 0.16, Enum.EasingStyle.Quad)
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
		setCrumb(text)
	end

	function panel.SetAccent(_self: Panel, color: Color3)
		logo.BackgroundColor3 = color
		for _, item in rowItems do
			item.Bar.BackgroundColor3 = color
		end
		for _, item in tabItems do
			item.Stroke.Color = color
		end
	end

	function panel.SetPage(_self: Panel, id: string)
		currentPage = id
		refreshPages()
	end

	return (panel :: any) :: Panel
end

return Panel
