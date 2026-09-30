--!strict
--[[
	MapBuilder : génère tout le monde de jeu de façon procédurale.

	Workspace.World
	├─ Hub (carte mère géante, socket CPU, classements, spawn)
	└─ Towers
	   └─ Tower1..6 (Model, attributs : Index, OwnerUserId, Zone, RgbHue)
	      ├─ Shell (boîtier : parois, vitres, cadre, balise AI Core)
	      └─ Floors
	         └─ Floor1..7 (Model, attributs : Zone)
	            ├─ Plate (sol, zone d'apparition des virus)
	            ├─ Modules / Z{z}M{s} (Model, attributs : ModuleId, Level)
	            ├─ Collector, Elevator, terminaux (ProximityPrompt avec attribut "Action")
	            └─ Fragments / F1..3
	Le client ajoute les animations (ventilateurs, flux de données, RGB) à partir des tags.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Theme = require(Shared.Config.Theme)
local Zones = require(Shared.Config.Zones)
local Modules = require(Shared.Config.Modules)
local WorldLayout = require(Shared.Config.WorldLayout)
local Build = require(script.Parent.Build)

local MapBuilder = {}

-- Dimensions (studs)
MapBuilder.TOWER_RADIUS = WorldLayout.TOWER_RADIUS
MapBuilder.TOWER_WIDTH = WorldLayout.TOWER_WIDTH
MapBuilder.TOWER_DEPTH = WorldLayout.TOWER_DEPTH
MapBuilder.FLOOR_HEIGHT = WorldLayout.FLOOR_HEIGHT
MapBuilder.FLOOR_COUNT = #Zones
MapBuilder.FRAGMENTS_PER_FLOOR = 3

local W, D, H = MapBuilder.TOWER_WIDTH, MapBuilder.TOWER_DEPTH, MapBuilder.FLOOR_HEIGHT

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local C = {
	Bg = hex(Theme.Colors.BgDeep),
	Pcb = hex(Theme.Colors.PcbGreen),
	MetalDark = hex(Theme.Colors.MetalDark),
	MetalLight = hex(Theme.Colors.MetalLight),
	Copper = hex(Theme.Colors.Copper),
	Gold = hex(Theme.Colors.CurrencyBits),
	Brand = hex(Theme.Colors.BrandAnga),
	Cyan = hex(Theme.Colors.AccentCyan),
	Violet = hex(Theme.Colors.AccentViolet),
	White = hex(Theme.Colors.TextPrimary),
}

MapBuilder.FloorY = WorldLayout.FloorY
MapBuilder.TowerCFrame = WorldLayout.TowerCFrame

-- Point d'apparition d'un étage (devant le collecteur), en coordonnées monde.
function MapBuilder.FloorSpawn(towerIndex: number, floor: number): CFrame
	local base = MapBuilder.TowerCFrame(towerIndex)
	-- Entre la vitre avant (z = -55) et le collecteur (z = -30 ± 7), face aux machines.
	return base * CFrame.new(0, MapBuilder.FloorY(floor) + 4, -D / 2 + 11) * CFrame.Angles(0, math.pi, 0)
end

------------------------------------------------------------------------------------
-- Hub : carte mère géante
------------------------------------------------------------------------------------

local function buildHub(world: Instance): Model
	local hub = Build.Model("Hub", world)
	hub.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- PCB principal
	Build.Part({
		Name = "Board",
		Size = Vector3.new(1000, 4, 1000),
		CFrame = CFrame.new(0, -2, 0),
		Color = C.Pcb,
		Material = Enum.Material.SmoothPlastic,
		Parent = hub,
	})

	-- Pistes de cuivre lumineuses : une vers chaque tour + anneau autour du socket.
	local traces = Build.Model("Traces", hub)
	for index = 1, GameConfig.MaxPlots do
		local towerCf = MapBuilder.TowerCFrame(index)
		local target = towerCf.Position
		local direction = target.Unit
		local length = MapBuilder.TOWER_RADIUS - D / 2 - 50
		for lane = -1, 1 do
			local offset = direction:Cross(Vector3.yAxis) * lane * 8
			local mid = direction * (50 + length / 2) + offset
			Build.Neon({
				Name = "Trace",
				Size = Vector3.new(1.2, 0.2, length),
				CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.1, 0), mid + direction + Vector3.new(0, 0.1, 0)),
				Color = if lane == 0 then C.Copper else C.Copper:Lerp(C.Bg, 0.4),
				Transparency = 0.15,
				Tags = { "DataTrace" },
				Parent = traces,
			})
		end
		-- Plot : dalle sous la tour
		Build.Part({
			Name = `PlotPad{index}`,
			Size = Vector3.new(W + 24, 1, D + 24),
			CFrame = towerCf * CFrame.new(0, -0.4, 0),
			Color = C.MetalDark,
			Material = Enum.Material.DiamondPlate,
			Parent = hub,
		})
	end

	-- Grille décorative de composants CMS (petites puces) : repères visuels au sol.
	local smd = Build.Model("SMD", hub)
	local rng = Random.new(42)
	for _ = 1, 70 do
		local r = rng:NextNumber(90, 470)
		local a = rng:NextNumber(0, math.pi * 2)
		local pos = Vector3.new(math.cos(a) * r, 0.6, math.sin(a) * r)
		local nearTower = false
		for index = 1, GameConfig.MaxPlots do
			if (MapBuilder.TowerCFrame(index).Position - pos).Magnitude < 95 then
				nearTower = true
			end
		end
		if not nearTower then
			Build.Part({
				Name = "Chip",
				Size = Vector3.new(rng:NextNumber(4, 10), rng:NextNumber(1, 2.5), rng:NextNumber(3, 8)),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = C.MetalDark:Lerp(C.Bg, 0.3),
				Material = Enum.Material.SmoothPlastic,
				CanQuery = false,
				Parent = smd,
			})
		end
	end

	-- Socket CPU central (place du hub)
	local socket = Build.Model("Socket", hub)
	Build.Part({
		Name = "Plaza",
		Size = Vector3.new(96, 2, 96),
		CFrame = CFrame.new(0, 1, 0),
		Color = C.MetalLight,
		Material = Enum.Material.Metal,
		Parent = socket,
	})
	for side = 0, 3 do
		local rot = CFrame.Angles(0, side * math.pi / 2, 0)
		Build.Neon({
			Name = "SocketEdge",
			Size = Vector3.new(96, 0.4, 1.2),
			CFrame = rot * CFrame.new(0, 2.1, -47.4),
			Color = C.Gold,
			Tags = { "RgbStrip" },
			Parent = socket,
		})
	end
	-- Broches dorées
	for x = -3, 3 do
		for z = -3, 3 do
			if math.abs(x) >= 2 or math.abs(z) >= 2 then
				Build.Decor({
					Name = "Pin",
					Size = Vector3.new(1.5, 1.2, 1.5),
					CFrame = CFrame.new(x * 11, 2.6, z * 11),
					Color = C.Gold,
					Material = Enum.Material.Foil,
					Parent = socket,
				})
			end
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.CFrame = CFrame.new(0, 2.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Neon
	spawn.Color = C.Brand
	spawn.Transparency = 0.2
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = socket

	-- Hologramme titre + deux tableaux de classement (SurfaceGui remplis par le client)
	local boards = Build.Model("Boards", hub)
	local function board(name: string, angle: number)
		local cf = CFrame.Angles(0, angle, 0) * CFrame.new(0, 26, -60)
		Build.Part({
			Name = name .. "Frame",
			Size = Vector3.new(46, 34, 1.5),
			CFrame = cf * CFrame.new(0, 0, 0.6),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Parent = boards,
		})
		local screen = Build.Decor({
			Name = name,
			Size = Vector3.new(44, 32, 0.4),
			CFrame = cf,
			Color = C.Bg,
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			Tags = { "LeaderboardScreen" },
			Parent = boards,
		})
		screen:SetAttribute("Board", name)
		Build.Part({
			Name = name .. "Leg",
			Size = Vector3.new(3, 10, 3),
			CFrame = CFrame.Angles(0, angle, 0) * CFrame.new(0, 5, -60.6),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = boards,
		})
	end
	board("BenchmarkBoard", math.rad(30))
	board("WeeklyBoard", math.rad(-30))

	local title = Build.Decor({
		Name = "TitleHologram",
		Size = Vector3.new(60, 14, 0.2),
		CFrame = CFrame.new(0, 44, 0),
		Transparency = 1,
		Tags = { "TitleHologram" },
		Parent = hub,
	})
	Build.PointLight(title, C.Violet, 2, 60)

	return hub
end

------------------------------------------------------------------------------------
-- Machines (modules) : une silhouette par composant
------------------------------------------------------------------------------------

local function glow(props: Build.Props): Part
	local part = Build.Neon(props)
	part.Transparency = 0.05
	local tags = { "TierGlow" }
	for _, tag in (props.Tags or {}) :: { string } do
		table.insert(tags, tag)
	end
	part:SetAttribute("GlowStrength", 1)
	for _, tag in tags do
		part:AddTag(tag)
	end
	return part
end

local function spinner(model: Model, cf: CFrame, radius: number, color: Color3, axis: string)
	-- Hélice : un disque + 3 pales, tournées côté client (tag "Spin").
	local hub = Build.Decor({
		Name = "SpinHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, radius * 0.5, radius * 0.5),
		CFrame = cf,
		Color = C.MetalLight,
		Material = Enum.Material.Metal,
		Tags = { "Spin" },
		Parent = model,
	})
	hub:SetAttribute("Axis", axis)
	for blade = 0, 2 do
		local b = Build.Decor({
			Name = "Blade",
			Size = Vector3.new(0.3, radius * 0.9, radius * 0.28),
			CFrame = cf * CFrame.Angles(blade * math.pi * 2 / 3, 0, 0) * CFrame.new(0, radius * 0.45, 0),
			Color = C.MetalDark:Lerp(color, 0.25),
			Material = Enum.Material.SmoothPlastic,
			Parent = hub,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = b
		weld.Parent = b
		b.Anchored = false
	end
	Build.Neon({
		Name = "FanRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2 + 1, radius * 2 + 1),
		CFrame = cf * CFrame.new(-0.3, 0, 0),
		Color = color,
		Transparency = 0.6,
		Parent = model,
	})
end

local function buildMachine(
	def: Modules.ModuleDef,
	cf: CFrame,
	parent: Instance,
	primary: Color3,
	secondary: Color3
): Model
	local model = Build.Model(def.Id, parent)
	model:SetAttribute("ModuleId", def.Id)
	model:SetAttribute("Level", 0)
	local scale = 0.8 + def.Slot * 0.2

	local base = Build.Part({
		Name = "Base",
		Size = Vector3.new(14, 2, 14),
		CFrame = cf * CFrame.new(0, 1, 0),
		Color = C.MetalDark,
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	model.PrimaryPart = base
	glow({
		Name = "BaseGlow",
		Size = Vector3.new(14.2, 0.3, 14.2),
		CFrame = cf * CFrame.new(0, 2.1, 0),
		Color = primary,
		Transparency = 0.5,
		Parent = model,
	})

	local top = 2
	local zone = def.Zone
	if zone == 1 then
		-- Condensateur géant
		local height = 10 * scale
		Build.Cylinder({
			Name = "Body",
			Size = Vector3.new(height, 8, 8),
			CFrame = cf * CFrame.new(0, top + height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = C.MetalDark:Lerp(primary, 0.15),
			Material = Enum.Material.Metal,
			Parent = model,
		})
		for ring = 1, 2 do
			glow({
				Name = "Ring",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.5, 8.4, 8.4),
				CFrame = cf * CFrame.new(0, top + height * ring / 3, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Color = primary,
				Parent = model,
			})
		end
		top += height
	elseif zone == 2 then
		-- Barrettes de RAM (lames verticales)
		local height = 12 * scale
		for i = -1, 1 do
			Build.Part({
				Name = "Stick",
				Size = Vector3.new(1.4, height, 10),
				CFrame = cf * CFrame.new(i * 3.2, top + height / 2, 0),
				Color = C.MetalDark,
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
			glow({
				Name = "StickGlow",
				Size = Vector3.new(1.5, 0.6, 10.1),
				CFrame = cf * CFrame.new(i * 3.2, top + height - 0.3, 0),
				Color = primary,
				Parent = model,
			})
			for chip = -1, 1 do
				Build.Decor({
					Name = "Chip",
					Size = Vector3.new(1.6, 2, 2.4),
					CFrame = cf * CFrame.new(i * 3.2, top + height * 0.45, chip * 3),
					Color = C.Bg,
					Material = Enum.Material.SmoothPlastic,
					Parent = model,
				})
			end
		end
		top += height
	elseif zone == 3 then
		-- Carte NVMe : plaque + puces NAND
		local height = 2 + scale
		Build.Part({
			Name = "Pcb",
			Size = Vector3.new(12, height, 8),
			CFrame = cf * CFrame.new(0, top + height / 2, 0),
			Color = C.Pcb:Lerp(primary, 0.1),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		for i = -1, 1 do
			Build.Decor({
				Name = "Nand",
				Size = Vector3.new(3, 1, 5),
				CFrame = cf * CFrame.new(i * 3.8, top + height + 0.5, 0),
				Color = C.Bg,
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
			glow({
				Name = "NandGlow",
				Size = Vector3.new(3.1, 0.2, 0.4),
				CFrame = cf * CFrame.new(i * 3.8, top + height + 1.05, -2),
				Color = primary,
				Parent = model,
			})
		end
		top += height + 1
	elseif zone == 4 then
		-- Ventilateur géant vertical
		local radius = 5 * scale
		Build.Part({
			Name = "Frame",
			Size = Vector3.new(radius * 2 + 2, radius * 2 + 2, 2),
			CFrame = cf * CFrame.new(0, top + radius + 1, 1.5),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Transparency = 0.2,
			Parent = model,
		})
		spinner(
			model,
			cf * CFrame.new(0, top + radius + 1, -0.2) * CFrame.Angles(0, math.pi / 2, 0),
			radius,
			primary,
			"X"
		)
		top += radius * 2 + 2
	elseif zone == 5 then
		-- Die CPU
		local height = 3 * scale
		Build.Part({
			Name = "Die",
			Size = Vector3.new(11, height, 11),
			CFrame = cf * CFrame.new(0, top + height / 2, 0),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		Build.Decor({
			Name = "Ihs",
			Size = Vector3.new(8, 0.6, 8),
			CFrame = cf * CFrame.new(0, top + height + 0.3, 0),
			Color = C.Gold,
			Material = Enum.Material.Foil,
			Parent = model,
		})
		glow({
			Name = "CoreX",
			Size = Vector3.new(8.2, 0.3, 0.5),
			CFrame = cf * CFrame.new(0, top + height + 0.7, 0),
			Color = primary,
			Parent = model,
		})
		glow({
			Name = "CoreZ",
			Size = Vector3.new(0.5, 0.3, 8.2),
			CFrame = cf * CFrame.new(0, top + height + 0.7, 0),
			Color = primary,
			Parent = model,
		})
		top += height + 1
	elseif zone == 6 then
		-- Carte graphique triple ventilateur
		local height = 5
		Build.Part({
			Name = "Shroud",
			Size = Vector3.new(13, height, 5 + scale * 2),
			CFrame = cf * CFrame.new(0, top + height / 2 + 1, 0),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		glow({
			Name = "ShroudGlow",
			Size = Vector3.new(13.1, 0.4, 0.4),
			CFrame = cf * CFrame.new(0, top + height + 1, -(2.5 + scale)),
			Color = secondary,
			Parent = model,
		})
		for i = -1, 1 do
			spinner(
				model,
				cf * CFrame.new(i * 4.2, top + height + 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
				1.8,
				primary,
				"X"
			)
		end
		top += height + 2
	else
		-- Orbe neuronal
		local radius = 2.5 + scale * 1.5
		Build.Part({
			Name = "Pedestal",
			Size = Vector3.new(6, 4, 6),
			CFrame = cf * CFrame.new(0, top + 2, 0),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		glow({
			Name = "Orb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(radius * 2, radius * 2, radius * 2),
			CFrame = cf * CFrame.new(0, top + 6 + radius, 0),
			Color = primary,
			Transparency = 0.15,
			Parent = model,
		})
		local ring = Build.Neon({
			Name = "Halo",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, radius * 3, radius * 3),
			CFrame = cf * CFrame.new(0, top + 6 + radius, 0),
			Color = secondary,
			Transparency = 0.5,
			Tags = { "Spin" },
			Parent = model,
		})
		ring:SetAttribute("Axis", "Y")
		top += 6 + radius * 2
	end

	-- Point d'ancrage de l'étiquette et du prompt
	local anchor = Build.Decor({
		Name = "LabelAnchor",
		Size = Vector3.one,
		CFrame = cf * CFrame.new(0, top + 3, 0),
		Transparency = 1,
		Parent = model,
	})
	Build.Prompt(anchor, "Améliorer", def.Name, "Upgrade", 14):SetAttribute("ModuleId", def.Id)
	return model
end

------------------------------------------------------------------------------------
-- Terminaux, pads, fragments
------------------------------------------------------------------------------------

local function terminal(
	parent: Instance,
	name: string,
	cf: CFrame,
	color: Color3,
	actionText: string,
	objectText: string,
	action: string
): Model
	local model = Build.Model(name, parent)
	local stand = Build.Part({
		Name = "Stand",
		Size = Vector3.new(4, 5, 3),
		CFrame = cf * CFrame.new(0, 2.5, 0),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	model.PrimaryPart = stand
	local screen = Build.Decor({
		Name = "Screen",
		Size = Vector3.new(6, 4, 0.4),
		CFrame = cf * CFrame.new(0, 6.5, -0.4) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = C.Bg,
		Material = Enum.Material.Glass,
		Transparency = 0.05,
		Tags = { "TerminalScreen" },
		Parent = model,
	})
	screen:SetAttribute("Label", objectText)
	screen:SetAttribute("Accent", color:ToHex())
	Build.Neon({
		Name = "Trim",
		Size = Vector3.new(6.2, 0.25, 0.5),
		CFrame = cf * CFrame.new(0, 4.4, -0.6),
		Color = color,
		Parent = model,
	})
	Build.PointLight(screen, color, 0.8, 10)
	Build.Prompt(stand, actionText, objectText, action, 12)
	return model
end

local function pad(parent: Instance, name: string, cf: CFrame, diameter: number, color: Color3): Part
	local base = Build.Cylinder({
		Name = name,
		Size = Vector3.new(0.6, diameter, diameter),
		CFrame = cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		CanTouch = true,
		Parent = parent,
	})
	Build.Neon({
		Name = name .. "Glow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, diameter - 1.5, diameter - 1.5),
		CFrame = cf * CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Transparency = 0.25,
		Tags = { "PulseGlow" },
		Parent = parent,
	})
	return base
end

-- Positions des fragments cachés par étage (coordonnées locales de l'étage).
local FRAGMENT_SPOTS = {
	Vector3.new(-50, 3, 50),
	Vector3.new(50, 3, 50),
	Vector3.new(50, 3, -50),
}

------------------------------------------------------------------------------------
-- Tour
------------------------------------------------------------------------------------

local function buildFloor(floors: Instance, towerCf: CFrame, k: number): Model
	local zone = Zones[k]
	local primary, secondary = hex(zone.Primary), hex(zone.Secondary)
	local floor = Build.Model(`Floor{k}`, floors)
	floor:SetAttribute("Zone", k)
	local y = MapBuilder.FloorY(k)
	local origin = towerCf * CFrame.new(0, y, 0)

	local plate = Build.Part({
		Name = "Plate",
		Size = Vector3.new(W - 4, 2, D - 4),
		CFrame = origin * CFrame.new(0, -1, 0),
		Color = C.MetalDark:Lerp(C.Bg, 0.35),
		Material = Enum.Material.DiamondPlate,
		Parent = floor,
	})
	floor.PrimaryPart = plate

	-- Bordures néon de la couleur de la zone (le client les anime)
	for side = 0, 3 do
		Build.Neon({
			Name = "Edge",
			Size = Vector3.new(W - 6, 0.3, 0.8),
			CFrame = origin * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0.2, -(D / 2 - 3)),
			Color = primary,
			Transparency = 0.1,
			Tags = { "ZoneEdge" },
			Parent = floor,
		})
	end
	-- Piste de données : machines -> collecteur
	for slot = 1, 3 do
		local x = (slot - 2) * 32
		local from = Vector3.new(x, 0.15, 14)
		local to = Vector3.new(0, 0.15, -30)
		local mid = (from + to) / 2
		local length = (to - from).Magnitude
		local trace = Build.Neon({
			Name = `Trace{slot}`,
			Size = Vector3.new(0.8, 0.12, length),
			CFrame = origin * CFrame.lookAt(mid, to),
			Color = primary:Lerp(C.Copper, 0.5),
			Transparency = 0.35,
			Tags = { "FloorTrace" },
			Parent = floor,
		})
		trace:SetAttribute("Slot", slot)
	end

	-- Lumières d'ambiance
	local lightAnchor = Build.Decor({
		Name = "Lights",
		Size = Vector3.one,
		CFrame = origin * CFrame.new(0, H - 8, 0),
		Transparency = 1,
		Parent = floor,
	})
	Build.PointLight(lightAnchor, primary, 1.2, 60)
	local lightAnchor2 = Build.Decor({
		Name = "Lights2",
		Size = Vector3.one,
		CFrame = origin * CFrame.new(0, 10, -30),
		Transparency = 1,
		Parent = floor,
	})
	Build.PointLight(lightAnchor2, secondary, 0.8, 40)

	-- Machines
	local modules = Build.Model("Modules", floor)
	for _, def in Modules.ForZone(k) do
		local cf = origin * CFrame.new((def.Slot - 2) * 32, 0, 22) * CFrame.Angles(0, math.pi, 0)
		buildMachine(def, cf, modules, primary, secondary)
	end

	-- Collecteur (northbridge) : on marche dessus pour encaisser
	local collector = pad(floor, "Collector", origin * CFrame.new(0, 0, -30), 14, C.Gold)
	collector:SetAttribute("Floor", k)
	collector:AddTag("Collector")

	-- Ascenseur
	local elevator = pad(floor, "Elevator", origin * CFrame.new(-42, 0, -38), 10, C.Cyan)
	Build.Prompt(elevator, "Ascenseur", "Changer d'étage", "Elevator", 10)

	-- Terminaux spécifiques
	local facing = CFrame.Angles(0, math.pi, 0)
	if k < #Zones then
		terminal(
			floor,
			"UnlockTerminal",
			origin * CFrame.new(42, 0, -38) * facing,
			hex(Zones[k + 1].Primary),
			"Débloquer",
			Zones[k + 1].Name,
			"Unlock"
		)
	end
	if k == 1 then
		terminal(
			floor,
			"PowerTerminal",
			origin * CFrame.new(-44, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			C.Gold,
			"Bloc d'alimentation",
			"Capacité en Watts",
			"Power"
		)
	elseif k == 2 then
		terminal(
			floor,
			"CapsuleTerminal",
			origin * CFrame.new(-44, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			C.Violet,
			"Ouvrir",
			"Capsules de Nanobots",
			"Capsules"
		)
	elseif k == 3 then
		terminal(
			floor,
			"DownloadTerminal",
			origin * CFrame.new(-44, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			primary,
			"Télécharger",
			"Téléchargements",
			"Downloads"
		)
	elseif k == 4 then
		terminal(
			floor,
			"CoolingTerminal",
			origin * CFrame.new(-44, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			C.Cyan,
			"Radiateurs",
			"Capacité thermique",
			"Cooling"
		)
	elseif k == 5 then
		terminal(
			floor,
			"OverclockTerminal",
			origin * CFrame.new(-44, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			C.Brand,
			"Overclocker",
			"Station d'overclock",
			"Overclock"
		)
	elseif k == 6 then
		terminal(
			floor,
			"RebootTerminal",
			origin * CFrame.new(-44, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			C.Violet,
			"Reboot",
			"Console BIOS",
			"Reboot"
		)
	elseif k == 7 then
		terminal(
			floor,
			"SingularityTerminal",
			origin * CFrame.new(-44, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			C.White,
			"Construire",
			"La Singularité",
			"Singularity"
		)
	end

	-- Fragments de données cachés
	local fragments = Build.Folder("Fragments", floor)
	for index, spot in FRAGMENT_SPOTS do
		local fragment = Build.Part({
			Name = `F{index}`,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 2.2, 2.2),
			CFrame = origin * CFrame.new(spot),
			Color = C.White,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = true,
			CastShadow = false,
			Tags = { "Fragment" },
			Parent = fragments,
		})
		fragment:SetAttribute("FragmentId", `Z{k}F{index}`)
		Build.PointLight(fragment, secondary, 1, 12)
	end

	return floor
end

local function buildShell(tower: Model, towerCf: CFrame)
	local shell = Build.Model("Shell", tower)
	local totalHeight = MapBuilder.FloorY(#Zones) + H
	local glassColor = C.Violet:Lerp(C.Bg, 0.6)

	-- Paroi arrière + paroi droite (métal), paroi gauche (verre trempé)
	Build.Part({
		Name = "Back",
		Size = Vector3.new(W, totalHeight, 2),
		CFrame = towerCf * CFrame.new(0, totalHeight / 2, D / 2),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = shell,
	})
	Build.Part({
		Name = "Right",
		Size = Vector3.new(2, totalHeight, D),
		CFrame = towerCf * CFrame.new(W / 2, totalHeight / 2, 0),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = shell,
	})
	Build.Part({
		Name = "LeftGlass",
		Size = Vector3.new(1, totalHeight, D),
		CFrame = towerCf * CFrame.new(-W / 2, totalHeight / 2, 0),
		Color = glassColor,
		Material = Enum.Material.Glass,
		Transparency = 0.65,
		CastShadow = false,
		Parent = shell,
	})

	-- Façade avant en verre avec porte au rez-de-chaussée
	local doorWidth, doorHeight = 30, 22
	local sideWidth = (W - doorWidth) / 2
	for side = -1, 1, 2 do
		Build.Part({
			Name = "FrontLow",
			Size = Vector3.new(sideWidth, doorHeight, 1),
			CFrame = towerCf * CFrame.new(side * (doorWidth / 2 + sideWidth / 2), doorHeight / 2, -D / 2),
			Color = glassColor,
			Material = Enum.Material.Glass,
			Transparency = 0.6,
			CastShadow = false,
			Parent = shell,
		})
	end
	Build.Part({
		Name = "FrontHigh",
		Size = Vector3.new(W, totalHeight - doorHeight, 1),
		CFrame = towerCf * CFrame.new(0, doorHeight + (totalHeight - doorHeight) / 2, -D / 2),
		Color = glassColor,
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		CastShadow = false,
		Parent = shell,
	})

	-- Cadre (montants) et bandes RGB sur les arêtes
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		local pos = Vector3.new(corner.X * W / 2, totalHeight / 2, corner.Z * D / 2)
		Build.Part({
			Name = "Pillar",
			Size = Vector3.new(4, totalHeight, 4),
			CFrame = towerCf * CFrame.new(pos),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = shell,
		})
		Build.Neon({
			Name = "RgbEdge",
			Size = Vector3.new(0.6, totalHeight, 0.6),
			CFrame = towerCf * CFrame.new(pos + Vector3.new(-corner.X * 2.2, 0, -corner.Z * 2.2)),
			Color = C.Violet,
			Tags = { "RgbStrip" },
			Parent = shell,
		})
	end
	-- Toit + balise de l'AI Core (repère visible de tout le hub)
	Build.Part({
		Name = "Roof",
		Size = Vector3.new(W + 4, 3, D + 4),
		CFrame = towerCf * CFrame.new(0, totalHeight + 1.5, 0),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = shell,
	})
	local beacon = Build.Neon({
		Name = "Beacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(14, 14, 14),
		CFrame = towerCf * CFrame.new(0, totalHeight + 12, 0),
		Color = hex(Zones[#Zones].Primary),
		Transparency = 0.1,
		Tags = { "Beacon" },
		Parent = shell,
	})
	Build.PointLight(beacon, C.Violet, 3, 60)
	Build.Neon({
		Name = "BeaconBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(160, 3, 3),
		CFrame = towerCf * CFrame.new(0, totalHeight + 92, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = C.Violet,
		Transparency = 0.75,
		Tags = { "Beacon" },
		Parent = shell,
	})

	-- Enseigne au-dessus de la porte (SurfaceGui rempli par le client)
	local sign = Build.Decor({
		Name = "Sign",
		Size = Vector3.new(34, 7, 0.4),
		CFrame = towerCf * CFrame.new(0, doorHeight + 5, -D / 2 - 0.9) * CFrame.Angles(0, math.pi, 0),
		Color = C.Bg,
		Transparency = 1,
		Tags = { "TowerSign" },
		Parent = shell,
	})
	sign:SetAttribute("Face", "Front")
end

local function buildTower(towers: Instance, index: number): Model
	local towerCf = MapBuilder.TowerCFrame(index)
	local tower = Build.Model(`Tower{index}`, towers)
	tower:SetAttribute("Index", index)
	tower:SetAttribute("OwnerUserId", 0)
	tower:SetAttribute("OwnerName", "")
	tower:SetAttribute("Zone", 0)
	tower:SetAttribute("RgbHue", -1)
	tower:SetAttribute("PoweredOn", false)
	tower.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	buildShell(tower, towerCf)
	local floors = Build.Folder("Floors", tower)
	for k = 1, #Zones do
		buildFloor(floors, towerCf, k)
	end
	Build.Folder("Viruses", tower)
	return tower
end

function MapBuilder.Build(): (Model, { Model })
	local existing = Workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	local hub = buildHub(world)
	local towerFolder = Build.Folder("Towers", world)
	local towers = {}
	for index = 1, GameConfig.MaxPlots do
		table.insert(towers, buildTower(towerFolder, index))
	end
	world.Parent = Workspace
	return hub, towers
end

return MapBuilder
