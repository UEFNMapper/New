--!nonstrict
-- Construit les 4 îles-arènes des mondes (Candy Coast, Frost Peaks, Volcano Core,
-- Cosmic Rift) et leurs portails dans le cratère central. Chaque arène a la même
-- structure lisible (plateau rond, 6 plateformes à météores, lac central, portail
-- du retour) mais un décor, des couleurs et des particules qui lui sont propres.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Worlds = require(Shared.Config.Worlds)
local Theme = require(Shared.Config.Theme)

local Decor = require(script.Parent.Decor)
local part = Decor.part
local cylinder = Decor.cylinder
local ball = Decor.ball
local light = Decor.light
local emitter = Decor.emitter
local floatingSign = Decor.floatingSign

local rgb = Color3.fromRGB

local WorldBuilder = {}

export type WorldInfo = {
	Id: string,
	Model: Model?,
	Pads: { BasePart },
	HubPortal: BasePart?, -- disque du portail dans le cratère
	HomePortal: BasePart?, -- disque du portail de retour dans l'arène
}

local R = Worlds.ArenaRadius

-- Pièce verticale (cylindre dont l'axe est vertical).
local function pillar(parent: Instance, base: CFrame, height: number, diameter: number, color: Color3, material: Enum.Material?): Part
	return cylinder(base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, 0, math.rad(-90)), height, diameter, {
		Name = "Pillar",
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
end

-- Rappel : Decor.cylinder(cf, h, d) couche l'axe du cylindre sur l'axe Y de `cf`.
-- Cylindre posé à plat (disque) : l'axe du cylindre est vertical.
local function disc(parent: Instance, center: Vector3, height: number, diameter: number, props: { [string]: any }): Part
	return cylinder(CFrame.new(center), height, diameter, props, parent)
end

-- Cône approximé par des disques empilés (sapins, volcans).
local function cone(parent: Instance, base: Vector3, height: number, radius: number, steps: number, color: Color3, material: Enum.Material?, topColor: Color3?)
	for i = 0, steps - 1 do
		local t = i / steps
		local h = height / steps
		local r = radius * (1 - t) + 0.4
		local p = disc(parent, base + Vector3.new(0, h * (i + 0.5), 0), h * 1.02, r * 2, {
			Name = "Cone",
			Color = if topColor and i >= steps - 2 then topColor else color,
			Material = material or Enum.Material.SmoothPlastic,
		})
		p.CastShadow = i < steps - 1
	end
end

----------------------------------------------------------------------------
-- Décors propres à chaque monde
----------------------------------------------------------------------------

local Props = {}

-- CANDY COAST ---------------------------------------------------------------
function Props.candyCane(parent: Instance, base: CFrame, height: number)
	local seg = height / 8
	for i = 0, 7 do
		local p = pillar(parent, base * CFrame.new(0, seg * i, 0), seg, 1.8, if i % 2 == 0 then rgb(255, 60, 80) else rgb(255, 255, 255))
		p.Name = "Cane"
	end
	-- crosse : demi-cercle de boules au sommet
	for i = 1, 5 do
		local a = math.rad(i * 36)
		ball(base * CFrame.new(-2.4 + math.cos(a) * 2.4, height + math.sin(a) * 2.4, 0), 1.9, if i % 2 == 0 then rgb(255, 60, 80) else rgb(255, 255, 255), parent)
	end
end

function Props.lollipop(parent: Instance, base: CFrame, height: number, colorA: Color3, colorB: Color3)
	pillar(parent, base, height, 0.8, rgb(255, 250, 240))
	local top = base * CFrame.new(0, height + 3, 0)
	-- disque vertical (spirale suggérée par 3 anneaux)
	for i, d in { 8, 6, 3.6 } do
		local c = cylinder(top * CFrame.new(0, 0, -0.02 * i) * CFrame.Angles(math.rad(-90), 0, 0), 1 + i * 0.05, d, {
			Name = "Candy",
			Color = if i % 2 == 1 then colorA else colorB,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.1,
		}, parent)
		c.CastShadow = i == 1
	end
end

function Props.gumdrop(parent: Instance, pos: Vector3, size: number, color: Color3)
	local p = ball(CFrame.new(pos + Vector3.new(0, size * 0.15, 0)), size, color, parent)
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0.15
	p.CanCollide = true
	-- sucre
	for _ = 1, 4 do
		local a = math.random() * math.pi * 2
		ball(CFrame.new(pos + Vector3.new(math.cos(a) * size * 0.3, size * 0.55, math.sin(a) * size * 0.3)), size * 0.1, rgb(255, 255, 255), parent)
	end
end

function Props.cupcake(parent: Instance, pos: Vector3, size: number, color: Color3)
	pillar(parent, CFrame.new(pos), size * 0.7, size, rgb(255, 170, 200))
	local cream = ball(CFrame.new(pos + Vector3.new(0, size * 0.85, 0)), size * 1.15, rgb(255, 250, 245), parent)
	cream.CanCollide = true
	ball(CFrame.new(pos + Vector3.new(0, size * 1.25, 0)), size * 0.7, color, parent)
	ball(CFrame.new(pos + Vector3.new(0, size * 1.65, 0)), size * 0.3, rgb(230, 30, 50), parent)
end

-- FROST PEAKS -----------------------------------------------------------------
function Props.pine(parent: Instance, pos: Vector3, height: number)
	pillar(parent, CFrame.new(pos), height * 0.25, 1.6, rgb(120, 80, 50), Enum.Material.Wood)
	for i, s in { 1, 0.75, 0.5 } do
		cone(parent, pos + Vector3.new(0, height * (0.2 + (i - 1) * 0.22), 0), height * 0.32, height * 0.26 * s, 4, rgb(40, 120, 90), Enum.Material.SmoothPlastic, rgb(245, 250, 255))
	end
end

function Props.snowman(parent: Instance, pos: Vector3, size: number)
	local white = rgb(250, 252, 255)
	ball(CFrame.new(pos + Vector3.new(0, size * 0.45, 0)), size, white, parent, Enum.Material.Snow).CanCollide = true
	ball(CFrame.new(pos + Vector3.new(0, size * 1.15, 0)), size * 0.72, white, parent, Enum.Material.Snow)
	local head = ball(CFrame.new(pos + Vector3.new(0, size * 1.65, 0)), size * 0.5, white, parent, Enum.Material.Snow)
	local look = CFrame.lookAt(head.Position, head.Position + Vector3.new(0, 0, -1))
	cylinder(look * CFrame.new(0, 0, -size * 0.3) * CFrame.Angles(math.rad(-90), 0, 0), size * 0.3, size * 0.1, { Name = "Carrot", Color = rgb(255, 140, 40), CanCollide = false }, parent)
	for _, x in { -0.1, 0.1 } do
		ball(look * CFrame.new(x * size, size * 0.06, -size * 0.23), size * 0.07, rgb(20, 20, 30), parent)
	end
	-- écharpe
	disc(parent, pos + Vector3.new(0, size * 1.42, 0), size * 0.12, size * 0.62, { Name = "Scarf", Color = rgb(255, 60, 80), CanCollide = false })
end

function Props.crystal(parent: Instance, pos: Vector3, height: number, color: Color3, material: Enum.Material?)
	local rng = Random.new(math.floor(pos.X * 7 + pos.Z * 13))
	for i = 1, 4 do
		local h = height * rng:NextNumber(0.5, 1)
		local w = height * 0.18
		local p = part({
			Name = "Crystal",
			Size = Vector3.new(w, h, w),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1) * w, h * 0.4, rng:NextNumber(-1, 1) * w)) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber() * math.pi, rng:NextNumber(-0.35, 0.35)),
			Color = color,
			Material = material or Enum.Material.Glass,
			Transparency = if material == Enum.Material.Neon then 0.1 else 0.25,
			Reflectance = 0.2,
		}, parent)
		if i == 1 then
			light(p, color, 14, 0.8)
		end
	end
