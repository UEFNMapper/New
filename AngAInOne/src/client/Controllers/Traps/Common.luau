--!strict
--[[
	Traps/Common : types, réglages et outils partagés par les pièges (voir TrapController).

	Règle d'or : tout ce qui DÉCIDE (pose, danger, plateforme solide ou non) est une fonction pure
	de l'horloge du monde (TrapClock) et des attributs du piège. Les pièces créées côté client
	(onglets, curseur, segments...) ne sont que l'habillage et les collisions locales : tous les
	joueurs voient la même chose au même moment, et les tests peuvent tout vérifier sans rendu.

	Équité (8–14 ans) : tout danger est annoncé au moins TELEGRAPH secondes avant (couleur,
	clignotement, anneau au sol, ombre) et OnCue permet d'y brancher un son.
]]

local Workspace = game:GetService("Workspace")

local Common = {}

Common.TELEGRAPH = 0.8 -- préavis minimal avant un danger (s)
Common.BODY_RADIUS = 0.95 -- rayon des 3 points testés sur le corps (indulgent pour les enfants)
Common.BODY_SAMPLES = { 0.9, 2.6, 4.3 } -- hauteurs des points testés au-dessus des pieds
Common.TWO_PI = math.pi * 2
Common.WALK_SPEED = 16

-- Pièce du piège (racine + pièces soudées) : taille et position relative mises en cache
-- pour ne lire aucune propriété d'instance à chaque image.
export type Solid = { Part: BasePart, Shape: Enum.PartType, Size: Vector3, Offset: CFrame, Transparency: number }

-- Pièce d'habillage créée par le client (onglet, patin, segment, curseur...). Current / Next :
-- repère LOGIQUE (dessus = Y local) ; la pièce visible est posée en Next * Offset.
export type Piece = {
	Part: BasePart,
	Offset: CFrame,
	Size: Vector3, -- boîte logique (pieds posés dessus)
	Current: CFrame,
	Next: CFrame,
	Solid: boolean, -- plateforme : transporte le personnage si le piège est porteur
	Alpha: number, -- transparence appliquée (-1 = jamais)
	Collide: boolean?, -- CanCollide appliqué
	Tint: Color3?, -- couleur appliquée
}

-- Contexte d'une image, recalculé pour le monde de chaque piège.
export type Ctx = {
	T: number, -- horloge des pièges du monde (TrapClock : figée en FREEZE, à-coups en LAG)
	Now: number, -- heure serveur brute (délais locaux)
	Dt: number,
	Incident: string, -- incident en cours dans le monde ("" sinon)
	Incoming: string, -- incident annoncé mais pas encore commencé ("" sinon)
	Until: number, -- secondes avant le début (annoncé) ou la fin (en cours) de l'incident
	Advanced: boolean, -- l'horloge du monde a avancé depuis l'image précédente
	Reduced: boolean, -- ReducedMotion : pas de clignotement
	Alive: boolean,
	Feet: Vector3,
	Root: BasePart?,
	Humanoid: Humanoid?,
	Grounded: boolean,
	Camera: Vector3,
	Push: Vector3, -- poussée horizontale accumulée (studs/s)
}

