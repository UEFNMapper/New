-- L'app AngAInOne partout : pages de l'app par monde, fenêtres de l'app sur les parois, journal
-- des plantages, intros des terminaux, Anga géant du lobby.
-- - logique PURE : Util/AppPanelLogic (valeurs des fenêtres), Util/CrashLogic (cartes « Plantages ») ;
-- - géométrie : construit une tour ISOLÉE (chargeur de modules à part, pour ne pas partager le cache
--   de Shim avec tower.spec) et vérifie emplacement, dégagement et visibilité des fenêtres, et l'Anga
--   géant (décor pur, face à la tour, hors du bureau, n'occulte pas l'écran du live).
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")

local Tower = Shim.load("src/shared/Config/Tower.luau")
local AppPages = Shim.load("src/shared/Util/AppPanelLogic.luau")
local CrashLogic = Shim.load("src/shared/Util/CrashLogic.luau")

local Instance, Enum, V3 = roblox.Instance, roblox.Enum, roblox.Vector3

------------------------------------------------------------------------------------
-- Tour isolée
------------------------------------------------------------------------------------

-- CFrame.lookAt de Lune pointe à l'opposé de Roblox (LookVector inversé) : on le corrige.
local function lookAt(at: any, target: any, up: any?): any
	local look = (target - at).Unit
	local right = look:Cross(up or V3.new(0, 1, 0)).Unit
	local trueUp = right:Cross(look)
	return roblox.CFrame.fromMatrix(at, right, trueUp, -look)
end
local CFrame = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })

local dataModel = Instance.new("DataModel")
local workspace = dataModel:GetService("Workspace")
local clientModels = Instance.new("Folder") -- ReplicatedStorage.ClientModels (ModelLibrary.Preload)
clientModels.Name = "ClientModels"
local globals = {
	game = {
		GetService = function(_self: any, name: string): any
			if name == "Workspace" then
				return workspace
			elseif name == "ReplicatedStorage" then
				return {
					WaitForChild = function(_: any, _name: string)
						return Shim.Node("src/shared")
					end,
					FindFirstChild = function(_: any, name_: string): any
						return if name_ == "ClientModels" then clientModels else nil
					end,
				}
			elseif name == "CollectionService" then
				return {
					AddTag = function(_: any, instance: any, tag: string)
						instance:AddTag(tag)
					end,
				}
			elseif name == "InsertService" then
				return Shim.OfflineInsertService() -- modèles 3D introuvables → décor de secours
			end
			error(`service non simulé : {name}`)
		end,
	},
	Instance = Instance,
	Enum = Enum,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	Vector3 = V3,
	UDim2 = roblox.UDim2,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	task = require("@lune/task"),
	warn = function() end, -- un avertissement par modèle introuvable (vérifié par models.spec)
}
local cache: { [string]: any } = {}
local function load(path: string): any
	if cache[path] ~= nil then
		return cache[path]
	end
	local env: { [string]: any } = { script = Shim.Node(path) }
	env.require = function(target: any)
		local target_ = if type(target) == "table" then rawget(target, "__path") else nil
		if target_ then
			return load(target_)
		end
		error("require non supporté : " .. tostring(target))
	end
	for key, value in globals do
		env[key] = value
	end
	local result = luau.load(Fs.readFile(path), { debugName = path, environment = env })()
	cache[path] = result
	return result
end

local AppPanels = load("src/server/World/Tower/AppPanels.luau")
local Common = load("src/server/World/Tower/Common.luau")
local tower = load("src/server/World/TowerBuilder.luau").Build()
local descendants = tower:GetDescendants()

local function extents(part: any): any
	if part:IsA("Part") and part.Shape == Enum.PartType.Ball then
		return part.Size / 2 -- une boule ne grossit pas en tournant
	end
	local cf, size = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return V3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) / 2
end

local function tagged(tag: string): { any }
	local list = {}
	for _, d in descendants do
		if d:HasTag(tag) then
			table.insert(list, d)
		end
	end
	return list
end

-- Segment a -> b coupé par la boîte alignée (lo, hi) ?
local function segmentHits(a: any, b: any, lo: any, hi: any): boolean
	local t0, t1 = 0.02, 0.98
	for _, axis in { "X", "Y", "Z" } do
		local p, d = a[axis], b[axis] - a[axis]
		if math.abs(d) < 1e-9 then
			if p < lo[axis] or p > hi[axis] then
				return false
			end
		else
			local u0, u1 = (lo[axis] - p) / d, (hi[axis] - p) / d
			t0, t1 = math.max(t0, math.min(u0, u1)), math.min(t1, math.max(u0, u1))
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

