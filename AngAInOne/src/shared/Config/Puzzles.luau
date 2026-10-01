--!strict
--[[
	Puzzles : les deux « enquêtes » 3D de l'ascension, calquées sur deux pages de l'app AngAInOne.
	Chaque enquête est une rangée de panneaux dans la salle du terminal du monde ; un seul est le
	coupable, et on le désigne avec le levier (ou le bouton Quarantaine) de son panneau. Le serveur
	(PuzzleService) vérifie la réponse et récompense une fois pour toujours.

	- Monde 1 · le Démarrage infecté : la page Démarrage de l'app liste ce qui se lance au boot, avec
	  l'impact et l'éditeur. Le programme à désactiver est celui qui n'a rien à faire là.
	- Monde 7 · l'enquête des Sessions de jeu : l'app nomme le programme qui a fait ramer la partie et
	  sa chaîne de parents (qui l'a lancé). On remonte la chaîne jusqu'au vrai coupable.
]]

export type Item = {
	Id: string,
	Name: string,
	Lines: { string }, -- lignes affichées sous le nom (impact, éditeur, parent…)
	Culprit: boolean?,
	Hint: string?, -- ce que dit l'assistant si on se trompe sur ce panneau
}

export type Puzzle = {
	World: number,
	Title: string,
	Subtitle: string,
	Action: string, -- texte du prompt
	Bits: number, -- récompense (une fois pour toujours)
	Intro: string, -- ce que dit l'assistant quand on approche
	Success: string, -- ce que dit l'assistant quand on a trouvé
	Items: { Item },
}

local Puzzles = {}

Puzzles.List = table.freeze({
	table.freeze({
		World = 1,
		Title = "DÉMARRAGE",
		Subtitle = "Ce qui se lance avec Windows",
		Action = "Désactiver",
		Bits = 25,
		Intro = "La page Démarrage : un interrupteur par programme. Lequel n'a rien à faire là ?",
		Success = "Désactivé ! C'est par là que LAGZ s'était faufilé. Pense à vérifier ton vrai Démarrage.",
		Items = table.freeze({
			{
				Id = "chat",
				Name = "Chat vocal",
				Lines = { "Impact : moyen", "Éditeur : vérifié" },
				Hint = "Utile et vérifié : il peut rester, ou se désactiver sans risque. Ce n'est pas lui.",
			},
			{
				Id = "launcher",
				Name = "Lanceur de jeux",
				Lines = { "Impact : élevé", "Éditeur : vérifié" },
				Hint = "Lourd au démarrage, mais vérifié. Pas lui.",
			},
			{
				Id = "audio",
				Name = "Pilote audio",
				Lines = { "Impact : faible", "Éditeur : vérifié" },
				Hint = "Un pilote : laisse-le tranquille.",
			},
			{
				Id = "virus",
				Name = "RAM_download_2go.exe",
				Lines = { "Impact : élevé", "Éditeur : inconnu" },
				Culprit = true,
			},
			{
				Id = "cloud",
				Name = "Sync cloud",
				Lines = { "Impact : moyen", "Éditeur : vérifié" },
				Hint = "Vérifié. Tu peux le désactiver chez toi, mais ce n'est pas le virus.",
			},
		} :: { Item }),
	}),
	table.freeze({
		World = 7,
		Title = "SESSIONS DE JEU",
		Subtitle = "D'où viennent les accrocs",
		Action = "Quarantaine",
		Bits = 40,
		Intro = "Pic de lag à 14:03. L'app a nommé le coupable… et qui l'a lancé. Remonte la chaîne !",
		Success = "Trouvé ! Mis en quarantaine. Le vrai coupable se cache toujours derrière un programme innocent.",
		Items = table.freeze({
			{
				Id = "browser",
				Name = "navigateur.exe (12 onglets)",
				Lines = { "Accrocs : 14:03", "Lancé par : updater.exe" },
				Hint = "Il ramait, oui, mais regarde qui l'a lancé.",
			},
			{
				Id = "updater",
				Name = "updater.exe",
				Lines = { "Mise à jour ?", "Lancé par : helper_svc.exe" },
				Hint = "Un relais. Qui l'a lancé, lui ?",
			},
			{
				Id = "helper",
				Name = "helper_svc.exe",
				Lines = { "Service inconnu", "Lancé par : lagz_miner.exe" },
				Hint = "Presque : encore un cran au-dessus.",
			},
			{
				Id = "miner",
				Name = "lagz_miner.exe",
				Lines = { "CPU : 100 %", "Lancé par : explorer.exe" },
				Culprit = true,
			},
			{
				Id = "explorer",
				Name = "explorer.exe",
				Lines = { "Le bureau Windows", "Lancé par : toi" },
				Hint = "C'est Windows lui-même : il lance tout, il n'est coupable de rien.",
			},
			{
				Id = "music",
				Name = "musique.exe",
				Lines = { "Accrocs : aucun", "Lancé par : explorer.exe" },
				Hint = "Il jouait de la musique, c'est tout.",
			},
		} :: { Item }),
	}),
} :: { Puzzle })

-- L'enquête d'un monde (nil si le monde n'en a pas).
function Puzzles.ForWorld(world: number): Puzzle?
	for _, puzzle in Puzzles.List do
		if puzzle.World == world then
			return puzzle
		end
	end
	return nil
end

-- L'élément désigné, et s'il est le coupable.
function Puzzles.Check(world: number, itemId: string): (boolean, Item?)
	local puzzle = Puzzles.ForWorld(world)
	if not puzzle then
		return false, nil
	end
	for _, item in puzzle.Items do
		if item.Id == itemId then
			return item.Culprit == true, item
		end
	end
	return false, nil
end

return Puzzles
