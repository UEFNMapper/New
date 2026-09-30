--!strict
--[[
	Traps/Classic : les 11 pièges d'origine (+ Hazard, danger statique, et Spin, moyeu décoratif).

	- Zapper / Heat : mortels pendant la phase active (Period, Duty, Phase) ; clignotent avant.
	  SURCHAUFFE : toutes les bouches de chaleur (Heat) sont actives.
	- SpinBar / Spin : rotation (Speed rad/s, Axis local) ; Spin = décor (ignoré en ReducedMotion).
	- Crusher : va-et-vient rapide (Offset, Period, Phase), s'éclaircit avant de tomber.
	- Mover (porteur) / Laser : aller-retour doux (Offset, Period, Phase).
	- Virus : patrouille en boucle (Waypoints, Speed, Phase = fraction de boucle).
	- Vanish : s'efface après contact (Delay, Respawn) pour le joueur local seulement.
	- Wind (Direction, Strength, rafales Period / Duty optionnelles) : SURCHAUFFE = force × 2
	  (plafonnée sous la vitesse de marche) ; Conveyor (Direction, Speed) ; Bounce (Power).
	  FREEZE : ventilateurs et tapis s'arrêtent aussi.
]]

local Common = require(script.Parent.Common)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler

local Classic = {}

local TWO_PI = Common.TWO_PI
local cycle = Common.Cycle
local WIND_CAP = Common.WALK_SPEED - 1 -- on peut toujours avancer contre le vent

------------------------------------------------------------------------------------
-- Poses
------------------------------------------------------------------------------------

local function spinPose(trap: Trap, t: number): CFrame
	local angle = (trap.Speed * t + trap.Phase * TWO_PI) % TWO_PI
	return trap.Rest * CFrame.fromAxisAngle(trap.Axis, angle)
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

local function crushPose(trap: Trap, t: number): CFrame
	return trap.Rest + trap.Offset * crushProfile(cycle(trap, t))
end

local function swingPose(trap: Trap, t: number): CFrame
	return trap.Rest + trap.Offset * Common.Swing(cycle(trap, t))
end

local function virusPose(trap: Trap, t: number): CFrame
	if trap.Loop <= 0 then
		return trap.Rest
	end
	local s = (t * trap.Speed + trap.Phase * trap.Loop) % trap.Loop
	local point = Common.PathPoint(trap.Path, trap.Cumulative, s, true)
	local spin = CFrame.Angles(0, (t * 2) % TWO_PI, 0)
	return CFrame.new(trap.Rest.Position + point) * trap.Rest.Rotation * spin
end

------------------------------------------------------------------------------------
-- Décharges et chaleur
------------------------------------------------------------------------------------

local function pulseActive(trap: Trap, f: Ctx): boolean
	if trap.Kind == "Heat" and f.Incident == "Overheat" then
		return true
	end
	return cycle(trap, f.T) < trap.Duty
end

local function setTransparency(trap: Trap, value: number)
	if trap.Visual ~= value then
		trap.Visual = value
		trap.Part.Transparency = value
	end
end

-- Signal visuel : actif = visible, juste avant = clignote, repos = fantôme.
local function pulseVisual(trap: Trap, f: Ctx)
	local base = trap.Solids[1].Transparency
	local p = cycle(trap, f.T)
	-- SURCHAUFFE annoncée : toutes les bouches clignotent pendant l'annonce
	local overheat = trap.Kind == "Heat" and f.Incoming == "Overheat"
	if pulseActive(trap, f) then
		setTransparency(trap, base)
	elseif (1 - p) * trap.Period < Common.TELEGRAPH or overheat then
		Common.Cue(trap, "Warn", Common.CycleIndex(trap, f.T))
		setTransparency(trap, if Common.Blink(f.T, 7, f.Reduced) then 0.6 else 0.88)
	else
		setTransparency(trap, if trap.Kind == "Heat" then 0.97 else 0.9)
	end
end

------------------------------------------------------------------------------------
-- Écraseur : s'éclaircit en clignotant avant de tomber (au moins TELEGRAPH s)
------------------------------------------------------------------------------------

local function crushVisual(trap: Trap, f: Ctx)
	local p = cycle(trap, f.T)
	local window = math.min(Common.TELEGRAPH / trap.Period, 0.45)
	local warn = p >= 0.45 - window and p < 0.45 and Common.Blink(f.T, 6, f.Reduced)
	local state = if warn then 1 else 0
	if trap.Visual ~= state then
		trap.Visual = state
		trap.Part.Color = if warn then trap.Color:Lerp(Color3.new(1, 1, 1), 0.55) else trap.Color
	end
end

