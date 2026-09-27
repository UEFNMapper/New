--!nonstrict
-- Récompenses et rétention : série quotidienne, cadeaux de temps de jeu,
-- quêtes du jour, codes, groupe, roue de la fortune, Kaijudex, statistiques.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared.Config.Rewards)
local Economy = require(Shared.Config.Economy)
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Levels = require(Shared.Config.Levels)
local Progress = require(Shared.Logic.Progress)
local Calc = require(Shared.Logic.Calc)
local Roll = require(Shared.Logic.Roll)
local Format = require(Shared.Logic.Format)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local RewardService = {}

local sessionStart: { [Player]: number } = {}
local playtimeClaimed: { [Player]: { [number]: boolean } } = {}

----------------------------------------------------------------------------
-- Attribution générique
----------------------------------------------------------------------------

-- Donne une récompense ; renvoie une description courte.
function RewardService.Grant(player: Player, reward: Rewards.Reward, source: string?): string
	local data = DataService.Get(player)
	if not data then
		return ""
	end
	if reward.Kind == "Cash" then
		local amount = Calc.CashReward(reward.Amount or 60, Registry.KaijuService.IncomePerSecond(player), reward.MinCash)
		DataService.AddCash(player, amount)
		return Format.Cash(amount)
	elseif reward.Kind == "Gems" then
		DataService.AddGems(player, reward.Amount or 0)
		return (reward.Amount or 0) .. " Gems"
	elseif reward.Kind == "Potion" then
		local id = reward.Id or "Luck"
		data.Potions[id] = (data.Potions[id] or 0) + (reward.Amount or 1)
		DataService.Replicate(player, "Potions")
		local potion = Economy.PotionsById[id]
		return (reward.Amount or 1) .. "x " .. (if potion then potion.Name else id)
	elseif reward.Kind == "Egg" then
		local rarity = reward.Rarity or "Common"
		Registry.KaijuService.GiveEgg(player, rarity, source)
		return Rarities.Get(rarity).Name .. " Egg"
	elseif reward.Kind == "Spins" then
		data.Spins += reward.Amount or 1
		DataService.Replicate(player, "Spins")
		return (reward.Amount or 1) .. " Spins"
	end
	return ""
end

----------------------------------------------------------------------------
-- Statistiques et quêtes
----------------------------------------------------------------------------

local function ensureQuests(player: Player, data: any)
	local today = Progress.DayNumber(os.time())
	if data.Quests.Day ~= today then
		local list = {}
		for _, id in Progress.PickQuests(player.UserId, today, data.Level) do
			table.insert(list, { Id = id, Progress = 0, Claimed = false })
		end
		data.Quests = { Day = today, List = list, BonusClaimed = false }
		DataService.Replicate(player, "Quests")
	end
end

function RewardService.Track(player: Player, stat: string, amount: number)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Stats[stat] = (data.Stats[stat] or 0) + amount
	ensureQuests(player, data)
	local changed = false
	for _, q in data.Quests.List do
		local def = Progress.QuestDef(q.Id)
		if def and def.Stat == stat and not q.Claimed and q.Progress < def.Goal then
			q.Progress = math.min(def.Goal, q.Progress + amount)
			changed = true
			if q.Progress >= def.Goal then
				Notify.Fx(player, "QuestReady", { Id = q.Id, Text = def.Text:format(def.Goal) })
			end
		end
	end
	if changed then
		DataService.Replicate(player, "Quests")
	end
	DataService.Replicate(player, "Stats")
	Registry.LeaderboardService.Update(player)
end

local function claimQuest(player: Player, payload: any): Router.Result
	local id = Router.String(payload.Id)
	local data = DataService.Get(player)
	if not id or not data then
		return { ok = false }
	end
	ensureQuests(player, data)
	for _, q in data.Quests.List do
		if q.Id == id then
			local def = Progress.QuestDef(id)
			if not def or q.Claimed or q.Progress < def.Goal then
				return { ok = false, msg = "Not finished yet!" }
			end
			q.Claimed = true
			local text = RewardService.Grant(player, def.Reward, "Quest")
			Registry.LevelService.AddXp(player, Levels.Xp.Quest, "Quest")
			DataService.Replicate(player, "Quests")
			Notify.Fx(player, "RewardClaimed", { Text = text, Source = "Quest" })
			return { ok = true, text = text }
		end
	end
	return { ok = false }
end

