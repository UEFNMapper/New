--!strict
--[[
	Driver : règles de l'épreuve du monde 6, « La carte graphique corrompue » (étape 5 et 5 bis du guide).
	Comme la page Pilotes GPU de l'app, en étapes :
	1. Nettoyage complet : supprimer les fichiers de l'ancien pilote ;
	2. Télécharger : rester dans la zone de téléchargement jusqu'à 100 % (en sortir met en pause) ;
	3. Installer : prendre chaque câble et le brancher sur le port de sa couleur ;
	4. Écran (page Écrans) : l'écran bridé à 60 Hz passe à sa fréquence maximale.
]]

local Driver = {}

Driver.FILES = table.freeze({ "ancien_pilote.sys", "cache_shaders.bin", "profil_3d_v2019.cfg", "panneau_obsolete.dll" })
Driver.CABLES = 3
Driver.DOWNLOAD_SECONDS = 6
Driver.FREQUENCIES = table.freeze({ 60, 120, 144, 170 })
Driver.SCREENS = table.freeze({ 170, 60, 170 }) -- fréquence de départ de chaque écran
Driver.MAX_HZ = 170

export type State = {
	Files: { boolean }, -- supprimé ?
	Download: number, -- 0..1
	Plugged: { boolean },
	Carrying: number?,
	Hz: { number },
	Mistakes: number,
}

function Driver.new(): State
	local files, plugged = {}, {}
	for i = 1, #Driver.FILES do
		files[i] = false
	end
	for i = 1, Driver.CABLES do
		plugged[i] = false
	end
	return {
		Files = files,
		Download = 0,
		Plugged = plugged,
		Carrying = nil,
		Hz = table.clone(Driver.SCREENS) :: { number },
		Mistakes = 0,
	}
end

local function count(list: { boolean }): number
	local n = 0
	for _, value in list do
		if value then
			n += 1
		end
	end
	return n
end

-- Étape en cours : 1..4, 5 = terminé.
function Driver.Stage(state: State): number
	if count(state.Files) < #Driver.FILES then
		return 1
	elseif state.Download < 1 then
		return 2
	elseif count(state.Plugged) < Driver.CABLES then
		return 3
	end
	for _, hz in state.Hz do
		if hz < Driver.MAX_HZ then
			return 4
		end
	end
	return 5
end

function Driver.FilesLeft(state: State): number
	return #Driver.FILES - count(state.Files)
end

function Driver.CablesPlugged(state: State): number
	return count(state.Plugged)
end

function Driver.Delete(state: State, file: number): boolean
	if Driver.Stage(state) ~= 1 or state.Files[file] ~= false then
		return false
	end
	state.Files[file] = true
	return true
end

-- Téléchargement : avance seulement dans la zone (`inside`).
function Driver.Step(state: State, dt: number, inside: boolean)
	if Driver.Stage(state) == 2 and inside then
		state.Download = math.min(1, state.Download + math.max(dt, 0) / Driver.DOWNLOAD_SECONDS)
	end
end

function Driver.Take(state: State, cable: number): boolean
	if Driver.Stage(state) ~= 3 or state.Carrying ~= nil or state.Plugged[cable] ~= false then
		return false
	end
	state.Carrying = cable
	return true
end

export type PlugResult = "Ok" | "Wrong" | "Empty"

-- Branche le câble porté sur le port `port` (même numéro = même couleur).
function Driver.Plug(state: State, port: number): PlugResult
	local cable = state.Carrying
	if not cable then
		return "Empty"
	end
	if cable ~= port then
		state.Mistakes += 1
		return "Wrong"
	end
	state.Plugged[cable] = true
	state.Carrying = nil
	return "Ok"
end

-- Change la fréquence de l'écran `screen` (cran suivant) ; renvoie la nouvelle fréquence.
function Driver.Cycle(state: State, screen: number): number
	local hz = state.Hz[screen]
	if not hz or Driver.Stage(state) ~= 4 then
		return hz or 0
	end
	local index = table.find(Driver.FREQUENCIES, hz) or 1
	local nextHz = Driver.FREQUENCIES[index % #Driver.FREQUENCIES + 1]
	state.Hz[screen] = nextHz
	return nextHz
end

function Driver.Score(state: State): number
	return math.max(60, 100 - 10 * state.Mistakes)
end

return table.freeze(Driver)
