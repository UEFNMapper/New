--!nonstrict
-- Quêtes du jour : barres de progression, tampons « fait », coffre bonus
-- quand tout est réclamé, compte à rebours jusqu'au renouvellement (minuit UTC).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared.Config.Rewards)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Config.Economy)
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

local Quests = {}

local DAY = 86400
local STAT_ICONS = {
	EggsBought = "🥚",
	Steals = "🦹",
	Bonks = "🔨",
	Saves = "🛡️",
	Feeds = "🍖",
	StageUps = "🌱",
	Fusions = "🧬",
	Collects = "💵",
	Orbs = "🔮",
	Hatches = "🐣",
}
local ROW_COLORS = { "Cyan", "Pink", "Gold", "Purple", "Magma" }

local window
local listFrame: Frame
local rows: { any } = {}
local rowKey = ""
local doneChip: Frame
local resetLabel: TextLabel
local chest: any = {}
local loopToken = 0
local busy: { [string]: any } = {}

----------------------------------------------------------------------------
-- Aides
----------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function questData(): any
	return State.Get("Quests") or { Day = 0, List = {}, BonusClaimed = false }
end

local function isComplete(q: any): boolean
	local def = Progress.QuestDef(q.Id)
	return def ~= nil and (q.Progress or 0) >= def.Goal
end

local function allClaimed(data: any): boolean
	if #data.List == 0 then
		return false
	end
	for _, q in data.List do
		if not q.Claimed then
			return false
		end
	end
	return true
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
		Kit.Breathe(inst, 0.06, 0.7)
	else
		Kit.Tween(Kit.ScaleOf(inst), 0.2, { Scale = 1 })
	end
end

