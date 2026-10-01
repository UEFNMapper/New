--!strict
--[[
	Investigation : règles de l'enquête du monde 7, « Sessions de jeu » (étape 6 du guide), jouée juste
	avant la phase finale du combat contre LAGZ. Le rapport de session montre un pic de lag et accuse
	le programme qui rame ; chaque programme dit qui l'a lancé (« Lancé par »). On remonte la chaîne :
	navigateur → updater → helper_svc → un processus masqué, LAGZ.exe, que l'on met en quarantaine.
]]

local Investigation = {}

export type Pod = {
	Id: string,
	Name: string,
	Cpu: string, -- « CPU 38 % »
	Parent: string?, -- Id du programme qui l'a lancé (nil = Windows)
	ParentName: string, -- ce qu'affiche « Lancé par »
	Hidden: boolean?, -- masqué tant que la chaîne n'y mène pas
	Culprit: boolean?,
	Suspect: boolean?, -- celui que le rapport accuse au départ
}

Investigation.PODS = table.freeze({
	{
		Id = "browser",
		Name = "navigateur.exe",
		Cpu = "CPU 38 % · 12 onglets",
		Parent = "updater",
		ParentName = "updater.exe",
		Suspect = true,
	},
	{ Id = "updater", Name = "updater.exe", Cpu = "CPU 4 %", Parent = "helper", ParentName = "helper_svc.exe" },
	{ Id = "helper", Name = "helper_svc.exe", Cpu = "CPU 2 %", Parent = "lagz", ParentName = "??? (masqué)" },
	{
		Id = "lagz",
		Name = "LAGZ.exe",
		Cpu = "CPU 41 %",
		ParentName = "free_robux_generator.exe",
		Hidden = true,
		Culprit = true,
	},
	{ Id = "music", Name = "musique.exe", Cpu = "CPU 1 %", ParentName = "explorer.exe (Windows)" },
	{ Id = "explorer", Name = "explorer.exe", Cpu = "CPU 3 %", ParentName = "Windows" },
} :: { Pod })

export type State = {
	Inspected: { [string]: boolean },
	Revealed: boolean,
	Quarantined: boolean,
	Inspections: number,
}

function Investigation.new(): State
	return { Inspected = {}, Revealed = false, Quarantined = false, Inspections = 0 }
end

function Investigation.Pod(id: string): Pod?
	for _, pod in Investigation.PODS do
		if pod.Id == id then
			return pod
		end
	end
	return nil
end

-- Inspecte un programme. Renvoie sa fiche, et `true` si cette inspection révèle le processus masqué.
function Investigation.Inspect(state: State, id: string): (Pod?, boolean)
	local pod = Investigation.Pod(id)
	if not pod or (pod.Hidden and not state.Revealed) then
		return nil, false
	end
	if not state.Inspected[id] then
		state.Inspected[id] = true
		state.Inspections += 1
	end
	local parent = if pod.Parent then Investigation.Pod(pod.Parent) else nil
	if parent and parent.Hidden and not state.Revealed then
		state.Revealed = true
		return pod, true
	end
	return pod, false
end

-- Maillons de la chaîne déjà éclairés : chaque programme inspecté relie son parent.
function Investigation.Linked(state: State, childId: string): boolean
	return state.Inspected[childId] == true
end

export type QuarantineResult = "Ok" | "Innocent" | "Hidden"

function Investigation.Quarantine(state: State, id: string): QuarantineResult
	local pod = Investigation.Pod(id)
	if not pod then
		return "Innocent"
	end
	if pod.Hidden and not state.Revealed then
		return "Hidden"
	end
	if not pod.Culprit then
		return "Innocent"
	end
	state.Quarantined = true
	return "Ok"
end

return table.freeze(Investigation)
