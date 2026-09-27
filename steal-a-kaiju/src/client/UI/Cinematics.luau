--!nonstrict
-- Cinématiques plein écran : révélation d'éclosion (dramaturgie selon la
-- rareté), casse réussie, vol subi, évolution, pass débloqué, récompenses,
-- découvertes du Kaijudex. Une file d'attente évite les chevauchements.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Growth = require(Shared.Config.Growth)
local Format = require(Shared.Logic.Format)

local Kit = require(script.Parent.Kit)
local Viewport = require(script.Parent.Viewport)
local Controllers = script.Parent.Parent.Controllers
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local CameraFx = require(Controllers.CameraFx)
local UIRegistry = require(Controllers.UIRegistry)

local C = Kit.Colors
local F = Kit.Fonts

local Cinematics = {}

local layer: ScreenGui
local smallLayer: ScreenGui
local queue: { () -> () } = {}
local running = false

local function enqueue(fn: () -> ())
	table.insert(queue, fn)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local job = table.remove(queue, 1)
			local ok, err = pcall(job)
			if not ok then
				warn("[Cinematics] " .. tostring(err))
			end
		end
		running = false
	end)
end

-- Scène vide plein écran ; renvoie le cadre, le fond et une fonction de fermeture.
local function stage(backdropColor: Color3?): (Frame, Frame, (number?) -> ())
	layer.Enabled = true
	local root = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = layer })
	local backdrop = Kit.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = backdropColor or C.Ink,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = root,
	})
	Kit.Tween(backdrop, 0.3, { BackgroundTransparency = 0.12 })
	local center = Kit.new("Frame", {
		Size = UDim2.fromOffset(1000, 640),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Kit.AutoScale(center)
	local closed = false
	local function close(delay: number?)
		if closed then
			return
		end
		closed = true
		task.wait(delay or 0)
		Kit.Tween(backdrop, 0.3, { BackgroundTransparency = 1 })
		Kit.Tween(Kit.ScaleOf(center), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.32)
		root:Destroy()
		if #layer:GetChildren() == 0 then
			layer.Enabled = false
		end
	end
	return center, backdrop, close
end

local function flash(color: Color3?, duration: number?)
	local f = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color or C.White,
		BackgroundTransparency = 0,
		ZIndex = 100,
		Parent = layer,
	})
	Kit.Tween(f, duration or 0.6, { BackgroundTransparency = 1 })
	task.delay((duration or 0.6) + 0.05, function()
		f:Destroy()
	end)
end

local function slamText(parent: Instance, props): TextLabel
	local label = Kit.Text({
		Size = props.Size or UDim2.fromOffset(900, 110),
		Position = props.Position or UDim2.fromScale(0.5, 0.78),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = props.Text,
		FontFace = props.Font or F.Impact,
		TextColor3 = props.Color or C.White,
		Stroke = props.Stroke or 6,
		MaxTextSize = props.MaxTextSize or 110,
		Rotation = props.Rotation or -3,
		ZIndex = props.ZIndex or 20,
		Parent = parent,
	})
	Kit.Pop(label, props.From or 3, 0.4)
	return label
end

-- Texte arc-en-ciel animé.
local function rainbow(label: TextLabel)
	local g = Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 120)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 180, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
		}),
		Parent = label,
	})
	label.TextColor3 = C.White
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not label.Parent then
			conn:Disconnect()
			return
		end
		g.Offset = Vector2.new(math.sin(os.clock() * 2) * 0.5, 0)
	end)
end

----------------------------------------------------------------------------
-- Éclosion
----------------------------------------------------------------------------

local HATCH_SOUND = { Common = "hatch_common", Rare = "hatch_common", Epic = "hatch_epic", Legendary = "hatch_legendary", Mythic = "hatch_legendary", Celestial = "hatch_secret", Secret = "hatch_secret" }

