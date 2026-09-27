--!nonstrict
-- Roue « KAIJU WHEEL » façon rouleau CS:GO : une bande de cartes glisse sous
-- un repère et ralentit (Quint) jusqu'à la carte choisie par le serveur.
-- Les probabilités sont TOUJOURS affichées (règle Roblox sur le hasard payant).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared.Config.Rewards)
local Economy = require(Shared.Config.Economy)
local Monetization = require(Shared.Config.Monetization)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Logic.Format)
local Roll = require(Shared.Logic.Roll)

local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)
local Remote = require(script.Parent.Parent.Parent.Controllers.Remote)
local Audio = require(script.Parent.Parent.Parent.Controllers.Audio)
local UIRegistry = require(script.Parent.Parent.Parent.Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts

local Spin = {}

-- Géométrie du rouleau
local REEL_W, REEL_H = 848, 190
local CARD_W, CARD_H = 132, 150
local STEP = CARD_W + 12
local COUNT = 44
local WIN = 38
local IDLE = 4 -- carte centrée au repos
local DURATION = 4

local window
local reelBody: CanvasGroup
local reelBox: Frame
local strip: Frame
local needleTop: Frame
local needleBottom: Frame
local winBurst: Frame
local resultLabel: TextLabel
local cards: { any } = {}
local weights: { number } = {}
local totalWeight = 0

local buttons: any = {}
local spinning = false
local needsReset = false
local conn: RBXScriptConnection? = nil
local finishSpin: (() -> ())? = nil
local loopToken = 0

----------------------------------------------------------------------------
-- Aides
----------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function restricted(): boolean
	return State.Get("RandomRestricted") == true
end

local function slotIcon(slot: any): string
	local r = slot.Reward
	if r.Kind == "Cash" then
		return if (r.Amount or 0) >= 1000 then "💰" else "💵"
	elseif r.Kind == "Gems" then
		return "💎"
	elseif r.Kind == "Potion" then
		local p = Economy.PotionsById[r.Id or "Luck"]
		return if p then p.Icon else "🧪"
	elseif r.Kind == "Egg" then
		return "🥚"
	elseif r.Kind == "Spins" then
		return "🎡"
	end
	return "🎁"
end

-- Les tranches rares (faible poids) ont un liseré doré et une étoile.
local function isJackpot(slot: any): boolean
	return slot.Weight / totalWeight < 0.06
end

local function stripX(index: number, offset: number): number
	return REEL_W / 2 - ((index - 1) * STEP + CARD_W / 2) - offset
end

local function stripY(): number
	return (REEL_H - CARD_H) / 2
end

local function setBreathe(inst: GuiObject, on: boolean)
	if (inst:GetAttribute("Breathing") == true) == on then
		return
	end
	inst:SetAttribute("Breathing", on)
	if on then
		Kit.Breathe(inst, 0.05, 0.7)
	else
		Kit.Tween(Kit.ScaleOf(inst), 0.2, { Scale = 1 })
	end
end

local function styleButton(button: GuiObject, color: string, disabled: boolean)
	Kit.SetDisabled(button, false)
	Kit.SetButtonColor(button, color)
	if disabled then
		Kit.SetDisabled(button, true)
	end
end

local function slotButton(parent: Instance, props: { [string]: any }): (Frame, TextButton, Frame)
	local slot = Kit.new("Frame", {
		Name = (props.Name or "Button") .. "Slot",
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = parent,
	})
	local breather = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = slot,
	})
	local bp = table.clone(props)
	bp.Size = UDim2.new(1, 0, 1, -6)
	bp.Position = UDim2.new(0.5, 0, 0.5, -3)
	bp.AnchorPoint = Vector2.new(0.5, 0.5)
	bp.LayoutOrder = nil
	bp.ZIndex = 6
	bp.Parent = breather
	return slot, Kit.Button(bp), breather
end

----------------------------------------------------------------------------
-- Cartes du rouleau (créées une fois, recolorées à chaque tirage)
----------------------------------------------------------------------------

