--!strict
--[[
	PopupLogic : règles PURES du mini-jeu "Pop-up Killer" (monde 2, testables dans Lune).

	Des fenêtres de pub (« TU AS GAGNÉ !!! ») s'ouvrent sur l'écran et se multiplient.
	Chaque fenêtre ouverte remplit la jauge de RAM. Il faut fermer `Target` fenêtres (en
	touchant leur ✕) avant que la RAM soit pleine. Certaines pubs ont de faux boutons
	(« OK », « Télécharger ») : les toucher ouvre une pub de plus et remplit la RAM.
	Une pub laissée trop longtemps se dédouble.

	Les fenêtres se superposent : la plus récente est dessus. Un appui touche la fenêtre
	la plus haute sous le doigt (PressAt) : même règle pour l'interface et les tests.

	Coordonnées : terrain Core.FIELD_W x Core.FIELD_H ; les fenêtres restent au-dessus
	de AREA_BOTTOM (la jauge de RAM est dessinée dessous).
]]

local Core = require(script.Parent.Core)

local PopupLogic = {}

export type Params = {
	Target: number, -- pubs à fermer
	SpawnEvery: number, -- secondes entre deux pubs (en moyenne)
	MaxOpen: number, -- écran plein : plus de nouvelles pubs au-delà
	Load: number, -- RAM remplie par seconde et par pub ouverte (1 = pleine)
	Drain: number, -- RAM libérée par seconde quand l'écran est vide
	StartRam: number,
	DecoyChance: number, -- probabilité d'au moins un faux bouton
	DoubleDecoyChance: number, -- probabilité d'un 2e faux bouton
	DecoyPenalty: number, -- RAM ajoutée par un faux bouton touché
	SplitAfter: number, -- une pub ouverte depuis ce temps se dédouble
	MoveChance: number, -- probabilité d'une pub qui se promène
	MoveSpeed: number, -- unités/s
	LeftCloseChance: number, -- ✕ à gauche (pub rusée)
	W: number, -- taille d'une fenêtre (unités)
	H: number,
}

local ROWS: { Params } = {
	{
		Target = 10,
		SpawnEvery = 1.6,
		MaxOpen = 6,
		Load = 0.022,
		Drain = 0.05,
		StartRam = 0.2,
		DecoyChance = 0.3,
		DoubleDecoyChance = 0,
		DecoyPenalty = 0.18,
		SplitAfter = 6,
		MoveChance = 0,
		MoveSpeed = 0,
		LeftCloseChance = 0,
		W = 300,
		H = 210,
	},
	{
		Target = 12,
		SpawnEvery = 1.4,
		MaxOpen = 6,
		Load = 0.024,
		Drain = 0.05,
		StartRam = 0.2,
		DecoyChance = 0.45,
		DoubleDecoyChance = 0.1,
		DecoyPenalty = 0.18,
		SplitAfter = 5.5,
		MoveChance = 0,
		MoveSpeed = 0,
		LeftCloseChance = 0,
		W = 290,
		H = 205,
	},
	{
		Target = 14,
		SpawnEvery = 1.2,
		MaxOpen = 7,
		Load = 0.026,
		Drain = 0.05,
		StartRam = 0.22,
		DecoyChance = 0.55,
		DoubleDecoyChance = 0.2,
		DecoyPenalty = 0.19,
		SplitAfter = 5,
		MoveChance = 0.1,
		MoveSpeed = 50,
		LeftCloseChance = 0,
		W = 280,
		H = 200,
	},
	{
		Target = 16,
		SpawnEvery = 1.05,
		MaxOpen = 7,
		Load = 0.028,
		Drain = 0.05,
		StartRam = 0.24,
		DecoyChance = 0.65,
		DoubleDecoyChance = 0.3,
		DecoyPenalty = 0.2,
		SplitAfter = 4.5,
		MoveChance = 0.2,
		MoveSpeed = 65,
		LeftCloseChance = 0.15,
		W = 270,
		H = 195,
	},
	{
		Target = 18,
		SpawnEvery = 0.95,
		MaxOpen = 8,
		Load = 0.03,
		Drain = 0.05,
		StartRam = 0.26,
		DecoyChance = 0.75,
		DoubleDecoyChance = 0.4,
		DecoyPenalty = 0.2,
		SplitAfter = 4,
		MoveChance = 0.25,
		MoveSpeed = 80,
		LeftCloseChance = 0.25,
		W = 265,
		H = 190,
	},
	{
		Target = 20,
		SpawnEvery = 0.85,
		MaxOpen = 8,
		Load = 0.032,
		Drain = 0.05,
		StartRam = 0.28,
		DecoyChance = 0.85,
		DoubleDecoyChance = 0.5,
		DecoyPenalty = 0.2,
		SplitAfter = 3.5,
		MoveChance = 0.3,
		MoveSpeed = 95,
		LeftCloseChance = 0.3,
		W = 255,
		H = 185,
	},
	{
		Target = 22,
		SpawnEvery = 0.75,
		MaxOpen = 9,
		Load = 0.034,
		Drain = 0.05,
		StartRam = 0.3,
		DecoyChance = 0.9,
		DoubleDecoyChance = 0.6,
		DecoyPenalty = 0.2,
		SplitAfter = 3.2,
		MoveChance = 0.35,
		MoveSpeed = 110,
		LeftCloseChance = 0.35,
		W = 250,
		H = 180,
	},
}

