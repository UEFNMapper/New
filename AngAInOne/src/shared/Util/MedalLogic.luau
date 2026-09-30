--!strict
--[[
	MedalLogic : calcul pur des médailles par monde (testé dans Lune, tests/medals.spec.luau).
	- Evaluate : médaille d'un passage (temps + morts + clés) selon Config/Medals
	- StartSplit / SplitTime : chrono d'un monde, en secondes d'ascension (RunElapsed)
	- UpdateBest : meilleur résultat sauvegardé (DataSchema.WorldBest), record seulement sans aide
	- NextGoal : prochaine médaille à viser (affichée sur la carte de médaille)
	- MarkAssisted : aide payante activée pendant l'ascension -> ascension ET monde marqués aussitôt
	- WatchFall : chute dans le vide vue par le serveur, comptée une fois par chute
]]

local Medals = require(script.Parent.Parent.Config.Medals)

export type Best = { Time: number, Medal: string }

-- Chrono du monde en cours (sauvegardé dans DataSchema.RunSplit).
export type Split = {
	World: number, -- monde chronométré (0 = aucun)
	Start: number, -- RunElapsed à l'entrée du monde
	Deaths: number, -- morts dans ce monde
	Keys: number, -- clés USB trouvées dans ce monde pendant ce passage
	Assisted: boolean, -- étape passée, bouclier ou passe avantage pendant ce monde
}

export type Goal = { Medal: string, Time: number, Deaths: number }

local MedalLogic = {}

local RANK: { [string]: number } = { Bronze = 1, Silver = 2, Gold = 3 }

-- Rang d'une médaille (0 = aucune).
function MedalLogic.Rank(medal: string?): number
	return if medal then RANK[medal] or 0 else 0
end

-- Clé de dictionnaire d'un monde (clés string obligatoires dans ProfileStore).
function MedalLogic.Key(world: number): string
	return `W{world}`
end

-- Médaille d'un monde nettoyé. `time` = nil : temps inconnu (reprise d'une ancienne sauvegarde,
-- commande de test) -> bronze.
function MedalLogic.Evaluate(world: number, time: number?, deaths: number, keys: number?, assisted: boolean?): string
	if not time then
		return "Bronze"
	end
	local rule = Medals.Rule(world)
	-- Aide payante (étape passée, bouclier, passes) : l'or reste réservé aux ascensions sans aide.
	if not assisted and time <= rule.Gold and deaths <= Medals.GoldMaxDeaths and (keys or 0) >= Medals.GoldMinKeys then
		return "Gold"
	end
	if time <= rule.Silver and deaths <= Medals.SilverMaxDeaths then
		return "Silver"
	end
	return "Bronze"
end

-- Prochaine médaille à viser après `medal` (nil = déjà l'or).
function MedalLogic.NextGoal(world: number, medal: string): Goal?
	local rule = Medals.Rule(world)
	local rank = MedalLogic.Rank(medal)
	if rank < 2 then
		return { Medal = "Silver", Time = rule.Silver, Deaths = Medals.SilverMaxDeaths }
	elseif rank < 3 then
		return { Medal = "Gold", Time = rule.Gold, Deaths = Medals.GoldMaxDeaths }
	end
	return nil
end

-- Démarre le chrono du monde `world` à `now` (secondes d'ascension).
function MedalLogic.StartSplit(split: Split, world: number, now: number, assisted: boolean)
	split.World = world
	split.Start = now
	split.Deaths = 0
	split.Keys = 0
	split.Assisted = assisted
end

-- Sous-ensemble des données du joueur touché par une aide (DataSchema.Data).
export type RunFlags = { RunStarted: boolean, RunAssisted: boolean, RunSplit: Split }

-- Aide payante (bottes anti-gravité, puce de vitesse, bouclier) ACTIVÉE pendant une ascension :
-- l'ascension (classement des temps) ET le monde en cours (or, record du monde) sont marqués tout de
-- suite, sans attendre la vérification périodique (activer puis couper en moins d'une seconde ne
-- passe plus inaperçu). Renvoie true si une ascension est en cours (donc marquée).
function MedalLogic.MarkAssisted(data: RunFlags): boolean
	if not data.RunStarted then
		return false
	end
	data.RunAssisted = true
	data.RunSplit.Assisted = true
	return true
end

-- Suivi serveur d'une chute dans le vide (voir ProgressService) : `Since` = instant d'entrée dans
-- le vide (nil = hors du vide), `Counted` = chute déjà comptée.
export type FallWatch = { Since: number?, Counted: boolean }

-- Renvoie true UNE SEULE fois par chute, quand le joueur est resté au moins `delay` secondes dans le
-- vide ; sortir du vide réarme le suivi.
function MedalLogic.WatchFall(watch: FallWatch, inVoid: boolean, now: number, delay: number): boolean
	if not inVoid then
		watch.Since = nil
		watch.Counted = false
		return false
	end
	local since = watch.Since
	if since == nil then
		watch.Since = now
		return false
	end
	if watch.Counted or now - since < delay then
		return false
	end
	watch.Counted = true
	return true
end

-- Temps du monde `world` à `now`, ou nil si le chrono ne concerne pas ce monde.
function MedalLogic.SplitTime(split: Split, world: number, now: number): number?
	if split.World ~= world or now < split.Start then
		return nil
	end
	return now - split.Start
end

-- Nouveau meilleur résultat d'un monde. `eligible` = passage sans aide avec un temps connu.
-- Renvoie (entrée à sauvegarder, nouveau record de temps ?, meilleure médaille qu'avant ?).
function MedalLogic.UpdateBest(
	previous: Best?,
	medal: string,
	time: number?,
	eligible: boolean
): (Best, boolean, boolean)
	local oldMedal = if previous then previous.Medal else ""
	local oldTime = if previous then previous.Time else 0
	local medalUp = MedalLogic.Rank(medal) > MedalLogic.Rank(oldMedal)
	local newBest = eligible and time ~= nil and (oldTime <= 0 or time < oldTime)
	return {
		Medal = if medalUp then medal else oldMedal,
		Time = if newBest and time then time else oldTime,
	},
		newBest,
		medalUp
end

-- Nombre de clés USB possédées dans un monde (KeyId "W{n}K{i}").
function MedalLogic.KeysInWorld(owned: { [string]: boolean }, world: number, perWorld: number): number
	local count = 0
	for i = 1, perWorld do
		if owned[`W{world}K{i}`] then
			count += 1
		end
	end
	return count
end

-- Monde d'une clé USB ("W3K2" -> 3), 0 si l'identifiant est inconnu.
function MedalLogic.KeyWorld(keyId: string): number
	return tonumber(string.match(keyId, "^W(%d+)K%d+$")) or 0
end

return table.freeze(MedalLogic)
