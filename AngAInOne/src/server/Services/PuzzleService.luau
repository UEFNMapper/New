--!strict
--[[
	PuzzleService : processus en fond du monde 5 (World/Tower/Mechanics) : « Fin de tâche ».
	- Uninstall(world, index) : à portée du processus ; UNINSTALL_BITS la première fois
	  (PlayerData.Puzzles["W5U{i}"]). Le blocage, lui, est retiré côté client à chaque ascension.
	Rôle Enquêteur (Config/Roles) : récompense × 2.
	(Les enquêtes des mondes 1 et 7 sont devenues des épreuves : Config/Epreuves.)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Roles = require(Shared.Config.Roles)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)

local PuzzleService = {}

PuzzleService.PANEL_DISTANCE = 16
PuzzleService.UNINSTALL_BITS = 3
PuzzleService.BLOATWARE_WORLD = 5

local blocks: { [number]: BasePart } = {}

local function track(tag: string, add: (BasePart) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") then
			add(instance)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			add(instance)
		end
	end)
end

local function reward(session: Session.Session, base: number, source: string): number
	local amount = math.floor(base * Roles.InvestigateFactor(session.Data.Role) + 0.5)
	return Wallet.Add(session, amount, source, true)
end

function PuzzleService.Uninstall(session: Session.Session, world: number, index: number)
	if world ~= PuzzleService.BLOATWARE_WORLD or not session.Alive then
		return
	end
	local block = blocks[index]
	if not block or RemoteGuard.DistanceTo(session.Player, block.Position) > PuzzleService.PANEL_DISTANCE then
		return
	end
	local data = session.Data
	local key = `W{world}U{index}`
	if data.Puzzles[key] then
		return
	end
	data.Puzzles[key] = true
	local bits = reward(session, PuzzleService.UNINSTALL_BITS, "Uninstall")
	Wallet.Fx(session, "Uninstalled", { Index = index, Bits = bits })
	GameEvents.StateChanged:Fire(session.Player)
end

function PuzzleService.Start()
	track("Bloatware", function(part: BasePart)
		local index = part:GetAttribute("Index")
		if type(index) == "number" then
			blocks[index] = part
		end
	end)
	RemoteGuard.On("Uninstall", {
		Args = { RemoteGuard.Int(1, 7), RemoteGuard.Int(1, 8) },
	}, PuzzleService.Uninstall)
end

return PuzzleService
