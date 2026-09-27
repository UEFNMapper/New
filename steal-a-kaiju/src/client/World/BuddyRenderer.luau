--!nonstrict
-- Compagnons (Buddy) côté client : chaque client dessine le mini-kaiju de
-- chaque joueur à partir de ses attributs (BuddyUid, BuddySpecies,
-- BuddyMutation, BuddyLevel) et le fait suivre son propriétaire (aucune
-- position répliquée). Gère aussi, pour le joueur local : le trésor privé
-- (butte, faisceau, flèches au sol, compte à rebours), les effets de fouille,
-- les orbes aspirées par l'aimant, les bonds d'attaque et la pastille HUD.
--   BuddyRenderer.Chip()      -> pastille HUD (à repositionner si besoin)
--   BuddyRenderer.Celebrate() -> saut de joie du compagnon local
--   BuddyRenderer.Model(userId?) -> modèle 3D du compagnon

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local KaijuBuilder = require(Shared.KaijuBuilder)
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Buddy = require(Shared.Config.Buddy)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Logic.Format)

local Controllers = script.Parent.Parent.Controllers
local State = require(Controllers.State)
local Audio = require(Controllers.Audio)
local FxBus = require(Controllers.FxBus)
local CameraFx = require(Controllers.CameraFx)
local UIRegistry = require(Controllers.UIRegistry)
local Kit = require(script.Parent.Parent.UI.Kit)
local Hud = require(script.Parent.Parent.UI.Hud)
local Viewport = require(script.Parent.Parent.UI.Viewport)
local Effects = require(script.Parent.Effects)
local Guide = require(script.Parent.Guide)

local C = Theme.Colors
local F = Theme.Fonts
local player = Players.LocalPlayer

local DIRT = Color3.fromRGB(120, 80, 45)

local BuddyRenderer = {}

type Pet = {
	Owner: Player,
	Key: string,
	Model: Model?,
	Parts: { BasePart },
	Offsets: { CFrame },
	Roles: { string },
	Pivots: { [string]: Vector3 },
	Scale: number,
	Height: number,
	Gui: BillboardGui?,
	Pos: Vector3?,
	Yaw: number,
	Phase: number,
	Joy: number, -- os.clock du dernier saut de joie
	Pounce: { From: Vector3, To: Vector3, Start: number, Hit: boolean }?,
	DigAt: Vector3?,
	NextDust: number,
}

local pets: { [Player]: Pet } = {}
local folder: Folder
local guide: any = nil

-- Trésor local
local spot: { Part: BasePart, Model: Model, Timer: TextLabel, Position: Vector3 }? = nil

-- Pastille HUD
local chip: { [string]: any } = {}

----------------------------------------------------------------------------
-- Construction du modèle
----------------------------------------------------------------------------

local function attr(p: Player, name: string): string?
	local v = p:GetAttribute(name)
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

local function levelOf(p: Player): number
	local v = p:GetAttribute("BuddyLevel")
	return if type(v) == "number" then v else 1
end

local function keyOf(p: Player): string
	local species = attr(p, "BuddySpecies")
	if not species then
		return ""
	end
	return table.concat({ species, attr(p, "BuddyMutation") or "", tostring(levelOf(p)) }, "|")
end

local function buildGui(pet: Pet): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "BuddyGui"
	gui.Size = UDim2.fromOffset(120, 90)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.AlwaysOnTop = false
	gui.StudsOffsetWorldSpace = Vector3.new(0, pet.Height + 1.2, 0)
	-- bulle « ! » (aboiement quand un trésor est flairé)
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.fromOffset(52, 52)
	bubble.Position = UDim2.fromScale(0.5, 0)
	bubble.AnchorPoint = Vector2.new(0.5, 0)
	bubble.BackgroundColor3 = C.Gold
	bubble.Visible = false
	Kit.Round().Parent = bubble
	Kit.Stroke(4).Parent = bubble
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.FontFace = F.Impact
	mark.TextScaled = true
	mark.Text = "!"
	mark.TextColor3 = C.Ink
	mark.Parent = bubble
	bubble.Parent = gui
	-- niveau
	local level = Instance.new("TextLabel")
	level.Name = "Level"
	level.BackgroundTransparency = 1
	level.Size = UDim2.new(1, 0, 0, 24)
	level.Position = UDim2.new(0, 0, 1, -24)
	level.FontFace = F.Title
	level.TextScaled = true
	level.TextColor3 = if pet.Owner == player then C.Radioactive else C.Paper
	level.Text = ("★ LV %d"):format(levelOf(pet.Owner))
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = C.Ink
	stroke.Parent = level
	level.Parent = gui
	gui.Parent = folder
	return gui
