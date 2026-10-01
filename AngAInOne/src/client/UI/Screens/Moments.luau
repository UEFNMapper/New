--!strict
--[[
	Moments : les instants forts du deathrun, courts et passables. L'histoire passe par l'IMAGE et
	par l'app partenaire AngAInOne (Windows 11 Fluent sombre : fond 202020, cartes 2B2B2B, accent
	violet, barre latérale avec l'avatar du joueur) — docs/AUDIT_V3.md C1 à C3.
	- Intro (première visite) : « Mode Intervention », une mission acceptée DANS l'app, en 3 étapes
	  (le PC rame, LAGZ le coupable, ta mission) ; le joueur devient Technicien·ne n° XXXX
	- En-tête de monde : la page de l'app du monde (titre + sous-titre gris, Util/AppPages)
	- Terminal réussi (« VIRUS ÉLIMINÉS, le portail est ouvert »)
	- Mort (petit flash glitch)
	- Victoire : « LE LIVE COMMENCE ! » (le stream d'Anga démarre, le chat défile), puis le
	  « Rapport AngAInOne » : la page Diagnostic de l'app (score 48 -> 100, cartes, menaces
	  supprimées, temps, record, clés USB, chutes, médaille du monde 7) (Util/OptimisationReport).
	  Public de moins de 13 ans : aucun appel à partager hors de Roblox, juste un rappel
	  « Capture d'écran 📸 ». Le rapport se ferme d'un toucher à l'extérieur, au ✕, ou seul
	  après 25 s (le serveur ramène le joueur au lobby et son écran « EN DIRECT » doit se voir).

	File des moments (UI/MomentQueue) : bannière « VIRUS ÉLIMINÉS » -> carte de médaille ->
	en-tête du monde suivant passent UN PAR UN (Moments.Queue / Finish / Expedite / ClearQueue).

	Téléphone : textes ≥ 18 px de conception, cibles tactiles ≥ 88 px ; sous une échelle de 0,75
	(petits écrans), mise en page COMPACTE (moins d'éléments, pas de liste de pages).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local NumberFormat = require(Shared.Util.NumberFormat)
local PcHealth = require(Shared.Util.PcHealth)
local Technician = require(Shared.Util.Technician)
local AppPages = require(Shared.Util.AppPages)
local OptimisationReport = require(Shared.Util.OptimisationReport)
local PerfTest = require(Shared.Util.PerfTest)
local Medals = require(Shared.Config.Medals)
local TimeUtil = require(Shared.Util.Time)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Lagz = require(script.Parent.Parent.Components.Lagz)
local Toasts = require(script.Parent.Toasts)
local MedalCard = require(script.Parent.MedalCard)
local MomentQueue = require(script.Parent.Parent.MomentQueue)

local New = Create.New

local Moments = {}

local layer: Frame

-- Plus petites tailles lisibles sur le plus petit téléphone (échelle ≈ 0,5).
local MIN_TEXT = 18
local TOUCH = 88
local COMPACT_SCALE = 0.75

-- Échelle réelle de l'interface (UIScale de App.Root) : < 0,75 = petit écran -> mise en page compacte.
local function isCompact(): boolean
	local root = layer and layer.Parent
	local scale = root and root:FindFirstChildOfClass("UIScale")
	return scale ~= nil and scale.Scale < COMPACT_SCALE
end

local function fullscreen(name: string, tag: string, transparency: number): Frame
	return New("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Tag = tag,
		Parent = layer,
	})
end

local function fadeOut(root: GuiObject, duration: number)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			Motion.Tween(d, { TextTransparency = 1 }, duration)
		end
	end
	Motion.Tween(root, { BackgroundTransparency = 1 }, duration).Completed:Once(function()
		root:Destroy()
	end)
end

------------------------------------------------------------------------------------
-- Kit « fenêtre de l'app AngAInOne » (Fluent sombre, reprise des captures de l'app)
------------------------------------------------------------------------------------

local APP = Branding.PartnerApp
local WHITE = Color3.new(1, 1, 1)
local A = {
	Surface = Color3.fromHex(APP.Surface),
	Side = Color3.fromRGB(28, 28, 28),
	Card = Color3.fromHex(APP.Card),
	CardHi = Color3.fromHex(APP.CardHover),
	Button = Color3.fromRGB(45, 45, 45),
	Stroke = Color3.fromRGB(58, 58, 58),
	Text = Color3.fromHex(APP.Text),
	Dim = Color3.fromHex(APP.TextDim),
	Faint = Color3.fromRGB(150, 150, 150),
	Accent = Color3.fromHex(APP.Accent),
	Violet = Color3.fromHex("8B7CFF"),
	Good = Color3.fromHex(APP.Good),
	Bad = Color3.fromHex(APP.Bad),
	Warn = Color3.fromHex(APP.Warn),
}
local F = Style.Fonts

type AppWindow = { Root: Frame, Main: Frame, Side: Frame, Close: TextButton }

local function text(
	parent: Instance,
	value: string,
	size: number,
	font: Font,
	color: Color3,
	props: { [string]: any }?
): TextLabel
	local label: TextLabel = New("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextSize = size,
		FontFace = font,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, size + 6),
		Parent = parent,
	})
	if props then
		for key, v in props do
			(label :: any)[key] = v
		end
	end
	return label
end

local function click()
	local sound = Keycap.ClickSound
	if sound then
		sound()
	end
end

