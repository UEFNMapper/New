--!strict
--[[
	BossLogic : la logique PURE du combat contre LAGZ (monde 7), partagée par le serveur
	(BossService, autorité), le client (BossController, habillage) et les tests (tests/boss.spec).

	Un état par joueur (le combat est individuel : chaque joueur voit SON LAGZ) :
	  Idle (0)      LAGZ attend, bouclier levé. Entrer dans l'arène lance le combat.
	  Lasers (1)    LASER_SECONDS de survie : lasers au ras du sol + curseur géant.
	  Plugs (2)     le sol se fragmente, des virus sortent : brancher les PLUG_COUNT prises
	                antivirus (boutons au sol, dans n'importe quel ordre) retire le bouclier.
	  Terminal (3)  bouclier détruit : le terminal final (Firewall boss, difficulté 8) est ouvert.
	  Defeated (4)  monde 7 nettoyé (ProgressService.ClearWorld) : LAGZ a disparu.

	Règles :
	- le combat n'existe que pour un joueur qui a nettoyé les mondes 1..6 et se trouve au
	  checkpoint d'entrée de l'arène ou dans la salle du terminal (Eligible) ; sinon Idle ;
	- mourir ou quitter l'arène plus de LEAVE_GRACE s pendant les phases 1–2 : retour à Idle
	  (on recommence) ; la phase 3 est gardée (le bouclier est tombé) jusqu'au lobby ;
	- une prise n'est validée que pendant la phase 2, une seule fois, si le personnage est à
	  moins de PLUG_REACH studs de son centre (vérifié par le serveur).
	Toutes les heures sont celles de Workspace:GetServerTimeNow() (comparables côté client).
]]

local Tower = require(script.Parent.Parent.Config.Tower)

local BossLogic = {}

BossLogic.Phase = table.freeze({
	Idle = 0,
	Lasers = 1,
	Plugs = 2,
	Terminal = 3,
	Defeated = 4,
})

local PHASE = BossLogic.Phase

BossLogic.WORLD = Tower.WORLD_COUNT -- le repaire de LAGZ
BossLogic.LASER_SECONDS = 25 -- durée de la phase 1 (survie)
BossLogic.PLUG_COUNT = 3
BossLogic.PLUG_REACH = 8 -- distance max (racine du personnage -> centre de la prise), avec la latence
BossLogic.LEAVE_GRACE = 2.5 -- secondes hors de l'arène tolérées pendant les phases 1–2
BossLogic.BOSS_DIFFICULTY = 8 -- MinigamePanel : 8 = Firewall contre LAGZ (36 PV, bouclier)

export type State = {
	Phase: number,
	Since: number, -- début de la phase en cours
	Plugs: { boolean }, -- prises branchées (index 1..PLUG_COUNT)
	OutsideSince: number?, -- sortie de l'arène pendant les phases 1–2
}

export type Inputs = {
	Now: number,
	Stage: number, -- checkpoint du joueur
	Cleared: number, -- mondes nettoyés
	AtLobby: boolean,
	Alive: boolean,
	InArena: boolean,
}

-- Évènements renvoyés par Step / Died / Plug (pour les répliques et la télémétrie).
export type Event = "Start" | "Plugs" | "Plug" | "Terminal" | "Abort" | "Reset" | "Defeated"

function BossLogic.New(now: number?): State
	return { Phase = PHASE.Idle, Since = now or 0, Plugs = {}, OutsideSince = nil }
end

-- Le joueur peut-il affronter LAGZ (mondes 1..6 nettoyés, à l'arène ou dans la dernière salle) ?
function BossLogic.Eligible(stage: number, cleared: number): boolean
	local last = Tower.TerminalStage(BossLogic.WORLD)
	return cleared == BossLogic.WORLD - 1 and (stage == last - 1 or stage == last)
end

-- Combat en cours (phases où l'arène est verrouillée et piégée).
function BossLogic.Fighting(phase: number): boolean
	return phase == PHASE.Lasers or phase == PHASE.Plugs
end

local function enter(state: State, phase: number, now: number)
	state.Phase = phase
	state.Since = now
	state.OutsideSince = nil
	if phase == PHASE.Idle or phase == PHASE.Lasers then
		table.clear(state.Plugs)
	end
end

-- Avance l'état d'une image serveur. Renvoie l'évènement éventuel.
function BossLogic.Step(state: State, input: Inputs): Event?
	local now = input.Now
	if input.Cleared >= BossLogic.WORLD then
		if state.Phase ~= PHASE.Defeated then
			enter(state, PHASE.Defeated, now)
			return "Defeated"
		end
		return nil
	end
	if input.AtLobby or not BossLogic.Eligible(input.Stage, input.Cleared) then
		if state.Phase ~= PHASE.Idle then
			enter(state, PHASE.Idle, now)
			return "Reset"
		end
		return nil
	end
	local phase = state.Phase
	if phase == PHASE.Defeated then
		-- Nouvelle ascension (Cleared est revenu à 6) : LAGZ est de retour.
		enter(state, PHASE.Idle, now)
		return "Reset"
	elseif phase == PHASE.Idle then
		if input.Alive and input.InArena then
			enter(state, PHASE.Lasers, now)
			return "Start"
		end
		return nil
	elseif BossLogic.Fighting(phase) then
		if not input.Alive then
			enter(state, PHASE.Idle, now)
			return "Abort"
		end
		if input.InArena then
			state.OutsideSince = nil
		else
			local since = state.OutsideSince or now
			state.OutsideSince = since
			if now - since > BossLogic.LEAVE_GRACE then
				enter(state, PHASE.Idle, now)
				return "Abort"
			end
		end
		if phase == PHASE.Lasers and now - state.Since >= BossLogic.LASER_SECONDS then
			enter(state, PHASE.Plugs, now)
			return "Plugs"
		end
	end
	return nil
end

-- Mort du personnage : le combat en cours est perdu (la phase 3 est gardée).
function BossLogic.Died(state: State, now: number): Event?
	if BossLogic.Fighting(state.Phase) then
		enter(state, PHASE.Idle, now)
		return "Abort"
	end
	return nil
end

-- Monde 7 nettoyé (terminal final réussi).
function BossLogic.Defeat(state: State, now: number): Event?
	if state.Phase ~= PHASE.Defeated then
		enter(state, PHASE.Defeated, now)
		return "Defeated"
	end
	return nil
end

-- Demande de branchement de la prise `index` ; `distance` = racine du personnage -> prise.
-- Renvoie (accepté, évènement ou raison du refus).
function BossLogic.Plug(state: State, index: number, distance: number, now: number): (boolean, string)
	if state.Phase ~= PHASE.Plugs then
		return false, "phase"
	end
	if index ~= math.floor(index) or index < 1 or index > BossLogic.PLUG_COUNT then
		return false, "index"
	end
	if state.Plugs[index] then
		return false, "done"
	end
	if not (distance <= BossLogic.PLUG_REACH) then
		return false, "distance"
	end
	state.Plugs[index] = true
	if BossLogic.PlugCount(state) >= BossLogic.PLUG_COUNT then
		enter(state, PHASE.Terminal, now)
		return true, "Terminal"
	end
	return true, "Plug"
end

function BossLogic.PlugCount(state: State): number
	local count = 0
	for i = 1, BossLogic.PLUG_COUNT do
		if state.Plugs[i] then
			count += 1
		end
	end
	return count
end

-- Prises branchées en masque de bits (bit i - 1 = prise i), pour l'attribut répliqué.
function BossLogic.PlugMask(state: State): number
	local mask = 0
	for i = 1, BossLogic.PLUG_COUNT do
		if state.Plugs[i] then
			mask += 2 ^ (i - 1)
		end
	end
	return mask
end

function BossLogic.MaskHas(mask: number, index: number): boolean
	return math.floor(mask / 2 ^ (index - 1)) % 2 == 1
end

-- Le terminal final peut-il être lancé ?
function BossLogic.TerminalOpen(state: State): boolean
	return state.Phase == PHASE.Terminal
end

-- Secondes restantes de la phase 1 (0 hors de la phase 1).
function BossLogic.Remaining(phase: number, since: number, now: number): number
	if phase ~= PHASE.Lasers then
		return 0
	end
	return math.max(0, BossLogic.LASER_SECONDS - (now - since))
end

-- Un piège de l'arène (attribut BossPhases, ex. "12") est-il actif pendant `phase` ?
function BossLogic.PhaseActive(spec: any, phase: number): boolean
	if type(spec) ~= "string" or not BossLogic.Fighting(phase) then
		return false
	end
	return string.find(spec, tostring(phase), 1, true) ~= nil
end

-- La position est-elle dans l'arène (boîte alignée sur les axes : centre + taille, repère BossArena) ?
function BossLogic.InArena(center: Vector3, size: Vector3, position: Vector3): boolean
	local d = position - center
	return math.abs(d.X) <= size.X / 2 and math.abs(d.Y) <= size.Y / 2 and math.abs(d.Z) <= size.Z / 2
end

return table.freeze(BossLogic)
