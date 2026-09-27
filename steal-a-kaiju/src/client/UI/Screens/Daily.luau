--!nonstrict
-- Récompenses quotidiennes : calendrier de 7 jours, jour courant qui respire,
-- jours réclamés tamponnés, jours futurs grisés, grand œuf du jour 7.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared.Config.Rewards)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Config.Economy)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)
local Progress = require(Shared.Logic.Progress)
local Calc = require(Shared.Logic.Calc)

local Kit = require(script.Parent.Parent.Kit)
local Viewport = require(script.Parent.Parent.Viewport)
local State = require(script.Parent.Parent.Parent.Controllers.State)
local Remote = require(script.Parent.Parent.Parent.Controllers.Remote)
local Audio = require(script.Parent.Parent.Parent.Controllers.Audio)
local UIRegistry = require(script.Parent.Parent.Parent.Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts

local Daily = {}

local DAY = 86400

local window
local cards: { any } = {}
local claimSlot: Frame
local claimButton: TextButton
local claimBreather: Frame
local countdownBox: Frame
local countdownLabel: TextLabel
local streakChip: Frame
local statusLabel: TextLabel
local eggView: any = nil
local eggRarity: string? = nil
local eggLabel: TextLabel
local loopToken = 0
local busy = false
local lastDay = -1

----------------------------------------------------------------------------
-- Aides
----------------------------------------------------------------------------

local function now(): number
	return math.floor(Workspace:GetServerTimeNow())
end

local function dailyData(): any
	return State.Get("Daily") or { Streak = 0, LastDay = 0, Cycle = 0 }
end

-- (peutRéclamer, série, cycle, dernierJourRéclamé)
local function compute(): (boolean, number, number, number)
	local can, streak, cycle = Progress.DailyState(dailyData(), now())
	local claimedUpTo = if can then streak - 1 else streak
	return can, streak, cycle, claimedUpTo
end

local function rewardInfo(r: any): (string, string, Color3)
	if r.Kind == "Cash" then
		local amount = Calc.CashReward(r.Amount or 60, State.Get("Income") or 0, r.MinCash)
		return "💵", Format.Cash(amount), C.Cash
	elseif r.Kind == "Gems" then
		return "💎", tostring(r.Amount or 0) .. " GEMS", C.Gem
	elseif r.Kind == "Potion" then
		local p = Economy.PotionsById[r.Id or "Luck"]
		local name = if p then string.upper(p.Id) else "POTION"
		return if p then p.Icon else "🧪", string.format("%dx %s", r.Amount or 1, name), C.Radioactive
	elseif r.Kind == "Egg" then
		local rarity = Rarities.Get(r.Rarity or "Common")
		return "🥚", string.upper(rarity.Id) .. " EGG", rarity.Color
	elseif r.Kind == "Spins" then
		return "🎡", tostring(r.Amount or 1) .. " SPINS", C.Gold
	end
	return "🎁", "GIFT", C.White
end

local function setBreathe(inst: GuiObject, on: boolean)
	if (inst:GetAttribute("Breathing") == true) == on then
		return
	end
	inst:SetAttribute("Breathing", on)
	if on then
		Kit.Breathe(inst, 0.05, 0.75)
	else
		Kit.Tween(Kit.ScaleOf(inst), 0.2, { Scale = 1 })
	end
end

local function setGradient(frame: Frame, name: string)
	local g = frame:FindFirstChildOfClass("UIGradient")
	local colors = Theme.Gradients[name]
	if g and colors then
		g.Color = ColorSequence.new(colors[1], colors[2])
	end
end

----------------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------------

-- Carte d'un jour (petite pour 1..6, grande pour le 7).
local function dayCard(parent: Instance, day: number, big: boolean, props: { [string]: any })
	local holder = Kit.new("Frame", {
		Name = "Day" .. day,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = parent,
	})
	local box, body = Kit.Panel({
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.new(0.5, -3, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = if big then 1.5 else ((day % 2 == 0) and 1.5 or -1.5),
		Gradient = if big then "Purple" else "Paper",
		Parent = holder,
	})
	-- rayons : dans la carte (jour 7, découpés par un CanvasGroup car la
	-- fenêtre est inclinée) ou derrière elle (jour courant)
	local burstParent: Instance = holder
	if big then
		burstParent = Kit.new("CanvasGroup", {
			Name = "Clip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = body,
		}, { Kit.Corner() })
	end
	local burst = Kit.Starburst({
		Size = if big then UDim2.fromOffset(520, 520) else UDim2.fromOffset(215, 215),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = C.Gold,
		Transparency = if big then 0.3 else 0.35,
		ZIndex = if big then 2 else 0,
		Parent = burstParent,
	})
	burst.Visible = big
	if not big then
		box.ZIndex = 2
	end
	-- en-tête « DAY N »
	local header = Kit.new("Frame", {
		Size = UDim2.new(1, -14, 0, if big then 40 else 30),
		Position = UDim2.fromOffset(7, 7),
		BackgroundColor3 = C.White,
		ZIndex = 3,
		Parent = body,
	}, { Kit.Corner(9), Kit.Stroke(3), Kit.Gradient(if big then "Gold" else "Ink") })
	Kit.Text({
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = if big then "DAY 7 · MEGA EGG" else "DAY " .. day,
		Stroke = 2.5,
		MaxTextSize = if big then 30 else 22,
		ZIndex = 4,
		Parent = header,
	})
	local icon = Kit.Text({
		Name = "Icon",
		Size = if big then UDim2.fromOffset(0, 0) else UDim2.new(1, 0, 0, 62),
		Position = UDim2.new(0.5, 0, 0, if big then 0 else 42),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		FontFace = F.Body,
		Stroke = false,
		MaxTextSize = 54,
		ZIndex = 4,
		Visible = not big,
		Parent = body,
	})
	local amount = Kit.Text({
		Name = "Amount",
		Size = UDim2.new(1, -12, 0, if big then 40 else 32),
		Position = UDim2.new(0.5, 0, 1, if big then -52 else -40),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		FontFace = F.Impact,
		Stroke = 2.5,
		MaxTextSize = if big then 40 else 30,
		ZIndex = 4,
		Parent = body,
	})
	-- voile des jours futurs
	local dim = Kit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Paper,
		BackgroundTransparency = 0.35,
		ZIndex = 8,
		Visible = false,
		Parent = body,
	}, { Kit.Corner() })
	-- voile + tampon des jours réclamés
	local done = Kit.new("Frame", {
		Name = "Done",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.5,
		ZIndex = 8,
		Visible = false,
		Parent = body,
	}, { Kit.Corner() })
	local stamp = Kit.new("Frame", {
		Name = "Stamp",
		Size = UDim2.fromOffset(if big then 110 else 70, if big then 110 else 70),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -12,
		BackgroundColor3 = C.White,
		ZIndex = 9,
		Visible = false,
		Parent = body,
	}, { Kit.Round(), Kit.Stroke(4), Kit.Gradient("Radioactive") })
	Kit.Text({
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "✓",
		FontFace = F.Body,
		Stroke = 3,
		MaxTextSize = 80,
		ZIndex = 10,
		Parent = stamp,
	})
	-- pastille TODAY / TOMORROW
	local tag = Kit.Chip({
		Name = "Tag",
		Text = "TODAY!",
		Color = C.Red,
		Size = UDim2.fromOffset(if big then 150 else 110, 28),
		Position = UDim2.new(0.5, 0, 0, -8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 12,
		Parent = holder,
	})
	tag.Rotation = -6
	tag.Visible = false
	return {
		Day = day,
		Big = big,
		Holder = holder,
		Box = box,
		Body = body,
		Burst = burst,
		Icon = icon,
		Amount = amount,
		Dim = dim,
		Done = done,
		Stamp = stamp,
		Tag = tag,
		Status = "",
	}
end

----------------------------------------------------------------------------
-- Rafraîchissement
----------------------------------------------------------------------------

local function refresh()
	if not window then
		return
	end
	local can, streak, cycle, claimedUpTo = compute()
	local tomorrow = if not can and streak < #Rewards.Daily then streak + 1 else nil
	for _, c in cards do
		local reward = Progress.DailyReward(c.Day, cycle)
		local icon, label, color = rewardInfo(reward)
		c.Icon.Text = icon
		c.Amount.Text = label
		c.Amount.TextColor3 = color
		local status
		if c.Day <= claimedUpTo then
			status = "claimed"
		elseif can and c.Day == streak then
			status = "today"
		elseif c.Day == tomorrow then
			status = "tomorrow"
		else
			status = "future"
		end
		c.Done.Visible = status == "claimed"
		c.Stamp.Visible = status == "claimed"
		c.Dim.Visible = status == "future"
		c.Tag.Visible = status == "today" or status == "tomorrow"
		local tagLabel = c.Tag:FindFirstChild("Text") :: TextLabel?
		if tagLabel then
			tagLabel.Text = if status == "today" then "TODAY!" else "TOMORROW"
		end
		c.Tag.BackgroundColor3 = if status == "today" then C.Red else C.InkSoft
		if not c.Big then
			c.Burst.Visible = status == "today"
			setGradient(c.Body, if status == "today" then "Gold" else "Paper")
		end
		if status ~= c.Status then
			c.Status = status
			c.Holder.ZIndex = if status == "today" then 6 else 5
			setBreathe(c.Holder, status == "today")
		end
		if c.Big then
			local rarity = reward.Rarity or "Epic"
			eggLabel.Text = string.upper(rarity) .. " EGG"
			eggLabel.TextColor3 = Rarities.Get(rarity).Color
			if eggView and eggRarity ~= rarity then
				eggRarity = rarity
				eggView:SetEgg(rarity)
			end
		end
	end
	-- série
	local streakLabel = streakChip:FindFirstChild("Text") :: TextLabel?
	if streakLabel then
		local shown = if can then streak - 1 else streak
		streakLabel.Text = string.format("🔥 STREAK: %d DAY%s", shown, if shown == 1 then "" else "S")
	end
	claimSlot.Visible = can
	countdownBox.Visible = not can
	if can then
		Kit.SetButtonText(claimButton, "CLAIM DAY " .. streak .. "!")
		statusLabel.Text = "Your reward is ready!"
		statusLabel.TextColor3 = C.RadioactiveDark
	else
		statusLabel.Text = if streak >= #Rewards.Daily then "Week complete! A new cycle starts tomorrow." else "Come back tomorrow to keep your streak!"
		statusLabel.TextColor3 = C.InkSoft
	end
	setBreathe(claimBreather, can)
end

local function tick()
	local t = now()
	local left = DAY - (t % DAY)
	countdownLabel.Text = Format.Clock(left)
	local today = t // DAY
	if today ~= lastDay then
		lastDay = today
		refresh()
	end
end

----------------------------------------------------------------------------
-- Réclamation
----------------------------------------------------------------------------

-- Texte qui s'envole depuis une carte.
local function flyText(parentCard: any, str: string, color: Color3)
	local label = Kit.Text({
		Size = UDim2.fromOffset(260, 44),
		Position = parentCard.Holder.Position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "+" .. str,
		FontFace = F.Impact,
		TextColor3 = color,
		Stroke = 3,
		MaxTextSize = 44,
		ZIndex = 20,
		Parent = parentCard.Holder.Parent,
	})
	Kit.Pop(label, 0.3, 0.4)
	Kit.Tween(label, 1.2, { Position = parentCard.Holder.Position - UDim2.fromOffset(0, 110), Rotation = math.random(-8, 8) }, Enum.EasingStyle.Quint)
	task.delay(0.8, function()
		Kit.Tween(label, 0.4, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Kit.Tween(stroke, 0.4, { Transparency = 1 })
		end
	end)
	task.delay(1.3, function()
		label:Destroy()
	end)
end

local function claim()
	if busy then
		return
	end
	local can, streak = compute()
	if not can then
		return
	end
	busy = true
	Kit.SetDisabled(claimButton, true)
	local r = Remote.Call("ClaimDaily")
	busy = false
	Kit.SetDisabled(claimButton, false)
	if not r.ok then
		refresh()
		return
	end
	local day = r.streak or streak
	local c = cards[day]
	Audio.Play("reward_claim")
	UIRegistry.Toast("Day " .. day .. ": " .. tostring(r.text or "Reward claimed!"), "Good")
	if c then
		-- éclair blanc
		local flash = Kit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0,
			ZIndex = 11,
			Parent = c.Body,
		}, { Kit.Corner() })
		Kit.Tween(flash, 0.5, { BackgroundTransparency = 1 })
		task.delay(0.55, function()
			flash:Destroy()
		end)
		Kit.Shake(c.Box, 6, 0.3)
		local _, _, color = rewardInfo(Progress.DailyReward(day, (dailyData()).Cycle))
		flyText(c, tostring(r.text or ""), color)
	end
	refresh()
	if c then
		-- tampon qui claque
		local s = Kit.ScaleOf(c.Stamp)
		s.Scale = 3
		c.Stamp.Rotation = -40
		Kit.Tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		Kit.Tween(c.Stamp, 0.35, { Rotation = -12 }, Enum.EasingStyle.Back)
		task.delay(0.3, function()
			Audio.Play("ui_click", { Pitch = 0.7 })
		end)
	end
	Kit.Punch(streakChip, 0.25)
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

