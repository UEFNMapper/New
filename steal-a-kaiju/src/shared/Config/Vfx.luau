--!strict
-- Textures des effets visuels (particules) : pack assets/vfx/*.png (CC0, Kenney Particle
-- Pack + Kenney Smoke Particles + quelques sprites générés par tools/models/curate_vfx.py).
--
-- Pour chaque clé :
--   Id      : identifiant Roblox de l'IMAGE une fois uploadée (0 = pas encore uploadée).
--             Asset Manager → Bulk Import des PNG de assets/vfx/, puis colle l'identifiant
--             (ou lance tools/upload_assets.py qui remplit ce champ).
--   Default : texture INTÉGRÉE au client Roblox (rbxasset://) utilisée tant que Id == 0.
--             Le jeu reste donc jouable sans aucun upload.
--
-- Utilisation :
--   emitter.Texture = Vfx.Texture("spark")   -- "rbxassetid://123" ou la texture intégrée
--
-- Les sprites du pack sont blancs sur fond transparent : la couleur vient de
-- ParticleEmitter.Color / Beam.Color. Exception : `confetti` est déjà coloré (garde Color blanc).
-- Garde ce format d'une ligne par clé (`cle = { Id = 0, Default = "…" },`) pour l'outil d'upload.

export type VfxDef = {
	Id: number,
	Default: string,
}

local P = "rbxasset://textures/particles/"
local T = "rbxasset://textures/"

local Defs: { [string]: VfxDef } = {
	bolt = { Id = 0, Default = P .. "fire_sparks_main.dds" },
	bubble = { Id = 0, Default = T .. "smallWhiteCircle.png" },
	circle = { Id = 0, Default = T .. "whiteCircle.png" },
	cloud = { Id = 0, Default = P .. "explosion01_smoke_main.dds" },
	confetti = { Id = 0, Default = P .. "SquareParticle.png" },
	drip = { Id = 0, Default = T .. "smallWhiteCircle.png" },
	dust = { Id = 0, Default = P .. "smoke_main.dds" },
	fire = { Id = 0, Default = P .. "fire_main.dds" },
	flare = { Id = 0, Default = T .. "sparkle.png" },
	glow_hard = { Id = 0, Default = T .. "whiteCircle.png" },
	glow_soft = { Id = 0, Default = T .. "glow.png" },
	heart = { Id = 0, Default = T .. "whiteCircle.png" },
	leaf = { Id = 0, Default = P .. "SquareParticle.png" },
	lightning = { Id = 0, Default = P .. "fire_sparks_main.dds" },
	magic = { Id = 0, Default = P .. "sparkles_main.dds" },
	meteor_trail = { Id = 0, Default = P .. "fire_main.dds" },
	muzzle = { Id = 0, Default = P .. "explosion01_core_main.dds" },
	radioactive = { Id = 0, Default = P .. "forcefield_glow_main.dds" },
	ring = { Id = 0, Default = P .. "explosion01_shockwave_main.dds" },
	scorch = { Id = 0, Default = P .. "explosion01_core_main.dds" },
	shockwave = { Id = 0, Default = P .. "explosion01_shockwave_main.dds" },
	skull = { Id = 0, Default = T .. "whiteCircle.png" },
	slash = { Id = 0, Default = T .. "gradient.png" },
	smoke = { Id = 0, Default = P .. "smoke_main.dds" },
	spark = { Id = 0, Default = P .. "fire_sparks_main.dds" },
	sparkle = { Id = 0, Default = T .. "sparkle.png" },
	star4 = { Id = 0, Default = P .. "sparkles_main.dds" },
	star5 = { Id = 0, Default = P .. "sparkles_main.dds" },
	trail = { Id = 0, Default = T .. "gradient.png" },
	twirl = { Id = 0, Default = P .. "forcefield_vortex_main.dds" },
}

local FALLBACK = P .. "sparkles_main.dds"

local Vfx = {}

--- Toutes les définitions (lecture seule).
Vfx.Defs = Defs

--- Retourne la texture à utiliser pour la clé : "rbxassetid://<Id>" si le sprite du pack
--- a été uploadé (Id ~= 0), sinon la texture intégrée `Default`. Clé inconnue → étincelles.
function Vfx.Texture(key: string): string
	local def = Defs[key]
	if def == nil then
		return FALLBACK
	end
	if def.Id ~= 0 then
		return "rbxassetid://" .. def.Id
	end
	return def.Default
end

return Vfx
