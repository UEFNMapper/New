--!strict
--[[
	Common : tout ce que les modules de la tour partagent (dimensions, repères, palette par monde,
	outils de construction) et le CONTEXTE DE MONDE (`WorldContext`) donné à chaque monde.

	Découpage (src/server/World) :
	- TowerBuilder.luau       orchestrateur : lobby, coque, puis World1..7 (API publique inchangée)
	- Tower/Common.luau       ce fichier (partagé : on n'y touche pas pendant la phase 2)
	- Tower/Shell.luau        coque vitrée de la tour (parois, vitre, façade, ventilateurs)
	- Tower/Lobby.luau        lobby sur le bureau + maison de départ (checkpoint 0 → toit = entrée du monde 1)
	- Tower/Legacy.luau       parcours v1 (anneau de modules) + décor v1, en attendant les mondes uniques
	- Tower/Worlds/W{n}.luau  un monde = `return function(ctx: Common.WorldContext)` (un agent par fichier)

	Géométrie fixe (vue de dessus, façade avant vers -Z, vitre côté +X, intérieur X, Z ∈ [-132, 132]) :
	- Monde n = tranche de hauteur [Base, Base + BAND[ avec Base = (n - 1) × 100.
	- Coins de l'anneau : 0 = (-88, -88), 1 = (88, -88), 2 = (88, 88), 3 = (-88, 88).
	- ENTRÉE du monde n (`ctx.Entry`) : coin (n - 1) % 4, dessus à Base + 10 (toit de la salle du
	  terminal du monde n - 1, ou de la maison de départ pour n = 1), LookVector = vers le coin suivant.
	- SALLE DU TERMINAL du monde n (`ctx.Terminal`) : coin n % 4, plancher à Base + 80, toit à Base + 110
	  (= entrée du monde n + 1). Le parcours doit finir devant la PORTE (`ctx.Terminal.Door` : bas-centre
	  de l'ouverture de 12 × 12 studs, LookVector = sens d'entrée dans la salle), 8 studs avant le coin.
	- `ctx.Reserved` : volumes à laisser libres (salle d'arrivée du monde précédent, salle du terminal).

	  Monde | Entry (pieds, regard)        | Porte de la salle (bas, regard) | Coin de la salle
	  1     | (-88,  10, -88) → +X         | ( 80,  80, -88) → +X            | ( 88, -88)
	  2     | ( 88, 110, -88) → +Z         | ( 88, 180,  80) → +Z            | ( 88,  88)
	  3     | ( 88, 210,  88) → -X         | (-80, 280,  88) → -X            | (-88,  88)
	  4     | (-88, 310,  88) → -Z         | (-88, 380, -80) → -Z            | (-88, -88)
	  5..7  | comme 1..3, 400 studs plus haut (le cycle des coins recommence)

	Contrat d'un monde (vérifié par TowerBuilder après construction, voir aussi tests/tower.spec.luau) :
	- checkpoints `Tower.FirstStage(n) .. Tower.TerminalStage(n) - 1` posés avec `ctx.Checkpoint`,
	  plateformes de l'étape s rangées dans `ctx.Stage(s)` (le graphe de sauts du test les y cherche) ;
	- `ctx.TerminalRoom()` appelé une fois (checkpoint TerminalStage(n), terminal, portail, rampe, et
	  l'arrivée `Finish` sur le toit du monde 7) ; `ctx.Void()` conseillé (vide mortel sous le monde) ;
	- 3 à 6 Bits par étape (`ctx.Coin`), 3 clés USB (`ctx.UsbKey`, i = 1..3) sur des chemins difficiles ;
	- tout piège passe par `ctx.Trap` (attribut `World` obligatoire), tout danger statique par
	  `ctx.Hazard` ; ce qui tue est rouge / magenta, les pièges mortels sont non solides.
	- Budgets de toute la tour : ≤ 8000 BaseParts, ≤ 90 lumières (≈ 900 pièces et 9 lumières par monde).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)

local Common = {}

------------------------------------------------------------------------------------
-- Dimensions
------------------------------------------------------------------------------------

local INNER = 132 -- demi-largeur intérieure de la tour
local WALL = 6 -- épaisseur des parois
local RING = 88 -- demi-côté de l'anneau du parcours (axe des plateformes)
local SIDE = RING * 2 -- longueur d'un côté (coin à coin)
local BAND = 100 -- hauteur d'un monde
local ENTRY = 10 -- hauteur du départ d'un monde au-dessus de son vide
local RISE = 14 -- montée d'une étape (parcours v1)
local CLIMB = BAND - Tower.STAGES_PER_WORLD * RISE -- rampe de la salle du terminal (30)
local CORNER = 8 -- demi-côté d'une plateforme de coin
local TOP = BAND * Tower.WORLD_COUNT + 50 -- plafond de la tour
local TERMINAL_FLOOR = ENTRY + Tower.STAGES_PER_WORLD * RISE -- plancher de la salle du terminal (80)

Common.INNER = INNER
Common.WALL = WALL
Common.RING = RING
Common.SIDE = SIDE
Common.BAND = BAND
Common.ENTRY = ENTRY
Common.RISE = RISE
Common.CLIMB = CLIMB
Common.CORNER = CORNER
Common.TOP = TOP
Common.TERMINAL_FLOOR = TERMINAL_FLOOR

Common.Dimensions = table.freeze({
	Inner = INNER,
	Wall = WALL,
	Ring = RING,
	Band = BAND,
	Entry = ENTRY,
	Rise = RISE,
	Climb = CLIMB,
	Top = TOP,
})

local UP = Vector3.yAxis
local C = Props.C
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)

Common.UP = UP
Common.C = C
Common.VERTICAL = VERTICAL -- axe X local (cylindres) -> vertical

-- Code couleur (règle d'or : ce qui tue est rouge / magenta néon ; le reste n'est jamais rouge)
local LETHAL = Color3.fromRGB(255, 46, 84)
local GLITCH = Color3.fromRGB(232, 52, 214)
local HEAT = Color3.fromRGB(255, 78, 52)
local VOID = Color3.fromRGB(128, 20, 90)
local SAFE = Color3.fromRGB(79, 209, 197)
local SPRING = Color3.fromRGB(104, 224, 140)
local BIT = Color3.fromRGB(246, 196, 83)
local USB_GOLD = Color3.fromRGB(255, 200, 64)

Common.Colors = table.freeze({
	Lethal = LETHAL,
	Glitch = GLITCH,
	Heat = HEAT,
	Void = VOID,
	Safe = SAFE,
	Spring = SPRING,
	Bit = BIT,
	UsbGold = USB_GOLD,
})

function Common.Hex(value: string): Color3
	return Color3.fromHex(value)
end

function Common.Frac(x: number): number
	return x - math.floor(x)
end

------------------------------------------------------------------------------------
-- Repères
------------------------------------------------------------------------------------

-- Repère : O = origine (y = 0), F = sens de la course, R = F × haut (à droite en courant).
-- Coordonnées locales : u le long de F, v le long de R, y absolu.
export type Frame = { O: Vector3, F: Vector3, R: Vector3 }

local CORNERS = {
	Vector3.new(-RING, 0, -RING),
	Vector3.new(RING, 0, -RING),
	Vector3.new(RING, 0, RING),
	Vector3.new(-RING, 0, RING),
}

-- Coin i de l'anneau (modulo 4), y = 0.
local function corner(i: number): Vector3
	return CORNERS[(i % 4) + 1]
end
Common.Corner = corner

local function frameOf(origin: Vector3, forward: Vector3): Frame
	return { O = origin, F = forward, R = forward:Cross(UP) }
end
Common.FrameOf = frameOf

-- Côté du coin i vers le coin i + 1 (R = vers le centre de la tour).
local function sideFrame(i: number): Frame
	return frameOf(corner(i), (corner(i + 1) - corner(i)).Unit)
end
Common.SideFrame = sideFrame

-- Repère d'un coin : F = direction d'arrivée (depuis le coin i - 1), R = direction de départ.
-- a = distance au-delà du coin (vers la paroi), b = distance le long du départ (b < 0 : dehors).
local function cornerFrame(i: number): Frame
	return frameOf(corner(i), (corner(i) - corner(i - 1)).Unit)
end
Common.CornerFrame = cornerFrame

-- Point du repère.
local function P(fr: Frame, u: number, y: number, v: number): Vector3
	return fr.O + fr.F * u + fr.R * v + Vector3.new(0, y, 0)
end
Common.P = P

-- CFrame dont le LookVector est F (X local = R, Y = haut).
local function CFA(fr: Frame, u: number, y: number, v: number): CFrame
	return CFrame.fromMatrix(P(fr, u, y, v), fr.R, UP, -fr.F)
end
Common.CFA = CFA

-- Boîte alignée sur le repère : Size = (étendue v, étendue y, étendue u).
local function span(
	fr: Frame,
	u0: number,
	u1: number,
	y0: number,
	y1: number,
	v0: number,
	v1: number
): (Vector3, CFrame)
	return Vector3.new(math.abs(v1 - v0), math.abs(y1 - y0), math.abs(u1 - u0)),
		CFA(fr, (u0 + u1) / 2, (y0 + y1) / 2, (v0 + v1) / 2)
end
Common.Span = span

-- CFrame posé en `position`, LookVector horizontal `look`.
local function facing(position: Vector3, look: Vector3): CFrame
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	return CFrame.fromMatrix(position, flat:Cross(UP), UP, -flat)
end
Common.Facing = facing

-- Bas de la tranche du monde w.
local function worldBase(w: number): number
	return (w - 1) * BAND
end
Common.WorldBase = worldBase

-- Coin d'entrée du monde w (= coin de la salle du terminal du monde w - 1).
local function startCorner(w: number): number
	return (w - 1) % 4
end
Common.StartCorner = startCorner

-- Coin de la salle du terminal du monde w (= coin d'entrée du monde w + 1).
local function terminalCorner(w: number): number
	return startCorner(w) + Tower.STAGES_PER_WORLD
end
Common.TerminalCorner = terminalCorner

-- Hauteur (dessus) du checkpoint de l'étape s (1..TOTAL) dans le parcours v1.
function Common.StageHeight(s: number): number
	local w = Tower.WorldOf(s)
	local j = s - Tower.FirstStage(w) + 1
	return worldBase(w) + ENTRY + RISE * j
end

-- Porte d'entrée du parcours dans la façade (bas de la cage d'escalier de la maison de départ).
function Common.EntranceDoor(): (number, number)
	local fr = cornerFrame(0)
	local a, b = P(fr, 44, 0, -44), P(fr, 44, 0, -32)
	return math.min(a.X, b.X), math.max(a.X, b.X)
end

-- Entrée du monde w : pieds du joueur au coin d'entrée, LookVector = vers le coin suivant.
function Common.EntryOf(w: number): CFrame
	return CFA(sideFrame(startCorner(w)), 0, worldBase(w) + ENTRY, 0)
end

export type Box3 = { Name: string, Min: Vector3, Max: Vector3 }

-- Volume d'une maison (salle + cage d'escalier + toit) dans le repère de coin `fr`.
local function houseBox(name: string, fr: Frame, y: number, climb: number): Box3
	local a, b = P(fr, -8, y - 2, -44), P(fr, 44, y + climb, 8)
	return {
		Name = name,
		Min = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)),
		Max = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)),
	}
