--!strict
--[[
	AppPanelLogic : logique PURE des pages de l'app AngAInOne dans le jeu (testée dans Lune).
	Chaque monde de la tour incarne une page de l'app (Tower.Worlds[n].AppSection) :
	- Tower/AppPanels (serveur) pose 2 ou 3 grandes fenêtres de l'app par monde (tag AppPanel,
	  attributs World, Page, Kind ∈ AppPages.Kinds[World]) ;
	- Controllers/AppPanels (client) les dessine et les anime avec les valeurs calculées ici,
	  à partir de la progression DU JOUEUR dans ce monde (Progress) et des incidents de LAGZ ;
	- MinigamePanel habille la carte d'intro des terminaux en page de l'app (Intro).
	Tout est déterministe : mêmes entrées -> mêmes valeurs (t = horloge en secondes).
]]

local Tower = require(script.Parent.Parent.Config.Tower)

local AppPages = {}

-- Types de fenêtres par monde (l'ordre = ordre de pose côté serveur).
AppPages.Kinds = table.freeze({
	{ "PowerPlan", "Watts" },
	{ "Startup", "Memory" },
	{ "Drive", "Treemap" },
	{ "Temps", "Verdict" },
	{ "FpsGraph", "PerfScore", "LaunchBanner" },
	{ "Driver", "DriverLog" },
	{ "Crashes", "CrashAlert" },
}) :: { { string } }

-- Barre latérale de l'app (les sous-pages sont indentées) ; la page du monde y est surlignée.
AppPages.Sidebar = table.freeze({
	{ Label = "Tableau de bord", Indent = false },
	{ Label = "Windows", Indent = false },
	{ Label = "Applications", Indent = false },
	{ Label = "Matériel", Indent = false },
	{ Label = "Pilotes GPU", Indent = true },
	{ Label = "Alimentation", Indent = true },
	{ Label = "Disques", Indent = true },
	{ Label = "Gaming", Indent = false },
	{ Label = "Test de perf", Indent = true },
	{ Label = "Diagnostic", Indent = false },
	{ Label = "Plantages", Indent = false },
}) :: { { Label: string, Indent: boolean } }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function frac(x: number): number
	return x - math.floor(x)
end

-- Nombre à une décimale, virgule française : 420.5 -> "420,5".
function AppPages.Decimal(value: number): string
	return (string.gsub(string.format("%.1f", value), "%.", ","))
end

-- Libellé de la barre latérale pour la page d'un monde ("Diagnostic · Températures" -> "Diagnostic").
function AppPages.SidebarLabel(world: number): string
	local def = Tower.Worlds[world]
	if not def then
		return "Tableau de bord"
	end
	return (string.match(def.AppSection, "^(.-)%s*·") or def.AppSection)
end

------------------------------------------------------------------------------------
-- Progression du joueur dans un monde
------------------------------------------------------------------------------------

export type Progress = {
	World: number,
	Reached: number, -- checkpoints du monde atteints (0..STAGES_PER_WORLD, le dernier = salle du terminal)
	Cleared: boolean, -- terminal du monde réussi
	Fraction: number, -- 0..1 : 0,9 au plus avant le nettoyage, 1 une fois nettoyé
}

function AppPages.Progress(world: number, stage: number, cleared: number): Progress
	local stages = Tower.STAGES_PER_WORLD
	local reached = math.clamp(math.floor(stage) - Tower.FirstStage(world) + 1, 0, stages)
	local done = cleared >= world
	return {
		World = world,
		Reached = if done then stages else reached,
		Cleared = done,
		Fraction = if done then 1 else reached / stages * 0.9,
	}
end

------------------------------------------------------------------------------------
-- Monde 1 · Alimentation
------------------------------------------------------------------------------------

AppPages.PowerPlans = table.freeze({ "Économie d'énergie", "Équilibré", "Performances maximales" })

-- Mode d'alimentation actif (index dans PowerPlans).
function AppPages.PowerPlan(p: Progress): number
	if p.Cleared then
		return 3
	end
	return if p.Reached >= 2 then 2 else 1
end

AppPages.MAX_WATTS = 650

-- Consommation affichée (W) à l'instant t : instable tant que le monde est infecté (coupures
-- brèves), stable une fois nettoyé, 0 pendant un BLACKOUT.
function AppPages.Watts(p: Progress, t: number, blackout: boolean): number
	if blackout then
		return 0
	end
	if p.Cleared then
		return math.floor(520 + 6 * math.sin(t * 1.7) + 0.5)
	end
	local base = lerp(90, 430, p.Fraction)
	if frac(t * 0.37) < 0.08 then
		return math.floor(base * 0.2 + 0.5) -- micro-coupure : Sparky joue avec le 12 V
	end
	local wobble = 0.22 * math.sin(t * 5.1) + 0.12 * math.sin(t * 13.7 + 1.3)
	return math.floor(math.clamp(base * (1 + wobble), 0, AppPages.MAX_WATTS) + 0.5)