end

-- VOLCANO CORE ---------------------------------------------------------------
function Props.spike(parent: Instance, pos: Vector3, height: number, color: Color3)
	local rng = Random.new(math.floor(pos.X * 3 + pos.Z * 5))
	for _ = 1, 3 do
		local h = height * rng:NextNumber(0.5, 1)
		part({
			Name = "Obsidian",
			Size = Vector3.new(height * 0.2, h, height * 0.2),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-2, 2), h * 0.4, rng:NextNumber(-2, 2))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber() * math.pi, rng:NextNumber(-0.4, 0.4)),
			Color = color,
			Material = Enum.Material.Glass,
			Reflectance = 0.25,
		}, parent)
	end
end

function Props.vent(parent: Instance, pos: Vector3, glow: Color3)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		ball(CFrame.new(pos + Vector3.new(math.cos(a) * 3, 0.6, math.sin(a) * 3)), 2.4, rgb(50, 36, 40), parent, Enum.Material.Basalt).CanCollide = true
	end
	local core = disc(parent, pos + Vector3.new(0, 0.1, 0), 0.3, 4.4, { Name = "Vent", Color = glow, Material = Enum.Material.Neon, CanCollide = false })
	light(core, glow, 18, 2)
	emitter(core, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Rate = 12,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(8, 14),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0.2) }),
		LightEmission = 0.8,
		Color = ColorSequence.new(rgb(255, 200, 60), rgb(255, 60, 20)),
		SpreadAngle = Vector2.new(12, 12),
	})
