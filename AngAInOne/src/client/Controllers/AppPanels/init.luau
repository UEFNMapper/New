--!strict
--[[
	AppPanels : les fenêtres de l'app AngAInOne accrochées aux parois de la tour (Tower/AppPanels),
	dessinées au style Fluent de l'app (Fluent.luau) et animées par la partie DU JOUEUR LOCAL
	(Pages.luau, valeurs : Util/AppPanelLogic) :
	- progression dans le monde de la fenêtre (Store : Stage, Cleared) ;
	- incidents de LAGZ dans ce monde (ReplicatedStorage.IncidentState via TrapClock) : coupure,
	  « Ne répond pas », secteurs corrompus, pic de lag, surchauffe, pub relancée ;
	- plantages de la session (Controllers/CrashLog) sur la page Plantages.
	Budget : un SurfaceGui n'existe que pour les fenêtres proches de la caméra (≤ VIEW_DISTANCE),
	détruit en s'éloignant ; mises à jour 4 fois par seconde. Compatible StreamingEnabled.

	Aussi :
	- ponts de chargement du monde 6 (Trap Kind = LoadBridge, World = 6) : bulle de l'app
	  « Téléchargement du pilote 610.47 · x % » au-dessus du pont (même avancement que le piège) ;
	- Anga géant du lobby (tag GiantAnga) : respiration lente et tête qui tourne doucement
	  (rien si ReducedMotion).
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

local Store = require(script.Parent.Store)
local CrashLog = require(script.Parent.CrashLog)
local TrapCommon = require(script.Parent.Traps.Common)
local LoadBridge = require(script.Parent.Traps.LoadBridge)
local Fluent = require(script.Fluent)
local Pages = require(script.Pages)

local AppPanels = {}

local player = Players.LocalPlayer

local VIEW_DISTANCE = 230 -- SurfaceGui créé en deçà, détruit au-delà (+ marge)
local UPDATE = 0.25
local CANVAS_WIDTH = 1200
local BRIDGE_DISTANCE = 150
local BRIDGE_WORLD = 6

type View = {
	Gui: SurfaceGui,
	Update: Pages.Updater?,
}

local panels: { [BasePart]: boolean } = {} -- fenêtres connues (streaming)
local views: { [BasePart]: View } = {} -- fenêtres dessinées (proches)

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
	local height = math.floor(CANVAS_WIDTH * part.Size.Y / math.max(part.Size.X, 0.1))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "AngAInOnePage"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(CANVAS_WIDTH, height)
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.MaxDistance = VIEW_DISTANCE + 40
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Fluent.C.Bg
	root.BorderSizePixel = 0
	root.Parent = gui
	local update: Pages.Updater? = nil
	if k == "LaunchBanner" then
		update = Pages.BuildBanner(root, CANVAS_WIDTH, height)
	elseif Pages.Has(k) then
		local window = Fluent.Window(root, {
			Width = CANVAS_WIDTH,
			Height = height,
			World = w,
			User = player.DisplayName,
		})
		update = Pages.Build(k, window)
	end
	gui.Parent = part
	return { Gui = gui, Update = update }
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

local function panelLoop()
	while true do
		task.wait(UPDATE)
		local camera = Workspace.CurrentCamera
		if camera then
			local eye = camera.CFrame.Position
			local now = Workspace:GetServerTimeNow()
			for part in panels do
				if part.Parent == nil then
					drop(part)
					panels[part] = nil
					continue
				end
				local view = views[part]
				local distance = (part.Position - eye).Magnitude
				-- Face avant tournée vers la caméra (on ne dessine pas le dos d'une fenêtre)
				local facing = part.CFrame.LookVector:Dot(eye - part.Position) > 0
				if view then
					if distance > VIEW_DISTANCE + 30 then
						drop(part)
					else
						refresh(part, view, now)
					end
				elseif distance < VIEW_DISTANCE and facing then
					local ok, built = pcall(build, part)
					if ok then
						views[part] = built
						refresh(part, built, now)
					else
						warn(`[AppPanels] construction : {built}`)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Ponts de chargement du monde 6 : « Téléchargement du pilote 610.47 · x % »
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

type Giant = {
	Model: Model,
	Head: { { Part: BasePart, Base: CFrame } },
	Pivot: Vector3,
	Right: Vector3,
	Base: CFrame?,
}

local giants: { [Model]: Giant } = {}

local function trackGiant(instance: Instance)
	if not instance:IsA("Model") or giants[instance] then
		return
	end
	local head = {}
	local holder = instance:FindFirstChild("Head")
	if holder then
		for _, d in holder:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(head, { Part = d, Base = d.CFrame })
			end
		end
	end
	local pivot = instance:GetAttribute("NeckPivot")
	giants[instance] = {
		Model = instance,
		Head = head,
		Pivot = if typeof(pivot) == "Vector3" then pivot else instance:GetPivot().Position,
		Right = instance:GetPivot().RightVector,
		-- Vrai modèle 3D (pas de tête séparée) : on fait « respirer » le modèle entier
		Base = if #head == 0 then instance:GetPivot() else nil,
	}
end

local function animateGiants()
	local rest = false
	RunService.Heartbeat:Connect(function()
		if not next(giants) then
			return
		end
		local still = reduced()
		if still and rest then
			return
		end
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local t = os.clock()
		for model, giant in giants do
			if model.Parent == nil then
				giants[model] = nil
				continue
			end
			if not still and (giant.Pivot - eye).Magnitude > 4000 then
				continue
			end
			local yaw = if still then 0 else math.rad(7) * math.sin(t * 0.33)
			local nod = if still then 0 else math.rad(2.5) * math.sin(t * 0.52 + 1)
			local breath = if still then 0 else 6 * math.sin(t * 1.1)
			if giant.Base then
				model:PivotTo((giant.Base :: CFrame) * CFrame.new(0, breath * 0.5, 0))
			else
				local pivot = giant.Pivot
				local turn = CFrame.new(pivot + Vector3.new(0, breath, 0))
					* CFrame.Angles(0, yaw, 0)
					* CFrame.fromAxisAngle(giant.Right, nod)
					* CFrame.new(-pivot)
				for _, entry in giant.Head do
					entry.Part.CFrame = turn * entry.Base
				end
			end
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
