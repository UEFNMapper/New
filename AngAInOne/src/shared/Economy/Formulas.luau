--!strict
--[[
	Formulas : toutes les maths de l'économie, sans aucune dépendance Roblox.
	Testé par tests/formulas.spec.luau et tests/pacing.spec.luau (Lune).

	Conventions :
	- "level" = niveau actuel d'un module (0 = non acheté).
	- Le coût d'un achat fait passer de level à level + 1.
]]

local Formulas = {}

export type LoadParams = {
	BaseCapacity: number,
	CapacityGrowth: number,
	BaseCost: number,
	CostGrowth: number,
}

-- Multiplicateur de paliers : x2 à chaque palier atteint.
function Formulas.MilestoneMultiplier(level: number, milestones: { number }): number
	local mult = 1
	for _, milestone in milestones do
		if level >= milestone then
			mult *= 2
		end
	end
	return mult
end

-- Production par seconde d'un module à un niveau donné (avant efficacité et bonus).
function Formulas.ModuleProduction(baseProd: number, level: number, milestones: { number }): number
	if level <= 0 then
		return 0
	end
	return baseProd * level * Formulas.MilestoneMultiplier(level, milestones)
end

-- Coût pour passer de level à level + 1.
function Formulas.UpgradeCost(baseCost: number, level: number, growth: number): number
	return baseCost * growth ^ level
end

-- Coût cumulé de `count` niveaux à partir de `level` (série géométrique).
function Formulas.BulkCost(baseCost: number, level: number, count: number, growth: number): number
	if count <= 0 then
		return 0
	end
	return baseCost * growth ^ level * (growth ^ count - 1) / (growth - 1)
end

-- Nombre maximal de niveaux achetables avec `money`, borné par `cap` niveaux restants.
function Formulas.MaxAffordable(baseCost: number, level: number, money: number, growth: number, cap: number): number
	if money <= 0 or cap <= 0 then
		return 0
	end
	local first = baseCost * growth ^ level
	if money < first then
		return 0
	end
	local count = math.floor(math.log(money * (growth - 1) / first + 1) / math.log(growth))
	-- Corrige les erreurs d'arrondi flottant aux bornes.
	while count > 0 and Formulas.BulkCost(baseCost, level, count, growth) > money do
		count -= 1
	end
	while count + 1 <= cap and Formulas.BulkCost(baseCost, level, count + 1, growth) <= money do
		count += 1
	end
	return math.min(count, cap)
end

-- Capacité (Watts ou refroidissement) pour un niveau d'amélioration.
function Formulas.Capacity(params: LoadParams, level: number): number
	return params.BaseCapacity * params.CapacityGrowth ^ level
end

function Formulas.CapacityUpgradeCost(params: LoadParams, level: number): number
	return params.BaseCost * params.CostGrowth ^ level
end

-- Efficacité = min(1, capacité / demande). Une demande nulle donne 1.
function Formulas.Efficiency(capacity: number, demand: number): number
	if demand <= 0 then
		return 1
	end
	return math.clamp(capacity / demand, 0, 1)
end

-- Firmware gagné en fin de run.
function Formulas.FirmwareGain(runBitsEarned: number, divisor: number): number
	if runBitsEarned <= 0 then
		return 0
	end
	return math.floor(math.sqrt(runBitsEarned / divisor))
end

function Formulas.FirmwareMultiplier(firmware: number, perPoint: number): number
	return 1 + perPoint * math.max(firmware, 0)
end

-- Gains hors ligne.
function Formulas.OfflineEarnings(ratePerSecond: number, elapsed: number, capSeconds: number, ratio: number): number
	if elapsed <= 0 or ratePerSecond <= 0 then
		return 0
	end
	return ratePerSecond * math.min(elapsed, capSeconds) * ratio
end

--[[
	Aiguille de l'Overclock : position dans [0, 1] en fonction du temps écoulé.
	Onde triangulaire déterministe, calculée à l'identique sur le client (affichage)
	et sur le serveur (validation), pour que le serveur garde l'autorité.
]]
function Formulas.NeedlePosition(elapsed: number, period: number): number
	local phase = (elapsed % period) / period
	if phase < 0.5 then
		return phase * 2
	end
	return 2 - phase * 2
end

-- Qualité d'un arrêt d'aiguille : "Perfect", "Good" ou "Miss" (cible = centre de la jauge).
function Formulas.OverclockGrade(position: number, target: number, goodHalf: number, perfectHalf: number): string
	local distance = math.abs(position - target)
	if distance <= perfectHalf then
		return "Perfect"
	elseif distance <= goodHalf then
		return "Good"
	end
	return "Miss"
end

-- Benchmark (score affiché en FLOPS) : somme pondérée des niveaux par zone.
function Formulas.Benchmark(levels: { [string]: number }, zoneOf: { [string]: number }): number
	local score = 0
	for id, level in levels do
		local zone = zoneOf[id]
		if zone then
			score += level * 10 ^ (zone + 1)
		end
	end
	return score
end

-- Tirage pondéré : `roll` dans [0, 1). Renvoie la clé choisie.
function Formulas.WeightedPick(weights: { { key: string, weight: number } }, roll: number): string
	local total = 0
	for _, entry in weights do
		total += entry.weight
	end
	local target = roll * total
	local acc = 0
	for _, entry in weights do
		acc += entry.weight
		if target < acc then
			return entry.key
		end
	end
	return weights[#weights].key
end

-- Jour UTC (entier) pour les systèmes quotidiens.
function Formulas.DayIndex(unixTime: number): number
	return math.floor(unixTime / 86400)
end

-- Semaine (lundi 00:00 UTC). Le 1er janvier 1970 était un jeudi : décalage de 3 jours.
function Formulas.WeekIndex(unixTime: number): number
	return math.floor((unixTime / 86400 + 3) / 7)
end

return table.freeze(Formulas)
