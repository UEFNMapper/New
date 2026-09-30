--!strict
--[[
	WorldFx : toute la vie visuelle du PC géant, côté client uniquement (zéro coût serveur).
	Fonctionne avec StreamingEnabled : chaque élément est pris en charge quand il
	arrive (CollectionService) et oublié quand il repart.

	Le monde est PARTAGÉ, mais chaque joueur y voit SA progression, calculée avec ses données :
	tier des machines, portails ouverts/verrouillés, fragments restant à trouver, ses virus.

	Tags gérés : Spin, DecorSpin, RgbStrip, TierGlow, PulseGlow, Beacon, ZoneGate, Virus,
	Fragment, TerminalScreen, LeaderboardScreen, TitleHologram.
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
local APP = Branding.PartnerApp

local WorldFx = {}

WorldFx.CurrentZone = 0 -- mis à jour par ZoneTracker (0 = hub)

local player = Players.LocalPlayer

local spins: { [BasePart]: { Axis: string, Speed: number, Module: Instance?, Decor: boolean } } = {}
local rgbStrips: { [BasePart]: number } = {} -- décalage de teinte
local tierGlows: { [BasePart]: boolean } = {}
local pulses: { [BasePart]: number } = {}
local viruses: { [BasePart]: { Base: CFrame, Phase: number } } = {}
local fragments: { [BasePart]: { Base: CFrame, Phase: number } } = {}
local beacons: { [BasePart]: number } = {}
local gates: { [BasePart]: boolean } = {}
local moduleModels: { [Instance]: () -> () } = {} -- modèle -> rafraîchissement de l'étiquette
local boardScreens: { [BasePart]: SurfaceGui } = {}

------------------------------------------------------------------------------------
-- Données du joueur local
------------------------------------------------------------------------------------

local function data(): any
	return Store.Data()
end

local function powered(): boolean
	local d = data()
	return d ~= nil and d.PoweredOn == true
end

local function unlockedZone(): number
	local d = data()
	return if d then d.Zone else 1
end

local function levelOf(id: string): number
	local d = data()
	return if d then (d.Levels[id] or 0) else 0
end

local function fixedHue(): number?
	local state = Store.State
	if state and state.Passes and state.Passes.RgbStudio then
		local hue = state.Data.Settings.RgbHue
		if type(hue) == "number" and hue >= 0 then
			return hue
		end
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
-- Surfaces (terminaux au style de l'app AngAInOne, classements, titre)
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

-- Écran de terminal : une "fenêtre" de l'app partenaire (gris Fluent, bouton violet).
local function setupTerminal(screen: BasePart)
	local accentHex = screen:GetAttribute("Accent")
	local accent = if type(accentHex) == "string" then Color3.fromHex(accentHex) else Style.Color("AccentCyan")
	local gui = surface(screen, Enum.NormalId.Front, 40)
	gui:ClearAllChildren()
	local window: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromHex(APP.Surface),
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		Create.Corner(14) :: Instance,
		New("UIStroke", { Color = accent, Thickness = 3, Transparency = 0.3 }),
	})
	New("TextLabel", {
		Position = UDim2.fromScale(0.06, 0.05),
		Size = UDim2.fromScale(0.88, 0.16),
		BackgroundTransparency = 1,
		Text = APP.Name,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Style.Fonts.Medium,
		TextColor3 = Color3.fromHex(APP.TextDim),
		Parent = window,
	})
	New("TextLabel", {
		Position = UDim2.fromScale(0.06, 0.26),
		Size = UDim2.fromScale(0.88, 0.3),
		BackgroundTransparency = 1,
		Text = tostring(screen:GetAttribute("Label") or ""),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Style.Fonts.Bold,
		TextColor3 = Color3.fromHex(APP.Text),
		Parent = window,
	})
	New("Frame", {
		Position = UDim2.fromScale(0.06, 0.66),
		Size = UDim2.fromScale(0.5, 0.22),
		BackgroundColor3 = Color3.fromHex(APP.Accent),
		BorderSizePixel = 0,
		Parent = window,
	}, {
		Create.Corner(8) :: Instance,
		New("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "Ouvrir  [E]",
			TextScaled = true,
			FontFace = Style.Fonts.Bold,
			TextColor3 = Color3.fromHex(APP.Text),
		}, { New("UITextSizeConstraint", { MaxTextSize = 60 }) :: Instance }),
	})
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