export type Handler = {
	Lethal: boolean?, -- contact mortel (Hits, sinon pièces du piège)
	Carrier: boolean?, -- transporte le personnage posé sur la racine ou sur ses pièces solides
	Decor: boolean?, -- pur décor : ignoré en ReducedMotion
	Setup: ((trap: Trap) -> ())?, -- lecture des attributs propres au type (sans créer d'instance)
	Build: ((trap: Trap, f: Ctx) -> ())?, -- habillage client, créé à la première animation
	Pose: ((trap: Trap, t: number) -> CFrame)?, -- pose de la racine
	Update: ((trap: Trap, f: Ctx) -> ())?, -- visuels, collisions, pièces (Next)
	Active: ((trap: Trap, f: Ctx) -> boolean)?, -- mortel en ce moment (défaut : toujours)
	Hits: ((trap: Trap, f: Ctx, feet: Vector3) -> boolean)?, -- contact (défaut : pièces du piège)
	Interact: ((trap: Trap, f: Ctx, feet: Vector3) -> ())?, -- poussées, rebonds, effacements
}

export type Trap = {
	Part: BasePart,
	Kind: string,
	World: number,
	Handler: Handler,
	Rest: CFrame,
	Current: CFrame,
	Next: CFrame,
	Radius: number, -- débattement autour de la boîte de repos (décalage, patrouille, zone...)
	Period: number,
	Duty: number,
	Phase: number,
	Speed: number,
	Axis: Vector3, -- axe LOCAL
	Offset: Vector3,
	Direction: Vector3,
	Strength: number,
	Delay: number,
	Respawn: number,
	Power: number,
	Path: { Vector3 },
	Cumulative: { number }, -- longueurs cumulées de la boucle fermée
	Loop: number, -- longueur de la boucle fermée
	OpenCumulative: { number }, -- longueurs cumulées du chemin ouvert (1er -> dernier point)
	OpenLength: number,
	Gusts: boolean,
	Cause: string,
	Seed: number, -- graine déterministe (position de repos)
	Solids: { Solid },
	Pieces: { Piece },
	Size: Vector3,
	Bound: number, -- rayon de la sphère englobant toutes les pièces (autour de la racine)
	Emitters: { ParticleEmitter },
	Color: Color3,
	Visual: number, -- dernier état visuel appliqué (évite les écritures inutiles)
	VanishAt: number?,
	Hidden: boolean,
	Removed: boolean,
	Near: boolean, -- proche du personnage (dernier recalcul des listes)
	Built: boolean,
	Rig: Instance?,
	CueKeys: { [string]: number }, -- dernier signal envoyé par nom (clés croissantes)
	Data: any, -- réglages et état propres au type (voir chaque module)
	Connection: RBXScriptConnection?,
}

------------------------------------------------------------------------------------
-- Attributs
------------------------------------------------------------------------------------

function Common.Num(part: Instance, name: string, default: number): number
	local value = part:GetAttribute(name)
	return if type(value) == "number" and value == value then value else default
end

function Common.Vec(part: Instance, name: string, default: Vector3?): Vector3
	local value = part:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else (default or Vector3.zero)
end

-- "X" | "Y" | "Z" (axe local) ou Vector3.
function Common.AxisOf(part: Instance, default: Vector3): Vector3
	local value = part:GetAttribute("Axis")
	if typeof(value) == "Vector3" and value.Magnitude > 0 then
		return value.Unit
	elseif value == "X" then
		return Vector3.xAxis
	elseif value == "Y" then
		return Vector3.yAxis
	elseif value == "Z" then
		return Vector3.zAxis
	end
	return default
end

-- "x,y,z;x,y,z" -> points relatifs (le premier point est normalement 0,0,0).
function Common.ParseWaypoints(text: any): { Vector3 }
	local points = {}
	if type(text) ~= "string" then
		return points
	end
	for chunk in string.gmatch(text, "[^;]+") do
		local x, y, z = string.match(chunk, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
		local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
		if nx and ny and nz then
			table.insert(points, Vector3.new(nx, ny, nz))
		end
	end
	return points
end

------------------------------------------------------------------------------------
-- Temps et hasard déterministe
------------------------------------------------------------------------------------

function Common.Cycle(trap: Trap, t: number): number
	return (t / trap.Period + trap.Phase) % 1
end

-- Numéro du cycle en cours (change quand Cycle repasse par 0).
function Common.CycleIndex(trap: Trap, t: number): number
	return math.floor(t / trap.Period + trap.Phase)
end

function Common.Smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Aller-retour doux (0 -> 1 -> 0) sur un cycle.
function Common.Swing(p: number): number
	return 0.5 - 0.5 * math.cos(Common.TWO_PI * p)
end

-- Nombre pseudo-aléatoire dans [0, 1), identique sur tous les clients (xorshift 32 bits exact).
function Common.Hash01(seed: number, n: number): number
	local x = bit32.bxor(math.floor(seed) % 4294967296, (math.floor(n) * 40503) % 4294967296)
	if x == 0 then
		x = 0x9E3779B9
	end
	for _ = 1, 3 do
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
	end
	return x / 4294967296
end

function Common.SeedOf(cf: CFrame): number
	local p = cf.Position
	return math.floor(math.abs(p.X) * 13 + math.abs(p.Y) * 7 + math.abs(p.Z) * 17) % 2147483647
end

-- Clignotement (ReducedMotion : allumé en continu).
function Common.Blink(t: number, hz: number, reduced: boolean): boolean
	return reduced or math.floor(t * hz * 2) % 2 == 0
end

------------------------------------------------------------------------------------
-- Chemins (Waypoints)
------------------------------------------------------------------------------------

-- Longueurs cumulées : boucle fermée (dernier -> premier) ou chemin ouvert.
function Common.Measure(path: { Vector3 }, closed: boolean): ({ number }, number)
	local cumulative = { 0 }
	local total = 0
	local count = if closed then #path else #path - 1
	if #path >= 2 then
		for i = 1, count do
			total += (path[i % #path + 1] - path[i]).Magnitude
			cumulative[i + 1] = total
		end
	end
	return cumulative, total
end

-- Point (et direction du segment) à l'abscisse s.
function Common.PathPoint(path: { Vector3 }, cumulative: { number }, s: number, closed: boolean): (Vector3, Vector3)
	local count = if closed then #path else #path - 1
	for i = 1, count do
		local a, b = cumulative[i], cumulative[i + 1]
		if s <= b or i == count then
			local from, to = path[i], path[i % #path + 1]
			local alpha = if b > a then math.clamp((s - a) / (b - a), 0, 1) else 0
			local delta = to - from
			return from:Lerp(to, alpha), if delta.Magnitude > 1e-6 then delta.Unit else Vector3.xAxis
		end
	end
	return if path[1] then path[1] else Vector3.zero, Vector3.xAxis
end

------------------------------------------------------------------------------------
-- Géométrie du personnage
------------------------------------------------------------------------------------

-- Distance d'un point à une pièce (0 ou négatif = dedans), selon sa forme.
function Common.DistanceTo(cf: CFrame, size: Vector3, shape: Enum.PartType, point: Vector3): number
	local lp = cf:PointToObjectSpace(point)
	local half = size / 2
	if shape == Enum.PartType.Ball then
		return lp.Magnitude - math.min(half.X, half.Y, half.Z)
	elseif shape == Enum.PartType.Cylinder then
		local radial = math.sqrt(lp.Y * lp.Y + lp.Z * lp.Z) - math.min(half.Y, half.Z)
		local axial = math.abs(lp.X) - half.X
		if radial <= 0 and axial <= 0 then
			return math.max(radial, axial)
		end
		local r, a = math.max(radial, 0), math.max(axial, 0)
		return math.sqrt(r * r + a * a)
	end
	local dx = math.max(math.abs(lp.X) - half.X, 0)
	local dy = math.max(math.abs(lp.Y) - half.Y, 0)
	local dz = math.max(math.abs(lp.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Le corps (3 points au-dessus des pieds) touche-t-il la boîte ?
function Common.BodyTouchesBox(cf: CFrame, size: Vector3, feet: Vector3): boolean
	if (cf.Position - feet).Magnitude > size.Magnitude / 2 + 6 then
		return false
	end
	for _, h in Common.BODY_SAMPLES do
		if Common.DistanceTo(cf, size, Enum.PartType.Block, feet + Vector3.new(0, h, 0)) <= Common.BODY_RADIUS then
			return true
		end
	end
	return false
end

-- Contact avec les pièces du piège (racine + pièces soudées) dans sa pose courante.
function Common.Touches(trap: Trap, feet: Vector3): boolean
	-- Test grossier d'abord : le corps (≈ 5,3 studs de haut) est-il près de la sphère englobante ?
	if (trap.Current.Position - feet).Magnitude > trap.Bound + 6 then
		return false
	end
	for _, solid in trap.Solids do
		local cf = trap.Current * solid.Offset
		for _, h in Common.BODY_SAMPLES do
			if Common.DistanceTo(cf, solid.Size, solid.Shape, feet + Vector3.new(0, h, 0)) <= Common.BODY_RADIUS then
				return true
			end
		end
	end
	return false
end

-- Les pieds reposent sur le dessus de la boîte (repère `cf`, haut = Y local).
function Common.StandsOn(cf: CFrame, size: Vector3, feet: Vector3): boolean
	local lp = cf:PointToObjectSpace(feet)
	local half = size / 2
	return math.abs(lp.X) <= half.X + 0.6
		and math.abs(lp.Z) <= half.Z + 0.6
		and lp.Y >= half.Y - 0.8
		and lp.Y <= half.Y + 1.2
end

------------------------------------------------------------------------------------
-- Habillage client (pièces locales, jamais répliquées)
------------------------------------------------------------------------------------

local container: Instance? = nil

-- Dossier Workspace.TrapRigs (créé au besoin) qui contient l'habillage de tous les pièges.
function Common.Container(): Instance
	local existing = container
	if existing and existing.Parent then
		return existing
	end
	local found = Workspace:FindFirstChild("TrapRigs")
	if not found then
		local folder = Instance.new("Folder")
		folder.Name = "TrapRigs"
		folder.Parent = Workspace
		found = folder
	end
	container = found
	return found :: Instance
end

-- Modèle d'habillage d'un piège (détruit quand le piège quitte le streaming).
function Common.RigOf(trap: Trap): Instance
	local rig = trap.Rig
	if rig then
		return rig
	end
	local model = Instance.new("Model")
	model.Name = `{trap.Kind}Rig`
	model.Parent = Common.Container()
	trap.Rig = model
	return model
end

function Common.Make(className: string, props: { [string]: any }, parent: Instance?): Instance
	local instance = Instance.new(className :: any)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Pièce ancrée, sans ombre, ni requête ni contact (les collisions sont gérées par état).
function Common.NewPart(
	className: string,
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): BasePart
	local part = Instance.new(className :: any) :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.Parent = parent
	return part
end

-- Cylindre (disque si on le couche : voir CFrame.Angles(0, 0, π / 2)).
function Common.Cylinder(part: BasePart)
	local block = part :: any
	if part:IsA("Part") then
		block.Shape = Enum.PartType.Cylinder
	end
end

-- Plateforme créée par le client : requêtable (le Humanoid doit la reconnaître comme sol).
function Common.Platform(part: BasePart)
	part.CanQuery = true
end

function Common.AddPiece(trap: Trap, part: BasePart, size: Vector3, cf: CFrame, solid: boolean, offset: CFrame?): Piece
	local piece: Piece = {
		Part = part,
		Offset = offset or CFrame.identity,
		Size = size,
		Current = cf,
		Next = cf,
		Solid = solid,
		Alpha = -1,
		Collide = nil,
		Tint = nil,
	}
	table.insert(trap.Pieces, piece)
	return piece
end

function Common.SetAlpha(piece: Piece, value: number)
	if piece.Alpha ~= value then
		piece.Alpha = value
		piece.Part.Transparency = value
	end
end

function Common.SetCollide(piece: Piece, value: boolean)
	if piece.Collide ~= value then
		piece.Collide = value
		piece.Part.CanCollide = value
	end
end

function Common.SetTint(piece: Piece, color: Color3)
	if piece.Tint ~= color then
		piece.Tint = color
		piece.Part.Color = color
	end
end

-- La racine du piège ne sert que de repère (zone, pont...) : invisible et traversable ici.
function Common.HideRoot(trap: Trap, transparency: number?)
	trap.Part.LocalTransparencyModifier = transparency or 1
	trap.Part.CanCollide = false
end

-- Applique transparence / collision à la racine et aux pièces soudées.
function Common.SetSolids(trap: Trap, transparency: number?, collide: boolean?)
	for _, solid in trap.Solids do
		if transparency then
			solid.Part.Transparency = transparency
		end
		if collide ~= nil then
			solid.Part.CanCollide = collide
		end
	end
end

------------------------------------------------------------------------------------
-- Signaux sonores / effets (branchés par TrapController.OnCue)
------------------------------------------------------------------------------------

Common.CueHandler = nil :: ((cue: string, trap: Trap) -> ())?

-- Signal envoyé une fois par clé CROISSANTE (ex. numéro de cycle), seulement pour les pièges
-- proches du joueur.
function Common.Cue(trap: Trap, cue: string, key: number)
	local last = trap.CueKeys[cue]
	if last and key <= last then
		return
	end
	trap.CueKeys[cue] = key
	local handler = Common.CueHandler
	if handler and trap.Near then
		handler(cue, trap)
	end
end

return Common
