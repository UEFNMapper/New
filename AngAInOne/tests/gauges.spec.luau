-- Jauges de PC (Util/Gauges) : logique pure.
local Gauges = Shim.load("src/shared/Util/Gauges.luau")

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
}
