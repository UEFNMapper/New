--!nocheck
-- Tests unitaires de la logique pure (formats, économie, tirages, croissance, quêtes).
-- Lancer : lune run tests/unit.luau
local Harness = require("./Harness")
local Shared, req = Harness.Shared("src/shared")
local test, expect, near = Harness.test, Harness.expect, Harness.near

local Format = req(Shared.Logic.Format)
local Calc = req(Shared.Logic.Calc)
local Roll = req(Shared.Logic.Roll)
local Progress = req(Shared.Logic.Progress)
local Growth = req(Shared.Config.Growth)
local Kaijus = req(Shared.Config.Kaijus)
local Rarities = req(Shared.Config.Rarities)
local Mutations = req(Shared.Config.Mutations)
local Economy = req(Shared.Config.Economy)
local Rewards = req(Shared.Config.Rewards)
local Monetization = req(Shared.Config.Monetization)
local Events = req(Shared.Config.Events)
local Builder = req(Shared.KaijuBuilder)

test("Format.Short", function()
	local cases = { [0] = "0", [5.5] = "5.5", [999] = "999", [1000] = "1K", [1234] = "1.23K", [15300] = "15.3K", [100000] = "100K", [280e9] = "280B", [1e12] = "1T", [2.5e15] = "2.5Qa" }
	for n, want in cases do
		expect(Format.Short(n) == want, ("Short(%s) = %s, attendu %s"):format(n, Format.Short(n), want))
	end
	expect(Format.Short(-1500) == "-1.5K")
end)

test("Format.Clock / Duration / Comma", function()
	expect(Format.Clock(75) == "1:15")
	expect(Format.Clock(3725) == "1:02:05")
	expect(Format.Duration(7200) == "2h")
	expect(Format.Duration(75) == "1m 15s")
	expect(Format.Comma(1234567) == "1,234,567")
end)

