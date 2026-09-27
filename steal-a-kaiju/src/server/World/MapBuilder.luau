--!nonstrict
-- Construit toute la carte au démarrage du serveur : océan, îles, cratère,
-- ponts, bases des joueurs, volcan, éclairage. Aucune pièce à placer à la main.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Config.Layout)
local Theme = require(Shared.Config.Theme)

local MapBuilder = {}

export type PlotInfo = {
	Index: number,
	CFrame: CFrame,
	Model: Model,
	Color: Color3,
	Nests: { BasePart },
	Collector: BasePart,
	CollectorGui: SurfaceGui,
	LockButton: BasePart,
	PersonalPad: BasePart,
	Sign: BillboardGui,
	Gate: BasePart,
}

export type MapInfo = {
	Plots: { PlotInfo },
	MeteorPads: { BasePart },
	Boards: { CFrame },
	BossSpot: CFrame,
	Hub: CFrame,
}

local rgb = Color3.fromRGB

local PLOT_COLORS = {
	rgb(124, 255, 79),
	rgb(255, 106, 31),
	rgb(255, 61, 139),
	rgb(61, 224, 255),
	rgb(255, 200, 40),
	rgb(150, 80, 255),
	rgb(255, 60, 60),
	rgb(90, 255, 200),
}

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

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

----------------------------------------------------------------------------
-- Ambiance
----------------------------------------------------------------------------

local function setupLighting()
	-- Lighting.Technology n'est pas modifiable par script : réglé dans default.project.json
	Lighting.Brightness = 2.6
	Lighting.ClockTime = 15.2
	Lighting.Ambient = rgb(70, 60, 90)
	Lighting.OutdoorAmbient = rgb(140, 128, 160)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GeographicLatitude = 30
	Lighting.FogColor = rgb(200, 220, 255)
	Lighting.FogEnd = 4000

	for _, child in Lighting:GetChildren() do
		child:Destroy()
	end

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 16
	sky.StarCount = 4000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.2
	atmosphere.Color = rgb(199, 190, 230)
	atmosphere.Decay = rgb(120, 90, 160)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.9
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Saturation = 0.22
	cc.Contrast = 0.08
	cc.Brightness = 0.02
	cc.TintColor = rgb(255, 248, 240)
	cc.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting

	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.12
	dof.FocusDistance = 120
	dof.InFocusRadius = 140
	dof.NearIntensity = 0
	dof.Parent = Lighting

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = rgb(255, 240, 250)
	clouds.Parent = Workspace.Terrain
end

local function setupTerrain()
	local terrain = Workspace.Terrain
	terrain.WaterColor = rgb(30, 160, 200)
	terrain.WaterTransparency = 0.35
	terrain.WaterWaveSize = 0.25
	terrain.WaterWaveSpeed = 12
	terrain.WaterReflectance = 0.6
	terrain:SetMaterialColor(Enum.Material.Grass, rgb(96, 190, 90))
	terrain:SetMaterialColor(Enum.Material.Sand, rgb(240, 214, 160))
	terrain:SetMaterialColor(Enum.Material.Basalt, rgb(50, 40, 50))
	terrain:SetMaterialColor(Enum.Material.Rock, rgb(120, 105, 110))

	-- Océan
	terrain:FillBlock(CFrame.new(0, -18, 0), Vector3.new(2400, 24, 2400), Enum.Material.Water)
	-- Fond marin
	terrain:FillBlock(CFrame.new(0, -34, 0), Vector3.new(2400, 8, 2400), Enum.Material.Sand)

	-- Le terrain s'arrête 0,6 stud sous le sol des pièces : pas de scintillement
	-- (z-fighting) entre le terrain et les sols construits.
	local TOP = -0.6
	-- Île centrale
	terrain:FillCylinder(CFrame.new(0, TOP - 14, 0), 26, 132, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, TOP - 11, 0), 22, 122, Enum.Material.Grass)
	terrain:FillCylinder(CFrame.new(0, TOP - 12, 0), 24, Layout.CraterRadius + 4, Enum.Material.Basalt)

	-- Îles des joueurs
	for i = 1, Layout.PlotCount do
		local cf = Layout.PlotCFrame(i)
		local pos = cf.Position
		terrain:FillCylinder(CFrame.new(pos.X, TOP - 14, pos.Z), 26, 92, Enum.Material.Sand)
		terrain:FillCylinder(CFrame.new(pos.X, TOP - 11, pos.Z), 22, 84, Enum.Material.Grass)
	end
