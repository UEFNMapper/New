--!nonstrict
-- Kaijus possédés : œufs, éclosion, croissance, revenus, collecteur, vente,
-- nourriture, transfert (vol). Chaque kaiju a une « ancre » invisible dans
-- workspace.Kaijus : le client en lit les attributs et fabrique le modèle 3D.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Growth = require(Shared.Config.Growth)
local Economy = require(Shared.Config.Economy)
local Calc = require(Shared.Logic.Calc)
local Roll = require(Shared.Logic.Roll)
local Format = require(Shared.Logic.Format)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local KaijuService = {}

type Record = Calc.KaijuRecord

local folder: Folder
local anchors: { [string]: BasePart } = {} -- Uid -> ancre
local ownerFolders: { [Player]: Folder } = {}
local multCache: { [Player]: number } = {}
local friendCount: { [Player]: number } = {}
local inGroup: { [Player]: boolean } = {}
local lastIncome: { [Player]: number } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function findRecord(data: any, uid: string): (Record?, number?)
	for i, rec in data.Kaijus do
		if rec.Uid == uid then
			return rec, i
		end
	end
	return nil, nil
end

KaijuService.FindRecord = findRecord

function KaijuService.Anchor(uid: string): BasePart?
	return anchors[uid]
end

-- Propriétaire d'une ancre.
function KaijuService.OwnerOf(uid: string): Player?
	local anchor = anchors[uid]
	if not anchor then
		return nil
	end
	return Players:GetPlayerByUserId(anchor:GetAttribute("Owner") or 0)
end

----------------------------------------------------------------------------
-- Multiplicateurs
----------------------------------------------------------------------------

local function indexCount(data: any): number
	local n = 0
	for _ in data.Index do
		n += 1
	end
	return n
end

