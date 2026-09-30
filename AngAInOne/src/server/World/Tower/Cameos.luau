--!strict
--[[
	Cameos : LAGZ apparaît EN 3D dans chaque monde (docs/AUDIT_V3.md, C2) : un écran accroché à une
	paroi de la tour, d'où sort sa tête géante quand le joueur atteint l'étape (client LagzCameo).
	Appelé une fois par TowerBuilder, après les mondes.

	Contrat (lu par Controllers/LagzCameo) :
	World{n}.Decor.LagzCameo{s}  (Model, tag LagzCameo, attributs World = n, Stage = s)
	├─ CameoBezel / CameoScreen / CameoEdge×4 / CameoStatic×5   l'écran (neige violette)
	└─ Head  (Model, WorldPivot = centre de sa base, face avant = +Z local = vers le parcours)
	Tout est du décor pur (ni collision, ni toucher, ni requêtes) : le graphe de sauts ne change pas.

	Emplacements (Spots) : contre les parois (X, Z = ±132), hors du volume des parcours ; choisis
	avec la carte exportée (tests/tools/ExportMap.luau) : aucune pièce des mondes dans la boîte
	26 × 24 × 12 studs devant l'écran, et vue dégagée depuis le checkpoint de l'étape.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Build = require(script.Parent.Parent.Build)
local Props = require(script.Parent.Parent.Props)
local ModelLibrary = require(script.Parent.Parent.ModelLibrary)
local Common = require(script.Parent.Common)

local Cameos = {}

export type Spot = {
	World: number,
	Stage: number, -- l'étape dont le checkpoint déclenche l'apparition
	Wall: string, -- "-X" | "+X" (vitre) | "-Z" (façade) | "+Z" (arrière)
	Along: number, -- position le long de la paroi (Z pour ±X, X pour ±Z)
	Y: number, -- hauteur du centre de l'écran
}

-- Deux apparitions par monde, jamais dans l'arène du boss. Au 1er checkpoint d'un monde, l'écran
-- illustre la réplique d'arrivée de LAGZ (Story.LagzWorld) sans en ajouter une.
Cameos.Spots = {
	{ World = 1, Stage = 2, Wall = "+Z", Along = -100, Y = 49 },
	{ World = 1, Stage = 4, Wall = "+X", Along = 0, Y = 67 },
	{ World = 2, Stage = 6, Wall = "-Z", Along = -20, Y = 129 },
	{ World = 2, Stage = 7, Wall = "+Z", Along = -24, Y = 139 },
	{ World = 3, Stage = 11, Wall = "+Z", Along = -16, Y = 221 },
	{ World = 3, Stage = 13, Wall = "-X", Along = -84, Y = 262 },
	{ World = 4, Stage = 16, Wall = "-X", Along = 8, Y = 323 },
	{ World = 4, Stage = 18, Wall = "-Z", Along = 48, Y = 351 },
	{ World = 5, Stage = 22, Wall = "+Z", Along = 16, Y = 437 },
	{ World = 5, Stage = 24, Wall = "-Z", Along = -4, Y = 482 },
	{ World = 6, Stage = 27, Wall = "+X", Along = 60, Y = 536 },
	{ World = 6, Stage = 29, Wall = "+X", Along = -12, Y = 567 },
	{ World = 7, Stage = 32, Wall = "-Z", Along = -52, Y = 639 },
	{ World = 7, Stage = 33, Wall = "-X", Along = 0, Y = 653 },
} :: { Spot }

Cameos.SCREEN = Vector3.new(26, 20, 1.4) -- cadre de l'écran (largeur, hauteur, épaisseur)
Cameos.HEAD_FIT = Vector3.new(15, 13, 10) -- boîte de la tête (axes du modèle)
Cameos.HEAD_OUT = 6.5 -- centre de la tête devant la paroi (studs)

local C = Props.C
local Box = Props.Box
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

local LAGZ = Color3.fromHex("9F7AEA")
local LAGZ_DARK = Color3.fromHex("6B46C1")
local GLITCH = Color3.fromHex("ED64A6")
local CYAN = Color3.fromHex("4FD1C5")
local CROWN = Color3.fromHex("F6E05E")
local INK = Color3.fromRGB(21, 18, 31)
local SCREEN = Color3.fromRGB(26, 12, 44)

local INWARD: { [string]: Vector3 } = {
	["-X"] = Vector3.xAxis,
	["+X"] = -Vector3.xAxis,
	["-Z"] = Vector3.zAxis,
	["+Z"] = -Vector3.zAxis,
}

-- Repère de l'écran : sur la face intérieure de la paroi, +Z local = vers le parcours.
function Cameos.MountCFrame(spot: Spot): CFrame
	local inner = Common.INNER
	local inward = INWARD[spot.Wall]
	assert(inward, `paroi inconnue : {spot.Wall}`)
	local surface = if spot.Wall == "-X" or spot.Wall == "+X"
		then Vector3.new(-inward.X * inner, spot.Y, spot.Along)
		else Vector3.new(spot.Along, spot.Y, -inward.Z * inner)
	-- LookVector = vers la paroi : l'avant du modèle (+Z local) regarde le parcours.
	return CFrame.fromMatrix(surface, Vector3.yAxis:Cross(inward), Vector3.yAxis, inward)
end

-- Tête de LAGZ en primitives (décor de secours) : blob violet glitché, yeux pixels, sourire en
-- dents de scie, couronne en roue de chargement (même dessin que UI/Components/Lagz).
-- `base` = centre de la base, face avant vers +Z local.
local function headFallback(base: CFrame): Model
	local model = Build.Model("Head")
	Build.Decor({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 11,
		CFrame = base * CFrame.new(0, 5.5, 0),
		Color = LAGZ,
		Material = SMOOTH,
		CastShadow = false,
		Parent = model,
	})
	Box(model, "GlitchPink", Vector3.new(11.6, 0.8, 9.4), base * CFrame.new(0.8, 3.2, 0), GLITCH, NEON)
	Box(model, "GlitchCyan", Vector3.new(11.4, 0.7, 9.2), base * CFrame.new(-0.7, 7.8, 0), CYAN, NEON)
	for _, x in { -2.2, 2.2 } do
		Box(model, "Eye", Vector3.new(2.6, 3, 0.8), base * CFrame.new(x, 6.6, 4.9), C.White, NEON)
		Box(model, "Pupil", Vector3.new(1.2, 1.3, 0.3), base * CFrame.new(x + 0.5, 6.3, 5.4), C.Black)
	end
	Box(model, "Mouth", Vector3.new(5, 0.9, 0.6), base * CFrame.new(0, 3.4, 4.8), LAGZ_DARK:Lerp(C.Black, 0.7))
	for i = 0, 3 do
		Box(
			model,
			"Tooth",
			Vector3.new(0.8, 0.6, 0.3),
			base * CFrame.new(-1.8 + i * 1.2, if i % 2 == 0 then 3.75 else 3.1, 5.2),
			C.White
		)
	end
	for k = 0, 7 do
		local angle = k * math.pi / 4
		local dot = Build.Neon({
			Name = "Crown",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.3,
			CFrame = base * CFrame.new(math.cos(angle) * 2.6, 11.9, math.sin(angle) * 2.6),
			Color = CROWN,
			Parent = model,
		})
		dot.Transparency = k / 8 * 0.8
	end
	for _, spot in { Vector3.new(-5.2, 7, 1), Vector3.new(5.3, 4.2, 0.5), Vector3.new(-3.8, 1.6, 3) } do
		Box(model, "Pixel", Vector3.one * 1.2, base * CFrame.new(spot), GLITCH, NEON)
	end
	model.WorldPivot = base
	return model
end

-- Neige de l'écran : bandes magenta / cyan (x, y, largeur) fixes, animées par le client.
local STATIC = {
	{ -3, 6, 16 },
	{ 4, 2.5, 12 },
	{ -5, -1.5, 9 },
	{ 2, -4.5, 18 },
	{ -1, -7, 11 },
}

-- Pose une apparition de LAGZ. Renvoie le Model tagué LagzCameo.
function Cameos.Place(spot: Spot, parent: Instance): Model
	local mount = Cameos.MountCFrame(spot)
	local cameo = Build.Model(`LagzCameo{spot.Stage}`, parent)
	local size = Cameos.SCREEN
	Box(cameo, "CameoBezel", size, mount * CFrame.new(0, 0, size.Z / 2), INK)
	Box(
		cameo,
		"CameoScreen",
		Vector3.new(size.X - 2.6, size.Y - 2.6, 0.2),
		mount * CFrame.new(0, 0, size.Z + 0.05),
		SCREEN
	)
	local edge = size.Z + 0.2
	for _, bar in
		{
			{ 0, size.Y / 2 - 0.3, size.X, 0.6 },
			{ 0, -size.Y / 2 + 0.3, size.X, 0.6 },
			{ size.X / 2 - 0.3, 0, 0.6, size.Y },
			{ -size.X / 2 + 0.3, 0, 0.6, size.Y },
		}
	do
		Box(cameo, "CameoEdge", Vector3.new(bar[3], bar[4], 0.3), mount * CFrame.new(bar[1], bar[2], edge), LAGZ, NEON)
	end
	for i, band in STATIC do
		local stripe = Box(
			cameo,
			"CameoStatic",
			Vector3.new(band[3], 0.5, 0.1),
			mount * CFrame.new(band[1], band[2], size.Z + 0.25),
			if i % 2 == 0 then CYAN else GLITCH,
			NEON
		)
		stripe.Transparency = 0.35
	end
	-- La tête : posée devant l'écran, base au bas de l'écran ; le client la cache puis la fait surgir.
	local base = mount * CFrame.new(0, -size.Y / 2 + 3, Cameos.HEAD_OUT)
	local head = ModelLibrary.Place(
		"LagzHead",
		base,
		cameo,
		{ Fit = Cameos.HEAD_FIT, Spin = false, Name = "Head" },
		function()
			return headFallback(base)
		end
	)
	if head and head:IsA("Model") then
		head.Name = "Head"
		head.WorldPivot = base
	end
	-- Décor pur, même pour le vrai modèle (sécurité).
	for _, d in cameo:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	cameo:SetAttribute("World", spot.World)
	cameo:SetAttribute("Stage", spot.Stage)
	cameo:AddTag("LagzCameo")
	return cameo
end

function Cameos.Build(tower: Instance)
	for _, spot in Cameos.Spots do
		local world = tower:FindFirstChild(`World{spot.World}`)
		if world and spot.World <= Tower.WORLD_COUNT then
			Cameos.Place(spot, world:FindFirstChild("Decor") or world)
		end
	end
end

return table.freeze(Cameos)
