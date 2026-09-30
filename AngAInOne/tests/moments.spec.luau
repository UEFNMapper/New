-- Moments, dialogues et HUD sur téléphone : file des moments (un seul à la fois), répliques qui
-- expirent, format du ping, et garde-fous de source (textes ≥ 18 px, pas de partage hors Roblox).
local MomentQueue = Shim.load("src/client/UI/MomentQueue.luau")
local DialogueQueue = Shim.load("src/client/UI/DialogueQueue.luau")
local HudFormat = Shim.load("src/client/UI/HudFormat.luau")

local function source(path: string): string
	return Fs.readFile(path)
end

local function item(kind: string, hold: number, unique: boolean?): any
	return { Kind = kind, Hold = hold, Unique = unique, Data = kind }
end

-- Fait tourner la file de `from` à `to` (pas de 0,05 s) ; renvoie les intervalles affichés.
local function run(queue: any, from: number, to: number, log: { any }, events: { [number]: () -> () }?)
	local t = from
	while t <= to + 1e-9 do
		if events then
			for at, event in events do
				if math.abs(at - t) < 0.025 then
					event()
				end
			end
		end
		local started, finished = MomentQueue.Step(queue, t)
		if finished then
			for _, entry in log do
				if entry.Item == finished and entry.To == nil then
					entry.To = t
				end
			end
		end
		if started then
			table.insert(log, { Item = started, Kind = started.Kind, From = t })
		end
		t += 0.05
	end
end

