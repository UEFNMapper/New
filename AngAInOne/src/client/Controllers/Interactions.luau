--!strict
--[[
	Interactions : les prompts du monde (E / X manette / tap).
	- "Minigame" (terminal antivirus en fin de monde) : lance le mini-jeu 2D du monde ; au monde 7,
	  c'est la phase 3 du combat contre LAGZ (bouclier détruit, Firewall boss = difficulté 8)
	- "Arcade" (lobby) : choisir un mini-jeu pour gagner quelques Bits
	- "Shop" / "Daily" (lobby) : ouvrent la boutique / les missions
	Le serveur valide tout (bon checkpoint, distance, durée).
	Fin de partie : une victoire est envoyée DÈS qu'elle est acquise (MinigamePanel, onWin) ;
	l'écran de réussite (fermeture auto en 6 s) ne compte donc pas dans le temps du monde.
	Échec ou abandon : envoyés à la fermeture, comme avant. Un seul envoi par essai ; RÉESSAYER
	relance le chrono du serveur (…Start) et rouvre l'envoi.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local BossLogic = require(Shared.Util.BossLogic)

local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local App = require(script.Parent.Parent.UI.App)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)
local Dialogue = require(script.Parent.Parent.UI.Screens.Dialogue)
local Audio = require(script.Parent.Audio)
local MinigamePanel = require(script.Parent.Parent.UI.Screens.MinigamePanel)

local Interactions = {}

-- Rappels de fin de partie : `send(success, score)` part une seule fois par essai (victoire
-- tout de suite, sinon à la fermeture) ; `restart()` rouvre l'envoi pour un nouvel essai.
local function reporter(send: (success: boolean, score: number) -> ())
	local sent = false
	local function report(success: boolean, score: number)
		if sent then
			return
		end
		sent = true
		send(success, score)
	end
	local onWin = function(score: number, _duration: number)
		report(true, score)
	end
	local onDone = function(success: boolean, score: number, _duration: number)
		report(success, score)
	end
	local function restart()
		sent = false
	end
	return onDone, onWin, restart
end

-- Lance le terminal antivirus du monde `world`.
function Interactions.PlayTerminal(world: number)
	local data = Store.Data()
	local def = Tower.Worlds[world]
	if not data or not def or MinigamePanel.IsPlaying() then
		return
	end
	if data.Cleared >= world then
		Toasts.Show("Success", "Ce terminal est déjà nettoyé. Le portail est ouvert !")
		return
	end
	if data.Stage ~= Tower.TerminalStage(world) or data.Cleared ~= world - 1 then
		Toasts.Show("Info", "Atteins d'abord le checkpoint de cette salle !")
		return
	end
	local boss = world == BossLogic.WORLD
	if boss and Players.LocalPlayer:GetAttribute("BossPhase") ~= BossLogic.Phase.Terminal then
		Toasts.Show("Info", "Le bouclier de LAGZ protège ce terminal : branche d'abord les 3 prises antivirus !")
		return
	end
	Net.Fire("MinigameStart", world)
	local difficulty = if boss then BossLogic.BOSS_DIFFICULTY else world
	local onDone, onWin, restart = reporter(function(success: boolean, score: number)
		Net.Fire("MinigameEnd", world, success, score)
	end)
	MinigamePanel.Play(def.Minigame, difficulty, onDone, function()
		restart()
		Net.Fire("MinigameStart", world) -- nouvel essai : le serveur relance son chrono
	end, onWin)
end

-- Partie d'arcade (lobby) : petite récompense, avec un délai entre deux gains.
function Interactions.PlayArcade(kind: string)
	if MinigamePanel.IsPlaying() then
		return
	end
	App.Close()
	Net.Fire("ArcadeStart", kind)
	local onDone, onWin, restart = reporter(function(success: boolean, score: number)
		Net.Fire("ArcadeEnd", kind, success, score)
	end)
	MinigamePanel.Play(kind, 2, onDone, function()
		restart()
		Net.Fire("ArcadeStart", kind)
	end, onWin)
end

------------------------------------------------------------------------------------
-- Easter eggs (World/Tower/EasterEggs) : réactions locales, jamais compétitives
------------------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local talkCount = 0
local pasteCount = 0
local rgbUntil = 0

local SERVICE_LINES = {
	"Avez-vous essayé de redémarrer ?",
	"Avez-vous essayé de l'éteindre, puis de le rallumer ?",
	"Redémarrez. Ça règle 80 % des problèmes. Les 20 % restants aussi.",
	"Je suis le Service. Je tourne en fond, 24 h/24. Avez-vous essayé de redémarrer ?",
	"Mon diagnostic : il faudrait redémarrer.",
}

-- Le câble HDMI : la fiche glisse dans la prise, ding, badge « Avez-vous essayé de le rebrancher ? »
local function plugCable(prompt: ProximityPrompt)
	local plug = prompt.Parent
	local folder = if plug then plug.Parent else nil
	local socket = if folder then folder:FindFirstChild("HdmiSocket") else nil
	if not (plug and plug:IsA("BasePart") and socket and socket:IsA("BasePart")) then
		return
	end
	prompt.Enabled = false
	local target = socket.CFrame * CFrame.new(0, 0, -1.4)
	TweenService:Create(plug, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target })
		:Play()
	task.delay(0.6, function()
		Audio.Play("Unlock", 1.2)
		Toasts.Show("Success", "Avez-vous essayé de le rebrancher ? ✓ Câble HDMI branché")
		Dialogue.Say("Ah, c'était ça, l'écran noir. Classique.", 4, "AIO")
	end)
end

