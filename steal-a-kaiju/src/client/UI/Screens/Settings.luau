--!nonstrict
-- Réglages : barres de volume (musique, effets sonores), effets réduits,
-- saisie de codes, récompense de groupe, crédits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared.Config.Rewards)
local Theme = require(Shared.Config.Theme)

local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)
local Remote = require(script.Parent.Parent.Parent.Controllers.Remote)
local Audio = require(script.Parent.Parent.Parent.Controllers.Audio)
local UIRegistry = require(script.Parent.Parent.Parent.Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts

local Settings = {}

local VERSION = "v1.0"
local TOGGLES = {
	{ Key = "Music", Volume = "MusicVolume", Icon = "🎵", Title = "MUSIC", Sub = "Soundtrack" },
	{ Key = "Sfx", Volume = "SfxVolume", Icon = "🔊", Title = "SOUNDS", Sub = "Stomps & cha-chings" },
	{ Key = "LowFx", Icon = "⚡", Title = "LOW EFFECTS", Sub = "Fewer particles for slower devices" },
}
local VOLUME_STEPS = 5 -- 0 %, 20 %, … 100 %

local window
local rows: { any } = {}
local toggles: { [string]: any } = {}
local volumes: { [string]: any } = {}
local codeBox: Frame
local codeStroke: UIStroke
local codeInput: TextBox
local redeemButton: TextButton
local groupSlot: Frame
local groupButton: TextButton
local groupChip: Frame
local groupPanel: Frame
local busy: { [string]: any } = {}

----------------------------------------------------------------------------
-- Interrupteur animé
----------------------------------------------------------------------------

local function makeToggle(parent: Instance, onFlip: (boolean) -> ()): any
	local holder = Kit.new("Frame", {
		Name = "Toggle",
		Size = UDim2.fromOffset(104, 48),
		Position = UDim2.new(1, -66, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = parent,
	})
	Kit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(3, 4),
		BackgroundColor3 = C.Ink,
		ZIndex = 5,
		Parent = holder,
	}, { Kit.Round() })
	local track = Kit.new("TextButton", {
		Name = "Track",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 6,
		Parent = holder,
	}, { Kit.Round(), Kit.Stroke(3) })
	local gradient = Kit.Gradient("Grey")
	gradient.Parent = track
	local label = Kit.Text({
		Size = UDim2.new(0.5, -6, 0.6, 0),
		Position = UDim2.new(0.25, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "ON",
		Stroke = 2,
		MaxTextSize = 20,
		ZIndex = 7,
		Parent = track,
	})
	local knob = Kit.new("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.new(0, 24, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 8,
		Parent = track,
	}, { Kit.Round(), Kit.Stroke(3), Kit.Gradient("Paper") })
	-- petit reflet sur le bouton rond
	Kit.new("Frame", {
		Size = UDim2.fromScale(0.4, 0.25),
		Position = UDim2.fromScale(0.28, 0.18),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.2,
		ZIndex = 9,
		Parent = knob,
	}, { Kit.Round() })

	local t = { Holder = holder, Track = track, Knob = knob, Value = nil :: boolean? }
	function t.Set(on: boolean, instant: boolean?)
		if t.Value == on then
			return
		end
		t.Value = on
		local colors = if on then Theme.Gradients.Radioactive else Theme.Gradients.Grey
		gradient.Color = ColorSequence.new(colors[1], colors[2])
		label.Text = if on then "ON" else "OFF"
		label.Position = UDim2.new(if on then 0.3 else 0.7, 0, 0.5, 0)
		local target = UDim2.new(if on then 1 else 0, if on then -24 else 24, 0.5, 0)
		if instant then
			knob.Position = target
			knob.Size = UDim2.fromOffset(38, 38)
			return
		end
		-- écrasement élastique pendant la glissade
		knob.Size = UDim2.fromOffset(50, 32)
		Kit.Tween(knob, 0.32, { Position = target }, Enum.EasingStyle.Back)
		Kit.Tween(knob, 0.4, { Size = UDim2.fromOffset(38, 38) }, Enum.EasingStyle.Elastic)
		Kit.Punch(label, 0.3)
	end
	track.Activated:Connect(function()
		Audio.Play("ui_click")
		onFlip(not t.Value)
	end)
	track.MouseEnter:Connect(function()
		Kit.Tween(Kit.ScaleOf(holder), 0.2, { Scale = 1.06 }, Enum.EasingStyle.Back)
	end)
	track.MouseLeave:Connect(function()
		Kit.Tween(Kit.ScaleOf(holder), 0.2, { Scale = 1 })
	end)
	return t
end

