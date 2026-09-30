--!strict
--[[
	Build : petits utilitaires de construction procédurale (pièces, rampes, néons, lumières, prompts).
	Toutes les pièces sont ancrées ; collisions/requêtes désactivées sur le décor pur.
]]

local CollectionService = game:GetService("CollectionService")

local Build = {}

export type Props = { [string]: any }

local DEFAULTS = {
	Anchored = true,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
	CastShadow = true,
}

local function apply(instance: Instance, props: Props)
	for key, value in props do
		if key ~= "Parent" and key ~= "Tags" then
			(instance :: any)[key] = value
		end
	end
	local tags = props.Tags
	if type(tags) == "table" then
		for _, tag in tags do
			CollectionService:AddTag(instance, tag)
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
end

function Build.Part(props: Props): Part
	local part = Instance.new("Part")
	for key, value in DEFAULTS do
		(part :: any)[key] = value
	end
	apply(part, props)
	return part
end

-- Décor pur : aucune collision, aucun toucher, pas de requêtes (raycasts caméra ignorés).
function Build.Decor(props: Props): Part
	local part = Build.Part(props)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

-- Bande néon (décor, sans ombre).
function Build.Neon(props: Props): Part
	local part = Build.Decor(props)
	part.Material = Enum.Material.Neon
	part.CastShadow = false
	return part
end

function Build.Cylinder(props: Props): Part
	local part = Build.Part(props)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Rampe solide (WedgePart) : face arrière (+Z local) pleine, la pente monte de l'avant (-Z)
-- vers l'arrière. Sert aux escaliers de la tour (collision lisse sous des marches décoratives).
function Build.Wedge(props: Props): WedgePart
	local wedge = Instance.new("WedgePart")
	for key, value in DEFAULTS do
		(wedge :: any)[key] = value
	end
	apply(wedge, props)
	return wedge
end

function Build.Model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	if parent then
		model.Parent = parent
	end
	return model
end

function Build.Folder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Build.PointLight(parent: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Prompt de proximité (clavier E / manette X / tactile). `action` est lu par le client.
function Build.Prompt(
	parent: Instance,
	actionText: string,
	objectText: string,
	action: string,
	distance: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.MaxActivationDistance = distance or 12
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("Action", action)
	prompt.Parent = parent
	return prompt
end

return table.freeze(Build)
