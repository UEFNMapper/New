--!strict
--[[
	Memory : retrouve les paires de cartes "composants du PC" (CPU, RAM, carte
	graphique, ventilo…). Les cartes sont montrées quelques secondes au début.
	Chaque carte porte le nom du composant : on apprend en jouant !

	Contrôles : tap / clic sur une carte ; manette : croix pour choisir, A pour retourner.
	Règles et chiffres : MemoryLogic (pur, testé).
]]

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Style = require(script.Parent.Parent.Style)
local Icon = require(script.Parent.Parent.Components.Icon)
local Core = require(script.Parent.Core)
local Common = require(script.Parent.Common)
local MemoryLogic = require(script.Parent.MemoryLogic)

local New = Create.New
local C = Common.Colors
local Shape = Common.Shape

local Memory = {}

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x, y)
end

-- Catalogue des icônes (MemoryLogic.SYMBOLS entrées) : nom affiché + couleur (token).
Memory.Components = table.freeze({
	{ Name = "CPU", Color = "AccentCyan" },
	{ Name = "RAM", Color = "Success" },
	{ Name = "GPU", Color = "AccentViolet" },
	{ Name = "VENTILO", Color = "CurrencyChips" },
	{ Name = "SSD", Color = "CurrencyBits" },
	{ Name = "ALIM", Color = "AccentAmber" },
	{ Name = "PUCE IA", Color = "BrandAnga" },
	{ Name = "SOURIS", Color = "TextPrimary" },
	{ Name = "CLAVIER", Color = "Copper" },
	{ Name = "ÉCRAN", Color = "Danger" },
	{ Name = "DISQUE", Color = "TextMuted" },
	{ Name = "CLÉ USB", Color = "AccentViolet" },
})

-- Icône Components/Icon (taille fixe) étirée à l'échelle du parent.
local function libraryIcon(parent: Instance, kind: string, colorName: string, size: number)
	local icon = Icon.new(kind, 100, colorName)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = at(0.5, 0.5)
	icon.Size = at(size, size)
	icon.Parent = parent
end

