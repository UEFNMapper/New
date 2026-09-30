--!strict
--[[
	ProgressService : le cœur du deathrun (autorité serveur).
	- Construit la tour (TowerBuilder) et indexe ses checkpoints, terminaux, orbes, arrivée
	- Checkpoints validés DANS L'ORDRE, avec un temps minimum par étape ; le premier checkpoint
	  d'un monde n'est accepté que si le terminal antivirus du monde précédent est réussi
	- Morts (signalées par le client ou détectées), réapparition au checkpoint
	- Chrono de l'ascension (arrêté au lobby et hors connexion), victoire au sommet
	- Orbes de Bits (une fois par ascension, à proximité), boutons checkpoint / lobby / reprendre
	- Les joueurs ne se bousculent pas (groupe de collision « Runners »)
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Tower = require(Shared.Config.Tower)
local DataSchema = require(Shared.Data.DataSchema)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local TowerBuilder = require(script.Parent.Parent.World.TowerBuilder)
local StateService = require(script.Parent.StateService)

local ProgressService = {}

local RUN = GameConfig.Run
local COLLISION_GROUP = "Runners"

local checkpoints: { [number]: BasePart } = {}
local arcades: { Vector3 } = {}
local terminals: { [number]: BasePart } = {}
local lobbySpawn: CFrame = CFrame.new(0, 5, 0)
local atLobby: { [Session.Session]: boolean } = {}

------------------------------------------------------------------------------------
-- Chrono
------------------------------------------------------------------------------------

local function startClock(session: Session.Session)
	if session.ClockSince == 0 and session.Data.RunStarted and not atLobby[session] then
		session.ClockSince = os.clock()
	end
end

local function stopClock(session: Session.Session)
	if session.ClockSince > 0 then
		session.Data.RunElapsed += os.clock() - session.ClockSince
		session.ClockSince = 0
	end
end

-- Reporte le segment en cours dans RunElapsed sans arrêter le chrono : les sauvegardes
-- automatiques (et une fin de session brutale) gardent ainsi un temps juste.
local function commitClock(session: Session.Session)
	if session.ClockSince > 0 then
		local now = os.clock()
		session.Data.RunElapsed += now - session.ClockSince
		session.ClockSince = now
	end
end

-- Un avantage (bottes, puce) est-il actif ? L'ascension n'entre alors pas au classement des temps.
local function assistActive(session: Session.Session): boolean
	local toggles = session.Data.Toggles
	return (toggles.LowGravity and session.Passes.LowGravity == true)
		or (toggles.SpeedChip and session.Passes.SpeedChip == true)
end

------------------------------------------------------------------------------------
-- Positions et téléportations
------------------------------------------------------------------------------------

function ProgressService.CheckpointCFrame(stage: number): CFrame
	local pad = checkpoints[stage]
	if not pad then
		return lobbySpawn
	end
	local top = pad.Position + Vector3.new(0, pad.Size.Y / 2 + RUN.RespawnHeight, 0)
	local look = pad.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(top, top + look.Unit)
end

function ProgressService.TerminalPosition(world: number): Vector3?
	local terminal = terminals[world]
	return if terminal then terminal.Position else nil
end

function ProgressService.IsAtLobby(session: Session.Session): boolean
	return atLobby[session] == true
end

local function teleport(session: Session.Session, target: CFrame)
	local player = session.Player
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 5)
	end)
	local character = player.Character
	if character and character.Parent then
		character:PivotTo(target)
	end
end

function ProgressService.ToCheckpoint(session: Session.Session)
	atLobby[session] = nil
	startClock(session)
	GameEvents.StateChanged:Fire(session.Player)
	teleport(session, ProgressService.CheckpointCFrame(session.Data.Stage))
end

-- Le joueur est-il près d'une borne d'arcade ?
function ProgressService.NearArcade(session: Session.Session, maxDistance: number): boolean
	for _, position in arcades do
		if RemoteGuard.DistanceTo(session.Player, position) <= maxDistance then
			return true
		end
	end
	return false
end

function ProgressService.ToLobby(session: Session.Session)
	atLobby[session] = true
	stopClock(session)
	teleport(session, lobbySpawn)
	GameEvents.StateChanged:Fire(session.Player)
end

local function syncAttributes(session: Session.Session)
	local player = session.Player
	player:SetAttribute("Stage", session.Data.Stage)
	player:SetAttribute("Wins", session.Data.Wins)
end

------------------------------------------------------------------------------------
-- Progression
------------------------------------------------------------------------------------

