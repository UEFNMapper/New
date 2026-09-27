--!nonstrict
-- RAMPAGE côté client : le modèle géant du kaiju « soudé » visuellement au
-- personnage (dandinement, écrasement au STOMP), caméra reculée selon la
-- taille, entrées (clic / F = STOMP, R = ROAR, gros boutons mobiles), tanks-
-- jouets et fléchettes calculés à partir du temps, débris physiques, poussière,
-- secousses, chiffres de cash, bannières. Le serveur (RampageService) décide
-- de tout ce qui compte ; ici on ne fait qu'afficher et envoyer les entrées.
--
-- API publique : RampageController.Open() (bouton du HUD), IsActive(),
-- Stomp(), Roar(), Leave().

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local KaijuBuilder = require(Shared.KaijuBuilder)
local Rampage = require(Shared.Config.Rampage)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Remote = require(Controllers.Remote)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local CameraFx = require(Controllers.CameraFx)
local UIRegistry = require(Controllers.UIRegistry)
local RampageHud = require(script.Parent.Parent.UI.RampageHud)
local Effects = require(script.Parent.Effects)

local C = Theme.Colors
local WINDOW = Color3.fromRGB(170, 230, 255)
local HIDDEN_GUIS = { "KaijuUI", "Tutorial", "Feed", "BossBar" } -- HUD principal masqué pendant la partie

local player = Players.LocalPlayer

local RampageController = {}

local active: any = nil -- partie en cours
local lastResult: any = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function lowFx(): boolean
	local settings = State.Get("Settings")
	return settings ~= nil and settings.LowFx == true
end

local function rampageScreen(): any
	return (UIRegistry.Screens :: any).Rampage
end

local function rootOf(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function tween(inst: Instance, time: number, props: { [string]: any })
	TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function fxFolder(): Folder
	local folder = Workspace:FindFirstChild("ClientRampage")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClientRampage"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function newPart(props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent or fxFolder()
	return p
end

-- Pied du personnage (niveau du sol sous le kaiju).
local function feetOf(root: BasePart): Vector3
	local humanoid = humanoidOf()
	local hip = if humanoid then humanoid.HipHeight else 2
	return root.Position - Vector3.new(0, (hip or 2) + root.Size.Y / 2, 0)
end

----------------------------------------------------------------------------
-- Effets de destruction
----------------------------------------------------------------------------

-- Morceaux physiques qui volent (courte durée de vie).
local function debris(pos: Vector3, size: Vector3, color: Color3, count: number)
	local folder = fxFolder()
	for _ = 1, count do
		local s = math.clamp(math.max(size.X, size.Z) * (0.16 + math.random() * 0.18), 0.6, 4)
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(s, s * (0.5 + math.random() * 0.8), s)
		chunk.Color = if math.random() < 0.25 then WINDOW else color:Lerp(Color3.new(1, 1, 1), math.random() * 0.25)
		chunk.Material = Enum.Material.SmoothPlastic
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CFrame = CFrame.new(pos + Vector3.new((math.random() - 0.5) * size.X, math.random() * size.Y, (math.random() - 0.5) * size.Z))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = folder
		local out = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		out = if out.Magnitude > 0.01 then out.Unit else Vector3.new(1, 0, 0)
		chunk.AssemblyLinearVelocity = out * (14 + math.random() * 22) + Vector3.new(0, 26 + math.random() * 30, 0)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 24
		Debris:AddItem(chunk, 2.2 + math.random() * 0.8)
	end
end

local function buildingModel(id: number): Model?
	local cities = Workspace:FindFirstChild("RampageCities")
	local city = cities and cities:FindFirstChild(tostring(player.UserId))
	local buildings = city and city:FindFirstChild("Buildings")
	return buildings and buildings:FindFirstChild("B" .. id) :: Model?
end

-- Petite barre de PV au-dessus d'un immeuble ou d'un tank.
local function hpBar(adornee: BasePart, height: number, alpha: number)
	local gui = adornee:FindFirstChild("HpBar") :: BillboardGui?
	if not gui then
		local g = Instance.new("BillboardGui")
		g.Name = "HpBar"
		g.Size = UDim2.fromOffset(70, 12)
		g.StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 2, 0)
		g.LightInfluence = 0
		g.MaxDistance = 160
		g.Adornee = adornee
		g.Parent = adornee
		local back = Instance.new("Frame")
		back.Name = "Back"
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = C.Ink
		back.BorderSizePixel = 0
		back.Parent = g
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = C.Red
		fill.BorderSizePixel = 0
		fill.Parent = back
		gui = g
	end
	local back = (gui :: BillboardGui):FindFirstChild("Back")
	local fill = back and back:FindFirstChild("Fill") :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	end
