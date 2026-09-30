--!strict
--[[
	W7Arena : l'arène du boss LAGZ (5ᵉ étape du monde 7 = étape 35), devant la porte de la salle
	du terminal final. Le combat lui-même est piloté par BossService (serveur) et BossController
	(client) ; ici, seulement la géométrie et les repères (voir aussi Util/BossLogic) :

	- Sol : dalles de 8 studs (disque d'environ 30 studs de rayon) ; dalles sûres fixes + dalles
	  « fragments » (pièges Vanish, actifs en phase 2 seulement).
	- Pièges de l'arène : passent tous par ctx.Trap (vérifiés par tower.spec) et portent en plus
	  BossPhases ("1", "2" ou "12" : phases où ils sont actifs pour le joueur local), Rest (CFrame
	  de repos, pour les remettre en place) et le tag BossTrap. Phase 1 : 2 lasers au ras du sol
	  (on saute par-dessus) + curseur géant ; phase 2 : fragments + 3 virus + curseur.
	- Repères : BossArena (boîte invisible = zone « dans l'arène »), BossPlug (3 prises antivirus,
	  attribut Index), BossBarrier (entrée / sortie, solides côté client pendant le combat),
	  BossLagz (modèle Lagz, animé par le client), BossShield (bouclier).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossLogic = require(Shared.Util.BossLogic)
local Common = require(script.Parent.Parent.Common)
local Build = require(script.Parent.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Parent.Props)
local ModelLibrary = require(script.Parent.Parent.Parent.ModelLibrary)

local Arena = {}

local C = Common.C
local Box = Props.Box
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local VERTICAL = Common.VERTICAL
local LETHAL = Common.Colors.Lethal
local GLITCH = Common.Colors.Glitch
local SAFE = Common.Colors.Safe

-- Géométrie (coordonnées absolues du monde 7 : sol de l'arène = plancher de la salle, 680).
local CENTER = Vector3.new(-48, 680, 64) -- centre du sol (dessus des dalles)
local PITCH, TILE = 8, 7.6
local LAGZ_BASE = CENTER + Vector3.new(0, 10, 0)

Arena.Center = CENTER
Arena.EntryPad = Vector3.new(CENTER.X, CENTER.Y, 22) -- dessus du checkpoint 34 (posé par W7)
Arena.Box = { Center = Vector3.new(-48, 690, 65), Size = Vector3.new(64, 28, 62) }

-- Dalles sûres (index de grille i, j ∈ -3..3) ; les autres sont des fragments en phase 2.
local SAFE_TILES = { "0,0", "0,-3", "3,-1", "-3,-1", "0,3", "-2,1", "2,1" }
-- Prises antivirus : dalle (i, j) de chacune.
local PLUGS = { { 3, -1 }, { -3, -1 }, { 0, 3 } }

local function tileCenter(i: number, j: number): Vector3
	return CENTER + Vector3.new(i * PITCH, 0, j * PITCH)
end

-- Piège de l'arène : ctx.Trap + phases actives + position de repos (BossController).
local function bossTrap(
	ctx: Common.WorldContext,
	kind: string,
	part: BasePart,
	phases: string,
	attributes: { [string]: any }
)
	attributes.BossPhases = phases
	attributes.Rest = part.CFrame
	ctx.Trap(kind, part, attributes)
	part:AddTag("BossTrap")
end

-- Repère invisible, sans collision ni requête.
local function marker(parent: Instance, name: string, size: Vector3, cf: CFrame, tag: string): Part
	return Build.Decor({
		Name = name,
		Size = size,
		CFrame = cf,
		Transparency = 1,
		CastShadow = false,
		Tags = { tag },
		Parent = parent,
	})
end

------------------------------------------------------------------------------------
-- LAGZ (décor de secours en primitives : blob violet glitché, yeux pixels, couronne)
------------------------------------------------------------------------------------

local function lagzFallback(cf: CFrame): Model
	local model = Build.Model("Lagz")
	local body = Build.Decor({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 10,
		CFrame = cf * CFrame.new(0, 5, 0),
		Color = Color3.fromHex("9F7AEA"),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	model.PrimaryPart = body
	-- Tranches glitchées (magenta / cyan décalées)
	for k, slice in
		{
			{ Y = 2.2, X = 0.9, Color = GLITCH },
			{ Y = 5.6, X = -0.8, Color = C.Cyan },
			{ Y = 7.6, X = 0.6, Color = GLITCH },
		}
	do
		Box(model, `Glitch{k}`, Vector3.new(9.2, 0.9, 8.6), cf * CFrame.new(slice.X, slice.Y, 0), slice.Color, NEON)
	end
	-- Yeux en pixels (face -Z = avant du modèle) et bouche en dents de scie
	for _, x in { -2, 2 } do
		Box(model, "Eye", Vector3.new(2.4, 2.4, 0.6), cf * CFrame.new(x, 6.2, -4.3), C.White, NEON)
		Box(model, "Pupil", Vector3.new(1.1, 1.1, 0.3), cf * CFrame.new(x + 0.4, 5.9, -4.65), C.Black)
	end
	Box(model, "Mouth", Vector3.new(4.2, 0.8, 0.5), cf * CFrame.new(0, 3.4, -4.4), C.Black)
	for _, x in { -1.2, 1.2 } do
		Box(model, "Tooth", Vector3.new(0.7, 0.6, 0.3), cf * CFrame.new(x, 3.7, -4.7), C.White)
	end
	-- Couronne : roue de chargement (points de plus en plus pâles)
	for k = 0, 7 do
		local angle = k * math.pi / 4
		local dot = Build.Neon({
			Name = "Crown",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.3,
			CFrame = cf * CFrame.new(math.cos(angle) * 2.8, 11.2, math.sin(angle) * 2.8),
			Color = Color3.fromHex("F6E05E"),
			Parent = model,
		})
		dot.Transparency = k / 8 * 0.8
	end
	-- Petits bras en blob
	for _, x in { -5.6, 5.6 } do
		Build.Decor({
			Name = "Arm",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3,
			CFrame = cf * CFrame.new(x, 3.6, -0.6),
			Color = Color3.fromHex("805AD5"),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	model.WorldPivot = cf
	return model
end

-- Virus patrouilleur : boule mortelle (piège Virus) + habillage VirusBug soudé (il suit la boule).
-- `phases` : piège de l'arène, actif seulement pendant ces phases du combat.
function Arena.Virus(
	ctx: Common.WorldContext,
	parent: Instance,
	position: Vector3,
	waypoints: string,
	speed: number,
	phase: number,
	phases: string?
): Part
	local ball = Build.Part({
		Name = "Virus",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3.6,
		CFrame = CFrame.new(position),
		Color = GLITCH,
		Material = NEON,
		CastShadow = false,
		CanCollide = false,
		Parent = parent,
	})
	local attributes: { [string]: any } = { Waypoints = waypoints, Speed = speed, Phase = phase }
	if phases then
		bossTrap(ctx, "Virus", ball, phases, attributes)
	else
		ctx.Trap("Virus", ball, attributes)
	end
	local cf = ball.CFrame * CFrame.new(0, -ball.Size.Y / 2, 0)
	local look = ModelLibrary.Place("VirusBug", cf, ball, { Scale = 1 }, function()
		local model = Build.Model("VirusBug")
		for s = 0, 5 do
			local dir = if s < 2
				then CFrame.Angles(0, 0, s * math.pi)
				elseif s < 4 then CFrame.Angles(0, 0, math.pi / 2 + (s - 2) * math.pi)
				else CFrame.Angles(math.pi / 2 + (s - 4) * math.pi, 0, 0)
			Box(model, "Spike", Vector3.new(0.7, 1.6, 0.7), ball.CFrame * dir * CFrame.new(0, 2.2, 0), GLITCH, NEON)
		end
		for _, x in { -0.7, 0.7 } do
			Box(model, "Eye", Vector3.new(0.7, 0.7, 0.3), ball.CFrame * CFrame.new(x, 0.5, -1.75), C.White, NEON)
		end
		return model
	end)
	if look then
		for _, d in look:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				Props.WeldTo(ball, d)
			end
		end
	end
	return ball
end

------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------

function Arena.Build(ctx: Common.WorldContext)
	local w = ctx.Index
	local style = ctx.Style
	local stage = ctx.Stage(35)
	local boss = Build.Folder("Boss", ctx.Model)
	local decor = Build.Folder("ArenaDecor", ctx.Model)
	local top = CENTER.Y

	-- Zone « dans l'arène » (serveur) : boîte invisible
	marker(boss, "BossArena", Arena.Box.Size, CFrame.new(Arena.Box.Center), "BossArena")

	-- Pont d'entrée (depuis le pad 34) et palier de sortie (vers la porte de la salle)
	ctx.Platform(stage, Vector3.new(12, 2, 8.2), CFrame.new(CENTER.X, top - 1, 32.1), "ArenaGate")
	ctx.Platform(
		stage,
		Vector3.new(9.8, 2, 11.8),
		CFrame.new(-74.1, top - 1, 89.1) * CFrame.Angles(0, math.pi / 2, 0),
		"ArenaExit"
	)

	-- Dalles : sûres (fixes) ou fragments (Vanish, phase 2)
	local safe: { [string]: boolean } = {}
	for _, key in SAFE_TILES do
		safe[key] = true
	end
	for i = -3, 3 do
		for j = -3, 3 do
			if math.abs(i) == 3 and math.abs(j) == 3 then
				continue
			end
			local c = tileCenter(i, j)
			local cf = CFrame.new(c.X, top - 1, c.Z)
			if safe[`{i},{j}`] then
				local tile = ctx.Platform(stage, Vector3.new(TILE, 2, TILE), cf, "SafeTile")
				tile.Color = style.Floor:Lerp(C.MetalDark, 0.25)
			else
				local tile = Build.Part({
					Name = "Fragment",
					Size = Vector3.new(TILE, 2, TILE),
					CFrame = cf,
					Color = style.Floor:Lerp(style.Secondary, 0.35),
					Material = Enum.Material.SmoothPlastic,
					Parent = stage,
				})
				bossTrap(ctx, "Vanish", tile, "2", { Delay = 0.7, Respawn = 2.6 })
			end
		end
	end
	-- Socle de l'arène et anneau lumineux
	Build.Decor({
		Name = "ArenaBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 66, 66),
		CFrame = CFrame.new(CENTER.X, top - 4.6, CENTER.Z) * VERTICAL,
		Color = style.Wall,
		Material = METAL,
		Parent = decor,
	})
	Props.Ring(
		decor,
		"ArenaRim",
		CFrame.new(CENTER.X, top - 2.2, CENTER.Z) * VERTICAL,
		32.6,
		1,
		1.2,
		20,
		style.Primary,
		NEON
	)
	local alert = Props.Ring(
		decor,
		"ArenaAlert",
		CFrame.new(CENTER.X, top - 3.4, CENTER.Z) * VERTICAL,
		32.2,
		0.5,
		0.6,
		12,
		LETHAL:Lerp(C.White, 0.1),
		NEON
	)
	for _, part in alert do
		ctx.Infected(part)
	end

	-- Prises antivirus (boutons au sol) + borne décorative
	for index, spot in PLUGS do
		local c = tileCenter(spot[1], spot[2])
		local plug = Build.Neon({
			Name = `AntivirusPlug{index}`,
			Size = Vector3.new(5, 0.3, 5),
			CFrame = CFrame.new(c.X, top + 0.1, c.Z),
			Color = SAFE,
			Tags = { "BossPlug" },
			Parent = boss,
		})
		plug:SetAttribute("Index", index)
		plug:SetAttribute("World", w)
		Props.Decal(
			boss,
			"PlugLabel",
			Vector3.new(4, 0.1, 4),
			CFrame.new(c.X, top + 0.3, c.Z),
			`🔌{index}`,
			C.White,
			Enum.NormalId.Top,
			Enum.Font.GothamBlack
		)
		-- Borne : prise géante plantée au bord de la dalle, câble vers le sol
		local out = Vector3.new(c.X - CENTER.X, 0, c.Z - CENTER.Z).Unit
		local post = Vector3.new(c.X, top, c.Z) + out * 3.2
		Box(decor, "PlugPost", Vector3.new(1.6, 5, 1.6), CFrame.new(post + Vector3.new(0, 2.5, 0)), C.MetalDark, METAL)
		Box(decor, "PlugHead", Vector3.new(2.6, 1.6, 2.6), CFrame.new(post + Vector3.new(0, 5.6, 0)), SAFE, NEON)
	end

	-- Barrières (solides côté client pendant les phases 1–2 : l'arène se verrouille)
	for _, spec in
		{
			{ Name = "EntryBarrier", Size = Vector3.new(14, 12, 0.8), CFrame = CFrame.new(CENTER.X, top + 6, 32.4) },
			{ Name = "ExitBarrier", Size = Vector3.new(0.8, 12, 12), CFrame = CFrame.new(-79.4, top + 6, 88) },
		}
	do
		local barrier = marker(boss, spec.Name, spec.Size, spec.CFrame, "BossBarrier")
		barrier.Material = Enum.Material.ForceField
		barrier.Color = style.Secondary
		barrier:SetAttribute("World", w)
	end

	-- Phase 1 : lasers au ras du sol (on saute par-dessus), tirés par LAGZ
	for k, spec in
		{
			{
				Size = Vector3.new(60, 0.6, 0.6),
				CFrame = CFrame.new(CENTER.X, top + 1, 40),
				Offset = Vector3.new(0, 0, 48),
				Period = 6,
				Phase = 0,
			},
			{
				Size = Vector3.new(0.6, 0.6, 60),
				CFrame = CFrame.new(-72, top + 1, CENTER.Z),
				Offset = Vector3.new(48, 0, 0),
				Period = 6.8,
				Phase = 0.25,
			},
		}
	do
		local beam = Build.Part({
			Name = `LagzLaser{k}`,
			Size = spec.Size,
			CFrame = spec.CFrame,
			Color = LETHAL,
			Material = NEON,
			CastShadow = false,
			CanCollide = false,
			Parent = stage,
		})
		bossTrap(ctx, "Laser", beam, "1", { Offset = spec.Offset, Period = spec.Period, Phase = spec.Phase })
	end

	-- Phases 1–2 : curseur géant de LAGZ sur toute l'arène (préavis 1 s)
	local cursor = Build.Part({
		Name = "LagzCursor",
		Size = Vector3.one,
		CFrame = CFrame.new(CENTER.X, top + 6, CENTER.Z + 1),
		Color = LETHAL,
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = stage,
	})
	bossTrap(ctx, "Cursor", cursor, "12", { Period = 3.2, Radius = 4.5, Area = Vector3.new(64, 12, 62) })

	-- Phase 2 : virus qui sortent (boucle autour des prises + deux diagonales)
	for k, spec in
		{
			{ At = CENTER + Vector3.new(-16, 2, -16), Path = "0,0,0;32,0,0;32,0,32;0,0,32", Speed = 8, Phase = 0 },
			{ At = CENTER + Vector3.new(-20, 2, -20), Path = "0,0,0;40,0,40", Speed = 9, Phase = 0.25 },
			{ At = CENTER + Vector3.new(20, 2, -20), Path = "0,0,0;-40,0,40", Speed = 9, Phase = 0.75 },
		}
	do
		local ball = Arena.Virus(ctx, stage, spec.At, spec.Path, spec.Speed, spec.Phase, "2")
		ball.Name = `LagzVirus{k}`
	end

	-- LAGZ, flottant au-dessus du centre, tourné vers l'entrée (-Z), et son bouclier
	local lagzCf = CFrame.lookAt(LAGZ_BASE, LAGZ_BASE - Vector3.zAxis)
	local lagz = ModelLibrary.Place("Lagz", lagzCf, boss, { Name = "Lagz", Spin = false }, function()
		return lagzFallback(lagzCf)
	end)
	if lagz then
		lagz:AddTag("BossLagz")
		lagz:SetAttribute("World", w)
	end
	local shield = Build.Decor({
		Name = "LagzShield",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 19,
		CFrame = CFrame.new(LAGZ_BASE + Vector3.new(0, 5.5, 0)),
		Color = style.Primary,
		Material = Enum.Material.ForceField,
		Transparency = 0.1,
		CastShadow = false,
		Tags = { "BossShield" },
		Parent = boss,
	})
	shield:SetAttribute("World", w)
	-- Portail du cœur sous LAGZ (décor) : anneau et colonne de glitch
	ModelLibrary.Place("LagzPortalCore", CFrame.new(CENTER + Vector3.new(0, 0.2, 0)), decor, nil, function()
		local model = Build.Model("LagzPortalCore")
		Props.Ring(
			model,
			"CoreRing",
			CFrame.new(CENTER + Vector3.new(0, 0.25, 0)) * VERTICAL,
			3.4,
			0.5,
			0.2,
			10,
			GLITCH,
			NEON
		)
		local column = Build.Neon({
			Name = "CoreBeam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 1.2, 1.2),
			CFrame = CFrame.new(CENTER + Vector3.new(0, 5, 0)) * VERTICAL,
			Color = style.Secondary,
			Transparency = 0.45,
			Parent = model,
		})
		ctx.Infected(column)
		return model
	end)

	-- Panneau au fond de l'arène, face à l'entrée
	local signCf = CFrame.lookAt(CENTER + Vector3.new(0, 26, 34), CENTER + Vector3.new(0, 26, 0))
	local sign = Box(decor, "ArenaSign", Vector3.new(30, 6, 0.4), signCf, C.Bg, METAL)
	Props.Sign(sign, "REPAIRE DE LAGZ", "Survis · branche les 3 prises · terminal final", style.Primary, C.White)
	local clean = Box(decor, "ArenaSignClean", Vector3.new(30.4, 6.4, 0.3), signCf * CFrame.new(0, 0, 0.3), C.Bg, METAL)
	Props.Sign(clean, "LE PC TOURNE À 144 FPS !", "LAGZ est vaincu · le live peut commencer", SAFE, C.White)
	ctx.Cleaned(clean)
	ctx.Lamp(CENTER + Vector3.new(0, 22, 0), style.Primary:Lerp(C.White, 0.3), 1.6, 70, decor)

	-- Bits : sur les dalles sûres, le pont et le palier de sortie
	for _, p in
		{
			Vector3.new(CENTER.X, top + 2.5, 31),
			tileCenter(2, 1) + Vector3.new(0, 2.5, 0),
			tileCenter(-2, 1) + Vector3.new(0, 2.5, 0),
			tileCenter(0, -3) + Vector3.new(0, 2.5, 0),
			Vector3.new(-74, top + 2.5, 90),
		}
	do
		ctx.Coin(p, 35)
	end

	-- Cohérence avec la logique du combat (vérifiée à chaque construction, donc par tower.spec) :
	-- autant de prises que BossLogic en attend, toutes dans l'arène ; les deux checkpoints qui
	-- l'encadrent (34 à l'entrée, 35 dans la salle) hors de l'arène, pour ne jamais y réapparaître.
	assert(#PLUGS == BossLogic.PLUG_COUNT, "W7Arena : nombre de prises ≠ BossLogic.PLUG_COUNT")
	local box = Arena.Box
	for _, spot in PLUGS do
		local root = tileCenter(spot[1], spot[2]) + Vector3.new(0, 3, 0)
		assert(BossLogic.InArena(box.Center, box.Size, root), "W7Arena : prise hors de l'arène")
	end
	local door = ctx.Terminal.Door
	for _, pad in { Arena.EntryPad, door.Position + door.LookVector * 8 } do
		assert(
			not BossLogic.InArena(box.Center, box.Size, pad + Vector3.new(0, 3, 0)),
			"W7Arena : checkpoint dans l'arène"
		)
	end
	assert(
		BossLogic.InArena(box.Center, box.Size, CENTER + Vector3.new(0, 3, 0)),
		"W7Arena : le centre de l'arène doit être dans la zone de combat"
	)
end

return table.freeze(Arena)
