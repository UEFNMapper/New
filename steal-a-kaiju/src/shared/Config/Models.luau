--!strict
-- Vrais modèles 3D des kaijus (pack assets/models/<Espèce>/, packs CC0 de Quaternius ;
-- voir assets/models/MANIFEST.json et LICENSES.md, aperçu : assets/models/contact_sheet.png).
--
-- Tant que MeshId == 0, le jeu construit le modèle procédural (KaijuBuilder). Dès qu'un
-- MeshId est renseigné, le client peut afficher le mesh importé à la place.
--
-- Champs :
--   MeshId     : identifiant du mesh uploadé (0 = pas encore importé).
--   TextureId  : identifiant de la texture (0 = pas de texture : couleurs plates du mesh).
--   Scale      : facteur pour que le kaiju fasse ~4,5 studs de haut au stade 1 (Baby),
--                calculé pour un import à l'échelle « 1 unité du fichier = 1 stud ».
--                Les stades suivants multiplient par Growth.Stages[i].Scale.
--   Offset     : décalage (studs, déjà multiplié par Scale) qui ramène le centre du mesh
--                au sol / au centre, si le fichier n'est pas déjà posé en (0,0,0).
--   Animations : identifiants des animations publiées (0 = pas encore publiée).
--   Source     : pack d'origine.  Quality : "good" | "ok" | "fallback" (voir MANIFEST.json ;
--                pour "fallback" mieux vaut garder le modèle procédural).
--
-- IMPORT DANS STUDIO (par espèce) --------------------------------------------------------
-- 1. Onglet Avatar → « 3D Importer » (ou Fichier → Import 3D…). Choisis le .fbx (ou le
--    .gltf/.glb) du dossier assets/models/<Espèce>/ ; la texture .png doit être dans le
--    même dossier (elle y est déjà).
-- 2. Dans le panneau d'import : « Scale Unit » = Studs (1 unité = 1 stud, sinon adapte
--    Scale), coche « Upload to Roblox » (indispensable pour obtenir un MeshId) et, pour les
--    modèles animés, garde « Import Animations » / « Rig type : Custom ». Valide.
-- 3. Un Model est inséré dans Workspace. Sélectionne son MeshPart (ou le premier s'il y en
--    a plusieurs) → Propriétés → « MeshId » = rbxassetid://NNNN : copie NNNN dans MeshId.
--    « TextureID » (ou SurfaceAppearance.ColorMap si un SurfaceAppearance a été créé)
--    donne TextureId. Sans texture (matériaux à couleurs plates), laisse 0 et vérifie
--    que les couleurs de sommets ont été importées (sinon MeshPart.Color = Primary).
-- 4. Animations : le rig importé contient un dossier « AnimSaves » (KeyframeSequences).
--    Ouvre Avatar → Animation Editor, sélectionne le rig, menu « … » → Load → choisis le
--    clip (ex. Idle, Walk — noms listés dans MANIFEST.json), puis « … » → « Publish to
--    Roblox » ; copie l'identifiant obtenu dans Animations.Idle / Animations.Walk.
--    (Alternative : « … » → Import → From FBX Animation, avec le même .fbx.)
-- 5. Supprime le Model de test du Workspace : le client instancie le mesh lui-même.
-- Les modèles « prop » (toast, croissant, donut, pizza, sushi, corn dog) n'ont ni rig ni
-- animation : laisse Animations à 0 ; le client garde ses animations procédurales.

export type ModelDef = {
	MeshId: number,
	TextureId: number,
	Scale: number,
	Offset: Vector3?,
	Animations: { Idle: number, Walk: number },
	Source: string,
	Quality: string,
}