-- Dessine l'icône du composant `symbol` dans `parent` (carré, tailles en échelle).
function Memory.DrawComponent(parent: Instance, symbol: number)
	local def = Memory.Components[symbol] or Memory.Components[1]
	local ink = Style.Color(def.Color)
	local dark = C.Ink
	if symbol == 1 then -- CPU
		libraryIcon(parent, "Cpu", def.Color, 0.9)
	elseif symbol == 2 then -- RAM : barrette avec puces et contacts dorés
		Shape(parent, at(0.5, 0.48), at(0.92, 0.36), ink, UDim.new(0.1, 0))
		for i = 0, 3 do
			Shape(parent, at(0.2 + i * 0.2, 0.46), at(0.14, 0.2), dark, UDim.new(0.15, 0))
		end
		for i = 0, 7 do
			Shape(parent, at(0.12 + i * 0.109, 0.7), at(0.05, 0.08), C.Gold)
		end
		Shape(parent, at(0.62, 0.66), at(0.04, 0.06), dark)
	elseif symbol == 3 then -- GPU : carte avec deux ventilateurs
		Shape(parent, at(0.52, 0.5), at(0.86, 0.52), ink, UDim.new(0.12, 0))
		Shape(parent, at(0.06, 0.5), at(0.05, 0.62), C.Metal, UDim.new(0.3, 0))
		for _, x in { 0.33, 0.7 } do
			local fan = Shape(parent, at(x, 0.5), at(0.32, 0.32), dark, UDim.new(1, 0))
			Shape(fan, at(0.5, 0.5), at(0.8, 0.16), ink, UDim.new(1, 0), { Rotation = 45 })
			Shape(fan, at(0.5, 0.5), at(0.8, 0.16), ink, UDim.new(1, 0), { Rotation = -45 })
			Shape(fan, at(0.5, 0.5), at(0.26, 0.26), dark, UDim.new(1, 0))
		end
	elseif symbol == 4 then -- Ventilateur
		local ring = Shape(parent, at(0.5, 0.5), at(0.84, 0.84), dark, UDim.new(1, 0), { BackgroundTransparency = 1 })
		New("UIStroke", { Color = ink, Thickness = 4, Parent = ring })
		for i = 0, 3 do
			Shape(parent, at(0.5, 0.5), at(0.66, 0.22), ink, UDim.new(1, 0), { Rotation = i * 45 + 20 })
		end
		Shape(parent, at(0.5, 0.5), at(0.22, 0.22), dark, UDim.new(1, 0))
		Shape(parent, at(0.5, 0.5), at(0.1, 0.1), ink, UDim.new(1, 0))
	elseif symbol == 5 then -- SSD : boîtier plat avec étiquette
		Shape(parent, at(0.5, 0.5), at(0.84, 0.58), ink, UDim.new(0.12, 0))
		Shape(parent, at(0.5, 0.42), at(0.62, 0.2), dark, UDim.new(0.2, 0))
		Shape(parent, at(0.3, 0.66), at(0.2, 0.06), dark, UDim.new(1, 0))
		Shape(parent, at(0.8, 0.68), at(0.06, 0.06), dark, UDim.new(1, 0))
	elseif symbol == 6 then -- Alimentation : boîte + éclair
		Shape(parent, at(0.5, 0.5), at(0.8, 0.72), ink, UDim.new(0.12, 0))
		local bolt = Icon.new("Bolt", 100, "BgDeep")
		bolt.AnchorPoint = Vector2.new(0.5, 0.5)
		bolt.Position = at(0.5, 0.5)
		bolt.Size = at(0.56, 0.56)
		bolt.Parent = parent
	elseif symbol == 7 then -- Puce IA
		libraryIcon(parent, "Bot", def.Color, 0.86)
	elseif symbol == 8 then -- Souris
		Shape(parent, at(0.5, 0.52), at(0.46, 0.76), ink, UDim.new(0.5, 0))
		Shape(parent, at(0.5, 0.3), at(0.04, 0.3), dark)
		Shape(parent, at(0.5, 0.3), at(0.08, 0.14), dark, UDim.new(1, 0))
		Shape(parent, at(0.5, 0.06), at(0.04, 0.12), ink)
	elseif symbol == 9 then -- Clavier
		Shape(parent, at(0.5, 0.52), at(0.94, 0.5), ink, UDim.new(0.12, 0))
		for row = 0, 2 do
			for col = 0, 4 do
				if not (row == 2 and col >= 1 and col <= 3) then
					Shape(parent, at(0.16 + col * 0.17, 0.38 + row * 0.13), at(0.11, 0.09), dark, UDim.new(0.2, 0))
				end
			end
		end
		Shape(parent, at(0.5, 0.64), at(0.44, 0.09), dark, UDim.new(0.2, 0))
	elseif symbol == 10 then -- Écran
		local screen = Shape(parent, at(0.5, 0.42), at(0.88, 0.6), dark, UDim.new(0.08, 0))
		New("UIStroke", { Color = ink, Thickness = 4, Parent = screen })
		Shape(screen, at(0.36, 0.4), at(0.4, 0.1), ink, UDim.new(1, 0), { BackgroundTransparency = 0.3 })
		Shape(screen, at(0.3, 0.62), at(0.28, 0.1), ink, UDim.new(1, 0), { BackgroundTransparency = 0.5 })
		Shape(parent, at(0.5, 0.8), at(0.1, 0.14), ink)
		Shape(parent, at(0.5, 0.88), at(0.46, 0.07), ink, UDim.new(1, 0))
	elseif symbol == 11 then -- Disque
		Shape(parent, at(0.5, 0.5), at(0.84, 0.84), ink, UDim.new(1, 0))
		local ring = Shape(parent, at(0.5, 0.5), at(0.56, 0.56), ink, UDim.new(1, 0), { BackgroundTransparency = 1 })
		New("UIStroke", { Color = dark, Thickness = 2, Transparency = 0.5, Parent = ring })
		Shape(parent, at(0.5, 0.5), at(0.22, 0.22), dark, UDim.new(1, 0))
		Shape(parent, at(0.34, 0.3), at(0.2, 0.08), C.White, UDim.new(1, 0), {
			Rotation = -35,
			BackgroundTransparency = 0.4,
		})
	else -- Clé USB
		Shape(parent, at(0.5, 0.26), at(0.3, 0.26), C.Metal, UDim.new(0.1, 0))
		Shape(parent, at(0.42, 0.22), at(0.07, 0.07), dark)
		Shape(parent, at(0.58, 0.22), at(0.07, 0.07), dark)
		Shape(parent, at(0.5, 0.62), at(0.42, 0.56), C.VirusHot, UDim.new(0.2, 0))
		Shape(parent, at(0.5, 0.78), at(0.12, 0.12), dark, UDim.new(1, 0))
	end
