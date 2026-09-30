--!strict
--[[
	DodgeLogic : règles PURES du mini-jeu "Dodge" (testables dans Lune).

	Un paquet de données avance tout seul vers la droite. Chaque appui le fait monter
	(façon Flappy, mais doux) ; il faut passer dans les trous des murs de virus jusqu'à
	la ligne d'arrivée. Toucher un mur coûte une vie (puis un court instant d'invincibilité) ;
	le sol et le plafond ne font jamais mal.

	Rien ne bouge avant le premier appui : l'enfant commence quand il est prêt.
]]

local Core = require(script.Parent.Core)

local DodgeLogic = {}

export type Params = {
	Speed: number, -- défilement (unités/s)
	Gravity: number, -- unités/s²
	Jump: number, -- vitesse verticale donnée par un appui
	MaxFall: number, -- vitesse de chute maximale
	Gap: number, -- hauteur du trou dans un mur
	Spacing: number, -- distance entre deux murs
	Walls: number, -- murs à passer
	Lives: number,
	MaxShift: number, -- écart vertical maximal entre deux trous successifs
}

local ROWS: { Params } = {
	{
		Speed = 170,
		Gravity = 700,
		Jump = 300,
		MaxFall = 300,
		Gap = 240,
		Spacing = 440,
		Walls = 8,
		Lives = 5,
		MaxShift = 110,
	},
	{
		Speed = 185,
		Gravity = 760,
		Jump = 315,
		MaxFall = 330,
		Gap = 225,
		Spacing = 420,
		Walls = 9,
		Lives = 5,
		MaxShift = 130,
	},
	{
		Speed = 200,
		Gravity = 820,
		Jump = 330,
		MaxFall = 360,
		Gap = 210,
		Spacing = 400,
		Walls = 10,
		Lives = 4,
		MaxShift = 150,
	},
	{
		Speed = 215,
		Gravity = 880,
		Jump = 345,
		MaxFall = 390,
		Gap = 195,
		Spacing = 380,
		Walls = 12,
		Lives = 4,
		MaxShift = 165,
	},
	{
		Speed = 230,
		Gravity = 940,
		Jump = 360,
		MaxFall = 420,
		Gap = 182,
		Spacing = 360,
		Walls = 13,
		Lives = 3,
		MaxShift = 180,
	},
	{
		Speed = 245,
		Gravity = 1000,
		Jump = 375,
		MaxFall = 450,
		Gap = 170,
		Spacing = 345,
		Walls = 14,
		Lives = 3,
		MaxShift = 195,
	},
	{
		Speed = 260,
		Gravity = 1060,
		Jump = 390,
		MaxFall = 480,
		Gap = 160,
		Spacing = 330,
		Walls = 16,
		Lives = 2,
		MaxShift = 210,
	},
}

DodgeLogic.PACKET_X = 220 -- position fixe du paquet à l'écran
DodgeLogic.HIT_RADIUS = 17 -- hitbox indulgente (le dessin fait ~30 de rayon)
DodgeLogic.WALL_HALF_W = 30 -- demi-largeur de collision d'un mur (dessin : ~44)
DodgeLogic.FIRST_WALL = 700 -- distance du premier mur (en unités de monde)
DodgeLogic.MARGIN = 34 -- marge haut/bas minimale des trous
DodgeLogic.INVULNERABLE = 1.4 -- secondes d'invincibilité après un choc

export type Wall = { Index: number, X: number, GapY: number, Passed: boolean }

export type Event = {
	Kind: "Start" | "Jump" | "Hit" | "Pass" | "Win" | "Lose",
	Wall: number?, -- index du mur (Hit / Pass)
}

export type State = {
	Params: Params,
	Rng: Core.Rng,
	Started: boolean,
	Time: number,
	Distance: number, -- position du paquet dans le monde (x)
	Goal: number, -- distance de la ligne d'arrivée
	Y: number,
	Vy: number,
	Walls: { Wall },
	Passed: number,
	Hits: number,
	Invulnerable: number,
	Done: boolean,
	Success: boolean,
}

function DodgeLogic.Params(difficulty: number): Params
	return Core.Row(ROWS, difficulty)
end

