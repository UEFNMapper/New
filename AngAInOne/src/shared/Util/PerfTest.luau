--!strict
--[[
	PerfTest : le « Test de perf » de fin d'ascension, calqué sur celui de la vraie app AngAInOne
	(hexagone de scores : Processeur, Carte graphique, Mémoire, Stockage ; score global ; emblème).
	Logique PURE (testée dans tests/perf.spec.luau) ; l'écran est dans UI/Screens/Moments.luau.

	- Processeur     = vitesse : temps total contre la somme des seuils Or / Argent des médailles ;
	- Carte graphique = fluidité : chutes pendant l'ascension (0 chute = 100) ;
	- Mémoire        = Bits ramassés pendant l'ascension, sur le total disponible ;
	- Stockage       = clés USB dorées trouvées, sur les 21.
	Le score global est la moyenne ; l'emblème en découle.
]]

local Medals = require(script.Parent.Parent.Config.Medals)
local Tower = require(script.Parent.Parent.Config.Tower)

local PerfTest = {}

export type Input = {
	Time: number?, -- secondes d'ascension
	Deaths: number?, -- chutes pendant l'ascension
	Coins: number?, -- Bits ramassés pendant l'ascension
	CoinsTotal: number?, -- Bits disponibles dans la tour
	Keys: number?, -- clés USB trouvées (pour toujours)
	KeysTotal: number?,
}

export type Axis = { Key: string, Label: string, Score: number, Detail: string }

export type Result = {
	Axes: { Axis }, -- dans l'ordre d'affichage : Processeur, Carte graphique, Mémoire, Stockage
	Score: number, -- 0..100
	Emblem: string, -- nom de l'emblème
	EmblemHint: string, -- ce qu'il faut pour le suivant (ou le bravo)
}

-- Emblèmes, du plus haut au plus bas : seuil de score global.
PerfTest.Emblems = table.freeze({
	{ Name = "Titan", Min = 90 },
	{ Name = "Élite", Min = 75 },
	{ Name = "Solide", Min = 55 },
	{ Name = "Rodage", Min = 0 },
})

local function clamp100(value: number): number
	return math.clamp(math.floor(value + 0.5), 0, 100)
end

-- Somme des seuils Or et Argent de tous les mondes (secondes).
function PerfTest.GoldTotal(): (number, number)
	local gold, silver = 0, 0
	for w = 1, Tower.WORLD_COUNT do
		local rule = Medals.Rule(w)
		gold += rule.Gold
		silver += rule.Silver
	end
	return gold, silver
end

-- Vitesse : 100 jusqu'au temps « tout en or », 60 au temps « tout en argent », 20 au double, jamais moins.
function PerfTest.SpeedScore(time: number?): number
	if not time or time <= 0 then
		return 0
	end
	local gold, silver = PerfTest.GoldTotal()
	if time <= gold then
		return 100
	elseif time <= silver then
		return clamp100(100 - 40 * (time - gold) / math.max(silver - gold, 1))
	end
	return clamp100(math.max(20, 60 - 40 * (time - silver) / math.max(silver, 1)))
end

-- Fluidité : chaque chute coûte 6 points, plancher 20 (le PC « tourne » toujours).
function PerfTest.SmoothnessScore(deaths: number?): number
	if deaths == nil then
		return 70
	end
	return clamp100(math.max(20, 100 - 6 * deaths))
end

local function ratioScore(count: number?, total: number?): number
	if not count or not total or total <= 0 then
		return 0
	end
	return clamp100(100 * count / total)
end

function PerfTest.Emblem(score: number): (string, string)
	for index, emblem in PerfTest.Emblems do
		if score >= emblem.Min then
			local above = PerfTest.Emblems[index - 1]
			local hint = if above
				then `Encore {above.Min - score} points pour l'emblème {above.Name}.`
				else "Le meilleur emblème : ton PC est entre de bonnes mains."
			return emblem.Name, hint
		end
	end
	return "Rodage", ""
end

function PerfTest.Build(input: Input): Result
	local speed = PerfTest.SpeedScore(input.Time)
	local smooth = PerfTest.SmoothnessScore(input.Deaths)
	local memory = ratioScore(input.Coins, input.CoinsTotal)
	local storage = ratioScore(input.Keys, input.KeysTotal)
	local score = clamp100((speed + smooth + memory + storage) / 4)
	local emblem, hint = PerfTest.Emblem(score)
	return {
		Axes = {
			{ Key = "Cpu", Label = "Processeur", Score = speed, Detail = "vitesse de l'ascension" },
			{
				Key = "Gpu",
				Label = "Carte graphique",
				Score = smooth,
				Detail = if input.Deaths
					then `{input.Deaths} chute{if input.Deaths == 1 then "" else "s"}`
					else "fluidité",
			},
			{
				Key = "Ram",
				Label = "Mémoire",
				Score = memory,
				Detail = if input.Coins and input.CoinsTotal
					then `{input.Coins}/{input.CoinsTotal} Bits`
					else "Bits ramassés",
			},
			{
				Key = "Ssd",
				Label = "Stockage",
				Score = storage,
				Detail = if input.Keys and input.KeysTotal
					then `{input.Keys}/{input.KeysTotal} clés USB`
					else "clés USB",
			},
		},
		Score = score,
		Emblem = emblem,
		EmblemHint = hint,
	}
end

return PerfTest
