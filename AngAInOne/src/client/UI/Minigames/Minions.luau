--!strict
--[[
	Minions : les sbires de LAGZ (et LAGZ lui-même), dessinés en Frames, mignons-méchants.
	Aucune image à importer ; tailles en échelle : le personnage remplit un carré.

		Minions.Build(name, size, mood)  -- mood : "Evil" (il nargue) ou "Defeated" (K.O.)
		Minions.Taunt(name)              -- "Sparky te bloque le terminal !"
		Minions.Defeat(name)             -- "Sparky a grillé ses fusibles !"
		Minions.Gloat(name)              -- après un échec

	Noms : ceux de Tower.Worlds[n].Minion (Sparky, Pop-Up, Corrupto, Dusty, Minor, Freezy,
	LAGZ). Un nom inconnu donne LAGZ.
]]

local TweenService = game:GetService("TweenService")

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

local New = Create.New
local C = Common.Colors
local Shape = Common.Shape

local Minions = {}

export type Mood = "Evil" | "Defeated"

type Lines = { Taunt: string, Defeat: string, Gloat: string }

local LINES: { [string]: Lines } = {
	Sparky = {
		Taunt = "Sparky te bloque le terminal !",
		Defeat = "Sparky a grillé ses fusibles !",
		Gloat = "Bzzt ! Sparky rigole… Réessaie !",
	},
	["Pop-Up"] = {
		Taunt = "Pop-Up inonde l'écran de pubs !",
		Defeat = "Pop-Up est fermé pour de bon !",
		Gloat = "Pop-Up rouvre ses fenêtres… Réessaie !",
	},
	Corrupto = {
		Taunt = "Corrupto a mélangé tes fichiers !",
		Defeat = "Corrupto est tout défragmenté !",
		Gloat = "Corrupto ricane en pixels… Réessaie !",
	},
	Dusty = {
		Taunt = "Dusty bouche le terminal !",
		Defeat = "Dusty est aspiré !",
		Gloat = "Dusty fait des moutons… Réessaie !",
	},
	Minor = {
		Taunt = "Minor pirate le terminal !",
		Defeat = "Minor a cassé sa pioche !",
		Gloat = "Minor creuse encore… Réessaie !",
	},
	Freezy = {
		Taunt = "Freezy a gelé le terminal !",
		Defeat = "Freezy a fondu !",
		Gloat = "Freezy te fige sur place… Réessaie !",
	},
	LAGZ = {
		Taunt = "LAGZ te bloque le terminal !",
		Defeat = "LAGZ EST DÉTRUIT !",
		Gloat = "LAGZ ricane… Réessaie, tu y es presque !",
	},
}

local function lines(name: string): Lines
	return LINES[name] or LINES.LAGZ
end

function Minions.Has(name: string): boolean
	return LINES[name] ~= nil
end

function Minions.Taunt(name: string): string
	return lines(name).Taunt
end

function Minions.Defeat(name: string): string
	return lines(name).Defeat
end

function Minions.Gloat(name: string): string
	return lines(name).Gloat
end

------------------------------------------------------------------------------------
-- Morceaux communs
------------------------------------------------------------------------------------

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x, y)
end

-- Rotation continue (roue de chargement), annulée à la destruction.
local function spin(instance: GuiObject, seconds: number)
	if Motion.IsReduced() then
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	local tween = TweenService:Create(instance, info, { Rotation = instance.Rotation + 360 })
	tween:Play()
	instance.Destroying:Once(function()
		tween:Cancel()
	end)
end

