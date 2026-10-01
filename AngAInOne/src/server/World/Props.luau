--!strict
--[[
	Props : éléments de décor réutilisables pour construire la tour PC géante.
	- Primitives de détail : Box, Rod, Wedge, Ring (décor pur : ni collision, ni requêtes, ni ombre)
	- Décor PC : ventilateurs, grilles nid d'abeille, blocs d'ailettes, câbles gainés, tubes de
	  watercooling, condensateurs, sérigraphie, panneaux (nom de monde + section de l'app)
	- Composants géants (le « héros » au centre de chaque monde) : alimentation, kit de RAM,
	  SSD M.2, radiateur de watercooling, ventirad de processeur, carte graphique, cœur neuronal

	Tags lus par le client : TrapSpin (moyeu de ventilateur tourné par TrapController, attributs
	Axis + Speed), RgbStrip (bande recolorée en arc-en-ciel si un contrôleur d'effets le gère).

	Convention : les petits détails sont du décor pur ; seuls les volumes principaux sont solides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Build = require(script.Parent.Build)

local Props = {}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

-- Palette matière du PC (dérivée du thème, plus claire que l'UI pour être lisible en 3D).
local C = {
	Bg = hex(Theme.Colors.BgDeep),
	Pcb = Color3.fromRGB(26, 58, 64),
	PcbDark = Color3.fromRGB(18, 38, 46),
	MetalDark = Color3.fromRGB(52, 58, 74),
	MetalLight = Color3.fromRGB(96, 104, 124),
	Aluminum = Color3.fromRGB(158, 166, 184),
	Nickel = Color3.fromRGB(196, 202, 214),
	Black = Color3.fromRGB(26, 28, 34),
	Rubber = Color3.fromRGB(40, 42, 50),
	Silk = Color3.fromRGB(206, 214, 222),
	Copper = hex(Theme.Colors.Copper),
	Gold = hex(Theme.Colors.CurrencyBits),
	Brand = hex(Theme.Colors.BrandAnga),
	Cyan = hex(Theme.Colors.AccentCyan),
	Violet = hex(Theme.Colors.AccentViolet),
	White = hex(Theme.Colors.TextPrimary),
}
Props.C = C

local UP = Vector3.yAxis
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- axe X local (cylindres) -> vertical
local METAL = Enum.Material.Metal

------------------------------------------------------------------------------------
-- Primitives de détail
------------------------------------------------------------------------------------

-- Bloc de détail (décor pur, sans ombre).
function Props.Box(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return Build.Decor({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CastShadow = false,
		Parent = parent,
	})
end

-- Cylindre de détail : axe = X local de `cf`.
function Props.Rod(
	parent: Instance,
	name: string,
	cf: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Build.Decor({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = material or METAL,
		CastShadow = false,
		Parent = parent,
	})
end

-- Repère dont l'axe X local va de `a` vers `b` (pour les cylindres).
function Props.Along(a: Vector3, b: Vector3): CFrame
	-- Segment vertical : lookAt dégénéré avec l'axe Y comme "haut", on prend X.
	local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else UP
	return CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
end

-- Repère centré en `position` dont le LookVector (-Z local) vaut `look` (horizontal ou non).
function Props.Facing(position: Vector3, look: Vector3): CFrame
	local unit = look.Unit
	local up = if math.abs(unit.Y) > 0.99 then Vector3.zAxis else UP
	local right = unit:Cross(up).Unit
	return CFrame.fromMatrix(position, right, right:Cross(unit), -unit)
end

-- Coin (WedgePart) de détail : face arrière (+Z) pleine, pente qui descend vers l'avant (-Z).
function Props.Wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cf
	wedge.Color = color
	wedge.Material = material or Enum.Material.SmoothPlastic
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.CanTouch = false
	wedge.CanQuery = false
	wedge.CastShadow = false
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

-- Anneau segmenté dans le plan YZ local de `cf` (axe = X local) : `count` blocs tangents.
function Props.Ring(
	parent: Instance,
	name: string,
	cf: CFrame,
	radius: number,
	width: number,
	depth: number,
	count: number,
	color: Color3,
	material: Enum.Material?
): { Part }
	local parts = {}
	local chord = 2 * (radius + width / 2) * math.tan(math.pi / count) + 0.02
	for i = 0, count - 1 do
		local part = Props.Box(
			parent,
			name,
			Vector3.new(depth, width, chord),
			cf * CFrame.Angles(i * math.pi * 2 / count, 0, 0) * CFrame.new(0, radius, 0),
			color,
			material
		)
		if material == Enum.Material.Neon then
			part.Transparency = 0.1
		end
		table.insert(parts, part)
	end
	return parts
end

-- Soude une pièce (libérée) à un moyeu ancré qui tourne côté client (tag TrapSpin).
local function weldTo(hub: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hub
	weld.Part1 = part
	weld.Parent = part
	part.Anchored = false
end
Props.WeldTo = weldTo

-- Moyeu invisible ancré qui tourne côté client (TrapController, tag TrapSpin).
function Props.SpinHub(parent: Instance, cf: CFrame, axis: string, speed: number): Part
	local hub = Build.Decor({
		Name = "SpinHub",
		Size = Vector3.one * 0.4,
		CFrame = cf,
		Transparency = 1,
		CastShadow = false,
		Tags = { "TrapSpin" },
		Parent = parent,
	})
	hub:SetAttribute("Axis", axis)
	hub:SetAttribute("Speed", speed)
	return hub
end

------------------------------------------------------------------------------------
-- Texte
------------------------------------------------------------------------------------

-- Texte "sérigraphié" (SurfaceGui statique sur une face d'une pièce).
function Props.Label(part: BasePart, text: string, color: Color3, face: Enum.NormalId?, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.LightInfluence = 0.3
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Font = font or Enum.Font.Michroma
	label.Parent = gui
	gui.Parent = part
end

-- Étiquette posée à plat (pièce invisible + texte) : sérigraphie au sol, autocollants.
function Props.Decal(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	text: string,
	color: Color3,
	face: Enum.NormalId?,
	font: Enum.Font?
): Part
	local part = Props.Box(parent, name, size, cf, color)
	part.Transparency = 1
	Props.Label(part, text, color, face or Enum.NormalId.Top, font)
	return part
end

-- Panneau à deux lignes (titre + sous-titre) sur la face avant d'une pièce : nom d'un monde,
-- section de l'app AngAInOne. Autoéclairé (LightInfluence 0) pour rester lisible dans l'ombre.
function Props.Sign(
	part: BasePart,
	title: string,
	subtitle: string?,
	color: Color3,
	subColor: Color3?,
	face: Enum.NormalId?
): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 8
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(0.94, if subtitle then 0.6 else 0.9)
	titleLabel.Position = UDim2.fromScale(0.03, 0.05)
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = color
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Parent = gui
	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.fromScale(0.9, 0.26)
		sub.Position = UDim2.fromScale(0.05, 0.68)
		sub.Text = subtitle
		sub.TextScaled = true
		sub.TextColor3 = subColor or C.White
		sub.Font = Enum.Font.GothamBold
		sub.Parent = gui
	end
	gui.Parent = part
	return gui
end

--[[
	Panneau de texte long (conseil, consigne) : petit titre en haut, corps sur plusieurs lignes
	(TextScaled + retour à la ligne). Même usage que Props.Sign ; `body` peut faire deux phrases.
]]
function Props.Notice(part: BasePart, title: string, body: string, color: Color3, face: Enum.NormalId?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Notice"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(0.92, 0.2)
	titleLabel.Position = UDim2.fromScale(0.04, 0.04)
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = color
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Parent = gui
	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Size = UDim2.fromScale(0.92, 0.7)
	bodyLabel.Position = UDim2.fromScale(0.04, 0.26)
	bodyLabel.Text = body
	bodyLabel.TextScaled = true
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.TextColor3 = C.White
	bodyLabel.Font = Enum.Font.GothamMedium
	bodyLabel.Parent = gui
	gui.Parent = part
	return gui
end

------------------------------------------------------------------------------------
-- Ventilateur
------------------------------------------------------------------------------------

type BladeSection = { From: number, To: number, Pitch: number, Sweep: number, Chord: number }

export type FanOptions = {
	Speed: number?, -- vitesse de rotation (rad/s) appliquée par le client ; défaut 2
	Light: boolean?, -- PointLight au centre (compte dans le budget de lumières)
	Rgb: boolean?, -- anneau recoloré en arc-en-ciel par le client (RgbStrip)
	Lite: boolean?, -- version économe en pièces (cadre simple, pales en 2 parties)
	Brand: string?, -- texte de l'autocollant du moyeu
	Frame: Color3?,
	BladeColor: Color3?,
}

--[[
	Ventilateur de boîtier stylisé : cadre carré à coins arrondis, stator à 4 bras, moyeu avec
	autocollant, pales vrillées, anneau LED sur la face avant.
	`cf` : centre de la face ARRIÈRE (plan de fixation) ; RightVector = axe, vers l'avant.
	Le moyeu (tag TrapSpin + Axis + Speed) tourne côté client ; les pales y sont soudées.
]]
function Props.Fan(
	parent: Instance,
	cf: CFrame,
	diameter: number,
	glowColor: Color3,
	blades: number?,
	options: FanOptions?
): Model
	local opts: FanOptions = options or {}
	local model = Build.Model("Fan", parent)
	local r = diameter / 2
	local lite = opts.Lite == true or diameter < 24
	local half = r * 1.08 -- demi-côté du cadre
	local inner = r * 1.01 -- bord intérieur des traverses (tangent à l'ouverture)
	local bar = half - inner
	local corner = r * 0.16 -- rayon des coins arrondis
	local depth = math.clamp(diameter * 0.14, 1.6, 14)
	local frameColor = opts.Frame or C.Black
	local mid = depth / 2

	-- Cadre : 4 traverses + coins arrondis (+ goussets et patins si détaillé)
	for k = 0, 3 do
		local rot = cf * CFrame.Angles(k * math.pi / 2, 0, 0)
		Props.Box(
			model,
			"FrameBar",
			Vector3.new(depth, bar, (half - corner) * 2),
			rot * CFrame.new(mid, inner + bar / 2, 0),
			frameColor
		)
		local c = half - corner
		Props.Rod(
			model,
			"FrameCorner",
			rot * CFrame.new(mid, c, c),
			depth,
			corner * 2,
			frameColor,
			Enum.Material.SmoothPlastic
		)
		if not lite then
			local leg = inner * 2 - r * math.sqrt(2)
			Props.Wedge(
				model,
				"FrameGusset",
				Vector3.new(depth, leg, leg),
				rot * CFrame.new(mid, inner - leg / 2, inner - leg / 2) * CFrame.Angles(0, 0, math.pi),
				frameColor
			)
			Props.Rod(
				model,
				"RubberPad",
				rot * CFrame.new(depth + 0.1, c, c),
				0.3,
				corner * 1.7,
				C.Rubber:Lerp(glowColor, 0.08),
				Enum.Material.SmoothPlastic
			)
		end
	end

	-- Stator (fixe) : moteur + 4 bras, à l'arrière des pales
	local hubRadius = r * 0.34
	if not lite then
		Props.Rod(model, "Motor", cf * CFrame.new(depth * 0.12, 0, 0), depth * 0.24, hubRadius * 1.9, frameColor)
		for k = 0, 3 do
			local len = inner - hubRadius * 0.9
			Props.Box(
				model,
				"Strut",
				Vector3.new(depth * 0.2, r * 0.05 + 0.2, len),
				cf
					* CFrame.Angles(math.pi / 4 + k * math.pi / 2, 0, 0)
					* CFrame.new(depth * 0.12, 0, hubRadius * 0.9 + len / 2),
				frameColor
			)
		end
	end

	-- Rotor : moyeu ancré (tourné par le client) + pales soudées
	local hubCf = cf * CFrame.new(depth * 0.55, 0, 0)
	local hub = Build.Decor({
		Name = "SpinHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(depth * 0.8, hubRadius * 2, hubRadius * 2),
		CFrame = hubCf,
		Color = C.MetalDark,
		Material = METAL,
		CastShadow = false,
		Tags = { "TrapSpin" },
		Parent = model,
	})
	hub:SetAttribute("Axis", "X")
	hub:SetAttribute("Speed", opts.Speed or 2)
	if not lite then
		local sticker = Props.Rod(
			hub,
			"Sticker",
			hubCf * CFrame.new(depth * 0.4 + 0.08, 0, 0),
			0.16,
			hubRadius * 1.56,
			C.Bg,
			Enum.Material.SmoothPlastic
		)
		Props.Label(sticker, opts.Brand or "AngaTV", glowColor, Enum.NormalId.Right, Enum.Font.GothamBlack)
		weldTo(hub, sticker)
	end
	local count = blades or 9
	local tip = r * 0.95
	local span = tip - hubRadius
	local bladeColor = opts.BladeColor or C.Black:Lerp(glowColor, 0.14)
	local thickness = 0.25 + r * 0.008
	-- Pale vrillée : emplanture étroite et très inclinée, puis sections plus larges, moins
	-- inclinées et balayées vers l'arrière (effet de pale courbe). 2 sections si économe.
	local sections: { BladeSection } = if lite
		then {
			{ From = hubRadius * 0.92, To = hubRadius + span * 0.45, Pitch = 38, Sweep = 0, Chord = 0.6 },
			{ From = hubRadius + span * 0.45 - 0.1, To = tip, Pitch = 24, Sweep = 9, Chord = 0.7 },
		}
		else {
			{ From = hubRadius * 0.92, To = hubRadius + span * 0.36, Pitch = 40, Sweep = 0, Chord = 0.46 },
			{ From = hubRadius + span * 0.34, To = hubRadius + span * 0.7, Pitch = 31, Sweep = 7, Chord = 0.6 },
			{ From = hubRadius + span * 0.68, To = tip, Pitch = 22, Sweep = 15, Chord = 0.7 },
		}
	for i = 0, count - 1 do
		local angle = i * math.pi * 2 / count
		for _, s in sections do
			local radial = (s.From + s.To) / 2
			local blade = Build.Decor({
				Name = "Blade",
				Size = Vector3.new(thickness, s.To - s.From, 2 * math.pi * radial / count * s.Chord),
				CFrame = hubCf
					* CFrame.Angles(angle + math.rad(s.Sweep), 0, 0)
					* CFrame.new(0, radial, 0)
					* CFrame.Angles(0, math.rad(s.Pitch), 0),
				Color = bladeColor,
				Material = Enum.Material.SmoothPlastic,
				CastShadow = false,
				Parent = hub,
			})
			weldTo(hub, blade)
		end
	end

	-- Anneau LED sur le bord intérieur de la face avant
	local ring = Props.Ring(
		model,
		"RgbRing",
		cf * CFrame.new(depth - 0.15, 0, 0),
		inner - bar * 0.2,
		math.max(bar * 0.7, 0.3),
		0.5,
		if lite then 10 else 16,
		glowColor,
		Enum.Material.Neon
	)
	if opts.Rgb then
		for _, segment in ring do
			segment:AddTag("RgbStrip")
		end
	end
	if opts.Light then
		local light = Props.Box(model, "Light", Vector3.one, cf * CFrame.new(depth + 2, 0, 0), C.White)
		light.Transparency = 1
		Build.PointLight(light, glowColor, 1.2, diameter)
	end
	return model
end

-- Grille "nid d'abeille" circulaire (motif kagomé de 3 familles de barres), plan YZ de `cf`.
function Props.Grille(
	parent: Instance,
	cf: CFrame,
	radius: number,
	spacing: number,
	barWidth: number,
	color: Color3,
	rimSegments: number?
): Model
	local model = Build.Model("Grille", parent)
	for family = 0, 2 do
		local rot = cf * CFrame.Angles(family * math.pi / 3, 0, 0)
		local offset = if family == 2 then spacing / 2 else 0
		local k = -math.floor(radius / spacing)
		while k * spacing + offset < radius do
			local y = k * spacing + offset
			local chord = 2 * math.sqrt(math.max(radius * radius - y * y, 0))
			if chord > spacing * 0.5 then
				Props.Box(
					model,
					"GrilleBar",
					Vector3.new(barWidth * 0.8, barWidth, chord),
					rot * CFrame.new(0, y, 0),
					color,
					METAL
				)
			end
			k += 1
		end
	end
	Props.Ring(model, "GrilleRim", cf, radius, barWidth * 2.2, barWidth * 1.4, rimSegments or 16, color, METAL)
	return model
end

------------------------------------------------------------------------------------
-- Ailettes, câbles, tubes, condensateurs
------------------------------------------------------------------------------------

-- Bloc d'ailettes (radiateur) : plaques fines empilées le long du LookVector de `cf` (décor).
function Props.Fins(
	parent: Instance,
	cf: CFrame,
	width: number,
	height: number,
	depth: number,
	count: number,
	color: Color3?
): Model
	local model = Build.Model("Fins", parent)
	local spacing = depth / count
	for i = 0, count - 1 do
		local fin = Props.Box(
			model,
			"Fin",
			Vector3.new(width, height, math.max(spacing * 0.35, 0.3)),
			cf * CFrame.new(0, 0, -depth / 2 + spacing * (i + 0.5)),
			color or C.Aluminum,
			METAL
		)
		fin.Reflectance = 0.05
	end
	return model
end

-- Câble gainé (décor) qui suit une liste de points (segments cylindriques + articulations).
function Props.Cable(
	parent: Instance,
	points: { Vector3 },
	radius: number,
	color: Color3,
	material: Enum.Material?
): Model
	local model = Build.Model("Cable", parent)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		Props.Rod(
			model,
			"Segment",
			Props.Along(a, b),
			(b - a).Magnitude,
			radius * 2,
			color,
			material or Enum.Material.Fabric
		)
		if i < #points - 1 then
			Build.Decor({
				Name = "Joint",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * radius * 2,
				CFrame = CFrame.new(b),
				Color = color,
				Material = material or Enum.Material.Fabric,
				CastShadow = false,
				Parent = model,
			})
		end
	end
	return model
end

-- Câble en arc (courbe de Bézier quadratique).
function Props.ArcCable(
	parent: Instance,
	from: Vector3,
	control: Vector3,
	to: Vector3,
	radius: number,
	color: Color3,
	segments: number?
): Model
	local points = {}
	local count = segments or 8
	for i = 0, count do
		local t = i / count
		table.insert(points, from * (1 - t) ^ 2 + control * 2 * (1 - t) * t + to * t ^ 2)
	end
	return Props.Cable(parent, points, radius, color)
end

-- Tube rigide de watercooling : verre + liquide lumineux, raccords chromés aux coudes et aux bouts.
function Props.Tube(parent: Instance, points: { Vector3 }, radius: number, coolant: Color3): Model
	local model = Build.Model("Tube", parent)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local along = Props.Along(a, b)
		local length = (b - a).Magnitude
		local glass = Props.Rod(model, "TubeGlass", along, length, radius * 2, Color3.fromRGB(215, 235, 255))
		glass.Material = Enum.Material.Glass
		glass.Transparency = 0.55
		Props.Rod(model, "TubeCoolant", along, length, radius * 1.3, coolant, Enum.Material.Neon).Transparency = 0.3
		if i < #points - 1 then
			Build.Decor({
				Name = "Elbow",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * radius * 2.7,
				CFrame = CFrame.new(b),
				Color = C.Nickel,
				Material = METAL,
				Reflectance = 0.15,
				CastShadow = false,
				Parent = model,
			})
		end
	end
	for _, endpoint in { points[1], points[#points] } do
		Build.Decor({
			Name = "Fitting",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * radius * 2.6,
			CFrame = CFrame.new(endpoint),
			Color = C.Nickel,
			Material = METAL,
			CastShadow = false,
			Parent = model,
		})
	end
	return model
end

-- Condensateur électrolytique : manchon, capot alu gravé en croix, bande de polarité, collerette lumineuse.
-- `solid` : le corps est une pièce solide (sinon décor pur).
function Props.Capacitor(
	parent: Instance,
	position: Vector3,
	radius: number,
	height: number,
	color: Color3,
	glowColor: Color3,
	solid: boolean?
): Part
	local body = Build.Cylinder({
		Name = "Capacitor",
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * VERTICAL,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	if not solid then
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
	end
	Props.Rod(
		parent,
		"CapTop",
		CFrame.new(position + Vector3.new(0, height + 0.1, 0)) * VERTICAL,
		0.3,
		radius * 1.9,
		C.Aluminum
	)
	for _, angle in { 0, math.pi / 2 } do
		Props.Box(
			parent,
			"CapVent",
			Vector3.new(radius * 1.5, 0.12, radius * 0.12 + 0.1),
			CFrame.new(position + Vector3.new(0, height + 0.3, 0)) * CFrame.Angles(0, angle, 0),
			C.Bg
		)
	end
	Props.Box(
		parent,
		"CapMinus",
		Vector3.new(0.2, height * 0.7, radius * 0.5),
		CFrame.new(position + Vector3.new(-radius - 0.05, height * 0.5, 0)),
		C.Silk
	)
	Build.Neon({
		Name = "CapRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, radius * 2 + 0.3, radius * 2 + 0.3),
		CFrame = CFrame.new(position + Vector3.new(0, height - 1, 0)) * VERTICAL,
		Color = glowColor,
		Transparency = 0.45,
		Parent = parent,
	})
	return body
end

------------------------------------------------------------------------------------
-- Composants géants (héros au centre de chaque monde)
-- `cf` : centre de la base, posé au sol ; la face avant (-Z local) regarde `cf.LookVector`.
------------------------------------------------------------------------------------

-- Pièce solide d'un composant géant.
local function solid(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	return Build.Part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CastShadow = false,
		Parent = parent,
	})
end

local function neon(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number?)
	return Build.Neon({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Transparency = transparency or 0.15,
		Parent = parent,
	})
end

-- Alimentation (PSU) : caisson noir, gros ventilateur sur le dessus derrière une grille,
-- panneau modulaire lumineux, étiquette de certification, câbles gainés qui montent.
function Props.PowerSupply(parent: Instance, cf: CFrame, primary: Color3, secondary: Color3): Model
	local model = Build.Model("PowerSupply", parent)
	local w, h, d = 104, 46, 84
	solid(model, "Chassis", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), C.Black, METAL)
	-- Arêtes chanfreinées et liseré
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			Props.Box(
				model,
				"Edge",
				Vector3.new(1.4, h + 0.4, 1.4),
				cf * CFrame.new(x * w / 2, h / 2, z * d / 2),
				C.MetalLight,
				METAL
			)
		end
	end
	neon(model, "Trim", Vector3.new(w + 0.6, 0.8, 0.6), cf * CFrame.new(0, h - 1, -d / 2), primary, 0.2)
	neon(model, "TrimBack", Vector3.new(w + 0.6, 0.8, 0.6), cf * CFrame.new(0, h - 1, d / 2), primary, 0.2)
	-- Ventilateur 135 mm géant sous une grille nid d'abeille (face du dessus)
	local top = cf * CFrame.new(0, h, 0) * CFrame.Angles(0, 0, math.pi / 2)
	Props.Fan(model, top * CFrame.new(-4, 0, 0), 60, primary, 7, { Speed = 1.6, Brand = "ANGA", Lite = true })
	Props.Grille(model, top * CFrame.new(0.6, 0, 0), 31, 7.5, 0.9, C.MetalLight, 20)
	-- Étiquette de certification (face avant)
	local label =
		Props.Box(model, "Certification", Vector3.new(44, 20, 0.3), cf * CFrame.new(-22, h / 2, -d / 2 - 0.2), C.Bg)
	Props.Sign(label, "ANGA POWER 1200W", "80 PLUS GOLD", C.Gold, C.Silk)
	-- Panneau modulaire (face avant, à droite) : prises lumineuses
	for row = 0, 2 do
		for col = 0, 1 do
			local p = cf * CFrame.new(18 + col * 14, 10 + row * 11, -d / 2 - 0.6)
			Props.Box(model, "Socket", Vector3.new(11, 7, 1.2), p, C.Rubber)
			neon(model, "SocketGlow", Vector3.new(9, 0.5, 0.4), p * CFrame.new(0, -2.6, -0.5), secondary, 0.3)
		end
	end
	-- Interrupteur + prise secteur
	Props.Box(model, "Switch", Vector3.new(6, 9, 1.2), cf * CFrame.new(44, 34, -d / 2 - 0.6), C.Brand)
	-- Câbles gainés qui montent vers le haut du monde
	for i, x in { -30, 10, 34 } do
		Props.ArcCable(
			model,
			(cf * CFrame.new(x, h, -d / 2 + 6)).Position,
			(cf * CFrame.new(x * 1.2, h + 30, -d / 2 - 12)).Position,
			(cf * CFrame.new(x * 0.8, h + 44, -d / 2 + 30 + i * 4)).Position,
			2,
			if i == 2 then secondary else C.Black,
			5
		)
	end
	return model
end

-- Kit de barrettes de RAM géantes debout dans leurs slots (dissipateur, puces, barre RGB).
function Props.RamKit(
	parent: Instance,
	cf: CFrame,
	count: number,
	length: number,
	height: number,
	primary: Color3,
	secondary: Color3
): Model
	local model = Build.Model("RamKit", parent)
	local pitch = 16
	for i = 1, count do
		local z = (i - (count + 1) / 2) * pitch
		local base = cf * CFrame.new(0, 0, z)
		solid(model, "DimmSlot", Vector3.new(length + 8, 5, 7), base * CFrame.new(0, 2.5, 0), C.Black)
		for _, x in { -1, 1 } do
			Props.Box(
				model,
				"Latch",
				Vector3.new(3, 9, 5),
				base * CFrame.new(x * (length / 2 + 5), 4.5, 0),
				C.White:Lerp(secondary, 0.3)
			)
		end
		local y0 = 5
		Props.Box(model, "Pcb", Vector3.new(length, height, 1.2), base * CFrame.new(0, y0 + height / 2, 0), C.PcbDark)
		Props.Box(
			model,
			"Fingers",
			Vector3.new(length - 4, 2, 1.4),
			base * CFrame.new(0, y0 + 1, 0),
			C.Gold,
			Enum.Material.Foil
		)
		local spreaderH = height - 8
		local spreader = solid(
			model,
			"HeatSpreader",
			Vector3.new(length, spreaderH, 4),
			base * CFrame.new(0, y0 + 6 + spreaderH / 2, 0),
			if i % 2 == 0 then C.MetalDark else C.Aluminum:Lerp(C.MetalDark, 0.4),
			METAL
		)
		if i == 1 then
			Props.Sign(spreader, "MEMORY LANES", "DDR5 · 64 GB", primary, C.Silk)
		end
		-- Chevrons sculptés sur le dissipateur
		for f = -2, 2 do
			Build.Neon({
				Name = "Chevron",
				Size = Vector3.new(1.2, spreaderH * 0.8, 0.3),
				CFrame = base
					* CFrame.new(f * length / 6, y0 + 6 + spreaderH / 2, -2.1)
					* CFrame.Angles(0, 0, math.rad(if f % 2 == 0 then 24 else -24)),
				Color = secondary,
				Transparency = 0.35,
				Parent = model,
			})
		end
		neon(model, "RgbBar", Vector3.new(length, 2.4, 4.2), base * CFrame.new(0, y0 + 7 + spreaderH, 0), primary, 0.1):AddTag(
			"RgbStrip"
		)
	end
	return model
end

-- Pile de SSD M.2 géants sur entretoises (puces NAND, contrôleur, dissipateur gravé).
function Props.SsdStack(parent: Instance, cf: CFrame, levels: number, primary: Color3, secondary: Color3): Model
	local model = Build.Model("SsdStack", parent)
	local length, width, pitch = 96, 34, 22
	for level = 1, levels do
		local y = level * pitch
		local base = cf * CFrame.new(0, y, 0) * CFrame.Angles(0, (level - 1) * math.rad(18), 0)
		solid(model, "Pcb", Vector3.new(length, 1.6, width), base, C.Pcb:Lerp(primary, 0.12))
		for _, x in { -length / 2 + 4, length / 2 - 4 } do
			for _, z in { -width / 2 + 4, width / 2 - 4 } do
				Props.Rod(model, "Standoff", base * CFrame.new(x, -pitch / 2, z) * VERTICAL, pitch - 1.6, 2, C.Nickel)
			end
		end
		Props.Box(
			model,
			"Fingers",
			Vector3.new(5, 1.8, width - 6),
			base * CFrame.new(-length / 2 + 2, 0, 0),
			C.Gold,
			Enum.Material.Foil
		)
		Props.Box(model, "Controller", Vector3.new(12, 2.4, 12), base * CFrame.new(-28, 1.6, 0), C.Bg)
		for n = 0, 2 do
			local chip = Props.Box(
				model,
				"Nand",
				Vector3.new(15, 3, 22),
				base * CFrame.new(-8 + n * 19, 2, 0),
				C.Black,
				Enum.Material.SmoothPlastic
			)
			if n == 1 and level == levels then
				Props.Label(chip, "DATA VAULT", secondary, Enum.NormalId.Top, Enum.Font.GothamBlack)
			end
		end
		neon(
			model,
			"DataLine",
			Vector3.new(length - 8, 0.4, 0.8),
			base * CFrame.new(0, 1, -width / 2 + 1),
			secondary,
			0.25
		)
	end
	return model
end

-- Radiateur de watercooling debout : faisceau d'ailettes, boîtes à eau, 2 ventilateurs,
-- réservoir en verre au liquide lumineux, tubes rigides.
function Props.Radiator(parent: Instance, cf: CFrame, primary: Color3, secondary: Color3): Model
	local model = Build.Model("Radiator", parent)
	local w, h, t = 44, 84, 10
	for _, y in { 3, h + 3 } do
		solid(model, "Tank", Vector3.new(w + 6, 6, t + 2), cf * CFrame.new(0, y, 0), C.Black, METAL)
	end
	Props.Fins(model, cf * CFrame.new(0, h / 2 + 6, 0) * CFrame.Angles(math.pi / 2, 0, 0), w, t, h - 6, 18, C.Aluminum)
	for _, x in { -w / 2 - 1, w / 2 + 1 } do
		Props.Box(model, "Rail", Vector3.new(2, h, t + 1), cf * CFrame.new(x, h / 2 + 6, 0), C.MetalDark, METAL)
	end
	-- Deux ventilateurs vissés sur la face avant (soufflent vers l'avant)
	for i = 0, 1 do
		local fanCf = CFrame.fromMatrix((cf * CFrame.new(0, 26 + i * 42, -t / 2)).Position, cf.LookVector, UP)
		Props.Fan(model, fanCf, 40, primary, 7, { Speed = 3, Lite = true, Frame = C.MetalDark })
	end
	-- Réservoir cylindrique (à droite) + tubes
	local tankPos = (cf * CFrame.new(w / 2 + 22, 0, 0)).Position
	Props.Rod(model, "ReservoirGlass", CFrame.new(tankPos + Vector3.new(0, 34, 0)) * VERTICAL, 56, 16, C.Silk).Transparency =
		0.6
	Props.Rod(
		model,
		"Coolant",
		CFrame.new(tankPos + Vector3.new(0, 30, 0)) * VERTICAL,
		46,
		13,
		secondary,
		Enum.Material.Neon
	).Transparency =
		0.25
	for _, y in { 5, 63 } do
		Props.Rod(model, "Cap", CFrame.new(tankPos + Vector3.new(0, y, 0)) * VERTICAL, 3, 17, C.Black)
	end
	Props.Tube(model, {
		tankPos + Vector3.new(0, 64, 0),
		tankPos + Vector3.new(0, 76, 0),
		(cf * CFrame.new(w / 2 - 4, 76, 0)).Position,
		(cf * CFrame.new(w / 2 - 4, h + 6, 0)).Position,
	}, 2, primary)
	Props.Tube(model, {
		tankPos + Vector3.new(-9, 12, 0),
		(cf * CFrame.new(w / 2 + 3, 12, 0)).Position,
	}, 2, primary)
	return model
end

-- Ventirad de processeur : socket, CPU (IHS gravé), caloducs en U, tour d'ailettes, ventilateur.
function Props.CpuCooler(parent: Instance, cf: CFrame, primary: Color3, secondary: Color3): Model
	local model = Build.Model("CpuCooler", parent)
	solid(model, "Socket", Vector3.new(76, 4, 76), cf * CFrame.new(0, 2, 0), C.Black)
	for k = 0, 3 do
		Props.Box(
			model,
			"LoadPlate",
			Vector3.new(72, 1.4, 4),
			cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 4.7, -34),
			C.Aluminum,
			METAL
		)
	end
	solid(model, "Substrate", Vector3.new(60, 2, 60), cf * CFrame.new(0, 5, 0), C.Pcb:Lerp(C.Gold, 0.1))
	local ihs = solid(model, "Ihs", Vector3.new(48, 4, 48), cf * CFrame.new(0, 8, 0), C.Nickel, METAL)
	Props.Label(ihs, "THE CORE", primary, Enum.NormalId.Front, Enum.Font.GothamBlack)
	-- Tour d'ailettes (au-dessus, on voit le CPU dessous)
	Props.Fins(model, cf * CFrame.new(0, 58, 0) * CFrame.Angles(math.pi / 2, 0, 0), 56, 30, 60, 16, C.Aluminum)
	Props.Box(model, "Cap", Vector3.new(58, 3, 32), cf * CFrame.new(0, 89.5, 0), C.Black, METAL)
	neon(model, "CapGlow", Vector3.new(58.4, 0.8, 32.4), cf * CFrame.new(0, 88, 0), primary, 0.2)
	-- Caloducs en U : jambes verticales du CPU jusque dans les ailettes
	for i = -2, 2 do
		for _, z in { -9, 9 } do
			Props.Rod(model, "HeatPipe", cf * CFrame.new(i * 9, 48, z) * VERTICAL, 80, 3.2, C.Copper)
		end
	end
	-- Ventilateur sur la face avant de la tour d'ailettes
	local fanCf = CFrame.fromMatrix((cf * CFrame.new(0, 58, -16)).Position, cf.LookVector, UP)
	Props.Fan(model, fanCf, 52, secondary, 7, { Speed = 4, Lite = true })
	return model
end

-- Carte graphique géante debout : PCB, carénage à facettes, 3 ventilateurs, backplate, logo RGB.
function Props.GraphicsCard(parent: Instance, cf: CFrame, primary: Color3, secondary: Color3): Model
	local model = Build.Model("GraphicsCard", parent)
	local length, height, thick = 112, 44, 16
	local cy = height / 2 + 8
	solid(model, "PcieSlot", Vector3.new(length - 20, 6, 8), cf * CFrame.new(-6, 3, 0), C.Black)
	Props.Box(model, "Fingers", Vector3.new(length - 30, 3, 2), cf * CFrame.new(-6, 7, 0), C.Gold, Enum.Material.Foil)
	solid(model, "Shroud", Vector3.new(length, height, thick), cf * CFrame.new(0, cy, 0), C.MetalDark, METAL)
	Props.Box(
		model,
		"Backplate",
		Vector3.new(length - 2, height - 2, 1),
		cf * CFrame.new(0, cy, thick / 2 + 0.5),
		C.Black,
		METAL
	)
	for _, side in { -1, 1 } do
		Props.Wedge(
			model,
			"Facet",
			Vector3.new(thick, height, 6),
			cf * CFrame.new(side * (length / 2 + 3), cy, 0) * CFrame.Angles(0, -side * math.pi / 2, 0),
			C.MetalLight,
			METAL
		)
	end
	for k = -1, 1 do
		local fanCf = CFrame.fromMatrix((cf * CFrame.new(k * 36, cy, -thick / 2)).Position, cf.LookVector, UP)
		Props.Fan(model, fanCf, 32, primary, 9, { Speed = 5 - k, Lite = true })
	end
	local logo =
		neon(model, "Logo", Vector3.new(length - 12, 3, thick - 2), cf * CFrame.new(0, height + 9.5, 0), secondary, 0.1)
	logo:AddTag("RgbStrip")
	local plate = Props.Box(
		model,
		"Nameplate",
		Vector3.new(44, 10, 0.3),
		cf * CFrame.new(0, cy, thick / 2 + 1.2) * CFrame.Angles(0, math.pi, 0),
		C.Bg
	)
	Props.Label(plate, "RENDER", primary, Enum.NormalId.Front, Enum.Font.GothamBlack)
	return model
end

-- Cœur neuronal (puce IA) : socle biseauté, substrat, die gravé, orbe et anneaux en rotation.
function Props.NeuralCore(parent: Instance, cf: CFrame, primary: Color3, secondary: Color3): Model
	local model = Build.Model("NeuralCore", parent)
	solid(model, "Pedestal", Vector3.new(56, 10, 56), cf * CFrame.new(0, 5, 0), C.MetalDark, METAL)
	solid(model, "Substrate", Vector3.new(44, 3, 44), cf * CFrame.new(0, 11.5, 0), C.Pcb:Lerp(secondary, 0.15))
	local die = solid(model, "Die", Vector3.new(26, 3, 26), cf * CFrame.new(0, 14.5, 0), C.Bg, Enum.Material.Glass)
	Props.Label(die, "NPU", primary, Enum.NormalId.Top, Enum.Font.GothamBlack)
	for k = 0, 3 do
		Build.Neon({
			Name = "Circuit",
			Size = Vector3.new(0.8, 0.3, 20),
			CFrame = cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 13.2, -18),
			Color = secondary,
			Transparency = 0.2,
			Parent = model,
		})
	end
	local center = cf * CFrame.new(0, 52, 0)
	local orb = neon(model, "Orb", Vector3.one * 22, center, primary, 0.15)
	orb.Shape = Enum.PartType.Ball
	-- Anneaux : moyeu invisible ancré (TrapSpin, axe Y) + segments soudés, inclinés différemment
	for i, tilt in { 12, -28, 52 } do
		local hubCf = center * CFrame.Angles(math.rad(tilt), math.rad(i * 40), 0)
		local hub = Props.SpinHub(model, hubCf, "Y", 0.5 + i * 0.25)
		for _, part in
			Props.Ring(
				model,
				"Halo",
				hubCf * CFrame.Angles(0, 0, math.pi / 2),
				20 + i * 6,
				1.2,
				0.8,
				16,
				if i == 2 then primary else secondary,
				Enum.Material.Neon
			)
		do
			part.Transparency = 0.3
			weldTo(hub, part)
		end
	end
	-- Faisceaux de données du socle vers l'orbe
	for k = 0, 3 do
		local foot = (cf * CFrame.Angles(0, math.pi / 4 + k * math.pi / 2, 0) * CFrame.new(0, 10, -30)).Position
		Build.Neon({
			Name = "Synapse",
			Size = Vector3.new((foot - center.Position).Magnitude, 0.6, 0.6),
			CFrame = Props.Along(foot, center.Position),
			Color = secondary,
			Transparency = 0.4,
			Parent = model,
		})
	end
	return model
end

return Props
