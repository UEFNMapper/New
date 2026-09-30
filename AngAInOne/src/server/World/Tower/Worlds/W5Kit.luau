--!strict
--[[
	W5Kit : outils de construction partagés par les mondes 5 (The Core) et 6 (Render Canyon).
	Tout ce qui est gameplay reste en primitives (plateformes solides lisibles, pièges rouges non
	solides) ; les vrais modèles 3D ne servent qu'à l'habillage (voir Kit.Place).

	Repères : `top` = centre du DESSUS d'une plateforme ; `look` = direction horizontale de la course
	(le LookVector de la pièce), la largeur est portée par le RightVector.
]]

local WorldFolder = script.Parent.Parent.Parent
local Build = require(WorldFolder.Build)
local Props = require(WorldFolder.Props)
local ModelLibrary = require(WorldFolder.ModelLibrary)
local Common = require(script.Parent.Parent.Common)

type Ctx = Common.WorldContext

local Kit = {}

local UP = Vector3.yAxis
local C = Common.C
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local LETHAL = Common.Colors.Lethal
local HEAT = Common.Colors.Heat
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- cylindre (axe X local) couché en disque

Kit.UP = UP
Kit.FLAT = FLAT
Kit.EMITTER = Color3.fromRGB(150, 24, 40) -- boîtiers des pièges mortels (rouge sombre)
Kit.WOOD = Color3.fromRGB(122, 86, 54)

local facing = Common.Facing

-- Repère posé en `position`, LookVector horizontal `look` (X local = largeur).
function Kit.Facing(position: Vector3, look: Vector3): CFrame
	return facing(position, look)
end

-- Plateforme solide aux couleurs du monde : dessus centré en `top`, longueur le long de `look`.
function Kit.Slab(
	ctx: Ctx,
	parent: Instance,
	top: Vector3,
	look: Vector3,
	length: number,
	width: number,
	name: string?,
	thick: number?
): Part
	local t = thick or 2
	return ctx.Platform(parent, Vector3.new(width, t, length), facing(top - Vector3.new(0, t / 2, 0), look), name)
end

-- Pièce de structure solide (sans liserés).
function Kit.Solid(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return Build.Part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or METAL,
		Parent = parent,
	})
end

-- Piège : pièce (solide seulement si `collide`) + tag Trap et attributs via ctx.Trap.
function Kit.Trap(
	ctx: Ctx,
	parent: Instance,
	kind: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	attributes: { [string]: any },
	collide: boolean?
): Part
	local part = Build.Part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		CastShadow = false,
		Parent = parent,
	})
	part.CanCollide = collide == true
	part.CanQuery = collide == true
	ctx.Trap(kind, part, attributes)
	return part
end

--[[
	Vrai modèle 3D posé en `cf` (centre de la base), mis à l'échelle pour mesurer `height` studs de
	haut ; sinon le décor de secours `fallback` (primitives). Le gameplay n'en dépend jamais.
]]
function Kit.Place(
	key: string,
	cf: CFrame,
	parent: Instance,
	height: number,
	fallback: () -> Instance?,
	spin: (boolean | string)?
): Instance?
	local placed = ModelLibrary.Place(key, cf, parent, { Collide = false, Spin = spin }, fallback)
	if placed and ModelLibrary.Has(key) and placed:IsA("Model") then
		local model = placed :: Model
		local _, size = model:GetBoundingBox()
		if size.Y > 0.01 then
			model:ScaleTo(model:GetScale() * height / size.Y)
			model:PivotTo(cf)
		end
	end
	return placed
end

