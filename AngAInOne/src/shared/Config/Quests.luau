--!strict
--[[
	Quests : modèles de quêtes quotidiennes / hebdomadaires et récompenses quotidiennes.
	Les objectifs "Collect" sont exprimés en secondes de production : ils s'adaptent
	au niveau du joueur au moment où la quête est tirée.
]]

export type QuestKind = "Collect" | "Upgrade" | "Zap" | "Overclock" | "Capsule" | "Playtime" | "Visit"

export type QuestTemplate = {
	Id: string,
	Kind: QuestKind,
	Target: number, -- Collect : secondes de production ; Playtime : minutes ; autres : nombre
	Chips: number,
	Text: string, -- "{n}" est remplacé par l'objectif formaté
	RequiredZone: number,
}

export type DailyReward = {
	Day: number,
	Kind: "Chips" | "Bits" | "Capsule" | "Boost" | "EpicNanobot",
	Amount: number, -- Chips : quantité ; Bits : secondes de prod ; Boost : minutes ; Capsule : nb
	Label: string,
}

local daily: { QuestTemplate } = {
	{ Id = "D_Collect1", Kind = "Collect", Target = 600, Chips = 15, Text = "Collecte {n} Bits", RequiredZone = 1 },
	{ Id = "D_Collect2", Kind = "Collect", Target = 1800, Chips = 25, Text = "Collecte {n} Bits", RequiredZone = 2 },
	{
		Id = "D_Upgrade1",
		Kind = "Upgrade",
		Target = 25,
		Chips = 15,
		Text = "Achète {n} améliorations",
		RequiredZone = 1,
	},
	{
		Id = "D_Upgrade2",
		Kind = "Upgrade",
		Target = 60,
		Chips = 25,
		Text = "Achète {n} améliorations",
		RequiredZone = 3,
	},
	{ Id = "D_Zap", Kind = "Zap", Target = 8, Chips = 20, Text = "Zappe {n} virus", RequiredZone = 1 },
	{
		Id = "D_Overclock",
		Kind = "Overclock",
		Target = 3,
		Chips = 25,
		Text = "Réussis {n} overclocks",
		RequiredZone = 5,
	},
	{ Id = "D_Capsule", Kind = "Capsule", Target = 2, Chips = 15, Text = "Ouvre {n} capsules", RequiredZone = 2 },
	{ Id = "D_Playtime", Kind = "Playtime", Target = 20, Chips = 20, Text = "Joue {n} minutes", RequiredZone = 1 },
	{
		Id = "D_Visit",
		Kind = "Visit",
		Target = 1,
		Chips = 10,
		Text = "Like la tour d'un autre joueur",
		RequiredZone = 1,
	},
}

local weekly: { QuestTemplate } = {
	{ Id = "W_Collect", Kind = "Collect", Target = 6 * 3600, Chips = 80, Text = "Collecte {n} Bits", RequiredZone = 1 },
	{
		Id = "W_Upgrade",
		Kind = "Upgrade",
		Target = 400,
		Chips = 60,
		Text = "Achète {n} améliorations",
		RequiredZone = 1,
	},
	{ Id = "W_Zap", Kind = "Zap", Target = 60, Chips = 70, Text = "Zappe {n} virus", RequiredZone = 1 },
	{ Id = "W_Capsule", Kind = "Capsule", Target = 15, Chips = 60, Text = "Ouvre {n} capsules", RequiredZone = 2 },
	{ Id = "W_Playtime", Kind = "Playtime", Target = 180, Chips = 90, Text = "Joue {n} minutes", RequiredZone = 1 },
	{
		Id = "W_Overclock",
		Kind = "Overclock",
		Target = 15,
		Chips = 70,
		Text = "Réussis {n} overclocks",
		RequiredZone = 5,
	},
}

local rewards: { DailyReward } = {
	{ Day = 1, Kind = "Chips", Amount = 25, Label = "25 Chips" },
	{ Day = 2, Kind = "Bits", Amount = 900, Label = "15 min de Bits" },
	{ Day = 3, Kind = "Chips", Amount = 40, Label = "40 Chips" },
	{ Day = 4, Kind = "Capsule", Amount = 1, Label = "1 capsule" },
	{ Day = 5, Kind = "Chips", Amount = 60, Label = "60 Chips" },
	{ Day = 6, Kind = "Boost", Amount = 30, Label = "30 min Bits x2" },
	{ Day = 7, Kind = "EpicNanobot", Amount = 1, Label = "Nanobot Épique" },
}

local byId: { [string]: QuestTemplate } = {}
for _, q in daily do
	byId[q.Id] = table.freeze(q)
end
for _, q in weekly do
	byId[q.Id] = table.freeze(q)
end
for _, r in rewards do
	table.freeze(r)
end

return table.freeze({
	Daily = table.freeze(daily),
	Weekly = table.freeze(weekly),
	ById = table.freeze(byId),
	DailyCount = 3,
	WeeklyCount = 4,
	DailyRewards = table.freeze(rewards),
})
