--!strict
--[[
	WorldFx : la vie visuelle de la tour, côté client (compatible StreamingEnabled).
	- Écrans du lobby : titre holographique, 3 classements
	- Orbes de Bits : tournent, et disparaissent pour moi une fois ramassées (ascension en cours)
	- Portails de monde : solides pour moi tant que le terminal n'est pas réussi
	- Checkpoints (« points de restauration » de l'app AngAInOne) : éteints / atteint (vert) /
	  prochain (qui pulse)
	- Traînées RGB animées, et étiquette « Étape X » au-dessus des autres joueurs
	Tags : TitleHologram, LeaderboardScreen, Coin, UsbKey, WorldGate, Checkpoint.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local NumberFormat = require(Shared.Util.NumberFormat)
local Time = require(Shared.Util.Time)

local Store = require(script.Parent.Store)
local Motion = require(script.Parent.Parent.UI.Motion)
local Style = require(script.Parent.Parent.UI.Style)
local Create = require(script.Parent.Parent.UI.Create)

local New = Create.New

local WorldFx = {}

local player = Players.LocalPlayer

local coins: { [BasePart]: { Base: CFrame, Phase: number } } = {}
local usbKeys: { [BasePart]: { Base: CFrame, Phase: number } } = {} -- clés USB dorées (une fois pour toujours)
local gates: { [BasePart]: boolean } = {}
local checkpoints: { [BasePart]: number } = {}
local boardScreens: { [BasePart]: SurfaceGui } = {}

local function data(): any
	return Store.Data()
end

------------------------------------------------------------------------------------
-- Écrans du lobby
------------------------------------------------------------------------------------

local function surface(part: BasePart, face: Enum.NormalId, pixels: number, name: string): SurfaceGui
	local existing = part:FindFirstChild(name)
	if existing and existing:IsA("SurfaceGui") then
		return existing
	end
	return New("SurfaceGui", {
		Name = name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixels,
		LightInfluence = 0,
		Brightness = 1.5,
		ZOffset = 1,
		Parent = part,
	})
end

local BOARD_INFO: { [string]: { Title: string, Color: string } } = {
	Wins = { Title = "VICTOIRES", Color = "CurrencyBits" },
	BestTime = { Title = "MEILLEURS TEMPS", Color = "AccentCyan" },
	Stage = { Title = "PLUS HAUT", Color = "AccentViolet" },
}

local function formatBoard(board: string, value: number): string
	if board == "BestTime" then
		return Time.Clock(value)
	elseif board == "Stage" then
		return `étape {value}`
	end
	return NumberFormat.Compact(value)
end

local function renderBoard(screen: BasePart)
	local gui = boardScreens[screen]
	if not gui then
		return
	end
	gui:ClearAllChildren()
	local boardKey = tostring(screen:GetAttribute("Board") or "Wins")
	local info = BOARD_INFO[boardKey] or BOARD_INFO.Wins
	local root: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.Color("BgDeep"),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		New("UIStroke", { Color = Style.Color(info.Color), Thickness = 6 }) :: Instance,
		Create.Padding(22),
		Create.List(Enum.FillDirection.Vertical, 6),
	})
	New("TextLabel", {
		Size = UDim2.new(1, 0, 0.14, 0),
		BackgroundTransparency = 1,
		Text = info.Title,
		TextScaled = true,
		FontFace = Style.Fonts.Display,
		TextColor3 = Style.Color(info.Color),
		LayoutOrder = 0,
		Parent = root,
	})
	local boards = Store.Boards
	local entries = if boards and boards[boardKey] then boards[boardKey] else {}
	for rank = 1, math.min(#entries, 10) do
		local entry = entries[rank]
		New("TextLabel", {
			Size = UDim2.new(1, 0, 0.075, 0),
			BackgroundTransparency = 1,
			Text = `#{rank}  {entry.Name}  —  {formatBoard(boardKey, entry.Value)}`,
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
			Size = UDim2.new(1, 0, 0.08, 0),
			BackgroundTransparency = 1,
			Text = "Sois le premier à grimper !",
			TextScaled = true,
			FontFace = Style.Fonts.Medium,
			TextColor3 = Style.Color("TextMuted"),
			LayoutOrder = 1,
			Parent = root,
		})
	end
end

local function setupTitle(part: BasePart)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local target = surface(part, face, 20, `Title{face.Name}`)
		target:ClearAllChildren()
		New("TextLabel", {
			Size = UDim2.new(1, 0, 0.66, 0),
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
			Position = UDim2.fromScale(0, 0.68),
			Size = UDim2.new(1, 0, 0.3, 0),
			BackgroundTransparency = 1,
			Text = "Grimpe la tour. Échappe au virus.",
			TextScaled = true,
			FontFace = Style.Fonts.Medium,
			TextColor3 = Style.Color("AccentCyan"),
			Parent = target,
		})
	end
end

------------------------------------------------------------------------------------
-- Progression du joueur local dans le monde
------------------------------------------------------------------------------------

local function applyCoin(p: BasePart)
	local id = p:GetAttribute("CoinId")
	local d = data()
	local taken = d ~= nil and type(id) == "string" and d.RunCoins[id] == true
	p.LocalTransparencyModifier = if taken then 1 else 0
	-- Descendants aussi : habillage 3D soudé (modèle BitCoin), lumière, particules.
	for _, node in p:GetDescendants() do
		if node:IsA("BasePart") then
			node.LocalTransparencyModifier = if taken then 1 else 0
		elseif node:IsA("PointLight") or node:IsA("ParticleEmitter") then
			(node :: any).Enabled = not taken
		end
	end
end

-- Clé USB déjà trouvée : cachée pour ce joueur (elle reste dans la tour pour les autres).
local function applyKey(p: BasePart)
	local id = p:GetAttribute("KeyId")
	local d = data()
	local found = d ~= nil and type(id) == "string" and d.UsbKeys[id] == true
	for _, node in p:GetDescendants() do
		if node:IsA("BasePart") then
			node.LocalTransparencyModifier = if found then 1 else 0
		elseif node:IsA("PointLight") or node:IsA("ParticleEmitter") or node:IsA("BillboardGui") then
			(node :: any).Enabled = not found
		end
	end
	p.LocalTransparencyModifier = if found then 1 else 0
end

local function applyGate(barrier: BasePart)
	local world = barrier:GetAttribute("World")
	local d = data()
	local cleared = if d then d.Cleared else 0
	local locked = type(world) ~= "number" or world > cleared
	-- Collision LOCALE : seul mon personnage est bloqué tant que le terminal n'est pas réussi.
	barrier.CanCollide = locked
	barrier.LocalTransparencyModifier = if locked then 0 else 0.9
	local hologram = barrier:FindFirstChild("LockedHologram")
	if locked and not hologram then
		local billboard: BillboardGui = New("BillboardGui", {
			Name = "LockedHologram",
			Size = UDim2.fromOffset(300, 64),
			StudsOffset = Vector3.new(0, 4, 0),
			MaxDistance = 80,
			LightInfluence = 0,
			Parent = barrier,
		})
		New("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "🔒 Élimine les virus au terminal 💻",
			TextScaled = true,
			FontFace = Style.Fonts.Heavy,
			TextColor3 = Style.Color("TextPrimary"),
			TextStrokeTransparency = 0.4,
			Parent = billboard,
		})
	elseif not locked and hologram then
		hologram:Destroy()
	end
end

local function applyCheckpoint(pad: BasePart, stage: number)
	local d = data()
	local current = if d then d.Stage else 0
	local accent = if stage <= current
		then Style.Color("Success")
		elseif stage == current + 1 then Style.Color("CurrencyBits")
		else Style.Color("MetalLight")
	local isNext = stage == current + 1
	for _, child in pad:GetDescendants() do
		if child:IsA("BasePart") and child.Material == Enum.Material.Neon then
			child.Color = accent
			-- Transparence d'origine mémorisée : restaurée quand le pad cesse de pulser.
			local base = child:GetAttribute("BaseTransparency")
			if type(base) ~= "number" then
				base = child.Transparency
				child:SetAttribute("BaseTransparency", base)
			end
			if not isNext then
				child.Transparency = base :: number
			end
		end
	end
	pad:SetAttribute("Next", isNext)
end

local function refreshAll()
	for p in coins do
		applyCoin(p)
	end
	for p in usbKeys do
		applyKey(p)
	end
	for barrier in gates do
		applyGate(barrier)
	end
	for pad, stage in checkpoints do
		applyCheckpoint(pad, stage)
	end
end

------------------------------------------------------------------------------------
-- Étiquettes au-dessus des autres joueurs
------------------------------------------------------------------------------------

local function tagCharacter(other: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not (head and head:IsA("BasePart")) then
		return
	end
	local billboard: BillboardGui = New("BillboardGui", {
		Name = "StageTag",
		Size = UDim2.fromOffset(120, 28),
		StudsOffset = Vector3.new(0, 2.6, 0),
		MaxDistance = 90,
		LightInfluence = 0,
		Parent = head,
	})
	local label: TextLabel = New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Style.Color("BgDeep"),
		BackgroundTransparency = 0.35,
		Text = "",
		TextScaled = true,
		FontFace = Style.Fonts.Heavy,
		TextColor3 = Style.Color("TextPrimary"),
		Parent = billboard,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) :: Instance, Create.Padding(3, 10) })
	local function refresh()
		local stage = other:GetAttribute("Stage")
		label.Text = `Étape {if type(stage) == "number" then stage else 0}`
	end
	refresh()
	local connection = other:GetAttributeChangedSignal("Stage"):Connect(refresh)
	billboard.Destroying:Connect(function()
		connection:Disconnect()
	end)
