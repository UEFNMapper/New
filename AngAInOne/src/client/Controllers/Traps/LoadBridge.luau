--!strict
--[[
	Traps/LoadBridge : « pont de chargement » (monde 6). La racine est le cadre de la barre de
	progression (rendu translucide et traversable ici) ; le client la remplit de Segments segments
	(défaut 8, de 2 à 24) le long de son plus grand côté horizontal, dans le sens de Direction
	(optionnel ; défaut +X local, ou +Z si plus long).

	Cycle de Period s (défaut 8, min 3) :
	  0–55 %   remplissage régulier… avec un BLOCAGE (≈ 30 % du remplissage) à une position tirée
	           au sort à chaque cycle (35–75 %, identique pour tous) : barre orange « Ne répond pas » ;
	  55–90 %  plein (vert) ; clignote pendant au moins 0,8 s avant la fin ;
	  90–100 % vide (réinitialisation), on tombe si on est encore dessus.
	Un segment n'est solide qu'une fois plein. Offset optionnel : le pont fait aussi des
	allers-retours (comme Mover) et transporte le personnage.
]]

local Common = require(script.Parent.Common)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler
type Piece = Common.Piece

local LoadBridge = {}

local FILL_END, EMPTY_START = 0.55, 0.9
local STALL = 0.3 -- fraction du remplissage passée bloquée
LoadBridge.FILL, LoadBridge.STALL, LoadBridge.FULL, LoadBridge.WARN, LoadBridge.EMPTY = 1, 2, 3, 4, 5

local GREEN = Color3.fromRGB(72, 187, 120)
local AMBER = Color3.fromRGB(246, 173, 85)
local WHITE = Color3.new(1, 1, 1)

type BridgeData = {
	Segments: number,
	Axis: Vector3, -- axe local (signé) du remplissage
	Length: number,
	Width: number,
	Thick: number,
	Cells: { Piece },
	Fill: { number }, -- remplissage affiché par segment
	WasFull: { boolean },
	Label: TextLabel?,
	Anchor: Piece?,
	Text: string,
}

local function setup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 8), 3)
	local size = part.Size
	local alongX = size.X >= size.Z
	local axis = if alongX then Vector3.xAxis else Vector3.zAxis
	if trap.Direction.Magnitude > 0 and trap.Rest:VectorToWorldSpace(axis):Dot(trap.Direction) < 0 then
		axis = -axis
	end
	trap.Data = {
		Segments = math.clamp(math.floor(Common.Num(part, "Segments", 8)), 2, 24),
		Axis = axis,
		Length = if alongX then size.X else size.Z,
		Width = if alongX then size.Z else size.X,
		Thick = size.Y,
		Cells = {},
		Fill = {},
		WasFull = {},
		Label = nil,
		Anchor = nil,
		Text = "",
	} :: BridgeData
end

-- Avancement de la barre (0..1) et phase du cycle.
function LoadBridge.Progress(trap: Trap, t: number): (number, number)
	local d = trap.Data :: BridgeData
	local p = Common.Cycle(trap, t)
	local warnStart = math.max(FILL_END, EMPTY_START - math.max(Common.TELEGRAPH / trap.Period, 0.1))
	if p < FILL_END then
		local segments = d.Segments
		local k = Common.CycleIndex(trap, t)
		-- Blocage sur une frontière de segment, tiré au sort (même valeur pour tous les clients)
		local stall = math.max(math.floor((0.35 + 0.4 * Common.Hash01(trap.Seed, k)) * segments), 1) / segments
		local u = p / FILL_END
		local a = (1 - STALL) * stall -- vitesse de remplissage constante hors blocage
		if u < a then
			return stall * u / a, LoadBridge.FILL
		elseif u < a + STALL then
			return stall, LoadBridge.STALL
		end
		return stall + (1 - stall) * (u - a - STALL) / (1 - a - STALL), LoadBridge.FILL
	elseif p < warnStart then
		return 1, LoadBridge.FULL
	elseif p < EMPTY_START then
		return 1, LoadBridge.WARN
	end
	return 0, LoadBridge.EMPTY
end

-- Remplissage du segment i (1..Segments) : 0..1 ; solide seulement à 1.
function LoadBridge.SegmentFill(trap: Trap, i: number, t: number): number
	local progress = LoadBridge.Progress(trap, t)
	return math.clamp(progress * (trap.Data :: BridgeData).Segments - (i - 1), 0, 1)
end

local function pose(trap: Trap, t: number): CFrame
	if trap.Offset.Magnitude == 0 then
		return trap.Rest
	end
	return trap.Rest + trap.Offset * Common.Swing(Common.Cycle(trap, t))
