--!strict
--[[
	Popup : "Pop-up Killer" (monde 2, Memory Lanes). Des fenêtres de pub avec les yeux de
	Pop-Up s'ouvrent et se multiplient : ferme-les avec leur ✕ avant que la RAM soit
	pleine ! Attention aux faux boutons (« OK », « Télécharger ») : ils ouvrent encore
	plus de pubs.

	Contrôles : doigt / clic sur le ✕ (à l'appui). Manette : A (ou X) ferme la pub du
	dessus ; clavier : Espace, X ou Retour arrière. Un appui touche toujours la fenêtre la
	plus haute sous le doigt (PopupLogic.PressAt) : pas de clic "à travers" une pub.
	Règles et chiffres : PopupLogic (pur, testé).
]]

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Style = require(script.Parent.Parent.Style)
local Icon = require(script.Parent.Parent.Components.Icon)
local Core = require(script.Parent.Core)
local Common = require(script.Parent.Common)
local PopupLogic = require(script.Parent.PopupLogic)

local New = Create.New
local C = Common.Colors
local At = Common.At
local Box = Common.Box

local Popup = {}

local CLOSE_KEYS = {
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.ButtonX] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.X] = true,
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.Delete] = true,
}

-- Les pubs (PopupLogic.STYLES) : gros titre + couleur (token du thème).
local ADS = table.freeze({
	{ Text = "TU AS GAGNÉ !!!", Color = "CurrencyBits" },
	{ Text = "CLIQUE ICI !", Color = "BrandAnga" },
	{ Text = "1 000 000 BITS GRATUITS", Color = "AccentCyan" },
	{ Text = "TON PC EST LENT ?", Color = "AccentAmber" },
	{ Text = "SUPER PROMO -99 %", Color = "Success" },
	{ Text = "BRAVO, 999e VISITEUR !", Color = "AccentViolet" },
})

-- Couleur des faux boutons : ils ont l'air de vrais boutons, c'est le piège.
local DECOY_COLORS = table.freeze({ "AccentCyan", "Success", "AccentViolet", "CurrencyBits" })

function Popup.Info(difficulty: number, device: Common.Device): Common.Info
	local p = PopupLogic.Params(difficulty)
	return {
		Title = "POP-UP KILLER",
		Rule = "Ferme les pubs (croix rouge) avant que la RAM soit pleine !",
		Target = `Ferme {p.Target} pubs !`,
		Controls = if device == "Gamepad"
			then "A pour fermer la pub du dessus"
			elseif device == "Touch" then "Tape sur la croix rouge, jamais sur OK !"
			else "Clique sur la croix rouge (ou Espace)",
		Tip = "Astuce : « OK » et « Télécharger » sont des pièges, vise la croix !",
		Goal = p.Target,
		Unit = "pubs",
		Icon = "Close",
		Accent = "BrandAnga",
	}
end

type WindowSpec = { W: number, H: number, CloseLeft: boolean, Decoys: { number }, Style: number }

type WindowView = {
	Root: Frame,
	Close: Frame,
	Ring: UIStroke,
}

-- Gros œil de Pop-Up (qui louche vers le ✕).
local function googlyEye(parent: Instance, position: UDim2, size: UDim2, lookRight: boolean)
	local eye = Common.Shape(parent, position, size, C.Eye, UDim.new(1, 0), { Name = "Eye", ZIndex = 3 })
	New("UIAspectRatioConstraint", { AspectRatio = 1, Parent = eye })
	New("UIStroke", { Color = C.Ink, Thickness = 2, Parent = eye })
	Common.Shape(
		eye,
		UDim2.fromScale(if lookRight then 0.64 else 0.36, 0.58),
		UDim2.fromScale(0.5, 0.5),
		C.Ink,
		UDim.new(1, 0),
		{
			Name = "Pupil",
			ZIndex = 4,
		}
	)
end

