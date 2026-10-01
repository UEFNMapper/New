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
	"ReportDeath", -- (cause: string) le client a touché un piège (pièges animés côté client)
	"ToCheckpoint", -- () revenir au dernier checkpoint
	"ToLobby", -- () retourner au lobby (la progression est gardée)
	"Resume", -- () depuis le lobby : reprendre au dernier checkpoint
	"MinigameStart", -- (world: number) terminal antivirus du monde
	"MinigameEnd", -- (world: number, success: boolean, score: number)
	"ArcadeStart", -- (kind: string) borne d'arcade du lobby
	"ArcadeEnd", -- (kind: string, success: boolean, score: number)
	"BossPlug", -- (index: number) combat de LAGZ, phase 2 : le personnage est sur la prise antivirus
	"BuyCosmetic", -- (id: string)
	"EquipCosmetic", -- (id: string)
	"ToggleAssist", -- (key: string, on: boolean) "LowGravity" | "SpeedChip"
	"ClaimDaily", -- ()
	"ClaimMission", -- (id: string)
	"IntroSeen", -- ()
	"SaveSettings", -- (music: number, sfx: number, reducedMotion: boolean)
	"PuzzleAnswer", -- (world: number, item: string) enquête de la salle du terminal (Config/Puzzles)
	"Uninstall", -- (world: number, index: number) désinstaller un bloatware (monde 5)
	"ChooseRole", -- (role: string) rôle coop (Config/Roles), "" = aucun
	"DevCommand", -- (command: string, value: number) STUDIO UNIQUEMENT, ignoré en ligne
}

-- Serveur -> client (RemoteEvent).
local SERVER_TO_CLIENT = {
	"State", -- (snapshot) état complet du joueur
	"Notify", -- (kind: string, text: string)
	"Fx", -- (kind: string, data: any) effets visuels/sonores ponctuels
	"Leaderboard", -- (boards)
}

local UNRELIABLE: { string } = {}

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
