--!strict
--[[
	App : racine de l'interface.
	- ScreenGui avec zones sûres (ScreenInsets) et un cadre "Root" mis à l'échelle par
	  UIScale : tout est dessiné en pixels de conception (1280x720) puis adapté à l'écran.
	  Sur téléphone, l'échelle garde les boutons de 72 px de conception à >= 44 px réels.
	- Calques : Hud < Panels < Overlays < Moments < Toasts
	- Gestionnaire de fenêtres : une seule fenêtre ouverte à la fois, fond assombri
	  + flou léger, fermeture par clic à l'extérieur ou Échap / bouton B manette.
]]

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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

local function computeScale(viewport: Vector2): number
	local s = math.min(viewport.X / DESIGN.X, viewport.Y / 620)
	return math.clamp(s, 0.6, 1.35)
end

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
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else DESIGN
		local s = computeScale(viewport)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	resize()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end

	layer("Hud", 1)
	local panelsLayer = layer("Panels", 2)
	layer("Overlays", 3)
	layer("Moments", 4)
	layer("Toasts", 5)

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
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if current and not processed then
				App.Close()
			end
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
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
