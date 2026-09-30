--!strict
--[[
	Fluent : petit kit d'interface au style de l'app AngAInOne (Windows 11 Fluent sombre :
	fond 202020, cartes 2B2B2B, textes blanc / gris, boutons violets), en PIXELS de canevas.
	Utilisé par les fenêtres de l'app posées dans la tour (AppPanels, SurfaceGui 1200 px de large)
	et par la carte d'intro des terminaux (MinigamePanel).

	Window(root, opts) dessine une fenêtre complète : barre de titre, barre latérale (page du monde
	surlignée, liseré violet), titre de page + ⓘ, sous-titre gris, bouton « Actualiser », et renvoie
	la zone de contenu + un voile (Overlay) pour les incidents (« Ne répond pas », coupure…).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Branding = require(Shared.Config.Branding)
local AppPages = require(Shared.Util.AppPanelLogic)

local Style = require(script.Parent.Parent.Parent.UI.Style)
local Create = require(script.Parent.Parent.Parent.UI.Create)

local New = Create.New
local APP = Branding.PartnerApp

local Fluent = {}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

Fluent.C = table.freeze({
	Bg = hex(APP.Surface), -- 202020
	Card = hex(APP.Card), -- 2B2B2B
	CardHover = hex(APP.CardHover), -- 323232
	Sunken = hex("1B1B1B"),
	Stroke = hex("3A3A3A"),
	Field = hex("383838"),
	Text = hex(APP.Text),
	Dim = hex(APP.TextDim),
	Faint = hex("8F8F8F"),
	Accent = hex(APP.Accent), -- violet des boutons
	AccentSoft = hex("8B7CFF"),
	Good = hex(APP.Good),
	Warn = hex(APP.Warn),
	Bad = hex(APP.Bad),
	Info = hex("60CDFF"),
})
local C = Fluent.C

-- Couleur d'un niveau "Good" | "Warn" | "Bad".
function Fluent.Level(level: string): Color3
	return if level == "Bad" then C.Bad elseif level == "Warn" then C.Warn else C.Good
end

local FONTS: { [string]: Font } = {
	Regular = Style.Fonts.Regular,
	Medium = Style.Fonts.Medium,
	Bold = Style.Fonts.Bold,
	Heavy = Style.Fonts.Heavy,
}

export type TextOptions = {
	Color: Color3?,
	Weight: string?, -- "Regular" | "Medium" | "Bold" | "Heavy"
	Align: string?, -- "Left" | "Center" | "Right"
	Wrap: boolean?,
	Name: string?,
}

-- Texte à taille fixe (canevas en pixels) ; tronqué plutôt que débordant.
function Fluent.Text(
	parent: Instance,
	text: string,
	x: number,
	y: number,
	w: number,
	h: number,
	size: number,
	options: TextOptions?
): TextLabel
	local o: TextOptions = options or {}
	local align = o.Align or "Left"
	return New("TextLabel", {
		Name = o.Name or "Text",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		FontFace = FONTS[o.Weight or "Regular"] or Style.Fonts.Regular,
		TextColor3 = o.Color or C.Text,
		TextXAlignment = if align == "Center"
			then Enum.TextXAlignment.Center
			elseif align == "Right" then Enum.TextXAlignment.Right
			else Enum.TextXAlignment.Left,
		TextYAlignment = if o.Wrap then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		TextWrapped = o.Wrap == true,
		TextTruncate = if o.Wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
end

-- Cadre simple (sans bordure).
function Fluent.Box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, radius: number?): Frame
	local frame: Frame = New("Frame", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if radius and radius > 0 then
		Create.Corner(radius).Parent = frame
	end
	return frame
end

-- Carte Fluent : fond 2B2B2B, coins arrondis, fin liseré.
function Fluent.Card(parent: Instance, x: number, y: number, w: number, h: number, color: Color3?): Frame
	local card = Fluent.Box(parent, x, y, w, h, color or C.Card, 8)
	card.Name = "Card"
	New("UIStroke", { Color = hex("1A1A1A"), Thickness = 1, Parent = card })
	return card
end

-- Bouton (décoratif ou cliquable) : "Accent" (violet plein), "Outline" (gris bordé), "Subtle".
function Fluent.Button(
	parent: Instance,
	text: string,
	x: number,
	y: number,
	w: number,
	h: number,
	variant: string?,
	size: number?
): (Frame, TextLabel)
	local kind = variant or "Outline"
	local frame = Fluent.Box(
		parent,
		x,
		y,
		w,
		h,
		if kind == "Accent" then C.Accent elseif kind == "Subtle" then C.Field else C.Card,
		6
	)
	frame.Name = "Button"
	if kind == "Outline" then
		New("UIStroke", { Color = C.Stroke, Thickness = 1, Parent = frame })
	end
	local label = Fluent.Text(frame, text, 0, 0, w, h, size or math.floor(h * 0.45), {
		Align = "Center",
		Weight = "Medium",
		Color = C.Text,
	})
	return frame, label
end

-- Barre de progression : piste sombre + remplissage (Size en échelle, 0..1).
function Fluent.Bar(parent: Instance, x: number, y: number, w: number, h: number, color: Color3): Frame
	local track = Fluent.Box(parent, x, y, w, h, C.Field, math.floor(h / 2))
	track.Name = "Track"
	local fill = Fluent.Box(track, 0, 0, 0, h, color, math.floor(h / 2))
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	return fill
end

function Fluent.SetBar(fill: Frame, fraction: number, color: Color3?)
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if color then
		fill.BackgroundColor3 = color
	end
end

-- Étiquette arrondie (« SSD · NVMe », « En cours »), largeur automatique.
function Fluent.Tag(
	parent: Instance,
	text: string,
	x: number,
	y: number,
	h: number,
	size: number,
	color: Color3?,
	background: Color3?
): (Frame, TextLabel)
	local frame: Frame = New("Frame", {
		Name = "Tag",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = background or C.Field,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		Create.Corner(math.floor(h / 3)),
		New("UIPadding", {
			PaddingLeft = UDim.new(0, math.floor(h * 0.4)),
			PaddingRight = UDim.new(0, math.floor(h * 0.4)),
		}),
	})
	local label: TextLabel = New("TextLabel", {
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		FontFace = Style.Fonts.Medium,
		TextColor3 = color or C.Text,
		Parent = frame,
	})
	return frame, label
end

-- Pastille ronde avec un signe (« ! », « i », « ✓ ») : icônes des listes de l'app.
function Fluent.Glyph(
	parent: Instance,
	x: number,
	y: number,
	d: number,
	glyph: string,
	color: Color3
): (Frame, TextLabel)
	local ring = Fluent.Box(parent, x, y, d, d, C.Bg, math.floor(d / 2))
	ring.Name = "Glyph"
	ring.BackgroundTransparency = 1
	local stroke = New("UIStroke", { Color = color, Thickness = math.max(2, math.floor(d / 14)), Parent = ring })
	stroke.Name = "Ring"
	local label = Fluent.Text(ring, glyph, 0, 0, d, d, math.floor(d * 0.62), {
		Align = "Center",
		Weight = "Bold",
		Color = color,
	})
	return ring, label
end

function Fluent.SetGlyph(ring: Frame, label: TextLabel, glyph: string, color: Color3)
	label.Text = glyph
	label.TextColor3 = color
	local stroke = ring:FindFirstChild("Ring")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = color
	end
end

export type Toggle = { Root: Frame, Knob: Frame, On: boolean? }

-- Interrupteur Windows 11 : violet plein + pastille à droite (activé), bordé gris sinon.
function Fluent.Toggle(parent: Instance, x: number, y: number, h: number): Toggle
	local w = math.floor(h * 2.1)
	local root = Fluent.Box(parent, x, y, w, h, C.Accent, math.floor(h / 2))
	root.Name = "Toggle"
	New("UIStroke", { Name = "Edge", Color = C.Faint, Thickness = 2, Transparency = 1, Parent = root })
	local knob = Fluent.Box(root, 0, 0, math.floor(h * 0.56), math.floor(h * 0.56), C.Text, math.floor(h * 0.28))
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	return { Root = root, Knob = knob, On = nil }
end

function Fluent.SetToggle(toggle: Toggle, on: boolean)
	if toggle.On == on then
		return
	end
	toggle.On = on
	local root = toggle.Root
	root.BackgroundColor3 = C.Accent
	root.BackgroundTransparency = if on then 0 else 1
	local edge = root:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Transparency = if on then 1 else 0
	end
	toggle.Knob.BackgroundColor3 = if on then C.Text else C.Faint
	toggle.Knob.Position = UDim2.fromScale(if on then 0.73 else 0.27, 0.5)
end

------------------------------------------------------------------------------------
-- Fenêtre complète de l'app
------------------------------------------------------------------------------------

export type WindowOptions = {
	Width: number,
	Height: number,
	World: number, -- page du monde (surlignée dans la barre latérale)
	User: string?, -- nom affiché en haut de la barre latérale
	Title: string?, -- par défaut : AppSection du monde
	Subtitle: string?, -- par défaut : AppSubtitle du monde
	Refresh: boolean?, -- bouton « Actualiser » en haut à droite (défaut : oui)
}

export type Window = {
	Root: Frame,
	Content: Frame, -- zone sous l'en-tête, à droite de la barre latérale
	Width: number, -- largeur de Content
	Height: number, -- hauteur de Content
	Title: TextLabel,
	Overlay: Frame, -- voile d'incident (caché par défaut)
	OverlayTitle: TextLabel,
	OverlayText: TextLabel,
	OverlayGlyph: Frame,
	OverlayGlyphText: TextLabel,
}

local SIDEBAR_W = 250
local TITLEBAR_H = 34

-- Barre latérale de l'app : profil, recherche, pages (celle du monde surlignée).
function Fluent.Sidebar(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	world: number,
	user: string?,
	textSize: number?
)
	local side = Fluent.Box(parent, x, y, w, h, C.Bg)
	side.Name = "Sidebar"
	local top = 8
	if user then
		local avatar = Fluent.Box(side, 16, top + 6, 34, 34, C.Bg, 17)
		New("UIStroke", { Color = C.Dim, Thickness = 2, Parent = avatar })
		Fluent.Text(avatar, "A", 0, 0, 34, 34, 18, { Align = "Center", Weight = "Bold", Color = C.Dim })
		Fluent.Text(side, user, 60, top + 2, w - 70, 24, 19, { Weight = "Medium" })
		Fluent.Text(side, "Pro", 60, top + 24, w - 70, 18, 14, { Color = C.Dim })
		top += 54
	end
	local fieldH = if textSize then math.floor(textSize * 2.2) else 34
	local search = Fluent.Box(side, 10, top, w - 20, fieldH, C.Card, 6)
	New("UIStroke", { Color = C.Stroke, Thickness = 1, Parent = search })
	Fluent.Text(search, "Rechercher une page…", 10, 0, w - 40, fieldH, textSize or 15, { Color = C.Dim })
	top += fieldH + 12
	local selected = AppPages.SidebarLabel(world)
	local rows = AppPages.Sidebar
	local rowH = math.min(math.floor((h - top - 6) / #rows), 44)
	for i, item in rows do
		local ry = top + (i - 1) * rowH
		local isOn = item.Label == selected
		if isOn then
			local row = Fluent.Box(side, 6, ry + 2, w - 12, rowH - 4, C.CardHover, 6)
			row.Name = "Selected"
			Fluent.Box(row, 0, math.floor(rowH * 0.25), 4, math.floor(rowH * 0.5) - 4, C.Accent, 2)
		end
		local indent = if item.Indent then math.floor(w * 0.17) else math.floor(w * 0.08)
		local size = textSize or math.min(math.floor(rowH * 0.5), 19)
		Fluent.Text(side, item.Label, indent, ry, w - indent - 8, rowH, size, {
			Color = if isOn then C.Text else C.Dim,
			Weight = if isOn then "Medium" else "Regular",
		})
	end
	return side
end

function Fluent.Window(root: GuiObject, options: WindowOptions): Window
	local def = AppPages.Intro(options.World)
	local W, H = options.Width, options.Height
	local frame = Fluent.Box(root, 0, 0, W, H, C.Bg)
	frame.Name = "Window"
	frame.ClipsDescendants = true
	-- Barre de titre
	Fluent.Text(frame, "AngAInOne", 18, 0, 200, TITLEBAR_H, 15, { Color = C.Dim })
	Fluent.Text(frame, "—", W - 150, 0, 30, TITLEBAR_H, 15, { Color = C.Dim, Align = "Center" })
	local square = Fluent.Box(frame, W - 96, math.floor(TITLEBAR_H / 2) - 6, 12, 12, C.Bg)
	New("UIStroke", { Color = C.Dim, Thickness = 1.5, Parent = square })
	Fluent.Text(frame, "✕", W - 54, 0, 30, TITLEBAR_H, 15, { Color = C.Dim, Align = "Center" })
	-- Barre latérale
	Fluent.Sidebar(frame, 0, TITLEBAR_H, SIDEBAR_W, H - TITLEBAR_H, options.World, options.User)
	Fluent.Box(frame, SIDEBAR_W, TITLEBAR_H, 1, H - TITLEBAR_H, hex("2A2A2A"))
	-- En-tête de page
	local left = SIDEBAR_W + 30
	-- Titre + pastille ⓘ juste après (liste horizontale : le titre prend la largeur de son texte)
	local header: Frame = New("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(left, TITLEBAR_H + 10),
		Size = UDim2.fromOffset(W - left - 200, 50),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 14, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	local title = Fluent.Text(header, options.Title or def.Page, 0, 0, 0, 50, 40, {
		Weight = "Bold",
		Name = "PageTitle",
	})
	title.AutomaticSize = Enum.AutomaticSize.X
	title.LayoutOrder = 1
	New("UISizeConstraint", { MaxSize = Vector2.new(W - left - 250, 50), Parent = title })
	local info = Fluent.Glyph(header, 0, 0, 22, "i", C.Dim)
	info.LayoutOrder = 2
	Fluent.Text(frame, options.Subtitle or def.Subtitle, left, TITLEBAR_H + 58, W - left - 30, 26, 19, {
		Color = C.Dim,
		Name = "Subtitle",
	})
	if options.Refresh ~= false then
		Fluent.Button(frame, "Actualiser", W - 170, TITLEBAR_H + 16, 146, 38, "Outline", 17)
	end
	local top = TITLEBAR_H + 100
	local content: Frame = New("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(left, top),
		Size = UDim2.fromOffset(W - left - 24, H - top - 16),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	-- Voile d'incident : fenêtre « Ne répond pas » / coupure de courant
	local overlay: Frame = New("Frame", {
		Name = "Overlay",
		Position = UDim2.fromOffset(0, TITLEBAR_H),
		Size = UDim2.fromOffset(W, H - TITLEBAR_H),
		BackgroundColor3 = hex("0B0B0B"),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Parent = frame,
	})
	local box =
		Fluent.Card(overlay, math.floor(W * 0.18), math.floor((H - TITLEBAR_H) * 0.28), math.floor(W * 0.64), 190)
	box.ZIndex = 21
	local glyph, glyphText = Fluent.Glyph(box, 26, 30, 44, "!", C.Bad)
	local overlayTitle =
		Fluent.Text(box, "", 90, 22, math.floor(W * 0.64) - 110, 60, 30, { Weight = "Bold", Wrap = true })
	local overlayText = Fluent.Text(box, "", 90, 92, math.floor(W * 0.64) - 110, 80, 20, { Color = C.Dim, Wrap = true })
	for _, d in overlay:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 22
		end
	end
	return {
		Root = frame,
		Content = content,
		Width = W - left - 24,
		Height = H - top - 16,
		Title = title,
		Overlay = overlay,
		OverlayTitle = overlayTitle,
		OverlayText = overlayText,
		OverlayGlyph = glyph,
		OverlayGlyphText = glyphText,
	}
end

-- Affiche (ou cache si title = nil) le voile d'incident de la fenêtre.
function Fluent.SetOverlay(window: Window, title: string?, text: string?, glyph: string?, color: Color3?)
	if not title then
		window.Overlay.Visible = false
		return
	end
	window.Overlay.Visible = true
	window.OverlayTitle.Text = title
	window.OverlayText.Text = text or ""
	Fluent.SetGlyph(window.OverlayGlyph, window.OverlayGlyphText, glyph or "!", color or C.Bad)
end

return table.freeze(Fluent)
