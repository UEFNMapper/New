--!strict
--[[
	MinigamePanel : hôte des mini-jeux 2D antivirus (terminal de fin de monde, borne d'arcade).

	Déroulé d'une partie :
		voile sombre + flou
		-> carte d'intro : le sbire du monde qui nargue, titre, règle illustrée, objectif,
		   gros bouton JOUER (+ Quitter)
		-> compte à rebours 3-2-1
		-> partie (HUD : chrono, progression vers l'objectif, vies, bouton X)
		-> bandeau "BRAVO !" / "OH NON !"
		-> carte de résultat : réussite (sbire K.O., confettis, CONTINUER) ou échec (le sbire
		   ricane, RÉESSAYER / Quitter)
		-> onDone(success, score, duration)

	Sbire : Tower.Worlds[difficulté].Minion (1..7). Difficulté 8 = combat final contre LAGZ
	(Core.IsBoss) : LAGZ sur les cartes, écran qui glitche pendant la partie, victoire
	« LAGZ EST DÉTRUIT ! ». Le Firewall a sa vraie variante boss (FirewallLogic) ; les
	autres jeux se jouent alors avec les réglages du niveau 7.

	`duration` = secondes réellement jouées pendant la manche qui donne le résultat
	(compte à rebours et cartes exclus) : le serveur vérifie une durée minimale.
	Pendant la partie, le personnage est figé et les contrôles tactiles de Roblox cachés.

	API :
		MinigamePanel.Mount(layer)                         -- une fois (App.Layers.Overlays)
		MinigamePanel.Play(kind, difficulty, onDone, onRetry?) -- kind : Tower.MinigameKinds ; 1..7, 8 = boss
		                                                   -- onRetry : appelé à chaque RÉESSAYER (le serveur
		                                                   -- relance alors son chrono de validation)
		MinigamePanel.IsPlaying()
		MinigamePanel.Cancel()                             -- ferme : onDone(false, 0, elapsed)
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Tower = require(Shared.Config.Tower)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Icon = require(script.Parent.Parent.Components.Icon)
local Minigames = script.Parent.Parent.Minigames
local Core = require(Minigames.Core)
local Common = require(Minigames.Common)
local Minions = require(Minigames.Minions)
local AppPages = require(Shared.Util.AppPanelLogic)
local Fluent = require(script.Parent.Parent.Parent.Controllers.AppPanels.Fluent)

local New = Create.New
local C = Common.Colors
local FC = Fluent.C -- couleurs de l'app AngAInOne (carte d'intro)

local MinigamePanel = {}

export type OnDone = (success: boolean, score: number, duration: number) -> ()

local GAMES: { [string]: Common.Game } = {
	Scan = require(Minigames.Scan),
	Firewall = require(Minigames.Firewall),
	Memory = require(Minigames.Memory),
	Dodge = require(Minigames.Dodge),
	Popup = require(Minigames.Popup),
	Defrag = require(Minigames.Defrag),
}

local BACK_ACTION = "AngAInOneMinigameBack"
local HEADER_H = 60
local CARD_GUARD = 0.5 -- secondes pendant lesquelles une nouvelle carte ignore les appuis
local SUCCESS_AUTOCLOSE = 6
local MAX_HEART_ICONS = 5

type Phase = "Intro" | "Countdown" | "Playing" | "Ending" | "Result"

type Session = {
	Kind: string,
	Difficulty: number,
	Boss: boolean, -- combat final contre LAGZ (difficulté 8)
	Minion: string, -- sbire affiché sur les cartes
	Game: Common.Game,
	Info: Common.Info,
	OnDone: OnDone,
	OnRetry: (() -> ())?,
	Phase: Phase,
	Closed: boolean,
	Root: Frame,
	Dim: TextButton,
	Content: Frame,
	Field: Frame,
	Cards: Frame,
	Hud: Common.Hud,
	ResetHud: () -> (),
	HeaderQuit: GuiObject?, -- bouton X du HUD (caché une fois la manche terminée)
	Card: Frame?,
	CardReadyAt: number,
	Primary: (() -> ())?,
	Secondary: (() -> ())?,
	Cleanup: (() -> ())?,
	AttemptStart: number?,
	LastScore: number,
	LastDuration: number,
	Attempt: number, -- numéro de manche (arrête les effets d'une manche finie)
	Connections: { RBXScriptConnection },
}

-- Phase lue via une fonction : l'analyseur ne garde pas d'affinage périmé dans les
-- fonctions différées (la phase change entre-temps).
local function phaseOf(s: Session): Phase
	return s.Phase
end

local layer: Frame? = nil
local blur: BlurEffect? = nil
local session: Session? = nil

------------------------------------------------------------------------------------
-- Outils
------------------------------------------------------------------------------------

-- Fige (ou libère) le personnage et cache les contrôles tactiles de Roblox.
local function setCharacterControls(enabled: boolean)
	pcall(function()
		local player = Players.LocalPlayer
		local scripts = player and player:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if module and module:IsA("ModuleScript") then
			local controls = (require :: any)(module):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
	pcall(function()
		GuiService.TouchControlsEnabled = enabled
	end)
end

local function setBlur(on: boolean)
	local effect = blur
	if not effect then
		return
	end
	if on then
		effect.Enabled = true
		Motion.Tween(effect, { Size = 14 }, 0.3)
	else
		Motion.Tween(effect, { Size = 0 }, 0.25).Completed:Once(function()
			if not session then
				effect.Enabled = false
			end
		end)
	end
end

-- Keycap avec un gros texte (le style TextKey fait 16 px : trop petit pour un CTA d'enfant).
local function bigKeycap(props: Keycap.Props, textSize: number): Keycap.Keycap
	local key = Keycap.new(props)
	local label = key.Label
	local dark = props.Variant == "Gold" or props.Variant == "Success" or props.Variant == "Cyan"
	for _, tag in { "TextKey", "TextKeyDark", "TextKeySmall", "TextKeySmallDark" } do
		label:RemoveTag(tag)
	end
	label:AddTag("FontHeavy")
	label.TextSize = textSize
	label.TextColor3 = Style.Color(if dark then "BgDeep" else "TextPrimary")
	return key
end

-- Icône de progression : virus miniature ou icône du design system.
local function progressIcon(kind: string, size: number, colorName: string): Frame
	if kind == "Virus" then
		return Common.Virus({ Size = UDim2.fromOffset(size, size), Calm = true })
	end
	local icon = Icon.new(kind, size, colorName)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	return icon
end

-- Petite horloge (anneau + aiguilles) pour le chrono.
local function clockGlyph(size: number, color: Color3): Frame
	local root: Frame = New("Frame", {
		Name = "Clock",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	})
	local ring = Common.Shape(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.84, 0.84), color, UDim.new(1, 0), {
		BackgroundTransparency = 1,
	})
	New("UIStroke", { Color = color, Thickness = 3, Parent = ring })
	New("Frame", {
		Name = "Hour",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.1, 0.28),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = root,
	}, { Common.Corner() })
	New("Frame", {
		Name = "Minute",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.46, 0.5),
		Size = UDim2.fromScale(0.3, 0.1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = root,
	}, { Common.Corner() })
	return root
end

local function label(props: { [string]: any }): TextLabel
	local text: TextLabel = New("TextLabel", {
		BackgroundTransparency = 1,
		TextWrapped = true,
	})
	for key, value in props do
		if key == "Tag" then
			text:AddTag(value)
		elseif key ~= "Parent" then
			(text :: any)[key] = value
		end
	end
	text.Parent = props.Parent
	return text
end

------------------------------------------------------------------------------------
-- HUD de partie (en haut de l'écran)
------------------------------------------------------------------------------------

local function buildHud(s: Session, parent: Frame): (Common.Hud, () -> ())
	local info = s.Info
	local accent = Style.Color(info.Accent)
	local header: Frame = New("Frame", {
		Name = "Hud",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, HEADER_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = parent,
	})

	-- Gauche : plaque du jeu
	local plaque: Frame = New("Frame", {
		Name = "Plaque",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundPill" },
		Parent = header,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 10, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 18) }),
	})
	local badge: Frame = New("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = plaque,
	}, { Common.Corner() })
	local badgeIcon = Icon.new("Bolt", 26, "BgDeep")
	badgeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	badgeIcon.Position = UDim2.fromScale(0.5, 0.5)
	badgeIcon.Parent = badge
	label({
		Name = "Title",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		Text = info.Title,
		TextSize = 18,
		TextColor3 = C.White,
		Tag = "FontDisplay",
		LayoutOrder = 2,
		Parent = plaque,
	})

	-- Centre : progression vers l'objectif
	local progress: Frame = New("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(330, 52),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundPill" },
		Parent = header,
	})
	local icon = progressIcon(info.Icon, 38, info.Accent)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0, 30, 0.5, 0)
	icon.Parent = progress
	local bar = Widgets.Bar(UDim2.fromOffset(170, 16), accent, progress)
	bar.Root.AnchorPoint = Vector2.new(0, 0.5)
	bar.Root.Position = UDim2.new(0, 58, 0.5, 0)
	local count = label({
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(80, 40),
		TextWrapped = false,
		Text = "0 / 0",
		TextSize = 24,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "FontHeavy",
		Parent = progress,
	})
	-- Combat final : la même pastille devient la barre de vie de LAGZ.
	local bossGroup: Frame = New("Frame", {
		Name = "Boss",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = progress,
	})
	local bossFace = Minions.Build("LAGZ", UDim2.fromOffset(44, 44), "Evil", bossGroup)
	bossFace.Position = UDim2.new(0, 30, 0.5, 0)
	local bossBar = Widgets.Bar(UDim2.fromOffset(190, 18), C.Bad, bossGroup)
	bossBar.Root.AnchorPoint = Vector2.new(0, 0.5)
	bossBar.Root.Position = UDim2.new(0, 58, 0.5, 0)
	local bossHp = label({
		Name = "Hp",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(64, 40),
		TextWrapped = false,
		Text = "",
		TextSize = 22,
		TextColor3 = C.Bad,
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "FontHeavy",
		Parent = bossGroup,
	})
	local normalParts: { GuiObject } = { icon, bar.Root, count }

	-- Droite : vies, chrono, quitter
	local right: Frame = New("Frame", {
		Name = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, 56),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = header,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 10, {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	local lives: Frame = New("Frame", {
		Name = "Lives",
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Visible = false,
		Tag = { "Glass", "RoundPill" },
		Parent = right,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 4, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		New("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
	})
	local timer: Frame = New("Frame", {
		Name = "Timer",
		Size = UDim2.fromOffset(112, 52),
		BackgroundTransparency = Theme.Alpha.Glass,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Visible = false,
		Tag = { "Glass", "RoundPill" },
		Parent = right,
	})
	local clock = clockGlyph(26, C.White)
	clock.AnchorPoint = Vector2.new(0, 0.5)
	clock.Position = UDim2.new(0, 14, 0.5, 0)
	clock.Parent = timer
	local seconds = label({
		Name = "Seconds",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(60, 40),
		TextWrapped = false,
		Text = "",
		TextSize = 28,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "FontHeavy",
		Parent = timer,
	})
	local quit = Keycap.new({
		Icon = "Close",
		IconOnly = true,
		Variant = "Ghost",
		Size = UDim2.fromOffset(56, 56),
		LayoutOrder = 3,
		Parent = right,
		OnClick = function()
			MinigamePanel.Cancel()
		end,
	})
	-- Pas de sélection manette : un A malencontreux ne doit pas quitter la partie
	-- (à la manette, on quitte avec B sur les cartes d'intro / de résultat).
	quit.Button.Selectable = false
	s.HeaderQuit = quit.Button

	-- État affiché (mis en cache : les jeux appellent le HUD à chaque image)
	local shownSeconds = -1
	local shownValue, shownTarget = -1, -1
	local shownLives: number? = nil
	local shownMax: number? = nil
	local shownBoss: number? = nil
	local hearts: { Frame } = {}
	local livesCount: TextLabel? = nil

	local function setHeart(heart: Frame, full: boolean)
		for _, part in heart:GetDescendants() do
			if part:IsA("Frame") then
				part.BackgroundTransparency = if full then 0 else 0.78
			end
		end
	end

	local hud: Common.Hud = {
		SetTimer = function(secondsLeft: number?)
			if secondsLeft == nil then
				timer.Visible = false
				shownSeconds = -1
				return
			end
			timer.Visible = true
			local display = Core.DisplaySeconds(secondsLeft)
			if display == shownSeconds then
				return
			end
			shownSeconds = display
			seconds.Text = tostring(display)
			local urgent = display <= 5 and phaseOf(s) == "Playing"
			seconds.TextColor3 = if urgent then C.Bad else C.White
			if urgent and display > 0 then
				Motion.Pop(timer, 0.18)
				Common.Sound("Click", 1.7)
			end
		end,
		SetProgress = function(value: number, target: number)
			if value == shownValue and target == shownTarget then
				return
			end
			local gained = value > shownValue and shownValue >= 0
			shownValue, shownTarget = value, target
			count.Text = `{value} / {target}`
			bar:Set(if target > 0 then value / target else 0)
			if gained then
				Motion.Pop(icon, 0.3)
				Motion.Pop(count, 0.2)
			end
		end,
		SetLives = function(value: number?, max: number?)
			if value == nil or max == nil or max <= 0 then
				lives.Visible = false
				shownLives, shownMax = nil, nil
				return
			end
			lives.Visible = true
			if max ~= shownMax then
				for _, child in lives:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				hearts = {}
				livesCount = nil
				local icons = if max <= MAX_HEART_ICONS then max else 1
				for i = 1, icons do
					local heart = Icon.new("Heart", 28, "Danger")
					heart.LayoutOrder = i
					heart.Parent = lives
					hearts[i] = heart
				end
				if max > MAX_HEART_ICONS then
					livesCount = label({
						Name = "Count",
						Size = UDim2.fromOffset(0, 40),
						AutomaticSize = Enum.AutomaticSize.X,
						TextWrapped = false,
						Text = "",
						TextSize = 24,
						TextColor3 = C.White,
						Tag = "FontHeavy",
						LayoutOrder = 99,
						Parent = lives,
					})
				end
				shownMax = max
				shownLives = nil
			end
			if value == shownLives then
				return
			end
			local lost = shownLives ~= nil and value < (shownLives :: number)
			shownLives = value
			local currentCount = livesCount
			if currentCount then
				currentCount.Text = `x{value}`
				setHeart(hearts[1], value > 0)
			else
				for i, heart in hearts do
					setHeart(heart, i <= value)
				end
			end
			if lost then
				Motion.Pop(lives, 0.25)
			end
		end,
		SetBoss = function(hp: number?, max: number?)
			local active = hp ~= nil and max ~= nil and max > 0
			bossGroup.Visible = active
			for _, part in normalParts do
				part.Visible = not active
			end
			if hp == nil or max == nil or max <= 0 then
				shownBoss = nil
				return
			end
			if hp == shownBoss then
				return
			end
			local hit = shownBoss ~= nil and hp < (shownBoss :: number)
			shownBoss = hp
			bossBar:Set(hp / max)
			bossHp.Text = `{math.max(0, hp)} PV`
			if hit then
				Motion.Pop(bossFace, 0.12)
			end
		end,
	}

	local function reset()
		shownValue, shownTarget = -1, -1
		hud.SetBoss(nil)
		hud.SetProgress(0, info.Goal)
		hud.SetTimer(nil)
		hud.SetLives(nil)
	end
	return hud, reset
end

------------------------------------------------------------------------------------
-- Cartes (intro / résultat)
------------------------------------------------------------------------------------

local function dismissCard(s: Session)
	local card = s.Card
	s.Card = nil
	s.Primary = nil
	s.Secondary = nil
	Common.Unfocus(s.Root)
	if card then
		Motion.Tween(Motion.ScaleOf(card), { Scale = 0.85 }, 0.15)
		task.delay(0.16, function()
			card:Destroy()
		end)
	end
end

local function newCard(s: Session, width: number, height: number): Frame
	dismissCard(s)
	local card: Frame = New("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 5,
		-- La croix de la manette reste sur les boutons de la carte.
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
		Tag = { "Glass", "RoundL" },
		Parent = s.Cards,
	}, {
		New("UIShadow", {
			BlurRadius = UDim.new(0, 34),
			Transparency = 0.3,
			Offset = UDim2.fromOffset(0, 12),
			Color = Style.Color("BgDeep"),
		}),
	})
	Material.Glass(card, true)
	Material.RgbEdge(card, 2, 0.1, 50)
	local scale = Motion.ScaleOf(card)
	scale.Scale = 0.8
	Motion.Tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	s.Card = card
	s.CardReadyAt = os.clock() + CARD_GUARD
	return card
end

-- Enveloppe une action de carte : ignorée pendant la garde (évite les appuis en rafale
-- de la partie qui tomberaient sur RÉESSAYER / CONTINUER).
local function guarded(s: Session, action: () -> ()): () -> ()
	return function()
		if s.Closed or os.clock() < s.CardReadyAt then
			return
		end
		action()
	end
end

local function buttonRow(card: Frame, y: number): Frame
	return New("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, -40, 0, 72),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 16, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
end

local close: (s: Session, success: boolean, cancelled: boolean) -> ()
local startCountdown: (s: Session) -> ()

-- Le sbire (ou LAGZ) dans un médaillon qui déborde du coin de la carte.
local function minionBadge(s: Session, card: Frame, mood: Minions.Mood, position: UDim2): Frame
	local badge: Frame = New("Frame", {
		Name = "Minion",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(124, 124),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = card,
	}, {
		Common.Corner(),
		New("UIStroke", {
			Color = if mood == "Defeated" then C.Good else C.VirusHot,
			Thickness = 3,
			Transparency = 0.1,
		}),
	})
	local character = Minions.Build(s.Minion, UDim2.fromScale(0.86, 0.86), mood, badge)
	character.ZIndex = 7
	Motion.Pop(badge, 0.3)
	return badge
end

-- Bulle de dialogue du sbire (une phrase).
local function speech(card: Frame, text: string, y: number, color: Color3): TextLabel
	return label({
		Name = "Speech",
		Position = UDim2.fromOffset(20, y),
		Size = UDim2.new(1, -170, 0, 36),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.35,
		TextWrapped = true,
		TextScaled = true,
		Text = text,
		TextColor3 = color,
		Tag = "FontBold",
		Parent = card,
		ZIndex = 6,
	}) :: TextLabel
end

-- Carte d'intro au style de l'app AngAInOne : la page du monde (barre latérale, titre, sous-titre)
-- en train de lancer son action (« Analyser », « Télécharger et extraire »…). Les commandes ne
-- changent pas : JOUER (Entrée / A) lance le compte à rebours, Quitter (B) ferme ; le bouton violet
-- de l'app lance aussi la partie.
local INTRO_W, INTRO_H = 760, 568
local SIDE_W = 170
local MAIN_X = SIDE_W + 20
local MAIN_W = INTRO_W - MAIN_X - 20

local function showIntro(s: Session)
	s.Phase = "Intro"
	local info = s.Info
	local page = AppPages.Intro(if s.Boss then Tower.WORLD_COUNT else AppPages.IntroWorld(s.Kind, s.Difficulty))
	local card = newCard(s, INTRO_W, INTRO_H)
	-- Fenêtre de l'app par-dessus le verre de la carte (le liseré RGB du terminal reste autour)
	local win = Fluent.Box(card, 0, 0, INTRO_W, INTRO_H, FC.Bg, Theme.Radius.L)
	win.Name = "AppWindow"
	Fluent.Text(win, "AngAInOne", 16, 0, 90, 30, 14, { Color = FC.Dim })
	Fluent.Tag(
		win,
		`{if s.Boss then "COMBAT FINAL" else "TERMINAL ANTIVIRUS"} · {info.Title}`,
		110,
		5,
		22,
		12,
		FC.Text,
		FC.Accent
	)
	Fluent.Sidebar(win, 0, 30, SIDE_W, INTRO_H - 30, page.World, nil, 14)
	Fluent.Box(win, SIDE_W, 30, 1, INTRO_H - 30, FC.CardHover)
	-- En-tête de la page (le sbire déborde du coin, à droite)
	Fluent.Text(win, page.Page, MAIN_X, 38, MAIN_W - 150, 40, 30, { Weight = "Bold", Name = "Title" })
	Fluent.Text(win, page.Subtitle, MAIN_X, 78, MAIN_W - 150, 34, 14, { Color = FC.Dim, Wrap = true })
	local line = speech(
		win,
		if s.Boss then "LAGZ te défie : détruis-le !" else Minions.Taunt(s.Minion),
		122,
		C.VirusHot:Lerp(C.White, 0.35)
	)
	line.Position = UDim2.fromOffset(MAIN_X, 122)
	line.Size = UDim2.fromOffset(MAIN_W, 28)
	New("UICorner", { CornerRadius = UDim.new(0, 10), Parent = line })
	New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = line })
	New("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 11, Parent = line })
	minionBadge(s, card, "Evil", UDim2.new(1, -72, 0, 62))
	-- L'action de l'app : tâche, détail, bouton violet, barre d'avancement à 0 %
	local action = Fluent.Card(win, MAIN_X, 158, MAIN_W, 88)
	Fluent.Glyph(action, 14, 14, 26, "!", FC.Bad)
	Fluent.Text(action, page.Task, 52, 8, MAIN_W - 280, 26, 16, { Weight = "Medium" })
	Fluent.Text(action, page.Detail, 52, 48, MAIN_W - 66, 20, 13, { Color = FC.Dim })
	local actionButton = Fluent.Button(action, page.Action, MAIN_W - 214, 8, 200, 36, "Accent", 15)
	local actionHit: TextButton = New("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Selectable = false,
		Parent = actionButton,
	})
	actionHit.Activated:Connect(guarded(s, function()
		startCountdown(s)
	end))
	Fluent.Bar(action, 52, 74, MAIN_W - 66, 6, FC.AccentSoft)
	local art: Frame = New("Frame", {
		Name = "Illustration",
		Position = UDim2.fromOffset(MAIN_X, 256),
		Size = UDim2.fromOffset(MAIN_W, 120),
		BackgroundColor3 = FC.Sunken,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = win,
	}, { Create.Corner(8) })
	xpcall(s.Game.Illustrate, function(err: any)
		warn("[MinigamePanel] illustration :", err)
	end, art)
	label({
		Name = "Rule",
		Position = UDim2.fromOffset(MAIN_X, 384),
		Size = UDim2.fromOffset(MAIN_W, 28),
		Text = info.Rule,
		TextSize = 22,
		TextColor3 = C.White,
		Tag = "FontBold",
		Parent = win,
	})
	-- Objectif
	local chip: Frame = New("Frame", {
		Name = "Target",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(MAIN_X + MAIN_W / 2, 418),
		Size = UDim2.fromOffset(0, 42),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = FC.Card,
		BorderSizePixel = 0,
		Parent = win,
	}, {
		Create.Corner(21) :: Instance,
		Create.List(Enum.FillDirection.Horizontal, 10, { VerticalAlignment = Enum.VerticalAlignment.Center }),
		New("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 20) }),
		New("UIStroke", { Color = C.Gold, Thickness = 2, Transparency = 0.4 }),
	})
	local star = Icon.new("Star", 26, "CurrencyBits")
	star.LayoutOrder = 1
	star.Parent = chip
	label({
		Name = "Text",
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		Text = info.Target,
		TextSize = 24,
		TextColor3 = C.Gold,
		Tag = "FontHeavy",
		LayoutOrder = 2,
		Parent = chip,
	})
	label({
		Name = "Controls",
		Position = UDim2.fromOffset(MAIN_X, 464),
		Size = UDim2.fromOffset(MAIN_W, 18),
		Text = info.Controls,
		Tag = "TextMuted",
		Parent = win,
	})
	local row: Frame = New("Frame", {
		Name = "Buttons",
		Position = UDim2.fromOffset(MAIN_X, 488),
		Size = UDim2.fromOffset(MAIN_W, 68),
		BackgroundTransparency = 1,
		Parent = win,
	}, {
		Create.List(Enum.FillDirection.Horizontal, 16, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	local play = bigKeycap({
		Text = "JOUER",
		Variant = "Primary",
		Size = UDim2.fromOffset(240, 64),
		LayoutOrder = 1,
		Parent = row,
		OnClick = guarded(s, function()
			startCountdown(s)
		end),
	}, 30)
	local quit = function()
		close(s, false, false)
	end
	Keycap.new({
		Text = "Quitter",
		Variant = "Ghost",
		Size = UDim2.fromOffset(150, 52),
		Small = true,
		LayoutOrder = 2,
		Parent = row,
		OnClick = guarded(s, quit),
	})
	s.Primary = function()
		startCountdown(s)
	end
	s.Secondary = quit
	Common.Focus(play.Button)
end

local function showResult(s: Session, success: boolean)
	s.Phase = "Result"
	local info = s.Info
	local card = newCard(s, 560, if success then 380 else 420)
	-- Médaillon qui déborde en haut
	local medal: Frame = New("Frame", {
		Name = "Medal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = if success then C.Gold else C.Amber,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = card,
	}, {
		Common.Corner(),
		New("UIStroke", { Color = C.White, Thickness = 3, Transparency = 0.2 }),
	})
	local medalIcon = Icon.new(if success then "Trophy" else "Heart", 54, "BgDeep")
	medalIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	medalIcon.Position = UDim2.fromScale(0.5, 0.5)
	medalIcon.Parent = medal
	Motion.Pop(medal, 0.4)
	-- Le sbire : K.O. après une victoire, narquois après un échec.
	minionBadge(s, card, if success then "Defeated" else "Evil", UDim2.new(1, -40, 0, 20))
	local title = if success
		then (if s.Boss then "LAGZ EST DÉTRUIT !" else "VIRUS ÉLIMINÉS !")
		else "Presque ! Réessaie"
	local titleLabel = label({
		Name = "Title",
		Position = UDim2.fromOffset(130, 60),
		Size = UDim2.new(1, -260, 0, 44),
		Text = title,
		TextScaled = true,
		TextColor3 = if success then C.Good else C.Amber,
		Tag = "FontDisplay",
		Parent = card,
	})
	New("UITextSizeConstraint", { MaxTextSize = if success then 32 else 30, Parent = titleLabel })
	label({
		Name = "Subtitle",
		Position = UDim2.fromOffset(20, 108),
		Size = UDim2.new(1, -40, 0, 26),
		Text = if success
			then (if s.Boss then "Le PC tourne à 144 FPS !" else Minions.Defeat(s.Minion))
			else Minions.Gloat(s.Minion),
		TextSize = 20,
		TextColor3 = C.White,
		Tag = "FontBold",
		Parent = card,
	})
	-- Score : "12 / 15 virus" qui défile
	local score: TextLabel = label({
		Name = "Score",
		Position = UDim2.fromOffset(20, 146),
		Size = UDim2.new(1, -40, 0, 56),
		TextWrapped = false,
		Text = "",
		TextSize = 46,
		TextColor3 = if success then C.Gold else C.White,
		Tag = "FontHeavy",
		Parent = card,
	})
	local goal, unit = info.Goal, info.Unit
	Motion.CountTo(score, 0, s.LastScore, function(n: number): string
		return `{math.floor(n + 0.5)} / {goal} {unit}`
	end, 0.8)
	label({
		Name = "Time",
		Position = UDim2.fromOffset(20, 204),
		Size = UDim2.new(1, -40, 0, 20),
		Text = `Temps : {math.floor(s.LastDuration + 0.5)} s`,
		Tag = "TextMuted",
		Parent = card,
	})
	if success then
		Common.Sound("Achievement")
		Common.Confetti(s.Cards)
		local row = buttonRow(card, 250)
		local continue = function()
			close(s, true, false)
		end
		local go = bigKeycap({
			Text = "CONTINUER",
			Variant = "Success",
			Size = UDim2.fromOffset(280, 68),
			Parent = row,
			OnClick = guarded(s, continue),
		}, 28)
		-- Fermeture automatique (barre qui se vide sous le bouton).
		local timerBar: Frame = New("Frame", {
			Name = "AutoClose",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -18),
			Size = UDim2.fromOffset(240, 5),
			BackgroundColor3 = C.Good,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Parent = card,
		}, { Common.Corner() })
		Motion.Tween(timerBar, { Size = UDim2.fromOffset(0, 5) }, SUCCESS_AUTOCLOSE, Enum.EasingStyle.Linear)
		task.delay(SUCCESS_AUTOCLOSE, function()
			if s.Card == card and not s.Closed then
				continue()
			end
		end)
		s.Primary = continue
		s.Secondary = continue
		Common.Focus(go.Button)
	else
		Common.Sound("Toast")
		label({
			Name = "Tip",
			Position = UDim2.fromOffset(20, 232),
			Size = UDim2.new(1, -40, 0, 44),
			Text = info.Tip,
			TextSize = 18,
			TextColor3 = C.Cyan,
			Tag = "FontBold",
			Parent = card,
		})
		local row = buttonRow(card, 300)
		local retry = function()
			if s.OnRetry then
				s.OnRetry()
			end
			startCountdown(s)
		end
		local quit = function()
			close(s, false, false)
		end
		local again = bigKeycap({
			Text = "RÉESSAYER",
			Variant = "Primary",
			Size = UDim2.fromOffset(260, 68),
			LayoutOrder = 1,
			Parent = row,
			OnClick = guarded(s, retry),
		}, 28)
		Keycap.new({
			Text = "Quitter",
			Variant = "Ghost",
			Size = UDim2.fromOffset(150, 52),
			Small = true,
			LayoutOrder = 2,
			Parent = row,
			OnClick = guarded(s, quit),
		})
		s.Primary = retry
		s.Secondary = quit
		Common.Focus(again.Button)
	end
end

------------------------------------------------------------------------------------
-- Partie
------------------------------------------------------------------------------------

local function stopGame(s: Session)
	local cleanup = s.Cleanup
	s.Cleanup = nil
	if cleanup then
		xpcall(cleanup, function(err: any)
			warn("[MinigamePanel] nettoyage du jeu :", err)
		end)
	end
	-- Filet de sécurité : rien ne doit rester dans le terrain.
	for _, child in s.Field:GetChildren() do
		child:Destroy()
	end
	Common.Unfocus(s.Root)
end

-- Grand texte au centre (compte à rebours, "BRAVO !").
local function shout(s: Session, text: string, color: Color3, size: number, hold: number): TextLabel
	local big = label({
		Name = "Shout",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 160),
		TextWrapped = false,
		Text = text,
		TextSize = size,
		TextColor3 = color,
		Tag = "FontDisplay",
		ZIndex = 8,
		Parent = s.Cards,
	})
	New("UIStroke", { Color = C.Ink, Thickness = 4, Transparency = 0.1, Parent = big })
	Motion.Pop(big, 0.45)
	task.delay(hold, function()
		if big.Parent then
			Motion.Tween(big, { TextTransparency = 1 }, 0.2)
			local stroke = big:FindFirstChildOfClass("UIStroke")
			if stroke then
				Motion.Tween(stroke, { Transparency = 1 }, 0.2)
			end
			task.delay(0.22, function()
				big:Destroy()
			end)
		end
	end)
	return big
end

local function onFinish(s: Session, success: boolean, score: number)
	if s.Closed or phaseOf(s) ~= "Playing" then
		return
	end
	s.Phase = "Ending"
	-- Plus de X : une victoire ne doit pas être perdue par un appui de trop.
	if s.HeaderQuit then
		s.HeaderQuit.Visible = false
	end
	s.LastScore = score
	s.LastDuration = if s.AttemptStart then os.clock() - s.AttemptStart else 0
	s.AttemptStart = nil
	if success then
		shout(s, "BRAVO !", C.Good, 84, 1)
		Common.Sound("Upgrade")
	else
		shout(s, "OH NON !", C.Amber, 72, 1)
		Common.Sound("Error", 0.8)
	end
	task.delay(1.25, function()
		if s.Closed or phaseOf(s) ~= "Ending" then
			return
		end
		stopGame(s)
		showResult(s, success)
	end)
end

-- Combat final : LAGZ glitche l'écran (barres colorées brèves, jamais bloquantes :
-- ce sont des Frames sans entrée, posées au-dessus du jeu dans le terrain).
local function bossGlitches(s: Session)
	local attempt = s.Attempt
	task.spawn(function()
		while true do
			task.wait(1.6 + math.random() * 2.2)
			if s.Closed or s.Attempt ~= attempt or phaseOf(s) ~= "Playing" then
				return
			end
			if not Motion.IsReduced() then
				for _ = 1, math.random(2, 4) do
					local bar: Frame = New("Frame", {
						Name = "BossGlitch",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.08, math.random()),
						Size = UDim2.new(1.1, 0, 0.015 + math.random() * 0.04, 0),
						BackgroundColor3 = if math.random() < 0.5 then C.GlitchA else C.GlitchB,
						BackgroundTransparency = 0.6,
						BorderSizePixel = 0,
						Active = false,
						ZIndex = 10,
						Parent = s.Field,
					})
					task.delay(0.07 + math.random() * 0.12, function()
						bar:Destroy()
					end)
				end
			end
		end
	end)
end

local function startGame(s: Session)
	if s.Closed then
		return
	end
	s.Phase = "Playing"
	s.Attempt += 1
	s.AttemptStart = os.clock()
	if s.Boss then
		bossGlitches(s)
	end
	local ok, result = pcall(s.Game.Run, s.Field, s.Difficulty, function(success: boolean, score: number)
		onFinish(s, success, score)
	end, s.Hud)
	if ok then
		s.Cleanup = result
	else
		warn("[MinigamePanel] impossible de lancer", s.Kind, ":", result)
		onFinish(s, false, 0)
	end
end

startCountdown = function(s: Session)
	if s.Closed or phaseOf(s) == "Countdown" or phaseOf(s) == "Playing" then
		return
	end
	dismissCard(s)
	stopGame(s)
	s.Phase = "Countdown"
	s.ResetHud()
	if s.HeaderQuit then
		s.HeaderQuit.Visible = true
	end
	task.spawn(function()
		for index, text in { "3", "2", "1", "GO !" } do
			if s.Closed or phaseOf(s) ~= "Countdown" then
				return
			end
			local last = index == 4
			shout(s, text, if last then C.Good else C.White, if last then 96 else 120, if last then 0.35 else 0.45)
			if last then
				Common.Sound("PowerOn", 1.2)
			else
				Common.Sound("Click", 0.9 + index * 0.12)
			end
			task.wait(if last then 0.4 else 0.65)
		end
		if not s.Closed and phaseOf(s) == "Countdown" then
			startGame(s)
		end
	end)
end

close = function(s: Session, success: boolean, cancelled: boolean)
	if s.Closed then
		return
	end
	s.Closed = true
	if session == s then
		session = nil
	end
	local elapsed = if s.AttemptStart then os.clock() - s.AttemptStart else s.LastDuration
	local score = if cancelled then 0 else s.LastScore
	stopGame(s)
	dismissCard(s)
	for _, connection in s.Connections do
		connection:Disconnect()
	end
	table.clear(s.Connections)
	ContextActionService:UnbindAction(BACK_ACTION)
	if not session then
		setCharacterControls(true)
		setBlur(false)
	end
	-- Fondu de sortie puis destruction.
	s.Content.Visible = false
	Motion.Tween(s.Dim, { BackgroundTransparency = 1 }, 0.25)
	task.delay(0.3, function()
		s.Root:Destroy()
	end)
	local callback = s.OnDone
	task.spawn(callback, success, score, if cancelled then elapsed else s.LastDuration)
end

------------------------------------------------------------------------------------
-- Construction de l'écran
------------------------------------------------------------------------------------

local function buildArena(s: Session, parent: Frame)
	local slot: Frame = New("Frame", {
		Name = "ArenaSlot",
		Position = UDim2.fromOffset(16, HEADER_H + 24),
		Size = UDim2.new(1, -32, 1, -(HEADER_H + 40)),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = parent,
	})
	local arena: Frame = New("Frame", {
		Name = "Arena",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Tag = { "GlassSunken", "RoundL" },
		Parent = slot,
	}, {
		New("UIAspectRatioConstraint", {
			AspectRatio = Core.FIELD_W / Core.FIELD_H,
			AspectType = Enum.AspectType.FitWithinMaxSize,
			DominantAxis = Enum.DominantAxis.Width,
		}),
	})
	Material.Glass(arena, false)
	Material.RgbEdge(arena, 2.5, 0.15, 30)
	-- Grille de circuit imprimé (décor)
	local accent = Style.Color(s.Info.Accent)
	for i = 1, math.floor(Core.FIELD_W / 50) - 1 do
		New("Frame", {
			Name = "GridV",
			Position = UDim2.fromScale(i * 50 / Core.FIELD_W, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.92,
			BorderSizePixel = 0,
			Parent = arena,
		})
	end
	for i = 1, math.floor(Core.FIELD_H / 50) - 1 do
		New("Frame", {
			Name = "GridH",
			Position = UDim2.fromScale(0, i * 50 / Core.FIELD_H),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.92,
			BorderSizePixel = 0,
			Parent = arena,
		})
	end
	-- Ligne de scan qui balaie l'écran (décor)
	local scanline: Frame = New("Frame", {
		Name = "Scanline",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Parent = arena,
	})
	Common.Pulse(scanline, { Position = UDim2.fromScale(0, 1) }, 3.2)
	s.Field = New("Frame", {
		Name = "Field",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = arena,
	})
	-- Les cartes et le compte à rebours se superposent au terrain.
	s.Cards = New("Frame", {
		Name = "Cards",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = parent,
	})
end

------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------

function MinigamePanel.Mount(target: Frame)
	layer = target
	if not blur then
		local effect: BlurEffect = New("BlurEffect", {
			Name = "MinigameBlur",
			Size = 0,
			Enabled = false,
			Parent = Lighting,
		})
		blur = effect
	end
end

function MinigamePanel.IsPlaying(): boolean
	return session ~= nil
end

function MinigamePanel.Cancel()
	local s = session
	if s then
		close(s, false, true)
	end
end

function MinigamePanel.Play(kind: string, difficulty: number, onDone: OnDone, onRetry: (() -> ())?)
	local entry = GAMES[kind]
	local target = layer
	if not entry or not target then
		warn(`[MinigamePanel] mini-jeu inconnu ou écran non monté : {tostring(kind)}`)
		task.defer(onDone, false, 0, 0)
		return
	end
	MinigamePanel.Cancel()
	local boss = Core.IsBoss(difficulty)
	local level = if boss then Core.BOSS_LEVEL else Core.Level(difficulty)
	local world = Tower.Worlds[Core.Level(difficulty)]
	local minion = if boss or not world then "LAGZ" else world.Minion

	local root: Frame = New("Frame", {
		Name = "Minigame",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = target,
	})
	-- Voile : un bouton plein écran qui absorbe tous les appuis (rien ne passe dessous).
	local dim: TextButton = New("TextButton", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		ZIndex = 1,
		Tag = "Backdrop",
		Parent = root,
	}, {
		New("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.25),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})
	local content: Frame = New("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})

	local s: Session = {
		Kind = kind,
		Difficulty = level,
		Boss = boss,
		Minion = minion,
		Game = entry,
		Info = entry.Info(level, Common.Device()),
		OnDone = onDone,
		OnRetry = onRetry,
		Phase = "Intro",
		Closed = false,
		Root = root,
		Dim = dim,
		Content = content,
		Field = content, -- remplacé par buildArena
		Cards = content, -- remplacé par buildArena
		Hud = Common.NullHud,
		ResetHud = function() end,
		HeaderQuit = nil,
		Card = nil,
		CardReadyAt = 0,
		Primary = nil,
		Secondary = nil,
		Cleanup = nil,
		AttemptStart = nil,
		LastScore = 0,
		LastDuration = 0,
		Attempt = 0,
		Connections = {},
	}
	session = s

	local hud, reset = buildHud(s, content)
	s.Hud = hud
	s.ResetHud = reset
	buildArena(s, content)
	reset()

	-- Entrées des cartes : Entrée = bouton principal ; B manette = quitter.
	-- (pas Espace : on le martèle dans Dodge, il ne doit pas relancer une partie par erreur)
	table.insert(
		s.Connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or not s.Card or os.clock() < s.CardReadyAt then
				return
			end
			local code = input.KeyCode
			if code == Enum.KeyCode.Return or code == Enum.KeyCode.KeypadEnter then
				local action = s.Primary
				if action then
					action()
				end
			end
		end)
	)
	ContextActionService:BindActionAtPriority(
		BACK_ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin and s.Card and os.clock() >= s.CardReadyAt then
				local action = s.Secondary
				if action then
					action()
					return Enum.ContextActionResult.Sink
				end
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value + 1,
		Enum.KeyCode.ButtonB
	)

	setCharacterControls(false)
	setBlur(true)
	GuiService.SelectedObject = nil
	Motion.Tween(dim, { BackgroundTransparency = 0.25 }, 0.3)
	Common.Sound("Whoosh")
	showIntro(s)
end

return MinigamePanel
