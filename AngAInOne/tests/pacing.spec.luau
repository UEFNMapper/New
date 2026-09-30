--[[
	Garde-fou d'équilibrage : rejoue la progression avec la vraie config et vérifie
	que le rythme reste dans les bornes du GDD. Si tu modifies GameConfig/Modules/Zones
	et que ce test échoue, lance `lune run tests/tools/pacing_report.luau` pour voir le détail.
]]
local Sim = PacingSim(Shim)
local GameConfig = Shim.load("src/shared/Config/GameConfig.luau")

local campaign = Sim.campaign(10)
local gen1 = campaign.Generations[1].Result

return {
	["1er run : déblocages dans les fenêtres du GDD (minutes)"] = function()
		local u = gen1.Unlocked
		Expect.between(u.RAM / 60, 2, 5, "RAM")
		Expect.between(u.SSD / 60, 7, 16, "SSD")
		Expect.between(u.Cooling / 60, 25, 60, "Cryo Tower")
		Expect.between(u.CPU / 60, 70, 160, "CPU")
		Expect.between(u.GPU / 60, 200, 420, "GPU")
	end,
	["énergie et refroidissement : coût raisonnable, jamais bloquants"] = function()
		Expect.between(gen1.CapacityShare, 0.03, 0.2, "part des dépenses en capacité")
		Expect.truthy(gen1.PowerEff >= 0.95, "efficacité électrique en fin de run")
		Expect.truthy(gen1.ThermalEff >= 0.95, "efficacité thermique en fin de run")
	end,
	["la Singularité est atteignable en 10 à 25 h de jeu optimal"] = function()
		Expect.between(campaign.TotalHours, 10, 25, "heures jusqu'à la fin")
		Expect.between(#campaign.Generations, 3, 8, "nombre de générations")
	end,
	["le 1er Reboot rapporte au moins x1,5"] = function()
		local firmware = campaign.Generations[1].Firmware
		Expect.truthy(1 + firmware * GameConfig.Reboot.FirmwarePerPoint >= 1.5, "multiplicateur après le 1er Reboot")
	end,
	["les phases de la Singularité coûtent ≈ SingularityCost"] = function()
		local sum = 0
		for _, cost in GameConfig.SingularityPhases do
			sum += cost
		end
		Expect.between(sum / GameConfig.SingularityCost, 0.95, 1.05)
	end,
}
