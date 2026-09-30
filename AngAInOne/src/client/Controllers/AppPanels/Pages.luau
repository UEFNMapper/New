--!strict
--[[
	Pages : contenu de chaque fenêtre de l'app posée dans la tour (attribut Kind de la dalle).
	Pages.Build(kind, window) dessine la page dans `window.Content` (≈ 896 × 532 px) et renvoie
	une fonction de mise à jour appelée quelques fois par seconde tant que la fenêtre est proche.
	Les valeurs viennent de Util/AppPanelLogic (progression du joueur dans le monde, incidents).
	Exception : LaunchBanner (bandeau « Lancer le test ») se dessine sans fenêtre (Pages.BuildBanner).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AppPages = require(Shared.Util.AppPanelLogic)
local CrashLogic = require(Shared.Util.CrashLogic)
local PcHealth = require(Shared.Util.PcHealth)
local NumberFormat = require(Shared.Util.NumberFormat)
local Tower = require(Shared.Config.Tower)

local Fluent = require(script.Parent.Fluent)

local C = Fluent.C
local Text, Box, Card, Bar, SetBar, Tag, Glyph =
	Fluent.Text, Fluent.Box, Fluent.Card, Fluent.Bar, Fluent.SetBar, Fluent.Tag, Fluent.Glyph

local Pages = {}

export type State = {
	Progress: AppPages.Progress, -- progression du joueur dans le monde de la fenêtre
	Cleared: number, -- mondes nettoyés (toute la tour)
	Incident: string, -- incident de LAGZ en cours dans ce monde ("" sinon)
	T: number, -- horloge (s)
	Exe: string, -- « Joueur.exe »
	Crash: CrashLogic.Log, -- plantages de la session (Controllers/CrashLog)
	Reduced: boolean, -- animations réduites (pas de clignotement)
}
export type Updater = (ps: State) -> ()

local MONO = Font.fromEnum(Enum.Font.RobotoMono)
local LAGZ_PINK = Color3.fromHex("E834D6")

-- Écrit un texte seulement s'il change (les fenêtres sont mises à jour 4 fois par seconde).
local function set(label: TextLabel, text: string, color: Color3?)
	if label.Text ~= text then
		label.Text = text
	end
	if color and label.TextColor3 ~= color then
		label.TextColor3 = color
	end
end

local function blink(ps: State, hz: number): boolean
	return not ps.Reduced and math.floor(ps.T * hz) % 2 == 0
end

-- Étiquette calée à droite de son parent (marge `right`), largeur automatique.
local function rightTag(
	parent: Instance,
	text: string,
	right: number,
	y: number,
	h: number,
	size: number,
	color: Color3?,
	background: Color3?
): (Frame, TextLabel)
	local frame, label = Tag(parent, text, 0, y, h, size, color, background)
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -right, 0, y)
	return frame, label
end

local function sectionTitle(parent: Instance, text: string, x: number, y: number, w: number): TextLabel
	return Text(parent, text, x, y, w, 30, 22, { Weight = "Bold" })
end

------------------------------------------------------------------------------------
-- Monde 1 · Alimentation
------------------------------------------------------------------------------------

local PLAN_HINTS =
	{ "Le PC se traîne pour économiser.", "Un peu de tout, sans forcer.", "Tout le jus pour le live d'Anga." }

local function powerPlan(win: Fluent.Window): Updater
	local root = win.Content
	local plans = Card(root, 0, 0, 896, 262)
	sectionTitle(plans, "Mode d'alimentation", 22, 14, 500)
	Text(plans, "Choisi par l'app selon ce que tu fais.", 22, 44, 600, 22, 16, { Color = C.Dim })
	local rows = {}
	for i, name in AppPages.PowerPlans do
		local y = 76 + (i - 1) * 60
		local row = Box(plans, 12, y, 872, 54, C.Card, 6)
		local radio = Box(row, 14, 15, 24, 24, C.Card, 12)
		local ring = Instance.new("UIStroke")
		ring.Color = C.Faint
		ring.Thickness = 2
		ring.Parent = radio
		local dot = Box(radio, 6, 6, 12, 12, C.Text, 6)
		Text(row, name, 54, 4, 420, 26, 19, { Weight = "Medium" })
		Text(row, PLAN_HINTS[i], 54, 28, 520, 20, 15, { Color = C.Dim })
		local tag = rightTag(row, "Actif", 16, 14, 28, 15, C.Text, C.Accent)
		rows[i] = { Row = row, Radio = radio, Ring = ring, Dot = dot, Tag = tag }
	end
	local stops = Card(root, 0, 278, 440, 254)
	sectionTitle(stops, "Arrêts inattendus", 22, 14, 400)
	local stopCount = Text(stops, "12", 22, 56, 400, 100, 86, { Weight = "Heavy" })
	local stopText = Text(stops, "", 22, 160, 400, 60, 17, { Color = C.Dim, Wrap = true })
	local psu = Card(root, 456, 278, 440, 254)
	sectionTitle(psu, "Bloc d'alimentation", 22, 14, 400)
	local psuGlyph, psuGlyphText = Glyph(psu, 22, 66, 34, "!", C.Warn)
	local psuTitle = Text(psu, "", 70, 60, 350, 46, 19, { Weight = "Medium", Wrap = true })
	local efficiency = Text(psu, "", 22, 130, 400, 30, 18, { Color = C.Dim })
	local effBar = Bar(psu, 22, 170, 396, 12, C.Warn)
	return function(ps: State)
		local p = ps.Progress
		local plan = AppPages.PowerPlan(p)
		for i, row in rows do
			local on = i == plan
			row.Row.BackgroundColor3 = if on then C.CardHover else C.Card
			row.Ring.Color = if on then C.Accent else C.Faint
			row.Radio.BackgroundColor3 = if on then C.Accent else C.Card
			row.Dot.Visible = on
			row.Tag.Visible = on
		end
		local stopsLeft = if p.Cleared then 0 else math.max(12 - p.Reached * 2, 2)
		set(stopCount, tostring(stopsLeft), if p.Cleared then C.Good else C.Bad)
		set(
			stopText,
			if p.Cleared
				then "Plus aucun arrêt depuis le nettoyage ✓"
				else "cette semaine · Sparky court-circuite le 12 V"
		)
		Fluent.SetGlyph(psuGlyph, psuGlyphText, if p.Cleared then "✓" else "!", if p.Cleared then C.Good else C.Warn)
		set(
			psuTitle,
			if p.Cleared then "Tension stable, câbles au propre" else "Tension instable : Sparky dans le câble 12 V"
		)
		local eff = math.floor(62 + 30 * p.Fraction + 0.5)
		set(efficiency, `Rendement : {eff} %`)
		SetBar(effBar, eff / 100, if p.Cleared then C.Good else C.Warn)
		if ps.Incident == "Blackout" then
			Fluent.SetOverlay(
				win,
				"Arrêt forcé par le bouton d'alimentation",
				"LAGZ a coupé le courant. Le PC redémarre dans quelques secondes…",
				"!",
				C.Bad
			)
		else
			Fluent.SetOverlay(win, nil)
		end
	end
end

local HISTORY = 60

-- Histogramme : HISTORY barres en bas d'une zone ; renvoie les barres.
local function histogram(parent: Instance, x: number, y: number, w: number, h: number, color: Color3): { Frame }
	local area = Box(parent, x, y, w, h, C.Sunken, 4)
	area.ClipsDescendants = true
	local bars = {}
	for i = 1, HISTORY do
		local bar = Box(area, 0, 0, 0, 0, color)
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new((i - 1) / HISTORY, 1, 1, 0)
		bar.Size = UDim2.new(1 / HISTORY, -2, 0, 0)
		bar.BackgroundTransparency = 0.25
		bars[i] = bar
	end
	return bars
end

local function pushHistory(history: { number }, bars: { Frame }, value: number, max: number, color: Color3)
	table.remove(history, 1)
	table.insert(history, value)
	for i, bar in bars do
		bar.Size = UDim2.new(1 / HISTORY, -2, math.clamp(history[i] / max, 0, 1), 0)
		bar.BackgroundColor3 = color
	end
end

local function watts(win: Fluent.Window): Updater
	local root = win.Content
	local live = Card(root, 0, 0, 896, 300)
	sectionTitle(live, "Consommation en direct", 22, 14, 500)
	local value = Text(live, "0 W", 22, 56, 520, 110, 96, { Weight = "Heavy" })
	local _, status = rightTag(live, "Instable", 22, 20, 32, 17, C.Bad, C.Sunken)
	local gauge = Bar(live, 22, 196, 852, 18, C.Warn)
	Text(live, "0 W", 22, 222, 200, 24, 15, { Color = C.Dim })
	Text(live, `{AppPages.MAX_WATTS} W`, 674, 222, 200, 24, 15, { Color = C.Dim, Align = "Right" })
	local hint = Text(live, "", 22, 252, 852, 30, 17, { Color = C.Dim })
	local graph = Card(root, 0, 316, 896, 216)
	sectionTitle(graph, "Historique · 15 dernières secondes", 22, 12, 600)
	local bars = histogram(graph, 22, 52, 852, 146, C.Accent)
	local history = table.create(HISTORY, 0)
	return function(ps: State)
		local p = ps.Progress
		local blackout = ps.Incident == "Blackout"
		local w = AppPages.Watts(p, ps.T, blackout)
		local level = if blackout then "Bad" elseif p.Cleared then "Good" else "Warn"
		set(value, `{w} W`, if blackout then C.Faint else C.Text)
		set(
			status,
			if blackout then "Coupure !" elseif p.Cleared then "Stable ✓" else "Instable",
			Fluent.Level(level)
		)
		SetBar(gauge, w / AppPages.MAX_WATTS, Fluent.Level(level))
		set(
			hint,
			if blackout
				then "Plus rien n'arrive au PC : attends le retour du courant."
				elseif p.Cleared then "Performances maximales : le PC d'Anga a tout ce qu'il faut."
				else "Des micro-coupures : chaque checkpoint remet un peu de courant."
		)
		pushHistory(history, bars, w, AppPages.MAX_WATTS, if p.Cleared then C.Good else C.AccentSoft)
	end
end

------------------------------------------------------------------------------------
-- Monde 2 · Applications
------------------------------------------------------------------------------------

local IMPACT_COLORS: { [string]: Color3 } =
	{ ["Très élevé"] = C.Bad, ["Élevé"] = C.Warn, Moyen = C.Dim, Faible = C.Good }

local function startup(win: Fluent.Window): Updater
	local root = win.Content
	local head = Card(root, 0, 0, 896, 96)
	local count = Text(head, "", 22, 10, 600, 44, 32, { Weight = "Bold" })
	local boot = Text(head, "", 22, 54, 600, 28, 17, { Color = C.Dim })
	local _, impact = rightTag(head, "", 22, 32, 32, 17, C.Bad, C.Sunken)
	local list = Card(root, 0, 110, 896, 422)
	Text(list, "Nom", 22, 8, 300, 30, 15, { Color = C.Dim })
	Text(list, "Impact", 470, 8, 160, 30, 15, { Color = C.Dim })
	Text(list, "État", 680, 8, 160, 30, 15, { Color = C.Dim })
	local rows = {}
	for i, app in AppPages.StartupApps do
		local y = 40 + (i - 1) * 54
		Box(list, 12, y, 872, 1, C.Stroke)
		local name = Text(list, app.Name, 22, y + 4, 440, 46, 19, { Weight = "Medium" })
		Text(list, app.Impact, 470, y + 4, 200, 46, 17, { Color = IMPACT_COLORS[app.Impact] or C.Dim })
		local toggle = Fluent.Toggle(list, 680, y + 14, 26)
		local label = Text(list, "", 752, y + 4, 130, 46, 16, { Color = C.Dim })
		rows[i] = { Name = name, Toggle = toggle, Label = label }
	end
	return function(ps: State)
		local p = ps.Progress
		set(count, `{AppPages.StartupCount(p)} applis au démarrage`)
		local seconds = AppPages.BootSeconds(p)
		set(
			boot,
			`Windows démarre en {if seconds >= 60 then `{seconds // 60} min {seconds % 60} s` else `{seconds} s`}`
		)
		set(
			impact,
			if p.Cleared then "Impact faible ✓" else "Impact très élevé",
			if p.Cleared then C.Good else C.Bad
		)
		for i, row in rows do
			local on = AppPages.StartupEnabled(p, i)
			Fluent.SetToggle(row.Toggle, on)
			set(row.Label, if on then "Activé" else "Désactivé")
			row.Name.TextColor3 = if on then C.Text else C.Faint
		end
		if ps.Incident == "Popups" then
			Fluent.SetOverlay(
				win,
				"PubPopUp Deluxe s'est relancé tout seul !",
				"Ferme les pubs de LAGZ ; l'app s'occupe du reste.",
				"!",
				C.Warn
			)
		else
			Fluent.SetOverlay(win, nil)
		end
	end
end

local function memory(win: Fluent.Window): Updater
	local root = win.Content
	local top = Card(root, 0, 0, 896, 190)
	sectionTitle(top, "Mémoire vive", 22, 14, 400)
	local used = Text(top, "", 22, 52, 600, 60, 44, { Weight = "Heavy" })
	local _, percent = rightTag(top, "", 22, 20, 32, 17, C.Bad, C.Sunken)
	local fill = Bar(top, 22, 124, 852, 18, C.Bad)
	local hint = Text(top, "", 22, 150, 852, 28, 16, { Color = C.Dim })
	local hogs = Card(root, 0, 206, 896, 326)
	sectionTitle(hogs, "Ce qui mange ta mémoire", 22, 14, 600)
	local rows = {}
	for i = 1, 4 do
		local y = 58 + (i - 1) * 64
		local name = Text(hogs, "", 22, y, 460, 30, 19, { Weight = "Medium" })
		local size = Text(hogs, "", 674, y, 200, 30, 19, { Align = "Right" })
		local bar = Bar(hogs, 22, y + 36, 852, 10, C.AccentSoft)
		rows[i] = { Name = name, Size = size, Bar = bar }
	end
	return function(ps: State)
		local p = ps.Progress
		local gigas = AppPages.MemoryUsed(p)
		local ratio = gigas / AppPages.RAM_TOTAL
		local level = if ratio >= 0.9 then "Bad" elseif ratio >= 0.7 then "Warn" else "Good"
		set(used, `{AppPages.Decimal(gigas)} Go sur {AppPages.RAM_TOTAL} Go`)
		set(percent, `{math.floor(ratio * 100 + 0.5)} % utilisés`, Fluent.Level(level))
		SetBar(fill, ratio, Fluent.Level(level))
		set(
			hint,
			if p.Cleared
				then "La mémoire est libérée : plus d'onglets fantômes ✓"
				else "200 onglets ouverts en arrière-plan : le PC n'a plus de place pour jouer."
		)
		for i, hog in AppPages.MemoryHogs(p) do
			local row = rows[i]
			if row then
				set(row.Name, hog.Name, if hog.Gigas < 0.05 then C.Faint else C.Text)
				set(row.Size, `{AppPages.Decimal(hog.Gigas)} Go`)
				SetBar(row.Bar, hog.Gigas / 9.1, if hog.Name == "Windows" then C.Info else C.AccentSoft)
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Monde 3 · Disques
------------------------------------------------------------------------------------

local function drive(win: Fluent.Window): Updater
	local root = win.Content
	local card = Card(root, 0, 0, 896, 380)
	local icon = Box(card, 20, 20, 50, 50, C.CardHover, 8)
	local slot = Box(icon, 13, 19, 24, 12, C.CardHover, 3)
	local edge = Instance.new("UIStroke")
	edge.Color = C.Dim
	edge.Thickness = 2
	edge.Parent = slot
	Text(card, "C:", 86, 16, 60, 36, 30, { Weight = "Bold" })
	Tag(card, "SSD · NVMe", 140, 22, 28, 15, C.Text, C.Field)
	Tag(card, "Windows", 262, 22, 28, 15, C.Text, C.Field)
	local pill, pillText = rightTag(card, "", 22, 20, 32, 16, C.Text, C.Field)
	Text(card, `SSD NVMe 500 Go · micrologiciel {AppPages.DISK_FIRMWARE}`, 86, 52, 700, 24, 16, { Color = C.Dim })
	local used = Text(card, "", 20, 96, 500, 30, 22, { Weight = "Bold" })
	local free = Text(card, "", 476, 96, 400, 30, 20, { Align = "Right" })
	local fill = Bar(card, 20, 134, 856, 14, C.Warn)
	local total = Text(card, "", 20, 154, 600, 24, 16, { Color = C.Dim })
	local temp
	for i, info in { { "Usure", "0 %" }, { "Température", "" }, { "Système de fichiers", "NTFS" } } do
		local mini = Box(card, 20 + (i - 1) * 226, 192, 212, 78, C.CardHover, 6)
		Text(mini, info[1], 14, 8, 190, 24, 16, { Color = C.Dim })
		local v = Text(mini, info[2], 14, 36, 190, 30, 21, { Weight = "Bold" })
		if i == 2 then
			temp = v
		end
	end
	local warnGlyph, warnGlyphText = Glyph(card, 20, 296, 26, "!", C.Warn)
	local warn = Text(card, "", 58, 288, 818, 70, 17, { Wrap = true })
	local tools = Card(root, 0, 396, 896, 136)
	sectionTitle(tools, "Libérer ou vérifier", 22, 14, 400)
	Text(
		tools,
		"Le nettoyage des fichiers temporaires et la vérification du disque sont sur la page Nettoyage & réparation.",
		22,
		48,
		852,
		40,
		15,
		{ Color = C.Dim, Wrap = true }
	)
	Fluent.Button(tools, "Nettoyage & réparation", 470, 88, 250, 36, "Outline", 16)
	Fluent.Button(tools, "Désinstaller", 732, 88, 142, 36, "Outline", 16)
	return function(ps: State)
		local p = ps.Progress
		local gigas = AppPages.DiskUsed(p)
		local percent = AppPages.DiskPercent(p)
		local status = AppPages.DiskStatus(p)
		local healthy = status == "Sain"
		set(pillText, if healthy then "● Sain ✓" else `● {status}`, if healthy then C.Good else C.Warn)
		pill.BackgroundColor3 = C.Sunken
		set(used, `{AppPages.Decimal(gigas)} Go utilisés`)
		set(free, `{AppPages.Decimal(AppPages.DISK_TOTAL - gigas)} Go libres`)
		SetBar(fill, percent / 100, if percent >= 75 then C.Warn else C.Good)
		set(total, `sur {AppPages.Decimal(AppPages.DISK_TOTAL)} Go · {percent} % occupés`)
		set(temp, `{math.floor(56 - 18 * p.Fraction + 0.5)} °C`)
		Fluent.SetGlyph(
			warnGlyph,
			warnGlyphText,
			if percent >= 75 then "!" else "✓",
			if percent >= 75 then C.Warn else C.Good
		)
		set(
			warn,
			if percent >= 90
				then "Plus de 90 % occupés : un disque aussi plein ralentit. Fais de la place : LAGZ_cache prend presque tout."
				elseif percent >= 75 then "Encore bien plein : continue, chaque checkpoint vide un peu LAGZ_cache."
				else "Assez de place : Windows respire, les jeux chargent vite."
		)
		if ps.Incident == "Corruption" then
			Fluent.SetOverlay(
				win,
				"Secteurs corrompus détectés",
				"Corrupto inverse les dalles ! L'analyse reprend dans un instant.",
				"!",
				C.Bad
			)
		else
			Fluent.SetOverlay(win, nil)
		end
	end
end

local TILE_COLORS: { [string]: Color3 } = {
	LAGZ_cache = Color3.fromHex("7B2CBF"),
	Windows = Color3.fromHex("2F6DB5"),
	Jeux = Color3.fromHex("2E8B57"),
	["Vidéos d'Anga"] = Color3.fromHex("B7791F"),
	Autres = Color3.fromHex("555555"),
	["Espace libre"] = Color3.fromHex("2F2F2F"),
}

local function treemap(win: Fluent.Window): Updater
	local root = win.Content
	local card = Card(root, 0, 0, 896, 532)
	local icon = Box(card, 20, 18, 46, 46, C.CardHover, 8)
	local pie = Box(icon, 11, 11, 24, 24, C.CardHover, 12)
	local pieEdge = Instance.new("UIStroke")
	pieEdge.Color = C.Dim
	pieEdge.Thickness = 2
	pieEdge.Parent = pie
	Box(pie, 11, 1, 2, 11, C.Dim)
	Text(card, "Où part ton espace disque", 80, 14, 520, 34, 26, { Weight = "Bold" })
	Text(
		card,
		"Chaque rectangle est un dossier : plus il pèse, plus il est grand.",
		80,
		48,
		520,
		24,
		15,
		{ Color = C.Dim }
	)
	local drop = Box(card, 612, 22, 110, 38, C.Field, 6)
	Text(drop, "C:", 12, 0, 50, 38, 17)
	Text(drop, "▾", 70, 0, 30, 38, 17, { Color = C.Dim, Align = "Center" })
	local _, analyse = Fluent.Button(card, "Analyser", 734, 22, 142, 38, "Accent", 17)
	local area = Box(card, 20, 88, 856, 424, C.Sunken, 6)
	area.ClipsDescendants = true
	local tiles: { [string]: { Frame: Frame, Name: TextLabel, Size: TextLabel } } = {}
	local lastFraction = -1
	local function layout(p: AppPages.Progress)
		local seen = {}
		for _, tile in AppPages.Treemap(AppPages.DiskShares(p)) do
			seen[tile.Name] = true
			local view = tiles[tile.Name]
			if not view then
				local frame = Box(area, 0, 0, 0, 0, TILE_COLORS[tile.Name] or C.Field, 4)
				local stroke = Instance.new("UIStroke")
				stroke.Color = C.Sunken
				stroke.Thickness = 3
				stroke.Parent = frame
				local name = Text(frame, tile.Name, 10, 6, 400, 24, 18, { Weight = "Bold" })
				local size = Text(frame, "", 10, 30, 400, 22, 15, { Color = C.Dim })
				view = { Frame = frame, Name = name, Size = size }
				tiles[tile.Name] = view
			end
			view.Frame.Visible = true
			view.Frame.Position = UDim2.fromScale(tile.X, tile.Y)
			view.Frame.Size = UDim2.fromScale(tile.W, tile.H)
			local small = tile.W * 856 < 120 or tile.H * 424 < 60
			view.Name.Visible = not small
			view.Size.Visible = not small
			view.Name.Size = UDim2.new(1, -16, 0, 24)
			view.Size.Size = UDim2.new(1, -16, 0, 22)
			set(
				view.Size,
				`{AppPages.Decimal(tile.Share * AppPages.DISK_TOTAL)} Go · {math.floor(tile.Share * 100 + 0.5)} %`
			)
		end
		for name, view in tiles do
			if not seen[name] then
				view.Frame.Visible = false
			end
		end
	end
	return function(ps: State)
		local p = ps.Progress
		if p.Fraction ~= lastFraction then
			lastFraction = p.Fraction
			layout(p)
		end
		set(analyse, if p.Cleared then "Analysé ✓" else "Analyser")
		local lagz = tiles.LAGZ_cache
		if lagz then
			local corrupt = ps.Incident == "Corruption"
			lagz.Frame.BackgroundColor3 = if corrupt and blink(ps, 4)
				then Color3.new(0, 0, 0)
				elseif corrupt then LAGZ_PINK
				else TILE_COLORS.LAGZ_cache
			set(lagz.Name, if corrupt then "LAGZ_cache (corrompu)" else "LAGZ_cache")
		end
	end
end

------------------------------------------------------------------------------------
-- Monde 4 · Diagnostic · Températures
------------------------------------------------------------------------------------

local function temps(win: Fluent.Window): Updater
	local root = win.Content
	sectionTitle(root, "Capteurs", 0, 4, 300)
	Fluent.Button(root, "Analyse express", 440, 0, 190, 40, "Outline", 17)
	Fluent.Button(root, "Analyse complète · 2 min", 642, 0, 254, 40, "Accent", 17)
	local cards = {}
	for i, label in { "Processeur", "Carte graphique" } do
		local card = Card(root, (i - 1) * 456, 56, 440, 300)
		Text(card, label, 22, 14, 300, 30, 22, { Weight = "Medium" })
		local _, word = rightTag(card, "", 22, 16, 30, 16, C.Bad, C.Sunken)
		local value = Text(card, "", 22, 56, 400, 120, 104, { Weight = "Heavy" })
		local bar = Bar(card, 22, 190, 396, 16, C.Bad)
		Text(card, "0 °C", 22, 212, 100, 22, 14, { Color = C.Dim })
		Text(card, "105 °C", 318, 212, 100, 22, 14, { Color = C.Dim, Align = "Right" })
		local fan = Text(card, "", 22, 248, 400, 30, 17, { Color = C.Dim })
		cards[i] = { Value = value, State = word, Bar = bar, Fan = fan }
	end
	local cool = Card(root, 0, 372, 896, 160)
	sectionTitle(cool, "Refroidissement", 22, 14, 400)
	local glyph, glyphText = Glyph(cool, 22, 62, 36, "!", C.Bad)
	local verdict = Text(cool, "", 76, 56, 800, 80, 20, { Wrap = true })
	return function(ps: State)
		local p = ps.Progress
		local overheat = ps.Incident == "Overheat"
		local cpu, gpu = AppPages.Temps(p, overheat)
		for i, celsius in { cpu, gpu } do
			local card = cards[i]
			local word, level = AppPages.TempLabel(celsius)
			local color = if overheat and blink(ps, 3) then C.Text else Fluent.Level(level)
			set(card.Value, `{celsius} °C`, color)
			set(card.State, if p.Cleared then `{word} ✓` else word, Fluent.Level(level))
			SetBar(card.Bar, celsius / 105, Fluent.Level(level))
			set(card.Fan, `Ventilateur : {NumberFormat.Grouped(AppPages.FanRpm(p))} tr/min`)
		end
		local good = p.Cleared
		Fluent.SetGlyph(
			glyph,
			glyphText,
			if good then "✓" else "!",
			if overheat then C.Bad elseif good then C.Good else C.Warn
		)
		set(
			verdict,
			if overheat
				then "ALERTE SURCHAUFFE : LAGZ a tout allumé en même temps !"
				elseif good then "Tout souffle normalement : le PC reste au frais ✓"
				else "Dusty bouche les ventilateurs du radiateur : chaque checkpoint fait baisser la température."
		)
	end
end

local function verdict(win: Fluent.Window): Updater
	local root = win.Content
	local glyph = Glyph(root, 0, 6, 26, "✓", C.Dim)
	glyph.Name = "VerdictGlyph"
	Text(root, "Verdict", 38, 0, 300, 24, 18, { Weight = "Medium" })
	Text(
		root,
		"Analyse express · rapport de ton ascension · 109 points vérifiés",
		38,
		22,
		700,
		20,
		14,
		{ Color = C.Dim }
	)
	local headline = Text(root, "", 0, 52, 896, 80, 27, { Weight = "Bold", Wrap = true })
	local scoreCard = Card(root, 0, 138, 206, 150)
	Text(scoreCard, "Score", 18, 14, 150, 24, 17)
	local score = Text(scoreCard, "", 18, 44, 180, 80, 64, { Weight = "Heavy" })
	local minis = {}
	for i, name in { "Températures", "Ventilation", "Stabilité" } do
		local card = Card(root, 222 + (i - 1) * 226, 138, 210, 150)
		Text(card, name, 18, 14, 180, 24, 17, { Weight = "Medium" })
		local dot = Box(card, 18, 52, 12, 12, C.Bad, 6)
		local value = Text(card, "", 38, 42, 160, 30, 19)
		local detail = Text(card, "", 18, 80, 180, 60, 14, { Color = C.Dim, Wrap = true })
		minis[i] = { Dot = dot, Value = value, Detail = detail }
	end
	Text(root, "Ce qu'il faut regarder", 0, 300, 400, 28, 19, { Weight = "Bold" })
	local issues = {}
	for i, issue in AppPages.DiagnosticIssues do
		local card = Card(root, 0, 336 + (i - 1) * 66, 896, 58)
		local g, gt = Glyph(card, 16, 14, 30, "!", C.Bad)
		local title = Text(card, issue.Title, 60, 0, 560, 58, 19)
		local button, buttonText = Fluent.Button(card, "Remettre d'aplomb", 690, 11, 190, 36, "Accent", 16)
		issues[i] = { Glyph = g, GlyphText = gt, Title = title, Button = button, ButtonText = buttonText }
	end
	return function(ps: State)
		local p = ps.Progress
		local value = AppPages.DiagnosticScore(p)
		set(
			headline,
			if p.Cleared
				then "Tout va bien : le PC respire à nouveau."
				else "Le PC chauffe, et la poussière a bouché les ventilos."
		)
		set(score, `{value}`, if value >= 75 then C.Good elseif value >= 45 then C.Warn else C.Bad)
		local temperatureScore = math.floor(20 + 80 * p.Fraction + 0.5)
		for i, mini in minis do
			local v = if i == 1
				then temperatureScore
				elseif i == 2 then math.floor(10 + 90 * p.Fraction + 0.5)
				else value
			local level = if v >= 75 then "Good" elseif v >= 45 then "Warn" else "Bad"
			mini.Dot.BackgroundColor3 = Fluent.Level(level)
			set(mini.Value, `{v} / 100`)
			set(
				mini.Detail,
				if i == 1
					then `CPU {(AppPages.Temps(p, false))} °C sous charge`
					elseif i == 2 then `{NumberFormat.Grouped(AppPages.FanRpm(p))} tr/min`
					elseif p.Cleared then "Aucun souci"
					else "Dusty dans le radiateur"
			)
		end
		local firstOpen = true
		for i, row in issues do
			local fixed = AppPages.IssueFixed(p, i)
			Fluent.SetGlyph(row.Glyph, row.GlyphText, if fixed then "✓" else "!", if fixed then C.Good else C.Bad)
			row.Title.TextColor3 = if fixed then C.Faint else C.Text
			row.Button.Visible = not fixed
			if not fixed then
				row.Button.BackgroundColor3 = if firstOpen then C.Accent else C.Field
				firstOpen = false
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Monde 5 · Test de perf
------------------------------------------------------------------------------------

local GRAPH_MAX = 160

local function fpsGraph(win: Fluent.Window): Updater
	local root = win.Content
	local card = Card(root, 0, 0, 896, 532)
	sectionTitle(card, "Images par seconde · en direct", 22, 14, 600)
	local value = Text(card, "", 22, 48, 500, 80, 72, { Weight = "Heavy" })
	local _, goal = rightTag(card, `Objectif {AppPages.FPS_GOAL} FPS`, 22, 22, 32, 16, C.Text, C.Sunken)
	local lagTag = rightTag(card, "LAG SPIKE", 22, 66, 32, 16, C.Bad, C.Sunken)
	local bars = histogram(card, 22, 140, 852, 320, C.Good)
	-- Ligne de l'objectif (144 FPS)
	local line = Box(card, 22, 140 + math.floor(320 * (1 - AppPages.FPS_GOAL / GRAPH_MAX)), 852, 2, C.AccentSoft)
	line.BackgroundTransparency = 0.2
	Text(card, "144", 830, line.Position.Y.Offset - 22, 44, 20, 14, { Color = C.AccentSoft, Align = "Right" })
	local footer = Text(card, "", 22, 470, 852, 40, 17, { Color = C.Dim })
	local history = table.create(HISTORY, 0)
	return function(ps: State)
		local p = ps.Progress
		local lag = ps.Incident == "Lag"
		local fps = AppPages.FpsSample(p, ps.T, lag)
		local level = PcHealth.Grade("Fps", fps)
		set(value, `{fps} FPS`, Fluent.Level(level))
		goal.TextColor3 = if p.Cleared then C.Good else C.Text
		lagTag.Visible = lag
		pushHistory(history, bars, fps, GRAPH_MAX, Fluent.Level(level))
		local sum, low = 0, math.huge
		for _, v in history do
			sum += v
			low = math.min(low, v)
		end
		set(
			footer,
			`Moyenne : {math.floor(sum / #history + 0.5)} FPS  ·  1 % bas : {low} FPS  ·  {if p.Cleared
				then "fluide ✓"
				else "Minor fait tourner son crypto-mineur"}`
		)
	end
end

local function perfScore(win: Fluent.Window): Updater
	local root = win.Content
	local card = Card(root, 0, 0, 896, 250)
	sectionTitle(card, "Résultat du test", 22, 14, 400)
	local score = Text(card, "", 22, 50, 400, 90, 80, { Weight = "Heavy" })
	Text(card, "points", 22, 140, 200, 24, 17, { Color = C.Dim })
	local compare = {}
	for i, name in { "Ton PC", "PC gamer moyen", "Objectif du live" } do
		local y = 40 + (i - 1) * 64
		Text(card, name, 440, y, 250, 26, 17, { Weight = if i == 1 then "Bold" else "Regular" })
		local number = Text(card, "", 690, y, 184, 26, 17, { Align = "Right", Color = C.Dim })
		local bar = Bar(card, 440, y + 30, 434, 12, if i == 1 then C.Accent else C.Faint)
		compare[i] = { Number = number, Bar = bar }
	end
	local cpu = Card(root, 0, 266, 440, 266)
	local gpu = Card(root, 456, 266, 440, 266)
	local rows = {}
	local titles = { "Processeur", "Carte graphique" }
	for i, parent in { cpu, gpu } do
		sectionTitle(parent, titles[i], 22, 14, 400)
		local load = Text(parent, "", 22, 56, 400, 70, 60, { Weight = "Heavy" })
		local bar = Bar(parent, 22, 140, 396, 14, C.Bad)
		local hint = Text(parent, "", 22, 170, 396, 70, 17, { Color = C.Dim, Wrap = true })
		rows[i] = { Load = load, Bar = bar, Hint = hint }
	end
	return function(ps: State)
		local p = ps.Progress
		local value = AppPages.PerfScore(p)
		set(score, NumberFormat.Grouped(value), if p.Cleared then C.Good else C.Text)
		for i, target in { value, 9800, 14400 } do
			set(compare[i].Number, NumberFormat.Grouped(target))
			SetBar(compare[i].Bar, target / 14400)
		end
		local cpuLoad = math.floor(100 - 88 * p.Fraction + 0.5)
		local gpuLoad = math.floor(35 + 50 * p.Fraction + 0.5)
		set(rows[1].Load, `{cpuLoad} %`, if cpuLoad >= 90 then C.Bad elseif cpuLoad >= 60 then C.Warn else C.Good)
		SetBar(rows[1].Bar, cpuLoad / 100, if cpuLoad >= 90 then C.Bad elseif cpuLoad >= 60 then C.Warn else C.Good)
		set(
			rows[1].Hint,
			if p.Cleared
				then "Le mineur est parti : le processeur souffle ✓"
				else "Le crypto-mineur de Minor lui vole du calcul !"
		)
		set(rows[2].Load, `{gpuLoad} %`, C.Good)
		SetBar(rows[2].Bar, gpuLoad / 100, C.Good)
		set(
			rows[2].Hint,
			if p.Cleared then "La carte graphique travaille enfin pour le jeu." else "Elle attend le processeur…"
		)
	end
end

-- Bandeau « Lancer le test » (sans fenêtre : canevas 1200 × 360).
function Pages.BuildBanner(root: GuiObject, width: number, height: number): Updater
	local frame = Box(root, 0, 0, width, height, C.Bg, 18)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Stroke
	stroke.Thickness = 3
	stroke.Parent = frame
	local logo = Box(frame, 40, math.floor(height / 2) - 70, 140, 140, C.Accent, 28)
	Text(logo, "A", 0, 0, 140, 140, 96, { Weight = "Heavy", Align = "Center" })
	Text(frame, "Test de perf", 220, math.floor(height / 2) - 80, 520, 80, 64, { Weight = "Bold" })
	Text(frame, "Combien d'images par seconde ton PC tient vraiment.", 220, math.floor(height / 2) + 6, 520, 60, 24, {
		Color = C.Dim,
		Wrap = true,
	})
	local button, label = Fluent.Button(frame, "", width - 420, math.floor(height / 2) - 64, 380, 100, "Accent", 36)
	local bar = Bar(frame, width - 420, math.floor(height / 2) + 58, 380, 14, C.AccentSoft)
	return function(ps: State)
		local phase, percent = AppPages.PerfTest(ps.Progress)
		if phase == "Done" then
			set(label, `Terminé · {AppPages.FPS_GOAL} FPS ✓`)
			button.BackgroundColor3 = Color3.fromHex("2E7D32")
		elseif phase == "Running" then
			set(label, `Test en cours · {percent} %`)
			button.BackgroundColor3 = C.Accent
		else
			set(label, "▶  Lancer le test")
			button.BackgroundColor3 = if blink(ps, 1) then C.Accent else C.AccentSoft
		end
		SetBar(bar, percent / 100, if phase == "Done" then C.Good else C.AccentSoft)
	end
end

------------------------------------------------------------------------------------
-- Monde 6 · Pilotes GPU
------------------------------------------------------------------------------------

local function driver(win: Fluent.Window): Updater
	local root = win.Content
	local head = Card(root, 0, 0, 896, 74)
	-- Carte fictive de l'univers AngAInOne : puce à l'accent violet de l'app (Branding.PartnerApp).
	local chip = Box(head, 14, 12, 50, 50, C.Accent, 8)
	Text(chip, "GPU", 0, 0, 50, 50, 15, { Weight = "Heavy", Align = "Center", Color = C.Text })
	Text(head, AppPages.GPU_NAME, 78, 10, 420, 28, 19, { Weight = "Medium" })
	local current = Text(head, "", 78, 38, 420, 24, 15, { Color = C.Dim })
	Tag(head, "GPU", 510, 22, 30, 15, C.Text, C.Field)
	Fluent.Button(head, "Ce n'est pas ma carte", 640, 19, 240, 36, "Outline", 17)
	local step = Card(root, 0, 88, 896, 340)
	Text(step, "↓", 18, 12, 30, 40, 26, { Color = C.Dim, Align = "Center" })
	local stepTitle = Text(step, "", 58, 10, 600, 28, 20, { Weight = "Medium" })
	Text(step, "Carte graphique, mode et version du pilote.", 58, 36, 600, 22, 15, { Color = C.Dim })
	local _, badge = rightTag(step, "En cours", 22, 18, 30, 15, C.Text, C.Field)
	Box(step, 0, 70, 896, 1, C.Stroke)
	Text(step, "Mode d'installation", 26, 84, 400, 26, 17)
	local mode = Box(step, 26, 114, 844, 40, C.Field, 6)
	Text(mode, "Nettoyage complet", 14, 0, 500, 40, 17)
	Text(mode, "▾", 800, 0, 30, 40, 17, { Color = C.Dim, Align = "Center" })
	Text(step, "Version du pilote", 26, 170, 400, 26, 17)
	local version = Box(step, 26, 200, 570, 40, C.Field, 6)
	Text(version, AppPages.DRIVER_NEW, 14, 0, 300, 40, 17)
	Text(version, "▾", 530, 0, 30, 40, 17, { Color = C.Dim, Align = "Center" })
	Fluent.Button(step, "↓  Télécharger et extraire", 610, 200, 260, 40, "Accent", 17)
	local fill = Bar(step, 26, 262, 844, 12, C.AccentSoft)
	local progress = Text(step, "", 26, 282, 600, 26, 16, { Color = C.Dim })
	local percent = Text(step, "", 670, 282, 200, 26, 16, { Align = "Right" })
	local log = Card(root, 0, 442, 896, 90)
	Text(log, "≡", 18, 18, 30, 40, 26, { Color = C.Dim, Align = "Center" })
	Text(log, "Journal d'opération", 58, 14, 600, 28, 19, { Weight = "Medium" })
	Text(
		log,
		"Le détail technique de chaque étape — s'ouvre tout seul en cas de problème",
		58,
		44,
		780,
		24,
		15,
		{ Color = C.Dim }
	)
	return function(ps: State)
		local p = ps.Progress
		local index = AppPages.DriverStep(p)
		local pct = AppPages.DriverPercent(p)
		set(current, `Pilote actuel : {if p.Cleared then AppPages.DRIVER_NEW else AppPages.DRIVER_OLD}`)
		set(
			stepTitle,
			if index >= 4
				then `Pilote {AppPages.DRIVER_NEW} installé ✓`
				else `Étape {index} — {AppPages.DriverSteps[index]}`
		)
		set(badge, if index >= 4 then "Terminé" else "En cours", if index >= 4 then C.Good else C.Text)
		SetBar(fill, pct / 100, if p.Cleared then C.Good else C.AccentSoft)
		set(
			progress,
			if p.Cleared
				then "Installation terminée"
				elseif index >= 2 then "Téléchargement et extraction…"
				else "Prêt à télécharger"
		)
		set(percent, `{pct} %`)
		if ps.Incident == "Freeze" then
			Fluent.SetOverlay(
				win,
				"Pilotes GPU (Ne répond pas)",
				"Freezy a figé la fenêtre. Elle se débloque dans quelques secondes…",
				"!",
				C.Info
			)
		else
			Fluent.SetOverlay(win, nil)
		end
	end
end

local function driverLog(win: Fluent.Window): Updater
	local root = win.Content
	local card = Card(root, 0, 0, 896, 420)
	sectionTitle(card, "Journal d'opération", 22, 14, 600)
	Text(card, "Le détail technique de chaque étape", 22, 44, 600, 22, 15, { Color = C.Dim })
	local lines = {}
	for i, line in AppPages.DriverLog do
		local y = 84 + (i - 1) * 54
		local g, gt = Glyph(card, 22, y + 8, 30, "·", C.Faint)
		local label = Text(card, line, 68, y, 800, 46, 18)
		label.FontFace = MONO
		lines[i] = { Glyph = g, GlyphText = gt, Label = label }
	end
	local tweaks = Card(root, 0, 436, 896, 96)
	Text(tweaks, "Réglages 3D", 22, 16, 400, 28, 19, { Weight = "Medium" })
	Text(tweaks, "Mode actif : Réactif · Profil jeu : —", 22, 48, 500, 24, 15, { Color = C.Dim })
	Fluent.Button(tweaks, "→  Ouvrir les réglages 3D", 620, 28, 256, 40, "Outline", 16)
	return function(ps: State)
		local shown = AppPages.DriverLogLines(ps.Progress)
		for i, line in lines do
			local done = i < shown or (i == shown and ps.Progress.Cleared)
			local current = i == shown and not ps.Progress.Cleared
			local glyph = if done then "✓" elseif current then "…" else "·"
			local color = if done then C.Good elseif current then C.AccentSoft else C.Faint
			Fluent.SetGlyph(line.Glyph, line.GlyphText, glyph, color)
			line.Label.TextColor3 = if i <= shown then C.Text else C.Faint
			line.Label.TextTransparency = if i <= shown then 0 else 0.5
		end
	end
end

------------------------------------------------------------------------------------
-- Monde 7 · Plantages
------------------------------------------------------------------------------------

local function crashes(win: Fluent.Window): Updater
	local root = win.Content
	local rows = {}
	local count = #AppPages.Crashes + 1
	local rowH = math.floor((532 - (count - 1) * 8) / count)
	for i = 1, count do
		local card = Card(root, 0, (i - 1) * (rowH + 8), 896, rowH)
		local g, gt = Glyph(card, 18, math.floor(rowH / 2) - 14, 28, "i", C.Faint)
		local title = Text(card, "", 64, 6, 640, math.floor(rowH / 2), 19)
		local detail = Text(card, "", 64, math.floor(rowH / 2), 640, math.floor(rowH / 2) - 6, 15, { Color = C.Dim })
		local tag, tagText = rightTag(card, "Réglé ✓", 22, math.floor(rowH / 2) - 15, 30, 15, C.Good, C.Sunken)
		rows[i] = { Glyph = g, GlyphText = gt, Title = title, Detail = detail, Tag = tag, TagText = tagText }
	end
	return function(ps: State)
		local p = ps.Progress
		-- 1re ligne : le joueur lui-même (ses plantages de la session, Controllers/CrashLog)
		local me = rows[1]
		local log = ps.Crash
		if log.Total > 0 then
			local top = CrashLogic.TopCause(log)
			Fluent.SetGlyph(me.Glyph, me.GlyphText, "!", C.Bad)
			set(me.Title, `{ps.Exe} s'est fermé tout seul`)
			set(me.Detail, `{log.Total} fois cette session · surtout : {CrashLogic.CauseLabel(top)}`)
			me.Tag.Visible = false
		else
			Fluent.SetGlyph(me.Glyph, me.GlyphText, "✓", C.Good)
			set(me.Title, `{ps.Exe} tient bon`)
			set(me.Detail, "Aucun plantage cette session")
			me.Tag.Visible = false
		end
		local fixed = AppPages.CrashesFixed(p)
		local total = #AppPages.Crashes
		for i, crash in AppPages.Crashes do
			local row = rows[i + 1]
			local done = i > total - fixed
			set(row.Title, crash.Title, if done then C.Faint else C.Text)
			set(row.Detail, crash.Detail)
			Fluent.SetGlyph(row.Glyph, row.GlyphText, if done then "✓" else "i", if done then C.Good else C.Faint)
			row.Tag.Visible = done
		end
	end
end

local function crashAlert(win: Fluent.Window): Updater
	local root = win.Content
	local alert = Card(root, 0, 0, 896, 120)
	local g, gt = Glyph(alert, 22, 22, 36, "!", C.Bad)
	local title = Text(alert, "", 76, 14, 800, 32, 22, { Weight = "Bold" })
	local text = Text(alert, "", 76, 46, 800, 28, 17)
	Text(
		alert,
		"Le journal remonte à 93 jours. Les incidents plus anciens sont conservés par l'app.",
		76,
		78,
		800,
		26,
		14,
		{ Color = C.Dim }
	)
	local detail = Card(root, 0, 136, 896, 396)
	local dg, dgt = Glyph(detail, 22, 24, 30, "!", C.Bad)
	local dTitle = Text(detail, "", 70, 16, 780, 28, 20, { Weight = "Medium" })
	local dSub = Text(detail, "", 70, 44, 780, 24, 15, { Color = C.Dim })
	Box(detail, 0, 84, 896, 1, C.Stroke)
	local body = Text(detail, "", 22, 98, 852, 56, 18, { Wrap = true })
	Text(detail, "Quoi faire", 22, 160, 400, 28, 19, { Weight = "Bold" })
	local todo = Text(detail, "", 22, 190, 852, 56, 18, { Wrap = true })
	local button, buttonText = Fluent.Button(detail, "Remettre d'aplomb", 22, 250, 230, 42, "Accent", 18)
	Text(detail, "Mondes nettoyés", 22, 314, 400, 26, 16, { Color = C.Dim })
	local worlds = Text(detail, "", 674, 314, 200, 26, 16, { Align = "Right" })
	local fill = Bar(detail, 22, 346, 852, 14, C.AccentSoft)
	return function(ps: State)
		local p = ps.Progress
		local done = p.Cleared
		Fluent.SetGlyph(g, gt, if done then "✓" else "!", if done then C.Good else C.Bad)
		set(
			title,
			if done then "Plus aucun plantage depuis le départ de LAGZ" else "Un virus montre des signes d'activité"
		)
		set(
			text,
			if done
				then "Le PC tourne à 144 FPS : le live peut commencer !"
				else "Arrête-le avant tout le reste. Le détail est plus bas."
		)
		Fluent.SetGlyph(dg, dgt, if done then "✓" else "!", if done then C.Good else C.Bad)
		set(dTitle, if done then "LAGZ.exe a été supprimé" else "LAGZ.exe s'est figé 19 fois")
		set(
			dSub,
			if done
				then "Plus aucune trace dans les 7 mondes"
				else "19 fois — dernière il y a 2 minutes, dans la puce IA"
		)
		set(
			body,
			if done
				then "Tous les composants sont nettoyés : alimentation, mémoire, disque, refroidissement, processeur, carte graphique."
				else "LAGZ se cache dans la puce IA et fait planter tout le reste. Ce sont les signes d'un virus bien installé."
		)
		set(
			todo,
			if done
				then "Rien : profite du live d'Anga. Tu peux refaire l'ascension pour battre ton record."
				else "Monte jusqu'à son cœur et réussis le terminal antivirus : l'app remet tout d'aplomb."
		)
		button.BackgroundColor3 = if done then Color3.fromHex("2E7D32") else C.Accent
		set(buttonText, if done then "Remis d'aplomb ✓" else "Remettre d'aplomb")
		local cleared = math.clamp(ps.Cleared, 0, Tower.WORLD_COUNT)
		set(worlds, `{cleared} / {Tower.WORLD_COUNT}`)
		SetBar(fill, cleared / Tower.WORLD_COUNT, if cleared >= Tower.WORLD_COUNT then C.Good else C.AccentSoft)
	end
end

------------------------------------------------------------------------------------

local BUILDERS: { [string]: (win: Fluent.Window) -> Updater } = {
	PowerPlan = powerPlan,
	Watts = watts,
	Startup = startup,
	Memory = memory,
	Drive = drive,
	Treemap = treemap,
	Temps = temps,
	Verdict = verdict,
	FpsGraph = fpsGraph,
	PerfScore = perfScore,
	Driver = driver,
	DriverLog = driverLog,
	Crashes = crashes,
	CrashAlert = crashAlert,
}

function Pages.Has(kind: string): boolean
	return BUILDERS[kind] ~= nil or kind == "LaunchBanner"
end

function Pages.Build(kind: string, win: Fluent.Window): Updater?
	local builder = BUILDERS[kind]
	return if builder then builder(win) else nil
end

return table.freeze(Pages)
