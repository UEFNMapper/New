--!strict
--[[
	Traps/TabRain : « pluie d'onglets » (monde 2). La racine n'est qu'un repère : la ZONE est une
	boîte centrée sur elle (attribut Size, Vector3 ; défaut = taille de la pièce), orientée comme elle.

	Toutes les Period secondes, un onglet de navigateur (TabSize, défaut 8 × 0,6 × 6) naît en haut de
	la zone, au-dessus d'une case de la grille (cases de TabSize + 1 stud ; ordre mélangé mais fixe,
	identique pour tous) :
	  1. ouverture 0,5 s en haut (fondu) ; une ombre rouge apparaît au sol, sur sa case ;
	  2. chute (Fall s, défaut 1,2, min 0,8) : MORTEL, barre de titre rouge, l'ombre fonce ;
	  3. posé en bas de la zone : PLATEFORME SÛRE (barre bleue) pendant Stay s (défaut 3) ;
	     clignote pendant ses 0,8 dernières secondes ;
	  4. se ferme (fondu 0,3 s) et disparaît.
	Préavis avant l'impact : 0,5 + Fall ≥ 1,3 s (ombre au sol). Pour que deux onglets ne tombent
	jamais sur la même case en même temps : cases ≥ (0,5 + Fall + Stay + 0,3) / Period + 1.
]]

local Common = require(script.Parent.Common)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler
type Piece = Common.Piece

local TabRain = {}

local OPEN, CLOSE = 0.5, 0.3
TabRain.NONE, TabRain.OPEN, TabRain.FALL, TabRain.REST, TabRain.CLOSE = 0, 1, 2, 3, 4

local TITLES = {
	"Nouvel onglet",
	"AngaTV - LIVE",
	"GAGNE UN PC !!!",
	"Mise à jour (37)",
	"Téléchargement...",
	"Cookies ?",
	"Tuto : anti-lag",
	"Recette de crêpes",
	"999 notifications",
	"Pop-Up.exe",
}
local DANGER = Color3.fromRGB(240, 86, 91)
local SAFE = Color3.fromRGB(91, 140, 255)
local PAGE = Color3.fromRGB(246, 247, 251)
local INK = Color3.fromRGB(214, 219, 229)

type TabData = {
	Zone: Vector3,
	Tab: Vector3,
	Stay: number,
	Fall: number,
	Life: number,
	Count: number,
	Cols: number,
	Rows: number,
	Perm: { number },
	Bodies: { Piece },
	Shadows: { Piece },
	Guis: { SurfaceGui },
	Bars: { Frame },
	Titles: { TextLabel },
	Shown: { number }, -- onglet affiché par chaque pièce du stock
	BaseN: { number }, -- onglet dont la case est en cache (par pièce du stock)
	Bases: { CFrame },
	ShadowN: { number }, -- onglet dont l'ombre est posée
	GuiOn: { boolean },
	Danger: { boolean },
}

local function setup(trap: Trap)
	local part = trap.Part
	local zone = Common.Vec(part, "Size", part.Size)
	local tab = Common.Vec(part, "TabSize", Vector3.new(8, 0.6, 6))
	trap.Period = math.max(Common.Num(part, "Period", 1.5), 0.3)
	local stay = math.max(Common.Num(part, "Stay", 3), 0.5)
	local fall = math.max(Common.Num(part, "Fall", 1.2), Common.TELEGRAPH)
	local life = OPEN + fall + stay + CLOSE
	local cols = math.max(1, math.floor(zone.X / (tab.X + 1)))
	local rows = math.max(1, math.floor(zone.Z / (tab.Z + 1)))
	-- Ordre des cases : mélange fixe (Fisher-Yates déterministe)
	local perm = {}
	for i = 1, cols * rows do
		perm[i] = i - 1
	end
	for i = #perm, 2, -1 do
		local j = math.floor(Common.Hash01(trap.Seed, i) * i) + 1
		perm[i], perm[j] = perm[j], perm[i]
	end
	trap.Data = {
		Zone = zone,
		Tab = tab,
		Stay = stay,
		Fall = fall,
		Life = life,
		Count = math.ceil(life / trap.Period) + 1,
		Cols = cols,
		Rows = rows,
		Perm = perm,
		Bodies = {},
		Shadows = {},
		Guis = {},
		Bars = {},
		Titles = {},
		Shown = {},
		BaseN = {},
		Bases = {},
		ShadowN = {},
		GuiOn = {},
		Danger = {},
	} :: TabData
	trap.Radius = math.max(trap.Radius, zone.Magnitude / 2)
