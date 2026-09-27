--!nonstrict
-- Effets visuels 3D réutilisables (tout est local et nettoyé automatiquement).

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Vfx = require(Shared.Config.Vfx)

local Effects = {}

-- Textures : pack assets/vfx une fois uploadé (Config/Vfx), sinon textures intégrées.
local TEX = {
	Sparkle = Vfx.Texture("sparkle"),
	Fire = Vfx.Texture("fire"),
	Smoke = Vfx.Texture("smoke"),
	Spark = Vfx.Texture("spark"),
	Glow = Vfx.Texture("glow_soft"),
	Shock = Vfx.Texture("shockwave"),
	Core = Vfx.Texture("flare"),
	Star = Vfx.Texture("star5"),
	Magic = Vfx.Texture("magic"),
	Ring = Vfx.Texture("ring"),
	Lightning = Vfx.Texture("lightning"),
	Radioactive = Vfx.Texture("radioactive"),
	Drip = Vfx.Texture("drip"),
	Confetti = Vfx.Texture("confetti"),
	Trail = Vfx.Texture("meteor_trail"),
}
Effects.Textures = TEX

local folder: Folder

local function getFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ClientFx"
		f.Parent = Workspace
		folder = f
	end
	return folder
end

local function anchorPart(pos: Vector3, size: Vector3?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = size or Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = getFolder()
	return p
end

local function tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Explosion de particules colorées.
function Effects.Burst(pos: Vector3, color: Color3, count: number?, size: number?)
	local p = anchorPart(pos)
	local s = size or 2
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX.Sparkle
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s * 0.7), NumberSequenceKeypoint.new(1, 0) })
	e.Speed = NumberRange.new(s * 6, s * 14)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Drag = 3
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Enabled = false
	e.Parent = p
	e:Emit(count or 30)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = s * 8
	light.Brightness = 4
	light.Parent = p
	tween(light, 0.6, { Brightness = 0 })
	Debris:AddItem(p, 1.6)
end

