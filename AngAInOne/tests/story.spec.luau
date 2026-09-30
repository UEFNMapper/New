-- Scénario par l'image (v3 · V2) : rôle du technicien, pages de l'app, rapport d'optimisation,
-- tour qui s'allume monde par monde, apparitions de LAGZ (emplacements et contrat d'instances).
local roblox = require("@lune/roblox")

local Instance, Enum, V3 = roblox.Instance, roblox.Enum, roblox.Vector3

local Tower = Shim.load("src/shared/Config/Tower.luau")
local PcHealth = Shim.load("src/shared/Util/PcHealth.luau")
local Technician = Shim.load("src/shared/Util/Technician.luau")
local AppPages = Shim.load("src/shared/Util/AppPages.luau")
local Report = Shim.load("src/shared/Util/OptimisationReport.luau")
local ShellGlow = Shim.load("src/shared/Util/ShellGlow.luau")

-- Cameos (serveur) : même environnement simulé que tests/tower.spec.luau (les modules du monde
-- chargés ici sont partagés avec la tour construite par tower.spec).
local function lookAt(at: any, target: any, up: any?): any
	local look = (target - at).Unit
	local right = look:Cross(up or V3.new(0, 1, 0)).Unit
	local trueUp = right:Cross(look)
	return roblox.CFrame.fromMatrix(at, right, trueUp, -look)
end
local CFrame = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })
local dataModel = Instance.new("DataModel")
local workspace = dataModel:GetService("Workspace")
Shim.Globals = {
	game = {
		GetService = function(_self: any, name: string): any
			if name == "Workspace" then
				return workspace
			elseif name == "ReplicatedStorage" then
				return {
					WaitForChild = function()
						return Shim.Node("src/shared")
					end,
				}
			elseif name == "CollectionService" then
				return {
					AddTag = function(_s: any, instance: any, tag: string)
						instance:AddTag(tag)
					end,
				}
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
}
local Cameos = Shim.load("src/server/World/Tower/Cameos.luau")
local Common = Shim.load("src/server/World/Tower/Common.luau")
Shim.Globals = {}

local function extents(part: any): any
	local cf, size = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return V3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) / 2
end

