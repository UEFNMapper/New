--!strict
--[[
	Monde 2 : Memory Lanes (mémoire vive) — « Mémoire saturée, 200 onglets ouverts ».

	Une ville de barrettes de RAM GÉANTES plantées debout (grand axe vertical, 84 studs de haut) :
	on circule dans les « rues » entre elles, on grimpe sur leurs puces, on traverse d'une barrette
	à l'autre. Au centre, 4 barrettes forment un canyon vertical où la fuite mémoire monte.
	Parcours (vue de dessus, sens inverse des aiguilles d'une montre) :

	  Étape 1 (rangée des slots, avant) BARRETTES QUI S'ENFONCENT : on court sur un slot DIMM
	                                    pendant que des barrettes y tombent en rythme (Crusher).
	  Étape 2 (rue de gauche)           BUS DE DONNÉES : tapis qui ramènent en arrière (Conveyor),
	                                    paquets de données qui font traverser (Mover), ascenseur.
	  Étape 3 (place du fond)           PLUIE D'ONGLETS : des fenêtres de navigateur tombent sur les
	                                    puces (TabRain) : on suit les ombres rouges pour les éviter.
	  Étape 4 (canyon central)          FUITE MÉMOIRE : le flot violet MONTE dans le canyon (Flood) :
	                                    on grimpe de puce en puce, d'une barrette à l'autre, avant lui.
	  Étape 5 (rue de droite)           FINALE : tapis + barrette qui tombe, paquet de données, tapis
	                                    sous la pluie d'onglets, slot gardé par deux barrettes, porte.

	POP-UP STORM (incident vedette) : les fenêtres couvrent l'écran ; les sections chronométrées
	(canyon, pluie d'onglets) deviennent plus dures ; chaque section commence sur une plateforme sûre
	où l'on peut fermer les pubs avant de repartir.

	Clés USB (chemins facultatifs difficiles) :
	  1. étape 2 : ruelle entre deux barrettes, tapis étroit qui pousse vers le vide ;
	  2. étape 3 : au-dessus du vide, les onglets posés servent de passerelle éphémère ;
	  3. étape 5 : paquet de données vers la vitre, clé sous une barrette qui s'enfonce.

	Décor : vrais modèles (`RamStick` en grand nombre, `DimmSlot`, `ChipsetHeatsink`, `PopUp`) avec
	décor de secours. Le gameplay ne dépend d'aucun modèle (murs du canyon = pièces invisibles).
	Infecté : pubs « 200 ONGLETS », alertes « RAM 99 % », flaques de glitch. Nettoyé : barres RGB,
	panneau « MÉMOIRE LIBÉRÉE », voyants verts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tower = require(ReplicatedStorage:WaitForChild("Shared").Config.Tower)
local Build = require(script.Parent.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Parent.Props)
local ModelLibrary = require(script.Parent.Parent.Parent.ModelLibrary)
local Common = require(script.Parent.Parent.Common)

local C = Common.C
local UP = Common.UP
local VERTICAL = Common.VERTICAL
local Box = Props.Box
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

local LETHAL = Common.Colors.Lethal
local GLITCH = Common.Colors.Glitch
local SAFE = Common.Colors.Safe
local SPRING = Common.Colors.Spring

local VIOLET = Color3.fromHex("8B7CFF") -- identité du monde
local LILAC = Color3.fromHex("C084FC")
local CRUSH = Color3.fromRGB(150, 36, 96) -- barrette qui écrase (mortelle : magenta)
local LEAK = Color3.fromRGB(176, 64, 236) -- fuite mémoire (mortelle : magenta-violet)
local BELT = Color3.fromRGB(34, 38, 60)
local CHIP = Color3.fromRGB(24, 24, 32)
local SLOT = Color3.fromRGB(20, 20, 26)
local LATCH = Color3.fromRGB(226, 222, 246)
local ALERT = Color3.fromRGB(255, 58, 58)

local STICK_H = 84 -- hauteur des barrettes géantes (du slot à la barre RGB)
local STICK_W = 24 -- largeur (dimension « hauteur » d'une vraie barrette)
local STICK_T = 4.4 -- épaisseur (PCB + dissipateurs)
local SLOT_TOP = 4 -- dessus des slots DIMM au sol (relatif à la base du monde)

return function(ctx: Common.WorldContext)
	local B = ctx.Base
	local decor = ctx.Decor

	-- Point du monde (y relatif au bas de la tranche).
	local function V(x: number, y: number, z: number): Vector3
		return Vector3.new(x, B + y, z)
	end

	------------------------------------------------------------------------------------
	-- Outils de gameplay (pièces primitives)
	------------------------------------------------------------------------------------

	-- Bloc praticable aligné sur les axes (dessus à `top`) + liserés lumineux sur les grands côtés.
	local function block(
		folder: Instance,
		name: string,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		color: Color3,
		material: Enum.Material?,
		rim: Color3?,
		thick: number?
	): Part
		local h = thick or 2
		local sx, sz = x1 - x0, z1 - z0
		local cf = CFrame.new(V((x0 + x1) / 2, top - h / 2, (z0 + z1) / 2))
		local part = Build.Part({
			Name = name,
			Size = Vector3.new(sx, h, sz),
			CFrame = cf,
			Color = color,
			Material = material or SMOOTH,
			Parent = folder,
		})
		local edge = rim or VIOLET:Lerp(C.White, 0.2)
		for _, side in { -1, 1 } do
			Build.Neon({
				Name = "Rim",
				Size = if sx > sz then Vector3.new(sx, 0.4, 0.4) else Vector3.new(0.4, 0.4, sz),
				CFrame = cf * CFrame.new(
					if sx > sz then 0 else side * sx / 2,
					h / 2 - 0.15,
					if sx > sz then side * sz / 2 else 0
				),
				Color = edge,
				Transparency = 0.25,
				Parent = part,
			})
		end
		return part
	end

	-- Palier sûr aux couleurs du monde.
	local function deck(
		folder: Instance,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		name: string?
	): Part
		return block(folder, name or "Landing", x0, x1, z0, z1, top, ctx.Style.Floor, ctx.Style.FloorMat)
	end

	-- Puce mémoire praticable (noire, liseré violet, point de repère blanc).
	local function chip(folder: Instance, x0: number, x1: number, z0: number, z1: number, top: number): Part
		local part = block(folder, "MemoryChip", x0, x1, z0, z1, top, CHIP, SMOOTH, VIOLET, 1.6)
		Box(part, "Pin1", Vector3.new(0.8, 0.1, 0.8), CFrame.new(V(x0 + 1, top + 0.03, z0 + 1)), C.Silk)
		return part
	end

	-- Slot DIMM praticable : bac noir, rainure dorée au centre.
	local function slot(folder: Instance, x0: number, x1: number, z0: number, z1: number, top: number): Part
		local part = block(folder, "DimmSlot", x0, x1, z0, z1, top, SLOT, SMOOTH, VIOLET, 3)
		local sx, sz = x1 - x0, z1 - z0
		Box(
			part,
			"Groove",
			if sx > sz then Vector3.new(sx - 1, 0.1, 1.2) else Vector3.new(1.2, 0.1, sz - 1),
			CFrame.new(V((x0 + x1) / 2, top + 0.03, (z0 + z1) / 2)),
			C.Gold,
			Enum.Material.Foil
		)
		return part
	end

	-- Barrette qui s'enfonce dans son slot (Crusher) en travers d'un passage : `alongX` = la
	-- barrette s'étend le long de X (le passage suit Z). Loquets du slot de part et d'autre.
	local function crusher(
		folder: Instance,
		x: number,
		z: number,
		alongX: boolean,
		span: number,
		walkTop: number,
		period: number,
		phase: number
	): Part
		local height, clearance = 16, 12
		local size = if alongX then Vector3.new(span, height, 3) else Vector3.new(3, height, span)
		local cf = CFrame.new(V(x, walkTop + clearance + height / 2, z))
		local stick = Build.Part({
			Name = "FallingStick",
			Size = size,
			CFrame = cf,
			Color = CRUSH,
			Material = SMOOTH,
			CastShadow = false,
			Parent = folder,
		})
		stick.CanCollide = false
		stick.CanQuery = false
		ctx.Trap("Crusher", stick, { Offset = Vector3.new(0, -clearance, 0), Period = period, Phase = phase })
		local edge = if alongX then Vector3.new(span + 0.2, 0.7, 3.2) else Vector3.new(3.2, 0.7, span + 0.2)
		Common.Attach(stick, "Edge", edge, cf * CFrame.new(0, -height / 2 + 0.35, 0), LETHAL, NEON)
		for k = -1, 1 do
			local offset = if alongX then Vector3.new(k * span / 3.4, 1.5, 0) else Vector3.new(0, 1.5, k * span / 3.4)
			Common.Attach(
				stick,
				"Chip",
				if alongX then Vector3.new(span / 4.5, 3.4, 3.4) else Vector3.new(3.4, 3.4, span / 4.5),
				cf + offset,
				CHIP
			)
		end
		-- Loquets blancs du slot, hors du passage
		for _, s in { -1, 1 } do
			local p = if alongX
				then V(x + s * (span / 2 + 1.2), walkTop + 3, z)
				else V(x, walkTop + 3, z + s * (span / 2 + 1.2))
			Box(decor, "Latch", Vector3.new(2.2, 6, 2.2), CFrame.new(p), LATCH)
		end
		return stick
	end

	-- Tapis de données (Conveyor) : pousse dans `dir` ; chevrons violets dans le sens de la poussée.
	local function belt(
		folder: Instance,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		dir: Vector3,
		speed: number
	): Part
		local sx, sz = x1 - x0, z1 - z0
		local alongX = sx > sz
		local long, short = math.max(sx, sz), math.min(sx, sz)
		local cf = CFrame.new(V((x0 + x1) / 2, top - 1, (z0 + z1) / 2))
			* (if alongX then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity)
		local part = Build.Part({
			Name = "DataBus",
			Size = Vector3.new(short, 2, long),
			CFrame = cf,
			Color = BELT,
			Material = SMOOTH,
			Parent = folder,
		})
		ctx.Trap("Conveyor", part, { Direction = dir, Speed = speed })
		-- Chevrons « > » dans le sens de la poussée
		local flat = Vector3.new(dir.X, 0, dir.Z).Unit
		local count = math.floor(long / 7)
		for k = 1, count do
			local along = -long / 2 + long * (k - 0.5) / count
			local center = (cf * CFrame.new(0, 1.06, along)).Position
			for _, side in { -1, 1 } do
				local wing = flat:Cross(UP) * side
				local look = (flat - wing).Unit
				Build.Neon({
					Name = "Chevron",
					Size = Vector3.new(0.5, 0.1, math.min(short * 0.3, 3)),
					CFrame = CFrame.lookAt(center + wing * math.min(short * 0.11, 1.1), center + wing * 2 + look),
					Color = LILAC,
					Transparency = 0.2,
					Parent = folder,
				})
			end
		end
		for _, side in { -1, 1 } do
			local offset = cf.RightVector * side * (short / 2 + 0.3)
			Box(
				folder,
				"BeltRail",
				Vector3.new(0.6, 2.4, long),
				cf + offset + Vector3.new(0, 0.2, 0),
				C.MetalLight,
				METAL
			)
		end
		return part
	end

	-- Paquet de données (Mover) : plateforme sûre qui fait l'aller-retour de `offset`.
	local function mover(
		folder: Instance,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		offset: Vector3,
		period: number,
		phase: number
	): Part
		local sx, sz = x1 - x0, z1 - z0
		local cf = CFrame.new(V((x0 + x1) / 2, top - 0.8, (z0 + z1) / 2))
		local packet = Build.Part({
			Name = "DataPacket",
			Size = Vector3.new(sx, 1.6, sz),
			CFrame = cf,
			Color = C.MetalLight,
			Material = METAL,
			CastShadow = false,
			Parent = folder,
		})
		ctx.Trap("Mover", packet, { Offset = offset, Period = period, Phase = phase })
		for _, s in { -1, 1 } do
			Common.Attach(
				packet,
				"PacketGlow",
				Vector3.new(0.4, 0.3, sz - 0.4),
				cf * CFrame.new(s * (sx / 2 - 0.2), 0.8, 0),
				SAFE,
				NEON
			)
		end
		Common.Attach(packet, "PacketBits", Vector3.new(sx - 2, 0.2, sz - 2), cf * CFrame.new(0, 0.85, 0), VIOLET, NEON).Transparency =
			0.5
		return packet
	end

	-- Pluie d'onglets (TabRain) : la racine est un repère invisible au centre de la zone.
	local function tabRain(
		folder: Instance,
		center: Vector3,
		size: Vector3,
		period: number,
		stay: number,
		phase: number
	)
		local root = Build.Part({
			Name = "TabRain",
			Size = Vector3.one * 2,
			CFrame = CFrame.new(center),
			Color = LETHAL,
			Transparency = 1,
			CastShadow = false,
			Parent = folder,
		})
		root.CanCollide = false
		root.CanQuery = false
		ctx.Trap("TabRain", root, { Size = size, Period = period, Stay = stay, Phase = phase })
		return root
	end

	local function checkpoint(stage: number, x: number, top: number, z: number, look: Vector3)
		ctx.Checkpoint(stage, Common.Facing(V(x, top, z), look))
	end

	local function coin(x: number, y: number, z: number)
		ctx.Coin(V(x, y, z))
	end

	------------------------------------------------------------------------------------
	-- Décor : barrettes géantes, slots, dissipateur du chipset (modèles 3D + secours)
	------------------------------------------------------------------------------------

	local stickCount = 0

	-- Barrette géante debout : `x, z` = centre de sa base ; `alongX` = sa largeur suit X.
	-- Modèle `RamStick` (long axe X, contacts en bas) : tourné pour que son long axe soit vertical.
	local function ramStick(x: number, z: number, alongX: boolean, label: string?)
		stickCount += 1
		local index = stickCount
		local fit = Vector3.new(STICK_H, STICK_W, 4) -- axes du modèle : longueur, hauteur, épaisseur
		local base = CFrame.new(V(x, SLOT_TOP + STICK_H / 2, z))
			* (if alongX then CFrame.identity else CFrame.Angles(0, math.pi / 2, 0))
		local pivot = base * CFrame.new(STICK_W / 2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
		ModelLibrary.Place("RamStick", pivot, decor, { Fit = fit }, function(): Instance?
			local model = Build.Model("RamStick", decor)
			local function at(u: number, y: number): CFrame
				return base * CFrame.new(u, y - STICK_H / 2, 0)
			end
			Box(model, "Pcb", Vector3.new(STICK_W, STICK_H, 1.2), at(0, STICK_H / 2), C.PcbDark)
			Box(model, "Fingers", Vector3.new(STICK_W - 3, 2, 1.5), at(0, 1), C.Gold, Enum.Material.Foil)
			local spreader = Box(
				model,
				"HeatSpreader",
				Vector3.new(STICK_W - 1, STICK_H - 12, STICK_T),
				at(0, 6 + (STICK_H - 12) / 2),
				if index % 2 == 0 then C.MetalDark else Color3.fromRGB(70, 64, 104),
				METAL
			)
			for _, u in { -STICK_W / 4, STICK_W / 4 } do
				Build.Neon({
					Name = "Chevron",
					Size = Vector3.new(1, (STICK_H - 12) * 0.7, STICK_T + 0.2),
					CFrame = at(u, 6 + (STICK_H - 12) / 2),
					Color = LILAC,
					Transparency = 0.45,
					Parent = model,
				})
			end
			Build.Neon({
				Name = "RgbBar",
				Size = Vector3.new(STICK_W - 1, 3, STICK_T + 0.3),
				CFrame = at(0, STICK_H - 3.5),
				Color = VIOLET,
				Transparency = 0.1,
				Parent = model,
			})
			if label then
				Props.Sign(spreader, label, "DDR5 · 6400", LILAC, C.Silk)
				Props.Sign(spreader, label, "DDR5 · 6400", LILAC, C.Silk, Enum.NormalId.Back)
			end
			return model
		end)
		-- Slot DIMM au pied (modèle `DimmSlot`, long axe X) + loquets
		ModelLibrary.Place(
			"DimmSlot",
			CFrame.new(V(x, 0, z)) * (if alongX then CFrame.identity else CFrame.Angles(0, math.pi / 2, 0)),
			decor,
			{ Fit = Vector3.new(STICK_W + 6, SLOT_TOP + 1, 6) },
			function(): Instance?
				local model = Build.Model("DimmSlot", decor)
				local slotCf = CFrame.new(V(x, SLOT_TOP / 2 + 0.5, z))
					* (if alongX then CFrame.identity else CFrame.Angles(0, math.pi / 2, 0))
				Box(model, "SlotBody", Vector3.new(STICK_W + 6, SLOT_TOP + 1, 6), slotCf, SLOT)
				for _, s in { -1, 1 } do
					Box(
						model,
						"Latch",
						Vector3.new(2.4, 7, 4.6),
						slotCf * CFrame.new(s * (STICK_W / 2 + 2), 2.5, 0),
						LATCH
					)
				end
				return model
			end
		)
	end

	-- Dissipateur du chipset (modèle `ChipsetHeatsink`).
	local function chipsetHeatsink(x: number, z: number, top: number, size: number)
		ModelLibrary.Place(
			"ChipsetHeatsink",
			CFrame.new(V(x, top - size / 4, z)),
			decor,
			{ Fit = Vector3.new(size, size / 4, size) },
			function(): Instance?
				local model = Build.Model("ChipsetHeatsink", decor)
				local h = size / 4
				Box(
					model,
					"HeatsinkBase",
					Vector3.new(size, 1.5, size),
					CFrame.new(V(x, top - h + 0.75, z)),
					C.MetalDark,
					METAL
				)
				for k = 0, 5 do
					Box(
						model,
						"Fin",
						Vector3.new(size - 1, h - 1.5, 0.8),
						CFrame.new(V(x, top - (h - 1.5) / 2, z - size / 2 + 1 + k * (size - 2) / 5)),
						C.Aluminum:Lerp(VIOLET, 0.15),
						METAL
					)
				end
				return model
			end
		)
	end

	-- Pop-Up : fenêtre de pub vivante (sbire du monde 2).
	local function popUpFallback(cf: CFrame, parent: Instance): Instance?
		local model = Build.Model("PopUp", parent)
		Build.Decor({
			Name = "Page",
			Size = Vector3.new(7, 5, 0.5),
			CFrame = cf,
			Color = Color3.fromRGB(246, 247, 251),
			Material = SMOOTH,
			Parent = model,
		})
		Build.Neon({
			Name = "TitleBar",
			Size = Vector3.new(7.2, 1.1, 0.7),
			CFrame = cf * CFrame.new(0, 2.9, 0),
			Color = GLITCH,
			Parent = model,
		})
		Build.Neon({
			Name = "CloseButton",
			Size = Vector3.new(1, 0.9, 0.9),
			CFrame = cf * CFrame.new(3, 2.9, -0.15),
			Color = LETHAL,
			Parent = model,
		})
		for _, x in { -1.5, 1.5 } do
			Build.Decor({
				Name = "Eye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.8,
				CFrame = cf * CFrame.new(x, 0.5, -0.4),
				Color = C.White,
				Material = SMOOTH,
				Parent = model,
			})
			Build.Decor({
				Name = "Pupil",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.8,
				CFrame = cf * CFrame.new(x + 0.2, 0.4, -1.1),
				Color = C.Black,
				Material = SMOOTH,
				Parent = model,
			})
		end
		Build.Decor({
			Name = "Grin",
			Size = Vector3.new(3, 0.5, 0.3),
			CFrame = cf * CFrame.new(0, -1.3, -0.35),
			Color = GLITCH,
			Material = SMOOTH,
			Parent = model,
		})
		local label = Build.Decor({
			Name = "Ad",
			Size = Vector3.new(5, 0.8, 0.1),
			CFrame = cf * CFrame.new(0, -2.1, -0.3),
			Color = C.Bg,
			Transparency = 1,
			Parent = model,
		})
		Props.Label(label, "CLIQUE ICI !", GLITCH, Enum.NormalId.Front, Enum.Font.GothamBlack)
		return model
	end

	------------------------------------------------------------------------------------
	-- Entrée, vide
	------------------------------------------------------------------------------------

	ctx.Void()
	ctx.Entrance()

	------------------------------------------------------------------------------------
	-- Étape 1 — Rangée des slots : barrettes qui s'enfoncent en rythme (Crusher)
	------------------------------------------------------------------------------------

	local first = Tower.FirstStage(ctx.Index)
	local s1 = ctx.Stage(first)
	deck(s1, 82, 94, -80, -68, 10, "SlotLanding")
	slot(s1, 44, 80, -72, -62, 11)
	-- Trois barrettes en « vague verte » : en courant juste derrière la première qui remonte, les
	-- suivantes remontent à ton passage (chacune tombe 0,6 s après la précédente)
	crusher(s1, 72, -67, false, 12, 11, 3.2, 0.4)
	crusher(s1, 61, -67, false, 12, 11, 3.2, 0.2)
	crusher(s1, 50, -67, false, 12, 11, 3.2, 0)
	-- Puis trois barrettes à contretemps : il faut s'arrêter entre elles (11 studs d'écart)
	slot(s1, 4, 40, -72, -62, 14)
	crusher(s1, 33, -67, false, 12, 14, 3.2, 0.1)
	crusher(s1, 22, -67, false, 12, 14, 3.2, 0.35)
	crusher(s1, 11, -67, false, 12, 14, 3.2, 0.6)
	chip(s1, -8, 0, -72, -62, 17.5)
	chip(s1, -22, -14, -72, -62, 21)
	coin(66.5, 13.5, -67)
	coin(27.5, 16.5, -67)
	coin(-4, 20, -67)
	coin(-18, 23.5, -67)
	checkpoint(first, -32, 24, -67, Vector3.zAxis)

	------------------------------------------------------------------------------------
	-- Étape 2 — Bus de données : tapis (Conveyor), paquets (Mover), ascenseur
	------------------------------------------------------------------------------------

	local s2 = ctx.Stage(first + 1)
	belt(s2, -37, -27, -57, -21, 25, -Vector3.zAxis, 6)
	deck(s2, -38, -26, -21, -13, 26.5, "BusJunction")
	mover(s2, -37, -27, -12, -4, 26.5, Vector3.new(0, 0, 13), 6, 0)
	deck(s2, -38, -26, 10, 18, 27.5, "BusJunction")
	belt(s2, -37, -27, 18, 46, 29, -Vector3.zAxis, 7)
	deck(s2, -38, -26, 46, 54, 30.5, "BusJunction")
	-- Ascenseur de données : seul moyen d'atteindre le checkpoint (7,5 studs plus haut)
	mover(s2, -37, -27, 55, 63, 30.5, Vector3.new(0, 7, 0), 5, 0.25)
	coin(-32, 27.5, -40)
	coin(-32, 29.5, -8)
	coin(-32, 31.5, 32)
	coin(-32, 35, 59)
	checkpoint(first + 1, -32, 38, 72, Vector3.xAxis)

	-- Clé USB 1 : ruelle entre deux barrettes, tapis étroit qui pousse vers le vide
	belt(s2, -58, -38, 10, 14, 27.5, Vector3.zAxis, 8)
	deck(s2, -70, -60, 6, 18, 28.5, "KeyPerch")
	ctx.UsbKey(V(-65, 31, 12), 1)

	------------------------------------------------------------------------------------
	-- Étape 3 — Pluie d'onglets (TabRain) sur les puces du chipset
	------------------------------------------------------------------------------------

	local s3 = ctx.Stage(first + 2)
	for _, x in { -16.5, -5.5, 5.5, 16.5 } do
		for _, z in { 70, 82 } do
			chip(s3, x - 4, x + 4, z - 4, z + 4, 40)
		end
	end
	-- Onglets qui tombent sur les puces : l'ombre rouge prévient 1,7 s avant l'impact
	tabRain(s3, V(0, 40 + 13, 76), Vector3.new(44, 26, 24), 1.2, 2.5, 0)
	chip(s3, 24, 32, 68, 78, 43.5)
	chip(s3, 22, 30, 56, 64, 46.5)
	chip(s3, 10, 18, 48, 56, 49.5)
	coin(-11, 42.5, 76)
	coin(11, 42.5, 76)
	coin(28, 46.5, 73)
	coin(14, 52.5, 52)
	checkpoint(first + 2, 0, 52, 52, -Vector3.zAxis)

	-- Clé USB 2 : au-dessus du vide, seuls les onglets posés font un pont (4 s chacun)
	tabRain(s3, V(0, 43 + 10, 105.5), Vector3.new(36, 20, 35), 0.6, 4, 0.5)
	deck(s3, -6, 6, 124, 131, 45.5, "KeyPerch")
	ctx.UsbKey(V(0, 48, 127.5), 2)

	------------------------------------------------------------------------------------
	-- Étape 4 — Canyon central : la fuite mémoire monte (Flood), on grimpe de puce en puce
	------------------------------------------------------------------------------------

	local s4 = ctx.Stage(first + 3)
	-- Murs du canyon : deux barrettes de chaque côté (pièces de collision invisibles)
	for _, side in { -1, 1 } do
		local wall = Build.Part({
			Name = "CanyonWall",
			Size = Vector3.new(STICK_T, STICK_H, 50),
			CFrame = CFrame.new(V(side * (7.8 + STICK_T / 2), SLOT_TOP + STICK_H / 2, 19)),
			Color = C.MetalDark,
			Transparency = 1,
			CastShadow = false,
			Parent = s4,
		})
		wall.CanQuery = false
	end
	-- Puces en quinconce sur les deux faces (écart 4,6 studs, +3 à chaque saut)
	local ledges = {
		{ -1, 32, 40, 48 },
		{ 1, 24, 32, 51 },
		{ -1, 16, 24, 54 },
		{ 1, 8, 16, 57 },
		{ -1, 0, 8, 60 },
		{ 1, -6, 0, 63 },
	}
	for _, l in ledges do
		local x0 = if l[1] < 0 then -7.8 else 2.3
		chip(s4, x0, x0 + 5.5, l[2], l[3], l[4])
	end
	-- La fuite : repos à 144, monte de 21 studs en 9,9 s (≈ 2 studs/s), reste 2,7 s, se vide.
	local leak = Build.Part({
		Name = "MemoryLeak",
		Size = Vector3.new(15.6, 1, 50),
		CFrame = CFrame.new(V(0, 43.5, 19)),
		Color = LEAK,
		Material = NEON,
		Transparency = 0.3,
		CastShadow = false,
		Parent = s4,
	})
	leak.CanCollide = false
	leak.CanQuery = false
	ctx.Trap("Flood", leak, { Rise = 21, Period = 18, Phase = 0 })
	for k = 0, 2 do
		Common.Attach(
			leak,
			"Bubble",
			Vector3.new(0.3, 0.2, 14),
			CFrame.new(V(-4 + k * 4, 44.05, 5 + k * 13)) * CFrame.Angles(0, 0.3 * k, 0),
			LILAC,
			NEON
		).Transparency =
			0.3
	end
	coin(-5, 50.5, 36)
	coin(5, 53.5, 28)
	coin(-5, 62.5, 4)
	coin(5, 65.5, -3)
	checkpoint(first + 3, 0, 66, -14, Vector3.xAxis)

	------------------------------------------------------------------------------------
	-- Étape 5 — Finale (rue de droite) : tapis + barrette, paquet, pluie d'onglets, slot gardé
	------------------------------------------------------------------------------------

	local s5 = ctx.Stage(first + 4)
	belt(s5, 10, 44, -19, -9, 67, -Vector3.xAxis, 7)
	crusher(s5, 27, -14, false, 12, 67, 3.4, 0)
	deck(s5, 44, 54, -20, -8, 68.5, "BusJunction")
	mover(s5, 56, 64, -18, -10, 68.5, Vector3.new(14, 0, 0), 5.5, 0.5)
	deck(s5, 80, 94, -20, -8, 69, "BusJunction")
	belt(s5, 82, 92, -8, 24, 70.5, -Vector3.zAxis, 7)
	tabRain(s5, V(87, 70.5 + 12, 8), Vector3.new(14, 24, 32), 1.5, 2, 0.2)
	deck(s5, 81, 93, 24, 32, 72, "BusJunction")
	slot(s5, 82, 92, 32, 56, 73.5)
	crusher(s5, 87, 40, true, 12, 73.5, 3.2, 0.3)
	crusher(s5, 87, 49, true, 12, 73.5, 3.2, 0.65)
	chip(s5, 82, 92, 58, 64, 76.5)
	deck(s5, 82, 94, 66, 80, 80, "DoorApproach")
	coin(38, 69.5, -14)
	coin(67, 71.5, -14)
	coin(87, 73, 16)
	coin(87, 76, 44.5)

	-- Clé USB 3 : paquet de données vers la vitre, clé sous une barrette qui s'enfonce
	mover(s5, 96, 104, -18, -10, 69, Vector3.new(18, 0, 0), 5, 0)
	slot(s5, 124, 131, -20, -8, 69.5)
	crusher(s5, 127.5, -14, false, 12, 69.5, 3.2, 0.5)
	ctx.UsbKey(V(127.5, 72, -14), 3)

	local room = ctx.TerminalRoom()

	------------------------------------------------------------------------------------
	-- Décor : la ville des barrettes
	------------------------------------------------------------------------------------

	-- Le canyon central (4 barrettes, faces intérieures à x = ±7,8)
	for _, side in { -1, 1 } do
		ramStick(side * (7.8 + STICK_T / 2), 7, false, if side < 0 then "MEMORY LANES" else nil)
		ramStick(side * (7.8 + STICK_T / 2), 31, false)
	end
	-- Rue de gauche (étape 2) : mur de barrettes à l'ouest, ruelle libre pour la clé 1
	for _, z in { -50, -24, 28, 54 } do
		ramStick(-50, z, false)
	end
	-- Rangée avant (derrière les slots de l'étape 1) et vis-à-vis
	for _, x in { -40, -14, 12, 38, 64 } do
		ramStick(x, -94, true, if x == 12 then "200 ONGLETS" else nil)
	end
	for _, x in { 10, 36, 62 } do
		ramStick(x, -44, true)
	end
	-- Fond et rue de droite
	for _, x in { -64, -38, 42, 66 } do
		ramStick(x, 114, true)
	end
	for _, z in { 22, 48, -62 } do
		ramStick(112, z, false)
	end

	-- Dissipateurs du chipset : sous la place des onglets et au sol
	Box(decor, "PlazaPillar", Vector3.new(30, 34, 16), CFrame.new(V(0, 21, 76)), C.MetalDark, METAL)
	chipsetHeatsink(0, 76, 38.5, 40)
	chipsetHeatsink(60, 30, 12, 32)
	chipsetHeatsink(-90, -100, 10, 28)

	-- Pistes de la carte mère (violettes) entre les slots
	for _, t in
		{
			{ V(0, 0.45, -80), Vector3.new(220, 0.1, 1) },
			{ V(0, 0.45, 100), Vector3.new(220, 0.1, 1) },
			{ V(-80, 0.45, 10), Vector3.new(1, 0.1, 160) },
			{ V(100, 0.45, 0), Vector3.new(1, 0.1, 120) },
		} :: { { any } }
	do
		Build.Neon({
			Name = "Trace",
			Size = t[2],
			CFrame = CFrame.new(t[1]),
			Color = VIOLET,
			Transparency = 0.4,
			Parent = decor,
		})
	end

	-- Paroi du fond : fenêtre de navigateur géante (infecté : 16 onglets entassés ; nettoyé : 2)
	local browserCf = Common.Facing(V(0, 72, 131.4), -Vector3.zAxis)
	Box(decor, "BrowserBezel", Vector3.new(86, 42, 0.6), browserCf, C.Black)
	local page = Box(decor, "BrowserPage", Vector3.new(82, 30, 0.3), browserCf * CFrame.new(0, -4, -0.45), C.Bg)
	Props.Sign(page, "MEMORY LANES", "Mémoire vive · DDR5 · 4 × 16 GB", VIOLET, C.Silk)
	local address = Box(decor, "AddressBar", Vector3.new(74, 2.4, 0.3), browserCf * CFrame.new(-3, 13.5, -0.45), C.Silk)
	Props.Label(address, "https://anga.tv/live", C.Bg, Enum.NormalId.Front, Enum.Font.GothamBold)
	Build.Neon({
		Name = "BrowserClose",
		Size = Vector3.new(2.4, 2.4, 0.5),
		CFrame = browserCf * CFrame.new(39.5, 17.5, -0.4),
		Color = LETHAL,
		Parent = decor,
	})

	-- Lumières (7 + entrée + salle = 9)
	ctx.Lamp(V(40, 30, -67), LILAC:Lerp(C.White, 0.4), 1.3, 70)
	ctx.Lamp(V(-32, 44, -10), LILAC:Lerp(C.White, 0.4), 1.3, 70)
	ctx.Lamp(V(0, 60, 80), VIOLET:Lerp(C.White, 0.4), 1.3, 70)
	ctx.Lamp(V(0, 40, 20), LEAK, 2, 50) -- la fuite éclaire le canyon par en dessous
	ctx.Lamp(V(87, 86, 10), LILAC:Lerp(C.White, 0.4), 1.3, 70)
	ctx.Lamp(V(0, 92, 0), C.White, 0.9, 110)

	------------------------------------------------------------------------------------
	-- Sbire : Pop-Up garde le terminal (dans la salle, près de l'écran)
	------------------------------------------------------------------------------------

	local popCf = CFrame.lookAt(V(110, 88, 112), V(88, 86, 84))
	ModelLibrary.Place("PopUp", popCf * CFrame.new(0, -3, 0), room, { Scale = 1.6 }, function(): Instance?
		return popUpFallback(popCf, room)
	end)
	ctx.Lamp(V(110, 92, 112), GLITCH:Lerp(C.White, 0.3), 1.1, 18, room)

	------------------------------------------------------------------------------------
	-- Infecté / nettoyé
	------------------------------------------------------------------------------------

	local infected = Build.Model("Infected", decor)
	ctx.Infected(infected)
	-- Pubs flottantes (200 onglets ouverts…)
	for _, ad in
		{
			{ V(20, 30, -82), Vector3.zAxis, "200 ONGLETS OUVERTS", "Fermer ? Non." },
			{ V(-46, 42, -30), Vector3.xAxis, "TÉLÉCHARGE + DE RAM", "100 % gratuit (ou pas)" },
			{ V(-30, 52, 100), -Vector3.zAxis, "MÉMOIRE PLEINE 99 %", "Pop-Up approuve" },
			{ V(30, 70, 10), -Vector3.xAxis, "TU AS GAGNÉ !!!", "Clique vite sur le ✕" },
			{ V(104, 84, 30), -Vector3.xAxis, "LAGZ PREMIUM", "Encore plus de lag" },
		} :: { { any } }
	do
		local cf = Common.Facing(ad[1], ad[2]) * CFrame.Angles(0, 0, -0.05)
		local window = Box(infected, "AdWindow", Vector3.new(16, 9, 0.4), cf, C.Bg)
		Props.Sign(window, ad[3], ad[4], GLITCH:Lerp(C.White, 0.25), C.Silk)
		Build.Neon({
			Name = "AdTitleBar",
			Size = Vector3.new(16, 1.2, 0.5),
			CFrame = cf * CFrame.new(0, 5.1, 0),
			Color = GLITCH,
			Parent = infected,
		})
		Build.Neon({
			Name = "AdClose",
			Size = Vector3.new(1.2, 1, 0.6),
			CFrame = cf * CFrame.new(7.2, 5.1, -0.1),
			Color = ALERT,
			Parent = infected,
		})
	end
	-- Alertes rouges « RAM 99 % » sur les parois
	for _, a in
		{
			{ V(-131.5, 60, 0), Vector3.xAxis },
			{ V(0, 50, -131.5), Vector3.zAxis },
		} :: { { Vector3 } }
	do
		local cf = Common.Facing(a[1], a[2])
		Build.Neon({
			Name = "AlertStrip",
			Size = Vector3.new(60, 1.2, 0.4),
			CFrame = cf,
			Color = ALERT,
			Parent = infected,
		})
		local warn = Box(infected, "AlertSign", Vector3.new(26, 7, 0.4), cf * CFrame.new(0, 6, 0), C.Bg)
		Props.Sign(warn, "⚠ RAM 99 %", "Fuite mémoire détectée", ALERT, C.Silk)
	end
	for i = 0, 15 do
		Build.Neon({
			Name = "CrowdedTab",
			Size = Vector3.new(4.4, 2.6, 0.4),
			CFrame = browserCf * CFrame.new(-37 + i * 4.7, 17.5, -0.4),
			Color = if i % 2 == 0 then VIOLET else LILAC,
			Transparency = 0.15,
			Parent = infected,
		})
	end
	for _, p in { { -60, -20, 16 }, { 50, 60, 20 }, { 60, -30, 14 }, { -90, 90, 18 } } :: { { number } } do
		Props.Rod(infected, "GlitchPuddle", CFrame.new(V(p[1], 2.1, p[2])) * VERTICAL, 0.2, p[3], GLITCH, NEON).Transparency =
			0.3
	end

	local cleaned = Build.Model("Cleaned", decor)
	ctx.Cleaned(cleaned)
	-- Barres RGB propres au sommet des barrettes du canyon, panneau « MÉMOIRE LIBÉRÉE », voyants
	for _, side in { -1, 1 } do
		Build.Neon({
			Name = "CleanRgb",
			Size = Vector3.new(STICK_T + 0.6, 1.2, 50),
			CFrame = CFrame.new(V(side * (7.8 + STICK_T / 2), SLOT_TOP + STICK_H + 0.8, 19)),
			Color = VIOLET,
			Parent = cleaned,
		}):AddTag("RgbStrip")
	end
	for i, title in { "AngaTV · LIVE", "AngAInOne" } do
		local tab = Box(
			cleaned,
			"CleanTab",
			Vector3.new(14, 2.6, 0.4),
			browserCf * CFrame.new(-33 + (i - 1) * 15, 17.5, -0.4),
			VIOLET
		)
		Props.Label(tab, title, C.White, Enum.NormalId.Front, Enum.Font.GothamBold)
	end
	local freed = Box(cleaned, "FreedSign", Vector3.new(26, 7, 0.4), Common.Facing(V(0, 74, -40), -Vector3.zAxis), C.Bg)
	Props.Sign(freed, "MÉMOIRE LIBÉRÉE", "16 % utilisés · 0 onglet fantôme", SPRING, C.Silk)
	for i = 0, 3 do
		Build.Neon({
			Name = "MemOk",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.4,
			CFrame = CFrame.new(V(-36 + i * 24, 7, -88)),
			Color = SPRING,
			Parent = cleaned,
		})
	end
end
