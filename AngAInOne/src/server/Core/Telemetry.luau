--!strict
--[[
	Telemetry : fine couche au-dessus d'AnalyticsService.
	- Funnel d'onboarding (où les nouveaux joueurs décrochent)
	- Économie (sources / puits de Bits et de Chips)
	- Progression (zones, reboots, singularité)
	Toutes les erreurs sont absorbées : l'analytics ne doit jamais casser le gameplay.
]]

local AnalyticsService = game:GetService("AnalyticsService")

local Telemetry = {}

local function safe(fn: () -> ())
	xpcall(fn, function(err: any)
		warn("[Telemetry]", err)
	end)
end

function Telemetry.Onboarding(player: Player, step: number, stepName: string)
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

-- flow : "Source" (gagné) ou "Sink" (dépensé). currency : "Bits" | "Chips".
function Telemetry.Economy(
	player: Player,
	flow: "Source" | "Sink",
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	if amount <= 0 then
		return
	end
	safe(function()
		local flowType = if flow == "Source"
			then Enum.AnalyticsEconomyFlowType.Source
			else Enum.AnalyticsEconomyFlowType.Sink
		AnalyticsService:LogEconomyEvent(player, flowType, currency, amount, balance, transactionType, sku)
	end)
end

function Telemetry.Progression(player: Player, path: string, level: number, levelName: string)
	safe(function()
		AnalyticsService:LogProgressionCompleteEvent(player, path, level, levelName)
	end)
end

function Telemetry.Custom(player: Player, eventName: string, value: number?)
	safe(function()
		AnalyticsService:LogCustomEvent(player, eventName, value)
	end)
end

return table.freeze(Telemetry)
