--!nocheck
-- PLAYTEST RAMPAGE : le mode « deviens ton kaiju et écrase une ville en jouet »
-- joué de bout en bout contre le vrai serveur (portail, lancement, STOMP /
-- ROAR / écrasement vérifiés avec la position serveur, combo, tanks et
-- fléchettes, fin de partie et récompenses, recharge, refus pendant un vol,
-- départ / mort / sortie de la ville) puis par le vrai client (écran de choix,
-- HUD, boutons, résultats). Un bot mesure aussi l'équilibrage par stade.
-- Lancer : lune run tests/sim/rampage.luau

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
local Services = S.ServerScriptService:FindFirstChild("Server"):FindFirstChild("Services")
local DataService = req(Services:FindFirstChild("DataService"))
local KaijuService = req(Services:FindFirstChild("KaijuService"))
local PlotService = req(Services:FindFirstChild("PlotService"))
local RampageService = req(Services:FindFirstChild("RampageService"))
local Shared = S.ReplicatedStorage:FindFirstChild("Shared")
local Rampage = req(Shared.Config.Rampage)
local Growth = req(Shared.Config.Growth)
local Layout = req(Shared.Config.Layout)
local Tutorial = req(Shared.Config.Tutorial)
local Worlds = req(Shared.Config.Worlds)
local Calc = req(Shared.Logic.Calc)

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
local function note(t)
	table.insert(lines, "  ℹ️  " .. t)
end

----------------------------------------------------------------------------
-- Aides
----------------------------------------------------------------------------

local function flat(v)
	return V3(v.X, 0, v.Z)
end
local function rootOf(p)
	return p.Character.HumanoidRootPart
end
local function cityOf(p)
	local cities = S.Workspace:FindFirstChild("RampageCities")
	return cities and cities:FindFirstChild(tostring(p.UserId))
end
local function buildingsOf(p)
	local city = cityOf(p)
	return if city then city:FindFirstChild("Buildings"):GetChildren() else {}
end
-- Emprise au sol d'un immeuble (comme le serveur).
local function footprint(model)
	local body = model.PrimaryPart
	local cf = body.CFrame
	local alongX = math.abs(cf.RightVector.X) > 0.5
	local hx = (if alongX then body.Size.X else body.Size.Z) / 2
	local hz = (if alongX then body.Size.Z else body.Size.X) / 2
	return cf.Position, hx, hz
end
local function footDist(model, pos)
	local c, hx, hz = footprint(model)
	local dx = math.max(math.abs(pos.X - c.X) - hx, 0)
	local dz = math.max(math.abs(pos.Z - c.Z) - hz, 0)
	return math.sqrt(dx * dx + dz * dz)
end
local function nearest(p, filter)
	local pos = rootOf(p).Position
	local best, bd = nil, math.huge
	for _, m in buildingsOf(p) do
		if not filter or filter(m) then
			local d = footDist(m, pos)
			if d < bd then
				best, bd = m, d
			end
		end
	end
	return best, bd
end
local function kind(k)
	return function(m)
		return m:GetAttribute("Kind") == k
	end
