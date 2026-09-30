--[[
	PacingSim : rejoue une partie avec un joueur "glouton" en utilisant la VRAIE
	config du jeu (Modules, Zones, GameConfig) et le VRAI calcul de production.
	Le joueur achète toujours l'option au meilleur ratio gain/coût (modules,
	bloc d'alimentation, radiateurs), débloque les zones dès que possible et fait
	un Reboot une heure après son dernier déblocage.
]]
return function(Shim: any)
	local Formulas = Shim.load("src/shared/Economy/Formulas.luau")
	local Production = Shim.load("src/shared/Economy/Production.luau")
	local GameConfig = Shim.load("src/shared/Config/GameConfig.luau")
	local Modules = Shim.load("src/shared/Config/Modules.luau")
	local Zones = Shim.load("src/shared/Config/Zones.luau")

	local Sim = {}

	function Sim.run(multiplier: number, horizon: number, stopAt: number?)
		local state = { Levels = {} :: { [string]: number }, Zone = 1, PsuLevel = 0, CoolingLevel = 0 }
		state.Levels["Z1M1"] = 1
		local money, earned, t = 0, 0, 0
		local unlocked: { [string]: number } = {}
		local spentCapacity, spentTotal = 0, 0
		local step = 10
		local function snapshot(s)
			return Production.Compute({
				Levels = s.Levels,
				Zone = s.Zone,
				PsuLevel = s.PsuLevel,
				CoolingLevel = s.CoolingLevel,
				Multiplier = multiplier,
				HeatMultiplier = 1,
				WattsReduction = 0,
				HeatReduction = 0,
			})
		end
		local current = snapshot(state)
		while t < horizon do
			money += current.Rate * step
			earned += current.Rate * step
			t += step
			if state.Zone == #Zones and money >= GameConfig.SingularityCost then
				unlocked.Singularity = t
				break
			end
			if stopAt and t >= stopAt then
				break
			end
			local nextZone = Zones[state.Zone + 1]
			if nextZone and money >= nextZone.UnlockCost then
				money -= nextZone.UnlockCost
				state.Zone += 1
				state.Levels[`Z{state.Zone}M1`] = math.max(state.Levels[`Z{state.Zone}M1`] or 0, 1)
				unlocked[nextZone.Id] = t
				current = snapshot(state)
				continue
			end
			-- Achats gloutons (ROI < 15 min, 60 min en fin de partie).
			local limit = if state.Zone < #Zones then 900 else 3600
			while true do
				local bestScore, bestApply, bestCost, bestIsCap = 0, nil :: any, 0, false
				local function consider(cost: number, mutate: (any) -> (), isCap: boolean)
					if cost > money then
						return
					end
					local trial = table.clone(state)
					trial.Levels = table.clone(state.Levels)
					mutate(trial)
					local gain = snapshot(trial).Rate - current.Rate
					if gain > 0 and cost / gain < limit and gain / cost > bestScore then
						bestScore, bestApply, bestCost, bestIsCap = gain / cost, mutate, cost, isCap
					end
				end
				for _, def in Modules.List do
					if def.Zone <= state.Zone then
						local level = state.Levels[def.Id] or 0
						if level < GameConfig.MaxModuleLevel then
							consider(Formulas.UpgradeCost(def.BaseCost, level, GameConfig.LevelGrowth), function(s)
								s.Levels[def.Id] = (s.Levels[def.Id] or 0) + 1
							end, false)
						end
					end
				end
				consider(Formulas.CapacityUpgradeCost(GameConfig.Power, state.PsuLevel), function(s)
					s.PsuLevel += 1
				end, true)
				if state.Zone >= GameConfig.Cooling.UnlockZone then
					consider(Formulas.CapacityUpgradeCost(GameConfig.Cooling, state.CoolingLevel), function(s)
						s.CoolingLevel += 1
					end, true)
				end
				if not bestApply then
					break
				end
				money -= bestCost
				spentTotal += bestCost
				if bestIsCap then
					spentCapacity += bestCost
				end
				bestApply(state)
				current = snapshot(state)
			end
		end
		return {
			Unlocked = unlocked,
			Time = t,
			Earned = earned,
			CapacityShare = if spentTotal > 0 then spentCapacity / spentTotal else 0,
			PowerEff = current.PowerEfficiency,
			ThermalEff = current.ThermalEfficiency,
		}
	end

	-- Parcours complet avec Reboots jusqu'à la Singularité.
	function Sim.campaign(maxGenerations: number)
		local firmware, total = 0, 0
		local generations = {}
		for gen = 1, maxGenerations do
			local mult = Formulas.FirmwareMultiplier(firmware, GameConfig.Reboot.FirmwarePerPoint)
			-- Un joueur réel refait un Reboot si la Singularité n'est pas à portée en 3 h.
			local full = Sim.run(mult, 3 * 3600)
			if full.Unlocked.Singularity then
				table.insert(generations, { Gen = gen, Result = full, Final = true })
				return { Generations = generations, TotalHours = (total + full.Unlocked.Singularity) / 3600 }
			end
			-- Le Reboot n'est autorisé qu'une fois le GPU débloqué (GameConfig.Reboot.RequiredZone).
			local long = Sim.run(mult, 12 * 3600)
			local gpuTime = long.Unlocked[Zones[GameConfig.Reboot.RequiredZone].Id]
			if not gpuTime then
				return { Generations = generations, TotalHours = math.huge }
			end
			-- Reboot 1 h après le GPU, ou 30 min après l'AI Core s'il arrive vite.
			local stopAt = gpuTime + 3600
			local aiTime = long.Unlocked[Zones[#Zones].Id]
			if aiTime and aiTime < gpuTime + 2 * 3600 then
				stopAt = aiTime + 1800
			end
			local run = Sim.run(mult, 12 * 3600, stopAt)
			total += run.Time
			firmware += Formulas.FirmwareGain(run.Earned, GameConfig.Reboot.FirmwareDivisor)
			table.insert(generations, { Gen = gen, Result = run, Final = false, Firmware = firmware })
		end
		return { Generations = generations, TotalHours = math.huge }
	end

	return Sim
end