-- « Le Service » : répond à tout « Avez-vous essayé de redémarrer ? » ; à la 10e, il redémarre lui-même
local function talkToService(prompt: ProximityPrompt)
	talkCount += 1
	local npc = if prompt.Parent then prompt.Parent.Parent else nil
	if talkCount == 1 then
		Dialogue.Say("Je suis le Service. Je ne dors jamais. Que puis-je pour vous ?", 4, "AIO")
	elseif talkCount >= 10 and npc then
		talkCount = 0
		Dialogue.Say("…Très bien. Je vais redémarrer MOI-MÊME.", 3, "AIO")
		local saved: { [BasePart]: number } = {}
		for _, part in npc:GetDescendants() do
			if part:IsA("BasePart") then
				saved[part] = part.LocalTransparencyModifier
				part.LocalTransparencyModifier = 1
			end
		end
		prompt.Enabled = false
		Audio.Play("PowerOn", 0.8)
		task.delay(3, function()
			for part, value in saved do
				part.LocalTransparencyModifier = value
			end
			prompt.Enabled = true
			Audio.Play("Unlock", 1.1)
			Toasts.Show("Milestone", "Le Service a redémarré. Rien n'a changé. Comme prévu.")
		end)
	else
		Dialogue.Say(SERVICE_LINES[(talkCount - 2) % #SERVICE_LINES + 1], 3.5, "AIO")
	end
end

-- La pâte thermique : une fois, parfait ; deux fois, le processeur du monde 5 disparaît sous la pâte
local function applyPaste(_prompt: ProximityPrompt)
	pasteCount += 1
	Audio.Play("Collect", 0.9)
	if pasteCount == 1 then
		Toasts.Show("Success", "Pâte thermique appliquée : un grain de riz, −10 °C. Parfait.")
		return
	end
	Toasts.Show(
		"Reward",
		if pasteCount == 2
			then "Trop de pâte ! Le processeur est recouvert… (classique)"
			else "C'est… beaucoup de pâte. Anga ne regarde pas."
	)
	local tower = Workspace:FindFirstChild("Tower")
	local world = if tower then tower:FindFirstChild("World5") else nil
	local decor = if world then world:FindFirstChild("Decor") else nil
	local chip = if decor then decor:FindFirstChild("CpuChip") else nil
	if not chip then
		return
	end
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in chip:GetDescendants() do
		if part:IsA("BasePart") then
			lo = lo:Min(part.Position - part.Size / 2)
			hi = hi:Max(part.Position + part.Size / 2)
		end
	end
	if lo.X == math.huge then
		return
	end
	local blob = Instance.new("Part")
	blob.Name = "ThermalPasteBlob"
	blob.Shape = Enum.PartType.Ball
	blob.Size = Vector3.one * math.max(hi.X - lo.X, hi.Z - lo.Z) * 0.9
	blob.CFrame = CFrame.new((lo.X + hi.X) / 2, hi.Y + 2, (lo.Z + hi.Z) / 2)
	blob.Color = Color3.fromRGB(190, 190, 200)
	blob.Material = Enum.Material.SmoothPlastic
	blob.Transparency = 0.15
	blob.Anchored = true
	blob.CanCollide = false
	blob.CanQuery = false
	blob.CanTouch = false
	blob.Parent = Workspace
	task.delay(25, function()
		blob:Destroy()
	end)
end

-- « RGB = +10 FPS » : 10 secondes de marche plus rapide (local, sans effet sur les records), et des couleurs
local function rgbSwitch(prompt: ProximityPrompt)
	if os.clock() < rgbUntil then
		Toasts.Show("Boost", "Le RGB est déjà au maximum. Patience.")
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid then
		return
	end
	rgbUntil = os.clock() + 10
	Audio.Play("PowerOn", 1.1)
	Toasts.Show("Boost", "RGB activé : +10 FPS ! (en vitesse de marche, pendant 10 s)")
	local base = humanoid.WalkSpeed
	humanoid.WalkSpeed = base + 10
	local lever = if prompt.Parent and prompt.Parent.Parent
		then prompt.Parent.Parent:FindFirstChild("RgbLever")
		else nil
	local tick = 0
	while os.clock() < rgbUntil do
		if lever and lever:IsA("BasePart") then
			lever.Color = Color3.fromHSV((tick * 0.08) % 1, 0.9, 1)
		end
		tick += 1
		task.wait(0.1)
	end
	if humanoid.Parent and humanoid.WalkSpeed == base + 10 then
		humanoid.WalkSpeed = base
	end
end

-- AngATV, le dev caché sur le toit du dernier monde
local function meetDev(_prompt: ProximityPrompt)
	Audio.Play("Achievement", 0.7)
	Dialogue.Say("Tu m'as trouvé. Le PC est entre de bonnes mains.", 6, "AIO")
	Toasts.Show("Milestone", "Secret trouvé : AngATV, le dev. Merci d'avoir joué !")
end

local HANDLERS: { [string]: (prompt: ProximityPrompt) -> () } = {
	Plug = plugCable,
	Talk = talkToService,
	Paste = applyPaste,
	Rgb = rgbSwitch,
	Dev = meetDev,
	Minigame = function(prompt)
		local world = prompt:GetAttribute("World")
		if type(world) == "number" then
			Interactions.PlayTerminal(world)
		end
	end,
	Arcade = function(_prompt)
		App.Open("Arcade")
	end,
	Shop = function(_prompt)
		App.Open("Shop")
	end,
	Daily = function(_prompt)
		App.Open("Missions")
	end,
}

function Interactions.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local action = prompt:GetAttribute("Action")
		if type(action) ~= "string" then
			return
		end
		local handler = HANDLERS[action]
		if handler then
			handler(prompt)
		end
	end)
end

return Interactions
