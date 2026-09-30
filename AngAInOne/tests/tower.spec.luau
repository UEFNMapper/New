-- Construit VRAIMENT la tour (TowerBuilder) avec les instances Roblox de Lune, puis vérifie :
-- - le VRAI TrapController (client) simulé sur cette tour : poses, transport, morts, points sûrs
-- - le contrat d'instances (lobby, checkpoints, terminaux, portails, arrivée, Bits, pièges)
-- - les budgets mobiles (pièces, lumières) et l'absence de géométrie invalide
-- - que chaque étape est franchissable : graphe de sauts entre les dessus de plateformes
--   (personnage par défaut : WalkSpeed 16, JumpPower 50, gravité 196,2)
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
}

local Tower = Shim.load("src/shared/Config/Tower.luau")
local TowerBuilder = Shim.load("src/server/World/TowerBuilder.luau")
local Common = Shim.load("src/server/World/Tower/Common.luau") -- même instance que celle de TowerBuilder
Shim.Globals = {}

local built = TowerBuilder.Build()
local tower = workspace:FindFirstChild("Tower")
Shim.LastTower = tower -- utilisé par tests/tools/ExportMap.luau

local descendants = tower:GetDescendants()

local function tagged(tag: string): { any }
	local list = {}
	for _, d in descendants do
		if d:HasTag(tag) then
			table.insert(list, d)
		end
	end
	return list
end

local function top(part: any): number
	local cf, size = part.CFrame, part.Size
	local ey = math.abs(cf.RightVector.Y) * size.X
		+ math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z
	return cf.Position.Y + ey / 2
end

-- Boîte englobante alignée sur les axes (demi-étendues).
local function extents(part: any): any
	local cf, size = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return V3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) / 2
end

local function worldOfInstance(instance: any): number?
	local node = instance
	while node and node ~= tower do
		local w = node:GetAttribute("World")
		if node:IsA("Model") and type(w) == "number" then
			return w
		end
		node = node.Parent
	end
	return nil
end

local function isA(value: any, typeName: string): boolean
	return typeof(value) == typeName
end

-- Paramètres requis par type de piège (Config/Tower) : nom -> type attendu.
local REQUIRED: { [string]: { [string]: string } } = {
	Zapper = { Period = "number", Duty = "number", Phase = "number" },
	SpinBar = { Speed = "number", Axis = "string" },
	Crusher = { Offset = "Vector3", Period = "number", Phase = "number" },
	Mover = { Offset = "Vector3", Period = "number", Phase = "number" },
	Vanish = { Delay = "number", Respawn = "number" },
	Wind = { Direction = "Vector3", Strength = "number" },
	Laser = { Offset = "Vector3", Period = "number", Phase = "number" },
	Virus = { Waypoints = "string", Speed = "number" },
	Conveyor = { Direction = "Vector3", Speed = "number" },
	Bounce = { Power = "number" },
	Heat = { Period = "number", Duty = "number", Phase = "number" },
}
local LETHAL_KINDS = { Zapper = true, SpinBar = true, Crusher = true, Laser = true, Virus = true, Heat = true }
local SOLID_KINDS = { Mover = true, Vanish = true, Conveyor = true, Bounce = true }

local function isLethal(part: any): boolean
	if part:HasTag("Hazard") then
		return true
	end
	local node = part
	while node and node ~= tower do
		if node:HasTag("Trap") and LETHAL_KINDS[node:GetAttribute("Kind")] then
			return true
		end
		node = node.Parent
	end
	return false
end

local function parseWaypoints(text: string): { any }?
	local points = {}
	for chunk in string.gmatch(text, "[^;]+") do
		local x, y, z = string.match(chunk, "^%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*$")
		if not x then
			return nil
		end
		table.insert(points, V3.new(tonumber(x), tonumber(y), tonumber(z)))
	end
	return points
end

------------------------------------------------------------------------------------
-- Checkpoints
------------------------------------------------------------------------------------

local pads: { [number]: any } = {}
local padErrors = {}
for _, pad in tagged("Checkpoint") do
	local stage = pad:GetAttribute("Stage")
	if type(stage) ~= "number" or stage ~= math.floor(stage) then
		table.insert(padErrors, `Stage invalide sur {pad:GetFullName()}`)
	elseif pads[stage] then
		table.insert(padErrors, `checkpoint {stage} en double`)
	else
		pads[stage] = pad
	end
end

------------------------------------------------------------------------------------
-- Graphe de sauts (dessus des plateformes)
------------------------------------------------------------------------------------

local WALK, JUMP, GRAVITY = 16, 50, 196.2
local FORGIVE = 1.2 -- largeur des pieds : on peut atterrir un peu au-delà du bord

-- Portée horizontale d'un saut qui arrive `dy` plus haut (nil si impossible).
local function reach(dy: number, power: number): number?
	local disc = power * power - 2 * GRAVITY * dy
	if disc < 0 or dy > power * power / (2 * GRAVITY) - 0.35 then
		return nil
	end
	local t = (power + math.sqrt(disc)) / GRAVITY
	return WALK * t + FORGIVE
end

type Rect = { X0: number, X1: number, Z0: number, Z1: number, Y: number, Bounce: boolean, Link: number?, Name: string? }

local function rectOf(part: any, y: number?): Rect
	local e = extents(part)
	local p = part.CFrame.Position
	return {
		X0 = p.X - e.X,
		X1 = p.X + e.X,
		Z0 = p.Z - e.Z,
		Z1 = p.Z + e.Z,
		Y = y or top(part),
		Bounce = part:HasTag("Trap") and part:GetAttribute("Kind") == "Bounce",
		Name = part:GetFullName(),
	}
end

-- Dessus praticables d'une pièce solide (tranches pour les rampes, 2 positions pour les Mover).
local function surfaces(part: any, out: { Rect })
	if not part.CanCollide or isLethal(part) then
		return
	end
	if part:IsA("WedgePart") then
		local cf, size = part.CFrame, part.Size
		local n = 12
		for i = 0, n - 1 do
			local z0 = -size.Z / 2 + size.Z * i / n
			local z1 = z0 + size.Z / n
			local yTop = -size.Y / 2 + size.Y * (i + 1) / n
			local a = cf:PointToWorldSpace(V3.new(-size.X / 2, yTop, z0))
			local b = cf:PointToWorldSpace(V3.new(size.X / 2, yTop, z1))
			table.insert(out, {
				X0 = math.min(a.X, b.X),
				X1 = math.max(a.X, b.X),
				Z0 = math.min(a.Z, b.Z),
				Z1 = math.max(a.Z, b.Z),
				Y = a.Y,
				Bounce = false,
				Name = part:GetFullName() .. "#" .. i,
			})
		end
		return
	end
	if math.abs(part.CFrame.UpVector.Y) < 0.99 then
		return
	end
	local rect = rectOf(part)
	table.insert(out, rect)
	if part:HasTag("Trap") and part:GetAttribute("Kind") == "Mover" then
		local offset = part:GetAttribute("Offset")
		local moved = table.clone(rect)
		moved.X0 += offset.X
		moved.X1 += offset.X
		moved.Z0 += offset.Z
		moved.Z1 += offset.Z
		moved.Y += offset.Y
		rect.Link = #out + 1
		table.insert(out, moved)
		moved.Link = #out - 1
	end
