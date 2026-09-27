--!nonstrict
-- Écran de chargement « KAIJU ALERT » (autonome : s'exécute avant tout le reste).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local INK = Color3.fromRGB(22, 16, 34)
local PAPER = Color3.fromRGB(255, 246, 222)
local GOLD = Color3.fromRGB(255, 200, 40)
local GREEN = Color3.fromRGB(124, 255, 79)
local MAGMA = Color3.fromRGB(255, 106, 31)
local TITLE = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
local IMPACT = Font.new("rbxasset://fonts/families/Bangers.json")
local BODY = Font.new("rbxasset://fonts/families/FredokaOne.json")

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = INK
bg.Parent = gui
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(60, 40, 90), INK)
grad.Rotation = 90
grad.Parent = bg

-- Rayons tournants
local rays = Instance.new("Frame")
rays.Size = UDim2.fromOffset(1600, 1600)
rays.Position = UDim2.fromScale(0.5, 0.42)
rays.AnchorPoint = Vector2.new(0.5, 0.5)
rays.BackgroundTransparency = 1
rays.Parent = bg
for i = 1, 16 do
	local r = Instance.new("Frame")
	r.Size = UDim2.new(0.06, 0, 1, 0)
	r.Position = UDim2.fromScale(0.5, 0.5)
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Rotation = i / 16 * 180
	r.BackgroundColor3 = MAGMA
	r.BackgroundTransparency = 0.85
	r.BorderSizePixel = 0
	r.Parent = rays
end
TweenService:Create(rays, TweenInfo.new(20, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()

local function text(props): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextScaled = true
	for k, v in props do
		if k ~= "StrokeThickness" then
			t[k] = v
		end
	end
	local s = Instance.new("UIStroke")
	s.Thickness = props.StrokeThickness or 6
	s.Color = INK
	s.Parent = t
	t.Parent = bg
	return t
end

local meteor = text({ Size = UDim2.fromOffset(120, 120), Position = UDim2.fromScale(0.2, -0.2), AnchorPoint = Vector2.new(0.5, 0.5), Text = "☄️", FontFace = BODY })
local title = text({ Size = UDim2.fromScale(0.8, 0.2), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), Text = "STEAL A KAIJU", FontFace = TITLE, TextColor3 = GREEN, Rotation = -4 })
local sub = text({ Size = UDim2.fromScale(0.5, 0.06), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Text = "GROW THEM. GUARD THEM. STEAL THEM.", FontFace = IMPACT, TextColor3 = GOLD, Rotation = 2, StrokeThickness = 3 })
local tip = text({ Size = UDim2.fromScale(0.6, 0.04), Position = UDim2.fromScale(0.5, 0.86), AnchorPoint = Vector2.new(0.5, 0.5), Text = "", FontFace = BODY, TextColor3 = PAPER, StrokeThickness = 2 })

local barBack = Instance.new("Frame")
barBack.Size = UDim2.fromScale(0.4, 0.03)
barBack.Position = UDim2.fromScale(0.5, 0.72)
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.BackgroundColor3 = Color3.fromRGB(50, 40, 70)
barBack.Parent = bg
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
local stroke = Instance.new("UIStroke")
stroke.Thickness = 4
stroke.Color = PAPER
stroke.Parent = barBack
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = GREEN
fill.Parent = barBack
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

local TIPS = {
	"Big kaijus earn more... but everyone can see them.",
	"Titans are too heavy to carry alone. Find a partner in crime!",
	"Bonk a thief to make them drop your kaiju!",
	"Lock your base before going on a heist.",
	"Fuse two Adult kaijus to discover SECRET kaijus.",
	"Blood Moons bring x4 mutations. Stay online!",
	"Legendary meteors glow gold. Run!",
}

local titleScale = Instance.new("UIScale")
titleScale.Scale = 0.2
titleScale.Parent = title
TweenService:Create(titleScale, TweenInfo.new(0.7, Enum.EasingStyle.Back), { Scale = 1 }):Play()
TweenService:Create(meteor, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, -1), { Position = UDim2.fromScale(0.85, 1.2) }):Play()
TweenService:Create(sub, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = -2 }):Play()

local done = false
task.spawn(function()
	local i = 1
	while not done do
		tip.Text = "💡 " .. TIPS[i]
		i = i % #TIPS + 1
		task.wait(2.6)
	end
end)

-- Progression : réplication + chargement des données du joueur
local start = os.clock()
local conn = RunService.RenderStepped:Connect(function()
	local target = math.clamp((os.clock() - start) / 5, 0, 0.9)
	if not game:IsLoaded() then
		target = math.min(target, 0.5)
	end
	fill.Size = UDim2.fromScale(fill.Size.X.Scale + (target - fill.Size.X.Scale) * 0.08, 1)
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
pcall(function()
	ContentProvider:PreloadAsync({ bg })
end)
-- Attend que le client principal ait reçu les données (attribut posé par Main.client)
local deadline = os.clock() + 25
while not player:GetAttribute("ClientReady") and os.clock() < deadline do
	task.wait(0.1)
end
done = true
conn:Disconnect()
TweenService:Create(fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(1, 1) }):Play()
task.wait(0.4)

-- Sortie : le titre claque puis tout glisse
TweenService:Create(titleScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 1.6 }):Play()
task.wait(0.2)
TweenService:Create(bg, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0, -1.1) }):Play()
task.wait(0.7)
gui:Destroy()