end

------------------------------------------------------------------------------------
-- Style (palette) par monde
------------------------------------------------------------------------------------

export type Style = {
	Floor: Color3, -- dessus des plateformes
	FloorMat: Enum.Material,
	Edge: Color3, -- liserés lumineux (bords des plateformes)
	Primary: Color3, -- néon principal du monde
	Secondary: Color3, -- accent (jamais rouge : le rouge est réservé au danger)
	Wall: Color3, -- piliers, murs, supports
}

local FLOORS: { [string]: { any } } = {
	PSU = { C.MetalLight, Enum.Material.DiamondPlate, Color3.fromRGB(40, 40, 48) },
	RAM = { Color3.fromRGB(46, 104, 92), SMOOTH, Color3.fromRGB(30, 34, 56) },
	SSD = { Color3.fromRGB(40, 92, 104), SMOOTH, Color3.fromRGB(24, 44, 52) },
	Cooling = { Color3.fromRGB(176, 214, 236), Enum.Material.Glacier, Color3.fromRGB(40, 60, 84) },
	CPU = { Color3.fromRGB(176, 150, 92), METAL, Color3.fromRGB(56, 50, 40) },
	GPU = { Color3.fromRGB(78, 86, 104), METAL, Color3.fromRGB(26, 36, 32) },
	AI = { Color3.fromRGB(92, 76, 140), SMOOTH, Color3.fromRGB(36, 28, 58) },
}

