--!strict
--[[
	Theme : tokens de design centralisés (couleurs, typo, espacements, rayons, durées).
	Source unique de vérité : le client en dérive une StyleSheet, le serveur s'en sert
	pour colorer la map. Les couleurs sont des chaînes hex pour rester pures (testables
	avec Lune) ; utiliser Color3.fromHex côté Roblox.
]]

local Theme = {}

Theme.Colors = table.freeze({
	BgBase = "0B0F1A",
	BgDeep = "070A12",
	Surface = "141A2B",
	SurfaceRaised = "1B2338",
	SurfaceSunken = "0E1322",
	Stroke = "FFFFFF",
	TextPrimary = "E8EBF4",
	TextMuted = "8A93A8",
	TextDim = "5B6479",
	BrandAnga = "F0565B",
	BrandAngaDark = "B83A40",
	AccentCyan = "4FD1C5",
	AccentViolet = "8B7CFF",
	AccentAmber = "F6AD55",
	CurrencyBits = "F6C453",
	CurrencyChips = "7FDBFF",
	Success = "68D391",
	Warning = "F6AD55",
	Danger = "FC8181",
	MetalLight = "3A4358",
	MetalDark = "1A2030",
	Copper = "C8814A",
	PcbGreen = "0F1F1A",
})

-- Transparences de référence (0 = opaque).
Theme.Alpha = table.freeze({
	Glass = 0.18,
	GlassStrong = 0.08,
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
	M = 12,
	L = 18,
	Pill = 999,
})

Theme.TextSize = table.freeze({
	Caption = 13,
	Body = 16,
	BodyLarge = 18,
	Title = 22,
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
