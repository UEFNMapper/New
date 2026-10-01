-- Épreuves 3D des salles du terminal (Config/Epreuves, Shared/EpreuveLogic) : logique PURE.
-- Des joueurs simulés jouent chaque épreuve : un bon joueur réussit, les erreurs coûtent, les
-- garde-fous tiennent (la lave ne monte jamais sur les socles, le preset ne sert qu'une fois…).
local Epreuves = Shim.load("src/shared/Config/Epreuves.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")
local Startup = Shim.load("src/shared/EpreuveLogic/Startup.luau")
local RamSlots = Shim.load("src/shared/EpreuveLogic/RamSlots.luau")
local Debloat = Shim.load("src/shared/EpreuveLogic/Debloat.luau")
local Cooling = Shim.load("src/shared/EpreuveLogic/Cooling.luau")
local CpuDefense = Shim.load("src/shared/EpreuveLogic/CpuDefense.luau")
local Driver = Shim.load("src/shared/EpreuveLogic/Driver.luau")
local Investigation = Shim.load("src/shared/EpreuveLogic/Investigation.luau")

local DT = 1 / 30
local SEEDS = { 1, 7, 42, 1234, 99991, 314159, 2718281, 55555 }

-- Défense : construit dès que possible, sur l'emplacement libre le plus utile (le plus de processus
-- à portée, à défaut le plus proche du processeur). `think` = délai entre deux constructions.
local function playDefense(seed: number, strategy: string, think: number?): any
	local sim = CpuDefense.new(CpuDefense.ROOM_LAYOUT, seed)
	local nextMove = 0
	while not sim.Done do
		CpuDefense.Step(sim, DT)
		if strategy ~= "idle" and sim.Time >= nextMove and sim.Energy >= sim.Params.Cost then
			nextMove = sim.Time + (think or 0.8)
			local best, bestScore = nil, -math.huge
			for slot, origin in sim.Layout.Slots do
				if not sim.Turrets[slot] and (strategy ~= "one" or slot == 1) then
					local score = -(origin - CpuDefense.CPU).Magnitude * 0.1
					for _, virus in sim.Viruses do
						if (CpuDefense.Position(sim, virus) - origin).Magnitude <= sim.Params.Range + 4 then
							score += 1
						end
					end
					if score > bestScore then
						best, bestScore = slot, score
					end
				end
			end
			if best then
				CpuDefense.Build(sim, best)
			end
		end
	end
	return sim
end

