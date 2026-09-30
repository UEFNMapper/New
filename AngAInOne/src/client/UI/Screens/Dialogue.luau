--!strict
--[[
	Dialogue : Anga te parle, dans une bulle DISCRÈTE (compacte, translucide, au-dessus du dock).
	- Petit portrait rond à gauche + plaque de nom
	- Texte qui s'écrit lettre par lettre, avec une petite "voix" (bip) toutes les 3 lettres
	- Le portrait s'anime pendant qu'il parle
	- Clic / tap sur la boîte : termine la phrase, puis passe à la suivante
	- Flèche ▼ qui clignote quand la phrase est finie

	- Trois voix : Anga (rouge AngaTV, par défaut), LAGZ (violet glitché, voix grave) et AIO
	  (l'assistant de l'app AngAInOne : gris Fluent + violet #8B7CFF, petite voix de robot)

	- Pendant l'ascension, quand le compagnon (mini-Anga sur son drone, Companion.luau) est à
	  l'écran, la réplique s'affiche dans une BULLE AU-DESSUS DE LUI (BillboardGui compact, verre
	  Fluent, sans portrait) : on ne quitte plus le jeu des yeux. Sinon (lobby, mini-jeu, compagnon
	  hors champ) : la bulle du bas, comme avant. Même texte, même frappe, même file d'attente.

	API :
		Dialogue.Say(texte, durée?, personnage?) -- réplique ponctuelle (file d'attente) ;
		                                         -- personnage : "Anga" (défaut) | "LAGZ" | "AIO"
		Dialogue.SetPersistent(texte?)    -- réplique de tutoriel qui reste affichée (nil = aucune)
		Dialogue.IsBusy()                 -- une réplique ponctuelle est affichée ou en attente
		Dialogue.SetLift(pixels)          -- remonte la bulle du bas (bouton JOUER affiché)
		Dialogue.SetWorldAnchor(pièce?)   -- (Companion) ancre de la bulle au-dessus d'Anga ;
		                                  -- nil = bulle du bas
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Branding = require(Shared.Config.Branding)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Lagz = require(script.Parent.Parent.Components.Lagz)

local New = Create.New

local Dialogue = {}

-- Branché par le contrôleur audio : petit bip de "voix" (pitch varié).
Dialogue.OnBlip = nil :: ((pitch: number) -> ())?

export type Speaker = "Anga" | "LAGZ" | "AIO"
type Line = { Text: string, Duration: number, Speaker: Speaker }

-- Couleurs de l'app AngAInOne (voix AIO).
local AIO_ACCENT = Color3.fromHex("8B7CFF")
local AIO_CARD = Color3.fromHex("2B2B2B")

local CHAR_DELAY = 0.022
local box: TextButton
local textLabel: TextLabel
local portrait: Frame
local portraitStroke: UIStroke
local angaLook: { GuiObject } = {}
local lagzLook: { GuiObject } = {}
local aioLook: { GuiObject } = {}
local speaking: Speaker = "Anga"
local arrow: Frame
local queue: { Line } = {}
local persistent: string? = nil
local showing: string? = nil
local typing = false
local skipTyping = false
local lineToken = 0
local visible = false
-- Au-dessus du dock (96 + 14) ; `lift` en plus quand le bouton JOUER / CONTINUER est affiché.
local lift = 0

------------------------------------------------------------------------------------
-- Bulle au-dessus d'Anga (compagnon) : BillboardGui compact, sans portrait
------------------------------------------------------------------------------------

local WORLD_TEXT = 17 -- lisible sur téléphone
local WORLD_MAX = 250 -- largeur max du texte (px)
local WORLD_PAD = 12
local world: BillboardGui? = nil
local bubble: TextButton
local bubbleText: TextLabel
local bubbleArrow: Frame
local bubbleStroke: UIStroke
local bubbleTag: Frame
local bubbleTagLabel: TextLabel
local bubbleTagStroke: UIStroke
local anchor: BasePart? = nil
local boxShown = false
local worldShown = false

-- Taille de la bulle pour ce texte (mesurée sur le texte COMPLET : elle ne bouge pas pendant
-- la frappe). Largeur ajustée aux répliques courtes, retour à la ligne au-delà de WORLD_MAX.
local function sizeBubble(text: string)
	local gui = world
	if not gui then
		return
	end
	local ok, bounds = pcall(function(): Vector2
		return TextService:GetTextSize(text, WORLD_TEXT, Enum.Font.BuilderSansBold, Vector2.new(WORLD_MAX, 1000))
	end)
	local measured = if ok then bounds else Vector2.new(WORLD_MAX, WORLD_TEXT * 2.4)
	local width = math.clamp(math.ceil(measured.X), 80, WORLD_MAX) + WORLD_PAD * 2 + 10
	local height = math.ceil(measured.Y) + WORLD_PAD * 2 + 4
	bubble.Size = UDim2.fromOffset(width, height)
	gui.Size = UDim2.fromOffset(width + 16, height + 30)
end

local function setBoxShown(value: boolean)
	if boxShown == value then
		return
	end
	boxShown = value
	local scale = Motion.ScaleOf(box)
	if value then
		box.Visible = true
		scale.Scale = 0.96
		box.Position = UDim2.new(0.5, 0, 1, -(96 + 14 + 4 + lift))
		Motion.Tween(scale, { Scale = 1 }, 0.2)
		Motion.Tween(box, { Position = UDim2.new(0.5, 0, 1, -(96 + 14 + 12 + lift)) }, 0.2)
	else
		Motion.Tween(scale, { Scale = 0.9 }, 0.18).Completed:Once(function()
			if not boxShown then
				box.Visible = false
			end
		end)
	end
end

local function setWorldShown(value: boolean)
	local gui = world
	if worldShown == value or not gui then
		return
	end
	worldShown = value
	local scale = Motion.ScaleOf(bubble)
	if value then
		gui.Enabled = true
		scale.Scale = 0.7
		Motion.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	else
		Motion.Tween(scale, { Scale = 0.6 }, 0.14).Completed:Once(function()
			if not worldShown then
				gui.Enabled = false
			end
		end)
	end
end

-- Affiche la bonne vue : bulle au-dessus d'Anga si une ancre est fournie, sinon bulle du bas.
local function applyViews()
	local useWorld = visible and anchor ~= nil and world ~= nil
	setWorldShown(useWorld)
	setBoxShown(visible and not useWorld)
end

local function setVisible(value: boolean)
	if visible == value then
		return
	end
	visible = value
	applyViews()
end

-- Texte, lettres visibles et flèche « continuer », dans les deux vues (une seule est affichée).
local function setText(text: string)
	textLabel.Text = text
	if world then
		bubbleText.Text = text
		sizeBubble(text)
	end
end

local function setGraphemes(count: number)
	textLabel.MaxVisibleGraphemes = count
	if world then
		bubbleText.MaxVisibleGraphemes = count
	end
end

local function setArrow(value: boolean)
	arrow.Visible = value
	if world then
		bubbleArrow.Visible = value
	end
end

------------------------------------------------------------------------------------
-- Personnages
------------------------------------------------------------------------------------

-- Couleur d'accent du personnage (cadre du portrait, bordure de la bulle).
local function speakerColor(speaker: Speaker): Color3
	if speaker == "LAGZ" then
		return Lagz.Color
	elseif speaker == "AIO" then
		return AIO_ACCENT
	end
	return Style.Color("BrandAnga")
end

-- Portrait, plaque de nom et couleur du cadre du personnage qui parle.
local function applySpeaker(speaker: Speaker)
	speaking = speaker
	for _, object in angaLook do
		object.Visible = speaker == "Anga"
	end
	for _, object in lagzLook do
		object.Visible = speaker == "LAGZ"
	end
	for _, object in aioLook do
		object.Visible = speaker == "AIO"
	end
	local accent = speakerColor(speaker)
	portraitStroke.Color = accent
	if world then
		bubbleStroke.Color = accent
		bubbleTagStroke.Color = accent
		if speaker == "LAGZ" then
			bubbleTag.BackgroundColor3 = Lagz.Dark
			bubbleTagLabel.Text = "LAGZ"
		elseif speaker == "AIO" then
			bubbleTag.BackgroundColor3 = AIO_CARD
			bubbleTagLabel.Text = "AIO · AngAInOne"
		else
			bubbleTag.BackgroundColor3 = accent
			bubbleTagLabel.Text = string.upper(Branding.MascotName)
		end
	end
end

-- Hauteur de la petite « voix » de chaque personnage.
local function blipPitch(speaker: Speaker): number
	if speaker == "LAGZ" then
		return 0.7 + math.random() * 0.25 -- grave et un peu « cassée »
	elseif speaker == "AIO" then
		return 1.7 + math.random() * 0.15 -- petit robot de l'app
	end
	return 1.25 + math.random() * 0.35
end

-- Écrit `text` lettre par lettre. Renvoie quand la phrase est entièrement affichée.
local function typeLine(text: string, token: number, speaker: Speaker)
	applySpeaker(speaker)
	showing = text
	setText(text)
	setArrow(false)
	typing = true
	skipTyping = false
	local total = utf8.len(text) or #text
	if Motion.IsReduced() then
		setGraphemes(-1)
	else
		setGraphemes(0)
		local portraitScale = Motion.ScaleOf(portrait)
		for count = 1, total do
			if token ~= lineToken then
				return
			end
			if skipTyping then
				break
			end
			setGraphemes(count)
			if count % 3 == 0 then
				local blip = Dialogue.OnBlip
				if blip then
					blip(blipPitch(speaking))
				end
				-- Le portrait (bulle du bas) ou la plaque de nom (bulle d'Anga) « parle ».
				local talker = if worldShown then Motion.ScaleOf(bubbleTag) else portraitScale
				talker.Scale = 1.05
				Motion.Tween(talker, { Scale = 1 }, 0.1)
			end
			task.wait(CHAR_DELAY)
		end
		setGraphemes(-1)
	end
	typing = false
	if token == lineToken then
		setArrow(true)
	end
end

local advance: () -> ()

-- Joue la prochaine réplique (file d'attente d'abord, puis la réplique persistante).
advance = function()
	lineToken += 1
	local token = lineToken
	local nextLine = table.remove(queue, 1)
	if nextLine then
		setVisible(true)
		task.spawn(function()
			typeLine(nextLine.Text, token, nextLine.Speaker)
			task.wait(nextLine.Duration)
			if token == lineToken then
				advance()
			end
		end)
	elseif persistent then
		local text = persistent
		setVisible(true)
		task.spawn(function()
			if showing ~= text then
				typeLine(text, token, "Anga")
			else
				setArrow(true)
			end
			-- Une réplique ponctuelle est arrivée pendant l'écriture : on l'enchaîne.
			if token == lineToken and #queue > 0 then
				task.wait(1.2)
				if token == lineToken then
					advance()
				end
			end
		end)
	else
		showing = nil
		setVisible(false)
	end
end

function Dialogue.Say(text: string, duration: number?, speaker: Speaker?)
	table.insert(queue, { Text = text, Duration = duration or 4, Speaker = speaker or "Anga" })
	-- Interrompt la réplique persistante (elle reviendra après), pas une réplique ponctuelle.
	if not typing and (showing == nil or showing == persistent) then
		advance()
	end
end

function Dialogue.IsBusy(): boolean
	return #queue > 0 or (showing ~= nil and showing ~= persistent)
end

function Dialogue.SetPersistent(text: string?)
	if persistent == text then
		return
	end
	local previous = persistent
	persistent = text
	-- On ne coupe pas une réplique ponctuelle en cours : elle enchaînera d'elle-même.
	if #queue == 0 and (showing == nil or showing == previous) then
		advance()
	end
end

function Dialogue.SetLift(pixels: number)
	lift = pixels
	if box and boxShown then
		box.Position = UDim2.new(0.5, 0, 1, -(96 + 14 + 12 + lift))
	end
end

-- (Companion) Ancre de la bulle au-dessus d'Anga ; nil = bulle du bas. Bascule en douceur,
-- même au milieu d'une réplique (le texte et la frappe continuent dans l'autre vue).
function Dialogue.SetWorldAnchor(part: BasePart?)
	if anchor == part then
		return
	end
	anchor = part
	local gui = world
	if gui and part then
		gui.Adornee = part
	end
	if box then
		applyViews()
	end
end

------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------

-- Bulle au-dessus d'Anga : verre Fluent compact, plaque de nom, petite queue vers Anga.
local function buildWorld(onActivated: () -> ())
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local gui: BillboardGui = New("BillboardGui", {
		Name = "AngaSpeech",
		Size = UDim2.fromOffset(WORLD_MAX, 90),
		SizeOffset = Vector2.new(0, 0.5), -- le bas de la bulle (la queue) touche l'ancre
		StudsOffsetWorldSpace = Vector3.new(0, 0.3, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = math.huge,
		ResetOnSpawn = false,
		Active = true,
		ClipsDescendants = false,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Adornee = anchor,
		Parent = playerGui,
	})
	-- Petite queue (carré tourné) qui pointe vers Anga, sous la bulle
	New("Frame", {
		Name = "Tail",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(14, 14),
		Rotation = 45,
		BackgroundColor3 = Style.Color("Surface"),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = gui,
	})
	bubble = New("TextButton", {
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(WORLD_MAX, 60),
		BackgroundColor3 = Style.Color("Surface"),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 2,
		Parent = gui,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, 14) }) :: Instance,
	})
	Material.Glass(bubble, false)
	bubbleStroke = New("UIStroke", {
		Color = Style.Color("BrandAnga"),
		Thickness = 2,
		Transparency = 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = bubble,
	})
	-- Plaque de nom (pas de portrait) posée sur le bord haut
	bubbleTag = New("Frame", {
		Name = "Tag",
		Position = UDim2.fromOffset(10, -10),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Style.Color("BrandAnga"),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = bubble,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		Create.Padding(1, 8),
	})
	bubbleTagStroke = New("UIStroke", {
		Color = Style.Color("BrandAnga"),
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = bubbleTag,
	})
	bubbleTagLabel = New("TextLabel", {
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = string.upper(Branding.MascotName),
		FontFace = Style.Fonts.Heavy,
		TextSize = 11,
		TextColor3 = Style.Color("TextPrimary"),
		ZIndex = 5,
		Parent = bubbleTag,
	})
	bubbleText = New("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(WORLD_PAD, WORLD_PAD + 2),
		Size = UDim2.new(1, -(WORLD_PAD * 2 + 10), 1, -(WORLD_PAD + 8)),
		BackgroundTransparency = 1,
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Style.Fonts.Bold,
		TextSize = WORLD_TEXT,
		TextColor3 = Style.Color("TextPrimary"),
		ZIndex = 3,
		Parent = bubble,
	})
	bubbleArrow = New("Frame", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -11, 1, -11),
		Size = UDim2.fromOffset(6, 6),
		Rotation = 45,
		BorderSizePixel = 0,
		BackgroundColor3 = Style.Color("TextPrimary"),
		Visible = false,
		ZIndex = 3,
		Parent = bubble,
	})
	bubble.Activated:Connect(onActivated)
	world = gui