end

function Memory.Info(difficulty: number, device: Common.Device): Common.Info
	local p = MemoryLogic.Params(difficulty)
	local pairs = math.floor(p.Cols * p.Rows / 2)
	return {
		Title = "MÉMOIRE",
		Rule = "Retrouve les paires de composants !",
		Target = `Trouve les {pairs} paires !`,
		Controls = if device == "Gamepad"
			then "Croix pour choisir, A pour retourner"
			elseif device == "Touch" then "Tape sur deux cartes"
			else "Clique sur deux cartes",
		Tip = "Astuce : regarde bien les cartes au début !",
		Goal = pairs,
		Unit = "paires",
		Icon = "Cpu",
		Accent = "Success",
	}
end

type CardView = {
	Button: TextButton,
	Flipper: Frame,
	Back: Frame,
	Front: Frame,
	Stroke: UIStroke,
	Up: boolean,
	Token: number, -- invalide les retournements en cours
	Flash: number, -- invalide les clignotements de bordure en cours
}

-- Construit une carte (dos + face) dans `parent`.
local function buildCard(parent: Instance, symbol: number, size: UDim2, position: UDim2, name: string): CardView
	local button: TextButton = New("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = true,
		ZIndex = 2,
		Parent = parent,
	})
	-- Le "flipper" rétrécit en largeur puis s'élargit : effet de carte qui se retourne.
	local flipper: Frame = New("Frame", {
		Name = "Flipper",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(0.5, 0.5),
		Size = at(1, 1),
		BackgroundTransparency = 1,
		Parent = button,
	}, {
		Common.Corner(UDim.new(0, 12)),
	})
	local back: Frame = New("Frame", {
		Name = "Back",
		Size = at(1, 1),
		BorderSizePixel = 0,
		Tag = { "FillViolet", "RoundM" },
		Parent = flipper,
	}, {
		New("UIGradient", { Rotation = 60, Color = ColorSequence.new(C.White, C.VirusDark:Lerp(C.White, 0.45)) }),
	})
	-- Motif de circuit + puce au centre (dos de carte)
	Shape(back, at(0.5, 0.5), at(0.46, 0.38), C.Ink, UDim.new(0.2, 0), { BackgroundTransparency = 0.35 })
	Shape(back, at(0.5, 0.5), at(0.2, 0.16), C.Gold, UDim.new(0.3, 0))
	for _, y in { 0.18, 0.82 } do
		Shape(back, at(0.5, y), at(0.7, 0.03), C.White, nil, { BackgroundTransparency = 0.6 })
	end
	local front: Frame = New("Frame", {
		Name = "Front",
		Size = at(1, 1),
		BorderSizePixel = 0,
		Visible = false,
		Tag = { "GlassRaised", "RoundM" },
		Parent = flipper,
	})
	local art: Frame = New("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(0.5, 0.42),
		Size = at(0.72, 0.6),
		BackgroundTransparency = 1,
		Parent = front,
	}, {
		New("UIAspectRatioConstraint", { AspectRatio = 1 }),
	})
	Memory.DrawComponent(art, symbol)
	local def = Memory.Components[symbol] or Memory.Components[1]
	New("TextLabel", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = at(0.5, 0.96),
		Size = at(0.94, 0.2),
		BackgroundTransparency = 1,
		Text = def.Name,
		TextScaled = true,
		TextColor3 = Style.Color(def.Color),
		Tag = "FontHeavy",
		Parent = front,
	}, {
		New("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 9 }),
	})
	local stroke: UIStroke = New("UIStroke", {
		Color = C.White,
		Thickness = 3,
		Transparency = 0.8,
		Parent = flipper,
	})
	return {
		Button = button,
		Flipper = flipper,
		Back = back,
		Front = front,
		Stroke = stroke,
		Up = false,
		Token = 0,
		Flash = 0,
	}
