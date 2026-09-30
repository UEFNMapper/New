--!strict
--[[
	Common : briques d'interface partagées par les mini-jeux antivirus.

	- Contrat d'un mini-jeu (Info / Illustrate / Run) et du HUD fourni par MinigamePanel
	- Palette dérivée des tokens du thème (virus violet-magenta, fichiers cyan…)
	- Virus : blob glitché aux yeux méchants, en Frames (aucune image à importer)
	- Fichier : gentil document souriant (à NE PAS toucher)
	- Effets : éclats de pixels, texte flottant, secousse, confettis, pulsation
	- Bin : range connexions, instances et tweens pour un nettoyage sans fuite
	- Terrain : conversion unités logiques (Core.FIELD_W x FIELD_H) <-> UDim2 / écran

	Tout ce qui est dessiné dans le terrain utilise des tailles en échelle : le terrain
	garde toujours le même rapport largeur/hauteur, donc un carré reste un carré.
]]

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Audio = require(script.Parent.Parent.Parent.Controllers.Audio)
local Core = require(script.Parent.Core)

local New = Create.New

local Common = {}

------------------------------------------------------------------------------------
-- Contrat des mini-jeux
------------------------------------------------------------------------------------

export type Device = "Touch" | "Keyboard" | "Gamepad"

-- HUD affiché par MinigamePanel au-dessus du terrain (chrono, progression, vies).
export type Hud = {
	SetTimer: (secondsLeft: number?) -> (), -- nil = chrono caché
	SetProgress: (value: number, target: number) -> (),
	SetLives: (lives: number?, max: number?) -> (), -- nil = pas de vies
}

export type Finish = (success: boolean, score: number) -> ()

-- Textes de la carte d'intro et de résultat.
export type Info = {
	Title: string, -- "SCAN ANTIVIRUS"
	Rule: string, -- une phrase courte
	Target: string, -- "Élimine 15 virus !"
	Controls: string, -- selon l'appareil
	Tip: string, -- conseil affiché après un échec
	Goal: number, -- objectif chiffré (résultat "12 / 15")
	Unit: string, -- "virus", "paires", "murs"
	Icon: string, -- icône de progression : "Virus" ou un type de Components/Icon
	Accent: string, -- token de couleur du jeu
}

export type Game = {
	Info: (difficulty: number, device: Device) -> Info,
	Illustrate: (parent: Frame) -> (),
	Run: (container: Frame, difficulty: number, finish: Finish, hud: Hud?) -> () -> (),
}

Common.NullHud = table.freeze({
	SetTimer = function(_seconds: number?) end,
	SetProgress = function(_value: number, _target: number) end,
	SetLives = function(_lives: number?, _max: number?) end,
}) :: Hud

------------------------------------------------------------------------------------
-- Palette (uniquement dérivée des tokens du thème)
------------------------------------------------------------------------------------

local function token(name: string): Color3
	return Style.Color(name)
end

Common.Colors = table.freeze({
	Virus = token("AccentViolet"),
	VirusHot = token("AccentViolet"):Lerp(token("BrandAnga"), 0.55), -- magenta
	VirusDark = token("AccentViolet"):Lerp(token("BgDeep"), 0.6),
	Eye = token("TextPrimary"),
	Ink = token("BgDeep"),
	GlitchA = token("AccentCyan"),
	GlitchB = token("BrandAnga"),
	File = token("AccentCyan"),
	FileLight = token("AccentCyan"):Lerp(token("TextPrimary"), 0.7),
	Cheek = token("BrandAnga"),
	Good = token("Success"),
	Bad = token("Danger"),
	Gold = token("CurrencyBits"),
	Amber = token("AccentAmber"),
	Cyan = token("AccentCyan"),
	White = token("TextPrimary"),
	Muted = token("TextMuted"),
	Dim = token("TextDim"),
	Screen = token("SurfaceSunken"),
	Raised = token("SurfaceRaised"),
	Metal = token("MetalLight"),
})

local C = Common.Colors

------------------------------------------------------------------------------------
-- Terrain logique
------------------------------------------------------------------------------------

-- Position (centre) dans le terrain logique -> UDim2 relatif au terrain.
function Common.At(x: number, y: number): UDim2
	return UDim2.fromScale(x / Core.FIELD_W, y / Core.FIELD_H)
end

-- Taille en unités logiques -> UDim2 relatif au terrain.
function Common.Box(w: number, h: number): UDim2
	return UDim2.fromScale(w / Core.FIELD_W, h / Core.FIELD_H)
end

