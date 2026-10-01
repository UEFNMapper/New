--!strict
--[[
	ProgressService : le cœur du deathrun (autorité serveur).
	- Construit la tour (TowerBuilder) et indexe ses checkpoints, terminaux, orbes, arrivée
	- Checkpoints validés DANS L'ORDRE, avec un temps minimum par étape ; le premier checkpoint
	  d'un monde n'est accepté que si le terminal antivirus du monde précédent est réussi
	- Morts (signalées par le client ou détectées), réapparition au checkpoint ; contrôle serveur
	  des chutes dans le vide (checkVoid) pour que les morts des médailles ne dépendent pas du client
	- Chrono de l'ascension (arrêté au lobby et hors connexion), victoire au sommet
	- Orbes de Bits (une fois par ascension, à proximité), boutons checkpoint / lobby / reprendre
	- Médailles par monde : chrono de chaque monde (RunSplit), morts et clés USB du monde,
	  meilleurs résultats (WorldBest), calculés à ClearWorld (Config/Medals, Util/MedalLogic)
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
local MedalLogic = require(Shared.Util.MedalLogic)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local TowerBuilder = require(script.Parent.Parent.World.TowerBuilder)
local Common = require(script.Parent.Parent.World.Tower.Common)
local StateService = require(script.Parent.StateService)

local ProgressService = {}

local RUN = GameConfig.Run
local COLLISION_GROUP = "Runners"

local checkpoints: { [number]: BasePart } = {}
local arcades: { Vector3 } = {}
local terminals: { [number]: BasePart } = {}
local lobbySpawn: CFrame = CFrame.new(0, 5, 0)
local atLobby: { [Session.Session]: boolean } = {}

-- Contrôle serveur des chutes dans le vide (médailles) : la racine sous le vide du monde plus de
-- VOID_DELAY s compte une mort (une fois par chute) ; un Died dans les VOID_DIED_WINDOW s qui
-- suivent (le client signale la même chute) n'est pas recompté.
local VOID_POLL = 0.25
local VOID_DELAY = 0.5
local VOID_DIED_WINDOW = 3
local fallWatch: { [Session.Session]: MedalLogic.FallWatch } = {}
local voidCountedAt: { [Session.Session]: number } = {}

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
-- Médailles : chrono de chaque monde
------------------------------------------------------------------------------------

-- Résultat d'un monde nettoyé (envoyé au client dans l'effet « WorldCleared »).
export type MedalResult = {
	Medal: string, -- "Bronze" | "Silver" | "Gold"
	Time: number, -- temps du monde (0 = inconnu)
	Best: number, -- meilleur temps sans aide après ce passage (0 = aucun)
	NewBest: boolean, -- nouveau record de temps du monde
	MedalUp: boolean, -- meilleure médaille qu'avant pour ce monde
	Deaths: number,
	Keys: number, -- clés USB possédées dans ce monde (sur Tower.USB_KEYS_PER_WORLD)
	Assisted: boolean, -- aide utilisée dans ce monde : médaille gardée, pas de record
}

-- Une aide est-elle active en ce moment (passe avantage ou bouclier) ?
local function helpedNow(session: Session.Session): boolean
	return assistActive(session) or session.ShieldUntil > os.time()
end

-- Aide active en entrant (ou en revenant) dans la tour pendant l'ascension : ascension et monde
-- marqués tout de suite (ShopService marque aussi à l'activation, hors lobby).
local function markIfHelped(session: Session.Session)
	if helpedNow(session) then
		MedalLogic.MarkAssisted(session.Data)
	end
end

-- Démarre le chrono du monde `world` (à l'entrée du monde).
local function startSplit(session: Session.Session, world: number, assisted: boolean)
	commitClock(session)
	MedalLogic.StartSplit(session.Data.RunSplit, world, session.Data.RunElapsed, assisted or helpedNow(session))
end

-- Termine le chrono du monde `world` (terminal réussi) : médaille + meilleur résultat.
local function finishSplit(session: Session.Session, world: number): MedalResult
	local data = session.Data
	local split = data.RunSplit
	commitClock(session)
	if helpedNow(session) then
		split.Assisted = true
	end
	local time = MedalLogic.SplitTime(split, world, data.RunElapsed)
	local keys = MedalLogic.KeysInWorld(data.UsbKeys, world, Tower.USB_KEYS_PER_WORLD)
	local deaths = if time then split.Deaths else 0
	local medal = MedalLogic.Evaluate(world, time, deaths, keys, split.Assisted)
	local key = MedalLogic.Key(world)
	-- Record seulement sans aide et avec un temps mesuré ; la médaille est gardée dans tous les cas.
	local best, newBest, medalUp = MedalLogic.UpdateBest(data.WorldBest[key], medal, time, not split.Assisted)
	data.WorldBest[key] = best
	return {
		Medal = medal,
		Time = time or 0,
		Best = best.Time,
		NewBest = newBest,
		MedalUp = medalUp,
		Deaths = deaths,
		Keys = keys,
		Assisted = split.Assisted,
	}
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
	session.Minigame = nil -- une partie ouverte ne survit pas à un déplacement
	markIfHelped(session)
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
	session.Minigame = nil
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
	session.Minigame = nil
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
			data.Cleared = 0 -- nouvelle ascension : la tour est de nouveau infectée
			data.RunDeaths = 0
			data.RunStarted = true
			data.RunAssisted = assistActive(session)
			session.LastCheckpointAt = os.clock()
			startSplit(session, 1, false)
			Wallet.Fx(session, "RunStart", {})
		else
			markIfHelped(session) -- retour sur la ligne de départ depuis le lobby, avantage actif
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
	local keys = 0
	for _ in data.UsbKeys do
		keys += 1
	end
	Wallet.Fx(session, "Victory", {
		Time = time,
		Record = record,
		Assisted = data.RunAssisted,
		First = first,
		Bits = bits,
		Wins = data.Wins,
		-- Rapport d'optimisation (UI/Screens/Moments) : chutes de CETTE ascension, clés USB trouvées.
		Deaths = data.RunDeaths,
		Keys = keys,
		KeysTotal = Tower.WORLD_COUNT * Tower.USB_KEYS_PER_WORLD,
	})
	DataSchema.ResetRun(data)
	-- La tour reste NETTOYÉE (décor, PC à 144 FPS, live, LAGZ vaincu) jusqu'à la prochaine
	-- ascension : Cleared ne repasse à 0 qu'au départ suivant (voir onCheckpoint, stage 0).
	data.Cleared = Tower.WORLD_COUNT
	syncAttributes(session)
	GameEvents.StateChanged:Fire(session.Player)
	task.delay(7, function()
		-- Seulement si le joueur n'a pas déjà relancé une ascension entre-temps.
		if Session.Get(session.Player) == session and data.Stage == 0 and not data.RunStarted then
			ProgressService.ToLobby(session)
		end
	end)
end

-- Le repaire de LAGZ (dernière étape + arène + terminal final) ne se passe pas : le boss se mérite.
function ProgressService.CanSkip(data: any): boolean
	return data.Stage < Tower.TOTAL_STAGES - 1
end

-- Passe l'étape (achat Robux) : checkpoint suivant ; saute aussi le terminal si besoin.
function ProgressService.Skip(session: Session.Session): boolean
	local data = session.Data
	if not ProgressService.CanSkip(data) then
		return false -- remboursé en Bits par MonetizationService
	end
	if not data.RunStarted then
		data.Cleared = 0 -- nouvelle ascension (la victoire précédente laisse la tour nettoyée)
		startSplit(session, 1, true)
		data.RunDeaths = 0
	end
	local nextStage = data.Stage + 1
	local world = Tower.WorldOf(nextStage)
	if nextStage == Tower.FirstStage(world) and data.Cleared < world - 1 then
		data.Cleared = world - 1
		-- Terminal sauté : pas de médaille pour le monde précédent, le monde suivant commence.
		startSplit(session, world, true)
	end
	data.RunStarted = true
	data.RunAssisted = true
	data.RunSplit.Assisted = true -- médaille possible, mais pas de record pour ce monde
	advanceTo(session, nextStage, true)
	ProgressService.ToCheckpoint(session)
	return true
end

-- Marque le monde comme nettoyé (terminal réussi) : ouvre son portail. Renvoie aussi la
-- médaille du monde (chrono depuis l'entrée du monde) ; le chrono du monde suivant démarre.
function ProgressService.ClearWorld(session: Session.Session, world: number): (boolean, MedalResult?)
	local data = session.Data
	if world ~= data.Cleared + 1 then
		return false, nil
	end
	data.Cleared = world
	local result = finishSplit(session, world)
	if world < Tower.WORLD_COUNT then
		startSplit(session, world + 1, false)
	end
	session.Player:SetAttribute("Cleared", world)
	GameEvents.WorldCleared:Fire(session.Player, world)
	GameEvents.StateChanged:Fire(session.Player)
	return true, result
end

------------------------------------------------------------------------------------
-- Morts de l'ascension et chutes dans le vide
------------------------------------------------------------------------------------

-- Une mort pendant l'ascension, hors lobby : rapport de fin (RunDeaths) et monde en cours (médailles).
local function countRunDeath(session: Session.Session)
	local data = session.Data
	if not data.RunStarted or atLobby[session] then
		return
	end
	data.RunDeaths += 1
	if data.RunSplit.World > 0 then
		data.RunSplit.Deaths += 1
	end
end

--[[
	Contrôle léger côté serveur : les morts par piège sont décidées par le client (ReportDeath), qui
	pourrait ne jamais signaler une chute dans le vide. Si la racine d'un joueur en course reste dans
	le vide d'un monde (Common.VoidWorldAt : sur ou sous la plaque, là où le voile mortel l'aurait
	touché) plus de VOID_DELAY s, la chute compte comme une mort (une fois) et il revient au checkpoint,
	comme pour la chute hors de la tour. Bouclier actif : rien (il marche sur le vide, course assistée).
]]
local function checkVoid(session: Session.Session, now: number)
	local watch = fallWatch[session]
	if not watch then
		watch = { Since = nil, Counted = false }
		fallWatch[session] = watch
	end
	local character = session.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local inVoid = session.Alive
		and session.Data.RunStarted
		and not atLobby[session]
		and session.ShieldUntil <= os.time()
		and root ~= nil
		and root:IsA("BasePart")
		and Common.VoidWorldAt(root.Position) > 0
	if MedalLogic.WatchFall(watch, inVoid == true, now, VOID_DELAY) then
		countRunDeath(session)
		voidCountedAt[session] = now
		GameEvents.StateChanged:Fire(session.Player)
		task.spawn(ProgressService.ToCheckpoint, session)
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
		-- Morts de l'ascension (rapport de fin) et du monde en cours (médailles) : pièges signalés
		-- par le client (ReportDeath, qui met la vie à 0), vide mortel, boss… Pas au lobby. Une
		-- chute dans le vide déjà comptée par le contrôle serveur (juste avant) ne compte pas deux fois.
		local counted = voidCountedAt[session]
		voidCountedAt[session] = nil
		if not (counted and os.clock() - counted < VOID_DIED_WINDOW) then
			countRunDeath(session)
		end
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
				if data.RunStarted and data.RunSplit.World == MedalLogic.KeyWorld(id) then
					data.RunSplit.Keys += 1
				end
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
				-- Méga-Bit des détours bonus : attribut Value (défaut 1)
				local value = math.max(1, math.floor(tonumber(part:GetAttribute("Value")) or 1))
				local gain = Wallet.Add(session, RUN.CoinBits * value, "Coin", true)
				Wallet.Fx(session, "Coin", {
					Id = id,
					Position = part.Position,
					Bits = gain,
					Bonus = part:GetAttribute("Bonus") == true,
					Mega = value > 1,
				})
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
		fallWatch[session] = nil
		voidCountedAt[session] = nil
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
				-- Aide utilisée pendant le monde (bouclier, passe activé) : pas de record pour ce monde
				-- (filet de sécurité : ShopService et ToCheckpoint marquent déjà à l'activation).
				if not atLobby[session] then
					markIfHelped(session)
				end
				-- Toutes les 5 s, le chrono en cours est reporté dans la sauvegarde.
				if session.PlaytimeCarry % 5 == 0 then
					commitClock(session)
				end
			end
		end
	end)

	-- Chutes dans le vide (médailles) : contrôle serveur 4 fois par seconde.
	task.spawn(function()
		while true do
			task.wait(VOID_POLL)
			local now = os.clock()
			for _, session in Session.All() do
				checkVoid(session, now)
			end
		end
	end)
end

-- Pour StateService : le joueur est-il au lobby ?
StateService.AtLobby = ProgressService.IsAtLobby

return ProgressService
