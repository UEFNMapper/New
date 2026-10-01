-- Mini-jeux « Tri des fichiers » (monde 5) et « Défense du CPU » (arcade) : logique PURE.
-- Des joueurs simulés jouent des parties complètes : un bon joueur gagne à toutes les difficultés,
-- un joueur qui ne fait rien (ou qui joue au hasard) perd, une même graine donne la même partie.
local Core = Shim.load("src/client/UI/Minigames/Core.luau")
local TriLogic = Shim.load("src/client/UI/Minigames/TriLogic.luau")
local DefenseLogic = Shim.load("src/client/UI/Minigames/DefenseLogic.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")
local GameConfig = Shim.load("src/shared/Config/GameConfig.luau")

local DT = 1 / 60
local SEEDS = { 1, 7, 42, 1234, 99991, 314159, 2718281, 55555 }
local MAX_TIME = 180

------------------------------------------------------------------------------------
-- Joueurs simulés
------------------------------------------------------------------------------------

-- Tri : range chaque fichier `reaction` s après son arrivée. Modes : "perfect" (bon bac),
-- "random" (bac au hasard), "trash" (tout à la corbeille), "idle" (rien).
local function playTri(level: number, seed: number, reaction: number, mode: string): any
	local sim = TriLogic.new(level, seed)
	local rng = Core.Rng(seed + 17)
	local sortAt = math.huge
	local spawns = {}
	while not sim.Done and sim.Time < MAX_TIME do
		for _, event in TriLogic.Step(sim, DT) do
			if event.Kind == "Spawn" then
				sortAt = sim.Time + reaction
				table.insert(spawns, event.File.Kind)
			end
		end
		if sim.Current and sim.Time >= sortAt and mode ~= "idle" then
			sortAt = math.huge
			local bin = if mode == "perfect"
				then sim.Current.Kind
				elseif mode == "trash" then "Trash"
				else TriLogic.BINS[rng:Int(1, 3)]
			TriLogic.Sort(sim, bin)
		end
	end
	sim.SpawnKinds = spawns
	return sim
end

-- Défense : "smart" construit dès qu'il peut, d'abord sur un bus sans antivirus, puis sur le bus
-- le plus chargé ; "oneLane" ne défend que le bus 1 ; "idle" ne construit rien.
local function playDefense(level: number, seed: number, strategy: string, think: number?): any
	local sim = DefenseLogic.new(level, seed)
	local nextMove = 0
	local delay = think or 0.6
	while not sim.Done and sim.Time < MAX_TIME do
		DefenseLogic.Step(sim, DT)
		if strategy ~= "idle" and sim.Time >= nextMove and sim.Energy >= sim.Params.Cost then
			nextMove = sim.Time + delay
			local best, bestScore = nil, -math.huge
			for lane = 1, DefenseLogic.LANES do
				if strategy == "oneLane" and lane ~= 1 then
					continue
				end
				local turrets, threats = 0, 0
				for slot in sim.Turrets do
					if DefenseLogic.SlotLane(slot) == lane then
						turrets += 1
					end
				end
				for _, virus in sim.Viruses do
					if virus.Lane == lane then
						threats += virus.Hp
					end
				end
				local score = threats - turrets * 3 + (if turrets == 0 then 10 else 0)
				if score > bestScore then
					for _, column in { 2, 1, 3, 4 } do
						local slot = (lane - 1) * DefenseLogic.COLUMNS + column
						if not sim.Turrets[slot] then
							best, bestScore = slot, score
							break
						end
					end
				end
			end
			if best then
				DefenseLogic.Build(sim, best)
			end
		end
	end
	return sim
end

local function triReaction(level: number): number
	return Core.Lerp(1.6, 1.1, (level - 1) / 6)
end

