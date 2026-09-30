-- Tests de la logique PURE des mini-jeux antivirus (src/client/UI/Minigames/*Logic.luau).
-- Des "joueurs simulés" jouent des parties complètes : un bon joueur doit gagner à toutes
-- les difficultés, un joueur qui ne fait rien doit perdre, et une même graine doit
-- toujours donner la même partie.
local Core = Shim.load("src/client/UI/Minigames/Core.luau")
local ScanLogic = Shim.load("src/client/UI/Minigames/ScanLogic.luau")
local FirewallLogic = Shim.load("src/client/UI/Minigames/FirewallLogic.luau")
local MemoryLogic = Shim.load("src/client/UI/Minigames/MemoryLogic.luau")
local DodgeLogic = Shim.load("src/client/UI/Minigames/DodgeLogic.luau")

local DT = 1 / 60
local SEEDS = { 1, 7, 42, 1234, 99991, 314159, 2718281, 55555 }
local MAX_TIME = 180 -- garde-fou des boucles de simulation

------------------------------------------------------------------------------------
-- Joueurs simulés
------------------------------------------------------------------------------------

-- Scan : touche chaque virus `reaction` secondes après son apparition (s'il est encore là).
-- `tapFiles` : touche aussi les fichiers (mauvais joueur).
local function playScan(level: number, seed: number, reaction: number?, tapFiles: boolean?)
	local state = ScanLogic.new(level, seed)
	local planned: { { At: number, Cell: number, Id: number } } = {}
	local log = {}
	while not state.Done and state.Time < MAX_TIME do
		for _, event in ScanLogic.Step(state, DT) do
			table.insert(log, `{event.Kind}:{event.Cell}`)
			if
				reaction
				and event.Kind == "Spawn"
				and (event.What == "Virus" or tapFiles)
				and reaction < (event.Life :: number)
			then
				table.insert(planned, { At = state.Time + reaction, Cell = event.Cell, Id = event.Id :: number })
			end
		end
		for i = #planned, 1, -1 do
			local tap = planned[i]
			if state.Time >= tap.At then
				table.remove(planned, i)
				if state.Cells[tap.Cell].Id == tap.Id then
					ScanLogic.Tap(state, tap.Cell)
				end
			end
		end
	end
	return state, table.concat(log, ",")
end

-- Firewall : vise le virus le plus bas au clavier (ou reste immobile si `idle`).
local function playFirewall(level: number, seed: number, idle: boolean?)
	local state = FirewallLogic.new(level, seed)
	local log = {}
	while not state.Done and state.Time < MAX_TIME do
		if not idle then
			local target: any = nil
			for _, virus in state.Viruses do
				if not target or virus.Y > target.Y then
					target = virus
				end
			end
			local axis = 0
			if target and math.abs(target.X - state.ShieldX) > 8 then
				axis = if target.X > state.ShieldX then 1 else -1
			end
			FirewallLogic.SetAxis(state, axis)
		end
		for _, event in FirewallLogic.Step(state, DT) do
			if event.Kind ~= "Fire" and event.Kind ~= "BulletGone" then
				table.insert(log, `{event.Kind}:{event.Id}`)
			end
		end
	end
	return state, table.concat(log, ",")
end

-- Memory : joueur à mémoire parfaite qui IGNORE l'aperçu (hypothèse prudente) ;
-- `forget` = probabilité d'oublier une carte vue. Une action toutes les `think` secondes.
local function playMemory(level: number, seed: number, forget: number?, think: number?)
	local state = MemoryLogic.new(level, seed)
	local brain = Core.Rng(seed + 17)
	local seen: { [number]: number } = {} -- index -> symbole
	local delay = think or 0.55
	local nextAction = 0
	local clock = 0
	local function remember(index: number)
		if brain:Next() >= (forget or 0) then
			seen[index] = state.Cards[index].Symbol
		end
	end
	local function unknownDown(except: number?): number?
		local choices = {}
		for index, card in state.Cards do
			if card.Face == "Down" and seen[index] == nil and index ~= except then
				table.insert(choices, index)
			end
		end
		if #choices == 0 then
			for index, card in state.Cards do
				if card.Face == "Down" and index ~= except then
					table.insert(choices, index)
				end
			end
		end
		return if #choices > 0 then choices[brain:Int(1, #choices)] else nil
	end
	local function knownPartner(index: number): number?
		local symbol = state.Cards[index].Symbol
		for other, s in seen do
			if other ~= index and s == symbol and state.Cards[other].Face ~= "Matched" then
				return other
			end
		end
		return nil
	end
	local function flip(index: number)
		for _, event in MemoryLogic.Flip(state, index) do
			if event.Kind == "Flip" then
				remember(event.Cards[1])
			end
		end
	end
	while not state.Done and clock < MAX_TIME do
		clock += DT
		MemoryLogic.Step(state, DT)
		if state.Phase == "Play" and not state.Done and clock >= nextAction then
			nextAction = clock + delay
			local first = state.First
			if first then
				local partner = knownPartner(first)
				flip(partner or unknownDown(first) or first)
			else
				-- Une paire déjà connue ? Sinon, une carte inconnue.
				local pairIndex: number? = nil
				for index, symbol in seen do
					local card = state.Cards[index]
					if card.Face == "Down" then
						for other, s in seen do
							if other ~= index and s == symbol and state.Cards[other].Face == "Down" then
								pairIndex = index
							end
						end
					end
				end
				local pick = pairIndex or unknownDown(nil)
				if pick then
					flip(pick)
				end
			end
		end
	end
	return state
end

-- Dodge : vise le centre du trou du prochain mur. `stopAfter` : arrête d'appuyer.
local function playDodge(level: number, seed: number, stopAfter: number?)
	local state = DodgeLogic.new(level, seed)
	DodgeLogic.Flap(state)
	local cooldown = 0
	local log = {}
	while not state.Done and state.Time < MAX_TIME do
		cooldown -= DT
		local wall = DodgeLogic.NextWall(state)
		local targetY = if wall then wall.GapY else Core.FIELD_H / 2
		if
			(not stopAfter or state.Time < stopAfter)
			and state.Y > targetY + 14
			and state.Vy > -40
			and cooldown <= 0
		then
			DodgeLogic.Flap(state)
			cooldown = 0.12
		end
		for _, event in DodgeLogic.Step(state, DT) do
			table.insert(log, `{event.Kind}:{event.Wall or 0}`)
		end
	end
	return state, table.concat(log, ",")
end

------------------------------------------------------------------------------------
-- Vérifications génériques des tables de réglages
------------------------------------------------------------------------------------

-- `field` doit évoluer dans le sens `direction` (+1 croissant, -1 décroissant) de 1 à 7.
local function monotonic(getParams: (number) -> any, field: string, direction: number)
	for level = 2, 7 do
		local before = getParams(level - 1)[field]
		local now = getParams(level)[field]
		Expect.truthy(
			(now - before) * direction >= 0,
			`{field} doit {if direction > 0 then "croître" else "décroître"} (niveau {level - 1} -> {level})`
		)
	end
	Expect.truthy((getParams(7)[field] - getParams(1)[field]) * direction > 0, `{field} doit changer entre 1 et 7`)
end

return {
	["core : difficulté bornée et arrondie"] = function()
		Expect.equal(Core.Level(1), 1)
		Expect.equal(Core.Level(7), 7)
		Expect.equal(Core.Level(0), 1)
		Expect.equal(Core.Level(-5), 1)
		Expect.equal(Core.Level(12), 7)
		Expect.equal(Core.Level(3.6), 4)
		Expect.equal(Core.Level(0 / 0), 1, "NaN")
		Expect.equal(Core.Level(nil), 1)
		Expect.equal(Core.DisplaySeconds(4.2), 5)
		Expect.equal(Core.DisplaySeconds(5), 5)
		Expect.equal(Core.DisplaySeconds(-1), 0)
	end,

	["core : générateur déterministe et bien réparti"] = function()
		local a, b = Core.Rng(42), Core.Rng(42)
		for _ = 1, 200 do
			Expect.equal(a:Next(), b:Next(), "même graine")
		end
		local c, d = Core.Rng(42), Core.Rng(43)
		local same = 0
		for _ = 1, 50 do
			if c:Next() == d:Next() then
				same += 1
			end
		end
		Expect.truthy(same < 3, "deux graines voisines divergent")
		local rng = Core.Rng(7)
		local counts = { 0, 0, 0, 0, 0, 0 }
		local sum = 0
		for _ = 1, 6000 do
			local v = rng:Next()
			Expect.between(v, 0, 0.9999999999)
			sum += v
			local n = rng:Int(1, 6)
			counts[n] += 1
		end
		Expect.near(sum / 6000, 0.5, 0.03, "moyenne")
		for face = 1, 6 do
			Expect.between(counts[face], 850, 1150, `face {face}`)
		end
		Expect.equal(rng:Int(3, 3), 3)
		local list = { 1, 2, 3, 4, 5, 6, 7, 8 }
		rng:Shuffle(list)
		table.sort(list)
		Expect.equal(table.concat(list, ","), "1,2,3,4,5,6,7,8", "le mélange garde tous les éléments")
	end,

	["scan : réglages cohérents de 1 à 7"] = function()
		monotonic(ScanLogic.Params, "Lifetime", -1)
		monotonic(ScanLogic.Params, "SpawnEvery", -1)
		monotonic(ScanLogic.Params, "Target", 1)
		monotonic(ScanLogic.Params, "FileChance", 1)
		for level = 1, 7 do
			local p = ScanLogic.Params(level)
			Expect.between(p.Cols * p.Rows, 9, 16, "grille 3x3 à 4x4")
			Expect.between(p.Duration, 20, 40, "durée")
			-- Assez de virus pour atteindre l'objectif avec de la marge.
			local expected = p.Duration / p.SpawnEvery * (1 - p.FileChance)
			Expect.truthy(expected >= p.Target * 1.5, `niveau {level} : trop peu de virus ({expected})`)
		end
		Expect.equal(ScanLogic.Params(0).Target, ScanLogic.Params(1).Target, "difficulté bornée")
	end,

	["scan : un bon joueur gagne, un joueur absent perd"] = function()
		for level = 1, 7 do
			-- Réflexes d'un enfant au niveau 1, d'un joueur vif au niveau 7.
			local reaction = Core.Lerp(0.95, 0.5, (level - 1) / 6)
			for _, seed in SEEDS do
				local state = playScan(level, seed, reaction)
				Expect.truthy(
					state.Success,
					`niveau {level} graine {seed} : perdu ({state.Hits}/{state.Params.Target})`
				)
				Expect.between(state.Time, 12, state.Params.Duration, `niveau {level} : durée`)
				local idle = playScan(level, seed, nil)
				Expect.truthy(idle.Done and not idle.Success, "sans rien toucher on perd")
				Expect.equal(idle.Hits, 0)
				Expect.near(idle.Time, idle.Params.Duration, 0.05, "fin au chrono")
			end
		end
	end,

	["scan : toucher un fichier coûte un point"] = function()
		local state = ScanLogic.new(7, 3)
		local sawFile = false
		while not state.Done and not sawFile do
			for _, event in ScanLogic.Step(state, DT) do
				if event.Kind == "Spawn" and event.What == "Virus" then
					ScanLogic.Tap(state, event.Cell)
				elseif event.Kind == "Spawn" and event.What == "File" and state.Hits > 0 then
					local before = state.Hits
					local result = ScanLogic.Tap(state, event.Cell)
					Expect.equal(result[1].Kind, "Oops")
					Expect.equal(state.Hits, before - 1)
					Expect.equal(state.Combo, 0)
					sawFile = true
				end
			end
		end
		Expect.truthy(sawFile, "un fichier doit apparaître au niveau 7")
		-- Toucher une case vide ne fait rien.
		local fresh = ScanLogic.new(1, 3)
		Expect.equal(#ScanLogic.Tap(fresh, 1), 0)
		Expect.equal(#ScanLogic.Tap(fresh, 99), 0)
	end,

	["scan : jamais plus d'objets que MaxAlive, premières apparitions sûres"] = function()
		for level = 1, 7 do
			local state = ScanLogic.new(level, 5)
			local spawns = 0
			while not state.Done do
				for _, event in ScanLogic.Step(state, DT) do
					if event.Kind == "Spawn" then
						spawns += 1
						if spawns <= ScanLogic.SAFE_SPAWNS then
							Expect.equal(event.What, "Virus", "premières apparitions")
						end
					end
				end
				Expect.truthy(ScanLogic.Alive(state) <= state.Params.MaxAlive, "MaxAlive")
			end
		end
	end,

	["scan : même graine = même partie"] = function()
		local _, a = playScan(4, 777, 0.6)
		local _, b = playScan(4, 777, 0.6)
		local _, c = playScan(4, 778, 0.6)
		Expect.equal(a, b, "déterminisme")
		Expect.truthy(a ~= c, "graines différentes -> parties différentes")
	end,

	["firewall : réglages cohérents de 1 à 7"] = function()
		monotonic(FirewallLogic.Params, "FallSpeed", 1)
		monotonic(FirewallLogic.Params, "SpawnEvery", -1)
		monotonic(FirewallLogic.Params, "Target", 1)
		monotonic(FirewallLogic.Params, "Lives", -1)
		for level = 1, 7 do
			local p = FirewallLogic.Params(level)
			Expect.truthy(p.Radius * 2 >= 44, "cibles assez grosses")
			Expect.truthy(p.Duration / p.SpawnEvery >= p.Target * 1.5, `niveau {level} : trop peu de virus`)
		end
	end,

	["firewall : un bon joueur gagne, un joueur immobile perd"] = function()
		for level = 1, 7 do
			for _, seed in SEEDS do
				local state = playFirewall(level, seed)
				Expect.truthy(
					state.Success,
					`niveau {level} graine {seed} : perdu ({state.Kills}/{state.Params.Target}, fuites {state.Leaks})`
				)
				Expect.between(state.Time, 10, state.Params.Duration, `niveau {level} : durée`)
			end
		end
		for level = 3, 7 do
			local lost = 0
			for _, seed in SEEDS do
				local state = playFirewall(level, seed, true)
				if not state.Success then
					lost += 1
				end
			end
			Expect.equal(lost, #SEEDS, `niveau {level} : rester immobile ne suffit pas`)
		end
	end,

	["firewall : bouclier borné, tirs et fuites"] = function()
		local state = FirewallLogic.new(1, 9)
		FirewallLogic.SetAxis(state, -1)
		for _ = 1, 120 do
			FirewallLogic.Step(state, DT)
		end
		Expect.equal(state.ShieldX, FirewallLogic.SHIELD_HALF_W, "bord gauche")
		FirewallLogic.SetPointer(state, 5000)
		Expect.equal(state.Pointer, Core.FIELD_W)
		for _ = 1, 120 do
			FirewallLogic.Step(state, DT)
		end
		Expect.equal(state.ShieldX, Core.FIELD_W - FirewallLogic.SHIELD_HALF_W, "bord droit")
		FirewallLogic.SetAxis(state, 1)
		Expect.equal(state.Pointer, nil, "le clavier reprend la main")
		Expect.truthy(#state.Bullets > 0 or state.Kills > 0, "tir automatique")
		-- Immobile : les virus finissent par fuir, une vie à la fois.
		local idle = playFirewall(7, 11, true)
		Expect.truthy(idle.Leaks >= idle.Params.Lives, "défaite par fuites")
		Expect.equal(FirewallLogic.LivesLeft(idle), 0)
	end,

	["firewall : même graine = même partie"] = function()
		local _, a = playFirewall(5, 2024)
		local _, b = playFirewall(5, 2024)
		local _, c = playFirewall(5, 2025)
		Expect.equal(a, b, "déterminisme")
		Expect.truthy(a ~= c, "graines différentes -> parties différentes")
	end,

	["memory : réglages et paquet de cartes"] = function()
		monotonic(MemoryLogic.Params, "Preview", -1)
		monotonic(MemoryLogic.Params, "MissShow", -1)
		for level = 1, 7 do
			local p = MemoryLogic.Params(level)
			Expect.equal((p.Cols * p.Rows) % 2, 0, "nombre de cartes pair")
			Expect.truthy(p.Cols * p.Rows / 2 <= MemoryLogic.SYMBOLS, "assez d'icônes")
			if level > 1 then
				local before = MemoryLogic.Params(level - 1)
				Expect.truthy(p.Cols * p.Rows >= before.Cols * before.Rows, "la grille grandit")
			end
			local state = MemoryLogic.new(level, level * 13)
			local count: { [number]: number } = {}
			for _, card in state.Cards do
				count[card.Symbol] = (count[card.Symbol] or 0) + 1
				Expect.equal(card.Face, "Up", "aperçu : cartes visibles")
			end
			local pairs = 0
			for _, n in count do
				Expect.equal(n, 2, "chaque icône en double")
				pairs += 1
			end
			Expect.equal(pairs, state.Pairs)
		end
		Expect.truthy(MemoryLogic.Params(7).Cols * MemoryLogic.Params(7).Rows > 12, "grille plus grande au 7")
	end,

	["memory : aperçu, paire, erreur, recache"] = function()
		local state = MemoryLogic.new(1, 21)
		Expect.equal(#MemoryLogic.Flip(state, 1), 0, "pas de clic pendant l'aperçu")
		local hidden = false
		while state.Phase == "Preview" do
			for _, event in MemoryLogic.Step(state, DT) do
				if event.Kind == "Hide" then
					hidden = #event.Cards == #state.Cards
				end
			end
		end
		Expect.truthy(hidden, "fin d'aperçu : tout se recache")
		-- Trouve une paire et une non-paire.
		local a, b, c = 1, nil :: number?, nil :: number?
		for index = 2, #state.Cards do
			if state.Cards[index].Symbol == state.Cards[a].Symbol then
				b = index
			elseif not c then
				c = index
			end
		end
		assert(b and c)
		MemoryLogic.Flip(state, a)
		Expect.equal(#MemoryLogic.Flip(state, a), 0, "retourner deux fois la même carte ne fait rien")
		local events = MemoryLogic.Flip(state, b)
		Expect.equal(events[#events].Kind, "Match")
		Expect.equal(state.Found, 1)
		-- Erreur : c + une carte d'une autre paire
		MemoryLogic.Flip(state, c)
		local d: number? = nil
		for index, card in state.Cards do
			if card.Face == "Down" and card.Symbol ~= state.Cards[c].Symbol then
				d = index
				break
			end
		end
		assert(d)
		events = MemoryLogic.Flip(state, d)
		Expect.equal(events[#events].Kind, "Miss")
		Expect.equal(MemoryLogic.LivesLeft(state), state.Params.Lives - 1)
		-- La mauvaise paire se recache toute seule…
		for _ = 1, math.ceil(state.Params.MissShow / DT) + 2 do
			MemoryLogic.Step(state, DT)
		end
		Expect.equal(state.Cards[c].Face, "Down")
		Expect.equal(state.Cards[d].Face, "Down")
		-- … ou tout de suite si on touche une 3e carte.
		MemoryLogic.Flip(state, c)
		MemoryLogic.Flip(state, d)
		events = MemoryLogic.Flip(state, a)
		Expect.equal(events[1].Kind, "Hide", "3e carte : la paire se recache d'abord")
	end,

	["memory : mémoire parfaite gagne, hasard pur perd aux niveaux durs"] = function()
		for level = 1, 7 do
			for _, seed in SEEDS do
				local state = playMemory(level, seed, 0, 0.55)
				Expect.truthy(
					state.Success,
					`niveau {level} graine {seed} : perdu ({state.Found}/{state.Pairs}, erreurs {state.Misses})`
				)
			end
		end
		for level = 5, 7 do
			local lost = 0
			for _, seed in SEEDS do
				if not playMemory(level, seed, 1, 0.55).Success then
					lost += 1
				end
			end
			Expect.truthy(lost >= #SEEDS - 1, `niveau {level} : jouer au hasard ne suffit pas ({lost})`)
		end
	end,

	["memory : chrono et vies"] = function()
		local state = MemoryLogic.new(3, 5)
		while not state.Done do
			MemoryLogic.Step(state, DT)
		end
		Expect.truthy(not state.Success, "sans jouer : perdu au chrono")
		Expect.near(state.Time, state.Params.Duration, 0.05)
	end,

	["memory : même graine = même paquet"] = function()
		local function deck(seed: number): string
			local parts = {}
			for _, card in MemoryLogic.new(6, seed).Cards do
				table.insert(parts, tostring(card.Symbol))
			end
			return table.concat(parts, ",")
		end
		Expect.equal(deck(123), deck(123))
		Expect.truthy(deck(123) ~= deck(124))
	end,

	["dodge : réglages cohérents de 1 à 7"] = function()
		monotonic(DodgeLogic.Params, "Speed", 1)
		monotonic(DodgeLogic.Params, "Gap", -1)
		monotonic(DodgeLogic.Params, "Spacing", -1)
		monotonic(DodgeLogic.Params, "Walls", 1)
		monotonic(DodgeLogic.Params, "Lives", -1)
		for level = 1, 7 do
			local state = DodgeLogic.new(level, 1)
			local seconds = DodgeLogic.TimeLeft(state)
			Expect.between(seconds, 18, 40, `niveau {level} : durée de parcours`)
			-- Le trou est toujours bien plus grand que le paquet.
			Expect.truthy(state.Params.Gap >= DodgeLogic.HIT_RADIUS * 2 * 4, "trou large")
			for i, wall in state.Walls do
				Expect.between(wall.GapY - state.Params.Gap / 2, DodgeLogic.MARGIN - 0.01, Core.FIELD_H)
				Expect.between(wall.GapY + state.Params.Gap / 2, 0, Core.FIELD_H - DodgeLogic.MARGIN + 0.01)
				if i > 1 then
					Expect.truthy(
						math.abs(wall.GapY - state.Walls[i - 1].GapY) <= state.Params.MaxShift + 1e-6,
						"écart entre trous"
					)
				end
			end
		end
	end,

	["dodge : rien ne bouge avant le premier appui"] = function()
		local state = DodgeLogic.new(1, 3)
		for _ = 1, 300 do
			DodgeLogic.Step(state, DT)
		end
		Expect.equal(state.Distance, DodgeLogic.PACKET_X)
		Expect.equal(state.Y, Core.FIELD_H / 2)
		local events = DodgeLogic.Flap(state)
		Expect.equal(events[1].Kind, "Start")
		Expect.truthy(state.Vy < 0, "l'appui fait monter")
	end,

	["dodge : un bon joueur gagne sans se cogner, un joueur passif perd"] = function()
		for level = 1, 7 do
			for _, seed in SEEDS do
				local state = playDodge(level, seed)
				Expect.truthy(state.Success, `niveau {level} graine {seed} : perdu (chocs {state.Hits})`)
				Expect.equal(state.Hits, 0, `niveau {level} graine {seed} : chocs`)
				Expect.equal(state.Passed, state.Params.Walls, "tous les murs passés")
				Expect.near(DodgeLogic.Progress(state), 1, 1e-9)
			end
		end
		for level = 1, 7 do
			for _, seed in SEEDS do
				local state = playDodge(level, seed, 0)
				Expect.truthy(state.Done and not state.Success, `niveau {level} : sans appuyer on perd`)
			end
		end
	end,

	["dodge : sol et plafond sans dégât, invincibilité après un choc"] = function()
		local state = DodgeLogic.new(1, 8)
		DodgeLogic.Flap(state)
		for _ = 1, 60 do
			DodgeLogic.Flap(state)
			DodgeLogic.Step(state, DT)
		end
		Expect.equal(state.Y, DodgeLogic.HIT_RADIUS, "plafond")
		Expect.equal(state.Hits, 0)
		local hits = 0
		while not state.Done do
			for _, event in DodgeLogic.Step(state, DT) do
				if event.Kind == "Hit" then
					hits += 1
					Expect.near(state.Invulnerable, DodgeLogic.INVULNERABLE, 1e-9)
				end
			end
		end
		Expect.equal(hits, state.Params.Lives, "une vie par choc")
	end,

	["dodge : même graine = même parcours"] = function()
		local _, a = playDodge(4, 4242)
		local _, b = playDodge(4, 4242)
		Expect.equal(a, b, "déterminisme")
		local w1, w2 = DodgeLogic.new(4, 1).Walls, DodgeLogic.new(4, 2).Walls
		local differs = false
		for i, wall in w1 do
			if wall.GapY ~= w2[i].GapY then
				differs = true
			end
		end
		Expect.truthy(differs, "graines différentes -> parcours différents")
	end,

	["(stats) durées et taux"] = function()
		for level = 1, 7 do
			local scanT, fwT, memT, dT, scanFast = 0, 0, 0, 0, math.huge
			local memWinsForget = 0
			for _, seed in SEEDS do
				scanT += playScan(level, seed, Core.Lerp(0.95, 0.5, (level - 1) / 6)).Time
				scanFast = math.min(scanFast, playScan(level, seed, 0.05).Time)
				fwT += playFirewall(level, seed).Time
				local m = playMemory(level, seed, 0, 0.8)
				memT += m.Time + m.Params.Preview
				if playMemory(level, seed, 0.35, 0.8).Success then
					memWinsForget += 1
				end
				dT += playDodge(level, seed).Time
			end
			local n = #SEEDS
			print(
				string.format(
					"  niv %d : scan %.1fs (min %.1fs)  firewall %.1fs  memory %.1fs (oublieux %d/%d)  dodge %.1fs",
					level,
					scanT / n,
					scanFast,
					fwT / n,
					memT / n,
					memWinsForget,
					n,
					dT / n
				)
			)
		end
	end,
}