local function appButton(
	parent: Instance,
	label: string,
	primary: boolean,
	position: UDim2,
	size: UDim2,
	onClick: () -> ()
): TextButton
	local button: TextButton = New("TextButton", {
		Position = position,
		Size = size,
		AutoButtonColor = false,
		BackgroundColor3 = if primary then A.Accent else A.Button,
		BorderSizePixel = 0,
		Text = label,
		TextSize = 20,
		FontFace = F.Bold,
		TextColor3 = A.Text,
		Parent = parent,
	}, {
		Create.Corner(8) :: Instance,
		New("UIStroke", {
			Color = if primary then A.Accent:Lerp(WHITE, 0.2) else A.Stroke,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	Motion.Pressable(button)
	button.Activated:Connect(function()
		click()
		onClick()
	end)
	return button
end

local function card(parent: Instance, position: UDim2, size: UDim2, color: Color3?): Frame
	return New("Frame", {
		Position = position,
		Size = size,
		BackgroundColor3 = color or A.Card,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Create.Corner(8) :: Instance })
end

local function dot(parent: Instance, position: UDim2, size: number, color: Color3): Frame
	return New("Frame", {
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance })
end

-- Pastille arrondie (badge « Nouveau », « En cours », « Terminé ✓ »…).
local function pill(parent: Instance, value: string, color: Color3, textColor: Color3?): Frame
	local frame: Frame = New("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		Create.Padding(0, 12) :: Instance,
	})
	text(frame, value, MIN_TEXT, F.Bold, textColor or A.Text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
	})
	return frame
end

local function headshot(parent: Instance, size: number, position: UDim2): ImageLabel
	return New("ImageLabel", {
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.fromRGB(60, 60, 60),
		BorderSizePixel = 0,
		Image = `rbxthumb://type=AvatarHeadShot&id={math.max(Players.LocalPlayer.UserId, 1)}&w=150&h=150`,
		Parent = parent,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance })
end

-- Titre de page + (?) + sous-titre gris, comme en haut de chaque page de l'app.
local function pageHeader(parent: Instance, title: string, subtitle: string, titleSize: number): Frame
	local header: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, titleSize + 36),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local row: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, titleSize + 8),
		BackgroundTransparency = 1,
		Parent = header,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 10, { VerticalAlignment = Enum.VerticalAlignment.Center }) :: Instance,
	})
	text(row, title, titleSize, F.Bold, A.Text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
	})
	local help: Frame = New("Frame", {
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = row,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		New("UIStroke", { Color = A.Dim, Thickness = 1.5 }) :: Instance,
	})
	text(help, "?", MIN_TEXT, F.Bold, A.Dim, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	text(header, subtitle, MIN_TEXT, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(0, titleSize + 8),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return header
end

-- Fenêtre de l'app : barre de titre, barre latérale (avatar, badge, recherche, pages), contenu.
-- Textes ≥ 18 px ; le ✕ a une zone tactile de 88 × 88 px (coin haut droit de la fenêtre).
-- `pages` vide = pas de recherche ni de liste de pages (mise en page compacte, rapport).
local TITLE_H = 40

local function appWindow(
	parent: Instance,
	size: Vector2,
	sideWidth: number,
	pages: { string },
	selected: string
): AppWindow
	local player = Players.LocalPlayer
	local root: Frame = New("Frame", {
		Name = "AngAInOneWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = A.Surface,
		BorderSizePixel = 0,
		Active = true,
		Parent = parent,
	}, {
		Create.Corner(8) :: Instance,
		New("UIStroke", { Color = A.Stroke, Thickness = 1 }) :: Instance,
	})
	-- Barre de titre
	local logo: Frame = New("Frame", {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = A.Accent,
		BorderSizePixel = 0,
		Parent = root,
	}, { Create.Corner(5) :: Instance })
	text(logo, "A", MIN_TEXT, F.Heavy, A.Text, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	text(root, `{APP.Name}  ·  {APP.Version}`, MIN_TEXT, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(46, 8),
		Size = UDim2.fromOffset(360, 24),
	})
	New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -150, 0, 20),
		Size = UDim2.fromOffset(12, 1),
		BackgroundColor3 = A.Dim,
		BorderSizePixel = 0,
		Parent = root,
	})
	New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -104, 0, 14),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		Parent = root,
	}, { New("UIStroke", { Color = A.Dim, Thickness = 1 }) :: Instance })
	-- ✕ : zone tactile 88 × 88 (transparente), case rouge visible de 64 × 38 dans le coin
	local close: TextButton = New("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(TOUCH, TOUCH),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		Parent = root,
	})
	local closeCap: Frame = New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -1, 0, 1),
		Size = UDim2.fromOffset(64, TITLE_H - 2),
		BackgroundColor3 = Color3.fromRGB(196, 43, 28),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = close,
	}, { Create.Corner(7) :: Instance })
	text(closeCap, "✕", 22, F.Medium, A.Text, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
	})
	close.MouseEnter:Connect(function()
		closeCap.BackgroundTransparency = 0
	end)
	close.MouseLeave:Connect(function()
		closeCap.BackgroundTransparency = 1
	end)

	-- Barre latérale
	local side: Frame = New("Frame", {
		Position = UDim2.fromOffset(0, TITLE_H),
		Size = UDim2.new(0, sideWidth, 1, -TITLE_H),
		BackgroundTransparency = 1,
		Parent = root,
	})
	headshot(side, 48, UDim2.fromOffset(14, 6))
	text(side, player.DisplayName, 20, F.Bold, A.Text, {
		Position = UDim2.fromOffset(72, 4),
		Size = UDim2.new(1, -80, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	text(side, Technician.Short(player.UserId), MIN_TEXT, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(72, 30),
		Size = UDim2.new(1, -80, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if #pages > 0 then
		local search = card(side, UDim2.fromOffset(10, 64), UDim2.new(1, -20, 0, 38), A.Card)
		New("UIStroke", { Color = A.Stroke, Parent = search })
		text(search, "Rechercher", MIN_TEXT, F.Regular, A.Dim, {
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -40, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		New("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, -1),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			Parent = search,
		}, {
			New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
			New("UIStroke", { Color = A.Dim, Thickness = 1.5 }) :: Instance,
		})
	end
	for i, name in pages do
		local row: Frame = New("Frame", {
			Position = UDim2.fromOffset(6, 112 + (i - 1) * 38),
			Size = UDim2.new(1, -12, 0, 36),
			BackgroundColor3 = A.CardHi,
			BackgroundTransparency = if name == selected then 0 else 1,
			BorderSizePixel = 0,
			Parent = side,
		}, { Create.Corner(4) :: Instance })
		if name == selected then
			New("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(3, 18),
				BackgroundColor3 = A.Accent,
				BorderSizePixel = 0,
				Parent = row,
			}, { Create.Corner(2) :: Instance })
		end
		New("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			Parent = row,
		}, {
			Create.Corner(3) :: Instance,
			New("UIStroke", { Color = if name == selected then A.Text else A.Dim, Thickness = 1.5 }) :: Instance,
		})
		text(row, name, MIN_TEXT, if name == selected then F.Medium else F.Regular, A.Text, {
			Position = UDim2.fromOffset(36, 0),
			Size = UDim2.new(1, -42, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local main: Frame = New("Frame", {
		Position = UDim2.fromOffset(sideWidth, TITLE_H),
		Size = UDim2.new(1, -sideWidth, 1, -TITLE_H),
		BackgroundTransparency = 1,
		Parent = root,
	}, { Create.Padding(0, 26) :: Instance })
	return { Root = root, Main = main, Side = side, Close = close }
end

------------------------------------------------------------------------------------
-- Intro : « Mode Intervention », une mission acceptée dans l'app (3 étapes)
------------------------------------------------------------------------------------

local STEPS = {
	{ Title = "Le problème", Sub = "Le PC d'Anga est au plus mal." },
	{ Title = "Le coupable", Sub = "Un virus se cache dans la tour." },
	{ Title = "Ta mission", Sub = "Nettoie la tour, monde par monde." },
}

local MINIONS = { "Sparky", "Pop-Up", "Corrupto", "Dusty", "Minor", "Freezy" }

-- Grosse tuile « valeur + légende » (FPS, ping, °C).
local function statTile(parent: Instance, position: UDim2, value: string, caption: string, color: Color3)
	local tile = card(parent, position, UDim2.fromOffset(168, 118), A.CardHi)
	dot(tile, UDim2.fromOffset(14, 17), 10, color)
	text(
		tile,
		caption,
		MIN_TEXT,
		F.Medium,
		A.Dim,
		{ Position = UDim2.fromOffset(32, 8), Size = UDim2.new(1, -40, 0, 26) }
	)
	local big = text(tile, value, 44, F.Heavy, color, {
		Position = UDim2.fromOffset(14, 44),
		Size = UDim2.new(1, -20, 0, 56),
	})
	Motion.Pop(big, 0.2)
end

-- Bouton « SUITE → » en bas à droite de l'étape (cible tactile 240 × 88).
local function nextButton(body: Frame, onNext: () -> ())
	local button =
		appButton(body, "SUITE  →", true, UDim2.new(1, -240, 1, -TOUCH), UDim2.fromOffset(240, TOUCH), onNext)
	button.TextSize = 24
end

-- Contenu d'une étape ouverte (zone de 688 × 264 px de conception).
local function introStep(body: Frame, step: number, onNext: () -> (), onAccept: (TextButton) -> ())
	local player = Players.LocalPlayer
	if step == 1 then
		local before = PcHealth.Stats(0)
		statTile(body, UDim2.fromOffset(0, 0), tostring(before.Fps), "FPS", A.Bad)
		statTile(body, UDim2.fromOffset(180, 0), `{before.Ping} ms`, "Ping", A.Bad)
		statTile(body, UDim2.fromOffset(360, 0), `{before.Temp} °C`, "Température", A.Bad)
		local avatar = Widgets.Avatar(64, body)
		avatar.Position = UDim2.fromOffset(0, 136)
		text(body, `{Branding.MascotName} : « Mon PC RAME ! Mon live commence dans 1 heure ! »`, 20, F.Bold, A.Text, {
			Position = UDim2.fromOffset(78, 132),
			Size = UDim2.new(1, -340, 0, 72),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		nextButton(body, onNext)
	elseif step == 2 then
		local face = Lagz.Face(120, body)
		face.Position = UDim2.fromOffset(0, 0)
		Motion.Pop(face, 0.3)
		text(
			body,
			"LAGZ",
			34,
			F.Heavy,
			Lagz.Color,
			{ Position = UDim2.fromOffset(140, 0), Size = UDim2.new(1, -140, 0, 40) }
		)
		text(body, "Un virus qui MANGE la puissance du PC.", 20, F.Bold, A.Text, {
			Position = UDim2.fromOffset(140, 42),
			Size = UDim2.new(1, -140, 0, 26),
		})
		text(body, "Ses 6 sbires se cachent dans la tour :", MIN_TEXT, F.Regular, A.Dim, {
			Position = UDim2.fromOffset(140, 72),
			Size = UDim2.new(1, -140, 0, 24),
		})
		local chips: Frame = New("Frame", {
			Position = UDim2.fromOffset(140, 102),
			Size = UDim2.new(1, -140, 0, 72),
			BackgroundTransparency = 1,
			Parent = body,
		}, {
			New("UIGridLayout", {
				CellSize = UDim2.fromOffset(128, 32),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}) :: Instance,
		})
		for i, name in MINIONS do
			local def = Tower.Worlds[i]
			local chip = card(chips, UDim2.new(), UDim2.new(), A.CardHi)
			chip.LayoutOrder = i
			dot(chip, UDim2.fromOffset(10, 11), 10, if def then Color3.fromHex(def.Primary) else A.Violet)
			text(
				chip,
				name,
				MIN_TEXT,
				F.Medium,
				A.Text,
				{ Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0) }
			)
		end
		-- LAGZ glitche (tremblement léger), sauf « Réduire les animations »
		task.spawn(function()
			while face.Parent do
				if not Motion.IsReduced() then
					face.Position = UDim2.fromOffset(math.random(-3, 3), math.random(-2, 2))
				end
				task.wait(if math.random() < 0.2 then 0.05 else 0.4)
			end
		end)
		nextButton(body, onNext)
	else
		-- Badge du technicien (à gauche) + ordre de mission (à droite)
		local badge = card(body, UDim2.fromOffset(0, 0), UDim2.fromOffset(260, 192), A.Accent)
		New("UIGradient", {
			Rotation = 35,
			Color = ColorSequence.new(A.Accent, A.Violet),
			Parent = badge,
		})
		text(badge, "BADGE OFFICIEL", MIN_TEXT, F.Heavy, WHITE, {
			Position = UDim2.fromOffset(16, 8),
			TextTransparency = 0.2,
		})
		headshot(badge, 56, UDim2.fromOffset(16, 40))
		text(badge, player.DisplayName, 20, F.Heavy, WHITE, {
			Position = UDim2.fromOffset(82, 54),
			Size = UDim2.new(1, -92, 0, 28),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(badge, `n° {Technician.Code(player.UserId)}`, 40, F.Heavy, WHITE, {
			Position = UDim2.fromOffset(16, 102),
			Size = UDim2.new(1, -32, 0, 48),
		})
		text(badge, "Technicien·ne AngAInOne", MIN_TEXT, F.Medium, WHITE, {
			Position = UDim2.fromOffset(16, 156),
			Size = UDim2.new(1, -24, 0, 26),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Motion.Pop(badge, 0.12)
		local orders = {
			"Entre dans la tour du PC.",
			`Nettoie les {Tower.WORLD_COUNT} mondes.`,
			"Supprime LAGZ, tout en haut !",
		}
		for i, line in orders do
			local y = (i - 1) * 50
			local number = dot(body, UDim2.fromOffset(282, y), 38, A.CardHi)
			text(number, tostring(i), 20, F.Heavy, A.Text, {
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			text(
				body,
				line,
				20,
				F.Bold,
				A.Text,
				{ Position = UDim2.fromOffset(332, y + 4), Size = UDim2.new(1, -332, 0, 30) }
			)
		end
		local accept: TextButton
		accept = appButton(
			body,
			"ACCEPTER LA MISSION",
			true,
			UDim2.new(1, -340, 1, -TOUCH),
			UDim2.fromOffset(340, TOUCH),
			function()
				onAccept(accept)
			end
		)
		accept.TextSize = 24
		accept.FontFace = F.Heavy
		Motion.Pop(accept, 0.1)
	end
end

-- Hauteurs des étapes (fenêtre de 600 px : la zone des étapes fait 472 px)
local STEP_OPEN_H = 340
local STEP_CLOSED_H = 56

function Moments.Intro(onDone: () -> ())
	local dim = fullscreen("Intro", "Backdrop", 0.3)
	local compact = isCompact()
	local pages = AppPages.Sidebar(Tower.Worlds)
	table.insert(pages, 2, "Mode Intervention")
	-- Petit écran : pas de recherche ni de liste de pages (moins de choses à lire)
	local window = appWindow(dim, Vector2.new(1000, 600), 220, if compact then {} else pages, "Mode Intervention")
	window.Close.Visible = false -- la mission se lance avec le gros bouton
	local main = window.Main
	pageHeader(main, "Mode Intervention", "Une réparation en direct… depuis l'intérieur du PC.", 28).Position =
		UDim2.fromOffset(0, 8)
	local status = pill(main, "PC d'Anga : critique", A.Bad:Lerp(Color3.new(0, 0, 0), 0.55), A.Bad)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, 0, 0, 12)

	local steps: Frame = New("Frame", {
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -88),
		BackgroundTransparency = 1,
		Parent = main,
	}, { Create.List(Enum.FillDirection.Vertical, 8) :: Instance })

	local current = 1
	local accepted = false
	local render: () -> ()
	local function finish(button: TextButton)
		if accepted then
			return
		end
		accepted = true
		button.Text = "MISSION ACCEPTÉE ✓"
		button.BackgroundColor3 = A.Good:Lerp(Color3.new(0, 0, 0), 0.35)
		Motion.Pop(button, 0.15)
		Toasts.Show("Success", `Mission acceptée ! Bonne chance, {Technician.Short(Players.LocalPlayer.UserId)} !`)
		task.delay(0.9, function()
			window.Root.Visible = false
			fadeOut(dim, 0.3)
			onDone()
		end)
	end
	render = function()
		for _, child in steps:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, step in STEPS do
			local open = i == current
			local box =
				card(steps, UDim2.new(), UDim2.new(1, 0, 0, if open then STEP_OPEN_H else STEP_CLOSED_H), A.Card)
			box.LayoutOrder = i
			local number = dot(
				box,
				UDim2.fromOffset(14, 13),
				30,
				if i < current then A.Good elseif open then A.Accent else A.CardHi
			)
			text(number, if i < current then "✓" else tostring(i), MIN_TEXT, F.Heavy, A.Text, {
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			text(
				box,
				`Étape {i} — {step.Title}`,
				20,
				F.Medium,
				A.Text,
				{ Position = UDim2.fromOffset(56, 3), Size = UDim2.new(1, -210, 0, 26) }
			)
			text(
				box,
				step.Sub,
				MIN_TEXT,
				F.Regular,
				A.Dim,
				{ Position = UDim2.fromOffset(56, 28), Size = UDim2.new(1, -210, 0, 24) }
			)
			local badge = pill(
				box,
				if i < current then "Terminé ✓" elseif open then "En cours" else "À venir",
				if i < current then A.Good:Lerp(Color3.new(0, 0, 0), 0.6) else A.CardHi,
				if i < current then A.Good else A.Dim
			)
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, -14, 0, 13)
			if open then
				local body: Frame = New("Frame", {
					Position = UDim2.fromOffset(20, 64),
					Size = UDim2.new(1, -40, 1, -76),
					BackgroundTransparency = 1,
					Parent = box,
				})
				introStep(body, i, function()
					current += 1
					render()
				end, finish)
			end
		end
	end
	render()
	Motion.Pop(window.Root, 0.06)
end

------------------------------------------------------------------------------------
-- File des moments : bannière -> médaille -> en-tête du monde, un seul à la fois
------------------------------------------------------------------------------------

-- Affichage d'un moment : reçoit `done` (à appeler s'il se ferme plus tôt, ex. d'un toucher)
-- et peut renvoyer une fonction qui le cache (fin de son temps, ou file vidée).
export type Show = (done: () -> ()) -> (() -> ())?

local queue = MomentQueue.new()
local pumpToken = 0
local currentHide: (() -> ())? = nil

local pump: () -> ()
pump = function()
	local now = os.clock()
	local started, finished = MomentQueue.Step(queue, now)
	-- D'abord cacher le moment terminé, ensuite seulement montrer le suivant.
	if finished then
		local hide = currentHide
		currentHide = nil
		if hide then
			xpcall(hide, function(err: any)
				warn("[Moments] fin d'un moment :", err)
			end)
		end
	end
	if started then
		local item = started
		local show = item.Data :: Show
		local ok, result = xpcall(show, function(err: any)
			warn(`[Moments] moment « {item.Kind} » :`, err)
		end, function()
			-- Différé : `done` peut être appelé pendant l'affichage lui-même (pas de ré-entrée).
			if MomentQueue.FinishItem(queue, item, os.clock()) then
				task.defer(pump)
			end
		end)
		if ok and type(result) == "function" then
			currentHide = result
		end
	end
	if queue.Current then
		pumpToken += 1
		local token = pumpToken
		task.delay(math.max(queue.EndsAt - now, 0) + 0.02, function()
			if token == pumpToken then
				pump()
			end
		end)
	end
end

-- Ajoute un moment à la file (`unique` : remplace un moment du même type encore en attente).
function Moments.Queue(kind: string, hold: number, show: Show, unique: boolean?)
	MomentQueue.Push(queue, { Kind = kind, Hold = hold, Unique = unique, Data = show })
	pump()
end

-- Le moment en cours de ce type se termine maintenant.
function Moments.Finish(kind: string)
	if MomentQueue.Finish(queue, kind, os.clock()) then
		pump()
	end
end

-- Raccourcit un type de moment (en cours : `minShown` s affiché au total au plus).
function Moments.Expedite(kind: string, minShown: number)
	MomentQueue.Expedite(queue, kind, os.clock(), minShown)
	pump()
end

-- Vide la file et cache le moment en cours (écran de victoire).
function Moments.ClearQueue()
	MomentQueue.Clear(queue, os.clock())
	pump()
end

------------------------------------------------------------------------------------
-- Bannières
------------------------------------------------------------------------------------

local BANNER_SECONDS = 4
local BANNER_FADE = 0.4
local HEADER_SECONDS = 4.5
local HEADER_FADE = 0.35

-- Bandeau plein écran ; renvoie une fonction qui le cache tout de suite.
local function banner(accent: Color3, caption: string, title: string, subtitle: string, seconds: number): () -> ()
	local band: Frame = New("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Style.Color("BgDeep"),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = layer,
	}, {
		New("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.1),
				NumberSequenceKeypoint.new(0.8, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local sweep: Frame = New("Frame", {
		Size = UDim2.new(0, 0, 0, 3),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = band,
	})
	New("Frame", {
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.new(0, 0, 1, -3),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = band,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = caption,
		Tag = "TextHeading", -- 18 px : lisible sur téléphone
		Parent = band,
	})
	local titleLabel: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		Text = title,
		Tag = "TextHero",
		Parent = band,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Text = subtitle,
		Tag = "TextHeading",
		Parent = band,
	})
	Motion.Pop(titleLabel, 0.25)
	Motion.Tween(sweep, { Size = UDim2.new(1, 0, 0, 3) }, 0.9, Enum.EasingStyle.Quart)
	local hidden = false
	local function hide()
		if hidden then
			return
		end
		hidden = true
		if band.Parent then
			fadeOut(band, BANNER_FADE)
		end
	end
	task.delay(seconds, hide)
	return hide
end

-- En-tête de la page de l'app d'un monde ; renvoie une fonction qui le cache tout de suite.
local function worldHeader(world: number): (() -> ())?
	local def = Tower.Worlds[world]
	if not def then
		return nil
	end
	local page = AppPages.Of(world, def)
	local accent = Color3.fromHex(def.Primary)
	local header: Frame = New("Frame", {
		Name = "AppPageBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.2, 0),
		Size = UDim2.fromOffset(720, 132),
		BackgroundColor3 = A.Surface,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Parent = layer,
	}, {
		Create.Corner(8) :: Instance,
		New("UIStroke", { Color = A.Stroke }) :: Instance,
	})
	New("Frame", {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(0, 4, 1, -28),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = header,
	}, { Create.Corner(2) :: Instance })
	local content: Frame = New("Frame", {
		Position = UDim2.fromOffset(26, 12),
		Size = UDim2.new(1, -44, 1, -20),
		BackgroundTransparency = 1,
		Parent = header,
	})
	text(content, `{APP.Name}  ›  Monde {world}/{Tower.WORLD_COUNT} · {def.Component}`, MIN_TEXT, F.Medium, A.Dim, {
		Size = UDim2.new(1, -250, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	pageHeader(content, page.Title, page.Subtitle, 30).Position = UDim2.fromOffset(0, 28)
	local alert = pill(content, `⚠ {def.Minion} détecté`, A.Bad:Lerp(Color3.new(0, 0, 0), 0.55), A.Bad)
	alert.AnchorPoint = Vector2.new(1, 0)
	alert.Position = UDim2.new(1, 0, 0, 0)
	Motion.Pop(header, 0.08)
	local hidden = false
	local function hide()
		if hidden then
			return
		end
		hidden = true
		if header.Parent then
			Motion.Tween(header, { Position = UDim2.new(0.5, 0, 0.2, -20), BackgroundTransparency = 1 }, HEADER_FADE)
			fadeOut(header, HEADER_FADE)
		end
	end
	task.delay(HEADER_SECONDS, hide)
	return hide
end

-- En entrant dans un monde : l'en-tête de la page de l'app qui lui correspond (dans la file :
-- après la bannière et la carte de médaille du monde précédent ; le plus récent seulement).
function Moments.WorldBanner(world: number)
	Moments.Queue("World", HEADER_SECONDS + HEADER_FADE, function(_done: () -> ()): (() -> ())?
		return worldHeader(world)
	end, true)
end

-- Monde nettoyé : bandeau « VIRUS ÉLIMINÉS ! » (dans la file, avant la carte de médaille).
function Moments.WorldCleared(world: number, bits: number)
	local def = Tower.Worlds[world]
	local caption = if world < Tower.WORLD_COUNT then "LE PORTAIL EST OUVERT !" else "LE CŒUR DU VIRUS EST DÉTRUIT !"
	Moments.Queue("Cleared", BANNER_SECONDS + BANNER_FADE, function(_done: () -> ()): (() -> ())?
		return banner(
			Style.Color("Success"),
			caption,
			"VIRUS ÉLIMINÉS !",
			`{if def then def.Name else ""} est propre · +{NumberFormat.Compact(bits)} Bits`,
			BANNER_SECONDS
		)
	end)
end

------------------------------------------------------------------------------------
-- Mort et victoire
------------------------------------------------------------------------------------

function Moments.DeathFlash()
	local flash = fullscreen("Death", "FillBrand", 0.55)
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(700, 60),
		BackgroundTransparency = 1,
		Text = "OUPS ! Retour au checkpoint…",
		Tag = "FontDisplay",
		TextSize = 34,
		TextColor3 = Style.Color("TextPrimary"),
		TextStrokeTransparency = 0.4,
		Parent = flash,
	})
	task.delay(0.35, function()
		fadeOut(flash, 0.9)
	end)
end

------------------------------------------------------------------------------------
-- Rapport AngAInOne : la page « Diagnostic » de l'app, après la victoire
------------------------------------------------------------------------------------

local REPORT_AUTO_CLOSE = 25 -- s : le serveur ramène au lobby à t + 7 s, l'écran « EN DIRECT » doit se voir
local REPORT_TAP_GUARD = 0.5 -- s : le toucher qui ouvre le rapport ne le referme pas
local CARD_W, CARD_GAP = 164, 12

local MEDAL_SHORT: { [string]: string } = { Gold = "Or", Silver = "Argent", Bronze = "Bronze" }

-- Carte du diagnostic : titre + note sur 100 (en gros). Renvoie le chiffre du score (carte 1).
local function reportCard(parent: Instance, index: number, data: OptimisationReport.Card): TextLabel?
	local box =
		card(parent, UDim2.fromOffset((index - 1) * (CARD_W + CARD_GAP), 0), UDim2.fromOffset(CARD_W, 96), A.Card)
	text(box, data.Title, MIN_TEXT, F.Bold, A.Text, {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -20, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local x = 12
	if index > 1 then
		dot(box, UDim2.fromOffset(12, 56), 10, if data.Good then A.Good else A.Bad)
		x = 30
	end
	local score = text(
		box,
		tostring(if index == 1 then OptimisationReport.START_SCORE else data.Score),
		34,
		F.Heavy,
		A.Text,
		{ Position = UDim2.fromOffset(x, 38), Size = UDim2.fromOffset(66, 44) }
	)
	text(
		box,
		"/100",
		MIN_TEXT,
		F.Regular,
		A.Dim,
		{ Position = UDim2.fromOffset(x + 66, 54), Size = UDim2.fromOffset(60, 24) }
	)
	return if index == 1 then score else nil
end

-- Une menace supprimée : titre, action faite, et 3 lignes (constat, pourquoi, quoi faire).
local function reportEntry(parent: Instance, entry: OptimisationReport.Entry)
	local box = card(parent, UDim2.new(), UDim2.new(1, -10, 0, 132), A.Card)
	box.LayoutOrder = entry.World
	local def = Tower.Worlds[entry.World]
	local badge = dot(box, UDim2.fromOffset(14, 12), 32, A.Good:Lerp(Color3.new(0, 0, 0), 0.6))
	text(
		badge,
		"✓",
		MIN_TEXT,
		F.Heavy,
		A.Good,
		{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }
	)
	text(box, entry.Title, 20, F.Medium, A.Text, {
		Position = UDim2.fromOffset(58, 10),
		Size = UDim2.new(1, -250, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if def then
		dot(box, UDim2.fromOffset(26, 56), 8, Color3.fromHex(def.Primary))
	end
	for i, row in { { "Constat", entry.Constat }, { "Pourquoi", entry.Pourquoi }, { "Quoi faire", entry.QuoiFaire } } do
		local y = 42 + (i - 1) * 28
		text(
			box,
			row[1],
			MIN_TEXT,
			F.Bold,
			A.Dim,
			{ Position = UDim2.fromOffset(58, y), Size = UDim2.fromOffset(120, 26) }
		)
		text(box, row[2], MIN_TEXT, if i == 3 then F.Medium else F.Regular, if i == 3 then A.Text else A.Dim, {
			Position = UDim2.fromOffset(184, y),
			Size = UDim2.new(1, -200, 0, 26),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local done = pill(box, entry.Action, A.Accent)
	done.AnchorPoint = Vector2.new(1, 0)
	done.Position = UDim2.new(1, -14, 0, 10)
end

-- Colonne « Ta mission » : la médaille du monde 7 (sa carte n'est pas montrée pendant la
-- victoire, pour ne pas se superposer à l'écran final).
local function medalBox(side: Instance, medal: any, y: number)
	if type(medal) ~= "table" or type(medal.Medal) ~= "string" then
		return
	end
	local box = card(side, UDim2.fromOffset(10, y), UDim2.new(1, -20, 0, 156), A.Card)
	box.Name = "WorldMedal"
	New("UIStroke", { Color = A.Violet, Transparency = 0.4, Parent = box })
	text(box, `Médaille du monde {Tower.WORLD_COUNT}`, MIN_TEXT, F.Bold, A.Text, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -24, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local icon = MedalCard.Icon(medal.Medal, 72)
	icon.Position = UDim2.fromOffset(12, 38)
	icon.Parent = box
	Motion.Pop(icon, 0.25)
	local colors = (Medals.Colors :: any)[medal.Medal] or Medals.Colors.Bronze
	text(box, MEDAL_SHORT[medal.Medal] or medal.Medal, 24, F.Heavy, Color3.fromHex(colors[1]), {
		Position = UDim2.fromOffset(96, 38),
		Size = UDim2.new(1, -106, 0, 30),
	})
	local time = if type(medal.Time) == "number" then medal.Time else 0
	local deaths = if type(medal.Deaths) == "number" then medal.Deaths else 0
	text(box, `⏱ {if time > 0 then TimeUtil.Clock(time) else "—"}`, MIN_TEXT, F.Bold, A.Text, {
		Position = UDim2.fromOffset(96, 70),
		Size = UDim2.new(1, -106, 0, 24),
	})
	text(box, `💥 {deaths} {if deaths == 1 then "chute" else "chutes"}`, MIN_TEXT, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(96, 96),
		Size = UDim2.new(1, -106, 0, 24),
	})
	if medal.NewBest == true then
		text(box, "✦ Nouveau record !", MIN_TEXT, F.Heavy, A.Violet, {
			Position = UDim2.fromOffset(14, 124),
			Size = UDim2.new(1, -24, 0, 24),
		})
	end
end

local function showReport(payload: any, medal: any?)
	local report = OptimisationReport.Build({
		Time = if type(payload.Time) == "number" then payload.Time else 0,
		Record = payload.Record == true,
		Assisted = payload.Assisted == true,
		Keys = if type(payload.Keys) == "number" then payload.Keys else nil,
		KeysTotal = if type(payload.KeysTotal) == "number" then payload.KeysTotal else nil,
		Deaths = if type(payload.Deaths) == "number" then payload.Deaths else nil,
	})
	local dateText = OptimisationReport.DateText(os.date("*t") :: any)
	local compact = isCompact()

	-- Fond : un bouton plein écran, un toucher À L'EXTÉRIEUR de la fenêtre ferme le rapport.
	local screen: TextButton = New("TextButton", {
		Name = "Report",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Tag = "Backdrop",
		Parent = layer,
	})
	Motion.Tween(screen, { BackgroundTransparency = 0.35 }, 0.4)
	-- Rapport : pas de liste de pages, la barre latérale sert à « Ta mission » et à la médaille.
	local window = appWindow(screen, Vector2.new(1180, 600), 260, {}, "Diagnostic")
	local openedAt = os.clock()
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		window.Root.Visible = false
		fadeOut(screen, 0.3)
	end
	window.Close.Activated:Connect(function()
		click()
		close()
	end)
	screen.Activated:Connect(function()
		if os.clock() - openedAt >= REPORT_TAP_GUARD then
			close()
		end
	end)

	-- Barre latérale : « Ta mission » (temps, record, clés USB, chutes, badge), puis la médaille
	local side = window.Side
	local mission = card(side, UDim2.fromOffset(10, 72), UDim2.new(1, -20, 0, 202), A.Card)
	text(
		mission,
		"Ta mission",
		20,
		F.Bold,
		A.Text,
		{ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 26) }
	)
	local rows: { { string } } = { { "Temps", report.TimeText } }
	if report.RecordText then
		table.insert(rows, { "", report.RecordText :: string })
	end
	table.insert(rows, { "Clés USB", report.KeysText })
	if report.DeathsText then
		table.insert(rows, { "Chutes", report.DeathsText :: string })
	end
	for i, row in rows do
		local y = 40 + (i - 1) * 28
		if row[1] == "" then
			text(mission, row[2], MIN_TEXT, F.Heavy, Style.Color("CurrencyBits"), {
				Position = UDim2.fromOffset(14, y),
				Size = UDim2.new(1, -28, 0, 26),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
		else
			text(
				mission,
				row[1],
				MIN_TEXT,
				F.Regular,
				A.Dim,
				{ Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 26) }
			)
			text(mission, row[2], MIN_TEXT, F.Bold, A.Text, {
				Position = UDim2.fromOffset(14, y),
				Size = UDim2.new(1, -28, 0, 26),
				TextXAlignment = Enum.TextXAlignment.Right,
			})
		end
	end
	local technicianBadge = pill(mission, "✓ Badge Technicien·ne", A.Accent)
	technicianBadge.Position = UDim2.new(0, 14, 1, -40)
	medalBox(side, medal, 286)

	-- Contenu : en-tête, rappel « capture d'écran », verdict, chiffres, cartes, menaces supprimées
	local main = window.Main
	pageHeader(main, "Diagnostic", "Ce qui va, ce qui cloche, et quoi faire.", 28).Position = UDim2.fromOffset(0, 8)
	-- Moins de 13 ans : pas de bouton de partage hors de Roblox, juste un rappel.
	local capture = pill(main, "Capture d'écran 📸", A.CardHi, A.Violet)
	capture.AnchorPoint = Vector2.new(1, 0)
	capture.Position = UDim2.new(1, -72, 0, 14)
	local verdictIcon = dot(main, UDim2.fromOffset(0, 83), 18, A.Surface)
	New("UIStroke", { Color = A.Good, Thickness = 2, Parent = verdictIcon })
	text(main, OptimisationReport.Verdict(dateText), MIN_TEXT, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(28, 78),
		Size = UDim2.new(1, -28, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	text(
		main,
		report.Headline,
		26,
		F.Bold,
		A.Text,
		{ Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 0, 34), TextTruncate = Enum.TextTruncate.AtEnd }
	)
	text(main, `{report.Threats} menaces supprimées · {report.Summary}`, MIN_TEXT, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(0, 144),
		Size = UDim2.new(1, 0, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- Avant -> après, en GROS
	for i, delta in report.Deltas do
		local box = card(main, UDim2.fromOffset((i - 1) * 293, 178), UDim2.fromOffset(282, 70), A.Card)
		text(
			box,
			delta.Label,
			MIN_TEXT,
			F.Medium,
			A.Dim,
			{ Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -28, 0, 24) }
		)
		local value = text(box, "", 30, F.Heavy, A.Text, {
			Position = UDim2.fromOffset(14, 28),
			Size = UDim2.new(1, -28, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Right,
			RichText = true,
		})
		local bad = A.Bad:ToHex()
		local good = A.Good:ToHex()
		Motion.CountTo(value, delta.From, delta.To, function(n: number): string
			return `<font color="#{bad}" size="20">{delta.From}</font> → <font color="#{good}">{math.floor(n + 0.5)}{delta.Unit}</font>`
		end, 1.6)
	end
	-- Les 5 cartes du diagnostic (pas sur petit écran : la liste des menaces a plus de place)
	local listTop = 262
	if not compact then
		local cardsRow: Frame = New("Frame", {
			Position = UDim2.fromOffset(0, 258),
			Size = UDim2.new(1, 0, 0, 96),
			BackgroundTransparency = 1,
			Parent = main,
		})
		local scoreLabel: TextLabel? = nil
		for i, data in report.Cards do
			local label = reportCard(cardsRow, i, data)
			if label then
				scoreLabel = label
			end
		end
		if scoreLabel then
			local label = scoreLabel
			task.spawn(function()
				local start = os.clock()
				local duration = if Motion.IsReduced() then 0 else 1.8
				while label.Parent do
					local alpha = if duration > 0 then (os.clock() - start) / duration else 1
					label.Text = tostring(OptimisationReport.ScoreAt(alpha, report.Score))
					if alpha >= 1 then
						break
					end
					task.wait()
				end
				label.TextColor3 = A.Good
				Motion.Pop(label, 0.25)
			end)
		end
		listTop = 366
	end
	-- « Ce qu'il faut regarder » : une entrée par menace supprimée
	text(
		main,
		"Ce qu'il faut regarder",
		20,
		F.Bold,
		A.Text,
		{ Position = UDim2.fromOffset(0, listTop), Size = UDim2.new(1, 0, 0, 26) }
	)
	local list: ScrollingFrame = New("ScrollingFrame", {
		Position = UDim2.fromOffset(0, listTop + 32),
		Size = UDim2.new(1, 0, 1, -(listTop + 40)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = A.Dim,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = main,
	}, { Create.List(Enum.FillDirection.Vertical, 8) :: Instance })
	for _, entry in report.Entries do
		reportEntry(list, entry)
	end
	Motion.Pop(window.Root, 0.05)
	task.delay(REPORT_AUTO_CLOSE, close)
end

local LIVE_CHAT = {
	{ Name = "PixelPanda", Text = "GG !!!" },
	{ Name = "Nova_08", Text = "merci l'antivirus ! 🙏" },
	{ Name = "TitoGamer", Text = "144 FPS 🔥🔥" },
	{ Name = "LunaBits", Text = "{name} le héros !" },
	{ Name = "RoboChips", Text = "LET'S GOOO" },
	{ Name = "Kiwi_12", Text = "bye bye LAGZ 👋" },
	{ Name = "ZigZag", Text = "GG {name} !" },
	{ Name = "MiniMax", Text = "le live est trop fluide" },
	{ Name = "Choco", Text = "merci {name} !!" },
	{ Name = "Sunny", Text = "LAGZ a perdu mdr" },
}
local CHAT_COLORS = { "F6AD55", "4FD1C5", "8B7CFF", "68D391", "ED64A6", "63B3ED" }

local function escapeRich(value: string): string
	return (string.gsub(string.gsub(string.gsub(value, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Fin : « LE LIVE COMMENCE ! » — le stream d'Anga démarre et le chat fête le joueur, puis le
-- Rapport AngAInOne (bouton, ou tout seul après quelques secondes). `medal` : payload
-- WorldCleared du monde 7 (sa médaille est montrée dans le rapport, pas en carte).
------------------------------------------------------------------------------------
-- Test de perf (fin d'ascension) : l'hexagone de la vraie app — mascotte au centre, quatre petits
-- hexagones (Processeur, Carte graphique, Mémoire, Stockage), score global, emblème, et le pseudo
-- du joueur en néon. Puis le rapport.
------------------------------------------------------------------------------------

local PERF_AUTO_NEXT = 12 -- s avant de passer au rapport tout seul

-- Contour d'hexagone (6 arêtes) centré en (cx, cy) px dans `parent`, rayon `radius` (sommets en haut/bas).
local function hexOutline(parent: Instance, cx: number, cy: number, radius: number, thickness: number, color: Color3)
	local apothem = radius * math.sqrt(3) / 2
	for k = 0, 5 do
		local angle = math.rad(k * 60) -- normale de l'arête (sommets à ±30° de la verticale)
		New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx + apothem * math.sin(angle), cy - apothem * math.cos(angle)),
			Size = UDim2.fromOffset(radius + thickness, thickness),
			Rotation = k * 60,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = parent,
		})
	end
end

-- Petit hexagone de score : contour, nombre, libellé et détail dessous.
local function scoreHex(parent: Instance, cx: number, cy: number, axis: PerfTest.Axis, accent: Color3)
	local radius = 58
	local fill: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(radius * 1.7, radius * 1.7),
		BackgroundColor3 = A.Card,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Create.Corner(radius) :: Instance })
	hexOutline(parent, cx, cy, radius, 3, accent)
	local good = axis.Score >= 75
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy - 6),
		Size = UDim2.fromOffset(radius * 1.5, 40),
		BackgroundTransparency = 1,
		Text = tostring(axis.Score),
		TextSize = 34,
		FontFace = F.Heavy,
		TextColor3 = if good then A.Good elseif axis.Score >= 50 then A.Text else A.Warn,
		Parent = parent,
	})
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy + 22),
		Size = UDim2.fromOffset(radius * 1.6, 18),
		BackgroundTransparency = 1,
		Text = "/100",
		TextSize = 18,
		FontFace = F.Medium,
		TextColor3 = A.Dim,
		Parent = parent,
	})
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(cx, cy + radius + 8),
		Size = UDim2.fromOffset(170, 22),
		BackgroundTransparency = 1,
		Text = axis.Label,
		TextSize = 18,
		FontFace = F.Bold,
		TextColor3 = A.Text,
		Parent = parent,
	})
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(cx, cy + radius + 30),
		Size = UDim2.fromOffset(190, 18),
		BackgroundTransparency = 1,
		Text = axis.Detail,
		TextSize = 18,
		FontFace = F.Medium,
		TextColor3 = A.Dim,
		Parent = parent,
	})
	return fill
end

local function showPerfTest(payload: any, medal: any?, onDone: () -> ())
	local result = PerfTest.Build({
		Time = if type(payload.Time) == "number" then payload.Time else nil,
		Deaths = if type(payload.Deaths) == "number" then payload.Deaths else nil,
		Coins = if type(payload.Coins) == "number" then payload.Coins else nil,
		CoinsTotal = if type(payload.CoinsTotal) == "number" then payload.CoinsTotal else nil,
		Keys = if type(payload.Keys) == "number" then payload.Keys else nil,
		KeysTotal = if type(payload.KeysTotal) == "number" then payload.KeysTotal else nil,
	})
	local accent = Color3.fromHex(Branding.PartnerApp.Accent)
	local screen: Frame = fullscreen("PerfTest", "Backdrop", 1)
	Motion.Tween(screen, { BackgroundTransparency = 0.35 }, 0.4)
	local window = appWindow(screen, Vector2.new(1180, 600), 260, {}, "Test de perf")
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		window.Root.Visible = false
		fadeOut(screen, 0.3)
		onDone()
	end
	window.Close.Activated:Connect(function()
		click()
		finish()
	end)

	-- Barre latérale : emblème, score global, puis la médaille du dernier monde
	local side = window.Side
	local emblemCard = card(side, UDim2.fromOffset(10, 72), UDim2.new(1, -20, 0, 206), A.Card)
	text(emblemCard, "Ton emblème", 20, F.Bold, A.Text, { Position = UDim2.fromOffset(16, 12) })
	text(emblemCard, result.Emblem, 34, F.Heavy, accent, { Position = UDim2.fromOffset(16, 44) })
	text(emblemCard, `{result.Score} / 100`, 26, F.Heavy, A.Text, { Position = UDim2.fromOffset(16, 92) })
	text(emblemCard, result.EmblemHint, 18, F.Medium, A.Dim, {
		Position = UDim2.fromOffset(16, 132),
		Size = UDim2.new(1, -32, 0, 64),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	if medal then
		medalBox(side, medal, 290)
	end

	-- Page : titre, hexagones
	local main = window.Main
	pageHeader(main, "Test de perf", "Ton PC vu de l'intérieur : score de l'ascension, comme dans l'app.", 28)
	local mainWidth = 1180 - 260
	local cx, cy = mainWidth / 2, 300
	local big = 118
	New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(big * 1.75, big * 1.75),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = main,
	}, { Create.Corner(big) :: Instance })
	hexOutline(main, cx, cy, big, 4, accent)
	local avatar = Widgets.Avatar(120, main)
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.Position = UDim2.fromOffset(cx, cy - 14)
	-- Pseudo en néon (couleur d'accent, contour), comme le Test de perf de l'app
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy + 72),
		Size = UDim2.fromOffset(big * 1.9, 32),
		BackgroundTransparency = 1,
		Text = Players.LocalPlayer.DisplayName,
		TextSize = 26,
		FontFace = F.Heavy,
		TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.35),
		TextStrokeColor3 = accent,
		TextStrokeTransparency = 0,
		TextScaled = true,
		Parent = main,
	})
	local spots = {
		{ cx - 300, cy - 110 },
		{ cx + 300, cy - 110 },
		{ cx - 300, cy + 90 },
		{ cx + 300, cy + 90 },
	}
	for index, axis in result.Axes do
		local spot = spots[index]
		local fill = scoreHex(main, spot[1], spot[2], axis, accent)
		Motion.Pop(fill, 0.1 + index * 0.08)
	end
	-- Conseil « vraie vie » de la fin (Tower.VictoryTip)
	local tip = Tower.VictoryTip
	if tip then
		text(main, `💡 {tip.Tip}  ·  {tip.AppTip}`, 18, F.Medium, A.Dim, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 24, 1, -92),
			Size = UDim2.new(1, -48, 0, 44),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Bottom,
		})
	end
	Keycap.new({
		Text = "VOIR MON RAPPORT",
		Variant = "Primary",
		Size = UDim2.fromOffset(340, TOUCH),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		OnClick = finish,
		Parent = main,
	})
	task.delay(PERF_AUTO_NEXT, finish)
end

function Moments.Victory(payload: any, medal: any?)
	-- L'écran final passe devant tout : plus de bannière ni de carte en attente.
	Moments.ClearQueue()
	MedalCard.Dismiss()
	local displayName = Players.LocalPlayer.DisplayName
	local data = if type(payload) == "table" then payload else {}
	local screen = fullscreen("Victory", "Backdrop", 1)
	Motion.Tween(screen, { BackgroundTransparency = 0.25 }, 0.6)
	local liveCard: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(760, 440),
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = screen,
	})
	Material.Glass(liveCard, true)
	Material.RgbEdge(liveCard, 2.5, 0.05, 80)
	local avatar = Widgets.Avatar(96, liveCard)
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.new(0.5, 0, 0, -48)

	-- Pastille « EN DIRECT » (point qui clignote) et performances du PC
	local live: Frame = New("Frame", {
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.fromOffset(170, 34),
		BorderSizePixel = 0,
		Tag = { "FillBrand", "RoundPill" },
		Parent = liveCard,
	})
	local blinkDot: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BorderSizePixel = 0,
		Tag = { "FillWhite", "RoundPill" },
		Parent = live,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -44, 1, 0),
		BackgroundTransparency = 1,
		Text = "EN DIRECT",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextKey",
		Parent = live,
	})
	local after = PcHealth.Stats(Tower.WORLD_COUNT)
	New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 16),
		Size = UDim2.fromOffset(220, 34),
		BackgroundTransparency = 1,
		Text = `{Branding.ChannelName} · {after.Fps} FPS · {after.Ping} ms`,
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "DynHeading",
		TextColor3 = Style.Color("Success"),
		Parent = liveCard,
	})

	-- Colonne de gauche : le moment
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 64),
		Size = UDim2.fromOffset(452, 44),
		BackgroundTransparency = 1,
		Text = "LE LIVE COMMENCE !",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "FontDisplay",
		TextColor3 = Style.Color("CurrencyBits"),
		Parent = liveCard,
	}, { New("UITextSizeConstraint", { MaxTextSize = 34 }) :: Instance })
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 112),
		Size = UDim2.fromOffset(452, 26),
		BackgroundTransparency = 1,
		Text = `LAGZ est vaincu : le PC tourne à {after.Fps} FPS !`,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = liveCard,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 150),
		Size = UDim2.fromOffset(452, 120),
		BackgroundTransparency = 1,
		Text = `{Branding.MascotName} : « Merci {displayName} ! Grâce à toi, mon PC revit et le live peut commencer. Tu es le héros du jour ! »`,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Tag = "TextHeading",
		Parent = liveCard,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 286),
		Size = UDim2.fromOffset(452, 26),
		BackgroundTransparency = 1,
		Text = `+{NumberFormat.Compact(data.Bits or 0)} Bits  ·  Victoires : {data.Wins or 1}`,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "DynHeading",
		TextColor3 = Style.Color("CurrencyBits"),
		Parent = liveCard,
	})

	-- Colonne de droite : le chat du live qui défile
	local chat: Frame = New("Frame", {
		Position = UDim2.fromOffset(496, 64),
		Size = UDim2.fromOffset(240, 256),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Tag = { "GlassSunken", "RoundM" },
		Parent = liveCard,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 20),
		BackgroundTransparency = 1,
		Text = "CHAT EN DIRECT",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = chat,
	})
	local feed: Frame = New("Frame", {
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -24, 1, -38),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = chat,
	}, {
		Create.List(Enum.FillDirection.Vertical, 4, { VerticalAlignment = Enum.VerticalAlignment.Bottom }) :: Instance,
	})
	local order = 0
	local function post()
		order += 1
		local message = LIVE_CHAT[(order - 1) % #LIVE_CHAT + 1]
		local color = CHAT_COLORS[order % #CHAT_COLORS + 1]
		local body = string.gsub(message.Text, "{name}", escapeRich(displayName))
		local line: TextLabel = New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			RichText = true,
			Text = `<font color="#{color}"><b>{message.Name}</b></font> {body}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = order,
			Tag = "TextHeading",
			Parent = feed,
		})
		Motion.Pop(line, 0.08)
		-- On garde les 8 derniers messages.
		local lines: { TextLabel } = {}
		for _, child in feed:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(lines, child)
			end
		end
		table.sort(lines, function(a: TextLabel, b: TextLabel): boolean
			return a.LayoutOrder < b.LayoutOrder
		end)
		for index = 1, #lines - 8 do
			lines[index]:Destroy()
		end
	end
	task.spawn(function()
		local blink = false
		while screen.Parent do
			post()
			blink = not blink
			blinkDot.BackgroundTransparency = if blink or Motion.IsReduced() then 0 else 0.6
			task.wait(0.7)
		end
	end)

	local opened = false
	local function openReport()
		if opened then
			return
		end
		opened = true
		liveCard.Visible = false
		fadeOut(screen, 0.4)
		-- Test de perf (hexagone de l'app), puis le rapport d'optimisation
		showPerfTest(data, medal, function()
			showReport(data, medal)
		end)
	end
	Keycap.new({
		Text = "VOIR MON RAPPORT",
		Variant = "Primary",
		Size = UDim2.fromOffset(380, TOUCH),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		OnClick = openReport,
		Parent = liveCard,
	})
	Motion.Pop(liveCard, 0.2)
	task.delay(9, openReport)
end

function Moments.Mount(target: Frame)
	layer = target
end

return Moments
