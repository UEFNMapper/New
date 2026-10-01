-- Jauges de PC (Util/Gauges) et enquêtes (Config/Puzzles) : logique pure.
local Gauges = Shim.load("src/shared/Util/Gauges.luau")
local Puzzles = Shim.load("src/shared/Config/Puzzles.luau")

return {
	["RAM : se remplit en ≈ 45 s, ralentit seulement au-delà du seuil, jamais sous le facteur minimal"] = function()
		local ram = 0
		local seconds = 0
		while ram < 100 do
			ram = Gauges.RamStep(ram, 1)
			seconds += 1
		end
		Expect.between(seconds, 40, 50, "temps de remplissage")
		Expect.equal(Gauges.RamSpeedFactor(0), 1)
		Expect.equal(Gauges.RamSpeedFactor(Gauges.RAM_SLOW_FROM), 1)
		Expect.near(Gauges.RamSpeedFactor(100), Gauges.RAM_MIN_FACTOR, 1e-6)
		local mid = Gauges.RamSpeedFactor((Gauges.RAM_SLOW_FROM + 100) / 2)
		Expect.truthy(mid < 1 and mid > Gauges.RAM_MIN_FACTOR, "à mi-chemin")
		Expect.truthy(Gauges.RamSpeedFactor(130) >= Gauges.RAM_MIN_FACTOR, "borné")
	end,

	["RAM : un bouton se réutilise après son cooldown seulement"] = function()
		Expect.equal(Gauges.CanFlush(100, nil), true)
		Expect.equal(Gauges.CanFlush(100, 95), false)
		Expect.equal(Gauges.CanFlush(100 + Gauges.RAM_FLUSH_COOLDOWN, 100), true)
	end,

	["Chaleur : monte en courant, redescend à l'arrêt, plus vite près d'un ventilateur, bornée"] = function()
		local heat = Gauges.HEAT_IDLE
		local seconds = 0
		while heat < Gauges.HEAT_MAX do
			heat = Gauges.HeatStep(heat, 1, true, false)
			seconds += 1
		end
		Expect.between(seconds, 18, 30, "course continue avant le plantage")
		Expect.equal(Gauges.HeatState(heat), "Crash")
		local rest = Gauges.HeatStep(Gauges.HEAT_MAX, 1, false, false)
		local cool = Gauges.HeatStep(Gauges.HEAT_MAX, 1, false, true)
		Expect.truthy(cool < rest and rest < Gauges.HEAT_MAX, "refroidissement")
		Expect.equal(
			Gauges.HeatStep(Gauges.HEAT_IDLE, 10, false, true),
			Gauges.HEAT_IDLE,
			"jamais sous la température de repos"
		)
		Expect.equal(Gauges.HeatState(Gauges.HEAT_IDLE), "Ok")
		Expect.equal(Gauges.HeatState(Gauges.HEAT_WARN), "Warn")
		Expect.equal(Gauges.HeatState(70), "Hot")
		-- courir / s'arrêter : on tient si l'on s'arrête un peu
		local h = Gauges.HEAT_IDLE
		for _ = 1, 60 do
			h = Gauges.HeatStep(h, 1, true, false)
			h = Gauges.HeatStep(h, 0.4, false, false)
		end
		Expect.truthy(h < Gauges.HEAT_MAX, "avec des pauses, pas de plantage")
	end,

	["Enquêtes : une par monde 1 et 7, un seul coupable, indices sur les autres, mondes sans enquête"] = function()
		Expect.equal(#Puzzles.List, 2)
		for _, puzzle in Puzzles.List do
			local culprits = 0
			local ids = {}
			for _, item in puzzle.Items do
				Expect.truthy(not ids[item.Id], `id en double : {item.Id}`)
				ids[item.Id] = true
				Expect.equal(#item.Lines, 2, `{item.Name} : deux lignes`)
				if item.Culprit then
					culprits += 1
				else
					Expect.truthy(item.Hint and #item.Hint > 10, `{item.Name} : indice`)
				end
			end
			Expect.equal(culprits, 1, `monde {puzzle.World} : un coupable`)
			Expect.truthy(puzzle.Bits > 0 and #puzzle.Intro > 10 and #puzzle.Success > 10, "textes")
			Expect.truthy(#puzzle.Items >= 5 and #puzzle.Items <= 6, "5 ou 6 panneaux (un mur de salle)")
		end
		Expect.equal(Puzzles.ForWorld(3), nil)
		local ok, item = Puzzles.Check(1, "virus")
		Expect.equal(ok, true)
		Expect.equal(item and item.Name, "RAM_download_2go.exe")
		local wrong, wrongItem = Puzzles.Check(7, "browser")
		Expect.equal(wrong, false)
		Expect.truthy(wrongItem and wrongItem.Hint, "indice sur le mauvais panneau")
		Expect.equal(Puzzles.Check(7, "inconnu"), false)
	end,
}