function KaijuService.Multiplier(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 1
	end
	local Shop = Registry.ShopService
	local event = Registry.EventService.Current()
	local m: Calc.Multipliers = {
		Rebirths = data.Rebirths,
		Reactor = data.Upgrades.Reactor,
		VIP = Shop.HasPass(player, "VIP"),
		DoubleCash = Shop.HasPass(player, "DoubleCash"),
		Friends = friendCount[player] or 0,
		Premium = player.MembershipType == Enum.MembershipType.Premium,
		Group = inGroup[player] == true,
		IndexCount = indexCount(data),
		CashPotion = data.Boosts.Cash > os.time(),
		EventCash = if event then event.CashMult else 1,
	}
	return Calc.CashMultiplier(m)
end

function KaijuService.GrowthRate(player: Player): number
	local data = DataService.Get(player)
	local rate = 1
	if Registry.ShopService.HasPass(player, "FastGrowth") then
		rate *= 1.5
	end
	if data and data.Boosts.Growth > os.time() then
		rate *= 2
	end
	return rate
end

function KaijuService.PersonalLuck(player: Player): number
	local data = DataService.Get(player)
	local luck = 1
	if data then
		luck *= Calc.RebirthLuck(data.Rebirths)
		if data.Boosts.Luck > os.time() then
			luck *= 2
		end
	end
	if Registry.ShopService.HasPass(player, "LuckyAura") then
		luck *= 2
	end
	return luck
end

function KaijuService.IncomePerSecond(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local total = 0
	for _, rec in data.Kaijus do
		local anchor = anchors[rec.Uid]
		if not (anchor and (anchor:GetAttribute("CarriedBy") or 0) ~= 0) then
			total += Calc.BaseIncome(rec)
		end
	end
	return total * (multCache[player] or KaijuService.Multiplier(player))
end

function KaijuService.RefreshPlayer(player: Player)
	multCache[player] = KaijuService.Multiplier(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local rate = KaijuService.GrowthRate(player)
	for _, rec in data.Kaijus do
		local anchor = anchors[rec.Uid]
		if anchor then
			anchor:SetAttribute("Income", Calc.BaseIncome(rec) * multCache[player])
			anchor:SetAttribute("GrowthRate", rate)
		end
	end
	DataService.SendDerived(player, "Multiplier", multCache[player])
	DataService.SendDerived(player, "Luck", KaijuService.PersonalLuck(player))
	DataService.SendDerived(player, "GrowthRate", rate)
end

----------------------------------------------------------------------------
-- Ancres
----------------------------------------------------------------------------

local function syncAnchor(player: Player, rec: Record)
	local plot = Registry.PlotService.Get(player)
	if not plot then
		return
	end
	local anchor = anchors[rec.Uid]
	if not anchor then
		local p = Instance.new("Part")
		p.Name = rec.Uid
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(2, 2, 2)
		p.Parent = ownerFolders[player]
		anchors[rec.Uid] = p
		anchor = p
	end
	assert(anchor)
	anchor.CFrame = Registry.PlotService.NestCFrame(plot, rec.Nest)
	anchor:SetAttribute("Uid", rec.Uid)
	anchor:SetAttribute("Owner", player.UserId)
	anchor:SetAttribute("OwnerName", player.DisplayName)
	anchor:SetAttribute("Plot", plot.Index)
	anchor:SetAttribute("Nest", rec.Nest)
	anchor:SetAttribute("Rarity", rec.Rarity)
	anchor:SetAttribute("Egg", rec.Egg == true)
	anchor:SetAttribute("HatchAt", rec.HatchAt or 0)
	anchor:SetAttribute("Species", rec.Species or "")
	anchor:SetAttribute("Mutation", rec.Mutation or "")
	anchor:SetAttribute("Stage", Calc.Stage(rec))
	anchor:SetAttribute("Growth", rec.Growth)
	anchor:SetAttribute("GrowthStamp", serverNow())
	anchor:SetAttribute("GrowthRate", KaijuService.GrowthRate(player))
	anchor:SetAttribute("Income", Calc.BaseIncome(rec) * (multCache[player] or 1))
	anchor:SetAttribute("SellValue", Calc.SellValue(rec))
	if anchor:GetAttribute("CarriedBy") == nil then
		anchor:SetAttribute("CarriedBy", 0)
	end
end

local function destroyAnchor(uid: string)
	local anchor = anchors[uid]
	if anchor then
		anchors[uid] = nil
		anchor:Destroy()
	end
end

KaijuService.SyncAnchor = syncAnchor

----------------------------------------------------------------------------
-- Nids et œufs
----------------------------------------------------------------------------

function KaijuService.FreeNest(player: Player): number?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local used = {}
	for _, rec in data.Kaijus do
		used[rec.Nest] = true
	end
	for slot = 1, Registry.PlotService.UnlockedNests(player) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

local function newUid(data: any): string
	local uid = string.format("%x-%x", data.NextUid, math.random(0, 0xFFFF))
	data.NextUid += 1
	return uid
end

-- Ajoute un œuf dans un nid libre. Renvoie le record ou nil si plein.
function KaijuService.AddEgg(player: Player, rarity: string, hatchSeconds: number?): Record?
	local data = DataService.Get(player)
	local slot = KaijuService.FreeNest(player)
	if not data or not slot then
		return nil
	end
	local r = Rarities.Get(rarity)
	local rec: Record = {
		Uid = newUid(data),
		Rarity = r.Id,
		Growth = 0,
		Nest = slot,
		Egg = true,
		HatchAt = os.time() + (hatchSeconds or r.HatchTime),
		Born = os.time(),
	}
	table.insert(data.Kaijus, rec)
	syncAnchor(player, rec)
	DataService.Replicate(player, "Kaijus")
	return rec
end

-- Œuf offert (récompenses, rebirth…) : mis en attente si aucun nid libre.
function KaijuService.GiveEgg(player: Player, rarity: string, source: string?)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local rec = KaijuService.AddEgg(player, rarity)
	local r = Rarities.Get(rarity)
	if rec then
		Notify.Fx(player, "EggGift", { Rarity = rarity, Source = source, Uid = rec.Uid })
	else
		table.insert(data.PendingEggs, rarity)
		DataService.Replicate(player, "PendingEggs")
		Notify.Toast(player, ("%s egg saved! Free a nest to place it."):format(r.Name), "Info")
	end
end

function KaijuService.PlacePending(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local changed = false
	while #data.PendingEggs > 0 and KaijuService.FreeNest(player) do
		local rarity = table.remove(data.PendingEggs, 1) :: string
		KaijuService.AddEgg(player, rarity)
		changed = true
	end
	if changed then
		DataService.Replicate(player, "PendingEggs")
	end
end

local function hatch(player: Player, data: any, rec: Record)
	local event = Registry.EventService.Current()
	local luck = KaijuService.PersonalLuck(player)
	local bonus = nil
	if event and event.Mutation and event.MutationChance then
		bonus = { Id = event.Mutation, Chance = event.MutationChance }
	end
	rec.Species = rec.Species or Roll.Species(rec.Rarity)
	if rec.Mutation == nil then
		rec.Mutation = Roll.Mutation(luck, bonus)
	end
	rec.Egg = nil
	rec.HatchAt = nil
	rec.Growth = 0
	syncAnchor(player, rec)
	DataService.Replicate(player, "Kaijus")

	local species = Kaijus.Get(rec.Species :: string)
	local rarity = Rarities.Get(rec.Rarity)
	Notify.Fx(player, "Hatch", { Uid = rec.Uid, Species = rec.Species, Mutation = rec.Mutation, Rarity = rec.Rarity })
	Notify.FxAll("HatchWorld", { Uid = rec.Uid, Rarity = rec.Rarity })
	Registry.RewardService.Discover(player, rec.Species :: string, rec.Mutation)
	Registry.RewardService.Track(player, "Hatches", 1)
	Registry.TutorialService.Notify(player, "Hatch")
	if rarity.Announce and species then
		local mut = if rec.Mutation then rec.Mutation .. " " else ""
		Notify.Feed(("%s hatched a %s%s %s!"):format(player.DisplayName, mut, string.upper(rarity.Name), species.Name), "Rare", rarity.Color)
	end
	KaijuService.RefreshPlayer(player)
end

function KaijuService.HatchAll(player: Player): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local any = false
	for _, rec in data.Kaijus do
		if rec.Egg then
			rec.HatchAt = os.time()
			any = true
		end
	end
	if not any then
		-- Aucun œuf : on compense pour que l'achat ne soit jamais perdu
		DataService.AddGems(player, 20)
		Notify.Toast(player, "No eggs to hatch: +20 gems instead!", "Gem")
	end
	return true
end

-- Crée directement un kaiju éclos (fusion, admin).
function KaijuService.AddHatched(player: Player, speciesId: string, mutation: string?, growth: number?): Record?
	local data = DataService.Get(player)
	local slot = KaijuService.FreeNest(player)
	local species = Kaijus.Get(speciesId)
	if not data or not slot or not species then
		return nil
	end
	local rec: Record = {
		Uid = newUid(data),
		Species = species.Id,
		Rarity = species.Rarity,
		Mutation = mutation,
		Growth = growth or 0,
		Nest = slot,
		Born = os.time(),
	}
	table.insert(data.Kaijus, rec)
	syncAnchor(player, rec)
	DataService.Replicate(player, "Kaijus")
	Registry.RewardService.Discover(player, species.Id, mutation)
	KaijuService.RefreshPlayer(player)
	return rec
end

function KaijuService.RemoveRecord(player: Player, uid: string): Record?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local rec, index = findRecord(data, uid)
	if not rec or not index then
		return nil
	end
	table.remove(data.Kaijus, index)
	destroyAnchor(uid)
	DataService.Replicate(player, "Kaijus")
	return rec
end

-- Transfert (vol réussi) : garde croissance et mutation, nouveau nid.
function KaijuService.Transfer(from: Player, uid: string, to: Player): Record?
	local toData = DataService.Get(to)
	local slot = KaijuService.FreeNest(to)
	if not toData or not slot then
		return nil
	end
	local rec = KaijuService.RemoveRecord(from, uid)
	if not rec then
		return nil
	end
	rec.Nest = slot
	rec.Uid = newUid(toData)
	table.insert(toData.Kaijus, rec)
	syncAnchor(to, rec)
	DataService.Replicate(to, "Kaijus")
	if rec.Species then
		Registry.RewardService.Discover(to, rec.Species, rec.Mutation)
	end
	KaijuService.RefreshPlayer(from)
	KaijuService.RefreshPlayer(to)
	KaijuService.PlacePending(from)
	return rec
end

function KaijuService.InstantGrow(player: Player, uid: string?): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local target: Record? = nil
	if uid then
		target = findRecord(data, uid)
	end
	if not target or target.Egg or Calc.Stage(target) >= Growth.MaxStage then
		-- sinon : le plus petit kaiju non adulte
		for _, rec in data.Kaijus do
			if not rec.Egg and Calc.Stage(rec) < Growth.MaxStage then
				if not target or Calc.BaseIncome(rec) > Calc.BaseIncome(target) then
					target = rec
				end
			end
		end
	end
	if not target or target.Egg or Calc.Stage(target) >= Growth.MaxStage then
		-- Rien à faire grandir : compensation
		DataService.AddGems(player, 25)
		Notify.Toast(player, "Nothing to grow: +25 gems instead!", "Gem")
		return true
	end
	local stage = Calc.Stage(target)
	target.Growth = Growth.Threshold(stage + 1, target.Rarity) + 0.5
	return true -- la boucle détecte le changement de stade
end

----------------------------------------------------------------------------
-- Collecteur
----------------------------------------------------------------------------

function KaijuService.Collect(player: Player)
	local data = DataService.Get(player)
	if not data or data.Stored < 1 then
		return
	end
	local amount = math.floor(data.Stored)
	data.Stored -= amount
	DataService.AddCash(player, amount)
	DataService.Replicate(player, "Stored")
	Notify.Fx(player, "Collect", { Amount = amount })
	Registry.RewardService.Track(player, "Collects", 1)
	Registry.TutorialService.Notify(player, "Collect")
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

local function sell(player: Player, payload: any): Router.Result
	local uid = Router.String(payload.Uid)
	local data = DataService.Get(player)
	if not uid or not data then
		return { ok = false }
	end
	local rec = findRecord(data, uid)
	local anchor = anchors[uid]
	if not rec or rec.Egg then
		return { ok = false, msg = "Can't sell this" }
	end
	if anchor and (anchor:GetAttribute("CarriedBy") or 0) ~= 0 then
		return { ok = false, msg = "It's being stolen!" }
	end
	local value = Calc.SellValue(rec)
	KaijuService.RemoveRecord(player, uid)
	DataService.AddCash(player, value, false)
	Notify.Fx(player, "Sold", { Amount = value, Species = rec.Species })
	KaijuService.RefreshPlayer(player)
	KaijuService.PlacePending(player)
	return { ok = true, amount = value }
end

local function feed(player: Player, payload: any): Router.Result
	local uid = Router.String(payload.Uid)
	local foodId = Router.String(payload.Food)
	local data = DataService.Get(player)
	if not uid or not foodId or not data or not Economy.FoodsById[foodId] then
		return { ok = false }
	end
	local rec = findRecord(data, uid)
	if not rec or rec.Egg then
		return { ok = false, msg = "Can't feed this" }
	end
	if Calc.Stage(rec) >= Growth.MaxStage then
		return { ok = false, msg = "Already fully grown!" }
	end
	local price = Calc.FoodPrice(rec, foodId)
	if not DataService.Spend(player, "Cash", price) then
		return { ok = false, msg = "Not enough cash (" .. Format.Cash(price) .. ")" }
	end
	rec.Growth += Calc.FoodGrowth(rec, foodId)
	local anchor = anchors[uid]
	if anchor then
		anchor:SetAttribute("Growth", rec.Growth)
		anchor:SetAttribute("GrowthStamp", serverNow())
	end
	Notify.FxAll("Fed", { Uid = uid, Food = foodId })
	Registry.RewardService.Track(player, "Feeds", 1)
	return { ok = true }
end

----------------------------------------------------------------------------
-- Boucle principale
----------------------------------------------------------------------------

local function tickPlayer(player: Player, dt: number)
	local data = DataService.Get(player)
	local plot = Registry.PlotService.Get(player)
	if not data or not plot then
		return
	end
	local now = os.time()
	local rate = KaijuService.GrowthRate(player)
	local mult = multCache[player] or KaijuService.Multiplier(player)
	local income = 0
	local changed = false

	for _, rec in table.clone(data.Kaijus) do
		local anchor = anchors[rec.Uid]
		if rec.Egg then
			if rec.HatchAt and now >= rec.HatchAt then
				hatch(player, data, rec)
			end
		else
			local carried = anchor and (anchor:GetAttribute("CarriedBy") or 0) ~= 0
			if not carried then
				local before = Calc.Stage(rec)
				rec.Growth += dt * rate
				local after = Calc.Stage(rec)
				if after > before then
					changed = true
					if anchor then
						syncAnchor(player, rec)
					end
					Notify.FxAll("StageUp", { Uid = rec.Uid, Stage = after })
					local stage = Growth.Get(after)
					local species = Kaijus.Get(rec.Species or "")
					Notify.Toast(player, ("%s grew into a %s!"):format(if species then species.Name else "Kaiju", string.upper(stage.Name)), "Good")
					Registry.RewardService.Track(player, "StageUps", after - before)
				end
				income += Calc.BaseIncome(rec)
			end
		end
	end

	if changed then
		DataService.Replicate(player, "Kaijus")
		KaijuService.RefreshPlayer(player)
		mult = multCache[player]
	end

	local earned = income * mult * dt
	if earned > 0 then
		if Registry.ShopService.HasPass(player, "AutoCollect") then
			data.Cash += earned
			data.TotalEarned += earned
			DataService.Replicate(player, "Cash", "TotalEarned")
		else
			data.Stored += earned
			DataService.Replicate(player, "Stored")
		end
	end
	plot.Model:SetAttribute("Stored", data.Stored)
	local label = plot.CollectorGui:FindFirstChild("Amount") :: TextLabel?
	if label then
		label.Text = Format.Cash(data.Stored)
	end

	local perSecond = income * mult
	if lastIncome[player] ~= perSecond then
		lastIncome[player] = perSecond
		DataService.SendDerived(player, "Income", perSecond)
	end
end

-- Gains et croissance hors ligne au chargement.
local function applyOffline(player: Player, data: any)
	if data.LastOnline <= 0 then
		return
	end
	local elapsed = math.max(0, os.time() - data.LastOnline)
	if elapsed < 60 then
		return
	end
	local maxHours = if Registry.ShopService.HasPass(player, "Offline") then Economy.OfflineMaxHoursPass else Economy.OfflineMaxHours
	local capped = math.min(elapsed, maxHours * 3600)
	local income = 0
	for _, rec in data.Kaijus do
		if not rec.Egg then
			rec.Growth += elapsed
			income += Calc.BaseIncome(rec)
		end
	end
	local amount = math.floor(income * KaijuService.Multiplier(player) * capped * Economy.OfflineRate)
	if amount > 0 then
		data.Stored += amount
		Notify.Fx(player, "WelcomeBack", { Amount = amount, Seconds = elapsed, Capped = capped < elapsed, MaxHours = maxHours })
	end
end

local function onLoaded(player: Player, data: any)
	local f = Instance.new("Folder")
	f.Name = tostring(player.UserId)
	f.Parent = folder
	ownerFolders[player] = f

	-- Nettoyage : nids hors limites (ex. pass expiré) -> œufs en attente
	-- Attend que l'île soit attribuée
	local t0 = os.clock()
	while not Registry.PlotService.Get(player) and os.clock() - t0 < 10 do
		task.wait()
	end
	-- Attend que les pass soient connus (1re fois)
	task.wait(0.5)
	applyOffline(player, data)
	local limit = Registry.PlotService.UnlockedNests(player)
	local used: { [number]: boolean } = {}
	for _, rec in table.clone(data.Kaijus) do
		if rec.Nest > limit or used[rec.Nest] then
			local slot = nil
			for s = 1, limit do
				if not used[s] then
					slot = s
					break
				end
			end
			if slot then
				rec.Nest = slot
			else
				local i = table.find(data.Kaijus, rec)
				if i then
					table.remove(data.Kaijus, i)
				end
				if rec.Egg then
					table.insert(data.PendingEggs, rec.Rarity)
				elseif rec.Species then
					-- revendu automatiquement plutôt que perdu
					data.Cash += Calc.SellValue(rec)
				end
				continue
			end
		end
		used[rec.Nest] = true
	end
	multCache[player] = KaijuService.Multiplier(player)
	for _, rec in data.Kaijus do
		syncAnchor(player, rec)
	end

	-- Premier œuf offert (éclosion rapide) pour accrocher dès la 1re minute
	if data.Tutorial == 0 and #data.Kaijus == 0 and data.TotalEarned == 0 then
		KaijuService.AddEgg(player, "Common", 6)
	end
	DataService.Replicate(player, "Kaijus", "Stored", "Cash", "PendingEggs")
	KaijuService.RefreshPlayer(player)
	KaijuService.PlacePending(player)
end

local function refreshFriends()
	local list = Players:GetPlayers()
	for _, player in list do
		task.spawn(function()
			local n = 0
			for _, other in list do
				if other ~= player then
					local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
					if ok and isFriend then
						n += 1
					end
				end
			end
			if friendCount[player] ~= n then
				friendCount[player] = n
				DataService.SendDerived(player, "Friends", n)
				KaijuService.RefreshPlayer(player)
			end
		end)
	end
end

function KaijuService.SetInGroup(player: Player, value: boolean)
	inGroup[player] = value
	KaijuService.RefreshPlayer(player)
end

function KaijuService.Init()
	folder = Workspace:WaitForChild("Kaijus") :: Folder

	Router.On("Sell", sell, 4)
	Router.On("Feed", feed, 6)

	DataService.Loaded:Connect(onLoaded)
	DataService.Releasing:Connect(function(player)
		-- Un kaiju en cours de vol revient chez son propriétaire (rien à faire :
		-- les records ne quittent la sauvegarde qu'à la livraison).
		local f = ownerFolders[player]
		if f then
			for _, child in f:GetChildren() do
				anchors[child.Name] = nil
			end
			f:Destroy()
		end
		ownerFolders[player] = nil
		multCache[player] = nil
		friendCount[player] = nil
		inGroup[player] = nil
		lastIncome[player] = nil
	end)

	Players.PlayerAdded:Connect(function()
		task.delay(2, refreshFriends)
	end)
	Players.PlayerRemoving:Connect(function()
		task.delay(1, refreshFriends)
	end)

	-- Boucle d'une seconde
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = math.min(now - last, 5)
			last = now
			for player in ownerFolders do
				local ok, err = pcall(tickPlayer, player, dt)
				if not ok then
					warn("[KaijuService] tick : " .. tostring(err))
				end
			end
		end
	end)

	-- Rafraîchit les multiplicateurs (potions qui expirent, événements…)
	task.spawn(function()
		while true do
			task.wait(10)
			for player in ownerFolders do
				KaijuService.RefreshPlayer(player)
			end
		end
	end)
end

return KaijuService
