--!nonstrict
-- Villes-jouets du mode RAMPAGE : construites à la demande par le serveur (une
-- ville privée par partie, détruite à la fin) + portail d'entrée sur chaque île.
-- Style « jouet » : blocs pastel à fenêtres, routes à pointillés, arbres-sucettes,
-- petites voitures. Chaque immeuble porte les attributs HP / MaxHP / Value.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.Layout)
local Theme = require(Shared.Config.Theme)
local Rampage = require(Shared.Config.Rampage)

local CityBuilder = {}

export type Building = {
	Id: number,
	Kind: string,
	Model: Model,
	Position: Vector3, -- centre au sol
	HalfX: number, -- demi-emprise au sol (axes du monde)
	HalfZ: number,
	Height: number,
	HP: number,
	MaxHP: number,
	Value: number,
	Golden: boolean,
	Color: Color3,
	Alive: boolean,
}

export type City = {
	Model: Model,
	Origin: Vector3,
	Half: number,
	Spawn: CFrame,
	Roads: { number }, -- positions (relatives) des axes des routes
	Buildings: { Building },
	TotalHP: number,
}

local rgb = Color3.fromRGB
local WINDOW = rgb(170, 230, 255)
local DOOR = rgb(90, 60, 70)
local GOLD = rgb(255, 200, 40)

local function part(props: { [string]: any }, parent: Instance?): BasePart
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	for k, v in props do
		if k ~= "ClassName" then
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function cylinder(cf: CFrame, height: number, diameter: number, props: { [string]: any }, parent: Instance?): BasePart
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	return part(props, parent)
end

local function ball(cf: CFrame, diameter: number, color: Color3, parent: Instance)
	return part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(diameter, diameter, diameter), CFrame = cf, Color = color }, parent)
end

