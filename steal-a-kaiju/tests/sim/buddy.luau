--!nocheck
-- COMPAGNON (Buddy) de bout en bout : choix automatique, SetBuddy (+ recharge,
-- refus), réaffectation après vente, trésors (apparition, fouille refusée /
-- réussie, butin, expiration, trésor du tutoriel), niveau du compagnon,
-- aimant à orbes, aide au combat, et côté client : modèle qui suit le joueur,
-- pastille HUD, bouton SET AS BUDDY de la fiche kaiju, zéro erreur.
-- Lancer : lune run tests/sim/buddy.luau

local Boot = require("./boot")
local Runtime = Boot.Start()
local ClientRuntime = require("./ClientRuntime")
ClientRuntime.Install(Runtime)
local roblox = require("@lune/roblox")
local V3 = roblox.Vector3.new

local S = Runtime.Services
local function req(inst)
	return Runtime.Globals.require(inst)
end
local Shared = S.ReplicatedStorage:FindFirstChild("Shared")
local Services = S.ServerScriptService:FindFirstChild("Server"):FindFirstChild("Services")
local DataService = req(Services:FindFirstChild("DataService"))
local KaijuService = req(Services:FindFirstChild("KaijuService"))
local PlotService = req(Services:FindFirstChild("PlotService"))
local EventService = req(Services:FindFirstChild("EventService"))
local BuddyService = req(Services:FindFirstChild("BuddyService"))
local SiegeService = req(Services:FindFirstChild("SiegeService"))
local Buddy = req(Shared.Config.Buddy)
local Layout = req(Shared.Config.Layout)
local Levels = req(Shared.Config.Levels)
local Growth = req(Shared.Config.Growth)

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
		print("  ✅ " .. name)
	else
		failed += 1
		print("  ❌ " .. name .. (if detail ~= nil then " — " .. tostring(detail) else ""))
	end
end
local function section(t)
	print("\n## " .. t)
end
local function data(p)
	return DataService.Get(p)
end
local function hatched(p)
	local out = {}
	for _, rec in data(p).Kaijus do
		if not rec.Egg then
			table.insert(out, rec)
		end
	end
	return out
end
local function root(p)
	return p.Character.HumanoidRootPart
end
local function spotOf(p)
	for _, part in S.Workspace:FindFirstChild("DigSpots"):GetChildren() do
		if part:GetAttribute("Owner") == p.UserId then
			return part
		end
	end
	return nil
end
local function flat(a, b)
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
-- Maintient l'invite DIG comme le ferait le client, puis la déclenche.
local function holdDig(p, part, seconds)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	prompt.PromptButtonHoldBegan:Fire(p)
	Runtime.Advance(seconds)
	prompt.Triggered:Fire(p)
	Runtime.Advance(0.1)
end

----------------------------------------------------------------------------
section("Compagnon automatique après la 1re éclosion")
local rival = Runtime.AddPlayer("Rival")
local hero, clientFolder = ClientRuntime.StartClient(Runtime, "Hero")
local logStart = #Runtime.ClientLog
Runtime.Advance(3)
-- tutoriel déjà fini : les trésors automatiques sont actifs (pendant le tutoriel, seule la mission en crée)
for _, p in { hero, rival } do
	local d = DataService.Get(p)
	if d then
		d.Tutorial = 7
	end
