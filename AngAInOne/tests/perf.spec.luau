-- Test de perf de fin d'ascension (Util/PerfTest) : scores par axe, score global, emblème.
local PerfTest = Shim.load("src/shared/Util/PerfTest.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")

return {
	["vitesse : 100 jusqu'au temps tout en or, 60 au temps tout en argent, plancher 20"] = function()
		local gold, silver = PerfTest.GoldTotal()
		Expect.truthy(gold > 0 and silver > gold, "seuils cumulés")
		Expect.equal(PerfTest.SpeedScore(gold), 100)
		Expect.equal(PerfTest.SpeedScore(gold / 2), 100)
		Expect.equal(PerfTest.SpeedScore(silver), 60)
		Expect.between(PerfTest.SpeedScore((gold + silver) / 2), 75, 85, "à mi-chemin")
		Expect.equal(PerfTest.SpeedScore(silver * 10), 20)
		Expect.equal(PerfTest.SpeedScore(nil), 0)
	end,

	["fluidité : 6 points par chute, plancher 20"] = function()
		Expect.equal(PerfTest.SmoothnessScore(0), 100)
		Expect.equal(PerfTest.SmoothnessScore(5), 70)
		Expect.equal(PerfTest.SmoothnessScore(40), 20)
	end,

	["ascension parfaite : 100 partout, emblème Titan"] = function()
		local gold = PerfTest.GoldTotal()
		local result = PerfTest.Build({
			Time = gold,
			Deaths = 0,
			Coins = 170,
			CoinsTotal = 170,
			Keys = Tower.WORLD_COUNT * Tower.USB_KEYS_PER_WORLD,
			KeysTotal = Tower.WORLD_COUNT * Tower.USB_KEYS_PER_WORLD,
		})
		Expect.equal(result.Score, 100)
		Expect.equal(result.Emblem, "Titan")
		Expect.equal(#result.Axes, 4)
		for _, axis in result.Axes do
			Expect.equal(axis.Score, 100, axis.Label)
		end
		Expect.truthy(string.find(result.Axes[4].Detail, "21/21", 1, true), "détail clés")
	end,

	["ascension moyenne : scores bornés, emblème intermédiaire avec son indice"] = function()
		local _, silver = PerfTest.GoldTotal()
		local result =
			PerfTest.Build({ Time = silver, Deaths = 10, Coins = 80, CoinsTotal = 170, Keys = 7, KeysTotal = 21 })
		Expect.equal(result.Axes[1].Score, 60)
		Expect.equal(result.Axes[2].Score, 40)
		Expect.equal(result.Axes[3].Score, 47)
		Expect.equal(result.Axes[4].Score, 33)
		Expect.equal(result.Score, 45)
		Expect.equal(result.Emblem, "Rodage")
		Expect.truthy(string.find(result.EmblemHint, "Solide", 1, true), "indice vers l'emblème suivant")
	end,

	["entrées inconnues : pas d'erreur, scores neutres"] = function()
		local result = PerfTest.Build({})
		Expect.equal(result.Axes[1].Score, 0)
		Expect.equal(result.Axes[2].Score, 70)
		Expect.equal(result.Axes[3].Score, 0)
		Expect.equal(result.Axes[4].Score, 0)
		Expect.truthy(result.Emblem ~= "", "emblème")
	end,
}