-- Yeux + sourcils + bouche dans `parent`. `pixel` : yeux carrés (LAGZ, robots).
local function face(parent: Instance, mood: Mood, y: number, spread: number, eye: number, pixel: boolean?)
	local round = if pixel then UDim.new(0.15, 0) else UDim.new(1, 0)
	for _, side in { -1, 1 } do
		local x = 0.5 + side * spread
		if mood == "Defeated" then
			-- Yeux en croix (K.O.)
			for _, angle in { 45, -45 } do
				Shape(parent, at(x, y), at(eye * 0.95, eye * 0.2), C.Ink, UDim.new(1, 0), {
					Name = "KoEye",
					Rotation = angle,
					ZIndex = 4,
				})
			end
		else
			local white = Shape(parent, at(x, y), at(eye, eye), C.Eye, round, { Name = "Eye", ZIndex = 4 })
			Shape(white, at(0.5 - side * 0.14, 0.58), at(0.52, 0.52), C.Ink, round, { Name = "Pupil", ZIndex = 5 })
			Shape(white, at(0.34 - side * 0.1, 0.34), at(0.2, 0.2), C.White, round, { Name = "Glint", ZIndex = 6 })
			Shape(parent, at(x, y - eye * 0.72), at(eye * 1.15, eye * 0.26), C.Ink, UDim.new(1, 0), {
				Name = "Brow",
				Rotation = -side * 20,
				ZIndex = 5,
			})
		end
	end
	local mouthY = y + eye * 0.95
	if mood == "Defeated" then
		-- Petite bouche en "o" qui tire la langue
		Shape(parent, at(0.5, mouthY), at(eye * 0.5, eye * 0.42), C.Ink, UDim.new(1, 0), { Name = "Mouth", ZIndex = 4 })
		Shape(parent, at(0.56, mouthY + eye * 0.24), at(eye * 0.3, eye * 0.28), C.Cheek, UDim.new(1, 0), {
			Name = "Tongue",
			ZIndex = 5,
		})
	else
		-- Grand sourire narquois avec deux crocs
		local mouth = Shape(parent, at(0.5, mouthY), at(eye * 1.7, eye * 0.46), C.Ink, UDim.new(1, 0), {
			Name = "Mouth",
			ZIndex = 4,
		})
		for _, x in { 0.3, 0.7 } do
			New("Frame", {
				Name = "Fang",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = at(x, 0),
				Size = at(0.14, 0.5),
				BackgroundColor3 = C.Eye,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = mouth,
			})
		end
	end
end

-- Étoiles qui tournent au-dessus de la tête (K.O.).
local function dizzy(root: Frame)
	local ring: Frame = New("Frame", {
		Name = "Dizzy",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(0.5, 0.02),
		Size = at(0.7, 0.22),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = root,
	})
	for i, x in { 0.1, 0.5, 0.9 } do
		Shape(ring, at(x, if i == 2 then 0.2 else 0.7), at(0.16, 0.5), C.Gold, UDim.new(0.2, 0), {
			Name = "Star",
			Rotation = 45,
			ZIndex = 8,
		})
	end
	Common.Pulse(ring, { Rotation = 12 }, 0.5)
end

------------------------------------------------------------------------------------
-- Les personnages
------------------------------------------------------------------------------------

local function sparky(root: Frame, mood: Mood)
	-- Étincelle : éclairs tout autour d'un cœur jaune.
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		Shape(
			root,
			at(0.5 + math.cos(angle) * 0.36, 0.52 + math.sin(angle) * 0.36),
			at(0.12, 0.3),
			if i % 2 == 0 then C.Gold else C.Amber,
			UDim.new(0.4, 0),
			{ Name = "Bolt", Rotation = math.deg(angle) + 90 + (if i % 2 == 0 then 18 else -18), ZIndex = 1 }
		)
	end
	local body = Shape(root, at(0.5, 0.52), at(0.66, 0.66), C.White, UDim.new(1, 0), { Name = "Body", ZIndex = 2 })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Gold, C.Amber), Parent = body })
	New("UIStroke", { Color = C.Amber:Lerp(C.Ink, 0.4), Thickness = 2, Parent = body })
	face(body, mood, 0.42, 0.19, 0.26)
end

local function popUp(root: Frame, mood: Mood)
	-- Fenêtre de pub avec des yeux et une croix ✕.
	local window = Shape(root, at(0.5, 0.54), at(0.86, 0.72), C.FileLight, UDim.new(0.1, 0), {
		Name = "Body",
		ZIndex = 2,
	})
	New("UIStroke", { Color = C.Ink, Thickness = 2, Transparency = 0.3, Parent = window })
	local bar: Frame = New("Frame", {
		Name = "TitleBar",
		Size = at(1, 0.22),
		BackgroundColor3 = C.GlitchB,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = window,
	}, { Common.Corner(UDim.new(0.35, 0)) })
	local close = Shape(bar, at(0.88, 0.5), at(0.14, 0.72), C.White, UDim.new(1, 0), { Name = "Close", ZIndex = 4 })
	New("UIAspectRatioConstraint", { AspectRatio = 1, Parent = close })
	for _, angle in { 45, -45 } do
		Shape(close, at(0.5, 0.5), at(0.7, 0.16), C.GlitchB, UDim.new(1, 0), { Rotation = angle, ZIndex = 5 })
	end
	for i = 0, 1 do
		Shape(bar, at(0.1 + i * 0.1, 0.5), at(0.06, 0.4), C.White, UDim.new(1, 0), {
			BackgroundTransparency = 0.3,
			ZIndex = 4,
		})
	end
	face(window, mood, 0.5, 0.2, 0.24)
	-- Petit "!!!" de pub
	New("TextLabel", {
		Name = "Shout",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(0.86, 0.86),
		Size = at(0.22, 0.2),
		BackgroundTransparency = 1,
		Text = "!!!",
		TextScaled = true,
		TextColor3 = C.GlitchB,
		Tag = "FontHeavy",
		ZIndex = 5,
		Parent = window,
	})
