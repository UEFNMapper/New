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

	Trois façons de poser un modèle :
	- `Place`     décor pur : le modèle, sinon les primitives de secours ;
	- `Dress`     habillage de primitives de GAMEPLAY (sol praticable, pièces à contrat) : si le modèle
	              existe, les primitives deviennent invisibles mais gardent collision, tags, attributs et
	              ProximityPrompt ; sinon rien ne change ;
	- `Weld`      habillage soudé à une racine animée (Bits, clés USB) : le client anime la racine.
	`FitScreen` recale une dalle primitive (hôte d'un SurfaceGui) sur la pièce `Screen` d'un modèle posé.

	Géométrie faite à la main (boîte englobante, échelle, pose pièce par pièce) plutôt qu'avec
	Model:ScaleTo / PivotTo : même résultat, et testable hors de Roblox (tests/models.spec.luau).
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

--[[
	Origine d'export (centre de la base dans Blender) des modèles ASYMÉTRIQUES, relative au centre de
	la base de leur boîte englobante, en unités modélisées et axes Roblox (Blender X -> X, Z -> Y,
	Y -> -Z). Mesurée sur assets/models/<clé>.glb. Sert à l'option `Anchor` : un câble, un bras ou une
	anse ne décale plus l'objet. Absent = origine au centre de la base (modèles symétriques).
]]
local ORIGIN: { [string]: Vector3 } = {
	Monitor = Vector3.new(0, 0, -35.36), -- pied profond à l'arrière
	Keyboard = Vector3.new(0, 0, -38.42), -- câble à l'arrière
	Mouse = Vector3.new(-0.23, 0, -26.15), -- câble à l'avant (vers l'écran)
	MicArm = Vector3.new(-1.15, 40, 62.12), -- pince 40 studs sous le plateau, bras vers -Z
	Mug = Vector3.new(7.54, 0, 0.75), -- anse côté -X
	DeskLamp = Vector3.new(0, 0, 25.73), -- abat-jour vers -Z
	Headset = Vector3.new(0, 0, -2.04),
	GamingChair = Vector3.new(0.19, 0, -12.12),
	WebcamLight = Vector3.new(0, 0, 1.65),
	Speaker = Vector3.new(0, 0, -1.77),
	Miniaturiseur = Vector3.new(0, 0, 1.72), -- marche d'accès à l'avant
	ArcadeCabinet = Vector3.new(0, 0, 0.28),
	ShopKiosk = Vector3.new(0, 0, 0.5),
	TerminalConsole = Vector3.new(0, 0, -0.87),
	BitCoin = Vector3.new(0, 1.25, 0), -- origine au centre de l'orbe
	UsbKey = Vector3.new(0, 0.39, 0), -- origine au centre de la clé
}

local failed: { [string]: boolean } = {}

-- Modèles recopiés dans ReplicatedStorage.ClientModels pour le client (voir publishForClient).
local CLIENT_MODELS = { "Anga", "AioDrone" }

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

-- Dossier ReplicatedStorage.ClientModels : TOUJOURS présent (même vide), pour que le client
-- (Companion) ne l'attende pas en vain ; il y trouve les modèles au fur et à mesure du chargement.
local function clientFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild("ClientModels")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "ClientModels"
	created.Parent = ReplicatedStorage
	return created
end

-- Modèle animé CÔTÉ CLIENT (compagnon mini-Anga : Companion.luau) : copie du gabarit dans
-- ReplicatedStorage.ClientModels dès son chargement. Absent = le client garde son secours en primitives.
local function publishForClient(key: string, template: Model)
	if not table.find(CLIENT_MODELS, key) then
		return
	end
	local folder = clientFolder()
	if not folder:FindFirstChild(key) then
		template:Clone().Parent = folder
	end
end

-- Charge tous les modèles référencés (en parallèle). À appeler avant de construire la tour.
-- Attend au plus 20 s ; un modèle plus lent reste utilisable ensuite (et publié pour le client).
function ModelLibrary.Preload()
	clientFolder()
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
					publishForClient(key, model)
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

