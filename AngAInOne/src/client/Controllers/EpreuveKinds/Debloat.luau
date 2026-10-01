--!strict
--[[
	Debloat : épreuve du monde 3, « L'invasion du Bloatware » (Shared/EpreuveLogic/Debloat).
	Des bloatware gros et lents (des boîtes de logiciel avec des yeux) se promènent dans la salle.
	Maintenir « Debloat » à côté : un rayon les aspire dans la Corbeille. Laissés tranquilles trop
	longtemps, ils s'installent encore (copie « (2) »). Le pad PRESET (une fois) aspire tout ce qui est
	à portée. Plus aucun bloatware : vider la Corbeille.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Debloat = require(ReplicatedStorage:WaitForChild("Shared").EpreuveLogic.Debloat)
local Fx = require(script.Parent.Parent.EpreuveFx)

local SPEED = 2.6 -- studs / s
local BODY_COLORS = {
	Color3.fromRGB(196, 178, 128),
	Color3.fromRGB(132, 168, 96),
	Color3.fromRGB(150, 150, 160),
	Color3.fromRGB(205, 150, 110),
	Color3.fromRGB(120, 140, 190),
}

type View = { Id: number, Model: Model, Body: Part, Target: Vector2, U: number, V: number, Prompt: ProximityPrompt? }

return function(run: any): () -> ()
	local sim = Debloat.new()
	local board = run.Board(run.Find("DebloatBoard"))
	local bin = run.Find("Corbeille")
	local binPos = if bin and bin:IsA("BasePart") then bin.Position + Vector3.new(0, 4.8, 0) else run.At(22, 9, 2)
	local presetPad = run.Find("PresetPad")
	local roamMin = run.Folder:GetAttribute("RoamMin") or Vector2.new(-4, -40)
	local roamMax = run.Folder:GetAttribute("RoamMax") or Vector2.new(27, 0)
	local rng = Random.new()
	local views: { [number]: View } = {}
	local binLabel = if bin then Fx.Label(bin, "Corbeille · 3 éléments", nil, 7) else nil
	run.Add(binLabel)

	local function binText()
		if binLabel then
			local text = binLabel:FindFirstChild("Text") :: TextLabel?
			if text then
				text.Text = `Corbeille · {3 + sim.Captured} éléments`
			end
		end
	end

	local function randomTarget(): Vector2
		return Vector2.new(rng:NextNumber(roamMin.X, roamMax.X), rng:NextNumber(roamMin.Y, roamMax.Y))
	end

	local capture: (id: number) -> ()

	local function spawnView(monster: Debloat.Monster, from: Vector2?)
		local start = from or randomTarget()
		local model = Instance.new("Model")
		model.Name = "Bloatware"
		local size = if monster.Copy then 3.4 else 4.8
		local body = Fx.Part({
			Name = "Body",
			Size = Vector3.new(size, size * 0.86, size),
			CFrame = CFrame.new(run.At(start.X, size * 0.43, start.Y)),
			Color = BODY_COLORS[(monster.Id % #BODY_COLORS) + 1],
			Material = Enum.Material.SmoothPlastic,
		}, model)
		-- Yeux et étiquette « boîte de logiciel »
		for _, side in { -1, 1 } do
			Fx.Part({
				Name = "Eye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * size * 0.24,
				CFrame = body.CFrame * CFrame.new(side * size * 0.2, size * 0.18, -size * 0.5),
				Color = Color3.new(1, 1, 1),
			}, model)
			Fx.Part({
				Name = "Pupil",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * size * 0.11,
				CFrame = body.CFrame * CFrame.new(side * size * 0.2, size * 0.16, -size * 0.6),
				Color = Color3.fromRGB(20, 20, 26),
			}, model)
		end
		model.PrimaryPart = body
		model.Parent = run.Folder
		local tag = Fx.Label(body, monster.Name, Color3.fromHex("FCE100"), size * 0.6 + 1.2)
		tag.Size = UDim2.fromOffset(300, 40)
		local view: View =
			{ Id = monster.Id, Model = model, Body = body, Target = randomTarget(), U = start.X, V = start.Y }
		view.Prompt = run.Prompt(body, "Debloat", monster.Name, 0.7, 13, function()
			capture(monster.Id)
		end)
		views[monster.Id] = view
		run.Add(model)
		return view
	end

	local function suck(view: View)
		views[view.Id] = nil
		if view.Prompt then
			view.Prompt.Enabled = false
		end
		local root = run.Root()
		if root then
			Fx.Beam(root.Position, view.Body.Position, Color3.fromHex("8B7CFF"), 0.4, 0.5)
		end
		local cf = CFrame.new(binPos)
		for _, part in Fx.Parts(view.Model) do
			Fx.Tween(
				part,
				{ CFrame = cf, Size = part.Size * 0.15, Transparency = 0.6 },
				0.7,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.In
			)
		end
		task.delay(0.75, function()
			view.Model:Destroy()
			Fx.Burst(binPos, Color3.fromHex("C5C5C5"), 6)
		end)
		run.Sound("Collect", 0.8)
	end

	local function onEvents(events: { Debloat.Event })
		for _, event in events do
			if event.Kind == "Captured" and event.Monster then
				local view = views[event.Monster.Id]
				if view then
					suck(view)
				end
				local row = table.find(Debloat.NAMES, event.Monster.Name)
				if row then
					board:Row(row, "✓ Corbeille", "6CCB5F")
				end
			elseif event.Kind == "Copy" and event.Monster then
				local parentName = string.gsub(event.Monster.Name, " %(2%)$", "")
				local from: Vector2? = nil
				for _, view in views do
					local monster = Debloat.Find(sim, view.Id)
					if monster and monster.Name == parentName then
						from = Vector2.new(view.U, view.V)
					end
				end
				spawnView(event.Monster, from)
				run.Say(`{event.Monster.Name} s'est réinstallé tout seul ! Debloat plus vite.`, 3.5)
				run.Sound("Error", 1.2)
			elseif event.Kind == "AllCaptured" then
				run.Step(1, true)
				run.Status("Tout est dans la Corbeille : vide-la !")
				board:Title("Programmes inutiles : 0")
				if bin then
					local prompt = run.Prompt(bin, "Vider la Corbeille", "Corbeille", 0.6, 14, function()
						if Debloat.Empty(sim) then
							run.Step(2, true)
							run.Sound("Whoosh", 0.8)
							Fx.Burst(binPos, Color3.fromHex("4FD1C5"), 14)
							if binLabel then
								local text = binLabel:FindFirstChild("Text") :: TextLabel?
								if text then
									text.Text = "Corbeille vide ✓"
								end
							end
							run.Win(Debloat.Score(sim))
						end
					end)
					prompt.Enabled = true
				end
			end
		end
		binText()
		run.Step(
			1,
			#sim.Monsters == 0,
			`Aspirer les bloatware ({sim.Captured} dans la Corbeille, {#sim.Monsters} restants)`
		)
	end

	capture = function(id: number)
		onEvents(Debloat.Capture(sim, id))
	end

	run.Step(1, false, `Aspirer les bloatware (0 dans la Corbeille, {#sim.Monsters} restants)`)
	run.Step(2, false, "Vider la Corbeille")
	run.Status("Approche-toi d'un bloatware et maintiens « Debloat ».")
	local spawns = run.Children("MonsterSpawn")
	for index, monster in sim.Monsters do
		local marker = spawns[index]
		local from: Vector2? = nil
		if marker and marker:IsA("BasePart") then
			local u, _, v = run.ToRoom(marker.Position)
			from = Vector2.new(u, v)
		end
		spawnView(monster, from)
	end

	local presetUsed = false
	run.Every(function(dt: number)
		onEvents(Debloat.Step(sim, dt))
		-- Déplacement lent et dandinant vers une cible au hasard
		for _, view in views do
			local here = Vector2.new(view.U, view.V)
			local delta = view.Target - here
			if delta.Magnitude < 1 then
				view.Target = randomTarget()
			else
				local stepLen = math.min(delta.Magnitude, SPEED * dt)
				here += delta.Unit * stepLen
				view.U, view.V = here.X, here.Y
			end
			local size = view.Body.Size.Y
			local bob = math.abs(math.sin(os.clock() * 4 + view.Id)) * 0.5
			local position = run.At(view.U, size / 2 + bob, view.V)
			local look = run.At(view.Target.X, size / 2, view.Target.Y)
			local flat = Vector3.new(look.X - position.X, 0, look.Z - position.Z)
			local cf = if flat.Magnitude > 0.1 then CFrame.lookAt(position, position + flat) else CFrame.new(position)
			view.Model:PivotTo(cf)
		end
		-- Preset « Performance » : une fois, aspire tout ce qui est à portée
		local root = run.Root()
		if not presetUsed and root and presetPad and presetPad:IsA("BasePart") then
			local flat = (root.Position - presetPad.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude < 3.4 then
				presetUsed = true
				local ids = {}
				for _, view in views do
					if (view.Body.Position - root.Position).Magnitude <= Debloat.PRESET_RADIUS then
						table.insert(ids, view.Id)
					end
				end
				run.Toast("Boost", `Preset Performance : {#ids} bloatware aspirés d'un coup !`)
				run.Sound("PowerOn", 1.4)
				Fx.Burst(presetPad.Position + Vector3.new(0, 1, 0), Fx.ACCENT, 16)
				onEvents(Debloat.Preset(sim, ids))
			end
		end
	end)

	return function()
		board:Title("Programmes inutiles : 5")
		for i in Debloat.NAMES do
			board:Row(i, "En fond · 340 Mo", "FCE100")
		end
	end
end
