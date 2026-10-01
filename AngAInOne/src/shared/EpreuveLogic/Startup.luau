--!strict
--[[
	Startup : règles de l'épreuve du monde 1, « Le Démarrage infecté » (étape 1 du guide).
	Un couloir de portes : chaque porte = un programme qui se lance au démarrage, avec son éditeur et
	son impact (comme la page Démarrage de l'app). Deux intrus à l'éditeur inconnu : couper leur levier.
	Couper le levier d'un programme vérifié n'est pas grave (il marche toujours si on le lance soi-même) :
	l'assistant donne un indice, l'erreur est comptée.
]]

local Startup = {}

export type Door = {
	Id: string,
	Name: string,
	Editor: string, -- « Vérifié » / « Inconnu »
	Impact: string, -- « Faible » / « Moyen » / « Élevé »
	Culprit: boolean?,
	Hint: string, -- ce que dit l'assistant quand on actionne ce levier
}

-- Ordre = emplacement dans le couloir (portes 1..3 côté gauche, 4..6 côté droit).
Startup.DOORS = table.freeze({
	{
		Id = "chat",
		Name = "Chat vocal",
		Editor = "Vérifié",
		Impact = "Moyen",
		Hint = "Éditeur vérifié : il peut rester. Cherche un éditeur inconnu.",
	},
	{
		Id = "ram",
		Name = "RAM_download_2go.exe",
		Editor = "Inconnu",
		Impact = "Élevé",
		Culprit = true,
		Hint = "Télécharger de la RAM, ça n'existe pas. Coupé !",
	},
	{
		Id = "launcher",
		Name = "Lanceur de jeux",
		Editor = "Vérifié",
		Impact = "Élevé",
		Hint = "Lourd au démarrage, mais vérifié : ce n'est pas un intrus.",
	},
	{
		Id = "audio",
		Name = "Pilote audio",
		Editor = "Vérifié",
		Impact = "Faible",
		Hint = "Un pilote vérifié : laisse-le, ton son en a besoin.",
	},
	{
		Id = "cloud",
		Name = "Sync cloud",
		Editor = "Vérifié",
		Impact = "Moyen",
		Hint = "Vérifié. Tu peux le couper un jour, mais ce n'est pas LAGZ.",
	},
	{
		Id = "robux",
		Name = "free_robux_generator.exe",
		Editor = "Inconnu",
		Impact = "Élevé",
		Culprit = true,
		Hint = "Des Robux gratuits ? C'est le fichier qui a tout déclenché. Coupé !",
	},
} :: { Door })

Startup.CULPRITS = 0
for _, door in Startup.DOORS do
	if door.Culprit then
		Startup.CULPRITS += 1
	end
end

export type Result = "Culprit" | "Legit" | "Already" | "Unknown"

export type State = {
	Disabled: { [string]: boolean },
	Found: number,
	Mistakes: number,
	Done: boolean,
}

function Startup.new(): State
	return { Disabled = {}, Found = 0, Mistakes = 0, Done = false }
end

function Startup.Door(id: string): Door?
	for _, door in Startup.DOORS do
		if door.Id == id then
			return door
		end
	end
	return nil
end

-- Actionne le levier de la porte `id`. Un levier d'intrus reste coupé ; celui d'un programme vérifié
-- revient en place (erreur comptée).
function Startup.Toggle(state: State, id: string): Result
	local door = Startup.Door(id)
	if not door or state.Done then
		return "Unknown"
	end
	if state.Disabled[id] then
		return "Already"
	end
	if not door.Culprit then
		state.Mistakes += 1
		return "Legit"
	end
	state.Disabled[id] = true
	state.Found += 1
	if state.Found >= Startup.CULPRITS then
		state.Done = true
	end
	return "Culprit"
end

-- Score : 100 sans erreur, −15 par levier inutile (au moins 40).
function Startup.Score(state: State): number
	return math.max(40, 100 - 15 * state.Mistakes)
end

return table.freeze(Startup)
