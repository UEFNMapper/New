--!nonstrict
-- Guide : chevrons lumineux au sol du joueur vers une cible + gros marqueur
-- rebondissant au-dessus de la cible. Utilisé par le tutoriel et pendant un vol.
--   local g = Guide.new(color) ; g:Point(targetPositionOrPart) ; g:Hide()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local ScreenScale = require(script.Parent.Parent.Controllers.ScreenScale)

local Guide = {}
Guide.__index = Guide

local CHEVRONS = 7
local player = Players.LocalPlayer

local function chevron(color: Color3, parent: Instance): Model
	local model = Instance.new("Model")
	for _, side in { -1, 1 } do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.new(0.6, 0.3, 2.4)
		p:SetAttribute("Side", side)
		p.Parent = model
	end
	model.Parent = parent
	return model
end

function Guide.new(color: Color3?)
	local folder = Instance.new("Folder")
	folder.Name = "Guide"
	folder.Parent = Workspace
	local self = setmetatable({
		Folder = folder,
		Color = color or Theme.Colors.Radioactive,
		Target = nil :: any,
		Chevrons = {},
		Marker = nil :: BillboardGui?,
		MarkerPart = nil :: BasePart?,
		Conn = nil :: RBXScriptConnection?,
	}, Guide)
	for i = 1, CHEVRONS do
		self.Chevrons[i] = chevron(self.Color, folder)
	end
	local markerPart = Instance.new("Part")
	markerPart.Anchored = true
	markerPart.CanCollide = false
	markerPart.CanQuery = false
	markerPart.CanTouch = false
	markerPart.Transparency = 1
	markerPart.Size = Vector3.new(1, 1, 1)
	markerPart.Parent = folder
	local marker = Instance.new("BillboardGui")
	marker.Size = ScreenScale.Px(90, 90)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Parent = markerPart
	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.Text = "⬇️"
	arrow.TextScaled = true
	arrow.Parent = marker
	self.Marker = marker
	self.MarkerPart = markerPart
	self:Hide()
	return self
end

local function targetPosition(target: any): Vector3?
	if typeof(target) == "Vector3" then
		return target
	elseif typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			return target.Position
		elseif target:IsA("Model") then
			return target:GetPivot().Position
		end
	end
	return nil
end

function Guide:Point(target: any)
	self.Target = target
	self.Folder.Parent = Workspace
	if self.Conn then
		return
	end
	self.Conn = RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local goal = targetPosition(self.Target)
		if not root or not goal then
			for _, c in self.Chevrons do
				for _, p in c:GetChildren() do
					p.Transparency = 1
				end
			end
			return
		end
		local t = os.clock()
		local from = Vector3.new(root.Position.X, root.Position.Y - 2.6, root.Position.Z)
		local to = Vector3.new(goal.X, from.Y, goal.Z)
		local delta = to - from
		local dist = delta.Magnitude
		local dir = if dist > 0.1 then delta.Unit else Vector3.new(0, 0, -1)
		local span = math.min(dist - 3, 40)
		for i, c in self.Chevrons do
			local a = ((i - 1) / CHEVRONS + t * 0.6) % 1
			local pos = from + dir * (3 + a * math.max(span, 0))
			local fade = math.sin(a * math.pi)
			local base = CFrame.lookAt(pos, pos + dir)
			for _, p in c:GetChildren() do
				local side = p:GetAttribute("Side")
				p.CFrame = base * CFrame.new(side * 0.7, 0, 0) * CFrame.Angles(0, math.rad(40 * side), 0)
				p.Transparency = if dist < 6 then 1 else 1 - fade * 0.85
			end
		end
		self.MarkerPart.CFrame = CFrame.new(goal + Vector3.new(0, 9 + math.sin(t * 5) * 1.2, 0))
	end)
end

function Guide:Hide()
	self.Target = nil
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
	self.Folder.Parent = nil
end

return Guide