end

----------------------------------------------------------------------------
-- Modèle du kaiju
----------------------------------------------------------------------------

local function buildKaiju(args: any): any
	local scale = args.Scale * Rampage.ModelScale
	local model = KaijuBuilder.Build(args.Species, args.Mutation, scale)
	model.Name = "RampageKaiju"
	local k = { Model = model, Parts = {}, Offsets = {}, Roles = {}, Scale = scale, Height = KaijuBuilder.Height(args.Species) * scale, Pivots = {} }
	local tailBest: Vector3? = nil
	local headSum, headCount = Vector3.zero, 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			local role = p:GetAttribute("Role") or ""
			table.insert(k.Parts, p)
			table.insert(k.Offsets, p.CFrame)
			table.insert(k.Roles, role)
			if role == "Tail" and (not tailBest or p.Position.Z < tailBest.Z) then
				tailBest = p.Position
			elseif role == "Head" then
				headSum += p.Position
				headCount += 1
			end
		end
	end
	k.Pivots.Tail = tailBest
	k.Pivots.Head = if headCount > 0 then headSum / headCount else nil
	model.Parent = fxFolder()
	-- anneau de portée du STOMP (lisible : ce qui est dedans sera touché)
	local radius = Rampage.StompRadius(args.Scale)
	k.Ring = newPart({
		Name = "StompRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, radius * 2, radius * 2),
		Color = C.Radioactive,
		Material = Enum.Material.Neon,
		Transparency = 0.78,
		CastShadow = false,
	})
	return k
end

