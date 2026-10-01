--!strict
--[[
	Tower : le contrat du deathrun. Une seule source de vérité partagée par le serveur
	(construction, progression, anti-triche), le client (HUD, pièges, histoire) et les tests.

	La tour PC est verticale : le lobby (Salle de démarrage) est au pied de la tour, puis on
	grimpe 7 MONDES (un par composant). Chaque monde a STAGES_PER_WORLD étapes ; chaque étape se
	termine par un checkpoint. À la fin d'un monde : une salle sûre avec un terminal antivirus
	(mini-jeu 2D). Réussir le mini-jeu ouvre le portail vers le monde suivant.

	Numérotation globale des checkpoints : 0 = lobby, 1..TOTAL_STAGES.
	Le checkpoint de la DERNIÈRE étape d'un monde est dans la salle du terminal.
]]

local Tower = {}

Tower.STAGES_PER_WORLD = 5

export type World = {
	Index: number,
	Id: string,
	Name: string,
	Component: string,
	AppSection: string, -- page de l'app partenaire AngAInOne que le monde incarne (barre latérale de l'app)
	AppSubtitle: string, -- sous-titre gris de cette page, sur le ton de l'app
	Primary: string, -- hex néon principal
	Secondary: string, -- hex accent
	Tint: string, -- hex ColorCorrection dans le monde
	Traps: { string }, -- pièges vedettes (TrapKinds)
	Minigame: string, -- mini-jeu du terminal de fin de monde (MinigameKinds)
	Intro: string, -- ce que dit Anga en entrant dans le monde
	Symptom: string, -- le symptôme du PC que ce monde répare (scénario « Opération Anti-Lag »)
	Minion: string, -- le sbire de LAGZ qui garde le terminal
	Incident: string, -- incident vedette de LAGZ dans ce monde (Incidents.Kinds ; "Any" = tous)
	Cleaned: string, -- ce que dit Anga quand le monde est nettoyé
}

-- Types de pièges animés côté client (voir TrapController) : tag "Trap" + attribut Kind.
Tower.TrapKinds = {
	"Zapper", -- décharge électrique : mortelle pendant la phase active (Period, Duty, Phase)
	"SpinBar", -- barre / pale qui tourne (Speed rad/s, Axis) : mortelle
	"Crusher", -- bloc qui va et vient (Offset Vector3, Period, Phase) : mortel
	"Mover", -- plateforme mobile SÛRE qui transporte le joueur (Offset, Period, Phase)
	"Vanish", -- plateforme qui disparaît après contact puis revient (Delay, Respawn)
	"Wind", -- zone de vent d'un ventilateur qui pousse (Direction Vector3, Strength)
	"Laser", -- faisceau qui balaie (Offset, Period, Phase) : mortel
	"Virus", -- ennemi qui patrouille entre des points (Waypoints, Speed) : mortel
	"Conveyor", -- tapis de données (Direction, Speed) : pousse
	"Bounce", -- trampoline condensateur (Power)
	"Heat", -- bouche de chaleur temporisée (Period, Duty, Phase) : mortelle quand active
	-- v2 « Opération Anti-Lag » (voir docs/SCENARIO.md). Offsets et Waypoints en coordonnées monde
	-- relatives à la position de repos ; Waypoints = "x,y,z;x,y,z" (le 1er point vaut 0,0,0).
	"Surge", -- impulsion électrique qui court le long d'un câble (Waypoints, Speed, Period) : mortelle
	"Powered", -- plateforme solide seulement quand le courant passe (Period, Duty, Phase) ; absente en BLACKOUT
	"TabRain", -- pluie d'onglets : fenêtres qui tombent (mortelles) puis restent un instant comme
	-- plateformes (Size Vector3 = zone, Period, Stay)
	"Flood", -- fuite mémoire : plan mortel qui MONTE puis redescend (Rise, Period, Phase)
	"Corrupt", -- dalle corrompue : solide/traversable en alternance (Period, Duty, Phase) ; inversée en CORRUPTION
	"Defrag", -- bloc SÛR qui coulisse de case en case (Waypoints, Step = secondes par case)
	"DustBall", -- boule de poussière qui roule en boucle (Waypoints, Speed) : mortelle
	"Pendulum", -- pioche / marteau qui se balance (Axis, Amplitude en degrés, Period, Phase, Pivot Vector3) : mortel
	"LagMover", -- plateforme SÛRE qui avance par à-coups, en retard (Offset, Period, Phase, Steps)
	"Spinner", -- roue de chargement : anneau de plateformes SÛRES qui tourne (Speed rad/s)
	"DeadPixels", -- dalles qui s'éteignent en vague (Direction, Period, Duty) : traversables éteintes
	"LoadBridge", -- pont qui se remplit comme une barre de progression (Period, Segments, Phase)
	"Cursor", -- curseur géant : vise le joueur, prévient, puis clique (Period, Radius, Area Vector3) : mortel
	"FirewallWall", -- mur percé qui avance (Offset, Period, Phase) : mortel sauf les trous
}

