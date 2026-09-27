--!nonstrict
-- ÉVOLUTION (rebirth) : niveau actuel, conditions en direct (cash + kaiju ADULTE
-- sacrifié), récompenses, avertissement de remise à zéro, gros bouton EVOLVE et
-- célébration animée après succès.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Growth = require(Shared.Config.Growth)
local Calc = require(Shared.Logic.Calc)
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Parent.Kit)
local Viewport = require(script.Parent.Parent.Viewport)
local Controllers = script.Parent.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local UIRegistry = require(Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts
local LocalPlayer = Players.LocalPlayer

local Rebirth = {}

----------------------------------------------------------------------------
-- Aides
----------------------------------------------------------------------------

local function anchorOf(uid: string): any
	local root = Workspace:FindFirstChild("Kaijus")
	local folder = root and root:FindFirstChild(tostring(LocalPlayer.UserId))
	return folder and folder:FindFirstChild(uid)
end

local function stageOf(rec: any): number
	local stage = Calc.Stage(rec)
	local anchor = anchorOf(rec.Uid)
	if anchor then
		stage = math.max(stage, anchor:GetAttribute("Stage") or 1)
	end
	return stage
end

local function isCarried(uid: string): boolean
	local anchor = anchorOf(uid)
	return anchor ~= nil and (anchor:GetAttribute("CarriedBy") or 0) ~= 0
end

-- Même logique que le serveur : le moins précieux des kaijus éligibles.
local function findSacrifice(needRarity: string): any
	local need = Rarities.Get(needRarity).Order
	local best, bestIncome = nil, math.huge
	for _, rec in State.Get("Kaijus") or {} do
		if not rec.Egg and rec.Species and Rarities.Get(rec.Rarity).Order >= need and stageOf(rec) >= 3 and not isCarried(rec.Uid) then
			local income = Calc.BaseIncome(rec)
			if income < bestIncome then
				best, bestIncome = rec, income
			end
		end
	end
	return best
end

local function multText(x: number): string
	return "x" .. Format.Short(x)
end

local function inkText(props: { [string]: any }): TextLabel
	props.Stroke = false
	props.FontFace = props.FontFace or F.Body
	props.TextColor3 = props.TextColor3 or C.Ink
	return Kit.Text(props)
end

local function setBreathing(button: GuiObject, on: boolean)
	if button:GetAttribute("Breathing") == on then
		return
	end
	button:SetAttribute("Breathing", on)
	if on then
		Kit.Breathe(button, 0.06, 0.7)
	else
		Kit.Tween(Kit.ScaleOf(button), 0.2, { Scale = 1 })
	end
	if not button:GetAttribute("BreatheHooked") then
		button:SetAttribute("BreatheHooked", true)
		button.MouseLeave:Connect(function()
			task.delay(0.25, function()
				if button:GetAttribute("Breathing") then
					Kit.Breathe(button, 0.06, 0.7)
				end
			end)
		end)
	end
end

-- Secousse sans dérive : la position d'origine est mémorisée une fois et une
-- nouvelle secousse remplace la précédente.
local shakeBase: { [Instance]: UDim2 } = {}
local shakeToken: { [Instance]: number } = {}
local function safeShake(inst: GuiObject, intensity: number, duration: number)
	local base = shakeBase[inst]
	if not base then
		base = inst.Position
		shakeBase[inst] = base
	end
	local token = (shakeToken[inst] or 0) + 1
	shakeToken[inst] = token
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local mine = shakeToken[inst] == token
		if t > duration or not mine or not inst.Parent then
			conn:Disconnect()
			if mine then
				inst.Position = base
			end
			return
		end
		local k = (1 - t / duration) * intensity
		inst.Position = base + UDim2.fromOffset((math.random() - 0.5) * 2 * k, (math.random() - 0.5) * 2 * k)
	end)
end

