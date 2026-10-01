--!strict
--[[
	Cooling : épreuve du monde 4, « La surchauffe » (Shared/EpreuveLogic/Cooling).
	Le sol du bassin devient rouge et la lave monte ; on saute de socle en socle (la lave ne monte
	jamais sur les socles), on relance les trois ventilateurs bouchés, puis on passe le plan
	d'alimentation en « Équilibré » : la lave redescend. Toucher la lave : on recommence.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cooling = require(ReplicatedStorage:WaitForChild("Shared").EpreuveLogic.Cooling)
local Fx = require(script.Parent.Parent.EpreuveFx)

local LAVA = Color3.fromRGB(255, 96, 32)
local FEET_BELOW_ROOT = 3

return function(run: any): () -> ()
	local sim = Cooling.new()
	local board = run.Board(run.Find("HeatBoard"))
	local plan = run.Find("PlanSwitch")
	local planBoard = run.Board(plan)
	local anchor = run.Find("LavaAnchor")
	local sizeU = if anchor then anchor:GetAttribute("SizeU") or 20 else 20
	local sizeV = if anchor then anchor:GetAttribute("SizeV") or 34 else 34
	local center = if anchor and anchor:IsA("BasePart") then anchor.Position else run.At(18, 0, -13)
	local basinCf = CFrame.fromMatrix(center, run.F, Vector3.yAxis)
	local lava = Fx.Part({
		Name = "Lava",
		Size = Vector3.new(sizeU, 0.4, sizeV),
		CFrame = basinCf * CFrame.new(0, Cooling.LAVA_START, 0),
		Color = LAVA,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	run.Add(lava)
	local glow = Instance.new("PointLight")
	glow.Color = LAVA
	glow.Range = 30
	glow.Brightness = 1.5
	glow.Parent = lava
	-- Le sol de la salle vire au rouge
	local house = run.Terminal:FindFirstChild("TerminalRoom")
	local floor = if house then house:FindFirstChild("Floor") else nil
	local floorSnap = Fx.Snapshot(if floor then { floor } else {}, { "Color" })
	if floor and floor:IsA("BasePart") then
		Fx.Tween(floor, { Color = Color3.fromRGB(92, 28, 20) }, 1.5)
	end

	local function refresh()
		local temp = Cooling.Temperature(sim)
		board:Big(
			`{temp} °C`,
			if temp > 70 then "Alerte : ça chauffe (95 °C = rouge)" else "Ça respire",
			if temp > 70 then "FF99A4" elseif temp > 50 then "FCE100" else "6CCB5F"
		)
		for i = 1, Cooling.FANS do
			board:Row(i, if sim.Fans[i] then "tourne ✓" else "bouché", if sim.Fans[i] then "6CCB5F" else "FF99A4")
		end
		board:Row(
			4,
			if sim.Balanced then "Équilibré ✓" else "Performances max",
			if sim.Balanced then "6CCB5F" else "FCE100"
		)
		planBoard:Row(1, if sim.Balanced then "○" else "●", if sim.Balanced then "8F8F8F" else "FF99A4")
		planBoard:Row(2, if sim.Balanced then "●" else "○", if sim.Balanced then "6CCB5F" else "8F8F8F")
		run.Step(
			1,
			Cooling.FansOn(sim) == Cooling.FANS,
			`Relancer les ventilateurs ({Cooling.FansOn(sim)}/{Cooling.FANS})`
		)
		run.Step(2, sim.Balanced, "Plan d'alimentation : Équilibré")
		run.Status(`Processeur : {temp} °C`)
	end

	local spins: { () -> () } = {}
	for i = 1, Cooling.FANS do
		local fan = run.Find(`Fan{i}`)
		local housing = if fan then fan:FindFirstChild("FanHousing") else nil
		if fan and housing then
			run.Prompt(housing, "Relancer le ventilateur", `Ventilateur {i}`, 0.8, 10, function()
				if Cooling.Restart(sim, i) then
					run.Sound("PowerOn", 0.9 + i * 0.1)
					for _, part in fan:GetChildren() do
						if part.Name == "FanDust" and part:IsA("BasePart") then
							Fx.Tween(part, { Transparency = 1 }, 0.5)
						elseif part.Name == "FanLed" and part:IsA("BasePart") then
							part.Color = Fx.GOOD
						end
					end
					local hub = fan:FindFirstChild("FanHub")
					local blades = {}
					for _, part in fan:GetChildren() do
						if part.Name == "Blade" and part:IsA("BasePart") then
							table.insert(blades, part)
						end
					end
					if hub and hub:IsA("BasePart") and housing:IsA("BasePart") then
						table.insert(spins, Fx.Spin(blades, hub.Position, housing.CFrame.LookVector, 2.5))
					end
					Fx.Burst(housing.Position, Color3.fromHex("4FD1C5"), 8)
					refresh()
					if Cooling.FansOn(sim) == Cooling.FANS then
						run.Say("Les trois ventilateurs tournent. Maintenant, le plan d'alimentation !", 3.5)
					end
				end
			end)
		end
	end
	if plan then
		run.Prompt(plan, "Passer en « Équilibré »", "Plan d'alimentation", 0.4, 10, function()
			local result = Cooling.SetBalanced(sim)
			if result == "FansFirst" then
				run.Say("Relance d'abord les trois ventilateurs : sans air, rien ne refroidit.", 3.5)
				run.Sound("Error")
			elseif result == "Ok" then
				run.Sound("Unlock", 1)
				refresh()
			end
		end)
	end

	run.Say("La lave monte ! Reste sur les socles.", 3)
	refresh()
	run.Every(function(dt: number)
		Cooling.Step(sim, dt)
		lava.CFrame = basinCf * CFrame.new(0, sim.Lava - 0.2, 0)
		local root = run.Root()
		if root and not sim.Done then
			local u, h, v = run.ToRoom(root.Position)
			if Cooling.InLava(u, v) and Cooling.Burns(sim, h - FEET_BELOW_ROOT) then
				run.Kill("Lava")
			end
		end
		if sim.Done and run.Running() then
			if floor and floor:IsA("BasePart") then
				floorSnap.Restore()
			end
			refresh()
			run.Win(100)
		end
	end)

	run.Add(function()
		for _, stop in spins do
			stop()
		end
	end)
	return function()
		floorSnap.Restore()
		for i = 1, Cooling.FANS do
			local fan = run.Find(`Fan{i}`)
			if fan then
				for _, part in fan:GetChildren() do
					if part.Name == "FanDust" and part:IsA("BasePart") then
						part.Transparency = 0.05
					elseif part.Name == "FanLed" and part:IsA("BasePart") then
						part.Color = Fx.BAD
					end
				end
			end
		end
		sim = Cooling.new()
		refresh()
	end
end