local Defs: { [string]: ModelDef } = {
	-- Quaternius Ultimate Food / Bread_Slice (Bread_Slice.fbx, 0.847 unités de haut)
	Toastzilla = { MeshId = 0, TextureId = 0, Scale = 5.3127, Offset = Vector3.new(0.005, 2.609, 0), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Food", Quality = "ok" },
	-- Quaternius Ultimate Monsters / Blob/GreenBlob (GreenBlob.fbx, 1.853 unités de haut)
	Gloop = { MeshId = 0, TextureId = 0, Scale = 2.428, Offset = Vector3.new(-0.185, 0.029, -0.095), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "good" },
	-- Quaternius Cute Monsters / Crab (Crab.fbx, 1.567 unités de haut)
	Pinchy = { MeshId = 0, TextureId = 0, Scale = 2.8721, Offset = Vector3.new(0, 0.083, -0.063), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Cute Monsters", Quality = "good" },
	-- Quaternius Ultimate Monsters / Big/Dino (Dino.fbx, 3.226 unités de haut)
	DinoNugget = { MeshId = 0, TextureId = 0, Scale = 1.3949, Offset = Vector3.new(0, 0.004, -0.117), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "ok" },
	-- Quaternius Cute Fish / Worm (Worm.fbx, 0.484 unités de haut)
	Wormzy = { MeshId = 0, TextureId = 0, Scale = 9.2914, Offset = Vector3.new(-0.186, -0.019, 0.158), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Cute Fish", Quality = "good" },
	-- Quaternius Ultimate Monsters / Flying/Pigeon (Pigeon.fbx, 1.37 unités de haut)
	Pigeonator = { MeshId = 0, TextureId = 0, Scale = 3.2852, Offset = Vector3.new(0, -5.148, 0.545), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "good" },
	-- Quaternius Cute Fish / Shark (Shark.fbx, 3.79 unités de haut)
	Sharkapillar = { MeshId = 0, TextureId = 0, Scale = 1.1874, Offset = Vector3.new(-0.007, 1.55, 0.464), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Cute Fish", Quality = "ok" },
	-- Quaternius Ultimate Food / Croissant (Croissant.fbx, 0.55 unités de haut)
	Croissantosaurus = { MeshId = 0, TextureId = 0, Scale = 8.185, Offset = Vector3.new(0, 2.251, -0.737), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Food", Quality = "ok" },
	-- Quaternius Ultimate Monsters / Big/Yeti (Yeti.fbx, 2.828 unités de haut)
	Frostodon = { MeshId = 0, TextureId = 0, Scale = 1.5912, Offset = Vector3.new(0, 0.018, -0.145), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "ok" },
	-- Quaternius Ultimate Monsters / Flying/Squidle (Squidle.fbx, 1.987 unités de haut)
	ThunderSquid = { MeshId = 0, TextureId = 0, Scale = 2.2652, Offset = Vector3.new(0, -2.252, 0.836), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "good" },
	-- Quaternius Ultimate Food / Corndog (Corndog.fbx, 1.352 unités de haut)
	Kebabzilla = { MeshId = 0, TextureId = 0, Scale = 3.3288, Offset = nil, Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Food", Quality = "fallback" },
	-- Quaternius Animated Robot / Robot (Robot.fbx, 4.497 unités de haut)
	BeepBoop = { MeshId = 0, TextureId = 0, Scale = 1.0007, Offset = nil, Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Robot", Quality = "good" },
	-- Quaternius Sushi Restaurant Kit / Food/Food_SalmonNigiri (Food_SalmonNigiri.gltf, 0.314 unités de haut)
	SushiRex = { MeshId = 0, TextureId = 0, Scale = 14.3276, Offset = nil, Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Sushi Restaurant Kit", Quality = "fallback" },
	-- Quaternius Animated Mechs / Textured/George (George.fbx, 6.528 unités de haut)
	Robotank = { MeshId = 0, TextureId = 0, Scale = 0.6894, Offset = Vector3.new(0, 0.013, -0.293), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Mechs", Quality = "good" },
	-- Quaternius Animated Dinosaurs / Stegosaurus (Stegosaurus.fbx, 10.616 unités de haut)
	Magmadillo = { MeshId = 0, TextureId = 0, Scale = 0.4239, Offset = Vector3.new(0, 0.045, 1.632), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Dinosaurs", Quality = "ok" },
	-- Quaternius Animated Dinosaurs / Parasaurolophus (Parasaurolophus.fbx, 5.979 unités de haut)
	Bananadon = { MeshId = 0, TextureId = 0, Scale = 0.7526, Offset = Vector3.new(0, 0.007, 1.163), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Dinosaurs", Quality = "ok" },
	-- Quaternius Cute Monsters / Crab (Crab.fbx, 1.567 unités de haut)
	Crabzooka = { MeshId = 0, TextureId = 0, Scale = 2.8721, Offset = Vector3.new(0, 0.083, -0.063), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Cute Monsters", Quality = "ok" },
	-- Quaternius Ultimate Food / Pizza (Pizza.fbx, 0.161 unités de haut)
	Pizzapocalypse = { MeshId = 0, TextureId = 0, Scale = 27.9618, Offset = Vector3.new(-0.112, 0.391, 0.419), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Food", Quality = "ok" },
	-- Quaternius Animated Dinosaurs / Trex (Trex.fbx, 15.225 unités de haut)
	Rexplosion = { MeshId = 0, TextureId = 0, Scale = 0.2956, Offset = Vector3.new(0, 0.001, 0.321), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Dinosaurs", Quality = "good" },
	-- Quaternius Cute Monsters / Cthulhu (Cthulhu.fbx, 1.565 unités de haut)
	KawaiiKraken = { MeshId = 0, TextureId = 0, Scale = 2.8758, Offset = Vector3.new(0, 0.164, -0.167), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Cute Monsters", Quality = "ok" },
	-- Quaternius Ultimate Monsters / Blob/Chicken (Chicken.fbx, 2.347 unités de haut)
	ThunderGoose = { MeshId = 0, TextureId = 0, Scale = 1.9172, Offset = Vector3.new(0, 0.012, -0.477), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "ok" },
	-- Quaternius Ultimate Food / Donut1 (Donut1.fbx, 0.291 unités de haut)
	Donutron = { MeshId = 0, TextureId = 0, Scale = 15.4436, Offset = Vector3.new(-0.015, 1.961, -0.139), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Food", Quality = "ok" },
	-- Quaternius Animated Monsters / Dragon (Dragon.fbx, 3.852 unités de haut)
	Drakonda = { MeshId = 0, TextureId = 0, Scale = 1.1681, Offset = Vector3.new(0, -0.152, 0.051), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Monsters", Quality = "good" },
	-- Quaternius Ultimate Animated Animals / Bull (Bull.fbx, 4.587 unités de haut)
	Kaijumbo = { MeshId = 0, TextureId = 0, Scale = 0.9811, Offset = Vector3.new(0, 0.055, -1.034), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Animated Animals", Quality = "ok" },
	-- Quaternius Animated Dinosaurs / Velociraptor (Velociraptor.fbx, 5.514 unités de haut)
	Nebulodon = { MeshId = 0, TextureId = 0, Scale = 0.8161, Offset = Vector3.new(0, 0.043, 1.203), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Dinosaurs", Quality = "ok" },
	-- Quaternius Ultimate Monsters / Blob/Fish (Fish.fbx, 2.731 unités de haut)
	Hydroblob = { MeshId = 0, TextureId = 0, Scale = 1.6477, Offset = Vector3.new(0, -0.028, 0.091), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "good" },
	-- Quaternius Cute Monsters / Crab (Crab.fbx, 1.567 unités de haut)
	Crabageddon = { MeshId = 0, TextureId = 0, Scale = 2.8721, Offset = Vector3.new(0, 0.083, -0.063), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Cute Monsters", Quality = "ok" },
	-- Quaternius Animated Dinosaurs / Trex (Trex.fbx, 15.225 unités de haut)
	SolarisRex = { MeshId = 0, TextureId = 0, Scale = 0.2956, Offset = Vector3.new(0, 0.001, 0.321), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Dinosaurs", Quality = "ok" },
	-- Quaternius Ultimate Monsters / Flying/Hywirl (Hywirl.fbx, 2.745 unités de haut)
	LunarSquid = { MeshId = 0, TextureId = 0, Scale = 1.6394, Offset = Vector3.new(0, -0.044, 0.134), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "ok" },
	-- Quaternius Ultimate Monsters / Big/Birb (Birb.fbx, 3.328 unités de haut)
	CosmoGoose = { MeshId = 0, TextureId = 0, Scale = 1.3522, Offset = Vector3.new(0, 0.004, -0.238), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "ok" },
	-- Quaternius Cute Fish / GoblinShark (GoblinShark.fbx, 2.761 unités de haut)
	SharktoastSupreme = { MeshId = 0, TextureId = 0, Scale = 1.6298, Offset = Vector3.new(0, 1.82, 0.109), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Cute Fish", Quality = "fallback" },
	-- Quaternius Ultimate Monsters / Flying/Squidle (Squidle.fbx, 1.987 unités de haut)
	CroissantKraken = { MeshId = 0, TextureId = 0, Scale = 2.2652, Offset = Vector3.new(0, -2.252, 0.836), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "ok" },
	-- Quaternius Ultimate Monsters / Blob/Pigeon (Pigeon.fbx, 1.802 unités de haut)
	NuclearPigeon = { MeshId = 0, TextureId = 0, Scale = 2.4968, Offset = Vector3.new(0, -0.01, -0.509), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "good" },
	-- Quaternius Animated Mechs / Textured/Leela (Leela.fbx, 5.276 unités de haut)
	OmegaSushiMech = { MeshId = 0, TextureId = 0, Scale = 0.853, Offset = Vector3.new(0, 0.016, -0.253), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Animated Mechs", Quality = "good" },
	-- Quaternius Ultimate Monsters / Blob/PinkBlob (PinkBlob.fbx, 2.009 unités de haut)
	InfiniteBlob = { MeshId = 0, TextureId = 0, Scale = 2.2403, Offset = Vector3.new(0, 0.173, 0.175), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "good" },
	-- Quaternius Ultimate Monsters / Big/Demon (Demon.fbx, 3.12 unités de haut)
	KingKaiju = { MeshId = 0, TextureId = 0, Scale = 1.4421, Offset = Vector3.new(0, 0.022, 0.245), Animations = { Idle = 0, Walk = 0 }, Source = "Quaternius Ultimate Monsters", Quality = "ok" },
}

local Models = {}

--- Toutes les définitions (lecture seule), indexées par identifiant d'espèce.
Models.Defs = Defs

--- Définition pour une espèce, ou nil si aucun modèle n'est prévu.
function Models.Get(speciesId: string): ModelDef?
	return Defs[speciesId]
end

--- true si un mesh a été importé pour l'espèce (MeshId renseigné) : le client peut alors
--- afficher le vrai modèle au lieu du modèle procédural.
function Models.HasMesh(speciesId: string): boolean
	local def = Defs[speciesId]
	return def ~= nil and def.MeshId ~= 0
end

--- Identifiant d'animation publié pour l'espèce ("Idle" | "Walk"), ou nil.
function Models.AnimationId(speciesId: string, name: string): string?
	local def = Defs[speciesId]
	if def == nil then
		return nil
	end
	local id = def.Animations.Idle
	if name == "Walk" then
		id = def.Animations.Walk
	end
	if id == 0 then
		return nil
	end
	return "rbxassetid://" .. id
end

return Models
