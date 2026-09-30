-- Simule le VRAI TrapController (client) sur de petites scènes construites ici, pour les 14 pièges
-- v2 « Opération Anti-Lag » et les incidents de LAGZ (FREEZE, LAG SPIKE, BLACKOUT, CORRUPTION,
-- SURCHAUFFE) : poses déterministes, danger / sécurité, transport, préavis, habillage client.
-- Services factices (comme tower.spec), temps serveur piloté par le test, IncidentState = vrai
-- dossier d'attributs. Le contrôleur est chargé dans un bac à sable (cache de modules à part).
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Instance, Enum, V3, CF, Color3 = roblox.Instance, roblox.Enum, roblox.Vector3, roblox.CFrame, roblox.Color3

------------------------------------------------------------------------------------
-- Scène : Workspace, dossier d'habillage, mondes 2 et 3, état des incidents
------------------------------------------------------------------------------------

local dataModel = Instance.new("DataModel")
local workspace = dataModel:GetService("Workspace")
local replicated = dataModel:GetService("ReplicatedStorage")
local rigFolder = Instance.new("Folder")
rigFolder.Name = "TrapRigs"
rigFolder.Parent = workspace
local incidentState = Instance.new("Folder")
incidentState.Name = "IncidentState"
incidentState.Parent = replicated
local worlds = {}
for _, w in { 2, 3 } do
	local model = Instance.new("Model")
	model.Name = `World{w}`
	model:SetAttribute("World", w)
	model.Parent = workspace
	worlds[w] = model
end

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

-- Pièces enveloppées : Lune n'a ni Position ni événements d'instance.
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

-- Relance la boucle de recalcul des listes de proximité du contrôleur.
local function tick()
	local waiting = sim.Waiting
	sim.Waiting = {}
	for _, co in waiting do
		local ok, err = coroutine.resume(co)
		assert(ok, err)
	end
end

------------------------------------------------------------------------------------
-- Personnage local factice (R15 : racine 3 studs au-dessus des pieds)
------------------------------------------------------------------------------------

local rootState = { CFrame = CF.new(0, 500, 0), Velocity = V3.new(0, 0, 0) }
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
local camera = { CFrame = CF.new(0, 30, 60) }
local preSimulation = fakeSignal()
local added = { Trap = fakeSignal(), Hazard = fakeSignal(), TrapSpin = fakeSignal() }
local removed = { Trap = fakeSignal(), Hazard = fakeSignal(), TrapSpin = fakeSignal() }

local simServices: { [string]: any } = {
	Players = { LocalPlayer = fakePlayer },
	RunService = { PreSimulation = preSimulation },
	Workspace = {
		CurrentCamera = camera,
		GetServerTimeNow = function()
			return sim.T
		end,
		BulkMoveTo = function(_: any, parts: { any }, frames: { any }, _mode: any)
			for i, wrapped in parts do
				(realOf[wrapped] or wrapped).CFrame = frames[i]
			end
		end,
		FindFirstChild = function(_: any, name: string)
			return if name == "TrapRigs" then rigFolder else nil
		end,
	},
	CollectionService = {
		GetTagged = function(_: any, _tag: string)
			return {}
		end,
		GetInstanceAddedSignal = function(_: any, tag: string)
			return added[tag]
		end,
		GetInstanceRemovedSignal = function(_: any, tag: string)
			return removed[tag]
		end,
	},
	ReplicatedStorage = {
		WaitForChild = function(_: any, _name: string)
			return Shim.Node("src/shared")
		end,
		FindFirstChild = function(_: any, name: string)
			return if name == "IncidentState" then incidentState else nil
		end,
	},
}

local globals = {
	game = {
		GetService = function(_self: any, name: string): any
			return simServices[name] or error(`service non simulé : {name}`)
		end,
	},
	Instance = Instance,
	Enum = Enum,
	CFrame = CF,
	Vector3 = V3,
	Color3 = Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	task = simTask,
	warn = function(...: any)
		table.insert(sim.Reports, "warn:" .. table.concat({ ... }, " "))
	end,
}

-- Bac à sable : charge le contrôleur et ses modules avec NOS services (le cache de Shim.load est
-- partagé entre les specs et contient déjà le contrôleur de tower.spec).
local cache: { [string]: any } = {}
local function load(path: string): any
	if cache[path] ~= nil then
		return cache[path]
	end
	local env: { [string]: any } = {
		script = Shim.Node(path),
		require = function(target: any)
			local targetPath = type(target) == "table" and rawget(target, "__path")
			if not targetPath then
				error("[traps.spec] require non supporté : " .. tostring(target))
			end
			return load(targetPath)
		end,
	}
	for key, value in globals do
		env[key] = value
	end
	local result = luau.load(fs.readFile(path), { debugName = path, environment = env })()
	cache[path] = result
	return result
end

local Net = load("src/client/Controllers/Net.luau")
Net.Fire = function(name: string, ...: any)
	table.insert(sim.Reports, name .. ":" .. tostring((...)))
end
local TrapController = load("src/client/Controllers/TrapController.luau")
local TrapClock = load("src/shared/Util/TrapClock.luau")
TrapController.OnDeath = function(cause: string)
	table.insert(sim.Deaths, cause)
end
local cues: { string } = {}
TrapController.OnCue = function(cue: string, kind: string, _position: any)
	table.insert(cues, `{kind}:{cue}`)
end

local function spawnCharacter()
	fakePlayer.Character = newCharacter()
	fakePlayer.CharacterAdded:Fire(fakePlayer.Character)
end

local function feet(): any
	return rootState.CFrame.Position - V3.new(0, 3, 0)
end

local function placeFeet(position: any)
	rootState.CFrame = CF.new(position + V3.new(0, 3, 0))
	rootState.Velocity = V3.new(0, 0, 0)
	camera.CFrame = CF.new(position + V3.new(0, 20, 40))
	tick()
end

