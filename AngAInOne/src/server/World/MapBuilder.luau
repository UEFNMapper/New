--!strict
--[[
	MapBuilder : construit le PC GÉANT dans lequel tous les joueurs se baladent.

	Le PC est couché sur le flanc : la carte mère est le sol, la vitre latérale est le
	plafond (la lumière de la pièce entre à travers). Voir Config/WorldLayout pour la
	grille des districts et les portails.

	Workspace.World
	├─ Case    : carte mère, parois du boîtier (passe-câbles, ventilateurs d'extraction), vitre
	├─ BoardDetails : CMS, selfs, condensateurs de la carte mère
	├─ Walls   : cloisons de verre entre districts
	├─ Gates   : Gate2..7 (portail d'énergie : tag ZoneGate, attribut Zone ; terminal "Débloquer")
	├─ Hub     : chipset, slots PCIe/M.2/SATA, ATX 24, Q-code, classements, téléporteur, spawn
	├─ Zones   : Zone1..7 (Model, attribut Zone)
	│    ├─ Modules / Z{z}M{s}  (attribut ModuleId, prompt "Améliorer")
	│    ├─ Collector, Teleporter, terminal de la zone, Fragments / F1..3
	│    └─ décor "héros" : PSU, barrettes de RAM, baie SSD + M.2, watercooling, ventirad, GPU, puce IA
	└─ Viruses : créés par VirusService (attribut OwnerUserId)

	Toute la progression visuelle (tiers des machines, portails ouverts/fermés, fragments
	trouvés) est calculée CÔTÉ CLIENT avec les données du joueur : chacun voit sa propre
	progression dans un monde partagé.

	Budget mobile : ≤ 6500 pièces, ≤ 60 PointLights (tests/map.spec.luau). Les détails fins
	sont du décor pur (Props.Box / Rod / Wedge) ; seuls les volumes principaux sont solides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Modules = require(Shared.Config.Modules)
local WorldLayout = require(Shared.Config.WorldLayout)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)

local MapBuilder = {}

local C = Props.C
local L = WorldLayout
local CASE_H = L.CASE_HEIGHT
local WALL_H = L.WALL_HEIGHT

local Box, Rod, Wedge = Props.Box, Props.Rod, Props.Wedge
local METAL = Enum.Material.Metal
local FOIL = Enum.Material.Foil
local UP = CFrame.Angles(0, 0, math.pi / 2) -- axe X local (cylindres) -> vertical

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

-- Repère "plaza" d'une zone : n = direction vers l'intérieur, t = latéral.
local function frameOf(layout: WorldLayout.ZoneLayout): (Vector3, Vector3)
	local inward = (layout.Spawn - layout.Gate) * Vector3.new(1, 0, 1)
	local n = inward.Unit
	local t = n:Cross(Vector3.yAxis)
	return n, t
end

local function plazaPoint(layout: WorldLayout.ZoneLayout, depth: number, lateral: number): Vector3
	local n, t = frameOf(layout)
	return layout.Gate + n * depth + t * lateral
end

-- CFrame au sol, face (-Z) tournée vers le portail de la zone.
local function facingGate(layout: WorldLayout.ZoneLayout, position: Vector3): CFrame
	local n = frameOf(layout)
	return CFrame.lookAt(position, position - n)
end

------------------------------------------------------------------------------------
-- Utilitaires de décor
------------------------------------------------------------------------------------

-- Volume solide (collision) : les grandes masses des composants.
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
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

-- Bande néon (décor), avec tags optionnels (RgbStrip, PulseGlow…).
local function neon(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	transparency: number?,
	tags: { string }?
): Part
	return Build.Neon({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Transparency = transparency or 0.2,
		Tags = tags,
		Parent = parent,
	})
end

-- Lumière d'ambiance (pièce invisible + PointLight sans ombres).
local function lamp(parent: Instance, name: string, position: Vector3, color: Color3, brightness: number, range: number)
	local anchor = Box(parent, name, Vector3.one, CFrame.new(position), color)
	anchor.Transparency = 1
	Build.PointLight(anchor, color, brightness, range)
end

-- Sérigraphie au sol : cadre fin autour d'une empreinte de composant.
local function silkRect(parent: Instance, center: Vector3, sizeX: number, sizeZ: number)
	for _, side in { -1, 1 } do
		Box(
			parent,
			"Silk",
			Vector3.new(sizeX, 0.06, 0.5),
			CFrame.new(center.X, 0.04, center.Z + side * sizeZ / 2),
			C.Silk
		)
		Box(
			parent,
			"Silk",
			Vector3.new(0.5, 0.06, sizeZ),
			CFrame.new(center.X + side * sizeX / 2, 0.04, center.Z),
			C.Silk
		)
	end
end

-- Texte sérigraphié au sol (lisible depuis le haut).
local function silkText(parent: Instance, text: string, center: Vector3, sizeX: number, sizeZ: number, color: Color3?)
	Props.Decal(
		parent,
		"SilkText",
		Vector3.new(sizeX, 0.1, sizeZ),
		CFrame.new(center.X, 0.06, center.Z),
		text,
		color or C.Silk,
		Enum.NormalId.Top,
		Enum.Font.Code
	)
end

-- Vis de fixation (entretoise de carte mère) : tête chromée fendue en croix sur pastille dorée.
local function screwHead(parent: Instance, cf: CFrame, diameter: number)
	Rod(parent, "ScrewPad", cf * CFrame.new(0, 0.05, 0) * UP, 0.1, diameter * 1.6, C.Gold, FOIL)
	Rod(parent, "Screw", cf * CFrame.new(0, 0.35, 0) * UP, 0.6, diameter, C.Nickel)
	for _, angle in { 0, math.pi / 2 } do
		Box(
			parent,
			"ScrewSlot",
			Vector3.new(diameter * 0.7, 0.1, diameter * 0.14),
			cf * CFrame.new(0, 0.67, 0) * CFrame.Angles(0, angle, 0),
			C.Bg
		)
	end
end

-- Passe-câble en caoutchouc (ovale fendu) sur une paroi. `cf` : LookVector = vers l'intérieur du boîtier.
local function grommet(parent: Instance, cf: CFrame, width: number, height: number)
	local body = cf * CFrame.new(0, 0, -0.6)
	Box(parent, "Grommet", Vector3.new(width - height, height, 1.2), body, C.Rubber)
	for _, side in { -1, 1 } do
		Rod(
			parent,
			"GrommetEnd",
			body * CFrame.new(side * (width - height) / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
			1.2,
			height,
			C.Rubber,
			Enum.Material.SmoothPlastic
		)
	end
	Box(parent, "GrommetSlit", Vector3.new(width - height * 0.5, height * 0.16, 1.3), body, C.Bg)
end

-- Self d'étage d'alimentation (ferrite + marquage) avec son DrMOS à côté (`toward`).
local function choke(parent: Instance, position: Vector3, toward: Vector3)
	solid(
		parent,
		"Choke",
		Vector3.new(8, 6, 8),
		CFrame.new(position + Vector3.new(0, 3, 0)),
		Color3.fromRGB(60, 62, 70),
		METAL
	)
	Box(
		parent,
		"ChokeTop",
		Vector3.new(7, 0.3, 7),
		CFrame.new(position + Vector3.new(0, 6.15, 0)),
		Color3.fromRGB(92, 96, 108),
		METAL
	)
	-- Marquage (point de polarité) plutôt qu'un texte : économise une SurfaceGui par self
	Box(parent, "ChokeDot", Vector3.new(1, 0.1, 1), CFrame.new(position + Vector3.new(-2.4, 6.33, -2.4)), C.Silk)
	Box(parent, "ChokePad", Vector3.new(9, 0.2, 9), CFrame.new(position + Vector3.new(0, 0.1, 0)), C.Aluminum, METAL)
	Box(parent, "DrMos", Vector3.new(5, 0.8, 5), CFrame.new(position + toward * 9 + Vector3.new(0, 0.4, 0)), C.Black)
end

-- Ruban plat (câble SATA, nappe) : segments de boîte qui suivent des points (décor).
local function ribbon(parent: Instance, points: { Vector3 }, width: number, color: Color3)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
		Box(
			parent,
			"Ribbon",
			Vector3.new(width, 0.5, (b - a).Magnitude + 0.5),
			CFrame.lookAt((a + b) / 2, b, up),
			color
		)
	end
end

------------------------------------------------------------------------------------
-- Boîtier et carte mère
------------------------------------------------------------------------------------

local function buildCase(world: Instance)
	local case = Build.Model("Case", world)
	case.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local sizeX, sizeZ = L.MAX_X - L.MIN_X, L.MAX_Z - L.MIN_Z

	-- Carte mère (sol)
	Build.Part({
		Name = "Motherboard",
		Size = Vector3.new(sizeX, 4, sizeZ),
		CFrame = CFrame.new(0, -2, 0),
		Color = C.Pcb,
		Material = Enum.Material.SmoothPlastic,
		Parent = case,
	})
	-- Grille de pistes de cuivre (lignes fines) : donne l'échelle et la texture "PCB"
	local traces = Build.Model("Traces", case)
	for x = L.MIN_X + 30, L.MAX_X - 30, 60 do
		Build.Decor({
			Name = "TraceX",
			Size = Vector3.new(0.6, 0.05, sizeZ - 20),
			CFrame = CFrame.new(x, 0.03, 0),
			Color = C.PcbDark:Lerp(C.Copper, 0.35),
			Material = Enum.Material.SmoothPlastic,
			Parent = traces,
		})
	end
	for z = L.MIN_Z + 30, L.MAX_Z - 30, 60 do
		Build.Decor({
			Name = "TraceZ",
			Size = Vector3.new(sizeX - 20, 0.05, 0.6),
			CFrame = CFrame.new(0, 0.03, z),
			Color = C.PcbDark:Lerp(C.Copper, 0.35),
			Material = Enum.Material.SmoothPlastic,
			Parent = traces,
		})
	end
	-- Contour sérigraphié + vis de fixation de la carte (entretoises)
	silkRect(traces, Vector3.zero, sizeX - 10, sizeZ - 10)
	for _, spot in
		{
			Vector3.new(-526, 0, -406),
			Vector3.new(526, 0, -406),
			Vector3.new(-526, 0, 406),
			Vector3.new(526, 0, 406),
			Vector3.new(-192, 0, 152),
			Vector3.new(192, 0, -152),
		}
	do
		screwHead(traces, CFrame.new(spot), 7)
	end

	-- Parois du boîtier (acier) + liseré RGB en bas
	local function wall(name: string, size: Vector3, position: Vector3)
		Build.Part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(position),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Parent = case,
		})
	end
	wall("Front", Vector3.new(6, CASE_H, sizeZ + 12), Vector3.new(L.MIN_X - 3, CASE_H / 2, 0))
	wall("Rear", Vector3.new(6, CASE_H, sizeZ + 12), Vector3.new(L.MAX_X + 3, CASE_H / 2, 0))
	wall("Top", Vector3.new(sizeX + 12, CASE_H, 6), Vector3.new(0, CASE_H / 2, L.MIN_Z - 3))
	wall("Bottom", Vector3.new(sizeX + 12, CASE_H, 6), Vector3.new(0, CASE_H / 2, L.MAX_Z + 3))
	for _, strip in
		{
			{ Vector3.new(0.8, 1.2, sizeZ), Vector3.new(L.MIN_X + 0.5, 3, 0) },
			{ Vector3.new(0.8, 1.2, sizeZ), Vector3.new(L.MAX_X - 0.5, 3, 0) },
			{ Vector3.new(sizeX, 1.2, 0.8), Vector3.new(0, 3, L.MIN_Z + 0.5) },
			{ Vector3.new(sizeX, 1.2, 0.8), Vector3.new(0, 3, L.MAX_Z - 0.5) },
		}
	do
		Build.Neon({
			Name = "CaseRgb",
			Size = strip[1],
			CFrame = CFrame.new(strip[2]),
			Color = C.Violet,
			Transparency = 0.3,
			Tags = { "RgbStrip" },
			Parent = case,
		})
	end

	-- Ventilateurs d'extraction sur le dessus du boîtier (paroi nord, au-dessus du ventirad)
	for _, x in { -75, 75 } do
		Props.Fan(
			case,
			CFrame.new(x, 215, L.MIN_Z) * CFrame.Angles(0, -math.pi / 2, 0),
			124,
			C.Violet,
			9,
			{ Rgb = true }
		)
	end
	-- Passe-câbles caoutchouc (câble EPS, bord arrière, canyon du GPU)
	for _, spot in
		{
			{ At = Vector3.new(-150, 40, L.MIN_Z), Inward = Vector3.zAxis, Width = 30 },
			{ At = Vector3.new(L.MAX_X, 40, -60), Inward = -Vector3.xAxis, Width = 40 },
			{ At = Vector3.new(L.MAX_X, 40, 60), Inward = -Vector3.xAxis, Width = 40 },
			{ At = Vector3.new(430, 40, L.MAX_Z), Inward = -Vector3.zAxis, Width = 40 },
		}
	do
		grommet(case, CFrame.lookAt(spot.At, spot.At + spot.Inward), spot.Width, spot.Width * 0.3)
	end

	-- Vitre latérale (plafond) : laisse passer la lumière de la pièce
	Build.Part({
		Name = "SideGlass",
		Size = Vector3.new(sizeX + 12, 2, sizeZ + 12),
		CFrame = CFrame.new(0, CASE_H + 1, 0),
		Color = Color3.fromRGB(200, 215, 240),
		Material = Enum.Material.Glass,
		Transparency = 0.88,
		CastShadow = false,
		Parent = case,
	})
	-- Poutres du cadre (visibles en levant la tête)
	for _, x in { L.MIN_X / 3, L.MAX_X / 3 } do
		Build.Decor({
			Name = "Beam",
			Size = Vector3.new(8, 8, sizeZ),
			CFrame = CFrame.new(x, CASE_H - 4, 0),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Parent = case,
		})
	end

	-- Spawn (hub)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(18, 0.4, 18)
	spawn.CFrame = CFrame.new(L.HubSpawn * Vector3.new(1, 0, 1) + Vector3.new(0, 0.2, 0))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Neon
	spawn.Color = C.Brand
	spawn.Transparency = 0.35
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = case
end

-- Composants CMS éparpillés sur la carte mère : très bas (on marche dessus), sans collision.
local function buildBoardDetails(world: Instance)
	local details = Build.Model("BoardDetails", world)
	details.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local rng = Random.new(20260930) -- graine fixe : même carte mère à chaque serveur
	local kinds = {
		{ Name = "Resistor", Size = Vector3.new(2.4, 0.45, 1.2), Color = C.Black },
		{ Name = "Ceramic", Size = Vector3.new(1.8, 0.5, 1), Color = Color3.fromRGB(176, 146, 104) },
		{ Name = "Chip", Size = Vector3.new(5, 0.5, 5), Color = C.Black },
		{ Name = "Diode", Size = Vector3.new(2, 0.4, 1.4), Color = C.MetalDark },
	}
	for _ = 1, 540 do
		local kind = kinds[rng:NextInteger(1, #kinds)]
		local x = rng:NextNumber(L.MIN_X + 8, L.MAX_X - 8)
		local z = rng:NextNumber(L.MIN_Z + 8, L.MAX_Z - 8)
		local cf = CFrame.new(x, kind.Size.Y / 2, z)
			* CFrame.Angles(0, if rng:NextNumber() < 0.5 then 0 else math.pi / 2, 0)
		Build.Decor({
			Name = kind.Name,
			Size = kind.Size,
			CFrame = cf,
			Color = kind.Color,
			Material = Enum.Material.SmoothPlastic,
			CastShadow = false,
			Parent = details,
		})
		if kind.Name == "Chip" then
			-- Broches argentées de chaque côté de la puce
			for _, side in { -1, 1 } do
				Build.Decor({
					Name = "Pins",
					Size = Vector3.new(4.4, 0.15, 0.6),
					CFrame = cf * CFrame.new(0, -0.15, side * 2.8),
					Color = C.Aluminum,
					Material = Enum.Material.Metal,
					CastShadow = false,
					Parent = details,
				})
			end
		end
	end
	-- Selfs (bobines) de l'étage d'alimentation : rangée ouest le long des VRM de The Core,
	-- et deux demi-rangées au nord, de part et d'autre du socket.
	for i = 0, 7 do
		choke(details, Vector3.new(-135, 0, -385 + i * 22), Vector3.new(1, 0, 0))
	end
	for _, x in { -102, -86, -70, 70, 86, 102 } do
		choke(details, Vector3.new(x, 0, -386), Vector3.new(0, 0, 0.8))
	end
end

------------------------------------------------------------------------------------
-- Cloisons de verre entre districts + portails
------------------------------------------------------------------------------------

local ZONE_OF_DISTRICT = {
	{ 4, 5, 7 }, -- ligne 1 (nord)
	{ 3, 0, 2 }, -- ligne 2
	{ 1, 1, 6 }, -- ligne 3 (sud)
}

local function glassWall(parent: Instance, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid + Vector3.new(0, WALL_H / 2, 0), to + Vector3.new(0, WALL_H / 2, 0))
	Build.Part({
		Name = "Glass",
		Size = Vector3.new(1, WALL_H, length),
		CFrame = cf,
		Color = Color3.fromRGB(120, 140, 190),
		Material = Enum.Material.Glass,
		Transparency = 0.7,
		CastShadow = false,
		Parent = parent,
	})
	Build.Part({
		Name = "Rail",
		Size = Vector3.new(3, 3, length),
		CFrame = cf * CFrame.new(0, -WALL_H / 2 + 1.5, 0),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	Build.Neon({
		Name = "Top",
		Size = Vector3.new(1.4, 0.8, length),
		CFrame = cf * CFrame.new(0, WALL_H / 2, 0),
		Color = C.Cyan,
		Transparency = 0.35,
		Parent = parent,
	})
end

local function buildGate(gates: Instance, layout: WorldLayout.ZoneLayout)
	local zone = Zones[layout.Zone]
	local primary = hex(zone.Primary)
	local model = Build.Model(`Gate{layout.Zone}`, gates)
	model:SetAttribute("Zone", layout.Zone)
	local n, t = frameOf(layout)
	local half = L.GATE_WIDTH / 2
	-- X local = latéral (largeur du portail), -Z local = vers l'intérieur de la zone
	local base = CFrame.lookAt(layout.Gate, layout.Gate + n)

	-- Piliers + linteau avec le nom de la zone
	for _, side in { -1, 1 } do
		Build.Part({
			Name = "Pillar",
			Size = Vector3.new(6, WALL_H + 10, 6),
			CFrame = CFrame.new(layout.Gate + t * (half + 3) * side + Vector3.new(0, (WALL_H + 10) / 2, 0)),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		Build.Neon({
			Name = "PillarGlow",
			Size = Vector3.new(1, WALL_H + 6, 1),
			CFrame = CFrame.new(layout.Gate + t * (half + 3) * side - n * 3.2 + Vector3.new(0, (WALL_H + 6) / 2, 0)),
			Color = primary,
			Transparency = 0.2,
			Parent = model,
		})
	end
	local lintel = Build.Part({
		Name = "Lintel",
		Size = Vector3.new(L.GATE_WIDTH + 18, 9, 4),
		CFrame = base * CFrame.new(0, WALL_H + 5, 0),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	-- Le nom est lisible des deux côtés
	local sign = `{string.upper(zone.Name)}  ·  {zone.AppSection}`
	Props.Label(lintel, sign, primary, Enum.NormalId.Front)
	Props.Label(lintel, sign, primary, Enum.NormalId.Back)

	-- Barrière d'énergie : collision gérée par le client (fermée tant que la zone est verrouillée)
	local barrier = Build.Part({
		Name = "Barrier",
		Size = Vector3.new(L.GATE_WIDTH, WALL_H, 1.5),
		CFrame = base * CFrame.new(0, WALL_H / 2, 0),
		Color = primary,
		Material = Enum.Material.ForceField,
		Transparency = 0.1,
		CanCollide = false,
		CastShadow = false,
		Tags = { "ZoneGate" },
		Parent = model,
	})
	barrier:SetAttribute("Zone", layout.Zone)
	Build.PointLight(barrier, primary, 1.6, 40)

	-- Terminal "Débloquer", côté zone parente (d'où l'on arrive)
	local terminalPos = layout.Gate - n * 10 + t * (half + 14)
	local terminalModel = Props.Terminal(
		model,
		"UnlockTerminal",
		CFrame.lookAt(terminalPos, terminalPos - n),
		primary,
		"Débloquer",
		zone.Name,
		"Unlock"
	)
	local prompt = terminalModel:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		prompt:SetAttribute("Zone", layout.Zone)
	end
end

local function buildWalls(world: Instance)
	local walls = Build.Model("Walls", world)
	walls.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local gates = Build.Model("Gates", world)
	gates.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- Portails posés sur un bord (entre zone et parent)
	local gatesOnEdges: { Vector3 } = {}
	for _, layout in L.Zones do
		table.insert(gatesOnEdges, layout.Gate)
	end

	local function edge(from: Vector3, to: Vector3)
		-- Découpe l'arête autour des portails qui s'y trouvent
		local dir = (to - from).Unit
		local length = (to - from).Magnitude
		local cuts: { number } = {}
		for _, gate in gatesOnEdges do
			local along = (gate - from):Dot(dir)
			local offset = ((gate - from) - dir * along).Magnitude
			if offset < 1 and along > 0 and along < length then
				table.insert(cuts, along)
			end
		end
		table.sort(cuts)
		local cursor = 0
		local half = L.GATE_WIDTH / 2 + 6
		for _, cut in cuts do
			glassWall(walls, from + dir * cursor, from + dir * (cut - half))
			cursor = cut + half
		end
		glassWall(walls, from + dir * cursor, to)
	end

	for row = 1, 3 do
		for col = 1, 3 do
			local zone = ZONE_OF_DISTRICT[row][col]
			local minX = L.MIN_X + (col - 1) * L.DISTRICT_X
			local minZ = L.MIN_Z + (row - 1) * L.DISTRICT_Z
			-- Bord est (vers la colonne suivante)
			if col < 3 and ZONE_OF_DISTRICT[row][col + 1] ~= zone then
				local x = minX + L.DISTRICT_X
				edge(Vector3.new(x, 0, minZ), Vector3.new(x, 0, minZ + L.DISTRICT_Z))
			end
			-- Bord sud (vers la ligne suivante)
			if row < 3 and ZONE_OF_DISTRICT[row + 1][col] ~= zone then
				local z = minZ + L.DISTRICT_Z
				edge(Vector3.new(minX, 0, z), Vector3.new(minX + L.DISTRICT_X, 0, z))
			end
		end
	end

	for _, layout in L.Zones do
		buildGate(gates, layout)
	end
end

------------------------------------------------------------------------------------
-- Gameplay commun d'une zone : machines, collecteur, téléporteur, terminal, fragments
------------------------------------------------------------------------------------

local TERMINALS: { [number]: { Name: string, Action: string, ActionText: string, Label: string, Color: Color3 } } = {
	[1] = {
		Name = "PowerTerminal",
		Action = "Power",
		ActionText = "Bloc d'alimentation",
		Label = "Capacité en Watts",
		Color = C.Gold,
	},
	[2] = {
		Name = "CapsuleTerminal",
		Action = "Capsules",
		ActionText = "Ouvrir",
		Label = "Capsules de Nanobots",
		Color = C.Violet,
	},
	[3] = {
		Name = "DownloadTerminal",
		Action = "Downloads",
		ActionText = "Télécharger",
		Label = "Téléchargements",
		Color = C.Cyan,
	},
	[4] = {
		Name = "CoolingTerminal",
		Action = "Cooling",
		ActionText = "Radiateurs",
		Label = "Capacité thermique",
		Color = C.Cyan,
	},
	[5] = {
		Name = "OverclockTerminal",
		Action = "Overclock",
		ActionText = "Overclocker",
		Label = "Station d'overclock",
		Color = C.Brand,
	},
	[6] = {
		Name = "RebootTerminal",
		Action = "Reboot",
		ActionText = "Reboot",
		Label = "Console BIOS",
		Color = C.Violet,
	},
	[7] = {
		Name = "SingularityTerminal",
		Action = "Singularity",
		ActionText = "Construire",
		Label = "La Singularité",
		Color = C.White,
	},
}

local function buildPlaza(model: Model, layout: WorldLayout.ZoneLayout, fragments: { Vector3 })
	local zone = Zones[layout.Zone]
	local primary, secondary = hex(zone.Primary), hex(zone.Secondary)

	-- Machines (3 modules) en arc face au portail
	local modules = Build.Model("Modules", model)
	for _, def in Modules.ForZone(layout.Zone) do
		local lateral = (def.Slot - 2) * 42
		local position = plazaPoint(layout, 104 - math.abs(lateral) * 0.25, lateral)
		Props.Machine(def, facingGate(layout, position), modules, primary, secondary)
	end

	-- Collecteur doré + pistes de données machine -> collecteur
	local collectorPos = plazaPoint(layout, 58, 0)
	local collector = Props.Pad(model, "Collector", CFrame.new(collectorPos), 16, C.Gold)
	collector:SetAttribute("Zone", layout.Zone)
	collector:AddTag("Collector")
	for _, def in Modules.ForZone(layout.Zone) do
		local lateral = (def.Slot - 2) * 42
		local from = plazaPoint(layout, 104 - math.abs(lateral) * 0.25, lateral) + Vector3.new(0, 0.15, 0)
		local to = collectorPos + Vector3.new(0, 0.15, 0)
		local trace = Build.Neon({
			Name = `Trace{def.Slot}`,
			Size = Vector3.new(1, 0.12, (to - from).Magnitude),
			CFrame = CFrame.lookAt((from + to) / 2, to),
			Color = primary:Lerp(C.Copper, 0.4),
			Transparency = 0.55,
			Tags = { "FloorTrace" },
			Parent = model,
		})
		trace:SetAttribute("Slot", def.Slot)
		trace:SetAttribute("Zone", layout.Zone)
	end

	-- Téléporteur + terminal de la zone
	local teleporter = Props.Pad(model, "Teleporter", CFrame.new(plazaPoint(layout, 42, -62)), 12, C.Cyan)
	Build.Prompt(teleporter, "Téléporteur", "Voyager", "Elevator", 12)
	local info = TERMINALS[layout.Zone]
	local terminalPos = plazaPoint(layout, 42, 62)
	Props.Terminal(
		model,
		info.Name,
		facingGate(layout, terminalPos),
		info.Color,
		info.ActionText,
		info.Label,
		info.Action
	)

	-- Éclairage de la plaza
	local lamp = Build.Decor({
		Name = "PlazaLight",
		Size = Vector3.one,
		CFrame = CFrame.new(plazaPoint(layout, 70, 0) + Vector3.new(0, 30, 0)),
		Transparency = 1,
		Parent = model,
	})
	Build.PointLight(lamp, primary, 1.4, 90)

	-- Fragments de données cachés
	local folder = Build.Folder("Fragments", model)
	for index, spot in fragments do
		local fragment = Build.Part({
			Name = `F{index}`,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.4, 2.4, 2.4),
			CFrame = CFrame.new(spot + Vector3.new(0, 3, 0)),
			Color = C.White,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = true,
			CastShadow = false,
			Tags = { "Fragment" },
			Parent = folder,
		})
		fragment:SetAttribute("FragmentId", `Z{layout.Zone}F{index}`)
		Build.PointLight(fragment, secondary, 1, 14)
	end
end

------------------------------------------------------------------------------------
-- Zones "héros" : les composants géants
------------------------------------------------------------------------------------

-- 1 · La Centrale : sous le cache d'alimentation, le bloc PSU géant
local function buildPsu(model: Model)
	local amber = hex(Zones[1].Primary)
	-- Cache d'alimentation (plafond bas) : nervures, lèvre avec logo, fentes d'aération lumineuses
	local shroudMinX, shroudMaxX = L.MIN_X, L.MIN_X + L.DISTRICT_X
	local shroudMinZ, shroudMaxZ = L.MAX_Z - L.DISTRICT_Z, L.MAX_Z
	local shroudZ = (shroudMinZ + shroudMaxZ) / 2
	solid(
		model,
		"PsuShroud",
		Vector3.new(shroudMaxX - shroudMinX, 4, shroudMaxZ - shroudMinZ),
		CFrame.new((shroudMinX + shroudMaxX) / 2, 92, shroudZ),
		C.Black,
		METAL
	)
	local lip = Box(
		model,
		"ShroudLip",
		Vector3.new(2, 8, shroudMaxZ - shroudMinZ),
		CFrame.new(shroudMaxX - 1, 86, shroudZ),
		C.Black,
		METAL
	)
	lip.CastShadow = true
	Props.Decal(
		model,
		"ShroudLogo",
		Vector3.new(0.2, 6, 150),
		CFrame.new(shroudMaxX + 0.15, 86.5, shroudZ),
		"ANGAINONE  ·  VOLTCORE",
		amber,
		Enum.NormalId.Right,
		Enum.Font.GothamBlack
	)
	neon(
		model,
		"ShroudEdge",
		Vector3.new(1.2, 1.2, shroudMaxZ - shroudMinZ),
		CFrame.new(shroudMaxX, 81.6, shroudZ),
		amber,
		0.2,
		{ "RgbStrip" }
	)
	for x = shroudMinX + 40, shroudMaxX - 40, 70 do
		neon(model, "ShroudVent", Vector3.new(40, 0.4, 3), CFrame.new(x, 89.8, shroudZ), amber, 0.3)
		for _, dz in { -70, 70 } do
			Box(model, "ShroudVentSlot", Vector3.new(40, 0.3, 2), CFrame.new(x, 89.85, shroudZ + dz), C.Bg)
		end
		Box(
			model,
			"ShroudRib",
			Vector3.new(3, 1.6, shroudMaxZ - shroudMinZ - 4),
			CFrame.new(x + 35, 89.2, shroudZ),
			C.MetalDark,
			METAL
		)
	end
	for _, x in { -440, -280 } do
		lamp(model, "ShroudLight", Vector3.new(x, 84, shroudZ), amber:Lerp(C.White, 0.4), 1.6, 130)
	end

	-- Le bloc d'alimentation : corps + cadre supérieur autour du ventilateur encastré
	local psu = Vector3.new(-360, 0, 300)
	solid(model, "PsuBox", Vector3.new(250, 64, 170), CFrame.new(psu + Vector3.new(0, 32, 0)), C.Black, METAL)
	local hole = 132
	local sideX = (250 - hole) / 2
	local sideZ = (170 - hole) / 2
	for _, side in { -1, 1 } do
		solid(
			model,
			"PsuTop",
			Vector3.new(sideX, 12, 170),
			CFrame.new(psu + Vector3.new(side * (hole + sideX) / 2, 70, 0)),
			C.Black,
			METAL
		)
		solid(
			model,
			"PsuTop",
			Vector3.new(hole, 12, sideZ),
			CFrame.new(psu + Vector3.new(0, 70, side * (hole + sideZ) / 2)),
			C.Black,
			METAL
		)
	end
	-- On marche sur la grille : plancher invisible au ras du dessus
	local floor =
		solid(model, "GrilleFloor", Vector3.new(hole, 1, hole), CFrame.new(psu + Vector3.new(0, 75.5, 0)), C.Black)
	floor.Transparency = 1
	-- Ventilateur 135 mm encastré + grille nid d'abeille
	Props.Fan(model, CFrame.new(psu + Vector3.new(0, 62, 0)) * UP, 120, amber, 9, { Light = true, Brand = "VOLTCORE" })
	Props.Grille(model, CFrame.new(psu + Vector3.new(0, 76.6, 0)) * UP, 63, 9, 1.2, C.MetalLight)
	neon(
		model,
		"PsuStripe",
		Vector3.new(251, 1.2, 1.2),
		CFrame.new(psu + Vector3.new(0, 70, -85.5)),
		amber,
		0.2,
		{ "RgbStrip" }
	)

	-- Étiquette de certification (face nord)
	local north = psu.Z - 85
	Box(model, "RatingSticker", Vector3.new(84, 46, 0.3), CFrame.new(-425, 34, north - 0.2), C.Silk)
	local title = Box(model, "RatingTitle", Vector3.new(78, 9, 0.2), CFrame.new(-425, 50, north - 0.4), C.Black)
	Props.Label(title, "VOLTCORE  2000W", amber, Enum.NormalId.Front, Enum.Font.GothamBlack)
	local badge = Box(
		model,
		"RatingBadge",
		Vector3.new(22, 24, 0.2),
		CFrame.new(-451, 29, north - 0.4),
		C.Gold:Lerp(C.White, 0.3),
		FOIL
	)
	Props.Label(badge, "80+\nTITANIUM", C.Black, Enum.NormalId.Front, Enum.Font.GothamBlack)
	local specs = Box(model, "RatingSpecs", Vector3.new(50, 24, 0.2), CFrame.new(-411, 29, north - 0.4), C.Silk)
	Props.Label(
		specs,
		"AC 100-240V ~ 16A\n+12V  166A\n+5V 25A   +3.3V 25A",
		C.Black,
		Enum.NormalId.Front,
		Enum.Font.Code
	)
	-- Ouïes d'aération (face nord, à droite de l'étiquette)
	for row = 0, 2 do
		for col = 0, 4 do
			Box(
				model,
				"PsuVent",
				Vector3.new(18, 2.4, 0.3),
				CFrame.new(-362 + col * 24, 22 + row * 12, north - 0.15),
				C.Bg
			)
		end
	end
	-- Prise secteur C14 + interrupteur (face ouest)
	local west = psu.X - 125
	Box(model, "AcInlet", Vector3.new(1.2, 16, 22), CFrame.new(west - 0.6, 30, 320), C.Bg)
	for k = -1, 1 do
		Box(
			model,
			"AcPin",
			Vector3.new(1.4, 3, 1.4),
			CFrame.new(west - 0.8, 30 + (if k == 0 then 3 else -2), 320 + k * 6),
			C.Nickel,
			METAL
		)
	end
	local switch = Box(model, "PowerSwitch", Vector3.new(1.6, 10, 8), CFrame.new(west - 0.8, 30, 296), C.Black)
	Props.Label(switch, "I  O", amber, Enum.NormalId.Left, Enum.Font.GothamBold)

	-- Panneau modulaire (face est) : prises gainées + sérigraphie
	local east = psu.X + 125
	Box(model, "ModularPanel", Vector3.new(0.6, 60, 150), CFrame.new(east + 0.3, 34, 300), C.MetalDark, METAL)
	Props.Decal(
		model,
		"PsuBrand",
		Vector3.new(0.2, 7, 50),
		CFrame.new(east + 0.15, 71, 251),
		"VOLTCORE",
		amber,
		Enum.NormalId.Right,
		Enum.Font.GothamBlack
	)
	Props.Decal(
		model,
		"PsuBrand",
		Vector3.new(0.2, 7, 50),
		CFrame.new(east + 0.15, 71, 349),
		"2000W  TITANIUM",
		amber,
		Enum.NormalId.Right,
		Enum.Font.GothamBlack
	)
	local function socket(label: string, z: number, y: number, width: number, height: number)
		Box(model, "Socket", Vector3.new(2.4, height, width), CFrame.new(east + 1.2, y, z), C.Black)
		Box(model, "SocketPins", Vector3.new(2.5, height * 0.62, width * 0.8), CFrame.new(east + 1.25, y, z), C.Bg)
		Box(
			model,
			"SocketLatch",
			Vector3.new(2.8, 1.2, width * 0.3),
			CFrame.new(east + 1.4, y + height / 2 + 0.6, z),
			C.Black
		)
		Props.Decal(
			model,
			"SocketSilk",
			Vector3.new(0.2, 3, width + 6),
			CFrame.new(east + 0.7, y + height / 2 + 3, z),
			label,
			C.Silk,
			Enum.NormalId.Right,
			Enum.Font.Code
		)
	end
	socket("ATX 24", 250, 50, 22, 16)
	socket("CPU 1", 240, 28, 12, 10)
	socket("CPU 2", 260, 28, 12, 10)
	socket("SATA", 240, 12, 12, 7)
	socket("PERIF", 260, 12, 12, 7)
	socket("12V-2x6", 330, 60, 20, 10)
	socket("PCIe 1", 330, 42, 16, 9)
	socket("PCIe 2", 330, 24, 16, 9)
	socket("SATA", 358, 42, 12, 7)
	socket("SATA", 358, 24, 12, 7)
	-- Câbles gainés (tresse) qui filent au sol vers la carte mère, tenus par des peignes
	local starts = {
		Vector3.new(east + 2, 28, 237),
		Vector3.new(east + 2, 28, 243),
		Vector3.new(east + 2, 28, 257),
		Vector3.new(east + 2, 28, 263),
		Vector3.new(east + 2, 12, 240),
		Vector3.new(east + 2, 12, 260),
	}
	for i, start in starts do
		local lane = -200 + (i - 1) * 7
		Props.Cable(model, {
			start,
			start + Vector3.new(16, -4, 0),
			Vector3.new(lane, 3, 212),
			Vector3.new(lane, 3, 160),
		}, 2.2, if i % 2 == 0 then C.Black else C.Brand)
	end
	for _, z in { 196, 176 } do
		Box(model, "CableComb", Vector3.new(44, 5.4, 2.4), CFrame.new(-182.5, 3, z), C.Black:Lerp(amber, 0.25))
	end

	-- Rampe pour monter sur le PSU (côté est : 76 studs de dénivelé sur ~150), bords lumineux
	local rise, run = 76, 150
	local rampCf = CFrame.new(psu.X + 125 + run / 2, rise / 2, psu.Z) * CFrame.Angles(0, 0, -math.atan2(rise, run))
	local rampLength = math.sqrt(rise * rise + run * run) + 2
	Build.Part({
		Name = "Ramp",
		Size = Vector3.new(rampLength, 2, 40),
		CFrame = rampCf,
		Color = C.MetalLight,
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		neon(
			model,
			"RampEdge",
			Vector3.new(rampLength, 0.6, 0.6),
			rampCf * CFrame.new(0, 1.3, side * 19.6),
			amber,
			0.25
		)
	end
	-- Forêt de condensateurs
	for i = 0, 5 do
		Props.Capacitor(model, Vector3.new(-120 + i * 14, 0, 400), 5, 22, C.Black, amber)
	end
end

-- 2 · Memory Lanes : 4 barrettes-gratte-ciels
local function buildRam(model: Model)
	local violet = hex(Zones[2].Primary)
	local lilac = hex(Zones[2].Secondary)
	local lengthZ = 200
	for index, x in { 336, 382, 428, 474 } do
		-- Slot DIMM : boîtier noir, fente à contacts dorés, détrompeur
		solid(model, "DimmSlot", Vector3.new(14, 6, lengthZ + 16), CFrame.new(x, 3, 0), C.Black)
		Box(model, "SlotGroove", Vector3.new(5, 0.2, lengthZ + 4), CFrame.new(x, 6.05, 0), C.Bg)
		Box(model, "SlotContacts", Vector3.new(3.4, 0.25, lengthZ), CFrame.new(x, 6.1, 0), C.Gold, FOIL)
		Box(model, "SlotKey", Vector3.new(5.4, 0.5, 3), CFrame.new(x, 6.15, 30), C.Black)
		-- Loquets aux deux bouts (corps + levier incliné + stries)
		for _, side in { -1, 1 } do
			local z = side * (lengthZ / 2 + 6)
			solid(model, "Latch", Vector3.new(12, 14, 6), CFrame.new(x, 7, z), C.White)
			Wedge(
				model,
				"LatchLever",
				Vector3.new(12, 6, 6),
				CFrame.new(x, 17, z) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
				C.White
			)
			for g = 0, 2 do
				Box(model, "LatchGrip", Vector3.new(12.2, 0.6, 0.6), CFrame.new(x, 9 + g * 2, z + side * 3), C.Silk)
			end
		end
		-- PCB + contacts dorés visibles au ras du slot (encoche détrompeur)
		solid(model, "DimmPcb", Vector3.new(2, 121, lengthZ), CFrame.new(x, 3 + 121 / 2, 0), C.PcbDark)
		for f = 0, 19 do
			local z = -lengthZ / 2 + 6 + f * ((lengthZ - 12) / 19)
			if math.abs(z - 30) > 4 then
				Box(model, "Finger", Vector3.new(0.3, 3.4, 6), CFrame.new(x - 1.1, 7.8, z), C.Gold, FOIL)
			end
		end
		Box(model, "FingerBand", Vector3.new(0.3, 3.4, lengthZ - 8), CFrame.new(x + 1.1, 7.8, 0), C.Gold, FOIL)
		-- Puces DRAM sur les deux faces (sous le dissipateur)
		for c = 0, 7 do
			local z = -lengthZ / 2 + 14 + c * ((lengthZ - 28) / 7)
			for _, side in { -1, 1 } do
				Box(model, "DramChip", Vector3.new(1, 8, 18), CFrame.new(x + side * 1.5, 15, z), C.Bg)
			end
		end
		Box(model, "Pmic", Vector3.new(1, 5, 8), CFrame.new(x - 1.5, 14, 82), C.Black)
		-- Dissipateurs : flancs métal, étiquettes, barres lumineuses diagonales
		local spreaderColor = if index % 2 == 0 then C.MetalDark else C.Aluminum
		for _, side in { -1, 1 } do
			solid(
				model,
				"HeatSpreader",
				Vector3.new(3, 96, lengthZ - 4),
				CFrame.new(x + side * 2.5, 68, 0),
				spreaderColor,
				METAL
			)
			local face = if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left
			local faceX = x + side * 4.25
			-- Bicolore : bas sombre, séparation en diagonale sur toute la longueur
			local accent = C.Black:Lerp(violet, 0.08)
			Box(
				model,
				"SpreaderTone",
				Vector3.new(0.2, 30, lengthZ - 4),
				CFrame.new(x + side * 4.1, 35, 0),
				accent,
				METAL
			)
			Wedge(
				model,
				"SpreaderSplit",
				Vector3.new(0.2, 20, lengthZ - 4),
				CFrame.new(x + side * 4.1, 60, 0),
				accent,
				METAL
			)
			Props.Decal(
				model,
				"DimmLabel",
				Vector3.new(0.2, 16, 84),
				CFrame.new(faceX, 84, -48),
				"KRYO  DDR6",
				violet,
				face,
				Enum.Font.GothamBlack
			)
			Props.Decal(
				model,
				"DimmSpec",
				Vector3.new(0.2, 6, 60),
				CFrame.new(faceX, 66, -48),
				"32GB  8000 MT/s  CL30",
				C.Silk,
				face,
				Enum.Font.Code
			)
			for k = 0, 2 do
				neon(
					model,
					"LightPipe",
					Vector3.new(0.4, 2.2, 70),
					CFrame.new(faceX, 58 + k * 14, 52) * CFrame.Angles(math.rad(side * 32), 0, 0),
					if k == 1 then lilac else violet,
					0.25
				)
			end
		end
		-- Couronne sculptée : diffuseur RGB + ailettes de hauteurs inégales
		neon(model, "DimmRgb", Vector3.new(6, 5, lengthZ - 8), CFrame.new(x, 118.5, 0), violet, 0.15, { "RgbStrip" })
		for f = 0, 8 do
			local h = 4 + (f % 3) * 3
			local z = -lengthZ / 2 + 12 + f * ((lengthZ - 24) / 8)
			Box(
				model,
				"Crest",
				Vector3.new(8.4, 5 + h, 12),
				CFrame.new(x, 116 + (5 + h) / 2, z),
				spreaderColor:Lerp(violet, 0.1),
				METAL
			)
		end
	end
	-- Lumière entre les barrettes (avenues)
	for _, x in { 359, 451 } do
		lamp(model, "LaneLight", Vector3.new(x, 20, 0), violet, 1.6, 80)
	end
end

-- 3 · Data Vault : cage de SSD SATA en tiroirs + SSD NVMe M.2 géants au sol
local function buildSsd(model: Model)
	local teal = hex(Zones[3].Primary)
	local cageX = -470
	solid(model, "CageBack", Vector3.new(4, 150, 240), CFrame.new(-535, 75, 0), C.MetalDark, METAL)
	for _, z in { -122, 122 } do
		local s = if z > 0 then 1 else -1
		solid(model, "CageSide", Vector3.new(140, 150, 4), CFrame.new(cageX, 75, z), C.MetalDark, METAL)
		for k = 0, 4 do
			Box(model, "CageVent", Vector3.new(8, 100, 0.3), CFrame.new(cageX - 44 + k * 22, 80, z + s * 2.1), C.Bg)
		end
		Box(model, "CagePost", Vector3.new(6, 152, 7), CFrame.new(-401, 76, z), C.Aluminum, METAL)
		neon(model, "CagePostGlow", Vector3.new(0.6, 140, 1), CFrame.new(-397.8, 76, z - s * 1.5), teal, 0.25)
	end
	Box(model, "CageTop", Vector3.new(144, 4, 250), CFrame.new(cageX, 152, 0), C.MetalDark, METAL)
	Props.Decal(
		model,
		"CageLogo",
		Vector3.new(0.2, 8, 120),
		CFrame.new(-398.8, 142, 0),
		"NOVADRIVE  RAID ARRAY",
		teal,
		Enum.NormalId.Right,
		Enum.Font.GothamBlack
	)
	Box(model, "CageLintel", Vector3.new(2, 10, 240), CFrame.new(-399.9, 142, 0), C.Black, METAL)

	for level = 0, 4 do
		local y = 14 + level * 28
		for _, z in { -117, 117 } do
			Box(model, "Rail", Vector3.new(136, 2, 6), CFrame.new(cageX, y - 9, z), C.Aluminum, METAL)
		end
		-- SSD SATA 2,5" dans son tiroir : façade, poignée, LED d'activité, connecteurs
		solid(
			model,
			"Ssd",
			Vector3.new(120, 16, 200),
			CFrame.new(cageX - 2, y, 0),
			if level % 2 == 0 then C.Black else C.MetalDark
		)
		Box(model, "DriveBezel", Vector3.new(2, 17, 226), CFrame.new(-410, y, 0), C.MetalDark, METAL)
		Props.Decal(
			model,
			"DriveLabel",
			Vector3.new(0.2, 9, 80),
			CFrame.new(-408.9, y + 1, -50),
			`NOVADRIVE  {level + 1}TB`,
			teal,
			Enum.NormalId.Right,
			Enum.Font.GothamBold
		)
		Box(model, "Handle", Vector3.new(2, 3, 60), CFrame.new(-406, y - 4, 30), C.Aluminum, METAL)
		for _, dz in { 2, 58 } do
			Box(model, "HandleArm", Vector3.new(3, 3, 2), CFrame.new(-407.5, y - 4, dz), C.Aluminum, METAL)
		end
		neon(model, "ActivityLed", Vector3.new(1, 3, 8), CFrame.new(-408.6, y + 4, 75), teal, 0.1, { "PulseGlow" })
		Box(model, "SataData", Vector3.new(3, 6, 10), CFrame.new(-407.5, y - 1, 92), C.Black)
		Box(model, "SataPower", Vector3.new(3, 6, 12), CFrame.new(-407.5, y - 1, 105), C.Black)
		-- Nappe SATA rouge jusqu'au sol, puis vers les ports SATA du hub (sous la cloison)
		-- (descentes décalées pour que les nappes ne se croisent pas)
		local drop, lane = -390 - level * 2.6, 96 + level * 4
		ribbon(model, {
			Vector3.new(-405.5, y - 1, 92),
			Vector3.new(drop, y - 1, 92),
			Vector3.new(drop, 0.35, 92),
			Vector3.new(drop, 0.35, lane),
			Vector3.new(-186, 0.35, lane),
		}, 2.4, C.Brand)
	end

	-- SSD NVMe M.2 posés au sol (sur entretoise) : un nu (puces visibles), un sous dissipateur
	local function m2(z: number, withHeatsink: boolean)
		local x0, length = -395, 90
		local cx = x0 + length / 2
		local towardPlaza = if z < 0 then Enum.NormalId.Back else Enum.NormalId.Front
		local edgeZ = if z < 0 then z + 11.9 else z - 11.9
		solid(model, "M2Slot", Vector3.new(8, 6, 28), CFrame.new(x0 - 3, 3, z), C.Black)
		Box(model, "M2Fingers", Vector3.new(3, 0.7, 20), CFrame.new(x0 + 0.5, 4, z), C.Gold, FOIL)
		solid(model, "M2Pcb", Vector3.new(length, 1, 24), CFrame.new(cx, 4, z), C.Black:Lerp(C.Pcb, 0.4))
		Rod(model, "M2Standoff", CFrame.new(x0 + length - 4, 1.75, z) * UP, 3.5, 5, C.Gold, METAL)
		screwHead(model, CFrame.new(x0 + length - 4, 4.4, z), 5)
		local controller = Box(model, "Controller", Vector3.new(10, 1.4, 10), CFrame.new(x0 + 12, 5.2, z), C.Bg)
		Props.Label(controller, "NOVA E26", C.Silk, Enum.NormalId.Top, Enum.Font.Code)
		Box(model, "Dram", Vector3.new(6, 1.2, 9), CFrame.new(x0 + 23, 5.1, z), C.Bg)
		Box(model, "Pmic", Vector3.new(3, 1, 3), CFrame.new(x0 + 5, 5, z + 7), C.Black)
		for k = 0, 1 do
			local nand = Box(model, "Nand", Vector3.new(16, 1.4, 18), CFrame.new(x0 + 38 + k * 22, 5.2, z), C.Bg)
			Props.Label(nand, "NAND 2TB", C.Silk, Enum.NormalId.Top, Enum.Font.Code)
		end
		if withHeatsink then
			local sink = solid(
				model,
				"M2Heatsink",
				Vector3.new(56, 4, 23),
				CFrame.new(x0 + 49, 6.8, z),
				C.Aluminum:Lerp(C.MetalDark, 0.25),
				METAL
			)
			Props.Label(sink, "NOVADRIVE GEN5", teal, towardPlaza, Enum.Font.GothamBlack)
			for f = 0, 9 do
				Box(
					model,
					"M2Fin",
					Vector3.new(1.6, 2.4, 23),
					CFrame.new(x0 + 24.5 + f * 5.4, 10, z),
					C.MetalDark,
					METAL
				)
			end
			neon(model, "M2Glow", Vector3.new(56, 0.6, 0.4), CFrame.new(x0 + 49, 4.9, edgeZ), teal, 0.2)
		else
			local sticker = Box(model, "M2Sticker", Vector3.new(12, 0.2, 20), CFrame.new(x0 + 76, 4.6, z), C.Silk)
			Props.Label(sticker, "NOVADRIVE\n4TB NVMe", C.Black, Enum.NormalId.Top, Enum.Font.GothamBold)
			neon(model, "M2Glow", Vector3.new(length, 0.4, 0.4), CFrame.new(cx, 3.6, edgeZ), teal, 0.3)
		end
		silkText(
			model,
			if withHeatsink then "M.2_2" else "M.2_1",
			Vector3.new(x0 - 3, 0, z + (if z < 0 then 19 else -19)),
			12,
			5
		)
	end
	m2(-75, false)
	m2(75, true)
	lamp(model, "VaultLight", Vector3.new(-400, 60, 0), teal, 2, 120)
end

-- 4 · Cryo Tower : radiateur 240 frontal + ventilateurs, pompe-réservoir, tubes rigides
local function buildCooling(model: Model)
	local ice = hex(Zones[4].Primary)
	local frost = hex(Zones[4].Secondary)
	-- Radiateur contre la façade (paroi ouest) : faisceau d'ailettes, tubes plats, boîtes à eau
	local radX = L.MIN_X + 7 -- centre en X (épaisseur 14)
	local zMin, zMax = -410, -170
	local coreMin, coreMax = zMin + 12, zMax - 12
	local coreZ = (coreMin + coreMax) / 2
	Box(
		model,
		"RadCore",
		Vector3.new(14, 100, coreMax - coreMin),
		CFrame.new(radX, 70, coreZ),
		C.MetalDark:Lerp(C.Aluminum, 0.45),
		METAL
	)
	for k = 0, 11 do
		Box(
			model,
			"RadTube",
			Vector3.new(14.6, 1.2, coreMax - coreMin),
			CFrame.new(radX, 24 + k * 8.4, coreZ),
			C.Aluminum,
			METAL
		)
	end
	for _, y in { 17.5, 122.5 } do
		Box(model, "RadRail", Vector3.new(15, 5, coreMax - coreMin), CFrame.new(radX, y, coreZ), C.Black, METAL)
	end
	Props.Decal(
		model,
		"RadLogo",
		Vector3.new(0.2, 7, 160),
		CFrame.new(L.MIN_X + 0.2, 134, coreZ),
		"GLACIER 240  ·  FROSTBYTE",
		ice,
		Enum.NormalId.Right,
		Enum.Font.GothamBlack
	)
	for _, z in { zMin + 6, zMax - 6 } do
		Box(model, "RadTank", Vector3.new(16, 112, 12), CFrame.new(radX + 1, 70, z), C.Black, METAL)
	end
	-- 2 ventilateurs vissés sur le radiateur (soufflent vers l'intérieur)
	for _, z in { coreZ - 54, coreZ + 54 } do
		Props.Fan(model, CFrame.new(L.MIN_X + 14, 70, z), 100, ice, 9, { Rgb = true, Brand = "FROSTBYTE" })
	end
	-- Raccords chromés sur les boîtes à eau
	local inlet = Vector3.new(L.MIN_X + 20, 40, zMin + 6)
	local outlet = Vector3.new(L.MIN_X + 20, 110, zMax - 6)
	for _, fitting in { inlet, outlet } do
		Rod(model, "TankFitting", CFrame.new(fitting - Vector3.new(2, 0, 0)), 4, 8, C.Nickel)
	end

	-- Pompe + réservoir (verre, liquide lumineux, tube de remplissage, cage à colonnettes)
	local res = Vector3.new(-300, 0, -370)
	Build.Cylinder({
		Name = "PumpBase",
		Size = Vector3.new(14, 44, 44),
		CFrame = CFrame.new(res + Vector3.new(0, 7, 0)) * UP,
		Color = C.Black,
		Material = METAL,
		Parent = model,
	})
	neon(
		model,
		"PumpRing",
		Vector3.new(0.8, 45, 45),
		CFrame.new(res + Vector3.new(0, 12, 0)) * UP,
		ice,
		0.3,
		{ "RgbStrip" }
	).Shape =
		Enum.PartType.Cylinder
	local lcd = Box(
		model,
		"PumpLcd",
		Vector3.new(14, 7, 0.5),
		CFrame.new(res + Vector3.new(0, 6, 22.1)),
		C.Bg,
		Enum.Material.Glass
	)
	Props.Label(lcd, "24°C", ice, Enum.NormalId.Back, Enum.Font.GothamBlack)
	Rod(model, "PumpCollar", CFrame.new(res + Vector3.new(0, 15.5, 0)) * UP, 3, 39, C.MetalDark)
	Build.Cylinder({
		Name = "Reservoir",
		Size = Vector3.new(88, 36, 36),
		CFrame = CFrame.new(res + Vector3.new(0, 61, 0)) * UP,
		Color = Color3.fromRGB(210, 235, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		CastShadow = false,
		Parent = model,
	})
	local coolant = Build.Neon({
		Name = "Coolant",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(70, 30, 30),
		CFrame = CFrame.new(res + Vector3.new(0, 52, 0)) * UP,
		Color = ice,
		Transparency = 0.35,
		Tags = { "PulseGlow" },
		Parent = model,
	})
	Build.PointLight(coolant, ice, 2.5, 90)
	Rod(model, "FillTube", CFrame.new(res + Vector3.new(0, 60, 0)) * UP, 84, 4, C.White, Enum.Material.Glass).Transparency =
		0.4
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + math.pi / 6
		Rod(
			model,
			"ResPost",
			CFrame.new(res + Vector3.new(math.cos(a) * 20, 61, math.sin(a) * 20)) * UP,
			88,
			2,
			C.Nickel
		)
	end
	local cap = Build.Cylinder({
		Name = "ResCap",
		Size = Vector3.new(5, 42, 42),
		CFrame = CFrame.new(res + Vector3.new(0, 107.5, 0)) * UP,
		Color = C.Black,
		Material = METAL,
		Parent = model,
	})
	Props.Label(cap, "CRYO", ice, Enum.NormalId.Right, Enum.Font.GothamBlack)
	neon(model, "CapGlow", Vector3.new(0.8, 42.6, 42.6), CFrame.new(res + Vector3.new(0, 104.6, 0)) * UP, frost, 0.25).Shape =
		Enum.PartType.Cylinder
	-- Tubes rigides (coudes à 90°) : pompe -> radiateur, radiateur -> haut du réservoir
	Props.Tube(model, {
		res + Vector3.new(-22, 8, 0),
		res + Vector3.new(-45, 8, 0),
		res + Vector3.new(-45, 40, 0),
		Vector3.new(res.X - 45, 40, inlet.Z),
		inlet,
	}, 3, ice)
	Props.Tube(model, {
		outlet,
		Vector3.new(L.MIN_X + 35, 110, outlet.Z),
		Vector3.new(L.MIN_X + 35, 124, outlet.Z),
		Vector3.new(res.X, 124, outlet.Z),
		Vector3.new(res.X, 124, res.Z),
		res + Vector3.new(0, 110, 0),
	}, 3, ice)
	-- Brume froide
	local mist = Build.Decor({
		Name = "Mist",
		Size = Vector3.new(60, 1, 200),
		CFrame = CFrame.new(L.MIN_X + 70, 2, -300),
		Transparency = 1,
		Parent = model,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 6
	emitter.Lifetime = NumberRange.new(6, 9)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 22) })
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(ice:Lerp(C.White, 0.6))
	emitter.LightEmission = 0.3
	emitter.EmissionDirection = Enum.NormalId.Right
	emitter.Parent = mist
end

-- 5 · The Core : socket LGA, ventirad tour à caloducs en U (push-pull), dissipateurs VRM
local function buildCpu(model: Model)
	local gold = hex(Zones[5].Primary)
	local center = Vector3.new(0, 0, -335)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(center + Vector3.new(x, y, z))
	end
	-- Socket : champ de broches (grille dorée), cadre de rétention (ILM) + levier
	solid(model, "Socket", Vector3.new(120, 3, 120), at(0, 1.5, 0), C.Black)
	Box(model, "PinField", Vector3.new(100, 0.1, 100), at(0, 3.05, 0), C.Gold:Lerp(C.Black, 0.45), FOIL)
	for k = -6, 6 do
		Box(model, "PinRow", Vector3.new(100, 0.2, 0.5), at(0, 3.1, k * 8), C.Bg)
		Box(model, "PinRow", Vector3.new(0.5, 0.2, 100), at(k * 8, 3.1, 0), C.Bg)
	end
	for _, side in { -1, 1 } do
		solid(model, "LoadPlate", Vector3.new(108, 2, 5), at(0, 4, side * 52), C.Nickel, METAL)
	end
	solid(model, "LoadHinge", Vector3.new(5, 3, 108), at(-54, 4.5, 0), C.Nickel, METAL)
	Rod(model, "Lever", at(58, 4, 0) * CFrame.Angles(0, math.pi / 2, 0), 110, 2.4, C.Nickel)
	Rod(model, "LeverHook", at(53, 4, -55), 10, 2.4, C.Nickel)
	Rod(
		model,
		"LeverGrip",
		at(58, 4, 56) * CFrame.Angles(0, math.pi / 2, 0),
		8,
		4,
		C.Black,
		Enum.Material.SmoothPlastic
	)
	-- Processeur : substrat + IHS gravé
	solid(model, "Substrate", Vector3.new(76, 1.5, 76), at(0, 3.75, 0), C.Pcb:Lerp(C.Gold, 0.1))
	Wedge(model, "Pin1Marker", Vector3.new(0.3, 6, 6), at(-35, 4.6, -35) * UP, C.Gold, FOIL)
	local ihs = solid(model, "Ihs", Vector3.new(60, 3.5, 60), at(0, 6.25, 0), C.Nickel, METAL)
	Props.Label(ihs, "HELION X-CORE", gold, Enum.NormalId.Front, Enum.Font.GothamBlack)
	-- Semelle en cuivre + étrier de fixation à molettes
	solid(model, "ColdPlate", Vector3.new(56, 6, 56), at(0, 11, 0), C.Copper, METAL).Reflectance = 0.1
	for _, z in { -20, 20 } do
		Box(model, "MountBar", Vector3.new(136, 2, 6), at(0, 15, z), C.MetalLight, METAL)
		for _, x in { -64, 64 } do
			Rod(model, "Standoff", at(x, 7, z) * UP, 14, 3, C.Nickel)
			Rod(model, "Thumbscrew", at(x, 17, z) * UP, 3, 7, C.Black)
		end
	end
	-- Caloducs en U : base dans la semelle, deux jambes qui montent dans les ailettes
	for k, a in { 14, 24, 34, 44 } do
		local z = if k % 2 == 0 then 8 else -8
		Props.Cable(model, {
			center + Vector3.new(-a, 156, z),
			center + Vector3.new(-a, 11, z),
			center + Vector3.new(a, 11, z),
			center + Vector3.new(a, 156, z),
		}, 2.6, C.Copper, METAL)
		for _, x in { -a, a } do
			Rod(model, "PipeCap", at(x, 156.5, z) * UP, 1.2, 6.4, C.Nickel)
		end
	end
	-- Pile d'ailettes horizontales (on marche dessous), capot à facettes + logo
	Props.Fins(
		model,
		CFrame.lookAt(center + Vector3.new(0, 110, 0), center + Vector3.new(0, 111, 0), Vector3.zAxis),
		130,
		70,
		80,
		36,
		C.Aluminum,
		true
	)
	local coverY = 152
	local coolerTop = solid(model, "CoolerTop", Vector3.new(132, 4, 60), at(0, coverY, 0), C.Black, METAL)
	Props.Label(coolerTop, "HELION  X-CORE", gold, Enum.NormalId.Top, Enum.Font.GothamBlack)
	for _, side in { -1, 1 } do
		Wedge(
			model,
			"CoverFacet",
			Vector3.new(132, 4, 6),
			at(0, coverY, side * 33) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			C.Black,
			METAL
		)
		neon(model, "CoverGlow", Vector3.new(132, 0.6, 0.6), at(0, coverY - 2.2, side * 36), gold, 0.2, { "RgbStrip" })
	end
	-- Ventilateurs push-pull (80) sur les faces sud et nord de la tour
	Props.Fan(model, at(0, 110, 35) * CFrame.Angles(0, -math.pi / 2, 0), 80, gold, 9, { Brand = "HELION" })
	Props.Fan(model, at(0, 110, -35) * CFrame.Angles(0, math.pi / 2, 0), 80, gold, 9, { Brand = "HELION" })
	-- Dissipateurs VRM : bloc + lamelles, capots biseautés, logo, liseré côté socket
	local function vrmSink(cf: CFrame, length: number)
		solid(model, "VrmHeatsink", Vector3.new(length, 22, 20), cf * CFrame.new(0, 11, 0), C.MetalDark, METAL)
		for k = -3, 3 do
			Box(model, "VrmFin", Vector3.new(length - 8, 12, 1.2), cf * CFrame.new(0, 28, k * 2.8), C.MetalLight, METAL)
		end
		for _, side in { -1, 1 } do
			Wedge(
				model,
				"VrmCap",
				Vector3.new(20, 14, 12),
				cf * CFrame.new(side * (length / 2 - 6), 29, 0) * CFrame.Angles(0, -side * math.pi / 2, 0),
				C.Black,
				METAL
			)
		end
		local plate = Box(model, "VrmPlate", Vector3.new(44, 1, 16), cf * CFrame.new(0, 34.5, 0), C.Black, METAL)
		Props.Label(plate, "HELION VRM", gold, Enum.NormalId.Top, Enum.Font.GothamBlack)
		neon(model, "VrmGlow", Vector3.new(length, 0.8, 0.5), cf * CFrame.new(0, 20, 10.2), gold, 0.25)
	end
	vrmSink(CFrame.new(0, 0, -405), 220)
	vrmSink(CFrame.new(-160, 0, -300) * CFrame.Angles(0, math.pi / 2, 0), 200)
	-- Connecteur EPS 8 broches + câble tressé qui sort par le passe-câble du haut du boîtier
	local eps = Vector3.new(-135, 0, -408)
	solid(model, "EpsHeader", Vector3.new(14, 8, 10), CFrame.new(eps + Vector3.new(0, 4, 0)), C.Black)
	local plug = Box(model, "EpsPlug", Vector3.new(14.4, 4, 10.4), CFrame.new(eps + Vector3.new(0, 10, 0)), C.Black)
	Props.Label(plug, "CPU 8", C.Silk, Enum.NormalId.Top, Enum.Font.Code)
	Box(model, "EpsLatch", Vector3.new(4, 3, 1), CFrame.new(eps + Vector3.new(0, 9, 5.6)), C.Black)
	silkText(model, "CPU_PWR1", eps + Vector3.new(0, 0, 10), 18, 4)
	Props.Cable(model, {
		eps + Vector3.new(0, 12, 0),
		eps + Vector3.new(0, 30, -4),
		Vector3.new(-150, 40, L.MIN_Z + 2),
	}, 2.5, C.Black)
	lamp(model, "CoreLight", center + Vector3.new(0, 40, 0), gold, 2.2, 110)
end

-- 6 · Render Canyon : la carte graphique géante et le canyon derrière elle
local function buildGpu(model: Model)
	local green = hex(Zones[6].Primary)
	local magenta = hex(Zones[6].Secondary)
	local z = 348
	local x0, x1 = 195, 525
	local cx = (x0 + x1) / 2
	-- Slot PCIe x16 blindé (gaine métal) + loquet
	solid(model, "PcieSlot", Vector3.new(302, 8.4, 13), CFrame.new(360, 4.2, z), C.Aluminum, METAL)
	Box(model, "PcieSlotTop", Vector3.new(296, 0.3, 6), CFrame.new(360, 8.5, z), C.Black)
	Box(model, "PcieLatch", Vector3.new(6, 10, 13), CFrame.new(513, 5, z), C.Black)
	Wedge(
		model,
		"PcieLatchLever",
		Vector3.new(13, 4, 6),
		CFrame.new(513, 12, z) * CFrame.Angles(0, -math.pi / 2, 0),
		C.Black
	)
	silkText(model, "PCIEX16_1", Vector3.new(260, 0, z + 12), 30, 5)
	-- Carte : PCB + contacts dorés, bloc d'ailettes, carénage à facettes, backplate
	solid(model, "GpuPcb", Vector3.new(320, 122, 3), CFrame.new(360, 69, z), C.PcbDark)
	Box(model, "GpuFingers", Vector3.new(280, 2.5, 0.3), CFrame.new(360, 9.5, z + 1.6), C.Gold, FOIL)
	solid(
		model,
		"HeatsinkCore",
		Vector3.new(x1 - x0 - 4, 118, 24),
		CFrame.new(cx, 69, 334),
		C.MetalDark:Lerp(C.Aluminum, 0.35),
		METAL
	)
	-- Carénage avant (z 308..322) : bandeaux haut/bas + montants entre les ventilateurs
	local front = 315
	solid(model, "Shroud", Vector3.new(x1 - x0, 14, 14), CFrame.new(cx, 128, front), C.MetalDark, METAL)
	solid(model, "ShroudBottom", Vector3.new(x1 - x0, 12, 14), CFrame.new(cx, 15, front), C.MetalDark, METAL)
	for _, span in { { x0, 207.5 }, { 302.5, 312.5 }, { 407.5, 417.5 }, { 512.5, x1 } } do
		solid(
			model,
			"ShroudPillar",
			Vector3.new(span[2] - span[1], 100, 14),
			CFrame.new((span[1] + span[2]) / 2, 71, front),
			C.MetalDark,
			METAL
		)
	end
	-- Facettes : arêtes en diamant entre les ventilateurs, sourcil biseauté, filets alu
	for _, px in { 307.5, 412.5 } do
		for _, side in { -1, 1 } do
			Wedge(
				model,
				"Facet",
				Vector3.new(96, 5, 5),
				CFrame.new(px + side * 2.5, 71, front - 9.5) * CFrame.Angles(0, 0, -side * math.pi / 2),
				C.MetalLight,
				METAL
			)
		end
		Box(model, "FacetEdge", Vector3.new(0.6, 96, 0.6), CFrame.new(px, 71, front - 11.8), C.Aluminum, METAL)
	end
	Wedge(model, "Brow", Vector3.new(x1 - x0, 7, 5), CFrame.new(cx, 131.5, front - 9.5), C.MetalLight, METAL)
	for _, y in { 122.5, 17 } do
		Box(model, "AccentStrip", Vector3.new(x1 - x0 - 10, 1, 0.6), CFrame.new(cx, y, front - 7.2), C.Aluminum, METAL)
	end
	neon(
		model,
		"GpuRgbEdge",
		Vector3.new(x1 - x0 - 20, 1, 0.5),
		CFrame.new(cx, 20, front - 7.4),
		green,
		0.2,
		{ "RgbStrip" }
	)
	-- 3 ventilateurs encastrés dans le carénage
	for _, x in { 255, 360, 465 } do
		Props.Fan(model, CFrame.new(x, 72, 322) * CFrame.Angles(0, math.pi / 2, 0), 88, green, 11, { Brand = "PRISM" })
	end
	-- Ailettes visibles sur la tranche haute + caloducs en U au bout de la carte
	for k = 0, 53 do
		Box(model, "TopFin", Vector3.new(0.6, 6, 24), CFrame.new(x0 + 5 + k * 6, 131, 334), C.Aluminum, METAL)
	end
	for k = 0, 4 do
		local y = 30 + k * 20
		for _, pz in { 327, 341 } do
			Rod(model, "HeatPipe", CFrame.new(x0 - 1, y, pz), 6, 4.6, C.Copper)
		end
		Rod(model, "HeatPipeBend", CFrame.new(x0 - 4, y, 334) * CFrame.Angles(0, math.pi / 2, 0), 14, 4.6, C.Copper)
		for _, pz in { 327, 341 } do
			Build.Decor({
				Name = "HeatPipeElbow",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 4.6,
				CFrame = CFrame.new(x0 - 4, y, pz),
				Color = C.Copper,
				Material = METAL,
				CastShadow = false,
				Parent = model,
			})
		end
	end
	-- Logo RGB sur la tranche (visible depuis la vitre) et connecteur 16 broches
	local logo =
		neon(model, "GpuLogo", Vector3.new(150, 1, 20), CFrame.new(310, 134.6, 334), magenta, 0.25, { "RgbStrip" })
	Props.Label(logo, "PRISM  PX-9000", C.White, Enum.NormalId.Top, Enum.Font.GothamBlack)
	local header = Box(model, "PowerHeader", Vector3.new(26, 6, 12), CFrame.new(452, 137, 334), C.Black)
	header.CastShadow = true
	local plug = Box(model, "PowerPlug", Vector3.new(22, 5, 10), CFrame.new(452, 142.5, 334), C.Black)
	Props.Label(plug, "12V-2x6", C.Silk, Enum.NormalId.Top, Enum.Font.Code)
	-- Backplate : grille de fentes obliques, logo, vis
	local back = z + 4.5
	solid(model, "Backplate", Vector3.new(326, 122, 3), CFrame.new(360, 71, back), C.Black, METAL)
	Props.Decal(
		model,
		"BackplateLogo",
		Vector3.new(140, 22, 0.2),
		CFrame.new(300, 108, back + 1.6),
		"PRISM",
		magenta,
		Enum.NormalId.Back,
		Enum.Font.GothamBlack
	)
	-- Fentes obliques rétroéclairées (lueur douce) + filets alu en chevron
	for row = 0, 2 do
		for col = 0, 7 do
			neon(
				model,
				"BackVent",
				Vector3.new(26, 3, 0.3),
				CFrame.new(222 + col * 35, 30 + row * 18, back + 1.6) * CFrame.Angles(0, 0, math.rad(28)),
				C.PcbDark:Lerp(magenta, 0.55),
				0.45
			)
		end
	end
	for _, side in { -1, 1 } do
		Box(
			model,
			"BackAccent",
			Vector3.new(90, 1.2, 0.3),
			CFrame.new(430 + side * 38, 108, back + 1.6) * CFrame.Angles(0, 0, math.rad(side * 12)),
			C.Aluminum,
			METAL
		)
	end
	for _, bx in { 210, 510 } do
		for _, by in { 22, 120 } do
			Rod(model, "BackScrew", CFrame.new(bx, by, back + 1.7) * CFrame.Angles(0, math.pi / 2, 0), 0.4, 4, C.Nickel)
		end
	end
	-- Équerre PCIe (bout arrière, côté est) : ports DisplayPort / HDMI, fentes d'aération
	local bracketX = x1 + 1.5
	solid(model, "PcieBracket", Vector3.new(1.5, 150, 38), CFrame.new(bracketX, 75, 332), C.Aluminum, METAL)
	Box(model, "BracketTab", Vector3.new(10, 1.5, 38), CFrame.new(bracketX + 4.5, 150, 332), C.Aluminum, METAL)
	for k = 0, 3 do
		local py = 30 + k * 16
		Box(model, "DisplayPort", Vector3.new(2, 8, 16), CFrame.new(bracketX + 1.2, py, 330), C.Bg)
		if k < 3 then
			Wedge(model, "DpChamfer", Vector3.new(2.2, 3, 3), CFrame.new(bracketX + 1.3, py - 2.5, 336.5), C.Aluminum)
		else
			for _, side in { -1, 1 } do
				Wedge(
					model,
					"HdmiChamfer",
					Vector3.new(2.2, 3, 3),
					CFrame.new(bracketX + 1.3, py - 2.5, 330 + side * 6.5)
						* CFrame.Angles(0, if side < 0 then math.pi else 0, 0),
					C.Aluminum
				)
			end
		end
	end
	for k = 0, 5 do
		Box(model, "BracketVent", Vector3.new(1.7, 3, 26), CFrame.new(bracketX, 100 + k * 7, 332), C.Bg)
	end
	-- Câbles 12V-2x6 : de grands arcs gainés qui filent jusqu'au PSU, au-dessus de La Centrale
	for i, color in { C.Black, C.Brand, C.Black } do
		local dz = (i - 2) * 7
		Props.ArcCable(
			model,
			Vector3.new(446 + i * 3, 145, 334 + dz * 0.4),
			Vector3.new(120, 250, 300 + dz),
			Vector3.new(-231, 60, 330 + dz),
			2.6,
			color,
			14
		)
	end
	-- Section audio dans le canyon : condensateurs dorés, codec blindé, ligne de séparation
	for i = 0, 5 do
		Props.Capacitor(model, Vector3.new(240 + i * 16, 0, 408), 5, 13, Color3.fromRGB(176, 140, 60), C.Gold)
	end
	local codec = solid(model, "AudioCodec", Vector3.new(34, 3, 26), CFrame.new(400, 1.5, 396), C.Aluminum, METAL)
	Props.Label(codec, "ANGASOUND HD", magenta, Enum.NormalId.Top, Enum.Font.GothamBlack)
	neon(model, "AudioLine", Vector3.new(248, 0.12, 0.8), CFrame.new(346, 0.08, 372), C.Gold, 0.35)
	neon(model, "AudioLine", Vector3.new(0.8, 0.12, 48), CFrame.new(470, 0.08, 396), C.Gold, 0.35)
	silkText(model, "HD AUDIO", Vector3.new(300, 0, 384), 40, 6, C.Gold)
	for _, lx in { 280, 440 } do
		lamp(model, "CanyonLight", Vector3.new(lx, 30, 395), magenta, 1.8, 70)
	end
end

-- 7 · Neural Nexus : zone secrète près des ports arrière, puce IA flottante
local function buildAi(model: Model)
	local white = hex(Zones[7].Primary)
	local violet = hex(Zones[7].Secondary)
	-- Plaque I/O sur la paroi arrière (est) : cadre embouti + vrais connecteurs
	local wallX = L.MAX_X
	local plate =
		solid(model, "IoShield", Vector3.new(3, 150, 150), CFrame.new(wallX - 1.5, 80, -340), C.Aluminum, METAL)
	plate.Reflectance = 0.05
	for _, side in { -1, 1 } do
		Box(model, "IoRim", Vector3.new(1.2, 150, 3), CFrame.new(wallX - 3.4, 80, -340 + side * 73.5), C.Nickel, METAL)
		Box(model, "IoRim", Vector3.new(1.2, 3, 150), CFrame.new(wallX - 3.4, 80 + side * 73.5, -340), C.Nickel, METAL)
	end
	local face = wallX - 3 -- plan de la face avant de la plaque
	local function port(name: string, y: number, z: number, height: number, width: number, shell: Color3, inner: Color3)
		Box(model, name, Vector3.new(2.4, height, width), CFrame.new(face - 1.2, y, z), shell, METAL)
		Box(model, name .. "Cavity", Vector3.new(2.5, height * 0.72, width * 0.86), CFrame.new(face - 1.25, y, z), C.Bg)
		return Box(
			model,
			name .. "Tongue",
			Vector3.new(2.6, height * 0.26, width * 0.7),
			CFrame.new(face - 1.3, y + height * 0.12, z),
			inner
		)
	end
	local function silk(text: string, y: number, z: number, width: number)
		Props.Decal(
			model,
			"IoSilk",
			Vector3.new(0.2, 3.4, width),
			CFrame.new(face - 0.15, y, z),
			text,
			C.Bg,
			Enum.NormalId.Left,
			Enum.Font.GothamBold
		)
	end
	-- Colonne 1 : antennes Wi-Fi (SMA dorés) + boutons BIOS / CMOS
	for _, y in { 128, 108 } do
		Rod(model, "WifiSma", CFrame.new(face - 4, y, -395), 8, 6, C.Gold, METAL)
		Rod(model, "WifiNut", CFrame.new(face - 1, y, -395), 2, 9, C.Nickel)
	end
	silk("Wi-Fi 7", 97, -395, 20)
	for i, label in { "BIOS", "CMOS" } do
		local y = 82 - (i - 1) * 16
		Box(model, "IoButton", Vector3.new(2, 7, 7), CFrame.new(face - 1, y, -395), if i == 1 then C.Brand else C.Black)
		silk(label, y - 6, -395, 14)
	end
	-- Colonne 2 : 4 USB-A (langue bleue)
	for k = 0, 3 do
		port("UsbA", 128 - k * 15, -368, 7, 15, C.Nickel, Color3.fromRGB(70, 130, 255))
	end
	silk("USB 10G", 70, -368, 18)
	-- Colonne 3 : HDMI, DisplayPort, 2 USB-C
	port("Hdmi", 128, -342, 7, 16, C.Nickel, C.Black)
	-- Coins inférieurs coupés : la cavité HDMI devient un trapèze
	for _, side in { -1, 1 } do
		Wedge(
			model,
			"HdmiChamfer",
			Vector3.new(2.7, 2.4, 2.4),
			CFrame.new(face - 1.35, 126.7, -342 + side * 5.7) * CFrame.Angles(0, if side < 0 then math.pi else 0, 0),
			C.Nickel,
			METAL
		)
	end
	port("Dp", 112, -342, 8, 15, C.Nickel, C.Black)
	for k = 0, 1 do
		local y = 96 - k * 13
		Box(model, "UsbC", Vector3.new(2.4, 5, 10), CFrame.new(face - 1.2, y, -342), C.Nickel, METAL)
		for _, side in { -1, 1 } do
			Rod(model, "UsbCEnd", CFrame.new(face - 1.2, y, -342 + side * 5), 2.4, 5, C.Nickel)
		end
		Box(model, "UsbCTongue", Vector3.new(2.6, 1.4, 8), CFrame.new(face - 1.3, y, -342), C.Bg)
	end
	silk("HDMI · DP · USB-C", 72, -342, 26)
	-- Colonne 4 : RJ45 5G (LED verte/orange) + 2 USB-A 20G (langue rouge)
	Box(model, "Rj45Shield", Vector3.new(2.6, 16, 16), CFrame.new(face - 1.3, 124, -316), C.Nickel, METAL)
	Box(model, "Rj45Jack", Vector3.new(2.7, 11, 11), CFrame.new(face - 1.35, 122.5, -316), C.Bg)
	Box(model, "Rj45Clip", Vector3.new(2.8, 3, 5), CFrame.new(face - 1.4, 126.5, -316), C.Black)
	neon(
		model,
		"LanLed",
		Vector3.new(2.8, 2, 3),
		CFrame.new(face - 1.4, 130, -322),
		C.Cyan:Lerp(Color3.fromRGB(80, 255, 120), 0.6),
		0.1,
		{ "PulseGlow" }
	)
	neon(model, "LanLed", Vector3.new(2.8, 2, 3), CFrame.new(face - 1.4, 130, -310), Color3.fromRGB(255, 170, 60), 0.1)
	for k = 0, 1 do
		port("Usb20G", 102 - k * 15, -316, 7, 15, C.Nickel, C.Brand)
	end
	silk("LAN 5G · USB 20G", 72, -316, 24)
	-- Colonne 5 : jacks audio colorés + optique
	local jacks = {
		Color3.fromRGB(120, 200, 80),
		Color3.fromRGB(240, 130, 170),
		Color3.fromRGB(80, 140, 230),
		Color3.fromRGB(245, 160, 60),
		C.Black,
		Color3.fromRGB(150, 155, 165),
	}
	for i, color in jacks do
		local row, col = (i - 1) % 3, math.floor((i - 1) / 3)
		local y, jz = 128 - row * 13, -294 + col * 11
		Rod(model, "AudioJack", CFrame.new(face - 1, y, jz), 2, 8, color, Enum.Material.SmoothPlastic)
		Rod(model, "AudioHole", CFrame.new(face - 1.6, y, jz), 2, 3.4, C.Bg, Enum.Material.SmoothPlastic)
	end
	Box(model, "Optical", Vector3.new(2.4, 7, 7), CFrame.new(face - 1.2, 88, -289), C.Black)
	silk("AUDIO", 72, -289, 14)
	Props.Decal(
		model,
		"IoLogo",
		Vector3.new(0.2, 12, 110),
		CFrame.new(face - 0.15, 30, -340),
		"ANGAINONE  I/O",
		violet,
		Enum.NormalId.Left,
		Enum.Font.GothamBlack
	)
	for k = 0, 3 do
		Box(model, "IoVent", Vector3.new(0.3, 2.4, 100), CFrame.new(face - 0.1, 44 + k * 5, -340), C.Bg)
	end
	-- Ventilateur d'extraction arrière (à côté de la plaque I/O), tourné vers l'intérieur
	Props.Fan(
		model,
		CFrame.new(wallX, 85, -205) * CFrame.Angles(0, math.pi, 0),
		110,
		violet,
		9,
		{ Rgb = true, Light = true }
	)

	-- Plateforme + puce IA flottante et ses anneaux en rotation
	local center = Vector3.new(380, 0, -330)
	Build.Cylinder({
		Name = "Pedestal",
		Size = Vector3.new(6, 90, 90),
		CFrame = CFrame.new(center + Vector3.new(0, 3, 0)) * UP,
		Color = C.MetalDark,
		Material = METAL,
		Parent = model,
	})
	Rod(model, "PedestalStep", CFrame.new(center + Vector3.new(0, 7, 0)) * UP, 2, 60, C.MetalLight)
	Build.Neon({
		Name = "PedestalRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 92, 92),
		CFrame = CFrame.new(center + Vector3.new(0, 5.2, 0)) * UP,
		Color = violet,
		Transparency = 0.3,
		Tags = { "PulseGlow" },
		Parent = model,
	})
	for k = 0, 7 do
		local a = k * math.pi / 4
		neon(
			model,
			"PedestalTrace",
			Vector3.new(14, 0.2, 0.8),
			CFrame.new(center + Vector3.new(0, 8.1, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(20, 0, 0),
			white,
			0.3
		)
	end
	-- Puce : substrat, pastilles dorées, CMS, die nu gravé de circuits néon
	local chipY = 80
	local chipCf = CFrame.new(center + Vector3.new(0, chipY, 0)) * CFrame.Angles(0, math.rad(45), 0)
	Box(model, "NpuSubstrate", Vector3.new(60, 3, 60), chipCf, C.Pcb:Lerp(violet, 0.15)).CastShadow = true
	Box(model, "NpuBga", Vector3.new(54, 0.4, 54), chipCf * CFrame.new(0, -1.7, 0), C.Gold:Lerp(C.Black, 0.3), FOIL)
	for _, side in { -1, 1 } do
		Box(model, "NpuPads", Vector3.new(50, 0.2, 1.4), chipCf * CFrame.new(0, 1.6, side * 26), C.Gold, FOIL)
		Box(model, "NpuPads", Vector3.new(1.4, 0.2, 50), chipCf * CFrame.new(side * 26, 1.6, 0), C.Gold, FOIL)
		for k = -1, 1 do
			Box(model, "NpuSmd", Vector3.new(2, 1, 3.4), chipCf * CFrame.new(side * 20, 2, k * 8), C.Copper, METAL)
		end
	end
	local die =
		Box(model, "NpuChip", Vector3.new(32, 2.4, 32), chipCf * CFrame.new(0, 2.7, 0), C.Bg, Enum.Material.Glass)
	die.Reflectance = 0.25
	die.CastShadow = true
	Props.Label(die, "ANGA  NPU", violet, Enum.NormalId.Top, Enum.Font.GothamBlack)
	for k = -1, 1 do
		neon(model, "DieCircuit", Vector3.new(28, 0.2, 0.5), chipCf * CFrame.new(0, 3.95, k * 9), violet, 0.2)
		neon(model, "DieCircuit", Vector3.new(0.5, 0.2, 28), chipCf * CFrame.new(k * 9, 3.95, 0), white, 0.35)
	end
	-- Faisceaux de données du socle vers les coins de la puce
	for k = 0, 3 do
		local corner = (chipCf * CFrame.new((if k % 2 == 0 then 1 else -1) * 28, -1.5, (if k < 2 then 1 else -1) * 28)).Position
		local foot = center + (Vector3.new(corner.X, 0, corner.Z) - center) * 1.3 + Vector3.new(0, 8, 0)
		neon(
			model,
			"DataBeam",
			Vector3.new((corner - foot).Magnitude, 0.6, 0.6),
			Props.Along(foot, corner),
			violet,
			0.55,
			{ "PulseGlow" }
		)
	end
	-- Anneaux : moyeu ancré (DecorSpin, axe Y) + segments soudés, chacun incliné différemment
	for i, radius in { 38, 48, 58 } do
		local hubCf = CFrame.new(center + Vector3.new(0, chipY, 0))
			* CFrame.Angles(math.rad(18 * i), math.rad(40 * i), 0)
		local hub = Build.Decor({
			Name = "RingHub",
			Size = Vector3.one,
			CFrame = hubCf,
			Transparency = 1,
			Tags = { "DecorSpin" },
			Parent = model,
		})
		hub:SetAttribute("Axis", "Y")
		hub:SetAttribute("Speed", 0.25 * i)
		for _, segment in
			Props.Ring(
				model,
				"Ring",
				hubCf * UP,
				radius,
				1.2,
				1,
				28,
				if i == 2 then white else violet,
				Enum.Material.Neon
			)
		do
			segment.Transparency = 0.35
			Props.WeldTo(hub, segment)
		end
		for k = 0, 1 do
			local node = Build.Decor({
				Name = "RingNode",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 4,
				CFrame = hubCf * CFrame.Angles(0, k * math.pi + i, 0) * CFrame.new(radius, 0, 0),
				Color = white,
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = model,
			})
			Props.WeldTo(hub, node)
		end
	end
	local brain = Build.Decor({
		Name = "Brain",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(44, 44, 44),
		CFrame = CFrame.new(center + Vector3.new(0, 150, 0)),
		Color = violet,
		Material = Enum.Material.ForceField,
		Transparency = 0.1,
		Parent = model,
	})
	Build.PointLight(brain, violet, 3, 140)
	-- Faisceau vers la vitre : repère visible de tout le PC
	Build.Neon({
		Name = "Beacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(CASE_H - 172, 6, 6),
		CFrame = CFrame.new(center + Vector3.new(0, 172 + (CASE_H - 172) / 2, 0)) * UP,
		Color = violet,
		Transparency = 0.7,
		Tags = { "Beacon" },
		Parent = model,
	})
end

-- Positions des fragments cachés (coins des zones, à explorer)
local FRAGMENTS: { [number]: { Vector3 } } = {
	[1] = { Vector3.new(-520, 0, 400), Vector3.new(-520, 0, 160), Vector3.new(160, 0, 400) },
	[2] = { Vector3.new(359, 0, 118), Vector3.new(451, 0, -118), Vector3.new(520, 0, 0) },
	[3] = { Vector3.new(-395, 0, -128), Vector3.new(-395, 0, 128), Vector3.new(-200, 0, -125) },
	[4] = { Vector3.new(-200, 0, -405), Vector3.new(-420, 0, -405), Vector3.new(-200, 0, -300) },
	[5] = { Vector3.new(-165, 0, -160), Vector3.new(165, 0, -405), Vector3.new(150, 0, -330) },
	[6] = { Vector3.new(200, 0, 400), Vector3.new(520, 0, 400), Vector3.new(520, 0, 160) },
	[7] = { Vector3.new(200, 0, -405), Vector3.new(520, 0, -160), Vector3.new(300, 0, -405) },
}

local HEROES: { [number]: (Model) -> () } = {
	[1] = buildPsu,
	[2] = buildRam,
	[3] = buildSsd,
	[4] = buildCooling,
	[5] = buildCpu,
	[6] = buildGpu,
	[7] = buildAi,
}

------------------------------------------------------------------------------------
-- Hub : le cœur de la carte mère
------------------------------------------------------------------------------------

local function buildHub(world: Instance): Model
	local hub = Build.Model("Hub", world)
	hub.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local center = Vector3.new(0, 0, 0)

	-- Chipset : dissipateur à ailettes, capot à facettes + logo, halo RGB au sol
	solid(hub, "Chipset", Vector3.new(70, 8, 50), CFrame.new(center + Vector3.new(0, 4, -40)), C.MetalDark, METAL)
	for i = -7, 7 do
		Box(
			hub,
			"ChipsetFin",
			Vector3.new(1.6, 4, 46),
			CFrame.new(center + Vector3.new(i * 4.4, 10, -40)),
			C.MetalLight,
			METAL
		)
	end
	local cover =
		solid(hub, "ChipsetCover", Vector3.new(40, 2, 30), CFrame.new(center + Vector3.new(0, 13, -40)), C.Black, METAL)
	Props.Label(cover, "AngAInOne", C.Violet, Enum.NormalId.Top, Enum.Font.GothamBlack)
	for _, side in { -1, 1 } do
		Wedge(
			hub,
			"ChipsetFacet",
			Vector3.new(40, 2, 6),
			CFrame.new(center + Vector3.new(0, 13, -40 + side * 18))
				* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			C.Black,
			METAL
		)
	end
	-- Liseré lumineux fin sous le bord du capot
	for _, side in { -1, 1 } do
		neon(
			hub,
			"ChipsetCoverGlow",
			Vector3.new(41, 0.4, 0.5),
			CFrame.new(center + Vector3.new(0, 11.9, -40 + side * 21.2)),
			C.Violet,
			0.2
		)
	end
	neon(
		hub,
		"ChipsetRgb",
		Vector3.new(72, 1, 52),
		CFrame.new(center + Vector3.new(0, 0.6, -40)),
		C.Violet,
		0.4,
		{ "RgbStrip" }
	)
	silkRect(hub, center + Vector3.new(0, 0, -40), 78, 58)
	local title = Build.Decor({
		Name = "TitleHologram",
		Size = Vector3.new(80, 20, 0.2),
		CFrame = CFrame.new(center + Vector3.new(0, 150, -128)),
		Transparency = 1,
		Tags = { "TitleHologram" },
		Parent = hub,
	})
	Build.PointLight(title, C.Violet, 2, 80)

	-- Écran géant de l'app partenaire AngAInOne (rendu côté client : tag AppScreen), monté sur
	-- deux piliers AU-DESSUS du portail de The Core : visible dès le spawn, sans gêner le passage.
	local monitorCf = CFrame.lookAt(Vector3.new(0, 96, -128), Vector3.new(0, 96, 0))
	Build.Part({
		Name = "MonitorBezel",
		Size = Vector3.new(118, 68, 3),
		CFrame = monitorCf * CFrame.new(0, 0, 1.6),
		Color = C.Black,
		Material = Enum.Material.Metal,
		Parent = hub,
	})
	local appScreen = Build.Decor({
		Name = "AppScreen",
		Size = Vector3.new(112, 63, 0.4),
		CFrame = monitorCf,
		Color = Color3.fromHex("202020"),
		Material = Enum.Material.SmoothPlastic,
		Tags = { "AppScreen" },
		Parent = hub,
	})
	Build.PointLight(appScreen, C.Violet, 1.2, 60)
	Build.Neon({
		Name = "MonitorAmbilight",
		Size = Vector3.new(116, 66, 0.4),
		CFrame = monitorCf * CFrame.new(0, 0, 3.4),
		Color = C.Violet,
		Transparency = 0.2,
		Tags = { "RgbStrip" },
		Parent = hub,
	})
	Box(hub, "MonitorChin", Vector3.new(118, 3, 3.4), monitorCf * CFrame.new(0, -35.4, 1.6), C.MetalLight, METAL)
	for _, x in { -63, 63 } do
		Build.Part({
			Name = "MonitorPillar",
			Size = Vector3.new(6, 130, 6),
			CFrame = CFrame.new(x, 65, -131),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = hub,
		})
	end

	-- Slots PCIe (nord-ouest) : deux x16 blindés + un x1, avec loquet et sérigraphie
	local function pcieSlot(label: string, fromX: number, toX: number, z: number, armored: boolean)
		local length = toX - fromX
		local cx = (fromX + toX) / 2
		solid(
			hub,
			"PcieSlot",
			Vector3.new(length, 5, 7),
			CFrame.new(cx, 2.5, z),
			if armored then C.Aluminum else C.Black,
			if armored then METAL else Enum.Material.SmoothPlastic
		)
		Box(hub, "PcieSlit", Vector3.new(length - 3, 0.2, 2.6), CFrame.new(cx, 5.05, z), C.Bg)
		Box(
			hub,
			"PcieKey",
			Vector3.new(1.4, 0.4, 2.8),
			CFrame.new(fromX + math.min(length * 0.18, 12), 5.1, z),
			C.Black
		)
		if armored then
			for _, side in { -1, 1 } do
				Box(
					hub,
					"PcieArmorEdge",
					Vector3.new(length, 0.4, 0.8),
					CFrame.new(cx, 5.1, z + side * 3.1),
					C.Nickel,
					METAL
				)
			end
		end
		solid(hub, "PcieLatch", Vector3.new(5, 6, 7.4), CFrame.new(toX + 2.5, 3, z), C.Black)
		Wedge(
			hub,
			"PcieLatchLever",
			Vector3.new(7.4, 2.5, 5),
			CFrame.new(toX + 2.5, 7.25, z) * CFrame.Angles(0, -math.pi / 2, 0),
			C.Black
		)
		silkRect(hub, Vector3.new(cx + 2.5, 0, z), length + 9, 11)
		silkText(hub, label, Vector3.new(fromX + 16, 0, z + 8.5), 28, 4)
	end
	pcieSlot("PCIEX16_1", -168, -62, -84, true)
	pcieSlot("PCIEX16_2", -168, -62, -50, true)
	pcieSlot("PCIEX1_1", -170, -140, -114, false)

	-- Dissipateurs M.2 : ailettes, vis, connecteur, liseré vers le spawn
	for index, x in { -120, 120 } do
		solid(hub, "M2Heatsink", Vector3.new(80, 3, 22), CFrame.new(x, 1.5, 118), C.Aluminum, METAL)
		for k = 0, 11 do
			Box(hub, "M2Fin", Vector3.new(2, 1.4, 20), CFrame.new(x - 36 + k * 5, 3.7, 118), C.MetalLight, METAL)
		end
		local plate = Box(hub, "M2Plate", Vector3.new(16, 0.4, 18), CFrame.new(x + 30, 3.2, 118), C.Black, METAL)
		Props.Label(plate, `M.2_{index}`, C.Cyan, Enum.NormalId.Top, Enum.Font.GothamBlack)
		Box(hub, "M2Connector", Vector3.new(5, 4, 24), CFrame.new(x - 42.5, 2, 118), C.Black)
		screwHead(hub, CFrame.new(x + 44, 0, 118), 6)
		neon(hub, "M2Glow", Vector3.new(80, 0.6, 0.4), CFrame.new(x, 2.2, 106.8), C.Cyan, 0.3)
		silkRect(hub, Vector3.new(x, 0, 118), 96, 28)
	end
	-- Pile BIOS dans son support
	Rod(hub, "CmosHolder", CFrame.new(130, 0.75, -60) * UP, 1.5, 46, C.Black, Enum.Material.SmoothPlastic)
	local battery = Build.Cylinder({
		Name = "CmosBattery",
		Size = Vector3.new(4, 40, 40),
		CFrame = CFrame.new(130, 2, -60) * UP,
		Color = Color3.fromRGB(205, 210, 220),
		Material = Enum.Material.Metal,
		Reflectance = 0.2,
		Parent = hub,
	})
	Props.Label(battery, "+ CR2032", C.Black, Enum.NormalId.Right, Enum.Font.GothamBold)
	Box(hub, "CmosClip", Vector3.new(6, 4.6, 10), CFrame.new(152, 2.3, -60), C.Nickel, METAL)

	-- Pistes lumineuses du spawn vers chaque portail relié au hub
	for _, layout in L.Zones do
		if layout.Parent == 0 then
			local from = L.HubSpawn * Vector3.new(1, 0, 1) + Vector3.new(0, 0.1, 0)
			local to = layout.Gate + Vector3.new(0, 0.1, 0)
			Build.Neon({
				Name = "GateTrace",
				Size = Vector3.new(2, 0.1, (to - from).Magnitude),
				CFrame = CFrame.lookAt((from + to) / 2, to),
				Color = hex(Zones[layout.Zone].Primary),
				Transparency = 0.5,
				Tags = { "DataTrace" },
				Parent = hub,
			})
		end
	end
	-- Logo sérigraphié de la carte, en grand entre le chipset et le spawn
	Props.Decal(
		hub,
		"BoardLogo",
		Vector3.new(96, 0.1, 22),
		CFrame.new(0, 0.07, 30),
		"AngAInOne",
		C.Silk,
		Enum.NormalId.Top,
		Enum.Font.GothamBlack
	)
	Box(hub, "BoardLogoLine", Vector3.new(96, 0.08, 0.8), CFrame.new(0, 0.05, 42.5), C.Brand)

	-- Connecteur ATX 24 broches + fiche + faisceau qui arrive du PSU en passant très haut
	local atx = solid(hub, "Atx24Pin", Vector3.new(12, 8, 26), CFrame.new(-160, 4, 60), C.Black)
	Props.Label(atx, "ATX 24", C.Gold, Enum.NormalId.Right, Enum.Font.GothamBold)
	Box(hub, "AtxPlug", Vector3.new(12.4, 3, 26.4), CFrame.new(-160, 9.5, 60), C.Black:Lerp(C.Brand, 0.15))
	Box(hub, "AtxLatch", Vector3.new(1.4, 4, 5), CFrame.new(-153.2, 7, 60), C.Black)
	silkRect(hub, Vector3.new(-160, 0, 60), 18, 32)
	silkText(hub, "ATX_PWR", Vector3.new(-160, 0, 80), 18, 4)
	for i = -2, 2 do
		Props.ArcCable(
			hub,
			Vector3.new(-160, 11, 60 + i * 4.5),
			Vector3.new(-205, 140, 150 + i * 4.5),
			Vector3.new(-236, 50, 250 + i * 4.5),
			2,
			if i == 0 then C.Brand else C.Black,
			12
		)
	end
	-- Q-code de débogage + LED de diagnostic (CPU, DRAM, VGA, BOOT)
	Box(hub, "QCode", Vector3.new(10, 1.2, 14), CFrame.new(-138, 0.6, 58), C.Black)
	local digits =
		Box(hub, "QCodeDigits", Vector3.new(8, 0.1, 11), CFrame.new(-138, 1.25, 58), C.Bg, Enum.Material.Glass)
	Props.Label(digits, "A0", C.Brand, Enum.NormalId.Top, Enum.Font.Arcade)
	for i, led in
		{
			{ Label = "CPU", Color = Color3.fromRGB(255, 80, 80) },
			{ Label = "DRAM", Color = Color3.fromRGB(255, 210, 80) },
			{ Label = "VGA", Color = C.White },
			{ Label = "BOOT", Color = Color3.fromRGB(90, 230, 120) },
		}
	do
		local z = 46 + (i - 1) * 8
		neon(hub, "DebugLed", Vector3.new(2, 0.8, 3), CFrame.new(-126, 0.4, z), led.Color, if i == 4 then 0.1 else 0.6)
		silkText(hub, led.Label, Vector3.new(-117, 0, z), 12, 3)
	end
	-- Ports SATA coudés (2 x 3) au bord ouest, avec leurs nappes rouges
	for row = 0, 1 do
		for col = 0, 2 do
			local pos = Vector3.new(-166, 2.1 + row * 4.2, 98 + col * 12)
			solid(hub, "SataPort", Vector3.new(8, 4, 10), CFrame.new(pos), C.Black)
			Box(hub, "SataKey", Vector3.new(8.2, 1, 7), CFrame.new(pos + Vector3.new(0, 0.5, -0.5)), C.Bg)
			Box(hub, "SataKeyL", Vector3.new(8.2, 2.4, 1), CFrame.new(pos + Vector3.new(0, -0.2, 3.3)), C.Bg)
		end
	end
	for k = 0, 2 do
		ribbon(hub, { Vector3.new(-170.5, 2.1, 98 + k * 12), Vector3.new(-176, 0.35, 98 + k * 5) }, 2.4, C.Brand)
	end
	silkText(hub, "SATA6G_1-6", Vector3.new(-150, 0, 110), 18, 4)
	-- Connecteurs du panneau avant et USB 3 (bord sud)
	Box(hub, "FPanelBase", Vector3.new(16, 1, 7), CFrame.new(48, 0.5, 132), C.Black)
	for i = 0, 4 do
		for j = 0, 1 do
			Rod(hub, "HeaderPin", CFrame.new(42 + i * 3, 3, 130.5 + j * 3) * UP, 4, 0.8, C.Gold, FOIL)
		end
	end
	silkText(hub, "F_PANEL", Vector3.new(48, 0, 124), 16, 3)
	local usb = solid(hub, "Usb3Header", Vector3.new(18, 5, 7), CFrame.new(72, 2.5, 132), Color3.fromRGB(60, 110, 220))
	usb.Material = Enum.Material.SmoothPlastic
	Box(hub, "Usb3Slit", Vector3.new(15, 0.2, 3), CFrame.new(72, 5.05, 132), C.Bg)
	silkText(hub, "USB3_1", Vector3.new(72, 0, 124), 14, 3)

	-- Deux écrans de classement tournés vers le spawn
	local function board(name: string, x: number)
		local base = CFrame.new(x, 24, -110)
		Build.Part({
			Name = name .. "Frame",
			Size = Vector3.new(46, 34, 1.5),
			CFrame = base * CFrame.new(0, 0, -0.6),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Parent = hub,
		})
		local screen = Build.Decor({
			Name = name,
			Size = Vector3.new(44, 32, 0.4),
			CFrame = base * CFrame.Angles(0, math.pi, 0),
			Color = C.Bg,
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			Tags = { "LeaderboardScreen" },
			Parent = hub,
		})
		screen:SetAttribute("Board", name)
		Build.Part({
			Name = name .. "Leg",
			Size = Vector3.new(3, 8, 3),
			CFrame = CFrame.new(x, 4, -111),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = hub,
		})
		Box(
			hub,
			name .. "Foot",
			Vector3.new(14, 0.8, 6),
			CFrame.new(x, 0.4, -111),
			C.MetalLight,
			Enum.Material.DiamondPlate
		)
		neon(hub, name .. "Trim", Vector3.new(46, 0.5, 0.5), base * CFrame.new(0, -17.2, 0.4), C.Violet, 0.25)
	end
	board("BenchmarkBoard", -110)
	board("WeeklyBoard", 110)

	-- Téléporteur du hub
	local teleporter = Props.Pad(hub, "Teleporter", CFrame.new(-50, 0, 105), 12, C.Cyan)
	Build.Prompt(teleporter, "Téléporteur", "Voyager", "Elevator", 12)

	-- Condensateurs aux 4 coins (hors des chemins spawn -> portails)
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		Props.Capacitor(hub, corner * Vector3.new(150, 0, 90), 6, 18, C.Black, C.Violet)
	end
	lamp(hub, "HubLight", Vector3.new(0, 60, 0), C.White, 1.2, 160)
	return hub
end

------------------------------------------------------------------------------------
-- Construction complète
------------------------------------------------------------------------------------

function MapBuilder.Build(): Model
	local existing = Workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"

	buildCase(world)
	buildBoardDetails(world)
	buildWalls(world)
	local hub = buildHub(world)

	local zonesFolder = Build.Folder("Zones", world)
	for _, layout in L.Zones do
		local model = Build.Model(`Zone{layout.Zone}`, zonesFolder)
		model:SetAttribute("Zone", layout.Zone)
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		buildPlaza(model, layout, FRAGMENTS[layout.Zone])
		HEROES[layout.Zone](model)
	end
	Build.Folder("Viruses", world)
	world.Parent = Workspace
	return hub
end

return MapBuilder