end
-- Marche à la vitesse réelle (l'anti-téléportation du serveur surveille).
local function walkTo(p, target, stopDist)
	stopDist = stopDist or 0.3
	for _ = 1, 4000 do
		local root = rootOf(p)
		local pos = root.Position
		local delta = V3(target.X - pos.X, 0, target.Z - pos.Z)
		if delta.Magnitude <= stopDist then
			return true
		end
		local speed = math.max(p.Character.Humanoid.WalkSpeed, 1)
		local len = math.min(delta.Magnitude - stopDist * 0.5, speed * 0.1)
		local dir = delta.Unit
		local np = pos + dir * len
		root.CFrame = Runtime.CFrame.lookAt(np, np + dir)
		Runtime.Advance(0.1)
		if not RampageService.IsActive(p) then
			return false
		end
	end
	return false
end
-- Se place juste à côté d'un immeuble (distance `gap` de son emprise).
local function walkNextTo(p, model, gap)
	local c, hx, hz = footprint(model)
	local pos = rootOf(p).Position
	local dir = flat(pos - c)
	dir = if dir.Magnitude > 0.1 then dir.Unit else V3(0, 0, 1)
	-- sort par le côté le plus proche
	local target
	if math.abs(dir.X) > math.abs(dir.Z) then
		target = V3(c.X + (if dir.X > 0 then 1 else -1) * (hx + gap), pos.Y, c.Z)
	else
		target = V3(c.X, pos.Y, c.Z + (if dir.Z > 0 then 1 else -1) * (hz + gap))
	end
	walkTo(p, target, 0.2)
	local r = rootOf(p)
	r.CFrame = Runtime.CFrame.lookAt(r.Position, V3(c.X, r.Position.Y, c.Z))
end
local function hatchedOf(p)
	local out = {}
	for _, rec in DataService.Get(p).Kaijus do
		if not rec.Egg then
			table.insert(out, rec)
		end
	end
	return out
end
local function lastFx(p, name, from)
	local list = Boot.FxFor(p, name, from)
	return list[#list]
end
local function waitFx(p, name, from, maxSeconds)
	local t = 0
	while t < (maxSeconds or 30) do
		local e = lastFx(p, name, from)
		if e then
			return e
		end
		Runtime.Advance(0.1)
		t += 0.1
	end
	return nil
end
local function toastsFor(p, from)
	local out = {}
	for i = from or 1, #Runtime.ClientLog do
		local e = Runtime.ClientLog[i]
		if e.remote == "Notify" and e.player == p then
			table.insert(out, e.args[1])
		end
	end
	return out
end
local function colossus(p, species)
	return KaijuService.AddHatched(p, species, nil, Growth.Threshold(5, "Common") + 10)
end
local function atStage(p, species, stage)
	return KaijuService.AddHatched(p, species, nil, Growth.Threshold(stage, "Common") + 5)
end
local function start(p, uid, district)
	return Boot.Call(p, "RampageStart", { Uid = uid, District = district or 1 })
end

-- Bot « joue normalement » : va vers l'immeuble le plus proche, piétine à la
-- cadence max, rugit dès que c'est prêt. Ne s'occupe pas des fléchettes.
local function bot(p, scale, casual)
	local from = #Runtime.ClientLog + 1
	local radius = Rampage.StompRadius(scale)
	-- « tranquille » : piétine deux fois moins vite et rugit rarement
	local stompEvery = if casual then 0.8 else Rampage.Stomp.Cooldown
	local roarEvery = if casual then 15 else Rampage.Roar.Cooldown
	local lastStomp, lastRoar = -10, -10
	while RampageService.IsActive(p) and not lastFx(p, "RampageEnd", from) do
		local target, d = nearest(p)
		local root = rootOf(p)
		if target then
			local c = footprint(target)
			local dir = flat(c - root.Position)
			if d > radius * 0.7 and dir.Magnitude > 0.1 then
				local speed = p.Character.Humanoid.WalkSpeed
				local np = root.Position + dir.Unit * math.min(speed * 0.1, d)
				root.CFrame = Runtime.CFrame.lookAt(np, np + dir.Unit)
			end
			local now = Runtime.Now()
			if d <= radius and now - lastStomp >= stompEvery - 1e-6 then
				lastStomp = now
				Boot.Input(p, "RampageStomp")
			end
			if d <= Rampage.RoarLength(scale) * 0.8 and now - lastRoar >= roarEvery and dir.Magnitude > 0.1 then
				lastRoar = now
				Boot.Input(p, "RampageRoar", { Dir = dir.Unit })
			end
		end
		Runtime.Advance(0.1)
	end
	return waitFx(p, "RampageEnd", from, 5)
end

----------------------------------------------------------------------------
section("Démarrage")
local alice = Runtime.AddPlayer("Alice")
local bob = Runtime.AddPlayer("Bob")
local carl = Runtime.AddPlayer("Carl")
local hero, clientFolder = ClientRuntime.StartClient(Runtime, "Hero")
Runtime.Advance(14)
check("aucune erreur au démarrage", #Runtime.Errors == 0, #Runtime.Errors)
for _, p in { alice, bob, carl } do
	DataService.Get(p).Tutorial = Tutorial.Done -- difficulté normale
end
check("données Rampage prêtes (5 quartiers, 0 étoile)", #DataService.Get(alice).Rampage.Stars == #Rampage.Districts and DataService.Get(alice).Rampage.Stars[1] == 0)

----------------------------------------------------------------------------
section("Portail RAMPAGE sur chaque île")
local portalsOk = 0
for _, plot in PlotService.All() do
	local pad = plot.Model:FindFirstChild("RampagePortal")
	if pad and pad.Parent == plot.Model and pad:FindFirstChild("RampagePrompt") then
		local rel = plot.CFrame:PointToObjectSpace(pad.Position)
		if math.abs(rel.X - Layout.RampagePortal.X) < 0.01 and math.abs(rel.Z - Layout.RampagePortal.Z) < 0.01 then
			portalsOk += 1
		end
	end
end
check(("portail « RampagePortal » enfant direct de chaque île, à (-40, -46) (%d/%d)"):format(portalsOk, #PlotService.All()), portalsOk == #PlotService.All())
local alicePad = PlotService.Get(alice).Model:FindFirstChild("RampagePortal")
do
	-- le portail ne chevauche ni la cour des nids ni les murs
	local rel = Layout.RampagePortal
	check("portail hors de la cour des nids et dans l'île", rel.Z < -34 - 7 and rel.Z > -Layout.PlotDepth / 2 + 7 and math.abs(rel.X) < Layout.PlotWidth / 2 - 7)
end

section("Ouverture de l'écran depuis le portail")
local from = #Runtime.ClientLog + 1
alicePad.Touched:Fire(rootOf(alice))
Runtime.Advance(0.2)
check("toucher son portail ouvre l'écran (Fx RampageOpen)", #Boot.FxFor(alice, "RampageOpen", from) == 1)
from = #Runtime.ClientLog + 1
alicePad:FindFirstChild("RampagePrompt").Triggered:Fire(bob)
Runtime.Advance(0.2)
check("le portail d'un autre joueur ne s'ouvre pas (message à la place)", #Boot.FxFor(bob, "RampageOpen", from) == 0 and #toastsFor(bob, from) == 1)
Runtime.Advance(3.5)
from = #Runtime.ClientLog + 1
Runtime.MoveTo(alice, alicePad.Position + V3(1, 3, 0))
Runtime.Advance(0.6)
check("marcher sur le portail l'ouvre aussi (proximité serveur)", #Boot.FxFor(alice, "RampageOpen", from) == 1)
Runtime.Advance(1)
check("rester dessus ne le rouvre pas en boucle", #Boot.FxFor(alice, "RampageOpen", from) == 1)
Runtime.MoveTo(alice, PlotService.Get(alice).CFrame * Layout.Spawn)

----------------------------------------------------------------------------
section("Lancement")
local baby = hatchedOf(alice)[1]
check("Alice a un bébé Common", baby and Calc.Stage(baby) == 1 and baby.Rarity == "Common", baby and baby.Species)
baby.Mutation = nil -- puissance 1 exacte pour les vérifications de dégâts (une mutation l'augmente)
local res = start(alice, baby.Uid, 2)
check("quartier 2 verrouillé au départ", res and not res.ok and res.msg and res.msg:find("stars"), res and res.msg)
res = start(alice, "zzz", 1)
check("kaiju inconnu refusé", res and not res.ok)
from = #Runtime.ClientLog + 1
local cashBefore = DataService.Get(alice).Cash
local growthBefore = baby.Growth
res = start(alice, baby.Uid, 1)
check("lancement accepté", res and res.ok, res and res.msg)
check("IsActive + attribut Rampage", RampageService.IsActive(alice) and alice:GetAttribute("Rampage") == true)
local startFx = lastFx(alice, "RampageStart", from)
check("Fx RampageStart (75 s, quartier 1)", startFx and math.abs(startFx.EndsAt - startFx.StartAt - Rampage.Duration) < 0.01 and startFx.District == 1)
local city = cityOf(alice)
check("ville privée construite", city ~= nil)
local buildings = buildingsOf(alice)
local expectedCount = 0
for _, def in Rampage.Buildings do
	expectedCount += def.Count
end
check(("%d immeubles avec HP/MaxHP/Value"):format(expectedCount), #buildings == expectedCount, #buildings)
local attrsOk, golden, hq = true, 0, 0
for _, m in buildings do
	if not (m:GetAttribute("HP") and m:GetAttribute("MaxHP") and m:GetAttribute("Value")) then
		attrsOk = false
	end
	if m:GetAttribute("Golden") then
		golden += 1
	end
	if m:GetAttribute("Kind") == "HQ" then
		hq += 1
	end
end
check("attributs présents sur chaque immeuble", attrsOk)
check("1 immeuble doré, 1 Toy HQ", golden == 1 and hq == 1, golden .. "/" .. hq)
local origin = startFx.Origin
local farOk = origin.Magnitude >= 2000
for _, plot in PlotService.All() do
	if (flat(plot.CFrame.Position) - flat(origin)).Magnitude < 1500 then
		farOk = false
	end
end
for _, a in { 45, 135, 225, 315 } do
	local arena = V3(math.sin(math.rad(a)) * Worlds.ArenaDistance, 0, math.cos(math.rad(a)) * Worlds.ArenaDistance)
	if (flat(arena) - flat(origin)).Magnitude < 1000 then
		farOk = false
	end
end
check("ville loin de tout (> 2000 studs du centre, loin des îles et arènes)", farOk, origin)
local distinct = true
for i = 1, 8 do
	for j = i + 1, 8 do
		if (Rampage.CityOrigin(i) - Rampage.CityOrigin(j)).Magnitude < 2 * (Rampage.Half + 60) then
			distinct = false
		end
	end
end
check("une origine distincte par île (villes qui ne se chevauchent pas)", distinct)
local rel = rootOf(alice).Position - origin
check("personnage téléporté dans la ville", math.abs(rel.X) < Rampage.Half and math.abs(rel.Z) < Rampage.Half + 10, rel)
check("personnage invisible", alice.Character.Head.Transparency == 1)
check("vitesse de marche du kaiju (22)", alice.Character.Humanoid.WalkSpeed == Rampage.WalkSpeed)
check("pas de saut pendant la partie (bouton de saut masqué sur mobile)", alice.Character.Humanoid.JumpPower == 0 and alice.Character.Humanoid.JumpHeight == 0)
check("l'original reste sur son nid (copie)", KaijuService.Anchor(baby.Uid) ~= nil and KaijuService.FindRecord(DataService.Get(alice), baby.Uid) ~= nil)
res = start(alice, baby.Uid, 1)
check("pas deux parties en même temps", res and not res.ok)

----------------------------------------------------------------------------
section("Coups vérifiés par le serveur (position serveur)")
-- au carrefour central : aucun immeuble à portée de piétinement d'un bébé
walkTo(alice, origin + V3(0, 3.5, 0))
local _, dNear = nearest(alice)
check("carrefour central hors de portée", dNear > Rampage.StompRadius(1), dNear)
local hpSnapshot = {}
for _, m in buildingsOf(alice) do
	hpSnapshot[m.Name] = m:GetAttribute("HP")
end
from = #Runtime.ClientLog + 1
local target = nearest(alice, kind("Shack"))
Boot.Input(alice, "RampageStomp", { Position = footprint(target) }) -- le client « ment » sur sa position
Runtime.Advance(0.5)
local unchanged = true
for _, m in buildingsOf(alice) do
	if m:GetAttribute("HP") ~= hpSnapshot[m.Name] then
		unchanged = false
	end
end
check("STOMP à distance : rien n'est cassé (position client ignorée)", unchanged and #Boot.FxFor(alice, "RampageSmash", from) == 0 and #Boot.FxFor(alice, "RampageHit", from) == 0)

-- téléportation suspecte dans la ville : coups ignorés
local house = nearest(alice, kind("House"))
local hc = footprint(house)
Runtime.MoveTo(alice, V3(hc.X, rootOf(alice).Position.Y, hc.Z) + V3(0, 0, 0))
Runtime.Advance(0.15)
from = #Runtime.ClientLog + 1
Boot.Input(alice, "RampageStomp")
Runtime.Advance(0.1)
check("téléportation dans la ville : STOMP ignoré", #Boot.FxFor(alice, "RampageSmash", from) == 0 and #Boot.FxFor(alice, "RampageHit", from) == 0)
Runtime.Advance(1.2)

-- STOMP à côté d'une cabane : détruite
local shack = nearest(alice, kind("Shack"))
walkNextTo(alice, shack, 1)
from = #Runtime.ClientLog + 1
local shackId = shack:GetAttribute("Id")
Boot.Input(alice, "RampageStomp")
Runtime.Advance(0.1)
local smashed = false
for _, e in Boot.FxFor(alice, "RampageSmash", from) do
	if e.Id == shackId and e.By == "Stomp" then
		smashed = true
	end
end
check("STOMP près d'une cabane (10 PV, puissance 1) : détruite", smashed and shack.Parent == nil)
local firstSmash = Boot.FxFor(alice, "RampageSmash", from)[1]
check("Fx Smash complet (position, taille, cash, combo, destruction)", firstSmash and firstSmash.Position and firstSmash.Size and firstSmash.Cash > 0 and firstSmash.Combo >= 1 and firstSmash.Destruction > 0)

-- recharge du STOMP sur une maison (25 PV)
Runtime.Advance(3) -- casse le combo
house = nearest(alice, function(m)
	return m:GetAttribute("Kind") == "House" and m:GetAttribute("HP") == 25
end)
walkNextTo(alice, house, 1)
Runtime.Advance(0.5)
local hp0 = house:GetAttribute("HP")
Boot.Input(alice, "RampageStomp")
Runtime.Advance(0.02)
local hp1 = house:GetAttribute("HP")
Boot.Input(alice, "RampageStomp")
Runtime.Advance(0.02)
local hp2 = house:GetAttribute("HP")
check("STOMP : 10 x Power de dégâts (25 -> 15)", hp0 == 25 and hp1 == 15, hp0 .. " -> " .. tostring(hp1))
check("recharge 0.4 s respectée (2e coup immédiat ignoré)", hp2 == hp1, hp2)
Runtime.Advance(0.4)
from = #Runtime.ClientLog + 1
Boot.Input(alice, "RampageStomp")
Runtime.Advance(0.02)
check("après 0.4 s le coup passe (15 -> 5, Fx RampageHit)", house:GetAttribute("HP") == 5 and #Boot.FxFor(alice, "RampageHit", from) >= 1)

-- ROAR : cône devant soi
Runtime.Advance(3)
local root = rootOf(alice)
local ahead, behind
local aheadDist = math.huge
for _, m in buildingsOf(alice) do
	local v = flat(footprint(m) - root.Position)
	if v.Magnitude > 3 and v.Magnitude < Rampage.RoarLength(1) - 6 and v.Magnitude < aheadDist then
		ahead, aheadDist = m, v.Magnitude
	end
end
local aheadDir = flat(footprint(ahead) - root.Position).Unit
for _, m in buildingsOf(alice) do
	local v = flat(footprint(m) - root.Position)
	if v.Magnitude > 6 and v.Magnitude < Rampage.RoarLength(1) - 4 and v.Unit:Dot(aheadDir) < -0.5 then
		behind = m
	end
end
local behindHp = behind and behind:GetAttribute("HP")
local aheadId = ahead:GetAttribute("Id")
from = #Runtime.ClientLog + 1
Boot.Input(alice, "RampageRoar", { Dir = aheadDir })
Runtime.Advance(0.1)
local roarHit = false
for _, name in { "RampageSmash", "RampageHit" } do
	for _, e in Boot.FxFor(alice, name, from) do
		if e.Id == aheadId then
			roarHit = true
		end
	end
end
check("ROAR : l'immeuble visé dans le cône est touché (30 x Power)", roarHit)
local comboList = Boot.FxFor(alice, "RampageSmash", from)
check("ROAR : rien derrière le kaiju", behind == nil or (behind.Parent ~= nil and behind:GetAttribute("HP") == behindHp))
from = #Runtime.ClientLog + 1
Boot.Input(alice, "RampageRoar", { Dir = aheadDir })
Runtime.Advance(0.1)
do
	local dbg = {}
	for _, e in Boot.FxFor(alice, "RampageSmash", from) do
		table.insert(dbg, "S" .. e.Id .. e.By)
	end
	for _, e in Boot.FxFor(alice, "RampageHit", from) do
		table.insert(dbg, "H" .. e.Id)
	end
	check("ROAR : recharge de 6 s", #dbg == 0, table.concat(dbg, ","))
end
Boot.Input(alice, "RampageRoar", { Dir = V3(0 / 0, 0, 0) })
Runtime.Advance(0.1)
check("direction invalide (NaN) sans erreur", #Runtime.Errors == 0, #Runtime.Errors)

section("Combo")
-- enchaînement : plusieurs cabanes cassées coup sur coup
local chain = {}
local walked = 0
while #chain < 4 and walked < 12 do
	walked += 1
	local s = nearest(alice, function(m)
		return m:GetAttribute("HP") <= 10
	end)
	if not s then
		break
	end
	walkNextTo(alice, s, 1)
	from = #Runtime.ClientLog + 1
	Boot.Input(alice, "RampageStomp")
	Runtime.Advance(0.45)
	for _, e in Boot.FxFor(alice, "RampageSmash", from) do
		table.insert(chain, { e = e, t = Runtime.Now() })
	end
end
local comboOk, sawCombo = true, false
for i = 2, #chain do
	local prev, cur = chain[i - 1], chain[i]
	if cur.t - prev.t <= Rampage.Combo.Window then
		if cur.e.ComboCount ~= prev.e.ComboCount + 1 then
			comboOk = false
		end
		sawCombo = true
	elseif cur.e.ComboCount ~= 0 then
		comboOk = false
	end
	if math.abs(cur.e.Combo - math.min(3, 1 + 0.1 * cur.e.ComboCount)) > 1e-6 then
		comboOk = false
	end
end
for i = 2, #comboList do
	if comboList[i].ComboCount ~= comboList[i - 1].ComboCount + 1 then
		comboOk = false
	end
end
check(("combo +1 par immeuble à moins de 2.5 s, x(1 + 0.1 n) (%d casses suivies)"):format(#chain), comboOk and (sawCombo or #comboList >= 2))
Runtime.Advance(Rampage.Combo.Window + 0.5)
local s = nearest(alice, function(m)
	return m:GetAttribute("HP") <= 10
end)
if s then
	walkNextTo(alice, s, 1)
	Runtime.Advance(Rampage.Combo.Window + 0.2)
	from = #Runtime.ClientLog + 1
	Boot.Input(alice, "RampageStomp")
	Runtime.Advance(0.1)
	local e = Boot.FxFor(alice, "RampageSmash", from)[1]
	check("le combo retombe à x1.0 après 2.5 s sans casse", e and e.ComboCount == 0 and e.Combo == 1, e and e.ComboCount)
end

----------------------------------------------------------------------------
section("Tanks-jouets et fléchettes")
local tankFx
while not tankFx and RampageService.IsActive(alice) do
	Runtime.Advance(0.5)
	tankFx = lastFx(alice, "RampageTank", 1)
end
local elapsedAtTank = tankFx and tankFx.T0 - startFx.StartAt or 0
check("un tank arrive après 25 s", tankFx ~= nil and tankFx.HP == Rampage.Tanks.HP and elapsedAtTank >= Rampage.Tanks.StartAt, elapsedAtTank)
-- rester immobile : la fléchette touche et retire 1 s
from = #Runtime.ClientLog + 1
local dart = waitFx(alice, "RampageDart", from, 12)
check("le tank tire une fléchette visible (départ, arrivée, durée)", dart and dart.From and dart.To and dart.T1 - dart.T0 >= Rampage.Tanks.DartMinTime - 1e-6)
local hitFx = waitFx(alice, "RampageDartHit", from, 5)
-- fin prévue juste avant cet impact (d'autres fléchettes ont pu toucher avant)
local endsBefore = startFx.EndsAt
for i = 1, #Runtime.ClientLog do
	local e = Runtime.ClientLog[i]
	if e.remote == "Fx" and e.player == alice and e.args[2] == hitFx then
		break
	end
	if e.remote == "Fx" and e.player == alice and (e.args[1] == "RampageDartHit" or e.args[1] == "RampageTankDown") then
		endsBefore = e.args[2].EndsAt
	end
end
check("fléchette reçue : -1 s au chrono", hitFx and math.abs(hitFx.EndsAt - (endsBefore - 1)) < 1e-6, hitFx and (hitFx.EndsAt - endsBefore))
-- esquive : s'écarter avant l'impact
from = #Runtime.ClientLog + 1
dart = waitFx(alice, "RampageDart", from, 6)
if dart then
	local away = flat(rootOf(alice).Position - dart.From)
	away = if away.Magnitude > 0.1 then away.Unit else V3(1, 0, 0)
	local side = V3(-away.Z, 0, away.X)
	walkTo(alice, rootOf(alice).Position + side * (Rampage.DartRadius(1) + 6), 0.5)
	Runtime.Advance(math.max(0, dart.T1 - (1790000000 + Runtime.Now())) + 0.3)
	local dodged = true
	for _, e in Boot.FxFor(alice, "RampageDartHit", from) do
		if e.Id == dart.Id then
			dodged = false
		end
	end
	check("fléchette esquivée : pas de pénalité", dodged)
end
-- détruire le tank : +3 s
local tankNow = function()
	local now = 1790000000 + Runtime.Now()
	local len = (tankFx.To - tankFx.From).Magnitude
	local a = if len < 0.01 then 1 else math.clamp((now - tankFx.T0) * tankFx.Speed / len, 0, 1)
	return tankFx.From:Lerp(tankFx.To, a)
end
from = #Runtime.ClientLog + 1
local endsNow = (lastFx(alice, "RampageDartHit", 1) or startFx).EndsAt
local down
for _ = 1, 60 do
	local tp = tankNow()
	walkTo(alice, V3(tp.X, rootOf(alice).Position.Y, tp.Z), Rampage.StompRadius(1))
	Boot.Input(alice, "RampageStomp")
	Runtime.Advance(0.45)
	down = lastFx(alice, "RampageTankDown", from)
	if down then
		break
	end
end
local hitsDuring = 0
for _, e in Boot.FxFor(alice, "RampageDartHit", from) do
	hitsDuring += e.Penalty
end
check("tank détruit au STOMP : +3 s au chrono", down and math.abs(down.EndsAt - (endsNow - hitsDuring + Rampage.Tanks.KillBonus)) < 1e-6, down and down.EndsAt - endsNow)
note(("tank arrivé à t=%.0fs après le lancement"):format(elapsedAtTank))

----------------------------------------------------------------------------
section("Fin de partie à 75 s")
from = #Runtime.ClientLog + 1
local endFx = waitFx(alice, "RampageEnd", 1, 120)
local data = DataService.Get(alice)
check("fin au chrono (Reason = Time)", endFx and endFx.Reason == "Time", endFx and endFx.Reason)
check("cash versé (> 0, égal au récapitulatif)", endFx and endFx.Cash > 0 and math.abs(data.Cash - cashBefore - endFx.Cash) < 1, endFx and (data.Cash - cashBefore) .. " vs " .. endFx.Cash)
local rec = KaijuService.FindRecord(data, baby.Uid)
-- plafond calculé sur la croissance juste avant l'ajout (le bébé a grandi pendant la partie)
local maxGrowth = Growth.Remaining(rec.Growth - (endFx and endFx.Growth or 0), baby.Rarity) * Rampage.GrowthCap
check("le kaiju a gagné plus que sa croissance passive", rec.Growth - growthBefore > Rampage.Duration)
check("croissance ajoutée au kaiju utilisé (plafond 25 % du stade)", endFx and endFx.Growth > 0 and endFx.Growth <= maxGrowth + 1, endFx and endFx.Growth .. " / " .. maxGrowth)
check("ancre du kaiju resynchronisée", KaijuService.Anchor(baby.Uid):GetAttribute("Growth") == rec.Growth)
check("étoiles enregistrées", data.Rampage.Stars[1] == endFx.Stars and data.Rampage.Runs == 1, data.Rampage.Stars[1])
check("stats Rampages / Smashed", data.Stats.Rampages == 1 and data.Stats.Smashed == endFx.Smashed and endFx.Smashed > 0, data.Stats.Smashed)
check("XP = étoiles x RampageStar", endFx.Xp == endFx.Stars * 30)
check("pendant la bannière de fin, toujours actif (défense en pause)", RampageService.IsActive(alice))
Runtime.Advance(Rampage.EndDelay + 0.3)
check("retour sur l'île", Layout.InPlot(PlotService.Get(alice).CFrame, rootOf(alice).Position, 2))
check("ville détruite", cityOf(alice) == nil)
check("personnage visible, vitesse et saut normaux", alice.Character.Head.Transparency == 0 and alice.Character.Humanoid.WalkSpeed == 22 and alice.Character.Humanoid.JumpPower > 0)
check("fin propre (inactif, attribut remis, Fx RampageHome)", not RampageService.IsActive(alice) and alice:GetAttribute("Rampage") == false and #Boot.FxFor(alice, "RampageHome", from) == 1)
note(("bébé Common, quartier 1 : %d%% détruit, %d étoile(s), %s de croissance"):format(math.floor(endFx.Destruction * 100), endFx.Stars, tostring(endFx.Growth)))

section("Recharge")
res = start(alice, baby.Uid, 1)
check("relance immédiate refusée (ville en reconstruction)", res and not res.ok and res.msg and res.msg:find("rebuilt"), res and res.msg)
check("attribut RampageReadyAt ~ +20 s", math.abs((alice:GetAttribute("RampageReadyAt") or 0) - endFx.ReadyAt) < 1e-6 and endFx.ReadyAt > 0)
Runtime.Advance(Rampage.Cooldown)

----------------------------------------------------------------------------
section("Colosse : écrasement passif, ville rasée, quartier 2")
local big = colossus(alice, "DinoNugget")
check("Colosse Common ajouté (puissance ~6.3)", big and math.abs(Calc.Power(big) - math.sqrt(40)) < 0.01)
local gemsBefore = data.Gems
local starsBefore = data.Rampage.Stars[1]
from = #Runtime.ClientLog + 1
res = start(alice, big.Uid, 1)
check("relance après 20 s", res and res.ok, res and res.msg)
walkTo(alice, origin + V3(0, 3.5, 0))
local weak = nearest(alice, kind("Shack"))
local weakId = weak:GetAttribute("Id")
local strong = nearest(alice, kind("House"))
local strongHp = strong:GetAttribute("HP")
from = #Runtime.ClientLog + 1
walkTo(alice, footprint(weak), 0.3)
local crushed = false
for _, e in Boot.FxFor(alice, "RampageSmash", from) do
	if e.Id == weakId and e.By == "Crush" then
		crushed = true
	end
end
check("marcher dans une cabane (10 PV <= 3 x 6.3) l'écrase", crushed)
if strong.Parent then
	walkTo(alice, footprint(strong), 0.3)
	check("une maison (25 PV > 19) résiste à l'écrasement", strong.Parent ~= nil and strong:GetAttribute("HP") == strongHp)
end
local endB = bot(alice, Growth.Get(5).Scale)
check("ville rasée : fin anticipée (Flattened)", endB and endB.Reason == "Flattened", endB and endB.Reason)
check("3 étoiles", endB and endB.Stars == 3 and data.Rampage.Stars[1] == 3)
check("gemmes pour chaque NOUVELLE étoile", endB and endB.NewStars == 3 - starsBefore and endB.Gems == endB.NewStars * Rampage.StarGems and data.Gems >= gemsBefore + endB.Gems)
check("quartier 2 débloqué", endB and endB.Unlocked == 2 and Rampage.Unlocked(data.Rampage.Stars, 2))
local income = KaijuService.IncomePerSecond(alice)
note(("colosse : quartier 1 rasé en %.0fs, cash = %.1f min de revenu passif"):format(Rampage.Duration - 0, endB.Cash / income / 60))
Runtime.Advance(Rampage.EndDelay + 0.5 + Rampage.Cooldown)
res = start(alice, big.Uid, 2)
check("quartier 2 jouable", res and res.ok, res and res.msg)
local startB2 = lastFx(alice, "RampageStart", from)
local hq2
for _, m in buildingsOf(alice) do
	if m:GetAttribute("Kind") == "HQ" then
		hq2 = m
	end
end
check("quartier 2 : PV x2.5", hq2 and hq2:GetAttribute("MaxHP") == 1000, hq2 and hq2:GetAttribute("MaxHP"))
from = #Runtime.ClientLog + 1
res = Boot.Call(alice, "RampageLeave")
Runtime.Advance(0.2)
local quit = lastFx(alice, "RampageEnd", from)
check("EXIT : fin propre (Quit), retour immédiat", res.ok and quit and quit.Reason == "Quit" and not RampageService.IsActive(alice) and cityOf(alice) == nil)
check("pas d'étoile à 0 %", quit and quit.Stars == 0 and data.Rampage.Stars[2] == 0)
Runtime.Advance(Rampage.Cooldown + 1)

----------------------------------------------------------------------------
section("Sécurité")
-- porter un kaiju volé interdit de lancer
local bobKaiju = hatchedOf(bob)[1]
PlotService.Get(bob).Model:SetAttribute("ProtectedUntil", 0)
Runtime.MoveTo(alice, KaijuService.Anchor(bobKaiju.Uid).Position + V3(2, 0, 0))
local stealRes = Boot.Call(alice, "Steal", { Uid = bobKaiju.Uid })
check("Alice porte le kaiju de Bob", stealRes and stealRes.ok, stealRes and stealRes.msg)
res = start(alice, baby.Uid, 1)
check("lancement refusé pendant un vol", res and not res.ok and res.msg and res.msg:find("stolen"), res and res.msg)
from = #Runtime.ClientLog + 1
alicePad.Touched:Fire(rootOf(alice))
Runtime.Advance(0.1)
check("le portail ne s'ouvre pas pendant un vol", #Boot.FxFor(alice, "RampageOpen", from) == 0)
Boot.Call(alice, "Drop")
Runtime.Advance(1)

-- mort pendant la partie
res = start(alice, baby.Uid, 1)
check("relance après le vol lâché", res and res.ok, res and res.msg)
from = #Runtime.ClientLog + 1
alice.Character.Humanoid.Health = 0
alice.Character.Humanoid.Died:Fire()
Runtime.Advance(0.3)
local died = lastFx(alice, "RampageEnd", from)
check("mort : fin propre (Died), ville détruite", died and died.Reason == "Died" and cityOf(alice) == nil and not RampageService.IsActive(alice))
alice.Character.Humanoid.Health = 100
Runtime.Advance(Rampage.Cooldown + 1)

-- sortie de la ville (téléportation hors limites)
res = start(alice, baby.Uid, 1)
from = #Runtime.ClientLog + 1
Runtime.MoveTo(alice, V3(0, 5, 0))
Runtime.Advance(0.3)
local left = lastFx(alice, "RampageEnd", from)
check("sortie de la ville : fin (Left) et retour sur l'île", left and left.Reason == "Left" and Layout.InPlot(PlotService.Get(alice).CFrame, rootOf(alice).Position, 2))

-- départ du joueur en pleine partie
res = start(bob, bobKaiju.Uid, 1)
check("Bob lance une partie", res and res.ok, res and res.msg)
local bobCity = cityOf(bob)
local errorsBefore = #Runtime.Errors
Runtime.RemovePlayer(bob)
Runtime.Advance(2)
check("Bob quitte le jeu : ville détruite, partie terminée", bobCity.Parent == nil and not RampageService.IsActive(bob) and #Runtime.Errors == errorsBefore)

----------------------------------------------------------------------------
section("Équilibrage (bot, quartier 1)")
local EventService = req(Services:FindFirstChild("EventService"))
-- Carl : un seul kaiju par mesure (le revenu passif sert d'étalon)
local carlData = DataService.Get(carl)
local function onlyKaiju(p, species, stage)
	local d = DataService.Get(p)
	for _, r in table.clone(d.Kaijus) do
		KaijuService.RemoveRecord(p, r.Uid)
	end
	return atStage(p, species, stage)
end
local function measure(p, species, stage, label, casual)
	Runtime.Advance(Rampage.Cooldown + 1)
	EventService.Stop() -- pas d'événement (mutation, bonus de cash) pendant la mesure
	local rec = onlyKaiju(p, species, stage)
	Runtime.Advance(1.2)
	local power = Calc.Power(rec)
	local income = KaijuService.IncomePerSecond(p)
	local r = start(p, rec.Uid, 1)
	if not (r and r.ok) then
		return nil
	end
	local e = bot(p, Growth.Get(stage).Scale, casual)
	note(("%-30s puissance %4.1f : %3d%% détruit, %d★, cash %.1f min de revenu, +%ds de croissance"):format(label, power, math.floor(e.Destruction * 100), e.Stars, e.Cash / math.max(income, 1e-6) / 60, e.Growth))
	Runtime.Advance(Rampage.EndDelay + 0.5)
	e.Minutes = e.Cash / math.max(income, 1e-6) / 60
	return e
end
local babyEnd = measure(carl, "Toastzilla", 1, "bébé Common")
local teenEnd = measure(carl, "Toastzilla", 2, "ado Common")
local adultEnd = measure(carl, "Toastzilla", 3, "adulte Common")
local casualBaby = measure(carl, "Toastzilla", 1, "bébé Common (joueur tranquille)", true)
local casualAdult = measure(carl, "Toastzilla", 3, "adulte Common (joueur tranquille)", true)
check("bébé Common : 1 à 2 étoiles", babyEnd and babyEnd.Stars >= 1 and babyEnd.Stars <= 2, babyEnd and babyEnd.Stars)
check("joueur tranquille avec un bébé : au plus 1 étoile (grandir compte)", casualBaby and casualBaby.Stars <= 1, casualBaby and casualBaby.Stars)
check("ado Common : plus de destruction que le bébé", teenEnd and teenEnd.Destruction >= babyEnd.Destruction, teenEnd and teenEnd.Stars)
check("adulte Common : 3 étoiles (2 en jouant tranquille)", adultEnd and adultEnd.Stars == 3 and casualAdult and casualAdult.Stars >= 2, adultEnd and adultEnd.Stars)
check("ville rasée par un adulte ≈ 4-6 min de revenu passif", adultEnd and adultEnd.Minutes >= 3.5 and adultEnd.Minutes <= 7, adultEnd and adultEnd.Minutes)
-- tutoriel : 1re partie gagnable facilement avec un bébé, même en jouant tranquille
carlData.Tutorial = 3
carlData.Rampage.Stars[1] = 0
local tutoEnd = measure(carl, "Toastzilla", 1, "bébé Common (tutoriel, tranquille)", true)
check("tutoriel : au moins 1 étoile quasi garantie avec un bébé Common", tutoEnd and tutoEnd.Stars >= 1 and tutoEnd.Destruction > Rampage.Stars[1] + 0.1, tutoEnd and tutoEnd.Destruction)
carlData.Tutorial = Tutorial.Done
check("aucune erreur Lua côté serveur", #Runtime.Errors == 0, #Runtime.Errors)

----------------------------------------------------------------------------
section("Client : écran, HUD, boutons, résultats")
local playerGui = hero:FindFirstChild("PlayerGui")
local UIRegistry = req(clientFolder:FindFirstChild("Controllers"):FindFirstChild("UIRegistry"))
local RampageController = req(clientFolder:FindFirstChild("World"):FindFirstChild("RampageController"))
local heroData = DataService.Get(hero)
atStage(hero, "Gloop", 2)
Runtime.Advance(1)
local n0 = #Runtime.Errors
local heroPad = PlotService.Get(hero).Model:FindFirstChild("RampagePortal")
heroPad.Touched:Fire(rootOf(hero))
Runtime.Advance(1)
local selection = playerGui:FindFirstChild("Window_Rampage")
check("toucher le portail ouvre l'écran RAMPAGE chez le client", selection and selection.Enabled == true)
local grid = selection:FindFirstChild("Grid", true)
local cardCount = 0
for _, c in grid:GetChildren() do
	if c.ClassName == "TextButton" then
		cardCount += 1
	end
end
check(("une carte par kaiju éclos (%d)"):format(cardCount), cardCount == #hatchedOf(hero))
-- clique : 2e carte, quartier 2 verrouillé, quartier 1, GO
local cardsList = {}
for _, c in grid:GetChildren() do
	if c.ClassName == "TextButton" then
		table.insert(cardsList, c)
	end
end
table.sort(cardsList, function(a, b)
	return a.LayoutOrder < b.LayoutOrder
end)
cardsList[#cardsList].Activated:Fire()
Runtime.Advance(0.2)
selection:FindFirstChild("District2", true).Activated:Fire()
Runtime.Advance(0.2)
selection:FindFirstChild("District1", true).Activated:Fire()
Runtime.Advance(0.2)
local chosenUid = cardsList[#cardsList].Name:sub(6)
selection:FindFirstChild("Go", true).Activated:Fire()
Runtime.Advance(1)
check("GO lance la partie avec la carte choisie", hero:GetAttribute("Rampage") == true and lastFx(hero, "RampageStart", 1).Uid == chosenUid)
check("écran de choix fermé", selection.Enabled == false)
local hud = playerGui:FindFirstChild("RampageHud")
check("HUD de partie affiché, HUD principal masqué", hud and hud.Enabled and playerGui:FindFirstChild("KaijuUI").Enabled == false)
local clientFx = S.Workspace:FindFirstChild("ClientRampage")
local kaijuModel = clientFx and clientFx:FindFirstChild("RampageKaiju")
check("modèle géant du kaiju construit et collé au personnage", kaijuModel and (flat(kaijuModel.PrimaryPart.Position) - flat(rootOf(hero).Position)).Magnitude < 0.5)
check("caméra reculée selon la taille", hero.CameraMinZoomDistance and hero.CameraMinZoomDistance > 16)
local heroOrigin = lastFx(hero, "RampageStart", 1).Origin
walkTo(hero, heroOrigin + V3(0, 3.5, 0))
local heroShack = nearest(hero, kind("Shack"))
walkNextTo(hero, heroShack, 1)
from = #Runtime.ClientLog + 1
hud:FindFirstChild("Stomp", true).Activated:Fire()
Runtime.Advance(0.5)
check("bouton STOMP : la cabane est écrasée", #Boot.FxFor(hero, "RampageSmash", from) >= 1)
check(
	"HUD : cash, compteur et barre de destruction mis à jour",
	hud:FindFirstChild("Cash", true).Text ~= "$0" and hud:FindFirstChild("Percent", true).Text ~= "DESTRUCTION 0%" and hud:FindFirstChild("Smashed", true).Text:find(" 0/") == nil,
	hud:FindFirstChild("Percent", true).Text .. " | " .. hud:FindFirstChild("Smashed", true).Text
)
hud:FindFirstChild("Roar", true).Activated:Fire()
Runtime.Advance(0.5)
local roarLabel = hud:FindFirstChild("Roar", true):FindFirstChild("Seconds")
check("bouton ROAR : anneau de recharge affiché", roarLabel and roarLabel.Text ~= "", roarLabel and roarLabel.Text)
local debrisCount = 0
for _, c in clientFx:GetChildren() do
	if c.ClassName == "Part" and not c.Anchored then
		debrisCount += 1
	end
end
check("débris physiques côté client", debrisCount > 0, debrisCount)
Runtime.Advance(32)
local tanks, darts = 0, 0
for _, c in clientFx:GetChildren() do
	if c.Name:sub(1, 7) == "ToyTank" then
		tanks += 1
	elseif c.Name == "Dart" then
		darts += 1
	end
end
check("tanks-jouets affichés côté client", tanks >= 1, tanks)
local sawDart = darts > 0
for _ = 1, 40 do
	if sawDart then
		break
	end
	Runtime.Advance(0.1)
	for _, c in clientFx:GetChildren() do
		if c.Name == "Dart" then
			sawDart = true
		end
	end
end
check("fléchettes visibles en vol", sawDart)
from = #Runtime.ClientLog + 1
waitFx(hero, "RampageEnd", 1, 90)
Runtime.Advance(Rampage.EndDelay + 2)
local resultsWin = playerGui:FindFirstChild("Window_RampageResults")
check("écran de résultats ouvert après le retour", resultsWin and resultsWin.Enabled == true)
check("résultats : cash qui défile", resultsWin:FindFirstChild("Cash", true).Text:sub(1, 2) == "+$")
check("résultats : ligne de croissance", resultsWin:FindFirstChild("Growth", true).Text:find("growth") ~= nil, resultsWin:FindFirstChild("Growth", true).Text)
check("HUD de partie retiré, HUD principal rétabli, objets nettoyés", not hud.Enabled and playerGui:FindFirstChild("KaijuUI").Enabled and #clientFx:GetChildren() == 0)
local again = resultsWin:FindFirstChild("PlayAgain", true)
check("PLAY AGAIN grisé pendant la recharge", again:GetAttribute("Disabled") == true)
Runtime.Advance(Rampage.Cooldown)
check("PLAY AGAIN actif après 20 s", again:GetAttribute("Disabled") == false)
again.Activated:Fire()
Runtime.Advance(1)
check("PLAY AGAIN relance une partie", hero:GetAttribute("Rampage") == true and hud.Enabled)
hud:FindFirstChild("Leave", true).Activated:Fire()
Runtime.Advance(1.5)
check("EXIT termine la partie et affiche les résultats", hero:GetAttribute("Rampage") == false and resultsWin.Enabled)
resultsWin:FindFirstChild("Change", true).Activated:Fire()
Runtime.Advance(1)
check("CHANGE KAIJU rouvre l'écran de choix", selection.Enabled == true and resultsWin.Enabled == false)
UIRegistry.Screens.Rampage.Close()
Runtime.Advance(1)
RampageController.Open()
Runtime.Advance(1)
check("RampageController.Open() (bouton HUD) ouvre l'écran", selection.Enabled == true)
UIRegistry.Screens.Rampage.Close()
Runtime.Advance(1)
check("aucune erreur Lua côté client", #Runtime.Errors == n0, #Runtime.Errors - n0)

print(table.concat(lines, "\n"))
print(("\nRÉSULTAT RAMPAGE : %d réussies, %d échouées, %d erreurs Lua"):format(passed, failed, #Runtime.Errors))
local seen = {}
for _, e in Runtime.Errors do
	local key = e:match("^[^\n]+")
	if not seen[key] then
		seen[key] = true
		print("---- " .. e:sub(1, 900))
	end
end
