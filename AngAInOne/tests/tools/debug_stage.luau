--[[
	Affiche le plus court chemin (en sauts) du graphe de tests/tower.spec.luau pour une étape.
	Usage : lune run tests/tools/debug_stage.luau <étape>   (depuis AngAInOne)
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Shim = require("../lib/RobloxShim")
local Expect = require("../lib/Expect")

local stage = tonumber(process.args[1]) or 1
local source = fs.readFile("tests/tower.spec.luau")
luau.load(source, {
	debugName = "tower.spec.luau",
	environment = { Shim = Shim, Expect = Expect, Vector3 = roblox.Vector3, print = function() end },
})()
local debug = Shim.TowerDebug
assert(debug, "Shim.TowerDebug introuvable")
for i, step in debug.Path(stage) do
	print(
		string.format(
			"%2d  %-60s y=%.1f  x=[%.1f, %.1f] z=[%.1f, %.1f]",
			i,
			step.Name,
			step.Y,
			step.X0,
			step.X1,
			step.Z0,
			step.Z1
		)
	)
end
