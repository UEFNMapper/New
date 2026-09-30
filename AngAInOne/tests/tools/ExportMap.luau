--[[
	Exporte la tour construite (TowerBuilder) en JSON pour un rendu sans Studio.
	Usage : lune run tests/tools/ExportMap.luau <sortie.json>   (depuis AngAInOne)
	Réutilise l'environnement de tests/tower.spec.luau (construction réelle avec les instances Lune).
	Puis : python3 tests/tools/render_iso.py <sortie.json> tower.png [options]  (voir render_iso.py)
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Shim = require("../lib/RobloxShim")
local Expect = require("../lib/Expect")

local source = fs.readFile("tests/tower.spec.luau")
-- Le spec construit la tour et la dépose dans Shim.LastTower.
luau.load(source, {
	debugName = "tower.spec.luau",
	environment = { Shim = Shim, Expect = Expect, Vector3 = roblox.Vector3, print = function() end },
})()
local captured = Shim.LastTower
assert(captured, "Tower introuvable")

local parts = {}
for _, part in captured:GetDescendants() do
	if part:IsA("BasePart") then
		local cf = part.CFrame
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		table.insert(parts, {
			n = part.Name,
			p = { x, y, z },
			r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
			s = { part.Size.X, part.Size.Y, part.Size.Z },
			c = { part.Color.R, part.Color.G, part.Color.B },
			t = part.Transparency,
			m = part.Material.Name,
			sh = if part:IsA("Part") then part.Shape.Name elseif part:IsA("WedgePart") then "Wedge" else part.ClassName,
			col = part.CanCollide,
			tg = part:GetTags(),
		})
	end
end
fs.writeFile(process.args[1], serde.encode("json", parts))
print(`{#parts} pièces exportées`)