function Daily.CanClaim(): boolean
	if State.Get("Daily") == nil then
		return false
	end
	local can = compute()
	return can
end

function Daily.Init()
	window = Kit.Window({ Name = "Daily", Title = "DAILY REWARDS", Icon = "📅", Color = "Gold", Size = UDim2.fromOffset(860, 540), RibbonWidth = 420 })
	local content = window.Frame

	-- en-tête
	streakChip = Kit.Chip({
		Text = "🔥 STREAK: 0 DAYS",
		Color = C.Magma,
		Size = UDim2.fromOffset(200, 34),
		Position = UDim2.fromOffset(0, -30),
		TextSize = 20,
		Parent = content,
	})
	streakChip.Rotation = -2
	statusLabel = Kit.Text({
		Size = UDim2.new(1, -270, 0, 30),
		Position = UDim2.new(1, -4, 0, 9),
		AnchorPoint = Vector2.new(1, 0),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Right,
		Stroke = false,
		MaxTextSize = 22,
		Parent = content,
	})

	-- calendrier : jours 1..6 en grille 3x2, jour 7 en grand à droite
	local area = Kit.new("Frame", {
		Name = "Calendar",
		Size = UDim2.new(1, 0, 0, 320),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local cw, ch, gap = 160, 156, 10
	for day = 1, #Rewards.Daily - 1 do
		local col = (day - 1) % 3
		local row = (day - 1) // 3
		cards[day] = dayCard(area, day, false, {
			Size = UDim2.fromOffset(cw, ch),
			Position = UDim2.fromOffset(col * (cw + gap) + cw / 2, row * (ch + gap - 2) + ch / 2),
		})
	end
	local left = 3 * (cw + gap) + 8
	local big = dayCard(area, #Rewards.Daily, true, {
		Size = UDim2.new(1, -left, 0, 318),
		Position = UDim2.new(0.5, left / 2, 0, 159),
	})
	cards[#Rewards.Daily] = big
	eggView = Viewport.new({
		Egg = "Epic",
		Size = UDim2.fromOffset(190, 190),
		Position = UDim2.new(0.5, 0, 0.47, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 5,
		Speed = 1,
		Parent = big.Body,
	})
	eggRarity = "Epic"
	Kit.Wobble(eggView.Frame, 5, 1)
	eggLabel = big.Amount
	eggLabel.TextColor3 = C.Gold

	-- bas : bouton de réclamation ou compte à rebours
	local slot = Kit.new("Frame", {
		Name = "ClaimSlot",
		Size = UDim2.fromOffset(340, 70),
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = content,
	})
	claimSlot = slot
	claimBreather = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = slot,
	})
	claimButton = Kit.Button({
		Name = "Claim",
		Text = "CLAIM!",
		Color = "Radioactive",
		Size = UDim2.new(1, 0, 1, -6),
		Position = UDim2.new(0.5, 0, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 36,
		ZIndex = 6,
		Sound = "ui_click",
		OnClick = claim,
		Parent = claimBreather,
	})
	local cdBox, cdBody = Kit.Panel({
		Name = "Countdown",
		Size = UDim2.fromOffset(380, 64),
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 1,
		Gradient = "Ink",
		Parent = content,
	})
	countdownBox = cdBox
	Kit.Text({
		Size = UDim2.new(0.55, 0, 0.6, 0),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Text = "NEXT REWARD IN",
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 2,
		MaxTextSize = 24,
		Parent = cdBody,
	})
	countdownLabel = Kit.Text({
		Size = UDim2.new(0.4, 0, 0.8, 0),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "0:00:00",
		FontFace = F.Impact,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Stroke = 2.5,
		MaxTextSize = 40,
		Parent = cdBody,
	})

	for _, key in { "Daily", "Income" } do
		State.Changed(key):Connect(function()
			if window.IsOpen then
				refresh()
			end
		end)
	end

	window.Opened:Connect(function()
		loopToken += 1
		local token = loopToken
		lastDay = -1
		task.spawn(function()
			while window.IsOpen and token == loopToken do
				tick()
				task.wait(1)
			end
		end)
	end)
	window.Closed:Connect(function()
		loopToken += 1
	end)
end

function Daily.Open(_args: any?)
	window:Open()
	refresh()
	-- cascade d'apparition des jours
	for i, c in cards do
		c.Status = ""
		c.Holder:SetAttribute("Breathing", false)
		local s = Kit.ScaleOf(c.Holder)
		s.Scale = 0
		task.delay(0.05 + i * 0.06, function()
			if not window.IsOpen then
				s.Scale = 1
				return
			end
			Kit.Pop(c.Holder, 0.2, 0.5)
			if i == #cards then
				task.delay(0.5, refresh)
			end
		end)
	end
	Kit.Pop(claimSlot, 0.3, 0.6)
end

function Daily.Close()
	window:Close()
end

return Daily