end

local function clearModel(pet: Pet, poof: boolean)
	if pet.Model then
		if poof and pet.Pos then
			Effects.Poof(pet.Pos + Vector3.new(0, 1, 0), 2)
		end
		pet.Model:Destroy()
		pet.Model = nil
	end
	if pet.Gui then
		pet.Gui:Destroy()
		pet.Gui = nil
	end
	pet.Parts = {}
	pet.Offsets = {}
	pet.Roles = {}
	pet.Pivots = {}
end

local function rebuild(pet: Pet)
	local key = keyOf(pet.Owner)
	if key == pet.Key then
		return
	end
	local hadModel = pet.Model ~= nil
	clearModel(pet, hadModel)
	pet.Key = key
	local species = attr(pet.Owner, "BuddySpecies")
	if not species then
		return
	end
	local scale = Buddy.ModelScale(levelOf(pet.Owner))
	local model = KaijuBuilder.Build(species, attr(pet.Owner, "BuddyMutation"), scale)
	model.Name = "Buddy_" .. pet.Owner.UserId
	model:SetAttribute("Owner", pet.Owner.UserId)
	pet.Model = model
	pet.Scale = scale
	pet.Height = KaijuBuilder.Height(species) * scale
	local sums: { [string]: Vector3 } = {}
	local counts: { [string]: number } = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			table.insert(pet.Parts, p)
			table.insert(pet.Offsets, p.CFrame)
			local role = p:GetAttribute("Role")
			role = if type(role) == "string" then role else ""
			table.insert(pet.Roles, role)
			if role ~= "" then
				sums[role] = (sums[role] or Vector3.zero) + p.Position
				counts[role] = (counts[role] or 0) + 1
			end
		end
	end
	for role, sum in sums do
		pet.Pivots[role] = sum / counts[role]
	end
	model.Parent = folder
	local gui = buildGui(pet)
	gui.Adornee = model.PrimaryPart
	pet.Gui = gui
	if hadModel and pet.Pos then
		Effects.Burst(pet.Pos + Vector3.new(0, pet.Height / 2, 0), C.Pink, 20, 1.5)
	end
end

local function track(p: Player)
	if pets[p] then
		return
	end
	local pet: Pet = {
		Owner = p,
		Key = "",
		Model = nil,
		Parts = {},
		Offsets = {},
		Roles = {},
		Pivots = {},
		Scale = Buddy.Scale,
		Height = 3,
		Gui = nil,
		Pos = nil,
		Yaw = 0,
		Phase = math.random() * 10,
		Joy = 0,
		Pounce = nil,
		DigAt = nil,
		NextDust = 0,
	}
	pets[p] = pet
	rebuild(pet)
	p.AttributeChanged:Connect(function(name)
		if name == "BuddySpecies" or name == "BuddyMutation" or name == "BuddyLevel" or name == "BuddyUid" then
			rebuild(pet)
			if pet.Gui then
				local level = pet.Gui:FindFirstChild("Level") :: TextLabel?
				if level then
					level.Text = ("★ LV %d"):format(levelOf(p))
				end
			end
		end
	end)
end

local function untrack(p: Player)
	local pet = pets[p]
	if pet then
		pets[p] = nil
		clearModel(pet, true)
	end
end

----------------------------------------------------------------------------
-- Animation
----------------------------------------------------------------------------

local function angleLerp(a: number, b: number, alpha: number): number
	local d = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + d * alpha
end

local function yawTowards(dir: Vector3, fallback: number): number
	if Vector3.new(dir.X, 0, dir.Z).Magnitude < 0.05 then
		return fallback
	end
	return math.atan2(-dir.X, -dir.Z)
end

