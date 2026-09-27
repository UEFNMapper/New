--!nonstrict
-- Kit d'interface « KAIJU ALERT » : panneaux BD encrés, boutons 3D à lèvre,
-- rubans à rayures de danger, fenêtres qui claquent à l'écran, rayons de
-- soleil tournants, compteurs animés. Tout est construit en code.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Icons = require(Shared.Config.Icons)
local Signal = require(Shared.Util.Signal)

local Audio = require(script.Parent.Parent.Controllers.Audio)
local ScreenScale = require(script.Parent.Parent.Controllers.ScreenScale)

local C = Theme.Colors
local F = Theme.Fonts

local Kit = {}
Kit.Colors = C
Kit.Fonts = F

----------------------------------------------------------------------------
-- Création
----------------------------------------------------------------------------

function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.Corner(radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner) })
end

function Kit.Round(): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Kit.Stroke(thickness: number?, color: Color3?, border: boolean?): UIStroke
	return Kit.new("UIStroke", {
		Thickness = thickness or Theme.Stroke,
		Color = color or C.Ink,
		ApplyStrokeMode = if border == false then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Kit.Gradient(name: string | { Color3 }, rotation: number?): UIGradient
	local colors = if type(name) == "string" then Theme.Gradients[name] or Theme.Gradients.Paper else name
	return Kit.new("UIGradient", {
		Color = ColorSequence.new(colors[1], colors[2]),
		Rotation = rotation or 90,
	})
end

function Kit.Padding(px: number, py: number?): UIPadding
	local y = py or px
	return Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, y),
		PaddingBottom = UDim.new(0, y),
	})
end

