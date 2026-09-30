--!strict
--[[
	PlotService : attribue une tour à chaque joueur et synchronise son apparence.
	- Construit la map (MapBuilder) au démarrage
	- Tour libre -> joueur ; libérée à son départ
	- Attributs répliqués (le client s'en sert pour les visuels) :
	  Tower : OwnerUserId, OwnerName, Zone, PoweredOn, RgbHue, Likes, Generation
	  Module : Level ; Fragment : Found
	- Collecteurs (on marche dessus) et fragments (on les touche)
	- Déplacements (ascenseur, hub) validés côté serveur
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Config.WorldLayout)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)

local PlotService = {}

local towers: { Model } = {}
local owners: { [number]: Session.Session } = {} -- index de tour -> session
local hubSpawn: CFrame = CFrame.new(0, 6, 0)
local lastTravel: { [Player]: number } = {}

function PlotService.GetTower(session: Session.Session): Model?
	return if session.Plot > 0 then towers[session.Plot] else nil
end

function PlotService.GetTowerByIndex(index: number): Model?
	return towers[index]
end

function PlotService.GetFloor(tower: Model, floor: number): Model?
	local floors = tower:FindFirstChild("Floors")
	local model = floors and floors:FindFirstChild(`Floor{floor}`)
	return if model and model:IsA("Model") then model else nil
end

-- Position locale du joueur dans sa tour (nil s'il n'y est pas).
function PlotService.LocalPosition(session: Session.Session): Vector3?
	if session.Plot == 0 then
		return nil
	end
	local character = session.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	return MapBuilder.TowerCFrame(session.Plot):PointToObjectSpace(root.Position)
end

function PlotService.IsInOwnTower(session: Session.Session): boolean
	local localPos = PlotService.LocalPosition(session)
	if not localPos then
		return false
	end
	local halfW = MapBuilder.TOWER_WIDTH / 2 + 6
	local halfD = MapBuilder.TOWER_DEPTH / 2 + 20 -- tolère le parvis devant la porte
	local top = MapBuilder.FloorY(#Zones) + MapBuilder.FLOOR_HEIGHT
	return math.abs(localPos.X) <= halfW and math.abs(localPos.Z) <= halfD and localPos.Y >= -8 and localPos.Y <= top
end

-- Étage où se trouve le joueur dans sa tour (0 si dehors).
function PlotService.CurrentFloor(session: Session.Session): number
	local localPos = PlotService.LocalPosition(session)
	if not localPos or not PlotService.IsInOwnTower(session) then
		return 0
	end
	return WorldLayout.FloorAt(localPos.Y, #Zones)
end

-- Point aléatoire sur un étage (pour faire apparaître les virus), en coordonnées monde.
function PlotService.RandomFloorPoint(index: number, floor: number, rng: Random): CFrame
	local x = rng:NextNumber(-44, 44)
	local z = rng:NextNumber(-22, 4)
	return MapBuilder.TowerCFrame(index) * CFrame.new(x, MapBuilder.FloorY(floor) + 3.5, z)
end

function PlotService.Teleport(session: Session.Session, target: CFrame)
	local character = session.Player.Character
	if character then
		character:PivotTo(target)
	end
end

function PlotService.TeleportToFloor(session: Session.Session, floor: number)
	if floor <= 0 or session.Plot == 0 then
		PlotService.Teleport(session, hubSpawn)
	else
		PlotService.Teleport(session, MapBuilder.FloorSpawn(session.Plot, floor))
	end
end

-- Recopie les données du joueur dans les attributs de sa tour.
function PlotService.Sync(session: Session.Session)
	local tower = PlotService.GetTower(session)
	if not tower then
		return
	end
	local data = session.Data
	tower:SetAttribute("Zone", data.Zone)
	tower:SetAttribute("PoweredOn", data.PoweredOn)
	tower:SetAttribute("RgbHue", if session.Passes.RgbStudio then data.Settings.RgbHue else -1)
	tower:SetAttribute("Likes", data.Likes.Received)
	tower:SetAttribute("Generation", data.Generation)
	tower:SetAttribute("SingularityPhase", data.SingularityPhase)
	for floorIndex = 1, #Zones do
		local floor = PlotService.GetFloor(tower, floorIndex)
		if floor then
			local modules = floor:FindFirstChild("Modules")
			if modules then
				for _, model in modules:GetChildren() do
					local id = model:GetAttribute("ModuleId")
					if type(id) == "string" then
						model:SetAttribute("Level", data.Levels[id] or 0)
					end
				end
			end
			local fragments = floor:FindFirstChild("Fragments")
			if fragments then
				for _, fragment in fragments:GetChildren() do
					local id = fragment:GetAttribute("FragmentId")
					if type(id) == "string" then
						fragment:SetAttribute("Found", data.Fragments[id] == true)
					end
				end
			end
		end
	end
end

local function resetTower(tower: Model)
	tower:SetAttribute("OwnerUserId", 0)
	tower:SetAttribute("OwnerName", "")
	tower:SetAttribute("Zone", 0)
	tower:SetAttribute("PoweredOn", false)
	tower:SetAttribute("RgbHue", -1)
	tower:SetAttribute("Likes", 0)
	for _, descendant in tower:GetDescendants() do
		if descendant:GetAttribute("ModuleId") then
			descendant:SetAttribute("Level", 0)
		elseif descendant:GetAttribute("FragmentId") then
			descendant:SetAttribute("Found", false)
		end
	end
	local viruses = tower:FindFirstChild("Viruses")
	if viruses then
		viruses:ClearAllChildren()
	end
end

local function assign(session: Session.Session)
	for index = 1, GameConfig.MaxPlots do
		if owners[index] == nil then
			owners[index] = session
			session.Plot = index
			local tower = towers[index]
			tower:SetAttribute("OwnerUserId", session.UserId)
			tower:SetAttribute("OwnerName", session.Player.DisplayName)
			tower:AddPersistentPlayer(session.Player)
			PlotService.Sync(session)
			return
		end
	end
	warn("[PlotService] Aucune tour libre (MaxPlayers du serveur > MaxPlots ?)")
end

local function release(session: Session.Session)
	if session.Plot == 0 then
		return
	end
	local tower = towers[session.Plot]
	owners[session.Plot] = nil
	if tower then
		tower:RemovePersistentPlayer(session.Player)
		resetTower(tower)
	end
	session.Plot = 0
end

-- Session du propriétaire de la tour qui contient `part` (nil si aucune).
local function ownerOfPart(part: Instance): Session.Session?
	local current: Instance? = part
	while current do
		local parent = current.Parent
		if not parent then
			return nil
		end
		local index = current:GetAttribute("Index")
		if current:IsA("Model") and type(index) == "number" and parent.Name == "Towers" then
			return owners[index]
		end
		current = parent
	end
	return nil
end

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return if model then Players:GetPlayerFromCharacter(model) else nil
end

local function wireTouches(tower: Model)
	for _, descendant in tower:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:HasTag("Collector") then
			local debounce: { [Player]: number } = {}
			descendant.Touched:Connect(function(hit: BasePart)
				local player = playerFromHit(hit)
				if not player then
					return
				end
				local owner = ownerOfPart(descendant)
				if not owner or owner.Player ~= player then
					return
				end
				local now = os.clock()
				if (debounce[player] or 0) > now then
					return
				end
				debounce[player] = now + 0.5
				EconomyService.Collect(owner)
			end)
		elseif descendant:IsA("BasePart") and descendant:HasTag("Fragment") then
			descendant.Touched:Connect(function(hit: BasePart)
				local player = playerFromHit(hit)
				local owner = ownerOfPart(descendant)
				if not player or not owner or owner.Player ~= player then
					return
				end
				local id = descendant:GetAttribute("FragmentId")
				if type(id) ~= "string" or owner.Data.Fragments[id] then
					return
				end
				owner.Data.Fragments[id] = true
				descendant:SetAttribute("Found", true)
				EconomyService.Fx(owner, "Fragment", { Id = id })
				GameEvents.StateChanged:Fire(owner.Player)
			end)
		end
	end
end

function PlotService.Start()
	local hub
	hub, towers = MapBuilder.Build()
	local spawnPart = hub:FindFirstChild("HubSpawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		hubSpawn = spawnPart.CFrame + Vector3.new(0, 4, 0)
	end
	for _, tower in towers do
		wireTouches(tower)
	end

	Session.Added:Connect(function(session: Session.Session)
		assign(session)
		local function onCharacter(character: Model)
			-- Apparition dans sa tour, à l'étage de La Centrale (ou le plus haut pendant le tutoriel terminé)
			task.defer(function()
				if character.Parent and session.Plot > 0 then
					character:PivotTo(MapBuilder.FloorSpawn(session.Plot, 1))
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
		release(session)
	end)

	GameEvents.StateChanged:Connect(function(player: Player)
		local session = Session.Get(player)
		if session then
			PlotService.Sync(session)
		end
	end)

	-- Ascenseur / retour au hub : l'étage doit être débloqué, 1 déplacement/s max.
	RemoteGuard.On(
		"Travel",
		{ Args = { RemoteGuard.Int(0, #Zones) } },
		function(session: Session.Session, floor: number)
			if floor > session.Data.Zone then
				return
			end
			local now = os.clock()
			if (lastTravel[session.Player] or 0) > now then
				return
			end
			lastTravel[session.Player] = now + 1
			PlotService.TeleportToFloor(session, floor)
		end
	)
end

return PlotService
