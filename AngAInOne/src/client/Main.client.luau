--!strict
--[[
	Point d'entrée client d'AngAInOne.
	1. Contrôleurs de base (réseau, état, audio)
	2. Interface (style, HUD, fenêtres, moments)
	3. Monde (effets, zones, prompts, guide)
	4. Signale au serveur qu'on est prêt (répété tant que l'état n'arrive pas :
	   le profil du joueur peut encore être en chargement).
]]

local Controllers = script.Parent.Controllers
local UI = script.Parent.UI
local Screens = UI.Screens

local Net = require(Controllers.Net)
local Store = require(Controllers.Store)
local Audio = require(Controllers.Audio)
local Feedback = require(Controllers.Feedback)
local WorldFx = require(Controllers.WorldFx)
local ZoneTracker = require(Controllers.ZoneTracker)
local Interactions = require(Controllers.Interactions)
local Guide = require(Controllers.Guide)

local App = require(UI.App)
local Style = require(UI.Style)
local Keycap = require(UI.Components.Keycap)
local HUD = require(Screens.HUD)
local Toasts = require(Screens.Toasts)
local Moments = require(Screens.Moments)
local ComponentsPanel = require(Screens.ComponentsPanel)
local NanobotsPanel = require(Screens.NanobotsPanel)
local QuestsPanel = require(Screens.QuestsPanel)
local ShopPanel = require(Screens.ShopPanel)
local MenuPanel = require(Screens.MenuPanel)
local ElevatorPanel = require(Screens.ElevatorPanel)
local BiosPanel = require(Screens.BiosPanel)
local OverclockOverlay = require(Screens.OverclockOverlay)
local DevPanel = require(Screens.DevPanel)

-- 1. Base
Store.Start()
Audio.Start()
Keycap.ClickSound = function()
	Audio.Play("Click")
end

-- 2. Interface
local gui = App.Mount()
HUD.Mount(App.Layers.Hud)
Toasts.Mount(App.Layers.Toasts)
Moments.Mount(App.Layers.Moments)
ComponentsPanel.Mount(App.Layers.Panels)
NanobotsPanel.Mount(App.Layers.Panels)
QuestsPanel.Mount(App.Layers.Panels)
ShopPanel.Mount(App.Layers.Panels)
MenuPanel.Mount(App.Layers.Panels)
ElevatorPanel.Mount(App.Layers.Panels)
BiosPanel.Mount(App.Layers.Panels)
OverclockOverlay.Mount(App.Layers.Overlays)
DevPanel.Mount(App.Layers.Overlays) -- Studio uniquement
task.spawn(Style.Verify, gui)

-- Actions de la carte Objectif (le CTA unique du HUD)
HUD.OnObjective = function(action: string, arg: any)
	if action == "PowerOn" then
		Net.Fire("PowerOn")
	elseif action == "Unlock" then
		Net.Fire("UnlockZone", arg)
	elseif action == "OpenModule" or action == "OpenZone" then
		App.Open("Components", arg)
	elseif action == "OpenNanobots" then
		App.Open("Nanobots", arg)
	elseif action == "OpenBios" then
		App.Open("Bios", arg)
	end
end

-- Transitions de déplacement (ascenseur, bannière "Y aller")
local function beforeTravel(_floor: number)
	Audio.Play("Whoosh")
end
ElevatorPanel.BeforeTravel = beforeTravel
Moments.OnTravel = function(floor: number)
	beforeTravel(floor)
	Net.Fire("Travel", floor)
end

MenuPanel.OnSettings = function(music: number, sfx: number, _reduced: boolean, _hue: number)
	Audio.SetVolumes(music, sfx)
end

-- 3. Monde
Feedback.OnWorldFx = WorldFx.OnFx
Feedback.Start()
WorldFx.Start()
ZoneTracker.Start()
Interactions.Start()
Guide.Start()

-- Premier état : réglages sauvegardés + écran d'allumage si besoin
local settingsLoaded = false
Store.Changed:Connect(function(state: any)
	if not settingsLoaded then
		settingsLoaded = true
		MenuPanel.LoadSettings(state.Data.Settings)
	end
	Moments.ShowPowerOn(not state.Data.PoweredOn)
end)

-- 4. Prêt : on relance tant que le serveur n'a pas répondu (profil en chargement).
task.spawn(function()
	while not Store.Ready do
		Net.Fire("ClientReady")
		task.wait(2)
	end
end)
