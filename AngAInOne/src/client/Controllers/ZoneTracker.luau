--!strict
--[[
	ZoneTracker : sait dans quelle zone du PC géant (ou dans le hub) se trouve le joueur.
	- Musique de la zone (fondu enchaîné)
	- Teinte de l'éclairage (ColorCorrection) et de l'atmosphère, en douceur
	- Petite annonce du nom de la zone (et de sa section de l'app AngAInOne) à l'entrée
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Config.WorldLayout)

local Audio = require(script.Parent.Audio)
local WorldFx = require(script.Parent.WorldFx)
local Motion = require(script.Parent.Parent.UI.Motion)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)

local ZoneTracker = {}

local current: number = -2 -- -2 inconnu, -1 hors carte, 0 hub, sinon zone
local HUB_TINT = Color3.fromRGB(250, 250, 255)
local HUB_ATMOSPHERE = Color3.fromRGB(199, 209, 235)

-- Zone contenant la position : 0 = hub, 1..7 = zone, -1 = hors de la carte mère.
function ZoneTracker.Locate(position: Vector3): number
	return WorldLayout.ZoneAt(position)
end

local function apply(zoneIndex: number)
	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if zoneIndex <= 0 then
		Audio.PlayZone("Hub")
		if correction then
			Motion.Tween(correction, { TintColor = HUB_TINT }, 1.2, Enum.EasingStyle.Sine)
		end
		if atmosphere then
			Motion.Tween(atmosphere, { Color = HUB_ATMOSPHERE }, 1.5, Enum.EasingStyle.Sine)
		end
		return
	end
	local zone = Zones[zoneIndex]
	Audio.PlayZone(zoneIndex)
	if correction then
		Motion.Tween(correction, { TintColor = Color3.fromHex(zone.Tint) }, 1.2, Enum.EasingStyle.Sine)
	end
	if atmosphere then
		Motion.Tween(
			atmosphere,
			{ Color = HUB_ATMOSPHERE:Lerp(Color3.fromHex(zone.Primary), 0.2) },
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
				local zoneIndex = ZoneTracker.Locate(root.Position)
				WorldFx.CurrentZone = math.max(zoneIndex, 0)
				if zoneIndex ~= current then
					local previous = current
					current = zoneIndex
					apply(zoneIndex)
					if previous >= -1 and zoneIndex > 0 then
						local zone = Zones[zoneIndex]
						Toasts.Show("Info", `{zone.Name} · {zone.AppSection}`)
					end
				end
			end
		end
	end)
end

return ZoneTracker
