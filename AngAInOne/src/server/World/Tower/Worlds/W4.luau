--!strict
--[[
	Monde 4 : Cryo Tower (refroidissement) — « Surchauffe, ventilos bouchés ». Sbire : Dusty.
	Incident : SURCHAUFFE (toutes les bouches de vapeur s'allument, le vent double).

	Entrée sur le toit de la salle du monde 3 (coin (-88, 88), regard -Z) ; porte du terminal au
	coin (-88, -88), on y entre vers -Z. Le parcours fait le tour de la tour en spirale :
	  1. Le radiateur (y 310 → 318) : on court dans les couloirs entre les tubes du radiateur
	     (murs trop hauts pour sauter) ; des jets de vapeur (Heat) montent du sol, des ouvertures
	     permettent de changer de couloir. SURCHAUFFE : tous les jets en même temps → on attend
	     entre deux bouches. Clé USB 1 : couloir en cul-de-sac aux jets rapides.
	  2. Le tube de watercooling (318 → 332) : tube de verre en pente ; des boules de poussière
	     (DustBall) le dévalent et le remplissent : on se cache dans les niches. Elles bouclent
	     par le tube de retour, sous le tube principal. Clé USB 2 : la chambre de la pompe, où
	     trois petites boules tournent autour de la clé.
	  3. Les ventilateurs (332 → 346) : trois ventilateurs géants en travers du chemin (pales
	     SpinBar) qui soufflent contre nous (Wind). Clé USB 3 : saut porté par une rafale.
	  4. La chambre froide (346 → 360) : blocs de glace qui fondent (Vanish) sous des rafales
	     latérales, abris coupe-vent entre les séries.
	  5. La sortie d'air (360 → 380) : boules de poussière en travers, jets de vapeur, un dernier
	     ventilateur et un escalier de glace sous un jet → porte.

	Décor : radiateur AIO géant et ses ventilateurs (« AioRadiator », « Fan140 »), réservoir de
	pompe (« PumpReservoir »), ventirad (« CpuCooler »), ventilateurs muraux (« Fan120 »), Dusty
	(« Dusty ») devant la porte ; versions infectée (poussière, alerte 97 °C) et nettoyée (RGB bleu).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Parent.Props)
local ModelLibrary = require(script.Parent.Parent.Parent.ModelLibrary)
local Common = require(script.Parent.Parent.Common)

local C = Common.C
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local VERTICAL = Common.VERTICAL
local HEAT = Common.Colors.Heat
local LETHAL = Common.Colors.Lethal
local UP = Vector3.yAxis

local ICE = Color3.fromRGB(190, 232, 255) -- blocs de glace (Vanish)
local GLASS = Color3.fromRGB(205, 232, 255) -- verre des tubes
local DUST = Color3.fromRGB(168, 70, 112) -- boules de poussière (mortelles : rouge / magenta)
local BLADE = Color3.fromRGB(196, 44, 84) -- pales (mortelles)
local GRIME = Color3.fromRGB(120, 116, 128) -- poussière du décor infecté

-- "x,y,z;x,y,z" (décalages monde relatifs à la position de repos).
local function waypoints(points: { Vector3 }): string
	local chunks = {}
	for _, p in points do
		table.insert(chunks, string.format("%.2f,%.2f,%.2f", p.X, p.Y, p.Z))
	end
	return table.concat(chunks, ";")
end

-- Pose un vrai modèle 3D (ou son décor de secours), mis à l'échelle pour que sa plus grande
-- dimension vaille `length` studs (l'échelle d'import des modèles n'est pas garantie) :
-- `Fit` cubique = échelle uniforme bornée par la plus grande dimension.
local function placeModel(
	key: string,
	cf: CFrame,
	parent: Instance,
	length: number,
	fallback: () -> Instance?,
	spin: (boolean | string)?
): Instance?
	return ModelLibrary.Place(key, cf, parent, { Collide = false, Spin = spin, Fit = Vector3.one * length }, fallback)
end

return function(ctx: Common.WorldContext)
	local first = Tower.FirstStage(ctx.Index) -- 16
	local style = ctx.Style
	local BLUE, PALE = style.Primary, style.Secondary
	local decor = ctx.Decor
	local base = ctx.Base

	ctx.Void()
	ctx.Entrance()

	------------------------------------------------------------------------------------
	-- Outils
	------------------------------------------------------------------------------------

	-- Dalle solide aux couleurs du monde (glace) : dessus à `top`, bornes x0..x1 / z0..z1.
	local function slab(
		parent: Instance,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		name: string?
	): Part
		local sx, sz = math.abs(x1 - x0), math.abs(z1 - z0)
		local center = Vector3.new((x0 + x1) / 2, top - 1, (z0 + z1) / 2)
		if sx > sz then
			return ctx.Platform(
				parent,
				Vector3.new(sz, 2, sx),
				CFrame.new(center) * CFrame.Angles(0, math.pi / 2, 0),
				name
			)
		end
		return ctx.Platform(parent, Vector3.new(sx, 2, sz), CFrame.new(center), name)
	end

	-- Mur solide (pas une plateforme) : bornes x0..x1, y0..y1, z0..z1.
	local function wall(
		parent: Instance,
		name: string,
		x0: number,
		x1: number,
		y0: number,
		y1: number,
		z0: number,
		z1: number,
		color: Color3,
		material: Enum.Material?
	): Part
		return Build.Part({
			Name = name,
			Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
			CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
			Color = color,
			Material = material or METAL,
			CastShadow = false,
			Parent = parent,
		})
	end

	local function trapPart(
		parent: Instance,
		kind: string,
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material,
		attributes: { [string]: any },
		solid: boolean?
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
		part.CanCollide = solid == true
		part.CanQuery = solid == true
		ctx.Trap(kind, part, attributes)
		return part
	end

	local function neon(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, alpha: number?): Part
		return Build.Neon({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color,
			Transparency = alpha or 0.2,
			Parent = parent,
		})
	end

	-- Jet de vapeur (Heat) : grille au sol + colonne mortelle quand elle souffle.
	local function steam(
		parent: Instance,
		cf: CFrame,
		size: Vector3,
		period: number,
		duty: number,
		phase: number,
		grate: boolean?
	): Part
		if grate ~= false then
			Box(
				parent,
				"VentGrate",
				Vector3.new(size.X, 0.14, size.Z),
				cf * CFrame.new(0, -size.Y / 2 + 0.07, 0),
				C.Black,
				METAL
			)
			neon(
				parent,
				"VentGlow",
				Vector3.new(size.X - 0.8, 0.16, size.Z - 0.8),
				cf * CFrame.new(0, -size.Y / 2 + 0.1, 0),
				HEAT,
				0.5
			)
		end
		local jet = trapPart(parent, "Heat", "SteamJet", size, cf, HEAT, NEON, {
			Period = period,
			Duty = duty,
			Phase = phase,
		})
		jet.Transparency = 0.45
		return jet
	end

	-- Zone de vent (Direction = souffle) avec particules ; rafales si `gust` = { Period, Duty, Phase }.
	local function wind(
		parent: Instance,
		center: Vector3,
		across: number,
		height: number,
		along: number,
		direction: Vector3,
		strength: number,
		gust: { number }?
	): Part
		local attributes: { [string]: any } = { Direction = direction, Strength = strength }
		if gust then
			attributes.Period = gust[1]
			attributes.Duty = gust[2]
			attributes.Phase = gust[3]
		end
		local zone = trapPart(
			parent,
			"Wind",
			"WindZone",
			Vector3.new(across, height, along),
			Common.Facing(center, direction),
			C.White,
			SMOOTH,
			attributes
		)
		zone.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Gust"
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Rate = 10 + strength
		emitter.Lifetime = NumberRange.new(0.6, 1)
		emitter.Speed = NumberRange.new(18 + strength * 2, 26 + strength * 2)
		emitter.Size = NumberSequence.new(0.25)
		emitter.Transparency = NumberSequence.new(0.45)
		emitter.LightEmission = 0.6
		emitter.Color = ColorSequence.new(Color3.fromRGB(220, 244, 255))
		emitter.Parent = zone
		return zone
	end

	-- Pales d'un ventilateur géant en travers du chemin (axe Z monde) : `bars` barres croisées.
	local function blades(parent: Instance, hub: Vector3, radius: number, bars: number, speed: number, phase: number)
		for i = 1, bars do
			local cf = CFrame.new(hub) * CFrame.Angles(0, 0, (i - 1) * math.pi / bars)
			local bar = trapPart(parent, "SpinBar", "FanBlade", Vector3.new(radius * 2, 2.4, 1.2), cf, BLADE, SMOOTH, {
				Speed = speed,
				Axis = "Z",
				Phase = phase,
			})
			for _, side in { -1, 1 } do
				Common.Attach(
					bar,
					"BladeEdge",
					Vector3.new(radius - 3, 0.5, 1.3),
					cf * CFrame.new(side * (radius / 2 + 1.5), 1.1, 0),
					LETHAL,
					NEON
				)
			end
		end
		Rod(parent, "FanHub", CFrame.new(hub) * CFrame.Angles(0, math.pi / 2, 0), 2.4, 5, C.MetalDark)
	end

	-- Cadre de ventilateur (décor, vrai modèle si importé) autour d'un moyeu, axe Z monde.
	local function fanFrame(hub: Vector3, diameter: number, key: string)
		local cf = CFrame.new(hub + Vector3.new(0, 0, 1.5)) * CFrame.Angles(math.pi / 2, 0, 0)
		placeModel(key, cf, decor, diameter * 1.08, function(): Instance?
			local model = Build.Model(key, decor)
			local half = diameter * 0.54
			for _, dx in { -1, 1 } do
				Box(
					model,
					"FrameSide",
					Vector3.new(2, diameter * 1.08, 3),
					CFrame.new(hub + Vector3.new(dx * half, 0, 0)),
					C.Black,
					METAL
				)
				Box(
					model,
					"FrameBar",
					Vector3.new(diameter * 1.08, 2, 3),
					CFrame.new(hub + Vector3.new(0, dx * half, 0)),
					C.Black,
					METAL
				)
			end
			Props.Ring(
				model,
				"FanRing",
				CFrame.new(hub + Vector3.new(0, 0, 1.6)) * CFrame.Angles(0, math.pi / 2, 0),
				diameter / 2,
				0.8,
				0.5,
				16,
				BLUE,
				NEON
			)
			return model
		end, "Hide") -- les vraies pales (rouges, mortelles) tournent devant
	end

	-- Bloc de glace qui fond après contact (Vanish).
	local function frost(
		parent: Instance,
		x: number,
		z: number,
		top: number,
		sx: number,
		sz: number,
		delay: number
	): Part
		local cf = CFrame.new(x, top - 0.7, z)
		local block = trapPart(parent, "Vanish", "IceBlock", Vector3.new(sx, 1.4, sz), cf, ICE, Enum.Material.Ice, {
			Delay = delay,
			Respawn = 3,
		}, true)
		block.Transparency = 0.1
		Common.Attach(
			block,
			"Frost",
			Vector3.new(sx - 1.2, 0.1, sz - 1.2),
			cf * CFrame.new(0, 0.72, 0),
			C.White,
			Enum.Material.Glacier
		)
		return block
	end

	-- Boule de poussière qui roule en boucle (DustBall) : yeux rouges.
	local function dustBall(
		parent: Instance,
		rest: Vector3,
		path: { Vector3 },
		speed: number,
		phase: number,
		diameter: number
	)
		local cf = CFrame.new(rest)
		local ball = trapPart(parent, "DustBall", "DustBall", Vector3.one * diameter, cf, DUST, Enum.Material.Fabric, {
			Waypoints = waypoints(path),
			Speed = speed,
			Phase = phase,
		})
		ball.Shape = Enum.PartType.Ball
		for _, side in { -1, 1 } do
			Common.Attach(
				ball,
				"Eye",
				Vector3.new(diameter * 0.14, diameter * 0.2, diameter * 0.1),
				cf * CFrame.new(side * diameter * 0.16, diameter * 0.1, -diameter * 0.46),
				LETHAL,
				NEON
			)
		end
		return ball
	end

	------------------------------------------------------------------------------------
	-- Étape 1 : le radiateur — couloirs entre les tubes, jets de vapeur
	------------------------------------------------------------------------------------

	local function stage1()
		local s = ctx.Stage(first)
		-- Entrée d'air (sous le portique), puis 4 couloirs A..D le long de -Z
		slab(s, -111, -73, 74, 79, 311, "Intake")
		local lanes: { [string]: number } = { A = -107, B = -97, C = -87, D = -77 }
		for name, x in lanes do
			local z1 = if name == "A" then 32 else 14
			slab(s, x - 4, x + 4, 44, 74, 311, `Channel{name}`)
			slab(s, x - 4, x + 4, z1, 44, 314, `Channel{name}`)
		end
		-- Tubes du radiateur (murs de 13 studs) et leurs ouvertures (z0, z1)
		local tubes: { { any } } = {
			{ -112, {} },
			{ -102, { { 66, 70 } } },
			{ -92, { { 60, 64 }, { 39, 43 }, { 16, 20 } } },
			{ -82, { { 52, 56 }, { 30, 34 } } },
			{ -72, {} },
		}
		for _, tube in tubes do
			local x = tube[1] :: number
			local cuts = tube[2] :: { { number } }
			local z = 74
			local spans: { { number } } = {}
			for _, cut in cuts do
				table.insert(spans, { cut[2], z })
				z = cut[1]
			end
			table.insert(spans, { 14, z })
			for _, span in spans do
				local z0, z1 = span[1], span[2]
				if z1 - z0 > 0.5 then
					wall(s, "RadiatorTube", x - 1, x + 1, 309, 322, z0, z1, C.Aluminum)
					neon(s, "Coolant", Vector3.new(0.5, 0.3, z1 - z0), CFrame.new(x, 322.1, (z0 + z1) / 2), BLUE, 0.15)
				end
			end
		end
		-- Couloir A : cul-de-sac fermé à z 32
		wall(s, "RadiatorTube", -111, -103, 309, 322, 30, 32, C.Aluminum)
		-- Jets de vapeur (couloirs B, C, D) : 3,4 s, actifs 40 %
		local vents = {
			{ -87, 68, 0 },
			{ -87, 48, 0.35 },
			{ -87, 24, 0.7 },
			{ -97, 54, 0.5 },
			{ -97, 30, 0.15 },
			{ -77, 60, 0.8 },
			{ -77, 38, 0.45 },
			{ -77, 20, 0.1 },
		}
		for _, v in vents do
			local floor = if v[2] > 44 then 311 else 314
			steam(s, CFrame.new(v[1], floor + 3.5, v[2]), Vector3.new(8, 7, 3), 3.4, 0.4, v[3])
		end
		-- Sortie : palier commun, puis le checkpoint à l'entrée du tube
		slab(s, -101, -65, 6, 14, 315, "Outlet")
		ctx.Checkpoint(first, Common.Facing(Vector3.new(-58, 318, 10), Vector3.xAxis))
		ctx.Coin(Vector3.new(-87, 313.5, 58))
		ctx.Coin(Vector3.new(-97, 313.5, 42))
		ctx.Coin(Vector3.new(-77, 316.5, 30))
		ctx.Coin(Vector3.new(-87, 317.5, 10))

		-- Clé USB 1 : couloir A, quatre jets rapides en vague (2,5 s, actifs 50 %)
		for k, z in { 62, 55, 48, 39 } do
			local floor = if z > 44 then 311 else 314
			steam(s, CFrame.new(-107, floor + 3.5, z), Vector3.new(8, 7, 3), 2.5, 0.5, (k - 1) * 0.2)
		end
		ctx.UsbKey(Vector3.new(-107, 316.3, 35), 1)

		-- Habillage : boîtes à eau aux deux bouts, étiquette
		for _, z in { 76.5, 17 } do
			Box(decor, "WaterTank", Vector3.new(4, 14, 6), CFrame.new(-116, 316, z), C.Black, METAL)
			Box(decor, "WaterTank", Vector3.new(4, 14, 6), CFrame.new(-68, 316, z), C.Black, METAL)
		end
		local label = Box(decor, "RadiatorLabel", Vector3.new(0.3, 6, 30), CFrame.new(-70.8, 318, 45), C.Bg)
		Props.Sign(label, "ANGA AIO 360", "Radiateur", BLUE, C.White, Enum.NormalId.Right)
		ctx.Lamp(Vector3.new(-90, 334, 44), BLUE:Lerp(C.White, 0.4), 1.3, 60)
	end

	------------------------------------------------------------------------------------
	-- Étape 2 : le tube de watercooling — boules de poussière, niches
	------------------------------------------------------------------------------------

	local X0, X1, Y0, Y1 = -52, 50, 318, 328 -- rampe du tube (le long de +X, z 4..16)
	local SLOPE = math.atan((Y1 - Y0) / (X1 - X0))
	local function floorAt(x: number): number
		return Y0 + (Y1 - Y0) * math.clamp((x - X0) / (X1 - X0), 0, 1)
	end

	-- Paroi de verre qui suit la pente entre xa et xb, sur la ligne z (collision : on ne sort pas du tube).
	local function tubeWall(parent: Instance, xa: number, xb: number, z: number)
		local ya, yb = floorAt(xa), floorAt(xb)
		local mid = Vector3.new((xa + xb) / 2, (ya + yb) / 2 + 3.5, z)
		local length = math.sqrt((xb - xa) ^ 2 + (yb - ya) ^ 2)
		local angle = math.atan((yb - ya) / (xb - xa))
		local pane = Build.Part({
			Name = "TubeGlass",
			Size = Vector3.new(length, 7, 1),
			CFrame = CFrame.new(mid) * CFrame.Angles(0, 0, angle),
			Color = GLASS,
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			CastShadow = false,
			Parent = parent,
		})
		return pane
	end

	local function stage2()
		local s = ctx.Stage(first + 1)
		-- Rampe (collision lisse) puis palier plat au sommet
		Build.Wedge({
			Name = "TubeFloor",
			Size = Vector3.new(12, Y1 - Y0, X1 - X0),
			CFrame = CFrame.fromMatrix(
				Vector3.new((X0 + X1) / 2, (Y0 + Y1) / 2, 10),
				-Vector3.zAxis,
				UP,
				Vector3.xAxis
			),
			Color = style.Floor,
			Material = style.FloorMat,
			Parent = s,
		})
		slab(s, X1, 58, 4, 16, Y1, "TubeTop")
		neon(
			decor,
			"TubeEdge",
			Vector3.new(X1 - X0 + 0.2, 0.3, 0.4),
			CFrame.new((X0 + X1) / 2, (Y0 + Y1) / 2 + 0.05, 4.2) * CFrame.Angles(0, 0, SLOPE),
			BLUE,
			0.3
		)
		neon(
			decor,
			"TubeEdge",
			Vector3.new(X1 - X0 + 0.2, 0.3, 0.4),
			CFrame.new((X0 + X1) / 2, (Y0 + Y1) / 2 + 0.05, 15.8) * CFrame.Angles(0, 0, SLOPE),
			BLUE,
			0.3
		)
		-- Parois : nord percée de 4 niches, sud percée de la sortie (x 43..49)
		local niches = { -30, -8, 14, 36 }
		local xa = X0
		for _, nx in niches do
			tubeWall(s, xa, nx - 3, 16.5)
			xa = nx + 3
		end
		tubeWall(s, xa, X1, 16.5)
		tubeWall(s, X0, 43, 3.5)
		tubeWall(s, 49, X1, 3.5)
		wall(s, "TubeGlass", 50, 58, Y1, Y1 + 7, 16, 17, GLASS, Enum.Material.Glass).Transparency = 0.55
		wall(s, "TubeGlass", 50, 58, Y1, Y1 + 7, 3, 4, GLASS, Enum.Material.Glass).Transparency = 0.55
		wall(s, "TubeCap", 58, 59, Y1, Y1 + 7, 3, 17, C.Nickel).Transparency = 0.2
		-- Verrière (décor, ni collision ni requêtes : la caméra passe au travers)
		local roof = Box(
			decor,
			"TubeRoof",
			Vector3.new((X1 - X0) / math.cos(SLOPE), 0.3, 14),
			CFrame.new((X0 + X1) / 2, (Y0 + Y1) / 2 + 9.5, 10) * CFrame.Angles(0, 0, SLOPE),
			GLASS,
			Enum.Material.Glass
		)
		roof.Transparency = 0.8
		neon(
			decor,
			"Coolant",
			Vector3.new((X1 - X0) / math.cos(SLOPE), 0.5, 1),
			roof.CFrame * CFrame.new(0, 0.4, 0),
			PALE,
			0.2
		)
		-- Niches (on s'y abrite quand une boule passe) : plancher + 3 parois
		for i, nx in niches do
			local top = floorAt(nx)
			local depth = if i == 4 then 10 else 6
			slab(s, nx - 3, nx + 3, 17, 17 + depth, top, "Niche")
			wall(s, "NicheGlass", nx - 4, nx - 3, top, top + 7, 16, 17 + depth, GLASS, Enum.Material.Glass).Transparency =
				0.55
			wall(s, "NicheGlass", nx + 3, nx + 4, top, top + 7, 16, 17 + depth, GLASS, Enum.Material.Glass).Transparency =
				0.55
			if i < 4 then
				wall(s, "NicheGlass", nx - 3, nx + 3, top, top + 7, 23, 24, GLASS, Enum.Material.Glass).Transparency =
					0.55
				ctx.Coin(Vector3.new(nx, top + 2.5, 20))
			end
		end
		-- Sortie sud, puis le checkpoint (les ventilateurs partent vers -Z)
		slab(s, 42, 52, -2, 3.5, 328.5, "Outlet")
		ctx.Checkpoint(first + 1, Common.Facing(Vector3.new(47, 332, -9), -Vector3.zAxis))
		ctx.Coin(Vector3.new(47, 331, 0))

		-- Boules de poussière : elles dévalent le tube, plongent sous le plancher en bas, remontent
		-- par le tube de retour et ressortent au sommet (x 55) : une toutes les ~8,6 s.
		local top = Vector3.new(55, Y1 + 4.5, 10)
		local loop = {
			Vector3.zero,
			Vector3.new(50, Y1 + 4.5, 10) - top,
			Vector3.new(-44, floorAt(-44) + 4.5, 10) - top,
			Vector3.new(-44, Y0 - 9, 10) - top,
			Vector3.new(55, Y1 - 9, 10) - top,
		}
		for k = 0, 2 do
			dustBall(s, top, loop, 9, k / 3, 9)
		end
		for _, x in { -44, 55 } do
			neon(decor, "Drain", Vector3.new(7, 0.2, 7), CFrame.new(x, floorAt(x) + 0.15, 10), HEAT, 0.4)
		end
		-- Tube de retour (décor), sous le tube principal
		local a, b = Vector3.new(-44, Y0 - 9, 10), Vector3.new(55, Y1 - 9, 10)
		local back = Rod(decor, "ReturnTube", Props.Along(a, b), (b - a).Magnitude, 11, GLASS, Enum.Material.Glass)
		back.Transparency = 0.7
		Rod(decor, "ReturnCoolant", Props.Along(a, b), (b - a).Magnitude, 2, PALE, NEON).Transparency = 0.3

		-- Clé USB 2 : la chambre de la pompe, au bout de la niche x 36 ; trois petites boules y
		-- tournent autour de la clé.
		local chamberTop = floorAt(36)
		slab(s, 28, 44, 27, 43, chamberTop, "PumpChamber")
		local orbitStart = Vector3.new(31, chamberTop + 2, 30)
		local orbit = {
			Vector3.zero,
			Vector3.new(10, 0, 0),
			Vector3.new(10, 0, 10),
			Vector3.new(0, 0, 10),
		}
		for k = 0, 2 do
			dustBall(s, orbitStart, orbit, 8, k / 3, 4)
		end
		ctx.UsbKey(Vector3.new(36, chamberTop + 2.4, 35), 2)
		ctx.Lamp(Vector3.new(0, 342, 10), PALE:Lerp(C.White, 0.3), 1.2, 60)
	end

	------------------------------------------------------------------------------------
	-- Étape 3 : les ventilateurs géants — pales et vent contraire
	------------------------------------------------------------------------------------

	local function stage3()
		local s = ctx.Stage(first + 2)
		local plates = {
			-- z0, z1, dessus, plan du ventilateur, barres, vitesse, vent
			{ -16, -40, 333, -28, 1, 1.2, 4 },
			{ -42, -66, 336, -54, 2, 0.75, 5 },
			{ -68, -92, 339, -80, 2, 0.9, 6 },
		}
		for i, p in plates do
			slab(s, 41, 53, p[2], p[1], p[3], "FanDeck")
			local hub = Vector3.new(47, p[3] + 11.5, p[4])
			blades(s, hub, 11, p[5], if i == 2 then -p[6] else p[6], (i * 0.37) % 1)
			fanFrame(hub, 26, if i == 2 then "Fan140" else "Fan120")
			-- Le ventilateur souffle vers nous (+Z)
			-- Rideau de vent juste devant les pales (côté d'arrivée) : il repousse vers +Z ; une fois
			-- les pales passées, plus de vent (on n'est jamais poussé dans les pales ni dans le vide).
			wind(s, Vector3.new(47, p[3] + 6, p[4] + 4.5), 12, 12, 7, Vector3.zAxis, p[7])
			ctx.Coin(Vector3.new(47, p[3] + 2.5, p[1] - 4))
		end
		slab(s, 41, 53, -97, -93, 342.5, "FanExit")
		ctx.Checkpoint(first + 2, Common.Facing(Vector3.new(47, 346, -104), -Vector3.xAxis))

		-- Clé USB 3 : saut porté par une rafale depuis le balcon du 2e ventilateur (12 studs de vide) ;
		-- retour en se laissant tomber sur une corniche plus basse, puis on remonte sur le pont.
		slab(s, 53, 57, -58, -48, 336, "WindBalcony")
		wind(s, Vector3.new(63, 341, -53), 10, 10, 20, Vector3.xAxis, 12, { 3, 0.5, 0 })
		local isle = slab(s, 69, 75, -57, -49, 336, "KeyIsle")
		Props.Decal(
			isle,
			"IsleMark",
			Vector3.new(5, 0.1, 5),
			CFrame.new(72, 336.06, -53),
			">>>",
			PALE,
			Enum.NormalId.Top,
			Enum.Font.GothamBlack
		)
		ctx.UsbKey(Vector3.new(72, 338.4, -53), 3)
		slab(s, 57, 63, -68, -62, 331, "ReturnLedge")
		ctx.Coin(Vector3.new(60, 333.5, -65))
		ctx.Lamp(Vector3.new(50, 356, -54), BLUE:Lerp(C.White, 0.4), 1.2, 60)
	end

	------------------------------------------------------------------------------------
	-- Étape 4 : la chambre froide — glace qui fond sous les rafales latérales
	------------------------------------------------------------------------------------

	local function stage4()
		local s = ctx.Stage(first + 3)
		-- Série A (vers -X), en zigzag
		for k, x in { 36, 29, 22 } do
			frost(s, x, if k % 2 == 1 then -102 else -106, 346.5 + 0.5 * k, 5, 5, 0.8)
		end
		slab(s, 8, 18, -110, -98, 349, "Shelter")
		wall(s, "Windbreak", 8, 18, 349, 355, -111, -110, GLASS, Enum.Material.Glass).Transparency = 0.5
		-- Série B : pont de glace sous rafales venues de l'avant (+Z, vers le vide)
		for k, x in { 3, -4, -11, -18, -25 } do
			frost(s, x, -104, 349.2 + 0.8 * k, 5, 5, 0.8)
		end
		wind(s, Vector3.new(-11, 355, -104), 38, 12, 20, Vector3.zAxis, 5, { 3.4, 0.5, 0 })
		slab(s, -44, -30, -110, -98, 354, "Shelter")
		wall(s, "Windbreak", -44, -30, 354, 360, -111, -110, GLASS, Enum.Material.Glass).Transparency = 0.5
		-- Série C (vers +Z), rafales vers l'est
		for k, z in { -93, -86, -79 } do
			frost(s, -38, z, 354 + 0.8 * k, 5, 5, 0.8)
		end
		wind(s, Vector3.new(-38, 360, -86), 20, 12, 20, Vector3.xAxis, 5, { 3, 0.5, 0.5 })
		slab(s, -44, -32, -74, -64, 357.5, "Shelter")
		for k, z in { -59.5, -52.5 } do
			frost(s, -38, z, 358 + 0.5 * k, 5, 5, 0.8)
		end
		wind(s, Vector3.new(-38, 362, -55), 16, 12, 14, -Vector3.xAxis, 5, { 3, 0.5, 0 })
		ctx.Checkpoint(first + 3, Common.Facing(Vector3.new(-38, 360, -40), -Vector3.xAxis))
		ctx.Coin(Vector3.new(29, 350.5, -106))
		ctx.Coin(Vector3.new(13, 351.5, -104))
		ctx.Coin(Vector3.new(-11, 354.5, -104))
		ctx.Coin(Vector3.new(-37, 356.5, -104))
		ctx.Coin(Vector3.new(-38, 360, -69))
		-- Givre (décor) dans les coins des abris
		for _, p in { { 16.5, 350.1, -108.5 }, { -42.5, 355.1, -108.5 }, { -43, 358.6, -65 } } do
			Box(
				decor,
				"Frost",
				Vector3.new(3, 2.2, 1.4),
				CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, 0.4, 0.3),
				C.White,
				Enum.Material.Ice
			)
		end
		ctx.Lamp(Vector3.new(-10, 372, -90), PALE:Lerp(C.White, 0.3), 1.3, 70)
	end

	------------------------------------------------------------------------------------
	-- Étape 5 : la sortie d'air — poussière, vapeur, dernier ventilateur, escalier de glace
	------------------------------------------------------------------------------------

	local function stage5()
		local s = ctx.Stage(first + 4)
		-- Plateau de la poussière : deux boules se croisent en boucle (x -49 vers +Z, x -57 vers -Z)
		slab(s, -60, -46, -54, -26, 361.5, "DustDeck")
		local start = Vector3.new(-49, 363.5, -52)
		local lap = { Vector3.zero, Vector3.new(0, 0, 24), Vector3.new(-8, 0, 24), Vector3.new(-8, 0, 0) }
		for k = 0, 2 do
			dustBall(s, start, lap, 9, k / 3, 4)
		end
		-- Passerelle aux deux jets de vapeur (onde verte)
		slab(s, -74, -62, -43, -37, 364, "SteamBridge")
		steam(s, CFrame.new(-65, 367.5, -40), Vector3.new(3, 7, 6), 3, 0.4, 0)
		steam(s, CFrame.new(-71, 367.5, -40), Vector3.new(3, 7, 6), 3, 0.4, 0.875)
		slab(s, -96, -76, -48, -32, 367, "Plenum")
		-- Dernier ventilateur (vers -Z) avec vent contraire
		slab(s, -94, -82, -62, -50, 370, "FanDeck")
		local hub = Vector3.new(-88, 381.5, -56)
		blades(s, hub, 11, 2, 0.85, 0.2)
		fanFrame(hub, 26, "Fan140")
		wind(s, Vector3.new(-88, 376, -52.25), 12, 12, 5.5, Vector3.zAxis, 5)
		-- Escalier de glace sous un jet de vapeur horizontal, jusqu'à la porte
		for k, z in { -64.25, -70.25, -76.25 } do
			frost(s, -88, z, 370 + 2.5 * k, 8, 4.5, 0.8)
		end
		steam(s, CFrame.new(-88, 376.5, -70.25), Vector3.new(12, 3, 3), 3, 0.35, 0.3, false)
		for _, x in { -95, -81 } do
			Box(s, "SteamPipe", Vector3.new(2, 2, 2), CFrame.new(x, 376.5, -70.25), C.Copper, METAL)
		end
		ctx.Coin(Vector3.new(-53, 364, -40))
		ctx.Coin(Vector3.new(-68, 366.5, -40))
		ctx.Coin(Vector3.new(-86, 369.5, -40))
		ctx.Coin(Vector3.new(-88, 372.5, -52))
		ctx.Coin(Vector3.new(-88, 380, -76))
		ctx.Lamp(Vector3.new(-75, 390, -55), BLUE:Lerp(C.White, 0.4), 1.3, 60)
	end

	------------------------------------------------------------------------------------
	-- Décor
	------------------------------------------------------------------------------------

	-- Petit ventilateur de secours (cadre, anneau, pales soudées à un moyeu qui tourne).
	local function simpleFan(parent: Instance, cf: CFrame, diameter: number, color: Color3, speed: number): Model
		local model = Build.Model("Fan", parent)
		local half = diameter * 0.54
		for k = 0, 3 do
			local rot = cf * CFrame.Angles(0, 0, k * math.pi / 2)
			Box(model, "FrameBar", Vector3.new(diameter * 1.08, 1.6, 2), rot * CFrame.new(0, half, 0), C.Black, METAL)
		end
		Props.Ring(
			model,
			"FanRing",
			cf * CFrame.new(0, 0, -1.1) * CFrame.Angles(0, math.pi / 2, 0),
			diameter / 2,
			0.6,
			0.4,
			12,
			color,
			NEON
		)
		local hub = Props.SpinHub(model, cf, "Z", speed)
		for k = 0, 4 do
			local blade = Box(
				model,
				"Blade",
				Vector3.new(diameter * 0.18, diameter * 0.4, 0.4),
				cf
					* CFrame.Angles(0, 0, k * math.pi * 2 / 5)
					* CFrame.new(0, diameter * 0.24, 0)
					* CFrame.Angles(0, 0.5, 0),
				C.Black:Lerp(color, 0.2)
			)
			Props.WeldTo(hub, blade)
		end
		Rod(model, "Hub", cf * CFrame.Angles(0, math.pi / 2, 0), 1.2, diameter * 0.24, C.MetalDark)
		return model
	end

	-- Radiateur AIO géant debout contre la vitre (+X), 3 ventilateurs tournés vers le parcours.
	-- Modèle à plat (123 × 25 × 33 : longueur X, épaisseur Y avec les ventilateurs côté Y bas, largeur Z) :
	-- dressé sur son long côté, longueur → Z, ventilateurs → -X, largeur → hauteur (≈ 35 studs) ;
	-- Anchor = bord bas (Z min du modèle) posé au sol, face des ventilateurs en x = 92.
	local function giantAio()
		local standing = CFrame.fromMatrix(Vector3.new(92, base, -20), Vector3.zAxis, Vector3.xAxis, Vector3.yAxis)
		ModelLibrary.Place("AioRadiator", standing, decor, {
			Collide = false,
			Fit = Vector3.one * 130,
			Anchor = Vector3.new(0, 0, -16.5),
		}, function(): Instance?
			local model = Build.Model("AioRadiator", decor)
			Box(model, "Core", Vector3.new(8, 40, 120), CFrame.new(112, base + 24, -20), C.Aluminum, METAL)
			for _, y in { base + 3, base + 45 } do
				Box(model, "Tank", Vector3.new(10, 6, 124), CFrame.new(112, y, -20), C.Black, METAL)
			end
			for k = 0, 9 do
				Box(
					model,
					"FinLine",
					Vector3.new(8.2, 0.4, 118),
					CFrame.new(112, base + 8 + k * 3.6, -20),
					C.MetalLight,
					METAL
				)
			end
			for i = -1, 1 do
				local fanCf = Common.Facing(Vector3.new(106.5, base + 24, -20 + i * 40), -Vector3.xAxis)
				simpleFan(model, fanCf, 34, BLUE, 2.5)
			end
			local plate = Box(model, "AioLabel", Vector3.new(0.3, 5, 40), CFrame.new(107.8, base + 49, -20), C.Bg)
			Props.Sign(plate, "CRYO TOWER", "AIO 360 · Anga", BLUE, C.White, Enum.NormalId.Left)
			return model
		end)
	end

	-- Réservoir de pompe géant, relié au tube de l'étape 2.
	local function reservoir()
		local position = Vector3.new(4, base, 44)
		placeModel("PumpReservoir", CFrame.new(position), decor, 56, function(): Instance?
			local model = Build.Model("PumpReservoir", decor)
			Rod(model, "PumpBase", CFrame.new(position + Vector3.new(0, 4, 0)) * VERTICAL, 8, 20, C.Black)
			local glass = Rod(
				model,
				"Reservoir",
				CFrame.new(position + Vector3.new(0, 30, 0)) * VERTICAL,
				44,
				16,
				GLASS,
				Enum.Material.Glass
			)
			glass.Transparency = 0.6
			Rod(model, "Coolant", CFrame.new(position + Vector3.new(0, 26, 0)) * VERTICAL, 34, 13, PALE, NEON).Transparency =
				0.25
			Rod(model, "Cap", CFrame.new(position + Vector3.new(0, 53, 0)) * VERTICAL, 3, 17, C.Nickel, METAL)
			return model
		end)
		Props.Tube(decor, {
			position + Vector3.new(0, 55, 0),
			position + Vector3.new(0, 62, 0),
			Vector3.new(-20, base + 62, 44),
			Vector3.new(-20, base + 32, 12),
		}, 1.5, PALE)
	end

	-- Ventirad géant sous la sortie d'air (paysage du fond).
	local function cooler()
		local position = Vector3.new(-66, base, -66)
		-- Assez bas pour ne jamais passer pour une plateforme (≥ 25 studs sous le parcours)
		placeModel("CpuCooler", CFrame.new(position), decor, 34, function(): Instance?
			local model = Build.Model("CpuCooler", decor)
			Box(model, "Socket", Vector3.new(34, 3, 34), CFrame.new(position + Vector3.new(0, 1.5, 0)), C.Black)
			Box(model, "Ihs", Vector3.new(22, 2, 22), CFrame.new(position + Vector3.new(0, 4, 0)), C.Nickel, METAL)
			for i = -2, 2 do
				Rod(model, "HeatPipe", CFrame.new(position + Vector3.new(i * 4, 17, 0)) * VERTICAL, 26, 2, C.Copper)
			end
			for k = 0, 7 do
				Box(
					model,
					"Fin",
					Vector3.new(30, 0.5, 22),
					CFrame.new(position + Vector3.new(0, 13 + k * 2.2, 0)),
					C.Aluminum,
					METAL
				)
			end
			Box(model, "Cap", Vector3.new(31, 2, 23), CFrame.new(position + Vector3.new(0, 31, 0)), C.Black, METAL)
			neon(
				model,
				"CapGlow",
				Vector3.new(31.4, 0.5, 23.4),
				CFrame.new(position + Vector3.new(0, 30, 0)),
				BLUE,
				0.2
			)
			return model
		end)
	end

	-- Dusty, le sbire : boule de poussière grise aux yeux rouges, devant la porte.
	local function dusty()
		local position = Vector3.new(-74, 386, -70)
		local cf = Common.Facing(position, Vector3.new(-1, 0, 0.3))
		local minion = placeModel("Dusty", cf, decor, 8, function(): Instance?
			local model = Build.Model("Dusty", decor)
			local body = Box(model, "Body", Vector3.one * 7, cf * CFrame.new(0, 3.5, 0), GRIME, Enum.Material.Fabric)
			body.Shape = Enum.PartType.Ball
			for k = 0, 5 do
				local tuft = Box(
					model,
					"Tuft",
					Vector3.one * 2.6,
					cf * CFrame.Angles(k * 1.1, k * 2.3, 0) * CFrame.new(0, 3.5, 0) * CFrame.new(0, 3.2, 0),
					GRIME:Lerp(C.White, 0.2),
					Enum.Material.Fabric
				)
				tuft.Shape = Enum.PartType.Ball
			end
			for _, side in { -1, 1 } do
				neon(model, "Eye", Vector3.new(1.2, 1.4, 0.4), cf * CFrame.new(side * 1.3, 4.4, -3.3), LETHAL, 0)
			end
			Box(model, "Frown", Vector3.new(2.6, 0.4, 0.3), cf * CFrame.new(0, 2.4, -3.45), C.Black)
			return model
		end)
		if minion then
			ctx.Infected(minion)
		end
		local plate = Box(
			decor,
			"DustyTag",
			Vector3.new(8, 2.2, 0.3),
			Common.Facing(position + Vector3.new(0, 10.5, 0), Vector3.new(-1, 0, 0.3)),
			C.Bg
		)
		plate.Transparency = 1
		Props.Sign(plate, "DUSTY", nil, GRIME:Lerp(C.White, 0.5))
		ctx.Infected(plate)
	end

	local function walls()
		-- Ventilateurs muraux (arrière, +Z) : propres = RGB bleu, infectés = bouchés de poussière
		for i, x in { -40, 20, 80 } do
			local cf = Common.Facing(Vector3.new(x, base + 60, 130), -Vector3.zAxis)
			placeModel("Fan120", cf * CFrame.Angles(math.pi / 2, 0, 0), decor, 30, function(): Instance?
				return simpleFan(decor, cf, 28, BLUE, 3 + i * 0.5)
			end)
			local dust = Build.Model("DustClog", decor)
			for k = 0, 2 do
				local blob = Box(
					dust,
					"Dust",
					Vector3.new(7, 5, 3),
					cf * CFrame.new(-6 + k * 6, -4 + (k % 2) * 7, -2),
					GRIME,
					Enum.Material.Fabric
				)
				blob.Shape = Enum.PartType.Ball
			end
			ctx.Infected(dust)
		end
		-- Thermomètre : 97 °C (infecté) / 65 °C (propre), sous la fenêtre de l'app « Verdict » (même paroi :
		-- à base + 64, il était dessous)
		local hot = Box(decor, "Thermo", Vector3.new(0.3, 16, 40), CFrame.new(-131.5, base + 40, 0), C.Bg)
		hot.Transparency = 1
		Props.Sign(hot, "97 °C", "SURCHAUFFE", Color3.fromRGB(255, 120, 96), C.White, Enum.NormalId.Right)
		ctx.Infected(hot)
		local cold = Box(decor, "Thermo", Vector3.new(0.3, 16, 40), CFrame.new(-131.5, base + 40, 0), C.Bg)
		cold.Transparency = 1
		Props.Sign(cold, "65 °C", "Cryo Tower au frais", BLUE, C.White, Enum.NormalId.Right)
		ctx.Cleaned(cold)
		-- Bandes lumineuses (RGB propre / alerte)
		local rgb = Build.Model("WallRgb", decor)
		local alert = Build.Model("WallAlert", decor)
		-- (hors de la salle du terminal : x < -80, z < -80)
		for _, w in { { 0, 131.4, 264, 0 }, { 27, -131.4, 210, 0 }, { -131.4, 27, 0, 210 } } do
			local size = if w[3] > 0 then Vector3.new(w[3], 0.8, 0.4) else Vector3.new(0.4, 0.8, w[4])
			neon(rgb, "RgbStrip", size, CFrame.new(w[1], base + 92, w[2]), BLUE, 0.15):AddTag("RgbStrip")
			neon(alert, "AlertStrip", size, CFrame.new(w[1], base + 92, w[2]), Color3.fromRGB(255, 96, 72), 0.35)
		end
		ctx.Cleaned(rgb)
		ctx.Infected(alert)
		-- Poussière en suspension sur les plateformes (infecté)
		local fluff = Build.Model("DustBunnies", decor)
		for _, p in { { -87, 311.6, 72 }, { -20, 322, 10 }, { 47, 333.6, -36 }, { 13, 349.6, -101 }, { -53, 362, -30 } } do
			local blob =
				Box(fluff, "Bunny", Vector3.new(2.4, 1.2, 2), CFrame.new(p[1], p[2], p[3]), GRIME, Enum.Material.Fabric)
			blob.Shape = Enum.PartType.Ball
		end
		ctx.Infected(fluff)
		ctx.Lamp(Vector3.new(60, base + 50, -20), BLUE:Lerp(C.White, 0.5), 1.4, 90)
	end

	stage1()
	stage2()
	stage3()
	stage4()
	stage5()
	giantAio()
	reservoir()
	cooler()
	dusty()
	walls()
	ctx.TerminalRoom()
end
