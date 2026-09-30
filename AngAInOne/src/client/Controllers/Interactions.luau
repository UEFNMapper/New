--!strict
--[[
	Interactions : les prompts du monde (E / X manette / tap) ouvrent le bon écran.
	Le prompt porte un attribut "Action" posé par le serveur (MapBuilder).
	Les actions qui modifient l'état (overclock) passent par une remote validée.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")

local Net = require(script.Parent.Net)
local App = require(script.Parent.Parent.UI.App)

local Interactions = {}

local HANDLERS: { [string]: (prompt: ProximityPrompt) -> () } = {
	Upgrade = function(prompt)
		App.Open("Components", prompt:GetAttribute("ModuleId"))
	end,
	Elevator = function(_prompt)
		App.Open("Elevator")
	end,
	Unlock = function(_prompt)
		App.Open("Components")
	end,
	Power = function(_prompt)
		App.Open("Components", 1)
	end,
	Cooling = function(_prompt)
		App.Open("Components", 4)
	end,
	Capsules = function(_prompt)
		App.Open("Nanobots", "Capsules")
	end,
	Downloads = function(_prompt)
		App.Open("Quests")
	end,
	Overclock = function(_prompt)
		Net.Fire("OverclockStart")
	end,
	Reboot = function(_prompt)
		App.Open("Bios", "Reboot")
	end,
	Singularity = function(_prompt)
		App.Open("Bios", "Singularity")
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
