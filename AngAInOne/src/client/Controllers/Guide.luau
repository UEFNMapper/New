--!strict
--[[
	Guide : onboarding "dans le monde". Un faisceau lumineux relie le joueur à sa
	prochaine cible (collecteur, première machine, terminal…) et la cible brille
	(Highlight). Aucun mur de texte : Anga donne une phrase courte dans le HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)

local Store = require(script.Parent.Store)
local Style = require(script.Parent.Parent.UI.Style)

local Guide = {}

local beam: Beam
local playerAttachment: Attachment?
local targetAttachment: Attachment
local highlight: Highlight
local anchor: Part

local function towerFloor(floor: number): Instance?
	local state = Store.State
	if not state or state.Plot == 0 then
		return nil
	end
	local world = Workspace:FindFirstChild("World")
	local towers = world and world:FindFirstChild("Towers")
	local tower = towers and towers:FindFirstChild(`Tower{state.Plot}`)
	local floors = tower and tower:FindFirstChild("Floors")
	return floors and floors:FindFirstChild(`Floor{floor}`)
end

-- Cible du tutoriel selon l'étape (nil = pas de guide).
local function currentTarget(): Instance?
	local state = Store.State
	if not state then
		return nil
	end
	local data = state.Data
	local step = data.Tutorial
	if not data.PoweredOn or step >= 8 then
		return nil
	end
	if step == 2 then
		local floor = towerFloor(1)
		return floor and floor:FindFirstChild("Collector")
	elseif step == 3 or step == 4 then
		local floor = towerFloor(1)
		local modules = floor and floor:FindFirstChild("Modules")
		return modules and modules:FindFirstChild("Z1M1")
	elseif step == 5 then
		if data.Bits >= Zones[2].UnlockCost then
			local floor = towerFloor(1)
			return floor and floor:FindFirstChild("UnlockTerminal")
		end
		local floor = towerFloor(1)
		return floor and floor:FindFirstChild("Collector")
	elseif step == 6 then
		local floor = towerFloor(2)
		return floor and floor:FindFirstChild("CapsuleTerminal")
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

local function ensurePlayerAttachment(): Attachment?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local existing = root:FindFirstChild("GuideAttachment")
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "GuideAttachment"
	attachment.Position = Vector3.new(0, -2, 0)
	attachment.Parent = root
	return attachment
end

function Guide.Start()
	anchor = Instance.new("Part")
	anchor.Name = "GuideAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = Workspace
	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = anchor

	beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(Style.Color("BrandAnga"), Style.Color("CurrencyBits"))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	beam.Width0 = 0.6
	beam.Width1 = 1.2
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 20
	beam.CurveSize0 = 4
	beam.CurveSize1 = -4
	beam.Enabled = false
	beam.Parent = anchor

	highlight = Instance.new("Highlight")
	highlight.Name = "GuideHighlight"
	highlight.FillColor = Style.Color("CurrencyBits")
	highlight.OutlineColor = Style.Color("TextPrimary")
	highlight.FillTransparency = 0.7
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = Workspace

	task.spawn(function()
		while true do
			task.wait(0.25)
			local target = currentTarget()
			local position = if target then positionOf(target) else nil
			if target and position then
				playerAttachment = ensurePlayerAttachment()
				beam.Attachment0 = playerAttachment
				anchor.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
				beam.Enabled = playerAttachment ~= nil
				highlight.Adornee = target
				highlight.Enabled = true
				highlight.FillTransparency = 0.55 + math.sin(os.clock() * 4) * 0.2
			else
				beam.Enabled = false
				highlight.Enabled = false
			end
		end
	end)
end

return Guide
