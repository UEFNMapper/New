--[[
	RobloxShim : permet de charger dans Lune les ModuleScripts "purs" du jeu
	qui utilisent require(script.Parent.X), sans modifier leur code.
	Chaque dossier/fichier du projet devient un faux noeud d'instance.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Shim = {}

local nodeCache: { [string]: any } = {}

-- Index des fichiers construit à l'avance : les métaméthodes ne peuvent pas yield
-- (les fonctions de @lune/fs sont asynchrones).
local isDir: { [string]: boolean } = {}
local isFile: { [string]: boolean } = {}
local function scan(dir: string)
	isDir[dir] = true
	for _, name in fs.readDir(dir) do
		local full = dir .. "/" .. name
		if fs.isDir(full) then
			scan(full)
		else
			isFile[full] = true
		end
	end
end
scan("src")
local moduleCache: { [string]: any } = {}

local function parentPath(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or "."
end

local makeNode: (path: string) -> any

makeNode = function(path: string): any
	local cached = nodeCache[path]
	if cached then
		return cached
	end
	local node = setmetatable({ __path = path }, {
		__index = function(_self, key: string)
			if key == "Parent" then
				return makeNode(parentPath(path))
			end
			local base = string.gsub(path, "%.luau$", "")
			local dir = if isDir[path] then path else parentPath(base)
			local child = dir .. "/" .. key
			if isDir[child] then
				return makeNode(child)
			end
			if isFile[child .. ".luau"] then
				return makeNode(child .. ".luau")
			end
			error(`[RobloxShim] {key} introuvable dans {path}`)
		end,
		__tostring = function()
			return path
		end,
	})
	nodeCache[path] = node
	return node
end

function Shim.load(filePath: string): any
	if moduleCache[filePath] ~= nil then
		return moduleCache[filePath]
	end
	local source = fs.readFile(filePath)
	local env = {
		script = makeNode(filePath),
		require = function(target: any)
			if type(target) == "table" and rawget(target, "__path") then
				return Shim.load(rawget(target, "__path"))
			end
			error("[RobloxShim] require non supporté : " .. tostring(target))
		end,
	}
	local chunk = luau.load(source, { debugName = filePath, environment = env })
	local result = chunk()
	moduleCache[filePath] = result
	return result
end

return Shim
