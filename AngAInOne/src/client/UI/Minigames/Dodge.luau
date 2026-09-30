--!strict
--[[
	Dodge : guide le paquet de données à travers les murs de virus jusqu'à l'arrivée.
	Un appui (tap, clic, Espace, flèche haut, A manette) le fait monter ; il redescend
	doucement tout seul. Rien ne bouge avant le premier appui.

	Règles et chiffres : DodgeLogic (pur, testé). Les murs ne sont construits que
	lorsqu'ils approchent de l'écran, et détruits dès qu'ils en sortent.
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Core = require(script.Parent.Core)
local Common = require(script.Parent.Common)
local DodgeLogic = require(script.Parent.DodgeLogic)

local New = Create.New
local C = Common.Colors
local At = Common.At
local Box = Common.Box
local Shape = Common.Shape

local Dodge = {}

local FLAP_KEYS = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.Z] = true,
	[Enum.KeyCode.ButtonA] = true,
}
local PACKET_SIZE = 60 -- dessin (la hitbox est plus petite : DodgeLogic.HIT_RADIUS)
local WALL_DRAW_W = 76 -- dessin (collision : 2 x DodgeLogic.WALL_HALF_W)
local CAP_SIZE = 84
local TRAIL = 5
local STARS = 26

function Dodge.Info(difficulty: number, device: Common.Device): Common.Info
	local p = DodgeLogic.Params(difficulty)
	return {
		Title = "TRANSFERT",
		Rule = "Passe dans les trous des murs de virus !",
		Target = `Traverse {p.Walls} murs !`,
		Controls = if device == "Gamepad"
			then "Appuie sur A pour monter"
			elseif device == "Touch" then "Tape l'écran pour monter"
			else "Clic ou Espace pour monter",
		Tip = "Astuce : de petits appuis, pas trop vite !",
		Goal = p.Walls,
		Unit = "murs",
		Icon = "Download",
		Accent = "AccentCyan",
	}
end

-- Paquet de données : cube cyan aux grands yeux qui regardent vers l'avant.
local function buildPacket(parent: Instance, size: UDim2, position: UDim2): Frame
	local root: Frame = New("Frame", {
		Name = "Packet",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = parent,
	})
	local glow = Shape(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1.35, 1.35), C.Cyan, UDim.new(1, 0), {
		Name = "Glow",
		BackgroundTransparency = 0.8,
		ZIndex = 1,
	})
	Common.Pulse(glow, { BackgroundTransparency = 0.9 }, 0.5)
	local body = Shape(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.9, 0.9), C.White, UDim.new(0.28, 0), {
		Name = "Body",
		ZIndex = 2,
	})
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Cyan:Lerp(C.White, 0.35), C.Cyan), Parent = body })
	New("UIStroke", { Color = C.Ink, Thickness = 2, Transparency = 0.3, Parent = body })
	-- Bandes "données" + yeux
	Shape(body, UDim2.fromScale(0.5, 0.82), UDim2.fromScale(0.7, 0.08), C.Ink, UDim.new(1, 0), {
		BackgroundTransparency = 0.6,
	})
	for _, x in { 0.42, 0.74 } do
		local eye = Shape(body, UDim2.fromScale(x, 0.42), UDim2.fromScale(0.26, 0.34), C.White, UDim.new(1, 0))
		Shape(eye, UDim2.fromScale(0.66, 0.55), UDim2.fromScale(0.55, 0.5), C.Ink, UDim.new(1, 0))
	end
	Shape(body, UDim2.fromScale(0.6, 0.66), UDim2.fromScale(0.2, 0.08), C.Ink, UDim.new(1, 0))
	return root
end

-- Mur : pilier violet glitché + virus à l'extrémité, côté trou.
local function buildPillar(parent: Instance, top: boolean): Frame
	local pillar: Frame = New("Frame", {
		Name = if top then "Top" else "Bottom",
		AnchorPoint = Vector2.new(0.5, if top then 1 else 0),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = parent,
	}, {
		Common.Corner(UDim.new(0, 14)),
		New("UIGradient", { Rotation = 0, Color = ColorSequence.new(C.VirusDark, C.Virus) }),
		New("UIStroke", { Color = C.VirusHot, Thickness = 2, Transparency = 0.3 }),
	})
	for i = 1, 3 do
		New("Frame", {
			Name = "Stripe",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, i / 4),
			Size = UDim2.new(0.8, 0, 0, 3),
			BackgroundColor3 = if i == 2 then C.GlitchA else C.VirusHot,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Parent = pillar,
		})
	end
	return pillar
end

type WallView = { Root: Frame, Top: Frame, Bottom: Frame, TopCap: Frame, BottomCap: Frame }

