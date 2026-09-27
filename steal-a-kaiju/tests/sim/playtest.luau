--!nocheck
-- PLAYTEST AUTOMATISÉ : exécute le vrai code serveur avec 3 joueurs simulés
-- et vérifie chaque boucle de gameplay. Lancer : lune run tests/sim/playtest.luau

local Boot = require("./boot")
local Runtime = Boot.Start()
local roblox = require("@lune/roblox")
local V3 = roblox.Vector3.new

local passed, failed = 0, 0
local report = {}
local function check(name, cond, detail)
	if cond then
		passed += 1
		table.insert(report, "  ✅ " .. name)
	else
		failed += 1
		table.insert(report, "  ❌ " .. name .. (if detail then " — " .. tostring(detail) else ""))
	end
end
local function section(title)
	table.insert(report, "\n## " .. title)
end

local S = Runtime.Services
local Shared = S.ReplicatedStorage:FindFirstChild("Shared")
local Server = S.ServerScriptService:FindFirstChild("Server")
local function req(inst)
	return Runtime.Globals.require(inst)
end
local Services = Server:FindFirstChild("Services")
local DataService = req(Services:FindFirstChild("DataService"))
local KaijuService = req(Services:FindFirstChild("KaijuService"))
local PlotService = req(Services:FindFirstChild("PlotService"))
local EventService = req(Services:FindFirstChild("EventService"))
local Growth = req(Shared.Config.Growth)
local Kaijus = req(Shared.Config.Kaijus)
local Calc = req(Shared.Logic.Calc)

local function data(p)
	return DataService.Get(p)
end
local function hatchedOf(p)
	local out = {}
	for _, rec in data(p).Kaijus do
		if not rec.Egg then
			table.insert(out, rec)
		end
	end
	return out
end
local function anchorPos(uid)
	local a = KaijuService.Anchor(uid)
	return a and a.Position
end
local function plotCenter(p)
	return PlotService.Get(p).CFrame.Position
end

