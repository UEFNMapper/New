--!strict
--[[
	Traps/Cursor : curseur géant de LAGZ (monde 7). Côté client : chaque joueur voit SON curseur,
	qui le vise lui. La racine n'est qu'un repère : la zone surveillée est une boîte centrée sur elle
	(attribut Area, Vector3 ; défaut = taille de la pièce).

	Cycle de Period s (défaut 4, min 2,5) :
	  1. suivi : l'anneau blanc suit les pieds du joueur (s'il est dans la zone), le curseur plane ;
	  2. visée (1 s) : la cible se VERROUILLE, l'anneau devient rouge et un disque se remplit
	     jusqu'au clic ; le curseur descend ;
	  3. clic (0,25 s) : MORTEL dans un cylindre de Radius studs (défaut 4) autour de la cible ;
	  4. remontée (0,45 s).
	Pour survivre : sortir de l'anneau pendant la seconde de visée (16 studs/s → 16 studs).
	FREEZE fige tout (y compris le suivi) ; hors de la zone, le curseur ne vise personne.
]]

local Common = require(script.Parent.Common)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler
type Piece = Common.Piece

local Cursor = {}

local WARN, CLICK, RISE = 1.0, 0.25, 0.45
local HOVER, LOW = 14, 4 -- hauteur de la pointe au-dessus de la cible (survol, fin de visée)
local TILT = 0.35
Cursor.TRACK, Cursor.WARN, Cursor.CLICK, Cursor.RISE = 1, 2, 3, 4
Cursor.WARN_SECONDS = WARN

local RED = Color3.fromRGB(245, 60, 70)
local WATCH = Color3.fromRGB(233, 216, 253)
local ARROW = Color3.fromRGB(250, 250, 252)
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- cylindre couché : axe vertical

type CursorData = {
	Area: Vector3,
	Radius: number,
	Target: Vector3?,
	TargetCycle: number,
	Lock: Vector3?,
	LockCycle: number,
	Arrow: { Piece },
	ArrowLocal: { CFrame },
	Ring: Piece?,
	Charge: Piece?,
}

local function setup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 4), WARN + CLICK + RISE + 0.8)
	local area = Common.Vec(part, "Area", part.Size)
	trap.Data = {
		Area = area,
		Radius = math.clamp(Common.Num(part, "Radius", 4), 1, 12),
		Target = nil,
		TargetCycle = -math.huge,
		Lock = nil,
		LockCycle = -math.huge,
		Arrow = {},
		ArrowLocal = {},
		Ring = nil,
		Charge = nil,
	} :: CursorData
	trap.Radius = math.max(trap.Radius, area.Magnitude / 2)
end

-- Phase du cycle, avancement dans la phase (0..1), numéro du cycle.
function Cursor.Phase(trap: Trap, t: number): (number, number, number)
	local u = Common.Cycle(trap, t) * trap.Period
	local track = trap.Period - WARN - CLICK - RISE
	local k = Common.CycleIndex(trap, t)
	if u < track then
		return Cursor.TRACK, u / track, k
	elseif u < track + WARN then
		return Cursor.WARN, (u - track) / WARN, k
	elseif u < track + WARN + CLICK then
		return Cursor.CLICK, (u - track - WARN) / CLICK, k
	end
	return Cursor.RISE, (u - track - WARN - CLICK) / RISE, k
end

local function inArea(trap: Trap, feet: Vector3): boolean
	local d = trap.Data :: CursorData
	local lp = trap.Rest:PointToObjectSpace(feet)
	return math.abs(lp.X) <= d.Area.X / 2
		and math.abs(lp.Z) <= d.Area.Z / 2
		and lp.Y >= -d.Area.Y / 2 - 1
		and lp.Y <= d.Area.Y / 2 + 6
end

-- Cible courante (verrouillée pendant la visée et le clic), ou nil.
function Cursor.LockOf(trap: Trap): Vector3?
	return (trap.Data :: CursorData).Lock
end

local function track(trap: Trap, f: Ctx)
	local d = trap.Data :: CursorData
	local phase, _, k = Cursor.Phase(trap, f.T)
	if phase == Cursor.TRACK then
		if f.Alive and inArea(trap, f.Feet) then
			local target = d.Target
			if not target or d.TargetCycle ~= k then
				d.Target = f.Feet
			elseif f.Advanced then
				d.Target = target:Lerp(f.Feet, math.min(1, f.Dt * 10))
			end
			d.TargetCycle = k
		else
			d.Target = nil
		end
	elseif d.LockCycle ~= k then
		-- Verrouillage (une fois par cycle) : la cible ne bouge plus jusqu'au clic
		d.LockCycle = k
		d.Lock = if d.TargetCycle == k then d.Target else nil
		d.Target = nil
		if d.Lock then
			Common.Cue(trap, "Warn", k)
		end
	end
end

local function hits(trap: Trap, f: Ctx, feet: Vector3): boolean
	local d = trap.Data :: CursorData
	local phase, _, k = Cursor.Phase(trap, f.T)
	local lock = d.Lock
	if phase ~= Cursor.CLICK or not lock or d.LockCycle ~= k then
		return false
	end
	local flat = (feet - lock) * Vector3.new(1, 0, 1)
	return flat.Magnitude <= d.Radius and feet.Y >= lock.Y - 2 and feet.Y <= lock.Y + 6
end

------------------------------------------------------------------------------------
-- Habillage : flèche de souris (contour noir) + anneau au sol + disque de charge
------------------------------------------------------------------------------------

