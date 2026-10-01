--!strict
--[[
	CrashLogic : logique PURE du journal des « Plantages » (Controllers/CrashLog, page Plantages).
	Chaque mort du joueur local devient une entrée façon app AngAInOne :
	    « Joueur.exe s'est fermé tout seul »   ·   « cause : Ventilateur · 3e fois ici »
	- CauseLabel(cause) : nom lisible d'une cause (Kind du piège, "Void", "Hazard")
	- ExeName(name) : « Joueur.exe » à partir du pseudo
	- new() / Record(log, cause, world) : compteurs de la session (par cause et par monde)
	- Format(exe, cause, count) : titre et détail de la carte
]]

local CrashLogic = {}

-- Causes envoyées par TrapController (Kind du piège, "Void", "Hazard") -> nom affiché.
local LABELS: { [string]: string } = {
	Zapper = "Décharge électrique",
	SpinBar = "Ventilateur",
	Crusher = "Barrette de RAM",
	Laser = "Laser de rendu",
	Virus = "Virus",
	Heat = "Bouche de chaleur",
	Surge = "Surtension",
	TabRain = "Pluie d'onglets",
	Flood = "Fuite mémoire",
	DustBall = "Boule de poussière",
	Pendulum = "Pioche du mineur",
	Cursor = "Curseur géant",
	FirewallWall = "Pare-feu",
	ThermalShutdown = "Arrêt thermique (100 °C)",
	Void = "Chute dans le vide",
	Hazard = "Court-circuit",
}
CrashLogic.UNKNOWN = "Cause inconnue"

function CrashLogic.CauseLabel(cause: string?): string
	if type(cause) ~= "string" or cause == "" then
		return CrashLogic.UNKNOWN
	end
	return LABELS[cause] or cause
end

-- 1 -> « 1re », 3 -> « 3e ».
function CrashLogic.Ordinal(n: number): string
	local k = math.max(math.floor(n), 1)
	return if k == 1 then "1re" else `{k}e`
end

-- Nom de processus du joueur : pseudo sans espaces ni caractères exotiques, 16 caractères max.
function CrashLogic.ExeName(name: string?): string
	local clean = string.gsub(if type(name) == "string" then name else "", "[^%w_%-]", "")
	if clean == "" then
		clean = "Joueur"
	end
	return string.sub(clean, 1, 16) .. ".exe"
end

export type Log = {
	Here: { [string]: number }, -- "{monde}:{cause}" -> morts (le « ici » de la carte)
	ByCause: { [string]: number }, -- cause -> morts de la session
	Total: number,
	LastCause: string?,
}

function CrashLogic.new(): Log
	return { Here = {}, ByCause = {}, Total = 0, LastCause = nil }
end

-- Enregistre une mort ; renvoie le nombre de morts pour cette cause dans ce monde (1 = première).
function CrashLogic.Record(log: Log, cause: string?, world: number): number
	local key = if type(cause) == "string" and cause ~= "" then cause else "Unknown"
	local here = `{math.floor(world)}:{key}`
	log.Here[here] = (log.Here[here] or 0) + 1
	log.ByCause[key] = (log.ByCause[key] or 0) + 1
	log.Total += 1
	log.LastCause = key
	return log.Here[here]
end

-- Titre et détail de la carte. À partir de 3 fois au même endroit, le ton de l'app change.
function CrashLogic.Format(exe: string, cause: string?, count: number): (string, string)
	local title = if count >= 3 then `{exe} s'est figé {count} fois ici` else `{exe} s'est fermé tout seul`
	return title, `cause : {CrashLogic.CauseLabel(cause)} · {CrashLogic.Ordinal(count)} fois ici`
end

-- Cause la plus fréquente de la session (nil si aucune mort) : pour la page Plantages.
function CrashLogic.TopCause(log: Log): (string?, number)
	local best, count = nil, 0
	for cause, n in log.ByCause do
		if n > count or (n == count and best ~= nil and cause < best) then
			best, count = cause, n
		end
	end
	return best, count
end

return table.freeze(CrashLogic)
