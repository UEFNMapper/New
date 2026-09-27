--!nonstrict
-- Écran RAMPAGE : choix du kaiju (cartes triées par puissance, aperçu 3D) et
-- du quartier (étoiles obtenues, verrous), bouton SMASH IT!, puis écran de
-- résultats (étoiles qui pop, cash qui défile, croissance gagnée, PLAY AGAIN).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rampage = require(Shared.Config.Rampage)
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

local C = Kit.Colors
local F = Kit.Fonts

local RampageScreen = {}

local CARD_W, CARD_H = 150, 180
local ROW_H = 54

local player = Players.LocalPlayer
local window: any
local results: any
local ui: any = {}
local cards: { any } = {}
local selectedUid: string? = nil
local selectedDistrict = 1
local pickedByHand = false -- le joueur a choisi lui-même un kaiju (sinon : le plus fort)
local lastResult: any = nil

local function readyIn(): number
	return math.max(0, (player:GetAttribute("RampageReadyAt") or 0) - Workspace:GetServerTimeNow())
end

local function starsData(): { number }
	local r = State.Get("Rampage")
	return if r and r.Stars then r.Stars else {}
end

local function hatched(): { any }
	local list = {}
	for _, rec in State.Get("Kaijus") or {} do
		if not rec.Egg and rec.Species and Kaijus.Get(rec.Species) then
			table.insert(list, rec)
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = Calc.Power(a), Calc.Power(b)
		if pa ~= pb then
			return pa > pb
		end
		return a.Uid < b.Uid
	end)
	return list
end