return {
	["file des moments : bannière -> médaille -> en-tête du monde, un seul à la fois"] = function()
		local queue = MomentQueue.new()
		MomentQueue.Push(queue, item("Cleared", 4.4))
		MomentQueue.Push(queue, item("Medal", 6.9))
		local log = {}
		run(queue, 0, 3, log)
		-- Le joueur arrive dans le monde suivant à t = 3 : l'en-tête attend son tour.
		MomentQueue.Push(queue, item("World", 4.85, true))
		run(queue, 3.05, 30, log)
		Expect.equal(#log, 3, "trois moments")
		Expect.equal(log[1].Kind, "Cleared")
		Expect.equal(log[2].Kind, "Medal")
		Expect.equal(log[3].Kind, "World")
		for i = 2, #log do
			Expect.truthy(
				log[i].From >= (log[i - 1].To or math.huge) - 1e-9,
				`{log[i].Kind} après la fin du précédent`
			)
		end
		Expect.near(log[2].From, 4.4, 0.06, "la médaille suit la bannière")
		Expect.near(log[3].From, 4.4 + 6.9, 0.06, "l'en-tête suit la médaille")
		Expect.equal(queue.Current, nil, "file vide à la fin")
	end,
	["file des moments : nouveau monde -> la carte de médaille se ferme vite"] = function()
		local queue = MomentQueue.new()
		MomentQueue.Push(queue, item("Cleared", 4.4))
		MomentQueue.Push(queue, item("Medal", 6.9))
		local log = {}
		run(queue, 0, 5, log)
		Expect.equal(queue.Current and queue.Current.Kind, "Medal", "médaille affichée")
		-- Checkpoint NewWorld à t = 5 : la médaille reste au plus 2 s au total, puis l'en-tête.
		MomentQueue.Expedite(queue, "Medal", 5, 2)
		MomentQueue.Push(queue, item("World", 4.85, true))
		run(queue, 5.05, 12, log)
		Expect.equal(log[3].Kind, "World")
		Expect.near(log[3].From, 6.4, 0.06, "en-tête 2 s après le début de la médaille")
		-- Déjà affichée depuis longtemps : fermée tout de suite.
		local late = MomentQueue.new()
		MomentQueue.Push(late, item("Medal", 6.9))
		MomentQueue.Step(late, 0)
		MomentQueue.Expedite(late, "Medal", 5, 2)
		Expect.near(late.EndsAt, 5, 1e-9, "fermée maintenant")
		-- Médaille encore en attente : sa durée est plafonnée.
		local pending = MomentQueue.new()
		MomentQueue.Push(pending, item("Cleared", 4.4))
		MomentQueue.Push(pending, item("Medal", 6.9))
		MomentQueue.Step(pending, 0)
		MomentQueue.Expedite(pending, "Medal", 1, 2)
		Expect.equal(pending.Pending[1].Hold, 2, "médaille en attente raccourcie")
		Expect.near(pending.EndsAt, 4.4, 1e-9, "la bannière garde son temps")
	end,
	["file des moments : fermeture au toucher, rappel tardif, unique, vider"] = function()
		local queue = MomentQueue.new()
		MomentQueue.Push(queue, item("Medal", 6.9))
		MomentQueue.Push(queue, item("World", 4.85))
		local medal = MomentQueue.Step(queue, 0)
		Expect.equal(medal and medal.Kind, "Medal")
		Expect.equal(MomentQueue.FinishItem(queue, medal, 1), true, "fermée d'un toucher")
		local nextItem, finished = MomentQueue.Step(queue, 1)
		Expect.equal(finished, medal)
		Expect.equal(nextItem and nextItem.Kind, "World", "le suivant démarre tout de suite")
		Expect.equal(MomentQueue.FinishItem(queue, medal, 1.5), false, "rappel tardif : ne coupe pas le suivant")
		Expect.near(queue.EndsAt, 1 + 4.85, 1e-9)
		Expect.equal(MomentQueue.Finish(queue, "Medal", 2), false, "pas de médaille en cours")
		Expect.equal(MomentQueue.Finish(queue, "World", 2), true)

		local unique = MomentQueue.new()
		MomentQueue.Push(unique, item("Cleared", 4))
		MomentQueue.Step(unique, 0)
		MomentQueue.Push(unique, item("World", 4, true))
		MomentQueue.Push(unique, item("Medal", 6))
		MomentQueue.Push(unique, item("World", 5, true))
		Expect.equal(#unique.Pending, 2, "un seul en-tête de monde en attente")
		Expect.equal(unique.Pending[2].Hold, 5, "le plus récent gagne")
		Expect.equal(MomentQueue.Has(unique, "Medal"), true)

		MomentQueue.Clear(unique, 1)
		Expect.equal(#unique.Pending, 0, "victoire : file vidée")
		local started, ended = MomentQueue.Step(unique, 1)
		Expect.equal(started, nil)
		Expect.equal(ended and ended.Kind, "Cleared", "le moment en cours se termine")
		Expect.equal(MomentQueue.Has(unique, "Medal"), false)
	end,
	["dialogue : une réplique expirée n'est jamais jouée, les autres restent"] = function()
		local queue = {}
		table.insert(queue, DialogueQueue.Make("Monde 1 nettoyé", 4, "Anga", 8, 0))
		table.insert(queue, DialogueQueue.Make("LAGZ râle", 3.5, "LAGZ", 6, 1))
		table.insert(queue, DialogueQueue.Make("Astuce", nil, nil, nil, 1))
		Expect.equal(queue[3].Duration, 4, "durée par défaut")
		Expect.equal(queue[3].Speaker, "Anga", "Anga par défaut")
		Expect.equal(queue[3].ExpiresAt, nil, "sans délai : n'expire pas")
		local first = DialogueQueue.PopNext(queue, 2)
		Expect.equal(first and first.Text, "Monde 1 nettoyé", "encore valable à t = 2")
		-- t = 10 : la réplique de LAGZ (expire à 7) est jetée, l'astuce reste.
		local nextLine = DialogueQueue.PopNext(queue, 10)
		Expect.equal(nextLine and nextLine.Text, "Astuce")
		Expect.equal(#queue, 0)
		Expect.equal(DialogueQueue.PopNext(queue, 10), nil)

		local pruned = {
			DialogueQueue.Make("a", 4, "Anga", 5, 0),
			DialogueQueue.Make("b", 4, "Anga", nil, 0),
			DialogueQueue.Make("c", 4, "AIO", 20, 0),
		}
		Expect.equal(DialogueQueue.Prune(pruned, 6), 1, "une réplique jetée")
		Expect.equal(pruned[1].Text, "b")
		Expect.equal(pruned[2].Text, "c", "l'ordre est gardé")
		Expect.equal(DialogueQueue.Make("d", 4, "Anga", 0, 3).ExpiresAt, nil, "délai nul : pas d'expiration")
	end,
	["HUD : ping en ms jusqu'à 999, puis en secondes (virgule)"] = function()
		Expect.equal(HudFormat.Ping(48), "48 ms")
		Expect.equal(HudFormat.Ping(999), "999 ms")
		Expect.equal(HudFormat.Ping(999.4), "999 ms")
		Expect.equal(HudFormat.Ping(1000), "1,0 s")
		Expect.equal(HudFormat.Ping(2400), "2,4 s")
		Expect.equal(HudFormat.Ping(2449), "2,4 s")
		Expect.equal(HudFormat.Ping(2450), "2,5 s")
		Expect.equal(HudFormat.Ping(12345), "12,3 s")
		Expect.equal(HudFormat.Ping(-3), "0 ms")
		for ms = 1, 30000, 7 do
			Expect.truthy(#HudFormat.Ping(ms) <= 7, `pastille courte ({ms} ms)`)
		end
	end,
	["téléphone : textes ≥ 18 px (carte de médaille, carte de plantage)"] = function()
		for _, path in { "src/client/UI/Screens/MedalCard.luau", "src/client/Controllers/CrashLog.luau" } do
			local code = source(path)
			for size in string.gmatch(code, "TextSize = (%d+)") do
				Expect.truthy(tonumber(size) >= 18, `{path} : TextSize {size}`)
			end
			for size in string.gmatch(code, "MinTextSize = (%d+)") do
				Expect.truthy(tonumber(size) >= 18, `{path} : MinTextSize {size}`)
			end
		end
		local crash = source("src/client/Controllers/CrashLog.luau")
		Expect.truthy(string.find(crash, "LEFT, TOP = 16, 216", 1, true) ~= nil, "carte de plantage en haut à gauche")
		local moments = source("src/client/UI/Screens/Moments.luau")
		Expect.truthy(string.find(moments, "local MIN_TEXT = 18", 1, true) ~= nil)
		Expect.truthy(string.find(moments, "local TOUCH = 88", 1, true) ~= nil)
		for size in string.gmatch(moments, "TextSize = (%d+)") do
			Expect.truthy(tonumber(size) >= 18, `Moments : TextSize {size}`)
		end
	end,
	["rapport de victoire : pas de partage hors Roblox, fermeture facile, médaille du monde 7"] = function()
		local moments = source("src/client/UI/Screens/Moments.luau")
		for _, banned in { "Copier en Markdown", "Mettre en ligne", "lien à partager" } do
			Expect.equal(string.find(moments, banned, 1, true), nil, `plus de « {banned} »`)
		end
		Expect.truthy(string.find(moments, "Capture d'écran 📸", 1, true) ~= nil, "un seul rappel de capture")
		Expect.truthy(string.find(moments, "REPORT_AUTO_CLOSE = 25", 1, true) ~= nil, "fermeture auto en 25 s")
		Expect.truthy(string.find(moments, "screen.Activated:Connect", 1, true) ~= nil, "toucher à l'extérieur")
		Expect.truthy(string.find(moments, "Médaille du monde", 1, true) ~= nil)
		local feedback = source("src/client/Controllers/Feedback.luau")
		Expect.equal(string.find(feedback, "MEDAL_DELAY", 1, true), nil, "plus de délai non gardé")
		Expect.truthy(string.find(feedback, "finalMedal = payload", 1, true) ~= nil, "monde 7 : médaille gardée")
		Expect.truthy(string.find(feedback, "Moments.Victory(payload, medal)", 1, true) ~= nil)
	end,
	["calques : le bandeau d'incident passe au-dessus des moments"] = function()
		local app = source("src/client/UI/App.luau")
		local moments = tonumber(string.match(app, 'layer%("Moments", (%d+)%)'))
		local alerts = tonumber(string.match(app, 'layer%("Alerts", (%d+)%)'))
		local toasts = tonumber(string.match(app, 'layer%("Toasts", (%d+)%)'))
		Expect.truthy(
			moments and alerts and toasts and moments < alerts and alerts < toasts,
			"Moments < Alerts < Toasts"
		)
		local incident = source("src/client/Controllers/IncidentController.luau")
		Expect.truthy(string.find(incident, 'FindFirstChild("Alerts")', 1, true) ~= nil, "bandeau sur Alerts")
	end,
	["mini-jeux : la victoire part dès qu'elle est acquise (terminal et arcade)"] = function()
		local panel = source("src/client/UI/Screens/MinigamePanel.luau")
		Expect.truthy(string.find(panel, "task.spawn(onWin, score, s.LastDuration)", 1, true) ~= nil)
		local interactions = source("src/client/Controllers/Interactions.luau")
		local _, wins = string.gsub(interactions, "end, onWin%)", "")
		Expect.equal(wins, 2, "terminal et arcade passent onWin")
		local _, restarts = string.gsub(interactions, 'restart%(%)\n%s*Net%.Fire%("%a+Start"', "")
		Expect.equal(restarts, 2, "RÉESSAYER rouvre l'envoi")
	end,
}
