--!strict
--[[
	DownloadService : "téléchargements" à durée fixe (30 min / 4 h / 8 h).
	Mécanique de rendez-vous : on lance, on revient plus tard récupérer une grosse récompense.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)

local DownloadService = {}

local byId: { [string]: GameConfig.DownloadKind } = {}
local ids: { string } = {}
for _, kind in GameConfig.Downloads do
	byId[kind.Id] = kind
	table.insert(ids, kind.Id)
end

function DownloadService.StartDownload(session: Session.Session, kindId: string)
	local data = session.Data
	local kind = byId[kindId]
	if not kind or data.Zone < GameConfig.DownloadRequiredZone or data.Download.Kind ~= "" then
		return
	end
	data.Download.Kind = kind.Id
	data.Download.StartedAt = os.time()
	EconomyService.Notify(session, "Info", `{kind.Name} lancé. Reviens dans un moment !`)
	GameEvents.StateChanged:Fire(session.Player)
end

function DownloadService.Claim(session: Session.Session)
	local data = session.Data
	local kind = byId[data.Download.Kind]
	if not kind or os.time() < data.Download.StartedAt + kind.Seconds then
		return
	end
	data.Download.Kind = ""
	data.Download.StartedAt = 0
	local bits = EconomyService.ProductionValue(session, kind.ProductionSeconds)
	EconomyService.AddBits(session, bits, "Download")
	EconomyService.AddChips(session, kind.Chips, "Download")
	EconomyService.Fx(session, "Reward", { Bits = bits, Chips = kind.Chips })
	GameEvents.StateChanged:Fire(session.Player)
end

function DownloadService.Start()
	RemoteGuard.On("StartDownload", { Args = { RemoteGuard.OneOf(ids) } }, DownloadService.StartDownload)
	RemoteGuard.On("ClaimDownload", { Args = {} }, DownloadService.Claim)
	MonetizationService.RegisterProduct("SkipDownload", function(session, _product)
		local data = session.Data
		local kind = byId[data.Download.Kind]
		if not kind then
			-- Rien en cours : on rend la valeur en Chips plutôt que de perdre l'achat.
			EconomyService.AddChips(session, 25, "SkipDownloadRefund")
			return true
		end
		data.Download.StartedAt = os.time() - kind.Seconds
		return true
	end)
end

return DownloadService
