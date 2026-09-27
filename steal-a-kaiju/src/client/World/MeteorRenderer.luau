--!nonstrict
-- Météores : chute depuis le ciel avec traînée de feu, impact, œuf posé sur
-- sa plateforme avec prix et minuteur, achat, envol vers la base.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local KaijuBuilder = require(Shared.KaijuBuilder)
local Rarities = require(Shared.Config.Rarities)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local CameraFx = require(Controllers.CameraFx)
local Effects = require(script.Parent.Effects)

local C = Theme.Colors
local player = Players.LocalPlayer

local MeteorRenderer = {}

type Entry = {
	Anchor: BasePart,
	Rock: BasePart?,
	Egg: Model?,
	Label: BillboardGui?,
	Prompt: ProximityPrompt?,
	Landed: boolean,
	From: Vector3,
	Whistle: Sound?,
	Removed: boolean,
}

local entries: { [string]: Entry } = {}
local recent: { [string]: Entry } = {} -- entrées retirées, gardées un instant pour les animations
local folder: Folder

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function isFreeForMe(): boolean
	local stats = State.Get("Stats")
	return stats ~= nil and stats.EggsBought == 0
end

local function buildLabel(entry: Entry)
	local anchor = entry.Anchor
	local rarity = Rarities.Get(anchor:GetAttribute("Rarity") or "Common")
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 86)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local function line(name: string, y: number, h: number, font: Font, color: Color3, text: string)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(0, y)
		t.Size = UDim2.new(1, 0, 0, h)
		t.FontFace = font
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = text
		local s = Instance.new("UIStroke")
		s.Thickness = 2.5
		s.Color = C.Ink
		s.Parent = t
		t.Parent = gui
		return t
	end
	local owner = anchor:GetAttribute("Owner") or 0
	local title = string.upper(rarity.Name) .. " EGG"
	if owner == player.UserId then
		title = "⭐ YOUR METEOR ⭐"
	end
	line("Title", 0, 28, Theme.Fonts.Title, if rarity.Id == "Secret" then C.White else rarity.Color, title)
	line("Price", 28, 30, Theme.Fonts.Impact, C.Cash, Format.Cash(anchor:GetAttribute("Price") or 0))
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(0.7, 0, 0, 10)
	bar.Position = UDim2.new(0.15, 0, 0, 64)
	bar.BackgroundColor3 = C.Ink
	bar.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = rarity.Color
	fill.BorderSizePixel = 0
	corner:Clone().Parent = fill
	fill.Parent = bar
	bar.Parent = gui
	gui.Parent = folder
	entry.Label = gui
end

local function buildPrompt(entry: Entry)
	local anchor = entry.Anchor
	local owner = anchor:GetAttribute("Owner") or 0
	if owner ~= 0 and owner ~= player.UserId then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 2.5, 0)
	attachment.Parent = anchor
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "BUY " .. Format.Cash(anchor:GetAttribute("Price") or 0)
	prompt.ObjectText = Rarities.Get(anchor:GetAttribute("Rarity") or "Common").Name .. " Egg"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("Color", "Radioactive")
	prompt.Parent = attachment
	prompt.Triggered:Connect(function()
		local r = Remote.Call("BuyMeteor", { Id = anchor:GetAttribute("Id") })
		if r.ok then
			Audio.Play("purchase")
			if r.free then
				Effects.FloatingText(anchor.Position + Vector3.new(0, 6, 0), "FREE!", C.Radioactive)
			end
		end
	end)
	entry.Prompt = prompt
end

local function spawnEgg(entry: Entry)
	local anchor = entry.Anchor
	local egg = KaijuBuilder.BuildEgg(anchor:GetAttribute("Rarity") or "Common", 1, anchor.CFrame * CFrame.new(0, -1.2, 0))
	egg.Parent = folder
	entry.Egg = egg
end