------------------------------------------------------------------------------------
-- Machines : tier et étiquette selon les niveaux DU JOUEUR LOCAL
------------------------------------------------------------------------------------

function WorldFx.PaintTier(part: BasePart)
	local model = moduleOf(part)
	local id = if model then model:GetAttribute("ModuleId") else nil
	local n = if type(id) == "string" then levelOf(id) else 0
	local color, rainbow = tierColor(n)
	if not color or not powered() then
		part.Color = Style.Color("MetalLight")
		part.Transparency = 0.7
		part:SetAttribute("Rainbow", false)
		return
	end
	part.Color = color
	part.Transparency = 0.05
	part:SetAttribute("Rainbow", rainbow)
end

local function setupModuleLabel(model: Instance)
	if moduleModels[model] then
		return
	end
	local anchor = model:FindFirstChild("LabelAnchor")
	local id = model:GetAttribute("ModuleId")
	local def = if type(id) == "string" then Modules.Get(id) else nil
	if not (anchor and anchor:IsA("BasePart")) or not def then
		return
	end
	local previous = anchor:FindFirstChild("ModuleLabel")
	if previous then
		previous:Destroy() -- ré-entrée après un streaming out : on reconstruit l'étiquette
	end
	local billboard: BillboardGui = New("BillboardGui", {
		Name = "ModuleLabel",
		Size = UDim2.fromOffset(200, 54),
		StudsOffset = Vector3.new(0, 1.5, 0),
		MaxDistance = 70,
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
	local shown = -1
	local function refresh()
		local n = levelOf(def.Id)
		if n == shown then
			return
		end
		local flash = shown >= 0 and n > shown
		shown = n
		level.Text = if n > 0 then `NIV. {n}` else "À ACHETER"
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and tierGlows[descendant] then
				WorldFx.PaintTier(descendant)
				-- Petit flash de la machine à chaque amélioration
				if flash and not Motion.IsReduced() then
					local original = descendant.Transparency
					descendant.Transparency = 0
					task.delay(0.12, function()
						descendant.Transparency = original
					end)
				end
			end
		end
	end
	moduleModels[model] = refresh
	refresh()
	-- Oublié quand il quitte le monde (destruction OU streaming out).
	local connection: RBXScriptConnection
	connection = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			moduleModels[model] = nil
			connection:Disconnect()
		end
	end)
end

------------------------------------------------------------------------------------
-- Portails de zone : barrière solide (localement) tant que la zone est verrouillée
------------------------------------------------------------------------------------

local function applyGate(barrier: BasePart)
	local zoneAttr = barrier:GetAttribute("Zone")
	local index = if type(zoneAttr) == "number" then zoneAttr else 2
	local zone = Zones[index]
	if not zone then
		return
	end
	local locked = index > unlockedZone()
	-- Collision locale : seul le personnage du joueur local est concerné.
	barrier.CanCollide = locked
	barrier.Transparency = if locked then 0.1 else 0.92
	local light = barrier:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = locked
	end
	local gate = barrier.Parent
	if gate then
		for _, descendant in gate:GetDescendants() do
			if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("Action") == "Unlock" then
				descendant.Enabled = locked
			end
		end
	end
	local hologram = barrier:FindFirstChild("LockedHologram")
	if locked and not hologram then
		local billboard: BillboardGui = New("BillboardGui", {
			Name = "LockedHologram",
			Size = UDim2.fromOffset(380, 120),
			StudsOffset = Vector3.new(0, 4, 0),
			MaxDistance = 160,
			LightInfluence = 0,
			Parent = barrier,
		})
		New("TextLabel", {
			Size = UDim2.fromScale(1, 0.4),
			BackgroundTransparency = 1,
			Text = `🔒 {string.upper(zone.Name)}`,
			TextScaled = true,
			FontFace = Style.Fonts.Display,
			TextColor3 = Color3.fromHex(zone.Primary),
			TextStrokeTransparency = 0.4,
			Parent = billboard,
		})
		New("TextLabel", {
			Position = UDim2.fromScale(0, 0.42),
			Size = UDim2.fromScale(1, 0.26),
			BackgroundTransparency = 1,
			Text = `Section « {zone.AppSection} »`,
			TextScaled = true,
			FontFace = Style.Fonts.Medium,
			TextColor3 = Style.Color("TextPrimary"),
			TextStrokeTransparency = 0.5,
			Parent = billboard,
		})
		New("TextLabel", {
			Position = UDim2.fromScale(0, 0.7),
			Size = UDim2.fromScale(1, 0.3),
			BackgroundTransparency = 1,
			Text = `{NumberFormat.Compact(zone.UnlockCost)} Bits`,
			TextScaled = true,
			FontFace = Style.Fonts.Heavy,
			TextColor3 = Style.Color("CurrencyBits"),
			TextStrokeTransparency = 0.5,
			Parent = billboard,
		})
	elseif not locked and hologram then
		hologram:Destroy()
	end
end

-- Ouverture animée d'un portail (quand la zone vient d'être débloquée).
local function openGate(index: number)
	for barrier in gates do
		if barrier:GetAttribute("Zone") == index then
			local target = barrier.Transparency
			barrier.Transparency = 0
			barrier.Color = Style.Color("TextPrimary")
			Motion.Tween(barrier, { Transparency = target, Color = Color3.fromHex(Zones[index].Primary) }, 1.4)
		end
	end
