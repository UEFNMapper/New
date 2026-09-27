--!nonstrict
-- Défense de l'île (« Wild Kaijus Invade! ») : des vagues de mini-kaijus
-- sauvages serpentent entre les nids jusqu'au réacteur. Les kaijus éclos
-- tirent dessus (tours), le joueur les bonke. Un envahisseur qui atteint le
-- réacteur prend un sac de cash (jamais de kaiju) et s'enfuit.
--
-- Réplication économe : chaque envahisseur est une pièce invisible dans
-- workspace.Siege.Plot<i> qui ne porte que des attributs (D0, T0, Speed, Dir,
-- Path…) ; client et serveur en déduisent la position avec Config/Siege.
-- Les tirs partent par lots (Fx « SiegeShots ») toutes les 0,25 s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Siege = require(Shared.Config.Siege)
local Layout = require(Shared.Config.Layout)
local Levels = require(Shared.Config.Levels)
local Tutorial = require(Shared.Config.Tutorial)
local Calc = require(Shared.Logic.Calc)
local Roll = require(Shared.Logic.Roll)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local SiegeService = {}

type Invader = {
	Id: string,
	Type: string,
	Part: BasePart,
	HP: number,
	MaxHP: number,
	Path: string,
	D0: number,
	T0: number,
	Speed: number,
	BaseSpeed: number,
	Dir: number,
	Radius: number,
	Alpha: boolean,
	Bag: number,
	Leaked: boolean,
	Killer: Player?,
	TowerProof: boolean?, -- ignoré par les tours (vague d'entraînement : à bonker)
}

type Wave = {
	Number: number,
	Tutorial: boolean,
	Bonus: boolean,
	Queue: { any }, -- { Type, Alpha?, HP?, Speed? }
	Gap: number,
	NextSpawn: number,
	Invaders: { [string]: Invader },
	Total: number,
	Kills: number,
	Leaks: number,
	Started: number,
	Cooldowns: { [string]: number },
}

type State = {
	Owner: Player,
	Plot: any,
	Folder: Folder,
	At: number, -- instant de la prochaine vague (quand le compte à rebours s'écoule)
	Left: number, -- secondes restantes (mémorisées pendant une pause)
	Paused: string?, -- Idle | Away | Rampage | AFK (nil = ça s'écoule)
	LastPos: Vector3?,
	LastMove: number,
	Wave: Wave?,
}

type Orb = { Id: string, Part: BasePart, Owner: Player, Value: number, Expires: number, Plot: number }

local root: Folder
local plotFolders: { [number]: Folder } = {}
local states: { [Player]: State } = {}
local orbs: { [string]: Orb } = {}
local counter = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function newId(prefix: string): string
	counter += 1
	return prefix .. counter
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent == Players
end

----------------------------------------------------------------------------
-- Audience et publication
----------------------------------------------------------------------------

-- Joueurs qui voient cette île (propriétaire + visiteurs proches).
local function audience(state: State): { Player }
	local list = {}
	local center = state.Plot.CFrame.Position
	for _, p in Players:GetPlayers() do
		if p == state.Owner then
			table.insert(list, p)
		else
			local r = rootOf(p)
			if r and (r.Position - center).Magnitude <= Siege.AudienceRadius then
				table.insert(list, p)
			end
		end
	end
	return list
end

local function fxAudience(state: State, name: string, args: any)
	for _, p in audience(state) do
		Notify.Fx(p, name, args)
	end
end

local function remaining(wave: Wave): number
	local n = #wave.Queue
	for _ in wave.Invaders do
		n += 1
	end
	return n
end

-- Recopie l'état du siège sur le dossier de l'île (lu par le HUD du client).
local function publish(state: State)
	local f = state.Folder
	local wave = state.Wave
	local data = DataService.Get(state.Owner)
	f:SetAttribute("Owner", state.Owner.UserId)
	f:SetAttribute("OwnerName", state.Owner.DisplayName)
	if wave then
		f:SetAttribute("Wave", wave.Number)
		f:SetAttribute("Tutorial", wave.Tutorial)
		f:SetAttribute("Bonus", wave.Bonus)
		f:SetAttribute("Count", wave.Total + #wave.Queue)
		f:SetAttribute("Remaining", remaining(wave))
		f:SetAttribute("Leaks", wave.Leaks)
		f:SetAttribute("Alpha", Siege.HasAlpha(wave.Number) and not wave.Tutorial)
		f:SetAttribute("State", "Active") -- en dernier : les autres attributs sont déjà à jour
	else
		local nextWave = if data then data.Siege.Wave else 1
		f:SetAttribute("Reason", state.Paused or "")
		f:SetAttribute("At", state.At)
		f:SetAttribute("Left", state.Left)
		f:SetAttribute("Wave", nextWave)
		f:SetAttribute("Tutorial", false)
		f:SetAttribute("Bonus", false)
		f:SetAttribute("Alpha", Siege.HasAlpha(nextWave))
		f:SetAttribute("Remaining", 0)
		f:SetAttribute("Leaks", 0)
		f:SetAttribute("State", if state.Paused == "Idle" then "Idle" elseif state.Paused then "Paused" else "Countdown")
	end
	state.Owner:SetAttribute("SiegeActive", wave ~= nil)
end

local function clearFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		local orb = orbs[child.Name]
		if orb then
			orbs[child.Name] = nil
		end
		child:Destroy()
	end
	for _, attr in { "Owner", "OwnerName", "State", "Reason", "At", "Left", "Wave", "Tutorial", "Bonus", "Count", "Remaining", "Leaks", "Alpha" } do
		folder:SetAttribute(attr, nil)
	end
end

----------------------------------------------------------------------------
-- Envahisseurs
----------------------------------------------------------------------------

local function pathOf(inv: Invader): Siege.Path
	return Siege.GetPath(inv.Path)
end

local function distanceOf(inv: Invader, t: number): number
	return Siege.Distance(pathOf(inv), inv.D0, inv.T0, inv.Speed, inv.Dir, t)
end

local function localPos(inv: Invader, t: number): (Vector3, number)
	local d = distanceOf(inv, t)
	local pos = Siege.PathAt(pathOf(inv), d)
	return pos, d
end

local function worldPos(state: State, inv: Invader, t: number): Vector3
	local p = localPos(inv, t)
	return (state.Plot.CFrame * CFrame.new(p.X, 0, p.Z)).Position
end

-- Change le mouvement à partir de la distance `d` (recul, fuite, demi-tour).
local function setMotion(inv: Invader, t: number, d: number, dir: number, speed: number, path: string)
	inv.D0, inv.T0, inv.Dir, inv.Speed, inv.Path = d, t, dir, speed, path
	local part = inv.Part
	part:SetAttribute("Path", path)
	part:SetAttribute("D0", d)
	part:SetAttribute("T0", t)
	part:SetAttribute("Speed", speed)
	part:SetAttribute("Dir", dir)
end

local function spawnInvader(state: State, wave: Wave, spec: any, t: number, d0: number?): Invader
	local isAlpha = spec.Alpha == true
	local def = Siege.Types[spec.Type] or Siege.Types.Grunt
	local base = Siege.BaseHP(wave.Number)
	local hp = spec.HP or (if isAlpha then base * Siege.Alpha.HP else base * def.HP)
	local speed = spec.Speed or (if isAlpha then Siege.Alpha.Speed else def.Speed)
	local pool = if isAlpha then Siege.Alpha.Species else def.Species
	local species = pool[math.random(1, #pool)]
	local id = newId("I")
	local part = Instance.new("Part")
	part.Name = id
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	local pathName = spec.Path or "In"
	local start = Siege.PathAt(Siege.GetPath(pathName), d0 or 0)
	part.CFrame = state.Plot.CFrame * CFrame.new(start.X, 1, start.Z)
	part:SetAttribute("Kind", "Invader")
	part:SetAttribute("Id", id)
	part:SetAttribute("Type", if isAlpha then "Alpha" else def.Id)
	part:SetAttribute("Species", species)
	part:SetAttribute("Scale", if isAlpha then Siege.Alpha.Scale else def.Scale)
	part:SetAttribute("Alpha", isAlpha)
	part:SetAttribute("MaxHP", hp)
	part:SetAttribute("HP", hp)
	part:SetAttribute("Bag", 0)
	if spec.TowerProof then
		part:SetAttribute("TowerProof", true)
		part:SetAttribute("Scale", Siege.Tutorial.ToughScale)
	end
	local inv: Invader = {
		Id = id,
		Type = def.Id,
		Part = part,
		HP = hp,
		MaxHP = hp,
		Path = "In",
		D0 = 0,
		T0 = t,
		Speed = speed,
		BaseSpeed = speed,
		Dir = 1,
		Radius = if isAlpha then Siege.Alpha.Radius else def.Radius,
		Alpha = isAlpha,
		Bag = 0,
		Leaked = false,
		Killer = nil,
		TowerProof = spec.TowerProof == true,
	}
	setMotion(inv, t, d0 or 0, 1, speed, pathName)
	part.Parent = state.Folder
	wave.Invaders[id] = inv
	wave.Total += 1
	return inv
end

----------------------------------------------------------------------------
-- Orbes de cash
----------------------------------------------------------------------------

local function spawnOrb(state: State, owner: Player, position: Vector3, value: number)
	local id = newId("O")
	local part = Instance.new("Part")
	part.Name = id
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	local jitter = Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10)
	part.CFrame = CFrame.new(position + jitter + Vector3.new(0, 1.5, 0))
	part:SetAttribute("Kind", "Orb")
	part:SetAttribute("Id", id)
	part:SetAttribute("Owner", owner.UserId)
	part:SetAttribute("Value", value)
	part.Parent = state.Folder
	orbs[id] = { Id = id, Part = part, Owner = owner, Value = value, Expires = now() + Siege.OrbLifetime, Plot = state.Plot.Index }
end

local function collectOrb(orb: Orb, player: Player)
	orbs[orb.Id] = nil
	local position = orb.Part.Position
	orb.Part:Destroy()
	DataService.AddCash(player, orb.Value)
	Notify.Fx(player, "SiegeOrb", { Id = orb.Id, Amount = orb.Value, Position = position })
	Registry.RewardService.Track(player, "Orbs", 1)
end

-- Ramasse les orbes du joueur autour d'une position (compagnon : aspirateur).
-- Renvoie le cash total ramassé et le nombre d'orbes.
function SiegeService.CollectOrbsNear(player: Player, position: Vector3, radius: number): (number, number)
	local total, count = 0, 0
	for _, orb in table.clone(orbs) do
		if orb.Owner == player and (orb.Part.Position - position).Magnitude <= radius then
			total += orb.Value
			count += 1
			collectOrb(orb, player)
		end
	end
	return total, count
end

local function stepOrbs(t: number)
	for _, orb in table.clone(orbs) do
		if t >= orb.Expires or not alive(orb.Owner) then
			orbs[orb.Id] = nil
			orb.Part:Destroy()
		else
			local r = rootOf(orb.Owner)
			if r then
				local offset = r.Position - orb.Part.Position
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= Siege.OrbPickup and math.abs(offset.Y) < 8 then
					collectOrb(orb, orb.Owner)
				end
			end
		end
	end
end

----------------------------------------------------------------------------
-- Sacs de cash, fuites, morts
----------------------------------------------------------------------------

local function saveBag(state: State, inv: Invader, by: Player?)
	if inv.Bag <= 0 then
		return
	end
	local amount = inv.Bag
	inv.Bag = 0
	inv.Part:SetAttribute("Bag", 0)
	if alive(state.Owner) then
		DataService.AddCash(state.Owner, amount)
	end
	fxAudience(state, "SiegeBagSaved", { Plot = state.Plot.Index, Id = inv.Id, Amount = amount, By = if by then by.UserId else 0 })
end

local function leak(state: State, wave: Wave, inv: Invader, t: number)
	inv.Leaked = true
	wave.Leaks += 1
	local owner = state.Owner
	local data = DataService.Get(owner)
	local bag = 0
	if data then
		local cap = Registry.KaijuService.IncomeSeconds(owner, Siege.BagMaxSeconds, 0)
		bag = math.floor(math.min(data.Stored * Siege.BagShare, cap))
		if bag > 0 then
			data.Stored -= bag
			DataService.Replicate(owner, "Stored")
			state.Plot.Model:SetAttribute("Stored", data.Stored)
		end
	end
	inv.Bag = bag
	inv.Part:SetAttribute("Bag", bag)
	setMotion(inv, t, 0, 1, inv.BaseSpeed * Siege.FleeSpeedMult, "Out")
	Notify.Fx(owner, "SiegeLeak", { Plot = state.Plot.Index, Id = inv.Id, Amount = bag })
end

local function escape(state: State, wave: Wave, inv: Invader)
	wave.Invaders[inv.Id] = nil
	inv.Part:Destroy()
	Notify.Fx(state.Owner, "SiegeEscaped", { Plot = state.Plot.Index, Id = inv.Id, Amount = inv.Bag })
end

local function rollEgg(wave: number): string
	local odds = Siege.EggOdds(wave)
	local weights = {}
	for i, row in odds do
		weights[i] = row.Weight
	end
	return odds[Roll.Weighted(weights)].Rarity
end

local function kill(state: State, wave: Wave, inv: Invader, t: number)
	if not wave.Invaders[inv.Id] then
		return
	end
	local owner = state.Owner
	local killer = if alive(inv.Killer) then inv.Killer else nil
	local credit = killer or owner
	local d = distanceOf(inv, t)
	local position = worldPos(state, inv, t)
	wave.Invaders[inv.Id] = nil
	wave.Kills += 1
	saveBag(state, inv, killer)
	-- l'effet part avant la destruction : le client sait que c'est un kill (et pas une fuite)
	fxAudience(state, "SiegeKill", { Plot = state.Plot.Index, Id = inv.Id, By = if killer then killer.UserId else 0, Alpha = inv.Alpha, Position = position })
	inv.Part:Destroy()

	local value = Registry.KaijuService.IncomeSeconds(credit, Siege.OrbSeconds, Siege.OrbMinPerWave * wave.Number)
	spawnOrb(state, credit, position, value)
	Registry.LevelService.AddXp(credit, Levels.Xp.SiegeKill, "SiegeKill")
	Registry.RewardService.Track(credit, "SiegeKills", 1)

	-- Le Splitter se divise en petits coureurs
	local def = Siege.Types[inv.Type]
	if def and def.SplitInto and not inv.Alpha then
		for k = 1, def.SplitCount or 2 do
			local child = spawnInvader(state, wave, { Type = def.SplitInto, Path = if inv.Path == "Out" then "In" else inv.Path }, t, math.max(0, d - k * 1.5))
			if inv.Path == "Out" then
				setMotion(child, t, math.max(0, d - k * 1.5), 1, child.BaseSpeed * Siege.FleeSpeedMult, "Out")
				child.Leaked = true
			end
		end
	end
	if inv.Alpha and not wave.Tutorial then
		local rarity = rollEgg(wave.Number)
		Registry.KaijuService.GiveEgg(owner, rarity, "Siege")
		Registry.LevelService.AddXp(owner, Levels.Xp.SiegeAlpha, "SiegeAlpha")
		Notify.Fx(owner, "SiegeAlphaEgg", { Rarity = rarity, Wave = wave.Number })
	end
end

local function damage(inv: Invader, amount: number, by: Player?)
	if inv.HP <= 0 then
		return
	end
	inv.HP = math.max(0, inv.HP - amount)
	if inv.HP <= 0 then
		inv.Killer = by
	end
end

----------------------------------------------------------------------------
-- Tours
----------------------------------------------------------------------------

type Tower = { Uid: string, Slot: number, Pos: Vector3, Range: number, Damage: number, Splash: boolean }

local function towersOf(player: Player): { Tower }
	local data = DataService.Get(player)
	local list = {}
	if not data then
		return list
	end
	for _, rec in data.Kaijus do
		if not rec.Egg and rec.Species and Layout.Nests[rec.Nest] then
			local anchor = Registry.KaijuService.Anchor(rec.Uid)
			if anchor and (anchor:GetAttribute("CarriedBy") or 0) == 0 then
				local stage = Calc.Stage(rec)
				table.insert(list, {
					Uid = rec.Uid,
					Slot = rec.Nest,
					Pos = Layout.Nests[rec.Nest],
					Range = Siege.Range(stage),
					Damage = Siege.TowerDamage * Calc.Power(rec),
					Splash = stage >= Siege.SplashStage,
				})
			end
		end
	end
	return list
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Priorité : les voleurs de sac d'abord (le plus près de la sortie), puis le plus avancé.
local function priority(inv: Invader, d: number): number
	if inv.Path == "Out" then
		return 100000 + d
	end
	return if inv.Dir < 0 then d - 1000 else d
end

local function fireTowers(state: State, wave: Wave, t: number, cache: { [Invader]: { Pos: Vector3, D: number } }): { any }
	local shots = {}
	for _, tower in towersOf(state.Owner) do
		local ready = wave.Cooldowns[tower.Uid]
		if not ready then
			-- premiers tirs décalés : les tours ne tirent pas toutes en même temps
			ready = wave.Started + (tower.Slot % 4) * Siege.Tick
			wave.Cooldowns[tower.Uid] = ready
		end
		if t >= ready then
			local best, bestScore = nil, -math.huge
			for inv, c in cache do
				if inv.HP > 0 and not inv.TowerProof and flat(tower.Pos, c.Pos) <= tower.Range then
					local score = priority(inv, c.D)
					if score > bestScore then
						best, bestScore = inv, score
					end
				end
			end
			if best then
				wave.Cooldowns[tower.Uid] = t + Siege.TowerCooldown
				damage(best, tower.Damage, nil)
				table.insert(shots, { U = tower.Uid, I = best.Id, D = tower.Damage, X = tower.Splash or nil })
				if tower.Splash then
					local center = cache[best].Pos
					for other, c in cache do
						if other ~= best and other.HP > 0 and not other.TowerProof and flat(center, c.Pos) <= Siege.SplashRadius + other.Radius then
							local splash = tower.Damage * Siege.SplashFactor
							damage(other, splash, nil)
							table.insert(shots, { I = other.Id, D = splash, S = true })
						end
					end
				end
			end
		end
	end
	return shots
end

----------------------------------------------------------------------------
-- Vagues
----------------------------------------------------------------------------

local function startWave(state: State, bonus: boolean, tutorial: boolean): boolean
	if state.Wave then
		return false
	end
	local data = DataService.Get(state.Owner)
	if not data then
		return false
	end
	local t = now()
	local number = if tutorial then 1 else data.Siege.Wave
	local queue = {}
	if tutorial then
		for _ = 1, Siege.Tutorial.Count do
			table.insert(queue, { Type = "Grunt", HP = Siege.Tutorial.HP, Speed = Siege.Tutorial.Speed, Path = "Tutorial" })
		end
		table.insert(queue, { Type = "Tank", HP = Siege.Tutorial.ToughHP, Speed = Siege.Tutorial.Speed, Path = "Tutorial", TowerProof = true })
	else
		for _, id in Siege.Composition(number) do
			table.insert(queue, { Type = id })
		end
		if Siege.HasAlpha(number) then
			table.insert(queue, { Type = "Grunt", Alpha = true })
		end
	end
	local wave: Wave = {
		Number = number,
		Tutorial = tutorial,
		Bonus = bonus,
		Queue = queue,
		Gap = if tutorial then Siege.Tutorial.Gap else Siege.SpawnGap,
		NextSpawn = t + 1.5, -- le temps que la sirène retentisse
		Invaders = {},
		Total = 0,
		Kills = 0,
		Leaks = 0,
		Started = t,
		Cooldowns = {},
	}
	state.Wave = wave
	state.Paused = nil
	publish(state)
	fxAudience(state, "SiegeWaveStart", {
		Plot = state.Plot.Index,
		Wave = number,
		Count = #queue,
		Alpha = Siege.HasAlpha(number) and not tutorial,
		Tutorial = tutorial,
		Bonus = bonus,
		Owner = state.Owner.UserId,
	})
	return true
end

local function finishWave(state: State, wave: Wave)
	local owner = state.Owner
	local data = DataService.Get(owner)
	state.Wave = nil
	if not data then
		return
	end
	local total = math.max(wave.Total, 1)
	local cleared = wave.Tutorial or wave.Leaks / total < Siege.FailRatio
	local cash, gems, xp = 0, 0, 0
	if cleared then
		local seconds = Siege.WaveSeconds * (1 + Siege.WavePerWave * wave.Number) * (if wave.Bonus then 1 + Siege.StartNowBonus else 1)
		cash = Registry.KaijuService.IncomeSeconds(owner, seconds, Siege.WaveMinPerWave * wave.Number)
		DataService.AddCash(owner, cash)
		xp = Levels.Xp.SiegeWave + 3 * wave.Number
		Registry.LevelService.AddXp(owner, xp, "SiegeWave")
		if not wave.Tutorial then
			if wave.Number % Siege.GemsEvery == 0 then
				gems = Siege.Gems
				DataService.AddGems(owner, gems)
			end
			data.Siege.Best = math.max(data.Siege.Best, wave.Number)
			data.Siege.Wave = wave.Number + 1
			data.Siege.Cleared += 1
			Registry.RewardService.Track(owner, "SiegeWaves", 1)
		end
		DataService.Replicate(owner, "Siege")
	end
	local t = now()
	state.Left = Siege.Countdown
	state.At = t + Siege.Countdown
	state.Paused = nil
	publish(state)
	Notify.Fx(owner, "SiegeWaveEnd", {
		Plot = state.Plot.Index,
		Wave = wave.Number,
		Cleared = cleared,
		Tutorial = wave.Tutorial,
		Kills = wave.Kills,
		Leaks = wave.Leaks,
		Total = wave.Total,
		Stars = if cleared then Siege.Stars(wave.Leaks, wave.Total) else 0,
		Cash = cash,
		Gems = gems,
		Xp = xp,
		Bonus = wave.Bonus,
		Next = data.Siege.Wave,
	})
	if cleared then
		Registry.TutorialService.Notify(owner, "SiegeWave")
	end
end

local function stepWave(state: State, wave: Wave, t: number)
	-- apparitions
	while #wave.Queue > 0 and t >= wave.NextSpawn do
		spawnInvader(state, wave, table.remove(wave.Queue, 1), t)
		wave.NextSpawn += wave.Gap
	end

	-- déplacements : arrivée au réacteur, demi-tour (entraînement), sortie
	local cache: { [Invader]: { Pos: Vector3, D: number } } = {}
	for _, inv in table.clone(wave.Invaders) do
		local pos, d = localPos(inv, t)
		local path = pathOf(inv)
		if inv.Path ~= "Out" and inv.Dir > 0 and d >= path.Length - 0.01 then
			if inv.Path == "Tutorial" then
				setMotion(inv, t, path.Length, -1, inv.BaseSpeed, "Tutorial")
			else
				leak(state, wave, inv, t)
				pos, d = localPos(inv, t)
			end
		elseif inv.Path == "Tutorial" and inv.Dir < 0 and d <= Siege.TutorialBounce then
			setMotion(inv, t, Siege.TutorialBounce, 1, inv.BaseSpeed, "Tutorial")
		elseif inv.Path == "Out" and d >= path.Length - 0.01 then
			escape(state, wave, inv)
			continue
		end
		cache[inv] = { Pos = pos, D = d }
	end

	-- tirs des tours
	local shots = fireTowers(state, wave, t, cache)
	if #shots > 0 then
		fxAudience(state, "SiegeShots", { Plot = state.Plot.Index, Shots = shots })
	end

	-- PV et morts
	for _, inv in table.clone(wave.Invaders) do
		inv.Part:SetAttribute("HP", inv.HP)
		if inv.HP <= 0 then
			kill(state, wave, inv, t)
		end
	end

	-- sécurité de la vague d'entraînement
	if wave.Tutorial and t - wave.Started > Siege.Tutorial.Timeout then
		for _, inv in table.clone(wave.Invaders) do
			wave.Invaders[inv.Id] = nil
			inv.Part:Destroy()
		end
		table.clear(wave.Queue)
	end

	if #wave.Queue == 0 and next(wave.Invaders) == nil then
		finishWave(state, wave)
	else
		publish(state)
	end
end

----------------------------------------------------------------------------
-- Compte à rebours
----------------------------------------------------------------------------

local function inRampage(player: Player): boolean
	local r = Registry.RampageService
	if r and r.IsActive and r.IsActive(player) then
		return true
	end
	return false
end

local function eligible(player: Player): boolean
	local data = DataService.Get(player)
	if not data or data.Tutorial < Tutorial.Done then
		return false
	end
	for _, rec in data.Kaijus do
		if not rec.Egg then
			return true
		end
	end
	return false
end

local function onIsland(state: State): boolean
	local r = rootOf(state.Owner)
	return r ~= nil and Layout.InPlot(state.Plot.CFrame, r.Position, Siege.IslandMargin)
end

local function pauseReason(state: State, t: number): string?
	if not eligible(state.Owner) then
		return "Idle"
	end
	if inRampage(state.Owner) then
		return "Rampage"
	end
	if not onIsland(state) then
		return "Away"
	end
	if t - state.LastMove > Siege.AfkSeconds then
		return "AFK"
	end
	return nil
end

local function stepCountdown(state: State, t: number)
	local r = rootOf(state.Owner)
	if r then
		if not state.LastPos or (r.Position - state.LastPos).Magnitude > 1.5 then
			state.LastPos = r.Position
			state.LastMove = t
		end
	end
	local reason = pauseReason(state, t)
	if reason then
		if not state.Paused then
			state.Left = math.max(0, state.At - t)
		end
		if reason == "Idle" and state.Paused ~= "Idle" then
			-- redevient éligible plus tard (fin du tutoriel, premier kaiju) : départ rapide
			local data = DataService.Get(state.Owner)
			if data and data.Siege.Cleared == 0 then
				state.Left = math.min(state.Left, Siege.FirstCountdown)
			end
		end
		if state.Paused ~= reason then
			state.Paused = reason
			publish(state)
		end
		return
	end
	if state.Paused then
		state.Paused = nil
		state.At = t + state.Left
		publish(state)
	end
	if t >= state.At then
		startWave(state, false, false)
	end
end

----------------------------------------------------------------------------
-- API publique
----------------------------------------------------------------------------

-- Vague d'entraînement (tutoriel) : 4 envahisseurs faibles, impossible à perdre.
function SiegeService.StartTutorialWave(player: Player): boolean
	local state = states[player]
	if not state then
		return false
	end
	return startWave(state, false, true)
end

function SiegeService.IsActive(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.Wave ~= nil
end

-- Bonk du joueur (appelé par StealService) : dégâts + recul le long du chemin.
-- Renvoie true si au moins un envahisseur a été touché.
function SiegeService.TryBonk(player: Player, position: Vector3, range: number, level: number): boolean
	local dmg = Siege.BonkDamage * (1 + Siege.BonkPerLevel * level)
	if Registry.ShopService.HasPass(player, "SuperBonk") then
		dmg *= Siege.SuperBonkMult
	end
	local t = now()
	local hitAny = false
	for _, state in states do
		local wave = state.Wave
		if wave and Layout.InPlot(state.Plot.CFrame, position, Siege.IslandMargin) then
			local here = state.Plot.CFrame:PointToObjectSpace(position)
			for _, inv in table.clone(wave.Invaders) do
				local pos, d = localPos(inv, t)
				if inv.HP > 0 and flat(here, pos) <= range + inv.Radius then
					hitAny = true
					damage(inv, dmg, player)
					saveBag(state, inv, player)
					inv.Part:SetAttribute("HP", inv.HP)
					local pushed = math.clamp(d - inv.Dir * Siege.BonkPush, 0, pathOf(inv).Length)
					setMotion(inv, t, pushed, inv.Dir, inv.Speed, inv.Path)
					fxAudience(state, "SiegeBonk", { Plot = state.Plot.Index, Id = inv.Id, UserId = player.UserId, Damage = dmg })
					if inv.HP <= 0 then
						kill(state, wave, inv, t)
					end
				end
			end
			publish(state)
		end
	end
	if hitAny then
		Registry.RewardService.Track(player, "Bonks", 1)
	end
	return hitAny
end

-- Attaque du compagnon : frappe l'envahisseur le plus proche dans le rayon.
-- Renvoie la position (monde) de la cible touchée et si elle a été éliminée.
function SiegeService.DamageNearest(player: Player, position: Vector3, radius: number, amount: number): (Vector3?, boolean)
	local t = now()
	for _, state in states do
		local wave = state.Wave
		if wave and Layout.InPlot(state.Plot.CFrame, position, Siege.IslandMargin) then
			local here = state.Plot.CFrame:PointToObjectSpace(position)
			local best, bestDist = nil, math.huge
			for _, inv in wave.Invaders do
				local dist = flat(here, (localPos(inv, t)))
				if inv.HP > 0 and not inv.TowerProof and dist <= radius + inv.Radius and dist < bestDist then
					best, bestDist = inv, dist
				end
			end
			if best then
				damage(best, amount, player)
				best.Part:SetAttribute("HP", best.HP)
				fxAudience(state, "SiegeShots", { Plot = state.Plot.Index, Shots = { { P = position, I = best.Id, D = amount } } })
				local target = state.Plot.CFrame:PointToWorldSpace((localPos(best, t)))
				local killed = best.HP <= 0
				if killed then
					kill(state, wave, best, t)
				end
				publish(state)
				return target, killed
			end
		end
	end
	return nil, false
end

----------------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------------

local function cleanup(player: Player)
	local state = states[player]
	if state then
		states[player] = nil
		clearFolder(state.Folder)
	end
	-- orbes de ce joueur sur les autres îles
	for id, orb in table.clone(orbs) do
		if orb.Owner == player then
			orbs[id] = nil
			orb.Part:Destroy()
		end
	end
end

local function onLoaded(player: Player, data: any)
	local t0 = os.clock()
	while not Registry.PlotService.Get(player) and os.clock() - t0 < 10 and player.Parent == Players do
		task.wait(0.1)
	end
	local plot = Registry.PlotService.Get(player)
	if not plot or player.Parent ~= Players then
		return
	end
	local folder = plotFolders[plot.Index]
	clearFolder(folder)
	local left = if data.Siege.Cleared == 0 then Siege.FirstCountdown else Siege.JoinCountdown
	local t = now()
	local state: State = {
		Owner = player,
		Plot = plot,
		Folder = folder,
		At = t + left,
		Left = left,
		Paused = "Idle",
		LastPos = nil,
		LastMove = t,
		Wave = nil,
	}
	states[player] = state
	publish(state)
end

local function startNow(player: Player): Router.Result
	local state = states[player]
	if not state then
		return { ok = false }
	end
	if state.Wave then
		return { ok = false, msg = "A wave is already here!" }
	end
	if not eligible(player) then
		return { ok = false, msg = "Hatch a kaiju first!" }
	end
	if inRampage(player) then
		return { ok = false, msg = "Finish your Rampage first!" }
	end
	if not onIsland(state) then
		return { ok = false, msg = "Go back to your island first!" }
	end
	startWave(state, true, false)
	return { ok = true }
end

function SiegeService.Init()
	root = Instance.new("Folder")
	root.Name = "Siege"
	root.Parent = Workspace
	for _, plot in Registry.PlotService.All() do
		local f = Instance.new("Folder")
		f.Name = "Plot" .. plot.Index
		f:SetAttribute("Plot", plot.Index)
		f.Parent = root
		plotFolders[plot.Index] = f
	end

	Router.On("SiegeStartNow", startNow, 1)
	DataService.Loaded:Connect(onLoaded)
	Players.PlayerRemoving:Connect(cleanup)

	task.spawn(function()
		while true do
			task.wait(Siege.Tick)
			-- une erreur ne doit jamais arrêter la boucle pour tout le serveur
			local ok, err = pcall(function()
				local t = now()
				for player, state in states do
					local ok, err = pcall(function()
						if player.Parent ~= Players then
							cleanup(player)
						elseif state.Wave then
							stepWave(state, state.Wave, t)
						else
							stepCountdown(state, t)
						end
					end)
					if not ok then
						warn("[SiegeService] " .. tostring(err))
					end
				end
				local ok, err = pcall(stepOrbs, t)
				if not ok then
					warn("[SiegeService] orbes : " .. tostring(err))
				end
			end)
			if not ok then
				warn("[SiegeService] boucle : " .. tostring(err))
			end
		end
	end)
end

return SiegeService
