--!strict
-- Géométrie de la carte (partagée : le serveur construit, le client s'en sert
-- pour les flèches, le dôme de bouclier, etc.).
--
-- Le cratère est au centre (0,0,0). Les 8 îles sont en cercle ; l'avant de
-- chaque île (-Z local) regarde le cratère.

local Layout = {}

Layout.PlotCount = 8
Layout.PlotRadius = 250
Layout.PlotWidth = 100
Layout.PlotDepth = 116
Layout.GroundY = 0
Layout.CraterRadius = 74
Layout.BridgeWidth = 22

-- CFrame du centre de l'île i (1..8), au niveau du sol, face au cratère.
function Layout.PlotCFrame(i: number): CFrame
	local angle = (i - 1) / Layout.PlotCount * math.pi * 2
	local pos = Vector3.new(math.sin(angle) * Layout.PlotRadius, Layout.GroundY, math.cos(angle) * Layout.PlotRadius)
	return CFrame.lookAt(pos, Vector3.new(0, Layout.GroundY, 0))
end

-- Nids : 5 colonnes x 4 rangées, remplis de l'arrière (plus sûr) vers l'avant.
Layout.Nests = {} :: { Vector3 }
do
	local rows = { 34, 14, -6, -26 }
	local cols = { -36, -18, 0, 18, 36 }
	-- ordre : centre d'abord, puis vers l'extérieur
	local colOrder = { 3, 2, 4, 1, 5 }
	for _, z in rows do
		for _, c in colOrder do
			table.insert(Layout.Nests, Vector3.new(cols[c], 0, z))
		end
	end
end

Layout.Collector = Vector3.new(0, 0, 50)
Layout.LockButton = Vector3.new(-30, 0, 50)
Layout.PersonalPad = Vector3.new(30, 0, 50)
Layout.Spawn = Vector3.new(0, 3, 43)
Layout.Gate = Vector3.new(0, 0, -Layout.PlotDepth / 2)
Layout.Sign = Vector3.new(0, 0, -Layout.PlotDepth / 2 - 4)
Layout.RampagePortal = Vector3.new(-40, 0, -46) -- portail RAMPAGE (avant-gauche, hors de la cour des nids)

-- Plateformes des météores dans le cratère.
function Layout.MeteorPad(i: number, count: number): Vector3
	local angle = (i - 0.5) / count * math.pi * 2
	return Vector3.new(math.sin(angle) * 38, Layout.GroundY, math.cos(angle) * 38)
end

-- Vrai si la position monde est sur l'île (rectangle local, marge incluse).
function Layout.InPlot(plotCf: CFrame, worldPos: Vector3, margin: number?): boolean
	local p = plotCf:PointToObjectSpace(worldPos)
	local m = margin or 0
	return math.abs(p.X) <= Layout.PlotWidth / 2 + m and math.abs(p.Z) <= Layout.PlotDepth / 2 + m and p.Y > -10 and p.Y < 160
end

return Layout
