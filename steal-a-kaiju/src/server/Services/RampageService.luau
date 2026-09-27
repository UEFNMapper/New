--!nonstrict
-- RAMPAGE : le joueur devient une copie géante d'un de ses kaijus et écrase une
-- ville-jouet privée pendant 75 s (piétinement, rayon rugissant, écrasement
-- passif, combos, tanks-jouets). L'original reste sur son nid et continue de
-- rapporter. Récompenses : cash (secondes de revenu), croissance du kaiju
-- utilisé, étoiles (gemmes, XP, déblocage du quartier suivant), œuf possible
-- dans l'immeuble doré.
--
-- Le serveur possède la ville, le chrono, le combo, les tanks et les
-- fléchettes ; chaque coup est vérifié avec la position serveur du personnage.
-- Le client (RampageController) ne fait que l'affichage et envoie les entrées.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rampage = require(Shared.Config.Rampage)
local Growth = require(Shared.Config.Growth)
local Levels = require(Shared.Config.Levels)
local Economy = require(Shared.Config.Economy)
local Tutorial = require(Shared.Config.Tutorial)
local Calc = require(Shared.Logic.Calc)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local CityBuilder = require(script.Parent.Parent.World.CityBuilder)

local RampageService = {}

type Tank = {
	Id: number,
	From: Vector3,
	To: Vector3,
	T0: number,
	Speed: number,
	HP: number,
	MaxHP: number,
	NextFire: number,
	Alive: boolean,
}

type Dart = {
	Id: number,
	From: Vector3,
	To: Vector3,
	T1: number,
}

type Run = {
	Player: Player,
	Uid: string,
	Species: string,
	Mutation: string?,
	Stage: number,
	Scale: number,
	Power: number,
	District: Rampage.District,
	City: CityBuilder.City,
	Rng: Random,
	StartAt: number,
	EndsAt: number,
	Smashed: number,
	DestroyedHP: number,
	Points: number,
	Cash: number,
	Combo: number,
	LastSmash: number,
	Stars: number,
	Egg: string?,
	Tanks: { Tank },
	Darts: { Dart },
	TankCount: number,
	NextTank: number,
	NextId: number,
	LastStomp: number,
	LastRoar: number,
	LastPos: Vector3?,
	LastCheck: number,
	SuspectUntil: number,
	Hidden: { [Instance]: number },
	Humanoid: Humanoid?,
	Jump: { Power: number, Height: number },
	DiedConn: RBXScriptConnection?,
	Ending: boolean,
	Easy: boolean,
}