-- Fenêtre de pub. Positions internes en unités du terrain (spec.W x spec.H) -> échelle,
-- pour dessiner la même fenêtre en jeu (Box) et en illustration (pixels).
local function buildWindow(parent: Instance, spec: WindowSpec, size: UDim2, position: UDim2, zIndex: number): WindowView
	local w, h = spec.W, spec.H
	local function rel(x: number, y: number): UDim2
		return UDim2.fromScale(x / w, y / h)
	end
	local ad = ADS[spec.Style] or ADS[1]
	local accent = Style.Color(ad.Color)
	local root: Frame = New("Frame", {
		Name = "Ad",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = parent,
	}, {
		Common.Corner(UDim.new(0, 10)),
		New("UIStroke", { Color = accent, Thickness = 3 }),
		New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.White, C.White:Lerp(accent, 0.25)) }),
	})
	-- Barre de titre
	local title: Frame = New("Frame", {
		Name = "TitleBar",
		Size = rel(w, PopupLogic.TITLE_H),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = root,
	}, { Common.Corner(UDim.new(0, 10)) })
	New("TextLabel", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.5),
		BackgroundTransparency = 1,
		Text = "PUB",
		TextScaled = true,
		TextColor3 = C.Ink,
		Tag = "FontHeavy",
		ZIndex = 3,
		Parent = title,
	})
	-- ✕ : rond rouge dans le coin (au centre de sa zone tactile)
	local half = PopupLogic.CLOSE_SIZE / 2
	local closeX = if spec.CloseLeft then half else w - half
	local close = Common.Shape(root, rel(closeX, half), rel(50, 50), C.Bad, UDim.new(1, 0), {
		Name = "Close",
		ZIndex = 5,
	})
	New("UIStroke", { Color = C.White, Thickness = 2, Parent = close })
	for _, angle in { 45, -45 } do
		Common.Shape(close, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.62, 0.14), C.White, UDim.new(1, 0), {
			Name = "Bar",
			Rotation = angle,
			ZIndex = 6,
		})
	end
	local ring: UIStroke = New("UIStroke", {
		Name = "Focus",
		Color = C.Gold,
		Thickness = 4,
		Transparency = 1,
	})
	local focus = Common.Shape(close, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1.35, 1.35), C.Gold, UDim.new(1, 0), {
		Name = "FocusRing",
		BackgroundTransparency = 1,
		ZIndex = 6,
	})
	ring.Parent = focus
	-- Contenu : les yeux de Pop-Up + le titre de la pub
	local bottom = if #spec.Decoys > 0 then h - 12 - PopupLogic.DECOY_H - 6 else h - 10
	local top = PopupLogic.TITLE_H + 4
	local middle = (top + bottom) / 2
	local eyeSize = math.min(34, bottom - top)
	googlyEye(root, rel(20 + eyeSize / 2, middle), rel(eyeSize, eyeSize), not spec.CloseLeft)
	googlyEye(root, rel(24 + eyeSize * 1.5, middle), rel(eyeSize, eyeSize), not spec.CloseLeft)
	local textLeft = 32 + eyeSize * 2
	New("TextLabel", {
		Name = "Headline",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = rel(textLeft, middle),
		Size = rel(w - textLeft - 10, bottom - top),
		BackgroundTransparency = 1,
		Text = ad.Text,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = C.Ink,
		Tag = "FontHeavy",
		ZIndex = 3,
		Parent = root,
	}, {
		New("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 8 }),
	})
	-- Faux boutons (mêmes rectangles que PopupLogic.DecoyRects)
	local fake: any = { X = w / 2, Y = h / 2, W = w, H = h, Decoys = spec.Decoys }
	for index, r in PopupLogic.DecoyRects(fake) do
		local label = PopupLogic.DECOY_LABELS[spec.Decoys[index]] or "OK"
		local color = Style.Color(DECOY_COLORS[spec.Decoys[index]] or "Success")
		local button: Frame = New("Frame", {
			Name = "Decoy",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = rel((r.X0 + r.X1) / 2, (r.Y0 + r.Y1) / 2),
			Size = rel(r.X1 - r.X0, r.Y1 - r.Y0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = root,
		}, {
			Common.Corner(UDim.new(0.3, 0)),
			New("UIStroke", { Color = C.Ink, Thickness = 2, Transparency = 0.4 }),
		})
		New("TextLabel", {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.88, 0.62),
			BackgroundTransparency = 1,
			Text = label,
			TextScaled = true,
			TextColor3 = C.Ink,
			Tag = "FontHeavy",
			ZIndex = 4,
			Parent = button,
		}, {
			New("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 8 }),
		})
	end
	return { Root = root, Close = close, Ring = ring }
end

function Popup.Illustrate(parent: Frame)
	-- Une pub à fermer (✕ entouré, coche) et un faux bouton « OK » barré.
	local spec: WindowSpec = { W = 300, H = 210, CloseLeft = false, Decoys = { 1 }, Style = 1 }
	local back = buildWindow(parent, {
		W = 300,
		H = 210,
		CloseLeft = false,
		Decoys = {},
		Style = 3,
	}, UDim2.fromOffset(150, 105), UDim2.fromScale(0.3, 0.44), 1)
	back.Root.Rotation = -6
	local view = buildWindow(parent, spec, UDim2.fromOffset(170, 119), UDim2.fromScale(0.52, 0.52), 2)
	view.Ring.Transparency = 0
	view.Ring.Color = C.Good
	Common.Pulse(view.Close, { Size = UDim2.fromScale(50 / 300 * 1.2, 50 / 210 * 1.2) }, 0.5)
	local ok = Icon.new("Check", 32, "Success")
	ok.AnchorPoint = Vector2.new(0.5, 0.5)
	ok.Position = UDim2.new(0.52, 100, 0.15, 0)
	ok.ZIndex = 3
	ok.Parent = parent
	local no = Icon.new("Close", 32, "Danger")
	no.AnchorPoint = Vector2.new(0.5, 0.5)
	no.Position = UDim2.new(0.52, 0, 0.93, 0)
	no.ZIndex = 3
	no.Parent = parent
	-- Jauge de RAM qui monte
	local gauge: Frame = New("Frame", {
		Name = "Ram",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.86, 0.5),
		Size = UDim2.fromOffset(26, 110),
		BackgroundColor3 = C.Screen,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Common.Corner(UDim.new(0, 8)), New("UIStroke", { Color = C.Muted, Thickness = 2 }) })
	local fill: Frame = New("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.3),
		BackgroundColor3 = C.Bad,
		BorderSizePixel = 0,
		Parent = gauge,
	}, { Common.Corner(UDim.new(0, 8)) })
	Common.Pulse(fill, { Size = UDim2.fromScale(1, 0.85) }, 1.4)
	New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(60, 18),
		BackgroundTransparency = 1,
		Text = "RAM",
		TextSize = 16,
		TextColor3 = C.White,
		Tag = "FontHeavy",
		Parent = gauge,
	})