-- Petites étoiles (pleines / vides) dans un conteneur horizontal.
local function starRow(parent: Instance, count: number, size: number, z: number): ({ GuiObject }, Frame)
	local row = Kit.new("Frame", {
		Name = "Stars",
		Size = UDim2.fromOffset(size * 3 + 8, size),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	}, { Kit.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local icons = {}
	for i = 1, 3 do
		local icon = Kit.Icon("star", { Size = UDim2.fromOffset(size, size), LayoutOrder = i, ZIndex = z + 1, Parent = row })
		if icon:IsA("ImageLabel") then
			icon.ImageTransparency = if i <= count then 0 else 0.65
			icon.ImageColor3 = if i <= count then Color3.new(1, 1, 1) else Color3.fromRGB(80, 70, 100)
		else
			icon.TextTransparency = if i <= count then 0 else 0.65
		end
		icons[i] = icon
	end
	return icons, row
end

----------------------------------------------------------------------------
-- Sélection
----------------------------------------------------------------------------

local function refreshGo()
	local wait = readyIn()
	local hasKaiju = selectedUid ~= nil
	local unlocked = Rampage.Unlocked(starsData(), selectedDistrict)
	if wait > 0 then
		Kit.SetButtonText(ui.Go, ("READY IN %ds"):format(math.ceil(wait)))
		Kit.SetDisabled(ui.Go, true)
	else
		Kit.SetButtonText(ui.Go, "SMASH IT!")
		Kit.SetDisabled(ui.Go, not hasKaiju or not unlocked)
	end
	local district = Rampage.District(selectedDistrict)
	if not hasKaiju then
		ui.Info.Text = "Hatch a kaiju first, then come back!"
	else
		local rec = nil
		for _, card in cards do
			if card.Uid == selectedUid then
				rec = card.Rec
			end
		end
		local power = if rec then Calc.Power(rec) else 0
		ui.Info.Text = ("⚡ Power %.1f • Buildings x%g HP • Cash x%g"):format(power, district.HpMult, district.RewardMult)
	end
end

local function styleCard(card: any)
	local on = card.Uid == selectedUid
	card.Stroke.Color = if on then C.Magma else C.Ink
	card.Stroke.Thickness = if on then 5 else 3
	card.Check.Visible = on
	if card.Vp then
		card.Vp.Spin = on
	end
end

local function selectKaiju(uid: string)
	selectedUid = uid
	pickedByHand = true
	for _, card in cards do
		styleCard(card)
		if card.Uid == uid then
			Kit.Punch(card.Button, 0.08)
		end
	end
	refreshGo()
end

local function buildCard(rec: any, order: number): any
	local species = Kaijus.Get(rec.Species)
	local rarity = Rarities.Get(rec.Rarity)
	local stage = Growth.Get(Calc.Stage(rec))
	local button = Kit.new("TextButton", {
		Name = "Card_" .. rec.Uid,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
		ZIndex = 6,
		Parent = ui.Grid,
	})
	Kit.new("Frame", { Name = "Shadow", Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = C.Ink, ZIndex = 6, Parent = button }, { Kit.Corner(14) })
	local stroke = Kit.Stroke(3)
	local body = Kit.new("Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, ZIndex = 7, Parent = button }, { Kit.Corner(14), stroke, Kit.Gradient("Paper") })
	local spot = Kit.new("Frame", {
		Name = "Spot",
		Size = UDim2.new(1, -10, 0, 100),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = C.White,
		ZIndex = 8,
		Parent = body,
	}, { Kit.Corner(10), Kit.Stroke(2.5), Kit.Gradient({ rarity.Glow, rarity.Color:Lerp(C.Ink, 0.15) }, 90) })
	local vp = Viewport.new({ Species = rec.Species, Mutation = rec.Mutation, Parent = spot, ZIndex = 9, Spin = false })
	Kit.Chip({ Text = string.upper(stage.Name), Color = C.Ink, Size = UDim2.fromOffset(70, 22), Position = UDim2.fromOffset(4, 4), TextSize = 14, ZIndex = 11, Parent = spot })
	local check = Kit.Icon("check", { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -2, 0, 2), AnchorPoint = Vector2.new(1, 0), ZIndex = 12, Visible = false, Parent = spot })
	Kit.Text({
		Name = "KaijuName",
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 110),
		Text = if species then species.Name else rec.Species,
		FontFace = F.Title,
		TextColor3 = C.Ink,
		Stroke = false,
		MaxTextSize = 20,
		ZIndex = 9,
		Parent = body,
	})
	Kit.Text({
		Name = "Power",
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.fromOffset(6, 140),
		Text = ("⚡ %.1f POWER"):format(Calc.Power(rec)),
		FontFace = F.Impact,
		TextColor3 = C.Magma,
		Stroke = 2,
		MaxTextSize = 24,
		ZIndex = 9,
		Parent = body,
	})
	local card = { Uid = rec.Uid, Rec = rec, Button = button, Stroke = stroke, Check = check, Vp = vp }
	button.Activated:Connect(function()
		Audio.Play("ui_tab")
		selectKaiju(rec.Uid)
	end)
	return card
end

local function refreshCards()
	for _, card in cards do
		if card.Vp then
			card.Vp:Destroy()
		end
		card.Button:Destroy()
	end
	cards = {}
	local list = hatched()
	local keep = false
	for i, rec in list do
		table.insert(cards, buildCard(rec, i))
		if rec.Uid == selectedUid then
			keep = true
		end
	end
	-- par défaut : le plus fort (la liste est triée par puissance)
	if not keep or not pickedByHand then
		selectedUid = if list[1] then list[1].Uid else nil
	end
	ui.Empty.Visible = #list == 0
	for _, card in cards do
		styleCard(card)
	end
end

local function styleDistricts()
	local stars = starsData()
	for i, row in ui.Districts do
		local unlocked = Rampage.Unlocked(stars, i)
		local on = i == selectedDistrict
		row.Gradient.Color = if unlocked
			then ColorSequence.new(Color3.new(1, 1, 1):Lerp(row.District.Accent, 0.25), row.District.Accent)
			else ColorSequence.new(Color3.fromRGB(200, 200, 208), Color3.fromRGB(150, 150, 162))
		row.Stroke.Color = if on then C.Magma else C.Ink
		row.Stroke.Thickness = if on then 5 else 3
		row.Lock.Visible = not unlocked
		row.StarsRow.Visible = unlocked
		row.Sub.Text = if unlocked
			then ("HP x%g • CASH x%g"):format(row.District.HpMult, row.District.RewardMult)
			else ("Need %d stars in %s"):format(Rampage.UnlockStars, Rampage.District(i - 1).Name)
		for k, icon in row.Stars do
			local lit = k <= (stars[i] or 0)
			if icon:IsA("ImageLabel") then
				icon.ImageTransparency = if lit then 0 else 0.65
				icon.ImageColor3 = if lit then Color3.new(1, 1, 1) else Color3.fromRGB(80, 70, 100)
			else
				icon.TextTransparency = if lit then 0 else 0.65
			end
		end
	end
end

local function selectDistrict(i: number)
	if not Rampage.Unlocked(starsData(), i) then
		Audio.Play("ui_error")
		Kit.Shake(ui.Districts[i].Button, 5, 0.3)
		return
	end
	selectedDistrict = i
	Audio.Play("ui_tab")
	Kit.Punch(ui.Districts[i].Button, 0.06)
	styleDistricts()
	refreshGo()
end

local function buildDistrictRow(parent: Instance, district: Rampage.District): any
	local button = Kit.new("TextButton", {
		Name = "District" .. district.Index,
		Size = UDim2.new(1, -8, 0, ROW_H),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = district.Index,
		ZIndex = 6,
		Parent = parent,
	})
	Kit.new("Frame", { Name = "Shadow", Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = C.Ink, ZIndex = 6, Parent = button }, { Kit.Corner(12) })
	local stroke = Kit.Stroke(3)
	local gradient = Kit.Gradient("Paper")
	local body = Kit.new("Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, ZIndex = 7, Parent = button }, { Kit.Corner(12), stroke, gradient })
	local badge = Kit.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.Ink,
		ZIndex = 8,
		Parent = body,
	}, { Kit.Round(), Kit.Stroke(2.5, C.White) })
	Kit.Text({ Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Text = tostring(district.Index), TextColor3 = C.Gold, ZIndex = 9, Parent = badge })
	Kit.Text({
		Name = "DistrictName",
		Size = UDim2.new(0, 150, 0, 26),
		Position = UDim2.fromOffset(56, 4),
		Text = string.upper(district.Name),
		FontFace = F.Title,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 2.5,
		MaxTextSize = 22,
		ZIndex = 9,
		Parent = body,
	})
	local sub = Kit.Text({
		Name = "Sub",
		Size = UDim2.new(0, 170, 0, 18),
		Position = UDim2.fromOffset(56, 31),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		MaxTextSize = 15,
		ZIndex = 9,
		Parent = body,
	})
	local icons, row = starRow(body, 0, 24, 9)
	row.Position = UDim2.new(1, -8, 0.5, 0)
	row.AnchorPoint = Vector2.new(1, 0.5)
	local lock = Kit.Icon("lock", { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -24, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 10, Parent = body })
	button.Activated:Connect(function()
		selectDistrict(district.Index)
	end)
	return { District = district, Button = button, Stroke = stroke, Gradient = gradient, Sub = sub, Stars = icons, StarsRow = row, Lock = lock }