return {
	["tri : réglages cohérents de 1 à 7"] = function()
		local previous = nil
		for level = 1, 7 do
			local p = TriLogic.Params(level)
			if previous then
				Expect.truthy(p.Lifetime <= previous.Lifetime, "le tapis accélère")
				Expect.truthy(p.Target >= previous.Target, "plus de fichiers")
				Expect.truthy(p.VirusChance >= previous.VirusChance, "plus de programmes déguisés")
			end
			Expect.truthy(p.Lifetime > triReaction(level) + 0.6, "on a le temps de lire")
			Expect.truthy(p.Target * (triReaction(level) + p.Gap) < p.Duration * 0.8, "temps suffisant")
			previous = p
		end
		Expect.equal(TriLogic.Params(1).Hints, true, "indices au début")
		Expect.equal(TriLogic.Params(7).Hints, false, "plus d'indices à la fin")
		Expect.equal(TriLogic.Params(8), TriLogic.Params(7))
	end,

	["tri : un bon joueur gagne partout, un enfant lent gagne aux premiers niveaux"] = function()
		for level = 1, 8 do
			for _, seed in SEEDS do
				local sim = playTri(level, seed, triReaction(level), "perfect")
				Expect.truthy(sim.Success, `bon joueur niveau {level} graine {seed}`)
				Expect.equal(sim.Lives, sim.Params.Lives, "aucune vie perdue")
				Expect.between(sim.Time, 8, sim.Params.Duration)
			end
		end
		for level = 1, 3 do
			for _, seed in SEEDS do
				Expect.truthy(playTri(level, seed, 2.3, "perfect").Success, `enfant lent niveau {level}`)
			end
		end
	end,

	["tri : ne rien faire, jouer au hasard ou tout jeter fait perdre"] = function()
		for level = 1, 7 do
			local randomWins = 0
			for _, seed in SEEDS do
				local idle = playTri(level, seed, 1, "idle")
				Expect.equal(idle.Success, false, "inactif")
				Expect.equal(idle.Sorted, 0)
				Expect.equal(playTri(level, seed, 1, "trash").Success, false, "tout à la corbeille")
				if playTri(level, seed, 1, "random").Success then
					randomWins += 1
				end
			end
			Expect.equal(randomWins, 0, `hasard au niveau {level}`)
		end
	end,

	["tri : jamais trois fois le même bac de suite, déterministe, programme gardé = 2 vies"] = function()
		for _, seed in SEEDS do
			local sim = playTri(5, seed, 1.2, "perfect")
			local kinds = sim.SpawnKinds
			for i = 3, #kinds do
				Expect.truthy(not (kinds[i] == kinds[i - 1] and kinds[i] == kinds[i - 2]), "trois de suite")
			end
			local again = playTri(5, seed, 1.2, "perfect")
			Expect.equal(table.concat(again.SpawnKinds, ","), table.concat(kinds, ","), "même graine, même partie")
		end
		-- Un programme déguisé rangé dans « Garder »
		local sim = TriLogic.new(1, 3)
		local guard = 0
		while guard < 20000 do
			guard += 1
			TriLogic.Step(sim, DT)
			if sim.Current and sim.Current.Kind == "Quarantine" then
				break
			elseif sim.Current then
				TriLogic.Sort(sim, sim.Current.Kind)
			end
		end
		Expect.truthy(sim.Current and sim.Current.Kind == "Quarantine", "un programme déguisé arrive")
		local before = sim.Lives
		local events = TriLogic.Sort(sim, "Keep")
		Expect.equal(sim.Lives, before - TriLogic.VIRUS_KEPT_PENALTY)
		Expect.equal(events[1].Ok, false)
		Expect.equal(events[1].Penalty, TriLogic.VIRUS_KEPT_PENALTY)
		-- Fichiers : noms uniques, aucun nom de marque (brand.spec vérifie les mots interdits)
		local seen = {}
		for _, bin in TriLogic.BINS do
			for _, file in TriLogic.FILES[bin] do
				Expect.equal(seen[file.Name], nil, file.Name)
				seen[file.Name] = true
			end
			Expect.truthy(#TriLogic.WHY[bin] > 10, "explication")
		end
	end,

	["défense : réglages cohérents de 1 à 7"] = function()
		local previous = nil
		for level = 1, 7 do
			local p = DefenseLogic.Params(level)
			if previous then
				Expect.truthy(p.SpawnEvery <= previous.SpawnEvery, "virus plus fréquents")
				Expect.truthy(p.Speed >= previous.Speed, "plus rapides")
				Expect.truthy(p.Target >= previous.Target, "plus de virus à éliminer")
			end
			Expect.truthy(p.StartEnergy >= p.Cost * 2, "deux antivirus dès le départ")
			previous = p
		end
		Expect.equal(DefenseLogic.Params(8), DefenseLogic.Params(7))
		-- Emplacements : 3 bus × 4 colonnes, tous dans le terrain, devant le processeur
		for slot = 1, DefenseLogic.LANES * DefenseLogic.COLUMNS do
			local x, y = DefenseLogic.SlotPosition(slot)
			Expect.truthy(x > DefenseLogic.LEAK_X + 40 and x < Core.FIELD_W - 100, "x de l'emplacement")
			Expect.truthy(y > 40 and y < Core.FIELD_H - 40, "y de l'emplacement")
		end
	end,

	["défense : un bon stratège gagne partout ; ne rien faire ou un seul bus fait perdre"] = function()
		for level = 1, 8 do
			local oneLaneWins = 0
			for _, seed in SEEDS do
				local smart = playDefense(level, seed, "smart")
				Expect.truthy(smart.Success, `stratège niveau {level} graine {seed} (fuites {smart.Leaks})`)
				Expect.between(smart.Time, 15, smart.Params.Duration)
				local idle = playDefense(level, seed, "idle")
				Expect.equal(idle.Success, false, "inactif")
				Expect.equal(idle.Kills, 0)
				if playDefense(level, seed, "oneLane").Success then
					oneLaneWins += 1
				end
			end
			Expect.equal(oneLaneWins, 0, `un seul bus au niveau {level}`)
		end
	end,

	["défense : énergie, emplacement occupé, déterminisme"] = function()
		local sim = DefenseLogic.new(1, 42)
		local cost = sim.Params.Cost
		local start = sim.Energy
		Expect.equal(DefenseLogic.Build(sim, 1)[1].Kind, "Build")
		Expect.equal(sim.Energy, start - cost)
		Expect.equal(DefenseLogic.Build(sim, 1)[1].Kind, "Occupied")
		Expect.equal(DefenseLogic.Build(sim, 2)[1].Kind, "Build")
		Expect.equal(DefenseLogic.Build(sim, 3)[1].Kind, "NoEnergy")
		Expect.equal(#DefenseLogic.Build(sim, 99), 0, "emplacement invalide")
		local a = playDefense(4, 1234, "smart")
		local b = playDefense(4, 1234, "smart")
		Expect.equal(a.Time, b.Time)
		Expect.equal(a.Leaks, b.Leaks)
	end,

	["config : Tri au monde 5, Défense à l'arcade, durées minimales sous les victoires les plus rapides"] = function()
		Expect.equal(Tower.Worlds[5].Minigame, "Tri")
		Expect.truthy(table.find(Tower.MinigameKinds, "Tri") ~= nil)
		Expect.truthy(table.find(Tower.MinigameKinds, "Defense") ~= nil)
		local MinSeconds = GameConfig.Minigame.MinSeconds
		local triFast, defenseFast = math.huge, math.huge
		for level = 1, 8 do
			for _, seed in SEEDS do
				local tri = playTri(level, seed, 0.05, "perfect")
				if tri.Success then
					triFast = math.min(triFast, tri.Time)
				end
				local defense = playDefense(level, seed, "smart", 0)
				if defense.Success then
					defenseFast = math.min(defenseFast, defense.Time)
				end
			end
		end
		print(string.format("    plus rapides : tri %.1fs, défense %.1fs", triFast, defenseFast))
		Expect.truthy(MinSeconds.Tri < triFast, `Tri : {MinSeconds.Tri} < {triFast}`)
		Expect.truthy(MinSeconds.Defense < defenseFast, `Defense : {MinSeconds.Defense} < {defenseFast}`)
		Expect.truthy(MinSeconds.Tri >= 3 and MinSeconds.Defense >= 8, "durées minimales utiles")
	end,

	["(stats) tri et défense"] = function()
		for level = 1, 7 do
			local tT, dT, dLeaks = 0, 0, 0
			for _, seed in SEEDS do
				tT += playTri(level, seed, triReaction(level), "perfect").Time
				local d = playDefense(level, seed, "smart")
				dT += d.Time
				dLeaks += d.Leaks
			end
			print(
				string.format(
					"  niv %d : tri %.1fs  défense %.1fs (fuites %.1f)",
					level,
					tT / #SEEDS,
					dT / #SEEDS,
					dLeaks / #SEEDS
				)
			)
		end
	end,
}
