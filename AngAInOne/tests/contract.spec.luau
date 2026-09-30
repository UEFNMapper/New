--[[
	Contrat client <-> serveur, vérifié par lecture du code source :
	- chaque Net.Fire("X", ...) du client correspond à une remote déclarée ET gérée
	  par le serveur (RemoteGuard.On("X")) avec le même nombre d'arguments ;
	- chaque remote déclarée est bien utilisée ;
	- chaque champ de l'état lu par le client (state.X) est envoyé par StateService.
]]

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

local function readAll(dir: string): { [string]: string }
	local sources = {}
	for _, path in listFiles(dir) do
		sources[path] = Fs.readFile(path)
	end
	return sources
end

local client = readAll("src/client")
local server = readAll("src/server")
local remotesSource = Fs.readFile("src/shared/Net/Remotes.luau")

-- Découpe les arguments de premier niveau d'un appel (gère parenthèses/accolades imbriquées).
local function countArgs(argText: string): number
	local depth, count, any = 0, 0, false
	-- Ignore une virgule finale ("{ a, b, }" = 2 arguments).
	argText = string.gsub(argText, ",%s*$", "")
	for i = 1, #argText do
		local c = string.sub(argText, i, i)
		if c == "(" or c == "{" or c == "[" then
			depth += 1
		elseif c == ")" or c == "}" or c == "]" then
			depth -= 1
		elseif c == "," and depth == 0 then
			count += 1
		end
		if not string.match(c, "%s") then
			any = true
		end
	end
	return if any then count + 1 else 0
end

-- Extrait le contenu entre la parenthèse ouvrante à `start` et sa fermante.
local function balanced(text: string, start: number): string
	local depth = 0
	for i = start, #text do
		local c = string.sub(text, i, i)
		if c == "(" then
			depth += 1
		elseif c == ")" then
			depth -= 1
			if depth == 0 then
				return string.sub(text, start + 1, i - 1)
			end
		end
	end
	return ""
end

local declared: { [string]: string } = {}
for section, body in string.gmatch(remotesSource, "local (%u[%u_]+) = (%b{})") do
	-- Uniquement les entrées de liste (une chaîne en début de ligne), pas les commentaires.
	local pattern = if string.find(body, "\n") then '\n%s*"(%w+)",' else '"(%w+)"'
	for name in string.gmatch(body, pattern) do
		declared[name] = section
	end
end

-- Serveur : RemoteGuard.On("Nom", { ... Args = { a, b } }, handler)
local guarded: { [string]: number } = {}
for _, source in server do
	local position = 1
	while true do
		local s, e, name = string.find(source, 'RemoteGuard%.On%(%s*"(%w+)"', position)
		if not s then
			break
		end
		local call = balanced(source, s + #"RemoteGuard.On")
		local argsBody = string.match(call, "Args%s*=%s*(%b{})") or "{}"
		guarded[name] = countArgs(string.sub(argsBody, 2, -2))
		position = e + 1
	end
end

-- Client : Net.Fire("Nom", a, b)
local fired: { { Name: string, Args: number, File: string } } = {}
for path, source in client do
	local position = 1
	while true do
		local s, e, name = string.find(source, 'Net%.Fire%(%s*"(%w+)"', position)
		if not s then
			break
		end
		local call = balanced(source, s + #"Net.Fire")
		table.insert(fired, { Name = name, Args = countArgs(call) - 1, File = path })
		position = e + 1
	end
end

return {
	["chaque requête client est déclarée, gardée, avec le bon nombre d'arguments"] = function()
		Expect.truthy(#fired > 10, "le test doit trouver des Net.Fire")
		for _, call in fired do
			Expect.equal(
				declared[call.Name],
				"CLIENT_TO_SERVER",
				`{call.Name} déclarée côté client->serveur ({call.File})`
			)
			Expect.truthy(guarded[call.Name] ~= nil, `{call.Name} gérée par RemoteGuard.On ({call.File})`)
			Expect.equal(call.Args, guarded[call.Name], `{call.Name} : nombre d'arguments ({call.File})`)
		end
	end,
	["chaque remote client->serveur déclarée est gérée par le serveur"] = function()
		for name, section in declared do
			if section == "CLIENT_TO_SERVER" then
				Expect.truthy(guarded[name] ~= nil, `remote {name} sans RemoteGuard.On`)
			end
		end
	end,
	["les remotes serveur->client utilisées existent"] = function()
		for path, source in client do
			for name in string.gmatch(source, 'Net%.On%(%s*"(%w+)"') do
				Expect.equal(declared[name], "SERVER_TO_CLIENT", `Net.On("{name}") dans {path}`)
			end
			for name in string.gmatch(source, 'Net%.OnUnreliable%(%s*"(%w+)"') do
				Expect.equal(declared[name], "UNRELIABLE", `Net.OnUnreliable("{name}") dans {path}`)
			end
		end
		for path, source in server do
			for name in string.gmatch(source, 'Remotes%.Get%(%s*"(%w+)"') do
				Expect.truthy(declared[name] ~= nil, `Remotes.Get("{name}") dans {path}`)
			end
		end
	end,
	["chaque champ d'état lu par le client est envoyé par le serveur"] = function()
		local stateSource = server["src/server/Services/StateService.luau"]
		local snapshotBody = string.match(stateSource, "local function buildSnapshot.-return (%b{})")
		Expect.truthy(snapshotBody ~= nil, "buildSnapshot introuvable")
		local sent: { [string]: boolean } = {}
		for key in string.gmatch(snapshotBody, "\n%s*(%u%w*)%s*=") do
			sent[key] = true
		end
		for path, source in client do
			for key in string.gmatch(source, "[^%w_]state%.(%u%w*)") do
				Expect.truthy(sent[key], `state.{key} lu dans {path} mais jamais envoyé`)
			end
			for key in string.gmatch(source, "Store%.State%.(%u%w*)") do
				Expect.truthy(sent[key], `Store.State.{key} lu dans {path} mais jamais envoyé`)
			end
		end
	end,
}