local function hatchReveal(args)
	local species = Kaijus.Get(args.Species or "")
	if not species then
		return
	end
	local rarity = Rarities.Get(args.Rarity or species.Rarity)
	local mutation = Mutations.Get(args.Mutation)
	local order = rarity.Order
	local center, backdrop, close = stage()

	local burst = Kit.Starburst({
		Size = UDim2.fromOffset(700 + order * 90, 700 + order * 90),
		Position = UDim2.fromScale(0.5, 0.42),
		Color = rarity.Color,
		Rays = 10 + order * 3,
		Transparency = 0.7,
		Period = 14 - order,
		Parent = center,
	})
	burst.Visible = false

	-- L'œuf tremble de plus en plus
	local eggVp = Viewport.new({ Egg = rarity.Id, Size = UDim2.fromOffset(340, 340), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), Spin = false, ZIndex = 10, Parent = center })
	eggVp.Angle = 0.4
	eggVp:_update()
	Kit.Pop(eggVp.Frame, 0.2, 0.5)
	local wobbles = 3 + math.min(order, 4)
	for i = 1, wobbles do
		local amp = 6 + i * 3
		Audio.Play("egg_wobble", { Pitch = 1 + i * 0.05 })
		Kit.Tween(eggVp.Frame, 0.09, { Rotation = amp }, Enum.EasingStyle.Sine)
		task.wait(0.09)
		Kit.Tween(eggVp.Frame, 0.12, { Rotation = -amp }, Enum.EasingStyle.Sine)
		task.wait(0.12)
		Kit.Tween(eggVp.Frame, 0.09, { Rotation = 0 }, Enum.EasingStyle.Sine)
		task.wait(math.max(0.12, 0.45 - i * 0.06))
	end
	if order >= 4 then
		-- Suspense : le fond vire à la couleur de la rareté
		Kit.Tween(backdrop, 0.6, { BackgroundColor3 = rarity.Color:Lerp(C.Ink, 0.82) })
		Audio.Play("meteor_rare_alarm")
		task.wait(0.7)
	end

	Audio.Play("egg_crack")
	Audio.Play(HATCH_SOUND[rarity.Id] or "hatch_common")
	flash(rarity.Glow, 0.7)
	CameraFx.Shake(0.3 + order * 0.25, 0.6)
	eggVp:Destroy()
	burst.Visible = true
	Kit.Pop(burst, 0.2, 0.6)

	local vp = Viewport.new({ Species = species.Id, Mutation = args.Mutation, Size = UDim2.fromOffset(420, 420), Position = UDim2.fromScale(0.5, 0.4), AnchorPoint = Vector2.new(0.5, 0.5), Speed = 1.2, ZIndex = 10, Parent = center })
	Kit.Pop(vp.Frame, 0.1, 0.6)

	local title = slamText(center, { Text = string.upper(species.Name), Color = rarity.Color, Position = UDim2.fromScale(0.5, 0.78) })
	if rarity.Id == "Secret" then
		title.TextColor3 = C.White
		rainbow(title)
	end
	Kit.Shake(title, 10, 0.4)
	local chips = Kit.new("Frame", {
		Size = UDim2.fromOffset(700, 40),
		Position = UDim2.fromScale(0.5, 0.9),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = center,
	}, { Kit.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local rChip = Kit.Chip({ Text = string.upper(rarity.Name), Color = rarity.Color, AutoWidth = true, Size = UDim2.fromOffset(0, 38), TextSize = 26, LayoutOrder = 1, ZIndex = 21, Parent = chips })
	Kit.Pop(rChip, 0.2)
	if mutation then
		task.wait(0.35)
		local mChip = Kit.Chip({ Text = ("%s  x%d"):format(string.upper(mutation.Name), mutation.Mult), Color = mutation.Color, AutoWidth = true, Size = UDim2.fromOffset(0, 38), TextSize = 26, LayoutOrder = 2, ZIndex = 21, Parent = chips })
		if mutation.Id == "Rainbow" then
			rainbow(mChip:FindFirstChild("Text") :: TextLabel)
		end
		Kit.Pop(mChip, 2.5, 0.4)
		Audio.Play("stage_up")
		CameraFx.Shake(0.4, 0.3)
	end
	local income = species.Income * (if mutation then mutation.Mult else 1)
	local incomeChip = Kit.Chip({ Text = ("+%s/s"):format(Format.Cash(income)), Color = C.RadioactiveDark, AutoWidth = true, Size = UDim2.fromOffset(0, 38), TextSize = 26, LayoutOrder = 3, ZIndex = 21, Parent = chips })
	Kit.Pop(incomeChip, 0.2)
	Kit.Text({
		Size = UDim2.fromOffset(600, 26),
		Position = UDim2.fromScale(0.5, 0.97),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = '"' .. species.Flavor .. '"',
		FontFace = F.Body,
		TextColor3 = C.Paper,
		Stroke = 2,
		ZIndex = 20,
		Parent = center,
	})

	local done = false
	backdrop.Activated:Connect(function()
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 2.6 + order * 0.35 do
		task.wait(0.05)
	end
	close()
end

----------------------------------------------------------------------------
-- Casse / vol
----------------------------------------------------------------------------

local function heistSuccess(args)
	local species = Kaijus.Get(args.Species or "")
	local center, _backdrop, close = stage()
	Kit.Starburst({ Size = UDim2.fromOffset(900, 900), Position = UDim2.fromScale(0.5, 0.45), Color = C.Gold, Parent = center })
	Kit.Hazard({ Size = UDim2.new(1.2, 0, 0, 22), Position = UDim2.fromScale(0.5, 0.08), AnchorPoint = Vector2.new(0.5, 0.5), Parent = center }).Rotation = -3
	Kit.Hazard({ Size = UDim2.new(1.2, 0, 0, 22), Position = UDim2.fromScale(0.5, 0.98), AnchorPoint = Vector2.new(0.5, 0.5), Parent = center }).Rotation = 2
	if species then
		local vp = Viewport.new({ Species = species.Id, Mutation = args.Mutation, Size = UDim2.fromOffset(360, 360), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), Speed = 1.4, ZIndex = 10, Parent = center })
		Kit.Pop(vp.Frame, 0.2, 0.5)
	end
	Audio.Play("heist_success")
	slamText(center, { Text = "HEIST COMPLETE!", Color = C.Gold, Position = UDim2.fromScale(0.5, 0.16), Rotation = -4 })
	local stage_ = Growth.Get(args.Stage or 1)
	slamText(center, {
		Text = ("You stole a %s %s!"):format(stage_.Name, if species then species.Name else "kaiju"),
		Font = F.Title,
		Color = C.White,
		Size = UDim2.fromOffset(800, 50),
		Position = UDim2.fromScale(0.5, 0.82),
		Stroke = 3,
		MaxTextSize = 44,
		Rotation = 1,
		From = 0.4,
	})
	CameraFx.Shake(0.8, 0.5)
	task.wait(3)
	close()
end

local function robbed(args)
	local species = Kaijus.Get(args.Species or "")
	local center, _backdrop, close = stage(C.Red:Lerp(C.Ink, 0.5))
	slamText(center, { Text = "YOU GOT ROBBED!", Color = C.Red, Position = UDim2.fromScale(0.5, 0.35), Rotation = 3 })
	slamText(center, {
		Text = ("%s stole your %s 😤"):format(args.Thief or "Someone", if species then species.Name else "kaiju"),
		Font = F.Title,
		Size = UDim2.fromOffset(800, 50),
		Position = UDim2.fromScale(0.5, 0.52),
		Stroke = 3,
		MaxTextSize = 44,
		Rotation = -1,
		From = 0.4,
	})
	slamText(center, {
		Text = "Lock your base 🛡️ — or steal it back!",
		Font = F.Body,
		Size = UDim2.fromOffset(700, 36),
		Position = UDim2.fromScale(0.5, 0.64),
		Stroke = 2,
		MaxTextSize = 30,
		Rotation = 0,
		From = 0.6,
	})
	Audio.Play("ui_error")
	Audio.Play("roar_small")
	CameraFx.Shake(1, 0.6)
	task.wait(2.6)
	close()
end

----------------------------------------------------------------------------
-- Évolution, pass, récompenses
----------------------------------------------------------------------------

local function rebirthCinematic(args)
	local center, _backdrop, close = stage(C.RadioactiveDark:Lerp(C.Ink, 0.6))
	Kit.Starburst({ Size = UDim2.fromOffset(1100, 1100), Position = UDim2.fromScale(0.5, 0.45), Color = C.Radioactive, Rays = 22, Period = 6, Parent = center })
	Audio.Play("rebirth")
	flash(C.Radioactive, 1)
	CameraFx.Shake(1.2, 1)
	local dna = Kit.Text({ Size = UDim2.fromOffset(220, 220), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), Text = "🧬", FontFace = F.Body, Stroke = false, ZIndex = 12, Parent = center })
	Kit.Pop(dna, 0.1, 0.8)
	Kit.Tween(dna, 3, { Rotation = 360 }, Enum.EasingStyle.Quad)
	slamText(center, { Text = "EVOLVED!", Color = C.Radioactive, Position = UDim2.fromScale(0.5, 0.66) })
	slamText(center, { Text = ("LEVEL %d"):format(args.Level or 1), Color = C.Gold, Size = UDim2.fromOffset(600, 70), Position = UDim2.fromScale(0.5, 0.8), MaxTextSize = 70, Rotation = 2, From = 0.3 })
	task.wait(3.2)
	close()
end

local function passUnlocked(args)
	local center, _backdrop, close = stage()
	Kit.Starburst({ Size = UDim2.fromOffset(900, 900), Position = UDim2.fromScale(0.5, 0.45), Color = C.Gold, Parent = center })
	Audio.Play("hatch_legendary")
	flash(C.Gold, 0.6)
	slamText(center, { Text = string.upper(args.Name or "PASS") .. " UNLOCKED!", Color = C.Gold, Position = UDim2.fromScale(0.5, 0.45) })
	slamText(center, { Text = "Thank you for supporting the game! 💛", Font = F.Body, Size = UDim2.fromOffset(700, 40), Position = UDim2.fromScale(0.5, 0.6), MaxTextSize = 34, Stroke = 2, Rotation = 0, From = 0.5 })
	task.wait(2.6)
	close()
end

-- Petite carte de récompense (non bloquante), au centre-haut.
local function rewardCard(icon: string, title: string, subtitle: string?, color: Color3?)
	local holder = Kit.new("Frame", {
		Size = UDim2.fromOffset(460, 110),
		Position = UDim2.new(0.5, 0, 0, 150),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = smallLayer,
	})
	Kit.AutoScale(holder)
	Kit.Starburst({ Size = UDim2.fromOffset(300, 300), Position = UDim2.fromOffset(60, 55), Color = color or C.Gold, Rays = 10, Transparency = 0.6, Parent = holder })
	local _, body = Kit.Panel({ Size = UDim2.fromScale(1, 1), Rotation = -2, Gradient = "Ink", Parent = holder })
	Kit.Text({ Size = UDim2.fromOffset(80, 80), Position = UDim2.fromOffset(12, 15), Text = icon, FontFace = F.Body, Stroke = false, ZIndex = 4, Parent = body })
	Kit.Text({ Size = UDim2.new(1, -110, 0, 46), Position = UDim2.fromOffset(100, 14), Text = title, FontFace = F.Impact, TextColor3 = color or C.Gold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Stroke = 3, Parent = body })
	if subtitle then
		Kit.Text({ Size = UDim2.new(1, -110, 0, 28), Position = UDim2.fromOffset(100, 62), Text = subtitle, FontFace = F.Body, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = body })
	end
	Kit.Pop(holder, 0.3, 0.45)
	task.delay(3, function()
		Kit.Tween(Kit.ScaleOf(holder), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.3)
		holder:Destroy()
	end)
end

function Cinematics.Init()
	layer = Kit.Layer("Cinematics", 30)
	layer.Enabled = false
	smallLayer = Kit.Layer("RewardCards", 35)

	FxBus.On("Hatch", function(args)
		enqueue(function()
			hatchReveal(args)
		end)
	end)
	FxBus.On("Fused", function(args)
		-- la fenêtre Fusion joue sa propre animation ; carte de rappel
		local species = Kaijus.Get(args.Species or "")
		if species then
			rewardCard("🧪", string.upper(species.Name), if args.Secret then "SECRET KAIJU CREATED!" else "Fusion complete!", Rarities.Get(species.Rarity).Color)
		end
	end)
	FxBus.On("HeistSuccess", function(args)
		enqueue(function()
			heistSuccess(args)
		end)
	end)
	FxBus.On("Robbed", function(args)
		enqueue(function()
			robbed(args)
		end)
	end)
	FxBus.On("Rebirth", function(args)
		if args.UserId == game:GetService("Players").LocalPlayer.UserId then
			enqueue(function()
				rebirthCinematic(args)
			end)
		end
	end)
	FxBus.On("PassUnlocked", function(args)
		enqueue(function()
			passUnlocked(args)
		end)
	end)
	FxBus.On("RewardClaimed", function(args)
		Audio.Play("reward_claim")
		rewardCard("🎁", args.Text or "Reward!", args.Source, C.Gold)
	end)
	FxBus.On("Discovered", function(args)
		local species = Kaijus.Get(args.Species or "")
		if not species then
			return
		end
		local mutation = Mutations.Get(args.Mutation)
		if args.NewSpecies then
			Audio.Play("quest_complete")
			rewardCard("📖", "NEW KAIJU DISCOVERED!", species.Name .. " — +1% cash forever", Rarities.Get(species.Rarity).Color)
		elseif mutation then
			rewardCard("✨", "NEW MUTATION!", mutation.Name .. " " .. species.Name, mutation.Color)
		end
	end)
	FxBus.On("EggGift", function(args)
		local rarity = Rarities.Get(args.Rarity or "Common")
		rewardCard("🥚", rarity.Name:upper() .. " EGG!", (args.Source or "Gift") .. " — placed in your nest", rarity.Color)
	end)
	FxBus.On("BossReward", function(args)
		rewardCard("👹", ("+%d 💎"):format(args.Gems or 0), if args.Top then "MVP of the raid!" else "Raid reward", C.Pink)
	end)
	FxBus.On("QuestReady", function(args)
		Audio.Play("quest_complete")
		UIRegistry.Toast("Quest complete: " .. (args.Text or ""), "Good")
	end)
	FxBus.On("DailyReady", function()
		task.delay(4, function()
			UIRegistry.Toast("Your daily reward is ready! 📅", "Good")
		end)
	end)
	FxBus.On("NestUnlocked", function(args)
		Audio.Play("level_jingle")
		rewardCard("🪺", "NEW NEST!", ("You now have %d nests"):format(args.Count or 0), C.Magma)
	end)
	FxBus.On("PersonalMeteor", function(args)
		local rarity = Rarities.Get(args.Rarity or "Common")
		if args.Golden then
			UIRegistry.Announce("🌟 GOLDEN METEOR!", C.Gold, ("A %s egg at HALF PRICE is landing on your island!"):format(string.upper(rarity.Name)), "meteor_rare_alarm")
		else
			UIRegistry.Toast(("☄️ A %s meteor is landing on YOUR island!"):format(rarity.Name), if rarity.Order >= 4 then "Rare" else "Info")
		end
	end)
	FxBus.On("HelperJoined", function(args)
		Audio.Play("steal_grab")
		UIRegistry.Toast((args.Name or "Someone") .. " is helping you carry it! GO GO GO!", "Good")
	end)
	FxBus.On("Grabbed", function(args)
		Audio.Play("steal_grab")
		if args.Lifting then
			UIRegistry.Announce("TOO HEAVY!", C.Magma, "Titans need 2 thieves — someone must help you lift it!", "ui_error")
		elseif args.Helper then
			UIRegistry.Toast("Team heist! Stay close to the leader!", "Good")
		end
	end)
end

return Cinematics
