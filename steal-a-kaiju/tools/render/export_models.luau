--!nocheck
-- Exporte les modèles de tous les kaijus (et œufs) en JSON pour le rendu d'aperçu.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Harness = require("../../tests/Harness")
local Shared, req = Harness.Shared("src/shared")
local Kaijus = req(Shared.Config.Kaijus)
local Mutations = req(Shared.Config.Mutations)
local Builder = req(Shared.KaijuBuilder)

local function dump(model)
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" and p.Transparency < 1 then
			local shape = "Block"
			if p.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif p:FindFirstChildOfClass("SpecialMesh") then
				shape = "Ellipsoid"
			elseif p.Shape == Harness.roblox.Enum.PartType.Cylinder then
				shape = "Cylinder"
			elseif p.Shape == Harness.roblox.Enum.PartType.Ball then
				shape = "Ball"
			end
			local cf = p.CFrame
			local c = { cf:GetComponents() }
			table.insert(parts, {
				shape = shape,
				size = { p.Size.X, p.Size.Y, p.Size.Z },
				cf = c,
				color = { p.Color.R, p.Color.G, p.Color.B },
				neon = p.Material == Harness.roblox.Enum.Material.Neon,
				transparency = p.Transparency,
			})
		end
	end
	return parts
end

local out = {}
local only = process.args[1]
for _, s in Kaijus.List do
	if not only or only == s.Id then
		local model = Builder.Build(s.Id, nil, 1)
		out[s.Id] = dump(model)
	end
end
for _, m in Mutations.List do
	out["Mut_" .. m.Id] = dump(Builder.Build("Rexplosion", m.Id, 1))
end
for _, r in { "Common", "Epic", "Legendary", "Secret" } do
	out["Egg_" .. r] = dump(Builder.BuildEgg(r, 1))
end
fs.writeFile("tools/render/models.json", serde.encode("json", out))
print("modèles exportés :", #Kaijus.List)
