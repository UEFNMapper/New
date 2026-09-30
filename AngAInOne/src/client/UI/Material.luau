--!strict
--[[
	Material : les "matériaux dynamiques" de l'UI, dans le thème du PC.

	- RGB Edge   : bordure (UIStroke + UIGradient) dont le dégradé RGB tourne lentement,
	               et qui vire à l'ambre puis au rouge quand le PC surchauffe.
	- Glass Sheen: reflet de lumière qui balaie le verre fumé des panneaux.
	- Brushed    : métal brossé (dégradé strié) pour les en-têtes et les keycaps.
	- Data Pulse : petite impulsion lumineuse qui parcourt une piste de circuit.

	Un seul animateur (30 Hz) pour tout, qui ignore les éléments invisibles.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)
local Motion = require(script.Parent.Motion)

local Material = {}

local edges: { [UIGradient]: number } = {} -- gradient -> vitesse (degrés/s)
local sheens: { [UIGradient]: number } = {} -- gradient -> phase
local pulses: { [Frame]: { Phase: number, Speed: number, Vertical: boolean } } = {}
local stress = 0 -- 0 = PC au frais ; 1 = surchauffe
local stressTarget = 0

local function sequence(hexes: { string }): ColorSequence
	local keypoints = {}
	for index, hex in hexes do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#hexes - 1), Color3.fromHex(hex)))
	end
	return ColorSequence.new(keypoints)
end

local RGB = sequence(Theme.RgbCycle)
local HOT = sequence({ "F6AD55", "FC8181", "F0565B", "F6AD55", "FC8181" })

-- Mélange deux ColorSequence de même structure.
local function lerpSequence(a: ColorSequence, b: ColorSequence, t: number): ColorSequence
	local out = {}
	for index, keypoint in a.Keypoints do
		local other = b.Keypoints[index] or keypoint
		table.insert(out, ColorSequenceKeypoint.new(keypoint.Time, keypoint.Value:Lerp(other.Value, t)))
	end
	return ColorSequence.new(out)
end

-- Niveau de "stress" thermique (0..1), transmis par le HUD à partir de l'efficacité thermique.
function Material.SetThermalStress(value: number)
	stressTarget = math.clamp(value, 0, 1)
end

-- Ajoute une bordure RGB dynamique à un GuiObject.
function Material.RgbEdge(object: GuiObject, thickness: number?, transparency: number?, speed: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 1.5
	stroke.Transparency = transparency or 0.15
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Color = RGB
	gradient.Parent = stroke
	stroke.Parent = object
	edges[gradient] = speed or 40
	gradient.Destroying:Connect(function()
		edges[gradient] = nil
	end)
	return stroke
end

-- Verre fumé : dégradé vertical + reflet qui balaie la surface.
function Material.Glass(object: GuiObject, withSheen: boolean?)
	local depth = Instance.new("UIGradient")
	depth.Rotation = 90
	depth.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 175, 195))
	depth.Parent = object

	if withSheen ~= false then
		local sheen = Instance.new("Frame")
		sheen.Name = "Sheen"
		sheen.Size = UDim2.fromScale(1, 1)
		sheen.BackgroundColor3 = Color3.new(1, 1, 1)
		sheen.BackgroundTransparency = 0
		sheen.BorderSizePixel = 0
		sheen.ZIndex = object.ZIndex + 1
		local corner = object:FindFirstChildOfClass("UICorner")
		if corner then
			corner:Clone().Parent = sheen
		end
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 25
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.93),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Offset = Vector2.new(-1, 0)
		gradient.Parent = sheen
		sheen.Parent = object
		sheens[gradient] = math.random() * 10
		gradient.Destroying:Connect(function()
			sheens[gradient] = nil
		end)
	end
end

