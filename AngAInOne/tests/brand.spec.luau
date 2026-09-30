-- Aucune vraie marque, aucun vrai produit ni pseudo réel dans le jeu (partenariat AngAInOne, public
-- 8–14 ans) : parcourt TOUS les fichiers de src/ (et les textes d'assets/) et refuse la liste
-- ci-dessous, sans tenir compte de la casse, en mots entiers (« intelligence » ne déclenche pas
-- « Intel », « évolution » ne déclenche pas « EVO »).
-- Mots génériques gardés volontairement (à valider par le partenaire) : Windows, dwm.exe, SSD, NVMe,
-- NTFS, DDR5, Fluent (style de l'app), Roblox (la plateforme).

-- Mots entiers interdits (minuscules).
local BANNED_WORDS = {
	-- cartes graphiques, processeurs
	"nvidia",
	"geforce",
	"rtx",
	"gtx",
	"radeon",
	"amd",
	"ryzen",
	"intel",
	"phantom",
	"gainward",
	"zotac",
	"evga",
	"palit",
	"asus",
	"msi",
	"gigabyte",
	-- stockage, mémoire, périphériques
	"samsung",
	"evo",
	"kingston",
	"corsair",
	"seagate",
	"logitech",
	"razer",
	"steelseries",
	"hyperx",
	"noctua",
	"nzxt",
	-- logiciels, jeux, réseaux
	"chrome",
	"firefox",
	"fortnite",
	"unreal",
	"minecraft",
	"microsoft",
	"google",
	"youtube",
	"tiktok",
	"twitch",
	"discord",
	-- pseudos réels
	"luffy",
	"builderman",
}

-- Chaînes exactes interdites (références réelles relevées dans les captures d'écran).
local BANNED_TOKENS = {
	"2b2qexm7", -- micrologiciel d'un vrai SSD
	"76b900", -- vert de la marque de cartes graphiques
	"610.47", -- version réelle de pilote
	"angaforce",
}

local TEXT_EXTENSIONS = { luau = true, lua = true, json = true, md = true, txt = true, py = true, toml = true }

local function isWordByte(byte: number?): boolean
	if byte == nil then
		return false
	end
	-- Lettres, chiffres, _ et octets UTF-8 (lettres accentuées) : font partie du mot.
	return byte >= 128
		or byte == 95
		or (byte >= 48 and byte <= 57)
		or (byte >= 65 and byte <= 90)
		or (byte >= 97 and byte <= 122)
end

-- Occurrences de `word` en mot entier dans `text` (déjà en minuscules) : numéros de ligne.
local function findWord(text: string, word: string): { number }
	local lines = {}
	local from = 1
	while true do
		local first, last = string.find(text, word, from, true)
		if not first then
			break
		end
		if not isWordByte(string.byte(text, first - 1)) and not isWordByte(string.byte(text, last + 1)) then
			local _, count = string.gsub(string.sub(text, 1, first), "\n", "")
			table.insert(lines, count + 1)
		end
		from = last + 1
	end
	return lines
end

local function collect(dir: string, into: { string })
	for _, name in Fs.readDir(dir) do
		local path = `{dir}/{name}`
		if Fs.isDir(path) then
			collect(path, into)
		else
			local extension = string.match(name, "%.(%w+)$")
			if extension and TEXT_EXTENSIONS[string.lower(extension)] then
				table.insert(into, path)
			end
		end
	end
end

local function scan(roots: { string }): { string }
	local files = {}
	for _, root in roots do
		if Fs.isDir(root) then
			collect(root, files)
		end
	end
	local hits = {}
	for _, path in files do
		local text = string.lower(Fs.readFile(path))
		for _, word in BANNED_WORDS do
			for _, line in findWord(text, word) do
				table.insert(hits, `{path}:{line} « {word} »`)
			end
		end
		for _, token in BANNED_TOKENS do
			if string.find(text, token, 1, true) then
				table.insert(hits, `{path} « {token} »`)
			end
		end
	end
	return hits
end

return {
	["détecteur : mots entiers, sans casse"] = function()
		Expect.equal(#findWord(string.lower("Carte NVIDIA RTX"), "rtx"), 1)
		Expect.equal(#findWord(string.lower("Une vraie Intelligence"), "intel"), 0, "préfixe d'un autre mot")
		Expect.equal(#findWord(string.lower("l'évolution"), "evo"), 0)
		Expect.equal(#findWord(string.lower("SSD 970 EVO Plus"), "evo"), 1)
		Expect.equal(#findWord("(amd)", "amd"), 1, "ponctuation = frontière")
		Expect.equal(#findWord("amd_driver", "amd"), 0, "identifiant")
		Expect.equal(findWord("ligne 1\nligne 2 chrome", "chrome")[1], 2, "numéro de ligne")
	end,
	["aucune vraie marque, aucun produit réel ni pseudo réel dans src/ et assets/"] = function()
		local hits = scan({ "src", "assets" })
		Expect.equal(#hits, 0, `marques ou références réelles trouvées :\n    {table.concat(hits, "\n    ")}`)
	end,
}
