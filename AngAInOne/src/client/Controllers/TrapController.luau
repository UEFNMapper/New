--!strict
--[[
	TrapController : fait vivre les pièges de la tour côté client et protège / tue le personnage LOCAL.

	- Animation déterministe à partir de Workspace:GetServerTimeNow() : tous les clients voient la
	  même chose au même moment, le serveur garde les pièces immobiles (position de repos).
	- Compatible StreamingEnabled : les pièces taguées sont prises en charge quand elles arrivent
	  (CollectionService) et oubliées quand elles repartent. Seuls les pièges proches de la caméra
	  (≤ 300 studs) sont animés ; seuls ceux proches du personnage sont testés.
	- Personnage local : transporté par les plateformes Mover, poussé par Wind / Conveyor, propulsé
	  par Bounce ; les plateformes Vanish s'effacent pour lui seul.
	- Contact mortel (Hazard + pièges mortels actifs) : détection géométrique locale (boîte, boule,
	  cylindre) sur 3 points du corps. Ignoré si le joueur a l'attribut Shielded = true ; sinon
	  Humanoid.Health = 0 et Net.Fire("ReportDeath", cause) UNE fois par vie, puis OnDeath(cause).
	  cause = Kind du piège, "Void" (chute dans le vide) ou "Hazard" (danger statique).

	Attributs lus (contrat de TowerBuilder / Config/Tower) :
	- Period, Duty, Phase (fraction de période ; de tour pour SpinBar ; de boucle pour Virus)
	- Offset, Direction : Vector3 MONDE ; Axis : "X" | "Y" | "Z" (axe local) ; Speed, Strength, Power
	- Delay, Respawn (Vanish) ; Waypoints (Virus) : "x,y,z;x,y,z" relatifs à la position de repos
	- Wind : Period / Duty optionnels (rafales) ; TrapSpin : moyeu décoratif (Axis, Speed)
	Joueur : attribut ReducedMotion = true -> pas de clignotement ni de décor tournant.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)

local TrapController = {}

-- Rappel optionnel (effets visuels / sonores) appelé à la mort du personnage local.
TrapController.OnDeath = nil :: ((cause: string) -> ())?

local ANIMATE_RADIUS = 300 -- pièges animés autour de la caméra
local INTERACT_MARGIN = 40 -- pièges testés autour du personnage (en plus de leur rayon)
local REFRESH = 0.25 -- recalcul des listes de proximité (s)
local TELEGRAPH = 0.6 -- clignotement avant l'activation (s)
local BODY_RADIUS = 0.95 -- rayon des 3 points testés sur le corps (indulgent pour les enfants)
local BODY_SAMPLES = { 0.9, 2.6, 4.3 } -- hauteurs des points testés au-dessus des pieds
local TWO_PI = math.pi * 2

local LETHAL: { [string]: boolean } = {
	Zapper = true,
	SpinBar = true,
	Crusher = true,
	Laser = true,
	Virus = true,
	Heat = true,
	Hazard = true,
}
local MOVING: { [string]: boolean } = {
	SpinBar = true,
	Crusher = true,
	Mover = true,
	Laser = true,
	Virus = true,
	Spin = true,
}
local KNOWN: { [string]: boolean } = {
	Zapper = true,
	SpinBar = true,
	Crusher = true,
	Mover = true,
	Vanish = true,
	Wind = true,
	Laser = true,
	Virus = true,
	Conveyor = true,
	Bounce = true,
	Heat = true,
	Hazard = true,
	Spin = true,
}

-- Pièce du piège (racine + pièces soudées) : taille et position relative mises en cache
-- pour ne lire aucune propriété d'instance à chaque image.
type Solid = { Part: BasePart, Shape: Enum.PartType, Size: Vector3, Offset: CFrame, Transparency: number }

type Trap = {
	Part: BasePart,
	Kind: string,
	Rest: CFrame,
	Current: CFrame,
	Next: CFrame,
	Radius: number, -- débattement autour de la boîte de repos (décalage, patrouille, rotation)
	Period: number,
	Duty: number,
	Phase: number,
	Speed: number,
	Axis: Vector3,
	Offset: Vector3,
	Direction: Vector3,
	Strength: number,
	Delay: number,
	Respawn: number,
	Power: number,
	Path: { Vector3 },
	Cumulative: { number },
	Loop: number,
	Gusts: boolean,
	Cause: string,
	Solids: { Solid },
	Size: Vector3,
	Bound: number, -- rayon de la sphère englobant toutes les pièces (autour de la racine)
	Emitters: { ParticleEmitter },
	Color: Color3,
	Visual: number, -- dernier état visuel appliqué (évite les écritures inutiles)
	VanishAt: number?,
	Hidden: boolean,
	Removed: boolean,
	Connection: RBXScriptConnection?,
}

local player = Players.LocalPlayer
local traps: { [BasePart]: Trap } = {}
local animated: { Trap } = {}
local nearby: { Trap } = {}
local vanishing: { [Trap]: boolean } = {}
local started = false

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local deadThisLife = false
local lastBounce = 0

------------------------------------------------------------------------------------
-- Lecture des attributs
------------------------------------------------------------------------------------

local function num(part: Instance, name: string, default: number): number
	local value = part:GetAttribute(name)
	return if type(value) == "number" and value == value then value else default
end

local function vec(part: Instance, name: string): Vector3
	local value = part:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else Vector3.zero
end

local function axisOf(part: Instance): Vector3
	local value = part:GetAttribute("Axis")
	if typeof(value) == "Vector3" and value.Magnitude > 0 then
		return value.Unit
	elseif value == "X" then
		return Vector3.xAxis
	elseif value == "Z" then
		return Vector3.zAxis
	end
	return Vector3.yAxis
end

-- "x,y,z;x,y,z" -> points relatifs (le premier point est normalement 0,0,0).
local function parseWaypoints(text: any): { Vector3 }
	local points = {}
	if type(text) ~= "string" then
		return points
	end
	for chunk in string.gmatch(text, "[^;]+") do
		local x, y, z = string.match(chunk, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
		local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
		if nx and ny and nz then
			table.insert(points, Vector3.new(nx, ny, nz))
		end
	end
	return points
end

local reduced = false -- attribut ReducedMotion du joueur, relu à chaque recalcul des listes

local function reducedMotion(): boolean
	return reduced
end

------------------------------------------------------------------------------------
-- Enregistrement (streaming : arrivée / départ des pièces taguées)
------------------------------------------------------------------------------------

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
	if type(kind) ~= "string" or not KNOWN[kind] then
		return
	end
	local rest = part.CFrame
	local offset = vec(part, "Offset")
	local direction = vec(part, "Direction")
	local path = parseWaypoints(part:GetAttribute("Waypoints"))
	local cumulative = { 0 }
	local loop = 0
	if #path >= 2 then
		for i = 1, #path do
			loop += (path[i % #path + 1] - path[i]).Magnitude
			cumulative[i + 1] = loop
		end
	end
	local reach = 0
	for _, point in path do
		reach = math.max(reach, point.Magnitude)
	end
	local trap: Trap = {
		Part = part,
		Kind = kind,
		Rest = rest,
		Current = rest,
		Next = rest,
		Radius = offset.Magnitude
			+ reach
			+ (if kind == "SpinBar" or kind == "Spin" then part.Size.Magnitude / 2 else 0),
		Period = math.max(num(part, "Period", 3), 0.1),
		Duty = math.clamp(num(part, "Duty", 0.5), 0, 1),
		Phase = num(part, "Phase", 0),
		Speed = num(part, "Speed", if kind == "Spin" then 2 else 8),
		Axis = axisOf(part),
		Offset = offset,
		Direction = if direction.Magnitude > 0 then direction.Unit else Vector3.zero,
		Strength = num(part, "Strength", 6),
		Delay = num(part, "Delay", 1),
		Respawn = num(part, "Respawn", 3),
		Power = num(part, "Power", 80),
		Path = path,
		Cumulative = cumulative,
		Loop = loop,
		Gusts = part:GetAttribute("Period") ~= nil,
		Cause = if kind == "Hazard" then (if part:GetAttribute("Cause") == "Void" then "Void" else "Hazard") else kind,
		Solids = {},
		Size = part.Size,
		Bound = 0,
		Emitters = {},
		Color = part.Color,
		Visual = -1,
		VanishAt = nil,
		Hidden = false,
		Removed = false,
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
		traps[instance :: BasePart] = nil
		vanishing[trap] = nil
	end
end

------------------------------------------------------------------------------------
-- Animation (fonctions du temps serveur)
------------------------------------------------------------------------------------

local function cycle(trap: Trap, t: number): number
	return (t / trap.Period + trap.Phase) % 1
end

-- Écraseur : repos (0) puis descente rapide, maintien en bas, remontée lente.
local function crushProfile(p: number): number
	if p < 0.45 then
		return 0
	elseif p < 0.55 then
		local x = (p - 0.45) / 0.1
		return x * x
	elseif p < 0.7 then
		return 1
	end
	return 1 - (p - 0.7) / 0.3
end

local function pathPoint(trap: Trap, s: number): Vector3
	local path, cumulative = trap.Path, trap.Cumulative
	for i = 1, #path do
		local a, b = cumulative[i], cumulative[i + 1]
		if s <= b or i == #path then
			local from, to = path[i], path[i % #path + 1]
			local alpha = if b > a then math.clamp((s - a) / (b - a), 0, 1) else 0
			return from:Lerp(to, alpha)
		end
	end
	return Vector3.zero
end

local function poseAt(trap: Trap, t: number): CFrame
	local kind = trap.Kind
	if kind == "SpinBar" or kind == "Spin" then
		local angle = (trap.Speed * t + trap.Phase * TWO_PI) % TWO_PI
		return trap.Rest * CFrame.fromAxisAngle(trap.Axis, angle)
	elseif kind == "Crusher" then
		return trap.Rest + trap.Offset * crushProfile(cycle(trap, t))
	elseif kind == "Mover" or kind == "Laser" then
		return trap.Rest + trap.Offset * (0.5 - 0.5 * math.cos(TWO_PI * cycle(trap, t)))
	elseif kind == "Virus" then
		if trap.Loop <= 0 then
			return trap.Rest
		end
		local s = (t * trap.Speed + trap.Phase * trap.Loop) % trap.Loop
		local spin = CFrame.Angles(0, (t * 2) % TWO_PI, 0)
		return CFrame.new(trap.Rest.Position + pathPoint(trap, s)) * trap.Rest.Rotation * spin
	end
	return trap.Rest
end

-- Piège mortel actif à l'instant t (décharges et chaleur ne tuent que pendant leur phase active).
local function isActive(trap: Trap, t: number): boolean
	if trap.Kind == "Zapper" or trap.Kind == "Heat" then
		return cycle(trap, t) < trap.Duty
	end
	return true
end

local function setTransparency(trap: Trap, value: number)
	if trap.Visual ~= value then
		trap.Visual = value
		trap.Part.Transparency = value
	end
end

-- Signal visuel : actif = visible, juste avant = clignote, repos = fantôme.
local function updateVisual(trap: Trap, t: number)
	local kind = trap.Kind
	if kind == "Zapper" or kind == "Heat" then
		local p = cycle(trap, t)
		local base = trap.Solids[1].Transparency
		if p < trap.Duty then
			setTransparency(trap, base)
		elseif (1 - p) * trap.Period < TELEGRAPH then
			local blink = reducedMotion() or math.floor(t * 14) % 2 == 0
			setTransparency(trap, if blink then 0.6 else 0.88)
		else
			setTransparency(trap, if kind == "Heat" then 0.97 else 0.9)
		end
	elseif kind == "Crusher" then
		local p = cycle(trap, t)
		local warn = p >= 0.3 and p < 0.45 and (reducedMotion() or math.floor(t * 12) % 2 == 0)
		local state = if warn then 1 else 0
		if trap.Visual ~= state then
			trap.Visual = state
			trap.Part.Color = if warn then trap.Color:Lerp(Color3.new(1, 1, 1), 0.55) else trap.Color
		end
	elseif kind == "Wind" and trap.Gusts then
		local on = cycle(trap, t) < trap.Duty
		local state = if on then 1 else 0
		if trap.Visual ~= state then
			trap.Visual = state
			for _, emitter in trap.Emitters do
				emitter.Enabled = on
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Géométrie du personnage
------------------------------------------------------------------------------------

-- Distance d'un point à une pièce (0 ou négatif = dedans), selon sa forme.
local function distanceTo(cf: CFrame, size: Vector3, shape: Enum.PartType, point: Vector3): number
	local lp = cf:PointToObjectSpace(point)
	local half = size / 2
	if shape == Enum.PartType.Ball then
		return lp.Magnitude - math.min(half.X, half.Y, half.Z)
	elseif shape == Enum.PartType.Cylinder then
		local radial = math.sqrt(lp.Y * lp.Y + lp.Z * lp.Z) - math.min(half.Y, half.Z)
		local axial = math.abs(lp.X) - half.X
		if radial <= 0 and axial <= 0 then
			return math.max(radial, axial)
		end
		local r, a = math.max(radial, 0), math.max(axial, 0)
		return math.sqrt(r * r + a * a)
	end
	local dx = math.max(math.abs(lp.X) - half.X, 0)
	local dy = math.max(math.abs(lp.Y) - half.Y, 0)
	local dz = math.max(math.abs(lp.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function touches(trap: Trap, feet: Vector3): boolean
	-- Test grossier d'abord : le corps (≈ 5,3 studs de haut) est-il près de la sphère englobante ?
	if (trap.Current.Position - feet).Magnitude > trap.Bound + 6 then
		return false
	end
	for _, solid in trap.Solids do
		local cf = trap.Current * solid.Offset
		for _, h in BODY_SAMPLES do
			if distanceTo(cf, solid.Size, solid.Shape, feet + Vector3.new(0, h, 0)) <= BODY_RADIUS then
				return true
			end
		end
	end
	return false
end

-- Les pieds reposent sur le dessus de la plateforme (repère `cf`, haut = Y local).
local function standsOn(trap: Trap, cf: CFrame, feet: Vector3): boolean
	local lp = cf:PointToObjectSpace(feet)
	local half = trap.Size / 2
	return math.abs(lp.X) <= half.X + 0.6
		and math.abs(lp.Z) <= half.Z + 0.6
		and lp.Y >= half.Y - 0.8
		and lp.Y <= half.Y + 1.2
end

local function inside(trap: Trap, point: Vector3): boolean
	local lp = trap.Current:PointToObjectSpace(point)
	local half = trap.Size / 2
	return math.abs(lp.X) <= half.X and math.abs(lp.Y) <= half.Y and math.abs(lp.Z) <= half.Z
end

local function feetOf(root: BasePart, hum: Humanoid): Vector3
	local hip = if hum.RigType == Enum.HumanoidRigType.R6 then 3 else hum.HipHeight + root.Size.Y / 2
	return root.Position - Vector3.new(0, hip, 0)
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

------------------------------------------------------------------------------------
-- Plateformes qui s'effacent (pour le joueur local seulement)
------------------------------------------------------------------------------------

local function setHidden(trap: Trap, hidden: boolean)
	trap.Hidden = hidden
	for _, solid in trap.Solids do
		solid.Part.LocalTransparencyModifier = if hidden then 0.85 else 0
	end
	trap.Part.CanCollide = not hidden
end

local function updateVanish(trap: Trap, now: number)
	local start = trap.VanishAt
	if not start or trap.Removed then
		vanishing[trap] = nil
		return
	end
	local elapsed = now - start
	if elapsed < trap.Delay then
		-- Clignote avant de disparaître
		local blink = not reducedMotion() and math.floor(elapsed * 10) % 2 == 1
		for _, solid in trap.Solids do
			solid.Part.LocalTransparencyModifier = if blink then 0.5 else 0.15
		end
	elseif elapsed < trap.Delay + trap.Respawn then
		if not trap.Hidden then
			setHidden(trap, true)
		end
	else
		setHidden(trap, false)
		trap.VanishAt = nil
		vanishing[trap] = nil
	end
end

------------------------------------------------------------------------------------
-- Boucle
------------------------------------------------------------------------------------

local function refresh()
	local camera = Workspace.CurrentCamera
	local root = rootPart
	local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
	local rootPos = if root then root.Position else nil
	table.clear(animated)
	table.clear(nearby)
	reduced = player:GetAttribute("ReducedMotion") == true
	local skipDecor = reduced
	for _, trap in traps do
		-- Distance à la boîte de repos (et non au centre) : le vide, immense, reste suivi partout.
		local size = trap.Size
		local near = rootPos ~= nil
			and distanceTo(trap.Rest, size, Enum.PartType.Block, rootPos) <= trap.Radius + INTERACT_MARGIN
		local seen = distanceTo(trap.Rest, size, Enum.PartType.Block, cameraPos) <= trap.Radius + ANIMATE_RADIUS
		if near then
			table.insert(nearby, trap)
		end
		if MOVING[trap.Kind] and not (skipDecor and trap.Kind == "Spin") then
			if near or seen then
				table.insert(animated, trap)
			end
		elseif seen and not near then
			table.insert(animated, trap) -- effets visuels seulement (décharges, chaleur, rafales)
		end
	end
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function step(dt: number)
	local t = Workspace:GetServerTimeNow()
	local now = t -- même horloge pour les délais locaux (effacements, anti-rebond)
	local root, hum = rootPart, humanoid
	local alive = root ~= nil and hum ~= nil and hum.Health > 0 and root.Parent ~= nil
	local feet = if alive and root and hum then feetOf(root, hum) else Vector3.zero

	-- 1. Nouvelles poses des pièges mobiles ; transport du personnage par les Mover
	table.clear(moveParts)
	table.clear(moveFrames)
	local carry = Vector3.zero
	for _, trap in animated do
		if not trap.Removed then
			if MOVING[trap.Kind] then
				local nextCf = poseAt(trap, t)
				if trap.Kind == "Mover" and alive and standsOn(trap, trap.Current, feet) then
					carry += nextCf.Position - trap.Current.Position
				end
				trap.Next = nextCf
				table.insert(moveParts, trap.Part)
				table.insert(moveFrames, nextCf)
			else
				updateVisual(trap, t)
			end
		end
	end
	for _, trap in nearby do
		if not trap.Removed and not MOVING[trap.Kind] then
			updateVisual(trap, t)
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		for _, trap in animated do
			if MOVING[trap.Kind] then
				trap.Current = trap.Next
			end
		end
	end
	for trap in vanishing do
		updateVanish(trap, now)
	end
	if not alive or not root or not hum then
		return
	end

	-- 2. Personnage local : poussées, rebonds, effacements, contacts mortels
	local push = Vector3.zero
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	for _, trap in nearby do
		if trap.Removed then
			continue
		end
		local kind = trap.Kind
		if LETHAL[kind] then
			if isActive(trap, t) and touches(trap, feet) then
				die(trap.Cause)
				return
			end
		elseif kind == "Conveyor" then
			if grounded and standsOn(trap, trap.Current, feet) then
				push += trap.Direction * trap.Speed
			end
		elseif kind == "Wind" then
			if (not trap.Gusts or cycle(trap, t) < trap.Duty) and inside(trap, root.Position) then
				push += trap.Direction * trap.Strength
			end
		elseif kind == "Bounce" then
			if now - lastBounce > 0.4 and root.AssemblyLinearVelocity.Y < 20 and standsOn(trap, trap.Current, feet) then
				lastBounce = now
				local v = root.AssemblyLinearVelocity
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
				root.AssemblyLinearVelocity = Vector3.new(v.X, trap.Power, v.Z)
			end
		elseif kind == "Vanish" then
			if not trap.VanishAt and not trap.Hidden and grounded and standsOn(trap, trap.Current, feet) then
				trap.VanishAt = now
				vanishing[trap] = true
			end
		end
	end
	local move = carry + push * dt
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
