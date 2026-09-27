--!nonstrict
-- HUD de partie RAMPAGE : chrono, barre de destruction à 3 crans d'étoiles,
-- cash gagné, combo, gros boutons STOMP / ROAR (pensés pour le pouce, avec
-- anneau de recharge), bouton EXIT, bannières et flashs d'écran.
-- Construit une seule fois, réinitialisé à chaque partie ; piloté par
-- World/RampageController.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rampage = require(Shared.Config.Rampage)
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Kit)
local Audio = require(script.Parent.Parent.Controllers.Audio)

local C = Kit.Colors
local F = Kit.Fonts

local RampageHud = {}

local layer: ScreenGui? = nil
local ui: any = {}
local handlers: { [string]: () -> () } = {}
local run: any = nil -- état de la partie affichée

local function setLit(icon: GuiObject, lit: boolean)
	if icon:IsA("ImageLabel") then
		icon.ImageTransparency = if lit then 0 else 0.6
		icon.ImageColor3 = if lit then Color3.new(1, 1, 1) else Color3.fromRGB(90, 80, 110)
	elseif icon:IsA("TextLabel") then
		icon.TextTransparency = if lit then 0 else 0.6
	end
end

-- Surcouche de recharge d'un bouton rond : voile qui se vide + anneau coloré.
local function cooldownOverlay(button: GuiObject, z: number): any
	local ring = Kit.new("Frame", {
		Name = "Ring",
		Size = UDim2.new(1, 14, 1, 14),
		Position = UDim2.new(0.5, 0, 0.5, 3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z - 1,
		Parent = button,
	}, { Kit.Round() })
	local stroke = Kit.new("UIStroke", { Thickness = 6, Color = C.Radioactive, Parent = ring })
	local group = Kit.new("CanvasGroup", {
		Name = "Cooldown",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = z + 10,
		Parent = button,
	}, { Kit.Round() })
	local fill = Kit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 0),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = z + 11,
		Parent = group,
	})
	local label = Kit.Text({
		Name = "Seconds",
		Size = UDim2.fromScale(0.6, 0.34),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "",
		FontFace = F.Title,
		TextColor3 = C.White,
		ZIndex = z + 12,
		Parent = button,
	})
	local face = button:FindFirstChild("Face")
	local content = face and face:FindFirstChild("Content")
	return { Stroke = stroke, Fill = fill, Label = label, Content = content, Ready = true, Button = button }
end

local function updateCooldown(cd: any, left: number, duration: number)
	local ready = left <= 0
	cd.Fill.Size = UDim2.fromScale(1, if ready then 0 else math.clamp(left / duration, 0, 1))
	cd.Label.Text = if ready or duration < 1 then "" else string.format("%.1f", left)
	if ready ~= cd.Ready then
		cd.Ready = ready
		cd.Stroke.Color = if ready then C.Radioactive else C.InkSoft
		if cd.Content and duration >= 1 then
			-- recharge longue : le compte à rebours remplace le texte du bouton
			cd.Content.Visible = ready
		end
		if ready and duration >= 1 then
			Kit.Punch(cd.Button, 0.12)
			Audio.Play("ui_tab", { Volume = 0.7 })
		end
	end
end

local function call(name: string)
	return function()
		local fn = handlers[name]
		if fn then
			fn()
		end
	end
end

