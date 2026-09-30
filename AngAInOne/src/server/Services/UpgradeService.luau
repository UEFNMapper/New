--!strict
--[[
	UpgradeService : tout ce qui fait grandir le PC.
	- PowerOn : premier allumage (moment "waouh" du tutoriel)
	- Upgrade : niveaux de modules (x1, x10, max)
	- UpgradeCapacity : bloc d'alimentation (Watts) et radiateurs (refroidissement)
	- UnlockZone : étage suivant
	- BuySingularityPhase : les 5 phases de la fin du jeu dans l'AI Core
	Toutes les requêtes exigent d'être dans sa propre tour, PC allumé, et de pouvoir payer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Zones = require(Shared.Config.Zones)
local Modules = require(Shared.Config.Modules)
local Formulas = require(Shared.Economy.Formulas)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local NumberFormat = require(Shared.Util.NumberFormat)

local UpgradeService = {}

local function canAct(session: Session.Session): boolean
	if not session.Data.PoweredOn then
		return false
	end
	if not PlotService.IsInOwnTower(session) then
		EconomyService.Notify(session, "Error", "Retourne dans ta tour pour faire ça.")
		return false
	end
	return true
end

local function crossedMilestone(before: number, after: number): boolean
	for _, milestone in GameConfig.Milestones do
		if before < milestone and after >= milestone then
			return true
		end
	end
	return false
end

function UpgradeService.PowerOn(session: Session.Session)
	local data = session.Data
	if data.PoweredOn then
		return
	end
	data.PoweredOn = true
	data.Levels.Z1M1 = math.max(data.Levels.Z1M1 or 0, 1)
	EconomyService.Fx(session, "PowerOn", {})
	GameEvents.PoweredOn:Fire(session.Player)
	GameEvents.StateChanged:Fire(session.Player)
end

function UpgradeService.Upgrade(session: Session.Session, moduleId: string, amount: number)
	local def = Modules.Get(moduleId)
	local data = session.Data
	if not def or def.Zone > data.Zone or not canAct(session) then
		return
	end
	local level = data.Levels[moduleId] or 0
	local remaining = GameConfig.MaxModuleLevel - level
	if remaining <= 0 then
		return
	end
	local count
	if amount == -1 then
		count = Formulas.MaxAffordable(def.BaseCost, level, data.Bits, GameConfig.LevelGrowth, remaining)
	else
		count = math.min(amount, remaining)
	end
	if count <= 0 then
		EconomyService.Notify(session, "Error", "Pas assez de Bits.")
		return
	end
	local cost = Formulas.BulkCost(def.BaseCost, level, count, GameConfig.LevelGrowth)
	if not EconomyService.SpendBits(session, cost, moduleId) then
		EconomyService.Notify(session, "Error", "Pas assez de Bits.")
		return
	end
	local newLevel = level + count
	data.Levels[moduleId] = newLevel
	data.Stats.Upgrades += count
	EconomyService.Fx(session, "Upgrade", { ModuleId = moduleId, Level = newLevel, Count = count })
	if crossedMilestone(level, newLevel) then
		EconomyService.Notify(session, "Milestone", `{def.Name} : palier atteint, production x2 !`)
	end
	GameEvents.Upgraded:Fire(session.Player, count)
	GameEvents.StateChanged:Fire(session.Player)
end

function UpgradeService.UpgradeCapacity(session: Session.Session, kind: string, amount: number)
	local data = session.Data
	if not canAct(session) then
		return
	end
	local params = if kind == "Power" then GameConfig.Power else GameConfig.Cooling
	if kind == "Cooling" and data.Zone < GameConfig.Cooling.UnlockZone then
		return
	end
	local level = if kind == "Power" then data.PsuLevel else data.CoolingLevel
	-- Calcule d'abord combien de niveaux sont payables, puis débite en une seule fois.
	local wanted = if amount == -1 then params.MaxLevel else math.clamp(amount, 1, 10)
	local bought, total = 0, 0
	while bought < wanted and level + bought < params.MaxLevel do
		local cost = Formulas.CapacityUpgradeCost(params, level + bought)
		if total + cost > data.Bits then
			break
		end
		total += cost
		bought += 1
	end
	if bought == 0 or not EconomyService.SpendBits(session, total, kind) then
		EconomyService.Notify(session, "Error", "Pas assez de Bits.")
		return
	end
	level += bought
	if kind == "Power" then
		data.PsuLevel = level
	else
		data.CoolingLevel = level
	end
	data.Stats.Upgrades += bought
	EconomyService.Fx(session, "Capacity", { Kind = kind, Level = level })
	GameEvents.Upgraded:Fire(session.Player, bought)
	GameEvents.StateChanged:Fire(session.Player)
end

function UpgradeService.UnlockZone(session: Session.Session, zoneIndex: number)
	local data = session.Data
	local zone = Zones[zoneIndex]
	if not zone or zoneIndex ~= data.Zone + 1 or not canAct(session) then
		return
	end
	if not EconomyService.SpendBits(session, zone.UnlockCost, `Zone_{zone.Id}`) then
		EconomyService.Notify(session, "Error", `Il te faut {NumberFormat.Compact(zone.UnlockCost)} Bits.`)
		return
	end
	data.Zone = zoneIndex
	local firstModule = `Z{zoneIndex}M1`
	data.Levels[firstModule] = math.max(data.Levels[firstModule] or 0, 1)
	EconomyService.Fx(session, "ZoneUnlocked", { Zone = zoneIndex })
	Telemetry.Progression(session.Player, "Zones", zoneIndex, zone.Id)
	GameEvents.ZoneUnlocked:Fire(session.Player, zoneIndex)
	GameEvents.StateChanged:Fire(session.Player)
end

function UpgradeService.BuySingularityPhase(session: Session.Session)
	local data = session.Data
	local phases = GameConfig.SingularityPhases
	if data.Zone < #Zones or data.SingularityPhase >= #phases or not canAct(session) then
		return
	end
	local cost = phases[data.SingularityPhase + 1]
	if not EconomyService.SpendBits(session, cost, "Singularity") then
		EconomyService.Notify(session, "Error", `Il te faut {NumberFormat.Compact(cost)} Bits.`)
		return
	end
	data.SingularityPhase += 1
	if data.SingularityPhase >= #phases then
		data.Singularities += 1
		EconomyService.Fx(session, "Singularity", { Count = data.Singularities })
		Telemetry.Progression(session.Player, "Singularity", data.Singularities, "Singularity")
	else
		EconomyService.Fx(session, "SingularityPhase", { Phase = data.SingularityPhase })
	end
	GameEvents.StateChanged:Fire(session.Player)
end

function UpgradeService.Start()
	RemoteGuard.On("PowerOn", { Args = {} }, UpgradeService.PowerOn)
	RemoteGuard.On("Upgrade", {
		Limit = "Upgrade",
		Args = { RemoteGuard.String(8), RemoteGuard.Int(-1, 10) },
	}, function(session: Session.Session, moduleId: string, amount: number)
		if amount == 0 then
			return
		end
		UpgradeService.Upgrade(session, moduleId, amount)
	end)
	RemoteGuard.On("UpgradeCapacity", {
		Limit = "Upgrade",
		Args = { RemoteGuard.OneOf({ "Power", "Cooling" }), RemoteGuard.Int(-1, 10) },
	}, function(session: Session.Session, kind: string, amount: number)
		if amount == 0 then
			return
		end
		UpgradeService.UpgradeCapacity(session, kind, amount)
	end)
	RemoteGuard.On("UnlockZone", { Args = { RemoteGuard.Int(2, #Zones) } }, UpgradeService.UnlockZone)
	RemoteGuard.On("BuySingularityPhase", { Args = {} }, UpgradeService.BuySingularityPhase)
end

return UpgradeService