end

function Dialogue.Mount(layer: Frame)
	box = New("TextButton", {
		Name = "Dialogue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(96 + 14 + 12)),
		-- Bulle compacte et translucide : on voit le jeu à travers, elle ne masque presque rien.
		Size = UDim2.fromOffset(470, 70),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Tag = { "Glass", "RoundPill" },
		Parent = layer,
	})
	Material.Glass(box, false)

	-- Petit portrait rond, dans la bulle
	portrait = New("Frame", {
		Name = "Portrait",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 9, 0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		BorderSizePixel = 0,
		ZIndex = 5,
		Tag = { "MetalDark", "RoundPill" },
		Parent = box,
	})
	portraitStroke = New("UIStroke", { Color = Style.Color("BrandAnga"), Thickness = 2, Parent = portrait })
	if Branding.AngaImageId ~= "" then
		-- Portrait importé (logo AngaTV) : remplit tout le cadre.
		local image = New("ImageLabel", {
			Size = UDim2.new(1, -8, 1, -8),
			Position = UDim2.fromOffset(4, 4),
			BackgroundTransparency = 1,
			Image = Branding.AngaImageId,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 6,
			Parent = portrait,
		}, {
			New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		})
		table.insert(angaLook, image)
	else
		local avatar = Widgets.Avatar(46, portrait)
		avatar.AnchorPoint = Vector2.new(0.5, 0.5)
		avatar.Position = UDim2.fromScale(0.5, 0.5)
		avatar.ZIndex = 6
		table.insert(angaLook, avatar)
	end
	-- Portrait de LAGZ (caché tant qu'Anga parle)
	local lagzFace = Lagz.Face(44, portrait)
	lagzFace.AnchorPoint = Vector2.new(0.5, 0.5)
	lagzFace.Position = UDim2.fromScale(0.5, 0.52)
	lagzFace.ZIndex = 6
	lagzFace.Visible = false
	for _, d in lagzFace:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 7
		end
	end
	table.insert(lagzLook, lagzFace)

	-- Portrait d'AIO (assistant de l'app) : logo « A » blanc sur violet
	local aioBadge: Frame = New("Frame", {
		Name = "AioBadge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = AIO_ACCENT,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 6,
		Parent = portrait,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, 11) }) :: Instance,
		New("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "A",
			FontFace = Style.Fonts.Heavy,
			TextSize = 26,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 7,
		}),
	})
	table.insert(aioLook, aioBadge)

	-- Plaque de nom
	local plate: Frame = New("Frame", {
		Name = "NamePlate",
		Position = UDim2.fromOffset(70, -11),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
		ZIndex = 5,
		Tag = { "FillBrand", "RoundPill" },
		Parent = box,
	}, {
		Create.Padding(2, 10) :: Instance,
		Create.List(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = string.upper(Branding.MascotName),
		LayoutOrder = 1,
		ZIndex = 6,
		Tag = "FontDisplay",
		TextSize = 12,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = plate,
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = Branding.ChannelName,
		LayoutOrder = 2,
		ZIndex = 6,
		Tag = "FontBold",
		TextSize = 11,
		TextColor3 = Style.Color("TextPrimary"),
		TextTransparency = 0.25,
		Parent = plate,
	})
	table.insert(angaLook, plate)

	-- Plaque de LAGZ (violet, couleur posée par le code : pas de tag de remplissage)
	local lagzPlate: Frame = New("Frame", {
		Name = "LagzPlate",
		Position = UDim2.fromOffset(70, -11),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Lagz.Dark,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Tag = "RoundPill",
		Parent = box,
	}, {
		Create.Padding(2, 10) :: Instance,
		Create.List(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		New("UIStroke", { Color = Lagz.Color, Thickness = 2 }),
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "LAGZ",
		LayoutOrder = 1,
		ZIndex = 6,
		Tag = "FontDisplay",
		TextSize = 12,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = lagzPlate,
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "virus",
		LayoutOrder = 2,
		ZIndex = 6,
		Tag = "FontBold",
		TextSize = 11,
		TextColor3 = Style.Color("TextPrimary"),
		TextTransparency = 0.25,
		Parent = lagzPlate,
	})
	table.insert(lagzLook, lagzPlate)

	-- Plaque d'AIO (gris Fluent de l'app, liseré violet)
	local aioPlate: Frame = New("Frame", {
		Name = "AioPlate",
		Position = UDim2.fromOffset(70, -11),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = AIO_CARD,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Tag = "RoundPill",
		Parent = box,
	}, {
		Create.Padding(2, 10) :: Instance,
		Create.List(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		New("UIStroke", { Color = AIO_ACCENT, Thickness = 2 }),
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "AIO",
		LayoutOrder = 1,
		ZIndex = 6,
		Tag = "FontDisplay",
		TextSize = 12,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = aioPlate,
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "AngAInOne",
		LayoutOrder = 2,
		ZIndex = 6,
		Tag = "FontBold",
		TextSize = 11,
		TextColor3 = AIO_ACCENT,
		Parent = aioPlate,
	})
	table.insert(aioLook, aioPlate)

	textLabel = New("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(72, 15),
		Size = UDim2.new(1, -100, 1, -22),
		BackgroundTransparency = 1,
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 5,
		Tag = "FontMedium",
		TextSize = 16,
		TextScaled = true, -- les longues répliques rétrécissent au lieu de déborder de la bulle
		TextColor3 = Style.Color("TextPrimary"),
		Parent = box,
	}, { New("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 11 }) :: Instance })

	-- Flèche "continuer" qui clignote
	arrow = New("Frame", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(7, 7),
		Rotation = 45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Tag = "FillBrand",
		Parent = box,
	})

	-- Clic / tap (bulle du bas ou bulle d'Anga) : termine la phrase, puis passe à la suivante.
	local function onActivated()
		if typing then
			skipTyping = true
		elseif showing ~= persistent or #queue > 0 then
			advance()
		end
	end
	box.Activated:Connect(onActivated)
	-- La bulle au-dessus d'Anga est un bonus : si elle échoue, la bulle du bas reste.
	xpcall(buildWorld, function(err: any)
		world = nil
		warn("[Dialogue] bulle au-dessus d'Anga indisponible :", err)
	end, onActivated)

	local blink = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if arrow.Visible then
			blink += dt
			local fade = if math.floor(blink * 2.5) % 2 == 0 then 0 else 0.7
			arrow.BackgroundTransparency = fade
			arrow.Position = UDim2.new(1, -20, 0.5, math.sin(blink * 6) * 2)
			if world then
				bubbleArrow.BackgroundTransparency = fade
				bubbleArrow.Position = UDim2.new(1, -11, 1, -11 + math.sin(blink * 6) * 1.5)
			end
		end
	end)
end

return Dialogue
