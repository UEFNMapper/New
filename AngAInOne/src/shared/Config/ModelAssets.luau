--!strict
--[[
	ModelAssets : identifiants Roblox des modèles 3D (assets/models/*.glb).
	Rempli AUTOMATIQUEMENT par tools/upload_models.py (Open Cloud), ou à la main après un
	import dans Studio (voir assets/README.md). Un modèle absent = décor de secours (primitives).
	Clé = nom du fichier .glb sans extension ; valeur = ID de l'asset Model.
]]

local ModelAssets: { [string]: number } = {
	-- généré : ne pas éditer à la main entre les deux marqueurs
	-- BEGIN
	-- END
}

return table.freeze(ModelAssets)
