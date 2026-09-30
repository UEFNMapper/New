-- Tests du combat final contre LAGZ (monde 7) : logique pure (Util/BossLogic, autorité de
-- BossService) + contrat entre serveur, client et mini-jeu, vérifié par lecture du code source.
-- La géométrie de l'arène est vérifiée à la construction (asserts de Worlds/W7Arena, tower.spec).
local BossLogic = Shim.load("src/shared/Util/BossLogic.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")

local PHASE = BossLogic.Phase
local W = BossLogic.WORLD
local ARENA_STAGE = Tower.TerminalStage(W) - 1 -- checkpoint à l'entrée de l'arène (34)
local ROOM_STAGE = Tower.TerminalStage(W) -- checkpoint de la salle du terminal (35)

-- Entrées d'une image serveur (par défaut : joueur vivant dans l'arène, prêt à combattre).
local function inputs(now: number, overrides: { [string]: any }?): any
	local input = {
		Now = now,
		Stage = ARENA_STAGE,
		Cleared = W - 1,
		AtLobby = false,
		Alive = true,
		InArena = true,
	}
	for key, value in overrides or {} do
		input[key] = value
	end
	return input
end

-- Amène un état neuf en phase 2 (prises) à l'instant renvoyé.
local function toPlugs(): (any, number)
	local state = BossLogic.New(0)
	Expect.equal(BossLogic.Step(state, inputs(1)), "Start", "entrée dans l'arène")
	local t = 1 + BossLogic.LASER_SECONDS
	Expect.equal(BossLogic.Step(state, inputs(t)), "Plugs", "fin de la phase 1")
	return state, t
end

local function source(path: string): string
	return Fs.readFile(path)
end

