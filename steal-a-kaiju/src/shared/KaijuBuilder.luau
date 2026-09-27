--!strict
-- Fabrique procédurale des modèles de kaijus et d'œufs.
-- Toutes les pièces sont ancrées, sans collision. L'origine du modèle (pièce
-- invisible « Root ») est au sol, au centre ; l'avant regarde vers -Z.
-- Les pièces animables portent un attribut `Role` (Head, Tail, WingL, WingR,
-- Wave, Halo, Squash) et `Phase` ; le client les anime (KaijuAnimator).

local Config = script.Parent.Config
local Kaijus = require(Config.Kaijus)
local Mutations = require(Config.Mutations)
local Rarities = require(Config.Rarities)

local KaijuBuilder = {}

type Ctx = {
	model: Model,
	root: Part,
	s: number,
	primary: Color3,
	secondary: Color3,
	accent: Color3,
	-- points d'ancrage des accessoires (coordonnées locales, échelle 1)
	headTop: Vector3,
	headFront: Vector3,
	headSize: Vector3,
	back: { Vector3 },
	shoulders: { Vector3 },
	mouth: Vector3,
	cheeks: { Vector3 },
	glowParts: { BasePart },
}

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(20, 16, 28)

local function setup(p: BasePart, color: Color3, material: Enum.Material?)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function place(ctx: Ctx, p: BasePart, pos: Vector3, rot: CFrame?)
	local cf = ctx.root.CFrame * CFrame.new(pos * ctx.s)
	if rot then
		cf *= rot
	end
	p.CFrame = cf
	p.Parent = ctx.model
end

local function tag(p: BasePart, role: string?, phase: number?)
	if role then
		p:SetAttribute("Role", role)
		p:SetAttribute("Phase", phase or 0)
	end
end