-- Soude toutes les pièces d'un modèle placé à la racine d'un piège (elles la suivent).
function Kit.WeldModel(root: BasePart, model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			Props.WeldTo(root, d)
		end
	end
end

------------------------------------------------------------------------------------
-- Pièges
------------------------------------------------------------------------------------

--[[
	Pioche du mineur (Pendulum) : la TÊTE (racine, rouge) est mortelle ; le manche est soudé mais
	hors de la racine (non mortel). `head` = centre de la tête au repos (bas du balancier) ;
	`swing` = sens du balancement (horizontal) ; le pivot est `length` studs au-dessus de la tête,
	accroché à une poutre de chevalement (décor) posée dans le plan du balancement.
]]
function Kit.Pickaxe(
	ctx: Ctx,
	parent: Instance,
	head: Vector3,
	swing: Vector3,
	length: number,
	amplitude: number,
	period: number,
	phase: number,
	rig: number?
): Part
	local cf = facing(head, swing)
	local root = Kit.Trap(ctx, parent, "Pendulum", "PickaxeHead", Vector3.new(1.8, 2, 5.4), cf, LETHAL, NEON, {
		Axis = "X",
		Amplitude = amplitude,
		Period = period,
		Phase = phase,
		Pivot = Vector3.new(0, length, 0),
	})
	root.Transparency = 0.05
	-- Pointes de la pioche (mortelles, soudées sous la racine)
	for _, side in { -1, 1 } do
		local tip = Common.Attach(
			root,
			"PickTip",
			Vector3.new(1.2, 1.2, 2.2),
			cf * CFrame.new(0, -0.5, side * 3.4) * CFrame.Angles(side * math.rad(20), 0, 0),
			LETHAL,
			NEON
		)
		tip.Transparency = 0.05
	end
	Common.Attach(root, "PickEye", Vector3.new(2.2, 2.6, 1.8), cf * CFrame.new(0, 0.3, 0), Kit.EMITTER, METAL)
	local pivot = head + Vector3.new(0, length, 0)
	local model = if ModelLibrary.Has("Pickaxe")
		then Kit.Place("Pickaxe", facing(head - Vector3.new(0, 1, 0), swing), parent, length + 2, function()
			return nil
		end)
		else nil
	if model then
		Kit.WeldModel(root, model)
		root.Transparency = 0.55
	else
		local handle = Props.Rod(
			parent,
			"PickHandle",
			Props.Along(head + Vector3.new(0, 1, 0), pivot),
			length - 1,
			1.1,
			Kit.WOOD,
			Enum.Material.Wood
		)
		Props.WeldTo(root, handle)
		local grip = Props.Rod(
			parent,
			"PickGrip",
			Props.Along(pivot - Vector3.new(0, 3.5, 0), pivot - Vector3.new(0, 0.5, 0)),
			3,
			1.4,
			C.Rubber
		)
		Props.WeldTo(root, grip)
	end
	-- Chevalement : poutre dans le plan du balancement (au-dessus du pivot) + deux jambes hors d'atteinte
	local reach = rig or (length * math.sin(math.rad(amplitude)) + 5)
	local beamCf = facing(pivot + Vector3.new(0, 1.2, 0), swing)
	Props.Box(parent, "RigBeam", Vector3.new(1.4, 1.4, reach * 2 + 2), beamCf, C.MetalDark, METAL)
	Props.Rod(parent, "RigPin", CFrame.fromMatrix(pivot, swing:Cross(UP), UP), 2.4, 1.6, C.Nickel)
	for _, side in { -1, 1 } do
		local foot = pivot + swing * side * reach
		Props.Box(
			parent,
			"RigLeg",
			Vector3.new(1.2, length + 18, 1.2),
			CFrame.new(foot + Vector3.new(0, 1.2 - (length + 18) / 2, 0)),
			C.MetalDark,
			METAL
		)
	end
	return root
end

-- Laser de rendu : faisceau (racine) le long de `across`, qui balaie de `offset` (aller-retour).
function Kit.Laser(
	ctx: Ctx,
	parent: Instance,
	center: Vector3,
	across: Vector3,
	width: number,
	offset: Vector3,
	period: number,
	phase: number,
	vertical: boolean?
): Part
	local cf = if vertical
		then CFrame.fromMatrix(center, across:Cross(UP).Unit, UP)
		else CFrame.fromMatrix(center, across, UP)
	local size = if vertical then Vector3.new(0.5, width, 0.5) else Vector3.new(width, 0.5, 0.5)
	local beam =
		Kit.Trap(ctx, parent, "Laser", if vertical then "LaserCurtain" else "LaserBeam", size, cf, LETHAL, NEON, {
			Offset = offset,
			Period = period,
			Phase = phase,
		})
	for _, side in { -1, 1 } do
		local at = if vertical
			then CFrame.new(0, side * (width / 2 + 0.5), 0)
			else CFrame.new(side * (width / 2 + 0.5), 0, 0)
		Common.Attach(beam, "LaserEmitter", Vector3.new(1.2, 1.2, 1.2), cf * at, Kit.EMITTER, METAL)
	end
	return beam
end

-- Bouche de chaleur : grille lumineuse au sol (décor) + colonne mortelle temporisée.
function Kit.Heat(
	ctx: Ctx,
	parent: Instance,
	floor: Vector3,
	look: Vector3,
	width: number,
	length: number,
	height: number,
	period: number,
	duty: number,
	phase: number
): Part
	Build.Neon({
		Name = "HeatVent",
		Size = Vector3.new(width, 0.12, length),
		CFrame = facing(floor + Vector3.new(0, 0.07, 0), look),
		Color = HEAT,
		Transparency = 0.5,
		Parent = parent,
	})
	local column = Kit.Trap(
		ctx,
		parent,
		"Heat",
		"HeatColumn",
		Vector3.new(width, height, length),
		facing(floor + Vector3.new(0, height / 2, 0), look),
		HEAT,
		NEON,
		{ Period = period, Duty = duty, Phase = phase }
	)
	column.Transparency = 0.45
	return column
end

-- Décharge (Zapper) : arc entre deux pylônes, en travers de la course.
function Kit.Zapper(
	ctx: Ctx,
	parent: Instance,
	floor: Vector3,
	look: Vector3,
	width: number,
	height: number,
	period: number,
	duty: number,
	phase: number
): Part
	local right = look:Cross(UP).Unit
	for _, side in { -1, 1 } do
		local base = floor + right * side * (width / 2 + 0.6)
		Props.Rod(
			parent,
			"ZapPylon",
			CFrame.new(base + Vector3.new(0, height / 2, 0)) * Common.VERTICAL,
			height + 1,
			1.4,
			C.MetalDark
		)
		Build.Neon({
			Name = "ZapCap",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2,
			CFrame = CFrame.new(base + Vector3.new(0, height + 0.8, 0)),
			Color = LETHAL,
			Transparency = 0.15,
			Parent = parent,
		})
	end
	local arc = Kit.Trap(
		ctx,
		parent,
		"Zapper",
		"ZapArc",
		Vector3.new(width, height, 0.6),
		facing(floor + Vector3.new(0, height / 2, 0), look),
		LETHAL,
		NEON,
		{ Period = period, Duty = duty, Phase = phase }
	)
	arc.Transparency = 0.3
	return arc
end

-- Plateforme en latence (LagMover) : sûre, avance par à-coups de `offset` (monde) en `steps` sauts.
function Kit.LagMover(
	ctx: Ctx,
	parent: Instance,
	top: Vector3,
	look: Vector3,
	length: number,
	width: number,
	offset: Vector3,
	period: number,
	steps: number,
	phase: number,
	color: Color3,
	edge: Color3
): Part
	local cf = facing(top - Vector3.new(0, 0.8, 0), look)
	local platform = Kit.Trap(
		ctx,
		parent,
		"LagMover",
		"LagPlatform",
		Vector3.new(width, 1.6, length),
		cf,
		color,
		SMOOTH,
		{ Offset = offset, Period = period, Phase = phase, Steps = steps },
		true
	)
	for _, side in { -1, 1 } do
		Common.Attach(
			platform,
			"LagEdge",
			Vector3.new(0.4, 0.4, length),
			cf * CFrame.new(side * width / 2, 0.65, 0),
			edge,
			NEON
		)
	end
	Common.Attach(
		platform,
		"LagUnder",
		Vector3.new(width - 1.5, 1, length - 1.5),
		cf * CFrame.new(0, -1.2, 0),
		C.MetalDark,
		METAL
	)
	Props.Label(platform, "999 ms", edge, Enum.NormalId.Top, Enum.Font.GothamBlack)
	return platform
end

-- Plateforme mobile sûre (Mover) : aller-retour doux de `offset` (monde).
function Kit.Mover(
	ctx: Ctx,
	parent: Instance,
	top: Vector3,
	look: Vector3,
	length: number,
	width: number,
	offset: Vector3,
	period: number,
	phase: number,
	color: Color3,
	edge: Color3
): Part
	local cf = facing(top - Vector3.new(0, 0.8, 0), look)
	local mover = Kit.Trap(
		ctx,
		parent,
		"Mover",
		"Shuttle",
		Vector3.new(width, 1.6, length),
		cf,
		color,
		METAL,
		{ Offset = offset, Period = period, Phase = phase },
		true
	)
	for _, side in { -1, 1 } do
		Common.Attach(
			mover,
			"ShuttleGlow",
			Vector3.new(0.4, 0.3, length),
			cf * CFrame.new(side * width / 2, 0.8, 0),
			edge,
			NEON
		)
	end
	Common.Attach(
		mover,
		"Thruster",
		Vector3.new(width - 2, 1.4, length - 2),
		cf * CFrame.new(0, -1.5, 0),
		C.MetalDark,
		METAL
	)
	return mover
end

--[[
	Roue de chargement (Spinner) : moyeu (racine) qui tourne sur son axe, `count` patins sûrs
	posés par le client sur un cercle de rayon `ring`. `center` = centre du plan des patins (le
	dessus des patins est 0,5 plus haut) ; `back` = direction du patin 1 au repos.
	`axis` = nil (manège à plat, axe Y) ou une direction horizontale (grande roue, patins à plat).
	Manège : des « ombres » invisibles et solides, soudées au moyeu, doublent les patins du client
	(elles tournent avec lui, exactement au même endroit) pour que la géométrie du serveur (graphe
	de sauts des tests) connaisse la roue ; le transport reste assuré par les patins du client.
]]
function Kit.Spinner(
	ctx: Ctx,
	parent: Instance,
	center: Vector3,
	back: Vector3,
	ring: number,
	count: number,
	speed: number,
	phase: number,
	hubSize: number,
	color: Color3,
	axis: Vector3?
): Part
	local flat = axis == nil
	local cf = if flat
		then CFrame.fromMatrix(center, back, UP)
		else CFrame.fromMatrix(center, (axis :: Vector3).Unit, UP)
	local hubDims = if flat then Vector3.new(hubSize, 1, hubSize) else Vector3.new(hubSize * 0.6, hubSize, hubSize)
	local hub = Kit.Trap(ctx, parent, "Spinner", "LoadingHub", hubDims, cf, color, SMOOTH, {
		Speed = speed,
		Count = count,
		Ring = ring,
		PadSize = Vector3.new(5, 1, 5),
		Phase = phase,
		Axis = if flat then "Y" else "X",
	}, flat)
	-- Pastille lumineuse sur le moyeu (tourne avec lui)
	local glow = Props.Rod(
		hub,
		"HubGlow",
		if flat then cf * CFrame.new(0, 0.55, 0) * FLAT else cf * CFrame.new(hubDims.X / 2 + 0.1, 0, 0),
		0.2,
		hubSize * 0.7,
		color:Lerp(Color3.new(1, 1, 1), 0.3),
		NEON
	)
	Props.WeldTo(hub, glow)
	-- Orbite des patins (décor fixe, discret) : on lit la roue même sans le client
	local orbitCf = if flat then CFrame.new(center - Vector3.new(0, 0.9, 0)) * FLAT else cf
	for _, segment in Props.Ring(parent, "LoadingOrbit", orbitCf, ring, 1.2, 0.2, 12, color:Lerp(C.Bg, 0.55), NEON) do
		segment.Transparency = 0.55
	end
	if flat then
		local u = back.Unit
		local v = UP:Cross(u)
		for i = 1, count do
			local a = math.pi * 2 * (i - 1) / count
			local position = center + (u * math.cos(a) + v * math.sin(a)) * ring
			local shadow = Common.Attach(
				hub,
				"PadShadow",
				Vector3.new(3.6, 1, 3.6),
				CFrame.new(position) * cf.Rotation,
				color,
				SMOOTH
			)
			shadow.Transparency = 1
			shadow.CanCollide = true
			shadow.CanQuery = true
		end
	else
		-- Rayons de la grande roue (décor tournant avec le moyeu)
		for k = 0, 2 do
			local spoke = Props.Box(
				hub,
				"Spoke",
				Vector3.new(0.4, ring * 2, 0.6),
				cf * CFrame.Angles(k * math.pi / 3, 0, 0),
				C.MetalLight,
				METAL
			)
			Props.WeldTo(hub, spoke)
		end
	end
	return hub
end

--[[
	Pale géante (SpinBar) : barre mortelle (racine) + barres soudées à angles réguliers autour de
	l'axe local X de `cf` (qui doit être la normale du disque). `arms` = nombre de branches (pair).
]]
function Kit.Blades(
	ctx: Ctx,
	parent: Instance,
	cf: CFrame,
	radius: number,
	chord: number,
	depth: number,
	arms: number,
	speed: number,
	phase: number
): Part
	local root = Kit.Trap(ctx, parent, "SpinBar", "FanBlade", Vector3.new(depth, radius * 2, chord), cf, LETHAL, NEON, {
		Speed = speed,
		Axis = "X",
		Phase = phase,
	})
	root.Transparency = 0.1
	local bars = math.max(math.floor(arms / 2), 1)
	for k = 1, bars - 1 do
		local extra = Common.Attach(
			root,
			"FanBlade",
			Vector3.new(depth, radius * 2, chord),
			cf * CFrame.Angles(k * math.pi / bars, 0, 0),
			LETHAL,
			NEON
		)
		extra.Transparency = 0.1
	end
	return root
end

------------------------------------------------------------------------------------
-- Checkpoints et Bits
------------------------------------------------------------------------------------

-- Palier de checkpoint 16 × 16 (dessus en `top`) + pad (dessus 0,4 plus haut), regard `look`.
function Kit.Checkpoint(ctx: Ctx, stage: number, parent: Instance, top: Vector3, look: Vector3, landingLook: Vector3?)
	Kit.Slab(ctx, parent, top, landingLook or look, 16, 16, "Landing")
	ctx.Checkpoint(stage, facing(top + Vector3.new(0, 0.4, 0), look))
end

-- Regard d'un pad : entre le sens de la course et la direction du checkpoint suivant.
function Kit.Toward(course: Vector3, from: Vector3, to: Vector3): Vector3
	local chord = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Unit
	local flat = Vector3.new(course.X, 0, course.Z).Unit
	return (flat + chord).Unit
end

return table.freeze(Kit)