end

-- COSMIC RIFT ------------------------------------------------------------------
function Props.planet(parent: Instance, pos: Vector3, size: number, color: Color3, ringColor: Color3?)
	local p = ball(CFrame.new(pos), size, color, parent)
	p.CastShadow = false
	if ringColor then
		cylinder(CFrame.new(pos) * CFrame.Angles(0.35, 0, 0.3), 0.2, size * 1.9, {
			Name = "PlanetRing",
			Color = ringColor,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
			CastShadow = false,
		}, parent)
	end
end

function Props.asteroid(parent: Instance, pos: Vector3, size: number, color: Color3)
	local rng = Random.new(math.floor(pos.X + pos.Z * 11))
	for i = 1, 3 do
		local b = ball(CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * size * 0.3), size * rng:NextNumber(0.55, 1), color:Lerp(rgb(20, 16, 30), rng:NextNumber(0, 0.4)), parent)
		b.CastShadow = i == 1
	end
end

----------------------------------------------------------------------------
-- Arène
----------------------------------------------------------------------------

local function ringPositions(origin: Vector3, entry: Vector3, count: number, rMin: number, rMax: number, rng: Random, avoidEntry: number): { Vector3 }
	local out = {}
	local entryAngle = math.atan2(entry.X, entry.Z)
	for i = 1, count do
		local a = (i + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local diff = math.abs(((a - entryAngle + math.pi) % (math.pi * 2)) - math.pi)
		if diff > avoidEntry then
			local r = rng:NextNumber(rMin, rMax)
			table.insert(out, origin + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r))
		end
	end
	return out
end

