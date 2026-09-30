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
	  supprimées, temps, record, clés USB, chutes) à capturer et partager (Util/OptimisationReport)
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

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Lagz = require(script.Parent.Parent.Components.Lagz)
local Toasts = require(script.Parent.Toasts)

local New = Create.New

local Moments = {}

local layer: Frame

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
		TextSize = 15,
		FontFace = F.Medium,
		TextColor3 = A.Text,
		Parent = parent,
	}, {
		Create.Corner(6) :: Instance,
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
		Size = UDim2.fromOffset(0, 22),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		Create.Padding(0, 10) :: Instance,
	})
	text(frame, value, 12, F.Bold, textColor or A.Text, {
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
		Size = UDim2.new(1, 0, 0, titleSize + 30),
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
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = row,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		New("UIStroke", { Color = A.Dim, Thickness = 1.5 }) :: Instance,
	})
	text(help, "?", 12, F.Bold, A.Dim, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	text(header, subtitle, 14, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(0, titleSize + 8),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return header
end

-- Fenêtre de l'app : barre de titre, barre latérale (avatar, badge, recherche, pages), contenu.
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
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = A.Accent,
		BorderSizePixel = 0,
		Parent = root,
	}, { Create.Corner(4) :: Instance })
	text(logo, "A", 11, F.Heavy, A.Text, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	text(root, `{APP.Name}  ·  {APP.Version}`, 12, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(36, 7),
		Size = UDim2.fromOffset(300, 18),
	})
	New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -118, 0, 16),
		Size = UDim2.fromOffset(10, 1),
		BackgroundColor3 = A.Dim,
		BorderSizePixel = 0,
		Parent = root,
	})
	New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -72, 0, 11),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		Parent = root,
	}, { New("UIStroke", { Color = A.Dim, Thickness = 1 }) :: Instance })
	local close: TextButton = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -1, 0, 1),
		Size = UDim2.fromOffset(48, 30),
		BackgroundColor3 = Color3.fromRGB(196, 43, 28),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "✕",
		TextSize = 14,
		FontFace = F.Medium,
		TextColor3 = A.Text,
		Parent = root,
	}, { Create.Corner(7) :: Instance })
	close.MouseEnter:Connect(function()
		close.BackgroundTransparency = 0
	end)
	close.MouseLeave:Connect(function()
		close.BackgroundTransparency = 1
	end)

	-- Barre latérale
	local side: Frame = New("Frame", {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(0, sideWidth, 1, -32),
		BackgroundTransparency = 1,
		Parent = root,
	})
	headshot(side, 40, UDim2.fromOffset(14, 6))
	text(side, player.DisplayName, 15, F.Bold, A.Text, {
		Position = UDim2.fromOffset(64, 5),
		Size = UDim2.new(1, -72, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	text(side, Technician.Short(player.UserId), 12, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(64, 26),
		Size = UDim2.new(1, -72, 0, 16),
	})
	local search = card(side, UDim2.fromOffset(10, 56), UDim2.new(1, -20, 0, 32), A.Card)
	New("UIStroke", { Color = A.Stroke, Parent = search })
	text(search, "Rechercher une page ou un paramètre", 13, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -36, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, -1),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		Parent = search,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		New("UIStroke", { Color = A.Dim, Thickness = 1.5 }) :: Instance,
	})
	for i, name in pages do
		local row: Frame = New("Frame", {
			Position = UDim2.fromOffset(6, 98 + (i - 1) * 32),
			Size = UDim2.new(1, -12, 0, 30),
			BackgroundColor3 = A.CardHi,
			BackgroundTransparency = if name == selected then 0 else 1,
			BorderSizePixel = 0,
			Parent = side,
		}, { Create.Corner(4) :: Instance })
		if name == selected then
			New("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(3, 16),
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
		text(row, name, 14, if name == selected then F.Medium else F.Regular, A.Text, {
			Position = UDim2.fromOffset(38, 0),
			Size = UDim2.new(1, -44, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local main: Frame = New("Frame", {
		Position = UDim2.fromOffset(sideWidth, 32),
		Size = UDim2.new(1, -sideWidth, 1, -32),
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
	dot(tile, UDim2.fromOffset(14, 16), 10, color)
	text(tile, caption, 14, F.Medium, A.Dim, { Position = UDim2.fromOffset(32, 9), Size = UDim2.new(1, -40, 0, 22) })
	local big = text(tile, value, 44, F.Heavy, color, {
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -20, 0, 56),
	})
	Motion.Pop(big, 0.2)
end

local function introStep(body: Frame, step: number, onNext: () -> (), onAccept: (TextButton) -> ())
	local player = Players.LocalPlayer
	if step == 1 then
		local before = PcHealth.Stats(0)
		statTile(body, UDim2.fromOffset(0, 8), tostring(before.Fps), "FPS", A.Bad)
		statTile(body, UDim2.fromOffset(180, 8), `{before.Ping} ms`, "Ping", A.Bad)
		statTile(body, UDim2.fromOffset(360, 8), `{before.Temp} °C`, "Température", A.Bad)
		local avatar = Widgets.Avatar(64, body)
		avatar.Position = UDim2.fromOffset(0, 146)
		text(body, `{Branding.MascotName} : « Mon PC RAME ! Mon live commence dans 1 heure ! »`, 18, F.Bold, A.Text, {
			Position = UDim2.fromOffset(78, 150),
			Size = UDim2.new(1, -300, 0, 56),
			TextWrapped = true,
		})
		appButton(body, "SUITE  →", true, UDim2.new(1, -200, 1, -52), UDim2.fromOffset(200, 48), onNext)
	elseif step == 2 then
		local face = Lagz.Face(150, body)
		face.Position = UDim2.fromOffset(0, 0)
		Motion.Pop(face, 0.3)
		text(
			body,
			"LAGZ",
			34,
			F.Heavy,
			Lagz.Color,
			{ Position = UDim2.fromOffset(170, 6), Size = UDim2.new(1, -170, 0, 40) }
		)
		text(body, "Un virus qui MANGE la puissance du PC.", 18, F.Bold, A.Text, {
			Position = UDim2.fromOffset(170, 50),
			Size = UDim2.new(1, -170, 0, 24),
		})
		text(body, "Ses 6 sbires se cachent dans la tour :", 14, F.Regular, A.Dim, {
			Position = UDim2.fromOffset(170, 86),
			Size = UDim2.new(1, -170, 0, 20),
		})
		local chips: Frame = New("Frame", {
			Position = UDim2.fromOffset(170, 112),
			Size = UDim2.new(1, -170, 0, 60),
			BackgroundTransparency = 1,
			Parent = body,
		}, {
			New("UIGridLayout", {
				CellSize = UDim2.fromOffset(110, 26),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}) :: Instance,
		})
		for i, name in MINIONS do
			local def = Tower.Worlds[i]
			local chip = card(chips, UDim2.new(), UDim2.new(), A.CardHi)
			chip.LayoutOrder = i
			dot(chip, UDim2.fromOffset(10, 8), 10, if def then Color3.fromHex(def.Primary) else A.Violet)
			text(
				chip,
				name,
				13,
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
		appButton(body, "SUITE  →", true, UDim2.new(1, -200, 1, -52), UDim2.fromOffset(200, 48), onNext)
	else
		-- Badge du technicien (à gauche) + ordre de mission (à droite)
		local badge = card(body, UDim2.fromOffset(0, 0), UDim2.fromOffset(250, 176), A.Accent)
		New("UIGradient", {
			Rotation = 35,
			Color = ColorSequence.new(A.Accent, A.Violet),
			Parent = badge,
		})
		text(badge, "BADGE OFFICIEL", 11, F.Heavy, WHITE, {
			Position = UDim2.fromOffset(16, 12),
			TextTransparency = 0.25,
		})
		headshot(badge, 56, UDim2.fromOffset(16, 38))
		text(badge, player.DisplayName, 18, F.Heavy, WHITE, {
			Position = UDim2.fromOffset(82, 42),
			Size = UDim2.new(1, -92, 0, 24),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(badge, "Technicien·ne AngAInOne", 13, F.Medium, WHITE, {
			Position = UDim2.fromOffset(82, 68),
			Size = UDim2.new(1, -92, 0, 18),
		})
		text(badge, `n° {Technician.Code(player.UserId)}`, 40, F.Heavy, WHITE, {
			Position = UDim2.fromOffset(16, 110),
			Size = UDim2.new(1, -32, 0, 48),
		})
		Motion.Pop(badge, 0.12)
		local orders = {
			"Entre dans la tour du PC.",
			`Nettoie les {Tower.WORLD_COUNT} mondes.`,
			"Supprime LAGZ, tout en haut !",
		}
		for i, line in orders do
			local y = 6 + (i - 1) * 50
			local number = dot(body, UDim2.fromOffset(272, y), 36, A.CardHi)
			text(number, tostring(i), 18, F.Heavy, A.Text, {
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			text(
				body,
				line,
				20,
				F.Bold,
				A.Text,
				{ Position = UDim2.fromOffset(322, y + 4), Size = UDim2.new(1, -322, 0, 28) }
			)
		end
		local accept: TextButton
		accept = appButton(
			body,
			"ACCEPTER LA MISSION",
			true,
			UDim2.new(1, -330, 1, -58),
			UDim2.fromOffset(330, 58),
			function()
				onAccept(accept)
			end
		)
		accept.TextSize = 20
		accept.FontFace = F.Heavy
		Motion.Pop(accept, 0.1)
	end
end

function Moments.Intro(onDone: () -> ())
	local dim = fullscreen("Intro", "Backdrop", 0.3)
	local pages = AppPages.Sidebar(Tower.Worlds)
	table.insert(pages, 2, "Mode Intervention")
	local window = appWindow(dim, Vector2.new(1000, 560), 220, pages, "Mode Intervention")
	window.Close.Visible = false -- la mission se lance avec le gros bouton
	local main = window.Main
	pageHeader(main, "Mode Intervention", "Une réparation en direct… depuis l'intérieur du PC.", 28).Position =
		UDim2.fromOffset(0, 12)
	local status = pill(main, "PC d'Anga : critique", A.Bad:Lerp(Color3.new(0, 0, 0), 0.55), A.Bad)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, 0, 0, 20)

	local steps: Frame = New("Frame", {
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 1, -100),
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
			local box = card(steps, UDim2.new(), UDim2.new(1, 0, 0, if open then 318 else 50), A.Card)
			box.LayoutOrder = i
			local number = dot(
				box,
				UDim2.fromOffset(14, 12),
				26,
				if i < current then A.Good elseif open then A.Accent else A.CardHi
			)
			text(number, if i < current then "✓" else tostring(i), 14, F.Heavy, A.Text, {
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			text(
				box,
				`Étape {i} — {step.Title}`,
				15,
				F.Medium,
				A.Text,
				{ Position = UDim2.fromOffset(52, 6), Size = UDim2.new(1, -200, 0, 20) }
			)
			text(
				box,
				step.Sub,
				12,
				F.Regular,
				A.Dim,
				{ Position = UDim2.fromOffset(52, 26), Size = UDim2.new(1, -200, 0, 16) }
			)
			local badge = pill(
				box,
				if i < current then "Terminé ✓" elseif open then "En cours" else "À venir",
				if i < current then A.Good:Lerp(Color3.new(0, 0, 0), 0.6) else A.CardHi,
				if i < current then A.Good else A.Dim
			)
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, -14, 0, 14)
			if open then
				local body: Frame = New("Frame", {
					Position = UDim2.fromOffset(20, 58),
					Size = UDim2.new(1, -40, 1, -72),
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
-- Bannières
------------------------------------------------------------------------------------

local function banner(accent: Color3, caption: string, title: string, subtitle: string, seconds: number)
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
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = caption,
		Tag = "TextCaption",
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
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = subtitle,
		Tag = "TextBody",
		Parent = band,
	})
	Motion.Pop(titleLabel, 0.25)
	Motion.Tween(sweep, { Size = UDim2.new(1, 0, 0, 3) }, 0.9, Enum.EasingStyle.Quart)
	task.delay(seconds, function()
		if band.Parent then
			fadeOut(band, 0.4)
		end
	end)
end

-- En entrant dans un monde : l'en-tête de la page de l'app qui lui correspond.
function Moments.WorldBanner(world: number)
	local def = Tower.Worlds[world]
	if not def then
		return
	end
	local page = AppPages.Of(world, def)
	local accent = Color3.fromHex(def.Primary)
	local header: Frame = New("Frame", {
		Name = "AppPageBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.2, 0),
		Size = UDim2.fromOffset(660, 118),
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
	text(content, `{APP.Name}  ›  Monde {world}/{Tower.WORLD_COUNT} · {def.Component}`, 12, F.Medium, A.Dim, {
		Size = UDim2.new(1, -180, 0, 18),
	})
	pageHeader(content, page.Title, page.Subtitle, 30).Position = UDim2.fromOffset(0, 22)
	local alert = pill(content, `⚠ {def.Minion} détecté`, A.Bad:Lerp(Color3.new(0, 0, 0), 0.55), A.Bad)
	alert.AnchorPoint = Vector2.new(1, 0)
	alert.Position = UDim2.new(1, 0, 0, 0)
	Motion.Pop(header, 0.08)
	task.delay(4.5, function()
		if header.Parent then
			Motion.Tween(header, { Position = UDim2.new(0.5, 0, 0.2, -20), BackgroundTransparency = 1 }, 0.35)
			fadeOut(header, 0.35)
		end
	end)
end

function Moments.WorldCleared(world: number, bits: number)
	local def = Tower.Worlds[world]
	local caption = if world < Tower.WORLD_COUNT then "LE PORTAIL EST OUVERT !" else "LE CŒUR DU VIRUS EST DÉTRUIT !"
	banner(
		Style.Color("Success"),
		caption,
		"VIRUS ÉLIMINÉS !",
		`{if def then def.Name else ""} est propre · +{NumberFormat.Compact(bits)} Bits`,
		4
	)
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

local function reportCard(parent: Instance, index: number, data: OptimisationReport.Card): TextLabel?
	local width = 168
	local box = card(parent, UDim2.fromOffset((index - 1) * (width + 10), 0), UDim2.fromOffset(width, 94), A.Card)
	text(box, data.Title, 14, F.Bold, A.Text, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -20, 0, 18) })
	if index == 1 then
		-- Score : gros chiffre animé de 48 à 100
		local score = text(box, tostring(OptimisationReport.START_SCORE), 38, F.Heavy, A.Text, {
			Position = UDim2.fromOffset(14, 32),
			Size = UDim2.fromOffset(78, 46),
		})
		text(
			box,
			"/100",
			13,
			F.Regular,
			A.Dim,
			{ Position = UDim2.fromOffset(92, 54), Size = UDim2.fromOffset(60, 18) }
		)
		return score
	end
	dot(box, UDim2.fromOffset(14, 38), 8, if data.Good then A.Good else A.Bad)
	text(
		box,
		`{data.Score} / 100`,
		14,
		F.Medium,
		A.Text,
		{ Position = UDim2.fromOffset(28, 32), Size = UDim2.new(1, -34, 0, 20) }
	)
	text(box, data.Detail, 12, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(14, 54),
		Size = UDim2.new(1, -22, 0, 34),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	return nil
end

local function reportEntry(parent: Instance, entry: OptimisationReport.Entry)
	local box = card(parent, UDim2.new(), UDim2.new(1, -10, 0, 104), A.Card)
	box.LayoutOrder = entry.World
	local def = Tower.Worlds[entry.World]
	local badge = dot(box, UDim2.fromOffset(14, 14), 28, A.Good:Lerp(Color3.new(0, 0, 0), 0.6))
	text(
		badge,
		"✓",
		15,
		F.Heavy,
		A.Good,
		{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }
	)
	text(box, entry.Title, 15, F.Medium, A.Text, {
		Position = UDim2.fromOffset(56, 10),
		Size = UDim2.new(1, -220, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if def then
		dot(box, UDim2.fromOffset(56, 36), 6, Color3.fromHex(def.Primary))
	end
	for i, row in { { "Constat", entry.Constat }, { "Pourquoi", entry.Pourquoi }, { "Quoi faire", entry.QuoiFaire } } do
		local y = 30 + (i - 1) * 22
		text(box, row[1], 12, F.Bold, A.Dim, { Position = UDim2.fromOffset(66, y), Size = UDim2.fromOffset(80, 18) })
		text(box, row[2], 13, if i == 3 then F.Medium else F.Regular, if i == 3 then A.Text else A.Dim, {
			Position = UDim2.fromOffset(150, y),
			Size = UDim2.new(1, -170, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local done = pill(box, entry.Action, A.Accent)
	done.AnchorPoint = Vector2.new(1, 0)
	done.Position = UDim2.new(1, -14, 0, 12)
end

local function showReport(payload: any)
	local report = OptimisationReport.Build({
		Time = if type(payload.Time) == "number" then payload.Time else 0,
		Record = payload.Record == true,
		Assisted = payload.Assisted == true,
		Keys = if type(payload.Keys) == "number" then payload.Keys else nil,
		KeysTotal = if type(payload.KeysTotal) == "number" then payload.KeysTotal else nil,
		Deaths = if type(payload.Deaths) == "number" then payload.Deaths else nil,
	})
	local dateText = OptimisationReport.DateText(os.date("*t") :: any)

	local screen = fullscreen("Report", "Backdrop", 1)
	Motion.Tween(screen, { BackgroundTransparency = 0.35 }, 0.4)
	local pages = AppPages.Sidebar(Tower.Worlds)
	local window = appWindow(screen, Vector2.new(1180, 600), 236, pages, "Diagnostic")
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

	-- Barre latérale, en bas : « Ta mission » (temps, record, clés USB, chutes, badge)
	local side = window.Side
	local mission = card(side, UDim2.new(0, 10, 1, -176), UDim2.new(1, -20, 0, 166), A.Card)
	text(
		mission,
		"Ta mission",
		14,
		F.Bold,
		A.Text,
		{ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18) }
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
		local y = 30 + (i - 1) * 21
		if row[1] == "" then
			text(mission, row[2], 13, F.Heavy, Style.Color("CurrencyBits"), {
				Position = UDim2.fromOffset(12, y),
				Size = UDim2.new(1, -24, 0, 18),
			})
		else
			text(
				mission,
				row[1],
				13,
				F.Regular,
				A.Dim,
				{ Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 18) }
			)
			text(mission, row[2], 14, F.Bold, A.Text, {
				Position = UDim2.fromOffset(12, y),
				Size = UDim2.new(1, -24, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Right,
			})
		end
	end
	local technicianBadge = pill(mission, "✓ Badge Technicien·ne", A.Accent)
	technicianBadge.Position = UDim2.new(0, 12, 1, -32)

	-- Contenu : en-tête, partage, verdict, chiffres, cartes, menaces supprimées
	local main = window.Main
	pageHeader(main, "Diagnostic", "Ce qui va, ce qui cloche, et quoi faire — en un lien à partager.", 28).Position =
		UDim2.fromOffset(0, 10)
	appButton(main, "Copier en Markdown", true, UDim2.new(1, -318, 0, 14), UDim2.fromOffset(170, 32), function()
		Toasts.Show("Info", "Rapport prêt ! Fais une capture d'écran pour le partager 📸")
	end)
	appButton(main, "Mettre en ligne", true, UDim2.new(1, -138, 0, 14), UDim2.fromOffset(138, 32), function()
		Toasts.Show("Success", "Montre ton rapport à tes amis : capture d'écran ! 📸")
	end)
	text(main, "📸 Partager : fais une capture de ton rapport !", 12, F.Medium, A.Violet, {
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local verdictIcon = dot(main, UDim2.fromOffset(0, 80), 18, A.Surface)
	New("UIStroke", { Color = A.Good, Thickness = 2, Parent = verdictIcon })
	text(main, "Verdict", 14, F.Bold, A.Text, { Position = UDim2.fromOffset(28, 74), Size = UDim2.new(1, -28, 0, 18) })
	text(main, OptimisationReport.Verdict(dateText), 12, F.Regular, A.Dim, {
		Position = UDim2.fromOffset(28, 92),
		Size = UDim2.new(1, -28, 0, 16),
	})
	text(
		main,
		report.Headline,
		22,
		F.Bold,
		A.Text,
		{ Position = UDim2.fromOffset(0, 116), Size = UDim2.new(1, 0, 0, 28) }
	)
	text(
		main,
		`Optimisation terminée · {report.Threats} menaces supprimées · {report.Summary}`,
		13,
		F.Regular,
		A.Dim,
		{
			Position = UDim2.fromOffset(0, 146),
			Size = UDim2.new(1, 0, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}
	)
	-- Avant -> après, en GROS
	for i, delta in report.Deltas do
		local box = card(main, UDim2.fromOffset((i - 1) * 298, 172), UDim2.fromOffset(288, 54), A.Card)
		text(
			box,
			delta.Label,
			13,
			F.Medium,
			A.Dim,
			{ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 100, 1, 0) }
		)
		local value = text(box, "", 28, F.Heavy, A.Text, {
			Position = UDim2.fromOffset(110, 0),
			Size = UDim2.new(1, -124, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			RichText = true,
		})
		local bad = A.Bad:ToHex()
		local good = A.Good:ToHex()
		Motion.CountTo(value, delta.From, delta.To, function(n: number): string
			return `<font color="#{bad}" size="18">{delta.From}</font> → <font color="#{good}">{math.floor(n + 0.5)}{delta.Unit}</font>`
		end, 1.6)
	end
	-- Les 5 cartes du diagnostic
	local cardsRow: Frame = New("Frame", {
		Position = UDim2.fromOffset(0, 236),
		Size = UDim2.new(1, 0, 0, 94),
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
	-- « Ce qu'il faut regarder » : une entrée par menace supprimée
	text(
		main,
		"Ce qu'il faut regarder",
		14,
		F.Bold,
		A.Text,
		{ Position = UDim2.fromOffset(0, 338), Size = UDim2.new(1, 0, 0, 18) }
	)
	local list: ScrollingFrame = New("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 362),
		Size = UDim2.new(1, 0, 1, -374),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
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
	task.delay(120, close)
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
-- Rapport AngAInOne (bouton, ou tout seul après quelques secondes).
function Moments.Victory(payload: any)
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
		Tag = "TextBody",
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
		Size = UDim2.fromOffset(240, 280),
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
		Tag = "TextCaption",
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
			Tag = "TextBody",
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
		showReport(data)
	end
	Keycap.new({
		Text = "VOIR MON RAPPORT",
		Variant = "Primary",
		Size = UDim2.fromOffset(360, 56),
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
