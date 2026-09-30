--!strict
--[[
	WorldFx : toute la vie visuelle du monde, côté client uniquement (zéro coût serveur).
	Fonctionne avec StreamingEnabled : chaque élément est pris en charge quand il
	arrive (CollectionService) et oublié quand il repart.

	Tags gérés : Spin, RgbStrip, TierGlow, PulseGlow, Beacon, ZoneEdge, Virus, Fragment,
	TerminalScreen, TowerSign, LeaderboardScreen, TitleHologram, Collector.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Modules = require(Shared.Config.Modules)
local Branding = require(Shared.Config.Branding)
local NumberFormat = require(Shared.Util.NumberFormat)

local Store = require(script.Parent.Store)
local Motion = require(script.Parent.Parent.UI.Motion)
local Style = require(script.Parent.Parent.UI.Style)
local Create = require(script.Parent.Parent.UI.Create)

local New = Create.New

local WorldFx = {}

local player = Players.LocalPlayer

local spins: { [BasePart]: { Axis: string, Speed: number, Tower: Model?, Module: Instance? } } = {}
local rgbStrips: { [BasePart]: { Tower: Model?, Offset: number } } = {} -- tour en cache
local tierGlows: { [BasePart]: boolean } = {}
local pulses: { [BasePart]: number } = {}
local viruses: { [BasePart]: { Base: CFrame, Phase: number } } = {}
local fragments: { [BasePart]: { Base: CFrame, Phase: number } } = {}
local beacons: { [BasePart]: { Base: number, Tower: Model? } } = {}
local boardScreens: { [BasePart]: SurfaceGui } = {}

------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------

local function towerOf(instance: Instance): Model?
	local current: Instance? = instance
	while current do
		if
			current:IsA("Model")
			and current:GetAttribute("Index") ~= nil
			and current:GetAttribute("OwnerUserId") ~= nil
		then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function moduleOf(instance: Instance): Instance?
	local current: Instance? = instance
	while current do
		if current:GetAttribute("ModuleId") ~= nil and current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isMine(tower: Model?): boolean
	return tower ~= nil and tower:GetAttribute("OwnerUserId") == player.UserId
end

local function powered(tower: Model?): boolean
	return tower ~= nil and tower:GetAttribute("PoweredOn") == true
end

local function hueFor(tower: Model?, offset: number): number
	local fixed = if tower then tower:GetAttribute("RgbHue") else nil
	if type(fixed) == "number" and fixed >= 0 then
		return fixed
	end
	return (os.clock() * 0.06 + offset) % 1
end

local TIER_COLORS = {
	{ Min = 100, Color = "BrandAnga", Rainbow = true },
	{ Min = 50, Color = "CurrencyChips", Rainbow = false },
	{ Min = 25, Color = "CurrencyBits", Rainbow = false },
	{ Min = 10, Color = "TextPrimary", Rainbow = false },
	{ Min = 1, Color = "AccentAmber", Rainbow = false },
}

local function tierColor(level: number): (Color3?, boolean)
	for _, tier in TIER_COLORS do
		if level >= tier.Min then
			return Style.Color(tier.Color), tier.Rainbow
		end
	end
	return nil, false
end

------------------------------------------------------------------------------------
-- Surfaces (panneaux, enseignes, classements)
------------------------------------------------------------------------------------

local function surface(part: BasePart, face: Enum.NormalId, pixels: number, name: string?): SurfaceGui
	local guiName = name or "FxSurface"
	local existing = part:FindFirstChild(guiName)
	if existing and existing:IsA("SurfaceGui") then
		return existing
	end
	local gui: SurfaceGui = New("SurfaceGui", {
		Name = guiName,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixels,
		LightInfluence = 0,
		Brightness = 1.5,
		ZOffset = 1,
		Parent = part,
	})
	return gui
end

local function setupTerminal(screen: BasePart)
	local accentHex = screen:GetAttribute("Accent")
	local accent = if type(accentHex) == "string" then Color3.fromHex(accentHex) else Style.Color("AccentCyan")
	local gui = surface(screen, Enum.NormalId.Front, 40)
	gui:ClearAllChildren()
	New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.Color("BgDeep"),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		New("UIStroke", { Color = accent, Thickness = 4 }) :: Instance,
		New("TextLabel", {
			Size = UDim2.new(1, -20, 1, -20),
			Position = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Text = tostring(screen:GetAttribute("Label") or ""),
			TextScaled = true,
			FontFace = Style.Fonts.Display,
			TextColor3 = accent,
		}),
	})
