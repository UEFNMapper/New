--!strict
--[[
	Badges Roblox (BadgeService) : un par monde nettoyé et un pour la victoire — les joueurs Roblox
	adorent collectionner. Les IDs se créent sur create.roblox.com → ton expérience → Badges, puis se
	collent ici ; 0 = badge pas encore créé (rien n'est attribué). Attribution : Services/AwardsService.
]]

return table.freeze({
	-- Monde 1 à 7 : « Alimentation réparée », « Memory Lanes nettoyée », …
	Worlds = table.freeze({ 0, 0, 0, 0, 0, 0, 0 }),
	-- LAGZ vaincu, le live a commencé
	Victory = 0,
})
