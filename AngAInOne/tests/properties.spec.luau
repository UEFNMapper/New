--[[
	Validation statique des propriétés : les constructeurs New("Classe", { Prop = … })
	(client) et Build.Part/Decor/Neon/Cylinder({ Prop = … }) (serveur) affectent des
	propriétés dynamiquement, donc invisibles pour l'analyseur de types.
	Ce test vérifie chaque nom de propriété contre les définitions officielles de
	l'API Roblox (héritage compris). Définitions : .tooling/globalTypes.None.d.luau
	(téléchargées par scripts/verify.sh).
]]

local DEFS = ".tooling/globalTypes.None.d.luau"
if not Fs.isFile(DEFS) then
	return {
		["(ignoré : définitions Roblox absentes, lance scripts/verify.sh)"] = function() end,
	}
end

-- Classe -> { propriétés propres }, Classe -> parent
local own: { [string]: { [string]: boolean } } = {}
local parentOf: { [string]: string } = {}
local currentClass: string? = nil
for line in string.gmatch(Fs.readFile(DEFS), "[^\n]+") do
	local class, base = string.match(line, "^declare extern type (%w+) extends (%w+) with")
	if class then
		currentClass = class
		own[class] = own[class] or {}
		parentOf[class] = base
	elseif line == "end" then
		currentClass = nil
	elseif currentClass then
		local name = string.match(line, "^\t(%u%w*):")
		if name then
			own[currentClass][name] = true
		end
	end
end

local function hasProperty(class: string, prop: string): boolean
	local current: string? = class
	while current do
		local props = own[current]
		if props and props[prop] then
			return true
		end
		current = parentOf[current]
	end
	return false
end

local function listFiles(dir: string, out: { string }?): { string }
	local result = out or {}
	for _, name in Fs.readDir(dir) do
		local path = dir .. "/" .. name
		if Fs.isDir(path) then
			listFiles(path, result)
		elseif string.match(name, "%.luau$") and not string.find(path, "/Packages/", 1, true) then
			table.insert(result, path)
		end
	end
	return result
end

-- Clés de premier niveau d'une table littérale "{ ... }".
local function topLevelKeys(tableText: string): { string }
	local keys = {}
	local depth = 0
	local i = 1
	local body = string.sub(tableText, 2, -2)
	while i <= #body do
		local c = string.sub(body, i, i)
		if c == "{" or c == "(" or c == "[" then
			depth += 1
		elseif c == "}" or c == ")" or c == "]" then
			depth -= 1
		elseif c == '"' or c == "`" then
			local close = string.find(body, c, i + 1, true)
			i = close or #body
		elseif depth == 0 then
			local key = string.match(body, "^(%a[%w_]*)%s*=[^=]", i)
			local before = if i > 1 then string.sub(body, i - 1, i - 1) else ","
			if key and (before == "," or before == "{" or string.match(before, "%s")) then
				-- vérifie que c'est un début d'élément (après une virgule ou un saut de ligne)
				local prefix = string.sub(body, 1, i - 1)
				local lastSignificant = string.match(prefix, "([^%s])%s*$")
				if lastSignificant == nil or lastSignificant == "," then
					table.insert(keys, key)
				end
				i += #key
			end
		end
		i += 1
	end
	return keys
end

local IGNORED = { Parent = true, Tag = true, Tags = true, Round = true }

local problems: { string } = {}
local checked = 0

local function checkCall(path: string, class: string, tableText: string)
	if not own[class] then
		table.insert(problems, `{path} : classe inconnue "{class}"`)
		return
	end
	for _, key in topLevelKeys(tableText) do
		if not IGNORED[key] then
			checked += 1
			if not hasProperty(class, key) then
				table.insert(problems, `{path} : {class}.{key} n'existe pas`)
			end
		end
	end
end

for _, path in listFiles("src") do
	local source = Fs.readFile(path)
	-- New("Classe", { ... })
	for class, tableText in string.gmatch(source, 'New%(%s*"(%w+)"%s*,%s*(%b{})') do
		checkCall(path, class, tableText)
	end
	-- Build.Part / Decor / Neon / Cylinder ({ ... }) -> Part
	for tableText in string.gmatch(source, "Build%.%u%a+%((%b{})") do
		checkCall(path, "Part", tableText)
	end
end

return {
	["toutes les propriétés affectées existent dans l'API Roblox"] = function()
		Expect.truthy(
			checked > 300,
			`trop peu de propriétés vérifiées ({checked}) : le test ne trouve pas les appels`
		)
		if #problems > 0 then
			error(table.concat(problems, "\n    "))
		end
	end,
}
