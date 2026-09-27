--!nonstrict
-- Rendu local des kaijus à partir des ancres serveur (workspace.Kaijus).
-- Construit le modèle 3D, l'anime (respiration, tête, queue, ailes…),
-- l'affiche porté au-dessus des voleurs, gère étiquettes, auras de rareté,
-- effets de mutation et les prompts (Voler / Aider / Gérer).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local KaijuBuilder = require(Shared.KaijuBuilder)
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Growth = require(Shared.Config.Growth)
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

local C = Theme.Colors
local player = Players.LocalPlayer

local KaijuRenderer = {}

type Entry = {
	Anchor: BasePart,
	Model: Model?,
	Parts: { BasePart },
	Offsets: { CFrame },
	Roles: { string },
	Phases: { number },
	Pivots: { [string]: Vector3 },
	RainbowParts: { BasePart },
	Key: string,
	Scale: number,
	Height: number,
	Label: BillboardGui?,
	Prompt: ProximityPrompt?,
	PromptAttachment: Attachment?,
	Current: CFrame?,
	FlyFrom: CFrame?,
	FlyStart: number,
	WasCarried: boolean,
	Phase: number,
	LastStage: number,
	WasEgg: boolean,
	Aura: BasePart?,
	Parked: CFrame?,
}

local entries: { [BasePart]: Entry } = {}
local byUid: { [string]: Entry } = {}
local folder: Folder
local ANIM_DISTANCE = 170

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function characterOf(userId: number): Model?
	local p = Players:GetPlayerByUserId(userId)
	return p and p.Character
end

local function plotShielded(plotIndex: number): boolean
	local map = Workspace:FindFirstChild("Map")
	local plot = map and map:FindFirstChild("Plot" .. plotIndex)
	if not plot then
		return false
	end
	local t = now()
	return (plot:GetAttribute("ShieldUntil") or 0) > t or (plot:GetAttribute("ProtectedUntil") or 0) > t
end

----------------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------------

local function keyOf(anchor: BasePart): string
	return table.concat({
		tostring(anchor:GetAttribute("Egg")),
		anchor:GetAttribute("Rarity") or "",
		anchor:GetAttribute("Species") or "",
		anchor:GetAttribute("Mutation") or "",
		tostring(anchor:GetAttribute("Stage") or 1),
	}, "|")
end

local function lowFx(): boolean
	local s = State.Get("Settings")
	return s ~= nil and s.LowFx == true
end

local function addAura(entry: Entry, rarity: Rarities.Rarity, scale: number)
	if entry.Aura then
		entry.Aura:Destroy()
		entry.Aura = nil
	end
	if rarity.Order < 4 or not entry.Model then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "Aura"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = rarity.Color
	ring.Transparency = 0.7
	ring.Size = Vector3.new(0.15, 4.2 + 2.2 * scale, 4.2 + 2.2 * scale)
	ring.Parent = entry.Model
	entry.Aura = ring
	if rarity.Order >= 6 and not lowFx() then
		local pillar = Instance.new("Part")
		pillar.Name = "Pillar"
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Anchored = true
		pillar.CanCollide = false
		pillar.CanQuery = false
		pillar.CanTouch = false
		pillar.CastShadow = false
		pillar.Material = Enum.Material.Neon
		pillar.Color = rarity.Glow
		pillar.Transparency = 0.82
		pillar.Size = Vector3.new(80, 3 * scale, 3 * scale)
		pillar.Parent = ring
		pillar:SetAttribute("Pillar", true)
	end
end

