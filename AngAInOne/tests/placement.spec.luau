-- Placement des VRAIS modèles 3D, simulés par leurs boîtes englobantes (tests/lib/FakeModels.luau,
-- à partir d'assets/models/bounds.json) : la tour est construite comme si tous les modèles étaient
-- importés (tests/lib/IsolatedTower.luau, chargeur à part), puis chaque pose est contrôlée.
-- Rapport détaillé : lune run tests/tools/PlacementReport.luau ; rendu : ExportMap --models.
local roblox = require("@lune/roblox")

local V3 = roblox.Vector3

-- Poses enregistrées (clé, cframe, options, modèle posé) par un enrobage de ModelLibrary.
local records = {}
local built = IsolatedTower.Build({
	Models = true,
	Observe = function(ModelLibrary)
		local realPlace = ModelLibrary.Place
		ModelLibrary.Place = function(key, cframe, parent, options, fallback)
			local placed = realPlace(key, cframe, parent, options, fallback)
			if placed and ModelLibrary.Has(key) then
				table.insert(records, { Key = key, CFrame = cframe, Options = options or {}, Model = placed })
			end
			return placed
		end
	end,
})
local tower = built.Tower
local Common = built.Load("src/server/World/Tower/Common.luau")
local Tower = built.Load("src/shared/Config/Tower.luau")

local function worldOf(instance: any): number?
	local node = instance
	while node do
		local w = node:GetAttribute("World")
		if type(w) == "number" and node.Parent == tower then
			return w
		end
		node = node.Parent
	end
	return nil
end

-- Portée d'une recherche de support : le Model du monde de la pose, ou le Lobby (le clavier géant du
-- lobby déborde en X/Z sur la tranche du monde 1).
local function scopeOf(instance: any): any
	local node = instance
	while node and node.Parent ~= tower do
		node = node.Parent
	end
	return node or tower
end

local function inLobby(instance: any): boolean
	local node = instance
	while node do
		if node.Name == "Lobby" and node.Parent == tower then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Plus haute surface VISIBLE (solide ou décor, autres modèles compris) sous (x, z), pas plus haute
-- que `limit`, hors des pièces de `self`. Une primitive habillée (invisible) n'est pas un support.
local function supportBelow(x: number, limit: number, z: number, self: any, scope: any): (number?, string?)
	local best, name = nil, nil
	for _, part in scope:GetDescendants() do
		if
			part:IsA("BasePart")
			and part.Transparency < 1
			and part.Name ~= "Segment" -- un câble de décor passe sous un objet sans le porter
			and not part:IsDescendantOf(self)
		then
			local lo, hi = IsolatedTower.Bounds(part)
			if lo and x >= lo.X - 0.3 and x <= hi.X + 0.3 and z >= lo.Z - 0.3 and z <= hi.Z + 0.3 and hi.Y <= limit then
				if not best or hi.Y > best then
					best, name = hi.Y, part:GetFullName()
				end
			end
		end
	end
	return best, name
end

-- Modèles posés AU SOL (ou sur un meuble) : leur bas doit être à ≤ 2,5 studs de leur support.
local GROUNDED = {
	Psu = true,
	Capacitor = true,
	CapacitorBig = true,
	Choke = true,
	ChokeRow = true,
	CpuCooler = true,
	PumpReservoir = true,
	AioRadiator = true,
	GamingChair = true,
	Plant = true,
	WebcamLight = true,
	Speaker = true,
	Anga = true,
	NpuChip = true,
	VrmHeatsink = true,
	TerminalConsole = true,
	ArcadeCabinet = true,
	ShopKiosk = true,
}

