--!strict
--[[
	Lobby (Salle de démarrage) : le bureau d'Anga devant la tour (Workspace.Tower.Lobby, Model persistant).
	LobbySpawn, AppScreen, LeaderboardScreen×3 (attribut Board), TitleHologram, bornes Shop / Arcade /
	Daily (prompt Action), AngaSpot, portique « JOUER » + checkpoint 0, décor du bureau, et la maison de
	départ (Lobby.Start) dont le toit est l'entrée du monde 1.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local Common = require(script.Parent.Common)

local Lobby = {}

local INNER, WALL = Common.INNER, Common.WALL
local C = Common.C
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local VERTICAL = Common.VERTICAL
local SAFE = Common.Colors.Safe
local SPRING = Common.Colors.Spring
local facing = Common.Facing
local lamp = Common.Lamp

function Lobby.Build(tower: Folder)
	local lobby = Build.Model("Lobby", tower)
	lobby.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local padTop = 0.4

	-- Bureau (sol), tapis de souris RGB (zone du lobby), murets invisibles au bord du bureau
	Build.Part({
		Name = "Desk",
		Size = Vector3.new(640, 6, 700),
		CFrame = CFrame.new(0, -3, -110),
		Color = Color3.fromRGB(58, 44, 38),
		Material = Enum.Material.WoodPlanks,
		Parent = lobby,
	})
	Build.Part({
		Name = "MousePad",
		Size = Vector3.new(360, 0.4, 250),
		CFrame = CFrame.new(-40, padTop / 2, -290),
		Color = Color3.fromRGB(24, 26, 34),
		Material = Enum.Material.Fabric,
		Parent = lobby,
	})
	for _, edge in
		{ { 0, -125.2, 360.4, 0.6 }, { 0, 125.2, 360.4, 0.6 }, { -180.2, 0, 0.6, 250 }, { 180.2, 0, 0.6, 250 } }
	do
		Build.Neon({
			Name = "PadRgb",
			Size = Vector3.new(edge[3], 0.5, edge[4]),
			CFrame = CFrame.new(-40 + edge[1], padTop, -290 + edge[2]),
			Color = C.Violet,
			Tags = { "RgbStrip" },
			Parent = lobby,
		})
	end
	for _, b in { { 0, 240, 640, 2 }, { 0, -460, 640, 2 }, { -320, -110, 2, 700 }, { 320, -110, 2, 700 } } do
		local barrier = Build.Part({
			Name = "DeskEdge",
			Size = Vector3.new(b[3], 60, b[4]),
			CFrame = CFrame.new(b[1], 30, b[2]),
			Transparency = 1,
			Parent = lobby,
		})
		barrier.CanQuery = false
	end

	-- Spawn : face à la tour, entre l'écran géant et la porte du parcours
	local spawnPos = Vector3.new(-40, padTop + 0.5, -290)
	local spawnLook = Vector3.new(-28, 0, -182) - Vector3.new(-40, 0, -290)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = facing(spawnPos, spawnLook)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = C.MetalDark
	spawn.Material = METAL
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby
	Props.Ring(lobby, "SpawnRing", spawn.CFrame * CFrame.new(0, 0.6, 0) * VERTICAL, 6.2, 0.5, 0.3, 16, C.Cyan, NEON)

	-- Écran géant de l'app AngAInOne (face avant dessinée par le client), tourné vers le spawn
	local screenPos = Vector3.new(80, 42, -222)
	local screenCf = facing(screenPos, spawnPos - screenPos)
	Build.Part({
		Name = "MonitorBezel",
		Size = Vector3.new(116, 68, 3),
		CFrame = screenCf * CFrame.new(0, 0, 1.8),
		Color = C.Black,
		Material = METAL,
		Parent = lobby,
	})
	local appScreen = Build.Decor({
		Name = "AppScreen",
		Size = Vector3.new(110, 62, 0.4),
		CFrame = screenCf,
		Color = Color3.fromHex("202020"),
		Material = SMOOTH,
		Tags = { "AppScreen" },
		Parent = lobby,
	})
	Build.PointLight(appScreen, C.Violet, 1.2, 70)
	Common.CountLight()
	Build.Neon({
		Name = "Ambilight",
		Size = Vector3.new(114, 66, 0.4),
		CFrame = screenCf * CFrame.new(0, 0, 3.6),
		Color = C.Violet,
		Transparency = 0.2,
		Tags = { "RgbStrip" },
		Parent = lobby,
	})
	Build.Part({
		Name = "MonitorNeck",
		Size = Vector3.new(10, 12, 4),
		CFrame = screenCf * CFrame.new(0, -38, 6),
		Color = C.MetalLight,
		Material = METAL,
		Parent = lobby,
	})
	Build.Part({
		Name = "MonitorFoot",
		Size = Vector3.new(44, 1.6, 26),
		CFrame = facing(Vector3.new(screenPos.X, 0.8, screenPos.Z), spawnPos - screenPos) * CFrame.new(0, 0, 10),
		Color = C.MetalLight,
		Material = METAL,
		Parent = lobby,
	})

	-- Hologramme du titre, sur la façade au-dessus de la porte
	local title = Build.Decor({
		Name = "TitleHologram",
		Size = Vector3.new(80, 20, 0.2),
		CFrame = facing(Vector3.new(-60, 52, -150), spawnPos - Vector3.new(-60, 52, -150)),
		Transparency = 1,
		Tags = { "TitleHologram" },
		Parent = lobby,
	})
	Build.PointLight(title, C.Violet, 1.6, 60)
	Common.CountLight()

	-- Classements (face avant dessinée par le client), côté droit du spawn
	for i, board in { "Wins", "BestTime", "Stage" } do
		local position = Vector3.new(-185, 20, -335 + i * 38)
		local cf = facing(position, spawnPos - position)
		Build.Part({
			Name = `{board}Frame`,
			Size = Vector3.new(32, 22, 1.4),
			CFrame = cf * CFrame.new(0, 0, 1),
			Color = C.MetalDark,
			Material = METAL,
			Parent = lobby,
		})
		local screen = Build.Decor({
			Name = `{board}Board`,
			Size = Vector3.new(30, 20, 0.3),
			CFrame = cf,
			Color = C.Bg,
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			Tags = { "LeaderboardScreen" },
			Parent = lobby,
		})
		screen:SetAttribute("Board", board)
		Build.Part({
			Name = `{board}Leg`,
			Size = Vector3.new(3, 9, 3),
			CFrame = cf * CFrame.new(0, -14.5, 1.2),
			Color = C.MetalLight,
			Material = METAL,
			Parent = lobby,
		})
		Build.Neon({
			Name = `{board}Trim`,
			Size = Vector3.new(32, 0.5, 0.5),
			CFrame = cf * CFrame.new(0, -11.2, 0),
			Color = C.Cyan,
			Parent = lobby,
		})
	end

	-- Bornes : boutique, arcade (mini-jeux), récompense du jour
	local kiosks = {
		{
			Action = "Shop",
			Text = "Boutique",
			Object = "Skins et effets",
			Color = C.Gold,
			At = Vector3.new(0, 0, -262),
		},
		{
			Action = "Arcade",
			Text = "Arcade",
			Object = "Mini-jeux antivirus",
			Color = C.Cyan,
			At = Vector3.new(8, 0, -298),
		},
		{
			Action = "Daily",
			Text = "Cadeau du jour",
			Object = "Récompenses",
			Color = SPRING,
			At = Vector3.new(-6, 0, -332),
		},
	}
	for _, kiosk in kiosks do
		local cf = facing(kiosk.At + Vector3.new(0, padTop, 0), spawnPos - kiosk.At)
		local model = Build.Model(`{kiosk.Action}Kiosk`, lobby)
		local stand = Build.Part({
			Name = "Stand",
			Size = Vector3.new(6, 5, 4),
			CFrame = cf * CFrame.new(0, 2.5, 0),
			Color = C.MetalDark,
			Material = METAL,
			Parent = model,
		})
		model.PrimaryPart = stand
		Box(
			model,
			"ScreenBack",
			Vector3.new(8, 6, 0.6),
			cf * CFrame.new(0, 8.4, 0.4) * CFrame.Angles(math.rad(-12), 0, 0),
			C.Black,
			METAL
		)
		local screen = Box(
			model,
			"Screen",
			Vector3.new(7.4, 5.4, 0.2),
			cf * CFrame.new(0, 8.4, 0) * CFrame.Angles(math.rad(-12), 0, 0),
			C.Bg
		)
		Props.Sign(screen, string.upper(kiosk.Text), kiosk.Object, kiosk.Color, C.White)
		Build.Neon({
			Name = "Trim",
			Size = Vector3.new(6.2, 0.4, 0.4),
			CFrame = cf * CFrame.new(0, 5.1, -2),
			Color = kiosk.Color,
			Parent = model,
		})
		Build.Prompt(stand, kiosk.Text, kiosk.Object, kiosk.Action, 12)
	end

	-- Emplacement de la mascotte Anga (le client l'affiche ici), à côté du spawn
	local angaPos = Vector3.new(-66, padTop + 3, -282)
	local anga = Build.Decor({
		Name = "AngaSpot",
		Size = Vector3.new(4, 6, 4),
		CFrame = facing(angaPos, spawnPos - angaPos),
		Transparency = 1,
		Parent = lobby,
	})
	anga.CanQuery = false
	Rod(lobby, "AngaPodium", CFrame.new(angaPos.X, padTop + 0.4, angaPos.Z) * VERTICAL, 0.8, 9, C.MetalDark)
	Props.Ring(
		lobby,
		"AngaRing",
		CFrame.new(angaPos.X, padTop + 0.9, angaPos.Z) * VERTICAL,
		4.4,
		0.4,
		0.3,
		14,
		C.Brand,
		NEON
	)

	-- Entrée du parcours : portique « JOUER » devant la porte, chemin lumineux depuis le spawn
	local doorX0, doorX1 = Common.EntranceDoor()
	local doorX = (doorX0 + doorX1) / 2
	local faceZ = -(INNER + WALL)
	for _, x in { doorX0 - 2, doorX1 + 2 } do
		Build.Part({
			Name = "PortalPillar",
			Size = Vector3.new(3, 16, 3),
			CFrame = CFrame.new(x, 8, faceZ - 3),
			Color = C.MetalDark,
			Material = METAL,
			Parent = lobby,
		})
		Build.Neon({
			Name = "PortalGlow",
			Size = Vector3.new(0.6, 15, 0.6),
			CFrame = CFrame.new(x + (if x < doorX then 1.6 else -1.6), 8, faceZ - 4.6),
			Color = SAFE,
			Parent = lobby,
		})
	end
	local lintel = Build.Part({
		Name = "PortalLintel",
		Size = Vector3.new(doorX1 - doorX0 + 7, 5, 3),
		CFrame = CFrame.new(doorX, 18.5, faceZ - 3),
		Color = C.Black,
		Material = METAL,
		Parent = lobby,
	})
	Props.Sign(lintel, "JOUER", "Grimpe la tour !", SAFE, C.White, Enum.NormalId.Front)
	lamp(lobby, Vector3.new(doorX, 12, faceZ - 12), SAFE, 1.4, 36)
	local padPos = Vector3.new(doorX, padTop, faceZ - 14)
	for i = 1, 5 do
		local t = i / 6
		local position = spawnPos:Lerp(padPos, t)
		Build.Neon({
			Name = "Chevron",
			Size = Vector3.new(7, 0.2, 1),
			CFrame = facing(Vector3.new(position.X, padTop + 0.1, position.Z), padPos - spawnPos),
			Color = SAFE,
			Transparency = 0.25,
			Parent = lobby,
		})
	end
	Common.CheckpointPad(0, Vector3.new(doorX, padTop + 0.6, faceZ - 14), Vector3.zAxis)

	-- Clavier géant (décor) derrière le spawn
	local keyboardCf = CFrame.new(-40, 0, -420)
	Build.Part({
		Name = "KeyboardBase",
		Size = Vector3.new(250, 5, 64),
		CFrame = keyboardCf * CFrame.new(0, 2.5, 0),
		Color = C.Black,
		Material = METAL,
		Parent = lobby,
	})
	Build.Neon({
		Name = "KeyboardGlow",
		Size = Vector3.new(252, 0.6, 66),
		CFrame = keyboardCf * CFrame.new(0, 0.4, 0),
		Color = C.Cyan,
		Transparency = 0.3,
		Tags = { "RgbStrip" },
		Parent = lobby,
	})
	for row = 0, 3 do
		for col = 0, 13 do
			local wide = row == 3 and col >= 4 and col <= 9
			if not (row == 3 and col > 4 and col <= 9) then
				Box(
					lobby,
					"Key",
					Vector3.new(if wide then 82 else 13, 3, 11),
					keyboardCf * CFrame.new(-110 + col * 17 + (if wide then 34.5 else 0), 6, -22 + row * 14.5),
					Color3.fromRGB(44, 46, 56)
				)
			end
		end
	end
	-- Souris géante (RGB), tasse de café, logo sérigraphié sur le tapis
	local mouseCf = CFrame.new(150, 0, -330) * CFrame.Angles(0, math.rad(-12), 0)
	Build.Part({
		Name = "MouseBody",
		Size = Vector3.new(26, 9, 40),
		CFrame = mouseCf * CFrame.new(0, 4.5, 0),
		Color = C.Black,
		Material = SMOOTH,
		Parent = lobby,
	})
	Rod(
		lobby,
		"MouseNose",
		mouseCf * CFrame.new(0, 4.5, -20) * CFrame.Angles(0, math.pi / 2, 0) * VERTICAL,
		26,
		9,
		C.Black
	)
	Rod(lobby, "MouseWheel", mouseCf * CFrame.new(0, 9.2, -12), 1.6, 5, C.MetalLight)
	Build.Neon({
		Name = "MouseRgb",
		Size = Vector3.new(26.4, 0.8, 40.4),
		CFrame = mouseCf * CFrame.new(0, 1.2, 0),
		Color = C.Violet,
		Tags = { "RgbStrip" },
		Parent = lobby,
	})
	Props.Cable(lobby, {
		(mouseCf * CFrame.new(0, 3, -24)).Position,
		(mouseCf * CFrame.new(10, 1.5, -70)).Position,
		Vector3.new(120, 1.5, -150),
	}, 1.2, C.Rubber)
	local mugPos = Vector3.new(-250, 0, -250)
	Build.Cylinder({
		Name = "Mug",
		Size = Vector3.new(34, 30, 30),
		CFrame = CFrame.new(mugPos + Vector3.new(0, 17, 0)) * VERTICAL,
		Color = C.White,
		Material = SMOOTH,
		Parent = lobby,
	})
	Rod(lobby, "Coffee", CFrame.new(mugPos + Vector3.new(0, 33.2, 0)) * VERTICAL, 0.6, 27, Color3.fromRGB(70, 42, 28))
	-- Anse : deux barreaux horizontaux + un montant (x, y, largeur, hauteur)
	for _, handle in { { 18, 26, 6, 3 }, { 18, 8, 6, 3 }, { 21.5, 17, 3, 21 } } do
		Box(
			lobby,
			"MugHandle",
			Vector3.new(handle[3], handle[4], 4),
			CFrame.new(mugPos + Vector3.new(handle[1], handle[2], 0)),
			C.White
		)
	end
	local mugLabel = Box(
		lobby,
		"MugLabel",
		Vector3.new(0.2, 12, 20),
		CFrame.new(mugPos + Vector3.new(15.1, 18, 0)) * CFrame.Angles(0, math.pi / 2, 0),
		C.Brand
	)
	mugLabel.Transparency = 1
	Props.Label(mugLabel, "ANGA", C.Brand, Enum.NormalId.Right, Enum.Font.GothamBlack)
	Props.Decal(
		lobby,
		"PadLogo",
		Vector3.new(120, 0.1, 24),
		facing(Vector3.new(-40, padTop + 0.06, -355), spawnLook) * CFrame.Angles(0, math.pi, 0),
		"ANGA TOWER",
		C.Violet,
		Enum.NormalId.Top,
		Enum.Font.GothamBlack
	)

	lamp(lobby, Vector3.new(-40, 40, -290), C.White, 1, 120)

	-- Maison de départ (coin 0) : de la porte de façade au toit = entrée du monde 1 (Common.EntryOf(1))
	local start = Build.Folder("Start", lobby)
	Common.House(Common.CornerFrame(0), 0.1, Common.ENTRY - 0.1, {
		Style = Common.Style(Tower.Worlds[1]),
		Parent = start,
	})
end

return table.freeze(Lobby)
