--!strict
--[[
	MemoryLogic : règles PURES du mini-jeu "Memory" (testables dans Lune).

	Les cartes (icônes de composants de PC) sont montrées quelques secondes, puis
	retournées. On retourne deux cartes : identiques -> elles restent visibles ;
	différentes -> elles se recachent et on perd une vie. Gagné quand toutes les paires
	sont trouvées ; perdu si les vies ou le chrono tombent à zéro.

	Une 3e carte touchée pendant qu'une mauvaise paire est encore visible recache
	immédiatement la paire (jeu nerveux, pas d'attente forcée).
]]

local Core = require(script.Parent.Core)

local MemoryLogic = {}

-- Nombre d'icônes différentes disponibles côté interface (voir Memory.luau).
MemoryLogic.SYMBOLS = 12

export type Params = {
	Cols: number,
	Rows: number,
	Lives: number, -- erreurs permises
	Duration: number, -- secondes (après l'aperçu)
	Preview: number, -- secondes pendant lesquelles toutes les cartes sont visibles
	MissShow: number, -- secondes d'affichage d'une mauvaise paire
}

local ROWS: { Params } = {
	{ Cols = 4, Rows = 3, Lives = 10, Duration = 50, Preview = 3.0, MissShow = 1.0 },
	{ Cols = 4, Rows = 3, Lives = 8, Duration = 45, Preview = 2.5, MissShow = 0.9 },
	{ Cols = 4, Rows = 4, Lives = 10, Duration = 55, Preview = 2.5, MissShow = 0.85 },
	{ Cols = 5, Rows = 4, Lives = 12, Duration = 60, Preview = 2.4, MissShow = 0.8 },
	{ Cols = 5, Rows = 4, Lives = 11, Duration = 55, Preview = 2.0, MissShow = 0.75 },
	{ Cols = 6, Rows = 4, Lives = 13, Duration = 65, Preview = 2.0, MissShow = 0.7 },
	{ Cols = 6, Rows = 4, Lives = 12, Duration = 60, Preview = 1.6, MissShow = 0.65 },
}

export type Face = "Down" | "Up" | "Matched"

export type Card = { Symbol: number, Face: Face }

export type Event = {
	Kind: "Hide" | "Flip" | "Match" | "Miss" | "Win" | "Lose",
	Cards: { number }, -- index des cartes concernées
	Reason: string?, -- Lose : "Lives" | "Time"
}

export type State = {
	Params: Params,
	Rng: Core.Rng,
	Phase: "Preview" | "Play" | "Done",
	PreviewLeft: number,
	Time: number, -- temps de jeu (hors aperçu)
	Cards: { Card },
	First: number?, -- première carte retournée de la paire en cours
	Pending: { number }?, -- mauvaise paire encore visible
	HideAt: number,
	Pairs: number,
	Found: number,
	Misses: number,
	Flips: number,
	Done: boolean,
	Success: boolean,
}

function MemoryLogic.Params(difficulty: number): Params
	return Core.Row(ROWS, difficulty)
end

function MemoryLogic.new(difficulty: number, seed: number): State
	local params = MemoryLogic.Params(difficulty)
	local rng = Core.Rng(seed)
	local pairs = math.floor(params.Cols * params.Rows / 2)
	-- Choix des icônes parmi le catalogue, puis mélange des cartes.
	local catalog = {}
	for symbol = 1, MemoryLogic.SYMBOLS do
		catalog[symbol] = symbol
	end
	rng:Shuffle(catalog)
	local cards: { Card } = {}
	for i = 1, pairs do
		local symbol = catalog[(i - 1) % MemoryLogic.SYMBOLS + 1]
		table.insert(cards, { Symbol = symbol, Face = "Up" })
		table.insert(cards, { Symbol = symbol, Face = "Up" })
	end
	rng:Shuffle(cards)
	return {
		Params = params,
		Rng = rng,
		Phase = "Preview",
		PreviewLeft = params.Preview,
		Time = 0,
		Cards = cards,
		First = nil,
		Pending = nil,
		HideAt = 0,
		Pairs = pairs,
		Found = 0,
		Misses = 0,
		Flips = 0,
		Done = false,
		Success = false,
	}
end

function MemoryLogic.LivesLeft(sim: State): number
	return math.max(0, sim.Params.Lives - sim.Misses)
end

function MemoryLogic.TimeLeft(sim: State): number
	return math.max(0, sim.Params.Duration - sim.Time)
end

local function lose(sim: State, events: { Event }, reason: string)
	sim.Done = true
	sim.Success = false
	sim.Phase = "Done"
	table.insert(events, { Kind = "Lose", Cards = {}, Reason = reason })
end

-- Recache la mauvaise paire affichée.
local function hidePending(sim: State, events: { Event })
	local pending = sim.Pending
	if not pending then
		return
	end
	sim.Pending = nil
	for _, index in pending do
		sim.Cards[index].Face = "Down"
	end
	table.insert(events, { Kind = "Hide", Cards = pending })
	if MemoryLogic.LivesLeft(sim) <= 0 then
		lose(sim, events, "Lives")
	end
end

function MemoryLogic.Step(sim: State, dt: number): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	dt = math.clamp(dt, 0, Core.MAX_STEP)
	if sim.Phase == "Preview" then
		sim.PreviewLeft -= dt
		if sim.PreviewLeft <= 0 then
			sim.Phase = "Play"
			local all = {}
			for index, card in sim.Cards do
				card.Face = "Down"
				table.insert(all, index)
			end
			table.insert(events, { Kind = "Hide", Cards = all })
		end
		return events
	end
	sim.Time += dt
	if sim.Pending and sim.Time >= sim.HideAt then
		hidePending(sim, events)
		if sim.Done then
			return events
		end
	end
	if sim.Time >= sim.Params.Duration then
		lose(sim, events, "Time")
	end
	return events
end

-- Retourne la carte `index`. Renvoie les événements (Flip, puis Match / Miss, Win…).
function MemoryLogic.Flip(sim: State, index: number): { Event }
	local events: { Event } = {}
	local card = sim.Cards[index]
	if sim.Done or sim.Phase ~= "Play" or not card then
		return events
	end
	if sim.Pending then
		hidePending(sim, events)
		if sim.Done then
			return events
		end
	end
	if card.Face ~= "Down" then
		return events
	end
	card.Face = "Up"
	sim.Flips += 1
	table.insert(events, { Kind = "Flip", Cards = { index } })
	local first = sim.First
	if not first then
		sim.First = index
		return events
	end
	sim.First = nil
	local other = sim.Cards[first]
	if other.Symbol == card.Symbol then
		other.Face = "Matched"
		card.Face = "Matched"
		sim.Found += 1
		table.insert(events, { Kind = "Match", Cards = { first, index } })
		if sim.Found >= sim.Pairs then
			sim.Done = true
			sim.Success = true
			sim.Phase = "Done"
			table.insert(events, { Kind = "Win", Cards = {} })
		end
	else
		sim.Misses += 1
		sim.Pending = { first, index }
		sim.HideAt = sim.Time + sim.Params.MissShow
		table.insert(events, { Kind = "Miss", Cards = { first, index } })
	end
	return events
end

return table.freeze(MemoryLogic)