PopupLogic.AREA_BOTTOM = Core.FIELD_H - 58 -- les fenêtres restent au-dessus de la jauge de RAM
PopupLogic.EDGE = 8
PopupLogic.CLOSE_SIZE = 72 -- zone tactile du ✕ (carré dans le coin haut de la fenêtre)
PopupLogic.TITLE_H = 56 -- barre de titre
PopupLogic.DECOY_H = 54
PopupLogic.DECOY_MAX_W = 130
PopupLogic.FIRST_SPAWN = 0.5
PopupLogic.MAX_TIME = 150 -- garde-fou : une partie ne dure jamais plus
PopupLogic.STYLES = 6 -- nombre de pubs différentes (textes et couleurs, voir Popup.luau)
PopupLogic.DECOY_LABELS = table.freeze({ "OK", "Télécharger", "Oui !", "Gratuit !" })

export type Rect = { X0: number, Y0: number, X1: number, Y1: number }

export type Window = {
	Id: number,
	X: number, -- centre
	Y: number,
	W: number,
	H: number,
	Z: number, -- ordre d'empilement (plus grand = dessus)
	Age: number, -- depuis l'ouverture ou le dernier dédoublement
	Life: number, -- depuis l'ouverture
	CloseLeft: boolean,
	Decoys: { number }, -- index dans DECOY_LABELS
	Style: number,
	Vx: number,
	Vy: number,
}

export type Event = {
	Kind: "Spawn" | "Close" | "Decoy" | "Body" | "Split" | "Win" | "Lose",
	Id: number, -- fenêtre concernée (0 pour Win / Lose)
	Parent: number?, -- Spawn issu d'un dédoublement ou d'un faux bouton
	Label: string?, -- Decoy : texte du faux bouton
	X: number?,
	Y: number?,
	Reason: string?, -- Lose : "Ram" | "Time"
}

export type State = {
	Params: Params,
	Rng: Core.Rng,
	Time: number,
	Ram: number, -- 0..1
	Windows: { Window }, -- ordre d'ouverture (Z croissant)
	NextSpawn: number,
	NextId: number,
	NextZ: number,
	Closed: number,
	Decoys: number, -- faux boutons touchés
	Done: boolean,
	Success: boolean,
}

function PopupLogic.Params(difficulty: number): Params
	return Core.Row(ROWS, difficulty)
end

