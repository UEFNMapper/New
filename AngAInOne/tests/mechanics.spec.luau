-- Mécaniques « PC » des mondes (World/Tower/Mechanics) et leurs configs (Puzzles, Roles, Gauges) :
-- tour construite à part (décor de secours), puis chaque mécanique est contrôlée là où elle est posée.
local roblox = require("@lune/roblox")

local V3 = roblox.Vector3
local GRAVITY = 196.2
local WALK = 16
local JUMP = 7.2

local built = IsolatedTower.Build({ Models = false })
local tower = built.Tower
local Tower = built.Load("src/shared/Config/Tower.luau")
local Puzzles = built.Load("src/shared/Config/Puzzles.luau")
local Roles = built.Load("src/shared/Config/Roles.luau")
local Mechanics = built.Load("src/server/World/Tower/Mechanics.luau")
local DataSchema = built.Load("src/shared/Data/DataSchema.luau")

local function world(n: number): any
	return tower:FindFirstChild(`World{n}`)
end

local function prompts(root: any, action: string): { any }
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("Action") == action then
			table.insert(list, d)
		end
	end
	return list
end

-- Dessus d'une pièce solide et plate qui porte le point `p` (à `tolerance` près), sinon nil.
local function supportUnder(root: any, p: any, tolerance: number, except: any?): any?
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide and part ~= except and math.abs(part.CFrame.UpVector.Y) > 0.99 then
			local lp = part.CFrame:PointToObjectSpace(p)
			local top = part.CFrame.Position.Y + part.Size.Y / 2
			if
				math.abs(lp.X) <= part.Size.X / 2
				and math.abs(lp.Z) <= part.Size.Z / 2
				and math.abs(p.Y - top) <= tolerance
			then
				return part
			end
		end
	end
	return nil
end

