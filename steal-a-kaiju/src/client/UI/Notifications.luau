--!nonstrict
-- Toasts, fil d'annonces du serveur, grandes annonces centrales, popup de
-- probabilités (obligatoire pour le hasard payant) et « Welcome back ».

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Kit)
local Controllers = script.Parent.Parent.Controllers
local Audio = require(Controllers.Audio)
local Remote = require(Controllers.Remote)
local FxBus = require(Controllers.FxBus)
local UIRegistry = require(Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts

local Notifications = {}

local layer: ScreenGui
local toastHolder: Frame
local feedHolder: Frame
local announceHolder: Frame

local TOAST_STYLE = {
	Info = { Color = "Ink", Icon = "💬", Sound = "ui_tab" },
	Good = { Color = "Radioactive", Icon = "✅", Sound = "reward_claim" },
	Bad = { Color = "Red", Icon = "⛔", Sound = "ui_error" },
	Cash = { Color = "Radioactive", Icon = "💰", Sound = "cash_collect" },
	Gem = { Color = "Cyan", Icon = "💎", Sound = "reward_claim" },
	Rare = { Color = "Purple", Icon = "✨", Sound = "hatch_epic" },
}

----------------------------------------------------------------------------
-- Toasts (en bas à droite)
----------------------------------------------------------------------------

function Notifications.Toast(text: string, kind: string?)
	local style = TOAST_STYLE[kind or "Info"] or TOAST_STYLE.Info
	local order = -math.floor(os.clock() * 100)
	local holder = Kit.new("Frame", {
		Size = UDim2.fromOffset(360, 58),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = toastHolder,
	})
	local container, body = Kit.Panel({
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(1.2, 0),
		Rotation = math.random(-15, 15) / 10,
		Gradient = style.Color,
		ShadowOffset = 5,
		Parent = holder,
	})
	Kit.Text({
		Size = UDim2.new(0, 40, 1, -10),
		Position = UDim2.fromOffset(8, 5),
		Text = style.Icon,
		FontFace = F.Body,
		Stroke = false,
		Parent = body,
	})
	Kit.Text({
		Size = UDim2.new(1, -60, 1, -12),
		Position = UDim2.fromOffset(52, 6),
		Text = text,
		FontFace = F.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = body,
	})
	Kit.Tween(container, 0.4, { Position = UDim2.fromScale(0, 0) }, Enum.EasingStyle.Back)
	if kind ~= "Info" then
		Audio.Play(style.Sound, { Volume = 0.6, Cooldown = 0.15 })
	end
	task.delay(3.6, function()
		Kit.Tween(container, 0.3, { Position = UDim2.fromScale(1.3, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.3)
		holder:Destroy()
	end)
	-- limite le nombre de toasts
	local toasts = {}
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 5 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
end

----------------------------------------------------------------------------
-- Fil d'annonces (à gauche) + chat
----------------------------------------------------------------------------

local FEED_ICON = {
	Meteor = "☄️",
	Rare = "🌟",
	Heist = "🦹",
	Help = "🆘",
	Event = "⚡",
	Boss = "👹",
	Purchase = "🛒",
	Rebirth = "🧬",
	Info = "📣",
}

local function systemChat(text: string, color: Color3?)
	local ok, channels = pcall(function()
		return TextChatService:WaitForChild("TextChannels", 2)
	end)
	if not ok or not channels then
		return
	end
	local general = channels:FindFirstChild("RBXGeneral") :: TextChannel?
	if general then
		local hex = (color or C.Gold):ToHex()
		pcall(general.DisplaySystemMessage, general, ('<font color="#%s"><b>%s</b></font>'):format(hex, text))
	end
end

function Notifications.Feed(text: string, style: string?, color: Color3?)
	local icon = FEED_ICON[style or "Info"] or "📣"
	local accent = color or C.Magma
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.15,
		LayoutOrder = -math.floor(os.clock() * 100),
		Position = UDim2.fromScale(-1, 0),
		Parent = feedHolder,
	}, { Kit.Corner(10), Kit.Stroke(2.5, accent) })
	Kit.new("Frame", {
		Size = UDim2.new(0, 6, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = accent,
		Parent = row,
	}, { Kit.Round() })
	Kit.Text({
		Size = UDim2.new(1, -24, 1, -8),
		Position = UDim2.fromOffset(16, 4),
		Text = icon .. "  " .. text,
		FontFace = F.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Stroke = 1.5,
		Parent = row,
	})
	Kit.Pop(row, 0.6, 0.35)
	task.delay(8, function()
		Kit.Tween(row, 0.4, { BackgroundTransparency = 1 })
		for _, d in row:GetDescendants() do
			if d:IsA("TextLabel") then
				Kit.Tween(d, 0.4, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				Kit.Tween(d, 0.4, { Transparency = 1 })
			elseif d:IsA("Frame") then
				Kit.Tween(d, 0.4, { BackgroundTransparency = 1 })
			end
		end
		task.wait(0.45)
		row:Destroy()
	end)
	local rows = {}
	for _, child in feedHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(rows, child)
		end
	end
	if #rows > 5 then
		table.sort(rows, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		rows[1]:Destroy()
	end
	systemChat(text, accent)
end

----------------------------------------------------------------------------
-- Grande annonce centrale (style titre de film)
----------------------------------------------------------------------------

function Notifications.Announce(text: string, color: Color3?, subtitle: string?, sound: string?)
	for _, child in announceHolder:GetChildren() do
		child:Destroy()
	end
	local frame = Kit.new("Frame", {
		Size = UDim2.fromOffset(900, 150),
		Position = UDim2.fromScale(0.5, 0.26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = announceHolder,
	})
	Kit.AutoScale(frame)
	Kit.Hazard({ Size = UDim2.new(1.1, 0, 0, 16), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), Parent = frame })
	Kit.Hazard({ Size = UDim2.new(1.1, 0, 0, 16), Position = UDim2.new(0.5, 0, 1, -16), AnchorPoint = Vector2.new(0.5, 0), Parent = frame })
	local title = Kit.Text({
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.fromOffset(0, 18),
		Text = text,
		FontFace = F.Impact,
		TextColor3 = color or C.Gold,
		Stroke = 5,
		MaxTextSize = 84,
		Rotation = -2,
		Parent = frame,
	})
	if subtitle then
		Kit.Text({
			Size = UDim2.new(0.8, 0, 0, 28),
			Position = UDim2.new(0.5, 0, 0, 104),
			AnchorPoint = Vector2.new(0.5, 0),
			Text = subtitle,
			FontFace = F.Body,
			MaxTextSize = 26,
			Parent = frame,
		})
	end
	Kit.Pop(title, 2.2, 0.45)
	Kit.Shake(frame, 8, 0.4)
	if sound then
		Audio.Play(sound)
	end
	task.delay(3.4, function()
		if frame.Parent then
			Kit.Tween(Kit.ScaleOf(title), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.3)
			frame:Destroy()
		end
	end)
end

----------------------------------------------------------------------------
-- Popup des probabilités
----------------------------------------------------------------------------

local oddsWindow

function Notifications.ShowOdds(title: string, rows: { { Label: string, Chance: number, Color: Color3? } })
	if not oddsWindow then
		oddsWindow = Kit.Window({ Name = "Odds", Title = "ODDS", Icon = "🎲", Color = "Cyan", Size = UDim2.fromOffset(520, 460), RibbonWidth = 240 })
	end
	local content = oddsWindow.Frame
	for _, child in content:GetChildren() do
		child:Destroy()
	end
	Kit.Text({ Size = UDim2.new(1, 0, 0, 36), Text = title, TextColor3 = C.Ink, Stroke = false, FontFace = F.Title, Parent = content })
	local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 44), Parent = content })
	Kit.List(Enum.FillDirection.Vertical, 6).Parent = list
	for i, row in rows do
		local line = Kit.new("Frame", {
			Size = UDim2.new(1, -16, 0, 36),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = if i % 2 == 0 then 0.9 else 0.8,
			LayoutOrder = i,
			Parent = list,
		}, { Kit.Corner(8) })
		Kit.Text({
			Size = UDim2.new(0.68, 0, 1, -8),
			Position = UDim2.fromOffset(10, 4),
			Text = row.Label,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = row.Color or C.Ink,
			FontFace = F.Body,
			Stroke = if row.Color then 1.5 else false,
			Parent = line,
		})
		Kit.Text({
			Size = UDim2.new(0.3, -10, 1, -8),
			Position = UDim2.new(0.7, 0, 0, 4),
			Text = Format.Percent(row.Chance),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.Ink,
			FontFace = F.Title,
			Stroke = false,
			Parent = line,
		})
	end
	oddsWindow:Open()
end

----------------------------------------------------------------------------
-- Bon retour (gains hors ligne)
----------------------------------------------------------------------------

local function welcomeBack(args)
	local window = Kit.Window({ Name = "WelcomeBack", Title = "WELCOME BACK!", Icon = "🌙", Color = "Purple", Size = UDim2.fromOffset(560, 380), RibbonWidth = 380 })
	local content = window.Frame
	Kit.Starburst({ Size = UDim2.fromOffset(420, 420), Position = UDim2.fromScale(0.5, 0.4), Color = C.Gold, Parent = content })
	Kit.Text({
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 10),
		Text = ("Your kaijus worked for %s while you were away"):format(Format.Duration(args.Seconds or 0)),
		TextColor3 = C.Ink,
		FontFace = F.Body,
		Stroke = false,
		ZIndex = 6,
		Parent = content,
	})
	local amount = Kit.Text({
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.fromOffset(0, 70),
		Text = "$0",
		FontFace = F.Impact,
		TextColor3 = C.Cash,
		Stroke = 5,
		MaxTextSize = 90,
		ZIndex = 6,
		Parent = content,
	})
	if args.Capped then
		Kit.Text({
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 168),
			Text = ("(capped at %dh — get Night Shift for 8h!)"):format(args.MaxHours or 3),
			TextColor3 = C.InkSoft,
			FontFace = F.Body,
			Stroke = false,
			ZIndex = 6,
			Parent = content,
		})
	end
	Kit.Text({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 200),
		Text = "It's waiting in your Cash Reactor — step on the pad!",
		TextColor3 = C.Ink,
		FontFace = F.Body,
		Stroke = false,
		ZIndex = 6,
		Parent = content,
	})
	local ok = Kit.Button({
		Text = "AWESOME!",
		Color = "Radioactive",
		Size = UDim2.fromOffset(240, 62),
		Position = UDim2.new(0.5, 0, 1, -76),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 8,
		OnClick = function()
			window:Close()
		end,
		Parent = content,
	})
	Kit.Breathe(ok)
	window:Open()
	task.delay(0.4, function()
		Kit.CountTo(amount, args.Amount or 0, Format.Cash, 1.6)
		Audio.Play("cash_collect")
	end)
end

function Notifications.Init()
	layer = Kit.Layer("Notifications", 40)
	toastHolder = Kit.new("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(380, 420),
		Position = UDim2.new(1, -20, 1, -110),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom) })
	Kit.AutoScale(toastHolder)
	feedHolder = Kit.new("Frame", {
		Name = "Feed",
		Size = UDim2.fromOffset(480, 250),
		Position = UDim2.new(0, 20, 0, 150),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top) })
	Kit.AutoScale(feedHolder)
	announceHolder = Kit.new("Frame", {
		Name = "Announce",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = layer,
	})

	UIRegistry.Toast = Notifications.Toast
	UIRegistry.Announce = Notifications.Announce
	UIRegistry.ShowOdds = Notifications.ShowOdds
	Remote.OnError = function(msg)
		Notifications.Toast(msg, "Bad")
	end

	Net.Event("Notify").OnClientEvent:Connect(function(text, kind)
		Notifications.Toast(text, kind)
	end)
	Net.Event("Feed").OnClientEvent:Connect(function(text, style, color)
		Notifications.Feed(text, style, color)
	end)
	FxBus.On("WelcomeBack", welcomeBack)
end

return Notifications