local function buildLabel(entry: Entry)
	if entry.Label then
		entry.Label:Destroy()
	end
	local anchor = entry.Anchor
	local gui = Instance.new("BillboardGui")
	gui.Name = "KaijuLabel"
	gui.Size = UDim2.fromOffset(220, 74)
	gui.MaxDistance = 75
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.StudsOffsetWorldSpace = Vector3.new(0, entry.Height + 1.5, 0)
	gui.Adornee = anchor
	local function text(name: string, y: number, h: number, font: Font, color: Color3, stroke: number): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0, h)
		t.Position = UDim2.fromOffset(0, y)
		t.FontFace = font
		t.TextScaled = true
		t.RichText = true
		t.TextColor3 = color
		t.Text = ""
		local s = Instance.new("UIStroke")
		s.Thickness = stroke
		s.Color = C.Ink
		s.Parent = t
		t.Parent = gui
		return t
	end
	text("Name", 0, 30, Theme.Fonts.Title, C.White, 2.5)
	text("Info", 30, 22, Theme.Fonts.Body, C.Cash, 2)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(0.7, 0, 0, 9)
	bar.Position = UDim2.new(0.15, 0, 0, 57)
	bar.BackgroundColor3 = C.Ink
	bar.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.BackgroundColor3 = C.Radioactive
	fill.BorderSizePixel = 0
	corner:Clone().Parent = fill
	fill.Parent = bar
	bar.Parent = gui
	gui.Parent = folder
	entry.Label = gui
end

local function rebuild(entry: Entry)
	local anchor = entry.Anchor
	if entry.Model then
		entry.Model:Destroy()
	end
	local isEgg = anchor:GetAttribute("Egg") == true
	local stage = anchor:GetAttribute("Stage") or 1
	local scale = if isEgg then 1 else Growth.Get(stage).Scale
	local model
	if isEgg then
		model = KaijuBuilder.BuildEgg(anchor:GetAttribute("Rarity") or "Common", 1)
		entry.Height = 2.8
	else
		local species = anchor:GetAttribute("Species") or "Toastzilla"
		local mutation = anchor:GetAttribute("Mutation")
		model = KaijuBuilder.Build(species, if mutation ~= "" then mutation else nil, scale)
		entry.Height = KaijuBuilder.Height(species) * scale
	end
	entry.Scale = scale
	entry.Model = model
	entry.Parts = {}
	entry.Offsets = {}
	entry.Roles = {}
	entry.Phases = {}
	entry.RainbowParts = {}
	local sums: { [string]: Vector3 } = {}
	local counts: { [string]: number } = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			table.insert(entry.Parts, p)
			table.insert(entry.Offsets, p.CFrame)
			local role = p:GetAttribute("Role") or ""
			table.insert(entry.Roles, role)
			table.insert(entry.Phases, p:GetAttribute("Phase") or 0)
			if role ~= "" then
				sums[role] = (sums[role] or Vector3.zero) + p.Position
				counts[role] = (counts[role] or 0) + 1
			end
			if p:GetAttribute("Rainbow") then
				table.insert(entry.RainbowParts, p)
			end
		end
	end
	entry.Pivots = {}
	for role, sum in sums do
		entry.Pivots[role] = sum / counts[role]
	end
	-- pivots explicites (ailes)
	for _, p in model:GetDescendants() do
		local pv = p:GetAttribute("Pivot")
		if typeof(pv) == "Vector3" then
			entry.Pivots[p:GetAttribute("Role")] = pv * scale
		end
	end
	if entry.Pivots.Tail then
		-- la queue pivote depuis son attache (le point le plus proche du corps)
		local best = nil
		for i, p in entry.Parts do
			if entry.Roles[i] == "Tail" and (not best or p.Position.Z < best.Z) then
				best = p.Position
			end
		end
		entry.Pivots.Tail = best
	end
	model.Parent = folder
	entry.Key = keyOf(anchor)
	entry.Parked = nil

	if not isEgg then
		local rarity = Rarities.Get(anchor:GetAttribute("Rarity") or "Common")
		addAura(entry, rarity, scale)
		local mutation = Mutations.Get(anchor:GetAttribute("Mutation"))
		if mutation and mutation.Particles and not lowFx() then
			Effects.MutationEmitter(model.PrimaryPart, mutation, scale)
		end
		if model:GetAttribute("FxStars") and not lowFx() then
			Effects.MutationEmitter(model.PrimaryPart, Mutations.Get("Galaxy") :: any, scale)
		end
	else
		local rarity = Rarities.Get(anchor:GetAttribute("Rarity") or "Common")
		if rarity.Order >= 3 and not lowFx() then
			Effects.Sparkles(model.PrimaryPart, rarity.Glow, 3 + rarity.Order)
		end
	end
	buildLabel(entry)
	if entry.PromptAttachment then
		entry.PromptAttachment.Position = Vector3.new(0, math.max(2.5, entry.Height * 0.55), 0)
	end
