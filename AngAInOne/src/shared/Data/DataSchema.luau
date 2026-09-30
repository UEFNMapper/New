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
	-- Records
	BestStage: number,
	Wins: number,
	BestTime: number, -- secondes (0 = jamais terminé sans assistance)
	Deaths: number,
	MinigamesWon: number,
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

DataSchema.CURRENT_VERSION = 1
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
		BestStage = 0,
		Wins = 0,
		BestTime = 0,
		Deaths = 0,
		MinigamesWon = 0,
		Cosmetics = { Owned = { "TrailNone", "DeathGlitch" }, Trail = "TrailNone", DeathFx = "DeathGlitch" },
		Toggles = { LowGravity = false, SpeedChip = false },
		Daily = { Streak = 0, LastClaimDay = -1 },
		Missions = { Day = -1, List = {} },
		ArcadeRewardAt = 0,
		Stats = { Playtime = 0, LastOnline = 0, CoinsCollected = 0 },
		UsbKeys = {},
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
end

-- Migrations : MIGRATIONS[v] transforme des données en version v vers v + 1.
local MIGRATIONS: { [number]: (any) -> () } = {
	-- [1] = function(data) data.NouveauChamp = ... end,
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
