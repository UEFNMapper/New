-- Parties simulées (tests/lib/PlayRoute) : le joueur suit chaque étape (toutes les plateformes
-- atteignables), circule dans les salles du terminal, le lobby et le BIOS, et regarde autour de lui.
-- Chaque panneau / fenêtre / écran doit être lisible depuis un point de vue (de face, à portée, sans
-- obstacle, face pas collée à une pièce), chaque modèle à façade doit montrer son avant au joueur,
-- chaque prompt doit être atteignable. Rapport détaillé : lune run tests/tools/PlayAudit.luau
local records = {}
local built = IsolatedTower.Build({ Models = true, Observe = PlayRoute.Recorder(records) })
local report = PlayRoute.Audit(built, records)

return {
	["parties simulées : chaque étape a un départ, et le joueur explore assez de plateformes"] = function()
		Expect.equal(#report.Missing, 0, `étapes sans départ : {table.concat(report.Missing, ", ")}`)
		Expect.truthy(report.Areas > 1000, `plateformes atteignables : {report.Areas}`)
		Expect.truthy(report.Counts.Panneau > 150 and report.Counts["Façade"] > 25, "cibles contrôlées")
		Expect.truthy(
			(report.Counts["Prompt d'épreuve"] or 0) >= 40,
			`prompts d'épreuve : {report.Counts["Prompt d'épreuve"]}`
		)
	end,

	["parties simulées : panneaux, fenêtres, modèles et prompts vus / atteints par le joueur"] = function()
		local lines = {}
		for _, p in report.Problems do
			if not p.Accepted then
				table.insert(lines, `[{p.Kind}] {p.Name} : {p.Why}`)
			end
		end
		print(
			`    {report.Counts.Panneau} panneaux, {report.Counts["Façade"]} façades, {report.Counts.Prompt} prompts, {report.Counts["Prompt d'épreuve"]} prompts d'épreuve ; exceptions : {report.Accepted}`
		)
		Expect.equal(#lines, 0, table.concat(lines, "\n      "))
	end,

	["parties simulées : chaque exception justifiée existe encore (liste à jour)"] = function()
		local seen = {}
		for _, p in report.Problems do
			if p.Accepted then
				seen[p.Name] = true
			end
		end
		for name in PlayRoute.ACCEPTED do
			Expect.truthy(seen[name], `exception devenue inutile, à retirer de PlayRoute.ACCEPTED : {name}`)
		end
	end,
}