local function placeKaiju(dt: number)
	local root = rootOf()
	local k = active and active.Kaiju
	if not root or not k then
		return
	end
	local feet = feetOf(root)
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local moving = math.clamp(speed / 12, 0, 1)
	local t = os.clock()
	active.Phase += dt * (3 + speed * 0.4)
	local s = k.Scale
	-- dandinement (roulis + rebond) quand il marche, respiration à l'arrêt
	local roll = math.sin(active.Phase) * 0.13 * moving
	local bob = math.abs(math.sin(active.Phase)) * 0.28 * s * moving + (math.sin(t * 2.2) + 1) * 0.04 * s
	-- STOMP : le kaiju se lève puis s'écrase
	local st = t - active.StompAt
	local lift = if st < 0.1 then st / 0.1 * 0.6 * s elseif st < 0.22 then (1 - (st - 0.1) / 0.12) * 0.6 * s - 0.25 * s * ((st - 0.1) / 0.12) else 0
	-- ROAR : il se cabre
	local rt = t - active.RoarAt
	local rear = if rt < 0.9 then math.sin(math.clamp(rt / 0.9, 0, 1) * math.pi) * 0.22 else 0
	local base = CFrame.new(feet.X, feet.Y + bob + lift, feet.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(rear, 0, roll)
	local cfs = table.create(#k.Parts)
	local tail, head = k.Pivots.Tail, k.Pivots.Head
	for i, offset in k.Offsets do
		local role = k.Roles[i]
		if role == "Tail" and tail then
			cfs[i] = base * CFrame.new(tail) * CFrame.Angles(0, math.sin(active.Phase * 0.5 + t * 2) * 0.3, 0) * CFrame.new(-tail) * offset
		elseif role == "Head" and head then
			cfs[i] = base * CFrame.new(head) * CFrame.Angles(rear * 1.5 + math.sin(t * 1.7) * 0.05, 0, 0) * CFrame.new(-head) * offset
		else
			cfs[i] = base * offset
		end
	end
	Workspace:BulkMoveTo(k.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if k.Model.PrimaryPart then
		k.Model.PrimaryPart.CFrame = base
	end
	k.Ring.CFrame = CFrame.new(feet.X, feet.Y + 0.1, feet.Z) * CFrame.Angles(0, 0, math.rad(90))
	k.Ring.Color = if os.clock() >= active.StompReady then C.Radioactive else C.InkSoft
end

----------------------------------------------------------------------------
-- Tanks et fléchettes (positions déduites du temps serveur)
----------------------------------------------------------------------------

local function buildTank(args: any): any
	local model = Instance.new("Model")
	model.Name = "ToyTank" .. args.Id
	model.Parent = fxFolder()
	local green = Color3.fromRGB(120, 190, 90)
	local hull = {
		{ newPart({ Name = "Hull", Size = Vector3.new(4.2, 1.6, 5.6), Color = green, Parent = model }), CFrame.new(0, 1.3, 0) },
		{ newPart({ Name = "Track", Size = Vector3.new(1.2, 1.3, 6.2), Color = C.Ink, Parent = model }), CFrame.new(-2.4, 0.65, 0) },
		{ newPart({ Name = "Track", Size = Vector3.new(1.2, 1.3, 6.2), Color = C.Ink, Parent = model }), CFrame.new(2.4, 0.65, 0) },
	}
	local turret = {
		{ newPart({ Name = "Turret", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Color = green:Lerp(C.White, 0.2), Parent = model }), CFrame.new(0, 0, 0) },
		{ newPart({ Name = "Barrel", Size = Vector3.new(0.7, 0.7, 3.6), Color = C.Magma, Parent = model }), CFrame.new(0, 0.2, -2.4) },
		{ newPart({ Name = "Flag", Size = Vector3.new(0.15, 1, 1.4), Color = C.Red, Parent = model }), CFrame.new(0.9, 2.2, 0.8) },
	}
	return { Args = args, Model = model, Hull = hull, Turret = turret, Body = hull[1][1] }
end

local function tankPosition(t: any, now: number): Vector3
	local from, to = t.Args.From, t.Args.To
	local len = (to - from).Magnitude
	if len < 0.01 then
		return to
	end
	return from:Lerp(to, math.clamp((now - t.Args.T0) * t.Args.Speed / len, 0, 1))
end

local function placeTanks(now: number)
	local root = rootOf()
	for _, t in active.Tanks do
		local pos = tankPosition(t, now)
		local dir = t.Args.To - t.Args.From
		local base = if dir.Magnitude > 0.1 then CFrame.lookAt(pos, pos + dir) else CFrame.new(pos)
		for _, entry in t.Hull do
			entry[1].CFrame = base * entry[2]
		end
		local turretPos = pos + Vector3.new(0, 2.6, 0)
		local aim = if root then Vector3.new(root.Position.X, turretPos.Y, root.Position.Z) - turretPos else base.LookVector
		local turretBase = if aim.Magnitude > 0.1 then CFrame.lookAt(turretPos, turretPos + aim) else CFrame.new(turretPos)
		for _, entry in t.Turret do
			entry[1].CFrame = turretBase * entry[2]
		end
	end
end

local function buildDart(args: any, radius: number): any
	local body = newPart({ Name = "Dart", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 0.6, 0.6), Color = C.Magma })
	local tip = newPart({ Name = "DartTip", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Color = C.Red })
	local ring = newPart({
		Name = "DartTarget",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 1, 1),
		CFrame = CFrame.new(args.To + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Red,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		CastShadow = false,
	})
	return { Args = args, Body = body, Tip = tip, Ring = ring, Radius = radius }
end

local function dartPoint(d: any, a: number): Vector3
	local from, to = d.Args.From, d.Args.To
	local arc = 5 + (to - from).Magnitude * 0.18
	return from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * arc, 0)
end

local function placeDarts(now: number)
	for id, d in active.Darts do
		local span = math.max(d.Args.T1 - d.Args.T0, 0.05)
		local a = math.clamp((now - d.Args.T0) / span, 0, 1)
		local p = dartPoint(d, a)
		local nextP = dartPoint(d, math.min(a + 0.02, 1.02))
		local cf = if (nextP - p).Magnitude > 0.01 then CFrame.lookAt(p, nextP) else CFrame.new(p)
		-- le cylindre est couché sur X : on l'aligne sur la trajectoire
		d.Body.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
		d.Tip.CFrame = cf * CFrame.new(0, 0, -1.4)
		local r = d.Radius * 2 * (0.35 + 0.65 * a)
		d.Ring.Size = Vector3.new(0.1, r, r)
		d.Ring.Transparency = 0.65 - 0.3 * a
		if a >= 1 and now > d.Args.T1 + 0.05 then
			active.Darts[id] = nil
			Effects.Poof(d.Args.To + Vector3.new(0, 1, 0), 2)
			Audio.Play("drop", { Volume = 0.5, Cooldown = 0.1 })
			d.Body:Destroy()
			d.Tip:Destroy()
			d.Ring:Destroy()
		end
	end
end

----------------------------------------------------------------------------
-- Boucle et nettoyage
----------------------------------------------------------------------------

local function step(dt: number)
	if not active then
		return
	end
	local now = serverNow()
	placeKaiju(dt)
	placeTanks(now)
	placeDarts(now)
	local clock = os.clock()
	RampageHud.Update(now, math.max(0, active.StompReady - clock), math.max(0, active.RoarReady - clock))
end

local function hideGuis()
	local gui = player:FindFirstChild("PlayerGui")
	if not gui then
		return
	end
	for _, name in HIDDEN_GUIS do
		local layer = gui:FindFirstChild(name) :: ScreenGui?
		if layer and layer.Enabled then
			layer.Enabled = false
			table.insert(active.HiddenGuis, layer)
		end
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
end

local function stop()
	local run = active
	if not run then
		return
	end
	active = nil
	for _, conn in run.Conns do
		conn:Disconnect()
	end
	fxFolder():ClearAllChildren()
	RampageHud.Hide()
	for _, layer in run.HiddenGuis do
		if layer.Parent then
			layer.Enabled = true
		end
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, true)
	player.CameraMinZoomDistance = run.Saved.MinZoom
	player.CameraMaxZoomDistance = run.Saved.MaxZoom
	local humanoid = humanoidOf()
	if humanoid then
		humanoid.CameraOffset = run.Saved.CameraOffset
	end
	if Audio.CurrentMusic() == "music_boss" then
		Audio.Music(run.Saved.Music or "music_main")
	end
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

