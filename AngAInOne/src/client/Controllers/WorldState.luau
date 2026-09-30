--!strict
--[[
	WorldState : décor « infecté » / « propre » de chaque monde, POUR LE JOUEUR LOCAL
	(docs/SCENARIO.md §3, contrat docs/ROADMAP.md).
	- Tag "Infected" (+ attribut World) : visible seulement tant que data.Cleared < World
	- Tag "Cleaned"  (+ attribut World) : visible seulement quand data.Cleared >= World
	Masquer = LocalTransparencyModifier (pièces, décalques), Enabled = false (lumières,
	particules, faisceaux, SurfaceGui, BillboardGui…) et pas de collision locale (aucun mur
	invisible). Le tag peut être posé sur une pièce ou sur un modèle entier.
	Compatible StreamingEnabled : CollectionService + DescendantAdded (les enfants d'un
	modèle arrivent après lui).
	Quand un monde est nettoyé : « vague de nettoyage » qui part du joueur (le décor infecté
	s'efface en étincelles, le décor propre apparaît) + balayage lumineux à l'écran.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local Motion = require(script.Parent.Parent.UI.Motion)
local Create = require(script.Parent.Parent.UI.Create)
local Style = require(script.Parent.Parent.UI.Style)

local New = Create.New

local WorldState = {}

type Entry = {
	Root: Instance,
	World: number,
	Infected: boolean, -- true : tag Infected ; false : tag Cleaned
	Hidden: boolean?,
	Added: RBXScriptConnection?,
}

local player = Players.LocalPlayer
local entries: { [string]: { [Instance]: Entry } } = { Infected = {}, Cleaned = {} }
-- Valeurs d'origine (avant toute modification) : Enabled, CanCollide.
local originalEnabled: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local originalCollide: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local cleared = -1 -- inconnu tant que le premier état n'est pas arrivé
local waveGui: ScreenGui? = nil

local WAVE_SPEED = 90 -- studs par seconde
local WAVE_MAX_DELAY = 2.2
local FADE_SECONDS = 0.45

local function isToggle(instance: Instance): boolean
	return instance:IsA("Light")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Fire")
		or instance:IsA("Smoke")
		or instance:IsA("Sparkles")
		or instance:IsA("SurfaceGui")
		or instance:IsA("BillboardGui")
		or instance:IsA("Highlight")
end

-- Applique l'état (caché ou non) à une instance, sans toucher à ses descendants.
local function applyOne(instance: Instance, hidden: boolean)
	if instance:IsA("BasePart") then
		instance.LocalTransparencyModifier = if hidden then 1 else 0
		if originalCollide[instance] == nil then
			originalCollide[instance] = instance.CanCollide
		end
		instance.CanCollide = if hidden then false else originalCollide[instance]
	elseif instance:IsA("Decal") then
		-- Decal et Texture
		instance.LocalTransparencyModifier = if hidden then 1 else 0
	elseif isToggle(instance) then
		local object = instance :: any
		if originalEnabled[instance] == nil then
			originalEnabled[instance] = object.Enabled == true
		end
		object.Enabled = if hidden then false else originalEnabled[instance]
	end
end

local function applyTree(root: Instance, hidden: boolean)
	applyOne(root, hidden)
	for _, descendant in root:GetDescendants() do
		applyOne(descendant, hidden)
	end
end

local function worldOf(instance: Instance): number
	local current: Instance? = instance
	while current and current ~= Workspace do
		local world = current:GetAttribute("World")
		if type(world) == "number" then
			return world
		end
		current = current.Parent
	end
	return 0
end

local function shouldHide(entry: Entry): boolean
	local done = math.max(cleared, 0)
	if entry.Infected then
		return done >= entry.World
	end
	return done < entry.World
end

local function refresh(entry: Entry)
	local hidden = shouldHide(entry)
	if entry.Hidden ~= hidden then
		entry.Hidden = hidden
		applyTree(entry.Root, hidden)
	end
end

local unregister: (tag: string, instance: Instance) -> ()

local function register(tag: string, instance: Instance)
	unregister(tag, instance)
	local world = worldOf(instance)
	if world <= 0 then
		return -- pas d'attribut World : on ne sait pas à quel monde il appartient
	end
	local entry: Entry = { Root = instance, World = world, Infected = tag == "Infected", Hidden = nil, Added = nil }
	entry.Added = instance.DescendantAdded:Connect(function(descendant: Instance)
		if entry.Hidden ~= nil then
			applyOne(descendant, entry.Hidden)
		end
	end)
	entries[tag][instance] = entry
	refresh(entry)
end

unregister = function(tag: string, instance: Instance)
	local entry = entries[tag][instance]
	if entry then
		entries[tag][instance] = nil
		if entry.Added then
			entry.Added:Disconnect()
		end
	end
end

------------------------------------------------------------------------------------
-- Vague de nettoyage
------------------------------------------------------------------------------------

local function sparkle(position: Vector3)
	local anchor: Part = New("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one,
		CFrame = CFrame.new(position),
		Parent = Workspace,
	})
	local emitter: ParticleEmitter = New("ParticleEmitter", {
		Enabled = false,
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.4, 0.8),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 0.9,
		Drag = 3,
		Color = ColorSequence.new(Style.Color("AccentCyan"), Color3.new(1, 1, 1)),
		Parent = anchor,
	})
	emitter:Emit(14)
	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

local function screenSweep()
	if Motion.IsReduced() then
		return
	end
	local gui = waveGui
	if not gui then
		gui = New("ScreenGui", {
			Name = "AngAInOneCleanWave",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 6,
			Parent = player:WaitForChild("PlayerGui"),
		})
		waveGui = gui
	end
	local band: Frame = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.3, 0.5),
		Size = UDim2.fromScale(0.45, 1.2),
		Rotation = 12,
		BackgroundColor3 = Style.Color("AccentCyan"),
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		New("UIGradient", {
			Color = ColorSequence.new(Style.Color("AccentCyan"), Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}) :: Instance,
	})
	Motion.Tween(band, { Position = UDim2.fromScale(1.3, 0.5) }, 1.1, Enum.EasingStyle.Sine).Completed:Once(function()
		band:Destroy()
	end)
