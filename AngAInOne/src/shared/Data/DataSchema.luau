--!strict
--[[
	DataSchema : forme des données sauvegardées d'un joueur + migrations versionnées.

	Règles ProfileStore : pas d'Instances, pas de userdata (Color3, Vector3…),
	pas de tableaux à trous, clés de dictionnaire en string uniquement.

	Pour faire évoluer le schéma :
	1. incrémente CURRENT_VERSION ;
	2. ajoute une fonction dans MIGRATIONS[ancienneVersion] qui transforme les données ;
	3. ajoute un test dans tests/shared.spec.luau.
]]

export type MissionState = {
	Id: string,
	Target: number,
	Progress: number,
	Claimed: boolean,
}

-- Meilleur résultat d'un monde (clé "W{n}") : médaille la plus haute + meilleur temps sans aide.
export type WorldBest = {
	Time: number, -- secondes (0 = aucun temps sans aide)
	Medal: string, -- "Bronze" | "Silver" | "Gold" ("" = aucune)
}

-- Chrono du monde en cours pour les médailles (voir Util/MedalLogic et Config/Medals).
export type RunSplit = {
	World: number, -- monde chronométré (0 = aucun)
	Start: number, -- RunElapsed à l'entrée du monde
	Deaths: number, -- morts dans ce monde
	Keys: number, -- clés USB trouvées dans ce monde pendant ce passage
	Assisted: boolean, -- étape passée, bouclier ou passe avantage pendant ce monde : pas de record
}

export type PlayerData = {
	Version: number,
	Bits: number,
	TotalBits: number,
	-- Ascension en cours (sauvegardée : on reprend où on en était)
	Stage: number, -- checkpoint actuel (0 = lobby, 1..Tower.TOTAL_STAGES)
	Cleared: number, -- dernier monde dont le terminal antivirus est réussi (0..7)
	RunElapsed: number, -- secondes d'ascension (chrono, hors temps de déconnexion)
	RunStarted: boolean, -- le chrono tourne (départ franchi)
	RunAssisted: boolean, -- passe « avantage » ou saut d'étape utilisé : hors classement des temps
	RunCoins: { [string]: boolean }, -- orbes déjà ramassées pendant cette ascension
	RunSplit: RunSplit, -- chrono du monde en cours (médailles), redémarré au départ et à chaque monde
	RunDeaths: number, -- chutes pendant cette ascension (rapport de fin)
	-- Records
	BestStage: number,
	Wins: number,
	BestTime: number, -- secondes (0 = jamais terminé sans assistance)
	Deaths: number,
	MinigamesWon: number,
	WorldBest: { [string]: WorldBest }, -- médailles et records par monde ("W1".."W7")
	Cosmetics: {
		Owned: { string },
		Trail: string,
		DeathFx: string,
	},
	Toggles: {
		LowGravity: boolean,
		SpeedChip: boolean,
	},
	Daily: {
		Streak: number,
		LastClaimDay: number,
	},
	Missions: {
		Day: number,
		List: { MissionState },
	},
	ArcadeRewardAt: number, -- os.time de la dernière récompense d'arcade
	Stats: {
		Playtime: number,
		LastOnline: number,
		CoinsCollected: number,
	},
	UsbKeys: { [string]: boolean }, -- clés USB dorées trouvées (KeyId "W{n}K{i}"), pour toujours
	-- Enquêtes résolues ("W1", "W7") et bloatware désinstallés ("W5U1".."W5U3"), pour toujours
	Puzzles: { [string]: boolean },
	Role: string, -- rôle coop (Config/Roles), "" = aucun
	IntroSeen: boolean,
	Settings: {
		Music: number,
		Sfx: number,
		ReducedMotion: boolean,
	},
	Receipts: { string },
	CreatedAt: number,
}

local DataSchema = {}

DataSchema.CURRENT_VERSION = 2
DataSchema.MAX_RECEIPTS = 50

function DataSchema.Template(): PlayerData
	return {
		Version = DataSchema.CURRENT_VERSION,
		Bits = 0,
		TotalBits = 0,
		Stage = 0,
		Cleared = 0,
		RunElapsed = 0,
		RunStarted = false,
		RunAssisted = false,
		RunCoins = {},
		RunSplit = { World = 0, Start = 0, Deaths = 0, Keys = 0, Assisted = false },
		RunDeaths = 0,
		BestStage = 0,
		Wins = 0,
		BestTime = 0,
		Deaths = 0,
		MinigamesWon = 0,
		WorldBest = {},
		Cosmetics = { Owned = { "TrailNone", "DeathGlitch" }, Trail = "TrailNone", DeathFx = "DeathGlitch" },
		Toggles = { LowGravity = false, SpeedChip = false },
		Daily = { Streak = 0, LastClaimDay = -1 },
		Missions = { Day = -1, List = {} },
		ArcadeRewardAt = 0,
		Stats = { Playtime = 0, LastOnline = 0, CoinsCollected = 0 },
		UsbKeys = {},
		Puzzles = {},
		Role = "",
		IntroSeen = false,
		Settings = { Music = 0.35, Sfx = 0.7, ReducedMotion = false },
		Receipts = {},
		CreatedAt = 0,
	}
end

-- Remet à zéro l'ascension en cours (après une victoire).
function DataSchema.ResetRun(data: PlayerData)
	data.Stage = 0
	data.Cleared = 0
	data.RunElapsed = 0
	data.RunStarted = false
	data.RunAssisted = false
	data.RunCoins = {}
	data.RunDeaths = 0
end

-- Migrations : MIGRATIONS[v] transforme des données en version v vers v + 1.
local MIGRATIONS: { [number]: (any) -> () } = {
	-- v1 -> v2 (médailles par monde) : WorldBest et RunSplit. Les valeurs par défaut viennent du
	-- modèle (reconcile, juste après) ; on retire seulement une valeur d'un mauvais type.
	[1] = function(data)
		if type(data.WorldBest) ~= "table" then
			data.WorldBest = nil
		end
		if type(data.RunSplit) ~= "table" then
			data.RunSplit = nil
		end
	end,
}

-- Complète récursivement les clés manquantes à partir du modèle (sans écraser l'existant).
local function reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = if type(value) == "table" then table.clone(value) else value
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			-- Ne descend que dans les "objets" du modèle (pas dans les listes/dicos vides).
			reconcile(target[key], value)
		end
	end
end

-- Migre puis complète des données chargées. Renvoie false si la version est plus récente
-- que ce serveur (ancien serveur encore en ligne) : il ne faut alors pas les modifier.
function DataSchema.Migrate(data: { [string]: any }): boolean
	local version = if type(data.Version) == "number" then data.Version else 0
	if version > DataSchema.CURRENT_VERSION then
		return false
	end
	if version == 0 then
		version = 1
	end
	while version < DataSchema.CURRENT_VERSION do
		local migrate = MIGRATIONS[version]
		if migrate then
			migrate(data)
		end
		version += 1
	end
	data.Version = version
	reconcile(data, DataSchema.Template() :: any)
	return true
end

-- Ajoute un PurchaseId à l'historique borné des reçus traités.
function DataSchema.AddReceipt(data: PlayerData, purchaseId: string)
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > DataSchema.MAX_RECEIPTS do
		table.remove(data.Receipts, 1)
	end
end

function DataSchema.HasReceipt(data: PlayerData, purchaseId: string): boolean
	return table.find(data.Receipts, purchaseId) ~= nil
end

return table.freeze(DataSchema)
