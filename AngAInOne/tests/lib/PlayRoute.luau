--[[
	PlayRoute : un joueur simulé parcourt la tour construite (IsolatedTower) et on regarde ce qu'il voit.
	- Trajet : plus court chemin du graphe de sauts de chaque étape (pad s-1 -> pad s, personnage par
	  défaut : WalkSpeed 16, JumpPower 50), quadrillage du sol de chaque salle du terminal (le joueur
	  y circule librement pendant l'épreuve) et des sols praticables du lobby.
	- Points de vue : les yeux du personnage (dessus de la plateforme + 5 studs) et une caméra un peu
	  en retrait et au-dessus (troisième personne).
	- Contrôles (PlayRoute.Audit) : chaque SurfaceGui actif (panneau, fenêtre, écran) doit être lisible
	  depuis au moins un point de vue (de face, à portée, sans obstacle, face pas collée à un mur) ;
	  chaque modèle 3D à façade (écran, visage) doit montrer son AVANT à un point de vue ; chaque
	  ProximityPrompt doit être atteignable (distance d'activation, ligne de vue).
	Accélération : grille de cellules de 16 studs pour les obstacles (boîtes orientées des pièces).
]]
local roblox = require("@lune/roblox")
local V3 = roblox.Vector3

local PlayRoute = {}

local WALK, JUMP, GRAVITY = 16, 50, 196.2
local FORGIVE = 1.2
local EYE = 5
local CELL = 16

local LETHAL_KINDS = {
	Zapper = true,
	SpinBar = true,
	Crusher = true,
	Laser = true,
	Virus = true,
	Heat = true,
	Surge = true,
	TabRain = true,
	Flood = true,
	DustBall = true,
	Pendulum = true,
	Cursor = true,
	FirewallWall = true,
}

local function extents(part: any): any
	local cf, size = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return V3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) / 2
end

local function top(part: any): number
	return part.CFrame.Position.Y + extents(part).Y
end

local function isLethal(part: any, tower: any): boolean
	if part:HasTag("Hazard") then
		return true
	end
	local node = part
	while node and node ~= tower do
		if node:HasTag("Trap") and LETHAL_KINDS[node:GetAttribute("Kind")] then
			return true
		end
		node = node.Parent
	end
	return false
end

local function reach(dy: number, power: number): number?
	local disc = power * power - 2 * GRAVITY * dy
	if disc < 0 or dy > power * power / (2 * GRAVITY) - 0.35 then
		return nil
	end
	local t = (power + math.sqrt(disc)) / GRAVITY
	return WALK * t + FORGIVE
end

type Rect = { X0: number, X1: number, Z0: number, Z1: number, Y: number, Bounce: boolean, Link: number? }

local function surfaces(part: any, out: { Rect }, tower: any)
	if not part.CanCollide or isLethal(part, tower) then
		return
	end
	if part:IsA("WedgePart") then
		local cf, size = part.CFrame, part.Size
		local n = 8
		for i = 0, n - 1 do
			local z0 = -size.Z / 2 + size.Z * i / n
			local z1 = z0 + size.Z / n
			local yTop = -size.Y / 2 + size.Y * (i + 1) / n
			local a = cf:PointToWorldSpace(V3.new(-size.X / 2, yTop, z0))
			local b = cf:PointToWorldSpace(V3.new(size.X / 2, yTop, z1))
			table.insert(out, {
				X0 = math.min(a.X, b.X),
				X1 = math.max(a.X, b.X),
				Z0 = math.min(a.Z, b.Z),
				Z1 = math.max(a.Z, b.Z),
				Y = a.Y,
				Bounce = false,
			})
		end
		return
	end
	if math.abs(part.CFrame.UpVector.Y) < 0.99 and math.abs(part.CFrame.RightVector.Y) < 0.99 then
		if math.abs(part.CFrame.LookVector.Y) < 0.99 then
			return
		end
	end
	local e = extents(part)
	local p = part.CFrame.Position
	local rect = {
		X0 = p.X - e.X,
		X1 = p.X + e.X,
		Z0 = p.Z - e.Z,
		Z1 = p.Z + e.Z,
		Y = p.Y + e.Y,
		Bounce = part:HasTag("Trap") and part:GetAttribute("Kind") == "Bounce",
	}
	table.insert(out, rect)
	if part:HasTag("Trap") and part:GetAttribute("Kind") == "Mover" then
		local offset = part:GetAttribute("Offset")
		if typeof(offset) == "Vector3" then
			local moved = table.clone(rect)
			moved.X0 += offset.X
			moved.X1 += offset.X
			moved.Z0 += offset.Z
			moved.Z1 += offset.Z
			moved.Y += offset.Y
			rect.Link = #out + 1
			table.insert(out, moved)
			moved.Link = #out - 1
		end
	end
end

local function gap(a: Rect, b: Rect): number
	local dx = math.max(0, math.max(a.X0, b.X0) - math.min(a.X1, b.X1))
	local dz = math.max(0, math.max(a.Z0, b.Z0) - math.min(a.Z1, b.Z1))
	return math.sqrt(dx * dx + dz * dz)
end

local function canJump(a: Rect, b: Rect): boolean
	local dy = b.Y - a.Y
	if dy < -80 then
		return false
	end
	local range = reach(dy, if a.Bounce then 80 else JUMP)
	return range ~= nil and gap(a, b) <= range
end

-- Toutes les plateformes atteignables depuis `from` (exploration complète : le joueur va où il veut).
local function flood(rects: { Rect }, from: any): { Rect }?
	local startIndex
	local fromTop = top(from)
	local fp = from.CFrame.Position
	for i, r in rects do
		if math.abs(r.Y - fromTop) < 0.01 and fp.X >= r.X0 and fp.X <= r.X1 and fp.Z >= r.Z0 and fp.Z <= r.Z1 then
			startIndex = startIndex or i
		end
	end
	if not startIndex then
		return nil
	end
	local seen = { [startIndex] = true }
	local queue = { startIndex }
	local head = 1
	while head <= #queue do
		local i = queue[head]
		head += 1
		local a = rects[i]
		if a.Link and not seen[a.Link] then
			seen[a.Link] = true
			table.insert(queue, a.Link)
		end
		for j, b in rects do
			if not seen[j] and canJump(a, b) then
				seen[j] = true
				table.insert(queue, j)
			end
		end
	end
	local out = {}
	for _, i in queue do
		table.insert(out, rects[i])
	end
	return out
end

export type View = { Eye: any, Label: string, World: number? }

------------------------------------------------------------------------------------
-- Obstacles : boîtes orientées des pièces visibles, rangées dans une grille
------------------------------------------------------------------------------------

type Box = { Part: any, Inv: any, Half: any, Lo: any, Hi: any }

local function newGrid(): any
	return { Cells = {} :: { [string]: { Box } } }
end

local function key(x: number, y: number, z: number): string
	return `{x},{y},{z}`
end

local function addBox(grid: any, part: any, shrink: number?)
	local e = extents(part)
	local p = part.CFrame.Position
	local lo, hi = p - e, p + e
	local box: Box = {
		Part = part,
		Inv = part.CFrame:Inverse(),
		Half = part.Size / 2 * (shrink or 1),
		Lo = lo,
		Hi = hi,
	}
	for x = math.floor(lo.X / CELL), math.floor(hi.X / CELL) do
		for y = math.floor(lo.Y / CELL), math.floor(hi.Y / CELL) do
			for z = math.floor(lo.Z / CELL), math.floor(hi.Z / CELL) do
				local k = key(x, y, z)
				local list = grid.Cells[k]
				if not list then
					list = {}
					grid.Cells[k] = list
				end
				table.insert(list, box)
			end
		end
	end
end

-- Le segment a -> b traverse-t-il une boîte (hors `ignore(part)`) ? Renvoie la pièce touchée.
local function segmentHit(grid: any, a: any, b: any, ignore: (any) -> boolean): any?
	local d = b - a
	local length = d.Magnitude
	if length < 1e-6 then
		return nil
	end
	local tested: { [Box]: boolean } = {}
	local steps = math.max(1, math.ceil(length / (CELL / 2)))
	for i = 0, steps do
		local p = a + d * (i / steps)
		local cx, cy, cz = math.floor(p.X / CELL), math.floor(p.Y / CELL), math.floor(p.Z / CELL)
		for ox = -1, 1 do
			for oy = -1, 1 do
				for oz = -1, 1 do
					for _, box in grid.Cells[key(cx + ox, cy + oy, cz + oz)] or {} do
						if not tested[box] then
							tested[box] = true
							if not ignore(box.Part) then
								-- slab test dans le repère de la pièce
								local la, lb = box.Inv * a, box.Inv * b
								local dir = lb - la
								local t0, t1 = 0, 1
								local hit = true
								for _, axis in { "X", "Y", "Z" } do
									local o, v, h = (la :: any)[axis], (dir :: any)[axis], (box.Half :: any)[axis]
									if math.abs(v) < 1e-9 then
										if o < -h or o > h then
											hit = false
											break
										end
									else
										local u0, u1 = (-h - o) / v, (h - o) / v
										if u0 > u1 then
											u0, u1 = u1, u0
										end
										t0, t1 = math.max(t0, u0), math.min(t1, u1)
										if t0 > t1 then
											hit = false
											break
										end
									end
								end
								if hit then
									return box.Part
								end
							end
						end
					end
				end
			end
		end
	end
	return nil
end

local function inside(grid: any, p: any, ignore: (any) -> boolean): any?
	local list = grid.Cells[key(math.floor(p.X / CELL), math.floor(p.Y / CELL), math.floor(p.Z / CELL))] or {}
	for _, box in list do
		if not ignore(box.Part) then
			local l = box.Inv * p
			if math.abs(l.X) < box.Half.X and math.abs(l.Y) < box.Half.Y and math.abs(l.Z) < box.Half.Z then
				return box.Part
			end
		end
	end
	return nil
end

------------------------------------------------------------------------------------
-- Construction du trajet
------------------------------------------------------------------------------------

-- Pièces des modèles 3D simulés (attribut AuditModelPart, boîtes englobantes trop grosses) : obstacles
-- réduits de moitié, et jamais « collées » à un panneau (FitScreen pose les écrans sur leur surface).
function PlayRoute.Build(built: any): any
	local tower = built.Tower
	local Tower = built.Load("src/shared/Config/Tower.luau")
	local descendants = tower:GetDescendants()
	local pads: { [number]: any } = {}
	for _, d in descendants do
		if d:HasTag("Checkpoint") then
			local stage = d:GetAttribute("Stage")
			if type(stage) == "number" then
				pads[stage] = d
			end
		end
	end

	-- Obstacles visibles (opaques) et solides (pour savoir où l'on peut se tenir)
	local sight = newGrid()
	local solid = newGrid()
	for _, d in descendants do
		if d:IsA("BasePart") then
			local m = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			if d.Transparency < 0.5 and m > 0.6 then
				addBox(sight, d, if d:GetAttribute("AuditModelPart") then 0.5 else 1)
			end
			if d.CanCollide then
				addBox(solid, d)
			end
		end
	end

	local views: { View } = {}
	local function addView(eye: any, label: string, world: number?)
		table.insert(views, { Eye = eye, Label = label, World = world })
	end

	-- 1. Chaque étape : toutes les plateformes atteignables depuis le pad précédent
	local areas: { Rect & { World: number } } = {}
	local function sample(r: Rect, label: string, w: number)
		local sx, sz = r.X1 - r.X0, r.Z1 - r.Z0
		-- un point tous les 8 à 30 studs (grandes surfaces du lobby : ≈ 600 points au plus)
		local step = math.max(8, math.sqrt(sx * sz / 600))
		local nx = math.max(1, math.floor(sx / step))
		local nz = math.max(1, math.floor(sz / step))
		for i = 1, nx do
			for j = 1, nz do
				local x = r.X0 + sx * (i - 0.5) / nx
				local z = r.Z0 + sz * (j - 0.5) / nz
				addView(V3.new(x, r.Y + EYE, z), label, w)
				-- caméra 3e personne : un peu au-dessus et en retrait (vers le centre de la tour)
				local back = V3.new(x, 0, z)
				local dir = if back.Magnitude > 1 then back.Unit else V3.new(0, 0, 1)
				addView(V3.new(x, r.Y + EYE + 4, z) + dir * 8, label .. " (caméra)", w)
			end
		end
	end
	local function explore(roots: { any }, extraPads: { any }, from: any, label: string, w: number): boolean
		local rects: { Rect } = {}
		for _, root in roots do
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					surfaces(d, rects, tower)
				end
			end
		end
		for _, pad in extraPads do
			surfaces(pad, rects, tower)
		end
		local reached = flood(rects, from)
		if not reached then
			return false
		end
		for _, r in reached do
			sample(r, label, w)
			local area = table.clone(r) :: any
			area.World = w
			table.insert(areas, area)
		end
		return true
	end
	local missing = {}
	for s = 1, Tower.TOTAL_STAGES do
		local w = Tower.WorldOf(s)
		local roots = {}
		local world = tower:FindFirstChild(`World{w}`)
		local function add(root: any?)
			if root then
				table.insert(roots, root)
			end
		end
		add(world and world:FindFirstChild(`Stage{s}`))
		local prevWorld = tower:FindFirstChild(`World{Tower.WorldOf(s - 1)}`)
		add(prevWorld and prevWorld:FindFirstChild(`Stage{s - 1}`))
		add(world and world:FindFirstChild("Terminal"))
		add(world and world:FindFirstChild("Mechanics"))
		add(world and world:FindFirstChild("Bonus"))
		if w > 1 then
			add(tower[`World{w - 1}`]:FindFirstChild("Terminal"))
		end
		if s == 1 then
			add(tower:FindFirstChild("Lobby"))
		end
		local extra = {}
		for stage, pad in pads do
			if stage == s or stage == s - 1 then
				table.insert(extra, pad)
			end
		end
		local from = pads[s - 1]
		if not from or not explore(roots, extra, from, `étape {s}`, w) then
			table.insert(missing, s)
		end
	end
	-- Salles où l'on est téléporté (BIOS caché) : quadrillage de leurs sols
	local lobbyFolder = tower:FindFirstChild("Lobby")
	local bios = lobbyFolder and lobbyFolder:FindFirstChild("Bios")
	if bios then
		local rects: { Rect } = {}
		for _, d in bios:GetDescendants() do
			if d:IsA("BasePart") then
				surfaces(d, rects, tower)
			end
		end
		for _, r in rects do
			if (r.X1 - r.X0) * (r.Z1 - r.Z0) > 30 then
				sample(r, "BIOS", 0)
				local area = table.clone(r) :: any
				area.World = 0
				table.insert(areas, area)
			end
		end
	end
	-- Sommet : toit de la dernière salle (depuis le dernier pad)
	local last = pads[Tower.TOTAL_STAGES]
	local top7 = tower:FindFirstChild(`World{Tower.WORLD_COUNT}`)
	if last and top7 then
		local roots = { top7:FindFirstChild("Terminal") }
		explore(roots, { last }, last, "sommet", Tower.WORLD_COUNT)
	end

	-- 2. Salles du terminal : quadrillage du sol (le joueur y circule librement)
	for _, d in descendants do
		if d.Name == "Epreuve" and d:GetAttribute("Origin") then
			local origin, f, r = d:GetAttribute("Origin"), d:GetAttribute("AxisF"), d:GetAttribute("AxisR")
			local w = d:GetAttribute("World")
			for u = -7, 36, 3 do
				for v = -42, 6, 3 do
					local floor = origin + f * u + r * v
					local feet = floor + V3.new(0, 1.2, 0)
					local head = floor + V3.new(0, 4.5, 0)
					local ignore = function(_part: any): boolean
						return false
					end
					if not inside(solid, feet, ignore) and not inside(solid, head, ignore) then
						addView(floor + V3.new(0, EYE, 0), `salle du terminal M{w} ({u}, {v})`, w)
					end
				end
			end
		end
	end

	return {
		Tower = tower,
		Views = views,
		Areas = areas,
		Sight = sight,
		Solid = solid,
		Missing = missing,
		Descendants = descendants,
	}
end

------------------------------------------------------------------------------------
-- Ce que voit le joueur
------------------------------------------------------------------------------------

local FACE_LOCAL = {
	Front = V3.new(0, 0, -1),
	Back = V3.new(0, 0, 1),
	Left = V3.new(-1, 0, 0),
	Right = V3.new(1, 0, 0),
	Top = V3.new(0, 1, 0),
	Bottom = V3.new(0, -1, 0),
}

local function worldOf(instance: any, tower: any): number?
	local node = instance
	while node and node ~= tower do
		if node.Parent == tower then
			local w = node:GetAttribute("World")
			return if type(w) == "number" then w else (if node.Name == "Lobby" then 0 else nil)
		end
		node = node.Parent
	end
	return nil
end

-- État de décor : "Infected" (visible tant que le monde est infecté), "Cleaned" (une fois nettoyé), nil.
local function stateOf(instance: any, tower: any): string?
	local node = instance
	while node and node ~= tower do
		if node:HasTag("Infected") then
			return "Infected"
		elseif node:HasTag("Cleaned") then
			return "Cleaned"
		end
		node = node.Parent
	end
	return nil
end

-- Pièce qui bouge (piège, danger) : elle passe devant un panneau, elle ne le recouvre pas.
local function moving(instance: any, tower: any): boolean
	local node = instance
	while node and node ~= tower do
		if node:HasTag("Trap") or node:HasTag("Hazard") or node:HasTag("TrapSpin") then
			return true
		end
		node = node.Parent
	end
	return false
end

export type Target = {
	Kind: string, -- "Panneau", "Façade", "Prompt"
	Name: string,
	Center: any,
	Normal: any?, -- direction dans laquelle il doit être vu (nil = n'importe laquelle)
	Range: number,
	MinDot: number,
	Own: (any) -> boolean, -- pièces qui appartiennent à la cible (pas des obstacles)
	World: number?,
}

-- Points d'une face de panneau : centre, puis quatre points en diagonale à 30 % des bords.
local function facePoints(target: Target): { any }
	local points = { target.Center }
	local host = (target :: any).Host
	if host then
		local cf, size = host.CFrame, host.Size
		local face = (target :: any).Face
		local a, b, sa, sb
		if face == "Left" or face == "Right" then
			a, b, sa, sb = cf.LookVector, cf.UpVector, size.Z, size.Y
		elseif face == "Top" or face == "Bottom" then
			a, b, sa, sb = cf.RightVector, cf.LookVector, size.X, size.Z
		else
			a, b, sa, sb = cf.RightVector, cf.UpVector, size.X, size.Y
		end
		for _, sign in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			table.insert(points, target.Center + a * (sign[1] * sa * 0.3) + b * (sign[2] * sb * 0.3))
		end
	end
	return points
end

-- Une cible est-elle vue depuis au moins un point de vue (un de ses points suffit) ?
-- Renvoie (ok, raison du meilleur échec).
function PlayRoute.Seen(route: any, target: Target): (boolean, string, number)
	local best = "aucun point de vue à portée"
	local seenCount = 0
	local closest = math.huge
	for _, view in route.Views do
		local delta = view.Eye - target.Center
		local distance = delta.Magnitude
		if distance <= target.Range and distance > 0.5 then
			closest = math.min(closest, distance)
			local facing = if target.Normal then delta.Unit:Dot(target.Normal) else 1
			if facing < target.MinDot then
				if best == "aucun point de vue à portée" then
					best = `vu de dos ou de biais (meilleur : {view.Label})`
				end
			else
				for _, point in facePoints(target) do
					local start = point + (if target.Normal then target.Normal * 0.15 else V3.zero)
					local blocker = segmentHit(route.Sight, start, view.Eye, target.Own)
					if blocker then
						best = `caché par {blocker:GetFullName()} (depuis {view.Label})`
					else
						seenCount += 1
						return true, view.Label, seenCount
					end
				end
			end
		end
	end
	if closest == math.huge then
		best = `aucun point de vue à moins de {target.Range} studs`
	end
	return false, best, 0
end

-- Toutes les cibles de la tour : panneaux (SurfaceGui actifs), façades de modèles, prompts.
function PlayRoute.Targets(route: any, facades: { { Key: string, Model: any, Front: any } }): { Target }
	local tower = route.Tower
	local targets: { Target } = {}
	for _, gui in route.Descendants do
		if gui:IsA("SurfaceGui") and gui.Enabled and gui.Name ~= "PcbPattern" then
			local part = gui.Adornee or gui.Parent
			if part and part:IsA("BasePart") then
				local faceName = gui.Face.Name
				local localNormal = FACE_LOCAL[faceName] or FACE_LOCAL.Front
				local normal = part.CFrame:VectorToWorldSpace(localNormal)
				local half = part.Size / 2
				local offset = V3.new(localNormal.X * half.X, localNormal.Y * half.Y, localNormal.Z * half.Z)
				local center = part.CFrame:PointToWorldSpace(offset)
				local host = part
				table.insert(
					targets,
					{
						Kind = "Panneau",
						Name = `{gui:GetFullName()} [{faceName}]`,
						Center = center,
						Normal = normal,
						Range = math.max(math.max(part.Size.X, part.Size.Y, part.Size.Z) * 9, 40),
						MinDot = 0.2,
						Own = function(p: any): boolean
							return p == host or p:IsDescendantOf(host)
						end,
						World = worldOf(part, tower),
						Host = part,
						Face = faceName,
					} :: any
				)
			end
		end
	end
	for _, rec in facades do
		local lo, hi = nil, nil
		for _, part in rec.Model:GetDescendants() do
			if part:IsA("BasePart") then
				local e = extents(part)
				local p = part.CFrame.Position
				lo = if lo
					then V3.new(math.min(lo.X, p.X - e.X), math.min(lo.Y, p.Y - e.Y), math.min(lo.Z, p.Z - e.Z))
					else p - e
				hi = if hi
					then V3.new(math.max(hi.X, p.X + e.X), math.max(hi.Y, p.Y + e.Y), math.max(hi.Z, p.Z + e.Z))
					else p + e
			end
		end
		if lo and hi then
			local center = (lo + hi) / 2
			local front = rec.Front
			local reachOut = math.abs(front.X) * (hi.X - lo.X) / 2 + math.abs(front.Z) * (hi.Z - lo.Z) / 2
			local model = rec.Model
			local at = (rec :: any).At
			table.insert(
				targets,
				{
					Kind = "Façade",
					Name = `{rec.Key} {model:GetFullName()}`,
					Center = if at then at + front * 0.5 else center + front * reachOut,
					Normal = front,
					Range = math.max((hi - lo).Magnitude * 6, 40),
					MinDot = 0.25,
					Own = function(p: any): boolean
						return p:IsDescendantOf(model)
					end,
					World = worldOf(model, tower),
					Anchor = model,
				} :: any
			)
		end
	end
	for _, prompt in route.Descendants do
		if prompt:IsA("ProximityPrompt") and prompt.Enabled then
			local part = prompt.Parent
			if part and part:IsA("BasePart") then
				local host = part
				table.insert(targets, {
					Kind = "Prompt",
					Name = `{prompt:GetFullName()} « {prompt.ActionText} »`,
					Center = part.CFrame.Position,
					Normal = nil,
					Range = prompt.MaxActivationDistance,
					MinDot = -2,
					Own = function(p: any): boolean
						return p == host or p:IsDescendantOf(host) or not p.CanQuery
					end,
					World = worldOf(part, tower),
				})
			end
		end
	end
	-- Décor d'un autre état du monde (infecté / nettoyé) : jamais visible en même temps
	for _, target in targets do
		local anchor = (target :: any).Host or (target :: any).Anchor
		local state = if anchor then stateOf(anchor, tower) else nil
		if state then
			local own = target.Own
			local other = if state == "Infected" then "Cleaned" else "Infected"
			target.Own = function(p: any): boolean
				return own(p) or stateOf(p, tower) == other
			end
		end
	end
	return targets
end

-- Prompt atteignable : un point d'une plateforme atteignable (racine du personnage, 3 studs
-- au-dessus) à portée d'activation, sans pièce interrogeable entre les deux.
function PlayRoute.Reachable(route: any, target: Target): (boolean, string)
	local best = math.huge
	for _, area in route.Areas do
		local p = target.Center
		local x = math.clamp(p.X, area.X0, area.X1)
		local z = math.clamp(p.Z, area.Z0, area.Z1)
		local root = V3.new(x, area.Y + 3, z)
		local d = (root - p).Magnitude
		if d <= target.Range then
			local blocker = segmentHit(route.Sight, root, p, target.Own)
			if not blocker then
				return true, ""
			end
		end
		best = math.min(best, d)
	end
	for _, view in route.Views do
		if string.find(view.Label, "salle du terminal", 1, true) then
			local d = (view.Eye - V3.new(0, 2, 0) - target.Center).Magnitude
			if d <= target.Range then
				return true, ""
			end
			best = math.min(best, d)
		end
	end
	return false, `plateforme atteignable la plus proche à {math.floor(best * 10) / 10} studs (portée {target.Range})`
end

-- Face d'un panneau collée contre une autre pièce (texte illisible) : pièce juste devant la face.
function PlayRoute.Buried(route: any, target: Target): any?
	if not target.Normal then
		return nil
	end
	local function ignore(p: any): boolean
		return target.Own(p) or p:GetAttribute("AuditModelPart") == true or moving(p, route.Tower)
	end
	-- Centre et quatre points de la face : collée si la majorité est recouverte (un croisillon de
	-- fenêtre devant le centre n'est pas un panneau collé au mur)
	local points = facePoints(target)
	local covered, first = 0, nil
	for _, point in points do
		for _, depth in { 0.2, 0.6 } do
			local hit = inside(route.Sight, point + target.Normal * depth, ignore)
			if hit then
				covered += 1
				first = first or hit
				break
			end
		end
	end
	return if covered * 2 > #points then first else nil
end

------------------------------------------------------------------------------------
-- Audit complet (outil tests/tools/PlayAudit.luau et test tests/playaudit.spec.luau)
------------------------------------------------------------------------------------

-- Modèles à façade : l'avant est du côté de la pièce repère (Away : à l'opposé de la pièce).
PlayRoute.FACES = {
	Anga = { Part = "Mouth" },
	Lagz = { Part = "Eyes" },
	LagzHead = { Part = "Eyes" },
	Sparky = { Part = "Pupil" },
	PopUp = { Part = "Text", From = "Frame" },
	Corrupto = { Part = "White" },
	Dusty = { Part = "EyeWhite" },
	Minor = { Part = "Screen" },
	Freezy = { Part = "Dark" },
	Monitor = { Part = "Screen" },
	Speaker = { Part = "Cone" },
	ArcadeCabinet = { Part = "Screen" },
	ShopKiosk = { Part = "Glass" },
	TerminalConsole = { Part = "Keys" },
	Miniaturiseur = { Part = "Screen" },
} :: { [string]: { Part: string, Away: boolean?, From: string? } }

--[[
	Exceptions justifiées (nom exact de la cible -> raison). Les modèles 3D sont simulés par les
	BOÎTES englobantes de leurs pièces : une boîte d'auvent couvre l'avant de la vitrine, une boîte de
	câble couvre tout l'espace qu'il traverse. Vérifié à l'œil sur les rendus.
]]
PlayRoute.ACCEPTED = {
	["Workspace.Tower.Checkpoints.Checkpoint0.StageNumber.SurfaceGui [Top]"] = "numéro 0 sous la plateforme du Miniaturiseur (le portail JOUER le remplace)",
	["Monitor Workspace.Tower.Lobby.DeskSetup.Monitor"] = "voulu : la dalle StreamMonitor (écran du live) est posée devant l'écran du moniteur",
	["Workspace.Tower.Lobby.ShopKiosk.Screen.Sign [Front]"] = "boîte de l'auvent de la boutique : couvre l'avant de la vitrine",
	["Workspace.Tower.Lobby.DeskSetup.StickyNote.Print [Front]"] = "boîte du câble du micro (diagonale) : le câble réel est fin",
} :: { [string]: string }

-- Pièces hôtes des prompts d'épreuve (motif du nom -> portée, comme dans Controllers/EpreuveKinds).
PlayRoute.EPREUVE_PROMPTS = {
	{ Pattern = "^LeverPost$", Range = 9 }, -- Démarrage : leviers
	{ Pattern = "^Slot%d$", Range = 12 }, -- RAM : emplacements
	{ Pattern = "^Stick%d$", Range = 12 }, -- RAM : barrettes (première pièce du modèle)
	{ Pattern = "^FlushCap$", Range = 11 }, -- RAM : Libérer la RAM
	{ Pattern = "^Corbeille$", Range = 14 }, -- Bloatware : vider la Corbeille
	{ Pattern = "^FanHousing$", Range = 10 }, -- Surchauffe : ventilateurs
	{ Pattern = "^PlanSwitch$", Range = 10 }, -- Surchauffe : plan d'alimentation
	{ Pattern = "^TurretSlot%d$", Range = 9 }, -- Défense du CPU : emplacements
	{ Pattern = "^OldFile%d$", Range = 10 }, -- Pilote : fichiers de l'ancien pilote
	{ Pattern = "^Reel%d$", Range = 10 }, -- Pilote : câbles
	{ Pattern = "^Port%d$", Range = 10 }, -- Pilote : ports
	{ Pattern = "^Monitor%d$", Range = 10 }, -- Pilote : écrans
	{ Pattern = "^PodGlass$", Range = 11 }, -- Enquête : capsules
} :: { { Pattern: string, Range: number } }

-- Observe pour IsolatedTower.Build : enregistre chaque modèle 3D posé (clé, modèle).
function PlayRoute.Recorder(records: { any }): (any) -> ()
	return function(ModelLibrary: any)
		local realPlace = ModelLibrary.Place
		ModelLibrary.Place = function(key, cframe, parent, options, fallback)
			local placed = realPlace(key, cframe, parent, options, fallback)
			if placed and ModelLibrary.Has(key) then
				table.insert(records, { Key = key, Model = placed })
			end
			return placed
		end
	end
end

local function boundsOf(model: any): (any, any)
	local lo, hi = nil, nil
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local e = extents(part)
			local p = part.CFrame.Position
			lo = if lo
				then V3.new(math.min(lo.X, p.X - e.X), math.min(lo.Y, p.Y - e.Y), math.min(lo.Z, p.Z - e.Z))
				else p - e
			hi = if hi
				then V3.new(math.max(hi.X, p.X + e.X), math.max(hi.Y, p.Y + e.Y), math.max(hi.Z, p.Z + e.Z))
				else p + e
		end
	end
	return lo, hi
end

export type Problem = {
	Kind: string,
	Name: string,
	World: number,
	Why: string,
	At: { number },
	Normal: { number }?,
	Accepted: string?,
}

function PlayRoute.Audit(built: any, records: { any }, debugName: string?): any
	for _, rec in records do
		for _, part in rec.Model:GetDescendants() do
			if part:IsA("BasePart") then
				part:SetAttribute("AuditModelPart", true) -- (une Instance Lune n'est pas une clé de table stable)
			end
		end
	end
	local route = PlayRoute.Build(built)
	local facades = {}
	for _, rec in records do
		local face = PlayRoute.FACES[rec.Key]
		if face then
			local lo, hi = boundsOf(rec.Model)
			local center = (lo + hi) / 2
			for _, part in rec.Model:GetDescendants() do
				if part:IsA("BasePart") and part.Name == face.From then
					center = part.CFrame.Position
				end
			end
			for _, part in rec.Model:GetDescendants() do
				if part:IsA("BasePart") and part.Name == face.Part then
					local d = part.CFrame.Position - center
					local flat = V3.new(d.X, 0, d.Z)
					if flat.Magnitude > 0.05 then
						table.insert(facades, {
							Key = rec.Key,
							Model = rec.Model,
							Front = flat.Unit * (if face.Away then -1 else 1),
							At = part.CFrame.Position, -- le visage / l'écran lui-même
						})
					end
					break
				end
			end
		end
	end
	local targets = PlayRoute.Targets(route, facades)
	if debugName then
		for _, target in targets do
			if string.find(target.Name, debugName, 1, true) then
				local n = target.Normal
				print(`DEBUG {target.Name} centre {target.Center} normale {n} portée {target.Range}`)
				local near = {}
				for _, view in route.Views do
					local d = view.Eye - target.Center
					table.insert(near, { View = view, D = d.Magnitude, Dot = if n then d.Unit:Dot(n) else 1 })
				end
				table.sort(near, function(a, b)
					return a.D < b.D
				end)
				for i = 1, math.min(6, #near) do
					local e = near[i]
					print(`   {e.View.Label} @ {e.View.Eye} d={math.floor(e.D)} dot={math.floor(e.Dot * 100) / 100}`)
				end
			end
		end
	end
	local problems: { Problem } = {}
	local counts = { Panneau = 0, ["Façade"] = 0, Prompt = 0 }
	local accepted = 0
	for _, target in targets do
		counts[target.Kind] = (counts[target.Kind] or 0) + 1
		local ok, why
		if target.Kind == "Prompt" then
			ok, why = PlayRoute.Reachable(route, target)
		else
			ok, why = PlayRoute.Seen(route, target)
		end
		local buried = if target.Kind == "Panneau" then PlayRoute.Buried(route, target) else nil
		if buried then
			ok = false
			why = `face collée à {buried:GetFullName()}`
		end
		if not ok then
			local reason = PlayRoute.ACCEPTED[target.Name]
			if reason then
				accepted += 1
			end
			table.insert(problems, {
				Kind = target.Kind,
				Name = target.Name,
				World = target.World or -1,
				Why = why,
				At = { target.Center.X, target.Center.Y, target.Center.Z },
				Normal = if target.Normal then { target.Normal.X, target.Normal.Y, target.Normal.Z } else nil,
				Accepted = reason,
			})
		end
	end
	-- Prompts des épreuves (créés par le client, Controllers/EpreuveKinds : pièce hôte, portée ; pas de
	-- ligne de vue). Le joueur se tient sur le sol de la salle, ou sur les socles quand le sol est de
	-- la lave (surchauffe, monde 4).
	for _, folder in route.Descendants do
		if folder.Name == "Epreuve" and folder:GetAttribute("Origin") then
			local w = folder:GetAttribute("World")
			local terminal = folder.Parent
			local roots = {}
			if folder:GetAttribute("Kind") == "Cooling" then
				for _, d in folder:GetDescendants() do
					if d.Name == "Pedestal" and d:IsA("BasePart") then
						table.insert(roots, V3.new(d.CFrame.Position.X, top(d) + 3, d.CFrame.Position.Z))
					end
				end
			else
				local label = `salle du terminal M{w} `
				for _, view in route.Views do
					if string.sub(view.Label, 1, #label) == label then
						table.insert(roots, view.Eye - V3.new(0, EYE - 3, 0))
					end
				end
			end
			counts["Prompt d'épreuve"] = counts["Prompt d'épreuve"] or 0
			for _, d in terminal:GetDescendants() do
				local range = nil
				for _, rule in PlayRoute.EPREUVE_PROMPTS do
					if string.match(d.Name, rule.Pattern) then
						range = rule.Range
						break
					end
				end
				local host = if range and d:IsA("Model") then d:FindFirstChildWhichIsA("BasePart", true) else d
				if range and host and host:IsA("BasePart") then
					counts["Prompt d'épreuve"] += 1
					local p = host.CFrame.Position
					local best = math.huge
					for _, root in roots do
						best = math.min(best, (root - p).Magnitude)
					end
					if best > range then
						local name = `{d:GetFullName()} (prompt d'épreuve)`
						local reason = PlayRoute.ACCEPTED[name]
						if reason then
							accepted += 1
						end
						table.insert(problems, {
							Kind = "Prompt",
							Name = name,
							World = w,
							Why = `hors de portée : {math.floor(best * 10) / 10} studs (portée {range}) depuis {if folder:GetAttribute(
									"Kind"
								) == "Cooling"
								then "les socles"
								else "le sol de la salle"}`,
							At = { p.X, p.Y, p.Z },
							Accepted = reason,
						})
					end
				end
			end
		end
	end
	table.sort(problems, function(a, b)
		if a.World ~= b.World then
			return a.World < b.World
		end
		if a.Kind ~= b.Kind then
			return a.Kind < b.Kind
		end
		return a.Name < b.Name
	end)
	return {
		Problems = problems,
		Accepted = accepted,
		Counts = counts,
		Views = #route.Views,
		Areas = #route.Areas,
		Missing = route.Missing,
	}
end

return PlayRoute