end

function Popup.Run(container: Frame, difficulty: number, finish: Common.Finish, hud: Common.Hud?): () -> ()
	local ui = hud or Common.NullHud
	local bin = Common.Bin()
	local sim = PopupLogic.new(difficulty, Common.Seed())
	local p = sim.Params
	local finished = false

	local stage = Common.Stage(container)
	bin:Add(stage)
	local catcher = Common.Catcher(stage)

	-- Jauge de RAM (bas du terrain)
	local gaugeTop = PopupLogic.AREA_BOTTOM + 10
	local gaugeH = Core.FIELD_H - gaugeTop - 10
	local gauge: Frame = New("Frame", {
		Name = "RamGauge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = At(Core.FIELD_W / 2, gaugeTop + gaugeH / 2),
		Size = Box(Core.FIELD_W - 32, gaugeH),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = stage,
	}, {
		Common.Corner(),
		New("UIStroke", { Color = C.Muted, Thickness = 2, Transparency = 0.4 }),
	})
	New("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0.015, 0),
		Size = UDim2.fromScale(0.1, 1),
		BackgroundTransparency = 1,
		Text = "RAM",
		TextScaled = true,
		TextColor3 = C.White,
		Tag = "FontHeavy",
		ZIndex = 3,
		Parent = gauge,
	}, { New("UITextSizeConstraint", { MaxTextSize = 24 }) })
	local track: Frame = New("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.12, 0.5),
		Size = UDim2.fromScale(0.74, 0.56),
		BackgroundColor3 = C.Screen,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = gauge,
	}, { Common.Corner() })
	local fill: Frame = New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(sim.Ram, 1),
		BackgroundColor3 = C.Good,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = track,
	}, { Common.Corner() })
	local percent: TextLabel = New("TextLabel", {
		Name = "Percent",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.985, 0),
		Size = UDim2.fromScale(0.12, 1),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		Tag = "FontHeavy",
		ZIndex = 3,
		Parent = gauge,
	}, { New("UITextSizeConstraint", { MaxTextSize = 24 }) })

	-- Calque des fenêtres : leur ordre d'empilement (ZIndex = Z) reste sous les effets.
	local layer: Frame = New("Frame", {
		Name = "Windows",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = stage,
	})

	local views: { [number]: WindowView } = {}
	local keyMode = Common.Device() == "Gamepad"
	local focused: WindowView? = nil
	local lastBodyHint = -10
	local shownPercent = -1

	local function done(success: boolean)
		if finished then
			return
		end
		finished = true
		finish(success, sim.Closed)
	end

	local function refreshFocus()
		local top = PopupLogic.Top(sim)
		local view = if top and keyMode then views[top.Id] else nil
		if view == focused then
			return
		end
		if focused and focused.Ring.Parent then
			focused.Ring.Transparency = 1
		end
		focused = view
		if view then
			view.Ring.Transparency = 0.1
		end
	end

	local function addWindow(id: number)
		local w = PopupLogic.Find(sim, id)
		if not w then
			return
		end
		local view = buildWindow(layer, w, Box(w.W, w.H), At(w.X, w.Y), w.Z)
		views[id] = view
		local scale = Motion.ScaleOf(view.Root)
		scale.Scale = 0.3
		Motion.Tween(scale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back)
		Common.Sound("Click", 1.3 + math.random() * 0.3)
	end

	local function removeWindow(id: number): Frame?
		local view = views[id]
		views[id] = nil
		if not view then
			return nil
		end
		if focused == view then
			focused = nil
		end
		return view.Root
	end

	local function handle(event: PopupLogic.Event)
		local kind = event.Kind
		local where = At(event.X or Core.FIELD_W / 2, event.Y or Core.FIELD_H / 2)
		if kind == "Spawn" then
			addWindow(event.Id)
		elseif kind == "Split" then
			addWindow(event.Id)
			Common.Popup(stage, where, "x2 !", C.Bad, 26)
		elseif kind == "Close" then
			local root = removeWindow(event.Id)
			if root then
				-- La fenêtre se referme en rétrécissant.
				Motion.Tween(Motion.ScaleOf(root), { Scale = 0 }, 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				task.delay(0.16, function()
					root:Destroy()
				end)
			end
			Common.Burst(stage, where, C.GlitchB, 10, 70)
			Common.Popup(stage, where, "+1", C.Gold)
			Common.Sound("Zap", 1 + math.min(sim.Closed, 20) * 0.02)
			ui.SetProgress(sim.Closed, p.Target)
		elseif kind == "Decoy" then
			Common.Popup(stage, where, `« {event.Label or "OK"} » : piège !`, C.Bad, 26)
			Common.Sound("Error")
			Common.Shake(stage, 10, 0.3)
			Motion.Pop(gauge, 0.15)
		elseif kind == "Body" then
			if sim.Time - lastBodyHint > 1.5 then
				lastBodyHint = sim.Time
				Common.Popup(stage, where, "Vise la croix !", C.Cyan, 24)
			end
			local view = views[event.Id]
			if view then
				Motion.Pop(view.Close, 0.35)
			end
		elseif kind == "Win" then
			done(true)
		elseif kind == "Lose" then
			Common.Shake(stage, 14, 0.4)
			done(false)
		end
	end

	local function run(events: { PopupLogic.Event })
		for _, event in events do
			handle(event)
		end
	end

	-- Entrées ------------------------------------------------------------------------
	bin:Add(catcher.InputBegan:Connect(function(input: InputObject)
		if finished or not Common.IsPress(input) then
			return
		end
		keyMode = false
		local point = Common.ToField(stage, input.Position)
		run(PopupLogic.PressAt(sim, point.X, point.Y))
		refreshFocus()
	end))
	bin:Add(UserInputService.InputBegan:Connect(function(input: InputObject)
		if finished or UserInputService:GetFocusedTextBox() or not CLOSE_KEYS[input.KeyCode] then
			return
		end
		keyMode = true
		run(PopupLogic.CloseTop(sim))
		refreshFocus()
	end))

	ui.SetProgress(0, p.Target)
	ui.SetLives(nil)
	ui.SetTimer(nil)
	if Common.Device() == "Gamepad" then
		local hint = Common.Hint(stage, "A : ferme la pub du dessus", 0.08)
		task.delay(2.5, function()
			hint:Destroy()
		end)
	end

	Common.Loop(bin, function(dt: number)
		if finished then
			return
		end
		run(PopupLogic.Step(sim, dt))
		-- Pubs qui se promènent
		for _, w in sim.Windows do
			local view = views[w.Id]
			if view and (w.Vx ~= 0 or w.Vy ~= 0) then
				view.Root.Position = At(w.X, w.Y)
			end
		end
		refreshFocus()
		-- Jauge de RAM : verte, puis orange, puis rouge qui clignote.
		fill.Size = UDim2.fromScale(math.clamp(sim.Ram, 0, 1), 1)
		fill.BackgroundColor3 = if sim.Ram < 0.5 then C.Good elseif sim.Ram < 0.8 then C.Amber else C.Bad
		if sim.Ram >= 0.8 then
			fill.BackgroundTransparency = 0.25 + 0.25 * math.sin(os.clock() * 12)
		else
			fill.BackgroundTransparency = 0
		end
		local shown = math.floor(sim.Ram * 100 + 0.5)
		if shown ~= shownPercent then
			shownPercent = shown
			percent.Text = `{shown} %`
		end
	end, function()
		done(false)
	end)

	return function()
		finished = true
		bin:Clean()
	end
end

return Popup
