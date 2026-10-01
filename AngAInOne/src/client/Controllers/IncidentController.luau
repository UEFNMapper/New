--!strict
--[[
	IncidentController : les incidents de LAGZ vus par le joueur (docs/SCENARIO.md §4).
	Lit ReplicatedStorage.IncidentState (publié par IncidentService) pour le monde OÙ JE COURS
	(hors lobby, hors mini-jeu) :
	- Annonce 3 s avant : bandeau « ⚠ LAGZ prépare un FREEZE ! » avec la tête de LAGZ + décompte
	- Pendant l'incident : titre + conseil + barre qui se vide, et l'effet d'écran du type :
	    FREEZE      teinte bleu glace, givre sur les bords, sablier
	    LAG SPIKE   l'image « rame » par à-coups (au rythme des pièges), roue de chargement
	    BLACKOUT    l'éclairage s'éteint (néons et dangers restent visibles), petite lueur
	                autour du joueur ; tout est restauré à la fin
	    POP-UP STORM 3 à 5 fausses pubs qui rebondissent : toucher le gros ✕ pour les fermer
	    CORRUPTION  flash « texture manquante » rose / noir
	    SURCHAUFFE  teinte rouge, ondes de chaleur, bordures de l'UI qui virent au rouge
	Respecte « Réduire les animations » (pas de flash, pas de saccade, rien qui bouge).
	Aucune remote : tout vient des attributs répliqués (les sons aussi, pour qu'un joueur qui
	arrive en plein incident le voie quand même).
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Incidents = require(Shared.Config.Incidents)
local IncidentSchedule = require(Shared.Util.IncidentSchedule)

local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local Create = require(script.Parent.Parent.UI.Create)
local Style = require(script.Parent.Parent.UI.Style)
local Motion = require(script.Parent.Parent.UI.Motion)
local Material = require(script.Parent.Parent.UI.Material)
local Icon = require(script.Parent.Parent.UI.Components.Icon)
local Lagz = require(script.Parent.Parent.UI.Components.Lagz)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)

local New = Create.New

local IncidentController = {}

-- Branché par Main : un mini-jeu est-il en cours ? (aucun incident pendant un mini-jeu)
IncidentController.IsBusy = function(): boolean
	return false
end

type Effect = {
	Update: (elapsed: number, dt: number) -> (),
	Stop: () -> (),
}

type Current = {
	Key: string,
	World: number,
	Kind: string,
	Warn: number,
	Start: number,
	End: number,
	Phase: string,
	Effect: Effect?,
	LastCount: number,
	LastElapsed: number,
}

local player = Players.LocalPlayer
local stateFolder: Instance? = nil
local fxGui: ScreenGui
local tint: ColorCorrectionEffect
local blur: BlurEffect
local tintToken = 0
local current: Current? = nil
local errors = 0

-- Bandeau d'annonce
local banner: Frame
local bannerTitle: TextLabel
local bannerSub: TextLabel
local bannerCount: TextLabel
local bannerFill: Frame
local bannerTrack: Frame
local bannerStroke: UIStroke

local ARTICLE: { [string]: string } = {
	Freeze = "un",
	Lag = "un",
	Blackout = "un",
	Popups = "une",
	Corruption = "une",
	Overheat = "une",
	Update = "une",
}

local HINT: { [string]: string } = {
	Freeze = "Les pièges sont figés : fonce !",
	Lag = "Les pièges avancent par à-coups : prends ton temps.",
	Blackout = "Suis les néons : les dangers restent visibles.",
	Popups = "Touche les ✕ pour fermer les pubs !",
	Corruption = "Les dalles corrompues sont inversées !",
	Overheat = "Toutes les bouches de chaleur soufflent !",
	Update = "Ne pas éteindre votre ordinateur… les pièges, eux, continuent !",
}

local LETHAL: { [string]: boolean } = {
	Zapper = true,
	SpinBar = true,
	Crusher = true,
	Laser = true,
	Virus = true,
	Heat = true,
	Surge = true,
	TabRain = true,
	Flood = true,
	DustBall = true,
	Pendulum = true,
	Cursor = true,
	FirewallWall = true,
}

local function shortName(kind: string): string
	local def = Incidents.ByKind[kind]
	if not def then
		return string.upper(kind)
	end
	return (string.gsub(def.Title, "%s*!$", ""))
end

------------------------------------------------------------------------------------
-- Outils : teinte, flou, calques plein écran
------------------------------------------------------------------------------------

local NEUTRAL = {
	TintColor = Color3.new(1, 1, 1),
	Saturation = 0,
	Contrast = 0,
	Brightness = 0,
}

local function setTint(props: { [string]: any }, duration: number)
	tintToken += 1
	tint.Enabled = true
	Motion.Tween(tint, props, duration, Enum.EasingStyle.Sine)
end

local function clearTint()
	tintToken += 1
	local token = tintToken
	Motion.Tween(tint, NEUTRAL, 0.6, Enum.EasingStyle.Sine).Completed:Once(function()
		if token == tintToken then
			tint.Enabled = false
		end
	end)
end

local function screenRoot(name: string): Frame
	return New("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = fxGui,
	})
