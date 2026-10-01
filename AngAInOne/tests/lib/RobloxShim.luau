--[[
	RobloxShim : permet de charger dans Lune les ModuleScripts "purs" du jeu
	qui utilisent require(script.Parent.X), sans modifier leur code.
	Chaque dossier/fichier du projet devient un faux noeud d'instance.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Shim = {}

-- Globales supplémentaires injectées dans les modules chargés (ex. game, Instance, Enum
-- pour construire la map dans Lune). Remplies par les tests qui en ont besoin.
Shim.Globals = {} :: { [string]: any }

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

-- Faux noeud d'instance pour un dossier du projet (ex. "src/shared").
function Shim.Node(path: string): any
	return makeNode(path)
end

-- Faux InsertService HORS LIGNE : LoadAsset échoue toujours (pas de Roblox dans Lune). ModelLibrary.Preload
-- passe alors chaque modèle de Config/ModelAssets en décor de secours, comme avant l'import des IDs :
-- les specs qui construisent la tour testent toujours la même géométrie.
function Shim.OfflineInsertService(): any
	return {
		LoadAsset = function(_self: any, id: number): any
			error(`[RobloxShim] InsertService hors ligne : asset {id}`)
		end,
	}
end

function Shim.load(filePath: string): any
	if moduleCache[filePath] ~= nil then
		return moduleCache[filePath]
	end
	local source = fs.readFile(filePath)
	local env = {
		script = makeNode(filePath),
		-- Types de données Roblox (fournis par Lune) pour les modules de géométrie partagés.
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		require = function(target: any)
			if type(target) == "table" and rawget(target, "__path") then
				return Shim.load(rawget(target, "__path"))
			end
			error("[RobloxShim] require non supporté : " .. tostring(target))
		end,
	}
	for key, value in Shim.Globals do
		env[key] = value
	end
	local chunk = luau.load(source, { debugName = filePath, environment = env })
	local result = chunk()
	moduleCache[filePath] = result
	return result
end

return Shim
