--!strict
--[[
	Missions : 3 missions du jour, tirées au hasard chaque jour (UTC) parmi ces modèles.
	Kind = compteur incrémenté par le serveur (voir MissionService).
]]

export type MissionKind = "Checkpoints" | "Coins" | "Minigames" | "Worlds" | "Wins" | "Arcade"

export type MissionTemplate = {
	Id: string,
	Kind: MissionKind,
	Text: string, -- "{n}" est remplacé par l'objectif
	Targets: { number },
	Bits: number,
}

local templates: { MissionTemplate } = {
	{ Id = "Checkpoints", Kind = "Checkpoints", Text = "Atteins {n} checkpoints", Targets = { 5, 10, 15 }, Bits = 60 },
	{ Id = "Coins", Kind = "Coins", Text = "Ramasse {n} orbes de Bits", Targets = { 15, 30, 50 }, Bits = 50 },
	{
		Id = "Minigames",
		Kind = "Minigames",
		Text = "Élimine les virus de {n} terminaux",
		Targets = { 1, 2, 3 },
		Bits = 80,
	},
	{ Id = "Worlds", Kind = "Worlds", Text = "Termine {n} monde(s)", Targets = { 1, 2 }, Bits = 90 },
	{ Id = "Wins", Kind = "Wins", Text = "Atteins le sommet {n} fois", Targets = { 1 }, Bits = 200 },
	{ Id = "Arcade", Kind = "Arcade", Text = "Gagne {n} partie(s) à l'arcade", Targets = { 1, 3 }, Bits = 40 },
}

local byId: { [string]: MissionTemplate } = {}
for _, template in templates do
	byId[template.Id] = template
end

return table.freeze({
	Templates = templates,
	ById = byId,
	PerDay = 3,
})
