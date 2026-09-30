--!strict
--[[
	Props : éléments de décor et de gameplay réutilisables pour construire le PC géant.
	- Gameplay : machines (modules), terminaux, pads (collecteur, téléporteur)
	- Décor PC : ventilateurs 120 mm, anneaux RGB, grilles, blocs d'ailettes, câbles gainés,
	  tubes rigides de watercooling, condensateurs, texte sérigraphié
	Tags lus par le client : TierGlow (couleur du tier), Spin (hélice de machine),
	DecorSpin (ventilateur de décor), RgbStrip, PulseGlow, TerminalScreen.

	Convention : les petits détails sont du décor pur (Props.Box / Rod / Wedge : ni collision,
	ni requêtes, ni ombre) ; seuls les volumes principaux sont solides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Modules = require(Shared.Config.Modules)
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
		Material = material or Enum.Material.Metal,
		CastShadow = false,
		Parent = parent,
	})
end

-- Repère dont l'axe X local va de `a` vers `b` (pour les cylindres).
function Props.Along(a: Vector3, b: Vector3): CFrame
	-- Segment vertical : lookAt dégénéré avec l'axe Y comme "haut", on prend X.
	local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
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

-- Soude une pièce (libérée) à un moyeu ancré qui tourne côté client (tags Spin / DecorSpin).
local function weldTo(hub: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hub
	weld.Part1 = part
	weld.Parent = part
	part.Anchored = false
end
Props.WeldTo = weldTo

------------------------------------------------------------------------------------
-- Ventilateur 120 mm
------------------------------------------------------------------------------------

type BladeSection = { From: number, To: number, Pitch: number, Sweep: number, Chord: number }

export type FanOptions = {
	Tag: string?, -- tag du moyeu : "DecorSpin" (défaut) ou "Spin" (machine)
	Light: boolean?, -- PointLight au centre (compte dans le budget de lumières)
	Rgb: boolean?, -- anneau recoloré en arc-en-ciel par le client (RgbStrip)
	RingTag: string?, -- tag des segments de l'anneau (ex. TierGlow sur une machine)
	Brand: string?, -- texte de l'autocollant du moyeu
	Frame: Color3?,
}

--[[
	Ventilateur de boîtier stylisé : cadre carré à coins arrondis (4 trous de vis et patins
	en caoutchouc), goussets triangulaires autour de l'ouverture, stator à 4 bras, moyeu
	avec autocollant, pales vrillées en 2 parties, anneau LED sur la face avant.
	`cf` : centre de la face ARRIÈRE (plan de fixation) ; RightVector = axe, vers l'avant.
	Le moyeu (tag DecorSpin + Axis) tourne côté client ; les pales y sont soudées.
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
	local lite = diameter < 24 -- petits ventilateurs (machines) : moins de pièces
	local half = r * 1.08 -- demi-côté du cadre
	local inner = r * 1.01 -- bord intérieur des traverses (tangent à l'ouverture)
	local bar = half - inner
	local corner = r * 0.16 -- rayon des coins arrondis
	local depth = math.clamp(diameter * 0.14, 1.6, 14)
	local frameColor = opts.Frame or C.Black
	local mid = depth / 2

	-- Cadre : 4 traverses + coins arrondis + goussets
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
			-- Patin anti-vibration + trou de vis (face avant)
			Props.Rod(
				model,
				"RubberPad",
				rot * CFrame.new(depth + 0.1, c, c),
				0.3,
				corner * 1.7,
				C.Rubber:Lerp(glowColor, 0.08),
				Enum.Material.SmoothPlastic
			)
			Props.Rod(model, "ScrewHole", rot * CFrame.new(depth + 0.2, c, c), 0.3, corner * 0.8, C.Bg)
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
		Material = Enum.Material.Metal,
		CastShadow = false,
		Tags = { opts.Tag or "DecorSpin" },
		Parent = model,
	})
	hub:SetAttribute("Axis", "X")
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
	local bladeColor = C.Black:Lerp(glowColor, 0.14)
	local thickness = 0.25 + r * 0.008
	-- Pale vrillée : emplanture étroite et très inclinée, puis sections de plus en plus larges,
	-- moins inclinées et balayées vers l'arrière (effet de pale courbe). 2 sections si petit.
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
	for _, segment in ring do
		if opts.Rgb then
			segment:AddTag("RgbStrip")
		end
		if opts.RingTag then
			segment:AddTag(opts.RingTag)
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
	solid: boolean?
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
				local bar = Props.Box(
					model,
					"GrilleBar",
					Vector3.new(barWidth * 0.8, barWidth, chord),
					rot * CFrame.new(0, y, 0),
					color,
					Enum.Material.Metal
				)
				if solid then
					bar.CanCollide = true
				end
			end
			k += 1
		end
	end
	Props.Ring(model, "GrilleRim", cf, radius, barWidth * 2.2, barWidth * 1.4, 24, color, Enum.Material.Metal)
	return model
end

------------------------------------------------------------------------------------
-- Machines (modules améliorables)
------------------------------------------------------------------------------------

function Props.Glow(props: Build.Props): Part
	local part = Build.Neon(props)
	part.Transparency = 0.05
	local tags = { "TierGlow" }
	for _, tag in (props.Tags or {}) :: { string } do
		table.insert(tags, tag)
	end
	part:SetAttribute("GlowStrength", 1)
	for _, tag in tags do
		part:AddTag(tag)
	end
	return part
end

-- Machine de zone : socle (prompt "Améliorer") + composant miniature propre à la zone.
-- Repère `cf` au sol ; la face avant (-Z local) regarde le portail. Taille selon le slot.
function Props.Machine(def: Modules.ModuleDef, cf: CFrame, parent: Instance, primary: Color3, secondary: Color3): Model
	local model = Build.Model(def.Id, parent)
	model:SetAttribute("ModuleId", def.Id)
	model:SetAttribute("Level", 0)
	local slot = def.Slot
	local scale = 0.8 + slot * 0.2

	-- Utilitaires locaux (coordonnées relatives au socle)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function solid(name: string, size: Vector3, where: CFrame, color: Color3, material: Enum.Material?): Part
		return Build.Part({
			Name = name,
			Size = size,
			CFrame = where,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	local function glow(name: string, size: Vector3, where: CFrame, shape: Enum.PartType?): Part
		return Props.Glow({
			Name = name,
			Shape = shape or Enum.PartType.Block,
			Size = size,
			CFrame = where,
			Color = primary,
			Parent = model,
		})
	end

	-- Socle : plaque striée + jupe biseautée + liseré de tier + plaque signalétique
	local base = Build.Part({
		Name = "Base",
		Size = Vector3.new(14, 2, 14),
		CFrame = at(0, 1, 0),
		Color = C.MetalDark,
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	model.PrimaryPart = base
	Props.Glow({
		Name = "BaseGlow",
		Size = Vector3.new(14.2, 0.3, 14.2),
		CFrame = at(0, 2.1, 0),
		Color = primary,
		Transparency = 0.5,
		Parent = model,
	})
	for k = 0, 3 do
		Props.Wedge(
			model,
			"BaseBevel",
			Vector3.new(14, 1.4, 1.4),
			cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0.7, -7.7),
			C.MetalLight,
			Enum.Material.Metal
		)
	end
	for _, x in { -6, 6 } do
		for _, z in { -6, 6 } do
			Props.Rod(model, "Bolt", at(x, 2.3, z) * CFrame.Angles(0, 0, math.pi / 2), 0.3, 0.9, C.Nickel)
		end
	end
	-- Plaque signalétique posée sur le biseau avant (pente à 45°)
	local plate = Props.Box(
		model,
		"Nameplate",
		Vector3.new(7, 1.3, 0.1),
		at(0, 0.74, -7.74) * CFrame.Angles(math.rad(45), 0, 0),
		C.Black
	)
	Props.Label(plate, string.upper(def.Name), primary, Enum.NormalId.Front, Enum.Font.GothamBold)

	local top = 2
	local zone = def.Zone
	if zone == 1 then
		-- Condensateur géant (+ petits condensateurs, puis bobine torique au slot 3)
		local height = 10 * scale
		solid("Plinth", Vector3.new(11, 1, 11), at(0, top + 0.5, 0), C.Pcb)
		top += 1
		Build.Cylinder({
			Name = "Body",
			Size = Vector3.new(height, 8, 8),
			CFrame = at(0, top + height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = C.MetalDark:Lerp(primary, 0.2),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		Props.Rod(model, "Seal", at(0, top + 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), 0.6, 8.3, C.Rubber)
		Props.Rod(model, "Can", at(0, top + height + 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), 0.4, 7.6, C.Aluminum)
		for _, angle in { math.pi / 4, -math.pi / 4 } do
			Props.Box(
				model,
				"Vent",
				Vector3.new(6, 0.2, 0.5),
				at(0, top + height + 0.35, 0) * CFrame.Angles(0, angle, 0),
				C.Bg
			)
		end
		Props.Box(
			model,
			"Stripe",
			Vector3.new(2.2, height * 0.8, 0.2),
			at(0, top + height * 0.5, -4.02),
			C.Aluminum:Lerp(primary, 0.25)
		)
		for ring = 1, 2 do
			glow(
				"Ring",
				Vector3.new(0.5, 8.4, 8.4),
				at(0, top + height * ring / 3, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Enum.PartType.Cylinder
			)
		end
		if slot >= 2 then
			for _, x in { -5, 5 } do
				local h = 4 + slot
				solid(
					"SmallCap",
					Vector3.new(h, 3, 3),
					at(x, top + h / 2, 3.5) * CFrame.Angles(0, 0, math.pi / 2),
					C.Black
				)
				Props.Rod(
					model,
					"SmallCapTop",
					at(x, top + h + 0.1, 3.5) * CFrame.Angles(0, 0, math.pi / 2),
					0.2,
					2.8,
					C.Aluminum
				)
				Props.Box(model, "SmallCapStripe", Vector3.new(0.8, h * 0.8, 0.2), at(x, top + h / 2, 1.97), secondary)
			end
		end
		if slot >= 3 then
			-- Bobine torique : anneau de cuivre autour d'un noyau, arc électrique
			local coil = at(-4.3, top + 3, -4.4) * CFrame.Angles(0, math.pi / 2, 0)
			Props.Ring(model, "Coil", coil, 2, 1.2, 1.4, 10, C.Copper, Enum.Material.Metal)
			Props.Rod(model, "Core", coil, 1, 2.8, C.Black)
			for k = 0, 2 do
				glow(
					"Arc",
					Vector3.new(0.25, 0.25, 1.6),
					at(-2.6 + k * 0.9, top + 3.8 + (k % 2) * 0.8, -4.3)
						* CFrame.Angles(0, math.rad(60), math.rad(35 - k * 50))
				)
			end
		end
		top += height
	elseif zone == 2 then
		-- Kit de barrettes (2, 3 puis 4) vues de face : dissipateur sculpté + barre RGB
		local height = 11 * scale
		local count = slot + 1
		for i = 1, count do
			local z = (i - (count + 1) / 2) * 3
			solid("DimmSlot", Vector3.new(12, 1.6, 1.8), at(0, top + 0.8, z), C.Black)
			for _, x in { -6.3, 6.3 } do
				Props.Box(model, "Latch", Vector3.new(0.8, 2.4, 1.4), at(x, top + 1.2, z), C.White)
			end
			local y0 = top + 1.2
			Props.Box(model, "Pcb", Vector3.new(11, height, 0.4), at(0, y0 + height / 2, z), C.PcbDark)
			Props.Box(model, "Fingers", Vector3.new(10.4, 0.6, 0.5), at(0, top + 1.9, z), C.Gold, Enum.Material.Foil)
			for c = -1, 1 do
				for _, side in { -1, 1 } do
					Props.Box(model, "Chip", Vector3.new(2.4, 1.3, 0.2), at(c * 3.3, top + 3.4, z + side * 0.3), C.Bg)
				end
			end
			local spreaderH = height - 3.2
			local spreader = solid(
				"Stick",
				Vector3.new(11, spreaderH, 1.2),
				at(0, top + 4.6 + spreaderH / 2, z),
				if i % 2 == 0 then C.MetalDark else C.Aluminum:Lerp(C.MetalDark, 0.35),
				Enum.Material.Metal
			)
			-- Crête sculptée au sommet (ailettes d'inégales hauteurs)
			for f = -2, 2 do
				local h = 0.6 + ((f + 3) % 3) * 0.35
				Props.Box(
					model,
					"Crest",
					Vector3.new(1.6, h, 1.3),
					at(f * 2.1, top + 4.6 + spreaderH + h / 2, z),
					C.MetalDark:Lerp(primary, 0.15),
					Enum.Material.Metal
				)
			end
			glow("StickGlow", Vector3.new(11, 0.5, 1.3), at(0, top + 4.6 + spreaderH + 0.25, z))
			Build.Neon({
				Name = "Diagonal",
				Size = Vector3.new(0.5, spreaderH * 1.05, 0.15),
				CFrame = at(1.8, top + 4.6 + spreaderH / 2, z - 0.65) * CFrame.Angles(0, 0, math.rad(-38)),
				Color = secondary,
				Transparency = 0.2,
				Parent = model,
			})
			if i == 1 then
				Props.Label(spreader, "KRYO", primary, Enum.NormalId.Front, Enum.Font.GothamBlack)
			end
		end
		top += height + 2.8
	elseif zone == 3 then
		-- SSD NVMe M.2 empilés sur entretoises (1, 2 puis 3 = RAID) + fond de panier lumineux
		local levels = slot
		local pitch = 3.2
		local backH = levels * pitch + 3
		solid("Backplane", Vector3.new(13, backH, 0.8), at(0, top + backH / 2, 5.6), C.PcbDark)
		for k = 1, 3 do
			glow("DataLine", Vector3.new(0.3, backH - 1, 0.2), at(-4 + k * 2, top + backH / 2, 5.15))
		end
		for level = 1, levels do
			local y = top + level * pitch - 0.8
			for _, x in { -5.5, 5.5 } do
				for _, zz in { -2.3, 2.3 } do
					Props.Rod(
						model,
						"Standoff",
						at(x, y - pitch / 2 + 0.2, zz) * CFrame.Angles(0, 0, math.pi / 2),
						pitch - 0.4,
						0.6,
						C.Nickel
					)
				end
			end
			solid("Pcb", Vector3.new(12.4, 0.4, 5.6), at(0, y, 0), C.Pcb:Lerp(primary, 0.12))
			Props.Box(model, "Fingers", Vector3.new(1, 0.45, 4.6), at(-6, y, 0.3), C.Gold, Enum.Material.Foil)
			Props.Rod(model, "Screw", at(5.9, y + 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), 0.3, 1.2, C.Nickel)
			Props.Box(model, "Controller", Vector3.new(2, 0.4, 2), at(-3.8, y + 0.4, 0), C.Bg)
			local sink = Props.Box(
				model,
				"Heatsink",
				Vector3.new(7.4, 0.9, 5),
				at(1.2, y + 0.65, 0),
				C.Aluminum:Lerp(C.MetalDark, 0.3),
				Enum.Material.Metal
			)
			Props.Label(sink, "NOVA", primary, Enum.NormalId.Front, Enum.Font.GothamBlack)
			for f = -2, 2 do
				Props.Box(
					model,
					"Rib",
					Vector3.new(0.35, 0.4, 5),
					at(1.2 + f * 1.4, y + 1.3, 0),
					C.MetalDark,
					Enum.Material.Metal
				)
			end
			glow("NandGlow", Vector3.new(7.4, 0.25, 0.3), at(1.2, y + 0.65, -2.6))
		end
		top += levels * pitch + 1
	elseif zone == 4 then
		-- Ventilateur géant sur pied ; slot 2 : radiateur derrière ; slot 3 : push-pull
		local diameter = 10 * scale
		local centerY = top + diameter / 2 + 1.6
		for _, x in { -5.4, 5.4 } do
			solid("Foot", Vector3.new(1.4, 1, 6), at(x, top + 0.5, 0.5), C.MetalDark, Enum.Material.Metal)
			Props.Box(
				model,
				"Upright",
				Vector3.new(0.8, centerY - top, 0.8),
				at(x, (top + centerY) / 2, 1.5),
				C.MetalLight,
				Enum.Material.Metal
			)
		end
		glow("StandGlow", Vector3.new(11.6, 0.3, 0.3), at(0, top + 1.1, -2.4))
		-- Face avant (-Z local) vers le portail : axe du ventilateur = -Z
		Props.Fan(model, at(0, centerY, 0.6) * CFrame.Angles(0, math.pi / 2, 0), diameter, primary, 7, {
			Tag = "Spin",
			RingTag = "TierGlow",
		})
		if slot >= 2 then
			-- Radiateur : lames verticales empilées le long de X
			Props.Fins(
				model,
				at(0, centerY, 2.2) * CFrame.Angles(0, math.pi / 2, 0),
				3.2,
				diameter * 1.05,
				diameter * 1.05,
				12,
				C.Aluminum,
				true
			)
			for _, y in { -1, 1 } do
				Props.Box(
					model,
					"Tank",
					Vector3.new(diameter * 1.1, 1, 3.6),
					at(0, centerY + y * (diameter * 0.55 + 0.5), 2.2),
					C.Black,
					Enum.Material.Metal
				)
			end
		end
		if slot >= 3 then
			Props.Fan(model, at(0, centerY, 3.8) * CFrame.Angles(0, -math.pi / 2, 0), diameter, primary, 7, {
				Tag = "Spin",
			})
		end
		top = centerY + diameter / 2 + 1
	elseif zone == 5 then
		-- Processeur dans son socket : levier, substrat, IHS gravé, grille de cœurs (2x2 -> 4x4)
		local height = 2.2 * scale
		solid("Socket", Vector3.new(13, 1.2, 13), at(0, top + 0.6, 0), C.Black)
		for k = 0, 3 do
			Props.Box(
				model,
				"LoadPlate",
				Vector3.new(12.6, 0.4, 1),
				cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, top + 1.4, -5.8),
				C.Aluminum,
				Enum.Material.Metal
			)
		end
		Props.Rod(model, "Lever", at(6.9, top + 1.2, 0) * CFrame.Angles(0, math.pi / 2, 0), 12, 0.5, C.Nickel)
		Props.Box(
			model,
			"LeverHook",
			Vector3.new(0.5, 0.5, 2),
			at(6.9, top + 1.2, -6.5) * CFrame.Angles(0, math.rad(90), 0),
			C.Nickel,
			Enum.Material.Metal
		)
		top += 1.2
		solid("Substrate", Vector3.new(11, 0.6, 11), at(0, top + 0.3, 0), C.Pcb:Lerp(C.Gold, 0.08))
		for _, x in { -4.6, 4.6 } do
			for zz = -1, 1 do
				Props.Box(
					model,
					"Smd",
					Vector3.new(0.5, 0.3, 1),
					at(x, top + 0.75, zz * 1.6),
					C.Copper,
					Enum.Material.Metal
				)
			end
		end
		top += 0.6
		local die = solid(
			"Die",
			Vector3.new(9, height, 9),
			at(0, top + height / 2, 0),
			C.MetalLight:Lerp(C.Nickel, 0.5),
			Enum.Material.Metal
		)
		die.Reflectance = 0.08
		Props.Label(die, "HELION", primary, Enum.NormalId.Front, Enum.Font.GothamBlack)
		top += height
		local n = slot + 1
		local cell = 6.4 / n
		for ix = 1, n do
			for iz = 1, n do
				glow(
					"Core",
					Vector3.new(cell * 0.72, 0.3, cell * 0.72),
					at((ix - (n + 1) / 2) * cell, top + 0.15, (iz - (n + 1) / 2) * cell)
				)
			end
		end
		Props.Box(model, "Ihs", Vector3.new(8, 0.15, 8), at(0, top + 0.06, 0), C.Gold, Enum.Material.Foil)
		top += 1
	elseif zone == 6 then
		-- Carte graphique debout, face au portail : 1 à 3 ventilateurs, carénage à facettes
		local length, height, thick = 13, 7, 2.6
		solid("PcieSlot", Vector3.new(11, 1.4, 1.6), at(-0.5, top + 0.7, 0.6), C.Black)
		Props.Box(model, "Fingers", Vector3.new(9, 0.6, 0.5), at(-0.5, top + 1.6, 0.6), C.Gold, Enum.Material.Foil)
		local y0 = top + 1.8
		local cy = y0 + height / 2
		solid("Shroud", Vector3.new(length, height, thick), at(0, cy, -0.2), C.MetalDark, Enum.Material.Metal)
		Props.Box(
			model,
			"Backplate",
			Vector3.new(length - 0.4, height - 0.4, 0.3),
			at(0, cy, 1.25),
			C.Black,
			Enum.Material.Metal
		)
		for _, side in { -1, 1 } do
			Props.Wedge(
				model,
				"Facet",
				Vector3.new(thick, height, 1.6),
				at(side * (length / 2 + 0.8), cy, -0.2) * CFrame.Angles(0, -side * math.pi / 2, 0),
				C.MetalLight,
				Enum.Material.Metal
			)
		end
		Props.Box(
			model,
			"Bracket",
			Vector3.new(0.3, height + 1.6, thick + 0.4),
			at(length / 2 + 1.75, cy + 0.4, -0.2),
			C.Aluminum,
			Enum.Material.Metal
		)
		for k = 0, 2 do
			Props.Box(model, "Port", Vector3.new(0.35, 0.8, 1.4), at(length / 2 + 1.8, y0 + 1 + k * 1.3, -0.2), C.Bg)
		end
		local count = slot
		local spacing = (length - 1) / 3
		for k = 1, count do
			local x = (k - (count + 1) / 2) * spacing
			Props.Fan(model, at(x, cy, -1.4) * CFrame.Angles(0, math.pi / 2, 0), 3.6, primary, 9, { Tag = "Spin" })
		end
		Props.Box(
			model,
			"ArmorTop",
			Vector3.new(length, 0.5, 0.4),
			at(0, y0 + height - 0.4, -1.55),
			C.Aluminum,
			Enum.Material.Metal
		)
		local logo = glow("ShroudGlow", Vector3.new(length - 1, 0.4, 0.4), at(0, y0 + height + 0.2, -0.2))
		logo.Transparency = 0.1
		local brand = Props.Box(
			model,
			"Logo",
			Vector3.new(6, 0.1, 1.8),
			at(-2, y0 + height + 0.45, -0.2),
			secondary,
			Enum.Material.Neon
		)
		brand.Transparency = 0.3
		Props.Label(brand, "PRISM", C.White, Enum.NormalId.Top, Enum.Font.GothamBlack)
		top = y0 + height + 1
	else
		-- Orbe neuronal : piédestal biseauté, puce NPU, orbe + anneau en rotation et satellites
		local radius = 2.2 + scale * 1.3
		local plinthH = 4
		solid("Pedestal", Vector3.new(6, plinthH, 6), at(0, top + plinthH / 2, 0), C.MetalLight, Enum.Material.Metal)
		for k = 0, 3 do
			Props.Wedge(
				model,
				"Chamfer",
				Vector3.new(6, 1.2, 1.2),
				cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, top + plinthH + 0.6, -2.4),
				C.MetalLight,
				Enum.Material.Metal
			)
			Build.Neon({
				Name = "Circuit",
				Size = Vector3.new(0.25, plinthH - 0.6, 0.1),
				CFrame = cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(1.2, top + plinthH / 2, -3.02),
				Color = secondary,
				Transparency = 0.2,
				Parent = model,
			})
		end
		Props.Box(
			model,
			"Riser",
			Vector3.new(3, 1.2, 3),
			at(0, top + plinthH + 0.6, 0),
			C.MetalDark,
			Enum.Material.Metal
		)
		Props.Box(model, "Substrate", Vector3.new(3.6, 0.3, 3.6), at(0, top + plinthH + 1.35, 0), C.Pcb)
		Props.Box(model, "Npu", Vector3.new(2.2, 0.4, 2.2), at(0, top + plinthH + 1.6, 0), C.Bg, Enum.Material.Glass)
		local orbY = top + plinthH + 3 + radius
		glow("Orb", Vector3.new(radius * 2, radius * 2, radius * 2), at(0, orbY, 0), Enum.PartType.Ball).Transparency =
			0.15
		-- Anneau : moyeu invisible ancré (tag Spin, axe Y) + segments soudés
		local hubCf = at(0, orbY, 0) * CFrame.Angles(math.rad(14), 0, math.rad(10))
		local hub = Build.Decor({
			Name = "Halo",
			Size = Vector3.new(0.4, 0.4, 0.4),
			CFrame = hubCf,
			Transparency = 1,
			Tags = { "Spin" },
			Parent = model,
		})
		hub:SetAttribute("Axis", "Y")
		local ringParts = Props.Ring(
			model,
			"HaloRing",
			hubCf * CFrame.Angles(0, 0, math.pi / 2),
			radius * 1.55,
			0.35,
			0.25,
			18,
			secondary,
			Enum.Material.Neon
		)
		for _, part in ringParts do
			part.Transparency = 0.3
			weldTo(hub, part)
		end
		for k = 1, slot do
			local node = glow(
				"Node",
				Vector3.one * 0.9,
				hubCf * CFrame.Angles(0, k * math.pi * 2 / slot, 0) * CFrame.new(radius * 1.55, 0, 0),
				Enum.PartType.Ball
			)
			weldTo(hub, node)
		end
		for k = 0, 3 do
			local foot = (cf * CFrame.Angles(0, math.pi / 4 + k * math.pi / 2, 0) * CFrame.new(0, top + plinthH, -2.6)).Position
			Build.Neon({
				Name = "Synapse",
				Size = Vector3.new((foot - at(0, orbY, 0).Position).Magnitude, 0.18, 0.18),
				CFrame = Props.Along(foot, at(0, orbY, 0).Position),
				Color = secondary,
				Transparency = 0.45,
				Parent = model,
			})
		end
		top = orbY + radius * 1.6
	end

	-- Point d'ancrage de l'étiquette de niveau (affichée par le client)
	Build.Decor({
		Name = "LabelAnchor",
		Size = Vector3.one,
		CFrame = cf * CFrame.new(0, top + 3, 0),
		Transparency = 1,
		Parent = model,
	})
	-- Prompt sur le socle (à hauteur de joueur) : l'étiquette peut être haute, le prompt non.
	Build.Prompt(base, "Améliorer", def.Name, "Upgrade", 14):SetAttribute("ModuleId", def.Id)
	return model
end

------------------------------------------------------------------------------------
-- Terminaux, pads, fragments
------------------------------------------------------------------------------------

-- Terminal de gameplay : pupitre + écran (rendu côté client, tag TerminalScreen).
-- L'écran est autoéclairé (SurfaceGui) : pas de PointLight, pour le budget mobile.
function Props.Terminal(
	parent: Instance,
	name: string,
	cf: CFrame,
	color: Color3,
	actionText: string,
	objectText: string,
	action: string
): Model
	local model = Build.Model(name, parent)
	local stand = Build.Part({
		Name = "Stand",
		Size = Vector3.new(4, 5, 3),
		CFrame = cf * CFrame.new(0, 2.5, 0),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	model.PrimaryPart = stand
	Props.Box(
		model,
		"Foot",
		Vector3.new(6, 0.5, 4.4),
		cf * CFrame.new(0, 0.25, 0.2),
		C.MetalLight,
		Enum.Material.DiamondPlate
	)
	for _, x in { -2.05, 2.05 } do
		Build.Neon({
			Name = "SideGlow",
			Size = Vector3.new(0.15, 4, 0.3),
			CFrame = cf * CFrame.new(x, 2.4, -1.3),
			Color = color,
			Transparency = 0.25,
			Parent = model,
		})
	end
	Props.Box(
		model,
		"ScreenBack",
		Vector3.new(6.4, 4.4, 0.5),
		cf * CFrame.new(0, 6.5, 0.05) * CFrame.Angles(math.rad(-15), 0, 0),
		C.Black,
		Enum.Material.Metal
	)
	local screen = Build.Decor({
		Name = "Screen",
		Size = Vector3.new(6, 4, 0.4),
		CFrame = cf * CFrame.new(0, 6.5, -0.4) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = C.Bg,
		Material = Enum.Material.Glass,
		Transparency = 0.05,
		Tags = { "TerminalScreen" },
		Parent = model,
	})
	screen:SetAttribute("Label", objectText)
	screen:SetAttribute("Accent", color:ToHex())
	Build.Neon({
		Name = "Trim",
		Size = Vector3.new(6.2, 0.25, 0.5),
		CFrame = cf * CFrame.new(0, 4.4, -0.6),
		Color = color,
		Parent = model,
	})
	Build.Prompt(stand, actionText, objectText, action, 12)
	return model
end

function Props.Pad(parent: Instance, name: string, cf: CFrame, diameter: number, color: Color3): Part
	local base = Build.Cylinder({
		Name = name,
		Size = Vector3.new(0.6, diameter, diameter),
		CFrame = cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		CanTouch = true,
		Parent = parent,
	})
	Build.Neon({
		Name = name .. "Glow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, diameter - 1.5, diameter - 1.5),
		CFrame = cf * CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Transparency = 0.5,
		Tags = { "PulseGlow" },
		Parent = parent,
	})
	-- Liseré chromé + plots de contact dorés
	Props.Rod(
		parent,
		name .. "Rim",
		cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		0.4,
		diameter + 0.8,
		C.Nickel
	)
	for k = 0, 5 do
		Props.Box(
			parent,
			name .. "Contact",
			Vector3.new(0.8, 0.2, 1.6),
			cf * CFrame.Angles(0, k * math.pi / 3, 0) * CFrame.new(0, 0.72, -(diameter / 2 - 1.8)),
			C.Gold,
			Enum.Material.Foil
		)
	end
	return base
end

------------------------------------------------------------------------------------
-- Décor PC : ailettes, câbles, tubes, condensateurs, texte
------------------------------------------------------------------------------------

-- Bloc d'ailettes (radiateur) : plaques fines empilées le long du LookVector de `cf`.
-- `decor` : plaques sans collision (détail hors de portée ou traversable).
function Props.Fins(
	parent: Instance,
	cf: CFrame,
	width: number,
	height: number,
	depth: number,
	count: number,
	color: Color3?,
	decor: boolean?
): Model
	local model = Build.Model("Fins", parent)
	local spacing = depth / count
	for i = 0, count - 1 do
		local fin = Build.Part({
			Name = "Fin",
			Size = Vector3.new(width, height, math.max(spacing * 0.35, 0.3)),
			CFrame = cf * CFrame.new(0, 0, -depth / 2 + spacing * (i + 0.5)),
			Color = color or C.Aluminum,
			Material = Enum.Material.Metal,
			Reflectance = 0.05,
			Parent = model,
		})
		if decor then
			fin.CanCollide = false
			fin.CanQuery = false
			fin.CanTouch = false
			fin.CastShadow = false
		end
	end
	return model
end

-- Câble gainé qui suit une liste de points (segments cylindriques + articulations).
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
		Build.Part({
			Name = "Segment",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((b - a).Magnitude, radius * 2, radius * 2),
			CFrame = Props.Along(a, b),
			Color = color,
			Material = material or Enum.Material.Fabric,
			Parent = model,
		})
		if i < #points - 1 then
			Build.Decor({
				Name = "Joint",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * radius * 2,
				CFrame = CFrame.new(b),
				Color = color,
				Material = material or Enum.Material.Fabric,
				Parent = model,
			})
		end
	end
	return model
end

-- Câble en arc (courbe de Bézier quadratique) : passe au-dessus des cloisons entre zones.
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
	local count = segments or 10
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
		Build.Part({
			Name = "TubeGlass",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length, radius * 2, radius * 2),
			CFrame = along,
			Color = Color3.fromRGB(215, 235, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			CastShadow = false,
			Parent = model,
		})
		Props.Rod(model, "TubeCoolant", along, length, radius * 1.3, coolant, Enum.Material.Neon).Transparency = 0.3
		for _, endpoint in { -1, 1 } do
			-- Bague de raccord à chaque extrémité de segment
			Props.Rod(
				model,
				"Fitting",
				along * CFrame.new(endpoint * (length / 2 - radius * 0.6), 0, 0),
				radius * 1.2,
				radius * 2.6,
				C.Nickel
			)
		end
		if i < #points - 1 then
			Build.Decor({
				Name = "Elbow",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * radius * 2.7,
				CFrame = CFrame.new(b),
				Color = C.Nickel,
				Material = Enum.Material.Metal,
				Reflectance = 0.15,
				CastShadow = false,
				Parent = model,
			})
		end
	end
	return model
end

-- Condensateur électrolytique : manchon, capot alu gravé en croix, bande de polarité, joint, collerette lumineuse.
function Props.Capacitor(
	parent: Instance,
	position: Vector3,
	radius: number,
	height: number,
	color: Color3,
	glowColor: Color3
)
	local up = CFrame.Angles(0, 0, math.pi / 2)
	Build.Cylinder({
		Name = "Capacitor",
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * up,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	Props.Rod(parent, "CapSeal", CFrame.new(position + Vector3.new(0, 0.3, 0)) * up, 0.6, radius * 2.1, C.Rubber)
	Props.Rod(
		parent,
		"CapTop",
		CFrame.new(position + Vector3.new(0, height + 0.1, 0)) * up,
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
	-- Bande de polarité (côté -X) : tirets clairs
	for k = 0, 2 do
		Props.Box(
			parent,
			"CapMinus",
			Vector3.new(0.2, radius * 0.25, radius * 0.5),
			CFrame.new(position + Vector3.new(-radius - 0.05, height * (0.3 + k * 0.2), 0)),
			C.Silk
		)
	end
	Build.Neon({
		Name = "CapRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, radius * 2 + 0.3, radius * 2 + 0.3),
		CFrame = CFrame.new(position + Vector3.new(0, height - 1, 0)) * up,
		Color = glowColor,
		Transparency = 0.45,
		Parent = parent,
	})
end

-- Texte "sérigraphié" (SurfaceGui statique sur la face avant d'une pièce).
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

return Props
