--!strict
--[[
	Moments : les instants forts, courts et passables.
	- Allumage du PC (tout premier CTA du jeu, < 5 s après l'arrivée)
	- Gains hors ligne (carte de retour)
	- Nouvel étage (bannière aux couleurs de la zone)
	- Capsule (révélation avec halo de rareté)
	- Reboot (écran BIOS de 3 s)
	- Singularité (cinématique de fin + crédits)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Zones = require(Shared.Config.Zones)
local Nanobots = require(Shared.Config.Nanobots)
local Branding = require(Shared.Config.Branding)
local NumberFormat = require(Shared.Util.NumberFormat)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)
local Material = require(script.Parent.Parent.Material)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local Widgets = require(script.Parent.Parent.Components.Widgets)
local Icon = require(script.Parent.Parent.Components.Icon)
local Net = require(script.Parent.Parent.Parent.Controllers.Net)

local New = Create.New

local Moments = {}

Moments.OnTravel = nil :: ((floor: number) -> ())?

local layer: Frame
local powerHero: Frame? = nil

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

------------------------------------------------------------------------------------
-- Allumage
------------------------------------------------------------------------------------

function Moments.ShowPowerOn(visible: boolean)
	if visible and not powerHero then
		local hero: Frame = New("Frame", {
			Name = "PowerHero",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			Size = UDim2.fromOffset(520, 300),
			BackgroundTransparency = Theme.Alpha.GlassStrong,
			BorderSizePixel = 0,
			Tag = { "Glass", "RoundL" },
			Parent = layer,
		}, {
			New("UIShadow", {
				BlurRadius = UDim.new(0, 30),
				Transparency = 0.35,
				Offset = UDim2.fromOffset(0, 10),
				Color = Style.Color("BgDeep"),
			}),
		})
		Material.Glass(hero, true)
		Material.RgbEdge(hero, 2, 0.1, 60)
		local avatar = Widgets.Avatar(84, hero)
		avatar.AnchorPoint = Vector2.new(0.5, 0)
		avatar.Position = UDim2.new(0.5, 0, 0, -42)
		New("TextLabel", {
			Position = UDim2.fromOffset(24, 52),
			Size = UDim2.new(1, -48, 0, 40),
			BackgroundTransparency = 1,
			Text = Branding.GameName,
			Tag = "FontDisplay",
			TextSize = 36,
			TextColor3 = Style.Color("TextPrimary"),
			Parent = hero,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(24, 96),
			Size = UDim2.new(1, -48, 0, 60),
			BackgroundTransparency = 1,
			Text = `{Branding.MascotName} : « On est à l'intérieur de TON PC gamer. Allume-le, et construisons la machine la plus puissante de l'univers ! »`,
			TextWrapped = true,
			Tag = "TextBody",
			Parent = hero,
		})
		Keycap.new({
			Text = "ALLUMER LE PC",
			Icon = "Power",
			Variant = "Primary",
			Size = UDim2.new(1, -80, 0, 76),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -24),
			OnClick = function()
				Net.Fire("PowerOn")
			end,
			Parent = hero,
		})
		Motion.Pop(hero, 0.15)
		powerHero = hero
	elseif not visible and powerHero then
		local hero = powerHero
		powerHero = nil
		Motion.Tween(Motion.ScaleOf(hero), { Scale = 0.85 }, 0.25).Completed:Once(function()
			hero:Destroy()
		end)
	end
end

-- Flash de démarrage (après PowerOn)
function Moments.BootFlash()
	local flash = fullscreen("BootFlash", "FillWhite", 0.2)
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(800, 60),
		BackgroundTransparency = 1,
		Text = "SYSTEM ONLINE",
		Tag = "FontDisplay",
		TextSize = Theme.TextSize.Hero,
		TextColor3 = Style.Color("BgDeep"),
		Parent = flash,
	})
	flash.BackgroundColor3 = Style.Color("AccentViolet")
	Motion.Tween(flash, { BackgroundTransparency = 1 }, 1.4, Enum.EasingStyle.Sine)
	for _, child in flash:GetChildren() do
		if child:IsA("TextLabel") then
			Motion.Tween(child, { TextTransparency = 1 }, 1.6, Enum.EasingStyle.Sine)
		end
	end
	task.delay(1.7, function()
		flash:Destroy()
	end)
end

------------------------------------------------------------------------------------
-- Gains hors ligne
------------------------------------------------------------------------------------

