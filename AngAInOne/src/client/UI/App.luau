--!strict
--[[
	App : racine de l'interface.
	- ScreenGui avec zones sûres (ScreenInsets) et un cadre "Root" mis à l'échelle par
	  UIScale : tout est dessiné en pixels de conception (1280x720) puis adapté à l'écran.
	  Sur téléphone, l'échelle garde les boutons de 72 px de conception à >= 44 px réels.
	- Calques : Hud < Panels < Overlays < Moments < Alerts < Toasts
	  (Alerts : bandeau d'incident de LAGZ, jamais caché par une bannière ou une carte de Moments)
	- Gestionnaire de fenêtres : une seule fenêtre ouverte à la fois, fond assombri
	  + flou léger, fermeture par clic à l'extérieur ou Échap / bouton B manette.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Create)
local Style = require(script.Parent.Style)
local Motion = require(script.Parent.Motion)

local New = Create.New

export type PanelEntry = {
	Panel: any, -- Panel.Panel
	OnOpen: ((arg: any) -> ())?,
}

local App = {}

App.Gui = nil :: any
App.Root = nil :: any
App.Layers = {} :: { [string]: Frame }

local panels: { [string]: PanelEntry } = {}
local current: string? = nil
local dim: TextButton
local blur: BlurEffect
local scale: UIScale

local DESIGN = Vector2.new(1280, 720)

-- Échelle calculée sur la zone RÉELLEMENT disponible (hors barre Roblox et encoches) :
-- le canevas de conception garde au moins ~620 px de haut.
local function computeScale(available: Vector2): number
	local s = math.min(available.X / DESIGN.X, available.Y / 620)
	return math.clamp(s, 0.5, 1.35)
end

local CLOSE_ACTION = "AngAInOneClosePanel"
local DOCK_ACTION = "AngAInOneFocusDock"
App.DockFocus = nil :: GuiObject? -- premier bouton du dock (navigation manette)

local function layer(name: string, order: number): Frame
	local frame: Frame = New("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = order,
		Parent = App.Root,
	})
	App.Layers[name] = frame
	return frame
end

function App.Mount(): ScreenGui
	local player = Players.LocalPlayer
	local gui: ScreenGui = New("ScreenGui", {
		Name = "AngAInOneUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	})
	App.Gui = gui
	Style.Mount(gui)

	local root: Frame = New("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	App.Root = root
	scale = New("UIScale", { Parent = root })

	local function resize()
		local available = gui.AbsoluteSize
		if available.X < 10 or available.Y < 10 then
			return
		end
		local s = computeScale(available)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)

	layer("Hud", 1)
	local panelsLayer = layer("Panels", 2)
	layer("Overlays", 3)
	layer("Moments", 4)
	layer("Alerts", 5)
	layer("Toasts", 6)

	dim = New("TextButton", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Tag = "Backdrop",
		Parent = panelsLayer,
	})
	dim.Activated:Connect(function()
		App.Close()
	end)

	blur = Instance.new("BlurEffect")
	blur.Name = "UIBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.Escape and current and not processed then
			App.Close()
		end
	end)
	-- Manette : Y met le focus sur le dock (croix directionnelle + A pour choisir).
	ContextActionService:BindAction(
		DOCK_ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin and App.DockFocus and not current then
				GuiService.SelectedObject = if GuiService.SelectedObject then nil else App.DockFocus
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.ButtonY
	)

	gui.Parent = player:WaitForChild("PlayerGui")
	task.defer(resize)
	return gui
end

function App.RegisterPanel(name: string, entry: PanelEntry)
	panels[name] = entry
	entry.Panel.OnClose = function()
		if current == name then
			current = nil
			Motion.Tween(dim, { BackgroundTransparency = 1 }, 0.18).Completed:Once(function()
				if not current then
					dim.Visible = false
				end
			end)
			Motion.Tween(blur, { Size = 0 }, 0.2).Completed:Once(function()
				if not current then
					blur.Enabled = false
				end
			end)
			GuiService.SelectedObject = nil
			ContextActionService:UnbindAction(CLOSE_ACTION)
		end
	end
end

function App.Open(name: string, arg: any?)
	local entry = panels[name]
	if not entry then
		return
	end
	if current and current ~= name then
		local previous = panels[current]
		current = nil
		previous.Panel:Close()
	end
	current = name
	dim.Visible = true
	Motion.Tween(dim, { BackgroundTransparency = 0.55 }, 0.25)
	blur.Enabled = true
	Motion.Tween(blur, { Size = 10 }, 0.25)
	if entry.OnOpen then
		entry.OnOpen(arg)
	end
	entry.Panel:Open()
	-- B (manette) ferme la fenêtre, prioritaire sur la navigation de l'interface.
	ContextActionService:BindActionAtPriority(
		CLOSE_ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				App.Close()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.ButtonB
	)
	-- À la manette, on sélectionne le premier bouton de la fenêtre pour naviguer.
	if UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
		task.delay(0.3, function()
			if current == name then
				for _, descendant in entry.Panel.Window:GetDescendants() do
					if descendant:IsA("GuiButton") and descendant.Visible and descendant.Name ~= "Dim" then
						GuiService.SelectedObject = descendant
						break
					end
				end
			end
		end)
	end
end

function App.Close()
	if current then
		local entry = panels[current]
		entry.Panel:Close()
	end
end

function App.Toggle(name: string, arg: any?)
	if current == name then
		App.Close()
	else
		App.Open(name, arg)
	end
end

function App.Current(): string?
	return current
end

return App
