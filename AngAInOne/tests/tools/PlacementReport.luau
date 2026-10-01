--[[
	Rapport de PLACEMENT des vrais modèles 3D, sans Roblox : construit la tour avec les modèles
	simulés (boîtes englobantes des .glb) et décrit chaque pose (Place / Dress / Weld).
	Usage : lune run tests/tools/PlacementReport.luau [filtre]   (depuis AngAInOne)
	Colonnes : monde · clé · taille posée · Fit demandé · usage du Fit par axe (part de la boîte
	cible réellement occupée : un axe « vide » = modèle couché ou Fit trop lâche) · écart entre le
	bas du modèle et le support solide sous son centre (> 0 : flotte ; < 0 : enfoncé) · pour Dress,
	écart de centre et rapport de taille avec les primitives habillées.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local IsolatedTower = require("../lib/IsolatedTower")

local filter = process.args[1]
local records = {}

local function worldOf(instance: any): string
	local node = instance
	while node do
		local w = node:GetAttribute("World")
		if type(w) == "number" then
			return `W{w}`
		end
		if node.Name == "Lobby" or node.Name == "Shell" then
			return node.Name
		end
		node = node.Parent
	end
	return "?"
end

local function fmt(v: any): string
	return string.format("%.1f×%.1f×%.1f", v.X, v.Y, v.Z)
end

local built = IsolatedTower.Build({
	Models = true,
	Observe = function(ModelLibrary)
		local realPlace, realDress, realWeld = ModelLibrary.Place, ModelLibrary.Dress, ModelLibrary.Weld
		ModelLibrary.Place = function(key, cframe, parent, options, fallback)
			local placed = realPlace(key, cframe, parent, options, fallback)
			if placed and ModelLibrary.Has(key) then
				table.insert(records, { Kind = "Place", Key = key, CFrame = cframe, Options = options, Model = placed })
			end
			return placed
		end
		ModelLibrary.Dress = function(key, cframe, parent, options, primitives)
			local lo, hi = nil, nil
			for _, primitive in primitives do
				local plo, phi = IsolatedTower.Bounds(primitive)
				if plo then
					lo = if lo then lo:Min(plo) else plo
					hi = if hi then hi:Max(phi) else phi
				end
			end
			local placed = realDress(key, cframe, parent, options, primitives)
			if placed then
				table.insert(records, {
					Kind = "Dress",
					Key = key,
					CFrame = cframe,
					Options = options,
					Model = placed,
					PrimLo = lo,
					PrimHi = hi,
				})
			end
			return placed
		end
		ModelLibrary.Weld = function(key, root, cframe, options)
			local placed = realWeld(key, root, cframe, options)
			if placed then
				table.insert(
					records,
					{ Kind = "Weld", Key = key, CFrame = cframe, Options = options, Model = placed, Root = root }
				)
			end
			return placed
		end
	end,
})

-- Boîte des BaseParts de `root` dans le repère LOCAL `cframe` (taille dans les axes du modèle posé).
local function localSize(root: any, cframe: any): any
	local inverse = cframe:Inverse()
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			local cf, size = inverse * part.CFrame, part.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
			local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
			local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
			local p = cf.Position
			x0, y0, z0 = math.min(x0, p.X - hx), math.min(y0, p.Y - hy), math.min(z0, p.Z - hz)
			x1, y1, z1 = math.max(x1, p.X + hx), math.max(y1, p.Y + hy), math.max(z1, p.Z + hz)
		end
	end
	return roblox.Vector3.new(x1 - x0, y1 - y0, z1 - z0)
end

-- Dessus du support solide (CanCollide, hors modèles simulés) le plus haut sous le point (x, z),
-- pas plus haut que `limit`, dans toute la tour. Renvoie la hauteur et le nom de la pièce.
local function supportBelow(tower: any, x: number, limit: number, z: number): (number?, string?)
	local best, name = nil, nil
	for _, part in tower:GetDescendants() do
		if
			part:IsA("BasePart")
			and part.CanCollide
			and part.Transparency < 1
			and not (part.Parent and part.Parent:GetAttribute("FakeModel"))
		then
			local lo, hi = IsolatedTower.Bounds(part)
			if lo and x >= lo.X - 0.3 and x <= hi.X + 0.3 and z >= lo.Z - 0.3 and z <= hi.Z + 0.3 and hi.Y <= limit then
				if not best or hi.Y > best then
					best, name = hi.Y, part.Name
				end
			end
		end
	end
	return best, name
end

local lines = {}
local seen = {}
for _, rec in records do
	local lo, hi = IsolatedTower.Bounds(rec.Model)
	if not lo then
		continue
	end
	local size = hi - lo
	local world = worldOf(rec.Model)
	local label = `{world} {rec.Kind} {rec.Key}`
	seen[label] = (seen[label] or 0) + 1
	if filter and not string.find(label, filter, 1, true) then
		continue
	end
	if seen[label] > 3 then
		continue -- séries répétées (condensateurs, selfs…) : 3 exemples suffisent
	end
	local fit = rec.Options and rec.Options.Fit
	local usage = "—"
	if fit then
		local function part(a: number, b: number): string
			return if b == math.huge then "·" else string.format("%d%%", math.floor(a / b * 100 + 0.5))
		end
		local ls = localSize(rec.Model, rec.CFrame)
		usage = `{part(ls.X, fit.X)} {part(ls.Y, fit.Y)} {part(ls.Z, fit.Z)}`
	end
	-- support : plus haute surface solide sous le centre, pas plus haute que le bas du modèle + 3/4 de
	-- sa hauteur (un modèle volontairement enfoncé garde son vrai support)
	local support, supportName = supportBelow(built.Tower, (lo.X + hi.X) / 2, lo.Y + size.Y * 0.75, (lo.Z + hi.Z) / 2)
	local gap = if support then string.format("%+.1f (%s)", lo.Y - support, supportName) else "aucun"
	local extra = ""
	if rec.Kind == "Dress" and rec.PrimLo then
		local pc = (rec.PrimLo + rec.PrimHi) / 2
		local mc = (lo + hi) / 2
		local ps = rec.PrimHi - rec.PrimLo
		extra = string.format(
			"  primitives %s · décalage centre %s · rapport %.2f×%.2f×%.2f",
			fmt(ps),
			fmt(mc - pc),
			size.X / math.max(ps.X, 0.01),
			size.Y / math.max(ps.Y, 0.01),
			size.Z / math.max(ps.Z, 0.01)
		)
	end
	table.insert(
		lines,
		string.format(
			"%-5s %-5s %-16s posé %-18s fit %-18s usage %-14s bas-support %s%s",
			world,
			rec.Kind,
			rec.Key,
			fmt(size),
			if fit then fmt(fit) else "—",
			usage,
			gap,
			extra
		)
	)
end
table.sort(lines)
for _, line in lines do
	print(line)
end
print(`\n{#records} poses, {#built.Warnings} avertissements`)
for _, w in built.Warnings do
	print("  " .. w)
end
