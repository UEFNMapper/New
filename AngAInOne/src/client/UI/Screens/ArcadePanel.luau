--!strict
--[[
	ArcadePanel : la borne d'arcade du lobby. On choisit un des 4 mini-jeux antivirus
	pour s'entraîner et gagner quelques Bits (avec un délai entre deux récompenses).
]]

local Create = require(script.Parent.Parent.Create)
local Style = require(script.Parent.Parent.Style)
local Panel = require(script.Parent.Parent.Components.Panel)
local Keycap = require(script.Parent.Parent.Components.Keycap)
local App = require(script.Parent.Parent.App)

local New = Create.New

local ArcadePanel = {}

-- Branché par Main (évite que l'UI dépende des contrôleurs de jeu).
ArcadePanel.OnPlay = nil :: ((kind: string) -> ())?

local GAMES = {
	{ Kind = "Scan", Name = "Scan", Rule = "Tape les virus qui surgissent !", Icon = "Bot" },
	{ Kind = "Firewall", Name = "Firewall", Rule = "Tire sur les virus qui tombent !", Icon = "Bolt" },
	{ Kind = "Memory", Name = "Memory", Rule = "Retrouve les paires de cartes !", Icon = "Cpu" },
	{ Kind = "Dodge", Name = "Dodge", Rule = "Évite les virus en sautant !", Icon = "Star" },
}

function ArcadePanel.Mount(layer: Frame)
	local panel = Panel.new({
		Name = "ArcadePanel",
		Title = "ARCADE ANTIVIRUS",
		Subtitle = "Entraîne-toi et gagne des Bits !",
		Size = UDim2.fromScale(0.62, 0.7),
		Parent = layer,
		Accent = Style.Color("AccentCyan"),
	})
	local grid: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	}, {
		New("UIGridLayout", {
			CellSize = UDim2.new(0.5, -8, 0.5, -8),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}) :: Instance,
	})
	for index, game_ in GAMES do
		local cell: Frame = New("Frame", {
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Tag = { "GlassSunken", "RoundM" },
			Parent = grid,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.new(1, -32, 0, 30),
			BackgroundTransparency = 1,
			Text = game_.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextTitle",
			Parent = cell,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(16, 44),
			Size = UDim2.new(1, -32, 0, 22),
			BackgroundTransparency = 1,
			Text = game_.Rule,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tag = "TextMuted",
			Parent = cell,
		})
		Keycap.new({
			Text = "JOUER",
			Icon = game_.Icon,
			Variant = "Primary",
			Size = UDim2.new(1, -32, 0, 52),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Small = true,
			OnClick = function()
				if ArcadePanel.OnPlay then
					ArcadePanel.OnPlay(game_.Kind)
				end
			end,
			Parent = cell,
		})
	end
	App.RegisterPanel("Arcade", { Panel = panel })
end

return ArcadePanel