-- Fait avancer le joueur au checkpoint `stage` (déjà validé). `skipped` = acheté.
local function advanceTo(session: Session.Session, stage: number, skipped: boolean)
	local data = session.Data
	local previousWorld = Tower.WorldOf(data.Stage)
	commitClock(session)
	data.Stage = stage
	session.LastCheckpointAt = os.clock()
	if stage > data.BestStage then
		data.BestStage = stage
	end
	if not skipped then
		Wallet.Add(session, RUN.CheckpointBits, "Checkpoint", true)
	end
	local world = Tower.WorldOf(stage)
	Wallet.Fx(session, "Checkpoint", {
		Stage = stage,
		World = world,
		NewWorld = world ~= previousWorld and previousWorld >= 1,
	})
	syncAttributes(session)
	GameEvents.CheckpointReached:Fire(session.Player, stage)
	if stage % Tower.STAGES_PER_WORLD == 1 or stage == Tower.TOTAL_STAGES then
		Telemetry.Progression(session.Player, "Tower", stage, `Stage{stage}`)
	end
	GameEvents.StateChanged:Fire(session.Player)
end

local function onCheckpoint(session: Session.Session, stage: number)
	local data = session.Data
	if stage == 0 then
		if data.Stage > 0 then
			-- Ascension déjà en cours : la ligne de départ ramène au dernier checkpoint.
			ProgressService.ToCheckpoint(session)
			return
		end
		atLobby[session] = nil
		-- Ligne de départ : le chrono démarre.
		if not data.RunStarted then
			data.RunStarted = true
			data.RunAssisted = assistActive(session)
			session.LastCheckpointAt = os.clock()
			Wallet.Fx(session, "RunStart", {})
		end
		startClock(session)
		GameEvents.StateChanged:Fire(session.Player)
		return
	end
	atLobby[session] = nil
	if stage ~= data.Stage + 1 then
		return -- retour en arrière ou étape sautée : ignoré
	end
	if not data.RunStarted then
		return
	end
	-- Entrée dans un nouveau monde : le terminal antivirus du précédent doit être réussi.
	local world = Tower.WorldOf(stage)
	if stage == Tower.FirstStage(world) and data.Cleared < world - 1 then
		return
	end
	if os.clock() - session.LastCheckpointAt < RUN.MinStageSeconds then
		return -- trop rapide pour être honnête
	end
	startClock(session)
	advanceTo(session, stage, false)
end

-- Victoire : sommet atteint, tous les terminaux réussis.
local function onFinish(session: Session.Session)
	local data = session.Data
	if data.Stage ~= Tower.TOTAL_STAGES or data.Cleared < Tower.WORLD_COUNT or session.Data.RunStarted == false then
		return
	end
	stopClock(session)
	if assistActive(session) then
		data.RunAssisted = true
	end
	local time = data.RunElapsed
	local first = data.Wins == 0
	data.Wins += 1
	local record = false
	if not data.RunAssisted and (data.BestTime == 0 or time < data.BestTime) then
		data.BestTime = time
		record = true
	end
	local bits = Wallet.Add(session, if first then RUN.VictoryBits else RUN.RepeatVictoryBits, "Victory", true)
	Telemetry.Progression(session.Player, "Tower", Tower.TOTAL_STAGES + 1, "Victory")
	GameEvents.Victory:Fire(session.Player, time)
	Wallet.Fx(session, "Victory", {
		Time = time,
		Record = record,
		Assisted = data.RunAssisted,
		First = first,
		Bits = bits,
		Wins = data.Wins,
	})
	DataSchema.ResetRun(data)
	syncAttributes(session)
	GameEvents.StateChanged:Fire(session.Player)
	task.delay(7, function()
		-- Seulement si le joueur n'a pas déjà relancé une ascension entre-temps.
		if Session.Get(session.Player) == session and data.Stage == 0 and not data.RunStarted then
			ProgressService.ToLobby(session)
		end
	end)
end

-- Passe l'étape (achat Robux) : checkpoint suivant ; saute aussi le terminal si besoin.
function ProgressService.Skip(session: Session.Session): boolean
	local data = session.Data
	if data.Stage >= Tower.TOTAL_STAGES then
		-- Au sommet, il ne reste que le dernier terminal : on le passe.
		if data.Cleared < Tower.WORLD_COUNT then
			data.Cleared = Tower.WORLD_COUNT
			data.RunAssisted = true
			session.Player:SetAttribute("Cleared", data.Cleared)
			Wallet.Fx(session, "WorldCleared", { World = Tower.WORLD_COUNT, Bits = 0, Score = 0 })
			GameEvents.StateChanged:Fire(session.Player)
			return true
		end
		return false
	end
	local nextStage = data.Stage + 1
	local world = Tower.WorldOf(nextStage)
	if nextStage == Tower.FirstStage(world) and data.Cleared < world - 1 then
		data.Cleared = world - 1
	end
	data.RunStarted = true
	data.RunAssisted = true
	advanceTo(session, nextStage, true)
	ProgressService.ToCheckpoint(session)
	return true
