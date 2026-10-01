--!strict
--[[
	Defense : « Défense du CPU » (arcade). Des virus remontent les trois bus de données vers le
	processeur : installe des antivirus sur les emplacements (⚡ énergie) pour les arrêter avant
	qu'ils l'atteignent. Chaque antivirus tire sur le virus le plus avancé de son bus.

	Contrôles : doigt / clic sur un emplacement libre ; manette / clavier : sélectionner un
	emplacement puis A / Entrée. Règles et chiffres : DefenseLogic (pur, testé).
]]

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.Create)
local Motion = require(script.Parent.Parent.Motion)
local Icon = require(script.Parent.Parent.Components.Icon)
local Common = require(script.Parent.Common)
local DefenseLogic = require(script.Parent.DefenseLogic)

local New = Create.New
local C = Common.Colors
local At = Common.At
local Box = Common.Box

local Defense = {}

local SLOT_SIZE = 86
local VIRUS_SIZE = 64

function Defense.Info(difficulty: number, device: Common.Device): Common.Info
	local p = DefenseLogic.Params(difficulty)
	return {
		Title = "DÉFENSE DU CPU",
		Rule = "Installe des antivirus sur les bus : aucun virus ne doit toucher le processeur !",
		Target = `Élimine {p.Target} virus !`,
		Controls = if device == "Gamepad"
			then "Choisis un emplacement, A pour installer"
			elseif device == "Touch" then "Tape un emplacement libre (⚡ {p.Cost})"
			else "Clique un emplacement libre (⚡ {p.Cost})",
		Tip = "Astuce : un antivirus par bus d'abord, puis renforce celui qui déborde !",
		Goal = p.Target,
		Unit = "virus",
		Icon = "Cpu",
		Accent = "AccentViolet",
	}
end

-- Illustration : le processeur, un antivirus et un virus qui arrive.
function Defense.Illustrate(parent: Frame)
	local cpu = Icon.new("Cpu", 70, "AccentCyan")
	cpu.AnchorPoint = Vector2.new(0.5, 0.5)
	cpu.Position = UDim2.fromScale(0.18, 0.5)
	cpu.Parent = parent
	local shield = Icon.new("Bot", 54, "Success")
	shield.AnchorPoint = Vector2.new(0.5, 0.5)
	shield.Position = UDim2.fromScale(0.45, 0.5)
	shield.Parent = parent
	Common.Virus({ Size = UDim2.fromOffset(70, 70), Position = UDim2.fromScale(0.78, 0.5), Parent = parent })
end

