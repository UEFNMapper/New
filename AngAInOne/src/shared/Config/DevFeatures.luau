--!strict
--[[
	DevFeatures : raccourcis du panneau DEV (Studio uniquement) vers chaque nouveauté à tester.
	- World : le joueur est placé dans ce monde, ENCORE INFECTÉ (Cleared = World - 1), au checkpoint
	  `Stage`, puis déplacé en `At` s'il est donné (pieds + 3 studs). Côté serveur : DevService.
	- Epreuve : salle du terminal du monde (checkpoint TerminalStage, monde encore infecté), devant la
	  borne ; le client lance l'épreuve juste après (DevPanel).
	- Client : action faite par le client seul (lobby, menu, mini-jeu sans récompense) : DevPanel.
]]

export type Feature = {
	Label: string,
	World: number?,
	Stage: number?,
	At: Vector3?,
	Epreuve: boolean?, -- épreuve de la salle du terminal : borne + lancement automatique
	Client: string?,
}

local DevFeatures = {}

DevFeatures.List = table.freeze({
	-- Épreuves 3D des salles du terminal : téléport devant la borne, monde encore infecté, épreuve lancée
	{ Label = "Épreuve 1 · Démarrage infecté", World = 1, Epreuve = true },
	{ Label = "Épreuve 2 · RAM saturée", World = 2, Epreuve = true },
	{ Label = "Épreuve 3 · Bloatware", World = 3, Epreuve = true },
	{ Label = "Épreuve 4 · Surchauffe", World = 4, Epreuve = true },
	{ Label = "Épreuve 5 · Défense du CPU", World = 5, Epreuve = true },
	{ Label = "Épreuve 6 · Pilote GPU + écran", World = 6, Epreuve = true },
	{ Label = "Épreuve 7 · Enquête (sans le boss)", Client = "Investigation" },
	-- Parcours
	{ Label = "Parcours : RAM + boutons (M2)", World = 2, Stage = 6, At = Vector3.new(91, 113, -74) },
	{ Label = "Parcours : chaleur + ventilo (M4)", World = 4, Stage = 16, At = Vector3.new(-63, 318, 8) },
	{ Label = "Parcours : ventilo propulseur (M4)", World = 4, Stage = 17, At = Vector3.new(24, 335, -8) },
	{ Label = "Parcours : processus en fond (M5)", World = 5, Stage = 21, At = Vector3.new(-16, 416, -88) },
	{ Label = "Parcours : artefacts GPU (M6)", World = 6, Stage = 26 },
	-- Lobby et divers
	{ Label = "Étape 0 : l'intrusion + intro", Client = "Intrusion" },
	{ Label = "BIOS caché (dedans)", Client = "Bios" },
	{ Label = "Touche Suppr (lobby)", Client = "BiosKey" },
	{ Label = "Stream Deck (lobby)", Client = "Deck" },
	{ Label = "Arcade : Tri des fichiers", Client = "PlayTri" },
	{ Label = "Arcade : Défense du CPU (2D)", Client = "PlayDefense" },
	{ Label = "Menu : Rôle d'équipe", Client = "Roles" },
	{ Label = "RAM à 90 % (monde 2)", Client = "Ram90" },
	{ Label = "Chaleur à 90 °C (monde 4)", Client = "Heat90" },
} :: { Feature })

return DevFeatures
