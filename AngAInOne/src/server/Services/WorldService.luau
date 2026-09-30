--!strict
--[[
	WorldService : le PC géant partagé par tous les joueurs du serveur.
	- Construit la map (MapBuilder) au démarrage
	- Collecteurs (on marche dessus) et fragments (on les touche) : chacun agit sur SES données
	- Téléporteurs (Travel) validés côté serveur
	- Portails : le client rend la barrière solide, le serveur renvoie derrière le portail
	  tout joueur qui se trouve dans une zone qu'il n'a pas débloquée (anti-triche)
	- Attributs répliqués sur le Player (visibles des autres joueurs) :
	  Zone, Generation, Likes, PoweredOn, RgbHue
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Config.WorldLayout)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)

local WorldService = {}

local lastTravel: { [Player]: number } = {}
local collectDebounce: { [Player]: number } = {}
local lastWarned: { [Player]: number } = {}

local function rootOf(session: Session.Session): BasePart?
	local character = session.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Zone où se trouve le joueur : 0 = hub, 1..7, -1 = hors carte / pas de personnage.
function WorldService.ZoneOf(session: Session.Session): number
	local root = rootOf(session)
	return if root then WorldLayout.ZoneAt(root.Position) else -1
end

-- Le joueur est sur la carte mère (hub ou une zone).
function WorldService.IsInWorld(session: Session.Session): boolean
	return WorldService.ZoneOf(session) >= 0
end

function WorldService.Teleport(session: Session.Session, target: CFrame)
	local player = session.Player
	-- StreamingEnabled : on demande au client de charger la destination AVANT d'y déplacer le joueur.
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 5)
	end)
	local character = player.Character
	if character and character.Parent then
		character:PivotTo(target)
	end
end

-- Arrivée d'une zone (0 = hub), tournée vers l'intérieur de la zone.
function WorldService.SpawnCFrame(zone: number): CFrame
	if zone <= 0 then
		return CFrame.lookAt(WorldLayout.HubSpawn, WorldLayout.HubSpawn - Vector3.zAxis)
	end
	local layout = WorldLayout.Zones[zone]
	local inward = (layout.Spawn - layout.Gate) * Vector3.new(1, 0, 1)
	return CFrame.lookAt(layout.Spawn, layout.Spawn + inward)
end

function WorldService.TeleportToZone(session: Session.Session, zone: number)
	WorldService.Teleport(session, WorldService.SpawnCFrame(zone))
end

-- Point aléatoire près du joueur, dans la zone où il se trouve (pour faire apparaître un virus).
function WorldService.RandomPointNear(session: Session.Session, rng: Random): CFrame?
	local root = rootOf(session)
	if not root then
		return nil
	end
	local zone = WorldLayout.ZoneAt(root.Position)
	if zone < 0 then
		return nil
	end
	for _ = 1, 8 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(18, 40)
		local point =
			Vector3.new(root.Position.X + math.cos(angle) * distance, 3.5, root.Position.Z + math.sin(angle) * distance)
		if WorldLayout.ZoneAt(point) == zone then
			return CFrame.new(point)
		end
	end
	return CFrame.new(root.Position.X, 3.5, root.Position.Z)
end

-- Recopie les données publiques du joueur dans ses attributs (lus par les autres clients).
function WorldService.Sync(session: Session.Session)
	local player = session.Player
	local data = session.Data
	player:SetAttribute("Zone", data.Zone)
	player:SetAttribute("PoweredOn", data.PoweredOn)
	player:SetAttribute("RgbHue", if session.Passes.RgbStudio then data.Settings.RgbHue else -1)
	player:SetAttribute("Likes", data.Likes.Received)
	player:SetAttribute("Generation", data.Generation)
end

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return if model then Players:GetPlayerFromCharacter(model) else nil
end

local function wireTouches(world: Instance)
	for _, descendant in world:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:HasTag("Collector") then
			descendant.Touched:Connect(function(hit: BasePart)
				local player = playerFromHit(hit)
				local session = player and Session.Get(player)
				if not player or not session then
					return
				end
				local now = os.clock()
				if (collectDebounce[player] or 0) > now then
					return
				end
				collectDebounce[player] = now + 0.5
				EconomyService.Collect(session)
			end)
		elseif descendant:IsA("BasePart") and descendant:HasTag("Fragment") then
			descendant.Touched:Connect(function(hit: BasePart)
				local player = playerFromHit(hit)
				local session = player and Session.Get(player)
				if not session then
					return
				end
				local id = descendant:GetAttribute("FragmentId")
				if type(id) ~= "string" or session.Data.Fragments[id] then
					return
				end
				-- Un fragment n'est ramassable que dans une zone débloquée.
				local zone = tonumber(string.match(id, "^Z(%d+)F"))
				if not zone or zone > session.Data.Zone then
					return
				end
				session.Data.Fragments[id] = true
				EconomyService.Fx(session, "Fragment", { Id = id })
				GameEvents.StateChanged:Fire(session.Player)
			end)
		end
	end
end

-- Renvoie derrière le portail les joueurs présents dans une zone verrouillée.
local function enforceGates()
	local now = os.clock()
	for _, session in Session.All() do
		local root = rootOf(session)
		if root then
			local zone = WorldLayout.ZoneAt(root.Position)
			if zone > session.Data.Zone then
				local layout = WorldLayout.Zones[zone]
				local outward = (layout.Gate - layout.Spawn) * Vector3.new(1, 0, 1)
				local back = layout.Gate + outward.Unit * 14 + Vector3.new(0, 4, 0)
				WorldService.Teleport(session, CFrame.lookAt(back, back + outward))
				if (lastWarned[session.Player] or 0) < now then
					lastWarned[session.Player] = now + 4
					EconomyService.Notify(
						session,
						"Error",
						`{Zones[zone].Name} est verrouillée : débloque-la au terminal.`
					)
				end
			elseif root.Position.Y < -40 or root.Position.Y > WorldLayout.CASE_HEIGHT + 20 then
				WorldService.TeleportToZone(session, 0)
			end
		end
	end
end

function WorldService.Start()
	MapBuilder.Build()
	local world = Workspace:FindFirstChild("World")
	if world then
		wireTouches(world)
	end

	Session.Added:Connect(function(session: Session.Session)
		WorldService.Sync(session)
		local function onCharacter(character: Model)
			task.spawn(function()
				-- Attend un personnage complet avant de le placer au hub.
				character:WaitForChild("HumanoidRootPart", 5)
				if character.Parent then
					WorldService.TeleportToZone(session, 0)
				end
			end)
		end
		session.Trove:Connect(session.Player.CharacterAdded, onCharacter)
		if session.Player.Character then
			onCharacter(session.Player.Character)
		end
	end)
	Session.Removing:Connect(function(session: Session.Session)
		lastTravel[session.Player] = nil
		collectDebounce[session.Player] = nil
		lastWarned[session.Player] = nil
	end)

	GameEvents.StateChanged:Connect(function(player: Player)
		local session = Session.Get(player)
		if session then
			WorldService.Sync(session)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			enforceGates()
		end
	end)

	-- Téléporteur / retour au hub : la zone doit être débloquée, 1 déplacement/s max.
	RemoteGuard.On("Travel", { Args = { RemoteGuard.Int(0, #Zones) } }, function(session: Session.Session, zone: number)
		if zone > session.Data.Zone then
			return
		end
		local now = os.clock()
		if (lastTravel[session.Player] or 0) > now then
			return
		end
		lastTravel[session.Player] = now + 1
		WorldService.TeleportToZone(session, zone)
	end)
end

return WorldService
