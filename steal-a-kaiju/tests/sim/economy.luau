--!nocheck
-- ÉQUILIBRAGE : un bot joue seul pendant plusieurs heures simulées avec une
-- stratégie raisonnable et on mesure la courbe de progression.
-- Lancer : lune run tests/sim/economy.luau [heures]

local process = require("@lune/process")
local Boot = require("./boot")
local Runtime = Boot.Start()
local roblox = require("@lune/roblox")

local HOURS = tonumber(process.args[1]) or 8
local S = Runtime.Services
local Shared = S.ReplicatedStorage:FindFirstChild("Shared")
local Services = S.ServerScriptService:FindFirstChild("Server"):FindFirstChild("Services")
local function req(inst)
	return Runtime.Globals.require(inst)
end
local DataService = req(Services:FindFirstChild("DataService"))
local KaijuService = req(Services:FindFirstChild("KaijuService"))
local PlotService = req(Services:FindFirstChild("PlotService"))
local Rarities = req(Shared.Config.Rarities)
local Economy = req(Shared.Config.Economy)
local Calc = req(Shared.Logic.Calc)
local Format = req(Shared.Logic.Format)
local Growth = req(Shared.Config.Growth)
local Kaijus = req(Shared.Config.Kaijus)
local Worlds = req(Shared.Config.Worlds)
local Levels = req(Shared.Config.Levels)

local bot = Runtime.AddPlayer("Bot")
Runtime.Advance(3)
local data = DataService.Get(bot)

local milestones = {}
local function milestone(key, text)
	if not milestones[key] then
		milestones[key] = true
		print(("[%s] %s"):format(Format.Clock(Runtime.Now()), text))
	end
end

local function lowestKaiju()
	local worst, value = nil, math.huge
	for _, rec in data.Kaijus do
		if not rec.Egg then
			local v = Calc.BaseIncome(rec)
			if v < value then
				worst, value = rec, v
			end
		end
	end
	return worst, value
end

local function tryBuyMeteors()
	for _, m in S.Workspace:FindFirstChild("Meteors"):GetChildren() do
		local owner = m:GetAttribute("Owner") or 0
		if (owner == 0 or owner == bot.UserId) and (m:GetAttribute("LandAt") or 0) <= Runtime.Now() + 1790000000 then
			local price = m:GetAttribute("Price")
			local rarity = Rarities.Get(m:GetAttribute("Rarity"))
			-- prend l'œuf s'il est abordable (garde 30 % de marge pour les nids/améliorations au début)
			if price <= data.Cash then
				if not KaijuService.FreeNest(bot) then
					-- nids pleins : revendre le plus faible si l'œuf vaut mieux
					local worst, income = lowestKaiju()
					local eggIncome = 0
					for _, s in Kaijus.ByRarity[rarity.Id] or {} do
						eggIncome = math.max(eggIncome, s.Income)
					end
					if worst and eggIncome * 2.5 > income then
						Boot.Call(bot, "Sell", { Uid = worst.Uid })
					end
				end
				if KaijuService.FreeNest(bot) then
					Runtime.MoveTo(bot, m.Position)
					local r = Boot.Call(bot, "BuyMeteor", { Id = m:GetAttribute("Id") })
					if r and r.ok then
						milestone("egg_" .. rarity.Id, "premier œuf " .. rarity.Name .. " acheté (" .. Format.Cash(price) .. ")")
					end
				end
			end
		end
	end
end

local function tryUpgrades()
	for _, id in { "Reactor", "Shield", "Sneakers" } do
		local level = data.Upgrades[id]
		local u = Economy.UpgradesById[id]
		if level < u.MaxLevel then
			local price = Economy.UpgradePrice(id, level)
			if data.Cash > price * 4 then
				Boot.Call(bot, "BuyUpgrade", { Id = id })
			end
		end
	end
end

