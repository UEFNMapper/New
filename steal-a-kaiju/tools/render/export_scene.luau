--!nocheck
-- Exporte une scène de jeu simulée (carte + kaijus rendus par le client) en JSON.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Boot = require("../../tests/sim/boot")
local Runtime = Boot.Start()
local ClientRuntime = require("../../tests/sim/ClientRuntime")
ClientRuntime.Install(Runtime)
Runtime.Validate = false
local S = Runtime.Services
local function req(inst)
	return Runtime.Globals.require(inst)
end
local Services = S.ServerScriptService:FindFirstChild("Server"):FindFirstChild("Services")
local KaijuService = req(Services:FindFirstChild("KaijuService"))
local Growth = req(S.ReplicatedStorage:FindFirstChild("Shared").Config.Growth)

local hero = ClientRuntime.StartClient(Runtime, "Hero")
local rival = Runtime.AddPlayer("Rival")
Runtime.Advance(10)
local DataService = req(Services:FindFirstChild("DataService"))
local PlotService = req(Services:FindFirstChild("PlotService"))
DataService.Get(hero).Nests = 16
PlotService.RefreshNests(hero)
-- Une île bien remplie : tous les stades et quelques mutations
local roster = {
	{ "Rexplosion", nil, 5 }, { "Kaijumbo", "Gold", 4 }, { "ThunderGoose", nil, 4 }, { "Drakonda", "Radioactive", 3 },
	{ "KawaiiKraken", nil, 3 }, { "SushiRex", "Diamond", 3 }, { "Robotank", nil, 2 }, { "Pizzapocalypse", nil, 2 },
	{ "Crabzooka", "Blood", 2 }, { "Frostodon", nil, 2 }, { "Toastzilla", nil, 1 }, { "BeepBoop", nil, 1 },
	{ "Magmadillo", nil, 2 }, { "Donutron", nil, 3 }, { "SolarisRex", nil, 1 },
}
for _, r in roster do
	local species = r[1]
	local rarity = require("@lune/roblox") and nil
	KaijuService.AddHatched(hero, species, r[2], Growth.Threshold(r[3], "Secret") * 0 + (function()
		local Kaijus = req(S.ReplicatedStorage:FindFirstChild("Shared").Config.Kaijus)
		return Growth.Threshold(r[3], Kaijus.Get(species).Rarity) + 1
	end)())
end
Runtime.Advance(3)

local parts = {}
local function add(p)
	if not p:IsA("BasePart") then
		return
	end
	if (p.Transparency or 0) >= 0.95 then
		return
	end
	local shape = "Block"
	if p.ClassName == "WedgePart" then
		shape = "Wedge"
	elseif p:FindFirstChildOfClass("SpecialMesh") then
		shape = "Ellipsoid"
	elseif p.Shape == roblox.Enum.PartType.Cylinder then
		shape = "Cylinder"
	elseif p.Shape == roblox.Enum.PartType.Ball then
		shape = "Ball"
	end
	local c = p.Color or roblox.Color3.new(0.6, 0.6, 0.6)
	table.insert(parts, {
		shape = shape,
		size = { p.Size.X, p.Size.Y, p.Size.Z },
		cf = { p.CFrame:GetComponents() },
		color = { c.R, c.G, c.B },
		neon = p.Material == roblox.Enum.Material.Neon,
		transparency = p.Transparency or 0,
	})
end
for _, folderName in { "Map", "ClientKaijus", "ClientMeteors" } do
	local f = S.Workspace:FindFirstChild(folderName)
	if f then
		for _, d in f:GetDescendants() do
			add(d)
		end
	end
end
-- position de l'île du héros pour cadrer la caméra
local plotIndex = hero:GetAttribute("Plot")
local plot = S.Workspace:FindFirstChild("Map"):FindFirstChild("Plot" .. plotIndex)
local floor = plot:FindFirstChild("Floor")
fs.writeFile("tools/render/scene.json", serde.encode("json", {
	parts = parts,
	focus = { floor.Position.X, floor.Position.Y, floor.Position.Z },
	look = { floor.CFrame.LookVector.X, floor.CFrame.LookVector.Y, floor.CFrame.LookVector.Z },
}))
print("parts exportées :", #parts, "erreurs :", #Runtime.Errors)