end

local function gap(a: Rect, b: Rect): number
	local dx = math.max(0, math.max(a.X0, b.X0) - math.min(a.X1, b.X1))
	local dz = math.max(0, math.max(a.Z0, b.Z0) - math.min(a.Z1, b.Z1))
	return math.sqrt(dx * dx + dz * dz)
end

local function canJump(a: Rect, b: Rect): boolean
	local dy = b.Y - a.Y
	if dy < -80 then
		return false
	end
	local range = reach(dy, if a.Bounce then 80 else JUMP)
	return range ~= nil and gap(a, b) <= range
end

-- Pièces praticables pour l'étape s : son dossier, le coin de départ (étape précédente),
-- les maisons de terminal voisines, l'entrée du lobby et les pads.
local function stageRects(s: number): { Rect }
	local rects: { Rect } = {}
	local w = Tower.WorldOf(s)
	local roots = {}
	local function add(root: any?)
		if root then
			table.insert(roots, root)
		end
	end
	local world = tower:FindFirstChild(`World{w}`)
	add(world and world:FindFirstChild(`Stage{s}`))
	local prevWorld = tower:FindFirstChild(`World{Tower.WorldOf(s - 1)}`)
	add(prevWorld and prevWorld:FindFirstChild(`Stage{s - 1}`))
	add(world and world:FindFirstChild("Terminal"))
	if w > 1 then
		add(tower[`World{w - 1}`]:FindFirstChild("Terminal"))
	end
	if s == 1 then
		add(tower.Lobby)
	end
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				surfaces(d, rects)
			end
		end
	end
	for stage, pad in pads do
		if stage == s or stage == s - 1 then
			surfaces(pad, rects)
		end
	end
	return rects
end

-- Plus court chemin (en nombre de sauts) d'un pad à l'autre ; nil si inaccessible.
local lastParents: { [number]: number } = {}
local lastGoal = 0
local function reachable(rects: { Rect }, from: any, to: any): (boolean, number)
	local startIndex, goalIndex
	local fromTop, toTop = top(from), top(to)
	for i, r in rects do
		local fp, tp = from.CFrame.Position, to.CFrame.Position
		if math.abs(r.Y - fromTop) < 0.01 and fp.X >= r.X0 and fp.X <= r.X1 and fp.Z >= r.Z0 and fp.Z <= r.Z1 then
			startIndex = startIndex or i
		end
		if math.abs(r.Y - toTop) < 0.01 and tp.X >= r.X0 and tp.X <= r.X1 and tp.Z >= r.Z0 and tp.Z <= r.Z1 then
			goalIndex = goalIndex or i
		end
	end
	if not startIndex or not goalIndex then
		return false, 0
	end
	table.clear(lastParents)
	local dist = { [startIndex] = 0 }
	local queue = { startIndex }
	local head = 1
	while head <= #queue do
		local i = queue[head]
		head += 1
		if i == goalIndex then
			lastGoal = i
			return true, dist[i]
		end
		local a = rects[i]
		local function visit(j: number)
			if not dist[j] then
				dist[j] = dist[i] + 1
				lastParents[j] = i
				table.insert(queue, j)
			end
		end
		if a.Link then
			visit(a.Link)
		end
		for j, b in rects do
			if not dist[j] and canJump(a, b) then
				visit(j)
			end
		end
	end
	return false, 0
end

------------------------------------------------------------------------------------
-- Simulation du VRAI TrapController (client) sur la tour construite
-- Services factices, pièces enveloppées (Lune n'a ni Position ni événements d'instance),
-- personnage R15 factice, temps serveur piloté par le test.
------------------------------------------------------------------------------------

local sim = { T = 1000, Waiting = {} :: { thread }, Reports = {} :: { string }, Deaths = {} :: { string } }

local function fakeSignal(): any
	local handlers = {}
	return {
		Connect = function(_self: any, fn: any)
			table.insert(handlers, fn)
			return { Disconnect = function() end }
		end,
		Fire = function(_self: any, ...: any)
			for _, handler in handlers do
				handler(...)
			end
		end,
	}
end

local realOf: { [any]: any } = {}
local proxyOf: { [any]: any } = {}
local function proxy(real: any): any
	local existing = proxyOf[real]
	if existing then
		return existing
	end
	local wrapped = setmetatable({}, {
		__index = function(_self: any, key: string): any
			if key == "DescendantAdded" then
				return fakeSignal()
			elseif key == "Position" then
				return real.CFrame.Position
			end
			local value = real[key]
			if type(value) == "function" then
				return function(_: any, ...: any): ...any
					return value(real, ...)
				end
			end
			return value
		end,
		__newindex = function(_self: any, key: string, value: any)
			real[key] = value
		end,
	})
	proxyOf[real] = wrapped
	realOf[wrapped] = real
	return wrapped
end

local simTask = {
	spawn = function(fn: any, ...: any)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		assert(ok, err)
	end,
	wait = function(_seconds: number?)
		table.insert(sim.Waiting, coroutine.running())
		coroutine.yield()
	end,
}

-- Relance les boucles en attente (recalcul des listes de proximité du contrôleur).
local function tick()
	local waiting = sim.Waiting
	sim.Waiting = {}
	for _, co in waiting do
		local ok, err = coroutine.resume(co)
		assert(ok, err)
	end
end

local rootState = { CFrame = roblox.CFrame.new(0, 10, -300), Velocity = V3.new(0, 0, 0) }
local character: any = nil
local humanoid: any = nil
local rootPart = setmetatable({}, {
	__index = function(_self: any, key: string): any
		if key == "CFrame" then
			return rootState.CFrame
		elseif key == "Position" then
			return rootState.CFrame.Position
		elseif key == "Size" then
			return V3.new(2, 2, 1)
		elseif key == "AssemblyLinearVelocity" then
			return rootState.Velocity
		elseif key == "Parent" then
			return character
		elseif key == "IsA" then
			return function(_: any, class: string)
				return class == "BasePart" or class == "Part"
			end
		end
		return nil
	end,
	__newindex = function(_self: any, key: string, value: any)
		if key == "CFrame" then
			rootState.CFrame = value
		elseif key == "AssemblyLinearVelocity" then
			rootState.Velocity = value
		end
	end,
})

