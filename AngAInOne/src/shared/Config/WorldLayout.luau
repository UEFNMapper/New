--!strict
--[[
	WorldLayout : géométrie du PC géant, partagée par le serveur (construction, contrôles
	d'accès) et le client (zone courante, guidage). Une seule source de vérité.

	Le PC est couché sur le flanc : la carte mère est le sol (y = 0), la vitre latérale est
	le plafond. Vue de dessus, la carte est découpée en 3 x 3 districts :

	          X : A (ouest, façade)   B (centre)        C (est, arrière)
	    Z  1 (nord) : Cryo Tower (4)   The Core (5)      Neural Nexus (7)
	       2        : Data Vault (3)   HUB (chipset)     Memory Lanes (2)
	       3 (sud)  : ------- La Centrale (1) -------    Render Canyon (6)

	Chaque zone a UN portail d'énergie vers sa zone "parente" (arbre enraciné au hub) :
	La Centrale, Data Vault, Memory Lanes, The Core -> hub ; Cryo Tower -> Data Vault ;
	Render Canyon et Neural Nexus -> Memory Lanes.
]]

local WorldLayout = {}

WorldLayout.DISTRICT_X = 360
WorldLayout.DISTRICT_Z = 280
WorldLayout.WALL_HEIGHT = 44
WorldLayout.CASE_HEIGHT = 330 -- hauteur de la vitre (plafond)
WorldLayout.GATE_WIDTH = 34

local DX, DZ = WorldLayout.DISTRICT_X, WorldLayout.DISTRICT_Z

-- Limites de la carte mère (3 x 3 districts centrés sur l'origine).
WorldLayout.MIN_X = -1.5 * DX
WorldLayout.MAX_X = 1.5 * DX
WorldLayout.MIN_Z = -1.5 * DZ
WorldLayout.MAX_Z = 1.5 * DZ

export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

export type ZoneLayout = {
	Zone: number, -- 0 = hub
	Rects: { Rect }, -- une zone peut couvrir plusieurs districts (La Centrale)
	Parent: number, -- zone d'où l'on entre (0 = hub)
	Gate: Vector3, -- centre du portail (au sol)
	GateAxis: "X" | "Z", -- le portail est un mur perpendiculaire à cet axe
	Spawn: Vector3, -- point d'arrivée (téléportation), juste derrière le portail
	Center: Vector3, -- centre "visuel" de la zone
}

-- Rectangle d'un district : colonne 1..3 (A..C), ligne 1..3 (nord..sud).
local function district(col: number, row: number): Rect
	local minX = WorldLayout.MIN_X + (col - 1) * DX
	local minZ = WorldLayout.MIN_Z + (row - 1) * DZ
	return { MinX = minX, MaxX = minX + DX, MinZ = minZ, MaxZ = minZ + DZ }
end

local function centerOf(rect: Rect): Vector3
	return Vector3.new((rect.MinX + rect.MaxX) / 2, 0, (rect.MinZ + rect.MaxZ) / 2)
end

WorldLayout.HubRect = district(2, 2)

-- Bords des districts (pour placer les portails)
local hub = WorldLayout.HubRect
local A1, B1, C1 = district(1, 1), district(2, 1), district(3, 1)
local A2, C2 = district(1, 2), district(3, 2)
local A3, B3, C3 = district(1, 3), district(2, 3), district(3, 3)

local function zone(
	index: number,
	rects: { Rect },
	parent: number,
	gate: Vector3,
	axis: "X" | "Z",
	inward: Vector3
): ZoneLayout
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, rect in rects do
		minX = math.min(minX, rect.MinX)
		maxX = math.max(maxX, rect.MaxX)
		minZ = math.min(minZ, rect.MinZ)
		maxZ = math.max(maxZ, rect.MaxZ)
	end
	return {
		Zone = index,
		Rects = rects,
		Parent = parent,
		Gate = gate,
		GateAxis = axis,
		Spawn = gate + inward * 26 + Vector3.new(0, 4, 0),
		Center = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2),
	}
end

-- Zones (index = zone du jeu)
WorldLayout.Zones = {
	-- 1 · La Centrale : tout le sud-ouest et le sud-centre (sous le cache d'alimentation)
	zone(1, { A3, B3 }, 0, Vector3.new(centerOf(B3).X, 0, hub.MaxZ), "Z", Vector3.new(0, 0, 1)),
	-- 2 · Memory Lanes : est-centre, portail sur le bord ouest (hub)
	zone(2, { C2 }, 0, Vector3.new(C2.MinX, 0, centerOf(C2).Z), "X", Vector3.new(1, 0, 0)),
	-- 3 · Data Vault : ouest-centre, portail sur le bord est (hub)
	zone(3, { A2 }, 0, Vector3.new(A2.MaxX, 0, centerOf(A2).Z), "X", Vector3.new(-1, 0, 0)),
	-- 4 · Cryo Tower : nord-ouest, portail sur le bord sud (Data Vault)
	zone(4, { A1 }, 3, Vector3.new(centerOf(A1).X, 0, A1.MaxZ), "Z", Vector3.new(0, 0, -1)),
	-- 5 · The Core : nord-centre, portail sur le bord sud (hub)
	zone(5, { B1 }, 0, Vector3.new(centerOf(B1).X, 0, B1.MaxZ), "Z", Vector3.new(0, 0, -1)),
	-- 6 · Render Canyon : sud-est, portail sur le bord nord (Memory Lanes)
	zone(6, { C3 }, 2, Vector3.new(centerOf(C3).X, 0, C3.MinZ), "Z", Vector3.new(0, 0, 1)),
	-- 7 · Neural Nexus : nord-est, portail sur le bord sud (Memory Lanes)
	zone(7, { C1 }, 2, Vector3.new(centerOf(C1).X, 0, C1.MaxZ), "Z", Vector3.new(0, 0, -1)),
} :: { ZoneLayout }

WorldLayout.HubSpawn = centerOf(hub) + Vector3.new(0, 5, 70)

local function inside(rect: Rect, position: Vector3): boolean
	return position.X >= rect.MinX and position.X <= rect.MaxX and position.Z >= rect.MinZ and position.Z <= rect.MaxZ
end

-- Zone contenant la position : 0 = hub, 1..7 = zone, -1 = hors de la carte mère.
function WorldLayout.ZoneAt(position: Vector3): number
	if inside(hub, position) then
		return 0
	end
	for _, layout in WorldLayout.Zones do
		for _, rect in layout.Rects do
			if inside(rect, position) then
				return layout.Zone
			end
		end
	end
	return -1
end

-- Prochain portail à franchir pour aller de la zone `from` à la zone `to` (arbre de zones).
-- Renvoie la position du portail, ou nil si on est déjà dans la bonne zone.
function WorldLayout.NextGate(from: number, to: number): Vector3?
	if from == to then
		return nil
	end
	-- Chemin de `to` jusqu'au hub
	local chain: { number } = {}
	local current = to
	while current ~= 0 do
		table.insert(chain, 1, current)
		current = WorldLayout.Zones[current].Parent
	end
	-- `from` est-il un ancêtre de `to` ? -> on descend vers l'enfant suivant.
	local position = if from == 0 then 0 else table.find(chain, from)
	if position ~= nil then
		local child = chain[position + 1]
		return if child then WorldLayout.Zones[child].Gate else nil
	end
	-- Sinon on remonte : on sort de la zone actuelle par son portail.
	if from > 0 then
		return WorldLayout.Zones[from].Gate
	end
	return nil
end

return table.freeze(WorldLayout)
