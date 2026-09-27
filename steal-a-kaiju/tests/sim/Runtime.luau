--!nocheck
-- Mini-runtime Roblox pour exécuter le VRAI code serveur hors de Studio (Lune).
--  * Instances factices (propriétés libres, enfants, attributs, signaux)
--  * Services : Players, Workspace, ReplicatedStorage, RunService, Marketplace…
--  * Planificateur `task` à horloge virtuelle : on peut simuler des heures
--    de jeu en quelques secondes.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Runtime = {}

-- API Roblox officielle (classes, propriétés, méthodes, événements)
local serde = require("@lune/serde")
local API = serde.decode("json", fs.readFile("tests/sim/api.json"))
Runtime.Validate = true
Runtime.ApiIssues = {}
local function apiFind(className: string, kind: string, member: string): string?
	local c = API[className]
	while c do
		local v
		if kind == "props" then
			v = c.props[member]
		else
			v = table.find(c[kind], member) and "ok" or nil
		end
		if v then
			return v
		end
		c = c.super and API[c.super]
	end
	return nil
end
Runtime.ApiFind = apiFind
local function apiIssue(msg: string)
	if not Runtime.ApiIssues[msg] then
		Runtime.ApiIssues[msg] = true
		local trace = debug.traceback("", 3)
		local where = trace:match('%[string "(src/[^"]+)"%]:(%d+)') and (trace:match('%[string "(src/[^"]+)"%]') .. ":" .. trace:match('%[string "src/[^"]+"%]:(%d+)')) or "?"
		table.insert(Runtime.Errors, "API ROBLOX : " .. msg .. " (" .. where .. ")")
	end
end

----------------------------------------------------------------------------
-- Horloge virtuelle + planificateur
----------------------------------------------------------------------------

local EPOCH = 1790000000
local clock = 0
local queue = {} -- { at, seq, co, args }
local seq = 0
Runtime.Errors = {}

local function schedule(at: number, co: thread, ...)
	seq += 1
	table.insert(queue, { at = at, seq = seq, co = co, args = table.pack(...) })
end