-- Métal brossé : fines stries horizontales (dégradé à nombreuses clés).
function Material.Brushed(object: GuiObject)
	local keypoints = {}
	local rng = Random.new(7)
	for i = 0, 18 do
		local shade = 0.82 + rng:NextNumber() * 0.18
		table.insert(keypoints, ColorSequenceKeypoint.new(i / 18, Color3.new(shade, shade, shade * 1.03)))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(keypoints)
	gradient.Parent = object
end

-- Piste de circuit décorative avec impulsion lumineuse.
function Material.Trace(parent: GuiObject, position: UDim2, size: UDim2, vertical: boolean, accent: Color3): Frame
	local line = Instance.new("Frame")
	line.Name = "Trace"
	line.Position = position
	line.Size = size
	line.BackgroundColor3 = accent
	line.BackgroundTransparency = 0.82
	line.BorderSizePixel = 0
	line.ZIndex = parent.ZIndex + 1
	line.Parent = parent
	local dot = Instance.new("Frame")
	dot.Name = "Pulse"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = if vertical then UDim2.new(1, 2, 0, 10) else UDim2.new(0, 10, 1, 2)
	dot.BackgroundColor3 = accent
	dot.BackgroundTransparency = 0.2
	dot.BorderSizePixel = 0
	dot.ZIndex = line.ZIndex + 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	dot.Parent = line
	pulses[dot] = { Phase = math.random(), Speed = 0.25 + math.random() * 0.2, Vertical = vertical }
	dot.Destroying:Connect(function()
		pulses[dot] = nil
	end)
	return line
end

-- Vis de boîtier aux 4 coins d'un panneau.
function Material.Screws(object: GuiObject, inset: number)
	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local screw = Instance.new("Frame")
		screw.Name = "Screw"
		screw.AnchorPoint = corner
		screw.Position = UDim2.new(corner.X, (corner.X * -2 + 1) * inset, corner.Y, (corner.Y * -2 + 1) * inset)
		screw.Size = UDim2.fromOffset(7, 7)
		screw.BackgroundColor3 = Color3.fromHex(Theme.Colors.MetalLight)
		screw.BorderSizePixel = 0
		screw.ZIndex = object.ZIndex + 2
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = screw
		local slot = Instance.new("Frame")
		slot.AnchorPoint = Vector2.new(0.5, 0.5)
		slot.Position = UDim2.fromScale(0.5, 0.5)
		slot.Size = UDim2.new(0.7, 0, 0, 1)
		slot.Rotation = 45
		slot.BackgroundColor3 = Color3.fromHex(Theme.Colors.BgDeep)
		slot.BorderSizePixel = 0
		slot.ZIndex = screw.ZIndex + 1
		slot.Parent = screw
		screw.Parent = object
	end
end

local function visible(instance: Instance): boolean
	local current: Instance? = instance
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("LayerCollector") then
			return current.Enabled
		end
		current = current.Parent
	end
	return false
end

local accumulator = 0
RunService.RenderStepped:Connect(function(dt: number)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	local step = accumulator
	accumulator = 0
	stress += (stressTarget - stress) * math.min(step * 2, 1)
	local motion = if Motion.IsReduced() then 0.15 else 1
	local edgeColor = if stress > 0.02 then lerpSequence(RGB, HOT, stress) else RGB
	for gradient, speed in edges do
		if visible(gradient) then
			gradient.Rotation = (gradient.Rotation + speed * step * motion * (1 + stress * 2)) % 360
			gradient.Color = edgeColor
		end
	end
	for gradient, phase in sheens do
		if visible(gradient) then
			-- Un passage de reflet toutes les ~7 s.
			local t = ((os.clock() + phase) % 7) / 7
			gradient.Offset = Vector2.new(-1 + t * 3.2, 0)
		end
	end
	for dot, info in pulses do
		if visible(dot) then
			info.Phase = (info.Phase + step * info.Speed * motion) % 1
			dot.Position = if info.Vertical then UDim2.fromScale(0.5, info.Phase) else UDim2.fromScale(info.Phase, 0.5)
		end
	end
end)

return Material