local function billboard(parent: BasePart, text: string, color: Color3, width: number, height: number, maxDistance: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SignGui"
	gui.Size = UDim2.fromOffset(width, height)
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Adornee = parent
	gui.Parent = parent
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
	return gui
end

local function darker(c: Color3, k: number): Color3
	return c:Lerp(Theme.Colors.Ink, k)
end

----------------------------------------------------------------------------
-- Portail sur l'île
----------------------------------------------------------------------------

-- Pose le portail RAMPAGE d'une île. Renvoie la pièce touchable « RampagePortal »
-- (enfant direct du modèle de l'île : le tutoriel pointe une flèche dessus).
function CityBuilder.BuildPortal(plot: any): BasePart
	local base = plot.CFrame * CFrame.new(Layout.RampagePortal)
	-- le portail regarde l'allée centrale (+X local de l'île)
	local face = base * CFrame.Angles(0, -math.pi / 2, 0)
	local decor = Instance.new("Model")
	decor.Name = "RampagePortalDecor"
	decor.Parent = plot.Model

	cylinder(face * CFrame.new(0, 0.3, 0), 0.6, 14, { Name = "Base", Color = Theme.Colors.Ink, Material = Enum.Material.Metal, CanCollide = true }, decor)
	local pad = cylinder(face * CFrame.new(0, 0.65, 0), 0.3, 11, {
		Name = "RampagePortal",
		Color = Theme.Colors.Pink,
		Material = Enum.Material.Neon,
		CanTouch = true,
		CastShadow = false,
	}, plot.Model)
	pad.Transparency = 0.15
	-- anneau de blocs-jouets
	local center = face * CFrame.new(0, 8, 0)
	local segments = 16
	for i = 0, segments - 1 do
		local a = i / segments * math.pi * 2
		part({
			Name = "Ring",
			Size = Vector3.new(2.9, 1.5, 2),
			CFrame = center * CFrame.Angles(0, 0, a) * CFrame.new(0, 7, 0),
			Color = if i % 2 == 0 then Theme.Colors.Gold else Theme.Colors.Pink,
			CanCollide = i >= segments / 4 * 3 or i <= segments / 4,
		}, decor)
	end
	local swirl = cylinder(center * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(-90)), 0.4, 12.5, {
		Name = "Swirl",
		Color = Theme.Colors.Purple,
		Material = Enum.Material.Neon,
		CastShadow = false,
	}, decor)
	swirl.Transparency = 0.3
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new(Theme.Colors.Pink, Theme.Colors.Gold)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Speed = NumberRange.new(2, 6)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Rate = 14
	sparkles.Parent = swirl
	local light = Instance.new("PointLight")
	light.Color = Theme.Colors.Pink
	light.Range = 24
	light.Brightness = 2
	light.Shadows = false
	light.Parent = swirl
	-- mini-immeubles de chaque côté (ça annonce la couleur)
	for _, side in { -1, 1 } do
		local x = side * 8.6
		part({ Name = "MiniTower", Size = Vector3.new(2.6, 7, 2.6), CFrame = face * CFrame.new(x, 3.5, 1.5), Color = if side < 0 then rgb(150, 215, 255) else rgb(255, 170, 190), CanCollide = true }, decor)
		part({ Name = "MiniWindows", Size = Vector3.new(2.8, 0.7, 2.8), CFrame = face * CFrame.new(x, 4.6, 1.5), Color = WINDOW }, decor)
		part({ Name = "MiniHouse", Size = Vector3.new(2.6, 2.5, 2.6), CFrame = face * CFrame.new(x, 1.25, -3.6), Color = rgb(255, 225, 120), CanCollide = true }, decor)
	end
	local signAnchor = part({ Name = "SignAnchor", Size = Vector3.new(1, 1, 1), CFrame = face * CFrame.new(0, 18.5, 0), Transparency = 1, CanQuery = false }, decor)
	billboard(signAnchor, "🏙️ RAMPAGE!", Theme.Colors.Magma, 300, 60, 160)
	local subAnchor = part({ Name = "SubAnchor", Size = Vector3.new(1, 1, 1), CFrame = face * CFrame.new(0, 16, 0), Transparency = 1, CanQuery = false }, decor)
	billboard(subAnchor, "Become your kaiju & smash a toy city!", Theme.Colors.Paper, 330, 26, 110)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RampagePrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "RAMPAGE!"
	prompt.ObjectText = "Toy City Portal"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Color", "Magma")
	prompt.Parent = pad
	return pad
end

----------------------------------------------------------------------------
-- Immeubles
----------------------------------------------------------------------------

-- Toit à deux pans (deux coins) au-dessus d'un bloc de taille `size`.
local function gableRoof(model: Model, cf: CFrame, size: Vector3, height: number, color: Color3)
	local halfDepth = size.Z / 2 + 0.3
	local roofCf = cf * CFrame.new(0, size.Y + height / 2, 0)
	part({ ClassName = "WedgePart", Name = "Roof", Size = Vector3.new(size.X + 0.6, height, halfDepth), CFrame = roofCf * CFrame.new(0, 0, -halfDepth / 2), Color = color }, model)
	part({ ClassName = "WedgePart", Name = "Roof", Size = Vector3.new(size.X + 0.6, height, halfDepth), CFrame = roofCf * CFrame.new(0, 0, halfDepth / 2) * CFrame.Angles(0, math.pi, 0), Color = color }, model)
end

-- Bande de fenêtres qui fait le tour du bloc.
local function windows(model: Model, cf: CFrame, size: Vector3, y: number, h: number, color: Color3?)
	part({ Name = "Windows", Size = Vector3.new(size.X + 0.2, h, size.Z + 0.2), CFrame = cf * CFrame.new(0, y, 0), Color = color or WINDOW, Material = Enum.Material.SmoothPlastic }, model)
end

local function door(model: Model, cf: CFrame, size: Vector3, w: number, h: number)
	part({ Name = "Door", Size = Vector3.new(w, h, 0.3), CFrame = cf * CFrame.new(0, h / 2, -size.Z / 2 - 0.1), Color = DOOR }, model)
