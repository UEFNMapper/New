--!strict
--[[
	Interactions : les prompts du monde (E / X manette / tap).
	- "Minigame" (terminal antivirus en fin de monde) : lance le mini-jeu 2D du monde ; au monde 7,
	  c'est la phase 3 du combat contre LAGZ (bouclier détruit, Firewall boss = difficulté 8)
	- "Arcade" (lobby) : choisir un mini-jeu pour gagner quelques Bits
	- "Shop" / "Daily" (lobby) : ouvrent la boutique / les missions
	Le serveur valide tout (bon checkpoint, distance, durée).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local BossLogic = require(Shared.Util.BossLogic)

local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local App = require(script.Parent.Parent.UI.App)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)
local MinigamePanel = require(script.Parent.Parent.UI.Screens.MinigamePanel)

local Interactions = {}

-- Lance le terminal antivirus du monde `world`.
function Interactions.PlayTerminal(world: number)
	local data = Store.Data()
	local def = Tower.Worlds[world]
	if not data or not def or MinigamePanel.IsPlaying() then
		return
	end
	if data.Cleared >= world then
		Toasts.Show("Success", "Ce terminal est déjà nettoyé. Le portail est ouvert !")
		return
	end
	if data.Stage ~= Tower.TerminalStage(world) or data.Cleared ~= world - 1 then
		Toasts.Show("Info", "Atteins d'abord le checkpoint de cette salle !")
		return
	end
	local boss = world == BossLogic.WORLD
	if boss and Players.LocalPlayer:GetAttribute("BossPhase") ~= BossLogic.Phase.Terminal then
		Toasts.Show("Info", "Le bouclier de LAGZ protège ce terminal : branche d'abord les 3 prises antivirus !")
		return
	end
	Net.Fire("MinigameStart", world)
	local difficulty = if boss then BossLogic.BOSS_DIFFICULTY else world
	MinigamePanel.Play(def.Minigame, difficulty, function(success: boolean, score: number, _duration: number)
		Net.Fire("MinigameEnd", world, success, score)
	end)
end

-- Partie d'arcade (lobby) : petite récompense, avec un délai entre deux gains.
function Interactions.PlayArcade(kind: string)
	if MinigamePanel.IsPlaying() then
		return
	end
	App.Close()
	Net.Fire("ArcadeStart", kind)
	MinigamePanel.Play(kind, 2, function(success: boolean, score: number, _duration: number)
		Net.Fire("ArcadeEnd", kind, success, score)
	end)
end

local HANDLERS: { [string]: (prompt: ProximityPrompt) -> () } = {
	Minigame = function(prompt)
		local world = prompt:GetAttribute("World")
		if type(world) == "number" then
			Interactions.PlayTerminal(world)
		end
	end,
	Arcade = function(_prompt)
		App.Open("Arcade")
	end,
	Shop = function(_prompt)
		App.Open("Shop")
	end,
	Daily = function(_prompt)
		App.Open("Missions")
	end,
}

function Interactions.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local action = prompt:GetAttribute("Action")
		if type(action) ~= "string" then
			return
		end
		local handler = HANDLERS[action]
		if handler then
			handler(prompt)
		end
	end)
end

return Interactions
