--!strict
--[[
	EpreuveFx : petits effets 3D locaux partagés par les épreuves (Controllers/EpreuveKinds) :
	pièces locales, rayons, éclats, rotations de pales, étiquettes flottantes, interrupteur façon app.
	Tout est client (rien ne se réplique) et respecte « Réduire les animations » quand ça bouge fort.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Motion = require(script.Parent.Parent.UI.Motion)

local EpreuveFx = {}

EpreuveFx.ACCENT = Color3.fromHex("9B2FD4")
EpreuveFx.GOOD = Color3.fromHex("6CCB5F")
EpreuveFx.BAD = Color3.fromHex("FF5A5F")
EpreuveFx.CARD = Color3.fromHex("2B2B2B")
EpreuveFx.STROKE = Color3.fromHex("3A3A3A")

-- Pièce locale ancrée, sans collision (décor de l'épreuve).
function EpreuveFx.Part(props: { [string]: any }, parent: Instance?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent or Workspace
	return part
end

function EpreuveFx.Tween(
	instance: Instance,
	props: { [string]: any },
	seconds: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Rayon lumineux de `from` à `to` (disparaît en `seconds`).
function EpreuveFx.Beam(from: Vector3, to: Vector3, color: Color3, seconds: number?, width: number?)
	local length = (to - from).Magnitude
	if length < 0.05 then
		return
	end
	local beam = EpreuveFx.Part({
		Name = "EpreuveBeam",
		Size = Vector3.new(width or 0.25, width or 0.25, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	})
	EpreuveFx.Tween(beam, { Transparency = 1 }, seconds or 0.12)
	task.delay((seconds or 0.12) + 0.05, function()
		beam:Destroy()
	end)
end

-- Éclats qui jaillissent d'un point.
function EpreuveFx.Burst(position: Vector3, color: Color3, count: number?)
	local n = count or 8
	if Motion.IsReduced() then
		n = math.max(2, math.floor(n / 3))
	end
	local rng = Random.new()
	for _ = 1, n do
		local bit = EpreuveFx.Part({
			Name = "EpreuveBit",
			Size = Vector3.one * rng:NextNumber(0.25, 0.6),
			CFrame = CFrame.new(position),
			Color = color,
			Material = Enum.Material.Neon,
		})
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.3, 1.4), rng:NextNumber(-1, 1))
			* rng:NextNumber(2, 5)
		EpreuveFx.Tween(bit, {
			CFrame = CFrame.new(position + offset) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Transparency = 1,
		}, 0.6)
		task.delay(0.65, function()
			bit:Destroy()
		end)
	end
end

-- Fait tourner `parts` autour de l'axe monde `axis` passant par `center`. Renvoie l'arrêt.
function EpreuveFx.Spin(parts: { BasePart }, center: Vector3, axis: Vector3, turnsPerSecond: number): () -> ()
	local base: { [BasePart]: CFrame } = {}
	local pivot = CFrame.lookAt(center, center + axis.Unit)
	for _, part in parts do
		base[part] = pivot:ToObjectSpace(part.CFrame)
	end
	local angle = 0
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		if Motion.IsReduced() then
			return
		end
		angle += dt * turnsPerSecond * math.pi * 2
		local turned = pivot * CFrame.Angles(0, 0, angle)
		for part, offset in base do
			part.CFrame = turned * offset
		end
	end)
	return function()
		connection:Disconnect()
		for part, offset in base do
			part.CFrame = pivot * offset
		end
	end
end

-- Étiquette flottante (BillboardGui) au-dessus de `adornee`.
function EpreuveFx.Label(adornee: Instance, text: string, color: Color3?, height: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "EpreuveLabel"
	gui.Size = UDim2.fromOffset(260, 44)
	gui.StudsOffset = Vector3.new(0, height or 3, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromHex("202020")
	label.BackgroundTransparency = 0.15
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label
	if adornee:IsA("BasePart") or adornee:IsA("Model") then
		gui.Adornee = adornee
	end
	gui.Parent = adornee
	return gui
end

-- Interrupteur façon app (pilule LeverPlate + rond LeverKnob posés par le serveur) : allumé / éteint.
function EpreuveFx.Toggle(plate: Instance, on: boolean)
	if not plate:IsA("BasePart") then
		return
	end
	EpreuveFx.Tween(plate, { Color = if on then EpreuveFx.ACCENT else EpreuveFx.STROKE }, 0.15)
	local knob = plate.Parent and plate.Parent:FindFirstChild("LeverKnob")
	if knob and knob:IsA("BasePart") then
		EpreuveFx.Tween(knob, { CFrame = plate.CFrame * CFrame.new(if on then 0.4 else -0.4, 0, -0.05) }, 0.15)
	end
end

-- Mémorise des propriétés pour les remettre plus tard (décor modifié pendant une épreuve).
export type Snapshot = { Restore: () -> () }

function EpreuveFx.Snapshot(instances: { Instance }, keys: { string }): Snapshot
	local saved: { [Instance]: { [string]: any } } = {}
	for _, instance in instances do
		local values = {}
		for _, key in keys do
			local ok, value = pcall(function()
				return (instance :: any)[key]
			end)
			if ok then
				values[key] = value
			end
		end
		saved[instance] = values
	end
	return {
		Restore = function()
			for instance, values in saved do
				if instance.Parent then
					for key, value in values do
						pcall(function()
							(instance :: any)[key] = value
						end)
					end
				end
			end
		end,
	}
end

-- Toutes les BasePart d'un modèle ou d'une pièce.
function EpreuveFx.Parts(root: Instance?): { BasePart }
	local list = {}
	if not root then
		return list
	end
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

return EpreuveFx