-- Anneau d'onde de choc au sol.
function Effects.Shockwave(pos: Vector3, color: Color3, radius: number, duration: number?)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = getFolder()
	local d = duration or 0.6
	tween(ring, d, { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quint)
	Debris:AddItem(ring, d + 0.1)
end

-- Nuage de fumée « pouf ».
function Effects.Poof(pos: Vector3, size: number?)
	local p = anchorPart(pos)
	local s = size or 3
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX.Smoke
	e.Color = ColorSequence.new(Color3.fromRGB(240, 235, 245))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s), NumberSequenceKeypoint.new(1, s * 2.5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Speed = NumberRange.new(s * 2, s * 4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Drag = 4
	e.Enabled = false
	e.Parent = p
	e:Emit(14)
	Debris:AddItem(p, 1.2)
end

-- Poussière au sol (atterrissage).
function Effects.Dust(pos: Vector3, size: number?)
	local p = anchorPart(pos + Vector3.new(0, 0.5, 0))
	local s = size or 3
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX.Smoke
	e.Color = ColorSequence.new(Color3.fromRGB(210, 190, 160))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s * 0.6), NumberSequenceKeypoint.new(1, s * 1.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Speed = NumberRange.new(s * 3, s * 5)
	e.SpreadAngle = Vector2.new(5, 180)
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Drag = 5
	e.Acceleration = Vector3.new(0, -2, 0)
	e.Enabled = false
	e.Parent = p
	e:Emit(16)
	Debris:AddItem(p, 1.3)
end

-- Pilier de lumière vertical (éclosions rares, mutations, alarmes).
function Effects.Pillar(pos: Vector3, color: Color3, duration: number?)
	local pillar = Instance.new("Part")
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Transparency = 0.35
	pillar.Size = Vector3.new(220, 1, 1)
	pillar.CFrame = CFrame.new(pos + Vector3.new(0, 110, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = getFolder()
	local d = duration or 2
	tween(pillar, 0.3, { Size = Vector3.new(220, 7, 7) }, Enum.EasingStyle.Back)
	task.delay(d, function()
		tween(pillar, 0.5, { Size = Vector3.new(220, 0.2, 0.2), Transparency = 1 })
	end)
	Debris:AddItem(pillar, d + 0.6)
end

-- Texte BD flottant dans le monde (« BONK! », « TITAN! »…).
function Effects.FloatingText(pos: Vector3, text: string, color: Color3?, size: number?)
	local p = anchorPart(pos)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260 * (size or 1), 80 * (size or 1))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.Impact
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Theme.Colors.Gold
	label.Rotation = math.random(-12, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Theme.Colors.Ink
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = label
	label.Parent = gui
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(p, 1.4, { CFrame = CFrame.new(pos + Vector3.new(0, 5, 0)) })
	task.delay(0.9, function()
		tween(label, 0.4, { TextTransparency = 1 })
		tween(stroke, 0.4, { Transparency = 1 })
	end)
	Debris:AddItem(p, 1.5)
end

-- Étincelles permanentes attachées à une pièce.
function Effects.Sparkles(part: BasePart?, color: Color3, rate: number?): ParticleEmitter?
	if not part then
		return nil
	end
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX.Sparkle
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate = rate or 6
	e.Parent = part
	return e
end

-- Émetteur propre à chaque mutation.
function Effects.MutationEmitter(part: BasePart?, mutation: any, scale: number)
	if not part or not mutation then
		return
	end
	local s = scale
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 0.8
	e.Rate = 8
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(1, 1.8)
	e.Speed = NumberRange.new(0.5 * s, 2 * s)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * s), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(mutation.Color)
	e.Texture = TEX.Sparkle
	local kind = mutation.Particles
	if kind == "Drip" then
		e.Texture = TEX.Glow
		e.Acceleration = Vector3.new(0, -12, 0)
		e.Speed = NumberRange.new(0, 0.5)
		e.Size = NumberSequence.new(0.35 * s)
		e.Rate = 10
	elseif kind == "Toxic" then
		e.Texture = TEX.Smoke
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8 * s), NumberSequenceKeypoint.new(1, 2 * s) })
		e.Rate = 6
	elseif kind == "Void" then
		e.Texture = TEX.Smoke
		e.LightEmission = 0
		e.Color = ColorSequence.new(Color3.fromRGB(40, 10, 60), Color3.fromRGB(120, 60, 200))
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 * s), NumberSequenceKeypoint.new(1, 2.5 * s) })
	elseif kind == "Rainbow" then
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 80)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
		})
		e.Rate = 14
	elseif kind == "Stars" then
		e.Color = ColorSequence.new(Color3.fromRGB(200, 180, 255), Color3.fromRGB(255, 255, 255))
		e.Rate = 12
		e.Speed = NumberRange.new(0.2, 1)
	elseif kind == "Shine" then
		e.Rate = 5
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.9 * s), NumberSequenceKeypoint.new(1, 0) })
	end
	e.Parent = part
end

-- Traînée de météore (feu + étincelles + trail).
function Effects.MeteorTrail(part: BasePart, color: Color3, width: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width * 0.4, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width * 0.4, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Parent = part
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = TEX.Fire
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), color)
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, width * 0.9), NumberSequenceKeypoint.new(1, 0) })
	fire.Speed = NumberRange.new(1, 3)
	fire.Lifetime = NumberRange.new(0.3, 0.6)
	fire.Rate = 60
	fire.SpreadAngle = Vector2.new(20, 20)
	fire.Parent = part
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = TEX.Spark
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.5)
	sparks.Speed = NumberRange.new(4, 10)
	sparks.Lifetime = NumberRange.new(0.4, 0.8)
	sparks.Rate = 40
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Parent = part
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 30
	light.Brightness = 3
	light.Parent = part
end

-- Explosion d'impact de météore.
function Effects.Impact(pos: Vector3, color: Color3, power: number)
	Effects.Shockwave(pos, color, 14 + power * 4, 0.7)
	Effects.Shockwave(pos, Color3.new(1, 1, 1), 8 + power * 2, 0.4)
	Effects.Burst(pos + Vector3.new(0, 2, 0), color, 30 + power * 6, 2 + power * 0.3)
	Effects.Dust(pos, 4 + power)
	local p = anchorPart(pos + Vector3.new(0, 1, 0))
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX.Spark
	e.Color = ColorSequence.new(Color3.fromRGB(255, 180, 90))
	e.LightEmission = 1
	e.Size = NumberSequence.new(0.6)
	e.Speed = NumberRange.new(20, 45)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -60, 0)
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Enabled = false
	e.Parent = p
	e:Emit(40 + power * 5)
	Debris:AddItem(p, 1.6)
end

return Effects
