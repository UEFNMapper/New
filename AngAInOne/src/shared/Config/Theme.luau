--!strict
--[[
	Theme : tokens de design centralisés (couleurs, typo, espacements, rayons, durées).
	Source unique de vérité : le client en dérive une StyleSheet, le serveur s'en sert
	pour colorer la map. Les couleurs sont des chaînes hex pour rester pures (testables
	avec Lune) ; utiliser Color3.fromHex côté Roblox.
]]

local Theme = {}

Theme.Colors = table.freeze({
	-- Palette de l'app AngAInOne (Fluent sombre) : surfaces plates gris anthracite, texte blanc.
	BgBase = "1A1A1A",
	BgDeep = "111111",
	Surface = "202020",
	SurfaceRaised = "2B2B2B",
	SurfaceSunken = "1B1B1B",
	Stroke = "FFFFFF",
	Outline = "3A3A3A", -- liseré fin des fenêtres, cartes et boutons
	TextPrimary = "FFFFFF",
	TextMuted = "C5C5C5",
	TextDim = "8F8F8F",
	BrandAnga = "F0565B",
	BrandAngaDark = "B83A40",
	AccentCyan = "4FD1C5",
	AccentViolet = "8B7CFF",
	AppAccent = "9B2FD4", -- violet de l'app : boutons principaux, page active
	AccentAmber = "F6AD55",
	CurrencyBits = "F6C453",
	CurrencyChips = "7FDBFF",
	Success = "6CCB5F",
	Warning = "FCE100",
	Danger = "FF99A4",
	MetalLight = "2D2D2D",
	MetalDark = "262626",
	Copper = "C8814A",
	PcbGreen = "0F1F1A",
})

-- Transparences de référence (0 = opaque).
Theme.Alpha = table.freeze({
	Glass = 0.06, -- surfaces presque opaques (style app), un soupçon de transparence sur le HUD
	GlassStrong = 0.02,
	StrokeSoft = 0.86,
	StrokeMedium = 0.7,
	Overlay = 0.35,
})

Theme.Spacing = table.freeze({
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
	XXL = 32,
})

Theme.Radius = table.freeze({
	S = 8,
	M = 10,
	L = 12,
	Pill = 999,
})

-- Tailles en pixels de conception (canevas 1280 × 720) : 18 est le minimum lisible sur téléphone.
Theme.TextSize = table.freeze({
	Caption = 14,
	Body = 18,
	BodyLarge = 20,
	Title = 24,
	Display = 30,
	Hero = 44,
})

Theme.Motion = table.freeze({
	Fast = 0.12,
	Base = 0.22,
	Panel = 0.28,
	Slow = 0.45,
	PressScale = 0.95,
	HoverScale = 1.04,
})

-- Dégradé RGB "néon doux" utilisé par les bordures dynamiques des panneaux.
Theme.RgbCycle = table.freeze({ "8B7CFF", "4FD1C5", "F6C453", "F0565B", "8B7CFF" })

-- Couleurs de rareté des Nanobots.
Theme.Rarity = table.freeze({
	Common = "A0AEC0",
	Rare = "4FD1C5",
	Epic = "8B7CFF",
	Legendary = "F6C453",
	Mythic = "F0565B",
})

return table.freeze(Theme)
