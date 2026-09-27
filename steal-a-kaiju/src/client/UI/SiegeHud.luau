--!nonstrict
-- HUD de la défense de l'île : compte à rebours + START NOW, suivi de la vague
-- (restants, fuites), barre de vie de l'Alpha, bandeau de sirène, carte de fin
-- de vague et révélation de l'œuf sauvage. Lit les attributs du dossier
-- workspace.Siege.Plot<i> (voir SiegeService) ; initialisé par SiegeRenderer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Siege = require(Shared.Config.Siege)
local Layout = require(Shared.Config.Layout)
local Rarities = require(Shared.Config.Rarities)
local Kaijus = require(Shared.Config.Kaijus)
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Kit)
local Viewport = require(script.Parent.Viewport)
local Controllers = script.Parent.Parent.Controllers
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local CameraFx = require(Controllers.CameraFx)
local UIRegistry = require(Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts
local player = Players.LocalPlayer

local SiegeHud = {}

local layer: ScreenGui
local ui: { [string]: any } = {}
local watched: Folder? = nil
local lastBeep = -1
local cards: { () -> () } = {}
local showingCard = false

local PAUSE_TEXT = {
	Away = "Go back to your island!",
	Rampage = "Finish your Rampage first!",
	AFK = "Move to wake them up!",
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function siegeFolder(index: number?): Folder?
	local root = Workspace:FindFirstChild("Siege")
	return if root and index then root:FindFirstChild("Plot" .. index) :: Folder? else nil
end

-- Île sur laquelle se tient le joueur (visiteur ou chez lui).
local function standingPlot(): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	for i = 1, Layout.PlotCount do
		if Layout.InPlot(Layout.PlotCFrame(i), root.Position, Siege.IslandMargin) then
			return i
		end
	end
	return nil
end

----------------------------------------------------------------------------
-- Panneau d'état (haut à gauche)
----------------------------------------------------------------------------

local function buildStatus()
	local holder = Kit.new("Frame", {
		Name = "SiegeStatus",
		Size = UDim2.fromOffset(300, 100),
		Position = UDim2.fromOffset(16, 58),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Kit.AutoScale(holder)
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Rotation = -1.5, Gradient = "Ink", Parent = holder })
	Kit.Hazard({ Size = UDim2.new(1, -24, 0, 8), Position = UDim2.fromOffset(12, 7), ZIndex = 3, Parent = body })
	ui.Title = Kit.Text({
		Name = "Title",
		Size = UDim2.new(1, -28, 0, 22),
		Position = UDim2.fromOffset(14, 16),
		Text = "🦖 WAVE 1 IN",
		FontFace = F.Impact,
		TextColor3 = C.Radioactive,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Parent = body,
	})
	ui.Value = Kit.Text({
		Name = "Value",
		Size = UDim2.fromOffset(130, 42),
		Position = UDim2.fromOffset(14, 38),
		Text = "2:30",
		FontFace = F.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 40,
		ZIndex = 4,
		Parent = body,
	})
	ui.Sub = Kit.Text({
		Name = "Sub",
		Size = UDim2.new(1, -28, 0, 16),
		Position = UDim2.fromOffset(14, 80),
		Text = "",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		ZIndex = 4,
		Parent = body,
	})
	local bar, setBar = Kit.ProgressBar({ Name = "Progress", Size = UDim2.new(1, -28, 0, 12), Position = UDim2.fromOffset(14, 82), Color = "Radioactive", ZIndex = 4, Parent = body })
	ui.Bar, ui.SetBar = bar, setBar
	ui.StartNow = Kit.Button({
		Name = "StartNow",
		Text = "START NOW",
		Color = "Magma",
		Size = UDim2.fromOffset(136, 44),
		Position = UDim2.new(1, -12, 0, 34),
		AnchorPoint = Vector2.new(1, 0),
		MaxTextSize = 22,
		ZIndex = 6,
		Parent = body,
		OnClick = function()
			local result = Remote.Call("SiegeStartNow")
			if result.ok then
				CameraFx.Shake(0.4, 0.3)
			end
		end,
	})
	local bonus = Kit.Chip({ Name = "Bonus", Text = "+10%", Size = UDim2.fromOffset(58, 22), Position = UDim2.new(1, 10, 0, -16), AnchorPoint = Vector2.new(1, 0), Color = C.Gold, ZIndex = 12, Parent = ui.StartNow })
	bonus.Rotation = 8
	Kit.Breathe(ui.StartNow, 0.04, 0.8)
	ui.Leaks = Kit.Chip({ Name = "Leaks", Text = "💰 0 LEAKS", Size = UDim2.fromOffset(128, 30), Position = UDim2.new(1, -12, 0, 42), AnchorPoint = Vector2.new(1, 0), Color = C.Red, ZIndex = 6, Parent = body })
	ui.Status = holder
end

----------------------------------------------------------------------------
-- Barre de vie de l'Alpha (sous les monnaies, même échelle que le HUD)
----------------------------------------------------------------------------

local function buildAlphaBar()
	local holder = Kit.new("Frame", {
		Name = "SiegeAlpha",
		Size = UDim2.fromOffset(560, 230),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Kit.AutoScale(holder)
	ui.AlphaTitle = Kit.Text({ Name = "Title", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 160), Text = "👑 ALPHA", FontFace = F.Impact, TextColor3 = C.Gold, Stroke = 3, ZIndex = 4, Parent = holder })
	local _, set = Kit.ProgressBar({ Size = UDim2.new(1, -40, 0, 24), Position = UDim2.fromOffset(20, 194), Color = "Red", ZIndex = 4, Parent = holder })
	ui.AlphaHP = Kit.Text({ Name = "HP", Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, 196), Text = "", FontFace = F.Title, ZIndex = 20, Parent = holder })
	ui.SetAlpha = set
	ui.Alpha = holder
end

----------------------------------------------------------------------------
-- Bandeau de sirène
----------------------------------------------------------------------------

local function siren(args)
	local tutorial = args.Tutorial == true
	local holder = Kit.new("Frame", {
		Name = "SiegeBanner",
		Size = UDim2.fromOffset(820, 150),
		Position = UDim2.fromScale(0.5, 0.34),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Kit.AutoScale(holder)
	Kit.Hazard({ Size = UDim2.new(1, 0, 0, 16), Parent = holder, ColorA = C.Red })
	Kit.Hazard({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), Parent = holder, ColorA = C.Red })
	local title = if tutorial then "🚨 TRAINING WAVE!" else ("🚨 WAVE %d"):format(args.Wave or 1)
	Kit.Text({ Size = UDim2.new(1, 0, 0, 78), Position = UDim2.fromOffset(0, 18), Text = title, FontFace = F.Impact, TextColor3 = C.Red, Stroke = 6, MaxTextSize = 80, Rotation = -2, Parent = holder })
	local subtitle = ("%d WILD KAIJUS INCOMING!"):format(args.Count or 0)
	if args.Alpha then
		subtitle = ("%d INVADERS + 👑 ALPHA!"):format((args.Count or 1) - 1)
	elseif tutorial then
		subtitle = "Your kaijus shoot them — BONK the ones that get close!"
	end
	Kit.Text({ Size = UDim2.new(1, -40, 0, 38), Position = UDim2.new(0.5, 0, 0, 96), AnchorPoint = Vector2.new(0.5, 0), Text = subtitle, FontFace = F.Title, TextColor3 = C.White, Stroke = 3, MaxTextSize = 36, Parent = holder })
	Kit.Pop(holder, 2.2, 0.4)
	Audio.Play("meteor_rare_alarm")
	Audio.Play("event_horn", { Volume = 0.7 })
	CameraFx.Shake(0.6, 0.6)
	-- bords rouges qui clignotent
	local edges = Kit.new("Frame", { Name = "SirenEdges", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = layer })
	for _, side in {
		{ UDim2.new(1, 0, 0, 26), UDim2.new() },
		{ UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 1, -26) },
		{ UDim2.new(0, 26, 1, 0), UDim2.new() },
		{ UDim2.new(0, 26, 1, 0), UDim2.new(1, -26, 0, 0) },
	} do
		Kit.new("Frame", { Size = side[1], Position = side[2], BackgroundColor3 = C.Red, BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = edges })
	end
	task.spawn(function()
		for i = 1, 6 do
			edges.Visible = i % 2 == 1
			task.wait(0.3)
		end
		edges:Destroy()
		task.wait(0.8)
		Kit.Tween(Kit.ScaleOf(holder), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.3)
		holder:Destroy()
	end)
end

----------------------------------------------------------------------------
-- Cartes (fin de vague, œuf de l'Alpha) : une à la fois
----------------------------------------------------------------------------

local function queueCard(fn: () -> ())
	table.insert(cards, fn)
	if showingCard then
		return
	end
	showingCard = true
	task.spawn(function()
		while #cards > 0 do
			local job = table.remove(cards, 1)
			local ok, err = pcall(job)
			if not ok then
				warn("[SiegeHud] " .. tostring(err))
			end
		end
		showingCard = false
	end)
end

local function cardFrame(name: string, size: Vector2, gradient: string): (Frame, Frame)
	local holder = Kit.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Kit.AutoScale(holder)
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Gradient = gradient, Parent = holder })
	Kit.Pop(holder, 0.3, 0.45)
	return holder, body
end

local function closeCard(holder: Frame)
	Kit.Tween(Kit.ScaleOf(holder), 0.22, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.wait(0.25)
	holder:Destroy()
end

-- Attend un clic sur OK ou la fin du délai.
local function waitClose(button: TextButton, seconds: number)
	local done = false
	button.Activated:Connect(function()
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < seconds do
		task.wait(0.1)
	end
end

local function waveEndCard(args)
	local cleared = args.Cleared == true
	local holder, body = cardFrame("SiegeEnd", Vector2.new(520, 320), if cleared then "Paper" else "Ink")
	local title = if args.Tutorial then "TRAINING COMPLETE!" elseif cleared then ("WAVE %d CLEARED!"):format(args.Wave or 1) else ("WAVE %d FAILED"):format(args.Wave or 1)
	Kit.Ribbon({ Text = title, Color = if cleared then "Radioactive" else "Red", Size = UDim2.fromOffset(420, 62), Position = UDim2.new(0.5, 0, 0, -30), ZIndex = 5, Parent = holder })
	if cleared then
		Kit.Starburst({ Size = UDim2.fromOffset(620, 620), Position = UDim2.fromScale(0.5, 0.45), Color = C.Gold, Transparency = 0.75, ZIndex = 0, Parent = holder })
		-- étoiles
		local stars = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 1, Parent = body }, {
			Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
		})
		for i = 1, 3 do
			local star = Kit.Text({ Size = UDim2.fromOffset(60, 60), Text = "⭐", FontFace = F.Body, Stroke = false, LayoutOrder = i, ZIndex = 6, Parent = stars })
			star.TextTransparency = if i <= (args.Stars or 0) then 0 else 0.75
			task.delay(0.15 * i, function()
				Kit.Pop(star, 2, 0.35)
				if i <= (args.Stars or 0) then
					Audio.Play("coin_tick", { Pitch = 1 + i * 0.15 })
				end
			end)
		end
		local cash = Kit.Text({ Name = "Cash", Size = UDim2.new(1, -40, 0, 54), Position = UDim2.fromOffset(20, 98), Text = "+$0", FontFace = F.Title, TextColor3 = C.Cash, Stroke = 4, MaxTextSize = 56, ZIndex = 6, Parent = body })
		Kit.CountTo(cash, args.Cash or 0, function(v)
			return "+" .. Format.Cash(math.floor(v))
		end, 1.2)
		local extras = {}
		if (args.Gems or 0) > 0 then
			table.insert(extras, ("+%d 💎"):format(args.Gems))
		end
		if (args.Xp or 0) > 0 then
			table.insert(extras, ("+%d XP"):format(args.Xp))
		end
		if args.Bonus then
			table.insert(extras, "START NOW +10%")
		end
		Kit.Text({ Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 154), Text = table.concat(extras, "   "), FontFace = F.Title, TextColor3 = C.Gem, Stroke = 3, MaxTextSize = 28, ZIndex = 6, Parent = body })
		Kit.Text({ Size = UDim2.new(1, -40, 0, 22), Position = UDim2.fromOffset(20, 186), Text = ("👾 %d defeated   💰 %d leaked"):format(args.Kills or 0, args.Leaks or 0), FontFace = F.Body, TextColor3 = C.Ink, Stroke = false, MaxTextSize = 22, ZIndex = 6, Parent = body })
		Audio.Play("heist_success")
	else
		Kit.Text({ Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 50), Text = "Too many wild kaijus got away with your cash!", FontFace = F.Title, TextColor3 = C.White, Stroke = 3, MaxTextSize = 30, ZIndex = 6, Parent = body })
		Kit.Text({ Size = UDim2.new(1, -40, 0, 48), Position = UDim2.fromOffset(20, 128), Text = "Grow your kaijus and BONK more — you'll try this wave again!", FontFace = F.Body, TextColor3 = C.Paper, Stroke = false, MaxTextSize = 24, ZIndex = 6, Parent = body })
		Audio.Play("ui_error")
	end
	local ok = Kit.Button({ Name = "Ok", Text = if cleared then "AWESOME!" else "I'LL GET THEM!", Color = if cleared then "Radioactive" else "Magma", Size = UDim2.fromOffset(220, 54), Position = UDim2.new(0.5, 0, 1, -26), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 8, Parent = body })
	waitClose(ok, 5)
	closeCard(holder)