end

local function corrupto(root: Frame, mood: Mood)
	-- Cube "texture manquante" rose / noir.
	local cube = Shape(root, at(0.5, 0.54), at(0.78, 0.78), C.Ink, UDim.new(0.12, 0), {
		Name = "Body",
		ClipsDescendants = true,
		ZIndex = 2,
	})
	for row = 0, 3 do
		for col = 0, 3 do
			if (row + col) % 2 == 0 then
				New("Frame", {
					Name = "Pixel",
					Position = at(col / 4, row / 4),
					Size = at(0.25, 0.25),
					BackgroundColor3 = C.VirusHot,
					BorderSizePixel = 0,
					ZIndex = 2,
					Parent = cube,
				})
			end
		end
	end
	New("UIStroke", { Color = C.VirusHot, Thickness = 2, Parent = cube })
	-- Pixel qui dépasse (cube abîmé)
	Shape(root, at(0.86, 0.22), at(0.12, 0.12), C.VirusHot, nil, { Name = "Chip", ZIndex = 3 })
	Shape(root, at(0.14, 0.9), at(0.09, 0.09), C.Cyan, nil, { Name = "Chip", ZIndex = 3 })
	face(cube, mood, 0.42, 0.2, 0.26, true)
end

local function dusty(root: Frame, mood: Mood)
	-- Boule de poussière grise et duveteuse.
	for i = 0, 9 do
		local angle = i / 10 * math.pi * 2
		Shape(
			root,
			at(0.5 + math.cos(angle) * 0.3, 0.54 + math.sin(angle) * 0.3),
			at(0.26, 0.26),
			C.Muted,
			UDim.new(1, 0),
			{ Name = "Fluff", ZIndex = 1 }
		)
	end
	local body = Shape(root, at(0.5, 0.54), at(0.7, 0.7), C.Muted, UDim.new(1, 0), { Name = "Body", ZIndex = 2 })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Muted:Lerp(C.White, 0.25), C.Dim), Parent = body })
	-- Moutons de poussière
	for _, spot in { { 0.25, 0.25 }, { 0.78, 0.3 }, { 0.3, 0.82 } } do
		Shape(body, at(spot[1], spot[2]), at(0.1, 0.1), C.Dim, UDim.new(1, 0), { ZIndex = 3 })
	end
	face(body, mood, 0.45, 0.19, 0.25)
end

local function minor(root: Frame, mood: Mood)
	-- Mini-robot mineur avec casque à lampe et pioche.
	local stick = Shape(root, at(0.84, 0.5), at(0.07, 0.62), Style.Color("Copper"), UDim.new(1, 0), {
		Name = "Pick",
		Rotation = 25,
		ZIndex = 1,
	})
	Shape(stick, at(0.5, 0.04), at(5, 0.12), C.Metal, UDim.new(1, 0), { Name = "PickHead", Rotation = -12, ZIndex = 1 })
	local head = Shape(root, at(0.46, 0.56), at(0.7, 0.62), C.Metal, UDim.new(0.18, 0), { Name = "Body", ZIndex = 2 })
	New("UIStroke", { Color = C.Ink, Thickness = 2, Transparency = 0.3, Parent = head })
	local helmet =
		Shape(root, at(0.46, 0.24), at(0.62, 0.16), C.Amber, UDim.new(0.5, 0), { Name = "Helmet", ZIndex = 3 })
	Shape(helmet, at(0.5, 0.45), at(0.22, 0.8), C.Gold, UDim.new(1, 0), { Name = "Lamp", ZIndex = 4 })
	local screen = Shape(head, at(0.5, 0.5), at(0.84, 0.66), C.Ink, UDim.new(0.18, 0), { Name = "Screen", ZIndex = 3 })
	face(screen, mood, 0.4, 0.22, 0.3, true)
	for _, side in { -1, 1 } do
		Shape(root, at(0.46 + side * 0.4, 0.58), at(0.08, 0.2), C.Metal, UDim.new(0.3, 0), { Name = "Ear", ZIndex = 1 })
	end
