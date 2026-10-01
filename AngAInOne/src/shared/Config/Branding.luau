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
	AngaImageId = "rbxassetid://79454493746475", -- portrait importé via Open Cloud : python3 tools/upload_models.py --portrait

	-- Logiciel partenaire : l'app AngAInOne (optimisation / maintenance de PC Windows).
	-- Son interface (gris Fluent + accent violet) est reprise par les écrans du monde.
	PartnerApp = {
		Name = "AngAInOne",
		Pitch = "L'app qui s'occupe de TOUT ton PC.",
		Version = "v5.9.0",
		Accent = "9B2FD4", -- violet des boutons de l'app
		Surface = "202020", -- fond de fenêtre
		Card = "2B2B2B", -- cartes
		CardHover = "323232",
		Text = "FFFFFF",
		TextDim = "C5C5C5",
		Good = "6CCB5F",
		Warn = "FCE100",
		Bad = "FF99A4",
		-- Sections de la barre latérale (les zones du jeu en débloquent une chacune).
		Sidebar = {
			"Tableau de bord",
			"Démarrage",
			"Applications",
			"Nettoyage & réparation",
			"Diagnostic",
			"Optimisations",
			"Gaming",
			"Réseau",
		},
	},
})
