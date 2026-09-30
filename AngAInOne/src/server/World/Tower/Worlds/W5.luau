--!strict
--[[
	Monde 5 : The Core (CPU) — « Processeur à 100 %, un crypto-mineur ! »

	Minor, le crypto-mineur, fait chauffer le processeur : il a ouvert le 2ᵉ socket de la carte
	mère (bi-processeur) pour en arracher la puce, et ses pioches géantes tapent sur les VRM.

	Parcours (entrée au coin (-88, 410, -88), porte de la salle du terminal en (80, 480, -88)) :
	1. Les VRM — passerelle sur les dissipateurs d'alimentation, 4 PIOCHES qui balaient (Pendulum).
	2. La spirale (1) — on grimpe autour du ventirad à caloducs sur des PLATEFORMES EN LATENCE
	   (LagMover) : elles partent et reviennent par à-coups, en retard.
	3. La spirale (2) — trois ROUES DE CHARGEMENT (Spinner) de plus en plus rapides.
	4. Le caloduc brûlant (bouches de CHALEUR en quinconce) puis le sprint sur la grille de broches
	   du socket ouvert, balayée par des LASERS.
	5. Le socket du mineur : pioches jumelles, latence au-dessus de la cavité, chaleur + laser,
	   ascenseur (Mover) et dernière roue de chargement jusqu'à la porte.

	LAG SPIKE (incident vedette) : l'horloge des pièges avance par à-coups de 0,4 s. Les fenêtres
	sûres font toutes ≥ 1 s (pioches ~1,1 s, latence ~1,3 s, chaleur 1,8 s) : le lag rend le
	timing plus dur (il faut attendre le « saut » suivant) sans rendre un passage impossible.

	Clés USB : K1 derrière la 2ᵉ pioche (au bord de la façade), K2 au sommet de la grande roue de
	chargement dressée derrière la spirale, K3 sur les broches isolées au-dessus de la cavité du socket.
]]

local WorldFolder = script.Parent.Parent.Parent
local Build = require(WorldFolder.Build)
local Props = require(WorldFolder.Props)
local Common = require(script.Parent.Parent.Common)
local Kit = require(script.Parent.W5Kit)

type Ctx = Common.WorldContext

local UP = Vector3.yAxis
local C = Common.C
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local VERTICAL = Common.VERTICAL
local FLAT = Kit.FLAT
local LETHAL = Common.Colors.Lethal
local GLITCH = Common.Colors.Glitch
local SAFE = Common.Colors.Safe
local Box, Rod = Props.Box, Props.Rod
local facing = Common.Facing

local EAST, NORTH, SOUTH = Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis
local COPPER = C.Copper
local ALU = C.Aluminum
local LAG = Color3.fromRGB(128, 116, 84) -- plateformes en latence : laiton terne
local PIN = Color3.fromRGB(214, 170, 72) -- broches dorées

-- Ventirad (centre au sol) et spirale : rayon de l'axe de la course, abscisse curviligne s
-- (s = 0 face avant, θ = -90°), sens trigonométrique vu de dessus (avant → est → fond → ouest).
local CORE = Vector3.new(-16, 0, 36)
local R = 44
local LANE = 9 -- largeur de la spirale
local COOLER_H = 62 -- hauteur du ventirad (le caloduc brûlant part de son sommet)

local function theta(s: number): number
	return -math.pi / 2 + s / R
end

-- Point de l'axe de la spirale (dr > 0 : vers l'extérieur).
local function arc(s: number, y: number, dr: number?): Vector3
	local t = theta(s)
	local r = R + (dr or 0)
	return Vector3.new(CORE.X + r * math.cos(t), y, CORE.Z + r * math.sin(t))
end

local function arcDir(s: number): Vector3
	local t = theta(s)
	return Vector3.new(-math.sin(t), 0, math.cos(t))
end

local function outward(s: number): Vector3
	local t = theta(s)
	return Vector3.new(math.cos(t), 0, math.sin(t))
end

