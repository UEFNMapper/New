-- Construit VRAIMENT la map (MapBuilder) avec les instances Roblox de Lune, puis vérifie :
-- - aucun point d'arrivée n'est dans un mur
-- - tout est atteignable à pied depuis le hub (flood fill sur une grille de 2 studs)
-- - chaque prompt a une action connue, chaque portail a son terminal et sa barrière
local roblox = require("@lune/roblox")

local Instance, Enum, V3 = roblox.Instance, roblox.Enum, roblox.Vector3

-- CFrame.lookAt de Lune pointe à l'opposé de Roblox (LookVector inversé) : on le corrige.
local function lookAt(at: any, target: any, up: any?): any
	local look = (target - at).Unit
	local right = look:Cross(up or V3.new(0, 1, 0)).Unit
	local trueUp = right:Cross(look)
	return roblox.CFrame.fromMatrix(at, right, trueUp, -look)
end
local CFrame = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })

local dataModel = Instance.new("DataModel")
local workspace = dataModel:GetService("Workspace")
local fakeCollection = {
	AddTag = function(_self: any, instance: any, tag: string)
		instance:AddTag(tag)
	end,
}
local fakeReplicated = {
	WaitForChild = function(_self: any, _name: string)
		return Shim.Node("src/shared")
	end,
}
Shim.Globals = {
	game = {
		GetService = function(_self: any, name: string): any
			if name == "Workspace" then
				return workspace
			elseif name == "ReplicatedStorage" then
				return fakeReplicated
			elseif name == "CollectionService" then
				return fakeCollection
			end
			error(`service non simulé : {name}`)
		end,
	},
	Instance = Instance,
	Enum = Enum,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	Vector3 = V3,
	UDim2 = roblox.UDim2,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	-- Random n'existe pas dans Lune : générateur déterministe minimal (LCG).
	Random = {
		new = function(seed: number?)
			local state = (seed or 1) % 2147483647
			local function nextFloat(): number
				state = (state * 48271) % 2147483647
				return state / 2147483647
			end
			return {
				NextNumber = function(_self: any, low: number?, high: number?): number
					local a, b = low or 0, high or 1
					return a + (b - a) * nextFloat()
				end,
				NextInteger = function(_self: any, low: number, high: number): number
					return low + math.floor(nextFloat() * (high - low + 1))
				end,
			}
		end,
	},
}

local WorldLayout = Shim.load("src/shared/Config/WorldLayout.luau")
local Zones = Shim.load("src/shared/Config/Zones.luau")
local MapBuilder = Shim.load("src/server/World/MapBuilder.luau")
Shim.Globals = {}

MapBuilder.Build()
local world = workspace:FindFirstChild("World")
Shim.LastWorld = world -- utilisé par tests/tools/ExportMap.luau

------------------------------------------------------------------------------------
-- Grille de marche (hauteur d'un joueur : de 0,7 à 5,5 studs au-dessus du sol)
------------------------------------------------------------------------------------

local CELL = 2
local MARGIN = 1 -- demi-largeur d'un personnage
local minX, minZ = WorldLayout.MIN_X, WorldLayout.MIN_Z
local cols = math.floor((WorldLayout.MAX_X - minX) / CELL)
local rows = math.floor((WorldLayout.MAX_Z - minZ) / CELL)
local blocked: { [number]: string } = {}

local function key(cx: number, cz: number): number
	return cz * (cols + 1) + cx
end

local function cellOf(position: any): (number, number)
	return math.floor((position.X - minX) / CELL), math.floor((position.Z - minZ) / CELL)
end

local function centerOf(cx: number, cz: number): any
	return V3.new(minX + (cx + 0.5) * CELL, 3, minZ + (cz + 0.5) * CELL)
end

local function extents(part: any): any
	local cf, size = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return V3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) / 2
end

