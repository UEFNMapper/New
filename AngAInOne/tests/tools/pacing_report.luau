local Shim = require("../lib/RobloxShim")
local Sim = require("../lib/PacingSim")(Shim)
local c = Sim.campaign(8)
for _, g in c.Generations do
	local parts = {}
	for k, v in g.Result.Unlocked do
		table.insert(parts, { k, v })
	end
	table.sort(parts, function(a, b)
		return a[2] < b[2]
	end)
	local s = ""
	for _, p in parts do
		s ..= string.format("%s %.0fmin, ", p[1], p[2] / 60)
	end
	print(
		string.format(
			"Gen %d: %s run %.1fh capShare %.0f%% pEff %.2f tEff %.2f fw %s",
			g.Gen,
			s,
			g.Result.Time / 3600,
			g.Result.CapacityShare * 100,
			g.Result.PowerEff,
			g.Result.ThermalEff,
			tostring(g.Firmware)
		)
	)
end
print("TOTAL h", c.TotalHours)