-- TESTS UNIQUEMENT (tests/models.spec.luau) : simule un modèle importé (`model` passe par la même
-- préparation qu'un asset chargé) ; `nil` le retire. Ne jamais appeler depuis le jeu.
function ModelLibrary._SetTemplate(key: string, model: Model?)
	if model then
		local prepared = prepare(model, key)
		assert(prepared, `[ModelLibrary] _SetTemplate({key}) : Model attendu`)
		prepared.Name = key
		templates[key] = prepared
	else
		templates[key] = nil
	end
end

export type PlaceOptions = {
	Scale: number?, -- 1 = taille modélisée (1 unité Blender = 1 stud)
	-- Taille cible (axes du modèle, avant la rotation de `cframe`) : échelle UNIFORME maximale pour
	-- tenir dans cette boîte. Préférable à Scale : ne dépend pas de la taille exacte du modèle.
	Fit: Vector3?,
	-- Point du modèle posé sur `cframe`, en unités MODÉLISÉES (avant échelle), relatif à son origine
	-- d'export (table ORIGIN). Ex. Vector3.zero = origine Blender ; (0, 2.56, 0) = 2,56 unités au-dessus
	-- (enfonce le modèle pour qu'une hauteur donnée affleure `cframe`). Par défaut : centre de la base
	-- de la boîte englobante (comportement historique).
	Anchor: Vector3?,
	Collide: boolean?, -- pièces solides (par défaut : décor sans collision)
	Name: string?,
	-- Pièces `__Spin` : true (défaut) = tournent côté client ; false = figées (modèle que l'on
	-- anime soi-même, ex. LAGZ) ; "Hide" = retirées (ex. ventilateur posé sur des pales mortelles :
	-- seules les vraies pales, rouges, doivent tourner).
	Spin: (boolean | string)?,
	-- Nouvelle couleur de pièces par nom (après convention), ex. { Trim = couleur du monde }.
	Recolor: { [string]: Color3 }?,
}

-- Boîte englobante (axes du monde) de toutes les BaseParts de `root` : coin min, coin max.
local function bounds(root: Instance): (Vector3?, Vector3?)
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			local cf, size = descendant.CFrame, descendant.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
			local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
			local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
			local p = cf.Position
			x0, y0, z0 = math.min(x0, p.X - hx), math.min(y0, p.Y - hy), math.min(z0, p.Z - hz)
			x1, y1, z1 = math.max(x1, p.X + hx), math.max(y1, p.Y + hy), math.max(z1, p.Z + hz)
		end
	end
	if x0 > x1 then
		return nil, nil
	end
	return Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
end

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
	-- Échelle : Fit (plus grande échelle qui tient dans la boîte) prime sur Scale
	local lo, hi = bounds(model)
	local scale = opts.Scale or 1
	local from = cframe.Position
	if lo and hi then
		local size = hi - lo
		local fit = opts.Fit
		if fit then
			local ratio = math.huge
			for _, pair in { { size.X, fit.X }, { size.Y, fit.Y }, { size.Z, fit.Z } } do
				if pair[1] > 0.01 then
					ratio = math.min(ratio, pair[2] / pair[1])
				end
			end
			if ratio < math.huge then
				scale = ratio
			end
		end
		-- Point posé sur `cframe` : centre de la base de la boîte, ou origine d'export + Anchor
		from = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
		if opts.Anchor then
			from += (ORIGIN[key] or Vector3.zero) + opts.Anchor
		end
	end
	local spin = if opts.Spin == nil then true else opts.Spin
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local cf = descendant.CFrame
			descendant.Size *= scale
			descendant.CFrame = cframe * CFrame.new((cf.Position - from) * scale) * (cf - cf.Position)
			local size = descendant.Size
			if math.max(size.X, size.Y, size.Z) <= 5 then
				descendant.CastShadow = false -- petit détail : pas d'ombre (budget mobile, comme Props)
			end
			local isSpin = descendant:GetAttribute("SpinPart") == true
			if opts.Collide and not isSpin then
				descendant.CanCollide = true
				descendant.CanQuery = true
			end
			local color = opts.Recolor and opts.Recolor[descendant.Name]
			if color then
				descendant.Color = color
			end
			if isSpin and spin == "Hide" then
				descendant:Destroy()
			elseif isSpin and spin == true then
				descendant:AddTag("TrapSpin")
			end
		end
	end
	model.WorldPivot = cframe -- ScaleTo / PivotTo ultérieurs : autour du point posé
	model.Parent = parent
	return model
end

-- Rend une primitive invisible sans rien lui retirer d'autre : collision, toucher, requêtes, tags,
-- attributs et ProximityPrompt restent ; ses SurfaceGui / Decal / Texture sont masqués.
local function conceal(root: Instance)
	local nodes = root:GetDescendants()
	table.insert(nodes, root)
	for _, node in nodes do
		if node:IsA("BasePart") then
			node.Transparency = 1
			node.CastShadow = false
		elseif node:IsA("SurfaceGui") then
			node.Enabled = false
		elseif node:IsA("Decal") then -- Texture hérite de Decal
			node.Transparency = 1
		end
	end
end

--[[
	Habille des primitives de GAMEPLAY avec le vrai modèle `key` (sol praticable, pièce qui porte un
	contrat : prompt, tag, SurfaceGui lu par le client…).
	- Modèle importé : chaque élément de `primitives` (une BasePart, ou un Model / Folder = toutes ses
	  BaseParts) devient invisible (Transparency = 1) en GARDANT sa collision, ses tags, attributs et
	  prompts ; le modèle est posé par-dessus comme décor sans collision (options de `Place`,
	  `Collide` ignoré). Renvoie le modèle posé.
	- Sinon : ne fait RIEN (les primitives restent exactement telles quelles) et renvoie nil.
]]
function ModelLibrary.Dress(
	key: string,
	cframe: CFrame,
	parent: Instance,
	options: PlaceOptions?,
	primitives: { Instance }
): Model?
	if not templates[key] then
		return nil
	end
	for _, primitive in primitives do
		conceal(primitive)
	end
	local opts: PlaceOptions = table.clone(options or {})
	opts.Collide = false
	return ModelLibrary.Place(key, cframe, parent, opts) :: Model?
end

--[[
	Habillage SOUDÉ à une racine animée (Bit, clé USB : le client anime le CFrame de la racine, qui
	reste la pièce touchée). Si le modèle existe : il est posé en `cframe` sous `root`, pièces `__Spin`
	figées, chaque pièce non ancrée, sans collision / toucher / requêtes, soudée (WeldConstraint) à
	`root` (ancrée) ; renvoie le modèle. Sinon : ne fait rien et renvoie nil. `root` n'est pas masquée.
]]
function ModelLibrary.Weld(key: string, root: BasePart, cframe: CFrame, options: PlaceOptions?): Model?
	if not templates[key] then
		return nil
	end
	local opts: PlaceOptions = table.clone(options or {})
	opts.Collide = false
	opts.Spin = false
	local model = ModelLibrary.Place(key, cframe, root, opts) :: Model
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = descendant
			descendant.Anchored = false
		end
	end
	return model
end

--[[
	Recale `host` (dalle primitive qui porte un SurfaceGui sur sa face avant) sur la pièce `Screen` du
	modèle posé `model` : même repère, même largeur / hauteur, juste devant sa face avant (-Z local).
	La résolution des SurfaceGui en PixelsPerStud est conservée (texte aussi net). Renvoie false (sans
	rien toucher) si le modèle n'a pas de `Screen`.
]]
function ModelLibrary.FitScreen(model: Instance, host: BasePart): boolean
	local screen: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant.Name == "Screen" and descendant:IsA("BasePart") then
			screen = descendant
			break
		end
	end
	if not screen then
		return false
	end
	local width = host.Size.X
	host.Size = Vector3.new(screen.Size.X, screen.Size.Y, host.Size.Z)
	host.CFrame = screen.CFrame * CFrame.new(0, 0, -(screen.Size.Z + host.Size.Z) / 2 - 0.05)
	for _, gui in host:GetChildren() do
		if gui:IsA("SurfaceGui") and gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud then
			gui.PixelsPerStud *= width / math.max(host.Size.X, 0.01)
		end
	end
	return true
end

return ModelLibrary