----------------------------------------------------------------------------
-- Barre de volume : un bouton muet + 5 barres de plus en plus hautes
----------------------------------------------------------------------------

local function makeVolume(parent: Instance, onSet: (number) -> ()): any
	local holder = Kit.new("Frame", {
		Name = "Volume",
		Size = UDim2.fromOffset(270, 48),
		Position = UDim2.new(1, -148, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = parent,
	})
	local mute = Kit.Button({
		Name = "Mute",
		Text = "",
		Icon = "🔇",
		IconSize = 26,
		Color = "Grey",
		Size = UDim2.fromOffset(46, 44),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 6,
		Parent = holder,
		OnClick = function()
			onSet(0)
		end,
	})
	local bars = {}
	for i = 1, VOLUME_STEPS do
		local h = 14 + i * 6
		local bar = Kit.new("TextButton", {
			Name = "Step" .. i,
			Size = UDim2.fromOffset(26, h),
			Position = UDim2.new(0, 58 + (i - 1) * 32, 1, -4),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = C.PaperDark,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 6,
			Parent = holder,
		}, { Kit.Corner(6), Kit.Stroke(2.5) })
		bar.Activated:Connect(function()
			onSet(i / VOLUME_STEPS)
		end)
		bars[i] = bar
	end
	local pct = Kit.Text({
		Name = "Percent",
		Size = UDim2.fromOffset(52, 30),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "60%",
		FontFace = F.Title,
		MaxTextSize = 22,
		Stroke = 2,
		ZIndex = 6,
		Parent = holder,
	})
	local v = { Holder = holder, Value = nil :: number? }
	function v.Set(value: number)
		v.Value = value
		local level = math.floor(value * VOLUME_STEPS + 0.5)
		for i, bar in bars do
			bar.BackgroundColor3 = if i <= level then C.Radioactive:Lerp(C.Gold, (i - 1) / VOLUME_STEPS) else C.PaperDark
		end
		Kit.SetButtonColor(mute, if level == 0 then "Red" else "Grey")
		pct.Text = if level == 0 then "OFF" else ("%d%%"):format(level * 100 // VOLUME_STEPS)
	end
	return v
end

----------------------------------------------------------------------------
-- Rangées
----------------------------------------------------------------------------

local function panelRow(parent: Instance, y: number, h: number, rotation: number, gradient: string?): (Frame, Frame)
	local holder = Kit.new("Frame", {
		Size = UDim2.new(1, -8, 0, h),
		Position = UDim2.new(0.5, 0, 0, y + h / 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local _, body = Kit.Panel({
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.new(0.5, -3, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = rotation,
		Gradient = gradient,
		Parent = holder,
	})
	table.insert(rows, holder)
	return holder, body
end

local function iconBadge(parent: Instance, icon: string, colorName: string, size: number)
	local badge = Kit.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.White,
		ZIndex = 3,
		Parent = parent,
	}, { Kit.Round(), Kit.Stroke(3), Kit.Gradient(colorName) })
	Kit.Text({
		Size = UDim2.fromScale(0.66, 0.66),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = icon,
		FontFace = F.Body,
		Stroke = false,
		MaxTextSize = 34,
		ZIndex = 4,
		Parent = badge,
	})
end

local function titleAndSub(parent: Instance, title: string, sub: string, x: number, reserve: number?)
	local right = reserve or 140
	Kit.Text({
		Size = UDim2.new(1, -(x + right), 0, 26),
		Position = UDim2.new(0, x, 0.5, -2),
		AnchorPoint = Vector2.new(0, 1),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 2.5,
		MaxTextSize = 24,
		ZIndex = 3,
		Parent = parent,
	})
	Kit.Text({
		Size = UDim2.new(1, -(x + right), 0, 20),
		Position = UDim2.new(0, x, 0.5, 2),
		Text = sub,
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = false,
		MaxTextSize = 17,
		ZIndex = 3,
		Parent = parent,
	})
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

local function currentSettings(): any
	return State.Get("Settings") or { Music = true, Sfx = true, LowFx = false, MusicVolume = 0.6, SfxVolume = 0.6 }
end

-- Volume effectif d'un réglage (l'ancien interrupteur OFF vaut 0).
local function volumeOf(settings: any, def: any): number
	if settings[def.Key] == false then
		return 0
	end
	return settings[def.Volume] or 0.6
end

local function setVolume(def: any, value: number)
	local v = volumes[def.Key]
	v.Set(value)
	if def.Key == "Sfx" then
		Audio.Play("ui_click", { Cooldown = 0 })
	end
	task.spawn(function()
		local r = Remote.Call("Settings", { [def.Volume] = value, [def.Key] = value > 0 })
		if not r.ok then
			v.Set(volumeOf(currentSettings(), def))
		end
	end)
end

local function flip(key: string, value: boolean)
	local t = toggles[key]
	if busy[key] then
		return
	end
	busy[key] = true
	t.Set(value)
	local r = Remote.Call("Settings", { [key] = value })
	busy[key] = nil
	if not r.ok then
		t.Set(currentSettings()[key] == true)
	end
end

local function flashStroke(color: Color3)
	codeStroke.Color = color
	codeStroke.Thickness = 6
	Kit.Tween(codeStroke, 0.6, { Thickness = 4, Color = C.Ink })
end

local function redeem()
	if busy.code then
		return
	end
	local code = string.gsub(codeInput.Text, "%s", "")
	if code == "" then
		Audio.Play("ui_error")
		Kit.Shake(codeBox, 6, 0.3)
		flashStroke(C.Red)
		return
	end
	busy.code = true
	Kit.SetDisabled(redeemButton, true)
	local r = Remote.Call("Redeem", { Code = code })
	busy.code = nil
	Kit.SetDisabled(redeemButton, false)
	if r.ok then
		Audio.Play("reward_claim")
		UIRegistry.Toast("Code redeemed: " .. tostring(r.text or ""), "Good")
		codeInput.Text = ""
		flashStroke(C.RadioactiveDark)
		Kit.Punch(codeBox, 0.12)
		-- éclat de rayons derrière la zone de saisie
		local burst = Kit.Starburst({ Size = UDim2.fromOffset(300, 300), Position = UDim2.fromScale(0.5, 0.5), Color = C.Gold, Transparency = 0.3, ZIndex = 0, Parent = codeBox })
		Kit.Pop(burst, 0.2, 0.4)
		task.delay(0.5, function()
			for _, ray in burst:GetChildren() do
				if ray:IsA("Frame") then
					Kit.Tween(ray, 0.4, { BackgroundTransparency = 1 })
				end
			end
		end)
		task.delay(1, function()
			burst:Destroy()
		end)
	else
		Kit.Shake(codeBox, 7, 0.35)
		flashStroke(C.Red)
	end
end

local function refreshGroup()
	local claimed = State.Get("GroupClaimed") == true
	local soon = Rewards.GroupId == 0
	groupChip.Visible = claimed
	groupSlot.Visible = not claimed
	Kit.SetDisabled(groupButton, false)
	if soon then
		Kit.SetButtonText(groupButton, "COMING SOON")
		Kit.SetButtonColor(groupButton, "Grey")
		Kit.SetDisabled(groupButton, true)
	else
		Kit.SetButtonText(groupButton, "CLAIM")
		Kit.SetButtonColor(groupButton, "Radioactive")
	end
end

local function claimGroup()
	if busy.group or Rewards.GroupId == 0 or State.Get("GroupClaimed") == true then
		return
	end
	busy.group = true
	local r = Remote.Call("ClaimGroup")
	busy.group = nil
	if r.ok then
		Audio.Play("reward_claim")
		UIRegistry.Toast("Group reward: " .. tostring(r.text or ""), "Good")
		Kit.Punch(groupPanel, 0.1)
	end
	refreshGroup()
	if r.ok then
		Kit.Pop(groupChip, 0.3, 0.5)
	end
end

----------------------------------------------------------------------------
-- Interface publique
----------------------------------------------------------------------------

function Settings.Init()
	window = Kit.Window({ Name = "Settings", Title = "SETTINGS", Icon = "⚙️", Color = "Cyan", Size = UDim2.fromOffset(660, 560), RibbonWidth = 320 })
	local content = window.Frame

	-- Interrupteurs
	for i, def in TOGGLES do
		local _, body = panelRow(content, (i - 1) * 70, 66, if i % 2 == 0 then 0.6 else -0.6)
		iconBadge(body, def.Icon, if def.Key == "LowFx" then "Gold" else "Cyan", 44)
		if def.Volume then
			titleAndSub(body, def.Title, def.Sub, 68, 300)
			volumes[def.Key] = makeVolume(body, function(value)
				setVolume(def, value)
			end)
		else
			titleAndSub(body, def.Title, def.Sub, 68)
			toggles[def.Key] = makeToggle(body, function(value)
				task.spawn(flip, def.Key, value)
			end)
		end
	end

	-- Codes
	local _, codes = panelRow(content, 214, 100, -0.8, "Pink")
	Kit.Text({
		Size = UDim2.new(0.6, 0, 0, 28),
		Position = UDim2.fromOffset(14, 8),
		Text = "🎟️ CODES",
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = 2.5,
		MaxTextSize = 26,
		ZIndex = 3,
		Parent = codes,
	})
	Kit.Text({
		Size = UDim2.new(0.5, 0, 0, 20),
		Position = UDim2.new(1, -14, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Text = "Follow us for new codes!",
		FontFace = F.Body,
		TextXAlignment = Enum.TextXAlignment.Right,
		Stroke = 1.5,
		MaxTextSize = 16,
		ZIndex = 3,
		Parent = codes,
	})
	codeBox = Kit.new("Frame", {
		Name = "CodeBox",
		Size = UDim2.new(1, -196, 0, 48),
		Position = UDim2.new(0, 14, 1, -58),
		BackgroundColor3 = C.White,
		ZIndex = 3,
		Parent = codes,
	}, { Kit.Corner(12), Kit.Gradient("Paper") })
	codeStroke = Kit.Stroke(4)
	codeStroke.Parent = codeBox
	codeInput = Kit.new("TextBox", {
		Name = "Input",
		Size = UDim2.new(1, -24, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = F.Title,
		Text = "",
		PlaceholderText = "ENTER CODE...",
		PlaceholderColor3 = Color3.fromRGB(170, 150, 170),
		TextColor3 = C.Ink,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ZIndex = 4,
		Parent = codeBox,
	})
	codeInput.Focused:Connect(function()
		Kit.Tween(codeStroke, 0.2, { Color = C.Cyan:Lerp(C.Ink, 0.3), Thickness = 5 })
	end)
	codeInput.FocusLost:Connect(function(enter)
		Kit.Tween(codeStroke, 0.2, { Color = C.Ink, Thickness = 4 })
		if enter then
			task.spawn(redeem)
		end
	end)
	local redeemSlot = Kit.new("Frame", {
		Size = UDim2.fromOffset(164, 58),
		Position = UDim2.new(1, -96, 1, -34),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = codes,
	})
	redeemButton = Kit.Button({
		Name = "Redeem",
		Text = "REDEEM",
		Color = "Gold",
		Size = UDim2.new(1, 0, 1, -6),
		Position = UDim2.new(0.5, 0, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 26,
		OnClick = function()
			redeem()
		end,
		Parent = redeemSlot,
	})

	-- Groupe
	local groupHolder, group = panelRow(content, 322, 76, 0.6, "Purple")
	groupPanel = groupHolder
	iconBadge(group, "👥", "Gold", 50)
	titleAndSub(group, "JOIN THE GROUP", "Members get 💎 100 + a Cash Potion", 74)
	local slot = Kit.new("Frame", {
		Size = UDim2.fromOffset(170, 54),
		Position = UDim2.new(1, -98, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = group,
	})
	groupSlot = slot
	groupButton = Kit.Button({
		Name = "Group",
		Text = "CLAIM",
		Color = "Radioactive",
		Size = UDim2.new(1, 0, 1, -6),
		Position = UDim2.new(0.5, 0, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 22,
		OnClick = function()
			claimGroup()
		end,
		Parent = slot,
	})
	groupChip = Kit.Chip({
		Text = "CLAIMED ✓",
		Color = C.RadioactiveDark,
		Size = UDim2.fromOffset(150, 36),
		Position = UDim2.new(1, -98, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 5,
		Parent = group,
	})
	groupChip.Rotation = -4

	-- Crédits
	Kit.Text({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "STEAL A KAIJU · " .. VERSION .. " · Made with 💚 and way too many meteors",
		FontFace = F.Body,
		TextColor3 = C.InkSoft,
		Stroke = false,
		MaxTextSize = 15,
		Parent = content,
	})

	State.Observe("Settings", function(s)
		if type(s) ~= "table" then
			return
		end
		for key, t in toggles do
			if not busy[key] then
				t.Set(s[key] == true, not window.IsOpen)
			end
		end
		for _, def in TOGGLES do
			if def.Volume then
				volumes[def.Key].Set(volumeOf(s, def))
			end
		end
	end)
	State.Changed("GroupClaimed"):Connect(refreshGroup)
	for key, t in toggles do
		t.Set(currentSettings()[key] == true, true)
	end
	for _, def in TOGGLES do
		if def.Volume then
			volumes[def.Key].Set(volumeOf(currentSettings(), def))
		end
	end
	refreshGroup()
end

function Settings.Open(_args: any?)
	refreshGroup()
	window:Open()
	for i, holder in rows do
		local s = Kit.ScaleOf(holder)
		s.Scale = 0
		task.delay(0.04 + i * 0.06, function()
			Kit.Pop(holder, 0.3, 0.45)
		end)
	end
end

function Settings.Close()
	window:Close()
end

return Settings
