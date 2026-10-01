--!strict
--[[
	AppBoard : panneau 3D au style de l'app AngAInOne (Fluent sombre), posé en SurfaceGui sur une pièce.
	Le même langage visuel partout dans les épreuves : fond 202020, cartes 2B2B2B, texte blanc,
	gris C5C5C5, accent violet 9B2FD4, fil d'Ariane « AngAInOne › Page ».

	Contenu (dans l'ordre, tout est facultatif sauf Page et Title) :
	- Fiche : Constat / Pourquoi / Quoi faire (le format du Diagnostic de l'app) ;
	- Steps : liste à cocher (« ○ » puis « ✓ ») ; le client coche avec AppBoard (client) via les noms
	  Step{i} / Step{i}.Check ;
	- Rows : paires libellé / valeur (une valeur peut être mise à jour : Row{i}.Value) ;
	- Big : gros chiffre + légende (Big.Value, Big.Caption) ;
	- Bar : barre de progression (Bar.Fill, Bar.Label), 0..1.
	Échelle : PIXELS px par stud ; les tailles de texte sont en pixels de la SurfaceGui.
]]

local AppBoard = {}

AppBoard.PIXELS = 40

AppBoard.C = table.freeze({
	Surface = Color3.fromHex("202020"),
	Card = Color3.fromHex("2B2B2B"),
	CardHi = Color3.fromHex("323232"),
	Stroke = Color3.fromHex("3A3A3A"),
	Text = Color3.fromHex("FFFFFF"),
	Dim = Color3.fromHex("C5C5C5"),
	Faint = Color3.fromHex("8F8F8F"),
	Accent = Color3.fromHex("9B2FD4"),
	Violet = Color3.fromHex("8B7CFF"),
	Good = Color3.fromHex("6CCB5F"),
	Warn = Color3.fromHex("FCE100"),
	Bad = Color3.fromHex("FF99A4"),
})

local C = AppBoard.C
local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local function weight(w: Enum.FontWeight): Font
	return Font.new(FAMILY, w)
end
local REGULAR = weight(Enum.FontWeight.Regular)
local MEDIUM = weight(Enum.FontWeight.Medium)
local BOLD = weight(Enum.FontWeight.Bold)
local HEAVY = weight(Enum.FontWeight.ExtraBold)

export type Spec = {
	Page: string,
	Title: string,
	Subtitle: string?,
	Accent: Color3?,
	Fiche: { Constat: string, Pourquoi: string, QuoiFaire: string }?,
	Steps: { string }?,
	Rows: { { string } }?, -- { libellé, valeur, couleur? (hex) }
	Big: { Value: string, Caption: string, Color: Color3? }?,
	Bar: { Label: string, Value: number, Color: Color3? }?,
	Face: Enum.NormalId?,
	Scale: number?, -- taille du texte (1 = normal, pour un panneau lu de loin : 1,3)
	Pixels: number?, -- pixels par stud (défaut PIXELS) : plus = texte plus petit sur la pièce
	TitleWrap: boolean?, -- titre sur plusieurs lignes (noms de fichiers longs)
}

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local object = Instance.new(class)
	for key, value in props do
		(object :: any)[key] = value
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local function corner(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.TextWrapped = if props.TextWrapped == nil then true else props.TextWrapped
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Top
	props.TextColor3 = props.TextColor3 or C.Text
	return new("TextLabel", props, parent)
end

-- Construit le panneau sur `part` (face avant par défaut). Renvoie la SurfaceGui.
function AppBoard.Build(part: BasePart, spec: Spec): SurfaceGui
	local accent = spec.Accent or C.Accent
	local k = spec.Scale or 1
	local gui: SurfaceGui = new("SurfaceGui", {
		Name = "AppBoard",
		Face = spec.Face or Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = spec.Pixels or AppBoard.PIXELS,
		LightInfluence = 0,
		Brightness = 1.4,
		MaxDistance = 220,
		ZOffset = 1,
	}, part)
	local root = new("Frame", {
		Name = "Window",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Surface,
		BorderSizePixel = 0,
	}, gui)
	corner(root, 18)
	new("UIStroke", { Color = C.Stroke, Thickness = 3 }, root)
	-- Barre de titre : logo + fil d'Ariane
	local bar = new("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, math.floor(56 * k)),
		BackgroundTransparency = 1,
	}, root)
	local logo = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		Size = UDim2.fromOffset(math.floor(30 * k), math.floor(30 * k)),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
	}, bar)
	corner(logo, 8)
	text(logo, {
		Size = UDim2.fromScale(1, 1),
		Text = "A",
		FontFace = HEAVY,
		TextSize = math.floor(22 * k),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	text(bar, {
		Name = "Crumb",
		Position = UDim2.fromOffset(math.floor(64 * k), 0),
		Size = UDim2.new(1, -math.floor(80 * k), 1, 0),
		RichText = true,
		Text = `<font color="#8F8F8F">AngAInOne   ›   </font>{spec.Page}`,
		FontFace = MEDIUM,
		TextSize = math.floor(26 * k),
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	new("Frame", {
		Position = UDim2.new(0, 0, 0, math.floor(56 * k)),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = C.Stroke,
		BorderSizePixel = 0,
	}, root)
	-- Corps : liste verticale
	local body = new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(28, math.floor(72 * k)),
		Size = UDim2.new(1, -56, 1, -math.floor(88 * k)),
		BackgroundTransparency = 1,
	}, root)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, math.floor(12 * k)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, body)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	text(body, {
		Name = "Title",
		AutomaticSize = if spec.TitleWrap then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, math.floor(54 * k)),
		Text = spec.Title,
		FontFace = HEAVY,
		TextSize = math.floor(46 * k),
		TextWrapped = spec.TitleWrap == true,
		TextTruncate = if spec.TitleWrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		LayoutOrder = nextOrder(),
	})
	if spec.Subtitle then
		text(body, {
			Name = "Subtitle",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			Text = spec.Subtitle,
			FontFace = REGULAR,
			TextSize = math.floor(26 * k),
			TextColor3 = C.Dim,
			LayoutOrder = nextOrder(),
		})
	end
	-- Fiche du Diagnostic
	if spec.Fiche then
		local entries: { { any } } = {
			{ "Constat", spec.Fiche.Constat, C.Warn },
			{ "Pourquoi", spec.Fiche.Pourquoi, C.Violet },
			{ "Quoi faire", spec.Fiche.QuoiFaire, C.Good },
		}
		for _, entry in entries do
			local card = new("Frame", {
				Name = entry[1],
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundColor3 = C.Card,
				BorderSizePixel = 0,
				LayoutOrder = nextOrder(),
			}, body)
			corner(card, 12)
			new("UIPadding", {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 14),
				PaddingLeft = UDim.new(0, 26),
				PaddingRight = UDim.new(0, 18),
			}, card)
			new("Frame", {
				Position = UDim2.new(0, -18, 0, 2),
				Size = UDim2.new(0, 6, 1, -4),
				BackgroundColor3 = entry[3],
				BorderSizePixel = 0,
			}, card)
			new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, card)
			text(card, {
				Size = UDim2.new(1, 0, 0, math.floor(30 * k)),
				Text = entry[1],
				FontFace = BOLD,
				TextSize = math.floor(26 * k),
				TextColor3 = entry[3],
				LayoutOrder = 1,
			})
			text(card, {
				Name = "Text",
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				Text = entry[2],
				FontFace = MEDIUM,
				TextSize = math.floor(28 * k),
				LayoutOrder = 2,
			})
		end
	end
	-- Liste à cocher
	if spec.Steps then
		for index, label in spec.Steps do
			local row = new("Frame", {
				Name = `Step{index}`,
				Size = UDim2.new(1, 0, 0, math.floor(48 * k)),
				BackgroundColor3 = C.Card,
				BorderSizePixel = 0,
				LayoutOrder = nextOrder(),
			}, body)
			corner(row, 10)
			text(row, {
				Name = "Check",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(math.floor(36 * k), math.floor(36 * k)),
				Text = "○",
				FontFace = HEAVY,
				TextSize = math.floor(32 * k),
				TextColor3 = C.Faint,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
			})
			text(row, {
				Name = "Label",
				Position = UDim2.fromOffset(math.floor(60 * k), 0),
				Size = UDim2.new(1, -math.floor(76 * k), 1, 0),
				Text = label,
				FontFace = MEDIUM,
				TextSize = math.floor(28 * k),
				TextYAlignment = Enum.TextYAlignment.Center,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
		end
	end
	-- Paires libellé / valeur
	if spec.Rows then
		for index, entry in spec.Rows do
			local row = new("Frame", {
				Name = `Row{index}`,
				Size = UDim2.new(1, 0, 0, math.floor(44 * k)),
				BackgroundColor3 = if index % 2 == 1 then C.Card else C.Surface,
				BorderSizePixel = 0,
				LayoutOrder = nextOrder(),
			}, body)
			corner(row, 8)
			text(row, {
				Name = "Label",
				Position = UDim2.fromOffset(16, 0),
				Size = UDim2.new(0.6, -16, 1, 0),
				Text = entry[1],
				FontFace = MEDIUM,
				TextSize = math.floor(26 * k),
				TextColor3 = C.Dim,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			text(row, {
				Name = "Value",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 0),
				Size = UDim2.new(0.4, -16, 1, 0),
				Text = entry[2] or "",
				FontFace = BOLD,
				TextSize = math.floor(26 * k),
				TextColor3 = if entry[3] then Color3.fromHex(entry[3]) else C.Text,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextWrapped = false,
			})
		end
	end
	-- Gros chiffre
	if spec.Big then
		local big = new("Frame", {
			Name = "Big",
			Size = UDim2.new(1, 0, 0, math.floor(120 * k)),
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
		}, body)
		text(big, {
			Name = "Value",
			Size = UDim2.new(1, 0, 0, math.floor(84 * k)),
			Text = spec.Big.Value,
			FontFace = HEAVY,
			TextSize = math.floor(80 * k),
			TextColor3 = spec.Big.Color or C.Text,
			TextWrapped = false,
		})
		text(big, {
			Name = "Caption",
			Position = UDim2.fromOffset(0, math.floor(86 * k)),
			Size = UDim2.new(1, 0, 0, math.floor(32 * k)),
			Text = spec.Big.Caption,
			FontFace = MEDIUM,
			TextSize = math.floor(26 * k),
			TextColor3 = C.Dim,
			TextWrapped = false,
		})
	end
	-- Barre de progression
	if spec.Bar then
		local holder = new("Frame", {
			Name = "Bar",
			Size = UDim2.new(1, 0, 0, math.floor(72 * k)),
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
		}, body)
		text(holder, {
			Name = "Label",
			Size = UDim2.new(1, 0, 0, math.floor(30 * k)),
			Text = spec.Bar.Label,
			FontFace = MEDIUM,
			TextSize = math.floor(26 * k),
			TextColor3 = C.Dim,
			TextWrapped = false,
		})
		local track = new("Frame", {
			Name = "Track",
			Position = UDim2.fromOffset(0, math.floor(40 * k)),
			Size = UDim2.new(1, 0, 0, math.floor(22 * k)),
			BackgroundColor3 = C.Card,
			BorderSizePixel = 0,
		}, holder)
		corner(track, 11)
		local fill = new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(math.clamp(spec.Bar.Value, 0, 1), 1),
			BackgroundColor3 = spec.Bar.Color or C.Accent,
			BorderSizePixel = 0,
		}, track)
		corner(fill, 11)
	end
	return gui
end

-- Pièce-panneau (plaque fine, décor) + AppBoard. `size` en studs (X largeur, Y hauteur).
function AppBoard.Panel(parent: Instance, name: string, size: Vector2, cframe: CFrame, spec: Spec): Part
	local plate = Instance.new("Part")
	plate.Name = name
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	plate.Size = Vector3.new(size.X, size.Y, 0.3)
	plate.CFrame = cframe
	plate.Color = C.Surface
	plate.Material = Enum.Material.SmoothPlastic
	plate.Parent = parent
	AppBoard.Build(plate, spec)
	return plate
end

return AppBoard
