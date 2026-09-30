--!strict
--[[
	Ambience : l'ambiance de chaque monde (v4, docs/AUDIT_V3.md § E).
	- Quand le monde parcouru change (AmbiencePresets.WorldFor : 0 = lobby), fondu de l'éclairage
	  vers le preset du monde : Lighting (Brightness, Ambient, OutdoorAmbient), Atmosphere
	  (Density, Color, Decay, Glare, Haze) et Bloom (Intensity, Threshold).
	- Particules d'ambiance autour du joueur : UN seul émetteur (étincelles, bits de données,
	  givre, chaleur, pixels, synapses), débit faible pour le mobile, coupé par
	  « Réduire les animations » (attribut ReducedMotion du joueur).

	Cohabitation :
	- La teinte ColorCorrection appartient à Feedback.applyWorld : on n'y touche pas.
	- Un BLACKOUT (IncidentController) sauvegarde l'éclairage au début de l'incident, l'éteint puis
	  le restaure : on ne lance aucun fondu pendant l'annonce, l'incident et la restauration
	  (AmbiencePresets.LightingFree) ; le preset du monde est rejoué juste après, à la fin de la
	  période de grâce, même sans changement de monde (replayAfterBlackout).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AmbiencePresets = require(Shared.Config.AmbiencePresets)

local Store = require(script.Parent.Store)
local IncidentController = require(script.Parent.IncidentController)
local Motion = require(script.Parent.Parent.UI.Motion)

local Ambience = {}

local player = Players.LocalPlayer
local applied = -1 -- monde dont l'éclairage est appliqué (ou en cours de fondu)
local lastBlackout = -math.huge -- os.clock() du dernier BLACKOUT vu (annonce ou incident)
local replayAfterBlackout = false -- preset du monde à rejouer une fois l'éclairage libéré
local rig: Part? = nil
local emitter: ParticleEmitter? = nil
local particleWorld = -1
local particlesOn = false

local function rgb(value: AmbiencePresets.Rgb): Color3
	return Color3.new(value[1], value[2], value[3])
end

local function isReduced(): boolean
	return Motion.IsReduced() or player:GetAttribute("ReducedMotion") == true
end

-- Monde courant d'après l'état du joueur (0 si l'état n'est pas encore arrivé).
local function currentWorld(): number
	local state = Store.State
	if not state then
		return 0
	end
	local data = state.Data
	return AmbiencePresets.WorldFor({
		AtLobby = state.AtLobby == true,
		Stage = if type(data.Stage) == "number" then data.Stage else 0,
		Cleared = if type(data.Cleared) == "number" then data.Cleared else 0,
		RunStarted = data.RunStarted == true,
	})
end

------------------------------------------------------------------------------------
-- Éclairage
------------------------------------------------------------------------------------

local function applyLighting(world: number, duration: number)
	local preset = AmbiencePresets.Get(world)
	Motion.Tween(Lighting, {
		Brightness = preset.Brightness,
		Ambient = rgb(preset.Ambient),
		OutdoorAmbient = rgb(preset.OutdoorAmbient),
	}, duration, Enum.EasingStyle.Sine)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local a = preset.Atmosphere
		Motion.Tween(atmosphere, {
			Density = a.Density,
			Color = rgb(a.Color),
			Decay = rgb(a.Decay),
			Glare = a.Glare,
			Haze = a.Haze,
		}, duration, Enum.EasingStyle.Sine)
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		Motion.Tween(bloom, {
			Intensity = preset.Bloom.Intensity,
			Threshold = preset.Bloom.Threshold,
		}, duration, Enum.EasingStyle.Sine)
	end
end

------------------------------------------------------------------------------------
-- Particules
------------------------------------------------------------------------------------

local FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.35),
	NumberSequenceKeypoint.new(0.8, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})

local FLICKER = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.1, 0.2),
	NumberSequenceKeypoint.new(0.3, 0.7),
	NumberSequenceKeypoint.new(0.5, 0.15),
	NumberSequenceKeypoint.new(0.7, 0.65),
	NumberSequenceKeypoint.new(0.85, 0.25),
	NumberSequenceKeypoint.new(1, 1),
})

