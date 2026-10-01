--!strict
--[[
	RamSlots : épreuve du monde 2, « La RAM saturée » (Shared/EpreuveLogic/RamSlots).
	1. Retirer une barrette (on la porte au-dessus de la tête), l'insérer dans un emplacement libre :
	   A2 + B2 = double canal (le tableau de bord le montre).
	2. La mémoire se remplit de déchets (onglets qui tombent sur les barrettes) ; au-delà de 85 %,
	   le joueur ralentit. Le gros bouton « Libérer la RAM » la vide (recharge 4 s). Trois fois : réussi.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RamSlots = require(ReplicatedStorage:WaitForChild("Shared").EpreuveLogic.RamSlots)
local Fx = require(script.Parent.Parent.EpreuveFx)

local CARRY_SCALE = 0.32
local JUNK_COLORS =
	{ Color3.fromHex("F6C453"), Color3.fromHex("4FD1C5"), Color3.fromHex("FF99A4"), Color3.fromHex("8B7CFF") }

return function(run: any): () -> ()
	local sim = RamSlots.new()
	local board = run.Board(run.Find("RamBoard"))
	local sticks: { Model } = {}
	local home: { CFrame } = {} -- pivot de départ de chaque barrette
	local slotPos: { Vector3 } = {}
	for slot = 1, #RamSlots.SLOTS do
		local marker = run.Find(`Slot{slot}`)
		if marker and marker:IsA("BasePart") then
			slotPos[slot] = marker.Position
		end
	end
	for stick = 1, 2 do
		local model = run.Find(`Stick{stick}`)
		if model and model:IsA("Model") then
			sticks[stick] = model
			home[stick] = model:GetPivot()
		end
	end
	if #sticks < 2 or #slotPos < 4 then
		run.Fail("Salle de la RAM incomplète")
		return function() end
	end

	local function refreshBoard()
		for slot, name in RamSlots.SLOTS do
			local stick = RamSlots.StickIn(sim, slot)
			board:Row(slot, if stick then "● Barrette" else "○ Vide", if stick then "6CCB5F" else "8F8F8F")
			local _ = name
		end
		local dual = RamSlots.DualChannel(sim)
		board:Row(5, if dual then "Double canal ✓" else "Simple canal", if dual then "6CCB5F" else "FF99A4")
	end

	-- Pivot d'une barrette posée dans l'emplacement `slot` (même orientation, translation entre slots)
	local function slotPivot(stick: number, slot: number): CFrame
		local start = RamSlots.START[stick]
		return home[stick] + (slotPos[slot] - slotPos[start])
	end

	local carryPrompts: { ProximityPrompt } = {}
	local insertPrompts: { [number]: ProximityPrompt } = {}
	local carried: Model? = nil

	local function setPrompts()
		for stick, prompt in carryPrompts do
			prompt.Enabled = sim.Phase == "Slots" and sim.Carrying == nil and sim.Sticks[stick] ~= 0
		end
		for slot, prompt in insertPrompts do
			prompt.Enabled = sim.Phase == "Slots" and sim.Carrying ~= nil and RamSlots.StickIn(sim, slot) == nil
		end
	end

	run.Step(1, false, "Barrettes en A2 + B2")
	run.Step(2, false, `Libérer la RAM (0/{RamSlots.FLUSHES})`)
	run.Status("Les barrettes sont en A1 et B1 : déplace-les en A2 et B2.")

	for stick, model in sticks do
		local grip = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if grip then
			carryPrompts[stick] = run.Prompt(grip, "Retirer la barrette", `Barrette {stick}`, 0.2, 12, function()
				if RamSlots.Take(sim, stick) then
					carried = model
					model:ScaleTo(CARRY_SCALE)
					run.Sound("Click", 0.9)
					run.Status("Porte la barrette jusqu'à un emplacement libre.")
					setPrompts()
					refreshBoard()
				end
			end)
		end
	end
	for slot, position in slotPos do
		local marker = run.Find(`Slot{slot}`)
		if marker then
			insertPrompts[slot] = run.Prompt(
				marker,
				`Insérer en {RamSlots.SLOTS[slot]}`,
				"Emplacement mémoire",
				0.2,
				12,
				function()
					local stick = sim.Carrying
					if stick and RamSlots.Insert(sim, slot) then
						local model = sticks[stick]
						carried = nil
						model:ScaleTo(1)
						model:PivotTo(slotPivot(stick, slot))
						run.Sound("Unlock", if RamSlots.TARGET[slot] then 1.2 else 0.8)
						Fx.Burst(position, Fx.GOOD, 6)
						refreshBoard()
						if sim.Phase == "Flush" then
							run.Step(1, true)
							run.Say("A2 + B2 : double canal activé ! Maintenant, la mémoire se remplit…", 4)
							run.Status("Appuie sur « Libérer la RAM » quand la jauge remonte.")
						elseif not RamSlots.TARGET[slot] then
							run.Say(`{RamSlots.SLOTS[slot]} ? Avec deux barrettes, la carte mère veut A2 et B2.`, 3.5)
						end
					end
					setPrompts()
				end
			)
		end
	end
	setPrompts()

	-- Barrette portée : suit le joueur, au-dessus de sa tête
	local junk: { BasePart } = {}
	local junkTimer = 0
	run.Every(function(dt: number)
		local root = run.Root()
		if carried and root then
			carried:PivotTo(root.CFrame * CFrame.new(0, 4.2, 0) * CFrame.Angles(0, math.pi / 2, 0))
		end
		if sim.Phase ~= "Flush" then
			return
		end
		RamSlots.Step(sim, dt)
		run.Speed(RamSlots.SpeedFactor(sim))
		local ram = math.floor(sim.Ram + 0.5)
		run.Bar(sim.Ram / 100, `Mémoire utilisée : {ram} %`)
		board:Bar(sim.Ram / 100, `Utilisée : {ram} %`, if ram >= RamSlots.SLOW_FROM then "FF99A4" else "9B2FD4")
		-- Déchets : des « onglets » tombent sur les barrettes tant que la mémoire se remplit
		junkTimer += dt
		if junkTimer > 0.35 and #junk < 40 and ram < 100 then
			junkTimer = 0
			local rng = Random.new()
			local slot = if rng:NextNumber() < 0.5 then 2 else 4
			local top = slotPos[slot] + Vector3.new(0, 5, 0) + run.R * rng:NextNumber(-8, 8)
			local cube = Fx.Part({
				Name = "RamJunk",
				Size = Vector3.new(1.4, 1, 0.3),
				CFrame = CFrame.new(top + Vector3.new(0, 10, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
				Color = JUNK_COLORS[rng:NextInteger(1, #JUNK_COLORS)],
				Material = Enum.Material.Neon,
			})
			Fx.Tween(
				cube,
				{ CFrame = CFrame.new(top) * CFrame.Angles(0, rng:NextNumber(0, 3), 0.3) },
				0.5,
				Enum.EasingStyle.Bounce
			)
			table.insert(junk, cube)
		end
	end)

	local cap = run.Find("FlushCap")
	if cap and cap:IsA("BasePart") then
		local base = cap.Color
		run.Prompt(cap, "Libérer la RAM", "Tableau de bord", 0, 11, function()
			local result = RamSlots.Flush(sim, os.clock())
			if result == "NotYet" then
				run.Say("D'abord les barrettes : A2 et B2.", 3)
			elseif result == "Cooldown" then
				run.Toast("Info", "Le bouton recharge…")
			else
				cap.Color = Fx.GOOD
				run.Delay(0.8, function()
					cap.Color = base
				end)
				run.Sound("PowerOn", 1.25)
				for _, cube in junk do
					Fx.Tween(cube, { Transparency = 1, Size = Vector3.one * 0.1 }, 0.35)
					task.delay(0.4, function()
						cube:Destroy()
					end)
				end
				table.clear(junk)
				local ring = Fx.Part({
					Name = "FlushWave",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.3, 2, 2),
					CFrame = CFrame.new(cap.Position) * CFrame.Angles(0, 0, math.pi / 2),
					Color = Color3.fromHex("4FD1C5"),
					Material = Enum.Material.Neon,
					Transparency = 0.3,
				})
				Fx.Tween(ring, { Size = Vector3.new(0.3, 44, 44), Transparency = 1 }, 0.7)
				task.delay(0.75, function()
					ring:Destroy()
				end)
				run.Step(2, sim.Phase == "Done", `Libérer la RAM ({sim.Flushes}/{RamSlots.FLUSHES})`)
				if sim.Phase == "Done" then
					run.Speed(nil)
					run.Bar(nil)
					board:Bar(0.32, "Utilisée : 32 %", "6CCB5F")
					board:Title("Mémoire 5,1 / 16 Go")
					run.Win(RamSlots.Score(sim))
				end
			end
		end)
	end
	refreshBoard()

	run.Add(function()
		for _, cube in junk do
			cube:Destroy()
		end
	end)
	return function()
		for stick, model in sticks do
			if model.Parent then
				model:ScaleTo(1)
				model:PivotTo(home[stick])
			end
		end
		board:Title("Mémoire 15,7 / 16 Go")
		board:Bar(0.98, "Utilisée : 98 %", "FF99A4")
		sim = RamSlots.new()
		refreshBoard()
	end
end
