--!strict
--[[
	Production : calcule l'instantané de production d'un PC (Bits/s, Watts, chaleur).
	Pur (aucune API Roblox) : utilisé par le serveur (autorité), par le client
	(prévisualisation dans l'UI) et par les tests de pacing.
]]

local Formulas = require(script.Parent.Formulas)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Modules = require(script.Parent.Parent.Config.Modules)

local Production = {}

export type Input = {
	Levels: { [string]: number },
	Zone: number,
	PsuLevel: number,
	CoolingLevel: number,
	Multiplier: number, -- tous les bonus de Bits combinés (pass, firmware, nanobots…)
	HeatMultiplier: number, -- overclock : > 1
	WattsReduction: number, -- nanobots : 0..0.9
	HeatReduction: number, -- nanobots : 0..0.9
}

export type Snapshot = {
	RawRate: number, -- Bits/s avant efficacité et bonus
	Rate: number, -- Bits/s final
	PowerDemand: number,
	PowerCapacity: number,
	PowerEfficiency: number,
	HeatDemand: number,
	HeatCapacity: number,
	ThermalEfficiency: number,
	Multiplier: number,
}

function Production.Compute(input: Input): Snapshot
	local raw = 0
	local watts = 0
	local heat = 0
	for _, def in Modules.List do
		local level = input.Levels[def.Id] or 0
		if level > 0 and def.Zone <= input.Zone then
			raw += Formulas.ModuleProduction(def.BaseProd, level, GameConfig.Milestones)
			watts += def.WattsPerLevel * level
			if def.Zone >= GameConfig.Cooling.HeatStartsAtZone then
				heat += def.HeatPerLevel * level
			end
		end
	end

	watts *= 1 - math.clamp(input.WattsReduction, 0, 0.9)
	heat *= (1 - math.clamp(input.HeatReduction, 0, 0.9)) * math.max(input.HeatMultiplier, 1)

	local powerCap = Formulas.Capacity(GameConfig.Power, input.PsuLevel)
	local heatCap = Formulas.Capacity(GameConfig.Cooling, input.CoolingLevel)
	local powerEff = Formulas.Efficiency(powerCap, watts)
	local thermalEff = Formulas.Efficiency(heatCap, heat)

	return {
		RawRate = raw,
		Rate = raw * powerEff * thermalEff * input.Multiplier,
		PowerDemand = watts,
		PowerCapacity = powerCap,
		PowerEfficiency = powerEff,
		HeatDemand = heat,
		HeatCapacity = heatCap,
		ThermalEfficiency = thermalEff,
		Multiplier = input.Multiplier,
	}
end

return table.freeze(Production)
