--!nonstrict
-- Compagnon (Buddy) : un kaiju éclos du joueur le suit en version mini (le
-- modèle est dessiné par chaque client à partir des attributs du joueur).
-- Le serveur gère : choix du compagnon, niveau/XP, aimant à orbes, trésors
-- privés à creuser, aide au combat (siège de l'île, boss).
--
-- Attributs du joueur : BuddyUid, BuddySpecies, BuddyMutation, BuddyLevel,
-- TreasurePos (Vector3 du trésor en cours, absent sinon).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Buddy = require(Shared.Config.Buddy)
local Layout = require(Shared.Config.Layout)
local Worlds = require(Shared.Config.Worlds)
local Levels = require(Shared.Config.Levels)
local Rarities = require(Shared.Config.Rarities)
local Calc = require(Shared.Logic.Calc)
local Roll = require(Shared.Logic.Roll)
local Format = require(Shared.Logic.Format)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local BuddyService = {}

type Spot = {
	Id: string,
	Part: BasePart,
	Position: Vector3,
	ExpireAt: number,
	Index: number?,
	HoldStart: number?,
}

type PlayerState = {
	NextSpotAt: number,
	Spot: Spot?,
	LastIndex: number?,
	SwapAt: number,
}

local states: { [Player]: PlayerState } = {}
local spotsFolder: Folder
local spotCount = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

----------------------------------------------------------------------------
-- Compagnon courant
----------------------------------------------------------------------------

-- Record du compagnon (nil si aucun).
function BuddyService.Record(player: Player): Calc.KaijuRecord?
	local data = DataService.Get(player)
	if not data or data.Buddy.Uid == "" then
		return nil
	end
	local rec = Registry.KaijuService.FindRecord(data, data.Buddy.Uid)
	if rec and not rec.Egg then
		return rec
	end
	return nil
end

function BuddyService.Level(player: Player): number
	local data = DataService.Get(player)
	return if data then Buddy.Level(data.Buddy.Xp) else 1
end

-- Rayon de l'aimant (studs autour du joueur) ; 0 sans compagnon.
function BuddyService.MagnetRadius(player: Player): number
	if not BuddyService.Record(player) then
		return 0
	end
	return Buddy.MagnetRadius(BuddyService.Level(player))
end

local function syncAttributes(player: Player, data: any)
	local rec = BuddyService.Record(player)
	local function set(name: string, value: any)
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
	set("BuddyUid", if rec then rec.Uid else nil)
	set("BuddySpecies", if rec then rec.Species else nil)
	set("BuddyMutation", if rec then rec.Mutation else nil)
	set("BuddyLevel", Buddy.Level(data.Buddy.Xp))
end

-- Meilleur kaiju éclos (puissance, puis revenu).
local function bestKaiju(data: any): Calc.KaijuRecord?
	local best, bestPower, bestIncome = nil, -1, -1
	for _, rec in data.Kaijus do
		if not rec.Egg and rec.Species then
			local power, income = Calc.Power(rec), Calc.BaseIncome(rec)
			if power > bestPower or (power == bestPower and income > bestIncome) then
				best, bestPower, bestIncome = rec, power, income
			end
		end
	end
	return best
end

local function setBuddy(player: Player, data: any, uid: string, reason: string)
	local previous = data.Buddy.Uid
	data.Buddy.Uid = uid
	syncAttributes(player, data)
	DataService.Replicate(player, "Buddy")
	local rec = BuddyService.Record(player)
	local first = previous == "" and rec ~= nil
	Notify.Fx(player, "BuddyChanged", {
		Uid = uid,
		Species = if rec then rec.Species else nil,
		Mutation = if rec then rec.Mutation else nil,
		Reason = reason,
		First = first,
	})
	local st = states[player]
	if first and st then
		st.NextSpotAt = math.max(st.NextSpotAt, now() + Buddy.TreasureFirstDelay)
	end
end

-- Vérifie que le compagnon existe toujours (vendu, fusionné, volé…) ; sinon
-- passe au meilleur kaiju restant. Le premier éclos devient compagnon.
local function ensureBuddy(player: Player, data: any): Calc.KaijuRecord?
	local rec = BuddyService.Record(player)
	if rec then
		syncAttributes(player, data)
		return rec
	end
	local best = bestKaiju(data)
	local uid = if best then best.Uid else ""
	if uid ~= data.Buddy.Uid then
		setBuddy(player, data, uid, if data.Buddy.Uid == "" then "Auto" else "Lost")
	end
	return best
end

-- XP du compagnon (orbes, fouilles, kills de siège, immeubles de Rampage…).
function BuddyService.AddXp(player: Player, amount: number, reason: string?)
	local data = DataService.Get(player)
	if not data or amount <= 0 or not BuddyService.Record(player) then
		return
	end
	local before = Buddy.Level(data.Buddy.Xp)
	data.Buddy.Xp += math.floor(amount + 0.5)
	local after = Buddy.Level(data.Buddy.Xp)
	DataService.Replicate(player, "Buddy")
	if after > before then
		player:SetAttribute("BuddyLevel", after)
		Notify.Fx(player, "BuddyLevelUp", { Level = after, Radius = Buddy.MagnetRadius(after), Reason = reason })
	end
end

local function setBuddyAction(player: Player, payload: any): Router.Result
	local uid = Router.String(payload.Uid)
	local data = DataService.Get(player)
	local st = states[player]
	if not uid or not data or not st then
		return { ok = false }
	end
	local rec = Registry.KaijuService.FindRecord(data, uid)
	if not rec then
		return { ok = false, msg = "That kaiju isn't yours!" }
	end
	if rec.Egg then
		return { ok = false, msg = "Hatch it first!" }
	end
	if data.Buddy.Uid == uid then
		return { ok = false, msg = "Already your buddy!" }
	end
	local t = now()
	if t < st.SwapAt then
		return { ok = false, msg = ("You can swap buddies in %ds"):format(math.ceil(st.SwapAt - t)) }
	end
	st.SwapAt = t + Buddy.SwapCooldown
	setBuddy(player, data, uid, "Set")
	Registry.TutorialService.Notify(player, "Buddy")
	return { ok = true, cooldown = Buddy.SwapCooldown }
end

----------------------------------------------------------------------------
-- Trésors
----------------------------------------------------------------------------

type Candidate = { Position: Vector3, Weight: number }

-- ~40 points : ton île, ton pont, le bord du cratère, les autres ponts.
local function mapCandidates(player: Player): { Candidate }
	local list: { Candidate } = {}
	local w = Buddy.SpotWeights
	local plot = Registry.PlotService.Get(player)
	if plot then
		for _, v in Buddy.IslandSpots do
			table.insert(list, { Position = plot.CFrame:PointToWorldSpace(v), Weight = w.Island })
		end
		local out = Vector3.new(plot.CFrame.Position.X, 0, plot.CFrame.Position.Z).Unit
		local side = Vector3.new(-out.Z, 0, out.X)
		local from = Layout.CraterRadius - 2
		local to = (plot.CFrame.Position + plot.CFrame.LookVector * (Layout.PlotDepth / 2 - 1)).Magnitude
		for i, f in Buddy.BridgeFractions do
			local lateral = if i % 2 == 0 then Buddy.BridgeSide else -Buddy.BridgeSide
			table.insert(list, { Position = out * (from + (to - from) * f) + side * lateral, Weight = w.Bridge })
		end
	end
	local mid = (Layout.CraterRadius - 2 + Layout.PlotRadius - Layout.PlotDepth / 2) / 2
	for i = 1, Layout.PlotCount do
		if not plot or plot.Index ~= i then
			local p = Layout.PlotCFrame(i).Position
			table.insert(list, { Position = Vector3.new(p.X, 0, p.Z).Unit * mid, Weight = w.OtherBridge })
		end
	end
	for k = 0, Layout.PlotCount - 1 do
		-- entre deux ponts (les rochers du bord ont une ouverture en face de chaque pont)
		local a = (k + 0.5) / Layout.PlotCount * math.pi * 2
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		table.insert(list, { Position = dir * Buddy.RimInner, Weight = w.Rim })
		table.insert(list, { Position = dir * Buddy.RimOuter, Weight = w.Rim })
	end
	return list
end

-- Point de fouille pour ce joueur : dans l'île-arène où il se trouve, sinon
-- sur la carte principale. nil s'il est ailleurs (ville de Rampage…).
local function pickSpot(player: Player, from: Vector3, lastIndex: number?): (Vector3?, number?)
	local worldId = Worlds.At(from)
	if worldId then
		local origin = Worlds.Origin(worldId)
		local k = math.random(1, Worlds.PadCount)
		local a = k / Worlds.PadCount * math.pi * 2 + (math.random() - 0.5) * 0.3
		local r = Buddy.ArenaRadius[1] + math.random() * (Buddy.ArenaRadius[2] - Buddy.ArenaRadius[1])
		return origin + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r), nil
	end
	if Vector3.new(from.X, 0, from.Z).Magnitude > Layout.PlotRadius + Layout.PlotDepth then
		return nil, nil
	end
	local list = mapCandidates(player)
	local weights = {}
	for i, c in list do
		local flat = Vector3.new(c.Position.X - from.X, 0, c.Position.Z - from.Z).Magnitude
		weights[i] = if i == lastIndex or flat < 10 then 0 else c.Weight
	end
	local index = Roll.Weighted(weights)
	return list[index].Position, index
