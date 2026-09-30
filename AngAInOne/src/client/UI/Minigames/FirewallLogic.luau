--!strict
--[[
	FirewallLogic : règles PURES du mini-jeu "Firewall" (testables dans Lune).

	Un bouclier pare-feu glisse en bas du terrain et tire tout seul vers le haut.
	Des virus tombent : il faut en détruire `Target` avant que `Lives` virus n'atteignent
	le bas (ou avant la fin du chrono). Un virus qui percute le bouclier est détruit.

	Combat final (difficulté 8, Core.IsBoss) : LAGZ flotte en haut de l'écran et crache
	les virus. Les tirs qui l'atteignent lui retirent des PV (barre de vie du boss au lieu
	du compteur de virus) ; de temps en temps il glitche et se protège d'une bulle
	(tirs bloqués). À mi-vie, il s'énerve : il bouge et tire plus vite. Gagné quand ses PV
	tombent à zéro ; perdu si `Lives` virus passent ou à la fin du chrono.

	Entrées (fournies par l'interface à chaque image) :
		FirewallLogic.SetAxis(sim, -1..1)     -- clavier / manette
		FirewallLogic.SetPointer(sim, x?)     -- doigt / souris (nil = relâché)
]]

local Core = require(script.Parent.Core)

local FirewallLogic = {}

export type Params = {
	Target: number, -- virus à détruire
	Lives: number, -- virus qui peuvent passer avant de perdre
	Duration: number,
	SpawnEvery: number,
	FallSpeed: number, -- unités/s
	Radius: number, -- rayon des virus (unités)
	Wobble: number, -- amplitude du zigzag horizontal (0 = chute droite)
	ToughChance: number, -- probabilité d'un virus casqué (2 tirs)
	FireEvery: number, -- cadence de tir automatique
	-- Combat final uniquement
	BossHp: number?, -- PV de LAGZ
	BossSpeed: number?, -- vitesse de balancement (rad/s)
	BossRange: number?, -- amplitude du balancement (unités)
}

local ROWS: { Params } = {
	{
		Target = 10,
		Lives = 5,
		Duration = 45,
		SpawnEvery = 1.5,
		FallSpeed = 75,
		Radius = 38,
		Wobble = 0,
		ToughChance = 0,
		FireEvery = 0.25,
	},
	{
		Target = 12,
		Lives = 5,
		Duration = 45,
		SpawnEvery = 1.35,
		FallSpeed = 85,
		Radius = 36,
		Wobble = 0,
		ToughChance = 0,
		FireEvery = 0.25,
	},
	{
		Target = 14,
		Lives = 4,
		Duration = 45,
		SpawnEvery = 1.2,
		FallSpeed = 95,
		Radius = 35,
		Wobble = 20,
		ToughChance = 0,
		FireEvery = 0.26,
	},
	{
		Target = 16,
		Lives = 4,
		Duration = 42,
		SpawnEvery = 1.05,
		FallSpeed = 105,
		Radius = 34,
		Wobble = 35,
		ToughChance = 0.1,
		FireEvery = 0.27,
	},
	{
		Target = 18,
		Lives = 4,
		Duration = 42,
		SpawnEvery = 0.95,
		FallSpeed = 118,
		Radius = 33,
		Wobble = 50,
		ToughChance = 0.15,
		FireEvery = 0.28,
	},
	{
		Target = 20,
		Lives = 3,
		Duration = 40,
		SpawnEvery = 0.85,
		FallSpeed = 130,
		Radius = 32,
		Wobble = 60,
		ToughChance = 0.2,
		FireEvery = 0.29,
	},
	{
		Target = 22,
		Lives = 3,
		Duration = 40,
		SpawnEvery = 0.75,
		FallSpeed = 142,
		Radius = 31,
		Wobble = 70,
		ToughChance = 0.25,
		FireEvery = 0.3,
	},
}

-- Combat final contre LAGZ : plus dur que le niveau 7 mais juste (une vie de plus).
local BOSS: Params = {
	Target = 36, -- = BossHp (objectif affiché)
	Lives = 4,
	Duration = 75,
	SpawnEvery = 1.0,
	FallSpeed = 125,
	Radius = 32,
	Wobble = 35,
	ToughChance = 0.15,
	FireEvery = 0.24,
	BossHp = 36,
	BossSpeed = 0.75,
	BossRange = 290,
}