end

-- Retourne la carte (animation de pincement horizontal).
local function setFace(view: CardView, up: boolean, instant: boolean?)
	if view.Up == up then
		return
	end
	view.Up = up
	view.Token += 1
	local token = view.Token
	if instant or Motion.IsReduced() then
		view.Front.Visible = up
		view.Back.Visible = not up
		view.Flipper.Size = at(1, 1)
		return
	end
	Motion.Tween(view.Flipper, { Size = at(0.02, 1.04) }, 0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.09, function()
		if view.Token ~= token or not view.Flipper.Parent then
			return
		end
		view.Front.Visible = up
		view.Back.Visible = not up
		Motion.Tween(view.Flipper, { Size = at(1, 1) }, 0.14, Enum.EasingStyle.Back)
	end)
end

function Memory.Illustrate(parent: Frame)
	-- Une paire trouvée (CPU + CPU), une carte cachée, une autre visible.
	local specs = {
		{ X = 0.2, Symbol = 1, Up = true },
		{ X = 0.4, Symbol = 1, Up = true },
		{ X = 0.6, Symbol = 2, Up = false },
		{ X = 0.8, Symbol = 3, Up = true },
	}
	for i, spec in specs do
		local view = buildCard(parent, spec.Symbol, UDim2.fromOffset(78, 100), UDim2.fromScale(spec.X, 0.5), `Card{i}`)
		setFace(view, spec.Up, true)
		if i <= 2 then
			view.Stroke.Color = C.Good
			view.Stroke.Transparency = 0
		end
	end
end

