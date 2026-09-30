--!strict
--[[
	TrapController (version provisoire) : remplacé par le vrai contrôleur des pièges.
]]

local TrapController = {}

TrapController.OnDeath = nil :: ((cause: string) -> ())?

function TrapController.Start() end

return TrapController
