--!strict
--[[
	Feedback : le « game feel ». Transforme chaque événement serveur (Fx, Notify) en
	retour visuel + sonore (toasts, bannières, particules, voix d'Anga), et règle
	l'ambiance du monde où l'on se trouve (musique, teinte de l'éclairage).

	Monde nettoyé : bannière -> carte de médaille -> en-tête du monde suivant passent UN PAR UN
	(file des moments, Moments.Queue). Arrivée dans le monde suivant : la carte de médaille se
	ferme vite. Monde 7 : pas de carte (la victoire arrive quelques secondes après) ; la médaille
	est gardée et montrée dans le rapport de victoire.
	Les répliques de fin de monde EXPIRENT (Dialogue.Say, 4e paramètre) : elles ne retardent
	jamais l'intro du monde suivant.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tower = require(Shared.Config.Tower)
local Cosmetics = require(Shared.Config.Cosmetics)
local Branding = require(Shared.Config.Branding)
local NumberFormat = require(Shared.Util.NumberFormat)

local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local Motion = require(script.Parent.Parent.UI.Motion)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)
local Moments = require(script.Parent.Parent.UI.Screens.Moments)
local Dialogue = require(script.Parent.Parent.UI.Screens.Dialogue)
local MedalCard = require(script.Parent.Parent.UI.Screens.MedalCard)

local Feedback = {}

local player = Players.LocalPlayer
local currentWorld = -1
local APP_NAME = Branding.PartnerApp.Name
-- Carte de médaille encore affichée quand on entre dans le monde suivant : visible au plus
-- MEDAL_MIN_SHOWN s au total, puis l'en-tête du nouveau monde prend la place.
local MEDAL_MIN_SHOWN = 2
-- Répliques de fin de monde : jetées si elles n'ont pas commencé après ce délai (s).
local CLEARED_LINE_EXPIRES = 8
-- Médaille du monde 7, montrée dans le rapport de victoire.
local finalMedal: any = nil

-- Léger tremblement de caméra (respecte "Réduire les animations").
local shakeToken = 0
function Feedback.Shake(strength: number, duration: number)
	if Motion.IsReduced() then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	shakeToken += 1
	local token = shakeToken
	local start = os.clock()
	task.spawn(function()
		while token == shakeToken and os.clock() - start < duration do
			local fade = 1 - (os.clock() - start) / duration
			humanoid.CameraOffset =
				Vector3.new((math.random() - 0.5) * strength * fade, (math.random() - 0.5) * strength * fade, 0)
			task.wait()
		end
		if token == shakeToken then
			humanoid.CameraOffset = Vector3.zero
		end
	end)
end

-- Explosion de particules à un endroit du monde (effet de mort, orbe ramassée).
local function burst(position: Vector3, colors: { string }, count: number, speed: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.LightEmission = 0.8
	emitter.Drag = 3
	local points = {}
	for index, hex in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / math.max(#colors - 1, 1), Color3.fromHex(hex)))
	end
	if #points == 1 then
		table.insert(points, ColorSequenceKeypoint.new(1, points[1].Value))
	end
	if #points > 0 then
		emitter.Color = ColorSequence.new(points)
	end
	emitter.Parent = anchor
	emitter:Emit(if Motion.IsReduced() then math.floor(count / 3) else count)
	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

-- Ambiance du monde (musique + teinte) selon l'étape du joueur.
local function applyWorld(world: number)
	if world == currentWorld then
		return
	end
	currentWorld = world
	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if world <= 0 then
		Audio.PlayZone("Hub")
		if correction then
			Motion.Tween(correction, { TintColor = Color3.fromRGB(250, 250, 255) }, 1.2, Enum.EasingStyle.Sine)
		end
		return
	end
	Audio.PlayZone(world)
	if correction then
		Motion.Tween(correction, { TintColor = Color3.fromHex(Tower.Worlds[world].Tint) }, 1.2, Enum.EasingStyle.Sine)
	end
end

local function onFx(kind: string, payload: any)
	if kind == "Checkpoint" then
		Audio.Play("Upgrade", 1 + (payload.Stage % 5) * 0.04)
		if payload.NewWorld and payload.World > 0 then
			Audio.Play("Unlock")
			Moments.Expedite("Medal", MEDAL_MIN_SHOWN)
			Moments.WorldBanner(payload.World)
			local def = Tower.Worlds[payload.World]
			if def then
				task.delay(1.5, function()
					Dialogue.Say(def.Intro, 6)
				end)
			end
		else
			-- Checkpoint = « point de restauration », une fonction de l'app AngAInOne (l'icône du
			-- toast « Success » est déjà la coche ✓).
			Toasts.Show("Success", `{APP_NAME} · Point de restauration créé · Étape {payload.Stage}`)
		end
	elseif kind == "RunStart" then
		finalMedal = nil
		Audio.Play("PowerOn")
		Moments.WorldBanner(1)
		task.delay(1.5, function()
			Dialogue.Say(Tower.Worlds[1].Intro, 6)
		end)
	elseif kind == "Coin" then
		Audio.Play("Collect", if payload.Mega then 0.85 else 1 + math.random() * 0.15)
		if typeof(payload.Position) == "Vector3" then
			burst(
				payload.Position,
				{ "F6E05E", "FBD38D" },
				if payload.Mega then 24 else 10,
				if payload.Mega then 14 else 8
			)
		end
		if payload.Mega then
			Toasts.Show("Reward", `Méga-Bit ! +{NumberFormat.Compact(payload.Bits or 0)} Bits · Ventilo bonus`)
		end
	elseif kind == "UsbKey" then
		Audio.Play("Unlock")
		Audio.Play("Collect", 0.8)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			burst(root.Position, { "F6E05E", "D4A64A", "FFFFFF" }, 30, 14)
		end
		local found, total = payload.Found or 0, payload.Total or 0
		Toasts.Show(
			"Milestone",
			`🔑 Clé USB dorée {found}/{total} · +{NumberFormat.Compact(payload.Bits or 0)} Bits`
		)
		if found >= total and total > 0 then
			task.delay(1.2, function()
				Toasts.Show("Success", "Toutes les clés USB ! Traînée USB débloquée dans la Boutique 🎉")
				Dialogue.Say("Toutes les clés USB ! Tu es un vrai Anti-Lag Légendaire !", 5)
			end)
		elseif found == 1 then
			task.delay(1, function()
				Dialogue.Say("Une clé USB dorée ! Il y en a 3 cachées dans chaque monde.", 5)
			end)
		end
	elseif kind == "Death" then
		local isMe = payload.UserId == player.UserId
		local def = Cosmetics.ById[payload.Fx] or Cosmetics.ById[Cosmetics.DefaultDeathFx]
		if typeof(payload.Position) == "Vector3" and def then
			burst(payload.Position, def.Colors, if isMe then 40 else 20, 16)
		end
		if isMe then
			Audio.Play("Zap", 0.8)
			Feedback.Shake(0.4, 0.3)
			Moments.DeathFlash()
		end
	elseif kind == "WorldCleared" then
		Audio.Play("Achievement")
		Audio.Duck(3)
		Moments.WorldCleared(payload.World, payload.Bits)
		Feedback.Shake(0.3, 0.4)
		-- Anga : le symptôme réparé (Tower.Cleaned), puis la suite. LAGZ râle ensuite (Story).
		local def = Tower.Worlds[payload.World]
		task.delay(2, function()
			if def then
				Dialogue.Say(def.Cleaned, 4, "Anga", CLEARED_LINE_EXPIRES)
			end
			Dialogue.Say(
				if payload.World < Tower.WORLD_COUNT
					then "Le portail est ouvert. Monte vite au monde suivant !"
					else "Touche la puce tout en haut : le live va pouvoir commencer !",
				4,
				"Anga",
				CLEARED_LINE_EXPIRES
			)
			-- Le conseil « vraie vie » du monde, par l'assistant de l'app (Tower.Tip) : une phrase utile
			-- pour le vrai PC du joueur (voir le panneau de la salle du terminal pour le raccourci).
			if def and def.Tip ~= "" then
				Dialogue.Say(`💡 {def.Tip}`, 7, "AIO", CLEARED_LINE_EXPIRES + 10)
			end
		end)
		-- Médaille du monde : carte « Rapport du monde » après la bannière (file des moments).
		-- Monde 7 : la victoire suit de près ; la médaille ira dans le rapport de victoire.
		if type(payload.Medal) == "string" then
			if payload.World >= Tower.WORLD_COUNT then
				finalMedal = payload
			else
				Moments.Queue("Medal", MedalCard.HOLD, function(done: () -> ()): (() -> ())?
					if payload.NewBest or payload.Medal == "Gold" then
						Audio.Play("Unlock", 1.15)
					else
						Audio.Play("Toast")
					end
					MedalCard.Show(payload, done)
					return MedalCard.Dismiss
				end)
			end
		end
	elseif kind == "Victory" then
		Audio.Play("Achievement")
		Audio.Duck(6)
		-- Moments.Victory vide la file des moments (carte de médaille comprise).
		local medal = finalMedal
		finalMedal = nil
		Moments.Victory(payload, medal)
	elseif kind == "Reward" then
		Audio.Play("Toast")
		Toasts.Show("Reward", `+{NumberFormat.Compact(payload.Bits or 0)} Bits`)
	elseif kind == "Daily" then
		Audio.Play("Achievement")
		Toasts.Show("Reward", `Jour {payload.Day} : {payload.Label} !`)
	elseif kind == "MissionReady" then
		Audio.Play("Toast", 1.2)
		Toasts.Show("Milestone", "Mission terminée ! Récupère ta récompense dans Missions.")
	elseif kind == "Bought" then
		Audio.Play("Unlock", 1.2)
		local def = Cosmetics.ById[payload.Id]
		Toasts.Show("Success", `{if def then def.Name else "Objet"} débloqué et équipé !`)
	elseif kind == "Shield" then
		Audio.Play("PowerOn", 1.3)
		Toasts.Show("Boost", "Bouclier activé : tu es invincible !")
	end
end

-- Confettis aux couleurs de l'app autour du joueur (Stream Deck, enquêtes réussies…).
function Feedback.Confetti(position: Vector3?, count: number?)
	local at = position
	if not at then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		at = if root and root:IsA("BasePart") then root.Position else nil
	end
	if at then
		burst(at + Vector3.new(0, 2, 0), { "9B2FD4", "F6C453", "4FD1C5", "F0565B", "FFFFFF" }, count or 60, 22)
	end
end

function Feedback.Start()
	Net.On("Fx", onFx)
	Net.On("Notify", function(kind: string, text: string)
		Audio.Play(if kind == "Error" then "Error" else "Toast")
		Toasts.Show(kind, text)
	end)
	Store.Changed:Connect(function(state: any)
		applyWorld(if state.AtLobby then 0 else Tower.RunWorld(state.Data.Stage, state.Data.Cleared))
	end)
end

return Feedback
