--[[
	AngAInOne — Audit de sécurité des modèles importés (Toolbox / Creator Store / kits).

	UTILISATION (Roblox Studio) :
	1. Sélectionne le(s) modèle(s) importé(s) dans l'Explorer (ou rien pour scanner tout Workspace).
	2. Menu Affichage > Barre de commande (View > Command Bar).
	3. Colle TOUT ce fichier dans la barre de commande et appuie sur Entrée.
	4. Lis le rapport dans la fenêtre Sortie (Output).

	Le script NE SUPPRIME RIEN : il liste. Règle d'or : supprime tout script dont tu ne
	comprends pas exactement le rôle. Un décor n'a besoin d'AUCUN script.
]]

local Selection = game:GetService("Selection")

local SUSPICIOUS = {
	{ Pattern = "require%s*%(%s*%d+", Why = "require(ID) : charge du code externe (backdoor classique)" },
	{ Pattern = "getfenv", Why = "getfenv : manipulation d'environnement (obfuscation)" },
	{ Pattern = "setfenv", Why = "setfenv : manipulation d'environnement (obfuscation)" },
	{ Pattern = "loadstring", Why = "loadstring : exécute du texte comme du code" },
	{ Pattern = "string%.reverse", Why = "string.reverse : souvent utilisé pour cacher du code" },
	{ Pattern = "\\%d%d%d?\\%d%d%d?\\%d%d%d?", Why = "séquences \\ddd : chaîne probablement obfusquée" },
	{ Pattern = "\\x%x%x", Why = "séquences \\x.. : chaîne probablement obfusquée" },
	{ Pattern = "MarketplaceService", Why = "achats : un décor ne doit jamais proposer d'achat" },
	{ Pattern = "TeleportService", Why = "téléportation vers un autre jeu" },
	{ Pattern = "HttpService", Why = "requêtes web" },
	{ Pattern = "InsertService", Why = "insertion d'assets à distance" },
	{ Pattern = "ServerScriptService", Why = "accès aux scripts serveur" },
	{ Pattern = "Kick%s*%(", Why = "expulse des joueurs" },
	{ Pattern = "%.Parent%s*=%s*nil", Why = "se cache/supprime après exécution" },
}

local roots = Selection:Get()
if #roots == 0 then
	roots = { workspace }
end

local scripts, warnings = 0, 0
local report = {}

local function check(container)
	for _, item in ipairs(container:GetDescendants()) do
		if item:IsA("LuaSourceContainer") then
			scripts += 1
			local ok, source = pcall(function()
				return item.Source
			end)
			local hits = {}
			if ok and type(source) == "string" then
				if #source > 20000 then
					table.insert(hits, "script très long (" .. #source .. " caractères) pour un modèle")
				end
				for _, rule in ipairs(SUSPICIOUS) do
					if string.find(source, rule.Pattern) then
						table.insert(hits, rule.Why)
					end
				end
				-- Longues lignes sans espaces = code minifié / obfusqué
				for line in string.gmatch(source, "[^\n]+") do
					if #line > 400 and not string.find(line, " ") then
						table.insert(hits, "ligne de " .. #line .. " caractères sans espace (obfuscation)")
						break
					end
				end
			end
			-- Noms trompeurs fréquents des backdoors
			local lowered = string.lower(item.Name)
			for _, bait in ipairs({ "vaccine", "antivirus", "fix", "weld", "lag", "virus", "anti", " " }) do
				if string.find(lowered, bait, 1, true) then
					table.insert(hits, "nom trompeur (« " .. item.Name .. " »)")
					break
				end
			end
			if item:IsA("Script") and item.RunContext == Enum.RunContext.Client then
				table.insert(hits, "Script en RunContext Client (inhabituel)")
			end
			local label = item:GetFullName() .. " [" .. item.ClassName .. "]"
			if #hits > 0 then
				warnings += 1
				table.insert(report, "⚠️  " .. label .. "\n      - " .. table.concat(hits, "\n      - "))
			else
				table.insert(report, "•  " .. label .. " (aucun motif suspect, vérifie quand même son rôle)")
			end
		end
	end
end

for _, root in ipairs(roots) do
	check(root)
end

print("======== AUDIT AngAInOne ========")
print(("Scripts trouvés : %d  ·  suspects : %d"):format(scripts, warnings))
for _, line in ipairs(report) do
	print(line)
end
if scripts == 0 then
	print("✔ Aucun script : ce modèle est un décor pur, parfait.")
end
print("Rappel : Paramètres du jeu > Sécurité : garde « Allow HTTP Requests » et « Allow Third Party Sales/Teleports » désactivés si tu n'en as pas besoin.")
print("=================================")
