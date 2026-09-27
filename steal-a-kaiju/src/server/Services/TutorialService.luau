--!nonstrict
-- Missions d'introduction validées côté serveur. Les autres services signalent
-- les événements via TutorialService.Notify ; certaines missions déclenchent
-- elles-mêmes leur contenu (vague d'entraînement, trésor du compagnon).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared.Config.Tutorial)
local Levels = require(Shared.Config.Levels)
local Layout = require(Shared.Config.Layout)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Notify)

local TutorialService = {}

-- Événement attendu pour valider la mission selon sa cible.
local EXPECTED = {
	Kaiju = "Hatch",
	Collector = "Collect",
	Meteor = "Meteor",
	Siege = "SiegeWave",
	RampagePortal = "Rampage",
	Treasure = "Dig",
}

local function step(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	return math.max(1, data.Tutorial)
end

function TutorialService.Step(player: Player): number
	return step(player)
end

function TutorialService.IsDone(player: Player): boolean
	return step(player) >= Tutorial.Done
end

-- Joueur en tutoriel ou qui vient de le finir (5 min de calme : pas d'événement mondial).
local doneAt: { [Player]: number } = {}
function TutorialService.InGracePeriod(player: Player): boolean
	if step(player) < Tutorial.Done then
		return DataService.Get(player) ~= nil
	end
	local t = doneAt[player]
	return t ~= nil and os.clock() - t < 300
end

local function firstHatched(player: Player): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	for _, rec in data.Kaijus do
		if not rec.Egg then
			return true
		end
	end
	return false
end

local advance: (player: Player) -> ()

-- Lance le contenu propre à une mission (après une courte pause pour lire la carte).
local function startStep(player: Player, s: number)
	local mission = Tutorial.Get(s)
	if not mission then
		return
	end
	if mission.Target == "Siege" then
		task.spawn(function()
			-- la vague d'entraînement ne commence que quand le joueur est rentré sur son île
			local deadline = os.clock() + 120
			while player.Parent == Players and step(player) == s and os.clock() < deadline do
				local plot = Registry.PlotService.Get(player)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if plot and root and Layout.InPlot(plot.CFrame, root.Position, 4) then
					break
				end
				task.wait(0.5)
			end
			task.wait(2)
			if player.Parent == Players and step(player) == s then
				local siege = Registry.SiegeService
				if siege.StartTutorialWave then
					siege.StartTutorialWave(player)
				else
					advance(player) -- défense d'île indisponible : on ne bloque pas le tutoriel
				end
			end
		end)
	elseif mission.Target == "Treasure" then
		task.delay(2, function()
			if player.Parent == Players and step(player) == s then
				Registry.BuddyService.ForceTreasure(player)
			end
		end)
	end
end

function advance(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local current = step(player)
	local mission = Tutorial.Get(current)
	if not mission then
		return
	end
	data.Tutorial = current + 1
	if mission.Reward.Cash then
		DataService.AddCash(player, mission.Reward.Cash, false)
	end
	if mission.Reward.Gems then
		DataService.AddGems(player, mission.Reward.Gems)
	end
	DataService.Replicate(player, "Tutorial")
	Notify.Fx(player, "MissionComplete", { Step = current, Reward = mission.Reward, Unlock = mission.UnlockMenus })
	Registry.LevelService.AddXp(player, Levels.Xp.Mission, "Mission")
	if data.Tutorial >= Tutorial.Done then
		doneAt[player] = os.clock()
		Notify.Fx(player, "TutorialDone", {})
	else
		startStep(player, data.Tutorial)
	end
end

-- event : Hatch | Collect | Meteor | SiegeWave | Rampage | Dig
function TutorialService.Notify(player: Player, event: string)
	local s = step(player)
	if s >= Tutorial.Done then
		return
	end
	local mission = Tutorial.Get(s)
	if mission and EXPECTED[mission.Target or ""] == event then
		advance(player)
	end
end

function TutorialService.Init()
	Players.PlayerRemoving:Connect(function(player)
		doneAt[player] = nil
	end)
	DataService.Loaded:Connect(function(player, data)
		task.delay(3, function()
			if player.Parent ~= Players then
				return
			end
			if data.Tutorial <= 0 then
				data.Tutorial = 1
			end
			-- rattrapage : déjà un kaiju éclos ?
			if step(player) == 1 and firstHatched(player) then
				advance(player)
			end
			DataService.Replicate(player, "Tutorial")
			startStep(player, step(player))
		end)
	end)
end

return TutorialService
