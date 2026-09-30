--!strict
--[[
	Traps/Toggles : plateformes v2 fixes qui deviennent traversables selon l'horloge du monde.
	La collision est changée LOCALEMENT (le personnage local est simulé par ce client) ; tous les
	clients calculent le même état au même moment.

	- Powered : solide pendant la fraction Duty du cycle (défaut Period 4, Duty 0,6).
	  0,8 s avant de s'éteindre elle clignote ; éteinte = fantôme sombre (on voit où elle
	  reviendra) ; 0,5 s avant de revenir elle grésille. BLACKOUT : éteinte et INVISIBLE ;
	  pendant l'annonce du BLACKOUT, toutes les plateformes allumées clignotent.
	- Corrupt : damier rose / noir « texture manquante » ; solide pendant Duty (défaut 0,5 sur
	  Period 4), traversable (fantôme) sinon ; clignote 0,8 s avant chaque bascule. CORRUPTION :
	  état inversé (damier aux couleurs inversées), avec clignotement avant le début et la fin.
	- DeadPixels : chaque dalle est un pixel ; il MEURT (noir, traversable) pendant la fraction Duty
	  du cycle (défaut 0,35 sur Period 3). La vague avance dans Direction à Speed studs/s (défaut 12) :
	  décalage = (position · Direction) / Speed. Le pixel grésille 0,8 s avant de mourir.
]]

local Common = require(script.Parent.Common)

type Trap = Common.Trap
type Ctx = Common.Ctx
type Handler = Common.Handler

local Toggles = {}

local TELEGRAPH = Common.TELEGRAPH
local cycle = Common.Cycle
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(18, 18, 24)
local PINK = Color3.fromRGB(255, 0, 220)

-- Applique un état visuel (transparence de la racine et des pièces soudées, collision, couleur).
local function apply(trap: Trap, state: number, collide: boolean, alpha: number, color: Color3)
	if trap.Visual == state then
		return
	end
	trap.Visual = state
	for _, solid in trap.Solids do
		solid.Part.Transparency = if alpha >= 1 then 1 else math.max(solid.Transparency, alpha)
	end
	trap.Part.CanCollide = collide
	trap.Part.Color = color
end

------------------------------------------------------------------------------------
-- Powered : plateforme alimentée
------------------------------------------------------------------------------------

local function poweredSetup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 4), 0.5)
	trap.Duty = math.clamp(Common.Num(part, "Duty", 0.6), 0.05, 0.95)
end

function Toggles.PoweredOn(trap: Trap, f: Ctx): boolean
	return f.Incident ~= "Blackout" and cycle(trap, f.T) < trap.Duty
end

local function poweredVisual(trap: Trap, f: Ctx)
	local base = trap.Solids[1].Transparency
	local color = trap.Color
	if f.Incident == "Blackout" then
		apply(trap, 7, false, 1, color)
		return
	end
	local p = cycle(trap, f.T)
	if p < trap.Duty then
		local left = (trap.Duty - p) * trap.Period
		if left < TELEGRAPH or f.Incoming == "Blackout" then
			Common.Cue(trap, "Warn", Common.CycleIndex(trap, f.T))
			if f.Reduced then
				apply(trap, 4, true, 0.35, color:Lerp(WHITE, 0.3))
			elseif Common.Blink(f.T, 5, false) then
				apply(trap, 2, true, base, color:Lerp(WHITE, 0.55))
			else
				apply(trap, 3, true, 0.55, color)
			end
		else
			apply(trap, 1, true, base, color)
		end
	elseif (1 - p) * trap.Period < 0.5 and not f.Reduced then
		-- Le courant revient : grésillement
		if Common.Blink(f.T, 8, false) then
			apply(trap, 5, false, 0.6, color)
		else
			apply(trap, 6, false, 0.8, color)
		end
	else
		apply(trap, 8, false, 0.85, color:Lerp(Color3.new(0, 0, 0), 0.5))
	end
end

------------------------------------------------------------------------------------
-- Corrupt : dalle corrompue (damier « texture manquante »)
------------------------------------------------------------------------------------

type CorruptData = { Pink: { Frame }, Black: { Frame }, Gui: SurfaceGui?, Shown: boolean?, Swapped: boolean }

local function corruptSetup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 4), 0.5)
	trap.Duty = math.clamp(Common.Num(part, "Duty", 0.5), 0.05, 0.95)
	trap.Data = { Pink = {}, Black = {}, Gui = nil, Shown = nil, Swapped = false } :: CorruptData
end