local function worldOf(instance: any): number?
	local node = instance
	while node and node ~= tower do
		local w = node:GetAttribute("World")
		if node:IsA("Model") and type(w) == "number" then
			return w
		end
		node = node.Parent
	end
	return nil
end

local function progress(world: number, reached: number, cleared: boolean): any
	return AppPages.Progress(world, Tower.FirstStage(world) - 1 + reached, if cleared then world else world - 1)
end

------------------------------------------------------------------------------------

return {
	["Tower : chaque monde est une page de l'app, avec son sous-titre"] = function()
		local expected = {
			"Alimentation",
			"Applications",
			"Disques",
			"Diagnostic · Températures",
			"Test de perf",
			"Pilotes GPU",
			"Plantages",
		}
		for w, def in Tower.Worlds do
			Expect.equal(def.AppSection, expected[w], `AppSection du monde {w}`)
			Expect.truthy(type(def.AppSubtitle) == "string" and #def.AppSubtitle > 20, `AppSubtitle du monde {w}`)
			Expect.truthy(string.find(def.AppSubtitle, "%.$") ~= nil, `sous-titre du monde {w} : une phrase`)
		end
		Expect.equal(
			Tower.Worlds[3].AppSubtitle,
			"L'état de tes SSD et disques durs, et ce qui prend la place, dossier par dossier."
		)
		Expect.equal(Tower.Worlds[7].AppSubtitle, "Ce qui a fait planter ton PC, et quoi faire ensuite.")
		Expect.equal(#AppPages.Kinds, Tower.WORLD_COUNT, "types de fenêtres par monde")
		Expect.equal(AppPages.SidebarLabel(4), "Diagnostic", "entrée de la barre latérale")
		local labels = {}
		for _, item in AppPages.Sidebar do
			labels[item.Label] = true
		end
		for w = 1, Tower.WORLD_COUNT do
			Expect.truthy(labels[AppPages.SidebarLabel(w)], `page du monde {w} dans la barre latérale`)
		end
	end,

	["AppPages : progression du joueur dans un monde"] = function()
		local start = AppPages.Progress(3, Tower.FirstStage(3) - 1, 2)
		Expect.equal(start.Reached, 0, "entrée du monde 3")
		Expect.equal(start.Cleared, false)
		Expect.equal(start.Fraction, 0)
		local mid = AppPages.Progress(3, Tower.FirstStage(3) + 1, 2)
		Expect.equal(mid.Reached, 2, "2 checkpoints atteints")
		Expect.near(mid.Fraction, 0.36, 1e-9)
		local room = AppPages.Progress(3, Tower.TerminalStage(3), 2)
		Expect.near(room.Fraction, 0.9, 1e-9, "salle du terminal : 90 %")
		local done = AppPages.Progress(3, Tower.TerminalStage(3), 3)
		Expect.equal(done.Cleared, true)
		Expect.equal(done.Fraction, 1)
		Expect.equal(AppPages.Progress(3, 0, 0).Reached, 0, "lobby")
		Expect.equal(AppPages.Progress(3, Tower.TOTAL_STAGES, 7).Fraction, 1, "au sommet")
		Expect.equal(AppPages.Progress(1, 40, 0).Reached, Tower.STAGES_PER_WORLD, "borné")
	end,

	["AppPages : Alimentation, Applications, Disques"] = function()
		-- Alimentation
		Expect.equal(AppPages.PowerPlans[AppPages.PowerPlan(progress(1, 0, false))], "Économie d'énergie")
		Expect.equal(AppPages.PowerPlans[AppPages.PowerPlan(progress(1, 3, false))], "Équilibré")
		Expect.equal(AppPages.PowerPlans[AppPages.PowerPlan(progress(1, 5, true))], "Performances maximales")
		for t = 0, 20, 0.37 do
			Expect.equal(AppPages.Watts(progress(1, 2, false), t, true), 0, "BLACKOUT : 0 W")
			Expect.between(AppPages.Watts(progress(1, 2, false), t, false), 0, AppPages.MAX_WATTS)
			Expect.between(AppPages.Watts(progress(1, 5, true), t, false), 500, 540, "stable une fois nettoyé")
		end
		-- Applications : une appli coupée par checkpoint (par le bas), LAGZ_miner.exe au nettoyage
		for reached = 0, Tower.STAGES_PER_WORLD do
			local p = progress(2, reached, false)
			Expect.equal(AppPages.StartupOff(p), reached, `checkpoint {reached}`)
			Expect.truthy(AppPages.StartupEnabled(p, 1), "LAGZ_miner.exe résiste jusqu'au nettoyage")
		end
		local cleaned = progress(2, 5, true)
		for i = 1, #AppPages.StartupApps do
			Expect.equal(AppPages.StartupEnabled(cleaned, i), false, `appli {i} coupée au nettoyage`)
		end
		Expect.equal(AppPages.StartupApps[1].Name, "LAGZ_miner.exe")
		Expect.equal(AppPages.StartupCount(progress(2, 0, false)), 214, "214 applis au démarrage")
		Expect.truthy(AppPages.StartupCount(cleaned) < 20, "presque plus rien au démarrage")
		Expect.truthy(AppPages.MemoryUsed(progress(2, 0, false)) > AppPages.MemoryUsed(cleaned), "mémoire libérée")
		-- Disques : C: 420,5 Go · 90 %, la barre descend, « Sain » au nettoyage
		local disk0 = progress(3, 0, false)
		Expect.equal(AppPages.Decimal(AppPages.DiskUsed(disk0)), "420,5")
		Expect.equal(AppPages.DiskPercent(disk0), 91)
		Expect.equal(AppPages.DiskStatus(disk0), "Attention")
		local last = math.huge
		for reached = 0, Tower.STAGES_PER_WORLD do
			local used = AppPages.DiskUsed(progress(3, reached, false))
			Expect.truthy(used < last, "l'espace utilisé baisse à chaque checkpoint")
			last = used
		end
		Expect.equal(AppPages.DiskStatus(progress(3, 5, true)), "Sain")
		Expect.truthy(AppPages.DiskPercent(progress(3, 5, true)) < 50, "disque dégagé")
	end,

	["AppPages : carte « Où part ton espace disque » (LAGZ_cache 70 %)"] = function()
		for _, reached in { 0, 2, 5 } do
			local shares = AppPages.DiskShares(progress(3, reached, reached == 5))
			local sum = 0
			for _, s in shares do
				Expect.truthy(s.Share >= 0, "part positive")
				sum += s.Share
			end
			Expect.near(sum, 1, 1e-9, "les parts couvrent le disque")
			local tiles = AppPages.Treemap(shares)
			local area = 0
			for _, tile in tiles do
				Expect.truthy(tile.X >= -1e-9 and tile.Y >= -1e-9, `{tile.Name} dans le cadre`)
				Expect.truthy(tile.X + tile.W <= 1 + 1e-9 and tile.Y + tile.H <= 1 + 1e-9, `{tile.Name} dans le cadre`)
				Expect.near(tile.W * tile.H, tile.Share, 1e-6, `aire de {tile.Name} = sa part`)
				area += tile.W * tile.H
			end
			Expect.near(area, 1, 1e-6, "la carte est pleine")
			-- Pas de chevauchement
			for i = 1, #tiles do
				for j = i + 1, #tiles do
					local a, b = tiles[i], tiles[j]
					local dx = math.min(a.X + a.W, b.X + b.W) - math.max(a.X, b.X)
					local dy = math.min(a.Y + a.H, b.Y + b.H) - math.max(a.Y, b.Y)
					Expect.truthy(dx <= 1e-6 or dy <= 1e-6, `{a.Name} / {b.Name} se chevauchent`)
				end
			end
		end
		local first = AppPages.Treemap(AppPages.DiskShares(progress(3, 0, false)))[1]
		Expect.equal(first.Name, "LAGZ_cache", "le plus gros rectangle")
		Expect.near(first.Share, 0.7, 1e-9, "LAGZ_cache prend 70 %")
		for _, tile in AppPages.Treemap(AppPages.DiskShares(progress(3, 5, true))) do
			Expect.truthy(tile.Name ~= "LAGZ_cache", "LAGZ_cache disparaît au nettoyage")
		end
	end,

	["AppPages : Températures, Test de perf, Pilotes GPU, Plantages"] = function()
		-- Températures : refroidissent à chaque checkpoint, la SURCHAUFFE ajoute des degrés
		local lastCpu = math.huge
		for reached = 0, Tower.STAGES_PER_WORLD do
			local cpu, gpu = AppPages.Temps(progress(4, reached, false), false)
			Expect.truthy(cpu < lastCpu and gpu < 100, "ça refroidit")
			lastCpu = cpu
		end
		local cpu0 = AppPages.Temps(progress(4, 0, false), false)
		Expect.equal(cpu0, 97, "97 °C au départ (comme le widget du PC)")
		local hot = AppPages.Temps(progress(4, 2, false), true)
		Expect.truthy(hot > AppPages.Temps(progress(4, 2, false), false), "surchauffe")
		Expect.equal((AppPages.TempLabel(97)), "Brûlant")
		Expect.equal((AppPages.TempLabel(45)), "Frais")
		Expect.truthy(
			AppPages.IssueFixed(progress(4, 2, false), 1) and not AppPages.IssueFixed(progress(4, 5, false), 3)
		)
		Expect.truthy(AppPages.IssueFixed(progress(4, 5, true), 3), "Dusty part au nettoyage")
		-- Test de perf
		Expect.equal(AppPages.FpsTarget(progress(5, 0, false)), 3)
		Expect.equal(AppPages.FpsTarget(progress(5, 5, true)), 144)
		local lagged = 0
		for t = 0, 10, 0.1 do
			local fps = AppPages.FpsSample(progress(5, 3, false), t, true)
			Expect.between(fps, 0, 240)
			if fps <= 3 then
				lagged += 1
			end
		end
		Expect.truthy(lagged > 10, "le LAG SPIKE fait des trous dans le graphe")
		Expect.equal((AppPages.PerfTest(progress(5, 0, false))), "Ready", "« Lancer le test » au départ")
		Expect.equal((AppPages.PerfTest(progress(5, 2, false))), "Running")
		Expect.equal((AppPages.PerfTest(progress(5, 5, true))), "Done")
		-- Pilotes GPU
		Expect.equal(AppPages.DriverSteps[AppPages.DriverStep(progress(6, 0, false))], "Préparer l'installation")
		Expect.equal(AppPages.DriverSteps[AppPages.DriverStep(progress(6, 2, false))], "Télécharger et extraire")
		Expect.equal(AppPages.DriverPercent(progress(6, 5, true)), 100)
		Expect.truthy(AppPages.DriverPercent(progress(6, 5, false)) < 100, "100 % seulement au nettoyage")
		Expect.equal(AppPages.BridgeLabel(0.42, 1), "Téléchargement du pilote 7.1 · 42 %")
		Expect.equal(AppPages.BridgeLabel(0.5, 2), "Pilote 7.1 · bloqué à 50 %")
		Expect.equal(AppPages.DriverLogLines(progress(6, 5, true)), #AppPages.DriverLog)
		-- Plantages : réglés un par un, tous au nettoyage
		Expect.equal(AppPages.CrashesFixed(progress(7, 0, false)), 0)
		Expect.equal(AppPages.CrashesFixed(progress(7, 3, false)), 3)
		Expect.equal(AppPages.CrashesFixed(progress(7, 5, true)), #AppPages.Crashes)
	end,

	["AppPages : intros des terminaux = la page du monde qui fait son action"] = function()
		Expect.equal(AppPages.Intro(3).Action, "Analyser")
		Expect.equal(AppPages.Intro(6).Action, "Télécharger et extraire")
		Expect.equal(AppPages.Intro(4).Action, "Analyse express")
		Expect.equal(AppPages.Intro(7).Action, "Remettre d'aplomb")
		for w = 1, Tower.WORLD_COUNT do
			local intro = AppPages.Intro(w)
			Expect.equal(intro.Page, Tower.Worlds[w].AppSection)
			Expect.truthy(#intro.Action > 0 and #intro.Task > 0 and #intro.Detail > 0, `intro du monde {w}`)
			-- Terminal du monde : sa propre page
			Expect.equal(AppPages.IntroWorld(Tower.Worlds[w].Minigame, w), w, `terminal du monde {w}`)
		end
		-- Borne d'arcade (niveau 2) : la page du jeu joué
		Expect.equal(AppPages.IntroWorld("Defrag", 2), 3)
		Expect.equal(AppPages.IntroWorld("Memory", 2), 6)
		Expect.equal(AppPages.IntroWorld("Popup", 2), 2)
	end,

	["CrashLogic : causes, comptes par cause et par monde, cartes"] = function()
		Expect.equal(CrashLogic.CauseLabel("SpinBar"), "Ventilateur")
		Expect.equal(CrashLogic.CauseLabel("Void"), "Chute dans le vide")
		Expect.equal(CrashLogic.CauseLabel(nil), CrashLogic.UNKNOWN)
		Expect.equal(CrashLogic.CauseLabel("NouveauPiege"), "NouveauPiege", "cause inconnue affichée telle quelle")
		for _, kind in Tower.TrapKinds do
			Expect.truthy(#CrashLogic.CauseLabel(kind) > 0, `libellé de {kind}`)
		end
		Expect.equal(CrashLogic.Ordinal(1), "1re")
		Expect.equal(CrashLogic.Ordinal(3), "3e")
		Expect.equal(CrashLogic.ExeName("Luffyy"), "Luffyy.exe")
		Expect.equal(CrashLogic.ExeName("Super Joueur!"), "SuperJoueur.exe")
		Expect.equal(CrashLogic.ExeName(""), "Joueur.exe")
		Expect.equal(CrashLogic.ExeName("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), "ABCDEFGHIJKLMNOP.exe")
		local log = CrashLogic.new()
		Expect.equal(CrashLogic.Record(log, "SpinBar", 4), 1)
		Expect.equal(CrashLogic.Record(log, "SpinBar", 4), 2)
		Expect.equal(CrashLogic.Record(log, "Void", 4), 1, "autre cause")
		Expect.equal(CrashLogic.Record(log, "SpinBar", 6), 1, "autre monde : 1re fois ici")
		Expect.equal(CrashLogic.Record(log, "SpinBar", 4), 3)
		Expect.equal(CrashLogic.Record(log, nil, 4), 1, "mort sans cause")
		Expect.equal(log.Total, 6)
		Expect.equal(log.ByCause.SpinBar, 4)
		local top, count = CrashLogic.TopCause(log)
		Expect.equal(top, "SpinBar")
		Expect.equal(count, 4)
		local title, detail = CrashLogic.Format("Joueur.exe", "SpinBar", 3)
		Expect.equal(detail, "cause : Ventilateur · 3e fois ici")
		Expect.equal(title, "Joueur.exe s'est figé 3 fois ici")
		local first = CrashLogic.Format("Joueur.exe", "Zapper", 1)
		Expect.equal(first, "Joueur.exe s'est fermé tout seul")
		Expect.equal(CrashLogic.TopCause(CrashLogic.new()), nil, "aucune mort")
	end,

	["fenêtres de l'app : 2 à 4 par monde, contrat, décor pur, face à l'intérieur"] = function()
		local panels = tagged("AppPanel")
		local perWorld: { [number]: { [string]: number } } = {}
		for _, panel in panels do
			local w = panel:GetAttribute("World")
			local kind = panel:GetAttribute("Kind")
			Expect.truthy(type(w) == "number" and Tower.Worlds[w] ~= nil, `World de {panel:GetFullName()}`)
			Expect.equal(worldOf(panel), w, `fenêtre rangée dans World{w}`)
			Expect.equal(panel:GetAttribute("Page"), Tower.Worlds[w].AppSection, "Page = AppSection")
			Expect.truthy(table.find(AppPages.Kinds[w], kind) ~= nil, `Kind {kind} du monde {w}`)
			perWorld[w] = perWorld[w] or {}
			perWorld[w][kind] = (perWorld[w][kind] or 0) + 1
			Expect.equal(panel.CanCollide, false, "non solide")
			Expect.equal(panel.CanQuery, false, "ignorée par les rayons")
			Expect.equal(panel.CanTouch, false, "pas de contact")
			Expect.truthy(panel.Size.Z <= 0.5 and panel.Size.X >= 30 and panel.Size.Y >= 10, "grande dalle fine")
			Expect.equal(panel:FindFirstChildOfClass("SurfaceGui"), nil, "SurfaceGui posé par le client")
			-- Contre une paroi intérieure (pas la vitre +X), face avant vers l'intérieur
			local p, look = panel.CFrame.Position, panel.CFrame.LookVector
			local onWall = math.abs(p.X + Common.INNER) < 1.5
				or math.abs(p.Z + Common.INNER) < 1.5
				or math.abs(p.Z - Common.INNER) < 1.5
			Expect.truthy(onWall, `{kind} plaquée sur une paroi`)
			local inward = V3.new(-p.X, 0, -p.Z).Unit
			Expect.truthy(look:Dot(inward) > 0.6, `{kind} tournée vers l'intérieur`)
			Expect.truthy(math.abs(look.Y) < 1e-6, "verticale")
			local base = Common.WorldBase(w)
			local e = extents(panel)
			Expect.truthy(
				p.Y - e.Y >= base + 5 and p.Y + e.Y <= base + Common.BAND,
				`{kind} dans la tranche du monde {w}`
			)
		end
		for w = 1, Tower.WORLD_COUNT do
			local kinds = perWorld[w] or {}
			local count = 0
			for _, n in kinds do
				count += n
			end
			Expect.between(count, 2, 4, `fenêtres du monde {w}`)
			for _, kind in AppPages.Kinds[w] do
				Expect.equal(kinds[kind], 1, `{kind} posée une fois au monde {w}`)
			end
		end
		Expect.equal(#AppPanels.Spots, #panels, "un emplacement par fenêtre")
	end,

	["fenêtres de l'app : hors du parcours, dégagées, visibles depuis le parcours"] = function()
		local panels = tagged("AppPanel")
		-- Boîtes de toutes les autres pièces (visibles ou solides), hors fenêtres de l'app
		local boxes = {}
		for _, d in descendants do
			local ours = d.Parent and d.Parent.Name == "AppPanels"
			if d:IsA("BasePart") and not ours and (d.CanCollide or d.Transparency < 1) then
				local e, c = extents(d), d.CFrame.Position
				table.insert(boxes, {
					Lo = c - e,
					Hi = c + e,
					Opaque = d.Transparency < 0.5
						and d.Material ~= Enum.Material.Glass
						and d.Material ~= Enum.Material.ForceField
						and math.max(d.Size.X, d.Size.Y, d.Size.Z) > 1.5,
					Name = d:GetFullName(),
				})
			end
		end
		local report = {}
		for _, panel in panels do
			local w = panel:GetAttribute("World")
			local kind = panel:GetAttribute("Kind")
			local cf, size = panel.CFrame, panel.Size
			-- Volume dégagé : la fenêtre (+1 stud tout autour), de la paroi jusqu'à 8 studs devant
			local a = cf:PointToWorldSpace(V3.new(-size.X / 2 - 1, -size.Y / 2 - 1, 2))
			local b = cf:PointToWorldSpace(V3.new(size.X / 2 + 1, size.Y / 2 + 1, -8))
			local lo = V3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
			local hi = V3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
			for _, box in boxes do
				local inside = box.Lo.X < hi.X
					and box.Hi.X > lo.X
					and box.Lo.Y < hi.Y
					and box.Hi.Y > lo.Y
					and box.Lo.Z < hi.Z
					and box.Hi.Z > lo.Z
				-- La coque (parois) est derrière la fenêtre : seule une pièce DEVANT compte
				local shell = string.find(box.Name, "%.Shell%.") ~= nil
				Expect.truthy(not inside or shell, `{kind} (monde {w}) touche {box.Name}`)
			end
			-- Visible depuis le parcours : checkpoints et dessus de plateformes du monde (yeux à +5)
			local eyes = {}
			local world = tower[`World{w}`]
			for _, d in world:GetDescendants() do
				if
					d:IsA("BasePart")
					and d.CanCollide
					and math.abs(d.CFrame.UpVector.Y) > 0.99
					and d.Size.X >= 2.5
					and d.Size.Z >= 2.5
					and d.Size.X <= 60
					and d.Size.Z <= 60
				then
					local e, c = extents(d), d.CFrame.Position
					table.insert(eyes, V3.new(c.X, c.Y + e.Y + 5, c.Z))
				end
			end
			for _, pad in tagged("Checkpoint") do
				if Tower.WorldOf(pad:GetAttribute("Stage")) == w then
					table.insert(eyes, pad.CFrame.Position + V3.new(0, 5.5, 0))
				end
			end
			local front = cf.Position + cf.LookVector * 1.5
			local seen = 0
			for _, eye in eyes do
				local delta = eye - front
				local distance = delta.Magnitude
				if distance > 15 and distance < 170 and delta.Unit:Dot(cf.LookVector) > 0.3 then
					local blocked = false
					for _, box in boxes do
						if box.Opaque and segmentHits(eye, front, box.Lo, box.Hi) then
							blocked = true
							break
						end
					end
					if not blocked then
						seen += 1
					end
				end
			end
			table.insert(report, `{kind} {seen}`)
			Expect.truthy(seen >= 8, `{kind} (monde {w}) vue depuis {seen} points du parcours seulement`)
		end
		print(`    points du parcours qui voient chaque fenêtre : {table.concat(report, ", ")}`)
	end,

	["monde 6 : ponts de chargement à étiqueter (« Téléchargement du pilote »)"] = function()
		local bridges = 0
		for _, trap in tagged("Trap") do
			if trap:GetAttribute("Kind") == "LoadBridge" and trap:GetAttribute("World") == 6 then
				bridges += 1
			end
		end
		Expect.truthy(bridges >= 1, "le client étiquette les LoadBridge du monde 6")
	end,

	["lobby : Anga géant, décor pur, tourné vers la tour, n'occulte pas l'écran du live"] = function()
		local giants = tagged("GiantAnga")
		Expect.equal(#giants, 1, "un Anga géant")
		local giant = giants[1]
		Expect.truthy(giant:IsA("Model") and giant:IsDescendantOf(tower.Lobby), "Model du lobby")
		local lo, hi = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
		local parts = {}
		for _, d in giant:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
				Expect.equal(d.CanCollide, false, `{d.Name} traversable`)
				Expect.equal(d.CanQuery, false, `{d.Name} ignoré par la caméra`)
				Expect.equal(d.CanTouch, false, `{d.Name} sans contact`)
				Expect.equal(d.CastShadow, false, `{d.Name} sans ombre`)
				local e, c = extents(d), d.CFrame.Position
				lo = V3.new(math.min(lo.X, c.X - e.X), math.min(lo.Y, c.Y - e.Y), math.min(lo.Z, c.Z - e.Z))
				hi = V3.new(math.max(hi.X, c.X + e.X), math.max(hi.Y, c.Y + e.Y), math.max(hi.Z, c.Z + e.Z))
			end
		end
		Expect.truthy(#parts >= 20, "décor de secours reconnaissable")
		Expect.truthy(hi.Y - lo.Y >= 1500, `géant : {math.floor(hi.Y - lo.Y)} studs`)
		Expect.near(lo.Y, -900, 3, "debout au sol de la chambre")
		Expect.truthy(
			lo.X > -1500 and hi.X < 1600 and lo.Z > -2100 and hi.Z < 380 and hi.Y < 1700,
			`dans la chambre : {lo} .. {hi}`
		)
		-- Rien de lui dans le bureau ni juste au-dessus (l'aire de jeu du lobby) : il peut se pencher
		-- au-dessus du bord du bureau, mais bien plus haut que les joueurs ; il ne traverse aucun objet.
		local others = {}
		for _, d in tower.Lobby:GetDescendants() do
			if d:IsA("BasePart") and not d:IsDescendantOf(giant) and d.Transparency < 1 then
				local e, c = extents(d), d.CFrame.Position
				table.insert(others, { Part = d, Lo = c - e, Hi = c + e })
			end
		end
		-- Deux boîtes orientées se traversent si un coin (ou le centre) de l'une est dans l'autre
		local function corners(part: any): { any }
			local list, h = { part.CFrame.Position }, part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						table.insert(list, part.CFrame:PointToWorldSpace(V3.new(sx * h.X, sy * h.Y, sz * h.Z)))
					end
				end
			end
			return list
		end
		local function inside(point: any, part: any): boolean
			local q, h = part.CFrame:PointToObjectSpace(point), part.Size / 2
			return math.abs(q.X) < h.X - 0.5 and math.abs(q.Y) < h.Y - 0.5 and math.abs(q.Z) < h.Z - 0.5
		end
		for _, part in parts do
			local e, c = extents(part), part.CFrame.Position
			local plo, phi = c - e, c + e
			-- Aire de jeu : le dessus du bureau jusqu'à 50 studs de haut
			local deskLo, deskHi = V3.new(-760, -44, -660), V3.new(900, 50, 330)
			local intrudes
			if part:IsA("Part") and part.Shape == Enum.PartType.Ball then
				local nearest = V3.new(
					math.clamp(c.X, deskLo.X, deskHi.X),
					math.clamp(c.Y, deskLo.Y, deskHi.Y),
					math.clamp(c.Z, deskLo.Z, deskHi.Z)
				)
				intrudes = (nearest - c).Magnitude < part.Size.X / 2
			else
				intrudes = phi.X > deskLo.X
					and plo.X < deskHi.X
					and phi.Y > deskLo.Y
					and plo.Y < deskHi.Y
					and phi.Z > deskLo.Z
					and plo.Z < deskHi.Z
			end
			Expect.truthy(not intrudes, `{part.Name} dans l'aire de jeu du bureau`)
			local mine = corners(part)
			for _, other in others do
				if
					plo.X < other.Hi.X
					and phi.X > other.Lo.X
					and plo.Y < other.Hi.Y
					and phi.Y > other.Lo.Y
					and plo.Z < other.Hi.Z
					and phi.Z > other.Lo.Z
				then
					local crossing = false
					for _, point in mine do
						crossing = crossing or inside(point, other.Part)
					end
					for _, point in corners(other.Part) do
						crossing = crossing or inside(point, part)
					end
					Expect.truthy(not crossing, `{part.Name} traverse {other.Part:GetFullName()}`)
				end
			end
		end
		-- Tourné vers la tour (le t-shirt, et son « A », regarde la tour)
		local shirt = giant:FindFirstChild("Shirt", true)
		Expect.truthy(shirt ~= nil, "t-shirt rouge")
		local toTower = (V3.new(0, 0, 0) - shirt.CFrame.Position) * V3.new(1, 0, 1)
		Expect.truthy(shirt.CFrame.LookVector:Dot(toTower.Unit) > 0.95, "Anga regarde la tour")
		Expect.truthy(
			giant:FindFirstChild("Head") ~= nil and typeof(giant:GetAttribute("NeckPivot")) == "Vector3",
			"tête animable"
		)
		-- N'occulte pas l'écran du live vu du spawn
		local spawn = tower.Lobby.LobbySpawn
		local screen = tagged("StreamMonitor")[1]
		local eye = spawn.CFrame.Position + V3.new(0, 5, 0)
		for _, u in { -0.45, 0, 0.45 } do
			for _, v in { -0.4, 0, 0.4 } do
				local target = (screen.CFrame * roblox.CFrame.new(screen.Size.X * u, screen.Size.Y * v, -1)).Position
				for _, part in parts do
					local e, c = extents(part), part.CFrame.Position
					Expect.truthy(not segmentHits(eye, target, c - e, c + e), `{part.Name} cache l'écran du live`)
				end
			end
		end
	end,

	["budget client : fenêtres (bande de mondes, hystérésis, toile réduite), tour vue de dedans"] = function()
		-- Dimensions recopiées côté client = celles de la tour construite
		Expect.equal(AppPages.TOWER_INNER, Common.INNER)
		Expect.equal(AppPages.TOWER_TOP, Common.TOP)
		Expect.truthy(AppPages.InsideTower(0, 300, 0), "au milieu de la tour")
		Expect.truthy(AppPages.InsideTower(-100, 5, 120), "au monde 1")
		local spawn = tower.Lobby.LobbySpawn.CFrame.Position
		Expect.truthy(not AppPages.InsideTower(spawn.X, spawn.Y + 5, spawn.Z), "au lobby")
		Expect.truthy(not AppPages.InsideTower(0, Common.TOP + 20, 0), "au-dessus du toit")
		-- Seuls le monde parcouru et le suivant ont des fenêtres
		Expect.truthy(AppPages.PanelWorldActive(3, 3) and AppPages.PanelWorldActive(4, 3))
		Expect.truthy(not AppPages.PanelWorldActive(2, 3) and not AppPages.PanelWorldActive(5, 3))
		-- Hystérésis d'au moins 60 studs, face avant exigée seulement pour apparaître
		local show, hide = AppPages.PANEL_SHOW, AppPages.PANEL_HIDE
		Expect.truthy(hide - show >= 60, "hystérésis ≥ 60 studs")
		Expect.equal(AppPages.PanelShown(false, show - 1, true), true)
		Expect.equal(AppPages.PanelShown(false, show - 1, false), false, "de dos : pas encore")
		Expect.equal(AppPages.PanelShown(false, show + 10, true), false)
		Expect.equal(AppPages.PanelShown(true, show + 50, false), true, "déjà affichée : reste affichée")
		Expect.equal(AppPages.PanelShown(true, hide + 1, true), false)
		-- Toile réduite, mise en page proportionnelle (grille logique de 1 200 px)
		Expect.truthy(AppPages.PANEL_CANVAS_WIDTH <= 800, "toile ≤ 800 px")
		Expect.equal(AppPages.PANEL_LAYOUT_WIDTH, 1200)
		-- Chaque fenêtre s'affiche depuis au moins un checkpoint de son monde (racine à +3)
		for _, panel in tagged("AppPanel") do
			local w = panel:GetAttribute("World")
			local nearest = math.huge
			for _, pad in tagged("Checkpoint") do
				local stage = pad:GetAttribute("Stage")
				if stage > 0 and Tower.WorldOf(stage) == w then
					local root = pad.CFrame.Position + V3.new(0, 3, 0)
					local facing = panel.CFrame.LookVector:Dot(root - panel.CFrame.Position) > 0
					if facing then
						nearest = math.min(nearest, (panel.CFrame.Position - root).Magnitude)
					end
				end
			end
			Expect.truthy(nearest < show, `{panel:GetAttribute("Kind")} : checkpoint le plus proche à {nearest}`)
		end
		-- Anga géant : animé depuis le lobby (hors de la tour, assez près)
		local giant = tagged("GiantAnga")[1]
		local lo, hi = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
		for _, d in giant:GetDescendants() do
			if d:IsA("BasePart") then
				local e, c = extents(d), d.CFrame.Position
				lo = V3.new(math.min(lo.X, c.X - e.X), math.min(lo.Y, c.Y - e.Y), math.min(lo.Z, c.Z - e.Z))
				hi = V3.new(math.max(hi.X, c.X + e.X), math.max(hi.Y, c.Y + e.Y), math.max(hi.Z, c.Z + e.Z))
			end
		end
		local center = (lo + hi) / 2
		local eye = spawn + V3.new(0, 8, 12)
		Expect.truthy((center - eye).Magnitude < AppPages.GIANT_RANGE, "animé vu du spawn")
	end,

	["aucune vraie marque : carte graphique, micrologiciel et pilote inventés"] = function()
		Expect.equal(AppPages.GPU_NAME, "Carte graphique AngaGPU 7000")
		Expect.equal(AppPages.DISK_FIRMWARE, "AIO-1.0")
		Expect.equal(AppPages.DRIVER_NEW, "7.1")
		Expect.truthy(string.find(AppPages.DriverLog[1], AppPages.GPU_NAME, 1, true) ~= nil)
	end,
}
