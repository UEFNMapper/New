--!strict
-- Logique pure des quêtes quotidiennes et de la série de connexion.

local Config = script.Parent.Parent.Config
local Rewards = require(Config.Rewards)

local Progress = {}

local DAY = 86400

function Progress.DayNumber(t: number): number
	return t // DAY
end

-- Tire les quêtes du jour de façon déterministe (même joueur, même jour = mêmes quêtes).
function Progress.PickQuests(userId: number, day: number): { string }
	local rng = Random.new(userId * 7919 + day * 104729)
	local pool = table.clone(Rewards.Quests)
	local picked: { string } = {}
	local usedStats: { [string]: boolean } = {}
	while #picked < Rewards.QuestsPerDay and #pool > 0 do
		local i = rng:NextInteger(1, #pool)
		local q = table.remove(pool, i) :: any
		if not usedStats[q.Stat] then
			usedStats[q.Stat] = true
			table.insert(picked, q.Id)
		end
	end
	return picked
end

function Progress.QuestDef(id: string): Rewards.QuestDef?
	for _, q in Rewards.Quests do
		if q.Id == id then
			return q
		end
	end
	return nil
end

-- Série quotidienne : renvoie (peutRéclamer, prochaineSérie, prochainCycle)
function Progress.DailyState(daily: { Streak: number, LastDay: number, Cycle: number }, now: number): (boolean, number, number)
	local today = Progress.DayNumber(now)
	if daily.LastDay == today then
		return false, daily.Streak, daily.Cycle
	end
	local streak = daily.Streak
	local cycle = daily.Cycle
	if daily.LastDay == today - 1 then
		streak += 1
	else
		streak = 1
		cycle = 0
	end
	if streak > #Rewards.Daily then
		streak = 1
		cycle += 1
	end
	return true, streak, cycle
end

function Progress.DailyReward(streak: number, cycle: number): Rewards.Reward
	local r = table.clone(Rewards.Daily[math.clamp(streak, 1, #Rewards.Daily)])
	if r.Kind == "Egg" then
		r.Rarity = Rewards.DailyEggByCycle[math.min(cycle + 1, #Rewards.DailyEggByCycle)]
	end
	return r
end

return Progress