end

----------------------------------------------------------------------------
-- Prompts
----------------------------------------------------------------------------

local function refreshPrompt(entry: Entry)
	local prompt = entry.Prompt
	if not prompt then
		return
	end
	local anchor = entry.Anchor
	local owner = anchor:GetAttribute("Owner") or 0
	local isEgg = anchor:GetAttribute("Egg") == true
	local carriedBy = anchor:GetAttribute("CarriedBy") or 0
	local stage = anchor:GetAttribute("Stage") or 1
	local species = Kaijus.Get(anchor:GetAttribute("Species") or "")
	prompt.ObjectText = if isEgg then (Rarities.Get(anchor:GetAttribute("Rarity") or "Common").Name .. " Egg") elseif species then species.Name else ""
	prompt.MaxActivationDistance = 9 + Growth.Get(stage).Scale * 3
	if owner == player.UserId then
		prompt.ActionText = if isEgg then "Egg info" else "Manage"
		prompt.HoldDuration = 0
		prompt.Enabled = carriedBy == 0
		prompt:SetAttribute("Kind", "Manage")
		prompt:SetAttribute("Color", "Cyan")
	else
		if anchor:GetAttribute("Lifting") and carriedBy ~= player.UserId and (anchor:GetAttribute("Helper") or 0) == 0 then
			prompt.ActionText = "HELP LIFT 🤝"
			prompt.HoldDuration = 0
			prompt.Enabled = true
			prompt.MaxActivationDistance = 24
			prompt:SetAttribute("Kind", "Help")
			prompt:SetAttribute("Color", "Gold")
		elseif carriedBy ~= 0 or isEgg then
			prompt.Enabled = false
		else
			local shielded = plotShielded(anchor:GetAttribute("Plot") or 0)
			prompt.ActionText = if shielded then "🛡️ SHIELDED" else (if Growth.Get(stage).Carriers > 1 then "STEAL (2 players)" else "STEAL")
			prompt.HoldDuration = if shielded then 0 else 0.5 + stage * 0.15
			prompt.Enabled = true
			prompt:SetAttribute("Kind", if shielded then "Blocked" else "Steal")
			prompt:SetAttribute("Color", if shielded then "Grey" else "Red")
		end
	end
end

local function makePrompt(entry: Entry)
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptPoint"
	attachment.Position = Vector3.new(0, math.max(2.5, entry.Height * 0.55), 0)
	attachment.Parent = entry.Anchor
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.Parent = attachment
	entry.Prompt = prompt
	entry.PromptAttachment = attachment
	prompt.Triggered:Connect(function()
		local kind = prompt:GetAttribute("Kind")
		local uid = entry.Anchor:GetAttribute("Uid")
		if kind == "Manage" then
			UIRegistry.OpenKaiju(uid)
		elseif kind == "Steal" then
			Remote.Call("Steal", { Uid = uid })
		elseif kind == "Help" then
			Remote.Call("Help", { Uid = uid })
		elseif kind == "Blocked" then
			Audio.Play("shield_zap")
			UIRegistry.Toast("This base is shielded! Wait for it to drop 🛡️", "Bad")
		end
	end)
	refreshPrompt(entry)
end

----------------------------------------------------------------------------
-- Cycle de vie des ancres
----------------------------------------------------------------------------