-- Position écran (InputObject.Position) -> unités du terrain affiché par `arena`.
function Common.ToField(arena: GuiObject, screen: Vector3 | Vector2): Vector2
	local size = arena.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return Vector2.new(Core.FIELD_W / 2, Core.FIELD_H / 2)
	end
	local origin = arena.AbsolutePosition
	return Vector2.new((screen.X - origin.X) / size.X * Core.FIELD_W, (screen.Y - origin.Y) / size.Y * Core.FIELD_H)
end

-- Le point écran est-il dans l'objet ?
function Common.Inside(object: GuiObject, screen: Vector3 | Vector2): boolean
	local origin, size = object.AbsolutePosition, object.AbsoluteSize
	return screen.X >= origin.X
		and screen.X <= origin.X + size.X
		and screen.Y >= origin.Y
		and screen.Y <= origin.Y + size.Y
end

-- Graine aléatoire pour une nouvelle partie.
function Common.Seed(): number
	return Random.new():NextInteger(1, 2147483645)
end

------------------------------------------------------------------------------------
-- Entrées / appareil
------------------------------------------------------------------------------------

function Common.Device(): Device
	local last = UserInputService:GetLastInputType()
	if string.find(last.Name, "^Gamepad") then
		return "Gamepad"
	elseif last == Enum.UserInputType.Touch then
		return "Touch"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

-- Met le focus manette sur un bouton (seulement si on joue à la manette).
function Common.Focus(object: GuiObject?)
	if object and Common.Device() == "Gamepad" then
		GuiService.SelectedObject = object
	end
end

-- Retire le focus manette s'il est dans `root` (ou partout si root est nil).
function Common.Unfocus(root: Instance?)
	local selected = GuiService.SelectedObject
	if selected and (root == nil or selected:IsDescendantOf(root)) then
		GuiService.SelectedObject = nil
	end
end

------------------------------------------------------------------------------------
-- Son (jamais bloquant)
------------------------------------------------------------------------------------

function Common.Sound(name: string, pitch: number?)
	pcall(Audio.Play, name, pitch)
end

------------------------------------------------------------------------------------
-- Bin : nettoyage
------------------------------------------------------------------------------------

export type Bin = {
	Add: (self: Bin, item: any) -> (),
	Clean: (self: Bin) -> (),
}

function Common.Bin(): Bin
	local items: { any } = {}
	local bin = {}
	function bin.Add(_self: Bin, item: any)
		table.insert(items, item)
	end
	function bin.Clean(_self: Bin)
		-- Ordre inverse : les connexions (ajoutées après les instances) partent d'abord.
		for i = #items, 1, -1 do
			local item = items[i]
			items[i] = nil
			local kind = typeof(item)
			if kind == "RBXScriptConnection" then
				item:Disconnect()
			elseif kind == "Instance" then
				if item:IsA("Tween") then
					item:Cancel()
				end
				item:Destroy()
			elseif kind == "function" then
				xpcall(item, function(err: any)
					warn("[Minigames] nettoyage :", err)
				end)
			end
		end
	end
	return (bin :: any) :: Bin
end

-- Boucle de jeu (RenderStepped). `onError` est appelé une seule fois si l'étape plante :
-- la boucle s'arrête proprement au lieu de spammer la sortie.
function Common.Loop(bin: Bin, step: (dt: number) -> (), onError: (() -> ())?)
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function(dt: number)
		local ok = xpcall(step, function(err: any)
			warn("[Minigames] erreur dans la boucle de jeu :", err, debug.traceback())
		end, math.min(dt, Core.MAX_STEP))
		if not ok then
			if connection then
				connection:Disconnect()
			end
			if onError then
				onError()
			end
		end
	end)
	bin:Add(connection)
end

------------------------------------------------------------------------------------
-- Formes de base
------------------------------------------------------------------------------------

local function corner(radius: UDim?): UICorner
	return New("UICorner", { CornerRadius = radius or UDim.new(1, 0) })
end
Common.Corner = corner

-- Rectangle / ovale en coordonnées d'échelle dans `parent`.
function Common.Shape(
	parent: Instance,
	position: UDim2,
	size: UDim2,
	color: Color3,
	radius: UDim?,
	props: { [string]: any }?
): Frame
	local frame: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	})
	if props then
		for key, value in props do
			(frame :: any)[key] = value
		end
	end
	if radius then
		corner(radius).Parent = frame
	end
	frame.Parent = parent
	return frame
end

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x, y)
end

-- Tween en boucle aller-retour (désactivé en animations réduites), annulé à la destruction.
function Common.Pulse(instance: Instance, props: { [string]: any }, duration: number)
	if Motion.IsReduced() then
		return
	end
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	instance.Destroying:Once(function()
		tween:Cancel()
	end)
