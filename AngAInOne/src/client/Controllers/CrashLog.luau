--!strict
--[[
	CrashLog : chaque mort du joueur local devient un « plantage », façon page Plantages de l'app
	AngAInOne. Petite carte discrète ~2,5 s en haut à GAUCHE, sous la colonne Bits / passes du HUD
	(x 16..312, y 216..308) : elle ne cache ni le menu « ⋯ » (en haut à droite), ni la carte de
	progression (x ≥ 320), ni la barre du boss (y ≥ 344), ni le dock ; jamais au centre :
	    (!)  Joueur.exe s'est fermé tout seul
	         cause : Ventilateur · 3e fois ici
	Compteurs de la session par cause et par monde (Util/CrashLogic), lus aussi par la fenêtre
	« Plantages » du monde 7 (Controllers/AppPanels).

	Cause de la mort : TrapController l'envoie au serveur (ReportDeath) mais l'effet serveur
	Fx "Death" ne la transmet pas ; on se branche donc EN LECTURE sur TrapController.OnDeath
	(le rappel déjà posé est conservé et appelé d'abord). Déclencheur : Humanoid.Died du personnage
	local (toute mort, même sans piège : cause inconnue).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Signal = require(Shared.Packages.Signal)
local CrashLogic = require(Shared.Util.CrashLogic)

local Store = require(script.Parent.Store)
local Fluent = require(script.Parent.AppPanels.Fluent)
local Create = require(script.Parent.Parent.UI.Create)
local Motion = require(script.Parent.Parent.UI.Motion)

local New = Create.New
local C = Fluent.C

local CrashLog = {}

CrashLog.Log = CrashLogic.new()
CrashLog.Changed = Signal.new() :: Signal.Signal<CrashLogic.Log>

local player = Players.LocalPlayer
local SHOW_SECONDS = 2.6
local CAUSE_WINDOW = 1.5 -- une cause notée par TrapController vaut pour la mort qui suit de près
-- Pixels de conception : colonne de gauche du HUD jusqu'à y = 204 (Bits + 2 passes + bouclier)
local LEFT, TOP = 16, 216
local WIDTH, HEIGHT = 296, 92
local TEXT_X = 50

local pendingCause: string? = nil
local pendingAt = -math.huge
local card: Frame? = nil
local titleLabel: TextLabel? = nil
local detailLabel: TextLabel? = nil
local shownAt = 0

-- Texte lisible sur téléphone : 18 px de conception au minimum, rétréci jusque-là si besoin.
local function fit(label: TextLabel, maxSize: number)
	label.TextScaled = true
	New("UITextSizeConstraint", { MinTextSize = 18, MaxTextSize = maxSize, Parent = label })
end

local function build(layer: Frame)
	-- En haut à gauche, sous la colonne Bits / passes / bouclier du HUD
	local frame = Fluent.Card(layer, 0, 0, WIDTH, HEIGHT)
	frame.Name = "CrashLog"
	frame.Position = UDim2.fromOffset(LEFT, TOP)
	frame.BackgroundTransparency = 0.06
	frame.Visible = false
	frame.Active = false
	frame.ZIndex = 5
	Fluent.Glyph(frame, 12, math.floor(HEIGHT / 2) - 13, 26, "!", C.Bad)
	-- Titre sur 2 lignes au besoin (« Pseudo.exe s'est fermé tout seul »), puis la cause
	titleLabel = Fluent.Text(frame, "", TEXT_X, 6, WIDTH - TEXT_X - 10, 48, 20, { Weight = "Medium", Wrap = true })
	detailLabel = Fluent.Text(frame, "", TEXT_X, 58, WIDTH - TEXT_X - 10, 26, 18, { Color = C.Dim })
	if titleLabel and detailLabel then
		fit(titleLabel, 20)
		fit(detailLabel, 18)
	end
	local accent = Fluent.Box(frame, 0, 10, 3, HEIGHT - 20, C.Bad, 2)
	accent.Name = "Accent"
	for _, d in frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 6
		end
	end
	New("UIScale", { Name = "MotionScale", Parent = frame })
	card = frame
end

local function show(title: string, detail: string)
	local frame = card
	if not frame or not titleLabel or not detailLabel then
		return
	end
	titleLabel.Text = title
	detailLabel.Text = detail
	frame.Visible = true
	frame.Position = UDim2.fromOffset(-WIDTH - 24, TOP)
	Motion.Tween(frame, { Position = UDim2.fromOffset(LEFT, TOP) }, 0.25)
	local stamp = os.clock()
	shownAt = stamp
	task.delay(SHOW_SECONDS, function()
		if shownAt == stamp and card then
			local tween = Motion.Tween(frame, { Position = UDim2.fromOffset(-WIDTH - 24, TOP) }, 0.3)
			tween.Completed:Connect(function()
				if shownAt == stamp then
					frame.Visible = false
				end
			end)
		end
	end)
end

-- Monde où l'on se trouve (0 = lobby) : le « ici » de la carte.
local function currentWorld(): number
	local data = Store.Data()
	if not data then
		return 0
	end
	return if data.Stage <= 0 and data.Cleared <= 0 then 0 else Tower.RunWorld(data.Stage, data.Cleared)
end

local function onDied()
	-- La cause arrive par TrapController.OnDeath (tâche lancée au même moment que la mort)
	task.wait(0.15)
	local cause = if os.clock() - pendingAt <= CAUSE_WINDOW then pendingCause else nil
	pendingCause = nil
	local count = CrashLogic.Record(CrashLog.Log, cause, currentWorld())
	local title, detail = CrashLogic.Format(CrashLogic.ExeName(player.DisplayName), cause, count)
	show(title, detail)
	CrashLog.Changed:Fire(CrashLog.Log)
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(onDied)
	end
end

-- Note la cause d'une mort (rappel TrapController.OnDeath).
function CrashLog.NoteCause(cause: string)
	pendingCause = cause
	pendingAt = os.clock()
end

function CrashLog.Start(layer: Frame)
	build(layer)
	-- Branchement en lecture sur TrapController.OnDeath : on garde le rappel existant
	local ok, TrapController = pcall(require, script.Parent.TrapController)
	if ok and TrapController then
		local previous = TrapController.OnDeath
		TrapController.OnDeath = function(cause: string)
			if previous then
				previous(cause)
			end
			CrashLog.NoteCause(cause)
		end
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

return CrashLog