-- Confettis BD qui explosent depuis le centre (créés une fois par célébration).
local function confetti(parent: GuiObject, count: number, colors: { Color3 })
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local dist = 180 + math.random() * 260
		local piece = Kit.new("Frame", {
			Size = UDim2.fromOffset(math.random(10, 20), math.random(6, 12)),
			Position = UDim2.fromScale(0.5, 0.45),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = colors[(i % #colors) + 1],
			Rotation = math.random(0, 360),
			ZIndex = 58,
			Parent = parent,
		}, { Kit.Corner(3), Kit.Stroke(2) })
		local target = UDim2.new(0.5, math.cos(angle) * dist, 0.45, math.sin(angle) * dist * 0.7)
		Kit.Tween(piece, 0.9 + math.random() * 0.5, { Position = target, Rotation = piece.Rotation + math.random(-400, 400) }, Enum.EasingStyle.Quint)
		task.delay(0.9, function()
			Kit.Tween(piece, 0.5, { BackgroundTransparency = 1, Position = target + UDim2.fromOffset(0, 60) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local stroke = piece:FindFirstChildOfClass("UIStroke")
			if stroke then
				Kit.Tween(stroke, 0.5, { Transparency = 1 })
			end
		end)
		task.delay(1.6, function()
			piece:Destroy()
		end)
	end
end

----------------------------------------------------------------------------
-- État
----------------------------------------------------------------------------

local win: any = nil
local ui: { [string]: any } = {}
local heartbeat: RBXScriptConnection? = nil
local accum = 0
local busy = false
local armed = false
local armToken = 0
local sacVp: any = nil
local sacUid: string? = nil
local eggVp: any = nil
local eggRarity = ""
local lastReady = { Cash = nil :: boolean?, Kaiju = nil :: boolean?, All = nil :: boolean? }
local celebrating = false

----------------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------------

local function statusDot(parent: Instance, pos: UDim2): Frame
	local dot = Kit.new("Frame", {
		Name = "Status",
		Size = UDim2.fromOffset(34, 34),
		Position = pos,
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = C.Red,
		ZIndex = 8,
		Parent = parent,
	}, { Kit.Round(), Kit.Stroke(3) })
	Kit.Text({
		Name = "Mark",
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "✗",
		FontFace = F.Body,
		Stroke = 2,
		ZIndex = 9,
		Parent = dot,
	})
	return dot
end

local function setStatus(dot: any, ok: boolean, previous: boolean?)
	dot.BackgroundColor3 = if ok then C.Radioactive else C.Red
	dot.Mark.Text = if ok then "✓" else "✗"
	if previous ~= nil and previous ~= ok then
		Kit.Pop(dot, 1.8, 0.45)
		if ok then
			Audio.Play("reward_claim", { Volume = 0.6 })
		end
	end
end

local function build()
	win = Kit.Window({
		Name = "Rebirth",
		Title = "EVOLUTION",
		Icon = "🧬",
		Color = "Pink",
		Size = UDim2.fromOffset(860, 540),
		RibbonWidth = 340,
		Rotation = -1,
	})
	local root: Frame = win.Frame
	ui.Root = root

	--------------------------------------------------------------- niveau
	local levelHolder, levelBody = Kit.Panel({
		Name = "Level",
		Size = UDim2.fromOffset(240, 300),
		Position = UDim2.fromOffset(0, 4),
		Rotation = -2.5,
		Gradient = "Ink",
		Corner = 18,
		Parent = root,
	})
	ui.LevelHolder = levelHolder
	local clip = Kit.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = levelBody,
	}, { Kit.Corner(18) })
	Kit.Starburst({
		Size = UDim2.fromOffset(520, 520),
		Position = UDim2.fromScale(0.5, 0.42),
		Color = C.Radioactive,
		Transparency = 0.7,
		Rays = 12,
		Period = 20,
		ZIndex = 2,
		Parent = clip,
	})
	Kit.Text({
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 12),
		Text = "EVOLUTION LEVEL",
		TextColor3 = C.Radioactive,
		MaxTextSize = 22,
		ZIndex = 4,
		Parent = levelBody,
	})
	local disc = Kit.new("Frame", {
		Name = "Disc",
		Size = UDim2.fromOffset(150, 150),
		Position = UDim2.new(0.5, 0, 0, 44),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.White,
		ZIndex = 4,
		Parent = levelBody,
	}, { Kit.Round(), Kit.Stroke(5), Kit.Gradient("Radioactive") })
	ui.Disc = disc
	ui.Level = Kit.Text({
		Name = "Level",
		Size = UDim2.fromScale(0.8, 0.7),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "0",
		FontFace = F.Impact,
		MaxTextSize = 110,
		Stroke = 5,
		ZIndex = 5,
		Parent = disc,
	})
	ui.Next = Kit.Text({
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 204),
		Text = "NEXT ▶ 1",
		TextColor3 = C.Gold,
		MaxTextSize = 24,
		ZIndex = 4,
		Parent = levelBody,
	})
	ui.CurMult = Kit.Chip({
		Name = "CurMult",
		Text = "CASH x1",
		Color = C.RadioactiveDark,
		Size = UDim2.new(1, -40, 0, 26),
		Position = UDim2.new(0.5, 0, 0, 238),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 4,
		Parent = levelBody,
	})
	ui.CurLuck = Kit.Chip({
		Name = "CurLuck",
		Text = "LUCK x1",
		Color = C.InkSoft,
		Size = UDim2.new(1, -40, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 268),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 4,
		Parent = levelBody,
	})

	--------------------------------------------------------------- conditions
	local reqHolder, reqBody = Kit.Panel({
		Name = "Requirements",
		Size = UDim2.fromOffset(276, 300),
		Position = UDim2.fromOffset(258, 4),
		Rotation = 1,
		Parent = root,
	})
	ui.ReqHolder = reqHolder
	Kit.Ribbon({
		Text = "REQUIREMENTS",
		Color = "Ink",
		Size = UDim2.fromOffset(210, 36),
		Position = UDim2.new(0.5, 0, 0, -16),
		Rotation = -2,
		ZIndex = 6,
		Parent = reqHolder,
	})
	-- cash
	local cashBox = Kit.new("Frame", {
		Name = "CashReq",
		Size = UDim2.new(1, -24, 0, 92),
		Position = UDim2.fromOffset(12, 30),
		BackgroundColor3 = C.Paper,
		ZIndex = 6,
		Parent = reqBody,
	}, { Kit.Corner(12), Kit.Stroke(2.5) })
	ui.CashBox = cashBox
	Kit.Text({
		Size = UDim2.new(1, -60, 0, 24),
		Position = UDim2.fromOffset(10, 8),
		Text = "💰 CASH",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Cash,
		MaxTextSize = 22,
		ZIndex = 7,
		Parent = cashBox,
	})
	ui.CashStatus = statusDot(cashBox, UDim2.new(1, -8, 0, 6))
	ui.CashText = inkText({
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 38),
		Text = "$0 / $0",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = cashBox,
	})
	local _, setCash = Kit.ProgressBar({
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 64),
		Color = "Radioactive",
		ZIndex = 7,
		Parent = cashBox,
	})
	ui.SetCash = setCash

	-- kaiju sacrifié
	local kBox = Kit.new("Frame", {
		Name = "KaijuReq",
		Size = UDim2.new(1, -24, 0, 150),
		Position = UDim2.fromOffset(12, 132),
		BackgroundColor3 = C.Paper,
		ZIndex = 6,
		Parent = reqBody,
	}, { Kit.Corner(12), Kit.Stroke(2.5) })
	ui.KBox = kBox
	ui.KTitle = Kit.Text({
		Size = UDim2.new(1, -60, 0, 40),
		Position = UDim2.fromOffset(10, 6),
		Text = "🦖 ADULT EPIC+",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Magma,
		TextWrapped = true,
		MaxTextSize = 20,
		ZIndex = 7,
		Parent = kBox,
	})
	ui.KStatus = statusDot(kBox, UDim2.new(1, -8, 0, 6))
	local sacFrame = Kit.new("Frame", {
		Name = "Sacrifice",
		Size = UDim2.fromOffset(84, 84),
		Position = UDim2.fromOffset(10, 54),
		BackgroundColor3 = C.White,
		ZIndex = 7,
		Parent = kBox,
	}, { Kit.Corner(10), Kit.Stroke(2.5), Kit.Gradient("Ink") })
	ui.SacFrame = sacFrame
	ui.SacEmpty = Kit.Text({
		Size = UDim2.fromScale(0.6, 0.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "?",
		TextColor3 = C.Gold,
		FontFace = F.Impact,
		ZIndex = 9,
		Parent = sacFrame,
	})
	ui.SacText = inkText({
		Size = UDim2.new(1, -110, 0, 84),
		Position = UDim2.fromOffset(102, 54),
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		ZIndex = 7,
		Parent = kBox,
	})

	--------------------------------------------------------------- récompenses
	local rewHolder, rewBody = Kit.Panel({
		Name = "Rewards",
		Size = UDim2.fromOffset(266, 300),
		Position = UDim2.fromOffset(550, 4),
		Rotation = -1,
		Gradient = "Gold",
		Parent = root,
	})
	ui.RewHolder = rewHolder
	Kit.Ribbon({
		Text = "REWARDS",
		Color = "Radioactive",
		Size = UDim2.fromOffset(180, 36),
		Position = UDim2.new(0.5, 0, 0, -16),
		Rotation = 2,
		ZIndex = 6,
		Parent = rewHolder,
	})
	local list = Kit.new("Frame", {
		Size = UDim2.new(1, -24, 1, -42),
		Position = UDim2.fromOffset(12, 32),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = rewBody,
	}, { Kit.List(Enum.FillDirection.Vertical, 8) })
	local function rewardRow(name: string, icon: string, order: number): any
		local row = Kit.new("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = C.Paper,
			LayoutOrder = order,
			ZIndex = 7,
			Parent = list,
		}, { Kit.Corner(12), Kit.Stroke(2.5) })
		Kit.Text({
			Name = "Icon",
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Text = icon,
			FontFace = F.Body,
			Stroke = false,
			ZIndex = 8,
			Parent = row,
		})
		local title = inkText({
			Name = "Title",
			Size = UDim2.new(1, -56, 0, 16),
			Position = UDim2.fromOffset(50, 6),
			Text = "",
			FontFace = F.Title,
			TextColor3 = C.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 8,
			Parent = row,
		})
		local value = Kit.Text({
			Name = "Value",
			Size = UDim2.new(1, -56, 0, 26),
			Position = UDim2.fromOffset(50, 22),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 24,
			Stroke = 2.5,
			ZIndex = 8,
			Parent = row,
		})
		return { Frame = row, Title = title, Value = value }
	end
	ui.RMult = rewardRow("Mult", "💰", 1)
	ui.RMult.Title.Text = "CASH MULTIPLIER"
	ui.RLuck = rewardRow("Luck", "🍀", 2)
	ui.RLuck.Title.Text = "PERSONAL LUCK"
	ui.RGems = rewardRow("Gems", "💎", 3)
	ui.RGems.Title.Text = "GEMS"
	ui.REgg = rewardRow("Egg", "", 4)
	ui.REgg.Title.Text = "FREE EGG"
	ui.EggHolder = Kit.new("Frame", {
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = ui.REgg.Frame,
	})

	--------------------------------------------------------------- avertissement
	local warnHolder, warnBody = Kit.Panel({
		Name = "Warning",
		Size = UDim2.fromOffset(470, 116),
		Position = UDim2.fromOffset(0, 326),
		Rotation = 0.6,
		Gradient = "Red",
		Parent = root,
	})
	ui.WarnHolder = warnHolder
	Kit.Hazard({ Size = UDim2.new(1, -20, 0, 10), Position = UDim2.fromOffset(10, 6), ZIndex = 3, Parent = warnBody })
	Kit.Text({
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 20),
		Text = "⚠️ EVOLVING RESETS:",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Gold,
		MaxTextSize = 24,
		Stroke = 3,
		ZIndex = 4,
		Parent = warnBody,
	})
	Kit.Text({
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 48),
		Text = "Your CASH, ALL kaijus & eggs, extra NESTS",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = F.Body,
		MaxTextSize = 19,
		Stroke = 2,
		ZIndex = 4,
		Parent = warnBody,
	})
	Kit.Text({
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 74),
		Text = "You KEEP: gems, upgrades, potions, Kaijudex & passes",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = F.Body,
		TextColor3 = C.Paper,
		MaxTextSize = 16,
		Stroke = 1.5,
		ZIndex = 4,
		Parent = warnBody,
	})

	--------------------------------------------------------------- bouton
	local evolveWrap = Kit.new("Frame", {
		Name = "EvolveWrap",
		Size = UDim2.fromOffset(318, 104),
		Position = UDim2.fromOffset(492, 330),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = root,
	}, { Kit.List(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left) })
	ui.EvolveWrap = evolveWrap
	ui.Evolve = Kit.Button({
		Name = "Evolve",
		Text = "EVOLVE!",
		Icon = "🧬",
		IconSize = 44,
		TextSize = 44,
		Color = "Radioactive",
		Size = UDim2.fromOffset(318, 96),
		Corner = 20,
		Sound = "ui_click",
		ZIndex = 10,
		Parent = evolveWrap,
		OnClick = function()
			Rebirth._Evolve()
		end,
	})
	ui.Evolve.Activated:Connect(function()
		if ui.Evolve:GetAttribute("Disabled") then
			safeShake(evolveWrap, 5, 0.3)
			if lastReady.Cash == false then
				Kit.Punch(ui.CashBox, 0.08)
			end
			if lastReady.Kaiju == false then
				Kit.Punch(ui.KBox, 0.08)
			end
		end
	end)
	ui.EvolveHint = inkText({
		Size = UDim2.fromOffset(318, 18),
		Position = UDim2.fromOffset(492, 436),
		Text = "",
		ZIndex = 6,
		Parent = root,
	})

	--------------------------------------------------------------- niveau max
	local maxHolder, maxBody = Kit.Panel({
		Name = "Max",
		Size = UDim2.fromOffset(558, 438),
		Position = UDim2.fromOffset(258, 4),
		Rotation = 1,
		Gradient = "Ink",
		Corner = 18,
		Parent = root,
	})
	maxHolder.Visible = false
	ui.MaxHolder = maxHolder
	local maxClip = Kit.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = maxBody,
	}, { Kit.Corner(18) })
	Kit.Starburst({ Size = UDim2.fromOffset(900, 900), Color = C.Gold, Transparency = 0.6, Rays = 18, Period = 14, ZIndex = 2, Parent = maxClip })
	local maxText = Kit.Text({
		Size = UDim2.new(1, -40, 0, 90),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "MAX EVOLUTION!",
		FontFace = F.Impact,
		MaxTextSize = 80,
		Stroke = 5,
		ZIndex = 4,
		Parent = maxBody,
	})
	Kit.new("UIGradient", { Color = ColorSequence.new(C.Gold, C.Magma), Rotation = 90, Parent = maxText })
	Kit.Text({
		Size = UDim2.new(1, -60, 0, 30),
		Position = UDim2.fromScale(0.5, 0.62),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "You are the apex kaiju tamer. Nothing left to evolve!",
		FontFace = F.Body,
		MaxTextSize = 22,
		Stroke = 2,
		ZIndex = 4,
		Parent = maxBody,
	})

	--------------------------------------------------------------- célébration
	local party = Kit.new("TextButton", {
		Name = "Celebration",
		Size = UDim2.new(1, 20, 1, 20),
		Position = UDim2.fromOffset(-10, -10),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 50,
		Parent = root,
	}, { Kit.Corner(16) })
	ui.Party = party