local function land(entry: Entry)
	entry.Landed = true
	local anchor = entry.Anchor
	local rarity = Rarities.Get(anchor:GetAttribute("Rarity") or "Common")
	if entry.Rock then
		entry.Rock:Destroy()
		entry.Rock = nil
	end
	if entry.Whistle then
		entry.Whistle:Destroy()
		entry.Whistle = nil
	end
	local pos = anchor.Position - Vector3.new(0, 1, 0)
	Effects.Impact(pos, rarity.Color, rarity.Order)
	Audio.Play("meteor_impact", { Parent = anchor, MaxDistance = 400 })
	CameraFx.ShakeAt(pos, 0.6 + rarity.Order * 0.2, 120, 0.5)
	if rarity.Order >= 4 then
		Effects.Pillar(pos, rarity.Color, 2.5)
	end
	spawnEgg(entry)
	buildLabel(entry)
	if entry.Prompt then
		entry.Prompt.Enabled = true
	end
end

local function track(anchor: BasePart)
	local id = anchor:GetAttribute("Id") or anchor.Name
	if entries[id] then
		return
	end
	local rarity = Rarities.Get(anchor:GetAttribute("Rarity") or "Common")
	local angle = math.random() * math.pi * 2
	local from = anchor.Position + Vector3.new(math.cos(angle) * 140, 320, math.sin(angle) * 140)
	local entry: Entry = { Anchor = anchor, Rock = nil, Egg = nil, Label = nil, Prompt = nil, Landed = false, From = from, Whistle = nil, Removed = false }
	entries[id] = entry
	buildPrompt(entry)

	local landAt = anchor:GetAttribute("LandAt") or 0
	if landAt <= now() then
		-- déjà tombé (on vient d'arriver)
		entry.Landed = true
		spawnEgg(entry)
		buildLabel(entry)
		if entry.Prompt then
			entry.Prompt.Enabled = true
		end
		return
	end
	local rock = Instance.new("Part")
	rock.Name = "Meteor"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(1, 1, 1) * (4 + rarity.Order * 0.6)
	rock.Material = Enum.Material.Slate
	rock.Color = Color3.fromRGB(70, 50, 50)
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false
	rock.CanTouch = false
	rock.CFrame = CFrame.new(from)
	rock.Parent = folder
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Size = rock.Size * 0.8
	core.Material = Enum.Material.Neon
	core.Color = rarity.Color
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Transparency = 0.3
	core.CFrame = rock.CFrame
	core.Parent = rock
	Effects.MeteorTrail(rock, rarity.Color, rarity.TrailWidth)
	entry.Rock = rock
	entry.Whistle = Audio.Play("meteor_whistle", { Parent = rock, MaxDistance = 500, NoVary = true })
end

local function untrack(id: string)
	local entry = entries[id]
	if not entry then
		return
	end
	entries[id] = nil
	recent[id] = entry
	task.delay(2, function()
		if recent[id] == entry then
			recent[id] = nil
		end
	end)
	entry.Removed = true
	for _, inst in { entry.Rock, entry.Label } do
		if inst then
			inst:Destroy()
		end
	end
	if entry.Whistle then
		entry.Whistle:Destroy()
	end
	-- l'œuf est géré par MeteorBought / MeteorExpired (animations), sinon supprimé
	task.delay(0.6, function()
		if entry.Egg and entry.Egg.Parent and not entry.Egg:GetAttribute("Animating") then
			entry.Egg:Destroy()
		end
	end)
end

local function flyEggTo(egg: Model, target: Vector3)
	egg:SetAttribute("Animating", true)
	local start = egg:GetPivot()
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / 1.1, 0, 1)
		local e = a * a * (3 - 2 * a)
		local p = start.Position:Lerp(target, e) + Vector3.new(0, math.sin(a * math.pi) * 60, 0)
		egg:PivotTo(CFrame.new(p) * CFrame.Angles(a * 8, a * 5, 0))
		if a >= 1 then
			conn:Disconnect()
			Effects.Dust(target, 3)
			egg:Destroy()
		end
	end)
end

function MeteorRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientMeteors"
	folder.Parent = Workspace

	local meteors = Workspace:WaitForChild("Meteors")
	for _, m in meteors:GetChildren() do
		if m:IsA("BasePart") then
			task.spawn(track, m)
		end
	end
	meteors.ChildAdded:Connect(function(m)
		if m:IsA("BasePart") then
			task.wait()
			track(m)
		end
	end)
	meteors.ChildRemoved:Connect(function(m)
		untrack(m:GetAttribute("Id") or m.Name)
	end)

	RunService.RenderStepped:Connect(function()
		local t = now()
		for _, entry in entries do
			local anchor = entry.Anchor
			if not entry.Landed then
				local landAt = anchor:GetAttribute("LandAt") or t
				local fall = 2.6
				local a = math.clamp(1 - (landAt - t) / fall, 0, 1)
				local e = a * a
				if entry.Rock then
					entry.Rock.CFrame = CFrame.new(entry.From:Lerp(anchor.Position, e)) * CFrame.Angles(a * 6, a * 4, 0)
					local core = entry.Rock:FindFirstChildWhichIsA("BasePart")
					if core then
						core.CFrame = entry.Rock.CFrame
					end
				end
				if a >= 1 then
					land(entry)
				end
			else
				if entry.Egg then
					local bob = math.sin(os.clock() * 2.5) * 0.3
					entry.Egg:PivotTo(anchor.CFrame * CFrame.new(0, -1 + bob, 0) * CFrame.Angles(0, os.clock() * 0.8, math.sin(os.clock() * 5) * 0.05))
				end
				local label = entry.Label
				if label then
					local expire = anchor:GetAttribute("ExpireAt") or t
					local land_ = anchor:GetAttribute("LandAt") or t
					local fill = label:FindFirstChild("Bar") and label.Bar:FindFirstChild("Fill")
					if fill then
						fill.Size = UDim2.fromScale(math.clamp((expire - t) / math.max(1, expire - land_), 0, 1), 1)
					end
				end
			end
		end
	end)

	-- Prix « GRATUIT » pour le tout premier œuf
	task.spawn(function()
		while true do
			task.wait(0.5)
			local free = isFreeForMe()
			for _, entry in entries do
				local price = entry.Anchor:GetAttribute("Price") or 0
				local text = if free and price <= 500 then "FREE!" else Format.Cash(price)
				if entry.Label then
					local p = entry.Label:FindFirstChild("Price") :: TextLabel?
					if p then
						p.Text = text
						p.TextColor3 = if (State.Get("Cash") or 0) >= price or text == "FREE!" then C.Cash else C.Red
					end
				end
				if entry.Prompt then
					entry.Prompt.ActionText = if text == "FREE!" then "GRAB FREE" else "BUY " .. text
				end
			end
		end
	end)

	FxBus.On("MeteorBought", function(args)
		local entry = entries[args.Id or ""] or recent[args.Id or ""]
		local egg = entry and entry.Egg
		local buyer = Players:GetPlayerByUserId(args.Buyer or 0)
		local plotIndex = buyer and buyer:GetAttribute("Plot")
		local map = Workspace:FindFirstChild("Map")
		local plot = plotIndex and map and map:FindFirstChild("Plot" .. plotIndex)
		if egg and plot then
			local floor = plot:FindFirstChild("Floor") :: BasePart?
			flyEggTo(egg, if floor then floor.Position + Vector3.new(0, 4, 0) else egg:GetPivot().Position)
			Audio.Play("whoosh")
		elseif egg then
			egg:Destroy()
		end
	end)
	FxBus.On("MeteorExpired", function(args)
		local entry = entries[args.Id or ""] or recent[args.Id or ""]
		if entry and entry.Egg then
			local egg = entry.Egg
			egg:SetAttribute("Animating", true)
			Effects.Poof(egg:GetPivot().Position, 3)
			Audio.Play("egg_crack", { Pitch = 0.8 })
			egg:Destroy()
		end
	end)
end

return MeteorRenderer
