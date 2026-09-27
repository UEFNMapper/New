--!nonstrict
-- Rendu local de la défense de l'île : mini-kaijus sauvages (positions
-- calculées à partir des attributs D0/T0/Speed/Dir, comme le serveur), barres
-- de vie, sacs de cash volés, orbes de cash, tirs des kaijus-tours (projectiles
-- couleur de rareté, chiffres de dégâts, éclaboussures), bonks et morts.
-- Initialise aussi le HUD de siège (UI/SiegeHud).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Siege = require(Shared.Config.Siege)
local Layout = require(Shared.Config.Layout)
local Rarities = require(Shared.Config.Rarities)
local Theme = require(Shared.Config.Theme)
local KaijuBuilder = require(Shared.KaijuBuilder)
local Format = require(Shared.Logic.Format)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local CameraFx = require(Controllers.CameraFx)
local Effects = require(script.Parent.Effects)
local KaijuRenderer = require(script.Parent.KaijuRenderer)
local SiegeHud = require(script.Parent.Parent.UI.SiegeHud)

local C = Theme.Colors
local player = Players.LocalPlayer

local SiegeRenderer = {}

type Invader = {
	Anchor: BasePart,
	PlotCf: CFrame,
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame },
	Colors: { Color3 },
	Height: number,
	Scale: number,
	Speed: number,
	Phase: number,
	Shown: number?,
	ShownPath: string?,
	Current: CFrame,
	Bar: BillboardGui,
	Fill: Frame,
	BagPart: BasePart?,
	Marker: BasePart,
	HopAt: number,
	FlinchAt: number,
	Killed: boolean,
}

type Orb = { Anchor: BasePart, Part: BasePart, Base: Vector3, Phase: number }

type Shot = { Part: BasePart, From: Vector3, Target: Invader?, Fallback: Vector3, T0: number, Duration: number, Damage: number, Color: Color3, Splash: boolean }

local folder: Folder
local invaders: { [BasePart]: Invader } = {}
local byId: { [string]: Invader } = {}
local orbs: { [BasePart]: Orb } = {}
local shots: { Shot } = {}
local numbersBudget = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function lowFx(): boolean
	local s = State.Get("Settings")
	return s ~= nil and s.LowFx == true
end

----------------------------------------------------------------------------
-- Envahisseurs
----------------------------------------------------------------------------

