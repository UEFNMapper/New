--!strict
--[[
	OnboardingService : suit la progression du tutoriel à partir des VRAIS événements
	de jeu (jamais sur simple déclaration du client) et alimente le funnel d'onboarding
	d'AnalyticsService pour savoir où les nouveaux joueurs décrochent.

	Étapes (GameConfig.TutorialSteps) :
	1 Spawn · 2 PowerOn · 3 FirstCollect · 4 FirstUpgrade · 5 SecondUpgrade
	6 UnlockRam · 7 FirstCapsule · 8 Done
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local StateService = require(script.Parent.StateService)

local OnboardingService = {}

local STEP = {
	Spawn = 1,
	PowerOn = 2,
	FirstCollect = 3,
	FirstUpgrade = 4,
	SecondUpgrade = 5,
	UnlockRam = 6,
	FirstCapsule = 7,
	Done = 8,
}

-- Avance au pas `step` seulement si c'est le suivant (les étapes sont séquentielles).
local function advance(session: Session.Session, step: number)
	local data = session.Data
	if data.Tutorial >= step then
		return
	end
	-- Rattrape les étapes intermédiaires éventuellement sautées (ex. Auto-Collect).
	for s = data.Tutorial + 1, step do
		if not session.FunnelDone[s] then
			session.FunnelDone[s] = true
			Telemetry.Onboarding(session.Player, s, GameConfig.TutorialSteps[s])
		end
	end
	data.Tutorial = step
	StateService.Push(session)
end

local function on(player: Player, fn: (Session.Session) -> ())
	local session = Session.Get(player)
	if session and session.Data.Tutorial < STEP.Done then
		fn(session)
	end
end

function OnboardingService.Start()
	Session.Added:Connect(function(session: Session.Session)
		if session.Data.Tutorial < STEP.Spawn then
			advance(session, STEP.Spawn)
		end
	end)
	GameEvents.PoweredOn:Connect(function(player: Player)
		on(player, function(session)
			advance(session, STEP.PowerOn)
		end)
	end)
	GameEvents.BitsEarned:Connect(function(player: Player, _amount: number, source: string)
		if source == "Collect" or source == "AutoCollect" then
			on(player, function(session)
				if session.Data.Tutorial == STEP.PowerOn then
					advance(session, STEP.FirstCollect)
				end
			end)
		end
	end)
	GameEvents.Upgraded:Connect(function(player: Player, _count: number)
		on(player, function(session)
			local tutorial = session.Data.Tutorial
			if tutorial == STEP.FirstCollect then
				advance(session, STEP.FirstUpgrade)
			elseif tutorial == STEP.FirstUpgrade then
				advance(session, STEP.SecondUpgrade)
			end
		end)
	end)
	GameEvents.ZoneUnlocked:Connect(function(player: Player, zone: number)
		if zone == 2 then
			on(player, function(session)
				advance(session, STEP.UnlockRam)
			end)
		end
	end)
	GameEvents.CapsuleOpened:Connect(function(player: Player, _capsuleId: string)
		on(player, function(session)
			if session.Data.Tutorial >= STEP.UnlockRam then
				advance(session, STEP.Done)
			end
		end)
	end)
end

return OnboardingService