end

-- Marque le monde comme nettoyé (terminal réussi) : ouvre son portail.
function ProgressService.ClearWorld(session: Session.Session, world: number): boolean
	local data = session.Data
	if world ~= data.Cleared + 1 then
		return false
	end
	data.Cleared = world
	session.Player:SetAttribute("Cleared", world)
	GameEvents.WorldCleared:Fire(session.Player, world)
	GameEvents.StateChanged:Fire(session.Player)
	return true
end

------------------------------------------------------------------------------------
-- Personnages
------------------------------------------------------------------------------------

local function playerFromHit(hit: BasePart): (Player?, Session.Session?)
	local model = hit:FindFirstAncestorOfClass("Model")
	local player = if model then Players:GetPlayerFromCharacter(model) else nil
	return player, if player then Session.Get(player) else nil
end

local function setCollisionGroup(character: Model)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP
		end
	end
	character.DescendantAdded:Connect(function(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP
		end
	end)
end

local function onCharacter(session: Session.Session, character: Model)
	setCollisionGroup(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root) or Session.Get(session.Player) ~= session then
		return
	end
	session.Alive = true
	humanoid.Died:Connect(function()
		if not session.Alive then
			return
		end
		session.Alive = false
		session.Data.Deaths += 1
		local position = if root:IsA("BasePart") then root.Position else Vector3.zero
		Wallet.FxAll("Death", { UserId = session.UserId, Position = position, Fx = session.Data.Cosmetics.DeathFx })
		GameEvents.Died:Fire(session.Player)
		GameEvents.StateChanged:Fire(session.Player)
	end)
	-- Réapparition : au lobby ou au dernier checkpoint. Le personnage apparaît d'abord au
	-- SpawnLocation du lobby ; on le place, puis on vérifie qu'il y est bien (la première
	-- physique du client peut écraser un déplacement trop précoce).
	if atLobby[session] or session.Data.Stage == 0 and not session.Data.RunStarted then
		return
	end
	task.spawn(function()
		local target = ProgressService.CheckpointCFrame(session.Data.Stage)
		task.wait(0.1)
		for _ = 1, 3 do
			if character.Parent == nil or Session.Get(session.Player) ~= session then
				return
			end
			teleport(session, target)
			task.wait(0.35)
			local current = character:GetPivot().Position
			if (current - target.Position).Magnitude < 25 then
				return
			end
		end
	end)
end

------------------------------------------------------------------------------------
-- Démarrage
------------------------------------------------------------------------------------