end

-- Fait disparaître un calque puis le détruit.
local function fadeAndDestroy(root: Instance, duration: number)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			Motion.Tween(d, { TextTransparency = 1 }, duration)
		elseif d:IsA("Frame") then
			Motion.Tween(d, { BackgroundTransparency = 1 }, duration)
		end
	end
	task.delay(duration + 0.05, function()
		root:Destroy()
	end)
end

local function edgeGlow(parent: Instance, color: Color3, rotation: number, strength: number): Frame
	return New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		New("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, strength),
				NumberSequenceKeypoint.new(0.22, 1),
				NumberSequenceKeypoint.new(0.78, 1),
				NumberSequenceKeypoint.new(1, strength),
			}),
		}),
	})
end

local function wash(parent: Instance, color: Color3, transparency: number): Frame
	return New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

------------------------------------------------------------------------------------
-- FREEZE
------------------------------------------------------------------------------------

local function freezeEffect(): Effect
	setTint({
		TintColor = Color3.fromRGB(205, 232, 255),
		Saturation = -0.35,
		Contrast = 0.05,
		Brightness = 0.04,
	}, 0.4)
	local root = screenRoot("Freeze")
	local ice = Color3.fromHex("DFF3FF")
	wash(root, Color3.fromHex("9FD8FF"), 0.86)
	edgeGlow(root, ice, 90, 0.35)
	edgeGlow(root, ice, 0, 0.45)
	local glass: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(90, 90),
		BackgroundTransparency = 1,
		Text = "⌛",
		TextScaled = true,
		TextTransparency = 0.15,
		Parent = root,
	})
	Audio.Play("Whoosh", 0.5)
	Audio.Play("Error", 0.6)
	return {
		Update = function(elapsed: number, _dt: number)
			if Motion.IsReduced() then
				glass.Rotation = 0
				return
			end
			-- Le sablier se retourne toutes les 1,5 s.
			local cycle = elapsed % 1.5
			local flips = math.floor(elapsed / 1.5)
			local turn = math.clamp((cycle - 1.1) / 0.4, 0, 1)
			glass.Rotation = (flips + turn) * 180
		end,
		Stop = function()
			fadeAndDestroy(root, 0.4)
			clearTint()
		end,
	}
end

------------------------------------------------------------------------------------
-- MISE À JOUR (Windows Update surprise : voile bleu, pourcentage qui grimpe, « ne pas éteindre »)
------------------------------------------------------------------------------------

local function updateEffect(duration: number): Effect
	local root = screenRoot("Update")
	wash(root, Color3.fromHex("0078D7"), 0.42)
	local face: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(160, 120),
		BackgroundTransparency = 1,
		Text = ":(",
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		Parent = root,
	})
	local line: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0, 44),
		BackgroundTransparency = 1,
		Text = "Mise à jour en cours… 0 %",
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamMedium,
		Parent = root,
	})
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.new(0.8, 0, 0, 30),
		BackgroundTransparency = 1,
		Text = "Ne pas éteindre votre ordinateur.",
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.2,
		Font = Enum.Font.Gotham,
		Parent = root,
	})
	Audio.Play("Toast", 0.8)
	local shown = -1
	return {
		Update = function(elapsed: number, _dt: number)
			-- Le pourcentage avance par paliers irréguliers, comme le vrai
			local percent = math.clamp(math.floor(100 * elapsed / math.max(duration, 0.1) / 7) * 7, 0, 100)
			if percent ~= shown then
				shown = percent
				line.Text = `Mise à jour en cours… {percent} %`
			end
			face.TextTransparency = if Motion.IsReduced() then 0 else 0.1 + 0.1 * math.sin(elapsed * 3)
		end,
		Stop = function()
			fadeAndDestroy(root, 0.3)
		end,
	}
end

------------------------------------------------------------------------------------
-- LAG SPIKE
------------------------------------------------------------------------------------

local function spinner(parent: Instance, position: UDim2, size: number): Frame
	local wheel: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.4, 0.5 + math.sin(angle) * 0.4),
			Size = UDim2.fromScale(0.16, 0.16),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.1 + i / 8 * 0.8,
			BorderSizePixel = 0,
			Parent = wheel,
		}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance })
	end
	return wheel
end