local collidables = 0
for _, part in world:GetDescendants() do
	if part:IsA("BasePart") and part.CanCollide then
		collidables += 1
		local half = extents(part)
		local center = part.CFrame.Position
		-- Seuls les obstacles à hauteur de joueur comptent (marche <= 0,7 stud franchissable).
		if center.Y + half.Y > 0.7 and center.Y - half.Y < 5.5 then
			local x0, z0 = cellOf(center - half - V3.new(MARGIN, 0, MARGIN))
			local x1, z1 = cellOf(center + half + V3.new(MARGIN, 0, MARGIN))
			for cx = math.max(x0, 0), math.min(x1, cols) do
				for cz = math.max(z0, 0), math.min(z1, rows) do
					local p = centerOf(cx, cz)
					local localPos = part.CFrame:PointToObjectSpace(V3.new(p.X, math.clamp(center.Y, 0.7, 5.5), p.Z))
					local size = part.Size / 2
					if
						math.abs(localPos.X) <= size.X + MARGIN
						and math.abs(localPos.Y) <= size.Y + MARGIN
						and math.abs(localPos.Z) <= size.Z + MARGIN
					then
						blocked[key(cx, cz)] = part:GetFullName()
					end
				end
			end
		end
	end
end

-- Flood fill depuis le spawn du hub (toutes les zones débloquées)
local reached: { [number]: boolean } = {}
local sx, sz = cellOf(WorldLayout.HubSpawn)
local queue = { { sx, sz } }
reached[key(sx, sz)] = true
local head = 1
while head <= #queue do
	local cell = queue[head]
	head += 1
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local nx, nz = cell[1] + d[1], cell[2] + d[2]
		local k = key(nx, nz)
		if nx >= 0 and nz >= 0 and nx <= cols and nz <= rows and not reached[k] and not blocked[k] then
			reached[k] = true
			table.insert(queue, { nx, nz })
		end
	end
end

-- Un objet est "atteignable" si une cellule libre et atteinte se trouve à moins de `radius`.
local function reachable(position: any, radius: number): boolean
	local cx, cz = cellOf(position)
	local r = math.ceil(radius / CELL)
	for dx = -r, r do
		for dz = -r, r do
			local k = key(cx + dx, cz + dz)
			if reached[k] and (centerOf(cx + dx, cz + dz) - V3.new(position.X, 3, position.Z)).Magnitude <= radius then
				return true
			end
		end
	end
	return false
end

local function pivot(instance: any): any
	if instance:IsA("BasePart") then
		return instance.CFrame.Position
	end
	local primary = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	return primary.CFrame.Position
end

local KNOWN_ACTIONS = {
	Upgrade = true,
	Elevator = true,
	Unlock = true,
	Power = true,
	Cooling = true,
	Capsules = true,
	Downloads = true,
	Overclock = true,
	Reboot = true,
	Singularity = true,
}

