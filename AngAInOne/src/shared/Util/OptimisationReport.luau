--!strict
--[[
	OptimisationReport : le contenu du « Rapport AngAInOne » de fin (page Diagnostic de l'app),
	logique PURE (docs/AUDIT_V3.md, C3). L'écran (UI/Screens/Moments) ne fait que l'afficher.
	- Score 48/100 au départ -> 100/100 ; 5 cartes (Score, Températures, Stockage, Stabilité, À jour)
	- Avant / après : FPS, température, ping (Util/PcHealth, 0 puis 7 mondes nettoyés)
	- « Ce qu'il faut regarder » : une entrée par menace supprimée (Constat / Pourquoi / Quoi faire)
	- Temps de l'ascension, record, clés USB trouvées, chutes de l'ascension
]]

local Tower = require(script.Parent.Parent.Config.Tower)
local PcHealth = require(script.Parent.PcHealth)
local Time = require(script.Parent.Time)

local OptimisationReport = {}

OptimisationReport.START_SCORE = 48 -- score du PC d'Anga avant la mission
OptimisationReport.POINTS = 109 -- « 109 points vérifiés » (comme l'app)

export type Card = { Title: string, Score: number, Good: boolean, Detail: string }
export type Delta = { Label: string, From: number, To: number, Unit: string }
export type Entry = {
	World: number,
	Minion: string,
	Title: string,
	Constat: string,
	Pourquoi: string,
	QuoiFaire: string,
	Action: string,
}
export type Input = {
	Time: number?, -- secondes d'ascension
	Record: boolean?,
	Assisted: boolean?,
	Keys: number?, -- clés USB trouvées (pour toujours)
	KeysTotal: number?,
	Deaths: number?, -- chutes pendant CETTE ascension (nil = inconnu)
}
export type Report = {
	StartScore: number,
	Score: number,
	Threats: number,
	Headline: string,
	Summary: string,
	Deltas: { Delta },
	Cards: { Card },
	Entries: { Entry },
	TimeText: string,
	RecordText: string?,
	KeysText: string,
	DeathsText: string?,
}

-- Une entrée drôle par menace (index = monde). Une phrase courte par ligne.
local ENTRIES: { { Title: string, Constat: string, Pourquoi: string, QuoiFaire: string, Action: string } } = {
	{
		Title = "Sparky coupait le courant pour rigoler",
		Constat = "Le PC s'éteignait tout seul, pile au mauvais moment.",
		Pourquoi = "Sparky adore les étincelles. Beaucoup trop.",
		QuoiFaire = "Rien : tu l'as déjà débranché !",
		Action = "Débranché ✓",
	},
	{
		Title = "Pop-Up ouvrait 200 onglets",
		Constat = "La mémoire était pleine de pubs et d'onglets fantômes.",
		Pourquoi = "Pop-Up croit que tout le monde a gagné un cadeau.",
		QuoiFaire = "Rien : tu as fermé toutes ses fenêtres !",
		Action = "Fermé ✓",
	},
	{
		Title = "Corrupto peignait les fichiers en rose",
		Constat = "Des pixels roses et noirs partout sur le disque.",
		Pourquoi = "Il trouve que la texture manquante, c'est joli.",
		QuoiFaire = "Rien : le disque est réparé, dossier par dossier !",
		Action = "Réparé ✓",
	},
	{
		Title = "Dusty bouchait les ventilateurs",
		Constat = "97 °C : le PC chauffait comme un grille-pain.",
		Pourquoi = "Dusty adore faire des câlins aux pales.",
		QuoiFaire = "Rien : les ventilateurs soufflent à nouveau !",
		Action = "Dépoussiéré ✓",
	},
	{
		Title = "Minor minait en cachette",
		Constat = "Processeur à 100 %, même sans rien lancer.",
		Pourquoi = "Minor cherche des pièces… dans TON processeur.",
		QuoiFaire = "Rien : sa pioche est confisquée !",
		Action = "Arrêté ✓",
	},
	{
		Title = "Freezy figeait l'écran",
		Constat = "Image bloquée et artefacts sur la carte graphique.",
		Pourquoi = "Freezy trouve que tout va beaucoup trop vite.",
		QuoiFaire = "Rien : l'image est fluide, le pilote est propre !",
		Action = "Dégelé ✓",
	},
	{
		Title = "LAGZ avait pris la puce IA",
		Constat = "3 FPS et 999 ms de ping : le live était fichu.",
		Pourquoi = "LAGZ se nourrit de la puissance des PC. Miam.",
		QuoiFaire = "Rien : LAGZ est supprimé. Le live peut commencer !",
		Action = "Supprimé ✓",
	},
}

local MONTHS = {
	"janvier",
	"février",
	"mars",
	"avril",
	"mai",
	"juin",
	"juillet",
	"août",
	"septembre",
	"octobre",
	"novembre",
	"décembre",
}

-- « 30 septembre 2026 à 22:36 » (table au format os.date("*t")).
function OptimisationReport.DateText(
	date: { year: number, month: number, day: number, hour: number, min: number }
): string
	local month = MONTHS[math.clamp(date.month, 1, 12)]
	return string.format("%d %s %d à %02d:%02d", date.day, month, date.year, date.hour, date.min)
end

-- « Analyse complète · rapport du … · 109 points vérifiés »
function OptimisationReport.Verdict(dateText: string): string
	return `Analyse complète · rapport du {dateText} · {OptimisationReport.POINTS} points vérifiés`
end

-- Score affiché pendant l'animation (alpha 0 -> 1) : entier de START_SCORE à `target`.
function OptimisationReport.ScoreAt(alpha: number, target: number?): number
	local goal = target or 100
	local a = math.clamp(alpha, 0, 1)
	local eased = 1 - (1 - a) ^ 3
	return math.floor(OptimisationReport.START_SCORE + (goal - OptimisationReport.START_SCORE) * eased + 0.5)
end

-- Note de stabilité selon les chutes de l'ascension (50 au minimum : on a gagné !).
function OptimisationReport.StabilityScore(deaths: number?): number
	if deaths == nil then
		return 100
	end
	return math.clamp(100 - math.floor(deaths) * 2, 50, 100)
end

-- Note de stockage selon les clés USB trouvées (70 à 100).
function OptimisationReport.StorageScore(keys: number, total: number): number
	if total <= 0 then
		return 100
	end
	return 70 + math.floor(30 * math.clamp(keys, 0, total) / total + 0.5)
end

function OptimisationReport.Build(input: Input): Report
	local worlds = Tower.WORLD_COUNT
	local before, after = PcHealth.Stats(0), PcHealth.Stats(worlds)
	local keysTotal = input.KeysTotal or worlds * Tower.USB_KEYS_PER_WORLD
	local keys = math.clamp(math.floor(input.Keys or 0), 0, keysTotal)
	local deaths = if input.Deaths ~= nil then math.max(math.floor(input.Deaths), 0) else nil
	local timeText = Time.Clock(input.Time or 0)
	local minions = worlds - 1

	local stability = OptimisationReport.StabilityScore(deaths)
	local storage = OptimisationReport.StorageScore(keys, keysTotal)
	local stabilityDetail = if deaths == nil
		then "Aucun plantage"
		elseif deaths == 0 then "Aucune chute : parfait !"
		else `{deaths} chute{if deaths > 1 then "s" else ""}, 0 écran bleu`

	local entries: { Entry } = {}
	for w = 1, worlds do
		local text = ENTRIES[w]
		local def = Tower.Worlds[w]
		if text and def then
			table.insert(entries, {
				World = w,
				Minion = def.Minion,
				Title = text.Title,
				Constat = text.Constat,
				Pourquoi = text.Pourquoi,
				QuoiFaire = text.QuoiFaire,
				Action = text.Action,
			})
		end
	end

	return {
		StartScore = OptimisationReport.START_SCORE,
		Score = 100,
		Threats = worlds,
		Headline = `Le PC d'Anga est réparé : {after.Fps} FPS, prêt pour le live.`,
		Summary = `LAGZ et ses {minions} sbires sont supprimés en {timeText}.`,
		Deltas = {
			{ Label = "FPS", From = before.Fps, To = after.Fps, Unit = "" },
			{ Label = "Température", From = before.Temp, To = after.Temp, Unit = " °C" },
			{ Label = "Ping", From = before.Ping, To = after.Ping, Unit = " ms" },
		},
		Cards = {
			{
				Title = "Score",
				Score = 100,
				Good = true,
				Detail = `{OptimisationReport.START_SCORE}/100 avant ta mission`,
			},
			{
				Title = "Températures",
				Score = 100,
				Good = true,
				Detail = `CPU {after.Temp} °C (avant : {before.Temp} °C), ventilos propres`,
			},
			{
				Title = "Stockage",
				Score = storage,
				Good = storage >= 80,
				Detail = `Fichiers réparés · clés USB {keys}/{keysTotal}`,
			},
			{ Title = "Stabilité", Score = stability, Good = stability >= 70, Detail = stabilityDetail },
			{
				Title = "À jour",
				Score = 100,
				Good = true,
				Detail = `{worlds} menaces supprimées · {after.Fps} FPS · {after.Ping} ms`,
			},
		},
		Entries = entries,
		TimeText = timeText,
		RecordText = if input.Record
			then "NOUVEAU RECORD !"
			elseif input.Assisted then "Course assistée (hors classement)"
			else nil,
		KeysText = `{keys}/{keysTotal}`,
		DeathsText = if deaths ~= nil then tostring(deaths) else nil,
	}
end

return table.freeze(OptimisationReport)
