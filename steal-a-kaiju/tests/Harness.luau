--!nocheck
-- Banc d'essai Lune : charge les modules du jeu hors de Roblox.
-- Reproduit l'arborescence Rojo (script.Parent.Config…) avec des nœuds virtuels,
-- fournit les types de données Roblox via @lune/roblox et quelques substituts
-- (Random, game:GetService minimal).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Harness = {}

-- Random déterministe (xorshift) compatible avec l'API Roblox utilisée.
local Random = {}
Random.__index = Random
function Random.new(seed: number?)
	local self = setmetatable({}, Random)
	self.state = math.floor(math.abs(seed or os.clock() * 1e6)) % 2147483647
	if self.state == 0 then
		self.state = 88172645
	end
	return self
end
function Random:_next(): number
	-- LCG de Park-Miller
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function Random:NextNumber(min: number?, max: number?): number
	local r = self:_next()
	if min and max then
		return min + (max - min) * r
	end
	return r
end
function Random:NextInteger(min: number, max: number): number
	return min + math.floor(self:_next() * (max - min + 1))
end

local services = {
	RunService = {
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
	},
}
local game = {
	GetService = function(_, name)
		return services[name] or {}
	end,
}

local function makeEnv(scriptNode, requireFn)
	return setmetatable({
		script = scriptNode,
		require = requireFn,
		game = game,
		Instance = roblox.Instance,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		Font = roblox.Font,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		ColorSequence = roblox.ColorSequence,
		Random = Random,
	}, { __index = getfenv(1) })
end

-- Nœud virtuel : répond à .Name, .Parent et à l'indexation d'un enfant.
local Node = {}
local nodeData = setmetatable({}, { __mode = "k" })

local function newNode(name: string, parent, path: string?, isDir: boolean)
	local node = {}
	nodeData[node] = { Name = name, Parent = parent, Path = path, IsDir = isDir, Children = {} }
	return setmetatable(node, Node)
end

Node.__index = function(self, key)
	local d = nodeData[self]
	if key == "Name" then
		return d.Name
	elseif key == "Parent" then
		return d.Parent
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(_, name)
			return d.Children[name]
		end
	end
	local child = d.Children[key]
	if child == nil then
		error("Harness: " .. d.Name .. "." .. tostring(key) .. " introuvable", 2)
	end
	return child
end

local function scan(dir: string, node)
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			local child = newNode(entry, node, full, true)
			nodeData[node].Children[entry] = child
			scan(full, child)
		elseif entry:match("%.luau$") and not entry:match("%.server%.luau$") and not entry:match("%.client%.luau$") then
			local name = entry:gsub("%.luau$", "")
			nodeData[node].Children[name] = newNode(name, node, full, false)
		end
	end
end

local cache = {}

local function requireNode(node)
	if cache[node] ~= nil then
		return cache[node]
	end
	local d = nodeData[node]
	assert(d and not d.IsDir, "Harness: require d'un nœud invalide")
	local source = fs.readFile(d.Path)
	local chunk = luau.load(source, { debugName = d.Path, environment = makeEnv(node, requireNode) })
	local result = chunk()
	cache[node] = result
	return result
end

-- Racine « Shared » (= ReplicatedStorage.Shared).
function Harness.Shared(root: string)
	local node = newNode("Shared", nil, root, true)
	scan(root, node)
	return setmetatable({}, {
		__index = function(_, key)
			return node[key]
		end,
	}),
		requireNode
end

Harness.Random = Random
Harness.roblox = roblox

-- Mini framework de tests
local results = { passed = 0, failed = 0, failures = {} }

function Harness.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, name .. " :: " .. tostring(err))
	end
end

function Harness.expect(cond: any, msg: string?)
	if not cond then
		error(msg or "échec de l'assertion", 2)
	end
end

function Harness.near(a: number, b: number, eps: number?, msg: string?)
	if math.abs(a - b) > (eps or 1e-6) then
		error((msg or "valeurs différentes") .. string.format(" (%s ≠ %s)", tostring(a), tostring(b)), 2)
	end
end

function Harness.report(): boolean
	print(string.format("\n%d tests réussis, %d échoués", results.passed, results.failed))
	for _, f in results.failures do
		print("  ✗ " .. f)
	end
	return results.failed == 0
end

return Harness
