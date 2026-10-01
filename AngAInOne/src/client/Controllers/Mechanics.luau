--!strict
--[[
	Mechanics (client) : les mécaniques « PC » des mondes (serveur : World/Tower/Mechanics) et les
	petites interactions du lobby (BIOS caché, Stream Deck).
	- Monde 2 · RAM : la jauge (Util/Gauges) se remplit pendant l'ascension du monde ; au-delà de 70 %,
	  la marche AU SOL ralentit (jusqu'à × 0,6 ; les sauts gardent leur portée). Les gros boutons
	  « Libérer la RAM » la vident (cooldown par bouton).
	- Monde 4 · chaleur : monte quand on court, redescend à l'arrêt, vite près d'une zone fraîche
	  (ventilateurs géants, ventilateurs relancés). À 100 °C : arrêt thermique (mort, retour au checkpoint).
	- Monde 6 · artefacts GPU : tant que le monde est infecté, de brefs artefacts graphiques (désactivés
	  avec « Réduire les animations »).
	- Monde 1 et 7 · enquêtes : PuzzleAnswer au serveur, indice ou victoire en retour (Fx "Puzzle").
	- Monde 5 · bloatware : désinstallé localement (prompt maintenu), Bits la première fois (Fx).
	- Rôle Technicien (Config/Roles) : les jauges montent 25 % moins vite.
	Les jauges sont en pause dans la salle du terminal, pendant un mini-jeu, et une fois le monde nettoyé.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Puzzles = require(Shared.Config.Puzzles)
local Roles = require(Shared.Config.Roles)
local Gauges = require(Shared.Util.Gauges)

local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local SpeedControl = require(script.Parent.SpeedControl)
local TrapController = require(script.Parent.TrapController)
local Interactions = require(script.Parent.Interactions)
local Feedback = require(script.Parent.Feedback)
local Companion = require(script.Parent.Companion)
local Motion = require(script.Parent.Parent.UI.Motion)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)
local Dialogue = require(script.Parent.Parent.UI.Screens.Dialogue)
local HUD = require(script.Parent.Parent.UI.Screens.HUD)
local MinigamePanel = require(script.Parent.Parent.UI.Screens.MinigamePanel)

local Mechanics = {}

local RAM_WORLD, HEAT_WORLD, GPU_WORLD, BLOAT_WORLD = 2, 4, 6, 5
local RAM_WARN = 85
local GPU_EVERY = { 7, 12 } -- s entre deux artefacts
local GPU_DURATION = 0.35
local DECK_SLOW_SECONDS = 6

local player = Players.LocalPlayer
local ram = 0
local heat = Gauges.HEAT_IDLE
local ramWarned = false
local heatWarned = false
local lastFlush: { [number]: number } = {}
local startedFans: { [number]: boolean } = {}
local spinning: { { Hub: BasePart, Blades: { { Part: BasePart, Offset: CFrame } } } } = {}
local removedBloat: { [number]: { Part: BasePart, Size: Vector3, Transparency: number } } = {}
local introShown: { [number]: boolean } = {}
local nextGlitch = os.clock() + 6
local glitchSaid = false
local deckUntil = 0

------------------------------------------------------------------------------------
-- Contexte : monde courant, pauses
------------------------------------------------------------------------------------

type Context = { World: number, Active: boolean, Data: any }

local function context(): Context
	local state = Store.State
	if not state or not state.Data then
		return { World = 0, Active = false, Data = nil }
	end
	local data = state.Data
	if state.AtLobby or data.Stage <= 0 then
		return { World = 0, Active = false, Data = data }
	end
	local world = Tower.RunWorld(data.Stage, data.Cleared)
	local inRoom = data.Stage == Tower.TerminalStage(world)
	local active = not inRoom and data.Cleared < world and not MinigamePanel.IsPlaying()
	return { World = world, Active = active, Data = data }
end

local function rootAndHumanoid(): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

------------------------------------------------------------------------------------
-- Zones fraîches (monde 4)
------------------------------------------------------------------------------------

local function zoneActive(zone: Instance): boolean
	if zone:GetAttribute("NeedsStart") ~= true then
		return true
	end
	local index = zone:GetAttribute("Index")
	return type(index) == "number" and startedFans[index] == true
end

local function inCoolZone(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged("CoolZone") do
		if zone:IsA("BasePart") and zoneActive(zone) then
			local radius = zone:GetAttribute("Radius")
			local r = if type(radius) == "number" then radius else Gauges.COOL_ZONE_RADIUS
			if (zone.Position - position).Magnitude <= r then
				return true
			end
		end
	end
	return false
end

------------------------------------------------------------------------------------
-- Jauges
------------------------------------------------------------------------------------

local function stepRam(ctx: Context, dt: number, humanoid: Humanoid?)
	if ctx.World == RAM_WORLD and ctx.Active then
		ram = Gauges.RamStep(ram, dt * Roles.GaugeFactor(ctx.Data.Role))
	elseif ctx.World ~= RAM_WORLD then
		ram = 0
	end
	local grounded = humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
	local slow = ctx.World == RAM_WORLD and ctx.Active and grounded
	SpeedControl.SetFactor("Ram", if slow then Gauges.RamSpeedFactor(ram) else nil)
	if ctx.World == RAM_WORLD and ctx.Data and ctx.Data.Cleared < RAM_WORLD then
		local value = math.floor(ram + 0.5)
		local grade = if value >= RAM_WARN then "Bad" elseif value >= Gauges.RAM_SLOW_FROM then "Warn" else "Good"
		HUD.SetGauge(`💾 RAM {value} %`, ram / 100, grade)
		if value >= RAM_WARN and not ramWarned then
			ramWarned = true
			Dialogue.Say("La RAM est saturée, tu rames ! Appuie sur un gros bouton « Libérer la RAM ».", 5, "AIO")
		elseif value < Gauges.RAM_SLOW_FROM then
			ramWarned = false
		end
	end
end

local function stepHeat(ctx: Context, dt: number, root: BasePart?)
	if ctx.World ~= HEAT_WORLD then
		heat = Gauges.HEAT_IDLE
		return
	end
	if ctx.Data and ctx.Data.Cleared >= HEAT_WORLD then
		return
	end
	if ctx.Active and root then
		local v = root.AssemblyLinearVelocity
		local moving = Vector3.new(v.X, 0, v.Z).Magnitude > 4
		local cool = inCoolZone(root.Position)
		local scaled = if moving and not cool then dt * Roles.GaugeFactor(ctx.Data.Role) else dt
		heat = Gauges.HeatStep(heat, scaled, moving, cool)
		if heat >= Gauges.HEAT_MAX then
			heat = Gauges.HEAT_IDLE
			heatWarned = false
			TrapController.Kill("ThermalShutdown")
			Toasts.Show("Boost", "Arrêt thermique ! 100 °C : le PC s'est éteint pour se protéger.")
			return
		end
	end
	local value = math.floor(heat + 0.5)
	local state = Gauges.HeatState(heat)
	local grade = if state == "Warn" or state == "Crash" then "Bad" elseif state == "Hot" then "Warn" else "Good"
	HUD.SetGauge(`🌡 CPU {value} °C`, (heat - Gauges.HEAT_IDLE) / (Gauges.HEAT_MAX - Gauges.HEAT_IDLE), grade)
	if heat >= Gauges.HEAT_WARN and not heatWarned then
		heatWarned = true
		Dialogue.Say("Ça chauffe ! Arrête-toi un instant, ou passe près d'un ventilateur qui tourne.", 5, "AIO")
	elseif heat < 65 then
		heatWarned = false
	end
end

------------------------------------------------------------------------------------
-- Artefacts graphiques (monde 6)
------------------------------------------------------------------------------------

local glitchGui: ScreenGui? = nil

local function glitch()
	local gui = glitchGui
	if not gui then
		local created = Instance.new("ScreenGui")
		created.Name = "GpuArtifacts"
		created.IgnoreGuiInset = true
		created.ResetOnSpawn = false
		created.DisplayOrder = 3
		created.Parent = player:WaitForChild("PlayerGui")
		glitchGui = created
		gui = created
	end
	local root = gui :: ScreenGui
	local colors = { Color3.fromRGB(0, 255, 170), Color3.fromRGB(255, 0, 200), Color3.fromRGB(80, 160, 255) }
	local rng = Random.new()
	for i = 1, rng:NextInteger(4, 7) do
		local block = Instance.new("Frame")
		block.BorderSizePixel = 0
		block.BackgroundColor3 = colors[(i % #colors) + 1]
		block.BackgroundTransparency = 0.55
		block.Position = UDim2.fromScale(rng:NextNumber(0, 0.9), rng:NextNumber(0, 0.9))
		block.Size = UDim2.fromScale(rng:NextNumber(0.04, 0.22), rng:NextNumber(0.006, 0.05))
		block.Parent = root
		task.delay(GPU_DURATION, function()
			block:Destroy()
		end)
	end
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "GpuArtifactTint"
	tint.Saturation = -0.25
	tint.TintColor = Color3.fromRGB(235, 220, 255)
	tint.Parent = Lighting
	task.delay(GPU_DURATION, function()
		tint:Destroy()
	end)
	if not glitchSaid then
		glitchSaid = true
		Dialogue.Say("Des artefacts à l'écran : la carte graphique est infectée. Nettoie son terminal !", 5, "AIO")
	end
end

local function stepGpu(ctx: Context)
	if ctx.World ~= GPU_WORLD or not ctx.Active or Motion.IsReduced() then
		return
	end
	local now = os.clock()
	if now >= nextGlitch then
		nextGlitch = now + Random.new():NextNumber(GPU_EVERY[1], GPU_EVERY[2])
		glitch()
	end
end

------------------------------------------------------------------------------------
-- Ventilateurs relancés : rotation locale des pales
------------------------------------------------------------------------------------

local spinAngle = 0
local function stepFans(dt: number)
	if #spinning == 0 then
		return
	end
	spinAngle += dt * math.pi * 2 * 1.5
	for _, fan in spinning do
		local hubCf = fan.Hub.CFrame
		for _, blade in fan.Blades do
			blade.Part.CFrame = hubCf * CFrame.Angles(spinAngle, 0, 0) * blade.Offset
		end
	end
end

------------------------------------------------------------------------------------
-- Prompts
------------------------------------------------------------------------------------

local function promptIndex(prompt: ProximityPrompt): number?
	local index = prompt:GetAttribute("Index")
	return if type(index) == "number" then index else nil
end

local function flushRam(prompt: ProximityPrompt)
	local index = promptIndex(prompt)
	if not index then
		return
	end
	local now = os.clock()
	if not Gauges.CanFlush(now, lastFlush[index]) then
		local left = math.ceil(Gauges.RAM_FLUSH_COOLDOWN - (now - (lastFlush[index] or now)))
		Toasts.Show("Info", `Ce bouton recharge… encore {left} s.`)
		return
	end
	lastFlush[index] = now
	local freed = math.floor(ram + 0.5)
	ram = 0
	ramWarned = false
	Audio.Play("PowerOn", 1.2)
	Toasts.Show("Success", `RAM libérée : {freed} % → 0 % ! (comme fermer les onglets inutiles)`)
	local cap = prompt.Parent
	if cap and cap:IsA("BasePart") then
		local color = cap.Color
		cap.Color = Color3.fromHex("6CCB5F")
		task.delay(1.2, function()
			cap.Color = color
		end)
	end
end

local function startFan(prompt: ProximityPrompt)
	local index = promptIndex(prompt)
	if not index or startedFans[index] then
		return
	end
	startedFans[index] = true
	prompt.Enabled = false
	local housing = prompt.Parent
	local unit = if housing then housing.Parent else nil
	if not unit then
		return
	end
	Audio.Play("PowerOn", 0.9)
	Toasts.Show("Success", "Ventilateur relancé : zone fraîche ❄️ (reste à côté pour refroidir)")
	local hub: BasePart? = nil
	local blades = {}
	for _, part in unit:GetChildren() do
		if part:IsA("BasePart") then
			if part.Name == "FanDust" then
				TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			elseif part.Name == "FanLed" then
				part.Color = Color3.fromHex("6CCB5F")
			elseif part.Name == "FanHub" then
				hub = part
			end
		end
	end
	if hub then
		local hubCf = (hub :: BasePart).CFrame
		for _, part in unit:GetChildren() do
			if part:IsA("BasePart") and part.Name == "Blade" then
				table.insert(blades, { Part = part, Offset = hubCf:ToObjectSpace(part.CFrame) })
			end
		end
		table.insert(spinning, { Hub = hub :: BasePart, Blades = blades })
	end
end

local function answerPuzzle(prompt: ProximityPrompt)
	local world, item = prompt:GetAttribute("World"), prompt:GetAttribute("Item")
	if type(world) == "number" and type(item) == "string" then
		Net.Fire("PuzzleAnswer", world, item)
	end
end

local function uninstall(prompt: ProximityPrompt)
	local index = promptIndex(prompt)
	local world = prompt:GetAttribute("World")
	local block = prompt.Parent
	if not index or type(world) ~= "number" or not (block and block:IsA("BasePart")) or removedBloat[index] then
		return
	end
	removedBloat[index] = { Part = block, Size = block.Size, Transparency = block.Transparency }
	prompt.Enabled = false
	block.CanCollide = false
	Audio.Play("Collect", 0.7)
	local program = block:GetAttribute("Program")
	Toasts.Show("Success", `Désinstallé : {if type(program) == "string" then program else "bloatware"} 🗑`)
	TweenService:Create(block, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = block.Size * Vector3.new(1, 0.05, 1),
		Transparency = 1,
	}):Play()
	for _, gui in block:GetChildren() do
		if gui:IsA("SurfaceGui") then
			gui.Enabled = false
		end
	end
	local edge = block.Parent and block.Parent:FindFirstChild("BloatwareEdge")
	if edge and edge:IsA("BasePart") then
		edge.LocalTransparencyModifier = 1
	end
	Net.Fire("Uninstall", world, index)
end

-- Nouvelle ascension (retour sous le monde 5) : les bloatware se réinstallent (c'est leur spécialité).
local function restoreBloatware(data: any)
	if not data or data.Stage >= Tower.FirstStage(BLOAT_WORLD) then
		return
	end
	for index, saved in removedBloat do
		local block = saved.Part
		if block.Parent then
			block.Size = saved.Size
			block.Transparency = saved.Transparency
			block.CanCollide = true
			for _, gui in block:GetChildren() do
				if gui:IsA("SurfaceGui") or gui:IsA("ProximityPrompt") then
					(gui :: any).Enabled = true
				end
			end
			local edge = block.Parent and block.Parent:FindFirstChild("BloatwareEdge")
			if edge and edge:IsA("BasePart") then
				edge.LocalTransparencyModifier = 0
			end
		end
		removedBloat[index] = nil
	end
end

local function teleport(prompt: ProximityPrompt, line: string?)
	local to = prompt:GetAttribute("To")
	local character = player.Character
	if typeof(to) ~= "Vector3" or not character then
		return
	end
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(to)
		end)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
		end
		character:PivotTo(CFrame.new(to))
		Audio.Play("PowerOn", 0.8)
		if line then
			Dialogue.Say(line, 6, "AIO")
		end
	end)
end

local function streamDeck(prompt: ProximityPrompt)
	local action = prompt:GetAttribute("Deck")
	if action == "Pet" then
		Companion.React("Happy", 3)
		Audio.Play("Collect", 1.4)
		Toasts.Show("Reward", "Pet ! Mini-Anga adore les caresses. 😄")
	elseif action == "Confetti" then
		Feedback.Confetti(nil, 80)
		Audio.Play("Achievement", 1.2)
		Toasts.Show("Reward", "Confettis ! 🎉 (le bouton le plus utilisé du live)")
	elseif action == "Slow" then
		deckUntil = os.clock() + DECK_SLOW_SECONDS
		SpeedControl.SetFactor("Deck", 0.5)
		Toasts.Show("Info", "Mode lent activé : c'est ça, un PC sans SSD. (6 s)")
		task.delay(DECK_SLOW_SECONDS, function()
			if os.clock() >= deckUntil - 0.05 then
				SpeedControl.SetFactor("Deck", nil)
			end
		end)
	end
end

------------------------------------------------------------------------------------
-- Retours du serveur
------------------------------------------------------------------------------------

local function findItem(world: number, id: string): Puzzles.Item?
	local puzzle = Puzzles.ForWorld(world)
	if not puzzle then
		return nil
	end
	for _, item in puzzle.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

local function onFx(kind: string, payload: any)
	if type(payload) ~= "table" then
		return
	end
	if kind == "Puzzle" then
		local puzzle = Puzzles.ForWorld(payload.World)
		if not puzzle then
			return
		end
		if payload.Already then
			Toasts.Show("Success", "Enquête déjà résolue ✓ Le coupable est hors d'état de nuire.")
		elseif payload.Ok then
			Audio.Play("Achievement")
			Feedback.Confetti(nil, 60)
			Toasts.Show("Milestone", `🔎 Enquête résolue : +{payload.Bits or 0} Bits`)
			Dialogue.Say(puzzle.Success, 6, "AIO")
			Companion.React("Celebrate", 3)
		else
			Audio.Play("Error")
			local item = findItem(payload.World, payload.Item)
			Dialogue.Say(if item and item.Hint then item.Hint else "Pas lui… Regarde mieux les indices.", 4, "AIO")
		end
	elseif kind == "Uninstalled" then
		Toasts.Show("Reward", `Bloatware désinstallé : +{payload.Bits or 0} Bits (une fois pour toutes)`)
	elseif kind == "Role" then
		local role = Roles.ById[payload.Id]
		if role then
			Toasts.Show("Success", `Rôle choisi : {role.Name}`)
			Dialogue.Say(role.Line, 5)
		else
			Toasts.Show("Info", "Plus de rôle : tu joues en solo libre.")
		end
	end
end

local function onState(state: any)
	local data = state and state.Data
	if not data then
		return
	end
	restoreBloatware(data)
	for _, world in { 1, Tower.WORLD_COUNT } do
		local puzzle = Puzzles.ForWorld(world)
		if
			puzzle
			and not introShown[world]
			and data.Stage == Tower.TerminalStage(world)
			and not (data.Puzzles and data.Puzzles[`W{world}`])
		then
			introShown[world] = true
			task.delay(2.5, function()
				Dialogue.Say(puzzle.Intro, 6, "AIO")
			end)
		end
	end
end

------------------------------------------------------------------------------------

function Mechanics.Start()
	Interactions.Register("FlushRam", flushRam)
	Interactions.Register("FanStart", startFan)
	Interactions.Register("Puzzle", answerPuzzle)
	Interactions.Register("Uninstall", uninstall)
	Interactions.Register("Bios", function(prompt: ProximityPrompt)
		teleport(prompt, "BIOS Setup Utility. Ici, on ne touche à rien sans savoir. F10 pour sortir.")
	end)
	Interactions.Register("BiosExit", function(prompt: ProximityPrompt)
		teleport(prompt, nil)
	end)
	Interactions.Register("Deck", streamDeck)
	Net.On("Fx", onFx)
	Store.Changed:Connect(onState)
	player.CharacterAdded:Connect(function()
		heat = Gauges.HEAT_IDLE
		heatWarned = false
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		stepFans(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		local step = accumulator
		accumulator = 0
		local ctx = context()
		local root, humanoid = rootAndHumanoid()
		stepRam(ctx, step, humanoid)
		stepHeat(ctx, step, root)
		stepGpu(ctx)
		if ctx.World ~= RAM_WORLD and ctx.World ~= HEAT_WORLD then
			HUD.SetGauge(nil, 0, "Good")
		end
	end)
end

return Mechanics
