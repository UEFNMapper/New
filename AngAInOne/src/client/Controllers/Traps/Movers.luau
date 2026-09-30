--!strict
--[[
	Traps/Movers : pièges v2 dont seule la RACINE bouge (pose = fonction pure de l'horloge).

	- Surge (mortel) : une impulsion électrique se charge 0,8 s au début du câble (clignote), puis
	  court le long des Waypoints (chemin ouvert) à Speed studs/s, puis disparaît jusqu'au cycle
	  suivant. Période par défaut : longueur / Speed + 2 s. Phase optionnelle.
	- Flood (mortel) : plan de « fuite mémoire » qui monte de Rise studs puis redescend.
	  Cycle : 10 % en bas, 55 % de montée régulière, 15 % en haut, 20 % de vidange.
	  Il s'éclaircit en clignotant 0,8 s avant de monter.
	- Defrag (sûr, porteur) : bloc qui coulisse de case en case le long des Waypoints (boucle),
	  Step secondes par case : 60 % de pause puis 40 % de glissement ; il blanchit avant de partir.
	- DustBall (mortel) : boule qui ROULE en boucle sur les Waypoints à Speed studs/s.
	- Pendulum (mortel) : pioche qui se balance autour de Pivot (décalage MONDE depuis la position
	  de repos = bas du balancier), axe local Axis (défaut X), Amplitude en degrés.
	- LagMover (sûr, porteur) : comme Mover mais par à-coups : Steps sauts par période, chaque saut
	  occupe les 20 derniers % de son pas (le reste : immobile) ; flash blanc juste avant.
]]

local Common = require(script.Parent.Common)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler

local Movers = {}

local TWO_PI = Common.TWO_PI
local TELEGRAPH = Common.TELEGRAPH
local cycle = Common.Cycle
local WHITE = Color3.new(1, 1, 1)

local function setTransparency(trap: Trap, value: number)
	if trap.Visual ~= value then
		trap.Visual = value
		trap.Part.Transparency = value
	end
end

-- Éclaircit la racine (état 1) ou lui rend sa couleur (état 0).
local function flash(trap: Trap, on: boolean)
	local state = if on then 1 else 0
	if trap.Visual ~= state then
		trap.Visual = state
		trap.Part.Color = if on then trap.Color:Lerp(WHITE, 0.6) else trap.Color
	end
end

------------------------------------------------------------------------------------
-- Surge : impulsion le long d'un câble
------------------------------------------------------------------------------------

-- 0 = charge (début du câble, sans danger), 1 = course (mortelle), 2 = repos ; abscisse.
function Movers.SurgeState(trap: Trap, t: number): (number, number)
	local u = cycle(trap, t) * trap.Period
	if u < TELEGRAPH then
		return 0, 0
	end
	local s = (u - TELEGRAPH) * trap.Speed
	if s <= trap.OpenLength then
		return 1, s
	end
	return 2, 0
end

local function surgeSetup(trap: Trap)
	local part = trap.Part
	trap.Speed = math.max(Common.Num(part, "Speed", 14), 1)
	local default = math.max(trap.OpenLength / trap.Speed + TELEGRAPH + 1.2, 3)
	trap.Period = math.max(Common.Num(part, "Period", default), 0.5)
end

local function surgePose(trap: Trap, t: number): CFrame
	local state, s = Movers.SurgeState(trap, t)
	local point = if state == 1 and #trap.Path >= 2
		then Common.PathPoint(trap.Path, trap.OpenCumulative, s, false)
		else (trap.Path[1] or Vector3.zero)
	return CFrame.new(trap.Rest.Position + point) * trap.Rest.Rotation * CFrame.Angles(0, (t * 9) % TWO_PI, 0)
end

local function surgeActive(trap: Trap, f: Ctx): boolean
	return (Movers.SurgeState(trap, f.T)) == 1
end

local function surgeVisual(trap: Trap, f: Ctx)
	local state = Movers.SurgeState(trap, f.T)
	local base = trap.Solids[1].Transparency
	if state == 0 then
		Common.Cue(trap, "Warn", Common.CycleIndex(trap, f.T))
		setTransparency(trap, if Common.Blink(f.T, 6, f.Reduced) then base else 0.6)
	elseif state == 1 then
		setTransparency(trap, base)
	else
		setTransparency(trap, 0.95)
	end
end

------------------------------------------------------------------------------------
-- Flood : fuite mémoire qui monte
------------------------------------------------------------------------------------

local RISE_START, RISE_END, DRAIN_START = 0.1, 0.65, 0.8

function Movers.FloodLevel(p: number): number
	if p < RISE_START then
		return 0
	elseif p < RISE_END then
		return (p - RISE_START) / (RISE_END - RISE_START)
	elseif p < DRAIN_START then
		return 1
	end
	return 1 - Common.Smooth((p - DRAIN_START) / (1 - DRAIN_START))
end

local function floodSetup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 16), 0.5)
	local rise = Common.Num(part, "Rise", 20)
	trap.Data = { Rise = rise }
	trap.Radius = math.max(trap.Radius, math.abs(rise))
end

local function floodPose(trap: Trap, t: number): CFrame
	return trap.Rest + Vector3.yAxis * (trap.Data.Rise * Movers.FloodLevel(cycle(trap, t)))
end

local function floodVisual(trap: Trap, f: Ctx)
	local p = cycle(trap, f.T)
	local before = (RISE_START - p) * trap.Period
	local warn = before > 0 and before < TELEGRAPH
	if warn then
		Common.Cue(trap, "Warn", Common.CycleIndex(trap, f.T))
	end
	flash(trap, warn and Common.Blink(f.T, 5, f.Reduced))
