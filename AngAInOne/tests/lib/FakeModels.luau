--[[
	FakeModels : simule les VRAIS modèles 3D (assets/models/*.glb) dans Lune, sans Roblox.
	Chaque noeud-maillage du fichier devient une Part de sa boîte englobante (assets/models/bounds.json,
	généré par tools/model_bounds.py), nommée comme dans le fichier : la convention
	<Nom>__<Matériau>__<RRGGBB>[__Spin] est donc lue, et ORIENT / ORIGIN de ModelLibrary s'appliquent,
	par le même chemin qu'un asset chargé (ModelLibrary._SetTemplate → prepare).
	Suffisant pour juger un PLACEMENT (position, échelle, orientation, flottement), pas un rendu.
]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local FakeModels = {}

type Box = { name: string, min: { number }, max: { number }, tris: number }
type Entry = { min: { number }, max: { number }, size: { number }, tris: number, parts: { Box } }

local BOUNDS = "assets/models/bounds.json"
local bounds: { [string]: Entry }? = nil

local function data(): { [string]: Entry }
	if not bounds then
		assert(fs.isFile(BOUNDS), `{BOUNDS} manquant : python3 tools/model_bounds.py`)
		bounds = serde.decode("json", fs.readFile(BOUNDS))
	end
	return bounds :: { [string]: Entry }
end

-- Clés disponibles (triées).
function FakeModels.Keys(): { string }
	local keys = {}
	for key in data() do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Boîte globale du fichier : taille (x, y, z) et minimum, en unités modélisées.
function FakeModels.Size(key: string): (any, any)
	local entry = data()[key]
	assert(entry, `modèle inconnu : {key}`)
	return roblox.Vector3.new(entry.size[1], entry.size[2], entry.size[3]),
		roblox.Vector3.new(entry.min[1], entry.min[2], entry.min[3])
end

-- Rotation simulée de l'import Roblox (tests : un asset tourné doit être recalibré par ModelLibrary).
FakeModels.ImportRotation = nil :: any?
-- Échelle simulée de l'import (ex. 1 unité du fichier = 2 studs).
FakeModels.ImportScale = nil :: number?

-- Construit le modèle simulé (une Part par noeud-maillage, boîtes englobantes). `rotation` (ou
-- FakeModels.ImportRotation) : l'asset arrive tourné autour du centre de sa boîte, comme après un import.
function FakeModels.Build(key: string, rotation: any?): any
	local entry = data()[key]
	assert(entry, `modèle inconnu : {key}`)
	local model = roblox.Instance.new("Model")
	model.Name = key
	model:SetAttribute("FakeModel", key)
	for _, box in entry.parts do
		local part = roblox.Instance.new("Part")
		part.Name = box.name
		part.Size = roblox.Vector3.new(
			math.max(box.max[1] - box.min[1], 0.05),
			math.max(box.max[2] - box.min[2], 0.05),
			math.max(box.max[3] - box.min[3], 0.05)
		)
		part.CFrame = roblox.CFrame.new(
			(box.min[1] + box.max[1]) / 2,
			(box.min[2] + box.max[2]) / 2,
			(box.min[3] + box.max[3]) / 2
		)
		part.Anchored = true
		part.Parent = model
	end
	local unit = FakeModels.ImportScale
	if unit and unit ~= 1 then
		for _, part in model:GetChildren() do
			part.Size *= unit
			part.CFrame = part.CFrame.Rotation + part.CFrame.Position * unit
		end
	end
	local turn = rotation or FakeModels.ImportRotation
	if turn then
		local k = unit or 1
		local center = roblox.CFrame.new(
			(entry.min[1] + entry.max[1]) / 2 * k + 3,
			(entry.min[2] + entry.max[2]) / 2 * k - 1,
			(entry.min[3] + entry.max[3]) / 2 * k + 5
		) -- (+ un décalage : l'import peut aussi déplacer le modèle)
		for _, part in model:GetChildren() do
			part.CFrame = center * turn * part.CFrame
		end
	end
	return model
end

-- Installe tous les modèles (ou `keys`) dans une instance de ModelLibrary, comme s'ils étaient importés.
function FakeModels.Install(ModelLibrary: any, keys: { string }?)
	for _, key in keys or FakeModels.Keys() do
		ModelLibrary._SetTemplate(key, FakeModels.Build(key))
	end
end

return FakeModels
