--!strict
--[[
	ZoneTracker : sait à quel étage (ou dans le hub) se trouve le joueur.
	- Musique de la zone (fondu enchaîné)
	- Teinte de l'éclairage (ColorCorrection) et de l'atmosphère, en douceur
	- Petite annonce du nom de l'étage à l'entrée
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local GameConfig = require(Shared.Config.GameConfig)
local WorldLayout = require(Shared.Config.WorldLayout)

local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local WorldFx = require(script.Parent.WorldFx)
local Motion = require(script.Parent.Parent.UI.Motion)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)

local ZoneTracker = {}

-- Zone de détection autour d'une tour (dimensions partagées avec la construction de la map).
local HALF_WIDTH = WorldLayout.TOWER_WIDTH / 2 + 6
local HALF_DEPTH = WorldLayout.TOWER_DEPTH / 2 + 6

local current: number = -1 -- -1 inconnu, 0 hub, sinon étage
local HUB_TINT = Color3.fromRGB(245, 245, 255)
local HUB_ATMOSPHERE = Color3.fromRGB(40, 35, 70)

-- Étage (1..7) si le point est dans une tour, 0 sinon. Renvoie aussi l'index de la tour.
function ZoneTracker.Locate(position: Vector3): (number, number)
	for index = 1, GameConfig.MaxPlots do
		local localPos = WorldLayout.TowerCFrame(index):PointToObjectSpace(position)
		if math.abs(localPos.X) <= HALF_WIDTH and math.abs(localPos.Z) <= HALF_DEPTH and localPos.Y > -6 then
			return WorldLayout.FloorAt(localPos.Y, #Zones), index
		end
	end
	return 0, 0
end

local function apply(floor: number)
	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if floor == 0 then
		Audio.PlayZone("Hub")
		if correction then
			Motion.Tween(correction, { TintColor = HUB_TINT }, 1.2, Enum.EasingStyle.Sine)
		end
		if atmosphere then
			Motion.Tween(atmosphere, { Color = HUB_ATMOSPHERE }, 1.5, Enum.EasingStyle.Sine)
		end
		return
	end
	local zone = Zones[floor]
	Audio.PlayZone(floor)
	if correction then
		Motion.Tween(correction, { TintColor = Color3.fromHex(zone.Tint) }, 1.2, Enum.EasingStyle.Sine)
	end
	if atmosphere then
		Motion.Tween(
			atmosphere,
			{ Color = HUB_ATMOSPHERE:Lerp(Color3.fromHex(zone.Primary), 0.25) },
			1.5,
			Enum.EasingStyle.Sine
		)
	end
end

function ZoneTracker.Start()
	task.spawn(function()
		while true do
			task.wait(0.3)
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local floor, towerIndex = ZoneTracker.Locate(root.Position)
				local state = Store.State
				local ownTower = state ~= nil and towerIndex == state.Plot
				WorldFx.CurrentFloor = if ownTower then floor else 0
				if floor ~= current then
					local previous = current
					current = floor
					apply(floor)
					if previous >= 0 and floor > 0 and ownTower then
						Toasts.Show("Info", `Étage {floor} · {Zones[floor].Name}`)
					end
				end
			end
		end
	end)
end

return ZoneTracker
