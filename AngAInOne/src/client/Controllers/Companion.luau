--!strict
--[[
	Companion : le compagnon du joueur, MINI-ANGA debout sur son drone AngAInOne (disque volant
	gris Fluent, anneau néon violet #8B7CFF, logo « A » de l'app, petits rotors). Purement LOCAL :
	chaque joueur voit le sien, rien n'est répliqué.

	Modèles : le serveur copie les gabarits `Anga` et `AioDrone` (ModelLibrary, assets/models) dans
	ReplicatedStorage.ClientModels (dossier créé tout de suite, modèles ajoutés dès que chaque
	LoadAsset réussit, parfois bien plus tard). Tant qu'ils n'y sont pas, le client construit un
	SECOURS en primitives : tête blonde, barbe, corps rouge avec un grand « A », sur un disque à
	anneau violet. Chaque modèle qui arrive (ChildAdded, à n'importe quel moment) remplace sa
	partie de secours : le compagnon est reconstruit si le modèle n'y est pas encore.

	Comportement (logique pure testée : CompanionLogic.luau) :
	- suit l'épaule droite du joueur (vue caméra) avec un ressort, flotte doucement (sauf
	  « Réduire les animations », attribut local ReducedMotion), s'incline dans les virages ;
	  regarde la caméra à l'arrêt, sa direction quand il vole ;
	- se cache en vue à la 1re personne (ou collé à la caméra) : il ne bouche jamais la vue
	  (pièces, lumière, écrans SurfaceGui et givre éteints) ;
	- GUIDE : aucun progrès depuis ~20 s en ascension -> il vole un peu devant vers le prochain
	  checkpoint (tag Checkpoint, attribut Stage = ma Stage + 1) avec une flèche-rayon violette,
	  et l'assistant AIO glisse un indice. La flèche vise le checkpoint seulement s'il est en vue
	  directe (lancer de rayon depuis le drone, personnages exclus) ; sinon elle reste
	  horizontale dans sa direction (jamais à travers un mur ni vers le vide) ;
	- RÉACTIONS (petite bulle d'émotion + animation) : content au checkpoint, paniqué pendant
	  l'annonce et le déroulé d'un incident, figé (givré) pendant un FREEZE, triste quand je
	  tombe, fête au monde nettoyé et à la victoire ;
	- pendant l'ascension, les répliques s'affichent dans une bulle au-dessus de lui
	  (Dialogue.SetWorldAnchor) ; au lobby, en mini-jeu ou hors champ : bulle du bas.
	Au lobby, il se contente de flotter à côté du joueur (ni guide ni réaction d'incident).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Store = require(script.Parent.Store)
local Net = require(script.Parent.Net)
local CompanionLogic = require(script.Parent.CompanionLogic)
local Dialogue = require(script.Parent.Parent.UI.Screens.Dialogue)
local Motion = require(script.Parent.Parent.UI.Motion)
local Style = require(script.Parent.Parent.UI.Style)

local Companion = {}

-- Branché par Main : un mini-jeu est-il en cours ? (pas de guide ni de bulle au-dessus d'Anga)
Companion.IsBusy = function(): boolean
	return false
end

-- Indices de l'assistant AIO quand il montre le chemin (courts, drôles, jamais effrayants).
Companion.GuideLines = {
	"Point de restauration en vue ! C'est par là !",
	"Psst ! Le prochain checkpoint est tout près. Suis la flèche !",
	"Recalcul de l'itinéraire… Suis la flèche violette !",
	"Diagnostic terminé : le checkpoint est par ici !",
}

-- Petite bulle d'émotion à côté de la tête d'Anga.
local EMOTE: { [string]: string } = {
	Happy = "😄",
	Panic = "😱",
	Frozen = "🥶",
	Sad = "😢",
	Celebrate = "🎉",
	Guide = "👉",
}

local player = Players.LocalPlayer

local RIDER_HEIGHT = 2.3 -- hauteur de mini-Anga (studs)
local DRONE_WIDTH = 1.9 -- diamètre du drone (studs)
local GUIDE_LINE_COOLDOWN = 45
local ACCENT = Color3.fromHex("8B7CFF")
-- Les modèles regardent vers +Z Roblox (−Y Blender) : demi-tour pour que l'avant = LookVector.
local FLIP = CFrame.Angles(0, math.pi, 0)

type Piece = { Part: BasePart, Offset: CFrame, Spin: boolean }
type Rig = {
	Model: Model,
	Drone: { Piece },
	Rider: { Piece },
	DeckTop: number,
	RiderHeight: number,
	Anchor: BasePart, -- au-dessus de la tête : bulle de dialogue, émotes
	Core: BasePart, -- centre du drone : lumière, départ de la flèche
	Tip: BasePart, -- bout de la flèche-rayon
	Parts: { BasePart },
	CFrames: { CFrame },
	Beam: Beam,
	Frost: Highlight,
	Glows: { Instance }, -- lumières et SurfaceGui du drone / de mini-Anga (éteints si caché)
	Emote: BillboardGui,
	EmoteFrame: Frame,
	EmoteLabel: TextLabel,
	FromModels: boolean,
	HasAnga: boolean, -- mini-Anga vient du vrai modèle (sinon : secours)
	HasDrone: boolean, -- le drone vient du vrai modèle (sinon : secours)
}

local rig: Rig? = nil
local checkpoints: { [BasePart]: number } = {}
local incidentController: any = nil

------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------

local function prepare(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

-- Boîte englobante (axes du monde) d'une liste de pièces : coin min, coin max.
local function bounds(parts: { BasePart }): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in parts do
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local half = Vector3.new(
			math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
			math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
			math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
		) / 2
		lo = lo:Min(cf.Position - half)
		hi = hi:Max(cf.Position + half)
	end
	return lo, hi
end

--[[
	Met un modèle à l'échelle (hauteur `fitHeight` OU largeur `fitWidth`) et renvoie ses pièces avec
	leur décalage par rapport au centre de sa base (avant = LookVector), et sa hauteur finale.
]]
local function collect(root: Instance, fitHeight: number?, fitWidth: number?): ({ Piece }, number)
	local parts: { BasePart } = {}
	for _, node in root:GetDescendants() do
		if node:IsA("BasePart") then
			table.insert(parts, node)
		end
	end
	if #parts == 0 then
		return {}, 0
	end
	local lo, hi = bounds(parts)
	local size = hi - lo
	local scale = if fitHeight
		then fitHeight / math.max(size.Y, 0.01)
		else (fitWidth or 1) / math.max(size.X, size.Z, 0.01)
	local from = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local pieces: { Piece } = {}
	for _, part in parts do
		local cf = part.CFrame
		part.Size *= scale
		prepare(part)
		table.insert(pieces, {
			Part = part,
			Offset = FLIP * CFrame.new((cf.Position - from) * scale) * cf.Rotation,
			Spin = part:GetAttribute("SpinPart") == true,
		})
	end
	return pieces, size.Y * scale
end

local function topOf(pieces: { Piece }, name: string): number?
	for _, piece in pieces do
		if piece.Part.Name == name then
			-- demi-hauteur dans les axes du compagnon (cylindre de secours couché, maillage droit…)
			local cf, size = piece.Offset, piece.Part.Size
			local half = math.abs(cf.RightVector.Y) * size.X
				+ math.abs(cf.UpVector.Y) * size.Y
				+ math.abs(cf.LookVector.Y) * size.Z
			return cf.Position.Y + half / 2
		end
	end
	return nil
end

-- Primitive de secours (modèle de 6 studs de haut, avant vers +Z comme les modèles importés).
local function prim(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	hex: string,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = Color3.fromHex(hex)
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylindre Roblox (axe X) debout (axe Y)

-- Grand « A » (logo) sur la face +Z d'une pièce.
local function logo(part: BasePart, textColor: Color3, pixels: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z : l'avant des modèles
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "A"
	label.TextScaled = true
	label.FontFace = Style.Fonts.Heavy
	label.TextColor3 = textColor
	label.Parent = gui
end

local function fallbackDrone(): Model
	local model = Instance.new("Model")
	model.Name = "AioDrone"
	prim(
		model,
		"Ring",
		Enum.PartType.Cylinder,
		Vector3.new(0.16, 2.6, 2.6),
		CFrame.new(0, 0.34, 0) * UPRIGHT,
		"8B7CFF",
		Enum.Material.Neon
	)
	prim(
		model,
		"Shell",
		Enum.PartType.Cylinder,
		Vector3.new(0.34, 2.36, 2.36),
		CFrame.new(0, 0.33, 0) * UPRIGHT,
		"C5C5C5"
	)
	prim(model, "Deck", Enum.PartType.Cylinder, Vector3.new(0.08, 2.0, 2.0), CFrame.new(0, 0.52, 0) * UPRIGHT, "2B2B2B")
	prim(
		model,
		"Glow",
		Enum.PartType.Cylinder,
		Vector3.new(0.14, 0.9, 0.9),
		CFrame.new(0, 0.1, 0) * UPRIGHT,
		"B9B0FF",
		Enum.Material.Neon
	)
	local badge =
		prim(model, "Badge", Enum.PartType.Block, Vector3.new(0.56, 0.3, 0.12), CFrame.new(0, 0.34, 1.2), "2B2B2B")
	logo(badge, ACCENT, 60)
	for k = 0, 3 do
		local angle = math.rad(45 + 90 * k)
		local at = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 1.45 + Vector3.new(0, 0.46, 0)
		prim(model, "Duct", Enum.PartType.Cylinder, Vector3.new(0.14, 0.6, 0.6), CFrame.new(at) * UPRIGHT, "C5C5C5")
		local blade = prim(
			model,
			`Rotor{k + 1}`,
			Enum.PartType.Block,
			Vector3.new(0.5, 0.04, 0.09),
			CFrame.new(at + Vector3.new(0, 0.1, 0)),
			"E6E6EA"
		)
		blade:SetAttribute("SpinPart", true)
	end
	return model
end

local function fallbackAnga(): Model
	local model = Instance.new("Model")
	model.Name = "Anga"
	local ball, block, cyl = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local SKIN, HAIR, BEARD, SHIRT, PANTS, DARK = "F2C9A8", "F0C24F", "D2A24A", "E53E3E", "24242B", "1B1B2F"
	for _, sx in { -1, 1 } do
		prim(model, "Shoe", block, Vector3.new(0.66, 0.36, 0.95), CFrame.new(sx * 0.46, 0.18, 0.12), DARK)
		prim(model, "Leg", block, Vector3.new(0.72, 1.0, 0.72), CFrame.new(sx * 0.44, 0.85, 0), PANTS)
		prim(model, "Sleeve", cyl, Vector3.new(0.5, 0.64, 0.64), CFrame.new(sx * 1.02, 2.72, 0) * UPRIGHT, SHIRT)
		prim(model, "Arm", cyl, Vector3.new(1.1, 0.4, 0.4), CFrame.new(sx * 1.12, 2.05, 0) * UPRIGHT, SKIN)
		prim(model, "Hand", ball, Vector3.one * 0.5, CFrame.new(sx * 1.15, 1.45, 0.05), SKIN)
		prim(model, "Eye", ball, Vector3.one * 0.2, CFrame.new(sx * 0.4, 4.5, 1.07), DARK)
		prim(model, "Cheek", ball, Vector3.one * 0.3, CFrame.new(sx * 0.62, 4.15, 0.94), "F29A9A")
		prim(model, "Ear", ball, Vector3.one * 0.42, CFrame.new(sx * 1.18, 4.25, 0.05), SKIN)
	end
	prim(model, "Hips", block, Vector3.new(1.7, 0.5, 1.2), CFrame.new(0, 1.45, 0), PANTS)
	prim(model, "Body", cyl, Vector3.new(1.75, 1.95, 1.95), CFrame.new(0, 2.3, 0) * UPRIGHT, SHIRT)
	-- « A » du t-shirt : SurfaceGui sur une plaque invisible posée devant le ventre
	local chest = prim(model, "Logo", block, Vector3.new(1.0, 1.0, 0.05), CFrame.new(0, 2.3, 0.99), SHIRT)
	chest.Transparency = 1
	logo(chest, Color3.fromHex("FFD3DA"), 50)
	prim(model, "Head", ball, Vector3.one * 2.4, CFrame.new(0, 4.25, 0), SKIN)
	prim(model, "Beard", ball, Vector3.one * 2.2, CFrame.new(0, 3.75, 0.2), BEARD)
	prim(model, "Mouth", block, Vector3.new(0.62, 0.26, 0.12), CFrame.new(0, 3.9, 1.26), "5E1C24")
	prim(model, "Teeth", block, Vector3.new(0.5, 0.07, 0.12), CFrame.new(0, 3.99, 1.28), "FFFFFF")
	prim(model, "Nose", ball, Vector3.one * 0.4, CFrame.new(0, 4.2, 1.2), SKIN)
	prim(model, "Hair", ball, Vector3.one * 2.5, CFrame.new(0, 4.65, -0.2), HAIR)
	-- houppe blonde : quelques boules sur le dessus, un peu vers l'avant et vers +X
	prim(model, "Quiff", ball, Vector3.one * 1.0, CFrame.new(0.2, 5.6, 0.35), HAIR)
	prim(model, "Quiff", ball, Vector3.one * 0.8, CFrame.new(-0.4, 5.5, 0.2), HAIR)
	prim(model, "Quiff", ball, Vector3.one * 0.7, CFrame.new(0.65, 5.75, 0.0), HAIR)
	return model
end

local function hidden(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one * 0.2
	part.Transparency = 1
	prepare(part)
	return part
end

local function buildRig(): Rig
	local folder = ReplicatedStorage:FindFirstChild("ClientModels")
	local angaTemplate = if folder then folder:FindFirstChild("Anga") else nil
	local droneTemplate = if folder then folder:FindFirstChild("AioDrone") else nil
	local droneModel: Model = if droneTemplate and droneTemplate:IsA("Model")
		then droneTemplate:Clone()
		else fallbackDrone()
	local riderModel: Model = if angaTemplate and angaTemplate:IsA("Model")
		then angaTemplate:Clone()
		else fallbackAnga()

	local model = Instance.new("Model")
	model.Name = "AngaCompanion"
	local drone = collect(droneModel, nil, DRONE_WIDTH)
	local rider, riderHeight = collect(riderModel, RIDER_HEIGHT, nil)
	droneModel.Parent = model
	riderModel.Parent = model

	local anchor = hidden("Anchor")
	local core = hidden("Core")
	local tip = hidden("Tip")
	for _, part in { anchor, core, tip } do
		part.Parent = model
	end

	-- Lueur violette du drone
	local light = Instance.new("PointLight")
	light.Color = ACCENT
	light.Range = 7
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = core

	-- Flèche-rayon (guide) : large au drone, pointue au bout
	local from = Instance.new("Attachment")
	from.Position = Vector3.new(0, 0, -0.9)
	from.Parent = core
	local to = Instance.new("Attachment")
	to.Parent = tip
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(ACCENT, Color3.fromHex("C9C2FF"))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	beam.Width0 = 0.55
	beam.Width1 = 0.02
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = core

	-- Givre (FREEZE)
	local frost = Instance.new("Highlight")
	frost.FillColor = Color3.fromRGB(170, 225, 255)
	frost.FillTransparency = 0.5
	frost.OutlineColor = Color3.new(1, 1, 1)
	frost.OutlineTransparency = 0.2
	frost.DepthMode = Enum.HighlightDepthMode.Occluded
	frost.Enabled = false
	frost.Parent = model

	-- Bulle d'émotion (à droite de la tête, vue caméra)
	local emote = Instance.new("BillboardGui")
	emote.Name = "Emote"
	emote.Size = UDim2.fromOffset(42, 42)
	emote.StudsOffset = Vector3.new(1.05, -0.35, 0)
	emote.AlwaysOnTop = true
	emote.LightInfluence = 0
	emote.MaxDistance = 120
	emote.Enabled = false
	emote.Adornee = anchor
	emote.Parent = anchor
	local emoteFrame = Instance.new("Frame")
	emoteFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	emoteFrame.Position = UDim2.fromScale(0.5, 0.5)
	emoteFrame.Size = UDim2.fromScale(1, 1)
	emoteFrame.BackgroundColor3 = Style.Color("Surface")
	emoteFrame.BackgroundTransparency = 0.1
	emoteFrame.Parent = emote
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = emoteFrame
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 2
	stroke.Parent = emoteFrame
	local emoteLabel = Instance.new("TextLabel")
	emoteLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emoteLabel.Position = UDim2.fromScale(0.5, 0.5)
	emoteLabel.Size = UDim2.fromScale(0.78, 0.78)
	emoteLabel.BackgroundTransparency = 1
	emoteLabel.Text = ""
	emoteLabel.TextScaled = true
	emoteLabel.FontFace = Style.Fonts.Bold
	emoteLabel.Parent = emoteFrame

	-- Lumières et écrans (SurfaceGui) allumés à la construction : éteints quand il est caché.
	local glows: { Instance } = {}
	for _, node in model:GetDescendants() do
		if (node:IsA("Light") or node:IsA("SurfaceGui")) and (node :: any).Enabled then
			table.insert(glows, node)
		end
	end

	local parts: { BasePart } = {}
	for _, piece in drone do
		table.insert(parts, piece.Part)
	end
	for _, piece in rider do
		table.insert(parts, piece.Part)
	end
	table.insert(parts, anchor)
	table.insert(parts, core)
	table.insert(parts, tip)
	local cframes: { CFrame } = table.create(#parts, CFrame.identity)

	model.Parent = Workspace
	return {
		Model = model,
		Drone = drone,
		Rider = rider,
		DeckTop = topOf(drone, "Deck") or 0.45,
		RiderHeight = riderHeight,
		Anchor = anchor,
		Core = core,
		Tip = tip,
		Parts = parts,
		CFrames = cframes,
		Beam = beam,
		Frost = frost,
		Glows = glows,
		Emote = emote,
		EmoteFrame = emoteFrame,
		EmoteLabel = emoteLabel,
		FromModels = droneTemplate ~= nil or angaTemplate ~= nil,
		HasAnga = angaTemplate ~= nil and angaTemplate:IsA("Model"),
		HasDrone = droneTemplate ~= nil and droneTemplate:IsA("Model"),
	}
end

------------------------------------------------------------------------------------
-- Monde : prochain checkpoint, incident en cours
------------------------------------------------------------------------------------

local function nextCheckpoint(stage: number, from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for pad, padStage in checkpoints do
		if padStage == stage + 1 and pad.Parent then
			local distance = (pad.Position - from).Magnitude
			if distance < bestDistance then
				best, bestDistance = pad, distance
			end
		end
	end
	return best
end

local function incidentNow(): (string, string)
	local controller = incidentController
	if controller and controller.Current then
		local ok, kind, phase = pcall(controller.Current)
		if ok and type(kind) == "string" and type(phase) == "string" then
			return kind, phase
		end
	end
	return "", ""
end

------------------------------------------------------------------------------------
-- Boucle
------------------------------------------------------------------------------------

local position: Vector3? = nil
local velocity = Vector3.zero
local yaw = 0
local fade = 1 -- 0 = visible, 1 = caché
local appliedFade = -1
local spinAngle = 0
local clock = 0
local mood: CompanionLogic.Mood = "Idle"
local reactions: { [string]: number } = {}
local tracker = CompanionLogic.NewTracker(os.clock())
local bubbleState = CompanionLogic.NewDebounce(false)
local guiding = false
local lastGuideLine = -math.huge
local extrasHidden = false -- lumière, écrans et givre éteints (vue à la 1re personne…)
-- Ligne de vue vers le checkpoint : lancer de rayon limité à ~5 fois par seconde.
local SIGHT_INTERVAL = 0.2
local sightTarget: BasePart? = nil
local sightAt = -math.huge
local sightClear = false
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.RespectCanCollide = true -- les zones de déclenchement invisibles ne bloquent pas
sightParams.IgnoreWater = true

local function applyFade(current: Rig, value: number)
	if math.abs(value - appliedFade) < 0.02 and not (value == 1 and appliedFade ~= 1) then
		return
	end
	appliedFade = value
	for _, piece in current.Drone do
		piece.Part.LocalTransparencyModifier = value
	end
	for _, piece in current.Rider do
		piece.Part.LocalTransparencyModifier = value
	end
end

local function setMood(current: Rig, value: CompanionLogic.Mood)
	if mood == value then
		return
	end
	mood = value
	local glyph = EMOTE[value]
	current.Emote.Enabled = glyph ~= nil
	current.Frost.Enabled = value == "Frozen" and not extrasHidden
	if glyph then
		current.EmoteLabel.Text = glyph
		Motion.Pop(current.EmoteFrame, 0.35)
	end
end

-- Lumière, écrans SurfaceGui et givre : éteints quand il est caché (sinon ils flottent seuls).
local function setExtrasHidden(current: Rig, value: boolean)
	if extrasHidden == value then
		return
	end
	extrasHidden = value
	for _, glow in current.Glows do
		(glow :: any).Enabled = not value
	end
	current.Frost.Enabled = not value and mood == "Frozen"
end

-- Le checkpoint est-il en vue directe depuis le drone ? (personnages et compagnon exclus)
local function inSight(current: Rig, from: Vector3, target: BasePart, now: number): boolean
	if target == sightTarget and now - sightAt < SIGHT_INTERVAL then
		return sightClear
	end
	sightTarget, sightAt = target, now
	local ignore: { Instance } = { current.Model }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	sightParams.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(from, target.Position - from, sightParams)
	local hit = result and result.Instance
	sightClear = hit == nil or hit == target or hit:IsDescendantOf(target) or target:IsDescendantOf(hit)
	return sightClear
end

local function hide(current: Rig)
	fade = 1
	applyFade(current, 1)
	setExtrasHidden(current, true)
	current.Beam.Enabled = false
	current.Emote.Enabled = false
	Dialogue.SetWorldAnchor(nil)
	CompanionLogic.Settle(bubbleState, false, os.clock(), 0)
end

local function update(dt: number)
	local current = rig
	if not current then
		return
	end
	dt = math.clamp(dt, 0, 0.1)
	clock += dt
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not (camera and root and root:IsA("BasePart")) then
		hide(current)
		return
	end
	local reduced = player:GetAttribute("ReducedMotion") == true
	local state = Store.State
	local inRun = state ~= nil and not state.AtLobby and state.Data ~= nil and state.Data.RunStarted == true
	local busy = Companion.IsBusy()

	-- Progression et guide
	local stage = if state and state.Data and type(state.Data.Stage) == "number" then state.Data.Stage else 0
	local target = if inRun then nextCheckpoint(stage, root.Position) else nil
	local distance = if target then (target.Position - root.Position).Magnitude else nil
	CompanionLogic.Track(tracker, stage, distance, now)
	local kind, phase = "", ""
	if inRun then
		kind, phase = incidentNow()
	end
	local wasGuiding = guiding
	guiding = inRun and CompanionLogic.ShouldGuide(tracker, now, distance, busy or phase ~= "")
	if guiding and not wasGuiding and now - lastGuideLine > GUIDE_LINE_COOLDOWN and not Dialogue.IsBusy() then
		lastGuideLine = now
		Dialogue.Say(Companion.GuideLines[math.random(1, #Companion.GuideLines)], 3.5, "AIO")
	end

	setMood(
		current,
		CompanionLogic.Mood({
			Now = now,
			Until = reactions,
			IncidentKind = kind,
			IncidentPhase = phase,
			Guiding = guiding,
		})
	)

	-- Suivi (ressort) : épaule droite vue de la caméra, ou devant pour guider
	local camCF = camera.CFrame
	local guideDir = if guiding and target then target.Position - root.Position else nil
	local goal = CompanionLogic.FollowTarget(root.Position, camCF.RightVector, camCF.LookVector, guideDir)
	if mood == "Sad" then
		goal -= Vector3.new(0, 0.4, 0)
	end
	local pos = position or goal
	if (pos - goal).Magnitude > 60 then -- réapparition, téléportation : il nous rejoint d'un coup
		pos, velocity = goal, Vector3.zero
	end
	if mood == "Frozen" then
		velocity = Vector3.zero -- givré sur place
	else
		pos, velocity = CompanionLogic.Spring(pos, velocity, goal, dt, if guiding then 1.1 else 1.6, 0.8)
	end
	position = pos

	-- Orientation : vers le checkpoint (guide), sa direction (vol), sinon la caméra
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local wantYaw = if guideDir then CompanionLogic.YawOf(guideDir) else nil
	if not wantYaw and flatVelocity.Magnitude > 4 then
		wantYaw = CompanionLogic.YawOf(flatVelocity)
	end
	if not wantYaw then
		wantYaw = CompanionLogic.YawOf(camCF.Position - pos)
	end
	if wantYaw and mood ~= "Frozen" then
		yaw = CompanionLogic.LerpAngle(yaw, wantYaw, CompanionLogic.Damp(5, dt))
	end

	-- Inclinaison dans le sens du vol, flottement, réactions
	local heading = CFrame.Angles(0, yaw, 0)
	local localVelocity = heading:VectorToObjectSpace(velocity)
	local pitch = math.clamp(localVelocity.Z * 0.02, -0.25, 0.25)
	local roll = math.clamp(-localVelocity.X * 0.02, -0.25, 0.25)
	local bob = 0
	local riderReaction = CFrame.identity
	if not reduced and mood ~= "Frozen" then
		bob = math.sin(clock * 2.2) * 0.16
		if mood == "Happy" then
			riderReaction = CFrame.new(0, math.abs(math.sin(clock * 9)) * 0.35, 0)
		elseif mood == "Celebrate" then
			riderReaction = CFrame.new(0, math.abs(math.sin(clock * 8)) * 0.4, 0) * CFrame.Angles(0, clock * 7, 0)
		elseif mood == "Panic" then
			riderReaction = CFrame.Angles(0, math.sin(clock * 35) * 0.18, math.sin(clock * 28) * 0.06)
			roll += math.sin(clock * 20) * 0.08
		elseif mood == "Guide" then
			riderReaction = CFrame.Angles(-0.12, 0, 0)
		end
	end
	if mood == "Sad" then
		riderReaction = CFrame.Angles(-0.22, 0, 0) -- tête basse
	end
	local spinSpeed = if mood == "Frozen" then 0 elseif mood == "Sad" then 10 else 30
	if not reduced then
		spinAngle = (spinAngle + spinSpeed * dt) % (2 * math.pi)
	end

	local base = CFrame.new(pos) * heading * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, bob, 0)
	local riderBase = base * CFrame.new(0, current.DeckTop - 0.02, 0) * riderReaction
	local cframes = current.CFrames
	local index = 0
	local spin = CFrame.Angles(0, spinAngle, 0)
	for _, piece in current.Drone do
		index += 1
		cframes[index] = if piece.Spin then base * piece.Offset * spin else base * piece.Offset
	end
	for _, piece in current.Rider do
		index += 1
		cframes[index] = riderBase * piece.Offset
	end
	local anchorCF = riderBase * CFrame.new(0, current.RiderHeight + 0.1, 0)
	local coreCF = base * CFrame.new(0, current.DeckTop * 0.5, 0)
	local tipPosition = coreCF.Position
	-- Flèche : droit sur le checkpoint s'il est en vue, sinon à l'horizontale dans sa direction.
	local beamDir: Vector3? = nil
	if guiding and target then
		local toTarget = target.Position - coreCF.Position
		beamDir = CompanionLogic.BeamDirection(toTarget, inSight(current, coreCF.Position, target, now))
	end
	if beamDir then
		tipPosition += beamDir.Unit * math.min(CompanionLogic.BEAM_LENGTH, beamDir.Magnitude)
	end
	cframes[index + 1] = CFrame.new(anchorCF.Position)
	cframes[index + 2] = coreCF
	cframes[index + 3] = CFrame.new(tipPosition)
	Workspace:BulkMoveTo(current.Parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	-- Visibilité : caché en 1re personne ou collé à la caméra (il ne bouche jamais la vue)
	local head = if character then character:FindFirstChild("Head") else nil
	local eyeDistance = if head and head:IsA("BasePart") then (camCF.Position - head.Position).Magnitude else 10
	local camDistance = (camCF.Position - coreCF.Position).Magnitude
	local wantFade = CompanionLogic.WantFade(eyeDistance, camDistance)
	fade += (wantFade - fade) * CompanionLogic.Damp(10, dt)
	if wantFade == 1 and fade > 0.97 then
		fade = 1
	end
	applyFade(current, fade)
	local shown = fade < 0.5
	setExtrasHidden(current, fade > 0.97)
	current.Beam.Enabled = shown and guiding and beamDir ~= nil
	current.Emote.Enabled = shown and EMOTE[mood] ~= nil

	-- Bulle de dialogue au-dessus d'Anga (ascension, à l'écran, place au-dessus pour la bulle)
	local onScreen = false
	if shown then
		local point, inView = camera:WorldToViewportPoint(current.Anchor.Position)
		local size = camera.ViewportSize
		onScreen = inView
			and point.Z > 0
			and point.X > 80
			and point.X < size.X - 80
			and point.Y > 140
			and point.Y < size.Y - 60
	end
	local want = CompanionLogic.WantsWorldBubble(inRun, busy, shown, onScreen)
	local useWorld = CompanionLogic.Settle(bubbleState, want, now, 0.3)
	Dialogue.SetWorldAnchor(if useWorld then current.Anchor else nil)
end

------------------------------------------------------------------------------------
-- Démarrage
------------------------------------------------------------------------------------

local function rebuild()
	local old = rig
	rig = nil
	if old then
		Dialogue.SetWorldAnchor(nil)
		old.Model:Destroy()
	end
	appliedFade = -1
	mood = "Idle"
	extrasHidden = false
	sightTarget = nil
	rig = buildRig()
end

-- Un vrai modèle est-il arrivé que le compagnon actuel n'utilise pas encore ? Reconstruit
-- alors (une seule fois pour des modèles arrivés ensemble : petit délai de regroupement).
local refreshQueued = false
local function refreshModels()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(0.2, function()
		refreshQueued = false
		local folder = ReplicatedStorage:FindFirstChild("ClientModels")
		if not folder then
			return
		end
		local anga = folder:FindFirstChild("Anga")
		local drone = folder:FindFirstChild("AioDrone")
		local hasAnga = anga ~= nil and anga:IsA("Model")
		local hasDrone = drone ~= nil and drone:IsA("Model")
		local current = rig
		if current and (current.HasAnga or not hasAnga) and (current.HasDrone or not hasDrone) then
			return -- rien de neuf : déjà construit avec les modèles présents
		end
		rebuild()
	end)
end

-- Dossier ClientModels (créé par le serveur au début du préchargement) : ce qui y est déjà,
-- puis chaque modèle ajouté plus tard.
local function watchModels()
	local function watch(folder: Instance)
		folder.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Anga" or child.Name == "AioDrone" then
				refreshModels()
			end
		end)
		refreshModels()
	end
	local folder = ReplicatedStorage:FindFirstChild("ClientModels")
	if folder then
		watch(folder)
		return
	end
	local connection: RBXScriptConnection
	connection = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "ClientModels" then
			connection:Disconnect()
			watch(child)
		end
	end)
end

local function onFx(kind: string, payload: any)
	local now = os.clock()
	if kind == "Checkpoint" then
		reactions.Happy = now + CompanionLogic.DURATION.Happy
	elseif kind == "Death" then
		if type(payload) == "table" and payload.UserId == player.UserId then
			reactions.Sad = now + CompanionLogic.DURATION.Sad
		end
	elseif kind == "WorldCleared" then
		reactions.Celebrate = now + CompanionLogic.DURATION.Celebrate
	elseif kind == "Victory" then
		reactions.Celebrate = now + CompanionLogic.DURATION.Celebrate * 1.6
	end
end

local function trackCheckpoints()
	local function add(instance: Instance)
		local stage = instance:GetAttribute("Stage")
		if instance:IsA("BasePart") and type(stage) == "number" then
			checkpoints[instance] = stage
		end
	end
	for _, instance in CollectionService:GetTagged("Checkpoint") do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal("Checkpoint"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Checkpoint"):Connect(function(instance: Instance)
		checkpoints[instance :: any] = nil
	end)
end

function Companion.Start()
	-- Incident en cours (même module que celui démarré par Main) ; absent = pas de panique.
	local ok, controller = pcall(require, script.Parent.IncidentController :: ModuleScript)
	incidentController = if ok then controller else nil

	trackCheckpoints()
	Net.On("Fx", onFx)
	rebuild()

	watchModels()

	local errors = 0
	RunService:BindToRenderStep("AngaCompanion", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		xpcall(update, function(err: any)
			errors += 1
			if errors <= 3 then
				warn("[Companion]", err)
			end
			Dialogue.SetWorldAnchor(nil)
		end, dt)
	end)
end

return Companion