end

----------------------------------------------------------------------------
-- Cratère central
----------------------------------------------------------------------------

local function buildCrater(folder: Folder): ({ BasePart }, { CFrame }, CFrame)
	local crater = Instance.new("Model")
	crater.Name = "Crater"
	crater.Parent = folder

	-- Sol calciné
	cylinder(CFrame.new(0, -0.5, 0), 1, Layout.CraterRadius * 2, {
		Name = "Floor",
		Color = rgb(58, 46, 60),
		Material = Enum.Material.Basalt,
	}, crater)

	-- Fissures de lave (néon)
	local rng = Random.new(42)
	for i = 1, 22 do
		local a = rng:NextNumber() * math.pi * 2
		local r = rng:NextNumber(8, Layout.CraterRadius - 12)
		local len = rng:NextNumber(8, 22)
		local crack = part({
			Name = "Lava",
			Size = Vector3.new(rng:NextNumber(0.6, 1.4), 0.2, len),
			CFrame = CFrame.new(math.cos(a) * r, 0.02, math.sin(a) * r) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
			Color = rgb(255, 110, 30),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		}, crater)
		if i % 4 == 0 then
			light(crack, rgb(255, 120, 40), 16, 1.2)
		end
	end

	-- Anneau de rochers avec 8 ouvertures (les ponts)
	for i = 1, 64 do
		local a = i / 64 * math.pi * 2
		local sector = (a / (math.pi * 2)) * Layout.PlotCount
		local gap = math.abs(sector - math.floor(sector + 0.5))
		if gap > 0.26 then
			local r = Layout.CraterRadius + rng:NextNumber(-1, 3)
			local size = rng:NextNumber(6, 11)
			local rock = part({
				Name = "Rock",
				Size = Vector3.new(size, size * rng:NextNumber(0.7, 1.4), size),
				CFrame = CFrame.new(math.sin(a) * r, size * 0.3, math.cos(a) * r)
					* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber() * 6, rng:NextNumber(-0.4, 0.4)),
				Color = rgb(80, 66, 78):Lerp(rgb(120, 100, 110), rng:NextNumber()),
				Material = Enum.Material.Slate,
			}, crater)
			rock.CastShadow = true
		end
	end

	-- Plateformes des météores
	local pads: { BasePart } = {}
	local count = 6
	for i = 1, count do
		local pos = Layout.MeteorPad(i, count)
		local base = cylinder(CFrame.new(pos + Vector3.new(0, 0.6, 0)), 1.2, 16, {
			Name = "MeteorPad" .. i,
			Color = rgb(40, 32, 48),
			Material = Enum.Material.Metal,
		}, crater)
		local ring = cylinder(CFrame.new(pos + Vector3.new(0, 1.25, 0)), 0.15, 17, {
			Name = "Ring",
			Color = Theme.Colors.Magma,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		}, crater)
		ring.Transparency = 0.2
		base:SetAttribute("Index", i)
		table.insert(pads, base)
	end

	-- Fumée volcanique au centre
	local smoke = part({
		Name = "SmokeSource",
		Size = Vector3.new(20, 1, 20),
		CFrame = CFrame.new(0, 0.5, 0),
		Transparency = 1,
		CanCollide = false,
	}, crater)
	emitter(smoke, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 3,
		Lifetime = NumberRange.new(6, 9),
		Speed = NumberRange.new(4, 8),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 22) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(90, 80, 90)),
		SpreadAngle = Vector2.new(20, 20),
		LightInfluence = 1,
	})
	emitter(smoke, {
		Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
		Rate = 8,
		Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(6, 14),
		Size = NumberSequence.new(0.6),
		LightEmission = 1,
		Color = ColorSequence.new(rgb(255, 150, 60)),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, -8, 0),
	})

	-- Tableaux des scores (face à l'extérieur, entre deux ponts)
	local boards: { CFrame } = {}
	for i, angleDeg in { 22.5 + 45 * 1, 22.5 + 45 * 3, 22.5 + 45 * 5 } do
		local a = math.rad(angleDeg)
		local pos = Vector3.new(math.sin(a) * (Layout.CraterRadius + 26), 0, math.cos(a) * (Layout.CraterRadius + 26))
		boards[i] = CFrame.lookAt(pos, pos * 2)
	end

	local bossSpot = CFrame.new(0, 0, 0)

	-- Lieu d'apparition neutre (les joueurs sont ensuite téléportés chez eux)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Parent = crater

	return pads, boards, bossSpot
end

----------------------------------------------------------------------------
-- Ponts
----------------------------------------------------------------------------

local function buildBridge(folder: Folder, index: number)
	local plotCf = Layout.PlotCFrame(index)
	local dir = -plotCf.Position.Unit -- vers le centre
	local startPos = dir * -(Layout.CraterRadius - 2) -- bord du cratère (côté île)
	local endPos = plotCf.Position + plotCf.LookVector * (Layout.PlotDepth / 2 - 1)
	local mid = (startPos + endPos) / 2
	local len = (endPos - startPos).Magnitude
	local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(endPos.X, 0, endPos.Z))
	local bridge = Instance.new("Model")
	bridge.Name = "Bridge" .. index
	bridge.Parent = folder
	part({
		Name = "Deck",
		Size = Vector3.new(Layout.BridgeWidth, 1.4, len),
		CFrame = cf * CFrame.new(0, -0.7, 0),
		Color = rgb(170, 120, 80),
		Material = Enum.Material.WoodPlanks,
	}, bridge)
	for _, side in { -1, 1 } do
		part({
			Name = "Rail",
			Size = Vector3.new(1, 1, len),
			CFrame = cf * CFrame.new(side * (Layout.BridgeWidth / 2 - 0.5), 2.6, 0),
			Color = rgb(120, 80, 50),
			Material = Enum.Material.Wood,
		}, bridge)
		local posts = math.floor(len / 18)
		for j = 0, posts do
			local z = -len / 2 + j * (len / posts)
			part({
				Name = "Post",
				Size = Vector3.new(1.2, 3.2, 1.2),
				CFrame = cf * CFrame.new(side * (Layout.BridgeWidth / 2 - 0.5), 1.6, z),
				Color = rgb(110, 70, 45),
				Material = Enum.Material.Wood,
			}, bridge)
			if j % 2 == 0 then
				local lamp = part({
					Name = "Lamp",
					Size = Vector3.new(1.4, 1.4, 1.4),
					CFrame = cf * CFrame.new(side * (Layout.BridgeWidth / 2 - 0.5), 3.9, z),
					Color = rgb(255, 210, 120),
					Material = Enum.Material.Neon,
					Shape = Enum.PartType.Ball,
					CanCollide = false,
				}, bridge)
				light(lamp, rgb(255, 200, 120), 18, 1)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Bases des joueurs
