--!strict
-- Identité visuelle « KAIJU ALERT » : affiche de film de monstres rétro × bande
-- dessinée. Encre noire épaisse, crème, vert radioactif, orange magma,
-- ombres portées pleines, panneaux légèrement inclinés, rubans à rayures.

local rgb = Color3.fromRGB

local Theme = {}

Theme.Colors = {
	Ink = rgb(22, 16, 34),
	InkSoft = rgb(52, 40, 72),
	Paper = rgb(255, 246, 222),
	PaperDark = rgb(240, 222, 186),
	White = rgb(255, 255, 255),
	Radioactive = rgb(124, 255, 79),
	RadioactiveDark = rgb(40, 170, 60),
	Magma = rgb(255, 106, 31),
	MagmaDark = rgb(200, 60, 10),
	Pink = rgb(255, 61, 139),
	Cyan = rgb(61, 224, 255),
	Gold = rgb(255, 200, 40),
	Purple = rgb(150, 80, 255),
	Red = rgb(255, 50, 60),
	Cash = rgb(110, 255, 110),
	Gem = rgb(90, 210, 255),
	Shadow = rgb(0, 0, 0),
}

Theme.Fonts = {
	Title = Font.new("rbxasset://fonts/families/LuckiestGuy.json"),
	Impact = Font.new("rbxasset://fonts/families/Bangers.json"),
	Body = Font.new("rbxasset://fonts/families/FredokaOne.json"),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
}

Theme.Stroke = 3
Theme.StrokeThick = 5
Theme.Corner = 14
Theme.ShadowOffset = 6

-- Dégradés prêts à l'emploi (du haut vers le bas)
Theme.Gradients = {
	Radioactive = { rgb(170, 255, 120), rgb(60, 200, 70) },
	Magma = { rgb(255, 170, 70), rgb(240, 70, 20) },
	Pink = { rgb(255, 130, 190), rgb(230, 40, 120) },
	Cyan = { rgb(140, 240, 255), rgb(30, 160, 230) },
	Gold = { rgb(255, 235, 120), rgb(245, 160, 20) },
	Purple = { rgb(200, 150, 255), rgb(120, 60, 230) },
	Paper = { rgb(255, 250, 235), rgb(245, 228, 195) },
	Ink = { rgb(60, 48, 84), rgb(22, 16, 34) },
	Red = { rgb(255, 120, 110), rgb(210, 30, 40) },
	Grey = { rgb(210, 210, 215), rgb(150, 150, 160) },
}

return Theme
