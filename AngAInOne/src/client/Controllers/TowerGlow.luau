--!strict
--[[
	TowerGlow : la tour s'allume monde par monde, visible depuis le lobby (docs/AUDIT_V3.md, C2).
	Néons de la coque tagués ShellLight par Shell.luau (attribut World : 1..7 = bande du monde,
	0 = toute la tour ; Split = bande verticale découpée ici en un morceau par monde).
	- Monde infecté (pour CE joueur) : rouge / violet terne qui vacille et « glitche »
	- Monde nettoyé (data.Cleared >= monde) : RGB propre à la couleur du monde (Tower.Worlds[w].Primary)
	- Monde qui vient d'être nettoyé : vague lumineuse qui balaie sa bande
	- Victoire : cascade arc-en-ciel du bas vers le haut, puis toute la tour en arc-en-ciel
	  (Cleared reste à WORLD_COUNT jusqu'au départ suivant : voir ProgressService.onFinish)
	Respecte ReducedMotion (attribut local du joueur) : couleurs fixes, sans clignotement.
	Budget : 10 mises à jour par seconde, et aucune quand la caméra est dans la tour (coque
	invisible de l'intérieur : AppPanelLogic.InsideTower).
	Logique pure : Shared/Util/ShellGlow.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Branding = require(Shared.Config.Branding)
local ShellGlow = require(Shared.Util.ShellGlow)
local AppPages = require(Shared.Util.AppPanelLogic)

local Store = require(script.Parent.Store)
local Net = require(script.Parent.Net)

local TowerGlow = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local APP_GLOW = Color3.fromHex(Branding.PartnerApp.Accent):Lerp(WHITE, 0.25)
local SPLIT_GAP = 3 -- studs éteints entre deux mondes sur une jauge découpée
local UPDATE_HZ = 10 -- ~110 néons : 10 écritures par seconde suffisent (vague, vacillement, arc-en-ciel)

type Light = {
	Part: BasePart,
	World: number,
	Base: number, -- transparence d'origine
	Seed: number,
	Height: number, -- 0..1 le long de la tour
	Along: number, -- 0..1 dans sa bande (vague)
	LastColor: Color3?,
	LastAlpha: number?,
}

local lights: { [BasePart]: Light } = {}
local cleared = 0
local victory = false
local synced = false
local waves: { [number]: number } = {} -- monde -> os.clock() du nettoyage
local cascadeAt = -math.huge

local function reduced(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

local function worldColor(world: number): Color3
	local def = Tower.Worlds[world]
	return if def then Color3.fromHex(def.Primary) else APP_GLOW
end

local function add(part: BasePart, world: number)
	local p = part.Position
	local band = math.max(world, 1)
	local base = (band - 1) * ShellGlow.BAND
	lights[part] = {
		Part = part,
		World = world,
		Base = math.min(part.Transparency, 0.2),
		Seed = math.random() * 100,
		Height = math.clamp(p.Y / ShellGlow.HEIGHT, 0, 1),
		Along = math.clamp(((p.X + p.Z) / 2 + 132) / 264 * 0.6 + (p.Y - base) / ShellGlow.BAND * 0.4, 0, 1),
	}
end

-- Jauge verticale (Split) : un morceau par monde, créé côté client ; l'original est masqué.
local function split(part: BasePart)
	local size = part.Size
	local cf = part.CFrame
	local half = size.Y / 2
	local y0, y1 = cf.Position.Y - half, cf.Position.Y + half
	for _, segment in ShellGlow.Segments(y0, y1, SPLIT_GAP) do
		local piece = Instance.new("Part")
		piece.Name = `{part.Name}W{segment.World}`
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.CastShadow = false
		piece.Material = Enum.Material.Neon
		piece.Color = part.Color
		piece.Size = Vector3.new(size.X, segment.Y1 - segment.Y0, size.Z)
		piece.CFrame = cf * CFrame.new(0, (segment.Y0 + segment.Y1) / 2 - cf.Position.Y, 0)
		piece.Parent = part.Parent
		add(piece, segment.World)
	end
	part.Transparency = 1
end

local function register(instance: Instance)
	if not instance:IsA("BasePart") or lights[instance] then
		return
	end
	local world = instance:GetAttribute("World")
	if type(world) ~= "number" then
		return
	end
	if instance:GetAttribute("Split") == true then
		split(instance)
	else
		add(instance, world)
	end
end

local function apply(light: Light, color: Color3, alpha: number)
	local last = light.LastColor
	if last and light.LastAlpha == alpha and last == color then
		return
	end
	light.LastColor = color
	light.LastAlpha = alpha
	light.Part.Color = color
	light.Part.Transparency = alpha
end

-- Couleur / transparence d'un néon à l'instant t.
local function shade(light: Light, t: number, calm: boolean): (Color3, number)
	local world = light.World
	local base = light.Base
	-- Victoire : cascade arc-en-ciel qui monte, puis arc-en-ciel qui tourne doucement.
	if victory then
		local reached, crest = ShellGlow.Cascade(if calm then math.huge else t - cascadeAt, light.Height)
		if reached then
			local hue = ShellGlow.RainbowHue(if calm then 0 else t, light.Height)
			return Color3.fromHSV(hue, 0.75, 1):Lerp(WHITE, crest), base
		end
		-- Pas encore atteint par la cascade : état propre.
		return if world > 0 then worldColor(world) else APP_GLOW, base
	end
	local color: Color3
	local alpha: number
	if ShellGlow.IsClean(world, cleared) then
		color, alpha = worldColor(world), base
	else
		local level = ShellGlow.InfectedLevel(t, light.Seed, calm)
		local infected =
			ShellGlow.InfectedRed:Lerp(ShellGlow.InfectedViolet, ShellGlow.InfectedMix(t, light.Seed, calm))
		if world == 0 then
			-- Toute la tour : l'infection recule à mesure que les mondes sont nettoyés.
			local progress = math.clamp(cleared / Tower.WORLD_COUNT, 0, 1)
			color = infected:Lerp(APP_GLOW, progress)
			level = level + (1 - level) * progress
		else
			color = infected
		end
		alpha = base + (1 - base) * (1 - level) * 0.85
	end
	-- Vague « monde nettoyé » (monde 0 : chaque nettoyage le fait vibrer)
	local startedAt = if world > 0 then waves[world] else waves[0]
	if startedAt then
		local k = if calm
			then math.clamp(1 - (t - startedAt) / ShellGlow.WAVE_SECONDS, 0, 1) * 0.5
			else ShellGlow.Wave(t - startedAt, light.Along)
		if k > 0 then
			color = color:Lerp(WHITE, k)
			alpha = alpha * (1 - k)
		end
	end
	return color, alpha
end

local function sync(data: any)
	if type(data) ~= "table" then
		return
	end
	local newCleared = if type(data.Cleared) == "number" then data.Cleared else 0
	local now = os.clock()
	if synced and newCleared > cleared then
		for w = cleared + 1, newCleared do
			waves[w] = now
		end
		waves[0] = now
	end
	cleared = newCleared
	local wasVictory = victory
	victory = ShellGlow.IsVictory(cleared, data.Stage or 0, data.RunStarted == true)
	if victory and not wasVictory then
		-- Victoire déjà acquise à la connexion : pas de cascade ; sinon elle démarre maintenant.
		cascadeAt = if synced then math.max(cascadeAt, now - 0.1) else -math.huge
	end
	synced = true
end

function TowerGlow.Start()
	for _, instance in CollectionService:GetTagged("ShellLight") do
		register(instance)
	end
	CollectionService:GetInstanceAddedSignal("ShellLight"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("ShellLight"):Connect(function(instance: Instance)
		lights[instance :: any] = nil
	end)

	sync(Store.Data())
	Store.Changed:Connect(function(snapshot: any)
		sync(if type(snapshot) == "table" then snapshot.Data else nil)
	end)
	Net.On("Fx", function(kind: string, payload: any)
		if kind == "Victory" then
			if os.clock() - cascadeAt > ShellGlow.CASCADE_SECONDS then
				cascadeAt = os.clock()
			end
		elseif kind == "WorldCleared" and type(payload) == "table" and type(payload.World) == "number" then
			-- Le Fx arrive souvent avant l'état : la vague part tout de suite.
			waves[payload.World] = os.clock()
			waves[0] = os.clock()
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < 1 / UPDATE_HZ then
			return
		end
		accumulator = 0
		local t = os.clock()
		-- Vagues terminées
		for w, startedAt in waves do
			if t - startedAt > ShellGlow.WAVE_SECONDS then
				waves[w] = nil
			end
		end
		-- Caméra dans la tour : la coque extérieure est invisible, on n'écrit rien (l'arc-en-ciel de
		-- la victoire et le vacillement reprennent dès qu'on ressort au lobby).
		local camera = Workspace.CurrentCamera
		if camera then
			local eye = camera.CFrame.Position
			if AppPages.InsideTower(eye.X, eye.Y, eye.Z) then
				return
			end
		end
		local calm = reduced()
		for part, light in lights do
			if part.Parent == nil then
				lights[part] = nil
			else
				local color, alpha = shade(light, t, calm)
				apply(light, color, alpha)
			end
		end
	end)
end

return TowerGlow