local function buildCard(k: number): any
	local frame = Kit.new("Frame", {
		Name = "Card" .. k,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Position = UDim2.fromOffset((k - 1) * STEP + CARD_W / 2, CARD_H / 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 3,
		Parent = strip,
	}, { Kit.Corner(12) })
	local gradient = Kit.Gradient({ C.White, C.White }, 90)
	gradient.Parent = frame
	local stroke = Kit.Stroke(3)
	stroke.Parent = frame
	-- reflet
	Kit.new("Frame", {
		Size = UDim2.new(1, -14, 0.3, 0),
		Position = UDim2.fromOffset(7, 6),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.72,
		ZIndex = 3,
		Parent = frame,
	}, { Kit.Corner(8) })
	local icon = Kit.Text({
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		FontFace = F.Body,
		Stroke = false,
		MaxTextSize = 58,
		ZIndex = 4,
		Parent = frame,
	})
	local label = Kit.Text({
		Size = UDim2.new(1, -12, 0, 34),
		Position = UDim2.new(0.5, 0, 1, -44),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		Stroke = 2.5,
		MaxTextSize = 22,
		ZIndex = 4,
		Parent = frame,
	})
	local bar = Kit.new("Frame", {
		Size = UDim2.new(1, -16, 0, 6),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.White,
		ZIndex = 4,
		Parent = frame,
	}, { Kit.Round() })
	local star = Kit.Text({
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(6, 4),
		Text = "★",
		FontFace = F.Body,
		TextColor3 = C.Gold,
		Stroke = 2,
		MaxTextSize = 26,
		ZIndex = 5,
		Visible = false,
		Parent = frame,
	})
	local dim = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.45,
		ZIndex = 6,
		Visible = false,
		Parent = frame,
	}, { Kit.Corner(12) })
	return { Frame = frame, Gradient = gradient, Stroke = stroke, Icon = icon, Label = label, Bar = bar, Star = star, Dim = dim, Slot = 1 }
end

local function setCard(card: any, slotIndex: number)
	local slot = Rewards.Wheel[slotIndex]
	card.Slot = slotIndex
	local color = slot.Color
	card.Gradient.Color = ColorSequence.new(color:Lerp(C.White, 0.3), color:Lerp(C.Ink, 0.3))
	card.Icon.Text = slotIcon(slot)
	card.Label.Text = string.upper(slot.Label)
	local jackpot = isJackpot(slot)
	card.Star.Visible = jackpot
	card.Stroke.Color = if jackpot then C.Gold else C.Ink
	card.Stroke.Thickness = if jackpot then 4 else 3
	local r = slot.Reward
	card.Bar.BackgroundColor3 = if r.Kind == "Egg" then Rarities.Get(r.Rarity or "Common").Color else C.White
end

local function randomSlot(): number
	return Roll.Weighted(weights)
end

-- Remet la carte gagnante au centre, en position « repos » (transition invisible).
local function resetStrip()
	if needsReset then
		needsReset = false
		for k = 1, 7 do
			local src = WIN - IDLE + k
			setCard(cards[k], cards[src].Slot)
		end
	end
	for k, card in cards do
		card.Dim.Visible = false
		card.Frame.ZIndex = 3
		if k > 7 then
			setCard(card, randomSlot())
		end
	end
	winBurst.Visible = false
	strip.Position = UDim2.fromOffset(stripX(IDLE, 0), stripY())
end

----------------------------------------------------------------------------
-- Boutons
----------------------------------------------------------------------------

function Spin.CanFreeSpin(): boolean
	return (State.Get("FreeSpinAt") or 0) <= now()
end

local function refreshButtons()
	if not window then
		return
	end
	local canFree = Spin.CanFreeSpin()
	local spins = State.Get("Spins") or 0
	local gems = State.Get("Gems") or 0
	local limited = restricted()

	if canFree then
		Kit.SetButtonText(buttons.Free, "FREE SPIN!")
	else
		Kit.SetButtonText(buttons.Free, "FREE IN " .. Format.Clock((State.Get("FreeSpinAt") or 0) - now()))
	end
	styleButton(buttons.Free, "Radioactive", spinning or not canFree)
	setBreathe(buttons.FreeBreather, canFree and not spinning)

	Kit.SetButtonText(buttons.Spins, string.format("SPIN (x%d)", spins))
	styleButton(buttons.Spins, "Magma", spinning or spins <= 0)
	setBreathe(buttons.SpinsBreather, spins > 0 and not canFree and not spinning)

	buttons.GemsSlot.Visible = not limited
	buttons.BuySlot.Visible = not limited
	styleButton(buttons.Gems, if gems >= Economy.SpinGemPrice then "Cyan" else "Grey", spinning)
	styleButton(buttons.Buy, "Gold", spinning)
end

----------------------------------------------------------------------------
-- Animation du tirage
----------------------------------------------------------------------------