end

local function go()
	if not selectedUid then
		return
	end
	local result = Remote.Call("RampageStart", { Uid = selectedUid, District = selectedDistrict })
	if result.ok then
		window:Close(true)
	else
		Kit.Shake(ui.Go, 5, 0.3)
	end
end

----------------------------------------------------------------------------
-- Résultats
----------------------------------------------------------------------------

local HEADLINES = {
	Time = { "TIME'S UP!", C.Magma },
	Flattened = { "CITY FLATTENED!", C.RadioactiveDark },
	Quit = { "RAMPAGE OVER", C.InkSoft },
	Died = { "KNOCKED OUT!", C.Red },
	Left = { "OUT OF THE CITY!", C.Red },
}

local function refreshPlayAgain()
	local wait = readyIn()
	if wait > 0 then
		Kit.SetButtonText(results.Again, ("PLAY AGAIN (%d)"):format(math.ceil(wait)))
		Kit.SetDisabled(results.Again, true)
	else
		Kit.SetButtonText(results.Again, "PLAY AGAIN")
		Kit.SetDisabled(results.Again, false)
	end
end

local function chip(text: string, color: Color3, order: number)
	local c = Kit.Chip({ Text = text, Color = color, AutoWidth = true, Size = UDim2.fromOffset(0, 34), TextSize = 20, LayoutOrder = order, ZIndex = 8, Parent = results.Chips })
	c.Name = "Reward"
	return c
end