end

------------------------------------------------------------------------------------
-- Monde 2 · Applications
------------------------------------------------------------------------------------

export type StartupApp = { Name: string, Impact: string }

-- Du pire (en haut) au plus anodin : on les coupe par le bas à chaque checkpoint ;
-- LAGZ_miner.exe ne se laisse désactiver qu'au nettoyage du monde.
AppPages.StartupApps = table.freeze({
	{ Name = "LAGZ_miner.exe", Impact = "Très élevé" },
	{ Name = "200 onglets de navigateur", Impact = "Très élevé" },
	{ Name = "PubPopUp Deluxe", Impact = "Élevé" },
	{ Name = "Barre d'outils MegaSearch", Impact = "Élevé" },
	{ Name = "Nettoyeur de PC « gratuit »", Impact = "Moyen" },
	{ Name = "Mise à jour de la mise à jour", Impact = "Moyen" },
	{ Name = "ChatQuiDanse.gif", Impact = "Faible" },
}) :: { StartupApp }

-- Nombre d'applis de la liste déjà désactivées (par le bas).
function AppPages.StartupOff(p: Progress): number
	local count = #AppPages.StartupApps
	if p.Cleared then
		return count
	end
	return math.min(p.Reached, count - 1)
end

-- L'appli n° i (1 = en haut) est-elle encore activée ?
function AppPages.StartupEnabled(p: Progress, i: number): boolean
	return i <= #AppPages.StartupApps - AppPages.StartupOff(p)
end

-- « 214 applis au démarrage » -> 12 une fois nettoyé.
function AppPages.StartupCount(p: Progress): number
	return math.floor(lerp(214, 12, p.Fraction) + 0.5)
end

-- Durée du démarrage de Windows (secondes) : 3 min 40 s -> 9 s.
function AppPages.BootSeconds(p: Progress): number
	return math.floor(lerp(220, 9, p.Fraction) + 0.5)
end

AppPages.RAM_TOTAL = 16

-- Mémoire utilisée (Go sur RAM_TOTAL).
function AppPages.MemoryUsed(p: Progress): number
	return lerp(15.8, 5.4, p.Fraction)
end

-- Plus gros consommateurs de mémoire (Go) : les nuisibles fondent avec la progression.
function AppPages.MemoryHogs(p: Progress): { { Name: string, Gigas: number } }
	local keep = 1 - p.Fraction
	return {
		{ Name = "200 onglets de navigateur", Gigas = 9.1 * keep },
		{ Name = "LAGZ_miner.exe", Gigas = 3.2 * keep },
		{ Name = "PubPopUp Deluxe", Gigas = 1.9 * keep },
		{ Name = "Windows", Gigas = 1.6 },
	}
end

------------------------------------------------------------------------------------
-- Monde 3 · Disques
------------------------------------------------------------------------------------

AppPages.DISK_TOTAL = 464.2

