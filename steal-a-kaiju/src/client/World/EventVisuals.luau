--!nonstrict
-- Ambiance des événements mondiaux (éclairage, météo, musique, annonces),
-- rendu du Colosse (boss) avec barre de vie, orbes de la Stampede.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local KaijuBuilder = require(Shared.KaijuBuilder)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local CameraFx = require(Controllers.CameraFx)
local UIRegistry = require(Controllers.UIRegistry)
local Effects = require(script.Parent.Effects)
local Kit = require(script.Parent.Parent.UI.Kit)

local C = Theme.Colors
local player = Players.LocalPlayer

local EventVisuals = {}

local DEFAULT = {
	ClockTime = 15.2,
	Ambient = Color3.fromRGB(70, 60, 90),
	Tint = Color3.fromRGB(255, 248, 240),
	FogColor = Color3.fromRGB(200, 220, 255),
	FogEnd = 4000,
}

local weather: Part
local emitters: { ParticleEmitter } = {}
local skyParts: { BasePart } = {}
local currentId: string? = nil
local worldLighting = nil -- éclairage d'un monde (prioritaire tant qu'on y est)

----------------------------------------------------------------------------
-- Éclairage et météo
----------------------------------------------------------------------------

local function applyLighting(cfg)
	local info = TweenInfo.new(3, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, {
		ClockTime = cfg.ClockTime or DEFAULT.ClockTime,
		Ambient = cfg.Ambient or DEFAULT.Ambient,
		FogColor = cfg.FogColor or DEFAULT.FogColor,
		FogEnd = cfg.FogEnd or DEFAULT.FogEnd,
	}):Play()
	local grade = Lighting:FindFirstChild("Grade")
	if grade then
		TweenService:Create(grade, info, { TintColor = cfg.Tint or DEFAULT.Tint }):Play()
	end
end

-- Éclairage effectif : celui du monde visité, sinon celui de l'événement, sinon le défaut.
local function refreshLighting()
	local event = currentId and Events.ById[currentId]
	applyLighting(worldLighting or (if event then event.Lighting else DEFAULT))
end

function EventVisuals.SetWorldLighting(cfg: any?)
	worldLighting = cfg
	refreshLighting()
end

local function clearWeather()
	for _, e in emitters do
		e.Enabled = false
		task.delay(3, function()
			e:Destroy()
		end)
	end
	table.clear(emitters)
	for _, p in skyParts do
		TweenService:Create(p, TweenInfo.new(2), { Transparency = 1 }):Play()
		task.delay(2.1, function()
			p:Destroy()
		end)
	end
	table.clear(skyParts)
end

