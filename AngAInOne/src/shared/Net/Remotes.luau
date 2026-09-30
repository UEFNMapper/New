--!strict
--[[
	Remotes : déclaration centralisée de tous les échanges client <-> serveur.
	Le serveur crée les instances (Remotes.Setup), le client les attend (Remotes.Get).
	Toute requête client est validée côté serveur par RemoteGuard (types, cadence, session).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "AngAInOneRemotes"

-- Client -> serveur (RemoteEvent). Les arguments attendus sont documentés ici.
local CLIENT_TO_SERVER = {
	"ClientReady", -- ()
	"PowerOn", -- ()
	"Upgrade", -- (moduleId: string, amount: number) amount = 1, 10 ou -1 (max)
	"UpgradeCapacity", -- (kind: "Power" | "Cooling", amount: number)
	"UnlockZone", -- (zone: number)
	"Travel", -- (floor: number) 0 = hub
	"OverclockStart", -- ()
	"OverclockStop", -- ()
	"OpenCapsule", -- (capsuleId: string)
	"EquipNanobot", -- (uid: string, equip: boolean)
	"FuseNanobots", -- (nanobotId: string)
	"ClaimDaily", -- ()
	"ClaimQuest", -- (questId: string)
	"StartDownload", -- (kind: string)
	"ClaimDownload", -- ()
	"Reboot", -- ()
	"BuySingularityPhase", -- ()
	"SaveSettings", -- (music: number, sfx: number, reducedMotion: boolean, rgbHue: number)
	"LikeTower", -- (ownerUserId: number)
	"DevCommand", -- (command: string, value: number) STUDIO UNIQUEMENT, ignoré en ligne
}

-- Serveur -> client (RemoteEvent), sauf "Tick" qui est non fiable (fréquent, perte tolérée).
local SERVER_TO_CLIENT = {
	"State", -- (snapshot) état complet du joueur
	"Notify", -- (kind: string, text: string)
	"Fx", -- (kind: string, data: any) effets visuels/sonores ponctuels
	"Leaderboard", -- (boards)
	"Offline", -- (bits: number, seconds: number)
	"ServerInfo", -- (info) boost serveur, annonces
	"Overclock", -- (phase: string, data: any)
}

local UNRELIABLE = { "Tick" } -- (bits, pending, rate, serverTime)

local Remotes = {}

function Remotes.Setup()
	assert(RunService:IsServer(), "Remotes.Setup doit être appelé par le serveur")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in CLIENT_TO_SERVER do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in SERVER_TO_CLIENT do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in UNRELIABLE do
		local remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function folder(): Instance
	local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
	assert(found, "Dossier de remotes introuvable")
	return found
end

function Remotes.Get(name: string): RemoteEvent
	local remote = folder():WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), `Remote {name} introuvable`)
	return remote
end

function Remotes.GetUnreliable(name: string): UnreliableRemoteEvent
	local remote = folder():WaitForChild(name, 30)
	assert(remote and remote:IsA("UnreliableRemoteEvent"), `Remote non fiable {name} introuvable`)
	return remote
end

Remotes.ClientToServer = table.freeze(CLIENT_TO_SERVER)
Remotes.ServerToClient = table.freeze(SERVER_TO_CLIENT)

return table.freeze(Remotes)