local function land(silent: boolean?)
	local card = cards[WIN]
	local slot = Rewards.Wheel[card.Slot]
	needsReset = true
	-- met la gagnante en avant, assombrit les autres
	for k, c in cards do
		c.Dim.Visible = k ~= WIN
	end
	card.Frame.ZIndex = 5
	winBurst.Position = card.Frame.Position
	winBurst.Visible = true
	resultLabel.Text = "YOU WON: " .. string.upper(slot.Label) .. "!"
	resultLabel.TextColor3 = slot.Color
	if silent then
		strip.Position = UDim2.fromOffset(stripX(WIN, 0), stripY())
		return
	end
	-- recentrage élastique sur la carte gagnante
	Kit.Tween(strip, 0.45, { Position = UDim2.fromOffset(stripX(WIN, 0), stripY()) }, Enum.EasingStyle.Back)
	Kit.Pop(winBurst, 0.2, 0.6)
	Kit.Punch(card.Frame, 0.25)
	Kit.Shake(reelBox, 5, 0.3)
	Kit.Pop(resultLabel, 0.3, 0.5)
	Audio.Play("spin_win")
	if isJackpot(slot) then
		UIRegistry.Announce("JACKPOT! " .. string.upper(slot.Label), slot.Color)
	end
end

local function animateTo(offset: number)
	local from = strip.Position.X.Offset
	local to = stripX(WIN, offset)
	local y = stripY()
	local t0 = os.clock()
	local lastIndex = math.floor((REEL_W / 2 - from) / STEP)
	local done = false
	local function finish(silent: boolean?)
		if done then
			return
		end
		done = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		finishSpin = nil
		needleTop.Rotation = 45
		needleBottom.Rotation = 45
		strip.Position = UDim2.fromOffset(to, y)
		land(silent)
		-- la récompense est accordée par le serveur (~4,2 s après l'appel)
		task.delay(if silent then 0 else 0.6, function()
			spinning = false
			refreshButtons()
		end)
	end
	finishSpin = function()
		finish(true)
	end
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / DURATION, 0, 1)
		-- Quint sortant : démarrage fulgurant, fin très lente
		local eased = 1 - (1 - a) ^ 5
		local x = from + (to - from) * eased
		strip.Position = UDim2.fromOffset(x, y)
		local travelled = REEL_W / 2 - x
		local index = math.floor(travelled / STEP)
		if index ~= lastIndex then
			lastIndex = index
			Audio.Play("spin_tick", { Cooldown = 0.03, Pitch = 0.9 + 0.4 * (1 - eased), NoVary = true })
		end
		-- le repère « claque » au passage de chaque carte
		local frac = (travelled % STEP) / STEP
		local kick = math.max(0, 1 - frac * 3) * 16 * (1 - eased * 0.5)
		needleTop.Rotation = 45 - kick
		needleBottom.Rotation = 45 + kick
		if a >= 1 then
			finish(false)
		end
	end)
end

local function doSpin(useGems: boolean)
	if spinning then
		return
	end
	spinning = true
	refreshButtons()
	resetStrip()
	resultLabel.Text = "SPINNING..."
	resultLabel.TextColor3 = C.Ink
	local r = Remote.Call("Spin", { UseGems = useGems })
	if not r.ok or type(r.index) ~= "number" or not Rewards.Wheel[r.index] or not window.IsOpen then
		spinning = false
		resultLabel.Text = "Spin to win!"
		refreshButtons()
		return
	end
	setCard(cards[WIN], r.index)
	Audio.Play("whoosh")
	local margin = CARD_W / 2 - 14
	animateTo((math.random() * 2 - 1) * margin)
end

----------------------------------------------------------------------------
-- Tableau des probabilités
----------------------------------------------------------------------------

