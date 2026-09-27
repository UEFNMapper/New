--!nocheck
-- PLAYTEST CLIENT : le vrai client (HUD, fenêtres, rendu 3D, cinématiques,
-- tutoriel) tourne contre le vrai serveur. On ouvre chaque écran, on clique
-- sur chaque bouton, on déclenche chaque effet et on compte les erreurs.
-- Lancer : lune run tests/sim/client_playtest.luau

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
local KaijuService = req(Services:FindFirstChild("KaijuService"))
local DataService = req(Services:FindFirstChild("DataService"))
local EventService = req(Services:FindFirstChild("EventService"))
local PlotService = req(Services:FindFirstChild("PlotService"))
local Growth = req(S.ReplicatedStorage:FindFirstChild("Shared").Config.Growth)

local passed, failed = 0, 0
local lines = {}
local function check(name, cond, detail)
	if cond then
		passed += 1
		table.insert(lines, "  ✅ " .. name)
	else
		failed += 1
		table.insert(lines, "  ❌ " .. name .. (if detail then " — " .. tostring(detail) else ""))
	end
end
local function section(t)
	table.insert(lines, "\n## " .. t)
end
local function errorsSince(n)
	return #Runtime.Errors - n
end

----------------------------------------------------------------------------
section("Démarrage du client")
local rival = Runtime.AddPlayer("Rival")
local hero, clientFolder = ClientRuntime.StartClient(Runtime, "Hero")
Runtime.Advance(12)
check("le client a démarré (ClientReady)", hero:GetAttribute("ClientReady") == true)
local playerGui = hero:FindFirstChild("PlayerGui")
check("interface principale créée", playerGui:FindFirstChild("KaijuUI") ~= nil)
check("écran de chargement retiré", playerGui:FindFirstChild("Loading") == nil)
check("aucune erreur au démarrage", #Runtime.Errors == 0, #Runtime.Errors)

local UIRegistry = req(clientFolder:FindFirstChild("Controllers"):FindFirstChild("UIRegistry"))
local State = req(clientFolder:FindFirstChild("Controllers"):FindFirstChild("State"))
check("état client reçu", State.Get("Cash") ~= nil)
local count = 0
for _ in UIRegistry.Screens do
	count += 1
end
check("12 écrans enregistrés", count == 12, count)

----------------------------------------------------------------------------
section("Éclosion (cinématique) et rendu 3D")
local before = #Runtime.Errors
Runtime.Advance(15)
check("cinématique d'éclosion sans erreur", errorsSince(before) == 0, errorsSince(before))
local clientKaijus = S.Workspace:FindFirstChild("ClientKaijus")
local models = 0
for _, c in clientKaijus:GetChildren() do
	if c.ClassName == "Model" then
		models += 1
	end
end
check("modèles 3D des kaijus construits côté client", models >= 2, models)

----------------------------------------------------------------------------
section("Chaque écran : ouvrir, cliquer partout, fermer")
local function allButtons(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if d.ClassName == "TextButton" or d.ClassName == "ImageButton" then
			table.insert(out, d)
		end
	end
	return out
end
local data = DataService.Get(hero)
data.Cash = 10 ^ 9
data.Gems = 5000
DataService.Replicate(hero, "Cash", "Gems")
-- quelques kaijus adultes pour la fusion / l'évolution
for _, sp in { "Toastzilla", "Sharkapillar", "Rexplosion" } do
	KaijuService.AddHatched(hero, sp, nil, Growth.Threshold(3, "Legendary") + 1)
end
Runtime.Advance(2)

for name, screen in UIRegistry.Screens do
	local n = #Runtime.Errors
	local ok, err = pcall(function()
		if name == "KaijuPanel" then
			local rec = DataService.Get(hero).Kaijus[1]
			screen.Open({ Uid = rec.Uid })
		else
			screen.Open()
		end
	end)
	Runtime.Advance(1)
	-- clique sur tous les boutons visibles de toutes les couches
	local clicked = 0
	for _, gui in playerGui:GetChildren() do
		for _, button in allButtons(gui) do
			local text = button.Name
			if text ~= "Backdrop" and text ~= "Close" then
				button.MouseEnter:Fire()
				button.MouseButton1Down:Fire()
				button.MouseButton1Up:Fire()
				button.Activated:Fire()
				button.MouseLeave:Fire()
				clicked += 1
			end
		end
		Runtime.Advance(0.05)
	end
	Runtime.Advance(6)
	pcall(function()
		screen.Close()
	end)
	Runtime.Advance(0.5)
	check(("écran %s (%d boutons cliqués)"):format(name, clicked), ok and #Runtime.Errors == n, if ok then (#Runtime.Errors - n) .. " erreur(s)" else err)
end

----------------------------------------------------------------------------
section("Boucles de jeu vues par le client")
local n = #Runtime.Errors
-- Achat de météore
for _ = 1, 40 do
	Runtime.Advance(1)
	local found
	for _, m in S.Workspace:FindFirstChild("Meteors"):GetChildren() do
		if (m:GetAttribute("Owner") or 0) == 0 and m:GetAttribute("LandAt") < Runtime.Now() + 1790000000 then
			found = m
		end
	end
	if found then
		Runtime.MoveTo(hero, found.Position)
		Boot.Call(hero, "BuyMeteor", { Id = found:GetAttribute("Id") })
		break
	end
end
Runtime.Advance(3)
check("achat de météore (vol de l'œuf, effets)", #Runtime.Errors == n, #Runtime.Errors - n)

-- Collecte
n = #Runtime.Errors
PlotService.Get(hero).Collector.Touched:Fire(hero.Character.HumanoidRootPart)
Runtime.Advance(2)
check("collecte (pièces volantes)", #Runtime.Errors == n)

-- Vol vécu par le client : se faire voler puis voler
n = #Runtime.Errors
Runtime.Advance(160)
local mine
for _, rec in DataService.Get(hero).Kaijus do
	if not rec.Egg then
		mine = rec
	end
end
if mine then
	local a = KaijuService.Anchor(mine.Uid)
	Runtime.MoveTo(rival, a.Position + V3(2, 0, 0))
	Boot.Call(rival, "Steal", { Uid = mine.Uid })
	Runtime.Advance(2)
	Boot.WalkTo({ { rival } }, PlotService.Get(rival).CFrame.Position)
	Runtime.Advance(4)
end
check("alarme + cinématique « robbed »", #Runtime.Errors == n, #Runtime.Errors - n)
n = #Runtime.Errors
local theirs
for _, rec in DataService.Get(rival).Kaijus do
	if not rec.Egg then
		theirs = rec
	end
end
if theirs then
	Runtime.MoveTo(hero, KaijuService.Anchor(theirs.Uid).Position + V3(2, 0, 0))
	Boot.Call(hero, "Steal", { Uid = theirs.Uid })
	Runtime.Advance(2)
	Boot.WalkTo({ { hero } }, PlotService.Get(hero).CFrame.Position)
	Runtime.Advance(5)
end
check("vol + cinématique de casse", #Runtime.Errors == n, #Runtime.Errors - n)

-- Bonk subi
n = #Runtime.Errors
local heroPos = hero.Character.HumanoidRootPart.Position
rival.Character.HumanoidRootPart.CFrame = Runtime.CFrame.lookAt(heroPos + V3(0, 0, 4), heroPos)
Boot.Input(rival, "Bonk")
Runtime.Advance(3)
check("bonk subi (étoiles, recul)", #Runtime.Errors == n, #Runtime.Errors - n)

-- Verrouillage
n = #Runtime.Errors
Boot.Call(hero, "Lock")
Runtime.Advance(3)
check("bouclier (dôme, minuteur)", #Runtime.Errors == n, #Runtime.Errors - n)

-- Évolution
n = #Runtime.Errors
KaijuService.AddHatched(hero, "Rexplosion", nil, Growth.Threshold(3, "Legendary") + 1)
DataService.Get(hero).Cash = 10 ^ 9
Runtime.Advance(1.2)
Boot.Call(hero, "Rebirth")
Runtime.Advance(6)
check("cinématique d'évolution", #Runtime.Errors == n, #Runtime.Errors - n)

----------------------------------------------------------------------------
section("Événements mondiaux (ambiance, météo, boss)")
for _, id in { "MeteorShower", "BloodMoon", "Radioactive", "GoldenHour", "Aurora", "Stampede", "BossRaid" } do
	n = #Runtime.Errors
	EventService.Stop()
	Runtime.Advance(1)
	EventService.Force(id)
	Runtime.Advance(20)
	if id == "BossRaid" then
		Runtime.MoveTo(hero, V3(8, 3, 0))
		for _ = 1, 30 do
			Boot.Input(hero, "Bonk")
			Runtime.Advance(0.5)
		end
	end
	check("événement " .. id, #Runtime.Errors == n, #Runtime.Errors - n)
end
EventService.Stop()
Runtime.Advance(5)

----------------------------------------------------------------------------
section("Session longue côté client (30 min)")
n = #Runtime.Errors
Runtime.Advance(1800)
check("30 min sans erreur client ni serveur", #Runtime.Errors == n, #Runtime.Errors - n)

print(table.concat(lines, "\n"))
print(("\nRÉSULTAT CLIENT : %d réussies, %d échouées, %d erreurs Lua au total"):format(passed, failed, #Runtime.Errors))
local seen = {}
local shown = 0
for _, e in Runtime.Errors do
	local key = e:match("^[^\n]+")
	if not seen[key] and shown < 25 then
		seen[key] = true
		shown += 1
		print("---- " .. e:sub(1, 700))
	end
end