return {
	["enquêtes : un seul coupable, un indice pour chaque innocent, textes FR sans marque"] = function()
		for _, puzzle in Puzzles.List do
			local culprits = 0
			for _, item in puzzle.Items do
				if item.Culprit then
					culprits += 1
				else
					Expect.truthy(type(item.Hint) == "string" and #item.Hint > 10, `indice de {item.Id}`)
				end
				Expect.truthy(#item.Lines >= 1, `lignes de {item.Id}`)
				Expect.truthy(#item.Id <= 24, "id court (RemoteGuard.String(24))")
			end
			Expect.equal(culprits, 1, `un coupable au monde {puzzle.World}`)
			Expect.truthy(puzzle.Bits > 0 and puzzle.Bits <= 60, "récompense raisonnable")
		end
	end,

	["enquêtes : un panneau par programme dans la salle du terminal, tourné vers la salle, à portée"] = function()
		for _, puzzle in Puzzles.List do
			local room = world(puzzle.World):FindFirstChild("Terminal")
			Expect.truthy(room, `salle du monde {puzzle.World}`)
			local list = prompts(room, "Puzzle")
			Expect.equal(#list, #puzzle.Items, `panneaux du monde {puzzle.World}`)
			local console = room:FindFirstChild("MinigameTerminal", true)
			local pad = nil
			for _, d in tower:GetDescendants() do
				if
					d:IsA("BasePart")
					and d:HasTag("Checkpoint")
					and d:GetAttribute("Stage") == Tower.TerminalStage(puzzle.World)
				then
					pad = d
				end
			end
			Expect.truthy(console and pad, "console et pad de la salle")
			local floorY = pad.CFrame.Position.Y + pad.Size.Y / 2
			local seen = {}
			for _, prompt in list do
				local panel = prompt.Parent
				Expect.truthy(panel:HasTag("PuzzlePanel"), "panneau tagué (PuzzleService)")
				Expect.equal(prompt:GetAttribute("World"), puzzle.World)
				local item = prompt:GetAttribute("Item")
				Expect.equal(panel:GetAttribute("Item"), item)
				seen[item] = true
				Expect.between(prompt.MaxActivationDistance, 8, 16, "distance du prompt")
				local p = panel.CFrame.Position
				Expect.between(p.Y - floorY, 2, 8, "panneau à hauteur de joueur")
				local floor = room:FindFirstChild("Floor", true)
				local lp = floor.CFrame:PointToObjectSpace(p)
				Expect.truthy(
					math.abs(lp.X) < floor.Size.X / 2 - 1 and math.abs(lp.Z) < floor.Size.Z / 2 - 1,
					"panneau dans la salle (au-dessus du plancher)"
				)
				Expect.truthy(
					panel.CFrame.LookVector:Dot((pad.CFrame.Position - p).Unit) > 0.3,
					"face tournée vers la salle"
				)
				Expect.equal(panel.CanCollide, false, "décor : ne bloque pas la salle")
			end
			for _, it in puzzle.Items do
				Expect.truthy(seen[it.Id], `panneau {it.Id}`)
			end
		end
	end,

	["RAM (monde 2) : trois boutons « Libérer la RAM » posés sur des paliers, avant chaque grande montée"] = function()
		local list = prompts(world(2), "FlushRam")
		Expect.equal(#list, #Mechanics.RAM_BUTTONS, "boutons")
		local indices = {}
		for _, prompt in list do
			local cap = prompt.Parent
			local index = prompt:GetAttribute("Index")
			indices[index] = true
			local spot = Mechanics.RAM_BUTTONS[index]
			Expect.truthy(spot, "bouton connu")
			Expect.truthy(supportUnder(world(2), spot.At, 0.3), `bouton {index} sur un palier solide`)
			Expect.truthy(
				-- Stage = dossier d'étape (segment qui mène au checkpoint `Stage`) : 6..10 au monde 2
				spot.Stage >= Tower.FirstStage(2) and spot.Stage <= Tower.TerminalStage(2),
				"étape du monde 2"
			)
			Expect.equal(cap.CanCollide, false, "décor : ne bloque pas le palier")
			Expect.between(prompt.MaxActivationDistance, 8, 16)
		end
		Expect.equal(#indices, #Mechanics.RAM_BUTTONS, "index 1..n")
	end,

	["chaleur (monde 4) : ventilateurs à relancer sur le parcours, zones fraîches, géants toujours actifs"] = function()
		local w4 = world(4)
		local fans = prompts(w4, "FanStart")
		Expect.equal(#fans, #Mechanics.RESTART_FANS, "ventilateurs à relancer")
		local zones = { NeedsStart = 0, Always = 0 }
		for _, d in w4:GetDescendants() do
			if d:IsA("BasePart") and d:HasTag("CoolZone") then
				Expect.equal(d.CanCollide, false, "zone fraîche non solide")
				Expect.equal(d.Transparency, 1, "zone fraîche invisible")
				if d:GetAttribute("NeedsStart") then
					zones.NeedsStart += 1
					Expect.truthy(type(d:GetAttribute("Index")) == "number", "zone reliée à son ventilateur")
				else
					zones.Always += 1
				end
			end
		end
		Expect.equal(zones.NeedsStart, #Mechanics.RESTART_FANS)
		Expect.equal(zones.Always, #Mechanics.GIANT_FANS + 1, "géants + ventilo propulseur")
		for index, spec in Mechanics.RESTART_FANS do
			Expect.truthy(supportUnder(w4, spec.At, 0.3), `ventilateur {index} posé sur un palier`)
			Expect.truthy(prompts(w4, "FanStart")[1].HoldDuration > 0, "appui maintenu")
		end
		for _, at in Mechanics.GIANT_FANS do
			Expect.truthy(supportUnder(w4, at, 0.3), "zone d'un ventilateur géant sur son FanDeck")
		end
	end,

	["ventilo propulseur (monde 4) : accessible depuis le checkpoint 17, fait monter au-dessus de la corniche"] = function()
		local spec = Mechanics.LAUNCH
		local w4 = world(4)
		local pad = nil
		for _, d in w4:GetDescendants() do
			if
				d:IsA("BasePart")
				and d:HasTag("Trap")
				and d:GetAttribute("Kind") == "Bounce"
				and d.Name == "LaunchPad"
			then
				pad = d
			end
		end
		Expect.truthy(pad, "pad Bounce du ventilo")
		Expect.equal(pad:GetAttribute("Power"), spec.Power)
		Expect.equal(pad:GetAttribute("Stage"), spec.Stage, "étape (tests de poses)")
		-- Hauteur atteinte : v² / 2g au-dessus du pad ; la corniche doit être en dessous (marge 2)
		local padTop = pad.CFrame.Position.Y + pad.Size.Y / 2
		local apex = padTop + spec.Power * spec.Power / (2 * GRAVITY)
		Expect.truthy(apex >= spec.Ledge.Top + 2, `apex {apex} au-dessus de la corniche {spec.Ledge.Top}`)
		Expect.truthy(spec.Ledge.Top - padTop > JUMP + 2, "corniche inaccessible sans le ventilo")
		-- Dérive horizontale pendant la descente sur la corniche : bord du pad → bord de la corniche
		local fall = math.sqrt(2 * (apex - spec.Ledge.Top) / GRAVITY)
		local rise = spec.Power / GRAVITY
		local gap = (pad.CFrame.Position.X - spec.PadSize / 2) - spec.Ledge.X1
		Expect.truthy(gap <= WALK * (rise + fall) * 0.6, "on atteint la corniche en dérivant")
		-- La plateforme du ventilo touche (presque) le pad du checkpoint 17 : un pas ou un petit saut
		local cp = nil
		for _, d in tower:GetDescendants() do
			if d:IsA("BasePart") and d:HasTag("Checkpoint") and d:GetAttribute("Stage") == spec.Stage then
				cp = d
			end
		end
		Expect.truthy(cp, "checkpoint 17")
		local cpWest = cp.CFrame.Position.X - cp.Size.X / 2
		Expect.between(cpWest - spec.Deck.X1, 0, 5, "écart pad 17 → plateforme du ventilo")
		Expect.truthy(math.abs((cp.CFrame.Position.Y + cp.Size.Y / 2) - spec.Deck.Top) <= 1, "même hauteur")
		-- Trois Bits bonus sur la corniche (hors du compte des 3–6 Bits par étape)
		local coins = 0
		for _, d in w4:GetDescendants() do
			if d:IsA("BasePart") and d:HasTag("Coin") and d:GetAttribute("Bonus") then
				local p = d.CFrame.Position
				if p.X >= spec.Ledge.X0 and p.X <= spec.Ledge.X1 and p.Y > spec.Ledge.Top then
					coins += 1
				end
			end
		end
		Expect.equal(coins, 3, "Bits de la corniche")
	end,

	["bloatware (monde 5) : bloque tout le passage, posé sur le chemin, trop haut pour sauter, désinstallable"] = function()
		local w5 = world(5)
		local list = prompts(w5, "Uninstall")
		Expect.equal(#list, #Mechanics.BLOATWARE, "bloatware")
		for _, prompt in list do
			local block = prompt.Parent
			Expect.truthy(block:HasTag("Bloatware"), "tag (PuzzleService)")
			Expect.truthy(block.CanCollide, "solide : il bloque vraiment")
			Expect.truthy(prompt.HoldDuration > 0, "appui maintenu")
			Expect.truthy(block.Size.Y > JUMP + 0.5, "on ne saute pas par-dessus")
			local bottom = block.CFrame.Position - V3.new(0, block.Size.Y / 2, 0)
			local floor = supportUnder(w5, bottom, 0.3, block)
			Expect.truthy(floor, `{block:GetAttribute("Program")} posé sur une plateforme`)
			-- Largeur : le bloc couvre la plateforme d'un bord à l'autre (en travers du chemin)
			local across = block.CFrame.RightVector
			local function extent(part: any, axis: any): number
				local cf = part.CFrame
				return math.abs(cf.RightVector:Dot(axis)) * part.Size.X
					+ math.abs(cf.UpVector:Dot(axis)) * part.Size.Y
					+ math.abs(cf.LookVector:Dot(axis)) * part.Size.Z
			end
			Expect.truthy(
				extent(block, across) >= extent(floor, across) - 0.01,
				`{block:GetAttribute("Program")} couvre toute la largeur`
			)
			-- Pas sur un checkpoint (ni dans sa marge de 3 studs)
			for _, d in tower:GetDescendants() do
				if d:IsA("BasePart") and d:HasTag("Checkpoint") then
					local dp = (d.CFrame.Position - block.CFrame.Position) * V3.new(1, 0, 1)
					Expect.truthy(dp.Magnitude > 9, "loin des checkpoints")
				end
			end
		end
	end,

	["rôles : quatre rôles, un passif chacun, aucun ne gêne sans rôle"] = function()
		Expect.equal(#Roles.List, 4)
		for _, role in Roles.List do
			Expect.truthy(Roles.IsValid(role.Id), role.Id)
			Expect.truthy(#role.Id <= 16, "id court (RemoteGuard.String(16))")
			Expect.truthy(#role.Passive > 10 and #role.Line > 10, "textes")
		end
		Expect.equal(Roles.IsValid(""), false)
		Expect.equal(Roles.IsValid("Pirate"), false)
		Expect.equal(Roles.GaugeFactor(""), 1)
		Expect.equal(Roles.CleanFactor(nil), 1)
		Expect.equal(Roles.InvestigateFactor("Technicien"), 1)
		Expect.equal(Roles.CheckpointBits(""), 0)
		Expect.truthy(Roles.GaugeFactor("Technicien") < 1, "Technicien : jauges plus lentes")
		Expect.truthy(Roles.CleanFactor("Nettoyeur") > 1, "Nettoyeur : terminaux")
		Expect.equal(Roles.InvestigateFactor("Enqueteur"), 2)
		Expect.equal(Roles.CheckpointBits("Service"), 1)
	end,

	["sauvegarde : enquêtes et rôle complétés sur une ancienne partie"] = function()
		local old: any = { Bits = 10, UsbKeys = { W1K1 = true } }
		Expect.truthy(DataSchema.Migrate(old))
		Expect.equal(type(old.Puzzles), "table")
		Expect.equal(next(old.Puzzles), nil)
		Expect.equal(old.Role, "")
		Expect.equal(old.UsbKeys.W1K1, true, "existant gardé")
	end,
}
