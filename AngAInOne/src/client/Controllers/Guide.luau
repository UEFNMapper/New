--!strict
--[[
	Guide : flèches VFX qui montrent au joueur OÙ ALLER.

	1. Chevrons lumineux au sol (›››) qui défilent du joueur vers la destination (style GPS)
	2. Marqueur au-dessus de la cible : flèche flottante qui rebondit + anneau qui pulse au sol
	   + surbrillance (Highlight) de l'objet à utiliser
	3. Flèche au bord de l'écran (avec la distance) quand la cible n'est pas visible
	4. Guidage intelligent : cible sur un autre étage -> l'ascenseur ; joueur dehors -> la porte

	Actif pendant le tutoriel, puis quand un objectif est prêt (étage à débloquer,
	surchauffe, manque de Watts). Tout est côté client (aucun coût serveur).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local GameConfig = require(Shared.Config.GameConfig)
local WorldLayout = require(Shared.Config.WorldLayout)

local Store = require(script.Parent.Store)
local WorldFx = require(script.Parent.WorldFx)
local Style = require(script.Parent.Parent.UI.Style)
local Motion = require(script.Parent.Parent.UI.Motion)

local Guide = {}

local CHEVRONS = 12
local SPACING = 3.5
local ARRIVED_DISTANCE = 8

local folder: Folder
local chevrons: { { Left: Part, Right: Part } } = {}
local marker: Model
local markerParts: { Part } = {}
local ring: Part
local highlight: Highlight
local edgeArrow: Frame
local edgeLabel: TextLabel

type Goal = { Floor: number, Name: string, Sub: string? }

------------------------------------------------------------------------------------
-- Où faut-il aller ?
------------------------------------------------------------------------------------

local function ownTower(): Model?
	local state = Store.State
	if not state or state.Plot == 0 then
		return nil
	end
	local world = Workspace:FindFirstChild("World")
	local towers = world and world:FindFirstChild("Towers")
	local tower = towers and towers:FindFirstChild(`Tower{state.Plot}`)
	return if tower and tower:IsA("Model") then tower else nil
end

local function floorModel(tower: Model, floor: number): Instance?
	local floors = tower:FindFirstChild("Floors")
	return floors and floors:FindFirstChild(`Floor{floor}`)
end

-- Objectif actuel (étage + nom de l'objet dans l'étage), nil = pas de guidage.
local function currentGoal(): Goal?
	local state = Store.State
	if not state then
		return nil
	end
	local data = state.Data
	if not data.PoweredOn then
		return nil
	end
	local step = data.Tutorial
	local production = state.Production
	if step == 2 then
		return { Floor = 1, Name = "Collector" }
	elseif step == 3 or step == 4 then
		return { Floor = 1, Name = "Modules", Sub = "Z1M1" }
	elseif step == 5 then
		if Store.Bits() >= Zones[2].UnlockCost then
			return { Floor = 1, Name = "UnlockTerminal" }
		end
		if not state.Passes.AutoCollect then
			return { Floor = 1, Name = "Collector" }
		end
		return nil
	elseif step == 6 then
		return { Floor = 2, Name = "CapsuleTerminal" }
	end
	-- Après le tutoriel : seulement quand une action utile est possible (on ne harcèle pas).
	if production.ThermalEfficiency < 0.9 and data.Zone >= GameConfig.Cooling.UnlockZone then
		return { Floor = GameConfig.Cooling.UnlockZone, Name = "CoolingTerminal" }
	end
	if production.PowerEfficiency < 0.9 then
		return { Floor = 1, Name = "PowerTerminal" }
	end
	local nextZone = Zones[data.Zone + 1]
	if nextZone and Store.Bits() >= nextZone.UnlockCost then
		return { Floor = data.Zone, Name = "UnlockTerminal" }
	end
	return nil
end

local function positionOf(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		return target:GetPivot().Position
	end
	return nil
end

-- Résout l'objectif en une destination concrète selon où se trouve le joueur.
-- Renvoie : position au sol, objet à mettre en surbrillance, libellé.
local function resolve(goal: Goal): (Vector3?, Instance?, string)
	local tower = ownTower()
	local state = Store.State
	if not tower or not state then
		return nil, nil, ""
	end
	local playerFloor = WorldFx.CurrentFloor
	if playerFloor == 0 then
		-- Dehors : direction la porte de sa tour.
		local door = WorldLayout.TowerCFrame(state.Plot)
			* CFrame.new(0, WorldLayout.FloorY(1), -WorldLayout.TOWER_DEPTH / 2 - 6)
		return door.Position, nil, "Ta tour"
	end
	if playerFloor ~= goal.Floor then
		-- Mauvais étage : direction l'ascenseur.
		local floor = floorModel(tower, playerFloor)
		local elevator = floor and floor:FindFirstChild("Elevator")
		if elevator then
			return positionOf(elevator), elevator, `Ascenseur → étage {goal.Floor}`
		end
		return nil, nil, ""
	end
	local floor = floorModel(tower, goal.Floor)
	local target = floor and floor:FindFirstChild(goal.Name)
	if target and goal.Sub then
		target = target:FindFirstChild(goal.Sub)
	end
	if not target then
		return nil, nil, ""
	end
	return positionOf(target), target, ""
end

------------------------------------------------------------------------------------
-- Construction des visuels
------------------------------------------------------------------------------------

local function neon(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Size = size
	part.Color = color
	part.Transparency = 1
	part.Parent = folder
	return part
end

local function buildWorld()
	folder = Instance.new("Folder")
	folder.Name = "GuideFx"
	folder.Parent = Workspace

	local brand = Style.Color("BrandAnga")
	local gold = Style.Color("CurrencyBits")
	for index = 1, CHEVRONS do
		local color = brand:Lerp(gold, (index - 1) / (CHEVRONS - 1))
		table.insert(chevrons, {
			Left = neon("ChevronL", Vector3.new(0.35, 0.12, 1.5), color),
			Right = neon("ChevronR", Vector3.new(0.35, 0.12, 1.5), color),
		})
	end

	-- Marqueur : flèche vers le bas au-dessus de la cible
	marker = Instance.new("Model")
	marker.Name = "GuideMarker"
	marker.Parent = folder
	local shaft = neon("Shaft", Vector3.new(0.6, 2.4, 0.6), gold)
	local leftHead = neon("HeadL", Vector3.new(0.6, 1.8, 0.6), gold)
	local rightHead = neon("HeadR", Vector3.new(0.6, 1.8, 0.6), gold)
	for _, p in { shaft, leftHead, rightHead } do
		p.Parent = marker
		table.insert(markerParts, p)
	end
	ring = neon("Ring", Vector3.new(0.2, 8, 8), brand)
	ring.Shape = Enum.PartType.Cylinder

	highlight = Instance.new("Highlight")
	highlight.Name = "GuideHighlight"
	highlight.FillColor = gold
	highlight.OutlineColor = Style.Color("TextPrimary")
	highlight.FillTransparency = 0.7
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = folder
end

local function buildScreenArrow()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GuideEdge"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	edgeArrow = Instance.new("Frame")
	edgeArrow.Name = "EdgeArrow"
	edgeArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	edgeArrow.Size = UDim2.fromOffset(64, 64)
	edgeArrow.BackgroundTransparency = 1
	edgeArrow.Visible = false
	edgeArrow.Parent = gui
	-- Pastille ronde + chevron (la pastille reste droite, le chevron tourne)
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(52, 52)
	disc.BackgroundColor3 = Style.Color("BgDeep")
	disc.BackgroundTransparency = 0.25
	disc.Parent = edgeArrow
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = disc
	local stroke = Instance.new("UIStroke")
	stroke.Color = Style.Color("BrandAnga")
	stroke.Thickness = 2.5
	stroke.Parent = disc
	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.fromScale(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(52, 52)
	pointer.BackgroundTransparency = 1
	pointer.Parent = edgeArrow
	for _, side in { -1, 1 } do
		local arm = Instance.new("Frame")
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.Position = UDim2.new(0.5, side * 7, 0.5, 0)
		arm.Size = UDim2.fromOffset(5, 22)
		arm.Rotation = side * -40
		arm.BackgroundColor3 = Style.Color("CurrencyBits")
		arm.BorderSizePixel = 0
		arm.Parent = pointer
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = arm
	end
	edgeLabel = Instance.new("TextLabel")
	edgeLabel.AnchorPoint = Vector2.new(0.5, 0)
	edgeLabel.Position = UDim2.new(0.5, 0, 1, 2)
	edgeLabel.Size = UDim2.fromOffset(160, 18)
	edgeLabel.BackgroundTransparency = 1
	edgeLabel.FontFace = Style.Fonts.Heavy
	edgeLabel.TextSize = 14
	edgeLabel.TextColor3 = Style.Color("TextPrimary")
	edgeLabel.TextStrokeTransparency = 0.4
	edgeLabel.Parent = edgeArrow
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

------------------------------------------------------------------------------------
-- Animation
------------------------------------------------------------------------------------

local function hideAll()
	for _, chevron in chevrons do
		chevron.Left.Transparency = 1
		chevron.Right.Transparency = 1
	end
	for _, p in markerParts do
		p.Transparency = 1
	end
	ring.Transparency = 1
	highlight.Enabled = false
	edgeArrow.Visible = false
end

-- Place un chevron "V" pointant vers `forward` au point `center` (au sol).
local function placeChevron(chevron: { Left: Part, Right: Part }, center: Vector3, forward: Vector3, alpha: number)
	local right = forward:Cross(Vector3.yAxis).Unit
	local tip = center + forward * 0.7
	for _, side in { -1, 1 } do
		local tail = center - forward * 0.6 + right * 0.95 * side
		local mid = (tip + tail) / 2
		local part = if side < 0 then chevron.Left else chevron.Right
		part.Size = Vector3.new(0.35, 0.12, (tip - tail).Magnitude + 0.2)
		part.CFrame = CFrame.lookAt(mid, tip)
		part.Transparency = alpha
	end
end

local function update(target: Vector3, instance: Instance?, label: string)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		hideAll()
		return
	end
	local t = os.clock()
	local feetY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 + 0.15
	local from = Vector3.new(root.Position.X, feetY, root.Position.Z)
	local flatTarget = Vector3.new(target.X, feetY, target.Z)
	local toTarget = flatTarget - from
	local distance = toTarget.Magnitude

	-- 1. Chevrons au sol, qui défilent vers la cible
	if distance > ARRIVED_DISTANCE then
		local forward = toTarget.Unit
		local scroll = if Motion.IsReduced() then 0 else (t * 7) % SPACING
		for index, chevron in chevrons do
			local along = 2.5 + (index - 1) * SPACING + scroll
			if along < distance - 3 then
				-- Fondu aux deux extrémités du chemin
				local fade = math.min((along - 2.5) / 3, (distance - 3 - along) / 3, 1)
				placeChevron(chevron, from + forward * along, forward, 1 - math.clamp(fade, 0, 1) * 0.75)
			else
				chevron.Left.Transparency = 1
				chevron.Right.Transparency = 1
			end
		end
	else
		for _, chevron in chevrons do
			chevron.Left.Transparency = 1
			chevron.Right.Transparency = 1
		end
	end

	-- 2. Marqueur flottant au-dessus de la cible + anneau au sol
	local bob = if Motion.IsReduced() then 0 else math.sin(t * 3) * 0.8
	local top = target + Vector3.new(0, 9 + bob, 0)
	local spin = CFrame.Angles(0, t * 1.5, 0)
	markerParts[1].CFrame = CFrame.new(top + Vector3.new(0, 1.6, 0)) * spin
	-- Deux branches inclinées dont les pieds se rejoignent sous le centre : un "V" qui pointe vers la cible.
	markerParts[2].CFrame = CFrame.new(top) * spin * CFrame.new(-0.55, 0, 0) * CFrame.Angles(0, 0, math.rad(40))
	markerParts[3].CFrame = CFrame.new(top) * spin * CFrame.new(0.55, 0, 0) * CFrame.Angles(0, 0, math.rad(-40))
	for _, p in markerParts do
		p.Transparency = 0.1
	end
	local pulse = 1 + ((t * 0.8) % 1) * 0.6
	ring.Size = Vector3.new(0.2, 7 * pulse, 7 * pulse)
	ring.CFrame = CFrame.new(Vector3.new(target.X, feetY + 0.1, target.Z)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Transparency = 0.35 + ((t * 0.8) % 1) * 0.6

	-- Surbrillance de l'objet
	if instance then
		highlight.Adornee = instance
		highlight.Enabled = true
		highlight.FillTransparency = 0.6 + math.sin(t * 4) * 0.15
	else
		highlight.Enabled = false
	end

	-- 3. Flèche au bord de l'écran si la cible n'est pas visible
	local camera = Workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		local point, onScreen = camera:WorldToViewportPoint(target + Vector3.new(0, 4, 0))
		local inside = onScreen
			and point.X > 40
			and point.X < viewport.X - 40
			and point.Y > 40
			and point.Y < viewport.Y - 40
		if inside or distance <= ARRIVED_DISTANCE then
			edgeArrow.Visible = false
		else
			local center = viewport / 2
			local direction = Vector2.new(point.X, point.Y) - center
			if point.Z < 0 then
				direction = -direction -- derrière la caméra : on inverse
			end
			if direction.Magnitude < 1 then
				direction = Vector2.new(0, 1)
			end
			direction = direction.Unit
			local margin = 60
			local scaleX = (center.X - margin) / math.max(math.abs(direction.X), 0.001)
			local scaleY = (center.Y - margin) / math.max(math.abs(direction.Y), 0.001)
			local edge = center + direction * math.min(scaleX, scaleY)
			edgeArrow.Position = UDim2.fromOffset(edge.X, edge.Y)
			local pointer = edgeArrow:FindFirstChild("Pointer")
			if pointer and pointer:IsA("Frame") then
				-- Le chevron pointe "vers le haut" à 0° : on l'oriente dans la direction de la cible.
				pointer.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
			end
			edgeLabel.Text = if label ~= "" then `{label} · {math.floor(distance)} m` else `{math.floor(distance)} m`
			edgeArrow.Visible = true
		end
	end
end

function Guide.Start()
	buildWorld()
	buildScreenArrow()
	hideAll()

	local goal: Goal? = nil
	local target: Vector3? = nil
	local instance: Instance? = nil
	local label = ""

	-- Recalcul de la destination 4 fois par seconde, animation à chaque image.
	task.spawn(function()
		while true do
			goal = currentGoal()
			if goal then
				target, instance, label = resolve(goal)
			else
				target, instance, label = nil, nil, ""
			end
			task.wait(0.25)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if target then
			update(target, instance, label)
		else
			hideAll()
		end
	end)
end

return Guide
