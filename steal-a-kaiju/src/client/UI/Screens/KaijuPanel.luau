--!nonstrict
-- Fiche « KAIJU FILE » : aperçu 3D, croissance en direct, nourriture, vente,
-- achat de croissance instantanée, fusion, choix du compagnon. Gère aussi les
-- œufs (compte à rebours).
--   UIRegistry.OpenKaiju(uid)  /  KaijuPanel.Open({ Uid = uid })

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Growth = require(Shared.Config.Growth)
local Economy = require(Shared.Config.Economy)
local Monetization = require(Shared.Config.Monetization)
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

local KaijuPanel = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 90)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(124, 255, 79)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(61, 224, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 61, 139)),
})

----------------------------------------------------------------------------
-- Aides
----------------------------------------------------------------------------

local function findRecord(uid: string?): any
	if not uid then
		return nil
	end
	for _, rec in State.Get("Kaijus") or {} do
		if rec.Uid == uid then
			return rec
		end
	end
	return nil
end

local function anchorOf(uid: string): any
	local root = Workspace:FindFirstChild("Kaijus")
	local folder = root and root:FindFirstChild(tostring(LocalPlayer.UserId))
	return folder and folder:FindFirstChild(uid)
end

-- Croissance extrapolée depuis l'ancre (sinon valeur du record).
local function liveGrowth(rec: any, anchor: any): (number, number)
	local rate = State.Get("GrowthRate") or 1
	if anchor then
		local g = anchor:GetAttribute("Growth")
		if type(g) == "number" then
			local stamp = anchor:GetAttribute("GrowthStamp") or Workspace:GetServerTimeNow()
			rate = anchor:GetAttribute("GrowthRate") or rate
			if (anchor:GetAttribute("CarriedBy") or 0) ~= 0 then
				return g, rate
			end
			return g + math.max(0, Workspace:GetServerTimeNow() - stamp) * rate, rate
		end
	end
	return rec.Growth or 0, rate
end

local function rarityText(id: string): string
	return string.upper(id)
end