local function addEmitter(props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		e[k] = v
	end
	e.Parent = weather
	table.insert(emitters, e)
	return e
end

local function lowFx(): boolean
	local s = State.Get("Settings")
	return s ~= nil and s.LowFx == true
end

local function startWeather(id: string)
	clearWeather()
	if lowFx() then
		return
	end
	local sparkle = Effects.Textures.Sparkle
	if id == "BloodMoon" then
		addEmitter({ Texture = Effects.Textures.Spark, Color = ColorSequence.new(Color3.fromRGB(255, 60, 60)), LightEmission = 1, Rate = 60, Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(4, 8), EmissionDirection = Enum.NormalId.Bottom, Size = NumberSequence.new(0.5), SpreadAngle = Vector2.new(30, 30) })
		-- lune de sang géante
		local moon = Instance.new("Part")
		moon.Shape = Enum.PartType.Ball
		moon.Size = Vector3.new(160, 160, 160)
		moon.Anchored = true
		moon.CanCollide = false
		moon.CanQuery = false
		moon.CanTouch = false
		moon.Material = Enum.Material.Neon
		moon.Color = Color3.fromRGB(220, 30, 40)
		moon.Transparency = 1
		moon.CFrame = CFrame.new(400, 520, -900)
		moon.Parent = Workspace
		TweenService:Create(moon, TweenInfo.new(3), { Transparency = 0.1 }):Play()
		table.insert(skyParts, moon)
	elseif id == "Radioactive" then
		addEmitter({ Texture = Effects.Textures.Glow, Color = ColorSequence.new(Color3.fromRGB(120, 255, 80)), LightEmission = 0.6, Rate = 220, Lifetime = NumberRange.new(1.2, 1.6), Speed = NumberRange.new(60, 80), EmissionDirection = Enum.NormalId.Bottom, Size = NumberSequence.new(0.25), SpreadAngle = Vector2.new(8, 8), Transparency = NumberSequence.new(0.3) })
		addEmitter({ Texture = Effects.Textures.Smoke, Color = ColorSequence.new(Color3.fromRGB(80, 200, 60)), Rate = 4, Lifetime = NumberRange.new(6, 8), Speed = NumberRange.new(2, 4), Size = NumberSequence.new(30), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 1) }) })
	elseif id == "Aurora" then
		addEmitter({ Texture = sparkle, Color = ColorSequence.new(Color3.fromRGB(150, 120, 255), Color3.fromRGB(80, 255, 230)), LightEmission = 1, Rate = 40, Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(1, 3), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 0) }), SpreadAngle = Vector2.new(180, 180) })
		for i = 1, 6 do
			local band = Instance.new("Part")
			band.Anchored = true
			band.CanCollide = false
			band.CanQuery = false
			band.CanTouch = false
			band.Material = Enum.Material.Neon
			band.Color = Color3.fromHSV(0.45 + i * 0.05, 0.7, 1)
			band.Transparency = 1
			band.Size = Vector3.new(900, 60, 2)
			band.CFrame = CFrame.new(0, 420 + i * 25, -300 + i * 90) * CFrame.Angles(math.rad(70), math.rad(i * 12), 0)
			band.Parent = Workspace
			TweenService:Create(band, TweenInfo.new(4), { Transparency = 0.7 }):Play()
			table.insert(skyParts, band)
		end
	elseif id == "GoldenHour" then
		addEmitter({ Texture = sparkle, Color = ColorSequence.new(Color3.fromRGB(255, 220, 90)), LightEmission = 1, Rate = 50, Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(1, 3), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 0) }), SpreadAngle = Vector2.new(180, 180) })
	elseif id == "MeteorShower" then
		addEmitter({ Texture = Effects.Textures.Spark, Color = ColorSequence.new(Color3.fromRGB(255, 200, 120)), LightEmission = 1, Rate = 12, Lifetime = NumberRange.new(1, 1.5), Speed = NumberRange.new(120, 180), EmissionDirection = Enum.NormalId.Bottom, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) }), SpreadAngle = Vector2.new(40, 40), Orientation = Enum.ParticleOrientation.VelocityParallel })
	end
end

local function onEventChanged()
	local id = Workspace:GetAttribute("EventId")
	if id == currentId then
		return
	end
	currentId = id
	local event = id and Events.ById[id]
	refreshLighting()
	if event then
		startWeather(event.Id)
		Audio.Music(event.Music or "music_main")
	else
		clearWeather()
		Audio.Music("music_main")
	end
end

----------------------------------------------------------------------------
-- Boss
----------------------------------------------------------------------------

local boss: Model? = nil
local bossAnchor: BasePart? = nil
local bossBar: Frame? = nil
local setBossBar: ((number, boolean?) -> ())? = nil
local bossJump = 0
local bossSpawnAt = 0

