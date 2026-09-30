--!strict
--[[
	VirusService : des glitches apparaissent près de chaque joueur, dans la zone où il est.
	On les zappe avec un prompt (F / bouton manette / tap) : Bits + chance de Chips.
	Chaque virus appartient à un joueur (attribut OwnerUserId) : le client cache ceux des
	autres. Le serveur vérifie que c'est bien le propriétaire qui zappe
	(la distance est garantie par MaxActivationDistance du prompt, revérifiée ici).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Theme = require(Shared.Config.Theme)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local Build = require(script.Parent.Parent.World.Build)
local EconomyService = require(script.Parent.EconomyService)
local WorldService = require(script.Parent.WorldService)

local VirusService = {}

local rng = Random.new()
local nextSpawn: { [Session.Session]: number } = {}
local alive: { [Session.Session]: number } = {}

local function zap(session: Session.Session, virus: BasePart)
	if not virus.Parent then
		return
	end
	if RemoteGuard.DistanceTo(session.Player, virus.Position) > GameConfig.Virus.ZapDistance + 4 then
		return
	end
	local position = virus.Position
	virus:Destroy()
	alive[session] = math.max((alive[session] or 1) - 1, 0)
	local cfg = GameConfig.Virus
	local bits = EconomyService.ProductionValue(session, cfg.RewardProductionSeconds)
	EconomyService.AddBits(session, bits, "Virus")
	local chips = 0
	if rng:NextNumber() < cfg.ChipChance then
		chips = cfg.ChipReward
		EconomyService.AddChips(session, chips, "Virus")
	end
	session.Data.Stats.VirusesZapped += 1
	EconomyService.Fx(session, "Zap", { Position = position, Bits = bits, Chips = chips })
	GameEvents.VirusZapped:Fire(session.Player)
	EconomyService.Refresh(session)
end

local function spawnVirus(session: Session.Session)
	local world = Workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("Viruses")
	if not folder or (alive[session] or 0) >= GameConfig.Virus.MaxAlive then
		return
	end
	local spot = WorldService.RandomPointNear(session, rng)
	if not spot then
		return
	end
	local virus = Build.Part({
		Name = "Virus",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = spot,
		Color = Color3.fromHex(Theme.Colors.Danger),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
		Tags = { "Virus" },
	})
	virus:SetAttribute("OwnerUserId", session.UserId)
	virus.Parent = folder
	alive[session] = (alive[session] or 0) + 1
	local prompt = Build.Prompt(virus, "Zapper", "Virus", "Zap", GameConfig.Virus.ZapDistance)
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Triggered:Connect(function(player: Player)
		if player == session.Player then
			zap(session, virus)
		end
	end)
	task.delay(GameConfig.Virus.LifeSeconds, function()
		if virus.Parent then
			virus:Destroy()
			alive[session] = math.max((alive[session] or 1) - 1, 0)
		end
	end)
end

function VirusService.Start()
	Session.Removing:Connect(function(session: Session.Session)
		nextSpawn[session] = nil
		alive[session] = nil
		local world = Workspace:FindFirstChild("World")
		local folder = world and world:FindFirstChild("Viruses")
		if folder then
			for _, virus in folder:GetChildren() do
				if virus:GetAttribute("OwnerUserId") == session.UserId then
					virus:Destroy()
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			local now = os.clock()
			for _, session in Session.All() do
				-- Pas de virus avant la fin des premières étapes du tutoriel.
				if session.Data.PoweredOn and session.Data.Tutorial >= 4 then
					local due = nextSpawn[session]
					if not due then
						nextSpawn[session] = now + rng:NextNumber(20, 40)
					elseif now >= due then
						nextSpawn[session] = now
							+ rng:NextNumber(GameConfig.Virus.MinInterval, GameConfig.Virus.MaxInterval)
						spawnVirus(session)
					end
				end
			end
		end
	end)
end

return VirusService