-- Bouton centré avec un cadre qui peut « respirer ».
local function breathingButton(parent: Instance, props: { [string]: any }): (Frame, TextButton, Frame)
	local slot = Kit.new("Frame", {
		Name = (props.Name or "Button") .. "Slot",
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
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
	bp.ZIndex = 6
	bp.Parent = breather
	return slot, Kit.Button(bp), breather
end

local function flyText(parent: Instance, str: string, color: Color3, origin: UDim2)
	local label = Kit.Text({
		Size = UDim2.fromOffset(260, 40),
		Position = origin,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "+" .. str,
		FontFace = F.Impact,
		TextColor3 = color,
		Stroke = 3,
		MaxTextSize = 40,
		ZIndex = 30,
		Parent = parent,
	})
	Kit.Pop(label, 0.3, 0.4)
	Kit.Tween(label, 1.1, { Position = origin - UDim2.fromOffset(0, 70) }, Enum.EasingStyle.Quint)
	task.delay(0.75, function()
		Kit.Tween(label, 0.35, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Kit.Tween(stroke, 0.35, { Transparency = 1 })
		end
	end)
	task.delay(1.2, function()
		label:Destroy()
	end)
end

local function slamStamp(stamp: GuiObject)
	stamp.Visible = true
	local s = Kit.ScaleOf(stamp)
	s.Scale = 3
	stamp.Rotation = -40
	Kit.Tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Kit.Tween(stamp, 0.35, { Rotation = -10 }, Enum.EasingStyle.Back)
end

----------------------------------------------------------------------------
-- Lignes de quête
----------------------------------------------------------------------------

local claimQuest: (any) -> ()

local function buildRow(i: number, q: any): any
	local def = Progress.QuestDef(q.Id)
	local holder = Kit.new("Frame", {
		Name = "Quest" .. i,
		Size = UDim2.new(1, 0, 0, 118),
		Position = UDim2.new(0.5, 0, 0, (i - 1) * 128 + 59),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = listFrame,
	})
	local box, body = Kit.Panel({
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.new(0.5, -3, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = if i % 2 == 0 then 0.7 else -0.7,
		Parent = holder,
	})
	local colorName = ROW_COLORS[(i - 1) % #ROW_COLORS + 1]
	local badge = Kit.new("Frame", {
		Size = UDim2.fromOffset(74, 74),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 3,
		Parent = body,
	}, { Kit.Round(), Kit.Stroke(3), Kit.Gradient(colorName) })
	local icon = Kit.Text({
		Size = UDim2.fromScale(0.68, 0.68),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = if def then (STAT_ICONS[def.Stat] or "⭐") else "⭐",
		FontFace = F.Body,
		Stroke = false,
		MaxTextSize = 44,
		ZIndex = 4,
		Parent = badge,
	})
	Kit.Wobble(icon, 6, 1.3 + i * 0.2)
	Kit.Text({
		Size = UDim2.new(1, -270, 0, 32),
		Position = UDim2.fromOffset(100, 10),
		Text = if def then string.upper(def.Text:format(def.Goal)) else "???",
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 2.5,
		MaxTextSize = 26,
		ZIndex = 3,
		Parent = body,
	})
	local rIcon, rLabel, rColor = rewardInfo(if def then def.Reward else { Kind = "Gems", Amount = 0 })
	local rewardChip = Kit.Chip({
		Text = "REWARD: " .. rIcon .. " " .. rLabel,
		Color = C.Ink,
		AutoWidth = true,
		Size = UDim2.fromOffset(0, 26),
		Position = UDim2.fromOffset(100, 46),
		TextSize = 16,
		ZIndex = 3,
		Parent = body,
	})
	rewardChip.Rotation = -1.5
	local bar, setBar = Kit.ProgressBar({
		Size = UDim2.new(1, -290, 0, 22),
		Position = UDim2.fromOffset(102, 80),
		Color = "Radioactive",
		ZIndex = 3,
		Parent = body,
	})
	local count = Kit.Text({
		Size = UDim2.new(1, 0, 1, 4),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "0 / 0",
		FontFace = F.Impact,
		Stroke = 2,
		MaxTextSize = 22,
		ZIndex = 10,
		Parent = bar,
	})
	local slot, button, breather = breathingButton(body, {
		Name = "Claim",
		Text = "CLAIM!",
		Color = "Radioactive",
		Size = UDim2.fromOffset(150, 62),
		Position = UDim2.new(1, -90, 0.5, 0),
		MaxTextSize = 28,
		OnClick = function()
			claimQuest(q.Id)
		end,
	})
	local pending = Kit.Chip({
		Text = "IN PROGRESS",
		Color = C.InkSoft,
		Size = UDim2.fromOffset(150, 32),
		Position = UDim2.new(1, -90, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 16,
		ZIndex = 5,
		Parent = body,
	})
	local dim = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Paper,
		BackgroundTransparency = 0.4,
		ZIndex = 8,
		Visible = false,
		Parent = body,
	}, { Kit.Corner() })
	local stamp = Kit.new("Frame", {
		Size = UDim2.fromOffset(130, 52),
		Position = UDim2.new(1, -90, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -10,
		BackgroundColor3 = C.White,
		ZIndex = 9,
		Visible = false,
		Parent = body,
	}, { Kit.Corner(10), Kit.Stroke(4, C.RadioactiveDark), Kit.Gradient({ C.White, C.Paper }) })
	Kit.Text({
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "DONE ✓",
		TextColor3 = C.RadioactiveDark,
		Stroke = false,
		MaxTextSize = 30,
		ZIndex = 10,
		Parent = stamp,
	})
	return {
		Id = q.Id,
		Def = def,
		Holder = holder,
		Box = box,
		Body = body,
		SetBar = setBar,
		Count = count,
		Slot = slot,
		Button = button,
		Breather = breather,
		Pending = pending,
		Dim = dim,
		Stamp = stamp,
		RewardColor = rColor,
		RewardChip = rewardChip,
		LastProgress = nil :: number?,
		Status = "",
		Claiming = false,
	}
end

local function rebuildRows(data: any)
	for _, r in rows do
		r.Holder:Destroy()
	end
	rows = {}
	local ids = {}
	for i, q in data.List do
		rows[i] = buildRow(i, q)
		table.insert(ids, q.Id)
	end
	rowKey = table.concat(ids, ",")
end

----------------------------------------------------------------------------
-- Coffre bonus
----------------------------------------------------------------------------

local function buildChest(parent: Instance)
	local box, body = Kit.Panel({
		Name = "Bonus",
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.new(0.5, -3, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 1.2,
		Gradient = "Ink",
		Parent = parent,
	})
	-- CanvasGroup : découpe fiable même sous une fenêtre inclinée
	local clip = Kit.new("CanvasGroup", {
		Name = "Clip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = body,
	}, { Kit.Corner() })
	local burst = Kit.Starburst({ Size = UDim2.fromOffset(520, 520), Position = UDim2.new(0.5, 0, 0.45, 0), Color = C.Gold, Transparency = 0.35, ZIndex = 2, Parent = clip })
	burst.Visible = false
	Kit.Hazard({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 0), ZIndex = 3, Parent = body })
	Kit.Text({
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 20),
		Text = "ALL-DONE BONUS",
		TextColor3 = C.Gold,
		Stroke = 3,
		MaxTextSize = 28,
		ZIndex = 4,
		Parent = body,
	})
	local _, label, color = rewardInfo(Rewards.AllQuestsBonus)
	local rewardLabel = Kit.Text({
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, 54),
		Text = label,
		FontFace = F.Impact,
		TextColor3 = color,
		Stroke = 2.5,
		MaxTextSize = 28,
		ZIndex = 4,
		Parent = body,
	})
	-- œuf qui flotte au-dessus du coffre
	local eggHolder = Kit.new("Frame", {
		Size = UDim2.fromOffset(110, 110),
		Position = UDim2.new(0.5, 0, 0, 140),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = body,
	})
	local egg = Viewport.new({ Egg = Rewards.AllQuestsBonus.Rarity or "Legendary", Size = UDim2.fromScale(1, 1), ZIndex = 4, Speed = 1.3, Parent = eggHolder })
	Kit.Tween(eggHolder, 1.1, { Position = UDim2.new(0.5, 0, 0, 128) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	-- coffre dessiné
	local chestFrame = Kit.new("Frame", {
		Size = UDim2.fromOffset(150, 96),
		Position = UDim2.new(0.5, 0, 0, 236),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = body,
	})
	local base = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.White,
		ZIndex = 5,
		Parent = chestFrame,
	}, { Kit.Corner(8), Kit.Stroke(4), Kit.Gradient({ Color3.fromRGB(190, 110, 50), Color3.fromRGB(120, 60, 25) }) })
	for _, x in { 0.18, 0.82 } do
		Kit.new("Frame", {
			Size = UDim2.new(0, 12, 1, 0),
			Position = UDim2.fromScale(x, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = base,
		})
	end
	local lid = Kit.new("Frame", {
		Size = UDim2.new(1, 8, 0, 44),
		Position = UDim2.new(0.5, 0, 1, -62),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.White,
		ZIndex = 7,
		Parent = chestFrame,
	}, { Kit.Corner(14), Kit.Stroke(4), Kit.Gradient({ Color3.fromRGB(215, 135, 65), Color3.fromRGB(150, 80, 35) }) })
	local lidHome = lid.Position
	local lock = Kit.new("Frame", {
		Size = UDim2.fromOffset(30, 34),
		Position = UDim2.new(0.5, 0, 1, -44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Gold,
		ZIndex = 8,
		Parent = chestFrame,
	}, { Kit.Corner(6), Kit.Stroke(3) })
	local progress = Kit.Chip({
		Text = "0 / 3 CLAIMED",
		Color = C.InkSoft,
		Size = UDim2.new(1, -40, 0, 30),
		Position = UDim2.new(0.5, 0, 1, -96),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 18,
		ZIndex = 6,
		Parent = body,
	})
	local slot, button, breather = breathingButton(body, {
		Name = "ClaimBonus",
		Text = "OPEN!",
		Color = "Gold",
		Size = UDim2.new(1, -40, 0, 60),
		Position = UDim2.new(0.5, 0, 1, -44),
		MaxTextSize = 30,
	})
	local claimed = Kit.Chip({
		Text = "CLAIMED ✓",
		Color = C.RadioactiveDark,
		Size = UDim2.new(1, -60, 0, 36),
		Position = UDim2.new(0.5, 0, 1, -44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 20,
		ZIndex = 6,
		Parent = body,
	})
	chest = {
		Box = box,
		Body = body,
		Burst = burst,
		RewardLabel = rewardLabel,
		Egg = egg,
		EggHolder = eggHolder,
		Chest = chestFrame,
		Lid = lid,
		LidHome = lidHome,
		Lock = lock,
		Progress = progress,
		Slot = slot,
		Button = button,
		Breather = breather,
		Claimed = claimed,
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
	local data = questData()
	local ids = {}
	for _, q in data.List do
		table.insert(ids, q.Id)
	end
	if table.concat(ids, ",") ~= rowKey then
		rebuildRows(data)
	end
	local claimedCount = 0
	for i, q in data.List do
		local r = rows[i]
		if r and r.Def then
			local goal = r.Def.Goal
			local p = math.min(q.Progress or 0, goal)
			r.SetBar(p / goal, r.LastProgress == nil)
			r.Count.Text = string.format("%d / %d", p, goal)
			if r.LastProgress ~= nil and p ~= r.LastProgress then
				Kit.Punch(r.Count, 0.35)
			end
			r.LastProgress = p
			if r.Def.Reward.Kind == "Cash" then
				local chipLabel = r.RewardChip:FindFirstChild("Text") :: TextLabel?
				local rIcon, rLabel = rewardInfo(r.Def.Reward)
				if chipLabel then
					chipLabel.Text = "REWARD: " .. rIcon .. " " .. rLabel
				end
			end
			local status = if q.Claimed then "claimed" elseif p >= goal then "ready" else "progress"
			if q.Claimed then
				claimedCount += 1
			end
			if status ~= r.Status and not r.Claiming then
				local previous = r.Status
				r.Status = status
				r.Slot.Visible = status == "ready"
				r.Pending.Visible = status == "progress"
				r.Dim.Visible = status == "claimed"
				r.Stamp.Visible = status == "claimed"
				setBreathe(r.Breather, status == "ready")
				if status == "ready" and previous == "progress" then
					Audio.Play("quest_complete")
					Kit.Punch(r.Box, 0.08)
					Kit.Pop(r.Slot, 0.3, 0.5)
				end
			end
		end
	end
	-- coffre
	local total = #data.List
	local progressLabel = chest.Progress:FindFirstChild("Text") :: TextLabel?
	if progressLabel then
		progressLabel.Text = string.format("%d / %d CLAIMED", claimedCount, total)
	end
	local chestStatus = if data.BonusClaimed then "claimed" elseif allClaimed(data) then "ready" else "locked"
	if chestStatus ~= chest.Status then
		chest.Status = chestStatus
		chest.Slot.Visible = chestStatus ~= "claimed"
		chest.Claimed.Visible = chestStatus == "claimed"
		chest.Burst.Visible = chestStatus ~= "locked"
		chest.Lock.Visible = chestStatus ~= "claimed"
		chest.Lid.Position = if chestStatus == "claimed" then chest.LidHome - UDim2.fromOffset(0, 26) else chest.LidHome
		chest.Lid.Rotation = if chestStatus == "claimed" then -18 else 0
		Kit.SetButtonText(chest.Button, if chestStatus == "ready" then "OPEN!" else "LOCKED 🔒")
		Kit.SetDisabled(chest.Button, false)
		Kit.SetButtonColor(chest.Button, "Gold")
		Kit.SetDisabled(chest.Button, chestStatus ~= "ready")
		setBreathe(chest.Breather, chestStatus == "ready")
		if chestStatus == "ready" then
			Kit.Wobble(chest.Chest, 4, 0.25)
		else
			Kit.Tween(chest.Chest, 0.2, { Rotation = 0 })
		end
	end
	local doneLabel = doneChip:FindFirstChild("Text") :: TextLabel?
	if doneLabel then
		doneLabel.Text = string.format("✔ %d / %d DONE", claimedCount, total)
	end
end

local function tick()
	local t = now()
	local data = questData()
	if data.Day ~= 0 and data.Day < Progress.DayNumber(t) then
		resetLabel.Text = "New quests are ready!"
		resetLabel.TextColor3 = C.RadioactiveDark
	else
		resetLabel.Text = "New quests in " .. Format.Clock(DAY - (t % DAY))
		resetLabel.TextColor3 = C.InkSoft
	end
end

----------------------------------------------------------------------------
-- Réclamations
----------------------------------------------------------------------------

claimQuest = function(id: string)
	if busy[id] then
		return
	end
	local row
	for _, r in rows do
		if r.Id == id then
			row = r
		end
	end
	busy[id] = true
	if row then
		row.Claiming = true
		Kit.SetDisabled(row.Button, true)
	end
	local r = Remote.Call("ClaimQuest", { Id = id })
	busy[id] = nil
	if row then
		row.Claiming = false
		Kit.SetDisabled(row.Button, false)
	end
	if not r.ok then
		refresh()
		return
	end
	Audio.Play("reward_claim")
	UIRegistry.Toast("Quest reward: " .. tostring(r.text or ""), "Good")
	if row and row.Holder.Parent then
		row.Status = "claimed"
		row.Slot.Visible = false
		row.Pending.Visible = false
		row.Dim.Visible = true
		setBreathe(row.Breather, false)
		slamStamp(row.Stamp)
		Kit.Shake(row.Box, 5, 0.3)
		flyText(row.Holder, tostring(r.text or ""), row.RewardColor, UDim2.new(1, -90, 0.3, 0))
	end
	refresh()
end

local function claimBonus()
	if busy.bonus then
		return
	end
	busy.bonus = true
	local r = Remote.Call("ClaimQuestBonus")
	busy.bonus = nil
	if not r.ok then
		refresh()
		return
	end
	Audio.Play("spin_win")
	UIRegistry.Toast("Bonus: " .. tostring(r.text or ""), "Good")
	-- le couvercle saute, l'œuf jaillit
	chest.Status = "claimed"
	chest.Slot.Visible = false
	chest.Claimed.Visible = true
	chest.Lock.Visible = false
	Kit.Tween(chest.Chest, 0.15, { Rotation = 0 })
	Kit.Tween(chest.Lid, 0.4, { Position = chest.LidHome - UDim2.fromOffset(0, 26), Rotation = -18 }, Enum.EasingStyle.Back)
	Kit.Shake(chest.Box, 7, 0.35)
	Kit.Punch(chest.EggHolder, 0.6)
	Kit.Pop(chest.Claimed, 0.3, 0.5)
	flyText(chest.Body, tostring(r.text or ""), C.Gold, UDim2.new(0.5, 0, 0, 120))
	refresh()
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

function Quests.ClaimableCount(): number
	local data = State.Get("Quests")
	if type(data) ~= "table" or type(data.List) ~= "table" then
		return 0
	end
	if data.Day ~= 0 and data.Day < Progress.DayNumber(now()) then
		return 0
	end
	local n = 0
	for _, q in data.List do
		if not q.Claimed and isComplete(q) then
			n += 1
		end
	end
	if not data.BonusClaimed and allClaimed(data) then
		n += 1
	end
	return n
end

function Quests.Init()
	window = Kit.Window({ Name = "Quests", Title = "DAILY QUESTS", Icon = "📜", Color = "Radioactive", Size = UDim2.fromOffset(860, 540), RibbonWidth = 400 })
	local content = window.Frame

	doneChip = Kit.Chip({
		Text = "✔ 0 / 3 DONE",
		Color = C.RadioactiveDark,
		Size = UDim2.fromOffset(200, 36),
		Position = UDim2.fromOffset(4, 6),
		TextSize = 22,
		Parent = content,
	})
	doneChip.Rotation = -2
	resetLabel = Kit.Text({
		Size = UDim2.new(1, -230, 0, 30),
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

	listFrame = Kit.new("Frame", {
		Name = "List",
		Size = UDim2.new(1, -290, 1, -56),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local chestHolder = Kit.new("Frame", {
		Name = "ChestHolder",
		Size = UDim2.new(0, 280, 1, -60),
		Position = UDim2.new(1, -140, 0.5, 28),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = content,
	})
	buildChest(chestHolder)
	chest.Holder = chestHolder
	chest.Button.Activated:Connect(function()
		if chest.Status == "ready" then
			task.spawn(claimBonus)
		end
	end)

	for _, key in { "Quests", "Income" } do
		State.Changed(key):Connect(function()
			if window.IsOpen then
				refresh()
			end
		end)
	end

	window.Opened:Connect(function()
		loopToken += 1
		local token = loopToken
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

function Quests.Open(_args: any?)
	window:Open()
	rowKey = "" -- reconstruit pour rejouer l'apparition
	for _, r in rows do
		r.Holder:Destroy()
	end
	rows = {}
	chest.Status = ""
	refresh()
	for i, r in rows do
		local s = Kit.ScaleOf(r.Holder)
		s.Scale = 0
		task.delay(0.05 + i * 0.08, function()
			if r.Holder.Parent then
				Kit.Pop(r.Holder, 0.2, 0.5)
			end
		end)
	end
	Kit.Pop(chest.Holder, 0.3, 0.6)
end

function Quests.Close()
	window:Close()
end

return Quests
