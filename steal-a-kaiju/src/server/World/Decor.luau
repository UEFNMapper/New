--!nonstrict
-- Briques de décor partagées par la carte principale et les mondes : pièces,
-- cylindres, lumières, panneaux flottants, particules, arbres « sucette »,
-- buissons, fleurs, nuages (style « jouet » : formes rondes, couleurs franches).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)

local rgb = Color3.fromRGB

local Decor = {}

local function part(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function cylinder(cf: CFrame, height: number, diameter: number, props: { [string]: any }, parent: Instance?): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	return part(props, parent)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

-- Étiquette flottante (lisible de loin) au-dessus d'un point.
local function floatingSign(parent: Instance, cf: CFrame, text: string, color: Color3, width: number, height: number, maxDistance: number, name: string?)
	local anchor = part({ Name = name or "Sign", Size = Vector3.new(1, 1, 1), CFrame = cf, Transparency = 1, CanCollide = false, CanQuery = false }, parent)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SignGui"
	gui.Size = UDim2.fromOffset(width, height)
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.Title
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Theme.Colors.Ink
	stroke.Parent = label
	label.Parent = gui
	return anchor
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

----------------------------------------------------------------------------
-- Décor (style « jouet » : formes rondes, couleurs franches)
----------------------------------------------------------------------------

local function ball(cf: CFrame, diameter: number, color: Color3, parent: Instance, material: Enum.Material?): Part
	return part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
	}, parent)
end

-- Arbre « sucette » : tronc + 3 boules de feuillage.
local function lollipopTree(parent: Instance, base: CFrame, height: number, rng: Random)
	local trunk = rgb(150, 100, 60)
	cylinder(base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, 0, math.rad(-90)), height, 2.2, { Name = "Trunk", Color = trunk, Material = Enum.Material.Wood }, parent)
	local greens = { rgb(96, 205, 90), rgb(70, 180, 80), rgb(130, 225, 100) }
	local d = height * 0.75
	ball(base * CFrame.new(0, height + d * 0.25, 0), d, greens[rng:NextInteger(1, 3)], parent)
	ball(base * CFrame.new(d * 0.35, height + d * 0.05, d * 0.2), d * 0.7, greens[rng:NextInteger(1, 3)], parent)
	ball(base * CFrame.new(-d * 0.3, height + d * 0.1, -d * 0.25), d * 0.65, greens[rng:NextInteger(1, 3)], parent)
	-- quelques fruits
	for _ = 1, 3 do
		local a = rng:NextNumber() * math.pi * 2
		ball(base * CFrame.new(math.cos(a) * d * 0.45, height + d * 0.2 + rng:NextNumber(-2, 2), math.sin(a) * d * 0.45), 1.2, rgb(255, 90, 90), parent, Enum.Material.SmoothPlastic)
	end
end

local function bush(parent: Instance, base: CFrame, size: number, rng: Random)
	ball(base * CFrame.new(0, size * 0.35, 0), size, rgb(80, 190, 90), parent)
	ball(base * CFrame.new(size * 0.4, size * 0.25, size * 0.2), size * 0.7, rgb(110, 215, 100), parent)
	ball(base * CFrame.new(-size * 0.35, size * 0.25, -size * 0.2), size * 0.6, rgb(70, 170, 85), parent)
	if rng:NextNumber() < 0.6 then
		ball(base * CFrame.new(size * 0.1, size * 0.85, size * 0.1), size * 0.3, rgb(255, 120, 200), parent)
	end
end

local function flower(parent: Instance, base: CFrame, color: Color3)
	cylinder(base * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, 0, math.rad(-90)), 2, 0.3, { Name = "Stem", Color = rgb(70, 170, 70), CanCollide = false }, parent)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		ball(base * CFrame.new(math.cos(a) * 0.7, 2.1, math.sin(a) * 0.7), 0.9, color, parent)
	end
	ball(base * CFrame.new(0, 2.15, 0), 0.8, rgb(255, 230, 90), parent)
end

local function cloud(parent: Instance, center: Vector3, size: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Cloud"
	model.Parent = parent
	for i = 1, 5 do
		local off = Vector3.new(rng:NextNumber(-1, 1) * size * 0.9, rng:NextNumber(-0.15, 0.25) * size, rng:NextNumber(-0.4, 0.4) * size)
		local p = ball(CFrame.new(center + off), size * rng:NextNumber(0.6, 1.1), rgb(255, 255, 255), model)
		p.Material = Enum.Material.SmoothPlastic
		p.CastShadow = false
		if i == 1 then
			model.PrimaryPart = p
		end
	end
end

-- Plateforme d'atterrissage d'un météore (anneau lumineux + cible).
local function meteorPad(parent: Instance, pos: Vector3, index: number, ringColor: Color3, baseColor: Color3): BasePart
	local base = cylinder(CFrame.new(pos + Vector3.new(0, 0.6, 0)), 1.2, 16, {
		Name = "MeteorPad" .. index,
		Color = baseColor,
		Material = Enum.Material.Metal,
	}, parent)
	local ring = cylinder(CFrame.new(pos + Vector3.new(0, 1.25, 0)), 0.15, 17, {
		Name = "Ring",
		Color = ringColor,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	}, parent)
	ring.Transparency = 0.1
	local inner = cylinder(CFrame.new(pos + Vector3.new(0, 1.26, 0)), 0.14, 8, { Name = "Target", Color = Theme.Colors.Magma, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }, parent)
	inner.Transparency = 0.3
	base:SetAttribute("Index", index)
	return base
end

Decor.meteorPad = meteorPad
Decor.part = part
Decor.cylinder = cylinder
Decor.light = light
Decor.floatingSign = floatingSign
Decor.emitter = emitter
Decor.ball = ball
Decor.lollipopTree = lollipopTree
Decor.bush = bush
Decor.flower = flower
Decor.cloud = cloud

return Decor
