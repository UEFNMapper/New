--!strict
--[[
	MapBuilder : construit le PC GÉANT dans lequel tous les joueurs se baladent.

	Le PC est couché sur le flanc : la carte mère est le sol, la vitre latérale est le
	plafond (la lumière de la pièce entre à travers). Voir Config/WorldLayout pour la
	grille des districts et les portails.

	Workspace.World
	├─ Case    : carte mère, parois du boîtier, vitre, poutres
	├─ Walls   : cloisons de verre entre districts
	├─ Gates   : Gate2..7 (portail d'énergie : tag ZoneGate, attribut Zone ; terminal "Débloquer")
	├─ Hub     : chipset, M.2, pile BIOS, classements, téléporteur, spawn
	├─ Zones   : Zone1..7 (Model, attribut Zone)
	│    ├─ Modules / Z{z}M{s}  (attribut ModuleId, prompt "Améliorer")
	│    ├─ Collector, Teleporter, terminal de la zone, Fragments / F1..3
	│    └─ décor "héros" : PSU, barrettes de RAM, baie SSD, watercooling, ventirad, GPU, puce IA
	└─ Viruses : créés par VirusService (attribut OwnerUserId)

	Toute la progression visuelle (tiers des machines, portails ouverts/fermés, fragments
	trouvés) est calculée CÔTÉ CLIENT avec les données du joueur : chacun voit sa propre
	progression dans un monde partagé.
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
	-- Selfs (bobines) de l'étage d'alimentation, alignées le long des VRM de The Core
	for i = 0, 7 do
		Build.Part({
			Name = "Choke",
			Size = Vector3.new(8, 6, 8),
			CFrame = CFrame.new(-135, 3, -385 + i * 22),
			Color = Color3.fromRGB(60, 62, 70),
			Material = Enum.Material.Metal,
			Parent = details,
		})
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
	-- Cache d'alimentation (plafond bas) avec fentes d'aération lumineuses
	local shroudMinX, shroudMaxX = L.MIN_X, L.MIN_X + L.DISTRICT_X
	local shroudMinZ, shroudMaxZ = L.MAX_Z - L.DISTRICT_Z, L.MAX_Z
	Build.Part({
		Name = "Shroud",
		Size = Vector3.new(shroudMaxX - shroudMinX, 4, shroudMaxZ - shroudMinZ),
		CFrame = CFrame.new((shroudMinX + shroudMaxX) / 2, 92, (shroudMinZ + shroudMaxZ) / 2),
		Color = C.Black,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Build.Neon({
		Name = "ShroudEdge",
		Size = Vector3.new(1.2, 1.2, shroudMaxZ - shroudMinZ),
		CFrame = CFrame.new(shroudMaxX, 89.5, (shroudMinZ + shroudMaxZ) / 2),
		Color = amber,
		Transparency = 0.2,
		Tags = { "RgbStrip" },
		Parent = model,
	})
	for x = shroudMinX + 40, shroudMaxX - 40, 70 do
		Build.Neon({
			Name = "ShroudVent",
			Size = Vector3.new(40, 0.4, 3),
			CFrame = CFrame.new(x, 89.8, (shroudMinZ + shroudMaxZ) / 2),
			Color = amber,
			Transparency = 0.3,
			Parent = model,
		})
		local light = Build.Decor({
			Name = "ShroudLight",
			Size = Vector3.one,
			CFrame = CFrame.new(x, 84, (shroudMinZ + shroudMaxZ) / 2),
			Transparency = 1,
			Parent = model,
		})
		Build.PointLight(light, amber:Lerp(C.White, 0.4), 1.6, 110)
	end

	-- Le bloc d'alimentation
	local psuCenter = Vector3.new(-360, 0, 300)
	local psu = Build.Part({
		Name = "PsuBox",
		Size = Vector3.new(250, 76, 170),
		CFrame = CFrame.new(psuCenter + Vector3.new(0, 38, 0)),
		Color = C.Black,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Props.Label(psu, "VOLTCORE  2000W  TITANIUM", amber, Enum.NormalId.Right)
	Build.Neon({
		Name = "PsuStripe",
		Size = Vector3.new(251, 1.2, 1.2),
		CFrame = CFrame.new(psuCenter + Vector3.new(0, 70, -85.5)),
		Color = amber,
		Transparency = 0.2,
		Tags = { "RgbStrip" },
		Parent = model,
	})
	-- Ventilateur sur le dessus (on marche sur le PSU par la rampe)
	-- (axe du ventilateur = X local -> tourné vers le haut)
	Props.Fan(model, CFrame.new(psuCenter + Vector3.new(0, 77.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), 120, amber, 9)
	-- Rampe pour monter sur le PSU (côté est : 76 studs de dénivelé sur ~150)
	local rise, run = 76, 150
	Build.Part({
		Name = "Ramp",
		Size = Vector3.new(math.sqrt(rise * rise + run * run) + 2, 2, 40),
		CFrame = CFrame.new(psuCenter.X + 125 + run / 2, rise / 2, psuCenter.Z)
			* CFrame.Angles(0, 0, -math.atan2(rise, run)),
		Color = C.MetalLight,
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	-- Connecteurs modulaires + câbles gainés qui montent vers la carte mère (vers le hub)
	for i = 0, 5 do
		local start = psuCenter + Vector3.new(125, 20 + i * 8, -60 + i * 10)
		Props.Cable(model, {
			start,
			start + Vector3.new(30, -12 - i * 6, 0),
			Vector3.new(-200 + i * 7, 3, 200),
			Vector3.new(-200 + i * 7, 3, 160),
		}, 2.2, if i % 2 == 0 then C.Black else C.Brand)
	end
	-- Forêt de condensateurs
	for i = 0, 5 do
		Props.Capacitor(model, Vector3.new(-120 + i * 14, 0, 400), 5, 22, C.Black, amber)
	end
end

-- 2 · Memory Lanes : 4 barrettes-gratte-ciels
local function buildRam(model: Model)
	local violet = hex(Zones[2].Primary)
	local lengthZ = 200
	for index, x in { 336, 382, 428, 474 } do
		-- Slot DIMM noir au sol + clips
		Build.Part({
			Name = "DimmSlot",
			Size = Vector3.new(14, 6, lengthZ + 16),
			CFrame = CFrame.new(x, 3, 0),
			Color = C.Black,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		for _, z in { -lengthZ / 2 - 6, lengthZ / 2 + 6 } do
			Build.Part({
				Name = "Latch",
				Size = Vector3.new(16, 18, 6),
				CFrame = CFrame.new(x, 9, z),
				Color = C.White,
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
		end
		-- Barrette : PCB + dissipateurs
		local height = 118
		Build.Part({
			Name = "DimmPcb",
			Size = Vector3.new(2, height, lengthZ),
			CFrame = CFrame.new(x, 6 + height / 2, 0),
			Color = C.PcbDark,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		for _, side in { -1, 1 } do
			local spreader = Build.Part({
				Name = "HeatSpreader",
				Size = Vector3.new(3, height - 10, lengthZ - 4),
				CFrame = CFrame.new(x + side * 2.5, 6 + height / 2, 0),
				Color = if index % 2 == 0 then C.MetalDark else C.Aluminum,
				Material = Enum.Material.Metal,
				Parent = model,
			})
			Props.Label(
				spreader,
				"KRYO  DDR6  8000",
				violet,
				if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left
			)
		end
		-- Bandeau RGB diffusé au sommet
		Build.Neon({
			Name = "DimmRgb",
			Size = Vector3.new(6, 8, lengthZ - 4),
			CFrame = CFrame.new(x, 6 + height + 4, 0),
			Color = violet,
			Transparency = 0.15,
			Tags = { "RgbStrip" },
			Parent = model,
		})
	end
	-- Lumière entre les barrettes (avenues)
	for _, x in { 359, 405, 451 } do
		local light = Build.Decor({
			Name = "LaneLight",
			Size = Vector3.one,
			CFrame = CFrame.new(x, 20, 0),
			Transparency = 1,
			Parent = model,
		})
		Build.PointLight(light, violet, 1.5, 70)
	end
end

-- 3 · Data Vault : baie de SSD empilés + câbles SATA
local function buildSsd(model: Model)
	local teal = hex(Zones[3].Primary)
	local cageX = -470
	Build.Part({
		Name = "CageBack",
		Size = Vector3.new(4, 150, 240),
		CFrame = CFrame.new(-535, 75, 0),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for _, z in { -122, 122 } do
		Build.Part({
			Name = "CageSide",
			Size = Vector3.new(140, 150, 4),
			CFrame = CFrame.new(cageX, 75, z),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	for level = 0, 4 do
		local y = 14 + level * 28
		local drive = Build.Part({
			Name = "Ssd",
			Size = Vector3.new(120, 16, 200),
			CFrame = CFrame.new(cageX, y, 0),
			Color = if level % 2 == 0 then C.Black else C.MetalDark,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		Props.Label(drive, `NOVADRIVE  {level + 1}TB`, teal, Enum.NormalId.Right)
		Build.Neon({
			Name = "ActivityLed",
			Size = Vector3.new(1, 3, 16),
			CFrame = CFrame.new(cageX + 60.5, y, 80),
			Color = teal,
			Transparency = 0.1,
			Tags = { "PulseGlow" },
			Parent = model,
		})
		-- Câble SATA plat (rouge) vers le sol
		Props.Cable(model, {
			Vector3.new(cageX + 62, y, -60 + level * 6),
			Vector3.new(cageX + 90, math.max(y - 20, 3), -60 + level * 6),
			Vector3.new(-380, 2, -100 + level * 12),
		}, 1.2, C.Brand, Enum.Material.SmoothPlastic)
	end
	local light = Build.Decor({
		Name = "VaultLight",
		Size = Vector3.one,
		CFrame = CFrame.new(-400, 60, 0),
		Transparency = 1,
		Parent = model,
	})
	Build.PointLight(light, teal, 2, 120)
end

-- 4 · Cryo Tower : ventilateurs frontaux géants, radiateur, réservoir de liquide lumineux
local function buildCooling(model: Model)
	local ice = hex(Zones[4].Primary)
	-- 2 ventilateurs sur la façade (mur ouest), qui soufflent vers l'intérieur
	for _, z in { -360, -250 } do
		Props.Fan(model, CFrame.new(L.MIN_X + 16, 75, z), 96, ice, 9)
	end
	-- Radiateur devant les ventilateurs
	Props.Fins(
		model,
		CFrame.lookAt(Vector3.new(L.MIN_X + 34, 75, -305), Vector3.new(L.MIN_X + 34, 75, -306)),
		20,
		110,
		230,
		40,
		C.Aluminum
	)
	-- Réservoir + pompe (verre + liquide néon)
	local reservoir = Vector3.new(-300, 0, -370)
	Build.Cylinder({
		Name = "PumpBase",
		Size = Vector3.new(14, 44, 44),
		CFrame = CFrame.new(reservoir + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = C.Black,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Build.Cylinder({
		Name = "Reservoir",
		Size = Vector3.new(90, 36, 36),
		CFrame = CFrame.new(reservoir + Vector3.new(0, 59, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(210, 235, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		CastShadow = false,
		Parent = model,
	})
	local coolant = Build.Neon({
		Name = "Coolant",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(70, 28, 28),
		CFrame = CFrame.new(reservoir + Vector3.new(0, 52, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = ice,
		Transparency = 0.35,
		Tags = { "PulseGlow" },
		Parent = model,
	})
	Build.PointLight(coolant, ice, 2.5, 90)
	-- Tubes rigides : réservoir -> radiateur
	for i, y in { 30, 90 } do
		Props.Cable(model, {
			reservoir + Vector3.new(0, y, 18),
			Vector3.new(-300, y, -320 + i * 10),
			Vector3.new(L.MIN_X + 46, y, -320 + i * 10),
		}, 3, ice, Enum.Material.Glass)
	end
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

-- 5 · The Core : socket CPU, ventirad tour à caloducs, dissipateurs VRM
local function buildCpu(model: Model)
	local gold = hex(Zones[5].Primary)
	local center = Vector3.new(0, 0, -335)
	Build.Part({
		Name = "Socket",
		Size = Vector3.new(120, 3, 120),
		CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)),
		Color = C.Black,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	Build.Part({
		Name = "RetentionFrame",
		Size = Vector3.new(96, 5, 96),
		CFrame = CFrame.new(center + Vector3.new(0, 4, 0)),
		Color = C.Aluminum,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Build.Part({
		Name = "ColdPlate",
		Size = Vector3.new(70, 8, 70),
		CFrame = CFrame.new(center + Vector3.new(0, 10, 0)),
		Color = C.Copper,
		Material = Enum.Material.Metal,
		Reflectance = 0.1,
		Parent = model,
	})
	-- Caloducs en cuivre (on passe entre eux)
	for i = -2, 2 do
		local x = i * 13
		Props.Cable(model, {
			center + Vector3.new(x, 12, 0),
			center + Vector3.new(x, 60, 0),
			center + Vector3.new(x, 140, 0),
		}, 3, C.Copper, Enum.Material.Metal)
	end
	-- Bloc d'ailettes surélevé (on marche dessous)
	Props.Fins(model, CFrame.new(center + Vector3.new(0, 110, 0)), 130, 80, 70, 26, C.Aluminum)
	local coolerTop = Build.Part({
		Name = "CoolerTop",
		Size = Vector3.new(132, 4, 72),
		CFrame = CFrame.new(center + Vector3.new(0, 152, 0)),
		Color = C.Black,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Props.Label(coolerTop, "HELION  X-CORE", gold, Enum.NormalId.Top)
	-- Ventilateur sur le côté du ventirad (souffle vers le nord)
	Props.Fan(
		model,
		CFrame.lookAt(center + Vector3.new(0, 110, 40), center + Vector3.new(0, 110, 80))
			* CFrame.Angles(0, math.pi / 2, 0),
		86,
		gold,
		7
	)
	-- Dissipateurs VRM (en L autour du socket)
	Props.Fins(model, CFrame.new(Vector3.new(0, 18, -405)), 220, 36, 20, 10, C.MetalLight)
	Props.Fins(model, CFrame.new(-160, 18, -300), 20, 36, 200, 10, C.MetalLight)
	-- Câble EPS 8 broches
	Props.Cable(
		model,
		{ Vector3.new(-170, 3, -410), Vector3.new(-120, 12, -410), Vector3.new(-80, 12, -400) },
		2.5,
		C.Black
	)
	local light = Build.Decor({
		Name = "CoreLight",
		Size = Vector3.one,
		CFrame = CFrame.new(center + Vector3.new(0, 40, 0)),
		Transparency = 1,
		Parent = model,
	})
	Build.PointLight(light, gold, 2.2, 110)
end

-- 6 · Render Canyon : la carte graphique géante et le canyon derrière elle
local function buildGpu(model: Model)
	local green = hex(Zones[6].Primary)
	local magenta = hex(Zones[6].Secondary)
	local z = 348
	-- Slot PCIe x16
	Build.Part({
		Name = "PcieSlot",
		Size = Vector3.new(300, 8, 12),
		CFrame = CFrame.new(360, 4, z),
		Color = C.Black,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	-- Carte : PCB + carénage + backplate
	Build.Part({
		Name = "GpuPcb",
		Size = Vector3.new(320, 120, 3),
		CFrame = CFrame.new(360, 70, z),
		Color = C.PcbDark,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local shroud = Build.Part({
		Name = "Shroud",
		Size = Vector3.new(330, 126, 28),
		CFrame = CFrame.new(360, 72, z - 16),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Props.Label(shroud, "PRISM  PX-9000", magenta, Enum.NormalId.Top)
	Build.Part({
		Name = "Backplate",
		Size = Vector3.new(326, 122, 3),
		CFrame = CFrame.new(360, 71, z + 3),
		Color = C.Black,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	-- 3 ventilateurs sur la face nord (face à la plaza)
	for _, x in { 255, 360, 465 } do
		Props.Fan(
			model,
			CFrame.lookAt(Vector3.new(x, 72, z - 30.5), Vector3.new(x, 72, z - 60)) * CFrame.Angles(0, math.pi / 2, 0),
			88,
			green,
			11
		)
	end
	-- Bandeaux RGB
	Build.Neon({
		Name = "GpuRgbTop",
		Size = Vector3.new(330, 2, 30),
		CFrame = CFrame.new(360, 136, z - 16),
		Color = magenta,
		Transparency = 0.25,
		Tags = { "RgbStrip" },
		Parent = model,
	})
	Build.Neon({
		Name = "GpuRgbEdge",
		Size = Vector3.new(2, 120, 30),
		CFrame = CFrame.new(196, 72, z - 16),
		Color = green,
		Transparency = 0.25,
		Tags = { "RgbStrip" },
		Parent = model,
	})
	-- Connecteur d'alimentation 16 broches + câble
	-- Câbles d'alimentation 16 broches : de grands arcs gainés qui filent jusqu'au PSU, au-dessus de La Centrale
	for i, color in { C.Black, C.Brand, C.Black } do
		local dz = (i - 2) * 7
		Props.ArcCable(
			model,
			Vector3.new(470 + i * 6, 136, z - 16 + dz),
			Vector3.new(120, 250, 300 + dz),
			Vector3.new(-236, 60, 330 + dz),
			2.6,
			color,
			14
		)
	end
	for _, x in { 240, 360, 480 } do
		local light = Build.Decor({
			Name = "CanyonLight",
			Size = Vector3.one,
			CFrame = CFrame.new(x, 30, 400),
			Transparency = 1,
			Parent = model,
		})
		Build.PointLight(light, magenta, 1.8, 60)
	end
end

-- 7 · Neural Nexus : zone secrète près des ports arrière, puce IA flottante
local function buildAi(model: Model)
	local white = hex(Zones[7].Primary)
	local violet = hex(Zones[7].Secondary)
	-- Plaque I/O sur la paroi arrière (est) : ports géants
	local plate = Build.Part({
		Name = "IoShield",
		Size = Vector3.new(3, 150, 250),
		CFrame = CFrame.new(L.MAX_X - 3, 80, -290),
		Color = C.Aluminum,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Props.Label(plate, "USB  ·  HDMI  ·  2.5G LAN", violet, Enum.NormalId.Left)
	for i = 0, 3 do
		Build.Neon({
			Name = "UsbPort",
			Size = Vector3.new(4, 10, 24),
			CFrame = CFrame.new(L.MAX_X - 5, 40 + i * 22, -380),
			Color = Color3.fromRGB(80, 140, 255),
			Transparency = 0.15,
			Parent = model,
		})
	end
	Build.Part({
		Name = "HdmiPort",
		Size = Vector3.new(4, 14, 40),
		CFrame = CFrame.new(L.MAX_X - 5, 60, -300),
		Color = C.Black,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	Props.Fan(model, CFrame.new(L.MAX_X - 16, 90, -200), 80, violet, 9)
	-- Plateforme + puce IA flottante et ses anneaux
	local center = Vector3.new(380, 0, -330)
	Build.Cylinder({
		Name = "Pedestal",
		Size = Vector3.new(6, 90, 90),
		CFrame = CFrame.new(center + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Build.Neon({
		Name = "PedestalRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 92, 92),
		CFrame = CFrame.new(center + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = violet,
		Transparency = 0.3,
		Tags = { "PulseGlow" },
		Parent = model,
	})
	local chip = Build.Part({
		Name = "NpuChip",
		Size = Vector3.new(50, 6, 50),
		CFrame = CFrame.new(center + Vector3.new(0, 80, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = C.White,
		Material = Enum.Material.Metal,
		Reflectance = 0.2,
		Parent = model,
	})
	Props.Label(chip, "ANGA  NPU", violet, Enum.NormalId.Top)
	for i, size in { 70, 90, 110 } do
		local ring = Build.Neon({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, size, size),
			CFrame = CFrame.new(center + Vector3.new(0, 80, 0)) * CFrame.Angles(math.rad(20 * i), 0, math.pi / 2),
			Color = if i == 2 then white else violet,
			Transparency = 0.45,
			Tags = { "DecorSpin" },
			Parent = model,
		})
		ring:SetAttribute("Axis", "Y")
		ring:SetAttribute("Speed", 0.3 * i)
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
		CFrame = CFrame.new(center + Vector3.new(0, 172 + (CASE_H - 172) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
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

	-- Chipset : dissipateur bas avec hologramme du titre au-dessus
	local chipset = Build.Part({
		Name = "Chipset",
		Size = Vector3.new(70, 12, 50),
		CFrame = CFrame.new(center + Vector3.new(0, 6, -40)),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = hub,
	})
	Props.Label(chipset, "ANGAINONE  CHIPSET", C.Violet, Enum.NormalId.Top)
	Build.Neon({
		Name = "ChipsetRgb",
		Size = Vector3.new(72, 1, 52),
		CFrame = CFrame.new(center + Vector3.new(0, 0.6, -40)),
		Color = C.Violet,
		Transparency = 0.4,
		Tags = { "RgbStrip" },
		Parent = hub,
	})
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

	-- Dissipateurs M.2 + pile BIOS géante
	for _, x in { -120, 120 } do
		local m2 = Build.Part({
			Name = "M2Heatsink",
			Size = Vector3.new(80, 3, 22),
			CFrame = CFrame.new(x, 1.5, 118),
			Color = C.Aluminum,
			Material = Enum.Material.Metal,
			Parent = hub,
		})
		Props.Label(m2, "M.2", C.Cyan, Enum.NormalId.Top)
	end
	Build.Cylinder({
		Name = "CmosBattery",
		Size = Vector3.new(4, 40, 40),
		CFrame = CFrame.new(130, 2, -60) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(205, 210, 220),
		Material = Enum.Material.Metal,
		Reflectance = 0.2,
		Parent = hub,
	})
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

	-- Connecteur ATX 24 broches + faisceau qui arrive du PSU en passant très haut
	local atx = Build.Part({
		Name = "Atx24Pin",
		Size = Vector3.new(12, 8, 26),
		CFrame = CFrame.new(-160, 4, 60),
		Color = C.Black,
		Material = Enum.Material.SmoothPlastic,
		Parent = hub,
	})
	Props.Label(atx, "ATX 24", C.Gold, Enum.NormalId.Top)
	for i = -2, 2 do
		Props.ArcCable(
			hub,
			Vector3.new(-160, 8, 60 + i * 4.5),
			Vector3.new(-250, 140, 150 + i * 4.5),
			Vector3.new(-236, 50, 250 + i * 4.5),
			2,
			if i == 0 then C.Brand else C.Black,
			12
		)
	end

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
	end
	board("BenchmarkBoard", -110)
	board("WeeklyBoard", 110)

	-- Téléporteur du hub
	local teleporter = Props.Pad(hub, "Teleporter", CFrame.new(-50, 0, 105), 12, C.Cyan)
	Build.Prompt(teleporter, "Téléporteur", "Voyager", "Elevator", 12)

	-- Condensateurs décoratifs autour de la place
	-- Condensateurs aux 4 coins (hors des chemins spawn -> portails)
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		Props.Capacitor(hub, corner * Vector3.new(150, 0, 90), 6, 18, C.Black, C.Violet)
	end
	local light = Build.Decor({
		Name = "HubLight",
		Size = Vector3.one,
		CFrame = CFrame.new(0, 60, 0),
		Transparency = 1,
		Parent = hub,
	})
	Build.PointLight(light, C.White, 1.2, 160)
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
