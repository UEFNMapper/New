--!strict
--[[
	LagzCameo : LAGZ surgit EN 3D de ses écrans accrochés aux parois (docs/AUDIT_V3.md, C2).
	Écrans posés par World/Tower/Cameos (tag LagzCameo, attributs World, Stage ; tête = « Head »).
	- Le joueur atteint l'étape d'un écran : l'écran grésille, LAGZ surgit, rit, lance une courte
	  réplique (Dialogue, personnage "LAGZ"), puis disparaît en glitchant
	- Pendant un incident dans le monde du joueur : l'écran le plus proche s'anime aussi (sans
	  réplique : Story dit déjà celle de l'incident)
	Respecte ReducedMotion (attribut local du joueur) : apparition / disparition en fondu, sans
	rebond ni tremblement. Tout est local (décor pur, rien n'est répliqué).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)

local Net = require(script.Parent.Net)
local Audio = require(script.Parent.Audio)
local Story = require(script.Parent.Story)
local Dialogue = require(script.Parent.Parent.UI.Screens.Dialogue)

local LagzCameo = {}

local player = Players.LocalPlayer

type PartState = { Part: BasePart, Base: number }
type Cameo = {
	Model: Model,
	World: number,
	Stage: number,
	Head: Model?,
	Parts: { PartState },
	Static: { PartState },
	Home: CFrame,
	Scale: number,
	Busy: boolean,
	LastAt: number,
}

local cameos: { [Model]: Cameo } = {}
local played: { [number]: boolean } = {} -- étapes déjà jouées pendant cette ascension
local lastStage = 0

local POP_DEPTH = 6 -- la tête sort de la paroi (studs)
local INCIDENT_RANGE = 200 -- écran assez proche pour réagir à un incident
local STAGE_RANGE = 320 -- écran chargé et pas trop loin pour l'apparition d'étape

local function reduced(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

local function setAlpha(states: { PartState }, hidden: number)
	for _, slot in states do
		slot.Part.Transparency = slot.Base + (1 - slot.Base) * hidden
	end
end

local function register(instance: Instance)
	if not instance:IsA("Model") or cameos[instance] then
		return
	end
	local world, stage = instance:GetAttribute("World"), instance:GetAttribute("Stage")
	if type(world) ~= "number" or type(stage) ~= "number" then
		return
	end
	local headInstance = instance:FindFirstChild("Head")
	local head: Model? = if headInstance and headInstance:IsA("Model") then headInstance else nil
	local parts: { PartState } = {}
	local static: { PartState } = {}
	if head then
		for _, d in head:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, { Part = d, Base = d.Transparency })
			end
		end
	end
	for _, d in instance:GetChildren() do
		if d:IsA("BasePart") and d.Name == "CameoStatic" then
			table.insert(static, { Part = d, Base = d.Transparency })
		end
	end
	local cameo: Cameo = {
		Model = instance,
		World = world,
		Stage = stage,
		Head = head,
		Parts = parts,
		Static = static,
		Home = if head then head:GetPivot() else instance:GetPivot(),
		Scale = 1,
		Busy = false,
		LastAt = -math.huge,
	}
	setAlpha(parts, 1) -- LAGZ se cache dans son écran
	cameos[instance] = cameo
end

-- Réplique de l'apparition. Au 1er checkpoint d'un monde, LAGZ dit déjà sa réplique d'arrivée
-- (Story.LagzWorld) : l'écran l'illustre sans en ajouter une. Sinon : la n-ième du monde.
local function lineOf(cameo: Cameo): string?
	local first = Tower.FirstStage(cameo.World)
	if cameo.Stage == first then
		return nil
	end
	local index = 1
	for _, other in cameos do
		if other.World == cameo.World and other.Stage < cameo.Stage and other.Stage ~= first then
			index += 1
		end
	end
	return Story.CameoLine(cameo.World, index)
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Boucle d'animation : step(alpha 0..1) à chaque image, `duration` secondes.
local function animate(cameo: Cameo, duration: number, step: (number) -> ())
	local start = os.clock()
	while cameo.Model.Parent do
		local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
		step(alpha)
		if alpha >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function pose(cameo: Cameo, offset: CFrame, scale: number)
	local head = cameo.Head
	if not head then
		return
	end
	local target = math.max(scale, 0.05)
	if math.abs(target - cameo.Scale) > 1e-3 then
		cameo.Scale = target
		pcall(function()
			head:ScaleTo(target)
		end)
	end
	head:PivotTo(cameo.Home * offset)
end

-- Rotation (lacet) de la tête vers le joueur, limitée : l'avant du modèle est +Z local.
local function lookYaw(cameo: Cameo): number
	local position = rootPosition()
	if not position then
		return 0
	end
	local rel = cameo.Home:PointToObjectSpace(position)
	return math.clamp(math.atan2(rel.X, rel.Z), -0.8, 0.8)
end

local function laugh()
	for _, pitch in { 0.55, 0.62, 0.5 } do
		Audio.Play("Error", pitch)
		task.wait(0.16)
	end
end

local function play(cameo: Cameo, line: string?)
	if cameo.Busy or not cameo.Head then
		return
	end
	cameo.Busy = true
	task.spawn(function()
		local calm = reduced()
		-- 1. L'écran grésille
		Audio.Play("Zap", 1.5)
		animate(cameo, 0.5, function(alpha: number)
			for _, slot in cameo.Static do
				slot.Part.Transparency = if calm or alpha >= 1
					then slot.Base
					else (if math.random() < 0.5 then 0 else 0.9)
			end
		end)
		-- 2. LAGZ surgit de l'écran
		Audio.Play("Whoosh", 0.8)
		animate(cameo, if calm then 0.35 else 0.45, function(alpha: number)
			if calm then
				pose(cameo, CFrame.identity, 1)
				setAlpha(cameo.Parts, 1 - alpha)
				return
			end
			-- Sortie avec rebond (easing « back »)
			local c = 1.9
			local e = 1 + (c + 1) * (alpha - 1) ^ 3 + c * (alpha - 1) ^ 2
			pose(cameo, CFrame.new(0, 0, -POP_DEPTH * (1 - e)), 0.35 + 0.65 * e)
			setAlpha(cameo.Parts, math.clamp(1 - alpha * 2.5, 0, 1))
		end)
		setAlpha(cameo.Parts, 0)
		-- 3. Il rit et nargue le joueur
		task.spawn(laugh)
		if line then
			Dialogue.Say(line, 3.5, "LAGZ")
		end
		local yaw = 0
		animate(cameo, 2.4, function(alpha: number)
			if calm then
				return
			end
			yaw += (lookYaw(cameo) - yaw) * 0.15
			local t = alpha * 2.4
			local bob = math.abs(math.sin(t * 12)) * 0.5 * (1 - alpha * 0.5)
			local roll = math.sin(t * 9) * 0.08
			pose(cameo, CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, roll), 1)
		end)
		-- 4. Il s'en va en glitchant
		Audio.Play("Zap", 1.9)
		animate(cameo, if calm then 0.4 else 0.55, function(alpha: number)
			if calm then
				setAlpha(cameo.Parts, alpha)
				return
			end
			local jitter = CFrame.new((math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.2, 0)
			pose(cameo, jitter * CFrame.Angles(0, yaw, 0), 1 - alpha * 0.6)
			for _, slot in cameo.Parts do
				slot.Part.Transparency = if math.random() < alpha then 1 else slot.Base
			end
			for _, slot in cameo.Static do
				slot.Part.Transparency = if math.random() < 0.5 then 0 else 0.9
			end
		end)
		setAlpha(cameo.Parts, 1)
		setAlpha(cameo.Static, 0)
		pose(cameo, CFrame.identity, 1)
		cameo.LastAt = os.clock()
		cameo.Busy = false
	end)
end

local function near(cameo: Cameo, range: number): boolean
	local position = rootPosition()
	return position ~= nil and (cameo.Home.Position - position).Magnitude <= range
end

local function onStage()
	local stage = player:GetAttribute("Stage")
	if type(stage) ~= "number" then
		return
	end
	if stage == 0 then
		table.clear(played)
	elseif stage > lastStage and not played[stage] then
		for _, cameo in cameos do
			if cameo.Stage == stage and near(cameo, STAGE_RANGE) then
				played[stage] = true
				-- Nouveau monde : l'en-tête de l'app s'affiche d'abord, LAGZ surgit avec sa réplique.
				local delay = if stage == Tower.FirstStage(cameo.World) then 1.6 else 0.8
				task.delay(delay, play, cameo, lineOf(cameo))
				break
			end
		end
	end
	lastStage = stage
end

local function onFx(kind: string, payload: any)
	if kind == "RunStart" then
		table.clear(played)
	elseif kind == "Incident" and type(payload) == "table" and payload.Phase == "Warn" then
		local stage = player:GetAttribute("Stage")
		local world = if type(stage) == "number" then Tower.WorldOf(stage) else 0
		if payload.World ~= world then
			return
		end
		-- L'écran le plus proche du joueur dans ce monde
		local position = rootPosition()
		local best: Cameo? = nil
		local bestDistance = INCIDENT_RANGE
		for _, cameo in cameos do
			if cameo.World == world and position and os.clock() - cameo.LastAt > 10 then
				local distance = (cameo.Home.Position - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = cameo, distance
				end
			end
		end
		if best then
			play(best, nil)
		end
	end
end

function LagzCameo.Start()
	for _, instance in CollectionService:GetTagged("LagzCameo") do
		register(instance)
	end
	CollectionService:GetInstanceAddedSignal("LagzCameo"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("LagzCameo"):Connect(function(instance: Instance)
		cameos[instance :: any] = nil
	end)
	local stage = player:GetAttribute("Stage")
	lastStage = if type(stage) == "number" then stage else 0
	player:GetAttributeChangedSignal("Stage"):Connect(onStage)
	Net.On("Fx", onFx)
end

return LagzCameo
