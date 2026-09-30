--!strict
--[[
	Monde 3 : Data Vault (SSD). Pour l'instant, le parcours et le décor v1 (Tower/Legacy).
	À réécrire en phase 2 avec les outils du contexte (voir l'en-tête de Tower/Common.luau).
]]

local Common = require(script.Parent.Parent.Common)
local Legacy = require(script.Parent.Parent.Legacy)

return function(ctx: Common.WorldContext)
	ctx.Void()
	Legacy.Decor(ctx)
	ctx.Entrance()
	Legacy.Course(ctx)
	ctx.TerminalRoom()
end