local function resume(co: thread, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		local msg = tostring(err) .. "\n" .. debug.traceback(co)
		table.insert(Runtime.Errors, msg)
		print("[ERREUR] " .. msg)
	end
end

local task = {}
function task.spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.defer(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(clock, co, ...)
	return co
end
function task.delay(t, fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(clock + (t or 0), co, ...)
	return co
end
function task.wait(t)
	local co = coroutine.running()
	local d = math.max(t or 0.03, 0.001)
	schedule(clock + d, co, d)
	return coroutine.yield()
end
function task.cancel(co)
	for i = #queue, 1, -1 do
		if queue[i].co == co then
			table.remove(queue, i)
		end
	end
end

-- Avance l'horloge de `seconds`, en exécutant tout ce qui est prévu.
function Runtime.Advance(seconds: number)
	local target = clock + seconds
	while true do
		local best, bi = nil, nil
		for i, item in queue do
			if item.at <= target and (not best or item.at < best.at or (item.at == best.at and item.seq < best.seq)) then
				best, bi = item, i
			end
		end
		if not best then
			break
		end
		table.remove(queue, bi)
		clock = math.max(clock, best.at)
		if coroutine.status(best.co) == "suspended" then
			resume(best.co, table.unpack(best.args, 1, best.args.n))
		end
	end
	clock = target
end

function Runtime.Now(): number
	return clock
end

local vos = setmetatable({
	clock = function()
		return clock
	end,
	time = function(t)
		if t then
			return os.time(t)
		end
		return math.floor(EPOCH + clock)
	end,
}, { __index = os })

----------------------------------------------------------------------------
-- Signaux
----------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
	local conn = { Connected = true }
	conn.fn = fn
	function conn.Disconnect(c)
		c.Connected = false
	end
	table.insert(self.handlers, conn)
	return conn
end
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Fire(...)
	for _, c in table.clone(self.handlers) do
		if c.Connected then
			task.spawn(c.fn, ...)
		end
	end
end
function Signal:Wait()
	local co = coroutine.running()
	self:Once(function(...)
		task.spawn(co, ...)
	end)
	return coroutine.yield()
end
Runtime.Signal = Signal
Runtime.Heartbeat = Signal.new()

----------------------------------------------------------------------------
-- Instances factices
----------------------------------------------------------------------------

local SUPER = {
	Part = "BasePart",
	WedgePart = "BasePart",
	CornerWedgePart = "BasePart",
	SpawnLocation = "Part",
	MeshPart = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	PVInstance = "Instance",
	Folder = "Instance",
	Tool = "BackpackItem",
	BackpackItem = "Instance",
	RemoteEvent = "Instance",
	RemoteFunction = "Instance",
	ScreenGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	LayerCollector = "GuiBase2d",
	TextLabel = "GuiObject",
	Frame = "GuiObject",
	GuiObject = "GuiBase2d",
	GuiBase2d = "Instance",
	StringValue = "ValueBase",
	IntValue = "ValueBase",
	ValueBase = "Instance",
	Humanoid = "Instance",
	Player = "Instance",
	Backpack = "Instance",
	LuaSourceContainer = "Instance",
	ModuleScript = "LuaSourceContainer",
	Script = "LuaSourceContainer",
	ParticleEmitter = "Instance",
	PointLight = "Light",
	Light = "Instance",
}

local EVENT_NAMES = {
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	AncestryChanged = true,
	AttributeChanged = true,
	Changed = true,
	Touched = true,
	TouchEnded = true,
	Died = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Activated = true,
	Heartbeat = true,
	Stepped = true,
	RenderStepped = true,
	PromptGamePassPurchaseFinished = true,
	PromptProductPurchaseFinished = true,
	Destroying = true,
	Triggered = true,
	PromptButtonHoldBegan = true,
	PromptButtonHoldEnded = true,
}

local Instance = {}
local data = setmetatable({}, { __mode = "k" })
local DEFAULTS = {} -- valeurs lues quand une propriété n'a jamais été écrite (mode client)
Runtime._defaults = DEFAULTS
Runtime._events = EVENT_NAMES
Runtime.Created = 0

local function isA(className: string, target: string): boolean
	local c = className
	while c do
		if c == target then
			return true
		end
		c = SUPER[c]
	end
	return target == "Instance"
end

local methods = {}

local function new(className: string, props: any?)
	local self = {}
	local d = {
		ClassName = className,
		Name = className,
		Parent = nil,
		Children = {},
		Attributes = {},
		AttrSignals = {},
		Signals = {},
		Props = {},
		PropSignals = {},
	}
	data[self] = d
	setmetatable(self, Instance)
	Runtime.Created += 1
	if isA(className, "BasePart") then
		d.Props.CFrame = roblox.CFrame.new()
		d.Props.Size = roblox.Vector3.new(4, 1, 2)
		d.Props.Transparency = 0
		d.Props.Anchored = false
	end
	if props then
		for k, v in props do
			self[k] = v
		end
	end
	return self
end
Runtime.NewInstance = new

Instance.__index = function(self, key)
	local d = data[self]
	if key == "ClassName" or key == "Name" or key == "Parent" then
		return d[key]
	end
	if methods[key] then
		if Runtime.Validate and API[d.ClassName] and string.sub(key, 1, 1) ~= "_" and not apiFind(d.ClassName, "methods", key) then
			apiIssue(("méthode inexistante %s:%s()"):format(d.ClassName, key))
		end
		return methods[key]
	end
	if key == "Position" and d.Props.CFrame and isA(d.ClassName, "BasePart") then
		return d.Props.CFrame.Position
	end
	if key == "AssemblyLinearVelocity" then
		return roblox.Vector3.new()
	end
	local v = d.Props[key]
	if v ~= nil then
		return v
	end
	if EVENT_NAMES[key] then
		if Runtime.Validate and API[d.ClassName] and not apiFind(d.ClassName, "events", key) and not apiFind(d.ClassName, "props", key) then
			apiIssue(("événement inexistant %s.%s"):format(d.ClassName, key))
		end
		local s = d.Signals[key]
		if not s then
			s = Signal.new()
			d.Signals[key] = s
		end
		return s
	end
	-- enfant du même nom
	for _, c in d.Children do
		if data[c].Name == key then
			return c
		end
	end
	local default = DEFAULTS[key]
	if default ~= nil then
		if type(default) == "function" then
			return default(self, d)
		end
		return default
	end
	return nil
end

Instance.__newindex = function(self, key, value)
	local d = data[self]
	if key == "Parent" then
		methods._setParent(self, value)
		return
	elseif key == "Name" then
		d.Name = value
		return
	elseif key == "Position" and typeof(value) == "Vector3" and isA(d.ClassName, "BasePart") then
		local cf = d.Props.CFrame or roblox.CFrame.new()
		d.Props.CFrame = roblox.CFrame.new(value) * cf.Rotation
		return
	end
	if Runtime.Validate and API[d.ClassName] and type(key) == "string" then
		local access = apiFind(d.ClassName, "props", key)
		if not access then
			apiIssue(("propriété inexistante %s.%s"):format(d.ClassName, key))
		elseif access == "r" then
			apiIssue(("propriété en lecture seule %s.%s"):format(d.ClassName, key))
		end
	end
	d.Props[key] = value
	local s = d.PropSignals[key]
	if s then
		s:Fire()
	end
end

Instance.__tostring = function(self)
	return data[self].Name
end

function methods._setParent(self, parent)
	local d = data[self]
	local old = d.Parent
	if old == parent then
		return
	end
	if old then
		local od = data[old]
		local i = table.find(od.Children, self)
		if i then
			table.remove(od.Children, i)
		end
		if od.Signals.ChildRemoved then
			od.Signals.ChildRemoved:Fire(self)
		end
	end
	d.Parent = parent
	if parent then
		table.insert(data[parent].Children, self)
		local pd = data[parent]
		if pd.Signals.ChildAdded then
			pd.Signals.ChildAdded:Fire(self)
		end
	end
end

function methods.IsA(self, className)
	return isA(data[self].ClassName, className)
end
function methods.GetChildren(self)
	return table.clone(data[self].Children)
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(inst)
		for _, c in data[inst].Children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in data[self].Children do
		if data[c].Name == name then
			return c
		end
	end
	if recursive then
		for _, c in data[self].Children do
			local r = methods.FindFirstChild(c, name, true)
			if r then
				return r
			end
		end
	end
	return nil
end
function methods.WaitForChild(self, name, timeout)
	local deadline = clock + (timeout or 5)
	while clock <= deadline do
		local c = methods.FindFirstChild(self, name)
		if c then
			return c
		end
		task.wait(0.05)
	end
	if not timeout then
		error("WaitForChild infini : " .. data[self].Name .. "." .. name)
	end
	return nil
end
function methods.FindFirstChildOfClass(self, className)
	for _, c in data[self].Children do
		if data[c].ClassName == className then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, className)
	for _, c in data[self].Children do
		if isA(data[c].ClassName, className) then
			return c
		end
	end
	return nil
end
function methods.FindFirstAncestorOfClass(self, className)
	local p = data[self].Parent
	while p do
		if data[p].ClassName == className then
			return p
		end
		p = data[p].Parent
	end
	return nil
end
function methods.IsDescendantOf(self, other)
	local p = data[self].Parent
	while p do
		if p == other then
			return true
		end
		p = data[p].Parent
	end
	return false
end
function methods.Destroy(self)
	for _, c in table.clone(data[self].Children) do
		methods.Destroy(c)
	end
	local d = data[self]
	if d.Signals.Destroying then
		d.Signals.Destroying:Fire()
	end
	methods._setParent(self, nil)
end
function methods.ClearAllChildren(self)
	for _, c in table.clone(data[self].Children) do
		methods.Destroy(c)
	end
end
function methods.Clone(self)
	local d = data[self]
	local copy = new(d.ClassName)
	local cd = data[copy]
	cd.Name = d.Name
	for k, v in d.Props do
		cd.Props[k] = v
	end
	for k, v in d.Attributes do
		cd.Attributes[k] = v
	end
	for _, c in d.Children do
		methods._setParent(methods.Clone(c), copy)
	end
	return copy
end
function methods.SetAttribute(self, name, value)
	local d = data[self]
	if d.Attributes[name] == value then
		return
	end
	d.Attributes[name] = value
	if d.AttrSignals[name] then
		d.AttrSignals[name]:Fire()
	end
	if d.Signals.AttributeChanged then
		d.Signals.AttributeChanged:Fire(name)
	end
end
function methods.GetAttribute(self, name)
	return data[self].Attributes[name]
end
function methods.GetAttributes(self)
	return table.clone(data[self].Attributes)
end
function methods.GetAttributeChangedSignal(self, name)
	local d = data[self]
	d.AttrSignals[name] = d.AttrSignals[name] or Signal.new()
	return d.AttrSignals[name]
end
function methods.GetPropertyChangedSignal(self, name)
	local d = data[self]
	d.PropSignals[name] = d.PropSignals[name] or Signal.new()
	return d.PropSignals[name]
end
function methods.PivotTo(self, cf)
	local d = data[self]
	if d.ClassName == "Model" then
		local root = d.Props.PrimaryPart or methods.FindFirstChild(self, "HumanoidRootPart")
		if root then
			root.CFrame = cf
		end
	else
		self.CFrame = cf
	end
end
function methods.GetPivot(self)
	local d = data[self]
	if d.ClassName == "Model" then
		local root = d.Props.PrimaryPart or methods.FindFirstChild(self, "HumanoidRootPart")
		return if root then root.CFrame else roblox.CFrame.new()
	end
	return self.CFrame
end
function methods.GetFullName(self)
	local names = {}
	local cur = self
	while cur do
		table.insert(names, 1, data[cur].Name)
		cur = data[cur].Parent
	end
	return table.concat(names, ".")
end
-- Méthodes génériques sans effet utiles au serveur
for _, name in { "FillBlock", "FillCylinder", "FillBall", "SetMaterialColor", "Play", "Stop", "Emit", "AddUserId", "Kick", "LoadCharacter", "BreakJoints", "ChangeState", "MoveTo", "UnequipTools" } do
	methods[name] = function(self, ...)
		if name == "Kick" then
			data[self].Props.Kicked = (...) or true
			print("[KICK] " .. tostring(data[self].Name) .. " : " .. tostring(...))
		end
	end
end

-- Journal de ce que le serveur envoie aux clients
Runtime.ClientLog = {} -- { { player = Player|"all", remote = nom, args = {...} } }
function methods.FireClient(self, player, ...)
	table.insert(Runtime.ClientLog, { player = player, remote = data[self].Name, args = table.pack(...) })
end
function methods.FireAllClients(self, ...)
	table.insert(Runtime.ClientLog, { player = "all", remote = data[self].Name, args = table.pack(...) })
end

Runtime._methods = methods
Runtime._isA = isA

Runtime.Data = function(inst)
	return data[inst]
end

----------------------------------------------------------------------------
-- Services
----------------------------------------------------------------------------

local game = new("DataModel")
data[game].Name = "game"
Runtime.game = game

local function service(name: string, className: string?)
	local s = new(className or name)
	data[s].Name = name
	methods._setParent(s, game)
	return s
end

local Workspace = service("Workspace")
local terrain = new("Terrain")
data[terrain].Name = "Terrain"
methods._setParent(terrain, Workspace)
data[Workspace].Props.Terrain = terrain
data[Workspace].Props.CurrentCamera = nil
methods.GetServerTimeNow = function()
	return EPOCH + clock
end
local Players = service("Players")
local ReplicatedStorage = service("ReplicatedStorage")
local ServerScriptService = service("ServerScriptService")
local Lighting = service("Lighting")
local RunService = service("RunService")
local MarketplaceService = service("MarketplaceService")
local PolicyService = service("PolicyService")
local DataStoreService = service("DataStoreService")
local HttpService = service("HttpService")
local MessagingService = service("MessagingService")
local TextChatService = service("TextChatService")
local GroupService = service("GroupService")
service("SoundService")
service("StarterPlayer")
service("ReplicatedFirst")
service("ServerStorage")
service("BadgeService")

data[RunService].Props.Heartbeat = Runtime.Heartbeat
data[RunService].Props.IsServer = function()
	return true
end
data[RunService].Props.IsClient = function()
	return false
end
data[RunService].Props.IsStudio = function()
	return true
end

data[MarketplaceService].Props.UserOwnsGamePassAsync = function()
	return false
end
data[MarketplaceService].Props.PromptGamePassPurchase = function() end
data[MarketplaceService].Props.PromptProductPurchase = function() end
Runtime.PaidRandomRestricted = false
data[PolicyService].Props.GetPolicyInfoForPlayerAsync = function()
	return { ArePaidRandomItemsRestricted = Runtime.PaidRandomRestricted, IsPaidItemTradingAllowed = true }
end
local ordered = {}
data[DataStoreService].Props.GetOrderedDataStore = function(_, name)
	ordered[name] = ordered[name] or {}
	local store = ordered[name]
	return {
		SetAsync = function(_, key, value)
			store[key] = value
		end,
		GetSortedAsync = function(_, ascending, pageSize)
			local list = {}
			for k, v in store do
				table.insert(list, { key = k, value = v })
			end
			table.sort(list, function(a, b)
				return if ascending then a.value < b.value else a.value > b.value
			end)
			local page = {}
			for i = 1, math.min(pageSize, #list) do
				page[i] = list[i]
			end
			return {
				GetCurrentPage = function()
					return page
				end,
			}
		end,
	}
end

function methods.GetService(self, name)
	local s = methods.FindFirstChild(game, name)
	if not s then
		s = service(name)
	end
	return s
end
data[game].Props.IsLoaded = function()
	return true
end

-- Players
local userIdCounter = 1000
data[Players].Props.GetPlayers = function()
	local list = {}
	for _, c in data[Players].Children do
		if data[c].ClassName == "Player" then
			table.insert(list, c)
		end
	end
	return list
end
data[Players].Props.GetPlayerByUserId = function(_, id)
	for _, c in data[Players].Children do
		if data[c].ClassName == "Player" and c.UserId == id then
			return c
		end
	end
	return nil
end
data[Players].Props.GetPlayerFromCharacter = function(_, model)
	for _, c in data[Players].Children do
		if data[c].ClassName == "Player" and c.Character == model then
			return c
		end
	end
	return nil
end
data[Players].Props.GetNameFromUserIdAsync = function(_, id)
	return "User" .. id
end

local function raw(inst, key, value)
	data[inst].Props[key] = value
end
Runtime.Raw = raw

local function makeCharacter(player)
	local character = new("Model")
	character.Name = player.Name
	local root = new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = roblox.CFrame.new(0, 5, 0)
	methods._setParent(root, character)
	local head = new("Part")
	head.Name = "Head"
	methods._setParent(head, character)
	local humanoid = new("Humanoid")
	humanoid.Name = "Humanoid"
	raw(humanoid, "Health", 100)
	humanoid.WalkSpeed = 16
	methods._setParent(humanoid, character)
	character.PrimaryPart = root
	methods._setParent(character, Workspace)
	return character
end

-- Fait rejoindre un joueur factice. Renvoie le Player.
function Runtime.AddPlayer(name: string, userId: number?)
	userIdCounter += 1
	local player = new("Player")
	player.Name = name
	raw(player, "UserId", userId or userIdCounter)
	raw(player, "DisplayName", name)
	raw(player, "MembershipType", roblox.Enum.MembershipType.None)
	raw(player, "IsFriendsWith", function()
		return false
	end)
	raw(player, "IsInGroupAsync", function()
		return false
	end)
	local backpack = new("Backpack")
	backpack.Name = "Backpack"
	methods._setParent(backpack, player)
	methods._setParent(player, Players)
	data[Players].Signals.PlayerAdded = data[Players].Signals.PlayerAdded or Signal.new()
	data[Players].Signals.PlayerAdded:Fire(player)
	-- personnage
	task.defer(function()
		local character = makeCharacter(player)
		raw(player, "Character", character)
		data[player].Signals.CharacterAdded = data[player].Signals.CharacterAdded or Signal.new()
		data[player].Signals.CharacterAdded:Fire(character)
	end)
	return player
end

function Runtime.RemovePlayer(player)
	data[Players].Signals.PlayerRemoving = data[Players].Signals.PlayerRemoving or Signal.new()
	data[Players].Signals.PlayerRemoving:Fire(player)
	task.defer(function()
		methods._setParent(player, nil)
	end)
end

-- Téléporte le personnage d'un joueur.
function Runtime.MoveTo(player, position)
	local character = player.Character
	if character then
		local root = methods.FindFirstChild(character, "HumanoidRootPart")
		root.CFrame = roblox.CFrame.new(position)
	end
end

----------------------------------------------------------------------------
-- Chargement des scripts depuis src/
----------------------------------------------------------------------------

local sources = {} -- ModuleScript/Script factice -> chemin
local texts = {} -- chemin -> source
local cache = {}

local globals
local function requireModuleProxy(m)
	return Runtime._require(m)
end

-- Lune intercepte `require` (asynchrone) : on le renomme dans les sources simulées.
local function prepare(source: string): string
	return (("\n" .. source):gsub("([^%w_%.:])require(%s*%()", "%1__simRequire%2"))
end

local function envFor(script)
	local env = { script = script, __simRequire = requireModuleProxy }
	for k, v in globals do
		env[k] = v
	end
	return setmetatable(env, { __index = getfenv(1) })
end

local function requireModule(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local override = Runtime.Overrides[methods.GetFullName(module)]
	if override then
		cache[module] = override
		return override
	end
	local path = sources[module]
	if not path then
		error("require d'un module inconnu : " .. tostring(module))
	end
	local chunk = luau.load(prepare(texts[path]), { debugName = path, environment = envFor(module) })
	local result = chunk()
	cache[module] = result
	return result
end

Runtime.Overrides = {}
Runtime._require = requireModule

local function mount(dir: string, parent)
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			local folder = new("Folder")
			folder.Name = entry
			methods._setParent(folder, parent)
			mount(full, folder)
		elseif entry:match("%.luau$") then
			local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
			local class = if entry:match("%.server%.luau$") then "Script" elseif entry:match("%.client%.luau$") then "LocalScript" else "ModuleScript"
			local inst = new(class)
			inst.Name = name
			sources[inst] = full
			texts[full] = fs.readFile(full) -- lu maintenant : fs.readFile cède la main au planificateur de Lune
			methods._setParent(inst, parent)
		end
	end
end

function Runtime.Mount(dir: string, parent, name: string)
	local folder = new("Folder")
	folder.Name = name
	methods._setParent(folder, parent)
	mount(dir, folder)
	return folder
end

function Runtime.RunScript(script)
	local path = sources[script]
	local chunk = luau.load(prepare(texts[path]), { debugName = path, environment = envFor(script) })
	task.spawn(chunk)
end

-- Lune inverse CFrame.lookAt par rapport à Roblox : version fidèle.
local function lookAt(at, target, up)
	local forward = target - at
	if forward.Magnitude < 1e-6 then
		return roblox.CFrame.new(at)
	end
	forward = forward.Unit
	local upVec = up or roblox.Vector3.new(0, 1, 0)
	local right = forward:Cross(upVec)
	if right.Magnitude < 1e-6 then
		right = forward:Cross(roblox.Vector3.new(0, 0, 1))
	end
	right = right.Unit
	local realUp = right:Cross(forward)
	return roblox.CFrame.fromMatrix(at, right, realUp, -forward)
end
local CFrameProxy = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local args = table.pack(...)
		if args.n == 2 and typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
			return lookAt(args[1], args[2])
		end
		return roblox.CFrame.new(...)
	end,
}, { __index = roblox.CFrame })
Runtime.CFrame = CFrameProxy

globals = setmetatable({
	game = game,
	workspace = Workspace,
	Workspace = Workspace,
	task = task,
	os = vos,
	require = requireModule,
	Instance = { new = new },
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = CFrameProxy,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	Font = roblox.Font,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	Random = nil, -- rempli par l'appelant
	warn = function(...)
		print("[warn]", ...)
	end,
	typeof = function(v)
		if type(v) == "table" and data[v] then
			return "Instance"
		end
		return typeof(v)
	end,
}, { __index = getfenv(1) })

Runtime.Globals = globals
Runtime.task = task
Runtime.Services = {
	Workspace = Workspace,
	Players = Players,
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	MarketplaceService = MarketplaceService,
	Lighting = Lighting,
	HttpService = HttpService,
	MessagingService = MessagingService,
	TextChatService = TextChatService,
	GroupService = GroupService,
}

return Runtime