return {
	["map : construite, taille raisonnable"] = function()
		Expect.truthy(world ~= nil, "World")
		local parts = 0
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		print(`    {parts} pièces, dont {collidables} solides ; {#queue} cellules atteignables`)
		Expect.between(parts, 500, 9000, "nombre de pièces")
	end,
	["map : budget mobile (pièces, lumières, pièces libres)"] = function()
		local parts, lights, guis = 0, 0, 0
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if not d.Anchored then
					-- Seules les pièces soudées à un moyeu ancré qui tourne (pales, anneaux) sont libres.
					local weld = d:FindFirstChildOfClass("WeldConstraint")
					local hub = weld and weld.Part0
					Expect.truthy(
						hub ~= nil and hub.Anchored and (hub:HasTag("DecorSpin") or hub:HasTag("Spin")),
						`pièce non ancrée sans moyeu : {d:GetFullName()}`
					)
				end
			elseif d:IsA("SurfaceGui") then
				guis += 1
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
				Expect.equal(d.Shadows, false, `ombres sur {d:GetFullName()}`)
			end
		end
		print(`    {parts} pièces, {lights} lumières, {guis} étiquettes (SurfaceGui)`)
		Expect.truthy(parts <= 6500, `trop de pièces : {parts}`)
		Expect.truthy(lights <= 60, `trop de lumières : {lights}`)
		Expect.truthy(guis <= 200, `trop d'étiquettes : {guis}`)
	end,
	["map : aucune géométrie invalide (NaN)"] = function()
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") then
				local p = d.CFrame.Position
				local look = d.CFrame.LookVector
				Expect.truthy(p == p and look == look, `CFrame NaN : {d:GetFullName()}`)
			end
		end
	end,
	["map : points d'arrivée libres"] = function()
		for zone = 0, #Zones do
			local spawn = if zone == 0 then WorldLayout.HubSpawn else WorldLayout.Zones[zone].Spawn
			local cx, cz = cellOf(spawn)
			local k = key(cx, cz)
			Expect.truthy(not blocked[k], `arrivée de la zone {zone} bloquée par {blocked[k]}`)
			Expect.truthy(reached[k], `arrivée de la zone {zone} inaccessible depuis le hub`)
		end
	end,
	["map : tout est atteignable à pied depuis le hub"] = function()
		local problems = {}
		local function check(what: string, position: any, radius: number)
			if not reachable(position, radius) then
				table.insert(problems, `{what} @ {math.floor(position.X)},{math.floor(position.Z)}`)
			end
		end
		for zone = 1, #Zones do
			local model = world.Zones:FindFirstChild(`Zone{zone}`)
			Expect.truthy(model ~= nil, `Zone{zone}`)
			check(`collecteur {zone}`, model.Collector.CFrame.Position, 7)
			check(`téléporteur {zone}`, model.Teleporter.CFrame.Position, 5)
			for _, machine in model.Modules:GetChildren() do
				check(`machine {machine.Name}`, machine.PrimaryPart.CFrame.Position, 12)
			end
			for _, fragment in model.Fragments:GetChildren() do
				check(`fragment {fragment:GetAttribute("FragmentId")}`, fragment.CFrame.Position, 2.5)
			end
			for _, child in model:GetChildren() do
				if child:IsA("Model") and string.match(child.Name, "Terminal$") then
					check(`terminal {child.Name}`, pivot(child), 8)
				end
			end
			local gate = world.Gates:FindFirstChild(`Gate{zone}`)
			check(`terminal de déblocage {zone}`, pivot(gate.UnlockTerminal), 8)
		end
		check("téléporteur du hub", world.Hub.Teleporter.CFrame.Position, 5)
		Expect.equal(#problems, 0, "inaccessibles :\n      " .. table.concat(problems, "\n      "))
	end,
	["map : fragments dans leur zone, hors des murs"] = function()
		for zone = 1, #Zones do
			for _, fragment in world.Zones[`Zone{zone}`].Fragments:GetChildren() do
				local id = fragment:GetAttribute("FragmentId")
				Expect.equal(WorldLayout.ZoneAt(fragment.CFrame.Position), zone, `{id} hors de sa zone`)
				local cx, cz = cellOf(fragment.CFrame.Position)
				Expect.truthy(not blocked[key(cx, cz)], `{id} dans {blocked[key(cx, cz)]}`)
			end
		end
	end,
	["map : prompts et portails cohérents"] = function()
		local upgrades = 0
		for _, d in world:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				local action = d:GetAttribute("Action")
				Expect.truthy(KNOWN_ACTIONS[action], `action inconnue {action} sur {d.Parent:GetFullName()}`)
				Expect.truthy(d.Parent:IsA("BasePart"), `prompt hors d'une pièce : {d:GetFullName()}`)
				if action == "Upgrade" then
					upgrades += 1
				elseif action == "Unlock" then
					Expect.truthy(type(d:GetAttribute("Zone")) == "number", "Zone sur le prompt Unlock")
				end
			end
		end
		Expect.equal(upgrades, #Zones * 3, "une machine améliorable par module")
		for zone = 2, #Zones do
			local gate = world.Gates:FindFirstChild(`Gate{zone}`)
			Expect.truthy(gate ~= nil, `Gate{zone}`)
			Expect.truthy(gate.Barrier:HasTag("ZoneGate"), "tag ZoneGate")
			Expect.equal(gate.Barrier:GetAttribute("Zone"), zone, "zone de la barrière")
			Expect.equal(gate.Barrier.CanCollide, false, "barrière traversable côté serveur")
		end
		local screens = 0
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and d:HasTag("AppScreen") then
				screens += 1
			end
		end
		Expect.equal(screens, 1, "écran de l'app AngAInOne dans le hub")
	end,
}