function RampageController.IsActive(): boolean
	return active ~= nil
end

-- Ouvre l'écran de choix (kaiju + quartier). Branché sur un bouton du HUD.
function RampageController.Open(args: any?)
	local screen = rampageScreen()
	if screen then
		screen.Open(args)
	end
end

function RampageController.Stomp()
	if not active or active.Ended then
		return
	end
	local clock = os.clock()
	if clock < active.StompReady then
		return
	end
	active.StompReady = clock + Rampage.Stomp.Cooldown
	active.StompAt = clock
	Remote.Input("RampageStomp")
	-- retour immédiat (le serveur confirme les dégâts)
	task.delay(0.16, function()
		local root = rootOf()
		if not active or not root then
			return
		end
		local feet = feetOf(root)
		local s = active.Args.Scale
		Effects.Shockwave(feet, C.Paper, Rampage.StompRadius(s), 0.35)
		Effects.Dust(feet, 2 + s)
		CameraFx.Shake(0.4 + s * 0.25, 0.25)
		Audio.Play("boss_stomp", { Volume = 0.45 + s * 0.08, Pitch = 1.3 - s * 0.08, Cooldown = 0.1 })
	end)
end

function RampageController.Roar()
	if not active or active.Ended then
		return
	end
	local clock = os.clock()
	if clock < active.RoarReady then
		return
	end
	local root = rootOf()
	if not root then
		return
	end
	active.RoarReady = clock + Rampage.Roar.Cooldown
	active.RoarAt = clock
	local look = root.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z)
	dir = if dir.Magnitude > 0.05 then dir.Unit else Vector3.new(0, 0, -1)
	Remote.Input("RampageRoar", { Dir = dir })
	-- rayon rugissant : cône lumineux qui balaie devant le kaiju
	local s = active.Args.Scale
	local length = Rampage.RoarLength(s)
	local feet = feetOf(root)
	local mouth = feet + Vector3.new(0, active.Kaiju.Height * 0.7, 0) + dir * (1 + s)
	local target = Vector3.new(feet.X, feet.Y + 1, feet.Z) + dir * length
	local mid = (mouth + target) / 2
	local beamLen = (target - mouth).Magnitude
	local beam = newPart({
		Name = "RoarBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(beamLen, 1, 1),
		CFrame = CFrame.lookAt(mid, target) * CFrame.Angles(0, math.rad(90), 0),
		Color = C.Purple,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		CastShadow = false,
	})
	local width = 2 * math.tan(math.rad(Rampage.Roar.Angle / 2)) * length
	local fan = newPart({
		Name = "RoarFan",
		Size = Vector3.new(width, 0.2, length),
		CFrame = CFrame.lookAt(feet + dir * (length / 2) + Vector3.new(0, 0.3, 0), feet + dir * length + Vector3.new(0, 0.3, 0)),
		Color = C.Pink,
		Material = Enum.Material.Neon,
		Transparency = 0.7,
		CastShadow = false,
	})
	tween(beam, 0.5, { Size = Vector3.new(beamLen, 4 + s * 2, 4 + s * 2), Transparency = 1 })
	tween(fan, 0.6, { Transparency = 1 })
	Debris:AddItem(beam, 0.7)
	Debris:AddItem(fan, 0.7)
	Effects.Burst(target, C.Pink, 24, 2 + s * 0.5)
	Effects.Shockwave(target, C.Purple, 6 + s * 2, 0.4)
	CameraFx.FovPunch(10, 0.6)
	CameraFx.Shake(1 + s * 0.3, 0.5)
	Audio.Play("roar_big", { Pitch = 1.25 - s * 0.08 })