local function newCharacter(): any
	humanoid = {
		Health = 100,
		HipHeight = 2,
		RigType = Enum.HumanoidRigType.R15,
		FloorMaterial = Enum.Material.Plastic,
		Died = fakeSignal(),
		IsA = function(_: any, class: string)
			return class == "Humanoid"
		end,
		ChangeState = function() end,
	}
	character = {
		WaitForChild = function(_: any, name: string)
			return if name == "Humanoid" then humanoid else rootPart
		end,
	}
	return character
end

local playerAttributes: { [string]: any } = {}
local fakePlayer = {
	GetAttribute = function(_: any, name: string)
		return playerAttributes[name]
	end,
	CharacterAdded = fakeSignal(),
	Character = nil :: any,
}
local camera = { CFrame = roblox.CFrame.new(0, 10, -300) }
local preSimulation = fakeSignal()

local simServices: { [string]: any } = {
	Players = { LocalPlayer = fakePlayer },
	RunService = { PreSimulation = preSimulation },
	Workspace = {
		CurrentCamera = camera,
		GetServerTimeNow = function()
			return sim.T
		end,
		-- Ne déplace que les racines : le contrôleur retrouve les pièces soudées par leur décalage
		-- mis en cache (dans Roblox, l'assemblage soudé suit sa racine).
		BulkMoveTo = function(_: any, parts: { any }, frames: { any }, _mode: any)
			for i, wrapped in parts do
				(realOf[wrapped] or wrapped).CFrame = frames[i]
			end
		end,
	},
	CollectionService = {
		GetTagged = function(_: any, tag: string)
			local list = {}
			for _, instance in tagged(tag) do
				table.insert(list, proxy(instance))
			end
			return list
		end,
		GetInstanceAddedSignal = function()
			return fakeSignal()
		end,
		GetInstanceRemovedSignal = function()
			return fakeSignal()
		end,
	},
	ReplicatedStorage = fakeReplicated,
}

Shim.Globals = {
	game = {
		GetService = function(_self: any, name: string): any
			return simServices[name] or error(`service non simulé : {name}`)
		end,
	},
	Enum = Enum,
	CFrame = roblox.CFrame,
	Vector3 = V3,
	Color3 = roblox.Color3,
	task = simTask,
	warn = function(...: any)
		table.insert(sim.Reports, "warn:" .. table.concat({ ... }, " "))
	end,
}
-- Net est chargé d'abord pour intercepter l'envoi au serveur (même table que celle du contrôleur).
local Net = Shim.load("src/client/Controllers/Net.luau")
Net.Fire = function(name: string, ...: any)
	table.insert(sim.Reports, name .. ":" .. tostring((...)))
end
local TrapController = Shim.load("src/client/Controllers/TrapController.luau")
Shim.Globals = {}
TrapController.OnDeath = function(cause: string)
	table.insert(sim.Deaths, cause)
end

local function spawnCharacter()
	fakePlayer.Character = newCharacter()
	fakePlayer.CharacterAdded:Fire(fakePlayer.Character)
end

-- Place les pieds du personnage (R15 : racine 3 studs au-dessus) et la caméra juste derrière
-- (ou très loin : seuls les pièges proches du personnage sont alors animés, plus rapide).
local function placeFeet(position: any, farCamera: boolean?)
	rootState.CFrame = roblox.CFrame.new(position + V3.new(0, 3, 0))
	rootState.Velocity = V3.new(0, 0, 0)
	camera.CFrame = roblox.CFrame.new(if farCamera then V3.new(0, -1e5, 0) else position + V3.new(0, 12, 20))
	tick()
end

local function stepFor(seconds: number, hz: number)
	local dt = 1 / hz
	for _ = 1, math.floor(seconds * hz) do
		sim.T += dt
		preSimulation:Fire(dt)
		if humanoid.Health <= 0 then
			return
		end
	end
end

local function trapsOfKind(kind: string): { any }
	local list = {}
	for _, part in tagged("Trap") do
		if part:GetAttribute("Kind") == kind then
			table.insert(list, part)
		end
	end
	return list
end

-- Instant (temps serveur) où le cycle du piège vaut `p`.
local function timeAtPhase(part: any, p: number): number
	local period = part:GetAttribute("Period")
	local phase = part:GetAttribute("Phase") or 0
	return (math.floor(sim.T / period) + 2 + ((p - phase) % 1)) * period
end

spawnCharacter()
TrapController.Start()

-- Instantané de toutes les pièces : la simulation déplace/recolore les pièges, on remet tout en place.
local snapshot: { [any]: { any } } = {}
for _, d in descendants do
	if d:IsA("BasePart") then
		snapshot[d] = { d.CFrame, d.Color, d.Transparency, d.CanCollide }
	end
end
local restFrames: { [any]: any } = {}
for part, saved in snapshot do
	restFrames[part] = saved[1]
end
local function restoreAll()
	for part, saved in snapshot do
		part.CFrame = saved[1]
		part.Color = saved[2]
		part.Transparency = saved[3]
		part.CanCollide = saved[4]
		part.LocalTransparencyModifier = 0
	end
end

-- Outil de diagnostic (tests/tools/debug_stage.luau) : chemin le plus court d'une étape.
Shim.TowerDebug = {
	Path = function(s: number): { Rect }
		local rects = stageRects(s)
		local ok = reachable(rects, pads[s - 1], pads[s])
		local path = {}
		if ok then
			local i: number? = lastGoal
			while i do
				table.insert(path, 1, rects[i])
				i = lastParents[i]
			end
		end
		return path
	end,
}

return {
	["TrapController : poses déterministes (Mover, Crusher, SpinBar)"] = function()
		spawnCharacter()
		local function near(part: any)
			local stage = tonumber(string.match(part.Parent.Name, "^Stage(%d+)$"))
			local pad = pads[stage]
			placeFeet(V3.new(pad.CFrame.Position.X, top(pad), pad.CFrame.Position.Z))
		end
		local mover = trapsOfKind("Mover")[1]
		near(mover)
		sim.T = timeAtPhase(mover, 0.5) - 1 / 60
		stepFor(1 / 60, 60)
		local expected = restFrames[mover].Position + mover:GetAttribute("Offset")
		Expect.near((mover.CFrame.Position - expected).Magnitude, 0, 0.01, "Mover à mi-cycle = repos + Offset")
		for _, crusher in trapsOfKind("Crusher") do
			near(crusher)
			sim.T = timeAtPhase(crusher, 0.6) - 1 / 60
			stepFor(1 / 60, 60)
			local down = restFrames[crusher].Position + crusher:GetAttribute("Offset")
			Expect.near((crusher.CFrame.Position - down).Magnitude, 0, 0.01, "Crusher en bas à 60 % du cycle")
			sim.T = timeAtPhase(crusher, 0.2) - 1 / 60
			stepFor(1 / 60, 60)
			Expect.near((crusher.CFrame.Position - restFrames[crusher].Position).Magnitude, 0, 0.01, "Crusher au repos")
			break
		end
		local bar = trapsOfKind("SpinBar")[1]
		near(bar)
		stepFor(1 / 60, 60)
		local angle = (bar:GetAttribute("Speed") * sim.T + (bar:GetAttribute("Phase") or 0) * math.pi * 2)
			% (math.pi * 2)
		local axis = if bar:GetAttribute("Axis") == "Y" then V3.new(0, 1, 0) else V3.new(0, 0, 1)
		local want = restFrames[bar] * roblox.CFrame.fromAxisAngle(axis, angle)
		Expect.near((bar.CFrame.LookVector - want.LookVector).Magnitude, 0, 1e-3, "SpinBar tournée de Speed × t")
		restoreAll()
	end,

	["TrapController : une seule mort par vie, bouclier respecté"] = function()
		spawnCharacter()
		table.clear(sim.Reports)
		table.clear(sim.Deaths)
		placeFeet(V3.new(100, 1, 100)) -- dans le vide du monde 1
		playerAttributes.Shielded = true
		stepFor(0.5, 10)
		Expect.equal(humanoid.Health, 100, "bouclier : pas de mort")
		Expect.equal(#sim.Reports, 0, "bouclier : rien d'envoyé")
		playerAttributes.Shielded = nil
		stepFor(0.2, 10)
		Expect.equal(humanoid.Health, 0, "tombé dans le vide")
		stepFor(0.5, 10)
		Expect.equal(#sim.Reports, 1, "ReportDeath une seule fois")
		Expect.equal(sim.Reports[1], "ReportDeath:Void", "cause Void")
		Expect.equal(#sim.Deaths, 1, "OnDeath une seule fois")
		-- Nouvelle vie : un bloc glitch (danger statique)
		spawnCharacter()
		local glitch
		for _, part in tagged("Hazard") do
			if part.Name == "GlitchBlock" then
				glitch = part
				break
			end
		end
		placeFeet(glitch.CFrame.Position - V3.new(0, 2, 0))
		stepFor(0.2, 10)
		Expect.equal(humanoid.Health, 0, "touché par un bloc glitch")
		Expect.equal(sim.Reports[2], "ReportDeath:Hazard", "cause Hazard")
		restoreAll()
	end,

	["TrapController : Mover transporte, Bounce propulse, Conveyor ramène"] = function()
		-- Mover au milieu de sa course (vitesse maximale)
		spawnCharacter()
		local mover = trapsOfKind("Mover")[1]
		sim.T = timeAtPhase(mover, 0.25)
		placeFeet(mover.CFrame.Position + V3.new(0, mover.Size.Y / 2, 0))
		stepFor(1 / 60, 60) -- premier pas : le Mover rejoint sa pose du moment
		placeFeet(mover.CFrame.Position + V3.new(0, mover.Size.Y / 2, 0))
		local before, platformBefore = rootState.CFrame.Position, mover.CFrame.Position
		stepFor(1 / 30, 30)
		local carried = rootState.CFrame.Position - before
		local moved = mover.CFrame.Position - platformBefore
		Expect.truthy(moved.Magnitude > 0.05, "le Mover bouge")
		Expect.near((carried - moved).Magnitude, 0, 1e-3, "le personnage suit le Mover")
		Expect.equal(humanoid.Health, 100, "vivant sur le Mover")
		-- Trampoline
		local pad = trapsOfKind("Bounce")[1]
		placeFeet(pad.CFrame.Position + V3.new(0, pad.Size.Y / 2, 0))
		stepFor(1 / 30, 30)
		Expect.equal(rootState.Velocity.Y, pad:GetAttribute("Power"), "propulsé par le condensateur")
		-- Tapis de données (loin de la barrette qui écrase au centre)
		local belt = trapsOfKind("Conveyor")[1]
		local spot = belt.CFrame * roblox.CFrame.new(0, belt.Size.Y / 2, belt.Size.Z / 2 - 5)
		placeFeet(spot.Position)
		local start = rootState.CFrame.Position
		stepFor(0.1, 10)
		local push = belt:GetAttribute("Direction") * belt:GetAttribute("Speed") * 0.1
		Expect.near((rootState.CFrame.Position - start - push).Magnitude, 0, 1e-3, "poussé par le tapis")
		Expect.equal(humanoid.Health, 100, "vivant sur le tapis")
		restoreAll()
	end,

	["TrapController : chaque piège mortel tue, avec sa cause"] = function()
		-- Témoins négatifs : sans eux, « personne ne meurt sur les points sûrs » ne prouverait rien.
		local down = V3.new(0, 1, 0)
		local spots: { [string]: (part: any) -> any } = {
			Zapper = function(part)
				return restFrames[part].Position - down * (part.Size.Y / 2)
			end,
			Heat = function(part)
				return restFrames[part].Position - down * (part.Size.Y / 2)
			end,
			Crusher = function(part)
				local low = restFrames[part].Position + part:GetAttribute("Offset")
				return low - down * (part.Size.Y / 2)
			end,
			Laser = function(part)
				return restFrames[part].Position + part:GetAttribute("Offset") * 0.5 - down * 1.4
			end,
			SpinBar = function(part)
				local rest = restFrames[part]
				if part:GetAttribute("Axis") == "Y" then
					return rest.Position + rest.RightVector * 4 - down * 1.3
				end
				return rest.Position - down * 7.4 -- pale verticale : elle balaie le sol sous le moyeu
			end,
			Virus = function(part)
				local text = part:GetAttribute("Waypoints")
				local x, y, z = string.match(text, ";(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+)")
				return restFrames[part].Position + V3.new(tonumber(x), tonumber(y), tonumber(z)) * 0.5 - down * 2.4
			end,
		}
		-- Un piège qui n'est pas au-dessus d'un tapis (le tapis emporterait le personnage témoin).
		local belts = trapsOfKind("Conveyor")
		local function awayFromBelts(kind: string): any
			for _, part in trapsOfKind(kind) do
				local clear = true
				for _, belt in belts do
					if (restFrames[belt].Position - restFrames[part].Position).Magnitude < 40 then
						clear = false
					end
				end
				if clear then
					return part
				end
			end
			error(`aucun {kind} loin des tapis`)
		end
		for kind, spotOf in spots do
			local part = awayFromBelts(kind)
			spawnCharacter()
			table.clear(sim.Reports)
			placeFeet(spotOf(part), true)
			stepFor(8, 20)
			Expect.equal(humanoid.Health, 0, `{kind} n'a pas tué ({part:GetFullName()})`)
			Expect.equal(sim.Reports[1], `ReportDeath:{kind}`, `cause rapportée pour {kind}`)
		end
		restoreAll()
	end,

	["TrapController : un bloc Vanish s'efface puis revient"] = function()
		spawnCharacter()
		local block = trapsOfKind("Vanish")[1]
		local delay, respawn = block:GetAttribute("Delay"), block:GetAttribute("Respawn")
		placeFeet(restFrames[block].Position + V3.new(0, block.Size.Y / 2, 0), true)
		local start = sim.T
		local function waitUntil(seconds: number)
			while sim.T - start < seconds do
				stepFor(1 / 30, 30)
			end
		end
		waitUntil(delay * 0.5)
		Expect.equal(block.CanCollide, true, "encore solide pendant le délai")
		waitUntil(delay + 0.3)
		Expect.equal(block.CanCollide, false, "effacé après le délai")
		placeFeet(V3.new(0, -300, -300), true) -- on s'en va (sinon il repartirait aussitôt)
		waitUntil(delay + respawn + 0.3)
		Expect.equal(block.CanCollide, true, "revenu après Respawn")
		restoreAll()
	end,

	["TrapController : personne ne meurt debout sur un checkpoint ou un palier"] = function()
		spawnCharacter()
		local spots = {}
		for s = 0, Tower.TOTAL_STAGES do
			local pad = pads[s]
			table.insert(
				spots,
				{ Name = `pad {s}`, Feet = V3.new(pad.CFrame.Position.X, top(pad), pad.CFrame.Position.Z) }
			)
		end
		for _, d in descendants do
			if d:IsA("BasePart") and d.Name == "Junction" then
				local p = d.CFrame.Position
				table.insert(spots, { Name = d:GetFullName(), Feet = V3.new(p.X, top(d), p.Z) })
			end
		end
		for _, spot in spots do
			placeFeet(spot.Feet, true) -- le personnage ne bouge plus : une seule mise à jour des listes
			stepFor(6, 12)
			Expect.equal(humanoid.Health, 100, `mort sur {spot.Name} : {sim.Deaths[#sim.Deaths] or "?"}`)
		end
		print(`    {#spots} points sûrs vérifiés pendant 6 s de pièges animés`)
		restoreAll()
	end,

	["tour : construite et renvoyée"] = function()
		Expect.truthy(tower ~= nil, "Workspace.Tower")
		Expect.equal(built, tower, "Build() renvoie Workspace.Tower")
		Expect.truthy(tower:IsA("Folder"), "Tower est un Folder")
		Expect.equal(#workspace:GetChildren(), 1, "une seule tour dans le Workspace")
	end,

	["lobby : spawn, écran de l'app, classements, bornes, Anga, entrée"] = function()
		local lobby = tower:FindFirstChild("Lobby")
		Expect.truthy(lobby and lobby:IsA("Model"), "Lobby (Model)")
		Expect.equal(lobby.ModelStreamingMode, Enum.ModelStreamingMode.Persistent, "Lobby persistant")
		local spawn = lobby:FindFirstChild("LobbySpawn")
		Expect.truthy(spawn and spawn:IsA("SpawnLocation"), "LobbySpawn")
		Expect.equal(spawn.Neutral, true, "spawn neutre")
		Expect.equal(spawn.Duration, 0, "pas de champ de force")
		local screens = tagged("AppScreen")
		Expect.equal(#screens, 1, "un AppScreen")
		local screen = screens[1]
		Expect.between(screen.Size.X, 100, 120, "largeur de l'écran")
		Expect.between(screen.Size.Y, 55, 70, "hauteur de l'écran")
		local toSpawn = (spawn.CFrame.Position - screen.CFrame.Position) * V3.new(1, 0, 1)
		Expect.truthy(screen.CFrame.LookVector:Dot(toSpawn.Unit) > 0.9, "la face avant de l'écran regarde le spawn")
		Expect.truthy(screen:IsDescendantOf(lobby), "écran dans le lobby")
		local boards = {}
		for _, board in tagged("LeaderboardScreen") do
			boards[board:GetAttribute("Board")] = true
			Expect.truthy(board:IsA("BasePart"), "classement = pièce")
			local dir = (spawn.CFrame.Position - board.CFrame.Position) * V3.new(1, 0, 1)
			Expect.truthy(board.CFrame.LookVector:Dot(dir.Unit) > 0.7, `classement {board.Name} tourné vers le spawn`)
		end
		for _, name in { "Wins", "BestTime", "Stage" } do
			Expect.truthy(boards[name], `classement {name}`)
		end
		Expect.equal(#tagged("TitleHologram"), 1, "TitleHologram")
		local actions = {}
		for _, d in lobby:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				local action = d:GetAttribute("Action")
				actions[action] = (actions[action] or 0) + 1
				Expect.truthy(d.Parent:IsA("BasePart"), `prompt {action} sur une pièce`)
				Expect.equal(d.RequiresLineOfSight, false, `prompt {action} sans ligne de vue`)
				Expect.between(d.MaxActivationDistance, 8, 16, `distance du prompt {action}`)
				Expect.between(d.Parent.CFrame.Position.Y, 0, 8, `prompt {action} à hauteur de joueur`)
			end
		end
		for _, action in { "Shop", "Arcade", "Daily" } do
			Expect.equal(actions[action], 1, `borne {action}`)
		end
		Expect.truthy(lobby:FindFirstChild("AngaSpot") and lobby.AngaSpot:IsA("BasePart"), "AngaSpot")
		Expect.truthy(
			pads[0] ~= nil and (pads[0].CFrame.Position - spawn.CFrame.Position).Magnitude < 200,
			"entrée proche du spawn"
		)
	end,

	["checkpoints : 0..TOTAL une fois chacun, en montant, bien orientés"] = function()
		Expect.equal(#padErrors, 0, table.concat(padErrors, "\n      "))
		Expect.truthy(tower:FindFirstChild("Checkpoints") ~= nil, "dossier Checkpoints")
		local previousWorldTop = -math.huge
		for s = 0, Tower.TOTAL_STAGES do
			local pad = pads[s]
			Expect.truthy(pad ~= nil, `checkpoint {s}`)
			Expect.truthy(pad.CanCollide and pad.CanTouch, `pad {s} solide et touchable`)
			Expect.between(pad.Size.X, 10, 14, `largeur du pad {s}`)
			Expect.between(pad.Size.Z, 10, 14, `profondeur du pad {s}`)
			Expect.truthy(math.abs(pad.CFrame.LookVector.Y) < 1e-3, `pad {s} à plat`)
			if s > 0 then
				local prev = pads[s - 1]
				Expect.truthy(top(pad) > top(prev), `checkpoint {s} plus haut que {s - 1}`)
				local d = (pad.CFrame.Position - prev.CFrame.Position).Magnitude
				Expect.between(d, 20, 260, `distance {s - 1} -> {s}`)
				-- Le pad précédent regarde vers la suite (salle du terminal : vers le terminal ;
				-- pad 0 : vers la porte du parcours, dans la façade de la tour)
				if s == 1 then
					Expect.truthy(prev.CFrame.LookVector.Z > 0.9, "pad 0 tourné vers la porte de la tour")
				elseif (s - 1) % Tower.STAGES_PER_WORLD ~= 0 then
					local dir = (pad.CFrame.Position - prev.CFrame.Position) * V3.new(1, 0, 1)
					Expect.truthy(prev.CFrame.LookVector:Dot(dir.Unit) > 0.3, `pad {s - 1} tourné vers la suite`)
				end
			end
			local w = Tower.WorldOf(s)
			if s > 0 and s == Tower.FirstStage(w) then
				Expect.truthy(top(pad) > previousWorldTop, `monde {w} au-dessus du monde {w - 1}`)
			end
			if s > 0 then
				previousWorldTop = math.max(previousWorldTop, top(pad))
			end
		end
	end,

	["checkpoints : place libre pour réapparaître (pad + 4)"] = function()
		local problems = {}
		for s, pad in pads do
			local p = pad.CFrame.Position
			local y0, y1 = top(pad) + 0.2, top(pad) + 6.5
			for _, d in descendants do
				if d:IsA("BasePart") and d.CanCollide and d ~= pad then
					local e = extents(d)
					local c = d.CFrame.Position
					if
						c.Y - e.Y < y1
						and c.Y + e.Y > y0
						and math.abs(c.X - p.X) < e.X + 3
						and math.abs(c.Z - p.Z) < e.Z + 3
					then
						table.insert(problems, `pad {s} : {d:GetFullName()}`)
					end
				end
			end
		end
		Expect.equal(#problems, 0, "obstacles au-dessus des pads :\n      " .. table.concat(problems, "\n      "))
	end,

	["terminaux, portails et arrivée"] = function()
		local terminals, gates = {}, {}
		for _, part in tagged("MinigameTerminal") do
			local w = part:GetAttribute("World")
			Expect.truthy(type(w) == "number" and not terminals[w], `terminal World={w}`)
			terminals[w] = part
			Expect.equal(worldOfInstance(part), w, "terminal dans son monde")
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			Expect.truthy(prompt ~= nil, `prompt du terminal {w}`)
			Expect.equal(prompt:GetAttribute("Action"), "Minigame", "action du terminal")
			Expect.equal(prompt:GetAttribute("World"), w, "monde du prompt")
			Expect.equal(prompt.RequiresLineOfSight, false, "prompt sans ligne de vue")
			Expect.between(prompt.MaxActivationDistance, 8, 16, "distance du prompt")
			-- Dans la salle du terminal : même étage que le pad de fin de monde, à moins de 50 studs
			local pad = pads[Tower.TerminalStage(w)]
			Expect.between(part.CFrame.Position.Y - top(pad), 0, 6, `terminal {w} à hauteur du pad`)
			Expect.truthy((part.CFrame.Position - pad.CFrame.Position).Magnitude < 50, `terminal {w} près du pad`)
		end
		for _, part in tagged("WorldGate") do
			local w = part:GetAttribute("World")
			Expect.truthy(type(w) == "number" and not gates[w], `portail World={w}`)
			gates[w] = part
			Expect.equal(part.CanCollide, false, "portail traversable côté serveur")
			Expect.equal(worldOfInstance(part), w, "portail dans son monde")
			Expect.truthy(
				(part.CFrame.Position - terminals[w].CFrame.Position).Magnitude < 60,
				"portail près du terminal"
			)
		end
		for w = 1, Tower.WORLD_COUNT do
			Expect.truthy(terminals[w] ~= nil, `terminal du monde {w}`)
			Expect.truthy(gates[w] ~= nil, `portail du monde {w}`)
			local model = tower:FindFirstChild(`World{w}`)
			Expect.truthy(model and model:IsA("Model") and model:GetAttribute("World") == w, `World{w}`)
		end
		local finishes = tagged("Finish")
		Expect.equal(#finishes, 1, "une arrivée")
		local finish = finishes[1]
		Expect.truthy(finish.CanTouch, "arrivée touchable")
		local finishY = finish.CFrame.Position.Y
		for _, tag in { "Checkpoint", "Trap", "Coin", "MinigameTerminal", "WorldGate", "Hazard" } do
			for _, part in tagged(tag) do
				Expect.truthy(top(part) < finishY, `{part:GetFullName()} au-dessus de l'arrivée`)
			end
		end
		Expect.truthy(finishY > gates[Tower.WORLD_COUNT].CFrame.Position.Y + 20, "arrivée après le portail 7")
	end,

	["Bits : CoinId uniques, 3 à 6 par étape"] = function()
		local ids, perStage = {}, {}
		for _, coin in tagged("Coin") do
			local id = coin:GetAttribute("CoinId")
			Expect.truthy(type(id) == "string" and #id > 0, "CoinId")
			Expect.truthy(not ids[id], `CoinId en double : {id}`)
			ids[id] = true
			Expect.equal(coin.CanCollide, false, "Bit traversable")
			Expect.equal(coin.CanTouch, true, "Bit touchable")
			local stage = tonumber(string.match(id, "^S(%d+)C%d+$"))
			Expect.truthy(stage ~= nil, `format de CoinId : {id}`)
			perStage[stage] = (perStage[stage] or 0) + 1
		end
		for s = 1, Tower.TOTAL_STAGES do
			Expect.between(perStage[s] or 0, 3, 6, `Bits de l'étape {s}`)
		end
	end,

	["pièges : type valide, attributs requis, fenêtres sûres, code couleur"] = function()
		local kinds = {}
		for _, kind in Tower.TrapKinds do
			kinds[kind] = 0
		end
		for _, part in tagged("Trap") do
			local kind = part:GetAttribute("Kind")
			local name = part:GetFullName()
			Expect.truthy(kinds[kind] ~= nil, `Kind inconnu {kind} : {name}`)
			kinds[kind] += 1
			for attribute, typeName in REQUIRED[kind] do
				local value = part:GetAttribute(attribute)
				Expect.truthy(isA(value, typeName), `{attribute} ({typeName}) manquant sur {name}`)
				if typeName == "number" then
					Expect.truthy(value == value and math.abs(value) < 1e6, `{attribute} invalide sur {name}`)
				end
			end
			Expect.truthy(worldOfInstance(part) ~= nil, `{name} hors d'un monde`)
			local period = part:GetAttribute("Period")
			if period ~= nil then
				Expect.truthy(period > 0.5, `Period trop courte sur {name}`)
			end
			local phase = part:GetAttribute("Phase")
			if phase ~= nil then
				Expect.between(phase, 0, 1, `Phase sur {name}`)
			end
			if kind == "Zapper" or kind == "Heat" then
				local duty = part:GetAttribute("Duty")
				Expect.between(duty, 0.05, 0.95, `Duty sur {name}`)
				Expect.truthy(period * (1 - duty) >= 1.2, `fenêtre sûre < 1,2 s sur {name}`)
			elseif kind == "Crusher" then
				Expect.truthy(period * 0.45 >= 1.2, `fenêtre sûre < 1,2 s sur {name}`)
			elseif kind == "SpinBar" then
				local axis = part:GetAttribute("Axis")
				Expect.truthy(axis == "X" or axis == "Y" or axis == "Z", `Axis sur {name}`)
			elseif kind == "Virus" then
				local points = parseWaypoints(part:GetAttribute("Waypoints"))
				Expect.truthy(points ~= nil and #points >= 2, `Waypoints illisibles sur {name}`)
				Expect.truthy(part:GetAttribute("Speed") > 0, `Speed sur {name}`)
			elseif kind == "Vanish" then
				Expect.truthy(part:GetAttribute("Delay") >= 0.5, `Delay sur {name}`)
			elseif kind == "Wind" then
				Expect.truthy(part:GetAttribute("Strength") < 14, `vent plus fort que la marche : {name}`)
			end
			if LETHAL_KINDS[kind] then
				Expect.equal(part.CanCollide, false, `piège mortel non solide : {name}`)
				local c = part.Color
				Expect.truthy(c.R >= 0.45 and c.G <= 0.45, `piège mortel rouge/magenta : {name}`)
			elseif SOLID_KINDS[kind] then
				Expect.equal(part.CanCollide, true, `plateforme solide : {name}`)
			end
		end
		for _, part in tagged("Hazard") do
			Expect.equal(part.CanCollide, false, "danger non solide")
			local c = part.Color
			Expect.truthy(c.R >= 0.45 and c.G <= 0.45, `danger rouge/magenta : {part:GetFullName()}`)
		end
		local summary = {}
		for kind, count in kinds do
			table.insert(summary, `{kind} {count}`)
		end
		table.sort(summary)
		print(`    pièges : {table.concat(summary, ", ")}`)
		for _, world in Tower.Worlds do
			for _, kind in world.Traps do
				local found = false
				for _, part in tagged("Trap") do
					if part:GetAttribute("Kind") == kind and worldOfInstance(part) == world.Index then
						found = true
						break
					end
				end
				Expect.truthy(found, `piège vedette {kind} absent du monde {world.Index}`)
			end
		end
	end,

	["pièges et dangers : attribut World = monde qui les contient"] = function()
		local count = 0
		for _, tag in { "Trap", "Hazard" } do
			for _, part in tagged(tag) do
				local w = part:GetAttribute("World")
				local owner = worldOfInstance(part)
				if tag == "Trap" or owner ~= nil then
					Expect.truthy(type(w) == "number", `attribut World (nombre) manquant sur {part:GetFullName()}`)
					Expect.equal(w, owner, `World de {part:GetFullName()}`)
					count += 1
				end
			end
		end
		Expect.truthy(count > 0, "aucun piège vérifié")
	end,

	["mondes : entrée sur le toit de la salle précédente, salle du terminal fixe"] = function()
		for w = 1, Tower.WORLD_COUNT do
			-- L'entrée (ctx.Entry) est posée sur le toit de la maison d'où l'on arrive.
			local entry = Common.EntryOf(w).Position
			local house = if w == 1 then tower.Lobby.Start else tower[`World{w - 1}`].Terminal
			local onRoof = false
			for _, d in house:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Roof" then
					local e, c = extents(d), d.CFrame.Position
					if
						math.abs(entry.X - c.X) <= e.X
						and math.abs(entry.Z - c.Z) <= e.Z
						and math.abs(top(d) - entry.Y) < 0.01
					then
						onRoof = true
					end
				end
			end
			Expect.truthy(onRoof, `entrée du monde {w} hors du toit de la salle précédente`)
			-- La salle du terminal est à l'emplacement fixe : pad TerminalStage(w) juste derrière la porte.
			local terminalPad = pads[Tower.TerminalStage(w)]
			local fr = Common.CornerFrame(Common.TerminalCorner(w))
			local door = Common.CFA(fr, -8, Common.WorldBase(w) + Common.TERMINAL_FLOOR, 0)
			Expect.near(top(terminalPad) - 0.4, door.Position.Y, 0.01, `plancher de la salle {w}`)
			Expect.near((terminalPad.CFrame.Position - door.Position).Magnitude, 8, 0.2, `pad de la salle {w}`)
		end
	end,

	["contexte de monde : clés USB, infecté / nettoyé, pièges, garde-fous"] = function()
		local scratch = Instance.new("Folder")
		local ctx, finish = Common.NewContext(scratch, Tower.Worlds[2])
		Expect.equal(ctx.Index, 2, "Index")
		Expect.equal(ctx.Model.Name, "World2", "Model World2")
		Expect.equal(ctx.Model:GetAttribute("World"), 2, "attribut World du Model")
		Expect.equal(ctx.Base, 100, "Base")
		Expect.near((ctx.Entry.Position - Common.EntryOf(2).Position).Magnitude, 0, 1e-6, "Entry")
		Expect.equal(#ctx.Reserved, 2, "volumes réservés")
		-- Clé USB
		local key = ctx.UsbKey(V3.new(0, 150, 0), 3)
		Expect.truthy(key:HasTag("UsbKey"), "tag UsbKey")
		Expect.equal(key:GetAttribute("KeyId"), "W2K3", "KeyId")
		Expect.equal(key.CanCollide, false, "clé traversable")
		Expect.equal(key.CanTouch, true, "clé touchable")
		Expect.truthy(key:IsDescendantOf(ctx.Model), "clé dans le monde")
		Expect.truthy(not pcall(ctx.UsbKey, V3.new(0, 150, 0), 3), "clé en double refusée")
		Expect.truthy(not pcall(ctx.UsbKey, V3.new(0, 150, 0), Tower.USB_KEYS_PER_WORLD + 1), "index de clé refusé")
		-- Décor infecté / nettoyé
		local infected, cleaned = Instance.new("Part"), Instance.new("Model")
		ctx.Infected(infected)
		ctx.Cleaned(cleaned)
		Expect.truthy(infected:HasTag("Infected") and infected:GetAttribute("World") == 2, "Infected + World")
		Expect.truthy(cleaned:HasTag("Cleaned") and cleaned:GetAttribute("World") == 2, "Cleaned + World")
		-- Piège : tag, Kind, World, paramètres
		local part = Instance.new("Part")
		ctx.Trap("Crusher", part, { Period = 3 })
		Expect.truthy(part:HasTag("Trap"), "tag Trap")
		Expect.equal(part:GetAttribute("Kind"), "Crusher", "Kind")
		Expect.equal(part:GetAttribute("World"), 2, "World")
		Expect.equal(part:GetAttribute("Period"), 3, "paramètres")
		-- Bit : CoinId de l'étape courante
		ctx.Stage(Tower.FirstStage(2))
		local bit = ctx.Coin(V3.new(0, 120, 0))
		Expect.equal(bit:GetAttribute("CoinId"), `S{Tower.FirstStage(2)}C1`, "CoinId")
		-- Garde-fous : checkpoints hors du monde, salle du terminal oubliée
		Expect.truthy(not pcall(ctx.Checkpoint, Tower.TerminalStage(2), roblox.CFrame.new()), "checkpoint de la salle")
		Expect.truthy(
			not pcall(ctx.Checkpoint, Tower.TerminalStage(1), roblox.CFrame.new()),
			"checkpoint d'un autre monde"
		)
		Expect.truthy(not pcall(ctx.Stage, Tower.TerminalStage(2) + 1), "étape d'un autre monde")
		Expect.truthy(not pcall(finish), "monde sans salle du terminal refusé")
		scratch:Destroy()
	end,

	["vide mortel sous chaque monde"] = function()
		for w = 1, Tower.WORLD_COUNT do
			local voids = {}
			for _, part in tower[`World{w}`]:GetDescendants() do
				if part:IsA("BasePart") and part:HasTag("Hazard") and part:GetAttribute("Cause") == "Void" then
					table.insert(voids, part)
				end
			end
			Expect.truthy(#voids > 0, `vide du monde {w}`)
			local lowest = math.huge
			for s = Tower.FirstStage(w), Tower.TerminalStage(w) do
				lowest = math.min(lowest, top(pads[s]))
			end
			-- Sous chaque point du parcours (milieu de chaque côté), il y a du vide plus bas
			for s = Tower.FirstStage(w), Tower.TerminalStage(w) do
				local a, b = pads[s - 1].CFrame.Position, pads[s].CFrame.Position
				local mid = (a + b) / 2
				local covered = false
				for _, void in voids do
					local e, c = extents(void), void.CFrame.Position
					if math.abs(mid.X - c.X) <= e.X and math.abs(mid.Z - c.Z) <= e.Z and top(void) < lowest - 5 then
						covered = true
					end
				end
				Expect.truthy(covered, `vide sous l'étape {s}`)
			end
		end
	end,

	["budget mobile : pièces, lumières, pièces libres soudées"] = function()
		local parts, lights, guis = 0, 0, 0
		for _, d in descendants do
			if d:IsA("BasePart") then
				parts += 1
				if not d.Anchored then
					local weld = d:FindFirstChildOfClass("WeldConstraint")
					local root = weld and weld.Part0
					Expect.truthy(
						root ~= nil and root.Anchored and (root:HasTag("Trap") or root:HasTag("TrapSpin")),
						`pièce non ancrée sans racine animée : {d:GetFullName()}`
					)
				end
			elseif d:IsA("SurfaceGui") then
				guis += 1
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
				Expect.equal(d.Shadows, false, `ombres sur {d:GetFullName()}`)
			end
		end
		print(
			`    {parts} pièces, {lights} lumières, {guis} SurfaceGui, {#tagged("Trap")} pièges, {#tagged("Coin")} Bits`
		)
		Expect.truthy(parts <= 8000, `trop de pièces : {parts}`)
		Expect.truthy(lights <= 90, `trop de lumières : {lights}`)
		Expect.truthy(guis <= 250, `trop de SurfaceGui : {guis}`)
	end,

	["aucune géométrie invalide (NaN)"] = function()
		for _, d in descendants do
			if d:IsA("BasePart") then
				local p = d.CFrame.Position
				local look, up = d.CFrame.LookVector, d.CFrame.UpVector
				Expect.truthy(p == p and look == look and up == up, `CFrame NaN : {d:GetFullName()}`)
				Expect.truthy(math.abs(look:Dot(up)) < 1e-3, `repère non orthogonal : {d:GetFullName()}`)
				Expect.truthy(d.Size.X > 0 and d.Size.Y > 0 and d.Size.Z > 0, `taille nulle : {d:GetFullName()}`)
				Expect.truthy(
					d.Size.X <= 2048 and d.Size.Y <= 2048 and d.Size.Z <= 2048,
					`pièce trop grande : {d:GetFullName()}`
				)
			end
		end
	end,

	["chaque étape est franchissable (graphe de sauts)"] = function()
		local problems, hops = {}, {}
		for s = 1, Tower.TOTAL_STAGES do
			local ok, count = reachable(stageRects(s), pads[s - 1], pads[s])
			if not ok then
				table.insert(problems, `étape {s} : pad {s} inaccessible depuis le pad {s - 1}`)
			end
			table.insert(hops, count)
		end
		print(`    sauts / marches par étape : {table.concat(hops, " ")}`)
		Expect.equal(#problems, 0, table.concat(problems, "\n      "))
	end,

	["le sommet est accessible depuis la dernière salle"] = function()
		local rects = {}
		for _, d in tower[`World{Tower.WORLD_COUNT}`].Terminal:GetDescendants() do
			if d:IsA("BasePart") then
				surfaces(d, rects)
			end
		end
		surfaces(pads[Tower.TOTAL_STAGES], rects)
		local finish = tagged("Finish")[1]
		-- Faux pad posé sous l'arrivée (dessus du toit)
		local roofTop = -math.huge
		for _, r in rects do
			local p = finish.CFrame.Position
			if p.X >= r.X0 and p.X <= r.X1 and p.Z >= r.Z0 and p.Z <= r.Z1 and r.Y < p.Y then
				roofTop = math.max(roofTop, r.Y)
			end
		end
		Expect.truthy(finish.CFrame.Position.Y - roofTop < 8, "arrivée à portée de main au-dessus du toit")
		local goal = {
			CFrame = roblox.CFrame.new(finish.CFrame.Position.X, roofTop - 0.5, finish.CFrame.Position.Z),
			Size = V3.new(1, 1, 1),
		}
		local ok = reachable(rects, pads[Tower.TOTAL_STAGES], goal)
		Expect.truthy(ok, "toit du sommet inaccessible")
	end,
}
