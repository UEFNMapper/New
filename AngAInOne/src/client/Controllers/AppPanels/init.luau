--!strict
--[[
	AppPanels : les fenêtres de l'app AngAInOne accrochées aux parois de la tour (Tower/AppPanels),
	dessinées au style Fluent de l'app (Fluent.luau) et animées par la partie DU JOUEUR LOCAL
	(Pages.luau, valeurs : Util/AppPanelLogic) :
	- progression dans le monde de la fenêtre (Store : Stage, Cleared) ;
	- incidents de LAGZ dans ce monde (ReplicatedStorage.IncidentState via TrapClock) : coupure,
	  « Ne répond pas », secteurs corrompus, pic de lag, surchauffe, pub relancée ;
	- plantages de la session (Controllers/CrashLog) sur la page Plantages.
	Budget (mobile) :
	- seules les fenêtres du monde parcouru (Tower.RunWorld) et du suivant ont un SurfaceGui ; il
	  est détruit quand le monde sort de cette bande ;
	- distance mesurée depuis la RACINE du personnage (pas la caméra, qui tourne autour) :
	  affichée sous AppPages.PANEL_SHOW, masquée (Enabled = false, rien n'est détruit ni reconstruit)
	  au-delà de PANEL_HIDE (hystérésis de 70 studs) ;
	- toile de 800 px de large (mise en page Fluent / Pages sur 1 200 px logiques, UIScale) ;
	- mises à jour 4 fois par seconde, seulement pour les fenêtres affichées. Compatible StreamingEnabled.

	Aussi :
	- ponts de chargement du monde 6 (Trap Kind = LoadBridge, World = 6) : bulle de l'app
	  « Téléchargement du pilote 7.1 · x % » au-dessus du pont (même avancement que le piège) ;
	- Anga géant du lobby (tag GiantAnga) : respiration lente et tête qui tourne doucement
	  (rien si ReducedMotion), à 30 Hz et seulement quand la caméra est au lobby, près de lui.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AppPages = require(Shared.Util.AppPanelLogic)
local CrashLogic = require(Shared.Util.CrashLogic)
local TrapClock = require(Shared.Util.TrapClock)
local Tower = require(Shared.Config.Tower)

local Store = require(script.Parent.Store)
local CrashLog = require(script.Parent.CrashLog)
local TrapCommon = require(script.Parent.Traps.Common)
local LoadBridge = require(script.Parent.Traps.LoadBridge)
local Fluent = require(script.Fluent)
local Pages = require(script.Pages)

local AppPanels = {}

local player = Players.LocalPlayer

local UPDATE = 0.25
local LAYOUT_WIDTH = AppPages.PANEL_LAYOUT_WIDTH -- grille logique de Fluent / Pages
local CANVAS_WIDTH = AppPages.PANEL_CANVAS_WIDTH -- pixels réels de la toile
local GUI_MAX_DISTANCE = AppPages.PANEL_HIDE + 80 -- depuis la caméra (un peu derrière le joueur)
local BRIDGE_DISTANCE = 150
local BRIDGE_WORLD = 6
local GIANT_RANGE = AppPages.GIANT_RANGE -- Anga géant animé seulement si la caméra est plus près
local GIANT_HZ = 30

type View = {
	Gui: SurfaceGui,
	Update: Pages.Updater?,
	Shown: boolean,
}

local panels: { [BasePart]: boolean } = {} -- fenêtres connues (streaming)
local views: { [BasePart]: View } = {} -- fenêtres dessinées (bande de mondes active)

local function reduced(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

local function stateFor(world: number, now: number): Pages.State?
	local data = Store.Data()
	if not data then
		return nil
	end
	return {
		Progress = AppPages.Progress(world, data.Stage, data.Cleared),
		Cleared = data.Cleared,
		Incident = TrapClock.Incident(world),
		T = now,
		Exe = CrashLogic.ExeName(player.DisplayName),
		Crash = CrashLog.Log,
		Reduced = reduced(),
	}
end

------------------------------------------------------------------------------------
-- Fenêtres
------------------------------------------------------------------------------------

local function build(part: BasePart): View
	local world = part:GetAttribute("World")
	local kind = part:GetAttribute("Kind")
	local w = if type(world) == "number" then world else 1
	local k = if type(kind) == "string" then kind else ""
	-- Mise en page sur la grille logique (LAYOUT_WIDTH × height), réduite à la toile par UIScale :
	-- toutes les positions / tailles de Fluent et Pages (en px) restent proportionnelles.
	local ratio = part.Size.Y / math.max(part.Size.X, 0.1)
	local height = math.floor(LAYOUT_WIDTH * ratio)
	local scale = CANVAS_WIDTH / LAYOUT_WIDTH
	local gui = Instance.new("SurfaceGui")
	gui.Name = "AngAInOnePage"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(CANVAS_WIDTH, math.floor(CANVAS_WIDTH * ratio))
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.MaxDistance = GUI_MAX_DISTANCE
	gui.Enabled = false -- affichée par panelLoop (hystérésis)
	local root = Instance.new("Frame")
	root.Size = UDim2.fromOffset(LAYOUT_WIDTH, height)
	root.BackgroundColor3 = Fluent.C.Bg
	root.BorderSizePixel = 0
	root.Parent = gui
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = root
	local update: Pages.Updater? = nil
	if k == "LaunchBanner" then
		update = Pages.BuildBanner(root, LAYOUT_WIDTH, height)
	elseif Pages.Has(k) then
		local window = Fluent.Window(root, {
			Width = LAYOUT_WIDTH,
			Height = height,
			World = w,
			User = player.DisplayName,
		})
		update = Pages.Build(k, window)
	end
	gui.Parent = part
	return { Gui = gui, Update = update, Shown = false }
end

local function drop(part: BasePart)
	local view = views[part]
	if view then
		view.Gui:Destroy()
	end
	views[part] = nil
end

local function refresh(part: BasePart, view: View, now: number)
	local update = view.Update
	if not update then
		return
	end
	local world = part:GetAttribute("World")
	local state = stateFor(if type(world) == "number" then world else 1, now)
	if state then
		local ok = xpcall(update, function(err: any)
			warn(`[AppPanels] {part:GetAttribute("Kind")} : {err}`)
		end, state)
		if not ok then
			view.Update = nil
		end
	end
end

-- Monde parcouru par le joueur local (1 avant le départ).
local function runWorld(): number
	local data = Store.Data()
	return if data then Tower.RunWorld(data.Stage, data.Cleared) else 1
end

-- Point de référence : racine du personnage (stable), sinon la caméra (mort, chargement).
local function viewpoint(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function panelLoop()
	while true do
		task.wait(UPDATE)
		local eye = viewpoint()
		if not eye then
			continue
		end
		local now = Workspace:GetServerTimeNow()
		local current = runWorld()
		for part in panels do
			if part.Parent == nil then
				drop(part)
				panels[part] = nil
				continue
			end
			local attribute = part:GetAttribute("World")
			local world = if type(attribute) == "number" then attribute else 1
			local view = views[part]
			-- Hors de la bande « monde parcouru + suivant » : rien n'existe.
			if not AppPages.PanelWorldActive(world, current) then
				if view then
					drop(part)
				end
				continue
			end
			local distance = (part.Position - eye).Magnitude
			-- Face avant tournée vers le joueur (on ne dessine pas le dos d'une fenêtre)
			local facing = part.CFrame.LookVector:Dot(eye - part.Position) > 0
			local shown = AppPages.PanelShown(if view then view.Shown else false, distance, facing)
			if shown and not view then
				local ok, built = pcall(build, part)
				if not ok then
					warn(`[AppPanels] construction : {built}`)
					continue
				end
				view = built
				views[part] = built
			end
			if view then
				if view.Shown ~= shown then
					view.Shown = shown
					view.Gui.Enabled = shown
				end
				if shown then
					refresh(part, view, now)
				end
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Ponts de chargement du monde 6 : « Téléchargement du pilote 7.1 · x % »
------------------------------------------------------------------------------------

type Bridge = {
	Part: BasePart,
	Trap: any, -- sous-ensemble d'un piège (Period, Phase, Seed, Data.Segments) pour LoadBridge.Progress
	Gui: BillboardGui,
	Label: TextLabel,
	Fill: Frame,
}

local bridges: { [BasePart]: Bridge } = {}

local function trackBridge(instance: Instance)
	if not instance:IsA("BasePart") or bridges[instance] then
		return
	end
	if instance:GetAttribute("Kind") ~= "LoadBridge" or instance:GetAttribute("World") ~= BRIDGE_WORLD then
		return
	end
	-- Mêmes réglages que Traps/LoadBridge (graine = position de repos, lue à l'arrivée du pont)
	local trap = {
		Period = math.max(TrapCommon.Num(instance, "Period", 8), 3),
		Phase = TrapCommon.Num(instance, "Phase", 0),
		Seed = TrapCommon.SeedOf(instance.CFrame),
		Data = { Segments = math.clamp(math.floor(TrapCommon.Num(instance, "Segments", 8)), 2, 24) },
	}
	local gui = Instance.new("BillboardGui")
	gui.Name = "AngAInOneDownload"
	gui.Size = UDim2.fromOffset(340, 58)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	gui.MaxDistance = BRIDGE_DISTANCE
	gui.LightInfluence = 0
	gui.Adornee = instance
	local card = Fluent.Card(gui, 0, 0, 340, 58)
	card.BackgroundTransparency = 0.08
	Fluent.Text(card, "↓", 8, 4, 30, 30, 20, { Color = Fluent.C.Dim, Align = "Center" })
	local label = Fluent.Text(card, "", 40, 4, 292, 30, 16, { Weight = "Medium" })
	local fill = Fluent.Bar(card, 12, 40, 316, 8, Fluent.C.AccentSoft)
	gui.Parent = instance
	bridges[instance] = { Part = instance, Trap = trap, Gui = gui, Label = label, Fill = fill }
end

local function bridgeLoop()
	while true do
		task.wait(0.1)
		if next(bridges) then
			local camera = Workspace.CurrentCamera
			local eye = if camera then camera.CFrame.Position else Vector3.zero
			local t = TrapClock.Now(BRIDGE_WORLD)
			for part, bridge in bridges do
				if part.Parent == nil then
					bridges[part] = nil
				elseif (part.Position - eye).Magnitude < BRIDGE_DISTANCE then
					local progress, phase = LoadBridge.Progress(bridge.Trap, t)
					local text = AppPages.BridgeLabel(progress, phase)
					if bridge.Label.Text ~= text then
						bridge.Label.Text = text
					end
					local shown = if phase == LoadBridge.EMPTY then 0 else progress
					Fluent.SetBar(
						bridge.Fill,
						shown,
						if phase == LoadBridge.STALL
							then Fluent.C.Warn
							elseif shown >= 1 then Fluent.C.Good
							else Fluent.C.AccentSoft
					)
				end
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Anga géant du lobby : respiration et tête qui tourne doucement
------------------------------------------------------------------------------------

-- Seule la tête bouge, en UN PivotTo de son groupe « Head » (décor de secours en primitives).
-- Le vrai modèle 3D (pas de groupe Head séparé) reste immobile : bouger tout le modèle coûtait trop.
type Giant = {
	Model: Model,
	Head: Model,
	HeadBase: CFrame, -- pivot du groupe Head au repos
	Pivot: Vector3, -- cou (attribut NeckPivot)
	Center: Vector3, -- centre de la boîte englobante (test de distance)
	Right: Vector3,
}

local giants: { [Model]: Giant } = {}

local function trackGiant(instance: Instance)
	if not instance:IsA("Model") or giants[instance] then
		return
	end
	-- (StreamingEnabled : la tête peut arriver un peu après le modèle)
	local head = instance:WaitForChild("Head", 10)
	if not (head and head:IsA("Model")) or giants[instance] or instance.Parent == nil then
		return -- vrai modèle 3D (sa tête est une simple pièce) : pas d'animation
	end
	local pivot = instance:GetAttribute("NeckPivot")
	local center = instance:GetBoundingBox().Position
	giants[instance] = {
		Model = instance,
		Head = head,
		HeadBase = head:GetPivot(),
		Pivot = if typeof(pivot) == "Vector3" then pivot else instance:GetPivot().Position,
		Center = center,
		Right = instance:GetPivot().RightVector,
	}
end

-- La caméra voit-elle l'Anga géant ? Au lobby (hors de la tour) et à moins de GIANT_RANGE de lui.
local function giantVisible(giant: Giant, eye: Vector3): boolean
	return not AppPages.InsideTower(eye.X, eye.Y, eye.Z) and (giant.Center - eye).Magnitude < GIANT_RANGE
end

local function animateGiants()
	local rest = false
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < 1 / GIANT_HZ or not next(giants) then
			return
		end
		accumulator = 0
		local still = reduced()
		if still and rest then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local t = os.clock()
		for model, giant in giants do
			if model.Parent == nil or giant.Head.Parent == nil then
				giants[model] = nil
				continue
			end
			-- ReducedMotion : on repose la tête une fois, même hors de vue.
			if not still and not giantVisible(giant, eye) then
				continue
			end
			local yaw = if still then 0 else math.rad(7) * math.sin(t * 0.33)
			local nod = if still then 0 else math.rad(2.5) * math.sin(t * 0.52 + 1)
			local breath = if still then 0 else 6 * math.sin(t * 1.1)
			local pivot = giant.Pivot
			local turn = CFrame.new(pivot + Vector3.new(0, breath, 0))
				* CFrame.Angles(0, yaw, 0)
				* CFrame.fromAxisAngle(giant.Right, nod)
				* CFrame.new(-pivot)
			giant.Head:PivotTo(turn * giant.HeadBase)
		end
		rest = still
	end)
end

------------------------------------------------------------------------------------

local function watch(tag: string, onAdd: (Instance) -> (), onRemove: ((Instance) -> ())?)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdd, instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(onAdd)
	if onRemove then
		CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemove)
	end
end

function AppPanels.Start()
	watch("AppPanel", function(instance: Instance)
		if instance:IsA("BasePart") then
			panels[instance] = true
		end
	end, function(instance: Instance)
		if instance:IsA("BasePart") then
			drop(instance)
			panels[instance] = nil
		end
	end)
	watch("Trap", trackBridge, function(instance: Instance)
		local bridge = bridges[instance :: any]
		if bridge then
			bridge.Gui:Destroy()
			bridges[instance :: any] = nil
		end
	end)
	watch("GiantAnga", trackGiant, function(instance: Instance)
		giants[instance :: any] = nil
	end)
	task.spawn(panelLoop)
	task.spawn(bridgeLoop)
	animateGiants()
end

return AppPanels