function Common.Style(world: Tower.World): Style
	local primary, secondary = Common.Hex(world.Primary), Common.Hex(world.Secondary)
	local f = FLOORS[world.Id] or FLOORS.PSU
	return {
		Floor = f[1],
		FloorMat = f[2],
		Wall = f[3],
		Edge = if world.Id == "PSU" then primary else primary:Lerp(C.White, 0.2),
		Primary = primary,
		-- Le rouge est réservé au danger : l'accent rouge de l'alimentation devient ambre clair.
		Secondary = if world.Id == "PSU" then Color3.fromRGB(255, 214, 120) else secondary,
	}
end

------------------------------------------------------------------------------------
-- Session de construction (compteur de lumières, dossier des checkpoints)
------------------------------------------------------------------------------------

local session = {
	Lights = 0,
	Checkpoints = nil :: Folder?,
}

-- Début d'une construction : crée Tower.Checkpoints et remet le compteur de lumières à zéro.
function Common.Begin(tower: Folder)
	session.Lights = 0
	session.Checkpoints = Build.Folder("Checkpoints", tower)
end

function Common.LightCount(): number
	return session.Lights
end

-- À appeler pour toute PointLight créée hors de `Common.Lamp` (budget ≤ 90).
function Common.CountLight()
	session.Lights += 1
end

-- Lampe (ancre invisible + PointLight sans ombres), comptée dans le budget.
function Common.Lamp(parent: Instance, position: Vector3, color: Color3, brightness: number, range: number): Part
	local anchor = Box(parent, "Lamp", Vector3.one, CFrame.new(position), color)
	anchor.Transparency = 1
	Build.PointLight(anchor, color, brightness, range)
	session.Lights += 1
	return anchor
end

------------------------------------------------------------------------------------
-- Outils de construction
------------------------------------------------------------------------------------

-- Pad de checkpoint : dessus à `position`, LookVector = `forward` (sens de la suite du parcours).
function Common.CheckpointPad(stage: number, position: Vector3, forward: Vector3): Part
	local cf = facing(position - Vector3.new(0, 0.5, 0), forward)
	local pad = Build.Part({
		Name = `Checkpoint{stage}`,
		Size = Vector3.new(12, 1, 12),
		CFrame = cf,
		Color = C.MetalDark,
		Material = METAL,
		Tags = { "Checkpoint" },
		Parent = session.Checkpoints,
	})
	pad.CanTouch = true
	pad:SetAttribute("Stage", stage)
	for k = 0, 3 do
		Build.Neon({
			Name = "Trim",
			Size = Vector3.new(12.2, 0.3, 0.6),
			CFrame = cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0.42, -5.8),
			Color = SAFE,
			Transparency = 0.1,
			Parent = pad,
		})
	end
	Props.Decal(
		pad,
		"StageNumber",
		Vector3.new(7, 0.1, 7),
		cf * CFrame.new(0, 0.56, 0),
		if stage == 0 then "GO" else tostring(stage),
		C.White,
		Enum.NormalId.Top,
		Enum.Font.GothamBlack
	)
	return pad