end

----------------------------------------------------------------------------
-- Rendu
----------------------------------------------------------------------------

local function disarm()
	armed = false
	armToken += 1
	Kit.SetButtonColor(ui.Evolve, "Radioactive")
	Kit.SetButtonText(ui.Evolve, "EVOLVE!")
end

local function refresh()
	local level = State.Get("Rebirths") or 0
	local cash = State.Get("Cash") or 0
	local nr = Calc.NextRebirth(level)

	ui.Level.Text = tostring(level)
	ui.CurMult.Text.Text = "CASH " .. multText(Calc.RebirthMult(level))
	ui.CurLuck.Text.Text = "LUCK " .. multText(Calc.RebirthLuck(level))

	local isMax = nr == nil
	ui.MaxHolder.Visible = isMax
	ui.ReqHolder.Visible = not isMax
	ui.RewHolder.Visible = not isMax
	ui.WarnHolder.Visible = not isMax
	ui.EvolveWrap.Visible = not isMax
	ui.EvolveHint.Visible = not isMax
	if not nr then
		ui.Next.Text = "MAXED OUT!"
		setBreathing(ui.Evolve, false)
		return
	end
	ui.Next.Text = "NEXT ▶ LEVEL " .. tostring(level + 1)

	-- cash
	local cashOk = cash >= nr.Cost
	ui.CashText.Text = ("<b>%s</b> / %s"):format(Format.Cash(cash), Format.Cash(nr.Cost))
	ui.CashText.TextColor3 = if cashOk then C.RadioactiveDark else C.Ink
	ui.SetCash(cash / nr.Cost)
	setStatus(ui.CashStatus, cashOk, lastReady.Cash)
	lastReady.Cash = cashOk

	-- kaiju à sacrifier
	local needName = string.upper(nr.NeedRarity)
	ui.KTitle.Text = ("🦖 ADULT %s+ KAIJU"):format(needName)
	local sac = findSacrifice(nr.NeedRarity)
	local kaijuOk = sac ~= nil
	if sac then
		local species = Kaijus.Get(sac.Species)
		local stageName = string.upper(Growth.Get(stageOf(sac)).Name)
		ui.SacText.Text = ("<b>%s</b> (%s)\nwill be <font color=\"#d2202a\"><b>SACRIFICED</b></font> to evolve."):format(
			if species then species.Name else "Kaiju",
			stageName
		)
		if sacUid ~= sac.Uid then
			sacUid = sac.Uid
			if not sacVp then
				sacVp = Viewport.new({ Parent = ui.SacFrame, ZIndex = 8, Speed = 0.9 })
			end
			sacVp.Frame.Visible = true
			sacVp:Set(sac.Species, sac.Mutation)
			Kit.Pop(sacVp.Frame, 0.3, 0.45)
		end
		sacVp.Spin = win.IsOpen
		ui.SacEmpty.Visible = false
	else
		sacUid = nil
		if sacVp then
			sacVp.Frame.Visible = false
			sacVp.Spin = false
		end
		ui.SacEmpty.Visible = true
		ui.SacText.Text = ("Grow a <b>%s</b> (or better) kaiju to <b>ADULT</b> stage. It will be sacrificed."):format(needName)
	end
	setStatus(ui.KStatus, kaijuOk, lastReady.Kaiju)
	lastReady.Kaiju = kaijuOk

	-- récompenses
	ui.RMult.Value.Text = ("%s ▶ <font color=\"#28aa3c\">%s</font>"):format(multText(Calc.RebirthMult(level)), multText(nr.Mult))
	ui.RLuck.Value.Text = ("%s ▶ <font color=\"#28aa3c\">%s</font>"):format(multText(Calc.RebirthLuck(level)), multText(nr.Luck))
	ui.RGems.Value.Text = "+" .. Format.Comma(nr.Gems) .. " 💎"
	ui.RGems.Value.TextColor3 = C.Gem
	local eggR = Rarities.Get(nr.EggRarity)
	ui.REgg.Value.Text = string.upper(nr.EggRarity) .. " EGG"
	ui.REgg.Value.TextColor3 = eggR.Color
	if eggRarity ~= nr.EggRarity then
		eggRarity = nr.EggRarity
		if not eggVp then
			eggVp = Viewport.new({ Parent = ui.EggHolder, ZIndex = 9, Speed = 1.2 })
		end
		eggVp:SetEgg(nr.EggRarity)
	end
	if eggVp then
		eggVp.Spin = win.IsOpen
	end

	-- bouton
	local ready = cashOk and kaijuOk
	if not armed then
		Kit.SetDisabled(ui.Evolve, not ready)
	end
	setBreathing(ui.Evolve, ready)
	if ready then
		ui.EvolveHint.Text = "<b>READY!</b> Evolve for a permanent boost."
		ui.EvolveHint.TextColor3 = C.RadioactiveDark
	elseif not cashOk then
		ui.EvolveHint.Text = ("Need <b>%s</b> more cash"):format(Format.Cash(nr.Cost - cash))
		ui.EvolveHint.TextColor3 = C.MagmaDark
	else
		ui.EvolveHint.Text = ("Need an ADULT <b>%s+</b> kaiju"):format(needName)
		ui.EvolveHint.TextColor3 = C.MagmaDark
	end
	if lastReady.All == false and ready then
		Kit.Pop(ui.Evolve, 1.35, 0.5)
		Audio.Play("stage_up", { Volume = 0.7 })
	end
	lastReady.All = ready
