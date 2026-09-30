--!strict
--[[
	Monde 6 : Render Canyon (GPU) — « Écran figé, artefacts »

	Freezy fige l'image : la carte graphique géante (debout, ventilateurs vers l'est) forme la
	paroi d'un canyon ; on le remonte puis on court sur une piste de pixels.

	Parcours (entrée au coin (88, 510, -88), porte de la salle du terminal en (88, 580, 80)) :
	1. Le canyon — corniche au pied de la carte, sous les PALES géantes du 1er ventilateur (SpinBar).
	2. Les ponts de chargement — trois PONTS qui se remplissent comme une barre de progression
	   (LoadBridge) devant le 2ᵉ ventilateur ; ils bloquent parfois (« Ne répond pas »).
	3. La piste de pixels — des PIXELS MORTS s'éteignent en vagues (DeadPixels) : vague qui suit
	   le joueur, puis balayage des couloirs, puis vagues en diagonale.
	4. Le banc de rendu — LASERS de rendu et DÉCHARGES des connecteurs d'alimentation (Zapper), puis
	   on grimpe sur le dessus de la carte.
	5. Le dessus de la carte — tout combiné : ventilateur-verrou, détour par pixels morts, pont de
	   chargement, décharges, puis l'escalier de pixels balayé par un laser jusqu'à la porte.

	FREEZE (incident vedette) : tous les pièges se figent. Sur le dessus de la carte, un ventilateur
	qui tourne beaucoup trop vite barre le chemin direct : pendant un FREEZE ses pales s'arrêtent et
	on passe tout droit (raccourci, et la clé K3 est juste derrière) au lieu de faire le détour.

	Clés USB : K1 dans les pales du 2ᵉ ventilateur, K2 au bout d'une jetée de pixels morts à
	contre-vague, K3 derrière le ventilateur-verrou (raccourci du FREEZE).
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

local EAST, WEST, NORTH, SOUTH = Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis
local ICE = Color3.fromRGB(190, 232, 255)

-- Carte graphique : x ∈ [30, 46], z ∈ [-104, 104], dessus à Base + CARD_TOP ; ventilateurs sur la
-- face est (x = 46), moyeux à Base + FAN_Y.
local CARD_X0, CARD_X1, CARD_Z = 30, 46, 104
local CARD_TOP = 54
local FAN_Y = 28
local FAN_Z = { -60, 0, 60 }
local FAN_R = 17.5
local BLADE_X = 51.5 -- plan des pales (devant la carte)

return function(ctx: Ctx)
	local B = ctx.Base
	local style = ctx.Style
	local P, S = style.Primary, style.Secondary
	local decor = ctx.Decor
	local cardX = (CARD_X0 + CARD_X1) / 2

	ctx.Void()
	ctx.Entrance()

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

	-- Pixel mort : dalle sûre qui s'éteint (noire, traversable) quand la vague passe.
	local function pixel(
		parent: Instance,
		top: Vector3,
		size: Vector3,
		color: Color3,
		direction: Vector3,
		speed: number,
		period: number,
		duty: number
	): Part
		local tile = Kit.Trap(
			ctx,
			parent,
			"DeadPixels",
			"Pixel",
			size,
			CFrame.new(top - Vector3.new(0, size.Y / 2, 0)),
			color,
			SMOOTH,
			{ Direction = direction, Speed = speed, Period = period, Duty = duty },
			true
		)
		return tile
	end

	-- Pont de chargement : cadre (racine) que le client remplit segment par segment.
	-- La racine reste solide côté serveur (le pont plein) ; le client la rend traversable.
	local function loadBridge(
		parent: Instance,
		top: Vector3,
		look: Vector3,
		length: number,
		period: number,
		segments: number,
		phase: number,
		offset: Vector3?
	): Part
		local cf = facing(top - Vector3.new(0, 0.5, 0), look)
		local attributes: { [string]: any } = {
			Period = period,
			Segments = segments,
			Phase = phase,
			Direction = look,
		}
		if offset then
			attributes.Offset = offset
		end
		local bridge = Kit.Trap(
			ctx,
			parent,
			"LoadBridge",
			"LoadBridge",
			Vector3.new(8, 1, length),
			cf,
			C.MetalDark,
			SMOOTH,
			attributes,
			true
		)
		bridge.Transparency = 0.35
		for _, side in { -1, 1 } do
			local rail = Common.Attach(
				bridge,
				"ProgressRail",
				Vector3.new(0.4, 0.5, length),
				cf * CFrame.new(side * 4.2, 0.1, 0),
				P,
				NEON
			)
			rail.Transparency = 0.2
		end
		return bridge
	end

	------------------------------------------------------------------------------------
	-- Décor : la carte graphique géante (paroi du canyon), slot PCIe, câbles d'alimentation
	------------------------------------------------------------------------------------

	local cardCf = CFrame.new(cardX, B, 0)
	Kit.Place("PcieSlot", cardCf * CFrame.Angles(0, math.pi / 2, 0), decor, 5, function()
		local m = Build.Model("PcieSlot", decor)
		Box(m, "Slot", Vector3.new(10, 5, 2 * CARD_Z - 30), cardCf * CFrame.new(0, 2.5, -10), C.Black)
		Box(m, "SlotLatch", Vector3.new(10, 6, 6), cardCf * CFrame.new(0, 3, CARD_Z - 16), SAFE:Lerp(C.White, 0.4))
		return m
	end)
	Kit.Place(
		"GpuCard",
		cardCf * CFrame.new(0, 4, 0) * CFrame.Angles(0, math.pi / 2, 0),
		decor,
		CARD_TOP - 4,
		function()
			local m = Build.Model("GpuCard", decor)
			local h = CARD_TOP - 6
			local body = cardCf * CFrame.new(0, 6 + h / 2, 0)
			Box(m, "Shroud", Vector3.new(CARD_X1 - CARD_X0, h, 2 * CARD_Z), body, C.MetalDark, METAL)
			Box(m, "Backplate", Vector3.new(1, h - 2, 2 * CARD_Z - 2), body * CFrame.new(-8.5, 0, 0), C.Black, METAL)
			Box(
				m,
				"Fingers",
				Vector3.new(4, 3, 2 * CARD_Z - 40),
				cardCf * CFrame.new(0, 4.5, -10),
				C.Gold,
				Enum.Material.Foil
			)
			-- Liserés RGB (vert / rose) le long de la face des ventilateurs
			for i, y in { 7, h + 5 } do
				local strip = Build.Neon({
					Name = "RgbStrip",
					Size = Vector3.new(0.6, 1, 2 * CARD_Z),
					CFrame = cardCf * CFrame.new(8.2, y, 0),
					Color = if i == 1 then P else S,
					Transparency = 0.15,
					Parent = m,
				})
				strip:AddTag("RgbStrip")
			end
			-- Ouïes des ventilateurs (anneaux) et moyeux ; les pales rouges sont les pièges
			for _, z in FAN_Z do
				local ringCf = CFrame.fromMatrix(Vector3.new(CARD_X1 + 0.3, B + FAN_Y, z), EAST, UP)
				Props.Ring(m, "FanShroud", ringCf, FAN_R + 1, 1.6, 0.8, 14, C.Black, METAL)
				Props.Ring(m, "FanGlow", ringCf * CFrame.new(0.5, 0, 0), FAN_R + 2.2, 0.5, 0.3, 14, P, NEON)
				Rod(m, "FanHub", ringCf * CFrame.new(3, 0, 0), 6, 7, C.Black)
			end
			-- Équerre d'E/S (bout sud) : les sorties d'image d'où partent les lasers de rendu
			local bracket = Box(
				m,
				"IoBracket",
				Vector3.new(CARD_X1 - CARD_X0 + 2, h + 8, 1.2),
				cardCf * CFrame.new(0, 2 + h / 2, -CARD_Z - 0.6),
				C.Aluminum,
				METAL
			)
			for k = 0, 3 do
				Box(
					m,
					"DisplayPort",
					Vector3.new(5, 3, 0.6),
					bracket.CFrame * CFrame.new(0, -14 + k * 8, -0.9),
					C.Black
				)
			end
			local logo = Box(m, "Logo", Vector3.new(0.4, 8, 60), cardCf * CFrame.new(-8.8, 30, 0), C.Bg)
			Props.Label(logo, "RENDER", S, Enum.NormalId.Left, Enum.Font.GothamBlack)
			return m
		end
	)
	-- Câbles d'alimentation gainés branchés sur le bord ouest de la carte (vers l'alimentation)
	for i, z in { -70, -48 } do
		local plug = Vector3.new(CARD_X0 + 2, B + CARD_TOP + 1, z)
		Kit.Place("CableSleeved8", facing(plug, WEST), decor, 30, function()
			local m = Build.Model("CableSleeved8", decor)
			Box(m, "Plug", Vector3.new(4, 3, 8), CFrame.new(plug + Vector3.new(0, 0.5, 0)), C.Black)
			for k = -1, 1 do
				Props.ArcCable(
					m,
					plug + Vector3.new(-1, 1.5, k * 2.2),
					plug + Vector3.new(-18, 22, k * 2.2 + i * 6),
					plug + Vector3.new(-50, 36, k * 3 + i * 14),
					0.9,
					if k == 0 then S else C.Black,
					5
				)
			end
			return m
		end)
	end

	------------------------------------------------------------------------------------
	-- Étape 1 (26) : le canyon, sous les pales du 1er ventilateur
	------------------------------------------------------------------------------------

	local s1 = ctx.Stage(26)
	Kit.Slab(ctx, s1, Vector3.new(84, B + 10, -72), WEST, 16, 9, "CanyonStep")
	Kit.Slab(ctx, s1, Vector3.new(66, B + 11.5, -72), WEST, 16, 9, "CanyonStep")
	local ledge = Kit.Slab(ctx, s1, Vector3.new(BLADE_X, B + 13, -57), NORTH, 42, 9, "CardLedge")
	ledge.Color = style.Floor:Lerp(C.PcbDark, 0.3)
	-- Pales du ventilateur 1 : 4 branches, le bas de la pale avance vers le nord (comme le joueur)
	local function fanBlades(z: number, arms: number, speed: number, phase: number)
		return Kit.Blades(
			ctx,
			s1,
			CFrame.fromMatrix(Vector3.new(BLADE_X, B + FAN_Y, z), EAST, UP),
			FAN_R,
			3.2,
			9.6,
			arms,
			speed,
			phase
		)
	end
	fanBlades(FAN_Z[1], 4, -0.5, 0)
	for _, p in
		{ Vector3.new(84, B + 12.5, -72), Vector3.new(BLADE_X, B + 15.5, -70), Vector3.new(BLADE_X, B + 15.5, -50) }
	do
		ctx.Coin(p)
	end
	support(Vector3.new(66, B + 9.5, -72))
	local cp26 = Vector3.new(60, B + 15, -26)
	local cp27 = Vector3.new(98, B + 21, 60)
	Kit.Checkpoint(ctx, 26, s1, cp26, Kit.Toward(NORTH, cp26, cp27), NORTH)
	support(cp26 - Vector3.new(0, 2, 0), 4)
	ctx.Lamp(Vector3.new(70, B + 40, -60), P:Lerp(C.White, 0.5), 1.3, 70)

	------------------------------------------------------------------------------------
	-- Étape 2 (27) : ponts de chargement devant le 2ᵉ ventilateur
	------------------------------------------------------------------------------------

	local s2 = ctx.Stage(27)
	-- Les pales du ventilateur 2 tournent aussi (décor dangereux, hors du chemin des ponts)
	Kit.Blades(
		ctx,
		s2,
		CFrame.fromMatrix(Vector3.new(BLADE_X, B + FAN_Y, FAN_Z[2]), EAST, UP),
		FAN_R,
		3.2,
		9.6,
		4,
		0.55,
		0.1
	)
	loadBridge(s2, Vector3.new(62, B + 15.5, 0), NORTH, 36, 8, 9, 0)
	Kit.Slab(ctx, s2, Vector3.new(62, B + 17, 24), NORTH, 8, 8, "LoadPad")
	loadBridge(s2, Vector3.new(80, B + 17.5, 24), EAST, 28, 7, 7, 0.35)
	Kit.Slab(ctx, s2, Vector3.new(98, B + 19, 24), EAST, 8, 8, "LoadPad")
	-- Le dernier pont glisse de côté pendant qu'il charge
	loadBridge(s2, Vector3.new(98, B + 19.5, 40), NORTH, 24, 7.5, 8, 0.7, Vector3.new(6, 0, 0))
	for _, p in
		{
			Vector3.new(62, B + 18, -8),
			Vector3.new(62, B + 19.5, 24),
			Vector3.new(84, B + 20, 24),
			Vector3.new(98, B + 22, 44),
		}
	do
		ctx.Coin(p)
	end
	support(Vector3.new(62, B + 15, 24))
	support(Vector3.new(98, B + 17, 24))
	-- K1 : deux marches qui montent dans le balayage des pales du ventilateur 2
	Kit.Slab(ctx, s2, Vector3.new(58, B + 19, -15), NORTH, 4, 4, "FanStep")
	Kit.Slab(ctx, s2, Vector3.new(54, B + 23, -9), NORTH, 4, 4, "FanStep")
	ctx.UsbKey(Vector3.new(54, B + 26, -9), 1)
	Kit.Checkpoint(ctx, 27, s2, cp27, Kit.Toward(EAST, cp27, Vector3.new(119.5, B + 41, -64)), NORTH)
	support(cp27 - Vector3.new(0, 2, 0), 4)

	------------------------------------------------------------------------------------
	-- Étape 3 (28) : la piste de pixels (3 couloirs, vers le sud)
	------------------------------------------------------------------------------------

	local s3 = ctx.Stage(28)
	local LANES = { 114.5, 119.5, 124.5 }
	local trackX = 119.5
	local island = Kit.Slab(ctx, s3, Vector3.new(118, B + 22.5, 60), SOUTH, 8, 20, "StuckPixels")
	island.Color = P:Lerp(style.Floor, 0.55)
	local z = 53.5
	local y = B + 23
	local function row(color: Color3, direction: Vector3, speed: number, period: number, duty: number)
		for i, x in LANES do
			local c = if (i + math.floor(z / 5)) % 2 == 0 then color else color:Lerp(C.White, 0.12)
			pixel(s3, Vector3.new(x, y, z), Vector3.new(4.8, 1, 4.8), c, direction, speed, period, duty)
		end
	end
	local function islandAt(rise: number): number
		-- Îlot de pixels coincés (statique), 4 studs de long, `rise` plus haut que la dernière rangée
		y += rise
		z -= 4.5
		local slab = Kit.Slab(ctx, s3, Vector3.new(trackX, y, z), SOUTH, 4, 15, "StuckPixels")
		slab.Color = P:Lerp(style.Floor, 0.55)
		support(Vector3.new(trackX, y - 2, z), 3)
		z -= 4.5
		return y
	end
	-- A : la vague suit le joueur (on la suit sans la dépasser)
	for _ = 1, 6 do
		row(P, SOUTH, 10, 3, 0.35)
		z -= 5
		y += 0.6
	end
	z += 2.5
	islandAt(1.4)
	ctx.Coin(Vector3.new(trackX, y + 2.5, z + 4.5))
	-- B : balayage d'un couloir à l'autre (un seul couloir éteint à la fois)
	y += 1
	for _ = 1, 6 do
		row(S, EAST, 4, 3.75, 0.3)
		z -= 5
		y += 0.6
	end
	z += 2.5
	islandAt(1.4)
	ctx.Coin(Vector3.new(trackX, y + 2.5, z + 4.5))
	-- C : vagues en diagonale
	y += 1
	for _ = 1, 6 do
		row(P:Lerp(S, 0.5), Vector3.new(1, 0, -1).Unit, 7, 3, 0.35)
		z -= 5
		y += 0.6
	end
	ctx.Coin(Vector3.new(trackX, B + 28.5, 30))
	ctx.Coin(Vector3.new(trackX, y + 2, z + 12))
	local cp28 = Vector3.new(trackX, y + 1, z - 5.5)
	-- K2 : jetée de pixels vers l'ouest, la vague arrive en face (à contre-vague)
	for i = 1, 3 do
		pixel(s3, Vector3.new(112 - i * 5, B + 30 + i * 0.5, -6), Vector3.new(4, 1, 4), S, EAST, 6, 3, 0.4)
	end
	local keyPad = Kit.Slab(ctx, s3, Vector3.new(92, B + 32, -6), WEST, 4, 4, "StuckPixel")
	keyPad.Color = S
	ctx.UsbKey(Vector3.new(92, B + 34.5, -6), 2)
	ctx.Lamp(Vector3.new(trackX, B + 50, 0), S:Lerp(C.White, 0.4), 1.4, 80)
	local cp29 = Vector3.new(cardX, B + CARD_TOP + 1.5, -12)
	Kit.Checkpoint(ctx, 28, s3, cp28, Kit.Toward(WEST, cp28, cp29), SOUTH)
	support(cp28 - Vector3.new(0, 2, 0), 4)

	------------------------------------------------------------------------------------
	-- Étape 4 (29) : banc de rendu (lasers + décharges), puis le dessus de la carte
	------------------------------------------------------------------------------------

	local s4 = ctx.Stage(29)
	local zc = cp28.Z
	local x = cp28.X - 8
	y = cp28.Y
	local slabs: { Vector3 } = {}
	for i = 1, 4 do
		y += 2
		local center = Vector3.new(x - 2.5 - 5, y, zc)
		Kit.Slab(ctx, s4, center, WEST, 10, 9, "RenderBench")
		support(center - Vector3.new(0, 2, 0))
		slabs[i] = center
		x -= 12.5
	end
	-- Laser au ras du sol qui balaie le banc (à sauter), décharge, rideau, décharges alternées
	Kit.Laser(ctx, s4, slabs[1] + Vector3.new(4, 1.4, 0), NORTH, 9, Vector3.new(-8, 0, 0), 3.2, 0)
	Kit.Zapper(ctx, s4, slabs[2], WEST, 9, 8, 3, 0.5, 0.2)
	Kit.Laser(ctx, s4, slabs[3] + Vector3.new(0, 4, -4), WEST, 8, Vector3.new(0, 0, 8), 2.8, 0.1, true)
	Kit.Zapper(ctx, s4, slabs[4] + Vector3.new(2.5, 0, 0), WEST, 9, 8, 2.8, 0.5, 0.6)
	Kit.Zapper(ctx, s4, slabs[4] - Vector3.new(2.5, 0, 0), WEST, 9, 8, 2.8, 0.5, 0.1)
	-- Virage au sud puis montée sur la carte, au sud du ventilateur 1
	y += 2
	Kit.Slab(ctx, s4, Vector3.new(62, y, zc - 12.5), SOUTH, 10, 8, "RenderBench")
	y += 1.5
	Kit.Slab(ctx, s4, Vector3.new(52, y, zc - 22), WEST, 9, 10, "BracketStep")
	-- Dessus de la carte : on court vers le nord entre les connecteurs qui crachent des arcs
	local topY = B + CARD_TOP
	local deck = Kit.Slab(ctx, s4, Vector3.new(cardX, topY, -62), NORTH, 84, CARD_X1 - CARD_X0, "CardTop")
	deck.Color = C.MetalDark:Lerp(P, 0.12)
	Kit.Zapper(ctx, s4, Vector3.new(cardX, topY, -70), NORTH, CARD_X1 - CARD_X0 - 1, 7, 3.2, 0.5, 0.3)
	Kit.Zapper(ctx, s4, Vector3.new(cardX, topY, -48), NORTH, CARD_X1 - CARD_X0 - 1, 7, 3.2, 0.5, 0.8)
	Kit.Laser(ctx, s4, Vector3.new(cardX, topY + 1.4, -38), EAST, CARD_X1 - CARD_X0, Vector3.new(0, 0, 14), 3, 0.5)
	for _, p in
		{
			slabs[1] + Vector3.new(0, 2.5, 3),
			slabs[3] + Vector3.new(0, 2.5, 3),
			Vector3.new(cardX, topY + 2.5, -80),
			Vector3.new(cardX + 4, topY + 2.5, -30),
		}
	do
		ctx.Coin(p)
	end
	Kit.Checkpoint(ctx, 29, s4, cp29, Kit.Toward(NORTH, cp29, Vector3.new(88, B + 80, 88)), NORTH)
	ctx.Lamp(Vector3.new(70, B + 70, -60), S:Lerp(C.White, 0.5), 1.2, 70)

	------------------------------------------------------------------------------------
	-- Étape 5 (30) : le dessus de la carte, tout combiné, jusqu'à la porte
	------------------------------------------------------------------------------------

	local s5 = ctx.Stage(30)
	local walk = Kit.Slab(ctx, s5, Vector3.new(cardX, topY + 2, 15), NORTH, 38, CARD_X1 - CARD_X0, "CardTop")
	walk.Color = C.MetalDark:Lerp(P, 0.12)
	-- Ventilateur-verrou : tourne bien trop vite (fenêtres minuscules). En FREEZE il s'arrête :
	-- raccourci tout droit, avec la clé K3 juste derrière.
	local lockY = topY + 2 + 8
	Kit.Place("Fan140", CFrame.fromMatrix(Vector3.new(cardX, lockY, 22.8), EAST, SOUTH), decor, 20, function()
		local m = Build.Model("LockFan", decor)
		local ringCf = CFrame.fromMatrix(Vector3.new(cardX, lockY, 23.2), NORTH, UP)
		Props.Ring(m, "LockFrame", ringCf, 11.2, 1.4, 1.6, 14, C.Black, METAL)
		Props.Ring(m, "LockGlow", ringCf * CFrame.new(-0.9, 0, 0), 11.8, 0.4, 0.3, 14, ICE, NEON)
		Rod(m, "LockHub", ringCf * CFrame.new(0.6, 0, 0), 2, 3, C.Black)
		return m
	end)
	Kit.Blades(ctx, s5, CFrame.fromMatrix(Vector3.new(cardX, lockY, 22), NORTH, UP), 10.5, 1.8, 1.4, 6, 3.4, 0)
	local sign =
		Box(decor, "FreezeHint", Vector3.new(12, 4, 0.3), facing(Vector3.new(cardX, lockY + 13, 21), SOUTH), C.Bg)
	Props.Sign(sign, "❄ FREEZE = PASSAGE", "Attends que Freezy fige tout", ICE, C.White)
	ctx.UsbKey(Vector3.new(cardX, topY + 5.5, 22), 3)
	-- Détour (sans FREEZE) : pixels morts vers l'est, pont de chargement, passerelle à décharges
	for i = 1, 4 do
		for _, dz in { -2, 2 } do
			pixel(s5, Vector3.new(CARD_X1 + i * 4, topY + 2.5, 8 + dz), Vector3.new(3.8, 1, 3.8), P, EAST, 8, 3, 0.35)
		end
	end
	Kit.Slab(ctx, s5, Vector3.new(68, topY + 3.5, 8), NORTH, 8, 8, "DetourPad")
	loadBridge(s5, Vector3.new(68, topY + 4, 26), NORTH, 28, 6, 7, 0.2)
	Kit.Slab(ctx, s5, Vector3.new(68, topY + 5.5, 44), NORTH, 8, 8, "DetourPad")
	Kit.Slab(ctx, s5, Vector3.new(55, topY + 6.5, 44), WEST, 18, 8, "ZapWalk")
	Kit.Zapper(ctx, s5, Vector3.new(58, topY + 6.5, 44), WEST, 8, 7, 2.6, 0.5, 0)
	Kit.Zapper(ctx, s5, Vector3.new(51, topY + 6.5, 44), WEST, 8, 7, 2.6, 0.5, 0.5)
	for _, p in { Vector3.new(56, topY + 5, 8), Vector3.new(68, topY + 7, 26) } do
		ctx.Coin(p)
	end
	support(Vector3.new(68, topY + 1.5, 8), 3)
	support(Vector3.new(68, topY + 3.5, 44), 3)
	-- Dessus de la carte, au nord du ventilateur-verrou
	local north = Kit.Slab(ctx, s5, Vector3.new(cardX, topY + 5, 56), NORTH, 40, CARD_X1 - CARD_X0, "CardTop")
	north.Color = C.MetalDark:Lerp(P, 0.12)
	-- Escalier de pixels vers la porte, balayé par un laser qui le descend en diagonale
	local door = ctx.Terminal.Door.Position
	local stepY = topY + 5
	for k = 0, 9 do
		stepY += 2
		pixel(
			s5,
			Vector3.new(48 + 3 * k + 1.5, stepY, 70),
			Vector3.new(3, 1, 8),
			if k % 2 == 0 then P else S,
			EAST,
			9,
			3.2,
			0.3
		)
	end
	Kit.Laser(ctx, s5, Vector3.new(49.5, topY + 7.4, 70), NORTH, 8, Vector3.new(27, 18, 0), 4.2, 0)
	ctx.Coin(Vector3.new(63, topY + 19.5, 70))
	local threshold = Kit.Slab(ctx, s5, Vector3.new(door.X, door.Y, 71), NORTH, 18, 16, "Threshold")
	threshold.Color = style.Floor:Lerp(C.White, 0.1)
	support(Vector3.new(door.X, door.Y - 2, 71), 4)
	ctx.Lamp(Vector3.new(60, B + 78, 40), P:Lerp(C.White, 0.5), 1.2, 70)

	-- Freezy, le glaçon au sablier, garde la porte
	local freezyCf = facing(Vector3.new(101, door.Y, 70), WEST)
	Kit.Solid(decor, "IcePedestal", Vector3.new(6, 2, 6), freezyCf * CFrame.new(0, -1, 0), ICE, Enum.Material.Ice)
	Kit.Place("Freezy", freezyCf, decor, 6, function()
		local m = Build.Model("Freezy", decor)
		local body =
			Box(m, "IceCube", Vector3.new(4.4, 4.4, 4.4), freezyCf * CFrame.new(0, 2.4, 0), ICE, Enum.Material.Ice)
		body.Transparency = 0.2
		Props.Label(body, "• ⏳ •", C.Bg, Enum.NormalId.Front, Enum.Font.GothamBlack)
		Box(m, "Hourglass", Vector3.new(1.4, 2.4, 1.4), freezyCf * CFrame.new(0, 5.8, 0), C.Gold, Enum.Material.Glass)
		Build.Neon({
			Name = "FrostGlow",
			Size = Vector3.new(4.8, 0.3, 4.8),
			CFrame = freezyCf * CFrame.new(0, 0.3, 0),
			Color = ICE,
			Parent = m,
		})
		return m
	end)

	------------------------------------------------------------------------------------
	-- Scénario : écran figé (infecté) / image fluide (nettoyé)
	------------------------------------------------------------------------------------

	local infected = Build.Model("CanyonInfected", decor)
	ctx.Infected(infected)
	for i, spot in { Vector3.new(100, B + 60, -20), Vector3.new(76, B + 88, 40) } do
		local popup =
			Box(infected, "FrozenWindow", Vector3.new(22, 10, 0.4), facing(spot, if i == 1 then WEST else SOUTH), C.Bg)
		Props.Sign(popup, "(Ne répond pas)", "Render.exe · 3 FPS", GLITCH, C.White)
	end
	for _, fz in FAN_Z do
		Build.Neon({
			Name = "AlertRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 4, 4),
			CFrame = CFrame.fromMatrix(Vector3.new(CARD_X1 + 6.4, B + FAN_Y, fz), EAST, UP),
			Color = LETHAL,
			Transparency = 0.3,
			Parent = infected,
		})
	end
	for _, spot in
		{ Vector3.new(62, B + 17.1, 26), Vector3.new(cardX, topY + 0.1, -90), Vector3.new(trackX + 4, B + 23.1, 60) }
	do
		Build.Neon({
			Name = "GlitchPuddle",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 4.5, 4.5),
			CFrame = CFrame.new(spot) * FLAT,
			Color = GLITCH,
			Transparency = 0.45,
			Parent = infected,
		})
	end
	local cleaned = Build.Model("CanyonCleaned", decor)
	ctx.Cleaned(cleaned)
	local fps = Box(cleaned, "FpsCounter", Vector3.new(22, 10, 0.4), facing(Vector3.new(100, B + 60, -20), WEST), C.Bg)
	Props.Sign(fps, "120 FPS", "Image fluide", P, C.White)
	for _, fz in FAN_Z do
		local ring = Build.Neon({
			Name = "RgbRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 5, 5),
			CFrame = CFrame.fromMatrix(Vector3.new(CARD_X1 + 6.4, B + FAN_Y, fz), EAST, UP),
			Color = S,
			Transparency = 0.2,
			Parent = cleaned,
		})
		ring:AddTag("RgbStrip")
	end
	ctx.Lamp(Vector3.new(cardX + 20, B + 50, 0), S:Lerp(C.White, 0.3), 1.5, 90, cleaned)

	ctx.TerminalRoom()
	assert(math.abs(door.Y - (B + 80)) < 1e-6, "monde 6 : le seuil doit être au niveau de la porte")
end
