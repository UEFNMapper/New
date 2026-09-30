-- Tests des modules partagés : format, schéma de données, limiteur, configs.
local NumberFormat = Shim.load("src/shared/Util/NumberFormat.luau")
local DataSchema = Shim.load("src/shared/Data/DataSchema.luau")
local RateLimiter = Shim.load("src/server/Security/RateLimiter.luau")
local Nanobots = Shim.load("src/shared/Config/Nanobots.luau")
local Modules = Shim.load("src/shared/Config/Modules.luau")
local Zones = Shim.load("src/shared/Config/Zones.luau")
local Products = Shim.load("src/shared/Config/Products.luau")
local Quests = Shim.load("src/shared/Config/Quests.luau")
local Bonuses = Shim.load("src/shared/Economy/Bonuses.luau")

return {
	["NumberFormat.Compact"] = function()
		Expect.equal(NumberFormat.Compact(0), "0")
		Expect.equal(NumberFormat.Compact(7.5), "7,5")
		Expect.equal(NumberFormat.Compact(999), "999")
		Expect.equal(NumberFormat.Compact(1000), "1K")
		Expect.equal(NumberFormat.Compact(1234), "1,23K")
		Expect.equal(NumberFormat.Compact(25000), "25K")
		Expect.equal(NumberFormat.Compact(999999), "1M")
		Expect.equal(NumberFormat.Compact(2.5e12), "2,5T")
		Expect.equal(NumberFormat.Compact(1e17), "100Qa")
		Expect.equal(NumberFormat.Compact(-1500), "-1,5K")
	end,
	["NumberFormat.Duration / Grouped / Flops"] = function()
		Expect.equal(NumberFormat.Duration(45), "45 s")
		Expect.equal(NumberFormat.Duration(125), "2 min 5 s")
		Expect.equal(NumberFormat.Duration(900), "15 min")
		Expect.equal(NumberFormat.Duration(3725), "1 h 02")
		Expect.equal(NumberFormat.Duration(90000), "1 j 1 h")
		Expect.equal(NumberFormat.Grouped(1234567), "1 234 567")
		Expect.equal(NumberFormat.Grouped(123), "123")
		Expect.equal(NumberFormat.Flops(2500000), "2,5 MFLOPS")
	end,
	["DataSchema : template, migration, reçus"] = function()
		local fresh = DataSchema.Template()
		Expect.equal(fresh.Version, DataSchema.CURRENT_VERSION)
		-- Données partielles (ancien joueur) : les champs manquants sont complétés.
		local old: any = { Bits = 42, Levels = { Z1M1 = 7 }, Settings = { Music = 0.1 } }
		Expect.truthy(DataSchema.Migrate(old))
		Expect.equal(old.Bits, 42)
		Expect.equal(old.Levels.Z1M1, 7)
		Expect.equal(old.Settings.Music, 0.1, "valeur existante conservée")
		Expect.equal(old.Settings.Sfx, 0.7, "valeur manquante complétée")
		Expect.equal(old.Stats.Playtime, 0)
		Expect.equal(old.Download.Kind, "")
		-- Données d'une version future : ne pas toucher.
		local future: any = { Version = DataSchema.CURRENT_VERSION + 1 }
		Expect.equal(DataSchema.Migrate(future), false)
		-- Reçus : historique borné.
		for i = 1, DataSchema.MAX_RECEIPTS + 10 do
			DataSchema.AddReceipt(fresh, `p{i}`)
		end
		Expect.equal(#fresh.Receipts, DataSchema.MAX_RECEIPTS)
		Expect.truthy(DataSchema.HasReceipt(fresh, `p{DataSchema.MAX_RECEIPTS + 10}`))
		Expect.equal(DataSchema.HasReceipt(fresh, "p1"), false)
	end,
	["RateLimiter : burst puis recharge"] = function()
		local t = 0
		local limiter = RateLimiter.new(2, 3, function()
			return t
		end)
		Expect.truthy(limiter:Allow("u1:x"))
		Expect.truthy(limiter:Allow("u1:x"))
		Expect.truthy(limiter:Allow("u1:x"))
		Expect.equal(limiter:Allow("u1:x"), false, "burst épuisé")
		Expect.truthy(limiter:Allow("u2:x"), "autre joueur indépendant")
		t = 0.5
		Expect.truthy(limiter:Allow("u1:x"), "1 jeton rechargé après 0,5 s à 2/s")
		Expect.equal(limiter:Allow("u1:x"), false)
		limiter:Forget("u1:")
		Expect.truthy(limiter:Allow("u1:x"), "seau recréé après Forget")
	end,
	["configs cohérentes"] = function()
		Expect.equal(#Zones, 7)
		Expect.equal(#Modules.List, 21)
		for i = 2, #Zones do
			Expect.truthy(Zones[i].UnlockCost > Zones[i - 1].UnlockCost, "coûts de zone croissants")
		end
		for _, capsule in Nanobots.Capsules do
			local total = 0
			for _, entry in Nanobots.OddsPercent(capsule.Id) do
				total += entry.percent
				Expect.truthy(#Nanobots.Pool(capsule.Id, entry.rarity) > 0, `pool {capsule.Id}/{entry.rarity}`)
			end
			Expect.near(total, 100, 1e-6, `probas {capsule.Id}`)
		end
		local seen = {}
		for _, p in Products.Products do
			Expect.equal(seen[p.Key], nil, "clé produit unique")
			seen[p.Key] = true
		end
		for _, q in Quests.Daily do
			Expect.truthy(Quests.ById[q.Id] ~= nil)
		end
		Expect.equal(#Quests.DailyRewards, 7)
	end,
	["Bonuses : cumul des multiplicateurs"] = function()
		local b = Bonuses.Compute({
			Firmware = 10,
			FragmentsFound = 5,
			EquippedNanobots = { { Id = "Bronze_1", Golden = false }, { Id = "Cryo_1", Golden = true } },
			HasDoubleBits = true,
			IsPremium = true,
			InGroup = false,
			FriendsInServer = 5,
			ServerBoostActive = false,
			PersonalBoostActive = false,
			OverclockMult = 1,
		})
		-- firmware 1+10*0.1=2 ; additifs 0.05+0.05+0.30+0.10=0.5 ; pass x2 => 2*1.5*2 = 6
		Expect.near(b.Total, 6, 1e-9)
		Expect.near(b.HeatReduction, 0.045, 1e-9, "Cryo_1 doré : 0.03 * 1.5")
	end,
}