end

------------------------------------------------------------------------------------
-- Fragments et virus (propres au joueur local)
------------------------------------------------------------------------------------

local function applyFragment(p: BasePart)
	local id = p:GetAttribute("FragmentId")
	local d = data()
	local zone = if type(id) == "string" then tonumber(string.match(id, "^Z(%d+)F")) else nil
	local visible = d ~= nil and type(id) == "string" and d.Fragments[id] ~= true and zone ~= nil and zone <= d.Zone
	p.LocalTransparencyModifier = if visible then 0 else 1
	local light = p:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = visible
	end
end

------------------------------------------------------------------------------------
-- Rafraîchissement global quand l'état du joueur change
------------------------------------------------------------------------------------

local lastZone = -1
local lastPowered = false
local function refreshAll()
	for p in tierGlows do
		WorldFx.PaintTier(p)
	end
	for _, refresh in moduleModels do
		refresh()
	end
	for barrier in gates do
		applyGate(barrier)
	end
	for p in fragments do
		applyFragment(p)
	end
	local zone = unlockedZone()
	if lastZone > 0 and zone > lastZone then
		for index = lastZone + 1, zone do
			openGate(index)
		end
	end
	lastZone = zone
	local on = powered()
	if on and not lastPowered and not Motion.IsReduced() then
		-- Vague d'allumage : les néons de machines flashent en blanc puis prennent leur tier.
		for p in tierGlows do
			local original = p.Color
			p.Color = Style.Color("TextPrimary")
			Motion.Tween(p, { Color = original }, 0.9)
		end
	end
	lastPowered = on
end

------------------------------------------------------------------------------------
-- Paquets de données (zone courante)
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
	-- La piste va de la machine (côté +Z local) vers le collecteur (côté -Z local).
	local half = trace.Size.Z / 2
	local from = trace.CFrame * CFrame.new(0, 0.35, half)
	local to = trace.CFrame * CFrame.new(0, 0.35, -half)
	packet.CFrame = from
	packet.Parent = packetFolder
	activePackets += 1
	local duration = math.clamp(trace.Size.Z / 30, 1, 2.2)
	local tween = Motion.Tween(packet, { CFrame = to }, duration, Enum.EasingStyle.Linear)
	tween.Completed:Once(function()
		activePackets -= 1
		packet.Parent = nil
		table.insert(packetPool, packet)
	end)
end

local function packetLoop()
	while true do
		local rate = Store.Rate()
		local interval = math.clamp(1.2 - math.log10(rate + 1) * 0.12, 0.25, 1.2)
		task.wait(interval)
		local zoneIndex = WorldFx.CurrentZone
		if powered() and zoneIndex > 0 and zoneIndex <= unlockedZone() then
			local world = Workspace:FindFirstChild("World")
			local zones = world and world:FindFirstChild("Zones")
			local zoneModel = zones and zones:FindFirstChild(`Zone{zoneIndex}`)
			if zoneModel then
				local color = Color3.fromHex(Zones[zoneIndex].Primary)
				for slot = 1, 3 do
					local trace = zoneModel:FindFirstChild(`Trace{slot}`)
					if levelOf(`Z{zoneIndex}M{slot}`) > 0 and trace and trace:IsA("BasePart") then
						spawnPacket(trace, color)
					end
				end
			end
		end
	end
end

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

local function trackSpin(decor: boolean)
	return function(instance: Instance)
		local p = part(instance)
		if p then
			local axis = p:GetAttribute("Axis")
			local speed = p:GetAttribute("Speed")
			spins[p] = {
				Axis = if type(axis) == "string" then axis else "X",
				Speed = if type(speed) == "number" then speed else (if decor then 1.2 else 2) + math.random(),
				Module = if decor then nil else moduleOf(p),
				Decor = decor,
			}
		end
	end
