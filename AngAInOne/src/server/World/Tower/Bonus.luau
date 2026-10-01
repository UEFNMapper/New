--!strict
--[[
	Bonus : les détours « Ventilo bonus », un par monde (table SPECS) : courts, OPTIONNELS et plus
	lucratifs que le chemin principal.

	Une passerelle étroite part d'un pad de checkpoint (sur le côté ou vers l'arrière, jamais vers
	l'étape suivante), traverse un ventilateur de boîtier dressé (cadre `Fan140`, vrai modèle ou
	secours) dont les pales (SpinBar, rouges, mortelles) balaient l'ouverture autour de l'axe de la
	passerelle, et finit sur une plateforme avec un MÉGA-BIT (5 Bits) et deux Bits sur le chemin :
	7 Bits pour un détour, contre 4 par étape sur le parcours. Cul-de-sac : il faut retraverser les
	pales pour revenir. Un panneau « BONUS » le signale au pied du pad.

	Contrat :
	- World{n}.Bonus (Model) : tag BonusRoute, attributs World, Stage, Bits (valeur totale) ;
	- ses Bits portent Bonus = true (hors du compte des 3–6 Bits par étape), le Méga-Bit Value = 5 ;
	- les pales sont des pièges SpinBar classiques (Axis "Z" = axe de la passerelle, Speed rad/s).
	Construit par TowerBuilder après le module du monde (ctx.CheckpointAt donne le pad).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local Common = require(script.Parent.Common)
local ModelLibrary = require(script.Parent.Parent.ModelLibrary)

local Bonus = {}

local C = Props.C
local LETHAL = Common.Colors.Lethal
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

export type Spec = {
	Stage: number, -- checkpoint de départ
	Direction: Vector3, -- direction horizontale de la passerelle (vers une zone libre)
	Start: number?, -- distance du centre du pad au début de la passerelle (défaut 7)
	Cross: boolean?, -- pales en croix (4 bras) au lieu d'une barre (2 bras)
	Speed: number?, -- vitesse de rotation des pales (rad/s)
}

-- Un détour par monde, dans l'espace libre de chaque monde : `lune run tests/tools/BonusSpots.luau`
-- liste les directions possibles autour de chaque checkpoint (empreinte réelle du détour, sans
-- traverser le décor) ; tests/tower.spec (détours bonus) le vérifie.
local SPECS: { [number]: Spec } = {
	[1] = { Stage = 4, Direction = -Vector3.xAxis, Speed = 0.9 }, -- au-dessus de la grille du ventilateur
	[2] = { Stage = 8, Direction = Vector3.zAxis, Speed = 1.0 }, -- derrière le pad 8
	[3] = { Stage = 12, Direction = Vector3.xAxis, Speed = 1.0 },
	[4] = { Stage = 19, Direction = Vector3.xAxis, Cross = true, Speed = 0.8 },
	[5] = { Stage = 22, Direction = Vector3.xAxis, Start = 13, Cross = true, Speed = 0.85 },
	[6] = { Stage = 29, Direction = -Vector3.xAxis, Start = 13, Cross = true, Speed = 0.9 },
	[7] = { Stage = 33, Direction = Vector3.zAxis, Cross = true, Speed = 1.0 },
}

Bonus.WALK_WIDTH = 5
Bonus.FAN_AT = 22 -- centre du ventilateur, depuis le centre du pad
Bonus.FAN_DIAMETER = 24
Bonus.FAN_LIFT = 8 -- centre du ventilateur au-dessus de la passerelle (ouverture ≈ 21 studs)
Bonus.LANDING_AT = 51 -- centre de la plateforme d'arrivée
Bonus.MEGA_VALUE = 5
Bonus.TOTAL_BITS = Bonus.MEGA_VALUE + 2

function Bonus.Spec(world: number): Spec?
	return SPECS[world]
end

-- Cadre de ventilateur dressé, axe = LookVector de `cf` (centre du cadre), diamètre `diameter`.
local function fanFrame(parent: Instance, cf: CFrame, diameter: number, accent: Color3)
	-- Modèle à plat (épaisseur Y) : dressé face à la passerelle ; Height = diamètre monde.
	local standing = cf * CFrame.Angles(math.pi / 2, 0, 0)
	ModelLibrary.Place("Fan140", standing, parent, { Height = diameter, Spin = "Hide", Name = "FanFrame" }, function()
		local model = Build.Model("FanFrame", parent)
		local half = diameter * 0.54
		for _, side in { -1, 1 } do
			Props.Box(
				model,
				"FrameSide",
				Vector3.new(2, diameter * 1.08, 3),
				cf * CFrame.new(side * half, 0, 0),
				C.Black,
				METAL
			)
			Props.Box(
				model,
				"FrameBar",
				Vector3.new(diameter * 1.08, 2, 3),
				cf * CFrame.new(0, side * half, 0),
				C.Black,
				METAL
			)
		end
		-- Anneau lumineux dans le plan du cadre (axe de Props.Ring = X local : on tourne Z → X)
		Props.Ring(model, "FanRing", cf * CFrame.Angles(0, math.pi / 2, 0), diameter / 2, 0.8, 0.5, 16, accent, NEON)
		return model
	end)
end

-- Construit le détour du monde `ctx.Index` s'il en a un.
function Bonus.Build(ctx: Common.WorldContext)
	local spec = SPECS[ctx.Index]
	if not spec then
		return
	end
	local pad = ctx.CheckpointAt(spec.Stage)
	assert(pad, `monde {ctx.Index} : détour bonus sur le checkpoint {spec.Stage}, qui n'existe pas`)
	local w = ctx.Index
	local style = ctx.Style
	local origin = pad.Position -- centre du dessus du pad
	local direction = Vector3.new(spec.Direction.X, 0, spec.Direction.Z).Unit
	-- Repère du détour : LookVector = direction ; les points du parcours sont en z négatif.
	local frame = CFrame.fromMatrix(origin, direction:Cross(Vector3.yAxis), Vector3.yAxis, -direction)
	local function at(distance: number, lift: number): CFrame
		return frame * CFrame.new(0, lift, -distance)
	end

	local model = Build.Model("Bonus", ctx.Model)
	model:AddTag("BonusRoute")
	model:SetAttribute("World", w)
	model:SetAttribute("Stage", spec.Stage)
	model:SetAttribute("Bits", Bonus.TOTAL_BITS)

	-- Passerelle (du bord du pad à la plateforme d'arrivée) et plateforme d'arrivée
	local start = spec.Start or 7
	local walkEnd = Bonus.LANDING_AT - 6
	local length = walkEnd - start
	ctx.Platform(model, Vector3.new(Bonus.WALK_WIDTH, 1, length), at((start + walkEnd) / 2, -0.5), "BonusWalk")
	ctx.Platform(model, Vector3.new(12, 1, 12), at(Bonus.LANDING_AT, -0.5), "BonusLanding")

	-- Ventilateur : cadre dressé autour de la passerelle, pales mortelles qui tournent autour de son axe
	local fanCf = at(Bonus.FAN_AT, Bonus.FAN_LIFT)
	fanFrame(model, fanCf, Bonus.FAN_DIAMETER, style.Primary)
	local arms = if spec.Cross then 2 else 1
	for k = 1, arms do
		local blade = Build.Part({
			Name = "FanBlade",
			Size = Vector3.new(Bonus.FAN_DIAMETER * 0.86, 1.6, 1),
			CFrame = fanCf * CFrame.Angles(0, 0, (k - 1) * math.pi / 2),
			Color = LETHAL,
			Material = NEON,
			CastShadow = false,
			Parent = model,
		})
		blade.CanCollide = false
		blade.CanQuery = false
		-- Rotation autour de l'axe Z local (= axe de la passerelle), même phase : une croix rigide
		ctx.Trap("SpinBar", blade, { Speed = spec.Speed or 1, Axis = "Z", Phase = 0 })
	end
	Props.Box(model, "FanHub", Vector3.new(2.6, 2.6, 1.4), fanCf, C.MetalDark, METAL)

	-- Récompenses : deux Bits après les pales, le Méga-Bit sur la plateforme d'arrivée
	ctx.Coin(at(Bonus.FAN_AT + 8, 2.6).Position, spec.Stage, { Bonus = true })
	ctx.Coin(at(Bonus.FAN_AT + 16, 2.6).Position, spec.Stage, { Bonus = true })
	ctx.Coin(at(Bonus.LANDING_AT, 3.4).Position, spec.Stage, { Bonus = true, Value = Bonus.MEGA_VALUE })

	-- Panneau « BONUS » au départ, en bord de passerelle, tourné vers le pad
	local sign = Props.Box(
		model,
		"BonusSign",
		Vector3.new(6, 3.2, 0.4),
		at(start + 3, 4.2) * CFrame.new(Bonus.WALK_WIDTH / 2 + 3.6, 0, 0) * CFrame.Angles(0, math.pi, 0),
		C.Bg,
		Enum.Material.SmoothPlastic
	)
	Props.Sign(sign, "BONUS", `Ventilo · +{Bonus.TOTAL_BITS} Bits`, style.Primary, C.White)
	Props.Box(
		model,
		"SignPost",
		Vector3.new(0.5, 4.2, 0.5),
		at(start + 3, 1.6) * CFrame.new(Bonus.WALK_WIDTH / 2 + 3.6, 0, 0),
		C.MetalDark,
		METAL
	)
	ctx.Lamp(at(Bonus.FAN_AT, Bonus.FAN_LIFT + 6).Position, style.Primary, 0.8, 26, model)
	assert(spec.Stage >= Tower.FirstStage(w), "étape du monde")
end

return Bonus