end

local function setupSign(sign: BasePart)
	local tower = towerOf(sign)
	local gui = surface(sign, Enum.NormalId.Front, 30)
	gui:ClearAllChildren()
	local label: TextLabel = New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextScaled = true,
		RichText = true,
		FontFace = Style.Fonts.Display,
		TextColor3 = Style.Color("TextPrimary"),
		TextStrokeTransparency = 0.6,
		Parent = gui,
	})
	local function refresh()
		if not tower then
			return
		end
		local owner = tower:GetAttribute("OwnerUserId")
		if owner == 0 or owner == nil then
			label.Text = "TOUR LIBRE"
			label.TextTransparency = 0.5
		else
			label.TextTransparency = 0
			label.Text =
				`{tower:GetAttribute("OwnerName")}  <font size="30">GEN {tower:GetAttribute("Generation") or 1} · ♥ {tower:GetAttribute(
					"Likes"
				) or 0}</font>`
		end
	end
	refresh()
	if tower then
		tower.AttributeChanged:Connect(refresh)
	end
end

local function renderBoard(screen: BasePart)
	local gui = boardScreens[screen]
	local boards = Store.Boards
	if not gui then
		return
	end
	gui:ClearAllChildren()
	local isWeekly = screen:GetAttribute("Board") == "WeeklyBoard"
	local root: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.Color("BgDeep"),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		New("UIStroke", { Color = Style.Color(if isWeekly then "AccentCyan" else "CurrencyBits"), Thickness = 6 }) :: Instance,
		Create.Padding(24),
		Create.List(Enum.FillDirection.Vertical, 6),
	})
	New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundTransparency = 1,
		Text = if isWeekly then "CETTE SEMAINE" else "LÉGENDES",
		TextScaled = true,
		FontFace = Style.Fonts.Display,
		TextColor3 = Style.Color(if isWeekly then "AccentCyan" else "CurrencyBits"),
		LayoutOrder = 0,
		Parent = root,
	})
	local entries = if boards then (if isWeekly then boards.Weekly else boards.Legends) else {}
	for rank = 1, math.min(#entries, 10) do
		local entry = entries[rank]
		New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundTransparency = 1,
			Text = `#{rank}  {entry.Name}  —  {NumberFormat.Compact(entry.Value)}`,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Style.Fonts.Bold,
			TextColor3 = Style.Color(if rank <= 3 then "CurrencyBits" else "TextPrimary"),
			LayoutOrder = rank,
			Parent = root,
		})
	end
	if #entries == 0 then
		New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 50),
			BackgroundTransparency = 1,
			Text = "Classement en chargement…",
			TextScaled = true,
			FontFace = Style.Fonts.Medium,
			TextColor3 = Style.Color("TextMuted"),
			LayoutOrder = 1,
			Parent = root,
		})
	end
end

local function setupTitle(part: BasePart)
	-- Hologramme lisible des deux côtés.
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local target = surface(part, face, 20, `Title{face.Name}`)
		target:ClearAllChildren()
		do
			New("TextLabel", {
				Size = UDim2.new(1, 0, 0.7, 0),
				BackgroundTransparency = 1,
				Text = Branding.GameName,
				TextScaled = true,
				FontFace = Style.Fonts.Display,
				TextColor3 = Style.Color("TextPrimary"),
				TextStrokeColor3 = Style.Color("AccentViolet"),
				TextStrokeTransparency = 0.2,
				Parent = target,
			})
			New("TextLabel", {
				Position = UDim2.fromScale(0, 0.7),
				Size = UDim2.new(1, 0, 0.3, 0),
				BackgroundTransparency = 1,
				Text = Branding.Tagline,
				TextScaled = true,
				FontFace = Style.Fonts.Medium,
				TextColor3 = Style.Color("AccentCyan"),
				Parent = target,
			})
		end
	end