FirewallLogic.BOSS_Y = 92 -- centre de la tête de LAGZ
FirewallLogic.BOSS_RADIUS = 74
FirewallLogic.BOSS_SHIELD_EVERY = 7 -- secondes (en moyenne) entre deux bulles
FirewallLogic.BOSS_SHIELD_TIME = 1.4
FirewallLogic.BOSS_RAGE = 0.5 -- fraction de PV sous laquelle LAGZ s'énerve

FirewallLogic.SHIELD_Y = Core.FIELD_H - 70 -- centre du bouclier (les fichiers à protéger sont dessous)
FirewallLogic.SHIELD_HALF_W = 62
FirewallLogic.SHIELD_HALF_H = 18
FirewallLogic.MOVE_SPEED = 640 -- clavier / manette (unités/s)
FirewallLogic.POINTER_SPEED = 1500 -- suivi du doigt / de la souris, lissé
FirewallLogic.BULLET_SPEED = 950
FirewallLogic.BULLET_RADIUS = 13 -- généreux : on touche facilement
FirewallLogic.FIRST_SPAWN = 0.8
FirewallLogic.EDGE = 24 -- marge latérale des apparitions

export type Virus = {
	Id: number,
	X: number,
	Y: number,
	BaseX: number,
	Phase: number,
	Hp: number,
	MaxHp: number,
	R: number,
}

export type Bullet = { Id: number, X: number, Y: number }

export type Boss = {
	Hp: number,
	MaxHp: number,
	X: number,
	Y: number,
	R: number,
	Swing: number, -- phase du balancement
	ShieldUntil: number, -- bulle active jusqu'à ce temps
	NextShield: number,
	Enraged: boolean,
}

export type Event = {
	Kind: "Spawn"
		| "Fire"
		| "BulletGone"
		| "Damage"
		| "Kill"
		| "Leak"
		| "BossHit"
		| "BossBlock"
		| "BossShield"
		| "BossRage"
		| "Win"
		| "Lose",
	Id: number, -- virus ou tir concerné (0 pour Win / Lose)
	X: number?,
	Y: number?,
	Blocked: boolean?, -- Kill : détruit par le bouclier lui-même
	Reason: string?, -- Lose : "Leaks" | "Time"
}

export type State = {
	Params: Params,
	Rng: Core.Rng,
	Time: number,
	ShieldX: number,
	Axis: number,
	Pointer: number?,
	Viruses: { Virus },
	Bullets: { Bullet },
	NextSpawn: number,
	NextFire: number,
	NextId: number,
	LastSpawnX: number,
	Kills: number,
	Leaks: number,
	Boss: Boss?, -- combat final uniquement
	Done: boolean,
	Success: boolean,
}

function FirewallLogic.Params(difficulty: number): Params
	if Core.IsBoss(difficulty) then
		return BOSS
	end
	return Core.Row(ROWS, difficulty)
end

function FirewallLogic.new(difficulty: number, seed: number): State
	local params = FirewallLogic.Params(difficulty)
	local boss: Boss? = nil
	local hp = params.BossHp
	if hp then
		boss = {
			Hp = hp,
			MaxHp = hp,
			X = Core.FIELD_W / 2,
			Y = FirewallLogic.BOSS_Y,
			R = FirewallLogic.BOSS_RADIUS,
			Swing = 0,
			ShieldUntil = 0,
			NextShield = FirewallLogic.BOSS_SHIELD_EVERY,
			Enraged = false,
		}
	end
	return {
		Params = params,
		Rng = Core.Rng(seed),
		Time = 0,
		ShieldX = Core.FIELD_W / 2,
		Axis = 0,
		Pointer = nil,
		Viruses = {},
		Bullets = {},
		NextSpawn = FirewallLogic.FIRST_SPAWN,
		NextFire = 0.3,
		NextId = 1,
		LastSpawnX = Core.FIELD_W / 2,
		Kills = 0,
		Leaks = 0,
		Boss = boss,
		Done = false,
		Success = false,
	}
end

function FirewallLogic.SetAxis(sim: State, axis: number)
	sim.Axis = math.clamp(axis, -1, 1)
	if sim.Axis ~= 0 then
		sim.Pointer = nil -- le clavier / la manette reprend la main
	end
end

function FirewallLogic.SetPointer(sim: State, x: number?)
	sim.Pointer = if x then math.clamp(x, 0, Core.FIELD_W) else nil
end

function FirewallLogic.LivesLeft(sim: State): number
	return math.max(0, sim.Params.Lives - sim.Leaks)
end

function FirewallLogic.TimeLeft(sim: State): number
	return math.max(0, sim.Params.Duration - sim.Time)