local function build()
	local gui = Kit.Layer("RampageHud", 12)
	gui.Enabled = false
	layer = gui

	-- Chrono + destruction (haut, centre)
	local top = Kit.new("Frame", {
		Name = "Top",
		Size = UDim2.fromOffset(560, 126),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.AutoScale(top)
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Gradient = "Ink", Parent = top })
	Kit.Icon("timer", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(12, 9), ZIndex = 4, Parent = body })
	ui.Clock = Kit.Text({
		Name = "Clock",
		Size = UDim2.fromOffset(96, 44),
		Position = UDim2.fromOffset(56, 7),
		Text = "",
		FontFace = F.Title,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 40,
		ZIndex = 4,
		Parent = body,
	})
	local _, setTime = Kit.ProgressBar({ Name = "TimeBar", Size = UDim2.fromOffset(384, 22), Position = UDim2.fromOffset(158, 19), Color = "Magma", Value = 1, ZIndex = 4, Parent = body })
	ui.SetTime = setTime
	ui.Percent = Kit.Text({
		Name = "Percent",
		Size = UDim2.fromOffset(240, 22),
		Position = UDim2.fromOffset(18, 60),
		Text = "",
		FontFace = F.Impact,
		TextColor3 = C.Paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		ZIndex = 4,
		Parent = body,
	})
	local bar, setDestruction = Kit.ProgressBar({ Name = "DestructionBar", Size = UDim2.fromOffset(500, 24), Position = UDim2.fromOffset(18, 90), Color = "Radioactive", ZIndex = 4, Parent = body })
	ui.SetDestruction = setDestruction
	ui.StarIcons = {}
	for i, threshold in Rampage.Stars do
		Kit.new("Frame", {
			Name = "Tick" .. i,
			Size = UDim2.new(0, 4, 1, 8),
			Position = UDim2.new(threshold, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = bar,
		})
		ui.StarIcons[i] = Kit.Icon("star", {
			Name = "Star" .. i,
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.new(threshold, 0, 0, -2),
			AnchorPoint = Vector2.new(0.5, 1),
			ZIndex = 9,
			Parent = bar,
		})
	end

	-- Cash gagné (haut, gauche)
	local cashBox = Kit.new("Frame", {
		Name = "CashBox",
		Size = UDim2.fromOffset(250, 84),
		Position = UDim2.fromOffset(16, 14),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.AutoScale(cashBox)
	local _, cashBody = Kit.Panel({ Size = UDim2.fromScale(1, 1), Gradient = "Ink", Rotation = -2, Parent = cashBox })
	Kit.Icon("cash", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(10, 8), ZIndex = 4, Parent = cashBody })
	ui.Cash = Kit.Text({
		Name = "Cash",
		Size = UDim2.fromOffset(180, 42),
		Position = UDim2.fromOffset(62, 6),
		Text = "$0",
		FontFace = F.Title,
		TextColor3 = C.Cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 38,
		ZIndex = 4,
		Parent = cashBody,
	})
	ui.Smashed = Kit.Text({
		Name = "Smashed",
		Size = UDim2.fromOffset(226, 24),
		Position = UDim2.fromOffset(12, 52),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		MaxTextSize = 18,
		ZIndex = 4,
		Parent = cashBody,
	})

	-- Sortie (haut, droite)
	local exitBox = Kit.new("Frame", {
		Name = "ExitBox",
		Size = UDim2.fromOffset(124, 52),
		Position = UDim2.new(1, -16, 0, 18),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.AutoScale(exitBox)
	Kit.Button({ Name = "Leave", Text = "EXIT", Icon = "exit", IconSize = 28, TextSize = 22, Color = "Red", Size = UDim2.fromScale(1, 1), OnClick = call("Leave"), Parent = exitBox })

	-- Combo (centre)
	ui.Combo = Kit.Text({
		Name = "Combo",
		Size = UDim2.fromOffset(460, 76),
		Position = UDim2.fromScale(0.5, 0.27),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -4,
		Text = "",
		FontFace = F.Impact,
		TextColor3 = C.Gold,
		Stroke = 4,
		MaxTextSize = 70,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})

	-- Boutons d'action (bas, droite) : gros, ronds, pour le pouce
	local pad = Kit.new("Frame", {
		Name = "Actions",
		Size = UDim2.fromOffset(300, 290),
		Position = UDim2.new(1, -24, 1, -24),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.AutoScale(pad)
	local stompButton = Kit.Button({
		Name = "Stomp",
		Text = "STOMP",
		Icon = "💥",
		IconSize = 30,
		TextSize = 26,
		Color = "Magma",
		Corner = 75,
		Size = UDim2.fromOffset(150, 150),
		Position = UDim2.new(1, 0, 1, -30),
		AnchorPoint = Vector2.new(1, 1),
		Sound = "whoosh",
		ZIndex = 5,
		OnClick = call("Stomp"),
		Parent = pad,
	})
	local roarButton = Kit.Button({
		Name = "Roar",
		Text = "ROAR",
		Icon = "fire",
		IconSize = 26,
		TextSize = 22,
		Color = "Purple",
		Corner = 56,
		Size = UDim2.fromOffset(112, 112),
		Position = UDim2.new(1, -164, 1, -150),
		AnchorPoint = Vector2.new(1, 1),
		Sound = "whoosh",
		ZIndex = 5,
		OnClick = call("Roar"),
		Parent = pad,
	})
	ui.StompCd = cooldownOverlay(stompButton, 5)
	ui.RoarCd = cooldownOverlay(roarButton, 5)
	if UserInputService.KeyboardEnabled then
		for _, hint in { { stompButton, "CLICK / F" }, { roarButton, "R" } } do
			Kit.Chip({ Text = hint[2], Color = C.Ink, Size = UDim2.fromOffset(96, 24), Position = UDim2.new(0.5, 0, 1, 16), AnchorPoint = Vector2.new(0.5, 0), TextSize = 16, ZIndex = 20, Parent = hint[1] })
		end
	end

	-- Astuce de départ (bas, centre)
	ui.Tip = Kit.Text({
		Name = "Tip",
		Size = UDim2.fromOffset(640, 34),
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.White,
		MaxTextSize = 26,
		ZIndex = 20,
		Parent = gui,
	})

	-- Flash d'écran + bannière
	ui.Flash = Kit.new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Red, BackgroundTransparency = 1, ZIndex = 1, Parent = gui })
	ui.BannerHolder = Kit.new("Frame", {
		Name = "Banner",
		Size = UDim2.fromOffset(700, 200),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	})
	Kit.AutoScale(ui.BannerHolder)
	Kit.Starburst({ Size = UDim2.fromOffset(520, 520), Color = C.Gold, Transparency = 0.7, ZIndex = 30, Parent = ui.BannerHolder })
	ui.BannerText = Kit.Text({
		Name = "Title",
		Size = UDim2.fromOffset(700, 110),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -5,
		Text = "",
		FontFace = F.Impact,
		TextColor3 = C.Magma,
		Stroke = 6,
		MaxTextSize = 110,
		ZIndex = 32,
		Parent = ui.BannerHolder,
	})
	ui.BannerSub = Kit.Text({
		Name = "Sub",
		Size = UDim2.fromOffset(620, 40),
		Position = UDim2.fromScale(0.5, 0.82),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "",
		FontFace = F.Title,
		TextColor3 = C.White,
		MaxTextSize = 34,
		ZIndex = 32,
		Parent = ui.BannerHolder,
	})
end

-- Affiche le HUD pour une nouvelle partie. actions : { Stomp, Roar, Leave }
function RampageHud.Show(args: any, actions: { [string]: () -> () })
	handlers = actions
	if not layer then
		build()
	end
	local state = {
		Duration = math.max(1, args.EndsAt - args.StartAt),
		EndsAt = args.EndsAt,
		Total = args.Buildings,
		DistrictName = string.upper(args.DistrictName),
		Stars = 0,
		LastSecond = -1,
		ComboHide = 0,
		CashValue = 0,
	}
	run = state
	ui.Clock.Text = Format.Clock(state.Duration)
	ui.Clock.TextColor3 = C.Gold
	ui.SetTime(1, true)
	ui.SetDestruction(0, true)
	ui.Percent.Text = "DESTRUCTION 0%"
	for _, icon in ui.StarIcons do
		setLit(icon, false)
	end
	ui.Cash:SetAttribute("Value", 0)
	ui.Cash.Text = "$0"
	ui.Smashed.Text = ("%s • 0/%d SMASHED"):format(state.DistrictName, state.Total)
	ui.Combo.Visible = false
	ui.BannerHolder.Visible = false
	ui.Flash.BackgroundTransparency = 1
	ui.Tip.Text = if args.Easy then "Smash buildings to earn stars! Walk into tiny ones to CRUSH them." else "Walk into tiny buildings to CRUSH them • Dodge the foam darts!"
	ui.Tip.TextTransparency = 0
	task.delay(7, function()
		if run == state then
			Kit.Tween(ui.Tip, 0.6, { TextTransparency = 1 })
		end
	end)
	updateCooldown(ui.StompCd, 0, Rampage.Stomp.Cooldown)
	updateCooldown(ui.RoarCd, 0, Rampage.Roar.Cooldown)
	if layer then
		layer.Enabled = true
	end
end

function RampageHud.Hide()
	run = nil
	handlers = {}
	if layer then
		layer.Enabled = false
	end
end

function RampageHud.SetEndsAt(endsAt: number)
	if run then
		run.EndsAt = endsAt
	end
end

-- Appelé à chaque image par le contrôleur.
function RampageHud.Update(now: number, stompLeft: number, roarLeft: number)
	if not run then
		return
	end
	local remaining = math.max(0, run.EndsAt - now)
	local second = math.ceil(remaining)
	if second ~= run.LastSecond then
		run.LastSecond = second
		ui.Clock.Text = Format.Clock(second)
		if second <= 10 and second > 0 then
			ui.Clock.TextColor3 = C.Red
			Kit.Punch(ui.Clock, 0.25)
			Audio.Play("countdown_beep", { Volume = 0.6 })
		else
			ui.Clock.TextColor3 = C.Gold
		end
	end
	ui.SetTime(remaining / run.Duration, true)
	updateCooldown(ui.StompCd, stompLeft, Rampage.Stomp.Cooldown)
	updateCooldown(ui.RoarCd, roarLeft, Rampage.Roar.Cooldown)
	if ui.Combo.Visible and now > run.ComboHide then
		ui.Combo.Visible = false
	end
end

local function addCash(amount: number)
	run.CashValue += amount
	Kit.CountTo(ui.Cash, run.CashValue, Format.Cash, 0.4)
	Kit.Punch(ui.Cash, 0.15)
end

-- « x2.4 COMBO! » (à partir du 2e coup enchaîné).
local function showCombo(mult: number, count: number, now: number)
	if not run or count < 1 then
		return
	end
	ui.Combo.Text = ("x%.1f COMBO!"):format(mult)
	ui.Combo.TextColor3 = if mult >= Rampage.Combo.Max then C.Pink elseif mult >= 2 then C.Magma else C.Gold
	ui.Combo.Visible = true
	ui.Combo.Rotation = math.random(-7, 3)
	Kit.Pop(ui.Combo, 0.6, 0.25)
	run.ComboHide = now + Rampage.Combo.Window
end

-- Immeuble détruit : barre, cash, combo.
function RampageHud.Smash(args: any, now: number)
	if not run then
		return
	end
	ui.SetDestruction(args.Destruction)
	ui.Percent.Text = ("DESTRUCTION %d%%"):format(Rampage.Percent(args.Destruction))
	ui.Smashed.Text = ("%s • %d/%d SMASHED"):format(run.DistrictName, args.Smashed, run.Total)
	addCash(args.Cash or 0)
	showCombo(args.Combo, args.ComboCount or 0, now)
end

function RampageHud.Cash(amount: number)
	if run then
		addCash(amount)
	end
end

function RampageHud.Star(stars: number)
	if not run then
		return
	end
	for i = run.Stars + 1, math.min(stars, #ui.StarIcons) do
		local icon = ui.StarIcons[i]
		setLit(icon, true)
		Kit.Pop(icon, 2.2, 0.5)
	end
	run.Stars = math.max(run.Stars, stars)
	Audio.Play("reward_claim")
end

-- Popup « -1s » / « +3s » sous le chrono.
function RampageHud.TimeDelta(delta: number)
	if not (run and layer) then
		return
	end
	local good = delta > 0
	local label = Kit.Text({
		Name = "TimeDelta",
		Size = UDim2.fromOffset(120, 50),
		Position = UDim2.new(0.5, -170, 0, 160),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = (if good then "+" else "") .. delta .. "s",
		FontFace = F.Impact,
		TextColor3 = if good then C.Radioactive else C.Red,
		Stroke = 3,
		MaxTextSize = 46,
		ZIndex = 25,
		Parent = layer,
	})
	Kit.Pop(label, 0.3, 0.3)
	Kit.Tween(label, 1.1, { Position = UDim2.new(0.5, -170, 0, 120), TextTransparency = 1 })
	task.delay(1.2, function()
		label:Destroy()
	end)
	Kit.Punch(ui.Clock, 0.3)
end

function RampageHud.Flash(color: Color3)
	if not run then
		return
	end
	ui.Flash.BackgroundColor3 = color
	ui.Flash.BackgroundTransparency = 0.55
	Kit.Tween(ui.Flash, 0.45, { BackgroundTransparency = 1 })
end

function RampageHud.Banner(text: string, sub: string?, color: Color3?, duration: number?)
	if not run then
		return
	end
	ui.BannerText.Text = text
	ui.BannerText.TextColor3 = color or C.Magma
	ui.BannerSub.Text = sub or ""
	ui.BannerHolder.Visible = true
	Kit.Pop(ui.BannerHolder, 0.3, 0.45)
	local token = {}
	run.BannerToken = token
	task.delay(duration or 1.6, function()
		if run and run.BannerToken == token then
			ui.BannerHolder.Visible = false
		end
	end)
end

return RampageHud
