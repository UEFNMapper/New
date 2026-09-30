--!strict
--[[
	RoomProps : le décor de la chambre d'Anga à l'échelle géante (le joueur est minuscule sur le bureau)
	et les pièces détaillées de la coque de la tour.
	- Chambre : bureau, sol, murs, plafond (sans ombre : le soleil éclaire toujours le bureau), fenêtre
	  au coucher de soleil, posters AngaTV, mousse acoustique, enseigne néon, chaise gamer
	- Setup de streamer : écran (face avant libre pour le client), webcam, clavier mécanique RGB
	  (touches solides : on saute dessus), souris, tapis XXL, micro sur bras articulé, casque sur son
	  support, tasse, lampe de bureau, multiprise, post-it
	- Coque : ventilateur de boîtier fin (derrière la façade mesh), vis moletée

	Convention (comme Props) : les volumes sur lesquels on marche sont solides, les petits détails
	sont du décor pur (ni collision, ni requêtes, ni toucher, sans ombre).
	Repère d'un objet posé : `cf` = centre de sa base sur le bureau, LookVector = sa face avant.
]]

local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local Common = require(script.Parent.Common)

local RoomProps = {}

local C = Common.C
local UP = Common.UP
local VERTICAL = Common.VERTICAL
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local FABRIC = Enum.Material.Fabric

-- Couleurs de la chambre (le violet de l'app AngAInOne sert d'accent)
local INK = Color3.fromRGB(30, 30, 36) -- plastique noir mat du matériel
local CHARCOAL = Color3.fromRGB(46, 48, 58)
local PAPER_YELLOW = Color3.fromRGB(255, 226, 102)
local PAPER_PINK = Color3.fromRGB(255, 156, 196)
local PAPER_CYAN = Color3.fromRGB(140, 228, 240)
local WARM = Color3.fromRGB(255, 214, 160)
local APP_ACCENT = Color3.fromHex("9B2FD4") -- violet de l'app AngAInOne (Branding.PartnerApp.Accent)

RoomProps.Colors = table.freeze({
	Ink = INK,
	Charcoal = CHARCOAL,
	PaperYellow = PAPER_YELLOW,
	PaperPink = PAPER_PINK,
	PaperCyan = PAPER_CYAN,
	Warm = WARM,
})

------------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------------

-- Volume solide (on marche dessus / on s'y cogne).
local function solid(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shadow: boolean?
): Part
	return Build.Part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or SMOOTH,
		CastShadow = shadow ~= false,
		Parent = parent,
	})
end
RoomProps.Solid = solid