function Dodge.Illustrate(parent: Frame)
	for _, isTop in { true, false } do
		local y = if isTop then 0.3 else 0.72
		local pillar = buildPillar(parent, isTop)
		pillar.Position = UDim2.fromScale(0.62, y)
		pillar.Size = UDim2.new(0, 46, 0.3, 0)
		Common.Virus({
			Size = UDim2.fromOffset(52, 52),
			Position = UDim2.fromScale(0.62, y),
			ZIndex = 4,
			Parent = parent,
		})
	end
	for i = 1, 3 do
		Shape(
			parent,
			UDim2.fromScale(0.2 + i * 0.06, 0.52 + (3 - i) * 0.04),
			UDim2.fromOffset(10, 10),
			C.Cyan,
			UDim.new(1, 0),
			{
				BackgroundTransparency = 0.3 + i * 0.1,
			}
		)
	end
	local packet = buildPacket(parent, UDim2.fromOffset(56, 56), UDim2.fromScale(0.4, 0.5))
	Common.Pulse(packet, { Position = UDim2.fromScale(0.4, 0.42) }, 0.5)
end

function Dodge.Run(container: Frame, difficulty: number, finish: Common.Finish, hud: Common.Hud?): () -> ()
	local ui = hud or Common.NullHud
	local bin = Common.Bin()
	local sim = DodgeLogic.new(difficulty, Common.Seed())
	local p = sim.Params
	local finished = false

	local stage = Common.Stage(container)
	bin:Add(stage)
	local catcher = Common.Catcher(stage)

	-- Fond : flux de bits qui défilent (parallaxe sur deux plans).
	type Star = { Frame: Frame, X: number, Y: number, Depth: number }
	local stars: { Star } = {}
	local decor = Core.Rng(Common.Seed())
	for i = 1, STARS do
		local depth = if i % 2 == 0 then 0.35 else 0.7
		local size = if depth > 0.5 then 6 else 4
		local star: Frame = New("Frame", {
			Name = "Bit",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size * 2.4, size),
			BackgroundColor3 = if i % 3 == 0 then C.Virus else C.Cyan,
			BackgroundTransparency = if depth > 0.5 then 0.45 else 0.7,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = stage,
		}, { Common.Corner() })
		table.insert(
			stars,
			{ Frame = star, X = decor:Range(0, Core.FIELD_W), Y = decor:Range(10, Core.FIELD_H - 10), Depth = depth }
		)
	end

	-- Ligne d'arrivée
	local finishLine: Frame = New("Frame", {
		Name = "FinishLine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = Box(18, Core.FIELD_H),
		BackgroundColor3 = C.Good,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = stage,
	})
	for i = 0, 9 do
		Shape(finishLine, UDim2.fromScale(0.5, (i + 0.5) / 10), UDim2.fromScale(1, 0.05), C.White, nil, {
			BackgroundTransparency = if i % 2 == 0 then 0.1 else 1,
		})
	end
	New("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 8, 0.5, 0),
		Size = UDim2.fromOffset(160, 40),
		BackgroundTransparency = 1,
		Text = "ARRIVÉE",
		TextColor3 = C.Good,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Tag = "FontHeavy",
		Parent = finishLine,
	})

	-- Traînée + paquet
	local trail: { Frame } = {}
	local history: { number } = {}
	for i = 1, TRAIL do
		local dot = Shape(stage, At(DodgeLogic.PACKET_X, sim.Y), Box(18 - i * 2, 18 - i * 2), C.Cyan, UDim.new(1, 0), {
			Name = "Trail",
			BackgroundTransparency = 0.3 + i * 0.12,
			ZIndex = 5,
		})
		trail[i] = dot
		history[i] = sim.Y
	end
	local packet = buildPacket(stage, Box(PACKET_SIZE, PACKET_SIZE), At(DodgeLogic.PACKET_X, sim.Y))

	local walls: { [number]: WallView } = {}

	local function buildWall(wall: DodgeLogic.Wall): WallView
		local root: Frame = New("Frame", {
			Name = `Wall{wall.Index}`,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = Box(WALL_DRAW_W, Core.FIELD_H),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = stage,
		})
		local gapTop = wall.GapY - p.Gap / 2
		local gapBottom = wall.GapY + p.Gap / 2
		local top = buildPillar(root, true)
		top.Position = UDim2.fromScale(0.5, gapTop / Core.FIELD_H)
		top.Size = UDim2.new(1, 0, gapTop / Core.FIELD_H, 20)
		local bottom = buildPillar(root, false)
		bottom.Position = UDim2.fromScale(0.5, gapBottom / Core.FIELD_H)
		bottom.Size = UDim2.new(1, 0, 1 - gapBottom / Core.FIELD_H, 20)
		-- Virus aux extrémités (côté trou) : un peu plus larges que le pilier.
		local capScale = CAP_SIZE / WALL_DRAW_W
		local topCap = Common.Virus({
			Size = UDim2.fromScale(capScale, CAP_SIZE / Core.FIELD_H),
			Position = UDim2.fromScale(0.5, (gapTop - CAP_SIZE * 0.32) / Core.FIELD_H),
			ZIndex = 4,
			Parent = root,
		})
		local bottomCap = Common.Virus({
			Size = UDim2.fromScale(capScale, CAP_SIZE / Core.FIELD_H),
			Position = UDim2.fromScale(0.5, (gapBottom + CAP_SIZE * 0.32) / Core.FIELD_H),
			ZIndex = 4,
			Parent = root,
		})
		return { Root = root, Top = top, Bottom = bottom, TopCap = topCap, BottomCap = bottomCap }
	end

	local function done(success: boolean)
		if finished then
			return
		end
		finished = true
		finish(success, sim.Passed)
	end

	local hint = Common.Hint(
		stage,
		if Common.Device() == "Gamepad"
			then "Appuie sur A pour voler !"
			elseif Common.Device() == "Touch" then "Tape pour voler !"
			else "Clique ou Espace pour voler !",
		0.8
	)
	Common.Pulse(Motion.ScaleOf(hint), { Scale = 1.08 }, 0.5)

	local function handle(event: DodgeLogic.Event)
		local kind = event.Kind
		if kind == "Start" then
			if hint.Parent then
				hint:Destroy()
			end
		elseif kind == "Jump" then
			Common.Sound("Click", 1.35 + math.random() * 0.15)
			Motion.Pop(packet, 0.1)
		elseif kind == "Hit" then
			Common.Sound("Error")
			Common.Shake(stage, 12, 0.35)
			Common.Burst(stage, packet.Position, C.Cyan, 10, 70)
			Common.Popup(stage, packet.Position - UDim2.fromOffset(0, 30), "Aïe !", C.Bad, 28)
			local view = walls[event.Wall or 0]
			if view then
				Common.Glitch(view.TopCap)
				Common.Glitch(view.BottomCap)
			end
			ui.SetLives(DodgeLogic.LivesLeft(sim), p.Lives)
		elseif kind == "Pass" then
			Common.Sound("Collect", 1 + sim.Passed * 0.03)
			Common.Popup(stage, packet.Position - UDim2.fromOffset(0, 40), "+1", C.Gold, 26)
			ui.SetProgress(sim.Passed, p.Walls)
		elseif kind == "Win" then
			Common.Burst(stage, packet.Position, C.Good, 16, 110)
			done(true)
		elseif kind == "Lose" then
			done(false)
		end
	end

	local function flap()
		if finished then
			return
		end
		for _, event in DodgeLogic.Flap(sim) do
			handle(event)
		end
	end

	-- Entrées : appui immédiat sur l'écran, touches clavier / manette.
	GuiService.SelectedObject = nil
	bin:Add(catcher.InputBegan:Connect(function(input: InputObject)
		if Common.IsPress(input) then
			flap()
		end
	end))
	-- (on ignore seulement la saisie de texte, pas les actions déjà liées au personnage)
	bin:Add(UserInputService.InputBegan:Connect(function(input: InputObject)
		if FLAP_KEYS[input.KeyCode] and not UserInputService:GetFocusedTextBox() then
			flap()
		end
	end))

	ui.SetProgress(0, p.Walls)
	ui.SetLives(p.Lives, p.Lives)
	ui.SetTimer(DodgeLogic.TimeLeft(sim))

	local clock = 0
	Common.Loop(bin, function(dt: number)
		if finished then
			return
		end
		clock += dt
		for _, event in DodgeLogic.Step(sim, dt) do
			handle(event)
		end
		-- Paquet : flotte doucement avant le départ, s'incline selon la vitesse ensuite.
		local y = sim.Y
		if not sim.Started then
			y += math.sin(clock * 3) * 6
		end
		packet.Position = At(DodgeLogic.PACKET_X, y)
		packet.Rotation = if sim.Started then math.clamp(sim.Vy / 14, -22, 30) else 0
		-- Clignote pendant l'invincibilité.
		local blink = not finished and sim.Invulnerable > 0 and (clock * 12) % 2 < 1
		packet.Visible = not blink
		-- Traînée
		table.insert(history, 1, y)
		history[TRAIL + 1] = nil
		for i, dot in trail do
			dot.Position = At(DodgeLogic.PACKET_X - i * 14, history[i] or y)
			dot.Visible = sim.Started
		end
		-- Fond
		local speed = if sim.Started then p.Speed else 20
		for _, star in stars do
			star.X -= speed * star.Depth * dt
			if star.X < -10 then
				star.X += Core.FIELD_W + 20
			end
			star.Frame.Position = At(star.X, star.Y)
		end
		-- Murs visibles uniquement
		for _, wall in sim.Walls do
			local x = DodgeLogic.ScreenX(sim, wall.X)
			local visible = x > -CAP_SIZE and x < Core.FIELD_W + CAP_SIZE
			local view = walls[wall.Index]
			if visible then
				if not view then
					view = buildWall(wall)
					walls[wall.Index] = view
				end
				if view then
					view.Root.Position = At(x, 0)
				end
			elseif view then
				view.Root:Destroy()
				walls[wall.Index] = nil
			end
		end
		local finishX = DodgeLogic.ScreenX(sim, sim.Goal)
		finishLine.Visible = finishX < Core.FIELD_W + 40
		finishLine.Position = At(finishX, Core.FIELD_H / 2)
		ui.SetTimer(DodgeLogic.TimeLeft(sim))
	end, function()
		done(false)
	end)

	return function()
		finished = true
		bin:Clean()
	end
end

return Dodge
