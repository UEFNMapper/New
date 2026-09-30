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
	teleport(session, ProgressService.CheckpointCFrame(session.Data.Stage))
	startClock(session)
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
	atLobby[session] = nil
	if stage == 0 then
		-- Ligne de départ : le chrono démarre (ou reprend).
		if data.Stage == 0 and not data.RunStarted then
			data.RunStarted = true
			session.LastCheckpointAt = os.clock()
			Wallet.Fx(session, "RunStart", {})
			GameEvents.StateChanged:Fire(session.Player)
		end
		startClock(session)
		return
	end
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
		if Session.Get(session.Player) == session then
			ProgressService.ToLobby(session)
		end
	end)
end

-- Passe l'étape (achat Robux) : checkpoint suivant ; saute aussi le terminal si besoin.
function ProgressService.Skip(session: Session.Session): boolean
	local data = session.Data
	if data.Stage >= Tower.TOTAL_STAGES then
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
function ProgressService.ClearWorld(session: Session.Session, world: number)
	local data = session.Data
	if world == data.Cleared + 1 then
		data.Cleared = world
		session.Player:SetAttribute("Cleared", world)
		GameEvents.WorldCleared:Fire(session.Player, world)
		GameEvents.StateChanged:Fire(session.Player)
	end
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
	-- Réapparition : au lobby ou au dernier checkpoint.
	task.defer(function()
		if atLobby[session] or session.Data.Stage == 0 and not session.Data.RunStarted then
			teleport(session, lobbySpawn)
		else
			teleport(session, ProgressService.CheckpointCFrame(session.Data.Stage))
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
					ProgressService.ToCheckpoint(session)
				end
			end
		end
	end)
end

-- Pour StateService : le joueur est-il au lobby ?
StateService.AtLobby = ProgressService.IsAtLobby

return ProgressService