end

local DECOR: { [string]: (Model, CFrame, Vector3, Color3, Color3, Random) -> () } = {
	Shack = function(model, cf, size, color, accent, _rng)
		gableRoof(model, cf, size, 2.2, darker(accent, 0.1))
		windows(model, cf, size, size.Y * 0.62, 0.8)
		door(model, cf, size, 1.4, 2.2)
	end,
	House = function(model, cf, size, color, accent, _rng)
		gableRoof(model, cf, size, 3, darker(accent, 0.15))
		windows(model, cf, size, size.Y * 0.68, 1.1)
		door(model, cf, size, 1.8, 2.8)
		part({ Name = "Chimney", Size = Vector3.new(1.1, 2.6, 1.1), CFrame = cf * CFrame.new(size.X * 0.28, size.Y + 2.2, size.Z * 0.2), Color = darker(color, 0.25) }, model)
	end,
	Shop = function(model, cf, size, color, accent, _rng)
		part({ Name = "RoofSlab", Size = Vector3.new(size.X + 0.8, 0.6, size.Z + 0.8), CFrame = cf * CFrame.new(0, size.Y + 0.3, 0), Color = darker(color, 0.2) }, model)
		part({ Name = "ShopWindow", Size = Vector3.new(size.X * 0.8, size.Y * 0.4, 0.3), CFrame = cf * CFrame.new(0, size.Y * 0.35, -size.Z / 2 - 0.1), Color = WINDOW }, model)
		for i = 0, 3 do
			local w = size.X / 4
			part({
				Name = "Awning",
				Size = Vector3.new(w, 0.3, 2),
				CFrame = cf * CFrame.new(-size.X / 2 + w * (i + 0.5), size.Y * 0.68, -size.Z / 2 - 0.9) * CFrame.Angles(math.rad(-18), 0, 0),
				Color = if i % 2 == 0 then accent else Theme.Colors.White,
			}, model)
		end
		part({ Name = "SignBoard", Size = Vector3.new(size.X * 0.6, 1.2, 0.4), CFrame = cf * CFrame.new(0, size.Y + 1.2, -size.Z / 2 + 0.4), Color = accent, Material = Enum.Material.Neon }, model)
	end,
	Tower = function(model, cf, size, color, accent, _rng)
		for k = 1, 5 do
			windows(model, cf, size, size.Y * (k - 0.35) / 5.4, 1)
		end
		part({ Name = "Cap", Size = Vector3.new(size.X + 0.6, 0.8, size.Z + 0.6), CFrame = cf * CFrame.new(0, size.Y + 0.4, 0), Color = accent }, model)
		part({ Name = "Antenna", Size = Vector3.new(0.4, 4, 0.4), CFrame = cf * CFrame.new(0, size.Y + 2.8, 0), Color = Theme.Colors.Ink }, model)
		part({ Name = "Beacon", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = cf * CFrame.new(0, size.Y + 5, 0), Color = Theme.Colors.Red, Material = Enum.Material.Neon }, model)
	end,
	HQ = function(model, cf, size, color, accent, _rng)
		-- blocs de construction empilés
		local mid = Vector3.new(size.X * 0.72, size.Y * 0.28, size.Z * 0.72)
		part({ Name = "Stack", Size = mid, CFrame = cf * CFrame.new(0, size.Y + mid.Y / 2, 0), Color = accent }, model)
		local top = Vector3.new(size.X * 0.45, size.Y * 0.2, size.Z * 0.45)
		part({ Name = "Stack", Size = top, CFrame = cf * CFrame.new(0, size.Y + mid.Y + top.Y / 2, 0), Color = Theme.Colors.Gold }, model)
		for k = 1, 4 do
			windows(model, cf, size, size.Y * (k - 0.4) / 4.3, 1.4)
		end
		windows(model, cf * CFrame.new(0, size.Y, 0), mid, mid.Y * 0.5, 1.2)
		local topY = size.Y + mid.Y + top.Y
		part({ Name = "Pole", Size = Vector3.new(0.5, 7, 0.5), CFrame = cf * CFrame.new(0, topY + 3.5, 0), Color = Theme.Colors.Ink }, model)
		part({ Name = "Flag", Size = Vector3.new(3.6, 2.2, 0.2), CFrame = cf * CFrame.new(1.9, topY + 5.8, 0), Color = Theme.Colors.Magma }, model)
		door(model, cf, size, 4, 5)
	end,
}