local function indexTower(tower: Folder)
	for _, part in CollectionService:GetTagged("Checkpoint") do
		local stage = part:GetAttribute("Stage")
		if part:IsA("BasePart") and type(stage) == "number" and part:IsDescendantOf(tower) then
			checkpoints[stage] = part
			part.Touched:Connect(function(hit: BasePart)
				local _, session = playerFromHit(hit)
				if session and session.Alive then
					onCheckpoint(session, stage)
				end
			end)
		end
	end
	for _, part in CollectionService:GetTagged("MinigameTerminal") do
		local world = part:GetAttribute("World")
		if part:IsA("BasePart") and type(world) == "number" then
			terminals[world] = part
		end
	end
	for _, part in CollectionService:GetTagged("Finish") do
		if part:IsA("BasePart") then
			part.Touched:Connect(function(hit: BasePart)
				local _, session = playerFromHit(hit)
				if session and session.Alive then
					onFinish(session)
				end
			end)
		end
	end
	-- Clés USB dorées : trouvées une fois pour toujours (chemins difficiles facultatifs).
	local totalKeys = Tower.WORLD_COUNT * Tower.USB_KEYS_PER_WORLD
	for _, part in CollectionService:GetTagged("UsbKey") do
		local id = part:GetAttribute("KeyId")
		if part:IsA("BasePart") and type(id) == "string" then
			part.Touched:Connect(function(hit: BasePart)
				local player, session = playerFromHit(hit)
				if not player or not session or not session.Alive then
					return
				end
				local data = session.Data
				if data.UsbKeys[id] or RemoteGuard.DistanceTo(player, part.Position) > RUN.CoinPickupDistance then
					return
				end
				data.UsbKeys[id] = true
				local found = 0
				for _ in data.UsbKeys do
					found += 1
				end
				local bits = Wallet.Add(session, RUN.UsbKeyBits, "UsbKey", true)
				if found >= totalKeys and not table.find(data.Cosmetics.Owned, RUN.UsbAllKeysCosmetic) then
					table.insert(data.Cosmetics.Owned, RUN.UsbAllKeysCosmetic)
				end
				Wallet.Fx(session, "UsbKey", { Id = id, Found = found, Total = totalKeys, Bits = bits })
				GameEvents.StateChanged:Fire(player)
			end)
		end
	end
	for _, part in CollectionService:GetTagged("Coin") do
		local id = part:GetAttribute("CoinId")
		if part:IsA("BasePart") and type(id) == "string" then
			local coinStage = tonumber(string.match(id, "^S(%d+)")) or 0
			part.Touched:Connect(function(hit: BasePart)
				local player, session = playerFromHit(hit)
				if not player or not session or not session.Alive then
					return
				end
				local data = session.Data
				if data.RunCoins[id] or coinStage > data.Stage + 1 then
					return
				end
				if RemoteGuard.DistanceTo(player, part.Position) > RUN.CoinPickupDistance then
					return
				end
				data.RunCoins[id] = true
				data.Stats.CoinsCollected += 1
				Wallet.Add(session, RUN.CoinBits, "Coin", true)
				Wallet.Fx(session, "Coin", { Id = id, Position = part.Position })
				GameEvents.CoinCollected:Fire(player)
			end)
		end
	end
	for _, descendant in tower:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("Action") == "Arcade" then
			local holder = descendant.Parent
			if holder and holder:IsA("BasePart") then
				table.insert(arcades, holder.Position)
			end
		end
	end
	local spawn = tower:FindFirstChild("LobbySpawn", true)
	if spawn and spawn:IsA("BasePart") then
		lobbySpawn = spawn.CFrame + Vector3.new(0, RUN.RespawnHeight, 0)
	end
end

function ProgressService.Start()
	Players.RespawnTime = RUN.RespawnSeconds
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

	indexTower(TowerBuilder.Build())

	Session.Added:Connect(function(session: Session.Session)
		atLobby[session] = true -- chaque connexion commence au lobby (histoire, boutique…)
		syncAttributes(session)
		session.Player:SetAttribute("Cleared", session.Data.Cleared)
		session.Trove:Connect(session.Player.CharacterAdded, function(character: Model)
			onCharacter(session, character)
		end)
		if session.Player.Character then
			task.spawn(onCharacter, session, session.Player.Character)
		end
	end)
	Session.Removing:Connect(function(session: Session.Session)
		stopClock(session)
		atLobby[session] = nil
	end)

	RemoteGuard.On("ReportDeath", { Limit = "Death", Args = { RemoteGuard.String(24) } }, function(session, _cause)
		if not session.Alive or session.ShieldUntil > os.time() then
			return
		end
		local character = session.Player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
	RemoteGuard.On("ToCheckpoint", { Args = {} }, function(session)
		if os.clock() - session.LastTeleportAt < RUN.TeleportCooldown then
			return
		end
		session.LastTeleportAt = os.clock()
		ProgressService.ToCheckpoint(session)
	end)
	RemoteGuard.On("ToLobby", { Args = {} }, function(session)
		if os.clock() - session.LastTeleportAt < RUN.TeleportCooldown then
			return
		end
		session.LastTeleportAt = os.clock()
		ProgressService.ToLobby(session)
	end)
	RemoteGuard.On("Resume", { Args = {} }, function(session)
		if os.clock() - session.LastTeleportAt < RUN.TeleportCooldown then
			return
		end
		session.LastTeleportAt = os.clock()
		ProgressService.ToCheckpoint(session)
		GameEvents.StateChanged:Fire(session.Player)
	end)

	-- Temps de jeu + chute hors de la tour
	task.spawn(function()
		while true do
			task.wait(1)
			for _, session in Session.All() do
				session.PlaytimeCarry += 1
				if session.PlaytimeCarry >= 60 then
					session.PlaytimeCarry -= 60
					session.Data.Stats.Playtime += 60
					GameEvents.PlaytimeMinute:Fire(session.Player)
				end
				local character = session.Player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and root.Position.Y < RUN.FallKillBelow and session.Alive then
					task.spawn(ProgressService.ToCheckpoint, session)
				end
				-- Toutes les 5 s, le chrono en cours est reporté dans la sauvegarde.
				if session.PlaytimeCarry % 5 == 0 then
					commitClock(session)
				end
			end
		end
	end)
end

-- Pour StateService : le joueur est-il au lobby ?
StateService.AtLobby = ProgressService.IsAtLobby

return ProgressService