end

------------------------------------------------------------------------------------
-- Étiquettes des machines + étages verrouillés + prompts
------------------------------------------------------------------------------------

local function setupModuleLabel(model: Instance)
	local anchor = model:FindFirstChild("LabelAnchor")
	if not (anchor and anchor:IsA("BasePart")) or anchor:FindFirstChild("ModuleLabel") then
		return
	end
	local id = model:GetAttribute("ModuleId")
	local def = if type(id) == "string" then Modules.Get(id) else nil
	if not def then
		return
	end
	local billboard: BillboardGui = New("BillboardGui", {
		Name = "ModuleLabel",
		Size = UDim2.fromOffset(200, 54),
		StudsOffset = Vector3.new(0, 1.5, 0),
		MaxDistance = 60,
		LightInfluence = 0,
		Parent = anchor,
	})
	local card: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.Color("Surface"),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = billboard,
	}, {
		Create.Corner(10) :: Instance,
		New("UIStroke", { Color = Color3.fromHex(Zones[def.Zone].Primary), Thickness = 1.5, Transparency = 0.2 }),
	})
	New("TextLabel", {
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 22),
		BackgroundTransparency = 1,
		Text = def.Name,
		TextScaled = true,
		FontFace = Style.Fonts.Bold,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = card,
	})
	local level: TextLabel = New("TextLabel", {
		Position = UDim2.fromOffset(8, 28),
		Size = UDim2.new(1, -16, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		FontFace = Style.Fonts.Heavy,
		TextColor3 = Style.Color("CurrencyBits"),
		Parent = card,
	})
	local function refresh()
		local value = model:GetAttribute("Level")
		local n = if type(value) == "number" then value else 0
		level.Text = if n > 0 then `NIV. {n}` else "À ACHETER"
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and tierGlows[part] then
				WorldFx.PaintTier(part)
			end
		end
	end
	refresh()
	model:GetAttributeChangedSignal("Level"):Connect(function()
		refresh()
		-- Petit flash de la machine à chaque amélioration de SA tour
		if isMine(towerOf(model)) and not Motion.IsReduced() then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and tierGlows[part] then
					local original = part.Transparency
					part.Transparency = 0
					task.delay(0.12, function()
						part.Transparency = original
					end)
				end
			end
		end
	end)
end

function WorldFx.PaintTier(part: BasePart)
	local model = moduleOf(part)
	local tower = towerOf(part)
	local level = if model then model:GetAttribute("Level") else 0
	local n = if type(level) == "number" then level else 0
	local color, rainbow = tierColor(n)
	if not color or not powered(tower) then
		part.Color = Style.Color("MetalLight")
		part.Transparency = 0.7
		part:SetAttribute("Rainbow", false)
		return
	end
	part.Color = color
	part.Transparency = 0.05
	part:SetAttribute("Rainbow", rainbow)
end

-- Lumières et néons d'un étage selon qu'il est débloqué et que la tour est allumée.
local function applyFloor(tower: Model, floor: Instance)
	local zoneAttr = floor:GetAttribute("Zone")
	local index = if type(zoneAttr) == "number" then zoneAttr else 1
	local towerZone = tower:GetAttribute("Zone")
	local unlocked = type(towerZone) == "number" and index <= towerZone
	local on = unlocked and powered(tower)
	for _, descendant in floor:GetDescendants() do
		if descendant:IsA("PointLight") then
			descendant.Enabled = on
		elseif descendant:IsA("BasePart") and (descendant:HasTag("ZoneEdge") or descendant.Name:match("^Trace")) then
			descendant.Transparency = if on then (if descendant:HasTag("ZoneEdge") then 0.5 else 0.6) else 0.88
		end
	end
	local plate = floor:FindFirstChild("Plate")
	if plate and plate:IsA("BasePart") then
		local hologram = plate:FindFirstChild("LockedHologram")
		if not unlocked and isMine(tower) then
			if not hologram then
				local zone = Zones[index]
				local billboard: BillboardGui = New("BillboardGui", {
					Name = "LockedHologram",
					Size = UDim2.fromOffset(360, 110),
					StudsOffset = Vector3.new(0, 14, 0),
					MaxDistance = 120,
					LightInfluence = 0,
					Parent = plate,
				})
				New("TextLabel", {
					Size = UDim2.fromScale(1, 0.55),
					BackgroundTransparency = 1,
					Text = `🔒 {string.upper(zone.Name)}`,
					TextScaled = true,
					FontFace = Style.Fonts.Display,
					TextColor3 = Color3.fromHex(zone.Primary),
					TextStrokeTransparency = 0.5,
					Parent = billboard,
				})
				New("TextLabel", {
					Position = UDim2.fromScale(0, 0.58),
					Size = UDim2.fromScale(1, 0.4),
					BackgroundTransparency = 1,
					Text = `{NumberFormat.Compact(zone.UnlockCost)} Bits`,
					TextScaled = true,
					FontFace = Style.Fonts.Heavy,
					TextColor3 = Style.Color("CurrencyBits"),
					Parent = billboard,
				})
			end
		elseif hologram then
			hologram:Destroy()
		end
	end
end

local function applyTower(tower: Model)
	local floors = tower:FindFirstChild("Floors")
	if floors then
		for _, floor in floors:GetChildren() do
			applyFloor(tower, floor)
		end
	end
	local mine = isMine(tower)
	for _, descendant in tower:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			-- Seul le propriétaire interagit avec sa tour.
			descendant.Enabled = mine
		elseif descendant:IsA("BasePart") and tierGlows[descendant] then
			WorldFx.PaintTier(descendant)
		end
	end
end

-- Vague d'allumage : les étages s'illuminent de bas en haut.
local function powerWave(tower: Model)
	local floors = tower:FindFirstChild("Floors")
	if not floors then
		return
	end
	for index = 1, #Zones do
		local floor = floors:FindFirstChild(`Floor{index}`)
		if floor then
			task.delay(index * 0.18, function()
				applyFloor(tower, floor)
				for _, descendant in floor:GetDescendants() do
					if descendant:IsA("PointLight") and descendant.Enabled then
						local target = descendant.Brightness
						descendant.Brightness = target * 4
						Motion.Tween(descendant, { Brightness = target }, 0.8)
					end
				end
			end)
		end
	end
end

------------------------------------------------------------------------------------
-- Paquets de données (tour du joueur, étage courant)
------------------------------------------------------------------------------------

local packetFolder: Folder
local packetPool: { BasePart } = {}
local activePackets = 0

local function spawnPacket(trace: BasePart, color: Color3)
	if activePackets > 24 then
		return
	end
	local packet = table.remove(packetPool)
		or New("Part", {
			Name = "Packet",
			Size = Vector3.new(0.9, 0.5, 1.6),
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
		})
	packet.Color = color
	packet.Transparency = 0
	local half = trace.Size.Z / 2
	local from = trace.CFrame * CFrame.new(0, 0.35, half)
	local to = trace.CFrame * CFrame.new(0, 0.35, -half)
	packet.CFrame = from
	packet.Parent = packetFolder
	activePackets += 1
	local tween = Motion.Tween(packet, { CFrame = to }, 1.6, Enum.EasingStyle.Linear)
	tween.Completed:Once(function()
		activePackets -= 1
		packet.Parent = nil
		table.insert(packetPool, packet)
	end)
end

local function packetLoop()
	while true do
		local state = Store.State
		local rate = Store.Rate()
		local interval = math.clamp(1.2 - math.log10(rate + 1) * 0.12, 0.25, 1.2)
		task.wait(interval)
		if state and state.Data.PoweredOn and state.Plot > 0 then
			local world = Workspace:FindFirstChild("World")
			local towers = world and world:FindFirstChild("Towers")
			local tower = towers and towers:FindFirstChild(`Tower{state.Plot}`)
			local floorIndex = WorldFx.CurrentFloor
			local floors = tower and tower:FindFirstChild("Floors")
			local floor = floors and floorIndex > 0 and floors:FindFirstChild(`Floor{floorIndex}`)
			if floor then
				local color = Color3.fromHex(Zones[floorIndex].Primary)
				for slot = 1, 3 do
					local level = state.Data.Levels[`Z{floorIndex}M{slot}`] or 0
					local trace = floor:FindFirstChild(`Trace{slot}`)
					if level > 0 and trace and trace:IsA("BasePart") then
						spawnPacket(trace, color)
					end
				end
			end
		end
	end
end

WorldFx.CurrentFloor = 0 -- mis à jour par ZoneTracker

------------------------------------------------------------------------------------
-- Enregistrement par tags (compatible streaming)
------------------------------------------------------------------------------------

local function track(tag: string, onAdd: (Instance) -> (), onRemove: ((Instance) -> ())?)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdd, instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(onAdd)
	if onRemove then
		CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemove)
	end