----------------------------------------------------------------------------

local function buildPlot(folder: Folder, index: number): PlotInfo
	local cf = Layout.PlotCFrame(index)
	local color = PLOT_COLORS[index]
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("Index", index)
	model.Parent = folder

	local W, D = Layout.PlotWidth, Layout.PlotDepth
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- Sol en damier doux
	part({ Name = "Floor", Size = Vector3.new(W, 1, D), CFrame = at(0, -0.5, 0), Color = rgb(110, 200, 100), Material = Enum.Material.Grass }, model)
	part({ Name = "Path", Size = Vector3.new(14, 1.05, D), CFrame = at(0, -0.48, 0), Color = rgb(235, 215, 170), Material = Enum.Material.Pavement }, model)
	part({ Name = "Trim", Size = Vector3.new(W + 2, 0.8, D + 2), CFrame = at(0, -0.9, 0), Color = color, Material = Enum.Material.SmoothPlastic }, model)

	-- Murets (avec ouverture de porte à l'avant)
	local wallH, wallT = 4, 2
	local wallColor = rgb(240, 228, 200)
	part({ Name = "WallBack", Size = Vector3.new(W, wallH, wallT), CFrame = at(0, wallH / 2, D / 2 - wallT / 2), Color = wallColor, Material = Enum.Material.Brick }, model)
	for _, side in { -1, 1 } do
		part({ Name = "WallSide", Size = Vector3.new(wallT, wallH, D), CFrame = at(side * (W / 2 - wallT / 2), wallH / 2, 0), Color = wallColor, Material = Enum.Material.Brick }, model)
		local frontLen = (W - Layout.BridgeWidth) / 2
		part({
			Name = "WallFront",
			Size = Vector3.new(frontLen, wallH, wallT),
			CFrame = at(side * (Layout.BridgeWidth / 2 + frontLen / 2), wallH / 2, -D / 2 + wallT / 2),
			Color = wallColor,
			Material = Enum.Material.Brick,
		}, model)
		-- Piliers de porte à rayures
		for k = 0, 5 do
			part({
				Name = "GatePost",
				Size = Vector3.new(3.2, 2, 3.2),
				CFrame = at(side * (Layout.BridgeWidth / 2 + 1.6), 1 + k * 2, -D / 2 + 1.6),
				Color = if k % 2 == 0 then Theme.Colors.Ink else color,
				Material = Enum.Material.SmoothPlastic,
			}, model)
		end
		local beacon = part({
			Name = "Beacon",
			Size = Vector3.new(2.4, 2.4, 2.4),
			Shape = Enum.PartType.Ball,
			CFrame = at(side * (Layout.BridgeWidth / 2 + 1.6), 13.2, -D / 2 + 1.6),
			Color = color,
			Material = Enum.Material.Neon,
		}, model)
		light(beacon, color, 22, 1.5)
	end

	-- Laser de porte (visible quand le bouclier est actif ; géré côté client)
	local gate = part({
		Name = "Gate",
		Size = Vector3.new(Layout.BridgeWidth, 10, 0.4),
		CFrame = at(0, 5, -D / 2 + 1.6),
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, model)

	-- Nids
	local nests: { BasePart } = {}
	for i, local_ in Layout.Nests do
		local nest = cylinder(at(local_.X, 0.25, local_.Z), 0.5, 12, {
			Name = "Nest" .. i,
			Color = rgb(160, 120, 80),
			Material = Enum.Material.WoodPlanks,
		}, model)
		local ring = cylinder(at(local_.X, 0.52, local_.Z), 0.06, 12.8, {
			Name = "NestRing",
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		}, model)
		ring.Transparency = 0.5
		nest:SetAttribute("Slot", i)
		nests[i] = nest
		-- brindilles décoratives
		for k = 1, 6 do
			local a = k / 6 * math.pi * 2
			part({
				Name = "Twig",
				Size = Vector3.new(0.5, 0.5, 4),
				CFrame = at(local_.X + math.cos(a) * 5.4, 0.7, local_.Z + math.sin(a) * 5.4) * CFrame.Angles(0, -a, math.rad(20)),
				Color = rgb(130, 90, 55),
				Material = Enum.Material.Wood,
				CanCollide = false,
			}, model)
		end
	end

	-- Réacteur à cash (collecteur)
	local reactorBase = at(Layout.Collector.X, 0, Layout.Collector.Z)
	cylinder(reactorBase * CFrame.new(0, 0.4, 0), 0.8, 13, { Name = "CollectorBase", Color = Theme.Colors.Ink, Material = Enum.Material.Metal }, model)
	local collector = cylinder(reactorBase * CFrame.new(0, 0.9, 0), 0.4, 11, {
		Name = "CollectorPad",
		Color = Theme.Colors.Cash,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	collector.Transparency = 0.2
	cylinder(reactorBase * CFrame.new(0, 6, 4.5), 7, 5, { Name = "Tank", Color = rgb(140, 255, 140), Material = Enum.Material.Glass, Transparency = 0.45, CanCollide = false }, model)
	local core = cylinder(reactorBase * CFrame.new(0, 6, 4.5), 6, 2.2, { Name = "Core", Color = Theme.Colors.Cash, Material = Enum.Material.Neon, CanCollide = false }, model)
	light(core, Theme.Colors.Cash, 20, 1.5)
	cylinder(reactorBase * CFrame.new(0, 10, 4.5), 1, 6, { Name = "Cap", Color = Theme.Colors.Ink, Material = Enum.Material.Metal }, model)
	local screen = part({ Name = "Screen", Size = Vector3.new(12, 5, 0.6), CFrame = reactorBase * CFrame.new(0, 14.5, 4.5) * CFrame.Angles(0, math.pi, 0), Color = Theme.Colors.Ink }, model)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CollectorGui"
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(480, 200)
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = screen
	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.7)
	label.FontFace = Theme.Fonts.Title
	label.TextScaled = true
	label.TextColor3 = Theme.Colors.Cash
	label.Text = "$0"
	label.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Hint"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.68)
	sub.Size = UDim2.fromScale(1, 0.3)
	sub.FontFace = Theme.Fonts.Body
	sub.TextScaled = true
	sub.TextColor3 = Theme.Colors.Paper
	sub.Text = "STEP ON THE PAD TO COLLECT"
	sub.Parent = gui

	-- Bouton de verrouillage (gros bouton rouge)
	local lockCf = at(Layout.LockButton.X, 0, Layout.LockButton.Z)
	cylinder(lockCf * CFrame.new(0, 0.6, 0), 1.2, 10, { Name = "LockBase", Color = Theme.Colors.Ink, Material = Enum.Material.Metal }, model)
	local lock = cylinder(lockCf * CFrame.new(0, 1.5, 0), 0.8, 7.5, {
		Name = "LockButton",
		Color = Theme.Colors.Red,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		part({
			Name = "Hazard",
			Size = Vector3.new(1.6, 0.3, 3),
			CFrame = lockCf * CFrame.new(math.cos(a) * 6.2, 0.1, math.sin(a) * 6.2) * CFrame.Angles(0, -a, 0),
			Color = if k % 2 == 0 then Theme.Colors.Gold else Theme.Colors.Ink,
		}, model)
	end

	-- Plateforme du météore personnel
	local personal = cylinder(at(Layout.PersonalPad.X, 0.5, Layout.PersonalPad.Z), 1, 12, {
		Name = "PersonalPad",
		Color = rgb(40, 32, 48),
		Material = Enum.Material.Metal,
	}, model)
	local pring = cylinder(at(Layout.PersonalPad.X, 1.05, Layout.PersonalPad.Z), 0.1, 12.6, {
		Name = "PersonalRing",
		Color = Theme.Colors.Cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	pring.Transparency = 0.3

	-- Panneau du propriétaire
	local signPart = part({ Name = "SignAnchor", Size = Vector3.new(1, 1, 1), CFrame = at(0, 18, -D / 2 + 1.6), Transparency = 1, CanCollide = false }, model)
	local sign = Instance.new("BillboardGui")
	sign.Name = "OwnerSign"
	sign.Size = UDim2.fromOffset(360, 90)
	sign.MaxDistance = 400
	sign.LightInfluence = 0
	sign.AlwaysOnTop = false
	sign.Parent = signPart
	local signLabel = Instance.new("TextLabel")
	signLabel.Name = "Title"
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.FontFace = Theme.Fonts.Title
	signLabel.TextScaled = true
	signLabel.TextColor3 = Theme.Colors.Paper
	signLabel.Text = "EMPTY ISLAND"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Theme.Colors.Ink
	stroke.Parent = signLabel
	signLabel.Parent = sign

	-- Décor : palmiers et rochers en bordure extérieure
	local rng = Random.new(index * 1337)
	for k = 1, 7 do
		local side = if k % 2 == 0 then 1 else -1
		local x = side * (W / 2 + rng:NextNumber(8, 22))
		local z = rng:NextNumber(-D / 2 + 10, D / 2 - 5)
		local base = at(x, 0, z)
		local h = rng:NextNumber(14, 22)
		for s = 0, 5 do
			part({
				Name = "Trunk",
				Size = Vector3.new(2 - s * 0.15, h / 6 + 0.3, 2 - s * 0.15),
				CFrame = base * CFrame.new(s * 0.35 * side, h / 12 + s * h / 6, 0) * CFrame.Angles(0, 0, math.rad(-6 * side)),
				Color = rgb(150, 100, 60):Lerp(rgb(120, 80, 50), s / 5),
				Material = Enum.Material.Wood,
			}, model)
		end
		local top = base * CFrame.new(2.1 * side, h, 0)
		for leaf = 1, 6 do
			local a = leaf / 6 * math.pi * 2
			local l = Instance.new("WedgePart")
			l.Anchored = true
			l.Size = Vector3.new(0.4, 1.4, 9)
			l.CFrame = top * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.8, 4.2) * CFrame.Angles(math.rad(22), 0, 0)
			l.Color = rgb(70, 170, 70):Lerp(rgb(110, 210, 90), rng:NextNumber())
			l.Material = Enum.Material.Grass
			l.CanCollide = false
			l.Parent = model
		end
	end

	return {
		Index = index,
		CFrame = cf,
		Model = model,
		Color = color,
		Nests = nests,
		Collector = collector,
		CollectorGui = gui,
		LockButton = lock,
		PersonalPad = personal,
		Sign = sign,
		Gate = gate,
	}
end

----------------------------------------------------------------------------
-- Volcan en toile de fond
----------------------------------------------------------------------------

local function buildVolcano(folder: Folder)
	local terrain = Workspace.Terrain
	local center = Vector3.new(-120, 0, 720)
	local layers = 14
	for i = 0, layers do
		local r = 240 - i * 15
		local y = -20 + i * 14
		terrain:FillCylinder(CFrame.new(center.X, y, center.Z), 16, r, if i < 4 then Enum.Material.Sand else Enum.Material.Basalt)
	end
	terrain:FillCylinder(CFrame.new(center.X, -20 + layers * 14 + 4, center.Z), 12, 22, Enum.Material.Air)
	local lava = cylinder(CFrame.new(center.X, -20 + layers * 14 - 2, center.Z), 2, 46, {
		Name = "VolcanoLava",
		Color = rgb(255, 100, 20),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, folder)
	light(lava, rgb(255, 110, 30), 60, 3)
	emitter(lava, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 4,
		Lifetime = NumberRange.new(10, 16),
		Speed = NumberRange.new(10, 18),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 20), NumberSequenceKeypoint.new(1, 70) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(rgb(70, 60, 70)),
		SpreadAngle = Vector2.new(15, 15),
		Acceleration = Vector3.new(4, 2, 0),
		LightInfluence = 1,
	})
end

----------------------------------------------------------------------------

function MapBuilder.Build(): MapInfo
	setupLighting()
	setupTerrain()

	local folder = Instance.new("Folder")
	folder.Name = "Map"
	folder.Parent = Workspace

	local pads, boards, bossSpot = buildCrater(folder)
	local plots: { PlotInfo } = {}
	for i = 1, Layout.PlotCount do
		buildBridge(folder, i)
		plots[i] = buildPlot(folder, i)
	end
	buildVolcano(folder)

	for _, name in { "Kaijus", "Meteors", "Effects", "Orbs" } do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = Workspace
	end

	return {
		Plots = plots,
		MeteorPads = pads,
		Boards = boards,
		BossSpot = bossSpot,
		Hub = CFrame.new(0, 3, 0),
	}
end

return MapBuilder