end

-- Repère d'une case (fill = 1) ou de sa partie remplie, mesurée depuis le début du pont.
local function cellFrame(trap: Trap, i: number, fill: number): (CFrame, Vector3)
	local d = trap.Data :: BridgeData
	local cell = d.Length / d.Segments
	local length = math.max(cell * fill - 0.25, 0.05)
	local center = -d.Length / 2 + (i - 1) * cell + cell * fill / 2
	local size = if math.abs(d.Axis.X) > 0.5
		then Vector3.new(length, d.Thick, d.Width)
		else Vector3.new(d.Width, d.Thick, length)
	return trap.Next * CFrame.new(d.Axis * center), size
end

local function build(trap: Trap, _f: Ctx)
	local d = trap.Data :: BridgeData
	local rig = Common.RigOf(trap)
	Common.HideRoot(trap, 0.75)
	for i = 1, d.Segments do
		local cf, size = cellFrame(trap, i, 1)
		local part = Common.NewPart("Part", rig, size, cf, GREEN, Enum.Material.Neon, 1)
		part.Name = `Segment{i}`
		Common.Platform(part)
		d.Cells[i] = Common.AddPiece(trap, part, size, cf, false)
		d.Fill[i] = 1
		d.WasFull[i] = false
	end
	-- Étiquette « Chargement… 42 % » au-dessus du pont, portée par une pièce invisible
	local lift = CFrame.new(0, d.Thick / 2 + 4, 0)
	local anchor =
		Common.NewPart("Part", rig, Vector3.new(0.2, 0.2, 0.2), trap.Next * lift, WHITE, Enum.Material.SmoothPlastic, 1)
	anchor.Name = "Label"
	d.Anchor = Common.AddPiece(trap, anchor, anchor.Size, trap.Next, false, lift)
	local gui = Common.Make("BillboardGui", {
		Name = "Progress",
		Size = UDim2.fromOffset(220, 44),
		LightInfluence = 0,
		MaxDistance = 140,
	}, anchor)
	d.Label = Common.Make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.3,
		TextScaled = true,
		Text = "",
	}, gui) :: TextLabel
end

local function update(trap: Trap, f: Ctx)
	local d = trap.Data :: BridgeData
	if #d.Cells == 0 then
		return
	end
	local progress, phase = LoadBridge.Progress(trap, f.T)
	local moving = trap.Offset.Magnitude > 0
	local blink = phase == LoadBridge.WARN and not Common.Blink(f.T, 5, f.Reduced)
	if phase == LoadBridge.WARN then
		Common.Cue(trap, "Warn", Common.CycleIndex(trap, f.T))
	end
	for i, piece in d.Cells do
		local fill = if phase == LoadBridge.EMPTY then 0 else math.clamp(progress * d.Segments - (i - 1), 0, 1)
		local full = fill >= 1
		local shown = if full then 1 else math.floor(fill * 50) / 50
		if d.Fill[i] ~= shown or moving then
			local cf, size = cellFrame(trap, i, if shown > 0 then shown else 1)
			if d.Fill[i] ~= shown and shown > 0 then
				piece.Part.Size = size
			end
			d.Fill[i] = shown
			piece.Next = cf
		end
		-- Transport seulement par un segment déjà plein à l'image précédente
		piece.Solid = full and d.WasFull[i]
		d.WasFull[i] = full
		Common.SetCollide(piece, full)
		if shown <= 0 then
			Common.SetAlpha(piece, 1)
		elseif not full then
			Common.SetTint(piece, GREEN:Lerp(WHITE, 0.4))
			Common.SetAlpha(piece, 0.45)
		else
			Common.SetTint(piece, if phase == LoadBridge.STALL then AMBER elseif blink then WHITE else GREEN)
			Common.SetAlpha(piece, if blink then 0.4 else 0)
		end
	end
	local anchor = d.Anchor
	if anchor then
		anchor.Next = trap.Next
	end
	local label = d.Label
	if label then
		local percent = math.floor(progress * 100 + 0.5)
		local text = if phase == LoadBridge.STALL
			then `Ne répond pas... {percent} %`
			elseif phase == LoadBridge.EMPTY then "Nouvel essai..."
			elseif phase == LoadBridge.FILL then `Chargement... {percent} %`
			else "100 %"
		if d.Text ~= text then
			d.Text = text
			label.Text = text
			label.TextColor3 = if phase == LoadBridge.STALL then AMBER else WHITE
		end
	end
end

LoadBridge.Handlers = {
	LoadBridge = { Carrier = true, Setup = setup, Build = build, Pose = pose, Update = update },
} :: { [string]: Handler }

return LoadBridge
