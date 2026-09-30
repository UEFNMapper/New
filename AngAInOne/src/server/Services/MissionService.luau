--!strict
--[[
	MissionService : calendrier de connexion (7 jours) et 3 missions du jour.
	- Calendrier : un jour manqué fait reculer la série d'un jour (jamais de retour à zéro brutal)
	- Missions : tirées au hasard chaque jour UTC (graine = jour + joueur), compteurs alimentés
	  par les événements de jeu (GameEvents)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Missions = require(Shared.Config.Missions)
local Time = require(Shared.Util.Time)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local ShopService = require(script.Parent.ShopService)

local MissionService = {}

-- Tire les missions du jour si elles datent d'un autre jour.
local function ensureMissions(session: Session.Session)
	local data = session.Data
	local today = Time.DayIndex(os.time())
	if data.Missions.Day == today then
		return
	end
	local rng = Random.new(today * 7919 + session.UserId % 100003)
	local pool = table.clone(Missions.Templates)
	local list = {}
	for _ = 1, math.min(Missions.PerDay, #pool) do
		local template = table.remove(pool, rng:NextInteger(1, #pool)) :: Missions.MissionTemplate
		table.insert(list, {
			Id = template.Id,
			Target = template.Targets[rng:NextInteger(1, #template.Targets)],
			Progress = 0,
			Claimed = false,
		})
	end
	data.Missions = { Day = today, List = list }
end

local function progress(player: Player, kind: Missions.MissionKind, amount: number)
	local session = Session.Get(player)
	if not session then
		return
	end
	ensureMissions(session)
	local changed = false
	for _, mission in session.Data.Missions.List do
		local template = Missions.ById[mission.Id]
		if template and template.Kind == kind and mission.Progress < mission.Target then
			mission.Progress = math.min(mission.Progress + amount, mission.Target)
			changed = true
			if mission.Progress >= mission.Target then
				Wallet.Fx(session, "MissionReady", { Id = mission.Id })
			end
		end
	end
	if changed then
		GameEvents.StateChanged:Fire(player)
	end
end

local function onClaimDaily(session: Session.Session)
	local data = session.Data
	local today = Time.DayIndex(os.time())
	if data.Daily.LastClaimDay == today then
		return
	end
	local missed = if data.Daily.LastClaimDay < 0 then 0 else today - data.Daily.LastClaimDay - 1
	local streak = math.max(data.Daily.Streak - missed, 0) + 1
	data.Daily.Streak = streak
	data.Daily.LastClaimDay = today
	local reward = GameConfig.DailyRewards[(streak - 1) % #GameConfig.DailyRewards + 1]
	Wallet.Add(session, reward.Bits, "Daily", false)
	if reward.Cosmetic then
		ShopService.Grant(session, reward.Cosmetic)
	end
	Wallet.Fx(session, "Daily", { Day = reward.Day, Label = reward.Label })
	GameEvents.StateChanged:Fire(session.Player)
end

local function onClaimMission(session: Session.Session, id: string)
	-- Pas de renouvellement ici : une mission finie hier peut encore être récupérée.
	for _, mission in session.Data.Missions.List do
		if mission.Id == id and not mission.Claimed and mission.Progress >= mission.Target then
			mission.Claimed = true
			local template = Missions.ById[id]
			local bits = Wallet.Add(session, if template then template.Bits else 50, "Mission", false)
			Wallet.Fx(session, "Reward", { Bits = bits })
			GameEvents.StateChanged:Fire(session.Player)
			return
		end
	end
end

function MissionService.Start()
	Session.Added:Connect(function(session: Session.Session)
		ensureMissions(session)
	end)
	GameEvents.CheckpointReached:Connect(function(player: Player, _stage: number)
		progress(player, "Checkpoints", 1)
	end)
	GameEvents.CoinCollected:Connect(function(player: Player)
		progress(player, "Coins", 1)
	end)
	GameEvents.WorldCleared:Connect(function(player: Player, _world: number)
		progress(player, "Minigames", 1)
		progress(player, "Worlds", 1)
	end)
	GameEvents.Victory:Connect(function(player: Player, _time: number)
		progress(player, "Wins", 1)
	end)
	GameEvents.ArcadeWon:Connect(function(player: Player)
		progress(player, "Arcade", 1)
	end)
	RemoteGuard.On("ClaimDaily", { Args = {} }, onClaimDaily)
	RemoteGuard.On("ClaimMission", { Args = { RemoteGuard.String(24) } }, onClaimMission)
end

return MissionService
