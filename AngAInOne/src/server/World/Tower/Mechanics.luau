--!strict
--[[
	Mechanics : les mécaniques « PC » de chaque monde, posées APRÈS le parcours (comme Bonus) :
	- Monde 1 et 7 · ENQUÊTES (Config/Puzzles) : une rangée de panneaux dans la salle du terminal, façon
	  page Démarrage / Sessions de jeu de l'app. Prompt « Désactiver » / « Quarantaine » sur chacun
	  (Action "Puzzle", attributs World + Item) ; le serveur (PuzzleService) vérifie la réponse.
	- Monde 2 · RAM SATURÉE : la jauge de RAM du joueur se remplit (client, Util/Gauges) et le ralentit
	  au sol ; trois gros boutons « Libérer la RAM » (Action "FlushRam") la vident.
	- Monde 4 · SURCHAUFFE : la jauge de chaleur monte quand on court ; à 100 °C, arrêt thermique.
	  Zones fraîches (tag CoolZone) : les 3 ventilateurs géants (toujours actifs) et 4 ventilateurs
	  encrassés à relancer (Action "FanStart", attribut NeedsStart). Plus le VENTILO PROPULSEUR : un
	  ventilateur couché (piège Bounce) à côté du checkpoint 17 qui fait décoller jusqu'à une corniche
	  à Bits bonus.
	- Monde 5 · BLOATWARE : trois programmes inutiles bloquent le passage (solides) ; prompt maintenu
	  « Désinstaller » (Action "Uninstall", attributs World + Index) : le client les retire localement,
	  le serveur donne quelques Bits la première fois.
	Les zones et prompts sont dans World{n}.Mechanics (attribut Stage sur chaque sous-dossier).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Puzzles = require(Shared.Config.Puzzles)
local Gauges = require(Shared.Util.Gauges)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local Common = require(script.Parent.Common)

local Mechanics = {}

local C = Props.C
local Box = Props.Box
local P = Common.P
local facing = Common.Facing
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic

local APP_ACCENT = Color3.fromHex("9B2FD4")
local APP_CARD = Color3.fromHex("2B2B2B")
local DANGER = Color3.fromHex("FF5A5F")

------------------------------------------------------------------------------------
-- Enquêtes (mondes 1 et 7)
------------------------------------------------------------------------------------

Mechanics.PANEL_SPACING = 4.4
Mechanics.PANEL_SIZE = Vector3.new(4, 5.4, 0.3)

local function puzzleRoom(ctx: Common.WorldContext, parent: Instance)
	local puzzle = Puzzles.ForWorld(ctx.Index)
	if not puzzle then
		return
	end
	local folder = Build.Folder("Puzzle", parent)
	folder:SetAttribute("Stage", Tower.TerminalStage(ctx.Index))
	local fr, y = ctx.Terminal.Frame, ctx.Terminal.Floor
	local count = #puzzle.Items
	local first = -4
	-- Bandeau de la page (comme le titre d'une page de l'app)
	local middle = first + Mechanics.PANEL_SPACING * (count - 1) / 2
	local header = Box(
		folder,
		"PuzzleHeader",
		Vector3.new(Mechanics.PANEL_SPACING * count, 2.4, 0.3),
		facing(P(fr, middle, y + 9.4, 6.6), -fr.R),
		APP_CARD,
		SMOOTH
	)
	Props.Sign(
		header,
		`{puzzle.Title} · {puzzle.Subtitle}`,
		"Enquête AngAInOne : trouve le coupable",
		APP_ACCENT,
		C.White
	)
	for index, item in puzzle.Items do
		local u = first + Mechanics.PANEL_SPACING * (index - 1)
		local cf = facing(P(fr, u, y + 2.2 + Mechanics.PANEL_SIZE.Y / 2, 6.6), -fr.R)
		local panel = Box(folder, "PuzzlePanel", Mechanics.PANEL_SIZE, cf, APP_CARD, SMOOTH)
		panel:AddTag("PuzzlePanel")
		panel:SetAttribute("World", ctx.Index)
		panel:SetAttribute("Item", item.Id)
		Props.Notice(panel, item.Name, table.concat(item.Lines, "\n"), APP_ACCENT)
		-- Interrupteur (levier) sous le panneau, comme le bouton Activé / Désactivé de la page
		local lever =
			Box(folder, "PuzzleLever", Vector3.new(1.6, 0.8, 0.4), cf * CFrame.new(0, -3.3, 0), C.Black, SMOOTH)
		Build.Neon({
			Name = "PuzzleLed",
			Size = Vector3.new(0.6, 0.4, 0.2),
			CFrame = lever.CFrame * CFrame.new(-0.4, 0, -0.25),
			Color = Color3.fromHex("6CCB5F"),
			Parent = folder,
		})
		local prompt = Build.Prompt(panel, puzzle.Action, item.Name, "Puzzle", 8)
		prompt:SetAttribute("World", ctx.Index)
		prompt:SetAttribute("Item", item.Id)
	end
end

------------------------------------------------------------------------------------
-- Monde 2 : gros boutons « Libérer la RAM »
------------------------------------------------------------------------------------

-- Emplacements (centre du dessus du palier) : palier d'arrivée, fin du bus de données, finale.
Mechanics.RAM_BUTTONS = {
	{ Stage = 6, At = Vector3.new(91, 110, -71) }, -- SlotLanding (x 82..94, z -80..-68)
	{ Stage = 7, At = Vector3.new(-29, 130.5, 51.5) }, -- BusJunction avant l'ascenseur (z 46..54)
	{ Stage = 10, At = Vector3.new(91, 169, -11) }, -- BusJunction de la finale (x 80..94)
}

local function ramButtons(ctx: Common.WorldContext, parent: Instance)
	for index, spot in Mechanics.RAM_BUTTONS do
		local folder = Build.Folder(`RamButton{index}`, parent)
		folder:SetAttribute("Stage", spot.Stage)
		local at = spot.At
		Props.Rod(
			folder,
			"RamButtonBase",
			CFrame.new(at + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			1,
			5,
			C.MetalDark,
			METAL
		)
		local cap = Props.Rod(
			folder,
			"RamButtonCap",
			CFrame.new(at + Vector3.new(0, 1.35, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			0.7,
			3.8,
			DANGER,
			NEON
		)
		cap:SetAttribute("Index", index)
		local sign = Box(
			folder,
			"RamButtonSign",
			Vector3.new(5.6, 2.2, 0.3),
			facing(at + Vector3.new(0, 3.4, 0), Vector3.zAxis) * CFrame.Angles(math.rad(-15), 0, 0),
			APP_CARD,
			SMOOTH
		)
		Props.Sign(sign, "LIBÉRER LA RAM", "appuie pour vider la mémoire", APP_ACCENT, C.White)
		local prompt = Build.Prompt(cap, "Libérer la RAM", "Mémoire saturée", "FlushRam", 10)
		prompt:SetAttribute("Index", index)
		prompt:SetAttribute("World", ctx.Index)
	end
end

------------------------------------------------------------------------------------
-- Monde 4 : zones fraîches, ventilateurs à relancer, ventilo propulseur
------------------------------------------------------------------------------------

-- Ventilateurs encrassés à relancer (au sol, sur un palier du parcours).
Mechanics.RESTART_FANS = {
	{ Stage = 16, At = Vector3.new(-70, 315, 8), Look = Vector3.xAxis }, -- Outlet, avant le checkpoint 16
	{ Stage = 17, At = Vector3.new(56, 328, 13), Look = -Vector3.zAxis }, -- TubeTop, fin du tube
	{ Stage = 19, At = Vector3.new(15, 349, -107), Look = Vector3.zAxis }, -- Shelter de la chambre froide
	{ Stage = 20, At = Vector3.new(-79, 367, -35), Look = -Vector3.xAxis }, -- Plenum de la sortie d'air
}
-- Zones fraîches toujours actives : les trois ventilateurs géants de l'étape 3 (dessus des FanDeck).
Mechanics.GIANT_FANS = {
	Vector3.new(47, 333, -22),
	Vector3.new(47, 336, -48),
	Vector3.new(47, 339, -74),
}
-- Ventilo propulseur (à côté du checkpoint 17, côté -X) : plateforme, ventilateur couché, corniche.
Mechanics.LAUNCH = {
	Stage = 17,
	Deck = { X0 = 20, X1 = 38, Z0 = -14, Z1 = -2, Top = 332 },
	Pad = Vector3.new(34, 332, -8), -- centre du dessus du ventilateur couché
	PadSize = 6,
	Power = 95, -- vitesse verticale (≈ 23 studs de haut)
	Ledge = { X0 = 20, X1 = 28, Z0 = -14, Z1 = -2, Top = 352 },
}

local function coolZone(parent: Instance, position: Vector3, needsStart: boolean): Part
	local zone = Build.Decor({
		Name = "CoolZone",
		Size = Vector3.one,
		CFrame = CFrame.new(position + Vector3.new(0, 3, 0)),
		Color = C.Cyan,
		Parent = parent,
	})
	zone.Transparency = 1
	zone:AddTag("CoolZone")
	zone:SetAttribute("Radius", Gauges.COOL_ZONE_RADIUS)
	zone:SetAttribute("NeedsStart", needsStart)
	return zone
end

-- Ventilateur de boîtier debout (primitives) : cadre, moyeu, 5 pales (« Blade ») ; encrassé de poussière.
local function restartFan(parent: Instance, at: Vector3, look: Vector3, index: number)
	local folder = Build.Folder(`FanUnit{index}`, parent)
	local cf = facing(at, look) * CFrame.new(0, 4.6, 0)
	local housing = Box(folder, "FanHousing", Vector3.new(8, 8, 1.6), cf, C.Black, METAL)
	housing:SetAttribute("Index", index)
	for _, side in { -1, 1 } do
		Box(folder, "FanFoot", Vector3.new(1.4, 1, 3), cf * CFrame.new(side * 3, -4.1, 0), C.MetalDark, METAL)
	end
	local hub = Props.Rod(
		folder,
		"FanHub",
		cf * CFrame.new(0, 0, -0.9) * CFrame.Angles(0, math.pi / 2, 0),
		0.6,
		2,
		C.MetalLight,
		METAL
	)
	hub:SetAttribute("Spin", 0) -- tours / s, piloté par le client une fois relancé
	for k = 0, 4 do
		local angle = k * math.pi * 2 / 5
		local blade = Box(
			folder,
			"Blade",
			Vector3.new(1.2, 3.2, 0.2),
			cf
				* CFrame.new(0, 0, -0.95)
				* CFrame.Angles(0, 0, angle)
				* CFrame.new(0, 2, 0)
				* CFrame.Angles(0, math.rad(20), 0),
			Color3.fromRGB(60, 64, 76),
			SMOOTH
		)
		blade:SetAttribute("Angle", angle)
	end
	-- Poussière (retirée par le client quand le ventilateur est relancé)
	for k = 1, 4 do
		local dust = Box(
			folder,
			"FanDust",
			Vector3.new(2.2, 1.2, 0.6),
			cf * CFrame.new((k - 2.5) * 1.6, ((k % 2) - 0.5) * 3, -1.2) * CFrame.Angles(0, 0, k * 0.7),
			Color3.fromRGB(150, 140, 120),
			Enum.Material.Sand
		)
		dust.Transparency = 0.1
	end
	local led = Build.Neon({
		Name = "FanLed",
		Size = Vector3.new(0.6, 0.6, 0.2),
		CFrame = cf * CFrame.new(3.2, 3.2, -0.85),
		Color = DANGER,
		Parent = folder,
	})
	led:SetAttribute("Index", index)
	local prompt = Build.Prompt(housing, "Relancer", "Ventilateur encrassé", "FanStart", 10)
	prompt:SetAttribute("Index", index)
	prompt.HoldDuration = 0.6
	local zone = coolZone(folder, at, true)
	zone:SetAttribute("Index", index)
end

local function launchFan(ctx: Common.WorldContext, parent: Instance)
	local spec = Mechanics.LAUNCH
	local folder = Build.Folder("LaunchFan", parent)
	folder:SetAttribute("Stage", spec.Stage)
	local style = ctx.Style
	local function deck(rect: { X0: number, X1: number, Z0: number, Z1: number, Top: number }, name: string): Part
		local size = Vector3.new(rect.X1 - rect.X0, 2, rect.Z1 - rect.Z0)
		local center = Vector3.new((rect.X0 + rect.X1) / 2, rect.Top - 1, (rect.Z0 + rect.Z1) / 2)
		return ctx.Platform(folder, size, CFrame.new(center), name)
	end
	deck(spec.Deck, "LaunchDeck")
	deck(spec.Ledge, "LaunchLedge")
	-- Ventilateur couché : le dessus est un pad Bounce, encadré de métal, pales visibles en dessous
	local s = spec.PadSize
	local padCf = CFrame.new(spec.Pad + Vector3.new(0, 0.4, 0))
	local pad = Build.Part({
		Name = "LaunchPad",
		Size = Vector3.new(s, 0.8, s),
		CFrame = padCf,
		Color = C.Cyan,
		Material = SMOOTH,
		CastShadow = false,
		Parent = folder,
	})
	pad.Transparency = 0.35
	ctx.Trap("Bounce", pad, { Power = spec.Power })
	pad:SetAttribute("Stage", spec.Stage)
	for _, side in { -1, 1 } do
		Box(
			folder,
			"LaunchFrame",
			Vector3.new(s + 1, 1, 0.8),
			padCf * CFrame.new(0, 0.1, side * (s / 2 + 0.4)),
			C.Black,
			METAL
		)
		Box(
			folder,
			"LaunchFrame",
			Vector3.new(0.8, 1, s + 1),
			padCf * CFrame.new(side * (s / 2 + 0.4), 0.1, 0),
			C.Black,
			METAL
		)
	end
	local spin = Props.SpinHub(folder, padCf * CFrame.new(0, -0.2, 0), "Y", 4)
	for k = 0, 2 do
		local blade = Box(
			folder,
			"LaunchBlade",
			Vector3.new(s - 1.2, 0.15, 1),
			padCf * CFrame.new(0, -0.2, 0) * CFrame.Angles(0, k * math.pi / 3, 0),
			C.MetalLight,
			SMOOTH
		)
		Props.WeldTo(spin, blade)
	end
	Build.Neon({
		Name = "LaunchGlow",
		Size = Vector3.new(s - 0.6, 0.2, s - 0.6),
		CFrame = padCf * CFrame.new(0, -0.35, 0),
		Color = C.Cyan,
		Parent = folder,
	}).Transparency =
		0.5
	-- Panneau d'avertissement
	local sign = Box(
		folder,
		"LaunchSign",
		Vector3.new(7, 2.4, 0.3),
		facing(Vector3.new(25, spec.Deck.Top + 3.4, -2.6), -Vector3.zAxis),
		APP_CARD,
		SMOOTH
	)
	Props.Sign(sign, "VENTILO PROPULSEUR", "monte dessus · atterris sur la corniche", APP_ACCENT, C.White)
	-- Bits bonus sur la corniche (Méga-Bit au centre) et zone fraîche du ventilateur
	local ledge = spec.Ledge
	local cz = (ledge.Z0 + ledge.Z1) / 2
	ctx.Coin(Vector3.new(24, ledge.Top + 2.5, cz), spec.Stage, { Value = 5, Bonus = true })
	ctx.Coin(Vector3.new(24, ledge.Top + 2.5, ledge.Z0 + 2), spec.Stage, { Bonus = true })
	ctx.Coin(Vector3.new(24, ledge.Top + 2.5, ledge.Z1 - 2), spec.Stage, { Bonus = true })
	coolZone(folder, spec.Pad, false)
	ctx.Lamp(Vector3.new(29, ledge.Top + 8, cz), style.Primary:Lerp(C.White, 0.4), 1, 40)
end

local function coolingWorld(ctx: Common.WorldContext, parent: Instance)
	local fans = Build.Folder("Fans", parent)
	for index, spec in Mechanics.RESTART_FANS do
		restartFan(fans, spec.At, spec.Look, index)
		local unit = fans:FindFirstChild(`FanUnit{index}`)
		if unit then
			unit:SetAttribute("Stage", spec.Stage)
		end
	end
	local giants = Build.Folder("GiantFans", parent)
	giants:SetAttribute("Stage", 18)
	for _, at in Mechanics.GIANT_FANS do
		coolZone(giants, at, false)
	end
	launchFan(ctx, parent)
end

------------------------------------------------------------------------------------
-- Monde 5 : bloatware à désinstaller
------------------------------------------------------------------------------------

Mechanics.BLOATWARE = {
	{
		Stage = 21,
		Name = "Barre d'outils Super-Recherche",
		Detail = "s'installe toute seule · 0 utilité",
		Center = Vector3.new(-16, 418.5, -77), -- passerelle VRM (lane x -20.5..-11.5)
		Size = Vector3.new(10, 8, 2.5),
		Look = -Vector3.zAxis,
	},
	{
		Stage = 24,
		Name = "Optimiseur 3000 GRATUIT",
		Detail = "« ton PC est lent ! » (c'est lui)",
		Center = Vector3.new(12, 464, -47), -- grille de broches (x 4..20)
		Size = Vector3.new(17, 8, 2.5),
		Look = Vector3.zAxis,
	},
	{
		Stage = 25,
		Name = "Coupons Express Assistant",
		Detail = "pop-up · traqueur · lance au démarrage",
		-- seuil devant la porte (z -96..-80) ; 8 de haut : on ne saute pas par-dessus (saut 7,2), et le
		-- dessus reste sous la bande du vide du monde 6 (test « vide »)
		Center = Vector3.new(75.75, 484, -88),
		Size = Vector3.new(2.5, 8, 17),
		Look = -Vector3.xAxis,
	},
}
Mechanics.UNINSTALL_BITS = 3

local function bloatware(ctx: Common.WorldContext, parent: Instance)
	for index, spec in Mechanics.BLOATWARE do
		local folder = Build.Folder(`Bloatware{index}`, parent)
		folder:SetAttribute("Stage", spec.Stage)
		-- Bloc solide : la fenêtre d'installation du programme, en travers du chemin
		local wide = spec.Size.X >= spec.Size.Z
		local across = if wide then spec.Size.X else spec.Size.Z
		local cf = facing(spec.Center, spec.Look)
		local block = Build.Part({
			Name = "BloatwareBlock",
			Size = Vector3.new(across, spec.Size.Y, math.min(spec.Size.X, spec.Size.Z)),
			CFrame = cf,
			Color = Color3.fromHex("3A3A3A"),
			Material = SMOOTH,
			Parent = folder,
		})
		block:AddTag("Bloatware")
		block:SetAttribute("World", ctx.Index)
		block:SetAttribute("Index", index)
		block:SetAttribute("Program", spec.Name)
		Props.Notice(
			block,
			`📦 {spec.Name}`,
			`{spec.Detail}\n\nInstallation : 99 %\nDésinstaller ? Oui, évidemment.`,
			DANGER
		)
		Build.Neon({
			Name = "BloatwareEdge",
			Size = Vector3.new(across + 0.2, 0.3, 0.3),
			CFrame = cf * CFrame.new(0, spec.Size.Y / 2 + 0.1, 0),
			Color = DANGER,
			Parent = folder,
		})
		local prompt = Build.Prompt(block, "Désinstaller", spec.Name, "Uninstall", 12)
		prompt.HoldDuration = 0.8
		prompt:SetAttribute("World", ctx.Index)
		prompt:SetAttribute("Index", index)
	end
end

------------------------------------------------------------------------------------

function Mechanics.Build(ctx: Common.WorldContext)
	local w = ctx.Index
	if not (Puzzles.ForWorld(w) or w == 2 or w == 4 or w == 5) then
		return
	end
	local folder = Build.Folder("Mechanics", ctx.Model)
	if Puzzles.ForWorld(w) then
		local room = ctx.Model:FindFirstChild("Terminal")
		puzzleRoom(ctx, room or folder)
	end
	if w == 2 then
		ramButtons(ctx, folder)
	elseif w == 4 then
		coolingWorld(ctx, folder)
	elseif w == 5 then
		bloatware(ctx, folder)
	end
end

return Mechanics