-- Mondes : ouvre le suivant dès que possible et s'installe dans le meilleur.
local lastTravel = -100
local function tryWorlds()
	for _, w in Worlds.List do
		if not data.Worlds[w.Id] and Worlds.MeetsGate(w, data.Level, data.Rebirths) and data.Cash >= w.Toll * 1.2 then
			local r = Boot.Call(bot, "UnlockWorld", { Id = w.Id })
			if r and r.ok then
				milestone("world_" .. w.Id, ("MONDE %s ouvert (niveau %d)"):format(w.Name, data.Level))
			end
		end
	end
	local best = Worlds.Best(data.Worlds)
	if Runtime.Now() - lastTravel > 60 and bot:GetAttribute("World") ~= best.Id then
		lastTravel = Runtime.Now()
		Boot.Call(bot, "Travel", { Id = best.Id })
	end
end

local function tryFeed()
	for _, rec in data.Kaijus do
		if not rec.Egg and Calc.Stage(rec) < Growth.MaxStage then
			local price = Calc.FoodPrice(rec, "Feast")
			if data.Cash > price * 6 then
				Boot.Call(bot, "Feed", { Uid = rec.Uid, Food = "Feast" })
			end
		end
	end
end

local lastCollect = 0
local samples = {}
local nextSample = 0
local total = HOURS * 3600
local step = 5
while Runtime.Now() < total do
	Runtime.Advance(step)
	local t = Runtime.Now()
	if t - lastCollect >= 30 then
		lastCollect = t
		PlotService.Get(bot).Collector.Touched:Fire(bot.Character.HumanoidRootPart)
	end
	tryBuyMeteors()
	tryUpgrades()
	tryFeed()
	tryWorlds()
	for _, l in { 5, 10, 15, 20, 25, 30, 40 } do
		if data.Level >= l then
			milestone("level" .. l, ("NIVEAU %d"):format(l))
		end
	end
	if Calc.NextRebirth(data.Rebirths) then
		local r = Boot.Call(bot, "Rebirth")
		if r and r.ok then
			milestone("rebirth" .. data.Rebirths, ("ÉVOLUTION %d (multiplicateur x%s)"):format(data.Rebirths, Format.Short(Calc.RebirthMult(data.Rebirths))))
		end
	end
	for _, rec in data.Kaijus do
		if not rec.Egg then
			local stage = Calc.Stage(rec)
			if stage >= 4 then
				milestone("titan", "premier TITAN (" .. rec.Species .. ")")
			end
			if stage >= 5 then
				milestone("colossus", "premier COLOSSE (" .. rec.Species .. ")")
			end
		end
	end
	local income = KaijuService.IncomePerSecond(bot)
	if income >= 1000 then
		milestone("1k", "revenu 1K $/s")
	end
	if income >= 1e5 then
		milestone("100k", "revenu 100K $/s")
	end
	if income >= 1e7 then
		milestone("10m", "revenu 10M $/s")
	end
	if t >= nextSample then
		nextSample += if t < 3600 then 600 else 3600
		table.insert(samples, ("  %8s | revenu %10s/s | cash %10s | niv %2d | nids %2d | kaijus %2d | évol %d | monde %s"):format(
			Format.Clock(t), Format.Cash(income), Format.Cash(data.Cash), data.Level, PlotService.UnlockedNests(bot), #data.Kaijus, data.Rebirths, Worlds.Best(data.Worlds).Id))
	end
end

print("\nCourbe de progression :")
print(table.concat(samples, "\n"))
local counts = {}
for _, rec in data.Kaijus do
	local key = rec.Rarity .. (if rec.Egg then " (œuf)" else "")
	counts[key] = (counts[key] or 0) + 1
end
print("\nKaijus en fin de session :")
for k, v in counts do
	print("  " .. k .. " x" .. v)
end
print("Erreurs Lua :", #Runtime.Errors)
for i, e in Runtime.Errors do
	if i <= 3 then
		print(tostring(e):sub(1, 600))
	end
end