end

------------------------------------------------------------------------------------
-- Virus : blob violet-magenta glitché aux yeux méchants
------------------------------------------------------------------------------------

export type SpriteProps = {
	Size: UDim2,
	Position: UDim2?,
	Parent: Instance?,
	ZIndex: number?,
	Name: string?,
	Tough: boolean?, -- casque doré : il faut deux tirs
	Calm: boolean?, -- sans respiration (icônes du HUD)
}

function Common.Virus(props: SpriteProps): Frame
	local root: Frame = New("Frame", {
		Name = props.Name or "Virus",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position or at(0.5, 0.5),
		Size = props.Size,
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 1,
	})
	-- Piquants tout autour (carrés arrondis inclinés).
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		Common.Shape(
			root,
			at(0.5 + math.cos(angle) * 0.4, 0.5 + math.sin(angle) * 0.4),
			at(0.2, 0.2),
			C.VirusHot,
			UDim.new(0.3, 0),
			{ Name = "Spike", Rotation = math.deg(angle) + 45, ZIndex = 1 }
		)
	end
	local body = Common.Shape(root, at(0.5, 0.5), at(0.8, 0.8), C.White, UDim.new(1, 0), { Name = "Body", ZIndex = 2 })
	New("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(C.Virus, C.VirusHot),
		Parent = body,
	})
	New("UIStroke", { Color = C.VirusDark, Thickness = 2, Parent = body })
	-- Reflet
	Common.Shape(body, at(0.3, 0.2), at(0.26, 0.13), C.White, UDim.new(1, 0), {
		Name = "Shine",
		Rotation = -25,
		BackgroundTransparency = 0.55,
	})
	-- Yeux méchants : pupilles qui louchent vers le centre + sourcils froncés.
	for _, side in { -1, 1 } do
		local eye = Common.Shape(body, at(0.5 + side * 0.18, 0.46), at(0.28, 0.28), C.Eye, UDim.new(1, 0), {
			Name = "Eye",
		})
		Common.Shape(eye, at(0.5 - side * 0.14, 0.6), at(0.52, 0.52), C.Ink, UDim.new(1, 0), { Name = "Pupil" })
		Common.Shape(body, at(0.5 + side * 0.18, 0.27), at(0.32, 0.085), C.Ink, UDim.new(1, 0), {
			Name = "Brow",
			Rotation = -side * 22,
		})
	end
	local mouth = Common.Shape(body, at(0.5, 0.73), at(0.4, 0.12), C.Ink, UDim.new(1, 0), { Name = "Mouth" })
	for _, x in { 0.3, 0.7 } do
		New("Frame", {
			Name = "Tooth",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = at(x, 0),
			Size = at(0.16, 0.55),
			BackgroundColor3 = C.Eye,
			BorderSizePixel = 0,
			Parent = mouth,
		})
	end
	-- Barres de glitch (cachées, voir Common.Glitch).
	for i, color in { C.GlitchA, C.GlitchB } do
		New("Frame", {
			Name = "Glitch",
			Position = at(0.05, 0.25 + i * 0.2),
			Size = at(0.9, 0.07),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 4,
			Parent = root,
		})
	end
	if props.Tough then
		local armor = Common.Shape(root, at(0.5, 0.5), at(0.98, 0.98), C.Gold, UDim.new(1, 0), {
			Name = "Armor",
			BackgroundTransparency = 1,
			ZIndex = 3,
		})
		New("UIStroke", { Color = C.Gold, Thickness = 4, Parent = armor })
		Common.Shape(root, at(0.5, 0.12), at(0.42, 0.14), C.Gold, UDim.new(0.5, 0), {
			Name = "Helmet",
			ZIndex = 3,
		})
	end
	if not props.Calm then
		local breath: UIScale = New("UIScale", { Name = "Breath", Parent = body })
		Common.Pulse(breath, { Scale = 1.07 }, 0.45 + math.random() * 0.25)
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return root
end

-- Petit glitch visuel (barres colorées décalées pendant ~0,1 s).
function Common.Glitch(virus: Instance)
	if Motion.IsReduced() then
		return
	end
	for _, child in virus:GetChildren() do
		if child.Name == "Glitch" and child:IsA("Frame") then
			child.Visible = true
			child.Position = UDim2.fromScale(math.random() * 0.2 - 0.1, 0.15 + math.random() * 0.65)
		end
	end
	task.delay(0.08 + math.random() * 0.06, function()
		for _, child in virus:GetChildren() do
			if child.Name == "Glitch" and child:IsA("Frame") then
				child.Visible = false
			end
		end
	end)
