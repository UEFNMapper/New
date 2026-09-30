--!strict
--[[
	DevService : commandes de test, actives UNIQUEMENT dans Roblox Studio.
	En ligne (serveurs publics), RunService:IsStudio() est faux : toute requête est ignorée.
	Permet de tester toute la progression en quelques minutes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local DataSchema = require(Shared.Data.DataSchema)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)

local DevService = {}

local COMMANDS = { "Bits", "Chips", "Zone", "Virus", "Reset", "Tutorial" }

function DevService.Start()
	RemoteGuard.On("DevCommand", {
		Args = { RemoteGuard.OneOf(COMMANDS), RemoteGuard.Number(-1, 1e30) },
	}, function(session: Session.Session, command: string, value: number)
		if not RunService:IsStudio() then
			return -- jamais en ligne
		end
		local data = session.Data
		if command == "Bits" then
			EconomyService.AddBits(session, value, "Dev")
		elseif command == "Chips" then
			EconomyService.AddChips(session, value, "Dev")
		elseif command == "Zone" then
			data.PoweredOn = true
			data.Zone = math.clamp(math.floor(value), 1, #Zones)
			for zone = 1, data.Zone do
				data.Levels[`Z{zone}M1`] = math.max(data.Levels[`Z{zone}M1`] or 0, 1)
			end
		elseif command == "Tutorial" then
			data.Tutorial = math.clamp(math.floor(value), 0, 8)
		elseif command == "Virus" then
			-- Force l'apparition rapide d'un virus (le VirusService s'en charge au prochain passage).
			data.Tutorial = math.max(data.Tutorial, 4)
		elseif command == "Reset" then
			local fresh = DataSchema.Template()
			for key in data :: any do
				(data :: any)[key] = nil
			end
			for key, fieldValue in fresh :: any do
				(data :: any)[key] = fieldValue
			end
			data.CreatedAt = os.time()
		end
		EconomyService.Notify(session, "Info", `[DEV] {command} {value}`)
		GameEvents.StateChanged:Fire(session.Player)
	end)
end

return DevService