return {
	["modèles simulés : tous installés, aucun décor de secours ni avertissement"] = function()
		Expect.truthy(#records >= 300, `poses enregistrées : {#records}`)
		Expect.equal(#built.Warnings, 0, table.concat(built.Warnings, "\n"))
		local keys = {}
		for _, rec in records do
			keys[rec.Key] = true
		end
		for _, key in { "Fan140", "AioRadiator", "RamStick", "GpuCard", "CpuCooler", "Anga", "Keyboard" } do
			Expect.truthy(keys[key], `{key} posé`)
		end
	end,

	["chaque pose est dans la tour et dans la tranche de son monde"] = function()
		local limit = Common.INNER + Common.WALL
		for _, rec in records do
			local lo, hi = IsolatedTower.Bounds(rec.Model)
			if not lo or inLobby(rec.Model) then
				continue
			end
			local label = `{rec.Key} ({rec.Model:GetFullName()})`
			Expect.truthy(
				math.max(math.abs(lo.X), math.abs(hi.X), math.abs(lo.Z), math.abs(hi.Z)) <= limit + 1,
				`{label} : hors de la tour`
			)
			local w = worldOf(rec.Model)
			if w then
				local base = (w - 1) * Common.BAND
				-- salle du terminal à +110, arène du boss (monde 7) un peu plus haut
				Expect.truthy(
					lo.Y >= base - 3 and hi.Y <= base + Common.BAND + 30,
					`{label} : hors de la tranche du monde {w}`
				)
			end
		end
	end,

	["option Height : l'étendue verticale posée vaut la hauteur demandée (ventilateurs dressés)"] = function()
		local checked = 0
		for _, rec in records do
			local height = rec.Options.Height
			if height then
				local lo, hi = IsolatedTower.Bounds(rec.Model)
				Expect.near(hi.Y - lo.Y, height, math.max(0.15, height * 0.06), `{rec.Key} : hauteur {height}`)
				checked += 1
			end
		end
		Expect.truthy(checked >= 10, `poses avec Height : {checked}`)
	end,

	["option Fit : le modèle tient dans la boîte demandée (axes du modèle)"] = function()
		for _, rec in records do
			local fit = rec.Options.Fit
			if fit then
				local inverse = rec.CFrame:Inverse()
				local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
				for _, part in rec.Model:GetDescendants() do
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
				local label = `{rec.Key} ({rec.Model:GetFullName()})`
				Expect.truthy(x1 - x0 <= fit.X + 0.2, `{label} : déborde en X ({x1 - x0} > {fit.X})`)
				Expect.truthy(y1 - y0 <= fit.Y + 0.2, `{label} : déborde en Y ({y1 - y0} > {fit.Y})`)
				Expect.truthy(z1 - z0 <= fit.Z + 0.2, `{label} : déborde en Z ({z1 - z0} > {fit.Z})`)
			end
		end
	end,

	["modèles posés au sol : à 2,5 studs au plus de leur support"] = function()
		local checked = 0
		for _, rec in records do
			if GROUNDED[rec.Key] then
				local lo, hi = IsolatedTower.Bounds(rec.Model)
				local support, supportName = supportBelow(
					(lo.X + hi.X) / 2,
					lo.Y + (hi.Y - lo.Y) * 0.75,
					(lo.Z + hi.Z) / 2,
					rec.Model,
					scopeOf(rec.Model)
				)
				Expect.truthy(support ~= nil, `{rec.Key} ({rec.Model:GetFullName()}) : aucun support`)
				Expect.truthy(
					math.abs(lo.Y - support) <= 2.5,
					`{rec.Key} ({rec.Model:GetFullName()}) : bas à {lo.Y - support} du support {supportName}`
				)
				checked += 1
			end
		end
		Expect.truthy(checked >= 20, `poses au sol vérifiées : {checked}`)
	end,

	["monde 4 : le radiateur AIO est debout contre la vitre, ventilateurs vers le parcours"] = function()
		for _, rec in records do
			if rec.Key == "AioRadiator" then
				local lo, hi = IsolatedTower.Bounds(rec.Model)
				local size = hi - lo
				Expect.between(size.Y, 30, 40, "hauteur du radiateur debout")
				Expect.between(size.Z, 120, 132, "longueur le long de la vitre")
				Expect.truthy(size.X < 30, `épaisseur {size.X}`)
				Expect.truthy(hi.X < Common.INNER and lo.X > 85, `contre la vitre (+X) : {lo.X}..{hi.X}`)
				return
			end
		end
		error("AioRadiator non posé")
	end,

	["monde 2 : les barrettes RAM mesurent 84 studs et touchent leur slot"] = function()
		local sticks = 0
		for _, rec in records do
			-- (les barrettes de l'épreuve de la salle du terminal sont à l'échelle du joueur)
			if rec.Key == "RamStick" and not rec.Model:FindFirstAncestor("Epreuve") then
				local lo, hi = IsolatedTower.Bounds(rec.Model)
				Expect.near(hi.Y - lo.Y, 84, 0.5, "hauteur de la barrette")
				Expect.near(lo.Y - Common.BAND, 4, 0.5, "bas de la barrette au dessus du slot (4)")
				sticks += 1
			end
		end
		Expect.truthy(sticks >= 4, `barrettes : {sticks}`)
	end,

	["façades : chaque modèle regarde dans le sens voulu par sa pose (LookVector = avant)"] = function()
		-- Pièce repère de l'AVANT (ou de l'ARRIÈRE : Back = true) de chaque modèle, d'après assets/models/bounds.json
		local MARKERS: { [string]: { Part: string, Back: boolean?, From: string? } } = {
			Anga = { Part = "Mouth" },
			Lagz = { Part = "Eyes" },
			Sparky = { Part = "Pupil" },
			PopUp = { Part = "Text", From = "Frame" }, -- fenêtre plate : texte devant le cadre
			Corrupto = { Part = "White" },
			Dusty = { Part = "EyeWhite" },
			Minor = { Part = "Screen" },
			Freezy = { Part = "Dark" },
			Monitor = { Part = "Screen" },
			Speaker = { Part = "Cone" },
			ArcadeCabinet = { Part = "Screen" },
			ShopKiosk = { Part = "Glass" },
			TerminalConsole = { Part = "Keys" },
			DeskLamp = { Part = "Shade" },
			WebcamLight = { Part = "Lens" },
			Miniaturiseur = { Part = "Screen" },
			Keyboard = { Part = "Cable", Back = true },
			Mouse = { Part = "Cable", Back = true },
			GamingChair = { Part = "Upholstery", Back = true },
			LagzHead = { Part = "Eyes", Back = true }, -- Cameos : LookVector vers la paroi, avant +Z vers le parcours
		}
		local function front(model: any, partName: string, fromName: string?): any?
			local lo, hi = IsolatedTower.Bounds(model)
			local center = (lo + hi) / 2
			if fromName then
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part.Name == fromName then
						center = part.CFrame.Position
					end
				end
			end
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.Name == partName then
					local d = part.CFrame.Position - center
					local flat = roblox.Vector3.new(d.X, 0, d.Z)
					return if flat.Magnitude > 0.05 then flat.Unit else nil
				end
			end
			return nil
		end
		local checked = 0
		for _, rec in records do
			local marker = MARKERS[rec.Key]
			if not marker then
				continue
			end
			local dir = front(rec.Model, marker.Part, marker.From)
			Expect.truthy(dir ~= nil, `{rec.Key} : pièce repère {marker.Part}`)
			local look = rec.CFrame.LookVector
			local along = dir:Dot(roblox.Vector3.new(look.X, 0, look.Z).Unit)
			local label = `{rec.Key} ({rec.Model:GetFullName()}) : avant·LookVector = {along}`
			if marker.Back then
				Expect.truthy(along < -0.5, label)
			else
				Expect.truthy(along > 0.5, label)
			end
			checked += 1
		end
		Expect.truthy(checked >= 20, `façades vérifiées : {checked}`)

		-- Sens voulus par le scénario
		for _, rec in records do
			local lo, hi = IsolatedTower.Bounds(rec.Model)
			local center = (lo + hi) / 2
			if rec.Key == "Anga" and rec.Model.Name == "GiantAnga" then
				local toTower = roblox.Vector3.new(-center.X, 0, -center.Z).Unit
				Expect.truthy(front(rec.Model, "Mouth"):Dot(toTower) > 0.8, "l'Anga géant regarde la tour")
			elseif rec.Key == "Lagz" then
				Expect.truthy(front(rec.Model, "Eyes").Z < -0.8, "LAGZ regarde l'entrée de l'arène (-Z)")
			elseif rec.Key == "CpuCooler" then
				local fan = front(rec.Model, "Rotor")
				Expect.truthy(fan and fan.Z < -0.8, `ventirad {rec.Model:GetFullName()} : ventilateur vers -Z`)
			elseif rec.Key == "GpuCard" and not rec.Model:FindFirstAncestor("Epreuve") then
				-- (la carte de l'épreuve du monde 6 est posée à plat sur un banc de test)
				local fan = front(rec.Model, "Fan2")
				Expect.truthy(fan and fan.X > 0.8, "carte graphique : ventilateurs vers l'est (+X)")
			elseif rec.Key == "PopUp" and rec.Model.Parent and rec.Model.Parent.Name == "Decor" then
				local inward = roblox.Vector3.new(-center.X, 0, -center.Z).Unit
				Expect.truthy(
					front(rec.Model, "Text", "Frame"):Dot(inward) > 0.3,
					`pub {rec.Model:GetFullName()} tournée vers le parcours`
				)
			elseif rec.Key == "LagzHead" then
				local inward = roblox.Vector3.new(-center.X, 0, -center.Z).Unit
				Expect.truthy(
					front(rec.Model, "Eyes"):Dot(inward) > 0.5,
					`tête de LAGZ {rec.Model:GetFullName()} vers le parcours`
				)
			end
		end
	end,

	["détours bonus : le cadre de ventilateur est centré sur la passerelle, 24 studs de haut"] = function()
		local frames = 0
		for _, route in tower:GetDescendants() do
			if route:HasTag("BonusRoute") then
				local walk = route:FindFirstChild("BonusWalk")
				local frame = route:FindFirstChild("FanFrame")
				Expect.truthy(walk and frame, `détour {route:GetFullName()} : passerelle et cadre`)
				local lo, hi = IsolatedTower.Bounds(frame)
				Expect.near(hi.Y - lo.Y, 24, 0.1, "diamètre du cadre")
				local center = (lo + hi) / 2
				local side = (center - walk.CFrame.Position):Dot(walk.CFrame.RightVector)
				Expect.truthy(math.abs(side) <= 1.5, `cadre centré sur la passerelle ({side})`)
				frames += 1
			end
		end
		Expect.equal(frames, Tower.WORLD_COUNT, "un cadre par monde")
	end,
}