end

function WorldFx.Start()
	packetFolder = New("Folder", { Name = "ClientPackets", Parent = Workspace })

	local function forget(map: { [any]: any })
		return function(instance: Instance)
			map[instance] = nil
		end
	end

	track("Spin", trackSpin(false), forget(spins))
	track("DecorSpin", trackSpin(true), forget(spins))
	track("RgbStrip", function(instance)
		local p = part(instance)
		if p then
			rgbStrips[p] = (p.Position.X + p.Position.Z) / 900
		end
	end, forget(rgbStrips))
	track("TierGlow", function(instance)
		local p = part(instance)
		if p then
			tierGlows[p] = true
			WorldFx.PaintTier(p)
			local model = moduleOf(p)
			if model then
				setupModuleLabel(model)
			end
		end
	end, forget(tierGlows))
	track("PulseGlow", function(instance)
		local p = part(instance)
		if p then
			pulses[p] = p.Transparency
		end
	end, forget(pulses))
	track("Beacon", function(instance)
		local p = part(instance)
		if p then
			beacons[p] = p.Transparency
		end
	end, forget(beacons))
	track("ZoneGate", function(instance)
		local p = part(instance)
		if p then
			gates[p] = true
			applyGate(p)
		end
	end, forget(gates))
	track("Virus", function(instance)
		local p = part(instance)
		if not p then
			return
		end
		if p:GetAttribute("OwnerUserId") ~= player.UserId then
			-- Virus d'un autre joueur : invisible et non interactif pour nous.
			p.LocalTransparencyModifier = 1
			local prompt = p:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = false
			end
			-- Le prompt peut se répliquer après le virus : on le désactive à son arrivée.
			p.ChildAdded:Connect(function(child: Instance)
				if child:IsA("ProximityPrompt") then
					child.Enabled = false
				end
			end)
			return
		end
		viruses[p] = { Base = p.CFrame, Phase = math.random() * 10 }
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.6
		highlight.OutlineColor = Style.Color("Danger")
		highlight.FillColor = Style.Color("Danger")
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = p
	end, forget(viruses))
	track("Fragment", function(instance)
		local p = part(instance)
		if p then
			fragments[p] = { Base = p.CFrame, Phase = math.random() * 10 }
			applyFragment(p)
		end
	end, forget(fragments))
	track("TerminalScreen", function(instance)
		local p = part(instance)
		if p then
			setupTerminal(p)
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
	end, forget(boardScreens))
	Store.BoardsChanged:Connect(function()
		for screen in boardScreens do
			renderBoard(screen)
		end
	end)
	Store.Changed:Connect(refreshAll)
	if Store.State then
		task.defer(refreshAll)
	end

	-- Animation (rotation chaque image ; couleurs à 30 Hz)
	local colorClock = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local reduced = Motion.IsReduced()
		local speedScale = if reduced then 0.3 else 1
		for p, info in spins do
			if (p.Position - eye).Magnitude < 320 then
				local factor = 1
				if not info.Decor then
					local model = info.Module
					local id = if model then model:GetAttribute("ModuleId") else nil
					local level = if type(id) == "string" then levelOf(id) else 0
					factor = if level > 0 and powered() then 1 + math.min(level, 100) / 40 else 0
				end
				if factor > 0 then
					local angle = dt * info.Speed * speedScale * factor
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
		local hue = fixedHue()
		for p, offset in rgbStrips do
			p.Color = Color3.fromHSV(hue or (t * 0.06 + offset) % 1, 0.55, 1)
		end
		for p in tierGlows do
			if p:GetAttribute("Rainbow") == true then
				p.Color = Color3.fromHSV((t * 0.2 + p.Position.Y / 50) % 1, 0.6, 1)
			end
		end
		for p, base in pulses do
			p.Transparency = math.min(base + (math.sin(t * 2.4) + 1) * 0.12, 0.9)
		end
		local strength = unlockedZone() / #Zones
		for p, base in beacons do
			p.Transparency = math.clamp(base + 0.2 - strength * 0.2 + math.sin(t * 1.5) * 0.08, 0, 0.95)
		end
	end)

	task.spawn(packetLoop)
end

function WorldFx.OnFx(_kind: string, _payload: any) end

return WorldFx