local function buildBossBar()
	local layer = Kit.Layer("BossBar", 8)
	local holder = Kit.new("Frame", {
		Size = UDim2.fromOffset(620, 70),
		Position = UDim2.new(0.5, 0, 0, 130),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	Kit.AutoScale(holder)
	Kit.Text({ Name = "Title", Size = UDim2.new(1, 0, 0, 32), Text = "👹 THE COLOSSUS", FontFace = Kit.Fonts.Impact, TextColor3 = C.Pink, Stroke = 3, Parent = holder })
	local _, set = Kit.ProgressBar({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 38), Color = "Red", Parent = holder })
	Kit.Text({ Name = "HP", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 40), Text = "", FontFace = Kit.Fonts.Title, ZIndex = 20, Parent = holder })
	bossBar = holder
	setBossBar = set
end

local function trackBoss(anchor: BasePart)
	bossAnchor = anchor
	local model = KaijuBuilder.Build(anchor:GetAttribute("Species") or "KingKaiju", anchor:GetAttribute("Mutation"), anchor:GetAttribute("Scale") or 7)
	model.Name = "BossModel"
	model.Parent = Workspace
	boss = model
	-- entrée dramatique : sort du sol
	model:PivotTo(anchor.CFrame * CFrame.new(0, -40, 0))
	bossSpawnAt = os.clock()
	Audio.Play("roar_big", { Volume = 1.5 })
	CameraFx.Shake(1.5, 2)
	if bossBar then
		bossBar.Visible = true
		Kit.Pop(bossBar)
	end
end

local function untrackBoss()
	if boss then
		local model = boss
		boss = nil
		local pos = model:GetPivot().Position
		Effects.Impact(pos, C.Pink, 10)
		model:Destroy()
	end
	bossAnchor = nil
	if bossBar then
		bossBar.Visible = false
	end
end

----------------------------------------------------------------------------
-- Orbes
----------------------------------------------------------------------------

local orbs: { [BasePart]: BasePart } = {}
local grabbed: { [string]: boolean } = {}

local function trackOrb(anchor: BasePart)
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2.6, 2.6, 2.6)
	orb.Material = Enum.Material.Neon
	orb.Color = C.Cash
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CFrame = anchor.CFrame
	orb.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = C.Cash
	light.Range = 10
	light.Parent = orb
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 60)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = orb
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "💵"
	label.TextScaled = true
	label.Parent = gui
	Effects.Sparkles(orb, C.Cash, 6)
	orbs[anchor] = orb
end

local function untrackOrb(anchor: Instance)
	local orb = orbs[anchor :: BasePart]
	if orb then
		orbs[anchor :: BasePart] = nil
		Effects.Burst(orb.Position, C.Cash, 12, 1.5)
		orb:Destroy()
	end
end

----------------------------------------------------------------------------

