-- ModelLibrary : vrais modèles 3D (assets/models/*.glb) → convention de nom des pièces et décor de secours.
local roblox = require("@lune/roblox")

Shim.Globals = {
	game = {
		GetService = function(_self: any, name: string): any
			assert(name == "ReplicatedStorage", `service inattendu : {name}`)
			return {
				WaitForChild = function()
					return Shim.Node("src/shared")
				end,
			}
		end,
	},
	Enum = roblox.Enum,
	Color3 = roblox.Color3,
	Instance = roblox.Instance,
}
local ModelLibrary = Shim.load("src/server/World/ModelLibrary.luau")
local ModelAssets = Shim.load("src/shared/Config/ModelAssets.luau")
Shim.Globals = {}

local V3, CF, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance

-- Clé réservée aux tests (aucun modèle du jeu ne s'appelle ainsi : un test qui échoue avant son
-- nettoyage ne change rien à la tour construite par les autres specs).
local KEY = "TestOnlyProp"

local function near(a: any, b: any, label: string)
	Expect.truthy((a - b).Magnitude < 1e-3, `{label} : {a} ≠ {b}`)
end

-- Faux modèle importé : socle 2 × 1 × 4 centré en (0, 0.5, 0), écran 2 × 1 × 0.2 au-dessus, néon.
local function fakeModel(): any
	local model = Instance.new("Model")
	local body = Instance.new("MeshPart")
	body.Name = "Body__SmoothPlastic__16181E"
	body.Size = V3.new(2, 1, 4)
	body.CFrame = CF.new(0, 0.5, 0)
	body.Parent = model
	local screen = Instance.new("MeshPart")
	screen.Name = "Screen__SmoothPlastic__0B0C10"
	screen.Size = V3.new(2, 1, 0.2)
	screen.CFrame = CF.new(0, 1.5, -1.9)
	screen.Parent = model
	local trim = Instance.new("MeshPart")
	trim.Name = "Trim__Neon__8B7CFF__Spin"
	trim.Size = V3.new(2, 0.2, 0.2)
	trim.CFrame = CF.new(0, 0.1, -2.1)
	trim.Parent = model
	return model
end

-- Primitives de gameplay : dalle praticable avec prompt et texte, et un Model de décor.
local function primitives(): (any, any, any)
	local folder = Instance.new("Folder")
	local floor = Instance.new("Part")
	floor.Name = "Stand"
	floor.Anchored = true
	floor.Size = V3.new(4, 2, 8)
	floor.CFrame = CF.new(10, 1, 0)
	floor.Parent = folder
	floor:AddTag("Kiosk")
	floor:SetAttribute("Action", "Shop")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Parent = floor
	local gui = Instance.new("SurfaceGui")
	gui.Parent = floor
	local decor = Instance.new("Model")
	decor.Parent = folder
	local knob = Instance.new("Part")
	knob.Name = "Knob"
	knob.CanCollide = false
	knob.Parent = decor
	return folder, floor, decor
end

return {
	["ModelLibrary : matériau, couleur et pièces qui tournent lus dans le nom"] = function()
		local blade = roblox.Instance.new("Part")
		blade.Name = "Blades__SmoothPlastic__2A2D38__Spin"
		Expect.equal(ModelLibrary.ApplyConvention(blade), true)
		Expect.equal(blade.Name, "Blades")
		Expect.equal(blade.Material, roblox.Enum.Material.SmoothPlastic)
		Expect.equal(blade.Color:ToHex():upper(), "2A2D38")

		local ring = roblox.Instance.new("Part")
		ring.Name = "Ring__Neon__8B7CFF"
		Expect.equal(ModelLibrary.ApplyConvention(ring), false)
		Expect.equal(ring.Material, roblox.Enum.Material.Neon)
		Expect.equal(ring.CastShadow, false)

		local plain = roblox.Instance.new("Part")
		plain.Name = "Base"
		Expect.equal(ModelLibrary.ApplyConvention(plain), false)
		Expect.equal(plain.Name, "Base")
	end,
	["ModelLibrary : sans modèle importé, le décor de secours est construit"] = function()
		local folder = roblox.Instance.new("Folder")
		local placed = ModelLibrary.Place("Inconnu", roblox.CFrame.new(), folder, nil, function()
			local part = roblox.Instance.new("Part")
			part.Name = "Secours"
			return part
		end)
		Expect.equal(placed.Name, "Secours")
		Expect.equal(placed.Parent, folder)
		Expect.equal(ModelLibrary.Has("Inconnu"), false)
	end,
	["ModelAssets : chaque ID correspond à un fichier assets/models/<clé>.glb"] = function()
		for key, id in ModelAssets do
			Expect.truthy(id > 0, key)
			Expect.truthy(Fs.isFile(`assets/models/{key}.glb`), `{key}.glb manquant`)
		end
	end,

	["Dress : sans modèle, ne fait rien (primitives intactes)"] = function()
		local folder, floor, decor = primitives()
		local placed = ModelLibrary.Dress(KEY, CF.new(10, 0, 0), folder, { Fit = V3.new(4, 4, 8) }, { floor, decor })
		Expect.equal(placed, nil, "rien de posé")
		Expect.equal(floor.Transparency, 0, "dalle visible")
		Expect.equal(floor.CanCollide, true, "dalle solide")
		Expect.equal(floor:FindFirstChildOfClass("SurfaceGui").Enabled, true, "texte visible")
		Expect.equal(decor.Knob.Transparency, 0, "décor visible")
		Expect.equal(#folder:GetChildren(), 2, "aucun modèle ajouté")
	end,

	["Dress : modèle présent → primitives invisibles mais solides, modèle mis à l'échelle Fit"] = function()
		ModelLibrary._SetTemplate(KEY, fakeModel())
		Expect.equal(ModelLibrary.Has(KEY), true, "modèle simulé")
		local folder, floor, decor = primitives()
		-- Boîte du modèle : 2 × 2 × 4.2 → Fit (4, 10, 20) : échelle 2 (limitée par X)
		local cf = CF.new(10, 0, 0) * CF.Angles(0, math.pi / 2, 0)
		local placed = ModelLibrary.Dress(
			KEY,
			cf,
			folder,
			{ Fit = V3.new(4, 10, 20), Collide = true, Recolor = { Trim = roblox.Color3.new(1, 0, 0) } },
			{ floor, decor }
		)
		ModelLibrary._SetTemplate(KEY, nil)
		Expect.equal(ModelLibrary.Has(KEY), false, "modèle retiré")

		-- Primitives : invisibles, mais collision, tags, attributs et prompt conservés
		Expect.equal(floor.Transparency, 1, "dalle invisible")
		Expect.equal(floor.CanCollide, true, "dalle toujours solide")
		Expect.equal(floor.Anchored, true, "dalle ancrée")
		Expect.truthy(floor:HasTag("Kiosk"), "tag conservé")
		Expect.equal(floor:GetAttribute("Action"), "Shop", "attribut conservé")
		Expect.truthy(floor:FindFirstChildOfClass("ProximityPrompt") ~= nil, "prompt conservé")
		Expect.equal(floor:FindFirstChildOfClass("SurfaceGui").Enabled, false, "texte masqué")
		Expect.equal(decor.Knob.Transparency, 1, "BaseParts d'un Model masquées")
		Expect.equal(decor.Knob.CanCollide, false, "collision d'origine inchangée")

		-- Modèle : décor sans collision (Collide ignoré), échelle Fit, base centrée sur `cf`
		Expect.truthy(placed ~= nil and placed:IsA("Model"), "modèle posé")
		Expect.equal(placed.Parent, folder, "parent")
		Expect.equal(placed.Name, KEY, "nom")
		local body, screen, trim = placed.Body, placed.Screen, placed.Trim
		for _, part in { body, screen, trim } do
			Expect.equal(part.CanCollide, false, `{part.Name} sans collision`)
			Expect.equal(part.CanTouch, false, `{part.Name} sans toucher`)
			Expect.equal(part.Anchored, true, `{part.Name} ancré`)
		end
		near(body.Size, V3.new(4, 2, 8), "échelle 2")
		near(screen.Size, V3.new(4, 2, 0.4), "échelle 2 (écran)")
		-- Boîte : x ∈ [-1, 1], y ∈ [0, 2], z ∈ [-2.2, 2] → centre de la base (0, 0, -0.1)
		near(body.CFrame.Position, (cf * CF.new(0, 1, 0.2)).Position, "socle posé sur cf")
		near(body.CFrame.LookVector, cf.LookVector, "orienté comme cf")
		near(screen.CFrame.Position, (cf * CF.new(0, 3, -3.6)).Position, "écran suit l'échelle")
		Expect.equal(trim.Color, roblox.Color3.new(1, 0, 0), "Recolor")
		Expect.equal(trim:HasTag("TrapSpin"), true, "pièce __Spin animée par défaut")
		near(placed.WorldPivot.Position, cf.Position, "pivot du modèle = point posé")
	end,

	["Place : Anchor pose un point du modèle (unités modélisées) sur le CFrame"] = function()
		ModelLibrary._SetTemplate(KEY, fakeModel())
		local folder = Instance.new("Folder")
		-- Scale 3 ; point (0, 1, 0) au-dessus de l'origine (sans ORIGIN : centre de la base (0, 0, -0.1))
		local placed = ModelLibrary.Place(KEY, CF.new(0, 50, 0), folder, { Scale = 3, Anchor = V3.new(0, 1, 0) })
		ModelLibrary._SetTemplate(KEY, nil)
		near(placed.Body.Size, V3.new(6, 3, 12), "Scale")
		-- Socle : centre (0, 0.5, 0) → relatif au point (0, 1, -0.1) : (0, -0.5, 0.1) × 3
		near(placed.Body.CFrame.Position, V3.new(0, 48.5, 0.3), "point d'ancrage")
	end,

	["Weld : habillage soudé, non ancré, sans collision ; racine intacte"] = function()
		local folder = Instance.new("Folder")
		local root = Instance.new("Part")
		root.Anchored = true
		root.CanTouch = true
		root.CFrame = CF.new(5, 20, 5)
		root.Parent = folder
		root:AddTag("Coin")
		Expect.equal(ModelLibrary.Weld(KEY, root, root.CFrame), nil, "sans modèle : rien")
		Expect.equal(#root:GetChildren(), 0, "sans modèle : racine intacte")

		ModelLibrary._SetTemplate(KEY, fakeModel())
		local model = ModelLibrary.Weld(KEY, root, root.CFrame, { Fit = V3.new(1, 1, 1) })
		ModelLibrary._SetTemplate(KEY, nil)
		Expect.equal(model.Parent, root, "modèle sous la racine")
		local parts = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				Expect.equal(d.Anchored, false, `{d.Name} non ancré`)
				Expect.equal(d.CanCollide, false, `{d.Name} sans collision`)
				Expect.equal(d.CanTouch, false, `{d.Name} sans toucher`)
				Expect.equal(d.CanQuery, false, `{d.Name} sans requêtes`)
				Expect.equal(d:HasTag("TrapSpin"), false, `{d.Name} : pièce __Spin figée`)
				local weld = d:FindFirstChildOfClass("WeldConstraint")
				Expect.truthy(weld and weld.Part0 == root and weld.Part1 == d, `{d.Name} soudé à la racine`)
			end
		end
		Expect.equal(parts, 3, "toutes les pièces soudées")
		Expect.equal(root.Anchored, true, "racine ancrée")
		Expect.equal(root.CanTouch, true, "racine touchable")
		Expect.equal(root.Transparency, 0, "racine non masquée par Weld")
	end,

	["FitScreen : la dalle hôte du SurfaceGui se recale devant l'écran du modèle"] = function()
		ModelLibrary._SetTemplate(KEY, fakeModel())
		local folder = Instance.new("Folder")
		local cf = CF.new(0, 0, 30) * CF.Angles(0, math.pi, 0)
		local placed = ModelLibrary.Place(KEY, cf, folder, { Scale = 2 })
		ModelLibrary._SetTemplate(KEY, nil)
		local host = Instance.new("Part")
		host.Size = V3.new(8, 4.5, 0.2)
		local gui = Instance.new("SurfaceGui")
		gui.SizingMode = roblox.Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 8
		gui.Parent = host
		Expect.equal(ModelLibrary.FitScreen(placed, host), true, "écran trouvé")
		local screen = placed.Screen
		near(host.Size, V3.new(screen.Size.X, screen.Size.Y, 0.2), "même taille que l'écran")
		near(host.CFrame.LookVector, screen.CFrame.LookVector, "même orientation")
		near(host.CFrame.Position, (screen.CFrame * CF.new(0, 0, -(0.4 + 0.2) / 2 - 0.05)).Position, "devant l'écran")
		Expect.truthy(math.abs(gui.PixelsPerStud - 16) < 1e-6, "résolution du texte conservée")
		Expect.equal(ModelLibrary.FitScreen(Instance.new("Model"), host), false, "pas d'écran : rien")
	end,
}
