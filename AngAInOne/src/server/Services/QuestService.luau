--!strict
--[[
	QuestService : quêtes quotidiennes/hebdomadaires + calendrier de récompenses quotidiennes.
	- Quêtes tirées au hasard parmi les modèles adaptés à la progression du joueur
	- Objectifs "Collect" calibrés sur la production actuelle au moment du tirage
	- Série quotidienne : un jour manqué fait reculer d'un jour (pas de retour à zéro)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local Formulas = require(Shared.Economy.Formulas)
local DataSchema = require(Shared.Data.DataSchema)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)
local StateService = require(script.Parent.StateService)
local NanobotService = require(script.Parent.NanobotService)

local QuestService = {}

local rng = Random.new()

local function pick(
	templates: { Quests.QuestTemplate },
	count: number,
	session: Session.Session
): { DataSchema.QuestState }
	local pool = {}
	for _, template in templates do
		if template.RequiredZone <= session.Data.Zone then
			table.insert(pool, template)
		end
	end
	local chosen: { DataSchema.QuestState } = {}
	while #chosen < count and #pool > 0 do
		local template = table.remove(pool, rng:NextInteger(1, #pool)) :: Quests.QuestTemplate
		local target = template.Target
		if template.Kind == "Collect" then
			target = math.max(math.floor(EconomyService.ProductionValue(session, template.Target)), 100)
		end
		table.insert(chosen, { Id = template.Id, Target = target, Progress = 0, Claimed = false })
	end
	return chosen
end

function QuestService.Ensure(session: Session.Session)
	local data = session.Data
	local now = os.time()
	local today = Formulas.DayIndex(now)
	local week = Formulas.WeekIndex(now)
	local changed = false
	if data.Quests.Day ~= today then
		data.Quests.Day = today
		data.Quests.Daily = pick(Quests.Daily, Quests.DailyCount, session)
		changed = true
	end
	if data.Quests.Week ~= week then
		data.Quests.Week = week
		data.Quests.Weekly = pick(Quests.Weekly, Quests.WeeklyCount, session)
		changed = true
	end
	if data.Likes.Day ~= today then
		data.Likes.Day = today
		data.Likes.GivenTo = {}
		changed = true
	end
	if changed then
		StateService.Push(session)
	end
end

function QuestService.Progress(session: Session.Session, kind: string, amount: number)
	local changed = false
	for _, list in { session.Data.Quests.Daily, session.Data.Quests.Weekly } do
		for _, quest in list do
			local template = Quests.ById[quest.Id]
			if template and template.Kind == kind and quest.Progress < quest.Target then
				quest.Progress = math.min(quest.Target, quest.Progress + amount)
				if quest.Progress >= quest.Target then
					EconomyService.Notify(session, "Quest", "Quête terminée ! Réclame ta récompense.")
				end
				changed = true
			end
		end
	end
	if changed then
		StateService.Push(session)
	end
end

function QuestService.Claim(session: Session.Session, questId: string)
	for _, list in { session.Data.Quests.Daily, session.Data.Quests.Weekly } do
		for _, quest in list do
			if quest.Id == questId and not quest.Claimed and quest.Progress >= quest.Target then
				local template = Quests.ById[quest.Id]
				if template then
					quest.Claimed = true
					EconomyService.AddChips(session, template.Chips, "Quest")
					EconomyService.Fx(session, "Reward", { Chips = template.Chips })
				end
				return
			end
		end
	end
end

function QuestService.ClaimDaily(session: Session.Session)
	local data = session.Data
	local today = Formulas.DayIndex(os.time())
	local last = data.Daily.LastClaimDay
	if last == today then
		return
	end
	if last == today - 1 then
		data.Daily.Streak += 1
	else
		-- Jour manqué : la série recule d'un jour au lieu de repartir à zéro.
		data.Daily.Streak = math.max(data.Daily.Streak - 1, 0) + 1
	end
	data.Daily.LastClaimDay = today
	local reward = Quests.DailyRewards[((data.Daily.Streak - 1) % #Quests.DailyRewards) + 1]
	if reward.Kind == "Chips" then
		EconomyService.AddChips(session, reward.Amount, "Daily")
	elseif reward.Kind == "Bits" then
		EconomyService.AddBits(session, EconomyService.ProductionValue(session, reward.Amount), "Daily")
	elseif reward.Kind == "Capsule" then
		local capsuleId = NanobotService.BestFreeCapsule(session)
		if capsuleId then
			NanobotService.OpenFree(session, capsuleId)
		else
			EconomyService.AddChips(session, 50, "Daily")
		end
	elseif reward.Kind == "Boost" then
		data.Boosts.BitsX2Until = math.max(data.Boosts.BitsX2Until, os.time()) + reward.Amount * 60
	elseif reward.Kind == "EpicNanobot" then
		if not NanobotService.GrantRandomOfRarity(session, "Epic") then
			EconomyService.AddChips(session, 150, "Daily")
		end
	end
	EconomyService.Fx(
		session,
		"Daily",
		{ Day = ((data.Daily.Streak - 1) % #Quests.DailyRewards) + 1, Label = reward.Label }
	)
	GameEvents.StateChanged:Fire(session.Player)
end

function QuestService.Start()
	RemoteGuard.On("ClaimQuest", { Args = { RemoteGuard.String(24) } }, QuestService.Claim)
	RemoteGuard.On("ClaimDaily", { Args = {} }, QuestService.ClaimDaily)

	Session.Added:Connect(function(session: Session.Session)
		-- Laisse EconomyService calculer la production avant de calibrer les objectifs.
		task.delay(4, function()
			if Session.Get(session.Player) == session then
				QuestService.Ensure(session)
			end
		end)
	end)

	local function withSession(player: Player, fn: (Session.Session) -> ())
		local session = Session.Get(player)
		if session then
			fn(session)
		end
	end

	GameEvents.BitsEarned:Connect(function(player: Player, amount: number, source: string)
		if source == "Collect" or source == "AutoCollect" then
			withSession(player, function(session)
				QuestService.Progress(session, "Collect", amount)
			end)
		end
	end)
	GameEvents.Upgraded:Connect(function(player: Player, count: number)
		withSession(player, function(session)
			QuestService.Progress(session, "Upgrade", count)
		end)
	end)
	GameEvents.VirusZapped:Connect(function(player: Player)
		withSession(player, function(session)
			QuestService.Progress(session, "Zap", 1)
		end)
	end)
	GameEvents.OverclockDone:Connect(function(player: Player, grade: string)
		if grade ~= "Miss" then
			withSession(player, function(session)
				QuestService.Progress(session, "Overclock", 1)
			end)
		end
	end)
	GameEvents.CapsuleOpened:Connect(function(player: Player, _capsuleId: string)
		withSession(player, function(session)
			QuestService.Progress(session, "Capsule", 1)
		end)
	end)
	GameEvents.TowerLiked:Connect(function(player: Player, _owner: number)
		withSession(player, function(session)
			QuestService.Progress(session, "Visit", 1)
		end)
	end)
	GameEvents.PlaytimeMinute:Connect(function(player: Player)
		withSession(player, function(session)
			QuestService.Ensure(session) -- passage de minuit UTC pendant la session
			QuestService.Progress(session, "Playtime", 1)
		end)
	end)
end

return QuestService
