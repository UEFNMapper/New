--!strict
--[[
	Startup : épreuve du monde 1, « Le Démarrage infecté » (Shared/EpreuveLogic/Startup).
	Le couloir « démarre » porte par porte ; on lit chaque porte (éditeur, impact) ; on coupe le levier
	des deux intrus. Couper un programme vérifié : l'interrupteur revient, l'assistant explique.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Startup = require(ReplicatedStorage:WaitForChild("Shared").EpreuveLogic.Startup)
local Fx = require(script.Parent.Parent.EpreuveFx)

local READ_DISTANCE = 8
local READ_NEEDED = 4

return function(run: any): () -> ()
	local sim = Startup.new()
	local doors: { [number]: Instance } = {}
	for i = 1, #Startup.DOORS do
		local door = run.Find(`Door{i}`)
		if door then
			doors[i] = door
		end
	end
	local touched: { Instance } = {}
	for _, door in doors do
		for _, part in Fx.Parts(door) do
			table.insert(touched, part)
		end
	end
	local snapshot = Fx.Snapshot(touched, { "Color", "Transparency" })
	local runway = run.Find("Runway")
	local runwaySnap = Fx.Snapshot(if runway then { runway } else {}, { "Color" })
	local wall = run.Find("StartupWall")

	run.Step(1, false, `Lire les portes du Démarrage (0/{READ_NEEDED})`)
	run.Step(2, false, `Désactiver les {Startup.CULPRITS} intrus (0/{Startup.CULPRITS})`)
	run.Status("Démarrage du PC en cours…")

	-- Séquence de démarrage : chaque porte s'allume à son tour
	for i, door in doors do
		local led = door:FindFirstChild("DoorLed")
		if led and led:IsA("BasePart") then
			led.Color = Fx.STROKE
			run.Delay(0.25 * i, function()
				led.Color = Fx.GOOD
				run.Sound("Click", 1 + i * 0.05)
			end)
		end
	end
	run.Delay(0.25 * #Startup.DOORS + 0.3, function()
		run.Status("Lis l'éditeur de chaque porte : deux sont « Inconnu ».")
	end)

	-- Yeux qui clignent derrière les portes des intrus
	local blink = 0
	local read: { [number]: boolean } = {}
	local readCount = 0
	run.Every(function(dt: number)
		blink += dt
		local open = (blink % 2.6) < 2.35
		for i, door in doors do
			local data = Startup.DOORS[i]
			if data.Culprit and not sim.Disabled[data.Id] then
				for _, eye in door:GetChildren() do
					if eye.Name == "DoorEye" and eye:IsA("BasePart") then
						eye.Transparency = if open then 0 else 1
					end
				end
			end
		end
		-- Lecture : il faut s'approcher des portes
		local root = run.Root()
		if root and readCount < READ_NEEDED then
			for i, door in doors do
				local leaf = door:FindFirstChild("DoorLeaf")
				if
					not read[i]
					and leaf
					and leaf:IsA("BasePart")
					and (leaf.Position - root.Position).Magnitude <= READ_DISTANCE
				then
					read[i] = true
					readCount += 1
					run.Step(
						1,
						readCount >= READ_NEEDED,
						`Lire les portes du Démarrage ({math.min(readCount, READ_NEEDED)}/{READ_NEEDED})`
					)
				end
			end
		end
	end)

	local function disable(index: number)
		local door = doors[index]
		local data = Startup.DOORS[index]
		local plate = door:FindFirstChild("LeverPlate")
		local result = Startup.Toggle(sim, data.Id)
		if result == "Culprit" then
			if plate then
				Fx.Toggle(plate, false)
			end
			local led = door:FindFirstChild("DoorLed")
			if led and led:IsA("BasePart") then
				led.Color = Fx.BAD
			end
			for _, child in door:GetChildren() do
				if (child.Name == "DoorLeak" or child.Name == "DoorEye") and child:IsA("BasePart") then
					child.Transparency = 1
				end
			end
			local leaf = door:FindFirstChild("DoorLeaf")
			run.Board(leaf):Row(3, "Désactivé", "FF99A4")
			run.Sound("Unlock", 1.1)
			if leaf and leaf:IsA("BasePart") then
				Fx.Burst(leaf.Position, Color3.fromHex("8B7CFF"), 10)
			end
			run.Say(data.Hint, 4)
			run.Step(2, sim.Done, `Désactiver les {Startup.CULPRITS} intrus ({sim.Found}/{Startup.CULPRITS})`)
			if wall then
				run.Board(wall):Row(3, tostring(Startup.CULPRITS - sim.Found), if sim.Done then "6CCB5F" else "FF99A4")
			end
			if sim.Done then
				run.Step(1, true)
				if runway and runway:IsA("BasePart") then
					runway.Color = Fx.GOOD
				end
				if wall then
					run.Board(wall):Row(1, "4")
				end
				run.Win(Startup.Score(sim))
			end
		elseif result == "Legit" then
			if plate then
				Fx.Toggle(plate, false)
				run.Delay(0.6, function()
					Fx.Toggle(plate, true)
				end)
			end
			run.Sound("Error")
			run.Say(data.Hint, 4)
		end
	end

	for i, door in doors do
		local post = door:FindFirstChild("LeverPost")
		if post then
			run.Prompt(post, "Désactiver au démarrage", Startup.DOORS[i].Name, 0.35, 9, function()
				disable(i)
			end)
		end
	end

	return function()
		snapshot.Restore()
		runwaySnap.Restore()
		for _, door in doors do
			local plate = door:FindFirstChild("LeverPlate")
			if plate then
				Fx.Toggle(plate, true)
			end
			run.Board(door:FindFirstChild("DoorLeaf")):Row(3, "Activé", "6CCB5F")
		end
		if wall then
			run.Board(wall):Row(1, "6")
			run.Board(wall):Row(3, "2", "FF99A4")
		end
	end
end