-- Mini-jeux 2D des terminaux antivirus (voir UI/Minigames).
Tower.MinigameKinds = {
	"Scan", -- tape les virus qui surgissent dans la grille avant qu'ils disparaissent
	"Firewall", -- déplace le pare-feu et tire sur les virus qui tombent
	"Memory", -- retrouve les paires de cartes mémoire
	"Dodge", -- guide le paquet de données entre les virus
	"Popup", -- Pop-up Killer : ferme les pubs (✕) avant que la RAM soit pleine, pas les faux boutons
	"Defrag", -- Défrag : échange les blocs pour regrouper chaque fichier
}

Tower.Worlds = {
	{
		Index = 1,
		Id = "PSU",
		Name = "Alimentation",
		Component = "Bloc d'alimentation",
		AppSection = "Alimentation",
		AppSubtitle = "Le mode d'alimentation de ton PC, et ce qui le fait couper sans prévenir.",
		Primary = "F6AD55",
		Secondary = "F0565B",
		Tint = "FFF3E6",
		Traps = { "Zapper", "Bounce", "SpinBar" },
		Minigame = "Scan",
		Intro = "Le virus a coupé le courant ! Évite les décharges électriques et saute sur les condensateurs.",
		Symptom = "Le PC s'éteint tout seul (coupures de courant)",
		Minion = "Sparky",
		Incident = "Blackout",
		Cleaned = "Le courant est revenu ! Le PC ne s'éteint plus tout seul.",
	},
	{
		Index = 2,
		Id = "RAM",
		Name = "Memory Lanes",
		Component = "Mémoire vive",
		AppSection = "Applications",
		AppSubtitle = "Ce qui se lance au démarrage et ce qui mange ta mémoire, appli par appli.",
		Primary = "8B7CFF",
		Secondary = "C084FC",
		Tint = "F1EEFF",
		Traps = { "Crusher", "Conveyor", "Mover" },
		Minigame = "Popup",
		Intro = "Les barrettes de RAM s'écrasent en rythme. Attends le bon moment pour passer !",
		Symptom = "Mémoire saturée : 200 onglets ouverts",
		Minion = "Pop-Up",
		Incident = "Popups",
		Cleaned = "La mémoire est libérée ! Plus d'onglets fantômes.",
	},
	{
		Index = 3,
		Id = "SSD",
		Name = "Data Vault",
		Component = "Stockage",
		AppSection = "Disques",
		AppSubtitle = "L'état de tes SSD et disques durs, et ce qui prend la place, dossier par dossier.",
		Primary = "38B2AC",
		Secondary = "4FD1C5",
		Tint = "E9FFFB",
		Traps = { "Vanish", "Crusher", "Conveyor" },
		Minigame = "Defrag",
		Intro = "Le virus efface les données : les plateformes disparaissent. Ne traîne pas !",
		Symptom = "Fichiers corrompus",
		Minion = "Corrupto",
		Incident = "Corruption",
		Cleaned = "Les fichiers sont réparés ! Le disque est tout propre.",
	},
	{
		Index = 4,
		Id = "Cooling",
		Name = "Cryo Tower",
		Component = "Refroidissement",
		AppSection = "Diagnostic · Températures",
		AppSubtitle = "Ce qui chauffe, ce qui souffle, et quoi faire, capteur par capteur.",
		Primary = "63B3ED",
		Secondary = "BEE3F8",
		Tint = "EBF8FF",
		Traps = { "Wind", "SpinBar", "Vanish" },
		Minigame = "Firewall",
		Intro = "Les ventilateurs soufflent fort ici. Accroche-toi et avance entre les rafales !",
		Symptom = "Surchauffe : ventilateurs bouchés",
		Minion = "Dusty",
		Incident = "Overheat",
		Cleaned = "Les ventilateurs respirent enfin ! Le PC refroidit.",
	},
	{
		Index = 5,
		Id = "CPU",
		Name = "The Core",
		Component = "Processeur",
		AppSection = "Test de perf",
		AppSubtitle = "Combien d'images par seconde ton PC tient vraiment, et ce qui le freine.",
		Primary = "F6E05E",
		Secondary = "FBD38D",
		Tint = "FFFBEA",
		Traps = { "Laser", "Heat", "Mover" },
		Minigame = "Scan",
		Intro = "Le processeur surchauffe ! Lasers et bouches de chaleur partout. Observe avant de courir.",
		Symptom = "Processeur à 100 % : un crypto-mineur !",
		Minion = "Minor",
		Incident = "Lag",
		Cleaned = "Le mineur est parti ! Le processeur souffle.",
	},
	{
		Index = 6,
		Id = "GPU",
		Name = "Render Canyon",
		Component = "Carte graphique",
		AppSection = "Pilotes GPU",
		AppSubtitle = "Le bon pilote pour ta carte graphique, installé proprement, étape par étape.",
		Primary = "48BB78",
		Secondary = "ED64A6",
		Tint = "F0FFF4",
		Traps = { "SpinBar", "Laser", "Zapper" },
		Minigame = "Memory",
		Intro = "Les ventilateurs de la carte graphique tournent à fond. Passe entre les pales !",
		Symptom = "Écran figé et artefacts",
		Minion = "Freezy",
		Incident = "Freeze",
		Cleaned = "Fini les freezes ! L'image est fluide.",
	},
	{
		Index = 7,
		Id = "AI",
		Name = "Neural Nexus",
		Component = "Puce IA",
		AppSection = "Plantages",
		AppSubtitle = "Ce qui a fait planter ton PC, et quoi faire ensuite.",
		Primary = "E9D8FD",
		Secondary = "9F7AEA",
		Tint = "FAF5FF",
		Traps = { "Virus", "Laser", "Mover" },
		Minigame = "Firewall",
		Intro = "Le cœur du virus est tout en haut. Évite ses gardes et détruis-le !",
		Symptom = "Le repaire de LAGZ",
		Minion = "LAGZ",
		Incident = "Any",
		Cleaned = "LAGZ est vaincu ! Le PC tourne à 144 FPS !",
	},
} :: { World }

