--[[
	PlayAudit : simule des parties (tests/lib/PlayRoute) et liste ce que le joueur ne peut pas voir ou
	atteindre : panneaux / fenêtres / écrans tournés vers un mur, cachés ou collés à une pièce,
	modèles 3D qui tournent le dos au parcours, prompts hors de portée.
	Usage : lune run tests/tools/PlayAudit.luau [fichier.json]   (depuis AngAInOne)
	AUDIT_DEBUG=<morceau de nom> : normale de la cible et points de vue les plus proches.
	Le JSON (facultatif) liste les problèmes avec leur position, pour les rendus render_iso.py --eye.
	Le test tests/playaudit.spec.luau exige le même résultat (exceptions justifiées : PlayRoute.ACCEPTED).
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local IsolatedTower = require("../lib/IsolatedTower")
local PlayRoute = require("../lib/PlayRoute")

local records = {}
local built = IsolatedTower.Build({
	Models = true,
	Observe = PlayRoute.Recorder(records),
})
local report = PlayRoute.Audit(built, records, process.env.AUDIT_DEBUG)
print(
	`points de vue simulés : {report.Views} ; plateformes atteignables : {report.Areas} ; étapes sans départ : {table.concat(
		report.Missing,
		", "
	)}`
)
print(
	`cibles : {report.Counts.Panneau} panneaux, {report.Counts["Façade"]} façades, {report.Counts.Prompt} prompts, {report.Counts["Prompt d'épreuve"]} prompts d'épreuve`
)
print(`problèmes : {#report.Problems} (dont {report.Accepted} acceptés, voir PlayRoute.ACCEPTED)`)
local lastWorld = nil
for _, p in report.Problems do
	if p.World ~= lastWorld then
		lastWorld = p.World
		print(`\n== {if p.World == 0 then "Lobby" elseif p.World < 0 then "Hors monde" else `Monde {p.World}`} ==`)
	end
	local tag = if p.Accepted then " (accepté)" else ""
	print(
		`  [{p.Kind}]{tag} {p.Name}\n      {p.Why}  @ ({math.floor(p.At[1])}, {math.floor(p.At[2])}, {math.floor(
			p.At[3]
		)})`
	)
end
local out = process.args[1]
if out then
	fs.writeFile(out, serde.encode("json", report.Problems, true))
end