local function animate(pet: Pet, dt: number, t: number, camPos: Vector3)
	local model = pet.Model
	local character = pet.Owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not model or not root then
		return
	end
	local rootCf = root.CFrame
	local _, ownerYaw = rootCf:ToEulerAnglesYXZ()
	local ground = rootCf.Position.Y - 3
	local follow = (CFrame.new(rootCf.Position) * CFrame.Angles(0, ownerYaw, 0) * CFrame.new(Buddy.FollowOffset)).Position
	local goal = Vector3.new(follow.X, ground, follow.Z)
	if pet.DigAt then
		-- il creuse à côté du trou, du côté du joueur
		local side = Vector3.new(rootCf.Position.X - pet.DigAt.X, 0, rootCf.Position.Z - pet.DigAt.Z)
		local dir = if side.Magnitude > 0.1 then side.Unit else Vector3.new(1, 0, 0)
		goal = Vector3.new(pet.DigAt.X, ground, pet.DigAt.Z) + dir * 2.2
	end

	local pos = pet.Pos
	if not pos or (pos - goal).Magnitude > Buddy.SnapDistance then
		if pos then
			Effects.Poof(goal + Vector3.new(0, 1, 0), 2)
		end
		pos = goal
	end
	local prev = pos :: Vector3
	local newPos = prev:Lerp(goal, 1 - math.exp(-Buddy.FollowSharpness * dt))
	pet.Pos = newPos
	local vel = (newPos - prev) / math.max(dt, 1e-3)
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local moving = math.clamp(speed / 6, 0, 1)

	-- regard : vers la direction de marche, sinon vers le joueur et autour
	local desired
	if pet.DigAt then
		desired = yawTowards(pet.DigAt - newPos, pet.Yaw)
	elseif speed > 0.8 then
		desired = yawTowards(vel, pet.Yaw)
	else
		desired = yawTowards(rootCf.Position - newPos, pet.Yaw) + math.sin(t * 0.6 + pet.Phase) * 0.7
	end

	local s = pet.Scale
	local lift = math.abs(math.sin(t * Buddy.HopSpeed + pet.Phase)) * Buddy.HopHeight * moving
	local roll = math.sin(t * Buddy.HopSpeed + pet.Phase) * Buddy.Roll * moving
	local pitch = 0
	local spin = 0
	local base = newPos
	-- saut de joie
	local joy = t - pet.Joy
	if joy < 0.7 then
		local a = joy / 0.7
		lift += math.sin(a * math.pi) * 3
		spin = a * math.pi * 2
	end
	-- bond d'attaque (aller-retour vers la cible)
	local pounce = pet.Pounce
	if pounce then
		local a = (t - pounce.Start) / Buddy.PounceTime
		if a >= 1 then
			pet.Pounce = nil
		else
			local out = if a < 0.5 then a * 2 else (1 - a) * 2
			local e = 1 - (1 - out) ^ 2
			base = newPos:Lerp(Vector3.new(pounce.To.X, ground, pounce.To.Z), e)
			lift += math.sin(a * math.pi) * 4
			pitch = -0.4 * math.sin(a * math.pi)
			desired = yawTowards(pounce.To - newPos, desired)
			if a >= 0.5 and not pounce.Hit then
				pounce.Hit = true
				Effects.Burst(pounce.To + Vector3.new(0, 2, 0), C.Magma, 14, 1.4)
				Effects.FloatingText(pounce.To + Vector3.new(0, 4, 0), "POW!", C.Magma, 0.6)
				Audio.Play("roar_small", { Parent = model.PrimaryPart, Pitch = 1.6, Cooldown = 0.2 })
			end
		end
	end
	-- creuse : la tête pique vers le sol, la terre gicle
	if pet.DigAt then
		pitch = 0.35 + math.sin(t * 22) * 0.2
		if t >= pet.NextDust then
			pet.NextDust = t + 0.25
			Effects.Dust(pet.DigAt, 1.6)
		end
	end
	pet.Yaw = angleLerp(pet.Yaw, desired, 1 - math.exp(-8 * dt))

	local breathe = math.sin(t * 2.2 + pet.Phase)
	local rootFrame = CFrame.new(base + Vector3.new(0, lift + (breathe + 1) * 0.04 * s, 0))
		* CFrame.Angles(0, pet.Yaw + spin, 0)
		* CFrame.Angles(pitch, 0, roll)
	local far = (base - camPos).Magnitude > Buddy.AnimDistance
	local cfs = table.create(#pet.Parts)
	local pivots = pet.Pivots
	local wag = 3 + moving * 6 + (if joy < 1.2 then 8 else 0)
	for i, offset in pet.Offsets do
		local role = pet.Roles[i]
		local cf
		if far or role == "" then
			cf = rootFrame * offset
		elseif role == "Head" then
			local pv = pivots.Head
			local look = math.sin(t * 0.9 + pet.Phase) * 0.25 * (1 - moving)
			cf = rootFrame * CFrame.new(pv) * CFrame.Angles(math.sin(t * 1.7 + pet.Phase) * 0.08, look, 0) * CFrame.new(-pv) * offset
		elseif role == "Tail" then
			local pv = pivots.Tail
			cf = rootFrame * CFrame.new(pv) * CFrame.Angles(0, math.sin(t * wag + pet.Phase) * 0.3, 0) * CFrame.new(-pv) * offset
		elseif role == "WingL" or role == "WingR" then
			local pv = pivots[role]
			local dir = if role == "WingL" then 1 else -1
			cf = rootFrame * CFrame.new(pv) * CFrame.Angles(0, 0, math.sin(t * 10 + pet.Phase) * 0.4 * dir) * CFrame.new(-pv) * offset
		elseif role == "Squash" then
			cf = rootFrame * CFrame.new(0, breathe * 0.05 * s, 0) * offset
		else
			cf = rootFrame * offset
		end
		cfs[i] = cf
	end
	Workspace:BulkMoveTo(pet.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if model.PrimaryPart then
		model.PrimaryPart.CFrame = rootFrame
	end
end

----------------------------------------------------------------------------
-- Pastille HUD
----------------------------------------------------------------------------

local function localPet(): Pet?
	return pets[player]
end

local function barkBubble(pet: Pet)
	local gui = pet.Gui
	local bubble = gui and gui:FindFirstChild("Bubble") :: Frame?
	if bubble then
		bubble.Visible = true
		Kit.Pop(bubble, 0.2, 0.4)
	end
end

local function hideBubble(pet: Pet?)
	local gui = pet and pet.Gui
	local bubble = gui and gui:FindFirstChild("Bubble") :: Frame?
	if bubble then
		bubble.Visible = false
	end
end

local function bark()
	local pet = localPet()
	if not pet or not pet.Model then
		return
	end
	pet.Joy = os.clock()
	barkBubble(pet)
	Audio.Play("roar_small", { Parent = pet.Model.PrimaryPart, Pitch = 2.1 })
	task.delay(0.25, function()
		if pet.Model then
			Audio.Play("roar_small", { Parent = pet.Model.PrimaryPart, Pitch = 2.3, Cooldown = 0 })
		end
	end)
end

local function refreshChip()
	if not chip.Holder then
		return
	end
	local species = attr(player, "BuddySpecies")
	chip.Holder.Visible = species ~= nil
	if not species then
		return
	end
	local def = Kaijus.Get(species)
	chip.Name.Text = if def then string.upper(def.Name) else "BUDDY"
	local key = species .. ":" .. (attr(player, "BuddyMutation") or "")
	if chip.VpKey ~= key then
		chip.VpKey = key
		chip.Viewport:Set(species, attr(player, "BuddyMutation"))
		Kit.Pop(chip.Portrait, 0.5, 0.45)
	end
	local buddy = State.Get("Buddy")
	local xp = if buddy then buddy.Xp or 0 else 0
	local level = Buddy.Level(xp)
	chip.Level.Text = ("LV %d"):format(level)
	chip.SetXp(Buddy.Progress(xp))
	if level >= Buddy.MaxLevel then
		chip.XpText.Text = "MAX LEVEL"
	else
		local from = Buddy.XpFor(level)
		chip.XpText.Text = ("%d / %d XP"):format(xp - from, Buddy.XpFor(level + 1) - from)
	end
	Kit.SetBadge(chip.Frame, spot ~= nil, "!")
end

local function buildChip()
	local layer = Kit.Layer("BuddyHud", 4)
	-- la pastille se range dans la colonne de gauche du HUD (sous le niveau)
	local column = if Hud.LeftColumn then Hud.LeftColumn() else nil
	local holder = Kit.new("TextButton", {
		Name = "BuddyChip",
		Size = UDim2.fromOffset(250, 78),
		Position = UDim2.fromOffset(16, 62),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		LayoutOrder = 3,
		Parent = column or layer,
	})
	if not column then
		Kit.AutoScale(holder)
	end
	local frame, body = Kit.Panel({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		Rotation = -2,
		Gradient = "Ink",
		Corner = 16,
		ShadowOffset = 5,
		ZIndex = 2,
		Parent = holder,
	})
	local portrait = Kit.new("Frame", {
		Name = "Portrait",
		Size = UDim2.fromOffset(66, 66),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = C.Pink,
		ZIndex = 3,
		Parent = body,
	}, { Kit.Round(), Kit.Stroke(3), Kit.Gradient("Pink") })
	local vp = Viewport.new({ Parent = portrait, ZIndex = 4, Speed = 0.8 })
	Kit.Text({
		Name = "Tag",
		Size = UDim2.fromOffset(80, 16),
		Position = UDim2.fromOffset(80, 6),
		Text = "🐾 BUDDY",
		FontFace = F.Title,
		TextColor3 = C.Pink,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Stroke = 2,
		ZIndex = 4,
		Parent = body,
	})
	local name = Kit.Text({
		Name = "KaijuName",
		Size = UDim2.new(1, -150, 0, 24),
		Position = UDim2.fromOffset(80, 22),
		Text = "BUDDY",
		FontFace = F.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Stroke = 2.5,
		ZIndex = 4,
		Parent = body,
	})
	local levelChip = Kit.Chip({
		Name = "LevelChip",
		Text = "LV 1",
		Size = UDim2.fromOffset(62, 26),
		Position = UDim2.new(1, -8, 0, 20),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.RadioactiveDark,
		TextSize = 18,
		ZIndex = 4,
		Parent = body,
	})
	local xpBar, setXp = Kit.ProgressBar({
		Name = "XpBar",
		Size = UDim2.new(1, -94, 0, 16),
		Position = UDim2.fromOffset(80, 51),
		Color = "Radioactive",
		ZIndex = 4,
		Parent = body,
	})
	local xpText = Kit.Text({
		Name = "XpText",
		Size = UDim2.new(1, -8, 1, 2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "0 / 10 XP",
		FontFace = F.Title,
		MaxTextSize = 13,
		Stroke = 1.5,
		ZIndex = 7,
		Parent = xpBar,
	})
	chip.Holder = holder
	chip.Frame = frame
	chip.Portrait = portrait
	chip.Viewport = vp
	chip.Name = name
	chip.Level = levelChip:FindFirstChild("Text")
	chip.LevelChip = levelChip
	chip.SetXp = setXp
	chip.XpText = xpText
	chip.VpKey = ""
	holder.Activated:Connect(function()
		Audio.Play("ui_click")
		Kit.Punch(frame, 0.12)
		if spot then
			-- rappelle où est le trésor
			guide:Point(spot.Position)
			bark()
		else
			local uid = attr(player, "BuddyUid")
			if uid then
				UIRegistry.OpenKaiju(uid)
			end
		end
	end)
end

----------------------------------------------------------------------------
-- Trésor privé
----------------------------------------------------------------------------

local function block(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function hideSpot()
	local s = spot
	if not s then
		return
	end
	spot = nil
	s.Model:Destroy()
	guide:Hide()
	hideBubble(localPet())
	refreshChip()
end

local function showSpot(part: BasePart)
	hideSpot()
	local pos = part.Position - Vector3.new(0, 1, 0)
	local model = Instance.new("Model")
	model.Name = "BuddyTreasure"
	-- butte de terre + croix rouge
	local mound = block({
		Name = "Mound",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 1.6, 5),
		CFrame = CFrame.new(pos),
		Color = DIRT,
		Material = Enum.Material.Ground,
	}, model)
	for _, a in { 45, -45 } do
		block({
			Name = "Cross",
			Size = Vector3.new(0.7, 0.2, 4.2),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.82, 0)) * CFrame.Angles(0, math.rad(a), 0),
			Color = C.Red,
			Material = Enum.Material.Neon,
		}, model)
	end
	-- faisceau visible de loin
	local beam = block({
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(40, 1.6, 1.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Gold,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	}, model)
	Effects.Sparkles(mound, C.Gold, 8)
	local light = Instance.new("PointLight")
	light.Color = C.Gold
	light.Range = 14
	light.Brightness = 2
	light.Parent = beam
	-- étiquette + compte à rebours
	local gui = Instance.new("BillboardGui")
	gui.Name = "TreasureGui"
	gui.Size = UDim2.fromOffset(170, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.AlwaysOnTop = true
	gui.Adornee = mound
	gui.Parent = model
	Kit.Text({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 38),
		Text = "💰 DIG HERE!",
		TextColor3 = C.Gold,
		FontFace = F.Impact,
		Stroke = 3,
		Parent = gui,
	})
	local timer = Kit.Text({
		Name = "Timer",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 40),
		Text = "0:45",
		TextColor3 = C.Paper,
		FontFace = F.Title,
		Stroke = 2.5,
		Parent = gui,
	})
	model.Parent = folder
	spot = { Part = part, Model = model, Timer = timer, Position = pos }
	-- la butte sort du sol
	mound.Size = Vector3.new(1, 0.2, 1)
	TweenService:Create(mound, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(5, 1.6, 5) }):Play()
	Effects.Dust(pos, 2)
	guide:Point(pos)
	bark()
	refreshChip()
	Kit.Pop(chip.Frame, 1.3, 0.5)
	UIRegistry.Toast("🐾 Your buddy sniffed out a TREASURE! Follow the arrows!", "Good")

	-- le compagnon creuse pendant qu'on maintient
	local prompt = part:FindFirstChildOfClass("ProximityPrompt") or part:WaitForChild("ProximityPrompt", 5)
	if prompt then
		prompt.PromptButtonHoldBegan:Connect(function()
			local pet = localPet()
			if pet then
				pet.DigAt = pos
			end
		end)
		prompt.PromptButtonHoldEnded:Connect(function()
			local pet = localPet()
			if pet then
				pet.DigAt = nil
			end
		end)
	end