end

-- Score affiché : virus détruits, ou PV retirés à LAGZ pendant le combat final.
function FirewallLogic.Score(sim: State): number
	local boss = sim.Boss
	if boss then
		return boss.MaxHp - boss.Hp
	end
	return sim.Kills
end

function FirewallLogic.BossShielded(sim: State): boolean
	local boss = sim.Boss
	return boss ~= nil and sim.Time < boss.ShieldUntil
end

local function minX(): number
	return FirewallLogic.SHIELD_HALF_W
end

local function maxX(): number
	return Core.FIELD_W - FirewallLogic.SHIELD_HALF_W
end

-- Le bouclier touche-t-il ce cercle ? (rectangle arrondi approché par un rectangle)
local function touchesShield(sim: State, x: number, y: number, r: number): boolean
	local dx = math.max(math.abs(x - sim.ShieldX) - FirewallLogic.SHIELD_HALF_W, 0)
	local dy = math.max(math.abs(y - FirewallLogic.SHIELD_Y) - FirewallLogic.SHIELD_HALF_H, 0)
	return dx * dx + dy * dy <= r * r
end

local function spawnVirus(sim: State): Event
	local p = sim.Params
	local margin = FirewallLogic.EDGE + p.Radius + p.Wobble
	local x = sim.Rng:Range(margin, Core.FIELD_W - margin)
	local y = -p.Radius
	local boss = sim.Boss
	if boss then
		-- LAGZ crache le virus : il sort de sa bouche.
		x = math.clamp(boss.X + sim.Rng:Range(-40, 40), margin, Core.FIELD_W - margin)
		y = boss.Y + boss.R * 0.6
	elseif math.abs(x - sim.LastSpawnX) < 110 then
		-- Évite deux virus d'affilée au même endroit : on écarte le nouveau du précédent.
		x = if sim.LastSpawnX < Core.FIELD_W / 2 then x + 220 else x - 220
		x = math.clamp(x, margin, Core.FIELD_W - margin)
	end
	sim.LastSpawnX = x
	local tough = sim.Rng:Chance(p.ToughChance)
	local virus: Virus = {
		Id = sim.NextId,
		X = x,
		Y = y,
		BaseX = x,
		Phase = sim.Rng:Range(0, math.pi * 2),
		Hp = if tough then 2 else 1,
		MaxHp = if tough then 2 else 1,
		R = p.Radius,
	}
	sim.NextId += 1
	table.insert(sim.Viruses, virus)
	return { Kind = "Spawn", Id = virus.Id, X = virus.X, Y = virus.Y }
end

local function finish(sim: State, events: { Event }, success: boolean, reason: string?)
	sim.Done = true
	sim.Success = success
	table.insert(events, { Kind = if success then "Win" else "Lose", Id = 0, Reason = reason })
end

