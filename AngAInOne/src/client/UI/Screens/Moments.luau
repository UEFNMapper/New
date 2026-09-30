--!strict
--[[
	Moments : les instants forts du deathrun, courts et passables.
	- Intro (première visite) : « Opération Anti-Lag » racontée par Anga en 3 cartes
	- Bannière de monde (en entrant dans un nouveau composant)
	- Terminal réussi (« VIRUS ÉLIMINÉS, le portail est ouvert »)
	- Mort (petit flash glitch) et victoire : « LE LIVE COMMENCE ! » (le stream d'Anga démarre,
	  le chat défile, Anga remercie le joueur par son pseudo)
]]

local Players = game:GetService("Players")
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
local Lagz = require(script.Parent.Parent.Components.Lagz)

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
	"Catastrophe ! Mon grand live sur AngaTV commence dans une heure… et mon PC RAME : 3 FPS et 999 de ping !",
	"Le coupable : LAGZ, un virus qui dévore la puissance des PC. Freezes, pubs, coupures de courant… c'est lui !",
	"Je te miniaturise et je t'envoie DANS la tour. Nettoie chaque composant et chaque terminal antivirus jusqu'en haut !",
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
	-- LAGZ se montre sur la carte qui le présente.
	local villain = Lagz.Face(76, card)
	villain.AnchorPoint = Vector2.new(1, 0)
	villain.Position = UDim2.new(1, -18, 0, -30)
	villain.Visible = false
	local heading: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(24, 52),
		Size = UDim2.new(1, -48, 0, 36),
		BackgroundTransparency = 1,
		Text = "OPÉRATION ANTI-LAG",
		Tag = "FontDisplay",
		TextScaled = true,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = card,
	}, { New("UITextSizeConstraint", { MaxTextSize = 30 }) :: Instance })
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
		villain.Visible = page == 2
		if page == 2 then
			Motion.Pop(villain, 0.2)
		end
		heading.Text = if page == 2 then "LAGZ, LE VIRUS" else "OPÉRATION ANTI-LAG"
		button:SetText(if page < #STORY then "SUITE" else "MODE INTERVENTION : GO !")
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

-- Fin : « LE LIVE COMMENCE ! » — le stream d'Anga démarre et le chat fête le joueur.
function Moments.Victory(payload: any)
	local displayName = Players.LocalPlayer.DisplayName
	local screen = fullscreen("Victory", "Backdrop", 1)
	Motion.Tween(screen, { BackgroundTransparency = 0.25 }, 0.6)
	local card: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(760, 440),
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

	-- Pastille « EN DIRECT » (point qui clignote) et performances du PC
	local live: Frame = New("Frame", {
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.fromOffset(170, 34),
		BorderSizePixel = 0,
		Tag = { "FillBrand", "RoundPill" },
		Parent = card,
	})
	local dot: Frame = New("Frame", {
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
	New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 16),
		Size = UDim2.fromOffset(220, 34),
		BackgroundTransparency = 1,
		Text = `{Branding.ChannelName} · 144 FPS · 8 ms`,
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "DynHeading",
		TextColor3 = Style.Color("Success"),
		Parent = card,
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
		Parent = card,
	}, { New("UITextSizeConstraint", { MaxTextSize = 34 }) :: Instance })
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 112),
		Size = UDim2.fromOffset(452, 26),
		BackgroundTransparency = 1,
		Text = "LAGZ est vaincu : le PC tourne à 144 FPS !",
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = card,
	})
	local timeText = `Temps : {Time.Clock(payload.Time or 0)}`
	if payload.Record then
		timeText ..= "  ·  NOUVEAU RECORD !"
	elseif payload.Assisted then
		timeText ..= "  ·  (course assistée)"
	end
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 144),
		Size = UDim2.fromOffset(452, 26),
		BackgroundTransparency = 1,
		Text = timeText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "TextHeading",
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 180),
		Size = UDim2.fromOffset(452, 96),
		BackgroundTransparency = 1,
		Text = `{Branding.MascotName} : « Merci {displayName} ! Grâce à toi, mon PC revit et le live peut commencer. Tu es le héros du jour ! »`,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Tag = "TextBody",
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(24, 286),
		Size = UDim2.fromOffset(452, 26),
		BackgroundTransparency = 1,
		Text = `+{NumberFormat.Compact(payload.Bits or 0)} Bits  ·  Victoires : {payload.Wins or 1}`,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "DynHeading",
		TextColor3 = Style.Color("CurrencyBits"),
		Parent = card,
	})

	-- Colonne de droite : le chat du live qui défile
	local chat: Frame = New("Frame", {
		Position = UDim2.fromOffset(496, 64),
		Size = UDim2.fromOffset(240, 280),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Tag = { "GlassSunken", "RoundM" },
		Parent = card,
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
			dot.BackgroundTransparency = if blink or Motion.IsReduced() then 0 else 0.6
			task.wait(0.7)
		end
	end)

	Keycap.new({
		Text = "SUPER !",
		Variant = "Primary",
		Size = UDim2.fromOffset(360, 56),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		OnClick = function()
			fadeOut(screen, 0.4)
			card.Visible = false
		end,
		Parent = card,
	})
	Motion.Pop(card, 0.2)
	task.delay(14, function()
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
