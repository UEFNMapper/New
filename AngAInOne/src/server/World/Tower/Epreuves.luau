--!strict
--[[
	Epreuves (serveur) : le décor de l'épreuve 3D de chaque salle du terminal (Config/Epreuves).
	Tout est posé en coordonnées de salle (u, v) : u le long de F, v le long de R (Common.House) ;
	le pad d'arrivée est en (0, 0), la borne en (12, -36), l'écran sur le mur du fond (v = -44), le
	portail de sortie en u = 29, v ∈ [-44, -32]. Zones libres : u ∈ [9, 28] × v ∈ [-30, 6] et
	u ∈ [-7, 8] × v ∈ [-40, -9].

	Le décor est fixe ; le jeu (prompts, animations, ennemis) est 100 % client
	(Controllers/Epreuves). Dossier Terminal/Epreuve : attributs World, Kind, Stage, et le repère de
	la salle (Origin = plancher en (0, 0), AxisF, AxisR) pour que le client place ses objets.
	Repères nommés (le client les retrouve par nom) : voir chaque monde ci-dessous.
	Partout : l'écran du fond devient la fiche de l'épreuve (format Diagnostic de l'app) et la borne
	propose « Lancer » au lieu de « Nettoyer ».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local EpreuveConfig = require(Shared.Config.Epreuves)
local Startup = require(Shared.EpreuveLogic.Startup)
local RamSlots = require(Shared.EpreuveLogic.RamSlots)
local Debloat = require(Shared.EpreuveLogic.Debloat)
local Cooling = require(Shared.EpreuveLogic.Cooling)
local CpuDefense = require(Shared.EpreuveLogic.CpuDefense)
local Driver = require(Shared.EpreuveLogic.Driver)
local Investigation = require(Shared.EpreuveLogic.Investigation)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local AppBoard = require(script.Parent.Parent.AppBoard)
local ModelLibrary = require(script.Parent.Parent.ModelLibrary)
local Common = require(script.Parent.Common)

local Epreuves = {}

local C = Props.C
local A = AppBoard.C
local P = Common.P
local facing = Common.Facing
local UP = Vector3.yAxis
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass
local AMBER = Color3.fromHex("F6AD55")

type Frame = Common.Frame

-- Contexte d'une salle : repère, plancher, dossier de l'épreuve.
type Room = {
	Ctx: Common.WorldContext,
	Fr: Frame,
	Y: number,
	House: Instance,
	Folder: Folder,
	Def: EpreuveConfig.Epreuve,
}

local function at(room: Room, u: number, h: number, v: number): Vector3
	return P(room.Fr, u, room.Y + h, v)
end

local function decor(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return Props.Box(parent, name, size, cf, color, material)
end

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
		Material = material or METAL,
		Parent = parent,
	})
end

local function neon(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	return Build.Neon({ Name = name, Size = size, CFrame = cf, Color = color, Parent = parent })
end

-- Repère invisible (attributs lus par le client).
local function marker(parent: Instance, name: string, position: Vector3, attributes: { [string]: any }?): Part
	local part = decor(parent, name, Vector3.one, CFrame.new(position), C.White)
	part.Transparency = 1
	for key, value in (attributes or {}) :: { [string]: any } do
		part:SetAttribute(key, value)
	end
	return part
end

-- CFrame dont le X local suit R (pour les objets longs posés le long de v).
local function alongR(room: Room, position: Vector3): CFrame
	return CFrame.fromMatrix(position, room.Fr.R, UP)
end

-- Panneau mural (mur intérieur v = 7, tourné vers la salle) au style de l'app.
local function wallBoard(room: Room, name: string, u: number, size: Vector2, spec: AppBoard.Spec): Part
	local cf = facing(at(room, u, 3 + size.Y / 2, 6.65), -room.Fr.R)
	return AppBoard.Panel(room.Folder, name, size, cf, spec)
end

------------------------------------------------------------------------------------
-- Monde 1 · Le Démarrage infecté : couloir de portes, un levier par programme
------------------------------------------------------------------------------------

Epreuves.DOOR_ROWS = { West = 10.3, East = 25.7 }
Epreuves.DOOR_V = { -2, -11, -20 }

-- Petit interrupteur façon app : pilule violette (allumé) et rond blanc qui coulisse (LeverKnob).
local function toggle(folder: Instance, plate: BasePart)
	plate.Color = A.Accent
	plate.Material = NEON
	decor(folder, "LeverKnob", Vector3.new(0.6, 0.6, 0.25), plate.CFrame * CFrame.new(0.4, 0, -0.05), A.Text, SMOOTH)
end

local function startupDoor(room: Room, index: number, door: Startup.Door, cf: CFrame)
	local folder = Build.Folder(`Door{index}`, room.Folder)
	folder:SetAttribute("Index", index)
	folder:SetAttribute("DoorId", door.Id)
	local leaf = decor(folder, "DoorLeaf", Vector3.new(5, 8.6, 0.35), cf * CFrame.new(0, 4.3, 0), A.Card, SMOOTH)
	AppBoard.Build(leaf, {
		Page = "Démarrage",
		Title = door.Name,
		TitleWrap = true,
		Rows = {
			{ "Éditeur", door.Editor, if door.Culprit then "FF99A4" else "6CCB5F" },
			{ "Impact", door.Impact },
			{ "Au démarrage", "Activé", "6CCB5F" },
		},
		Pixels = 60,
		Scale = 0.62,
	})
	for _, side in { -1, 1 } do
		decor(folder, "DoorPost", Vector3.new(0.5, 9.2, 0.7), cf * CFrame.new(side * 2.75, 4.6, 0), C.MetalDark, METAL)
	end
	decor(folder, "DoorLintel", Vector3.new(6, 0.6, 0.7), cf * CFrame.new(0, 9.2, 0), C.MetalDark, METAL)
	neon(folder, "DoorLed", Vector3.new(4.4, 0.25, 0.15), cf * CFrame.new(0, 8.85, -0.35), A.Good)
	if door.Culprit then
		-- Lueur violette sous la porte et deux yeux dans le trou de serrure : quelqu'un se cache derrière
		neon(folder, "DoorLeak", Vector3.new(4.6, 0.15, 0.7), cf * CFrame.new(0, 0.08, -0.45), C.Violet).Transparency =
			0.25
		for _, side in { -1, 1 } do
			neon(folder, "DoorEye", Vector3.new(0.22, 0.22, 0.1), cf * CFrame.new(side * 0.3, 2.2, -0.2), C.White)
		end
	end
	-- Levier : borne + interrupteur façon app (activé)
	local post = decor(folder, "LeverPost", Vector3.new(1, 3.4, 1), cf * CFrame.new(3.7, 1.7, -1.2), C.MetalDark, METAL)
	post:SetAttribute("Door", index)
	local plate =
		decor(folder, "LeverPlate", Vector3.new(1.6, 0.8, 0.2), cf * CFrame.new(3.7, 3.0, -1.75), A.Surface, SMOOTH)
	toggle(folder, plate)
end

local function buildStartup(room: Room)
	local fr = room.Fr
	-- Mur ouest du couloir, tourné vers le pad : la page Démarrage de l'app en grand
	local wallCf = facing(at(room, 9.9, 5, -11), -fr.F)
	local wall = solid(room.Folder, "StartupWall", Vector3.new(27, 10, 0.4), wallCf, A.Surface, SMOOTH)
	AppBoard.Build(wall, {
		Page = "Démarrage",
		Title = "Ce qui se lance avec Windows",
		Subtitle = "6 programmes au démarrage · temps de démarrage : 3 min 02 · deux éditeurs inconnus",
		Rows = {
			{ "Programmes activés", "6" },
			{ "Impact élevé", "3", "FCE100" },
			{ "Éditeur inconnu", "2", "FF99A4" },
		},
		Pixels = 30,
		Scale = 1.1,
	})
	for i, door in Startup.DOORS do
		local west = i <= 3
		local u = if west then Epreuves.DOOR_ROWS.West else Epreuves.DOOR_ROWS.East
		local v = Epreuves.DOOR_V[(i - 1) % 3 + 1]
		startupDoor(room, i, door, facing(at(room, u, 0, v), if west then fr.F else -fr.F))
	end
	-- Fond du couloir côté est et piste lumineuse au sol
	decor(room.Folder, "StartupBack", Vector3.new(27, 10, 0.4), facing(at(room, 26.6, 5, -11), fr.F), A.Surface, SMOOTH)
	neon(room.Folder, "Runway", Vector3.new(26, 0.12, 0.6), alongR(room, at(room, 18, 0.07, -11)), C.Cyan).Transparency =
		0.4
end

------------------------------------------------------------------------------------
-- Monde 2 · La RAM saturée : quatre emplacements A1 A2 B1 B2, deux barrettes, « Libérer la RAM »
------------------------------------------------------------------------------------

Epreuves.SLOT_U = { 11, 15.6, 20.2, 24.8 }
Epreuves.SLOT_V = -12
Epreuves.FLUSH_AT = Vector2.new(2, -21)

local function stickFallback(parent: Instance, name: string, cf: CFrame): Instance
	local model = Build.Model(name, parent)
	decor(model, "Pcb", Vector3.new(19, 5.8, 0.35), cf * CFrame.new(0, 3.2, 0), Color3.fromRGB(34, 110, 70), SMOOTH)
	decor(model, "Contacts", Vector3.new(19, 0.7, 0.4), cf * CFrame.new(0, 0.35, 0), C.Gold, Enum.Material.Foil)
	for k = 0, 7 do
		for _, side in { -1, 1 } do
			decor(
				model,
				"Chip",
				Vector3.new(1.7, 2.4, 0.25),
				cf * CFrame.new(-7.9 + k * 2.25, 3.3, side * 0.3),
				C.Black,
				SMOOTH
			)
		end
	end
	return model
end

local function buildRamSlots(room: Room)
	local fr = room.Fr
	decor(
		room.Folder,
		"Motherboard",
		Vector3.new(20, 0.25, 30),
		CFrame.fromMatrix(at(room, 18, 0.125, -12), fr.F, UP),
		C.Pcb,
		SMOOTH
	)
	for k = 0, 5 do
		neon(
			room.Folder,
			"Trace",
			Vector3.new(19, 0.06, 0.18),
			CFrame.fromMatrix(at(room, 18, 0.27, -25 + k * 0.9), fr.F, UP),
			C.Copper
		).Transparency =
			0.5
	end
	for slot, name in RamSlots.SLOTS do
		local u = Epreuves.SLOT_U[slot]
		local base = at(room, u, 0.25, Epreuves.SLOT_V)
		local cf = alongR(room, base)
		local placed = ModelLibrary.Place(
			"DimmSlot",
			cf,
			room.Folder,
			{ Fit = Vector3.new(20.5, 2.4, 1.7), Name = `DimmSlot{slot}` },
			function(): Instance?
				local model = Build.Model(`DimmSlot{slot}`, room.Folder)
				decor(model, "Body", Vector3.new(20.5, 1.2, 1.6), cf * CFrame.new(0, 0.6, 0), C.Black, SMOOTH)
				for _, side in { -1, 1 } do
					decor(
						model,
						"Latch",
						Vector3.new(0.8, 2.2, 1.8),
						cf * CFrame.new(side * 10.6, 1.1, 0),
						C.Silk,
						SMOOTH
					)
				end
				return model
			end
		)
		if placed then
			placed:SetAttribute("Slot", slot)
		end
		marker(room.Folder, `Slot{slot}`, base + UP * 3, { Slot = slot, Name = name })
		local label = decor(
			room.Folder,
			"SlotLabel",
			Vector3.new(3.2, 0.15, 2.2),
			CFrame.fromMatrix(at(room, u, 0.33, -24.2), fr.F, UP),
			A.Surface,
			SMOOTH
		)
		Props.Sign(
			label,
			name,
			if RamSlots.TARGET[slot] then "double canal" else nil,
			C.White,
			A.Dim,
			Enum.NormalId.Top
		)
	end
	for stick, slot in RamSlots.START do
		local cf = alongR(room, at(room, Epreuves.SLOT_U[slot], 1.35, Epreuves.SLOT_V))
		local model = ModelLibrary.Place(
			"RamStick",
			cf,
			room.Folder,
			{ Fit = Vector3.new(19, 6.6, 0.95), Name = `Stick{stick}` },
			function(): Instance?
				return stickFallback(room.Folder, `Stick{stick}`, cf)
			end
		)
		if model then
			model:SetAttribute("Stick", stick)
		end
	end
	wallBoard(room, "RamBoard", 18, Vector2.new(15, 10.5), {
		Page = "Tableau de bord · Mémoire",
		Title = "Mémoire 15,7 / 16 Go",
		Rows = {
			{ "A1", "● Barrette", "6CCB5F" },
			{ "A2", "○ Vide", "8F8F8F" },
			{ "B1", "● Barrette", "6CCB5F" },
			{ "B2", "○ Vide", "8F8F8F" },
			{ "Mode", "Simple canal", "FF99A4" },
		},
		Bar = { Label = "Utilisée : 98 %", Value = 0.98, Color = A.Bad },
		Pixels = 56,
	})
	-- Le gros bouton « Libérer la RAM »
	local flush = at(room, Epreuves.FLUSH_AT.X, 0, Epreuves.FLUSH_AT.Y)
	Props.Rod(
		room.Folder,
		"FlushBase",
		CFrame.new(flush + UP * 0.6) * CFrame.Angles(0, 0, math.pi / 2),
		1.2,
		6.4,
		C.MetalDark,
		METAL
	)
	local cap = Props.Rod(
		room.Folder,
		"FlushCap",
		CFrame.new(flush + UP * 1.55) * CFrame.Angles(0, 0, math.pi / 2),
		0.8,
		4.8,
		Color3.fromHex("FF5A5F"),
		NEON
	)
	cap:SetAttribute("Flush", true)
	AppBoard.Panel(
		room.Folder,
		"FlushSign",
		Vector2.new(7, 3),
		facing(flush + UP * 5, fr.R + fr.F * 0.4) * CFrame.Angles(math.rad(-12), 0, 0),
		{
			Page = "Tableau de bord",
			Title = "Libérer la RAM",
			Pixels = 60,
			Scale = 0.9,
		}
	)
end

------------------------------------------------------------------------------------
-- Monde 3 · L'invasion du Bloatware : aspirer les bloatware dans la Corbeille
------------------------------------------------------------------------------------

Epreuves.MONSTER_SPAWNS =
	{ Vector2.new(2, -18), Vector2.new(14, -8), Vector2.new(21, -22), Vector2.new(6, -32), Vector2.new(15, -30) }
Epreuves.ROAM = { Min = Vector2.new(-4, -40), Max = Vector2.new(27, 0) }
Epreuves.PRESET_AT = Vector2.new(-2, -25)

local function buildDebloat(room: Room)
	local fr = room.Fr
	for i, spot in Epreuves.MONSTER_SPAWNS do
		marker(room.Folder, `MonsterSpawn{i}`, at(room, spot.X, 3, spot.Y), { Index = i })
	end
	room.Folder:SetAttribute("RoamMin", Epreuves.ROAM.Min)
	room.Folder:SetAttribute("RoamMax", Epreuves.ROAM.Max)
	-- Pad du preset « Performance » (power-up : la page Optimisations rappelle des dizaines de réglages d'un coup)
	local pad = decor(
		room.Folder,
		"PresetPad",
		Vector3.new(6, 0.3, 6),
		CFrame.fromMatrix(at(room, Epreuves.PRESET_AT.X, 0.15, Epreuves.PRESET_AT.Y), fr.F, UP),
		A.Surface,
		SMOOTH
	)
	Props.Sign(pad, "PRESET", "Performance", C.Violet, A.Dim, Enum.NormalId.Top)
	Props.Ring(
		room.Folder,
		"PresetRing",
		CFrame.new(pad.CFrame.Position + UP * 0.25) * CFrame.Angles(0, 0, math.pi / 2),
		3.4,
		0.3,
		0.3,
		12,
		A.Accent,
		NEON
	)
	local rows = {}
	for _, name in Debloat.NAMES do
		table.insert(rows, { name, "En fond · 340 Mo", "FCE100" })
	end
	wallBoard(room, "DebloatBoard", 6, Vector2.new(14, 10), {
		Page = "Optimisations · Debloat",
		Title = "Programmes inutiles : 5",
		Rows = rows,
		Pixels = 56,
	})
end

------------------------------------------------------------------------------------
-- Monde 4 · La surchauffe : socles au-dessus de la lave, trois ventilateurs, plan d'alimentation
------------------------------------------------------------------------------------

local function coolingFan(room: Room, index: number, top: Vector3, look: Vector3)
	local folder = Build.Folder(`Fan{index}`, room.Folder)
	folder:SetAttribute("Fan", index)
	local cf = facing(top, look) * CFrame.new(0, 2.6, 0.6)
	decor(folder, "FanHousing", Vector3.new(4.4, 4.4, 1), cf, C.Black, METAL)
	local hub = Props.Rod(
		folder,
		"FanHub",
		cf * CFrame.new(0, 0, -0.55) * CFrame.Angles(0, math.pi / 2, 0),
		0.4,
		1.2,
		C.MetalLight,
		METAL
	)
	hub:SetAttribute("Fan", index)
	for k = 0, 4 do
		decor(
			folder,
			"Blade",
			Vector3.new(0.7, 1.7, 0.15),
			cf
				* CFrame.new(0, 0, -0.6)
				* CFrame.Angles(0, 0, k * math.pi * 2 / 5)
				* CFrame.new(0, 1.05, 0)
				* CFrame.Angles(0, math.rad(20), 0),
			Color3.fromRGB(60, 64, 76),
			SMOOTH
		)
	end
	for k = 1, 3 do
		local dust = decor(
			folder,
			"FanDust",
			Vector3.new(1.4, 0.8, 0.4),
			cf * CFrame.new((k - 2) * 1.1, ((k % 2) - 0.5) * 1.6, -0.8),
			Color3.fromRGB(150, 140, 120),
			Enum.Material.Sand
		)
		dust.Transparency = 0.05
	end
	neon(folder, "FanLed", Vector3.new(0.4, 0.4, 0.15), cf * CFrame.new(1.8, 1.8, -0.55), Color3.fromHex("FF5A5F"))
	decor(
		folder,
		"FanStand",
		Vector3.new(1.2, 0.6, 1.6),
		facing(top, look) * CFrame.new(0, 0.3, 0.6),
		C.MetalDark,
		METAL
	)
end

local function buildCooling(room: Room)
	local fr = room.Fr
	local basin = Cooling.BASIN
	room.Folder:SetAttribute("BasinMin", basin.Min)
	room.Folder:SetAttribute("BasinMax", basin.Max)
	-- Bord du bassin : liseré orange au ras du sol
	local cu = (basin.Min.X + basin.Max.X) / 2
	local cv = (basin.Min.Y + basin.Max.Y) / 2
	local w, d = basin.Max.X - basin.Min.X, basin.Max.Y - basin.Min.Y
	for _, edge in
		{
			{ cu, basin.Min.Y, w, 0.4 },
			{ cu, basin.Max.Y, w, 0.4 },
			{ basin.Min.X, cv, 0.4, d },
			{ basin.Max.X, cv, 0.4, d },
		}
	do
		neon(
			room.Folder,
			"BasinEdge",
			Vector3.new(edge[3], 0.12, edge[4]),
			CFrame.fromMatrix(at(room, edge[1], 0.07, edge[2]), fr.F, UP),
			AMBER
		).Transparency =
			0.3
	end
	marker(room.Folder, "LavaAnchor", at(room, cu, 0, cv), { SizeU = w, SizeV = d })
	for i, ped in Cooling.PEDESTALS do
		local cf = CFrame.fromMatrix(at(room, ped.U, ped.Top / 2, ped.V), fr.F, UP)
		local part = solid(
			room.Folder,
			"Pedestal",
			Vector3.new(Cooling.PEDESTAL_SIZE, ped.Top, Cooling.PEDESTAL_SIZE),
			cf,
			C.MetalDark,
			METAL
		)
		part:SetAttribute("Index", i)
		neon(
			room.Folder,
			"PedestalRim",
			Vector3.new(Cooling.PEDESTAL_SIZE + 0.1, 0.12, Cooling.PEDESTAL_SIZE + 0.1),
			cf * CFrame.new(0, ped.Top / 2 - 0.05, 0),
			C.Cyan
		).Transparency =
			0.45
		local top = at(room, ped.U, ped.Top, ped.V)
		if ped.Fan then
			-- Le ventilateur regarde vers le centre de la salle
			local toCenter = at(room, 8, 0, -12) - top
			coolingFan(room, ped.Fan, top, Vector3.new(toCenter.X, 0, toCenter.Z))
		elseif ped.Plan then
			local look = at(room, 4, 0, -12) - top
			local lectern = facing(top, Vector3.new(look.X, 0, look.Z))
			decor(room.Folder, "PlanPost", Vector3.new(1, 3, 1), lectern * CFrame.new(0, 1.5, 0.8), C.MetalDark, METAL)
			local panel = AppBoard.Panel(
				room.Folder,
				"PlanSwitch",
				Vector2.new(4.6, 3.2),
				lectern * CFrame.new(0, 3.6, 0.4) * CFrame.Angles(math.rad(-25), 0, 0),
				{
					Page = "Alimentation",
					Title = "Plan d'alimentation",
					Rows = { { "Performances max", "●", "FF99A4" }, { "Équilibré", "○", "8F8F8F" } },
					Pixels = 70,
					Scale = 0.7,
				}
			)
			panel:SetAttribute("Plan", true)
		end
	end
	wallBoard(room, "HeatBoard", 4, Vector2.new(9, 10.5), {
		Page = "Tableau de bord · Températures",
		Title = "Processeur",
		Big = { Value = "97 °C", Caption = "Alerte : ça chauffe (95 °C = rouge)", Color = A.Bad },
		Rows = {
			{ "Ventilateur 1", "bouché", "FF99A4" },
			{ "Ventilateur 2", "bouché", "FF99A4" },
			{ "Ventilateur 3", "bouché", "FF99A4" },
			{ "Plan", "Performances max", "FCE100" },
		},
		Pixels = 56,
	})
end

------------------------------------------------------------------------------------
-- Monde 5 · Défense du CPU : bus de données, emplacements d'optimisations, processeur
------------------------------------------------------------------------------------

local function buildCpuDefense(room: Room)
	local fr = room.Fr
	local layout = CpuDefense.ROOM_LAYOUT
	local cpu = at(room, CpuDefense.CPU.X, 0, CpuDefense.CPU.Y)
	local socketCf = CFrame.fromMatrix(cpu, fr.F, UP)
	ModelLibrary.Place(
		"CpuSocket",
		socketCf,
		room.Folder,
		{ Fit = Vector3.new(9, 0.9, 9), Name = "CpuSocket" },
		function(): Instance?
			local model = Build.Model("CpuSocket", room.Folder)
			decor(model, "Body", Vector3.new(9, 0.6, 9), socketCf * CFrame.new(0, 0.3, 0), C.Black, SMOOTH)
			decor(model, "Pins", Vector3.new(7, 0.15, 7), socketCf * CFrame.new(0, 0.65, 0), C.Gold, Enum.Material.Foil)
			return model
		end
	)
	local chipCf = socketCf * CFrame.new(0, 0.75, 0)
	ModelLibrary.Place(
		"CpuChip",
		chipCf,
		room.Folder,
		{ Fit = Vector3.new(6.2, 0.7, 6.2), Name = "CpuChip" },
		function(): Instance?
			local model = Build.Model("CpuChip", room.Folder)
			decor(model, "Lid", Vector3.new(6, 0.6, 6), chipCf * CFrame.new(0, 0.3, 0), C.Nickel, METAL)
			return model
		end
	)
	neon(room.Folder, "CpuGlow", Vector3.new(9.6, 0.1, 9.6), socketCf * CFrame.new(0, 0.05, 0), C.Cyan).Transparency =
		0.5
	marker(room.Folder, "Cpu", cpu + UP * 2)
	AppBoard.Panel(
		room.Folder,
		"CpuBoard",
		Vector2.new(9, 5.4),
		facing(at(room, CpuDefense.CPU.X, 8, CpuDefense.CPU.Y - 4), fr.R),
		{
			Page = "Optimisations",
			Title = "Processeur 100 %",
			Rows = {
				{ "Santé", `{CpuDefense.PARAMS.CpuHp} / {CpuDefense.PARAMS.CpuHp}`, "6CCB5F" },
				{ "Processus du virus", "en approche", "FF99A4" },
			},
			Pixels = 60,
			Scale = 0.85,
		}
	)
	-- Bus (lignes brisées) et ports d'entrée dans le mur intérieur
	for index, points in layout.Paths do
		for k = 2, #points do
			local a = at(room, points[k - 1].X, 0.08, points[k - 1].Y)
			local b = at(room, points[k].X, 0.08, points[k].Y)
			local mid = (a + b) / 2
			local dir = (b - a).Unit
			neon(
				room.Folder,
				"Bus",
				Vector3.new(1.4, 0.1, (b - a).Magnitude + 1.4),
				CFrame.fromMatrix(mid, dir:Cross(UP), UP, -dir),
				Color3.fromHex("FF5A5F")
			).Transparency =
				0.55
		end
		local port = at(room, points[1].X, 1.6, 6.6)
		decor(room.Folder, "BusPort", Vector3.new(3.2, 3.2, 0.5), facing(port, -fr.R), C.Black, SMOOTH)
		Props.Ring(
			room.Folder,
			"BusPortRing",
			facing(port, -fr.R) * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.pi / 2, 0),
			1.6,
			0.25,
			0.25,
			10,
			Color3.fromHex("FF5A5F"),
			NEON
		)
		marker(room.Folder, `BusStart{index}`, port)
	end
	room.Folder:SetAttribute("Paths", #layout.Paths)
	for slot, spot in layout.Slots do
		local base = at(room, spot.X, 0, spot.Y)
		local pad = Props.Rod(
			room.Folder,
			`TurretSlot{slot}`,
			CFrame.new(base + UP * 0.15) * CFrame.Angles(0, 0, math.pi / 2),
			0.3,
			3.4,
			A.Surface,
			SMOOTH
		)
		pad:SetAttribute("Slot", slot)
		Props.Ring(
			room.Folder,
			"TurretSlotRing",
			CFrame.new(base + UP * 0.32) * CFrame.Angles(0, 0, math.pi / 2),
			1.8,
			0.2,
			0.2,
			10,
			A.Accent,
			NEON
		)
	end
	wallBoard(room, "DefenseBoard", 4, Vector2.new(9, 8), {
		Page = "Optimisations · Défense",
		Title = "Optimisations",
		Rows = {
			{ "Énergie", `⚡ {CpuDefense.PARAMS.StartEnergy}` },
			{ "Une optimisation", `⚡ {CpuDefense.PARAMS.Cost}` },
			{ "Processus arrêtés", `0 / {CpuDefense.PARAMS.Target}` },
		},
		Pixels = 56,
	})
end

------------------------------------------------------------------------------------
-- Monde 6 · La carte graphique corrompue : ancien pilote, téléchargement, câbles, écrans
------------------------------------------------------------------------------------

Epreuves.OLD_FILES = { Vector2.new(3, -14), Vector2.new(12, -22), Vector2.new(15, -6), Vector2.new(6, -32) }
Epreuves.DOWNLOAD_AT = Vector2.new(10, -12)
Epreuves.REELS = { Vector2.new(-3, -22), Vector2.new(0, -27.5), Vector2.new(3, -22) }
Epreuves.CABLE_COLORS = { "4FD1C5", "9B2FD4", "F6C453" }
Epreuves.SCREENS_V = { -14, -21, -28 }
Epreuves.GPU_AT = Vector2.new(23, -12)

local function buildDriver(room: Room)
	local fr = room.Fr
	-- La carte graphique, posée à plat sur le banc de test (grandes faces vers le haut)
	local gpu = at(room, Epreuves.GPU_AT.X, 0, Epreuves.GPU_AT.Y)
	local gpuCf = alongR(room, gpu)
	ModelLibrary.Place(
		"GpuCard",
		gpuCf,
		room.Folder,
		{ Fit = Vector3.new(24, 4.4, 10.6), Name = "GpuCard" },
		function(): Instance?
			local model = Build.Model("GpuCard", room.Folder)
			decor(
				model,
				"Shroud",
				Vector3.new(24, 3.4, 10),
				gpuCf * CFrame.new(0, 1.7, 0),
				Color3.fromRGB(30, 32, 40),
				SMOOTH
			)
			for k = -1, 1 do
				Props.Ring(
					model,
					"FanRing",
					gpuCf * CFrame.new(k * 7.6, 3.45, 0) * CFrame.Angles(0, 0, math.pi / 2),
					3.3,
					0.35,
					0.3,
					14,
					C.MetalLight,
					METAL
				)
			end
			return model
		end
	)
	-- Ports colorés sur le flanc de la carte, côté salle
	for i, hex in Epreuves.CABLE_COLORS do
		local port = at(room, Epreuves.GPU_AT.X - 5.6, 2.2, Epreuves.GPU_AT.Y - 5 + (i - 1) * 5)
		local cf = facing(port, -fr.F)
		decor(room.Folder, "PortBody", Vector3.new(1.8, 1.2, 0.4), cf, C.Black, SMOOTH)
		local ring =
			neon(room.Folder, `Port{i}`, Vector3.new(1.2, 0.6, 0.1), cf * CFrame.new(0, 0, -0.22), Color3.fromHex(hex))
		ring:SetAttribute("Port", i)
	end
	-- Fichiers de l'ancien pilote (cubes qui glitchent)
	for i, spot in Epreuves.OLD_FILES do
		local cube = decor(
			room.Folder,
			`OldFile{i}`,
			Vector3.new(2.4, 2.4, 2.4),
			CFrame.new(at(room, spot.X, 1.6, spot.Y)) * CFrame.Angles(0.3, i, 0.2),
			Color3.fromHex("FF00C8"),
			NEON
		)
		cube.Transparency = 0.2
		cube:SetAttribute("File", i)
	end
	-- Zone de téléchargement : disque au sol et colonne de lumière
	local dl = at(room, Epreuves.DOWNLOAD_AT.X, 0, Epreuves.DOWNLOAD_AT.Y)
	Props.Rod(
		room.Folder,
		"DownloadPad",
		CFrame.new(dl + UP * 0.12) * CFrame.Angles(0, 0, math.pi / 2),
		0.24,
		6.4,
		A.Surface,
		SMOOTH
	)
	Props.Ring(
		room.Folder,
		"DownloadRing",
		CFrame.new(dl + UP * 0.28) * CFrame.Angles(0, 0, math.pi / 2),
		3.2,
		0.25,
		0.25,
		14,
		C.Cyan,
		NEON
	)
	local beam = Props.Rod(
		room.Folder,
		"DownloadBeam",
		CFrame.new(dl + UP * 7) * CFrame.Angles(0, 0, math.pi / 2),
		14,
		5.8,
		C.Cyan,
		NEON
	)
	beam.Transparency = 0.86
	marker(room.Folder, "DownloadZone", dl + UP * 2, { Radius = 3.2 })
	AppBoard.Panel(room.Folder, "DownloadBoard", Vector2.new(7, 3.4), facing(dl + UP * 9, fr.R - fr.F * 0.3), {
		Page = "Pilotes GPU",
		Title = "Téléchargement",
		Bar = { Label = "Pilote 2026.10 · 0 %", Value = 0, Color = A.Accent },
		Pixels = 60,
		Scale = 0.8,
	})
	-- Bobines de câbles (une couleur par port)
	for i, spot in Epreuves.REELS do
		local base = at(room, spot.X, 0, spot.Y)
		local reel = Props.Rod(
			room.Folder,
			`Reel{i}`,
			CFrame.new(base + UP * 1.4) * CFrame.Angles(0, 0, math.pi / 2),
			2.8,
			2.6,
			Color3.fromHex(Epreuves.CABLE_COLORS[i]),
			SMOOTH
		)
		reel:SetAttribute("Cable", i)
		Props.Rod(
			room.Folder,
			"ReelCap",
			CFrame.new(base + UP * 2.9) * CFrame.Angles(0, 0, math.pi / 2),
			0.25,
			3.2,
			C.MetalDark,
			METAL
		)
	end
	-- Trois écrans numérotés (page Écrans de l'app), le long du mur d'arrivée
	for i, v in Epreuves.SCREENS_V do
		local base = at(room, -5.4, 0, v)
		local cf = facing(base, fr.F)
		decor(room.Folder, "ScreenStand", Vector3.new(0.6, 3.2, 0.6), cf * CFrame.new(0, 1.6, 0.4), C.MetalDark, METAL)
		decor(room.Folder, "ScreenBezel", Vector3.new(6.2, 4, 0.4), cf * CFrame.new(0, 5, 0.25), C.Black, SMOOTH)
		local hz = Driver.SCREENS[i]
		local panel = AppBoard.Panel(room.Folder, `Monitor{i}`, Vector2.new(5.8, 3.6), cf * CFrame.new(0, 5, 0), {
			Page = "Écrans",
			Title = `Écran {i}`,
			Rows = {
				{ "Résolution", "2560 × 1440" },
				{ "Fréquence", `{hz} Hz`, if hz < Driver.MAX_HZ then "FF99A4" else "6CCB5F" },
			},
			Pixels = 70,
			Scale = 0.72,
		})
		panel:SetAttribute("Screen", i)
	end
	wallBoard(room, "DriverBoard", 6, Vector2.new(12, 9), {
		Page = "Pilotes GPU",
		Title = "Pilote graphique : corrompu",
		Rows = {
			{ "Ancien pilote", `{#Driver.FILES} fichiers`, "FF99A4" },
			{ "Téléchargement", "0 %" },
			{ "Câbles", `0 / {Driver.CABLES}` },
			{ "Écran 2", "60 Hz", "FF99A4" },
		},
		Pixels = 56,
	})
end

------------------------------------------------------------------------------------
-- Monde 7 · L'enquête des Sessions de jeu : capsules de programmes et chaîne « Lancé par »
------------------------------------------------------------------------------------

Epreuves.PODS = {
	browser = Vector2.new(4, -14),
	updater = Vector2.new(13, -2),
	helper = Vector2.new(25, -22),
	lagz = Vector2.new(11, -23.5),
	music = Vector2.new(24, 1),
	explorer = Vector2.new(-3, -32),
}

local function buildInvestigation(room: Room)
	for _, pod in Investigation.PODS do
		local spot = Epreuves.PODS[pod.Id]
		local base = at(room, spot.X, 0, spot.Y)
		local folder = Build.Folder(`Pod_{pod.Id}`, room.Folder)
		folder:SetAttribute("Pod", pod.Id)
		Props.Rod(
			folder,
			"PodBase",
			CFrame.new(base + UP * 0.3) * CFrame.Angles(0, 0, math.pi / 2),
			0.6,
			4.6,
			C.MetalDark,
			METAL
		)
		local glass = Build.Part({
			Name = "PodGlass",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6, 4, 4),
			CFrame = CFrame.new(base + UP * 3.6) * CFrame.Angles(0, 0, math.pi / 2),
			Color = if pod.Hidden then C.Black else Color3.fromRGB(170, 190, 220),
			Material = GLASS,
			Transparency = if pod.Hidden then 0.15 else 0.55,
			Parent = folder,
		})
		glass:SetAttribute("Pod", pod.Id)
		local core = neon(
			folder,
			"PodCore",
			Vector3.new(1.6, 1.6, 1.6),
			CFrame.new(base + UP * 3.6) * CFrame.Angles(0.6, 0.6, 0),
			if pod.Suspect then AMBER elseif pod.Hidden then C.Black else C.Cyan
		)
		core.Transparency = if pod.Hidden then 0.6 else 0.1
		local toward = at(room, 8, 0, -14) - base
		local label = AppBoard.Panel(
			folder,
			"PodLabel",
			Vector2.new(5.4, 3),
			facing(base + UP * 8.2, Vector3.new(toward.X, 0, toward.Z)),
			{
				Page = "Sessions de jeu",
				Title = if pod.Hidden then "processus masqué" else pod.Name,
				Rows = { { "Activité", if pod.Hidden then "???" else pod.Cpu }, { "Lancé par", "?", "8F8F8F" } },
				Pixels = 70,
				Scale = 0.7,
			}
		)
		label:SetAttribute("Pod", pod.Id)
	end
	-- Câbles « Lancé par » (éteints) : du programme vers celui qui l'a lancé
	for _, pod in Investigation.PODS do
		if pod.Parent then
			local a = Epreuves.PODS[pod.Id]
			local b = Epreuves.PODS[pod.Parent]
			local pa, pb = at(room, a.X, 0.1, a.Y), at(room, b.X, 0.1, b.Y)
			local dir = (pb - pa).Unit
			local link = neon(
				room.Folder,
				`Link_{pod.Id}`,
				Vector3.new(0.5, 0.1, (pb - pa).Magnitude - 4),
				CFrame.fromMatrix((pa + pb) / 2, dir:Cross(UP), UP, -dir),
				C.MetalLight
			)
			link.Transparency = 0.7
		end
	end
	wallBoard(room, "SessionBoard", 6, Vector2.new(12, 8.5), {
		Page = "Sessions de jeu",
		Title = "Partie du jour",
		Rows = {
			{ "Verdict", "🟡 Quelques accrocs", "FCE100" },
			{ "Pic de lag", "14:03 · 1 % low à 9 FPS" },
			{ "D'où viennent les accrocs", "navigateur.exe ?", "FF99A4" },
			{ "Quoi faire", "remonte « Lancé par »" },
		},
		Pixels = 56,
	})
end

------------------------------------------------------------------------------------

local BUILDERS: { [string]: (Room) -> () } = {
	Startup = buildStartup,
	RamSlots = buildRamSlots,
	Debloat = buildDebloat,
	Cooling = buildCooling,
	CpuDefense = buildCpuDefense,
	Driver = buildDriver,
	Investigation = buildInvestigation,
}

-- L'écran du fond devient la fiche de l'épreuve ; la borne propose de la lancer.
local function dressTerminal(room: Room)
	local house = room.House
	local screen = house:FindFirstChild("Screen")
	if screen and screen:IsA("BasePart") then
		local old = screen:FindFirstChild("Sign")
		if old then
			old:Destroy()
		end
		AppBoard.Build(screen, {
			Page = room.Def.Page,
			Title = `{room.Def.Step} · {room.Def.Name}`,
			Fiche = room.Def.Fiche,
			Pixels = 64,
		})
	end
	local console = house:FindFirstChild("MinigameTerminal")
	local prompt = if console then console:FindFirstChildOfClass("ProximityPrompt") else nil
	if prompt then
		prompt.ActionText = room.Def.Start
		prompt.ObjectText = "Borne AngAInOne"
	end
end

function Epreuves.Build(ctx: Common.WorldContext)
	local def = EpreuveConfig.ByWorld[ctx.Index]
	local terminal = ctx.Model:FindFirstChild("Terminal")
	local house = if terminal then terminal:FindFirstChild("TerminalRoom") else nil
	local builder = if def then BUILDERS[def.Kind] else nil
	if not def or not terminal or not house or not builder then
		return
	end
	local folder = Build.Folder("Epreuve", terminal)
	local fr, y = ctx.Terminal.Frame, ctx.Terminal.Floor
	folder:SetAttribute("World", ctx.Index)
	folder:SetAttribute("Kind", def.Kind)
	folder:SetAttribute("Stage", Tower.TerminalStage(ctx.Index))
	folder:SetAttribute("Origin", P(fr, 0, y, 0))
	folder:SetAttribute("AxisF", fr.F)
	folder:SetAttribute("AxisR", fr.R)
	local room: Room = { Ctx = ctx, Fr = fr, Y = y, House = house, Folder = folder, Def = def }
	dressTerminal(room)
	builder(room)
	-- Lumière de l'épreuve, au-dessus de la zone de jeu (la salle n'avait qu'une lampe)
	Common.Lamp(folder, at(room, 17, 16, -12), ctx.Style.Primary:Lerp(C.White, 0.6), 1.3, 46)
end

return Epreuves
