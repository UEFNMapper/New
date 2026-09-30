--!strict
--[[
	Firewall : le pare-feu (un mur de flammes avec un canon) glisse en bas de l'écran et
	tire tout seul. Des virus tombent sur les fichiers du PC : détruis-les avant qu'ils
	n'infectent tous les fichiers !

	Contrôles : glisser le doigt, souris (le pare-feu suit le curseur), flèches / A-D,
	stick gauche ou croix de la manette. Règles et chiffres : FirewallLogic (pur, testé).
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Core = require(script.Parent.Core)
local Common = require(script.Parent.Common)
local FirewallLogic = require(script.Parent.FirewallLogic)

local New = Create.New
local C = Common.Colors
local At = Common.At
local Box = Common.Box

local Firewall = {}

local LEFT_KEYS = { Enum.KeyCode.Left, Enum.KeyCode.A, Enum.KeyCode.Q, Enum.KeyCode.DPadLeft }
local RIGHT_KEYS = { Enum.KeyCode.Right, Enum.KeyCode.D, Enum.KeyCode.DPadRight }
local STICK_DEADZONE = 0.2
local FILE_Y = Core.FIELD_H - 24

function Firewall.Info(difficulty: number, device: Common.Device): Common.Info
	local p = FirewallLogic.Params(difficulty)
	return {
		Title = "PARE-FEU",
		Rule = "Bouge le pare-feu : il tire tout seul !",
		Target = `Détruis {p.Target} virus !`,
		Controls = if device == "Gamepad"
			then "Stick gauche pour bouger"
			elseif device == "Touch" then "Glisse ton doigt à gauche et à droite"
			else "Souris ou flèches ← →",
		Tip = "Astuce : place-toi sous le virus le plus bas !",
		Goal = p.Target,
		Unit = "virus",
		Icon = "Virus",
		Accent = "BrandAnga",
	}
end

-- Pare-feu : mur de briques en flammes + canon. Taille en échelle du parent.
local function buildShield(parent: Instance, size: UDim2, position: UDim2): Frame
	local root: Frame = New("Frame", {
		Name = "Shield",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = parent,
	})
	-- Flammes (derrière le mur)
	for i, x in { 0.18, 0.4, 0.62, 0.84 } do
		local flame =
			Common.Shape(root, UDim2.fromScale(x, 0.08), UDim2.fromScale(0.2, 0.55), C.Gold, UDim.new(0.5, 0), {
				Name = "Flame",
				Rotation = 45,
				ZIndex = 1,
			})
		local flameScale: UIScale = New("UIScale", { Parent = flame })
		Common.Pulse(flameScale, { Scale = 1.25 }, 0.22 + i * 0.04)
	end
	-- Canon
	Common.Shape(root, UDim2.fromScale(0.5, -0.05), UDim2.fromScale(0.16, 0.6), C.Cyan, UDim.new(0.3, 0), {
		Name = "Cannon",
		ZIndex = 2,
	})
	local wall = Common.Shape(root, UDim2.fromScale(0.5, 0.55), UDim2.fromScale(1, 0.9), C.White, UDim.new(0.25, 0), {
		Name = "Wall",
		ZIndex = 3,
	})
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Amber, C.GlitchB), Parent = wall })
	New("UIStroke", { Color = C.Ink, Thickness = 2, Transparency = 0.3, Parent = wall })
	-- Briques
	Common.Shape(wall, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.94, 0.06), C.Ink, nil, {
		Name = "Mortar",
		BackgroundTransparency = 0.55,
	})
	for _, x in { 0.25, 0.5, 0.75 } do
		Common.Shape(wall, UDim2.fromScale(x, 0.27), UDim2.fromScale(0.03, 0.4), C.Ink, nil, {
			Name = "Joint",
			BackgroundTransparency = 0.55,
		})
	end
	for _, x in { 0.125, 0.375, 0.625, 0.875 } do
		Common.Shape(wall, UDim2.fromScale(x, 0.74), UDim2.fromScale(0.03, 0.4), C.Ink, nil, {
			Name = "Joint",
			BackgroundTransparency = 0.55,
		})
	end
	return root
end