end

------------------------------------------------------------------------------------
-- Defrag : bloc sûr qui coulisse de case en case
------------------------------------------------------------------------------------

local SLIDE = 0.4 -- fraction du pas passée à glisser (en fin de pas)

local function defragSetup(trap: Trap)
	trap.Data = { Step = math.max(Common.Num(trap.Part, "Step", 2), 0.5) }
end

local function defragStep(trap: Trap, t: number): (number, number)
	local n = #trap.Path
	local u = t / trap.Data.Step + trap.Phase * n
	local k = math.floor(u)
	return k, u - k
end

local function defragPose(trap: Trap, t: number): CFrame
	local n = #trap.Path
	if n < 2 then
		return trap.Rest
	end
	local k, f = defragStep(trap, t)
	local alpha = Common.Smooth((f - (1 - SLIDE)) / SLIDE)
	local i = k % n + 1
	return trap.Rest + trap.Path[i]:Lerp(trap.Path[i % n + 1], alpha)
end

local function defragVisual(trap: Trap, f: Ctx)
	if #trap.Path < 2 then
		return
	end
	local _, u = defragStep(trap, f.T)
	local left = (1 - SLIDE - u) * trap.Data.Step -- secondes avant de glisser
	flash(trap, left > 0 and left < 0.5 and Common.Blink(f.T, 5, f.Reduced))
end

------------------------------------------------------------------------------------
-- DustBall : boule de poussière qui roule
------------------------------------------------------------------------------------

local function dustSetup(trap: Trap)
	trap.Speed = math.max(Common.Num(trap.Part, "Speed", 8), 0)
end

local function dustPose(trap: Trap, t: number): CFrame
	if trap.Loop <= 0 then
		return trap.Rest
	end
	local travelled = t * trap.Speed + trap.Phase * trap.Loop
	local point, dir = Common.PathPoint(trap.Path, trap.Cumulative, travelled % trap.Loop, true)
	local radius = math.max(math.min(trap.Size.X, trap.Size.Y, trap.Size.Z) / 2, 0.5)
	-- Roulement sans glisser : axe = haut × direction, angle = distance / rayon
	local axis = Vector3.yAxis:Cross(dir)
	axis = if axis.Magnitude > 1e-3 then axis.Unit else Vector3.xAxis
	local angle = (travelled / radius) % TWO_PI
	return CFrame.new(trap.Rest.Position + point) * CFrame.fromAxisAngle(axis, angle) * trap.Rest.Rotation
end

------------------------------------------------------------------------------------
-- Pendulum : pioche / marteau qui se balance
------------------------------------------------------------------------------------

local function pendulumSetup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 3), 0.5)
	trap.Axis = Common.AxisOf(part, Vector3.xAxis)
	local pivot = Common.Vec(part, "Pivot", Vector3.new(0, 10, 0))
	trap.Data = {
		Amplitude = math.rad(math.clamp(Common.Num(part, "Amplitude", 60), 0, 175)),
		Pivot = pivot,
		WorldAxis = trap.Rest:VectorToWorldSpace(trap.Axis),
	}
	trap.Radius = math.max(trap.Radius, 2 * pivot.Magnitude + part.Size.Magnitude / 2)
end

function Movers.PendulumAngle(trap: Trap, t: number): number
	return trap.Data.Amplitude * math.sin(TWO_PI * cycle(trap, t))
end

local function pendulumPose(trap: Trap, t: number): CFrame
	local pivot = trap.Rest.Position + trap.Data.Pivot
	local turn = CFrame.fromAxisAngle(trap.Data.WorldAxis, Movers.PendulumAngle(trap, t))
	return CFrame.new(pivot) * turn * CFrame.new(-pivot) * trap.Rest
end

------------------------------------------------------------------------------------
-- LagMover : plateforme sûre qui avance par à-coups
------------------------------------------------------------------------------------

local JERK = 0.2 -- fraction de chaque pas occupée par le saut

local function lagSetup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 6), 0.5)
	trap.Data = { Steps = math.max(math.floor(Common.Num(part, "Steps", 5)), 1) }
end

function Movers.LagProgress(trap: Trap, t: number): (number, number)
	local steps = trap.Data.Steps
	local u = cycle(trap, t) * steps
	local k = math.floor(u)
	local f = u - k
	local g = Common.Smooth((f - (1 - JERK)) / JERK)
	return (k + g) / steps, f
end

local function lagPose(trap: Trap, t: number): CFrame
	local q = Movers.LagProgress(trap, t)
	return trap.Rest + trap.Offset * Common.Swing(q)
end

local function lagVisual(trap: Trap, f: Ctx)
	local _, u = Movers.LagProgress(trap, f.T)
	local left = (1 - JERK - u) * trap.Period / trap.Data.Steps
	flash(trap, left > 0 and left < 0.3 and not f.Reduced)
end

Movers.Handlers = {
	Surge = { Lethal = true, Setup = surgeSetup, Pose = surgePose, Active = surgeActive, Update = surgeVisual },
	Flood = { Lethal = true, Setup = floodSetup, Pose = floodPose, Update = floodVisual },
	Defrag = { Carrier = true, Setup = defragSetup, Pose = defragPose, Update = defragVisual },
	DustBall = { Lethal = true, Setup = dustSetup, Pose = dustPose },
	Pendulum = { Lethal = true, Setup = pendulumSetup, Pose = pendulumPose },
	LagMover = { Carrier = true, Setup = lagSetup, Pose = lagPose, Update = lagVisual },
} :: { [string]: Handler }

return Movers