function Moments.Offline(bits: number, seconds: number)
	local card: Frame = New("Frame", {
		Name = "Offline",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -220),
		Size = UDim2.fromOffset(440, 190),
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = layer,
	}, {
		New("UIShadow", {
			BlurRadius = UDim.new(0, 24),
			Transparency = 0.4,
			Offset = UDim2.fromOffset(0, 8),
			Color = Style.Color("BgDeep"),
		}),
	})
	Material.Glass(card, true)
	Material.RgbEdge(card, 1.5, 0.2)
	New("TextLabel", {
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 24),
		BackgroundTransparency = 1,
		Text = "CONTENT DE TE REVOIR",
		Tag = "TextTitle",
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(20, 44),
		Size = UDim2.new(1, -40, 0, 20),
		BackgroundTransparency = 1,
		Text = `Pendant {NumberFormat.Duration(seconds)}, ton PC a produit :`,
		Tag = "TextMuted",
		Parent = card,
	})
	local amount: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(20, 70),
		Size = UDim2.new(1, -40, 0, 40),
		BackgroundTransparency = 1,
		Text = "0",
		Tag = "FontHeavy",
		TextSize = 36,
		TextColor3 = Style.Color("CurrencyBits"),
		Parent = card,
	})
	Motion.CountTo(amount, 0, bits, function(n: number): string
		return `+{NumberFormat.Compact(n)} Bits`
	end, 1.4)
	local function close()
		Motion.Tween(
			card,
			{ Position = UDim2.new(0.5, 0, 0, -220) },
			0.3,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		).Completed
			:Once(function()
				card:Destroy()
			end)
	end
	Keycap.new({
		Text = "SUPER !",
		Variant = "Gold",
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.fromOffset(20, 124),
		Small = true,
		OnClick = close,
		Parent = card,
	})
	Motion.Tween(card, { Position = UDim2.new(0.5, 0, 0, 90) }, 0.45, Enum.EasingStyle.Back)
	task.delay(9, function()
		if card.Parent then
			close()
		end
	end)
end

------------------------------------------------------------------------------------
-- Nouvel étage
------------------------------------------------------------------------------------

function Moments.ZoneUnlocked(zoneIndex: number)
	local zone = Zones[zoneIndex]
	if not zone then
		return
	end
	local primary = Color3.fromHex(zone.Primary)
	local band: Frame = New("Frame", {
		Name = "ZoneBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(1, 0, 0, 170),
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
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = primary,
		BorderSizePixel = 0,
		Parent = band,
	})
	New("Frame", {
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.new(0, 0, 1, -3),
		BackgroundColor3 = primary,
		BorderSizePixel = 0,
		Parent = band,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = `NOUVEL ÉTAGE · {string.upper(zone.Component)}`,
		Tag = "TextCaption",
		Parent = band,
	})
	local title: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		Text = string.upper(zone.Name),
		Tag = "TextHero",
		Parent = band,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = `{zone.Tagline} · Débloque : {zone.Feature}`,
		Tag = "TextBody",
		Parent = band,
	})
	local go = Keycap.new({
		Text = "Y ALLER",
		Variant = "Primary",
		Size = UDim2.fromOffset(180, 44),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 14),
		Small = true,
		OnClick = function()
			if Moments.OnTravel then
				Moments.OnTravel(zoneIndex)
			end
			band:Destroy()
		end,
		Parent = band,
	})
	local _ = go
	Motion.Pop(title, 0.25)
	sweep.Size = UDim2.new(0, 0, 0, 3)
	Motion.Tween(sweep, { Size = UDim2.new(1, 0, 0, 3) }, 0.9, Enum.EasingStyle.Quart)
	task.delay(6, function()
		if band.Parent then
			Motion.Tween(band, { BackgroundTransparency = 1 }, 0.4)
			for _, d in band:GetDescendants() do
				if d:IsA("TextLabel") then
					Motion.Tween(d, { TextTransparency = 1 }, 0.4)
				end
			end
			task.delay(0.45, function()
				band:Destroy()
			end)
		end
	end)
end

------------------------------------------------------------------------------------
-- Capsule
------------------------------------------------------------------------------------

