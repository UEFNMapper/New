--!strict
--[[
	Traps/FirewallWall : mur pare-feu percé qui avance (monde 7). Aller-retour doux le long
	d'Offset (comme Laser / Mover : Period défaut 6, Phase). Mortel, SAUF dans les trous.

	Deux façons de faire les trous :
	- attribut Holes = "x,y,l,h;x,y,l,h" (studs, repère local du mur : x selon X, y selon Y, centre
	  du mur = 0,0 ; l × h = taille du trou). La racine donne l'étendue du mur (fine selon Z) : le
	  client la cache et construit un mur de briques orange avec des cadres VERTS autour des trous ;
	- sans Holes, si la racine a des pièces soudées : le mur est ces pièces (trous = espaces vides).
	Sans rien de tout ça : une porte de 6 × 7 au sol, au centre.
	Conseils : trous ≥ 5 × 6,5 studs posés au sol (ou à hauteur de saut), vitesse max
	π × |Offset| / Period ≤ 8 studs/s.
]]

local Common = require(script.Parent.Common)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler

local FirewallWall = {}

type Hole = { X: number, Y: number, W: number, H: number }
type WallData = { Holes: { Hole }, Built: boolean }

local BRICK = Color3.fromRGB(232, 84, 52)
local FLAME = Color3.fromRGB(255, 150, 60)
local SAFE = Color3.fromRGB(72, 220, 120)

local function parseHoles(text: any): { Hole }
	local holes = {}
	if type(text) ~= "string" then
		return holes
	end
	for chunk in string.gmatch(text, "[^;]+") do
		local values = {}
		for number in string.gmatch(chunk, "[^,]+") do
			table.insert(values, tonumber(number))
		end
		local x, y, w, h = values[1], values[2], values[3], values[4]
		if x and y and w and h and w > 0 and h > 0 then
			table.insert(holes, { X = x, Y = y, W = w, H = h })
		end
	end
	return holes
end

local function setup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 6), 0.5)
	local holes = parseHoles(part:GetAttribute("Holes"))
	local welded = #trap.Solids > 1
	if #holes == 0 and not welded then
		-- Porte par défaut : on ne fabrique jamais un mur infranchissable
		local size = part.Size
		holes = { { X = 0, Y = -size.Y / 2 + 3.5, W = math.min(6, size.X), H = math.min(7, size.Y) } }
	end
	trap.Data = { Holes = holes, Built = false } :: WallData
end

local function pose(trap: Trap, t: number): CFrame
	return trap.Rest + trap.Offset * Common.Swing(Common.Cycle(trap, t))
end

-- Le point (repère local du mur) est-il dans un trou ?
function FirewallWall.InHole(trap: Trap, x: number, y: number): boolean
	for _, hole in (trap.Data :: WallData).Holes do
		if math.abs(x - hole.X) <= hole.W / 2 and math.abs(y - hole.Y) <= hole.H / 2 then
			return true
		end
	end
	return false
end

local function hits(trap: Trap, _f: Ctx, feet: Vector3): boolean
	local d = trap.Data :: WallData
	if #d.Holes == 0 then
		return Common.Touches(trap, feet)
	end
	local half = trap.Size / 2
	local r = Common.BODY_RADIUS
	for _, h in Common.BODY_SAMPLES do
		local lp = trap.Current:PointToObjectSpace(feet + Vector3.new(0, h, 0))
		if
			math.abs(lp.Z) <= half.Z + r
			and math.abs(lp.X) <= half.X + r
			and math.abs(lp.Y) <= half.Y + r
			and not FirewallWall.InHole(trap, lp.X, lp.Y)
		then
			return true
		end
	end
	return false
end

-- Découpe le mur (moins les trous) en rectangles : bandes verticales entre les bords des trous.
function FirewallWall.Panels(width: number, height: number, holes: { Hole }): { Hole }
	local xs = { -width / 2, width / 2 }
	for _, hole in holes do
		table.insert(xs, math.clamp(hole.X - hole.W / 2, -width / 2, width / 2))
		table.insert(xs, math.clamp(hole.X + hole.W / 2, -width / 2, width / 2))
	end
	table.sort(xs)
	local panels = {}
	for i = 1, #xs - 1 do
		local x0, x1 = xs[i], xs[i + 1]
		if x1 - x0 > 0.05 then
			local mid = (x0 + x1) / 2
			local cuts = {}
			for _, hole in holes do
				if math.abs(mid - hole.X) < hole.W / 2 then
					table.insert(cuts, { hole.Y - hole.H / 2, hole.Y + hole.H / 2 })
				end
			end
			table.sort(cuts, function(a, b)
				return a[1] < b[1]
			end)
			local y = -height / 2
			for _, cut in cuts do
				local top = math.min(cut[1], height / 2)
				if top - y > 0.05 then
					table.insert(panels, { X = mid, Y = (y + top) / 2, W = x1 - x0, H = top - y })
				end
				y = math.max(y, cut[2])
			end
			if height / 2 - y > 0.05 then
				table.insert(panels, { X = mid, Y = (y + height / 2) / 2, W = x1 - x0, H = height / 2 - y })
			end
		end
	end
	return panels
end

local function build(trap: Trap, _f: Ctx)
	local d = trap.Data :: WallData
	if #d.Holes == 0 then
		return
	end
	d.Built = true
	local rig = Common.RigOf(trap)
	Common.HideRoot(trap)
	local size = trap.Size
	local depth = size.Z
	local function add(x: number, y: number, w: number, h: number, z: number, color: Color3, material: Enum.Material)
		local offset = CFrame.new(x, y, z)
		local partSize = Vector3.new(w, h, depth)
		local part = Common.NewPart("Part", rig, partSize, trap.Current * offset, color, material)
		Common.AddPiece(trap, part, partSize, trap.Current, false, offset)
	end
	for _, panel in FirewallWall.Panels(size.X, size.Y, d.Holes) do
		add(panel.X, panel.Y, panel.W, panel.H, 0, BRICK, Enum.Material.Brick)
	end
	-- Crête de flammes en haut du mur
	add(0, size.Y / 2 + 0.3, size.X, 0.6, 0, FLAME, Enum.Material.Neon)
	-- Cadres verts autour des trous : « passe ici ! »
	for _, hole in d.Holes do
		local t = 0.35
		add(hole.X, hole.Y + hole.H / 2 - t / 2, hole.W, t, 0, SAFE, Enum.Material.Neon)
		add(hole.X, hole.Y - hole.H / 2 + t / 2, hole.W, t, 0, SAFE, Enum.Material.Neon)
		add(hole.X - hole.W / 2 + t / 2, hole.Y, t, hole.H, 0, SAFE, Enum.Material.Neon)
		add(hole.X + hole.W / 2 - t / 2, hole.Y, t, hole.H, 0, SAFE, Enum.Material.Neon)
	end
end

local function update(trap: Trap, _f: Ctx)
	for _, piece in trap.Pieces do
		piece.Next = trap.Next
	end
end

FirewallWall.Handlers = {
	FirewallWall = { Lethal = true, Setup = setup, Build = build, Pose = pose, Update = update, Hits = hits },
} :: { [string]: Handler }

return FirewallWall