end

local function eggCard(args)
	local rarity = Rarities.Get(args.Rarity or "Rare")
	local holder, body = cardFrame("SiegeEgg", Vector2.new(420, 290), "Ink")
	holder.Position = UDim2.fromScale(0.5, 0.62)
	Kit.Starburst({ Size = UDim2.fromOffset(600, 600), Position = UDim2.fromScale(0.5, 0.42), Color = rarity.Color, Transparency = 0.6, ZIndex = 0, Parent = holder })
	Kit.Ribbon({ Text = "👑 ALPHA DEFEATED!", Color = "Gold", Size = UDim2.fromOffset(360, 58), Position = UDim2.new(0.5, 0, 0, -28), ZIndex = 5, Parent = holder })
	local vp = Viewport.new({ Size = UDim2.fromOffset(160, 160), Position = UDim2.new(0.5, 0, 0, 32), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 6, Speed = 1.4, Parent = body })
	vp:SetEgg(rarity.Id)
	Kit.Text({ Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 192), Text = ("WILD %s EGG!"):format(string.upper(rarity.Name)), FontFace = F.Impact, TextColor3 = rarity.Color, Stroke = 4, MaxTextSize = 44, ZIndex = 6, Parent = body })
	Kit.Text({ Size = UDim2.new(1, -40, 0, 24), Position = UDim2.fromOffset(20, 240), Text = "It's in your nest — hatch it!", FontFace = F.Body, TextColor3 = C.Paper, Stroke = false, MaxTextSize = 24, ZIndex = 6, Parent = body })
	Audio.Play(if rarity.Order >= 4 then "hatch_legendary" else "hatch_epic")
	CameraFx.Shake(0.5, 0.5)
	local t0 = os.clock()
	while os.clock() - t0 < 3.2 do
		task.wait(0.1)
	end
	vp:Destroy()
	closeCard(holder)
