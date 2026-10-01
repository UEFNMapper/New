--[[
	Volumes libres : liste les pièces de la tour (modèles simulés ET décor de secours) qui traversent
	des boîtes candidates (min, max). Sert à poser une mécanique (ventilo propulseur, bloatware…) sans
	toucher le décor existant.
	Usage : lune run tests/tools/FreeBoxes.luau
]]
local roblox = require("@lune/roblox")
local IsolatedTower = require("../lib/IsolatedTower")

local V3 = roblox.Vector3

local CANDIDATES = {
	{ "M4 · plateforme du ventilo propulseur", V3.new(20, 330, -15), V3.new(38.5, 332, -1) },
	{ "M4 · colonne de vol", V3.new(20, 332, -15), V3.new(38.5, 360, -1) },
	{ "M4 · corniche haute", V3.new(19, 350, -15), V3.new(29, 352, -1) },
	{ "M5 · bloatware passerelle VRM", V3.new(-21, 414.5, -78.5), V3.new(-11, 422.5, -75.5) },
	{ "M5 · bloatware grille de broches", V3.new(3.5, 460, -48.5), V3.new(20.5, 468, -45.5) },
	{ "M5 · bloatware seuil", V3.new(74.5, 480, -96.5), V3.new(77, 489, -79.5) },
}

local function overlaps(part: any, lo: any, hi: any): boolean
	local cf, size = part.CFrame, part.Size
	-- boîte englobante monde de la pièce (rotation comprise)
	local half = V3.new(
		math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z,
		math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z,
		math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z
	) / 2
	local p = cf.Position
	return p.X + half.X > lo.X
		and p.X - half.X < hi.X
		and p.Y + half.Y > lo.Y
		and p.Y - half.Y < hi.Y
		and p.Z + half.Z > lo.Z
		and p.Z - half.Z < hi.Z
end

for _, models in { true, false } do
	local built = IsolatedTower.Build({ Models = models })
	print(if models then "== modèles 3D simulés" else "== décor de secours")
	for _, candidate in CANDIDATES do
		local hits = {}
		for _, part in built.Tower:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 and overlaps(part, candidate[2], candidate[3]) then
				table.insert(
					hits,
					`{part.Name} ({part.Parent and part.Parent.Name}) {part.CanCollide and "solide" or "décor"}`
				)
			end
		end
		print(`  {candidate[1]} : {if #hits == 0 then "libre" else table.concat(hits, ", ")}`)
	end
end