end

local function clearSpot(player: Player, st: PlayerState, expired: boolean)
	local spot = st.Spot
	if not spot then
		return
	end
	st.Spot = nil
	spot.Part:Destroy()
	player:SetAttribute("TreasurePos", nil)
	if expired then
		Notify.Fx(player, "BuddyTreasureGone", { Id = spot.Id })
	end
end

local function rollEggRarity(luck: number): string
	local ids, weights = {}, {}
	for id, weight in Buddy.EggWeights do
		local order = Rarities.Get(id).Order
		table.insert(ids, id)
		-- la chance favorise les raretés Épique et au-delà (comme les météores)
		table.insert(weights, if order >= 3 then weight * luck ^ (1 + (order - 3) * 0.25) else weight)
	end
	return ids[Roll.Weighted(weights)]
end

-- Tire et donne le butin d'un trésor.
local function grantLoot(player: Player): { [string]: any }
	local weights = {}
	for i, loot in Buddy.Loot do
		weights[i] = loot.Weight
	end
	local kind = Buddy.Loot[Roll.Weighted(weights)].Kind
	if kind == "Cash" then
		local amount = Registry.KaijuService.IncomeSeconds(player, Buddy.CashSeconds, Buddy.CashMin)
		DataService.AddCash(player, amount)
		return { Kind = kind, Amount = amount, Text = Format.Cash(amount) }
	elseif kind == "Potion" then
		local text = Registry.RewardService.Grant(player, { Kind = "Potion", Id = Buddy.PotionId, Amount = 1 }, "Buddy")
		return { Kind = kind, Id = Buddy.PotionId, Amount = 1, Text = text }
	elseif kind == "Gems" then
		local amount = math.random(Buddy.Gems[1], Buddy.Gems[2])
		DataService.AddGems(player, amount)
		return { Kind = kind, Amount = amount, Text = amount .. " Gems" }
	end
	local rarity = rollEggRarity(Registry.KaijuService.PersonalLuck(player))
	Registry.KaijuService.GiveEgg(player, rarity, "Buddy")
	return { Kind = "Egg", Rarity = rarity, Amount = 1, Text = Rarities.Get(rarity).Name .. " Egg" }
