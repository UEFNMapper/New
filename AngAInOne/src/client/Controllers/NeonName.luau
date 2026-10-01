--!strict
--[[
	NeonName : le mur du lobby où le pseudo du joueur s'affiche en néon, à la couleur d'accent de
	l'app (comme le Test de perf d'AngAInOne). Pièces taguées NeonName (World/Tower/EasterEggs) ;
	chaque joueur voit son propre pseudo.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Branding = require(Shared.Config.Branding)
local Style = require(script.Parent.Parent.UI.Style)

local NeonName = {}

local player = Players.LocalPlayer
local ACCENT = Color3.fromHex(Branding.PartnerApp.Accent)

local function build(part: BasePart)
	local existing = part:FindFirstChild("NeonNameGui")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NeonNameGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = part

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Size = UDim2.fromScale(0.9, 0.16)
	caption.Position = UDim2.fromScale(0.05, 0.08)
	caption.Text = "ICI, C'EST TOI QUI STREAMES"
	caption.TextScaled = true
	caption.FontFace = Style.Fonts.Bold
	caption.TextColor3 = Color3.fromRGB(197, 197, 197)
	caption.Parent = gui

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(0.9, 0.46)
	name.Position = UDim2.fromScale(0.05, 0.26)
	name.Text = player.DisplayName
	name.TextScaled = true
	name.FontFace = Style.Fonts.Heavy
	name.TextColor3 = ACCENT:Lerp(Color3.new(1, 1, 1), 0.3)
	name.TextStrokeColor3 = ACCENT
	name.TextStrokeTransparency = 0
	name.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(0.9, 0.14)
	sub.Position = UDim2.fromScale(0.05, 0.76)
	sub.Text = `{Branding.ChannelName} · en néon, couleur d'accent`
	sub.TextScaled = true
	sub.FontFace = Style.Fonts.Medium
	sub.TextColor3 = ACCENT
	sub.Parent = gui

	-- Léger scintillement de néon (le nom reste lisible)
	task.spawn(function()
		local t = 0
		while gui.Parent do
			t += 0.1
			name.TextStrokeTransparency = 0.1 + 0.1 * math.sin(t * 2.3) + (if math.random() < 0.02 then 0.3 else 0)
			task.wait(0.1)
		end
	end)
end

local function track(instance: Instance)
	if instance:IsA("BasePart") then
		build(instance)
	end
end

function NeonName.Start()
	for _, instance in CollectionService:GetTagged("NeonName") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("NeonName"):Connect(track)
end

return NeonName