function EventVisuals.Init()
	weather = Instance.new("Part")
	weather.Name = "Weather"
	weather.Anchored = true
	weather.CanCollide = false
	weather.CanQuery = false
	weather.CanTouch = false
	weather.Transparency = 1
	weather.Size = Vector3.new(180, 1, 180)
	weather.Parent = Workspace

	buildBossBar()

	Workspace:GetAttributeChangedSignal("EventId"):Connect(onEventChanged)
	onEventChanged()
	if not Workspace:GetAttribute("EventId") then
		Audio.Music("music_main")
	end

	FxBus.On("EventStart", function(args)
		local event = Events.ById[args.Id or ""]
		if event then
			Audio.Play("event_horn")
			UIRegistry.Announce(event.Icon .. " " .. event.Name, event.Color, event.Tagline)
			CameraFx.Shake(0.5, 1)
		end
	end)
	FxBus.On("EventEnd", function(args)
		local event = Events.ById[args.Id or ""]
		if event then
			UIRegistry.Toast(event.Name .. " is over!", "Info")
		end
	end)

	local effects = Workspace:WaitForChild("Effects")
	effects.ChildAdded:Connect(function(child)
		if child.Name == "Boss" and child:IsA("BasePart") then
			task.wait()
			trackBoss(child)
		end
	end)
	effects.ChildRemoved:Connect(function(child)
		if child == bossAnchor then
			untrackBoss()
		end
	end)
	local existing = effects:FindFirstChild("Boss")
	if existing and existing:IsA("BasePart") then
		trackBoss(existing)
	end

	FxBus.On("BossHit", function(args)
		if boss then
			local pos = boss:GetPivot().Position + Vector3.new(math.random(-12, 12), math.random(4, 18), math.random(-12, 12))
			Effects.FloatingText(pos, "-" .. Format.Short(args.Damage or 0), if args.UserId == player.UserId then C.Gold else C.Paper, 0.7)
			if args.UserId == player.UserId then
				Effects.Burst(pos, C.Pink, 10, 2)
			end
		end
	end)
	FxBus.On("BossStomp", function()
		bossJump = os.clock()
		task.delay(0.8, function()
			if boss then
				local pos = boss:GetPivot().Position
				Effects.Shockwave(pos, C.Pink, 50, 0.8)
				Effects.Dust(pos, 12)
				Audio.Play("boss_stomp", { Volume = 1.3 })
				CameraFx.ShakeAt(pos, 2, 220, 0.7)
			end
		end)
	end)
	FxBus.On("BossSpawn", function()
		UIRegistry.Announce("👹 THE COLOSSUS AWAKENS!", C.Pink, "Everyone to the crater — BONK IT!", "roar_big")
	end)
	FxBus.On("BossEnd", function(args)
		if args.Defeated then
			UIRegistry.Announce("COLOSSUS DEFEATED!", C.Gold, "Rewards sent to all fighters!", "heist_success")
		end
	end)

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera then
			weather.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 60, 0))
		end
		if boss and bossAnchor then
			local t = os.clock()
			local jump = t - bossJump
			local y = 0
			if jump < 0.8 then
				y = math.sin(jump / 0.8 * math.pi) * 14
			end
			local rise = math.clamp((t - bossSpawnAt) / 2.5, 0, 1)
			if rise < 1 then
				y = -40 * (1 - rise) ^ 2
			end
			-- regarde le joueur le plus proche (le local, pour le frisson)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local look = if root then Vector3.new(root.Position.X, 0, root.Position.Z) else Vector3.new(0, 0, -1)
			local base = bossAnchor.Position
			local cf = CFrame.lookAt(base, Vector3.new(look.X, base.Y, look.Z) + Vector3.new(0.01, 0, 0))
			boss:PivotTo(cf * CFrame.new(0, y + math.sin(t * 1.5) * 0.6, 0) * CFrame.Angles(0, 0, math.sin(t * 0.8) * 0.03))
			local hp = bossAnchor:GetAttribute("HP") or 0
			local maxHp = bossAnchor:GetAttribute("MaxHP") or 1
			if setBossBar then
				setBossBar(hp / maxHp, true)
			end
			if bossBar then
				local label = bossBar:FindFirstChild("HP") :: TextLabel?
				if label then
					label.Text = ("%s / %s"):format(Format.Short(hp), Format.Short(maxHp))
				end
			end
		end
		-- orbes : animation + ramassage par proximité
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		for anchor, orb in orbs do
			local t = os.clock()
			orb.CFrame = anchor.CFrame * CFrame.new(0, math.sin(t * 3 + anchor.Position.X) * 0.6, 0)
			if root and (root.Position - orb.Position).Magnitude < 7 then
				local id = anchor:GetAttribute("Id")
				if id and not grabbed[id] then
					grabbed[id] = true
					Remote.Input("Orb", { Id = id })
					Audio.Play("coin_tick", { Pitch = 1.2 })
				end
			end
		end
	end)

	local orbFolder = Workspace:WaitForChild("Orbs")
	orbFolder.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			trackOrb(child)
		end
	end)
	orbFolder.ChildRemoved:Connect(untrackOrb)
	FxBus.On("StampedeWave", function()
		Audio.Play("roar_small", { Pitch = 0.8 })
	end)
end

return EventVisuals
