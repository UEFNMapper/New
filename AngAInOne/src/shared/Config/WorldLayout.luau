--!strict
--[[
	WorldLayout : géométrie du monde partagée par le serveur (construction de la map)
	et le client (détection de l'étage courant). Une seule source de vérité.
]]

local GameConfig = require(script.Parent.GameConfig)

local WorldLayout = {}

WorldLayout.TOWER_RADIUS = 300 -- distance hub -> tour
WorldLayout.TOWER_WIDTH = 110
WorldLayout.TOWER_DEPTH = 110
WorldLayout.FLOOR_HEIGHT = 46

-- Hauteur du dessus du sol de l'étage k (1..7), en coordonnées locales de la tour.
-- Le rez-de-chaussée ne dépasse que de 0,5 stud du hub : on entre sans sauter.
function WorldLayout.FloorY(k: number): number
	return 0.5 + (k - 1) * WorldLayout.FLOOR_HEIGHT
end

-- CFrame de base d'une tour (face avant = -Z locale, tournée vers le hub).
function WorldLayout.TowerCFrame(index: number): CFrame
	local angle = math.rad((index - 1) * (360 / GameConfig.MaxPlots))
	local position = Vector3.new(math.sin(angle), 0, math.cos(angle)) * WorldLayout.TOWER_RADIUS
	return CFrame.lookAt(position, Vector3.zero)
end

-- Étage (1..floorCount) pour une hauteur locale, en tenant compte des pieds du joueur.
function WorldLayout.FloorAt(localY: number, floorCount: number): number
	return math.clamp(math.floor((localY - 1) / WorldLayout.FLOOR_HEIGHT) + 1, 1, floorCount)
end

return table.freeze(WorldLayout)