function Memory.Run(container: Frame, difficulty: number, finish: Common.Finish, hud: Common.Hud?): () -> ()
	local ui = hud or Common.NullHud
	local bin = Common.Bin()
	local sim = MemoryLogic.new(difficulty, Common.Seed())
	local p = sim.Params
	local finished = false

	local stage = Common.Stage(container)
	bin:Add(stage)

	-- Disposition : cartes au format portrait (0,8), le plus grandes possible, sous une
	-- bande libre en haut (bandeau "Mémorise !").
	local margin, gap, band = 16, 12, 40
	local slotW = (Core.FIELD_W - margin * 2 - gap * (p.Cols - 1)) / p.Cols
	local slotH = (Core.FIELD_H - band - margin - gap * (p.Rows - 1)) / p.Rows
	local cardH = math.min(slotH, slotW / 0.8)
	local cardW = cardH * 0.8
	local gridW = cardW * p.Cols + gap * (p.Cols - 1)
	local gridH = cardH * p.Rows + gap * (p.Rows - 1)
	local originX = (Core.FIELD_W - gridW) / 2
	local originY = band + (Core.FIELD_H - band - margin - gridH) / 2

	local views: { CardView } = {}

	local function done(success: boolean)
		if finished then
			return
		end
		finished = true
		finish(success, sim.Found)
	end

	-- Bordure colorée : `keep` = reste allumée (paire trouvée), sinon s'éteint.
	-- Le jeton évite qu'un ancien clignotement (erreur) n'éteigne une paire trouvée juste après.
	local function flash(view: CardView, color: Color3, keep: boolean)
		view.Flash += 1
		local token = view.Flash
		view.Stroke.Color = color
		view.Stroke.Transparency = 0
		-- Un nouveau tween remplace celui en cours sur la même propriété.
		Motion.Tween(view.Stroke, { Transparency = if keep then 0 else 0.8 }, if keep then 0.05 else 0.6)
		if not keep then
			task.delay(0.6, function()
				if view.Flash == token and view.Stroke.Parent then
					view.Stroke.Color = C.White
				end
			end)
		end
	end

	local function wiggle(view: CardView)
		if Motion.IsReduced() then
			return
		end
		task.spawn(function()
			for _, angle in { -8, 7, -5, 3, 0 } do
				if not view.Button.Parent then
					return
				end
				view.Button.Rotation = angle
				task.wait(0.05)
			end
		end)
	end

	-- Bandeau d'aperçu : "Mémorise !" + barre qui se vide.
	local banner = Common.Hint(stage, "Mémorise les cartes !", band / 2 / Core.FIELD_H)
	banner.Size = UDim2.fromOffset(0, 32)
	banner.TextSize = 20
	banner.ZIndex = 20
	local previewBar: Frame = New("Frame", {
		Name = "PreviewBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.new(1, -30, 0, 6),
		BackgroundColor3 = C.Gold,
		BorderSizePixel = 0,
		ZIndex = 21,
		Parent = banner,
	}, { Common.Corner() })
	Motion.Tween(previewBar, { Size = UDim2.new(0, 0, 0, 6) }, p.Preview, Enum.EasingStyle.Linear)

	local function handle(event: MemoryLogic.Event)
		local kind = event.Kind
		if kind == "Hide" then
			for _, index in event.Cards do
				setFace(views[index], false)
			end
			if banner.Parent then
				banner:Destroy()
				Common.Sound("Whoosh")
				Common.Focus(views[1].Button)
			end
		elseif kind == "Flip" then
			setFace(views[event.Cards[1]], true)
			Common.Sound("Click", 1.2)
		elseif kind == "Match" then
			for _, index in event.Cards do
				local view = views[index]
				flash(view, C.Good, true)
				Motion.Pop(view.Button, 0.18)
				Common.Burst(stage, view.Button.Position, C.Gold, 8, 60)
			end
			local where = views[event.Cards[2]].Button.Position
			Common.Popup(stage, where, "Paire !", C.Good, 28)
			Common.Sound("Collect", 1 + sim.Found * 0.04)
			ui.SetProgress(sim.Found, sim.Pairs)
		elseif kind == "Miss" then
			for _, index in event.Cards do
				flash(views[index], C.Bad, false)
				wiggle(views[index])
			end
			Common.Sound("Error")
			ui.SetLives(MemoryLogic.LivesLeft(sim), p.Lives)
		elseif kind == "Win" then
			for i, view in views do
				task.delay(i * 0.03, function()
					if view.Button.Parent then
						Motion.Pop(view.Button, 0.15)
					end
				end)
			end
			done(true)
		elseif kind == "Lose" then
			-- On montre la solution, pour apprendre.
			for _, view in views do
				setFace(view, true)
			end
			done(false)
		end
	end

	for index, card in sim.Cards do
		local col = (index - 1) % p.Cols
		local row = (index - 1) // p.Cols
		local view = buildCard(
			stage,
			card.Symbol,
			Common.Box(cardW, cardH),
			Common.At(originX + col * (cardW + gap) + cardW / 2, originY + row * (cardH + gap) + cardH / 2),
			`Card{index}`
		)
		setFace(view, true, true) -- aperçu : toutes les cartes visibles
		views[index] = view
		local function flip()
			if finished then
				return
			end
			for _, event in MemoryLogic.Flip(sim, index) do
				handle(event)
			end
		end
		bin:Add(view.Button.InputBegan:Connect(function(input: InputObject)
			if Common.IsPress(input) then
				flip()
			end
		end))
		bin:Add(view.Button.Activated:Connect(function()
			local last = UserInputService:GetLastInputType()
			if string.find(last.Name, "^Gamepad") or last == Enum.UserInputType.Keyboard then
				flip()
			end
		end))
	end

	ui.SetProgress(0, sim.Pairs)
	ui.SetLives(p.Lives, p.Lives)
	ui.SetTimer(MemoryLogic.TimeLeft(sim))

	Common.Loop(bin, function(dt: number)
		if finished then
			return
		end
		for _, event in MemoryLogic.Step(sim, dt) do
			handle(event)
		end
		ui.SetTimer(MemoryLogic.TimeLeft(sim))
	end, function()
		done(false)
	end)

	return function()
		finished = true
		Common.Unfocus(stage)
		bin:Clean()
	end
end

return Memory
