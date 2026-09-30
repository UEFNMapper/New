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
	AppSection: string, -- section de l'app partenaire AngAInOne
	Primary: string, -- hex néon principal
	Secondary: string, -- hex accent
	Tint: string, -- hex ColorCorrection dans le monde
	Traps: { string }, -- pièges vedettes (TrapKinds)
	Minigame: string, -- mini-jeu du terminal de fin de monde (MinigameKinds)
	Intro: string, -- ce que dit Anga en entrant dans le monde
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
}

-- Mini-jeux 2D des terminaux antivirus (voir UI/Minigames).
Tower.MinigameKinds = {
	"Scan", -- tape les virus qui surgissent dans la grille avant qu'ils disparaissent
	"Firewall", -- déplace le pare-feu et tire sur les virus qui tombent
	"Memory", -- retrouve les paires de cartes mémoire
	"Dodge", -- guide le paquet de données entre les virus
}

Tower.Worlds = {
	{
		Index = 1,
		Id = "PSU",
		Name = "La Centrale",
		Component = "Alimentation",
		AppSection = "Démarrage",
		Primary = "F6AD55",
		Secondary = "F0565B",
		Tint = "FFF3E6",
		Traps = { "Zapper", "Bounce", "SpinBar" },
		Minigame = "Scan",
		Intro = "Le virus a coupé le courant ! Évite les décharges électriques et saute sur les condensateurs.",
	},
	{
		Index = 2,
		Id = "RAM",
		Name = "Memory Lanes",
		Component = "Mémoire vive",
		AppSection = "Applications",
		Primary = "8B7CFF",
		Secondary = "C084FC",
		Tint = "F1EEFF",
		Traps = { "Crusher", "Conveyor", "Mover" },
		Minigame = "Memory",
		Intro = "Les barrettes de RAM s'écrasent en rythme. Attends le bon moment pour passer !",
	},
	{
		Index = 3,
		Id = "SSD",
		Name = "Data Vault",
		Component = "Stockage",
		AppSection = "Nettoyage & réparation",
		Primary = "38B2AC",
		Secondary = "4FD1C5",
		Tint = "E9FFFB",
		Traps = { "Vanish", "Crusher", "Conveyor" },
		Minigame = "Dodge",
		Intro = "Le virus efface les données : les plateformes disparaissent. Ne traîne pas !",
	},
	{
		Index = 4,
		Id = "Cooling",
		Name = "Cryo Tower",
		Component = "Refroidissement",
		AppSection = "Diagnostic",
		Primary = "63B3ED",
		Secondary = "BEE3F8",
		Tint = "EBF8FF",
		Traps = { "Wind", "SpinBar", "Vanish" },
		Minigame = "Firewall",
		Intro = "Les ventilateurs soufflent fort ici. Accroche-toi et avance entre les rafales !",
	},
	{
		Index = 5,
		Id = "CPU",
		Name = "The Core",
		Component = "Processeur",
		AppSection = "Optimisations",
		Primary = "F6E05E",
		Secondary = "FBD38D",
		Tint = "FFFBEA",
		Traps = { "Laser", "Heat", "Mover" },
		Minigame = "Scan",
		Intro = "Le processeur surchauffe ! Lasers et bouches de chaleur partout. Observe avant de courir.",
	},
	{
		Index = 6,
		Id = "GPU",
		Name = "Render Canyon",
		Component = "Carte graphique",
		AppSection = "Gaming",
		Primary = "48BB78",
		Secondary = "ED64A6",
		Tint = "F0FFF4",
		Traps = { "SpinBar", "Laser", "Zapper" },
		Minigame = "Memory",
		Intro = "Les ventilateurs de la carte graphique tournent à fond. Passe entre les pales !",
	},
	{
		Index = 7,
		Id = "AI",
		Name = "Neural Nexus",
		Component = "Puce IA",
		AppSection = "Réseau",
		Primary = "E9D8FD",
		Secondary = "9F7AEA",
		Tint = "FAF5FF",
		Traps = { "Virus", "Laser", "Mover" },
		Minigame = "Firewall",
		Intro = "Le cœur du virus est tout en haut. Évite ses gardes et détruis-le !",
	},
} :: { World }

Tower.WORLD_COUNT = #Tower.Worlds
Tower.TOTAL_STAGES = Tower.WORLD_COUNT * Tower.STAGES_PER_WORLD

-- Monde d'un checkpoint (0 = lobby).
function Tower.WorldOf(stage: number): number
	if stage <= 0 then
		return 0
	end
	return math.min(math.ceil(stage / Tower.STAGES_PER_WORLD), Tower.WORLD_COUNT)
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
