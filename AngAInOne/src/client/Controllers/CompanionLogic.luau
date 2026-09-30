--!strict
--[[
	CompanionLogic : la logique PURE du compagnon (mini-Anga sur son drone AngAInOne), sans
	instance Roblox, testée dans Lune (tests/companion.spec.luau). Companion.luau s'occupe du rendu.

	- Spring      : ressort amorti (suivi fluide de l'épaule, sans à-coups même si l'image rame)
	- Tracker     : « le joueur progresse-t-il ? » (nouvelle étape, ou nettement plus près du
	                prochain checkpoint) ; ShouldGuide = aucun progrès depuis GUIDE_AFTER secondes
	- Mood        : l'émotion affichée, par priorité (fête > tristesse > gel > panique > joie > guide)
	- FollowTarget: où se placer (épaule droite vue de la caméra, ou un peu devant pour guider)
	- BeamDirection: où pointe la flèche du guide (droit si le checkpoint est en vue, sinon à plat)
	- Debounce    : bascule stable (bulle au-dessus d'Anga ↔ bulle du bas) sans clignoter
]]

local CompanionLogic = {}

-- Secondes sans progrès avant qu'Anga montre le chemin.
CompanionLogic.GUIDE_AFTER = 20
-- Gain (studs) vers le prochain checkpoint qui compte comme un progrès.
CompanionLogic.PROGRESS_STEP = 8
-- Déjà tout près du checkpoint : inutile de guider.
CompanionLogic.GUIDE_MIN_DISTANCE = 14
-- Pas maximal d'intégration du ressort (stabilité quand l'image rame).
CompanionLogic.MAX_STEP = 1 / 120

------------------------------------------------------------------------------------
-- Mouvement
------------------------------------------------------------------------------------

--[[
	Un pas de ressort amorti vers `target` (Euler semi-implicite, sous-pas ≤ MAX_STEP).
	frequency : raideur en Hz (≈ vitesse de rattrapage) ; damping : 1 = critique (pas de rebond),
	< 1 = léger rebond. Renvoie la nouvelle position et la nouvelle vitesse.
]]
function CompanionLogic.Spring(
	position: Vector3,
	velocity: Vector3,
	target: Vector3,
	dt: number,
	frequency: number,
	damping: number
): (Vector3, Vector3)
	if dt <= 0 then
		return position, velocity
	end
	local omega = 2 * math.pi * frequency
	local steps = math.max(1, math.ceil(dt / CompanionLogic.MAX_STEP))
	local h = dt / steps
	local p, v = position, velocity
	for _ = 1, steps do
		local accel = (target - p) * (omega * omega) - v * (2 * damping * omega)
		v += accel * h
		p += v * h
	end
	return p, v
end

-- Facteur d'interpolation indépendant du nombre d'images par seconde (lissage exponentiel).
function CompanionLogic.Damp(rate: number, dt: number): number
	return 1 - math.exp(-rate * math.max(dt, 0))
end

-- Interpole deux angles (radians) par le plus court chemin.
function CompanionLogic.LerpAngle(from: number, to: number, alpha: number): number
	local delta = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + delta * alpha
end

-- Lacet (rotation autour de Y) dont le LookVector pointe vers `direction` (composante Y ignorée).
function CompanionLogic.YawOf(direction: Vector3): number?
	if direction.X * direction.X + direction.Z * direction.Z < 1e-6 then
		return nil
	end
	return math.atan2(-direction.X, -direction.Z)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.new(0, 0, 0)
	end
	return f.Unit
end

--[[
	Position visée pour la BASE du drone.
	- Suivi : à droite du joueur vu de la caméra, un peu devant (reste dans le champ sans masquer
	  le personnage), à hauteur d'épaule.
	- Guide (`guide` = direction vers le prochain checkpoint) : quelques studs devant, dans cette
	  direction, un peu plus haut.
]]
function CompanionLogic.FollowTarget(root: Vector3, cameraRight: Vector3, cameraLook: Vector3, guide: Vector3?): Vector3
	local up = Vector3.new(0, 1, 0)
	if guide then
		local dir = flat(guide)
		if dir.Magnitude > 0.5 then
			return root + dir * 6 + flat(cameraRight) * 1.2 + up * 1.4
		end
	end
	return root + flat(cameraRight) * 3 + flat(cameraLook) * 0.6 + up * 0.7
end

-- Caméra plus près que ça de la tête : vue à la 1re personne -> compagnon caché.
CompanionLogic.FIRST_PERSON = 1.6
-- Caméra à moins de FADE_NEAR studs du drone : il s'efface (entièrement à FADE_NEAR − FADE_SPAN).
CompanionLogic.FADE_NEAR = 4
CompanionLogic.FADE_SPAN = 2.5

--[[
	Transparence voulue (0 = visible, 1 = caché) selon la distance caméra -> tête et caméra ->
	drone. Il ne s'efface que s'il bouche la vue : 1re personne, ou caméra collée à lui. Avec le
	zoom par défaut de Roblox (12,5 studs), il reste toujours entièrement visible.
]]
function CompanionLogic.WantFade(eyeDistance: number, camDistance: number): number
	if eyeDistance < CompanionLogic.FIRST_PERSON then
		return 1
	end
	return math.clamp((CompanionLogic.FADE_NEAR - camDistance) / CompanionLogic.FADE_SPAN, 0, 1)
