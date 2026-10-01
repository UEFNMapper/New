--!strict
--[[
	Epreuves : l'épreuve 3D de chaque monde, jouée dans la salle du terminal, d'après le guide
	« AngAinOne × Roblox » (une étape = une vraie zone du PC + la vraie page de l'app qui la règle).

	Déroulé : on arrive dans la salle → fiche de l'épreuve au format du Diagnostic de l'app
	(Constat / Pourquoi / Quoi faire) → « Lancer » sur la borne AngAInOne → l'épreuve se joue dans la
	salle (client, World/Tower/Epreuves pour le décor, Controllers/Epreuves pour le jeu) → réussie,
	le serveur nettoie le monde (MinigameService, mêmes contrôles qu'un mini-jeu : départ près de la
	borne, durée minimale `MinSeconds`), le portail s'ouvre.

	Monde 7 : l'Enquête se joue AVANT la phase finale du combat contre LAGZ (le Firewall boss) :
	elle désigne le coupable, que l'on met en quarantaine.
]]

export type Fiche = {
	Constat: string,
	Pourquoi: string,
	QuoiFaire: string,
}

export type Epreuve = {
	World: number,
	Kind: string, -- Controllers/EpreuveKinds/<Kind>
	Name: string, -- « Le Démarrage infecté »
	Step: string, -- étape du guide (« Étape 1 »)
	Page: string, -- page de l'app qui règle le problème
	Fiche: Fiche,
	Steps: { string }, -- liste à cocher (HUD + panneau de la salle)
	Start: string, -- texte du prompt de la borne
	Done: string, -- ce que dit l'assistant à la fin
	MinSeconds: number, -- durée minimale acceptée par le serveur
}

local Epreuves = {}

local LIST: { Epreuve } = {
	{
		World = 1,
		Kind = "Startup",
		Name = "Le Démarrage infecté",
		Step = "Étape 1",
		Page = "Démarrage",
		Fiche = {
			Constat = "Le PC met trois minutes à démarrer, et LAGZ revient à chaque allumage.",
			Pourquoi = "Chaque programme du Démarrage se lance tout seul avec le PC. Deux intrus s'y sont glissés.",
			QuoiFaire = "Lis chaque porte : éditeur et impact. Coupe le levier des deux programmes à l'éditeur inconnu.",
		},
		Steps = { "Lire les portes du Démarrage", "Désactiver les 2 intrus" },
		Start = "Ouvrir le Démarrage",
		Done = "Démarrage nettoyé : le PC s'allume deux fois plus vite, et LAGZ ne revient plus au boot.",
		MinSeconds = 6,
	},
	{
		World = 2,
		Kind = "RamSlots",
		Name = "La RAM saturée",
		Step = "Étape 3",
		Page = "Tableau de bord · Mémoire",
		Fiche = {
			Constat = "Mémoire pleine à 98 %, et les deux barrettes sont en A1 et B1.",
			Pourquoi = "Avec deux barrettes, la carte mère attend A2 + B2 : sinon la RAM tourne deux fois moins vite.",
			QuoiFaire = "Déplace les barrettes en A2 et B2, puis appuie sur « Libérer la RAM » quand la jauge remonte.",
		},
		Steps = { "Barrettes en A2 + B2", "Libérer la RAM (3 fois)" },
		Start = "Ouvrir le Tableau de bord",
		Done = "Double canal activé et mémoire libérée : la RAM respire.",
		MinSeconds = 10,
	},
	{
		World = 3,
		Kind = "Debloat",
		Name = "L'invasion du Bloatware",
		Step = "Étape 2",
		Page = "Optimisations · Debloat",
		Fiche = {
			Constat = "Cinq programmes inutiles, gros et lents, encombrent le disque et tournent en fond.",
			Pourquoi = "Les bloatware s'installent avec d'autres logiciels et mangent place, mémoire et processeur.",
			QuoiFaire = "Approche-toi et maintiens « Debloat » pour les aspirer dans la Corbeille, puis vide-la.",
		},
		Steps = { "Aspirer les bloatware", "Vider la Corbeille" },
		Start = "Lancer le Debloat",
		Done = "Plus un seul bloatware : le disque a retrouvé de la place.",
		MinSeconds = 10,
	},
	{
		World = 4,
		Kind = "Cooling",
		Name = "La surchauffe",
		Step = "Étape 4",
		Page = "Tableau de bord · Températures",
		Fiche = {
			Constat = "Processeur à 97 °C : les ventilateurs sont bouchés et le sol devient de la lave.",
			Pourquoi = "La poussière empêche l'air de passer, et le plan « Performances max » pousse le processeur.",
			QuoiFaire = "Saute de socle en socle, relance les trois ventilateurs, puis passe le plan d'alimentation en « Équilibré ».",
		},
		Steps = { "Relancer les ventilateurs", "Plan d'alimentation : Équilibré" },
		Start = "Ouvrir les températures",
		Done = "45 °C : les ventilateurs soufflent et le processeur ne force plus.",
		MinSeconds = 10,
	},
	{
		World = 5,
		Kind = "CpuDefense",
		Name = "Défense du CPU",
		Step = "Processeur à 100 %",
		Page = "Optimisations",
		Fiche = {
			Constat = "Le processeur est à 100 % : LAGZ envoie des vagues de processus vers lui.",
			Pourquoi = "Chaque processus en trop vole du temps de calcul à ton jeu : c'est ça, le lag.",
			QuoiFaire = "Pose des optimisations (⚡) à côté des bus : elles arrêtent les processus avant le processeur.",
		},
		Steps = { "Poser des optimisations", "Arrêter les processus du virus" },
		Start = "Défendre le processeur",
		Done = "Processeur à 12 % : les processus du virus ne passent plus.",
		MinSeconds = 12,
	},
	{
		World = 6,
		Kind = "Driver",
		Name = "La carte graphique corrompue",
		Step = "Étape 5",
		Page = "Pilotes GPU · Écrans",
		Fiche = {
			Constat = "Artefacts à l'écran, textures qui clignotent : le pilote graphique est corrompu.",
			Pourquoi = "Un pilote abîmé dessine mal l'image. Et l'écran est bridé à 60 Hz sans le savoir.",
			QuoiFaire = "Nettoyage complet de l'ancien pilote, téléchargement, installation, puis la bonne fréquence d'écran.",
		},
		Steps = {
			"Nettoyage complet (ancien pilote)",
			"Télécharger le pilote",
			"Installer : brancher les câbles",
			"Écran : fréquence maximale",
		},
		Start = "Ouvrir Pilotes GPU",
		Done = "Pilote neuf et écran à 170 Hz : l'image est nette et fluide.",
		MinSeconds = 12,
	},
	{
		World = 7,
		Kind = "Investigation",
		Name = "L'enquête des Sessions de jeu",
		Step = "Étape 6",
		Page = "Sessions de jeu",
		Fiche = {
			Constat = "Partie avec quelques accrocs : un pic de lag à 14:03.",
			Pourquoi = "Le virus se cache derrière un programme innocent, qui a été lancé par un autre…",
			QuoiFaire = "Inspecte le programme qui rame, remonte « Lancé par » jusqu'au vrai coupable, mets-le en quarantaine.",
		},
		Steps = { "Inspecter le programme qui rame", "Remonter la chaîne", "Mettre le coupable en quarantaine" },
		Start = "Ouvrir Sessions de jeu",
		Done = "Coupable trouvé : LAGZ.exe. Quarantaine en cours !",
		MinSeconds = 0, -- pas de validation serveur : la phase finale du boss suit
	},
}

Epreuves.List = table.freeze(LIST)

Epreuves.ByWorld = {} :: { [number]: Epreuve }
Epreuves.ByKind = {} :: { [string]: Epreuve }
for _, epreuve in LIST do
	Epreuves.ByWorld[epreuve.World] = epreuve
	Epreuves.ByKind[epreuve.Kind] = epreuve
end
table.freeze(Epreuves.ByWorld)
table.freeze(Epreuves.ByKind)

-- Monde dont l'épreuve remplace le mini-jeu 2D du terminal (1 à 6 ; le 7 garde le Firewall boss).
function Epreuves.ClearsWorld(world: number): boolean
	local epreuve = Epreuves.ByWorld[world]
	return epreuve ~= nil and epreuve.MinSeconds > 0
end

return table.freeze(Epreuves)
