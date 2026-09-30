-- Tests de la logique PURE des mini-jeux antivirus (src/client/UI/Minigames/*Logic.luau).
-- Des "joueurs simulés" jouent des parties complètes : un bon joueur doit gagner à toutes
-- les difficultés, un joueur qui ne fait rien doit perdre, et une même graine doit
-- toujours donner la même partie.
local Core = Shim.load("src/client/UI/Minigames/Core.luau")
local ScanLogic = Shim.load("src/client/UI/Minigames/ScanLogic.luau")
local FirewallLogic = Shim.load("src/client/UI/Minigames/FirewallLogic.luau")
local MemoryLogic = Shim.load("src/client/UI/Minigames/MemoryLogic.luau")
local DodgeLogic = Shim.load("src/client/UI/Minigames/DodgeLogic.luau")
local PopupLogic = Shim.load("src/client/UI/Minigames/PopupLogic.luau")
local DefragLogic = Shim.load("src/client/UI/Minigames/DefragLogic.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")
local GameConfig = Shim.load("src/shared/Config/GameConfig.luau")

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
-- Combat final : vise LAGZ tant qu'aucun virus n'est menaçant (`danger` = hauteur d'alerte).
-- `sniper` (combat final) : ne vise QUE LAGZ (le plus rapide possible, pour MinSeconds).
local function playFirewall(level: number, seed: number, idle: boolean?, sniper: boolean?)
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
			local boss = state.Boss
			local aimX = if target then target.X else nil
			if boss and (sniper or not target or target.Y < 250) then
				aimX = boss.X
			end
			local axis = 0
			if aimX and math.abs(aimX - state.ShieldX) > 8 then
				axis = if aimX > state.ShieldX then 1 else -1
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

-- Pop-up Killer : une action toutes les `reaction` s sur la plus vieille pub dont le ✕ est
-- visible (vue depuis au moins `perceive` s). Modes : "close" (bon joueur), "decoy"
-- (touche les faux boutons quand il y en a), "exploit" (touche un faux bouton pour faire
-- venir les pubs plus vite tant que la RAM le permet : pour mesurer la victoire la plus
-- rapide possible). Sans `reaction` : joueur absent.
local function playPopup(level: number, seed: number, reaction: number?, mode: string?, perceive: number?)
	local state = PopupLogic.new(level, seed)
	local nextAction = 0
	local log = {}
	local see = perceive or 0.25
	local function press(x: number, y: number)
		for _, event in PopupLogic.PressAt(state, x, y) do
			table.insert(log, `{event.Kind}:{event.Id}:{math.floor(event.X or 0)}`)
		end
	end
	while not state.Done and state.Time < MAX_TIME do
		for _, event in PopupLogic.Step(state, DT) do
			table.insert(log, `{event.Kind}:{event.Id}:{math.floor(event.X or 0)}`)
		end
		if reaction and not state.Done and state.Time >= nextAction then
			local pick: any = nil
			for _, w in state.Windows do
				if w.Life >= see and not PopupLogic.Covered(state, w) and (not pick or w.Life > pick.Life) then
					pick = w
				end
			end
			if pick then
				nextAction = state.Time + reaction
				local useDecoy = #pick.Decoys > 0
					and (
						mode == "decoy"
						or (mode == "exploit" and state.Ram + state.Params.DecoyPenalty < 0.9 and pick.Life < 0.5)
					)
				if useDecoy then
					local r = PopupLogic.DecoyRects(pick)[1]
					press((r.X0 + r.X1) / 2, (r.Y0 + r.Y1) / 2)
				else
					press(PopupLogic.CloseCenter(pick))
				end
			end
		end
	end
	return state, table.concat(log, ",")
end

-- Défrag : `think` secondes par coup. "plan" (bon joueur : suit le meilleur plan calculé
-- au début), "random" (échanges au hasard). Sans `think` : joueur absent.
local function playDefrag(level: number, seed: number, think: number?, mode: string?)
	local state = DefragLogic.new(level, seed)
	local total = state.Params.Cols * state.Params.Rows
	local rng = Core.Rng(seed + 5)
	local plan: { { number } }? = nil
	local step = 0
	local nextAction = think or 0
	local log = {}
	local clock = 0
	while not state.Done and clock < MAX_TIME do
		clock += DT
		for _, event in DefragLogic.Step(state, DT) do
			table.insert(log, event.Kind)
		end
		if think and state.Phase == "Play" and not state.Done and clock >= DefragLogic.SCRAMBLE_TIME + nextAction then
			nextAction += think
			local a, b
			if mode == "random" then
				a, b = rng:Int(1, total), rng:Int(1, total)
			else
				plan = plan or DefragLogic.Plan(state)
				step += 1
				local swap = (plan :: any)[step]
				a, b = swap[1], swap[2]
			end
			for _, event in DefragLogic.Swap(state, a, b) do
				table.insert(log, `{event.Kind}:{table.concat(event.Cells, "-")}`)
			end
		end
	end
	return state, table.concat(log, ","), clock
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

	["core : combat final (difficulté 8)"] = function()
		Expect.truthy(Core.IsBoss(8), "8 = boss")
		Expect.truthy(Core.IsBoss(8.2), "arrondi")
		Expect.truthy(not Core.IsBoss(7), "7 = monde 7")
		Expect.truthy(not Core.IsBoss(9), "9 invalide")
		Expect.truthy(not Core.IsBoss(nil))
		Expect.truthy(not Core.IsBoss(0 / 0), "NaN")
		Expect.equal(Core.Level(8), 7, "les jeux sans variante jouent au niveau 7")
		-- Les jeux sans combat dédié gardent les réglages du niveau 7.
		Expect.equal(PopupLogic.Params(8), PopupLogic.Params(7))
		Expect.equal(DefragLogic.Params(8), DefragLogic.Params(7))
		Expect.equal(ScanLogic.Params(8), ScanLogic.Params(7))
	end,

	["config : Pop-up Killer et Défrag enregistrés"] = function()
		for _, kind in { "Scan", "Firewall", "Memory", "Dodge", "Popup", "Defrag" } do
			Expect.truthy(table.find(Tower.MinigameKinds, kind) ~= nil, `{kind} dans MinigameKinds`)
			Expect.truthy(GameConfig.Minigame.MinSeconds[kind] ~= nil, `MinSeconds de {kind}`)
		end
		Expect.equal(#Tower.MinigameKinds, 6)
		Expect.equal(Tower.Worlds[2].Minigame, "Popup")
		Expect.equal(Tower.Worlds[3].Minigame, "Defrag")
		Expect.equal(Tower.Worlds[7].Minigame, "Firewall", "le combat final est un Firewall")
	end,

	["config : MinSeconds sous la victoire la plus rapide possible"] = function()
		local MinSeconds = GameConfig.Minigame.MinSeconds
		local popupFast, defragFast, bossFast = math.huge, math.huge, math.huge
		for level = 1, 8 do
			for _, seed in SEEDS do
				-- Pop-up : fermeture instantanée, avec ou sans l'astuce des faux boutons.
				for _, mode in { "close", "exploit" } do
					local state = playPopup(level, seed, 0.05, mode, 0)
					if state.Success then
						popupFast = math.min(popupFast, state.Time)
					end
				end
				-- Défrag : le meilleur plan, un échange toutes les 0,3 s (glisser très vite).
				local defrag, _, clock = playDefrag(level, seed, 0.3, "plan")
				Expect.truthy(defrag.Success, `défrag rapide niveau {level} graine {seed}`)
				defragFast = math.min(defragFast, clock)
			end
		end
		for _, seed in SEEDS do
			for _, sniper in { false, true } do
				local state = playFirewall(8, seed, false, sniper)
				if state.Success then
					bossFast = math.min(bossFast, state.Time)
				end
			end
		end
		print(
			string.format(
				"    plus rapides : popup %.1fs, défrag %.1fs, boss LAGZ %.1fs",
				popupFast,
				defragFast,
				bossFast
			)
		)
		Expect.truthy(MinSeconds.Popup < popupFast, `Popup : {MinSeconds.Popup} < {popupFast}`)
		Expect.truthy(MinSeconds.Defrag < defragFast, `Defrag : {MinSeconds.Defrag} < {defragFast}`)
		Expect.truthy(MinSeconds.Firewall < bossFast, `Firewall (boss) : {MinSeconds.Firewall} < {bossFast}`)
		-- Une vérification qui sert à quelque chose : au moins quelques secondes.
		Expect.truthy(MinSeconds.Popup >= 3 and MinSeconds.Defrag >= 2.5, "durées minimales utiles")
	end,

	["popup : réglages cohérents de 1 à 7"] = function()
		monotonic(PopupLogic.Params, "SpawnEvery", -1)
		monotonic(PopupLogic.Params, "Target", 1)
		monotonic(PopupLogic.Params, "Load", 1)
		monotonic(PopupLogic.Params, "DecoyChance", 1)
		monotonic(PopupLogic.Params, "SplitAfter", -1)
		monotonic(PopupLogic.Params, "MoveChance", 1)
		-- Cibles tactiles : 72 unités ~ 44 px sur le plus petit téléphone.
		Expect.truthy(PopupLogic.CLOSE_SIZE >= 72, "✕ assez gros")
		Expect.truthy(PopupLogic.DECOY_H >= 44, "faux boutons assez gros")
		for level = 1, 7 do
			local p = PopupLogic.Params(level)
			Expect.truthy(p.W <= Core.FIELD_W / 2 and p.H <= PopupLogic.AREA_BOTTOM / 2 + 10, "fenêtre raisonnable")
			Expect.truthy(p.MaxOpen >= 5, "écran qui se remplit")
			-- Le ✕ et les faux boutons ne se chevauchent jamais, et restent dans la fenêtre.
			local w = {
				Id = 1,
				X = 450,
				Y = 220,
				W = p.W,
				H = p.H,
				Z = 1,
				Age = 0,
				Life = 0,
				CloseLeft = false,
				Decoys = { 1, 2 },
				Style = 1,
				Vx = 0,
				Vy = 0,
			}
			local box = PopupLogic.Bounds(w)
			for _, left in { false, true } do
				w.CloseLeft = left
				local close = PopupLogic.CloseRect(w)
				for _, r in PopupLogic.DecoyRects(w) do
					Expect.truthy(
						r.Y0 > close.Y1 or r.X1 < close.X0 or r.X0 > close.X1,
						"✕ séparé des faux boutons"
					)
					Expect.truthy(r.X0 >= box.X0 and r.X1 <= box.X1 and r.Y1 <= box.Y1, "faux bouton dans la fenêtre")
					Expect.truthy(r.X1 - r.X0 >= 72, "faux bouton assez large")
				end
			end
		end
	end,

	["popup : un bon joueur gagne, un joueur absent perd, les faux boutons coûtent cher"] = function()
		for level = 1, 8 do
			local reaction = Core.Lerp(0.6, 0.42, (math.min(level, 7) - 1) / 6)
			for _, seed in SEEDS do
				local state = playPopup(level, seed, reaction, "close")
				Expect.truthy(
					state.Success,
					`niveau {level} graine {seed} : perdu ({state.Closed}/{state.Params.Target}, RAM {state.Ram})`
				)
				Expect.between(state.Time, 8, 40, `niveau {level} : durée`)
				Expect.truthy(state.Ram < 1, "RAM jamais pleine")
				local idle = playPopup(level, seed, nil)
				Expect.truthy(idle.Done and not idle.Success, "sans rien toucher on perd")
				Expect.equal(idle.Closed, 0)
				Expect.equal(idle.Ram, 1, "perdu par la RAM pleine")
				Expect.truthy(#idle.Windows == idle.Params.MaxOpen, "l'écran s'est rempli")
			end
		end
		-- Un enfant plus lent gagne encore aux premiers mondes.
		for level = 1, 3 do
			for _, seed in SEEDS do
				Expect.truthy(playPopup(level, seed, 1.1, "close").Success, `enfant lent niveau {level}`)
			end
		end
		for level = 2, 7 do
			local lost = 0
			for _, seed in SEEDS do
				if not playPopup(level, seed, 0.5, "decoy").Success then
					lost += 1
				end
			end
			Expect.truthy(lost >= #SEEDS - 1, `niveau {level} : cliquer sur les faux boutons fait perdre ({lost})`)
		end
	end,

	["popup : empilement, ✕ caché, faux bouton"] = function()
		local state = PopupLogic.new(7, 12)
		while #state.Windows < 2 do
			PopupLogic.Step(state, DT)
		end
		local a, b = state.Windows[1], state.Windows[2]
		Expect.truthy(b.Z > a.Z, "la plus récente est dessus")
		-- b recouvre exactement le ✕ de a.
		b.Vx, b.Vy, a.Vx, a.Vy = 0, 0, 0, 0
		b.Decoys = { 1 }
		local ax, ay = PopupLogic.CloseCenter(a)
		b.X, b.Y = ax, ay
		Expect.truthy(PopupLogic.Covered(state, a), "✕ caché")
		Expect.truthy(not PopupLogic.Covered(state, b), "✕ du dessus visible")
		local events = PopupLogic.PressAt(state, ax, ay)
		Expect.truthy(events[1] == nil or events[1].Id == b.Id, "l'appui touche la fenêtre du dessus")
		Expect.truthy(PopupLogic.Find(state, a.Id) ~= nil, "a n'est pas fermée à travers b")
		-- Appui dans le vide : rien.
		Expect.equal(#PopupLogic.PressAt(state, -50, -50), 0)
		-- Faux bouton : RAM + une pub de plus (issue de b).
		local ram = state.Ram
		local count = #state.Windows
		local r = PopupLogic.DecoyRects(b)[1]
		events = PopupLogic.PressAt(state, (r.X0 + r.X1) / 2, (r.Y0 + r.Y1) / 2)
		Expect.equal(events[1].Kind, "Decoy")
		Expect.equal(events[1].Label, PopupLogic.DECOY_LABELS[1])
		Expect.near(state.Ram, math.min(1, ram + state.Params.DecoyPenalty), 1e-9)
		Expect.equal(#state.Windows, count + 1, "une pub de plus")
		Expect.equal(events[2].Kind, "Split")
		Expect.equal(events[2].Parent, b.Id)
		-- Manette : ferme la pub du dessus.
		local top = PopupLogic.Top(state) :: any
		events = PopupLogic.CloseTop(state)
		Expect.equal(events[1].Kind, "Close")
		Expect.equal(events[1].Id, top.Id)
		Expect.equal(state.Closed, 1)
		-- Le ✕ de a, découvert, se ferme.
		PopupLogic.Close(state, b.Id)
		if not PopupLogic.Covered(state, a) then
			events = PopupLogic.PressAt(state, PopupLogic.CloseCenter(a))
			Expect.equal(events[1].Kind, "Close")
			Expect.equal(events[1].Id, a.Id)
		end
	end,

	["popup : une pub oubliée se dédouble, la RAM se vide écran propre"] = function()
		local state = PopupLogic.new(1, 4)
		while #state.Windows < 1 do
			PopupLogic.Step(state, DT)
		end
		local first = state.Windows[1]
		local split = false
		for _ = 1, math.ceil(state.Params.SplitAfter / DT) + 2 do
			for _, event in PopupLogic.Step(state, DT) do
				if event.Kind == "Split" and event.Parent == first.Id then
					split = true
				end
			end
		end
		Expect.truthy(split, "dédoublement")
		for _, w in table.clone(state.Windows) do
			PopupLogic.Close(state, w.Id)
		end
		local ram = state.Ram
		PopupLogic.Step(state, DT)
		if #state.Windows == 0 then
			Expect.truthy(state.Ram < ram, "la RAM se libère")
		end
	end,

	["popup : même graine = même partie"] = function()
		local _, a = playPopup(5, 2024, 0.45, "close")
		local _, b = playPopup(5, 2024, 0.45, "close")
		local _, c = playPopup(5, 2025, 0.45, "close")
		Expect.equal(a, b, "déterminisme")
		Expect.truthy(a ~= c, "graines différentes -> parties différentes")
	end,

	["defrag : réglages et disques générés"] = function()
		monotonic(DefragLogic.Params, "Files", 1)
		monotonic(DefragLogic.Params, "Scramble", 1)
		monotonic(DefragLogic.Params, "MinMoves", 1)
		monotonic(DefragLogic.Params, "Slack", -1)
		for level = 1, 7 do
			local p = DefragLogic.Params(level)
			Expect.truthy(p.Files <= DefragLogic.MAX_FILES, "assez de couleurs")
			Expect.truthy(p.Files * p.Blocks < p.Cols * p.Rows, "au moins une case vide")
			local cell = DefragLogic.Layout(p)
			Expect.truthy(cell >= 72, `niveau {level} : cases assez grosses ({cell})`)
			for _, seed in SEEDS do
				local state = DefragLogic.new(level, seed)
				Expect.truthy(not DefragLogic.IsSolved(p, state.Cells), "disque bien mélangé")
				Expect.truthy(DefragLogic.IsSolved(p, state.Solved), "disque de départ rangé")
				Expect.truthy(state.Best >= p.MinMoves, `niveau {level} graine {seed} : plan {state.Best}`)
				Expect.equal(state.MaxMoves, state.Best + p.Slack)
				-- Rejouer le mélange sur le disque rangé redonne le disque mélangé.
				local cells = table.clone(state.Solved)
				for _, swap in state.Swaps do
					cells[swap[1]], cells[swap[2]] = cells[swap[2]], cells[swap[1]]
				end
				Expect.equal(table.concat(cells, ","), table.concat(state.Cells, ","), "mélange rejouable")
				local count = {}
				for _, value in state.Cells do
					count[value] = (count[value] or 0) + 1
				end
				for file = 1, p.Files do
					Expect.equal(count[file], p.Blocks, "blocs par fichier")
				end
			end
		end
		-- Coordonnées : chaque centre de case retombe dans sa case.
		local p = DefragLogic.Params(7)
		for index = 1, p.Cols * p.Rows do
			Expect.equal(DefragLogic.CellAt(p, DefragLogic.CellCenter(p, index)), index)
		end
		Expect.equal(DefragLogic.CellAt(p, -10, 200), nil)
		Expect.equal(DefragLogic.CellAt(p, 450, 5), nil, "bandeau du haut")
	end,

	["defrag : un bon joueur gagne, absent et hasard perdent"] = function()
		for level = 1, 8 do
			local think = Core.Lerp(2.5, 4, (math.min(level, 7) - 1) / 6)
			for _, seed in SEEDS do
				local state, _, clock = playDefrag(level, seed, think, "plan")
				Expect.truthy(
					state.Success,
					`niveau {level} graine {seed} : perdu ({state.Moves}/{state.MaxMoves} coups, {state.Time} s)`
				)
				Expect.truthy(state.Moves <= state.Best, "le plan tient dans les coups")
				Expect.between(clock, DefragLogic.SCRAMBLE_TIME, state.Params.Duration, `niveau {level} : durée`)
				local idle = playDefrag(level, seed, nil)
				Expect.truthy(idle.Done and not idle.Success, "sans jouer on perd")
				Expect.near(idle.Time, idle.Params.Duration, 0.05, "fin au chrono")
			end
		end
		for level = 3, 7 do
			local lost = 0
			for _, seed in SEEDS do
				if not playDefrag(level, seed, 1, "random").Success then
					lost += 1
				end
			end
			Expect.equal(lost, #SEEDS, `niveau {level} : échanger au hasard ne suffit pas`)
		end
	end,

	["defrag : choisir, échanger, annuler, coups limités"] = function()
		local state = DefragLogic.new(4, 31)
		local p = state.Params
		local block, empty = 0, 0
		for index, value in state.Cells do
			if value ~= 0 and block == 0 then
				block = index
			elseif value == 0 and empty == 0 then
				empty = index
			end
		end
		Expect.equal(#DefragLogic.Tap(state, block), 0, "pendant le mélange : ignoré")
		local ready = false
		while state.Phase == "Scramble" do
			for _, event in DefragLogic.Step(state, DT) do
				ready = ready or event.Kind == "Ready"
			end
		end
		Expect.truthy(ready, "fin du mélange")
		Expect.equal(#DefragLogic.Tap(state, empty), 0, "case vide seule : rien")
		Expect.equal(DefragLogic.Tap(state, block)[1].Kind, "Select")
		Expect.equal(DefragLogic.Tap(state, block)[1].Kind, "Deselect")
		Expect.equal(state.Selected, nil)
		-- Échange avec une case vide.
		DefragLogic.Tap(state, block)
		local events = DefragLogic.Tap(state, empty)
		Expect.equal(events[1].Kind, "Swap")
		Expect.equal(state.Moves, 1)
		Expect.equal(state.Cells[block], 0)
		Expect.equal(state.Selected, nil)
		-- Deux blocs du même fichier : pas de coup perdu.
		local a, b = 0, 0
		for i = 1, #state.Cells do
			for j = i + 1, #state.Cells do
				if a == 0 and state.Cells[i] ~= 0 and state.Cells[i] == state.Cells[j] then
					a, b = i, j
				end
			end
		end
		Expect.equal(DefragLogic.Swap(state, a, b)[1].Kind, "Same")
		Expect.equal(state.Moves, 1)
		Expect.equal(#DefragLogic.Swap(state, a, 999), 0, "case hors grille")
		-- Coups épuisés sans ranger : perdu.
		local rng = Core.Rng(3)
		local lastKind = ""
		while not state.Done do
			local x, y = rng:Int(1, p.Cols * p.Rows), rng:Int(1, p.Cols * p.Rows)
			for _, event in DefragLogic.Swap(state, x, y) do
				lastKind = event.Kind
			end
		end
		if not state.Success then
			Expect.equal(lastKind, "Lose")
			Expect.equal(state.Moves, state.MaxMoves)
			Expect.equal(DefragLogic.MovesLeft(state), 0)
		end
	end,

	["defrag : fichiers regroupés un à un, même graine = même disque"] = function()
		local state = DefragLogic.new(5, 77)
		while state.Phase == "Scramble" do
			DefragLogic.Step(state, DT)
		end
		local fixedEvents = 0
		for _, swap in DefragLogic.Plan(state) do
			for _, event in DefragLogic.Swap(state, swap[1], swap[2]) do
				if event.Kind == "Fixed" then
					fixedEvents += 1
				end
			end
		end
		Expect.truthy(state.Success, "le plan range le disque")
		Expect.equal(DefragLogic.FixedCount(state), state.Params.Files)
		Expect.truthy(fixedEvents >= 1, "des fichiers réparés en route")
		local _, a = playDefrag(6, 4242, 2, "plan")
		local _, b = playDefrag(6, 4242, 2, "plan")
		Expect.equal(a, b, "déterminisme")
		Expect.truthy(
			table.concat(DefragLogic.new(6, 1).Cells, ",") ~= table.concat(DefragLogic.new(6, 2).Cells, ","),
			"graines différentes -> disques différents"
		)
	end,

	["firewall : combat final contre LAGZ (difficulté 8)"] = function()
		local p = FirewallLogic.Params(8)
		Expect.truthy(p.BossHp ~= nil and p.BossHp > 0, "PV du boss")
		Expect.equal(FirewallLogic.Params(7).BossHp, nil, "niveau 7 normal")
		Expect.equal(FirewallLogic.new(7, 1).Boss, nil)
		Expect.truthy(p.Lives >= FirewallLogic.Params(7).Lives, "juste : au moins autant de vies qu'au 7")
		Expect.truthy(p.Radius * 2 >= 44, "cibles assez grosses")
		for _, seed in SEEDS do
			local state = playFirewall(8, seed)
			Expect.truthy(
				state.Success,
				`graine {seed} : perdu (PV {(state.Boss :: any).Hp}, fuites {state.Leaks}, {state.Time} s)`
			)
			Expect.equal(FirewallLogic.Score(state), p.BossHp, "score = PV retirés")
			Expect.between(state.Time, 12, p.Duration, "durée")
			local idle = playFirewall(8, seed, true)
			Expect.truthy(idle.Done and not idle.Success, "immobile : LAGZ gagne")
		end
		-- Bulle : les tirs sont bloqués ; mi-vie : LAGZ s'énerve.
		local state = FirewallLogic.new(8, 5)
		local blocked, rage, shield = 0, 0, 0
		while not state.Done and state.Time < MAX_TIME do
			local boss = state.Boss :: any
			FirewallLogic.SetAxis(
				state,
				if math.abs(boss.X - state.ShieldX) > 8 then (if boss.X > state.ShieldX then 1 else -1) else 0
			)
			for _, event in FirewallLogic.Step(state, DT) do
				if event.Kind == "BossBlock" then
					blocked += 1
					Expect.truthy(FirewallLogic.BossShielded(state), "bloqué seulement sous la bulle")
				elseif event.Kind == "BossRage" then
					rage += 1
				elseif event.Kind == "BossShield" then
					shield += 1
				end
			end
		end
		Expect.truthy(shield >= 1 and blocked >= 1, "la bulle bloque des tirs")
		Expect.equal(rage, 1, "LAGZ s'énerve une seule fois")
	end,

	["(stats) nouveaux jeux"] = function()
		for level = 1, 7 do
			local pT, pWin, pFast, pDecoyWin, pIdleT = 0, 0, math.huge, 0, 0
			local dT, dWin, dFast, dRandWin, dBest, dMax = 0, 0, math.huge, 0, 0, 0
			for _, seed in SEEDS do
				local reaction = Core.Lerp(0.6, 0.42, (level - 1) / 6)
				local g = playPopup(level, seed, reaction, "close")
				pT += g.Time
				if g.Success then
					pWin += 1
				end
				pFast = math.min(pFast, playPopup(level, seed, 0.05, "close", 0).Time)
				local ex = playPopup(level, seed, 0.05, "exploit", 0)
				if ex.Success then
					pFast = math.min(pFast, ex.Time)
				end
				if playPopup(level, seed, reaction, "decoy").Success then
					pDecoyWin += 1
				end
				pIdleT += playPopup(level, seed, nil).Time
				local think = Core.Lerp(2.5, 4, (level - 1) / 6)
				local d, _, clock = playDefrag(level, seed, think, "plan")
				dT += clock
				if d.Success then
					dWin += 1
				end
				dBest += d.Best
				dMax += d.MaxMoves
				local _, _, fast = playDefrag(level, seed, 0.3, "plan")
				dFast = math.min(dFast, fast)
				if playDefrag(level, seed, 1, "random").Success then
					dRandWin += 1
				end
			end
			local n = #SEEDS
			print(
				string.format(
					"  niv %d : popup %.1fs win %d/%d (min %.1fs, decoy %d, idle %.1fs)  defrag %.1fs win %d/%d (min %.1fs, plan %.1f / max %.1f, hasard %d)",
					level,
					pT / n,
					pWin,
					n,
					pFast,
					pDecoyWin,
					pIdleT / n,
					dT / n,
					dWin,
					n,
					dFast,
					dBest / n,
					dMax / n,
					dRandWin
				)
			)
		end
		local bT, bWin, bFast, bIdle = 0, 0, math.huge, 0
		for _, seed in SEEDS do
			local b = playFirewall(8, seed)
			bT += b.Time
			if b.Success then
				bWin += 1
			end
			local sn = playFirewall(8, seed, false, true)
			if sn.Success then
				bFast = math.min(bFast, sn.Time)
			end
			bFast = math.min(bFast, if b.Success then b.Time else math.huge)
			if playFirewall(8, seed, true).Success then
				bIdle += 1
			end
		end
		print(
			string.format(
				"  boss LAGZ : %.1fs win %d/%d (min %.1fs, immobile gagne %d)",
				bT / #SEEDS,
				bWin,
				#SEEDS,
				bFast,
				bIdle
			)
		)
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
