--!strict
--[[
	JumpTiming : logique pure des sensations de saut (testée dans Lune, tests/jump.spec.luau).
	Utilisée par le client (Controllers/JumpAssist) avec l'état du Humanoid.

	- Coyote time : on peut encore sauter COYOTE s après avoir QUITTÉ un bord en marchant
	  (pas après un saut, pas en étant propulsé vers le haut : trampoline, vent…).
	- Saut mémorisé : un appui fait jusqu'à BUFFER s avant d'atterrir déclenche le saut à
	  l'atterrissage.
	- Jamais de double saut : au plus un saut « coyote » par passage en l'air, et aucun après un
	  vrai saut.

	Les temps sont des secondes (os.clock côté client).
]]

export type State = {
	Grounded: boolean,
	LeftAt: number, -- quitté le sol (sans sauter) à cet instant
	Jumped: boolean, -- ce passage en l'air a commencé par un saut (ou un saut coyote)
	CoyoteUsed: boolean,
	BufferedAt: number, -- dernier appui en l'air (-inf = aucun)
}

-- Décision prise sur un appui de saut.
export type Action = "None" | "Coyote" | "Buffered"

local JumpTiming = {}

JumpTiming.COYOTE = 0.12
JumpTiming.BUFFER = 0.12
-- Au-delà de cette vitesse verticale (studs/s), on est propulsé : pas de coyote.
JumpTiming.MAX_RISE_SPEED = 2

function JumpTiming.new(): State
	return {
		Grounded = true,
		LeftAt = -math.huge,
		Jumped = false,
		CoyoteUsed = false,
		BufferedAt = -math.huge,
	}
end

-- Le personnage vient de sauter (état Jumping : saut normal, trampoline, saut assisté).
function JumpTiming.OnJumped(state: State, _now: number)
	state.Grounded = false
	state.Jumped = true
	state.BufferedAt = -math.huge
end

-- Le personnage est en l'air sans avoir sauté (a quitté un bord, poussé…).
function JumpTiming.OnAirborne(state: State, now: number)
	if not state.Grounded then
		return -- déjà en l'air (ex. Jumping -> Freefall) : on garde l'instant de départ
	end
	state.Grounded = false
	state.Jumped = false
	state.CoyoteUsed = false
	state.LeftAt = now
end

-- Le personnage touche le sol. Renvoie true s'il faut déclencher le saut mémorisé.
function JumpTiming.OnLanded(state: State, now: number): boolean
	if state.Grounded then
		return false
	end
	state.Grounded = true
	state.Jumped = false
	state.CoyoteUsed = false
	local buffered = now - state.BufferedAt <= JumpTiming.BUFFER
	state.BufferedAt = -math.huge
	return buffered
end

-- Appui sur saut (JumpRequest : clavier, manette, bouton tactile). Au sol, le moteur de Roblox
-- saute tout seul : rien à faire. En l'air : saut coyote si permis, sinon l'appui est mémorisé.
function JumpTiming.OnRequest(state: State, now: number, verticalSpeed: number): Action
	if state.Grounded then
		return "None"
	end
	if
		not state.Jumped
		and not state.CoyoteUsed
		and now - state.LeftAt <= JumpTiming.COYOTE
		and verticalSpeed <= JumpTiming.MAX_RISE_SPEED
	then
		state.CoyoteUsed = true
		state.Jumped = true
		return "Coyote"
	end
	state.BufferedAt = now
	return "Buffered"
end

return table.freeze(JumpTiming)
