--!strict
--[[
	CpuDefense : épreuve du monde 5, « Défense du CPU » (Shared/EpreuveLogic/CpuDefense).
	Des processus du virus sortent des ports du mur et suivent les bus jusqu'au processeur. Sur les
	emplacements violets, on installe des optimisations (⚡ énergie) : chacune tire sur le processus
	le plus avancé à portée. Un processus qui touche le processeur lui retire un point de santé.
	Lisibilité : cercle de portée sur chaque emplacement (vif une fois l'optimisation posée), tête de
	tourelle qui vise sa cible, impact visible, processus lourds plus gros, trois vagues annoncées.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CpuDefense = require(ReplicatedStorage:WaitForChild("Shared").EpreuveLogic.CpuDefense)
local Fx = require(script.Parent.Parent.EpreuveFx)

local VIRUS = Color3.fromHex("FF5A5F")
local TOUGH = Color3.fromHex("8B7CFF")

type View = { Model: Model, Body: BasePart }

local function virusModel(parent: Instance, tough: boolean): View
	local model = Instance.new("Model")
	model.Name = "Processus"
	local template = ReplicatedStorage:FindFirstChild("ClientModels")
	local bug = if template then template:FindFirstChild("VirusBug") else nil
	local body: BasePart
	if bug and bug:IsA("Model") then
		local copy = bug:Clone()
		copy:ScaleTo(if tough then 0.8 else 0.55)
		for _, part in Fx.Parts(copy) do
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
		copy.Parent = model
		-- Pivot du gabarit (aligné sur son avant par ModelLibrary) : pas de PrimaryPart, dont
		-- l'orientation interne retournerait le processus.
		model.WorldPivot = copy:GetPivot()
		body = copy:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	else
		body = Fx.Part({
			Name = "Body",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (if tough then 2.6 else 2),
			Color = if tough then TOUGH else VIRUS,
			Material = Enum.Material.Neon,
		}, model)
		for k = 0, 5 do
			local angle = k * math.pi / 3
			Fx.Part({
				Name = "Spike",
				Size = Vector3.new(0.5, 0.5, 0.9),
				CFrame = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -body.Size.X / 2),
				Color = Color3.fromRGB(40, 10, 30),
			}, model)
		end
		for _, side in { -1, 1 } do
			Fx.Part({
				Name = "Eye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.5,
				CFrame = CFrame.new(side * 0.4, 0.3, -body.Size.X / 2 + 0.1),
				Color = Color3.new(1, 1, 1),
				Material = Enum.Material.Neon,
			}, model)
		end
	end
	if not (bug and bug:IsA("Model")) then
		model.PrimaryPart = body -- secours en primitives : le corps est déjà orienté vers -Z
	end
	model.Parent = parent
	return { Model = model, Body = body }
end

-- Disque de portée (Params.Range) posé au sol autour d'un emplacement.
local function rangeRing(parent: Instance, position: Vector3, range: number): BasePart
	return Fx.Part({
		Name = "Range",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, range * 2, range * 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Fx.ACCENT,
		Material = Enum.Material.Neon,
		Transparency = 0.94,
	}, parent)
end

type Turret = { Orb: BasePart, Head: BasePart, Base: Vector3 }

local function turret(parent: Instance, position: Vector3, name: string): Turret
	local model = Instance.new("Model")
	model.Name = "Optimisation"
	Fx.Part({
		Name = "TurretBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 3, 3),
		CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromHex("2B2B2B"),
		Material = Enum.Material.Metal,
	}, model)
	Fx.Part({
		Name = "TurretPost",
		Size = Vector3.new(0.7, 2.6, 0.7),
		CFrame = CFrame.new(position + Vector3.new(0, 1.9, 0)),
		Color = Color3.fromHex("3A3A3A"),
		Material = Enum.Material.Metal,
	}, model)
	local orb = Fx.Part({
		Name = "TurretOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.5,
		CFrame = CFrame.new(position + Vector3.new(0, 3.6, 0)),
		Color = Fx.ACCENT,
		Material = Enum.Material.Neon,
	}, model)
	local light = Instance.new("PointLight")
	light.Color = Fx.ACCENT
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = orb
	-- Tête orientable : un canon qui pointe vers le processus visé
	local head = Fx.Part({
		Name = "TurretBarrel",
		Size = Vector3.new(0.45, 0.45, 1.8),
		CFrame = CFrame.new(position + Vector3.new(0, 3.6, -0.9)),
		Color = Color3.fromHex("E8E8E8"),
		Material = Enum.Material.SmoothPlastic,
	}, model)
	model.PrimaryPart = orb
	model.Parent = parent
	Fx.Label(orb, name, Color3.fromHex("C5C5C5"), 1.6).Size = UDim2.fromOffset(220, 36)
	return { Orb = orb, Head = head, Base = position + Vector3.new(0, 3.6, 0) }
end

-- Vagues annoncées (cosmétique) : à quel processus apparu commence chaque vague.
local WAVES = {
	{ From = 1, Text = "Vague 1/3 : les premiers processus arrivent !" },
	{ From = 0.4, Text = "Vague 2/3 : des processus lourds (violets) se mêlent au flot." },
	{ From = 0.75, Text = "Vague 3/3 : dernière vague, ils accélèrent !" },
}

return function(run: any): () -> ()
	local layout = CpuDefense.ROOM_LAYOUT
	local sim = CpuDefense.new(layout, math.floor(os.clock() * 1000) % 100000 + 1)
	local p = sim.Params
	local board = run.Board(run.Find("DefenseBoard"))
	local cpuBoard = run.Board(run.Find("CpuBoard"))
	local cpuMarker = run.Find("Cpu")
	local views: { [number]: View } = {}
	local orbs: { [number]: Turret } = {}
	local rings: { [number]: BasePart } = {}
	local wave = 0
	local prompts: { [number]: ProximityPrompt } = {}
	local lastZap = 0

	local function world(point: Vector2, height: number): Vector3
		return run.At(point.X, height, point.Y)
	end

	local function refresh()
		local energy = math.floor(sim.Energy)
		board:Row(1, `⚡ {energy}`, if energy >= p.Cost then "6CCB5F" else "FCE100")
		board:Row(3, `{sim.Kills} / {p.Target}`)
		cpuBoard:Row(1, `{sim.CpuHp} / {p.CpuHp}`, if sim.CpuHp > 2 then "6CCB5F" else "FF99A4")
		cpuBoard:Title(`Processeur {math.max(12, 100 - math.floor(88 * sim.Kills / p.Target))} %`)
		run.Status(`⚡ {energy} · Processus arrêtés {sim.Kills}/{p.Target} · Processeur {sim.CpuHp}/{p.CpuHp}`)
		run.Bar(sim.Kills / p.Target, `Processus arrêtés : {sim.Kills} / {p.Target}`)
		for slot, prompt in prompts do
			if not sim.Turrets[slot] then
				prompt.ActionText = if energy >= p.Cost
					then `Installer · ⚡{p.Cost}`
					else `⚡{p.Cost} (énergie : {energy})`
			end
		end
	end

	local function handle(event: CpuDefense.Event)
		if event.Kind == "Spawn" and event.Id and event.Path then
			views[event.Id] = virusModel(run.Folder, event.Tough == true)
			run.Add(views[event.Id].Model)
			local nextWave = WAVES[wave + 1]
			if nextWave then
				local from = if nextWave.From >= 1 then 1 else math.ceil(p.Target * nextWave.From)
				if sim.Spawned >= from then
					wave += 1
					run.Say(nextWave.Text, 3)
					cpuBoard:Row(2, `Vague {wave} / {#WAVES}`, if wave == #WAVES then "FF99A4" else "FCE100")
				end
			end
		elseif event.Kind == "Shot" and event.Slot and event.Id then
			local unit = orbs[event.Slot]
			local view = views[event.Id]
			if unit and view then
				local target = view.Body.Position
				local flat = Vector3.new(target.X, unit.Base.Y, target.Z)
				if (flat - unit.Base).Magnitude > 0.05 then
					local aim = CFrame.lookAt(unit.Base, flat)
					unit.Head.CFrame = aim * CFrame.new(0, 0, -0.9)
				end
				Fx.Beam(unit.Head.Position, target, Fx.ACCENT, 0.1, 0.3)
				Fx.Burst(target, Fx.ACCENT, 3)
				if os.clock() - lastZap > 0.15 then
					lastZap = os.clock()
					run.Sound("Zap", 1.3)
				end
			end
		elseif event.Kind == "Kill" and event.Id then
			local view = views[event.Id]
			views[event.Id] = nil
			if view then
				Fx.Burst(view.Body.Position, VIRUS, 8)
				view.Model:Destroy()
			end
		elseif event.Kind == "Leak" and event.Id then
			local view = views[event.Id]
			views[event.Id] = nil
			if view then
				view.Model:Destroy()
			end
			run.Sound("Error")
			if cpuMarker and cpuMarker:IsA("BasePart") then
				Fx.Burst(cpuMarker.Position, VIRUS, 12)
			end
			run.Toast("Info", `Un processus a touché le processeur ({sim.CpuHp}/{p.CpuHp})`)
		elseif event.Kind == "Build" and event.Slot then
			local spot = layout.Slots[event.Slot]
			local unit = turret(run.Folder, world(spot, 0), CpuDefense.OPTIMISATIONS[event.Slot])
			orbs[event.Slot] = unit
			run.Add(unit.Orb.Parent)
			local ring = rings[event.Slot]
			if ring then
				Fx.Tween(ring, { Transparency = 0.82 }, 0.3)
			end
			local prompt = prompts[event.Slot]
			if prompt then
				prompt.Enabled = false
			end
			run.Sound("PowerOn", 1.3)
			run.Step(1, true, "Poser des optimisations")
		elseif event.Kind == "NoEnergy" then
			run.Toast("Info", "Pas assez d'énergie : elle se recharge toute seule, et à chaque processus arrêté.")
		elseif event.Kind == "Win" then
			run.Step(2, true, `Arrêter les processus du virus ({sim.Kills}/{p.Target})`)
			refresh()
			run.Win(CpuDefense.Score(sim))
		elseif event.Kind == "Lose" or event.Kind == "Timeout" then
			run.Fail("Le processeur a saturé")
		end
	end

	for slot, spot in layout.Slots do
		rings[slot] = rangeRing(run.Folder, world(spot, 0), p.Range)
		run.Add(rings[slot])
		local pad = run.Find(`TurretSlot{slot}`)
		if pad then
			prompts[slot] = run.Prompt(pad, `Installer · ⚡{p.Cost}`, CpuDefense.OPTIMISATIONS[slot], 0, 9, function()
				for _, event in CpuDefense.Build(sim, slot) do
					handle(event)
				end
				refresh()
			end)
		end
	end

	run.Step(1, false, "Poser des optimisations")
	run.Step(2, false, `Arrêter les processus du virus (0/{p.Target})`)
	run.Say("Pose une optimisation près de chaque bus avant que les processus arrivent !", 4)
	refresh()

	local refreshTimer = 0
	run.Every(function(dt: number)
		for _, event in CpuDefense.Step(sim, dt) do
			handle(event)
			if not run.Running() then
				return
			end
		end
		for _, virus in sim.Viruses do
			local view = views[virus.Id]
			if view then
				local here = CpuDefense.Position(sim, virus)
				local ahead = CpuDefense.Position(
					sim,
					{ Id = 0, Path = virus.Path, Distance = virus.Distance + 0.5, Hp = 1, Tough = false }
				)
				local position = world(here, 1.4 + math.sin(os.clock() * 8 + virus.Id) * 0.15)
				local target = world(ahead, 1.4)
				local cf = if (target - position).Magnitude > 0.01
					then CFrame.lookAt(position, target)
					else CFrame.new(position)
				view.Model:PivotTo(cf)
			end
		end
		refreshTimer += dt
		if refreshTimer > 0.25 then
			refreshTimer = 0
			refresh()
			run.Step(2, false, `Arrêter les processus du virus ({sim.Kills}/{p.Target})`)
		end
	end)

	return function()
		cpuBoard:Row(1, `{p.CpuHp} / {p.CpuHp}`, "6CCB5F")
		cpuBoard:Title("Processeur 100 %")
		board:Row(1, `⚡ {p.StartEnergy}`)
		cpuBoard:Row(2, "en approche", "FF99A4")
		board:Row(3, `0 / {p.Target}`)
	end
end
