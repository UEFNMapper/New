--!strict
--[[
	DataSchema : forme des données sauvegardées d'un joueur + migrations versionnées.

	Règles ProfileStore : pas d'Instances, pas de userdata (Color3, Vector3…),
	pas de tableaux à trous, clés de dictionnaire en string uniquement.

	Pour faire évoluer le schéma :
	1. incrémente CURRENT_VERSION ;
	2. ajoute une fonction dans MIGRATIONS[ancienneVersion] qui transforme les données ;
	3. ajoute un test dans tests/dataschema.spec.luau.
]]

export type OwnedNanobot = {
	Uid: string,
	Id: string,
	Golden: boolean,
}

export type QuestState = {
	Id: string,
	Target: number,
	Progress: number,
	Claimed: boolean,
}

export type PlayerData = {
	Version: number,
	Bits: number,
	Chips: number,
	Pending: number,
	PoweredOn: boolean,
	Zone: number,
	Levels: { [string]: number },
	PsuLevel: number,
	CoolingLevel: number,
	SingularityPhase: number,
	Firmware: number,
	Generation: number,
	RunBitsEarned: number,
	TotalBitsEarned: number,
	WeeklyBits: number,
	WeeklyIndex: number,
	Singularities: number,
	RebootBoostPending: boolean,
	Nanobots: {
		Owned: { OwnedNanobot },
		Equipped: { string },
		NextUid: number,
	},
	Daily: {
		Streak: number,
		LastClaimDay: number,
	},
	Quests: {
		Day: number,
		Daily: { QuestState },
		Week: number,
		Weekly: { QuestState },
	},
	Download: {
		Kind: string, -- "" = aucun
		StartedAt: number,
	},
	Fragments: { [string]: boolean },
	Stats: {
		Playtime: number,
		VirusesZapped: number,
		Overclocks: number,
		CapsulesOpened: number,
		Upgrades: number,
		LastOnline: number,
		Reboots: number,
	},
	Tutorial: number,
	Settings: {
		Music: number,
		Sfx: number,
		ReducedMotion: boolean,
		RgbHue: number, -- -1 = RGB animé ; sinon teinte 0..1 (RGB Studio)
	},
	Receipts: { string },
	Likes: {
		Received: number,
		Day: number,
		GivenTo: { string },
	},
	Boosts: {
		BitsX2Until: number,
	},
	StarterPackBought: boolean,
	CreatedAt: number,
}

local DataSchema = {}

DataSchema.CURRENT_VERSION = 1
DataSchema.MAX_RECEIPTS = 50

function DataSchema.Template(): PlayerData
	return {
		Version = DataSchema.CURRENT_VERSION,
		Bits = 0,
		Chips = 0,
		Pending = 0,
		PoweredOn = false,
		Zone = 1,
		Levels = {},
		PsuLevel = 0,
		CoolingLevel = 0,
		SingularityPhase = 0,
		Firmware = 0,
		Generation = 1,
		RunBitsEarned = 0,
		TotalBitsEarned = 0,
		WeeklyBits = 0,
		WeeklyIndex = 0,
		Singularities = 0,
		RebootBoostPending = false,
		Nanobots = { Owned = {}, Equipped = {}, NextUid = 1 },
		Daily = { Streak = 0, LastClaimDay = -1 },
		Quests = { Day = -1, Daily = {}, Week = -1, Weekly = {} },
		Download = { Kind = "", StartedAt = 0 },
		Fragments = {},
		Stats = {
			Playtime = 0,
			VirusesZapped = 0,
			Overclocks = 0,
			CapsulesOpened = 0,
			Upgrades = 0,
			LastOnline = 0,
			Reboots = 0,
		},
		Tutorial = 0,
		Settings = { Music = 0.35, Sfx = 0.7, ReducedMotion = false, RgbHue = -1 },
		Receipts = {},
		Likes = { Received = 0, Day = -1, GivenTo = {} },
		Boosts = { BitsX2Until = 0 },
		StarterPackBought = false,
		CreatedAt = 0,
	}
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
