--!strict
-- Sons du jeu.
--   Default  : son public de la bibliothèque Roblox (fonctionne tout de suite).
--   Uploaded : identifiant de la version ORIGINALE du pack assets/audio/ une fois
--              uploadée dans ton compte (prioritaire si ≠ 0).
-- Volume/PlaybackSpeed : réglages de base ; le client ajoute une légère
-- variation de hauteur pour éviter la répétition.

export type SoundDef = {
	Default: string,
	Uploaded: number,
	Volume: number,
	Speed: number?,
	Looped: boolean?,
}

local function D(id: number | string, volume: number, speed: number?, looped: boolean?): SoundDef
	local default = if typeof(id) == "number" then "rbxassetid://" .. id else id
	return { Default = default :: string, Uploaded = 0, Volume = volume, Speed = speed, Looped = looped }
end

local Sounds: { [string]: SoundDef } = {
	-- UI
	ui_click = D(15675059323, 0.5),
	ui_hover = D(17208339919, 0.25),
	ui_open = D(15675028888, 0.45),
	ui_close = D(15674975792, 0.4, 1.15),
	ui_error = D(17208214688, 0.5),
	ui_tab = D(15675032796, 0.45),
	-- Économie
	cash_collect = D(9113849492, 0.6),
	coin_tick = D(127645268874265, 0.35, 1.3),
	purchase = D(9113728049, 0.6),
	sell = D(9113726510, 0.55),
	-- Météores
	meteor_whistle = D(12222095, 0.7, 0.6),
	meteor_impact = D("rbxasset://sounds/impact_explosion_03.mp3", 0.8),
	meteor_rare_alarm = D(9126073001, 0.8),
	-- Œufs / kaijus
	egg_wobble = D(15675055424, 0.5, 0.8),
	egg_crack = D(9113263649, 0.6),
	hatch_common = D(9125640290, 0.7),
	hatch_epic = D(9116384485, 0.8),
	hatch_legendary = D(1836473422, 0.8),
	hatch_secret = D(1845411858, 0.9),
	stage_up = D(9116395089, 0.7),
	roar_small = D(9113985604, 0.5, 1.4),
	roar_big = D(9113980319, 0.8),
	-- Vol / défense
	steal_grab = D(17208319162, 0.6),
	alarm = D(9119162409, 0.55, 1, true),
	bonk = D(12222046, 0.8, 0.8),
	knockback_whoosh = D(15675012262, 0.6),
	shield_on = D(17208327798, 0.7),
	shield_zap = D(9113085801, 0.5, 1.6),
	drop = D("rbxasset://sounds/action_jump_land.mp3", 0.8),
	heist_success = D(1844584698, 0.8),
	-- Progression
	rebirth = D(9041812129, 0.9),
	fusion_charge = D(17208327798, 0.8, 0.6),
	fusion_boom = D(9126102254, 0.8),
	reward_claim = D(17208380755, 0.7),
	quest_complete = D(12222253, 0.7),
	level_jingle = D(12222253, 0.6, 1.1),
	spin_tick = D(15675032796, 0.35, 1.4),
	spin_win = D(1836301731, 0.8),
	event_horn = D(9119162409, 0.8, 0.7),
	countdown_beep = D(17208361335, 0.6),
	boss_stomp = D(9114224354, 0.9),
	whoosh = D(15675028888, 0.5),
	-- Musique
	music_main = D(9043821805, 0.32, 1, true),
	music_event = D(1842174239, 0.34, 1, true),
	music_boss = D(9046119816, 0.36, 1, true),
	music_lobby_calm = D(9043887091, 0.3, 1, true),
}

return Sounds
