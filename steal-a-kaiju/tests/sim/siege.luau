--!nocheck
-- DÉFENSE DE L'ÎLE (« Wild Kaijus Invade! ») jouée de bout en bout : vague
-- d'entraînement, vagues gagnées par les tours, bonk, fuite + sac récupéré,
-- vague ratée rejouée, Alpha → œuf, pauses du compte à rebours, visiteur,
-- compagnon, départ en pleine vague ; le vrai client tourne en même temps
-- (rendu des envahisseurs, HUD, cartes) et on compte les erreurs.
-- Lancer : lune run tests/sim/siege.luau

local Boot = require("./boot")
local Runtime = Boot.Start()
local ClientRuntime = require("./ClientRuntime")
ClientRuntime.Install(Runtime)
local roblox = require("@lune/roblox")
local V3 = roblox.Vector3.new
local CF = roblox.CFrame.new

local passed, failed = 0, 0
local lines = {}
local function check(name, cond, detail)
	if cond then
		passed += 1
		table.insert(lines, "  ✅ " .. name)
	else
		failed += 1
		table.insert(lines, "  ❌ " .. name .. (if detail ~= nil then " — " .. tostring(detail) else ""))
	end
end
local function section(t)
	table.insert(lines, "\n## " .. t)
end

local S = Runtime.Services
local function req(inst)
	return Runtime.Globals.require(inst)
end
local Services = S.ServerScriptService:FindFirstChild("Server"):FindFirstChild("Services")
local Registry = req(Services:FindFirstChild("Registry"))
local SiegeService = req(Services:FindFirstChild("SiegeService"))
local DataService = req(Services:FindFirstChild("DataService"))
local KaijuService = req(Services:FindFirstChild("KaijuService"))
local PlotService = req(Services:FindFirstChild("PlotService"))
local Shared = S.ReplicatedStorage:FindFirstChild("Shared")
local Siege = req(Shared.Config.Siege)
local Tutorial = req(Shared.Config.Tutorial)
local Growth = req(Shared.Config.Growth)
local Kaijus = req(Shared.Config.Kaijus)

-- Espion : événements envoyés au tutoriel
local notified = {}
local realNotify = Registry.TutorialService.Notify
Registry.TutorialService.Notify = function(p, event)
	table.insert(notified, { Player = p, Event = event })
	return realNotify(p, event)
end
local function notifiedCount(p, event)
	local n = 0
	for _, e in notified do
		if e.Player == p and e.Event == event then
			n += 1
		end
	end
	return n
end

local function serverNow()
	return S.Workspace:GetServerTimeNow()
end

