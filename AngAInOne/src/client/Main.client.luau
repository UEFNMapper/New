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

-- Menus simples : la liste des joueurs de Roblox est remplacée par Menu > Joueurs.
step("CoreGui", function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- 2. Interface --------------------------------------------------------------------
local App = load(UI.App)
local Style = load(UI.Style)
local Keycap = load(UI.Components.Keycap)
local HUD = load(Screens.HUD)
local Toasts = load(Screens.Toasts)
local Moments = load(Screens.Moments)
local MenuPanel = load(Screens.MenuPanel)

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
step("MedalCard", function()
	load(Screens.MedalCard).Mount(App.Layers.Moments)
end)
for _, name in { "ShopPanel", "MissionsPanel", "MenuPanel", "ArcadePanel" } do
	step(name, function()
		local screen = load(Screens:FindFirstChild(name) :: Instance)
		if screen then
			screen.Mount(App.Layers.Panels)
		end
	end)
end
step("MinigamePanel", function()
	load(Screens.MinigamePanel).Mount(App.Layers.Overlays)
end)
step("DevPanel", function()
	load(Screens.DevPanel).Mount(App.Layers.Overlays) -- Studio uniquement
end)
step("Style.Verify", function()
	if gui then
		task.spawn(Style.Verify, gui)
	end
end)
step("Réglages audio", function()
	MenuPanel.OnSettings = function(music: number, sfx: number, _reduced: boolean)
		Audio.SetVolumes(music, sfx)
	end
end)

-- 3. Monde ------------------------------------------------------------------------
step("Feedback", function()
	load(Controllers.Feedback).Start()
end)
step("WorldFx", function()
	load(Controllers.WorldFx).Start()
end)
step("AppScreen", function()
	load(Controllers.AppScreen).Start()
end)
-- Sensations de saut : coyote time + saut mémorisé.
step("JumpAssist", function()
	load(Controllers.JumpAssist).Start()
end)
step("TrapController", function()
	local TrapController = load(Controllers.TrapController)
	if TrapController then
		TrapController.Start()
	end
end)
-- L'app AngAInOne partout : morts = « Plantages » (carte en haut à droite), fenêtres de l'app
-- sur les parois de chaque monde, ponts « Téléchargement du pilote », Anga géant du lobby.
step("CrashLog", function()
	load(Controllers.CrashLog).Start(App.Layers.Toasts)
end)
step("AppPanels", function()
	load(Controllers.AppPanels).Start()
end)
-- Combat final contre LAGZ (monde 7) : arène, pièges de chaque phase, prises, bandeau.
step("BossController", function()
	load(Controllers.BossController).Start(App.Layers.Hud)
end)
-- Scénario « Opération Anti-Lag » : incidents de LAGZ, décor infecté / propre, répliques,
-- écran du live dans le lobby.
step("IncidentController", function()
	local IncidentController = load(Controllers.IncidentController)
	local MinigamePanel = load(Screens.MinigamePanel)
	if MinigamePanel and MinigamePanel.IsPlaying then
		IncidentController.IsBusy = MinigamePanel.IsPlaying
	end
	IncidentController.Start(App.Layers.Overlays)
end)
-- Ambiance par monde (atmosphère, lumière, particules) ; laisse la main au BLACKOUT.
step("Ambience", function()
	load(Controllers.Ambience).Start()
end)
-- TowerGlow : la coque s'allume monde par monde ; LagzCameo : LAGZ surgit de ses écrans.
for _, name in { "WorldState", "Story", "StreamMonitor", "TowerGlow", "LagzCameo" } do
	step(name, function()
		local controller = load(Controllers:FindFirstChild(name) :: Instance)
		if controller then
			controller.Start()
		end
	end)
end
-- Compagnon : mini-Anga sur son drone AngAInOne (guide, réactions, bulle de dialogue au-dessus).
step("Companion", function()
	local Companion = load(Controllers.Companion)
	local MinigamePanel = load(Screens.MinigamePanel)
	if Companion then
		if MinigamePanel and MinigamePanel.IsPlaying then
			Companion.IsBusy = MinigamePanel.IsPlaying
		end
		Companion.Start()
	end
end)
step("Interactions", function()
	local Interactions = load(Controllers.Interactions)
	Interactions.Start()
	load(Screens.ArcadePanel).OnPlay = Interactions.PlayArcade
end)

-- Premier état : réglages sauvegardés + histoire d'Anga à la première visite
step("État initial", function()
	local settingsLoaded = false
	local introShown = false
	Store.Changed:Connect(function(state: any)
		if not settingsLoaded then
			settingsLoaded = true
			step("Réglages", function()
				MenuPanel.LoadSettings(state.Data.Settings)
			end)
		end
		if not introShown and not state.Data.IntroSeen then
			introShown = true
			step("Intro", function()
				Moments.Intro(function()
					Net.Fire("IntroSeen")
				end)
			end)
		end
	end)
end)