end

-- Retire le casque d'un virus touché une première fois.
function Common.CrackArmor(virus: Instance)
	for _, name in { "Armor", "Helmet" } do
		local part = virus:FindFirstChild(name)
		if part then
			part:Destroy()
		end
	end
end

------------------------------------------------------------------------------------
-- Fichier : gentil document souriant (à protéger)
------------------------------------------------------------------------------------

function Common.File(props: SpriteProps): Frame
	local root: Frame = New("Frame", {
		Name = props.Name or "File",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position or at(0.5, 0.5),
		Size = props.Size,
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 1,
	})
	local paper = Common.Shape(root, at(0.5, 0.52), at(0.66, 0.84), C.FileLight, UDim.new(0.14, 0), {
		Name = "Paper",
	})
	New("UIStroke", { Color = C.File, Thickness = 3, Parent = paper })
	-- Coin corné
	New("Frame", {
		Name = "Fold",
		AnchorPoint = Vector2.new(1, 0),
		Position = at(1, 0),
		Size = at(0.3, 0.22),
		BackgroundColor3 = C.File,
		BorderSizePixel = 0,
		Parent = paper,
	}, { corner(UDim.new(0.3, 0)) })
	-- Lignes de texte
	for i = 0, 1 do
		Common.Shape(paper, at(0.42, 0.2 + i * 0.12), at(0.5, 0.05), C.File, UDim.new(1, 0), {
			Name = "Line",
			BackgroundTransparency = 0.35,
		})
	end
	-- Visage content
	for _, side in { -1, 1 } do
		Common.Shape(paper, at(0.5 + side * 0.18, 0.54), at(0.14, 0.11), C.Ink, UDim.new(1, 0), { Name = "Eye" })
		Common.Shape(paper, at(0.5 + side * 0.3, 0.66), at(0.16, 0.08), C.Cheek, UDim.new(1, 0), {
			Name = "Cheek",
			BackgroundTransparency = 0.45,
		})
	end
	local smile: Frame = New("Frame", {
		Name = "Smile",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = at(0.5, 0.64),
		Size = at(0.36, 0.14),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = paper,
	})
	local arc = Common.Shape(smile, at(0.5, 0), at(1, 1.6), C.Ink, UDim.new(1, 0), {
		Name = "Arc",
		BackgroundTransparency = 1,
	})
	New("UIStroke", { Color = C.Ink, Thickness = 3, Parent = arc })
	if props.Parent then
		root.Parent = props.Parent
	end
	return root
end

-- Fichier infecté : il vire au violet et ouvre une bouche en "O" (choqué).
-- (on ne tourne pas le sourire : ClipsDescendants est ignoré sur un objet tourné)
function Common.InfectFile(file: Instance)
	local paper = file:FindFirstChild("Paper")
	if paper and paper:IsA("Frame") then
		paper.BackgroundColor3 = C.Virus:Lerp(C.White, 0.3)
		local stroke = paper:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = C.VirusHot
		end
		local smile = paper:FindFirstChild("Smile")
		if smile and smile:IsA("GuiObject") then
			smile.Visible = false
		end
		if not paper:FindFirstChild("Shocked") then
			Common.Shape(paper, at(0.5, 0.74), at(0.18, 0.13), C.Ink, UDim.new(1, 0), { Name = "Shocked" })
		end
	end
end

------------------------------------------------------------------------------------
-- Effets
------------------------------------------------------------------------------------

-- Éclats de pixels qui jaillissent d'un point.
function Common.Burst(parent: Instance, position: UDim2, color: Color3, count: number?, spread: number?)
	local n = count or 10
	if Motion.IsReduced() then
		n = math.max(3, math.floor(n / 3))
	end
	local reach = spread or 70
	for i = 1, n do
		local angle = (i / n) * math.pi * 2 + math.random() * 0.6
		local distance = reach * (0.6 + math.random() * 0.6)
		local size = math.random(7, 14)
		local bit: Frame = New("Frame", {
			Name = "Pixel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 30,
			Parent = parent,
		})
		Motion.Tween(bit, {
			Position = position + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance),
			Size = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 1,
			Rotation = math.random(-180, 180),
		}, 0.4 + math.random() * 0.2, Enum.EasingStyle.Quad)
		task.delay(0.7, function()
			bit:Destroy()
		end)
	end
end

