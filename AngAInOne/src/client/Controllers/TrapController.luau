--!strict
--[[
	TrapController : fait vivre les pièges de la tour côté client et protège / tue le personnage LOCAL.

	- Horloge : chaque piège suit l'horloge de SON monde (attribut World du piège, sinon du premier
	  ancêtre qui l'a, sinon 0) = TrapClock.Compute appliqué à ReplicatedStorage.IncidentState,
	  lu une fois par image et par monde (même résultat que TrapClock.Now). FREEZE fige donc les
	  pièges du monde, LAG SPIKE les fait avancer par à-coups ; tous les clients voient la même chose
	  au même moment, le serveur garde les pièces immobiles (position de repos).
	- Incidents (TrapClock.Incident) : BLACKOUT éteint les plateformes Powered, CORRUPTION inverse
	  les dalles Corrupt, SURCHAUFFE active toutes les bouches Heat et double le vent (Wind).
	- Compatible StreamingEnabled : les pièces taguées sont prises en charge quand elles arrivent
	  (CollectionService) et oubliées quand elles repartent (avec leur habillage client). Seuls les
	  pièges proches de la caméra (≤ 300 studs) sont animés ; seuls ceux proches du personnage sont
	  testés.
	- Personnage local : transporté par les pièges porteurs (Mover, Defrag, LagMover, Spinner,
	  LoadBridge), poussé par Wind / Conveyor, propulsé par Bounce ; les plateformes Vanish
	  s'effacent pour lui seul ; le curseur géant (Cursor) ne vise que lui.
	- Contact mortel (Hazard + pièges mortels actifs) : détection géométrique locale (boîte, boule,
	  cylindre) sur 3 points du corps. Ignoré si le joueur a l'attribut Shielded = true ; sinon
	  Humanoid.Health = 0 et Net.Fire("ReportDeath", cause) UNE fois par vie, puis OnDeath(cause).
	  cause = Kind du piège, "Void" (chute dans le vide) ou "Hazard" (danger statique).

	Chaque type de piège est décrit dans Traps/* (attributs, défauts, préavis) :
	Classic (les 11 d'origine), Movers (Surge, Flood, Defrag, DustBall, Pendulum, LagMover),
	Toggles (Powered, Corrupt, DeadPixels), TabRain, Cursor, Spinner, LoadBridge, FirewallWall.
	Joueur : attribut ReducedMotion = true -> pas de clignotement ni de décor tournant.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Incidents = require(Shared.Config.Incidents)
local TrapClock = require(Shared.Util.TrapClock)

local Net = require(script.Parent.Net)
local Traps = script.Parent.Traps
local Common = require(Traps.Common)
local Classic = require(Traps.Classic)
local Movers = require(Traps.Movers)
local Toggles = require(Traps.Toggles)
local TabRain = require(Traps.TabRain)
local Cursor = require(Traps.Cursor)
local Spinner = require(Traps.Spinner)
local LoadBridge = require(Traps.LoadBridge)
local FirewallWall = require(Traps.FirewallWall)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler

local TrapController = {}

-- Rappel optionnel (effets visuels / sonores) appelé à la mort du personnage local.
TrapController.OnDeath = nil :: ((cause: string) -> ())?
-- Rappel optionnel pour les sons des préavis : cue = "Warn" | "Land" | "Click", piège proche du joueur.
TrapController.OnCue = nil :: ((cue: string, kind: string, position: Vector3) -> ())?

local ANIMATE_RADIUS = 300 -- pièges animés autour de la caméra
local INTERACT_MARGIN = 40 -- pièges testés autour du personnage (en plus de leur rayon)
local REFRESH = 0.25 -- recalcul des listes de proximité (s)

local HANDLERS: { [string]: Handler } = {}
for _, list in
	{
		Classic.Handlers,
		Movers.Handlers,
		Toggles.Handlers,
		TabRain.Handlers,
		Cursor.Handlers,
		Spinner.Handlers,
		LoadBridge.Handlers,
		FirewallWall.Handlers,
	}
do
	for kind, handler in list do
		HANDLERS[kind] = handler
	end
end

local player = Players.LocalPlayer
local traps: { [BasePart]: Trap } = {}
local active: { Trap } = {} -- animés (proches de la caméra ou du personnage)
local nearby: { Trap } = {} -- testés (proches du personnage)
local started = false
local reduced = false -- attribut ReducedMotion du joueur, relu à chaque recalcul des listes

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local deadThisLife = false

------------------------------------------------------------------------------------
-- Horloge et incidents par monde (une lecture par image et par monde)
------------------------------------------------------------------------------------

local stateFolder: Instance? = nil
local frameId = 0

type WorldState = {
	Stamp: number,
	T: number,
	Last: number?,
	Advanced: boolean,
	Incident: string,
	Incoming: string,
	Until: number,
	Names: { string },
}
local worlds: { [number]: WorldState } = {}

local frame: Ctx = {
	T = 0,
	Now = 0,
	Dt = 0,
	Incident = "",
	Incoming = "",
	Until = 0,
	Advanced = true,
	Reduced = false,
	Alive = false,
	Feet = Vector3.zero,
	Root = nil,
	Humanoid = nil,
	Grounded = false,
	Camera = Vector3.zero,
	Push = Vector3.zero,
}

local function findStateFolder()
	if stateFolder and stateFolder.Parent then
		return
	end
	-- pcall : ReplicatedStorage peut être simulé (tests) ; le dossier arrive avec IncidentService.
	local ok, found = pcall(function()
		return ReplicatedStorage:FindFirstChild(Incidents.StateFolder)
	end)
	stateFolder = if ok then found else nil
end

local function attribute(folder: Instance, name: string): any
	return folder:GetAttribute(name)
end

-- Remplit frame.T / Incident / Incoming / Until / Advanced pour ce monde.
local function prepare(world: number)
	local clock = worlds[world]
	if not clock then
		clock = {
			Stamp = -1,
			T = 0,
			Last = nil,
			Advanced = true,
			Incident = "",
			Incoming = "",
			Until = 0,
			Names = { `Kind{world}`, `Start{world}`, `End{world}`, `Offset{world}` },
		}
		worlds[world] = clock
	end
	if clock.Stamp ~= frameId then
		clock.Stamp = frameId
		local kind, start, finish, offset = "", 0, 0, 0
		local folder = stateFolder
		if folder then
			local names = clock.Names
			local k, s, e, o =
				attribute(folder, names[1]),
				attribute(folder, names[2]),
				attribute(folder, names[3]),
				attribute(folder, names[4])
			kind = if type(k) == "string" then k else ""
			start = if type(s) == "number" then s else 0
			finish = if type(e) == "number" then e else 0
			offset = if type(o) == "number" then o else 0
		end
		local now = frame.Now
		local t = TrapClock.Compute(now, kind, start, finish, offset)
		clock.Advanced = clock.Last == nil or t ~= clock.Last
		clock.Last = t
		clock.T = t
		clock.Incident, clock.Incoming, clock.Until = "", "", 0
		if kind ~= "" then
			if now >= start and now < finish then
				clock.Incident, clock.Until = kind, finish - now
			elseif now < start then
				clock.Incoming, clock.Until = kind, start - now
			end
		end
	end
	frame.T = clock.T
	frame.Advanced = clock.Advanced
	frame.Incident = clock.Incident
	frame.Incoming = clock.Incoming
	frame.Until = clock.Until
end

------------------------------------------------------------------------------------
-- Enregistrement (streaming : arrivée / départ des pièces taguées)
------------------------------------------------------------------------------------

-- Monde du piège : son attribut World, sinon celui du premier ancêtre qui l'a, sinon 0.
local function worldOf(part: Instance): number
	local node: Instance? = part
	while node do
		local value = node:GetAttribute("World")
		if type(value) == "number" then
			return value
		end
		node = node.Parent
	end
	return 0
end

local function addSolid(trap: Trap, part: BasePart)
	local shape = if part:IsA("Part") then (part :: Part).Shape else Enum.PartType.Block
	table.insert(trap.Solids, {
		Part = part,
		Shape = shape,
		Size = part.Size,
		Offset = if part == trap.Part then CFrame.identity else trap.Current:ToObjectSpace(part.CFrame),
		Transparency = part.Transparency,
	})
	local offset = if part == trap.Part then Vector3.zero else trap.Current:PointToObjectSpace(part.CFrame.Position)
	trap.Bound = math.max(trap.Bound, offset.Magnitude + part.Size.Magnitude / 2)
end

local function register(instance: Instance, tag: string)
	if not instance:IsA("BasePart") or traps[instance] then
		return
	end
	local part = instance :: BasePart
	local kind = if tag == "Hazard" then "Hazard" elseif tag == "TrapSpin" then "Spin" else part:GetAttribute("Kind")
	if type(kind) ~= "string" then
		return
	end
	local handler = HANDLERS[kind]
	if not handler then
		return
	end
	local rest = part.CFrame
	local offset = Common.Vec(part, "Offset")
	local direction = Common.Vec(part, "Direction")
	local path = Common.ParseWaypoints(part:GetAttribute("Waypoints"))
	local cumulative, loop = Common.Measure(path, true)
	local openCumulative, openLength = Common.Measure(path, false)
	local reach = 0
	for _, point in path do
		reach = math.max(reach, point.Magnitude)
	end
	local trap: Trap = {
		Part = part,
		Kind = kind,
		World = worldOf(part),
		Handler = handler,
		Rest = rest,
		Current = rest,
		Next = rest,
		Radius = offset.Magnitude
			+ reach
			+ (if kind == "SpinBar" or kind == "Spin" then part.Size.Magnitude / 2 else 0),
		Period = math.max(Common.Num(part, "Period", 3), 0.1),
		Duty = math.clamp(Common.Num(part, "Duty", 0.5), 0, 1),
		Phase = Common.Num(part, "Phase", 0),
		Speed = Common.Num(part, "Speed", if kind == "Spin" then 2 else 8),
		Axis = Common.AxisOf(part, Vector3.yAxis),
		Offset = offset,
		Direction = if direction.Magnitude > 0 then direction.Unit else Vector3.zero,
		Strength = Common.Num(part, "Strength", 6),
		Delay = Common.Num(part, "Delay", 1),
		Respawn = Common.Num(part, "Respawn", 3),
		Power = Common.Num(part, "Power", 80),
		Path = path,
		Cumulative = cumulative,
		Loop = loop,
		OpenCumulative = openCumulative,
		OpenLength = openLength,
		Gusts = part:GetAttribute("Period") ~= nil,
		Cause = if kind == "Hazard" then (if part:GetAttribute("Cause") == "Void" then "Void" else "Hazard") else kind,
		Seed = Common.SeedOf(rest),
		Solids = {},
		Pieces = {},
		Size = part.Size,
		Bound = 0,
		Emitters = {},
		Color = part.Color,
		Visual = -1,
		VanishAt = nil,
		Hidden = false,
		Removed = false,
		Near = false,
		Built = false,
		Rig = nil,
		CueKeys = {},
		Data = nil,
		Connection = nil,
	}
	addSolid(trap, part)
	for _, d in part:GetDescendants() do
		if d:IsA("BasePart") then
			addSolid(trap, d)
		elseif d:IsA("ParticleEmitter") then
			table.insert(trap.Emitters, d)
		end
	end
	if handler.Setup then
		handler.Setup(trap)
	end
	-- Pièces soudées qui arriveraient après la racine
	trap.Connection = part.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("BasePart") then
			addSolid(trap, d)
		elseif d:IsA("ParticleEmitter") then
			table.insert(trap.Emitters, d)
		end
	end)
	traps[part] = trap
end

local function unregister(instance: Instance)
	local trap = traps[instance :: BasePart]
	if trap then
		trap.Removed = true
		if trap.Connection then
			trap.Connection:Disconnect()
		end
		if trap.Rig then
			trap.Rig:Destroy()
			trap.Rig = nil
		end
		traps[instance :: BasePart] = nil
		Classic.Vanishing[trap] = nil
	end
end

------------------------------------------------------------------------------------
-- Mort (une seule fois par vie)
------------------------------------------------------------------------------------

local function die(cause: string)
	if deadThisLife or player:GetAttribute("Shielded") == true then
		return
	end
	local hum = humanoid
	if not hum or hum.Health <= 0 then
		return
	end
	deadThisLife = true
	hum.Health = 0
	task.spawn(function()
		local ok, err = pcall(function()
			Net.Fire("ReportDeath", cause)
		end)
		if not ok then
			warn(`[TrapController] ReportDeath : {err}`)
		end
	end)
	local callback = TrapController.OnDeath
	if callback then
		task.spawn(callback, cause)
	end
end

Common.CueHandler = function(cue: string, trap: Trap)
	local callback = TrapController.OnCue
	if callback then
		task.spawn(callback, cue, trap.Kind, trap.Current.Position)
	end
end

------------------------------------------------------------------------------------
-- Boucle
------------------------------------------------------------------------------------

local function feetOf(root: BasePart, hum: Humanoid): Vector3
	local hip = if hum.RigType == Enum.HumanoidRigType.R6 then 3 else hum.HipHeight + root.Size.Y / 2
	return root.Position - Vector3.new(0, hip, 0)
end

local function refresh()
	findStateFolder()
	local camera = Workspace.CurrentCamera
	local root = rootPart
	local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
	local rootPos = if root then root.Position else nil
	table.clear(active)
	table.clear(nearby)
	reduced = player:GetAttribute("ReducedMotion") == true
	for _, trap in traps do
		-- Distance à la boîte de repos (et non au centre) : le vide, immense, reste suivi partout.
		local size = trap.Size
		local near = rootPos ~= nil
			and Common.DistanceTo(trap.Rest, size, Enum.PartType.Block, rootPos) <= trap.Radius + INTERACT_MARGIN
		local seen = Common.DistanceTo(trap.Rest, size, Enum.PartType.Block, cameraPos) <= trap.Radius + ANIMATE_RADIUS
		trap.Near = near
		if near then
			table.insert(nearby, trap)
		end
		if (near or seen) and not (reduced and trap.Handler.Decor) then
			table.insert(active, trap)
		end
	end
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

-- Déplacement des pieds posés sur une plateforme qui passe de `from` à `to` (rotation comprise).
local function carried(from: CFrame, to: CFrame, feet: Vector3): Vector3
	return (to * from:Inverse()) * feet - feet
end

local function step(dt: number)
	frameId += 1
	local root, hum = rootPart, humanoid
	local alive = root ~= nil and hum ~= nil and hum.Health > 0 and root.Parent ~= nil
	local feet = if alive and root and hum then feetOf(root, hum) else Vector3.zero
	local camera = Workspace.CurrentCamera
	frame.Now = Workspace:GetServerTimeNow()
	frame.Dt = dt
	frame.Reduced = reduced
	frame.Alive = alive
	frame.Feet = feet
	frame.Root = root
	frame.Humanoid = hum
	frame.Grounded = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
	frame.Camera = if camera then camera.CFrame.Position else Vector3.zero
	frame.Push = Vector3.zero

	-- 1. Poses, habillage et états ; transport du personnage par les pièges porteurs
	table.clear(moveParts)
	table.clear(moveFrames)
	local carry: Vector3? = nil
	for _, trap in active do
		if trap.Removed then
			continue
		end
		local handler = trap.Handler
		prepare(trap.World)
		-- Seul un piège porteur proche du personnage peut le transporter
		local carrier = alive and trap.Near and handler.Carrier == true
		local build = handler.Build
		if build and not trap.Built then
			trap.Built = true
			local ok, err = pcall(function()
				build(trap, frame)
			end)
			if not ok then
				warn(`[TrapController] habillage {trap.Kind} : {err}`)
			end
		end
		if handler.Pose then
			local nextCf = handler.Pose(trap, frame.T)
			if carrier and not carry and Common.StandsOn(trap.Current, trap.Size, feet) then
				carry = carried(trap.Current, nextCf, feet)
			end
			trap.Next = nextCf
			if nextCf ~= trap.Current then
				table.insert(moveParts, trap.Part)
				table.insert(moveFrames, nextCf)
			end
		end
		if handler.Update then
			handler.Update(trap, frame)
		end
		for _, piece in trap.Pieces do
			if piece.Next ~= piece.Current then
				if carrier and piece.Solid and not carry and Common.StandsOn(piece.Current, piece.Size, feet) then
					carry = carried(piece.Current, piece.Next, feet)
				end
				table.insert(moveParts, piece.Part)
				table.insert(moveFrames, piece.Next * piece.Offset)
				piece.Current = piece.Next
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	for _, trap in active do
		if trap.Handler.Pose then
			trap.Current = trap.Next
		end
	end
	for trap in Classic.Vanishing do
		prepare(trap.World)
		Classic.UpdateVanish(trap, frame.T, reduced)
	end
	if not alive or not root or not hum then
		return
	end

	-- 2. Personnage local : contacts mortels, poussées, rebonds, effacements
	for _, trap in nearby do
		if trap.Removed then
			continue
		end
		local handler = trap.Handler
		prepare(trap.World)
		if handler.Lethal and (not handler.Active or handler.Active(trap, frame)) then
			local hit = if handler.Hits then handler.Hits(trap, frame, feet) else Common.Touches(trap, feet)
			if hit then
				die(trap.Cause)
				return
			end
		end
		if handler.Interact then
			handler.Interact(trap, frame, feet)
		end
	end
	local move = (carry or Vector3.zero) + frame.Push * dt
	if move.Magnitude > 1e-4 then
		root.CFrame += move
	end
end

------------------------------------------------------------------------------------
-- Démarrage
------------------------------------------------------------------------------------

local function onCharacter(character: Model)
	deadThisLife = false
	humanoid = nil
	rootPart = nil
	task.spawn(function()
		local hum = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if player.Character ~= character or not hum or not root then
			return
		end
		if hum:IsA("Humanoid") and root:IsA("BasePart") then
			humanoid = hum
			rootPart = root
			hum.Died:Connect(function()
				deadThisLife = true
			end)
			refresh()
		end
	end)
end

function TrapController.Start()
	if started then
		return
	end
	started = true
	for _, tag in { "Trap", "Hazard", "TrapSpin" } do
		for _, instance in CollectionService:GetTagged(tag) do
			register(instance, tag)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
			register(instance, tag)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(unregister)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
	RunService.PreSimulation:Connect(step)
end

return TrapController
