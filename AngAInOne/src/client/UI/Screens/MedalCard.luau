--!strict
--[[
	MedalCard : carte « Rapport du monde » au style de l'app AngAInOne (gris Fluent + violet),
	affichée après le moment « monde nettoyé » (Feedback, effet WorldCleared).
	- Médaille bronze / argent / or dessinée en Frames et dégradés (aucune image)
	- Temps du monde, morts, clés USB du monde
	- Prochaine médaille à viser (seuil de temps et de morts), ou le record si c'est déjà l'or
	- Pastille « Nouveau record ! »
	Se ferme toute seule (ou d'un clic / d'un toucher).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local Medals = require(Shared.Config.Medals)
local MedalLogic = require(Shared.Util.MedalLogic)
local Time = require(Shared.Util.Time)

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)

local New = Create.New
local APP = Branding.PartnerApp

local MedalCard = {}

local SHOW_SECONDS = 6.5
local WIDTH, HEIGHT = 440, 158

local TITLES: { [string]: string } = {
	Gold = "MÉDAILLE D'OR",
	Silver = "MÉDAILLE D'ARGENT",
	Bronze = "MÉDAILLE DE BRONZE",
}

local layer: Frame? = nil
local current: Frame? = nil

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local VIOLET = Style.Color("AccentViolet")

local function label(parent: Instance, props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	props.FontFace = props.FontFace or Style.Fonts.Medium
	props.TextColor3 = props.TextColor3 or hex(APP.Text)
	props.TextSize = props.TextSize or 15
	props.TextTruncate = Enum.TextTruncate.AtEnd
	props.Parent = parent
	return New("TextLabel", props)
end

-- Médaille dessinée : ruban violet (couleurs de l'app), disque en dégradé, anneau, étoile.
function MedalCard.Icon(medal: string, size: number): Frame
	local colors = (Medals.Colors :: any)[medal] or Medals.Colors.Bronze
	local light, base, shadow = hex(colors[1]), hex(colors[2]), hex(colors[3])
	local holder: Frame = New("Frame", {
		Name = "Medal",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	})
	-- Ruban : deux bandes inclinées derrière le disque.
	for index, angle in { -24, 24 } do
		New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(if index == 1 then 0.36 else 0.64, 0.48),
			Size = UDim2.fromScale(0.26, 0.52),
			Rotation = angle,
			BackgroundColor3 = if index == 1 then VIOLET else VIOLET:Lerp(Color3.new(0, 0, 0), 0.3),
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = holder,
		})
	end
	local disc: Frame = New("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.78, 0.78),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = holder,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		New("UIGradient", {
			Rotation = 45,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, light),
				ColorSequenceKeypoint.new(0.45, base),
				ColorSequenceKeypoint.new(1, shadow),
			}),
		}),
		New("UIStroke", { Color = shadow, Thickness = math.max(2, size / 24) }),
	})
	New("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = disc,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance,
		New("UIStroke", { Color = light, Thickness = math.max(1, size / 36), Transparency = 0.2 }),
	})
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.6, 0.6),
		BackgroundTransparency = 1,
		Text = "★",
		TextScaled = true,
		FontFace = Style.Fonts.Heavy,
		TextColor3 = shadow,
		ZIndex = 4,
		Parent = disc,
	})
	return holder
end

-- Texte de l'objectif suivant (ou du record si l'or est déjà gagné).
local function goalText(world: number, payload: any): string
	local medal = payload.Medal or "Bronze"
	local time = if type(payload.Time) == "number" then payload.Time else 0
	if payload.Assisted then
		return "Aide utilisée dans ce monde : médaille gardée, pas de record."
	end
	local goal = MedalLogic.NextGoal(world, medal)
	if not goal then
		local best = if type(payload.Best) == "number" then payload.Best else 0
		return if best > 0 then `Médaille maximale ! Record du monde : {Time.Clock(best)}` else "Médaille maximale !"
	end
	local target = if goal.Medal == "Gold" then "Pour l'or" else "Pour l'argent"
	local text = `{target} : moins de {Time.Clock(goal.Time)} et {goal.Deaths} morts max`
	if time > goal.Time then
		text ..= ` (encore {math.ceil(time - goal.Time)} s à gagner)`
	elseif (payload.Deaths or 0) > goal.Deaths then
		text ..= " (tu y es presque : moins de chutes !)"
	end
	return text
end

-- Fondu de sortie (textes, fonds opaques, contours), puis destruction.
local function dismiss(card: Frame)
	if current == card then
		current = nil
	end
	if not card.Parent then
		return
	end
	local duration = 0.3
	for _, d in card:GetDescendants() do
		if d:IsA("TextLabel") then
			Motion.Tween(d, { TextTransparency = 1 }, duration)
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			Motion.Tween(d, { BackgroundTransparency = 1 }, duration)
		elseif d:IsA("UIStroke") then
			Motion.Tween(d, { Transparency = 1 }, duration)
		end
	end
	Motion.Tween(card, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.3, -16) }, duration).Completed
		:Once(function()
			card:Destroy()
		end)