end

local function part(instance: Instance): BasePart?
	return if instance:IsA("BasePart") then instance else nil
end

local watchedTowers: { [Model]: boolean } = {}
local function watchTower(tower: Model?)
	if not tower or watchedTowers[tower] then
		return
	end
	watchedTowers[tower] = true
	tower.AttributeChanged:Connect(function(attribute: string)
		if attribute == "PoweredOn" and powered(tower) and isMine(tower) then
			powerWave(tower)
			applyTower(tower)
		elseif attribute == "Zone" or attribute == "OwnerUserId" or attribute == "PoweredOn" then
			applyTower(tower)
		end
	end)
	tower.Destroying:Connect(function()
		watchedTowers[tower] = nil
	end)
	task.defer(applyTower, tower)
end

function WorldFx.Start()
	packetFolder = New("Folder", { Name = "ClientPackets", Parent = Workspace })

	track("Spin", function(instance)
		local p = part(instance)
		if p then
			local axis = p:GetAttribute("Axis")
			spins[p] = {
				Axis = if type(axis) == "string" then axis else "X",
				Speed = 2 + math.random(),
				Tower = towerOf(p),
				Module = moduleOf(p),
			}
		end
	end, function(instance)
		spins[instance :: any] = nil
	end)
	track("RgbStrip", function(instance)
		local p = part(instance)
		if p then
			local tower = towerOf(p)
			rgbStrips[p] = { Tower = tower, Offset = p.Position.Y / 300 }
			watchTower(tower)
		end
	end, function(instance)
		rgbStrips[instance :: any] = nil
	end)
	track("TierGlow", function(instance)
		local p = part(instance)
		if p then
			tierGlows[p] = true
			WorldFx.PaintTier(p)
			local model = moduleOf(p)
			if model then
				setupModuleLabel(model)
			end
			watchTower(towerOf(p))
		end
	end, function(instance)
		tierGlows[instance :: any] = nil
	end)
	track("PulseGlow", function(instance)
		local p = part(instance)
		if p then
			pulses[p] = p.Transparency
		end
	end, function(instance)
		pulses[instance :: any] = nil
	end)
	track("Beacon", function(instance)
		local p = part(instance)
		if p then
			beacons[p] = { Base = p.Transparency, Tower = towerOf(p) }
		end
	end, function(instance)
		beacons[instance :: any] = nil
	end)
	track("Virus", function(instance)
		local p = part(instance)
		if p then
			viruses[p] = { Base = p.CFrame, Phase = math.random() * 10 }
			if not isMine(towerOf(p)) then
				local prompt = p:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					prompt.Enabled = false
				end
			end
			local highlight = Instance.new("Highlight")
			highlight.FillTransparency = 0.6
			highlight.OutlineColor = Style.Color("Danger")
			highlight.FillColor = Style.Color("Danger")
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Parent = p
		end
	end, function(instance)
		viruses[instance :: any] = nil
	end)
	track("Fragment", function(instance)
		local p = part(instance)
		if p then
			fragments[p] = { Base = p.CFrame, Phase = math.random() * 10 }
			local function refresh()
				local mine = isMine(towerOf(p))
				p.LocalTransparencyModifier = if mine and p:GetAttribute("Found") ~= true then 0 else 1
				local light = p:FindFirstChildOfClass("PointLight")
				if light then
					light.Enabled = mine and p:GetAttribute("Found") ~= true
				end
			end
			refresh()
			p:GetAttributeChangedSignal("Found"):Connect(refresh)
		end
	end, function(instance)
		fragments[instance :: any] = nil
	end)
	track("TerminalScreen", function(instance)
		local p = part(instance)
		if p then
			setupTerminal(p)
		end
	end)
	track("TowerSign", function(instance)
		local p = part(instance)
		if p then
			setupSign(p)
		end
	end)
	track("TitleHologram", function(instance)
		local p = part(instance)
		if p then
			setupTitle(p)
		end
	end)
	track("LeaderboardScreen", function(instance)
		local p = part(instance)
		if p then
			-- 25 px/stud : les 10 lignes du classement tiennent sur l'écran de 44x32 studs.
			boardScreens[p] = surface(p, Enum.NormalId.Front, 25)
			renderBoard(p)
		end
	end, function(instance)
		boardScreens[instance :: any] = nil
	end)
	Store.BoardsChanged:Connect(function()
		for screen in boardScreens do
			renderBoard(screen)
		end
	end)

	-- Animation (rotation chaque image ; couleurs à 30 Hz)
	local colorClock = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local reduced = Motion.IsReduced()
		local speedScale = if reduced then 0.3 else 1
		for p, info in spins do
			if (p.Position - eye).Magnitude < 220 and powered(info.Tower) then
				local model = info.Module
				local level = if model then model:GetAttribute("Level") else 1
				if type(level) == "number" and level > 0 then
					local angle = dt * info.Speed * speedScale * (1 + math.min(level, 100) / 40)
					p.CFrame *= if info.Axis == "Y" then CFrame.Angles(0, angle, 0) else CFrame.Angles(angle, 0, 0)
				end
			end
		end
		local t = os.clock()
		for p, info in viruses do
			local bob = math.sin(t * 3 + info.Phase) * 0.6
			p.CFrame = info.Base * CFrame.new(0, bob, 0) * CFrame.Angles(t * 2, t * 3, 0)
			if not reduced and math.random() < 0.04 then
				p.Size = Vector3.one * (2.6 + math.random() * 0.9)
			end
		end
		for p, info in fragments do
			p.CFrame = info.Base * CFrame.new(0, math.sin(t * 2 + info.Phase) * 0.5, 0) * CFrame.Angles(0, t, 0)
		end
		colorClock += dt
		if colorClock < 1 / 30 then
			return
		end
		colorClock = 0
		for p, info in rgbStrips do
			local tower = info.Tower
			if tower == nil or powered(tower) then
				p.Color = Color3.fromHSV(hueFor(tower, info.Offset), 0.55, 1)
				p.Transparency = 0.05
			else
				p.Transparency = 0.85
			end
		end
		for p in tierGlows do
			if p:GetAttribute("Rainbow") == true then
				p.Color = Color3.fromHSV((t * 0.2 + p.Position.Y / 50) % 1, 0.6, 1)
			end
		end
		for p, base in pulses do
			p.Transparency = math.min(base + (math.sin(t * 2.4) + 1) * 0.12, 0.9)
		end
		for p, info in beacons do
			local zone = if info.Tower then info.Tower:GetAttribute("Zone") else 0
			local strength = if type(zone) == "number" then zone / #Zones else 0
			p.Transparency = math.clamp(info.Base + 0.5 - strength * 0.5 + math.sin(t * 1.5) * 0.08, 0, 0.95)
		end
	end)

	task.spawn(packetLoop)
end

-- La vague d'allumage est déclenchée par l'attribut PoweredOn de la tour (voir watchTower),
-- qui arrive toujours après la mise à jour serveur : rien à faire ici pour l'instant.
function WorldFx.OnFx(_kind: string, _payload: any) end

return WorldFx
