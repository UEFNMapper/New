--!strict
--[[
	Driver : épreuve du monde 6, « La carte graphique corrompue » (Shared/EpreuveLogic/Driver),
	en étapes comme la page Pilotes GPU de l'app, puis la page Écrans :
	1. Nettoyage complet : supprimer les quatre fichiers de l'ancien pilote (cubes qui glitchent) ;
	2. Télécharger : rester dans la colonne de lumière jusqu'à 100 % ;
	3. Installer : prendre chaque câble sur sa bobine et le brancher sur le port de sa couleur ;
	4. Écran : l'écran 2 est bridé à 60 Hz, le passer à 170 Hz.
	Tant que le pilote n'est pas installé, des artefacts apparaissent dans la salle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Driver = require(ReplicatedStorage:WaitForChild("Shared").EpreuveLogic.Driver)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)
local Fx = require(script.Parent.Parent.EpreuveFx)

local ARTIFACT_COLORS = { Color3.fromRGB(0, 255, 170), Color3.fromRGB(255, 0, 200), Color3.fromRGB(80, 160, 255) }
local CABLE_COLORS = { "4FD1C5", "9B2FD4", "F6C453" }

return function(run: any): () -> ()
	local sim = Driver.new()
	local board = run.Board(run.Find("DriverBoard"))
	local dlBoard = run.Board(run.Find("DownloadBoard"))
	local zone = run.Find("DownloadZone")
	local beamPart = run.Find("DownloadBeam")
	local radius = if zone then zone:GetAttribute("Radius") or 3.2 else 3.2
	local files: { BasePart } = {}
	for i = 1, #Driver.FILES do
		local cube = run.Find(`OldFile{i}`)
		if cube and cube:IsA("BasePart") then
			files[i] = cube
		end
	end
	local touched: { Instance } = {}
	for _, cube in files do
		table.insert(touched, cube)
	end
	local snapshot = Fx.Snapshot(touched, { "Transparency", "Size", "CFrame" })

	local function refresh()
		local stage = Driver.Stage(sim)
		local left = Driver.FilesLeft(sim)
		run.Step(1, stage > 1, `Nettoyage complet : ancien pilote ({#Driver.FILES - left}/{#Driver.FILES})`)
		run.Step(2, stage > 2, `Télécharger le pilote ({math.floor(sim.Download * 100)} %)`)
		run.Step(3, stage > 3, `Installer : brancher les câbles ({Driver.CablesPlugged(sim)}/{Driver.CABLES})`)
		run.Step(4, stage > 4, "Écran : fréquence maximale")
		board:Row(1, if left == 0 then "supprimé ✓" else `{left} fichiers`, if left == 0 then "6CCB5F" else "FF99A4")
		board:Row(2, `{math.floor(sim.Download * 100)} %`, if sim.Download >= 1 then "6CCB5F" else nil)
		board:Row(
			3,
			`{Driver.CablesPlugged(sim)} / {Driver.CABLES}`,
			if Driver.CablesPlugged(sim) == Driver.CABLES then "6CCB5F" else nil
		)
		local hz = sim.Hz[2]
		board:Row(4, `{hz} Hz`, if hz >= Driver.MAX_HZ then "6CCB5F" else "FF99A4")
		if stage >= 3 then
			board:Title("Pilote graphique : à jour")
		end
		run.Status(({
			"Supprime les fichiers de l'ancien pilote (cubes roses).",
			"Reste dans la colonne de lumière pour télécharger.",
			"Prends un câble sur sa bobine, branche-le sur le port de sa couleur.",
			"Un écran est bridé à 60 Hz : trouve-le et monte sa fréquence.",
			"Tout est réglé !",
		})[stage])
	end

	-- 1. Fichiers de l'ancien pilote
	for i, cube in files do
		run.Prompt(cube, "Supprimer", Driver.FILES[i], 0.5, 10, function()
			if Driver.Delete(sim, i) then
				Fx.Burst(cube.Position, Color3.fromHex("FF00C8"), 10)
				Fx.Tween(cube, { Size = Vector3.one * 0.1, Transparency = 1 }, 0.3)
				run.Sound("Collect", 0.7)
				refresh()
				if Driver.Stage(sim) == 2 then
					run.Say("Ancien pilote supprimé. Télécharge le nouveau : va dans la colonne de lumière.", 4)
				end
			end
		end)
	end

	-- 3. Câbles : bobines → ports (le câble suit le joueur, une Beam relie la bobine à la fiche)
	local plug: BasePart? = nil
	local keep: { Instance } = {}
	local function makeCable(reel: BasePart, color: Color3): (Beam, Attachment)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0, 0)
		a0.Parent = reel
		local endPart = Fx.Part({
			Name = "CablePlug",
			Size = Vector3.new(0.7, 0.7, 1.2),
			Color = color,
			Material = Enum.Material.Neon,
		})
		local a1 = Instance.new("Attachment")
		a1.Parent = endPart
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(color)
		beam.Width0 = 0.35
		beam.Width1 = 0.35
		beam.CurveSize0 = 2
		beam.CurveSize1 = -2
		beam.FaceCamera = true
		beam.LightEmission = 0.6
		beam.Parent = reel
		-- Les câbles branchés restent après la réussite ; retirés au retour à l'état de départ.
		table.insert(keep, beam)
		table.insert(keep, a0)
		table.insert(keep, endPart)
		return beam, a1
	end
	for i = 1, Driver.CABLES do
		local reel = run.Find(`Reel{i}`)
		local port = run.Find(`Port{i}`)
		if reel and reel:IsA("BasePart") then
			run.Prompt(reel, "Prendre le câble", `Câble {i}`, 0.3, 10, function()
				if Driver.Stage(sim) < 3 then
					run.Say("Pas encore : nettoyage et téléchargement d'abord.", 3)
				elseif Driver.Take(sim, i) then
					local _, a1 = makeCable(reel, Color3.fromHex(CABLE_COLORS[i]))
					plug = a1.Parent :: BasePart
					run.Sound("Click", 1.1)
				end
			end)
		end
		if port and port:IsA("BasePart") then
			run.Prompt(port, "Brancher", `Port {i}`, 0.2, 10, function()
				local result = Driver.Plug(sim, i)
				if result == "Ok" then
					local current = plug
					plug = nil
					if current then
						current.CFrame = port.CFrame * CFrame.new(0, 0, -0.5)
					end
					Fx.Burst(port.Position, port.Color, 8)
					run.Sound("Unlock", 1 + i * 0.1)
					refresh()
					if Driver.Stage(sim) == 4 then
						run.Say("Pilote installé ! Dernier réglage : un écran est bridé à 60 Hz.", 4)
					end
				elseif result == "Wrong" then
					run.Toast("Info", "Mauvais port : chaque câble va sur le port de sa couleur.")
					run.Sound("Error")
				end
			end)
		end
	end

	-- 4. Écrans : changer la fréquence de l'écran bridé
	local flicker: { [number]: BasePart } = {}
	for i = 1, #Driver.SCREENS do
		local monitor = run.Find(`Monitor{i}`)
		if monitor and monitor:IsA("BasePart") then
			if Driver.SCREENS[i] < Driver.MAX_HZ then
				flicker[i] = monitor
			end
			local monitorBoard = run.Board(monitor)
			run.Prompt(monitor, "Changer la fréquence", `Écran {i}`, 0.2, 10, function()
				if Driver.Stage(sim) < 4 then
					run.Say("Le pilote d'abord : sans lui, l'écran ne peut pas monter en fréquence.", 3)
					return
				end
				if sim.Hz[i] >= Driver.MAX_HZ then
					run.Toast("Info", `Écran {i} : déjà à {Driver.MAX_HZ} Hz, sa fréquence maximale.`)
					return
				end
				local hz = Driver.Cycle(sim, i)
				monitorBoard:Row(2, `{hz} Hz`, if hz >= Driver.MAX_HZ then "6CCB5F" else "FCE100")
				run.Sound("Click", 0.8 + hz / 300)
				refresh()
				if Driver.Stage(sim) == 5 then
					flicker[i] = nil
					for _, gui in monitor:GetChildren() do
						if gui:IsA("SurfaceGui") then
							gui.Enabled = true
						end
					end
					run.Win(Driver.Score(sim))
				end
			end)
		end
	end

	-- Boucle : glitch des fichiers, téléchargement, câble porté, écran saccadé, artefacts
	local artifactTimer = 0
	local clock = 0
	run.Every(function(dt: number)
		clock += dt
		local stage = Driver.Stage(sim)
		for i, cube in files do
			if not sim.Files[i] then
				cube.CFrame = cube.CFrame * CFrame.Angles(dt * 1.3, dt * 0.9, 0)
				cube.Color = ARTIFACT_COLORS[math.floor(clock * 6 + i) % #ARTIFACT_COLORS + 1]
			end
		end
		local root = run.Root()
		if stage == 2 and root and zone and zone:IsA("BasePart") then
			local flat = (root.Position - zone.Position) * Vector3.new(1, 0, 1)
			local inside = flat.Magnitude <= radius
			Driver.Step(sim, dt, inside)
			if beamPart and beamPart:IsA("BasePart") then
				beamPart.Transparency = if inside then 0.65 else 0.86
			end
			dlBoard:Bar(
				sim.Download,
				`Pilote 2026.10 · {math.floor(sim.Download * 100)} %`,
				if sim.Download >= 1 then "6CCB5F" else nil
			)
			run.Bar(
				sim.Download,
				if inside then "Téléchargement…" else "En pause : reviens dans la colonne de lumière"
			)
			if Driver.Stage(sim) == 3 then
				run.Bar(nil)
				run.Sound("Achievement", 1.4)
				run.Say("Téléchargé ! Installation : branche les trois câbles sur la carte graphique.", 4)
				refresh()
			elseif math.floor(clock * 4) % 4 == 0 then
				refresh()
			end
		end
		local current = plug
		if current and root then
			current.CFrame = root.CFrame * CFrame.new(1.2, 0.2, -1.4)
		end
		local on = math.floor(clock * 7) % 2 == 0
		for _, monitor in flicker do
			for _, gui in monitor:GetChildren() do
				if gui:IsA("SurfaceGui") then
					gui.Enabled = on or Motion.IsReduced()
				end
			end
		end
		artifactTimer += dt
		if stage < 4 and artifactTimer > 0.5 and not Motion.IsReduced() then
			artifactTimer = 0
			local rng = Random.new()
			local tile = Fx.Part({
				Name = "Artifact",
				Size = Vector3.new(rng:NextNumber(1, 4), rng:NextNumber(0.3, 1.5), 0.1),
				CFrame = CFrame.new(run.At(rng:NextNumber(-6, 28), rng:NextNumber(2, 18), 6.4))
					* CFrame.Angles(0, if math.abs(run.R.X) > 0.5 then math.pi / 2 else 0, 0),
				Color = ARTIFACT_COLORS[rng:NextInteger(1, #ARTIFACT_COLORS)],
				Material = Enum.Material.Neon,
				Transparency = 0.25,
			})
			task.delay(0.35, function()
				tile:Destroy()
			end)
		end
	end)

	run.Step(1, false, `Nettoyage complet : ancien pilote (0/{#Driver.FILES})`)
	run.Step(2, false, "Télécharger le pilote (0 %)")
	run.Step(3, false, `Installer : brancher les câbles (0/{Driver.CABLES})`)
	run.Step(4, false, "Écran : fréquence maximale")
	refresh()

	run.Add(function()
		-- Câble encore en main (épreuve interrompue) : il ne reste pas accroché au joueur.
		local current = plug
		if current and not run.Running() then
			current.Transparency = 1
		end
	end)

	return function()
		for _, item in keep do
			item:Destroy()
		end
		table.clear(keep)
		snapshot.Restore()
		local monitor2 = run.Find("Monitor2")
		if monitor2 then
			run.Board(monitor2):Row(2, "60 Hz", "FF99A4")
		end
		board:Title("Pilote graphique : corrompu")
		dlBoard:Bar(0, "Pilote 2026.10 · 0 %")
		sim = Driver.new()
		refresh()
	end
end