-- Ellipsoïde (pièce + SpecialMesh sphère qui épouse la taille de la pièce).
local function ell(ctx: Ctx, size: Vector3, pos: Vector3, color: Color3, rot: CFrame?, role: string?, phase: number?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Size = size * ctx.s
	setup(p, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	tag(p, role, phase)
	place(ctx, p, pos, rot)
	return p
end

local function block(ctx: Ctx, size: Vector3, pos: Vector3, color: Color3, rot: CFrame?, role: string?, phase: number?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Size = size * ctx.s
	setup(p, color, material)
	tag(p, role, phase)
	place(ctx, p, pos, rot)
	return p
end

-- Cylindre vertical (axe Y).
local function cyl(ctx: Ctx, height: number, diameter: number, pos: Vector3, color: Color3, rot: CFrame?, role: string?, phase: number?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter) * ctx.s
	setup(p, color, material)
	tag(p, role, phase)
	local r = CFrame.Angles(0, 0, math.rad(90))
	place(ctx, p, pos, if rot then rot * r else r)
	return p
end

local function wedge(ctx: Ctx, size: Vector3, pos: Vector3, color: Color3, rot: CFrame?, role: string?, phase: number?, material: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
	p.Size = size * ctx.s
	setup(p, color, material)
	tag(p, role, phase)
	place(ctx, p, pos, rot)
	return p
end

-- Pointe symétrique (deux cales dos à dos). `rot` oriente la pointe (vers +Y par défaut).
local function spike(ctx: Ctx, base: Vector3, height: number, length: number, thick: number, color: Color3, rot: CFrame?, role: string?, phase: number?, material: Enum.Material?)
	local r = rot or CFrame.identity
	local half = length / 2
	-- partie arrière (arête haute côté centre)
	local backOffset = r:VectorToWorldSpace(Vector3.new(0, height / 2, half / 2))
	wedge(ctx, Vector3.new(thick, height, half), base + backOffset, color, r * CFrame.Angles(0, math.pi, 0), role, phase, material)
	local frontOffset = r:VectorToWorldSpace(Vector3.new(0, height / 2, -half / 2))
	wedge(ctx, Vector3.new(thick, height, half), base + frontOffset, color, r, role, phase, material)
end

local function eye(ctx: Ctx, pos: Vector3, size: number, angry: boolean?)
	local white = ell(ctx, Vector3.new(size, size * 1.1, size * 0.7), pos, WHITE, nil, "Head")
	white:SetAttribute("Eye", true)
	local pupil = ell(ctx, Vector3.new(size * 0.55, size * 0.62, size * 0.4), pos + Vector3.new(0, -size * 0.05, -size * 0.28), BLACK, nil, "Head")
	pupil:SetAttribute("Eye", true)
	local glint = ell(ctx, Vector3.new(size * 0.2, size * 0.2, size * 0.12), pos + Vector3.new(size * 0.12, size * 0.14, -size * 0.45), WHITE, nil, "Head", 0, Enum.Material.Neon)
	glint:SetAttribute("Eye", true)
	if angry then
		local side = if pos.X > 0 then -1 else 1
		local brow = block(ctx, Vector3.new(size * 0.9, size * 0.18, size * 0.2), pos + Vector3.new(0, size * 0.62, -size * 0.3), BLACK, CFrame.Angles(0, 0, math.rad(18 * side)), "Head")
		brow:SetAttribute("Eye", true)
	end
end

local function pair(fn: (sign: number) -> ())
	fn(-1)
	fn(1)
end

----------------------------------------------------------------------------
-- Archétypes
----------------------------------------------------------------------------

local Archetypes: { [string]: (ctx: Ctx, species: Kaijus.Species) -> () } = {}

Archetypes.Rex = function(ctx)
	local P, S = ctx.primary, ctx.secondary
	pair(function(x)
		ell(ctx, Vector3.new(1.0, 1.4, 1.1), Vector3.new(0.72 * x, 0.75, 0.2), P)
		ell(ctx, Vector3.new(1.1, 0.45, 1.45), Vector3.new(0.75 * x, 0.22, -0.15), P)
		for i = -1, 1 do
			ell(ctx, Vector3.new(0.22, 0.22, 0.3), Vector3.new(0.75 * x + i * 0.3, 0.2, -0.85), WHITE)
		end
		ell(ctx, Vector3.new(0.42, 0.95, 0.42), Vector3.new(1.08 * x, 2.35, -0.85), P, CFrame.Angles(math.rad(-35), 0, math.rad(15 * x)))
	end)
	ell(ctx, Vector3.new(2.5, 2.7, 2.3), Vector3.new(0, 2.0, 0.1), P, CFrame.Angles(math.rad(-12), 0, 0))
	ell(ctx, Vector3.new(1.75, 2.1, 0.8), Vector3.new(0, 1.9, -0.85), S, CFrame.Angles(math.rad(-12), 0, 0))
	-- Queue (3 segments)
	ell(ctx, Vector3.new(1.45, 1.25, 1.9), Vector3.new(0, 1.35, 1.35), P, CFrame.Angles(math.rad(12), 0, 0), "Tail", 0)
	ell(ctx, Vector3.new(1.0, 0.85, 1.55), Vector3.new(0, 0.95, 2.55), P, CFrame.Angles(math.rad(10), 0, 0), "Tail", 1)
	ell(ctx, Vector3.new(0.6, 0.5, 1.2), Vector3.new(0, 0.72, 3.45), P, nil, "Tail", 2)
	-- Tête
	ell(ctx, Vector3.new(1.95, 1.65, 1.95), Vector3.new(0, 3.65, -0.7), P, nil, "Head")
	ell(ctx, Vector3.new(1.55, 0.95, 1.3), Vector3.new(0, 3.3, -1.55), P, nil, "Head")
	ell(ctx, Vector3.new(1.3, 0.35, 1.0), Vector3.new(0, 2.95, -1.6), S, nil, "Head")
	pair(function(x)
		ell(ctx, Vector3.new(0.14, 0.1, 0.1), Vector3.new(0.3 * x, 3.55, -2.15), BLACK, nil, "Head")
		eye(ctx, Vector3.new(0.52 * x, 4.02, -1.42), 0.62, true)
	end)
	ctx.headTop = Vector3.new(0, 4.45, -0.7)
	ctx.headFront = Vector3.new(0, 3.4, -2.2)
	ctx.headSize = Vector3.new(1.95, 1.65, 1.95)
	ctx.mouth = Vector3.new(0, 3.05, -2.05)
	ctx.back = {
		Vector3.new(0, 4.35, 0.0),
		Vector3.new(0, 3.3, 0.75),
		Vector3.new(0, 2.25, 1.55),
		Vector3.new(0, 1.55, 2.5),
		Vector3.new(0, 1.05, 3.3),
	}
	ctx.shoulders = { Vector3.new(-1.1, 3.0, 0.2), Vector3.new(1.1, 3.0, 0.2) }
	ctx.cheeks = { Vector3.new(-0.75, 3.45, -1.5), Vector3.new(0.75, 3.45, -1.5) }
end

Archetypes.Quad = function(ctx)
	local P, S = ctx.primary, ctx.secondary
	for _, pos in { Vector3.new(-1.05, 0.7, -1.1), Vector3.new(1.05, 0.7, -1.1), Vector3.new(-1.05, 0.7, 1.1), Vector3.new(1.05, 0.7, 1.1) } do
		cyl(ctx, 1.4, 0.95, pos, P)
		ell(ctx, Vector3.new(1.05, 0.4, 1.1), pos - Vector3.new(0, 0.62, 0.05), S)
	end
	ell(ctx, Vector3.new(3.0, 2.0, 3.6), Vector3.new(0, 1.95, 0), P)
	ell(ctx, Vector3.new(2.3, 1.0, 2.9), Vector3.new(0, 1.35, 0), S)
	ell(ctx, Vector3.new(0.7, 0.6, 1.3), Vector3.new(0, 1.8, 2.1), P, CFrame.Angles(math.rad(-20), 0, 0), "Tail", 0)
	ell(ctx, Vector3.new(0.4, 0.35, 0.9), Vector3.new(0, 1.55, 2.8), P, nil, "Tail", 1)
	ell(ctx, Vector3.new(1.75, 1.5, 1.7), Vector3.new(0, 2.35, -2.05), P, nil, "Head")
	ell(ctx, Vector3.new(1.3, 0.8, 0.8), Vector3.new(0, 2.0, -2.75), S, nil, "Head")
	pair(function(x)
		eye(ctx, Vector3.new(0.5 * x, 2.7, -2.7), 0.55, false)
		ell(ctx, Vector3.new(0.5, 0.7, 0.2), Vector3.new(0.85 * x, 2.8, -1.8), P, CFrame.Angles(0, 0, math.rad(25 * x)), "Head")
	end)
	ctx.headTop = Vector3.new(0, 3.1, -2.05)
	ctx.headFront = Vector3.new(0, 2.2, -2.95)
	ctx.headSize = Vector3.new(1.75, 1.5, 1.7)
	ctx.mouth = Vector3.new(0, 1.85, -2.95)
	ctx.back = { Vector3.new(0, 2.9, -0.9), Vector3.new(0, 2.95, 0), Vector3.new(0, 2.85, 0.9), Vector3.new(0, 2.5, 1.6) }
	ctx.shoulders = { Vector3.new(-1.3, 2.6, -0.6), Vector3.new(1.3, 2.6, -0.6) }
	ctx.cheeks = { Vector3.new(-0.7, 2.2, -2.6), Vector3.new(0.7, 2.2, -2.6) }
end

Archetypes.Serpent = function(ctx)
	local P, S = ctx.primary, ctx.secondary
	local points = {
		Vector3.new(0, 0.55, 3.1),
		Vector3.new(0.45, 0.62, 2.3),
		Vector3.new(0.55, 0.72, 1.45),
		Vector3.new(0.15, 0.85, 0.6),
		Vector3.new(-0.3, 1.2, -0.2),
		Vector3.new(-0.2, 1.75, -0.8),
	}
	for i, pos in points do
		local size = 0.9 + i * 0.12
		local color = if i % 2 == 0 then P else S
		ell(ctx, Vector3.new(size, size, size), pos, color, nil, "Wave", i)
		if i <= 5 then
			pair(function(x)
				ell(ctx, Vector3.new(0.18, 0.3, 0.18), pos + Vector3.new(size * 0.42 * x, -size * 0.45, 0), S, nil, "Wave", i)
			end)
		end
	end
	ell(ctx, Vector3.new(1.65, 1.45, 1.75), Vector3.new(0, 2.55, -1.3), P, nil, "Head")
	ell(ctx, Vector3.new(1.3, 0.55, 0.9), Vector3.new(0, 2.2, -1.95), S, nil, "Head")
	pair(function(x)
		eye(ctx, Vector3.new(0.45 * x, 2.9, -1.95), 0.55, false)
	end)
	ctx.headTop = Vector3.new(0, 3.25, -1.3)
	ctx.headFront = Vector3.new(0, 2.4, -2.2)
	ctx.headSize = Vector3.new(1.65, 1.45, 1.75)
	ctx.mouth = Vector3.new(0, 2.15, -2.1)
	ctx.back = { Vector3.new(-0.2, 2.35, -0.8), Vector3.new(-0.3, 1.8, -0.2), Vector3.new(0.15, 1.45, 0.6), Vector3.new(0.55, 1.3, 1.45), Vector3.new(0.45, 1.1, 2.3) }
	ctx.shoulders = { Vector3.new(-0.9, 2.0, -0.6), Vector3.new(0.6, 2.0, -0.6) }
	ctx.cheeks = { Vector3.new(-0.62, 2.45, -1.9), Vector3.new(0.62, 2.45, -1.9) }
end

Archetypes.Bird = function(ctx)
	local P, S, A = ctx.primary, ctx.secondary, ctx.accent
	pair(function(x)
		cyl(ctx, 0.9, 0.2, Vector3.new(0.45 * x, 0.45, 0), Color3.fromRGB(255, 160, 40))
		wedge(ctx, Vector3.new(0.55, 0.15, 0.7), Vector3.new(0.45 * x, 0.08, -0.3), Color3.fromRGB(255, 160, 40))
		-- aile
		local wing = ell(ctx, Vector3.new(0.35, 1.5, 2.0), Vector3.new(1.18 * x, 1.95, 0.15), S, CFrame.Angles(0, 0, math.rad(-12 * x)), if x < 0 then "WingL" else "WingR")
		wing:SetAttribute("Pivot", Vector3.new(0.9 * x, 2.4, 0.15))
	end)
	ell(ctx, Vector3.new(2.3, 2.3, 2.5), Vector3.new(0, 1.85, 0.1), P)
	ell(ctx, Vector3.new(1.7, 1.6, 0.9), Vector3.new(0, 1.7, -0.85), S)
	wedge(ctx, Vector3.new(1.2, 0.5, 1.0), Vector3.new(0, 2.2, 1.45), P, CFrame.Angles(math.rad(-25), 0, 0), "Tail", 0)
	ell(ctx, Vector3.new(1.45, 1.45, 1.45), Vector3.new(0, 3.35, -0.55), P, nil, "Head")
	wedge(ctx, Vector3.new(0.6, 0.35, 0.8), Vector3.new(0, 3.2, -1.45), A, CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(180), 0, 0), "Head")
	wedge(ctx, Vector3.new(0.55, 0.25, 0.7), Vector3.new(0, 3.0, -1.35), A, CFrame.Angles(0, math.pi, 0), "Head")
	pair(function(x)
		eye(ctx, Vector3.new(0.42 * x, 3.55, -1.1), 0.5, true)
	end)
	ctx.headTop = Vector3.new(0, 4.05, -0.55)
	ctx.headFront = Vector3.new(0, 3.3, -1.3)
	ctx.headSize = Vector3.new(1.45, 1.45, 1.45)
	ctx.mouth = Vector3.new(0, 3.1, -1.5)
	ctx.back = { Vector3.new(0, 3.0, 0.4), Vector3.new(0, 2.7, 0.9) }
	ctx.shoulders = { Vector3.new(-1.1, 2.6, 0), Vector3.new(1.1, 2.6, 0) }
	ctx.cheeks = { Vector3.new(-0.55, 3.2, -1.1), Vector3.new(0.55, 3.2, -1.1) }
end

Archetypes.Blob = function(ctx)
	local P, S, A = ctx.primary, ctx.secondary, ctx.accent
	local body = ell(ctx, Vector3.new(3.1, 2.5, 3.0), Vector3.new(0, 1.3, 0), P, nil, "Squash")
	body.Transparency = 0.12
	body.Material = Enum.Material.Glass
	ell(ctx, Vector3.new(1.3, 1.1, 1.3), Vector3.new(0.3, 1.1, 0.4), A, nil, "Squash")
	ell(ctx, Vector3.new(2.6, 0.5, 2.5), Vector3.new(0, 0.28, 0), S, nil, "Squash")
	for i = 1, 4 do
		local a = i * math.pi / 2 + 0.4
		ell(ctx, Vector3.new(0.4, 0.55, 0.4), Vector3.new(math.cos(a) * 1.35, 0.35, math.sin(a) * 1.3), P, nil, "Squash")
	end
	pair(function(x)
		eye(ctx, Vector3.new(0.6 * x, 1.75, -1.3), 0.75, false)
	end)
	ell(ctx, Vector3.new(0.7, 0.3, 0.2), Vector3.new(0, 1.05, -1.45), BLACK, nil, "Squash")
	ctx.headTop = Vector3.new(0, 2.55, 0)
	ctx.headFront = Vector3.new(0, 1.4, -1.5)
	ctx.headSize = Vector3.new(3.1, 2.5, 3.0)
	ctx.mouth = Vector3.new(0, 1.05, -1.5)
	ctx.back = { Vector3.new(0, 2.5, 0.2), Vector3.new(0, 2.2, 0.9) }
	ctx.shoulders = { Vector3.new(-1.4, 1.8, 0), Vector3.new(1.4, 1.8, 0) }
	ctx.cheeks = { Vector3.new(-1.0, 1.35, -1.25), Vector3.new(1.0, 1.35, -1.25) }
end

Archetypes.Crab = function(ctx)
	local P, S = ctx.primary, ctx.secondary
	pair(function(x)
		for i = 0, 2 do
			local z = -0.6 + i * 0.65
			ell(ctx, Vector3.new(1.2, 0.25, 0.25), Vector3.new(1.55 * x, 0.65, z), P, CFrame.Angles(0, 0, math.rad(-35 * x)), "Wave", i + (if x > 0 then 3 else 0))
		end
		-- pince
		ell(ctx, Vector3.new(0.5, 0.5, 1.3), Vector3.new(1.4 * x, 1.4, -0.95), P, CFrame.Angles(math.rad(15), math.rad(20 * x), 0), "Head")
		ell(ctx, Vector3.new(1.05, 0.95, 1.25), Vector3.new(1.55 * x, 1.6, -1.65), P, nil, "Head")
		wedge(ctx, Vector3.new(0.45, 0.35, 0.8), Vector3.new(1.55 * x, 1.9, -2.4), S, CFrame.Angles(0, math.pi, 0), "Head")
		wedge(ctx, Vector3.new(0.45, 0.35, 0.8), Vector3.new(1.55 * x, 1.45, -2.4), S, CFrame.Angles(0, math.pi, math.pi), "Head")
		-- yeux sur tiges
		cyl(ctx, 0.9, 0.18, Vector3.new(0.45 * x, 2.1, -0.75), P, nil, "Head")
		eye(ctx, Vector3.new(0.45 * x, 2.65, -0.8), 0.55, true)
	end)
	ell(ctx, Vector3.new(3.3, 1.45, 2.4), Vector3.new(0, 1.2, 0), P)
	ell(ctx, Vector3.new(2.6, 0.6, 1.9), Vector3.new(0, 0.75, 0), S)
	ell(ctx, Vector3.new(0.8, 0.25, 0.2), Vector3.new(0, 1.05, -1.18), BLACK)
	ctx.headTop = Vector3.new(0, 1.95, 0)
	ctx.headFront = Vector3.new(0, 1.2, -1.25)
	ctx.headSize = Vector3.new(3.3, 1.45, 2.4)
	ctx.mouth = Vector3.new(0, 1.0, -1.2)
	ctx.back = { Vector3.new(-0.8, 1.85, 0.1), Vector3.new(0, 1.95, 0.1), Vector3.new(0.8, 1.85, 0.1) }
	ctx.shoulders = { Vector3.new(-1.3, 1.9, 0.3), Vector3.new(1.3, 1.9, 0.3) }
	ctx.cheeks = { Vector3.new(-0.9, 1.2, -1.1), Vector3.new(0.9, 1.2, -1.1) }
end

Archetypes.Mech = function(ctx)
	local P, S, A = ctx.primary, ctx.secondary, ctx.accent
	local metal = Enum.Material.DiamondPlate
	pair(function(x)
		block(ctx, Vector3.new(0.8, 1.2, 1.0), Vector3.new(0.65 * x, 0.65, 0), S, nil, nil, nil, metal)
		block(ctx, Vector3.new(1.0, 0.35, 1.4), Vector3.new(0.65 * x, 0.18, -0.1), S)
		block(ctx, Vector3.new(0.55, 1.4, 0.6), Vector3.new(1.5 * x, 2.0, -0.2), S, CFrame.Angles(math.rad(-15), 0, 0), "Head")
		ell(ctx, Vector3.new(0.7, 0.7, 0.7), Vector3.new(1.5 * x, 1.2, -0.45), P, nil, "Head")
	end)
	block(ctx, Vector3.new(2.5, 2.1, 1.9), Vector3.new(0, 2.25, 0), P, nil, nil, nil, Enum.Material.Metal)
	block(ctx, Vector3.new(1.6, 0.9, 0.2), Vector3.new(0, 2.3, -0.98), S)
	local core = ell(ctx, Vector3.new(0.6, 0.6, 0.3), Vector3.new(0, 2.3, -1.08), A, nil, nil, nil, Enum.Material.Neon)
	table.insert(ctx.glowParts, core)
	block(ctx, Vector3.new(1.8, 1.4, 1.6), Vector3.new(0, 3.95, -0.1), P, nil, "Head", 0, Enum.Material.Metal)
	pair(function(x)
		eye(ctx, Vector3.new(0.42 * x, 4.05, -0.92), 0.5, false)
	end)
	block(ctx, Vector3.new(1.0, 0.18, 0.12), Vector3.new(0, 3.55, -0.92), BLACK, nil, "Head")
	ctx.headTop = Vector3.new(0, 4.65, -0.1)
	ctx.headFront = Vector3.new(0, 4.0, -0.95)
	ctx.headSize = Vector3.new(1.8, 1.4, 1.6)
	ctx.mouth = Vector3.new(0, 3.55, -0.95)
	ctx.back = { Vector3.new(0, 3.35, 0.9) }
	ctx.shoulders = { Vector3.new(-1.35, 3.35, 0), Vector3.new(1.35, 3.35, 0) }
	ctx.cheeks = { Vector3.new(-0.7, 3.75, -0.92), Vector3.new(0.7, 3.75, -0.92) }
end

Archetypes.Squid = function(ctx)
	local P, S = ctx.primary, ctx.secondary
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		for j = 0, 2 do
			local r = 0.7 + j * 0.45
			local size = 0.62 - j * 0.14
			ell(ctx, Vector3.new(size, size, size), dir * r + Vector3.new(0, 0.9 - j * 0.3, 0), if j % 2 == 0 then P else S, nil, "Wave", i + j * 0.6)
		end
	end
	ell(ctx, Vector3.new(2.3, 2.7, 2.3), Vector3.new(0, 2.5, 0.15), P, nil, "Squash")
	ell(ctx, Vector3.new(1.6, 1.2, 0.5), Vector3.new(0, 1.9, -0.85), S, nil, "Squash")
	for i = 1, 3 do
		ell(ctx, Vector3.new(0.35, 0.35, 0.2), Vector3.new((i - 2) * 0.7, 3.3 - math.abs(i - 2) * 0.2, -0.95), S, nil, "Squash")
	end
	pair(function(x)
		eye(ctx, Vector3.new(0.5 * x, 2.35, -0.98), 0.7, false)
	end)
	ctx.headTop = Vector3.new(0, 3.85, 0.15)
	ctx.headFront = Vector3.new(0, 2.4, -1.1)
	ctx.headSize = Vector3.new(2.3, 2.7, 2.3)
	ctx.mouth = Vector3.new(0, 1.75, -1.05)
	ctx.back = { Vector3.new(0, 3.3, 0.9), Vector3.new(0, 2.6, 1.2) }
	ctx.shoulders = { Vector3.new(-1.15, 2.8, 0), Vector3.new(1.15, 2.8, 0) }
	ctx.cheeks = { Vector3.new(-0.85, 2.0, -0.95), Vector3.new(0.85, 2.0, -0.95) }
end

local function tinyLegs(ctx: Ctx, spread: number, depth: number, color: Color3)
	pair(function(x)
		cyl(ctx, 0.8, 0.28, Vector3.new(spread * x, 0.4, depth), color)
		ell(ctx, Vector3.new(0.5, 0.25, 0.65), Vector3.new(spread * x, 0.1, depth - 0.12), color)
	end)
end

local function tinyArms(ctx: Ctx, spread: number, y: number, z: number, color: Color3)
	pair(function(x)
		cyl(ctx, 0.9, 0.22, Vector3.new(spread * x, y, z), color, CFrame.Angles(0, 0, math.rad(40 * x)), "Head")
		ell(ctx, Vector3.new(0.35, 0.35, 0.35), Vector3.new((spread + 0.3) * x, y - 0.3, z), WHITE, nil, "Head")
	end)
end

Archetypes.Food = function(ctx, species)
	local P, S, A = ctx.primary, ctx.secondary, ctx.accent
	local shape = species.Shape or "Toast"
	local limbColor = Color3.fromRGB(60, 40, 30)
	if shape == "Toast" then
		tinyLegs(ctx, 0.55, 0, limbColor)
		block(ctx, Vector3.new(2.8, 2.6, 0.9), Vector3.new(0, 2.0, 0), P)
		ell(ctx, Vector3.new(2.8, 1.2, 0.9), Vector3.new(0, 3.3, 0), P)
		block(ctx, Vector3.new(2.4, 2.3, 0.2), Vector3.new(0, 2.0, -0.46), S)
		ell(ctx, Vector3.new(2.4, 1.0, 0.2), Vector3.new(0, 3.15, -0.46), S)
		tinyArms(ctx, 1.55, 2.0, 0, limbColor)
		pair(function(x)
			eye(ctx, Vector3.new(0.55 * x, 2.55, -0.62), 0.6, true)
		end)
		block(ctx, Vector3.new(0.8, 0.14, 0.12), Vector3.new(0, 1.85, -0.6), BLACK)
		ctx.headTop = Vector3.new(0, 3.85, 0)
		ctx.headFront = Vector3.new(0, 2.4, -0.6)
		ctx.headSize = Vector3.new(2.8, 3.0, 0.9)
		ctx.mouth = Vector3.new(0, 1.85, -0.6)
		ctx.back = { Vector3.new(0, 3.6, 0.4), Vector3.new(-0.9, 3.4, 0.4), Vector3.new(0.9, 3.4, 0.4) }
		ctx.cheeks = { Vector3.new(-0.95, 2.2, -0.6), Vector3.new(0.95, 2.2, -0.6) }
	elseif shape == "Croissant" then
		tinyLegs(ctx, 0.6, 0, limbColor)
		for i = -2, 2 do
			local a = i * 0.42
			local size = 1.55 - math.abs(i) * 0.3
			ell(ctx, Vector3.new(size * 1.05, size, size * 0.95), Vector3.new(math.sin(a) * 1.35, 1.05 + math.cos(a) * 0.35, math.cos(a) * 0.3 - 0.2), if i % 2 == 0 then P else S, CFrame.Angles(0, 0, -a), "Wave", i)
		end
		pair(function(x)
			eye(ctx, Vector3.new(0.35 * x, 1.55, -0.75), 0.5, true)
		end)
		ctx.headTop = Vector3.new(0, 2.05, -0.1)
		ctx.headFront = Vector3.new(0, 1.35, -0.8)
		ctx.headSize = Vector3.new(1.55, 1.55, 1.5)
		ctx.mouth = Vector3.new(0, 1.0, -0.85)
		ctx.back = { Vector3.new(-1.1, 1.8, 0), Vector3.new(0, 2.0, 0.1), Vector3.new(1.1, 1.8, 0) }
		ctx.cheeks = { Vector3.new(-0.6, 1.2, -0.75), Vector3.new(0.6, 1.2, -0.75) }
	elseif shape == "Kebab" then
		tinyLegs(ctx, 0.45, 0, limbColor)
		cyl(ctx, 4.6, 0.18, Vector3.new(0, 2.4, 0), Color3.fromRGB(200, 200, 205), nil, nil, nil, Enum.Material.Metal)
		for i = 0, 5 do
			local c = if i % 3 == 2 then A elseif i % 2 == 0 then P else S
			local d = 1.9 - math.abs(i - 2.5) * 0.12
			cyl(ctx, 0.45, d, Vector3.new(0, 1.0 + i * 0.48, 0), c, nil, "Wave", i)
		end
		pair(function(x)
			eye(ctx, Vector3.new(0.4 * x, 2.5, -0.9), 0.5, true)
		end)
		tinyArms(ctx, 1.05, 2.0, 0, limbColor)
		ctx.headTop = Vector3.new(0, 4.4, 0)
		ctx.headFront = Vector3.new(0, 2.4, -0.95)
		ctx.headSize = Vector3.new(1.9, 3.0, 1.9)
		ctx.mouth = Vector3.new(0, 2.0, -0.95)
		ctx.back = { Vector3.new(0, 3.9, 0.7), Vector3.new(0, 3.2, 0.9) }
		ctx.cheeks = { Vector3.new(-0.7, 2.2, -0.8), Vector3.new(0.7, 2.2, -0.8) }
	elseif shape == "Pizza" then
		tinyLegs(ctx, 0.35, 0, limbColor)
		-- part debout, pointe vers le bas
		local tri = Vector3.new(0.45, 3.2, 1.35)
		wedge(ctx, tri, Vector3.new(-0.67, 2.3, 0), S, CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(math.pi, 0, 0))
		wedge(ctx, tri, Vector3.new(0.67, 2.3, 0), S, CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.pi, 0, 0))
		cyl(ctx, 2.9, 0.65, Vector3.new(0, 3.95, 0), P, CFrame.Angles(0, 0, math.rad(90)))
		for _, pos in { Vector3.new(-0.5, 3.1, -0.26), Vector3.new(0.45, 2.9, -0.26), Vector3.new(0, 2.1, -0.26) } do
			cyl(ctx, 0.08, 0.55, pos, A, CFrame.Angles(math.rad(90), 0, 0))
		end
		pair(function(x)
			eye(ctx, Vector3.new(0.38 * x, 3.4, -0.35), 0.45, true)
		end)
		tinyArms(ctx, 1.25, 3.0, 0, limbColor)
		ctx.headTop = Vector3.new(0, 4.35, 0)
		ctx.headFront = Vector3.new(0, 3.2, -0.35)
		ctx.headSize = Vector3.new(2.9, 3.4, 0.6)
		ctx.mouth = Vector3.new(0, 2.8, -0.35)
		ctx.back = { Vector3.new(-1.0, 4.2, 0), Vector3.new(1.0, 4.2, 0) }
		ctx.cheeks = { Vector3.new(-0.7, 3.1, -0.3), Vector3.new(0.7, 3.1, -0.3) }
	else -- Donut
		tinyLegs(ctx, 0.9, 0, limbColor)
		for i = 1, 12 do
			local a = i / 12 * math.pi * 2
			local pos = Vector3.new(math.cos(a) * 1.25, 2.0 + math.sin(a) * 1.25, 0)
			ell(ctx, Vector3.new(1.05, 1.05, 1.1), pos, P, nil, "Squash")
			if math.sin(a) > -0.3 then
				ell(ctx, Vector3.new(0.95, 0.95, 0.4), pos + Vector3.new(0, 0, -0.42), S, nil, "Squash")
			end
		end
		pair(function(x)
			eye(ctx, Vector3.new(0.45 * x, 3.2, -0.72), 0.5, false)
		end)
		ctx.headTop = Vector3.new(0, 3.8, 0)
		ctx.headFront = Vector3.new(0, 2.8, -0.7)
		ctx.headSize = Vector3.new(3.4, 3.4, 1.1)
		ctx.mouth = Vector3.new(0, 2.7, -0.75)
		ctx.back = { Vector3.new(-1.0, 3.5, 0.3), Vector3.new(1.0, 3.5, 0.3) }
		ctx.cheeks = { Vector3.new(-0.95, 2.9, -0.7), Vector3.new(0.95, 2.9, -0.7) }
	end
	ctx.shoulders = { Vector3.new(-1.3, 2.9, 0), Vector3.new(1.3, 2.9, 0) }
end

----------------------------------------------------------------------------
-- Accessoires
----------------------------------------------------------------------------

local Accessories: { [string]: (ctx: Ctx) -> () } = {}

Accessories.Spikes = function(ctx)
	for i, pos in ctx.back do
		local h = 0.9 - math.abs(i - (#ctx.back + 1) / 2) * 0.12
		spike(ctx, pos - Vector3.new(0, 0.2, 0), h, 0.8, 0.22, ctx.accent)
	end
end

Accessories.Fin = function(ctx)
	local base = ctx.back[math.max(1, math.floor(#ctx.back / 2))]
	wedge(ctx, Vector3.new(0.25, 1.4, 1.3), base + Vector3.new(0, 0.5, 0), ctx.primary)
end

Accessories.Horn = function(ctx)
	local top = ctx.headTop + Vector3.new(0, -0.1, -ctx.headSize.Z * 0.3)
	spike(ctx, top, 1.0, 0.45, 0.35, Color3.fromRGB(255, 245, 220), CFrame.Angles(math.rad(-25), 0, 0), "Head")
end

Accessories.Tusks = function(ctx)
	pair(function(x)
		spike(ctx, ctx.mouth + Vector3.new(0.45 * x, -0.1, 0), 0.9, 0.3, 0.25, WHITE, CFrame.Angles(math.rad(-120), 0, 0), "Head")
	end)
end

Accessories.Teeth = function(ctx)
	for i = -2, 2 do
		wedge(ctx, Vector3.new(0.14, 0.22, 0.14), ctx.mouth + Vector3.new(i * 0.2, -0.05, -0.05), WHITE, CFrame.Angles(math.pi, 0, 0), "Head")
	end
end

Accessories.Crown = function(ctx)
	local top = ctx.headTop + Vector3.new(0, 0.05, 0)
	local gold = Color3.fromRGB(255, 205, 50)
	cyl(ctx, 0.35, 1.1, top + Vector3.new(0, 0.15, 0), gold, nil, "Head", 0, Enum.Material.Foil)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		spike(ctx, top + Vector3.new(math.cos(a) * 0.42, 0.3, math.sin(a) * 0.42), 0.45, 0.3, 0.15, gold, CFrame.Angles(0, -a, 0), "Head", 0, Enum.Material.Foil)
	end
	local gem = ell(ctx, Vector3.new(0.25, 0.25, 0.25), top + Vector3.new(0, 0.2, -0.55), Color3.fromRGB(255, 40, 90), nil, "Head", 0, Enum.Material.Neon)
	table.insert(ctx.glowParts, gem)
end

Accessories.Halo = function(ctx)
	local top = ctx.headTop + Vector3.new(0, 0.9, 0)
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local p = block(ctx, Vector3.new(0.34, 0.12, 0.14), top + Vector3.new(math.cos(a) * 0.75, 0, math.sin(a) * 0.75), Color3.fromRGB(255, 240, 150), CFrame.Angles(0, -a + math.pi / 2, 0), "Halo", 0, Enum.Material.Neon)
		p.CastShadow = false
		table.insert(ctx.glowParts, p)
	end
end

Accessories.Antenna = function(ctx)
	pair(function(x)
		local base = ctx.headTop + Vector3.new(0.35 * x, 0, 0)
		cyl(ctx, 0.9, 0.1, base + Vector3.new(0.1 * x, 0.4, 0), BLACK, CFrame.Angles(0, 0, math.rad(-15 * x)), "Head")
		local ball = ell(ctx, Vector3.new(0.3, 0.3, 0.3), base + Vector3.new(0.22 * x, 0.9, 0), ctx.accent, nil, "Head", 0, Enum.Material.Neon)
		table.insert(ctx.glowParts, ball)
	end)
end

Accessories.Bolt = function(ctx)
	local yellow = Color3.fromRGB(255, 235, 60)
	for i, pos in ctx.back do
		if i % 2 == 1 then
			local p = wedge(ctx, Vector3.new(0.15, 0.7, 0.5), pos + Vector3.new(0, 0.3, 0), yellow, CFrame.Angles(0, 0, math.rad(20)), nil, nil, Enum.Material.Neon)
			table.insert(ctx.glowParts, p)
		end
	end
end

Accessories.Wings = function(ctx)
	local base = ctx.back[1] or ctx.headTop
	pair(function(x)
		local role = if x < 0 then "WingL" else "WingR"
		for i = 0, 2 do
			local w = wedge(ctx, Vector3.new(0.12, 1.3 - i * 0.25, 1.5 - i * 0.2), base + Vector3.new((0.95 + i * 0.7) * x, 0.55 + i * 0.3, 0.3), ctx.accent, CFrame.Angles(0, math.rad(-90 * x), 0) * CFrame.Angles(math.rad(25), 0, 0), role)
			w:SetAttribute("Pivot", base + Vector3.new(0.4 * x, 0.4, 0.2))
		end
	end)
end

Accessories.Visor = function(ctx)
	local p = block(ctx, Vector3.new(ctx.headSize.X * 0.8, 0.28, 0.12), ctx.headFront + Vector3.new(0, 0.35, -0.08), ctx.accent, nil, "Head", 0, Enum.Material.Neon)
	p.Transparency = 0.25
	table.insert(ctx.glowParts, p)
end

Accessories.Cannon = function(ctx)
	local s = ctx.shoulders[2]
	cyl(ctx, 0.5, 0.7, s + Vector3.new(0, 0.2, 0), Color3.fromRGB(70, 70, 80), nil, "Head")
	cyl(ctx, 1.6, 0.42, s + Vector3.new(0, 0.5, -0.5), Color3.fromRGB(90, 90, 100), CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, 0, math.rad(-90)), "Head", 0, Enum.Material.Metal)
	local muzzle = cyl(ctx, 0.1, 0.3, s + Vector3.new(0, 0.5, -1.3), ctx.accent, CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, 0, math.rad(-90)), "Head", 0, Enum.Material.Neon)
	table.insert(ctx.glowParts, muzzle)
end

Accessories.Bow = function(ctx)
	local top = ctx.headTop + Vector3.new(0.5, -0.1, 0)
	local pink = Color3.fromRGB(255, 80, 150)
	wedge(ctx, Vector3.new(0.2, 0.6, 0.5), top + Vector3.new(-0.25, 0, 0), pink, CFrame.Angles(0, math.rad(90), 0), "Head")
	wedge(ctx, Vector3.new(0.2, 0.6, 0.5), top + Vector3.new(0.25, 0, 0), pink, CFrame.Angles(0, math.rad(-90), 0), "Head")
	ell(ctx, Vector3.new(0.25, 0.25, 0.25), top, pink, nil, "Head")
end

Accessories.Blush = function(ctx)
	for _, c in ctx.cheeks do
		ell(ctx, Vector3.new(0.4, 0.22, 0.1), c, Color3.fromRGB(255, 120, 160), nil, "Head")
	end
end

Accessories.Nori = function(ctx)
	local base = ctx.back[2] or ctx.headTop
	block(ctx, Vector3.new(2.2, 0.8, 0.1), base + Vector3.new(0, -0.6, 0), Color3.fromRGB(25, 50, 30), CFrame.Angles(math.rad(90), 0, 0))
end

Accessories.Cheese = function(ctx)
	for i = 1, 4 do
		ell(ctx, Vector3.new(0.3, 0.6, 0.2), ctx.headFront + Vector3.new(-0.9 + i * 0.4, 0.6 - (i % 2) * 0.4, -0.02), Color3.fromRGB(255, 225, 80), nil, "Head")
	end
end

Accessories.Sprinkles = function(ctx)
	local colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 240, 80), Color3.fromRGB(120, 255, 120), WHITE }
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local pos = Vector3.new(math.cos(a) * 1.25, 2.0 + math.sin(a) * 1.25, -0.72)
		block(ctx, Vector3.new(0.3, 0.08, 0.08), pos, colors[(i % #colors) + 1], CFrame.Angles(0, 0, a * 3), "Squash")
	end
end

Accessories.Shell = function(ctx)
	local base = ctx.back[2] or ctx.headTop
	ell(ctx, Vector3.new(2.6, 1.3, 2.9), base + Vector3.new(0, -0.35, 0), ctx.secondary)
	for i = -1, 1 do
		local p = ell(ctx, Vector3.new(0.5, 0.3, 0.5), base + Vector3.new(i * 0.7, 0.25, i * 0.3), ctx.accent, nil, nil, nil, Enum.Material.Neon)
		table.insert(ctx.glowParts, p)
	end
end

Accessories.Glow = function(ctx)
	-- Les pièces d'accent deviennent néon + lumière.
	for _, p in ctx.model:GetDescendants() do
		if p:IsA("BasePart") and p.Color == ctx.accent and not p:GetAttribute("Eye") then
			p.Material = Enum.Material.Neon
			table.insert(ctx.glowParts, p)
		end
	end
	local light = Instance.new("PointLight")
	light.Color = ctx.accent
	light.Range = 10 * ctx.s
	light.Brightness = 1.4
	light.Parent = ctx.root
end

Accessories.Stars = function(ctx)
	ctx.model:SetAttribute("FxStars", true)
end

----------------------------------------------------------------------------
-- Mutations
----------------------------------------------------------------------------

local function applyMutation(ctx: Ctx, mutationId: string?)
	local mutation = Mutations.Get(mutationId)
	if not mutation then
		return
	end
	ctx.model:SetAttribute("Mutation", mutation.Id)
	if mutation.Id == "Rainbow" then
		for _, p in ctx.model:GetDescendants() do
			if p:IsA("BasePart") and not p:GetAttribute("Eye") and p ~= ctx.root then
				p:SetAttribute("Rainbow", true)
			end
		end
		return
	end
	for _, p in ctx.model:GetDescendants() do
		if p:IsA("BasePart") and p ~= ctx.root and not p:GetAttribute("Eye") then
			if mutation.Tint then
				p.Color = p.Color:Lerp(mutation.Tint, 0.72)
			end
			if mutation.Material and p.Material ~= Enum.Material.Neon then
				p.Material = mutation.Material
			end
			if mutation.Reflectance then
				p.Reflectance = mutation.Reflectance
			end
			if mutation.Id == "Diamond" then
				p.Transparency = math.max(p.Transparency, 0.15)
			end
		end
	end
	if mutation.Id == "Shadow" or mutation.Id == "Radioactive" or mutation.Id == "Galaxy" then
		local light = Instance.new("PointLight")
		light.Color = mutation.Color
		light.Range = 12 * ctx.s
		light.Brightness = 2
		light.Parent = ctx.root
	end
end

----------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------

local function newCtx(name: string, scale: number, primary: Color3, secondary: Color3, accent: Color3, origin: CFrame?): Ctx
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	setup(root, WHITE)
	root.CastShadow = false
	root.CFrame = origin or CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	return {
		model = model,
		root = root,
		s = scale,
		primary = primary,
		secondary = secondary,
		accent = accent,
		headTop = Vector3.new(0, 4, 0),
		headFront = Vector3.new(0, 3, -1),
		headSize = Vector3.new(2, 2, 2),
		back = {},
		shoulders = { Vector3.new(-1, 3, 0), Vector3.new(1, 3, 0) },
		mouth = Vector3.new(0, 3, -1),
		cheeks = {},
		glowParts = {},
	}
end

-- Construit un kaiju. `scale` = échelle du stade de croissance.
function KaijuBuilder.Build(speciesId: string, mutationId: string?, scale: number?, origin: CFrame?): Model
	local species = Kaijus.Get(speciesId) or Kaijus.List[1]
	local ctx = newCtx(species.Id, scale or 1, species.Primary, species.Secondary, species.Accent, origin)
	local build = Archetypes[species.Archetype] or Archetypes.Rex
	build(ctx, species)
	for _, name in species.Accessories do
		local fn = Accessories[name]
		if fn then
			fn(ctx)
		end
	end
	applyMutation(ctx, mutationId)
	ctx.model:SetAttribute("Species", species.Id)
	ctx.model:SetAttribute("Rarity", species.Rarity)
	ctx.model:SetAttribute("Height", ctx.headTop.Y * ctx.s)
	return ctx.model
end

-- Hauteur approximative (échelle 1) de l'espèce, pour placer les étiquettes.
function KaijuBuilder.Height(speciesId: string): number
	local species = Kaijus.Get(speciesId)
	if not species then
		return 4.5
	end
	local heights = { Rex = 4.6, Quad = 3.3, Serpent = 3.4, Bird = 4.2, Blob = 2.7, Crab = 3.0, Food = 4.2, Mech = 4.8, Squid = 4.0 }
	return heights[species.Archetype] or 4.5
end

-- Œuf de météore.
function KaijuBuilder.BuildEgg(rarityId: string, scale: number?, origin: CFrame?): Model
	local rarity = Rarities.Get(rarityId)
	local ctx = newCtx("Egg", scale or 1, rarity.Color, rarity.Glow, rarity.Glow, origin)
	local shell = ell(ctx, Vector3.new(2.1, 2.7, 2.1), Vector3.new(0, 1.4, 0), rarity.Color, nil, "Squash")
	shell.Name = "Shell"
	if rarity.Id == "Secret" then
		shell.Material = Enum.Material.Glass
		shell.Transparency = 0.1
	end
	local rng = Random.new(#rarityId * 97)
	for _ = 1, 7 do
		local a = rng:NextNumber() * math.pi * 2
		local y = rng:NextNumber(0.6, 2.3)
		local r = 1.0 - math.abs(y - 1.4) * 0.35
		ell(ctx, Vector3.new(0.5, 0.5, 0.2), Vector3.new(math.cos(a) * r, y, math.sin(a) * r), rarity.Glow, CFrame.lookAt(Vector3.zero, Vector3.new(math.cos(a), 0, math.sin(a))), "Squash")
	end
	if rarity.Order >= 3 then
		local band = cyl(ctx, 0.25, 2.12, Vector3.new(0, 1.4, 0), rarity.Glow, nil, "Squash", 0, Enum.Material.Neon)
		band.Transparency = 0.2
		local light = Instance.new("PointLight")
		light.Color = rarity.Glow
		light.Range = 12 * ctx.s
		light.Brightness = 1.5 + rarity.Order * 0.3
		light.Parent = ctx.root
	end
	ctx.model:SetAttribute("Rarity", rarity.Id)
	return ctx.model
end

return KaijuBuilder
