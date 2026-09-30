--!strict
--[[
	AppPages : la page de l'app AngAInOne qui correspond à chaque monde (en-tête affiché en entrant
	dans un monde, barre latérale des fenêtres de l'app). Logique PURE.
	Si la définition du monde (Config/Tower) fournit AppSection + AppSubtitle, elles priment ;
	sinon on prend la table de secours ci-dessous (pages réelles de l'app).
]]

local AppPages = {}

export type Page = { Title: string, Subtitle: string }

local FALLBACK: { Page } = {
	{ Title = "Alimentation", Subtitle = "Ce qui coupe le courant de ton PC, et comment l'éviter." },
	{ Title = "Applications", Subtitle = "Ce qui tourne sur ton PC, et ce qui remplit ta mémoire." },
	{ Title = "Disques", Subtitle = "L'état de tes SSD et disques durs, et ce qui prend la place." },
	{ Title = "Diagnostic · Températures", Subtitle = "Ce qui chauffe, ce qui souffle, et quoi faire." },
	{ Title = "Test de perf", Subtitle = "Ce que ton processeur donne vraiment, image par image." },
	{ Title = "Pilotes GPU", Subtitle = "Ta carte graphique, son pilote, et une installation propre." },
	{ Title = "Plantages", Subtitle = "Ce qui a fait planter ton PC, et quoi faire ensuite." },
}

-- Page de l'app du monde `world` ; `def` = Tower.Worlds[world] (facultatif).
function AppPages.Of(world: number, def: any?): Page
	local fallback = FALLBACK[math.clamp(math.floor(world), 1, #FALLBACK)]
	if type(def) == "table" then
		local title, subtitle = def.AppSection, def.AppSubtitle
		if type(title) == "string" and title ~= "" and type(subtitle) == "string" and subtitle ~= "" then
			return { Title = title, Subtitle = subtitle }
		end
	end
	return { Title = fallback.Title, Subtitle = fallback.Subtitle }
end

-- Barre latérale d'une fenêtre de l'app : Tableau de bord, une page par monde, Diagnostic.
-- `worlds` = Tower.Worlds (ou nil : pages de secours). Pas de doublon.
function AppPages.Sidebar(worlds: { any }?): { string }
	local list: { string } = { "Tableau de bord" }
	local count = if worlds then #worlds else #FALLBACK
	for w = 1, count do
		local title = AppPages.Of(w, if worlds then worlds[w] else nil).Title
		-- « Diagnostic · Températures » -> « Températures » (sous-page)
		title = string.match(title, "·%s*(.+)$") or title
		if not table.find(list, title) then
			table.insert(list, title)
		end
	end
	if not table.find(list, "Diagnostic") then
		table.insert(list, "Diagnostic")
	end
	return list
end

return table.freeze(AppPages)
