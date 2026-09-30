--!strict
--[[
	RebootService : le prestige. Réinitialise le run (Bits, niveaux, zones) contre du
	Firmware (multiplicateur permanent) et fait passer à la Génération suivante.
	On garde : Chips, Nanobots, Firmware, fragments, statistiques, cosmétiques.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Economy.Formulas)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local MonetizationService = require(script.Parent.MonetizationService)

local RebootService = {}

function RebootService.Preview(session: Session.Session): number
	local gain = Formulas.FirmwareGain(session.Data.RunBitsEarned, GameConfig.Reboot.FirmwareDivisor)
	if session.Data.RebootBoostPending then
		gain = math.floor(gain * 1.5)
	end
	return gain
end

function RebootService.Reboot(session: Session.Session)
	local data = session.Data
	if data.Zone < GameConfig.Reboot.RequiredZone then
		return
	end
	local gain = RebootService.Preview(session)
	if gain < GameConfig.Reboot.MinFirmwareGain then
		EconomyService.Notify(session, "Error", "Produis encore un peu avant de rebooter.")
		return
	end
	data.Firmware += gain
	data.Generation += 1
	data.Bits = 0
	data.Pending = 0
	data.Levels = { Z1M1 = 1 }
	data.Zone = 1
	data.PsuLevel = 0
	data.CoolingLevel = 0
	data.RunBitsEarned = 0
	data.SingularityPhase = 0
	data.RebootBoostPending = false
	data.Stats.Reboots += 1
	session.OverclockUntil = 0
	session.OverclockMult = 1
	session.OverclockCooldownUntil = 0
	EconomyService.Fx(session, "Reboot", { Firmware = gain, Generation = data.Generation })
	Telemetry.Progression(session.Player, "Generation", data.Generation, `Gen{data.Generation}`)
	GameEvents.Rebooted:Fire(session.Player, gain)
	GameEvents.StateChanged:Fire(session.Player)
	task.delay(2.5, function()
		if Session.Get(session.Player) == session then
			PlotService.TeleportToFloor(session, 1)
		end
	end)
end

function RebootService.Start()
	RemoteGuard.On("Reboot", { Args = {} }, RebootService.Reboot)
	MonetizationService.RegisterProduct("RebootBoost", function(session, _product)
		session.Data.RebootBoostPending = true
		return true
	end)
end

return RebootService
