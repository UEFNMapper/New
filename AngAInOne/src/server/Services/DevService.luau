--!strict
--[[
	DevService : commandes de test, actives UNIQUEMENT dans Roblox Studio.
	- Bits    : ajoute des Bits
	- Stage   : va directement à une étape (nettoie les mondes précédents)
	- Clear   : réussit le terminal antivirus du monde actuel
	- Shield  : bouclier de 30 s
	- Reset   : remet la sauvegarde à zéro
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local DataSchema = require(Shared.Data.DataSchema)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local ProgressService = require(script.Parent.ProgressService)
local ShopService = require(script.Parent.ShopService)

local DevService = {}

local COMMANDS = { "Bits", "Stage", "Clear", "Shield", "Reset" }

function DevService.Start()
	RemoteGuard.On("DevCommand", {
		Args = { RemoteGuard.OneOf(COMMANDS), RemoteGuard.Number(-1, 1e12) },
	}, function(session: Session.Session, command: string, value: number)
		if not RunService:IsStudio() then
			return -- jamais en ligne
		end
		local data = session.Data
		if command == "Bits" then
			Wallet.Add(session, value, "Dev", false)
		elseif command == "Stage" then
			local stage = math.clamp(math.floor(value), 0, Tower.TOTAL_STAGES)
			data.Stage = stage
			data.BestStage = math.max(data.BestStage, stage)
			data.RunStarted = true
			data.Cleared = math.max(data.Cleared, Tower.WorldOf(stage) - 1)
			session.Player:SetAttribute("Stage", stage)
			session.Player:SetAttribute("Cleared", data.Cleared)
			ProgressService.ToCheckpoint(session)
		elseif command == "Clear" then
			ProgressService.ClearWorld(session, data.Cleared + 1)
		elseif command == "Shield" then
			ShopService.GrantShield(session, 30)
		elseif command == "Reset" then
			local fresh = DataSchema.Template()
			for key in data :: any do
				(data :: any)[key] = nil
			end
			for key, fieldValue in fresh :: any do
				(data :: any)[key] = fieldValue
			end
			data.CreatedAt = os.time()
			ProgressService.ToLobby(session)
		end
		Wallet.Notify(session, "Info", `[DEV] {command} {value}`)
		GameEvents.StateChanged:Fire(session.Player)
	end)
end

return DevService
