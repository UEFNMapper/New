--!strict
--[[
	Shell : la coque de la tour PC (Workspace.Tower.Shell, Model persistant), façon boîtier haut de
	gamme vu de l'extérieur comme de l'intérieur. Rien ne dépasse de plus d'un stud dans le volume
	intérieur (X, Z ∈ [-132, 132], construit par les mondes) : tout est sur ou devant les parois.
	- Côté +X : panneau en verre trempé (bord sérigraphié noir), cadre alu, vis moletées, cache
	  d'alimentation en bas (logo, ouïes, liseré RGB), rails lumineux aux planchers des mondes
	- Façade (-Z) : face mesh (treillis en losanges) devant 3 ventilateurs d'admission RGB, bandeau
	  haut avec I/O (bouton d'alimentation à LED, reset, USB, jacks) et logo, bandeau bas (écran de
	  l'app posé par Lobby, plaque de marque), porte d'entrée du parcours laissée libre
	- Dessus : 2 ventilateurs d'extraction sous un filtre à poussière
	- Arrière : plaque d'I/O de la carte mère, ventilateur d'extraction, équerres PCIe (carte
	  graphique), ouïes, alimentation (grille, prise secteur, interrupteur)
	- Côté -X : panneau acier, ouïes d'alimentation, logo en relief ; passe-câbles en caoutchouc sur
	  sa face intérieure (visibles à travers la vitre) ; 4 pieds
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local Common = require(script.Parent.Common)
local RoomProps = require(script.Parent.RoomProps)

local Shell = {}

local INNER, WALL, TOP = Common.INNER, Common.WALL, Common.TOP
local UP = Common.UP
local C = Common.C
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local hex = Common.Hex
local worldBase = Common.WorldBase

local APP_GLOW = Color3.fromHex(Branding.PartnerApp.Accent):Lerp(C.White, 0.25)
local STEEL = Color3.fromRGB(30, 33, 42) -- tôle peinte noire
local GUNMETAL = Color3.fromRGB(44, 47, 58) -- cadre de façade
local MESH = Color3.fromRGB(70, 74, 88)

-- Néon piloté par le client TowerGlow (la tour s'allume monde par monde, visible du lobby) :
-- tag ShellLight + attribut World (1..7 = bande du monde, 0 = toute la tour). Split = bande
-- verticale que le client découpe par monde. Remplace RgbStrip (un seul pilote par néon).
local function shellLight(part: BasePart, world: number, split: boolean?)
	part:RemoveTag("RgbStrip")
	part:AddTag("ShellLight")
	part:SetAttribute("World", world)
	if split then
		part:SetAttribute("Split", true)
	end
end

-- Tag ShellLight sur les segments de l'anneau RGB d'un ventilateur (RoomProps.CaseFan).
local function fanLight(fan: Model, world: number)
	for _, d in fan:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "FanRgb" then
			shellLight(d, world)
		end
	end
end

-- Treillis en losanges dans le plan (X, Y) de `cf` (centre du rectangle w × h), barres en Z = 0.
local function lattice(parent: Instance, cf: CFrame, w: number, h: number, spacing: number, bar: number, color: Color3)
	local model = Build.Model("Mesh", parent)
	local step = spacing * math.sqrt(2)
	for _, sign in { 1, -1 } do
		-- Droites y = sign * x + c, découpées au rectangle [-w/2, w/2] × [-h/2, h/2]
		local c = -(w + h) / 2 + step / 2
		while c < (w + h) / 2 do
			local points = {}
			local function add(x: number, y: number)
				if math.abs(x) <= w / 2 + 1e-6 and math.abs(y) <= h / 2 + 1e-6 then
					table.insert(points, Vector3.new(x, y, 0))
				end
			end
			add(-w / 2, sign * (-w / 2) + c)
			add(w / 2, sign * (w / 2) + c)
			add(sign * (-h / 2 - c), -h / 2)
			add(sign * (h / 2 - c), h / 2)
			if #points >= 2 then
				local a, b = points[1], points[1]
				for _, p in points do
					if (p - a).Magnitude > (b - a).Magnitude then
						b = p
					end
				end
				local length = (b - a).Magnitude
				if length > spacing * 0.5 then
					local dir = (b - a).Unit
					local barCf = CFrame.fromMatrix((a + b) / 2, dir, Vector3.zAxis:Cross(dir))
					Box(model, "MeshBar", Vector3.new(length, bar, bar * 0.7), cf * barCf, color, METAL)
				end
			end
			c += step
		end
	end
	return model
end

-- Repère sur la face +Z (arrière) : x, y monde, LookVector = +Z.
local function rearCf(x: number, y: number, dz: number): CFrame
	return CFrame.fromMatrix(Vector3.new(x, y, INNER + WALL + dz), -Vector3.xAxis, UP)
end

-- Repère sur la façade (-Z) : LookVector = -Z (vers le lobby).
local function frontCf(x: number, y: number, dz: number): CFrame
	return CFrame.new(x, y, -(INNER + WALL) - dz)
end

function Shell.Build(tower: Folder)
	local shell = Build.Model("Shell", tower)
	shell.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local outer = INNER + WALL
	local h = TOP
	local function wall(name: string, size: Vector3, position: Vector3, color: Color3?, material: Enum.Material?): Part
		return Build.Part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(position),
			Color = color or STEEL,
			Material = material or METAL,
			CastShadow = false,
			Parent = shell,
		})
	end

	------------------------------------------------------------------------------
	-- Parois (positions inchangées) : façade percée de la porte, arrière, côté -X, dessus
	------------------------------------------------------------------------------
	local zc = -(INNER + WALL / 2)
	local doorX0, doorX1 = Common.EntranceDoor()
	local doorTop = 8
	wall("Front", Vector3.new(outer - doorX1, h, WALL), Vector3.new((doorX1 + outer) / 2, h / 2, zc))
	wall("Front", Vector3.new(doorX0 + outer, h, WALL), Vector3.new((-outer + doorX0) / 2, h / 2, zc))
	wall(
		"Front",
		Vector3.new(doorX1 - doorX0, h - doorTop, WALL),
		Vector3.new((doorX0 + doorX1) / 2, (h + doorTop) / 2, zc)
	)
	wall("Back", Vector3.new(outer * 2, h, WALL), Vector3.new(0, h / 2, INNER + WALL / 2))
	wall("Left", Vector3.new(WALL, h, INNER * 2), Vector3.new(-(INNER + WALL / 2), h / 2, 0))
	wall("Top", Vector3.new(outer * 2, 6, outer * 2), Vector3.new(0, h + 3, 0))

	------------------------------------------------------------------------------
	-- Côté +X : verre trempé, cadre, vis moletées, cache d'alimentation
	------------------------------------------------------------------------------
	local shroudTop = 36
	local glassH = h - 6 - shroudTop
	local glass = wall(
		"SideGlass",
		Vector3.new(2, glassH, INNER * 2),
		Vector3.new(INNER + 1, shroudTop + glassH / 2, 0),
		Color3.fromRGB(170, 190, 220),
		Enum.Material.Glass
	)
	glass.Transparency = 0.72
	-- Bord sérigraphié noir (sur la face extérieure du verre)
	local silk = Color3.fromRGB(14, 14, 18)
	for _, band in
		{
			{ shroudTop + 5, 10, 0, 248 },
			{ h - 11, 10, 0, 248 },
			{ shroudTop + glassH / 2, glassH, -119, 10 },
			{ shroudTop + glassH / 2, glassH, 119, 10 },
		}
	do
		Box(shell, "GlassSilk", Vector3.new(0.4, band[2], band[4]), CFrame.new(INNER + 2.2, band[1], band[3]), silk)
	end
	-- Cadre alu : montants avant/arrière, traverse haute
	for _, z in { -128, 128 } do
		wall("GlassFrame", Vector3.new(4, h - shroudTop, 8), Vector3.new(INNER + 4, (h + shroudTop) / 2, z), C.Aluminum)
	end
	wall("GlassFrame", Vector3.new(WALL, 6, INNER * 2), Vector3.new(INNER + WALL / 2, h - 3, 0), C.Aluminum)
	for _, y in { shroudTop + 24, (h + shroudTop) / 2, h - 30 } do
		for _, z in { -128, 128 } do
			RoomProps.Thumbscrew(shell, CFrame.new(outer, y, z), 7)
		end
	end
	-- Cache d'alimentation (bas du côté vitré) : logo, ouïes, liseré RGB
	wall(
		"PsuShroud",
		Vector3.new(WALL, shroudTop, INNER * 2),
		Vector3.new(INNER + WALL / 2, shroudTop / 2, 0),
		GUNMETAL
	)
	local shroudLogo = Box(
		shell,
		"ShroudLogo",
		Vector3.new(130, 20, 0.2),
		Common.Facing(Vector3.new(outer + 0.2, shroudTop / 2, -40), Vector3.xAxis),
		C.White
	)
	shroudLogo.Transparency = 1
	RoomProps.Print(shroudLogo, Branding.GameName, C.White, Enum.NormalId.Front, Enum.Font.GothamBlack, 6)
	for i = 0, 5 do
		Box(shell, "ShroudVent", Vector3.new(0.4, 18, 4), CFrame.new(outer + 0.1, shroudTop / 2, 50 + i * 12), silk)
	end
	local shroudRgb = Build.Neon({
		Name = "ShroudRgb",
		Size = Vector3.new(0.6, 1, INNER * 2 - 16),
		CFrame = CFrame.new(outer + 0.3, shroudTop - 1.5, 0),
		Color = APP_GLOW,
		Parent = shell,
	})
	shellLight(shroudRgb, 1)
	-- Rails lumineux aux planchers des mondes (vus à travers la vitre)
	for w = 2, Tower.WORLD_COUNT do
		local y = worldBase(w)
		Box(
			shell,
			"GlassRail",
			Vector3.new(1.2, 2.4, INNER * 2 - 16),
			CFrame.new(INNER + 2.8, y - 1, 0),
			C.Aluminum,
			METAL
		)
		local rail = Build.Neon({
			Name = "RgbRail",
			Size = Vector3.new(0.4, 0.8, INNER * 2 - 16),
			CFrame = CFrame.new(INNER + 3.6, y - 1, 0),
			Color = hex(Tower.Worlds[w].Primary),
			Parent = shell,
		})
		shellLight(rail, w)
	end

	------------------------------------------------------------------------------
	-- Façade : face mesh, ventilateurs d'admission, bandeaux, I/O
	------------------------------------------------------------------------------
	local panelDepth = 5
	local pz = -(outer + panelDepth / 2) -- milieu de l'épaisseur de la face
	local meshBottom, meshTop = 96, 690
	local function panel(name: string, x0: number, x1: number, y0: number, y1: number)
		local part = wall(
			name,
			Vector3.new(x1 - x0, y1 - y0, panelDepth),
			Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, pz),
			GUNMETAL
		)
		part.CastShadow = true
	end
	panel("FrontBorder", -outer, doorX0, 0, h)
	panel("FrontBorder", INNER, outer, 0, h)
	panel("FrontBottom", doorX0, INNER, doorTop, meshBottom)
	panel("FrontBottom", doorX1, INNER, 0, doorTop)
	panel("FrontTop", doorX0, INNER, meshTop, h)
	-- Ventilateurs derrière le treillis (moyeux tournés par le client)
	for i, y in { 200, 393, 586 } do
		local fanCf = CFrame.fromMatrix(Vector3.new(0, y, -outer), -Vector3.zAxis, UP)
		fanLight(RoomProps.CaseFan(shell, fanCf, 170, hex(Tower.Worlds[i * 2].Primary), 1.4), i * 2)
	end
	lattice(
		shell,
		CFrame.new(0, (meshBottom + meshTop) / 2, -(outer + panelDepth) + 0.4),
		INNER * 2,
		meshTop - meshBottom,
		13,
		1.3,
		MESH
	)
	for _, x in { doorX0 + 0.8, INNER - 0.8 } do
		local strip = Build.Neon({
			Name = "FrontStrip",
			Size = Vector3.new(0.8, meshTop - meshBottom, 0.6),
			CFrame = CFrame.new(x, (meshBottom + meshTop) / 2, -(outer + panelDepth) + 0.3),
			Color = APP_GLOW,
			Parent = shell,
		})
		shellLight(strip, 0, true) -- jauge verticale : un morceau par monde (côté client)
	end
	for _, y in { meshBottom + 0.8, meshTop - 0.8 } do
		local strip = Build.Neon({
			Name = "FrontStrip",
			Size = Vector3.new(INNER * 2, 0.8, 0.6),
			CFrame = CFrame.new(0, y, -(outer + panelDepth) + 0.3),
			Color = APP_GLOW,
			Parent = shell,
		})
		shellLight(strip, math.clamp(math.floor(y / Common.BAND) + 1, 1, Tower.WORLD_COUNT))
	end
	-- Bandeau haut : logo, bouton d'alimentation à LED, reset, USB, jacks
	local ioY = (meshTop + h) / 2
	local logo = Box(shell, "FrontLogo", Vector3.new(130, 26, 0.2), frontCf(-60, ioY, panelDepth + 0.2), C.White)
	logo.Transparency = 1
	RoomProps.Print(logo, Branding.GameName, C.White, Enum.NormalId.Front, Enum.Font.GothamBlack, 6)
	local power = frontCf(96, ioY, panelDepth) * CFrame.Angles(0, math.pi / 2, 0) -- axe X local = -Z monde
	Rod(shell, "PowerButton", power * CFrame.new(1, 0, 0), 2, 20, C.MetalLight, METAL)
	local powerRing =
		Props.Ring(shell, "PowerRing", power * CFrame.new(2.2, 0, 0), 12, 1.4, 0.6, 16, C.Cyan, Enum.Material.Neon)
	for _, segment in powerRing do
		shellLight(segment, 0) -- bouton d'alimentation : l'état de toute la tour
	end
	local powerIcon = Box(
		shell,
		"PowerIcon",
		Vector3.new(1.6, 7, 0.4),
		frontCf(96, ioY + 2, panelDepth + 2.2),
		C.Cyan,
		Enum.Material.Neon
	)
	shellLight(powerIcon, 0)
	Rod(
		shell,
		"ResetButton",
		frontCf(122, ioY, panelDepth) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0.8, 0, 0),
		1.6,
		7,
		C.MetalLight,
		METAL
	)
	for _, x in { 20, 36 } do
		Box(shell, "UsbPort", Vector3.new(12, 5, 1), frontCf(x, ioY, panelDepth + 0.3), C.Black)
		Box(
			shell,
			"UsbTongue",
			Vector3.new(10, 1.6, 1),
			frontCf(x, ioY + 0.8, panelDepth + 0.5),
			Color3.fromRGB(40, 110, 230)
		)
	end
	Box(shell, "UsbCPort", Vector3.new(8, 3, 1), frontCf(52, ioY, panelDepth + 0.3), C.Black)
	for i, x in { 64, 74 } do
		Rod(
			shell,
			"AudioJack",
			frontCf(x, ioY, panelDepth) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0.4, 0, 0),
			1,
			5,
			if i == 1 then C.Black else C.MetalDark
		)
	end
	-- Bandeau bas : plaque de marque (l'écran de l'app est posé par le lobby à gauche)
	local badge = Box(shell, "FrontBadge", Vector3.new(76, 22, 0.2), frontCf(88, 56, panelDepth + 0.2), C.White)
	badge.Transparency = 1
	Props.Sign(badge, "ANGA TOWER", "Édition Anti-Lag", C.White, APP_GLOW)
	for i = 0, 2 do
		Build.Neon({
			Name = "StatusLed",
			Size = Vector3.new(3, 1.2, 0.4),
			CFrame = frontCf(66 + i * 8, 30, panelDepth + 0.2),
			Color = if i == 0 then C.Cyan elseif i == 1 then APP_GLOW else Color3.fromRGB(104, 224, 140),
			Parent = shell,
		})
	end
	-- Pieds (patins caoutchouc aux 4 coins, légèrement en saillie)
	for _, x in { -(outer - 2.5), outer - 2.5 } do
		for _, z in { -(outer + panelDepth - 3), outer - 2 } do
			Box(
				shell,
				"Foot",
				Vector3.new(7, 4, 10),
				CFrame.new(x, 2, z),
				Color3.fromRGB(20, 20, 24),
				Enum.Material.Rubber
			)
			Box(shell, "FootTrim", Vector3.new(7.4, 0.6, 10.4), CFrame.new(x, 4.2, z), C.Aluminum, METAL)
		end
	end
	-- Halo des ventilateurs de façade
	for _, y in { 230, 520 } do
		Common.Lamp(shell, Vector3.new(0, y, -(outer + 30)), APP_GLOW, 1.2, 60)
	end

	------------------------------------------------------------------------------
	-- Dessus : 2 ventilateurs d'extraction sous un filtre à poussière
	------------------------------------------------------------------------------
	local filterX, filterW, filterD = 24, 136, 264
	for _, z in { -62, 62 } do
		local topFan = RoomProps.CaseFan(
			shell,
			CFrame.fromMatrix(Vector3.new(filterX, h + 6, z), UP, Vector3.zAxis),
			112,
			C.Violet,
			1.8
		)
		fanLight(topFan, Tower.WORLD_COUNT)
	end
	lattice(
		shell,
		CFrame.fromMatrix(Vector3.new(filterX, h + 10.6, 0), Vector3.xAxis, -Vector3.zAxis),
		filterW,
		filterD,
		11,
		1,
		MESH
	)
	for _, edge in
		{
			{ 0, filterD / 2, filterW + 4, 4 },
			{ 0, -filterD / 2, filterW + 4, 4 },
			{ filterW / 2, 0, 4, filterD },
			{ -filterW / 2, 0, 4, filterD },
		}
	do
		Box(
			shell,
			"FilterFrame",
			Vector3.new(edge[3], 1.6, edge[4]),
			CFrame.new(filterX + edge[1], h + 10.6, edge[2]),
			GUNMETAL,
			METAL
		)
	end

	------------------------------------------------------------------------------
	-- Arrière : I/O de la carte mère, ventilateur, équerres PCIe, alimentation
	------------------------------------------------------------------------------
	local ioShield = rearCf(-104, 628, 0.5)
	Box(shell, "IoShield", Vector3.new(40, 140, 1), ioShield, C.Aluminum, METAL)
	local ports: { { any } } = {
		{ 690, 12, 4, Color3.fromRGB(40, 110, 230) },
		{ 682, 12, 4, Color3.fromRGB(40, 110, 230) },
		{ 672, 12, 4, C.Black },
		{ 664, 12, 4, C.Black },
		{ 648, 13, 10, C.Black },
		{ 630, 13, 4.5, C.Black },
		{ 620, 13, 4.5, C.Black },
	}
	for _, port in ports do
		Box(shell, "IoPort", Vector3.new(port[2], port[3], 1), rearCf(-104, port[1], 1.3), port[4])
	end
	Box(
		shell,
		"LanLed",
		Vector3.new(2, 1.4, 0.4),
		rearCf(-96, 654, 1.9),
		Color3.fromRGB(104, 224, 140),
		Enum.Material.Neon
	)
	Box(
		shell,
		"LanLed",
		Vector3.new(2, 1.4, 0.4),
		rearCf(-112, 654, 1.9),
		Color3.fromRGB(255, 180, 60),
		Enum.Material.Neon
	)
	for i, color in { Color3.fromRGB(255, 140, 190), Color3.fromRGB(104, 224, 140), Color3.fromRGB(80, 160, 255) } do
		Rod(shell, "AudioJack", rearCf(-104, 600 - i * 9, 1) * CFrame.Angles(0, math.pi / 2, 0), 1.2, 5.5, color)
	end
	local rearFan =
		RoomProps.CaseFan(shell, CFrame.fromMatrix(Vector3.new(4, 626, outer), Vector3.zAxis, UP), 110, C.Violet, 1.6)
	fanLight(rearFan, Tower.WORLD_COUNT)
	lattice(shell, rearCf(4, 626, 4.6), 112, 112, 9, 0.9, MESH)
	-- Équerres PCIe : carte graphique (2 emplacements, sorties vidéo) puis caches ventilés
	for slot = 0, 6 do
		local y = 540 - slot * 32
		Rod(shell, "SlotScrew", rearCf(-124, y, 1) * CFrame.Angles(0, math.pi / 2, 0), 2, 5, C.Nickel)
		if slot == 0 then
			Box(shell, "GpuBracket", Vector3.new(86, 56, 1), rearCf(-76, y - 14, 0.6), C.MetalLight, METAL)
			for k = 0, 3 do
				Box(shell, "GpuPort", Vector3.new(11, 5, 1), rearCf(-104 + k * 16, y - 20, 1.3), C.Black)
			end
		elseif slot >= 2 then
			Box(shell, "SlotCover", Vector3.new(86, 24, 1), rearCf(-76, y, 0.6), C.MetalDark, METAL)
			Box(shell, "SlotVent", Vector3.new(66, 4, 0.4), rearCf(-76, y, 1.3), C.Black)
		end
	end
	for i = 0, 11 do
		Box(shell, "RearVent", Vector3.new(56, 3, 0.4), rearCf(92, 300 + i * 20, 0.2), C.Black)
	end
	-- Alimentation : plaque, grille du ventilateur, prise secteur, interrupteur, étiquette
	local psu = rearCf(-44, 56, 0.6)
	Box(shell, "PsuBack", Vector3.new(172, 90, 1.2), psu, C.Black, METAL)
	Rod(
		shell,
		"PsuFanHole",
		rearCf(-90, 56, 1.1) * CFrame.Angles(0, math.pi / 2, 0),
		0.4,
		70,
		Color3.fromRGB(12, 12, 16)
	)
	Props.Ring(
		shell,
		"PsuGrille",
		rearCf(-90, 56, 1.4) * CFrame.Angles(0, math.pi / 2, 0),
		34,
		2,
		1,
		16,
		C.MetalDark,
		METAL
	)
	for k = -2, 2 do
		Box(
			shell,
			"PsuGrilleBar",
			Vector3.new(66 - math.abs(k) * 12, 1.4, 0.8),
			rearCf(-90, 56 + k * 12, 1.5),
			C.MetalDark,
			METAL
		)
	end
	Box(shell, "PsuSocket", Vector3.new(16, 12, 3), rearCf(15, 70, 2), C.Black)
	Box(
		shell,
		"PsuSwitch",
		Vector3.new(8, 12, 2),
		rearCf(15, 44, 1.6),
		Color3.fromRGB(255, 170, 60),
		Enum.Material.Neon
	)
	local psuLabel = Box(shell, "PsuLabel", Vector3.new(40, 16, 0.2), rearCf(-24, 40, 1.4), C.Silk)
	psuLabel.Transparency = 1
	RoomProps.Print(psuLabel, "ANGA POWER 1200W", C.Silk, Enum.NormalId.Front, Enum.Font.GothamBold, 8)
	for _, x in { -(INNER - 4), INNER - 4 } do
		for _, y in { 30, h - 30 } do
			RoomProps.Thumbscrew(shell, CFrame.fromMatrix(Vector3.new(x, y, outer), Vector3.zAxis, UP), 6)
		end
	end

	------------------------------------------------------------------------------
	-- Côté -X : ouïes d'alimentation, logo en relief ; passe-câbles à l'intérieur
	------------------------------------------------------------------------------
	for i = 0, 7 do
		Box(shell, "SideVent", Vector3.new(0.4, 3, 96), CFrame.new(-outer - 0.1, 16 + i * 8, 70), C.Black)
	end
	local sideLogo = Box(
		shell,
		"SideLogo",
		Vector3.new(220, 44, 0.2),
		Common.Facing(Vector3.new(-outer - 0.2, 420, 0), -Vector3.xAxis),
		C.White
	)
	sideLogo.Transparency = 1
	RoomProps.Print(
		sideLogo,
		Branding.GameName,
		Color3.fromRGB(70, 76, 92),
		Enum.NormalId.Front,
		Enum.Font.GothamBlack,
		2
	)
	for w = 1, Tower.WORLD_COUNT do
		local y = worldBase(w) + 52
		Box(
			shell,
			"Grommet",
			Vector3.new(0.8, 36, 16),
			CFrame.new(-INNER + 0.4, y, -112),
			Color3.fromRGB(16, 16, 20),
			Enum.Material.Rubber
		)
		Box(shell, "GrommetSlit", Vector3.new(1, 28, 5), CFrame.new(-INNER + 0.5, y, -112), Color3.fromRGB(4, 4, 6))
	end
end

return table.freeze(Shell)