local function lagEffect(): Effect
	setTint({ TintColor = Color3.fromRGB(255, 238, 215), Contrast = 0.18, Saturation = -0.1 }, 0.3)
	local root = screenRoot("Lag")
	local wheel = spinner(root, UDim2.fromScale(0.5, 0.36), 64)
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 40),
		Size = UDim2.fromOffset(260, 28),
		BackgroundTransparency = 1,
		Text = "Chargement…",
		TextScaled = true,
		FontFace = Style.Fonts.Heavy,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		Parent = root,
	})
	local tears: { Frame } = {}
	for _ = 1, 3 do
		table.insert(
			tears,
			New("Frame", {
				Size = UDim2.new(1, 0, 0, 10),
				BackgroundColor3 = Color3.fromHex("F6AD55"),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
				Visible = false,
				Parent = root,
			})
		)
	end
	local lastStep = -1
	local holdUntil = 0
	Audio.Play("Error", 0.6)
	return {
		Update = function(elapsed: number, _dt: number)
			local step = math.floor(elapsed / Incidents.LagStep)
			if step ~= lastStep then
				lastStep = step
				wheel.Rotation += 45
				if not Motion.IsReduced() then
					-- Un « à-coup » : l'image se brouille une fraction de seconde, en rythme
					-- avec les pièges (TrapClock avance par pas de LagStep).
					blur.Enabled = true
					blur.Size = 6
					holdUntil = os.clock() + 0.07
					for _, tear in tears do
						tear.Visible = true
						tear.Position = UDim2.new((math.random() - 0.5) * 0.05, 0, math.random(), 0)
						tear.Size = UDim2.new(1, 0, 0, math.random(4, 16))
					end
				end
			end
			if os.clock() > holdUntil and blur.Size > 0 then
				blur.Size = 0
				for _, tear in tears do
					tear.Visible = false
				end
			end
		end,
		Stop = function()
			blur.Size = 0
			blur.Enabled = false
			fadeAndDestroy(root, 0.3)
			clearTint()
		end,
	}
end

------------------------------------------------------------------------------------
-- BLACKOUT (éclairage local, restauré à la fin)
------------------------------------------------------------------------------------

type LightSave = {
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ExposureCompensation: number,
	EnvironmentDiffuseScale: number,
	EnvironmentSpecularScale: number,
	AtmosphereColor: Color3?,
	AtmosphereDecay: Color3?,
	BloomIntensity: number?,
}

local lightSave: LightSave? = nil
local lightToken = 0

local function atmosphere(): Atmosphere?
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function bloom(): BloomEffect?
	return Lighting:FindFirstChildOfClass("BloomEffect")
end

local function captureLighting(): LightSave
	local atmo = atmosphere()
	local glow = bloom()
	return {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ExposureCompensation = Lighting.ExposureCompensation,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
		AtmosphereColor = if atmo then atmo.Color else nil,
		AtmosphereDecay = if atmo then atmo.Decay else nil,
		BloomIntensity = if glow then glow.Intensity else nil,
	}
end

local function tweenLighting(save: LightSave, dark: boolean, duration: number): Tween
	local atmo = atmosphere()
	local glow = bloom()
	if atmo and save.AtmosphereColor and save.AtmosphereDecay then
		Motion.Tween(atmo, {
			Color = if dark then Color3.fromRGB(12, 12, 20) else save.AtmosphereColor,
			Decay = if dark then Color3.fromRGB(8, 8, 14) else save.AtmosphereDecay,
		}, duration)
	end
	if glow and save.BloomIntensity then
		Motion.Tween(glow, { Intensity = if dark then 1 else save.BloomIntensity }, duration)
	end
	return Motion.Tween(Lighting, {
		Brightness = if dark then 0 else save.Brightness,
		Ambient = if dark then Color3.fromRGB(10, 10, 18) else save.Ambient,
		OutdoorAmbient = if dark then Color3.fromRGB(12, 12, 20) else save.OutdoorAmbient,
		ExposureCompensation = if dark then -0.6 else save.ExposureCompensation,
		EnvironmentDiffuseScale = if dark then 0.1 else save.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = if dark then 0.2 else save.EnvironmentSpecularScale,
	}, duration, Enum.EasingStyle.Sine)
end

local function trapWorld(instance: Instance): number
	local world = instance:GetAttribute("World")
	return if type(world) == "number" then world else 0
end

