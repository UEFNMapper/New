-- Tests des modules partagés : format, temps, schéma de données, limiteur, configs du deathrun.
local NumberFormat = Shim.load("src/shared/Util/NumberFormat.luau")
local Time = Shim.load("src/shared/Util/Time.luau")
local DataSchema = Shim.load("src/shared/Data/DataSchema.luau")
local RateLimiter = Shim.load("src/server/Security/RateLimiter.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")
local GameConfig = Shim.load("src/shared/Config/GameConfig.luau")
local Cosmetics = Shim.load("src/shared/Config/Cosmetics.luau")
local Missions = Shim.load("src/shared/Config/Missions.luau")
local Products = Shim.load("src/shared/Config/Products.luau")
local Incidents = Shim.load("src/shared/Config/Incidents.luau")

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
	end,
	["Time : jours UTC et chrono"] = function()
		Expect.equal(Time.DayIndex(0), 0)
		Expect.equal(Time.DayIndex(86400 * 3 + 5), 3)
		Expect.equal(Time.WeekIndex(0), 0, "jeudi 1er janvier 1970 : semaine 0")
		Expect.equal(Time.WeekIndex(86400 * 4), 1, "le lundi suivant change de semaine")
		Expect.equal(Time.Clock(0), "0:00.0")
		Expect.equal(Time.Clock(65.37), "1:05.3")
		Expect.equal(Time.Clock(3725), "1:02:05")
	end,
	["DataSchema : template, migration, fin d'ascension, reçus"] = function()
		local fresh = DataSchema.Template()
		Expect.equal(fresh.Version, DataSchema.CURRENT_VERSION)
		Expect.equal(fresh.Stage, 0)
		Expect.truthy(
			table.find(fresh.Cosmetics.Owned, Cosmetics.DefaultTrail) ~= nil,
			"traînée par défaut possédée"
		)
		Expect.truthy(table.find(fresh.Cosmetics.Owned, Cosmetics.DefaultDeathFx) ~= nil, "effet par défaut possédé")
		-- Données partielles : les champs manquants sont complétés, l'existant est gardé.
		local old: any = { Bits = 42, Stage = 12, Settings = { Music = 0.1 } }
		Expect.truthy(DataSchema.Migrate(old))
		Expect.equal(old.Bits, 42)
		Expect.equal(old.Stage, 12)
		Expect.equal(old.Settings.Music, 0.1, "valeur existante conservée")
		Expect.equal(old.Settings.Sfx, 0.7, "valeur manquante complétée")
		Expect.equal(old.Stats.CoinsCollected, 0)
		Expect.equal(old.Toggles.LowGravity, false)
		-- Fin d'ascension : la course repart de zéro, les records restent.
		old.Wins = 3
		old.RunCoins = { S1C1 = true }
		old.Cleared = 7
		DataSchema.ResetRun(old)
		Expect.equal(old.Stage, 0)
		Expect.equal(old.Cleared, 0)
		Expect.equal(next(old.RunCoins), nil)
		Expect.equal(old.Wins, 3, "victoires conservées")
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
	["Tower : mondes, étapes, helpers"] = function()
		Expect.equal(Tower.WORLD_COUNT, 7)
		Expect.equal(Tower.TOTAL_STAGES, Tower.WORLD_COUNT * Tower.STAGES_PER_WORLD)
		Expect.equal(Tower.WorldOf(0), 0, "lobby")
		Expect.equal(Tower.WorldOf(1), 1)
		Expect.equal(Tower.WorldOf(Tower.STAGES_PER_WORLD), 1, "salle du terminal du monde 1")
		Expect.equal(Tower.WorldOf(Tower.STAGES_PER_WORLD + 1), 2)
		Expect.equal(Tower.WorldOf(Tower.TOTAL_STAGES), Tower.WORLD_COUNT)
		for world = 1, Tower.WORLD_COUNT do
			Expect.equal(Tower.WorldOf(Tower.FirstStage(world)), world)
			Expect.equal(Tower.WorldOf(Tower.TerminalStage(world)), world)
			local def = Tower.Worlds[world]
			Expect.equal(def.Index, world)
			Expect.truthy(table.find(Tower.MinigameKinds, def.Minigame) ~= nil, `mini-jeu du monde {world}`)
			for _, trap in def.Traps do
				Expect.truthy(table.find(Tower.TrapKinds, trap) ~= nil, `piège {trap} du monde {world}`)
			end
			Expect.truthy(#def.Intro > 10, "réplique d'Anga")
		end
		for kind in GameConfig.Minigame.MinSeconds do
			Expect.truthy(table.find(Tower.MinigameKinds, kind) ~= nil, `durée min de {kind}`)
		end
	end,
	["TrapClock : FREEZE fige puis reprend sans saut, LAG avance par à-coups"] = function()
		Shim.Globals = {
			game = {
				GetService = function(_self: any, _name: string): any
					return {}
				end,
			},
		}
		local TrapClock = Shim.load("src/shared/Util/TrapClock.luau")
		Shim.Globals = {}
		local Incidents = Shim.load("src/shared/Config/Incidents.luau")
		local C = TrapClock.Compute
		Expect.equal(C(100, "", 0, 0, 5), 95, "sans incident : heure - décalage")
		-- FREEZE de 110 à 116
		Expect.equal(C(109, "Freeze", 110, 116, 0), 109, "avant le freeze")
		Expect.equal(C(113, "Freeze", 110, 116, 0), 110, "pendant : figé")
		Expect.equal(C(118, "Freeze", 110, 116, 0), 112, "après, avant la mise à jour du décalage")
		Expect.equal(C(118, "", 0, 0, 6), 112, "après la mise à jour : identique (pas de saut)")
		-- LAG de 200 à 207
		local a, b = C(200.1, "Lag", 200, 207, 0), C(200.3, "Lag", 200, 207, 0)
		Expect.equal(a, b, "même pas de temps")
		Expect.near(C(200.5, "Lag", 200, 207, 0), 200 + Incidents.LagStep, 1e-9)
		Expect.equal(C(207.2, "Lag", 200, 207, 0), 207.2, "après le lag : heure normale")
	end,
	["configs cohérentes"] = function()
		local ids = {}
		for _, def in Cosmetics.List do
			Expect.equal(ids[def.Id], nil, `cosmétique unique {def.Id}`)
			ids[def.Id] = true
			Expect.truthy(def.Kind == "Trail" or def.Kind == "DeathFx")
			for _, hex in def.Colors do
				Expect.truthy(string.match(hex, "^%x%x%x%x%x%x$") ~= nil, `couleur {hex}`)
			end
		end
		for _, reward in GameConfig.DailyRewards do
			if reward.Cosmetic then
				Expect.truthy(Cosmetics.ById[reward.Cosmetic] ~= nil, "cosmétique du calendrier")
			end
		end
		Expect.equal(#GameConfig.DailyRewards, 7)
		Expect.truthy(#Missions.Templates >= Missions.PerDay)
		for _, template in Missions.Templates do
			Expect.truthy(string.find(template.Text, "{n}", 1, true) ~= nil, `objectif dans {template.Id}`)
		end
		local seen = {}
		for _, product in Products.Products do
			Expect.equal(seen[product.Key], nil, "clé produit unique")
			seen[product.Key] = true
		end
		for _, pass in Products.Passes do
			Expect.equal(seen[pass.Key], nil, "clé pass unique")
			seen[pass.Key] = true
		end
		Expect.truthy(Products.PassByKey.LowGravity.Toggle and Products.PassByKey.SpeedChip.Toggle)
		for _, world in Tower.Worlds do
			Expect.truthy(
				world.Incident == "Any" or Incidents.ByKind[world.Incident] ~= nil,
				`incident du monde {world.Index}`
			)
			Expect.truthy(#world.Symptom > 0 and #world.Minion > 0 and #world.Cleaned > 0, "scénario du monde")
		end
	end,
}