end
check("pas de compagnon tant que rien n'a éclos", data(hero).Buddy.Uid == "" and hero:GetAttribute("BuddyUid") == nil, data(hero).Buddy.Uid)
Runtime.Advance(9)
local first = hatched(hero)[1]
check("l'œuf de bienvenue a éclos", first ~= nil)
check("le 1er kaiju éclos devient le compagnon", first and data(hero).Buddy.Uid == first.Uid, data(hero).Buddy.Uid)
check("attributs répliqués (BuddyUid / BuddySpecies / BuddyLevel)", first and hero:GetAttribute("BuddyUid") == first.Uid and hero:GetAttribute("BuddySpecies") == first.Species and hero:GetAttribute("BuddyLevel") == 1)
local changed = Boot.FxFor(hero, "BuddyChanged", logStart)
check("effet BuddyChanged (First, Auto)", #changed >= 1 and changed[1].First == true and changed[1].Reason == "Auto", #changed)
check("le rival a aussi son compagnon", (rival:GetAttribute("BuddyUid") or "") ~= "")

local playerGui = hero:FindFirstChild("PlayerGui")
local UIRegistry = req(clientFolder:FindFirstChild("Controllers"):FindFirstChild("UIRegistry"))
local BuddyRenderer = req(clientFolder:FindFirstChild("World"):FindFirstChild("BuddyRenderer"))
check("aucune erreur au démarrage", #Runtime.Errors == 0, #Runtime.Errors)

----------------------------------------------------------------------------
section("Client : modèle du compagnon qui suit le joueur")
local folder = S.Workspace:FindFirstChild("ClientBuddies")
local heroModel = BuddyRenderer.Model(hero.UserId)
check("modèle 3D du compagnon construit", heroModel ~= nil and heroModel.Parent == folder)
check("compagnon du rival dessiné aussi (vu par tous)", BuddyRenderer.Model(rival.UserId) ~= nil)
check("mini-copie de la bonne espèce", heroModel and heroModel:GetAttribute("Species") == first.Species)
local plot = PlotService.Get(hero)
local walkTarget = plot.CFrame * roblox.CFrame.new(0, 3, 20)
root(hero).CFrame = walkTarget
Runtime.Advance(3)
local function buddyPos()
	local m = BuddyRenderer.Model(hero.UserId)
	return m and m.PrimaryPart.CFrame.Position
end
local expected = (walkTarget * roblox.CFrame.new(Buddy.FollowOffset)).Position
check("le compagnon se place derrière / à droite du joueur", buddyPos() and flat(buddyPos(), expected) < 2, buddyPos() and flat(buddyPos(), expected))
check("le compagnon est posé au sol", buddyPos() and math.abs(buddyPos().Y - (walkTarget.Position.Y - 3)) < 1.5, buddyPos() and buddyPos().Y)
-- marche : il suit en retard (interpolation), sans se téléporter
local before = buddyPos()
root(hero).CFrame = walkTarget * roblox.CFrame.new(0, 0, -8)
Runtime.Advance(0.05)
local mid = buddyPos()
check("il suit en douceur (interpolation)", mid and flat(mid, before) > 0.1 and flat(mid, before) < 8, mid and flat(mid, before))
Runtime.Advance(2)
check("il rattrape le joueur", flat(buddyPos(), root(hero).Position) < 8, flat(buddyPos(), root(hero).Position))
-- trop loin : il se téléporte
root(hero).CFrame = walkTarget * roblox.CFrame.new(0, 0, -100)
Runtime.Advance(0.1)
check("trop loin : téléporté à côté du joueur", flat(buddyPos(), root(hero).Position) < 10, flat(buddyPos(), root(hero).Position))
root(hero).CFrame = walkTarget
Runtime.Advance(1)

----------------------------------------------------------------------------
section("Client : pastille HUD du compagnon")
local chip = BuddyRenderer.Chip()
check("pastille créée et visible", chip ~= nil and chip.Visible == true)
check("pastille rangée dans la colonne de gauche du HUD (sous le niveau)", chip ~= nil and chip.Parent ~= nil and chip.Parent.Name == "LeftColumn")
local function chipText(name)
	for _, d in chip:GetDescendants() do
		if d.Name == name and d.ClassName == "TextLabel" then
			return d.Text
		end
	end
	for _, d in chip:GetDescendants() do
		if d.Name == name then
			local t = d:FindFirstChild("Text")
			return t and t.Text
		end
	end
	return nil
end
check("niveau affiché (LV 1)", chipText("LevelChip") == "LV 1", chipText("LevelChip"))
check("portrait 3D (ViewportFrame)", chip:FindFirstChild("Portrait", true) and chip:FindFirstChild("Portrait", true):FindFirstChildOfClass("ViewportFrame") ~= nil)
check("barre d'XP", chip:FindFirstChild("XpBar", true) ~= nil)

----------------------------------------------------------------------------
section("SetBuddy : changement, recharge, refus")
local mega = KaijuService.AddHatched(hero, "Rexplosion", "Gold", Growth.Threshold(3, "Legendary") + 1)
local shark = KaijuService.AddHatched(hero, "Sharkapillar", nil, 0)
Runtime.Advance(1)
check("le compagnon ne change pas tout seul", data(hero).Buddy.Uid == first.Uid)
local r = Boot.Call(hero, "SetBuddy", { Uid = mega.Uid })
Runtime.Advance(0.2)
check("SetBuddy accepté", r and r.ok == true, r and r.msg)
check("nouveau compagnon enregistré + attributs", data(hero).Buddy.Uid == mega.Uid and hero:GetAttribute("BuddySpecies") == "Rexplosion" and hero:GetAttribute("BuddyMutation") == "Gold")
Runtime.Advance(0.5)
check("le client reconstruit la mini-copie", BuddyRenderer.Model(hero.UserId) and BuddyRenderer.Model(hero.UserId):GetAttribute("Species") == "Rexplosion")
local r2 = Boot.Call(hero, "SetBuddy", { Uid = first.Uid })
check("recharge de 10 s respectée", r2 and r2.ok == false and tostring(r2.msg):find("swap") ~= nil, r2 and r2.msg)
local rivalUid = hatched(rival)[1].Uid
local r3 = Boot.Call(hero, "SetBuddy", { Uid = rivalUid })
check("refus d'un kaiju qui n'est pas à toi", r3 and r3.ok == false and data(hero).Buddy.Uid == mega.Uid, r3 and r3.msg)
local r4 = Boot.Call(hero, "SetBuddy", { Uid = 42 })
check("paramètre invalide refusé", r4 and r4.ok == false)
Runtime.Advance(10.5)
local r5 = Boot.Call(hero, "SetBuddy", { Uid = first.Uid })
check("après la recharge : accepté", r5 and r5.ok == true and data(hero).Buddy.Uid == first.Uid, r5 and r5.msg)

----------------------------------------------------------------------------
section("Client : bouton SET AS BUDDY dans la fiche kaiju")
Runtime.Advance(10.5)
local n = #Runtime.Errors
local panel = UIRegistry.Screens.KaijuPanel
panel.Open({ Uid = shark.Uid })
Runtime.Advance(1)
local button = playerGui:FindFirstChild("SetBuddy", true)
check("bouton SET AS BUDDY présent et visible", button ~= nil and button.Visible == true)
local label = button and button:FindFirstChild("Label", true)
check("texte « SET AS BUDDY »", label and label.Text == "SET AS BUDDY", label and label.Text)
button.MouseButton1Down:Fire()
button.MouseButton1Up:Fire()
button.Activated:Fire()
Runtime.Advance(1)
check("clic : le kaiju devient le compagnon", data(hero).Buddy.Uid == shark.Uid, data(hero).Buddy.Uid)
check("le bouton affiche « YOUR BUDDY »", label and label.Text == "YOUR BUDDY", label and label.Text)
button.Activated:Fire()
Runtime.Advance(0.5)
panel.Open({ Uid = mega.Uid })
Runtime.Advance(0.5)
check("autre kaiju : de nouveau « SET AS BUDDY »", label and label.Text == "SET AS BUDDY", label and label.Text)
panel.Close()
Runtime.Advance(0.5)
check("fiche kaiju sans erreur", #Runtime.Errors == n, #Runtime.Errors - n)

----------------------------------------------------------------------------
section("Réaffectation après vente")
logStart = #Runtime.ClientLog
local sold = Boot.Call(hero, "Sell", { Uid = shark.Uid })
Runtime.Advance(1)
check("vente du compagnon", sold and sold.ok == true)
check("le compagnon passe au meilleur kaiju restant", data(hero).Buddy.Uid == mega.Uid, data(hero).Buddy.Uid)
local lost = Boot.FxFor(hero, "BuddyChanged", logStart)
check("effet BuddyChanged (Lost)", #lost >= 1 and lost[#lost].Reason == "Lost")

----------------------------------------------------------------------------
section("Trésor : apparition")
-- on attend un trésor tout neuf (celui qui aurait pu apparaître plus tôt expire)
local previous = spotOf(hero)
logStart = #Runtime.ClientLog
local spot
for _ = 1, 110 do
	Runtime.Advance(0.5)
	spot = spotOf(hero)
	if spot and spot ~= previous then
		break
	end
	spot = nil
end
check("un trésor apparaît (≤ intervalle)", spot ~= nil)
local treasureFx = Boot.FxFor(hero, "BuddyTreasure", logStart)
check("effet BuddyTreasure envoyé", #treasureFx >= 1)
check("attribut TreasurePos sur le joueur", spot and typeof(hero:GetAttribute("TreasurePos")) == "Vector3" and flat(hero:GetAttribute("TreasurePos"), spot.Position) < 0.01)
local prompt = spot and spot:FindFirstChildOfClass("ProximityPrompt")
check("invite DIG (maintien 1,5 s)", prompt and prompt.ActionText == "DIG" and prompt.HoldDuration == Buddy.DigHold)
check("expire après 45 s", spot and math.abs(spot:GetAttribute("ExpireAt") - S.Workspace:GetServerTimeNow() - Buddy.TreasureLifetime) < 2)
local center = V3(spot.Position.X, 0, spot.Position.Z)
local inArena = false
for _, id in { "Candy", "Frost", "Volcano", "Cosmic" } do
	local o = req(Shared.Config.Worlds).Origin(id)
	if flat(center, o) < 120 then
		inArena = true
	end
end
check("jamais dans une île-arène", not inArena)
check("sur la carte (île, pont ou cratère)", center.Magnitude < Layout.PlotRadius + Layout.PlotDepth)
Runtime.Advance(0.5)
check("client : butte, faisceau et flèches", folder:FindFirstChild("BuddyTreasure") ~= nil and S.Workspace:FindFirstChild("BuddyGuide") ~= nil)
local badge = chip:FindFirstChild("Badge", true)
check("pastille HUD : « ! » quand un trésor est prêt", badge and badge.Visible == true)

-- le trésor du rival : invite désactivée chez nous
local rivalSpot = BuddyService.ForceTreasure(rival) and spotOf(rival)
Runtime.Advance(0.5)
local rivalPrompt = rivalSpot and rivalSpot:FindFirstChildOfClass("ProximityPrompt")
check("trésor d'un autre joueur : invite désactivée localement", rivalPrompt and rivalPrompt.Enabled == false)
check("trésor d'un autre joueur : aucun visuel chez nous", #(function()
	local out = {}
	for _, c in folder:GetChildren() do
		if c.Name == "BuddyTreasure" then
			table.insert(out, c)
		end
	end
	return out
end)() == 1)

----------------------------------------------------------------------------
section("Trésor : fouilles refusées")
local digs0 = data(hero).Stats.Digs
root(hero).CFrame = roblox.CFrame.new(spot.Position + V3(30, 3, 0))
holdDig(hero, spot, 1.6)
check("trop loin (> 8 studs) : refusé", spotOf(hero) == spot and data(hero).Stats.Digs == digs0)
root(hero).CFrame = roblox.CFrame.new(spot.Position + V3(2, 3, 0))
prompt.Triggered:Fire(hero)
Runtime.Advance(0.1)
check("sans maintenir 1,5 s : refusé", spotOf(hero) == spot and data(hero).Stats.Digs == digs0)
root(rival).CFrame = roblox.CFrame.new(spot.Position + V3(-2, 3, 0))
holdDig(rival, spot, 1.6)
check("un autre joueur ne peut pas creuser ton trésor", spotOf(hero) == spot and data(rival).Stats.Digs == 0)

----------------------------------------------------------------------------
section("Trésor : fouille réussie")
logStart = #Runtime.ClientLog
local buddyXp0 = data(hero).Buddy.Xp
local xp0 = data(hero).Xp
local n2 = #Runtime.Errors
holdDig(hero, spot, 1.6)
check("trésor creusé (disparu)", spotOf(hero) == nil and spot.Parent == nil)
check("TreasurePos effacé", hero:GetAttribute("TreasurePos") == nil)
check("statistique Digs +1", data(hero).Stats.Digs == digs0 + 1)
check("XP du compagnon +5", data(hero).Buddy.Xp - buddyXp0 >= Buddy.Xp.Dig, data(hero).Buddy.Xp - buddyXp0)
check("XP du joueur (Levels.Xp.Dig)", data(hero).Xp - xp0 >= Levels.Xp.Dig, data(hero).Xp - xp0)
local digFx = Boot.FxFor(hero, "BuddyDig", logStart)
check("effet BuddyDig avec butin", #digFx == 1 and digFx[1].Kind ~= nil and digFx[1].Text ~= nil, digFx[1] and digFx[1].Kind)
check("effet BuddyDigWorld pour les autres", #Boot.FxFor(rival, "BuddyDigWorld", logStart) == 1)
Runtime.Advance(3)
check("client : coffre, pièces et visuels nettoyés sans erreur", #Runtime.Errors == n2 and folder:FindFirstChild("BuddyTreasure") == nil, #Runtime.Errors - n2)
check("client : flèches cachées", S.Workspace:FindFirstChild("BuddyGuide") == nil)
check("client : « ! » éteint", badge.Visible == false)

-- Butin : plusieurs fouilles (trésor du tutoriel), chaque type vérifié
local kinds = {}
local okLoot = true
local detail = ""
for _ = 1, 40 do
	local d = data(hero)
	local cash, gems, potions, eggs = d.Cash, d.Gems, d.Potions.Growth, #d.Kaijus + #d.PendingEggs
	local pos = BuddyService.ForceTreasure(hero)
	local part = spotOf(hero)
	root(hero).CFrame = roblox.CFrame.new(pos + V3(1, 3, 0))
	logStart = #Runtime.ClientLog
	holdDig(hero, part, 1.6)
	local fx = Boot.FxFor(hero, "BuddyDig", logStart)[1]
	if not fx then
		okLoot = false
		detail = "pas de BuddyDig"
		break
	end
	kinds[fx.Kind] = (kinds[fx.Kind] or 0) + 1
	d = data(hero)
	local good = if fx.Kind == "Cash"
		then d.Cash >= cash + math.max(Buddy.CashMin, fx.Amount) - 1 and fx.Amount >= Buddy.CashMin
		elseif fx.Kind == "Gems" then d.Gems == gems + fx.Amount and fx.Amount >= 2 and fx.Amount <= 5
		elseif fx.Kind == "Potion" then d.Potions.Growth == potions + 1
		elseif fx.Kind == "Egg" then (#d.Kaijus + #d.PendingEggs) == eggs + 1 and (fx.Rarity == "Rare" or fx.Rarity == "Epic" or fx.Rarity == "Legendary")
		else false
	if not good then
		okLoot = false
		detail = fx.Kind
	end
end
local seen = {}
for k, v in kinds do
	table.insert(seen, k .. "=" .. v)
end
check("butin conforme à chaque fouille (cash / potion / gemmes / œuf)", okLoot, detail)
check("butin varié (cash le plus fréquent)", kinds.Cash and kinds.Cash >= 15 and (kinds.Potion or 0) >= 1, table.concat(seen, " "))

----------------------------------------------------------------------------
section("Trésor du tutoriel (ForceTreasure) et expiration")
local spawnPos = (plot.CFrame * roblox.CFrame.new(Layout.Spawn)).Position
root(hero).CFrame = roblox.CFrame.new(spawnPos)
local forced = BuddyService.ForceTreasure(hero)
check("ForceTreasure renvoie une position", typeof(forced) == "Vector3")
local d = forced and flat(forced, spawnPos)
check("à 15-25 studs du spawn (jamais > 40)", d and d >= 15 and d <= 25, d)
check("sur l'île du joueur", forced and Layout.InPlot(plot.CFrame, forced + V3(0, 1, 0)))
check("TreasurePos = position forcée", hero:GetAttribute("TreasurePos") == forced)
logStart = #Runtime.ClientLog
Runtime.Advance(Buddy.TreasureLifetime + 1)
check("expiré après 45 s", spotOf(hero) == nil)
check("effet BuddyTreasureGone", #Boot.FxFor(hero, "BuddyTreasureGone", logStart) == 1)
check("TreasurePos effacé à l'expiration", hero:GetAttribute("TreasurePos") == nil)

----------------------------------------------------------------------------
section("Niveau du compagnon")
check("formule du niveau", Buddy.Level(0) == 1 and Buddy.Level(10) == 2 and Buddy.Level(90) == 4 and Buddy.Level(10 ^ 9) == 50)
check("l'aimant grandit avec le niveau", Buddy.MagnetRadius(10) > Buddy.MagnetRadius(1))
check("les trésors arrivent plus vite avec le niveau", Buddy.TreasureInterval(30) < Buddy.TreasureInterval(1))
logStart = #Runtime.ClientLog
local lvl0 = BuddyService.Level(hero)
local height0 = BuddyRenderer.Model(hero.UserId):GetAttribute("Height")
BuddyService.AddXp(hero, Buddy.XpFor(lvl0 + 2) - data(hero).Buddy.Xp, "Test")
Runtime.Advance(0.5)
check("le niveau monte", BuddyService.Level(hero) == lvl0 + 2 and hero:GetAttribute("BuddyLevel") == lvl0 + 2, BuddyService.Level(hero))
check("effet BuddyLevelUp", #Boot.FxFor(hero, "BuddyLevelUp", logStart) == 1)
Runtime.Advance(0.5)
check("pastille HUD : niveau à jour", chipText("LevelChip") == ("LV %d"):format(lvl0 + 2), chipText("LevelChip"))
local height1 = BuddyRenderer.Model(hero.UserId):GetAttribute("Height")
check("le modèle grandit un peu", height1 > height0, ("%.2f -> %.2f"):format(height0, height1))

----------------------------------------------------------------------------
section("Aimant : orbes de Stampede")
root(rival).CFrame = PlotService.Get(rival).CFrame * roblox.CFrame.new(0, 3, 30)
EventService.Stop()
Runtime.Advance(0.5)
EventService.Force("Stampede")
Runtime.Advance(2)
local orbs = S.Workspace:FindFirstChild("Orbs"):GetChildren()
check("vague d'orbes", #orbs > 0, #orbs)
local target = orbs[1]
local radius = BuddyService.MagnetRadius(hero)
check("rayon d'aimant > ramassage à la main (14)", radius > 14, radius)
root(hero).CFrame = roblox.CFrame.new(target.Position + V3(radius - 1.5, 3, 0))
logStart = #Runtime.ClientLog
local orbs0 = data(hero).Stats.Orbs
local bxp = data(hero).Buddy.Xp
Runtime.Advance(0.6)
check("orbe hors de portée de main attrapée par l'aimant", target.Parent == nil)
local grabbedCount = data(hero).Stats.Orbs - orbs0
check("stat Orbs et cash versés", grabbedCount >= 1 and #Boot.FxFor(hero, "OrbGrabbed", logStart) >= 1, grabbedCount)
-- (la stat Orbs compte aussi les orbes de la défense d'île ramassées à pied : on compte les Fx de Stampede)
local stampedeGrabbed = #Boot.FxFor(hero, "OrbGrabbed", logStart)
check("XP compagnon +1 par orbe", data(hero).Buddy.Xp - bxp >= stampedeGrabbed * Buddy.Xp.Orb, (data(hero).Buddy.Xp - bxp) .. " xp / " .. stampedeGrabbed)
check("effet BuddyMagnet (positions)", #Boot.FxFor(hero, "BuddyMagnet", logStart) >= 1)
EventService.Stop()
Runtime.Advance(1)

----------------------------------------------------------------------------
section("Aide au combat")
-- siège (contrat défensif : SiegeService.DamageNearest / CollectOrbsNear)
local calls = {}
local realDamage, realCollect = SiegeService.DamageNearest, SiegeService.CollectOrbsNear
SiegeService.DamageNearest = function(p, pos, range, dmg)
	if p == hero then
		table.insert(calls, { p = p, range = range, dmg = dmg })
	end
	return pos + V3(5, 0, 0), true
end
SiegeService.CollectOrbsNear = function()
	return 500, 2
end
root(hero).CFrame = plot.CFrame * roblox.CFrame.new(0, 3, -10)
logStart = #Runtime.ClientLog
bxp = data(hero).Buddy.Xp
Runtime.Advance(1.6)
check("siège : DamageNearest appelé (portée 18, 4 x puissance)", #calls >= 1 and calls[1].range == 18 and calls[1].dmg > 0 and calls[1].p == hero, #calls)
check("siège : bond d'attaque (BuddyPounce)", #Boot.FxFor(hero, "BuddyPounce", logStart) >= 1)
check("siège : XP +2 par kill aidé, +1 par orbe de siège", data(hero).Buddy.Xp - bxp >= Buddy.Xp.SiegeKill + 2, data(hero).Buddy.Xp - bxp)
local offIsland = #calls
root(hero).CFrame = roblox.CFrame.new(0, 3, 0)
Runtime.Advance(3.2)
check("siège : pas d'aide hors de ton île", #calls == offIsland)
SiegeService.DamageNearest = realDamage
SiegeService.CollectOrbsNear = realCollect
-- boss
EventService.Stop()
Runtime.Advance(0.5)
EventService.Force("BossRaid")
Runtime.Advance(3)
local boss = S.Workspace:FindFirstChild("Effects"):FindFirstChild("Boss")
check("boss présent", boss ~= nil)
local hp0 = boss and boss:GetAttribute("HP")
logStart = #Runtime.ClientLog
root(hero).CFrame = roblox.CFrame.new(20, 3, 0)
Runtime.Advance(3.1)
local hits = Boot.FxFor(hero, "BossHit", logStart)
check("boss : le compagnon frappe (BossHit Buddy)", #hits >= 1 and hits[1].Buddy == true and boss:GetAttribute("HP") < hp0, #hits)
check("boss : bond d'attaque vers le boss", #Boot.FxFor(hero, "BuddyPounce", logStart) >= 1)
local nb = #hits
root(hero).CFrame = plot.CFrame * roblox.CFrame.new(0, 3, 0)
Runtime.Advance(3.1)
check("boss : trop loin, aucun coup", #Boot.FxFor(hero, "BossHit", logStart) == nb)
EventService.Stop()
Runtime.Advance(2)

----------------------------------------------------------------------------
section("Session : trésors réguliers, 0 erreur")
local n3 = #Runtime.Errors
local spawned = 0
local lastId
for _ = 1, 300 do
	Runtime.Advance(1)
	local s = spotOf(hero)
	if s and s:GetAttribute("Id") ~= lastId then
		spawned += 1
		lastId = s:GetAttribute("Id")
	end
end
check("un trésor environ toutes les 50 s (5 min → 5-8)", spawned >= 5 and spawned <= 8, spawned)
chip.Activated:Fire()
Runtime.Advance(1)
check("clic sur la pastille sans erreur", #Runtime.Errors == n3, #Runtime.Errors - n3)
check("5 min sans erreur client ni serveur", #Runtime.Errors == 0, #Runtime.Errors)

print(("\nRÉSULTAT BUDDY : %d réussies, %d échouées, %d erreurs Lua au total"):format(passed, failed, #Runtime.Errors))
local shown = {}
local count = 0
for _, e in Runtime.Errors do
	local key = e:match("^[^\n]+")
	if not shown[key] and count < 15 then
		shown[key] = true
		count += 1
		print("---- " .. e:sub(1, 900))
	end
end
