--!nonstrict
-- Registre côté client (rempli par Main.client) : écrans et services d'UI
-- partagés, pour éviter les require circulaires.
--   UIRegistry.Screens.Shop:Open()
--   UIRegistry.Toast("Hello", "Good")
--   UIRegistry.OpenKaiju(uid)
local UIRegistry = {
	Screens = {},
	Toast = function(_text: string, _kind: string?) end,
	Announce = function(_text: string, _color: Color3?) end,
	OpenKaiju = function(_uid: string) end,
	ShowOdds = function(_title: string, _rows: { { Label: string, Chance: number, Color: Color3? } }) end,
}
return UIRegistry