local function build(trap: Trap, _f: Ctx)
	local d = trap.Data :: CursorData
	local rig = Common.RigOf(trap)
	Common.HideRoot(trap)
	local model = Common.Make("Model", { Name = "Arrow" }, rig)
	-- Repère de la flèche : pointe à l'origine, corps vers +Y, épaisseur selon Z.
	local H, W, T = 6, 3, 0.8
	local wedge = Vector3.new(T, W, H)
	local shapes = {
		{
			Class = "WedgePart",
			Size = wedge,
			Local = CFrame.fromMatrix(Vector3.new(W / 2, H / 2, 0), Vector3.zAxis, Vector3.xAxis, Vector3.yAxis),
		},
		{
			Class = "WedgePart",
			Size = wedge,
			Local = CFrame.fromMatrix(Vector3.new(-W / 2, H / 2, 0), -Vector3.zAxis, -Vector3.xAxis, Vector3.yAxis),
		},
		{ Class = "Part", Size = Vector3.new(1.8, 4.5, T), Local = CFrame.new(0, H * 0.7 + 2.25, 0) },
	}
	for _, shape in shapes do
		local part = Common.NewPart(shape.Class, model, shape.Size, trap.Rest, ARROW, Enum.Material.SmoothPlastic)
		table.insert(d.Arrow, Common.AddPiece(trap, part, shape.Size, trap.Rest, false))
		table.insert(d.ArrowLocal, shape.Local)
	end
	Common.Make("Highlight", {
		Adornee = model,
		FillTransparency = 1,
		OutlineColor = Color3.new(0, 0, 0),
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	}, model)
	local diameter = d.Radius * 2
	local ringSize = Vector3.new(0.2, diameter, diameter)
	local ring = Common.NewPart("Part", rig, ringSize, trap.Rest, WATCH, Enum.Material.Neon, 1)
	ring.Name = "Ring"
	Common.Cylinder(ring)
	d.Ring = Common.AddPiece(trap, ring, ringSize, trap.Rest, false, FLAT)
	local charge = Common.NewPart("Part", rig, Vector3.new(0.22, 0.2, 0.2), trap.Rest, RED, Enum.Material.Neon, 1)
	charge.Name = "Charge"
	Common.Cylinder(charge)
	d.Charge = Common.AddPiece(trap, charge, ringSize, trap.Rest, false, FLAT)
end

local function update(trap: Trap, f: Ctx)
	track(trap, f)
	local d = trap.Data :: CursorData
	local ring, charge = d.Ring, d.Charge
	if not ring or not charge then
		return
	end
	local phase, progress = Cursor.Phase(trap, f.T)
	local focus = if phase == Cursor.TRACK then d.Target else d.Lock
	local idle = trap.Rest:PointToWorldSpace(Vector3.new(0, -d.Area.Y / 2, 0))
	local height = HOVER + math.sin(f.T * 2) * 0.6
	if focus and phase == Cursor.WARN then
		height = HOVER - (HOVER - LOW) * Common.Smooth(progress)
	elseif focus and phase == Cursor.CLICK then
		height = LOW * math.max(0, 1 - progress * 4)
	elseif focus and phase == Cursor.RISE then
		height = HOVER * Common.Smooth(progress)
	end
	-- Flèche tournée vers la caméra, légèrement penchée comme un pointeur de souris
	local tip = (focus or idle) + Vector3.new(0, height, 0)
	local toCamera = (f.Camera - tip) * Vector3.new(1, 0, 1)
	local back = if toCamera.Magnitude > 0.1 then toCamera.Unit else Vector3.zAxis
	local frame = CFrame.fromMatrix(tip, Vector3.yAxis:Cross(back), Vector3.yAxis, back) * CFrame.Angles(0, 0, TILT)
	for i, piece in d.Arrow do
		piece.Next = frame * d.ArrowLocal[i]
		Common.SetAlpha(piece, 0)
	end
	-- Anneau au sol et disque de charge
	if not focus then
		Common.SetAlpha(ring, 1)
		Common.SetAlpha(charge, 1)
		return
	end
	local ground = CFrame.new(focus + Vector3.new(0, 0.1, 0))
	ring.Next = ground
	charge.Next = ground + Vector3.new(0, 0.04, 0)
	local diameter = d.Radius * 2
	if phase == Cursor.TRACK then
		Common.SetTint(ring, WATCH)
		Common.SetAlpha(ring, 0.7)
		Common.SetAlpha(charge, 1)
	elseif phase == Cursor.WARN then
		Common.SetTint(ring, RED)
		Common.SetAlpha(ring, if Common.Blink(f.T, 4, f.Reduced) then 0.35 else 0.55)
		local size = math.max(diameter * progress, 0.2)
		charge.Part.Size = Vector3.new(0.22, size, size)
		Common.SetAlpha(charge, 0.3)
	elseif phase == Cursor.CLICK then
		Common.Cue(trap, "Click", Common.CycleIndex(trap, f.T))
		Common.SetAlpha(ring, 0.05)
		charge.Part.Size = Vector3.new(0.22, diameter, diameter)
		Common.SetAlpha(charge, 0.1)
	else
		Common.SetAlpha(ring, 0.4 + 0.6 * progress)
		Common.SetAlpha(charge, 1)
	end
end

Cursor.Handlers = {
	Cursor = { Lethal = true, Setup = setup, Build = build, Update = update, Hits = hits },
} :: { [string]: Handler }

return Cursor
