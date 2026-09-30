--!strict
--[[
	ArcadePanel : la borne d'arcade du lobby. On choisit un des 6 mini-jeux antivirus (grille 3 x 2)
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
	{ Kind = "Popup", Name = "Pop-up Killer", Rule = "Ferme les pubs avant que la RAM explose !", Icon = "Close" },
	{ Kind = "Defrag", Name = "Défrag", Rule = "Regroupe les blocs de chaque fichier !", Icon = "Check" },
}

function ArcadePanel.Mount(layer: Frame)
	local panel = Panel.new({
		Name = "ArcadePanel",
		Title = "ARCADE ANTIVIRUS",
		Subtitle = "Entraîne-toi et gagne des Bits !",
		Size = UDim2.fromScale(0.72, 0.74),
		Parent = layer,
		Accent = Style.Color("AccentCyan"),
	})
	local grid: Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = panel.Body,
	}, {
		New("UIGridLayout", {
			-- 3 colonnes x 2 lignes : 2 espacements de 12 px à répartir sur 3 cases.
			CellSize = UDim2.new(1 / 3, -8, 0.5, -6),
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
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -28, 0, 30),
			BackgroundTransparency = 1,
			Text = game_.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Tag = "TextTitle",
			Parent = cell,
		})
		New("TextLabel", {
			Position = UDim2.fromOffset(14, 42),
			Size = UDim2.new(1, -28, 1, -110), -- deux lignes au besoin, au-dessus du bouton
			BackgroundTransparency = 1,
			Text = game_.Rule,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Tag = "TextMuted",
			Parent = cell,
		})
		Keycap.new({
			Text = "JOUER",
			Icon = game_.Icon,
			Variant = "Primary",
			Size = UDim2.new(1, -28, 0, 52),
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
