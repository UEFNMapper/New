--!strict
--[[
	ChillIdle : easter egg du monde 4 (Cryo Tower). Rester immobile deux minutes dans le froid gèle le
	personnage : bloc de glace (local), toast « 0 °C : idle = température minimale ». Bouger dégèle.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)
local Audio = require(script.Parent.Audio)

local ChillIdle = {}

ChillIdle.IDLE_SECONDS = 120
ChillIdle.WORLD = 4

local player = Players.LocalPlayer

local function freeze(root: BasePart)
	local ice = Instance.new("Part")
	ice.Name = "IdleIce"
	ice.Size = Vector3.new(5, 7.5, 5)
	ice.CFrame = CFrame.new(root.Position + Vector3.new(0, 0.5, 0))
	ice.Color = Color3.fromRGB(205, 232, 255)
	ice.Material = Enum.Material.Ice
	ice.Transparency = 0.35
	ice.Anchored = true
	ice.CanCollide = false
	ice.CanQuery = false
	ice.CanTouch = false
	ice.Parent = Workspace
	Audio.Play("Whoosh", 0.6)
	Toasts.Show("Boost", "0 °C : idle = température minimale. Bouge, tu gèles !")
	task.delay(4, function()
		ice:Destroy()
	end)
end

function ChillIdle.Start()
	task.spawn(function()
		local still = 0
		while true do
			task.wait(1)
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			local stage = player:GetAttribute("Stage")
			local inCryo = type(stage) == "number" and stage > 0 and Tower.WorldOf(stage) == ChillIdle.WORLD
			if root and root:IsA("BasePart") and inCryo and root.AssemblyLinearVelocity.Magnitude < 0.5 then
				still += 1
			else
				still = 0
			end
			if still == ChillIdle.IDLE_SECONDS and root and root:IsA("BasePart") then
				freeze(root)
				still = 0
			end
		end
	end)
end

return ChillIdle
