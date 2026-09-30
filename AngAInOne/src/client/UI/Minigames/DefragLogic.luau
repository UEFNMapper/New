--!strict
--[[
	DefragLogic : règles PURES du mini-jeu "Défrag" (monde 3, testables dans Lune).

	Un disque en grille (Cols x Rows cases). Chaque fichier est fait de `Blocks` blocs de
	la même couleur ; Corrupto les a éparpillés. On échange deux cases (bloc <-> bloc ou
	bloc <-> case vide) pour que les blocs de chaque fichier se touchent (un seul groupe,
	voisins haut / bas / gauche / droite). Gagné quand tous les fichiers sont regroupés,
	perdu si les coups (MaxMoves) ou le chrono tombent à zéro.

	Génération : un disque rangé (fichiers posés à la suite le long d'un chemin en
	serpentin) est mélangé par `Scramble` échanges. Le nombre de coups autorisé est
	calculé sur le meilleur rangement « en serpentin » trouvé (Plan) + une marge `Slack` :
	la partie est toujours faisable, facile au niveau 1, un vrai casse-tête au niveau 7.

	Phase "Scramble" (SCRAMBLE_TIME s) : l'interface montre le disque rangé qui se fait
	mélanger (Swaps, dans l'ordre) ; les appuis sont ignorés.

	Entrées : Tap(index) (toucher une case : choisir, puis échanger) ou Swap(a, b)
	(glisser d'une case à l'autre). Cases numérotées ligne par ligne, 1..Cols*Rows ;
	0 = case vide, 1..Files = fichier.
]]

local Core = require(script.Parent.Core)

local DefragLogic = {}

export type Params = {
	Cols: number,
	Rows: number,
	Files: number,
	Blocks: number, -- blocs par fichier
	Scramble: number, -- échanges de mélange
	MinMoves: number, -- coups minimum du plan (sinon on remélange)
	Slack: number, -- coups de marge au-delà du plan
	Duration: number,
}

local ROWS: { Params } = {
	{ Cols = 4, Rows = 3, Files = 2, Blocks = 3, Scramble = 3, MinMoves = 3, Slack = 6, Duration = 60 },
	{ Cols = 4, Rows = 3, Files = 3, Blocks = 3, Scramble = 4, MinMoves = 3, Slack = 5, Duration = 70 },
	{ Cols = 5, Rows = 4, Files = 3, Blocks = 4, Scramble = 6, MinMoves = 4, Slack = 5, Duration = 80 },
	{ Cols = 5, Rows = 4, Files = 4, Blocks = 4, Scramble = 8, MinMoves = 5, Slack = 4, Duration = 90 },
	{ Cols = 6, Rows = 4, Files = 4, Blocks = 5, Scramble = 10, MinMoves = 6, Slack = 4, Duration = 100 },
	{ Cols = 6, Rows = 5, Files = 5, Blocks = 5, Scramble = 12, MinMoves = 8, Slack = 3, Duration = 110 },
	{ Cols = 7, Rows = 5, Files = 5, Blocks = 6, Scramble = 14, MinMoves = 10, Slack = 2, Duration = 120 },
}

DefragLogic.SCRAMBLE_TIME = 3
DefragLogic.MAX_FILES = 5 -- couleurs / types de fichiers dessinés par l'interface
local CANDIDATES = 6 -- rangements évalués en détail (les plus prometteurs)
local ORDER_PICKS = 3 -- ordres de fichiers gardés par chemin et décalage
local MAX_ATTEMPTS = 25

export type Swap = { number } -- { a, b }

export type Event = {
	Kind: "Ready" | "Select" | "Deselect" | "Swap" | "Same" | "Fixed" | "Broken" | "Win" | "Lose",
	Cells: { number }, -- cases concernées
	File: number?, -- Fixed / Broken : fichier regroupé / de nouveau éparpillé
	Reason: string?, -- Lose : "Moves" | "Time"
}

export type State = {
	Params: Params,
	Rng: Core.Rng,
	Phase: "Scramble" | "Play" | "Done",
	ScrambleLeft: number,
	Time: number, -- temps de jeu (hors mélange)
	Cells: { number },
	Solved: { number }, -- disque rangé de départ (montré pendant le mélange)
	Swaps: { Swap }, -- échanges du mélange, dans l'ordre
	Best: number, -- coups du meilleur plan trouvé au départ
	MaxMoves: number,
	Moves: number,
	Selected: number?,
	Fixed: { [number]: boolean }, -- fichiers déjà regroupés
	Done: boolean,
	Success: boolean,
}

function DefragLogic.Params(difficulty: number): Params
	return Core.Row(ROWS, difficulty)
end

------------------------------------------------------------------------------------
-- Outils de grille
------------------------------------------------------------------------------------

function DefragLogic.Coords(p: Params, index: number): (number, number)
	return (index - 1) % p.Cols, (index - 1) // p.Cols -- colonne, ligne (à partir de 0)
end

function DefragLogic.Index(p: Params, col: number, row: number): number?
	if col < 0 or row < 0 or col >= p.Cols or row >= p.Rows then
		return nil
	end
	return row * p.Cols + col + 1
end

-- Disposition dans le terrain : cases carrées le plus grandes possible sous un bandeau
-- (coups restants). Renvoie la taille d'une case et le coin haut-gauche de la grille.
DefragLogic.BAND = 56
DefragLogic.MARGIN = 14
function DefragLogic.Layout(p: Params): (number, number, number)
	local margin = DefragLogic.MARGIN
	local cell = math.min((Core.FIELD_W - margin * 2) / p.Cols, (Core.FIELD_H - DefragLogic.BAND - margin) / p.Rows)
	local originX = (Core.FIELD_W - cell * p.Cols) / 2
	local originY = DefragLogic.BAND + (Core.FIELD_H - DefragLogic.BAND - margin - cell * p.Rows) / 2
	return cell, originX, originY
end

-- Case sous le point (x, y) du terrain (nil en dehors de la grille).
function DefragLogic.CellAt(p: Params, x: number, y: number): number?
	local cell, originX, originY = DefragLogic.Layout(p)
	return DefragLogic.Index(p, math.floor((x - originX) / cell), math.floor((y - originY) / cell))
end

-- Centre de la case `index` dans le terrain.
function DefragLogic.CellCenter(p: Params, index: number): (number, number)
	local cell, originX, originY = DefragLogic.Layout(p)
	local col, row = DefragLogic.Coords(p, index)
	return originX + (col + 0.5) * cell, originY + (row + 0.5) * cell
end

-- Le fichier `file` forme-t-il un seul groupe ?
function DefragLogic.IsWhole(p: Params, cells: { number }, file: number): boolean
	local start: number? = nil
	local total = 0
	for index, value in cells do
		if value == file then
			total += 1
			start = start or index
		end
	end
	if not start then
		return true
	end
	local seen: { [number]: boolean } = { [start] = true }
	local stack = { start }
	local count = 0
	while #stack > 0 do
		local index = table.remove(stack) :: number
		count += 1
		local col, row = DefragLogic.Coords(p, index)
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local other = DefragLogic.Index(p, col + d[1], row + d[2])
			if other and not seen[other] and cells[other] == file then
				seen[other] = true
				table.insert(stack, other)
			end
		end
	end
	return count == total
end

function DefragLogic.IsSolved(p: Params, cells: { number }): boolean
	for file = 1, p.Files do
		if not DefragLogic.IsWhole(p, cells, file) then
			return false
		end
	end
	return true
end

-- Chemins en serpentin (8 : lignes ou colonnes, depuis chacun des 4 coins). Deux cases
-- qui se suivent sur un chemin sont voisines : un morceau de chemin est d'un seul tenant.
local function snakePaths(p: Params): { { number } }
	local paths = {}
	for _, byColumn in { false, true } do
		for _, flipX in { false, true } do
			for _, flipY in { false, true } do
				local path = {}
				local outer = if byColumn then p.Cols else p.Rows
				local inner = if byColumn then p.Rows else p.Cols
				for a = 0, outer - 1 do
					for k = 0, inner - 1 do
						local b = if a % 2 == 0 then k else inner - 1 - k
						local col = if byColumn then a else b
						local row = if byColumn then b else a
						if flipX then
							col = p.Cols - 1 - col
						end
						if flipY then
							row = p.Rows - 1 - row
						end
						table.insert(path, DefragLogic.Index(p, col, row) :: number)
					end
				end
				table.insert(paths, path)
			end
		end
	end
	return paths
end

local function permutations(n: number): { { number } }
	local result = {}
	local current = {}
	local used = {}
	local function build()
		if #current == n then
			table.insert(result, table.clone(current))
			return
		end
		for value = 1, n do
			if not used[value] then
				used[value] = true
				table.insert(current, value)
				build()
				table.remove(current)
				used[value] = false
			end
		end
	end
	build()
	return result
end

-- Disque rangé : fichiers posés à la suite le long du chemin, après `offset` cases vides.
local function layout(p: Params, path: { number }, order: { number }, offset: number): { number }
	local cells = table.create(p.Cols * p.Rows, 0)
	for k, file in order do
		for j = 1, p.Blocks do
			cells[path[offset + (k - 1) * p.Blocks + j]] = file
		end
	end
	return cells
end

-- Majorant rapide des échanges nécessaires pour atteindre layout(path, order, offset) :
-- cases mal placées - échanges "croisés" (deux cases réglées d'un coup). Calculé sans
-- construire le disque cible ; `counts` : tableau de travail (kinds + 1)^2, remis à zéro.
local function estimate(
	cur: { number },
	path: { number },
	order: { number },
	offset: number,
	blocks: number,
	counts: { number }
): number
	local kinds = #order
	local stride = kinds + 1
	local filled = kinds * blocks
	local misplaced = 0
	for k, index in path do
		local rel = k - offset
		local want = if rel >= 1 and rel <= filled then order[(rel - 1) // blocks + 1] else 0
		local value = cur[index]
		if value ~= want then
			misplaced += 1
			local key = value * stride + want + 1
			counts[key] += 1
		end
	end
	local crossed = 0
	for a = 0, kinds do
		for b = a + 1, kinds do
			crossed += math.min(counts[a * stride + b + 1], counts[b * stride + a + 1])
		end
	end
	for key = 1, stride * stride do
		counts[key] = 0
	end
	return misplaced - crossed
end

-- Plan glouton d'échanges pour passer de `cur` à `tgt` : d'abord les échanges qui
-- placent deux cases d'un coup, puis une case à la fois.
function DefragLogic.PlanTo(cur: { number }, tgt: { number }): { Swap }
	local cells = table.clone(cur)
	local plan: { Swap } = {}
	local n = #cells
	for i = 1, n do
		if cells[i] ~= tgt[i] then
			for j = i + 1, n do
				if cells[j] ~= tgt[j] and cells[i] == tgt[j] and cells[j] == tgt[i] then
					cells[i], cells[j] = cells[j], cells[i]
					table.insert(plan, { i, j })
					break
				end
			end
		end
	end
	while true do
		local i: number? = nil
		for index = 1, n do
			if cells[index] ~= tgt[index] then
				i = index
				break
			end
		end
		if not i then
			break
		end
		local pick: number? = nil
		for j = 1, n do
			if j ~= i and cells[j] ~= tgt[j] and cells[j] == tgt[i] then
				if tgt[j] == cells[i] then
					pick = j
					break
				end
				pick = pick or j
			end
		end
		if not pick then
			break -- impossible (comptes différents) : ne devrait jamais arriver
		end
		cells[i], cells[pick] = cells[pick], cells[i]
		table.insert(plan, { i, pick })
	end
	return plan
end

-- Meilleur plan vers un disque rangé "en serpentin" depuis `cells`.
function DefragLogic.BestPlan(p: Params, cells: { number }): { Swap }
	local empties = p.Cols * p.Rows - p.Files * p.Blocks
	-- Les CANDIDATES meilleurs rangements (score croissant ; à égalité, le premier trouvé :
	-- déterministe).
	type Candidate = { Score: number, Path: { number }, Order: { number }, Offset: number }
	type Pick = { Matches: number, Order: { number } }
	local files, blocks = p.Files, p.Blocks
	local filled = files * blocks
	local top: { Candidate } = {}
	local orders = permutations(files)
	local counts = table.create((files + 1) * (files + 1), 0)
	local matches = table.create(files * files, 0) -- [segment, fichier] -> blocs déjà en place
	for _, path in snakePaths(p) do
		for offset = 0, empties do
			-- 1. Pour chaque morceau du chemin, combien de blocs de chaque fichier y sont déjà.
			for key = 1, files * files do
				matches[key] = 0
			end
			for k, index in path do
				local rel = k - offset
				local value = cells[index]
				if value > 0 and rel >= 1 and rel <= filled then
					local key = ((rel - 1) // blocks) * files + value
					matches[key] += 1
				end
			end
			-- 2. Les ordres de fichiers qui laissent le plus de blocs en place…
			local picks: { Pick } = {}
			for _, order in orders do
				local total = 0
				for segment, file in order do
					total += matches[(segment - 1) * files + file]
				end
				if #picks < ORDER_PICKS or total > picks[#picks].Matches then
					local at = #picks + 1
					while at > 1 and picks[at - 1].Matches < total do
						at -= 1
					end
					table.insert(picks, at, { Matches = total, Order = order })
					if #picks > ORDER_PICKS then
						table.remove(picks)
					end
				end
			end
			-- 3. … évalués plus finement.
			for _, pick in picks do
				local score = estimate(cells, path, pick.Order, offset, blocks, counts)
				if #top < CANDIDATES or score < top[#top].Score then
					local at = #top + 1
					while at > 1 and top[at - 1].Score > score do
						at -= 1
					end
					table.insert(top, at, { Score = score, Path = path, Order = pick.Order, Offset = offset })
					if #top > CANDIDATES then
						table.remove(top)
					end
				end
			end
		end
	end
	local best: { Swap }? = nil
	for _, candidate in top do
		local target = layout(p, candidate.Path, candidate.Order, candidate.Offset)
		local plan = DefragLogic.PlanTo(cells, target)
		if not best or #plan < #best then
			best = plan
		end
	end
	return best or {}
end

------------------------------------------------------------------------------------
-- Partie
------------------------------------------------------------------------------------

function DefragLogic.new(difficulty: number, seed: number): State
	local p = DefragLogic.Params(difficulty)
	local rng = Core.Rng(seed)
	local total = p.Cols * p.Rows
	local empties = total - p.Files * p.Blocks
	local paths = snakePaths(p)
	local solved: { number } = {}
	local cells: { number } = {}
	local swaps: { Swap } = {}
	local best = 0
	for attempt = 1, MAX_ATTEMPTS do
		local order = {}
		for file = 1, p.Files do
			order[file] = file
		end
		rng:Shuffle(order)
		solved = layout(p, paths[rng:Int(1, #paths)], order, rng:Int(0, empties))
		cells = table.clone(solved)
		swaps = {}
		-- Un peu plus de mélange à chaque nouvel essai.
		local wanted = p.Scramble + (attempt - 1) // 3
		local guard = 0
		while #swaps < wanted and guard < 1000 do
			guard += 1
			local a, b = rng:Int(1, total), rng:Int(1, total)
			if cells[a] ~= cells[b] then
				cells[a], cells[b] = cells[b], cells[a]
				table.insert(swaps, { a, b })
			end
		end
		best = #DefragLogic.BestPlan(p, cells)
		if best >= p.MinMoves and not DefragLogic.IsSolved(p, cells) then
			break
		end
	end
	local fixed: { [number]: boolean } = {}
	for file = 1, p.Files do
		fixed[file] = DefragLogic.IsWhole(p, cells, file)
	end
	return {
		Params = p,
		Rng = rng,
		Phase = "Scramble",
		ScrambleLeft = DefragLogic.SCRAMBLE_TIME,
		Time = 0,
		Cells = cells,
		Solved = solved,
		Swaps = swaps,
		Best = best,
		MaxMoves = best + p.Slack,
		Moves = 0,
		Selected = nil,
		Fixed = fixed,
		Done = false,
		Success = false,
	}
end

function DefragLogic.MovesLeft(sim: State): number
	return math.max(0, sim.MaxMoves - sim.Moves)
end

function DefragLogic.TimeLeft(sim: State): number
	return math.max(0, sim.Params.Duration - sim.Time)
end

function DefragLogic.FixedCount(sim: State): number
	local count = 0
	for file = 1, sim.Params.Files do
		if sim.Fixed[file] then
			count += 1
		end
	end
	return count
end

-- Plan conseillé depuis la position actuelle (joueur simulé, indice éventuel).
function DefragLogic.Plan(sim: State): { Swap }
	return DefragLogic.BestPlan(sim.Params, sim.Cells)
end

local function lose(sim: State, events: { Event }, reason: string)
	sim.Done = true
	sim.Success = false
	sim.Phase = "Done"
	sim.Selected = nil
	table.insert(events, { Kind = "Lose", Cells = {}, Reason = reason })
end

function DefragLogic.Step(sim: State, dt: number): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	dt = math.clamp(dt, 0, Core.MAX_STEP)
	if sim.Phase == "Scramble" then
		sim.ScrambleLeft -= dt
		if sim.ScrambleLeft <= 0 then
			sim.Phase = "Play"
			table.insert(events, { Kind = "Ready", Cells = {} })
		end
		return events
	end
	sim.Time += dt
	if sim.Time >= sim.Params.Duration then
		lose(sim, events, "Time")
	end
	return events
end

-- Échange les cases a et b (glisser, ou 2e appui).
function DefragLogic.Swap(sim: State, a: number, b: number): { Event }
	local events: { Event } = {}
	local p = sim.Params
	local total = p.Cols * p.Rows
	if sim.Done or sim.Phase ~= "Play" or a == b or a < 1 or b < 1 or a > total or b > total then
		return events
	end
	if sim.Selected then
		sim.Selected = nil
	end
	local cells = sim.Cells
	if cells[a] == cells[b] then
		table.insert(events, { Kind = "Same", Cells = { a, b } })
		return events
	end
	cells[a], cells[b] = cells[b], cells[a]
	sim.Moves += 1
	table.insert(events, { Kind = "Swap", Cells = { a, b } })
	for file = 1, p.Files do
		local whole = DefragLogic.IsWhole(p, cells, file)
		if whole ~= sim.Fixed[file] then
			sim.Fixed[file] = whole
			table.insert(events, { Kind = if whole then "Fixed" else "Broken", Cells = {}, File = file })
		end
	end
	if DefragLogic.IsSolved(p, cells) then
		sim.Done = true
		sim.Success = true
		sim.Phase = "Done"
		table.insert(events, { Kind = "Win", Cells = {} })
	elseif sim.Moves >= sim.MaxMoves then
		lose(sim, events, "Moves")
	end
	return events
end

-- Appui sur une case : 1er appui = choisir un bloc, 2e appui = échanger (ou annuler).
function DefragLogic.Tap(sim: State, index: number): { Event }
	local events: { Event } = {}
	local p = sim.Params
	if sim.Done or sim.Phase ~= "Play" or index < 1 or index > p.Cols * p.Rows then
		return events
	end
	local selected = sim.Selected
	if not selected then
		if sim.Cells[index] ~= 0 then
			sim.Selected = index
			table.insert(events, { Kind = "Select", Cells = { index } })
		end
		return events
	end
	if selected == index then
		sim.Selected = nil
		table.insert(events, { Kind = "Deselect", Cells = { index } })
		return events
	end
	return DefragLogic.Swap(sim, selected, index)
end

return table.freeze(DefragLogic)