------------------------------------------------------------------------------------
-- Poussées, rebonds, effacements
------------------------------------------------------------------------------------

local function inside(trap: Trap, point: Vector3): boolean
	local lp = trap.Current:PointToObjectSpace(point)
	local half = trap.Size / 2
	return math.abs(lp.X) <= half.X and math.abs(lp.Y) <= half.Y and math.abs(lp.Z) <= half.Z
end

local function windOn(trap: Trap, f: Ctx): boolean
	return f.Incident ~= "Freeze" and (not trap.Gusts or cycle(trap, f.T) < trap.Duty)
end

-- Force du vent (SURCHAUFFE : × 2, plafonnée pour rester franchissable).
function Classic.WindStrength(trap: Trap, f: Ctx): number
	if f.Incident == "Overheat" then
		return math.min(trap.Strength * 2, math.max(trap.Strength, WIND_CAP))
	end
	return trap.Strength
end

local function windVisual(trap: Trap, f: Ctx)
	if not trap.Gusts and f.Incident ~= "Freeze" and trap.Visual == -1 then
		return
	end
	local on = windOn(trap, f)
	local state = if on then 1 else 0
	if trap.Visual ~= state then
		trap.Visual = state
		for _, emitter in trap.Emitters do
			emitter.Enabled = on
		end
	end
end

local function windPush(trap: Trap, f: Ctx, _feet: Vector3)
	local root = f.Root
	if root and windOn(trap, f) and inside(trap, root.Position) then
		f.Push += trap.Direction * Classic.WindStrength(trap, f)
	end
end

local function conveyorPush(trap: Trap, f: Ctx, feet: Vector3)
	if f.Incident ~= "Freeze" and f.Grounded and Common.StandsOn(trap.Current, trap.Size, feet) then
		f.Push += trap.Direction * trap.Speed
	end
end

local lastBounce = -math.huge

local function bounce(trap: Trap, f: Ctx, feet: Vector3)
	local root, hum = f.Root, f.Humanoid
	if not root or not hum then
		return
	end
	if
		f.Now - lastBounce > 0.4
		and root.AssemblyLinearVelocity.Y < 20
		and Common.StandsOn(trap.Current, trap.Size, feet)
	then
		lastBounce = f.Now
		local v = root.AssemblyLinearVelocity
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		root.AssemblyLinearVelocity = Vector3.new(v.X, trap.Power, v.Z)
	end
end

-- Plateformes qui s'effacent (pour le joueur local seulement), sur l'horloge du monde.
Classic.Vanishing = {} :: { [Trap]: boolean }

local function setHidden(trap: Trap, hidden: boolean)
	trap.Hidden = hidden
	for _, solid in trap.Solids do
		solid.Part.LocalTransparencyModifier = if hidden then 0.85 else 0
	end
	trap.Part.CanCollide = not hidden
end

local function vanishTouch(trap: Trap, f: Ctx, feet: Vector3)
	if not trap.VanishAt and not trap.Hidden and f.Grounded and Common.StandsOn(trap.Current, trap.Size, feet) then
		trap.VanishAt = f.T
		Classic.Vanishing[trap] = true
	end
end

-- Appelé à chaque image pour chaque bloc en cours d'effacement (t = horloge de son monde).
function Classic.UpdateVanish(trap: Trap, t: number, reduced: boolean)
	local start = trap.VanishAt
	if not start or trap.Removed then
		Classic.Vanishing[trap] = nil
		return
	end
	local elapsed = t - start
	if elapsed < trap.Delay then
		-- Clignote avant de disparaître
		local blink = not reduced and math.floor(elapsed * 10) % 2 == 1
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
		Classic.Vanishing[trap] = nil
	end
end

------------------------------------------------------------------------------------
-- Table des types
------------------------------------------------------------------------------------

Classic.Handlers = {
	Zapper = { Lethal = true, Active = pulseActive, Update = pulseVisual },
	Heat = { Lethal = true, Active = pulseActive, Update = pulseVisual },
	SpinBar = { Lethal = true, Pose = spinPose },
	Spin = { Decor = true, Pose = spinPose },
	Crusher = { Lethal = true, Pose = crushPose, Update = crushVisual },
	Mover = { Carrier = true, Pose = swingPose },
	Laser = { Lethal = true, Pose = swingPose },
	Virus = { Lethal = true, Pose = virusPose },
	Vanish = { Interact = vanishTouch },
	Wind = { Update = windVisual, Interact = windPush },
	Conveyor = { Interact = conveyorPush },
	Bounce = { Interact = bounce },
	Hazard = { Lethal = true },
} :: { [string]: Handler }

return Classic