function FirewallLogic.Step(sim: State, dt: number): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	dt = math.clamp(dt, 0, Core.MAX_STEP)
	sim.Time += dt
	local p = sim.Params

	-- 1. Bouclier
	local pointer = sim.Pointer
	if pointer then
		local delta =
			math.clamp(pointer - sim.ShieldX, -FirewallLogic.POINTER_SPEED * dt, FirewallLogic.POINTER_SPEED * dt)
		sim.ShieldX += delta
	else
		sim.ShieldX += sim.Axis * FirewallLogic.MOVE_SPEED * dt
	end
	sim.ShieldX = math.clamp(sim.ShieldX, minX(), maxX())

	-- 2. Tir automatique
	if sim.Time >= sim.NextFire then
		sim.NextFire = sim.Time + p.FireEvery
		local bullet = {
			Id = sim.NextId,
			X = sim.ShieldX,
			Y = FirewallLogic.SHIELD_Y - FirewallLogic.SHIELD_HALF_H,
		}
		sim.NextId += 1
		table.insert(sim.Bullets, bullet)
		table.insert(events, { Kind = "Fire", Id = bullet.Id, X = bullet.X, Y = bullet.Y })
	end

	-- 3. LAGZ (combat final) puis apparitions
	local boss = sim.Boss
	if boss then
		local speed = (p.BossSpeed or 0) * (if boss.Enraged then 1.4 else 1)
		boss.Swing += speed * dt
		boss.X = Core.FIELD_W / 2 + math.sin(boss.Swing) * (p.BossRange or 0)
		if sim.Time >= boss.NextShield then
			boss.ShieldUntil = sim.Time + FirewallLogic.BOSS_SHIELD_TIME
			boss.NextShield = sim.Time + FirewallLogic.BOSS_SHIELD_EVERY * sim.Rng:Range(0.8, 1.2)
			table.insert(events, { Kind = "BossShield", Id = 0, X = boss.X, Y = boss.Y })
		end
	end
	if sim.Time >= sim.NextSpawn then
		table.insert(events, spawnVirus(sim))
		local rage = if boss and boss.Enraged then 0.8 else 1
		sim.NextSpawn = sim.Time + p.SpawnEvery * rage * sim.Rng:Range(0.8, 1.2)
	end

	-- 4. Déplacements
	for i = #sim.Bullets, 1, -1 do
		local bullet = sim.Bullets[i]
		bullet.Y -= FirewallLogic.BULLET_SPEED * dt
		if bullet.Y < -20 then
			table.remove(sim.Bullets, i)
			table.insert(events, { Kind = "BulletGone", Id = bullet.Id })
		end
	end
	for _, virus in sim.Viruses do
		virus.Y += p.FallSpeed * dt
		if p.Wobble > 0 then
			virus.X = virus.BaseX + math.sin(sim.Time * 2.2 + virus.Phase) * p.Wobble
		end
	end

	-- 5. Collisions tirs / virus
	for i = #sim.Viruses, 1, -1 do
		local virus = sim.Viruses[i]
		local dead = false
		for j = #sim.Bullets, 1, -1 do
			local bullet = sim.Bullets[j]
			local dx, dy = bullet.X - virus.X, bullet.Y - virus.Y
			local reach = virus.R + FirewallLogic.BULLET_RADIUS
			if dx * dx + dy * dy <= reach * reach then
				table.remove(sim.Bullets, j)
				table.insert(events, { Kind = "BulletGone", Id = bullet.Id, X = bullet.X, Y = bullet.Y })
				virus.Hp -= 1
				if virus.Hp <= 0 then
					dead = true
					break
				end
				table.insert(events, { Kind = "Damage", Id = virus.Id, X = virus.X, Y = virus.Y })
			end
		end
		local blocked = not dead and touchesShield(sim, virus.X, virus.Y, virus.R * 0.8)
		if dead or blocked then
			table.remove(sim.Viruses, i)
			sim.Kills += 1
			table.insert(events, { Kind = "Kill", Id = virus.Id, X = virus.X, Y = virus.Y, Blocked = blocked })
		elseif virus.Y - virus.R > Core.FIELD_H then
			table.remove(sim.Viruses, i)
			sim.Leaks += 1
			table.insert(events, { Kind = "Leak", Id = virus.Id, X = virus.X, Y = Core.FIELD_H })
		end
	end

	-- 6. Tirs qui atteignent LAGZ
	if boss then
		local shielded = sim.Time < boss.ShieldUntil
		for j = #sim.Bullets, 1, -1 do
			local bullet = sim.Bullets[j]
			local dx, dy = bullet.X - boss.X, bullet.Y - boss.Y
			local reach = boss.R + FirewallLogic.BULLET_RADIUS
			if dx * dx + dy * dy <= reach * reach and boss.Hp > 0 then
				table.remove(sim.Bullets, j)
				table.insert(events, { Kind = "BulletGone", Id = bullet.Id, X = bullet.X, Y = bullet.Y })
				if shielded then
					table.insert(events, { Kind = "BossBlock", Id = 0, X = bullet.X, Y = bullet.Y })
				else
					boss.Hp -= 1
					table.insert(events, { Kind = "BossHit", Id = 0, X = bullet.X, Y = bullet.Y })
					if not boss.Enraged and boss.Hp > 0 and boss.Hp <= boss.MaxHp * FirewallLogic.BOSS_RAGE then
						boss.Enraged = true
						table.insert(events, { Kind = "BossRage", Id = 0, X = boss.X, Y = boss.Y })
					end
				end
			end
		end
	end

	-- 7. Fin de partie
	if boss then
		if boss.Hp <= 0 then
			finish(sim, events, true)
		elseif sim.Leaks >= p.Lives then
			finish(sim, events, false, "Leaks")
		elseif sim.Time >= p.Duration then
			finish(sim, events, false, "Time")
		end
	elseif sim.Kills >= p.Target then
		finish(sim, events, true)
	elseif sim.Leaks >= p.Lives then
		finish(sim, events, false, "Leaks")
	elseif sim.Time >= p.Duration then
		finish(sim, events, false, "Time")
	end
	return events
end

return table.freeze(FirewallLogic)