test("roster cohérent", function()
	expect(#Kaijus.List == 36, #Kaijus.List)
	for _, s in Kaijus.List do
		expect(Rarities.ById[s.Rarity] ~= nil, s.Id)
		expect(s.Income > 0, s.Id)
		if s.Rarity ~= "Secret" then
			expect(s.Price > 0, s.Id)
		else
			local r = s.Recipe
			expect(r and Kaijus.Get(r[1]) and Kaijus.Get(r[2]), "recette " .. s.Id)
		end
	end
end)

test("tous les kaijus se construisent (36 modèles + œufs)", function()
	for _, s in Kaijus.List do
		local model = Builder.Build(s.Id, nil, 1)
		expect(#model:GetChildren() > 8, s.Id)
		for _, m in Mutations.List do
			Builder.Build(s.Id, m.Id, 2)
		end
	end
	for _, r in Rarities.List do
		Builder.BuildEgg(r.Id)
	end
end)

test("croissance : seuils et progression", function()
	expect(Growth.StageFor(0, "Common") == 1)
	expect(Growth.StageFor(Growth.Threshold(2, "Common"), "Common") == 2)
	expect(Growth.StageFor(1e12, "Rare") == 5)
	near(Growth.Progress(30, "Common"), 0.5, 1e-9)
	expect(Growth.Threshold(3, "Legendary") > Growth.Threshold(3, "Common"))
end)

test("revenus et multiplicateurs", function()
	local rec = { Uid = "a", Species = "Toastzilla", Rarity = "Common", Growth = 0, Nest = 1 }
	near(Calc.BaseIncome(rec), 1)
	rec.Growth = Growth.Threshold(5, "Common")
	near(Calc.BaseIncome(rec), 40)
	rec.Mutation = "Gold"
	near(Calc.BaseIncome(rec), 80)
	local m = Calc.DefaultMultipliers()
	near(Calc.CashMultiplier(m), 1)
	m.DoubleCash = true
	m.Rebirths = 1
	near(Calc.CashMultiplier(m), 3)
	expect(Calc.BaseIncome({ Uid = "e", Rarity = "Rare", Growth = 0, Nest = 1, Egg = true }) == 0)
end)

test("nourriture : prix proportionnel au temps sauté", function()
	local rec = { Uid = "a", Species = "Sharkapillar", Rarity = "Rare", Growth = 0, Nest = 1 }
	local snack, steak = Calc.FoodPrice(rec, "Snack"), Calc.FoodPrice(rec, "Steak")
	expect(steak > snack, "steak plus cher")
	near(Calc.FoodGrowth(rec, "Steak"), Growth.Remaining(0, "Rare"))
end)

test("vente : croissante avec le stade", function()
	local rec = { Uid = "a", Species = "Rexplosion", Rarity = "Legendary", Growth = 0, Nest = 1 }
	local baby = Calc.SellValue(rec)
	rec.Growth = Growth.Threshold(5, "Legendary")
	expect(Calc.SellValue(rec) > baby * 10)
end)

test("tirages : raretés et chance", function()
	local rng = Harness.Random.new(7)
	local counts = {}
	for _ = 1, 20000 do
		local r = Roll.Rarity(1, rng)
		counts[r] = (counts[r] or 0) + 1
	end
	expect(counts.Common > counts.Rare and counts.Rare > counts.Epic, "ordre des raretés")
	expect(counts.Secret == nil, "jamais de Secret dans le ciel")
	local base, lucky = Roll.RarityOdds(1), Roll.RarityOdds(2)
	expect(lucky.Legendary > base.Legendary * 1.8, "la chance x2 double presque les Légendaires")
	local total = 0
	for _, v in base do
		total += v
	end
	near(total, 1, 1e-9)
end)

test("tirages : espèces et mutations", function()
	local rng = Harness.Random.new(3)
	for _, r in Rarities.List do
		if r.Weight > 0 then
			local s = Roll.Species(r.Id, rng)
			expect(Kaijus.Get(s).Rarity == r.Id)
		end
	end
	local gold = 0
	for _ = 1, 10000 do
		if Roll.Mutation(1, nil, rng) == "Gold" then
			gold += 1
		end
	end
	expect(gold > 250 and gold < 550, "Or ~4% : " .. gold)
	local blood = 0
	for _ = 1, 1000 do
		if Roll.Mutation(1, { Id = "Blood", Chance = 0.25 }, rng) == "Blood" then
			blood += 1
		end
	end
	expect(blood > 180 and blood < 320, "bonus d'événement ~25% : " .. blood)
end)

test("quêtes du jour déterministes et variées", function()
	local a = Progress.PickQuests(42, 20000)
	local b = Progress.PickQuests(42, 20000)
	expect(#a == 3 and a[1] == b[1] and a[3] == b[3])
	local stats = {}
	for _, id in a do
		local def = Progress.QuestDef(id)
		expect(not stats[def.Stat], "pas deux quêtes sur la même stat")
		stats[def.Stat] = true
	end
end)

test("série quotidienne", function()
	local day = 86400
	local can, streak, cycle = Progress.DailyState({ Streak = 0, LastDay = 0, Cycle = 0 }, 100 * day)
	expect(can and streak == 1 and cycle == 0)
	can, streak = Progress.DailyState({ Streak = 3, LastDay = 99, Cycle = 0 }, 100 * day)
	expect(can and streak == 4)
	can = Progress.DailyState({ Streak = 3, LastDay = 100, Cycle = 0 }, 100 * day + 5)
	expect(not can)
	can, streak, cycle = Progress.DailyState({ Streak = 7, LastDay = 99, Cycle = 0 }, 100 * day)
	expect(streak == 1 and cycle == 1, "boucle après 7 jours")
	expect(Progress.DailyReward(7, 1).Rarity == "Legendary")
	can, streak = Progress.DailyState({ Streak = 5, LastDay = 90, Cycle = 2 }, 100 * day)
	expect(streak == 1, "série cassée")
end)

test("configuration boutique et récompenses", function()
	local keys = {}
	for _, p in Monetization.Passes do
		expect(not keys[p.Key])
		keys[p.Key] = true
	end
	for _, p in Monetization.Products do
		expect(not keys[p.Key])
		keys[p.Key] = true
	end
	local w = 0
	for _, slot in Rewards.Wheel do
		w += slot.Weight
	end
	near(w, 100, 1e-6)
	for _, e in Events.List do
		expect(e.Duration > 0 and e.Weight > 0)
	end
	expect(#Economy.Rebirths == 25)
	for i = 2, #Economy.Rebirths do
		expect(Economy.Rebirths[i].Cost > Economy.Rebirths[i - 1].Cost)
	end
end)

local ok = Harness.report()
if not ok then
	error("tests unitaires en échec")
end