local function wildTint(model: Model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Material ~= Enum.Material.Neon then
			p.Color = p.Color:Lerp(Siege.WildTint, Siege.WildTintAmount)
		end
	end
end

local function healthBar(entry: Invader, alpha: boolean)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SiegeBar"
	gui.Size = if alpha then UDim2.fromOffset(120, 34) else UDim2.fromOffset(64, 22)
	gui.StudsOffset = Vector3.new(0, entry.Height + 1.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = if alpha then 220 else 110
	gui.AlwaysOnTop = false
	gui.Adornee = entry.Model.PrimaryPart
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, 0, 0, if alpha then 14 else 10)
	bar.Position = UDim2.new(0, 0, 1, if alpha then -14 else -10)
	bar.BackgroundColor3 = C.Ink
	bar.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if alpha then C.Gold else C.Radioactive
	fill.BorderSizePixel = 0
	corner:Clone().Parent = fill
	fill.Parent = bar
	bar.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Tag"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, if alpha then -14 else -10)
	label.FontFace = Theme.Fonts.Impact
	label.TextScaled = true
	label.TextColor3 = if alpha then C.Gold else C.Red
	label.Text = if alpha then "👑 ALPHA" else ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = C.Ink
	stroke.Parent = label
	label.Parent = gui
	gui.Enabled = alpha
	gui.Parent = entry.Model.PrimaryPart
	entry.Bar = gui
	entry.Fill = fill
end

local function refreshBar(entry: Invader)
	local anchor = entry.Anchor
	local hp = anchor:GetAttribute("HP") or 0
	local max = math.max(anchor:GetAttribute("MaxHP") or 1, 1)
	local ratio = math.clamp(hp / max, 0, 1)
	entry.Fill.Size = UDim2.fromScale(ratio, 1)
	if not anchor:GetAttribute("Alpha") then
		entry.Fill.BackgroundColor3 = if ratio > 0.5 then C.Radioactive elseif ratio > 0.25 then C.Gold else C.Red
		entry.Bar.Enabled = ratio < 0.999 or (anchor:GetAttribute("Bag") or 0) > 0
	end
	local tag = entry.Bar:FindFirstChild("Tag") :: TextLabel?
	if tag and not anchor:GetAttribute("Alpha") then
		tag.Text = if (anchor:GetAttribute("Bag") or 0) > 0 then "💰 BONK ME!" else ""
	end
end

local function refreshBag(entry: Invader)
	local bag = entry.Anchor:GetAttribute("Bag") or 0
	if bag > 0 and not entry.BagPart then
		local p = Instance.new("Part")
		p.Name = "CashBag"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(2.2, 2.2, 2.2)
		p.Color = Color3.fromRGB(190, 150, 90)
		p.Material = Enum.Material.Fabric
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = entry.Model
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(40, 40)
		gui.LightInfluence = 0
		gui.MaxDistance = 140
		gui.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Text = "💰"
		label.Parent = gui
		gui.Parent = p
		if not lowFx() then
			Effects.Sparkles(p, C.Cash, 8)
		end
		entry.BagPart = p
	elseif bag <= 0 and entry.BagPart then
		entry.BagPart:Destroy()
		entry.BagPart = nil
	end
	refreshBar(entry)
end

local function track(anchor: BasePart, plotCf: CFrame)
	if invaders[anchor] then
		return
	end
	local scale = anchor:GetAttribute("Scale") or 0.7
	local species = anchor:GetAttribute("Species") or "Gloop"
	local id = tostring(anchor:GetAttribute("Id") or anchor.Name)
	local model = KaijuBuilder.Build(species, nil, scale)
	model.Name = "Wild_" .. id
	wildTint(model)
	local alpha = anchor:GetAttribute("Alpha") == true
	if alpha and model.PrimaryPart and not lowFx() then
		Effects.Sparkles(model.PrimaryPart, C.Gold, 10)
	end
	local parts, offsets, colors = {}, {}, {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= model.PrimaryPart then
			table.insert(parts, p)
			table.insert(offsets, p.CFrame)
			table.insert(colors, p.Color)
		end
	end
	-- disque « ennemi » au sol : on distingue d'un coup d'œil les sauvages de ses kaijus
	local marker = Instance.new("Part")
	marker.Name = "EnemyMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.12, 2.6 * scale + 1.2, 2.6 * scale + 1.2)
	marker.Color = if alpha then C.Gold else C.Red
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.45
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Parent = model
	local speed = anchor:GetAttribute("Speed") or 8
	local entry: Invader = {
		Anchor = anchor,
		PlotCf = plotCf,
		Model = model,
		Parts = parts,
		Offsets = offsets,
		Colors = colors,
		Height = KaijuBuilder.Height(species) * scale,
		Scale = scale,
		Speed = speed,
		Phase = math.random() * 10,
		Shown = nil,
		ShownPath = nil,
		Current = anchor.CFrame,
		Bar = nil :: any,
		Fill = nil :: any,
		BagPart = nil,
		Marker = marker,
		HopAt = 0,
		FlinchAt = 0,
		Killed = false,
	}
	healthBar(entry, alpha)
	model.Parent = folder
	invaders[anchor] = entry
	byId[id] = entry
	anchor.AttributeChanged:Connect(function(attr)
		if attr == "HP" then
			refreshBar(entry)
		elseif attr == "Bag" then
			refreshBag(entry)
		end
	end)
	refreshBag(entry)
	-- arrivée : chute depuis un petit météore au portail
	local gate = (plotCf * CFrame.new(0, 0, -Layout.PlotDepth / 2 + 4)).Position
	if not lowFx() then
		Effects.Dust(gate, 2 + scale * 2)
	end
	Audio.Play("roar_small", { Parent = anchor, Pitch = if alpha then 0.7 else 1.7, Cooldown = 0.15 })
	if alpha then
		Effects.Impact(gate, C.Red, 6)
		CameraFx.ShakeAt(gate, 1.2, 160, 0.8)
		Audio.Play("roar_big", { Parent = anchor, MaxDistance = 300 })
	end
end

local function untrack(anchor: BasePart)
	local entry = invaders[anchor]
	if not entry then
		return
	end
	invaders[anchor] = nil
	for id, e in byId do
		if e == entry then
			byId[id] = nil
		end
	end
	local function vanish()
		local pos = entry.Current.Position + Vector3.new(0, entry.Height / 2, 0)
		Effects.Poof(pos, 2 + entry.Scale * 2)
		if entry.Killed then
			Effects.Burst(pos, Siege.WildTint, if lowFx() then 8 else 22, 1 + entry.Scale)
		end
		entry.Model:Destroy()
	end
	if entry.Killed then
		-- petit arrêt sur image : le dernier tir arrive, puis pouf
		task.delay(0.25, vanish)
	else
		vanish()
	end
end

-- Place un envahisseur à l'image courante.
local function animate(entry: Invader, dt: number, t: number, serverT: number)
	local anchor = entry.Anchor
	local pathName = anchor:GetAttribute("Path") or "In"
	local path = Siege.GetPath(pathName)
	local dir = anchor:GetAttribute("Dir") or 1
	local d = Siege.Distance(path, anchor:GetAttribute("D0") or 0, anchor:GetAttribute("T0") or serverT, anchor:GetAttribute("Speed") or 8, dir, serverT)
	-- lissage (recul d'un bonk) ; changement de chemin = saut direct
	if entry.ShownPath ~= pathName or not entry.Shown or math.abs(d - entry.Shown) > 30 then
		entry.Shown = d
		entry.ShownPath = pathName
	else
		entry.Shown += (d - entry.Shown) * math.min(1, dt * 10)
	end
	local pos, forward = Siege.PathAt(path, entry.Shown :: number)
	local s = entry.Scale
	local speed = anchor:GetAttribute("Speed") or 8
	local stride = t * (4 + speed * 0.6) + entry.Phase
	local bob = math.abs(math.sin(stride)) * 0.35 * s
	local hopAge = t - entry.HopAt
	local knock = if hopAge < 0.45 then math.sin(hopAge / 0.45 * math.pi) * 2.5 else 0
	local flinchAge = t - entry.FlinchAt
	local flinch = if flinchAge < 0.15 then math.sin(flinchAge / 0.15 * math.pi) * 0.4 * s else 0
	local lift = bob + knock + flinch
	local world = entry.PlotCf * CFrame.new(pos.X, pos.Y + lift, pos.Z)
	local look = entry.PlotCf:VectorToWorldSpace(forward * dir)
	local cf = CFrame.lookAt(world.Position, world.Position + look) * CFrame.Angles(0, 0, math.sin(stride) * 0.12)
	if knock > 0 then
		cf *= CFrame.Angles(0, hopAge * 14, 0)
	end
	entry.Current = cf
	local cfs = table.create(#entry.Parts)
	for i, offset in entry.Offsets do
		cfs[i] = cf * offset
	end
	Workspace:BulkMoveTo(entry.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if entry.Model.PrimaryPart then
		entry.Model.PrimaryPart.CFrame = cf
	end
	entry.Marker.CFrame = CFrame.new(cf.Position - Vector3.new(0, pos.Y + lift - 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	if entry.BagPart then
		entry.BagPart.CFrame = cf * CFrame.new(0, entry.Height + 1.4 + math.sin(t * 6) * 0.2, 0.6)
	end
end

----------------------------------------------------------------------------
-- Orbes
----------------------------------------------------------------------------

local function trackOrb(anchor: BasePart)
	if orbs[anchor] then
		return
	end
	local mine = anchor:GetAttribute("Owner") == player.UserId
	local p = Instance.new("Part")
	p.Name = "SiegeOrb"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.5, 2.4, 2.4)
	p.Color = C.Gold
	p.Material = Enum.Material.Neon
	p.Transparency = if mine then 0 else 0.6
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = anchor.CFrame
	p.Parent = folder
	if mine then
		local light = Instance.new("PointLight")
		light.Color = C.Gold
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = p
		if not lowFx() then
			Effects.Sparkles(p, C.Cash, 5)
		end
	end
	orbs[anchor] = { Anchor = anchor, Part = p, Base = anchor.Position, Phase = math.random() * 6 }
end

local function untrackOrb(anchor: BasePart)
	local orb = orbs[anchor]
	if orb then
		orbs[anchor] = nil
		orb.Part:Destroy()
	end
end

----------------------------------------------------------------------------
-- Tirs
----------------------------------------------------------------------------

local function damageNumber(pos: Vector3, amount: number, color: Color3, small: boolean)
	if numbersBudget <= 0 then
		return
	end
	numbersBudget -= 1
	Effects.FloatingText(pos, Format.Short(math.max(1, math.floor(amount + 0.5))), color, if small then 0.45 else 0.6)
end

local function launch(from: Vector3, target: Invader?, fallback: Vector3, damage: number, color: Color3, splash: boolean)
	local p = Instance.new("Part")
	p.Name = "SiegeShot"
	p.Shape = Enum.PartType.Ball
	p.Size = if splash then Vector3.new(1.6, 1.6, 1.6) else Vector3.new(1, 1, 1)
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = CFrame.new(from)
	p.Parent = folder
	if not lowFx() then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.3, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.3, 0)
		a1.Parent = p
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.2
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Parent = p
	end
	table.insert(shots, { Part = p, From = from, Target = target, Fallback = fallback, T0 = os.clock(), Duration = 0.28, Damage = damage, Color = color, Splash = splash })
end

local function impact(shot: Shot, pos: Vector3)
	shot.Part:Destroy()
	local target = shot.Target
	if target and target.Model.Parent then
		target.FlinchAt = os.clock() -- petit sursaut
		-- éclair blanc sur le modèle
		for i, part in target.Parts do
			if i % 3 == 0 then
				part.Color = C.White
			end
		end
		task.delay(0.08, function()
			for i, part in target.Parts do
				part.Color = target.Colors[i]
			end
		end)
	end
	if not lowFx() then
		Effects.Burst(pos, shot.Color, if shot.Splash then 16 else 6, if shot.Splash then 1.6 else 0.8)
	end
	if shot.Splash then
		Effects.Shockwave(pos - Vector3.new(0, 1.5, 0), shot.Color, Siege.SplashRadius, 0.4)
	end
	damageNumber(pos + Vector3.new(0, 2, 0), shot.Damage, if shot.Splash then C.Magma else C.Gold, false)
	Audio.Play("shield_zap", { Pitch = 1.9, Volume = 0.35, Cooldown = 0.06 })
end

local function stepShots()
	local t = os.clock()
	for i = #shots, 1, -1 do
		local shot = shots[i]
		local target = shot.Target
		local goal = if target and target.Model.Parent then target.Current.Position + Vector3.new(0, target.Height * 0.5, 0) else shot.Fallback
		local a = math.clamp((t - shot.T0) / shot.Duration, 0, 1)
		if a >= 1 then
			table.remove(shots, i)
			impact(shot, goal)
		else
			local p = shot.From:Lerp(goal, a) + Vector3.new(0, math.sin(a * math.pi) * 3, 0)
			shot.Part.CFrame = CFrame.new(p)
		end
	end
end

local function onShots(args)
	for _, s in args.Shots or {} do
		local target = byId[s.I or ""]
		local goal = if target then target.Current.Position + Vector3.new(0, target.Height * 0.5, 0) else nil
		if goal then
			if s.S then
				-- victime d'éclaboussure : chiffre seulement
				task.delay(0.28, function()
					damageNumber(goal + Vector3.new(0, 1.5, 0), s.D or 0, C.Magma, true)
				end)
			elseif s.U then
				local from = KaijuRenderer.Aim(s.U, goal)
				if from then
					local tower = KaijuRenderer.ByUid(s.U)
					local rarity = Rarities.Get(if tower then tower.Anchor:GetAttribute("Rarity") or "Common" else "Common")
					launch(from, target, goal, s.D or 0, rarity.Color, s.X == true)
					Audio.Play("whoosh", { Parent = tower and tower.Anchor, Pitch = 1.8, Volume = 0.4, Cooldown = 0.08 })
				end
			elseif typeof(s.P) == "Vector3" then
				launch(s.P + Vector3.new(0, 2, 0), target, goal, s.D or 0, C.Cyan, false)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Tracé du chemin (pointillés rouges au sol pendant une vague)
----------------------------------------------------------------------------

local trails: { [Instance]: Folder } = {}

local function buildTrail(plotFolder: Instance, plotCf: CFrame): Folder
	local trail = Instance.new("Folder")
	trail.Name = "SiegeTrail"
	local path = if plotFolder:GetAttribute("Tutorial") then Siege.TutorialPath else Siege.In
	local step = if lowFx() then 9 else 5
	for d = 3, path.Length - 2, step do
		local pos, dir = Siege.PathAt(path, d)
		if pos.Y < 0.05 then -- pas de pointillés sur les bonds (clôtures)
			local world = plotCf * CFrame.new(pos.X, 0.08, pos.Z)
			local look = plotCf:VectorToWorldSpace(dir)
			local dash = Instance.new("Part")
			dash.Name = "Dash"
			dash.Size = Vector3.new(0.7, 0.06, 2.2)
			dash.Color = C.Red
			dash.Material = Enum.Material.Neon
			dash.Transparency = 0.55
			dash.Anchored = true
			dash.CanCollide = false
			dash.CanQuery = false
			dash.CanTouch = false
			dash.CastShadow = false
			dash.CFrame = CFrame.lookAt(world.Position, world.Position + look)
			dash.Parent = trail
		end
	end
	trail.Parent = folder
	return trail
end

local function refreshTrail(plotFolder: Instance, plotCf: CFrame)
	local active = plotFolder:GetAttribute("State") == "Active"
	local trail = trails[plotFolder]
	if active and not trail then
		trails[plotFolder] = buildTrail(plotFolder, plotCf)
	elseif not active and trail then
		trails[plotFolder] = nil
		trail:Destroy()
	end
end

----------------------------------------------------------------------------
-- Dossiers des îles
----------------------------------------------------------------------------

local function watchPlot(plotFolder: Instance)
	local index = plotFolder:GetAttribute("Plot") or tonumber(string.match(plotFolder.Name, "%d+"))
	if not index then
		return
	end
	local plotCf = Layout.PlotCFrame(index)
	local function add(child: Instance)
		if not child:IsA("BasePart") then
			return
		end
		local kind = child:GetAttribute("Kind")
		if kind == "Invader" then
			track(child, plotCf)
		elseif kind == "Orb" then
			trackOrb(child)
		end
	end
	for _, child in plotFolder:GetChildren() do
		add(child)
	end
	plotFolder.ChildAdded:Connect(function(child)
		task.wait() -- attend les attributs
		add(child)
	end)
	plotFolder.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			untrack(child)
			untrackOrb(child)
		end
	end)
	plotFolder:GetAttributeChangedSignal("State"):Connect(function()
		refreshTrail(plotFolder, plotCf)
	end)
	refreshTrail(plotFolder, plotCf)
end

function SiegeRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientSiege"
	folder.Parent = Workspace

	SiegeHud.Init()

	local root = Workspace:WaitForChild("Siege")
	for _, f in root:GetChildren() do
		watchPlot(f)
	end
	root.ChildAdded:Connect(watchPlot)

	FxBus.On("SiegeShots", onShots)
	FxBus.On("SiegeBonk", function(args)
		local entry = byId[args.Id or ""]
		if entry then
			entry.HopAt = os.clock()
			local pos = entry.Current.Position + Vector3.new(0, entry.Height * 0.6, 0)
			Effects.FloatingText(pos + Vector3.new(0, 2, 0), "BONK! " .. Format.Short(math.floor((args.Damage or 0) + 0.5)), C.Pink, 0.8)
			Effects.Burst(pos, C.Pink, 14, 1.2)
			Audio.Play("bonk", { Parent = entry.Anchor })
			if args.UserId == player.UserId then
				CameraFx.Shake(0.35, 0.2)
			end
		end
	end)
	FxBus.On("SiegeKill", function(args)
		local entry = byId[args.Id or ""]
		if entry then
			entry.Killed = true
		end
		local pos = if typeof(args.Position) == "Vector3" then args.Position else nil
		if pos then
			Audio.Play("egg_crack", { Pitch = if args.Alpha then 0.7 else 1.5, Volume = 0.6, Cooldown = 0.05 })
			if args.Alpha then
				Effects.Impact(pos, C.Gold, 8)
				Effects.Pillar(pos, C.Gold, 2)
				CameraFx.ShakeAt(pos, 1.5, 200, 0.8)
				Audio.Play("roar_big")
			end
		end
	end)
	FxBus.On("SiegeLeak", function(args)
		local entry = byId[args.Id or ""]
		if entry then
			Effects.Pillar(entry.Current.Position, C.Red, 1.5)
			Effects.FloatingText(entry.Current.Position + Vector3.new(0, entry.Height + 3, 0), if (args.Amount or 0) > 0 then "-" .. Format.Cash(args.Amount) else "HEHEHE!", C.Red, 0.9)
		end
	end)
	FxBus.On("SiegeBagSaved", function(args)
		local entry = byId[args.Id or ""]
		local pos = if entry then entry.Current.Position + Vector3.new(0, entry.Height + 2, 0) else nil
		if pos then
			Effects.FloatingText(pos, "SAVED +" .. Format.Cash(args.Amount or 0), C.Cash, 1)
			Effects.Burst(pos, C.Cash, 24, 1.5)
			Audio.Play("cash_collect")
		end
	end)
	FxBus.On("SiegeOrb", function(args)
		local pos = if typeof(args.Position) == "Vector3" then args.Position else nil
		if pos then
			Effects.FloatingText(pos + Vector3.new(0, 2, 0), "+" .. Format.Cash(args.Amount or 0), C.Cash, 0.7)
			Effects.Burst(pos, C.Gold, 10, 1)
		end
		Audio.Play("coin_tick", { Cooldown = 0.05 })
	end)
	FxBus.On("SiegeWaveStart", function(args)
		local index = args.Plot
		if not index then
			return
		end
		local gate = (Layout.PlotCFrame(index) * CFrame.new(0, 0, -Layout.PlotDepth / 2 + 4)).Position
		Effects.Impact(gate, C.Radioactive, 4)
		Effects.Pillar(gate, C.Red, 2.5)
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local serverT = now()
		numbersBudget = math.min(numbersBudget + dt * 14, 10)
		for _, entry in invaders do
			animate(entry, dt, t, serverT)
		end
		for _, orb in orbs do
			local y = math.sin(t * 3 + orb.Phase) * 0.4
			orb.Part.CFrame = CFrame.new(orb.Base + Vector3.new(0, y, 0)) * CFrame.Angles(0, t * 3 + orb.Phase, 0)
		end
		stepShots()
	end)
end

return SiegeRenderer
