--[[
	IsolatedTower : construit la tour (TowerBuilder.Build) avec un chargeur de modules À PART (cache
	séparé de RobloxShim : n'altère pas l'instance de ModelLibrary partagée par les autres specs),
	avec ou sans modèles 3D simulés (tests/lib/FakeModels.luau). Même environnement que tower.spec.
	Usage :
	    local built = IsolatedTower.Build({ Models = true })
	    built.Tower / built.Workspace / built.Load("src/...") / built.Warnings
	`Observe(ModelLibrary)` est appelé avant la construction (ex. envelopper Place pour l'inspecter).
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Shim = require("./RobloxShim")
local FakeModels = require("./FakeModels")

local IsolatedTower = {}

local Instance, Enum, V3 = roblox.Instance, roblox.Enum, roblox.Vector3

-- CFrame.lookAt de Lune pointe à l'opposé de Roblox (LookVector inversé) : on le corrige.
local function lookAt(at: any, target: any, up: any?): any
	local look = (target - at).Unit
	local right = look:Cross(up or V3.new(0, 1, 0)).Unit
	local trueUp = right:Cross(look)
	return roblox.CFrame.fromMatrix(at, right, trueUp, -look)
end
local CFrame = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })

export type Options = {
	Models: boolean?, -- installe les modèles simulés (tous, ou `Keys`)
	Keys: { string }?,
	Observe: ((ModelLibrary: any) -> ())?,
	-- Retouches de modules juste après leur chargement, par chemin (ex. neutraliser Tower/Bonus).
	Patch: { [string]: (module: any) -> () }?,
}

export type Built = {
	Tower: any,
	Workspace: any,
	Load: (path: string) -> any,
	Warnings: { string },
}

function IsolatedTower.Build(options: Options?): Built
	local opts: Options = options or {}
	local dataModel = Instance.new("DataModel")
	local workspace = dataModel:GetService("Workspace")
	local clientModels = Instance.new("Folder") -- ReplicatedStorage.ClientModels (ModelLibrary.Preload)
	clientModels.Name = "ClientModels"
	local warnings: { string } = {}
	local globals = {
		game = {
			GetService = function(_self: any, name: string): any
				if name == "Workspace" then
					return workspace
				elseif name == "ReplicatedStorage" then
					return {
						WaitForChild = function(_: any, _name: string)
							return Shim.Node("src/shared")
						end,
						FindFirstChild = function(_: any, name_: string): any
							return if name_ == "ClientModels" then clientModels else nil
						end,
					}
				elseif name == "CollectionService" then
					return {
						AddTag = function(_: any, instance: any, tag: string)
							instance:AddTag(tag)
						end,
					}
				elseif name == "InsertService" then
					return Shim.OfflineInsertService()
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
		UDim = roblox.UDim,
		Vector2 = roblox.Vector2,
		Font = roblox.Font,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		task = require("@lune/task"),
		warn = function(...: any)
			local parts = {}
			for _, value in { ... } do
				table.insert(parts, tostring(value))
			end
			table.insert(warnings, table.concat(parts, " "))
		end,
	}
	local cache: { [string]: any } = {}
	local function load(path: string): any
		if cache[path] ~= nil then
			return cache[path]
		end
		local env: { [string]: any } = { script = Shim.Node(path) }
		env.require = function(target: any)
			local target_ = if type(target) == "table" then rawget(target, "__path") else nil
			if target_ then
				return load(target_)
			end
			error("require non supporté : " .. tostring(target))
		end
		for key, value in globals do
			env[key] = value
		end
		local result = luau.load(fs.readFile(path), { debugName = path, environment = env })()
		cache[path] = result
		local fix = opts.Patch and opts.Patch[path]
		if fix then
			fix(result)
		end
		return result
	end
	local ModelLibrary = load("src/server/World/ModelLibrary.luau")
	if opts.Models then
		FakeModels.Install(ModelLibrary, opts.Keys)
	end
	if opts.Observe then
		opts.Observe(ModelLibrary)
	end
	local tower = load("src/server/World/TowerBuilder.luau").Build()
	return { Tower = tower, Workspace = workspace, Load = load, Warnings = warnings }
end

-- Boîte englobante (axes du monde) des BaseParts de `root` : coin min, coin max (nil si aucune).
function IsolatedTower.Bounds(root: any): (any, any)
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	local nodes = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(nodes, root)
	end
	for _, part in nodes do
		if part:IsA("BasePart") then
			local cf, size = part.CFrame, part.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
			local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
			local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
			local p = cf.Position
			x0, y0, z0 = math.min(x0, p.X - hx), math.min(y0, p.Y - hy), math.min(z0, p.Z - hz)
			x1, y1, z1 = math.max(x1, p.X + hx), math.max(y1, p.Y + hy), math.max(z1, p.Z + hz)
		end
	end
	if x0 > x1 then
		return nil, nil
	end
	return V3.new(x0, y0, z0), V3.new(x1, y1, z1)
end

return IsolatedTower
