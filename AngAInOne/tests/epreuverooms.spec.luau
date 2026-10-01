-- Décor des épreuves 3D dans les salles du terminal (World/Tower/Epreuves) : tour construite à part
-- (décor de secours), puis chaque salle est contrôlée : repères attendus par le client, fiche sur
-- l'écran, borne et portail dégagés, socles de lave accessibles en sautant, tout reste dans la salle.
local roblox = require("@lune/roblox")

local V3 = roblox.Vector3

local built = IsolatedTower.Build({ Models = false })
local tower = built.Tower
local Tower = built.Load("src/shared/Config/Tower.luau")
local EpreuveConfig = built.Load("src/shared/Config/Epreuves.luau")
local Cooling = built.Load("src/shared/EpreuveLogic/Cooling.luau")
local CpuDefense = built.Load("src/shared/EpreuveLogic/CpuDefense.luau")
local Startup = built.Load("src/shared/EpreuveLogic/Startup.luau")
local Investigation = built.Load("src/shared/EpreuveLogic/Investigation.luau")

local JUMP_HEIGHT = 7.2
local JUMP_GAP = 6.5 -- écart horizontal franchissable entre deux bords (marche 16, saut 7,2)

type Room = { Folder: any, Terminal: any, Origin: any, F: any, R: any }

local function room(w: number): Room
	local terminal = tower:FindFirstChild(`World{w}`):FindFirstChild("Terminal")
	local folder = terminal:FindFirstChild("Epreuve")
	return {
		Folder = folder,
		Terminal = terminal,
		Origin = folder:GetAttribute("Origin"),
		F = folder:GetAttribute("AxisF"),
		R = folder:GetAttribute("AxisR"),
	}
end

local function uvh(r: Room, p: any): (number, number, number)
	local d = p - r.Origin
	return d:Dot(r.F), d:Dot(r.R), d.Y
end

local REQUIRED: { [string]: { string } } = {
	Startup = {
		"StartupWall",
		"Door1",
		"Door2",
		"Door3",
		"Door4",
		"Door5",
		"Door6",
		"LeverPost",
		"LeverPlate",
		"LeverKnob",
	},
	RamSlots = { "Slot1", "Slot2", "Slot3", "Slot4", "Stick1", "Stick2", "FlushCap", "RamBoard" },
	Debloat = { "MonsterSpawn1", "MonsterSpawn5", "PresetPad", "DebloatBoard" },
	Cooling = {
		"Fan1",
		"Fan2",
		"Fan3",
		"FanHousing",
		"FanHub",
		"Blade",
		"PlanSwitch",
		"LavaAnchor",
		"HeatBoard",
		"Pedestal",
	},
	CpuDefense = { "Cpu", "CpuBoard", "DefenseBoard", "BusStart1", "BusStart3", "TurretSlot1", "TurretSlot6" },
	Driver = {
		"OldFile1",
		"OldFile4",
		"DownloadZone",
		"DownloadBoard",
		"Reel1",
		"Reel3",
		"Port1",
		"Port3",
		"Monitor1",
		"Monitor3",
		"DriverBoard",
	},
	Investigation = { "SessionBoard", "PodGlass", "PodLabel", "Link_browser", "Link_updater", "Link_helper" },
}

