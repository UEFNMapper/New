--!nonstrict
-- Échelle d'écran partagée : l'interface est dessinée pour 1280 x 720 et réduite
-- sur les petits écrans (téléphones). Sert au HUD (Kit.AutoScale) et aux
-- étiquettes 3D (BillboardGui) pour qu'elles ne mangent pas l'écran sur mobile.

local Workspace = game:GetService("Workspace")

local ScreenScale = {}

-- Échelle du HUD : on vise 800 px de haut pour laisser de la place au jeu.
function ScreenScale.Hud(): number
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min(size.X / 1280, size.Y / 800), 0.42, 1.25)
end

-- Échelle des fenêtres (modales : elles ont tout l'écran pour elles, un peu plus grandes que le HUD).
function ScreenScale.Window(): number
	local hud = ScreenScale.Hud()
	return math.min(hud * 1.3, math.max(1, hud))
end

-- Échelle des étiquettes 3D (jamais agrandies, un peu moins réduites que le HUD).
function ScreenScale.World(): number
	return math.clamp(ScreenScale.Hud() * 1.1, 0.5, 1)
end

-- Taille d'une étiquette 3D en pixels de maquette, adaptée à l'écran.
function ScreenScale.Px(width: number, height: number): UDim2
	local s = ScreenScale.World()
	return UDim2.fromOffset(math.floor(width * s + 0.5), math.floor(height * s + 0.5))
end

return ScreenScale