end

----------------------------------------------------------------------------
-- Mise à jour continue
----------------------------------------------------------------------------

local function alphaInvader(folder: Folder): BasePart?
	for _, child in folder:GetChildren() do
		if child:GetAttribute("Alpha") == true then
			return child :: BasePart
		end
	end
	return nil
end

local function refresh()
	local mine = siegeFolder(player:GetAttribute("Plot"))
	local here = siegeFolder(standingPlot())
	local folder = nil
	if mine and (mine:GetAttribute("State") or "Idle") ~= "Idle" then
		folder = mine
	end
	if here and here ~= mine and here:GetAttribute("State") == "Active" then
		folder = here
	end
	watched = folder
	local status = ui.Status
	if not folder then
		status.Visible = false
		ui.Alpha.Visible = false
		return
	end
	if not status.Visible then
		status.Visible = true
		Kit.Pop(status, 0.4, 0.4)
	end
	local state = folder:GetAttribute("State")
	local wave = folder:GetAttribute("Wave") or 1
	local helping = folder ~= mine
	if state == "Active" then
		local left = folder:GetAttribute("Remaining") or 0
		local count = math.max(folder:GetAttribute("Count") or 1, 1)
		local leaks = folder:GetAttribute("Leaks") or 0
		if helping then
			ui.Title.Text = ("🛡️ HELP %s!"):format(string.upper(folder:GetAttribute("OwnerName") or "THEM"))
		else
			ui.Title.Text = if folder:GetAttribute("Tutorial") then "🚨 TRAINING WAVE" else ("🚨 WAVE %d"):format(wave)
		end
		ui.Title.TextColor3 = C.Red
		ui.Value.Text = ("%d LEFT"):format(left)
		ui.Value.TextColor3 = C.White
		ui.StartNow.Visible = false
		ui.Leaks.Visible = true
		local leakText = ui.Leaks:FindFirstChild("Text") :: TextLabel?
		if leakText then
			leakText.Text = ("💰 %d LEAK%s"):format(leaks, if leaks == 1 then "" else "S")
		end
		ui.Leaks.BackgroundColor3 = if leaks > 0 then C.Red else C.InkSoft
		ui.Sub.Visible = false
		ui.Bar.Visible = true
		local progress = 1 - left / count
		if progress ~= ui.LastProgress then
			ui.LastProgress = progress
			ui.SetBar(progress)
		end
	else
		local left = if state == "Paused" then (folder:GetAttribute("Left") or 0) else math.max(0, (folder:GetAttribute("At") or 0) - now())
		local paused = state == "Paused"
		local alphaWave = folder:GetAttribute("Alpha") == true
		if paused then
			ui.Title.Text = ("WAVE %d PAUSED"):format(wave)
		else
			ui.Title.Text = if alphaWave then ("👑 ALPHA WAVE %d IN"):format(wave) else ("🦖 WAVE %d IN"):format(wave)
		end
		ui.Title.TextColor3 = if paused then C.Gold elseif alphaWave then C.Gold else C.Radioactive
		ui.Value.Text = Format.Clock(math.ceil(left))
		ui.Value.TextColor3 = if paused then C.PaperDark else (if left <= 10 then C.Gold else C.White)
		ui.StartNow.Visible = true
		ui.Leaks.Visible = false
		ui.Bar.Visible = false
		local reason = folder:GetAttribute("Reason") or ""
		ui.Sub.Visible = paused
		ui.Sub.Text = PAUSE_TEXT[reason] or ""
		ui.Sub.TextColor3 = C.Gold
		-- derniers instants : bips
		local whole = math.ceil(left)
		if state == "Countdown" and whole <= 5 and whole >= 1 and whole ~= lastBeep then
			lastBeep = whole
			Audio.Play("countdown_beep", { Pitch = 1 + (5 - whole) * 0.08 })
			Kit.Punch(ui.Value, 0.25)
		end
	end
	-- Alpha
	local alpha = if state == "Active" then alphaInvader(folder) else nil
	if alpha then
		local hp, max = alpha:GetAttribute("HP") or 0, math.max(alpha:GetAttribute("MaxHP") or 1, 1)
		if not ui.Alpha.Visible then
			ui.Alpha.Visible = true
			Kit.Pop(ui.Alpha)
			Audio.Play("roar_big")
		end
		local species = Kaijus.Get(alpha:GetAttribute("Species") or "")
		ui.AlphaTitle.Text = ("👑 ALPHA %s"):format(if species then string.upper(species.Name) else "")
		if hp / max ~= ui.LastAlpha then
			ui.LastAlpha = hp / max
			ui.SetAlpha(hp / max)
		end
		ui.AlphaHP.Text = ("%s / %s"):format(Format.Short(math.ceil(hp)), Format.Short(math.ceil(max)))
	else
		ui.Alpha.Visible = false
	end