local function track(anchor: BasePart)
	if entries[anchor] then
		return
	end
	local entry: Entry = {
		Anchor = anchor,
		Model = nil,
		Parts = {},
		Offsets = {},
		Roles = {},
		Phases = {},
		Pivots = {},
		RainbowParts = {},
		Key = "",
		Scale = 1,
		Height = 4,
		Label = nil,
		Prompt = nil,
		PromptAttachment = nil,
		Current = nil,
		FlyFrom = nil,
		FlyStart = 0,
		WasCarried = false,
		Phase = math.random() * 10,
		LastStage = anchor:GetAttribute("Stage") or 1,
		WasEgg = anchor:GetAttribute("Egg") == true,
		Aura = nil,
		Parked = nil,
	}
	entries[anchor] = entry
	byUid[anchor:GetAttribute("Uid") or anchor.Name] = entry
	rebuild(entry)
	makePrompt(entry)
	-- apparition : petit pop
	entry.FlyFrom = anchor.CFrame * CFrame.new(0, 12, 0)
	entry.FlyStart = os.clock()

	anchor.AttributeChanged:Connect(function(attr)
		if attr == "Egg" or attr == "Species" or attr == "Mutation" or attr == "Stage" or attr == "Rarity" then
			if keyOf(anchor) ~= entry.Key then
				local wasEgg = entry.WasEgg
				local stage = anchor:GetAttribute("Stage") or 1
				rebuild(entry)
				local pos = anchor.Position + Vector3.new(0, entry.Height / 2, 0)
				if wasEgg and not anchor:GetAttribute("Egg") then
					local rarity = Rarities.Get(anchor:GetAttribute("Rarity") or "Common")
					Effects.Burst(pos, rarity.Glow, 30 + rarity.Order * 10, entry.Scale * 3)
					Effects.Shockwave(anchor.Position, rarity.Color, 16, 0.6)
					Audio.Play("egg_crack", { Parent = anchor })
				elseif stage > entry.LastStage then
					Effects.Burst(pos, C.Radioactive, 40, entry.Scale * 3)
					Effects.Shockwave(anchor.Position, C.Radioactive, 10 + entry.Scale * 6, 0.7)
					Effects.FloatingText(pos + Vector3.new(0, entry.Height / 2 + 2, 0), string.upper(Growth.Get(stage).Name) .. "!", C.Radioactive)
					Audio.Play("stage_up", { Parent = anchor })
					if stage >= 4 then
						Audio.Play("roar_big", { Parent = anchor, MaxDistance = 400 })
						CameraFx.ShakeAt(anchor.Position, 1.2, 160, 0.8)
					else
						Audio.Play("roar_small", { Parent = anchor })
					end
				elseif attr == "Mutation" then
					local mutation = Mutations.Get(anchor:GetAttribute("Mutation"))
					if mutation then
						Effects.Burst(pos, mutation.Color, 60, entry.Scale * 3)
						Effects.FloatingText(pos + Vector3.new(0, entry.Height / 2 + 2, 0), string.upper(mutation.Name) .. "!", mutation.Color)
					end
				end
				entry.WasEgg = anchor:GetAttribute("Egg") == true
				entry.LastStage = stage
			end
		end
		if attr == "CarriedBy" then
			local carried = (anchor:GetAttribute("CarriedBy") or 0) ~= 0
			if entry.WasCarried and not carried and entry.Current then
				-- retour à la maison en vol plané
				entry.FlyFrom = entry.Current
				entry.FlyStart = os.clock()
			end
			entry.WasCarried = carried
		end
		refreshPrompt(entry)
	end)
end