local runs: { [Player]: Run } = {}
local readyAt: { [Player]: number } = {}
local openDebounce: { [Player]: number } = {}
local onPad: { [Player]: boolean } = {}
local portals: { [number]: BasePart } = {} -- index d'île -> pièce touchable
local runCounter = 0

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Distance horizontale d'un point à l'emprise au sol d'un immeuble.
local function footprintDistance(b: CityBuilder.Building, pos: Vector3): number
	local dx = math.max(math.abs(pos.X - b.Position.X) - b.HalfX, 0)
	local dz = math.max(math.abs(pos.Z - b.Position.Z) - b.HalfZ, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Données Rampage complètes (tableau d'étoiles sans trou, sûr pour la sauvegarde).
local function ensureData(data: any): any
	data.Rampage = data.Rampage or { Stars = {}, Best = 0, Runs = 0 }
	local r = data.Rampage
	r.Stars = r.Stars or {}
	for i = 1, #Rampage.Districts do
		r.Stars[i] = r.Stars[i] or 0
	end
	r.Best = r.Best or 0
	r.Runs = r.Runs or 0
	return r
end

function RampageService.IsActive(player: Player): boolean
	return runs[player] ~= nil
end

----------------------------------------------------------------------------
-- Récompenses en cours de partie
----------------------------------------------------------------------------

local function destruction(run: Run): number
	return run.DestroyedHP / math.max(run.City.TotalHP, 1)
end

local function flattened(run: Run): boolean
	return run.Smashed >= #run.City.Buildings
end

-- Ajoute un « coup » au combo et renvoie (multiplicateur, cash, points).
local function scoreHit(run: Run, value: number): (number, number, number)
	local now = serverNow()
	if run.LastSmash > 0 and now - run.LastSmash <= Rampage.Combo.Window then
		run.Combo += 1
	else
		run.Combo = 0
	end
	run.LastSmash = now
	local mult = Rampage.ComboMult(run.Combo)
	local points = value * mult * run.District.RewardMult
	local minCash = points * Rampage.MinCashPerPoint * run.District.Index
	local cash = Registry.KaijuService.IncomeSeconds(run.Player, points, minCash)
	run.Points += points
	run.Cash += cash
	return mult, cash, points
end

local function pickEgg(district: Rampage.District, rng: Random): string
	local total = 0
	for _, e in district.Egg do
		total += e.Weight
	end
	local roll = rng:NextNumber() * total
	for _, e in district.Egg do
		roll -= e.Weight
		if roll <= 0 then
			return e.Rarity
		end
	end
	return district.Egg[1].Rarity
end

local function smash(run: Run, b: CityBuilder.Building, by: string)
	b.Alive = false
	b.HP = 0
	run.Smashed += 1
	run.DestroyedHP += b.MaxHP
	local mult, cash, points = scoreHit(run, b.Value)
	local egg = nil
	if b.Golden and run.Rng:NextNumber() < Rampage.GoldenEggChance then
		egg = pickEgg(run.District, run.Rng)
		run.Egg = egg
	end
	local size = Vector3.new(b.HalfX * 2, b.Height, b.HalfZ * 2)
	b.Model:Destroy()
	local part = destruction(run)
	Notify.Fx(run.Player, "RampageSmash", {
		Id = b.Id,
		Kind = b.Kind,
		Position = b.Position,
		Size = size,
		Color = b.Color,
		Golden = b.Golden,
		Egg = egg,
		Cash = cash,
		Points = points,
		Combo = mult,
		ComboCount = run.Combo,
		Destruction = part,
		Smashed = run.Smashed,
		By = by,
	})
	local stars = Rampage.StarsFor(part, flattened(run))
	if stars > run.Stars then
		run.Stars = stars
		Notify.Fx(run.Player, "RampageStar", { Stars = stars })
	end
end

local function damageBuilding(run: Run, b: CityBuilder.Building, damage: number, by: string)
	if not b.Alive then
		return
	end
	b.HP -= damage
	if b.HP <= 0 then
		smash(run, b, by)
	else
		b.Model:SetAttribute("HP", b.HP)
		Notify.Fx(run.Player, "RampageHit", { Id = b.Id, HP = b.HP, MaxHP = b.MaxHP, Position = b.Position, Height = b.Height })
	end
end

local function tankPosition(t: Tank, now: number): Vector3
	local len = (t.To - t.From).Magnitude
	if len < 0.01 then
		return t.To
	end
	local alpha = math.clamp((now - t.T0) * t.Speed / len, 0, 1)
	return t.From:Lerp(t.To, alpha)
end

local function damageTank(run: Run, t: Tank, damage: number)
	if not t.Alive then
		return
	end
	t.HP -= damage
	if t.HP > 0 then
		Notify.Fx(run.Player, "RampageTankHit", { Id = t.Id, HP = t.HP, MaxHP = t.MaxHP })
		return
	end
	t.Alive = false
	run.EndsAt += Rampage.Tanks.KillBonus
	local mult, cash = scoreHit(run, Rampage.Tanks.Value)
	Notify.Fx(run.Player, "RampageTankDown", {
		Id = t.Id,
		Position = tankPosition(t, serverNow()),
		Bonus = Rampage.Tanks.KillBonus,
		EndsAt = run.EndsAt,
		Cash = cash,
		Combo = mult,
	})
end

----------------------------------------------------------------------------
-- Actions du kaiju (position SERVEUR du personnage)
----------------------------------------------------------------------------

local endRun: (Player, string) -> ()

-- Renvoie la position utilisable pour une attaque, ou nil (partie finie, mort,
-- déplacement suspect).
local function attackPosition(player: Player, run: Run): Vector3?
	if run.Ending or os.clock() < run.SuspectUntil then
		return nil
	end
	local root = rootOf(player)
	local humanoid = humanoidOf(player)
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root.Position
end

local function afterAttack(run: Run)
	if flattened(run) then
		endRun(run.Player, "Flattened")
	end
end

local function stomp(player: Player)
	local run = runs[player]
	if not run then
		return
	end
	local now = os.clock()
	if now - run.LastStomp < Rampage.Stomp.Cooldown - Rampage.InputTolerance then
		return
	end
	local pos = attackPosition(player, run)
	if not pos then
		return
	end
	run.LastStomp = now
	local radius = Rampage.StompRadius(run.Scale)
	local damage = Rampage.Stomp.Damage * run.Power
	for _, b in run.City.Buildings do
		if b.Alive and footprintDistance(b, pos) <= radius then
			damageBuilding(run, b, damage, "Stomp")
		end
	end
	local t = serverNow()
	for _, tank in run.Tanks do
		if tank.Alive and (flat(tankPosition(tank, t)) - flat(pos)).Magnitude <= radius + Rampage.Tanks.Radius then
			damageTank(run, tank, damage)
		end
	end
	afterAttack(run)
end

-- Vrai si une cible de rayon `r` au point `target` est dans le cône.
local function inCone(pos: Vector3, dir: Vector3, target: Vector3, r: number, length: number, halfAngle: number): boolean
	local v = flat(target) - flat(pos)
	local d = v.Magnitude
	if d <= r + 1 then
		return true
	end
	if d - r > length then
		return false
	end
	local allowed = halfAngle + math.atan(r / d)
	return v.Unit:Dot(dir) >= math.cos(math.min(allowed, math.pi))
end

local function roar(player: Player, payload: any)
	local run = runs[player]
	if not run then
		return
	end
	local now = os.clock()
	if now - run.LastRoar < Rampage.Roar.Cooldown - Rampage.InputTolerance then
		return
	end
	local pos = attackPosition(player, run)
	local root = rootOf(player)
	if not pos or not root then
		return
	end
	-- direction : celle du client si valide (visée caméra), sinon le regard du personnage
	local dir = root.CFrame.LookVector
	if type(payload) == "table" and typeof(payload.Dir) == "Vector3" then
		local d = payload.Dir :: Vector3
		if d.Magnitude == d.Magnitude and d.Magnitude < 1e4 and flat(d).Magnitude > 0.05 then
			dir = d
		end
	end
	dir = flat(dir)
	if dir.Magnitude < 0.05 then
		return
	end
	dir = dir.Unit
	run.LastRoar = now
	local length = Rampage.RoarLength(run.Scale)
	local halfAngle = math.rad(Rampage.Roar.Angle / 2)
	local damage = Rampage.Roar.Damage * run.Power
	for _, b in run.City.Buildings do
		if b.Alive and footprintDistance(b, pos) <= length and inCone(pos, dir, b.Position, math.max(b.HalfX, b.HalfZ), length, halfAngle) then
			damageBuilding(run, b, damage, "Roar")
		end
	end
	local t = serverNow()
	for _, tank in run.Tanks do
		if tank.Alive and inCone(pos, dir, tankPosition(tank, t), Rampage.Tanks.Radius, length, halfAngle) then
			damageTank(run, tank, damage)
		end
	end
	afterAttack(run)
end

-- Écrasement passif : les immeubles assez faibles cèdent au contact.
local function crush(run: Run, pos: Vector3)
	local limit = Rampage.CrushMult * run.Power
	local reach = Rampage.CrushRadius(run.Scale)
	for _, b in run.City.Buildings do
		if b.Alive and b.HP <= limit and footprintDistance(b, pos) <= reach then
			smash(run, b, "Crush")
		end
	end
	local t = serverNow()
	for _, tank in run.Tanks do
		if tank.Alive and tank.HP <= limit and (flat(tankPosition(tank, t)) - flat(pos)).Magnitude <= reach + Rampage.Tanks.Radius then
			damageTank(run, tank, tank.HP)
		end
	end
end

----------------------------------------------------------------------------
-- Tanks-jouets et fléchettes (trajets déterministes)
----------------------------------------------------------------------------

local function spawnTank(run: Run, playerPos: Vector3, now: number)
	local cfg = Rampage.Tanks
	local origin = run.City.Origin
	local rel = flat(playerPos - origin)
	local roads = run.City.Roads
	local edge = roads[#roads]
	local best, bestScore = nil, math.huge
	-- extrémités de routes : on prend la route qui passe le plus près du joueur,
	-- depuis un bout assez loin pour que le tank soit visible en arrivant
	for _, r in roads do
		for _, s in { -1, 1 } do
			for _, alongX in { true, false } do
				local from = if alongX then Vector3.new(r, 0, s * edge) else Vector3.new(s * edge, 0, r)
				if (from - rel).Magnitude >= cfg.MinSpawnDistance then
					local lineDist = if alongX then math.abs(rel.X - r) else math.abs(rel.Z - r)
					local score = lineDist + run.Rng:NextNumber() * 10
					if score < bestScore then
						bestScore = score
						best = { from = from, alongX = alongX, r = r }
					end
				end
			end
		end
	end
	if not best then
		return
	end
	local from = best.from
	local proj = if best.alongX then Vector3.new(best.r, 0, math.clamp(rel.Z, -edge, edge)) else Vector3.new(math.clamp(rel.X, -edge, edge), 0, best.r)
	local toward = proj - from
	local to = from
	if toward.Magnitude > cfg.StopDistance then
		to = proj - toward.Unit * cfg.StopDistance
	end
	run.NextId += 1
	run.TankCount += 1
	local hp = math.floor(cfg.HP * run.District.HpMult * (if run.Easy then Rampage.TutorialHpMult else 1) + 0.5)
	local tank: Tank = {
		Id = run.NextId,
		From = origin + from,
		To = origin + to,
		T0 = now,
		Speed = cfg.Speed,
		HP = hp,
		MaxHP = hp,
		NextFire = now + (to - from).Magnitude / cfg.Speed + cfg.FireDelay,
		Alive = true,
	}
	table.insert(run.Tanks, tank)
	Notify.Fx(run.Player, "RampageTank", { Id = tank.Id, From = tank.From, To = tank.To, T0 = tank.T0, Speed = tank.Speed, HP = hp })
end

local function stepTanks(run: Run, pos: Vector3, now: number)
	local cfg = Rampage.Tanks
	local alive = 0
	for _, t in run.Tanks do
		if t.Alive then
			alive += 1
		end
	end
	if now - run.StartAt >= cfg.StartAt and now >= run.NextTank and alive < cfg.MaxAlive and run.TankCount < cfg.MaxTotal then
		run.NextTank = now + cfg.Interval
		spawnTank(run, pos, now)
	end
	-- tirs : la fléchette vise l'endroit où est le joueur au moment du tir
	for _, t in run.Tanks do
		if t.Alive and now >= t.NextFire then
			t.NextFire = now + cfg.FireEvery
			local tp = tankPosition(t, now)
			local target = Vector3.new(pos.X, run.City.Origin.Y, pos.Z)
			local dist = (flat(target) - flat(tp)).Magnitude
			if dist <= cfg.Range then
				run.NextId += 1
				local from = tp + Vector3.new(0, 2.5, 0)
				local t1 = now + math.max(cfg.DartMinTime, dist / cfg.DartSpeed)
				table.insert(run.Darts, { Id = run.NextId, From = from, To = target, T1 = t1 })
				Notify.Fx(run.Player, "RampageDart", { Id = run.NextId, From = from, To = target, T0 = now, T1 = t1 })
			end
		end
	end
	-- impacts
	local radius = Rampage.DartRadius(run.Scale)
	for i = #run.Darts, 1, -1 do
		local dart = run.Darts[i]
		if now >= dart.T1 then
			table.remove(run.Darts, i)
			if (flat(pos) - flat(dart.To)).Magnitude <= radius then
				run.EndsAt -= cfg.HitPenalty
				Notify.Fx(run.Player, "RampageDartHit", { Id = dart.Id, Position = dart.To, Penalty = cfg.HitPenalty, EndsAt = run.EndsAt })
			end
		end
	end
end

----------------------------------------------------------------------------
-- Fin de partie
----------------------------------------------------------------------------

local function grantRewards(player: Player, run: Run, reason: string): any
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local r = ensureData(data)
	local d = run.District.Index
	local part = destruction(run)
	local stars = Rampage.StarsFor(part, flattened(run))
	local before = r.Stars[d] or 0
	local newStars = math.max(0, stars - before)
	if stars > before then
		r.Stars[d] = stars
	end
	local unlocked = nil
	if before < Rampage.UnlockStars and stars >= Rampage.UnlockStars and d < #Rampage.Districts then
		unlocked = d + 1
	end
	local cash = math.floor(run.Cash)
	if cash > 0 then
		DataService.AddCash(player, cash)
	end
	local gems = newStars * Rampage.StarGems
	if gems > 0 then
		DataService.AddGems(player, gems)
	end
	-- croissance du kaiju utilisé (plafonnée : jamais de changement de stade d'un coup)
	local growth = 0
	local rec = Registry.KaijuService.FindRecord(data, run.Uid)
	if rec and not rec.Egg and run.Points > 0 then
		local remaining = Growth.Remaining(rec.Growth, rec.Rarity)
		growth = math.floor(math.min(run.Points, remaining * Rampage.GrowthCap))
		if growth > 0 then
			rec.Growth += growth
			Registry.KaijuService.SyncAnchor(player, rec)
			DataService.Replicate(player, "Kaijus")
		end
	end
	if run.Egg then
		Registry.KaijuService.GiveEgg(player, run.Egg, "Rampage")
	end
	local xp = stars * Levels.Xp.RampageStar
	if xp > 0 then
		Registry.LevelService.AddXp(player, xp, "Rampage")
	end
	r.Runs += 1
	local score = math.floor(run.Points)
	local newBest = score > r.Best
	if newBest then
		r.Best = score
	end
	DataService.Replicate(player, "Rampage")
	Registry.RewardService.Track(player, "Rampages", 1)
	if run.Smashed > 0 then
		Registry.RewardService.Track(player, "Smashed", run.Smashed)
	end
	return {
		Reason = reason,
		District = d,
		Uid = run.Uid,
		Species = run.Species,
		Mutation = run.Mutation,
		Stars = stars,
		NewStars = newStars,
		Destruction = part,
		Smashed = run.Smashed,
		Total = #run.City.Buildings,
		Cash = cash,
		Score = score,
		Best = r.Best,
		NewBest = newBest,
		Growth = growth,
		Gems = gems,
		Xp = xp,
		Egg = run.Egg,
		Unlocked = unlocked,
	}
end

local function restoreCharacter(run: Run)
	for inst, transparency in run.Hidden do
		if inst.Parent then
			(inst :: any).Transparency = transparency
		end
	end
	table.clear(run.Hidden)
	local humanoid = run.Humanoid
	if humanoid and humanoid.Parent then
		humanoid.JumpPower = run.Jump.Power
		humanoid.JumpHeight = run.Jump.Height
	end
end

local function cleanup(player: Player, run: Run, sendHome: boolean)
	if runs[player] ~= run then
		return
	end
	runs[player] = nil
	if run.DiedConn then
		run.DiedConn:Disconnect()
	end
	run.City.Model:Destroy()
	restoreCharacter(run)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute("Rampage", false)
	if sendHome then
		Registry.PlotService.SpawnAt(player)
	end
	Registry.StealService.RefreshSpeed(player)
	Notify.Fx(player, "RampageHome", {})
	Registry.TutorialService.Notify(player, "Rampage")
end

-- reason : Time | Flattened | Quit | Died | Left | Gone (a quitté le jeu)
endRun = function(player: Player, reason: string)
	local run = runs[player]
	if not run or run.Ending then
		return
	end
	run.Ending = true
	if reason == "Gone" then
		cleanup(player, run, false)
		return
	end
	local result = grantRewards(player, run, reason)
	local ready = serverNow() + Rampage.Cooldown
	readyAt[player] = ready
	player:SetAttribute("RampageReadyAt", ready)
	local delay = if reason == "Time" or reason == "Flattened" then Rampage.EndDelay else 0
	if result then
		result.ReadyAt = ready
		result.Delay = delay
		Notify.Fx(player, "RampageEnd", result)
	end
	if delay > 0 then
		local humanoid = humanoidOf(player)
		if humanoid then
			humanoid.WalkSpeed = 0 -- le kaiju prend la pose pendant la bannière
		end
		task.delay(delay, cleanup, player, run, true)
	else
		cleanup(player, run, reason ~= "Died")
	end
end

----------------------------------------------------------------------------
-- Lancement
----------------------------------------------------------------------------

local function hideCharacter(run: Run, character: Model)
	for _, inst in character:GetDescendants() do
		if (inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart") or inst:IsA("Decal") then
			local obj = inst :: any
			run.Hidden[inst] = obj.Transparency
			obj.Transparency = 1
		end
	end
end

local function start(player: Player, payload: any): Router.Result
	local uid = Router.String(payload.Uid)
	local districtIndex = Router.Int(payload.District, 1, #Rampage.Districts)
	local data = DataService.Get(player)
	if not uid or not districtIndex or not data then
		return { ok = false, msg = "Pick a kaiju and a district!" }
	end
	if runs[player] then
		return { ok = false, msg = "You're already smashing!" }
	end
	local now = serverNow()
	if (readyAt[player] or 0) > now then
		return { ok = false, msg = ("The city is being rebuilt... %ds"):format(math.ceil(readyAt[player] - now)) }
	end
	if Registry.SiegeService.IsActive(player) then
		return { ok = false, msg = "Defend your island first!" }
	end
	if Registry.StealService.IsCarrying(player) then
		return { ok = false, msg = "Deliver the stolen kaiju first!" }
	end
	local rec = Registry.KaijuService.FindRecord(data, uid)
	if not rec or rec.Egg or not rec.Species then
		return { ok = false, msg = "Pick a hatched kaiju!" }
	end
	local r = ensureData(data)
	if not Rampage.Unlocked(r.Stars, districtIndex) then
		local prev = Rampage.District(districtIndex - 1)
		return { ok = false, msg = ("Get %d stars in %s first!"):format(Rampage.UnlockStars, prev.Name) }
	end
	local plot = Registry.PlotService.Get(player)
	local character = player.Character
	local root = rootOf(player)
	local humanoid = humanoidOf(player)
	if not plot or not character or not root or not humanoid or humanoid.Health <= 0 then
		return { ok = false, msg = "Try again in a moment!" }
	end

	local district = Rampage.District(districtIndex)
	local easy = data.Tutorial < Tutorial.Done
	local hpMult = district.HpMult * (if easy then Rampage.TutorialHpMult else 1)
	runCounter += 1
	local seed = player.UserId * 31 + runCounter * 7919 + os.time()
	local folder = CityBuilder.Folder()
	local old = folder:FindFirstChild(tostring(player.UserId))
	if old then
		old:Destroy()
	end
	local origin = Rampage.CityOrigin(plot.Index)
	local city = CityBuilder.Build(folder, tostring(player.UserId), origin, district, hpMult, seed)
	local stage = Calc.Stage(rec)
	local run: Run = {
		Player = player,
		Uid = uid,
		Species = rec.Species,
		Mutation = rec.Mutation,
		Stage = stage,
		Scale = Growth.Get(stage).Scale,
		Power = Calc.Power(rec),
		District = district,
		City = city,
		Rng = Random.new(seed),
		StartAt = now,
		EndsAt = now + Rampage.Duration,
		Smashed = 0,
		DestroyedHP = 0,
		Points = 0,
		Cash = 0,
		Combo = 0,
		LastSmash = 0,
		Stars = 0,
		Egg = nil,
		Tanks = {},
		Darts = {},
		TankCount = 0,
		NextTank = 0,
		NextId = 0,
		LastStomp = 0,
		LastRoar = 0,
		LastPos = city.Spawn.Position,
		LastCheck = os.clock(),
		SuspectUntil = 0,
		Hidden = {},
		Humanoid = humanoid,
		Jump = { Power = humanoid.JumpPower or 50, Height = humanoid.JumpHeight or 7.2 },
		DiedConn = nil,
		Ending = false,
		Easy = easy,
	}
	runs[player] = run
	player:SetAttribute("Rampage", true)

	if Workspace.StreamingEnabled then
		pcall(player.RequestStreamAroundAsync, player, city.Spawn.Position)
	end
	humanoid:UnequipTools()
	character:PivotTo(city.Spawn)
	hideCharacter(run, character)
	humanoid.WalkSpeed = Rampage.WalkSpeed + data.Upgrades.Sneakers * Economy.UpgradesById.Sneakers.PerLevel
	-- un kaiju ne saute pas (et sur mobile le bouton de saut disparaît : place au STOMP)
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	run.DiedConn = humanoid.Died:Connect(function()
		endRun(player, "Died")
	end)

	Notify.Fx(player, "RampageStart", {
		Uid = uid,
		Species = rec.Species,
		Mutation = rec.Mutation,
		Rarity = rec.Rarity,
		Stage = stage,
		Scale = run.Scale,
		Power = run.Power,
		District = districtIndex,
		DistrictName = district.Name,
		Origin = origin,
		Half = city.Half,
		Spawn = city.Spawn,
		StartAt = run.StartAt,
		EndsAt = run.EndsAt,
		TotalHP = city.TotalHP,
		Buildings = #city.Buildings,
		Easy = easy,
	})
	return { ok = true, origin = origin, endsAt = run.EndsAt }
end

----------------------------------------------------------------------------
-- Portails des îles
----------------------------------------------------------------------------

local function tryOpen(player: Player, plotIndex: number, explicit: boolean)
	if Registry.PlotService.Owner(plotIndex) ~= player then
		if explicit then
			Notify.Toast(player, "Use the RAMPAGE portal on your own island!", "Info")
		end
		return
	end
	if runs[player] or (openDebounce[player] or 0) > os.clock() then
		return
	end
	openDebounce[player] = os.clock() + 3
	if Registry.SiegeService.IsActive(player) then
		return { ok = false, msg = "Defend your island first!" }
	end
	if Registry.StealService.IsCarrying(player) then
		Notify.Toast(player, "Deliver the stolen kaiju first!", "Bad")
		return
	end
	Notify.Fx(player, "RampageOpen", {})
end

-- Proximité vérifiée par le serveur : ouvre l'écran à l'arrivée sur le portail.
local function checkPortals()
	for index, pad in portals do
		local owner = Registry.PlotService.Owner(index)
		local root = owner and rootOf(owner)
		if owner and root then
			local near = (flat(root.Position) - flat(pad.Position)).Magnitude <= 5.5 and math.abs(root.Position.Y - pad.Position.Y) < 8
			if near and not onPad[owner] then
				tryOpen(owner, index, false)
			end
			onPad[owner] = near
		end
	end
end

----------------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------------

local function stepRun(player: Player, run: Run)
	if run.Ending then
		return
	end
	local root = rootOf(player)
	local humanoid = humanoidOf(player)
	if not root or not humanoid or humanoid.Health <= 0 then
		endRun(player, "Died")
		return
	end
	local pos = root.Position
	local rel = pos - run.City.Origin
	local limit = run.City.Half + Rampage.BoundsMargin
	if math.abs(rel.X) > limit or math.abs(rel.Z) > limit or rel.Y < -30 or rel.Y > 200 then
		endRun(player, "Left")
		return
	end
	-- anti-téléportation : au-delà de la vitesse de marche, les coups sont ignorés 1 s
	local clock = os.clock()
	local dt = clock - run.LastCheck
	if run.LastPos and dt > 0 then
		local moved = (flat(pos) - flat(run.LastPos)).Magnitude
		if moved > (humanoid.WalkSpeed * 1.5 + 16) * dt + 8 then
			run.SuspectUntil = clock + 1
			warn(("[RampageService] déplacement suspect de %s (%.0f studs en %.2fs)"):format(player.Name, moved, dt))
		end
	end
	run.LastPos = pos
	run.LastCheck = clock
	local now = serverNow()
	if clock >= run.SuspectUntil then
		crush(run, pos)
		if flattened(run) then
			endRun(player, "Flattened")
			return
		end
	end
	stepTanks(run, pos, now)
	if now >= run.EndsAt then
		endRun(player, "Time")
	end
end

function RampageService.Init()
	Router.On("RampageStart", start, 2)
	Router.On("RampageLeave", function(player)
		if not runs[player] then
			return { ok = false }
		end
		endRun(player, "Quit")
		return { ok = true }
	end, 2)
	Router.OnInput("RampageStomp", function(player)
		stomp(player)
	end)
	Router.OnInput("RampageRoar", function(player, payload)
		roar(player, payload)
	end)

	for _, plot in Registry.PlotService.All() do
		local pad = CityBuilder.BuildPortal(plot)
		portals[plot.Index] = pad
		pad.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player then
				tryOpen(player, plot.Index, false)
			end
		end)
		local prompt = pad:FindFirstChild("RampagePrompt") :: ProximityPrompt
		prompt.Triggered:Connect(function(player)
			tryOpen(player, plot.Index, true)
		end)
	end

	DataService.Loaded:Connect(function(player, data)
		ensureData(data)
		DataService.Replicate(player, "Rampage")
	end)

	Players.PlayerRemoving:Connect(function(player)
		endRun(player, "Gone")
		readyAt[player] = nil
		openDebounce[player] = nil
		onPad[player] = nil
	end)

	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.1)
			-- une erreur ne doit jamais arrêter la boucle pour tout le serveur
			local ok, err = pcall(function()
				tick += 1
				for player, run in runs do
					local ok, err = pcall(stepRun, player, run)
					if not ok then
						warn("[RampageService] " .. tostring(err))
					end
				end
				if tick % 3 == 0 then
					local ok, err = pcall(checkPortals)
					if not ok then
						warn("[RampageService] portails : " .. tostring(err))
					end
				end
			end)
			if not ok then
				warn("[RampageService] boucle : " .. tostring(err))
			end
		end
	end)
end

return RampageService
