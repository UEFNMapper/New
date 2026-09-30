--!strict
--[[
	Traps/Spinner : « roue de chargement » (monde 5). La racine est le moyeu : elle tourne sur son
	axe local Axis (défaut Y) à Speed rad/s (défaut 0,6 ; Phase = fraction de tour).
	Autour, le client pose Count patins SÛRS (défaut 8) sur un cercle de rayon Ring (défaut 12),
	de taille PadSize (défaut 5 × 1 × 5) : des disques qui restent À PLAT (grande roue si l'axe est
	horizontal, manège si l'axe est vertical), dégradé de couleur comme l'icône de chargement.
	Porteur : le personnage posé sur un patin (ou sur le moyeu) est transporté.
	Mettre Count = 0 pour n'utiliser que des pièces soudées au moyeu.
]]

local Common = require(script.Parent.Common)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler
type Piece = Common.Piece

local Spinner = {}

local TWO_PI = Common.TWO_PI
local TAIL = Color3.fromRGB(45, 55, 72)
local FLAT = CFrame.Angles(0, 0, math.pi / 2)

type SpinnerData = {
	Count: number,
	Ring: number,
	Pad: Vector3,
	WorldAxis: Vector3,
	U: Vector3,
	V: Vector3,
	Pads: { Piece },
}

local function setup(trap: Trap)
	local part = trap.Part
	trap.Speed = Common.Num(part, "Speed", 0.6)
	trap.Axis = Common.AxisOf(part, Vector3.yAxis)
	local worldAxis = trap.Rest:VectorToWorldSpace(trap.Axis)
	-- Base du plan de la roue (perpendiculaire à l'axe)
	local reference = if math.abs(worldAxis.Y) < 0.9 then Vector3.yAxis else trap.Rest.RightVector
	local u = (reference - worldAxis * reference:Dot(worldAxis)).Unit
	local count = math.clamp(math.floor(Common.Num(part, "Count", 8)), 0, 16)
	local ring = math.max(Common.Num(part, "Ring", 12), 1)
	local pad = Common.Vec(part, "PadSize", Vector3.new(5, 1, 5))
	trap.Data = {
		Count = count,
		Ring = ring,
		Pad = pad,
		WorldAxis = worldAxis,
		U = u,
		V = worldAxis:Cross(u),
		Pads = {},
	} :: SpinnerData
	trap.Radius = math.max(trap.Radius, part.Size.Magnitude / 2, if count > 0 then ring + pad.Magnitude else 0)
end

function Spinner.Angle(trap: Trap, t: number): number
	return (trap.Speed * t + trap.Phase * TWO_PI) % TWO_PI
end

-- Repère (à plat) du patin i à l'instant t.
function Spinner.PadAt(trap: Trap, i: number, t: number): CFrame
	local d = trap.Data :: SpinnerData
	local a = Spinner.Angle(trap, t) + TWO_PI * (i - 1) / d.Count
	local position = trap.Rest.Position + (d.U * math.cos(a) + d.V * math.sin(a)) * d.Ring
	return CFrame.new(position) * trap.Rest.Rotation
end

local function pose(trap: Trap, t: number): CFrame
	return trap.Rest * CFrame.fromAxisAngle(trap.Axis, Spinner.Angle(trap, t))
end

local function build(trap: Trap, f: Ctx)
	local d = trap.Data :: SpinnerData
	if d.Count == 0 then
		return
	end
	local rig = Common.RigOf(trap)
	local size = Vector3.new(d.Pad.Y, d.Pad.X, d.Pad.Z)
	for i = 1, d.Count do
		-- Tête brillante, traîne qui s'assombrit (icône de chargement)
		local fade = (d.Count - i) / d.Count
		local color = trap.Color:Lerp(TAIL, fade * 0.85)
		local cf = Spinner.PadAt(trap, i, f.T)
		local part = Common.NewPart("Part", rig, size, cf * FLAT, color, Enum.Material.Neon)
		part.Name = `Pad{i}`
		Common.Platform(part)
		Common.Cylinder(part)
		part.CanCollide = true
		local piece = Common.AddPiece(trap, part, d.Pad, cf, true, FLAT)
		piece.Collide = true
		piece.Alpha = 0
		table.insert(d.Pads, piece)
	end
end

local function update(trap: Trap, f: Ctx)
	for i, piece in (trap.Data :: SpinnerData).Pads do
		piece.Next = Spinner.PadAt(trap, i, f.T)
	end
end

Spinner.Handlers = {
	Spinner = { Carrier = true, Setup = setup, Build = build, Pose = pose, Update = update },
} :: { [string]: Handler }

return Spinner
