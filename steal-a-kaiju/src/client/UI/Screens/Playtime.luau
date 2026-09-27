--!nonstrict
-- Cadeaux de temps de jeu : 10 boîtes dessinées en code, compte à rebours en
-- direct, boîtes prêtes qui gigotent, couvercle qui saute à l'ouverture.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared.Config.Rewards)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Config.Economy)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)
local Calc = require(Shared.Logic.Calc)

local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)
local Remote = require(script.Parent.Parent.Parent.Controllers.Remote)
local Audio = require(script.Parent.Parent.Parent.Controllers.Audio)
local UIRegistry = require(script.Parent.Parent.Parent.Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts

local Playtime = {}

local BOX_COLORS = { "Pink", "Cyan", "Gold", "Purple", "Radioactive", "Magma" }

local window
local gifts: { any } = {}
local sessionChip: Frame
local nextLabel: TextLabel
local loopToken = 0
local busy: { [number]: any } = {}

----------------------------------------------------------------------------
-- Logique
----------------------------------------------------------------------------

local function elapsed(): number?
	local start = State.Get("SessionStart")
	if type(start) ~= "number" then
		return nil
	end
	return Workspace:GetServerTimeNow() - start
end

-- Les tables à clés numériques creuses peuvent arriver avec des clés texte.
local function isClaimed(i: number): boolean
	local claimed = State.Get("PlaytimeClaimed")
	if type(claimed) ~= "table" then
		return false
	end
	return claimed[i] == true or claimed[tostring(i)] == true
end

local function remaining(i: number): number
	local e = elapsed()
	if not e then
		return math.huge
	end
	return Rewards.Playtime[i].Minutes * 60 - e
end

local function isReady(i: number): boolean
	return not isClaimed(i) and remaining(i) <= 0
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

----------------------------------------------------------------------------
-- Construction d'une boîte cadeau
----------------------------------------------------------------------------

local function giftBox(parent: Instance, colorName: string): (Frame, Frame)
	local colors = Theme.Gradients[colorName]
	local area = Kit.new("Frame", {
		Name = "Gift",
		Size = UDim2.fromOffset(104, 92),
		Position = UDim2.new(0.5, 0, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = parent,
	})
	local box = Kit.new("Frame", {
		Name = "Box",
		Size = UDim2.new(0.74, 0, 0, 50),
		Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.White,
		ZIndex = 4,
		Parent = area,
	}, { Kit.Corner(6), Kit.Stroke(3), Kit.Gradient(colors) })
	Kit.new("Frame", {
		Size = UDim2.new(0, 14, 1, 0),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.Gold,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = box,
	})
	-- couvercle + nœud (tout ensemble pour s'envoler)
	local lid = Kit.new("Frame", {
		Name = "Lid",
		Size = UDim2.new(0.88, 0, 0, 20),
		Position = UDim2.new(0.5, 0, 1, -52),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.White,
		ZIndex = 6,
		Parent = area,
	}, { Kit.Corner(6), Kit.Stroke(3), Kit.Gradient({ colors[1], colors[2]:Lerp(C.Ink, 0.15) }) })
	Kit.new("Frame", {
		Size = UDim2.new(0, 14, 1, 0),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.Gold,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = lid,
	})
	for _, side in { -1, 1 } do
		Kit.new("Frame", {
			Size = UDim2.fromOffset(24, 16),
			Position = UDim2.new(0.5, side * 12, 0, -8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = side * 25,
			BackgroundColor3 = C.Gold,
			ZIndex = 7,
			Parent = lid,
		}, { Kit.Corner(8), Kit.Stroke(2.5) })
	end
	Kit.new("Frame", {
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.new(0.5, 0, 0, -6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Gold,
		ZIndex = 8,
		Parent = lid,
	}, { Kit.Round(), Kit.Stroke(2.5) })
	return area, lid
end

local function buildGift(parent: Instance, i: number, pos: UDim2, size: UDim2)
	local entry = Rewards.Playtime[i]
	local big = entry.Reward.Kind == "Egg"
	local holder = Kit.new("Frame", {
		Name = "Gift" .. i,
		Size = size,
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = parent,
	})
	local burst = Kit.Starburst({ Size = UDim2.fromOffset(210, 210), Position = UDim2.new(0.5, 0, 0, 62), Color = C.Gold, Transparency = 0.35, ZIndex = 0, Parent = holder })
	burst.Visible = false
	local box, body = Kit.Panel({
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.new(0.5, -3, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = if i % 2 == 0 then 1.4 else -1.4,
		Gradient = if big then "Gold" else "Paper",
		Parent = holder,
	})
	box.ZIndex = 2
	local minutes = Kit.Chip({
		Text = entry.Minutes .. " MIN",
		Color = C.Ink,
		Size = UDim2.fromOffset(74, 24),
		Position = UDim2.fromOffset(4, 4),
		TextSize = 16,
		ZIndex = 9,
		Parent = body,
	})
	minutes.Rotation = -6
	local area, lid = giftBox(body, BOX_COLORS[(i - 1) % #BOX_COLORS + 1])
	local lidHome = lid.Position
	local icon, label, color = rewardInfo(entry.Reward)
	-- icône de la récompense, visible une fois la boîte ouverte
	local reveal = Kit.Text({
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(0.5, 0, 1, -58),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = icon,
		FontFace = F.Body,
		Stroke = false,
		MaxTextSize = 44,
		ZIndex = 5,
		Visible = false,
		Parent = area,
	})
	local rewardLabel = Kit.Text({
		Name = "Reward",
		Size = UDim2.new(1, -10, 0, 28),
		Position = UDim2.fromOffset(5, 106),
		Text = icon .. " " .. label,
		FontFace = F.Impact,
		TextColor3 = color,
		Stroke = 2.5,
		MaxTextSize = 24,
		ZIndex = 4,
		Parent = body,
	})
	-- zone d'état : compte à rebours / bouton / réclamé
	local timerBox = Kit.new("Frame", {
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.new(0.5, 0, 1, -44),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = body,
	})
	local timerText = Kit.Text({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "0:00",
		FontFace = F.Title,
		TextColor3 = C.Ink,
		Stroke = false,
		MaxTextSize = 22,
		ZIndex = 4,
		Parent = timerBox,
	})
	local _, setBar = Kit.ProgressBar({
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.fromOffset(0, 24),
		Color = BOX_COLORS[(i - 1) % #BOX_COLORS + 1],
		ZIndex = 4,
		Parent = timerBox,
	})
	local claimSlot = Kit.new("Frame", {
		Size = UDim2.new(1, -16, 0, 46),
		Position = UDim2.new(0.5, 0, 1, -30),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Visible = false,
		Parent = body,
	})
	local claimBreather = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = claimSlot,
	})
	local g
	local claimButton = Kit.Button({
		Name = "Claim",
		Text = "CLAIM!",
		Color = "Radioactive",
		Size = UDim2.new(1, 0, 1, -6),
		Position = UDim2.new(0.5, 0, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 24,
		ZIndex = 6,
		OnClick = function()
			if g then
				g.Claim()
			end
		end,
		Parent = claimBreather,
	})
	local done = Kit.Chip({
		Text = "CLAIMED ✓",
		Color = C.RadioactiveDark,
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.new(0.5, 0, 1, -28),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 9,
		Parent = body,
	})
	done.Visible = false
	local dim = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.6,
		ZIndex = 8,
		Visible = false,
		Parent = body,
	}, { Kit.Corner() })

	g = {
		Index = i,
		Holder = holder,
		Box = box,
		Body = body,
		Burst = burst,
		Area = area,
		Lid = lid,
		LidHome = lidHome,
		Reveal = reveal,
		RewardLabel = rewardLabel,
		TimerBox = timerBox,
		TimerText = timerText,
		SetBar = setBar,
		ClaimSlot = claimSlot,
		ClaimBreather = claimBreather,
		ClaimButton = claimButton,
		Done = done,
		Dim = dim,
		Status = "",
		Popping = false,
		Claiming = false,
		Claim = nil :: any,
	}
	return g
end

----------------------------------------------------------------------------
-- États & animations
----------------------------------------------------------------------------

local function applyStatus(g: any, status: string)
	if g.Status == status then
		return
	end
	local previous = g.Status
	g.Status = status
	g.TimerBox.Visible = status == "waiting"
	g.ClaimSlot.Visible = status == "ready"
	g.Done.Visible = status == "claimed"
	g.Dim.Visible = status == "claimed"
	g.Burst.Visible = status == "ready"
	g.Lid.Visible = status ~= "claimed"
	g.Reveal.Visible = status == "claimed"
	if status ~= "claimed" then
		g.Lid.Position = g.LidHome
		g.Lid.Rotation = 0
	end
	g.Holder.ZIndex = if status == "ready" then 6 else 5
	if status == "ready" then
		Kit.Wobble(g.Area, 9, 0.28)
		Kit.Breathe(g.ClaimBreather, 0.07, 0.6)
		if not g.Popping then
			Kit.Breathe(g.Holder, 0.03, 0.8)
		end
		if previous == "waiting" then
			Audio.Play("quest_complete", { Volume = 0.6 })
			Kit.Pop(g.ClaimSlot, 0.3, 0.5)
		end
	elseif previous == "ready" then
		Kit.Tween(g.Area, 0.2, { Rotation = 0 })
		Kit.Tween(Kit.ScaleOf(g.ClaimBreather), 0.2, { Scale = 1 })
		if not g.Popping then
			Kit.Tween(Kit.ScaleOf(g.Holder), 0.2, { Scale = 1 })
		end
	end
end

local function tick()
	local e = elapsed()
	for i, g in gifts do
		local status
		if g.Claiming then
			status = g.Status
		elseif isClaimed(i) then
			status = "claimed"
		elseif isReady(i) then
			status = "ready"
		else
			status = "waiting"
		end
		applyStatus(g, status)
		if status == "waiting" then
			local total = Rewards.Playtime[i].Minutes * 60
			g.TimerText.Text = Format.Clock(remaining(i))
			g.SetBar(if e then e / total else 0, true)
		end
	end
	if e then
		local chipLabel = sessionChip:FindFirstChild("Text") :: TextLabel?
		if chipLabel then
			chipLabel.Text = "⏱ PLAYED " .. Format.Clock(e)
		end
	end
	local nextIn = Playtime.NextReadyIn()
	if nextIn == 0 then
		local n = Playtime.ClaimableCount()
		nextLabel.Text = if n > 1 then n .. " gifts are ready!" else "A gift is ready!"
		nextLabel.TextColor3 = C.RadioactiveDark
	elseif nextIn < 0 then
		nextLabel.Text = "All gifts claimed. See you next session!"
		nextLabel.TextColor3 = C.InkSoft
	else
		nextLabel.Text = "Next gift in " .. Format.Clock(nextIn)
		nextLabel.TextColor3 = C.InkSoft
	end
end

-- Confettis encrés (créés une fois par ouverture, pas à chaque image).
local function confetti(parent: Instance, origin: UDim2)
	local palette = { C.Pink, C.Cyan, C.Gold, C.Radioactive, C.Magma, C.Purple }
	for n = 1, 12 do
		local piece = Kit.new("Frame", {
			Size = UDim2.fromOffset(math.random(8, 13), math.random(8, 13)),
			Position = origin,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = math.random(0, 90),
			BackgroundColor3 = palette[(n - 1) % #palette + 1],
			ZIndex = 20,
			Parent = parent,
		}, { Kit.Corner(3), Kit.Stroke(2) })
		local angle = math.rad(n / 12 * 360 + math.random(-12, 12))
		local dist = math.random(60, 110)
		Kit.Tween(piece, 0.7, {
			Position = origin + UDim2.fromOffset(math.cos(angle) * dist, math.sin(angle) * dist - 30),
			Rotation = piece.Rotation + math.random(-360, 360),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quint)
		local stroke = piece:FindFirstChildOfClass("UIStroke")
		if stroke then
			Kit.Tween(stroke, 0.7, { Transparency = 1 }, Enum.EasingStyle.Quint)
		end
		task.delay(0.75, function()
			piece:Destroy()
		end)
	end
end

local function claim(g: any)
	local i = g.Index
	if busy[i] or not isReady(i) then
		return
	end
	busy[i] = true
	g.Claiming = true
	Kit.SetDisabled(g.ClaimButton, true)
	local r = Remote.Call("ClaimPlaytime", { Index = i })
	busy[i] = nil
	Kit.SetDisabled(g.ClaimButton, false)
	if not r.ok then
		g.Claiming = false
		return
	end
	Audio.Play("reward_claim")
	UIRegistry.Toast("Gift: " .. tostring(r.text or "claimed!"), "Good")
	-- le couvercle s'envole, confettis, révélation
	local lid = g.Lid
	Kit.Tween(lid, 0.45, { Position = g.LidHome + UDim2.fromOffset(math.random(-30, 30), -70), Rotation = math.random(-60, 60) }, Enum.EasingStyle.Quad)
	confetti(g.Holder, UDim2.new(0.5, 0, 0, 58))
	Kit.Shake(g.Box, 5, 0.3)
	Kit.Punch(g.RewardLabel, 0.4)
	g.Reveal.Visible = true
	Kit.Pop(g.Reveal, 0.2, 0.5)
	task.delay(0.45, function()
		g.Claiming = false
		applyStatus(g, "claimed")
	end)
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

-- Secondes avant le prochain cadeau (0 = un cadeau est prêt, -1 = tout pris).
function Playtime.NextReadyIn(): number
	if elapsed() == nil then
		return -1
	end
	local best = math.huge
	for i = 1, #Rewards.Playtime do
		if not isClaimed(i) then
			local left = remaining(i)
			if left <= 0 then
				return 0
			end
			best = math.min(best, left)
		end
	end
	return if best == math.huge then -1 else math.ceil(best)
end

function Playtime.ClaimableCount(): number
	local n = 0
	for i = 1, #Rewards.Playtime do
		if isReady(i) then
			n += 1
		end
	end
	return n
end

function Playtime.Init()
	window = Kit.Window({ Name = "Playtime", Title = "FREE GIFTS", Icon = "🎁", Color = "Pink", Size = UDim2.fromOffset(860, 540), RibbonWidth = 360 })
	local content = window.Frame

	sessionChip = Kit.Chip({
		Text = "⏱ PLAYED 0:00",
		Color = C.Pink,
		Size = UDim2.fromOffset(220, 36),
		Position = UDim2.fromOffset(4, 6),
		TextSize = 22,
		Parent = content,
	})
	sessionChip.Rotation = -2
	nextLabel = Kit.Text({
		Size = UDim2.new(1, -250, 0, 30),
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

	local area = Kit.new("Frame", {
		Name = "Gifts",
		Size = UDim2.new(1, 0, 1, -56),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local cw, ch, gap = 152, 190, 11
	local cols = 5
	local width = cols * cw + (cols - 1) * gap
	for i = 1, #Rewards.Playtime do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		local g = buildGift(area, i, UDim2.new(0.5, -width / 2 + col * (cw + gap) + cw / 2, 0, row * (ch + gap) + ch / 2 + 4), UDim2.fromOffset(cw, ch))
		g.Claim = function()
			task.spawn(claim, g)
		end
		gifts[i] = g
	end

	State.Changed("PlaytimeClaimed"):Connect(function()
		if window.IsOpen then
			tick()
		end
	end)
	State.Changed("Income"):Connect(function()
		if not window.IsOpen then
			return
		end
		for i, g in gifts do
			local icon, label = rewardInfo(Rewards.Playtime[i].Reward)
			g.RewardLabel.Text = icon .. " " .. label
		end
	end)

	window.Opened:Connect(function()
		loopToken += 1
		local token = loopToken
		task.spawn(function()
			while window.IsOpen and token == loopToken do
				tick()
				task.wait(0.2)
			end
		end)
	end)
	window.Closed:Connect(function()
		loopToken += 1
	end)
end

function Playtime.Open(_args: any?)
	if window.IsOpen then
		return
	end
	for i, g in gifts do
		local icon, label = rewardInfo(Rewards.Playtime[i].Reward)
		g.RewardLabel.Text = icon .. " " .. label
		g.Status = ""
		g.Popping = true
		local s = Kit.ScaleOf(g.Holder)
		s.Scale = 0
		task.delay(0.04 + i * 0.05, function()
			Kit.Pop(g.Holder, 0.2, 0.5)
			-- les cadeaux prêts reprennent leur respiration après l'apparition
			task.delay(0.5, function()
				g.Popping = false
				if g.Status == "ready" then
					Kit.Breathe(g.Holder, 0.03, 0.8)
				end
			end)
		end)
	end
	window:Open()
end

function Playtime.Close()
	window:Close()
end

return Playtime
