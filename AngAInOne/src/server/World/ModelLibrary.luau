--!strict
--[[
	ModelLibrary : place les VRAIS modèles 3D (MeshParts modélisés dans Blender, assets/models)
	dans la tour. Chaque modèle est chargé une fois (InsertService:LoadAsset) puis cloné.

	Convention de nom des pièces (voir assets/blender/common.py) :
	    <Nom>__<Matériau>__<RRGGBB>[__Spin]
	→ matériau et couleur Roblox appliqués au chargement ; "__Spin" = pièce qui tourne côté client
	  (tag TrapSpin, axe Y local).

	Si un modèle n'est pas (encore) importé, `Place` construit le décor de SECOURS fourni
	(primitives) : le jeu fonctionne toujours, et devient beau dès que les IDs sont renseignés.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModelAssets = require(Shared.Config.ModelAssets)

local ModelLibrary = {}

local templates: { [string]: Model } = {}

-- Modèles exportés couchés : rotation appliquée une fois au chargement pour les redresser
-- (axes Roblox : Blender X -> X, Blender Z -> Y, Blender Y -> -Z). Voir assets/README.md.
local ORIENT: { [string]: CFrame } = {
	CpuCooler = CFrame.Angles(0, 0, math.rad(90)), -- haut du ventirad vers +X -> +Y
	GpuCard = CFrame.Angles(math.rad(90), 0, 0), -- carte à plat -> debout, ventilateurs vers +Z
}
local failed: { [string]: boolean } = {}

local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Plastic = Enum.Material.Plastic,
	Metal = Enum.Material.Metal,
	DiamondPlate = Enum.Material.DiamondPlate,
	Glass = Enum.Material.Glass,
	Neon = Enum.Material.Neon,
	Foil = Enum.Material.Foil,
	Fabric = Enum.Material.Fabric,
	Granite = Enum.Material.Granite,
	Marble = Enum.Material.Marble,
	Wood = Enum.Material.Wood,
	Concrete = Enum.Material.Concrete,
	Ice = Enum.Material.Ice,
	ForceField = Enum.Material.ForceField,
	CorrodedMetal = Enum.Material.CorrodedMetal,
	Pebble = Enum.Material.Pebble,
}

-- Applique la convention de nom à une pièce importée. Renvoie true si c'est une pièce qui tourne.
function ModelLibrary.ApplyConvention(part: BasePart): boolean
	local name, material, color, flag = string.match(part.Name, "^(.-)__(%a+)__(%x%x%x%x%x%x)(.*)$")
	if not name then
		return false
	end
	part.Name = name :: string
	local mat = MATERIALS[material :: string]
	if mat then
		part.Material = mat
	end
	part.Color = Color3.fromHex(color :: string)
	if mat == Enum.Material.Glass then
		part.Transparency = math.max(part.Transparency, 0.55)
	end
	part.CastShadow = mat ~= Enum.Material.Neon and mat ~= Enum.Material.Glass
	return flag == "__Spin"
end

local function prepare(asset: Instance, key: string): Model?
	local model = asset:FindFirstChildWhichIsA("Model") or (if asset:IsA("Model") then asset else nil)
	if not model then
		return nil
	end
	local fix = ORIENT[key]
	if fix then
		model:PivotTo(model:GetPivot() * fix)
		model.WorldPivot = CFrame.new(model:GetPivot().Position) -- boîte englobante alignée sur le monde
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			if ModelLibrary.ApplyConvention(descendant) then
				descendant:SetAttribute("Axis", "Y")
				descendant:SetAttribute("Speed", 4)
				descendant:SetAttribute("SpinPart", true)
			end
		end
	end
	return model
end

-- Charge tous les modèles référencés (en parallèle). À appeler avant de construire la tour.
function ModelLibrary.Preload()
	if next(ModelAssets) == nil then
		return -- aucun modèle importé : tout le décor utilise les primitives de secours
	end
	local InsertService = game:GetService("InsertService")
	local pending = 0
	for key, id in ModelAssets do
		if not templates[key] and not failed[key] and id > 0 then
			pending += 1
			task.spawn(function()
				local ok, asset = pcall(function(): Instance
					return InsertService:LoadAsset(id)
				end)
				local model = if ok and asset then prepare(asset, key) else nil
				if model then
					model.Name = key
					templates[key] = model
				else
					failed[key] = true
					warn(`[ModelLibrary] modèle {key} ({id}) introuvable : décor de secours utilisé`)
				end
				pending -= 1
			end)
		end
	end
	local deadline = os.clock() + 20
	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
end

function ModelLibrary.Has(key: string): boolean
	local template: Model? = templates[key]
	return template ~= nil
end

export type PlaceOptions = {
	Scale: number?, -- 1 = taille modélisée (1 unité Blender = 1 stud)
	-- Taille cible (axes du modèle, avant la rotation de `cframe`) : échelle UNIFORME maximale pour
	-- tenir dans cette boîte. Préférable à Scale : ne dépend pas de la taille exacte du modèle.
	Fit: Vector3?,
	Collide: boolean?, -- pièces solides (par défaut : décor sans collision)
	Name: string?,
	-- Pièces `__Spin` : true (défaut) = tournent côté client ; false = figées (modèle que l'on
	-- anime soi-même, ex. LAGZ) ; "Hide" = retirées (ex. ventilateur posé sur des pales mortelles :
	-- seules les vraies pales, rouges, doivent tourner).
	Spin: (boolean | string)?,
}

-- Place le modèle `key` (origine = centre de la base) au CFrame donné. Sinon : `fallback()`.
function ModelLibrary.Place(
	key: string,
	cframe: CFrame,
	parent: Instance,
	options: PlaceOptions?,
	fallback: (() -> Instance?)?
): Instance?
	local template = templates[key]
	if not template then
		local built = if fallback then fallback() else nil
		if built and not built.Parent then
			built.Parent = parent
		end
		return built
	end
	local opts: PlaceOptions = options or {}
	local model = template:Clone()
	model.Name = opts.Name or key
	if opts.Scale and opts.Scale ~= 1 then
		model:ScaleTo(opts.Scale)
	end
	if opts.Fit then
		local _, current = model:GetBoundingBox()
		local fit = opts.Fit
		local ratio = math.huge
		for _, axis in { "X", "Y", "Z" } do
			local have = (current :: any)[axis] :: number
			if have > 0.01 then
				ratio = math.min(ratio, (fit :: any)[axis] / have)
			end
		end
		if ratio < math.huge then
			model:ScaleTo(model:GetScale() * ratio)
		end
	end
	-- Origine = centre de la base de la boîte englobante
	local boxCf, size = model:GetBoundingBox()
	local base = boxCf * CFrame.new(0, -size.Y / 2, 0)
	model.WorldPivot = CFrame.new(base.Position)
	model:PivotTo(cframe)
	local spin = if opts.Spin == nil then true else opts.Spin
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local isSpin = descendant:GetAttribute("SpinPart") == true
			if opts.Collide and not isSpin then
				descendant.CanCollide = true
				descendant.CanQuery = true
			end
			if isSpin and spin == "Hide" then
				descendant:Destroy()
			elseif isSpin and spin == true then
				descendant:AddTag("TrapSpin")
			end
		end
	end
	model.Parent = parent
	return model
end

return ModelLibrary