return {
	["combat complet : attente, lasers, prises (ordre libre), terminal, vaincu"] = function()
		local state = BossLogic.New(0)
		Expect.equal(state.Phase, PHASE.Idle, "état initial")
		-- Hors de l'arène : LAGZ attend
		Expect.equal(BossLogic.Step(state, inputs(0.5, { InArena = false })), nil, "pas de combat hors de l'arène")
		Expect.equal(state.Phase, PHASE.Idle, "toujours en attente")
		-- Phase 1 : survie pendant LASER_SECONDS
		Expect.equal(BossLogic.Step(state, inputs(1)), "Start", "le combat démarre")
		Expect.equal(state.Phase, PHASE.Lasers, "phase 1")
		Expect.near(BossLogic.Remaining(state.Phase, state.Since, 11), BossLogic.LASER_SECONDS - 10, 1e-9, "chrono")
		Expect.equal(BossLogic.Step(state, inputs(BossLogic.LASER_SECONDS)), nil, "phase 1 pas encore finie")
		Expect.equal(BossLogic.Step(state, inputs(1 + BossLogic.LASER_SECONDS)), "Plugs", "phase 2")
		Expect.equal(state.Phase, PHASE.Plugs, "phase 2")
		Expect.equal(BossLogic.Remaining(state.Phase, state.Since, 100), 0, "plus de chrono en phase 2")
		-- Phase 2 : les prises dans le désordre
		local t = 2 + BossLogic.LASER_SECONDS
		Expect.equal(select(2, BossLogic.Plug(state, 3, 2, t)), "Plug", "prise 3")
		Expect.equal(select(2, BossLogic.Plug(state, 1, 2, t)), "Plug", "prise 1")
		Expect.equal(BossLogic.TerminalOpen(state), false, "terminal fermé à 2/3")
		local ok, event = BossLogic.Plug(state, 2, 2, t)
		Expect.truthy(ok, "prise 2 acceptée")
		Expect.equal(event, "Terminal", "3/3 : bouclier détruit")
		Expect.equal(state.Phase, PHASE.Terminal, "phase 3")
		Expect.truthy(BossLogic.TerminalOpen(state), "terminal final ouvert")
		-- Le joueur entre dans la salle (checkpoint 35) : la phase 3 est gardée
		Expect.equal(BossLogic.Step(state, inputs(t + 5, { Stage = ROOM_STAGE, InArena = false })), nil, "salle")
		Expect.truthy(BossLogic.TerminalOpen(state), "toujours ouvert dans la salle")
		-- Terminal réussi : ProgressService.ClearWorld(7)
		Expect.equal(BossLogic.Defeat(state, t + 40), "Defeated", "LAGZ vaincu")
		Expect.equal(BossLogic.Defeat(state, t + 41), nil, "une seule fois")
		Expect.equal(BossLogic.Step(state, inputs(t + 42, { Stage = ROOM_STAGE, Cleared = W })), nil, "reste vaincu")
		Expect.equal(state.Phase, PHASE.Defeated, "phase 4")
	end,

	["seuls les joueurs au bout du monde 7 (mondes 1..6 nettoyés) affrontent LAGZ"] = function()
		Expect.truthy(BossLogic.Eligible(ARENA_STAGE, W - 1), "checkpoint de l'arène")
		Expect.truthy(BossLogic.Eligible(ROOM_STAGE, W - 1), "salle du terminal (retour dans l'arène)")
		Expect.truthy(not BossLogic.Eligible(ARENA_STAGE - 1, W - 1), "étape précédente")
		Expect.truthy(not BossLogic.Eligible(ARENA_STAGE, W - 2), "monde 6 pas nettoyé")
		Expect.truthy(not BossLogic.Eligible(ARENA_STAGE, W), "déjà vaincu")
		for _, overrides in
			{
				{ Stage = ARENA_STAGE - 1 },
				{ Cleared = W - 2 },
				{ AtLobby = true },
				{ Alive = false },
			}
		do
			local state = BossLogic.New(0)
			Expect.equal(BossLogic.Step(state, inputs(1, overrides)), nil, "pas de combat")
			Expect.equal(state.Phase, PHASE.Idle, "reste en attente")
		end
		-- Monde 7 déjà nettoyé (reconnexion) : LAGZ n'est plus là
		local state = BossLogic.New(0)
		Expect.equal(BossLogic.Step(state, inputs(1, { Cleared = W, Stage = ROOM_STAGE })), "Defeated", "vaincu")
		-- Nouvelle ascension (données remises à zéro) : il revient
		Expect.equal(BossLogic.Step(state, inputs(2, { Cleared = 0, Stage = 1 })), "Reset", "remis à zéro")
		Expect.equal(state.Phase, PHASE.Idle, "LAGZ est de retour")
	end,

	["mort ou fuite pendant les phases 1–2 : on recommence ; la phase 3 est gardée"] = function()
		-- Mort en phase 1 (GameEvents.Died)
		local state = BossLogic.New(0)
		BossLogic.Step(state, inputs(1))
		Expect.equal(BossLogic.Died(state, 3), "Abort", "mort en phase 1")
		Expect.equal(state.Phase, PHASE.Idle, "retour en attente")
		-- Mort vue par l'image serveur (Alive = false) en phase 2 : prises perdues
		local plugs, t = toPlugs()
		BossLogic.Plug(plugs, 1, 1, t)
		Expect.equal(BossLogic.Step(plugs, inputs(t + 1, { Alive = false })), "Abort", "mort en phase 2")
		Expect.equal(BossLogic.PlugCount(plugs), 0, "prises remises à zéro")
		-- Sortie de l'arène : tolérance LEAVE_GRACE, puis abandon
		local runner = BossLogic.New(0)
		BossLogic.Step(runner, inputs(1))
		Expect.equal(BossLogic.Step(runner, inputs(2, { InArena = false })), nil, "sortie brève")
		Expect.equal(
			BossLogic.Step(runner, inputs(2 + BossLogic.LEAVE_GRACE * 0.5, { InArena = false })),
			nil,
			"encore toléré"
		)
		Expect.equal(BossLogic.Step(runner, inputs(3 + BossLogic.LEAVE_GRACE * 0.5)), nil, "de retour")
		Expect.equal(runner.OutsideSince, nil, "tolérance remise à zéro au retour")
		Expect.equal(BossLogic.Step(runner, inputs(5, { InArena = false })), nil, "ressort")
		Expect.equal(
			BossLogic.Step(runner, inputs(5.1 + BossLogic.LEAVE_GRACE, { InArena = false })),
			"Abort",
			"trop longtemps dehors"
		)
		-- Retour au lobby : remis à zéro, quelle que soit la phase
		local lobby, t2 = toPlugs()
		Expect.equal(BossLogic.Step(lobby, inputs(t2 + 1, { AtLobby = true })), "Reset", "lobby")
		-- Phase 3 : la mort ne remet pas le bouclier
		local shieldDown, t3 = toPlugs()
		for i = 1, BossLogic.PLUG_COUNT do
			BossLogic.Plug(shieldDown, i, 0, t3)
		end
		Expect.equal(shieldDown.Phase, PHASE.Terminal, "phase 3")
		Expect.equal(BossLogic.Died(shieldDown, t3 + 1), nil, "mort en phase 3 : rien ne change")
		Expect.equal(
			BossLogic.Step(shieldDown, inputs(t3 + 2, { Alive = false, InArena = false })),
			nil,
			"réapparition"
		)
		Expect.truthy(BossLogic.TerminalOpen(shieldDown), "terminal toujours ouvert")
		Expect.equal(BossLogic.Step(shieldDown, inputs(t3 + 3, { AtLobby = true })), "Reset", "sauf au lobby")
	end,

	["prises antivirus : validées par le serveur (phase, index, une fois, distance)"] = function()
		local idle = BossLogic.New(0)
		Expect.equal(select(2, BossLogic.Plug(idle, 1, 0, 1)), "phase", "hors phase 2 (attente)")
		BossLogic.Step(idle, inputs(1))
		Expect.equal(select(2, BossLogic.Plug(idle, 1, 0, 2)), "phase", "hors phase 2 (lasers)")
		local state, t = toPlugs()
		for _, index in { 0, 4, 1.5, -1, 0 / 0 } do
			local ok, reason = BossLogic.Plug(state, index, 0, t)
			Expect.truthy(not ok and reason == "index", `index {index} refusé`)
		end
		local ok, reason = BossLogic.Plug(state, 2, BossLogic.PLUG_REACH + 0.1, t)
		Expect.truthy(not ok and reason == "distance", "trop loin de la prise")
		ok, reason = BossLogic.Plug(state, 2, math.huge, t)
		Expect.truthy(not ok and reason == "distance", "sans personnage")
		ok, reason = BossLogic.Plug(state, 2, 0 / 0, t)
		Expect.truthy(not ok and reason == "distance", "distance invalide")
		Expect.truthy((BossLogic.Plug(state, 2, BossLogic.PLUG_REACH, t)), "à portée")
		ok, reason = BossLogic.Plug(state, 2, 0, t)
		Expect.truthy(not ok and reason == "done", "déjà branchée")
		Expect.equal(BossLogic.PlugCount(state), 1, "une seule prise comptée")
		Expect.equal(BossLogic.PlugMask(state), 2, "masque : bit de la prise 2")
		Expect.truthy(
			BossLogic.MaskHas(2, 2) and not BossLogic.MaskHas(2, 1) and not BossLogic.MaskHas(2, 3),
			"MaskHas"
		)
		BossLogic.Plug(state, 3, 0, t)
		Expect.equal(BossLogic.PlugMask(state), 6, "masque 2 + 4")
		BossLogic.Plug(state, 1, 0, t)
		Expect.equal(BossLogic.PlugMask(state), 7, "3/3")
		Expect.equal(state.Phase, PHASE.Terminal, "bouclier détruit")
	end,

	["pièges de l'arène par phase, zone de l'arène"] = function()
		Expect.truthy(BossLogic.PhaseActive("1", PHASE.Lasers), "laser en phase 1")
		Expect.truthy(not BossLogic.PhaseActive("1", PHASE.Plugs), "laser coupé en phase 2")
		Expect.truthy(BossLogic.PhaseActive("12", PHASE.Plugs), "curseur en phase 2")
		Expect.truthy(BossLogic.PhaseActive("2", PHASE.Plugs), "virus en phase 2")
		for _, phase in { PHASE.Idle, PHASE.Terminal, PHASE.Defeated } do
			Expect.truthy(not BossLogic.PhaseActive("12", phase), `rien d'actif hors combat ({phase})`)
		end
		Expect.truthy(not BossLogic.PhaseActive(nil, PHASE.Lasers), "attribut absent")
		Expect.truthy(BossLogic.Fighting(PHASE.Lasers) and BossLogic.Fighting(PHASE.Plugs), "combat")
		local center, size = Vector3.new(0, 10, 0), Vector3.new(20, 10, 30)
		Expect.truthy(BossLogic.InArena(center, size, Vector3.new(9.9, 14, -14.9)), "dans la boîte")
		Expect.truthy(not BossLogic.InArena(center, size, Vector3.new(10.1, 10, 0)), "dehors en X")
		Expect.truthy(not BossLogic.InArena(center, size, Vector3.new(0, 15.1, 0)), "au-dessus")
		Expect.truthy(not BossLogic.InArena(center, size, Vector3.new(0, 10, 15.1)), "dehors en Z")
		-- Une ascension type : 25 s de lasers + prises + mini-jeu tient dans 1 à 2 minutes
		Expect.between(BossLogic.LASER_SECONDS, 15, 40, "durée de la phase 1")
	end,

	["contrat : serveur, client, terminal final (difficulté 8), démarrage"] = function()
		local service = source("src/server/Services/BossService.luau")
		local controller = source("src/client/Controllers/BossController.luau")
		for _, attribute in { "BossPhase", "BossSince", "BossPlugs" } do
			Expect.truthy(string.find(service, `"{attribute}"`, 1, true) ~= nil, `serveur : {attribute}`)
			Expect.truthy(string.find(controller, `"{attribute}"`, 1, true) ~= nil, `client : {attribute}`)
		end
		for _, tag in { "BossArena", "BossPlug" } do
			Expect.truthy(string.find(service, `"{tag}"`, 1, true) ~= nil, `serveur : tag {tag}`)
		end
		local arena = source("src/server/World/Tower/Worlds/W7Arena.luau")
		for _, tag in { "BossArena", "BossPlug", "BossBarrier", "BossLagz", "BossShield", "BossTrap" } do
			Expect.truthy(string.find(arena, `"{tag}"`, 1, true) ~= nil, `arène : tag {tag}`)
			if tag ~= "BossArena" then
				Expect.truthy(string.find(controller, `"{tag}"`, 1, true) ~= nil, `client : tag {tag}`)
			end
		end
		-- Terminal du monde 7 : fermé tant que le bouclier tient, puis Firewall boss (difficulté 8)
		local minigames = source("src/server/Services/MinigameService.luau")
		Expect.truthy(string.find(minigames, "BossService.TerminalOpen(session)", 1, true) ~= nil, "garde serveur")
		local interactions = source("src/client/Controllers/Interactions.luau")
		Expect.truthy(string.find(interactions, "BossLogic.BOSS_DIFFICULTY", 1, true) ~= nil, "difficulté 8")
		Expect.equal(BossLogic.BOSS_DIFFICULTY, 8, "Firewall contre LAGZ")
		Expect.equal(Tower.Worlds[W].Minigame, "Firewall", "mini-jeu du monde 7")
		-- Démarrage : après ProgressService (tour construite), avant DataService (sessions)
		local main = source("src/server/Main.server.luau")
		local order = string.match(main, "local ORDER = (%b{})") or ""
		local progress = string.find(order, '"ProgressService"', 1, true)
		local boss = string.find(order, '"BossService"', 1, true)
		local data = string.find(order, '"DataService"', 1, true)
		Expect.truthy(progress and boss and data and progress < boss and boss < data, "ordre des services")
		Expect.truthy(
			string.find(source("src/client/Main.client.luau"), "Controllers.BossController", 1, true) ~= nil,
			"BossController démarré"
		)
	end,
}
