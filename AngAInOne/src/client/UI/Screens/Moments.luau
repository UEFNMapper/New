--!strict
--[[
	Moments : les instants forts du deathrun, courts et passables.
	- Intro (première visite) : l'histoire racontée par Anga + « C'EST PARTI ! »
	- Bannière de monde (en entrant dans un nouveau composant)
	- Terminal réussi (« VIRUS ÉLIMINÉS, le portail est ouvert »)
	- Mort (petit flash glitch) et victoire au sommet (temps, record, Bits)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local NumberFormat = require(Shared.Util.NumberFormat)
local Time = require(Shared.Util.Time)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)

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
-- Intro : l'histoire en 3 cartes courtes
------------------------------------------------------------------------------------

local STORY = {
	"Oh non ! Un VIRUS a infecté mon PC. Il a piégé toutes les pièces : l'alimentation, la RAM, la carte graphique…",
	"Tu es tout petit, à l'intérieur de la tour. Grimpe jusqu'en haut en évitant les pièges : ventilateurs, décharges, virus !",
	"À chaque terminal antivirus, élimine les virus dans un mini-jeu pour ouvrir la porte suivante. Prêt ? On y va !",
}

function Moments.Intro(onDone: () -> ())
	local dim = fullscreen("Intro", "Backdrop", 0.35)
	local card: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(560, 300),
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = dim,
	})
	Material.Glass(card, true)
	Material.RgbEdge(card, 2, 0.1, 60)
	local avatar = Widgets.Avatar(90, card)
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.new(0.5, 0, 0, -45)
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 52),
		Size = UDim2.new(1, -48, 0, 36),
		BackgroundTransparency = 1,
		Text = Branding.GameName,
		Tag = "FontDisplay",
		TextSize = 32,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = card,
	})
	local text: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(28, 96),
		Size = UDim2.new(1, -56, 0, 96),
		BackgroundTransparency = 1,
		Text = "",
		TextWrapped = true,
		Tag = "TextBody",
		Parent = card,
	})
	local page = 1
	local button: Keycap.Keycap
	local function show()
		text.Text = `{Branding.MascotName} : « {STORY[page]} »`
		Motion.Pop(text, 0.05)
		button:SetText(if page < #STORY then "SUITE" else "C'EST PARTI !")
	end
	button = Keycap.new({
		Text = "SUITE",
		Variant = "Primary",
		Size = UDim2.new(1, -80, 0, 70),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		OnClick = function()
			if page < #STORY then
				page += 1
				show()
			else
				fadeOut(dim, 0.3)
				onDone()
			end
		end,
		Parent = card,
	})
	show()
	Motion.Pop(card, 0.15)
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

function Moments.WorldBanner(world: number)
	local def = Tower.Worlds[world]
	if def then
		banner(
			Color3.fromHex(def.Primary),
			`MONDE {world}/{Tower.WORLD_COUNT} · {string.upper(def.Component)}`,
			string.upper(def.Name),
			`Section AngAInOne : {def.AppSection}`,
			4
		)
	end
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

function Moments.Victory(payload: any)
	local screen = fullscreen("Victory", "Backdrop", 1)
	Motion.Tween(screen, { BackgroundTransparency = 0.25 }, 0.6)
	local card: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 340),
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = screen,
	})
	Material.Glass(card, true)
	Material.RgbEdge(card, 2.5, 0.05, 80)
	local avatar = Widgets.Avatar(96, card)
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.new(0.5, 0, 0, -48)
	New("TextLabel", {
		Position = UDim2.fromOffset(20, 56),
		Size = UDim2.new(1, -40, 0, 44),
		BackgroundTransparency = 1,
		Text = "TU AS SAUVÉ LE PC !",
		Tag = "FontDisplay",
		TextSize = 34,
		TextColor3 = Style.Color("CurrencyBits"),
		Parent = card,
	})
	local timeText = `Temps : {Time.Clock(payload.Time or 0)}`
	if payload.Record then
		timeText ..= "  ·  NOUVEAU RECORD !"
	elseif payload.Assisted then
		timeText ..= "  ·  (course assistée)"
	end
	New("TextLabel", {
		Position = UDim2.fromOffset(20, 108),
		Size = UDim2.new(1, -40, 0, 30),
		BackgroundTransparency = 1,
		Text = timeText,
		Tag = "TextHeading",
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(28, 146),
		Size = UDim2.new(1, -56, 0, 80),
		BackgroundTransparency = 1,
		Text = `{Branding.MascotName} : « Le virus est détruit, mon PC revit ! Merci ! Tu veux retenter l'ascension pour battre ton record ? »`,
		TextWrapped = true,
		Tag = "TextBody",
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(20, 236),
		Size = UDim2.new(1, -40, 0, 26),
		BackgroundTransparency = 1,
		Text = `+{NumberFormat.Compact(payload.Bits or 0)} Bits  ·  Victoires : {payload.Wins or 1}`,
		Tag = "DynHeading",
		TextColor3 = Style.Color("CurrencyBits"),
		Parent = card,
	})
	Keycap.new({
		Text = "SUPER !",
		Variant = "Primary",
		Size = UDim2.new(1, -120, 0, 56),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		OnClick = function()
			fadeOut(screen, 0.4)
			card.Visible = false
		end,
		Parent = card,
	})
	Motion.Pop(card, 0.2)
	task.delay(12, function()
		if screen.Parent then
			fadeOut(screen, 0.5)
			card.Visible = false
		end
	end)
end

function Moments.Mount(target: Frame)
	layer = target
end

return Moments
