--!strict
--[[
	Monde 3 : Data Vault (SSD) — « Fichiers corrompus ». Sbire : Corrupto. Incident : CORRUPTION.

	On traverse l'intérieur d'un SSD géant : un M.2 immense sert de paysage (tout en bas, sous le
	vide), le parcours est une grille de cellules NAND suspendue, puis une baie de disques SATA
	accrochée à la paroi, et le coffre-fort (salle du terminal) au fond à gauche.

	Vue de dessus (entrée au coin (88, 88) → porte (-80, 88), regard -X) :
	  1. Cellules NAND (y 210 → 216) : damier suspendu de cellules qui s'effacent (Vanish), le long de
	     la paroi du fond (vers -X). Tutoriel du monde : on saute en diagonale sans s'arrêter.
	  2. Secteurs corrompus (216 → 229) : dalles « texture manquante » (Corrupt) au-dessus du M.2,
	     vers l'avant (-Z) : damier qui s'inverse (les deux couleurs portent ensemble 0,4 s à chaque
	     relève), puis échelle à deux voies en opposition.
	     CORRUPTION (6 s, annoncée 3 s avant) inverse tout : le damier a alors deux trous de 0,4 s
	     par cycle (on attend sur un palier), les voies s'échangent par surprise (préavis clignotant),
	     et un pont fantôme (dalles presque toujours traversables) devient solide → clé USB 1.
	  3. Défragmenteur (229 → 243) : blocs-fragments qui coulissent de case en case (Defrag) sur une
	     grille ; on passe de bloc en bloc comme un relais de taquin. Clé USB 2 : deux blocs rapides
	     sur un circuit à l'écart.
	  4. Baie de disques (243 → 256) : le long de la paroi gauche, des tiroirs SSD sortent du mur
	     (Mover) pour faire pont ; des pistons d'écriture (Crusher) balaient les paliers.
	     Clé USB 3 : échelle de connecteurs SATA sur la façade de la baie, jusqu'au toit.
	  5. Le coffre-fort (256 → 280) : bus de données à contre-courant (Conveyor) + pistons,
	     secteurs corrompus, ascenseur de fragments (Defrag), cellules NAND finales → porte.

	Décor : SSD M.2 géant (ModelLibrary « M2Ssd »), baie de SSD SATA (« SataSsd »), tours de NAND
	3D, anneau de porte de coffre-fort, Corrupto (« Corrupto ») devant la porte ; versions
	infectée (glitch violet, fenêtres d'erreur, alertes) et nettoyée (pistes de données teal, RGB).
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
local LETHAL = Common.Colors.Lethal

local NAND = Color3.fromRGB(56, 178, 172) -- cellules NAND (Vanish)
local CORRUPT = Color3.fromRGB(58, 34, 76) -- dalles corrompues (le damier rose / noir est posé par le client)
local PISTON = Color3.fromRGB(150, 36, 96) -- pistons d'écriture (mortels)
local GLITCH = Color3.fromRGB(150, 96, 236) -- glitch violet du décor infecté (jamais un danger)
local PINK = Color3.fromRGB(255, 0, 220)
local FRAGMENTS = { -- fragments de fichiers (Defrag) : jamais rouges
	Color3.fromRGB(79, 209, 197),
	Color3.fromRGB(99, 179, 237),
	Color3.fromRGB(154, 140, 255),
}

-- "x,y,z;x,y,z" (décalages monde relatifs à la position de repos).
local function waypoints(points: { Vector3 }): string
	local chunks = {}
	for _, p in points do
		table.insert(chunks, string.format("%.2f,%.2f,%.2f", p.X, p.Y, p.Z))
	end
	return table.concat(chunks, ";")
end

-- Pose un vrai modèle 3D (ou son décor de secours), mis à l'échelle pour que sa plus grande
-- dimension vaille `length` studs (l'échelle d'import des modèles n'est pas garantie).
local function placeModel(
	key: string,
	cf: CFrame,
	parent: Instance,
	length: number,
	fallback: () -> Instance?
): Instance?
	local placed = ModelLibrary.Place(key, cf, parent, { Collide = false }, fallback)
	if placed and placed:IsA("Model") and ModelLibrary.Has(key) then
		local model = placed :: Model
		local extent = model:GetExtentsSize()
		local biggest = math.max(extent.X, extent.Y, extent.Z)
		if biggest > 0 then
			model:ScaleTo(model:GetScale() * length / biggest)
			model:PivotTo(cf)
		end
	end
	return placed
end

return function(ctx: Common.WorldContext)
	local first = Tower.FirstStage(ctx.Index) -- 11
	local style = ctx.Style
	local TEAL, AQUA = style.Primary, style.Secondary
	local decor = ctx.Decor

	ctx.Void()
	ctx.Entrance()

	------------------------------------------------------------------------------------
	-- Outils
	------------------------------------------------------------------------------------

	-- Dalle solide aux couleurs du monde : dessus à `top`, bornes x0..x1 / z0..z1. La course suit
	-- le plus grand côté (les liserés lumineux de ctx.Platform bordent les grands côtés).
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

	-- Pièce piégée (mortelle = non solide ; plateformes = solides).
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

	-- Cellule NAND qui s'efface après contact (Vanish), puce sombre gravée sur le dessus.
	local function nandCell(parent: Instance, x: number, z: number, top: number, delay: number): Part
		local cf = CFrame.new(x, top - 0.7, z)
		local cell = trapPart(parent, "Vanish", "NandCell", Vector3.new(6, 1.4, 6), cf, NAND, SMOOTH, {
			Delay = delay,
			Respawn = 3,
		}, true)
		Common.Attach(cell, "Die", Vector3.new(4.2, 0.12, 4.2), cf * CFrame.new(0, 0.72, 0), C.Bg)
		Common.Attach(cell, "DieMark", Vector3.new(0.9, 0.14, 0.9), cf * CFrame.new(-1.4, 0.74, -1.4), AQUA, NEON)
		return cell
	end

	-- Secteur corrompu (Corrupt) : solide pendant Duty, traversable sinon ; inversé en CORRUPTION.
	local function sector(
		parent: Instance,
		x: number,
		z: number,
		top: number,
		period: number,
		duty: number,
		phase: number
	): Part
		return trapPart(
			parent,
			"Corrupt",
			"CorruptSector",
			Vector3.new(6, 1, 6),
			CFrame.new(x, top - 0.5, z),
			CORRUPT,
			SMOOTH,
			{ Period = period, Duty = duty, Phase = phase },
			true
		)
	end

	-- Fragment de fichier (Defrag) : `top` = dessus à la première case ; bande « fichier » sur le dessus.
	local function fragment(
		parent: Instance,
		x: number,
		z: number,
		top: number,
		path: { Vector3 },
		step: number,
		phase: number,
		color: Color3
	): Part
		local cf = CFrame.new(x, top - 0.8, z)
		local block = trapPart(parent, "Defrag", "Fragment", Vector3.new(6.2, 1.6, 6.2), cf, color, SMOOTH, {
			Waypoints = waypoints(path),
			Step = step,
			Phase = phase,
		}, true)
		Common.Attach(block, "FileTab", Vector3.new(2.4, 0.2, 1.2), cf * CFrame.new(-1.6, 0.86, -2.3), C.White, SMOOTH)
		Common.Attach(
			block,
			"FileLines",
			Vector3.new(4.4, 0.16, 0.5),
			cf * CFrame.new(0, 0.84, 0.6),
			color:Lerp(C.White, 0.6),
			NEON
		)
		return block
	end

	-- Grille lumineuse fine (cases de `pitch` studs) : le « damier en hauteur ».
	local function lattice(
		parent: Instance,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		y: number,
		pitch: number,
		color: Color3
	)
		local nx = math.floor((x1 - x0) / pitch + 0.5)
		local nz = math.floor((z1 - z0) / pitch + 0.5)
		for k = 0, nz do
			local z = z0 + k * pitch
			neon(parent, "GridLine", Vector3.new(x1 - x0, 0.25, 0.25), CFrame.new((x0 + x1) / 2, y, z), color, 0.45)
		end
		for k = 0, nx do
			local x = x0 + k * pitch
			neon(parent, "GridLine", Vector3.new(0.25, 0.25, z1 - z0), CFrame.new(x, y, (z0 + z1) / 2), color, 0.45)
		end
	end

	-- Fenêtre d'erreur flottante (décor infecté).
	local function errorPopup(position: Vector3, look: Vector3, title: string, subtitle: string)
		local model = Build.Model("ErrorPopup", decor)
		local cf = Common.Facing(position, look)
		local frame = Box(model, "Window", Vector3.new(14, 8, 0.4), cf, C.Bg)
		Props.Sign(frame, title, subtitle, GLITCH:Lerp(C.White, 0.3), C.White)
		Box(model, "TitleBar", Vector3.new(14, 1.2, 0.5), cf * CFrame.new(0, 4.4, 0), GLITCH)
		Box(model, "Close", Vector3.new(1, 0.9, 0.6), cf * CFrame.new(6.2, 4.4, -0.1), C.White)
		ctx.Infected(model)
	end

	------------------------------------------------------------------------------------
	-- Étape 1 : cellules NAND (Vanish) — damier suspendu le long de la paroi du fond
	------------------------------------------------------------------------------------

	local function stage1()
		local s = ctx.Stage(first)
		-- Quai de départ (sous le portique d'entrée), au ras du toit de la salle d'arrivée
		slab(s, 62, 80, 82, 94, 210, "Dock")
		-- Champ A (dessus 211) puis champ B (dessus 214) : cases présentes en damier
		for i = 0, 3 do
			for j = 0, 4 do
				if (i + j) % 2 == 0 then
					nandCell(s, 57 - 7 * i, 74 + 7 * j, 211, 1)
				end
				if (i + j + 1) % 2 == 0 then
					nandCell(s, 18 - 7 * i, 74 + 7 * j, 214, 0.9)
				end
			end
		end
		lattice(decor, 32.5, 60.5, 70.5, 105.5, 210, 7, TEAL)
		lattice(decor, -6.5, 21.5, 70.5, 105.5, 213, 7, TEAL)
		-- Palier : la puce contrôleur du SSD
		local controller = slab(s, 23, 31, 76, 100, 212.5, "Controller")
		Props.Decal(
			controller,
			"ControllerMark",
			Vector3.new(6, 0.1, 16),
			CFrame.new(27, 212.56, 88) * CFrame.Angles(0, math.pi / 2, 0),
			"CTRL",
			AQUA,
			Enum.NormalId.Top,
			Enum.Font.GothamBlack
		)
		ctx.Checkpoint(first, Common.Facing(Vector3.new(-14, 216, 88), -Vector3.zAxis))
		ctx.Coin(Vector3.new(50, 213.6, 81))
		ctx.Coin(Vector3.new(57, 213.6, 102))
		ctx.Coin(Vector3.new(27, 215, 88))
		ctx.Coin(Vector3.new(4, 216.6, 95))
		ctx.Lamp(Vector3.new(30, 232, 88), TEAL:Lerp(C.White, 0.45), 1.2, 60)
	end

	------------------------------------------------------------------------------------
	-- Étape 2 : secteurs corrompus (Corrupt) au-dessus du M.2 géant, vers l'avant
	------------------------------------------------------------------------------------

	local function stage2()
		local s = ctx.Stage(first + 1)
		-- Damier qui s'inverse : chaque couleur est pleine 60 % du temps, les deux ensemble 0,4 s
		-- à chaque bascule (on change de case à ce moment-là). En CORRUPTION c'est l'inverse :
		-- deux trous de 0,4 s par cycle où plus rien ne porte… mieux vaut attendre sur un palier.
		for r = 0, 4 do
			for j = 0, 2 do
				sector(s, -21 + 7 * j, 77 - 7 * r, 217, 4, 0.6, ((r + j) % 2) * 0.5)
			end
		end
		local map = slab(s, -24, -4, 34, 44, 218.5, "SectorMap")
		-- Secteur défectueux (danger statique) : on le contourne
		ctx.Hazard(
			s,
			"GlitchBlock",
			Vector3.new(3, 3.5, 3),
			CFrame.new(-22.5, 220.25, 39),
			Common.Colors.Glitch,
			"Hazard"
		)
		Props.Decal(
			map,
			"MapMark",
			Vector3.new(16, 0.1, 6),
			CFrame.new(-14, 218.56, 39),
			"SECTOR MAP",
			AQUA,
			Enum.NormalId.Top,
			Enum.Font.GothamBlack
		)
		-- Échelle à deux voies en opposition (pleines ensemble 0,35 s à chaque relève) : on change de
		-- voie quand la sienne clignote
		for r = 0, 5 do
			local z, top = 29 - 7 * r, 219.7 + 1.3 * r
			sector(s, -18, z, top, 4.4, 0.58, 0)
			sector(s, -10, z, top, 4.4, 0.58, 0.5)
		end
		ctx.Checkpoint(first + 1, Common.Facing(Vector3.new(-14, 229, -18), -Vector3.zAxis))
		ctx.Coin(Vector3.new(-14, 219.5, 63))
		ctx.Coin(Vector3.new(-14, 221, 39))
		ctx.Coin(Vector3.new(-18, 224.8, 15))
		ctx.Coin(Vector3.new(-10, 228.7, -6))

		-- Clé USB 1 : pont fantôme (solide 0,6 s toutes les 12 s… et pendant toute la CORRUPTION)
		-- vers un îlot ; on revient en se laissant tomber sur le damier.
		local ghost = { { 0.5, 220, 39 }, { 7.5, 221.5, 39 }, { 7.5, 223, 46 }, { 7.5, 224.5, 53 } }
		for _, g in ghost do
			sector(s, g[1], g[3], g[2], 12, 0.05, 0)
		end
		local islet = slab(s, 3.5, 11.5, 57, 65, 226, "GhostIslet")
		Props.Decal(
			islet,
			"IsletMark",
			Vector3.new(6, 0.1, 6),
			CFrame.new(7.5, 226.06, 61),
			"?",
			PINK,
			Enum.NormalId.Top,
			Enum.Font.GothamBlack
		)
		ctx.UsbKey(Vector3.new(7.5, 228.3, 61), 1)
		ctx.Lamp(Vector3.new(-12, 240, 38), AQUA:Lerp(C.White, 0.4), 1.1, 55)
	end

	------------------------------------------------------------------------------------
	-- Étape 3 : le défragmenteur (Defrag) — relais de blocs sur une grille
	------------------------------------------------------------------------------------

	local function stage3()
		local s = ctx.Stage(first + 2)
		local step = 1.7
		-- Relais 1 (vers -Z) : chaque bloc fait l'aller-retour entre deux cases en montant de 1,5 ;
		-- les blocs voisins sont en opposition : on passe de l'un à l'autre pendant leurs pauses.
		for k = 0, 2 do
			fragment(
				s,
				-14,
				-28 - 14 * k,
				229.5 + 1.5 * k,
				{ Vector3.zero, Vector3.new(0, 1.5, -7) },
				step,
				(k % 2) * 0.5,
				FRAGMENTS[1]
			)
		end
		lattice(decor, -17.5, -10.5, -66.5, -24.5, 226.5, 7, AQUA)
		local hub = slab(s, -21, -7, -79, -67, 234.5, "DefragHub")
		Props.Decal(
			hub,
			"HubMark",
			Vector3.new(10, 0.1, 8),
			CFrame.new(-14, 234.56, -73),
			"DEFRAG",
			AQUA,
			Enum.NormalId.Top,
			Enum.Font.GothamBlack
		)
		-- Relais 2 (vers -X), 5 blocs
		for k = 0, 4 do
			fragment(
				s,
				-25 - 14 * k,
				-73,
				235 + 1.5 * k,
				{ Vector3.zero, Vector3.new(-7, 1.5, 0) },
				step,
				(k % 2) * 0.5,
				FRAGMENTS[2]
			)
		end
		lattice(decor, -91.5, -21.5, -76.5, -69.5, 231.5, 7, AQUA)
		ctx.Checkpoint(first + 2, Common.Facing(Vector3.new(-98, 243, -73), Vector3.zAxis))
		ctx.Coin(Vector3.new(-14, 233.5, -35))
		ctx.Coin(Vector3.new(-14, 235, -49))
		ctx.Coin(Vector3.new(-14, 237, -73))
		ctx.Coin(Vector3.new(-46, 240.5, -73))
		ctx.Coin(Vector3.new(-74, 243.5, -73))

		-- Clé USB 2 : deux fragments rapides (pause 0,66 s) sur un circuit à l'écart du hub
		fragment(
			s,
			-3,
			-73,
			234.5,
			{ Vector3.zero, Vector3.new(7, 0, 0), Vector3.new(14, 0, 0), Vector3.new(7, 0, 0) },
			1.1,
			0,
			FRAGMENTS[3]
		)
		fragment(
			s,
			11,
			-80,
			234.5,
			{ Vector3.zero, Vector3.new(0, 0, -7), Vector3.new(0, 0, -14), Vector3.new(0, 0, -7) },
			1.1,
			0.5,
			FRAGMENTS[3]
		)
		lattice(decor, -6.5, 14.5, -97.5, -69.5, 231.5, 7, FRAGMENTS[3])
		ctx.UsbKey(Vector3.new(11, 237.3, -94), 2)
		ctx.Lamp(Vector3.new(-40, 252, -73), AQUA:Lerp(C.White, 0.4), 1.2, 60)
	end

	------------------------------------------------------------------------------------
	-- Étape 4 : la baie de disques — tiroirs SSD (Mover) et pistons d'écriture (Crusher)
	------------------------------------------------------------------------------------

	-- Tiroir SSD : rentré dans la baie (x -128..-116), il sort de 16 studs pour faire pont.
	local function drawer(parent: Instance, z: number, top: number, phase: number): Part
		local cf = CFrame.new(-122, top - 0.7, z)
		local tray = trapPart(parent, "Mover", "SsdDrawer", Vector3.new(12, 1.4, 8), cf, C.Aluminum, METAL, {
			Offset = Vector3.new(16, 0, 0),
			Period = 5,
			Phase = phase,
		}, true)
		Common.Attach(tray, "Label", Vector3.new(7, 0.1, 5.4), cf * CFrame.new(-1, 0.74, 0), C.Bg)
		Common.Attach(tray, "LabelLine", Vector3.new(7, 0.12, 0.5), cf * CFrame.new(-1, 0.76, -1.8), TEAL, NEON)
		Common.Attach(tray, "Handle", Vector3.new(0.5, 1.6, 7.2), cf * CFrame.new(6.1, 0, 0), C.Black)
		Common.Attach(tray, "Led", Vector3.new(0.3, 0.4, 1), cf * CFrame.new(6.4, 0.3, 2.6), AQUA, NEON)
		return tray
	end

	-- Piston d'écriture : sort de la baie (+X) et balaie le palier.
	local function piston(parent: Instance, z: number, floor: number, phase: number)
		local cf = CFrame.new(-122, floor + 3.5, z)
		local head = trapPart(parent, "Crusher", "WritePiston", Vector3.new(12, 7, 4), cf, PISTON, SMOOTH, {
			Offset = Vector3.new(14, 0, 0),
			Period = 3.2,
			Phase = phase,
		})
		Common.Attach(head, "Edge", Vector3.new(0.6, 7.1, 4.1), cf * CFrame.new(6.1, 0, 0), LETHAL, NEON)
	end

	local function stage4()
		local s = ctx.Stage(first + 3)
		drawer(s, -62, 244, 0)
		slab(s, -111, -101, -57, -45, 245.5, "Bay")
		piston(s, -51, 245.5, 0)
		drawer(s, -40, 247, 0.25)
		slab(s, -111, -101, -35, -23, 248.5, "Bay")
		piston(s, -29, 248.5, 0.5)
		drawer(s, -18, 250, 0.5)
		slab(s, -111, -101, -13, -1, 251.5, "Bay")
		drawer(s, 4, 253, 0.75)
		slab(s, -111, -101, 9, 15, 254.5, "Bay")
		ctx.Checkpoint(first + 3, Common.Facing(Vector3.new(-106, 256, 22), Vector3.zAxis))
		ctx.Coin(Vector3.new(-106, 248, -55.5))
		ctx.Coin(Vector3.new(-106, 251, -32.5))
		ctx.Coin(Vector3.new(-106, 252.6, -18))
		ctx.Coin(Vector3.new(-106, 254, -7))

		-- Clé USB 3 : échelle de connecteurs SATA sur la façade de la baie, jusqu'au toit
		for k, z in { -10.5, -5.5, -0.5 } do
			local top = 251.5 + 4 * k
			local rung = Build.Part({
				Name = "SataRung",
				Size = Vector3.new(3, 1, 3),
				CFrame = CFrame.new(-115.5, top - 0.5, z),
				Color = C.Black,
				Material = SMOOTH,
				Parent = s,
			})
			neon(rung, "RungPins", Vector3.new(0.3, 0.2, 2.6), CFrame.new(-114.1, top - 0.1, z), C.Gold, 0.1)
		end
		local roof = slab(s, -128, -114, 3, 11, 267.5, "BayRoof")
		roof.Color = C.MetalDark
		ctx.UsbKey(Vector3.new(-121, 270, 7), 3)
		ctx.Lamp(Vector3.new(-100, 266, -26), TEAL:Lerp(C.White, 0.45), 1.2, 60)
	end

	------------------------------------------------------------------------------------
	-- Étape 5 : le coffre-fort — bus de données, pistons, secteurs, ascenseur de fragments
	------------------------------------------------------------------------------------

	local function stage5()
		local s = ctx.Stage(first + 4)
		-- Bus de données qui ramène vers la baie (local +Z vers -Z monde), balayé par 2 pistons
		local busCf = CFrame.new(-106, 256.5, 42) * CFrame.Angles(0, math.pi, 0)
		trapPart(s, "Conveyor", "DataBus", Vector3.new(8, 1, 26), busCf, Color3.fromRGB(30, 38, 52), SMOOTH, {
			Direction = -Vector3.zAxis,
			Speed = 6,
		}, true)
		for _, x in { -110.4, -101.6 } do
			Box(s, "BusRail", Vector3.new(0.8, 1.6, 26), CFrame.new(x, 256.6, 42), C.MetalLight, METAL)
		end
		for z = 32, 52, 5 do
			for _, side in { -1, 1 } do
				neon(
					s,
					"BusChevron",
					Vector3.new(0.4, 0.1, 3.4),
					CFrame.new(-106 + side * 1.4, 257.06, z) * CFrame.Angles(0, side * math.rad(40), 0),
					AQUA,
					0.25
				)
			end
		end
		-- « Onde verte » : à contre-courant (10 studs/s), le 2e piston se range quand on arrive
		piston(s, 38, 257, 0.6)
		piston(s, 49, 257, 0.26)
		slab(s, -112, -100, 56, 70, 258, "BusEnd")
		-- Secteurs corrompus vers +X : deux voies en opposition qui montent
		for r = 0, 4 do
			local x, top = -96 + 7 * r, 259 + 1.2 * r
			sector(s, x, 59.5, top, 4, 0.58, 0)
			sector(s, x, 66.5, top, 4, 0.58, 0.5)
		end
		slab(s, -64, -50, 56, 70, 265, "VaultStep")
		ctx.Hazard(
			s,
			"GlitchBlock",
			Vector3.new(3, 3.5, 3),
			CFrame.new(-51.5, 266.75, 58),
			Common.Colors.Glitch,
			"Hazard"
		)
		-- Ascenseur de fragments : chaque bloc monte de 4 puis redescend ; on passe au suivant en haut
		fragment(s, -57, 74, 266, { Vector3.zero, Vector3.new(0, 4, 0) }, 1.6, 0, FRAGMENTS[1])
		fragment(s, -57, 81, 270, { Vector3.zero, Vector3.new(0, 4, 0) }, 1.6, 0.5, FRAGMENTS[2])
		fragment(s, -64, 81, 274, { Vector3.zero, Vector3.new(0, 4, 0) }, 1.6, 0, FRAGMENTS[3])
		-- Dernières cellules NAND devant la porte du coffre
		nandCell(s, -71, 84, 279, 0.8)
		nandCell(s, -77, 88, 280, 0.8)
		ctx.Coin(Vector3.new(-106, 259.5, 44))
		ctx.Coin(Vector3.new(-106, 260.5, 63))
		ctx.Coin(Vector3.new(-82, 263, 63))
		ctx.Coin(Vector3.new(-57, 267.5, 63))
		ctx.Coin(Vector3.new(-71, 281.6, 84))
		ctx.Lamp(Vector3.new(-80, 276, 58), TEAL:Lerp(C.White, 0.45), 1.3, 60)
	end

	------------------------------------------------------------------------------------
	-- Décor
	------------------------------------------------------------------------------------

	-- SSD M.2 géant couché sur le plancher du monde (sous la brume du vide) : le paysage.
	local function giantM2()
		local base = ctx.Base
		local center = Vector3.new(-14, base, 0)
		local cf = CFrame.new(center)
		placeModel("M2Ssd", cf * CFrame.Angles(0, math.pi / 2, 0), decor, 200, function(): Instance?
			local model = Build.Model("M2Ssd", decor)
			local top = base + 0.6
			Box(model, "Pcb", Vector3.new(56, 1.2, 200), CFrame.new(-14, top - 0.6, 0), C.Pcb:Lerp(TEAL, 0.1))
			Box(model, "Fingers", Vector3.new(44, 0.3, 8), CFrame.new(-14, top + 0.05, -95), C.Gold, Enum.Material.Foil)
			for x = -34, 6, 8 do
				Box(model, "FingerGap", Vector3.new(0.8, 0.35, 8.2), CFrame.new(x, top + 0.06, -95), C.Pcb)
			end
			Rod(model, "ScrewNotch", CFrame.new(-14, top, 100) * VERTICAL, 1.3, 14, C.Gold, Enum.Material.Foil)
			Box(model, "Controller", Vector3.new(18, 2.4, 18), CFrame.new(-14, top + 1.2, 72), C.Black)
			Box(model, "Dram", Vector3.new(12, 1.8, 16), CFrame.new(-14, top + 0.9, 50), C.Black)
			for i, z in { 22, -12, -46 } do
				local chip = Box(model, "Nand", Vector3.new(40, 2.6, 28), CFrame.new(-14, top + 1.3, z), C.Black)
				if i == 2 then
					Props.Label(chip, "ANGA · 2 TB · NVMe", AQUA, Enum.NormalId.Top, Enum.Font.GothamBlack)
				end
			end
			for _, z in { 86, 60, 36, -76 } do
				for _, x in { -36, 8 } do
					Box(model, "Smd", Vector3.new(3, 1, 2), CFrame.new(x, top + 0.5, z), C.Silk)
				end
			end
			return model
		end)
		-- Pistes de données : teal vif une fois nettoyé, grises et ternes tant que c'est infecté
		local clean = Build.Model("DataTraces", decor)
		local dull = Build.Model("DeadTraces", decor)
		for _, x in { -40, -38, 10, 12 } do
			neon(clean, "Trace", Vector3.new(0.6, 0.2, 170), CFrame.new(x, base + 1.7, 0), TEAL, 0.1)
			Box(dull, "Trace", Vector3.new(0.6, 0.2, 170), CFrame.new(x, base + 1.7, 0), C.MetalDark)
		end
		ctx.Cleaned(clean)
		ctx.Infected(dull)
		-- Flaques de glitch violet sur le SSD
		local glitch = Build.Model("GlitchPuddles", decor)
		for _, p in { { -30, 30 }, { 4, -24 }, { -24, -64 }, { 0, 58 } } do
			neon(glitch, "Glitch", Vector3.new(9, 0.3, 7), CFrame.new(p[1], base + 3.2, p[2]), GLITCH, 0.35)
			neon(glitch, "GlitchPixel", Vector3.new(3, 0.3, 3), CFrame.new(p[1] + 5, base + 3.4, p[2] - 4), PINK, 0.4)
		end
		ctx.Infected(glitch)
	end

	-- Baie de disques SATA accrochée à la paroi gauche (x -132) : cadre, disques rangés.
	local function driveBay()
		local model = Build.Model("DriveBay", decor)
		for _, z in { -70, -48, -26, -4, 18, 40, 60 } do
			Box(model, "Post", Vector3.new(2, 26, 2), CFrame.new(-116.5, 253, z), C.MetalDark, METAL)
			Box(model, "BackPost", Vector3.new(2, 26, 2), CFrame.new(-130, 253, z), C.MetalDark, METAL)
		end
		for _, y in { 240, 266 } do
			Box(model, "Rail", Vector3.new(15.5, 1.2, 132), CFrame.new(-123.25, y, -5), C.MetalDark, METAL)
		end
		neon(model, "BayStrip", Vector3.new(0.4, 0.6, 132), CFrame.new(-115.3, 265, -5), TEAL, 0.15)
		-- Disques rangés (décor) entre les tiroirs mobiles
		local stored = {
			{ -76, 248 },
			{ -62, 250 },
			{ -40, 253 },
			{ -18, 256 },
			{ 4, 259 },
			{ 24, 262 },
			{ 44, 260 },
			{ 60, 262 },
		}
		for _, d in stored do
			local cf = CFrame.new(-123, d[2], d[1]) * CFrame.Angles(0, math.pi / 2, 0)
			placeModel("SataSsd", cf, model, 12, function(): Instance?
				local drive = Build.Model("SataSsd", model)
				Box(drive, "Case", Vector3.new(8, 1.4, 12), cf * CFrame.new(0, 0.7, 0), C.Aluminum, METAL)
				Box(drive, "Sticker", Vector3.new(6, 0.1, 7), cf * CFrame.new(0, 1.44, 0.5), C.Bg)
				Box(drive, "Port", Vector3.new(4, 0.6, 0.6), cf * CFrame.new(0, 0.7, -6.2), C.Black)
				return drive
			end)
		end
		local plate = Box(model, "BayLabel", Vector3.new(0.3, 5, 26), CFrame.new(-115.4, 276, -30), C.Bg)
		Props.Sign(plate, "BAIE SATA", "Tiroirs hot-swap", TEAL, C.White, Enum.NormalId.Right)
	end

	-- Tour de NAND 3D (couches empilées + canaux verticaux), vue à travers la vitre.
	local function nandTower(x: number, z: number, layers: number)
		local model = Build.Model("Nand3D", decor)
		local base = ctx.Base
		for k = 0, layers - 1 do
			local y = base + 6 + k * 5
			local plate = Box(
				model,
				"Layer",
				Vector3.new(22, 1.6, 22),
				CFrame.new(x, y, z),
				if k % 2 == 0 then C.PcbDark else C.Black
			)
			plate.Transparency = 0.1
			if k % 3 == 1 then
				neon(model, "LayerGlow", Vector3.new(22.4, 0.3, 22.4), CFrame.new(x, y + 0.9, z), TEAL, 0.3)
			end
		end
		for _, dx in { -6, 6 } do
			for _, dz in { -6, 6 } do
				Rod(
					model,
					"Channel",
					CFrame.new(x + dx, base + 5 + layers * 2.5, z + dz) * VERTICAL,
					layers * 5 + 2,
					1.4,
					AQUA:Lerp(C.White, 0.3),
					NEON
				).Transparency =
					0.35
			end
		end
	end

	-- Anneau de porte de coffre-fort autour de la porte de la salle du terminal (x -80).
	local function vaultDoor()
		local door = ctx.Terminal.Door.Position
		local cf = CFrame.new(door.X + 0.6, door.Y + 6, door.Z)
		local model = Build.Model("VaultRing", decor)
		Props.Ring(model, "VaultRing", cf, 9.6, 1.6, 1.2, 16, C.Nickel, METAL)
		for k = 0, 7 do
			local bolt = cf * CFrame.Angles(k * math.pi / 4 + math.pi / 8, 0, 0) * CFrame.new(0.4, 11.2, 0)
			Rod(model, "Bolt", bolt, 1.6, 1.4, C.MetalLight)
		end
		local glow = Build.Model("VaultGlow", decor)
		Props.Ring(glow, "VaultGlow", cf * CFrame.new(0.5, 0, 0), 8.4, 0.5, 0.4, 16, TEAL, NEON)
		ctx.Cleaned(glow)
		local alarm = Build.Model("VaultAlarm", decor)
		Props.Ring(alarm, "VaultAlarm", cf * CFrame.new(0.5, 0, 0), 8.4, 0.5, 0.4, 16, GLITCH, NEON)
		ctx.Infected(alarm)
	end

	-- Corrupto, le sbire : cube de pixels « texture manquante » qui garde la porte.
	local function corrupto()
		local position = Vector3.new(-70, 289, 101)
		local cf = Common.Facing(position, Vector3.new(1, 0, -0.4))
		local minion = placeModel("Corrupto", cf, decor, 9, function(): Instance?
			local model = Build.Model("Corrupto", decor)
			for i = 0, 7 do
				local dx, dy, dz = (i % 2) * 2 - 1, (math.floor(i / 2) % 2) * 2 - 1, (math.floor(i / 4) % 2) * 2 - 1
				local pink = (i + math.floor(i / 2) + math.floor(i / 4)) % 2 == 0
				Box(
					model,
					"Pixel",
					Vector3.one * 3.6,
					cf * CFrame.new(dx * 1.8, 4 + dy * 1.8, dz * 1.8),
					if pink then PINK else C.Black
				)
			end
			for _, side in { -1, 1 } do
				Box(model, "Eye", Vector3.new(1.4, 1.8, 0.3), cf * CFrame.new(side * 1.3, 5, -3.7), C.White)
				Box(model, "Pupil", Vector3.new(0.7, 0.9, 0.3), cf * CFrame.new(side * 1.2, 4.8, -3.85), C.Black)
			end
			Box(model, "Grin", Vector3.new(3.4, 0.5, 0.3), cf * CFrame.new(0, 2.8, -3.75), C.White)
			for k = 0, 3 do
				Box(
					model,
					"StrayPixel",
					Vector3.one * 1.2,
					cf * CFrame.new(-4 + k * 2.6, 9 + (k % 2) * 1.5, 1),
					if k % 2 == 0 then PINK else C.Black
				)
			end
			return model
		end)
		-- Il n'est là que tant que le monde est infecté
		if minion then
			ctx.Infected(minion)
		end
		local plate = Box(
			decor,
			"CorruptoTag",
			Vector3.new(10, 2.4, 0.3),
			Common.Facing(position + Vector3.new(0, 12.5, 0), Vector3.new(1, 0, -0.4)),
			C.Bg
		)
		plate.Transparency = 1
		Props.Sign(plate, "CORRUPTO", nil, PINK)
		ctx.Infected(plate)
	end

	local function walls()
		local base = ctx.Base
		-- Paroi du fond (+Z) : grand nom du monde (propre / infecté)
		local clean = Box(decor, "VaultSign", Vector3.new(90, 16, 0.3), CFrame.new(20, base + 58, 131.5), C.Bg)
		clean.Transparency = 1
		Props.Sign(clean, "DATA VAULT", "Stockage · 100 % sain", TEAL, C.White, Enum.NormalId.Front)
		ctx.Cleaned(clean)
		local sick = Box(decor, "VaultSign", Vector3.new(90, 16, 0.3), CFrame.new(20, base + 58, 131.5), C.Bg)
		sick.Transparency = 1
		Props.Sign(
			sick,
			"DATA VAULT",
			"Fichiers corrompus : 37 %",
			GLITCH:Lerp(C.White, 0.2),
			C.White,
			Enum.NormalId.Front
		)
		ctx.Infected(sick)
		-- Bandes lumineuses le long des parois (RGB propre / alerte)
		local rgb = Build.Model("WallRgb", decor)
		local alert = Build.Model("WallAlert", decor)
		-- (hors de la salle du terminal : x < -80, z > 80)
		for _, wall in { { 27, 131.4, 210, 0 }, { 0, -131.4, 264, 0 }, { -131.4, -27, 0, 210 } } do
			local size = if wall[3] > 0 then Vector3.new(wall[3], 0.8, 0.4) else Vector3.new(0.4, 0.8, wall[4])
			local strip = neon(rgb, "RgbStrip", size, CFrame.new(wall[1], base + 90, wall[2]), TEAL, 0.15)
			strip:AddTag("RgbStrip")
			neon(alert, "AlertStrip", size, CFrame.new(wall[1], base + 90, wall[2]), Color3.fromRGB(255, 80, 96), 0.35)
		end
		ctx.Cleaned(rgb)
		ctx.Infected(alert)
		-- Fenêtres d'erreur flottantes (infecté)
		errorPopup(Vector3.new(40, 226, 112), Vector3.new(0, 0, -1), "ERREUR CRC", "Secteur illisible")
		errorPopup(Vector3.new(16, 240, 10), Vector3.new(-1, 0, 0), "BAD SECTOR", "Fichier corrompu")
		errorPopup(Vector3.new(-60, 258, -100), Vector3.new(0, 0, 1), "DÉFRAG 3 %", "Temps restant : 999 h")
		errorPopup(Vector3.new(-30, 294, 78), Vector3.new(-1, 0, 0), "ACCÈS REFUSÉ", "Corrupto garde le coffre")
		ctx.Lamp(Vector3.new(30, base + 48, -40), TEAL:Lerp(C.White, 0.5), 1.4, 90)
	end

	stage1()
	stage2()
	stage3()
	stage4()
	stage5()
	giantM2()
	driveBay()
	nandTower(78, -70, 12)
	nandTower(96, 10, 9)
	vaultDoor()
	corrupto()
	walls()
	ctx.TerminalRoom()
end