-- Go utilisés sur C: (420,5 au départ, comme dans l'app).
function AppPages.DiskUsed(p: Progress): number
	return lerp(420.5, 118.3, p.Fraction)
end

function AppPages.DiskPercent(p: Progress): number
	return math.floor(AppPages.DiskUsed(p) / AppPages.DISK_TOTAL * 100 + 0.5)
end

-- État du disque : "Sain" une fois nettoyé, "Attention" tant qu'il est trop plein.
function AppPages.DiskStatus(p: Progress): string
	if p.Cleared then
		return "Sain"
	end
	return if AppPages.DiskPercent(p) >= 75 then "Attention" else "Correct"
end

export type Share = { Name: string, Share: number }

-- Qui prend la place (parts de C:, somme = 1) : LAGZ_cache fond, l'espace libre grandit.
function AppPages.DiskShares(p: Progress): { Share }
	local lagz = 0.7 * (1 - p.Fraction)
	local list = {
		{ Name = "LAGZ_cache", Share = lagz },
		{ Name = "Windows", Share = 0.12 },
		{ Name = "Jeux", Share = 0.09 },
		{ Name = "Vidéos d'Anga", Share = 0.05 },
		{ Name = "Autres", Share = 0.04 },
	}
	local used = 0
	for _, entry in list do
		used += entry.Share
	end
	table.insert(list, { Name = "Espace libre", Share = math.max(1 - used, 0) })
	return list
end

export type Tile = { Name: string, Share: number, X: number, Y: number, W: number, H: number }

-- Carte « Où part ton espace disque » : découpe du carré unité en rectangles d'aire = part
-- (tranches alternées, du plus gros au plus petit). Les parts nulles sont omises.
function AppPages.Treemap(shares: { Share }): { Tile }
	local list = {}
	for _, entry in shares do
		if entry.Share > 1e-4 then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a: Share, b: Share): boolean
		return a.Share > b.Share
	end)
	local total = 0
	for _, entry in list do
		total += entry.Share
	end
	local tiles: { Tile } = {}
	local x, y, w, h = 0, 0, 1, 1
	local remaining = total
	for i, entry in list do
		local ratio = if remaining > 0 then entry.Share / remaining else 1
		local last = i == #list
		if w >= h then
			local cut = if last then w else w * ratio
			table.insert(tiles, { Name = entry.Name, Share = entry.Share / total, X = x, Y = y, W = cut, H = h })
			x += cut
			w -= cut
		else
			local cut = if last then h else h * ratio
			table.insert(tiles, { Name = entry.Name, Share = entry.Share / total, X = x, Y = y, W = w, H = cut })
			y += cut
			h -= cut
		end
		remaining -= entry.Share
	end
	return tiles
end

------------------------------------------------------------------------------------
-- Monde 4 · Diagnostic · Températures
------------------------------------------------------------------------------------

-- Températures (°C) du processeur et de la carte graphique ; la SURCHAUFFE ajoute 9 °C.
function AppPages.Temps(p: Progress, overheat: boolean): (number, number)
	local boost = if overheat then 9 else 0
	local cpu = math.min(math.floor(lerp(97, 45, p.Fraction) + 0.5) + boost, 105)
	local gpu = math.min(math.floor(lerp(91, 42, p.Fraction) + 0.5) + boost, 105)
	return cpu, gpu
end

-- Vitesse des ventilateurs (tr/min) : à fond et bouchés, puis calmes.
function AppPages.FanRpm(p: Progress): number
	return math.floor(lerp(4800, 1100, p.Fraction) / 10 + 0.5) * 10
end

-- Mot d'état d'une température (et niveau pour la couleur).
function AppPages.TempLabel(celsius: number): (string, string)
	if celsius >= 85 then
		return "Brûlant", "Bad"
	elseif celsius >= 65 then
		return "Chaud", "Warn"
	end
	return "Frais", "Good"
end

-- Score du diagnostic (/100).
function AppPages.DiagnosticScore(p: Progress): number
	return math.floor(lerp(18, 96, p.Fraction) + 0.5)
end

-- « Ce qu'il faut regarder » : réglé au fil des checkpoints (Dusty ne part qu'au nettoyage).
AppPages.DiagnosticIssues = table.freeze({
	{ Title = "Ventilateurs bouchés par la poussière", Fix = 2 },
	{ Title = "Pâte thermique toute sèche", Fix = 4 },
	{ Title = "Dusty squatte le radiateur", Fix = 99 },
}) :: { { Title: string, Fix: number } }

