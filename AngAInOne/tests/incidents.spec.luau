-- Tests des incidents de LAGZ (programmation pure) et de la « Performance du PC ».
local IncidentSchedule = Shim.load("src/shared/Util/IncidentSchedule.luau")
local PcHealth = Shim.load("src/shared/Util/PcHealth.luau")
local Incidents = Shim.load("src/shared/Config/Incidents.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")

-- Suite pseudo-aléatoire reproductible dans [0, 1[.
local function lcg(seed: number): () -> number
	local value = seed
	return function(): number
		value = (value * 1103515245 + 12345) % 2147483648
		return value / 2147483648
	end
end

-- Simule un monde de `from` à `to` (pas de 0,2 s) ; `occupied(t)` dit si quelqu'un y court.
-- Renvoie la liste des incidents annoncés { Kind, Warn, Start, End } et l'état final.
local function simulate(world: number, from: number, to: number, occupied: (number) -> boolean, seed: number?)
	local state = IncidentSchedule.NewState()
	local roll = lcg(seed or 7)
	local list = {}
	local t = from
	while t <= to do
		local event = IncidentSchedule.Step(state, world, t, occupied(t), roll)
		if event == "Warn" then
			table.insert(list, { Kind = state.Kind, Warn = state.Warn, Start = state.Start, End = state.End })
		end
		t += 0.2
	end
	return list, state
end

local function always(_t: number): boolean
	return true
end

return {
	["monde vide : aucun incident"] = function()
		local list, state = simulate(1, 0, 2000, function()
			return false
		end)
		Expect.equal(#list, 0)
		Expect.equal(state.Kind, "")
	end,
	["monde occupé : intervalles, annonce 3 s avant, durée du type"] = function()
		for world = 1, Tower.WORLD_COUNT do
			local list = simulate(world, 1000, 1000 + 3600, always, world)
			Expect.truthy(#list > 10, `des incidents au monde {world}`)
			local boss = world == Tower.WORLD_COUNT
			local low = if boss then Incidents.BossIntervalMin else Incidents.IntervalMin
			local high = if boss then Incidents.BossIntervalMax else Incidents.IntervalMax
			Expect.between(list[1].Warn - 1000, low - 0.3, high + 0.3, "premier incident après un intervalle")
			for index, incident in list do
				local def = Incidents.ByKind[incident.Kind]
				Expect.truthy(def ~= nil, `type connu {incident.Kind}`)
				Expect.near(incident.Start - incident.Warn, Incidents.WarningSeconds, 1e-9, "annonce")
				Expect.near(incident.End - incident.Start, def.Duration, 1e-9, "durée")
				if not boss then
					Expect.equal(incident.Kind, Tower.Worlds[world].Incident, "incident vedette du monde")
				end
				local previous = list[index - 1]
				if previous then
					-- Jamais deux incidents en même temps ; écart = fin + intervalle.
					Expect.between(incident.Warn - previous.End, low - 0.3, high + 0.3, "écart entre incidents")
				end
			end
		end
	end,
	["monde 7 : tous les types, jamais deux fois le même d'affilée"] = function()
		local list = simulate(Tower.WORLD_COUNT, 0, 20000, always, 3)
		local seen = {}
		for index, incident in list do
			seen[incident.Kind] = true
			if index > 1 then
				Expect.truthy(incident.Kind ~= list[index - 1].Kind, "pas de répétition")
			end
		end
		for _, def in Incidents.List do
			Expect.truthy(seen[def.Kind], `type {def.Kind} tiré au monde 7`)
		end
	end,
	["FREEZE : décalage ajouté et Kind effacé dans la même étape"] = function()
		local state = IncidentSchedule.NewState()
		local roll = lcg(1)
		IncidentSchedule.Announce(state, 100, "Freeze")
		local duration = Incidents.ByKind.Freeze.Duration
		Expect.equal(state.Start, 100 + Incidents.WarningSeconds)
		Expect.equal(IncidentSchedule.Step(state, 6, state.End - 0.01, true, roll), nil, "encore en cours")
		Expect.equal(state.Kind, "Freeze")
		local finish = state.End
		Expect.equal(IncidentSchedule.Step(state, 6, finish + 0.1, true, roll), "End")
		Expect.equal(state.Kind, "")
		Expect.near(state.Offset, duration, 1e-9, "durée du freeze reportée")
		Expect.truthy(state.NextAt > finish, "prochain incident programmé")
		-- Un LAG ne décale pas l'horloge.
		IncidentSchedule.Announce(state, 300, "Lag")
		IncidentSchedule.Step(state, 5, state.End, true, roll)
		Expect.near(state.Offset, duration, 1e-9, "LAG sans décalage")
	end,
	["horloge des pièges continue à la fin d'un FREEZE publié"] = function()
		Shim.Globals = {
			game = {
				GetService = function(_self: any, _name: string): any
					return {}
				end,
			},
		}
		local TrapClock = Shim.load("src/shared/Util/TrapClock.luau")
		Shim.Globals = {}
		local state = IncidentSchedule.NewState()
		IncidentSchedule.Announce(state, 50, "Freeze")
		local kind, start, finish, offset = state.Kind, state.Start, state.End, state.Offset
		local before = TrapClock.Compute(finish + 0.05, kind, start, finish, offset)
		IncidentSchedule.Step(state, 6, finish + 0.05, true, lcg(2))
		local after = TrapClock.Compute(finish + 0.05, state.Kind, state.Start, state.End, state.Offset)
		Expect.near(after, before, 1e-9, "pas de saut quand le serveur publie la fin")
		Expect.near(TrapClock.Compute(start + 2, kind, start, finish, offset), start, 1e-9, "figé pendant")
	end,
	["un incident annoncé va jusqu'au bout, même si le monde se vide"] = function()
		local state = IncidentSchedule.NewState()
		IncidentSchedule.Announce(state, 10, "Blackout")
		Expect.equal(IncidentSchedule.Step(state, 1, 12, false, lcg(1)), nil)
		Expect.equal(state.Kind, "Blackout")
		Expect.equal(IncidentSchedule.Step(state, 1, state.End, false, lcg(1)), "End")
		Expect.equal(state.NextAt, 0, "monde vide : rien de programmé")
	end,
	["retour dans un monde : jamais d'incident dès l'arrivée"] = function()
		-- Occupé 0..50, vide 50..400, de nouveau occupé ensuite.
		local list = simulate(3, 0, 1000, function(t: number): boolean
			return t < 50 or t >= 400
		end)
		for _, incident in list do
			Expect.truthy(incident.Warn < 50 or incident.Warn >= 400 + IncidentSchedule.ENTRY_GRACE - 0.3, "marge")
		end
		Expect.truthy(#list > 0)
	end,
	["phases vues par le client"] = function()
		local P = IncidentSchedule.Phase
		Expect.equal(P("", 10, 13, 20, 12), "")
		Expect.equal(P("Lag", 10, 13, 20, 9), "")
		Expect.equal(P("Lag", 10, 13, 20, 11), "Warn")
		Expect.equal(P("Lag", 10, 13, 20, 13), "Active")
		Expect.equal(P("Lag", 10, 13, 20, 20), "")
	end,
	["Performance du PC : tableau du scénario"] = function()
		local s0, s4, s7 = PcHealth.Stats(0), PcHealth.Stats(4), PcHealth.Stats(7)
		Expect.equal(s0.Fps, 3)
		Expect.equal(s0.Ping, 999)
		Expect.equal(s0.Temp, 97)
		Expect.equal(s4.Fps, 60)
		Expect.equal(s4.Ping, 120)
		Expect.equal(s7.Fps, 144)
		Expect.equal(s7.Ping, 8)
		Expect.equal(s7.Temp, 40)
		Expect.equal(PcHealth.Stats(12).Fps, 144, "borné")
		local previous = PcHealth.Stats(0)
		for cleared = 1, Tower.WORLD_COUNT do
			local current = PcHealth.Stats(cleared)
			Expect.truthy(current.Fps > previous.Fps and current.Ping < previous.Ping, "le PC s'améliore")
			Expect.truthy(current.Temp < previous.Temp, "le PC refroidit")
			previous = current
		end
		Expect.equal(PcHealth.Grade("Fps", 3), "Bad")
		Expect.equal(PcHealth.Grade("Fps", 144), "Good")
		Expect.equal(PcHealth.Grade("Ping", 250), "Warn")
		Expect.equal(PcHealth.Grade("Temp", 40), "Good")
	end,
	["compte à rebours du live : 60:00 -> 00:00"] = function()
		Expect.equal(PcHealth.LiveCountdown(0, 0), 3600)
		Expect.equal(PcHealth.Clock(3600), "60:00")
		Expect.equal(PcHealth.Clock(59), "00:59")
		Expect.equal(PcHealth.LiveCountdown(Tower.TOTAL_STAGES, Tower.WORLD_COUNT), 0)
		local previous = 3601
		for stage = 0, Tower.TOTAL_STAGES do
			local world = Tower.WorldOf(stage)
			-- Le monde n'est nettoyé qu'au terminal (dernière étape du monde).
			local last = if stage > 0 and stage == Tower.TerminalStage(world) then world else math.max(world - 1, 0)
			for cleared = math.max(world - 1, 0), last do
				local left = PcHealth.LiveCountdown(stage, cleared)
				Expect.truthy(left <= previous, `décroît (étape {stage}, nettoyés {cleared})`)
				previous = left
			end
		end
		Expect.truthy(PcHealth.LiveCountdown(Tower.TerminalStage(3), 2) > 0, "le terminal termine le monde")
	end,
}