local function buildResults()
	results = { Window = Kit.Window({ Name = "RampageResults", Title = "RAMPAGE RESULTS", Icon = "🏆", Color = "Gold", Size = UDim2.fromOffset(660, 500), RibbonWidth = 400 }) }
	local content = results.Window.Frame
	Kit.Starburst({ Size = UDim2.fromOffset(380, 380), Position = UDim2.new(0.5, 0, 0, 60), Color = C.Gold, Transparency = 0.75, ZIndex = 5, Parent = content })
	results.Stars = {}
	local starHolder = Kit.new("Frame", { Name = "StarRow", Size = UDim2.fromOffset(300, 92), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 6, Parent = content }, {
		Kit.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom),
	})
	for i = 1, 3 do
		local size = if i == 2 then 92 else 76
		results.Stars[i] = Kit.Icon("star", { Name = "Star" .. i, Size = UDim2.fromOffset(size, size), LayoutOrder = i, ZIndex = 7, Parent = starHolder })
	end
	results.Headline = Kit.Text({ Name = "Headline", Size = UDim2.fromOffset(560, 48), Position = UDim2.new(0.5, 0, 0, 104), AnchorPoint = Vector2.new(0.5, 0), Rotation = -2, Text = "", FontFace = F.Impact, TextColor3 = C.Magma, Stroke = 3, MaxTextSize = 46, ZIndex = 8, Parent = content })
	results.Sub = Kit.Text({ Name = "Sub", Size = UDim2.fromOffset(560, 24), Position = UDim2.new(0.5, 0, 0, 154), AnchorPoint = Vector2.new(0.5, 0), Text = "", FontFace = F.Body, TextColor3 = C.InkSoft, Stroke = false, MaxTextSize = 20, ZIndex = 8, Parent = content })
	local cashRow = Kit.new("Frame", { Name = "CashRow", Size = UDim2.fromOffset(420, 58), Position = UDim2.new(0.5, 0, 0, 184), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 8, Parent = content }, {
		Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	Kit.Icon("cash", { Size = UDim2.fromOffset(54, 54), LayoutOrder = 1, ZIndex = 9, Parent = cashRow })
	results.Cash = Kit.Text({
		Name = "Cash",
		Size = UDim2.fromOffset(0, 56),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 50,
		LayoutOrder = 2,
		Text = "+$0",
		FontFace = F.Title,
		TextColor3 = C.Cash,
		Stroke = 3.5,
		ZIndex = 9,
		Parent = cashRow,
	})
	local growthRow = Kit.new("Frame", { Name = "GrowthRow", Size = UDim2.fromOffset(480, 58), Position = UDim2.new(0.5, 0, 0, 246), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 8, Parent = content }, {
		Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	results.KaijuHolder = Kit.new("Frame", { Name = "Kaiju", Size = UDim2.fromOffset(58, 58), LayoutOrder = 1, BackgroundColor3 = C.Radioactive, ZIndex = 9, Parent = growthRow }, { Kit.Round(), Kit.Stroke(3) })
	results.Growth = Kit.Text({
		Name = "Growth",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 26,
		LayoutOrder = 2,
		Text = "",
		FontFace = F.Title,
		TextColor3 = C.RadioactiveDark,
		Stroke = false,
		ZIndex = 9,
		Parent = growthRow,
	})
	results.Chips = Kit.new("Frame", { Name = "Chips", Size = UDim2.fromOffset(600, 36), Position = UDim2.new(0.5, 0, 0, 312), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 8, Parent = content }, {
		Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local buttons = Kit.new("Frame", { Name = "Buttons", Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 1, -64), BackgroundTransparency = 1, ZIndex = 8, Parent = content }, {
		Kit.List(Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	results.Again = Kit.Button({
		Name = "PlayAgain",
		Text = "PLAY AGAIN",
		Color = "Radioactive",
		Size = UDim2.fromOffset(270, 56),
		LayoutOrder = 1,
		TextSize = 28,
		OnClick = function()
			if not lastResult or readyIn() > 0 then
				return
			end
			local result = Remote.Call("RampageStart", { Uid = lastResult.Uid, District = lastResult.District })
			if result.ok then
				results.Window:Close(true)
			end
		end,
		Parent = buttons,
	})
	Kit.Button({
		Name = "Change",
		Text = "CHANGE KAIJU",
		Color = "Cyan",
		Size = UDim2.fromOffset(230, 56),
		LayoutOrder = 2,
		TextSize = 24,
		OnClick = function()
			results.Window:Close(true)
			RampageScreen.Open(if lastResult then { District = lastResult.District } else nil)
		end,
		Parent = buttons,
	})
end

function RampageScreen.ShowResults(res: any)
	lastResult = res
	if res.Uid then
		selectedUid = res.Uid
	end
	selectedDistrict = res.District or selectedDistrict
	local head = HEADLINES[res.Reason] or HEADLINES.Time
	results.Headline.Text = head[1]
	results.Headline.TextColor3 = head[2]
	results.Sub.Text = ("%s • Destruction %d%% • %d/%d smashed"):format(Rampage.District(res.District).Name, Rampage.Percent(res.Destruction), res.Smashed, res.Total)
	for i, icon in results.Stars do
		if icon:IsA("ImageLabel") then
			icon.ImageTransparency = 0.65
			icon.ImageColor3 = Color3.fromRGB(80, 70, 100)
		else
			icon.TextTransparency = 0.65
		end
		if i <= res.Stars then
			task.delay(0.35 + i * 0.35, function()
				if icon:IsA("ImageLabel") then
					icon.ImageTransparency = 0
					icon.ImageColor3 = Color3.new(1, 1, 1)
				else
					icon.TextTransparency = 0
				end
				Kit.Pop(icon, 2.4, 0.45)
				Audio.Play("reward_claim", { Pitch = 1 + i * 0.12 })
			end)
		end
	end
	results.Cash:SetAttribute("Value", 0)
	results.Cash.Text = "+$0"
	task.delay(0.3, function()
		Kit.CountTo(results.Cash, res.Cash, function(v)
			return "+" .. Format.Cash(v)
		end, 1.4)
		Audio.Play("cash_collect")
	end)
	-- aperçu du kaiju qui a grandi
	results.KaijuHolder:ClearAllChildren()
	Kit.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = results.KaijuHolder })
	Kit.Stroke(3).Parent = results.KaijuHolder
	if res.Species then
		Viewport.new({ Species = res.Species, Mutation = res.Mutation, Parent = results.KaijuHolder, ZIndex = 10 })
	end
	local species = Kaijus.Get(res.Species or "")
	local name = if species then species.Name else "your kaiju"
	local grown = false
	for _, rec in State.Get("Kaijus") or {} do
		if rec.Uid == res.Uid and Calc.Stage(rec) >= Growth.MaxStage then
			grown = true
		end
	end
	results.Growth.Text = if res.Growth > 0
		then ("+%s growth for %s!"):format(Format.Duration(res.Growth), name)
		elseif grown then ("%s is fully grown!"):format(name)
		else ("Smash buildings to make %s grow!"):format(name)
	Kit.Pop(results.Growth, 0.5, 0.5)
	for _, c in results.Chips:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local order = 0
	local function add(text: string, color: Color3)
		order += 1
		local c = chip(text, color, order)
		task.delay(1 + order * 0.2, function()
			if c.Parent then
				Kit.Pop(c, 0.3, 0.4)
			end
		end)
	end
	if res.Gems > 0 then
		add(("+%d 💎"):format(res.Gems), C.Cyan)
	end
	if res.Xp > 0 then
		add(("+%d XP"):format(res.Xp), C.Purple)
	end
	if res.Egg then
		add(("🥚 %s EGG!"):format(string.upper(Rarities.Get(res.Egg).Name)), Rarities.Get(res.Egg).Color:Lerp(C.Ink, 0.2))
	end
	if res.NewBest then
		add("NEW BEST!", C.Magma)
	end
	if res.Unlocked then
		add(("🔓 %s UNLOCKED!"):format(string.upper(Rampage.District(res.Unlocked).Name)), C.RadioactiveDark)
	end
	refreshPlayAgain()
	results.Window:Open()
	Audio.Play(if res.Stars >= 3 then "heist_success" else "quest_complete")
	task.spawn(function()
		while results.Window.IsOpen do
			refreshPlayAgain()
			task.wait(0.25)
		end
	end)
end

----------------------------------------------------------------------------
-- Écran
----------------------------------------------------------------------------

function RampageScreen.Init()
	window = Kit.Window({ Name = "Rampage", Title = "RAMPAGE!", Icon = "🏙️", Color = "Magma", Size = UDim2.fromOffset(880, 540), RibbonWidth = 340 })
	local content = window.Frame

	-- Colonne gauche : kaijus
	Kit.Text({ Name = "PickKaiju", Size = UDim2.fromOffset(480, 32), Position = UDim2.fromOffset(4, 0), Text = "1. PICK YOUR KAIJU", FontFace = F.Impact, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Left, Stroke = false, MaxTextSize = 30, ZIndex = 6, Parent = content })
	Kit.Text({
		Name = "CopyHint",
		Size = UDim2.fromOffset(500, 22),
		Position = UDim2.fromOffset(4, 32),
		Text = "It plays as a COPY: the real one keeps earning on its nest!",
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		MaxTextSize = 18,
		ZIndex = 6,
		Parent = content,
	})
	local grid = Kit.Scroll({ Name = "Grid", Size = UDim2.fromOffset(508, 398), Position = UDim2.fromOffset(0, 62), ZIndex = 6, Parent = content })
	ui.Grid = grid
	local layout = Kit.Grid(UDim2.fromOffset(CARD_W, CARD_H), 12)
	layout.Parent = grid
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12), Parent = grid })
	ui.Empty = Kit.Text({ Name = "Empty", Size = UDim2.fromOffset(420, 80), Position = UDim2.fromOffset(40, 180), Text = "No hatched kaiju yet! 🥚", FontFace = F.Title, TextColor3 = C.InkSoft, Stroke = false, MaxTextSize = 30, Visible = false, ZIndex = 7, Parent = content })

	-- Colonne droite : quartiers + GO
	local right = Kit.new("Frame", { Name = "Right", Size = UDim2.fromOffset(318, 460), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1, ZIndex = 6, Parent = content })
	Kit.Text({ Name = "PickDistrict", Size = UDim2.fromOffset(318, 32), Text = "2. PICK A DISTRICT", FontFace = F.Impact, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Left, Stroke = false, MaxTextSize = 30, ZIndex = 6, Parent = right })
	local list = Kit.new("Frame", { Name = "Districts", Size = UDim2.fromOffset(318, 5 * ROW_H + 4 * 8), Position = UDim2.fromOffset(0, 38), BackgroundTransparency = 1, ZIndex = 6, Parent = right }, {
		Kit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	ui.Districts = {}
	for _, district in Rampage.Districts do
		ui.Districts[district.Index] = buildDistrictRow(list, district)
	end
	ui.Go = Kit.Button({ Name = "Go", Text = "SMASH IT!", Icon = "💥", IconSize = 36, TextSize = 34, Color = "Radioactive", Size = UDim2.fromOffset(318, 68), Position = UDim2.fromOffset(0, 356), Sound = "purchase", OnClick = go, Parent = right })
	Kit.Breathe(ui.Go, 0.03, 0.9)
	ui.Info = Kit.Text({ Name = "Info", Size = UDim2.fromOffset(318, 24), Position = UDim2.fromOffset(0, 434), Text = "", FontFace = F.Body, TextColor3 = C.InkSoft, Stroke = false, MaxTextSize = 17, ZIndex = 6, Parent = right })

	buildResults()

	State.Observe("Rampage", function()
		if ui.Districts then
			styleDistricts()
		end
	end)
end

-- args : { District? } (quartier présélectionné)
function RampageScreen.Open(args: any?)
	local stars = starsData()
	if type(args) == "table" and args.District and Rampage.Unlocked(stars, args.District) then
		selectedDistrict = args.District
	else
		-- par défaut : le meilleur quartier ouvert qui n'a pas encore ses 3 étoiles
		selectedDistrict = 1
		for i = 1, #Rampage.Districts do
			if Rampage.Unlocked(stars, i) then
				selectedDistrict = i
				if (stars[i] or 0) < 3 then
					break
				end
			end
		end
	end
	refreshCards()
	styleDistricts()
	refreshGo()
	if window.IsOpen then
		return
	end
	window:Open()
	-- compte à rebours du bouton tant que la fenêtre est ouverte
	task.spawn(function()
		while window.IsOpen do
			task.wait(0.5)
			if window.IsOpen then
				refreshGo()
			end
		end
	end)
end

function RampageScreen.Close()
	window:Close()
	results.Window:Close()
end

return RampageScreen