end

-- Les trésors des autres joueurs restent invisibles et inactifs chez nous.
local function muteForeign(part: Instance)
	local function mute(d: Instance)
		if d:IsA("ProximityPrompt") then
			d.Enabled = false
		end
	end
	for _, d in part:GetDescendants() do
		mute(d)
	end
	part.DescendantAdded:Connect(mute)
end

local function onSpotAdded(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	task.wait() -- attributs
	if part:GetAttribute("Owner") == player.UserId then
		showSpot(part)
	else
		muteForeign(part)
	end
end

----------------------------------------------------------------------------
-- Effets
----------------------------------------------------------------------------

local LOOT_TEXT = {
	Cash = function(args)
		return "+" .. Format.Cash(args.Amount or 0), C.Cash
	end,
	Gems = function(args)
		return ("💎 +%d"):format(args.Amount or 0), C.Gem
	end,
	Potion = function()
		return "🧪 GROWTH POTION!", C.Radioactive
	end,
	Egg = function(args)
		local r = Rarities.Get(args.Rarity or "Rare")
		return "🥚 " .. string.upper(r.Name) .. " EGG!", r.Color
	end,
}

-- Terre qui gicle, coffre qui sort du sol, pièces qui volent.
local function digBurst(pos: Vector3, kind: string, text: string?, color: Color3?)
	Effects.Burst(pos + Vector3.new(0, 1, 0), DIRT, 28, 2)
	Effects.Dust(pos, 4)
	Effects.Shockwave(pos, C.Gold, 9, 0.5)
	Audio.Play("drop")
	local chest = Instance.new("Model")
	chest.Name = "TreasureChest"
	local from = CFrame.new(pos - Vector3.new(0, 2, 0))
	local up = CFrame.new(pos + Vector3.new(0, 0.9, 0))
	local base = block({ Name = "Base", Size = Vector3.new(2.6, 1.6, 1.8), CFrame = from, Color = Color3.fromRGB(150, 90, 40), Material = Enum.Material.WoodPlanks }, chest)
	local lid = block({ Name = "Lid", Size = Vector3.new(2.7, 0.6, 1.9), CFrame = from * CFrame.new(0, 1.1, 0), Color = Color3.fromRGB(170, 105, 50), Material = Enum.Material.WoodPlanks }, chest)
	local band = block({ Name = "Band", Size = Vector3.new(2.75, 0.3, 1.95), CFrame = from * CFrame.new(0, 0.4, 0), Color = C.Gold, Material = Enum.Material.Foil }, chest)
	chest.Parent = folder
	local rise = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(base, rise, { CFrame = up }):Play()
	TweenService:Create(band, rise, { CFrame = up * CFrame.new(0, 0.4, 0) }):Play()
	TweenService:Create(lid, rise, { CFrame = up * CFrame.new(0, 1.1, 0) }):Play()
	task.delay(0.4, function()
		-- le couvercle s'ouvre (charnière à l'arrière)
		local hinge = up * CFrame.new(0, 0.8, 0.95)
		TweenService:Create(lid, TweenInfo.new(0.25, Enum.EasingStyle.Back), { CFrame = hinge * CFrame.Angles(math.rad(-110), 0, 0) * CFrame.new(0, 0.3, -0.95) }):Play()
		Effects.Burst(pos + Vector3.new(0, 2, 0), if kind == "Gems" then C.Gem else C.Gold, 40, 1.6)
		Audio.Play("reward_claim")
		-- pièces qui volent
		for i = 1, 8 do
			local coin = block({
				Name = "Coin",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.25, 1, 1),
				CFrame = CFrame.new(pos + Vector3.new(0, 1.8, 0)),
				Color = if kind == "Gems" then C.Gem else C.Gold,
				Material = Enum.Material.Neon,
			}, chest)
			local a = i / 8 * math.pi * 2
			local goal = pos + Vector3.new(math.cos(a) * 3.5, 5 + (i % 3), math.sin(a) * 3.5)
			TweenService:Create(coin, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = CFrame.new(goal) * CFrame.Angles(0, a, math.rad(90)), Transparency = 1 }):Play()
		end
		for i = 1, 3 do
			task.delay(i * 0.08, function()
				Audio.Play("coin_tick", { Pitch = 1 + i * 0.12, Cooldown = 0 })
			end)
		end
		if text then
			Effects.FloatingText(pos + Vector3.new(0, 5, 0), text, color, 0.9)
		end
	end)
	Debris:AddItem(chest, 2.4)