local function blackoutEffect(world: number): Effect
	lightToken += 1
	local save = lightSave or captureLighting()
	lightSave = save
	tweenLighting(save, true, if Motion.IsReduced() then 0.01 else 0.8)
	setTint({ TintColor = Color3.fromRGB(190, 200, 235), Saturation = -0.25 }, 0.8)
	Audio.Play("Zap", 0.6)

	-- Petite lueur autour du joueur : on voit toujours où on met les pieds.
	local glow: PointLight? = nil
	local function ensureGlow()
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end
		if glow and glow.Parent == rootPart then
			return
		end
		if glow then
			glow:Destroy()
		end
		glow = New("PointLight", {
			Name = "BlackoutGlow",
			Range = 18,
			Brightness = 1.4,
			Color = Color3.fromRGB(205, 215, 255),
			Shadows = false,
			Parent = rootPart,
		})
	end
	ensureGlow()

	-- Les dangers les plus proches restent visibles (contour rouge, 16 au plus).
	local highlights: { Highlight } = {}
	local function clearHighlights()
		for _, highlight in highlights do
			highlight:Destroy()
		end
		table.clear(highlights)
	end
	local function refreshHighlights()
		clearHighlights()
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local nearby: { { Target: PVInstance, Distance: number } } = {}
		for _, trap in CollectionService:GetTagged("Trap") do
			local kind = trap:GetAttribute("Kind")
			if trap:IsA("PVInstance") and trapWorld(trap) == world and type(kind) == "string" and LETHAL[kind] then
				local distance = (trap:GetPivot().Position - eye).Magnitude
				if distance < 160 then
					table.insert(nearby, { Target = trap, Distance = distance })
				end
			end
		end
		table.sort(nearby, function(a, b)
			return a.Distance < b.Distance
		end)
		for index = 1, math.min(#nearby, 16) do
			local target = nearby[index].Target
			table.insert(
				highlights,
				New("Highlight", {
					Name = "BlackoutDanger",
					Adornee = target,
					FillColor = Style.Color("Danger"),
					FillTransparency = 0.75,
					OutlineColor = Style.Color("Danger"),
					OutlineTransparency = 0.1,
					DepthMode = Enum.HighlightDepthMode.Occluded,
					Parent = target,
				})
			)
		end
	end
	refreshHighlights()
	local nextRefresh = 1.5

	return {
		Update = function(elapsed: number, _dt: number)
			ensureGlow()
			if elapsed >= nextRefresh then
				nextRefresh = elapsed + 1.5
				refreshHighlights()
			end
		end,
		Stop = function()
			clearHighlights()
			if glow then
				glow:Destroy()
				glow = nil
			end
			clearTint()
			lightToken += 1
			local token = lightToken
			task.spawn(function()
				-- Clignotement de reprise du courant, puis retour à la normale.
				if not Motion.IsReduced() then
					for _ = 1, 2 do
						if token ~= lightToken then
							return
						end
						Lighting.ExposureCompensation = save.ExposureCompensation
						Lighting.Brightness = save.Brightness
						task.wait(0.08)
						if token ~= lightToken then
							return
						end
						Lighting.ExposureCompensation = -0.6
						Lighting.Brightness = 0
						task.wait(0.12)
					end
				end
				if token ~= lightToken then
					return
				end
				Audio.Play("PowerOn", 1.1)
				tweenLighting(save, false, 0.6).Completed:Once(function()
					if token == lightToken then
						lightSave = nil
					end
				end)
			end)
		end,
	}
end

------------------------------------------------------------------------------------
-- POP-UP STORM
------------------------------------------------------------------------------------

local ADS = {
	{ Emoji = "🎉", Title = "FÉLICITATIONS !", Text = "Tu es le 1 000 000ᵉ visiteur ! (c'est faux)" },
	{ Emoji = "🐱", Title = "OFFRE SPÉCIALE", Text = "Des chatons GRATUITS ! Clique vite !" },
	{ Emoji = "💾", Title = "PUB !!!", Text = "Télécharge plus de RAM ! (ça n'existe pas)" },
	{ Emoji = "🍕", Title = "NOUVEAU !", Text = "Pizza livrée dans ta tour PC en 3 secondes !" },
	{ Emoji = "😎", Title = "PROMO", Text = "Lunettes anti-lag : +1000 FPS garantis !" },
	{ Emoji = "🦄", Title = "PUB !!!", Text = "PC trop lent ? Achète une licorne !" },
	{ Emoji = "🏆", Title = "BRAVO !", Text = "Tu as gagné… une autre pub !" },
}
local AD_COLORS = { "ED64A6", "F6AD55", "4FD1C5", "8B7CFF", "68D391" }
local AD_SIZE = Vector2.new(300, 190)
-- Zone où rebondissent les pubs (centres, en proportion de l'écran) : loin du joystick
-- (bas gauche), du bouton de saut (bas droite), du menu et des actions (droite).
local AD_MIN = Vector2.new(0.34, 0.3)
local AD_MAX = Vector2.new(0.66, 0.58)

type Ad = { Root: Frame, Velocity: Vector2, Pos: Vector2, Closed: boolean }

local function popupEffect(layer: Frame): Effect
	local ads: { Ad } = {}
	local count = math.random(3, 5)
	local closed = 0
	local finished = false
	local root: Frame = New("Frame", {
		Name = "PopupStorm",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	local function closeAd(ad: Ad, byPlayer: boolean)
		if ad.Closed then
			return
		end
		ad.Closed = true
		local scale = Motion.ScaleOf(ad.Root)
		Motion.Tween(scale, { Scale = 0 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.25, function()
			ad.Root:Destroy()
		end)
		if byPlayer then
			closed += 1
			Audio.Play("Collect", 1 + closed * 0.08)
			if closed >= count and not finished then
				Audio.Play("Upgrade")
				Toasts.Show("Success", "Toutes les pubs sont fermées. Bien joué !")
			end
		end
	end
	local function spawnAd(index: number)
		if finished then
			return
		end
		local info = ADS[math.random(1, #ADS)]
		local accent = Color3.fromHex(AD_COLORS[math.random(1, #AD_COLORS)])
		local pos = Vector2.new(
			AD_MIN.X + math.random() * (AD_MAX.X - AD_MIN.X),
			AD_MIN.Y + math.random() * (AD_MAX.Y - AD_MIN.Y)
		)
		local window: Frame = New("Frame", {
			Name = `Ad{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(pos.X, pos.Y),
			Size = UDim2.fromOffset(AD_SIZE.X, AD_SIZE.Y),
			BorderSizePixel = 0,
			ZIndex = 10 + index,
			Tag = { "FillWhite", "RoundM" },
			Parent = root,
		}, {
			New("UIStroke", { Color = accent, Thickness = 4 }) :: Instance,
			New("UIShadow", {
				BlurRadius = UDim.new(0, 18),
				Transparency = 0.4,
				Offset = UDim2.fromOffset(0, 6),
				Color = Style.Color("BgDeep"),
			}),
		})
		local header: Frame = New("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Parent = window,
		}, { New("UICorner", { CornerRadius = UDim.new(0, 12) }) :: Instance })
		New("TextLabel", {
			Position = UDim2.fromOffset(14, 4),
			Size = UDim2.new(1, -90, 1, -8),
			BackgroundTransparency = 1,
			Text = info.Title,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Style.Fonts.Heavy,
			TextColor3 = Color3.new(1, 1, 1),
			Parent = header,
		}, { New("UITextSizeConstraint", { MaxTextSize = 20 }) :: Instance })
		New("TextLabel", {
			Position = UDim2.fromOffset(12, 50),
			Size = UDim2.fromOffset(64, 64),
			BackgroundTransparency = 1,
			Text = info.Emoji,
			TextScaled = true,
			Parent = window,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(86, 50),
			Size = UDim2.new(1, -98, 1, -62),
			BackgroundTransparency = 1,
			Text = info.Text,
			TextScaled = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Style.Fonts.Bold,
			TextColor3 = Style.Color("BgDeep"),
			Parent = window,
		}, { New("UITextSizeConstraint", { MaxTextSize = 20 }) :: Instance })
		-- Le gros ✕ : 88 px de conception ≈ 46 px réels sur le plus petit téléphone (échelle 0,52).
		local close: TextButton = New("TextButton", {
			Name = "Close",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(88, 88),
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			ZIndex = 2,
			Tag = { "FillBrand", "RoundPill" },
			Parent = window,
		}, { New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3 }) :: Instance })
		local cross = Icon.new("Close", 34, "TextPrimary")
		cross.AnchorPoint = Vector2.new(0.5, 0.5)
		cross.Position = UDim2.fromScale(0.5, 0.5)
		cross.ZIndex = 3
		cross.Parent = close
		Motion.Pressable(close)
		local angle = math.random() * math.pi * 2
		local speed = 0.05 + math.random() * 0.05
		local ad: Ad = {
			Root = window,
			Velocity = Vector2.new(math.cos(angle), math.sin(angle)) * speed,
			Pos = pos,
			Closed = false,
		}
		close.Activated:Connect(function()
			closeAd(ad, true)
		end)
		table.insert(ads, ad)
		local scale = Motion.ScaleOf(window)
		scale.Scale = 0.2
		Motion.Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
		Audio.Play("Toast", 1.3 + index * 0.05)
	end
	for index = 1, count do
		task.delay((index - 1) * 0.35, spawnAd, index)
	end
	return {
		Update = function(_elapsed: number, dt: number)
			if Motion.IsReduced() then
				return
			end
			for _, ad in ads do
				if not ad.Closed then
					local pos = ad.Pos + ad.Velocity * dt
					local velocity = ad.Velocity
					if pos.X < AD_MIN.X or pos.X > AD_MAX.X then
						velocity = Vector2.new(-velocity.X, velocity.Y)
					end
					if pos.Y < AD_MIN.Y or pos.Y > AD_MAX.Y then
						velocity = Vector2.new(velocity.X, -velocity.Y)
					end
					ad.Velocity = velocity
					ad.Pos = Vector2.new(math.clamp(pos.X, AD_MIN.X, AD_MAX.X), math.clamp(pos.Y, AD_MIN.Y, AD_MAX.Y))
					ad.Root.Position = UDim2.fromScale(ad.Pos.X, ad.Pos.Y)
				end
			end
		end,
		Stop = function()
			finished = true
			for _, ad in ads do
				closeAd(ad, false)
			end
			task.delay(0.4, function()
				root:Destroy()
			end)
		end,
	}
end

------------------------------------------------------------------------------------
-- CORRUPTION
------------------------------------------------------------------------------------

local function corruptionEffect(): Effect
	setTint({ TintColor = Color3.fromRGB(255, 222, 246), Saturation = 0.2, Contrast = 0.1 }, 0.3)
	local root = screenRoot("Corruption")
	local grid: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		New("UIGridLayout", {
			CellSize = UDim2.fromScale(1 / 12, 1 / 7),
			CellPadding = UDim2.new(),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}) :: Instance,
	})
	local magenta = Color3.fromHex("FF00DC")
	local black = Color3.new(0, 0, 0)
	local cells: { Frame } = {}
	for row = 0, 6 do
		for col = 0, 11 do
			table.insert(
				cells,
				New("Frame", {
					BackgroundColor3 = if (row + col) % 2 == 0 then magenta else black,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					LayoutOrder = row * 12 + col,
					Parent = grid,
				})
			)
		end
	end
	local label: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromOffset(420, 44),
		BackgroundTransparency = 1,
		Text = "TEXTURE MANQUANTE ?!",
		TextScaled = true,
		FontFace = Style.Fonts.Heavy,
		TextColor3 = magenta,
		TextStrokeColor3 = black,
		TextStrokeTransparency = 0.2,
		TextTransparency = 0.1,
		Parent = root,
	})
	local alpha = -1
	local function setAlpha(value: number)
		if value == alpha then
			return
		end
		alpha = value
		for _, cell in cells do
			cell.BackgroundTransparency = value
		end
	end
	Audio.Play("Error", 1.3)
	return {
		Update = function(elapsed: number, _dt: number)
			if Motion.IsReduced() then
				setAlpha(0.9)
				return
			end
			-- Deux flashs au début (2 par seconde au plus), puis un léger voile avec un petit
			-- glitch toutes les 1,4 s.
			local flash = (elapsed < 0.2) or (elapsed >= 0.5 and elapsed < 0.7)
			local glitch = elapsed > 1 and (elapsed % 1.4) < 0.1
			setAlpha(if flash then 0.5 elseif glitch then 0.75 else 0.9)
			label.Position = UDim2.new(0.5, if glitch then math.random(-6, 6) else 0, 0.34, 0)
		end,
		Stop = function()
			fadeAndDestroy(root, 0.3)
			clearTint()
		end,
	}
end

------------------------------------------------------------------------------------
-- SURCHAUFFE
------------------------------------------------------------------------------------

local function overheatEffect(): Effect
	setTint({ TintColor = Color3.fromRGB(255, 205, 185), Saturation = 0.25, Contrast = 0.1 }, 0.5)
	Material.SetThermalStress(1)
	local root = screenRoot("Overheat")
	local heat = Color3.fromHex("FF7A45")
	edgeGlow(root, Color3.fromHex("FF4E34"), 90, 0.55)
	local bands: { { Frame: Frame, Y: number, Speed: number, Phase: number } } = {}
	for i = 1, 6 do
		local frame: Frame = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, i / 6),
			Size = UDim2.new(1.2, 0, 0.06, 0),
			BackgroundColor3 = heat,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Parent = root,
		}, {
			New("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
			}) :: Instance,
		})
		table.insert(
			bands,
			{ Frame = frame, Y = i / 6, Speed = 0.08 + math.random() * 0.06, Phase = math.random() * 6 }
		)
	end
	Audio.Play("Error", 0.8)
	task.delay(0.6, function()
		Audio.Play("Error", 0.8)
	end)
	return {
		Update = function(elapsed: number, dt: number)
			if Motion.IsReduced() then
				return
			end
			-- Ondes de chaleur qui montent en ondulant + léger flou qui « respire ».
			for _, band in bands do
				band.Y -= band.Speed * dt
				if band.Y < -0.05 then
					band.Y = 1.05
				end
				local wobble = math.sin(elapsed * 3 + band.Phase) * 0.015
				band.Frame.Position = UDim2.fromScale(0.5 + wobble, band.Y)
			end
			blur.Enabled = true
			blur.Size = 1.5 + math.sin(elapsed * 4) * 1
		end,
		Stop = function()
			Material.SetThermalStress(0)
			blur.Size = 0
			blur.Enabled = false
			fadeAndDestroy(root, 0.5)
			clearTint()
		end,
	}
end

------------------------------------------------------------------------------------
-- Bandeau d'annonce
------------------------------------------------------------------------------------

local function buildBanner(layer: Frame)
	-- Calque « Alerts » (au-dessus de Moments) : le bandeau n'est jamais caché par une bannière
	-- ou une carte de médaille. Repli : le calque reçu (Overlays).
	local root = layer.Parent
	local alerts = if root then root:FindFirstChild("Alerts") else nil
	local target: Instance = if alerts and alerts:IsA("Frame") then alerts else layer
	banner = New("Frame", {
		Name = "IncidentBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		-- Sous la carte de progression (12..108) et la pastille des clés (114..140) ; les
		-- notifications passent dessous tant qu'il est affiché (Toasts.SetInset).
		Position = UDim2.new(0.5, 0, 0, 148),
		Size = UDim2.fromOffset(540, 84),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 40,
		Tag = { "Glass", "RoundL" },
		Parent = target,
	})
	bannerStroke = New("UIStroke", { Color = Lagz.Color, Thickness = 3, Parent = banner })
	local bubble: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Lagz.Dark,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = banner,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		New("UIStroke", { Color = Lagz.Color, Thickness = 2 }) :: Instance,
	})
	local face = Lagz.Face(54, bubble)
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.52)
	face.ZIndex = 42
	bannerTitle = New("TextLabel", {
		Position = UDim2.fromOffset(88, 10),
		Size = UDim2.new(1, -160, 0, 32),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextPrimary"),
		ZIndex = 41,
		Tag = "FontHeavy",
		Parent = banner,
	}, { New("UITextSizeConstraint", { MaxTextSize = 26 }) :: Instance })
	bannerSub = New("TextLabel", {
		Position = UDim2.fromOffset(88, 44),
		Size = UDim2.new(1, -160, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Style.Color("TextPrimary"),
		TextTransparency = 0.1,
		ZIndex = 41,
		Tag = "FontBold",
		Parent = banner,
	}, { New("UITextSizeConstraint", { MaxTextSize = 18 }) :: Instance })
	bannerCount = New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextColor3 = Style.Color("CurrencyBits"),
		ZIndex = 41,
		Tag = "FontDisplay",
		Parent = banner,
	})
	bannerTrack = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -36, 0, 5),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 41,
		Tag = { "GlassSunken", "RoundPill" },
		Parent = banner,
	})
	bannerFill = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Lagz.Color,
		BorderSizePixel = 0,
		ZIndex = 42,
		Tag = "RoundPill",
		Parent = bannerTrack,
	})
end

local function showBanner(kind: string, phase: string)
	local def = Incidents.ByKind[kind]
	local accent = if def then Color3.fromHex(def.Color) else Lagz.Color
	-- Le noir du BLACKOUT serait invisible sur le verre : violet de LAGZ à la place.
	if kind == "Blackout" then
		accent = Lagz.Color
	end
	bannerStroke.Color = accent
	bannerFill.BackgroundColor3 = accent
	if phase == "Warn" then
		bannerTitle.Text = `⚠ LAGZ prépare {ARTICLE[kind] or "un"} {shortName(kind)} !`
		bannerSub.Text = if def then def.Warning else ""
		bannerTrack.Visible = false
	else
		bannerTitle.Text = if def then def.Title else shortName(kind)
		bannerSub.Text = HINT[kind] or ""
		bannerCount.Text = ""
		bannerTrack.Visible = true
	end
	if not banner.Visible then
		banner.Visible = true
		banner.BackgroundTransparency = 0.08
		Toasts.SetInset(84 + 8)
	end
	Motion.Pop(banner, 0.08)
end

local function hideBanner()
	banner.Visible = false
	Toasts.SetInset(0)
end

------------------------------------------------------------------------------------
-- Boucle
------------------------------------------------------------------------------------

-- Monde où je cours (0 = lobby, départ, mini-jeu).
function IncidentController.LocalWorld(): number
	local state = Store.State
	if not state or state.AtLobby or IncidentController.IsBusy() then
		return 0
	end
	local data = state.Data
	if not data.RunStarted then
		return 0
	end
	return Tower.RunWorld(data.Stage, data.Cleared)
end

local function readWorld(world: number): (string, number, number, number)
	local folder = stateFolder
	if not folder or world <= 0 then
		return "", 0, 0, 0
	end
	local kind = folder:GetAttribute(`Kind{world}`)
	local warn = folder:GetAttribute(`Warn{world}`)
	local start = folder:GetAttribute(`Start{world}`)
	local finish = folder:GetAttribute(`End{world}`)
	if type(kind) ~= "string" or type(warn) ~= "number" or type(start) ~= "number" or type(finish) ~= "number" then
		return "", 0, 0, 0
	end
	return kind, warn, start, finish
end

local function startEffect(active: Current, layer: Frame)
	local kind = active.Kind
	local effect: Effect? = nil
	if kind == "Freeze" then
		effect = freezeEffect()
	elseif kind == "Lag" then
		effect = lagEffect()
	elseif kind == "Blackout" then
		effect = blackoutEffect(active.World)
	elseif kind == "Popups" then
		effect = popupEffect(layer)
	elseif kind == "Corruption" then
		effect = corruptionEffect()
	elseif kind == "Overheat" then
		effect = overheatEffect()
	elseif kind == "Update" then
		local def = Incidents.ByKind[kind]
		effect = updateEffect(if def then def.Duration else 5)
	end
	active.Effect = effect
end

local function stop(active: Current)
	local effect = active.Effect
	active.Effect = nil
	if effect then
		xpcall(effect.Stop, function(err: any)
			warn("[IncidentController] arrêt :", err)
		end)
	end
	hideBanner()
end

local function tick(layer: Frame)
	local world = IncidentController.LocalWorld()
	local kind, warnAt, start, finish = readWorld(world)
	local now = Workspace:GetServerTimeNow()
	local phase = IncidentSchedule.Phase(kind, warnAt, start, finish, now)
	local key = if phase ~= "" then `{world}|{kind}|{warnAt}` else ""
	local previous = current
	if previous and previous.Key ~= key then
		current = nil
		stop(previous)
	end
	if phase == "" then
		return
	end
	local active: Current = current
		or {
			Key = key,
			World = world,
			Kind = kind,
			Warn = warnAt,
			Start = start,
			End = finish,
			Phase = "",
			Effect = nil,
			LastCount = -1,
			LastElapsed = 0,
		}
	current = active
	if active.Phase ~= phase then
		active.Phase = phase
		showBanner(kind, phase)
		if phase == "Warn" then
			Audio.Play("Error", 1.15)
		else
			startEffect(active, layer)
		end
	end
	if phase == "Warn" then
		local count = math.max(math.ceil(start - now), 1)
		if count ~= active.LastCount then
			active.LastCount = count
			bannerCount.Text = tostring(count)
			Motion.Pop(bannerCount, 0.25)
			Audio.Play("Click", 1.3)
		end
	else
		local duration = math.max(finish - start, 0.01)
		bannerFill.Size = UDim2.fromScale(math.clamp(1 - (now - start) / duration, 0, 1), 1)
		local elapsed = now - start
		local dt = math.clamp(elapsed - active.LastElapsed, 0, 0.1)
		active.LastElapsed = elapsed
		local effect = active.Effect
		if effect then
			effect.Update(elapsed, dt)
		end
	end
end

-- Incident en cours pour moi : type, phase ("" | "Warn" | "Active") et avancement 0..1.
function IncidentController.Current(): (string, string, number)
	local active = current
	if not active then
		return "", "", 0
	end
	local progress = 0
	if active.Phase == "Active" then
		local now = Workspace:GetServerTimeNow()
		progress = math.clamp((now - active.Start) / math.max(active.End - active.Start, 0.01), 0, 1)
	end
	return active.Kind, active.Phase, progress
end

function IncidentController.Start(layer: Frame)
	fxGui = New("ScreenGui", {
		Name = "AngAInOneIncidentFx",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5, -- sous l'interface principale (10) : le HUD reste net et cliquable
		Parent = player:WaitForChild("PlayerGui"),
	})
	tint = New("ColorCorrectionEffect", {
		Name = "IncidentTint",
		Enabled = false,
		Parent = Lighting,
	})
	blur = New("BlurEffect", {
		Name = "IncidentBlur",
		Size = 0,
		Enabled = false,
		Parent = Lighting,
	})
	buildBanner(layer)

	task.spawn(function()
		stateFolder = ReplicatedStorage:WaitForChild(Incidents.StateFolder, math.huge)
	end)

	RunService.Heartbeat:Connect(function()
		xpcall(tick, function(err: any)
			errors += 1
			if errors <= 3 then
				warn("[IncidentController]", err)
			end
			local active = current
			current = nil
			if active then
				task.defer(stop, active)
			end
		end, layer)
	end)
end

return IncidentController