end

local function dig(player: Player, spot: Spot)
	local st = states[player]
	if not st or st.Spot ~= spot then
		return -- pas le propriétaire, ou déjà creusé / expiré
	end
	-- un maintien ne sert qu'une fois
	local holdStart = spot.HoldStart
	spot.HoldStart = nil
	local root = rootOf(player)
	if not root or (root.Position - spot.Part.Position).Magnitude > Buddy.DigDistance then
		Notify.Toast(player, "Get closer to dig!", "Bad")
		return
	end
	if not holdStart or os.clock() - holdStart < Buddy.DigHold - Buddy.DigHoldTolerance then
		return
	end
	clearSpot(player, st, false)
	local loot = grantLoot(player)
	loot.Id = spot.Id
	loot.Position = spot.Position
	Notify.Fx(player, "BuddyDig", loot)
	Notify.FxAll("BuddyDigWorld", { UserId = player.UserId, Position = spot.Position, Kind = loot.Kind })
	Registry.TutorialService.Notify(player, "Dig")
	Registry.RewardService.Track(player, "Digs", 1)
	Registry.LevelService.AddXp(player, Levels.Xp.Dig, "Dig")
	BuddyService.AddXp(player, Buddy.Xp.Dig, "Dig")
end

local function spawnSpot(player: Player, st: PlayerState, position: Vector3, index: number?)
	clearSpot(player, st, false)
	spotCount += 1
	local id = "T" .. spotCount
	local expire = now() + Buddy.TreasureLifetime
	local part = Instance.new("Part")
	part.Name = id
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(2, 1, 2)
	part.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
	part:SetAttribute("Id", id)
	part:SetAttribute("Owner", player.UserId)
	part:SetAttribute("ExpireAt", expire)
	local spot: Spot = { Id = id, Part = part, Position = position, ExpireAt = expire, Index = index, HoldStart = nil }
	-- Prompt visible par le seul propriétaire (les autres clients le désactivent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "DIG"
	prompt.ObjectText = "Buried Treasure"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = Buddy.DigHold
	prompt.MaxActivationDistance = Buddy.DigDistance - 0.5
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Color", "Gold")
	prompt:SetAttribute("Owner", player.UserId)
	prompt.PromptButtonHoldBegan:Connect(function(who)
		if who == player then
			spot.HoldStart = os.clock()
		end
	end)
	prompt.Triggered:Connect(function(who)
		dig(who, spot)
	end)
	prompt.Parent = part
	part.Parent = spotsFolder
	st.Spot = spot
	st.LastIndex = index
	local data = DataService.Get(player)
	st.NextSpotAt = now() + Buddy.TreasureInterval(if data then Buddy.Level(data.Buddy.Xp) else 1)
	player:SetAttribute("TreasurePos", position)
	Notify.Fx(player, "BuddyTreasure", { Id = id, Position = position, ExpireAt = expire })
end

-- Fait apparaître tout de suite un trésor sur l'île du joueur, à 15-25 studs
-- du spawn (tutoriel). Renvoie sa position.
function BuddyService.ForceTreasure(player: Player): Vector3?
	local st = states[player]
	local plot = Registry.PlotService.Get(player)
	if not st or not plot then
		return nil
	end
	local root = rootOf(player)
	local options = {}
	for _, v in Buddy.TutorialSpots do
		local pos = plot.CFrame:PointToWorldSpace(v)
		if not root or Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z).Magnitude > 6 then
			table.insert(options, pos)
		end
	end
	local pos = options[math.random(1, #options)]
	spawnSpot(player, st, pos, nil)
	return pos
end

----------------------------------------------------------------------------
-- Aimant et combat
----------------------------------------------------------------------------

local function magnet(player: Player, data: any, root: BasePart)
	local radius = Buddy.MagnetRadius(Buddy.Level(data.Buddy.Xp))
	local grabbed = Registry.EventService.GrabOrbsNear(player, root.Position, radius)
	local count = #grabbed
	local siege = Registry.SiegeService
	if siege and siege.CollectOrbsNear then
		-- renvoie (cash, nombre d'orbes) ; on compte les orbes pour l'XP du compagnon
		local cash, n = siege.CollectOrbsNear(player, root.Position, radius)
		local orbsGrabbed = if type(n) == "number" then n elseif type(cash) == "number" then cash else 0
		count += orbsGrabbed
	end
	if count > 0 then
		Notify.Fx(player, "BuddyMagnet", { Positions = grabbed, Count = count })
		BuddyService.AddXp(player, count * Buddy.Xp.Orb, "Orb")
	end
end

local function assist(player: Player, rec: Calc.KaijuRecord, root: BasePart)
	local power = Calc.Power(rec)
	local plot = Registry.PlotService.Get(player)
	local siege = Registry.SiegeService
	if plot and siege and siege.DamageNearest and Layout.InPlot(plot.CFrame, root.Position, 4) then
		local target, killed = siege.DamageNearest(player, root.Position, Buddy.AssistRange, Buddy.AssistPower * power)
		if typeof(target) == "Vector3" then
			Notify.FxAll("BuddyPounce", { UserId = player.UserId, Target = target })
		end
		if killed then
			BuddyService.AddXp(player, Buddy.Xp.SiegeKill, "SiegeKill")
		end
	end
	local event = Registry.EventService.Current()
	if event and event.Id == "BossRaid" then
		local bossPos = Registry.EventService.BuddyBossHit(player, root.Position, Buddy.AssistRange, Buddy.BossDamage(power))
		if bossPos then
			-- bond vers les pieds du boss, du côté du joueur
			local flat = Vector3.new(root.Position.X - bossPos.X, 0, root.Position.Z - bossPos.Z)
			local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)
			Notify.FxAll("BuddyPounce", { UserId = player.UserId, Target = bossPos + dir * 10, Boss = true })
		end
	end
end

----------------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------------

local function tickPlayer(player: Player, st: PlayerState, withAssist: boolean)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local rec = ensureBuddy(player, data)
	local t = now()
	if st.Spot and t >= st.Spot.ExpireAt then
		clearSpot(player, st, true)
	end
	local root = rootOf(player)
	if not rec or not root then
		return
	end
	-- pendant le tutoriel, c'est la mission « DIG UP A TREASURE » qui fait apparaître le trésor
	if not st.Spot and t >= st.NextSpotAt and Registry.TutorialService.IsDone(player) then
		local pos, index = pickSpot(player, root.Position, st.LastIndex)
		if pos then
			spawnSpot(player, st, pos, index)
		else
			st.NextSpotAt = t + 5
		end
	end
	magnet(player, data, root)
	if withAssist then
		assist(player, rec, root)
	end
end

function BuddyService.Init()
	spotsFolder = Instance.new("Folder")
	spotsFolder.Name = "DigSpots"
	spotsFolder.Parent = Workspace

	Router.On("SetBuddy", setBuddyAction, 2)

	DataService.Loaded:Connect(function(player)
		states[player] = { NextSpotAt = now() + Buddy.TreasureFirstDelay, Spot = nil, LastIndex = nil, SwapAt = 0 }
	end)
	Players.PlayerRemoving:Connect(function(player)
		local st = states[player]
		if st then
			clearSpot(player, st, false)
			states[player] = nil
		end
	end)

	task.spawn(function()
		local assistEvery = math.max(1, math.floor(Buddy.AssistTick / Buddy.MagnetTick + 0.5))
		local tick = 0
		while true do
			task.wait(Buddy.MagnetTick)
			tick += 1
			for player, st in states do
				local ok, err = pcall(tickPlayer, player, st, tick % assistEvery == 0)
				if not ok then
					warn("[BuddyService] tick : " .. tostring(err))
				end
			end
		end
	end)
end

return BuddyService