end

function RampageController.Leave()
	if active and not active.Ended then
		Remote.Call("RampageLeave", {}, true)
	end
end

----------------------------------------------------------------------------
-- Événements du serveur
----------------------------------------------------------------------------

local function onStart(args: any)
	stop()
	lastResult = nil
	local humanoid = humanoidOf()
	active = {
		Args = args,
		Kaiju = nil,
		Phase = 0,
		StompReady = 0,
		RoarReady = 0,
		StompAt = -10,
		RoarAt = -10,
		Tanks = {},
		Darts = {},
		Conns = {},
		HiddenGuis = {},
		Ended = false,
		Saved = {
			MinZoom = player.CameraMinZoomDistance or 0.5,
			MaxZoom = player.CameraMaxZoomDistance or 90,
			CameraOffset = if humanoid then humanoid.CameraOffset or Vector3.zero else Vector3.zero,
			Music = Audio.CurrentMusic(),
		},
	}
	local screen = rampageScreen()
	if screen then
		screen.Close()
	end
	active.Kaiju = buildKaiju(args)
	-- caméra : recule selon la taille du kaiju
	local height = active.Kaiju.Height
	local distance = 16 + height * 2.2
	player.CameraMaxZoomDistance = math.max(distance + 25, active.Saved.MaxZoom)
	player.CameraMinZoomDistance = distance
	if humanoid then
		humanoid.CameraOffset = Vector3.new(0, height * 0.45, 0)
	end
	hideGuis()
	RampageHud.Show(args, { Stomp = RampageController.Stomp, Roar = RampageController.Roar, Leave = RampageController.Leave })
	RampageHud.Banner("RAMPAGE!", ("%s • %s"):format(string.upper(args.DistrictName), "SMASH EVERYTHING!"), C.Magma, 2)
	table.insert(active.Conns, RunService.RenderStepped:Connect(step))
	table.insert(active.Conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.F then
			RampageController.Stomp()
		elseif input.KeyCode == Enum.KeyCode.R then
			RampageController.Roar()
		end
	end))
	Audio.Music("music_boss")
	Audio.Play("roar_big")
	CameraFx.Shake(1.5, 0.6)
	CameraFx.FovPunch(14, 0.8)