function AppPages.IssueFixed(p: Progress, i: number): boolean
	local issue = AppPages.DiagnosticIssues[i]
	return p.Cleared or (issue ~= nil and p.Reached >= issue.Fix)
end

------------------------------------------------------------------------------------
-- Monde 5 · Test de perf
------------------------------------------------------------------------------------

AppPages.FPS_GOAL = 144

-- FPS moyen visé à ce stade (3 -> 144).
function AppPages.FpsTarget(p: Progress): number
	if p.Cleared then
		return AppPages.FPS_GOAL
	end
	return math.floor(lerp(3, 120, p.Fraction / 0.9) + 0.5)
end

-- Mesure « en direct » à l'instant t : bruit autour de la cible, trous pendant un LAG SPIKE.
function AppPages.FpsSample(p: Progress, t: number, lag: boolean): number
	local target = AppPages.FpsTarget(p)
	if lag and frac(t * 1.6) < 0.45 then
		return math.floor(1 + 2 * frac(t * 7.3))
	end
	local noise = if p.Cleared then 0.02 else 0.18
	local wobble = noise * (math.sin(t * 3.1) + 0.6 * math.sin(t * 8.7 + 0.4))
	return math.clamp(math.floor(target * (1 + wobble) + 0.5), 0, 240)
end

-- Score du test de perf (1 250 -> 14 400).
function AppPages.PerfScore(p: Progress): number
	return math.floor(lerp(1250, 14400, p.Fraction) / 10 + 0.5) * 10
end

-- Bandeau « Lancer le test » : état + avancement (0..100).
function AppPages.PerfTest(p: Progress): (string, number)
	if p.Cleared then
		return "Done", 100
	elseif p.Reached <= 0 then
		return "Ready", 0
	end
	return "Running", math.floor(p.Fraction / 0.9 * 95 + 0.5)
end

------------------------------------------------------------------------------------
-- Monde 6 · Pilotes GPU
------------------------------------------------------------------------------------

AppPages.DRIVER_NEW = "610.47"
AppPages.DRIVER_OLD = "399.99"

-- Étape de l'installation (1..3 ; 4 = installé) et libellé.
AppPages.DriverSteps = table.freeze({
	"Préparer l'installation",
	"Télécharger et extraire",
	"Installer le pilote",
	"Pilote installé",
}) :: { string }

function AppPages.DriverStep(p: Progress): number
	if p.Cleared then
		return 4
	end
	return if p.Reached >= 4 then 3 elseif p.Reached >= 2 then 2 else 1
end

-- Avancement de la barre « Télécharger et extraire » (0..100).
function AppPages.DriverPercent(p: Progress): number
	if p.Cleared then
		return 100
	end
	return math.min(math.floor(p.Fraction / 0.9 * 99 + 0.5), 99)
end

-- Journal d'opération : une ligne de plus à chaque checkpoint (la dernière au nettoyage).
AppPages.DriverLog = table.freeze({
	"Carte détectée : AngaForce RTX 3070 Phantom",
	"Ancien pilote 399.99 : Freezy a tout figé",
	"Téléchargement du pilote 610.47",
	"Extraction : 1 204 fichiers",
	"Nettoyage complet de l'ancien pilote",
	"Installation terminée, image fluide",
}) :: { string }

