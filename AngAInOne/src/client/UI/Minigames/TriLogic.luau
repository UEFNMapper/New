--!strict
--[[
	TriLogic : règles PURES du mini-jeu « Tri des fichiers » (monde 5, testables dans Lune).

	Un fichier arrive à la fois sur le tapis. On le range dans l'un des trois bacs :
	- Garder : les vrais fichiers (photos, devoirs, sauvegardes de jeu, musique) ;
	- Corbeille : doublons (« (2) », « - Copie »), fichiers temporaires (.tmp), caches, vieux journaux ;
	- Quarantaine : programmes déguisés (« photo.jpg.exe », « .scr », « .bat », « robux_gratuits.exe »).
	Bon bac : +1. Mauvais bac, ou fichier qui file au bout du tapis (trop lent) : une vie en moins.
	Un programme déguisé rangé dans « Garder » : deux vies en moins (le pire : on l'a gardé !).
	Gagné à `Target` fichiers bien triés ; perdu à 0 vie ou à la fin du temps.
	Niveaux 1 à 3 : une étiquette d'indice sous le nom (« doublon », « programme ! »).
]]

local Core = require(script.Parent.Core)

local TriLogic = {}

export type Bin = "Keep" | "Trash" | "Quarantine"

local BINS: { Bin } = { "Keep" :: Bin, "Trash" :: Bin, "Quarantine" :: Bin }
TriLogic.BINS = table.freeze(BINS)

export type Params = {
	Target: number, -- fichiers à bien trier
	Duration: number, -- secondes
	Lifetime: number, -- secondes avant que le fichier file au bout du tapis
	Gap: number, -- secondes entre deux fichiers
	VirusChance: number, -- probabilité d'un programme déguisé
	TrashChance: number, -- probabilité d'un fichier inutile
	Lives: number,
	Hints: boolean, -- étiquette d'indice sous le nom
}

local ROWS: { Params } = {
	{
		Target = 10,
		Duration = 45,
		Lifetime = 5.0,
		Gap = 0.35,
		VirusChance = 0.25,
		TrashChance = 0.35,
		Lives = 3,
		Hints = true,
	},
	{
		Target = 11,
		Duration = 45,
		Lifetime = 4.5,
		Gap = 0.35,
		VirusChance = 0.28,
		TrashChance = 0.35,
		Lives = 3,
		Hints = true,
	},
	{
		Target = 12,
		Duration = 45,
		Lifetime = 4.0,
		Gap = 0.3,
		VirusChance = 0.3,
		TrashChance = 0.36,
		Lives = 3,
		Hints = true,
	},
	{
		Target = 13,
		Duration = 42,
		Lifetime = 3.6,
		Gap = 0.3,
		VirusChance = 0.32,
		TrashChance = 0.36,
		Lives = 3,
		Hints = false,
	},
	{
		Target = 14,
		Duration = 40,
		Lifetime = 3.2,
		Gap = 0.28,
		VirusChance = 0.34,
		TrashChance = 0.36,
		Lives = 3,
		Hints = false,
	},
	{
		Target = 15,
		Duration = 40,
		Lifetime = 2.9,
		Gap = 0.25,
		VirusChance = 0.35,
		TrashChance = 0.36,
		Lives = 3,
		Hints = false,
	},
	{
		Target = 16,
		Duration = 38,
		Lifetime = 2.6,
		Gap = 0.25,
		VirusChance = 0.36,
		TrashChance = 0.36,
		Lives = 3,
		Hints = false,
	},
}

TriLogic.FIRST_SPAWN = 0.6
TriLogic.VIRUS_KEPT_PENALTY = 2

-- Fichiers par bac : nom affiché, indice (niveaux 1 à 3), explication en cas d'erreur.
export type FileDef = { Name: string, Hint: string }

TriLogic.FILES = table.freeze({
	Keep = table.freeze({
		{ Name = "photo_vacances.jpg", Hint = "ta photo" },
		{ Name = "devoir_maths.docx", Hint = "ton devoir" },
		{ Name = "sauvegarde_jeu.sav", Hint = "ta partie" },
		{ Name = "dessin_dragon.png", Hint = "ton dessin" },
		{ Name = "exposé_volcans.pptx", Hint = "ton exposé" },
		{ Name = "musique_préférée.mp3", Hint = "ta musique" },
		{ Name = "vidéo_anniversaire.mp4", Hint = "ta vidéo" },
		{ Name = "lettre_mamie.pdf", Hint = "ta lettre" },
	}),
	Trash = table.freeze({
		{ Name = "photo_vacances (2).jpg", Hint = "doublon" },
		{ Name = "devoir_maths - Copie.docx", Hint = "doublon" },
		{ Name = "~tmp4821.tmp", Hint = "temporaire" },
		{ Name = "cache_navigateur.dat", Hint = "cache" },
		{ Name = "vieil_installateur.zip", Hint = "déjà installé" },
		{ Name = "journal_erreurs.log", Hint = "vieux journal" },
		{ Name = "Nouveau dossier (7)", Hint = "dossier vide" },
		{ Name = "miniatures.db", Hint = "cache" },
	}),
	Quarantine = table.freeze({
		{ Name = "photo_vacances.jpg.exe", Hint = "programme !" },
		{ Name = "devoir.pdf.scr", Hint = "programme !" },
		{ Name = "skin_gratuit.bat", Hint = "programme !" },
		{ Name = "robux_gratuits.exe", Hint = "arnaque !" },
		{ Name = "jeu_crack.exe", Hint = "programme !" },
		{ Name = "RAM_download_2go.exe", Hint = "arnaque !" },
		{ Name = "lagz_miner.exe", Hint = "mineur !" },
		{ Name = "mise_a_jour_urgente.vbs", Hint = "programme !" },
	}),
})

-- Ce que dit le jeu quand on se trompe, selon le bon bac.
TriLogic.WHY = table.freeze({
	Keep = "C'était un vrai fichier : on le garde !",
	Trash = "Doublon ou fichier temporaire : à la corbeille.",
	Quarantine = "Programme déguisé (.exe, .scr, .bat) : quarantaine !",
})

export type File = { Id: number, Kind: Bin, Name: string, Hint: string, Born: number, Expires: number }

export type Event = {
	Kind: "Spawn" | "Sorted" | "Miss" | "Win" | "Lose" | "Timeout",
	File: File?,
	Bin: Bin?,
	Ok: boolean?,
	Penalty: number?,
}

export type State = {
	Params: Params,
	Rng: Core.Rng,
	Time: number,
	NextAt: number,
	Current: File?,
	Sorted: number,
	Lives: number,
	Mistakes: number,
	Spawned: number,
	History: { Bin },
	LastName: string,
	Done: boolean,
	Success: boolean,
}

function TriLogic.Params(difficulty: number): Params
	return Core.Row(ROWS, difficulty)
end

function TriLogic.new(difficulty: number, seed: number): State
	local p = TriLogic.Params(difficulty)
	return {
		Params = p,
		Rng = Core.Rng(seed),
		Time = 0,
		NextAt = TriLogic.FIRST_SPAWN,
		Current = nil,
		Sorted = 0,
		Lives = p.Lives,
		Mistakes = 0,
		Spawned = 0,
		History = {},
		LastName = "",
		Done = false,
		Success = false,
	}
end

function TriLogic.TimeLeft(sim: State): number
	return math.max(0, sim.Params.Duration - sim.Time)
end

local function pickKind(sim: State): Bin
	local p = sim.Params
	local roll = sim.Rng:Next()
	local kind: Bin = if roll < p.VirusChance
		then "Quarantine" :: Bin
		elseif roll < p.VirusChance + p.TrashChance then "Trash" :: Bin
		else "Keep" :: Bin
	-- Jamais trois fois le même bac de suite (sinon le tri devient un réflexe).
	local n = #sim.History
	if n >= 2 and sim.History[n] == kind and sim.History[n - 1] == kind then
		local others: { Bin } = {}
		for _, bin in TriLogic.BINS do
			if bin ~= kind then
				table.insert(others, bin)
			end
		end
		kind = others[sim.Rng:Int(1, #others)]
	end
	return kind
end

local function spawn(sim: State): File
	local kind = pickKind(sim)
	local list = (TriLogic.FILES :: any)[kind] :: { FileDef }
	local def = list[sim.Rng:Int(1, #list)]
	if def.Name == sim.LastName then
		def = list[(table.find(list, def) :: number) % #list + 1]
	end
	sim.Spawned += 1
	table.insert(sim.History, kind)
	sim.LastName = def.Name
	local file: File = {
		Id = sim.Spawned,
		Kind = kind :: Bin,
		Name = def.Name,
		Hint = def.Hint,
		Born = sim.Time,
		Expires = sim.Time + sim.Params.Lifetime,
	}
	sim.Current = file
	return file
end

local function lose(sim: State, events: { Event }, amount: number)
	sim.Lives = math.max(0, sim.Lives - amount)
	sim.Mistakes += 1
	if sim.Lives <= 0 then
		sim.Done = true
		sim.Success = false
		table.insert(events, { Kind = "Lose" })
	end
end

-- Avance la partie de `dt` secondes. Renvoie les événements survenus, dans l'ordre.
function TriLogic.Step(sim: State, dt: number): { Event }
	local events: { Event } = {}
	if sim.Done then
		return events
	end
	sim.Time += math.clamp(dt, 0, Core.MAX_STEP)
	if sim.Time >= sim.Params.Duration then
		sim.Done = true
		sim.Success = false
		table.insert(events, { Kind = "Timeout" })
		return events
	end
	local current = sim.Current
	if current and sim.Time >= current.Expires then
		sim.Current = nil
		sim.NextAt = sim.Time + sim.Params.Gap
		table.insert(events, { Kind = "Miss", File = current })
		lose(sim, events, 1)
		if sim.Done then
			return events
		end
	end
	if not sim.Current and sim.Time >= sim.NextAt then
		table.insert(events, { Kind = "Spawn", File = spawn(sim) })
	end
	return events
end

-- Range le fichier courant dans `bin`. Renvoie les événements (Sorted, puis Win / Lose).
function TriLogic.Sort(sim: State, bin: Bin): { Event }
	local events: { Event } = {}
	local current = sim.Current
	if sim.Done or not current then
		return events
	end
	sim.Current = nil
	sim.NextAt = sim.Time + sim.Params.Gap
	if bin == current.Kind then
		sim.Sorted += 1
		table.insert(events, { Kind = "Sorted", File = current, Bin = bin, Ok = true })
		if sim.Sorted >= sim.Params.Target then
			sim.Done = true
			sim.Success = true
			table.insert(events, { Kind = "Win" })
		end
		return events
	end
	local penalty = if current.Kind == "Quarantine" and bin == "Keep" then TriLogic.VIRUS_KEPT_PENALTY else 1
	table.insert(events, { Kind = "Sorted", File = current, Bin = bin, Ok = false, Penalty = penalty })
	lose(sim, events, penalty)
	return events
end

return table.freeze(TriLogic)
