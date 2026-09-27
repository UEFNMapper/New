--!nonstrict
-- Aperçu 3D d'un kaiju (ou d'un œuf) dans l'interface, avec rotation lente.
--   local vp = Viewport.new({ Species = "Toastzilla", Mutation = nil, Parent = frame })
--   vp:Set("Rexplosion", "Gold") ; vp:SetSilhouette(true) ; vp:Destroy()

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local KaijuBuilder = require(Shared.KaijuBuilder)
local Theme = require(Shared.Config.Theme)

local Viewport = {}
Viewport.__index = Viewport

local active: { [any]: boolean } = {}

function Viewport.new(props: { [string]: any })
	local frame = Instance.new("ViewportFrame")
	frame.Name = props.Name or "Viewport"
	frame.Size = props.Size or UDim2.fromScale(1, 1)
	frame.Position = props.Position or UDim2.new()
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.BackgroundTransparency = 1
	frame.Ambient = Color3.fromRGB(170, 160, 190)
	frame.LightColor = Color3.fromRGB(255, 250, 240)
	frame.LightDirection = Vector3.new(-0.6, -1, -0.5)
	frame.ZIndex = props.ZIndex or 5
	frame.LayoutOrder = props.LayoutOrder or 0
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = frame
	frame.CurrentCamera = camera
	local world = Instance.new("WorldModel")
	world.Parent = frame
	frame.Parent = props.Parent

	local self = setmetatable({
		Frame = frame,
		Camera = camera,
		World = world,
		Model = nil :: Model?,
		Angle = props.Angle or 0.6,
		Spin = props.Spin ~= false,
		Speed = props.Speed or 0.6,
		Distance = 1,
		Center = Vector3.zero,
		Silhouette = false,
	}, Viewport)
	if props.Egg then
		self:SetEgg(props.Egg)
	elseif props.Species then
		self:Set(props.Species, props.Mutation)
	end
	if props.Silhouette then
		self:SetSilhouette(true)
	end
	active[self] = true
	return self
end

function Viewport:_frame(model: Model)
	local cf, size = model:GetBoundingBox()
	self.Center = cf.Position
	local radius = size.Magnitude / 2
	self.Distance = radius / math.tan(math.rad(self.Camera.FieldOfView / 2)) * 1.05
	self:_update()
end

function Viewport:_update()
	local dir = Vector3.new(math.sin(self.Angle), 0.35, -math.cos(self.Angle)).Unit
	self.Camera.CFrame = CFrame.lookAt(self.Center + dir * self.Distance, self.Center)
end

function Viewport:_replace(model: Model)
	if self.Model then
		self.Model:Destroy()
	end
	self.Model = model
	model.Parent = self.World
	self:_frame(model)
	if self.Silhouette then
		self:SetSilhouette(true)
	end
end

function Viewport:Set(species: string, mutation: string?)
	self:_replace(KaijuBuilder.Build(species, mutation, 1))
end

function Viewport:SetEgg(rarity: string)
	self:_replace(KaijuBuilder.BuildEgg(rarity, 1))
end

-- Silhouette noire (kaiju pas encore découvert).
function Viewport:SetSilhouette(on: boolean)
	self.Silhouette = on
	if on then
		self.Frame.ImageColor3 = Theme.Colors.Ink
		self.Frame.Ambient = Color3.new(0, 0, 0)
		self.Frame.LightColor = Color3.new(0, 0, 0)
	else
		self.Frame.ImageColor3 = Color3.new(1, 1, 1)
		self.Frame.Ambient = Color3.fromRGB(170, 160, 190)
		self.Frame.LightColor = Color3.fromRGB(255, 250, 240)
	end
end

function Viewport:Destroy()
	active[self] = nil
	self.Frame:Destroy()
end

RunService.RenderStepped:Connect(function(dt)
	for vp in active do
		local frame = vp.Frame
		if not frame.Parent then
			active[vp] = nil
		elseif vp.Spin and frame.Visible then
			vp.Angle += dt * vp.Speed
			vp:_update()
		end
	end
end)

return Viewport
