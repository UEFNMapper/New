--!strict
--[[
	EasterEggs : clins d'œil à la vraie app AngAInOne et aux galères PC que tout joueur connaît
	(docs/SCENARIO.md §7). Décor + ProximityPrompt ; les réactions sont côté client
	(Controllers/Interactions : actions Plug, Talk, Paste, Rgb, Dev), rien n'y est compétitif.

	Lobby (BuildLobby) :
	- le câble HDMI débranché derrière la tour (« Brancher » : ding + « Avez-vous essayé de le rebrancher ? ») ;
	- « le Service », le PNJ support qui ne dort jamais et répond à tout « Avez-vous essayé de redémarrer ? » ;
	- le mur où le pseudo du joueur s'affiche en néon (tag NeonName, Controllers/NeonName).
	Salles de terminal (BuildWorld) :
	- monde 3 : la Corbeille, avec des fichiers supprimés célèbres (dont RAM_download_2go.exe, le virus) ;
	- monde 5 : le tube de pâte thermique (« Appliquer » : une fois = parfait, deux fois = le CPU disparaît) ;
	- monde 6 : l'interrupteur « RGB = +10 FPS » (10 secondes de vitesse en plus, et des couleurs) ;
	- monde 7 : l'escargot « Wi-Fi de l'hôtel » qui transporte les paquets (ping 999), et sur le toit,
	  AngATV, le dev caché (« Tu m'as trouvé. Le PC est entre de bonnes mains. »).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local Common = require(script.Parent.Common)

local EasterEggs = {}

local C = Props.C
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic
local facing = Common.Facing
local P = Common.P

local Box = Props.Box
local Rod = Props.Rod

local VIOLET = Color3.fromHex("8B7CFF")
local SAFE = Common.Colors.Safe

-- Petit robot (PNJ) : corps, visière, antenne, pieds. Avant = LookVector de `cf` (base au sol).
local function robot(parent: Instance, name: string, cf: CFrame, body: Color3, visor: Color3): Model
	local model = Build.Model(name, parent)
	Box(model, "Body", Vector3.new(3, 3.6, 2.2), cf * CFrame.new(0, 2.6, 0), body, SMOOTH)
	Box(model, "Visor", Vector3.new(2.2, 0.9, 0.3), cf * CFrame.new(0, 3.3, -1.2), visor, NEON)
	Box(model, "Mouth", Vector3.new(1.2, 0.25, 0.3), cf * CFrame.new(0, 2.3, -1.2), visor, NEON)
	Rod(model, "Antenna", cf * CFrame.new(0, 5.2, 0) * CFrame.Angles(0, 0, math.pi / 2), 1.6, 0.3, C.MetalLight, METAL)
	local bulb = Build.Neon({
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.7,
		CFrame = cf * CFrame.new(0, 6.1, 0),
		Color = visor,
		Parent = model,
	})
	bulb.CastShadow = false
	for _, side in { -1, 1 } do
		Box(model, "Foot", Vector3.new(1.1, 0.8, 1.6), cf * CFrame.new(side * 0.9, 0.4, 0), C.MetalDark, METAL)
	end
	return model
end

-- Humain stylisé (le dev) : sweat à capuche, tête, casquette. Avant = LookVector de `cf`.
local function human(parent: Instance, name: string, cf: CFrame, hoodie: Color3, cap: Color3): Model
	local model = Build.Model(name, parent)
	Box(model, "Body", Vector3.new(2.4, 2.6, 1.3), cf * CFrame.new(0, 2.9, 0), hoodie, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		Box(
			model,
			"Leg",
			Vector3.new(0.9, 1.6, 1),
			cf * CFrame.new(side * 0.55, 0.8, 0),
			C.MetalDark,
			Enum.Material.Fabric
		)
	end
	local head = Build.Decor({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.8,
		CFrame = cf * CFrame.new(0, 5.1, 0),
		Color = Color3.fromRGB(240, 200, 170),
		Material = SMOOTH,
		Parent = model,
	})
	head.CanCollide = false
	Box(model, "Cap", Vector3.new(1.9, 0.5, 1.9), cf * CFrame.new(0, 5.9, 0), cap, SMOOTH)
	Box(model, "Peak", Vector3.new(1.6, 0.15, 1.0), cf * CFrame.new(0, 5.72, -1.2), cap, SMOOTH)
	for _, side in { -1, 1 } do
		Box(model, "Eye", Vector3.new(0.25, 0.3, 0.2), cf * CFrame.new(side * 0.35, 5.2, -0.85), C.Black, SMOOTH)
	end
	return model
end

------------------------------------------------------------------------------------
-- Lobby
------------------------------------------------------------------------------------

-- Tour : |x|, |z| ≤ 138 (coque + façade) ; bureau : x -760..900, z -660..330, dessus à y = 0 ;
-- spawn à (-30, 0.6, -290), bornes vers (-150, -250).
local SPAWN = Vector3.new(-30, 0.6, -290)

------------------------------------------------------------------------------------
-- Le BIOS caché : une salle bleue et grise façon « Setup Utility », cachée au-dessus de la chambre d'Anga,
-- où l'on entre par la touche Suppr posée devant le portail (comme au démarrage d'un vrai PC).
-- Note du BIOS, « À faire d'abord », et le QR code géant de la page BIOS de l'app (anga.tv).
-- Entrée / sortie : téléport côté client (Interactions : actions Bios / BiosExit).
------------------------------------------------------------------------------------

-- QR code de https://anga.tv (version 1, 21 × 21) : 1 = module noir.
local QR = {
	"111111101010101111111",
	"100000100011001000001",
	"101110101100101011101",
	"101110101101101011101",
	"101110101000101011101",
	"100000100111001000001",
	"111111101010101111111",
	"000000000001000000000",
	"111100101111010011101",
	"000101001101011111111",
	"101011110100010001011",
	"101110011100100101010",
	"100110101111001011001",
	"000000001011101010000",
	"111111100100000010000",
	"100000100111110111111",
	"101110100101000010110",
	"101110101100101100010",
	"101110101011101100100",
	"100000101110111110001",
	"111111101001011011100",
}

-- Centre au sol de la salle : AU-DESSUS du plafond de la chambre (y 1700), hors de vue ; jamais
-- sous le lobby (le serveur ramène au spawn tout joueur sous GameConfig.Run.FallKillBelow).
EasterEggs.BIOS_AT = Vector3.new(1300, 1900, -1850)
EasterEggs.BIOS_SPAWN = EasterEggs.BIOS_AT + Vector3.new(0, 3, 18) -- où l'on arrive (face aux panneaux)
EasterEggs.BIOS_KEY_AT = Vector3.new(-150, 0.6, -170) -- la touche Suppr, devant le portail

local BIOS_BLUE = Color3.fromRGB(0, 0, 168)
local BIOS_DEEP = Color3.fromRGB(0, 0, 120)
local BIOS_GREY = Color3.fromRGB(190, 190, 190)

local function biosPanel(parent: Instance, cf: CFrame, size: Vector3, title: string, body: string)
	local plate = Box(parent, "BiosPanel", size, cf, BIOS_GREY, SMOOTH)
	Props.Notice(plate, title, body, BIOS_BLUE)
	return plate
end

local function biosRoom(tower: Instance)
	local lobby = tower:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	local folder = Build.Folder("Bios", lobby)
	local at = EasterEggs.BIOS_AT
	local W, H, D = 70, 24, 60
	local function slab(size: Vector3, offset: Vector3, color: Color3)
		return Build.Part({
			Name = "BiosWall",
			Size = size,
			CFrame = CFrame.new(at + offset),
			Color = color,
			Material = SMOOTH,
			Parent = folder,
		})
	end
	slab(Vector3.new(W, 2, D), Vector3.new(0, -1, 0), BIOS_DEEP)
	slab(Vector3.new(W, 2, D), Vector3.new(0, H + 1, 0), BIOS_BLUE)
	slab(Vector3.new(W, H, 2), Vector3.new(0, H / 2, -D / 2 - 1), BIOS_BLUE)
	slab(Vector3.new(W, H, 2), Vector3.new(0, H / 2, D / 2 + 1), BIOS_BLUE)
	slab(Vector3.new(2, H, D), Vector3.new(-W / 2 - 1, H / 2, 0), BIOS_BLUE)
	slab(Vector3.new(2, H, D), Vector3.new(W / 2 + 1, H / 2, 0), BIOS_BLUE)
	Build.Neon({
		Name = "BiosLight",
		Size = Vector3.new(W - 10, 0.4, 1),
		CFrame = CFrame.new(at + Vector3.new(0, H - 0.5, 0)),
		Color = BIOS_GREY,
		Parent = folder,
	})
	Common.Lamp(folder, at + Vector3.new(0, H - 3, 0), BIOS_GREY, 1.4, 90)
	-- Bandeau du haut : « AngAInOne BIOS Setup Utility »
	local back = facing(at + Vector3.new(0, 0, -D / 2 + 0.6), Vector3.zAxis)
	local banner =
		Box(folder, "BiosBanner", Vector3.new(W - 6, 3.4, 0.3), back * CFrame.new(0, H - 2.5, 0), BIOS_GREY, SMOOTH)
	Props.Sign(
		banner,
		"AngAInOne BIOS Setup Utility · v1.0",
		"Suppr au démarrage · F10 : Save & Exit",
		BIOS_BLUE,
		BIOS_BLUE
	)
	-- Note et liste « À faire d'abord » (page BIOS de l'app)
	biosPanel(
		folder,
		back * CFrame.new(-18, 11, 0),
		Vector3.new(26, 14, 0.3),
		"NOTE DU BIOS : 92 / 100",
		"À faire d'abord :\n1. Mettre à jour le BIOS, uniquement avec le fichier du site officiel de la carte mère.\n2. Jamais pendant un orage, jamais en coupant le courant au milieu.\n3. XMP / EXPO activé : ta RAM tourne à sa vraie vitesse."
	)
	biosPanel(
		folder,
		back * CFrame.new(18, 11, 0),
		Vector3.new(26, 14, 0.3),
		"RACCOURCI AngAInOne",
		"La page BIOS te dit si ton BIOS est à jour, donne le lien officiel, les étapes, et un bouton pour redémarrer directement dans le BIOS. Scanne le QR code pour l'app."
	)
	-- Le QR code géant (SurfaceGui : une case par module)
	local qrWall = Box(
		folder,
		"BiosQr",
		Vector3.new(22, 22, 0.3),
		facing(at + Vector3.new(-W / 2 + 0.6, 12, 0), Vector3.xAxis),
		Color3.new(1, 1, 1),
		SMOOTH
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Qr"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.Parent = qrWall
	local n = #QR
	for row, line in QR do
		for col = 1, n do
			if string.sub(line, col, col) == "1" then
				local cell = Instance.new("Frame")
				cell.BorderSizePixel = 0
				cell.BackgroundColor3 = Color3.new(0, 0, 0)
				cell.Position = UDim2.fromScale(0.06 + 0.88 * (col - 1) / n, 0.06 + 0.88 * (row - 1) / n)
				cell.Size = UDim2.fromScale(0.88 / n + 0.002, 0.88 / n + 0.002)
				cell.Parent = gui
			end
		end
	end
	local qrSign = Box(
		folder,
		"BiosQrSign",
		Vector3.new(22, 3, 0.3),
		facing(at + Vector3.new(-W / 2 + 0.6, 25.2, 0), Vector3.xAxis),
		BIOS_GREY,
		SMOOTH
	)
	Props.Sign(qrSign, "Scanne-moi avec ton téléphone", "anga.tv · l'app AngAInOne", BIOS_BLUE, BIOS_BLUE)
	-- Sortie : la touche F10 (Save & Exit)
	local exitKey = Box(
		folder,
		"BiosExitKey",
		Vector3.new(8, 1.2, 8),
		CFrame.new(at + Vector3.new(0, 0.6, D / 2 - 8)),
		BIOS_GREY,
		SMOOTH
	)
	Props.Sign(exitKey, "F10", "Save & Exit", BIOS_BLUE, BIOS_BLUE, Enum.NormalId.Top)
	local exitPrompt = Build.Prompt(exitKey, "Quitter le BIOS", "F10 · Save & Exit", "BiosExit", 12)
	exitPrompt:SetAttribute("To", EasterEggs.BIOS_KEY_AT + Vector3.new(0, 3, 6))
	folder:SetAttribute("Spawn", EasterEggs.BIOS_SPAWN)
end

-- La touche Suppr, posée sur le bureau devant le portail.
local function biosEntry(folder: Instance)
	local key = Box(
		folder,
		"BiosKey",
		Vector3.new(6, 1.2, 6),
		CFrame.new(EasterEggs.BIOS_KEY_AT),
		Color3.fromRGB(43, 43, 43),
		SMOOTH
	)
	Props.Sign(key, "Suppr", "BIOS", VIOLET, C.White, Enum.NormalId.Top)
	local prompt = Build.Prompt(key, "Entrer dans le BIOS", "Touche Suppr", "Bios", 10)
	prompt:SetAttribute("To", EasterEggs.BIOS_SPAWN)
end

-- Le Stream Deck d'Anga : trois touches font une action débile (le client s'en charge).
local function streamDeckKeys(lobby: Instance)
	local deck = lobby:FindFirstChild("StreamDeck", true)
	if not deck then
		return
	end
	local keys = {}
	for _, part in deck:GetChildren() do
		if part.Name == "StreamDeckKey" and part:IsA("BasePart") then
			table.insert(keys, part)
		end
	end
	table.sort(keys, function(a: BasePart, b: BasePart): boolean
		return a.CFrame.Position.X < b.CFrame.Position.X
	end)
	local actions = { { "Pet", "Pet !" }, { "Confetti", "Confettis" }, { "Slow", "Mode lent" } }
	for index, action in actions do
		local key = keys[index * 4]
		if key then
			local prompt = Build.Prompt(key, action[2], "Stream Deck", "Deck", 10)
			prompt:SetAttribute("Deck", action[1])
		end
	end
end

function EasterEggs.BuildLobby(tower: Instance)
	local lobby = tower:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	local folder = Build.Folder("EasterEggs", lobby)

	-- 1. Le câble HDMI débranché, derrière la tour : prise sur la paroi arrière, fiche posée sur le bureau
	do
		local socketCf = facing(Vector3.new(40, 4, 139.6), Vector3.zAxis)
		Box(folder, "HdmiSocket", Vector3.new(3, 2, 1.2), socketCf, C.MetalDark, METAL)
		Box(folder, "HdmiSocketHole", Vector3.new(1.6, 0.7, 0.3), socketCf * CFrame.new(0, 0, -0.5), C.Black, SMOOTH)
		local plate =
			Box(folder, "HdmiLabel", Vector3.new(6, 2.2, 0.3), socketCf * CFrame.new(0, 2.6, -0.3), C.Bg, SMOOTH)
		Props.Sign(plate, "HDMI", "entrée vidéo", VIOLET, C.White)
		local plugCf = facing(Vector3.new(44, 1, 158), Vector3.zAxis) * CFrame.Angles(0, 0.35, 0)
		local plug = Box(folder, "HdmiPlug", Vector3.new(2, 1.2, 3), plugCf, C.Black, SMOOTH)
		Box(plug, "PlugTip", Vector3.new(1.4, 0.5, 1.2), plugCf * CFrame.new(0, 0, -2.0), C.MetalLight, METAL)
		Props.Cable(folder, {
			plugCf.Position + Vector3.new(0, 0.3, 1.5),
			Vector3.new(60, 0.6, 175),
			Vector3.new(110, 0.6, 205),
			Vector3.new(170, 0.6, 196),
		}, 1.2, C.Black)
		Build.Prompt(plug, "Brancher", "Câble HDMI débranché", "Plug", 12)
	end

	-- 2. « Le Service » : support technique qui ne dort jamais, près des bornes, tourné vers le spawn
	do
		local at = Vector3.new(-95, 0, -332)
		local cf = facing(at, SPAWN - at)
		local npc = robot(folder, "ServiceNpc", cf, Color3.fromRGB(43, 43, 43), VIOLET)
		local body = npc:FindFirstChild("Body") :: BasePart
		Build.Prompt(body, "Parler", "Le Service · support", "Talk", 12)
		local plate = Box(folder, "ServiceSign", Vector3.new(7, 2.4, 0.3), cf * CFrame.new(0, 8.2, 0), C.Bg, SMOOTH)
		Props.Sign(plate, "LE SERVICE", "24 h/24 · ne dort jamais", VIOLET, C.White)
		Build.Neon({
			Name = "ServiceRing",
			Size = Vector3.new(5, 0.2, 5),
			CFrame = cf * CFrame.new(0, 0.1, 0),
			Color = VIOLET,
			Transparency = 0.5,
			Parent = folder,
		})
	end

	-- 3. Le pseudo en néon : panneau tourné vers le spawn (texte posé par le client, tag NeonName)
	do
		local at = Vector3.new(-30, 0, -440)
		local cf = facing(at, Vector3.zAxis)
		Box(folder, "NeonFrame", Vector3.new(44, 15, 1.2), cf * CFrame.new(0, 9, 0.5), C.MetalDark, METAL)
		local wall = Build.Part({
			Name = "NeonName",
			Size = Vector3.new(42, 13, 0.4),
			CFrame = cf * CFrame.new(0, 9, -0.3),
			Color = C.Bg,
			Material = SMOOTH,
			Tags = { "NeonName" },
			Parent = folder,
		})
		wall.CanCollide = false
		wall.CastShadow = false
		for _, side in { -1, 1 } do
			Rod(
				folder,
				"NeonPost",
				cf * CFrame.new(side * 20, 1.5, 0.5) * CFrame.Angles(0, 0, math.pi / 2),
				3,
				1.2,
				C.MetalDark,
				METAL
			)
		end
	end

	-- 4. La touche Suppr (entrée du BIOS caché), le BIOS lui-même, et les touches du Stream Deck
	biosEntry(folder)
	biosRoom(tower)
	streamDeckKeys(lobby)
end

------------------------------------------------------------------------------------
-- Salles de terminal des mondes (repère de la salle : u le long de F, v le long de R ;
-- pad en (0, 0), console en (12, -36), écran sur le mur v = -44, rampe vers u = 30..44)
------------------------------------------------------------------------------------

local function corbeille(ctx: Common.WorldContext, folder: Instance, fr: Common.Frame, y: number)
	local cf = facing(P(fr, 22, y, 2), -fr.F)
	local bin = Build.Part({
		Name = "Corbeille",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 9, 9),
		CFrame = cf * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(64, 68, 82),
		Material = SMOOTH,
		Parent = folder,
	})
	bin.CanCollide = true
	Box(folder, "BinRim", Vector3.new(9.6, 0.6, 9.6), cf * CFrame.new(0, 9, 0), C.MetalLight, METAL)
	local plate = Box(folder, "BinSign", Vector3.new(7, 2.4, 0.3), cf * CFrame.new(0, 11.4, 0), C.Bg, SMOOTH)
	Props.Sign(plate, "CORBEILLE", "3 éléments · vider ?", ctx.Style.Primary, C.White)
	-- Fichiers célèbres qui dépassent de la corbeille
	type File = { Name: string, Color: Color3, Yaw: number }
	local files: { File } = {
		{ Name = "devoirs_finaux_VRAIMENT_FINAL_v3.docx", Color = C.White, Yaw = 0 },
		{ Name = "screenshot_win_ranked.png", Color = Color3.fromRGB(170, 210, 255), Yaw = 0.5 },
		{ Name = "RAM_download_2go.exe", Color = Common.Colors.Lethal, Yaw = -0.5 },
	}
	for index, file in files do
		local tilt = CFrame.Angles(0, file.Yaw, math.rad(12 * (index - 2)))
		local sheet = Box(
			folder,
			"File",
			Vector3.new(4.2, 5.4, 0.25),
			cf * CFrame.new((index - 2) * 2.2, 10.2, (index - 2) * 0.8) * tilt,
			file.Color,
			SMOOTH
		)
		Props.Sign(sheet, file.Name, if index == 3 then "⚠ c'est lui, le virus" else "supprimé", C.Black, C.Black)
	end
end

local function thermalPaste(folder: Instance, fr: Common.Frame, y: number, accent: Color3)
	local cf = facing(P(fr, 24, y, -26), -fr.F)
	local tube = Build.Part({
		Name = "PasteTube",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 2.2, 2.2),
		CFrame = cf * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(20)),
		Color = C.MetalLight,
		Material = SMOOTH,
		Parent = folder,
	})
	tube.CanCollide = false
	Rod(folder, "PasteCap", cf * CFrame.new(-2.6, 2.0, 0) * CFrame.Angles(0, 0, math.rad(20)), 1.2, 1, accent, SMOOTH)
	local plate = Box(folder, "PasteSign", Vector3.new(6, 2, 0.3), cf * CFrame.new(0, 5, 0), C.Bg, SMOOTH)
	Props.Sign(plate, "PÂTE THERMIQUE", "un grain de riz suffit", accent, C.White)
	Build.Prompt(tube, "Appliquer", "Pâte thermique premium", "Paste", 12)