-- Cylindre solide : axe = X local de `cf`.
local function solidRod(
	parent: Instance,
	name: string,
	cf: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Build.Cylinder({
		Name = name,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = material or SMOOTH,
		Parent = parent,
	})
end

local function neon(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	transparency: number?
): Part
	return Build.Neon({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Transparency = transparency or 0,
		Parent = parent,
	})
end
RoomProps.Neon = neon

local function ball(
	parent: Instance,
	name: string,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return Build.Decor({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = cf,
		Color = color,
		Material = material or SMOOTH,
		CastShadow = false,
		Parent = parent,
	})
end

-- Barre (décor) de `a` à `b`, section carrée `width`.
local function beam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Rod(parent, name, Props.Along(a, b), (b - a).Magnitude, width, color, material)
end

-- Cylindre vertical (décor) posé sur `base` (centre du dessous).
local function post(
	parent: Instance,
	name: string,
	base: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Rod(
		parent,
		name,
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * VERTICAL,
		height,
		diameter,
		color,
		material
	)
end

------------------------------------------------------------------------------------
-- Texte (SurfaceGui dessiné sur une face)
------------------------------------------------------------------------------------

-- SurfaceGui autoéclairé sur une face (densité en pixels par stud, adaptée aux grandes surfaces).
local function surface(part: BasePart, face: Enum.NormalId, pixelsPerStud: number, lightInfluence: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Print"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = lightInfluence or 0.2
	gui.Parent = part
	return gui
end

local function textLabel(
	parent: Instance,
	text: string,
	color: Color3,
	font: Enum.Font,
	position: UDim2,
	size: UDim2,
	rotation: number?
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = color
	label.Font = font
	label.Rotation = rotation or 0
	label.Parent = parent
	return label
end

-- Texte plein cadre sur une face (sérigraphie, légende de touche, logo).
function RoomProps.Print(
	part: BasePart,
	text: string,
	color: Color3,
	face: Enum.NormalId?,
	font: Enum.Font?,
	pixelsPerStud: number?
): SurfaceGui
	local gui = surface(part, face or Enum.NormalId.Front, pixelsPerStud or 8, 0.1)
	textLabel(gui, text, color, font or Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.84))
	return gui
end

------------------------------------------------------------------------------------
-- Petits objets du bureau
------------------------------------------------------------------------------------

-- Post-it : `cf` = centre, face avant (-Z) = côté écrit. `flat` : posé à plat (texte sur le dessus).
function RoomProps.StickyNote(
	parent: Instance,
	cf: CFrame,
	text: string,
	paper: Color3,
	size: number?,
	flat: boolean?
): Part
	local s = size or 22
	local note = Box(parent, "StickyNote", if flat then Vector3.new(s, 0.3, s) else Vector3.new(s, s, 0.3), cf, paper)
	-- Bande collante un peu plus foncée en haut
	local stripCf = if flat then cf * CFrame.new(0, 0.05, -s * 0.4) else cf * CFrame.new(0, s * 0.4, 0.05)
	Box(
		parent,
		"StickyGlue",
		if flat then Vector3.new(s, 0.3, s * 0.2) else Vector3.new(s, s * 0.2, 0.3),
		stripCf,
		paper:Lerp(Color3.new(0, 0, 0), 0.12)
	)
	local gui = surface(note, if flat then Enum.NormalId.Top else Enum.NormalId.Front, 10, 0.25)
	textLabel(
		gui,
		text,
		Color3.fromRGB(40, 36, 60),
		Enum.Font.PermanentMarker,
		UDim2.fromScale(0.08, 0.2),
		UDim2.fromScale(0.84, 0.72),
		-4
	)
	return note
end

-- Tasse géante « ANGA » (volume solide), café fumant. `look` = côté du logo.
function RoomProps.Mug(parent: Instance, base: Vector3, look: Vector3): Model
	local model = Build.Model("Mug", parent)
	local cf = Common.Facing(base, look)
	local d, h = 100, 118
	local white = Color3.fromRGB(236, 236, 240)
	Build.Cylinder({
		Name = "MugBody",
		Size = Vector3.new(h, d, d),
		CFrame = cf * CFrame.new(0, h / 2, 0) * VERTICAL,
		Color = white,
		Material = SMOOTH,
		Parent = model,
	})
	Props.Ring(model, "MugRim", cf * CFrame.new(0, h + 3, 0) * VERTICAL, d / 2 - 2, 4, 6, 20, white, SMOOTH)
	Rod(model, "Coffee", cf * CFrame.new(0, h + 0.4, 0) * VERTICAL, 0.8, d - 6, Color3.fromRGB(86, 52, 34))
	-- Anse en C sur le côté droit
	for _, bar in { { 11, 92, 22, 10 }, { 11, 30, 22, 10 }, { 20, 61, 8, 62 } } do
		Box(model, "MugHandle", Vector3.new(bar[3], bar[4], 12), cf * CFrame.new(d / 2 + bar[1], bar[2], 0), white)
	end
	-- Logo imprimé face au spawn (feuille transparente contre le flanc)
	local logo = Box(model, "MugPrint", Vector3.new(58, 46, 0.2), cf * CFrame.new(0, 62, -d / 2 - 0.3), white)
	logo.Transparency = 1
	local gui = surface(logo, Enum.NormalId.Front, 6, 0.3)
	textLabel(gui, "ANGA", C.Brand, Enum.Font.GothamBlack, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.62))
	textLabel(
		gui,
		"#1 STREAMER",
		Color3.fromRGB(60, 60, 72),
		Enum.Font.GothamBold,
		UDim2.fromScale(0.05, 0.64),
		UDim2.fromScale(0.9, 0.3)
	)
	-- Vapeur
	for i, offset in { Vector3.new(-8, 14, 4), Vector3.new(6, 30, -6), Vector3.new(-4, 48, 2) } do
		local puff = ball(model, "Steam", 18 + i * 4, cf * CFrame.new(offset + Vector3.new(0, h, 0)), C.White)
		puff.Transparency = 0.8 + i * 0.04
	end
	return model
end

-- Lampe de bureau articulée : socle (solide, on peut monter dessus), deux bras, tête orientée vers `aim`.
function RoomProps.DeskLamp(parent: Instance, base: Vector3, elbow: Vector3, head: Vector3, aim: Vector3): Model
	local model = Build.Model("DeskLamp", parent)
	local black = Color3.fromRGB(38, 38, 44)
	solidRod(model, "LampBase", CFrame.new(base + Vector3.new(0, 3, 0)) * VERTICAL, 6, 72, black, METAL)
	neon(
		model,
		"LampBaseRing",
		Vector3.new(0.6, 74, 74),
		CFrame.new(base + Vector3.new(0, 0.4, 0)) * VERTICAL,
		WARM,
		0.3
	).Shape =
		Enum.PartType.Cylinder
	local pivot = base + Vector3.new(0, 14, 0)
	post(model, "LampPivot", base + Vector3.new(0, 6, 0), 10, 16, black, METAL)
	beam(model, "LampArmLow", pivot, elbow, 8, Color3.fromRGB(210, 210, 216), METAL)
	beam(model, "LampSpring", pivot + Vector3.new(0, 0, 7), elbow + Vector3.new(0, -10, 7), 2.4, C.Nickel, METAL)
	ball(model, "LampElbow", 14, CFrame.new(elbow), black, METAL)
	beam(model, "LampArmHigh", elbow, head, 8, Color3.fromRGB(210, 210, 216), METAL)
	ball(model, "LampNeck", 12, CFrame.new(head), black, METAL)
	local dir = (aim - head).Unit
	local headCf = Props.Along(head + dir * 6, head + dir * 34)
	Rod(model, "LampShade", headCf, 28, 62, black, METAL)
	Rod(model, "LampShadeBack", Props.Along(head, head + dir * 8), 8, 40, black, METAL)
	neon(model, "LampBulb", Vector3.new(1, 54, 54), headCf * CFrame.new(14.2, 0, 0), WARM, 0).Shape =
		Enum.PartType.Cylinder
	return model
end

-- Multiprise (décor) : boîtier, interrupteur orange allumé, prises branchées.
function RoomProps.PowerStrip(parent: Instance, cf: CFrame): Model
	local model = Build.Model("PowerStrip", parent)
	solid(model, "StripBody", Vector3.new(170, 14, 40), cf * CFrame.new(0, 7, 0), Color3.fromRGB(232, 232, 236))
	neon(model, "StripSwitch", Vector3.new(16, 3, 12), cf * CFrame.new(-72, 14.8, 0), Color3.fromRGB(255, 170, 60), 0.1)
	for i = 0, 3 do
		Box(
			model,
			"Plug",
			Vector3.new(20, 16, 22),
			cf * CFrame.new(-40 + i * 34, 22, 0),
			if i % 2 == 0 then INK else C.White
		)
	end
	return model
end

------------------------------------------------------------------------------------
-- Setup de streamer
------------------------------------------------------------------------------------

export type MonitorParts = {
	Model: Model,
	Screen: CFrame, -- centre de la face avant de la dalle (LookVector = vers le spectateur)
	ScreenSize: Vector3,
	Top: CFrame, -- milieu du bord supérieur du boîtier (pour la webcam)
	Rear: CFrame, -- arrière du boîtier, à mi-hauteur (départ des câbles)
}

--[[
	Écran gamer : pied en V (solide, 4 studs : on grimpe dessus), colonne, boîtier fin avec
	menton et logo, coque arrière et rétroéclairage RGB. La dalle elle-même (contrat StreamMonitor)
	est posée par Lobby à `Screen` : sa face avant est dessinée par le client.
]]
function RoomProps.Monitor(parent: Instance, cf: CFrame, width: number, height: number, bottom: number): MonitorParts
	local model = Build.Model("Monitor", parent)
	local midY = bottom + height / 2
	-- Boîtier : bords fins (5) en haut et sur les côtés, menton (11) en bas
	local housing = solid(
		model,
		"MonitorHousing",
		Vector3.new(width + 10, height + 16, 6),
		cf * CFrame.new(0, midY - 3, 3.6),
		INK,
		METAL,
		true
	)
	housing.CanQuery = false
	local chinLogo = Box(model, "MonitorBrand", Vector3.new(44, 7, 0.2), cf * CFrame.new(0, bottom - 5.5, 0.4), INK)
	chinLogo.Transparency = 1
	RoomProps.Print(chinLogo, "AngaTV", C.Silk, Enum.NormalId.Front, Enum.Font.GothamBold, 10)
	neon(model, "MonitorPowerLed", Vector3.new(3, 1, 0.4), cf * CFrame.new(width / 2 - 8, bottom - 6, 0.5), C.Cyan)
	-- Coque arrière bombée, support VESA, rétroéclairage
	Box(model, "MonitorBack", Vector3.new(width * 0.62, height * 0.62, 12), cf * CFrame.new(0, midY, 12.6), INK, METAL)
	Box(
		model,
		"MonitorBackRim",
		Vector3.new(width * 0.9, height * 0.84, 4),
		cf * CFrame.new(0, midY, 8.6),
		CHARCOAL,
		METAL
	)
	local backlight = neon(
		model,
		"MonitorBacklight",
		Vector3.new(width * 0.5, height * 0.46, 0.4),
		cf * CFrame.new(0, midY, 18.8),
		C.Violet,
		0.1
	)
	backlight:AddTag("RgbStrip")
	Box(model, "VesaMount", Vector3.new(44, 34, 8), cf * CFrame.new(0, midY, 22), CHARCOAL, METAL)
	-- Colonne (solide) avec clip de câbles, pied en V
	local neckTop = midY + 6
	solid(
		model,
		"MonitorNeck",
		Vector3.new(30, neckTop - 4, 12),
		cf * CFrame.new(0, 4 + (neckTop - 4) / 2, 28),
		CHARCOAL,
		METAL
	)
	Box(model, "CableClip", Vector3.new(32, 14, 14), cf * CFrame.new(0, 60, 28), INK)
	neon(
		model,
		"NeckGlow",
		Vector3.new(2, neckTop - 30, 0.4),
		cf * CFrame.new(0, 10 + (neckTop - 30) / 2, 21.8),
		C.Violet,
		0.2
	)
	solid(model, "MonitorFootHub", Vector3.new(50, 4, 44), cf * CFrame.new(0, 2, 26), CHARCOAL, METAL)
	for _, side in { -1, 1 } do
		local legCf = cf * CFrame.new(0, 2, 26) * CFrame.Angles(0, side * math.rad(38), 0) * CFrame.new(0, 0, -40)
		solid(model, "MonitorFootLeg", Vector3.new(20, 4, 80), legCf, CHARCOAL, METAL)
		Box(model, "MonitorFootPad", Vector3.new(22, 1, 12), legCf * CFrame.new(0, -1.6, -34), INK)
	end
	return {
		Model = model,
		Screen = cf * CFrame.new(0, midY, 0),
		ScreenSize = Vector3.new(width, height, 0.6),
		Top = cf * CFrame.new(0, bottom + height + 5, 3.6),
		Rear = cf * CFrame.new(0, midY, 19),
	}
end

-- Webcam clipsée sur le haut de l'écran : `cf` = milieu du bord supérieur, LookVector = vers le spectateur.
function RoomProps.Webcam(parent: Instance, cf: CFrame): Model
	local model = Build.Model("Webcam", parent)
	Box(model, "WebcamClip", Vector3.new(14, 3, 14), cf * CFrame.new(0, 1.5, 0), INK)
	Box(model, "WebcamClipBack", Vector3.new(14, 12, 2), cf * CFrame.new(0, -4, 6.5), INK)
	Rod(model, "WebcamBody", cf * CFrame.new(0, 10, -1), 44, 13, INK, SMOOTH)
	local lensCf = cf * CFrame.new(0, 10, -7.6) * CFrame.Angles(0, math.pi / 2, 0)
	Rod(model, "WebcamLensRing", lensCf, 1.4, 10, C.Nickel, METAL)
	local lens = Rod(
		model,
		"WebcamLens",
		lensCf * CFrame.new(-0.4, 0, 0),
		1.2,
		7,
		Color3.fromRGB(20, 26, 50),
		Enum.Material.Glass
	)
	lens.Reflectance = 0.3
	neon(model, "WebcamLed", Vector3.new(1.4, 1.4, 0.4), cf * CFrame.new(13, 10, -6.6), Color3.fromRGB(120, 255, 150))
	return model
end

--[[
	Clavier mécanique 75 % RGB, à l'échelle géante : chaque touche est une pièce solide (on court
	et on saute de touche en touche : boîtier 5 studs, touches +4,4). `cf` : centre du dessous,
	LookVector = vers l'écran (dos au joueur qui tape), RightVector = sa droite.
]]
type Key = { W: number, Legend: string?, Kind: string? }

-- Une touche (largeur en unités de touche, légende, style).
local function key(w: number, legend: string?, kind: string?): Key
	return { W = w, Legend = legend, Kind = kind }
end

-- `count` touches normales de 1 unité.
local function keys(count: number): { Key }
	local list = {}
	for _ = 1, count do
		table.insert(list, key(1))
	end
	return list
end

-- Rangée : concatène des groupes de touches (chaque rangée fait 15 unités).
local function row(lift: number, groups: { { Key } }): { Keys: { Key }, Lift: number }
	local list = {}
	for _, group in groups do
		for _, k in group do
			table.insert(list, k)
		end
	end
	return { Keys = list, Lift = lift }
end

local MOD, ARROW = "Mod", "Arrow"
local KEY_ROWS: { { Keys: { Key }, Lift: number } } = {
	row(0.8, { { key(1, "ESC", "Accent") }, keys(4), { key(1, "LIVE", "Live") }, keys(9) }),
	row(0.5, { keys(13), { key(2, nil, MOD) } }),
	row(0.2, { { key(1.5, nil, MOD), key(1), key(1, "W", "Wasd") }, keys(10), { key(1.5, nil, MOD) } }),
	row(0, {
		{ key(1.75, nil, MOD), key(1, "A", "Wasd"), key(1, "S", "Wasd"), key(1, "D", "Wasd") },
		keys(7),
		{ key(2.25, "GO !", "Accent") },
	}),
	row(0.2, { { key(2.25, nil, MOD) }, keys(10), { key(1.75, nil, MOD), key(1, nil, ARROW) } }),
	row(0.4, {
		{ key(1.25, nil, MOD), key(1.25, nil, MOD), key(1.25, nil, MOD), key(6.25, "AngaTV", "Space") },
		{ key(1, nil, MOD), key(1, nil, MOD), key(1, nil, ARROW), key(1, nil, ARROW), key(1, nil, ARROW) },
	}),
}

local KEY_COLORS: { [string]: Color3 } = {
	Normal = Color3.fromRGB(66, 68, 84),
	Mod = Color3.fromRGB(96, 98, 118),
	Accent = APP_ACCENT,
	Live = Color3.fromRGB(246, 196, 83),
	Wasd = Color3.fromRGB(222, 226, 238),
	Arrow = Color3.fromRGB(79, 209, 197),
	Space = Color3.fromRGB(84, 86, 104),
}

RoomProps.KEY_UNIT = 24
RoomProps.KEYBOARD_SIZE = Vector3.new(15 * 24 + 24, 5, 6 * 24 + 24)

function RoomProps.Keyboard(parent: Instance, cf: CFrame): Model
	local model = Build.Model("Keyboard", parent)
	local u = RoomProps.KEY_UNIT
	local gap = 3.6
	local size = RoomProps.KEYBOARD_SIZE
	local caseTop = size.Y
	-- Boîtier alu (solide) et liseré lumineux tout autour
	solid(model, "KeyboardCase", size, cf * CFrame.new(0, caseTop / 2, 0), Color3.fromRGB(40, 42, 50), METAL)
	for _, edge in { { 0, size.Z / 2 + 0.2, size.X + 0.8, 0.4 }, { 0, -size.Z / 2 - 0.2, size.X + 0.8, 0.4 } } do
		neon(
			model,
			"KeyboardEdgeGlow",
			Vector3.new(edge[3], 1, edge[4]),
			cf * CFrame.new(edge[1], 1.4, edge[2]),
			C.Violet,
			0.1
		):AddTag("RgbStrip")
	end
	for _, side in { -1, 1 } do
		neon(
			model,
			"KeyboardEdgeGlow",
			Vector3.new(0.4, 1, size.Z),
			cf * CFrame.new(side * (size.X / 2 + 0.2), 1.4, 0),
			C.Violet,
			0.1
		):AddTag("RgbStrip")
	end
	-- Rétroéclairage : une bande par colonne, en arc-en-ciel (visible entre les touches)
	local keysWidth, keysDepth = 15 * u, 6 * u
	for i = 0, 14 do
		local strip = neon(
			model,
			"KeyGlow",
			Vector3.new(u, 0.3, keysDepth),
			cf * CFrame.new(-keysWidth / 2 + (i + 0.5) * u, caseTop + 0.1, 0),
			Color3.fromHSV(0.44 + i / 14 * 0.34, 0.7, 1), -- turquoise -> violet (jamais rouge : couleur du danger)
			0
		)
		strip:AddTag("RgbStrip")
	end
	-- Touches (rangée 0 = la plus éloignée du joueur qui tape)
	for r, spec in KEY_ROWS do
		local x = -keysWidth / 2
		local z = -keysDepth / 2 + (r - 0.5) * u
		for _, key in spec.Keys do
			local w = key.W * u
			local height = 4.4 + spec.Lift
			local kind = key.Kind or "Normal"
			local cap = solid(
				model,
				"Key",
				Vector3.new(w - gap, height, u - gap),
				cf * CFrame.new(x + w / 2, caseTop + height / 2, z),
				KEY_COLORS[kind],
				SMOOTH
			)
			if key.Legend then
				local dark = kind == "Wasd" or kind == "Live"
				RoomProps.Print(
					cap,
					key.Legend,
					if dark then Color3.fromRGB(34, 34, 44) else C.White,
					Enum.NormalId.Top,
					Enum.Font.GothamBlack,
					6
				)
			end
			x += w
		end
	end
	return model
end

-- Souris gamer (solide) : coque en gélule, molette, boutons, logo et halo RGB. LookVector = vers l'avant.
function RoomProps.Mouse(parent: Instance, cf: CFrame): Model
	local model = Build.Model("Mouse", parent)
	local r, len = 30, 56
	solidRod(model, "MouseShell", cf * CFrame.Angles(0, math.pi / 2, 0), len, r * 2, INK, SMOOTH)
	for _, z in { -len / 2, len / 2 } do
		Build.Part({
			Name = "MouseShell",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * r * 2,
			CFrame = cf * CFrame.new(0, 0, z),
			Color = INK,
			Material = SMOOTH,
			Parent = model,
		})
	end
	Box(model, "MouseSplit", Vector3.new(1.4, 1, 40), cf * CFrame.new(0, r + 0.1, -12), Color3.fromRGB(12, 12, 16))
	Rod(model, "MouseWheel", cf * CFrame.new(0, r - 1, -16), 5, 12, CHARCOAL, Enum.Material.Rubber)
	neon(model, "MouseWheelGlow", Vector3.new(5.4, 1, 4), cf * CFrame.new(0, r + 0.2, -16), C.Cyan, 0.2)
	for _, z in { -6, 8 } do
		Box(model, "MouseSideButton", Vector3.new(2, 5, 11), cf * CFrame.new(-24.5, 17, z), CHARCOAL)
	end
	neon(
		model,
		"MouseLogo",
		Vector3.new(9, 0.6, 9),
		cf * CFrame.new(0, r + 0.2, 16) * CFrame.Angles(0, math.pi / 4, 0),
		C.Violet
	):AddTag("RgbStrip")
	neon(
		model,
		"MouseUnderglow",
		Vector3.new(r * 2 + 3, 0.4, len + r * 2 + 3),
		cf * CFrame.new(0, 0.3, 0),
		C.Violet,
		0.2
	):AddTag("RgbStrip")
	return model
end

-- Tapis de souris XXL (sol du lobby) : liseré RGB et logo sérigraphié. `cf` : centre du dessus.
function RoomProps.DeskMat(parent: Instance, cf: CFrame, width: number, depth: number, logo: string): Part
	local mat = solid(
		parent,
		"DeskMat",
		Vector3.new(width, 0.6, depth),
		cf * CFrame.new(0, -0.3, 0),
		Color3.fromRGB(26, 26, 34),
		FABRIC,
		false
	)
	for _, edge in
		{
			{ 0, depth / 2, width, 1 },
			{ 0, -depth / 2, width, 1 },
			{ width / 2, 0, 1, depth },
			{ -width / 2, 0, 1, depth },
		}
	do
		neon(
			parent,
			"MatRgb",
			Vector3.new(edge[3] + 0.4, 0.7, edge[4] + 0.4),
			cf * CFrame.new(edge[1], 0.05, edge[2]),
			C.Violet,
			0.05
		):AddTag("RgbStrip")
	end
	local print = Box(
		parent,
		"MatLogo",
		Vector3.new(width * 0.3, 0.1, width * 0.06),
		cf * CFrame.new(-width * 0.26, 0.08, depth * 0.3),
		C.Violet
	)
	print.Transparency = 1
	RoomProps.Print(print, logo, C.Violet:Lerp(C.White, 0.2), Enum.NormalId.Top, Enum.Font.GothamBlack, 3)
	return mat
end

--[[
	Micro de stream sur bras articulé : socle lesté (solide), colonne, deux bras à ressorts,
	suspension antichoc, filtre anti-pop, câble XLR. `mic` = centre du micro, `aim` = vers la bouche.
]]
function RoomProps.MicArm(parent: Instance, base: Vector3, elbow: Vector3, mic: Vector3, aim: Vector3): Model
	local model = Build.Model("MicArm", parent)
	local arm = Color3.fromRGB(34, 34, 40)
	solidRod(model, "MicArmBase", CFrame.new(base + Vector3.new(0, 3, 0)) * VERTICAL, 6, 44, arm, METAL)
	local top = base + Vector3.new(0, 56, 0)
	post(model, "MicArmPost", base + Vector3.new(0, 6, 0), 50, 8, arm, METAL)
	Rod(model, "MicArmJoint", CFrame.new(top) * CFrame.Angles(0, math.pi / 2, 0), 12, 12, arm, METAL)
	local hang = mic + Vector3.new(0, 26, 0)
	for _, segment in { { top, elbow }, { elbow, hang } } do
		local a, b = segment[1], segment[2]
		local side = (b - a):Cross(UP).Unit * 3.2
		beam(model, "MicArmBar", a + side, b + side, 3.4, arm, METAL)
		beam(model, "MicArmBar", a - side, b - side, 3.4, arm, METAL)
		beam(
			model,
			"MicArmSpring",
			a + (b - a) * 0.2 + Vector3.new(0, 5, 0),
			a + (b - a) * 0.75 + Vector3.new(0, 5, 0),
			2,
			C.Nickel,
			METAL
		)
	end
	Rod(model, "MicArmJoint", CFrame.new(elbow) * CFrame.Angles(0, math.pi / 2, 0), 12, 12, arm, METAL)
	beam(model, "MicHanger", hang, mic + Vector3.new(0, 14, 0), 3, arm, METAL)
	-- Micro : corps, grille, suspension antichoc, filtre anti-pop
	local dir = (aim - mic).Unit
	local back, front = mic - dir * 34, mic + dir * 26
	Rod(model, "MicBody", Props.Along(back, front), (front - back).Magnitude, 26, Color3.fromRGB(28, 28, 34), METAL)
	local grille = Rod(
		model,
		"MicGrille",
		Props.Along(front - dir * 4, front + dir * 20),
		24,
		29,
		Color3.fromRGB(70, 72, 84),
		Enum.Material.DiamondPlate
	)
	grille.Reflectance = 0.1
	ball(model, "MicTip", 29, CFrame.new(front + dir * 20), Color3.fromRGB(70, 72, 84), Enum.Material.DiamondPlate)
	neon(model, "MicRing", Vector3.new(1.2, 27.4, 27.4), Props.Along(front - dir * 5, front - dir * 4), C.Violet, 0).Shape =
		Enum.PartType.Cylinder
	Props.Ring(model, "ShockMount", Props.Along(mic, mic + dir), 19, 2.4, 3, 12, arm, METAL)
	local popCenter = front + dir * 52
	local pop =
		Rod(model, "PopFilter", Props.Along(popCenter, popCenter + dir), 0.8, 46, Color3.fromRGB(20, 20, 26), FABRIC)
	pop.Transparency = 0.35
	Props.Ring(model, "PopFilterRing", Props.Along(popCenter, popCenter + dir), 23.5, 1.6, 1.6, 14, arm, METAL)
	beam(model, "PopGooseneck", mic + Vector3.new(0, 14, 0), popCenter + Vector3.new(0, 24, 0), 2, arm, METAL)
	return model
end

-- Casque gamer sur son support (socle solide, colonne, arceau, coussinets, anneaux RGB).
function RoomProps.HeadsetStand(parent: Instance, cf: CFrame): Model
	local model = Build.Model("HeadsetStand", parent)
	solidRod(model, "StandBase", cf * CFrame.new(0, 2, 0) * VERTICAL, 4, 60, INK, METAL)
	neon(model, "StandGlow", Vector3.new(0.6, 62, 62), cf * CFrame.new(0, 0.4, 0) * VERTICAL, C.Cyan, 0.2).Shape =
		Enum.PartType.Cylinder
	Rod(model, "StandPole", cf * CFrame.new(0, 76, 0) * VERTICAL, 144, 8, CHARCOAL, METAL)
	Box(model, "StandHanger", Vector3.new(50, 5, 12), cf * CFrame.new(0, 148, 0), INK, METAL)
	-- Arceau (arc de 9 segments dans le plan XY local), oreillettes
	local r, cy = 36, 114
	local count = 9
	for i = 0, count - 1 do
		local a0 = math.rad(-96 + 192 * i / count)
		local a1 = math.rad(-96 + 192 * (i + 1) / count)
		local p0 = Vector3.new(r * math.sin(a0), cy + r * math.cos(a0), 0)
		local p1 = Vector3.new(r * math.sin(a1), cy + r * math.cos(a1), 0)
		local seg = Box(model, "Headband", Vector3.new((p1 - p0).Magnitude + 1.5, 5, 12), CFrame.new(), INK)
		seg.CFrame = cf * CFrame.new((p0 + p1) / 2) * CFrame.Angles(0, 0, math.atan2(p1.Y - p0.Y, p1.X - p0.X))
	end
	for _, side in { -1, 1 } do
		local cup = cf * CFrame.new(side * (r + 6), cy - 14, 0)
		Rod(model, "EarCup", cup, 14, 42, INK, SMOOTH)
		Rod(model, "EarCushion", cup * CFrame.new(-side * 8.5, 0, 0), 5, 36, Color3.fromRGB(22, 22, 28), FABRIC)
		neon(model, "EarRgb", Vector3.new(1.2, 44, 44), cup * CFrame.new(side * 7.2, 0, 0), C.Violet, 0.05).Shape =
			Enum.PartType.Cylinder
		Rod(model, "EarLogo", cup * CFrame.new(side * 7.8, 0, 0), 0.6, 26, C.Brand, SMOOTH)
	end
	beam(
		model,
		"HeadsetMic",
		(cf * CFrame.new(-(r + 12), cy - 20, -4)).Position,
		(cf * CFrame.new(-(r + 8), cy - 44, -34)).Position,
		3,
		INK
	)
	return model
end

-- Stream Deck (pavé de raccourcis du streamer) : socle bas solide (on monte dessus), 15 touches LCD
-- lumineuses. `cf` : centre du dessous, LookVector = vers le joueur qui l'utilise.
function RoomProps.StreamDeck(parent: Instance, cf: CFrame): Model
	local model = Build.Model("StreamDeck", parent)
	solid(model, "StreamDeckBody", Vector3.new(76, 5, 52), cf * CFrame.new(0, 2.5, 0), INK, METAL)
	Box(model, "StreamDeckStand", Vector3.new(60, 3, 30), cf * CFrame.new(0, 1, 14), CHARCOAL, METAL)
	local colors = { C.Violet, C.Cyan, Color3.fromRGB(246, 196, 83), Color3.fromRGB(104, 224, 140), APP_ACCENT }
	for row = 0, 2 do
		for col = 0, 4 do
			local color = colors[(row * 2 + col) % #colors + 1]
			neon(
				model,
				"StreamDeckKey",
				Vector3.new(11, 1, 11),
				cf * CFrame.new(-28 + col * 14, 5.4, -14 + row * 14),
				color,
				0.15
			)
		end
	end
	return model
end

------------------------------------------------------------------------------------
-- Chambre
------------------------------------------------------------------------------------

--[[
	Chaise gamer (hors du bureau, derrière le spawn) : piétement étoile, vérin, assise, dossier baquet
	incliné avec coussins « AngaTV », accoudoirs. `cf` = centre au sol, LookVector = vers le bureau.
]]
function RoomProps.Chair(parent: Instance, cf: CFrame): Model
	local model = Build.Model("GamingChair", parent)
	local shell = Color3.fromRGB(28, 28, 34)
	local accent = APP_ACCENT
	for k = 0, 4 do
		local legCf = cf * CFrame.Angles(0, k * math.pi * 2 / 5, 0) * CFrame.new(0, 44, -150)
		Box(model, "ChairLeg", Vector3.new(44, 26, 300), legCf, shell, METAL)
		Rod(model, "ChairCaster", legCf * CFrame.new(0, -24, -140), 30, 40, INK)
	end
	Rod(model, "ChairLift", cf * CFrame.new(0, 250, 0) * VERTICAL, 420, 52, C.Nickel, METAL)
	Rod(model, "ChairLiftCover", cf * CFrame.new(0, 150, 0) * VERTICAL, 200, 80, shell, SMOOTH)
	Box(model, "ChairSeatBase", Vector3.new(420, 40, 420), cf * CFrame.new(0, 490, 0), shell, METAL)
	Box(model, "ChairSeat", Vector3.new(560, 90, 540), cf * CFrame.new(0, 555, 0), shell, FABRIC)
	for _, side in { -1, 1 } do
		Box(model, "ChairSeatBolster", Vector3.new(80, 130, 540), cf * CFrame.new(side * 290, 575, 0), shell, FABRIC)
		Box(model, "ChairSeatStripe", Vector3.new(44, 2, 500), cf * CFrame.new(side * 140, 601, 0), accent, FABRIC)
		-- Accoudoirs
		Box(model, "ChairArmPost", Vector3.new(44, 200, 64), cf * CFrame.new(side * 350, 620, 60), shell, METAL)
		Box(
			model,
			"ChairArmPad",
			Vector3.new(80, 24, 280),
			cf * CFrame.new(side * 350, 730, 20),
			shell,
			Enum.Material.Rubber
		)
	end
	-- Dossier incliné vers l'arrière (+Z local)
	local back = cf * CFrame.new(0, 600, 270) * CFrame.Angles(math.rad(10), 0, 0)
	Box(model, "ChairBack", Vector3.new(520, 900, 110), back * CFrame.new(0, 450, 55), shell, FABRIC)
	for _, side in { -1, 1 } do
		Box(
			model,
			"ChairWing",
			Vector3.new(90, 640, 150),
			back * CFrame.new(side * 290, 330, 30) * CFrame.Angles(0, -side * math.rad(14), 0),
			shell,
			FABRIC
		)
		Box(model, "ChairShoulder", Vector3.new(96, 200, 120), back * CFrame.new(side * 250, 790, 45), shell, FABRIC)
		Box(model, "ChairBackStripe", Vector3.new(60, 700, 4), back * CFrame.new(side * 150, 430, -2), accent, FABRIC)
	end
	local pillow = Box(model, "ChairPillow", Vector3.new(300, 150, 60), back * CFrame.new(0, 760, -30), accent, FABRIC)
	RoomProps.Print(pillow, "AngaTV", C.White, Enum.NormalId.Front, Enum.Font.GothamBlack, 1)
	Box(model, "ChairLumbar", Vector3.new(340, 160, 60), back * CFrame.new(0, 180, -30), shell, FABRIC)
	return model
end

export type PosterDesign = {
	Top: Color3, -- dégradé de fond (haut -> bas)
	Bottom: Color3,
	Glyph: string?, -- gros symbole central
	GlyphColor: Color3?,
	Title: string,
	TitleColor: Color3,
	Subtitle: string?,
}

-- Poster encadré sur un mur : `cf` = centre, LookVector = vers la pièce.
function RoomProps.Poster(parent: Instance, cf: CFrame, width: number, height: number, design: PosterDesign): Part
	Box(
		parent,
		"PosterFrame",
		Vector3.new(width + 16, height + 16, 3),
		cf * CFrame.new(0, 0, 1.5),
		Color3.fromRGB(22, 22, 26)
	)
	local panel = Box(parent, "Poster", Vector3.new(width, height, 1), cf * CFrame.new(0, 0, -0.6), design.Bottom)
	local gui = surface(panel, Enum.NormalId.Front, 700 / width, 0.35)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.White
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(design.Top, design.Bottom)
	gradient.Rotation = 90
	gradient.Parent = bg
	if design.Glyph then
		textLabel(
			bg,
			design.Glyph,
			design.GlyphColor or C.White,
			Enum.Font.GothamBlack,
			UDim2.fromScale(0.1, 0.06),
			UDim2.fromScale(0.8, 0.5)
		)
	end
	local titleY = if design.Glyph then 0.58 else 0.2
	textLabel(
		bg,
		design.Title,
		design.TitleColor,
		Enum.Font.GothamBlack,
		UDim2.fromScale(0.06, titleY),
		UDim2.fromScale(0.88, 0.2)
	)
	if design.Subtitle then
		textLabel(
			bg,
			design.Subtitle,
			C.White,
			Enum.Font.GothamBold,
			UDim2.fromScale(0.08, titleY + 0.22),
			UDim2.fromScale(0.84, 0.12)
		)
	end
	return panel
end

-- Fenêtre au coucher de soleil : ciel en dégradé autoéclairé, soleil, silhouettes d'immeubles,
-- cadre, croisillons, appui, rideaux. `cf` = centre sur le mur, LookVector = vers la pièce.
function RoomProps.Window(parent: Instance, cf: CFrame, width: number, height: number): Model
	local model = Build.Model("Window", parent)
	local frameColor = Color3.fromRGB(236, 232, 226)
	local sky = Box(
		model,
		"WindowSky",
		Vector3.new(width, height, 2),
		cf * CFrame.new(0, 0, 6),
		Color3.fromRGB(255, 150, 110),
		NEON
	)
	local gui = surface(sky, Enum.NormalId.Front, 400 / width, 0)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.White
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(96, 70, 170), Color3.fromRGB(255, 150, 90))
	gradient.Rotation = 90
	gradient.Parent = bg
	-- Soleil bas sur l'horizon, immeubles en ombre chinoise
	local sun = ball(
		model,
		"WindowSun",
		height * 0.28,
		cf * CFrame.new(width * 0.18, -height * 0.18, 4.5),
		Color3.fromRGB(255, 196, 120),
		NEON
	)
	sun.Transparency = 0.05
	local skyline = {
		{ -0.42, 0.2, 0.3 },
		{ -0.25, 0.14, 0.42 },
		{ -0.1, 0.12, 0.24 },
		{ 0.05, 0.16, 0.36 },
		{ 0.24, 0.12, 0.2 },
		{ 0.38, 0.18, 0.3 },
	}
	for _, b in skyline do
		local w, h = width * b[2], height * b[3]
		Box(
			model,
			"Skyline",
			Vector3.new(w, h, 1),
			cf * CFrame.new(width * b[1], -height / 2 + h / 2, 3.5),
			Color3.fromRGB(58, 40, 86)
		)
	end
	-- Cadre, croisillons, appui
	local t = 24
	for _, bar in
		{
			{ 0, height / 2 + t / 2, width + 2 * t, t },
			{ 0, -height / 2 - t / 2, width + 2 * t, t },
			{ width / 2 + t / 2, 0, t, height },
			{ -width / 2 - t / 2, 0, t, height },
			{ 0, 0, 14, height },
			{ 0, height * 0.12, width, 14 },
		}
	do
		Box(model, "WindowFrame", Vector3.new(bar[3], bar[4], 16), cf * CFrame.new(bar[1], bar[2], 0), frameColor)
	end
	Box(model, "WindowSill", Vector3.new(width + 80, 16, 60), cf * CFrame.new(0, -height / 2 - t - 8, -20), frameColor)
	-- Rideaux et tringle
	for _, side in { -1, 1 } do
		Box(
			model,
			"Curtain",
			Vector3.new(width * 0.24, height + 200, 20),
			cf * CFrame.new(side * (width / 2 + width * 0.1), -40, -30),
			Color3.fromRGB(92, 58, 150),
			FABRIC
		)
	end
	Rod(model, "CurtainRod", cf * CFrame.new(0, height / 2 + 80, -30), width * 1.7, 12, C.Nickel, METAL)
	return model
end

-- Carré de mousse acoustique (3 × 3 dalles en relief). `cf` = centre sur le mur, LookVector = pièce.
function RoomProps.AcousticFoam(parent: Instance, cf: CFrame, tile: number, color: Color3): Model
	local model = Build.Model("AcousticFoam", parent)
	for i = -1, 1 do
		for j = -1, 1 do
			local deep = (i + j) % 2 == 0
			Box(
				model,
				"FoamTile",
				Vector3.new(tile - 6, tile - 6, if deep then 22 else 14),
				cf * CFrame.new(i * tile, j * tile, if deep then -11 else -7),
				if deep then color else color:Lerp(Color3.new(0, 0, 0), 0.25),
				FABRIC
			)
		end
	end
	return model
end

-- Enseigne néon (texte lumineux sur une plaque transparente + contour néon).
function RoomProps.NeonSign(
	parent: Instance,
	cf: CFrame,
	width: number,
	height: number,
	text: string,
	color: Color3
): Model
	local model = Build.Model("NeonSign", parent)
	local plate =
		Box(model, "NeonSignPlate", Vector3.new(width, height, 1), cf * CFrame.new(0, 0, 4), Color3.fromRGB(20, 20, 26))
	plate.Transparency = 0.4
	local gui = surface(plate, Enum.NormalId.Front, 500 / width, 0)
	gui.Brightness = 2.5
	local label =
		textLabel(gui, text, color, Enum.Font.GothamBlack, UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8))
	label.TextStrokeColor3 = color:Lerp(C.White, 0.6)
	label.TextStrokeTransparency = 0.3
	for _, bar in
		{
			{ 0, height / 2, width, 6 },
			{ 0, -height / 2, width, 6 },
			{ width / 2, 0, 6, height },
			{ -width / 2, 0, 6, height },
		}
	do
		neon(model, "NeonSignTube", Vector3.new(bar[3], bar[4], 4), cf * CFrame.new(bar[1], bar[2], 0), color, 0.05)
	end
	return model
end

------------------------------------------------------------------------------------
-- Coque de la tour
------------------------------------------------------------------------------------

--[[
	Ventilateur de boîtier fin (derrière une façade mesh) : cadre carré, moyeu tournant (TrapSpin)
	avec 7 pales soudées, anneau RGB. `cf` : centre du plan arrière, RightVector = axe vers l'extérieur.
]]
function RoomProps.CaseFan(parent: Instance, cf: CFrame, diameter: number, glow: Color3, speed: number): Model
	local model = Build.Model("CaseFan", parent)
	local r = diameter / 2
	local depth = 4
	local bar = r * 0.1
	for k = 0, 3 do
		local rot = cf * CFrame.Angles(k * math.pi / 2, 0, 0)
		Box(model, "FanFrame", Vector3.new(depth, bar, 2 * (r + bar)), rot * CFrame.new(depth / 2, r + bar / 2, 0), INK)
	end
	local hubCf = cf * CFrame.new(depth * 0.6, 0, 0)
	local hub = Build.Decor({
		Name = "SpinHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(depth * 0.8, r * 0.64, r * 0.64),
		CFrame = hubCf,
		Color = CHARCOAL,
		Material = SMOOTH,
		CastShadow = false,
		Tags = { "TrapSpin" },
		Parent = model,
	})
	hub:SetAttribute("Axis", "X")
	hub:SetAttribute("Speed", speed)
	local blades = 7
	for i = 0, blades - 1 do
		local blade = Build.Decor({
			Name = "Blade",
			Size = Vector3.new(0.5, r * 0.62, r * 0.42),
			CFrame = hubCf
				* CFrame.Angles(i * math.pi * 2 / blades, 0, 0)
				* CFrame.new(0, r * 0.6, 0)
				* CFrame.Angles(math.rad(12), math.rad(28), 0),
			Color = INK:Lerp(glow, 0.2),
			Material = SMOOTH,
			CastShadow = false,
			Transparency = 0.1,
			Parent = hub,
		})
		Props.WeldTo(hub, blade)
	end
	local ring =
		Props.Ring(model, "FanRgb", cf * CFrame.new(depth - 0.2, 0, 0), r * 0.97, r * 0.07, 0.6, 14, glow, NEON)
	for _, segment in ring do
		segment:AddTag("RgbStrip")
	end
	return model
end

-- Vis moletée : `cf` = centre sur la surface, RightVector = normale vers l'extérieur.
function RoomProps.Thumbscrew(parent: Instance, cf: CFrame, diameter: number)
	Rod(parent, "ScrewCollar", cf * CFrame.new(0.4, 0, 0), 0.8, diameter * 1.25, CHARCOAL, METAL)
	Rod(parent, "ScrewHead", cf * CFrame.new(2.2, 0, 0), 3, diameter, C.Nickel, Enum.Material.DiamondPlate)
	Box(parent, "ScrewSlot", Vector3.new(0.3, diameter * 0.7, 0.8), cf * CFrame.new(3.75, 0, 0), CHARCOAL)
end

return RoomProps
