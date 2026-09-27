--!nonstrict
-- Événements mondiaux : rotation automatique, déclenchement payant,
-- mutations contagieuses, Stampede (orbes de cash) et Raid du Colosse (boss).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Kaijus = require(Shared.Config.Kaijus)
local Mutations = require(Shared.Config.Mutations)
local Layout = require(Shared.Config.Layout)
local Roll = require(Shared.Logic.Roll)
local Calc = require(Shared.Logic.Calc)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Notify)
local Router = require(script.Parent.Router)

local EventService = {}

local current: Events.WorldEvent? = nil
local endsAt = 0
local queue: { { Id: string, By: Player? } } = {}
local orbsFolder: Folder
local orbs: { [string]: { Part: BasePart, Value: number } } = {}
local orbId = 0

-- Boss
local boss: BasePart? = nil
local bossDamage: { [Player]: number } = {}
local bossHitCooldown: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

function EventService.Current(): Events.WorldEvent?
	return current
end

----------------------------------------------------------------------------
-- Stampede : orbes de cash
----------------------------------------------------------------------------

local function spawnOrbWave()
	local cfg = Events.Stampede
	for _ = 1, cfg.OrbsPerWave do
		orbId += 1
		local id = "O" .. orbId
		local a = math.random() * math.pi * 2
		local r = math.random() * (Layout.CraterRadius - 12) + 6
		local p = Instance.new("Part")
		p.Name = id
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(2.4, 2.4, 2.4)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.CFrame = CFrame.new(math.cos(a) * r, 2.5, math.sin(a) * r)
		p:SetAttribute("Id", id)
		p.Parent = orbsFolder
		orbs[id] = { Part = p, Value = 1 }
		task.delay(20, function()
			if orbs[id] then
				orbs[id] = nil
				p:Destroy()
			end
		end)
	end
	Notify.FxAll("StampedeWave", {})
end

local function grabOrb(player: Player, payload: any)
	local id = if type(payload) == "table" then Router.String(payload.Id) else nil
	local orb = id and orbs[id]
	if not orb or not id then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - orb.Part.Position).Magnitude > 14 then
		return
	end
	orbs[id] = nil
	orb.Part:Destroy()
	local cfg = Events.Stampede
	local amount = Calc.CashReward(cfg.OrbCashSeconds, Registry.KaijuService.IncomePerSecond(player), cfg.OrbMinCash)
	DataService.AddCash(player, amount)
	Notify.Fx(player, "OrbGrabbed", { Id = id, Amount = amount })
	Notify.FxAll("OrbGone", { Id = id })
	Registry.RewardService.Track(player, "Orbs", 1)
end

----------------------------------------------------------------------------
-- Raid du Colosse
----------------------------------------------------------------------------

local function spawnBoss()
	local players = #Players:GetPlayers()
	local hp = math.max(Events.Boss.MinHealth, Events.Boss.Health * players)
	local b = Instance.new("Part")
	b.Name = "Boss"
	b.Anchored = true
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.Transparency = 1
	b.Size = Vector3.new(4, 4, 4)
	b.CFrame = CFrame.new(0, 0, 0)
	b:SetAttribute("Species", "KingKaiju")
	b:SetAttribute("Mutation", "Shadow")
	b:SetAttribute("MaxHP", hp)
	b:SetAttribute("HP", hp)
	b:SetAttribute("Scale", 7)
	b.Parent = Workspace:WaitForChild("Effects")
	boss = b
	table.clear(bossDamage)
	Notify.FxAll("BossSpawn", {})
end

local function finishBoss(defeated: boolean)
	local b = boss
	if not b then
		return
	end
	boss = nil
	Notify.FxAll("BossEnd", { Defeated = defeated })
	if defeated then
		local total = 0
		local best: Player? = nil
		local bestDamage = 0
		for p, d in bossDamage do
			total += d
			if d > bestDamage then
				best, bestDamage = p, d
			end
		end
		for p, d in bossDamage do
			if p.Parent == Players then
				local share = d / math.max(total, 1)
				local gems = math.max(5, math.floor(Events.Boss.RewardGems * (0.5 + share * 3)))
				DataService.AddGems(p, gems)
				Notify.Fx(p, "BossReward", { Gems = gems, Top = p == best })
				if math.random() < Events.Boss.EggChance then
					Registry.KaijuService.GiveEgg(p, "Legendary", "Raid")
				end
			end
		end
		if best and best.Parent == Players then
			Registry.KaijuService.GiveEgg(best, Events.Boss.TopEggRarity, "Raid MVP")
			Notify.Feed(("👑 %s dealt the most damage to the COLOSSUS and wins a MYTHIC egg!"):format(best.DisplayName), "Boss")
		end
	else
		Notify.Feed("The Colossus escaped... next time!", "Boss")
	end
	task.delay(2, function()
		b:Destroy()
	end)
end

function EventService.TryBossHit(player: Player, position: Vector3, range: number)
	local b = boss
	if not b or (bossHitCooldown[player] or 0) > os.clock() then
		return
	end
	local flat = Vector3.new(position.X - b.Position.X, 0, position.Z - b.Position.Z)
	-- le boss est immense : on peut frapper ses pieds de loin
	if flat.Magnitude > 30 + range then
		return
	end
	bossHitCooldown[player] = os.clock() + 0.35
	local data = DataService.Get(player)
	local dmg = Events.Boss.DamagePerBonk * (1 + (if data then data.Upgrades.Bonker else 0) * 0.25)
	if Registry.ShopService.HasPass(player, "SuperBonk") then
		dmg *= 1.5
	end
	bossDamage[player] = (bossDamage[player] or 0) + dmg
	if data then
		data.Stats.BossDamage += dmg
	end
	local hp = math.max(0, (b:GetAttribute("HP") or 0) - dmg)
	b:SetAttribute("HP", hp)
	Notify.FxAll("BossHit", { UserId = player.UserId, Damage = dmg })
	if hp <= 0 then
		finishBoss(true)
	end