end

-- Dossier du siège actuellement suivi par le HUD (nil si rien à montrer).
function SiegeHud.Watched(): Folder?
	return watched
end

function SiegeHud.Init()
	layer = Kit.Layer("SiegeHud", 7)
	buildStatus()
	buildAlphaBar()

	FxBus.On("SiegeWaveStart", function(args)
		if args.Owner == player.UserId then
			siren(args)
		end
	end)
	FxBus.On("SiegeWaveEnd", function(args)
		queueCard(function()
			waveEndCard(args)
		end)
	end)
	FxBus.On("SiegeAlphaEgg", function(args)
		queueCard(function()
			eggCard(args)
		end)
	end)
	FxBus.On("SiegeLeak", function(args)
		if (args.Amount or 0) > 0 then
			UIRegistry.Toast(("😱 A wild kaiju stole %s! BONK IT to get it back!"):format(Format.Cash(args.Amount)), "Bad")
		else
			UIRegistry.Toast("😱 A wild kaiju reached your reactor! Stop the others!", "Bad")
		end
		Audio.Play("shield_zap", { Pitch = 0.7 })
		if ui.Leaks.Visible then
			Kit.Shake(ui.Leaks, 6, 0.4)
		end
	end)
	FxBus.On("SiegeEscaped", function(args)
		if (args.Amount or 0) > 0 then
			UIRegistry.Toast(("💨 It got away with %s..."):format(Format.Cash(args.Amount)), "Bad")
		end
	end)
	FxBus.On("SiegeBagSaved", function(args)
		if args.By == player.UserId or player:GetAttribute("Plot") == args.Plot then
			UIRegistry.Toast(("💰 Cash bag saved: +%s!"):format(Format.Cash(args.Amount or 0)), "Cash")
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn("[SiegeHud] " .. tostring(err))
			end
			task.wait(0.2)
		end
	end)
end

return SiegeHud
