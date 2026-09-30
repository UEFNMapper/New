-- Médailles par monde : règles (Config/Medals), chrono d'un monde, meilleur résultat
-- (Util/MedalLogic) et schéma de données (WorldBest, RunSplit, migration v1 -> v2).
local Medals = Shim.load("src/shared/Config/Medals.luau")
local MedalLogic = Shim.load("src/shared/Util/MedalLogic.luau")
local DataSchema = Shim.load("src/shared/Data/DataSchema.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")

return {
	["config : un seuil or < argent par monde, généreux pour les enfants"] = function()
		Expect.equal(#Medals.Worlds, Tower.WORLD_COUNT, "une règle par monde")
		for world = 1, Tower.WORLD_COUNT do
			local rule = Medals.Rule(world)
			Expect.truthy(rule.Gold < rule.Silver, `monde {world} : or plus exigeant que l'argent`)
			-- Au moins ~1 min 30 pour l'or : la course pure dure ~40 s, plus pièges et mini-jeu.
			Expect.truthy(rule.Gold >= 90, `monde {world} : or pas trop dur`)
			Expect.truthy(rule.Silver >= rule.Gold * 1.4, `monde {world} : écart or / argent`)
		end
		Expect.truthy(Medals.Rule(Tower.WORLD_COUNT).Gold > Medals.Rule(1).Gold, "le boss rallonge le monde 7")
		Expect.truthy(Medals.GoldMaxDeaths >= 2 and Medals.SilverMaxDeaths > Medals.GoldMaxDeaths)
		for _, medal in Medals.Order do
			Expect.truthy(Medals.Names[medal] ~= nil and #Medals.Colors[medal] == 3, `couleurs de {medal}`)
		end
	end,
	["règles : temps et morts"] = function()
		local rule = Medals.Rule(1)
		Expect.equal(MedalLogic.Evaluate(1, rule.Gold, 0), "Gold", "pile sur le seuil = or")
		Expect.equal(MedalLogic.Evaluate(1, rule.Gold - 10, Medals.GoldMaxDeaths), "Gold")
		Expect.equal(MedalLogic.Evaluate(1, rule.Gold - 10, Medals.GoldMaxDeaths + 1), "Silver", "trop de morts")
		Expect.equal(MedalLogic.Evaluate(1, rule.Gold + 0.1, 0), "Silver")
		Expect.equal(MedalLogic.Evaluate(1, rule.Silver, Medals.SilverMaxDeaths), "Silver")
		Expect.equal(MedalLogic.Evaluate(1, rule.Silver, Medals.SilverMaxDeaths + 1), "Bronze")
		Expect.equal(MedalLogic.Evaluate(1, rule.Silver + 1, 0), "Bronze", "nettoyé = au moins bronze")
		Expect.equal(MedalLogic.Evaluate(1, 99999, 50), "Bronze")
		Expect.equal(MedalLogic.Evaluate(1, nil, 0), "Bronze", "temps inconnu = bronze")
		-- Le monde 7 (boss) accepte un temps qui serait du bronze au monde 1.
		Expect.equal(MedalLogic.Evaluate(7, rule.Silver + 1, 0), "Gold")
	end,
	["prochain objectif"] = function()
		local rule = Medals.Rule(3)
		local goal = MedalLogic.NextGoal(3, "Bronze")
		Expect.equal(goal and goal.Medal, "Silver")
		Expect.equal(goal and goal.Time, rule.Silver)
		goal = MedalLogic.NextGoal(3, "Silver")
		Expect.equal(goal and goal.Medal, "Gold")
		Expect.equal(goal and goal.Deaths, Medals.GoldMaxDeaths)
		Expect.equal(MedalLogic.NextGoal(3, "Gold"), nil, "déjà l'or")
		Expect.equal(MedalLogic.Rank("Gold") > MedalLogic.Rank("Silver"), true)
		Expect.equal(MedalLogic.Rank(""), 0)
		Expect.equal(MedalLogic.Rank(nil), 0)
	end,
	["chrono d'un monde (split)"] = function()
		local split = DataSchema.Template().RunSplit
		Expect.equal(split.World, 0, "aucun monde chronométré au départ")
		Expect.equal(MedalLogic.SplitTime(split, 1, 30), nil)
		MedalLogic.StartSplit(split, 2, 120.5, false)
		split.Deaths = 4
		Expect.equal(MedalLogic.SplitTime(split, 2, 200.5), 80)
		Expect.equal(MedalLogic.SplitTime(split, 3, 200.5), nil, "autre monde : temps inconnu")
		Expect.equal(MedalLogic.SplitTime(split, 2, 100), nil, "chrono incohérent")
		MedalLogic.StartSplit(split, 3, 200.5, true)
		Expect.equal(split.Deaths, 0, "morts remises à zéro")
		Expect.equal(split.Keys, 0)
		Expect.equal(split.Assisted, true)
	end,
	["meilleur résultat : record sans aide, médaille toujours gardée"] = function()
		-- Premier passage : médaille + temps.
		local best, newBest, medalUp = MedalLogic.UpdateBest(nil, "Silver", 140, true)
		Expect.equal(best.Medal, "Silver")
		Expect.equal(best.Time, 140)
		Expect.equal(newBest, true)
		Expect.equal(medalUp, true)
		-- Plus lent, médaille moins bonne : rien ne change.
		best, newBest, medalUp = MedalLogic.UpdateBest(best, "Bronze", 200, true)
		Expect.equal(best.Medal, "Silver")
		Expect.equal(best.Time, 140)
		Expect.equal(newBest, false)
		Expect.equal(medalUp, false)
		-- Assisté et plus rapide : la médaille monte, pas le record.
		best, newBest, medalUp = MedalLogic.UpdateBest(best, "Gold", 80, false)
		Expect.equal(best.Medal, "Gold")
		Expect.equal(best.Time, 140, "temps assisté jamais enregistré")
		Expect.equal(newBest, false)
		Expect.equal(medalUp, true)
		-- Sans aide et plus rapide : nouveau record.
		best, newBest, medalUp = MedalLogic.UpdateBest(best, "Gold", 95, true)
		Expect.equal(best.Time, 95)
		Expect.equal(newBest, true)
		Expect.equal(medalUp, false)
		-- Temps inconnu : ni record, ni perte.
		best, newBest = MedalLogic.UpdateBest(best, "Bronze", nil, true)
		Expect.equal(best.Time, 95)
		Expect.equal(best.Medal, "Gold")
		Expect.equal(newBest, false)
		-- Première fois en assisté : médaille, mais aucun temps (0).
		local assisted = MedalLogic.UpdateBest(nil, "Gold", 60, false)
		Expect.equal(assisted.Medal, "Gold")
		Expect.equal(assisted.Time, 0)
	end,
	["clés USB d'un monde"] = function()
		Expect.equal(MedalLogic.KeyWorld("W3K2"), 3)
		Expect.equal(MedalLogic.KeyWorld("W12K1"), 12)
		Expect.equal(MedalLogic.KeyWorld("S3C1"), 0)
		local owned = { W2K1 = true, W2K3 = true, W3K1 = true }
		Expect.equal(MedalLogic.KeysInWorld(owned, 2, Tower.USB_KEYS_PER_WORLD), 2)
		Expect.equal(MedalLogic.KeysInWorld(owned, 1, Tower.USB_KEYS_PER_WORLD), 0)
		Expect.equal(MedalLogic.Key(4), "W4")
	end,
	["schéma : valeurs par défaut et migration v1 -> v2"] = function()
		Expect.truthy(DataSchema.CURRENT_VERSION >= 2, "version du schéma augmentée")
		local fresh = DataSchema.Template()
		Expect.equal(next(fresh.WorldBest), nil, "aucune médaille au départ")
		Expect.equal(fresh.RunSplit.World, 0)
		Expect.equal(fresh.RunSplit.Assisted, false)
		-- Sauvegarde v1 (avant les médailles) : les champs sont ajoutés, le reste est gardé.
		local v1: any = { Version = 1, Bits = 7, Stage = 13, Cleared = 2, RunElapsed = 321, RunStarted = true }
		Expect.truthy(DataSchema.Migrate(v1))
		Expect.equal(v1.Version, DataSchema.CURRENT_VERSION)
		Expect.equal(type(v1.WorldBest), "table")
		Expect.equal(v1.RunSplit.World, 0, "chrono inconnu : la reprise donne le bronze sans record")
		Expect.equal(v1.RunSplit.Deaths, 0)
		Expect.equal(v1.Stage, 13)
		-- Données abîmées : remplacées par les valeurs par défaut.
		local broken: any = { Version = 1, WorldBest = 5, RunSplit = "x" }
		Expect.truthy(DataSchema.Migrate(broken))
		Expect.equal(type(broken.WorldBest), "table")
		Expect.equal(broken.RunSplit.Keys, 0)
		-- Champs partiels : complétés sans écraser.
		local partial: any =
			{ Version = 2, WorldBest = { W1 = { Time = 88, Medal = "Gold" } }, RunSplit = { World = 3 } }
		Expect.truthy(DataSchema.Migrate(partial))
		Expect.equal(partial.WorldBest.W1.Time, 88)
		Expect.equal(partial.RunSplit.World, 3)
		Expect.equal(partial.RunSplit.Start, 0)
		-- Deux modèles ne partagent pas la même table (pas d'effet de bord entre joueurs).
		local a, b = DataSchema.Template(), DataSchema.Template()
		a.RunSplit.Deaths = 9
		Expect.equal(b.RunSplit.Deaths, 0)
	end,
	["une ascension type : or, puis argent avec des morts, puis record battu"] = function()
		local data: any = DataSchema.Template()
		local rule = Medals.Rule(1)
		-- Départ à 0 s, terminal du monde 1 à rule.Gold - 5 s, une mort.
		MedalLogic.StartSplit(data.RunSplit, 1, 0, false)
		data.RunSplit.Deaths += 1
		local time = MedalLogic.SplitTime(data.RunSplit, 1, rule.Gold - 5)
		local medal = MedalLogic.Evaluate(1, time, data.RunSplit.Deaths)
		Expect.equal(medal, "Gold")
		local best, newBest = MedalLogic.UpdateBest(data.WorldBest.W1, medal, time, not data.RunSplit.Assisted)
		data.WorldBest.W1 = best
		Expect.equal(newBest, true)
		-- Deuxième ascension : plus rapide mais trop de morts -> argent, record quand même battu.
		MedalLogic.StartSplit(data.RunSplit, 1, 0, false)
		data.RunSplit.Deaths = Medals.GoldMaxDeaths + 1
		time = MedalLogic.SplitTime(data.RunSplit, 1, rule.Gold - 20)
		medal = MedalLogic.Evaluate(1, time, data.RunSplit.Deaths)
		Expect.equal(medal, "Silver")
		best, newBest = MedalLogic.UpdateBest(data.WorldBest.W1, medal, time, true)
		Expect.equal(best.Medal, "Gold", "la meilleure médaille reste l'or")
		Expect.equal(best.Time, rule.Gold - 20)
		Expect.equal(newBest, true)
	end,
	["aide payante activée pendant l'ascension : ascension ET monde marqués aussitôt"] = function()
		local data: any = DataSchema.Template()
		-- Hors ascension (lobby avant le départ) : rien n'est marqué.
		Expect.equal(MedalLogic.MarkAssisted(data), false)
		Expect.equal(data.RunAssisted, false)
		Expect.equal(data.RunSplit.Assisted, false)
		-- Ascension en cours : activer puis couper tout de suite ne passe plus inaperçu.
		data.RunStarted = true
		MedalLogic.StartSplit(data.RunSplit, 2, 100, false)
		Expect.equal(MedalLogic.MarkAssisted(data), true)
		Expect.equal(data.RunAssisted, true, "hors classement des temps")
		Expect.equal(data.RunSplit.Assisted, true, "monde en cours assisté")
		local rule = Medals.Rule(2)
		local time = MedalLogic.SplitTime(data.RunSplit, 2, 100 + rule.Gold - 30)
		Expect.equal(MedalLogic.Evaluate(2, time, 0, 3, data.RunSplit.Assisted), "Silver", "pas d'or")
		local best, newBest = MedalLogic.UpdateBest(nil, "Silver", time, not data.RunSplit.Assisted)
		Expect.equal(newBest, false, "pas de record du monde")
		Expect.equal(best.Time, 0)
		-- Le monde suivant repart sans aide (si l'aide est coupée).
		MedalLogic.StartSplit(data.RunSplit, 3, 400, false)
		Expect.equal(data.RunSplit.Assisted, false)
	end,
	["chute dans le vide vue par le serveur : comptée une fois par chute, après le délai"] = function()
		local watch: any = { Since = nil, Counted = false }
		Expect.equal(MedalLogic.WatchFall(watch, false, 0, 0.5), false)
		Expect.equal(MedalLogic.WatchFall(watch, true, 1, 0.5), false, "entrée dans le vide")
		Expect.equal(MedalLogic.WatchFall(watch, true, 1.25, 0.5), false, "trop tôt")
		Expect.equal(MedalLogic.WatchFall(watch, true, 1.5, 0.5), true, "0,5 s dans le vide : une mort")
		Expect.equal(MedalLogic.WatchFall(watch, true, 1.75, 0.5), false, "pas deux fois pour la même chute")
		Expect.equal(MedalLogic.WatchFall(watch, true, 5, 0.5), false)
		-- Sorti du vide (ramené au checkpoint) : la chute suivante compte de nouveau.
		Expect.equal(MedalLogic.WatchFall(watch, false, 5.25, 0.5), false)
		Expect.equal(watch.Since, nil)
		Expect.equal(MedalLogic.WatchFall(watch, true, 6, 0.5), false)
		Expect.equal(MedalLogic.WatchFall(watch, true, 6.5, 0.5), true)
		-- Un passage bref (saut au ras du vide) ne compte pas.
		local brief: any = { Since = nil, Counted = false }
		MedalLogic.WatchFall(brief, true, 0, 0.5)
		MedalLogic.WatchFall(brief, false, 0.25, 0.5)
		Expect.equal(MedalLogic.WatchFall(brief, true, 0.5, 0.5), false)
	end,
	["médailles : une aide payante plafonne à l'argent (l'or ne s'achète pas)"] = function()
		local MedalLogicT = Shim.load("src/shared/Util/MedalLogic.luau")
		Expect.equal(MedalLogicT.Evaluate(1, 10, 0, 0, false), "Gold")
		Expect.equal(MedalLogicT.Evaluate(1, 10, 0, 0, true), "Silver")
	end,
}
