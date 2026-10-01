--!strict
--[[
	Monde 1 : Alimentation (le bloc d'alimentation) — « Le PC s'éteint tout seul ».

	Tout le monde est une CENTRALE ÉLECTRIQUE miniature : au centre, le bloc d'alimentation géant
	(le « réacteur »), autour, les câbles tressés qui en sortent (lignes à haute tension), une forêt
	de condensateurs (silos), des dissipateurs alu (pylônes) reliés par des rails 12 V, et sur le
	toit du bloc, la grille de son ventilateur (tour de refroidissement). On en fait le tour en
	montant, dans le sens des aiguilles d'une montre vu de dessus :

	  Étape 1 (couloir gauche, sud)  CÂBLES TRESSÉS : on court SUR les câbles ; des impulsions (Surge)
	                                 remontent le câble vers nous : on saute par-dessus.
	  Étape 2 (couloir gauche, nord) CONDENSATEURS : on saute de condensateur en condensateur, un
	                                 couloir de décharges (Zapper), puis un condensateur-trampoline
	                                 (Bounce) propulse sur le grand condensateur du checkpoint.
	  Étape 3 (couloir du fond)      RAILS 12 V : plateformes alimentées (Powered) qui ne sont solides
	                                 que quand le courant passe, entre des dissipateurs sûrs. En
	                                 BLACKOUT elles disparaissent : on attend sur un dissipateur.
	  Étape 4 (toit du bloc)         GRILLE DU VENTILATEUR : on traverse la grille (anneaux + rayons)
	                                 au-dessus du ventilateur qui tourne ; un arc électrique balaie la
	                                 grille (SpinBar) : on saute par-dessus. Puis les selfs en marches.
	  Étape 5 (couloir droit)        FINALE : câble + impulsion, rails alimentés, trampoline, porte
	                                 gardée par deux décharges, puis la salle du terminal (Sparky).

	Clés USB (chemins facultatifs difficiles) :
	  1. étape 2 : trampoline caché contre le mur → câble fin en hauteur parcouru par une impulsion ;
	  2. étape 3 : rails alimentés à fenêtre courte derrière les dissipateurs ;
	  3. étape 5 : câble fin vers la vitre, impulsion rapide.

	Décor : vrais modèles (`Psu`, `Fan140`, `CapacitorBig`, `Capacitor`, `ChokeRow`, `Choke`,
	`CableBraided24`, `CableSleeved8`, `Sparky`) avec décor de secours en primitives. Le gameplay ne
	dépend d'aucun modèle (plateformes, câbles et pièges sont des pièces primitives).
	Infecté : alertes rouges, flaques de glitch, pubs flottantes, voyants « ERROR ».
	Nettoyé : liserés orange qui brillent, « 80 PLUS GOLD » allumé, voyants « POWER OK ».
]]

local Build = require(script.Parent.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Parent.Props)
local ModelLibrary = require(script.Parent.Parent.Parent.ModelLibrary)
local Common = require(script.Parent.Parent.Common)

local C = Common.C
local UP = Common.UP
local VERTICAL = Common.VERTICAL
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local FABRIC = Enum.Material.Fabric

local LETHAL = Common.Colors.Lethal
local GLITCH = Common.Colors.Glitch
local SPRING = Common.Colors.Spring
local SAFE = Common.Colors.Safe

local ORANGE = Color3.fromHex("F6AD55") -- identité du monde
local AMBER = Color3.fromRGB(255, 214, 120)
local POWER = Color3.fromRGB(255, 186, 84) -- rail alimenté (allumé)
local SURGE = Color3.fromRGB(255, 70, 120) -- impulsion (mortelle : rouge / magenta)
local ALERT = Color3.fromRGB(255, 58, 58)
local BRAID = Color3.fromRGB(38, 34, 40)
local CAP_BODY = Color3.fromRGB(30, 34, 50)
local FLOOR_Y = 2 -- sol du monde (au-dessus du vide mortel)

local function frac(x: number): number
	return x - math.floor(x)
end

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

	-- Plateforme sûre alignée sur les axes, dessus à `top` ; liserés sur les grands côtés.
	local function deck(
		folder: Instance,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		name: string?,
		thick: number?
	): Part
		local h = thick or 2
		local sx, sz = x1 - x0, z1 - z0
		local center = V((x0 + x1) / 2, top - h / 2, (z0 + z1) / 2)
		if sx > sz then
			return ctx.Platform(
				folder,
				Vector3.new(sz, h, sx),
				CFrame.new(center) * CFrame.Angles(0, math.pi / 2, 0),
				name
			)
		end
		return ctx.Platform(folder, Vector3.new(sx, h, sz), CFrame.new(center), name)
	end

	-- Bloc solide (collidable) aux couleurs données.
	local function solid(
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
			Material = material or SMOOTH,
			Parent = parent,
		})
	end

	-- Câble tressé praticable : segments horizontaux (cylindres) + rotules, dessus à `top`.
	-- `points` = { {x, z}, ... } ; manchons orange tous les ~11 studs, filet lumineux sur le dessus.
	local function cable(folder: Instance, points: { { number } }, d: number, top: number, color: Color3?)
		local y = top - d / 2
		for i = 1, #points - 1 do
			local a = V(points[i][1], y, points[i][2])
			local b = V(points[i + 1][1], y, points[i + 1][2])
			local dir = (b - a).Unit
			local len = (b - a).Magnitude
			local cf = CFrame.fromMatrix((a + b) / 2, dir, UP)
			local segment = Build.Part({
				Name = "BraidedCable",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(len, d, d),
				CFrame = cf,
				Color = color or BRAID,
				Material = FABRIC,
				Parent = folder,
			})
			segment.CastShadow = true
			Build.Neon({
				Name = "LiveWire",
				Size = Vector3.new(len, 0.12, 0.45),
				CFrame = cf * CFrame.new(0, d / 2 + 0.02, 0),
				Color = ORANGE,
				Transparency = 0.35,
				Parent = folder,
			})
			local rings = math.floor(len / 11)
			for k = 1, rings do
				Rod(
					folder,
					"Sleeve",
					cf * CFrame.new(-len / 2 + len * k / (rings + 1), 0, 0),
					0.9,
					d + 0.35,
					ORANGE,
					METAL
				)
			end
			if i < #points - 1 then
				Build.Part({
					Name = "CableJoint",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * d,
					CFrame = CFrame.new(b),
					Color = color or BRAID,
					Material = FABRIC,
					Parent = folder,
				})
			end
		end
	end

	-- Serre-câble (peigne) : bloc sûr noir sanglé d'orange, dessus à `top`.
	local function clamp(folder: Instance, x0: number, x1: number, z0: number, z1: number, top: number): Part
		local sx, sz = x1 - x0, z1 - z0
		local body = solid(
			folder,
			"CableComb",
			Vector3.new(sx, 4, sz),
			CFrame.new(V((x0 + x1) / 2, top - 2, (z0 + z1) / 2)),
			C.MetalDark,
			METAL
		)
		local long = if sx > sz then Vector3.new(sx + 0.3, 1, 1.2) else Vector3.new(1.2, 1, sz + 0.3)
		for _, k in { -0.3, 0.3 } do
			local offset = if sx > sz then Vector3.new(0, 0, k * sz) else Vector3.new(k * sx, 0, 0)
			Box(folder, "Strap", long, CFrame.new(V((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2) + offset), ORANGE)
		end
		return body
	end

	-- Impulsion électrique (Surge) : boule mortelle + étincelles soudées, qui court le long d'un
	-- câble depuis `from` (repos, là où elle se charge) en suivant `path` (points du monde).
	local function surge(
		folder: Instance,
		from: Vector3,
		path: { Vector3 },
		speed: number,
		quiet: number,
		phase: number
	)
		local rest = from + Vector3.new(0, 1.2, 0)
		local ball = Build.Part({
			Name = "Surge",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.4,
			CFrame = CFrame.new(rest),
			Color = SURGE,
			Material = NEON,
			CastShadow = false,
			Parent = folder,
		})
		ball.CanCollide = false
		ball.CanQuery = false
		local chunks = { "0,0,0" }
		local length, last = 0, from
		for _, p in path do
			local d = p - from
			table.insert(chunks, string.format("%.2f,%.2f,%.2f", d.X, d.Y, d.Z))
			length += (p - last).Magnitude
			last = p
		end
		ctx.Trap("Surge", ball, {
			Waypoints = table.concat(chunks, ";"),
			Speed = speed,
			Period = 0.8 + length / speed + quiet,
			Phase = phase,
		})
		for k = 0, 2 do
			Common.Attach(
				ball,
				"Spark",
				Vector3.new(3.4, 0.22, 0.22),
				CFrame.new(rest) * CFrame.Angles(0, k * math.pi / 3, math.rad(12)),
				SURGE,
				NEON
			)
		end
		return ball
	end

	-- Condensateur praticable : corps cylindrique solide + dessus alu gravé ; une dalle invisible
	-- inscrite dans le disque sert de sol (dessus à `top`).
	local function capacitor(folder: Instance, x: number, z: number, d: number, top: number, glow: Color3?): Part
		local h = top - FLOOR_Y
		local center = V(x, FLOOR_Y + h / 2, z)
		Build.Part({
			Name = "Capacitor",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, d, d),
			CFrame = CFrame.new(center) * VERTICAL,
			Color = CAP_BODY,
			Material = SMOOTH,
			Parent = folder,
		})
		local side = d * 0.7
		local top3 = V(x, top, z)
		local slab = Build.Part({
			Name = "CapDeck",
			Size = Vector3.new(side, 1, side),
			CFrame = CFrame.new(top3 - Vector3.new(0, 0.5, 0)),
			Color = C.Aluminum,
			Transparency = 1,
			CastShadow = false,
			Parent = folder,
		})
		Rod(folder, "CapTop", CFrame.new(top3 - Vector3.new(0, 0.12, 0)) * VERTICAL, 0.3, d - 0.3, C.Aluminum)
		for _, angle in { 0, math.pi / 2 } do
			Box(
				folder,
				"CapVent",
				Vector3.new(d * 0.62, 0.1, 0.35),
				CFrame.new(top3 + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, angle + math.pi / 4, 0),
				C.MetalDark
			)
		end
		Build.Neon({
			Name = "CapCollar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, d + 0.3, d + 0.3),
			CFrame = CFrame.new(top3 - Vector3.new(0, 1.4, 0)) * VERTICAL,
			Color = glow or ORANGE,
			Transparency = 0.35,
			Parent = folder,
		})
		Box(
			folder,
			"CapStripe",
			Vector3.new(0.2, h - 2.5, d * 0.28),
			CFrame.new(V(x - d / 2 - 0.02, FLOOR_Y + (h - 2.5) / 2, z)),
			C.Silk
		)
		return slab
	end

	-- Condensateur-trampoline : le dessus est un pad Bounce (Power 80) vert.
	local function bounceCap(folder: Instance, x: number, z: number, d: number, top: number): Part
		capacitor(folder, x, z, d, top, SPRING)
		local s = d * 0.62
		local cf = CFrame.new(V(x, top + 0.4, z))
		local pad = Build.Part({
			Name = "BouncePad",
			Size = Vector3.new(s, 0.8, s),
			CFrame = cf,
			Color = SPRING,
			Material = SMOOTH,
			CastShadow = false,
			Parent = folder,
		})
		ctx.Trap("Bounce", pad, { Power = 80 })
		Common.Attach(pad, "PadGlow", Vector3.new(s - 1, 0.2, s - 1), cf * CFrame.new(0, 0.45, 0), SPRING, NEON).Transparency =
			0.2
		return pad
	end

	-- Décharge (Zapper) : arc vertical entre deux bornes, mortel pendant Duty.
	local function zapper(
		folder: Instance,
		a: Vector3,
		b: Vector3,
		y0: number,
		height: number,
		period: number,
		phase: number
	)
		local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local len = dir.Magnitude
		local mid = (a + b) / 2
		local arc = Build.Part({
			Name = "Arc",
			Size = Vector3.new(len, height, 0.6),
			CFrame = CFrame.fromMatrix(Vector3.new(mid.X, B + y0 + height / 2, mid.Z), dir.Unit, UP),
			Color = LETHAL,
			Material = NEON,
			Transparency = 0.3,
			CastShadow = false,
			Parent = folder,
		})
		arc.CanCollide = false
		arc.CanQuery = false
		ctx.Trap("Zapper", arc, { Period = period, Duty = 0.4, Phase = phase })
		-- Bornes (petits condensateurs) de part et d'autre
		for _, p in { a, b } do
			Rod(
				decor,
				"ZapPost",
				CFrame.new(Vector3.new(p.X, B + y0 + height / 2 - 1, p.Z)) * VERTICAL,
				height + 2,
				2.4,
				C.Black
			)
			Build.Neon({
				Name = "ZapTip",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 2.6,
				CFrame = CFrame.new(Vector3.new(p.X, B + y0 + height + 0.6, p.Z)),
				Color = LETHAL,
				Transparency = 0.15,
				Parent = decor,
			})
		end
		return arc
	end

	-- Rail 12 V alimenté (Powered) : solide seulement quand le courant passe (clignote avant la
	-- coupure), absent en BLACKOUT. Bornes cuivre aux deux bouts (elles s'éteignent avec lui).
	local function powered(
		folder: Instance,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		top: number,
		period: number,
		duty: number,
		phase: number
	): Part
		local sx, sz = x1 - x0, z1 - z0
		local cf = CFrame.new(V((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2))
		local rail = Build.Part({
			Name = "Rail12V",
			Size = Vector3.new(sx, 1.2, sz),
			CFrame = cf,
			Color = POWER,
			Material = NEON,
			CastShadow = false,
			Parent = folder,
		})
		rail.Transparency = 0.1
		ctx.Trap("Powered", rail, { Period = period, Duty = duty, Phase = frac(phase) })
		local along = if sx > sz then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
		local long = if sx > sz then sx else sz
		for _, s in { -1, 1 } do
			Box(
				rail,
				"Terminal",
				if sx > sz then Vector3.new(1.2, 1.5, sz + 0.2) else Vector3.new(sx + 0.2, 1.5, 1.2),
				cf + along * s * (long / 2 - 0.6),
				C.Copper,
				METAL
			)
		end
		return rail
	end

	-- Dissipateur alu (île sûre des rails) : plateau + ailettes jusqu'au sol.
	local function heatsink(folder: Instance, x0: number, x1: number, z0: number, z1: number, top: number): Part
		local plate = deck(folder, x0, x1, z0, z1, top, "HeatsinkTop")
		local h = top - 2 - FLOOR_Y
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		Box(
			decor,
			"HeatsinkCore",
			Vector3.new(x1 - x0 - 4, h, z1 - z0 - 4),
			CFrame.new(V(cx, FLOOR_Y + h / 2, cz)),
			C.MetalDark,
			METAL
		)
		for k = -2, 2 do
			Box(
				decor,
				"Fin",
				Vector3.new(0.5, h - 1, z1 - z0 - 1),
				CFrame.new(V(cx + k * (x1 - x0 - 1.5) / 4, FLOOR_Y + (h - 1) / 2, cz)),
				C.Aluminum,
				METAL
			)
		end
		return plate
	end

	-- Self (bobine) praticable : noyau noir, bobinage cuivre, dessus sûr.
	local function choke(folder: Instance, x0: number, x1: number, z0: number, z1: number, top: number): Part
		local plate = deck(folder, x0, x1, z0, z1, top, "ChokeTop")
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		local h = top - 2 - FLOOR_Y
		Box(
			decor,
			"ChokeCore",
			Vector3.new(x1 - x0 - 1, h, z1 - z0 - 1),
			CFrame.new(V(cx, FLOOR_Y + h / 2, cz)),
			C.Black
		)
		for k = 1, 3 do
			Rod(
				decor,
				"Winding",
				CFrame.new(V(cx, top - 2 - k * 2.2, cz)) * VERTICAL,
				1.2,
				math.max(x1 - x0, z1 - z0) + 0.8,
				C.Copper,
				METAL
			)
		end
		return plate
	end

	local function spinBar(folder: Instance, center: Vector3, length: number, speed: number, phase: number): Part
		local blade = Build.Part({
			Name = "ArcSweeper",
			Size = Vector3.new(length, 1.2, 1.2),
			CFrame = CFrame.new(center),
			Color = LETHAL,
			Material = NEON,
			CastShadow = false,
			Parent = folder,
		})
		blade.CanCollide = false
		blade.CanQuery = false
		ctx.Trap("SpinBar", blade, { Speed = speed, Axis = "Y", Phase = phase })
		return blade
	end

	local function checkpoint(stage: number, x: number, top: number, z: number, look: Vector3)
		ctx.Checkpoint(stage, Common.Facing(V(x, top, z), look))
	end

	local function coin(x: number, y: number, z: number)
		ctx.Coin(V(x, y, z))
	end

	------------------------------------------------------------------------------------
	-- Décor : pièces du thème (modèles 3D, avec décor de secours en primitives)
	------------------------------------------------------------------------------------

	-- Condensateur de décor (sans collision). Modèles `Capacitor` / `CapacitorBig`.
	local function decorCap(x: number, z: number, d: number, h: number, big: boolean?)
		local key = if big then "CapacitorBig" else "Capacitor"
		ModelLibrary.Place(
			key,
			CFrame.new(V(x, FLOOR_Y, z)),
			decor,
			{ Fit = Vector3.new(d, h, d) },
			function(): Instance?
				local model = Build.Model(key, decor)
				Props.Capacitor(model, V(x, FLOOR_Y, z), d / 2, h, CAP_BODY, ORANGE)
				return model
			end
		)
	end

	-- Rangée de selfs de décor (modèle `ChokeRow`, alignée sur X).
	local function decorChokes(cf: CFrame, count: number, size: number)
		local fit = Vector3.new(count * size * 1.3, size * 1.2, size * 2)
		ModelLibrary.Place("ChokeRow", cf, decor, { Fit = fit }, function(): Instance?
			local model = Build.Model("ChokeRow", decor)
			for i = 1, count do
				local p = cf * CFrame.new((i - (count + 1) / 2) * size * 1.3, size / 2, 0)
				Box(model, "ChokeCore", Vector3.new(size, size, size), p, C.Black)
				Rod(model, "Winding", p * VERTICAL, size * 0.5, size + 0.6, C.Copper, METAL)
				Box(
					model,
					"ChokeCap",
					Vector3.new(size + 0.2, 0.4, size + 0.2),
					p * CFrame.new(0, size / 2, 0),
					C.MetalDark
				)
			end
			return model
		end)
	end

	-- Bloc d'alimentation géant (le « réacteur » de la centrale) : caisson sans dessus (le toit est
	-- la grille praticable de l'étape 4), panneau modulaire, étiquette, interrupteur.
	local function psuFallback(): Instance?
		local model = Build.Model("Psu", decor)
		local half, h = 50, 46
		local wall = C.Black:Lerp(C.MetalDark, 0.35)
		-- Parois (décor pur : on ne les touche jamais, on tombe dans le vide si on rate la grille)
		for _, side in { -1, 1 } do
			Box(
				model,
				"SidePanel",
				Vector3.new(2, h, half * 2),
				CFrame.new(V(side * (half - 1), FLOOR_Y + h / 2, 0)),
				wall,
				METAL
			)
			Box(
				model,
				"EndPanel",
				Vector3.new(half * 2, h, 2),
				CFrame.new(V(0, FLOOR_Y + h / 2, side * (half - 1))),
				wall,
				METAL
			)
		end
		-- Cadre du dessus + arêtes
		for _, side in { -1, 1 } do
			Box(
				model,
				"TopFrame",
				Vector3.new(4, 2, half * 2),
				CFrame.new(V(side * (half - 2), 47, 0)),
				C.MetalDark,
				METAL
			)
			Box(
				model,
				"TopFrame",
				Vector3.new(half * 2, 2, 4),
				CFrame.new(V(0, 47, side * (half - 2))),
				C.MetalDark,
				METAL
			)
			for _, other in { -1, 1 } do
				Box(
					model,
					"Edge",
					Vector3.new(1.6, h + 1, 1.6),
					CFrame.new(V(side * half, FLOOR_Y + h / 2, other * half)),
					C.MetalLight,
					METAL
				)
			end
		end
		-- Liserés orange en haut de chaque face (s'allument franchement une fois nettoyé)
		for _, side in { -1, 1 } do
			Build.Neon({
				Name = "Trim",
				Size = Vector3.new(0.5, 0.6, half * 2),
				CFrame = CFrame.new(V(side * (half + 0.1), 45.5, 0)),
				Color = ORANGE:Lerp(C.Black, 0.45),
				Parent = model,
			})
			Build.Neon({
				Name = "Trim",
				Size = Vector3.new(half * 2, 0.6, 0.5),
				CFrame = CFrame.new(V(0, 45.5, side * (half + 0.1))),
				Color = ORANGE:Lerp(C.Black, 0.45),
				Parent = model,
			})
		end
		-- Étiquette de certification (côté gauche, visible depuis les condensateurs)
		local label = Box(
			model,
			"Certification",
			Vector3.new(40, 18, 0.3),
			Common.Facing(V(-half - 0.3, 26, 8), -Vector3.xAxis),
			C.Bg
		)
		Props.Sign(label, "ANGA POWER 1200W", "Bloc d'alimentation · 12 V", AMBER, C.Silk)
		-- Panneau modulaire (face avant, vers -Z) : prises d'où partent les câbles tressés
		for row = 0, 1 do
			for col = 0, 3 do
				local p = V(-30 + col * 12, 14 + row * 10, -half - 0.8)
				Box(model, "Socket", Vector3.new(9, 6, 1.2), CFrame.new(p), C.Rubber)
				Build.Neon({
					Name = "SocketGlow",
					Size = Vector3.new(7, 0.5, 0.4),
					CFrame = CFrame.new(p + Vector3.new(0, -2.4, -0.5)),
					Color = AMBER,
					Transparency = 0.3,
					Parent = model,
				})
			end
		end
		-- Fentes d'aération sur les côtés droit et arrière, logo sur le côté droit (vers l'étape 5)
		for k = 0, 5 do
			Box(model, "Vent", Vector3.new(0.4, 1.6, 44), CFrame.new(V(half + 0.2, 8 + k * 4, -18)), C.Bg)
			Box(model, "Vent", Vector3.new(36, 1.6, 0.4), CFrame.new(V(22, 8 + k * 4, half + 0.2)), C.Bg)
		end
		Props.Decal(
			model,
			"Logo",
			Vector3.new(34, 12, 0.2),
			Common.Facing(V(half + 0.3, 34, 14), Vector3.xAxis),
			"ANGA",
			ORANGE,
			Enum.NormalId.Front,
			Enum.Font.GothamBlack
		)
		-- Face arrière (vers le checkpoint 3) : prise secteur et interrupteur I/O
		Box(model, "AcInlet", Vector3.new(12, 9, 1.2), CFrame.new(V(-20, 30, half + 0.6)), C.Rubber)
		Box(model, "Switch", Vector3.new(6, 8, 1.4), CFrame.new(V(-6, 30, half + 0.7)), C.Brand)
		Props.Decal(
			model,
			"SwitchLabel",
			Vector3.new(6, 3, 0.2),
			Common.Facing(V(-6, 36, half + 1.5), Vector3.zAxis),
			"I / O",
			C.White,
			Enum.NormalId.Front,
			Enum.Font.GothamBlack
		)
		return model
	end

	-- Sparky : petite étincelle jaune colérique (sbire du monde 1).
	local function sparkyFallback(cf: CFrame, parent: Instance): Instance?
		local model = Build.Model("Sparky", parent)
		local yellow = Color3.fromRGB(255, 222, 64)
		local core = Build.Neon({
			Name = "Body",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 4,
			CFrame = cf,
			Color = yellow,
			Parent = model,
		})
		core.Transparency = 0
		for k = 0, 7 do
			local angle = k * math.pi / 4
			Build.Neon({
				Name = "Spike",
				Size = Vector3.new(0.7, 2.6, 0.7),
				CFrame = cf * CFrame.Angles(0, 0, angle) * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.pi / 4, 0),
				Color = if k % 2 == 0 then yellow else ORANGE,
				Parent = model,
			})
		end
		for _, x in { -0.75, 0.75 } do
			Build.Decor({
				Name = "Eye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.9,
				CFrame = cf * CFrame.new(x, 0.35, -1.7),
				Color = C.Black,
				Material = SMOOTH,
				Parent = model,
			})
			Build.Decor({
				Name = "Brow",
				Size = Vector3.new(1.1, 0.25, 0.3),
				CFrame = cf * CFrame.new(x, 1.05, -1.75) * CFrame.Angles(0, 0, if x < 0 then -0.45 else 0.45),
				Color = C.Black,
				Material = SMOOTH,
				Parent = model,
			})
		end
		Build.Decor({
			Name = "Grin",
			Size = Vector3.new(1.4, 0.3, 0.3),
			CFrame = cf * CFrame.new(0, -0.7, -1.8),
			Color = C.Black,
			Material = SMOOTH,
			Parent = model,
		})
		-- Queue en éclair
		Build.Neon({
			Name = "Bolt",
			Size = Vector3.new(0.6, 2.4, 0.6),
			CFrame = cf * CFrame.new(0.6, -3, 0.6) * CFrame.Angles(0, 0, 0.5),
			Color = yellow,
			Parent = model,
		})
		Build.Neon({
			Name = "Bolt",
			Size = Vector3.new(0.6, 2.4, 0.6),
			CFrame = cf * CFrame.new(-0.2, -4.8, 0.6) * CFrame.Angles(0, 0, -0.5),
			Color = yellow,
			Parent = model,
		})
		return model
	end

	------------------------------------------------------------------------------------
	-- Entrée, vide, salle du terminal
	------------------------------------------------------------------------------------

	ctx.Void()
	ctx.Entrance()

	------------------------------------------------------------------------------------
	-- Étape 1 — Câbles tressés (impulsions Surge) : couloir gauche, du coin vers le nord
	------------------------------------------------------------------------------------

	local s1 = ctx.Stage(1)
	deck(s1, -80, -66, -95, -81, 10, "CableLanding")
	cable(s1, { { -73, -81 }, { -73, -46 } }, 7, 11)
	clamp(s1, -81, -65, -46, -38, 12.5)
	cable(s1, { { -73, -38 }, { -73, -2 } }, 7, 14)
	-- 1ʳᵉ impulsion : elle se charge au bout du câble (on la voit clignoter) puis fonce vers nous
	surge(s1, V(-73, 14, -3.5), { V(-73, 14, -36.5) }, 12, 2.4, 0)
	clamp(s1, -81, -65, -2, 6, 15.5)
	cable(s1, { { -81, 2 }, { -106, 2 } }, 7, 17)
	surge(s1, V(-104.5, 17, 2), { V(-82.5, 17, 2) }, 12, 2.2, 0.5)
	clamp(s1, -116, -104, -5, 9, 18.5)
	coin(-73, 13.8, -70)
	coin(-73, 13.8, -56)
	coin(-73, 16.8, -20)
	coin(-94, 19.8, 2)
	checkpoint(1, -110, 22, 20, Vector3.new(0, 0, 1))

	------------------------------------------------------------------------------------
	-- Étape 2 — Forêt de condensateurs (Zapper, Bounce) : couloir gauche, vers le fond
	------------------------------------------------------------------------------------

	local s2 = ctx.Stage(2)
	capacitor(s2, -110, 34, 10, 23)
	capacitor(s2, -99, 44, 10, 24.5)
	capacitor(s2, -110, 55, 12, 26)
	deck(s2, -116, -104, 64, 86, 26, "BusPlate")
	-- Couloir des décharges : deux arcs en alternance (fenêtre sûre 1,9 s)
	zapper(s2, V(-119, 26, 70), V(-101, 26, 70), 26, 9, 3.2, 0)
	zapper(s2, V(-119, 26, 79), V(-101, 26, 79), 26, 9, 3.2, 0.5)
	bounceCap(s2, -110, 94, 10, 26.5)
	-- Le grand condensateur du checkpoint 2
	capacitor(s2, -96, 106, 18, 35)
	coin(-99, 27.5, 44)
	coin(-110, 29, 74.5)
	coin(-110, 40, 94)
	coin(-103, 38, 101)
	checkpoint(2, -96, 36, 106, Vector3.new(1, 0, 0))

	-- Clé USB 1 : trampoline caché contre le mur, câble fin en hauteur, impulsion rapide
	bounceCap(s2, -124, 47, 8, 25)
	cable(s2, { { -126, 55 }, { -126, 92 } }, 3.5, 38)
	surge(s2, V(-126, 38, 90), { V(-126, 38, 57) }, 14, 1.8, 0.3)
	deck(s2, -130, -120, 92, 100, 39, "KeyPerch")
	ctx.UsbKey(V(-125, 41.5, 96), 1)

	------------------------------------------------------------------------------------
	-- Étape 3 — Rails 12 V (Powered) entre des dissipateurs : couloir du fond, vers l'est
	------------------------------------------------------------------------------------

	local s3 = ctx.Stage(3)
	heatsink(s3, -86, -74, 100, 112, 37)
	-- Le courant avance avec toi : chaque rail s'allume 0,4 s après le précédent (allumé 2,4 s)
	powered(s3, -70, -62, 102, 110, 38.5, 4, 0.6, 0.3)
	powered(s3, -58, -50, 102, 110, 40, 4, 0.6, 0.2)
	powered(s3, -46, -38, 102, 110, 41.5, 4, 0.6, 0.1)
	heatsink(s3, -34, -22, 100, 112, 43)
	-- Deuxième série, plus vive (allumé 2 s sur 3,6 s)
	powered(s3, -18, -10, 102, 110, 44.5, 3.6, 0.55, 0.35)
	powered(s3, -6, 2, 102, 110, 46, 3.6, 0.55, 0.2)
	heatsink(s3, 6, 18, 100, 112, 47.5)
	powered(s3, 8, 16, 88, 96, 48.5, 3.6, 0.55, 0.3)
	powered(s3, 8, 16, 76, 84, 49.5, 3.6, 0.55, 0.15)
	coin(-54, 43, 106)
	coin(-28, 45.5, 106)
	coin(-2, 48.5, 106)
	coin(12, 52, 86)
	checkpoint(3, 12, 50, 66, Vector3.new(0, 0, -1))

	-- Clé USB 2 : rails à fenêtre courte (allumés 1,3 s) derrière les dissipateurs
	powered(s3, -32, -24, 116, 122, 45, 3.6, 0.35, 0.6)
	powered(s3, -44, -36, 118, 126, 47.5, 3.6, 0.35, 0.45)
	deck(s3, -58, -48, 116, 128, 50, "KeyPerch")
	ctx.UsbKey(V(-53, 52.5, 122), 2)

	------------------------------------------------------------------------------------
	-- Étape 4 — Grille du ventilateur (SpinBar) sur le toit du bloc, puis selfs en marches
	------------------------------------------------------------------------------------

	local s4 = ctx.Stage(4)
	local GRILLE = C.Aluminum:Lerp(C.MetalLight, 0.3)
	deck(s4, 6, 18, 46, 60, 50, "RearLedge")
	-- Anneaux de la grille (segments) : dessus à 50
	local function ring(radius: number, width: number, count: number)
		local chord = 2 * (radius + width / 2) * math.tan(math.pi / count) + 0.05
		for i = 0, count - 1 do
			local theta = i * math.pi * 2 / count
			local pos = V(radius * math.cos(theta), 49.25, radius * math.sin(theta))
			local bar = solid(
				s4,
				"GrilleRing",
				Vector3.new(width, 1.5, chord),
				CFrame.new(pos) * CFrame.Angles(0, -theta, 0),
				GRILLE,
				METAL
			)
			bar.CastShadow = true
		end
	end
	ring(44, 5, 22)
	ring(27, 4, 16)
	for k = 0, 5 do
		local theta = k * math.pi / 3
		local r0, r1 = 5.5, 41.8
		local pos = V((r0 + r1) / 2 * math.cos(theta), 49.25, (r0 + r1) / 2 * math.sin(theta))
		solid(
			s4,
			"GrilleSpoke",
			Vector3.new(r1 - r0, 1.5, 4),
			CFrame.new(pos) * CFrame.Angles(0, -theta, 0),
			GRILLE,
			METAL
		)
	end
	local hub = solid(s4, "GrilleHub", Vector3.new(12, 1.5, 12), CFrame.new(V(0, 49.25, 0)), C.MetalDark, METAL)
	Props.Decal(
		decor,
		"HubLogo",
		Vector3.new(9, 0.1, 9),
		CFrame.new(V(0, 50.07, 0)),
		"ANGA",
		ORANGE,
		Enum.NormalId.Top,
		Enum.Font.GothamBlack
	)
	hub.CastShadow = true
	-- Arc électrique qui balaie toute la grille (passe partout toutes les 4,2 s)
	spinBar(s4, V(0, 51.3, 0), 94, 0.75, 0)
	deck(s4, 49, 58, -6, 6, 50, "FanExit")
	choke(s4, 60, 68, -5, 5, 53.5)
	choke(s4, 70, 80, -5, 5, 57.5)
	coin(0, 52.5, 27)
	coin(27, 52.5, 0)
	coin(-27, 52.5, 0)
	coin(64, 56.5, 0)
	checkpoint(4, 90, 62, 0, Vector3.new(0, 0, -1))

	------------------------------------------------------------------------------------
	-- Étape 5 — Finale (couloir droit) : câble + impulsion, rails, trampoline, porte gardée
	------------------------------------------------------------------------------------

	local s5 = ctx.Stage(5)
	cable(s5, { { 90, -6 }, { 90, -38 } }, 7, 63)
	surge(s5, V(90, 63, -36.5), { V(90, 63, -7.5) }, 13, 2, 0.2)
	clamp(s5, 82, 98, -46, -38, 64.5)
	powered(s5, 86, 94, -58, -50, 66, 4, 0.55, 0.25)
	powered(s5, 74, 82, -58, -50, 67.5, 4, 0.55, 0.12)
	bounceCap(s5, 64, -54, 10, 67.5)
	deck(s5, 58, 72, -78, -65, 77, "FinalLedge")
	deck(s5, 62, 80, -95, -81, 80, "DoorApproach")
	zapper(s5, V(67, 80, -96.5), V(67, 80, -79.8), 80, 9, 3.2, 0.25)
	zapper(s5, V(74, 80, -96.5), V(74, 80, -79.8), 80, 9, 3.2, 0.75)
	coin(90, 65.8, -22)
	coin(90, 69, -54)
	coin(66, 74, -60)
	coin(70.5, 82.5, -88)

	-- Clé USB 3 : câble fin vers la vitre, impulsion rapide
	cable(s5, { { 98, -42 }, { 121, -42 } }, 3.5, 66)
	surge(s5, V(119.5, 66, -42), { V(99.5, 66, -42) }, 16, 1.6, 0.6)
	deck(s5, 120, 130, -48, -36, 67.5, "KeyPerch")
	ctx.UsbKey(V(125, 70, -42), 3)

	local room = ctx.TerminalRoom()

	------------------------------------------------------------------------------------
	-- Décor : le bloc d'alimentation
	------------------------------------------------------------------------------------

	-- Le bloc d'alimentation géant (sous la grille praticable de l'étape 4) et son ventilateur
	ModelLibrary.Place("Psu", CFrame.new(V(0, FLOOR_Y, 0)), decor, { Fit = Vector3.new(100, 46, 100) }, psuFallback)
	-- (modèle 17,9 × 3,3 × 16 : Fit en Y assez large pour que ce soit le diamètre qui borne l'échelle)
	ModelLibrary.Place(
		"Fan140",
		CFrame.new(V(0, 33, 0)),
		decor,
		{ Fit = Vector3.new(88, 18, 88) },
		function(): Instance?
			return Props.Fan(
				decor,
				CFrame.new(V(0, 34, 0)) * VERTICAL,
				88,
				ORANGE,
				7,
				{ Speed = 1.4, Lite = true, Brand = "ANGA", Frame = C.MetalDark }
			)
		end
	)
	ctx.Lamp(V(0, 30, 0), ORANGE, 2, 60) -- le ventilateur brille sous la grille

	-- Câbles de décor : du panneau modulaire du bloc jusqu'au câble de l'étape 1
	Props.Cable(
		decor,
		{ V(-30, 17, -50), V(-30, 7.5, -62), V(-30, 7.5, -108), V(-73, 7.5, -108), V(-73, 7.5, -81) },
		3.5,
		BRAID
	)
	Props.Cable(decor, { V(-6, 27, -50), V(-6, 18, -66), V(-40, 18, -66), V(-60, 12.5, -38) }, 2.5, BRAID)
	Props.Cable(decor, { V(18, 17, -50), V(18, 9, -70), V(60, 9, -70), V(90, 30, -30), V(90, 59.5, -30) }, 3, BRAID)
	-- Faisceaux gainés qui montent du bloc vers la carte mère, au plafond (modèle `CableSleeved8` :
	-- plat, 28 × 29, monte du connecteur bas-gauche (x = -20) au connecteur haut-droit ; posé dans le
	-- plan vertical de sa trajectoire, connecteur bas en path[1], haut vers path[3]).
	for i, path in
		{
			{ V(-44, 48, -44), V(-46, 76, -62), V(-52, 98, -84) },
			{ V(44, 48, -44), V(32, 76, -62), V(20, 98, -84) },
			{ V(-44, 48, 44), V(-58, 76, 50), V(-70, 98, 60) },
		} :: { { Vector3 } }
	do
		local run = path[3] - path[1]
		local along = Vector3.new(run.X, 0, run.Z)
		local plane = CFrame.fromMatrix(path[1], along.Unit, Vector3.yAxis, along.Unit:Cross(Vector3.yAxis))
		ModelLibrary.Place(
			"CableSleeved8",
			plane,
			decor,
			{ Fit = Vector3.new(along.Magnitude, run.Y, 12), Anchor = Vector3.new(-14.1, 0, 0) },
			function(): Instance?
				return Props.ArcCable(decor, path[1], path[2], path[3], 1.8, if i == 2 then ORANGE else BRAID, 5)
			end
		)
	end
	-- Transformateurs du bloc (noyau feuilleté, ruban jaune, bobinage cuivre)
	for _, t in { { -50, -88, 0 }, { 10, -96, 0.5 }, { 110, -10, 1.2 } } :: { { number } } do
		local cf = CFrame.new(V(t[1], FLOOR_Y, t[2])) * CFrame.Angles(0, t[3], 0)
		Box(decor, "TransformerCore", Vector3.new(16, 14, 10), cf * CFrame.new(0, 7, 0), C.MetalDark, METAL)
		Box(
			decor,
			"TransformerTape",
			Vector3.new(10, 10.4, 10.6),
			cf * CFrame.new(0, 7, 0),
			Color3.fromRGB(242, 196, 48)
		)
		Box(decor, "TransformerWire", Vector3.new(10.4, 1.4, 11), cf * CFrame.new(0, 10, 0), C.Copper, METAL)
		Box(decor, "TransformerWire", Vector3.new(10.4, 1.4, 11), cf * CFrame.new(0, 4, 0), C.Copper, METAL)
	end
	-- Rouleau de câble 24 broches posé au sol (modèle `CableBraided24`)
	ModelLibrary.Place(
		"CableBraided24",
		CFrame.new(V(-40, FLOOR_Y, -100)),
		decor,
		{ Fit = Vector3.new(50, 22, 30) },
		function(): Instance?
			return Props.ArcCable(decor, V(-60, 4, -118), V(-40, 22, -96), V(-10, 4, -116), 2.6, BRAID, 7)
		end
	)

	-- Forêt de condensateurs de décor (silos) autour du parcours
	for _, c in
		{
			{ -124, 18, 7, 20 },
			{ -94, 60, 8, 22 },
			{ -122, 112, 9, 30 },
			{ -84, 30, 6, 16 },
			{ -58, 84, 10, 28, true },
			{ -56, -20, 8, 18 },
			{ 30, 118, 9, 34, true },
			{ 64, 104, 10, 40, true },
			{ 112, 60, 9, 30, true },
			{ 118, 20, 7, 24 },
			{ 108, -104, 8, 20 },
			{ 30, -110, 10, 26, true },
			{ -12, -118, 7, 18 },
		} :: { { any } }
	do
		decorCap(c[1], c[2], c[3], c[4], c[5] == true)
	end
	-- Selfs alignées au sol (transformateurs de la centrale)
	decorChokes(CFrame.new(V(60, FLOOR_Y, -110)), 4, 7)
	decorChokes(CFrame.new(V(-100, FLOOR_Y, -40)) * CFrame.Angles(0, math.pi / 2, 0), 3, 6)
	decorChokes(CFrame.new(V(70, FLOOR_Y, 70)) * CFrame.Angles(0, 0.4, 0), 3, 8)
	ModelLibrary.Place(
		"Choke",
		CFrame.new(V(96, FLOOR_Y, 28)),
		decor,
		{ Fit = Vector3.new(9, 9, 9) },
		function(): Instance?
			local model = Build.Model("Choke", decor)
			Box(model, "ChokeCore", Vector3.new(9, 9, 9), CFrame.new(V(96, FLOOR_Y + 4.5, 28)), C.Black)
			Rod(model, "Winding", CFrame.new(V(96, FLOOR_Y + 4.5, 28)) * VERTICAL, 5, 10, C.Copper, METAL)
			return model
		end
	)

	-- Pistes de la carte (sous le vide) : lignes orange qui mènent au bloc
	for _, t in { { -130, -60, 0 }, { 60, 130, 0 }, { -20, 20, 1 } } :: { { number } } do
		local horizontal = t[3] == 0
		Build.Neon({
			Name = "Trace",
			Size = if horizontal then Vector3.new(t[2] - t[1], 0.1, 1) else Vector3.new(1, 0.1, 80),
			CFrame = CFrame.new(V(if horizontal then (t[1] + t[2]) / 2 else 0, 0.4, if horizontal then 0 else -92)),
			Color = ORANGE,
			Transparency = 0.4,
			Parent = decor,
		})
	end

	-- Paroi du fond : plaque signalétique géante de la centrale
	local plate =
		Box(decor, "PowerPlate", Vector3.new(80, 16, 0.4), Common.Facing(V(-20, 72, 131.5), -Vector3.zAxis), C.Bg)
	Props.Sign(plate, "ALIMENTATION", "Bloc 1200 W · 12 V · 80 PLUS", ORANGE, C.Silk)
	for _, x in { -60, 20 } do
		Props.Decal(
			decor,
			"Stencil",
			Vector3.new(16, 8, 0.2),
			Common.Facing(V(x, 30, 131.6), -Vector3.zAxis),
			"12V",
			ORANGE,
			Enum.NormalId.Front,
			Enum.Font.GothamBlack
		)
	end

	-- Lumières (7 + entrée + salle = 9)
	ctx.Lamp(V(-80, 34, -40), ORANGE:Lerp(C.White, 0.3), 1.3, 70)
	ctx.Lamp(V(-104, 50, 70), ORANGE:Lerp(C.White, 0.3), 1.3, 70)
	ctx.Lamp(V(-30, 64, 106), AMBER, 1.2, 70)
	ctx.Lamp(V(80, 78, -40), ORANGE:Lerp(C.White, 0.3), 1.3, 70)
	ctx.Lamp(V(0, 88, 0), C.White, 0.9, 110)

	------------------------------------------------------------------------------------
	-- Sbire : Sparky garde le terminal (dans la salle, près de l'écran)
	------------------------------------------------------------------------------------

	-- Au-dessus de l'écran du fond (salle : u 12, v -40, +20) : la salle reste libre pour l'épreuve.
	local sparkyCf = CFrame.lookAt(V(100, 100, -128), V(88, 100, -88))
	ModelLibrary.Place("Sparky", sparkyCf * CFrame.new(0, -3, 0), room, { Scale = 1.6 }, function(): Instance?
		return sparkyFallback(sparkyCf, room)
	end)
	ctx.Lamp(V(110, 92, -112), Color3.fromRGB(255, 222, 64), 1.2, 18, room)

	------------------------------------------------------------------------------------
	-- Infecté (tant que le terminal n'est pas réussi) / nettoyé (après)
	------------------------------------------------------------------------------------

	local infected = Build.Model("Infected", decor)
	ctx.Infected(infected)
	-- Néons rouges d'alerte sur les parois + panneaux « COUPURE »
	for _, a in
		{
			{ V(-131.5, 40, 0), Vector3.xAxis },
			{ V(0, 60, 131.5), -Vector3.zAxis },
			{ V(131.2, 50, 60), -Vector3.xAxis },
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
		local sign = Box(infected, "AlertSign", Vector3.new(24, 7, 0.4), cf * CFrame.new(0, 6, 0), C.Bg)
		Props.Sign(sign, "⚠ COUPURE", "Surtension détectée", ALERT, C.Silk)
	end
	-- Flaques de glitch violettes sur la carte
	for _, p in { { -90, -60, 16 }, { 40, 80, 20 }, { 90, -70, 14 }, { -40, 110, 18 } } :: { { number } } do
		Rod(infected, "GlitchPuddle", CFrame.new(V(p[1], 2.1, p[2])) * VERTICAL, 0.2, p[3], GLITCH, NEON).Transparency =
			0.3
	end
	-- Pubs flottantes
	for _, ad in
		{
			{ V(-100, 34, -60), Vector3.new(1, 0, 0), "PILOTES GRATUITS !", "Clique ici (vraiment)" },
			{ V(-40, 58, 88), Vector3.new(0, 0, 1), "TON PC RAME ?", "Télécharge plus de RAM" },
			{ V(106, 76, -20), Vector3.new(-1, 0, 0), "LAGZ WAS HERE", "Bzzt bzzt bzzt" },
		} :: { { any } }
	do
		local cf = Common.Facing(ad[1], ad[2]) * CFrame.Angles(0, 0, 0.06)
		local window = Box(infected, "AdWindow", Vector3.new(14, 8, 0.4), cf, C.Bg)
		Props.Sign(window, ad[3], ad[4], GLITCH:Lerp(C.White, 0.2), C.Silk)
		Build.Neon({
			Name = "AdTitleBar",
			Size = Vector3.new(14, 1.2, 0.5),
			CFrame = cf * CFrame.new(0, 4.6, 0),
			Color = GLITCH,
			Parent = infected,
		})
	end
	-- Voyants « ERROR » sur le bloc
	local err = Box(infected, "ErrorLed", Vector3.new(14, 5, 0.3), Common.Facing(V(-50.6, 40, 8), -Vector3.xAxis), C.Bg)
	Props.Sign(err, "ERROR", nil, ALERT, nil)

	local cleaned = Build.Model("Cleaned", decor)
	ctx.Cleaned(cleaned)
	-- Liserés orange francs autour du bloc + « 80 PLUS GOLD » + voyants verts
	for _, side in { -1, 1 } do
		Build.Neon({
			Name = "CleanTrim",
			Size = Vector3.new(0.6, 0.8, 100.4),
			CFrame = CFrame.new(V(side * 50.3, 45.5, 0)),
			Color = ORANGE,
			Parent = cleaned,
		})
		Build.Neon({
			Name = "CleanTrim",
			Size = Vector3.new(100.4, 0.8, 0.6),
			CFrame = CFrame.new(V(0, 45.5, side * 50.3)),
			Color = ORANGE,
			Parent = cleaned,
		})
	end
	local gold =
		Box(cleaned, "GoldBadge", Vector3.new(14, 5, 0.3), Common.Facing(V(-50.6, 40, 8), -Vector3.xAxis), C.Bg)
	Props.Sign(gold, "80 PLUS GOLD", "POWER OK", C.Gold, SPRING)
	for i = 0, 3 do
		Build.Neon({
			Name = "PowerOk",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.4,
			CFrame = CFrame.new(V(-24 + i * 12, 30, -51)),
			Color = SPRING,
			Parent = cleaned,
		})
	end
	-- Anneau propre autour de la grille du ventilateur (RGB)
	for _, part in Props.Ring(cleaned, "FanRgb", CFrame.new(V(0, 48.6, 0)) * VERTICAL, 47.5, 0.8, 0.5, 24, ORANGE, NEON) do
		part:AddTag("RgbStrip")
	end
	Build.Neon({
		Name = "CleanBeam",
		Size = Vector3.new(0.6, 40, 0.6),
		CFrame = CFrame.new(V(-131.4, 40, 20)),
		Color = SAFE,
		Parent = cleaned,
	})
end