end

local function onSmash(args: any)
	if not active then
		return
	end
	local low = lowFx()
	local height = args.Size.Y
	debris(args.Position, args.Size, args.Color, if low then 4 else math.clamp(math.floor(4 + height * 0.5), 6, 14))
	Effects.Dust(args.Position, math.max(args.Size.X, args.Size.Z) * 0.6)
	if args.Golden then
		Effects.Burst(args.Position + Vector3.new(0, height / 2, 0), C.Gold, 40, 3)
		Effects.Pillar(args.Position, C.Gold, 1.5)
		Effects.FloatingText(args.Position + Vector3.new(0, height + 8, 0), if args.Egg then "🥚 EGG CRATE!" else "GOLDEN!", C.Gold, 1.4)
		Audio.Play("spin_win")
	end
	Effects.FloatingText(args.Position + Vector3.new(0, height + 3, 0), "+" .. Format.Cash(args.Cash or 0), C.Cash, 0.9 + math.min(height, 24) / 40)
	CameraFx.ShakeAt(args.Position, 0.6 + height * 0.06, 140, 0.35)
	Audio.Play("meteor_impact", { Volume = 0.35 + math.min(height, 24) / 40, Pitch = 1.4 - math.min(height, 24) / 40, Cooldown = 0.05 })
	if (args.ComboCount or 0) >= 1 then
		Audio.Play("coin_tick", { Pitch = 1 + math.min(args.ComboCount, 20) * 0.04, Cooldown = 0.03 })
	end
	RampageHud.Smash(args, serverNow())
end

local function onHit(args: any)
	if not active then
		return
	end
	local model = buildingModel(args.Id)
	local body = model and model.PrimaryPart
	if body then
		hpBar(body, args.Height, args.HP / args.MaxHP)
	end
	debris(args.Position + Vector3.new(0, args.Height * 0.5, 0), Vector3.new(2, 1, 2), C.Paper, if lowFx() then 1 else 3)
	Effects.Poof(args.Position + Vector3.new(0, args.Height * 0.6, 0), 1.5)
	Audio.Play("bonk", { Volume = 0.4, Pitch = 1.3, Cooldown = 0.05 })
end

local function onTank(args: any)
	if not active then
		return
	end
	local tank = buildTank(args)
	active.Tanks[args.Id] = tank
	hpBar(tank.Body, 2, 1)
	Effects.FloatingText(args.From + Vector3.new(0, 6, 0), "TOY TANK!", C.Radioactive, 1)
	Audio.Play("event_horn", { Volume = 0.35, Pitch = 1.6 })
