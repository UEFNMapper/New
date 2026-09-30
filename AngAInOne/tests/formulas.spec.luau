-- Tests unitaires des formules économiques (src/shared/Economy/Formulas.luau).
local Formulas = Shim.load("src/shared/Economy/Formulas.luau")
local GameConfig = Shim.load("src/shared/Config/GameConfig.luau")

return {
	["paliers de production x2"] = function()
		local m = GameConfig.Milestones
		Expect.equal(Formulas.MilestoneMultiplier(9, m), 1)
		Expect.equal(Formulas.MilestoneMultiplier(10, m), 2)
		Expect.equal(Formulas.MilestoneMultiplier(25, m), 4)
		Expect.equal(Formulas.ModuleProduction(0.9, 0, m), 0)
		Expect.near(Formulas.ModuleProduction(0.9, 10, m), 18, 1e-9)
	end,
	["coût en masse = somme des coûts unitaires"] = function()
		local g = GameConfig.LevelGrowth
		local sum = 0
		for level = 7, 7 + 14 do
			sum += Formulas.UpgradeCost(10, level, g)
		end
		Expect.near(Formulas.BulkCost(10, 7, 15, g), sum, sum * 1e-9)
		Expect.equal(Formulas.BulkCost(10, 7, 0, g), 0)
	end,
	["MaxAffordable exact aux bornes"] = function()
		local g = GameConfig.LevelGrowth
		for _, level in { 0, 5, 40, 120 } do
			for count = 1, 30 do
				local exact = Formulas.BulkCost(10, level, count, g)
				Expect.equal(Formulas.MaxAffordable(10, level, exact, g, 999), count, `level {level} count {count}`)
				Expect.equal(Formulas.MaxAffordable(10, level, exact * 0.999999, g, 999), count - 1)
			end
		end
		Expect.equal(Formulas.MaxAffordable(10, 0, 1e30, g, 5), 5, "plafond respecté")
		Expect.equal(Formulas.MaxAffordable(10, 0, 5, g, 5), 0)
	end,
	["efficacité énergie/chaleur"] = function()
		Expect.equal(Formulas.Efficiency(100, 0), 1)
		Expect.equal(Formulas.Efficiency(100, 50), 1)
		Expect.near(Formulas.Efficiency(100, 200), 0.5, 1e-9)
	end,
	["firmware et hors ligne"] = function()
		Expect.equal(Formulas.FirmwareGain(3.8e13, 1e11), 19)
		Expect.equal(Formulas.FirmwareGain(0, 1e11), 0)
		Expect.near(Formulas.FirmwareMultiplier(20, 0.05), 2, 1e-9)
		Expect.equal(Formulas.OfflineEarnings(10, 10000, 7200, 0.5), 36000)
		Expect.equal(Formulas.OfflineEarnings(10, -5, 7200, 0.5), 0)
	end,
	["aiguille d'overclock : onde triangulaire"] = function()
		Expect.near(Formulas.NeedlePosition(0, 2), 0, 1e-9)
		Expect.near(Formulas.NeedlePosition(0.5, 2), 0.5, 1e-9)
		Expect.near(Formulas.NeedlePosition(1, 2), 1, 1e-9)
		Expect.near(Formulas.NeedlePosition(1.5, 2), 0.5, 1e-9)
		Expect.near(Formulas.NeedlePosition(2, 2), 0, 1e-9)
		Expect.equal(Formulas.OverclockGrade(0.52, 0.5, 0.14, 0.05), "Perfect")
		Expect.equal(Formulas.OverclockGrade(0.6, 0.5, 0.14, 0.05), "Good")
		Expect.equal(Formulas.OverclockGrade(0.9, 0.5, 0.14, 0.05), "Miss")
	end,
	["tirage pondéré"] = function()
		local w = { { key = "A", weight = 60 }, { key = "B", weight = 40 } }
		Expect.equal(Formulas.WeightedPick(w, 0), "A")
		Expect.equal(Formulas.WeightedPick(w, 0.599), "A")
		Expect.equal(Formulas.WeightedPick(w, 0.6), "B")
		Expect.equal(Formulas.WeightedPick(w, 0.99999), "B")
	end,
	["jours et semaines UTC"] = function()
		Expect.equal(Formulas.DayIndex(86399), 0)
		Expect.equal(Formulas.DayIndex(86400), 1)
		-- Lundi 5 janvier 1970 00:00 UTC = début de la semaine 1.
		Expect.equal(Formulas.WeekIndex(4 * 86400 - 1), 0)
		Expect.equal(Formulas.WeekIndex(4 * 86400), 1)
	end,
}
