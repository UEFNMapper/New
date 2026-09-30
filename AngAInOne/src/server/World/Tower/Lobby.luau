--!strict
--[[
	Lobby : la chambre d'Anga (docs/SCENARIO.md §6), à l'échelle géante. Le joueur, miniaturisé,
	apparaît SUR LE BUREAU devant la tour PC (Workspace.Tower.Lobby, Model persistant).

	Contrat (lu par ProgressService, WorldFx, AppScreen, StreamMonitor) :
	- LobbySpawn (SpawnLocation), sur le tapis de souris XXL, devant le clavier ;
	- StreamMonitor : dalle de l'écran d'Anga (face avant dessinée par le client : « LIVE DANS
	  59:00 » + chat), tournée vers le spawn, à moins de 300 studs (le client ne met à jour que de près) ;
	- AppScreen : écran LCD intégré en bas de la façade de la tour (face avant dessinée par le client) ;
	- LeaderboardScreen ×3 (attribut Board = Wins / BestTime / Stage), TitleHologram, AngaSpot ;
	- bornes Shop / Arcade / Daily (ProximityPrompt, attribut Action) ;
	- le Miniaturiseur AngAInOne (portail de départ « JOUER ») autour du checkpoint 0, devant la porte
	  de la façade ; la maison de départ (Lobby.Start) monte jusqu'au toit = entrée du monde 1.

	Géométrie (bureau à y = 0, tour centrée en X = Z = 0, façade vers -Z, vitre côté +X) :
	- le setup du streamer (écran, clavier, souris, micro, casque, Stream Deck) est côté vitre de la tour
	  (+X), tourné de 60° vers le spawn : de là, on voit l'écran en entier à côté de la tour ;
	- la base (bornes, classements) est entre le spawn et le Miniaturiseur (côté -X), Anga devant le spawn ;
	- la chaise, les murs, la fenêtre au coucher de soleil et les posters habillent la chambre autour.
	Toute la base est accessible à pied depuis le spawn (tests/tower.spec.luau).

	Vrais modèles 3D (ModelLibrary, assets/models) : tant qu'ils ne sont pas importés, tout est
	construit en primitives, exactement comme avant. Une fois importés :
	- décor pur (fauteuil, ring light, enceintes, plante) : `Place`, primitives en secours ;
	- objets solides ou à contrat (clavier, souris, écran, micro, casque, tasse, lampe, bornes Shop /
	  Arcade, capsule du Miniaturiseur) : `Dress` → les primitives restent (invisibles) pour la
	  collision, les touches praticables, les prompts (attribut Action) et les tags ; le modèle les habille.
	- StreamMonitor et l'écran des bornes restent des dalles primitives (hôtes des SurfaceGui),
	  recalées sur la pièce `Screen` du modèle (`FitScreen`). Pad 0 et LobbySpawn ne changent jamais.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local ModelLibrary = require(script.Parent.Parent.ModelLibrary)
local Common = require(script.Parent.Common)
local RoomProps = require(script.Parent.RoomProps)

local Lobby = {}

local INNER, WALL = Common.INNER, Common.WALL
local C = Common.C
local UP = Common.UP
local Box, Rod = Props.Box, Props.Rod
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local VERTICAL = Common.VERTICAL
local SAFE = Common.Colors.Safe
local SPRING = Common.Colors.Spring
local facing = Common.Facing
local lamp = Common.Lamp

local APP_ACCENT = Color3.fromHex(Branding.PartnerApp.Accent) -- violet de l'app AngAInOne
local APP_GLOW = APP_ACCENT:Lerp(C.White, 0.25)
local ORIGIN = Vector3.zero -- `Anchor` des modèles : leur origine d'export (centre de la base dans Blender)

------------------------------------------------------------------------------------
-- Repères de la scène
------------------------------------------------------------------------------------

local FACE_Z = -(INNER + WALL) -- façade de la tour (la face mesh dépasse jusqu'à -143)
local PANEL_Z = FACE_Z - 5 -- devant de la face mesh (voir Shell)
local MAT_TOP = 0.6

-- Spawn : sur le tapis XXL, devant le clavier, à ~180 studs du checkpoint 0
local SPAWN = Vector3.new(-30, MAT_TOP + 0.5, -290)

-- Setup du streamer : écran en M, tourné de 60° vers le spawn (L = vers le joueur qui tape)
local MONITOR_AT = Vector3.new(230, 0, -260)
local SETUP_ANGLE = math.rad(60)
local L = Vector3.new(-math.sin(SETUP_ANGLE), 0, -math.cos(SETUP_ANGLE))
local R = L:Cross(UP) -- droite de l'écran vue de face (= gauche du joueur qui tape)
local SCREEN_W, SCREEN_H, SCREEN_BOTTOM = 240, 135, 70
local KEYBOARD_AT = MONITOR_AT + L * 130
-- Dessus moyen des touches praticables (boîtier 5 + touche 4,4 + relief de rangée 0..0,8)
local KEY_TOP = RoomProps.KEYBOARD_SIZE.Y + 4.8
local MAT_W, MAT_D = 640, 300 -- tapis XXL (le long de R, le long de L), centré sur le clavier + 60 R + 10 L

-- Bureau (dessus à y = 0) et chambre
local DESK_X0, DESK_X1, DESK_Z0, DESK_Z1 = -760, 900, -660, 330
local FLOOR_Y = -900
local ROOM_X0, ROOM_X1, ROOM_Z0, ROOM_Z1, CEILING_Y = -1500, 1600, -2100, 380, 1700

-- Repère « setup » : origine au pied de l'écran, u le long de L (vers le joueur), v le long de R.
local function setup(u: number, y: number, v: number): Vector3
	return MONITOR_AT + L * u + R * v + Vector3.new(0, y, 0)
end

------------------------------------------------------------------------------------
-- Chambre : bureau, sol, murs, plafond, fenêtre, posters, chaise
------------------------------------------------------------------------------------

-- Grande dalle de la pièce découpée en morceaux ≤ 2000 studs (limite des pièces Roblox).
local function slab(parent: Instance, name: string, a: Vector3, b: Vector3, color: Color3, material: Enum.Material)
	local lo = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local hi = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	local span = hi - lo
	local nx, ny, nz = math.ceil(span.X / 2000), math.ceil(span.Y / 2000), math.ceil(span.Z / 2000)
	local step = Vector3.new(span.X / nx, span.Y / ny, span.Z / nz)
	for i = 0, nx - 1 do
		for j = 0, ny - 1 do
			for k = 0, nz - 1 do
				local part = Build.Part({
					Name = name,
					Size = step,
					CFrame = CFrame.new(lo + step * Vector3.new(i + 0.5, j + 0.5, k + 0.5)),
					Color = color,
					Material = material,
					CastShadow = false, -- la chambre ne bloque pas le soleil : le bureau reste lumineux
					Parent = parent,
				})
				part.CanQuery = false
			end
		end
	end
end

local function buildRoom(lobby: Model)
	local room = Build.Folder("Room", lobby)
	local wallColor = Color3.fromRGB(78, 74, 118)
	-- Bureau (le sol du lobby), chant avec ruban LED, pieds
	local deskSize = Vector3.new(DESK_X1 - DESK_X0, 44, DESK_Z1 - DESK_Z0)
	local deskCenter = Vector3.new((DESK_X0 + DESK_X1) / 2, -22, (DESK_Z0 + DESK_Z1) / 2)
	Build.Part({
		Name = "Desk",
		Size = deskSize,
		CFrame = CFrame.new(deskCenter),
		Color = Color3.fromRGB(112, 78, 56),
		Material = Enum.Material.Wood,
		Parent = room,
	})
	Build.Neon({
		Name = "DeskLed",
		Size = Vector3.new(deskSize.X, 3, 0.6),
		CFrame = CFrame.new(deskCenter.X, -6, DESK_Z0 - 0.3),
		Color = APP_GLOW,
		Transparency = 0.1,
		Tags = { "RgbStrip" },
		Parent = room,
	})
	for _, x in { DESK_X0 + 60, DESK_X1 - 60 } do
		for _, z in { DESK_Z0 + 60, DESK_Z1 - 60 } do
			Box(
				room,
				"DeskLeg",
				Vector3.new(60, -44 - FLOOR_Y, 60),
				CFrame.new(x, (FLOOR_Y - 44) / 2, z),
				C.Black,
				METAL
			)
		end
	end
	-- Murets invisibles au bord du bureau (on ne tombe pas de 900 studs)
	local ex, ez = deskSize.X, deskSize.Z
	for _, b in
		{
			{ deskCenter.X, DESK_Z0 - 1, ex + 4, 2 },
			{ deskCenter.X, DESK_Z1 + 1, ex + 4, 2 },
			{ DESK_X0 - 1, deskCenter.Z, 2, ez + 4 },
			{ DESK_X1 + 1, deskCenter.Z, 2, ez + 4 },
		}
	do
		local barrier = Build.Part({
			Name = "DeskEdge",
			Size = Vector3.new(b[3], 120, b[4]),
			CFrame = CFrame.new(b[1], 60, b[2]),
			Transparency = 1,
			CastShadow = false,
			Parent = room,
		})
		barrier.CanQuery = false
	end

	-- Sol (parquet), tapis rond sous la chaise, murs, plafond
	slab(
		room,
		"RoomFloor",
		Vector3.new(ROOM_X0, FLOOR_Y - 20, ROOM_Z0),
		Vector3.new(ROOM_X1, FLOOR_Y, ROOM_Z1),
		Color3.fromRGB(150, 108, 76),
		Enum.Material.WoodPlanks
	)
	Rod(
		room,
		"Rug",
		CFrame.new(-560, FLOOR_Y + 1, -900) * VERTICAL,
		2,
		1500,
		Color3.fromRGB(70, 60, 110),
		Enum.Material.Fabric
	)
	slab(
		room,
		"RoomWallBack",
		Vector3.new(ROOM_X0, FLOOR_Y, ROOM_Z1),
		Vector3.new(ROOM_X1, CEILING_Y, ROOM_Z1 + 20),
		wallColor,
		SMOOTH
	)
	slab(
		room,
		"RoomWallFront",
		Vector3.new(ROOM_X0, FLOOR_Y, ROOM_Z0 - 20),
		Vector3.new(ROOM_X1, CEILING_Y, ROOM_Z0),
		wallColor,
		SMOOTH
	)
	slab(
		room,
		"RoomWallLeft",
		Vector3.new(ROOM_X0 - 20, FLOOR_Y, ROOM_Z0),
		Vector3.new(ROOM_X0, CEILING_Y, ROOM_Z1),
		wallColor,
		SMOOTH
	)
	slab(
		room,
		"RoomWallRight",
		Vector3.new(ROOM_X1, FLOOR_Y, ROOM_Z0),
		Vector3.new(ROOM_X1 + 20, CEILING_Y, ROOM_Z1),
		wallColor,
		SMOOTH
	)
	slab(
		room,
		"RoomCeiling",
		Vector3.new(ROOM_X0, CEILING_Y, ROOM_Z0),
		Vector3.new(ROOM_X1, CEILING_Y + 20, ROOM_Z1),
		Color3.fromRGB(236, 232, 240),
		SMOOTH
	)
	-- Ruban LED au plafond (violet de l'app), le long des 4 murs
	for _, strip in
		{
			{ (ROOM_X0 + ROOM_X1) / 2, ROOM_Z1 - 6, ROOM_X1 - ROOM_X0, 4 },
			{ (ROOM_X0 + ROOM_X1) / 2, ROOM_Z0 + 6, ROOM_X1 - ROOM_X0, 4 },
			{ ROOM_X0 + 6, (ROOM_Z0 + ROOM_Z1) / 2, 4, ROOM_Z1 - ROOM_Z0 },
			{ ROOM_X1 - 6, (ROOM_Z0 + ROOM_Z1) / 2, 4, ROOM_Z1 - ROOM_Z0 },
		}
	do
		Build.Neon({
			Name = "CeilingLed",
			Size = Vector3.new(math.min(strip[3], 2000), 10, math.min(strip[4], 2000)),
			CFrame = CFrame.new(strip[1], CEILING_Y - 30, strip[2]),
			Color = APP_GLOW,
			Tags = { "RgbStrip" },
			Parent = room,
		})
	end

	-- Fenêtre au coucher de soleil (mur -X), enseigne néon et mousse acoustique (mur du fond, côté -X)
	RoomProps.Window(room, facing(Vector3.new(ROOM_X0 + 2, 360, -520), Vector3.xAxis), 820, 760)
	local backWall = function(x: number, y: number): CFrame
		return facing(Vector3.new(x, y, ROOM_Z1 - 1), -Vector3.zAxis)
	end
	RoomProps.NeonSign(room, backWall(-1000, 760), 520, 170, "AngaTV", Color3.fromRGB(255, 92, 170))
	RoomProps.AcousticFoam(room, backWall(-1150, 380), 110, Color3.fromRGB(58, 52, 96))
	RoomProps.AcousticFoam(room, backWall(-800, 380), 110, Color3.fromRGB(58, 52, 96))
	-- Posters (mur du fond côté +X, au-dessus de l'écran ; mur +X ; mur de devant, derrière la chaise)
	RoomProps.Poster(room, backWall(900, 560), 380, 540, {
		Top = Color3.fromRGB(240, 86, 91),
		Bottom = Color3.fromRGB(120, 30, 50),
		Glyph = "A",
		Title = "AngaTV",
		TitleColor = C.White,
		Subtitle = "LIVE CHAQUE SOIR · 20h",
	})
	RoomProps.Poster(room, backWall(1340, 520), 320, 440, {
		Top = Color3.fromRGB(255, 232, 170),
		Bottom = Color3.fromRGB(230, 190, 120),
		Glyph = "LAGZ",
		GlyphColor = Color3.fromRGB(120, 60, 200),
		Title = "RECHERCHÉ",
		TitleColor = Color3.fromRGB(70, 40, 30),
		Subtitle = "Récompense : 144 FPS",
	})
	RoomProps.Poster(room, facing(Vector3.new(ROOM_X1 - 1, 500, -420), -Vector3.xAxis), 460, 620, {
		Top = Color3.fromRGB(80, 60, 190),
		Bottom = Color3.fromRGB(20, 110, 150),
		Glyph = "7",
		GlyphColor = Color3.fromRGB(120, 255, 236),
		Title = "OPÉRATION ANTI-LAG",
		TitleColor = C.White,
		Subtitle = "7 mondes · 1 virus · ce soir",
	})
	RoomProps.Poster(room, facing(Vector3.new(-200, 300, ROOM_Z0 + 1), Vector3.zAxis), 500, 360, {
		Top = Color3.fromRGB(30, 30, 40),
		Bottom = Color3.fromRGB(60, 40, 110),
		Glyph = "GG",
		GlyphColor = Color3.fromRGB(246, 196, 83),
		Title = "144 FPS OU RIEN",
		TitleColor = C.White,
	})
	-- Porte de la chambre (mur de devant)
	local doorCf = facing(Vector3.new(700, FLOOR_Y + 560, ROOM_Z0 + 8), Vector3.zAxis)
	Box(room, "RoomDoor", Vector3.new(520, 1120, 12), doorCf, Color3.fromRGB(236, 232, 226))
	Box(room, "RoomDoorFrame", Vector3.new(580, 1170, 8), doorCf * CFrame.new(0, 25, 8), Color3.fromRGB(210, 206, 200))
	Rod(room, "RoomDoorKnob", doorCf * CFrame.new(-200, -20, -14) * CFrame.Angles(0, math.pi / 2, 0), 24, 30, C.Nickel)

	-- Chaise gamer d'Anga : hors du bureau, derrière le spawn, tournée vers l'écran
	local chairAt = KEYBOARD_AT + L * 820
	local chairCf = facing(Vector3.new(chairAt.X, FLOOR_Y, chairAt.Z), -L)
	-- Boîte de la chaise primitive : accoudoirs 660 de large, dossier ~1490 de haut, piétement ~720
	ModelLibrary.Place("GamingChair", chairCf, room, { Fit = Vector3.new(660, 1490, 720), Anchor = ORIGIN }, function()
		return RoomProps.Chair(room, chairCf)
	end)
end

------------------------------------------------------------------------------------
-- Setup du streamer (écran, clavier, souris, micro, casque, tasse, lampe, câbles, post-it)
------------------------------------------------------------------------------------

local function buildSetup(lobby: Model, spawnCf: CFrame)
	local desk = Build.Folder("DeskSetup", lobby)
	-- Tapis XXL (sol du lobby) sous le clavier et la souris
	local matCf = facing(KEYBOARD_AT + R * 60 + L * 10 + Vector3.new(0, MAT_TOP, 0), L)
	RoomProps.DeskMat(desk, matCf, MAT_W, MAT_D, "AngAInOne")

	-- Écran d'Anga : la dalle StreamMonitor regarde le spawn
	local monitorCf = facing(MONITOR_AT, L)
	local monitor = RoomProps.Monitor(desk, monitorCf, SCREEN_W, SCREEN_H, SCREEN_BOTTOM)
	local screen = Build.Part({
		Name = "StreamMonitor",
		Size = monitor.ScreenSize,
		CFrame = monitor.Screen * CFrame.new(0, 0, 0.3),
		Color = Color3.fromRGB(14, 14, 20),
		Material = Enum.Material.Glass,
		Reflectance = 0.05,
		CastShadow = false,
		Tags = { "StreamMonitor" },
		Parent = desk,
	})
	screen.CanCollide = false
	screen.CanQuery = false
	-- Vrai écran incurvé (pied plus profond que le V primitif) : la dalle StreamMonitor reste l'hôte du
	-- direct, recalée devant son `Screen` ; boîtier, colonne et pied primitifs gardent leur collision.
	local monitorModel = ModelLibrary.Dress(
		"Monitor",
		monitorCf,
		desk,
		{ Fit = Vector3.new(SCREEN_W + 10, SCREEN_BOTTOM + SCREEN_H + 5, 140), Anchor = ORIGIN },
		{ monitor.Model }
	)
	if monitorModel then
		ModelLibrary.FitScreen(monitorModel, screen)
	end
	-- Face avant de la dalle (= monitor.Screen en primitives) et haut du boîtier (webcam)
	local screenFront = if monitorModel then screen.CFrame * CFrame.new(0, 0, -screen.Size.Z / 2) else monitor.Screen
	local screenW, screenH = screen.Size.X, screen.Size.Y
	local monitorTop = if monitorModel
		then monitorCf * CFrame.new(0, screenFront.Position.Y - MONITOR_AT.Y + screenH / 2 + 3, 3.6)
		else monitor.Top
	lamp(desk, (monitor.Screen * CFrame.new(0, -30, -40)).Position, Color3.fromRGB(170, 190, 255), 1, 60)
	-- Ring light + webcam sur trépied, à droite de l'écran (sinon : webcam clipsée sur l'écran)
	local ringCf = facing(setup(-60, 0, 300), L - R * 0.3)
	ModelLibrary.Place(
		"WebcamLight",
		ringCf,
		desk,
		{ Fit = Vector3.new(76, 150, 76), Anchor = ORIGIN, Name = "Webcam" },
		function()
			return RoomProps.Webcam(desk, monitorTop)
		end
	)
	-- Post-it collés sur les bords de l'écran
	RoomProps.StickyNote(
		desk,
		screenFront * CFrame.new(-screenW / 2 - 8, -screenH / 2 + 26, -0.4) * CFrame.Angles(0, 0, math.rad(6)),
		"LIVE 20h !",
		RoomProps.Colors.PaperYellow,
		26
	)
	RoomProps.StickyNote(
		desk,
		screenFront * CFrame.new(screenW / 2 + 8, -screenH / 2 + 22, -0.4) * CFrame.Angles(0, 0, math.rad(-5)),
		"NE PAS ÉTEINDRE LE PC !!",
		RoomProps.Colors.PaperPink,
		26
	)
	-- Enceintes de bureau de part et d'autre de l'écran, un peu en retrait, tournées vers le joueur
	for _, side in { -1, 1 } do
		ModelLibrary.Place(
			"Speaker",
			facing(setup(-110, 0, side * 160), L - R * side * 0.15),
			desk,
			{ Fit = Vector3.new(60, 110, 80), Anchor = ORIGIN }
		)
	end

	-- Clavier mécanique (dos à l'écran = le joueur qui tape le regarde depuis le spawn), souris à côté
	local keyboard = RoomProps.Keyboard(desk, facing(KEYBOARD_AT + Vector3.new(0, MAT_TOP, 0), -L))
	-- Vrai clavier : largeur du boîtier géant ; enfoncé dans le bureau pour que le dessus de ses touches
	-- (11,59 unités modélisées) affleure celui des touches praticables, qui restent solides (invisibles).
	-- Sa face avant (barre d'espace) regarde le joueur qui tape, son câble part vers l'écran.
	ModelLibrary.Dress(
		"Keyboard",
		facing(KEYBOARD_AT + Vector3.new(0, MAT_TOP + KEY_TOP, 0), L),
		desk,
		{ Fit = Vector3.new(RoomProps.KEYBOARD_SIZE.X, 40, 400), Anchor = Vector3.new(0, 11.59, 0) },
		{ keyboard }
	)
	lamp(desk, KEYBOARD_AT + Vector3.new(0, 30, 0), Color3.fromRGB(150, 120, 255), 0.8, 60)
	local mouseCf = facing(KEYBOARD_AT + R * 238 + L * 16 + Vector3.new(0, MAT_TOP, 0), -L)
		* CFrame.Angles(0, math.rad(-8), 0)
	local mouse = RoomProps.Mouse(desk, mouseCf)
	-- Souris : paume (face avant du modèle) vers le joueur, câble vers l'écran
	ModelLibrary.Dress(
		"Mouse",
		mouseCf * CFrame.Angles(0, math.pi, 0),
		desk,
		{ Fit = Vector3.new(60, 32, 170), Anchor = ORIGIN },
		{ mouse }
	)

	-- Micro sur bras (socle à côté de la vitre de la tour), casque sur support, multiprise
	local micBase, micAt = setup(-40, 0, -150), setup(210, 190, -95)
	local micArm = RoomProps.MicArm(desk, micBase, setup(40, 330, -150), micAt, setup(480, 330, -120))
	-- Bras modélisé vers -Z depuis son origine (pince 40 studs sous le plateau, cachée dans le bureau)
	ModelLibrary.Dress(
		"MicArm",
		facing(micBase, micAt - micBase),
		desk,
		{ Fit = Vector3.new(100, 430, 360), Anchor = ORIGIN },
		{ micArm }
	)
	local headsetCf = facing(setup(-20, 0, 190), L + R * 0.4)
	local headset = RoomProps.HeadsetStand(desk, headsetCf)
	ModelLibrary.Dress("Headset", headsetCf, desk, { Fit = Vector3.new(100, 151, 100), Anchor = ORIGIN }, { headset })
	RoomProps.StreamDeck(desk, facing(setup(40, MAT_TOP, 150), L))
	local stripCf = facing(Vector3.new(300, 0, 60), Vector3.xAxis)
	RoomProps.PowerStrip(desk, stripCf)
	local function plug(i: number): Vector3
		return (stripCf * CFrame.new(-40 + i * 34, 24, 0)).Position
	end

	-- Tasse géante et lampe de bureau (côté -X de la tour), plante à côté de la tasse
	local mugAt = Vector3.new(-470, 0, -250)
	local mug = RoomProps.Mug(desk, mugAt, SPAWN - mugAt)
	ModelLibrary.Dress(
		"Mug",
		facing(mugAt, SPAWN - mugAt),
		desk,
		{ Fit = Vector3.new(122, 121, 100), Anchor = ORIGIN },
		{ mug }
	)
	local lampBase, lampHead = Vector3.new(-560, 0, 80), Vector3.new(-420, 470, -90)
	local deskLamp =
		RoomProps.DeskLamp(desk, lampBase, Vector3.new(-600, 360, 10), lampHead, Vector3.new(-200, 0, -260))
	-- Abat-jour modélisé vers -Z : tourné vers la tête de la lampe primitive
	ModelLibrary.Dress(
		"DeskLamp",
		facing(lampBase, lampHead - lampBase),
		desk,
		{ Fit = Vector3.new(100, 500, 300), Anchor = ORIGIN },
		{ deskLamp }
	)
	local plantAt = Vector3.new(-580, 0, -340)
	ModelLibrary.Place(
		"Plant",
		facing(plantAt, SPAWN - plantAt),
		desk,
		{ Fit = Vector3.new(90, 110, 90), Anchor = ORIGIN }
	)

	-- Spaghetti de câbles : écran, clavier, webcam, micro -> arrière de la tour ; tour, écran -> multiprise
	local backZ = INNER + WALL + 6
	local function cable(points: { Vector3 }, color: Color3, radius: number)
		Props.Cable(desk, points, radius, color)
	end
	local rear = monitor.Rear.Position
	local braid = Color3.fromRGB(140, 80, 220)
	cable({
		rear,
		rear + Vector3.new(0, -70, 0) + L * -20,
		setup(-70, 1.5, 20),
		Vector3.new(160, 1.5, 40),
		Vector3.new(158, 1.5, 150),
		Vector3.new(60, 1.5, backZ),
	}, C.Black, 2)
	cable({
		setup(66, 2, 0),
		setup(20, 1.5, -70),
		Vector3.new(172, 1.5, -20),
		Vector3.new(214, 1.5, 110),
		Vector3.new(120, 1.5, 158),
		Vector3.new(30, 1.5, backZ),
	}, braid, 1.4)
	-- Câble de la webcam : du haut de l'écran, ou du pied de la ring light (modèle) en contournant l'enceinte
	local webcamCable = if ModelLibrary.Has("WebcamLight")
		then { ringCf.Position + Vector3.new(0, 1.5, 0), setup(-150, 1.5, 250), setup(-190, 1.5, 60) }
		else {
			monitorTop.Position + Vector3.new(0, 4, 0) - L * 10,
			rear + R * 30 + Vector3.new(0, -40, 0),
			setup(-80, 1.5, 60),
		}
	for _, point in { Vector3.new(250, 1.5, 90), Vector3.new(170, 1.5, 180), Vector3.new(10, 1.5, backZ) } do
		table.insert(webcamCable, point)
	end
	cable(webcamCable, Color3.fromRGB(210, 210, 220), 1.2)
	cable({
		setup(-40, 3, -150),
		Vector3.new(185, 1.5, -40),
		Vector3.new(150, 1.5, 60),
		Vector3.new(190, 1.5, 165),
		Vector3.new(-10, 1.5, backZ),
	}, C.Black, 1.4)
	cable({
		Vector3.new(15, 70, backZ - 2.5),
		Vector3.new(15, 1.5, 190),
		Vector3.new(150, 1.5, 205),
		Vector3.new(260, 1.5, 130),
		plug(3),
	}, C.Black, 2.4)
	cable(
		{ rear + R * -20 + Vector3.new(0, -20, 0), setup(-60, 1.5, -40), Vector3.new(250, 1.5, 20), plug(0) },
		C.Black,
		1.8
	)
	cable({
		(stripCf * CFrame.new(85, 7, 0)).Position,
		Vector3.new(310, 1.5, 200),
		Vector3.new(420, 1.5, 290),
		Vector3.new(440, 1.5, DESK_Z1 - 2),
		Vector3.new(450, -80, DESK_Z1 + 10),
	}, Color3.fromRGB(230, 230, 236), 2)
	cable({
		Vector3.new(-560, 2, 80),
		Vector3.new(-600, 1.5, 200),
		Vector3.new(-520, 1.5, 300),
		Vector3.new(-500, 1.5, DESK_Z1 - 2),
		Vector3.new(-490, -80, DESK_Z1 + 10),
	}, C.Black, 1.4)

	-- Post-it sur le bureau, devant le spawn, et sur la façade de la tour
	RoomProps.StickyNote(
		desk,
		spawnCf * CFrame.new(-34, MAT_TOP + 0.16 - SPAWN.Y, 4) * CFrame.Angles(0, math.rad(12), 0),
		"Réparer le PC avant 20h !",
		RoomProps.Colors.PaperYellow,
		22,
		true
	)
	RoomProps.StickyNote(
		desk,
		facing(Vector3.new(40, 150, PANEL_Z - 0.4), -Vector3.zAxis) * CFrame.Angles(0, 0, math.rad(-7)),
		"Mode Intervention : ON",
		RoomProps.Colors.PaperCyan,
		26
	)
end

------------------------------------------------------------------------------------
-- Base : spawn, écran de l'app, classements, bornes, Anga, titre
------------------------------------------------------------------------------------

local function buildBase(lobby: Model): CFrame
	-- Spawn : face à la tour et à l'écran d'Anga (le bouton JOUER du HUD mène au pad 0, au Miniaturiseur)
	local spawnCf = facing(SPAWN, Vector3.new(170, 0, -80) - SPAWN)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = spawnCf
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = C.MetalDark
	spawn.Material = METAL
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby
	Props.Ring(lobby, "SpawnRing", spawnCf * CFrame.new(0, 0.6, 0) * VERTICAL, 6.2, 0.5, 0.3, 16, C.Cyan, NEON)
	lamp(lobby, SPAWN + Vector3.new(0, 36, 0), Color3.fromRGB(255, 236, 214), 1, 60)

	-- Écran de l'app AngAInOne : LCD intégré en bas de la façade de la tour (à droite du portail)
	local appCf = CFrame.new(-20, 60, PANEL_Z - 0.6)
	Box(lobby, "AppScreenBezel", Vector3.new(118, 70, 0.8), appCf * CFrame.new(0, 0, 0.5), C.Black, METAL)
	local appScreen = Build.Decor({
		Name = "AppScreen",
		Size = Vector3.new(110, 62, 0.4),
		CFrame = appCf,
		Color = Color3.fromHex(Branding.PartnerApp.Surface),
		Material = SMOOTH,
		Tags = { "AppScreen" },
		Parent = lobby,
	})
	Build.PointLight(appScreen, APP_GLOW, 1.2, 60)
	Common.CountLight()
	Build.Neon({
		Name = "AppScreenGlow",
		Size = Vector3.new(120, 0.6, 0.6),
		CFrame = appCf * CFrame.new(0, -35.4, 0),
		Color = APP_GLOW,
		Tags = { "RgbStrip" },
		Parent = lobby,
	})

	-- Hologramme du titre, au-dessus du Miniaturiseur et de l'écran de l'app
	local titlePos = Vector3.new(-73, 128, FACE_Z - 18)
	local title = Build.Decor({
		Name = "TitleHologram",
		Size = Vector3.new(80, 20, 0.2),
		CFrame = facing(titlePos, SPAWN - titlePos),
		Transparency = 1,
		Tags = { "TitleHologram" },
		Parent = lobby,
	})
	Build.PointLight(title, C.Violet, 1.6, 60)
	Common.CountLight()

	-- Classements (face avant dessinée par le client), côté -X, tournés vers le spawn
	for i, board in { "Wins", "BestTime", "Stage" } do
		local position = Vector3.new(-250 - (i - 2) ^ 2 * 14, 20, -320 + (i - 2) * 50)
		local cf = facing(position, SPAWN - position)
		Build.Part({
			Name = `{board}Frame`,
			Size = Vector3.new(33, 23, 1.6),
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
			CFrame = cf * CFrame.new(0, -15.5, 1.2),
			Color = C.MetalLight,
			Material = METAL,
			Parent = lobby,
		})
		Build.Part({
			Name = `{board}Foot`,
			Size = Vector3.new(16, 1, 10),
			CFrame = facing(Vector3.new(position.X, 0.5, position.Z), SPAWN - position) * CFrame.new(0, 0, 1.2),
			Color = C.MetalDark,
			Material = METAL,
			Parent = lobby,
		})
		Build.Neon({
			Name = `{board}Trim`,
			Size = Vector3.new(33, 0.5, 0.5),
			CFrame = cf * CFrame.new(0, -11.8, 0),
			Color = if i == 1 then C.Gold elseif i == 2 then C.Cyan else C.Violet,
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
			At = Vector3.new(-150, 0, -250),
		},
		{
			Action = "Arcade",
			Text = "Arcade",
			Object = "Mini-jeux antivirus",
			Color = C.Cyan,
			At = Vector3.new(-170, 0, -300),
		},
		{
			Action = "Daily",
			Text = "Cadeau du jour",
			Object = "Récompenses",
			Color = SPRING,
			At = Vector3.new(-155, 0, -350),
		},
	}
	-- Vrais modèles des bornes (la borne du cadeau du jour reste en primitives)
	local KIOSK_MODELS: { [string]: string } = { Shop = "ShopKiosk", Arcade = "ArcadeCabinet" }
	for _, kiosk in kiosks do
		local cf = facing(kiosk.At, SPAWN - kiosk.At)
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
		local base = Box(model, "Base", Vector3.new(9, 0.6, 7), cf * CFrame.new(0, 0.3, 0.4), C.Black, METAL)
		local screenBack = Box(
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
		local trim = Build.Neon({
			Name = "Trim",
			Size = Vector3.new(6.2, 0.4, 0.4),
			CFrame = cf * CFrame.new(0, 5.1, -2),
			Color = kiosk.Color,
			Parent = model,
		})
		Build.Prompt(stand, kiosk.Text, kiosk.Object, kiosk.Action, 12)
		-- Modèle : Stand (porteur du prompt) et socle restent solides mais invisibles ; l'écran primitif
		-- (texte de la borne) est recalé sur le `Screen` du modèle. Boîte de la borne primitive : 9 × 11,4 × 7,4.
		local key = KIOSK_MODELS[kiosk.Action]
		local placed = if key
			then ModelLibrary.Dress(
				key,
				cf,
				model,
				{ Fit = Vector3.new(9, 11.4, 7.4), Anchor = ORIGIN },
				{ stand, base, screenBack, trim }
			)
			else nil
		if placed then
			ModelLibrary.FitScreen(placed, screen)
		end
	end

	-- Emplacement de la mascotte Anga (le client l'affiche ici), à côté du spawn
	local angaPos = Vector3.new(-38, 3, -246)
	local anga = Build.Decor({
		Name = "AngaSpot",
		Size = Vector3.new(4, 6, 4),
		CFrame = facing(angaPos, SPAWN - angaPos),
		Transparency = 1,
		Parent = lobby,
	})
	anga.CanQuery = false
	Rod(lobby, "AngaPodium", CFrame.new(angaPos.X, 0.4, angaPos.Z) * VERTICAL, 0.8, 9, C.MetalDark)
	Props.Ring(lobby, "AngaRing", CFrame.new(angaPos.X, 0.9, angaPos.Z) * VERTICAL, 4.4, 0.4, 0.3, 14, C.Brand, NEON)
	return spawnCf
end

------------------------------------------------------------------------------------
-- Miniaturiseur AngAInOne : portail de départ autour du checkpoint 0, devant la porte de la façade
------------------------------------------------------------------------------------

-- Arc de cercle vertical (segments tangents) dans le plan XY, centre `center`, de a0 à a1 (radians,
-- 0 = en haut). Décor pur.
local function arc(
	parent: Instance,
	name: string,
	center: Vector3,
	radius: number,
	a0: number,
	a1: number,
	count: number,
	width: number,
	depth: number,
	color: Color3,
	material: Enum.Material
)
	for i = 0, count - 1 do
		local t0 = a0 + (a1 - a0) * i / count
		local t1 = a0 + (a1 - a0) * (i + 1) / count
		local p0 = center + Vector3.new(radius * math.sin(t0), radius * math.cos(t0), 0)
		local p1 = center + Vector3.new(radius * math.sin(t1), radius * math.cos(t1), 0)
		local dir = (p1 - p0).Unit
		local part = Box(
			parent,
			name,
			Vector3.new((p1 - p0).Magnitude + width * 0.3, width, depth),
			CFrame.fromMatrix((p0 + p1) / 2, dir, Vector3.zAxis:Cross(dir)),
			color,
			material
		)
		if material == NEON then
			part.Transparency = 0.05
		end
	end
end

-- Pièces du Miniaturiseur primitif que la capsule modélisée remplace (masquées, collision gardée).
local CAPSULE_PARTS: { [string]: boolean } = {
	MiniaturiserBase = true,
	MiniaturiserBaseRing = true,
	ShrinkRing = true,
	ShrinkRingGlow = true,
	ShrinkBeam = true,
	BeamNozzle = true,
	BeamArm = true,
}

local function buildMiniaturiser(lobby: Model)
	local model = Build.Model("Miniaturiser", lobby)
	local doorX0, doorX1 = Common.EntranceDoor()
	local doorX = (doorX0 + doorX1) / 2
	local padZ = PANEL_Z - 9 -- pad de 12 : son bord arrière est à 3 studs de la face mesh
	local gateZ = padZ - 2
	-- Socle rond sous le pad (plus bas que son dessus), cerclé de cyan (couleur « sûr » du jeu : un
	-- disque violet lumineux au sol ressemblerait à une flaque de glitch)
	local baseCf = CFrame.new(doorX, 0.3, padZ - 6)
	Build.Cylinder({
		Name = "MiniaturiserBase",
		Size = Vector3.new(0.6, 52, 52),
		CFrame = baseCf * VERTICAL,
		Color = Color3.fromRGB(40, 36, 56),
		Material = METAL,
		Parent = model,
	})
	Props.Ring(model, "MiniaturiserBaseRing", baseCf * CFrame.new(0, 0.2, 0) * VERTICAL, 24.6, 1, 0.3, 24, SAFE, NEON)
	Props.Ring(
		model,
		"MiniaturiserBaseRing",
		baseCf * CFrame.new(0, 0.2, 0) * VERTICAL,
		19,
		0.6,
		0.3,
		20,
		APP_GLOW,
		NEON
	)
	-- Anneaux du rayon réducteur : de plus en plus petits vers la porte (on « rétrécit » en entrant)
	for i, ring in { { 30, gateZ - 8 }, { 21, gateZ + 2 }, { 13, PANEL_Z - 1.5 } } do
		local r, z = ring[1], ring[2]
		local center = Vector3.new(doorX, r - 1, z)
		arc(model, "ShrinkRing", center, r + 1.8, math.rad(-128), math.rad(128), 18, 3, 3.4, C.MetalDark, METAL)
		arc(
			model,
			"ShrinkRingGlow",
			center + Vector3.new(0, 0, -1.9),
			r,
			math.rad(-126),
			math.rad(126),
			18,
			1.3,
			0.6,
			if i == 2 then SAFE else APP_GLOW,
			NEON
		)
	end
	-- Pylônes (solides, hors de la zone du pad), émetteurs, pupitres, traverse et panneau JOUER
	local topY = 76
	for _, side in { -1, 1 } do
		local x = doorX + side * 38
		Build.Part({
			Name = "MiniaturiserPylon",
			Size = Vector3.new(10, topY, 14),
			CFrame = CFrame.new(x, topY / 2, gateZ),
			Color = C.MetalDark,
			Material = METAL,
			Parent = model,
		})
		Build.Neon({
			Name = "PylonGlow",
			Size = Vector3.new(0.8, topY - 8, 1.4),
			CFrame = CFrame.new(x - side * 5.2, topY / 2, gateZ - 3.5),
			Color = APP_GLOW,
			Tags = { "RgbStrip" },
			Parent = model,
		})
		Build.Neon({
			Name = "PylonEmitter",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 9,
			CFrame = CFrame.new(x, topY + 4, gateZ),
			Color = SAFE,
			Parent = model,
		})
		-- Pupitre de commande incliné devant le pylône
		local console = CFrame.new(x + side * 2, 0, gateZ - 14)
		Box(model, "ConsoleStand", Vector3.new(8, 8, 6), console * CFrame.new(0, 4, 0), C.MetalDark, METAL)
		Box(
			model,
			"ConsoleScreen",
			Vector3.new(9, 0.4, 6),
			console * CFrame.new(0, 8.6, -0.5) * CFrame.Angles(math.rad(-25), 0, 0),
			APP_GLOW,
			NEON
		)
	end
	Box(model, "MiniaturiserBeam", Vector3.new(86, 7, 12), CFrame.new(doorX, topY, gateZ), C.Black, METAL)
	local sign = Box(model, "PlaySign", Vector3.new(80, 22, 1), CFrame.new(doorX, topY + 16, gateZ), C.Bg, METAL)
	Props.Sign(sign, "JOUER", "Miniaturiseur AngAInOne", SAFE, C.White, Enum.NormalId.Front)
	for _, y in { topY + 4.6, topY + 27.4 } do
		Build.Neon({
			Name = "PlaySignTrim",
			Size = Vector3.new(82, 1, 1.4),
			CFrame = CFrame.new(doorX, y, gateZ),
			Color = APP_GLOW,
			Parent = model,
		})
	end
	-- Rayon réducteur : du pad jusqu'à la buse suspendue à la traverse
	local beam = Build.Decor({
		Name = "ShrinkBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(topY - 8, 10, 10),
		CFrame = CFrame.new(doorX, (topY - 8) / 2, padZ) * VERTICAL,
		Color = APP_GLOW,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		CastShadow = false,
		Parent = model,
	})
	beam.CanTouch = false
	Rod(model, "BeamNozzle", CFrame.new(doorX, topY - 6, padZ) * VERTICAL, 6, 14, C.MetalLight)
	Box(model, "BeamArm", Vector3.new(6, 3, 10), CFrame.new(doorX, topY - 3, (padZ + gateZ) / 2), C.MetalLight, METAL)
	lamp(model, Vector3.new(doorX, 22, padZ - 16), APP_GLOW, 1.8, 50)

	-- Chemin lumineux du spawn au portail
	local padPos = Vector3.new(doorX, 0, padZ)
	local matCenter = KEYBOARD_AT + R * 60 + L * 10
	for i = 1, 6 do
		local t = i / 7
		local position = SPAWN:Lerp(padPos, t)
		local offset = position - matCenter
		local onMat = math.abs(offset:Dot(R)) < MAT_W / 2 and math.abs(offset:Dot(L)) < MAT_D / 2
		Build.Neon({
			Name = "Chevron",
			Size = Vector3.new(7, 0.2, 1.2),
			CFrame = facing(Vector3.new(position.X, if onMat then MAT_TOP + 0.1 else 0.1, position.Z), padPos - SPAWN),
			Color = SAFE,
			Transparency = 0.2,
			Parent = model,
		})
	end
	Common.CheckpointPad(0, Vector3.new(doorX, 1, padZ), Vector3.zAxis)

	-- Vraie capsule « Mode Intervention » autour du pad 0 : entrée (-Z du modèle) vers le spawn, sol
	-- hexagonal (2,56 unités modélisées) juste sous le dessus du pad, avancée de 4 studs pour moins
	-- mordre dans la façade. Remplace socle, anneaux et rayon ; le portique (pylônes, traverse, panneau
	-- JOUER, pupitres) et le chemin lumineux restent. Boîte du portail primitif : 86 × 104 × 41.
	local capsule: { Instance } = {}
	for _, child in model:GetChildren() do
		if CAPSULE_PARTS[child.Name] then
			table.insert(capsule, child)
		end
	end
	ModelLibrary.Dress(
		"Miniaturiseur",
		facing(Vector3.new(doorX, 0.95, padZ - 4), -Vector3.zAxis),
		model,
		{ Fit = Vector3.new(86, 104, 41), Anchor = Vector3.new(0, 2.56, 0) },
		capsule
	)
end

function Lobby.Build(tower: Folder)
	local lobby = Build.Model("Lobby", tower)
	lobby.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildRoom(lobby)
	local spawnCf = buildBase(lobby)
	buildSetup(lobby, spawnCf)
	buildMiniaturiser(lobby)

	-- Maison de départ (coin 0) : de la porte de façade au toit = entrée du monde 1 (Common.EntryOf(1))
	local start = Build.Folder("Start", lobby)
	Common.House(Common.CornerFrame(0), 0.1, Common.ENTRY - 0.1, {
		Style = Common.Style(Tower.Worlds[1]),
		Parent = start,
	})
end

return table.freeze(Lobby)
