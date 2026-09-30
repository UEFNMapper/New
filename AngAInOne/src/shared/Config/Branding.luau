--!strict
--[[
	Branding : identité visuelle d'AngAInOne.

	⚠️ Pour afficher la VRAIE mascotte Anga dans le jeu :
	1. Dans Studio : onglet "Asset Manager" (ou Creator Dashboard) > Importer > ton image du logo.
	2. Copie l'ID de l'image (le numéro) et colle-le ci-dessous : AngaImageId = "rbxassetid://123456789".
	Tant que c'est vide, l'UI affiche un monogramme "A" rouge dans le style du t-shirt d'Anga.
]]

return table.freeze({
	GameName = "AngAInOne",
	Tagline = "Ton PC. De l'intérieur.",
	MascotName = "Anga",
	ChannelName = "AngaTV",
	AngaImageId = "", -- ex. "rbxassetid://1234567890"
})