end

-- Repère de la case de l'onglet n au niveau du centre de la zone (petite rotation comprise),
-- mis en cache par pièce du stock : calculé une fois par onglet.
local function baseOf(trap: Trap, n: number): CFrame
	local d = trap.Data :: TabData
	local i = n % d.Count + 1
	if d.BaseN[i] ~= n then
		local slot = d.Perm[n % #d.Perm + 1]
		local col, row = slot % d.Cols, math.floor(slot / d.Cols)
		local x = -d.Zone.X / 2 + (col + 0.5) * d.Zone.X / d.Cols
		local z = -d.Zone.Z / 2 + (row + 0.5) * d.Zone.Z / d.Rows
		local yaw = (Common.Hash01(trap.Seed + 7, n) - 0.5) * 0.3
		d.BaseN[i] = n
		d.Bases[i] = trap.Rest * CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	end
	return d.Bases[i]
end

-- État de l'onglet n à l'instant t : phase, repère, avancement (0..1) dans la phase.
function TabRain.TabAt(trap: Trap, n: number, t: number): (number, CFrame, number)
	local d = trap.Data :: TabData
	local age = t - (n - trap.Phase) * trap.Period
	if age < 0 or age >= d.Life then
		return TabRain.NONE, trap.Rest, 0
	end
	local base = baseOf(trap, n)
	local top = d.Zone.Y / 2 - d.Tab.Y / 2
	local bottom = -d.Zone.Y / 2 + d.Tab.Y / 2
	if age < OPEN then
		return TabRain.OPEN, base * CFrame.new(0, top, 0), age / OPEN
	elseif age < OPEN + d.Fall then
		local progress = (age - OPEN) / d.Fall
		local y = top - (top - bottom) * progress * progress
		local roll = math.sin(progress * math.pi * 3) * 0.12 * (1 - progress)
		return TabRain.FALL, base * CFrame.new(0, y, 0) * CFrame.Angles(roll, 0, 0), progress
	elseif age < OPEN + d.Fall + d.Stay then
		return TabRain.REST, base * CFrame.new(0, bottom, 0), (age - OPEN - d.Fall) / d.Stay
	end
	return TabRain.CLOSE, base * CFrame.new(0, bottom, 0), (age - OPEN - d.Fall - d.Stay) / CLOSE
end

-- Premier et dernier onglet possiblement vivants à l'instant t.
function TabRain.Alive(trap: Trap, t: number): (number, number)
	local last = math.floor(t / trap.Period + trap.Phase)
	return last - (trap.Data :: TabData).Count + 1, last
end

local function hits(trap: Trap, f: Ctx, feet: Vector3): boolean
	local d = trap.Data :: TabData
	local first, last = TabRain.Alive(trap, f.T)
	for n = first, last do
		local phase, cf = TabRain.TabAt(trap, n, f.T)
		if phase == TabRain.FALL and Common.BodyTouchesBox(cf, d.Tab, feet) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------
-- Habillage : onglets de navigateur (page + barre de titre + ✕) et ombres d'impact
------------------------------------------------------------------------------------

local function build(trap: Trap, _f: Ctx)
	local d = trap.Data :: TabData
	local rig = Common.RigOf(trap)
	Common.HideRoot(trap)
	local shadowSize = Vector3.new(d.Tab.X, 0.12, d.Tab.Z)
	for i = 1, d.Count do
		local body = Common.NewPart("Part", rig, d.Tab, trap.Rest, PAGE, Enum.Material.SmoothPlastic, 1)
		body.Name = `Tab{i}`
		Common.Platform(body)
		local gui = Common.Make("SurfaceGui", {
			Face = Enum.NormalId.Top,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 24,
			LightInfluence = 0.2,
			MaxDistance = 250,
			Enabled = false,
		}, body) :: SurfaceGui
		local bar = Common.Make("Frame", {
			Name = "TitleBar",
			BorderSizePixel = 0,
			BackgroundColor3 = DANGER,
			Size = UDim2.fromScale(1, 0.2),
		}, gui) :: Frame
		local title = Common.Make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.05, 0.1),
			Size = UDim2.fromScale(0.72, 0.8),
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = TITLES[1],
		}, bar) :: TextLabel
		Common.Make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.84, 0.05),
			Size = UDim2.fromScale(0.12, 0.9),
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = true,
			Text = "X",
		}, bar)
		-- Page : barre d'adresse, image, lignes de texte
		local blocks = {
			{ X = 0.05, Y = 0.27, W = 0.9, H = 0.09, Color = INK },
			{ X = 0.05, Y = 0.43, W = 0.38, H = 0.47, Color = Color3.fromRGB(159, 122, 234) },
			{ X = 0.5, Y = 0.45, W = 0.45, H = 0.07, Color = INK },
			{ X = 0.5, Y = 0.6, W = 0.4, H = 0.07, Color = INK },
			{ X = 0.5, Y = 0.75, W = 0.3, H = 0.07, Color = INK },
		}
		for _, b in blocks do
			Common.Make("Frame", {
				BorderSizePixel = 0,
				Position = UDim2.fromScale(b.X, b.Y),
				Size = UDim2.fromScale(b.W, b.H),
				BackgroundColor3 = b.Color,
			}, gui)
		end
		local shadow = Common.NewPart("Part", rig, shadowSize, trap.Rest, DANGER, Enum.Material.Neon, 1)
		shadow.Name = `Shadow{i}`
		d.Bodies[i] = Common.AddPiece(trap, body, d.Tab, trap.Rest, false)
		d.Shadows[i] = Common.AddPiece(trap, shadow, shadowSize, trap.Rest, false)
		d.Guis[i] = gui
		d.Bars[i] = bar
		d.Titles[i] = title
		d.Shown[i] = -math.huge
		d.Danger[i] = true
	end