local function untrack(anchor: BasePart)
	local entry = entries[anchor]
	if not entry then
		return
	end
	entries[anchor] = nil
	for uid, e in byUid do
		if e == entry then
			byUid[uid] = nil
		end
	end
	if entry.Model then
		local model = entry.Model
		-- disparition : on laisse l'effet se jouer
		local pos = if entry.Current then entry.Current.Position else anchor.Position
		Effects.Poof(pos + Vector3.new(0, entry.Height / 2, 0), entry.Scale * 3)
		model:Destroy()
	end
	if entry.Label then
		entry.Label:Destroy()
	end
end

function KaijuRenderer.ByUid(uid: string): any
	return byUid[uid]
end

----------------------------------------------------------------------------
-- Boucle d'animation
----------------------------------------------------------------------------

local function placement(entry: Entry, t: number): CFrame
	local anchor = entry.Anchor
	local carriedBy = anchor:GetAttribute("CarriedBy") or 0
	if carriedBy ~= 0 then
		local lead = characterOf(carriedBy)
		local head = lead and lead:FindFirstChild("Head") :: BasePart?
		if head then
			local helperId = anchor:GetAttribute("Helper") or 0
			local helper = if helperId ~= 0 then characterOf(helperId) else nil
			local helperHead = helper and helper:FindFirstChild("Head") :: BasePart?
			if anchor:GetAttribute("Lifting") then
				-- trop lourd : il tangue au sol à côté du voleur
				local root = lead:FindFirstChild("HumanoidRootPart") :: BasePart?
				local base = if root then root.CFrame * CFrame.new(0, -3, -4 - entry.Scale) else head.CFrame
				return CFrame.new(base.Position) * CFrame.Angles(math.sin(t * 9) * 0.08, 0, math.sin(t * 7) * 0.1)
			end
			local pos = head.Position
			if helperHead then
				pos = (pos + helperHead.Position) / 2
			end
			local yaw = select(2, head.CFrame:ToEulerAnglesYXZ())
			local lift = 1.2 + math.sin(t * 10) * 0.25
			return CFrame.new(pos + Vector3.new(0, lift, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.sin(t * 6) * 0.12)
		end
	end
	return anchor.CFrame
end

local function animate(entry: Entry, dt: number, t: number, camPos: Vector3)
	local model = entry.Model
	if not model then
		return
	end
	local target = placement(entry, t)
	-- vol plané (apparition, retour)
	if entry.FlyFrom then
		local a = math.clamp((os.clock() - entry.FlyStart) / 0.9, 0, 1)
		local e = 1 - (1 - a) ^ 3
		local p = entry.FlyFrom.Position:Lerp(target.Position, e) + Vector3.new(0, math.sin(a * math.pi) * 10, 0)
		target = CFrame.new(p) * target.Rotation
		if a >= 1 then
			entry.FlyFrom = nil
			if (entry.Anchor:GetAttribute("CarriedBy") or 0) == 0 and not entry.WasEgg then
				Effects.Dust(entry.Anchor.Position, entry.Scale * 3)
			end
		end
	end
	entry.Current = target
	if entry.PromptAttachment then
		-- le prompt suit le kaiju (utile pour « aider à soulever »)
		entry.PromptAttachment.WorldPosition = target.Position + Vector3.new(0, math.max(2.5, entry.Height * 0.55), 0)
	end
	local far = (target.Position - camPos).Magnitude > ANIM_DISTANCE
	-- Loin et immobile : déjà en place, rien à recalculer (grosse économie sur mobile)
	if far and entry.Parked == target then
		return
	end
	entry.Parked = if far then target else nil
	local phase = entry.Phase
	local s = entry.Scale
	local breathe = math.sin(t * 2.2 + phase)
	local root = target * CFrame.new(0, if far then 0 else (breathe + 1) * 0.06 * s, 0) * CFrame.Angles(0, if far then 0 else math.sin(t * 0.7 + phase) * 0.06, 0)
	local cfs = table.create(#entry.Parts)
	local pivots = entry.Pivots
	for i, offset in entry.Offsets do
		local role = entry.Roles[i]
		local cf
		if far or role == "" then
			cf = root * offset
		elseif role == "Head" then
			local pv = pivots.Head
			cf = root * CFrame.new(pv) * CFrame.Angles(math.sin(t * 1.7 + phase) * 0.06, math.sin(t * 0.9 + phase) * 0.12, 0) * CFrame.new(-pv) * offset
		elseif role == "Tail" then
			local pv = pivots.Tail
			local k = 1 + entry.Phases[i] * 0.6
			cf = root * CFrame.new(pv) * CFrame.Angles(0, math.sin(t * 3 + phase) * 0.18 * k, 0) * CFrame.new(-pv) * offset
		elseif role == "WingL" or role == "WingR" then
			local pv = pivots[role]
			local dir = if role == "WingL" then 1 else -1
			cf = root * CFrame.new(pv) * CFrame.Angles(0, 0, math.sin(t * 8 + phase) * 0.35 * dir) * CFrame.new(-pv) * offset
		elseif role == "Wave" then
			local ph = entry.Phases[i]
			cf = root * CFrame.new(math.sin(t * 3 + ph * 0.9) * 0.12 * s, math.sin(t * 4 + ph) * 0.1 * s, 0) * offset
		elseif role == "Halo" then
			local pv = pivots.Halo
			cf = root * CFrame.new(pv) * CFrame.Angles(0, t * 1.5, 0) * CFrame.new(0, math.sin(t * 2) * 0.1 * s, 0) * CFrame.new(-pv) * offset
		elseif role == "Squash" then
			cf = root * CFrame.new(0, breathe * 0.05 * s, 0) * offset
		else
			cf = root * offset
		end
		cfs[i] = cf
	end
	Workspace:BulkMoveTo(entry.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if model.PrimaryPart then
		model.PrimaryPart.CFrame = root
	end
	if entry.Aura then
		entry.Aura.CFrame = target * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90))
		entry.Aura.Transparency = 0.68 + math.sin(t * 3 + phase) * 0.12
		local pillar = entry.Aura:FindFirstChild("Pillar") :: BasePart?
		if pillar then
			pillar.CFrame = target * CFrame.new(0, 40, 0) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
	if not far and #entry.RainbowParts > 0 then
		for i, p in entry.RainbowParts do
			p.Color = Color3.fromHSV((t * 0.25 + i * 0.04) % 1, 0.65, 1)
		end
	end
	-- étiquette
	local label = entry.Label
	if label and not far then
		label.StudsOffsetWorldSpace = Vector3.new(0, entry.Height + 1.5, 0) + (target.Position - entry.Anchor.Position)
	end
end

local function updateLabel(entry: Entry)
	local label = entry.Label
	if not label then
		return
	end
	local anchor = entry.Anchor
	local nameLabel = label:FindFirstChild("Name") :: TextLabel
	local info = label:FindFirstChild("Info") :: TextLabel
	local bar = label:FindFirstChild("Bar") :: Frame
	local fill = bar:FindFirstChild("Fill") :: Frame
	local rarity = Rarities.Get(anchor:GetAttribute("Rarity") or "Common")
	local t = now()
	if anchor:GetAttribute("Egg") then
		nameLabel.Text = ("🥚 %s EGG"):format(string.upper(rarity.Name))
		nameLabel.TextColor3 = rarity.Color
		local left = (anchor:GetAttribute("HatchAt") or 0) - t
		info.Text = if left > 0 then ("Hatching in %s"):format(Format.Clock(left)) else "Hatching..."
		info.TextColor3 = C.Paper
		bar.Visible = false
		return
	end
	local species = Kaijus.Get(anchor:GetAttribute("Species") or "")
	local mutation = Mutations.Get(anchor:GetAttribute("Mutation"))
	local stage = anchor:GetAttribute("Stage") or 1
	local mutText = if mutation then ('<font color="#%s">%s</font> '):format(mutation.TextColor:ToHex(), string.upper(mutation.Name)) else ""
	nameLabel.Text = mutText .. (if species then species.Name else "?")
	nameLabel.TextColor3 = if rarity.Id == "Secret" then C.White else rarity.Color
	local carried = (anchor:GetAttribute("CarriedBy") or 0) ~= 0
	if carried then
		info.Text = "🚨 BEING STOLEN!"
		info.TextColor3 = C.Red
	else
		info.Text = ("%s • %s/s"):format(string.upper(Growth.Get(stage).Name), Format.Cash(anchor:GetAttribute("Income") or 0))
		info.TextColor3 = C.Cash
	end
	if stage < Growth.MaxStage and species then
		local growth = (anchor:GetAttribute("Growth") or 0) + (t - (anchor:GetAttribute("GrowthStamp") or t)) * (anchor:GetAttribute("GrowthRate") or 1)
		bar.Visible = true
		fill.Size = UDim2.fromScale(Growth.Progress(growth, species.Rarity), 1)
	else
		bar.Visible = false
	end
end

----------------------------------------------------------------------------

function KaijuRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientKaijus"
	folder.Parent = Workspace

	local anchors = Workspace:WaitForChild("Kaijus")
	local function watchOwner(ownerFolder: Instance)
		for _, a in ownerFolder:GetChildren() do
			if a:IsA("BasePart") then
				task.spawn(track, a)
			end
		end
		ownerFolder.ChildAdded:Connect(function(a)
			if a:IsA("BasePart") then
				-- attend les attributs
				task.wait()
				track(a)
			end
		end)
		ownerFolder.ChildRemoved:Connect(function(a)
			if a:IsA("BasePart") then
				untrack(a)
			end
		end)
	end
	for _, f in anchors:GetChildren() do
		watchOwner(f)
	end
	anchors.ChildAdded:Connect(watchOwner)

	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local t = os.clock()
		for _, entry in entries do
			animate(entry, dt, t, camPos)
		end
	end)

	-- Étiquettes et prompts : 5 fois par seconde suffit
	task.spawn(function()
		while true do
			for _, entry in entries do
				updateLabel(entry)
				refreshPrompt(entry)
			end
			task.wait(0.2)
		end
	end)

	FxBus.On("Fed", function(args)
		local entry = byUid[args.Uid or ""]
		if entry and entry.Current then
			local pos = entry.Current.Position + Vector3.new(0, entry.Height * 0.7, 0)
			local icons = { Snack = "🍖", Feast = "🍗", Steak = "🥩" }
			Effects.FloatingText(pos, (icons[args.Food] or "🍖") .. " NOM!", C.Gold)
			Effects.Burst(pos, C.Gold, 12, entry.Scale * 2)
			Audio.Play("roar_small", { Parent = entry.Anchor, Pitch = 1.3 })
		end
	end)
	FxBus.On("KaijuReturned", function(args)
		local entry = byUid[args.Uid or ""]
		if entry and entry.Current then
			Effects.Poof(entry.Current.Position, entry.Scale * 3)
			Audio.Play("drop", { Parent = entry.Anchor })
		end
	end)
	FxBus.On("HatchWorld", function(args)
		local entry = byUid[args.Uid or ""]
		if entry then
			local rarity = Rarities.Get(args.Rarity or "Common")
			if rarity.Order >= 4 then
				Effects.Pillar(entry.Anchor.Position, rarity.Color, 3)
			end
		end
	end)
	FxBus.On("Infected", function(args)
		local entry = byUid[args.Uid or ""]
		if entry then
			local mutation = Mutations.Get(args.Mutation)
			Effects.Pillar(entry.Anchor.Position, if mutation then mutation.Color else C.Radioactive, 2)
		end
	end)
	FxBus.On("Alarm", function(args)
		local entry = byUid[args.Uid or ""]
		if entry then
			Effects.Pillar(entry.Anchor.Position, C.Red, 2)
		end
	end)
end

return KaijuRenderer