end

-- Pièce décorative soudée à un piège (elle bouge avec lui).
function Common.Attach(
	root: BasePart,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Box(root, name, size, cf, color, material)
	Props.WeldTo(root, part)
	return part
end

-- Piège : tag Trap, attributs Kind + World + paramètres, touchable (le client gère le contact).
function Common.MarkTrap(world: number, kind: string, part: BasePart, attributes: { [string]: any }?)
	part:AddTag("Trap")
	part.CanTouch = true
	part:SetAttribute("Kind", kind)
	part:SetAttribute("World", world)
	if attributes then
		for key, value in attributes do
			part:SetAttribute(key, value)
		end
	end
end

-- Danger statique : non solide, tag Hazard, attributs Cause (+ World si donné).
function Common.MarkHazard(part: BasePart, cause: string?, world: number?)
	part:AddTag("Hazard")
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = true
	part:SetAttribute("Cause", cause or "Hazard")
	if world then
		part:SetAttribute("World", world)
	end
end

--[[
	Maison (salle du terminal, ou maison de départ du lobby si `World` = nil), dans le repère de coin
	`fr` : a ∈ [-8, 44] (au-delà du coin jusqu'à la paroi), b ∈ [-44, 8]. Plancher à `y`.
	- Salle : a ∈ [-8, 29], porte d'arrivée dans le mur a = -8 (b ∈ [-6, 6]).
	- Cage d'escalier : a ∈ [30, 44], rampe de b = -38 (y) à b = 6 (y + climb) ; on y entre par
	  l'ouverture b ∈ [-44, -32] de la cloison a = 29..30, fermée par le portail (WorldGate).
	- Toit : dessus à y + climb = départ du monde suivant (trémie au-dessus du haut de la rampe).
]]
export type HouseOptions = {
	World: Tower.World?, -- monde dont c'est la salle du terminal (nil = maison de départ)
	Style: Style,
	Parent: Instance,
}

function Common.House(fr: Frame, y: number, climb: number, opts: HouseOptions): Model
	local s = opts.Style
	local model = Build.Model("TerminalRoom", opts.Parent)
	local roofBottom = y + climb - 2
	local wallColor = s.Wall
	local function slab(
		name: string,
		a0: number,
		a1: number,
		y0: number,
		y1: number,
		b0: number,
		b1: number,
		color: Color3?
	)
		local size, cf = span(fr, a0, a1, y0, y1, b0, b1)
		return Build.Part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color or wallColor,
			Material = METAL,
			Parent = model,
		})
	end

	slab("Floor", -8, 44, y - 2, y, -44, 8, s.Floor:Lerp(C.MetalDark, 0.5))
	-- Mur d'arrivée (porte si salle de terminal)
	if opts.World then
		slab("WallArrival", -8, -7, y, roofBottom, -44, -6)
		slab("WallArrival", -8, -7, y, roofBottom, 6, 8)
		slab("DoorLintel", -8, -7, y + 12, roofBottom, -6, 6)
		for _, b in { -6.3, 6.3 } do
			local size, cf = span(fr, -8.3, -6.7, y, y + 12, b - 0.3, b + 0.3)
			Build.Neon({ Name = "DoorGlow", Size = size, CFrame = cf, Color = SAFE, Parent = model })
		end
	else
		slab("WallArrival", -8, -7, y, roofBottom, -44, 8)
	end
	slab("WallInner", -7, 30, y, roofBottom, 7, 8)
	slab("WallInner", 30, 44, y, roofBottom, 7, 8)
	-- Cloison salle / escalier, avec l'ouverture du portail
	local doorTop = math.min(y + 14, roofBottom)
	slab("Partition", 29, 30, y, roofBottom, -32, 8)
	if doorTop < roofBottom then
		slab("GateLintel", 29, 30, doorTop, roofBottom, -44, -32)
	end
	if not opts.World then
		slab("Partition", 29, 30, y, doorTop, -44, -32)
	end
	-- Toit (salle + haut de la cage d'escalier) et palier d'arrivée de la rampe
	local roofColor = s.Floor:Lerp(C.MetalLight, 0.35)
	slab("Roof", -8, 30, roofBottom, y + climb, -44, 8, roofColor)
	local hatch = -38 + 44 * (climb - 9.5) / climb
	if hatch > -42 then
		slab("RoofStairs", 30, 44, roofBottom, y + climb, -44, hatch, roofColor)
	end
	slab("Landing", 30, 44, roofBottom, y + climb, 6, 8, roofColor)
	for _, a in { -8, 44 } do
		local size, cf = span(fr, a - 0.3, a + 0.3, y + climb - 0.3, y + climb + 0.1, -44, 8)
		Build.Neon({ Name = "RoofEdge", Size = size, CFrame = cf, Color = s.Edge, Transparency = 0.3, Parent = model })
	end
	local esize, ecf = span(fr, -8, 30, y + climb - 0.3, y + climb + 0.1, 7.7, 8.1)
	Build.Neon({ Name = "RoofEdge", Size = esize, CFrame = ecf, Color = s.Edge, Transparency = 0.3, Parent = model })

	-- Rampe (collision lisse) + nez de marches lumineux
	Build.Wedge({
		Name = "Ramp",
		Size = Vector3.new(13.4, climb, 44),
		CFrame = CFrame.fromMatrix(P(fr, 37, y + climb / 2, -16), fr.F, UP, fr.R),
		Color = s.Floor,
		Material = s.FloorMat,
		Parent = model,
	})
	local steps = math.max(math.floor(climb / 3), 3)
	for i = 1, steps - 1 do
		local b = -38 + 44 * i / steps
		local h = y + climb * i / steps
		local size, cf = span(fr, 30.6, 43.4, h - 0.1, h + 0.25, b - 0.35, b + 0.35)
		Build.Neon({ Name = "StepNose", Size = size, CFrame = cf, Color = s.Edge, Transparency = 0.35, Parent = model })
	end

	if opts.World then
		local world = opts.World
		local w = world.Index
		-- Terminal antivirus (face à la salle) + grand écran
		local consoleCf = facing(P(fr, 12, y + 2.5, -36), fr.R)
		local console = Build.Part({
			Name = "MinigameTerminal",
			Size = Vector3.new(8, 5, 3),
			CFrame = consoleCf,
			Color = C.MetalDark,
			Material = METAL,
			Tags = { "MinigameTerminal" },
			Parent = model,
		})
		console:SetAttribute("World", w)
		console:SetAttribute("Minigame", world.Minigame)
		local prompt = Build.Prompt(console, "Nettoyer", "Terminal antivirus", "Minigame", 12)
		prompt:SetAttribute("World", w)
		Box(model, "Keyboard", Vector3.new(7, 0.4, 2.4), consoleCf * CFrame.new(0, 2.7, -0.4), C.Black)
		Build.Neon({
			Name = "ConsoleGlow",
			Size = Vector3.new(8.2, 0.3, 0.3),
			CFrame = consoleCf * CFrame.new(0, 2.2, -1.6),
			Color = SAFE,
			Parent = model,
		})
		local screenCf = facing(P(fr, 12, y + 12, -43.2), fr.R)
		Box(model, "ScreenBezel", Vector3.new(19, 11, 0.6), screenCf * CFrame.new(0, 0, 0.4), C.Black, METAL)
		local screen = Box(model, "Screen", Vector3.new(18, 10, 0.3), screenCf, C.Bg, Enum.Material.Glass)
		Props.Sign(screen, "ANTIVIRUS", `Mini-jeu : {world.Minigame}`, SAFE, C.White)
		-- Portail d'énergie : traversable côté serveur, rendu solide par le client tant que verrouillé
		local gsize, gcf = span(fr, 29.1, 29.9, y, doorTop, -44, -32)
		local gate = Build.Part({
			Name = "WorldGate",
			Size = gsize,
			CFrame = gcf,
			Color = s.Primary,
			Material = Enum.Material.ForceField,
			Transparency = 0.15,
			CastShadow = false,
			Tags = { "WorldGate" },
			Parent = model,
		})
		gate.CanCollide = false
		gate.CanQuery = false
		gate.CanTouch = true
		gate:SetAttribute("World", w)
		for _, b in { -43.6, -32.4 } do
			local size, cf = span(fr, 28.8, 30.2, y, doorTop, b - 0.4, b + 0.4)
			Build.Neon({ Name = "GateFrame", Size = size, CFrame = cf, Color = s.Primary, Parent = model })
		end
		local signCf = facing(P(fr, 28.6, doorTop + 3, -38), -fr.F)
		local sign = Box(model, "GateSign", Vector3.new(12, 4, 0.3), signCf, C.Bg)
		Props.Sign(
			sign,
			if w < Tower.WORLD_COUNT then `MONDE {w + 1}` else "SOMMET",
			if w < Tower.WORLD_COUNT then Tower.Worlds[w + 1].Name else "Cœur du virus",
			s.Primary,
			C.White
		)
		Common.CheckpointPad(Tower.TerminalStage(w), P(fr, 0, y + 0.4, 0), P(fr, 12, 0, -36) - P(fr, 0, 0, 0))
		Common.Lamp(model, P(fr, 10, y + 20, -18), C.White, 1.2, 50)
	end
	return model
end

-- Arrivée : le cœur du virus vaincu (tag Finish), sur le toit de la salle du terminal du dernier monde.
local function buildFinish(parent: Instance, fr: Frame, top: number)
	local finishCf = CFrame.new(P(fr, 11, top + 7, -20))
	local finish = Build.Part({
		Name = "Finish",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 10,
		CFrame = finishCf,
		Color = Color3.fromRGB(120, 255, 236),
		Material = NEON,
		CastShadow = false,
		Tags = { "Finish" },
		Parent = parent,
	})
	finish.CanCollide = false
	finish.CanTouch = true
	Rod(parent, "FinishPedestal", finishCf * CFrame.new(0, -5.5, 0) * VERTICAL, 3, 12, C.MetalDark)
	Props.Ring(parent, "FinishHalo", finishCf * VERTICAL, 8.5, 0.8, 0.6, 16, SAFE, NEON)
	local hub = Props.SpinHub(parent, finishCf, "Y", 1.2)
	for _, part in Props.Ring(parent, "FinishOrbit", finishCf * CFrame.Angles(0.5, 0, 0), 11, 0.6, 0.5, 12, BIT, NEON) do
		Props.WeldTo(hub, part)
	end
	local signCf = facing(P(fr, 11, top + 20, -20), fr.R)
	local sign = Box(parent, "SummitSign", Vector3.new(30, 6, 0.3), signCf, C.Bg)
	Props.Sign(sign, "CŒUR DU VIRUS", "Touche-le pour sauver le PC d'Anga !", LETHAL:Lerp(C.White, 0.3), C.White)
	Common.Lamp(parent, P(fr, 11, top + 14, -20), SAFE, 2, 60)
end

-- Rectangles couvrant [-INNER, INNER]² privé du carré de coin (|x|, |z| ∈ [RING - CORNER, INNER]).
local function floorRects(cornerIndex: number): { { number } }
	local k = corner(cornerIndex)
	local sx, sz = math.sign(k.X), math.sign(k.Z)
	local edge = RING - CORNER
	local function range(sign: number, a: number, b: number): (number, number)
		local p, q = sign * a, sign * b
		return math.min(p, q), math.max(p, q)
	end
	local zA0, zA1 = range(sz, -INNER, edge)
	local xB0, xB1 = range(sx, -INNER, edge)
	local zB0, zB1 = range(sz, edge, INNER)
	return {
		{ -INNER, INNER, zA0, zA1 },
		{ xB0, xB1, zB0, zB1 },
	}
end

------------------------------------------------------------------------------------
-- Contexte de monde
------------------------------------------------------------------------------------

export type TerminalSpot = {
	Frame: Frame, -- repère du coin de la salle (a le long de F, b le long de R ; voir Common.House)
	Floor: number, -- dessus du plancher de la salle (Base + 80)
	Roof: number, -- dessus du toit (Base + 110 = entrée du monde suivant)
	Door: CFrame, -- bas-centre de la porte d'arrivée (12 × 12), LookVector = vers l'intérieur
}

export type WorldContext = {
	Def: Tower.World, -- définition du monde (Config/Tower)
	Index: number, -- n (1..7)
	Model: Model, -- Workspace.Tower.World{n} (attribut World = n)
	Coins: Folder, -- World{n}.Coins (rempli par ctx.Coin)
	Decor: Folder, -- World{n}.Decor (décor, vide, panneaux)
	Base: number, -- bas de la tranche du monde
	Band: number, -- hauteur de la tranche (100)
	Style: Style, -- palette du monde
	Entry: CFrame, -- pieds du joueur à son arrivée (toit de la salle précédente), LookVector = suite
	Terminal: TerminalSpot, -- emplacement FIXE de la salle du terminal
	Reserved: { Box3 }, -- volumes à laisser libres (salle d'arrivée, salle du terminal)

	-- Dossier Stage{s} (créé au premier appel) ; devient l'étape « courante » de ctx.Coin.
	Stage: (stage: number) -> Folder,
	-- Checkpoint `stage` (FirstStage(n) .. TerminalStage(n) - 1) : `cframe` = dessus du pad (12×1×12),
	-- LookVector = sens de la suite.
	Checkpoint: (stage: number, cframe: CFrame) -> Part,
	-- Bit (tag Coin, CoinId "S{stage}C{i}") ; `stage` par défaut = dernier ctx.Stage(s).
	Coin: (position: Vector3, stage: number?) -> Part,
	-- Clé USB dorée (tag UsbKey, KeyId "W{n}K{i}", i = 1..3), non collidable, touchable.
	UsbKey: (position: Vector3, index: number) -> Part,
	-- Marque une pièce comme piège : tag Trap, Kind, World = n, attributs ; CanTouch = true.
	Trap: (kind: string, part: BasePart, attributes: { [string]: any }?) -> (),
	-- Danger statique néon (tag Hazard, Cause, World) : non solide. Couleur par défaut : rouge.
	Hazard: (
		parent: Instance,
		name: string,
		size: Vector3,
		cframe: CFrame,
		color: Color3?,
		cause: string?
	) -> Part,
	-- Plateforme solide aux couleurs du monde, liserés néon sur ses bords ±X local (la course suit Z).
	Platform: (parent: Instance, size: Vector3, cframe: CFrame, name: string?) -> Part,
	-- Décor visible seulement tant que le monde est infecté / après son nettoyage (tags + World).
	Infected: (instance: Instance) -> (),
	Cleaned: (instance: Instance) -> (),
	-- Lampe comptée dans le budget (parent par défaut : Decor).
	Lamp: (position: Vector3, color: Color3, brightness: number, range: number, parent: Instance?) -> Part,
	-- Plaque + vide mortel (Cause "Void") sous tout le monde, trouée au coin d'entrée.
	Void: () -> (),
	-- Portique au nom du monde juste après l'entrée (facultatif).
	Entrance: () -> (),
	-- Salle du terminal standard (à appeler une fois) : checkpoint TerminalStage(n), MinigameTerminal,
	-- WorldGate, rampe vers l'entrée du monde suivant (+ Finish au dernier monde). Dans World{n}.Terminal.
	TerminalRoom: () -> Model,
}

function Common.NewContext(tower: Instance, world: Tower.World): (WorldContext, () -> ())
	local w = world.Index
	local base = worldBase(w)
	local style = Common.Style(world)
	local model = Build.Model(`World{w}`, tower)
	model:SetAttribute("World", w)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local coins = Build.Folder("Coins", model)
	local decor = Build.Folder("Decor", model)

	local first, terminalStage = Tower.FirstStage(w), Tower.TerminalStage(w)
	local terminalFrame = cornerFrame(terminalCorner(w))
	local terminalFloor = base + TERMINAL_FLOOR
	local entryFrame = cornerFrame(startCorner(w))
	local entryHouse = if w == 1
		then houseBox("StartRoom", entryFrame, 0.1, ENTRY - 0.1)
		else houseBox("PreviousTerminalRoom", entryFrame, base - BAND + TERMINAL_FLOOR, CLIMB)

	local stages: { [number]: Folder } = {}
	local coinCounts: { [number]: number } = {}
	local placed: { [number]: boolean } = {}
	local keys: { [number]: boolean } = {}
	local current: number? = nil
	local terminalBuilt = false
	local keyFolder: Folder? = nil

	local ctx: WorldContext
	ctx = {
		Def = world,
		Index = w,
		Model = model,
		Coins = coins,
		Decor = decor,
		Base = base,
		Band = BAND,
		Style = style,
		Entry = Common.EntryOf(w),
		Terminal = {
			Frame = terminalFrame,
			Floor = terminalFloor,
			Roof = terminalFloor + CLIMB,
			Door = CFA(terminalFrame, -8, terminalFloor, 0),
		},
		Reserved = { entryHouse, houseBox("TerminalRoom", terminalFrame, terminalFloor, CLIMB) },

		Stage = function(stage: number): Folder
			assert(stage >= first and stage <= terminalStage, `monde {w} : étape {stage} hors du monde`)
			local folder = stages[stage]
			if not folder then
				folder = Build.Folder(`Stage{stage}`, model)
				stages[stage] = folder
			end
			current = stage
			return folder
		end,

		Checkpoint = function(stage: number, cframe: CFrame): Part
			assert(
				stage >= first and stage < terminalStage,
				`monde {w} : checkpoint {stage} hors de {first}..{terminalStage - 1} (le dernier est dans la salle)`
			)
			assert(not placed[stage], `monde {w} : checkpoint {stage} en double`)
			placed[stage] = true
			return Common.CheckpointPad(stage, cframe.Position, cframe.LookVector)
		end,

		Coin = function(position: Vector3, stage: number?): Part
			local s = stage or current
			assert(s ~= nil, `monde {w} : ctx.Coin sans étape (appeler ctx.Stage(s) ou passer stage)`)
			assert(s >= first and s <= terminalStage, `monde {w} : Bit de l'étape {s} hors du monde`)
			coinCounts[s] = (coinCounts[s] or 0) + 1
			local bit = Build.Decor({
				Name = "Bit",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 2.2,
				CFrame = CFrame.new(position),
				Color = BIT,
				Material = NEON,
				CastShadow = false,
				Tags = { "Coin" },
				Parent = coins,
			})
			bit.CanTouch = true
			bit:SetAttribute("CoinId", `S{s}C{coinCounts[s]}`)
			bit:SetAttribute("Stage", s)
			return bit
		end,

		UsbKey = function(position: Vector3, index: number): Part
			assert(
				index == math.floor(index) and index >= 1 and index <= Tower.USB_KEYS_PER_WORLD,
				`monde {w} : clé USB {index} hors de 1..{Tower.USB_KEYS_PER_WORLD}`
			)
			assert(not keys[index], `monde {w} : clé USB {index} en double`)
			keys[index] = true
			local folder = keyFolder or Build.Folder("UsbKeys", model)
			keyFolder = folder
			-- Clé penchée, qui brille : corps doré (pièce touchable), embout métal, deux fenêtres noires.
			local cf = CFrame.new(position) * CFrame.Angles(0, math.rad(35 * index), math.rad(20))
			local key = Build.Part({
				Name = `UsbKey{index}`,
				Size = Vector3.new(1.8, 0.8, 3.2),
				CFrame = cf,
				Color = USB_GOLD,
				Material = NEON,
				CastShadow = false,
				Tags = { "UsbKey" },
				Parent = folder,
			})
			key.CanCollide = false
			key.CanQuery = false
			key.CanTouch = true
			key:SetAttribute("KeyId", `W{w}K{index}`)
			key:SetAttribute("World", w)
			Box(key, "Plug", Vector3.new(1.3, 0.55, 1.4), cf * CFrame.new(0, 0, -2.25), C.Nickel, METAL)
			for _, x in { -0.3, 0.3 } do
				Box(key, "PlugHole", Vector3.new(0.3, 0.1, 0.4), cf * CFrame.new(x, 0.29, -2.5), C.Black)
			end
			Box(key, "Cap", Vector3.new(1.9, 0.9, 0.5), cf * CFrame.new(0, 0, 1.6), C.Gold, Enum.Material.Foil)
			-- Les détails suivent le corps quand le client le fait tourner (WorldFx).
			for _, child in key:GetChildren() do
				if child:IsA("BasePart") then
					child.CanTouch = false
					Props.WeldTo(key, child)
				end
			end
			return key
		end,

		Trap = function(kind: string, part: BasePart, attributes: { [string]: any }?)
			Common.MarkTrap(w, kind, part, attributes)
		end,

		Hazard = function(
			parent: Instance,
			name: string,
			size: Vector3,
			cframe: CFrame,
			color: Color3?,
			cause: string?
		): Part
			local part = Build.Part({
				Name = name,
				Size = size,
				CFrame = cframe,
				Color = color or LETHAL,
				Material = NEON,
				Transparency = 0.2,
				CastShadow = false,
				Parent = parent,
			})
			Common.MarkHazard(part, cause, w)
			return part
		end,

		Platform = function(parent: Instance, size: Vector3, cframe: CFrame, name: string?): Part
			local part = Build.Part({
				Name = name or "Platform",
				Size = size,
				CFrame = cframe,
				Color = style.Floor,
				Material = style.FloorMat,
				Parent = parent,
			})
			-- Liserés lumineux sur les bords latéraux : on voit où la plateforme s'arrête.
			for _, side in { -1, 1 } do
				Build.Neon({
					Name = "Rim",
					Size = Vector3.new(0.4, 0.4, size.Z),
					CFrame = cframe * CFrame.new(side * size.X / 2, size.Y / 2 - 0.15, 0),
					Color = style.Edge,
					Transparency = 0.25,
					Parent = part,
				})
			end
			return part
		end,

		Infected = function(instance: Instance)
			instance:AddTag("Infected")
			instance:SetAttribute("World", w)
		end,

		Cleaned = function(instance: Instance)
			instance:AddTag("Cleaned")
			instance:SetAttribute("World", w)
		end,

		Lamp = function(position: Vector3, color: Color3, brightness: number, range: number, parent: Instance?): Part
			return Common.Lamp(parent or decor, position, color, brightness, range)
		end,

		Void = function()
			-- Monde 1 : la plaque est posée sur le bureau (fine, pour éviter le z-fighting avec lui)
			local top = if w == 1 then 0.3 else base
			local thickness = if w == 1 then 0.3 else 2
			for i, r in floorRects(startCorner(w)) do
				local sx, sz = r[2] - r[1], r[4] - r[3]
				local center = Vector3.new((r[1] + r[2]) / 2, top, (r[3] + r[4]) / 2)
				Build.Part({
					Name = "Shelf",
					Size = Vector3.new(sx, thickness, sz),
					CFrame = CFrame.new(center - Vector3.new(0, thickness / 2, 0)),
					Color = C.PcbDark,
					Material = SMOOTH,
					CastShadow = false,
					Parent = decor,
				})
				local void = ctx.Hazard(
					decor,
					if i == 1 then "Void" else "VoidB",
					Vector3.new(sx, 1.5, sz),
					CFrame.new(center + Vector3.new(0, 0.75, 0)),
					VOID,
					"Void"
				)
				void.Transparency = 0.45
			end
		end,

		Entrance = function()
			local fr = sideFrame(startCorner(w))
			local y = base + ENTRY
			for _, v in { -13, 13 } do
				local size, cf = span(fr, 9, 13, base, y + 28, v - 2, v + 2)
				Build.Part({
					Name = "GantryPillar",
					Size = size,
					CFrame = cf,
					Color = style.Wall,
					Material = METAL,
					CanCollide = false,
					Parent = decor,
				})
			end
			local size, cf = span(fr, 9.5, 12.5, y + 13, y + 28, -15, 15)
			local panel = Box(decor, "WorldNameWall", size, cf, C.Bg, METAL)
			panel.CastShadow = true
			-- Le joueur arrive par l'arrière du panneau (face Back = -LookVector)
			Props.Sign(
				panel,
				`MONDE {w} · {string.upper(world.Name)}`,
				`{world.Component}  —  AngAInOne : {world.AppSection}`,
				style.Primary,
				C.White,
				Enum.NormalId.Back
			)
			for _, yy in { y + 12.6, y + 28.4 } do
				local tsize, tcf = span(fr, 9.3, 12.7, yy - 0.4, yy + 0.4, -15.2, 15.2)
				Build.Neon({ Name = "WallTrim", Size = tsize, CFrame = tcf, Color = style.Primary, Parent = decor })
			end
			Common.Lamp(decor, P(fr, 4, y + 10, 0), style.Primary:Lerp(C.White, 0.4), 1.4, 40)
		end,

		TerminalRoom = function(): Model
			assert(not terminalBuilt, `monde {w} : salle du terminal en double`)
			terminalBuilt = true
			local terminal = Build.Folder("Terminal", model)
			local room = Common.House(terminalFrame, terminalFloor, CLIMB, {
				World = world,
				Style = style,
				Parent = terminal,
			})
			if w == Tower.WORLD_COUNT then
				buildFinish(terminal, terminalFrame, terminalFloor + CLIMB)
			end
			return room
		end,
	}

	-- Vérifie le contrat une fois le monde construit (erreur claire pour l'auteur du monde).
	local function finish()
		assert(terminalBuilt, `monde {w} : ctx.TerminalRoom() n'a pas été appelé`)
		for s = first, terminalStage - 1 do
			assert(placed[s], `monde {w} : checkpoint {s} manquant (ctx.Checkpoint)`)
		end
	end
	return ctx, finish
end

return table.freeze(Common)