return function(ctx: Ctx)
	local B = ctx.Base
	local style = ctx.Style
	local P, S = style.Primary, style.Secondary
	local decor = ctx.Decor

	ctx.Void()
	ctx.Entrance()

	-- Tronçon de spirale (plateforme droite tangente au milieu de [s0, s1]).
	local function arcSlab(parent: Instance, s0: number, s1: number, y: number, name: string?): Part
		local mid = (s0 + s1) / 2
		local chord = 2 * R * math.sin((s1 - s0) / (2 * R)) + 0.3
		return Kit.Slab(ctx, parent, arc(mid, y), arcDir(mid), chord, LANE, name)
	end

	-- Colonne de soutien (décor) sous un point, jusqu'au plancher du monde.
	local function support(position: Vector3, diameter: number?)
		local h = position.Y - B
		if h > 2 then
			Rod(
				decor,
				"Support",
				CFrame.new(position.X, B + h / 2, position.Z) * VERTICAL,
				h,
				diameter or 2.4,
				style.Wall
			)
		end
	end

	------------------------------------------------------------------------------------
	-- Décor : ventirad géant (la spirale s'enroule autour), sockets, VRM, puce arrachée
	------------------------------------------------------------------------------------

	local coolerCf = CFrame.new(CORE.X, B, CORE.Z)
	Kit.Place("CpuSocket", coolerCf, decor, 5, function()
		local m = Build.Model("CpuSocket", decor)
		Box(m, "SocketFrame", Vector3.new(66, 4, 66), coolerCf * CFrame.new(0, 2, 0), C.Black)
		for k = 0, 3 do
			Box(
				m,
				"LoadPlate",
				Vector3.new(62, 1.2, 4),
				coolerCf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 4.5, -30),
				ALU,
				METAL
			)
		end
		return m
	end)
	Kit.Place("CpuCooler", coolerCf * CFrame.new(0, 4, 0), decor, COOLER_H - 4, function()
		local m = Build.Model("CpuCooler", decor)
		Box(m, "ColdPlate", Vector3.new(30, 4, 30), coolerCf * CFrame.new(0, 6, 0), COPPER, METAL)
		-- Tour d'ailettes horizontales empilées (on les voit défiler en montant la spirale)
		for i = 0, 13 do
			local fin = Box(m, "Fin", Vector3.new(44, 0.7, 44), coolerCf * CFrame.new(0, 14 + i * 3.3, 0), ALU, METAL)
			fin.Reflectance = 0.06
		end
		Box(m, "TopCap", Vector3.new(45, 2.4, 45), coolerCf * CFrame.new(0, COOLER_H - 1.2, 0), C.Black, METAL)
		for k = 0, 3 do
			local rim = Build.Neon({
				Name = "CapGlow",
				Size = Vector3.new(45.6, 0.7, 0.7),
				CFrame = coolerCf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, COOLER_H - 2.6, -22.6),
				Color = P,
				Transparency = 0.15,
				Parent = m,
			})
			rim:AddTag("RgbStrip")
		end
		-- Caloducs : jambes verticales + coudes en U sous la tour
		for i = -2, 2 do
			for _, z in { -8, 8 } do
				Rod(m, "HeatPipe", coolerCf * CFrame.new(i * 7, 34, z) * VERTICAL, 50, 2.6, COPPER)
			end
			Rod(m, "PipeBend", coolerCf * CFrame.new(i * 7, 9, 0) * CFrame.Angles(0, math.pi / 2, 0), 18, 2.6, COPPER)
		end
		local plate = Box(
			m,
			"Brand",
			Vector3.new(30, 8, 0.4),
			coolerCf * CFrame.new(0, COOLER_H + 0.3, 0) * CFrame.Angles(math.pi / 2, 0, 0),
			C.Bg
		)
		plate.Transparency = 1
		Props.Label(plate, "THE CORE", P, Enum.NormalId.Front, Enum.Font.GothamBlack)
		-- Ventilateur 140 mm géant vissé sur la face avant de la tour d'ailettes (axe du modèle = Y)
		local face = Vector3.new(CORE.X, B + 36, CORE.Z - 22.5)
		Kit.Place("Fan140", CFrame.fromMatrix(face, EAST, SOUTH), m, 40, function()
			return Props.Fan(
				m,
				CFrame.fromMatrix(face, SOUTH, UP),
				38,
				P,
				7,
				{ Speed = 3, Lite = true, Brand = "CORE" }
			)
		end)
		return m
	end)

	-- VRM : rangées de dissipateurs à ailettes sous la passerelle de l'étape 1
	local function vrm(center: Vector3, look: Vector3, length: number)
		Kit.Place("VrmHeatsink", facing(center, look), decor, 8, function()
			local m = Build.Model("VrmHeatsink", decor)
			local cf = facing(center, look)
			Box(m, "VrmBase", Vector3.new(12, 3, length), cf * CFrame.new(0, 1.5, 0), C.MetalDark, METAL)
			Props.Fins(m, cf * CFrame.new(0, 6, 0), 11, 6, length, math.floor(length / 4), ALU)
			Build.Neon({
				Name = "VrmTrace",
				Size = Vector3.new(0.4, 0.4, length),
				CFrame = cf * CFrame.new(6.1, 2.5, 0),
				Color = P,
				Transparency = 0.3,
				Parent = m,
			})
			return m
		end)
		-- Selfs (chokes) le long des dissipateurs
		local right = look:Cross(UP)
		for k = -1, 1 do
			Box(
				decor,
				"Choke",
				Vector3.new(5, 5, 5),
				facing(center + right * 9 + look * (k * length / 3) + Vector3.new(0, 2.5, 0), look),
				C.Black
			)
		end
	end
	vrm(Vector3.new(-52, B, -88), EAST, 52)
	vrm(Vector3.new(-16, B, -54), NORTH, 60)

	-- Socket ouvert du mineur (2ᵉ processeur) : anneau de broches (x ∈ [4, 76], z ∈ [-128, -40]),
	-- cavité centrale vide où bave le glitch du mineur.
	local SX0, SX1, SZ0, SZ1, RIM = 4, 76, -128, -40, 16
	local socketTop = B + 60
	local socketCenter = Vector3.new((SX0 + SX1) / 2, B, (SZ0 + SZ1) / 2)
	Kit.Place("CpuSocket", CFrame.new(socketCenter.X, socketTop - 6, socketCenter.Z), decor, 4, function()
		local m = Build.Model("OpenSocket", decor)
		for _, side in { -1, 1 } do
			Box(
				m,
				"SocketLip",
				Vector3.new(SX1 - SX0 + 2, 5, 1.2),
				CFrame.new(socketCenter.X, socketTop - 4, socketCenter.Z + side * (SZ1 - SZ0 + 2) / 2),
				C.Black
			)
			Box(
				m,
				"SocketLip",
				Vector3.new(1.2, 5, SZ1 - SZ0 + 2),
				CFrame.new(socketCenter.X + side * (SX1 - SX0 + 2) / 2, socketTop - 4, socketCenter.Z),
				C.Black
			)
		end
		-- Levier de verrouillage relevé (le mineur a ouvert le socket)
		Rod(
			m,
			"LoadLever",
			Props.Along(Vector3.new(SX1 + 3, socketTop - 3, SZ1 - 4), Vector3.new(SX1 + 3, socketTop + 26, SZ1 + 6)),
			31,
			1.6,
			ALU
		)
		return m
	end)
	-- Côtés nord et est du socket : broches arrachées, cadre nu 5 studs plus bas (cul-de-sac)
	for _, r in { { SX0 + RIM, SX1, SZ1 - RIM, SZ1 }, { SX1 - RIM, SX1, SZ0 + RIM, SZ1 - RIM } } do
		Kit.Solid(
			decor,
			"BarePins",
			Vector3.new(r[2] - r[1], 2, r[4] - r[3]),
			CFrame.new((r[1] + r[2]) / 2, socketTop - 6, (r[3] + r[4]) / 2),
			C.PcbDark,
			SMOOTH
		)
	end
	-- Carte mère sous le socket (le « sol » du socket, loin sous l'anneau)
	Box(
		decor,
		"Motherboard",
		Vector3.new(SX1 - SX0 + 12, 2, SZ1 - SZ0 + 12),
		CFrame.new(socketCenter.X, socketTop - 8, socketCenter.Z),
		C.PcbDark
	)
	for _, x in { SX0 + 10, SX1 - 10 } do
		support(Vector3.new(x, socketTop - 9, SZ0 + 12), 5)
		support(Vector3.new(x, socketTop - 9, SZ1 - 12), 5)
	end
	-- Flaque de glitch du mineur au fond de la cavité : mortelle (magenta)
	local pool = ctx.Hazard(
		decor,
		"MinerGlitch",
		Vector3.new(SX1 - SX0 - 2 * RIM, 0.6, SZ1 - SZ0 - 2 * RIM),
		CFrame.new(socketCenter.X, socketTop - 7, socketCenter.Z),
		GLITCH,
		"Hazard"
	)
	pool.Transparency = 0.55

	-- La puce arrachée, posée de travers sur le bord du socket
	local chipCf = CFrame.new(SX1 - 8, socketTop, -62) * CFrame.Angles(0, math.rad(20), math.rad(58))
	Kit.Place("CpuChip", chipCf, decor, 3, function()
		local m = Build.Model("CpuChip", decor)
		Box(m, "Substrate", Vector3.new(30, 1.4, 30), chipCf * CFrame.new(0, 0.7, 0), Color3.fromRGB(40, 92, 60))
		local ihs = Box(m, "Ihs", Vector3.new(22, 1.6, 22), chipCf * CFrame.new(0, 2.2, 0), C.Nickel, METAL)
		Props.Label(ihs, "CORE i∞", P, Enum.NormalId.Top, Enum.Font.GothamBlack)
		Box(m, "GoldPads", Vector3.new(26, 0.2, 26), chipCf * CFrame.new(0, -0.05, 0), C.Gold, Enum.Material.Foil)
		return m
	end)

	------------------------------------------------------------------------------------
	-- Étape 1 (21) : les VRM et les pioches du mineur
	------------------------------------------------------------------------------------

	local s1 = ctx.Stage(21)
	local zA = -88 -- passerelle vers l'est
	Kit.Slab(ctx, s1, Vector3.new(-65, B + 10, zA), EAST, 30, LANE, "VrmBridge")
	Kit.Slab(ctx, s1, Vector3.new(-37, B + 11.5, zA), EAST, 26, LANE, "VrmBridge")
	Kit.Slab(ctx, s1, Vector3.new(-16, B + 13, zA), EAST, 16, 16, "VrmCorner")
	Kit.Slab(ctx, s1, Vector3.new(-16, B + 14.5, -65), NORTH, 30, LANE, "VrmBridge")
	Kit.Slab(ctx, s1, Vector3.new(-16, B + 16, -33), NORTH, 34, LANE, "VrmBridge")
	-- Pioches : balancement en travers de la passerelle (tête au ras du sol au passage)
	Kit.Pickaxe(ctx, s1, Vector3.new(-62, B + 11.2, zA), NORTH, 17, 55, 3.2, 0)
	Kit.Pickaxe(ctx, s1, Vector3.new(-40, B + 12.7, zA), NORTH, 17, 55, 3.0, 0.35, 26)
	Kit.Pickaxe(ctx, s1, Vector3.new(-16, B + 15.7, -64), EAST, 17, 55, 2.8, 0.1)
	-- Pioches jumelles, en opposition : on s'arrête entre les deux
	Kit.Pickaxe(ctx, s1, Vector3.new(-16, B + 17.2, -40), EAST, 17, 55, 2.6, 0.2)
	Kit.Pickaxe(ctx, s1, Vector3.new(-16, B + 17.2, -29), EAST, 17, 55, 2.6, 0.7)
	for _, p in
		{
			Vector3.new(-72, B + 12.5, zA),
			Vector3.new(-50, B + 14, zA),
			Vector3.new(-16, B + 15.5, zA),
			Vector3.new(-16, B + 18.5, -52),
		}
	do
		ctx.Coin(p)
	end
	-- K1 : derrière la 2ᵉ pioche, deux broches de self au bord de la façade
	Kit.Slab(ctx, s1, Vector3.new(-40, B + 12.5, -98.5), EAST, 3.6, 3.6, "ChokeStep")
	Kit.Slab(ctx, s1, Vector3.new(-40, B + 14, -107.5), EAST, 7, 7, "KeyLedge")
	ctx.UsbKey(Vector3.new(-40, B + 16.5, -107.5), 1)
	support(Vector3.new(-40, B + 12, -107.5))
	support(Vector3.new(-65, B + 8, zA))
	support(Vector3.new(-16, B + 11, zA))
	ctx.Lamp(Vector3.new(-40, B + 34, -70), P:Lerp(C.White, 0.5), 1.2, 60)

	-- Checkpoint 21 : pied de la spirale (face avant du ventirad)
	local cp21 = arc(0, B + 18)
	local cp22 = arc(104, B + 32)
	local cp23 = arc(236, B + 44)
	Kit.Checkpoint(ctx, 21, s1, cp21, Kit.Toward(arcDir(0), cp21, cp22), arcDir(0))

	------------------------------------------------------------------------------------
	-- Étape 2 (22) : spirale, plateformes en latence
	------------------------------------------------------------------------------------

	local s2 = ctx.Stage(22)
	local function lag(
		s0: number,
		s1_: number,
		y: number,
		offset: Vector3,
		period: number,
		steps: number,
		phase: number
	): Part
		local mid = (s0 + s1_) / 2
		return Kit.LagMover(ctx, s2, arc(mid, y), arcDir(mid), s1_ - s0, 8, offset, period, steps, phase, LAG, P)
	end
	arcSlab(s2, 8, 16, B + 18)
	lag(18.5, 25.5, B + 19.5, outward(22) * 11, 5.2, 4, 0)
	arcSlab(s2, 28, 36, B + 21)
	lag(38.5, 45.5, B + 22.5, Vector3.new(0, -8, 0), 4.5, 3, 0.4)
	arcSlab(s2, 48, 56, B + 24)
	lag(58.5, 65, B + 25.5, outward(62) * 10, 5, 5, 0.1)
	lag(67.5, 74, B + 27, outward(71) * 10, 5, 5, 0.6)
	arcSlab(s2, 76.5, 84, B + 28.5)
	lag(86.5, 93.5, B + 30, outward(90) * 9, 4.4, 4, 0.3)
	for _, c in { { 12, 18 }, { 32, 21 }, { 52, 24 }, { 80, 28.5 } } do
		ctx.Coin(arc(c[1], B + c[2] + 2.5))
	end
	for _, s in { 12, 52 } do
		support(arc(s, B + 15))
	end
	Kit.Checkpoint(ctx, 22, s2, cp22, Kit.Toward(arcDir(104), cp22, cp23), arcDir(104))
	support(cp22 - Vector3.new(0, 2, 0), 4)

	------------------------------------------------------------------------------------
	-- Étape 3 (23) : spirale, roues de chargement
	------------------------------------------------------------------------------------

	local s3 = ctx.Stage(23)
	local base3 = 104
	local function wheel(c: number, y: number, ring: number, count: number, speed: number, phase: number)
		local s = base3 + c
		return Kit.Spinner(ctx, s3, arc(s, y - 0.5), -arcDir(s), ring, count, speed, phase, 7, P)
	end
	arcSlab(s3, base3 + 8, base3 + 14, B + 32)
	arcSlab(s3, base3 + 14, base3 + 20, B + 33.5)
	wheel(34, B + 34.5, 10, 8, 0.55, 0)
	arcSlab(s3, base3 + 48, base3 + 53, B + 35.5)
	arcSlab(s3, base3 + 53, base3 + 58, B + 37)
	wheel(71, B + 38, 9, 6, -0.75, 0.1)
	arcSlab(s3, base3 + 84, base3 + 89, B + 39)
	arcSlab(s3, base3 + 89, base3 + 94, B + 40.5)
	wheel(106, B + 41.5, 8, 4, 1.0, 0.2)
	arcSlab(s3, base3 + 118, base3 + 124, B + 42.5)
	for _, c in { { 17, 33.5 }, { 34, 34.5 }, { 55, 37 }, { 91, 40.5 } } do
		ctx.Coin(arc(base3 + c[1], B + c[2] + 2.5))
	end
	-- K2 : grande roue de chargement dressée derrière la spirale ; la clé flotte au-dessus du sommet
	local ks = base3 + 53
	Kit.Spinner(ctx, s3, arc(ks, B + 37, 18), arcDir(ks), 9, 6, 0.6, 0, 3, S, arcDir(ks))
	ctx.UsbKey(arc(ks, B + 37 + 9 + 4.2, 18), 2)
	ctx.Lamp(arc(base3 + 70, B + 56, 6), P:Lerp(C.White, 0.4), 1.3, 70)
	Kit.Checkpoint(ctx, 23, s3, cp23, Kit.Toward(arcDir(236), cp23, Vector3.new(12, B + 63, -120)), arcDir(236))
	support(cp23 - Vector3.new(0, 2, 0), 4)

	------------------------------------------------------------------------------------
	-- Étape 4 (24) : caloduc brûlant (chaleur) puis grille de broches (lasers)
	------------------------------------------------------------------------------------

	local s4 = ctx.Stage(24)
	arcSlab(s4, 244, 252, B + 44)
	-- Caloduc : de la spirale au coin nord-ouest du socket, en marches de 1,75
	local p0 = arc(252, B + 44)
	local p1 = Vector3.new(12, B + 58.25, SZ1 + 2)
	local run = Vector3.new(p1.X - p0.X, 0, p1.Z - p0.Z)
	local dir = run.Unit
	local right = dir:Cross(UP)
	local n = 8
	local step = run.Magnitude / n
	for i = 1, n do
		local center = p0 + dir * (step * (i - 0.5)) + Vector3.new(0, 1.75 * (i - 1) + 1.75, 0)
		local deck = Kit.Slab(ctx, s4, center, dir, step + 0.3, 10, "HeatPipe")
		deck.Color = COPPER:Lerp(style.Floor, 0.35)
		-- Bouches des deux couloirs, en alternance ; la vague avance le long du caloduc
		if i >= 2 and i <= 7 then
			for _, lane in { -1, 1 } do
				local phase = Common.Frac((if lane > 0 then 0 else 0.5) - i * 0.1)
				Kit.Heat(ctx, s4, center + right * lane * 2.5, dir, 4.6, 5, 9, 3, 0.4, phase)
			end
		end
		Rod(decor, "PipeStrut", CFrame.new(center - Vector3.new(0, 5, 0)) * VERTICAL, 6, 1.6, COPPER)
	end
	-- Grille de broches : côté ouest de l'anneau du socket (on descend vers le sud)
	local function rim(
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		look: Vector3,
		parent: Instance,
		name: string
	): Part
		local alongX = math.abs(look.X) > 0.5
		local length = if alongX then x1 - x0 else z1 - z0
		local width = if alongX then z1 - z0 else x1 - x0
		local slab = Kit.Slab(ctx, parent, Vector3.new((x0 + x1) / 2, top, (z0 + z1) / 2), look, length, width, name, 3)
		slab.Color = style.Floor:Lerp(C.PcbDark, 0.35)
		-- Rangées de broches dorées (sillons lumineux dans le sens de la course)
		for k = 1, math.floor(width / 2.6) do
			local o = -width / 2 + k * width / (math.floor(width / 2.6) + 1)
			local r2 = look:Cross(UP)
			Build.Neon({
				Name = "PinRow",
				Size = Vector3.new(0.35, 0.12, length - 1),
				CFrame = facing(Vector3.new((x0 + x1) / 2, top + 0.06, (z0 + z1) / 2) + r2 * o, look),
				Color = PIN,
				Transparency = 0.35,
				Parent = slab,
			})
		end
		return slab
	end
	rim(SX0, SX0 + RIM, -76, SZ1, B + 60, SOUTH, s4, "PinGrid")
	rim(SX0, SX0 + RIM, SZ0 + RIM, -76, B + 61.5, SOUTH, s4, "PinGrid")
	-- Lasers de la grille : faisceaux au ras du sol (à sauter), rideau qui balaie la largeur
	local mx = SX0 + RIM / 2
	Kit.Laser(ctx, s4, Vector3.new(mx, B + 61.4, -58), EAST, RIM, Vector3.new(0, 0, -14), 3.6, 0)
	Kit.Laser(ctx, s4, Vector3.new(SX0 + 1.5, B + 64, -84), NORTH, 8, Vector3.new(RIM - 3, 0, 0), 3.2, 0.25, true)
	Kit.Laser(ctx, s4, Vector3.new(mx, B + 62.9, -92), EAST, RIM, Vector3.new(0, 0, -14), 3.4, 0.5)
	Kit.Laser(ctx, s4, Vector3.new(mx, B + 62.9, -92), EAST, RIM, Vector3.new(0, 0, -14), 3.4, 0)
	for _, p in
		{
			arc(248, B + 46.5),
			p0 + dir * 30 + Vector3.new(0, 11, 0),
			Vector3.new(mx, B + 63, -66),
			Vector3.new(mx + 4, B + 64.5, -100),
		}
	do
		ctx.Coin(p)
	end
	local cp24 = Vector3.new(mx, B + 63, SZ0 + RIM / 2)
	rim(SX0, SX0 + RIM, SZ0, SZ0 + RIM, B + 63, EAST, s4, "PinCorner")
	ctx.Checkpoint(24, facing(cp24 + Vector3.new(0, 0.4, 0), EAST))
	ctx.Lamp(Vector3.new(40, B + 84, -84), P:Lerp(C.White, 0.45), 1.4, 80)

	------------------------------------------------------------------------------------
	-- Étape 5 (25) : le socket du mineur (tout combiné) jusqu'à la porte
	------------------------------------------------------------------------------------

	local s5 = ctx.Stage(25)
	local zS = SZ0 + RIM / 2 -- axe de l'anneau sud
	rim(SX0 + RIM, 35, SZ0, SZ0 + RIM, B + 63, EAST, s5, "PinGrid")
	-- Pioches jumelles de Minor, en travers de l'anneau
	Kit.Pickaxe(ctx, s5, Vector3.new(24, B + 64.2, zS), NORTH, 12, 50, 2.8, 0, 11)
	Kit.Pickaxe(ctx, s5, Vector3.new(31, B + 64.2, zS), NORTH, 12, 50, 2.8, 0.5, 11)
	-- Broches arrachées : on traverse la brèche sur une plateforme en latence
	Kit.LagMover(ctx, s5, Vector3.new(42.5, B + 64, zS), EAST, 11, 10, Vector3.new(0, 0, 11), 4.4, 3, 0.2, LAG, P)
	rim(50, 60, SZ0, SZ0 + RIM, B + 65, EAST, s5, "PinGrid")
	Kit.Heat(ctx, s5, Vector3.new(55, B + 65, zS - 4), EAST, 8, 9, 9, 3, 0.4, 0.15)
	Kit.Heat(ctx, s5, Vector3.new(55, B + 65, zS + 4), EAST, 8, 9, 9, 3, 0.4, 0.65)
	-- Ascenseur (Mover) au coin sud-est, puis dernière roue de chargement jusqu'au seuil
	Kit.Mover(ctx, s5, Vector3.new(66, B + 65.5, -123), NORTH, 8, 8, Vector3.new(0, 12, 0), 6.5, 0, C.MetalLight, SAFE)
	Kit.Spinner(ctx, s5, Vector3.new(68, B + 78, -106.5), SOUTH, 6.5, 6, 0.7, 0, 5, P)
	local threshold = Kit.Slab(ctx, s5, Vector3.new(72, B + 80, -88), EAST, 16, 16, "Threshold")
	threshold.Color = style.Floor:Lerp(C.White, 0.1)
	support(Vector3.new(72, B + 78, -88), 4)
	support(Vector3.new(66, B + 60, -123), 3)
	for _, p in
		{
			Vector3.new(20, B + 66, zS),
			Vector3.new(42.5, B + 67, zS),
			Vector3.new(66, B + 72, -123),
			Vector3.new(68, B + 82, -106.5),
		}
	do
		ctx.Coin(p)
	end
	-- K3 : broches isolées au-dessus de la flaque de glitch, balayées par un rideau laser
	for i, z in { -105, -98, -91 } do
		local pin = Kit.Slab(ctx, s5, Vector3.new(55, B + 64 + i * 0.8, z), NORTH, 3, 3, "LonePin", 1.2)
		pin.Color = PIN
		Rod(decor, "PinLeg", CFrame.new(55, B + 56 + i * 0.4, z) * VERTICAL, 14, 1, PIN)
	end
	Kit.Laser(ctx, s5, Vector3.new(46, B + 68, -98), NORTH, 9, Vector3.new(18, 0, 0), 3.6, 0.3, true)
	ctx.UsbKey(Vector3.new(55, B + 69, -91), 3)

	-- Minor, le crypto-mineur, garde la porte depuis le bord de la puce arrachée
	local minorCf = facing(Vector3.new(58, B + 80, -86), Vector3.new(1, 0, -0.4))
	Kit.Solid(decor, "MinorPerch", Vector3.new(6, 2, 6), minorCf * CFrame.new(0, -1, 0), C.MetalDark)
	Kit.Place("Minor", minorCf, decor, 7, function()
		local m = Build.Model("Minor", decor)
		Box(m, "Body", Vector3.new(3.4, 3, 2.4), minorCf * CFrame.new(0, 2.6, 0), C.MetalLight, METAL)
		local head = Box(m, "Head", Vector3.new(3, 2.4, 2.6), minorCf * CFrame.new(0, 5.3, 0), C.Aluminum, METAL)
		Props.Label(head, "◉ ◉", LETHAL, Enum.NormalId.Front, Enum.Font.GothamBlack)
		Box(m, "Helmet", Vector3.new(3.4, 0.8, 3), minorCf * CFrame.new(0, 6.8, 0), P)
		Build.Neon({
			Name = "HeadLamp",
			Size = Vector3.new(1, 0.6, 0.4),
			CFrame = minorCf * CFrame.new(0, 6.8, -1.6),
			Color = C.White,
			Parent = m,
		})
		for _, x in { -0.9, 0.9 } do
			Box(m, "Leg", Vector3.new(1, 1.2, 1.2), minorCf * CFrame.new(x, 0.6, 0), C.Black)
		end
		Rod(
			m,
			"PickHandle",
			minorCf * CFrame.new(2.4, 4, -0.6) * CFrame.Angles(0, 0, math.rad(70)),
			5,
			0.5,
			Kit.WOOD,
			Enum.Material.Wood
		)
		Box(m, "PickHead", Vector3.new(0.6, 0.6, 3.6), minorCf * CFrame.new(3.3, 6.2, -0.6), LETHAL, NEON)
		return m
	end)

	------------------------------------------------------------------------------------
	-- Scénario : version infectée (le mineur tourne à fond) / nettoyée (CPU au repos)
	------------------------------------------------------------------------------------

	local infected = Build.Model("CoreInfected", decor)
	ctx.Infected(infected)
	for i, spot in { Vector3.new(-16, B + 78, -12), Vector3.new(40, B + 82, -60) } do
		local ad = Box(
			infected,
			"MinerAd",
			Vector3.new(20, 9, 0.4),
			facing(spot, if i == 1 then SOUTH else Vector3.new(-1, 0, 1)),
			C.Bg
		)
		Props.Sign(ad, if i == 1 then "CPU 100 %" else "MINING... 999 %", "Minor.exe (ne pas fermer)", LETHAL, C.White)
		ad.Transparency = 0.1
	end
	for k = 0, 3 do
		Build.Neon({
			Name = "AlertStrip",
			Size = Vector3.new(46, 0.8, 0.8),
			CFrame = coolerCf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, COOLER_H - 8, -23),
			Color = LETHAL,
			Transparency = 0.2,
			Parent = infected,
		})
	end
	for _, spot in
		{ Vector3.new(SX0 + 12, socketTop + 0.1, -50), Vector3.new(70, socketTop + 0.1, -62), arc(160, B + 36.1, -6) }
	do
		Build.Neon({
			Name = "GlitchPuddle",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 5, 5),
			CFrame = CFrame.new(spot) * FLAT,
			Color = GLITCH,
			Transparency = 0.45,
			Parent = infected,
		})
	end

	local cleaned = Build.Model("CoreCleaned", decor)
	ctx.Cleaned(cleaned)
	local calm = Box(cleaned, "CpuUsage", Vector3.new(20, 9, 0.4), facing(Vector3.new(-16, B + 78, -12), SOUTH), C.Bg)
	Props.Sign(calm, "CPU 12 %", "Mineur supprimé", SAFE, C.White)
	for k = 0, 3 do
		local strip = Build.Neon({
			Name = "RgbStrip",
			Size = Vector3.new(46, 0.8, 0.8),
			CFrame = coolerCf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, COOLER_H - 8, -23),
			Color = P,
			Transparency = 0.15,
			Parent = cleaned,
		})
		strip:AddTag("RgbStrip")
	end
	ctx.Lamp(Vector3.new(CORE.X, B + 86, CORE.Z), P:Lerp(C.White, 0.3), 1.6, 90, cleaned)

	ctx.TerminalRoom()
	assert(math.abs(ctx.Terminal.Floor - (B + 80)) < 1e-6, "monde 5 : le seuil doit être au niveau de la porte")
end
