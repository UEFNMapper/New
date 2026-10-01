--!strict
--[[
	Roles : les quatre rôles « coop » de l'équipe anti-lag (idée du guide AngAInOne), version légère.
	Chacun a UN passif, choisi dans le menu (page Rôle) et sauvegardé (PlayerData.Role). Aucun n'est
	obligatoire : sans rôle, rien ne change. Les passifs ne rendent jamais une ascension « assistée ».
	- Technicien : les jauges RAM (monde 2) et chaleur (monde 4) montent 25 % moins vite (client).
	- Nettoyeur : +10 % de Bits à chaque terminal antivirus réussi (serveur, MinigameService).
	- Enquêteur : les enquêtes et les bloatware désinstallés rapportent le double (serveur, PuzzleService).
	- Service : +1 Bit par checkpoint atteint (serveur, ProgressService) : « avez-vous essayé de redémarrer ? »
]]

export type Role = {
	Id: string,
	Name: string,
	Icon: string, -- UI/Components/Icon
	Passive: string, -- une phrase, affichée dans le menu
	Line: string, -- ce que dit Anga quand on le choisit
}

local Roles = {}

Roles.List = table.freeze({
	table.freeze({
		Id = "Technicien",
		Name = "Technicien",
		Icon = "Cpu",
		Passive = "Les jauges RAM (monde 2) et chaleur (monde 4) montent 25 % moins vite.",
		Line = "Technicien : tu gères la machine. Pense à faire des pauses à l'ombre des ventilos.",
	}),
	table.freeze({
		Id = "Nettoyeur",
		Name = "Nettoyeur",
		Icon = "Check",
		Passive = "+10 % de Bits à chaque terminal antivirus nettoyé.",
		Line = "Nettoyeur : chaque terminal te paie un peu plus. Un PC propre, c'est un PC rapide.",
	}),
	table.freeze({
		Id = "Enqueteur",
		Name = "Enquêteur",
		Icon = "Star",
		Passive = "Les enquêtes (mondes 1 et 7) et les bloatware désinstallés rapportent le double.",
		Line = "Enquêteur : regarde l'éditeur, l'impact, et qui a lancé quoi. Le coupable se cache toujours.",
	}),
	table.freeze({
		Id = "Service",
		Name = "Service",
		Icon = "Heart",
		Passive = "+1 Bit à chaque checkpoint atteint.",
		Line = "Service : vous avez essayé de redémarrer ? Oui ? Alors chaque checkpoint te paie un Bit.",
	}),
})

Roles.ById = {} :: { [string]: Role }
for _, role in Roles.List do
	Roles.ById[role.Id] = role
end
table.freeze(Roles.ById)

Roles.GAUGE_FACTOR = 0.75 -- Technicien : vitesse de remplissage des jauges
Roles.CLEAN_BONUS = 0.1 -- Nettoyeur : part de Bits en plus sur un terminal
Roles.INVESTIGATE_FACTOR = 2 -- Enquêteur : multiplicateur des enquêtes et désinstallations
Roles.CHECKPOINT_BITS = 1 -- Service : Bits par checkpoint

-- Facteur appliqué à la vitesse des jauges pour un rôle (1 = normal).
function Roles.GaugeFactor(role: string?): number
	return if role == "Technicien" then Roles.GAUGE_FACTOR else 1
end

-- Facteur appliqué aux Bits d'un terminal antivirus.
function Roles.CleanFactor(role: string?): number
	return if role == "Nettoyeur" then 1 + Roles.CLEAN_BONUS else 1
end

-- Facteur appliqué aux Bits d'une enquête ou d'une désinstallation.
function Roles.InvestigateFactor(role: string?): number
	return if role == "Enqueteur" then Roles.INVESTIGATE_FACTOR else 1
end

-- Bits en plus à chaque checkpoint.
function Roles.CheckpointBits(role: string?): number
	return if role == "Service" then Roles.CHECKPOINT_BITS else 0
end

function Roles.IsValid(id: any): boolean
	return type(id) == "string" and Roles.ById[id] ~= nil
end

return table.freeze(Roles)
