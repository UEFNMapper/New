--!strict
--[[
	Epreuves (client) : joue l'épreuve 3D de la salle du terminal (Config/Epreuves ; décor :
	World/Tower/Epreuves ; règles pures : Shared/EpreuveLogic ; jeu de chaque épreuve :
	Controllers/EpreuveKinds/<Kind>).

	Start(world) : envoie MinigameStart (le serveur vérifie qu'on est à la borne), affiche la carte
	d'épreuve (UI/Screens/EpreuveHud) et lance le jeu. Réussie : MinigameEnd(world, true, score) →
	le serveur nettoie le monde (portail ouvert, médaille…). Ratée (chute dans la lave, processeur
	saturé, mort, sortie de la salle, « Abandonner ») : MinigameEnd(world, false, 0) et le décor
	revient à son état de départ ; on relance depuis la borne.
	Monde 7 (Investigation) : pas de validation serveur ; `onWin` enchaîne la phase finale du combat.

	Chaque épreuve reçoit un objet `Run` (outils communs : repère de la salle, prompts locaux,
	panneaux AppBoard, cases à cocher, sons, nettoyage) et renvoie éventuellement une fonction
	`Restore` appelée quand le monde redevient infecté (nouvelle ascension).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local EpreuveConfig = require(Shared.Config.Epreuves)

local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local SpeedControl = require(script.Parent.SpeedControl)
local TrapController = require(script.Parent.TrapController)
local Feedback = require(script.Parent.Feedback)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)
local Dialogue = require(script.Parent.Parent.UI.Screens.Dialogue)
local HUD = require(script.Parent.Parent.UI.Screens.HUD)
local EpreuveHud = require(script.Parent.Parent.UI.Screens.EpreuveHud)

local Epreuves = {}

local player = Players.LocalPlayer

-- Panneau AppBoard (SurfaceGui posée par le serveur) : mise à jour de ses éléments nommés.
export type Board = {
	Row: (self: Board, index: number, value: string, color: string?) -> (),
	Step: (self: Board, index: number, done: boolean) -> (),
	Title: (self: Board, text: string) -> (),
	Big: (self: Board, value: string, caption: string?, color: string?) -> (),
	Bar: (self: Board, fraction: number, label: string?, color: string?) -> (),
}

export type Run = {
	World: number,
	Def: EpreuveConfig.Epreuve,
	Folder: Instance,
	Terminal: Instance,
	Origin: Vector3,
	F: Vector3,
	R: Vector3,
	At: (u: number, h: number, v: number) -> Vector3,
	ToRoom: (position: Vector3) -> (number, number, number),
	Find: (name: string) -> Instance?,
	Children: (prefix: string) -> { Instance },
	Board: (part: Instance?) -> Board,
	Step: (index: number, done: boolean, text: string?) -> (),
	Status: (text: string) -> (),
	Bar: (fraction: number?, text: string?) -> (),
	Say: (text: string, seconds: number?) -> (),
	Toast: (kind: string, text: string) -> (),
	Sound: (name: string, pitch: number?) -> (),
	Confetti: (position: Vector3?, count: number?) -> (),
	Prompt: (
		parent: Instance,
		action: string,
		object: string,
		hold: number?,
		distance: number?,
		onTrigger: () -> ()
	) -> ProximityPrompt,
	Every: (step: (dt: number) -> ()) -> (),
	Delay: (seconds: number, fn: () -> ()) -> (),
	Add: (item: any) -> (),
	Root: () -> BasePart?,
	Humanoid: () -> Humanoid?,
	Win: (score: number) -> (),
	Fail: (reason: string) -> (),
	Kill: (cause: string) -> (),
	Speed: (factor: number?) -> (),
	Running: () -> boolean,
}

export type Kind = (run: Run) -> (() -> ())?

local KINDS: { [string]: Kind } = {}
local kindsFolder = script.Parent:FindFirstChild("EpreuveKinds")
if kindsFolder then
	for _, module in kindsFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, kind = pcall(require, module)
			if ok and type(kind) == "function" then
				KINDS[module.Name] = kind :: Kind
			else
				warn(`[Epreuves] épreuve {module.Name} : {kind}`)
			end
		end
	end
end

local running: { World: number, Stop: (success: boolean) -> () }? = nil
local restores: { [number]: () -> () } = {}

------------------------------------------------------------------------------------
-- Panneaux AppBoard
------------------------------------------------------------------------------------

local function boardFor(part: Instance?): Board
	local gui = if part then part:FindFirstChild("AppBoard") else nil
	local body = if gui then gui:FindFirstChild("Body", true) else nil
	local function find(name: string): Instance?
		return if body then body:FindFirstChild(name) else nil
	end
	local board = {}
	function board.Row(_self: Board, index: number, value: string, color: string?)
		local row = find(`Row{index}`)
		local label = if row then row:FindFirstChild("Value") else nil
		if label and label:IsA("TextLabel") then
			label.Text = value
			if color then
				label.TextColor3 = Color3.fromHex(color)
			end
		end
	end
	function board.Step(_self: Board, index: number, done: boolean)
		local row = find(`Step{index}`)
		local check = if row then row:FindFirstChild("Check") else nil
		if check and check:IsA("TextLabel") then
			check.Text = if done then "✓" else "○"
			check.TextColor3 = Color3.fromHex(if done then "6CCB5F" else "8F8F8F")
		end
	end
	function board.Title(_self: Board, text: string)
		local label = find("Title")
		if label and label:IsA("TextLabel") then
			label.Text = text
		end
	end
	function board.Big(_self: Board, value: string, caption: string?, color: string?)
		local big = find("Big")
		local valueLabel = if big then big:FindFirstChild("Value") else nil
		local captionLabel = if big then big:FindFirstChild("Caption") else nil
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = value
			if color then
				valueLabel.TextColor3 = Color3.fromHex(color)
			end
		end
		if caption and captionLabel and captionLabel:IsA("TextLabel") then
			captionLabel.Text = caption
		end
	end
	function board.Bar(_self: Board, fraction: number, label: string?, color: string?)
		local bar = find("Bar")
		local fill = if bar then bar:FindFirstChild("Fill", true) else nil
		local text = if bar then bar:FindFirstChild("Label") else nil
		if fill and fill:IsA("Frame") then
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			if color then
				fill.BackgroundColor3 = Color3.fromHex(color)
			end
		end
		if label and text and text:IsA("TextLabel") then
			text.Text = label
		end
	end
	return (board :: any) :: Board
end

------------------------------------------------------------------------------------

local function folderFor(world: number): Instance?
	local tower = Workspace:FindFirstChild("Tower")
	local model = if tower then tower:FindFirstChild(`World{world}`) else nil
	local terminal = if model then model:FindFirstChild("Terminal") else nil
	return if terminal then terminal:FindFirstChild("Epreuve") else nil
end

function Epreuves.Has(world: number): boolean
	local def = EpreuveConfig.ByWorld[world]
	return def ~= nil and KINDS[def.Kind] ~= nil
end

function Epreuves.IsRunning(): boolean
	return running ~= nil
end

-- Lance l'épreuve du monde. `onWin` (monde 7) : appelé après la réussite à la place de MinigameEnd.
function Epreuves.Start(world: number, onWin: (() -> ())?): boolean
	if running then
		return false
	end
	local def = EpreuveConfig.ByWorld[world]
	local kind = if def then KINDS[def.Kind] else nil
	local folder = folderFor(world)
	if not def or not kind or not folder then
		return false
	end
	local terminal = folder.Parent :: Instance
	local origin = folder:GetAttribute("Origin")
	local axisF = folder:GetAttribute("AxisF")
	local axisR = folder:GetAttribute("AxisR")
	if typeof(origin) ~= "Vector3" or typeof(axisF) ~= "Vector3" or typeof(axisR) ~= "Vector3" then
		return false
	end
	local validated = EpreuveConfig.ClearsWorld(world)
	if validated then
		Net.Fire("MinigameStart", world)
	end

	local cleanup: { any } = {}
	local alive = true
	local finished = false
	local stop: (success: boolean) -> ()

	local function add(item: any)
		table.insert(cleanup, item)
	end

	local run = {} :: any
	run.World = world
	run.Def = def
	run.Folder = folder
	run.Terminal = terminal
	run.Origin = origin
	run.F = axisF
	run.R = axisR
	function run.At(u: number, h: number, v: number): Vector3
		return origin + axisF * u + axisR * v + Vector3.new(0, h, 0)
	end
	function run.ToRoom(position: Vector3): (number, number, number)
		local d = position - origin
		return d:Dot(axisF), d.Y, d:Dot(axisR)
	end
	function run.Find(name: string): Instance?
		return folder:FindFirstChild(name, true) or terminal:FindFirstChild(name, true)
	end
	function run.Children(prefix: string): { Instance }
		local list = {}
		for _, child in folder:GetDescendants() do
			if string.sub(child.Name, 1, #prefix) == prefix then
				table.insert(list, child)
			end
		end
		return list
	end
	run.Board = boardFor
	run.Step = EpreuveHud.Step
	run.Status = EpreuveHud.Status
	run.Bar = EpreuveHud.Bar
	function run.Say(text: string, seconds: number?)
		Dialogue.Say(text, seconds or 4.5, "AIO")
	end
	run.Toast = Toasts.Show
	function run.Sound(name: string, pitch: number?)
		pcall(Audio.Play, name, pitch)
	end
	run.Confetti = Feedback.Confetti
	function run.Prompt(
		parent: Instance,
		action: string,
		object: string,
		hold: number?,
		distance: number?,
		onTrigger: () -> ()
	): ProximityPrompt
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = action
		prompt.ObjectText = object
		prompt.HoldDuration = hold or 0
		prompt.MaxActivationDistance = distance or 10
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = parent
		add(prompt)
		add(prompt.Triggered:Connect(function()
			if alive then
				onTrigger()
			end
		end))
		return prompt
	end
	function run.Every(step: (dt: number) -> ())
		add(RunService.Heartbeat:Connect(function(dt: number)
			if alive then
				step(dt)
			end
		end))
	end
	function run.Delay(seconds: number, fn: () -> ())
		task.delay(seconds, function()
			if alive then
				fn()
			end
		end)
	end
	run.Add = add
	function run.Root(): BasePart?
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		return if root and root:IsA("BasePart") then root else nil
	end
	function run.Humanoid(): Humanoid?
		local character = player.Character
		return if character then character:FindFirstChildOfClass("Humanoid") else nil
	end
	function run.Win(score: number)
		if finished then
			return
		end
		finished = true
		Audio.Play("Achievement")
		Feedback.Confetti(nil, 90)
		run.Say(def.Done, 6)
		run.Status("✓ Réparé")
		run.Delay(1.4, function()
			stop(true)
			if onWin then
				onWin()
			elseif validated then
				Net.Fire("MinigameEnd", world, true, math.clamp(math.floor(score), 0, 100))
			end
		end)
	end
	function run.Fail(reason: string)
		if finished then
			return
		end
		finished = true
		Toasts.Show("Info", `{reason} · Relance l'épreuve depuis la borne.`)
		stop(false)
		if validated then
			Net.Fire("MinigameEnd", world, false, 0)
		end
	end
	function run.Kill(cause: string)
		TrapController.Kill(cause)
	end
	function run.Speed(factor: number?)
		SpeedControl.SetFactor("Epreuve", factor)
	end
	function run.Running(): boolean
		return alive and not finished
	end

	stop = function(success: boolean)
		if not alive then
			return
		end
		alive = false
		running = nil
		SpeedControl.SetFactor("Epreuve", nil)
		EpreuveHud.Hide()
		HUD.SetProgressVisible(true)
		for i = #cleanup, 1, -1 do
			local item = cleanup[i]
			local kindOf = typeof(item)
			if kindOf == "RBXScriptConnection" then
				item:Disconnect()
			elseif kindOf == "Instance" then
				item:Destroy()
			elseif kindOf == "function" then
				pcall(item)
			end
		end
		local restore = run.RestoreFn
		if restore then
			if success then
				restores[world] = restore -- le décor « réparé » reste jusqu'à la prochaine ascension
			else
				pcall(restore)
			end
		end
	end

	running = { World = world, Stop = stop }
	HUD.SetProgressVisible(false)
	EpreuveHud.Show(def, function()
		run.Fail("Épreuve abandonnée")
	end)
	-- Fin de l'épreuve : mort du personnage, sortie de la salle
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		add(humanoid.Died:Connect(function()
			run.Fail("Oups, réessaie")
		end))
	end
	add(player.CharacterAdded:Connect(function()
		run.Fail("Oups, réessaie")
	end))
	add(Store.Changed:Connect(function(state: any)
		local data = state and state.Data
		if data and (state.AtLobby or data.Stage ~= Tower.TerminalStage(world)) then
			run.Fail("Tu as quitté la salle")
		end
	end))
	local ok, result = pcall(kind, run :: Run)
	if not ok then
		warn(`[Epreuves] {def.Kind} : {result}`)
		run.Fail("Petit souci technique")
		return false
	end
	run.RestoreFn = result
	run.Sound("PowerOn", 1)
	return true
end

function Epreuves.Stop()
	local current = running
	if current then
		current.Stop(false)
	end
end

function Epreuves.Init()
	-- Nouvelle ascension : les salles redeviennent infectées, leur décor revient à l'état de départ.
	Store.Changed:Connect(function(state: any)
		local data = state and state.Data
		if not data then
			return
		end
		for world, restore in restores do
			if data.Cleared < world then
				restores[world] = nil
				pcall(restore)
			end
		end
	end)
end

return Epreuves