local function buildBuilding(parent: Instance, id: number, def: Rampage.BuildingDef, cf: CFrame, color: Color3, accent: Color3, hpMult: number, golden: boolean, rng: Random): Building
	local model = Instance.new("Model")
	model.Name = "B" .. id
	local size = def.Size
	local bodyColor = if golden then GOLD else color
	local body = part({
		Name = "Body",
		Size = size,
		CFrame = cf * CFrame.new(0, size.Y / 2, 0),
		Color = bodyColor,
		Material = if golden then Enum.Material.Foil else Enum.Material.SmoothPlastic,
		CanCollide = true,
	}, model)
	model.PrimaryPart = body
	DECOR[def.Id](model, cf, size, bodyColor, if golden then rgb(255, 240, 150) else accent, rng)
	if golden then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "GoldSparkles"
		sparkle.Color = ColorSequence.new(GOLD, Theme.Colors.White)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Speed = NumberRange.new(1, 4)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Rate = 10
		sparkle.Parent = body
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 18
		light.Brightness = 2
		light.Parent = body
	end
	local hp = math.floor(def.HP * hpMult + 0.5)
	local value = def.Value * (if golden then Rampage.GoldenValueMult else 1)
	model:SetAttribute("Id", id)
	model:SetAttribute("Kind", def.Id)
	model:SetAttribute("HP", hp)
	model:SetAttribute("MaxHP", hp)
	model:SetAttribute("Value", value)
	model:SetAttribute("Golden", golden)
	model.Parent = parent

	-- emprise au sol dans les axes du monde (rotations par quarts de tour)
	local right = cf.RightVector
	local alongX = math.abs(right.X) > 0.5
	return {
		Id = id,
		Kind = def.Id,
		Model = model,
		Position = cf.Position,
		HalfX = (if alongX then size.X else size.Z) / 2,
		HalfZ = (if alongX then size.Z else size.X) / 2,
		Height = size.Y,
		HP = hp,
		MaxHP = hp,
		Value = value,
		Golden = golden,
		Color = bodyColor,
		Alive = true,
	}
end

----------------------------------------------------------------------------
-- Décor
----------------------------------------------------------------------------