return {
	["config : une épreuve par monde, avec fiche, étapes et durée minimale"] = function()
		for w = 1, Tower.WORLD_COUNT do
			local e = Epreuves.ByWorld[w]
			Expect.truthy(e, `épreuve du monde {w}`)
			Expect.truthy(#e.Fiche.Constat > 20 and #e.Fiche.Pourquoi > 20 and #e.Fiche.QuoiFaire > 20, "fiche")
			Expect.truthy(#e.Steps >= 2, "étapes")
			Expect.truthy(#e.Start > 4 and #e.Done > 10, "textes")
			Expect.equal(Epreuves.ClearsWorld(w), w < Tower.WORLD_COUNT, "le monde 7 garde le combat final")
			if w < Tower.WORLD_COUNT then
				Expect.truthy(e.MinSeconds >= 5, "durée minimale utile")
			end
		end
	end,

	["démarrage : couper les deux intrus termine, un programme vérifié compte une erreur"] = function()
		Expect.equal(Startup.CULPRITS, 2)
		local state = Startup.new()
		Expect.equal(Startup.Toggle(state, "chat"), "Legit")
		Expect.equal(state.Mistakes, 1)
		Expect.equal(Startup.Toggle(state, "ram"), "Culprit")
		Expect.equal(Startup.Toggle(state, "ram"), "Already")
		Expect.equal(state.Done, false)
		Expect.equal(Startup.Toggle(state, "robux"), "Culprit")
		Expect.equal(state.Done, true)
		Expect.equal(Startup.Score(state), 85)
		for _, door in Startup.DOORS do
			Expect.equal(door.Culprit == true, door.Editor == "Inconnu", `{door.Name} : indice = éditeur`)
			Expect.truthy(#door.Hint > 10, "indice")
		end
	end,

	["RAM : A2 + B2 en deux déplacements, puis trois libérations avec recharge"] = function()
		local state = RamSlots.new()
		Expect.equal(RamSlots.DualChannel(state), false)
		Expect.equal(RamSlots.Insert(state, 2), false, "mains vides")
		Expect.truthy(RamSlots.Take(state, 1))
		Expect.equal(RamSlots.Take(state, 2), false, "une barrette à la fois")
		Expect.equal(RamSlots.Insert(state, 3), false, "B1 occupé")
		Expect.truthy(RamSlots.Insert(state, 2))
		Expect.truthy(RamSlots.Take(state, 2))
		Expect.truthy(RamSlots.Insert(state, 4))
		Expect.equal(state.Phase, "Flush")
		Expect.equal(RamSlots.Score(state), 100)
		local now = 0
		RamSlots.Step(state, 10)
		Expect.equal(state.Ram, 100, "plafond")
		Expect.equal(RamSlots.SpeedFactor(state), RamSlots.SLOW_FACTOR, "ralenti quand c'est plein")
		Expect.equal(RamSlots.Flush(state, now), "Ok")
		Expect.equal(RamSlots.SpeedFactor(state), 1)
		Expect.equal(RamSlots.Flush(state, now + 1), "Cooldown")
		Expect.equal(RamSlots.Flush(state, now + RamSlots.COOLDOWN), "Ok")
		Expect.equal(RamSlots.Flush(state, now + 2 * RamSlots.COOLDOWN), "Ok")
		Expect.equal(state.Phase, "Done")
		Expect.truthy(2 * RamSlots.COOLDOWN < Epreuves.ByWorld[2].MinSeconds + 2 * RamSlots.COOLDOWN, "durée")
	end,

	["debloat : copies limitées, preset unique, Corbeille vidée à la fin seulement"] = function()
		local state = Debloat.new()
		Expect.equal(#state.Monsters, #Debloat.NAMES)
		for _ = 1, 200 do
			Debloat.Step(state, 1)
		end
		Expect.equal(state.Copies, Debloat.MAX_COPIES, "copies plafonnées")
		Expect.equal(Debloat.CanEmpty(state), false)
		local ids = {}
		for i = 1, 3 do
			table.insert(ids, state.Monsters[i].Id)
		end
		Expect.equal(#Debloat.Preset(state, ids) >= 3, true)
		Expect.equal(#Debloat.Preset(state, { state.Monsters[1].Id }), 0, "preset une seule fois")
		while #state.Monsters > 0 do
			Debloat.Capture(state, state.Monsters[1].Id)
		end
		Expect.equal(state.Captured, #Debloat.NAMES + Debloat.MAX_COPIES)
		Expect.truthy(Debloat.Empty(state))
		Expect.equal(Debloat.Empty(state), false)
		Expect.equal(Debloat.Score(state), 100 - 10 * Debloat.MAX_COPIES)
	end,

	["surchauffe : la lave reste sous les socles, ventilos d'abord, puis le plan la fait descendre"] = function()
		Expect.truthy(Cooling.LAVA_MAX + 0.2 < Cooling.PEDESTAL_MIN_TOP, "jamais sur les socles")
		local state = Cooling.new()
		for _ = 1, 600 do
			Cooling.Step(state, DT)
		end
		Expect.truthy(state.Lava > 0 and state.Lava <= Cooling.LAVA_MAX)
		Expect.truthy(Cooling.Burns(state, 0), "le sol du bassin brûle")
		Expect.equal(Cooling.Burns(state, Cooling.PEDESTAL_MIN_TOP), false, "les socles sont sûrs")
		Expect.equal(Cooling.SetBalanced(state), "FansFirst")
		for fan = 1, Cooling.FANS do
			Expect.truthy(Cooling.Restart(state, fan))
		end
		Expect.equal(Cooling.Restart(state, 1), false)
		Expect.equal(Cooling.Temperature(state), Cooling.TEMP_START - Cooling.FANS * Cooling.TEMP_PER_FAN)
		Expect.equal(Cooling.SetBalanced(state), "Ok")
		local t = 0
		while not state.Done and t < 30 do
			Cooling.Step(state, DT)
			t += DT
		end
		Expect.truthy(state.Done, "la lave redescend")
		Expect.truthy(t < 6, "vite")
		Expect.equal(Cooling.Burns(state, 0), false)
		Expect.equal(Cooling.Temperature(state), 45)
	end,

	["défense du CPU : un bon stratège gagne toujours, ne rien faire ou un seul emplacement perd"] = function()
		local times = {}
		for _, seed in SEEDS do
			local smart = playDefense(seed, "smart")
			Expect.truthy(smart.Success, `stratège graine {seed} (fuites {smart.Leaks})`)
			Expect.truthy(smart.Time > Epreuves.ByWorld[5].MinSeconds, "durée minimale du serveur")
			table.insert(times, string.format("%.0f", smart.Time))
			Expect.equal(playDefense(seed, "idle").Success, false, "inactif")
			Expect.equal(playDefense(seed, "one").Success, false, "un seul emplacement")
			local fast = playDefense(seed, "smart", 0)
			Expect.truthy(not fast.Success or fast.Time > Epreuves.ByWorld[5].MinSeconds, "même au plus vite")
		end
		print(`    défense du CPU (s) : {table.concat(times, " ")}`)
		-- Emplacements à portée d'au moins un bus, positions sur le chemin
		local sim = CpuDefense.new(CpuDefense.ROOM_LAYOUT, 1)
		for slot, origin in sim.Layout.Slots do
			local near = false
			for path in sim.Layout.Paths do
				for d = 0, sim.Lengths[path], 1 do
					local p = CpuDefense.Position(sim, { Id = 0, Path = path, Distance = d, Hp = 1, Tough = false })
					if (p - origin).Magnitude <= sim.Params.Range then
						near = true
					end
				end
			end
			Expect.truthy(near, `emplacement {slot} utile`)
		end
		Expect.equal(#CpuDefense.OPTIMISATIONS, #sim.Layout.Slots, "un nom d'optimisation par emplacement")
	end,

	["pilote GPU : étapes dans l'ordre, téléchargement en pause hors zone, bon port, 170 Hz"] = function()
		local state = Driver.new()
		Expect.equal(Driver.Stage(state), 1)
		Expect.equal(Driver.Take(state, 1), false, "pas avant le nettoyage")
		for i = 1, #Driver.FILES do
			Expect.truthy(Driver.Delete(state, i))
		end
		Expect.equal(Driver.Stage(state), 2)
		Driver.Step(state, 100, false)
		Expect.equal(state.Download, 0, "en pause hors de la zone")
		local t = 0
		while state.Download < 1 do
			Driver.Step(state, DT, true)
			t += DT
		end
		Expect.truthy(math.abs(t - Driver.DOWNLOAD_SECONDS) < 0.1)
		Expect.equal(Driver.Stage(state), 3)
		Expect.truthy(Driver.Take(state, 2))
		Expect.equal(Driver.Plug(state, 1), "Wrong")
		Expect.equal(Driver.Plug(state, 2), "Ok")
		Expect.truthy(Driver.Take(state, 1))
		Expect.equal(Driver.Plug(state, 1), "Ok")
		Expect.truthy(Driver.Take(state, 3))
		Expect.equal(Driver.Plug(state, 3), "Ok")
		Expect.equal(Driver.Stage(state), 4)
		local screen = table.find(Driver.SCREENS, 60)
		Expect.truthy(screen, "un écran bridé à 60 Hz")
		local hz = 0
		for _ = 1, 3 do
			hz = Driver.Cycle(state, screen :: number)
		end
		Expect.equal(hz, Driver.MAX_HZ)
		Expect.equal(Driver.Stage(state), 5)
		Expect.equal(Driver.Score(state), 90)
	end,

	["enquête : la chaîne mène au processus masqué, seul le coupable part en quarantaine"] = function()
		local state = Investigation.new()
		Expect.equal(Investigation.Quarantine(state, "lagz"), "Hidden")
		Expect.equal((Investigation.Inspect(state, "lagz")), nil, "masqué")
		local suspect = nil
		for _, pod in Investigation.PODS do
			if pod.Suspect then
				suspect = pod
			end
		end
		Expect.truthy(suspect, "le rapport accuse un programme")
		Expect.equal(Investigation.Quarantine(state, suspect.Id), "Innocent", "le suspect n'est pas le coupable")
		-- Remonter la chaîne
		local id = suspect.Id
		local revealed = false
		for _ = 1, 6 do
			local pod, reveal = Investigation.Inspect(state, id)
			revealed = revealed or reveal
			if not pod or not pod.Parent then
				break
			end
			id = pod.Parent
		end
		Expect.truthy(revealed and state.Revealed, "processus masqué révélé")
		Expect.equal(id, "lagz")
		Expect.equal(Investigation.Quarantine(state, "lagz"), "Ok")
		Expect.truthy(state.Quarantined)
		Expect.equal(Investigation.Quarantine(state, "music"), "Innocent")
	end,
}