function Moments.Capsule(nanobotId: string)
	local def = Nanobots.ById[nanobotId]
	if not def then
		return
	end
	local color = Color3.fromHex((Theme.Rarity :: any)[def.Rarity] or Theme.Rarity.Common)
	local veil = fullscreen("CapsuleVeil", "Backdrop", 0.45)
	local card: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 380),
		BackgroundTransparency = Theme.Alpha.GlassStrong,
		BorderSizePixel = 0,
		Tag = { "Glass", "RoundL" },
		Parent = veil,
	}, {
		New("UIStroke", { Color = color, Thickness = 3 }),
		New("UIShadow", { BlurRadius = UDim.new(0, 40), Transparency = 0.2, Color = color }),
	})
	Material.Glass(card, true)
	local halo: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 130),
		Size = UDim2.fromOffset(170, 170),
		BackgroundColor3 = Color3.fromHex(def.Color),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Tag = "RoundPill",
		Parent = card,
	})
	local bot = Icon.new("Bot", 110, nil)
	bot.AnchorPoint = Vector2.new(0.5, 0.5)
	bot.Position = UDim2.fromScale(0.5, 0.5)
	bot.Parent = halo
	New("TextLabel", {
		Position = UDim2.fromOffset(0, 236),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = string.upper(Nanobots.RarityNames[def.Rarity]),
		Tag = "DynHeading",
		TextColor3 = color,
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(0, 258),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Text = def.Name,
		Tag = "FontDisplay",
		TextSize = 26,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(0, 296),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = Nanobots.BonusText(def, false),
		Tag = "TextBody",
		Parent = card,
	})
	local close = function()
		veil:Destroy()
	end
	Keycap.new({
		Text = "GÉNIAL",
		Variant = "Secondary",
		Size = UDim2.new(1, -60, 0, 44),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Small = true,
		OnClick = close,
		Parent = card,
	})
	local scale = Motion.ScaleOf(card)
	scale.Scale = 0.2
	Motion.Tween(scale, { Scale = 1 }, 0.5, Enum.EasingStyle.Back)
	local haloScale = Motion.ScaleOf(halo)
	task.spawn(function()
		while halo.Parent do
			Motion.Tween(haloScale, { Scale = 1.08 }, 0.8, Enum.EasingStyle.Sine)
			task.wait(0.8)
			Motion.Tween(haloScale, { Scale = 1 }, 0.8, Enum.EasingStyle.Sine)
			task.wait(0.8)
		end
	end)
	task.delay(5, function()
		if veil.Parent then
			close()
		end
	end)
end

------------------------------------------------------------------------------------
-- Reboot : écran BIOS
------------------------------------------------------------------------------------

function Moments.Reboot(firmware: number, generation: number)
	local screen = fullscreen("BiosScreen", "Backdrop", 0)
	local lines = {
		`AngAInOne BIOS v{generation}.0 — (c) Anga Systems`,
		"Vérification de la mémoire .......... OK",
		`Flash du firmware (+{firmware}) ........ OK`,
		"Réinitialisation des composants ..... OK",
		`Démarrage de la Génération {generation}…`,
	}
	local text: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(80, 80),
		Size = UDim2.new(1, -160, 1, -200),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Code,
		TextSize = 22,
		TextColor3 = Style.Color("AccentCyan"),
		Parent = screen,
	})
	local bar = Widgets.Bar(UDim2.new(1, -160, 0, 10), Style.Color("AccentViolet"), screen)
	bar.Root.Position = UDim2.new(0, 80, 1, -100)
	task.spawn(function()
		for index, value in lines do
			text.Text ..= value .. "\n"
			bar:Set(index / #lines)
			task.wait(0.45)
		end
		task.wait(0.4)
		Motion.Tween(screen, { BackgroundTransparency = 1 }, 0.6)
		Motion.Tween(text, { TextTransparency = 1 }, 0.4)
		bar.Root.Visible = false
		task.wait(0.65)
		screen:Destroy()
	end)
end

------------------------------------------------------------------------------------
-- Singularité : fin du jeu
------------------------------------------------------------------------------------

function Moments.Singularity(count: number)
	local screen = fullscreen("Singularity", "FillWhite", 1)
	screen.BackgroundColor3 = Style.Color("AccentViolet")
	New("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Style.Color("TextPrimary"), Style.Color("AccentViolet")),
		Parent = screen,
	})
	Motion.Tween(screen, { BackgroundTransparency = 0 }, 1.2, Enum.EasingStyle.Sine)
	task.wait(1.2)
	local avatar = Widgets.Avatar(110, screen)
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.Position = UDim2.fromScale(0.5, 0.25)
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(900, 60),
		BackgroundTransparency = 1,
		Text = "SINGULARITÉ",
		Tag = "FontDisplay",
		TextSize = 56,
		TextColor3 = Style.Color("BgDeep"),
		Parent = screen,
	})
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(760, 110),
		BackgroundTransparency = 1,
		Text = `{Branding.MascotName} : « On l'a fait. Ton PC pense, rêve et calcule plus vite que l'univers lui-même. Merci d'avoir construit ça avec moi. Mais… et si on recommençait, encore plus fort ? »`,
		TextWrapped = true,
		Tag = "FontMedium",
		TextSize = 20,
		TextColor3 = Style.Color("BgDeep"),
		Parent = screen,
	})
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromOffset(700, 24),
		BackgroundTransparency = 1,
		Text = `Singularités atteintes : {count} · Un jeu d'Anga · Musique APM Music`,
		Tag = "FontBold",
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Style.Color("SurfaceSunken"),
		Parent = screen,
	})
	Keycap.new({
		Text = "CONTINUER",
		Variant = "Primary",
		Size = UDim2.fromOffset(260, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.74),
		OnClick = function()
			Motion.Tween(screen, { BackgroundTransparency = 1 }, 0.6).Completed:Once(function()
				screen:Destroy()
			end)
			for _, d in screen:GetDescendants() do
				if d:IsA("GuiObject") then
					d.Visible = false
				end
			end
		end,
		Parent = screen,
	})
end

function Moments.Mount(target: Frame)
	layer = target
end

return Moments