end

type WaveItem = { Instance: Instance, Delay: number, Out: boolean }

local function cleanWave(world: number)
	local character = player.Character
	local camera = Workspace.CurrentCamera
	local origin = if character
		then character:GetPivot().Position
		elseif camera then camera.CFrame.Position
		else Vector3.zero
	local items: { WaveItem } = {}
	local sparks: { Vector3 } = {}
	local touched: { Entry } = {}
	for _, tag in { "Infected", "Cleaned" } do
		for _, entry in entries[tag] do
			if entry.World == world then
				table.insert(touched, entry)
				local out = entry.Infected
				local nodes = entry.Root:GetDescendants()
				table.insert(nodes, entry.Root)
				for _, node in nodes do
					local position: Vector3? = nil
					if node:IsA("BasePart") then
						position = node.Position
					elseif node.Parent and node.Parent:IsA("BasePart") then
						position = (node.Parent :: BasePart).Position
					end
					local delay = if position
						then math.min((position - origin).Magnitude / WAVE_SPEED, WAVE_MAX_DELAY)
						else 0.3
					table.insert(items, { Instance = node, Delay = delay, Out = out })
					if out and position and node:IsA("BasePart") and #sparks < 12 then
						table.insert(sparks, position)
					end
				end
			end
		end
	end
	Audio.Play("Whoosh", 1.2)
	screenSweep()
	if Motion.IsReduced() or #items == 0 then
		for _, entry in touched do
			refresh(entry)
		end
		return
	end
	-- Pendant la vague : le décor propre part invisible et apparaît en fondu.
	for _, item in items do
		if not item.Out then
			applyOne(item.Instance, true)
		end
	end
	for _, position in sparks do
		task.delay(math.min((position - origin).Magnitude / WAVE_SPEED, WAVE_MAX_DELAY), sparkle, position)
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		for _, item in items do
			local t = math.clamp((elapsed - item.Delay) / FADE_SECONDS, 0, 1)
			local node = item.Instance
			local alpha = if item.Out then t else 1 - t
			if node:IsA("BasePart") or node:IsA("Decal") then
				(node :: any).LocalTransparencyModifier = alpha
			elseif t >= 0.5 and isToggle(node) then
				applyOne(node, item.Out)
			end
		end
		if elapsed > WAVE_MAX_DELAY + FADE_SECONDS + 0.1 then
			connection:Disconnect()
			-- État final exact (collisions, lumières), même si cleared a encore changé.
			for _, entry in touched do
				entry.Hidden = nil
				refresh(entry)
			end
		end
	end)
end

------------------------------------------------------------------------------------
-- Démarrage
------------------------------------------------------------------------------------

local function onState(state: any)
	local data = state.Data
	local value = if type(data.Cleared) == "number" then data.Cleared else 0
	if value == cleared then
		return
	end
	local previous = cleared
	cleared = value
	local waves: { number } = {}
	if previous >= 0 and value > previous then
		for world = previous + 1, value do
			table.insert(waves, world)
		end
	end
	for _, tag in { "Infected", "Cleaned" } do
		for _, entry in entries[tag] do
			if not table.find(waves, entry.World) then
				refresh(entry)
			end
		end
	end
	for _, world in waves do
		cleanWave(world)
	end
end

function WorldState.Start()
	for _, tag in { "Infected", "Cleaned" } do
		for _, instance in CollectionService:GetTagged(tag) do
			register(tag, instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
			register(tag, instance)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
			unregister(tag, instance)
		end)
	end
	if Store.State then
		onState(Store.State)
	end
	Store.Changed:Connect(onState)
end

-- Le monde est-il nettoyé pour moi ? (autres contrôleurs)
function WorldState.IsCleaned(world: number): boolean
	return cleared >= world
end

return WorldState
