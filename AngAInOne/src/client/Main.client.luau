--!strict
--[[
	Point d'entrée client d'AngAInOne.

	Robustesse : chaque module est chargé et démarré ISOLÉMENT (pcall). Si un écran
	plante, il est signalé (fenêtre Sortie + encadré rouge dans Studio) mais le reste
	du jeu continue de fonctionner. Le signal "prêt" part en tout premier.

	1. Rapport d'erreurs, réseau, état, audio + signal "prêt" au serveur
	2. Interface (style, HUD, fenêtres, moments)
	3. Monde (effets, zones, prompts, guide)
]]

local Controllers = script.Parent.Controllers
local UI = script.Parent.UI
local Screens = UI.Screens

local ErrorReporter = require(Controllers.ErrorReporter)
ErrorReporter.Start()

-- Charge un module sans jamais bloquer le démarrage (nil si son chargement échoue).
local function load(module: Instance): any
	local ok, result = pcall(require, module :: ModuleScript)
	if not ok then
		ErrorReporter.Report(`Chargement de {module.Name}`, result)
		return nil
	end
	return result
end

-- Exécute une étape de démarrage ; une erreur est signalée sans arrêter les suivantes.
local function step(name: string, fn: () -> ())
	xpcall(fn, function(e: any)
		ErrorReporter.Report(name, `{tostring(e)}\n{debug.traceback()}`)
	end)
end

-- 1. Base -------------------------------------------------------------------------
local Net = load(Controllers.Net)
local Store = load(Controllers.Store)
local Audio = load(Controllers.Audio)

step("Store", function()
	Store.Start()
end)

-- Signal "prêt" : relancé tant que l'état n'arrive pas (le profil peut être en chargement).
task.spawn(function()
	while not (Store and Store.Ready) do
		if Net then
			pcall(Net.Fire, "ClientReady")
		end
		task.wait(2)
	end
end)

step("Audio", function()
	Audio.Start()
end)

-- 2. Interface --------------------------------------------------------------------
local App = load(UI.App)
local Style = load(UI.Style)
local Keycap = load(UI.Components.Keycap)
local HUD = load(Screens.HUD)
local Toasts = load(Screens.Toasts)
local Moments = load(Screens.Moments)
local MenuPanel = load(Screens.MenuPanel)
local ElevatorPanel = load(Screens.ElevatorPanel)

local gui: ScreenGui? = nil
step("App", function()
	Keycap.ClickSound = function()
		Audio.Play("Click")
	end
	gui = App.Mount()
end)

step("Dialogue", function()
	local Dialogue = load(Screens.Dialogue)
	Dialogue.OnBlip = function(pitch: number)
		Audio.Play("Voice", pitch)
	end
	Dialogue.Mount(App.Layers.Moments)
end)
step("HUD", function()
	HUD.Mount(App.Layers.Hud)
end)
step("Toasts", function()
	Toasts.Mount(App.Layers.Toasts)
end)
step("Moments", function()
	Moments.Mount(App.Layers.Moments)
end)
for _, name in
	{ "ComponentsPanel", "NanobotsPanel", "QuestsPanel", "ShopPanel", "MenuPanel", "ElevatorPanel", "BiosPanel" }
do
	step(name, function()
		local screen = load(Screens:FindFirstChild(name) :: Instance)
		if screen then
			screen.Mount(App.Layers.Panels)
		end
	end)
end
step("OverclockOverlay", function()
	load(Screens.OverclockOverlay).Mount(App.Layers.Overlays)
end)
step("DevPanel", function()
	load(Screens.DevPanel).Mount(App.Layers.Overlays) -- Studio uniquement
end)
step("Style.Verify", function()
	if gui then
		task.spawn(Style.Verify, gui)
	end
end)

-- Actions de la carte Objectif (le CTA unique du HUD)
step("Objectif", function()
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
end)

-- Transitions de déplacement (ascenseur, bannière "Y aller")
step("Voyages", function()
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
end)

-- 3. Monde ------------------------------------------------------------------------
local Feedback = load(Controllers.Feedback)
local WorldFx = load(Controllers.WorldFx)
step("Feedback", function()
	Feedback.OnWorldFx = WorldFx.OnFx
	Feedback.Start()
end)
step("WorldFx", function()
	WorldFx.Start()
end)
step("ZoneTracker", function()
	load(Controllers.ZoneTracker).Start()
end)
step("Interactions", function()
	load(Controllers.Interactions).Start()
end)
step("Guide", function()
	load(Controllers.Guide).Start()
end)

-- Premier état : réglages sauvegardés + écran d'allumage si besoin
step("État initial", function()
	local settingsLoaded = false
	Store.Changed:Connect(function(state: any)
		if not settingsLoaded then
			settingsLoaded = true
			step("Réglages", function()
				MenuPanel.LoadSettings(state.Data.Settings)
			end)
		end
		step("Écran d'allumage", function()
			Moments.ShowPowerOn(not state.Data.PoweredOn)
		end)
	end)
end)
