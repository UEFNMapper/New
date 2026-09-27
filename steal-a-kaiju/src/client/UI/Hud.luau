--!nonstrict
-- HUD principal : compteurs (cash, gemmes, $/s), menus latéraux, bouton de
-- verrouillage, bannière d'événement, boosts actifs, indicateur de vol,
-- alarme de vol (vignette rouge), pièces volantes vers le compteur.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local Events = require(Shared.Config.Events)
local Economy = require(Shared.Config.Economy)
local Kaijus = require(Shared.Config.Kaijus)
local Growth = require(Shared.Config.Growth)
local Rarities = require(Shared.Config.Rarities)
local TutorialConfig = require(Shared.Config.Tutorial)
local Levels = require(Shared.Config.Levels)
local Worlds = require(Shared.Config.Worlds)
local Tutorial = require(script.Parent.Parent.World.Tutorial)

local Kit = require(script.Parent.Kit)
local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local UIRegistry = require(Controllers.UIRegistry)
local CameraFx = require(Controllers.CameraFx)

local C = Kit.Colors
local F = Kit.Fonts
local player = Players.LocalPlayer

local Hud = {}

local layer: ScreenGui
local cashLabel: TextLabel
local incomeLabel: TextLabel
local gemLabel: TextLabel
local cashPanel: Frame
local storedChip: Frame
local lockButton: TextButton
local eventBanner: Frame
local boostRow: Frame
local carryPanel: Frame
local alarm: Frame
local menuButtons: { [string]: GuiObject } = {}
local alarmSound: Sound? = nil
local alarmUntil = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

----------------------------------------------------------------------------
-- Compteurs
----------------------------------------------------------------------------

local function currencyPanel(props): (Frame, TextLabel)
	local container, body = Kit.Panel({
		Name = props.Name,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Rotation = props.Rotation,
		Gradient = "Ink",
		Parent = props.Parent,
	})
	local icon = Kit.Text({
		Size = UDim2.new(0, props.IconSize or 52, 1, 6),
		Position = UDim2.fromOffset(-14, -3),
		Text = props.Icon,
		FontFace = F.Body,
		Stroke = false,
		ZIndex = 4,
		Parent = body,
	})
	Kit.Wobble(icon, 6, 1.4)
	local label = Kit.Text({
		Name = "Value",
		Size = UDim2.new(1, -(props.IconSize or 52), props.ValueHeight or 1, -8),
		Position = UDim2.fromOffset((props.IconSize or 52) - 6, 4),
		Text = "0",
		FontFace = F.Impact,
		TextColor3 = props.Color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 3,
		MaxTextSize = props.MaxTextSize or 46,
		ZIndex = 4,
		Parent = body,
	})
	return container, label
end

