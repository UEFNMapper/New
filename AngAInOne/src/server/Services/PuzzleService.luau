--!strict
--[[
	PuzzleService : enquêtes des salles du terminal (mondes 1 et 7, Config/Puzzles) et bloatware du
	monde 5 (World/Tower/Mechanics). Le client montre tout ; le serveur ne fait que vérifier et payer.
	- PuzzleAnswer(world, item) : le joueur est vivant, à moins de PANEL_DISTANCE studs du panneau ; une
	  mauvaise réponse ne coûte rien (l'assistant donne un indice) mais impose WRONG_COOLDOWN s avant la
	  suivante ; la bonne rapporte puzzle.Bits une fois pour toujours (PlayerData.Puzzles["W{n}"]).
	- Uninstall(world, index) : à portée du bloatware ; UNINSTALL_BITS la première fois
	  (PlayerData.Puzzles["W5U{i}"]). Le blocage, lui, est retiré côté client à chaque ascension.
	Rôle Enquêteur (Config/Roles) : récompenses × 2.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Puzzles = require(Shared.Config.Puzzles)
local Roles = require(Shared.Config.Roles)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)

local PuzzleService = {}

PuzzleService.PANEL_DISTANCE = 16
PuzzleService.WRONG_COOLDOWN = 2.5
PuzzleService.UNINSTALL_BITS = 3
PuzzleService.BLOATWARE_WORLD = 5

local panels: { [string]: BasePart } = {}
local blocks: { [number]: BasePart } = {}
local lastWrong: { [Session.Session]: number } = {}

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

function PuzzleService.Answer(session: Session.Session, world: number, item: string)
	local puzzle = Puzzles.ForWorld(world)
	if not puzzle or not session.Alive then
		return
	end
	local panel = panels[`{world}:{item}`]
	if not panel or RemoteGuard.DistanceTo(session.Player, panel.Position) > PuzzleService.PANEL_DISTANCE then
		return
	end
	local data = session.Data
	local key = `W{world}`
	if data.Puzzles[key] then
		Wallet.Fx(session, "Puzzle", { World = world, Item = item, Ok = true, Already = true, Bits = 0 })
		return
	end
	local now = os.clock()
	local wrongAt = lastWrong[session]
	if wrongAt and now - wrongAt < PuzzleService.WRONG_COOLDOWN then
		return
	end
	local ok = Puzzles.Check(world, item)
	if not ok then
		lastWrong[session] = now
		Wallet.Fx(session, "Puzzle", { World = world, Item = item, Ok = false })
		return
	end
	data.Puzzles[key] = true
	local bits = reward(session, puzzle.Bits, "Puzzle")
	Wallet.Fx(session, "Puzzle", { World = world, Item = item, Ok = true, Bits = bits })
	GameEvents.StateChanged:Fire(session.Player)
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
	track("PuzzlePanel", function(part: BasePart)
		local world, item = part:GetAttribute("World"), part:GetAttribute("Item")
		if type(world) == "number" and type(item) == "string" then
			panels[`{world}:{item}`] = part
		end
	end)
	track("Bloatware", function(part: BasePart)
		local index = part:GetAttribute("Index")
		if type(index) == "number" then
			blocks[index] = part
		end
	end)
	RemoteGuard.On("PuzzleAnswer", {
		Args = { RemoteGuard.Int(1, 7), RemoteGuard.String(24) },
	}, PuzzleService.Answer)
	RemoteGuard.On("Uninstall", {
		Args = { RemoteGuard.Int(1, 7), RemoteGuard.Int(1, 8) },
	}, PuzzleService.Uninstall)
	Session.Removing:Connect(function(session: Session.Session)
		lastWrong[session] = nil
	end)
end

return PuzzleService
