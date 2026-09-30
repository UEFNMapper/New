--!strict
--[[
	BossService : le combat final contre LAGZ (monde 7), autorité serveur.
	Logique pure dans Util/BossLogic (testée : tests/boss.spec.luau).

	- Un état par joueur (combat individuel) ; avancé toutes les TICK s d'après la position du
	  personnage (boîte de l'arène : pièce taguée BossArena, posée par Worlds/W7), sa vie, son checkpoint
	  et le lobby. Mort pendant les phases 1–2 : on recommence ; lobby / départ : remis à zéro.
	- Phase 2 : remote BossPlug(index) — gardée par RemoteGuard (type, cadence) puis validée ici
	  (phase, une seule fois, personnage vivant à moins de BossLogic.PLUG_REACH de la prise
	  taguée BossPlug + attribut Index). Les 3 prises -> phase 3 (terminal ouvert).
	- Phase 3 : MinigameService n'ouvre le terminal du monde 7 que si BossService.TerminalOpen.
	  Réussite -> ProgressService.ClearWorld(7) -> GameEvents.WorldCleared -> phase 4.
	- Réplication : attributs du joueur BossPhase (0..4), BossSince (heure serveur du début de
	  la phase), BossPlugs (masque des prises branchées). BossController (client) s'en sert
	  pour l'arène, LAGZ, les pièges de chaque phase et les répliques.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossLogic = require(Shared.Util.BossLogic)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local ProgressService = require(script.Parent.ProgressService)

local BossService = {}

local TICK = 0.2
local PHASE = BossLogic.Phase

type Arena = { Center: Vector3, Size: Vector3 }

local arena: Arena? = nil
local plugs: { [number]: Vector3 } = {}
local states: { [Session.Session]: BossLogic.State } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Publie l'état pour le client (attributs répliqués du joueur).
local function sync(session: Session.Session, state: BossLogic.State)
	local player = session.Player
	player:SetAttribute("BossSince", state.Since)
	player:SetAttribute("BossPlugs", BossLogic.PlugMask(state))
	player:SetAttribute("BossPhase", state.Phase) -- en dernier : le client lit un état complet
end

local function stateOf(session: Session.Session): BossLogic.State
	local state = states[session]
	if not state then
		state = BossLogic.New(now())
		states[session] = state
	end
	return state
end

local function inArena(session: Session.Session): boolean
	local zone = arena
	local character = session.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not zone or not root or not root:IsA("BasePart") then
		return false
	end
	return BossLogic.InArena(zone.Center, zone.Size, root.Position)
end

local function onEvent(session: Session.Session, state: BossLogic.State, event: string?)
	if not event then
		return
	end
	sync(session, state)
	if event == "Start" or event == "Plugs" or event == "Terminal" or event == "Abort" then
		Telemetry.Custom(session.Player, `Boss{event}`, state.Phase)
	end
end

local function step(session: Session.Session)
	local state = stateOf(session)
	local data = session.Data
	local event = BossLogic.Step(state, {
		Now = now(),
		Stage = data.Stage,
		Cleared = data.Cleared,
		AtLobby = ProgressService.IsAtLobby(session),
		Alive = session.Alive,
		InArena = inArena(session),
	})
	onEvent(session, state, event)
end

-- Phase du combat du joueur (BossLogic.Phase).
function BossService.Phase(session: Session.Session): number
	local state = states[session]
	return if state then state.Phase else PHASE.Idle
end

-- Le terminal final (monde 7) peut-il être lancé par ce joueur ?
function BossService.TerminalOpen(session: Session.Session): boolean
	local state = states[session]
	return state ~= nil and BossLogic.TerminalOpen(state)
end

local function onPlug(session: Session.Session, index: number)
	local state = states[session]
	local position = plugs[index]
	if not state or not position or not session.Alive then
		return
	end
	local ok, result = BossLogic.Plug(state, index, RemoteGuard.DistanceTo(session.Player, position), now())
	if ok then
		onEvent(session, state, result)
	end
end

local function indexArena()
	for _, part in CollectionService:GetTagged("BossArena") do
		if part:IsA("BasePart") then
			arena = { Center = part.Position, Size = part.Size }
		end
	end
	for _, part in CollectionService:GetTagged("BossPlug") do
		local index = part:GetAttribute("Index")
		if part:IsA("BasePart") and type(index) == "number" then
			plugs[index] = part.Position
		end
	end
	if not arena then
		warn("[BossService] arène de LAGZ introuvable (tag BossArena) : combat désactivé")
	end
end

function BossService.Start()
	indexArena() -- la tour est construite par ProgressService (démarré avant)

	Session.Added:Connect(function(session: Session.Session)
		local state = stateOf(session)
		step(session)
		sync(session, state)
	end)
	Session.Removing:Connect(function(session: Session.Session)
		states[session] = nil
	end)
	GameEvents.Died:Connect(function(player: Player)
		local session = Session.Get(player)
		local state = session and states[session]
		if session and state then
			onEvent(session, state, BossLogic.Died(state, now()))
		end
	end)
	GameEvents.WorldCleared:Connect(function(player: Player, world: number)
		local session = Session.Get(player)
		local state = session and states[session]
		if session and state and world >= BossLogic.WORLD then
			onEvent(session, state, BossLogic.Defeat(state, now()))
		end
	end)
	RemoteGuard.On("BossPlug", { Args = { RemoteGuard.Int(1, BossLogic.PLUG_COUNT) } }, onPlug)

	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, session in Session.All() do
				step(session)
			end
		end
	end)
end

return BossService
