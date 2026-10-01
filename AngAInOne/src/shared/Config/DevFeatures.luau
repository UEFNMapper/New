--!strict
--[[
	DevFeatures : raccourcis du panneau DEV (Studio uniquement) vers chaque nouveauté à tester.
	- World : le joueur est placé dans ce monde, ENCORE INFECTÉ (Cleared = World - 1), au checkpoint
	  `Stage`, puis déplacé en `At` s'il est donné (pieds + 3 studs). Côté serveur : DevService.
	- Client : action faite par le client seul (lobby, menu, mini-jeu sans récompense) : DevPanel.
]]

export type Feature = {
	Label: string,
	World: number?,
	Stage: number?,
	At: Vector3?,
	Client: string?,
}

local DevFeatures = {}

DevFeatures.List = table.freeze({
	{ Label = "Enquête Démarrage (M1)", World = 1, Stage = 5 },
	{ Label = "RAM + boutons (M2)", World = 2, Stage = 6, At = Vector3.new(91, 113, -74) },
	{ Label = "Chaleur + ventilo à relancer (M4)", World = 4, Stage = 16, At = Vector3.new(-63, 318, 8) },
	{ Label = "Ventilo propulseur (M4)", World = 4, Stage = 17, At = Vector3.new(24, 335, -8) },
	{ Label = "Bloatware (M5)", World = 5, Stage = 21, At = Vector3.new(-16, 416, -88) },
	{ Label = "Terminal Tri des fichiers (M5)", World = 5, Stage = 25 },
	{ Label = "Artefacts GPU (M6)", World = 6, Stage = 26 },
	{ Label = "Enquête Sessions de jeu (M7)", World = 7, Stage = 35 },
	{ Label = "BIOS caché (dedans)", Client = "Bios" },
	{ Label = "Touche Suppr (lobby)", Client = "BiosKey" },
	{ Label = "Stream Deck (lobby)", Client = "Deck" },
	{ Label = "Jouer : Tri des fichiers", Client = "PlayTri" },
	{ Label = "Jouer : Défense du CPU", Client = "PlayDefense" },
	{ Label = "Menu : Rôle d'équipe", Client = "Roles" },
	{ Label = "RAM à 90 % (monde 2)", Client = "Ram90" },
	{ Label = "Chaleur à 90 °C (monde 4)", Client = "Heat90" },
} :: { Feature })

return DevFeatures