-- Texte qui s'envole ("+1", "Oups !").
function Common.Popup(parent: Instance, position: UDim2, text: string, color: Color3, size: number?)
	local label: TextLabel = New("TextLabel", {
		Name = "Popup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(260, 44),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		TextSize = size or 30,
		Tag = "FontHeavy",
		ZIndex = 35,
		Parent = parent,
	})
	local stroke: UIStroke = New("UIStroke", { Color = C.Ink, Thickness = 2.5, Parent = label })
	Motion.Pop(label, 0.35)
	Motion.Tween(
		label,
		{ Position = position - UDim2.fromOffset(0, 54), TextTransparency = 1 },
		0.85,
		Enum.EasingStyle.Quad
	)
	Motion.Tween(stroke, { Transparency = 1 }, 0.85, Enum.EasingStyle.Quad)
	task.delay(0.9, function()
		label:Destroy()
	end)
end

-- Secousse d'un objet (écran touché). Plusieurs secousses se fusionnent.
local shaking: { [GuiObject]: { Base: UDim2, Until: number, Strength: number } } = {}
function Common.Shake(target: GuiObject, strength: number, duration: number?)
	if Motion.IsReduced() then
		return
	end
	local length = duration or 0.25
	local entry = shaking[target]
	if entry then
		entry.Until = math.max(entry.Until, os.clock() + length)
		entry.Strength = math.max(entry.Strength, strength)
		return
	end
	local newEntry = { Base = target.Position, Until = os.clock() + length, Strength = strength }
	shaking[target] = newEntry
	task.spawn(function()
		while target.Parent and os.clock() < newEntry.Until do
			local k = newEntry.Strength * math.clamp((newEntry.Until - os.clock()) / length, 0, 1)
			target.Position = newEntry.Base + UDim2.fromOffset((math.random() * 2 - 1) * k, (math.random() * 2 - 1) * k)
			task.wait(1 / 60)
		end
		if target.Parent then
			target.Position = newEntry.Base
		end
		shaking[target] = nil
	end)
end

-- Pluie de confettis (carte de victoire).
function Common.Confetti(parent: GuiObject, count: number?)
	local palette = { C.Virus, C.Cyan, C.Gold, C.GlitchB, C.Good }
	local reduced = Motion.IsReduced()
	local n = if reduced then 10 else (count or 44)
	for i = 1, n do
		local startX = 0.5 + (math.random() - 0.5) * 0.25
		local piece: Frame = New("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(startX, 0.45),
			Size = UDim2.fromOffset(math.random(8, 13), math.random(12, 20)),
			BackgroundColor3 = palette[(i - 1) % #palette + 1],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			ZIndex = 50,
			Parent = parent,
		})
		if reduced then
			-- Animations réduites : confettis immobiles qui s'effacent.
			piece.Position = UDim2.fromScale(math.random(), math.random() * 0.8)
			task.delay(1.2, function()
				piece:Destroy()
			end)
		else
			local peak = UDim2.fromScale(startX + (math.random() - 0.5) * 1.1, 0.3 - math.random() * 0.35)
			Motion.Tween(
				piece,
				{ Position = peak, Rotation = piece.Rotation + math.random(-200, 200) },
				0.5,
				Enum.EasingStyle.Quad
			)
			task.delay(0.5, function()
				if piece.Parent then
					Motion.Tween(piece, {
						Position = UDim2.fromScale(peak.X.Scale + (math.random() - 0.5) * 0.15, 1.1),
						Rotation = piece.Rotation + math.random(-400, 400),
						BackgroundTransparency = 0.4,
					}, 1.4 + math.random() * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
			task.delay(2.8, function()
				piece:Destroy()
			end)
		end
	end
end

-- Bulle d'indice en bas du terrain ("Tape pour voler !").
function Common.Hint(parent: Instance, text: string, y: number?): TextLabel
	local label: TextLabel = New("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, y or 0.88),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.25,
		Text = text,
		TextColor3 = C.White,
		TextSize = 24,
		Tag = "FontHeavy",
		ZIndex = 40,
		Parent = parent,
	}, {
		corner(UDim.new(1, 0)),
		New("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }),
	})
	Motion.Pop(label, 0.2)
	return label
end

-- Scène d'un jeu : remplit le conteneur (c'est elle qu'on secoue). La navigation manette
-- reste enfermée dedans (sinon la croix pourrait sélectionner l'interface cachée dessous).
function Common.Stage(container: Frame): Frame
	return New("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
		Parent = container,
	})
end

-- Bouton invisible qui couvre la scène et capte le doigt / la souris.
function Common.Catcher(parent: Instance): TextButton
	return New("TextButton", {
		Name = "Catcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		ZIndex = 1,
		Parent = parent,
	})
end

-- Est-ce un appui "principal" (clic gauche ou doigt) ?
function Common.IsPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

return Common
