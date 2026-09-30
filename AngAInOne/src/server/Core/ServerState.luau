--!strict
--[[
	ServerState : état global du serveur (non sauvegardé), lisible par tous les services.
]]

local ServerState = {
	ServerBoostUntil = 0, -- os.time() de fin du Server Boost (x2 pour tout le serveur)
	ServerBoostBy = "", -- nom du joueur qui l'a offert
}

return ServerState
