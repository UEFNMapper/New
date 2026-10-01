--[[
	Lanceur de tests : `lune run tests/run.luau` (depuis le dossier AngAInOne).
	Chaque fichier tests/*.spec.luau renvoie une table { ["nom du test"] = function() ... end }.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")
local Shim = require("./lib/RobloxShim")
local Expect = require("./lib/Expect")
local PacingSim = require("./lib/PacingSim")
local FakeModels = require("./lib/FakeModels")
local PlayRoute = require("./lib/PlayRoute")
local IsolatedTower = require("./lib/IsolatedTower")
local roblox = require("@lune/roblox")

local filter = process.args[1]
local files = fs.readDir("tests")
table.sort(files)

local passed, failed = 0, 0
for _, file in files do
	if string.match(file, "%.spec%.luau$") and (not filter or string.find(file, filter, 1, true)) then
		local source = fs.readFile("tests/" .. file)
		local ok, specOrErr = pcall(function()
			return luau.load(source, {
				debugName = file,
				environment = {
					Shim = Shim,
					Expect = Expect,
					PacingSim = PacingSim,
					IsolatedTower = IsolatedTower, -- tour construite à part, avec modèles 3D simulés
					FakeModels = FakeModels, -- modèles 3D simulés (assets/models/bounds.json)
					PlayRoute = PlayRoute, -- parties simulées (ce que voit et atteint le joueur)
					Fs = fs,
					Vector3 = roblox.Vector3,
				},
			})()
		end)
		if not ok then
			print(`✗ {file} : échec du chargement\n    {specOrErr}`)
			failed += 1
			continue
		end
		local names = {}
		for name in specOrErr do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local start = os.clock()
			local success, err = pcall(specOrErr[name])
			local ms = math.floor((os.clock() - start) * 1000)
			if success then
				passed += 1
				print(`✓ {file} › {name} ({ms} ms)`)
			else
				failed += 1
				print(`✗ {file} › {name}\n    {err}`)
			end
		end
	end
end

print(`\n{passed} réussi(s), {failed} échoué(s)`)
process.exit(if failed > 0 then 1 else 0)