function PopupLogic.new(difficulty: number, seed: number): State
	local params = PopupLogic.Params(difficulty)
	return {
		Params = params,
		Rng = Core.Rng(seed),
		Time = 0,
		Ram = params.StartRam,
		Windows = {},
		NextSpawn = PopupLogic.FIRST_SPAWN,
		NextId = 1,
		NextZ = 1,
		Closed = 0,
		Decoys = 0,
		Done = false,
		Success = false,
	}
end

------------------------------------------------------------------------------------
-- Géométrie d'une fenêtre
------------------------------------------------------------------------------------

function PopupLogic.Bounds(w: Window): Rect
	return { X0 = w.X - w.W / 2, Y0 = w.Y - w.H / 2, X1 = w.X + w.W / 2, Y1 = w.Y + w.H / 2 }
end

-- Zone tactile du ✕ (dans le coin haut, à droite ou à gauche).
function PopupLogic.CloseRect(w: Window): Rect
	local size = PopupLogic.CLOSE_SIZE
	local top = w.Y - w.H / 2
	if w.CloseLeft then
		local left = w.X - w.W / 2
		return { X0 = left, Y0 = top, X1 = left + size, Y1 = top + size }
	end
	local right = w.X + w.W / 2
	return { X0 = right - size, Y0 = top, X1 = right, Y1 = top + size }
end

function PopupLogic.CloseCenter(w: Window): (number, number)
	local r = PopupLogic.CloseRect(w)
	return (r.X0 + r.X1) / 2, (r.Y0 + r.Y1) / 2
end

-- Faux boutons : alignés en bas de la fenêtre.
function PopupLogic.DecoyRects(w: Window): { Rect }
	local rects = {}
	local count = #w.Decoys
	if count == 0 then
		return rects
	end
	local gap = 10
	local width = math.min(PopupLogic.DECOY_MAX_W, (w.W - 24 - gap * (count - 1)) / count)
	local total = width * count + gap * (count - 1)
	local left = w.X - total / 2
	local bottom = w.Y + w.H / 2 - 12
	for i = 1, count do
		local x0 = left + (i - 1) * (width + gap)
		table.insert(rects, { X0 = x0, Y0 = bottom - PopupLogic.DECOY_H, X1 = x0 + width, Y1 = bottom })
	end
	return rects
end

local function inside(r: Rect, x: number, y: number): boolean
	return x >= r.X0 and x <= r.X1 and y >= r.Y0 and y <= r.Y1
end

local function overlap(a: Rect, b: Rect): number
	local w = math.min(a.X1, b.X1) - math.max(a.X0, b.X0)
	local h = math.min(a.Y1, b.Y1) - math.max(a.Y0, b.Y0)
	return if w > 0 and h > 0 then w * h else 0
end

-- Le centre du ✕ de `w` est-il caché par une fenêtre plus récente ?
function PopupLogic.Covered(sim: State, w: Window): boolean
	local cx, cy = PopupLogic.CloseCenter(w)
	for _, other in sim.Windows do
		if other.Z > w.Z and inside(PopupLogic.Bounds(other), cx, cy) then
			return true
		end
	end
	return false
end