local function claimQuestBonus(player: Player): Router.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	ensureQuests(player, data)
	if data.Quests.BonusClaimed then
		return { ok = false, msg = "Already claimed today!" }
	end
	for _, q in data.Quests.List do
		if not q.Claimed then
			return { ok = false, msg = "Claim all quests first!" }
		end
	end
	data.Quests.BonusClaimed = true
	local text = RewardService.Grant(player, Rewards.AllQuestsBonus, "Daily Quests")
	Registry.LevelService.AddXp(player, Levels.Xp.QuestBonus, "Quest")
	DataService.Replicate(player, "Quests")
	Notify.Fx(player, "RewardClaimed", { Text = text, Source = "All quests" })
	return { ok = true, text = text }
end

----------------------------------------------------------------------------
-- Kaijudex
----------------------------------------------------------------------------

function RewardService.Discover(player: Player, speciesId: string, mutation: string?)
	local data = DataService.Get(player)
	if not data or not Kaijus.Get(speciesId) then
		return
	end
	local entry = data.Index[speciesId]
	local key = mutation or "Normal"
	local isNewSpecies = entry == nil
	if not entry then
		entry = {}
		data.Index[speciesId] = entry
	end
	if not entry[key] then
		entry[key] = true
		DataService.Replicate(player, "Index")
		Notify.Fx(player, "Discovered", { Species = speciesId, Mutation = mutation, NewSpecies = isNewSpecies })
		if isNewSpecies then
			Registry.KaijuService.RefreshPlayer(player)
			local species = Kaijus.Get(speciesId)
			Registry.LevelService.AddXp(player, Registry.LevelService.HatchXp(species.Rarity) * (Levels.NewSpeciesMult - 1), "NewSpecies")
		elseif mutation then
			Registry.LevelService.AddXp(player, Levels.NewMutationXp, "NewMutation")
		end
	end
end

----------------------------------------------------------------------------
-- Quotidien, temps de jeu, codes, groupe
----------------------------------------------------------------------------

local function claimDaily(player: Player): Router.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	local can, streak, cycle = Progress.DailyState(data.Daily, os.time())
	if not can then
		return { ok = false, msg = "Come back tomorrow!" }
	end
	local reward = Progress.DailyReward(streak, cycle)
	data.Daily = { Streak = streak, LastDay = Progress.DayNumber(os.time()), Cycle = cycle }
	local text = RewardService.Grant(player, reward, "Daily")
	DataService.Replicate(player, "Daily")
	Notify.Fx(player, "RewardClaimed", { Text = text, Source = "Day " .. streak })
	return { ok = true, text = text, streak = streak }
end

