--!strict
--[[
	HudFormat : petits formats PURS du HUD (testés dans Lune : tests/moments.spec.luau).
	- Ping : « 48 ms » jusqu'à 999 ms, puis « 2,4 s » (tient dans la pastille, lisible par un enfant)
]]

local HudFormat = {}

function HudFormat.Ping(ms: number): string
	local value = math.max(math.floor(ms + 0.5), 0)
	if value <= 999 then
		return `{value} ms`
	end
	local tenths = math.floor(value / 100 + 0.5)
	local whole = math.floor(tenths / 10)
	return `{whole},{tenths - whole * 10} s`
end

return HudFormat
