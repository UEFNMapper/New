--[[
	Emplacements possibles pour un détour « Ventilo bonus » (Tower/Bonus.luau) : construit la tour SANS
	les détours, deux fois (avec les modèles 3D simulés, et avec le décor de secours : les deux décors
	doivent rester libres), puis, pour chaque checkpoint de chaque monde et chaque direction cardinale,
	vérifie que l'empreinte réelle du détour (passerelle, cadre du ventilateur, plateforme d'arrivée,
	panneau) reste dans la tour et ne traverse aucune pièce du monde (vide, plaque et motifs exclus).
	Usage : lune run tests/tools/BonusSpots.luau [monde]   (depuis AngAInOne)
	« face » = vers l'étape suivante (à éviter), « dos » = derrière le pad, « côté » = latéral.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local IsolatedTower = require("../lib/IsolatedTower")

local V3 = roblox.Vector3
local only = tonumber(process.args[1])

local function buildWithout(models: boolean)
	return IsolatedTower.Build({
		Models = models,
		Patch = {
			["src/server/World/Tower/Bonus.luau"] = function(Bonus)
				Bonus.Build = function() end
			end,
		},
	})
end
local built = buildWithout(true)
local fallbackBuilt = buildWithout(false)
local tower = built.Tower
local Bonus = built.Load("src/server/World/Tower/Bonus.luau")
local Common = built.Load("src/server/World/Tower/Common.luau")
local Tower = built.Load("src/shared/Config/Tower.luau")

-- Boîtes (min, max) du détour pour un pad `origin` (dessus) et une direction horizontale
local function footprint(origin: any, direction: any, start: number): { { any } }
	-- même repère que Bonus.Build (fromMatrix : CFrame.lookAt de Lune a le LookVector inversé)
	local frame = roblox.CFrame.fromMatrix(origin, direction:Cross(V3.yAxis), V3.yAxis, -direction)
	local boxes = {}
	local function box(distance: number, lift: number, size: any, side: number?)
		local center = (frame * roblox.CFrame.new(side or 0, lift, -distance)).Position
		-- étendue monde d'une boîte alignée sur le repère du détour (directions cardinales : pas de rotation)
		local half = V3.new(
			math.abs(frame.RightVector.X) * size.X / 2 + math.abs(frame.LookVector.X) * size.Z / 2,
			size.Y / 2,
			math.abs(frame.RightVector.Z) * size.X / 2 + math.abs(frame.LookVector.Z) * size.Z / 2
		)
		table.insert(boxes, { center - half, center + half })
	end
	local walkEnd = Bonus.LANDING_AT - 6
	box((start + walkEnd) / 2, -0.5, V3.new(Bonus.WALK_WIDTH + 1, 1, walkEnd - start))
	box(Bonus.LANDING_AT, -0.5, V3.new(12, 1, 12))
	local d = Bonus.FAN_DIAMETER
	box(Bonus.FAN_AT, Bonus.FAN_LIFT, V3.new(d * 1.12, d * 1.0, 6))
	box(start + 3, 3, V3.new(6, 6, 1), Bonus.WALK_WIDTH / 2 + 3.6)
	return boxes
end

local function overlaps(a: { any }, b: { any }): boolean
	return a[1].X < b[2].X - 0.3
		and a[2].X > b[1].X + 0.3
		and a[1].Y < b[2].Y - 0.3
		and a[2].Y > b[1].Y + 0.3
		and a[1].Z < b[2].Z - 0.3
		and a[2].Z > b[1].Z + 0.3
end

local DIRS = { ["+X"] = V3.xAxis, ["-X"] = -V3.xAxis, ["+Z"] = V3.zAxis, ["-Z"] = -V3.zAxis }

for w = 1, Tower.WORLD_COUNT do
	if only and w ~= only then
		continue
	end
	local parts = {}
	for _, source in { tower, fallbackBuilt.Tower } do
		for _, d in source:FindFirstChild(`World{w}`):GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local n = d.Name
				local skip = n == "Void"
					or n == "VoidB"
					or n == "Shelf"
					or string.find(n, "^Pcb")
					or d:HasTag("Checkpoint")
				if not skip then
					local lo, hi = IsolatedTower.Bounds(d)
					table.insert(parts, { lo, hi, d })
				end
			end
		end
	end
	for _, pad in tower.Checkpoints:GetChildren() do
		local stage = pad:GetAttribute("Stage")
		if Tower.WorldOf(stage) ~= w or stage >= Tower.TerminalStage(w) then
			continue
		end
		local origin = pad.CFrame.Position + V3.new(0, pad.Size.Y / 2, 0)
		local look = pad.CFrame.LookVector
		local lines = {}
		for name, dir in DIRS do
			local facing = dir:Dot(look)
			local kind = if facing > 0.7 then "face" elseif facing < -0.7 then "dos" else "côté"
			for _, start in { 7, 13 } do
				local boxes = footprint(origin, dir, start)
				local inside = true
				local hits = {}
				for _, b in boxes do
					if
						math.max(math.abs(b[1].X), math.abs(b[2].X), math.abs(b[1].Z), math.abs(b[2].Z))
						> Common.INNER - 2
					then
						inside = false
					end
					for _, p in parts do
						if overlaps(b, p) then
							hits[p[3].Name] = true
						end
					end
				end
				local names = {}
				for n in hits do
					table.insert(names, n)
				end
				table.sort(names)
				if inside and #names == 0 then
					table.insert(lines, `{name} ({kind}, départ {start})`)
					break
				elseif #names > 0 and #names <= 2 and inside then
					table.insert(lines, `{name} ({kind}, départ {start}) gêné par {table.concat(names, ", ")}`)
				end
			end
		end
		table.sort(lines)
		print(
			string.format(
				"W%d checkpoint %2d (%5.0f, %6.1f, %5.0f) regarde %s : %s",
				w,
				stage,
				origin.X,
				origin.Y,
				origin.Z,
				string.format("%+.0f,%+.0f", look.X, look.Z),
				if #lines > 0 then table.concat(lines, " · ") else "rien de libre"
			)
		)
	end
end