local function ensureRig(): ParticleEmitter
	local existing = emitter
	if existing and rig and rig.Parent then
		return existing
	end
	-- Pièce locale invisible (jamais répliquée) qui suit le joueur : les particules naissent dans
	-- son volume puis restent dans le monde (LockedToPart = false).
	local part = Instance.new("Part")
	part.Name = "AmbienceRig"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(44, 22, 44)
	part.Parent = Workspace
	local fx = Instance.new("ParticleEmitter")
	fx.Name = "AmbientParticles"
	fx.Enabled = false
	fx.Shape = Enum.ParticleEmitterShape.Box
	fx.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	fx.EmissionDirection = Enum.NormalId.Top
	fx.LockedToPart = false
	fx.Drag = 0.4
	fx.Rotation = NumberRange.new(0, 360)
	fx.Parent = part
	rig = part
	emitter = fx
	return fx
end

local function configure(fx: ParticleEmitter, spec: AmbiencePresets.Particles)
	local keypoints = {}
	for index, color in spec.Colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / math.max(#spec.Colors - 1, 1), rgb(color)))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, keypoints[1].Value))
	end
	fx.Color = ColorSequence.new(keypoints)
	fx.Texture = spec.Texture
	fx.Rate = spec.Rate
	fx.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
	fx.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
	fx.Acceleration = Vector3.new(spec.Acceleration[1], spec.Acceleration[2], spec.Acceleration[3])
	fx.SpreadAngle = Vector2.new(spec.Spread, spec.Spread)
	fx.LightEmission = spec.LightEmission
	fx.RotSpeed = NumberRange.new(-spec.RotSpeed, spec.RotSpeed)
	fx.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, spec.Size),
		NumberSequenceKeypoint.new(0.85, spec.Size),
		NumberSequenceKeypoint.new(1, 0),
	})
	fx.Transparency = if spec.Flicker then FLICKER else FADE
end

local function updateParticles(world: number)
	local spec = AmbiencePresets.Get(world).Particles
	if spec == nil or isReduced() then
		if particlesOn and emitter then
			emitter.Enabled = false
			emitter:Clear()
		end
		particlesOn = false
		particleWorld = -1
		return
	end
	local fx = ensureRig()
	if particleWorld ~= world then
		particleWorld = world
		configure(fx, spec)
		fx:Clear()
	end
	fx.Enabled = true
	particlesOn = true
end

-- Le volume des particules suit le joueur (ou la caméra, sans personnage).
local function followPlayer()
	local part = rig
	if not part or not particlesOn then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position: Vector3? = nil
	if root and root:IsA("BasePart") then
		position = root.Position
	else
		local camera = Workspace.CurrentCamera
		position = if camera then camera.Focus.Position else nil
	end
	if position then
		part.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
	end
end

------------------------------------------------------------------------------------
-- Boucle
------------------------------------------------------------------------------------

local accumulator = 0
local errors = 0

local function refresh()
	local world = currentWorld()
	local kind = IncidentController.Current()
	local now = os.clock()
	if kind == "Blackout" then
		lastBlackout = now
		-- IncidentController restaure l'éclairage d'AVANT la coupure : à la fin de la période de
		-- grâce, on rejoue le preset du monde même si le monde n'a pas changé entre-temps.
		replayAfterBlackout = true
	end
	if (applied ~= world or replayAfterBlackout) and AmbiencePresets.LightingFree(kind, now - lastBlackout) then
		-- Premier réglage (arrivée en cours d'ascension) : fondu court.
		applyLighting(world, if applied < 0 then 0.6 else AmbiencePresets.TWEEN)
		applied = world
		replayAfterBlackout = false
	end
	updateParticles(world)
end

function Ambience.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		followPlayer()
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		accumulator = 0
		xpcall(refresh, function(err: any)
			errors += 1
			if errors <= 3 then
				warn("[Ambience]", err)
			end
		end)
	end)
	player:GetAttributeChangedSignal("ReducedMotion"):Connect(function()
		updateParticles(currentWorld())
	end)
end

return Ambience