local function buildCurrencies()
	local top = Kit.new("Frame", {
		Name = "Top",
		Size = UDim2.fromOffset(560, 180),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Kit.AutoScale(top)
	local panel
	panel, cashLabel = currencyPanel({
		Name = "Cash",
		Icon = "💵",
		Size = UDim2.fromOffset(300, 74),
		Position = UDim2.fromOffset(40, 0),
		Rotation = -1.5,
		Color = C.Cash,
		ValueHeight = 0.72,
		Parent = top,
	})
	cashPanel = panel
	incomeLabel = Kit.Text({
		Size = UDim2.new(1, -60, 0.32, 0),
		Position = UDim2.new(0, 46, 0.66, -4),
		Text = "+$0/s",
		FontFace = F.Body,
		TextColor3 = C.Radioactive,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 2,
		ZIndex = 4,
		Parent = panel:FindFirstChild("Body"),
	})
	local gemPanel
	gemPanel, gemLabel = currencyPanel({
		Name = "Gems",
		Icon = "💎",
		IconSize = 44,
		Size = UDim2.fromOffset(170, 58),
		Position = UDim2.fromOffset(362, 8),
		Rotation = 1.5,
		Color = C.Gem,
		MaxTextSize = 36,
		Parent = top,
	})

	-- Cash en attente dans le réacteur
	storedChip = Kit.Chip({
		Name = "Stored",
		Text = "⚛️ $0 in reactor",
		Color = C.RadioactiveDark,
		Size = UDim2.fromOffset(250, 30),
		Position = UDim2.fromOffset(64, 80),
		Parent = top,
	})
	storedChip.Visible = false

	-- Prochain météore / œuf disponible dans le cratère
	local meteorChip = Kit.Chip({
		Name = "Meteor",
		Text = "☄️ Next meteor in 10s",
		Color = C.MagmaDark,
		Size = UDim2.fromOffset(250, 30),
		Position = UDim2.fromOffset(64, 116),
		Parent = top,
	})
	local meteorText = meteorChip:FindFirstChild("Text") :: TextLabel
	-- Prochain météore doré (rendez-vous régulier sur ton île)
	local goldenChip = Kit.Chip({
		Name = "Golden",
		Text = "🌟 Golden meteor in 0:00",
		Color = C.Gold:Lerp(C.Ink, 0.45),
		Size = UDim2.fromOffset(250, 26),
		Position = UDim2.fromOffset(64, 150),
		TextSize = 16,
		Parent = top,
	})
	local goldenText = goldenChip:FindFirstChild("Text") :: TextLabel
	RunService.Heartbeat:Connect(function()
		local at = player:GetAttribute("GoldenMeteorAt")
		local step = State.Get("Tutorial") or 0
		goldenChip.Visible = at ~= nil and step >= TutorialConfig.Done
		if at then
			local left = at - now()
			goldenText.Text = if left > 1 then "🌟 Golden meteor in " .. Format.Clock(left) else "🌟 GOLDEN METEOR INCOMING!"
		end
	end)
	local lastBest = ""
	RunService.Heartbeat:Connect(function()
		local folder = Workspace:FindFirstChild("Meteors")
		local best, bestOrder = nil, 0
		-- œufs du monde où l'on se trouve (le cratère quand on est sur son île)
		local here = player:GetAttribute("World") or "Island"
		local worldId = if Worlds.ById[here] then here else Worlds.Default
		local inWorld = worldId ~= Worlds.Default
		if folder then
			for _, m in folder:GetChildren() do
				if m:IsA("BasePart") and (m:GetAttribute("Owner") or 0) == 0 and (m:GetAttribute("LandAt") or 0) <= now() and (m:GetAttribute("World") or Worlds.Default) == worldId then
					local order = Rarities.Get(m:GetAttribute("Rarity") or "Common").Order
					if order > bestOrder then
						best, bestOrder = m, order
					end
				end
			end
		end
		if best then
			local rarity = Rarities.Get(best:GetAttribute("Rarity") or "Common")
			local left = (best:GetAttribute("ExpireAt") or 0) - now()
			meteorText.Text = ("☄️ %s EGG %s! %ds"):format(string.upper(rarity.Name), if inWorld then "landed here" else "in the crater", math.max(0, math.ceil(left)))
			meteorChip.BackgroundColor3 = rarity.Color:Lerp(C.Ink, 0.35)
			if lastBest ~= best.Name then
				lastBest = best.Name
				Kit.Punch(meteorChip, 0.15)
			end
		else
			lastBest = ""
			local wait = Workspace:GetAttribute(if inWorld then "NextMeteorIn_" .. worldId else "NextMeteorIn") or -1
			meteorText.Text = if wait >= 0 then ("☄️ Next meteor in %ds"):format(math.ceil(wait)) else "☄️ Meteors paused (raid!)"
			meteorChip.BackgroundColor3 = C.MagmaDark
		end
	end)

	State.Observe("Cash", function(value)
		local previous = cashLabel:GetAttribute("Value") or value
		Kit.CountTo(cashLabel, value, Format.Cash, 0.7)
		if value > previous then
			Kit.Punch(cashPanel, 0.08)
		end
	end)
	State.Observe("Gems", function(value)
		local previous = gemLabel:GetAttribute("Value") or value
		Kit.CountTo(gemLabel, value, Format.Short, 0.6)
		if value ~= previous then
			Kit.Punch(gemPanel, 0.12)
		end
	end)
	State.Observe("Income", function(value)
		local mult = State.Get("Multiplier") or 1
		local multText = if mult < 10 then (("%.2f"):format(mult):gsub("0+$", ""):gsub("%.$", "")) else Format.Short(mult)
		incomeLabel.Text = ("+%s/s"):format(Format.Cash(value)) .. (if mult > 1.001 then ("  <font color=\"#FFC828\">x%s</font>"):format(multText) else "")
	end)
	State.Observe("Stored", function(value)
		local auto = (State.Get("Passes") or {}).AutoCollect
		storedChip.Visible = value >= 1 and not auto
		local text = storedChip:FindFirstChild("Text") :: TextLabel
		text.Text = ("⚛️ %s in reactor"):format(Format.Cash(value))
	end)
	Kit.Breathe(storedChip, 0.05, 0.7)
end

-- Pièces qui volent jusqu'au compteur.
function Hud.FlyCoins(icon: string, count: number, from: Vector2?)
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local start = from or Vector2.new(viewport.X / 2, viewport.Y * 0.62)
	local target = cashPanel.AbsolutePosition + cashPanel.AbsoluteSize / 2
	for i = 1, count do
		task.delay(i * 0.035, function()
			local coin = Kit.Text({
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.fromOffset(start.X, start.Y),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Text = icon,
				FontFace = F.Body,
				Stroke = false,
				ZIndex = 60,
				Parent = layer,
			})
			local mid = start + Vector2.new(math.random(-220, 220), math.random(-260, -80))
			local t0 = os.clock()
			local d = 0.55 + math.random() * 0.25
			local conn
			conn = RunService.RenderStepped:Connect(function()
				local a = math.clamp((os.clock() - t0) / d, 0, 1)
				local e = a * a
				local p = start:Lerp(mid, e):Lerp(mid:Lerp(target, e), e)
				coin.Position = UDim2.fromOffset(p.X, p.Y)
				coin.Rotation = a * 360
				if a >= 1 then
					conn:Disconnect()
					coin:Destroy()
					Audio.Play("coin_tick", { Cooldown = 0.02, Volume = 0.5 })
					Kit.Punch(cashPanel, 0.05)
				end
			end)
		end)
	end
end

-- Nombre flottant (+$1.2K) près du compteur.
function Hud.FloatText(text: string, color: Color3)
	local label = Kit.Text({
		Size = UDim2.fromOffset(260, 44),
		Position = UDim2.new(0.5, math.random(-60, 60), 0, 118),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = text,
		FontFace = F.Impact,
		TextColor3 = color,
		Stroke = 3,
		ZIndex = 61,
		Parent = layer,
	})
	Kit.Pop(label, 1.8, 0.3)
	Kit.Tween(label, 1.2, { Position = label.Position - UDim2.fromOffset(0, 60), TextTransparency = 1 }, Enum.EasingStyle.Quad)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		Kit.Tween(stroke, 1.2, { Transparency = 1 })
	end
	task.delay(1.3, function()
		label:Destroy()
	end)
end

----------------------------------------------------------------------------
-- Niveau + « NEXT GOAL » (en haut à gauche)
----------------------------------------------------------------------------

local levelPanel: Frame
local leftColumn: Frame? = nil -- colonne de gauche : niveau, compagnon, menus (une seule échelle)

-- Colonne de gauche, partagée avec la pastille du compagnon (BuddyRenderer).
function Hud.LeftColumn(): Frame
	local column = leftColumn
	if not column then
		column = Kit.new("Frame", {
			Name = "LeftColumn",
			Size = UDim2.fromOffset(350, 620),
			Position = UDim2.fromOffset(16, 62),
			BackgroundTransparency = 1,
			Parent = layer,
		}, { Kit.List(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top) })
		Kit.AutoScale(column)
		leftColumn = column
	end
	return column
end

-- Le prochain objectif du joueur : un monde à ouvrir, sinon le prochain déblocage de niveau.
local function nextGoal(): (string, number?, string?)
	local level = State.Get("Level") or 1
	local rebirths = State.Get("Rebirths") or 0
	local cash = State.Get("Cash") or 0
	local unlocked = State.Get("Worlds") or {}
	for _, w in Worlds.List do
		if not unlocked[w.Id] and Worlds.MeetsGate(w, level, rebirths) then
			if cash >= w.Toll then
				return ("🌍 %s is ready! TAP TO UNLOCK"):format(string.upper(w.Name)), 1, w.Id
			end
			return ("🌍 Save %s for %s"):format(Format.Cash(w.Toll), string.upper(w.Name)), cash / math.max(1, w.Toll), w.Id
		end
	end
	local u = Levels.NextUnlock(level)
	if u then
		return ("⭐ LV %d unlocks %s"):format(u.Level, u.Text), nil, if u.Kind == "World" then u.Id else nil
	end
	return "⭐ Max unlocks reached — chase the Kaijudex!", nil, nil
end

local function buildLevel()
	levelPanel = Kit.new("Frame", {
		Name = "Level",
		Size = UDim2.fromOffset(330, 84),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = Hud.LeftColumn(),
	})
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Rotation = -1, Gradient = "Ink", Parent = levelPanel })
	local star = Kit.Icon("level", { Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(-10, -6), ZIndex = 5, Parent = body })
	Kit.Wobble(star, 5, 1.6)
	local levelNumber = Kit.Text({
		Name = "Number",
		Size = UDim2.fromOffset(70, 40),
		Position = UDim2.fromOffset(-10, 12),
		Text = "1",
		FontFace = F.Impact,
		MaxTextSize = 30,
		Stroke = 3,
		ZIndex = 7,
		Parent = body,
	})
	local title = Kit.Text({
		Name = "Title",
		Size = UDim2.new(1, -80, 0, 26),
		Position = UDim2.fromOffset(64, 4),
		Text = "LEVEL 1",
		FontFace = F.Title,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		ZIndex = 5,
		Parent = body,
	})
	local xpText = Kit.Text({
		Name = "Xp",
		Size = UDim2.new(1, -80, 0, 18),
		Position = UDim2.fromOffset(64, 4),
		Text = "0 / 40 XP",
		FontFace = F.Body,
		TextColor3 = C.Paper,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 14,
		ZIndex = 5,
		Parent = body,
	})
	local _, setXp = Kit.ProgressBar({ Name = "XpBar", Size = UDim2.new(1, -80, 0, 14), Position = UDim2.fromOffset(64, 32), Color = "Gold", Parent = body })
	local goalButton = Kit.new("TextButton", {
		Name = "Goal",
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.new(0, 8, 1, -30),
		BackgroundColor3 = C.InkSoft,
		Text = "",
		AutoButtonColor = true,
		ZIndex = 5,
		Parent = body,
	}, { Kit.Round() })
	local goalFill = Kit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.RadioactiveDark,
		ZIndex = 5,
		Parent = goalButton,
	}, { Kit.Round() })
	local goalText = Kit.Text({
		Name = "Text",
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(6, 0),
		Text = "",
		FontFace = F.Title,
		MaxTextSize = 15,
		Stroke = 2,
		ZIndex = 6,
		Parent = goalButton,
	})
	local goalWorld: string? = nil
	goalButton.Activated:Connect(function()
		Audio.Play("ui_click")
		local screen = (UIRegistry.Screens :: any).Worlds
		if screen and screen.Open and (State.Get("Level") or 1) >= (Levels.MenuLevels.Worlds or 1) then
			screen.Open(goalWorld)
		end
	end)

	local lastLevel = 0
	local function refresh()
		local xp = State.Get("Xp") or 0
		local level, progress, into, need = Levels.FromXp(xp)
		levelNumber.Text = tostring(level)
		title.Text = "LEVEL " .. level
		xpText.Text = if need > 0 then ("%s / %s XP"):format(Format.Short(into), Format.Short(need)) else "MAX"
		setXp(progress, lastLevel == level)
		if lastLevel ~= 0 and level > lastLevel then
			Kit.Punch(levelPanel, 0.2)
		end
		lastLevel = level
		local text, fill, world = nextGoal()
		goalText.Text = text
		goalWorld = world
		goalFill.Visible = fill ~= nil
		goalFill.Size = UDim2.fromScale(math.clamp(fill or 0, 0, 1), 1)
		goalFill.BackgroundColor3 = if fill and fill >= 1 then C.Gold else C.RadioactiveDark
	end
	for _, key in { "Xp", "Level", "Cash", "Worlds", "Rebirths" } do
		State.Observe(key, refresh)
	end
	-- l'objectif « prêt à ouvrir » respire pour attirer l'œil
	Kit.Breathe(goalButton, 0.03, 0.8)
