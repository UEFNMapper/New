--!strict
--[[
	Monde 7 : Neural Nexus (puce IA) — le repaire de LAGZ.

	Décor : une puce NPU géante au fond du monde projette un CERVEAU HOLOGRAPHIQUE au centre de la
	tour ; le parcours est fait de plateformes flottantes qui en font le tour en montant (entrée au
	coin +X +Z, puis côté vitre +X, façade -Z et côté -X), reliées au cerveau par des synapses,
	jusqu'à l'arène de LAGZ devant la salle du terminal final.

	Étapes (une idée chacune, la 5ᵉ combine) :
	  31 Axones          neurones reliés par des axones : virus patrouilleurs en travers,
	                     paquets de données (Mover) ; clé 1 sur une île côté vitre.
	  32 Bus réseau      pare-feu mobiles (FirewallWall) : trouver le trou, changer de voie
	                     dans les poches entre deux murs ; clé 2 au-dessus du coin, sous un laser.
	  33 Bureau de LAGZ  fenêtres flottantes et barre des tâches sous le CURSEUR géant : ne jamais
	                     rester immobile (préavis 1 s, anneau rouge).
	  34 Couche cachée   lasers (barre basse à sauter + rideau), ascenseurs (Mover vertical),
	                     plateformes alimentées (Powered : BLACKOUT les coupe) ; clé 3 dans
	                     l'hologramme du cerveau.
	  35 Arène de LAGZ   combat en 3 phases (W7Arena + BossService + BossController).
	Incidents : tous (plus fréquents). FREEZE fige tout, LAG fait sauter murs et curseur,
	BLACKOUT éteint les plateformes alimentées de l'étape 34.
]]

local Common = require(script.Parent.Parent.Common)
local Build = require(script.Parent.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Parent.Props)
local ModelLibrary = require(script.Parent.Parent.Parent.ModelLibrary)
local Arena = require(script.Parent.W7Arena)

local C = Common.C
local Box = Props.Box
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic
local VERTICAL = Common.VERTICAL
local LETHAL = Common.Colors.Lethal
local GLITCH = Common.Colors.Glitch
local SAFE = Common.Colors.Safe

local BRICK = Color3.fromRGB(232, 84, 52) -- pare-feu (mortel : rouge orangé)
local HOLO = Color3.fromHex("E9D8FD")
local VIOLET = Color3.fromHex("9F7AEA")

