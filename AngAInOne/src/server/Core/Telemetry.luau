--!strict
--[[
	Telemetry : fine couche au-dessus d'AnalyticsService.
	- Funnel d'onboarding (où les nouveaux joueurs décrochent)
	- Économie (sources / puits de Bits et de Chips)
	- Progression (zones, reboots, singularité)
	Toutes les erreurs sont absorbées : l'analytics ne doit jamais casser le gameplay.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

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

-- Économie : les événements sont AGRÉGÉS par joueur et par type pendant 60 s puis envoyés
-- en un seul appel (la production automatique ferait sinon un événement par seconde et
-- saturerait le budget AnalyticsService, étouffant les événements importants).
type Bucket = {
	Player: Player,
	Flow: string,
	Currency: string,
	Amount: number,
	Balance: number,
	Transaction: string,
	Sku: string?,
}
local buckets: { [string]: Bucket } = {}
local FLUSH_SECONDS = 60

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
	if amount <= 0 or amount ~= amount then
		return
	end
	local key = `{player.UserId}|{flow}|{currency}|{transactionType}|{sku or ""}`
	local bucket = buckets[key]
	if bucket then
		bucket.Amount += amount
		bucket.Balance = balance
	else
		buckets[key] = {
			Player = player,
			Flow = flow,
			Currency = currency,
			Amount = amount,
			Balance = balance,
			Transaction = transactionType,
			Sku = sku,
		}
	end
end

local function flush()
	local pending = buckets
	buckets = {}
	for _, bucket in pending do
		if bucket.Player.Parent then
			safe(function()
				local flowType = if bucket.Flow == "Source"
					then Enum.AnalyticsEconomyFlowType.Source
					else Enum.AnalyticsEconomyFlowType.Sink
				AnalyticsService:LogEconomyEvent(
					bucket.Player,
					flowType,
					bucket.Currency,
					bucket.Amount,
					bucket.Balance,
					bucket.Transaction,
					bucket.Sku
				)
			end)
		end
	end
end

task.spawn(function()
	while true do
		task.wait(FLUSH_SECONDS)
		flush()
	end
end)

-- Envoie les événements en attente d'un joueur qui part (sinon ils seraient perdus).
Players.PlayerRemoving:Connect(function(player: Player)
	local prefix = `{player.UserId}|`
	local mine: { [string]: Bucket } = {}
	for key, bucket in buckets do
		if string.sub(key, 1, #prefix) == prefix then
			mine[key] = bucket
			buckets[key] = nil
		end
	end
	for _, bucket in mine do
		safe(function()
			AnalyticsService:LogEconomyEvent(
				player,
				if bucket.Flow == "Source"
					then Enum.AnalyticsEconomyFlowType.Source
					else Enum.AnalyticsEconomyFlowType.Sink,
				bucket.Currency,
				bucket.Amount,
				bucket.Balance,
				bucket.Transaction,
				bucket.Sku
			)
		end)
	end
end)

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