end

local function celebrate(pet: Pet?)
	if pet and pet.Model then
		pet.Joy = os.clock()
	end
end

----------------------------------------------------------------------------
-- API publique
----------------------------------------------------------------------------

function BuddyRenderer.Chip(): GuiObject?
	return chip.Holder
end

function BuddyRenderer.Celebrate()
	celebrate(localPet())
end

function BuddyRenderer.Model(userId: number?): Model?
	local p = if userId then Players:GetPlayerByUserId(userId) else player
	local pet = p and pets[p]
	return pet and pet.Model
end

function BuddyRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientBuddies"
	folder.Parent = Workspace
	guide = Guide.new(C.Gold)
	guide.Folder.Name = "BuddyGuide"
	buildChip()

	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)

	player.AttributeChanged:Connect(function(name)
		if name == "BuddySpecies" or name == "BuddyMutation" or name == "BuddyUid" then
			refreshChip()
		end
	end)
	State.Observe("Buddy", function()
		refreshChip()
	end)

	local spots = Workspace:WaitForChild("DigSpots")
	for _, part in spots:GetChildren() do
		task.spawn(onSpotAdded, part)
	end
	spots.ChildAdded:Connect(onSpotAdded)
	spots.ChildRemoved:Connect(function(part)
		if spot and spot.Part == part then
			hideSpot()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local t = os.clock()
		for _, pet in pets do
			animate(pet, dt, t, camPos)
		end
	end)

	-- compte à rebours du trésor
	task.spawn(function()
		while true do
			task.wait(0.25)
			local s = spot
			if s then
				local left = math.max(0, (s.Part:GetAttribute("ExpireAt") or 0) - Workspace:GetServerTimeNow())
				s.Timer.Text = Format.Clock(math.ceil(left))
				s.Timer.TextColor3 = if left <= 10 then C.Red else C.Paper
			end
		end
	end)

	FxBus.On("BuddyChanged", function(args)
		refreshChip()
		local def = Kaijus.Get(args.Species or "")
		local name = if def then def.Name else "Your kaiju"
		if args.Uid == "" or not def then
			UIRegistry.Toast("You have no buddy right now. Hatch a kaiju!", "Info")
		elseif args.First then
			-- après la cinématique d'éclosion qui vient de se jouer
			task.delay(6, function()
				UIRegistry.Announce("🐾 NEW BUDDY!", C.Pink, name .. " follows you everywhere and sniffs out treasure!", "reward_claim")
				celebrate(localPet())
			end)
		elseif args.Reason == "Lost" then
			UIRegistry.Toast(("Your buddy is gone... %s takes over! 🐾"):format(name), "Info")
		else
			UIRegistry.Toast(("%s is your new buddy! 🐾"):format(name), "Good")
		end
		task.delay(0.1, function()
			celebrate(localPet())
		end)
	end)
	FxBus.On("BuddyLevelUp", function(args)
		local pet = localPet()
		if pet and pet.Pos then
			local top = pet.Pos + Vector3.new(0, pet.Height + 2, 0)
			Effects.FloatingText(top, ("BUDDY LV %d!"):format(args.Level or 1), C.Radioactive, 0.9)
			Effects.Burst(top, C.Radioactive, 30, 1.6)
		end
		celebrate(pet)
		Audio.Play("level_jingle")
		refreshChip()
		if chip.LevelChip then
			Kit.Punch(chip.LevelChip, 0.5)
		end
		UIRegistry.Toast(("🐾 Buddy reached LEVEL %d! Bigger magnet, faster treasures!"):format(args.Level or 1), "Good")
	end)
	FxBus.On("BuddyTreasure", function()
		refreshChip()
	end)
	FxBus.On("BuddyTreasureGone", function()
		hideSpot()
		UIRegistry.Toast("The treasure sank back underground... your buddy will find another!", "Info")
	end)
	FxBus.On("BuddyDig", function(args)
		hideSpot()
		local pet = localPet()
		if pet then
			pet.DigAt = nil
		end
		local fn = LOOT_TEXT[args.Kind or ""]
		local text, color = nil, nil
		if fn then
			text, color = fn(args)
		end
		local pos = if typeof(args.Position) == "Vector3" then args.Position else Vector3.zero
		digBurst(pos, args.Kind or "Cash", text, color)
		CameraFx.ShakeAt(pos, 0.5, 40, 0.3)
		task.delay(0.45, function()
			celebrate(localPet())
		end)
		UIRegistry.Toast(("🐾 Treasure! %s"):format(args.Text or ""), if args.Kind == "Gems" then "Gem" elseif args.Kind == "Egg" then "Rare" elseif args.Kind == "Cash" then "Cash" else "Good")
		if chip.Frame then
			Kit.Punch(chip.Frame, 0.2)
		end
	end)
	FxBus.On("BuddyDigWorld", function(args)
		if args.UserId ~= player.UserId and typeof(args.Position) == "Vector3" then
			digBurst(args.Position, args.Kind or "Cash", nil, nil)
			local p = Players:GetPlayerByUserId(args.UserId or 0)
			celebrate(p and pets[p])
		end
	end)
	FxBus.On("BuddyMagnet", function(args)
		local pet = localPet()
		if not pet or not pet.Pos or type(args.Positions) ~= "table" then
			return
		end
		local target = pet.Pos + Vector3.new(0, pet.Height * 0.6, 0)
		for _, pos in args.Positions do
			if typeof(pos) == "Vector3" then
				local orb = block({ Name = "MagnetOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = CFrame.new(pos), Color = C.Cash, Material = Enum.Material.Neon }, folder)
				TweenService:Create(orb, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(target), Size = Vector3.new(0.4, 0.4, 0.4) }):Play()
				Debris:AddItem(orb, 0.4)
			end
		end
		Audio.Play("coin_tick", { Pitch = 1.4 })
		task.delay(0.35, function()
			Effects.Burst(target, C.Cash, 10, 1)
		end)
	end)
	FxBus.On("BuddyPounce", function(args)
		local p = Players:GetPlayerByUserId(args.UserId or 0)
		local pet = p and pets[p]
		if pet and pet.Pos and typeof(args.Target) == "Vector3" then
			pet.Pounce = { From = pet.Pos, To = args.Target, Start = os.clock(), Hit = false }
		end
	end)
	-- saut de joie quand on gagne quelque chose
	for _, name in { "Collect", "OrbGrabbed", "Hatch", "LevelUp", "RewardClaimed", "HeistSuccess", "EggGift", "BossReward" } do
		FxBus.On(name, function()
			celebrate(localPet())
		end)
	end
end

return BuddyRenderer