end

-- Longueur max de la flèche-rayon du guide (studs).
CompanionLogic.BEAM_LENGTH = 7

--[[
	Direction de la flèche-rayon vers le prochain checkpoint (`toTarget` = checkpoint − drone).
	- En vue directe (`clear`) : droit sur lui, montée ou descente comprise.
	- Caché (mur, plafond, plateforme) : à l'HORIZONTALE dans sa direction — jamais à travers un
	  mur vers le haut, ni plongée vers le vide.
	nil = rien à montrer (déjà dessus, ou juste au-dessus / en dessous et caché).
]]
function CompanionLogic.BeamDirection(toTarget: Vector3, clear: boolean): Vector3?
	if clear then
		return if toTarget.Magnitude > 0.1 then toTarget else nil
	end
	local horizontal = Vector3.new(toTarget.X, 0, toTarget.Z)
	return if horizontal.Magnitude > 0.5 then horizontal else nil
end

------------------------------------------------------------------------------------
-- Progression : quand guider ?
------------------------------------------------------------------------------------

export type Tracker = {
	Stage: number,
	Best: number, -- plus petite distance au prochain checkpoint depuis le dernier progrès
	Since: number, -- heure du dernier progrès
}

function CompanionLogic.NewTracker(now: number): Tracker
	return { Stage = -1, Best = math.huge, Since = now }
end

-- Met à jour le suivi : nouvelle étape, ou `distance` (au prochain checkpoint) nettement réduite.
function CompanionLogic.Track(tracker: Tracker, stage: number, distance: number?, now: number)
	if stage ~= tracker.Stage then
		tracker.Stage = stage
		tracker.Best = distance or math.huge
		tracker.Since = now
		return
	end
	if distance then
		if tracker.Best == math.huge then
			tracker.Best = distance
		elseif distance < tracker.Best - CompanionLogic.PROGRESS_STEP then
			tracker.Best = distance
			tracker.Since = now
		end
	end
end

-- Secondes écoulées sans progrès.
function CompanionLogic.Idle(tracker: Tracker, now: number): number
	return now - tracker.Since
end

-- Faut-il montrer le chemin ? `blocked` : incident, mini-jeu, lobby… (on ne distrait pas).
function CompanionLogic.ShouldGuide(tracker: Tracker, now: number, distance: number?, blocked: boolean): boolean
	if blocked or distance == nil then
		return false
	end
	if distance < CompanionLogic.GUIDE_MIN_DISTANCE then
		return false
	end
	return CompanionLogic.Idle(tracker, now) >= CompanionLogic.GUIDE_AFTER
end

------------------------------------------------------------------------------------
-- Émotions
------------------------------------------------------------------------------------

export type Mood = "Idle" | "Happy" | "Panic" | "Frozen" | "Sad" | "Celebrate" | "Guide"

-- Durée (s) des réactions ponctuelles.
CompanionLogic.DURATION = table.freeze({
	Happy = 2.5,
	Sad = 3,
	Celebrate = 5,
})

export type MoodInput = {
	Now: number,
	Until: { [string]: number }, -- réaction ponctuelle -> heure de fin
	IncidentKind: string, -- "" si aucun
	IncidentPhase: string, -- "" | "Warn" | "Active"
	Guiding: boolean,
}

local function timed(input: MoodInput, mood: string): boolean
	local finish = input.Until[mood]
	return finish ~= nil and input.Now < finish
end

-- Émotion à afficher, par priorité.
function CompanionLogic.Mood(input: MoodInput): Mood
	if timed(input, "Celebrate") then
		return "Celebrate"
	elseif timed(input, "Sad") then
		return "Sad"
	elseif input.IncidentKind == "Freeze" and input.IncidentPhase == "Active" then
		return "Frozen"
	elseif input.IncidentPhase == "Warn" or input.IncidentPhase == "Active" then
		return "Panic"
	elseif timed(input, "Happy") then
		return "Happy"
	elseif input.Guiding then
		return "Guide"
	end
	return "Idle"
end

------------------------------------------------------------------------------------
-- Bulle de dialogue : au-dessus d'Anga ou en bas de l'écran
------------------------------------------------------------------------------------

-- La bulle peut-elle s'afficher au-dessus d'Anga ?
function CompanionLogic.WantsWorldBubble(inRun: boolean, busy: boolean, shown: boolean, onScreen: boolean): boolean
	return inRun and not busy and shown and onScreen
end

export type Debounce = { Value: boolean, Pending: boolean, Since: number }

function CompanionLogic.NewDebounce(value: boolean): Debounce
	return { Value = value, Pending = value, Since = 0 }
end

-- Valeur stable : un changement n'est retenu qu'après `delay` secondes sans revenir en arrière.
function CompanionLogic.Settle(debounce: Debounce, value: boolean, now: number, delay: number): boolean
	if value ~= debounce.Pending then
		debounce.Pending = value
		debounce.Since = now
	end
	if debounce.Pending ~= debounce.Value and now - debounce.Since >= delay then
		debounce.Value = debounce.Pending
	end
	return debounce.Value
end

return CompanionLogic
