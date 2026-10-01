--!strict
--[[
	DevService : commandes de test, actives UNIQUEMENT dans Roblox Studio.
	- Bits    : ajoute des Bits
	- Stage   : va directement à une étape (nettoie les mondes précédents)
	- Clear   : réussit le terminal antivirus du monde actuel
	- Shield  : bouclier de 30 s
	- Reset   : remet la sauvegarde à zéro
	- Feature : va tester une nouveauté (Config/DevFeatures, index) : monde encore infecté,
	  checkpoint, puis position exacte
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local DevFeatures = require(Shared.Config.DevFeatures)
local DataSchema = require(Shared.Data.DataSchema)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local ProgressService = require(script.Parent.ProgressService)
local ShopService = require(script.Parent.ShopService)

local DevService = {}

local COMMANDS = { "Bits", "Stage", "Clear", "Shield", "Reset", "Feature" }

-- Place le joueur dans le monde de la nouveauté, monde encore infecté, puis à sa position.
local function goToFeature(session: Session.Session, index: number)
	local feature = DevFeatures.List[math.floor(index)]
	if not feature or not feature.World then
		return
	end
	local stage = feature.Stage or Tower.TerminalStage(feature.World)
	local data = session.Data
	data.Stage = stage
	data.BestStage = math.max(data.BestStage, stage)
	data.RunStarted = true
	data.Cleared = feature.World - 1
	session.Player:SetAttribute("Stage", data.Stage)
	session.Player:SetAttribute("Cleared", data.Cleared)
	ProgressService.ToCheckpoint(session)
	local at = feature.At
	if feature.Epreuve then
		-- Devant la borne de la salle (u 12, v -31 dans le repère de l'épreuve)
		local tower = Workspace:FindFirstChild("Tower")
		local model = if tower then tower:FindFirstChild(`World{feature.World}`) else nil
		local folder = if model then model:FindFirstChild("Epreuve", true) else nil
		local origin = if folder then folder:GetAttribute("Origin") else nil
		local axisF = if folder then folder:GetAttribute("AxisF") else nil
		local axisR = if folder then folder:GetAttribute("AxisR") else nil
		if typeof(origin) == "Vector3" and typeof(axisF) == "Vector3" and typeof(axisR) == "Vector3" then
			at = origin + axisF * 12 + axisR * -30 + Vector3.new(0, 3.5, 0)
		end
	end
	if at then
		task.delay(0.8, function()
			local player = session.Player
			pcall(function()
				player:RequestStreamAroundAsync(at, 5)
			end)
			local character = player.Character
			if character and character.Parent then
				character:PivotTo(CFrame.new(at))
			end
		end)
	end
end

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
		elseif command == "Feature" then
			goToFeature(session, value)
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