end

local function bossStomp()
	local b = boss
	if not b then
		return
	end
	Notify.FxAll("BossStomp", {})
	task.wait(0.8)
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local offset = root.Position - b.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude < 45 and root.Position.Y < 8 then
				local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
				Notify.Fx(p, "Knockback", { Velocity = dir * 90 + Vector3.new(0, 55, 0), From = "the Colossus" })
			end
		end
	end
end

----------------------------------------------------------------------------
-- Cycle de vie des événements
----------------------------------------------------------------------------

local function infect()
	local event = current
	if not event or not event.Mutation or not event.InfectChance then
		return
	end
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		if data then
			for _, rec in data.Kaijus do
				if not rec.Egg and rec.Mutation == nil and math.random() < event.InfectChance * 10 then
					rec.Mutation = event.Mutation
					Registry.KaijuService.SyncAnchor(player, rec)
					local species = Kaijus.Get(rec.Species or "")
					local mutation = Mutations.Get(event.Mutation)
					Notify.FxAll("Infected", { Uid = rec.Uid, Mutation = event.Mutation })
					Notify.Toast(player, ("Your %s mutated into %s! (x%d)"):format(if species then species.Name else "kaiju", if mutation then mutation.Name else event.Mutation, if mutation then mutation.Mult else 1), "Rare")
					if species then
						Registry.RewardService.Discover(player, species.Id, rec.Mutation)
					end
					DataService.Replicate(player, "Kaijus")
					Registry.KaijuService.RefreshPlayer(player)
					break -- une mutation par joueur et par vague
				end
			end
		end
	end
end

local function stop()
	local event = current
	if not event then
		return
	end
	current = nil
	Workspace:SetAttribute("EventId", nil)
	Workspace:SetAttribute("EventEnds", nil)
	Notify.FxAll("EventEnd", { Id = event.Id })
	if event.Id == "BossRaid" then
		finishBoss(false)
	elseif event.Id == "Stampede" then
		for id, orb in orbs do
			orb.Part:Destroy()
			orbs[id] = nil
		end
	end
	for _, player in Players:GetPlayers() do
		Registry.KaijuService.RefreshPlayer(player)
	end
end

local function start(id: string, by: Player?)
	local event = Events.ById[id]
	if not event then
		return
	end
	if current then
		stop()
	end
	current = event
	endsAt = now() + event.Duration
	Workspace:SetAttribute("EventId", event.Id)
	Workspace:SetAttribute("EventEnds", endsAt)
	Notify.FxAll("EventStart", { Id = event.Id, By = if by then by.DisplayName else nil })
	if by then
		Notify.Feed(("%s %s summoned a %s!"):format(event.Icon, by.DisplayName, event.Name), "Event", event.Color)
	else
		Notify.Feed(("%s %s — %s"):format(event.Icon, event.Name, event.Tagline), "Event", event.Color)
	end
	for _, player in Players:GetPlayers() do
		Registry.KaijuService.RefreshPlayer(player)
	end

	task.spawn(function()
		local thisEvent = event
		local tick = 0
		while current == thisEvent and now() < endsAt do
			task.wait(1)
			tick += 1
			if tick % 10 == 0 then
				infect()
			end
			if thisEvent.Id == "Stampede" and tick % Events.Stampede.WaveEvery == 1 then
				spawnOrbWave()
			end
			if thisEvent.Id == "BossRaid" then
				if tick == 1 then
					spawnBoss()
				elseif boss and tick % 9 == 0 then
					task.spawn(bossStomp)
				elseif not boss and tick > 2 then
					break -- vaincu
				end
			end
		end
		if current == thisEvent then
			stop()
		end
	end)
end

function EventService.Force(id: string, by: Player?)
	if current and current.Id ~= id then
		table.insert(queue, { Id = id, By = by })
		if by then
			Notify.Toast(by, "Your event is queued and will start right after the current one!", "Good")
		end
		return
	end
	if current and current.Id == id then
		endsAt += Events.ById[id].Duration -- prolonge
		Workspace:SetAttribute("EventEnds", endsAt)
		if by then
			Notify.Feed(("%s %s extended the %s!"):format(Events.ById[id].Icon, by.DisplayName, Events.ById[id].Name), "Event", Events.ById[id].Color)
		end
		return
	end
	start(id, by)
end

local function pickRandom(): string
	local weights = {}
	for i, e in Events.List do
		weights[i] = e.Weight
		if e.Id == "BossRaid" and #Players:GetPlayers() < 2 then
			weights[i] = 0
		end
	end
	return Events.List[Roll.Weighted(weights)].Id
end

function EventService.Init()
	orbsFolder = Workspace:WaitForChild("Orbs") :: Folder
	Router.OnInput("Orb", grabOrb)
	Players.PlayerRemoving:Connect(function(p)
		bossDamage[p] = nil
		bossHitCooldown[p] = nil
	end)
end

function EventService.Start()
	task.spawn(function()
		task.wait(Events.FirstDelay)
		while true do
			if not current then
				local nextEvent = table.remove(queue, 1)
				if nextEvent then
					start(nextEvent.Id, nextEvent.By)
				else
					start(pickRandom())
				end
			end
			-- attend la fin, puis une pause (sauf si un événement payant attend)
			while current do
				task.wait(1)
			end
			local gap = math.random(Events.Gap[1], Events.Gap[2])
			local waited = 0
			while waited < gap and #queue == 0 do
				task.wait(1)
				waited += 1
			end
		end
	end)
end

return EventService