function Defense.Run(container: Frame, difficulty: number, finish: Common.Finish, hud: Common.Hud?): () -> ()
	local ui = hud or Common.NullHud
	local bin = Common.Bin()
	local sim = DefenseLogic.new(difficulty, Common.Seed())
	local p = sim.Params
	local finished = false

	local stage = Common.Stage(container)
	bin:Add(stage)

	local function done(success: boolean)
		if finished then
			return
		end
		finished = true
		finish(success, sim.Kills)
	end

	-- Bus de données (bandes), processeur à gauche
	for lane = 1, DefenseLogic.LANES do
		local y = DefenseLogic.LANE_Y[lane]
		local strip = Common.Shape(stage, At(520, y), Box(800, 96), C.Screen, UDim.new(0, 14), {
			Name = `Bus{lane}`,
			ZIndex = 1,
		})
		for k = 0, 2 do
			Common.Shape(strip, UDim2.fromScale(0.5, 0.25 + k * 0.25), UDim2.fromScale(0.98, 0.03), C.Cyan, nil, {
				Name = "Trace",
				BackgroundTransparency = 0.75,
			})
		end
	end
	local cpu: Frame = New("Frame", {
		Name = "Cpu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = At(DefenseLogic.CPU_X, 265),
		Size = Box(120, 380),
		BackgroundColor3 = C.Raised,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = stage,
	}, {
		Common.Corner(UDim.new(0, 14)),
		New("UIStroke", { Color = C.Cyan, Thickness = 3 }),
	})
	local chip = Icon.new("Cpu", 64, "AccentCyan")
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.Position = UDim2.fromScale(0.5, 0.42)
	chip.ZIndex = 3
	chip.Parent = cpu
	local hpLabel: TextLabel = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(0.9, 0.1),
		BackgroundTransparency = 1,
		Text = "CPU",
		TextScaled = true,
		TextColor3 = C.White,
		Tag = "FontHeavy",
		ZIndex = 3,
		Parent = cpu,
	}, { New("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 18 }) })

	-- Énergie (en haut à gauche du terrain)
	local energy: TextLabel = New("TextLabel", {
		Name = "Energy",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = At(150, 40),
		Size = Box(260, 46),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.25,
		Text = "",
		TextScaled = true,
		TextColor3 = C.Gold,
		Tag = "FontHeavy",
		ZIndex = 6,
		Parent = stage,
	}, {
		Common.Corner(UDim.new(1, 0)),
		New("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 18 }),
	})

	-- Emplacements
	type SlotView = { Button: TextButton, Stroke: UIStroke, Plus: TextLabel, Turret: Frame? }
	local slots: { [number]: SlotView } = {}
	local build: (slot: number) -> ()

	for slot = 1, DefenseLogic.LANES * DefenseLogic.COLUMNS do
		local x, y = DefenseLogic.SlotPosition(slot)
		local button: TextButton = New("TextButton", {
			Name = `Slot{slot}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = At(x, y),
			Size = Box(SLOT_SIZE, SLOT_SIZE),
			BackgroundColor3 = C.Raised,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Selectable = true,
			ZIndex = 3,
			Parent = stage,
		}, { Common.Corner(UDim.new(0, 12)) })
		local stroke: UIStroke = New("UIStroke", { Color = C.Gold, Thickness = 2, Transparency = 0.4, Parent = button })
		local plus: TextLabel = New("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = `+\n⚡{p.Cost}`,
			TextScaled = true,
			TextColor3 = C.Gold,
			Tag = "FontHeavy",
			ZIndex = 4,
			Parent = button,
		}, { New("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 18 }) })
		slots[slot] = { Button = button, Stroke = stroke, Plus = plus, Turret = nil }
		bin:Add(button.InputBegan:Connect(function(input: InputObject)
			if Common.IsPress(input) then
				build(slot)
			end
		end))
		bin:Add(button.Activated:Connect(function()
			local last = UserInputService:GetLastInputType()
			if string.find(last.Name, "^Gamepad") or last == Enum.UserInputType.Keyboard then
				build(slot)
			end
		end))
	end

	-- Virus affichés
	local sprites: { [number]: Frame } = {}

	local function beam(slot: number, id: number)
		local sprite = sprites[id]
		if not sprite then
			return
		end
		local x, y = DefenseLogic.SlotPosition(slot)
		local target = sprite.Position
		local tx = target.X.Scale * 900
		local length = math.max(tx - x, 10)
		local ray = Common.Shape(stage, At(x + length / 2, y), Box(length, 6), C.Good, UDim.new(1, 0), {
			Name = "Beam",
			ZIndex = 5,
			BackgroundTransparency = 0.2,
		})
		Motion.Tween(ray, { BackgroundTransparency = 1 }, 0.15)
		task.delay(0.16, function()
			ray:Destroy()
		end)
	end

	local function handle(event: DefenseLogic.Event)
		if event.Kind == "Spawn" and event.Id and event.Lane then
			local sprite = Common.Virus({
				Size = Box(VIRUS_SIZE, VIRUS_SIZE),
				Position = At(DefenseLogic.SPAWN_X, DefenseLogic.LANE_Y[event.Lane]),
				Parent = stage,
				ZIndex = 4,
				Tough = event.Tough,
			})
			sprites[event.Id] = sprite
		elseif event.Kind == "Shot" and event.Slot and event.Id then
			beam(event.Slot, event.Id)
			Common.Sound("Zap", 1.3)
		elseif event.Kind == "Kill" and event.Id then
			local sprite = sprites[event.Id]
			sprites[event.Id] = nil
			if sprite then
				Common.Burst(stage, sprite.Position, C.VirusHot, 8, 50)
				sprite:Destroy()
			end
			ui.SetProgress(sim.Kills, p.Target)
		elseif event.Kind == "Leak" and event.Id then
			local sprite = sprites[event.Id]
			sprites[event.Id] = nil
			if sprite then
				sprite:Destroy()
			end
			Common.Sound("Error")
			Common.Shake(stage, 10, 0.3)
			Common.Popup(stage, At(DefenseLogic.CPU_X + 60, 120), "-1 CPU", C.Bad, 26)
			ui.SetLives(sim.CpuHp, p.CpuHp)
		elseif event.Kind == "Build" and event.Slot then
			local view = slots[event.Slot]
			view.Plus.Visible = false
			view.Stroke.Color = C.Good
			view.Stroke.Transparency = 0
			local turret = Icon.new("Bot", 54, "Success")
			turret.AnchorPoint = Vector2.new(0.5, 0.5)
			turret.Position = UDim2.fromScale(0.5, 0.5)
			turret.ZIndex = 4
			turret.Parent = view.Button
			view.Turret = turret
			Motion.Pop(view.Button, 0.25)
			Common.Sound("PowerOn", 1.4)
		elseif event.Kind == "NoEnergy" and event.Slot then
			local x, y = DefenseLogic.SlotPosition(event.Slot)
			Common.Popup(stage, At(x, y - 50), "Pas assez d'⚡", C.Amber, 22)
		elseif event.Kind == "Win" then
			done(true)
		elseif event.Kind == "Lose" or event.Kind == "Timeout" then
			done(false)
		end
	end

	build = function(slot: number)
		if finished then
			return
		end
		for _, event in DefenseLogic.Build(sim, slot) do
			handle(event)
		end
	end

	ui.SetProgress(0, p.Target)
	ui.SetLives(sim.CpuHp, p.CpuHp)
	ui.SetTimer(nil)
	Common.Focus(slots[2].Button)
	local hint = Common.Hint(stage, "Pose un antivirus sur chaque bus !", 0.94)
	task.delay(4, function()
		if hint.Parent then
			hint:Destroy()
		end
	end)

	Common.Loop(bin, function(dt: number)
		if finished then
			return
		end
		for _, event in DefenseLogic.Step(sim, dt) do
			handle(event)
			if finished then
				return
			end
		end
		for _, virus in sim.Viruses do
			local sprite = sprites[virus.Id]
			if sprite then
				sprite.Position = At(virus.X, DefenseLogic.LANE_Y[virus.Lane])
			end
		end
		energy.Text = `⚡ {math.floor(sim.Energy)} · antivirus ⚡{p.Cost}`
		hpLabel.Text = `CPU {sim.CpuHp}/{p.CpuHp}`
		local affordable = sim.Energy >= p.Cost
		for slot, view in slots do
			if not sim.Turrets[slot] then
				view.Stroke.Transparency = if affordable then 0.1 else 0.7
				view.Plus.TextTransparency = if affordable then 0 else 0.5
			end
		end
	end, function()
		done(false)
	end)

	return function()
		finished = true
		Common.Unfocus(stage)
		bin:Clean()
	end
end

return Defense