return {
	["technicien : numéro stable à 4 chiffres, varié d'un joueur à l'autre"] = function()
		Expect.equal(Technician.Number(123456789), Technician.Number(123456789), "stable")
		local seen: { [number]: boolean } = {}
		local distinct = 0
		for id = 1, 3000, 3 do
			local n = Technician.Number(id)
			Expect.between(n, 1, 9999, `numéro de {id}`)
			Expect.equal(n, math.floor(n), "entier")
			if not seen[n] then
				seen[n] = true
				distinct += 1
			end
		end
		Expect.truthy(distinct >= 990, `numéros trop souvent identiques : {distinct}/1000`)
		for _, id in { -1, -2, 0, 1, 99999999999 } do
			local code = Technician.Code(id)
			Expect.truthy(string.match(code, "^%d%d%d%d$") ~= nil, `code sur 4 chiffres : {code}`)
		end
		Expect.equal(Technician.Short(1), `Technicien·ne n° {Technician.Code(1)}`)
		Expect.equal(Technician.Title(1), `Technicien·ne AngAInOne n° {Technician.Code(1)}`)
	end,

	["pages de l'app : une par monde, secours si Tower n'a pas AppSubtitle, barre latérale sans doublon"] = function()
		for w = 1, Tower.WORLD_COUNT do
			local page = AppPages.Of(w, Tower.Worlds[w])
			Expect.truthy(#page.Title > 0 and #page.Subtitle > 0, `page du monde {w}`)
		end
		Expect.equal(AppPages.Of(3, { AppSection = "Nettoyage" }).Title, "Disques", "sans sous-titre : page de secours")
		local custom = AppPages.Of(1, { AppSection = "Alimentation", AppSubtitle = "Le courant." })
		Expect.equal(custom.Subtitle, "Le courant.", "Tower.AppSubtitle prime")
		Expect.equal(AppPages.Of(7).Title, "Plantages")
		local side = AppPages.Sidebar(nil)
		Expect.equal(side[1], "Tableau de bord")
		Expect.truthy(table.find(side, "Diagnostic") ~= nil, "Diagnostic dans la barre latérale")
		Expect.truthy(table.find(side, "Températures") ~= nil, "sous-page « Diagnostic · Températures »")
		local seen = {}
		for _, name in AppPages.Sidebar(Tower.Worlds) do
			Expect.truthy(not seen[name], `doublon : {name}`)
			seen[name] = true
		end
	end,

	["rapport : score 48 -> 100, avant / après du PC, 5 cartes, 7 menaces"] = function()
		local r = Report.Build({ Time = 754.55, Record = true, Keys = 18, KeysTotal = 21, Deaths = 12 })
		Expect.equal(r.StartScore, 48)
		Expect.equal(r.Score, 100)
		Expect.equal(r.Threats, Tower.WORLD_COUNT)
		local before, after = PcHealth.Stats(0), PcHealth.Stats(Tower.WORLD_COUNT)
		Expect.equal(r.Deltas[1].From, before.Fps)
		Expect.equal(r.Deltas[1].To, 144)
		Expect.equal(r.Deltas[2].From, 97)
		Expect.equal(r.Deltas[2].To, after.Temp)
		Expect.equal(r.Deltas[3].From, 999)
		Expect.equal(r.Deltas[3].To, 8)
		local titles = {}
		for _, c in r.Cards do
			table.insert(titles, c.Title)
			Expect.between(c.Score, 0, 100, c.Title)
		end
		Expect.equal(table.concat(titles, ","), "Score,Températures,Stockage,Stabilité,À jour")
		Expect.equal(r.Cards[3].Score, 70 + math.floor(30 * 18 / 21 + 0.5), "stockage selon les clés")
		Expect.equal(r.Cards[4].Score, 76, "stabilité : 100 - 2 × 12 chutes")
		Expect.equal(r.KeysText, "18/21")
		Expect.equal(r.DeathsText, "12")
		Expect.equal(r.TimeText, "12:34.5")
		Expect.equal(r.RecordText, "NOUVEAU RECORD !")
		Expect.truthy(string.find(r.Headline, "144 FPS", 1, true) ~= nil, "titre : 144 FPS")
		Expect.equal(#r.Entries, Tower.WORLD_COUNT, "une entrée par menace")
		for i, entry in r.Entries do
			Expect.equal(entry.Minion, Tower.Worlds[i].Minion)
			for _, field in { entry.Title, entry.Constat, entry.Pourquoi, entry.QuoiFaire, entry.Action } do
				Expect.truthy(#field > 0 and #field <= 80, `texte court (monde {i}) : {field}`)
			end
		end
		-- Sans données de chutes / clés : valeurs sûres
		local bare = Report.Build({})
		Expect.equal(bare.DeathsText, nil)
		Expect.equal(bare.KeysText, `0/{Tower.WORLD_COUNT * Tower.USB_KEYS_PER_WORLD}`)
		Expect.equal(bare.Cards[4].Score, 100)
		Expect.equal(bare.RecordText, nil)
		Expect.equal(Report.Build({ Assisted = true }).RecordText, "Course assistée (hors classement)")
		Expect.equal(Report.StabilityScore(500), 50, "stabilité : 50 au minimum")
		Expect.equal(Report.StorageScore(21, 21), 100)
		Expect.equal(Report.StorageScore(0, 21), 70)
	end,

	["rapport : animation du score, date et verdict"] = function()
		Expect.equal(Report.ScoreAt(0), 48)
		Expect.equal(Report.ScoreAt(1), 100)
		Expect.equal(Report.ScoreAt(7), 100, "borné")
		local last = 0
		for i = 0, 20 do
			local s = Report.ScoreAt(i / 20)
			Expect.truthy(s >= last, "le score ne redescend pas")
			last = s
		end
		local date = Report.DateText({ year = 2026, month = 9, day = 9, hour = 22, min = 6 })
		Expect.equal(date, "9 septembre 2026 à 22:06")
		Expect.equal(
			Report.Verdict(date),
			"Analyse complète · rapport du 9 septembre 2026 à 22:06 · 109 points vérifiés"
		)
	end,

	["tour qui s'allume : bandes, propre / infecté, victoire, vague, cascade"] = function()
		Expect.equal(ShellGlow.BandOf(0), 1)
		Expect.equal(ShellGlow.BandOf(250), 3)
		Expect.equal(ShellGlow.BandOf(10000), Tower.WORLD_COUNT)
		-- Jauge verticale de la façade (y 96 -> 690) : un morceau par monde, dans l'ordre, sans chevauchement
		local segments = ShellGlow.Segments(96, 690, 3)
		Expect.equal(#segments, Tower.WORLD_COUNT)
		for i, s in segments do
			Expect.equal(s.World, i)
			Expect.truthy(s.Y1 > s.Y0, "morceau non vide")
			if i > 1 then
				Expect.truthy(s.Y0 >= segments[i - 1].Y1 + 2.9, "espace entre deux mondes")
			end
		end
		Expect.truthy(ShellGlow.IsClean(3, 3) and not ShellGlow.IsClean(4, 3), "propre si Cleared >= monde")
		Expect.truthy(
			not ShellGlow.IsClean(0, 6) and ShellGlow.IsClean(0, Tower.WORLD_COUNT),
			"monde 0 : toute la tour"
		)
		Expect.truthy(ShellGlow.IsVictory(Tower.WORLD_COUNT, 0, false), "victoire : tour nettoyée, au lobby")
		Expect.truthy(not ShellGlow.IsVictory(Tower.WORLD_COUNT, 35, true), "pas pendant l'ascension")
		Expect.truthy(not ShellGlow.IsVictory(3, 0, false), "pas sans les 7 mondes")
		for i = 0, 200 do
			local level = ShellGlow.InfectedLevel(i * 0.037, 4.2, false)
			Expect.between(level, 0, 1, "luminosité infectée")
			Expect.between(ShellGlow.InfectedMix(i * 0.037, 4.2, false), 0, 1, "mélange rouge / violet")
		end
		Expect.equal(ShellGlow.InfectedLevel(1, 2, true), ShellGlow.InfectedLevel(9, 7, true), "ReducedMotion : fixe")
		-- Vague : balaie la bande du début à la fin, puis s'éteint
		Expect.truthy(ShellGlow.Wave(0.35, 0.1) > ShellGlow.Wave(0.35, 0.9), "la vague part du début")
		Expect.truthy(ShellGlow.Wave(1.3, 0.9) > ShellGlow.Wave(1.3, 0.1), "puis atteint la fin")
		Expect.equal(ShellGlow.Wave(ShellGlow.WAVE_SECONDS + 0.1, 0.5), 0)
		-- Cascade : le bas est atteint avant le haut, tout est atteint à la fin
		local bottom = ShellGlow.Cascade(0.5, 0.05)
		local top = ShellGlow.Cascade(0.5, 0.95)
		Expect.truthy(bottom and not top, "la cascade monte")
		Expect.truthy((ShellGlow.Cascade(ShellGlow.CASCADE_SECONDS, 1)), "toute la tour à la fin")
		local hue = ShellGlow.RainbowHue(3.3, 0.4)
		Expect.between(hue, 0, 1, "teinte")
	end,

	["LAGZ en 3D : 1 à 2 écrans par monde, hors de l'arène, contre les parois, dans la bande"] = function()
		local perWorld: { [number]: number } = {}
		local stages: { [number]: boolean } = {}
		for _, spot in Cameos.Spots do
			local w = spot.World
			perWorld[w] = (perWorld[w] or 0) + 1
			Expect.truthy(not stages[spot.Stage], `étape {spot.Stage} en double`)
			stages[spot.Stage] = true
			Expect.equal(Tower.WorldOf(spot.Stage), w, `étape {spot.Stage} dans le monde {w}`)
			Expect.truthy(spot.Stage >= Tower.FirstStage(w), "dans le parcours du monde")
			Expect.truthy(
				spot.Stage < Tower.TerminalStage(w) - (if w == Tower.WORLD_COUNT then 1 else 0),
				"pas dans l'arène"
			)
			local base = Common.WorldBase(w)
			local half = Cameos.SCREEN.Y / 2
			Expect.truthy(
				spot.Y - half >= base + 6 and spot.Y + half <= base + Common.BAND,
				`écran dans la bande du monde {w}`
			)
			Expect.truthy(math.abs(spot.Along) <= Common.INNER - Cameos.SCREEN.X / 2, "écran entier sur la paroi")
			local mount = Cameos.MountCFrame(spot)
			local p = mount.Position
			Expect.truthy(
				math.abs(math.max(math.abs(p.X), math.abs(p.Z)) - Common.INNER) < 1e-3,
				"posé sur la face intérieure d'une paroi"
			)
			-- +Z local (avant du modèle) vers l'intérieur de la tour
			local inward = mount:VectorToWorldSpace(V3.new(0, 0, 1))
			Expect.truthy((p + inward * 10).Magnitude < p.Magnitude, `écran tourné vers le parcours ({spot.Wall})`)
		end
		for w = 1, Tower.WORLD_COUNT do
			Expect.between(perWorld[w] or 0, 1, 2, `apparitions de LAGZ dans le monde {w}`)
		end
	end,

	["LAGZ en 3D : décor pur tagué LagzCameo (World, Stage), tête « Head » dans l'écran"] = function()
		local tower = Instance.new("Folder")
		tower.Name = "Tower"
		for w = 1, Tower.WORLD_COUNT do
			local model = Instance.new("Model")
			model.Name = `World{w}`
			local decor = Instance.new("Folder")
			decor.Name = "Decor"
			decor.Parent = model
			model.Parent = tower
		end
		Cameos.Build(tower)
		local count = 0
		for _, d in tower:GetDescendants() do
			if d:HasTag("LagzCameo") then
				count += 1
				Expect.truthy(d:IsA("Model"), "écran = Model")
				local w, s = d:GetAttribute("World"), d:GetAttribute("Stage")
				Expect.truthy(type(w) == "number" and type(s) == "number", "attributs World et Stage")
				Expect.equal(d.Parent.Parent.Name, `World{w}`, "rangé dans le décor de son monde")
				local head = d:FindFirstChild("Head")
				Expect.truthy(head and head:IsA("Model"), "tête (Model Head)")
				Expect.truthy(#head:GetChildren() >= 10, "tête de secours en primitives")
				local statics = 0
				local base = Common.WorldBase(w)
				for _, part in d:GetDescendants() do
					if part:IsA("BasePart") then
						Expect.truthy(part.Anchored, `ancré : {part.Name}`)
						Expect.truthy(
							not part.CanCollide and not part.CanTouch and not part.CanQuery,
							`décor pur : {part:GetFullName()}`
						)
						local c, e = part.CFrame.Position, extents(part)
						local wall = Common.INNER - math.max(math.abs(c.X) + e.X, math.abs(c.Z) + e.Z)
						Expect.truthy(wall > -0.5, `dans la tour : {part.Name}`)
						local depth = Common.INNER - math.max(math.abs(c.X) - e.X, math.abs(c.Z) - e.Z)
						Expect.truthy(depth <= 14, `près de la paroi : {part.Name} ({depth})`)
						Expect.truthy(
							c.Y - e.Y >= base and c.Y + e.Y <= base + Common.BAND,
							`dans la bande : {part.Name}`
						)
						if part.Name == "CameoStatic" then
							statics += 1
						end
					end
				end
				Expect.equal(statics, 5, "neige de l'écran")
			end
		end
		Expect.equal(count, #Cameos.Spots)
	end,
}