end

----------------------------------------------------------------------------
-- Célébration
----------------------------------------------------------------------------

local function celebrate(level: number, reward: any)
	celebrating = true
	local party = ui.Party
	party:ClearAllChildren()
	Kit.Corner(16).Parent = party
	party.Visible = true
	party.BackgroundTransparency = 1
	Kit.Tween(party, 0.25, { BackgroundTransparency = 0.12 })

	local burstA = Kit.Starburst({ Size = UDim2.fromOffset(1100, 1100), Position = UDim2.fromScale(0.5, 0.45), Color = C.Gold, Transparency = 0.45, Rays = 16, Period = 8, ZIndex = 51, Parent = party })
	local burstB = Kit.Starburst({ Size = UDim2.fromOffset(800, 800), Position = UDim2.fromScale(0.5, 0.45), Color = C.Radioactive, Transparency = 0.55, Rays = 10, Period = 6, ZIndex = 51, Parent = party })
	burstB.Rotation = 10
	Kit.Tween(burstB, 6, { Rotation = -350 }, Enum.EasingStyle.Linear)
	Kit.Pop(burstA, 0.1, 0.7)
	Kit.Pop(burstB, 0.1, 0.6)

	-- rubans de danger qui traversent
	local top = Kit.Hazard({ Size = UDim2.new(1.3, 0, 0, 22), Position = UDim2.new(-0.15, 0, 0, 30), ZIndex = 52, Parent = party })
	top.Rotation = -4
	local bottom = Kit.Hazard({ Size = UDim2.new(1.3, 0, 0, 22), Position = UDim2.new(-0.15, 0, 1, -60), ZIndex = 52, Parent = party })
	bottom.Rotation = 3

	local title = Kit.Text({
		Size = UDim2.fromOffset(620, 90),
		Position = UDim2.fromScale(0.5, 0.2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "EVOLVED!",
		FontFace = F.Impact,
		MaxTextSize = 90,
		Stroke = 6,
		Rotation = -5,
		ZIndex = 56,
		Parent = party,
	})
	Kit.new("UIGradient", { Color = ColorSequence.new(C.Radioactive, C.Gold), Rotation = 90, Parent = title })
	Kit.Pop(title, 3.2, 0.5)

	local disc = Kit.new("Frame", {
		Size = UDim2.fromOffset(190, 190),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 54,
		Parent = party,
	}, { Kit.Round(), Kit.Stroke(6), Kit.Gradient("Radioactive") })
	local num = Kit.Text({
		Size = UDim2.fromScale(0.8, 0.72),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = tostring(math.max(level - 1, 0)),
		FontFace = F.Impact,
		MaxTextSize = 150,
		Stroke = 6,
		ZIndex = 55,
		Parent = disc,
	})
	Kit.Pop(disc, 0.2, 0.5)
	Audio.Play("rebirth")
	safeShake(win.Holder, 10, 0.4)

	-- le nouveau niveau s'écrase sur l'ancien
	task.delay(0.65, function()
		num.Text = tostring(level)
		Kit.Punch(disc, 0.7)
		safeShake(win.Holder, 16, 0.5)
		Audio.Play("fusion_boom", { Volume = 0.7 })
		confetti(party, 26, { C.Radioactive, C.Gold, C.Pink, C.Cyan, C.Magma })
		local flash = Kit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.1,
			ZIndex = 57,
			Parent = party,
		}, { Kit.Corner(16) })
		Kit.Tween(flash, 0.45, { BackgroundTransparency = 1 })
		task.delay(0.5, function()
			flash:Destroy()
		end)
	end)

	-- récompenses en cascade
	local chips = Kit.new("Frame", {
		Size = UDim2.new(1, -40, 0, 40),
		Position = UDim2.fromScale(0.5, 0.8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 56,
		Parent = party,
	}, { Kit.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local items = {}
	if reward then
		items = {
			{ "CASH " .. multText(reward.Mult), C.RadioactiveDark },
			{ "LUCK " .. multText(reward.Luck), C.InkSoft },
			{ "+" .. Format.Comma(reward.Gems) .. " 💎", C.Cyan },
			{ string.upper(reward.EggRarity) .. " EGG 🥚", Rarities.Get(reward.EggRarity).Color },
		}
	end
	for i, item in items do
		local chip = Kit.Chip({
			Text = item[1],
			Color = item[2],
			AutoWidth = true,
			TextSize = 22,
			Size = UDim2.fromOffset(0, 36),
			LayoutOrder = i,
			ZIndex = 57,
			Parent = chips,
		})
		chip.Visible = false
		task.delay(1 + i * 0.15, function()
			chip.Visible = true
			Kit.Pop(chip, 0.2, 0.45)
			Audio.Play("coin_tick", { Pitch = 1 + i * 0.1 })
		end)
	end

	local tap = Kit.Text({
		Size = UDim2.fromOffset(400, 20),
		Position = UDim2.new(0.5, 0, 1, -18),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "tap to continue",
		FontFace = F.Body,
		MaxTextSize = 18,
		Stroke = 1.5,
		ZIndex = 56,
		Parent = party,
	})
	tap.TextTransparency = 1
	task.delay(1.8, function()
		Kit.Tween(tap, 0.3, { TextTransparency = 0 })
	end)

	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		Kit.Tween(party, 0.25, { BackgroundTransparency = 1 })
		Kit.Tween(Kit.ScaleOf(disc), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		Kit.Tween(Kit.ScaleOf(title), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		Kit.Tween(Kit.ScaleOf(burstA), 0.25, { Scale = 0 })
		Kit.Tween(Kit.ScaleOf(burstB), 0.25, { Scale = 0 })
		task.delay(0.26, function()
			party.Visible = false
			party:ClearAllChildren()
			celebrating = false
			refresh()
			Kit.Pop(ui.LevelHolder, 0.5, 0.5)
			Kit.Punch(ui.Level, 0.6)
		end)
	end
	local conn
	conn = party.Activated:Connect(function()
		if conn then
			conn:Disconnect()
		end
		finish()
	end)
	task.delay(4.5, function()
		if conn then
			conn:Disconnect()
		end
		finish()
	end)
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

function Rebirth._Evolve()
	if busy or celebrating then
		return
	end
	local level = State.Get("Rebirths") or 0
	local nr = Calc.NextRebirth(level)
	if not nr then
		return
	end
	if not armed then
		armed = true
		armToken += 1
		local token = armToken
		Kit.SetButtonColor(ui.Evolve, "Red")
		Kit.SetButtonText(ui.Evolve, "SURE? RESET!")
		Kit.Punch(ui.Evolve, 0.2)
		safeShake(ui.WarnHolder, 8, 0.4)
		Kit.Punch(ui.WarnHolder, 0.08)
		task.delay(3, function()
			if armed and armToken == token then
				disarm()
			end
		end)
		return
	end
	disarm()
	busy = true
	local res = Remote.Call("Rebirth", {})
	busy = false
	if res.ok then
		sacUid = nil
		celebrate(res.level or (level + 1), nr)
		UIRegistry.Toast(("EVOLVED to level %d! Cash %s forever!"):format(res.level or (level + 1), multText(nr.Mult)), "Good")
	else
		refresh()
	end
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

local function onChanged()
	if win and win.IsOpen and not celebrating then
		refresh()
	end
end

function Rebirth.Init()
	build()
	State.Changed("Cash"):Connect(onChanged)
	State.Changed("Kaijus"):Connect(onChanged)
	State.Changed("Rebirths"):Connect(onChanged)

	win.Opened:Connect(function()
		-- vérification périodique (vol en cours, stade des kaijus)
		if heartbeat then
			heartbeat:Disconnect()
		end
		accum = 0
		heartbeat = RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum >= 0.5 then
				accum = 0
				onChanged()
			end
		end)
	end)
	win.Closed:Connect(function()
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
		if sacVp then
			sacVp.Spin = false
		end
		if eggVp then
			eggVp.Spin = false
		end
		if armed then
			disarm()
		end
	end)
end

function Rebirth.Open(_args: any?)
	lastReady.Cash = nil
	lastReady.Kaiju = nil
	lastReady.All = nil
	win:Open()
	refresh()
	-- apparition en cascade
	local items = { ui.LevelHolder, ui.ReqHolder, ui.RewHolder, ui.WarnHolder, ui.Evolve, ui.MaxHolder }
	for i, item in items do
		if item.Visible and (item ~= ui.Evolve or ui.EvolveWrap.Visible) then
			Kit.ScaleOf(item).Scale = 0.01
			task.delay(0.05 * i, function()
				Kit.Pop(item, 0.3, 0.5)
				if item:GetAttribute("Breathing") then
					task.delay(0.5, function()
						if item:GetAttribute("Breathing") then
							Kit.Breathe(item, 0.06, 0.7)
						end
					end)
				end
			end)
		end
	end
	task.delay(0.3, function()
		Kit.Punch(ui.Level, 0.4)
	end)
end

function Rebirth.Close()
	if win then
		win:Close()
	end
end

return Rebirth
