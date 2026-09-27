--!strict
-- Icônes de l'interface (pack assets/icons/*.png : Fluent Emoji 3D + game-icons.net).
--
-- Pour chaque clé :
--   Id    : identifiant Roblox de l'IMAGE une fois uploadée (0 = pas encore uploadée).
--           Colle ici l'identifiant après upload (Bulk Import) ou lance tools/upload_assets.py,
--           qui remplit ce champ automatiquement.
--   Emoji : texte de secours affiché tant que Id == 0 (le jeu reste jouable sans upload).
--
-- Utilisation côté client :
--   local img = Icons.Image("shop")   -- "rbxassetid://123456" ou nil si pas uploadée
--   local txt = Icons.Emoji("shop")   -- "🛒"
--
-- Les clés sont triées par ordre alphabétique ; garde ce format d'une ligne par clé
-- (`cle = { Id = 0, Emoji = "…" },`) : tools/upload_assets.py s'appuie dessus.

export type IconDef = {
	Id: number,
	Emoji: string,
}

local Defs: { [string]: IconDef } = {
	alarm = { Id = 0, Emoji = "🚨" },
	arrow_down = { Id = 0, Emoji = "⬇️" },
	arrow_right = { Id = 0, Emoji = "➡️" },
	aurora = { Id = 0, Emoji = "🌌" },
	blood_moon = { Id = 0, Emoji = "🔴" },
	bonk = { Id = 0, Emoji = "🔨" },
	boss = { Id = 0, Emoji = "👹" },
	bridge = { Id = 0, Emoji = "🌉" },
	cash = { Id = 0, Emoji = "💸" },
	chat = { Id = 0, Emoji = "💬" },
	check = { Id = 0, Emoji = "✅" },
	code = { Id = 0, Emoji = "⌨️" },
	collect = { Id = 0, Emoji = "💰" },
	cross = { Id = 0, Emoji = "❌" },
	crown = { Id = 0, Emoji = "👑" },
	daily = { Id = 0, Emoji = "📅" },
	diamond = { Id = 0, Emoji = "💎" },
	dragon = { Id = 0, Emoji = "🐉" },
	egg = { Id = 0, Emoji = "🥚" },
	egg_celestial = { Id = 0, Emoji = "🥚" },
	egg_common = { Id = 0, Emoji = "🥚" },
	egg_epic = { Id = 0, Emoji = "🥚" },
	egg_legendary = { Id = 0, Emoji = "🥚" },
	egg_mythic = { Id = 0, Emoji = "🥚" },
	egg_rare = { Id = 0, Emoji = "🥚" },
	egg_secret = { Id = 0, Emoji = "🥚" },
	evolve = { Id = 0, Emoji = "🧬" },
	exit = { Id = 0, Emoji = "🚪" },
	eyes = { Id = 0, Emoji = "👀" },
	fire = { Id = 0, Emoji = "🔥" },
	food_feast = { Id = 0, Emoji = "🍗" },
	food_snack = { Id = 0, Emoji = "🍖" },
	food_steak = { Id = 0, Emoji = "🥩" },
	friends = { Id = 0, Emoji = "👥" },
	fusion = { Id = 0, Emoji = "⚗️" },
	fx = { Id = 0, Emoji = "🎇" },
	galaxy = { Id = 0, Emoji = "🌌" },
	gem = { Id = 0, Emoji = "💎" },
	ghost = { Id = 0, Emoji = "👻" },
	gifts = { Id = 0, Emoji = "🎁" },
	gold = { Id = 0, Emoji = "🪙" },
	group = { Id = 0, Emoji = "🫂" },
	growth = { Id = 0, Emoji = "🌱" },
	heart = { Id = 0, Emoji = "❤️" },
	home = { Id = 0, Emoji = "🏠" },
	hourglass = { Id = 0, Emoji = "⏳" },
	howtoplay = { Id = 0, Emoji = "❓" },
	island = { Id = 0, Emoji = "🏝️" },
	kaiju = { Id = 0, Emoji = "🦖" },
	kaijudex = { Id = 0, Emoji = "📖" },
	lightning = { Id = 0, Emoji = "⚡" },
	lock = { Id = 0, Emoji = "🔒" },
	luck = { Id = 0, Emoji = "🍀" },
	map = { Id = 0, Emoji = "🗺️" },
	medal_1 = { Id = 0, Emoji = "🥇" },
	medal_2 = { Id = 0, Emoji = "🥈" },
	medal_3 = { Id = 0, Emoji = "🥉" },
	meteor = { Id = 0, Emoji = "☄️" },
	moon = { Id = 0, Emoji = "🌕" },
	muscle = { Id = 0, Emoji = "💪" },
	music = { Id = 0, Emoji = "🎵" },
	nest = { Id = 0, Emoji = "🪺" },
	package = { Id = 0, Emoji = "📦" },
	pause = { Id = 0, Emoji = "⏸️" },
	play = { Id = 0, Emoji = "▶️" },
	potion_cash = { Id = 0, Emoji = "💰" },
	potion_growth = { Id = 0, Emoji = "🌱" },
	potion_luck = { Id = 0, Emoji = "🍀" },
	premium = { Id = 0, Emoji = "👑" },
	quests = { Id = 0, Emoji = "📜" },
	radioactive = { Id = 0, Emoji = "☢️" },
	rainbow = { Id = 0, Emoji = "🌈" },
	reactor = { Id = 0, Emoji = "⚛️" },
	rebirth = { Id = 0, Emoji = "🧬" },
	robux = { Id = 0, Emoji = "🪙" },
	settings = { Id = 0, Emoji = "⚙️" },
	shadow = { Id = 0, Emoji = "🌑" },
	shield = { Id = 0, Emoji = "🛡️" },
	shop = { Id = 0, Emoji = "🛒" },
	skull = { Id = 0, Emoji = "💀" },
	snowflake = { Id = 0, Emoji = "❄️" },
	sound_off = { Id = 0, Emoji = "🔇" },
	sound_on = { Id = 0, Emoji = "🔊" },
	sparkles = { Id = 0, Emoji = "✨" },
	speed = { Id = 0, Emoji = "👟" },
	spin = { Id = 0, Emoji = "🎡" },
	spins = { Id = 0, Emoji = "🎡" },
	stampede = { Id = 0, Emoji = "🦬" },
	star = { Id = 0, Emoji = "⭐" },
	sun = { Id = 0, Emoji = "🌅" },
	tab_boosts = { Id = 0, Emoji = "🚀" },
	tab_cash = { Id = 0, Emoji = "💵" },
	tab_gems = { Id = 0, Emoji = "💎" },
	tab_passes = { Id = 0, Emoji = "🎫" },
	tab_upgrades = { Id = 0, Emoji = "📈" },
	target = { Id = 0, Emoji = "🎯" },
	thief = { Id = 0, Emoji = "🥷" },
	timer = { Id = 0, Emoji = "⏱️" },
	tornado = { Id = 0, Emoji = "🌪️" },
	trophy = { Id = 0, Emoji = "🏆" },
	upgrades = { Id = 0, Emoji = "🔧" },
	volcano = { Id = 0, Emoji = "🌋" },
	warning = { Id = 0, Emoji = "⚠️" },
}

local Icons = {}

--- Toutes les définitions (lecture seule).
Icons.Defs = Defs

--- Retourne "rbxassetid://<Id>" pour la clé, ou nil si l'icône n'est pas encore uploadée
--- (Id == 0) ou si la clé est inconnue.
function Icons.Image(key: string): string?
	local def = Defs[key]
	if def == nil or def.Id == 0 then
		return nil
	end
	return "rbxassetid://" .. def.Id
end

--- Retourne l'emoji de secours pour la clé ("❔" si la clé est inconnue).
function Icons.Emoji(key: string): string
	local def = Defs[key]
	if def == nil then
		return "❔"
	end
	return def.Emoji
end

--- Vrai si la clé existe dans le pack.
function Icons.Has(key: string): boolean
	return Defs[key] ~= nil
end

return Icons