-- Fenêtre la plus haute (nil si l'écran est vide).
function PopupLogic.Top(sim: State): Window?
	local top: Window? = nil
	for _, w in sim.Windows do
		if not top or w.Z > top.Z then
			top = w
		end
	end
	return top
end

function PopupLogic.Find(sim: State, id: number): Window?
	for _, w in sim.Windows do
		if w.Id == id then
			return w
		end
	end
	return nil
end

------------------------------------------------------------------------------------
-- Déroulement
------------------------------------------------------------------------------------

local function clampWindow(w: Window)
	local edge = PopupLogic.EDGE
	w.X = math.clamp(w.X, w.W / 2 + edge, Core.FIELD_W - w.W / 2 - edge)
	w.Y = math.clamp(w.Y, w.H / 2 + edge, PopupLogic.AREA_BOTTOM - w.H / 2)
end

local function finish(sim: State, events: { Event }, success: boolean, reason: string?)
	sim.Done = true
	sim.Success = success
	table.insert(events, { Kind = if success then "Win" else "Lose", Id = 0, Reason = reason })
end

-- Ouvre une pub. `parent` : pub qui se dédouble (la copie apparaît à côté).
local function spawn(sim: State, events: { Event }, parent: Window?): Window?
	local p = sim.Params
	if #sim.Windows >= p.MaxOpen then
		return nil
	end
	local rng = sim.Rng
	local edge = PopupLogic.EDGE
	-- Plusieurs positions candidates : on garde celle qui cache le moins de ✕ déjà là.
	local bestX, bestY, bestScore = 0, 0, math.huge
	for attempt = 1, 10 do
		local x, y
		if parent and attempt <= 5 then
			local angle = rng:Range(0, math.pi * 2)
			x = parent.X + math.cos(angle) * p.W * 0.45
			y = parent.Y + math.sin(angle) * p.H * 0.45
		else
			x = rng:Range(p.W / 2 + edge, Core.FIELD_W - p.W / 2 - edge)
			y = rng:Range(p.H / 2 + edge, PopupLogic.AREA_BOTTOM - p.H / 2)
		end
		x = math.clamp(x, p.W / 2 + edge, Core.FIELD_W - p.W / 2 - edge)
		y = math.clamp(y, p.H / 2 + edge, PopupLogic.AREA_BOTTOM - p.H / 2)
		local rect = { X0 = x - p.W / 2, Y0 = y - p.H / 2, X1 = x + p.W / 2, Y1 = y + p.H / 2 }
		local score = 0
		for _, other in sim.Windows do
			local cx, cy = PopupLogic.CloseCenter(other)
			if inside(rect, cx, cy) then
				score += 1000
			end
			score += overlap(rect, PopupLogic.Bounds(other)) / (p.W * p.H) * 100
		end
		if score < bestScore then
			bestX, bestY, bestScore = x, y, score
		end
	end
	local decoys: { number } = {}
	if rng:Chance(p.DecoyChance) then
		table.insert(decoys, rng:Int(1, #PopupLogic.DECOY_LABELS))
		if rng:Chance(p.DoubleDecoyChance) then
			local second = rng:Int(1, #PopupLogic.DECOY_LABELS - 1)
			if second >= decoys[1] then
				second += 1
			end
			table.insert(decoys, second)
		end
	end
	local vx, vy = 0, 0
	if p.MoveSpeed > 0 and rng:Chance(p.MoveChance) then
		local angle = rng:Range(0, math.pi * 2)
		vx, vy = math.cos(angle) * p.MoveSpeed, math.sin(angle) * p.MoveSpeed
	end
	local w: Window = {
		Id = sim.NextId,
		X = bestX,
		Y = bestY,
		W = p.W,
		H = p.H,
		Z = sim.NextZ,
		Age = 0,
		Life = 0,
		CloseLeft = rng:Chance(p.LeftCloseChance),
		Decoys = decoys,
		Style = rng:Int(1, PopupLogic.STYLES),
		Vx = vx,
		Vy = vy,
	}
	sim.NextId += 1
	sim.NextZ += 1
	table.insert(sim.Windows, w)
	table.insert(events, {
		Kind = if parent then "Split" else "Spawn",
		Id = w.Id,
		Parent = if parent then parent.Id else nil,
		X = w.X,
		Y = w.Y,
	})
	return w
end

local function removeWindow(sim: State, id: number): Window?
	for i, w in sim.Windows do
		if w.Id == id then
			table.remove(sim.Windows, i)
			return w
		end
	end
	return nil
end

function PopupLogic.Step(sim: State, dt: number): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	dt = math.clamp(dt, 0, Core.MAX_STEP)
	sim.Time += dt
	local p = sim.Params

	-- 1. Nouvelles pubs
	if sim.Time >= sim.NextSpawn then
		spawn(sim, events, nil)
		sim.NextSpawn = sim.Time + p.SpawnEvery * sim.Rng:Range(0.8, 1.2)
	end

	-- 2. Pubs qui se promènent (rebond sur les bords) et qui se dédoublent
	local edge = PopupLogic.EDGE
	for i = 1, #sim.Windows do
		local w = sim.Windows[i]
		if w.Vx ~= 0 or w.Vy ~= 0 then
			w.X += w.Vx * dt
			w.Y += w.Vy * dt
			if w.X - w.W / 2 < edge or w.X + w.W / 2 > Core.FIELD_W - edge then
				w.Vx = -w.Vx
			end
			if w.Y - w.H / 2 < edge or w.Y + w.H / 2 > PopupLogic.AREA_BOTTOM then
				w.Vy = -w.Vy
			end
			clampWindow(w)
		end
		w.Age += dt
		w.Life += dt
		if w.Age >= p.SplitAfter then
			w.Age = 0
			spawn(sim, events, w)
		end
	end

	-- 3. RAM
	local open = #sim.Windows
	if open > 0 then
		sim.Ram += p.Load * open * dt
	else
		sim.Ram = math.max(0, sim.Ram - p.Drain * dt)
	end

	-- 4. Fin de partie
	if sim.Ram >= 1 then
		sim.Ram = 1
		finish(sim, events, false, "Ram")
	elseif sim.Time >= PopupLogic.MAX_TIME then
		finish(sim, events, false, "Time")
	end
	return events
end

-- Ferme la fenêtre `id` (✕ touché).
function PopupLogic.Close(sim: State, id: number): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	local w = removeWindow(sim, id)
	if not w then
		return events
	end
	sim.Closed += 1
	table.insert(events, { Kind = "Close", Id = w.Id, X = w.X, Y = w.Y })
	if sim.Closed >= sim.Params.Target then
		finish(sim, events, true)
	end
	return events
end

-- Faux bouton `which` de la fenêtre `id` touché : une pub de plus et de la RAM en moins.
function PopupLogic.Decoy(sim: State, id: number, which: number): { Event }
	local events: { Event } = {}
	local w = PopupLogic.Find(sim, id)
	if sim.Done or not w or not w.Decoys[which] then
		return events
	end
	sim.Decoys += 1
	sim.Ram = math.min(1, sim.Ram + sim.Params.DecoyPenalty)
	local x, y = w.X, w.Y
	local rects = PopupLogic.DecoyRects(w)
	local r = rects[which]
	if r then
		x, y = (r.X0 + r.X1) / 2, (r.Y0 + r.Y1) / 2
	end
	table.insert(events, {
		Kind = "Decoy",
		Id = w.Id,
		Label = PopupLogic.DECOY_LABELS[w.Decoys[which]],
		X = x,
		Y = y,
	})
	w.Age = 0
	spawn(sim, events, w)
	if sim.Ram >= 1 then
		finish(sim, events, false, "Ram")
	end
	return events
end

-- Appui au point (x, y) du terrain : la fenêtre la plus haute sous le doigt réagit.
function PopupLogic.PressAt(sim: State, x: number, y: number): { Event }
	if sim.Done then
		return {}
	end
	local hit: Window? = nil
	for _, w in sim.Windows do
		if inside(PopupLogic.Bounds(w), x, y) and (not hit or w.Z > hit.Z) then
			hit = w
		end
	end
	if not hit then
		return {}
	end
	if inside(PopupLogic.CloseRect(hit), x, y) then
		return PopupLogic.Close(sim, hit.Id)
	end
	for index, rect in PopupLogic.DecoyRects(hit) do
		if inside(rect, x, y) then
			return PopupLogic.Decoy(sim, hit.Id, index)
		end
	end
	return { { Kind = "Body", Id = hit.Id, X = x, Y = y } }
end

-- Manette / clavier : ferme la pub du dessus.
function PopupLogic.CloseTop(sim: State): { Event }
	local top = PopupLogic.Top(sim)
	if not top then
		return {}
	end
	return PopupLogic.Close(sim, top.Id)
end

return table.freeze(PopupLogic)