function Kit.List(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Kit.Grid(cell: UDim2, padding: number?): UIGridLayout
	return Kit.new("UIGridLayout", {
		CellSize = cell,
		CellPadding = UDim2.fromOffset(padding or 10, padding or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
end

-- Icône : image du pack (Config/Icons) si uploadée, sinon emoji de secours.
-- `key` peut aussi être directement un emoji.
-- En mode aperçu (attribut IconPreview sur ReplicatedStorage), l'image pointe
-- vers "preview://<clé>" pour les rendus hors Roblox.
-- Un emoji brut est converti vers la clé du pack qui l'utilise (ex. "💎" -> "gem").
local emojiToKey: { [string]: string } = {}
local function stripVariation(text: string): string
	return (text:gsub("\u{FE0F}", ""))
end
for key, def in Icons.Defs do
	local e = stripVariation(def.Emoji)
	if not emojiToKey[e] then
		emojiToKey[e] = key
	end
end

local function resolveKey(keyOrEmoji: string): string
	if Icons.Has(keyOrEmoji) then
		return keyOrEmoji
	end
	return emojiToKey[stripVariation(keyOrEmoji)] or keyOrEmoji
end


local function iconImage(key: string): string?
	if ReplicatedStorage:GetAttribute("IconPreview") and Icons.Has(key) then
		return "preview://" .. key
	end
	return Icons.Image(key)
end

-- Image du pack pour un texte qui est un emoji seul (sinon nil).
local function emojiImageFor(text: string): string?
	local key = emojiToKey[stripVariation(text)]
	if key then
		return iconImage(key)
	end
	return nil
end

-- Un TextLabel dont le texte est un emoji du pack affiche l'image à la place
-- (le texte devient invisible). Suit les changements de .Text.
local function attachEmojiImage(label: TextLabel)
	local function refresh()
		local image = emojiImageFor(label.Text)
		local existing = label:FindFirstChild("EmojiImage") :: ImageLabel?
		if image then
			if not existing then
				existing = Instance.new("ImageLabel")
				existing.Name = "EmojiImage"
				existing.BackgroundTransparency = 1
				existing.Size = UDim2.fromScale(1, 1)
				existing.ScaleType = Enum.ScaleType.Fit
				existing.ZIndex = label.ZIndex
				existing.Parent = label
			end
			existing.Image = image
			label.TextTransparency = 1
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 1
			end
		elseif existing then
			existing:Destroy()
			label.TextTransparency = 0
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0
			end
		end
	end
	label:GetPropertyChangedSignal("Text"):Connect(refresh)
	refresh()
end

function Kit.Icon(keyOrEmoji: string, props: { [string]: any }): GuiObject
	local key = resolveKey(keyOrEmoji)
	local image = iconImage(key)
	local inst
	if image then
		inst = Kit.new("ImageLabel", {
			Name = props.Name or "Icon",
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		inst = Kit.new("TextLabel", {
			Name = props.Name or "Icon",
			BackgroundTransparency = 1,
			Text = if Icons.Has(key) then Icons.Emoji(key) else key,
			FontFace = F.Body,
			TextScaled = true,
		})
	end
	inst:SetAttribute("IconKey", key)
	for k, v in props do
		if k ~= "Name" and k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

-- Change l'icône d'un élément créé par Kit.Icon (remplace l'instance si le type change).
function Kit.SetIcon(inst: GuiObject, keyOrEmoji: string): GuiObject
	local key = resolveKey(keyOrEmoji)
	if inst:GetAttribute("IconKey") == key then
		return inst
	end
	local image = iconImage(key)
	if image and inst:IsA("ImageLabel") then
		inst.Image = image
		inst:SetAttribute("IconKey", key)
		return inst
	elseif not image and inst:IsA("TextLabel") then
		inst.Text = if Icons.Has(key) then Icons.Emoji(key) else key
		inst:SetAttribute("IconKey", key)
		return inst
	end
	local replacement = Kit.Icon(key, {
		Size = inst.Size,
		Position = inst.Position,
		AnchorPoint = inst.AnchorPoint,
		ZIndex = inst.ZIndex,
		LayoutOrder = inst.LayoutOrder,
		Rotation = inst.Rotation,
		Parent = inst.Parent,
	})
	replacement.Name = inst.Name
	for _, child in inst:GetChildren() do
		child.Parent = replacement
	end
	inst:Destroy()
	return replacement
end

-- Texte BD : police, contour encre.
function Kit.Text(props: { [string]: any }): TextLabel
	local stroke = props.Stroke
	local scaled = props.TextScaled ~= false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = F.Title
	label.TextColor3 = C.White
	label.RichText = true
	label.TextScaled = scaled
	for k, v in props do
		if k ~= "Stroke" and k ~= "MaxTextSize" and k ~= "Parent" then
			(label :: any)[k] = v
		end
	end
	if stroke ~= false then
		Kit.new("UIStroke", {
			Thickness = if type(stroke) == "number" then stroke else 2.5,
			Color = C.Ink,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = label,
		})
	end
	if scaled then
		Kit.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 60, Parent = label })
	end
	if props.NoEmojiImage ~= true then
		attachEmojiImage(label)
	end
	label.Parent = props.Parent
	return label
end

----------------------------------------------------------------------------
-- Animations
----------------------------------------------------------------------------

function Kit.Tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, repeats: number?, reverses: boolean?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, repeats or 0, reverses or false), props)
	tween:Play()
	return tween
end

-- Échelle animable d'un élément. Un élément mis à l'échelle de l'écran
-- (Kit.AutoScale) n'a qu'UN UIScale : Roblox n'en applique qu'un seul par
-- élément, donc les animations (Pop, Punch, Breathe) le réutilisent et
-- travaillent autour de l'échelle d'écran au lieu de la remplacer.
function Kit.ScaleOf(inst: GuiObject): UIScale
	local auto = inst:FindFirstChild("AutoScale") :: UIScale?
	if auto then
		return auto
	end
	local s = inst:FindFirstChild("KitScale") :: UIScale?
	if not s then
		s = Kit.new("UIScale", { Name = "KitScale", Parent = inst })
	end
	return s :: UIScale
end

-- Échelle « au repos » d'une échelle animable (1, ou l'échelle d'écran).
local function restScale(s: UIScale): number
	if s.Name == "AutoScale" then
		return if s:GetAttribute("Kind") == "Window" then ScreenScale.Window() else Kit.UIScale
	end
	return 1
end

function Kit.Pop(inst: GuiObject, from: number?, time: number?)
	local s = Kit.ScaleOf(inst)
	local rest = restScale(s)
	s.Scale = (from or 0.4) * rest
	Kit.Tween(s, time or 0.45, { Scale = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end
function Kit.Punch(inst: GuiObject, amount: number?)
	local s = Kit.ScaleOf(inst)
	local rest = restScale(s)
	s.Scale = rest * (1 + (amount or 0.18))
	Kit.Tween(s, 0.35, { Scale = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end
function Kit.Shake(inst: GuiObject, intensity: number?, duration: number?)
	-- position d'origine mémorisée une seule fois (secousses qui se chevauchent)
	local saved = inst:GetAttribute("ShakeBase")
	local base = if typeof(saved) == "UDim2" then saved else inst.Position
	inst:SetAttribute("ShakeBase", base)
	local strength = intensity or 6
	local t0 = os.clock()
	local d = duration or 0.35
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > d or not inst.Parent then
			conn:Disconnect()
			inst.Position = base
			inst:SetAttribute("ShakeBase", nil)
			return
		end
		local k = (1 - t / d) * strength
		inst.Position = base + UDim2.fromOffset((math.random() - 0.5) * 2 * k, (math.random() - 0.5) * 2 * k)
	end)
end

function Kit.Breathe(inst: GuiObject, amount: number?, period: number?)
	local s = Kit.ScaleOf(inst)
	local rest = restScale(s)
	Kit.Tween(s, period or 0.9, { Scale = rest * (1 + (amount or 0.05)) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
end

-- Balancement continu.
function Kit.Wobble(inst: GuiObject, degrees: number?, period: number?)
	local d = degrees or 4
	inst.Rotation = -d
	Kit.Tween(inst, period or 1.2, { Rotation = d }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
end

-- Compteur animé : met à jour label.Text avec fmt(valeur).
local counters: { [Instance]: { from: number, to: number, t0: number, d: number, fmt: (number) -> string } } = {}
function Kit.CountTo(label: TextLabel, value: number, fmt: (number) -> string, duration: number?)
	local current = counters[label]
	local from = value
	if current then
		local a = math.clamp((os.clock() - current.t0) / current.d, 0, 1)
		from = current.from + (current.to - current.from) * (1 - (1 - a) ^ 3)
	elseif label:GetAttribute("Value") then
		from = label:GetAttribute("Value")
	end
	label:SetAttribute("Value", value)
	counters[label] = { from = from, to = value, t0 = os.clock(), d = duration or 0.6, fmt = fmt }
end

RunService.RenderStepped:Connect(function()
	for label, c in counters do
		local a = math.clamp((os.clock() - c.t0) / c.d, 0, 1)
		local eased = 1 - (1 - a) ^ 3
		label.Text = c.fmt(c.from + (c.to - c.from) * eased)
		if a >= 1 or not label.Parent then
			counters[label] = nil
		end
	end
end)

----------------------------------------------------------------------------
-- Échelle globale (mobile ↔ PC)
----------------------------------------------------------------------------

Kit.ScaleChanged = Signal.new()
Kit.UIScale = 1
local scaled: { UIScale } = {}

local function computeScale(): number
	return ScreenScale.Hud()
end

-- Ajoute une échelle automatique à un élément de premier niveau.
-- kind = "Window" : échelle des fenêtres (un peu plus grandes que le HUD sur téléphone).
function Kit.AutoScale(inst: GuiObject, kind: string?)
	local s = Kit.new("UIScale", { Name = "AutoScale", Scale = if kind == "Window" then ScreenScale.Window() else Kit.UIScale, Parent = inst })
	s:SetAttribute("Kind", kind or "Hud")
	table.insert(scaled, s)
	return s
end

local function refreshScale()
	Kit.UIScale = computeScale()
	local window = ScreenScale.Window()
	for _, s in scaled do
		s.Scale = if s:GetAttribute("Kind") == "Window" then window else Kit.UIScale
	end
	Kit.ScaleChanged:Fire(Kit.UIScale)
end

task.defer(function()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end
	refreshScale()
end)

----------------------------------------------------------------------------
-- Composants
----------------------------------------------------------------------------

-- Panneau BD : ombre portée pleine + corps crème encré.
function Kit.Panel(props: { [string]: any }): (Frame, Frame)
	local container = Kit.new("Frame", {
		Name = props.Name or "Panel",
		Size = props.Size or UDim2.fromOffset(300, 200),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Rotation = props.Rotation or 0,
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	local offset = props.ShadowOffset or Theme.ShadowOffset
	Kit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(offset, offset),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = props.ShadowTransparency or 0,
		ZIndex = container.ZIndex,
		Parent = container,
	}, { Kit.Corner(props.Corner) })
	local body = Kit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		ZIndex = container.ZIndex,
		ClipsDescendants = props.Clip == true,
		Parent = container,
	}, {
		Kit.Corner(props.Corner),
		Kit.Stroke(props.StrokeThickness or 4),
		Kit.Gradient(props.Gradient or "Paper"),
	})
	return container, body
end

-- Bandes de danger jaune/noir (dans un CanvasGroup pour couper proprement).
function Kit.Hazard(props: { [string]: any }): CanvasGroup
	local group = Kit.new("CanvasGroup", {
		Name = "Hazard",
		Size = props.Size or UDim2.new(1, 0, 0, 14),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = props.ColorA or C.Gold,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	}, { Kit.Corner(props.Corner or 4) })
	local stripes = Kit.new("Frame", {
		Size = UDim2.new(2, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = group,
	})
	for i = 0, 60 do
		Kit.new("Frame", {
			Size = UDim2.new(0, 10, 3, 0),
			Position = UDim2.new(0, i * 24, -1, 0),
			Rotation = 35,
			BackgroundColor3 = props.ColorB or C.Ink,
			BorderSizePixel = 0,
			ZIndex = group.ZIndex,
			Parent = stripes,
		})
	end
	if props.Animate ~= false then
		Kit.Tween(stripes, 1.6, { Position = UDim2.fromOffset(-48, 0) }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	end
	return group
end

-- Ruban de titre incliné.
function Kit.Ribbon(props: { [string]: any }): Frame
	local ribbon = Kit.new("Frame", {
		Name = "Ribbon",
		Size = props.Size or UDim2.fromOffset(320, 56),
		Position = props.Position or UDim2.new(0.5, 0, 0, -26),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0),
		Rotation = props.Rotation or -2.5,
		BackgroundColor3 = C.White,
		ZIndex = (props.ZIndex or 1) + 2,
		Parent = props.Parent,
	}, {
		Kit.Corner(10),
		Kit.Stroke(4),
		Kit.Gradient(props.Color or "Magma"),
	})
	Kit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = C.Ink,
		ZIndex = ribbon.ZIndex - 1,
		Parent = ribbon,
	}, { Kit.Corner(10) })
	Kit.Text({
		Name = "Title",
		Size = UDim2.new(1, -24, 1, -10),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = props.Text or "",
		FontFace = F.Title,
		ZIndex = ribbon.ZIndex + 1,
		Stroke = 3,
		Parent = ribbon,
	})
	return ribbon
end

-- Bouton 3D à lèvre, avec reflet qui balaie au survol.
function Kit.Button(props: { [string]: any }): TextButton
	local color = props.Color or "Radioactive"
	local colors = Theme.Gradients[color] or Theme.Gradients.Radioactive
	local lipColor = colors[2]:Lerp(C.Ink, 0.45)
	local z = props.ZIndex or 5
	local button = Kit.new("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(200, 64),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Rotation = props.Rotation or 0,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = z,
		Parent = props.Parent,
	})
	Kit.new("Frame", {
		Name = "Lip",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.fromOffset(0, 6),
		BackgroundColor3 = lipColor,
		ZIndex = z,
		Parent = button,
	}, { Kit.Corner(props.Corner or 14), Kit.Stroke(3) })
	local face = Kit.new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.White,
		ZIndex = z + 1,
		Parent = button,
	}, { Kit.Corner(props.Corner or 14), Kit.Stroke(3), Kit.Gradient(colors) })
	-- reflet haut (volume)
	Kit.new("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -12, 0.36, 0),
		Position = UDim2.fromOffset(6, 4),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.7,
		ZIndex = z + 2,
		Parent = face,
	}, { Kit.Corner((props.Corner or 14) - 4) })
	-- reflet qui balaie : bande diagonale dessinée par un dégradé (aucun
	-- débordement, même quand le bouton ou sa fenêtre sont inclinés)
	local shineFrame = Kit.new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.35,
		ZIndex = z + 3,
		Parent = face,
	}, { Kit.Corner(props.Corner or 14) })
	local shine = Kit.new("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = shineFrame,
	})
	local content = Kit.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z + 4,
		Parent = face,
	}, { Kit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	if props.Icon then
		Kit.Icon(props.Icon, {
			Name = "Icon",
			Size = UDim2.new(0, props.IconSize or 34, 0.8, 0),
			ZIndex = z + 4,
			LayoutOrder = 1,
			Parent = content,
		})
	end
	local label = Kit.Text({
		Name = "Label",
		Size = UDim2.new(if props.Icon then 0.75 else 1, 0, props.TextHeight or 0.8, 0),
		AutomaticSize = if props.Icon then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
		Text = props.Text or "",
		FontFace = props.Font or F.Title,
		TextColor3 = props.TextColor or C.White,
		ZIndex = z + 4,
		LayoutOrder = 2,
		Stroke = 2.5,
		MaxTextSize = props.MaxTextSize or 34,
		Parent = content,
	})
	if props.Icon then
		label.Size = UDim2.new(0, 0, props.TextHeight or 0.8, 0)
		label.TextScaled = false
		label.TextSize = props.TextSize or 26
	end

	local scale = Kit.ScaleOf(button)
	local hovering = false
	button.MouseEnter:Connect(function()
		if button:GetAttribute("Disabled") then
			return
		end
		hovering = true
		Audio.Play("ui_hover", { Cooldown = 0.06 })
		Kit.Tween(scale, 0.25, { Scale = 1.06 }, Enum.EasingStyle.Back)
		Kit.Tween(button, 0.25, { Rotation = (props.Rotation or 0) + (props.HoverTilt or 1.5) }, Enum.EasingStyle.Back)
		shine.Offset = Vector2.new(-1, 0)
		Kit.Tween(shine, 0.55, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		Kit.Tween(scale, 0.2, { Scale = 1 })
		Kit.Tween(button, 0.2, { Rotation = props.Rotation or 0 })
		face.Position = UDim2.new()
	end)
	button.MouseButton1Down:Connect(function()
		if button:GetAttribute("Disabled") then
			return
		end
		face.Position = UDim2.fromOffset(0, 5)
		Kit.Tween(scale, 0.08, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(function()
		face.Position = UDim2.new()
		Kit.Tween(scale, 0.25, { Scale = if hovering then 1.06 else 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") then
			Audio.Play("ui_error")
			Kit.Shake(button, 4, 0.25)
			return
		end
		Audio.Play(props.Sound or "ui_click")
		if props.OnClick then
			task.spawn(props.OnClick, button)
		end
	end)
	return button
end

function Kit.SetButtonText(button: GuiObject, text: string)
	local label = button:FindFirstChild("Label", true) :: TextLabel?
	if label then
		label.Text = text
	end
end

function Kit.SetButtonColor(button: GuiObject, color: string)
	local colors = Theme.Gradients[color]
	local face = button:FindFirstChild("Face")
	local lip = button:FindFirstChild("Lip") :: Frame?
	if colors and face and lip then
		local g = face:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(colors[1], colors[2])
		end
		lip.BackgroundColor3 = colors[2]:Lerp(C.Ink, 0.45)
	end
end

function Kit.SetDisabled(button: GuiObject, disabled: boolean)
	button:SetAttribute("Disabled", disabled)
	local face = button:FindFirstChild("Face") :: Frame?
	if face then
		local g = face:FindFirstChildOfClass("UIGradient")
		if g then
			if disabled then
				g:SetAttribute("Saved", g:GetAttribute("Saved") or g.Color)
				g.Color = ColorSequence.new(Theme.Gradients.Grey[1], Theme.Gradients.Grey[2])
			elseif g:GetAttribute("Saved") then
				g.Color = g:GetAttribute("Saved")
				g:SetAttribute("Saved", nil)
			end
		end
	end
end

-- Pastille de notification (!) qui rebondit.
function Kit.Badge(parent: GuiObject, text: string?): Frame
	local badge = parent:FindFirstChild("Badge") :: Frame?
	if not badge then
		badge = Kit.new("Frame", {
			Name = "Badge",
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -6, 0, -6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Red,
			ZIndex = 50,
			Visible = false,
			Parent = parent,
		}, { Kit.Round(), Kit.Stroke(3) })
		Kit.Text({
			Name = "Text",
			Size = UDim2.fromScale(0.8, 0.8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = text or "!",
			ZIndex = 51,
			Stroke = 1.5,
			Parent = badge,
		})
		Kit.Breathe(badge :: Frame, 0.18, 0.45)
	end
	return badge :: Frame
end

function Kit.SetBadge(parent: GuiObject, visible: boolean, text: string?)
	local badge = Kit.Badge(parent, text)
	badge.Visible = visible
	if text then
		local label = badge:FindFirstChild("Text") :: TextLabel?
		if label then
			label.Text = text
		end
	end
end

-- Rayons de soleil tournants (derrière les récompenses).
function Kit.Starburst(props: { [string]: any }): Frame
	local holder = Kit.new("Frame", {
		Name = "Starburst",
		Size = props.Size or UDim2.fromOffset(600, 600),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	local count = props.Rays or 14
	for i = 1, count do
		Kit.new("Frame", {
			Size = UDim2.new(0.12, 0, 1, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = i / count * 180,
			BackgroundColor3 = props.Color or C.Gold,
			BackgroundTransparency = props.Transparency or 0.55,
			BorderSizePixel = 0,
			ZIndex = holder.ZIndex,
			Parent = holder,
		}, {
			Kit.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.35, 0.2),
					NumberSequenceKeypoint.new(0.5, 1),
					NumberSequenceKeypoint.new(0.65, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
			}),
		})
	end
	Kit.Tween(holder, props.Period or 12, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	return holder
end

-- Barre de progression encrée.
function Kit.ProgressBar(props: { [string]: any }): (Frame, (number, boolean?) -> ())
	local bar = Kit.new("Frame", {
		Name = props.Name or "Progress",
		Size = props.Size or UDim2.fromOffset(200, 18),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = C.Ink,
		ZIndex = props.ZIndex or 5,
		Parent = props.Parent,
	}, { Kit.Round(), Kit.Stroke(3) })
	local fill = Kit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.White,
		ZIndex = bar.ZIndex + 1,
		Parent = bar,
	}, { Kit.Round(), Kit.Gradient(props.Color or "Radioactive") })
	local function set(alpha: number, instant: boolean?)
		alpha = math.clamp(alpha, 0, 1)
		if instant then
			fill.Size = UDim2.fromScale(alpha, 1)
		else
			Kit.Tween(fill, 0.35, { Size = UDim2.fromScale(alpha, 1) })
		end
		fill.Visible = alpha > 0.01
	end
	set(props.Value or 0, true)
	return bar, set
end

-- Liste défilante stylée.
function Kit.Scroll(props: { [string]: any }): ScrollingFrame
	return Kit.new("ScrollingFrame", {
		Name = props.Name or "Scroll",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = C.Ink,
		ScrollBarImageTransparency = 0.2,
		AutomaticCanvasSize = props.Horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = props.Horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
		ZIndex = props.ZIndex or 5,
		Parent = props.Parent,
	})
end

-- Pastille arrondie (étiquette de rareté, chips…).
function Kit.Chip(props: { [string]: any }): Frame
	local chip = Kit.new("Frame", {
		Name = props.Name or "Chip",
		Size = props.Size or UDim2.fromOffset(120, 30),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		AutomaticSize = props.AutoWidth and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = props.Color or C.Ink,
		ZIndex = props.ZIndex or 5,
		Parent = props.Parent,
	}, { Kit.Round(), Kit.Stroke(2.5), Kit.Padding(10, 2) })
	Kit.Text({
		Name = "Text",
		Size = UDim2.new(if props.AutoWidth then 0 else 1, 0, 1, 0),
		AutomaticSize = props.AutoWidth and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
		TextScaled = not props.AutoWidth,
		TextSize = props.TextSize or 18,
		Text = props.Text or "",
		FontFace = props.Font or F.Title,
		TextColor3 = props.TextColor or C.White,
		ZIndex = chip.ZIndex + 1,
		Stroke = 2,
		Parent = chip,
	})
	return chip
end

----------------------------------------------------------------------------
-- Fenêtres modales
----------------------------------------------------------------------------

local root: ScreenGui? = nil
local blur: BlurEffect? = nil
local openWindow: any = nil
Kit.WindowOpened = Signal.new()

function Kit.Root(): ScreenGui
	if root then
		return root
	end
	local player = Players.LocalPlayer
	root = Kit.new("ScreenGui", {
		Name = "KaijuUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	blur = Kit.new("BlurEffect", { Name = "UIBlur", Size = 0, Parent = Lighting })
	return root :: any
end

-- Crée une couche plein écran (au-dessus du HUD si displayOrder plus grand).
function Kit.Layer(name: string, displayOrder: number): ScreenGui
	local player = Players.LocalPlayer
	return Kit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Parent = player:WaitForChild("PlayerGui"),
	})
end

export type Window = {
	Frame: Frame, -- zone de contenu
	Holder: Frame,
	Open: (self: Window) -> (),
	Close: (self: Window) -> (),
	IsOpen: boolean,
	Opened: any,
	Closed: any,
}

function Kit.Window(props: { [string]: any }): Window
	local layer = Kit.Layer("Window_" .. (props.Name or props.Title or "W"), 20)
	layer.Enabled = false
	local backdrop = Kit.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = layer,
	})
	local holder = Kit.new("Frame", {
		Name = "Holder",
		Size = props.Size or UDim2.fromOffset(820, 520),
		Position = UDim2.fromScale(0.5, 0.53),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Kit.AutoScale(holder, "Window")
	-- Au repos la fenêtre est droite : Roblox ne découpe pas (ClipsDescendants)
	-- le contenu d'un parent incliné. L'inclinaison BD passe par le ruban.
	local restRotation = props.Rotation or 0
	local container, body = Kit.Panel({
		Size = UDim2.fromScale(1, 1),
		Rotation = restRotation,
		Gradient = props.Gradient or "Paper",
		Parent = holder,
	})
	-- bandeau de danger en bas
	Kit.Hazard({
		Size = UDim2.new(1, -40, 0, 12),
		Position = UDim2.new(0.5, 0, 1, -22),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = body,
	})
	Kit.Ribbon({
		Text = (props.Icon and (props.Icon .. " ") or "") .. (props.Title or ""),
		Color = props.Color or "Magma",
		Size = UDim2.fromOffset(props.RibbonWidth or 360, 62),
		Position = UDim2.new(0.5, 0, 0, -34),
		ZIndex = 5,
		Parent = container,
	})
	local close = Kit.Button({
		Name = "Close",
		Text = "X",
		Color = "Red",
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(1, -18, 0, -18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Corner = 28,
		ZIndex = 30,
		Sound = "ui_close",
		HoverTilt = 12,
		Parent = container,
	})
	local content = Kit.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -44, 1, -80),
		Position = UDim2.fromOffset(22, 44),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = body,
	})

	local window = {
		Frame = content,
		Holder = holder,
		IsOpen = false,
		Opened = Signal.new(),
		Closed = Signal.new(),
	}

	function window.Open(self)
		if self.IsOpen then
			return
		end
		if openWindow and openWindow ~= self then
			openWindow:Close(true)
		end
		openWindow = self
		self.IsOpen = true
		layer.Enabled = true
		Audio.Play("ui_open")
		backdrop.BackgroundTransparency = 1
		Kit.Tween(backdrop, 0.25, { BackgroundTransparency = 0.45 })
		if blur then
			Kit.Tween(blur, 0.3, { Size = 14 })
		end
		local s = Kit.ScaleOf(container)
		s.Scale = 0.55
		container.Rotation = restRotation - 9
		Kit.Tween(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		Kit.Tween(container, 0.5, { Rotation = restRotation }, Enum.EasingStyle.Back)
		self.Opened:Fire()
		Kit.WindowOpened:Fire(self)
	end

	function window.Close(self, silent: boolean?)
		if not self.IsOpen then
			return
		end
		self.IsOpen = false
		if openWindow == self then
			openWindow = nil
		end
		if not silent then
			Audio.Play("ui_close")
		end
		local s = Kit.ScaleOf(container)
		Kit.Tween(s, 0.18, { Scale = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Kit.Tween(backdrop, 0.18, { BackgroundTransparency = 1 })
		if blur and not openWindow then
			Kit.Tween(blur, 0.2, { Size = 0 })
		end
		task.delay(0.18, function()
			if not self.IsOpen then
				layer.Enabled = false
			end
		end)
		self.Closed:Fire()
	end

	function window.Toggle(self)
		if self.IsOpen then
			self:Close()
		else
			self:Open()
		end
	end

	close.Activated:Connect(function()
		window:Close()
	end)
	backdrop.Activated:Connect(function()
		window:Close()
	end)
	return window :: any
end

function Kit.CloseAll()
	if openWindow then
		openWindow:Close()
	end
end

-- Onglets : renvoie la barre et une fonction select(id).
function Kit.Tabs(props: { [string]: any }): (Frame, (string) -> ())
	local bar = Kit.new("Frame", {
		Name = "Tabs",
		Size = props.Size or UDim2.new(1, 0, 0, 52),
		Position = props.Position or UDim2.new(),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = props.Parent,
	}, { Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local buttons = {}
	local function select(id: string)
		for tabId, button in buttons do
			local active = tabId == id
			Kit.SetButtonColor(button, if active then (props.ActiveColor or "Magma") else "Ink")
		end
		if props.OnSelect then
			props.OnSelect(id)
		end
	end
	for i, tab in props.Tabs do
		buttons[tab.Id] = Kit.Button({
			Name = tab.Id,
			Text = tab.Text,
			Icon = tab.Icon,
			IconSize = 26,
			TextSize = 20,
			Color = "Ink",
			Size = UDim2.fromOffset(tab.Width or 140, 46),
			LayoutOrder = i,
			Sound = "ui_tab",
			ZIndex = 6,
			OnClick = function()
				select(tab.Id)
			end,
			Parent = bar,
		})
	end
	return bar, select
end

return Kit