function AppPages.DriverLogLines(p: Progress): number
	if p.Cleared then
		return #AppPages.DriverLog
	end
	return math.min(p.Reached + 1, #AppPages.DriverLog - 1)
end

-- Étiquette d'un pont de chargement (LoadBridge) : phase = LoadBridge.FILL (1), STALL (2),
-- FULL (3), WARN (4), EMPTY (5).
function AppPages.BridgeLabel(progress: number, phase: number): string
	local percent = math.floor(math.clamp(progress, 0, 1) * 100 + 0.5)
	if phase == 2 then
		return `Pilote {AppPages.DRIVER_NEW} · bloqué à {percent} %`
	elseif phase == 5 then
		return `Pilote {AppPages.DRIVER_NEW} · nouvel essai…`
	elseif phase == 3 or phase == 4 then
		return `Pilote {AppPages.DRIVER_NEW} · extrait ✓`
	end
	return `Téléchargement du pilote {AppPages.DRIVER_NEW} · {percent} %`
end

------------------------------------------------------------------------------------
-- Monde 7 · Plantages
------------------------------------------------------------------------------------

export type Crash = { Title: string, Detail: string }

AppPages.Crashes = table.freeze({
	{ Title = "LAGZ.exe s'est figé 19 fois", Detail = "19 fois, dernière il y a 2 minutes" },
	{ Title = "dwm.exe s'est fermé tout seul", Detail = "5 fois, l'écran a clignoté" },
	{ Title = "Arrêt forcé par le bouton d'alimentation", Detail = "Sparky, au monde 1" },
	{ Title = "PubPopUp.exe s'est fermé tout seul", Detail = "Il reviendra (ou pas)" },
	{ Title = "Freezy.exe ne répond pas", Detail = "Depuis 12 minutes" },
	{ Title = "Erreurs de lecture sur un disque", Detail = "4 fois, Corrupto rôdait" },
}) :: { Crash }

-- Nombre d'entrées déjà réglées (en partant du bas).
function AppPages.CrashesFixed(p: Progress): number
	if p.Cleared then
		return #AppPages.Crashes
	end
	return math.min(p.Reached, #AppPages.Crashes - 1)
end

------------------------------------------------------------------------------------
-- Intros des terminaux (MinigamePanel) : la page de l'app qui fait une action
------------------------------------------------------------------------------------

export type Intro = {
	World: number,
	Page: string, -- titre de la page (AppSection)
	Subtitle: string,
	Sidebar: string, -- entrée surlignée de la barre latérale
	Action: string, -- le bouton violet de l'app
	Task: string, -- ce que l'action traite
	Detail: string, -- ligne grise sous la tâche
}

local INTROS: { { Action: string, Task: string, Detail: string } } = {
	{
		Action = "Appliquer le plan",
		Task = "Plan « Performances maximales »",
		Detail = "Sparky tient le câble : scanne et élimine les virus.",
	},
	{
		Action = "Désactiver au démarrage",
		Task = "214 applis au démarrage",
		Detail = "Pop-Up relance ses pubs : ferme-les avant la saturation.",
	},
	{
		Action = "Analyser",
		Task = "C: · 420,5 Go · 90 % occupés",
		Detail = "LAGZ_cache prend 70 % du disque.",
	},
	{
		Action = "Analyse express",
		Task = "CPU 97 °C · GPU 91 °C",
		Detail = "Dusty bouche les ventilos.",
	},
	{ Action = "Lancer le test", Task = "3 FPS · objectif 144 FPS", Detail = "Minor fait tourner son crypto-mineur." },
	{
		Action = "Télécharger et extraire",
		Task = `Étape 1 — Préparer l'installation`,
		Detail = `Pilote {AppPages.DRIVER_NEW} · Freezy a figé l'ancien.`,
	},
	{ Action = "Remettre d'aplomb", Task = "LAGZ.exe s'est figé 19 fois", Detail = "Le cœur du virus est ici." },
}

-- Page d'un mini-jeu pour la borne d'arcade (quand le jeu n'est pas celui du monde du niveau).
local KIND_WORLD: { [string]: number } = { Scan = 1, Popup = 2, Defrag = 3, Firewall = 4, Dodge = 5, Memory = 6 }

-- Monde (page de l'app) d'une intro : celui du niveau si c'est son mini-jeu, sinon celui du jeu.
function AppPages.IntroWorld(kind: string, level: number): number
	local world = math.clamp(math.floor(level), 1, Tower.WORLD_COUNT)
	if Tower.Worlds[world].Minigame == kind then
		return world
	end
	return KIND_WORLD[kind] or world
end

function AppPages.Intro(world: number): Intro
	local w = math.clamp(math.floor(world), 1, Tower.WORLD_COUNT)
	local def = Tower.Worlds[w]
	local intro = INTROS[w]
	return {
		World = w,
		Page = def.AppSection,
		Subtitle = def.AppSubtitle,
		Sidebar = AppPages.SidebarLabel(w),
		Action = intro.Action,
		Task = intro.Task,
		Detail = intro.Detail,
	}
end

return table.freeze(AppPages)
