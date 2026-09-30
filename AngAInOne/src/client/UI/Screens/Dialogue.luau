--!strict
--[[
	Dialogue : Anga te parle, façon boîte de dialogue de jeu.
	- Portrait encadré qui déborde de la boîte + plaque de nom
	- Texte qui s'écrit lettre par lettre, avec une petite "voix" (bip) toutes les 3 lettres
	- Le portrait s'anime pendant qu'il parle
	- Clic / tap sur la boîte : termine la phrase, puis passe à la suivante
	- Flèche ▼ qui clignote quand la phrase est finie

	- Deux personnages : Anga (rouge AngaTV, par défaut) et LAGZ (violet glitché, voix grave)

	API :
		Dialogue.Say(texte, durée?, personnage?) -- réplique ponctuelle (file d'attente) ;
		                                         -- personnage : "Anga" (défaut) | "LAGZ"
		Dialogue.SetPersistent(texte?)    -- réplique de tutoriel qui reste affichée (nil = aucune)
		Dialogue.IsBusy()                 -- une réplique ponctuelle est affichée ou en attente
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

export type Speaker = "Anga" | "LAGZ"
type Line = { Text: string, Duration: number, Speaker: Speaker }

local CHAR_DELAY = 0.022
local box: TextButton
local textLabel: TextLabel
local portrait: Frame
local portraitStroke: UIStroke
local angaLook: { GuiObject } = {}
local lagzLook: { GuiObject } = {}
local speaking: Speaker = "Anga"
local arrow: Frame
local queue: { Line } = {}
local persistent: string? = nil
local showing: string? = nil
local typing = false
local skipTyping = false
local lineToken = 0
local visible = false

local function setVisible(value: boolean)
	if visible == value then
		return
	end
	visible = value
	local scale = Motion.ScaleOf(box)
	if value then
		box.Visible = true
		scale.Scale = 0.85
		box.Position = UDim2.new(0.5, 0, 1, -(96 + 14 + 4))
		Motion.Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
		Motion.Tween(box, { Position = UDim2.new(0.5, 0, 1, -(96 + 14 + 18)) }, 0.3)
	else
		Motion.Tween(scale, { Scale = 0.9 }, 0.18).Completed:Once(function()
			if not visible then
				box.Visible = false
			end
		end)
	end
end

-- Portrait, plaque de nom et couleur du cadre du personnage qui parle.
local function applySpeaker(speaker: Speaker)
	speaking = speaker
	local isLagz = speaker == "LAGZ"
	for _, object in angaLook do
		object.Visible = not isLagz
	end
	for _, object in lagzLook do
		object.Visible = isLagz
	end
	portraitStroke.Color = if isLagz then Lagz.Color else Style.Color("BrandAnga")
end

-- Écrit `text` lettre par lettre. Renvoie quand la phrase est entièrement affichée.
local function typeLine(text: string, token: number, speaker: Speaker)
	applySpeaker(speaker)
	showing = text
	textLabel.Text = text
	arrow.Visible = false
	typing = true
	skipTyping = false
	local total = utf8.len(text) or #text
	if Motion.IsReduced() then
		textLabel.MaxVisibleGraphemes = -1
	else
		textLabel.MaxVisibleGraphemes = 0
		local portraitScale = Motion.ScaleOf(portrait)
		for count = 1, total do
			if token ~= lineToken then
				return
			end
			if skipTyping then
				break
			end
			textLabel.MaxVisibleGraphemes = count
			if count % 3 == 0 then
				local blip = Dialogue.OnBlip
				if blip then
					-- LAGZ : voix plus grave et un peu « cassée ».
					blip(if speaking == "LAGZ" then 0.7 + math.random() * 0.25 else 1.25 + math.random() * 0.35)
				end
				portraitScale.Scale = 1.05
				Motion.Tween(portraitScale, { Scale = 1 }, 0.1)
			end
			task.wait(CHAR_DELAY)
		end
		textLabel.MaxVisibleGraphemes = -1
	end
	typing = false
	if token == lineToken then
		arrow.Visible = true
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
				arrow.Visible = true
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

function Dialogue.Mount(layer: Frame)
	box = New("TextButton", {
		Name = "Dialogue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(96 + 14 + 18)),
		Size = UDim2.fromOffset(640, 118),
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	}, {
		New("UIShadow", {
			BlurRadius = UDim.new(0, 22),
			Transparency = 0.35,
			Offset = UDim2.fromOffset(0, 8),
			Color = Style.Color("BgDeep"),
		}),
	})
	Material.Glass(box, true)
	Material.RgbEdge(box, 1.8, 0.2, 35)

	-- Portrait qui déborde en haut à gauche (style "speaker")
	portrait = New("Frame", {
		Name = "Portrait",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -14),
		Size = UDim2.fromOffset(112, 112),
		BorderSizePixel = 0,
		ZIndex = 5,
		Tag = { "MetalDark", "RoundL" },
		Parent = box,
	})
	portraitStroke = New("UIStroke", { Color = Style.Color("BrandAnga"), Thickness = 3, Parent = portrait })
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
			New("UICorner", { CornerRadius = UDim.new(0, Theme.Radius.M) }),
		})
		table.insert(angaLook, image)
	else
		local avatar = Widgets.Avatar(100, portrait)
		avatar.AnchorPoint = Vector2.new(0.5, 0.5)
		avatar.Position = UDim2.fromScale(0.5, 0.5)
		avatar.ZIndex = 6
		table.insert(angaLook, avatar)
	end
	-- Portrait de LAGZ (caché tant qu'Anga parle)
	local lagzFace = Lagz.Face(96, portrait)
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

	-- Plaque de nom
	local plate: Frame = New("Frame", {
		Name = "NamePlate",
		Position = UDim2.fromOffset(142, -16),
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
		ZIndex = 5,
		Tag = { "FillBrand", "RoundPill" },
		Parent = box,
	}, {
		Create.Padding(4, 16) :: Instance,
		Create.List(Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = string.upper(Branding.MascotName),
		LayoutOrder = 1,
		ZIndex = 6,
		Tag = "FontDisplay",
		TextSize = 16,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = plate,
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = Branding.ChannelName,
		LayoutOrder = 2,
		ZIndex = 6,
		Tag = "FontBold",
		TextSize = 13,
		TextColor3 = Style.Color("TextPrimary"),
		TextTransparency = 0.25,
		Parent = plate,
	})
	table.insert(angaLook, plate)

	-- Plaque de LAGZ (violet, couleur posée par le code : pas de tag de remplissage)
	local lagzPlate: Frame = New("Frame", {
		Name = "LagzPlate",
		Position = UDim2.fromOffset(142, -16),
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Lagz.Dark,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Tag = "RoundPill",
		Parent = box,
	}, {
		Create.Padding(4, 16) :: Instance,
		Create.List(Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		New("UIStroke", { Color = Lagz.Color, Thickness = 2 }),
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "LAGZ",
		LayoutOrder = 1,
		ZIndex = 6,
		Tag = "FontDisplay",
		TextSize = 16,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = lagzPlate,
	})
	New("TextLabel", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "virus",
		LayoutOrder = 2,
		ZIndex = 6,
		Tag = "FontBold",
		TextSize = 13,
		TextColor3 = Style.Color("TextPrimary"),
		TextTransparency = 0.25,
		Parent = lagzPlate,
	})
	table.insert(lagzLook, lagzPlate)

	textLabel = New("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(146, 26),
		Size = UDim2.new(1, -176, 1, -40),
		BackgroundTransparency = 1,
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 5,
		Tag = "FontMedium",
		TextSize = 19,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = box,
	})

	-- Flèche "continuer" qui clignote
	arrow = New("Frame", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -24, 1, -20),
		Size = UDim2.fromOffset(10, 10),
		Rotation = 45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Tag = "FillBrand",
		Parent = box,
	})

	box.Activated:Connect(function()
		if typing then
			skipTyping = true
		elseif showing ~= persistent or #queue > 0 then
			advance()
		end
	end)

	local blink = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if arrow.Visible then
			blink += dt
			arrow.BackgroundTransparency = if math.floor(blink * 2.5) % 2 == 0 then 0 else 0.7
			arrow.Position = UDim2.new(1, -24, 1, -20 + math.sin(blink * 6) * 2)
		end
	end)
end

return Dialogue