end

local function rgbSwitch(folder: Instance, fr: Common.Frame, y: number, accent: Color3)
	-- Boîtier sur le mur intérieur (v = 7), tourné vers la salle (-R)
	local cf = facing(P(fr, 24, y + 5, 6.4), -fr.R)
	local box = Build.Part({
		Name = "RgbSwitch",
		Size = Vector3.new(3, 4, 1.2),
		CFrame = cf,
		Color = C.MetalDark,
		Material = METAL,
		Parent = folder,
	})
	box.CanCollide = false
	Box(
		folder,
		"RgbLever",
		Vector3.new(0.8, 1.6, 0.6),
		cf * CFrame.new(0, -0.4, -0.8) * CFrame.Angles(math.rad(-25), 0, 0),
		accent,
		NEON
	)
	local plate = Box(folder, "RgbSign", Vector3.new(7, 2.4, 0.3), cf * CFrame.new(0, 3.6, 0.2), C.Bg, SMOOTH)
	Props.Sign(plate, "RGB = +10 FPS", "c'est scientifique", accent, C.White)
	Build.Prompt(box, "Activer", "Interrupteur RGB", "Rgb", 12)
end

local function snail(ctx: Common.WorldContext, folder: Instance, fr: Common.Frame, y: number)
	local cf = facing(P(fr, 18, y, -12), fr.F)
	local root = Build.Part({
		Name = "Snail",
		Size = Vector3.new(2.4, 1.4, 5),
		CFrame = cf * CFrame.new(0, 0.7, 0),
		Color = Color3.fromRGB(196, 150, 110),
		Material = SMOOTH,
		Parent = folder,
	})
	Common.Attach(
		root,
		"Shell",
		Vector3.new(3.4, 3.4, 3.4),
		cf * CFrame.new(0, 2.4, 0.8),
		Color3.fromRGB(120, 86, 60),
		SMOOTH
	)
	for _, side in { -1, 1 } do
		Common.Attach(
			root,
			"Eyestalk",
			Vector3.new(0.3, 1.6, 0.3),
			cf * CFrame.new(side * 0.6, 2.1, -2.2),
			Color3.fromRGB(196, 150, 110),
			SMOOTH
		)
		Common.Attach(root, "Eye", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(side * 0.6, 3.0, -2.2), C.Black, SMOOTH)
	end
	-- Les paquets réseau sur sa coquille
	for index = 1, 2 do
		local packet = Common.Attach(
			root,
			"Packet",
			Vector3.new(1.3, 1.3, 1.3),
			cf * CFrame.new((index - 1.5) * 1.5, 4.7, 0.8),
			SAFE,
			NEON
		)
		Props.Sign(packet, "PKT", nil, C.Black)
	end
	-- Transporteur très lent : aller-retour de 7 studs en 16 s
	ctx.Trap("Mover", root, { Offset = fr.F * 7, Period = 16, Phase = 0 })
	local plate = Box(folder, "SnailSign", Vector3.new(8, 2.4, 0.3), cf * CFrame.new(0, 7.2, 0), C.Bg, SMOOTH)
	Props.Sign(plate, "WI-FI DE L'HÔTEL", "ping 999 ms · paquets en route", ctx.Style.Primary, C.White)