local function stepFor(seconds: number, hz: number)
	local dt = 1 / hz
	for _ = 1, math.floor(seconds * hz + 0.5) do
		sim.T += dt
		preSimulation:Fire(dt)
		if humanoid.Health <= 0 then
			return
		end
	end
end

-- Une image exactement à l'instant t.
local function frameAt(t: number)
	sim.T = t - 1 / 60
	stepFor(1 / 60, 60)
end

-- Avance jusqu'à l'instant t (s'arrête à la mort).
local function runUntil(t: number, hz: number?)
	local dt = 1 / (hz or 30)
	while sim.T < t - 1e-9 and humanoid.Health > 0 do
		sim.T += dt
		preSimulation:Fire(dt)
	end
end

-- Instant (futur) où le cycle vaut p.
local function timeAt(period: number, phase: number, p: number): number
	return (math.floor(sim.T / period) + 2 + ((p - phase) % 1)) * period
end

------------------------------------------------------------------------------------
-- Pièges de test
------------------------------------------------------------------------------------

local live: { any } = {}

local function newTrap(kind: string, size: any, position: any, attributes: { [string]: any }, options: any?): any
	local opts = options or {}
	local part = Instance.new("Part")
	part.Name = kind
	part.Size = size
	part.CFrame = if typeof(position) == "CFrame" then position else CF.new(position)
	part.Anchored = true
	part.CanCollide = opts.Collide == true
	part.Color = opts.Color or Color3.fromRGB(240, 60, 90)
	if opts.Shape then
		part.Shape = opts.Shape
	end
	part:SetAttribute("Kind", kind)
	for key, value in attributes do
		part:SetAttribute(key, value)
	end
	part.Parent = opts.Parent or worlds[3]
	part:AddTag("Trap")
	added.Trap:Fire(proxy(part))
	table.insert(live, part)
	return part
end

local function setIncident(world: number, kind: string, start: number, finish: number, offset: number?)
	incidentState:SetAttribute(`Kind{world}`, kind)
	incidentState:SetAttribute(`Start{world}`, start)
	incidentState:SetAttribute(`End{world}`, finish)
	incidentState:SetAttribute(`Offset{world}`, offset or 0)
end

local function clearAll()
	for _, part in live do
		removed.Trap:Fire(proxy(part))
		part:Destroy()
	end
	table.clear(live)
	for _, w in { 2, 3 } do
		setIncident(w, "", 0, 0, 0)
	end
	playerAttributes.Shielded = nil
	playerAttributes.ReducedMotion = nil
	Expect.equal(#rigFolder:GetChildren(), 0, "habillage détruit avec son piège")
	sim.T = math.floor(sim.T / 100 + 1) * 100
end

local function rigPart(kind: string, name: string): any
	local rig = rigFolder:FindFirstChild(`{kind}Rig`)
	Expect.truthy(rig ~= nil, `habillage {kind} ({table.concat(sim.Reports, " | ")})`)
	local part = rig:FindFirstChild(name, true)
	Expect.truthy(part ~= nil, `pièce {name} de {kind}`)
	return part
end

-- Une valeur proche de v a-t-elle été vue ? (propriétés stockées en float32)
local function saw(seen: { [number]: boolean }, v: number): boolean
	for value in seen do
		if math.abs(value - v) < 1e-3 then
			return true
		end
	end
	return false
end

local function near(a: any, b: any, tolerance: number, message: string)
	Expect.near((a - b).Magnitude, 0, tolerance, message)
end

-- Le personnage posé sur `part` (dessus) est-il transporté exactement comme elle ?
local function expectCarried(part: any, top: number, message: string)
	placeFeet(part.CFrame.Position + V3.new(0, top, 0))
	local before, platformBefore = feet(), part.CFrame.Position
	stepFor(1 / 30, 30)
	local moved = part.CFrame.Position - platformBefore
	Expect.truthy(moved.Magnitude > 0.02, `{message} : la plateforme bouge`)
	near(feet() - before, moved, 1e-3, `{message} : le personnage suit`)
	Expect.equal(humanoid.Health, 100, `{message} : vivant`)
end

spawnCharacter()
TrapController.Start()
tick()

return {
	["Surge : impulsion qui court le câble, mortelle seulement en course"] = function()
		spawnCharacter()
		local surge = newTrap(
			"Surge",
			V3.new(3, 3, 3),
			V3.new(0, 5, 0),
			{ Waypoints = "0,0,0;40,0,0", Speed = 10, Period = 6 },
			{ Shape = Enum.PartType.Ball }
		)
		placeFeet(V3.new(0, 100, 0))
		local t0 = timeAt(6, 0, 0)
		frameAt(t0 + 0.8 + 2) -- 2 s de course : 20 studs
		near(surge.CFrame.Position, V3.new(20, 5, 0), 0.01, "pose = repos + chemin(Speed × t)")
		frameAt(t0 + 0.4)
		near(surge.CFrame.Position, V3.new(0, 5, 0), 0.01, "en charge au début du câble")
		-- Sûr pendant la charge (même posé au départ) et pendant le repos
		sim.T = t0 + 6
		placeFeet(V3.new(0, 3.5, 0))
		runUntil(t0 + 6 + 0.7)
		Expect.equal(humanoid.Health, 100, "charge : pas de danger")
		placeFeet(V3.new(20, 3.5, 0))
		sim.T = t0 + 12 + 4.9
		runUntil(t0 + 12 + 5.9)
		Expect.equal(humanoid.Health, 100, "repos : pas de danger")
		-- Mortel quand l'impulsion passe
		table.clear(sim.Reports)
		sim.T = t0 + 18
		runUntil(t0 + 24)
		Expect.equal(humanoid.Health, 0, "l'impulsion tue")
		Expect.equal(sim.Reports[1], "ReportDeath:Surge", "cause Surge")
		-- charge 0,8 s + 20 studs à 10 studs/s, moins le rayon de la boule et du corps
		Expect.between(sim.T - (t0 + 18), 2.45, 2.85, "au passage de l'impulsion")
		clearAll()
	end,

	["Surge : bouclier respecté, une seule mort par vie, OnDeath"] = function()
		spawnCharacter()
		newTrap("Surge", V3.new(3, 3, 3), V3.new(0, 5, 0), { Waypoints = "0,0,0;40,0,0", Speed = 10, Period = 6 })
		table.clear(sim.Reports)
		table.clear(sim.Deaths)
		placeFeet(V3.new(20, 3.5, 0))
		playerAttributes.Shielded = true
		local t0 = timeAt(6, 0, 0)
		sim.T = t0
		runUntil(t0 + 6)
		Expect.equal(humanoid.Health, 100, "bouclier : pas de mort")
		playerAttributes.Shielded = nil
		runUntil(t0 + 12)
		Expect.equal(humanoid.Health, 0, "sans bouclier : mort")
		runUntil(t0 + 20)
		Expect.equal(#sim.Reports, 1, "ReportDeath une seule fois")
		Expect.equal(#sim.Deaths, 1, "OnDeath une seule fois")
		Expect.equal(sim.Deaths[1], "Surge", "OnDeath(cause)")
		clearAll()
	end,

	["Powered : solide au rythme du courant, clignote avant, éteinte en BLACKOUT"] = function()
		spawnCharacter()
		local pad = newTrap("Powered", V3.new(8, 1, 8), V3.new(0, 0, 0), { Period = 4, Duty = 0.5 }, { Collide = true })
		local other = newTrap(
			"Powered",
			V3.new(8, 1, 8),
			V3.new(20, 0, 0),
			{ Period = 4, Duty = 0.5 },
			{ Collide = true, Parent = worlds[2] }
		)
		placeFeet(V3.new(0, 30, 0))
		frameAt(timeAt(4, 0, 0.25))
		Expect.equal(pad.CanCollide, true, "allumée : solide")
		Expect.equal(pad.Transparency, 0, "allumée : visible")
		-- Préavis : clignote pendant les 0,8 s avant de s'éteindre, toujours solide
		local t = timeAt(4, 0, 0.5) - 0.75
		sim.T = t
		local seen = {}
		while sim.T < t + 0.7 do
			stepFor(1 / 60, 60)
			seen[pad.Transparency] = true
			Expect.equal(pad.CanCollide, true, "solide pendant le préavis")
		end
		Expect.truthy(saw(seen, 0.55) and saw(seen, 0), "clignote avant de s'éteindre")
		frameAt(timeAt(4, 0, 0.75))
		Expect.equal(pad.CanCollide, false, "éteinte : traversable")
		Expect.near(pad.Transparency, 0.85, 1e-3, "éteinte : fantôme visible")
		-- BLACKOUT dans le monde 3 : éteinte et invisible même en phase allumée ; le monde 2 continue
		local on = timeAt(4, 0, 0.25)
		setIncident(3, "Blackout", on - 1, on + 5)
		frameAt(on)
		Expect.equal(pad.CanCollide, false, "BLACKOUT : traversable")
		Expect.equal(pad.Transparency, 1, "BLACKOUT : invisible")
		Expect.equal(other.CanCollide, true, "le monde 2 n'est pas touché")
		-- Annonce du BLACKOUT : clignote tout en restant solide
		local later = timeAt(4, 0, 0.1)
		setIncident(3, "Blackout", later + 2.5, later + 9)
		sim.T = later
		table.clear(seen)
		for _ = 1, 30 do
			stepFor(1 / 60, 60)
			seen[pad.Transparency] = true
		end
		Expect.equal(pad.CanCollide, true, "annonce : encore solide")
		Expect.truthy(saw(seen, 0.55), "annonce : clignote")
		clearAll()
	end,

	["TabRain : l'onglet tombe (mortel, ombre au sol), puis sert de plateforme, puis se ferme"] = function()
		spawnCharacter()
		-- Zone 18 × 30 × 14 centrée en y = 20 : haut 35, bas 5 ; 2 × 2 cases ; stock de 4 onglets
		newTrap("TabRain", V3.new(1, 1, 1), V3.new(0, 20, 0), { Size = V3.new(18, 30, 14), Period = 2, Stay = 3 })
		placeFeet(V3.new(0, 60, 0))
		local n = math.floor(sim.T / 2) + 3
		local born = n * 2
		frameAt(born - 1)
		local body = rigPart("TabRain", `Tab{n % 4 + 1}`)
		local shadow = rigPart("TabRain", `Shadow{n % 4 + 1}`)
		-- Préavis : l'ombre est au sol plus de 0,8 s avant l'impact (ouverture 0,5 + chute 1,2)
		frameAt(born + 0.8)
		Expect.truthy(shadow.Transparency < 1, "ombre visible avant l'impact")
		Expect.near(shadow.CFrame.Position.Y, 5.06, 0.01, "ombre au sol")
		-- Chute : de plus en plus bas, visible, traversable
		frameAt(born + 0.5 + 0.4)
		local y1 = body.CFrame.Position.Y
		frameAt(born + 0.5 + 0.9)
		local y2 = body.CFrame.Position.Y
		Expect.truthy(y1 < 34.71 and y2 < y1 and y2 > 5.3, `l'onglet tombe ({y1} puis {y2})`)
		Expect.equal(body.Transparency, 0, "visible en chute")
		Expect.equal(body.CanCollide, false, "pas solide en chute")
		-- Posé : plateforme solide en bas de la zone
		frameAt(born + 0.5 + 1.2 + 1)
		Expect.near(body.CFrame.Position.Y, 5.3, 0.01, "posé en bas de la zone")
		Expect.equal(body.CanCollide, true, "posé : solide")
		local slot = body.CFrame.Position
		-- Fermé
		frameAt(born + 5.2)
		Expect.equal(body.Transparency, 1, "fermé : invisible")
		Expect.equal(body.CanCollide, false, "fermé : traversable")
		-- Sûr debout sur l'onglet posé (aucun autre onglet ne tombe sur sa case)
		sim.T = born + 1.75
		placeFeet(slot + V3.new(0, 0.3, 0))
		runUntil(born + 4.6)
		Expect.equal(humanoid.Health, 100, "sûr sur l'onglet posé")
		-- Déterministe : le même onglet tue quelqu'un qui reste sous lui
		sim.T = born - 0.2
		table.clear(sim.Reports)
		placeFeet(V3.new(slot.X, 5, slot.Z))
		runUntil(born + 2)
		Expect.equal(humanoid.Health, 0, "l'onglet qui tombe tue")
		Expect.equal(sim.Reports[1], "ReportDeath:TabRain", "cause TabRain")
		Expect.truthy(sim.T > born + 0.5 + 0.8, "pas avant la fin de la chute (préavis)")
		clearAll()
	end,

	["Flood : le plan mortel monte régulièrement puis redescend"] = function()
		spawnCharacter()
		local flood = newTrap("Flood", V3.new(30, 1, 30), V3.new(0, 0, 0), { Rise = 20, Period = 10 })
		placeFeet(V3.new(0, 60, 0))
		frameAt(timeAt(10, 0, 0.05))
		Expect.near(flood.CFrame.Position.Y, 0, 1e-6, "en bas au début")
		local last = -1
		for i = 0, 10 do
			frameAt(timeAt(10, 0, 0.1 + 0.055 * i))
			local y = flood.CFrame.Position.Y
			Expect.truthy(y >= last - 1e-6, "monte sans redescendre")
			Expect.near(y, 20 * i / 10, 0.01, "montée régulière")
			last = y
		end
		frameAt(timeAt(10, 0, 0.7))
		Expect.near(flood.CFrame.Position.Y, 20, 1e-6, "en haut")
		frameAt(timeAt(10, 0, 0.9))
		Expect.between(flood.CFrame.Position.Y, 0.1, 19.9, "redescend")
		-- Préavis : la surface s'éclaircit en clignotant avant de monter
		local rise = timeAt(10, 0, 0.1)
		sim.T = rise - 0.75
		local flashed = false
		while sim.T < rise - 0.05 do
			stepFor(1 / 60, 60)
			flashed = flashed or flood.Color ~= Color3.fromRGB(240, 60, 90)
		end
		Expect.truthy(flashed, "flash avant la montée")
		-- Mortel quand il atteint le joueur (perché à y = 12)
		sim.T = timeAt(10, 0, 0.3)
		placeFeet(V3.new(0, 12, 0))
		runUntil(sim.T + 0.5)
		Expect.equal(humanoid.Health, 100, "pas encore atteint")
		table.clear(sim.Reports)
		runUntil(sim.T + 5)
		Expect.equal(humanoid.Health, 0, "rattrapé par la fuite mémoire")
		Expect.equal(sim.Reports[1], "ReportDeath:Flood", "cause Flood")
		clearAll()
	end,

	["Corrupt : damier texture manquante, alterne, inversé en CORRUPTION"] = function()
		spawnCharacter()
		local tile = newTrap(
			"Corrupt",
			V3.new(6, 1, 6),
			V3.new(0, 0, 0),
			{ Period = 4, Duty = 0.5 },
			{ Collide = true }
		)
		placeFeet(V3.new(0, 30, 0))
		frameAt(timeAt(4, 0, 0.25))
		Expect.equal(tile.CanCollide, true, "solide pendant Duty")
		local gui = rigPart("Corrupt", "MissingTexture")
		Expect.truthy(gui ~= nil and gui.Enabled, "damier affiché")
		local colors = {}
		for _, cell in gui:GetChildren() do
			if cell:IsA("Frame") then
				colors[cell.BackgroundColor3:ToHex()] = true
			end
		end
		Expect.truthy(colors["FF00DC"] and colors["121218"], "damier rose / noir")
		frameAt(timeAt(4, 0, 0.75))
		Expect.equal(tile.CanCollide, false, "traversable ensuite")
		Expect.near(tile.Transparency, 0.8, 1e-3, "fantôme")
		-- Préavis : clignote avant de devenir traversable, en restant solide
		local switch = timeAt(4, 0, 0.5)
		sim.T = switch - 0.75
		local seen = {}
		while sim.T < switch - 0.05 do
			stepFor(1 / 60, 60)
			seen[tile.Transparency] = true
			Expect.equal(tile.CanCollide, true, "solide pendant le préavis")
		end
		Expect.truthy(saw(seen, 0.8) and saw(seen, 0), "clignote avant la bascule")
		-- CORRUPTION : inversé
		local t = timeAt(4, 0, 0.25)
		setIncident(3, "Corruption", t - 1, t + 5)
		frameAt(t)
		Expect.equal(tile.CanCollide, false, "CORRUPTION : traversable pendant Duty")
		frameAt(t + 2)
		Expect.equal(tile.CanCollide, true, "CORRUPTION : solide hors Duty")
		local first = gui:GetChildren()
		local swapped = false
		for _, cell in first do
			if cell:IsA("Frame") and cell.LayoutOrder == 0 then
				swapped = cell.BackgroundColor3:ToHex() == "121218"
			end
		end
		Expect.truthy(swapped, "CORRUPTION : damier inversé")
		clearAll()
	end,

	["Defrag : coulisse de case en case (pause puis glissement) et transporte"] = function()
		spawnCharacter()
		local block = newTrap(
			"Defrag",
			V3.new(6, 1, 6),
			V3.new(0, 0, 0),
			{ Waypoints = "0,0,0;8,0,0;8,0,8", Step = 2 },
			{ Collide = true }
		)
		placeFeet(V3.new(0, 30, 0))
		local base = math.floor(sim.T / 6 + 2) * 6 -- début d'une boucle : case 1
		frameAt(base + 0.5)
		near(block.CFrame.Position, V3.new(0, 0, 0), 1e-6, "pause sur la case 1")
		frameAt(base + 2 + 1)
		near(block.CFrame.Position, V3.new(8, 0, 0), 1e-6, "pause sur la case 2")
		frameAt(base + 4 + 1)
		near(block.CFrame.Position, V3.new(8, 0, 8), 1e-6, "pause sur la case 3")
		frameAt(base + 4 + 1.6)
		local mid = block.CFrame.Position
		Expect.truthy(mid.Z > 0 and mid.Z < 8 and mid.X > 0 and mid.X < 8, "glisse vers la case 1")
		-- Transport pendant un glissement
		frameAt(base + 1.5)
		expectCarried(block, 0.5, "Defrag")
		clearAll()
	end,

	["DustBall : roule en boucle (pose déterministe), mortelle"] = function()
		spawnCharacter()
		local ball = newTrap(
			"DustBall",
			V3.new(4, 4, 4),
			V3.new(0, 2, 0),
			{ Waypoints = "0,0,0;20,0,0;20,0,20;0,0,20", Speed = 8 },
			{ Shape = Enum.PartType.Ball }
		)
		placeFeet(V3.new(0, 60, 0))
		local base = math.floor(sim.T / 10 + 2) * 10 -- boucle de 80 studs à 8 studs/s = 10 s
		frameAt(base + 1)
		near(ball.CFrame.Position, V3.new(8, 2, 0), 1e-4, "8 studs le long du 1er segment")
		local look = ball.CFrame.LookVector
		frameAt(base + 3.5)
		near(ball.CFrame.Position, V3.new(20, 2, 8), 1e-4, "sur le 2e segment")
		Expect.truthy((ball.CFrame.LookVector - look).Magnitude > 0.1, "elle roule (rotation)")
		table.clear(sim.Reports)
		sim.T = base
		placeFeet(V3.new(20, 0, 10))
		runUntil(base + 10)
		Expect.equal(humanoid.Health, 0, "écrasé par la boule")
		Expect.equal(sim.Reports[1], "ReportDeath:DustBall", "cause DustBall")
		clearAll()
	end,

	["Pendulum : balancier autour du pivot, mortel au passage"] = function()
		spawnCharacter()
		local pick = newTrap(
			"Pendulum",
			V3.new(2, 4, 2),
			V3.new(0, 5, 0),
			{ Axis = "Z", Amplitude = 60, Period = 4, Pivot = V3.new(0, 12, 0) }
		)
		placeFeet(V3.new(0, 80, 0))
		frameAt(timeAt(4, 0, 0))
		near(pick.CFrame.Position, V3.new(0, 5, 0), 1e-4, "en bas au début du cycle")
		frameAt(timeAt(4, 0, 0.25))
		local pivot = V3.new(0, 17, 0)
		near(
			pick.CFrame.Position,
			pivot + V3.new(12 * math.sin(math.rad(60)), -6, 0),
			1e-3,
			"60° à un quart de cycle"
		)
		Expect.near((pick.CFrame.Position - pivot).Magnitude, 12, 1e-3, "toujours à 12 studs du pivot")
		frameAt(timeAt(4, 0, 0.75))
		Expect.truthy(pick.CFrame.Position.X < -10, "de l'autre côté à trois quarts")
		table.clear(sim.Reports)
		sim.T = timeAt(4, 0, 0.3)
		placeFeet(V3.new(0, 2.2, 0))
		runUntil(sim.T + 4)
		Expect.equal(humanoid.Health, 0, "frappé par la pioche")
		Expect.equal(sim.Reports[1], "ReportDeath:Pendulum", "cause Pendulum")
		clearAll()
	end,

	["LagMover : avance par à-coups (immobile entre deux sauts) et transporte"] = function()
		spawnCharacter()
		local lag = newTrap(
			"LagMover",
			V3.new(6, 1, 6),
			V3.new(0, 0, 0),
			{ Offset = V3.new(20, 0, 0), Period = 5, Steps = 5 },
			{ Collide = true }
		)
		placeFeet(V3.new(0, 30, 0))
		local base = math.floor(sim.T / 5 + 2) * 5
		frameAt(base + 1.1)
		local a = lag.CFrame.Position
		frameAt(base + 1.7)
		near(lag.CFrame.Position, a, 1e-6, "immobile pendant le pas")
		local swing = 0.5 - 0.5 * math.cos(2 * math.pi / 5)
		near(a, V3.new(20 * swing, 0, 0), 1e-4, "position du 1er pas")
		frameAt(base + 2.1)
		Expect.truthy(lag.CFrame.Position.X > a.X + 1, "saut au pas suivant")
		frameAt(base + 1.85)
		expectCarried(lag, 0.5, "LagMover pendant un saut")
		clearAll()
	end,

	["Spinner : roue de chargement, patins à plat sur le cercle, transport"] = function()
		spawnCharacter()
		newTrap("Spinner", V3.new(4, 1, 4), V3.new(0, 10, 0), { Speed = 0.5, Count = 6, Ring = 10 })
		placeFeet(V3.new(0, 40, 0))
		local t = math.floor(sim.T) + 3
		frameAt(t)
		local rig = rigFolder:FindFirstChild("SpinnerRig")
		Expect.equal(#rig:GetChildren(), 6, "6 patins")
		local angle = (0.5 * t) % (2 * math.pi)
		for i = 1, 6 do
			local pad = rig:FindFirstChild(`Pad{i}`)
			local a = angle + 2 * math.pi * (i - 1) / 6
			near(pad.CFrame.Position, V3.new(10 * math.cos(a), 10, -10 * math.sin(a)), 1e-3, `patin {i} sur le cercle`)
			Expect.near(math.abs(pad.CFrame.RightVector.Y), 1, 1e-3, "disque couché (à plat)")
			Expect.equal(pad.CanCollide, true, "patin solide")
		end
		expectCarried(rig:FindFirstChild("Pad1"), 0.5, "Spinner")
		clearAll()
	end,

	["DeadPixels : la vague éteint les dalles l'une après l'autre (traversables)"] = function()
		spawnCharacter()
		local a = newTrap(
			"DeadPixels",
			V3.new(4, 1, 4),
			V3.new(0, 0, 0),
			{ Direction = V3.new(1, 0, 0), Speed = 12, Period = 3, Duty = 0.35 },
			{ Collide = true }
		)
		local b = newTrap(
			"DeadPixels",
			V3.new(4, 1, 4),
			V3.new(12, 0, 0),
			{ Direction = V3.new(1, 0, 0), Speed = 12, Period = 3, Duty = 0.35 },
			{ Collide = true }
		)
		placeFeet(V3.new(6, 30, 0))
		local base = math.floor(sim.T / 3 + 2) * 3
		frameAt(base + 0.3)
		Expect.equal(a.CanCollide, false, "pixel A mort")
		Expect.equal(b.CanCollide, true, "pixel B encore allumé")
		frameAt(base + 1.3)
		Expect.equal(a.CanCollide, true, "pixel A rallumé")
		Expect.equal(b.CanCollide, false, "pixel B mort (1 s plus tard : 12 studs à 12 studs/s)")
		frameAt(base + 2.2)
		Expect.equal(a.CanCollide, true, "A allumé")
		Expect.equal(b.CanCollide, true, "B allumé")
		-- Préavis : A grésille en restant solide pendant les 0,8 s avant de mourir
		sim.T = base + 3 - 0.75
		local seen = {}
		while sim.T < base + 3 - 0.05 do
			stepFor(1 / 60, 60)
			seen[a.Color:ToHex()] = true
			Expect.equal(a.CanCollide, true, "solide pendant le préavis")
		end
		Expect.truthy(seen["121218"] ~= nil, "grésille (noir) avant de mourir")
		clearAll()
	end,

	["LoadBridge : se remplit (avec blocage), plein, clignote, se vide ; transporte"] = function()
		spawnCharacter()
		local bridge = newTrap("LoadBridge", V3.new(32, 1, 6), V3.new(0, 0, 0), { Period = 10, Segments = 8 })
		placeFeet(V3.new(0, 30, 0))
		local base = math.floor(sim.T / 10 + 2) * 10
		frameAt(base + 6)
		local rig = rigFolder:FindFirstChild("LoadBridgeRig")
		for i = 1, 8 do
			local segment = rig:FindFirstChild(`Segment{i}`)
			Expect.equal(segment.CanCollide, true, `segment {i} plein`)
			near(segment.CFrame.Position, V3.new(-16 + 4 * (i - 0.5), 0, 0), 1e-3, `segment {i} à sa place`)
		end
		Expect.equal(bridge.CanCollide, false, "le cadre n'est pas solide")
		frameAt(base + 9.5)
		for i = 1, 8 do
			Expect.equal(rig:FindFirstChild(`Segment{i}`).CanCollide, false, `segment {i} vidé`)
		end
		-- Remplissage : de plus en plus de segments, avec un blocage « Ne répond pas »
		sim.T = base + 10
		local last, stalled = 0, false
		local label = rigPart("LoadBridge", "Progress"):FindFirstChildOfClass("TextLabel")
		while sim.T < base + 15.6 do
			stepFor(1 / 30, 30)
			local full = 0
			for i = 1, 8 do
				if rig:FindFirstChild(`Segment{i}`).CanCollide then
					full += 1
				end
			end
			Expect.truthy(full >= last, "le pont ne recule pas en se remplissant")
			last = full
			stalled = stalled or string.find(label.Text, "Ne répond pas", 1, true) ~= nil
		end
		Expect.equal(last, 8, "plein à la fin du remplissage")
		Expect.truthy(stalled, "le chargement bloque un moment")
		-- Préavis : clignote au moins 0,8 s avant de se vider
		sim.T = base + 10 + 9 - 0.78
		local seen = {}
		while sim.T < base + 10 + 8.95 do
			stepFor(1 / 60, 60)
			seen[rig:FindFirstChild("Segment1").Transparency] = true
		end
		Expect.truthy(saw(seen, 0.4) and saw(seen, 0), "clignote avant de se vider")
		clearAll()
		-- Pont mobile (Offset) : transporte le personnage posé sur un segment plein
		spawnCharacter()
		newTrap(
			"LoadBridge",
			V3.new(32, 1, 6),
			V3.new(0, 0, 0),
			{ Period = 10, Segments = 8, Offset = V3.new(0, 0, 20) }
		)
		placeFeet(V3.new(0, 30, 0))
		base = math.floor(sim.T / 10 + 2) * 10
		frameAt(base + 6.5)
		frameAt(base + 6.6)
		expectCarried(rigFolder:FindFirstChild("LoadBridgeRig"):FindFirstChild("Segment3"), 0.5, "LoadBridge mobile")
		clearAll()
	end,

	["Cursor : suit le joueur, verrouille ≥ 0,8 s avec un anneau rouge, puis clique"] = function()
		spawnCharacter()
		table.clear(cues)
		newTrap("Cursor", V3.new(1, 1, 1), V3.new(0, 10, 0), { Area = V3.new(40, 20, 40), Period = 4, Radius = 4 })
		local base = math.floor(sim.T / 4 + 2) * 4 -- suivi 2,3 s, visée 1 s, clic 0,25 s
		sim.T = base
		placeFeet(V3.new(5, 0, 5))
		runUntil(base + 2.2)
		local ring = rigPart("Cursor", "Ring")
		near(ring.CFrame.Position, V3.new(5, 0.1, 5), 0.05, "l'anneau suit le joueur")
		Expect.truthy(ring.Transparency < 1, "anneau visible")
		Expect.equal(humanoid.Health, 100, "vivant pendant le suivi")
		-- Visée : l'anneau devient rouge ; on note quand
		local redAt
		while humanoid.Health > 0 and sim.T < base + 4 do
			stepFor(1 / 60, 60)
			if not redAt and ring.Color:ToHex() == "F53C46" then
				redAt = sim.T
			end
		end
		Expect.equal(humanoid.Health, 0, "cliqué s'il reste dans l'anneau")
		Expect.truthy(redAt ~= nil, "anneau rouge avant le clic")
		Expect.truthy(sim.T - redAt >= 0.8, `préavis ≥ 0,8 s (obtenu {sim.T - redAt})`)
		Expect.equal(sim.Deaths[#sim.Deaths], "Cursor", "cause Cursor")
		Expect.truthy(table.find(cues, "Cursor:Warn") ~= nil, "signal sonore du verrouillage")
		-- On s'écarte pendant la visée : sauf
		spawnCharacter()
		base += 8
		sim.T = base
		placeFeet(V3.new(5, 0, 5))
		runUntil(base + 2.4)
		placeFeet(V3.new(15, 0, 5))
		runUntil(base + 3.9)
		Expect.equal(humanoid.Health, 100, "sorti de l'anneau pendant la visée : sauf")
		Expect.truthy(table.find(cues, "Cursor:Click") ~= nil, "signal sonore du clic")
		-- Hors de la zone : il ne vise personne
		base += 8
		sim.T = base
		placeFeet(V3.new(100, 0, 0))
		runUntil(base + 4)
		Expect.equal(humanoid.Health, 100, "hors zone : pas visé")
		clearAll()
	end,

	["FirewallWall : le mur avance, seuls les trous sont sûrs"] = function()
		spawnCharacter()
		local wall = newTrap(
			"FirewallWall",
			V3.new(20, 12, 1),
			V3.new(0, 6, 0),
			{ Offset = V3.new(0, 0, 30), Period = 8, Holes = "0,-2.5,6,7" }
		)
		placeFeet(V3.new(0, 60, 15))
		local base = math.floor(sim.T / 8 + 2) * 8
		frameAt(base + 4)
		near(wall.CFrame.Position, V3.new(0, 6, 30), 1e-4, "au bout de sa course à mi-cycle")
		Expect.equal(wall.LocalTransparencyModifier, 1, "racine cachée (briques client)")
		Expect.truthy(#rigFolder:FindFirstChild("FirewallWallRig"):GetChildren() >= 4, "briques + cadres")
		sim.T = base
		placeFeet(V3.new(0, 0, 15))
		runUntil(base + 8)
		Expect.equal(humanoid.Health, 100, "debout dans le trou : le mur passe")
		table.clear(sim.Reports)
		sim.T = base
		placeFeet(V3.new(7, 0, 15))
		runUntil(base + 8)
		Expect.equal(humanoid.Health, 0, "hors du trou : touché")
		Expect.equal(sim.Reports[1], "ReportDeath:FirewallWall", "cause FirewallWall")
		clearAll()
	end,

	["FREEZE fige les pièges du monde (sans saut à la reprise), pas ceux des autres mondes"] = function()
		spawnCharacter()
		local pick = newTrap(
			"Pendulum",
			V3.new(2, 4, 2),
			V3.new(0, 5, 0),
			{ Axis = "Z", Amplitude = 60, Period = 4, Pivot = V3.new(0, 12, 0) }
		)
		local mover = newTrap(
			"Mover",
			V3.new(6, 1, 6),
			V3.new(30, 0, 0),
			{ Offset = V3.new(0, 0, 20), Period = 5, Phase = 0 },
			{ Collide = true }
		)
		local other = newTrap(
			"Mover",
			V3.new(6, 1, 6),
			V3.new(60, 0, 0),
			{ Offset = V3.new(0, 0, 20), Period = 5, Phase = 0 },
			{ Collide = true, Parent = worlds[2] }
		)
		placeFeet(V3.new(30, 40, 0))
		local t0 = math.floor(sim.T / 20 + 2) * 20 + 0.3
		setIncident(3, "Freeze", t0, t0 + 6)
		frameAt(t0 + 1)
		local p1, m1, o1 = pick.CFrame, mover.CFrame.Position, other.CFrame.Position
		frameAt(t0 + 4)
		near(pick.CFrame.Position, p1.Position, 1e-6, "pioche figée")
		near(mover.CFrame.Position, m1, 1e-6, "Mover figé")
		Expect.truthy((other.CFrame.Position - o1).Magnitude > 0.1, "le monde 2 continue")
		-- Reprise : la pose à t0 + 6,5 est celle de t0 + 0,5 (le temps a été suspendu 6 s)
		frameAt(t0 + 6.5)
		local resumed = pick.CFrame.Position
		setIncident(3, "", 0, 0, 6) -- le serveur reporte la durée dans Offset
		frameAt(t0 + 6.5)
		near(pick.CFrame.Position, resumed, 1e-6, "aucun saut quand le serveur met à jour Offset")
		setIncident(3, "", 0, 0, 0)
		frameAt(t0 + 0.5)
		near(pick.CFrame.Position, resumed, 1e-6, "reprend là où il s'était arrêté")
		Expect.near(TrapClock.Compute(t0 + 6.5, "Freeze", t0, t0 + 6, 0), t0 + 0.5, 1e-9, "même horloge que TrapClock")
		clearAll()
	end,

	["LAG SPIKE : les pièges avancent par à-coups de 0,4 s"] = function()
		spawnCharacter()
		local pick = newTrap(
			"Pendulum",
			V3.new(2, 4, 2),
			V3.new(0, 5, 0),
			{ Axis = "Z", Amplitude = 60, Period = 4, Pivot = V3.new(0, 12, 0) }
		)
		placeFeet(V3.new(0, 40, 0))
		local t0 = math.floor(sim.T / 20 + 2) * 20 + 0.1
		setIncident(3, "Lag", t0, t0 + 7)
		frameAt(t0 + 0.05)
		local a = pick.CFrame.Position
		frameAt(t0 + 0.35)
		near(pick.CFrame.Position, a, 1e-6, "même pas de temps : immobile")
		frameAt(t0 + 0.45)
		Expect.truthy((pick.CFrame.Position - a).Magnitude > 0.1, "puis saut")
		setIncident(3, "", 0, 0, 0)
		frameAt(t0 + 0.4)
		local expected = pick.CFrame.Position
		setIncident(3, "Lag", t0, t0 + 7)
		frameAt(t0 + 0.7)
		near(pick.CFrame.Position, expected, 1e-6, "pose = pose de l'instant arrondi au pas")
		clearAll()
	end,

	["SURCHAUFFE : toutes les bouches Heat actives, vent × 2 (plafonné sous la marche)"] = function()
		spawnCharacter()
		newTrap("Heat", V3.new(4, 1, 4), V3.new(0, 0, 0), { Period = 4, Duty = 0.25, Phase = 0 })
		local t = timeAt(4, 0, 0.5)
		sim.T = t
		placeFeet(V3.new(0, -0.5, 0))
		runUntil(t + 0.8)
		Expect.equal(humanoid.Health, 100, "bouche éteinte : sauf")
		table.clear(sim.Reports)
		setIncident(3, "Overheat", t + 0.9, t + 8)
		runUntil(t + 1.2)
		Expect.equal(humanoid.Health, 0, "SURCHAUFFE : la bouche éteinte brûle")
		Expect.equal(sim.Reports[1], "ReportDeath:Heat", "cause Heat")
		clearAll()
		-- Vent
		spawnCharacter()
		newTrap("Wind", V3.new(20, 20, 20), V3.new(0, 10, 0), { Direction = V3.new(1, 0, 0), Strength = 6 })
		newTrap(
			"Wind",
			V3.new(20, 20, 20),
			V3.new(100, 10, 0),
			{ Direction = V3.new(1, 0, 0), Strength = 10 },
			{ Parent = worlds[3] }
		)
		local function drift(x: number): number
			placeFeet(V3.new(x, 5, 0))
			local before = feet().X
			stepFor(0.1, 10)
			return feet().X - before
		end
		Expect.near(drift(0), 0.6, 1e-6, "vent normal : 6 studs/s")
		local now = sim.T
		setIncident(3, "Overheat", now - 1, now + 10)
		Expect.near(drift(0), 1.2, 1e-6, "SURCHAUFFE : 12 studs/s")
		Expect.near(drift(100), 1.5, 1e-6, "SURCHAUFFE : plafonné à 15 studs/s")
		setIncident(3, "Freeze", now - 1, now + 10)
		Expect.near(drift(0), 0, 1e-6, "FREEZE : ventilateur arrêté")
		clearAll()
	end,

	["monde du piège : attribut World, sinon celui d'un ancêtre"] = function()
		spawnCharacter()
		local own = newTrap(
			"Mover",
			V3.new(6, 1, 6),
			V3.new(0, 0, 0),
			{ Offset = V3.new(0, 0, 20), Period = 5, World = 2 },
			{ Collide = true, Parent = worlds[3] }
		)
		local inherited = newTrap(
			"Mover",
			V3.new(6, 1, 6),
			V3.new(20, 0, 0),
			{ Offset = V3.new(0, 0, 20), Period = 5 },
			{ Collide = true, Parent = worlds[3] }
		)
		placeFeet(V3.new(10, 40, 0))
		local t0 = math.floor(sim.T / 20 + 2) * 20 + 0.3
		setIncident(2, "Freeze", t0, t0 + 6)
		frameAt(t0 + 1)
		local a, b = own.CFrame.Position, inherited.CFrame.Position
		frameAt(t0 + 2)
		near(own.CFrame.Position, a, 1e-6, "World = 2 sur la pièce : figé par le FREEZE du monde 2")
		Expect.truthy((inherited.CFrame.Position - b).Magnitude > 0.1, "ancêtre World3 : continue")
		clearAll()
	end,

	["performances : 20 pièges de chaque type v2 animés, habillage compris"] = function()
		-- On mesure : personne ne meurt (bouclier)
		local kinds = {
			{ "Powered", { Period = 4 } },
			{ "Corrupt", { Period = 4 } },
			{ "DeadPixels", { Direction = V3.new(1, 0, 0) } },
			{ "Defrag", { Waypoints = "0,0,0;6,0,0" } },
			{ "LagMover", { Offset = V3.new(8, 0, 0) } },
			{ "Pendulum", { Pivot = V3.new(0, 8, 0) } },
			{ "DustBall", { Waypoints = "0,0,0;10,0,0;10,0,10" } },
			{ "Surge", { Waypoints = "0,0,0;20,0,0" } },
			{ "Flood", { Rise = 10 } },
			{ "FirewallWall", { Offset = V3.new(0, 0, 10), Holes = "0,-1,4,6" } },
			{ "LoadBridge", { Segments = 6 } },
			{ "Spinner", { Count = 6 } },
			{ "TabRain", { Size = V3.new(18, 20, 14) } },
			{ "Cursor", { Area = V3.new(20, 10, 20) } },
		}
		local report, total = {}, 0
		for _, def in kinds do
			spawnCharacter()
			playerAttributes.Shielded = true
			for i = 1, 20 do
				local x, z = (i % 5) * 24 - 48, math.floor(i / 5) * 24 - 48
				newTrap(def[1], V3.new(10, 6, 4), V3.new(x, 0, z), def[2], { Collide = true })
			end
			placeFeet(V3.new(0, 3, 0))
			stepFor(0.2, 30) -- construit l'habillage
			local start = os.clock()
			stepFor(1, 30)
			local ms = (os.clock() - start) * 1000 / 30
			total += ms
			table.insert(report, `{def[1]} {string.format("%.2f", ms)}`)
			clearAll()
		end
		print(`    ms / image pour 20 pièges (Lune, sans rendu) : {table.concat(report, ", ")}`)
		Expect.truthy(total / #kinds < 2, "budget de simulation")
	end,
}