Tower.WORLD_COUNT = #Tower.Worlds
Tower.USB_KEYS_PER_WORLD = 3 -- clés USB dorées cachées par monde (tag UsbKey, KeyId "W{n}K{i}")
Tower.TOTAL_STAGES = Tower.WORLD_COUNT * Tower.STAGES_PER_WORLD

-- Monde d'un checkpoint (0 = lobby).
function Tower.WorldOf(stage: number): number
	if stage <= 0 then
		return 0
	end
	return math.min(math.ceil(stage / Tower.STAGES_PER_WORLD), Tower.WORLD_COUNT)
end

-- Monde que le joueur est en train de PARCOURIR. Différent de WorldOf pendant la 1re étape d'un
-- monde : le 1er checkpoint est au bout de l'étape, donc Stage vaut encore le checkpoint de la
-- salle du terminal précédente (ou 0 au départ). Si ce terminal est nettoyé, on court déjà dans
-- le monde suivant. Sert aux incidents, au HUD, à l'ambiance.
function Tower.RunWorld(stage: number, cleared: number): number
	if stage <= 0 then
		return 1
	end
	local world = Tower.WorldOf(stage)
	if stage == world * Tower.STAGES_PER_WORLD and cleared >= world and world < #Tower.Worlds then
		return world + 1
	end
	return world
end

-- Checkpoint de la salle du terminal (dernière étape) du monde.
function Tower.TerminalStage(world: number): number
	return world * Tower.STAGES_PER_WORLD
end

-- Premier checkpoint du monde.
function Tower.FirstStage(world: number): number
	return (world - 1) * Tower.STAGES_PER_WORLD + 1
end

return table.freeze(Tower)