local function corruptBuild(trap: Trap, _f: Ctx)
	local data = trap.Data :: CorruptData
	local size = trap.Size
	local n = math.clamp(math.floor(math.max(size.X, size.Z) / 2.5 + 0.5), 2, 6)
	-- Pellicule invisible posée sur la dalle, qui porte le damier (la dalle reste au monde)
	local skin = Common.NewPart(
		"Part",
		Common.RigOf(trap),
		Vector3.new(size.X, 0.05, size.Z),
		trap.Rest * CFrame.new(0, size.Y / 2 + 0.03, 0),
		PINK,
		Enum.Material.SmoothPlastic,
		1
	)
	skin.Name = "CorruptSkin"
	local gui = Common.Make("SurfaceGui", {
		Name = "MissingTexture",
		Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 12,
		LightInfluence = 0,
		MaxDistance = 250,
	}, skin) :: SurfaceGui
	Common.Make("UIGridLayout", {
		CellSize = UDim2.fromScale(1 / n, 1 / n),
		CellPadding = UDim2.fromOffset(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, gui)
	for row = 0, n - 1 do
		for col = 0, n - 1 do
			local pink = (row + col) % 2 == 0
			local cell = Common.Make("Frame", {
				BorderSizePixel = 0,
				LayoutOrder = row * n + col,
				BackgroundColor3 = if pink then PINK else BLACK,
			}, gui) :: Frame
			table.insert(if pink then data.Pink else data.Black, cell)
		end
	end
	data.Gui = gui
end

function Toggles.CorruptSolid(trap: Trap, f: Ctx): boolean
	return (cycle(trap, f.T) < trap.Duty) ~= (f.Incident == "Corruption")
end

local function corruptVisual(trap: Trap, f: Ctx)
	local data = trap.Data :: CorruptData
	local p = cycle(trap, f.T)
	local solid = Toggles.CorruptSolid(trap, f)
	local inverted = f.Incident == "Corruption"
	-- Secondes avant la prochaine bascule (cycle naturel, début ou fin de l'incident)
	local natural = if p < trap.Duty then (trap.Duty - p) * trap.Period else (1 - p) * trap.Period
	local edge = if f.Incident == "Corruption" or f.Incoming == "Corruption" then f.Until else math.huge
	local soon = math.min(natural, edge) < TELEGRAPH
	if soon then
		Common.Cue(trap, "Warn", Common.CycleIndex(trap, f.T) * 2 + (if p < trap.Duty then 0 else 1))
	end
	local looksSolid = solid
	if soon and not f.Reduced then
		looksSolid = Common.Blink(f.T, 6, false)
	end
	local half = soon and f.Reduced
	local state = (if solid then 1 else 0) + (if looksSolid then 2 else 0) + (if half then 4 else 0)
	local base = trap.Solids[1].Transparency
	local alpha = if half then 0.4 elseif looksSolid then base else 0.8
	apply(trap, state, solid, alpha, trap.Color)
	local gui = data.Gui
	local shown = looksSolid or half
	if gui and data.Shown ~= shown then
		data.Shown = shown
		gui.Enabled = shown
	end
	if data.Swapped ~= inverted then
		data.Swapped = inverted
		for _, cell in data.Pink do
			cell.BackgroundColor3 = if inverted then BLACK else PINK
		end
		for _, cell in data.Black do
			cell.BackgroundColor3 = if inverted then PINK else BLACK
		end
	end
end

------------------------------------------------------------------------------------
-- DeadPixels : dalles qui s'éteignent en vague
------------------------------------------------------------------------------------

local function pixelSetup(trap: Trap)
	local part = trap.Part
	trap.Period = math.max(Common.Num(part, "Period", 3), 0.5)
	trap.Duty = math.clamp(Common.Num(part, "Duty", 0.35), 0.05, 0.9)
	if trap.Direction.Magnitude == 0 then
		trap.Direction = Vector3.xAxis
	end
	local speed = math.max(Common.Num(part, "Speed", 12), 0.5)
	trap.Data = { Delay = trap.Rest.Position:Dot(trap.Direction) / speed }
end

function Toggles.PixelCycle(trap: Trap, t: number): number
	return ((t - trap.Data.Delay) / trap.Period + trap.Phase) % 1
end

function Toggles.PixelDead(trap: Trap, t: number): boolean
	return Toggles.PixelCycle(trap, t) < trap.Duty
end

local function pixelVisual(trap: Trap, f: Ctx)
	local c = Toggles.PixelCycle(trap, f.T)
	local base = trap.Solids[1].Transparency
	local color = trap.Color
	if c < trap.Duty then
		if (trap.Duty - c) * trap.Period < 0.4 and not f.Reduced then
			apply(trap, 5, false, 0.6, color) -- se rallume
		else
			apply(trap, 4, false, 0.88, BLACK)
		end
	elseif (1 - c) * trap.Period < TELEGRAPH then
		Common.Cue(trap, "Warn", math.floor((f.T - trap.Data.Delay) / trap.Period + trap.Phase))
		if f.Reduced then
			apply(trap, 3, true, math.max(base, 0.3), color:Lerp(BLACK, 0.5))
		elseif Common.Blink(f.T, 7, false) then
			apply(trap, 2, true, base, BLACK)
		else
			apply(trap, 6, true, base, color:Lerp(WHITE, 0.4))
		end
	else
		apply(trap, 1, true, base, color)
	end
end

Toggles.Handlers = {
	Powered = { Setup = poweredSetup, Update = poweredVisual },
	Corrupt = { Setup = corruptSetup, Build = corruptBuild, Update = corruptVisual },
	DeadPixels = { Setup = pixelSetup, Update = pixelVisual },
} :: { [string]: Handler }

return Toggles
