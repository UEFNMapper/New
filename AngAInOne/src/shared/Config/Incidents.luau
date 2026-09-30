--!strict
--[[
	Incidents : les « attaques » de LAGZ pendant une ascension (voir docs/SCENARIO.md §4).
	Le serveur (IncidentService) les programme par monde et publie leur état dans
	ReplicatedStorage.IncidentState ; le client les affiche, et les pièges en tiennent compte
	(TrapClock pour FREEZE / LAG SPIKE, TrapController pour BLACKOUT / CORRUPTION / SURCHAUFFE).
]]

export type IncidentDef = {
	Kind: string,
	Title: string, -- gros titre à l'écran
	Warning: string, -- annonce 3 s avant
	Duration: number, -- secondes
	Color: string, -- hex de l'ambiance
}

local list: { IncidentDef } = {
	{
		Kind = "Freeze",
		Title = "FREEZE !",
		Warning = "LAGZ prépare un FREEZE : tout va se figer !",
		Duration = 6,
		Color = "9FD8FF",
	},
	{
		Kind = "Lag",
		Title = "LAG SPIKE !",
		Warning = "LAGZ envoie un pic de LAG : ça va saccader !",
		Duration = 7,
		Color = "F6AD55",
	},
	{
		Kind = "Blackout",
		Title = "BLACKOUT !",
		Warning = "Coupure de courant imminente !",
		Duration = 7,
		Color = "2D3748",
	},
	{
		Kind = "Popups",
		Title = "POP-UP STORM !",
		Warning = "Des pubs arrivent : ferme-les vite !",
		Duration = 10,
		Color = "ED64A6",
	},
	{
		Kind = "Corruption",
		Title = "CORRUPTION !",
		Warning = "Les dalles vont s'inverser !",
		Duration = 6,
		Color = "E834D6",
	},
	{
		Kind = "Overheat",
		Title = "SURCHAUFFE !",
		Warning = "Ça va chauffer : toutes les bouches s'activent !",
		Duration = 7,
		Color = "FF4E34",
	},
}

local byKind: { [string]: IncidentDef } = {}
for _, def in list do
	byKind[def.Kind] = def
end

return table.freeze({
	List = list,
	ByKind = byKind,
	WarningSeconds = 3,
	IntervalMin = 60, -- secondes entre deux incidents dans un même monde
	IntervalMax = 120,
	BossIntervalMin = 35, -- monde 7 : LAGZ attaque plus souvent
	BossIntervalMax = 60,
	LagStep = 0.4, -- LAG SPIKE : le temps des pièges avance par pas de 0,4 s
	StateFolder = "IncidentState", -- dossier de ReplicatedStorage (attributs Kind{w}, Warn{w}, Start{w}, End{w}, Offset{w})
})
