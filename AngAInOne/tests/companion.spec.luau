-- Compagnon (mini-Anga sur son drone) : logique pure — ressort, quand guider, émotions, bulle.
local Logic = Shim.load("src/client/Controllers/CompanionLogic.luau")

local function run(position: any, velocity: any, target: any, seconds: number, fps: number, frequency: number)
	local p, v = position, velocity
	local frames = math.floor(seconds * fps)
	for _ = 1, frames do
		p, v = Logic.Spring(p, v, target, 1 / fps, frequency, 0.8)
	end
	return p, v
end

local function mood(overrides: { [string]: any }): string
	local input = {
		Now = 100,
		Until = {},
		IncidentKind = "",
		IncidentPhase = "",
		Guiding = false,
	}
	for key, value in overrides do
		(input :: any)[key] = value
	end
	return Logic.Mood(input)
end

return {
	["ressort : rejoint la cible sans diverger, même à 10 images/s"] = function()
		local target = Vector3.new(10, 4, -6)
		for _, fps in { 10, 30, 60, 144 } do
			local p, v = run(Vector3.zero, Vector3.zero, target, 3, fps, 1.6)
			Expect.truthy((p - target).Magnitude < 0.05, `proche de la cible à {fps} img/s`)
			Expect.truthy(v.Magnitude < 0.5, `presque à l'arrêt à {fps} img/s`)
		end
	end,
	["ressort : lisse (pas de téléportation) et léger dépassement seulement"] = function()
		local target = Vector3.new(10, 0, 0)
		local p, v = Logic.Spring(Vector3.zero, Vector3.zero, target, 1 / 60, 1.6, 0.8)
		Expect.truthy(p.X > 0 and p.X < 0.5, "le premier pas ne saute pas à la cible")
		local peak = 0
		for _ = 1, 300 do
			p, v = Logic.Spring(p, v, target, 1 / 60, 1.6, 0.8)
			peak = math.max(peak, p.X)
		end
		Expect.between(peak, 10, 10.6, "dépassement faible (amortissement 0,8)")
		local same, still = Logic.Spring(target, Vector3.zero, target, 0, 1.6, 0.8)
		Expect.near((same - target).Magnitude + still.Magnitude, 0, 1e-9, "dt = 0 : rien ne bouge")
	end,
	["angles : plus court chemin et lacet vers une direction"] = function()
		Expect.near(Logic.LerpAngle(math.rad(170), math.rad(-170), 0.5), math.rad(180), 1e-6, "passe par 180°")
		Expect.near(Logic.LerpAngle(0, 1, 1), 1, 1e-9)
		Expect.near(Logic.YawOf(Vector3.new(0, 0, -1)) :: number, 0, 1e-9, "vers -Z : lacet 0")
		Expect.near(Logic.YawOf(Vector3.new(1, 0, 0)) :: number, -math.pi / 2, 1e-9, "vers +X")
		Expect.equal(Logic.YawOf(Vector3.new(0, 5, 0)), nil, "vertical : pas de lacet")
		Expect.between(Logic.Damp(5, 1 / 60), 0.07, 0.09)
		Expect.equal(Logic.Damp(5, 0), 0)
	end,
	["suivi : épaule droite vue caméra, ou devant vers le checkpoint"] = function()
		local root = Vector3.new(0, 10, 0)
		local right, look = Vector3.new(1, 0, 0), Vector3.new(0, -0.5, -1).Unit
		local goal = Logic.FollowTarget(root, right, look, nil)
		Expect.truthy(goal.X > 2.5, "à droite")
		Expect.truthy(goal.Y > root.Y, "à hauteur d'épaule")
		Expect.truthy(goal.Z < root.Z, "un peu devant (dans le champ)")
		local guide = Logic.FollowTarget(root, right, look, Vector3.new(0, 30, 40))
		Expect.truthy(guide.Z > 4, "vole vers le checkpoint (+Z)")
		Expect.near(
			Logic.FollowTarget(root, right, look, Vector3.new(0, 20, 0)).X,
			goal.X,
			1e-6,
			"direction verticale : suivi normal"
		)
	end,
	["guide : seulement après 20 s sans progrès, loin du checkpoint, hors incident"] = function()
		local t = Logic.NewTracker(0)
		Logic.Track(t, 3, 80, 0)
		Expect.equal(Logic.ShouldGuide(t, 10, 80, false), false, "10 s : trop tôt")
		Logic.Track(t, 3, 78, 19)
		Expect.equal(Logic.ShouldGuide(t, 19.9, 78, false), false, "petits pas : pas un progrès, mais < 20 s")
		Expect.equal(Logic.ShouldGuide(t, 20.5, 78, false), true, "20 s sans progrès : guide")
		Expect.equal(Logic.ShouldGuide(t, 20.5, 78, true), false, "incident / mini-jeu : pas de guide")
		Expect.equal(Logic.ShouldGuide(t, 20.5, nil, false), false, "checkpoint inconnu (streaming)")
		Expect.equal(Logic.ShouldGuide(t, 20.5, 10, false), false, "déjà tout près")
		-- se rapprocher franchement compte comme un progrès
		Logic.Track(t, 3, 60, 21)
		Expect.equal(Logic.ShouldGuide(t, 30, 60, false), false, "progrès à 21 s : on attend encore")
		Expect.equal(Logic.ShouldGuide(t, 41.5, 60, false), true, "puis de nouveau 20 s")
		-- nouvelle étape : tout repart de zéro
		Logic.Track(t, 4, 120, 42)
		Expect.equal(Logic.ShouldGuide(t, 50, 120, false), false, "nouvelle étape")
		Expect.near(Logic.Idle(t, 50), 8, 1e-9)
	end,
	["guide : reculer ne remet pas le compteur à zéro"] = function()
		local t = Logic.NewTracker(0)
		Logic.Track(t, 1, 50, 0)
		Logic.Track(t, 1, 90, 5) -- tombé plus bas
		Logic.Track(t, 1, 70, 12) -- remonte, mais pas mieux qu'avant
		Expect.equal(Logic.ShouldGuide(t, 21, 70, false), true)
	end,
	["émotions : priorités (fête > triste > gel > panique > joie > guide)"] = function()
		Expect.equal(mood({}), "Idle")
		Expect.equal(mood({ Guiding = true }), "Guide")
		Expect.equal(mood({ Guiding = true, Until = { Happy = 101 } }), "Happy")
		Expect.equal(mood({ Until = { Happy = 99 } }), "Idle", "réaction terminée")
		Expect.equal(mood({ IncidentKind = "Lag", IncidentPhase = "Warn", Until = { Happy = 101 } }), "Panic")
		Expect.equal(mood({ IncidentKind = "Freeze", IncidentPhase = "Warn" }), "Panic", "annonce du FREEZE")
		Expect.equal(mood({ IncidentKind = "Freeze", IncidentPhase = "Active" }), "Frozen")
		Expect.equal(mood({ IncidentKind = "Blackout", IncidentPhase = "Active" }), "Panic")
		Expect.equal(mood({ IncidentKind = "Freeze", IncidentPhase = "Active", Until = { Sad = 102 } }), "Sad")
		Expect.equal(mood({ Until = { Sad = 102, Celebrate = 103 } }), "Celebrate")
		Expect.truthy(Logic.DURATION.Happy > 0 and Logic.DURATION.Sad > 0 and Logic.DURATION.Celebrate > 0)
	end,
	["bulle : au-dessus d'Anga seulement en ascension, visible, à l'écran, hors mini-jeu"] = function()
		Expect.equal(Logic.WantsWorldBubble(true, false, true, true), true)
		Expect.equal(Logic.WantsWorldBubble(false, false, true, true), false, "lobby")
		Expect.equal(Logic.WantsWorldBubble(true, true, true, true), false, "mini-jeu")
		Expect.equal(Logic.WantsWorldBubble(true, false, false, true), false, "caché (1re personne)")
		Expect.equal(Logic.WantsWorldBubble(true, false, true, false), false, "hors champ")
	end,
	["bulle : bascule stable (pas de clignotement)"] = function()
		local d = Logic.NewDebounce(false)
		Expect.equal(Logic.Settle(d, true, 0, 0.3), false, "pas tout de suite")
		Expect.equal(Logic.Settle(d, false, 0.1, 0.3), false, "aller-retour ignoré")
		Expect.equal(Logic.Settle(d, true, 0.2, 0.3), false)
		Expect.equal(Logic.Settle(d, true, 0.45, 0.3), false, "0,25 s : encore en attente")
		Expect.equal(Logic.Settle(d, true, 0.55, 0.3), true, "stable 0,3 s : bascule")
		Expect.equal(Logic.Settle(d, false, 0.6, 0), false, "délai nul : immédiat")
	end,
	["visibilité : jamais effacé au zoom par défaut (lobby compris), caché en 1re personne"] = function()
		-- Caméra Roblox par défaut : 12,5 studs derrière la tête, légèrement plongeante.
		local root = Vector3.new(0, 5, 0)
		local head = root + Vector3.new(0, 1.5, 0)
		for _, yaw in { 0, 0.8, 2, -2.5 } do
			for _, zoom in { 12.5, 8, 5 } do
				local look = Vector3.new(-math.sin(yaw), -0.35, -math.cos(yaw)).Unit
				local camera = head - look * zoom
				local right = look:Cross(Vector3.new(0, 1, 0)).Unit
				local drone = Logic.FollowTarget(root, right, look, nil)
				local fade = Logic.WantFade((camera - head).Magnitude, (camera - drone).Magnitude)
				Expect.equal(fade, 0, `visible (zoom {zoom}, lacet {yaw})`)
				Expect.truthy((camera - drone).Magnitude > 4, "à bonne distance de la caméra")
			end
		end
		Expect.equal(Logic.WantFade(0.5, 3), 1, "1re personne : caché")
		Expect.equal(Logic.WantFade(3, 1), 1, "caméra collée au drone : caché")
		Expect.between(Logic.WantFade(3, 3), 0.3, 0.5, "entre les deux : fondu")
	end,
	["flèche du guide : droit si en vue, sinon à l'horizontale (jamais à travers un mur ni vers le vide)"] = function()
		local up = Vector3.new(3, 12, 4)
		Expect.near((Logic.BeamDirection(up, true) :: any - up).Magnitude, 0, 1e-9, "en vue : droit dessus")
		local hidden = Logic.BeamDirection(up, false) :: any
		Expect.near(hidden.Y, 0, 1e-9, "caché : à plat")
		Expect.near(hidden.Unit.X, 0.6, 1e-6, "caché : même direction horizontale")
		local down = Logic.BeamDirection(Vector3.new(0, -40, 10), false) :: any
		Expect.near(down.Y, 0, 1e-9, "checkpoint caché plus bas : ne plonge pas vers le vide")
		Expect.equal(
			Logic.BeamDirection(Vector3.new(0, 30, 0.2), false),
			nil,
			"juste au-dessus et caché : pas de flèche"
		)
		Expect.equal(Logic.BeamDirection(Vector3.new(0, 0.05, 0), true), nil, "déjà dessus")
		Expect.truthy(Logic.BEAM_LENGTH > 0 and Logic.BEAM_LENGTH <= 10, "flèche courte")
	end,
}
