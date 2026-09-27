--!nonstrict
-- Point d'entrée client : fondations, attente des données, UI, monde, effets.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")
local World = script.Parent:WaitForChild("World")

local State = require(Controllers.State)
local Audio = require(Controllers.Audio)
local CameraFx = require(Controllers.CameraFx)
local FxBus = require(Controllers.FxBus)
local UIRegistry = require(Controllers.UIRegistry)

State.Init()
Audio.Init()
CameraFx.Init()

State.WaitLoaded()

local function safeInit(name: string, module: any)
	local ok, err = pcall(function()
		if module.Init then
			module.Init()
		end
	end)
	if not ok then
		warn(("[Client] %s.Init a échoué : %s"):format(name, tostring(err)))
	end
end

-- Interface
local Kit = require(UI.Kit)
Kit.Root()
safeInit("Notifications", require(UI.Notifications))
safeInit("PromptStyle", require(UI.PromptStyle))
safeInit("Hud", require(UI.Hud))
safeInit("Cinematics", require(UI.Cinematics))

-- Fenêtres
local screensFolder = UI:WaitForChild("Screens")
for _, module in screensFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, screen = pcall(require, module)
		if ok then
			UIRegistry.Screens[module.Name] = screen
			safeInit(module.Name, screen)
		else
			warn(("[Client] écran %s : %s"):format(module.Name, tostring(screen)))
		end
	end
end

-- Monde
for _, name in { "KaijuRenderer", "MeteorRenderer", "PlotVisuals", "EventVisuals", "CharacterFx", "Tutorial" } do
	safeInit(name, require(World:WaitForChild(name)))
end

-- Les effets serveur n'arrivent qu'une fois tout le monde abonné
FxBus.Init()

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
end)
player:SetAttribute("ClientReady", true)
print("[Steal a Kaiju] client prêt")