end

local function hiddenDev(folder: Instance, fr: Common.Frame, roof: number, accent: Color3)
	local at = P(fr, 26, roof, 4)
	local cf = facing(at, P(fr, 11, roof, -18) - at) -- tourné vers le cœur du virus vaincu
	local dev = human(folder, "AngaTvDev", cf, Color3.fromRGB(32, 34, 44), Color3.fromRGB(240, 86, 91))
	local body = dev:FindFirstChild("Body") :: BasePart
	Build.Prompt(body, "Parler", "AngATV", "Dev", 12)
	local plate = Box(folder, "DevSign", Vector3.new(5, 1.6, 0.3), cf * CFrame.new(0, 7.4, 0), C.Bg, SMOOTH)
	Props.Sign(plate, "AngATV", "le dev", accent, C.White)
end

function EasterEggs.BuildWorld(ctx: Common.WorldContext)
	local room = ctx.Model:FindFirstChild("Terminal")
	if not room then
		return
	end
	local folder = Build.Folder("EasterEggs", room)
	folder:SetAttribute("Stage", Tower.TerminalStage(ctx.Index)) -- étape de la salle (tests : pad le plus proche)
	local fr, floor, roof = ctx.Terminal.Frame, ctx.Terminal.Floor, ctx.Terminal.Roof
	local accent = ctx.Style.Primary
	if ctx.Index == 3 then
		corbeille(ctx, folder, fr, floor)
	elseif ctx.Index == 5 then
		thermalPaste(folder, fr, floor, accent)
	elseif ctx.Index == 6 then
		rgbSwitch(folder, fr, floor, accent)
	elseif ctx.Index == Tower.WORLD_COUNT then
		snail(ctx, folder, fr, floor)
		hiddenDev(folder, fr, roof, accent)
	end
end

return EasterEggs