local function claimPlaytime(player: Player, payload: any): Router.Result
	local index = Router.Int(payload.Index, 1, #Rewards.Playtime)
	local started = sessionStart[player]
	if not index or not started then
		return { ok = false }
	end
	local claimed = playtimeClaimed[player]
	if claimed[index] then
		return { ok = false, msg = "Already claimed!" }
	end
	local entry = Rewards.Playtime[index]
	if (Workspace:GetServerTimeNow() - started) < entry.Minutes * 60 - 1 then
		return { ok = false, msg = "Not yet!" }
	end
	claimed[index] = true
	local text = RewardService.Grant(player, entry.Reward, "Gift")
	DataService.SendDerived(player, "PlaytimeClaimed", claimed)
	Notify.Fx(player, "RewardClaimed", { Text = text, Source = "Gift" })
	return { ok = true, text = text }
end

local function redeem(player: Player, payload: any): Router.Result
	local raw = Router.String(payload.Code, 32)
	local data = DataService.Get(player)
	if not raw or not data then
		return { ok = false, msg = "Invalid code" }
	end
	local code = string.upper((raw:gsub("%s", "")))
	local list = Rewards.Codes[code]
	if not list then
		return { ok = false, msg = "Invalid code" }
	end
	if data.Codes[code] then
		return { ok = false, msg = "Already redeemed!" }
	end
	data.Codes[code] = true
	local parts = {}
	for _, reward in list do
		table.insert(parts, RewardService.Grant(player, reward, "Code"))
	end
	DataService.Replicate(player, "Codes")
	local text = table.concat(parts, " + ")
	Notify.Fx(player, "RewardClaimed", { Text = text, Source = "Code " .. code })
	return { ok = true, text = text }
end

local function checkGroup(player: Player): boolean
	if Rewards.GroupId == 0 then
		return false
	end
	local ok, result = pcall(function()
		return player:IsInGroupAsync(Rewards.GroupId)
	end)
	return ok and result == true
end

local function claimGroup(player: Player): Router.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	if Rewards.GroupId == 0 then
		return { ok = false, msg = "Group rewards coming soon!" }
	end
	if data.GroupClaimed then
		return { ok = false, msg = "Already claimed!" }
	end
	if not checkGroup(player) then
		return { ok = false, msg = "Join the group first!" }
	end
	data.GroupClaimed = true
	local parts = {}
	for _, reward in Rewards.GroupReward do
		table.insert(parts, RewardService.Grant(player, reward, "Group"))
	end
	DataService.Replicate(player, "GroupClaimed")
	Registry.KaijuService.SetInGroup(player, true)
	local text = table.concat(parts, " + ")
	Notify.Fx(player, "RewardClaimed", { Text = text, Source = "Group" })
	return { ok = true, text = text }
end

----------------------------------------------------------------------------
-- Roue
----------------------------------------------------------------------------

local function spin(player: Player, payload: any): Router.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	local t = os.time()
	local cooldown = Economy.FreeSpinCooldown
	if Registry.ShopService.HasPass(player, "VIP") then
		cooldown = math.floor(cooldown * 0.5)
	end
	local source
	if data.FreeSpinAt <= t then
		data.FreeSpinAt = t + cooldown
		source = "Free"
	elseif data.Spins > 0 then
		data.Spins -= 1
		source = "Spin"
	elseif payload.UseGems == true then
		if Registry.ShopService.IsRandomRestricted(player) then
			return { ok = false, msg = "Not available in your region" }
		end
		if not DataService.Spend(player, "Gems", Economy.SpinGemPrice) then
			return { ok = false, msg = "Not enough gems" }
		end
		source = "Gems"
	else
		return { ok = false, msg = "No spins left!" }
	end
	local weights = {}
	for i, slot in Rewards.Wheel do
		weights[i] = slot.Weight
	end
	local index = Roll.Weighted(weights)
	local slot = Rewards.Wheel[index]
	DataService.Replicate(player, "Spins", "FreeSpinAt")
	-- La récompense arrive après l'animation de la roue
	task.delay(4.2, function()
		if player.Parent == Players then
			local text = RewardService.Grant(player, slot.Reward, "Wheel")
			Notify.Fx(player, "RewardClaimed", { Text = text, Source = "Wheel" })
			if slot.Reward.Kind == "Egg" and (slot.Reward.Rarity == "Mythic" or slot.Reward.Rarity == "Celestial") then
				Notify.Feed(("🎡 %s won a %s EGG on the wheel!"):format(player.DisplayName, string.upper(slot.Reward.Rarity or "")), "Rare")
			end
		end
	end)
	return { ok = true, index = index, source = source }
end

local function tutorial(player: Player, payload: any): Router.Result
	local step = Router.Int(payload.Step, 0, 10)
	local data = DataService.Get(player)
	if not step or not data then
		return { ok = false }
	end
	if step > data.Tutorial then
		data.Tutorial = step
		DataService.Replicate(player, "Tutorial")
	end
	return { ok = true }
end

local function saveSettings(player: Player, payload: any): Router.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	for _, key in { "Music", "Sfx", "LowFx" } do
		if type(payload[key]) == "boolean" then
			data.Settings[key] = payload[key]
		end
	end
	-- volumes 0..1 par pas de 0.2 (barres des réglages)
	for _, key in { "MusicVolume", "SfxVolume" } do
		local v = payload[key]
		if type(v) == "number" and v == v then
			data.Settings[key] = math.clamp(math.floor(v * 5 + 0.5) / 5, 0, 1)
		end
	end
	DataService.Replicate(player, "Settings")
	return { ok = true }
end

function RewardService.Init()
	Router.On("ClaimDaily", claimDaily, 2)
	Router.On("ClaimPlaytime", claimPlaytime, 4)
	Router.On("ClaimQuest", claimQuest, 4)
	Router.On("ClaimQuestBonus", claimQuestBonus, 2)
	Router.On("Redeem", redeem, 1)
	Router.On("ClaimGroup", claimGroup, 1)
	Router.On("Spin", spin, 1)
	Router.On("Tutorial", tutorial, 4)
	Router.On("Settings", saveSettings, 2)

	DataService.Loaded:Connect(function(player, data)
		sessionStart[player] = Workspace:GetServerTimeNow()
		playtimeClaimed[player] = {}
		DataService.SendDerived(player, "SessionStart", sessionStart[player])
		DataService.SendDerived(player, "PlaytimeClaimed", {})
		ensureQuests(player, data)
		local can = Progress.DailyState(data.Daily, os.time())
		if can then
			Notify.Fx(player, "DailyReady", {})
		end
		task.spawn(function()
			if checkGroup(player) then
				Registry.KaijuService.SetInGroup(player, true)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local data = DataService.Get(player)
		local started = sessionStart[player]
		if data and started then
			data.Stats.PlaySeconds += math.floor(Workspace:GetServerTimeNow() - started)
		end
		sessionStart[player] = nil
		playtimeClaimed[player] = nil
	end)
end

return RewardService