end

-- Affiche la carte d'un monde nettoyé (payload de l'effet serveur « WorldCleared »).
function MedalCard.Show(payload: any)
	local target = layer
	local world = if type(payload) == "table" then payload.World else nil
	if not target or type(world) ~= "number" or type(payload.Medal) ~= "string" then
		return
	end
	if current then
		current:Destroy()
		current = nil
	end
	local def = Tower.Worlds[world]
	local medal: string = payload.Medal
	local colors = (Medals.Colors :: any)[medal] or Medals.Colors.Bronze
	local newBest = payload.NewBest == true

	-- Fenêtre de l'app : fond Fluent, contour violet.
	local card: Frame = New("Frame", {
		Name = "MedalCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 30),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundColor3 = hex(APP.Surface),
		BorderSizePixel = 0,
		Parent = target,
	}, {
		Create.Corner(12) :: Instance,
		New("UIStroke", { Color = VIOLET, Transparency = 0.35, Thickness = 1.5 }),
	})
	current = card

	-- Barre de titre.
	local titleBar: Frame = New("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = hex(APP.Card),
		BorderSizePixel = 0,
		Parent = card,
	}, { Create.Corner(12) :: Instance })
	New("Frame", {
		Position = UDim2.new(0, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = hex(APP.Card),
		BorderSizePixel = 0,
		Parent = titleBar,
	})
	New("Frame", {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = VIOLET,
		BorderSizePixel = 0,
		Parent = titleBar,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance })
	label(titleBar, {
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Text = `{APP.Name} · Rapport du monde {world}`,
		TextColor3 = hex(APP.TextDim),
		TextSize = 13,
		FontFace = Style.Fonts.Bold,
	})

	local icon = MedalCard.Icon(medal, 92)
	icon.Position = UDim2.fromOffset(16, 42)
	icon.Parent = card

	local left = 124
	local body = UDim2.new(1, -(left + 14), 0, 0)
	-- Le titre laisse la place à la pastille « Nouveau record ! ».
	local titleWidth = if newBest then body - UDim2.fromOffset(136, 0) else body
	label(card, {
		Position = UDim2.fromOffset(left, 38),
		Size = titleWidth + UDim2.fromOffset(0, 26),
		Text = TITLES[medal] or string.upper(medal),
		TextColor3 = hex(colors[1]),
		TextSize = 20,
		FontFace = Style.Fonts.Heavy,
	})
	label(card, {
		Position = UDim2.fromOffset(left, 64),
		Size = body + UDim2.fromOffset(0, 18),
		Text = `Monde {world} · {if def then def.Name else ""}`,
		TextColor3 = hex(APP.TextDim),
		TextSize = 14,
	})
	local time = if type(payload.Time) == "number" then payload.Time else 0
	local keys = if type(payload.Keys) == "number" then payload.Keys else 0
	local deaths = if type(payload.Deaths) == "number" then payload.Deaths else 0
	label(card, {
		Position = UDim2.fromOffset(left, 86),
		Size = body + UDim2.fromOffset(0, 24),
		Text = `⏱ {if time > 0 then Time.Clock(time) else "—"}    💥 {deaths}    🔑 {keys}/{Tower.USB_KEYS_PER_WORLD}`,
		TextSize = 18,
		FontFace = Style.Fonts.Bold,
	})
	label(card, {
		Position = UDim2.fromOffset(left, 114),
		Size = body + UDim2.fromOffset(0, 34),
		Text = goalText(world, payload),
		TextColor3 = hex(APP.TextDim),
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	if newBest then
		local badge: Frame = New("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 39),
			Size = UDim2.fromOffset(128, 24),
			BackgroundColor3 = VIOLET,
			BorderSizePixel = 0,
			Parent = card,
		}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance })
		label(badge, {
			Size = UDim2.fromScale(1, 1),
			Text = "Nouveau record !",
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 14,
			FontFace = Style.Fonts.Heavy,
		})
		task.delay(0.4, function()
			Motion.Pop(badge, 0.3)
		end)
	end

	-- Clic / toucher : fermer.
	local close: TextButton = New("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 10,
		Parent = card,
	})
	close.Activated:Connect(function()
		dismiss(card)
	end)

	Motion.Tween(card, { Position = UDim2.fromScale(0.5, 0.3) }, 0.35, Enum.EasingStyle.Back)
	Motion.Pop(icon, 0.25)
	task.delay(SHOW_SECONDS, function()
		dismiss(card)
	end)
end

function MedalCard.Mount(target: Frame)
	layer = target
end

return MedalCard