local function lollipopTree(parent: Instance, cf: CFrame, height: number, rng: Random)
	cylinder(cf * CFrame.new(0, height / 2, 0), height, 0.8,{ Name = "Trunk", Color = rgb(150, 100, 60) }, parent)
	local colors = { rgb(120, 220, 110), rgb(255, 150, 200), rgb(110, 200, 255), rgb(255, 210, 90) }
	ball(cf * CFrame.new(0, height + 1.2, 0), 3.4, colors[rng:NextInteger(1, #colors)], parent)
end

local function toyCar(parent: Instance, cf: CFrame, color: Color3)
	part({ Name = "CarBody", Size = Vector3.new(2.6, 1.1, 4.6), CFrame = cf * CFrame.new(0, 1, 0), Color = color }, parent)
	part({ Name = "CarCabin", Size = Vector3.new(2.2, 1, 2.2), CFrame = cf * CFrame.new(0, 2, 0.3), Color = WINDOW }, parent)
	for _, z in { -1.4, 1.4 } do
		-- essieu : cylindre couché qui dépasse de chaque côté (deux roues d'un coup)
		part({ Name = "Wheels", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.1, 1.1), CFrame = cf * CFrame.new(0, 0.55, z), Color = Theme.Colors.Ink }, parent)
	end
end

----------------------------------------------------------------------------
-- Ville
----------------------------------------------------------------------------

local function shuffle<T>(list: { T }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Construit une ville-jouet. `hpMult` multiplie les PV (quartier, tutoriel).
function CityBuilder.Build(parent: Instance, name: string, origin: Vector3, district: Rampage.District, hpMult: number, seed: number): City
	local rng = Random.new(seed)
	local B, R, N = Rampage.Block, Rampage.Road, Rampage.Blocks
	local half = Rampage.Half
	local o = CFrame.new(origin)
	local model = Instance.new("Model")
	model.Name = name
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = model
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = model
	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "Buildings"
	buildingsFolder.Parent = model

	-- Sol : tapis de jeu, plaque de la ville (routes), trottoirs surélevés
	part({ Name = "PlayMat", Size = Vector3.new(660, 1, 660), CFrame = o * CFrame.new(0, -2.5, 0), Color = darker(district.Ground, 0.12), CanCollide = true }, ground)
	part({ Name = "Streets", Size = Vector3.new(half * 2 + 20, 2, half * 2 + 20), CFrame = o * CFrame.new(0, -1, 0), Color = rgb(112, 118, 150), CanCollide = true }, ground)
	local roads: { number } = {}
	for k = 0, N do
		table.insert(roads, -half + R / 2 + k * (B + R))
	end
	local blockCenters: { number } = {}
	for k = 0, N - 1 do
		table.insert(blockCenters, -half + R + B / 2 + k * (B + R))
	end
	for _, bx in blockCenters do
		for _, bz in blockCenters do
			part({ Name = "Sidewalk", Size = Vector3.new(B, 0.5, B), CFrame = o * CFrame.new(bx, 0.25, bz), Color = district.Ground, CanCollide = true }, ground)
		end
	end
	-- pointillés au milieu des routes
	for _, r in roads do
		for _, c in blockCenters do
			part({ Name = "Dash", Size = Vector3.new(0.6, 0.06, B * 0.55), CFrame = o * CFrame.new(r, 0.03, c), Color = rgb(255, 235, 120) }, ground)
			part({ Name = "Dash", Size = Vector3.new(B * 0.55, 0.06, 0.6), CFrame = o * CFrame.new(c, 0.03, r), Color = rgb(255, 235, 120) }, ground)
		end
	end
	-- bordure-jouet colorée + murs invisibles
	local edge = half + 10
	for _, side in { -1, 1 } do
		part({ Name = "Curb", Size = Vector3.new(edge * 2 + 3, 1.6, 3), CFrame = o * CFrame.new(0, 0.8, side * (edge + 1.5)), Color = district.Accent, CanCollide = true }, ground)
		part({ Name = "Curb", Size = Vector3.new(3, 1.6, edge * 2 + 3), CFrame = o * CFrame.new(side * (edge + 1.5), 0.8, 0), Color = district.Accent, CanCollide = true }, ground)
		part({ Name = "Wall", Size = Vector3.new(edge * 2 + 6, 80, 2), CFrame = o * CFrame.new(0, 40, side * (edge + 3)), Transparency = 1, CanCollide = true, CanQuery = false }, ground)
		part({ Name = "Wall", Size = Vector3.new(2, 80, edge * 2 + 6), CFrame = o * CFrame.new(side * (edge + 3), 40, 0), Transparency = 1, CanCollide = true, CanQuery = false }, ground)
	end

	-- Emplacements : 4 par pâté ; le QG occupe un pâté central entier
	local center = { 2, 3 } -- pâtés centraux (grille 4x4)
	local hqBlock = Vector2.new(center[rng:NextInteger(1, 2)], center[rng:NextInteger(1, 2)])
	local slots: { { pos: Vector3, face: Vector3 } } = {}
	for ix, bx in blockCenters do
		for iz, bz in blockCenters do
			if not (ix == hqBlock.X and iz == hqBlock.Y) then
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local face = if rng:NextNumber() < 0.5 then Vector3.new(sx, 0, 0) else Vector3.new(0, 0, sz)
						table.insert(slots, { pos = Vector3.new(bx + sx * B / 4, 0.5, bz + sz * B / 4), face = face })
					end
				end
			end
		end
	end
	shuffle(slots, rng)

	local kinds: { Rampage.BuildingDef } = {}
	local hqDef: Rampage.BuildingDef? = nil
	for _, def in Rampage.Buildings do
		if def.Id == "HQ" then
			hqDef = def
		else
			for _ = 1, def.Count do
				table.insert(kinds, def)
			end
		end
	end
	local goldenIndex = rng:NextInteger(1, #kinds)

	local buildings: { Building } = {}
	local totalHP = 0
	local palette = district.Palette
	for i, def in kinds do
		local slot = slots[i]
		local cf = o * CFrame.lookAt(slot.pos, slot.pos + slot.face)
		local color = palette[rng:NextInteger(1, #palette)]
		local accent = palette[rng:NextInteger(1, #palette)]
		local b = buildBuilding(buildingsFolder, i, def, cf, color, accent, hpMult, i == goldenIndex, rng)
		table.insert(buildings, b)
		totalHP += b.MaxHP
	end
	if hqDef then
		local pos = Vector3.new(blockCenters[hqBlock.X], 0.5, blockCenters[hqBlock.Y])
		local cf = o * CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
		local b = buildBuilding(buildingsFolder, #kinds + 1, hqDef, cf, district.Accent, Theme.Colors.Cyan, hpMult, false, rng)
		table.insert(buildings, b)
		totalHP += b.MaxHP
	end
	-- emplacements restants : petits parcs
	for i = #kinds + 1, #slots do
		local slot = slots[i]
		local cf = o * CFrame.new(slot.pos)
		lollipopTree(decor, cf * CFrame.new(-2.5, 0, -2), rng:NextNumber(3, 4.5), rng)
		lollipopTree(decor, cf * CFrame.new(2.5, 0, 2.5), rng:NextNumber(3, 4.5), rng)
	end
	-- voitures-jouets garées le long des routes
	local carColors = { Theme.Colors.Red, Theme.Colors.Cyan, Theme.Colors.Gold, Theme.Colors.Radioactive, Theme.Colors.Purple }
	for i = 1, 8 do
		local r = roads[rng:NextInteger(2, #roads - 1)]
		local c = blockCenters[rng:NextInteger(1, #blockCenters)] + rng:NextNumber(-8, 8)
		local lane = if rng:NextNumber() < 0.5 then -3 else 3
		local cf = if i % 2 == 0 then o * CFrame.new(r + lane, 0, c) else o * CFrame.new(c, 0, r + lane) * CFrame.Angles(0, math.pi / 2, 0)
		toyCar(decor, cf, carColors[rng:NextInteger(1, #carColors)])
	end

	-- Entrée : départ au milieu de la route sud, face au centre
	local spawnPos = origin + Vector3.new(0, 3.5, roads[#roads])
	local spawn = CFrame.lookAt(spawnPos, spawnPos + Vector3.new(0, 0, -1))
	local signAnchor = part({ Name = "CitySign", Size = Vector3.new(1, 1, 1), CFrame = o * CFrame.new(0, 20, half + 6), Transparency = 1, CanQuery = false }, decor)
	billboard(signAnchor, ("🏙️ %s"):format(string.upper(district.Name)), district.Accent, 420, 70, 400)

	model.Parent = parent
	return {
		Model = model,
		Origin = origin,
		Half = half,
		Spawn = spawn,
		Roads = roads,
		Buildings = buildings,
		TotalHP = totalHP,
	}
end

-- Dossier racine des villes (créé à la demande).
function CityBuilder.Folder(): Folder
	local folder = Workspace:FindFirstChild("RampageCities")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RampageCities"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

return CityBuilder
