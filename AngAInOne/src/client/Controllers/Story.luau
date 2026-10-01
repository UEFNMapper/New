--!strict
--[[
	Story : les répliques d'Anga et de LAGZ pendant l'ascension (docs/SCENARIO.md).
	- LAGZ se moque en entrant dans un monde et à chaque incident (Fx "Incident")
	- Anga souffle quand un incident est passé, encourage après plusieurs chutes d'affilée
	  et donne une astuce sur les pièges du monde
	Les répliques d'intro de monde et de monde nettoyé sont jouées par Feedback.
	Répliques de transition (monde nettoyé, arrivée dans un monde) : elles EXPIRENT si la file
	est trop longue (Dialogue.Say, 4e paramètre), pour ne jamais retarder le monde suivant.
	Ton : drôle, jamais effrayant ; une réplique = une phrase courte.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)

local Net = require(script.Parent.Net)
local Dialogue = require(script.Parent.Parent.UI.Screens.Dialogue)

local Story = {}

local player = Players.LocalPlayer

-- LAGZ en arrivant dans chaque monde.
Story.LagzWorld = {
	"Hé hé ! Sans courant, pas de live ! Bon courage, minus !",
	"200 onglets ouverts… et j'en ouvre encore ! Mouahaha !",
	"J'ai tout corrompu ! Attention aux pixels roses !",
	"Ça chauffe, hein ? Mes boules de poussière adorent ça !",
	"Mon mineur tourne à 100 % ! Ce processeur est À MOI !",
	"Freeeeze ! Tout le monde s'arrête… sauf moi !",
	"Tu es arrivé jusqu'à mon repaire ? Chargement de ma défaite : 0 %.",
}

-- LAGZ quand il lance un incident.
Story.LagzIncident = {
	Freeze = { "FREEZE ! Plus personne ne bouge !", "Pause ! Hé… pourquoi toi tu bouges encore ?" },
	Lag = { "Lag, lag, LAG ! Des à-coups partout : ton 1 % low va pleurer !", "999 de ping ! Bonne chance, hé hé !" },
	Blackout = { "Clic ! J'éteins la lumière !", "Oups, j'ai marché sur la prise ! Hé hé !" },
	Popups = { "Des pubs gratuites pour tout le monde !", "Clique ici ! Non, là ! Non, LÀ !" },
	Corruption = { "Pixels roses partout ! C'est joli, non ?", "Oups ! J'ai inversé les dalles !" },
	Overheat = { "On monte le chauffage à fond !", "Ça chauffe, ça chauffe ! Mouahaha !" },
	Update = {
		"Mise à jour ! 0 %… NE PAS ÉTEINDRE ! Mouahaha !",
		"Redémarrage dans 5 secondes… ou pas. Hé hé !",
	},
}

-- LAGZ qui surgit de son écran sur une paroi du monde (Controllers/LagzCameo), 2 par monde.
Story.LagzCameo = {
	{ "Coucou ! C'est moi qui mange tes électrons !", "Bzzt ! Encore une petite coupure ? Hé hé !" },
	{ "Tu fermes mes pubs ? J'en ai 200 !", "Oups, j'ai encore ouvert un onglet ! Hé hé !" },
	{ "Ton disque est tout rose ! J'adore !", "Chargement de ta défaite : 99 %…" },
	{ "Il fait chaud, hein ? Le chauffage, c'est moi !", "Atchoum ! Oups, de la poussière partout !" },
	{ "Mon mineur creuse, creuse, creuse ! Mouahaha !", "Processeur à 100 % ! Et toi, à combien ?" },
	{ "Tiens, un freeze ! Oh, pardon… Hé hé !", "Image figée ! Souris pour la photo !" },
	{ "Tu es chez moi, ici ! Essuie tes pieds !", "Encore un pas et… écran bleu ! Mouahaha !" },
}

-- Réplique d'une apparition : la 1re ou la 2e du monde selon l'étape.
function Story.CameoLine(world: number, index: number): string?
	local lines = Story.LagzCameo[world]
	return if lines then lines[(index - 1) % #lines + 1] else nil
end

-- Anga quand l'incident est passé (pas à chaque fois).
Story.AngaRelief = {
	"Ouf ! LAGZ a raté son coup !",
	"Bien joué ! On continue !",
	"Rien ne t'arrête, toi !",
}

-- Anga après plusieurs chutes d'affilée.
Story.AngaCheer = {
	"Pas grave ! Même les pros tombent. Respire et réessaie !",
	"Tu y es presque ! Observe le rythme avant de sauter.",
	"Courage ! Chaque essai te rapproche du checkpoint.",
}

-- Astuce d'Anga pour chaque monde.
Story.AngaHint = {
	"Astuce : les décharges s'arrêtent un instant. Passe juste après l'éclair !",
	"Astuce : attends que la barrette remonte, puis fonce dessous !",
	"Astuce : ne t'arrête pas sur les plateformes qui clignotent !",
	"Astuce : avance entre deux rafales de vent, pas pendant !",
	"Astuce : regarde passer les lasers une fois avant de courir.",
	"Astuce : passe entre les pales quand elles s'éloignent de toi.",
	"Astuce : les virus suivent un chemin. Attends qu'ils s'éloignent !",
}

-- LAGZ quand un monde est nettoyé (sauf le dernier : il est vaincu).
Story.LagzCleaned = {
	"Grrr ! Tu as réparé ça ? Pas grave, j'ai d'autres virus !",
	"Quoi ?! Rends-moi mes pubs !",
	"Mes beaux pixels roses… Tu vas me le payer !",
	"Mes boules de poussière ! Nooon !",
	"Mon mineur ! Il travaillait si bien…",
	"Hmpf. Même pas mal. Enfin… un peu.",
}

-- Délais d'expiration (s) des répliques de transition de monde.
local CLEANED_EXPIRES = 6
local WORLD_EXPIRES = 10

local deathsInRow = 0
local currentWorld = 0
local incidentCount = 0

local function pick(list: { string }): string
	return list[math.random(1, #list)]
end

local function lagz(text: string, delay: number, expires: number?)
	task.delay(delay, function()
		Dialogue.Say(text, 3.5, "LAGZ", expires)
	end)
end

local function anga(text: string, duration: number?)
	Dialogue.Say(text, duration or 4, "Anga")
end

local function onDeath()
	deathsInRow += 1
	if deathsInRow == 3 then
		anga(pick(Story.AngaCheer))
		local hint = Story.AngaHint[currentWorld]
		if hint then
			anga(hint, 5)
		end
	elseif deathsInRow == 6 then
		anga(pick(Story.AngaCheer))
	elseif deathsInRow == 10 then
		anga("Ce passage est coriace ! Fais une petite pause si tu veux, je t'attends.", 5)
		deathsInRow = 0
	end
end

local function onFx(kind: string, payload: any)
	if type(payload) ~= "table" then
		return
	end
	if kind == "Checkpoint" then
		deathsInRow = 0
		if type(payload.World) == "number" then
			currentWorld = payload.World
		end
		-- Nouveau monde : Anga le présente (Feedback), puis LAGZ se moque (file d'attente).
		if payload.NewWorld and Story.LagzWorld[payload.World] then
			lagz(Story.LagzWorld[payload.World], 2, WORLD_EXPIRES)
		end
	elseif kind == "RunStart" then
		deathsInRow = 0
		currentWorld = 1
		lagz(Story.LagzWorld[1], 2)
	elseif kind == "Death" then
		if payload.UserId == player.UserId then
			onDeath()
		end
	elseif kind == "WorldCleared" then
		deathsInRow = 0
		local line = Story.LagzCleaned[payload.World]
		if line then
			lagz(line, 7.5, CLEANED_EXPIRES)
		end
	elseif kind == "Incident" then
		local lines = Story.LagzIncident[payload.Kind]
		if payload.Phase == "Warn" and lines then
			incidentCount += 1
			-- Pas de réplique si Anga est déjà en train de parler (on ne cumule pas).
			if not Dialogue.IsBusy() then
				Dialogue.Say(pick(lines), 3, "LAGZ")
			end
		elseif payload.Phase == "End" and incidentCount % 3 == 1 and not Dialogue.IsBusy() then
			anga(pick(Story.AngaRelief), 3)
		end
	elseif kind == "Victory" then
		deathsInRow = 0
		currentWorld = 0
	end
end

function Story.Start()
	Net.On("Fx", onFx)
	-- Monde courant (reprise d'une ascension en cours, retour au checkpoint…).
	local function syncWorld()
		local stage = player:GetAttribute("Stage")
		if type(stage) == "number" then
			currentWorld = Tower.WorldOf(stage)
		end
	end
	syncWorld()
	player:GetAttributeChangedSignal("Stage"):Connect(syncWorld)
end

return Story