end

local function freezy(root: Frame, mood: Mood)
	-- Glaçon cubique avec un sablier sur la tête.
	local cube = Shape(root, at(0.5, 0.58), at(0.76, 0.7), C.White, UDim.new(0.16, 0), { Name = "Body", ZIndex = 2 })
	New("UIGradient", {
		Rotation = 120,
		Color = ColorSequence.new(C.White, Style.Color("CurrencyChips")),
		Parent = cube,
	})
	New("UIStroke", { Color = Style.Color("CurrencyChips"), Thickness = 3, Parent = cube })
	Shape(cube, at(0.22, 0.2), at(0.2, 0.08), C.White, UDim.new(1, 0), { Name = "Shine", Rotation = -30, ZIndex = 3 })
	-- Sablier
	local glass =
		Shape(root, at(0.5, 0.14), at(0.2, 0.22), C.Gold, nil, { Name = "Hourglass", BackgroundTransparency = 1 })
	for _, y in { 0.06, 0.94 } do
		Shape(glass, at(0.5, y), at(1.2, 0.12), C.Gold, UDim.new(1, 0), { ZIndex = 3 })
	end
	for _, y in { 0.3, 0.7 } do
		Shape(glass, at(0.5, y), at(0.55, 0.55), C.Gold, UDim.new(0.15, 0), {
			Rotation = 45,
			BackgroundTransparency = 0.25,
			ZIndex = 2,
		})
	end
	face(cube, mood, 0.44, 0.19, 0.24)
end

local function lagz(root: Frame, mood: Mood)
	-- Blob violet glitché, couronne en roue de chargement, yeux pixelisés.
	local crown: Frame = New("Frame", {
		Name = "Crown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(0.5, 0.14),
		Size = at(0.46, 0.46),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = root,
	})
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		Shape(
			crown,
			at(0.5 + math.cos(angle) * 0.4, 0.5 + math.sin(angle) * 0.4),
			at(0.2, 0.2),
			C.Gold,
			UDim.new(1, 0),
			{
				Name = "Dot",
				BackgroundTransparency = i / 10,
				ZIndex = 1,
			}
		)
	end
	if mood == "Evil" then
		spin(crown, 1.6)
	end
	local body = Shape(root, at(0.5, 0.58), at(0.86, 0.72), C.White, UDim.new(0.45, 0), { Name = "Body", ZIndex = 2 })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Virus, C.VirusHot), Parent = body })
	New("UIStroke", { Color = C.VirusDark, Thickness = 3, Parent = body })
	-- Gouttes du blob
	for _, x in { 0.2, 0.5, 0.8 } do
		Shape(root, at(x, 0.92), at(0.14, 0.12), C.VirusHot, UDim.new(1, 0), { Name = "Drip", ZIndex = 1 })
	end
	face(body, mood, 0.4, 0.2, 0.24, true)
	-- Barres de glitch (voir Common.Glitch)
	for i, color in { C.GlitchA, C.GlitchB } do
		New("Frame", {
			Name = "Glitch",
			Position = at(0.05, 0.3 + i * 0.2),
			Size = at(0.9, 0.06),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 7,
			Parent = root,
		})
	end
end

local BUILDERS: { [string]: (Frame, Mood) -> () } = {
	Sparky = sparky,
	["Pop-Up"] = popUp,
	Corrupto = corrupto,
	Dusty = dusty,
	Minor = minor,
	Freezy = freezy,
	LAGZ = lagz,
}

-- Construit le personnage `name` (carré) ; `size` / position en UDim2 du parent.
function Minions.Build(name: string, size: UDim2, mood: Mood?, parent: Instance?): Frame
	local feeling: Mood = mood or "Evil"
	local root: Frame = New("Frame", {
		Name = `Minion_{name}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(0.5, 0.5),
		Size = size,
		BackgroundTransparency = 1,
	}, {
		New("UIAspectRatioConstraint", { AspectRatio = 1 }),
	})
	local builder: (Frame, Mood) -> () = BUILDERS[name] or lagz
	builder(root, feeling)
	if feeling == "Defeated" then
		root.Rotation = 14
		dizzy(root)
	else
		local body = root:FindFirstChild("Body")
		if body then
			local breath: UIScale = New("UIScale", { Name = "Breath", Parent = body })
			Common.Pulse(breath, { Scale = 1.06 }, 0.5)
		end
	end
	if parent then
		root.Parent = parent
	end
	return root
end

return Minions