----------------------------------------------------------------------------
section("Connexion")
local alice = Runtime.AddPlayer("Alice")
local bob = Runtime.AddPlayer("Bob")
local carl = Runtime.AddPlayer("Carl")
Runtime.Advance(2)
check("données chargées pour 3 joueurs", data(alice) and data(bob) and data(carl))
check("îles attribuées", PlotService.Get(alice) and PlotService.Get(bob) and PlotService.Get(carl))
check("cash de départ", data(alice).Cash == 100, data(alice).Cash)
check("œuf de bienvenue posé", #data(alice).Kaijus == 1 and data(alice).Kaijus[1].Egg == true)
check("outil Bonker donné", alice:FindFirstChild("Backpack"):FindFirstChild("Bonker") ~= nil)
check("leaderstats créés", alice:FindFirstChild("leaderstats") ~= nil)

----------------------------------------------------------------------------
section("Éclosion et revenus")
local logStart = #Runtime.ClientLog
Runtime.Advance(8)
local hatches = Boot.FxFor(alice, "Hatch", logStart)
check("l'œuf a éclos (cinématique envoyée)", #hatches >= 1, #hatches)
check("un kaiju éclos", #hatchedOf(alice) == 1)
local species = hatchedOf(alice)[1] and hatchedOf(alice)[1].Species
check("espèce commune", species and Kaijus.Get(species).Rarity == "Common", species)
check("Kaijudex mis à jour", data(alice).Index[species] ~= nil)
Runtime.Advance(20)
check("le réacteur accumule du cash", data(alice).Stored > 0, data(alice).Stored)

-- Collecte en marchant sur le pad
local cashBefore = data(alice).Cash
local stored = data(alice).Stored
PlotService.Get(alice).Collector.Touched:Fire(alice.Character.HumanoidRootPart)
Runtime.Advance(0.1)
check("collecte : cash transféré", data(alice).Cash >= cashBefore + math.floor(stored) - 1, data(alice).Cash)
check("collecte : réacteur vidé", data(alice).Stored < 5, data(alice).Stored)

----------------------------------------------------------------------------
section("Météores")
local meteorsFolder = S.Workspace:FindFirstChild("Meteors")
local landed
for _ = 1, 60 do
	Runtime.Advance(1)
	for _, m in meteorsFolder:GetChildren() do
		local r = m:GetAttribute("Rarity")
		if (m:GetAttribute("Owner") or 0) == 0 and m:GetAttribute("LandAt") <= Runtime.Now() + 1790000000 and (r == "Common" or r == "Rare") then
			landed = m
		end
	end
	if landed then
		break
	end
end
check("un météore Commun ou Rare est tombé dans le cratère", landed ~= nil)
if landed then
	local id = landed:GetAttribute("Id")
	local far = Boot.Call(alice, "BuyMeteor", { Id = id })
	check("achat refusé si trop loin", far and far.ok == false, far and far.msg)
	Runtime.MoveTo(alice, landed.Position + V3(3, 0, 0))
	local r = Boot.Call(alice, "BuyMeteor", { Id = id })
	check("premier œuf acheté (gratuit)", r and r.ok and r.free, r and r.msg)
	Runtime.Advance(2)
	check("l'œuf acheté est dans un nid", #data(alice).Kaijus == 2, #data(alice).Kaijus)
	check("quête/statistique EggsBought", data(alice).Stats.EggsBought == 1)
	local again = Boot.Call(bob, "BuyMeteor", { Id = id })
	check("impossible d'acheter deux fois le même œuf", again and not again.ok)
end
-- Météore personnel
Runtime.Advance(40)
local personal
for _, m in meteorsFolder:GetChildren() do
	if m:GetAttribute("Owner") == bob.UserId then
		personal = m
	end
end
check("météore personnel tombé sur l'île de Bob", personal ~= nil)
if personal then
	Runtime.MoveTo(alice, personal.Position)
	local r = Boot.Call(alice, "BuyMeteor", { Id = personal:GetAttribute("Id") })
	check("Alice ne peut pas acheter le météore perso de Bob", r and not r.ok, r and r.msg)
end

----------------------------------------------------------------------------
section("Vol simple")
-- Fin de la protection des nouveaux joueurs
Runtime.Advance(160)
local bobKaiju = hatchedOf(bob)[1]
check("Bob a un kaiju éclos", bobKaiju ~= nil)
if bobKaiju then
	Runtime.MoveTo(alice, anchorPos(bobKaiju.Uid) + V3(2, 0, 0))
	local r = Boot.Call(alice, "Steal", { Uid = bobKaiju.Uid })
	check("Alice attrape le kaiju de Bob", r and r.ok, r and r.msg)
	check("alarme envoyée à Bob", #Boot.FxFor(bob, "Alarm") >= 1)
	local speed = alice.Character.Humanoid.WalkSpeed
	check("Alice est ralentie en portant", speed < 22, speed)
	check("Bob ne gagne plus avec ce kaiju", KaijuService.Anchor(bobKaiju.Uid):GetAttribute("CarriedBy") == alice.UserId)
	-- Alice rentre chez elle en marchant
	Boot.WalkTo({ { alice } }, plotCenter(alice))
	Runtime.Advance(0.5)
	local found = false
	for _, rec in data(alice).Kaijus do
		if rec.Species == bobKaiju.Species and not rec.Egg then
			found = true
		end
	end
	check("livraison : le kaiju appartient à Alice", found)
	check("livraison : retiré de chez Bob", #hatchedOf(bob) == 0, #hatchedOf(bob))
	check("statistique Steals d'Alice", data(alice).Stats.Steals == 1)
	check("cinématique de casse envoyée", #Boot.FxFor(alice, "HeistSuccess") == 1)
	check("Bob notifié du vol", #Boot.FxFor(bob, "Robbed") == 1)
	check("vitesse d'Alice restaurée", alice.Character.Humanoid.WalkSpeed >= 22)
end

----------------------------------------------------------------------------
section("Anti-triche")
local victimKaiju = hatchedOf(bob)[1] or hatchedOf(carl)[1]
if victimKaiju then
	local owner = if hatchedOf(bob)[1] then bob else carl
	Runtime.MoveTo(alice, anchorPos(victimKaiju.Uid) + V3(2, 0, 0))
	Runtime.Advance(3.5)
	local r = Boot.Call(alice, "Steal", { Uid = victimKaiju.Uid })
	check("vol lancé", r and r.ok, r and r.msg)
	Runtime.Advance(0.3)
	Runtime.MoveTo(alice, plotCenter(alice))
	Runtime.Advance(0.3)
	check("téléportation pendant un vol : le kaiju est lâché", KaijuService.Anchor(victimKaiju.Uid) ~= nil and KaijuService.Anchor(victimKaiju.Uid):GetAttribute("CarriedBy") == 0)
	local still = false
	for _, rec in data(owner).Kaijus do
		if rec.Uid == victimKaiju.Uid then
			still = true
		end
	end
	check("le kaiju reste à son propriétaire", still)
	Runtime.Advance(4)
end
local fake = Boot.Call(alice, "Steal", { Uid = "n'existe-pas" })
check("vol d'un kaiju inexistant refusé", fake and not fake.ok)
local junk = Boot.Call(alice, "Sell", { Uid = 42 })
check("paramètre invalide rejeté proprement", junk and not junk.ok)
local unknown = Boot.Call(alice, "GiveMeMoney", {})
check("action inconnue rejetée", unknown and not unknown.ok)
local spam = 0
for _ = 1, 30 do
	local x = Boot.Call(alice, "Lock")
	if x and x.msg == "Slow down!" then
		spam += 1
	end
end
check("limitation de débit (anti-spam)", spam > 0, spam)

----------------------------------------------------------------------------
section("Bonk : défendre sa base")
local carlKaiju = hatchedOf(carl)[1]
if carlKaiju then
	local pos = anchorPos(carlKaiju.Uid)
	Runtime.MoveTo(bob, pos + V3(2, 0, 0))
	local r = Boot.Call(bob, "Steal", { Uid = carlKaiju.Uid })
	check("Bob attrape le kaiju de Carl", r and r.ok, r and r.msg)
	-- Carl arrive derrière Bob et le bonke
	local bobPos = bob.Character.HumanoidRootPart.Position
	carl.Character.HumanoidRootPart.CFrame = Runtime.CFrame.lookAt(bobPos + V3(0, 0, 4), bobPos)
	Runtime.Advance(1)
	Boot.Input(carl, "Bonk")
	Runtime.Advance(0.2)
	check("le bonk fait lâcher le kaiju", KaijuService.Anchor(carlKaiju.Uid):GetAttribute("CarriedBy") == 0)
	check("Bob reçoit un recul", #Boot.FxFor(bob, "Knockback") >= 1)
	check("Carl compte un sauvetage", data(carl).Stats.Saves == 1)
	local cooldown = #Boot.FxFor(carl, "BonkSwing")
	Boot.Input(carl, "Bonk")
	Runtime.Advance(0.05)
	check("délai entre deux bonks", #Boot.FxFor(carl, "BonkSwing") == cooldown)
else
	check("Carl a un kaiju", false)
end

----------------------------------------------------------------------------
section("Bouclier")
local lock = Boot.Call(carl, "Lock")
check("Carl verrouille sa base", lock and lock.ok, lock and lock.msg)
local carlKaiju2 = hatchedOf(carl)[1]
if carlKaiju2 then
	Runtime.MoveTo(alice, anchorPos(carlKaiju2.Uid) + V3(2, 0, 0))
	Runtime.Advance(0.3)
	check("intrus expulsé par le bouclier", not require("@lune/roblox") or (alice.Character.HumanoidRootPart.Position - anchorPos(carlKaiju2.Uid)).Magnitude > 20)
	Runtime.MoveTo(alice, anchorPos(carlKaiju2.Uid) + V3(2, 0, 0))
	local r = Boot.Call(alice, "Steal", { Uid = carlKaiju2.Uid })
	check("vol impossible sous bouclier", r and not r.ok, r and r.msg)
end
local relock = Boot.Call(carl, "Lock")
check("pas de double verrouillage", relock and not relock.ok)

----------------------------------------------------------------------------
section("Casse à deux (Titan)")
-- On donne un Titan à Bob
local titan = KaijuService.AddHatched(bob, "Frostodon", nil, Growth.Threshold(4, "Rare") + 1)
Runtime.Advance(1.2)
check("Titan créé chez Bob", titan and Calc.Stage(titan) == 4)
if titan then
	Runtime.MoveTo(alice, anchorPos(titan.Uid) + V3(3, 0, 0))
	Runtime.Advance(3.5)
	local r = Boot.Call(alice, "Steal", { Uid = titan.Uid })
	check("Alice soulève le Titan (attend de l'aide)", r and r.ok and r.lifting, r and r.msg)
	check("Alice presque immobile", alice.Character.Humanoid.WalkSpeed <= 4)
	Runtime.MoveTo(carl, alice.Character.HumanoidRootPart.Position + V3(3, 0, 0))
	local h = Boot.Call(carl, "Steal", { Uid = titan.Uid })
	check("Carl aide à porter", h and h.ok, h and h.msg)
	check("vitesse de portage d'un Titan", alice.Character.Humanoid.WalkSpeed < 16, alice.Character.Humanoid.WalkSpeed)
	local carlCash = data(carl).Cash
	Boot.WalkTo({ { alice }, { carl, V3(4, 0, 0) } }, plotCenter(alice))
	Runtime.Advance(0.5)
	local owned = false
	for _, rec in data(alice).Kaijus do
		if rec.Species == "Frostodon" then
			owned = true
		end
	end
	check("le Titan est livré chez Alice", owned)
	check("Carl touche sa part du butin", data(carl).Cash > carlCash, data(carl).Cash - carlCash)
end
-- Aide trop loin => le Titan tombe
local titan2 = KaijuService.AddHatched(bob, "Kaijumbo", nil, Growth.Threshold(4, "Mythic") + 1)
Runtime.Advance(3.5)
if titan2 then
	Runtime.MoveTo(alice, anchorPos(titan2.Uid) + V3(3, 0, 0))
	Boot.Call(alice, "Steal", { Uid = titan2.Uid })
	Runtime.MoveTo(carl, alice.Character.HumanoidRootPart.Position + V3(3, 0, 0))
	Boot.Call(carl, "Help", { Uid = titan2.Uid })
	Runtime.MoveTo(carl, alice.Character.HumanoidRootPart.Position + V3(80, 0, 0))
	Runtime.Advance(0.3)
	check("partenaire trop loin : le Titan retombe", KaijuService.Anchor(titan2.Uid):GetAttribute("CarriedBy") == 0)
	-- Seul, le levage expire
	Runtime.Advance(4)
	Runtime.MoveTo(alice, anchorPos(titan2.Uid) + V3(3, 0, 0))
	Boot.Call(alice, "Steal", { Uid = titan2.Uid })
	Runtime.Advance(13)
	check("levage seul : abandon après le délai", KaijuService.Anchor(titan2.Uid):GetAttribute("CarriedBy") == 0)
end

----------------------------------------------------------------------------
section("Boutique (achats simulés Studio)")
local vip = Boot.Call(alice, "Buy", { Kind = "Pass", Key = "VIP" })
check("pass VIP simulé", vip and vip.ok, vip and vip.msg)
Runtime.Advance(1)
local mult = KaijuService.Multiplier(alice)
check("le VIP augmente le multiplicateur", mult >= 1.2, mult)
local gems = data(alice).Gems
local g = Boot.Call(alice, "Buy", { Kind = "Product", Key = "Gems550" })
check("pack de gemmes", g and g.ok and data(alice).Gems == gems + 550, data(alice).Gems)
local cashP = data(alice).Cash
Boot.Call(alice, "Buy", { Kind = "Product", Key = "CashM" })
check("pack de cash (>= 1000)", data(alice).Cash >= cashP + 1000)
local starter = Boot.Call(alice, "Buy", { Kind = "Product", Key = "StarterPack" })
Runtime.Advance(0.5)
check("starter pack", starter and starter.ok and data(alice).StarterPack)
local starter2 = Boot.Call(alice, "Buy", { Kind = "Product", Key = "StarterPack" })
check("starter pack une seule fois", starter2 and not starter2.ok)
local luck = Boot.Call(bob, "Buy", { Kind = "Product", Key = "ServerLuck" })
Runtime.Advance(1)
check("chance serveur x2", luck and luck.ok and S.Workspace:GetAttribute("ServerLuck") == 2)
local potion = Boot.Call(alice, "BuyPotion", { Id = "Growth" })
check("achat de potion en gemmes", potion and potion.ok)
local use = Boot.Call(alice, "UsePotion", { Id = "Growth" })
check("potion utilisée", use and use.ok and KaijuService.GrowthRate(alice) >= 2)
data(alice).Cash += 100000
local up = Boot.Call(alice, "BuyUpgrade", { Id = "Sneakers" })
Runtime.Advance(0.1)
check("amélioration Rocket Sneakers", up and up.ok and alice.Character.Humanoid.WalkSpeed == 24, alice.Character.Humanoid.WalkSpeed)
local nest = Boot.Call(alice, "BuyNest")
check("achat d'un nid", nest and nest.ok and data(alice).Nests == 7)

-- Politique : joueur en zone restreinte
Runtime.PaidRandomRestricted = true
local dave = Runtime.AddPlayer("Dave")
Runtime.Advance(2)
local blocked = Boot.Call(dave, "Buy", { Kind = "Product", Key = "Spins3" })
check("hasard payant bloqué en zone restreinte", blocked and not blocked.ok, blocked and blocked.msg)
local allowed = Boot.Call(dave, "Buy", { Kind = "Product", Key = "ShieldNow" })
check("achat non aléatoire autorisé", allowed and allowed.ok, allowed and allowed.msg)
Runtime.PaidRandomRestricted = false

----------------------------------------------------------------------------
section("Récompenses")
local daily = Boot.Call(alice, "ClaimDaily")
check("récompense quotidienne", daily and daily.ok and daily.streak == 1, daily and daily.msg)
local daily2 = Boot.Call(alice, "ClaimDaily")
check("pas deux fois le même jour", daily2 and not daily2.ok)
local code = Boot.Call(alice, "Redeem", { Code = " release " })
check("code RELEASE", code and code.ok, code and code.msg)
local code2 = Boot.Call(alice, "Redeem", { Code = "RELEASE" })
check("code déjà utilisé", code2 and not code2.ok)
local bad = Boot.Call(alice, "Redeem", { Code = "NOPE" })
check("code invalide", bad and not bad.ok)
local gift = Boot.Call(alice, "ClaimPlaytime", { Index = 1 })
check("cadeau de 1 min disponible", gift and gift.ok, gift and gift.msg)
local gift10 = Boot.Call(alice, "ClaimPlaytime", { Index = 10 })
check("cadeau de 60 min pas encore dispo", gift10 and not gift10.ok)
local spin = Boot.Call(alice, "Spin")
check("tour de roue gratuit", spin and spin.ok and spin.index >= 1, spin and spin.msg)
Runtime.Advance(5)
local spin2 = Boot.Call(alice, "Spin")
check("tour avec le spin offert", spin2 and spin2.ok, spin2 and spin2.msg)
local quests = data(alice).Quests
check("3 quêtes du jour", #quests.List == 3, #quests.List)

----------------------------------------------------------------------------
section("Fusion et Évolution")
-- On libère les nids d'Alice
for _, rec in table.clone(data(alice).Kaijus) do
	KaijuService.RemoveRecord(alice, rec.Uid)
end
local a = KaijuService.AddHatched(alice, "Toastzilla", nil, Growth.Threshold(3, "Common") + 1)
local b = KaijuService.AddHatched(alice, "Sharkapillar", nil, Growth.Threshold(3, "Rare") + 1)
Runtime.Advance(1.2)
if a and b then
	local odds = Boot.Call(alice, "FuseOdds", { A = a.Uid, B = b.Uid })
	check("probabilités de fusion affichées", odds and odds.ok and odds.odds[1].Chance == 1)
	local f = Boot.Call(alice, "Fuse", { A = a.Uid, B = b.Uid })
	check("recette secrète : Sharktoast Supreme", f and f.ok and f.species == "SharktoastSupreme", f and (f.msg or f.species))
end
local c1 = KaijuService.AddHatched(alice, "Pinchy", nil, 0)
local c2 = KaijuService.AddHatched(alice, "Gloop", nil, 0)
Runtime.Advance(1.2)
if c1 and c2 then
	local f = Boot.Call(alice, "Fuse", { A = c1.Uid, B = c2.Uid })
	check("fusion refusée pour des bébés", f and not f.ok)
end
-- Évolution
for _, rec in table.clone(data(alice).Kaijus) do
	if rec.Egg then
		KaijuService.RemoveRecord(alice, rec.Uid)
	end
end
local legend = KaijuService.AddHatched(alice, "Rexplosion", nil, Growth.Threshold(3, "Legendary") + 1)
data(alice).Cash = 10 ^ 7
local rebirth = Boot.Call(alice, "Rebirth")
Runtime.Advance(1)
check("évolution réussie", rebirth and rebirth.ok and data(alice).Rebirths == 1, rebirth and rebirth.msg)
check("évolution : cash remis à zéro", data(alice).Cash == 100, data(alice).Cash)
check("évolution : œuf bonus offert", #data(alice).Kaijus == 1 and data(alice).Kaijus[1].Egg)
check("évolution : multiplicateur x1.5", Calc.RebirthMult(1) == 1.5)


----------------------------------------------------------------------------
section("Événements mondiaux et boss")
EventService.Stop()
EventService.Force("BossRaid")
Runtime.Advance(2)
local boss = S.Workspace:FindFirstChild("Effects"):FindFirstChild("Boss")
check("le Colosse apparaît", boss ~= nil)
if boss then
	local hp = boss:GetAttribute("HP")
	for _, p in { alice, bob, carl } do
		Runtime.MoveTo(p, V3(10, 3, 0))
	end
	for _ = 1, 400 do
		for _, p in { alice, bob, carl } do
			Boot.Input(p, "Bonk")
		end
		Runtime.Advance(0.5)
		if not boss.Parent or (boss:GetAttribute("HP") or 0) <= 0 then
			break
		end
	end
	check("le Colosse perd des PV", (boss:GetAttribute("HP") or 0) < hp)
	check("le Colosse est vaincu", (boss:GetAttribute("HP") or 1) <= 0)
	Runtime.Advance(3)
	check("récompenses de raid", #Boot.FxFor(alice, "BossReward") >= 1)
end
Runtime.Advance(5)
EventService.Stop()
EventService.Force("BloodMoon")
Runtime.Advance(1)
check("Lune de sang active", S.Workspace:GetAttribute("EventId") == "BloodMoon")
Runtime.Advance(150)
check("Lune de sang terminée", S.Workspace:GetAttribute("EventId") ~= "BloodMoon")
EventService.Stop()
EventService.Force("Stampede")
Runtime.Advance(3)
local orbs = S.Workspace:FindFirstChild("Orbs"):GetChildren()
check("des orbes apparaissent", #orbs > 0, #orbs)
if #orbs > 0 then
	local o = orbs[1]
	Runtime.MoveTo(bob, o.Position)
	local before = data(bob).Cash
	Boot.Input(bob, "Orb", { Id = o:GetAttribute("Id") })
	Runtime.Advance(0.1)
	check("orbe ramassé = cash", data(bob).Cash > before)
end

----------------------------------------------------------------------------
section("Hors ligne et reconnexion")
local bobId = bob.UserId
local bobKaijus = #data(bob).Kaijus
Runtime.RemovePlayer(bob)
Runtime.Advance(3600)
local bob2 = Runtime.AddPlayer("Bob", bobId)
Runtime.Advance(3)
check("Bob retrouve ses kaijus", data(bob2) and #data(bob2).Kaijus >= bobKaijus, data(bob2) and #data(bob2).Kaijus)
check("gains hors ligne crédités", #Boot.FxFor(bob2, "WelcomeBack") >= 1)

----------------------------------------------------------------------------
section("Longue session (2 h de jeu simulé)")
local errorsBefore = #Runtime.Errors
Runtime.Advance(7200)
check("aucune erreur pendant 2 h", #Runtime.Errors == errorsBefore, #Runtime.Errors - errorsBefore)
local events = 0
for _, e in Runtime.ClientLog do
	if e.remote == "Fx" and e.args[1] == "EventStart" then
		events += 1
	end
end
check("rotation des événements", events >= 8, events)
check("économie : Alice gagne de l'argent", data(alice).TotalEarned > 0, data(alice).TotalEarned)

print(table.concat(report, "\n"))
print(("\nRÉSULTAT : %d vérifications réussies, %d échouées, %d erreurs Lua"):format(passed, failed, #Runtime.Errors))
for i, e in Runtime.Errors do
	if i <= 10 then
		print("---- erreur " .. i .. "\n" .. e)
	end
end
