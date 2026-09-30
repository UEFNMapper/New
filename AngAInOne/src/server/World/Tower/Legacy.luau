--!strict
--[[
	Legacy : le parcours et le décor v1 de la tour (avant les mondes uniques de la phase 2).

	- Legacy.Course(ctx) : les 5 étapes du monde le long de l'anneau carré (axe à ±88). Chaque étape
	  = un côté de 176 studs entre deux coins, qui monte de RISE studs (4 modules d'obstacles de
	  34 studs séparés par des paliers) ; chaque coin porte le checkpoint de l'étape qui s'y termine.
	  Le monde n commence au coin (n - 1) % 4 (ctx.Entry) et la 5ᵉ étape arrive à la porte de la
	  salle du terminal (ctx.Terminal.Door).
	- Legacy.Decor(ctx) : composant géant au centre, composants accrochés aux parois, bandes lumineuses.

	Un monde réécrit (Worlds/W{n}.luau) peut arrêter d'appeler ce module ou n'en garder qu'une partie.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local Common = require(script.Parent.Common)

local Legacy = {}

local INNER = Common.INNER
local SIDE = Common.SIDE
local BAND = Common.BAND
local ENTRY = Common.ENTRY
local RISE = Common.RISE
local CORNER = Common.CORNER
local JUNCTION = 6 -- palier entre deux modules
local MODULE_L = 34 -- longueur d'un module d'obstacles
local TOTAL = Tower.TOTAL_STAGES

local UP = Common.UP
local C = Common.C
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local VERTICAL = Common.VERTICAL

local LETHAL = Common.Colors.Lethal
local GLITCH = Common.Colors.Glitch
local HEAT = Common.Colors.Heat
local SAFE = Common.Colors.Safe
local SPRING = Common.Colors.Spring

local frac = Common.Frac
local corner = Common.Corner
local sideFrame = Common.SideFrame
local P, CFA, span, facing = Common.P, Common.CFA, Common.Span, Common.Facing
local worldBase, startCorner = Common.WorldBase, Common.StartCorner
local lamp = Common.Lamp
local attach = Common.Attach

type Frame = Common.Frame
type Style = Common.Style

------------------------------------------------------------------------------------
-- État de construction v1
------------------------------------------------------------------------------------

type Ctx = {
	C: Common.WorldContext, -- contexte de monde (outils partagés)
	World: Tower.World,
	W: number,
	Style: Style,
	Decor: Folder,
	Stage: number,
	K: number, -- difficulté 0..1 sur toute la tour
	Folder: Folder, -- pièces de l'étape en cours
}

type Mod = { Ctx: Ctx, Fr: Frame, U: number, Y: number }

local function newCtx(world: Common.WorldContext): Ctx
	return {
		C = world,
		World = world.Def,
		W = world.Index,
		Style = world.Style,
		Decor = world.Decor,
		Stage = 0,
		K = 0,
		Folder = world.Decor,
	}
end

-- Plateforme solide du module : u, v relatifs au module, dessus à Y + dy.
local function plat(m: Mod, u0: number, u1: number, v0: number, v1: number, dy: number, name: string?): Part
	local size, cf = span(m.Fr, m.U + u0, m.U + u1, m.Y + dy - 2, m.Y + dy, v0, v1)
	return m.Ctx.C.Platform(m.Ctx.Folder, size, cf, name)
end

local function coin(ctx: Ctx, position: Vector3)
	ctx.C.Coin(position, ctx.Stage)
end

local function mcoin(m: Mod, u: number, dy: number, v: number)
	coin(m.Ctx, P(m.Fr, m.U + u, m.Y + dy, v))
end

-- Piège animé côté client. Les pièges mortels sont non solides ; les plateformes le sont.
local function trap(
	ctx: Ctx,
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
		Parent = ctx.Folder,
	})
	part.CanCollide = collide == true
	part.CanQuery = collide == true
	ctx.C.Trap(kind, part, attributes)
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
		trap(ctx, "Zapper", "Arc", size, cf, LETHAL, NEON, {
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
			ctx.C.Hazard(ctx.Folder, "ShortCircuit", size, cf, LETHAL, "Hazard")
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
	local pad = trap(ctx, "Bounce", "Capacitor", size, cf, SPRING, SMOOTH, { Power = 80 }, true)
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
			ctx,
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
		local stick = trap(ctx, "Crusher", "RamStick", size, cf, Color3.fromRGB(150, 36, 96), SMOOTH, {
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
		local block = trap(ctx, "Crusher", "Piston", size, cf, Color3.fromRGB(150, 36, 96), SMOOTH, {
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
	trap(ctx, "Conveyor", "DataBelt", size, cf, Color3.fromRGB(34, 40, 56), SMOOTH, {
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
		local stick = trap(ctx, "Crusher", "RamStick", csize, ccf, Color3.fromRGB(150, 36, 96), SMOOTH, {
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
			ctx.C.Hazard(ctx.Folder, "GlitchBlock", gsize, gcf, GLITCH, "Hazard")
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
	local mover = trap(ctx, "Mover", "Shuttle", size, cf, C.MetalLight, METAL, {
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
			ctx,
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
		ctx,
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
			ctx,
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
	local beam = trap(ctx, "Laser", "Beam", Vector3.new(12.6, 0.5, 0.5), cf, LETHAL, NEON, {
		Offset = m.Fr.F * 26,
		Period = 4.4 - 1.0 * k,
		Phase = phaseOf(ctx, 6),
	})
	for _, v in { -6.8, 6.8 } do
		attach(beam, "Emitter", Vector3.new(1, 1.6, 1.6), cf * CFrame.new(v, 0, 0), C.Black, METAL)
	end
	if k > 0.4 then
		local vcf = CFA(m.Fr, m.U + 17, m.Y + 4.6, -5.6)
		local curtain = trap(ctx, "Laser", "Curtain", Vector3.new(0.5, 9, 0.5), vcf, LETHAL, NEON, {
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
			trap(ctx, "Heat", "HeatColumn", hsize, hcf, HEAT, NEON, {
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
		local virus = trap(ctx, "Virus", "Virus", Vector3.one * 4.4, cf, GLITCH, NEON, {
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
		ctx.C.Hazard(ctx.Folder, "GlitchBlock", size, cf, GLITCH, "Hazard")
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
Legacy.ModuleList = moduleList

------------------------------------------------------------------------------------
-- Checkpoints, paliers, coins
------------------------------------------------------------------------------------

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
	ctx.C.Checkpoint(stage, facing(P(fr, SIDE, y + 0.4, 0), fr.R))
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
-- API
------------------------------------------------------------------------------------

-- Les 5 étapes v1 du monde (checkpoints FirstStage .. TerminalStage - 1 compris).
function Legacy.Course(world: Common.WorldContext)
	local ctx = newCtx(world)
	for j = 1, Tower.STAGES_PER_WORLD do
		local stage = Tower.FirstStage(ctx.W) + j - 1
		ctx.Stage = stage
		ctx.K = (stage - 1) / (TOTAL - 1)
		ctx.Folder = world.Stage(stage)
		buildSide(ctx, j)
	end
end

-- Décor v1 : composant géant, composants muraux, bandes lumineuses.
function Legacy.Decor(world: Common.WorldContext)
	buildHero(newCtx(world))
end

return table.freeze(Legacy)