function DodgeLogic.new(difficulty: number, seed: number): State
	local params = DodgeLogic.Params(difficulty)
	local rng = Core.Rng(seed)
	local walls: { Wall } = {}
	local low = DodgeLogic.MARGIN + params.Gap / 2
	local high = Core.FIELD_H - DodgeLogic.MARGIN - params.Gap / 2
	local gapY = Core.FIELD_H / 2
	for i = 1, params.Walls do
		if i > 1 then
			gapY = math.clamp(gapY + rng:Range(-params.MaxShift, params.MaxShift), low, high)
		end
		table.insert(walls, {
			Index = i,
			X = DodgeLogic.FIRST_WALL + (i - 1) * params.Spacing,
			GapY = gapY,
			Passed = false,
		})
	end
	return {
		Params = params,
		Rng = rng,
		Started = false,
		Time = 0,
		Distance = DodgeLogic.PACKET_X,
		Goal = walls[#walls].X + params.Spacing * 0.8,
		Y = Core.FIELD_H / 2,
		Vy = 0,
		Walls = walls,
		Passed = 0,
		Hits = 0,
		Invulnerable = 0,
		Done = false,
		Success = false,
	}
end

function DodgeLogic.LivesLeft(sim: State): number
	return math.max(0, sim.Params.Lives - sim.Hits)
end

function DodgeLogic.Progress(sim: State): number
	return math.clamp((sim.Distance - DodgeLogic.PACKET_X) / (sim.Goal - DodgeLogic.PACKET_X), 0, 1)
end

-- Secondes restantes avant la ligne d'arrivée (défilement constant).
function DodgeLogic.TimeLeft(sim: State): number
	return math.max(0, sim.Goal - sim.Distance) / sim.Params.Speed
end

-- Position d'un mur à l'écran (unités du terrain).
function DodgeLogic.ScreenX(sim: State, worldX: number): number
	return worldX - sim.Distance + DodgeLogic.PACKET_X
end

-- Prochain mur à franchir (ou nil).
function DodgeLogic.NextWall(sim: State): Wall?
	for _, wall in sim.Walls do
		if wall.X + DodgeLogic.WALL_HALF_W + DodgeLogic.HIT_RADIUS >= sim.Distance then
			return wall
		end
	end
	return nil
end

-- Appui : le paquet monte (et la partie démarre au premier appui).
function DodgeLogic.Flap(sim: State): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	if not sim.Started then
		sim.Started = true
		table.insert(events, { Kind = "Start" })
	end
	sim.Vy = -sim.Params.Jump
	table.insert(events, { Kind = "Jump" })
	return events
end

-- Le cercle (px, py, r) touche-t-il le rectangle [left, right] x [top, bottom] ?
local function circleHitsRect(
	px: number,
	py: number,
	r: number,
	left: number,
	right: number,
	top: number,
	bottom: number
): boolean
	local dx = px - math.clamp(px, left, right)
	local dy = py - math.clamp(py, top, bottom)
	return dx * dx + dy * dy <= r * r
end

-- Collision avec les deux blocs d'un mur (au-dessus et au-dessous du trou).
local function collides(sim: State, wall: Wall): boolean
	local r = DodgeLogic.HIT_RADIUS
	local left = wall.X - DodgeLogic.WALL_HALF_W
	local right = wall.X + DodgeLogic.WALL_HALF_W
	local gapTop = wall.GapY - sim.Params.Gap / 2
	local gapBottom = wall.GapY + sim.Params.Gap / 2
	return circleHitsRect(sim.Distance, sim.Y, r, left, right, -math.huge, gapTop)
		or circleHitsRect(sim.Distance, sim.Y, r, left, right, gapBottom, math.huge)
end

function DodgeLogic.Step(sim: State, dt: number): { Event }
	local events: { Event } = {}
	if sim.Done or not sim.Started then
		return events
	end
	dt = math.clamp(dt, 0, Core.MAX_STEP)
	local p = sim.Params
	sim.Time += dt
	sim.Distance += p.Speed * dt
	sim.Vy = math.min(sim.Vy + p.Gravity * dt, p.MaxFall)
	sim.Y += sim.Vy * dt
	-- Sol et plafond : on glisse, sans dégât.
	local r = DodgeLogic.HIT_RADIUS
	if sim.Y < r then
		sim.Y = r
		sim.Vy = math.max(sim.Vy, 0)
	elseif sim.Y > Core.FIELD_H - r then
		sim.Y = Core.FIELD_H - r
		sim.Vy = math.min(sim.Vy, 0)
	end
	sim.Invulnerable = math.max(0, sim.Invulnerable - dt)

	for _, wall in sim.Walls do
		if not wall.Passed then
			if sim.Invulnerable <= 0 and collides(sim, wall) then
				sim.Hits += 1
				sim.Invulnerable = DodgeLogic.INVULNERABLE
				table.insert(events, { Kind = "Hit", Wall = wall.Index })
				if DodgeLogic.LivesLeft(sim) <= 0 then
					sim.Done = true
					sim.Success = false
					table.insert(events, { Kind = "Lose" })
					return events
				end
			end
			if sim.Distance - r > wall.X + DodgeLogic.WALL_HALF_W then
				wall.Passed = true
				sim.Passed += 1
				table.insert(events, { Kind = "Pass", Wall = wall.Index })
			end
		end
	end

	if sim.Distance >= sim.Goal then
		sim.Done = true
		sim.Success = true
		table.insert(events, { Kind = "Win" })
	end
	return events
end

return table.freeze(DodgeLogic)