end

local function onTankHit(args: any)
	local tank = active and active.Tanks[args.Id]
	if tank then
		hpBar(tank.Body, 2, args.HP / args.MaxHP)
		Effects.Poof(tank.Body.Position, 1.5)
	end
end

local function onTankDown(args: any)
	if not active then
		return
	end
	local tank = active.Tanks[args.Id]
	if tank then
		active.Tanks[args.Id] = nil
		tank.Model:Destroy()
	end
	Effects.Impact(args.Position, C.Magma, 2)
	debris(args.Position, Vector3.new(4, 2, 5), Color3.fromRGB(120, 190, 90), if lowFx() then 3 else 8)
	Effects.FloatingText(args.Position + Vector3.new(0, 7, 0), ("+%ds"):format(args.Bonus), C.Radioactive, 1.2)
	RampageHud.SetEndsAt(args.EndsAt)
	RampageHud.TimeDelta(args.Bonus)
	RampageHud.Cash(args.Cash or 0)
	Audio.Play("meteor_impact", { Volume = 0.6 })
end

local function onDart(args: any)
	if not active then
		return
	end
	active.Darts[args.Id] = buildDart(args, Rampage.DartRadius(active.Args.Scale))
	Audio.Play("whoosh", { Volume = 0.35, Pitch = 1.5, Cooldown = 0.1 })
end

local function onDartHit(args: any)
	if not active then
		return
	end
	RampageHud.SetEndsAt(args.EndsAt)
	RampageHud.TimeDelta(-args.Penalty)
	RampageHud.Flash(C.Red)
	CameraFx.Shake(1.2, 0.3)
	Effects.FloatingText(args.Position + Vector3.new(0, 6, 0), ("-%ds!"):format(args.Penalty), C.Red, 1.1)
	Audio.Play("shield_zap", { Volume = 0.8 })
end

local BANNERS = {
	Time = { "TIME'S UP!", C.Gold },
	Flattened = { "CITY FLATTENED!", C.Radioactive },
	Died = { "KNOCKED OUT!", C.Red },
	Left = { "OUT OF THE CITY!", C.Red },
}

local function onEnd(args: any)
	lastResult = args
	if not active then
		return
	end
	active.Ended = true
	local banner = BANNERS[args.Reason]
	if banner then
		RampageHud.Banner(banner[1], ("DESTRUCTION %d%%"):format(Rampage.Percent(args.Destruction)), banner[2], Rampage.EndDelay + 1)
		Audio.Play(if args.Reason == "Flattened" then "heist_success" else "event_horn")
		CameraFx.Shake(1, 0.5)
	end
end

local function onHome()
	stop()
	local result = lastResult
	lastResult = nil
	local screen = rampageScreen()
	if result and screen then
		screen.ShowResults(result)
	end
end

function RampageController.Init()
	FxBus.On("RampageOpen", function()
		RampageController.Open()
	end)
	FxBus.On("RampageStart", onStart)
	FxBus.On("RampageSmash", onSmash)
	FxBus.On("RampageHit", onHit)
	FxBus.On("RampageStar", function(args)
		RampageHud.Star(args.Stars)
		if active then
			local root = rootOf()
			if root then
				Effects.FloatingText(root.Position + Vector3.new(0, active.Kaiju.Height + 6, 0), ("⭐ %d STAR%s!"):format(args.Stars, if args.Stars > 1 then "S" else ""), C.Gold, 1.5)
			end
		end
	end)
	FxBus.On("RampageTank", onTank)
	FxBus.On("RampageTankHit", onTankHit)
	FxBus.On("RampageTankDown", onTankDown)
	FxBus.On("RampageDart", onDart)
	FxBus.On("RampageDartHit", onDartHit)
	FxBus.On("RampageEnd", onEnd)
	FxBus.On("RampageHome", onHome)
end

return RampageController