end

local function watchPlayer(other: Player)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(character: Model)
		tagCharacter(other, character)
	end)
	if other.Character then
		task.spawn(tagCharacter, other, other.Character)
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

function WorldFx.Start()
	track("TitleHologram", function(instance)
		local p = part(instance)
		if p then
			setupTitle(p)
		end
	end)
	track("LeaderboardScreen", function(instance)
		local p = part(instance)
		if p then
			boardScreens[p] = surface(p, Enum.NormalId.Front, 12, "Board")
			renderBoard(p)
		end
	end, function(instance)
		boardScreens[instance :: any] = nil
	end)
	track("Coin", function(instance)
		local p = part(instance)
		if p then
			coins[p] = { Base = p.CFrame, Phase = math.random() * 10 }
			applyCoin(p)
		end
	end, function(instance)
		coins[instance :: any] = nil
	end)
	track("UsbKey", function(instance)
		local p = part(instance)
		if p then
			usbKeys[p] = { Base = p.CFrame, Phase = math.random() * 10 }
			applyKey(p)
		end
	end, function(instance)
		usbKeys[instance :: any] = nil
	end)
	track("WorldGate", function(instance)
		local p = part(instance)
		if p then
			gates[p] = true
			applyGate(p)
		end
	end, function(instance)
		gates[instance :: any] = nil
	end)
	track("Checkpoint", function(instance)
		local p = part(instance)
		local stage = if p then p:GetAttribute("Stage") else nil
		if p and type(stage) == "number" then
			checkpoints[p] = stage
			applyCheckpoint(p, stage)
		end
	end, function(instance)
		checkpoints[instance :: any] = nil
	end)
	Store.BoardsChanged:Connect(function()
		for screen in boardScreens do
			renderBoard(screen)
		end
	end)
	Store.Changed:Connect(refreshAll)

	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	-- Animation : orbes qui tournent, checkpoint suivant qui pulse, traînées RGB.
	local colorClock = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local t = os.clock()
		local reduced = Motion.IsReduced()
		for p, info in coins do
			if (p.Position - eye).Magnitude < 200 then
				local bob = if reduced then 0 else math.sin(t * 2.5 + info.Phase) * 0.4
				p.CFrame = info.Base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * 2 + info.Phase, 0)
			end
		end
		for p, info in usbKeys do
			if (p.Position - eye).Magnitude < 200 then
				local bob = if reduced then 0 else math.sin(t * 2 + info.Phase) * 0.5
				p.CFrame = info.Base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * 1.4 + info.Phase, 0)
			end
		end
		colorClock += dt
		if colorClock < 1 / 20 then
			return
		end
		colorClock = 0
		local pulse = 0.5 + math.sin(t * 4) * 0.5
		for pad in checkpoints do
			if pad:GetAttribute("Next") == true then
				for _, child in pad:GetDescendants() do
					if child:IsA("BasePart") and child.Material == Enum.Material.Neon then
						child.Transparency = 0.1 + pulse * 0.4
					end
				end
			end
		end
		-- Traînées « RGB Gamer » : couleur qui tourne
		for _, other in Players:GetPlayers() do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local folder = root and root:FindFirstChild("AngaTrail")
			local trail = folder and folder:FindFirstChildOfClass("Trail")
			if trail and trail:GetAttribute("Rainbow") == true then
				local hue = (t * 0.25) % 1
				trail.Color = ColorSequence.new(Color3.fromHSV(hue, 0.7, 1), Color3.fromHSV((hue + 0.3) % 1, 0.7, 1))
			end
		end
	end)
end

-- Tour du monde courant (pour d'autres contrôleurs).
function WorldFx.CurrentWorld(): number
	local d = data()
	return if d then Tower.RunWorld(d.Stage, d.Cleared) else 0
end

return WorldFx