return {
	["chaque salle a son épreuve, sa fiche sur l'écran et une borne « Lancer »"] = function()
		for w = 1, Tower.WORLD_COUNT do
			local def = EpreuveConfig.ByWorld[w]
			local r = room(w)
			Expect.truthy(r.Folder, `épreuve du monde {w}`)
			Expect.equal(r.Folder:GetAttribute("Kind"), def.Kind)
			Expect.equal(r.Folder:GetAttribute("Stage"), Tower.TerminalStage(w))
			Expect.truthy(
				typeof(r.Origin) == "Vector3" and typeof(r.F) == "Vector3" and typeof(r.R) == "Vector3",
				"repère"
			)
			Expect.near(r.F:Dot(r.R), 0, 1e-4, "repère orthogonal")
			local house = r.Terminal:FindFirstChild("TerminalRoom")
			local screen = house:FindFirstChild("Screen")
			Expect.truthy(screen:FindFirstChild("AppBoard"), "fiche de l'épreuve sur l'écran")
			Expect.equal(screen:FindFirstChild("Sign"), nil, "ancien panneau retiré")
			local prompt = house:FindFirstChild("MinigameTerminal"):FindFirstChildOfClass("ProximityPrompt")
			Expect.equal(prompt.ActionText, def.Start)
			Expect.equal(prompt:GetAttribute("Action"), "Minigame", "même borne, même validation serveur")
			for _, name in REQUIRED[def.Kind] do
				Expect.truthy(r.Folder:FindFirstChild(name, true), `{def.Kind} : repère {name}`)
			end
		end
		-- La Corbeille de l'épreuve du monde 3 est celle des easter eggs
		Expect.truthy(room(3).Terminal:FindFirstChild("Corbeille", true), "Corbeille du monde 3")
	end,

	["tout reste dans la salle ; borne, portail et entrée dégagés"] = function()
		for w = 1, Tower.WORLD_COUNT do
			local r = room(w)
			for _, part in r.Folder:GetDescendants() do
				if part:IsA("BasePart") then
					local u, v, h = uvh(r, part.CFrame.Position)
					Expect.truthy(
						u > -7.5 and u < 29.5 and v > -44 and v < 7.5 and h > -1 and h < 27,
						`{part:GetFullName()} hors de la salle ({u}, {v}, {h})`
					)
					if part.CanCollide then
						-- Demi-étendues de la pièce le long de F (u) et de R (v)
						local cf, size = part.CFrame, part.Size
						local function extent(axis: any): number
							return (
								math.abs(cf.RightVector:Dot(axis)) * size.X
								+ math.abs(cf.UpVector:Dot(axis)) * size.Y
								+ math.abs(cf.LookVector:Dot(axis)) * size.Z
							) / 2
						end
						local hu, hv = extent(r.F), extent(r.R)
						-- Devant la borne (u 6..18, v -34..-28), allée du portail (u 21..29, v -44..-29),
						-- porte d'arrivée (u -7..-1, v -6..6)
						local function clear(u0: number, u1: number, v0: number, v1: number): boolean
							return u + hu < u0 or u - hu > u1 or v + hv < v0 or v - hv > v1
						end
						Expect.truthy(clear(6, 18, -34, -28), `{part:GetFullName()} devant la borne`)
						Expect.truthy(clear(21, 29, -44, -29), `{part:GetFullName()} dans l'allée du portail`)
						Expect.truthy(clear(-7, -1, -6, 6), `{part:GetFullName()} devant la porte d'arrivée`)
					end
				end
			end
		end
	end,

	["démarrage : six portes face au couloir, un levier par porte, intrus marqués"] = function()
		local r = room(1)
		local levers = 0
		for i, door in Startup.DOORS do
			local folder = r.Folder:FindFirstChild(`Door{i}`)
			Expect.equal(folder:GetAttribute("DoorId"), door.Id)
			local leaf = folder:FindFirstChild("DoorLeaf")
			Expect.truthy(leaf:FindFirstChild("AppBoard"), "fiche du programme sur la porte")
			-- La face avant de la porte regarde l'axe du couloir (u = 18)
			local u = uvh(r, leaf.CFrame.Position)
			local look = leaf.CFrame.LookVector:Dot(r.F)
			Expect.truthy((u < 18 and look > 0.9) or (u > 18 and look < -0.9), `porte {i} tournée vers le couloir`)
			Expect.equal(folder:FindFirstChild("DoorLeak") ~= nil, door.Culprit == true, `porte {i} : lueur des intrus`)
			if folder:FindFirstChild("LeverPost") then
				levers += 1
			end
		end
		Expect.equal(levers, #Startup.DOORS)
	end,

	["surchauffe : socles hors du pad et de la borne, tous accessibles en sautant depuis le sol"] = function()
		local r = room(4)
		local pedestals = {}
		for _, part in r.Folder:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Pedestal" then
				Expect.truthy(part.CanCollide, "socle solide")
				local u, v, h = uvh(r, part.CFrame.Position)
				table.insert(pedestals, { U = u, V = v, Top = h + part.Size.Y / 2, Half = part.Size.X / 2 })
			end
		end
		Expect.equal(#pedestals, #Cooling.PEDESTALS)
		local basin = Cooling.BASIN
		Expect.equal(Cooling.InLava(0, 0), false, "le pad n'est pas dans la lave")
		Expect.equal(Cooling.InLava(12, -36), false, "la borne non plus")
		-- Graphe de sauts : départ = sol hors du bassin (u < basin.Min.X), hauteur 0
		local reached = {}
		local queue = {}
		for i, ped in pedestals do
			local gap = (ped.U - ped.Half) - basin.Min.X
			if gap <= JUMP_GAP and ped.Top <= JUMP_HEIGHT - 1 then
				reached[i] = true
				table.insert(queue, i)
			end
		end
		while #queue > 0 do
			local a = pedestals[table.remove(queue, 1)]
			for j, b in pedestals do
				if not reached[j] then
					local dx = math.max(0, math.abs(a.U - b.U) - a.Half - b.Half)
					local dz = math.max(0, math.abs(a.V - b.V) - a.Half - b.Half)
					if math.sqrt(dx * dx + dz * dz) <= JUMP_GAP and b.Top - a.Top <= JUMP_HEIGHT - 1.5 then
						reached[j] = true
						table.insert(queue, j)
					end
				end
			end
		end
		for i, ped in pedestals do
			Expect.truthy(reached[i], `socle {i} ({ped.U}, {ped.V}) inaccessible`)
			Expect.truthy(ped.Top > Cooling.LAVA_MAX + 0.5, "au-dessus de la lave")
		end
		-- Le socle du pupitre est à un saut du sol sûr côté borne (v < bassin)
		local plan = Cooling.PEDESTALS[8]
		Expect.truthy(plan.Plan, "pupitre sur le dernier socle")
		Expect.truthy((plan.V - Cooling.PEDESTAL_SIZE / 2) - basin.Min.Y <= JUMP_GAP, "retour au sol sûr")
	end,

	["défense du CPU : bus, emplacements et processeur posés au plan partagé avec le client"] = function()
		local r = room(5)
		local cpu = r.Folder:FindFirstChild("Cpu")
		local u, v = uvh(r, cpu.CFrame.Position)
		Expect.near(u, CpuDefense.CPU.X, 0.01)
		Expect.near(v, CpuDefense.CPU.Y, 0.01)
		for slot, spot in CpuDefense.ROOM_LAYOUT.Slots do
			local pad = r.Folder:FindFirstChild(`TurretSlot{slot}`)
			local pu, pv = uvh(r, pad.CFrame.Position)
			Expect.near(pu, spot.X, 0.01)
			Expect.near(pv, spot.Y, 0.01)
			Expect.equal(pad.CanCollide, false, "emplacement plat, sans collision")
		end
		for index, points in CpuDefense.ROOM_LAYOUT.Paths do
			local start = r.Folder:FindFirstChild(`BusStart{index}`)
			local su = uvh(r, start.CFrame.Position)
			Expect.near(su, points[1].X, 0.01, "port d'entrée au bout du bus")
			local last = points[#points]
			Expect.truthy((last - CpuDefense.CPU).Magnitude < 5, "le bus finit au processeur")
		end
	end,

	["enquête : une capsule par programme, câbles « Lancé par » vers le parent"] = function()
		local r = room(7)
		for _, pod in Investigation.PODS do
			local folder = r.Folder:FindFirstChild(`Pod_{pod.Id}`)
			Expect.truthy(folder, `capsule {pod.Id}`)
			Expect.truthy(folder:FindFirstChild("PodLabel"):FindFirstChild("AppBoard"), "étiquette")
			Expect.equal(r.Folder:FindFirstChild(`Link_{pod.Id}`) ~= nil, pod.Parent ~= nil, `câble de {pod.Id}`)
		end
		-- L'escargot « Wi-Fi de l'hôtel » (easter egg) garde sa place : pas de capsule sur son trajet
		local snail = r.Terminal:FindFirstChild("Snail", true)
		if snail then
			for _, pod in Investigation.PODS do
				local glass = r.Folder:FindFirstChild(`Pod_{pod.Id}`):FindFirstChild("PodGlass")
				local d = (glass.CFrame.Position - snail.CFrame.Position) * V3.new(1, 0, 1)
				Expect.truthy(d.Magnitude > 4, `capsule {pod.Id} sur le chemin de l'escargot`)
			end
		end
	end,
}