return function(ctx: Common.WorldContext)
	local style = ctx.Style
	local decor = ctx.Decor

	ctx.Void()
	ctx.Entrance()
	-- Dossiers d'étapes créés de la dernière à la première : dans Lune (tests), GetDescendants les
	-- rend dans l'ordre inverse, et les témoins Laser / Virus de tower.spec (premier piège trouvé
	-- de chaque type) tombent ainsi sur l'étape 31, loin des curseurs et des pare-feu.
	for s = 35, 31, -1 do
		ctx.Stage(s)
	end

	--------------------------------------------------------------------------------
	-- Outils du monde
	--------------------------------------------------------------------------------

	-- Plateforme solide (x0..x1, z0..z1, dessus à `top`) ; liserés le long du plus grand côté.
	local function slab(stage: number, x0: number, x1: number, z0: number, z1: number, top: number, name: string?): Part
		local sx, sz = x1 - x0, z1 - z0
		local cf = CFrame.new((x0 + x1) / 2, top - 1, (z0 + z1) / 2)
		if sx > sz then
			return ctx.Platform(ctx.Stage(stage), Vector3.new(sz, 2, sx), cf * CFrame.Angles(0, math.pi / 2, 0), name)
		end
		return ctx.Platform(ctx.Stage(stage), Vector3.new(sx, 2, sz), cf, name)
	end

	-- Neurone : plateforme + noyau lumineux dessous + dendrites qui plongent vers la puce.
	local function neuron(stage: number, x0: number, x1: number, z0: number, z1: number, top: number): Part
		local part = slab(stage, x0, x1, z0, z1, top, "Soma")
		local c = Vector3.new((x0 + x1) / 2, top, (z0 + z1) / 2)
		local d = math.min(x1 - x0, z1 - z0)
		Build.Neon({
			Name = "Nucleus",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, d * 0.8, d * 0.8),
			CFrame = CFrame.new(c - Vector3.new(0, 2.3, 0)) * VERTICAL,
			Color = style.Primary,
			Transparency = 0.25,
			Parent = decor,
		})
		for k = 0, 1 do
			local a = c + Vector3.new(0, -2.5, 0)
			local b = a + Vector3.new(if k == 0 then 5 else -5, -9, if k == 0 then -3 else 3)
			Build.Neon({
				Name = "Dendrite",
				Size = Vector3.new((b - a).Magnitude, 0.35, 0.35),
				CFrame = Props.Along(a, b),
				Color = VIOLET,
				Transparency = 0.35,
				Parent = decor,
			})
		end
		return part
	end

	-- Plateforme mobile SÛRE (paquet de données / ascenseur).
	local function mover(
		stage: number,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		offset: Vector3,
		period: number,
		phase: number,
		name: string
	): Part
		local size = Vector3.new(x1 - x0, 1.2, z1 - z0)
		local cf = CFrame.new((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2)
		local part = Build.Part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = HOLO:Lerp(C.MetalLight, 0.35),
			Material = SMOOTH,
			Parent = ctx.Stage(stage),
		})
		ctx.Trap("Mover", part, { Offset = offset, Period = period, Phase = phase })
		for _, x in { -1, 1 } do
			Common.Attach(
				part,
				"PacketGlow",
				Vector3.new(0.4, 0.3, size.Z - 0.4),
				cf * CFrame.new(x * (size.X / 2 - 0.3), 0.66, 0),
				SAFE,
				NEON
			)
		end
		Common.Attach(
			part,
			"Thruster",
			Vector3.new(size.X * 0.6, 0.8, size.Z * 0.6),
			cf * CFrame.new(0, -1, 0),
			C.MetalDark,
			METAL
		)
		return part
	end

	-- Laser (barre basse à sauter, ou rideau vertical) qui balaie le long d'Offset.
	local function laser(stage: number, size: Vector3, cf: CFrame, offset: Vector3, period: number, phase: number): Part
		local beam = Build.Part({
			Name = "Laser",
			Size = size,
			CFrame = cf,
			Color = LETHAL,
			Material = NEON,
			CastShadow = false,
			CanCollide = false,
			Parent = ctx.Stage(stage),
		})
		ctx.Trap("Laser", beam, { Offset = offset, Period = period, Phase = phase })
		-- Émetteurs aux deux bouts (le long du grand axe)
		local axis = if size.X >= size.Y and size.X >= size.Z
			then Vector3.xAxis
			elseif size.Y >= size.Z then Vector3.yAxis
			else Vector3.zAxis
		local half = axis * (axis:Dot(size) / 2 + 0.5)
		for _, sign in { -1, 1 } do
			Common.Attach(beam, "Emitter", Vector3.one * 1.3, cf + half * sign, C.Black, METAL)
		end
		return beam
	end

	-- Pare-feu mobile : mur percé (12 × 10) qui avance le long d'Offset. `floor` = bas du mur,
	-- `alongX` : il avance selon X (mur dans le plan YZ). Holes : repère local du mur.
	local function firewall(
		stage: number,
		floor: Vector3,
		alongX: boolean,
		offset: Vector3,
		period: number,
		phase: number,
		holes: string
	): Part
		local cf = CFrame.new(floor + Vector3.new(0, 5, 0))
		if alongX then
			cf *= CFrame.Angles(0, math.pi / 2, 0)
		end
		local wall = Build.Part({
			Name = "FirewallWall",
			Size = Vector3.new(12, 10, 1),
			CFrame = cf,
			Color = BRICK,
			Material = Enum.Material.Brick,
			Transparency = 0.2,
			CastShadow = false,
			CanCollide = false,
			Parent = ctx.Stage(stage),
		})
		ctx.Trap("FirewallWall", wall, { Offset = offset, Period = period, Phase = phase, Holes = holes })
		return wall
	end

	-- Curseur géant de LAGZ (zone surveillée = boîte Area centrée sur la racine invisible).
	local function cursor(stage: number, center: Vector3, area: Vector3, period: number)
		local root = Build.Part({
			Name = "GiantCursor",
			Size = Vector3.one,
			CFrame = CFrame.new(center),
			Color = LETHAL,
			Transparency = 1,
			CastShadow = false,
			CanCollide = false,
			Parent = ctx.Stage(stage),
		})
		ctx.Trap("Cursor", root, { Period = period, Radius = 4, Area = area })
	end

	-- Plateforme alimentée : solide quand le courant passe (éteinte pendant un BLACKOUT).
	local function powered(stage: number, x0: number, x1: number, z0: number, z1: number, top: number, phase: number)
		local part = Build.Part({
			Name = "PoweredNeuron",
			Size = Vector3.new(x1 - x0, 1.2, z1 - z0),
			CFrame = CFrame.new((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2),
			Color = HOLO,
			Material = SMOOTH,
			Parent = ctx.Stage(stage),
		})
		ctx.Trap("Powered", part, { Period = 4, Duty = 0.6, Phase = phase })
	end

	-- Fenêtre d'application flottante (étape 33) : plateforme + barre de titre + 3 boutons.
	local function window(x0: number, x1: number, z0: number, z1: number, top: number, titleAtMinZ: boolean)
		slab(33, x0, x1, z0, z1, top, "Window").Color = Color3.fromRGB(226, 220, 240)
		local z = if titleAtMinZ then z0 + 0.8 else z1 - 0.8
		local cx = (x0 + x1) / 2
		Box(decor, "TitleBar", Vector3.new(x1 - x0, 0.2, 1.6), CFrame.new(cx, top + 0.1, z), VIOLET, NEON)
		for k = 1, 3 do
			Box(decor, "WindowButton", Vector3.new(0.9, 0.25, 0.9), CFrame.new(x1 - k * 1.3, top + 0.2, z), HOLO, NEON)
		end
	end

	-- Fenêtre de pub (décor infecté) : modèle PopUp, ou cadre blanc + bandeau + ✕.
	local function popup(position: Vector3, yaw: number)
		local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
		local placed = ModelLibrary.Place("PopUp", cf, decor, { Scale = 1.5 }, function()
			local model = Build.Model("PopUp")
			local frame = Box(model, "Frame", Vector3.new(9, 7, 0.4), cf * CFrame.new(0, 3.5, 0), C.White)
			Props.Sign(frame, "GAGNE UN PC !", "Clique ici (vraiment)", GLITCH, C.Black)
			Box(model, "TitleBar", Vector3.new(9, 1.1, 0.5), cf * CFrame.new(0, 7.3, 0), VIOLET, NEON)
			Box(model, "Close", Vector3.new(1, 1, 0.6), cf * CFrame.new(3.9, 7.3, -0.1), GLITCH, NEON)
			return model
		end)
		if placed then
			ctx.Infected(placed)
		end
	end

	--------------------------------------------------------------------------------
	-- Décor : puce NPU géante + cerveau holographique
	--------------------------------------------------------------------------------

	local base = ctx.Base
	local chipCf = CFrame.new(0, base + 1.6, 0)
	ModelLibrary.Place("NpuChip", chipCf, decor, { Scale = 1 }, function()
		local model = Build.Model("NpuChip")
		Box(model, "Package", Vector3.new(72, 3, 72), chipCf * CFrame.new(0, 1.5, 0), C.PcbDark, SMOOTH)
		for k = 0, 3 do
			local side = CFrame.Angles(0, k * math.pi / 2, 0)
			Box(
				model,
				"Pins",
				Vector3.new(66, 0.6, 2),
				chipCf * side * CFrame.new(0, 3.2, -34),
				C.Gold,
				Enum.Material.Foil
			)
			Build.Neon({
				Name = "Trace",
				Size = Vector3.new(0.8, 0.3, 14),
				CFrame = chipCf * side * CFrame.new(-9, 3.2, -25),
				Color = VIOLET,
				Transparency = 0.2,
				Parent = model,
			})
			Build.Neon({
				Name = "Trace",
				Size = Vector3.new(0.8, 0.3, 14),
				CFrame = chipCf * side * CFrame.new(9, 3.2, -25),
				Color = style.Primary,
				Transparency = 0.2,
				Parent = model,
			})
		end
		local die =
			Box(model, "Die", Vector3.new(36, 1.4, 36), chipCf * CFrame.new(0, 3.7, 0), C.Bg, Enum.Material.Glass)
		Props.Label(die, "NPU", style.Primary, Enum.NormalId.Top, Enum.Font.GothamBlack)
		return model
	end)

	-- Cerveau holographique (lobes en champ de force, sillons néon), projeté par la puce.
	-- Deux hémisphères allongés d'avant en arrière (Z), cervelet à l'arrière ; K = échelle.
	local brain = Vector3.new(0, base + 56, 0)
	local K = 1.6
	local holo = Build.Model("Brain", decor)
	Build.Neon({
		Name = "Projection",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(brain.Y - 14 - (base + 5), 16, 16),
		CFrame = CFrame.new(0, (brain.Y - 14 + base + 5) / 2, 0) * VERTICAL,
		Color = style.Primary,
		Transparency = 0.82,
		Parent = holo,
	})
	for _, lobe in
		{
			{ X = -5, Y = 2, Z = -6, D = 15 },
			{ X = 5, Y = 2, Z = -6, D = 15 },
			{ X = -6, Y = 3, Z = 3, D = 16 },
			{ X = 6, Y = 3, Z = 3, D = 16 },
			{ X = -5, Y = -2, Z = 10, D = 12 },
			{ X = 5, Y = -2, Z = 10, D = 12 },
			{ X = -8, Y = -4, Z = -2, D = 11 },
			{ X = 8, Y = -4, Z = -2, D = 11 },
			{ X = -4, Y = 0, Z = -12, D = 10 },
			{ X = 4, Y = 0, Z = -12, D = 10 },
		}
	do
		Build.Decor({
			Name = "Lobe",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * lobe.D * K,
			CFrame = CFrame.new(brain + Vector3.new(lobe.X, lobe.Y, lobe.Z) * K),
			Color = style.Primary,
			Material = Enum.Material.ForceField,
			CastShadow = false,
			Parent = holo,
		})
	end
	Build.Decor({
		Name = "Cerebellum",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 8 * K,
		CFrame = CFrame.new(brain + Vector3.new(0, -7, 13) * K),
		Color = VIOLET,
		Material = Enum.Material.ForceField,
		CastShadow = false,
		Parent = holo,
	})
	-- Sillons (néon) sur les deux hémisphères + scissure au milieu
	for k = 0, 7 do
		local side = if k % 2 == 0 then -1 else 1
		local z = -12 + math.floor(k / 2) * 7
		local a = brain + Vector3.new(side * 2, 10, z) * K
		local b = brain + Vector3.new(side * 11, 2, z + 3) * K
		Build.Neon({
			Name = "Sulcus",
			Size = Vector3.new((b - a).Magnitude, 0.5, 0.5),
			CFrame = Props.Along(a, b),
			Color = VIOLET,
			Transparency = 0.15,
			Parent = holo,
		})
	end
	Build.Neon({
		Name = "Fissure",
		Size = Vector3.new(0.6, 0.6, 30 * K),
		CFrame = CFrame.new(brain + Vector3.new(0, 11, 0) * K),
		Color = HOLO,
		Transparency = 0.2,
		Parent = holo,
	})
	-- Cœur : glitch magenta tant que LAGZ tient la puce, cyan une fois nettoyé
	local coreInfected = Build.Neon({
		Name = "CoreGlitch",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 10,
		CFrame = CFrame.new(brain),
		Color = GLITCH,
		Transparency = 0.2,
		Parent = holo,
	})
	ctx.Infected(coreInfected)
	local coreClean = Build.Neon({
		Name = "CoreClean",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 10,
		CFrame = CFrame.new(brain),
		Color = SAFE,
		Transparency = 0.1,
		Parent = holo,
	})
	ctx.Cleaned(coreClean)
	for k = 0, 7 do
		local angle = k * math.pi / 4
		local cube = Box(
			holo,
			"GlitchCube",
			Vector3.one * (1.6 + (k % 3) * 0.8),
			CFrame.new(brain + Vector3.new(math.cos(angle) * 30, (k % 3) * 7 - 7, math.sin(angle) * 30))
				* CFrame.Angles(k, k * 0.7, 0),
			if k % 2 == 0 then GLITCH else C.Black,
			NEON
		)
		ctx.Infected(cube)
	end
	-- Anneaux orbitaux (tournent côté client)
	for i, spec in { { Tilt = 18, Radius = 34, Speed = 0.4 }, { Tilt = -30, Radius = 40, Speed = -0.25 } } do
		local hubCf = CFrame.new(brain) * CFrame.Angles(math.rad(spec.Tilt), math.rad(i * 50), 0)
		local hub = Props.SpinHub(holo, hubCf, "Y", spec.Speed)
		for _, part in
			Props.Ring(
				holo,
				"Orbit",
				hubCf * CFrame.Angles(0, 0, math.pi / 2),
				spec.Radius,
				0.8,
				0.6,
				18,
				if i == 1 then VIOLET else style.Primary,
				NEON
			)
		do
			part.Transparency = 0.3
			Props.WeldTo(hub, part)
		end
	end
	-- Synapses : faisceaux du cerveau vers le parcours (sous les plateformes)
	for _, target in
		{
			Vector3.new(71, base + 4, 54),
			Vector3.new(71, base + 8, -24),
			Vector3.new(71, base + 15, -92),
			Vector3.new(0, base + 26, -92),
			Vector3.new(-83, base + 32, -88),
			Vector3.new(-101, base + 36, -44),
			Vector3.new(-83, base + 42, 2),
		}
	do
		local from = brain + (target - brain).Unit * 26
		Build.Neon({
			Name = "Synapse",
			Size = Vector3.new((target - from).Magnitude, 0.35, 0.35),
			CFrame = Props.Along(from, target),
			Color = VIOLET,
			Transparency = 0.45,
			Parent = holo,
		})
	end
	ctx.Lamp(brain, style.Primary, 1.4, 60)

	-- Pubs de LAGZ qui flottent dans la tour (infecté)
	popup(Vector3.new(34, base + 30, 44), math.rad(200))
	popup(Vector3.new(-40, base + 54, -44), math.rad(40))
	popup(Vector3.new(44, base + 70, -52), math.rad(-30))

	--------------------------------------------------------------------------------
	-- Étape 31 · Axones : virus en travers des ponts, paquets de données (Mover)
	--------------------------------------------------------------------------------

	local y = base + 10 -- 610 : toit de la salle d'arrivée
	neuron(31, 64, 78, 82, 94, y)
	slab(31, 68, 74, 62, 82, y, "Axon")
	Arena.Virus(ctx, ctx.Stage(31), Vector3.new(56, y + 2, 72), "0,0,0;30,0,0", 9, 0)
	neuron(31, 65, 77, 48, 60, y + 2)
	mover(31, 67, 75, 36, 44, y + 2, Vector3.new(0, 0, -16), 6, 0, "DataPacket")
	neuron(31, 65, 77, 6, 18, y + 3)
	slab(31, 68, 74, -16, 6, y + 4, "Axon")
	Arena.Virus(ctx, ctx.Stage(31), Vector3.new(84, y + 6, -5), "0,0,0;-30,0,0", 10, 0.5)
	neuron(31, 65, 77, -30, -18, y + 6)
	slab(31, 67, 75, -38, -32, y + 8.5, "Step")
	for _, p in
		{
			Vector3.new(71, y + 2.5, 88),
			Vector3.new(71, y + 4.5, 54),
			Vector3.new(71, y + 5.5, 12),
			Vector3.new(71, y + 8.5, -24),
			Vector3.new(71, y + 11, -35),
		}
	do
		ctx.Coin(p, 31)
	end
	-- Clé 1 : un paquet vers une île côté vitre, balayée par un rideau laser
	mover(31, 81, 89, 8, 16, y + 3, Vector3.new(20, 0, 0), 6.4, 0.3, "DataPacket")
	neuron(31, 111, 121, 6, 18, y + 5)
	laser(31, Vector3.new(0.6, 9, 0.6), CFrame.new(116, y + 9.5, 3), Vector3.new(0, 0, 18), 3.6, 0)
	ctx.UsbKey(Vector3.new(116, y + 7.5, 12), 1)
	ctx.Checkpoint(31, Common.Facing(Vector3.new(71, y + 11, -46), Vector3.new(0, 0, -1)))

	--------------------------------------------------------------------------------
	-- Étape 32 · Bus réseau : pare-feu mobiles (trouver le trou, changer de voie)
	--------------------------------------------------------------------------------

	y = base + 21 -- 621
	slab(32, 65, 77, -86, -52, y, "Bus")
	slab(32, 65, 77, -98, -86, y, "BusCorner")
	slab(32, 18, 65, -98, -86, y, "Bus")
	slab(32, 11, 17, -97, -87, y + 3, "Step")
	slab(32, 4, 10, -97, -87, y + 6.5, "Step")
	slab(32, -3, 3, -97, -87, y + 10, "Step")
	slab(32, -44, -4, -98, -86, y + 11, "Bus")
	firewall(32, Vector3.new(71, y, -62), false, Vector3.new(0, 0, -14), 5.6, 0, "3,-1.5,5,7")
	firewall(32, Vector3.new(56, y, -92), true, Vector3.new(-12, 0, 0), 5.6, 0.2, "-3,-1.5,5,7")
	firewall(32, Vector3.new(36, y, -92), true, Vector3.new(-12, 0, 0), 5.6, 0.7, "3,-1.5,5,7")
	firewall(32, Vector3.new(-10, y + 11, -92), true, Vector3.new(-10, 0, 0), 5, 0, "0,-1.5,5,7")
	firewall(32, Vector3.new(-28, y + 11, -92), true, Vector3.new(-10, 0, 0), 5, 0.45, "-3.5,-1.5,4.6,7;3.5,-1.5,4.6,7")
	-- Bande de données sous le bus (décor)
	for _, seg in { { 71, -69, 0.6, 34 }, { 41.5, -92, 47, 0.6 }, { -24, -92, 40, 0.6 } } do
		Box(decor, "BusLane", Vector3.new(seg[3], 0.3, seg[4]), CFrame.new(seg[1], y - 2.2, seg[2]), VIOLET, NEON)
	end
	for _, p in
		{
			Vector3.new(71, y + 1.5, -70),
			Vector3.new(71, y + 1.5, -92),
			Vector3.new(40, y + 1.5, -92),
			Vector3.new(7, y + 8, -92),
			Vector3.new(-24, y + 12.5, -92),
		}
	do
		ctx.Coin(p, 32)
	end
	-- Clé 2 : trois marches étroites au-dessus du coin, un virus patrouille sur la 2ᵉ
	slab(32, 69, 73, -105.5, -101.5, y + 3, "Ledge")
	slab(32, 69, 73, -113, -109, y + 6.5, "Ledge")
	slab(32, 69, 73, -120.5, -116.5, y + 10, "Ledge")
	Arena.Virus(ctx, ctx.Stage(32), Vector3.new(60, y + 8.5, -111), "0,0,0;22,0,0", 8, 0)
	ctx.UsbKey(Vector3.new(71, y + 12.5, -118.5), 2)
	ctx.Lamp(Vector3.new(24, y + 22, -92), style.Primary:Lerp(C.White, 0.3), 1.2, 60)
	ctx.Checkpoint(32, Common.Facing(Vector3.new(-50, y + 13, -92), Vector3.new(-1, 0, 0)))

	--------------------------------------------------------------------------------
	-- Étape 33 · Bureau de LAGZ : fenêtres et barre des tâches sous le curseur géant
	--------------------------------------------------------------------------------

	y = base + 34 -- 634 (pad 32)
	window(-72, -60, -98, -86, y + 2, true)
	window(-89, -77, -94, -82, y + 4, true)
	window(-104, -92, -78, -66, y + 6, false)
	slab(33, -104, -98, -64, -24, y + 8, "Taskbar").Color = Color3.fromRGB(58, 48, 92)
	Box(decor, "StartButton", Vector3.new(3.6, 0.25, 3.6), CFrame.new(-101, y + 8.1, -61), VIOLET, NEON)
	for k = 1, 3 do
		Box(decor, "TaskIcon", Vector3.new(2.4, 0.25, 2.4), CFrame.new(-101, y + 8.1, -56 + k * 8), HOLO, NEON)
	end
	window(-108, -96, -20, -8, y + 11, false)
	cursor(33, Vector3.new(-82, y + 6, -84), Vector3.new(50, 20, 40), 3.4)
	cursor(33, Vector3.new(-101, y + 10, -36), Vector3.new(26, 20, 58), 3)
	for _, p in
		{
			Vector3.new(-66, y + 3.5, -92),
			Vector3.new(-83, y + 5.5, -88),
			Vector3.new(-98, y + 7.5, -72),
			Vector3.new(-101, y + 9.5, -40),
			Vector3.new(-102, y + 12.5, -14),
		}
	do
		ctx.Coin(p, 33)
	end
	popup(Vector3.new(-116, y + 14, -40), math.rad(90))
	ctx.Lamp(Vector3.new(-96, y + 26, -60), HOLO, 1.2, 60)
	ctx.Checkpoint(33, Common.Facing(Vector3.new(-102, y + 14, 2), Vector3.new(1, 0, 0)))

	--------------------------------------------------------------------------------
	-- Étape 34 · Couche cachée : lasers, ascenseurs, neurones alimentés (BLACKOUT)
	--------------------------------------------------------------------------------

	y = base + 48 -- 648 (pad 33)
	slab(34, -96, -70, -4, 8, y, "HiddenLayer")
	laser(34, Vector3.new(0.6, 0.6, 12.6), CFrame.new(-92, y + 1, 2), Vector3.new(18, 0, 0), 4, 0)
	laser(34, Vector3.new(0.6, 9, 0.6), CFrame.new(-80, y + 4.5, -3.4), Vector3.new(0, 0, 10.8), 3.4, 0.5)
	mover(34, -68, -60, -2, 6, y, Vector3.new(0, 14, 0), 7, 0, "Elevator")
	powered(34, -56, -50, -1, 5, y + 15, 0)
	powered(34, -46, -40, -1, 5, y + 16.5, 0.2)
	powered(34, -36, -30, -1, 5, y + 18, 0.4)
	mover(34, -34, -26, 9, 17, y + 18, Vector3.new(0, 12, 0), 7, 0.5, "Elevator")
	slab(34, -41.5, -35.5, 16, 28, y + 32, "Landing")
	for _, p in
		{
			Vector3.new(-84, y + 1.5, 6),
			Vector3.new(-64, y + 2, 2),
			Vector3.new(-53, y + 16.5, 2),
			Vector3.new(-33, y + 19.5, 2),
			Vector3.new(-38.5, y + 33.5, 22),
		}
	do
		ctx.Coin(p, 34)
	end
	-- Clé 3 : dans le halo du cerveau, trois éclats de mémoire gardés par un virus
	slab(34, -24, -21, -2, 1, y + 19, "Shard")
	slab(34, -17, -14, -8, -5, y + 20.5, "Shard")
	slab(34, -10, -6, -14, -10, y + 22, "Shard")
	Arena.Virus(ctx, ctx.Stage(34), Vector3.new(-22, y + 24, -12), "0,0,0;16,0,0", 7, 0)
	ctx.UsbKey(Vector3.new(-8, y + 24.5, -12), 3)
	ctx.Checkpoint(34, Common.Facing(Arena.EntryPad, Vector3.new(0, 0, 1)))

	--------------------------------------------------------------------------------
	-- Étape 35 · l'arène de LAGZ, puis la salle du terminal final (et l'arrivée sur le toit)
	--------------------------------------------------------------------------------

	Arena.Build(ctx)
	ctx.TerminalRoom()
end