-- Dégradé arc-en-ciel animé (textes / pastilles SECRET).
local function rainbow(parent: Instance, period: number?): UIGradient
	local g = parent:FindFirstChild("Rainbow") :: UIGradient?
	if not g then
		g = Kit.new("UIGradient", { Name = "Rainbow", Color = RAINBOW, Parent = parent })
		Kit.Tween(g :: UIGradient, period or 2.5, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	end
	return g :: UIGradient
end

local function clearRainbow(parent: Instance)
	local g = parent:FindFirstChild("Rainbow")
	if g then
		g:Destroy()
	end
end

-- Respiration qui reprend après le survol (Kit.Button remet l'échelle à 1).
local function setBreathing(button: GuiObject, on: boolean)
	if button:GetAttribute("Breathing") == on then
		return
	end
	button:SetAttribute("Breathing", on)
	if on then
		Kit.Breathe(button, 0.05, 0.75)
	else
		Kit.Tween(Kit.ScaleOf(button), 0.2, { Scale = 1 })
	end
	if not button:GetAttribute("BreatheHooked") then
		button:SetAttribute("BreatheHooked", true)
		button.MouseLeave:Connect(function()
			task.delay(0.25, function()
				if button:GetAttribute("Breathing") then
					Kit.Breathe(button, 0.05, 0.75)
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

-- Petite étiquette de prix Robux inclinée collée sur un bouton.
local function priceTag(button: GuiObject, text: string)
	local tag = Kit.Chip({
		Name = "PriceTag",
		Text = text,
		Color = C.Gold,
		TextColor = C.White,
		Size = UDim2.fromOffset(74, 26),
		Position = UDim2.new(1, 6, 0, -8),
		AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = 20,
		Parent = button,
	})
	Kit.Wobble(tag, 6, 0.9)
	return tag
end

-- Apparition élastique différée (relance la respiration si besoin).
local function popIn(item: GuiObject, delay: number, from: number?)
	Kit.ScaleOf(item).Scale = 0.01
	task.delay(delay, function()
		Kit.Pop(item, from or 0.3, 0.45)
		if item:GetAttribute("Breathing") then
			task.delay(0.46, function()
				if item:GetAttribute("Breathing") then
					Kit.Breathe(item, 0.05, 0.75)
				end
			end)
		end
	end)
end

local function inkText(props: { [string]: any }): TextLabel
	props.Stroke = false
	props.FontFace = props.FontFace or F.Body
	props.TextColor3 = props.TextColor3 or C.Ink
	return Kit.Text(props)
end

----------------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------------

local win: any = nil
local ui: { [string]: any } = {}
local vp: any = nil
local vpKey = ""
local currentUid: string? = nil
local renderConn: RBXScriptConnection? = nil
local busy = false

-- Mémoire des valeurs affichées (pour les « punch » sur changement)
local shown = {
	Stage = 0,
	Income = -1,
	Sell = -1,
	Stolen = false,
	Egg = nil :: boolean?,
	Remain = "",
	Mode = "",
	PricesDirty = true,
}
local sellArmed = false
local sellToken = 0
local lastRec: any = nil

local function build()
	win = Kit.Window({
		Name = "KaijuPanel",
		Title = "KAIJU FILE",
		Icon = "📋",
		Color = "Cyan",
		Size = UDim2.fromOffset(860, 540),
		RibbonWidth = 340,
		Rotation = 1,
	})
	local root: Frame = win.Frame

	------------------------------------------------------------------ gauche
	local cardHolder, card = Kit.Panel({
		Name = "Card",
		Size = UDim2.fromOffset(300, 356),
		Position = UDim2.fromOffset(2, 12),
		Rotation = -2.5,
		Gradient = "Cyan",
		Corner = 18,
		Parent = root,
	})
	ui.CardHolder = cardHolder
	ui.CardGradient = card:FindFirstChildOfClass("UIGradient")

	-- rayons tournants découpés proprement
	local burstClip = Kit.new("CanvasGroup", {
		Name = "BurstClip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	}, { Kit.Corner(18) })
	ui.Burst = Kit.Starburst({
		Size = UDim2.fromOffset(620, 620),
		Position = UDim2.fromScale(0.5, 0.42),
		Rays = 16,
		Color = C.White,
		Transparency = 0.55,
		Period = 18,
		ZIndex = 2,
		Parent = burstClip,
	})
	-- ombre au sol
	Kit.new("Frame", {
		Name = "Floor",
		Size = UDim2.fromOffset(190, 30),
		Position = UDim2.fromScale(0.5, 0.74),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.65,
		ZIndex = 3,
		Parent = card,
	}, { Kit.Round() })
	ui.VpHolder = Kit.new("Frame", {
		Name = "VpHolder",
		Size = UDim2.new(1, -16, 1, -86),
		Position = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = card,
	})
	-- plaque du stade
	local plate = Kit.new("Frame", {
		Name = "Plate",
		Size = UDim2.new(1, -30, 0, 58),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.Ink,
		Rotation = 2,
		ZIndex = 6,
		Parent = card,
	}, { Kit.Corner(12), Kit.Stroke(3, C.White) })
	ui.Plate = plate
	ui.PlateTitle = Kit.Text({
		Name = "Title",
		Size = UDim2.new(1, -16, 0.62, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "ADULT",
		TextColor3 = C.Radioactive,
		MaxTextSize = 34,
		ZIndex = 7,
		Parent = plate,
	})
	ui.PlateSub = Kit.Text({
		Name = "Sub",
		Size = UDim2.new(1, -16, 0.3, 0),
		Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "STAGE 3 / 5",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		Stroke = false,
		MaxTextSize = 16,
		ZIndex = 7,
		Parent = plate,
	})

	-- bandeau « BEING STOLEN! »
	local stolen = Kit.new("Frame", {
		Name = "Stolen",
		Size = UDim2.new(1, 30, 0, 50),
		Position = UDim2.new(0.5, 0, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -7,
		BackgroundColor3 = C.Red,
		Visible = false,
		ZIndex = 12,
		Parent = cardHolder,
	}, { Kit.Corner(8), Kit.Stroke(4) })
	Kit.Hazard({ Size = UDim2.new(1, -10, 0, 8), Position = UDim2.fromOffset(5, 3), ColorA = C.Gold, ZIndex = 13, Parent = stolen })
	Kit.Hazard({ Size = UDim2.new(1, -10, 0, 8), Position = UDim2.new(0, 5, 1, -11), ColorA = C.Gold, ZIndex = 13, Parent = stolen })
	Kit.Text({
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "🚨 BEING STOLEN! 🚨",
		ZIndex = 14,
		Stroke = 3,
		Parent = stolen,
	})
	ui.Stolen = stolen

	-- compagnon : sous la carte, aligné sur la rangée d'actions
	ui.BuddyButton = Kit.Button({
		Name = "SetBuddy",
		Text = "SET AS BUDDY",
		Icon = "🐾",
		IconSize = 30,
		TextSize = 24,
		Color = "Pink",
		Size = UDim2.fromOffset(296, 56),
		Position = UDim2.fromOffset(4, 380),
		ZIndex = 6,
		Parent = root,
		OnClick = function()
			KaijuPanel._SetBuddy()
		end,
	})

	------------------------------------------------------------------ droite
	local right = Kit.new("Frame", {
		Name = "Right",
		Size = UDim2.new(1, -324, 1, 0),
		Position = UDim2.fromOffset(324, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = root,
	})
	ui.Right = right

	ui.Name = Kit.Text({
		Name = "KaijuName",
		Size = UDim2.new(1, -10, 0, 50),
		Position = UDim2.fromOffset(4, 0),
		Text = "KAIJU",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 46,
		Stroke = 3.5,
		ZIndex = 6,
		Parent = right,
	})
	local chips = Kit.new("Frame", {
		Name = "Chips",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(4, 54),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = right,
	}, { Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	ui.RarityChip = Kit.Chip({ Name = "Rarity", AutoWidth = true, Size = UDim2.fromOffset(0, 28), TextSize = 18, LayoutOrder = 1, ZIndex = 7, Parent = chips })
	ui.MutChip = Kit.Chip({ Name = "Mutation", AutoWidth = true, Size = UDim2.fromOffset(0, 28), TextSize = 18, LayoutOrder = 2, ZIndex = 7, Parent = chips })
	ui.NestChip = Kit.Chip({ Name = "Nest", AutoWidth = true, Size = UDim2.fromOffset(0, 28), TextSize = 16, Color = C.InkSoft, LayoutOrder = 3, ZIndex = 7, Parent = chips })

	---------------------------------------------------------- stade + croissance
	local stageHolder, stageBody = Kit.Panel({
		Name = "StagePanel",
		Size = UDim2.new(1, -8, 0, 104),
		Position = UDim2.fromOffset(2, 94),
		Rotation = 0.8,
		ShadowOffset = 5,
		Parent = right,
	})
	ui.StagePanel = stageHolder
	inkText({
		Size = UDim2.fromOffset(120, 18),
		Position = UDim2.fromOffset(14, 8),
		Text = "GROWTH",
		FontFace = F.Title,
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = stageBody,
	})
	-- pastilles des 5 stades reliées par un trait
	local pips = Kit.new("Frame", {
		Name = "Pips",
		Size = UDim2.fromOffset(250, 34),
		Position = UDim2.new(1, -14, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = stageBody,
	})
	Kit.new("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -30, 0, 6),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = pips,
	})
	ui.PipLine = Kit.new("Frame", {
		Name = "LineFill",
		Size = UDim2.new(0, 0, 0, 6),
		Position = UDim2.new(0, 15, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.Radioactive,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = pips,
	})
	ui.Pips = {}
	for i = 1, Growth.MaxStage do
		local pip = Kit.new("Frame", {
			Name = "Pip" .. i,
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.new((i - 1) / (Growth.MaxStage - 1), (i - 1) / (Growth.MaxStage - 1) * -30 + 15, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Paper,
			ZIndex = 8,
			Parent = pips,
		}, { Kit.Round(), Kit.Stroke(3) })
		Kit.Text({
			Name = "Num",
			Size = UDim2.fromScale(0.7, 0.7),
			Position = UDim2.fromScale(0.5, 0.52),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = tostring(i),
			Stroke = 2,
			ZIndex = 9,
			Parent = pip,
		})
		ui.Pips[i] = pip
	end
	ui.StageName = Kit.Text({
		Name = "StageName",
		Size = UDim2.fromOffset(170, 30),
		Position = UDim2.fromOffset(14, 26),
		Text = "ADULT",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Radioactive,
		MaxTextSize = 30,
		ZIndex = 6,
		Parent = stageBody,
	})
	local bar, setBar = Kit.ProgressBar({
		Name = "GrowthBar",
		Size = UDim2.new(1, -28, 0, 20),
		Position = UDim2.fromOffset(14, 60),
		Color = "Radioactive",
		ZIndex = 6,
		Parent = stageBody,
	})
	ui.GrowthBar = bar
	ui.SetGrowth = setBar
	ui.GrowthText = inkText({
		Name = "GrowthText",
		Size = UDim2.new(1, -28, 0, 18),
		Position = UDim2.fromOffset(14, 82),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = stageBody,
	})

	---------------------------------------------------------------- stats
	local stats = Kit.new("Frame", {
		Name = "Stats",
		Size = UDim2.new(1, -8, 0, 60),
		Position = UDim2.fromOffset(2, 210),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = right,
	})
	ui.Stats = stats
	local function statBox(name: string, title: string, gradient: string, x: number, rot: number): TextLabel
		local holder, body = Kit.Panel({
			Name = name,
			Size = UDim2.new(0.5, -6, 1, 0),
			Position = UDim2.new(x, if x > 0 then 6 else 0, 0, 0),
			Rotation = rot,
			Gradient = gradient,
			ShadowOffset = 5,
			Parent = stats,
		})
		ui[name .. "Holder"] = holder
		Kit.Text({
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.fromOffset(10, 5),
			Text = title,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = F.Title,
			MaxTextSize = 16,
			Stroke = 2,
			ZIndex = 6,
			Parent = body,
		})
		return Kit.Text({
			Name = "Value",
			Size = UDim2.new(1, -16, 0, 30),
			Position = UDim2.fromOffset(10, 24),
			Text = "$0",
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 30,
			Stroke = 3,
			ZIndex = 6,
			Parent = body,
		})
	end
	ui.Income = statBox("IncomeBox", "💵 INCOME", "Radioactive", 0, -1)
	ui.Sell = statBox("SellBox", "🏷️ SELL VALUE", "Gold", 0.5, 1)

	----------------------------------------------------------------- nourriture
	local foods = Kit.new("Frame", {
		Name = "Foods",
		Size = UDim2.new(1, -8, 0, 78),
		Position = UDim2.fromOffset(2, 284),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = right,
	}, { Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top) })
	ui.Foods = foods
	ui.FoodButtons = {}
	for i, food in Economy.Foods do
		local slot = Kit.new("Frame", {
			Name = food.Id,
			Size = UDim2.fromOffset(154, 78),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			ZIndex = 5,
			Parent = foods,
		})
		local button = Kit.Button({
			Name = "Button",
			Icon = food.Icon,
			IconSize = 30,
			Text = "$0",
			TextSize = 24,
			Color = "Magma",
			Size = UDim2.fromOffset(150, 48),
			Sound = "ui_click",
			ZIndex = 6,
			Parent = slot,
			OnClick = function()
				KaijuPanel._Feed(food.Id)
			end,
		})
		local effect = if food.Cut >= 1 then "next stage NOW" else ("-%d%% wait"):format(math.floor(food.Cut * 100 + 0.5))
		inkText({
			Name = "Caption",
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 58),
			Text = ("<b>%s</b> · %s"):format(food.Name, effect),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
			Parent = slot,
		})
		ui.FoodButtons[food.Id] = button
	end

	------------------------------------------------------------------- œuf
	local eggHolder, eggBody = Kit.Panel({
		Name = "EggPanel",
		Size = UDim2.new(1, -8, 0, 176),
		Position = UDim2.fromOffset(2, 96),
		Rotation = 0.8,
		Gradient = "Ink",
		Parent = right,
	})
	ui.EggPanel = eggHolder
	Kit.Text({
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 12),
		Text = "HATCHES IN",
		TextColor3 = C.Paper,
		MaxTextSize = 24,
		ZIndex = 6,
		Parent = eggBody,
	})
	ui.EggTime = Kit.Text({
		Name = "Countdown",
		Size = UDim2.new(1, -20, 0, 64),
		Position = UDim2.fromOffset(10, 40),
		Text = "0:00",
		TextColor3 = C.Gold,
		FontFace = F.Impact,
		MaxTextSize = 64,
		Stroke = 4,
		ZIndex = 6,
		Parent = eggBody,
	})
	local eggBar, setEgg = Kit.ProgressBar({
		Name = "HatchBar",
		Size = UDim2.new(1, -40, 0, 20),
		Position = UDim2.fromOffset(20, 112),
		Color = "Gold",
		ZIndex = 6,
		Parent = eggBody,
	})
	ui.EggBar = eggBar
	ui.SetEgg = setEgg
	ui.EggHint = Kit.Text({
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 142),
		Text = "Something big is wiggling inside...",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		Stroke = false,
		MaxTextSize = 18,
		ZIndex = 6,
		Parent = eggBody,
	})

	------------------------------------------------------------------- actions
	local actions = Kit.new("Frame", {
		Name = "Actions",
		Size = UDim2.new(1, -8, 0, 62),
		Position = UDim2.fromOffset(2, 380),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = right,
	}, { Kit.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top) })
	ui.Actions = actions
	ui.SellButton = Kit.Button({
		Name = "Sell",
		Text = "SELL",
		Color = "Gold",
		Size = UDim2.fromOffset(172, 56),
		LayoutOrder = 1,
		Sound = "ui_click",
		ZIndex = 6,
		Parent = actions,
		OnClick = function()
			KaijuPanel._Sell()
		end,
	})
	local growProduct = Monetization.ProductByKey.InstantGrow
	ui.GrowButton = Kit.Button({
		Name = "Grow",
		Text = "INSTANT GROW",
		Color = "Radioactive",
		Size = UDim2.fromOffset(182, 56),
		LayoutOrder = 2,
		ZIndex = 6,
		Parent = actions,
		OnClick = function()
			if currentUid then
				Remote.Call("Buy", { Kind = "Product", Key = "InstantGrow", Target = currentUid })
			end
		end,
	})
	priceTag(ui.GrowButton, "R$" .. (if growProduct then growProduct.Robux else 25))
	ui.FuseButton = Kit.Button({
		Name = "Fuse",
		Text = "FUSE",
		Icon = "🧪",
		IconSize = 26,
		TextSize = 24,
		Color = "Purple",
		Size = UDim2.fromOffset(112, 56),
		LayoutOrder = 3,
		ZIndex = 6,
		Parent = actions,
		OnClick = function()
			local uid = currentUid
			if not uid then
				return
			end
			win:Close(true)
			local fusion = (UIRegistry.Screens :: any).Fusion
			if fusion then
				fusion.Open({ A = uid })
			end
		end,
	})
	local hatchProduct = Monetization.ProductByKey.InstantHatch
	ui.HatchButton = Kit.Button({
		Name = "Hatch",
		Text = "INSTANT HATCH",
		Icon = "🥚",
		IconSize = 30,
		TextSize = 26,
		Color = "Gold",
		Size = UDim2.fromOffset(300, 56),
		LayoutOrder = 4,
		ZIndex = 6,
		Parent = actions,
		OnClick = function()
			Remote.Call("Buy", { Kind = "Product", Key = "InstantHatch" })
		end,
	})
	priceTag(ui.HatchButton, "R$" .. (if hatchProduct then hatchProduct.Robux else 19))
end

----------------------------------------------------------------------------
-- Rendu
----------------------------------------------------------------------------

local function setChip(chip: any, text: string, color: Color3, secret: boolean?)
	chip.BackgroundColor3 = color
	local label = chip:FindFirstChild("Text")
	if label then
		label.Text = text
	end
	if secret then
		rainbow(chip, 2)
	else
		clearRainbow(chip)
	end
end

-- Bouton compagnon : « YOUR BUDDY » si c'est déjà lui.
local function refreshBuddyButton()
	local buddy = State.Get("Buddy")
	local isBuddy = buddy ~= nil and currentUid ~= nil and buddy.Uid == currentUid
	Kit.SetButtonText(ui.BuddyButton, if isBuddy then "YOUR BUDDY" else "SET AS BUDDY")
	Kit.SetButtonColor(ui.BuddyButton, if isBuddy then "Gold" else "Pink")
	ui.BuddyButton:SetAttribute("IsBuddy", isBuddy)
end

local function disarmSell()
	sellArmed = false
	sellToken += 1
	Kit.SetButtonColor(ui.SellButton, "Gold")
	shown.Sell = -1 -- force la remise à jour du texte
end

local function setPips(stage: number, animate: boolean)
	for i, pip in ui.Pips do
		local done = i <= stage
		pip.BackgroundColor3 = if i == stage then C.Gold elseif done then C.Radioactive else C.Paper
		local num = pip:FindFirstChild("Num")
		if num then
			num.TextColor3 = if done then C.White else C.InkSoft
		end
		if i == stage then
			if animate then
				Kit.Pop(pip, 2.2, 0.6)
			end
		else
			Kit.Tween(Kit.ScaleOf(pip), 0.2, { Scale = if done then 1 else 0.85 })
		end
	end
	local alpha = (stage - 1) / (Growth.MaxStage - 1)
	Kit.Tween(ui.PipLine, if animate then 0.5 else 0, { Size = UDim2.new(alpha, -30 * alpha, 0, 6) }, Enum.EasingStyle.Back)
end

-- Rendu « statique » : appelé à l'ouverture et quand le record change.
local function renderStatic(rec: any, fresh: boolean)
	local isEgg = rec.Egg == true or rec.Species == nil
	local rarity = Rarities.Get(rec.Rarity)
	local secret = rec.Rarity == "Secret"
	local species = if rec.Species then Kaijus.Get(rec.Species) else nil
	local mutation = Mutations.Get(rec.Mutation)

	-- aperçu 3D (reconstruit uniquement si nécessaire)
	local key = if isEgg then "Egg:" .. rec.Rarity else (rec.Species or "") .. ":" .. (rec.Mutation or "")
	if key ~= vpKey then
		vpKey = key
		if not vp then
			vp = Viewport.new({ Parent = ui.VpHolder, ZIndex = 5, Speed = 0.7 })
		end
		if isEgg then
			vp:SetEgg(rec.Rarity)
		elseif rec.Species then
			vp:Set(rec.Species, rec.Mutation)
		end
		Kit.Pop(vp.Frame, 0.3, 0.55)
		if not fresh and shown.Egg == true and not isEgg then
			-- l'œuf vient d'éclore sous nos yeux
			Audio.Play("egg_crack")
			safeShake(ui.CardHolder, 10, 0.4)
			Kit.Punch(ui.Name, 0.4)
		end
	end
	vp.Spin = true

	-- couleurs de la carte selon la rareté
	local base = if secret then C.InkSoft else rarity.Color
	ui.CardGradient.Color = ColorSequence.new(base:Lerp(C.White, 0.45), base:Lerp(C.Ink, 0.2))
	for _, ray in ui.Burst:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = if secret then C.Gold else rarity.Glow
		end
	end

	-- nom + pastilles
	if isEgg then
		ui.Name.Text = rarityText(rec.Rarity) .. " EGG"
	else
		ui.Name.Text = if species then species.Name else "???"
	end
	ui.Name.TextColor3 = if secret then C.White else rarity.Color:Lerp(C.White, 0.25)
	if secret then
		rainbow(ui.Name, 2.5)
	else
		clearRainbow(ui.Name)
	end
	setChip(ui.RarityChip, rarityText(rec.Rarity), if secret then C.Ink else rarity.Color, secret)
	if mutation and not isEgg then
		ui.MutChip.Visible = true
		setChip(ui.MutChip, ("%s  x%s"):format(string.upper(mutation.Name), tostring(mutation.Mult)), mutation.Color, mutation.Id == "Rainbow")
		local label = ui.MutChip:FindFirstChild("Text")
		if label then
			label.TextColor3 = C.White
		end
	else
		ui.MutChip.Visible = false
	end
	setChip(ui.NestChip, "NEST " .. tostring(rec.Nest or "?"), C.InkSoft)

	-- mode œuf / kaiju
	local mode = if isEgg then "Egg" else "Kaiju"
	ui.StagePanel.Visible = not isEgg
	ui.Stats.Visible = not isEgg
	ui.Foods.Visible = not isEgg
	ui.EggPanel.Visible = isEgg
	ui.Plate.Visible = not isEgg
	ui.SellButton.Visible = not isEgg
	ui.GrowButton.Visible = not isEgg
	ui.FuseButton.Visible = not isEgg
	ui.HatchButton.Visible = isEgg
	ui.BuddyButton.Visible = not isEgg
	refreshBuddyButton()
	if isEgg then
		setBreathing(ui.HatchButton, true)
	end
	shown.Egg = isEgg

	if fresh or mode ~= shown.Mode then
		shown.Mode = mode
		shown.Stage = 0
		shown.Income = -1
		shown.Sell = -1
		shown.Remain = ""
		shown.PricesDirty = true
		disarmSell()
		-- apparition en cascade
		local items = if isEgg
			then { ui.Name, ui.EggPanel, ui.HatchButton }
			else { ui.Name, ui.StagePanel, ui.IncomeBoxHolder, ui.SellBoxHolder, ui.SellButton, ui.GrowButton, ui.FuseButton, ui.BuddyButton }
		for i, item in items do
			popIn(item, 0.04 * i)
		end
		if not isEgg then
			for i, food in Economy.Foods do
				popIn(ui.FoodButtons[food.Id], 0.22 + 0.06 * i)
			end
		end
	end
end

-- Mise à jour des prix de nourriture (dépendent du stade).
local function refreshFoods(rec: any, growth: number, stage: number)
	local cash = State.Get("Cash") or 0
	local live = { Uid = rec.Uid, Species = rec.Species, Rarity = rec.Rarity, Mutation = rec.Mutation, Growth = growth, Nest = rec.Nest }
	for _, food in Economy.Foods do
		local b = ui.FoodButtons[food.Id]
		if stage >= Growth.MaxStage then
			Kit.SetButtonText(b, "MAX")
			Kit.SetDisabled(b, true)
		else
			local price = Calc.FoodPrice(live :: any, food.Id)
			Kit.SetButtonText(b, Format.Cash(price))
			Kit.SetDisabled(b, false)
			local label = b:FindFirstChild("Label", true)
			if label then
				label.TextColor3 = if cash >= price then C.White else Color3.fromRGB(255, 190, 190)
			end
		end
	end
end

-- Mise à jour à chaque image (valeurs vivantes).
local function step()
	local uid = currentUid
	local rec = lastRec
	if not uid or not rec then
		return
	end
	local anchor = anchorOf(uid)
	local now = Workspace:GetServerTimeNow()

	-- vol en cours
	local stolen = anchor ~= nil and (anchor:GetAttribute("CarriedBy") or 0) ~= 0
	if stolen ~= shown.Stolen then
		shown.Stolen = stolen
		ui.Stolen.Visible = stolen
		if stolen then
			Kit.Pop(ui.Stolen, 1.8, 0.4)
			task.delay(0.4, function()
				if shown.Stolen then
					Kit.Breathe(ui.Stolen, 0.08, 0.35)
				end
			end)
			Audio.Play("ui_error")
		end
	end

	if rec.Egg or not rec.Species then
		local hatchAt = (anchor and anchor:GetAttribute("HatchAt")) or rec.HatchAt or now
		local left = math.max(0, hatchAt - now)
		local total = Rarities.Get(rec.Rarity).HatchTime
		local text = if left <= 0 then "HATCHING!" else Format.Clock(math.ceil(left))
		if text ~= shown.Remain then
			shown.Remain = text
			ui.EggTime.Text = text
			if left <= 5 then
				Kit.Punch(ui.EggTime, 0.2)
			end
		end
		ui.SetEgg(1 - left / math.max(1, total), true)
		return
	end

	local growth, rate = liveGrowth(rec, anchor)
	local stage = Growth.StageFor(growth, rec.Rarity)
	if anchor then
		stage = math.max(stage, anchor:GetAttribute("Stage") or 1)
	end
	stage = math.clamp(stage, 1, Growth.MaxStage)

	if stage ~= shown.Stage then
		local grew = shown.Stage > 0 and stage > shown.Stage
		shown.Stage = stage
		local st = Growth.Get(stage)
		ui.StageName.Text = string.upper(st.Name)
		ui.PlateTitle.Text = string.upper(st.Name)
		ui.PlateSub.Text = ("STAGE %d / %d"):format(stage, Growth.MaxStage)
		setPips(stage, grew)
		shown.PricesDirty = true
		Kit.SetDisabled(ui.GrowButton, stage >= Growth.MaxStage)
		Kit.SetDisabled(ui.FuseButton, stage < 3)
		if grew then
			Audio.Play("stage_up")
			Kit.Punch(ui.StageName, 0.5)
			Kit.Punch(ui.Plate, 0.35)
			safeShake(ui.CardHolder, 8, 0.35)
			Kit.Pop(vp.Frame, 0.5, 0.6)
		end
	end

	if shown.PricesDirty then
		shown.PricesDirty = false
		refreshFoods(rec, growth, stage)
	end

	-- barre de croissance
	if stage >= Growth.MaxStage then
		ui.SetGrowth(1, true)
		if shown.Remain ~= "MAX" then
			shown.Remain = "MAX"
			ui.GrowthText.Text = "<b>MAX SIZE!</b> This kaiju is a full COLOSSUS."
		end
	else
		ui.SetGrowth(Growth.Progress(growth, rec.Rarity), true)
		local left = Growth.Remaining(growth, rec.Rarity) / math.max(rate, 0.01)
		local nextName = string.upper(Growth.Get(stage + 1).Name)
		local text = if shown.Stolen
			then ("Growth paused while stolen · next: <b>%s</b>"):format(nextName)
			else ("Next stage <b>%s</b> in <b>%s</b>"):format(nextName, Format.Duration(math.ceil(left)))
		if text ~= shown.Remain then
			shown.Remain = text
			ui.GrowthText.Text = text
		end
	end

	-- revenus / valeur de revente
	local income = if anchor then anchor:GetAttribute("Income") or 0 else Calc.BaseIncome(rec)
	if income ~= shown.Income then
		local first = shown.Income < 0
		shown.Income = income
		if first then
			ui.Income.Text = Format.Cash(income) .. "/s"
		else
			Kit.CountTo(ui.Income, income, function(v)
				return Format.Cash(v) .. "/s"
			end, 0.6)
			Kit.Punch(ui.Income, 0.25)
		end
	end
	local sell = if anchor then anchor:GetAttribute("SellValue") or 0 else Calc.SellValue(rec)
	if sell ~= shown.Sell then
		local first = shown.Sell < 0
		shown.Sell = sell
		ui.Sell.Text = Format.Cash(sell)
		if not first then
			Kit.Punch(ui.Sell, 0.25)
		end
		if not sellArmed then
			Kit.SetButtonText(ui.SellButton, "SELL " .. Format.Cash(sell))
		end
	end
end

local function startLoop()
	if renderConn then
		return
	end
	renderConn = RunService.RenderStepped:Connect(step)
end

local function stopLoop()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

function KaijuPanel._Feed(foodId: string)
	local uid = currentUid
	if not uid or busy then
		return
	end
	busy = true
	local res = Remote.Call("Feed", { Uid = uid, Food = foodId })
	busy = false
	if res.ok then
		local food = Economy.FoodsById[foodId]
		Audio.Play("purchase")
		Kit.Punch(ui.GrowthBar, 0.12)
		Kit.Punch(ui.FoodButtons[foodId], 0.2)
		Kit.Pop(vp.Frame, 0.8, 0.4)
		if food then
			UIRegistry.Toast(("%s %s devoured! Growing faster!"):format(food.Icon, food.Name), "Good")
		end
		shown.PricesDirty = true
	end
end

function KaijuPanel._Sell()
	local uid = currentUid
	if not uid or busy then
		return
	end
	if not sellArmed then
		sellArmed = true
		sellToken += 1
		local token = sellToken
		Kit.SetButtonColor(ui.SellButton, "Red")
		Kit.SetButtonText(ui.SellButton, "SURE? " .. Format.Cash(math.max(shown.Sell, 0)))
		Kit.Punch(ui.SellButton, 0.2)
		task.delay(3, function()
			if sellArmed and sellToken == token then
				disarmSell()
			end
		end)
		return
	end
	busy = true
	local res = Remote.Call("Sell", { Uid = uid })
	busy = false
	disarmSell()
	if res.ok then
		Audio.Play("sell")
		UIRegistry.Toast("Sold for " .. Format.Cash(res.amount or shown.Sell) .. "!", "Cash")
		KaijuPanel.Close()
	end
end

function KaijuPanel._SetBuddy()
	local uid = currentUid
	if not uid or busy then
		return
	end
	if ui.BuddyButton:GetAttribute("IsBuddy") then
		Kit.Shake(ui.BuddyButton, 4, 0.25)
		UIRegistry.Toast("Already your buddy! It follows you everywhere 🐾", "Info")
		return
	end
	busy = true
	local res = Remote.Call("SetBuddy", { Uid = uid })
	busy = false
	if res.ok then
		Audio.Play("reward_claim")
		Kit.Punch(ui.BuddyButton, 0.3)
		Kit.Pop(vp.Frame, 0.8, 0.4)
		refreshBuddyButton()
	end
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

function KaijuPanel.Init()
	build()
	UIRegistry.OpenKaiju = function(uid: string)
		KaijuPanel.Open({ Uid = uid })
	end

	win.Opened:Connect(startLoop)
	win.Closed:Connect(function()
		stopLoop()
		if vp then
			vp.Spin = false
		end
		disarmSell()
	end)

	-- Suit le record : fermeture s'il disparaît (vendu / volé / fusionné)
	State.Changed("Kaijus"):Connect(function()
		if not win.IsOpen or not currentUid then
			return
		end
		local rec = findRecord(currentUid)
		if not rec then
			KaijuPanel.Close()
			return
		end
		lastRec = rec
		renderStatic(rec, false)
	end)
	State.Changed("Buddy"):Connect(function()
		if win.IsOpen then
			refreshBuddyButton()
		end
	end)
	State.Changed("Cash"):Connect(function()
		if win.IsOpen and lastRec and not lastRec.Egg then
			shown.PricesDirty = true -- recolore les prix abordables
		end
	end)
end

function KaijuPanel.Open(args: any?)
	if args == KaijuPanel then
		args = nil
	end
	local uid = if type(args) == "table" then args.Uid else nil
	uid = uid or currentUid
	local rec = findRecord(uid)
	if not rec then
		return
	end
	currentUid = uid
	lastRec = rec
	shown.Stolen = false
	ui.Stolen.Visible = false
	renderStatic(rec, true)
	win:Open()
	startLoop()
	step()
	Kit.Pop(ui.CardHolder, 0.6, 0.5)
end

function KaijuPanel.Close()
	if win then
		win:Close()
	end
end

return KaijuPanel
