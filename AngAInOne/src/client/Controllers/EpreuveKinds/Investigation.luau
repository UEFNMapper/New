--!strict
--[[
	Investigation : l'enquête du monde 7, « Sessions de jeu » (Shared/EpreuveLogic/Investigation),
	juste avant la phase finale du combat contre LAGZ. Le rapport accuse navigateur.exe ; chaque
	capsule dit qui a lancé le programme (« Lancé par ») et allume le câble vers son parent. On remonte
	jusqu'au processus masqué, LAGZ.exe, et on le met en quarantaine : la quarantaine, c'est le combat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Investigation = require(ReplicatedStorage:WaitForChild("Shared").EpreuveLogic.Investigation)
local Fx = require(script.Parent.Parent.EpreuveFx)

local VIOLET = Color3.fromHex("8B7CFF")

return function(run: any): () -> ()
	local sim = Investigation.new()
	local session = run.Board(run.Find("SessionBoard"))
	local touched: { Instance } = {}
	for _, pod in Investigation.PODS do
		local folder = run.Find(`Pod_{pod.Id}`)
		for _, part in Fx.Parts(folder) do
			table.insert(touched, part)
		end
		local link = run.Find(`Link_{pod.Id}`)
		if link then
			table.insert(touched, link)
		end
	end
	local snapshot = Fx.Snapshot(touched, { "Color", "Transparency" })

	local function podParts(id: string): (Instance?, BasePart?, BasePart?, Instance?)
		local folder = run.Find(`Pod_{id}`)
		local glass = if folder then folder:FindFirstChild("PodGlass") else nil
		local core = if folder then folder:FindFirstChild("PodCore") else nil
		local label = if folder then folder:FindFirstChild("PodLabel") else nil
		return folder,
			if glass and glass:IsA("BasePart") then glass else nil,
			if core and core:IsA("BasePart") then core else nil,
			label
	end

	local suspect = "browser"
	for _, pod in Investigation.PODS do
		if pod.Suspect then
			suspect = pod.Id
		end
	end

	local function refresh()
		run.Step(1, sim.Inspected[suspect] == true, "Inspecter le programme qui rame")
		run.Step(2, sim.Revealed, "Remonter « Lancé par » jusqu'au coupable")
		run.Step(3, sim.Quarantined, "Mettre le coupable en quarantaine")
	end

	local prompts: { [string]: ProximityPrompt } = {}

	local function reveal()
		local hidden = prompts.lagz
		if hidden then
			hidden.ActionText = "Mettre en quarantaine"
			hidden.ObjectText = "LAGZ.exe"
			hidden.HoldDuration = 1
		end
		local _, glass, core, label = podParts("lagz")
		if glass then
			Fx.Tween(glass, { Color = VIOLET, Transparency = 0.45 }, 0.6)
		end
		if core then
			core.Color = Color3.fromHex("FF5A5F")
			core.Transparency = 0
		end
		local board = run.Board(label)
		board:Title("LAGZ.exe")
		board:Row(1, "CPU 41 %", "FF99A4")
		board:Row(2, "free_robux_generator.exe", "FF99A4")
		if glass then
			Fx.Burst(glass.Position, VIOLET, 16)
		end
		run.Sound("Error", 0.7)
		run.Say("Le voilà : un processus masqué, LAGZ.exe ! Mets-le en quarantaine.", 4.5)
		session:Row(3, "LAGZ.exe (masqué)", "FF99A4")
	end

	local function inspect(id: string)
		local pod, revealed = Investigation.Inspect(sim, id)
		if not pod then
			return
		end
		local _, glass, _, label = podParts(id)
		local board = run.Board(label)
		local innocent = pod.Parent == nil
		board:Row(2, pod.ParentName, if innocent then "6CCB5F" else "FCE100")
		if glass then
			Fx.Burst(glass.Position + Vector3.new(0, 2, 0), if innocent then Fx.GOOD else Color3.fromHex("FCE100"), 6)
		end
		local link = run.Find(`Link_{id}`)
		if link and link:IsA("BasePart") then
			link.Color = VIOLET
			link.Transparency = 0.1
		end
		run.Sound("Click", 1.1)
		if innocent then
			run.Say(`{pod.Name} : lancé par {pod.ParentName}. Innocent.`, 3)
		elseif pod.Suspect then
			run.Say(`{pod.Name} rame, mais il a été lancé par {pod.ParentName}. Remonte la chaîne !`, 4)
		elseif not revealed then
			run.Say(`{pod.Name} : lancé par {pod.ParentName}…`, 3)
		end
		if revealed then
			reveal()
		end
		refresh()
	end

	for _, pod in Investigation.PODS do
		local _, glass = podParts(pod.Id)
		if glass then
			prompts[pod.Id] = run.Prompt(
				glass,
				"Inspecter",
				if pod.Hidden then "processus masqué" else pod.Name,
				0.3,
				11,
				function()
					if pod.Hidden and not sim.Revealed then
						run.Say(
							"Ce processus est masqué. Remonte d'abord la chaîne depuis le programme qui rame.",
							3.5
						)
						return
					end
					if pod.Hidden then
						local result = Investigation.Quarantine(sim, pod.Id)
						if result == "Ok" then
							local prompt = prompts[pod.Id]
							if prompt then
								prompt.Enabled = false
							end
							if glass then
								Fx.Tween(glass, { Color = Color3.fromHex("FF5A5F"), Transparency = 0.2 }, 0.4)
							end
							session:Row(1, "Coupable trouvé", "6CCB5F")
							refresh()
							run.Win(100)
						end
						return
					end
					inspect(pod.Id)
				end
			)
		end
	end

	run.Status("Le rapport accuse navigateur.exe… mais qui l'a lancé ?")
	refresh()

	return function()
		snapshot.Restore()
		for _, pod in Investigation.PODS do
			local _, _, _, label = podParts(pod.Id)
			local board = run.Board(label)
			board:Row(2, "?", "8F8F8F")
			if pod.Hidden then
				board:Title("processus masqué")
				board:Row(1, "???")
			end
		end
		session:Row(1, "🟡 Quelques accrocs", "FCE100")
		session:Row(3, "navigateur.exe ?", "FF99A4")
	end
end
