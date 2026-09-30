--!strict
--[[
	TowerBuilder : construit toute la tour PC verticale du deathrun (Workspace.Tower).

	Disposition (vue de dessus, la façade avant regarde -Z, le lobby est posé devant sur le bureau) :
	- Intérieur de la tour : X, Z ∈ [-132, 132], parois de 6 studs ; vitre latérale côté +X.
	- Le parcours tourne le long d'un anneau carré (axe à ±88) : chaque ÉTAPE = un côté de 176 studs
	  entre deux coins, qui monte de RISE studs. Un monde = 5 côtés (1,25 tour) dans sa tranche de
	  hauteur BAND ; le monde w commence au coin (w - 1) % 4.
	- Chaque coin porte le checkpoint de l'étape qui s'y termine (pad 12×1×12, LookVector = suite).
	- La 5ᵉ étape entre dans la « maison du terminal » du coin suivant : salle sûre (pad, terminal
	  antivirus, portail WorldGate) puis rampe fermée qui monte sur le toit = départ du monde suivant.
	- Sous chaque monde : une plaque (PCB) recouverte d'un vide mortel (Hazard, Cause = "Void"),
	  trouée à l'emplacement de la maison du terminal qui la traverse.
	- Sommet : sur le toit de la maison du monde 7, le cœur du virus vaincu (tag Finish).

	Contrat (voir Config/Tower) :
	Workspace.Tower
	├─ Lobby        (Model, Persistent) LobbySpawn, AppScreen, LeaderboardScreen×3 (Board),
	│                TitleHologram, bornes Shop/Arcade/Daily (prompt Action), AngaSpot, porte d'entrée
	├─ Checkpoints  pads tag Checkpoint, attribut Stage (0 = entrée du parcours, dans le lobby)
	├─ Shell        (Model, Persistent) parois, vitre, ventilateurs de façade
	└─ World1..7    (Model, Atomic, attribut World)
	     ├─ Stage{s}   plateformes + pièges (tag Trap, attribut Kind + paramètres)
	     ├─ Coins      orbes « Bit » (tag Coin, attribut CoinId unique)
	     ├─ Terminal   maison du terminal : MinigameTerminal, WorldGate (+ Finish au monde 7)
	     └─ Decor      composant géant, vide mortel (tag Hazard), panneaux

	Attributs des pièges (animés côté client par TrapController à partir de GetServerTimeNow) :
	- Offset / Direction : Vector3 en coordonnées MONDE (studs). Axis : "X" | "Y" | "Z" (axe LOCAL).
	- Phase : fraction de période (ou de tour pour SpinBar, de boucle pour Virus), dans [0, 1[.
	- Waypoints (Virus) : chaîne "x,y,z;x,y,z;…" = décalages MONDE relatifs à la position de repos
	  (le premier point vaut 0,0,0) ; la patrouille boucle sur les points (aller-retour si 2 points).
	Les pièges mortels sont non solides (CanCollide false) : le client détecte le contact lui-même.

	Budget : ≤ 8000 BaseParts, ≤ 90 PointLights (tests/tower.spec.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)

local TowerBuilder = {}

------------------------------------------------------------------------------------
-- Dimensions
------------------------------------------------------------------------------------

local INNER = 132 -- demi-largeur intérieure de la tour
local WALL = 6 -- épaisseur des parois
local RING = 88 -- demi-côté de l'anneau du parcours (axe des plateformes)
local SIDE = RING * 2 -- longueur d'un côté (coin à coin)
local BAND = 100 -- hauteur d'un monde
local ENTRY = 10 -- hauteur du départ d'un monde au-dessus de son vide
local RISE = 14 -- montée d'une étape
local CLIMB = BAND - Tower.STAGES_PER_WORLD * RISE -- rampe de la maison du terminal (30)
local CORNER = 8 -- demi-côté d'une plateforme de coin
local JUNCTION = 6 -- palier entre deux modules
local MODULE_L = 34 -- longueur d'un module d'obstacles
local TOP = BAND * Tower.WORLD_COUNT + 50 -- plafond de la tour
local TOTAL = Tower.TOTAL_STAGES

TowerBuilder.Dimensions = table.freeze({
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

-- Code couleur (règle d'or : ce qui tue est rouge / magenta néon ; le reste n'est jamais rouge)
local LETHAL = Color3.fromRGB(255, 46, 84)
local GLITCH = Color3.fromRGB(232, 52, 214)
local HEAT = Color3.fromRGB(255, 78, 52)
local VOID = Color3.fromRGB(128, 20, 90)
local SAFE = Color3.fromRGB(79, 209, 197)
local SPRING = Color3.fromRGB(104, 224, 140)
local BIT = Color3.fromRGB(246, 196, 83)

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local function frac(x: number): number
	return x - math.floor(x)
end

------------------------------------------------------------------------------------
-- Repères
------------------------------------------------------------------------------------

-- Repère d'un côté : O = coin de départ (y = 0), F = sens de la course, R = vers le centre.
-- Coordonnées locales : u le long de F, v le long de R, y absolu.
type Frame = { O: Vector3, F: Vector3, R: Vector3 }

local CORNERS = {
	Vector3.new(-RING, 0, -RING),
	Vector3.new(RING, 0, -RING),
	Vector3.new(RING, 0, RING),
	Vector3.new(-RING, 0, RING),
}

local function corner(i: number): Vector3
	return CORNERS[(i % 4) + 1]
end

local function frameOf(origin: Vector3, forward: Vector3): Frame
	return { O = origin, F = forward, R = forward:Cross(UP) }
end

-- Côté du coin i vers le coin i + 1.
local function sideFrame(i: number): Frame
	return frameOf(corner(i), (corner(i + 1) - corner(i)).Unit)
end

-- Repère d'un coin : F = direction d'arrivée (depuis le coin i - 1), R = direction de départ.
-- a = distance au-delà du coin (vers la paroi), b = distance le long du départ (b < 0 : dehors).
local function cornerFrame(i: number): Frame
	return frameOf(corner(i), (corner(i) - corner(i - 1)).Unit)
end

local function P(fr: Frame, u: number, y: number, v: number): Vector3
	return fr.O + fr.F * u + fr.R * v + Vector3.new(0, y, 0)
end

-- CFrame dont le LookVector est F (X local = R, Y = haut).
local function CFA(fr: Frame, u: number, y: number, v: number): CFrame
	return CFrame.fromMatrix(P(fr, u, y, v), fr.R, UP, -fr.F)
end

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

-- CFrame posé en `position`, LookVector horizontal `look`.
local function facing(position: Vector3, look: Vector3): CFrame
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	return CFrame.fromMatrix(position, flat:Cross(UP), UP, -flat)
end

local function worldBase(w: number): number
	return (w - 1) * BAND
end

local function startCorner(w: number): number
	return (w - 1) % 4
end

-- Hauteur (dessus) du checkpoint de l'étape s (1..TOTAL).
local function stageHeight(s: number): number
	local w = Tower.WorldOf(s)
	local j = s - Tower.FirstStage(w) + 1
	return worldBase(w) + ENTRY + RISE * j
end
TowerBuilder.StageHeight = stageHeight

------------------------------------------------------------------------------------
-- Style par monde
------------------------------------------------------------------------------------

type Style = {
	Floor: Color3,
	FloorMat: Enum.Material,
	Edge: Color3,
	Primary: Color3,
	Secondary: Color3,
	Wall: Color3,
}

local function style(world: Tower.World): Style
	local primary, secondary = hex(world.Primary), hex(world.Secondary)
	local floors: { [string]: { any } } = {
		PSU = { C.MetalLight, Enum.Material.DiamondPlate, Color3.fromRGB(40, 40, 48) },
		RAM = { Color3.fromRGB(46, 104, 92), SMOOTH, Color3.fromRGB(30, 34, 56) },
		SSD = { Color3.fromRGB(40, 92, 104), SMOOTH, Color3.fromRGB(24, 44, 52) },
		Cooling = { Color3.fromRGB(176, 214, 236), Enum.Material.Glacier, Color3.fromRGB(40, 60, 84) },
		CPU = { Color3.fromRGB(176, 150, 92), METAL, Color3.fromRGB(56, 50, 40) },
		GPU = { Color3.fromRGB(78, 86, 104), METAL, Color3.fromRGB(26, 36, 32) },
		AI = { Color3.fromRGB(92, 76, 140), SMOOTH, Color3.fromRGB(36, 28, 58) },
	}
	local f = floors[world.Id] or floors.PSU
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
-- Contexte de construction
------------------------------------------------------------------------------------

type Ctx = {
	World: Tower.World,
	W: number,
	Style: Style,
	Model: Model,
	Coins: Folder,
	Decor: Folder,
	Stage: number,
	K: number, -- difficulté 0..1 sur toute la tour
	Folder: Folder, -- pièces de l'étape en cours
	CoinCount: number,
}

type Mod = { Ctx: Ctx, Fr: Frame, U: number, Y: number }

local lights = { 0 }

local function lamp(parent: Instance, position: Vector3, color: Color3, brightness: number, range: number)
	local anchor = Box(parent, "Lamp", Vector3.one, CFrame.new(position), color)
	anchor.Transparency = 1
	Build.PointLight(anchor, color, brightness, range)
	lights[1] += 1
end

-- Plateforme solide du module : u, v relatifs au module, dessus à Y + dy.
local function plat(m: Mod, u0: number, u1: number, v0: number, v1: number, dy: number, name: string?): Part
	local s = m.Ctx.Style
	local size, cf = span(m.Fr, m.U + u0, m.U + u1, m.Y + dy - 2, m.Y + dy, v0, v1)
	local part = Build.Part({
		Name = name or "Platform",
		Size = size,
		CFrame = cf,
		Color = s.Floor,
		Material = s.FloorMat,
		Parent = m.Ctx.Folder,
	})
	-- Liserés lumineux sur les bords latéraux : on voit où la plateforme s'arrête.
	for _, v in { v0, v1 } do
		local tsize, tcf = span(m.Fr, m.U + u0, m.U + u1, m.Y + dy - 0.35, m.Y + dy + 0.05, v - 0.2, v + 0.2)
		Build.Neon({ Name = "Rim", Size = tsize, CFrame = tcf, Color = s.Edge, Transparency = 0.25, Parent = part })
	end
	return part
end

local function coin(ctx: Ctx, position: Vector3)
	ctx.CoinCount += 1
	local bit = Build.Decor({
		Name = "Bit",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.2,
		CFrame = CFrame.new(position),
		Color = BIT,
		Material = NEON,
		CastShadow = false,
		Tags = { "Coin" },
		Parent = ctx.Coins,
	})
	bit.CanTouch = true
	bit:SetAttribute("CoinId", `S{ctx.Stage}C{ctx.CoinCount}`)
	bit:SetAttribute("Stage", ctx.Stage)
end

local function mcoin(m: Mod, u: number, dy: number, v: number)
	coin(m.Ctx, P(m.Fr, m.U + u, m.Y + dy, v))
end

-- Piège animé côté client. Les pièges mortels sont non solides ; les plateformes le sont.
local function trap(
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
		Tags = { "Trap" },
		Parent = parent,
	})
	part.CanCollide = collide == true
	part.CanQuery = collide == true
	part.CanTouch = true
	part:SetAttribute("Kind", kind)
	for key, value in attributes do
		part:SetAttribute(key, value)
	end
	return part
end

-- Danger statique (liquide de court-circuit, bloc glitch, vide) : non solide, tag Hazard.
local function hazard(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, cause: string): Part
	local part = Build.Part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = NEON,
		Transparency = 0.2,
		CastShadow = false,
		Tags = { "Hazard" },
		Parent = parent,
	})
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = true
	part:SetAttribute("Cause", cause)
	return part
end

-- Pièce décorative soudée à un piège (bouge avec lui).
local function attach(root: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local part = Box(root, name, size, cf, color, material)
	Props.WeldTo(root, part)
	return part
end

local function phaseOf(ctx: Ctx, i: number): number
	return frac(ctx.Stage * 0.37 + i * 0.22)
end

------------------------------------------------------------------------------------
-- Modules d'obstacles (34 studs de long, entrée et sortie à la hauteur Y ; renvoient leur montée)
------------------------------------------------------------------------------------

-- Sauts entre plateformes (écarts de 3 à 6,5 studs selon la difficulté).
local function mHop(m: Mod): number
	local k = m.Ctx.K
	local gap = 3 + 3.5 * k
	local n, len = 3, (MODULE_L - 4 * gap) / 3
	if len < 6 then
		n, len = 2, (MODULE_L - 3 * gap) / 2
	end
	local u = gap
	for i = 1, n do
		local dv = (if i % 2 == 0 then 1 else -1) * 2 * k
		plat(m, u, u + len, dv - 5, dv + 5, if i % 2 == 0 then 1.5 else 0)
		u += len + gap
	end
	mcoin(m, gap + len + gap / 2, 3.5, 0)
	return 0
end

-- Couloir de décharges : arcs électriques temporisés entre deux pylônes.
local function mZapper(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -6, 6, 0)
	local n = if k > 0.35 then 3 else 2
	local period = 3 - 0.6 * k
	local duty = 0.42 + 0.08 * k
	for i = 1, n do
		local u = MODULE_L * i / (n + 1)
		for _, v in { -6.9, 6.9 } do
			Rod(ctx.Folder, "Pylon", CFA(m.Fr, m.U + u, m.Y + 5, v) * VERTICAL, 10, 1.6, C.MetalDark)
			Build.Neon({
				Name = "PylonCap",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 2.2,
				CFrame = CFA(m.Fr, m.U + u, m.Y + 10.4, v),
				Color = LETHAL,
				Transparency = 0.15,
				Parent = ctx.Folder,
			})
		end
		local size, cf = span(m.Fr, m.U + u - 0.3, m.U + u + 0.3, m.Y, m.Y + 9.5, -6.4, 6.4)
		trap(ctx.Folder, "Zapper", "Arc", size, cf, LETHAL, NEON, {
			Period = period,
			Duty = duty,
			Phase = frac(phaseOf(ctx, 0) + (i - 1) * 0.22),
		}).Transparency =
			0.3
	end
	mcoin(m, MODULE_L * 1.5 / (n + 1), 2.5, 3.5)
	return 0
end

-- Liquide de court-circuit dans des tranchées (à sauter), statique.
local function mLiquid(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	local pools = if k > 0.3 then 3 else 2
	local pool = 3 + 2 * k
	local piece = (MODULE_L - pools * pool) / (pools + 1)
	local u = 0
	for i = 1, pools + 1 do
		plat(m, u, u + piece, -6, 6, 0)
		u += piece
		if i <= pools then
			local size, cf = span(m.Fr, m.U + u, m.U + u + pool, m.Y - 2.2, m.Y - 0.8, -6, 6)
			hazard(ctx.Folder, "ShortCircuit", size, cf, LETHAL, "Hazard")
			if i == 2 then
				mcoin(m, u + pool / 2, 3.2, 0)
			end
			u += pool
		end
	end
	return 0
end

-- Trampoline condensateur : propulse sur une corniche 9 studs plus haut (infranchissable sans lui).
local function mBounce(m: Mod): number
	local ctx = m.Ctx
	plat(m, 0, 13, -6, 6, 0)
	local size, cf = span(m.Fr, m.U + 13, m.U + 21, m.Y - 1.6, m.Y + 0.4, -4, 4)
	local pad = trap(ctx.Folder, "Bounce", "Capacitor", size, cf, SPRING, SMOOTH, { Power = 80 }, true)
	attach(pad, "PadGlow", Vector3.new(6.4, 0.2, 6.4), cf * CFrame.new(0, 1.05, 0), SPRING, NEON).Transparency = 0.2
	-- Corps du condensateur sous le pad
	Rod(ctx.Folder, "CapBody", CFA(m.Fr, m.U + 17, m.Y - 8, 0) * VERTICAL, 14, 8.6, C.Black)
	Build.Neon({
		Name = "CapRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 9, 9),
		CFrame = CFA(m.Fr, m.U + 17, m.Y - 3, 0) * VERTICAL,
		Color = SPRING,
		Transparency = 0.3,
		Parent = ctx.Folder,
	})
	plat(m, 13, 21, -6, -4.5, -0.2, "PadSide")
	plat(m, 13, 21, 4.5, 6, -0.2, "PadSide")
	local ledge = plat(m, 24, MODULE_L, -6, 6, 9, "Ledge")
	local wsize, wcf = span(m.Fr, m.U + 24, m.U + 24.6, m.Y, m.Y + 7, -6, 6)
	Box(ledge, "LedgeFace", wsize, wcf, m.Ctx.Style.Wall)
	mcoin(m, 21, 13, 0)
	return 9
end

-- Barre tournante au ras du sol : on saute par-dessus.
local function mSpin(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -8, 8, 0)
	local speed = 1.2 + 0.9 * k
	local dir = if ctx.Stage % 2 == 0 then -1 else 1
	local pivots: { number } = if k > 0.5 then { 9, 25 } else { 17 }
	for i, u in pivots do
		local length = if #pivots == 2 then 14 else 15
		Rod(ctx.Folder, "Hub", CFA(m.Fr, m.U + u, m.Y + 1, 0) * VERTICAL, 2.2, 2.4, C.MetalDark)
		trap(
			ctx.Folder,
			"SpinBar",
			"Blade",
			Vector3.new(length, 1.2, 1.2),
			CFA(m.Fr, m.U + u, m.Y + 1.3, 0),
			LETHAL,
			NEON,
			{ Speed = speed * dir * (if i == 2 then -1 else 1), Axis = "Y", Phase = phaseOf(ctx, i) }
		)
	end
	mcoin(m, pivots[1], 4, 6)
	return 0
end

-- Barrettes de RAM qui s'écrasent (de haut en bas) en rythme.
local function mCrusher(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -6, 6, 0)
	local period = 3.4 - 0.6 * k
	for i, u in { 7, 17, 27 } do
		for _, v in { -7.2, 7.2 } do
			local size, cf = span(m.Fr, m.U + u - 1, m.U + u + 1, m.Y, m.Y + 22, v - 0.6, v + 0.6)
			Box(ctx.Folder, "Rail", size, cf, C.MetalLight, METAL)
		end
		local size, cf = span(m.Fr, m.U + u - 2, m.U + u + 2, m.Y + 13, m.Y + 21, -6.2, 6.2)
		local stick = trap(ctx.Folder, "Crusher", "RamStick", size, cf, Color3.fromRGB(150, 36, 96), SMOOTH, {
			Offset = Vector3.new(0, -13, 0),
			Period = period,
			Phase = frac(phaseOf(ctx, 0) + i * 0.3),
		})
		attach(stick, "Edge", Vector3.new(12.4, 0.6, 4.2), cf * CFrame.new(0, -3.8, 0), LETHAL, NEON)
		attach(stick, "Heatsink", Vector3.new(12.6, 2, 4.4), cf * CFrame.new(0, 3, 0), C.MetalDark, METAL)
	end
	mcoin(m, 12, 2.5, 0)
	return 0
end

-- Pistons latéraux (SSD) : des blocs sortent des côtés et balaient toute la largeur.
local function mPistons(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -6, 6, 0)
	local period = 3.4 - 0.6 * k
	for i, u in { 8, 17, 26 } do
		local side = if i % 2 == 0 then 1 else -1
		local size, cf = span(m.Fr, m.U + u - 2, m.U + u + 2, m.Y, m.Y + 8.5, side * 6.6, side * 18.6)
		local block = trap(ctx.Folder, "Crusher", "Piston", size, cf, Color3.fromRGB(150, 36, 96), SMOOTH, {
			Offset = m.Fr.R * (-side * 12.4),
			Period = period,
			Phase = frac(phaseOf(ctx, 1) + i * 0.33),
		})
		attach(block, "Edge", Vector3.new(0.6, 8.6, 4.2), cf * CFrame.new(-side * 5.8, 0, 0), LETHAL, NEON)
		local hsize, hcf = span(m.Fr, m.U + u - 3, m.U + u + 3, m.Y - 1, m.Y + 10, side * 18.6, side * 20.6)
		Box(ctx.Folder, "Housing", hsize, hcf, C.MetalDark, METAL)
	end
	mcoin(m, 12.5, 2.5, 0)
	return 0
end

-- Tapis de données qui ramène en arrière (+ une barrette qui écrase au monde de la RAM).
local function mConveyor(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	local speed = 5 + 4 * k
	local size, cf = span(m.Fr, m.U, m.U + MODULE_L, m.Y - 2, m.Y, -5, 5)
	trap(ctx.Folder, "Conveyor", "DataBelt", size, cf, Color3.fromRGB(34, 40, 56), SMOOTH, {
		Direction = -m.Fr.F,
		Speed = speed,
	}, true)
	for _, v in { -5.4, 5.4 } do
		local rsize, rcf = span(m.Fr, m.U, m.U + MODULE_L, m.Y - 2.2, m.Y + 0.4, v - 0.4, v + 0.4)
		Box(ctx.Folder, "BeltRail", rsize, rcf, C.MetalLight, METAL)
	end
	-- Chevrons lumineux dans le sens du tapis (vers l'arrière)
	for u = 5, MODULE_L - 3, 7 do
		for _, side in { -1, 1 } do
			Build.Neon({
				Name = "Chevron",
				Size = Vector3.new(0.5, 0.1, 4.2),
				CFrame = CFA(m.Fr, m.U + u, m.Y + 0.06, side * 1.5) * CFrame.Angles(0, side * math.rad(-40), 0),
				Color = SAFE,
				Transparency = 0.2,
				Parent = ctx.Folder,
			})
		end
	end
	if ctx.World.Id == "RAM" and k > 0.1 then
		local csize, ccf = span(m.Fr, m.U + 15, m.U + 19, m.Y + 13, m.Y + 21, -5.2, 5.2)
		local stick = trap(ctx.Folder, "Crusher", "RamStick", csize, ccf, Color3.fromRGB(150, 36, 96), SMOOTH, {
			Offset = Vector3.new(0, -13, 0),
			Period = 3.2,
			Phase = phaseOf(ctx, 3),
		})
		attach(stick, "Edge", Vector3.new(10.4, 0.6, 4.2), ccf * CFrame.new(0, -3.8, 0), LETHAL, NEON)
		for _, v in { -6.2, 6.2 } do
			local rsize, rcf = span(m.Fr, m.U + 16, m.U + 18, m.Y, m.Y + 22, v - 0.6, v + 0.6)
			Box(ctx.Folder, "Rail", rsize, rcf, C.MetalLight, METAL)
		end
	elseif ctx.World.Id ~= "RAM" then
		-- Blocs glitch sur le flux de données : il faut slalomer à contre-courant.
		for i, u in { 11, 24 } do
			local v = if i == 1 then -2.4 else 2.4
			local gsize, gcf = span(m.Fr, m.U + u - 1.5, m.U + u + 1.5, m.Y, m.Y + 5, v - 2.2, v + 2.2)
			hazard(ctx.Folder, "GlitchBlock", gsize, gcf, GLITCH, "Hazard")
		end
	end
	mcoin(m, 26, 2.5, if ctx.World.Id == "RAM" then 3 else -3)
	return 0
end

-- Plateforme mobile qui fait traverser un grand trou.
local function mMover(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, 4, -6, 6, 0)
	plat(m, 30, MODULE_L, -6, 6, 0)
	local size, cf = span(m.Fr, m.U + 4.2, m.U + 13.8, m.Y - 1.6, m.Y, -5, 5)
	local mover = trap(ctx.Folder, "Mover", "Shuttle", size, cf, C.MetalLight, METAL, {
		Offset = m.Fr.F * 16,
		Period = 7.2 - 1.2 * k,
		Phase = phaseOf(ctx, 2),
	}, true)
	for _, v in { -4.8, 4.8 } do
		attach(mover, "ShuttleGlow", Vector3.new(0.4, 0.3, 9.6), cf * CFrame.new(v, 0.8, 0), SAFE, NEON)
	end
	attach(mover, "Thruster", Vector3.new(6, 1.2, 6), cf * CFrame.new(0, -1.4, 0), C.MetalDark, METAL)
	mcoin(m, 17, 4.5, 0)
	return 0
end

-- Blocs NAND qui s'effacent après contact puis reviennent.
local function mVanish(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	local gap = 2 + 2 * k
	local len = (MODULE_L - 4 * gap) / 3
	local icy = ctx.World.Id == "Cooling"
	local u = gap
	for i = 1, 3 do
		local size, cf = span(m.Fr, m.U + u, m.U + u + len, m.Y - 2, m.Y, -5, 5)
		local block = trap(
			ctx.Folder,
			"Vanish",
			if icy then "FrozenBlock" else "NandBlock",
			size,
			cf,
			if icy then Color3.fromRGB(190, 232, 255) else Color3.fromRGB(56, 178, 172),
			if icy then Enum.Material.Ice else SMOOTH,
			{ Delay = 1 - 0.3 * k, Respawn = 3 },
			true
		)
		attach(block, "Chip", Vector3.new(6, 0.2, math.max(len - 2, 1)), cf * CFrame.new(0, 1.05, 0), C.Bg)
		if i == 2 then
			mcoin(m, u + len / 2, 2.5, 0)
		end
		u += len + gap
	end
	return 0
end

-- Pont étroit balayé par le vent de ventilateurs (vers le vide) ; muret de protection troué.
local function mWind(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -4, 4, 0)
	-- Muret côté vide (-R) : plein au début, troué quand la difficulté monte.
	local gaps: { { number } } = if k > 0.4 then { { 9, 15 }, { 21, 27 } } else {}
	local u = 0
	for _, g in gaps do
		local size, cf = span(m.Fr, m.U + u, m.U + g[1], m.Y, m.Y + 2, -4.8, -4)
		Build.Part({
			Name = "Curb",
			Size = size,
			CFrame = cf,
			Color = C.Aluminum,
			Material = METAL,
			Parent = ctx.Folder,
		})
		u = g[2]
	end
	local size, cf = span(m.Fr, m.U + u, m.U + MODULE_L, m.Y, m.Y + 2, -4.8, -4)
	Build.Part({ Name = "Curb", Size = size, CFrame = cf, Color = C.Aluminum, Material = METAL, Parent = ctx.Folder })
	-- Zone de vent : LookVector = direction du souffle
	local center = P(m.Fr, m.U + MODULE_L / 2, m.Y + 6, -1)
	local attributes: { [string]: any } = { Direction = -m.Fr.R, Strength = 5 + 5 * k }
	if k > 0.45 then
		attributes.Period = 3.2
		attributes.Duty = 0.6
		attributes.Phase = phaseOf(ctx, 4)
	end
	local zone = trap(
		ctx.Folder,
		"Wind",
		"WindZone",
		Vector3.new(MODULE_L, 12, 16),
		facing(center, -m.Fr.R),
		C.White,
		SMOOTH,
		attributes
	)
	zone.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Gust"
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Rate = 14
	emitter.Lifetime = NumberRange.new(0.6, 0.9)
	emitter.Speed = NumberRange.new(24, 32)
	emitter.Size = NumberSequence.new(0.25)
	emitter.Transparency = NumberSequence.new(0.5)
	emitter.LightEmission = 0.6
	emitter.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	emitter.Parent = zone
	-- Ventilateurs côté centre, soufflant vers le vide
	for _, fu in { 9, 25 } do
		local base = P(m.Fr, m.U + fu, m.Y + 5.5, 12)
		Props.Fan(
			ctx.Folder,
			CFrame.fromMatrix(base, -m.Fr.R, UP),
			11,
			ctx.Style.Primary,
			7,
			{ Speed = 7, Lite = true }
		)
		local psize, pcf = span(m.Fr, m.U + fu - 0.8, m.U + fu + 0.8, m.Y - 30, m.Y - 0.5, 11, 12.6)
		Box(ctx.Folder, "FanMast", psize, pcf, C.MetalDark, METAL)
	end
	mcoin(m, 17, 2.5, -2.6)
	return 0
end

-- Grand ventilateur vertical en travers du chemin : on passe entre les pales.
local function mWindmill(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -6, 6, 0)
	local crossed = k > 0.5
	local speed = if crossed then 0.62 else 1.0 + 0.3 * k
	local dir = if ctx.Stage % 2 == 0 then 1 else -1
	local hubY = m.Y + 8.4
	for i = 1, if crossed then 2 else 1 do
		trap(
			ctx.Folder,
			"SpinBar",
			"FanBlade",
			Vector3.new(17.6, 1.6, 1.4),
			CFA(m.Fr, m.U + 17, hubY, 0),
			LETHAL,
			NEON,
			{ Speed = speed * dir, Axis = "Z", Phase = frac(phaseOf(ctx, 5) + (i - 1) * 0.25) }
		)
	end
	-- Cadre du ventilateur (U inversé hors du chemin) + moyeu
	for _, v in { -10.5, 10.5 } do
		local size, cf = span(m.Fr, m.U + 15.5, m.U + 18.5, m.Y - 2, m.Y + 19.5, v - 1, v + 1)
		Box(ctx.Folder, "FanFrame", size, cf, C.Black, METAL)
	end
	local tsize, tcf = span(m.Fr, m.U + 15.5, m.U + 18.5, m.Y + 18, m.Y + 20, -11.5, 11.5)
	Box(ctx.Folder, "FanFrame", tsize, tcf, C.Black, METAL)
	Props.Ring(
		ctx.Folder,
		"FanRing",
		CFrame.fromMatrix(P(m.Fr, m.U + 17.4, hubY, 0), m.Fr.F, UP),
		9.6,
		0.5,
		0.4,
		16,
		ctx.Style.Primary,
		NEON
	)
	Rod(ctx.Folder, "Hub", CFrame.fromMatrix(P(m.Fr, m.U + 18.2, hubY, 0), m.Fr.F, UP), 1.4, 3, C.MetalDark)
	mcoin(m, 25, 2.5, -4)
	return 0
end

-- Laser qui balaie le sol (à sauter) + rideau laser latéral quand la difficulté monte.
local function mLaser(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -6, 6, 0)
	for _, v in { -6.6, 6.6 } do
		local size, cf = span(m.Fr, m.U + 2, m.U + MODULE_L - 2, m.Y, m.Y + 1, v - 0.5, v + 0.5)
		Box(ctx.Folder, "LaserTrack", size, cf, C.MetalDark, METAL)
	end
	local cf = CFA(m.Fr, m.U + 4, m.Y + 1.4, 0)
	local beam = trap(ctx.Folder, "Laser", "Beam", Vector3.new(12.6, 0.5, 0.5), cf, LETHAL, NEON, {
		Offset = m.Fr.F * 26,
		Period = 4.4 - 1.0 * k,
		Phase = phaseOf(ctx, 6),
	})
	for _, v in { -6.8, 6.8 } do
		attach(beam, "Emitter", Vector3.new(1, 1.6, 1.6), cf * CFrame.new(v, 0, 0), C.Black, METAL)
	end
	if k > 0.4 then
		local vcf = CFA(m.Fr, m.U + 17, m.Y + 4.6, -5.6)
		local curtain = trap(ctx.Folder, "Laser", "Curtain", Vector3.new(0.5, 9, 0.5), vcf, LETHAL, NEON, {
			Offset = m.Fr.R * 11.2,
			Period = 3.4,
			Phase = phaseOf(ctx, 7),
		})
		attach(curtain, "Emitter", Vector3.new(1.4, 1, 1.4), vcf * CFrame.new(0, 4.9, 0), C.Black, METAL)
		local gsize, gcf = span(m.Fr, m.U + 16, m.U + 18, m.Y + 9.8, m.Y + 10.6, -7, 7)
		Box(ctx.Folder, "Gantry", gsize, gcf, C.MetalDark, METAL)
		for _, v in { -7.4, 7.4 } do
			local psize, pcf = span(m.Fr, m.U + 16.4, m.U + 17.6, m.Y, m.Y + 10.6, v - 0.6, v + 0.6)
			Box(ctx.Folder, "GantryLeg", psize, pcf, C.MetalDark, METAL)
		end
	end
	mcoin(m, 12, 2.5, 4)
	return 0
end

-- Bouches de chaleur en damier : deux couloirs qui soufflent en alternance.
local function mHeat(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -6, 6, 0)
	local period = 3 - 0.5 * k
	for row, u in { 7, 17, 27 } do
		for lane, v in { -3, 3 } do
			local size, cf = span(m.Fr, m.U + u - 2.2, m.U + u + 2.2, m.Y + 0.02, m.Y + 0.14, v - 2.7, v + 2.7)
			Build.Neon({
				Name = "Vent",
				Size = size,
				CFrame = cf,
				Color = HEAT,
				Transparency = 0.55,
				Parent = ctx.Folder,
			})
			local hsize, hcf = span(m.Fr, m.U + u - 2.2, m.U + u + 2.2, m.Y, m.Y + 10, v - 2.8, v + 2.8)
			trap(ctx.Folder, "Heat", "HeatColumn", hsize, hcf, HEAT, NEON, {
				Period = period,
				Duty = 0.45,
				Phase = frac(row * 0.18 + (lane - 1) * 0.5 + phaseOf(ctx, 8)),
			}).Transparency =
				0.45
		end
	end
	mcoin(m, 12, 2.5, 0)
	return 0
end

-- Virus gardiens qui patrouillent en travers du chemin.
local function mVirus(m: Mod): number
	local ctx, k = m.Ctx, m.Ctx.K
	plat(m, 0, MODULE_L, -8, 8, 0)
	local count = if k > 0.8 then 3 else 2
	for i = 1, count do
		local u = MODULE_L * i / (count + 1)
		local side = if i % 2 == 0 then 1 else -1
		local sweep = m.Fr.R * (-side * 12)
		local cf = CFA(m.Fr, m.U + u, m.Y + 2.4, side * 6)
		local virus = trap(ctx.Folder, "Virus", "Virus", Vector3.one * 4.4, cf, GLITCH, NEON, {
			Waypoints = string.format("0,0,0;%.2f,%.2f,%.2f", sweep.X, sweep.Y, sweep.Z),
			Speed = 7 + 5 * k,
			Phase = frac(i * 0.37),
		})
		virus.Shape = Enum.PartType.Ball
		for s = 0, 5 do
			local dir = if s < 2
				then CFrame.Angles(0, 0, s * math.pi)
				elseif s < 4 then CFrame.Angles(0, 0, math.pi / 2 + (s - 2) * math.pi)
				else CFrame.Angles(math.pi / 2 + (s - 4) * math.pi, 0, 0)
			attach(virus, "Spike", Vector3.new(0.8, 2.2, 0.8), cf * dir * CFrame.new(0, 2.6, 0), LETHAL, NEON)
		end
	end
	mcoin(m, MODULE_L / 2 + 2, 2.5, 0)
	return 0
end

-- Slalom entre des blocs glitch statiques.
local function mSlalom(m: Mod): number
	local ctx = m.Ctx
	plat(m, 0, MODULE_L, -7, 7, 0)
	for i, u in { 6, 14, 22, 30 } do
		local v = if i % 2 == 0 then 3.5 else -3.5
		local size, cf = span(m.Fr, m.U + u - 2, m.U + u + 2, m.Y, m.Y + 6, v - 2.5, v + 2.5)
		hazard(ctx.Folder, "GlitchBlock", size, cf, GLITCH, "Hazard")
	end
	mcoin(m, 18, 2.5, -4)
	return 0
end

local MODULES: { [string]: (Mod) -> number } = {
	Hop = mHop,
	Zapper = mZapper,
	Liquid = mLiquid,
	Bounce = mBounce,
	Spin = mSpin,
	Crusher = mCrusher,
	Pistons = mPistons,
	Conveyor = mConveyor,
	Mover = mMover,
	Vanish = mVanish,
	Wind = mWind,
	Windmill = mWindmill,
	Laser = mLaser,
	Heat = mHeat,
	Virus = mVirus,
	Slalom = mSlalom,
}

-- Réserve de modules par monde (tourne d'une étape à l'autre).
local POOLS: { [string]: { string } } = {
	PSU = { "Hop", "Zapper", "Liquid", "Bounce", "Spin" },
	RAM = { "Crusher", "Conveyor", "Mover", "Hop" },
	SSD = { "Vanish", "Pistons", "Conveyor", "Slalom", "Hop" },
	Cooling = { "Wind", "Windmill", "Vanish", "Hop" },
	CPU = { "Laser", "Heat", "Mover", "Hop" },
	GPU = { "Windmill", "Spin", "Laser", "Zapper" },
	AI = { "Virus", "Laser", "Mover", "Vanish", "Virus", "Pistons" },
}

local function moduleList(world: Tower.World, j: number): { string }
	local pool = POOLS[world.Id] or POOLS.PSU
	local list = {}
	for i = 1, 4 do
		table.insert(list, pool[((j - 1) * 3 + (i - 1)) % #pool + 1])
	end
	return list
end
TowerBuilder.ModuleList = moduleList

------------------------------------------------------------------------------------
-- Checkpoints, paliers, coins
------------------------------------------------------------------------------------

local checkpointsFolder: Folder? = nil

-- Pad de checkpoint : dessus à `top`, LookVector = `forward` (sens de la suite du parcours).
local function checkpoint(stage: number, position: Vector3, forward: Vector3, color: Color3): Part
	local cf = facing(position - Vector3.new(0, 0.5, 0), forward)
	local pad = Build.Part({
		Name = `Checkpoint{stage}`,
		Size = Vector3.new(12, 1, 12),
		CFrame = cf,
		Color = C.MetalDark,
		Material = METAL,
		Tags = { "Checkpoint" },
		Parent = checkpointsFolder,
	})
	pad.CanTouch = true
	pad:SetAttribute("Stage", stage)
	for k = 0, 3 do
		Build.Neon({
			Name = "Trim",
			Size = Vector3.new(12.2, 0.3, 0.6),
			CFrame = cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0.42, -5.8),
			Color = color,
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

-- Colonne de soutien décorative sous une plateforme (jusqu'au plancher du monde).
local function support(parent: Instance, position: Vector3, floorY: number, color: Color3)
	local height = position.Y - floorY
	if height > 1 then
		Rod(parent, "Support", CFrame.new(position.X, floorY + height / 2, position.Z) * VERTICAL, height, 2.6, color)
	end
end

local function buildCornerPlatform(ctx: Ctx, fr: Frame, y: number, stage: number)
	local size, cf = span(fr, SIDE - CORNER, SIDE + CORNER, y - 2, y, -CORNER, CORNER)
	local platform = Build.Part({
		Name = "CornerPlatform",
		Size = size,
		CFrame = cf,
		Color = ctx.Style.Floor,
		Material = ctx.Style.FloorMat,
		Parent = ctx.Folder,
	})
	for k = 0, 3 do
		Build.Neon({
			Name = "Rim",
			Size = Vector3.new(16, 0.4, 0.4),
			CFrame = CFA(fr, SIDE, y - 0.15, 0) * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -7.8),
			Color = ctx.Style.Edge,
			Transparency = 0.2,
			Parent = platform,
		})
	end
	checkpoint(stage, P(fr, SIDE, y + 0.4, 0), fr.R, SAFE)
	support(ctx.Decor, P(fr, SIDE, y - 2, 0), worldBase(ctx.W), ctx.Style.Wall)
	lamp(ctx.Decor, P(fr, SIDE, y + 16, 0), ctx.Style.Primary:Lerp(C.White, 0.5), 1.1, 44)
end

------------------------------------------------------------------------------------
-- Une étape = un côté de l'anneau
------------------------------------------------------------------------------------

local function buildSide(ctx: Ctx, j: number)
	local w = ctx.W
	local fr = sideFrame(startCorner(w) + j - 1)
	local y0 = worldBase(w) + ENTRY + RISE * (j - 1)
	local names = moduleList(ctx.World, j)

	-- Répartition de la montée : ce que les modules ne font pas se fait en 4 marches.
	local planned = 0
	for _, name in names do
		if name == "Bounce" then
			planned += 9
		end
	end
	local step = (RISE - planned) / 4

	local y = y0
	local u = CORNER
	for i, name in names do
		-- Palier (6 studs) : marche de `step` sauf avant le premier module
		if i > 1 then
			y += step
		end
		local jsize, jcf = span(fr, u, u + JUNCTION, y - 2, y, -6, 6)
		local junction = Build.Part({
			Name = "Junction",
			Size = jsize,
			CFrame = jcf,
			Color = ctx.Style.Floor:Lerp(C.White, 0.12),
			Material = ctx.Style.FloorMat,
			Parent = ctx.Folder,
		})
		local tsize, tcf = span(fr, u + JUNCTION - 0.3, u + JUNCTION, y - 0.3, y + 0.05, -6, 6)
		Build.Neon({ Name = "Edge", Size = tsize, CFrame = tcf, Color = ctx.Style.Edge, Parent = junction })
		support(ctx.Decor, P(fr, u + JUNCTION / 2, y - 2, 0), worldBase(w), ctx.Style.Wall)
		if i == 3 then
			coin(ctx, P(fr, u + JUNCTION / 2, y + 2.5, 4.5))
		end
		u += JUNCTION
		local rise = MODULES[name]({ Ctx = ctx, Fr = fr, U = u, Y = y })
		y += rise
		u += MODULE_L
	end
	y += step
	assert(math.abs(y - (y0 + RISE)) < 1e-6, "montée d'étape incohérente")
	if j < Tower.STAGES_PER_WORLD then
		buildCornerPlatform(ctx, fr, y, ctx.Stage)
	end
end

------------------------------------------------------------------------------------
-- Maison du terminal (fin de monde) et maison de départ (entrée du parcours)
------------------------------------------------------------------------------------

type HouseOptions = {
	World: Tower.World?, -- monde dont c'est la salle du terminal (nil = maison de départ)
	Style: Style,
	Parent: Instance,
}

--[[
	Coordonnées du repère de coin (cornerFrame) : a ∈ [-8, 44] (au-delà du coin jusqu'à la paroi),
	b ∈ [-44, 8] (du fond de la tour jusqu'au départ du côté suivant). Plancher à `y`.
	- Salle : a ∈ [-8, 29], porte d'arrivée dans le mur a = -8 (b ∈ [-6, 6]).
	- Cage d'escalier : a ∈ [30, 44], rampe de b = -38 (y) à b = 6 (y + climb) ; on y entre par
	  l'ouverture b ∈ [-44, -32] de la cloison a = 29..30, fermée par le portail (WorldGate).
	- Toit : dessus à y + climb = départ du monde suivant (trémie au-dessus du haut de la rampe).
]]
local function buildHouse(fr: Frame, y: number, climb: number, opts: HouseOptions): Model
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
		checkpoint(Tower.TerminalStage(w), P(fr, 0, y + 0.4, 0), P(fr, 12, 0, -36) - P(fr, 0, 0, 0), SAFE)
		lamp(model, P(fr, 10, y + 20, -18), C.White, 1.2, 50)
	end
	return model
end

------------------------------------------------------------------------------------
-- Entrée d'un monde : portique au nom du monde (+ section de l'app AngAInOne)
------------------------------------------------------------------------------------

local function buildEntrance(ctx: Ctx)
	local w = ctx.W
	local world = ctx.World
	local fr = sideFrame(startCorner(w))
	local y = worldBase(w) + ENTRY
	local parent = ctx.Decor
	for _, v in { -13, 13 } do
		local size, cf = span(fr, 9, 13, worldBase(w), y + 28, v - 2, v + 2)
		Build.Part({
			Name = "GantryPillar",
			Size = size,
			CFrame = cf,
			Color = ctx.Style.Wall,
			Material = METAL,
			CanCollide = false,
			Parent = parent,
		})
	end
	local size, cf = span(fr, 9.5, 12.5, y + 13, y + 28, -15, 15)
	local panel = Box(parent, "WorldNameWall", size, cf, C.Bg, METAL)
	panel.CastShadow = true
	-- Le joueur arrive par l'arrière du panneau (face Back = -LookVector)
	Props.Sign(
		panel,
		`MONDE {w} · {string.upper(world.Name)}`,
		`{world.Component}  —  AngAInOne : {world.AppSection}`,
		ctx.Style.Primary,
		C.White,
		Enum.NormalId.Back
	)
	for _, yy in { y + 12.6, y + 28.4 } do
		local tsize, tcf = span(fr, 9.3, 12.7, yy - 0.4, yy + 0.4, -15.2, 15.2)
		Build.Neon({ Name = "WallTrim", Size = tsize, CFrame = tcf, Color = ctx.Style.Primary, Parent = parent })
	end
	lamp(parent, P(fr, 4, y + 10, 0), ctx.Style.Primary:Lerp(C.White, 0.4), 1.4, 40)
end

------------------------------------------------------------------------------------
-- Plancher mortel d'un monde (troué à l'emplacement de la maison qui le traverse)
------------------------------------------------------------------------------------

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

local function buildFloor(ctx: Ctx)
	-- Monde 1 : la plaque est posée sur le bureau (fine, pour éviter le z-fighting avec lui)
	local top = if ctx.W == 1 then 0.3 else worldBase(ctx.W)
	local thickness = if ctx.W == 1 then 0.3 else 2
	for i, r in floorRects(startCorner(ctx.W)) do
		local sx, sz = r[2] - r[1], r[4] - r[3]
		local center = Vector3.new((r[1] + r[2]) / 2, top, (r[3] + r[4]) / 2)
		Build.Part({
			Name = "Shelf",
			Size = Vector3.new(sx, thickness, sz),
			CFrame = CFrame.new(center - Vector3.new(0, thickness / 2, 0)),
			Color = C.PcbDark,
			Material = SMOOTH,
			CastShadow = false,
			Parent = ctx.Decor,
		})
		local void = hazard(
			ctx.Decor,
			if i == 1 then "Void" else "VoidB",
			Vector3.new(sx, 1.5, sz),
			CFrame.new(center + Vector3.new(0, 0.75, 0)),
			VOID,
			"Void"
		)
		void.Transparency = 0.45
	end
end

------------------------------------------------------------------------------------
-- Décor mural : composants du thème accrochés aux 3 parois pleines (la 4ᵉ est la vitre)
------------------------------------------------------------------------------------

-- `cf` : sur la surface du mur, LookVector vers l'intérieur de la tour (-Z local = vers la salle).
local WALL_ITEMS: { [string]: (parent: Instance, cf: CFrame, p: Color3, s: Color3) -> () } = {
	PSU = function(parent, cf, p, _s)
		for i = -1, 1 do
			Rod(
				parent,
				"WallCable",
				cf * CFrame.new(i * 4.5, 0, -2.5) * VERTICAL,
				64,
				3.6,
				if i == 0 then p else C.Black,
				Enum.Material.Fabric
			)
		end
		for _, y in { -22, 22 } do
			Box(parent, "Clamp", Vector3.new(16, 2.4, 3), cf * CFrame.new(0, y, -1.6), C.Aluminum, METAL)
		end
		Props.Decal(
			parent,
			"WallLabel",
			Vector3.new(14, 5, 0.2),
			cf * CFrame.new(0, 12, -0.2),
			"12V",
			p,
			Enum.NormalId.Front,
			Enum.Font.GothamBlack
		)
	end,
	RAM = function(parent, cf, p, s)
		Box(parent, "WallSlot", Vector3.new(56, 3, 3), cf * CFrame.new(0, -8, -1.5), C.Black)
		for _, x in { -29, 29 } do
			Box(parent, "WallLatch", Vector3.new(2, 5, 3.4), cf * CFrame.new(x, -7, -1.7), C.White:Lerp(s, 0.3))
		end
		Box(parent, "WallStick", Vector3.new(52, 16, 1.2), cf * CFrame.new(0, 1.5, -1.5), C.PcbDark)
		for x = -18, 18, 12 do
			Box(parent, "WallChip", Vector3.new(8, 6, 0.8), cf * CFrame.new(x, 2, -2.4), C.Black)
		end
		Build.Neon({
			Name = "WallRgb",
			Size = Vector3.new(52, 1, 1.4),
			CFrame = cf * CFrame.new(0, 10, -1.5),
			Color = p,
			Parent = parent,
		})
	end,
	SSD = function(parent, cf, p, s)
		Box(parent, "WallM2", Vector3.new(50, 14, 1), cf * CFrame.new(0, 0, -1), C.Pcb:Lerp(p, 0.15))
		for x = -12, 16, 14 do
			Box(parent, "WallNand", Vector3.new(11, 9, 1), cf * CFrame.new(x, 0, -2), C.Black)
		end
		Box(parent, "WallController", Vector3.new(7, 7, 1), cf * CFrame.new(-19, 0, -2), C.Bg)
		Box(parent, "WallFingers", Vector3.new(3, 11, 1.2), cf * CFrame.new(-26, 0, -1), C.Gold, Enum.Material.Foil)
		Build.Neon({
			Name = "WallData",
			Size = Vector3.new(46, 0.6, 0.4),
			CFrame = cf * CFrame.new(0, -6, -2.1),
			Color = s,
			Parent = parent,
		})
	end,
	Cooling = function(parent, cf, p, _s)
		Props.Fins(parent, cf * CFrame.new(0, 0, -3) * CFrame.Angles(0, math.pi / 2, 0), 4, 30, 44, 11, C.Aluminum)
		for _, y in { -17, 17 } do
			Box(parent, "WallTank", Vector3.new(48, 4, 5), cf * CFrame.new(0, y, -2.5), C.Black, METAL)
		end
		Build.Neon({
			Name = "WallCoolant",
			Size = Vector3.new(1, 30, 1),
			CFrame = cf * CFrame.new(26, 0, -2),
			Color = p,
			Parent = parent,
		})
	end,
	CPU = function(parent, cf, p, _s)
		Box(parent, "WallVrm", Vector3.new(46, 10, 5), cf * CFrame.new(0, 6, -2.5), C.MetalDark, METAL)
		for x = -20, 20, 5 do
			Box(parent, "WallFin", Vector3.new(1.2, 6, 6), cf * CFrame.new(x, 13, -3), C.Aluminum, METAL)
		end
		for x = -18, 18, 12 do
			Box(parent, "WallChoke", Vector3.new(7, 7, 6), cf * CFrame.new(x, -6, -3), C.Black)
		end
		Build.Neon({
			Name = "WallTrace",
			Size = Vector3.new(46, 0.6, 0.4),
			CFrame = cf * CFrame.new(0, 0.5, -5.1),
			Color = p,
			Parent = parent,
		})
	end,
	GPU = function(parent, cf, _p, s)
		Box(parent, "WallBracket", Vector3.new(14, 40, 1.4), cf * CFrame.new(0, 0, -0.8), C.Aluminum, METAL)
		for y = -12, 12, 8 do
			Box(parent, "WallPort", Vector3.new(8, 4, 1.2), cf * CFrame.new(0, y, -1.8), C.Black)
		end
		for i = -1, 1 do
			Rod(parent, "WallPipe", cf * CFrame.new(16 + i * 4, 0, -2) * VERTICAL, 44, 2.6, C.Copper)
		end
		Build.Neon({
			Name = "WallRgb",
			Size = Vector3.new(1, 40, 0.6),
			CFrame = cf * CFrame.new(-9, 0, -1.2),
			Color = s,
			Parent = parent,
		})
	end,
	AI = function(parent, cf, p, s)
		for i, seg in { { -20, 0, 20, 0 }, { 0, 0, 0, 16 }, { 0, 16, 18, 16 }, { -20, 0, -20, -14 } } do
			local a, b = Vector3.new(seg[1], seg[2], -0.8), Vector3.new(seg[3], seg[4], -0.8)
			local mid = (a + b) / 2
			local len = (b - a).Magnitude
			local horizontal = seg[2] == seg[4]
			Build.Neon({
				Name = "WallCircuit",
				Size = if horizontal then Vector3.new(len + 1, 0.8, 0.6) else Vector3.new(0.8, len + 1, 0.6),
				CFrame = cf * CFrame.new(mid),
				Color = if i % 2 == 0 then p else s,
				Transparency = 0.15,
				Parent = parent,
			})
		end
		for _, node in { { 20, 0 }, { 18, 16 }, { -20, -14 } } do
			Build.Neon({
				Name = "WallNode",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 3.4,
				CFrame = cf * CFrame.new(node[1], node[2], -1.5),
				Color = p,
				Parent = parent,
			})
		end
	end,
}

local function buildWallDecor(ctx: Ctx)
	local base = worldBase(ctx.W)
	local item = WALL_ITEMS[ctx.World.Id]
	local p, s = ctx.Style.Primary, ctx.Style.Secondary
	-- Parois pleines : avant (-Z), arrière (+Z), gauche (-X). Normales vers l'intérieur.
	for index, normal in { Vector3.zAxis, -Vector3.zAxis, Vector3.xAxis } do
		for k, t in { -48, 0, 48 } do
			local along = normal:Cross(UP)
			local height = base + 44 + (if k == 2 then 12 else 0)
			local cf = facing(-normal * INNER + along * t + Vector3.new(0, height, 0), normal)
			if item then
				item(ctx.Decor, cf, p, s)
			end
			if k == 2 and index == 2 then
				-- Grand nom du monde sérigraphié sur la paroi du fond
				local label = Box(ctx.Decor, "WallName", Vector3.new(90, 14, 0.2), cf * CFrame.new(0, 26, -0.3), C.Bg)
				label.Transparency = 1
				Props.Sign(
					label,
					string.upper(ctx.World.Name),
					`{ctx.World.Component} · {ctx.World.AppSection}`,
					p,
					C.White
				)
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Décor : composant géant au centre + bandes lumineuses sur les parois
------------------------------------------------------------------------------------

local function buildHero(ctx: Ctx)
	local base = worldBase(ctx.W)
	local cf = CFrame.new(0, base, 0) * CFrame.Angles(0, math.pi, 0) -- face avant vers -Z
	local p, s = ctx.Style.Primary, ctx.Style.Secondary
	local id = ctx.World.Id
	local parent = ctx.Decor
	if id == "PSU" then
		Props.PowerSupply(parent, cf * CFrame.new(0, 1.5, 0), p, s)
		for _, x in { -40, 40 } do
			for _, z in { -52, 52 } do
				Props.Capacitor(parent, Vector3.new(x, base + 1.5, z), 7, 24, C.Black, p)
			end
		end
	elseif id == "RAM" then
		Props.RamKit(parent, cf * CFrame.new(0, 1.5, 0), 4, 96, 78, p, s)
	elseif id == "SSD" then
		Props.SsdStack(parent, cf, 3, p, s)
	elseif id == "Cooling" then
		Props.Radiator(parent, cf * CFrame.new(-10, 1.5, 0), p, s)
	elseif id == "CPU" then
		Props.CpuCooler(parent, cf * CFrame.new(0, 1.5, 0), p, s)
	elseif id == "GPU" then
		Props.GraphicsCard(parent, cf * CFrame.new(0, 1.5, 0), p, s)
	else
		Props.NeuralCore(parent, cf * CFrame.new(0, 1.5, 0), p, s)
	end
	lamp(parent, Vector3.new(0, base + 60, 0), p:Lerp(C.White, 0.5), 1.5, 90)
	buildWallDecor(ctx)
	-- Bandes lumineuses le long des 4 parois (hauteur de la mi-tranche)
	for i = 0, 3 do
		local look = (corner(i + 1) - corner(i)).Unit
		local out = -look:Cross(UP)
		local position = out * (INNER - 0.3) + Vector3.new(0, base + BAND * 0.55, 0)
		Build.Neon({
			Name = "WallStrip",
			Size = Vector3.new(0.4, 1.2, INNER * 2),
			CFrame = CFrame.fromMatrix(position, out, UP),
			Color = p,
			Transparency = 0.2,
			Parent = parent,
		})
	end
end

------------------------------------------------------------------------------------
-- Un monde complet
------------------------------------------------------------------------------------

local function buildWorld(tower: Folder, world: Tower.World)
	local w = world.Index
	local model = Build.Model(`World{w}`, tower)
	model:SetAttribute("World", w)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local ctx: Ctx = {
		World = world,
		W = w,
		Style = style(world),
		Model = model,
		Coins = Build.Folder("Coins", model),
		Decor = Build.Folder("Decor", model),
		Stage = 0,
		K = 0,
		Folder = model :: any,
		CoinCount = 0,
	}
	buildFloor(ctx)
	buildHero(ctx)
	buildEntrance(ctx)
	for j = 1, Tower.STAGES_PER_WORLD do
		local stage = Tower.FirstStage(w) + j - 1
		ctx.Stage = stage
		ctx.K = (stage - 1) / (TOTAL - 1)
		ctx.CoinCount = 0
		ctx.Folder = Build.Folder(`Stage{stage}`, model)
		buildSide(ctx, j)
	end
	-- Maison du terminal au coin suivant, au bout de la 5ᵉ étape
	local terminalCorner = startCorner(w) + Tower.STAGES_PER_WORLD
	local floorY = worldBase(w) + ENTRY + RISE * Tower.STAGES_PER_WORLD
	local terminal = Build.Folder("Terminal", model)
	buildHouse(cornerFrame(terminalCorner), floorY, CLIMB, { World = world, Style = ctx.Style, Parent = terminal })
	if w == Tower.WORLD_COUNT then
		-- Sommet : le cœur du virus vaincu, sur le toit de la dernière maison
		local fr = cornerFrame(terminalCorner)
		local top = floorY + CLIMB
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
			Parent = terminal,
		})
		finish.CanCollide = false
		finish.CanTouch = true
		Rod(terminal, "FinishPedestal", finishCf * CFrame.new(0, -5.5, 0) * VERTICAL, 3, 12, C.MetalDark)
		Props.Ring(terminal, "FinishHalo", finishCf * VERTICAL, 8.5, 0.8, 0.6, 16, SAFE, NEON)
		local hub = Props.SpinHub(terminal, finishCf, "Y", 1.2)
		for _, part in
			Props.Ring(terminal, "FinishOrbit", finishCf * CFrame.Angles(0.5, 0, 0), 11, 0.6, 0.5, 12, BIT, NEON)
		do
			Props.WeldTo(hub, part)
		end
		local signCf = facing(P(fr, 11, top + 20, -20), fr.R)
		local sign = Box(terminal, "SummitSign", Vector3.new(30, 6, 0.3), signCf, C.Bg)
		Props.Sign(sign, "CŒUR DU VIRUS", "Touche-le pour sauver le PC d'Anga !", LETHAL:Lerp(C.White, 0.3), C.White)
		lamp(terminal, P(fr, 11, top + 14, -20), SAFE, 2, 60)
	end
end

------------------------------------------------------------------------------------
-- Coque de la tour (parois, vitre, cadre, ventilateurs de façade)
------------------------------------------------------------------------------------

-- Porte d'entrée du parcours dans la façade (bas de la cage d'escalier de la maison de départ).
local function entranceDoor(): (number, number)
	local fr = cornerFrame(0)
	local a, b = P(fr, 44, 0, -44), P(fr, 44, 0, -32)
	return math.min(a.X, b.X), math.max(a.X, b.X)
end

local function buildShell(tower: Folder)
	local shell = Build.Model("Shell", tower)
	shell.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local outer = INNER + WALL
	local h = TOP
	local steel = Color3.fromRGB(34, 38, 50)
	local function wall(name: string, size: Vector3, position: Vector3, color: Color3?, material: Enum.Material?)
		return Build.Part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(position),
			Color = color or steel,
			Material = material or METAL,
			CastShadow = false,
			Parent = shell,
		})
	end
	local zc = -(INNER + WALL / 2)
	local doorX0, doorX1 = entranceDoor()
	local doorTop = 8
	-- Façade avant (-Z), percée de la porte d'entrée
	wall("Front", Vector3.new(outer - doorX1, h, WALL), Vector3.new((doorX1 + outer) / 2, h / 2, zc))
	wall("Front", Vector3.new(doorX0 + outer, h, WALL), Vector3.new((-outer + doorX0) / 2, h / 2, zc))
	wall(
		"Front",
		Vector3.new(doorX1 - doorX0, h - doorTop, WALL),
		Vector3.new((doorX0 + doorX1) / 2, (h + doorTop) / 2, zc)
	)
	wall("Back", Vector3.new(outer * 2, h, WALL), Vector3.new(0, h / 2, INNER + WALL / 2))
	wall("Left", Vector3.new(WALL, h, INNER * 2), Vector3.new(-(INNER + WALL / 2), h / 2, 0))
	wall("Top", Vector3.new(outer * 2, 6, outer * 2), Vector3.new(0, h + 3, 0))
	-- Vitre latérale (+X) et son cadre alu
	local glass = wall(
		"SideGlass",
		Vector3.new(2, h, INNER * 2),
		Vector3.new(INNER + 1, h / 2, 0),
		Color3.fromRGB(190, 215, 240),
		Enum.Material.Glass
	)
	glass.Transparency = 0.72
	for _, z in { -(INNER - 2), INNER - 2 } do
		wall("GlassFrame", Vector3.new(WALL, h, 4), Vector3.new(INNER + WALL / 2, h / 2, z), C.Aluminum)
	end
	wall("GlassFrame", Vector3.new(WALL, 6, outer * 2), Vector3.new(INNER + WALL / 2, 3, 0), C.Aluminum)
	-- Rails horizontaux à chaque plancher de monde (vus à travers la vitre), liseré RGB
	for w = 2, Tower.WORLD_COUNT do
		local y = worldBase(w)
		local rail =
			Box(shell, "GlassRail", Vector3.new(3, 3, INNER * 2), CFrame.new(INNER + 2.5, y - 1, 0), C.Aluminum, METAL)
		rail.CastShadow = false
		Build.Neon({
			Name = "RgbRail",
			Size = Vector3.new(0.4, 0.8, INNER * 2),
			CFrame = CFrame.new(INNER + 4.2, y - 1, 0),
			Color = hex(Tower.Worlds[w].Primary),
			Tags = { "RgbStrip" },
			Parent = shell,
		})
	end
	-- Façade : bandes lumineuses verticales, logo, bouton d'alimentation, 3 ventilateurs d'admission
	local face = -(outer + 0.2)
	for _, x in { -outer + 8, outer - 8 } do
		Build.Neon({
			Name = "FrontStrip",
			Size = Vector3.new(1.2, h - 30, 0.4),
			CFrame = CFrame.new(x, h / 2 + 10, face),
			Color = C.Violet,
			Tags = { "RgbStrip" },
			Parent = shell,
		})
	end
	for i, y in { 190, 360, 530 } do
		local fanCf = CFrame.fromMatrix(Vector3.new(0, y, face + 0.2), -Vector3.zAxis, UP)
		Props.Fan(shell, fanCf, 110, hex(Tower.Worlds[i * 2].Primary), 7, { Speed = 1.2, Lite = true, Rgb = true })
	end
	local logo = Box(
		shell,
		"FrontLogo",
		Vector3.new(120, 26, 0.4),
		CFrame.new(0, h - 60, face) * CFrame.Angles(0, math.pi, 0),
		C.Bg
	)
	logo.Transparency = 1
	Props.Sign(logo, "ANGA TOWER", "Deathrun dans le PC", C.White, C.Cyan, Enum.NormalId.Back)
	Rod(
		shell,
		"PowerButton",
		CFrame.fromMatrix(Vector3.new(0, h - 22, face - 0.3), -Vector3.zAxis, UP),
		1.2,
		14,
		C.MetalDark
	)
	Props.Ring(
		shell,
		"PowerRing",
		CFrame.fromMatrix(Vector3.new(0, h - 22, face - 0.9), -Vector3.zAxis, UP),
		7.4,
		0.8,
		0.4,
		16,
		C.Cyan,
		NEON
	)
	-- Dessus : deux ventilateurs d'extraction
	for _, x in { -62, 62 } do
		Props.Fan(shell, CFrame.fromMatrix(Vector3.new(x, h + 6, 0), UP, Vector3.zAxis), 100, C.Violet, 7, {
			Speed = 1.5,
			Lite = true,
		})
	end
	-- Socle (plinthe) autour du pied de la tour
	for i = 0, 3 do
		local look = (corner(i + 1) - corner(i)).Unit
		local out = -look:Cross(UP)
		Box(
			shell,
			"Plinth",
			Vector3.new(outer * 2 + 4, 4, 3),
			CFrame.fromMatrix(out * (outer + 1.5) + Vector3.new(0, 2, 0), look, UP),
			C.Black,
			METAL
		)
	end
end

------------------------------------------------------------------------------------
-- Lobby (Salle de démarrage) : le bureau devant la tour
------------------------------------------------------------------------------------

local function buildLobby(tower: Folder)
	local lobby = Build.Model("Lobby", tower)
	lobby.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local padTop = 0.4

	-- Bureau (sol), tapis de souris RGB (zone du lobby), murets invisibles au bord du bureau
	Build.Part({
		Name = "Desk",
		Size = Vector3.new(640, 6, 700),
		CFrame = CFrame.new(0, -3, -110),
		Color = Color3.fromRGB(58, 44, 38),
		Material = Enum.Material.WoodPlanks,
		Parent = lobby,
	})
	Build.Part({
		Name = "MousePad",
		Size = Vector3.new(360, 0.4, 250),
		CFrame = CFrame.new(-40, padTop / 2, -290),
		Color = Color3.fromRGB(24, 26, 34),
		Material = Enum.Material.Fabric,
		Parent = lobby,
	})
	for _, edge in
		{ { 0, -125.2, 360.4, 0.6 }, { 0, 125.2, 360.4, 0.6 }, { -180.2, 0, 0.6, 250 }, { 180.2, 0, 0.6, 250 } }
	do
		Build.Neon({
			Name = "PadRgb",
			Size = Vector3.new(edge[3], 0.5, edge[4]),
			CFrame = CFrame.new(-40 + edge[1], padTop, -290 + edge[2]),
			Color = C.Violet,
			Tags = { "RgbStrip" },
			Parent = lobby,
		})
	end
	for _, b in { { 0, 240, 640, 2 }, { 0, -460, 640, 2 }, { -320, -110, 2, 700 }, { 320, -110, 2, 700 } } do
		local barrier = Build.Part({
			Name = "DeskEdge",
			Size = Vector3.new(b[3], 60, b[4]),
			CFrame = CFrame.new(b[1], 30, b[2]),
			Transparency = 1,
			Parent = lobby,
		})
		barrier.CanQuery = false
	end

	-- Spawn : face à la tour, entre l'écran géant et la porte du parcours
	local spawnPos = Vector3.new(-40, padTop + 0.5, -290)
	local spawnLook = Vector3.new(-28, 0, -182) - Vector3.new(-40, 0, -290)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = facing(spawnPos, spawnLook)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = C.MetalDark
	spawn.Material = METAL
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby
	Props.Ring(lobby, "SpawnRing", spawn.CFrame * CFrame.new(0, 0.6, 0) * VERTICAL, 6.2, 0.5, 0.3, 16, C.Cyan, NEON)

	-- Écran géant de l'app AngAInOne (face avant dessinée par le client), tourné vers le spawn
	local screenPos = Vector3.new(80, 42, -222)
	local screenCf = facing(screenPos, spawnPos - screenPos)
	Build.Part({
		Name = "MonitorBezel",
		Size = Vector3.new(116, 68, 3),
		CFrame = screenCf * CFrame.new(0, 0, 1.8),
		Color = C.Black,
		Material = METAL,
		Parent = lobby,
	})
	local appScreen = Build.Decor({
		Name = "AppScreen",
		Size = Vector3.new(110, 62, 0.4),
		CFrame = screenCf,
		Color = Color3.fromHex("202020"),
		Material = SMOOTH,
		Tags = { "AppScreen" },
		Parent = lobby,
	})
	Build.PointLight(appScreen, C.Violet, 1.2, 70)
	lights[1] += 1
	Build.Neon({
		Name = "Ambilight",
		Size = Vector3.new(114, 66, 0.4),
		CFrame = screenCf * CFrame.new(0, 0, 3.6),
		Color = C.Violet,
		Transparency = 0.2,
		Tags = { "RgbStrip" },
		Parent = lobby,
	})
	Build.Part({
		Name = "MonitorNeck",
		Size = Vector3.new(10, 12, 4),
		CFrame = screenCf * CFrame.new(0, -38, 6),
		Color = C.MetalLight,
		Material = METAL,
		Parent = lobby,
	})
	Build.Part({
		Name = "MonitorFoot",
		Size = Vector3.new(44, 1.6, 26),
		CFrame = facing(Vector3.new(screenPos.X, 0.8, screenPos.Z), spawnPos - screenPos) * CFrame.new(0, 0, 10),
		Color = C.MetalLight,
		Material = METAL,
		Parent = lobby,
	})

	-- Hologramme du titre, sur la façade au-dessus de la porte
	local title = Build.Decor({
		Name = "TitleHologram",
		Size = Vector3.new(80, 20, 0.2),
		CFrame = facing(Vector3.new(-60, 52, -150), spawnPos - Vector3.new(-60, 52, -150)),
		Transparency = 1,
		Tags = { "TitleHologram" },
		Parent = lobby,
	})
	Build.PointLight(title, C.Violet, 1.6, 60)
	lights[1] += 1

	-- Classements (face avant dessinée par le client), côté droit du spawn
	for i, board in { "Wins", "BestTime", "Stage" } do
		local position = Vector3.new(-185, 20, -335 + i * 38)
		local cf = facing(position, spawnPos - position)
		Build.Part({
			Name = `{board}Frame`,
			Size = Vector3.new(32, 22, 1.4),
			CFrame = cf * CFrame.new(0, 0, 1),
			Color = C.MetalDark,
			Material = METAL,
			Parent = lobby,
		})
		local screen = Build.Decor({
			Name = `{board}Board`,
			Size = Vector3.new(30, 20, 0.3),
			CFrame = cf,
			Color = C.Bg,
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			Tags = { "LeaderboardScreen" },
			Parent = lobby,
		})
		screen:SetAttribute("Board", board)
		Build.Part({
			Name = `{board}Leg`,
			Size = Vector3.new(3, 9, 3),
			CFrame = cf * CFrame.new(0, -14.5, 1.2),
			Color = C.MetalLight,
			Material = METAL,
			Parent = lobby,
		})
		Build.Neon({
			Name = `{board}Trim`,
			Size = Vector3.new(32, 0.5, 0.5),
			CFrame = cf * CFrame.new(0, -11.2, 0),
			Color = C.Cyan,
			Parent = lobby,
		})
	end

	-- Bornes : boutique, arcade (mini-jeux), récompense du jour
	local kiosks = {
		{
			Action = "Shop",
			Text = "Boutique",
			Object = "Skins et effets",
			Color = C.Gold,
			At = Vector3.new(0, 0, -262),
		},
		{
			Action = "Arcade",
			Text = "Arcade",
			Object = "Mini-jeux antivirus",
			Color = C.Cyan,
			At = Vector3.new(8, 0, -298),
		},
		{
			Action = "Daily",
			Text = "Cadeau du jour",
			Object = "Récompenses",
			Color = SPRING,
			At = Vector3.new(-6, 0, -332),
		},
	}
	for _, kiosk in kiosks do
		local cf = facing(kiosk.At + Vector3.new(0, padTop, 0), spawnPos - kiosk.At)
		local model = Build.Model(`{kiosk.Action}Kiosk`, lobby)
		local stand = Build.Part({
			Name = "Stand",
			Size = Vector3.new(6, 5, 4),
			CFrame = cf * CFrame.new(0, 2.5, 0),
			Color = C.MetalDark,
			Material = METAL,
			Parent = model,
		})
		model.PrimaryPart = stand
		Box(
			model,
			"ScreenBack",
			Vector3.new(8, 6, 0.6),
			cf * CFrame.new(0, 8.4, 0.4) * CFrame.Angles(math.rad(-12), 0, 0),
			C.Black,
			METAL
		)
		local screen = Box(
			model,
			"Screen",
			Vector3.new(7.4, 5.4, 0.2),
			cf * CFrame.new(0, 8.4, 0) * CFrame.Angles(math.rad(-12), 0, 0),
			C.Bg
		)
		Props.Sign(screen, string.upper(kiosk.Text), kiosk.Object, kiosk.Color, C.White)
		Build.Neon({
			Name = "Trim",
			Size = Vector3.new(6.2, 0.4, 0.4),
			CFrame = cf * CFrame.new(0, 5.1, -2),
			Color = kiosk.Color,
			Parent = model,
		})
		Build.Prompt(stand, kiosk.Text, kiosk.Object, kiosk.Action, 12)
	end

	-- Emplacement de la mascotte Anga (le client l'affiche ici), à côté du spawn
	local angaPos = Vector3.new(-66, padTop + 3, -282)
	local anga = Build.Decor({
		Name = "AngaSpot",
		Size = Vector3.new(4, 6, 4),
		CFrame = facing(angaPos, spawnPos - angaPos),
		Transparency = 1,
		Parent = lobby,
	})
	anga.CanQuery = false
	Rod(lobby, "AngaPodium", CFrame.new(angaPos.X, padTop + 0.4, angaPos.Z) * VERTICAL, 0.8, 9, C.MetalDark)
	Props.Ring(
		lobby,
		"AngaRing",
		CFrame.new(angaPos.X, padTop + 0.9, angaPos.Z) * VERTICAL,
		4.4,
		0.4,
		0.3,
		14,
		C.Brand,
		NEON
	)

	-- Entrée du parcours : portique « JOUER » devant la porte, chemin lumineux depuis le spawn
	local doorX0, doorX1 = entranceDoor()
	local doorX = (doorX0 + doorX1) / 2
	local faceZ = -(INNER + WALL)
	for _, x in { doorX0 - 2, doorX1 + 2 } do
		Build.Part({
			Name = "PortalPillar",
			Size = Vector3.new(3, 16, 3),
			CFrame = CFrame.new(x, 8, faceZ - 3),
			Color = C.MetalDark,
			Material = METAL,
			Parent = lobby,
		})
		Build.Neon({
			Name = "PortalGlow",
			Size = Vector3.new(0.6, 15, 0.6),
			CFrame = CFrame.new(x + (if x < doorX then 1.6 else -1.6), 8, faceZ - 4.6),
			Color = SAFE,
			Parent = lobby,
		})
	end
	local lintel = Build.Part({
		Name = "PortalLintel",
		Size = Vector3.new(doorX1 - doorX0 + 7, 5, 3),
		CFrame = CFrame.new(doorX, 18.5, faceZ - 3),
		Color = C.Black,
		Material = METAL,
		Parent = lobby,
	})
	Props.Sign(lintel, "JOUER", "Grimpe la tour !", SAFE, C.White, Enum.NormalId.Front)
	lamp(lobby, Vector3.new(doorX, 12, faceZ - 12), SAFE, 1.4, 36)
	local padPos = Vector3.new(doorX, padTop, faceZ - 14)
	for i = 1, 5 do
		local t = i / 6
		local position = spawnPos:Lerp(padPos, t)
		Build.Neon({
			Name = "Chevron",
			Size = Vector3.new(7, 0.2, 1),
			CFrame = facing(Vector3.new(position.X, padTop + 0.1, position.Z), padPos - spawnPos),
			Color = SAFE,
			Transparency = 0.25,
			Parent = lobby,
		})
	end
	checkpoint(0, Vector3.new(doorX, padTop + 0.6, faceZ - 14), Vector3.zAxis, SAFE)

	-- Clavier géant (décor) derrière le spawn
	local keyboardCf = CFrame.new(-40, 0, -420)
	Build.Part({
		Name = "KeyboardBase",
		Size = Vector3.new(250, 5, 64),
		CFrame = keyboardCf * CFrame.new(0, 2.5, 0),
		Color = C.Black,
		Material = METAL,
		Parent = lobby,
	})
	Build.Neon({
		Name = "KeyboardGlow",
		Size = Vector3.new(252, 0.6, 66),
		CFrame = keyboardCf * CFrame.new(0, 0.4, 0),
		Color = C.Cyan,
		Transparency = 0.3,
		Tags = { "RgbStrip" },
		Parent = lobby,
	})
	for row = 0, 3 do
		for col = 0, 13 do
			local wide = row == 3 and col >= 4 and col <= 9
			if not (row == 3 and col > 4 and col <= 9) then
				Box(
					lobby,
					"Key",
					Vector3.new(if wide then 82 else 13, 3, 11),
					keyboardCf * CFrame.new(-110 + col * 17 + (if wide then 34.5 else 0), 6, -22 + row * 14.5),
					Color3.fromRGB(44, 46, 56)
				)
			end
		end
	end
	-- Souris géante (RGB), tasse de café, logo sérigraphié sur le tapis
	local mouseCf = CFrame.new(150, 0, -330) * CFrame.Angles(0, math.rad(-12), 0)
	Build.Part({
		Name = "MouseBody",
		Size = Vector3.new(26, 9, 40),
		CFrame = mouseCf * CFrame.new(0, 4.5, 0),
		Color = C.Black,
		Material = SMOOTH,
		Parent = lobby,
	})
	Rod(
		lobby,
		"MouseNose",
		mouseCf * CFrame.new(0, 4.5, -20) * CFrame.Angles(0, math.pi / 2, 0) * VERTICAL,
		26,
		9,
		C.Black
	)
	Rod(lobby, "MouseWheel", mouseCf * CFrame.new(0, 9.2, -12), 1.6, 5, C.MetalLight)
	Build.Neon({
		Name = "MouseRgb",
		Size = Vector3.new(26.4, 0.8, 40.4),
		CFrame = mouseCf * CFrame.new(0, 1.2, 0),
		Color = C.Violet,
		Tags = { "RgbStrip" },
		Parent = lobby,
	})
	Props.Cable(lobby, {
		(mouseCf * CFrame.new(0, 3, -24)).Position,
		(mouseCf * CFrame.new(10, 1.5, -70)).Position,
		Vector3.new(120, 1.5, -150),
	}, 1.2, C.Rubber)
	local mugPos = Vector3.new(-250, 0, -250)
	Build.Cylinder({
		Name = "Mug",
		Size = Vector3.new(34, 30, 30),
		CFrame = CFrame.new(mugPos + Vector3.new(0, 17, 0)) * VERTICAL,
		Color = C.White,
		Material = SMOOTH,
		Parent = lobby,
	})
	Rod(lobby, "Coffee", CFrame.new(mugPos + Vector3.new(0, 33.2, 0)) * VERTICAL, 0.6, 27, Color3.fromRGB(70, 42, 28))
	-- Anse : deux barreaux horizontaux + un montant (x, y, largeur, hauteur)
	for _, handle in { { 18, 26, 6, 3 }, { 18, 8, 6, 3 }, { 21.5, 17, 3, 21 } } do
		Box(
			lobby,
			"MugHandle",
			Vector3.new(handle[3], handle[4], 4),
			CFrame.new(mugPos + Vector3.new(handle[1], handle[2], 0)),
			C.White
		)
	end
	local mugLabel = Box(
		lobby,
		"MugLabel",
		Vector3.new(0.2, 12, 20),
		CFrame.new(mugPos + Vector3.new(15.1, 18, 0)) * CFrame.Angles(0, math.pi / 2, 0),
		C.Brand
	)
	mugLabel.Transparency = 1
	Props.Label(mugLabel, "ANGA", C.Brand, Enum.NormalId.Right, Enum.Font.GothamBlack)
	Props.Decal(
		lobby,
		"PadLogo",
		Vector3.new(120, 0.1, 24),
		facing(Vector3.new(-40, padTop + 0.06, -355), spawnLook) * CFrame.Angles(0, math.pi, 0),
		"ANGA TOWER",
		C.Violet,
		Enum.NormalId.Top,
		Enum.Font.GothamBlack
	)

	lamp(lobby, Vector3.new(-40, 40, -290), C.White, 1, 120)
end

------------------------------------------------------------------------------------
-- Construction complète
------------------------------------------------------------------------------------

function TowerBuilder.Build(): Folder
	local existing = Workspace:FindFirstChild("Tower")
	if existing then
		existing:Destroy()
	end
	lights[1] = 0
	local tower = Instance.new("Folder")
	tower.Name = "Tower"
	checkpointsFolder = Build.Folder("Checkpoints", tower)
	buildLobby(tower)
	buildShell(tower)
	-- Maison de départ (coin 0) : de la porte de façade au toit = départ du monde 1
	local startStyle = style(Tower.Worlds[1])
	local start = Build.Folder("Start", tower:FindFirstChild("Lobby") :: Instance)
	buildHouse(cornerFrame(0), 0.1, ENTRY - 0.1, { Style = startStyle, Parent = start })
	for _, world in Tower.Worlds do
		buildWorld(tower, world)
	end
	tower:SetAttribute("PointLights", lights[1])
	tower.Parent = Workspace
	return tower
end

return TowerBuilder