local function buildOdds(parent: Instance)
	local box, body = Kit.Panel({
		Name = "Odds",
		Size = UDim2.new(0, 410, 1, -10),
		Position = UDim2.new(1, -8, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		Rotation = 0.8,
		Parent = parent,
	})
	Kit.Text({
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, 6),
		Text = "🎲 ODDS PER SPIN",
		TextColor3 = C.Ink,
		Stroke = false,
		MaxTextSize = 24,
		ZIndex = 3,
		Parent = body,
	})
	local list = Kit.new("Frame", {
		Size = UDim2.new(1, -20, 1, -44),
		Position = UDim2.fromOffset(10, 38),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = body,
	}, { Kit.List(Enum.FillDirection.Vertical, 2) })
	local rowH = math.floor((238 - 44) / #Rewards.Wheel) - 2
	for i, slot in Rewards.Wheel do
		local chance = slot.Weight / totalWeight
		local row = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, rowH),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = if i % 2 == 0 then 0.92 else 0.85,
			LayoutOrder = i,
			ZIndex = 3,
			Parent = list,
		}, { Kit.Corner(6) })
		Kit.new("Frame", {
			Size = UDim2.fromOffset(rowH - 6, rowH - 6),
			Position = UDim2.new(0, 4, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = slot.Color,
			ZIndex = 4,
			Parent = row,
		}, { Kit.Corner(4), Kit.Stroke(2) })
		Kit.Text({
			Size = UDim2.new(0.55, -rowH, 1, -4),
			Position = UDim2.new(0, rowH + 4, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Text = slotIcon(slot) .. " " .. slot.Label,
			FontFace = F.Body,
			TextColor3 = C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			Stroke = false,
			MaxTextSize = 17,
			ZIndex = 4,
			Parent = row,
		})
		-- barre proportionnelle à la chance
		local track = Kit.new("Frame", {
			Size = UDim2.new(0.25, 0, 0, 8),
			Position = UDim2.new(0.58, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = C.PaperDark,
			ZIndex = 4,
			Parent = row,
		}, { Kit.Round() })
		Kit.new("Frame", {
			Size = UDim2.fromScale(math.max(0.03, chance / 0.3), 1),
			BackgroundColor3 = slot.Color,
			ZIndex = 5,
			Parent = track,
		}, { Kit.Round() })
		Kit.Text({
			Size = UDim2.new(0.16, 0, 1, -4),
			Position = UDim2.new(1, -4, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Text = Format.Percent(chance),
			FontFace = F.Title,
			TextColor3 = C.Ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			Stroke = false,
			MaxTextSize = 17,
			ZIndex = 4,
			Parent = row,
		})
	end
	return box
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

function Spin.Init()
	for i, slot in Rewards.Wheel do
		weights[i] = slot.Weight
		totalWeight += slot.Weight
	end

	window = Kit.Window({ Name = "Spin", Title = "KAIJU WHEEL", Icon = "🎡", Color = "Gold", Size = UDim2.fromOffset(900, 580), RibbonWidth = 380 })
	local content = window.Frame

	-- Rouleau
	local box, body = Kit.Panel({
		Name = "Reel",
		Size = UDim2.fromOffset(REEL_W, REEL_H),
		Position = UDim2.new(0.5, -3, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		Rotation = -0.6,
		Gradient = "Ink",
		Parent = content,
	})
	reelBox = box
	-- CanvasGroup : la fenêtre est inclinée, ClipsDescendants serait ignoré
	reelBody = Kit.new("CanvasGroup", {
		Name = "ReelClip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = body,
	}, { Kit.Corner() })
	strip = Kit.new("Frame", {
		Name = "Strip",
		Size = UDim2.fromOffset(COUNT * STEP, CARD_H),
		Position = UDim2.fromOffset(stripX(IDLE, 0), stripY()),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = reelBody,
	})
	winBurst = Kit.Starburst({ Size = UDim2.fromOffset(340, 340), Color = C.Gold, Transparency = 0.2, Rays = 16, Period = 6, ZIndex = 4, Parent = strip })
	winBurst.Visible = false
	for k = 1, COUNT do
		cards[k] = buildCard(k)
	end
	-- fondu sur les bords
	for _, side in { 0, 1 } do
		Kit.new("Frame", {
			Size = UDim2.new(0, 150, 1, 0),
			Position = UDim2.fromScale(side, 0),
			AnchorPoint = Vector2.new(side, 0),
			BackgroundColor3 = C.Ink,
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = reelBody,
		}, {
			Kit.new("UIGradient", {
				Transparency = NumberSequence.new(if side == 0 then 0 else 1, if side == 0 then 1 else 0),
			}),
		})
	end
	Kit.Hazard({ Size = UDim2.new(1, -24, 0, 8), Position = UDim2.fromOffset(12, 4), ZIndex = 9, Parent = body })
	Kit.Hazard({ Size = UDim2.new(1, -24, 0, 8), Position = UDim2.new(0, 12, 1, -12), ZIndex = 9, Parent = body })
	-- repère central : ligne (dans le rouleau) + deux losanges épinglés sur le cadre
	Kit.new("Frame", {
		Size = UDim2.new(0, 4, 1, 0),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.Gold,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = reelBody,
	})
	needleTop = Kit.new("Frame", {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0.5, 0, 0, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = C.Red,
		ZIndex = 10,
		Parent = body,
	}, { Kit.Corner(4), Kit.Stroke(3) })
	needleBottom = Kit.new("Frame", {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0.5, 0, 1, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = C.Red,
		ZIndex = 10,
		Parent = body,
	}, { Kit.Corner(4), Kit.Stroke(3) })

	resultLabel = Kit.Text({
		Size = UDim2.new(0.8, 0, 0, 40),
		Position = UDim2.new(0.5, 0, 0, REEL_H + 30),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "Spin to win!",
		TextColor3 = C.Ink,
		Stroke = false,
		MaxTextSize = 34,
		Parent = content,
	})

	-- Zone basse : boutons à gauche, probabilités à droite
	local bottom = Kit.new("Frame", {
		Name = "Bottom",
		Size = UDim2.new(1, 0, 0, 248),
		Position = UDim2.new(0, 0, 1, -248),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local left = Kit.new("Frame", {
		Size = UDim2.new(1, -440, 1, 0),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	local freeSlot, freeButton, freeBreather = slotButton(left, {
		Name = "Free",
		Text = "FREE SPIN!",
		Color = "Radioactive",
		Size = UDim2.new(1, -20, 0, 72),
		Position = UDim2.new(0.5, 0, 0, 44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 34,
		Sound = "ui_click",
		OnClick = function()
			doSpin(false)
		end,
	})
	local spinsSlot, spinsButton, spinsBreather = slotButton(left, {
		Name = "Spins",
		Text = "SPIN (x0)",
		Color = "Magma",
		Size = UDim2.new(1, -20, 0, 62),
		Position = UDim2.new(0.5, 0, 0, 118),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 30,
		OnClick = function()
			doSpin(false)
		end,
	})
	local gemsSlot, gemsButton = slotButton(left, {
		Name = "Gems",
		Text = "SPIN " .. Economy.SpinGemPrice .. " 💎",
		Color = "Cyan",
		Size = UDim2.new(0.5, -14, 0, 58),
		Position = UDim2.new(0.25, 2, 0, 190),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 24,
		OnClick = function()
			doSpin(true)
		end,
	})
	local product = Monetization.ProductByKey.Spins3
	local buySlot, buyButton = slotButton(left, {
		Name = "Buy3",
		Text = "3 SPINS · R$ " .. (if product then product.Robux else 79),
		Color = "Gold",
		Size = UDim2.new(0.5, -14, 0, 58),
		Position = UDim2.new(0.75, -2, 0, 190),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 22,
		OnClick = function()
			if buttons.Buying then
				return
			end
			buttons.Buying = true
			local r = Remote.Call("Buy", { Kind = "Product", Key = "Spins3" })
			buttons.Buying = false
			if r.ok and r.msg then
				Audio.Play("purchase")
				UIRegistry.Toast(r.msg, "Good")
			end
		end,
	})
	buttons = {
		Free = freeButton,
		FreeSlot = freeSlot,
		FreeBreather = freeBreather,
		Spins = spinsButton,
		SpinsSlot = spinsSlot,
		SpinsBreather = spinsBreather,
		Gems = gemsButton,
		GemsSlot = gemsSlot,
		Buy = buyButton,
		BuySlot = buySlot,
		Buying = false,
	}
	buildOdds(bottom)

	for _, card in cards do
		setCard(card, randomSlot())
	end

	for _, key in { "FreeSpinAt", "Spins", "Gems", "RandomRestricted" } do
		State.Changed(key):Connect(function()
			if window.IsOpen then
				refreshButtons()
			end
		end)
	end

	window.Opened:Connect(function()
		loopToken += 1
		local token = loopToken
		task.spawn(function()
			while window.IsOpen and token == loopToken do
				refreshButtons()
				task.wait(1)
			end
		end)
	end)
	window.Closed:Connect(function()
		loopToken += 1
		-- fermeture en plein tirage : on coupe la boucle et on pose le résultat
		if finishSpin then
			finishSpin()
		end
	end)
end

function Spin.Open(_args: any?)
	window:Open()
	if not spinning then
		resetStrip()
		resultLabel.Text = "Spin to win!"
		resultLabel.TextColor3 = C.Ink
	end
	refreshButtons()
	-- les cartes visibles surgissent en cascade
	for k = 1, 7 do
		local frame = cards[k].Frame
		local s = Kit.ScaleOf(frame)
		s.Scale = 0
		task.delay(0.05 + k * 0.05, function()
			Kit.Pop(frame, 0.2, 0.45)
		end)
	end
	Kit.Pop(buttons.FreeSlot, 0.4, 0.5)
	Kit.Pop(buttons.SpinsSlot, 0.4, 0.55)
end

function Spin.Close()
	window:Close()
end

return Spin