end

local function update(trap: Trap, f: Ctx)
	local d = trap.Data :: TabData
	if #d.Bodies == 0 then
		return
	end
	local first, last = TabRain.Alive(trap, f.T)
	for n = first, last do
		local i = n % d.Count + 1
		local body, shadow = d.Bodies[i], d.Shadows[i]
		if d.Shown[i] ~= n then
			d.Shown[i] = n
			d.Titles[i].Text = TITLES[math.floor(Common.Hash01(trap.Seed + 3, n) * #TITLES) + 1]
		end
		local phase, cf, progress = TabRain.TabAt(trap, n, f.T)
		if phase == TabRain.NONE and body.Alpha == 1 and shadow.Alpha == 1 then
			continue
		end
		local alpha, collide, danger = 1, false, true
		if phase == TabRain.OPEN then
			alpha = 1 - progress
			Common.Cue(trap, "Warn", n)
		elseif phase == TabRain.FALL then
			alpha = 0
		elseif phase == TabRain.REST then
			Common.Cue(trap, "Land", n)
			collide, danger = true, false
			local left = (1 - progress) * d.Stay
			alpha = if left < Common.TELEGRAPH and not Common.Blink(f.T, 5, f.Reduced) then 0.5 else 0
		elseif phase == TabRain.CLOSE then
			alpha, danger = progress, false
		end
		if phase ~= TabRain.NONE then
			body.Next = cf
		end
		Common.SetAlpha(body, alpha)
		Common.SetCollide(body, collide)
		local showGui = alpha < 0.6
		if d.GuiOn[i] ~= showGui then
			d.GuiOn[i] = showGui
			d.Guis[i].Enabled = showGui
		end
		if d.Danger[i] ~= danger then
			d.Danger[i] = danger
			d.Bars[i].BackgroundColor3 = if danger then DANGER else SAFE
		end
		-- Ombre d'impact : de plus en plus nette jusqu'à l'impact
		if phase == TabRain.OPEN or phase == TabRain.FALL then
			if d.ShadowN[i] ~= n then
				d.ShadowN[i] = n
				shadow.Next = baseOf(trap, n) * CFrame.new(0, -d.Zone.Y / 2 + 0.06, 0)
			end
			Common.SetAlpha(shadow, if phase == TabRain.OPEN then 0.85 else 0.8 - 0.5 * progress)
		else
			Common.SetAlpha(shadow, 1)
		end
	end
end

TabRain.Handlers = {
	TabRain = { Lethal = true, Setup = setup, Build = build, Update = update, Hits = hits },
} :: { [string]: Handler }

return TabRain
