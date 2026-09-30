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
}
local ModelLibrary = Shim.load("src/server/World/ModelLibrary.luau")
local ModelAssets = Shim.load("src/shared/Config/ModelAssets.luau")
Shim.Globals = {}

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
}