end

-- « +10 XP » qui monte depuis la barre de niveau.
local function floatXp(amount: number)
	if not levelPanel then
		return
	end
	local label = Kit.Text({
		Size = UDim2.fromOffset(120, 30),
		Position = UDim2.new(0, levelPanel.AbsolutePosition.X + levelPanel.AbsoluteSize.X * 0.7 + math.random(-20, 20), 0, levelPanel.AbsolutePosition.Y + levelPanel.AbsoluteSize.Y * 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = ("+%d XP"):format(amount),
		FontFace = F.Impact,
		TextColor3 = C.Gold,
		Stroke = 3,
		ZIndex = 62,
		Parent = layer,
	})
	Kit.Pop(label, 1.5, 0.25)
	Kit.Tween(label, 1, { Position = label.Position - UDim2.fromOffset(0, 40), TextTransparency = 1 }, Enum.EasingStyle.Quad)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		Kit.Tween(stroke, 1, { Transparency = 1 })
	end
	task.delay(1.1, function()
		label:Destroy()
	end)
end

local function levelUp(args)
	local lines = {}
	for _, u in args.Unlocks or {} do
		table.insert(lines, u.Text)
	end
	local sub = ("+%d 💎"):format(args.Gems or 0)
	if args.Egg then
		sub ..= "  •  " .. string.upper(args.Egg) .. " EGG"
	end
	if #lines > 0 then
		sub = "UNLOCKED: " .. table.concat(lines, " • ") .. "   " .. sub
	end
	UIRegistry.Announce(("LEVEL %d!"):format(args.Level or 1), C.Gold, sub, "level_jingle")
	CameraFx.FovPunch(-6, 0.5)
	Hud.FlyCoins("💎", 10)
end

----------------------------------------------------------------------------
-- Menus latéraux
----------------------------------------------------------------------------

local function menuButton(parent: Instance, props): TextButton
	local button = Kit.Button({
		Name = props.Id,
		Text = "",
		Color = props.Color,
		Size = UDim2.fromOffset(84, 84),
		LayoutOrder = props.Order,
		Rotation = props.Rotation,
		HoverTilt = -props.Rotation * 2 + 3,
		Corner = 18,
		Parent = parent,
		OnClick = props.OnClick,
	})
	local face = button:FindFirstChild("Face")
	Kit.Icon(props.Icon, {
		Name = "Emoji",
		Size = UDim2.fromScale(0.66, 0.66),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 12,
		Parent = face,
	})
	Kit.Text({
		Name = "Caption",
		Size = UDim2.new(1, 12, 0, 22),
		Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = props.Text,
		FontFace = F.Title,
		MaxTextSize = 20,
		Stroke = 2.5,
		ZIndex = 13,
		Parent = button,
	})
	menuButtons[props.Id] = button
	return button
end

local function openScreen(name: string, args: any?)
	local screen = UIRegistry.Screens[name]
	if screen and screen.Open then
		screen.Open(args)
	end
end

local function buildMenus()
	local left = Kit.new("Frame", {
		Name = "LeftMenu",
		Size = UDim2.fromOffset(200, 310),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = Hud.LeftColumn(),
	}, {
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(84, 84),
			CellPadding = UDim2.fromOffset(14, 22),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Kit.Padding(4, 8),
	})
	menuButton(left, { Id = "Shop", Text = "SHOP", Icon = "shop", Color = "Magma", Order = 1, Rotation = -3, OnClick = function() openScreen("Shop") end })
	menuButton(left, { Id = "Upgrades", Text = "UPGRADES", Icon = "upgrades", Color = "Pink", Order = 2, Rotation = 3, OnClick = function() openScreen("Shop", "Upgrades") end })
	menuButton(left, { Id = "Worlds", Text = "WORLDS", Icon = "worlds", Color = "Cyan", Order = 3, Rotation = 2, OnClick = function() openScreen("Worlds") end })
	menuButton(left, { Id = "Index", Text = "KAIJUDEX", Icon = "kaijudex", Color = "Gold", Order = 4, Rotation = -2, OnClick = function() openScreen("Index") end })
	menuButton(left, { Id = "Fusion", Text = "FUSION", Icon = "fusion", Color = "Purple", Order = 5, Rotation = -3, OnClick = function() openScreen("Fusion") end })
	menuButton(left, { Id = "Rebirth", Text = "EVOLVE", Icon = "evolve", Color = "Radioactive", Order = 6, Rotation = 2, OnClick = function() openScreen("Rebirth") end })

	local right = Kit.new("Frame", {
		Name = "RightMenu",
		Size = UDim2.fromOffset(100, 500),
		Position = UDim2.new(1, -16, 0.5, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.List(Enum.FillDirection.Vertical, 38, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	Kit.AutoScale(right)
	menuButton(right, { Id = "Rewards", Text = "REWARDS", Icon = "rewards", Color = "Pink", Order = 1, Rotation = 3, OnClick = function() openScreen("Rewards") end })
	menuButton(right, { Id = "Rampage", Text = "RAMPAGE", Icon = "rampage", Color = "Red", Order = 2, Rotation = -2, OnClick = function() openScreen("Rampage") end })
	menuButton(right, { Id = "Settings", Text = "SETTINGS", Icon = "settings", Color = "Ink", Order = 3, Rotation = -2, OnClick = function() openScreen("Settings") end })
	menuButton(right, { Id = "HowToPlay", Text = "HELP", Icon = "howtoplay", Color = "Cyan", Order = 4, Rotation = 2, OnClick = function() openScreen("HowToPlay") end })

	-- Déblocage progressif des menus : missions du tutoriel, puis niveaux
	local function refreshMenus()
		local step = math.max(1, State.Get("Tutorial") or 1)
		local visible = TutorialConfig.VisibleMenus(step)
		if step >= TutorialConfig.Done then
			local level = State.Get("Level") or 1
			for id, need in Levels.MenuLevels do
				if level >= need then
					visible[id] = true
				end
			end
		end
		for id, button in menuButtons do
			local show = visible[id] == true
			if show and not button.Visible then
				button.Visible = true
				Kit.Pop(button, 0.2, 0.5)
			elseif not show then
				button.Visible = false
			end
		end
	end
	State.Observe("Tutorial", refreshMenus)
	State.Observe("Level", refreshMenus)

	-- Badges : rafraîchis régulièrement
	task.spawn(function()
		while true do
			local screens = UIRegistry.Screens
			local function badge(id: string, count: number)
				local b = menuButtons[id]
				if b then
					Kit.SetBadge(b, count > 0, if count > 1 then tostring(count) else "!")
				end
			end
			if screens.Rewards and screens.Rewards.ClaimableCount then
				badge("Rewards", screens.Rewards.ClaimableCount())
			end
			if screens.Worlds and screens.Worlds.UnlockableCount then
				badge("Worlds", screens.Worlds.UnlockableCount())
			end
			-- Évolution disponible ?
			local rebirths = State.Get("Rebirths") or 0
			local nextR = Economy.Rebirths[rebirths + 1]
			local canEvolve = nextR and (State.Get("Cash") or 0) >= nextR.Cost and (State.Get("Level") or 1) >= (Levels.MenuLevels.Rebirth or 1)
			badge("Rebirth", if canEvolve then 1 else 0)
			task.wait(0.5)
		end
	end)
end

----------------------------------------------------------------------------
-- Bouton de verrouillage + boosts + bannière d'événement
----------------------------------------------------------------------------

local function myPlot(): Instance?
	local index = player:GetAttribute("Plot")
	local map = Workspace:FindFirstChild("Map")
	return if index and map then map:FindFirstChild("Plot" .. index) else nil
end

local function buildBottom()
	local bottom = Kit.new("Frame", {
		Name = "Bottom",
		Size = UDim2.fromOffset(700, 90),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Kit.AutoScale(bottom)
	lockButton = Kit.Button({
		Name = "Lock",
		Text = "LOCK BASE",
		Icon = "🛡️",
		Color = "Red",
		Size = UDim2.fromOffset(250, 70),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 28,
		Sound = "shield_on",
		OnClick = function()
			local r = Remote.Call("Lock")
			if r.ok then
				CameraFx.FovPunch(-6, 0.5)
			end
		end,
		Parent = bottom,
	})
	Kit.Text({
		Name = "Key",
		Size = UDim2.fromOffset(34, 22),
		Position = UDim2.new(1, -8, 0, -8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "[L]",
		FontFace = F.Title,
		MaxTextSize = 18,
		ZIndex = 20,
		Parent = lockButton,
	})

	-- Retour à la maison (quand on est loin de son île)
	local homeButton = Kit.Button({
		Name = "Home",
		Text = "HOME",
		Icon = "home",
		Color = "Radioactive",
		Size = UDim2.fromOffset(190, 70),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 28,
		Sound = "whoosh",
		OnClick = function()
			Remote.Call("Home")
		end,
		Parent = bottom,
	})
	homeButton.Visible = false
	RunService.Heartbeat:Connect(function()
		local where = player:GetAttribute("World") or "Island"
		local away = where ~= "Island"
		local plot = myPlot()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local floor = plot and plot:FindFirstChild("Floor") :: BasePart?
		if floor and root and not away then
			away = (root.Position - floor.Position).Magnitude > 170
		end
		local inRampage = (player:GetAttribute("Rampage") or false) ~= false
		homeButton.Visible = away and not inRampage
		-- le bouclier ne sert que contre d'autres joueurs
		local others = #Players:GetPlayers() > 1
		lockButton.Visible = others and not homeButton.Visible and not inRampage
		lockButton.Position = UDim2.new(0.5, 0, 1, -8)
	end)

	boostRow = Kit.new("Frame", {
		Name = "Boosts",
		Size = UDim2.fromOffset(600, 34),
		Position = UDim2.new(0.5, 0, 0, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = bottom,
	}, { Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })

	-- Mise à jour du bouclier et des boosts
	local chips: { [string]: Frame } = {}
	local function chip(id: string, text: string, color: Color3)
		local c = chips[id]
		if not c then
			c = Kit.Chip({ Name = id, Text = text, Color = color, AutoWidth = true, Size = UDim2.fromOffset(0, 30), TextSize = 18, Parent = boostRow })
			chips[id] = c
			Kit.Pop(c)
		end
		local chipText = c:FindFirstChild("Text") :: TextLabel
		chipText.Text = text
		c:SetAttribute("Seen", true)
	end
	RunService.Heartbeat:Connect(function()
		local t = now()
		local plot = myPlot()
		if plot then
			local shield = (plot:GetAttribute("ShieldUntil") or 0) - t
			local protected = (plot:GetAttribute("ProtectedUntil") or 0) - t
			local cooldown = (plot:GetAttribute("ShieldCooldown") or 0) - t
			if shield > 0 then
				Kit.SetButtonText(lockButton, "SHIELD " .. Format.Clock(shield))
				Kit.SetButtonColor(lockButton, "Cyan")
			elseif protected > 0 then
				Kit.SetButtonText(lockButton, "SAFE " .. Format.Clock(protected))
				Kit.SetButtonColor(lockButton, "Radioactive")
			elseif cooldown > 0 then
				Kit.SetButtonText(lockButton, "RECHARGE " .. Format.Clock(cooldown))
				Kit.SetButtonColor(lockButton, "Grey")
			else
				Kit.SetButtonText(lockButton, "LOCK BASE")
				Kit.SetButtonColor(lockButton, "Red")
			end
		end
		for _, c in chips do
			c:SetAttribute("Seen", false)
		end
		local boosts = State.Get("Boosts") or {}
		local unix = os.time()
		if (boosts.Luck or 0) > unix then
			chip("Luck", "🍀 x2 LUCK " .. Format.Clock(boosts.Luck - unix), C.RadioactiveDark)
		end
		if (boosts.Growth or 0) > unix then
			chip("Growth", "🌱 x2 GROWTH " .. Format.Clock(boosts.Growth - unix), Color3.fromRGB(90, 150, 40))
		end
		if (boosts.Cash or 0) > unix then
			chip("Cash", "💸 x2 CASH " .. Format.Clock(boosts.Cash - unix), C.RadioactiveDark)
		end
		local serverLuckUntil = Workspace:GetAttribute("ServerLuckUntil") or 0
		if serverLuckUntil > t then
			chip("ServerLuck", ("🍀 SERVER LUCK x%s %s"):format(Format.Short(Workspace:GetAttribute("ServerLuck") or 2), Format.Clock(serverLuckUntil - t)), C.Purple)
		end
		local friends = State.Get("Friends") or 0
		if friends > 0 then
			chip("Friends", ("👥 +%d%% FRIENDS"):format(math.min(friends * 10, 40)), C.Cyan:Lerp(C.Ink, 0.4))
		end
		for id, c in chips do
			if not c:GetAttribute("Seen") then
				c:Destroy()
				chips[id] = nil
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.L then
			Remote.Call("Lock")
		end
	end)
end

local function buildEventBanner()
	eventBanner = Kit.new("Frame", {
		Name = "Event",
		Size = UDim2.fromOffset(330, 92),
		Position = UDim2.new(1, -20, 0, 16),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Kit.AutoScale(eventBanner)
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Rotation = 1.5, Gradient = "Ink", Parent = eventBanner })
	local icon = Kit.Text({ Name = "Icon", Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(8, 8), Text = "🌠", FontFace = F.Body, Stroke = false, ZIndex = 4, Parent = body })
	Kit.Wobble(icon, 10, 0.8)
	Kit.Text({ Name = "Name", Size = UDim2.new(1, -86, 0, 34), Position = UDim2.fromOffset(76, 8), Text = "EVENT", FontFace = F.Impact, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = body })
	Kit.Text({ Name = "Time", Size = UDim2.new(1, -86, 0, 22), Position = UDim2.fromOffset(76, 42), Text = "0:00", FontFace = F.Body, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = body })
	local _, setBar = Kit.ProgressBar({ Size = UDim2.new(1, -24, 0, 12), Position = UDim2.new(0, 12, 1, -18), Color = "Magma", Parent = body })
	-- Raid : bouton pour rejoindre le cratère en un clic
	local goButton = Kit.Button({
		Name = "Go",
		Text = "GO!",
		Color = "Radioactive",
		Size = UDim2.fromOffset(84, 44),
		Position = UDim2.new(1, -10, 0, 30),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 22,
		ZIndex = 8,
		OnClick = function()
			Remote.Call("Travel", { Id = Worlds.Default })
		end,
		Parent = body,
	})
	goButton.Visible = false

	local function refresh()
		local id = Workspace:GetAttribute("EventId")
		local event = id and Events.ById[id]
		eventBanner.Visible = event ~= nil
		if event then
			local nameLabel = body:FindFirstChild("Name") :: TextLabel
			local iconLabel = body:FindFirstChild("Icon") :: TextLabel
			nameLabel.Text = event.Name
			nameLabel.TextColor3 = event.Color
			iconLabel.Text = event.Icon
			Kit.Pop(eventBanner, 0.3)
		end
	end
	Workspace:GetAttributeChangedSignal("EventId"):Connect(refresh)
	refresh()
	RunService.Heartbeat:Connect(function()
		if not eventBanner.Visible then
			return
		end
		local id = Workspace:GetAttribute("EventId")
		local event = id and Events.ById[id]
		local left = (Workspace:GetAttribute("EventEnds") or 0) - now()
		local timeLabel = body:FindFirstChild("Time") :: TextLabel
		timeLabel.Text = "⏱️ " .. Format.Clock(left) .. " left"
		goButton.Visible = id == "BossRaid" and player:GetAttribute("World") ~= Worlds.Default and not player:GetAttribute("Rampage")
		if event then
			setBar(left / event.Duration, true)
		end
	end)
end

----------------------------------------------------------------------------
-- Vol : indicateur de portage + alarme
----------------------------------------------------------------------------

local function buildCarry()
	carryPanel = Kit.new("Frame", {
		Name = "Carry",
		Size = UDim2.fromOffset(460, 110),
		Position = UDim2.new(0.5, 0, 1, -130),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Kit.AutoScale(carryPanel)
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Rotation = -1, Gradient = "Pink", Parent = carryPanel })
	Kit.Hazard({ Size = UDim2.new(1, -20, 0, 10), Position = UDim2.fromOffset(10, 6), Parent = body })
	Kit.Text({ Name = "Title", Size = UDim2.new(1, -150, 0, 40), Position = UDim2.fromOffset(14, 20), Text = "CARRYING!", FontFace = F.Impact, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = body })
	Kit.Text({ Name = "Hint", Size = UDim2.new(1, -150, 0, 24), Position = UDim2.fromOffset(14, 60), Text = "Run back to your island!", FontFace = F.Body, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = body })
	local _, setBar = Kit.ProgressBar({ Name = "Timer", Size = UDim2.new(1, -150, 0, 12), Position = UDim2.new(0, 14, 1, -22), Color = "Gold", Parent = body })
	Kit.Button({
		Name = "Drop",
		Text = "DROP [Q]",
		Color = "Ink",
		Size = UDim2.fromOffset(120, 56),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 22,
		OnClick = function()
			Remote.Call("Drop")
		end,
		Parent = body,
	})
	local startedAt = 0
	local current = ""
	RunService.Heartbeat:Connect(function()
		local uid = player:GetAttribute("Carrying") or ""
		if uid ~= current then
			current = uid
			startedAt = os.clock()
			carryPanel.Visible = uid ~= ""
			if uid ~= "" then
				Kit.Pop(carryPanel, 0.5)
			end
		end
		if uid == "" then
			return
		end
		local anchor = nil
		local folder = Workspace:FindFirstChild("Kaijus")
		if folder then
			for _, owner in folder:GetChildren() do
				anchor = owner:FindFirstChild(uid)
				if anchor then
					break
				end
			end
		end
		local title = body:FindFirstChild("Title") :: TextLabel
		local hint = body:FindFirstChild("Hint") :: TextLabel
		if anchor then
			local species = Kaijus.Get(anchor:GetAttribute("Species") or "")
			local stage = Growth.Get(anchor:GetAttribute("Stage") or 1)
			if anchor:GetAttribute("Lifting") then
				local left = (anchor:GetAttribute("LiftUntil") or 0) - now()
				title.Text = "TOO HEAVY! 🆘"
				hint.Text = ("A %s needs 2 thieves — wait for help (%ds)"):format(stage.Name, math.max(0, math.ceil(left)))
				startedAt = os.clock()
			else
				title.Text = ("CARRYING %s!"):format(string.upper(if species then species.Name else "KAIJU"))
				hint.Text = if (anchor:GetAttribute("Helper") or 0) ~= 0 then "Team heist! Stay close to your partner!" else "Run back to your island!"
			end
		end
		setBar(1 - (os.clock() - startedAt) / Economy.StealMaxCarryTime, true)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Q and (player:GetAttribute("Carrying") or "") ~= "" then
			Remote.Call("Drop")
		end
	end)
end

local function buildAlarm()
	alarm = Kit.new("Frame", {
		Name = "Alarm",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 1,
		Parent = layer,
	})
	-- vignette rouge sur les bords
	for _, side in {
		{ UDim2.new(1, 0, 0.18, 0), UDim2.new(), 90 },
		{ UDim2.new(1, 0, 0.18, 0), UDim2.new(0, 0, 0.82, 0), -90 },
		{ UDim2.new(0.14, 0, 1, 0), UDim2.new(), 0 },
		{ UDim2.new(0.14, 0, 1, 0), UDim2.new(0.86, 0, 0, 0), 180 },
	} do
		Kit.new("Frame", {
			Size = side[1],
			Position = side[2],
			BackgroundColor3 = C.Red,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = alarm,
		}, {
			Kit.new("UIGradient", {
				Rotation = side[3],
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			}),
		})
	end
	local label = Kit.Text({
		Name = "Label",
		Size = UDim2.fromOffset(760, 56),
		Position = UDim2.new(0.5, 0, 0, 126),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "🚨 THIEF IN YOUR BASE! 🚨",
		FontFace = F.Impact,
		TextColor3 = C.Red,
		Stroke = 4,
		ZIndex = 3,
		Parent = alarm,
	})
	Kit.AutoScale(label)
	Kit.Breathe(label, 0.08, 0.3)
end

local function startAlarm(args)
	alarmUntil = os.clock() + 20
	alarm.Visible = true
	local label = alarm:FindFirstChild("Label") :: TextLabel
	label.Text = ("🚨 %s IS STEALING YOUR %s! BONK THEM! 🚨"):format(string.upper(args.Thief or "SOMEONE"), string.upper(args.Species or "KAIJU"))
	if not alarmSound then
		alarmSound = Audio.Loop("alarm", { Volume = 0.7 })
	end
	CameraFx.Shake(0.4, 0.5)
	-- flèches rouges vers le voleur
	local target = nil
	for _, other in Players:GetPlayers() do
		if other.DisplayName == args.Thief and other.Character then
			target = other.Character:FindFirstChild("HumanoidRootPart")
		end
	end
	if target then
		Tutorial.PointThief(target)
	end
end

local function stopAlarm()
	alarmUntil = 0
	alarm.Visible = false
	if alarmSound then
		alarmSound:Destroy()
		alarmSound = nil
	end
	Tutorial.HideThief()
end

----------------------------------------------------------------------------

function Hud.Init()
	layer = Kit.Root()
	buildCurrencies()
	buildLevel()
	buildMenus()
	buildBottom()
	buildEventBanner()
	buildCarry()
	buildAlarm()

	FxBus.On("Collect", function(args)
		Audio.Play("cash_collect")
		Hud.FlyCoins("💵", 14)
		Hud.FloatText("+" .. Format.Cash(args.Amount or 0), C.Cash)
		CameraFx.FovPunch(-4, 0.4)
	end)
	FxBus.On("CashBurst", function(args)
		Audio.Play("purchase")
		Hud.FlyCoins("💰", 22)
		Hud.FloatText("+" .. Format.Cash(args.Amount or 0), C.Cash)
	end)
	FxBus.On("GemBurst", function(args)
		Audio.Play("reward_claim")
		Hud.FlyCoins("💎", 18)
		Hud.FloatText("+" .. Format.Short(args.Amount or 0) .. " 💎", C.Gem)
	end)
	FxBus.On("Sold", function(args)
		Audio.Play("sell")
		Hud.FlyCoins("💵", 8)
		Hud.FloatText("+" .. Format.Cash(args.Amount or 0), C.Cash)
	end)
	FxBus.On("OrbGrabbed", function(args)
		Hud.FloatText("+" .. Format.Cash(args.Amount or 0), C.Cash)
		Hud.FlyCoins("💵", 3)
	end)
	FxBus.On("HeistCut", function(args)
		Hud.FlyCoins("💰", 12)
		Hud.FloatText("+" .. Format.Cash(args.Amount or 0) .. " heist cut!", C.Gold)
	end)
	FxBus.On("Xp", function(args)
		floatXp(args.Amount or 0)
	end)
	FxBus.On("LevelUp", levelUp)
	FxBus.On("Alarm", startAlarm)
	FxBus.On("AlarmStop", stopAlarm)
	FxBus.On("Robbed", stopAlarm)
	FxBus.On("Upgraded", function()
		Audio.Play("level_jingle")
	end)
	FxBus.On("PotionUsed", function(args)
		Audio.Play("stage_up")
		UIRegistry.Toast(("%s potion active!"):format(args.Id or ""), "Good")
	end)

	RunService.Heartbeat:Connect(function()
		if alarmUntil > 0 and os.clock() > alarmUntil then
			stopAlarm()
		end
	end)
end

function Hud.Button(id: string): GuiObject?
	return menuButtons[id]
end

function Hud.LockButton(): GuiObject
	return lockButton
end

return Hud
