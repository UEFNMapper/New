--!strict
--[[
	VirusService : des glitches apparaissent dans la tour de chaque joueur.
	On les zappe avec un prompt (E / bouton manette / tap) : Bits + chance de Chips.
	Le serveur crée le virus, vérifie que c'est bien le propriétaire qui zappe
	(la distance est garantie par MaxActivationDistance du prompt, revérifiée ici).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Theme = require(Shared.Config.Theme)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local Build = require(script.Parent.Parent.World.Build)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)

local VirusService = {}

local rng = Random.new()
local nextSpawn: { [Session.Session]: number } = {}

local function aliveCount(folder: Instance): number
	return #folder:GetChildren()
end

local function zap(session: Session.Session, virus: BasePart)
	if not virus.Parent then
		return
	end
	if RemoteGuard.DistanceTo(session.Player, virus.Position) > GameConfig.Virus.ZapDistance + 4 then
		return
	end
	local position = virus.Position
	virus:Destroy()
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
	local tower = PlotService.GetTower(session)
	local folder = tower and tower:FindFirstChild("Viruses")
	if not tower or not folder or aliveCount(folder) >= GameConfig.Virus.MaxAlive then
		return
	end
	-- 70 % de chances d'apparaître à l'étage où se trouve le joueur (sinon un étage débloqué au hasard).
	local floor = PlotService.CurrentFloor(session)
	if floor == 0 or rng:NextNumber() > 0.7 then
		floor = rng:NextInteger(1, session.Data.Zone)
	end
	local virus = Build.Part({
		Name = "Virus",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = PlotService.RandomFloorPoint(session.Plot, floor, rng),
		Color = Color3.fromHex(Theme.Colors.Danger),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
		Tags = { "Virus" },
		Parent = folder,
	})
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
		end
	end)
end

function VirusService.Start()
	Session.Removing:Connect(function(session: Session.Session)
		nextSpawn[session] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			local now = os.clock()
			for _, session in Session.All() do
				-- Pas de virus avant la fin des premières étapes du tutoriel.
				if session.Data.PoweredOn and session.Data.Tutorial >= 4 and session.Plot > 0 then
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