function Firewall.Illustrate(parent: Frame)
	for i, x in { 0.3, 0.62 } do
		local virus = Common.Virus({
			Size = UDim2.fromOffset(62, 62),
			Position = UDim2.fromScale(x, 0.2 + i * 0.08),
			Parent = parent,
		})
		Common.Pulse(virus, { Position = UDim2.fromScale(x, 0.36 + i * 0.08) }, 0.9)
	end
	for i = 0, 2 do
		New("Frame", {
			Name = "Shot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.3, 0.56 - i * 0.1),
			Size = UDim2.fromOffset(8, 18),
			BackgroundColor3 = C.Cyan,
			BorderSizePixel = 0,
			Parent = parent,
		}, { Common.Corner() })
	end
	local shield = buildShield(parent, UDim2.fromOffset(120, 36), UDim2.fromScale(0.3, 0.82))
	Common.Pulse(shield, { Position = UDim2.fromScale(0.62, 0.82) }, 1.2)
end

function Firewall.Run(container: Frame, difficulty: number, finish: Common.Finish, hud: Common.Hud?): () -> ()
	local ui = hud or Common.NullHud
	local bin = Common.Bin()
	local sim = FirewallLogic.new(difficulty, Common.Seed())
	local p = sim.Params
	local finished = false

	local stage = Common.Stage(container)
	bin:Add(stage)
	local catcher = Common.Catcher(stage)

	-- Zone à protéger : la rangée de fichiers du PC (une vie par fichier).
	New("Frame", {
		Name = "SafeZone",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = Box(Core.FIELD_W, 52),
		BackgroundColor3 = C.Cyan,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = stage,
	})
	local files: { Frame } = {}
	for i = 1, p.Lives do
		local x = Core.FIELD_W * (i - 0.5) / p.Lives
		table.insert(
			files,
			Common.File({ Size = Box(44, 44), Position = At(x, FILE_Y), ZIndex = 2, Name = `File{i}`, Parent = stage })
		)
	end
	local infected: { [Frame]: boolean } = {}

	local shield = buildShield(
		stage,
		Box(FirewallLogic.SHIELD_HALF_W * 2, FirewallLogic.SHIELD_HALF_H * 2),
		At(sim.ShieldX, FirewallLogic.SHIELD_Y)
	)

	local viruses: { [number]: Frame } = {}
	local bullets: { [number]: Frame } = {}

	local function done(success: boolean)
		if finished then
			return
		end
		finished = true
		finish(success, sim.Kills)
	end

	local function infectNearest(x: number)
		local best: Frame? = nil
		local bestDistance = math.huge
		for _, file in files do
			if not infected[file] then
				local distance = math.abs(file.Position.X.Scale * Core.FIELD_W - x)
				if distance < bestDistance then
					best, bestDistance = file, distance
				end
			end
		end
		if best then
			infected[best] = true
			Common.InfectFile(best)
			Motion.Pop(best, 0.4)
			Common.Burst(stage, best.Position, C.VirusHot, 8, 50)
		end
	end

	local function handle(event: FirewallLogic.Event)
		local kind = event.Kind
		if kind == "Spawn" then
			local data: FirewallLogic.Virus? = nil
			for _, virus in sim.Viruses do
				if virus.Id == event.Id then
					data = virus
				end
			end
			if data then
				local sprite = Common.Virus({
					Size = Box(data.R * 2, data.R * 2),
					Position = At(data.X, data.Y),
					Tough = data.MaxHp > 1,
					ZIndex = 3,
					Parent = stage,
				})
				viruses[event.Id] = sprite
			end
		elseif kind == "Fire" then
			bullets[event.Id] = New("Frame", {
				Name = "Shot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = At(event.X or 0, event.Y or 0),
				Size = Box(10, 26),
				BackgroundColor3 = C.White,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = stage,
			}, {
				Common.Corner(),
				New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.White, C.Cyan) }),
			})
		elseif kind == "BulletGone" then
			local shot = bullets[event.Id]
			bullets[event.Id] = nil
			if shot then
				shot:Destroy()
			end
		elseif kind == "Damage" then
			local sprite = viruses[event.Id]
			if sprite then
				Common.CrackArmor(sprite)
				Common.Glitch(sprite)
				Motion.Pop(sprite, 0.25)
				Common.Burst(stage, sprite.Position, C.Gold, 6, 45)
				Common.Sound("Click", 1.5)
			end
		elseif kind == "Kill" then
			local sprite = viruses[event.Id]
			viruses[event.Id] = nil
			local where = At(event.X or 0, event.Y or 0)
			if sprite then
				sprite:Destroy()
			end
			Common.Burst(stage, where, C.VirusHot, 12, 80)
			Common.Popup(
				stage,
				where,
				if event.Blocked then "BLOQUÉ !" else "+1",
				C.Gold,
				if event.Blocked then 26 else 30
			)
			Common.Sound(if event.Blocked then "Collect" else "Zap", 0.95 + math.random() * 0.2)
			Motion.Pop(shield, 0.12)
			ui.SetProgress(sim.Kills, p.Target)
		elseif kind == "Leak" then
			local sprite = viruses[event.Id]
			viruses[event.Id] = nil
			if sprite then
				sprite:Destroy()
			end
			infectNearest(event.X or Core.FIELD_W / 2)
			Common.Popup(stage, At(event.X or Core.FIELD_W / 2, Core.FIELD_H - 80), "Aïe !", C.Bad, 28)
			Common.Sound("Error")
			Common.Shake(stage, 10, 0.3)
			ui.SetLives(FirewallLogic.LivesLeft(sim), p.Lives)
		elseif kind == "Win" then
			done(true)
		elseif kind == "Lose" then
			done(false)
		end
	end

	-- Entrées ------------------------------------------------------------------------
	GuiService.SelectedObject = nil -- le stick sert à bouger, pas à naviguer
	local held: { [Enum.KeyCode]: boolean } = {}
	local stickX = 0
	local dragInput: InputObject? = nil
	local pointerX: number? = nil

	local function setPointer(position: Vector3)
		pointerX = Common.ToField(stage, position).X
	end

	bin:Add(catcher.InputBegan:Connect(function(input: InputObject)
		if Common.IsPress(input) then
			dragInput = input
			setPointer(input.Position)
		end
	end))
	bin:Add(UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x = input.Position.X
			stickX = if math.abs(x) > STICK_DEADZONE then x else 0
		elseif
			input == dragInput
			-- Souris : le pare-feu suit le curseur, sans cliquer.
			or (input.UserInputType == Enum.UserInputType.MouseMovement and Common.Inside(stage, input.Position))
		then
			setPointer(input.Position)
		end
	end))
	bin:Add(UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == dragInput then
			dragInput = nil
			if input.UserInputType == Enum.UserInputType.Touch then
				pointerX = nil
				FirewallLogic.SetPointer(sim, nil)
			end
		end
		held[input.KeyCode] = nil
	end))
	-- (on ignore seulement la saisie de texte, pas les actions déjà liées au personnage)
	bin:Add(UserInputService.InputBegan:Connect(function(input: InputObject)
		if not UserInputService:GetFocusedTextBox() then
			held[input.KeyCode] = true
		end
	end))

	local function axis(): number
		local value = stickX
		for _, key in LEFT_KEYS do
			if held[key] then
				value -= 1
				break
			end
		end
		for _, key in RIGHT_KEYS do
			if held[key] then
				value += 1
				break
			end
		end
		return math.clamp(value, -1, 1)
	end

	ui.SetProgress(0, p.Target)
	ui.SetLives(p.Lives, p.Lives)
	ui.SetTimer(FirewallLogic.TimeLeft(sim))

	Common.Loop(bin, function(dt: number)
		if finished then
			return
		end
		local direction = axis()
		FirewallLogic.SetAxis(sim, direction)
		if direction ~= 0 then
			pointerX = nil
		elseif pointerX then
			FirewallLogic.SetPointer(sim, pointerX)
		end
		for _, event in FirewallLogic.Step(sim, dt) do
			handle(event)
		end
		-- Affichage
		shield.Position = At(sim.ShieldX, FirewallLogic.SHIELD_Y)
		for _, virus in sim.Viruses do
			local sprite = viruses[virus.Id]
			if sprite then
				sprite.Position = At(virus.X, virus.Y)
				if math.random() < 0.008 then
					Common.Glitch(sprite)
				end
			end
		end
		for _, bullet in sim.Bullets do
			local shot = bullets[bullet.Id]
			if shot then
				shot.Position = At(bullet.X, bullet.Y)
			end
		end
		ui.SetTimer(FirewallLogic.TimeLeft(sim))
	end, function()
		done(false)
	end)

	return function()
		finished = true
		bin:Clean()
	end
end

return Firewall
