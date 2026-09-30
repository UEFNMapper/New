--!strict
--[[
	Props : éléments de décor et de gameplay réutilisables pour construire le PC géant.
	- Gameplay : machines (modules), terminaux, pads (collecteur, téléporteur)
	- Décor PC : ventilateurs, blocs d'ailettes, câbles gainés, condensateurs, texte sérigraphié
	Tags lus par le client : TierGlow (couleur du tier), Spin (hélice de machine),
	DecorSpin (ventilateur de décor), RgbStrip, PulseGlow, TerminalScreen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Modules = require(Shared.Config.Modules)
local Build = require(script.Parent.Build)

local Props = {}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

-- Palette matière du PC (dérivée du thème, plus claire que l'UI pour être lisible en 3D).
local C = {
	Bg = hex(Theme.Colors.BgDeep),
	Pcb = Color3.fromRGB(26, 58, 64),
	PcbDark = Color3.fromRGB(18, 38, 46),
	MetalDark = Color3.fromRGB(52, 58, 74),
	MetalLight = Color3.fromRGB(96, 104, 124),
	Aluminum = Color3.fromRGB(158, 166, 184),
	Black = Color3.fromRGB(26, 28, 34),
	Copper = hex(Theme.Colors.Copper),
	Gold = hex(Theme.Colors.CurrencyBits),
	Brand = hex(Theme.Colors.BrandAnga),
	Cyan = hex(Theme.Colors.AccentCyan),
	Violet = hex(Theme.Colors.AccentViolet),
	White = hex(Theme.Colors.TextPrimary),
}
Props.C = C

function Props.Glow(props: Build.Props): Part
	local part = Build.Neon(props)
	part.Transparency = 0.05
	local tags = { "TierGlow" }
	for _, tag in (props.Tags or {}) :: { string } do
		table.insert(tags, tag)
	end
	part:SetAttribute("GlowStrength", 1)
	for _, tag in tags do
		part:AddTag(tag)
	end
	return part
end

function Props.Spinner(model: Model, cf: CFrame, radius: number, color: Color3, axis: string)
	-- Hélice : un disque + 3 pales, tournées côté client (tag "Spin").
	local hub = Build.Decor({
		Name = "SpinHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, radius * 0.5, radius * 0.5),
		CFrame = cf,
		Color = C.MetalLight,
		Material = Enum.Material.Metal,
		Tags = { "Spin" },
		Parent = model,
	})
	hub:SetAttribute("Axis", axis)
	for blade = 0, 2 do
		local b = Build.Decor({
			Name = "Blade",
			Size = Vector3.new(0.3, radius * 0.9, radius * 0.28),
			CFrame = cf * CFrame.Angles(blade * math.pi * 2 / 3, 0, 0) * CFrame.new(0, radius * 0.45, 0),
			Color = C.MetalDark:Lerp(color, 0.25),
			Material = Enum.Material.SmoothPlastic,
			Parent = hub,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = b
		weld.Parent = b
		b.Anchored = false
	end
	Build.Neon({
		Name = "FanRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2 + 1, radius * 2 + 1),
		CFrame = cf * CFrame.new(-0.3, 0, 0),
		Color = color,
		Transparency = 0.6,
		Parent = model,
	})
end

function Props.Machine(def: Modules.ModuleDef, cf: CFrame, parent: Instance, primary: Color3, secondary: Color3): Model
	local model = Build.Model(def.Id, parent)
	model:SetAttribute("ModuleId", def.Id)
	model:SetAttribute("Level", 0)
	local scale = 0.8 + def.Slot * 0.2

	local base = Build.Part({
		Name = "Base",
		Size = Vector3.new(14, 2, 14),
		CFrame = cf * CFrame.new(0, 1, 0),
		Color = C.MetalDark,
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	model.PrimaryPart = base
	Props.Glow({
		Name = "BaseGlow",
		Size = Vector3.new(14.2, 0.3, 14.2),
		CFrame = cf * CFrame.new(0, 2.1, 0),
		Color = primary,
		Transparency = 0.5,
		Parent = model,
	})

	local top = 2
	local zone = def.Zone
	if zone == 1 then
		-- Condensateur géant
		local height = 10 * scale
		Build.Cylinder({
			Name = "Body",
			Size = Vector3.new(height, 8, 8),
			CFrame = cf * CFrame.new(0, top + height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = C.MetalDark:Lerp(primary, 0.15),
			Material = Enum.Material.Metal,
			Parent = model,
		})
		for ring = 1, 2 do
			Props.Glow({
				Name = "Ring",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.5, 8.4, 8.4),
				CFrame = cf * CFrame.new(0, top + height * ring / 3, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Color = primary,
				Parent = model,
			})
		end
		top += height
	elseif zone == 2 then
		-- Barrettes de RAM (lames verticales)
		local height = 12 * scale
		for i = -1, 1 do
			Build.Part({
				Name = "Stick",
				Size = Vector3.new(1.4, height, 10),
				CFrame = cf * CFrame.new(i * 3.2, top + height / 2, 0),
				Color = C.MetalDark,
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
			Props.Glow({
				Name = "StickGlow",
				Size = Vector3.new(1.5, 0.6, 10.1),
				CFrame = cf * CFrame.new(i * 3.2, top + height - 0.3, 0),
				Color = primary,
				Parent = model,
			})
			for chip = -1, 1 do
				Build.Decor({
					Name = "Chip",
					Size = Vector3.new(1.6, 2, 2.4),
					CFrame = cf * CFrame.new(i * 3.2, top + height * 0.45, chip * 3),
					Color = C.Bg,
					Material = Enum.Material.SmoothPlastic,
					Parent = model,
				})
			end
		end
		top += height
	elseif zone == 3 then
		-- Carte NVMe : plaque + puces NAND
		local height = 2 + scale
		Build.Part({
			Name = "Pcb",
			Size = Vector3.new(12, height, 8),
			CFrame = cf * CFrame.new(0, top + height / 2, 0),
			Color = C.Pcb:Lerp(primary, 0.1),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		for i = -1, 1 do
			Build.Decor({
				Name = "Nand",
				Size = Vector3.new(3, 1, 5),
				CFrame = cf * CFrame.new(i * 3.8, top + height + 0.5, 0),
				Color = C.Bg,
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
			Props.Glow({
				Name = "NandGlow",
				Size = Vector3.new(3.1, 0.2, 0.4),
				CFrame = cf * CFrame.new(i * 3.8, top + height + 1.05, -2),
				Color = primary,
				Parent = model,
			})
		end
		top += height + 1
	elseif zone == 4 then
		-- Ventilateur géant vertical
		local radius = 5 * scale
		Build.Part({
			Name = "Frame",
			Size = Vector3.new(radius * 2 + 2, radius * 2 + 2, 2),
			CFrame = cf * CFrame.new(0, top + radius + 1, 1.5),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Transparency = 0.2,
			Parent = model,
		})
		Props.Spinner(
			model,
			cf * CFrame.new(0, top + radius + 1, -0.2) * CFrame.Angles(0, math.pi / 2, 0),
			radius,
			primary,
			"X"
		)
		top += radius * 2 + 2
	elseif zone == 5 then
		-- Die CPU
		local height = 3 * scale
		Build.Part({
			Name = "Die",
			Size = Vector3.new(11, height, 11),
			CFrame = cf * CFrame.new(0, top + height / 2, 0),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		Build.Decor({
			Name = "Ihs",
			Size = Vector3.new(8, 0.6, 8),
			CFrame = cf * CFrame.new(0, top + height + 0.3, 0),
			Color = C.Gold,
			Material = Enum.Material.Foil,
			Parent = model,
		})
		Props.Glow({
			Name = "CoreX",
			Size = Vector3.new(8.2, 0.3, 0.5),
			CFrame = cf * CFrame.new(0, top + height + 0.7, 0),
			Color = primary,
			Parent = model,
		})
		Props.Glow({
			Name = "CoreZ",
			Size = Vector3.new(0.5, 0.3, 8.2),
			CFrame = cf * CFrame.new(0, top + height + 0.7, 0),
			Color = primary,
			Parent = model,
		})
		top += height + 1
	elseif zone == 6 then
		-- Carte graphique triple ventilateur
		local height = 5
		Build.Part({
			Name = "Shroud",
			Size = Vector3.new(13, height, 5 + scale * 2),
			CFrame = cf * CFrame.new(0, top + height / 2 + 1, 0),
			Color = C.MetalDark,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		Props.Glow({
			Name = "ShroudGlow",
			Size = Vector3.new(13.1, 0.4, 0.4),
			CFrame = cf * CFrame.new(0, top + height + 1, -(2.5 + scale)),
			Color = secondary,
			Parent = model,
		})
		for i = -1, 1 do
			Props.Spinner(
				model,
				cf * CFrame.new(i * 4.2, top + height + 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
				1.8,
				primary,
				"X"
			)
		end
		top += height + 2
	else
		-- Orbe neuronal
		local radius = 2.5 + scale * 1.5
		Build.Part({
			Name = "Pedestal",
			Size = Vector3.new(6, 4, 6),
			CFrame = cf * CFrame.new(0, top + 2, 0),
			Color = C.MetalLight,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		Props.Glow({
			Name = "Orb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(radius * 2, radius * 2, radius * 2),
			CFrame = cf * CFrame.new(0, top + 6 + radius, 0),
			Color = primary,
			Transparency = 0.15,
			Parent = model,
		})
		local ring = Build.Neon({
			Name = "Halo",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, radius * 3, radius * 3),
			CFrame = cf * CFrame.new(0, top + 6 + radius, 0),
			Color = secondary,
			Transparency = 0.5,
			Tags = { "Spin" },
			Parent = model,
		})
		ring:SetAttribute("Axis", "Y")
		top += 6 + radius * 2
	end

	-- Point d'ancrage de l'étiquette de niveau (affichée par le client)
	Build.Decor({
		Name = "LabelAnchor",
		Size = Vector3.one,
		CFrame = cf * CFrame.new(0, top + 3, 0),
		Transparency = 1,
		Parent = model,
	})
	-- Prompt sur le socle (à hauteur de joueur) : l'étiquette peut être haute, le prompt non.
	Build.Prompt(base, "Améliorer", def.Name, "Upgrade", 14):SetAttribute("ModuleId", def.Id)
	return model
end

------------------------------------------------------------------------------------
-- Terminaux, pads, fragments
------------------------------------------------------------------------------------

function Props.Terminal(
	parent: Instance,
	name: string,
	cf: CFrame,
	color: Color3,
	actionText: string,
	objectText: string,
	action: string
): Model
	local model = Build.Model(name, parent)
	local stand = Build.Part({
		Name = "Stand",
		Size = Vector3.new(4, 5, 3),
		CFrame = cf * CFrame.new(0, 2.5, 0),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	model.PrimaryPart = stand
	local screen = Build.Decor({
		Name = "Screen",
		Size = Vector3.new(6, 4, 0.4),
		CFrame = cf * CFrame.new(0, 6.5, -0.4) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = C.Bg,
		Material = Enum.Material.Glass,
		Transparency = 0.05,
		Tags = { "TerminalScreen" },
		Parent = model,
	})
	screen:SetAttribute("Label", objectText)
	screen:SetAttribute("Accent", color:ToHex())
	Build.Neon({
		Name = "Trim",
		Size = Vector3.new(6.2, 0.25, 0.5),
		CFrame = cf * CFrame.new(0, 4.4, -0.6),
		Color = color,
		Parent = model,
	})
	Build.PointLight(screen, color, 0.8, 10)
	Build.Prompt(stand, actionText, objectText, action, 12)
	return model
end

function Props.Pad(parent: Instance, name: string, cf: CFrame, diameter: number, color: Color3): Part
	local base = Build.Cylinder({
		Name = name,
		Size = Vector3.new(0.6, diameter, diameter),
		CFrame = cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		CanTouch = true,
		Parent = parent,
	})
	Build.Neon({
		Name = name .. "Glow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, diameter - 1.5, diameter - 1.5),
		CFrame = cf * CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Transparency = 0.5,
		Tags = { "PulseGlow" },
		Parent = parent,
	})
	return base
end

-- Ventilateur de décor (toujours en rotation côté client). `cf` : RightVector = axe du ventilateur.
function Props.Fan(parent: Instance, cf: CFrame, diameter: number, glowColor: Color3, blades: number?): Model
	local model = Build.Model("Fan", parent)
	local r = diameter / 2
	Build.Part({
		Name = "Frame",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, diameter + 4, diameter + 4),
		CFrame = cf * CFrame.new(-1.2, 0, 0),
		Color = C.Black,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		Parent = model,
	})
	local hub = Build.Decor({
		Name = "SpinHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, r * 0.55, r * 0.55),
		CFrame = cf,
		Color = C.MetalDark,
		Material = Enum.Material.Metal,
		Tags = { "DecorSpin" },
		Parent = model,
	})
	hub:SetAttribute("Axis", "X")
	local count = blades or 7
	for i = 0, count - 1 do
		local blade = Build.Decor({
			Name = "Blade",
			Size = Vector3.new(0.5, r * 0.8, r * 0.34),
			CFrame = cf
				* CFrame.Angles(i * math.pi * 2 / count, 0, 0)
				* CFrame.new(0, r * 0.55, 0)
				* CFrame.Angles(0, math.rad(22), 0),
			Color = C.Black:Lerp(glowColor, 0.12),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.05,
			Parent = hub,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = blade
		weld.Parent = blade
		blade.Anchored = false
	end
	Build.Neon({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, diameter + 1, diameter + 1),
		CFrame = cf * CFrame.new(-0.4, 0, 0),
		Color = glowColor,
		Transparency = 0.55,
		Tags = { "RgbStrip" },
		Parent = model,
	})
	local light = Build.Decor({ Name = "Light", Size = Vector3.one, CFrame = cf, Transparency = 1, Parent = model })
	Build.PointLight(light, glowColor, 1.2, diameter)
	return model
end

-- Bloc d'ailettes (radiateur) : plaques fines empilées le long du LookVector de `cf`.
function Props.Fins(
	parent: Instance,
	cf: CFrame,
	width: number,
	height: number,
	depth: number,
	count: number,
	color: Color3?
): Model
	local model = Build.Model("Fins", parent)
	local spacing = depth / count
	for i = 0, count - 1 do
		Build.Part({
			Name = "Fin",
			Size = Vector3.new(width, height, math.max(spacing * 0.35, 0.4)),
			CFrame = cf * CFrame.new(0, 0, -depth / 2 + spacing * (i + 0.5)),
			Color = color or C.Aluminum,
			Material = Enum.Material.Metal,
			Reflectance = 0.05,
			Parent = model,
		})
	end
	return model
end

-- Câble gainé qui suit une liste de points (segments cylindriques + articulations).
function Props.Cable(
	parent: Instance,
	points: { Vector3 },
	radius: number,
	color: Color3,
	material: Enum.Material?
): Model
	local model = Build.Model("Cable", parent)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		-- Segment vertical : lookAt dégénéré avec l'axe Y comme "haut", on prend X.
		local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
		Build.Part({
			Name = "Segment",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length, radius * 2, radius * 2),
			CFrame = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0),
			Color = color,
			Material = material or Enum.Material.Fabric,
			Parent = model,
		})
		if i < #points - 1 then
			Build.Decor({
				Name = "Joint",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * radius * 2,
				CFrame = CFrame.new(b),
				Color = color,
				Material = material or Enum.Material.Fabric,
				Parent = model,
			})
		end
	end
	return model
end

-- Câble en arc (courbe de Bézier quadratique) : passe au-dessus des cloisons entre zones.
function Props.ArcCable(
	parent: Instance,
	from: Vector3,
	control: Vector3,
	to: Vector3,
	radius: number,
	color: Color3,
	segments: number?
): Model
	local points = {}
	local count = segments or 10
	for i = 0, count do
		local t = i / count
		table.insert(points, from * (1 - t) ^ 2 + control * 2 * (1 - t) * t + to * t ^ 2)
	end
	return Props.Cable(parent, points, radius, color)
end

-- Condensateur électrolytique (cylindre + collerette lumineuse).
function Props.Capacitor(
	parent: Instance,
	position: Vector3,
	radius: number,
	height: number,
	color: Color3,
	glowColor: Color3
)
	Build.Cylinder({
		Name = "Capacitor",
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	Build.Neon({
		Name = "CapRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, radius * 2 + 0.3, radius * 2 + 0.3),
		CFrame = CFrame.new(position + Vector3.new(0, height - 1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = glowColor,
		Transparency = 0.45,
		Parent = parent,
	})
end

-- Texte "sérigraphié" (SurfaceGui statique sur la face avant d'une pièce).
function Props.Label(part: BasePart, text: string, color: Color3, face: Enum.NormalId?, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.LightInfluence = 0.3
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Font = font or Enum.Font.Michroma
	label.Parent = gui
	gui.Parent = part
end

return Props