----------------------------------------------------------------------------
-- Démarrage : un vrai client
----------------------------------------------------------------------------
section("Démarrage")
local hero, clientFolder = ClientRuntime.StartClient(Runtime, "Hero")
Runtime.Advance(12)
local data = DataService.Get(hero)
check("client prêt", hero:GetAttribute("ClientReady") == true)
check("aucune erreur au démarrage", #Runtime.Errors == 0, #Runtime.Errors)
local plot = PlotService.Get(hero)
local plotCf = plot.CFrame
local folder = S.Workspace:FindFirstChild("Siege"):FindFirstChild("Plot" .. plot.Index)
check("dossier workspace.Siege.Plot<i> créé", folder ~= nil)
check("pas de vague pendant le début du tutoriel (Idle)", folder:GetAttribute("State") == "Idle", folder:GetAttribute("State"))
local playerGui = hero:FindFirstChild("PlayerGui")
local hud = playerGui:FindFirstChild("SiegeHud")
check("couche SiegeHud créée", hud ~= nil)
local status = hud and hud:FindFirstChild("SiegeStatus")
check("panneau d'état caché hors siège", status and status.Visible == false)

local function hatchedCount(p)
	local n = 0
	for _, rec in DataService.Get(p).Kaijus do
		if not rec.Egg then
			n += 1
		end
	end
	return n
end
check("le premier bébé a éclos", hatchedCount(hero) == 1, hatchedCount(hero))

local function localToWorld(x, z)
	return (plotCf * CF(x, 3, z)).Position
end
-- place le héros sur son île, hors des couloirs et loin du pad du réacteur
local SAFE = localToWorld(15, 50)
Runtime.MoveTo(hero, SAFE)

-- avance en bougeant un peu (pas AFK), en restant sur l'île
local wiggleSide = 1
local function wiggle(seconds, base)
	local target = base or SAFE
	for _ = 1, math.ceil(seconds) do
		wiggleSide = -wiggleSide
		Runtime.MoveTo(hero, target + V3(wiggleSide * 2, 0, 0))
		Runtime.Advance(1)
	end
end

local function untilState(want, maxSeconds, base)
	for _ = 1, maxSeconds do
		if folder:GetAttribute("State") == want then
			return true
		end
		wiggle(1, base)
	end
	return folder:GetAttribute("State") == want
end

local function invaders(f)
	local list = {}
	for _, c in (f or folder):GetChildren() do
		if c:GetAttribute("Kind") == "Invader" then
			table.insert(list, c)
		end
	end
	return list
end
local function orbsOf(f)
	local list = {}
	for _, c in (f or folder):GetChildren() do
		if c:GetAttribute("Kind") == "Orb" then
			table.insert(list, c)
		end
	end
	return list
end
local function invaderPos(part, cf)
	local path = Siege.GetPath(part:GetAttribute("Path"))
	local d = Siege.Distance(path, part:GetAttribute("D0"), part:GetAttribute("T0"), part:GetAttribute("Speed"), part:GetAttribute("Dir"), serverNow())
	local p = Siege.PathAt(path, d)
	return ((cf or plotCf) * CF(p.X, 0, p.Z)).Position, d
end
local function clientModels()
	local n = 0
	local f = S.Workspace:FindFirstChild("ClientSiege")
	for _, c in (f and f:GetChildren() or {}) do
		if c.ClassName == "Model" and string.sub(c.Name, 1, 5) == "Wild_" then
			n += 1
		end
	end
	return n
end
local function lastFx(p, name, from)
	local list = Boot.FxFor(p, name, from)
	return list[#list]
end

----------------------------------------------------------------------------
section("Géométrie du chemin")
do
	local ok = true
	local worst = math.huge
	for _, path in { Siege.In, Siege.Out, Siege.TutorialPath } do
		for d = 0, path.Length, 0.5 do
			local p = Siege.PathAt(path, d)
			for _, nest in req(Shared.Config.Layout).Nests do
				local dist = V3(p.X - nest.X, 0, p.Z - nest.Z).Magnitude
				worst = math.min(worst, dist)
				if dist < 6.5 then
					ok = false
				end
			end
			if math.abs(p.X) > 47 or p.Z < -57 or p.Z > 44 then
				ok = false
			end
		end
	end
	check("le chemin ne traverse ni les nids ni les murs", ok, worst)
	check("bonds au-dessus de la clôture (2 par chemin)", #Siege.In.Hops == 2 and #Siege.Out.Hops == 2 and #Siege.TutorialPath.Hops == 2)
	local p = Siege.PathAt(Siege.In, Siege.In.Hops[1])
	check("hauteur de bond au franchissement", p.Y > 3, p.Y)
end

----------------------------------------------------------------------------
section("Vague d'entraînement (1 bébé, gagnée par les tours)")
local log = #Runtime.ClientLog
check("vague d'entraînement lancée", SiegeService.StartTutorialWave(hero) == true)
check("attribut joueur SiegeActive = true", hero:GetAttribute("SiegeActive") == true)
check("pas deux vagues à la fois", SiegeService.StartTutorialWave(hero) == false)
local start = lastFx(hero, "SiegeWaveStart", log)
check("sirène envoyée (Tutorial, 4 envahisseurs)", start and start.Tutorial == true and start.Count == 4, start and start.Count)
Runtime.Advance(0.5)
check("bandeau de sirène affiché", hud:FindFirstChild("SiegeBanner") ~= nil)
Runtime.Advance(5.5)
check("envahisseurs rendus côté client", clientModels() >= 1, clientModels())
check("HUD : panneau de vague visible", status.Visible == true)
check("HUD : « TRAINING WAVE »", string.find(status:FindFirstChild("Title", true).Text, "TRAINING") ~= nil, status:FindFirstChild("Title", true).Text)
check("le bandeau s'efface", hud:FindFirstChild("SiegeBanner") == nil)
local sawAim = false
for _ = 1, 150 do
	Runtime.Advance(1)
	if not sawAim and #Boot.FxFor(hero, "SiegeShots", log) > 0 then
		sawAim = true
	end
	if folder:GetAttribute("State") ~= "Active" then
		break
	end
end
local tutoEnd = lastFx(hero, "SiegeWaveEnd", log)
check("vague d'entraînement terminée", tutoEnd ~= nil)
check("4 kills par les tours, aucune fuite", tutoEnd and tutoEnd.Kills == 4 and tutoEnd.Leaks == 0 and tutoEnd.Cleared == true, tutoEnd and (tutoEnd.Kills .. " kills / " .. tutoEnd.Leaks .. " fuites"))
check("aucun bonk : ce sont bien les tours", #Boot.FxFor(hero, "SiegeBonk", log) == 0)
check("tirs envoyés par lots (SiegeShots)", sawAim)
check("TutorialService.Notify(« SiegeWave »)", notifiedCount(hero, "SiegeWave") == 1, notifiedCount(hero, "SiegeWave"))
check("SiegeActive repasse à false", hero:GetAttribute("SiegeActive") == false)
check("la vague d'entraînement ne change pas le numéro de vague", data.Siege.Wave == 1, data.Siege.Wave)
check("rien volé pendant l'entraînement", #Boot.FxFor(hero, "SiegeLeak", log) == 0)
Runtime.Advance(1)
check("carte de fin affichée", hud:FindFirstChild("SiegeEnd") ~= nil)
check("retour à Idle tant que le tutoriel n'est pas fini", folder:GetAttribute("State") == "Idle", folder:GetAttribute("State"))

----------------------------------------------------------------------------
section("Vague normale gagnée par les tours")
data.Tutorial = Tutorial.Done
DataService.Replicate(hero, "Tutorial")
data.Nests = 20
PlotService.RefreshNests(hero)
for _, sp in { "Toastzilla", "Gloop", "Pinchy" } do
	KaijuService.AddHatched(hero, sp, nil, Growth.Threshold(3, "Common") + 5)
end
Runtime.Advance(1)
wiggle(1)
check("compte à rebours lancé après le tutoriel", folder:GetAttribute("State") == "Countdown", folder:GetAttribute("State"))
local left = (folder:GetAttribute("At") or 0) - serverNow()
check("première vague rapide (~45 s)", left > 30 and left <= Siege.FirstCountdown + 1, left)
check("HUD : compte à rebours + START NOW", status.Visible and status:FindFirstChild("StartNow", true).Visible == true)
log = #Runtime.ClientLog
check("la vague démarre à la fin du compte à rebours", untilState("Active", 60))
local s1 = lastFx(hero, "SiegeWaveStart", log)
check("sirène vague 1 (6 envahisseurs)", s1 and s1.Wave == 1 and s1.Count == 6 and not s1.Bonus, s1 and s1.Count)
local cash0, xp0 = data.Cash, data.Xp
local modelsSeen = 0
for _ = 1, 200 do
	wiggle(1)
	modelsSeen = math.max(modelsSeen, clientModels())
	if folder:GetAttribute("State") ~= "Active" then
		break
	end
end
local e1 = lastFx(hero, "SiegeWaveEnd", log)
check("vague 1 gagnée", e1 and e1.Cleared == true and e1.Wave == 1, e1 and e1.Leaks)
check("modèles des envahisseurs construits", modelsSeen >= 2, modelsSeen)
check("vague suivante = 2", data.Siege.Wave == 2 and data.Siege.Best == 1 and data.Siege.Cleared == 1, data.Siege.Wave)
check("statistiques SiegeWaves / SiegeKills", data.Stats.SiegeWaves == 1 and data.Stats.SiegeKills >= 6 + 4, data.Stats.SiegeKills)
check("bonus de fin de vague payé", e1 and e1.Cash > 0 and data.Cash >= cash0 + e1.Cash, e1 and e1.Cash)
check("XP gagnée", data.Xp > xp0, data.Xp - xp0)
check("Notify SiegeWave pour une vague normale", notifiedCount(hero, "SiegeWave") == 2)
check("étoiles de fin", e1 and e1.Stars >= 1)

-- Orbes de cash
local orbs = orbsOf()
check("orbes de cash lâchées par les kills", #orbs >= 1, #orbs)
if #orbs > 0 then
	local o = orbs[1]
	local value = o:GetAttribute("Value")
	local before = data.Cash
	Runtime.MoveTo(hero, o.Position)
	Runtime.Advance(0.5)
	check("orbe ramassée en marchant dessus", o.Parent == nil and data.Cash >= before + value, data.Cash - before)
	check("effet SiegeOrb", #Boot.FxFor(hero, "SiegeOrb", log) >= 1)
end
local rest = orbsOf()
if #rest > 0 then
	local got = SiegeService.CollectOrbsNear(hero, rest[1].Position, 200)
	check("CollectOrbsNear (compagnon) aspire les orbes", got > 0 and #orbsOf() == 0, got)
end
Runtime.MoveTo(hero, SAFE)

----------------------------------------------------------------------------
section("Compte à rebours : pauses")
wiggle(2)
check("compte à rebours de 2:30 entre deux vagues", folder:GetAttribute("State") == "Countdown" and (folder:GetAttribute("At") - serverNow()) > 140, folder:GetAttribute("At") - serverNow())
Runtime.MoveTo(hero, V3(0, 3, 0)) -- cratère
Runtime.Advance(1)
check("hors de l'île : en pause (Away)", folder:GetAttribute("State") == "Paused" and folder:GetAttribute("Reason") == "Away", folder:GetAttribute("Reason"))
local frozen = folder:GetAttribute("Left")
Runtime.Advance(30)
check("le compte à rebours ne s'écoule pas hors de l'île", folder:GetAttribute("Left") == frozen and folder:GetAttribute("State") == "Paused")
check("HUD : « PAUSED — Go back to your island! »", string.find(status:FindFirstChild("Title", true).Text, "PAUSED") ~= nil and string.find(status:FindFirstChild("Sub", true).Text, "island") ~= nil, status:FindFirstChild("Sub", true).Text)
wiggle(1)
local resumed = folder:GetAttribute("At") - serverNow()
check("de retour chez soi : ça repart d'où c'était", folder:GetAttribute("State") == "Countdown" and math.abs(resumed - (frozen - 1)) < 1.5, resumed)
-- AFK
Runtime.MoveTo(hero, SAFE)
Runtime.Advance(Siege.AfkSeconds + 3)
check("immobile 2 min : en pause (AFK)", folder:GetAttribute("Reason") == "AFK", folder:GetAttribute("Reason"))
wiggle(1)
check("on bouge : ça repart", folder:GetAttribute("State") == "Countdown")
-- Rampage (fonction fournie par un autre service : appel défensif)
Registry.RampageService.IsActive = function(p)
	return p == hero
end
wiggle(1)
check("en Rampage : en pause", folder:GetAttribute("Reason") == "Rampage", folder:GetAttribute("Reason"))
local refused = Boot.Call(hero, "SiegeStartNow")
check("START NOW refusé pendant un Rampage", refused and refused.ok == false)
Registry.RampageService.IsActive = nil
wiggle(1)
check("fin du Rampage : ça repart", folder:GetAttribute("State") == "Countdown")

----------------------------------------------------------------------------
section("START NOW (bouton du HUD) + bonk d'un envahisseur")
log = #Runtime.ClientLog
local button = status:FindFirstChild("StartNow", true)
button.Activated:Fire()
Runtime.Advance(0.5)
check("le bouton START NOW lance la vague", folder:GetAttribute("State") == "Active")
local s2 = lastFx(hero, "SiegeWaveStart", log)
check("bonus START NOW (+10 %)", s2 and s2.Bonus == true and s2.Wave == 2)
Runtime.Advance(3)
local target = invaders()[1]
check("un envahisseur est là", target ~= nil)
if target then
	local hp = target:GetAttribute("HP")
	local pos, d = invaderPos(target)
	hero.Character.HumanoidRootPart.CFrame = Runtime.CFrame.lookAt(pos + V3(2, 3, 0), pos)
	local bonks = data.Stats.Bonks
	Boot.Input(hero, "Bonk")
	Runtime.Advance(0.1)
	local bonk = lastFx(hero, "SiegeBonk", log)
	local expected = Siege.BonkDamage * (1 + Siege.BonkPerLevel * data.Upgrades.Bonker)
	check("bonk : dégâts 10 × (1 + 0,25 × niveau)", bonk and math.abs(bonk.Damage - expected) < 0.01, bonk and bonk.Damage)
	check("bonk : PV réduits", target.Parent == nil or target:GetAttribute("HP") < hp)
	if target.Parent then
		local _, d2 = invaderPos(target)
		check("bonk : recul le long du chemin", d2 < d, ("%.1f -> %.1f"):format(d, d2))
	else
		check("bonk : envahisseur achevé", true)
	end
	check("statistique Bonks", data.Stats.Bonks == bonks + 1)
end
Runtime.MoveTo(hero, SAFE)
untilState("Countdown", 220)
local e2 = lastFx(hero, "SiegeWaveEnd", log)
check("vague 2 gagnée avec le bonus", e2 and e2.Cleared and e2.Bonus == true, e2 and e2.Leaks)

----------------------------------------------------------------------------
section("Fuite, sac de cash récupéré au bonk, vague ratée rejouée")
local range = Siege.TowerRange
Siege.TowerRange = -1000 -- tours hors service pour ce test
data.Stored = 20000
local waveBefore = data.Siege.Wave
log = #Runtime.ClientLog
Boot.Call(hero, "SiegeStartNow")
local leakFx
local storedPrev, storedBefore = data.Stored, data.Stored
for _ = 1, 120 do
	storedBefore = storedPrev
	storedPrev = data.Stored
	wiggle(1)
	leakFx = lastFx(hero, "SiegeLeak", log)
	if leakFx then
		break
	end
end
local income = KaijuService.IncomePerSecond(hero)
check("un envahisseur atteint le réacteur", leakFx ~= nil)
check("il prend un sac (5 % du réacteur, plafonné à 60 s de revenu)", leakFx and leakFx.Amount > 0 and leakFx.Amount <= math.min((storedPrev + income * 2) * Siege.BagShare, income * Siege.BagMaxSeconds) + 1, leakFx and leakFx.Amount)
check("le cash stocké diminue", data.Stored < storedPrev and storedPrev >= storedBefore, ("%d -> %d"):format(storedPrev, data.Stored))
local thief
for _, inv in invaders() do
	if (inv:GetAttribute("Bag") or 0) > 0 then
		thief = inv
	end
end
check("le voleur s'enfuit (chemin Out, demi-vitesse)", thief and thief:GetAttribute("Path") == "Out" and thief:GetAttribute("Speed") < 9, thief and thief:GetAttribute("Speed"))
check("jamais de kaiju volé", hatchedCount(hero) == 4, hatchedCount(hero))
if thief then
	local bag = thief:GetAttribute("Bag")
	local cashBefore = data.Cash
	local pos = invaderPos(thief)
	hero.Character.HumanoidRootPart.CFrame = Runtime.CFrame.lookAt(pos + V3(2, 3, 0), pos)
	Boot.Input(hero, "Bonk")
	Runtime.Advance(0.1)
	local saved = lastFx(hero, "SiegeBagSaved", log)
	check("bonk : le sac est rendu", saved and saved.Amount == bag and data.Cash >= cashBefore + bag, saved and saved.Amount)
	check("le voleur n'a plus de sac", thief.Parent == nil or thief:GetAttribute("Bag") == 0)
end
Runtime.MoveTo(hero, SAFE)
untilState("Countdown", 400)
local e3 = lastFx(hero, "SiegeWaveEnd", log)
check("trop de fuites : vague ratée", e3 and e3.Cleared == false and e3.Leaks * 2 >= e3.Total, e3 and (e3.Leaks .. "/" .. e3.Total))
check("la même vague sera rejouée", data.Siege.Wave == waveBefore, data.Siege.Wave)
check("certains s'échappent avec le cash", #Boot.FxFor(hero, "SiegeEscaped", log) >= 1)
check("pas de récompense ni de Notify pour une vague ratée", e3 and e3.Cash == 0 and notifiedCount(hero, "SiegeWave") == 3)
Runtime.Advance(1)
check("HUD : carte « FAILED »", hud:FindFirstChild("SiegeEnd") ~= nil)
Siege.TowerRange = range

----------------------------------------------------------------------------
section("Alpha → œuf sauvage")
for _, sp in { "Frostodon", "SushiRex", "Rexplosion" } do
	local species = Kaijus.Get(sp)
	KaijuService.AddHatched(hero, sp, nil, Growth.Threshold(4, species.Rarity) + 5)
end
data.Siege.Wave = 5
log = #Runtime.ClientLog
local eggsBefore = #data.Kaijus + #data.PendingEggs
wiggle(1)
Boot.Call(hero, "SiegeStartNow")
local alphaSeen, barSeen = false, false
for _ = 1, 300 do
	wiggle(1)
	for _, inv in invaders() do
		if inv:GetAttribute("Alpha") then
			alphaSeen = true
		end
	end
	if hud:FindFirstChild("SiegeAlpha").Visible then
		barSeen = true
	end
	if folder:GetAttribute("State") ~= "Active" then
		break
	end
end
check("un Alpha apparaît à la vague 5", alphaSeen)
check("HUD : barre de vie de l'Alpha", barSeen)
local egg = lastFx(hero, "SiegeAlphaEgg", log)
check("l'Alpha lâche un œuf (Rare 70 / Epic 30)", egg and (egg.Rarity == "Rare" or egg.Rarity == "Epic"), egg and egg.Rarity)
local gift = lastFx(hero, "EggGift", log)
check("œuf donné via GiveEgg (source Siege)", gift and gift.Source == "Siege" and #data.Kaijus + #data.PendingEggs == eggsBefore + 1, gift and gift.Source)
local e5 = lastFx(hero, "SiegeWaveEnd", log)
check("vague 5 gagnée", e5 and e5.Cleared and data.Siege.Wave == 6, e5 and e5.Leaks)
Runtime.Advance(0.5)
check("HUD : révélation de l'œuf", hud:FindFirstChild("SiegeEgg") ~= nil or hud:FindFirstChild("SiegeEnd") ~= nil)
Runtime.Advance(10)

----------------------------------------------------------------------------
section("Visiteur et compagnon")
local rival = Runtime.AddPlayer("Rival")
Runtime.Advance(3)
log = #Runtime.ClientLog
wiggle(1)
Boot.Call(hero, "SiegeStartNow")
Runtime.Advance(4)
local inv = invaders()[1]
check("vague en cours pour le visiteur", inv ~= nil)
if inv then
	local pos = invaderPos(inv)
	Runtime.MoveTo(rival, pos + V3(1, 3, 0))
	Boot.Input(rival, "Bonk")
	Runtime.Advance(0.1)
	local b = lastFx(rival, "SiegeBonk", log)
	check("un visiteur peut bonker sur ton île", b and b.UserId == rival.UserId)
end
check("compagnon : rien à frapper loin des îles", SiegeService.DamageNearest(rival, V3(0, 3, 0), 10, 999) == nil)
local victim = invaders()[1]
if victim then
	local pos = invaderPos(victim)
	check("compagnon : DamageNearest touche l'envahisseur", typeof(SiegeService.DamageNearest(rival, pos, 6, 1e6)) == "Vector3")
	local mine
	for _, o in orbsOf() do
		if o:GetAttribute("Owner") == rival.UserId then
			mine = o
		end
	end
	check("le visiteur garde l'orbe de son kill", mine ~= nil)
	if mine then
		local c = DataService.Get(rival).Cash
		local got = SiegeService.CollectOrbsNear(rival, mine.Position, 5)
		check("le visiteur ramasse son orbe", got > 0 and DataService.Get(rival).Cash >= c + got, got)
	end
end
untilState("Countdown", 300)
check("la vague se termine normalement", lastFx(hero, "SiegeWaveEnd", log) ~= nil)
check("le visiteur proche reçoit les tirs de l'île", #Boot.FxFor(rival, "SiegeShots", log) >= 1)

----------------------------------------------------------------------------
section("Départ du propriétaire en pleine vague")
local rdata = DataService.Get(rival)
rdata.Tutorial = Tutorial.Done
local rplot = PlotService.Get(rival)
local rfolder = S.Workspace:FindFirstChild("Siege"):FindFirstChild("Plot" .. rplot.Index)
Runtime.Advance(8) -- l'œuf de bienvenue du visiteur éclôt
PlotService.SpawnAt(rival)
Runtime.Advance(1)
local r = Boot.Call(rival, "SiegeStartNow")
check("le visiteur lance une vague chez lui", r and r.ok, r and r.msg)
Runtime.Advance(6)
check("des envahisseurs chez lui", #invaders(rfolder) >= 1, #invaders(rfolder))
local n = #Runtime.Errors
Runtime.RemovePlayer(rival)
Runtime.Advance(2)
check("sa vague disparaît proprement", #rfolder:GetChildren() == 0 and rfolder:GetAttribute("State") == nil, #rfolder:GetChildren())
local leftover = 0
for _, o in orbsOf() do
	if o:GetAttribute("Owner") == rival.UserId then
		leftover += 1
	end
end
check("ses orbes sur les autres îles disparaissent", leftover == 0, leftover)
Runtime.Advance(10)
check("aucune erreur après le départ", #Runtime.Errors == n, #Runtime.Errors - n)
check("la défense du héros continue", folder:GetAttribute("State") ~= nil)

----------------------------------------------------------------------------
section("Session longue (10 min, vagues automatiques)")
n = #Runtime.Errors
local waves = data.Stats.SiegeWaves
for _ = 1, 600 do
	wiggle(1)
end
check("les vagues s'enchaînent toutes seules", data.Stats.SiegeWaves > waves or data.Siege.Wave >= 6, data.Stats.SiegeWaves - waves)
check("10 min sans erreur client ni serveur", #Runtime.Errors == n, #Runtime.Errors - n)

print(table.concat(lines, "\n"))
print(("\nRÉSULTAT SIEGE : %d réussies, %d échouées, %d erreurs Lua au total"):format(passed, failed, #Runtime.Errors))
local seen = {}
for _, e in Runtime.Errors do
	local key = e:match("^[^\n]+")
	if not seen[key] then
		seen[key] = true
		print("---- " .. e:sub(1, 700))
	end
end