-- Portail : arche + disque lumineux traversable. Renvoie le disque (détecteur).
local function portal(parent: Instance, cf: CFrame, color: Color3, glow: Color3, title: string, sub: string, name: string): BasePart
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local width, height = 14, 16
	for _, side in { -1, 1 } do
		part({
			Name = "Post",
			Size = Vector3.new(2.6, height, 2.6),
			CFrame = cf * CFrame.new(side * (width / 2 + 1.3), height / 2, 0),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}, model)
		ball(cf * CFrame.new(side * (width / 2 + 1.3), height + 1.4, 0), 3.6, glow, model, Enum.Material.Neon)
	end
	part({
		Name = "Beam",
		Size = Vector3.new(width + 6, 2.4, 2.8),
		CFrame = cf * CFrame.new(0, height + 0.2, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	}, model)
	local diskCf = cf * CFrame.new(0, height / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	local disk = cylinder(diskCf, 0.6, height - 1, {
		Name = "Gate",
		Color = glow,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CastShadow = false,
	}, model)
	disk.CanTouch = true
	light(disk, glow, 24, 2)
	emitter(disk, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 14,
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 1,
		Color = ColorSequence.new(glow, rgb(255, 255, 255)),
		SpreadAngle = Vector2.new(180, 180),
	})
	floatingSign(model, cf * CFrame.new(0, height + 7, 0), title, glow, 300, 50, 260, "Title")
	floatingSign(model, cf * CFrame.new(0, height + 3.2, 0), sub, Theme.Colors.Paper, 260, 30, 200, "Sub")
	return disk
end

local function buildArena(folder: Folder, world: Worlds.World): WorldInfo
	local pal = world.Palette
	local origin = Worlds.Origin(world.Id)
	local entry = Worlds.EntryDirection(world.Id)
	local rng = Random.new(world.Order * 97)
	local model = Instance.new("Model")
	model.Name = "World_" .. world.Id
	model:SetAttribute("World", world.Id)
	model.Parent = folder

	-- Plateau (falaise ronde qui plonge dans l'océan) + sol
	disc(model, origin + Vector3.new(0, -16, 0), 30, R * 2 + 8, { Name = "Cliff", Color = pal.Rock, Material = Enum.Material.SmoothPlastic })
	disc(model, origin + Vector3.new(0, -0.5, 0), 1, R * 2, { Name = "Floor", Color = pal.Ground, Material = pal.GroundMaterial })
	disc(model, origin + Vector3.new(0, -0.45, 0), 0.9, R * 2 + 4, { Name = "Edge", Color = pal.Rim, Material = Enum.Material.SmoothPlastic })

	-- Lac central lumineux
	local lake = disc(model, origin + Vector3.new(0, 0.05, 0), 0.5, 30, { Name = "Lake", Color = pal.Lava, Material = Enum.Material.Neon, CanCollide = false })
	light(lake, pal.Glow, 50, 2)
	disc(model, origin + Vector3.new(0, 0.02, 0), 0.4, 35, { Name = "LakeRim", Color = pal.Rock, CanCollide = false })

	-- Chemin d'entrée (du portail de retour vers le centre)
	local entryCf = CFrame.lookAt(origin + entry * (R / 2), origin)
	part({
		Name = "Path",
		Size = Vector3.new(12, 0.2, R - 22),
		CFrame = entryCf * CFrame.new(0, 0.05, 0),
		Color = pal.Rim,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	}, model)

	-- Plateformes à météores
	local pads: { BasePart } = {}
	for i = 1, Worlds.PadCount do
		table.insert(pads, Decor.meteorPad(model, Worlds.PadPosition(world.Id, i), i, pal.Rim, pal.Rock))
	end

	-- Anneau de bord (rochers / cristaux) avec une ouverture côté entrée
	for _, pos in ringPositions(origin, entry, 40, R - 5, R - 2, rng, 0.35) do
		local size = rng:NextNumber(5, 9)
		local rock = ball(CFrame.new(pos + Vector3.new(0, size * 0.25, 0)), size, pal.Rock:Lerp(pal.Rim, rng:NextNumber(0, 0.35)), model)
		rock.CanCollide = true
	end

	-- Taches colorées au sol (glaçage, glace, fissures, étoiles) : le sol n'est jamais nu
	local patchColors = {
		Candy = { rgb(255, 250, 250), rgb(150, 230, 255), rgb(255, 240, 150), rgb(200, 160, 255) },
		Frost = { rgb(190, 235, 255), rgb(220, 245, 255) },
		Volcano = { rgb(70, 45, 45), rgb(90, 50, 40) },
		Cosmic = { rgb(70, 50, 140), rgb(90, 60, 170) },
	}
	local patches = patchColors[world.Id]
	if patches then
		for _, pos in ringPositions(origin, entry, 26, 18, R - 14, rng, 0.25) do
			local d = rng:NextNumber(5, 11)
			local patch = disc(model, pos + Vector3.new(0, 0.02, 0), 0.15, d, { Name = "Patch", Color = patches[rng:NextInteger(1, #patches)], CanCollide = false })
			patch.CastShadow = false
			if world.Id == "Frost" then
				patch.Material = Enum.Material.Glass
				patch.Reflectance = 0.3
			elseif world.Id == "Cosmic" then
				-- petites étoiles lumineuses
				ball(CFrame.new(pos + Vector3.new(0, 0.2, 0)), 0.8, pal.Accent, model, Enum.Material.Neon).CastShadow = false
			end
		end
	end

	-- Décor propre au monde (deux anneaux : près du bord et entre les plateformes)
	local decorSpots = ringPositions(origin, entry, 30, 56, R - 10, rng, 0.4)
	for _, pos in ringPositions(origin, entry, 12, 20, 26, rng, 0.5) do
		table.insert(decorSpots, pos)
	end
	if world.Id == "Candy" then
		local colors = { rgb(255, 90, 180), rgb(120, 230, 255), rgb(255, 230, 90), rgb(150, 255, 150), rgb(200, 140, 255) }
		for i, pos in decorSpots do
			local k = i % 4
			local c = colors[rng:NextInteger(1, #colors)]
			if k == 0 then
				Props.candyCane(model, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0), rng:NextNumber(14, 22))
			elseif k == 1 then
				Props.lollipop(model, CFrame.lookAt(pos, origin), rng:NextNumber(12, 18), c, rgb(255, 255, 255))
			elseif k == 2 then
				Props.gumdrop(model, pos, rng:NextNumber(6, 10), c)
			else
				Props.cupcake(model, pos, rng:NextNumber(5, 8), c)
			end
		end
		-- sucette géante au centre, entourée de bonbons
		Props.lollipop(model, CFrame.lookAt(origin, origin + entry), 30, rgb(255, 90, 180), rgb(255, 255, 255))
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			Props.gumdrop(model, origin + Vector3.new(math.sin(a) * 19, 0, math.cos(a) * 19), 3.5, colors[(i % #colors) + 1])
		end
	elseif world.Id == "Frost" then
		for i, pos in decorSpots do
			local k = i % 3
			if k == 0 then
				Props.pine(model, pos, rng:NextNumber(20, 32))
			elseif k == 1 then
				Props.crystal(model, pos, rng:NextNumber(9, 15), rgb(150, 230, 255))
			else
				Props.snowman(model, pos, rng:NextNumber(4.5, 6.5))
			end
		end
		Props.crystal(model, origin, 34, rgb(170, 240, 255))
		-- congères
		for _, pos in ringPositions(origin, entry, 16, 60, R - 6, rng, 0.4) do
			local size = rng:NextNumber(6, 12)
			ball(CFrame.new(pos + Vector3.new(0, -size * 0.2, 0)), size, rgb(248, 252, 255), model, Enum.Material.Snow).CanCollide = true
		end
		emitter(lake, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Rate = 6,
			Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(2, 4),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
			LightEmission = 1,
			Color = ColorSequence.new(rgb(200, 245, 255)),
			SpreadAngle = Vector2.new(60, 60),
		})
	elseif world.Id == "Volcano" then
		for i, pos in decorSpots do
			if i % 3 == 0 then
				Props.vent(model, pos, pal.Glow)
			else
				Props.spike(model, pos, rng:NextNumber(10, 18), rgb(30, 20, 30))
			end
		end
		-- volcan central
		cone(model, origin, 36, 17, 9, rgb(60, 40, 44), Enum.Material.Basalt)
		-- coulées de lave sur les flancs
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2 + 0.4
			part({
				Name = "LavaFlow",
				Size = Vector3.new(2.2, 0.6, 20),
				CFrame = CFrame.new(origin + Vector3.new(math.sin(a) * 10, 18, math.cos(a) * 10)) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-58), 0, 0),
				Color = pal.Lava,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			}, model)
		end
		local crater = disc(model, origin + Vector3.new(0, 36.3, 0), 0.6, 8, { Name = "Magma", Color = pal.Lava, Material = Enum.Material.Neon, CanCollide = false })
		light(crater, pal.Glow, 40, 3)
		emitter(crater, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Rate = 4,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(6, 10),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 18) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(rgb(80, 60, 60)),
			SpreadAngle = Vector2.new(15, 15),
			LightInfluence = 1,
		})
		-- rivières de lave
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2 + 0.2
			local r = rng:NextNumber(20, 50)
			part({
				Name = "LavaRiver",
				Size = Vector3.new(rng:NextNumber(1, 2), 0.2, rng:NextNumber(10, 22)),
				CFrame = CFrame.new(origin + Vector3.new(math.sin(a) * r, 0.03, math.cos(a) * r)) * CFrame.Angles(0, a + rng:NextNumber(-0.5, 0.5), 0),
				Color = pal.Lava,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			}, model)
		end
	elseif world.Id == "Cosmic" then
		for i, pos in decorSpots do
			if i % 2 == 0 then
				Props.crystal(model, pos, rng:NextNumber(10, 17), if i % 4 == 0 then pal.Accent else pal.Glow, Enum.Material.Neon)
			else
				Props.asteroid(model, pos + Vector3.new(0, rng:NextNumber(12, 28), 0), rng:NextNumber(5, 10), pal.Rock)
			end
		end
		-- planètes dans le ciel de l'arène
		Props.planet(model, origin + Vector3.new(40, 70, -30), 22, rgb(255, 150, 210), rgb(255, 230, 150))
		Props.planet(model, origin + Vector3.new(-50, 55, 40), 12, rgb(90, 220, 255), nil)
		Props.planet(model, origin + Vector3.new(10, 90, 50), 8, rgb(255, 220, 120), rgb(170, 120, 255))
		-- la faille : anneau vertical de néon au-dessus du lac
		local rift = CFrame.lookAt(origin + Vector3.new(0, 18, 0), origin + Vector3.new(0, 18, 0) + entry)
		for i = 1, 20 do
			local a = i / 20 * math.pi * 2
			ball(rift * CFrame.new(math.cos(a) * 11, math.sin(a) * 11, 0), 2.6, if i % 2 == 0 then pal.Glow else pal.Accent, model, Enum.Material.Neon)
		end
		local core = part({ Name = "RiftCore", Size = Vector3.new(1, 1, 1), CFrame = rift, Transparency = 1, CanCollide = false }, model)
		light(core, pal.Glow, 60, 3)
		emitter(core, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Rate = 30,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(2, 6),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
			LightEmission = 1,
			Color = ColorSequence.new(pal.Accent, pal.Glow),
			SpreadAngle = Vector2.new(180, 180),
		})
	end

	-- Particules d'ambiance au-dessus de l'arène
	local sky = part({ Name = "Ambience", Size = Vector3.new(R * 1.6, 1, R * 1.6), CFrame = CFrame.new(origin + Vector3.new(0, 45, 0)), Transparency = 1, CanCollide = false, CanQuery = false }, model)
	local ambience = {
		Candy = { "rbxasset://textures/particles/sparkles_main.dds", rgb(255, 150, 220), -2 },
		Frost = { "rbxasset://textures/particles/sparkles_main.dds", rgb(255, 255, 255), -4 },
		Volcano = { "rbxasset://textures/particles/fire_sparks_main.dds", rgb(255, 150, 60), 3 },
		Cosmic = { "rbxasset://textures/particles/sparkles_main.dds", rgb(170, 140, 255), -1 },
	}
	local amb = ambience[world.Id]
	if amb then
		emitter(sky, {
			Name = "AmbienceFx",
			Texture = amb[1],
			Rate = 18,
			Lifetime = NumberRange.new(6, 9),
			Speed = NumberRange.new(1, 3),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.4) }),
			LightEmission = 0.8,
			Color = ColorSequence.new(amb[2]),
			Acceleration = Vector3.new(0, amb[3], 0),
			SpreadAngle = Vector2.new(20, 20),
		})
	end

	-- Panneaux : nom du monde + minuteur du prochain météore
	floatingSign(model, CFrame.new(origin + Vector3.new(0, 46, 0)), string.upper(world.Name), pal.Glow, 560, 76, 1400, "WorldSign")
	floatingSign(model, CFrame.new(origin + Vector3.new(0, 39, 0)), world.Tagline, Theme.Colors.Paper, 520, 32, 400, "WorldSub")
	floatingSign(model, CFrame.new(origin + Vector3.new(0, 33, 0)), "NEXT METEOR IN 10s", Theme.Colors.Gold, 420, 44, 500, "MeteorTimer")

	-- Portail du retour, côté entrée
	local homeCf = CFrame.lookAt(origin + entry * (R - 12), origin)
	local home = portal(model, homeCf, pal.Rock, Theme.Colors.Radioactive, "🏠 HOME", "Back to your island", "HomePortal")

	return { Id = world.Id, Model = model, Pads = pads, HomePortal = home }
end

-- Construit toutes les arènes et les portails du cratère.
function WorldBuilder.Build(mapFolder: Folder, craterPads: { BasePart }): { [string]: WorldInfo }
	local folder = Instance.new("Folder")
	folder.Name = "Worlds"
	folder.Parent = mapFolder
	local out: { [string]: WorldInfo } = {}
	for _, world in Worlds.List do
		if world.Id == Worlds.Default then
			out[world.Id] = { Id = world.Id, Pads = craterPads }
		else
			local info = buildArena(folder, world)
			local hub = portal(folder, Worlds.HubPortal(world.Id), world.Palette.Rock, world.Palette.Glow, string.upper(world.Name), ("LV %d"):format(world.Level), "Portal_" .. world.Id)
			hub:SetAttribute("World", world.Id)
			info.HubPortal = hub
			out[world.Id] = info
		end
	end
	return out
end

return WorldBuilder
