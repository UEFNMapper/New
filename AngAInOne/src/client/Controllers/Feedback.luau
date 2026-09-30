--!strict
--[[
	Feedback : "game feel". Transforme chaque événement serveur (Fx, Notify, Offline)
	en retour visuel + sonore : particules de Bits aspirées vers le compteur,
	texte flottant, léger screen shake, toasts, moments forts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Nanobots = require(Shared.Config.Nanobots)
local NumberFormat = require(Shared.Util.NumberFormat)

local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)
local Create = require(script.Parent.Parent.UI.Create)
local Style = require(script.Parent.Parent.UI.Style)
local Motion = require(script.Parent.Parent.UI.Motion)
local App = require(script.Parent.Parent.UI.App)
local Icon = require(script.Parent.Parent.UI.Components.Icon)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)
local Moments = require(script.Parent.Parent.UI.Screens.Moments)
local HUD = require(script.Parent.Parent.UI.Screens.HUD)
local Dialogue = require(script.Parent.Parent.UI.Screens.Dialogue)

local New = Create.New

local Feedback = {}

-- Branché par le contrôleur du monde (vague d'allumage, flash de module…).
Feedback.OnWorldFx = nil :: ((kind: string, payload: any) -> ())?

local shakeToken = 0

-- Ce que dit Anga en découvrant chaque étage.
local ZONE_LINES: { [number]: string } = {
	[2] = "Memory Lanes ! Ici, tout va à la vitesse de la lumière. Et regarde : un terminal à capsules de Nanobots !",
	[3] = "Le Data Vault… Chaque cellule garde un secret. Essaie les téléchargements : lance-en un et reviens plus tard !",
	[4] = "Brrr, la Cryo Tower ! Surveille ta jauge de chaleur : si ton PC chauffe, améliore les radiateurs.",
	[5] = "The Core, le cœur du réacteur. La station d'overclock t'attend : arrête l'aiguille dans la zone dorée !",
	[6] = "Render Canyon ! C'est ici que naissent les pixels. Et la console BIOS permet de faire un Reboot…",
	[7] = "Le Neural Nexus… Ton PC commence à rêver. Construis la Singularité, on y est presque !",
}

-- Léger tremblement de caméra (respecte "Réduire les animations").
function Feedback.Shake(strength: number, duration: number)
	if Motion.IsReduced() then
		return
	end
	local character = Players.LocalPlayer.Character
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

-- Particules de Bits : partent du centre de l'écran et filent vers le compteur.
local function collectBurst(amount: number)
	local layer = App.Layers.Moments
	local target = HUD.BitsPill
	if not layer or not target then
		return
	end
	local root = App.Root
	local count = math.clamp(math.floor(math.log10(amount + 1) * 2), 4, 12)
	-- Coordonnées écran -> pixels de conception du calque (le Root est mis à l'échelle par UIScale).
	local rootScale = root:FindFirstChildOfClass("UIScale")
	local s = if rootScale then rootScale.Scale else 1
	local targetPos = (target.AbsolutePosition + target.AbsoluteSize / 2 - root.AbsolutePosition) / s
	local origin = root.AbsoluteSize / 2 / s + Vector2.new(0, 60)
	for i = 1, count do
		local icon = Icon.new("Bits", 22, nil)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		local spread = Vector2.new(math.random(-90, 90), math.random(-50, 50))
		icon.Position = UDim2.fromOffset(origin.X, origin.Y)
		icon.Parent = layer
		local mid = origin + spread
		task.delay(i * 0.03, function()
			Motion.Tween(icon, { Position = UDim2.fromOffset(mid.X, mid.Y) }, 0.22, Enum.EasingStyle.Quad).Completed
				:Once(function()
					Motion.Tween(
						icon,
						{ Position = UDim2.fromOffset(targetPos.X, targetPos.Y), Size = UDim2.fromOffset(12, 12) },
						0.42,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.In
					).Completed
						:Once(function()
							icon:Destroy()
							if i == count then
								Motion.Pop(target, 0.08)
							end
						end)
				end)
		end)
	end
end

-- Texte flottant dans le monde (ex. "+1,2K" au-dessus d'un virus zappé).
local function floatingText(position: Vector3, text: string, colorName: string)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	local billboard: BillboardGui = New("BillboardGui", {
		Size = UDim2.fromOffset(220, 50),
		StudsOffset = Vector3.new(0, 2, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = anchor,
	})
	local label: TextLabel = New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = Style.Fonts.Heavy,
		TextSize = 28,
		TextColor3 = Style.Color(colorName),
		TextStrokeTransparency = 0.4,
		Parent = billboard,
	})
	Motion.Tween(billboard, { StudsOffset = Vector3.new(0, 7, 0) }, 1.1, Enum.EasingStyle.Quad)
	Motion.Tween(label, { TextTransparency = 1, TextStrokeTransparency = 1 }, 1.1, Enum.EasingStyle.Quad)
	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

local function onFx(kind: string, payload: any)
	if kind == "Collect" then
		Audio.Play("Collect", 1 + math.random() * 0.1)
		collectBurst(payload.Amount)
	elseif kind == "Upgrade" then
		Audio.Play("Upgrade", 1 + math.min(payload.Count, 10) * 0.02)
	elseif kind == "Capacity" then
		Audio.Play("Upgrade", 0.9)
	elseif kind == "PowerOn" then
		Audio.Play("PowerOn")
		Audio.Duck(2)
		Moments.ShowPowerOn(false)
		Moments.BootFlash()
		Feedback.Shake(0.35, 0.6)
		task.delay(1.2, function()
			Dialogue.Say(
				"Wouhou, ton PC est VIVANT ! Bienvenue chez toi. On va en faire la machine la plus puissante de l'univers.",
				5
			)
		end)
	elseif kind == "ZoneUnlocked" then
		Audio.Play("Unlock")
		Audio.Duck(3)
		Moments.ZoneUnlocked(payload.Zone)
		Feedback.Shake(0.3, 0.5)
		local line = ZONE_LINES[payload.Zone]
		if line then
			task.delay(2, function()
				Dialogue.Say(line, 6)
			end)
		end
	elseif kind == "Zap" then
		Audio.Play("Zap", 0.95 + math.random() * 0.15)
		Feedback.Shake(0.2, 0.15)
		floatingText(payload.Position, `+{NumberFormat.Compact(payload.Bits)}`, "CurrencyBits")
		if payload.Chips > 0 then
			Toasts.Show("Reward", `Virus zappé : +{payload.Chips} Chips !`)
		end
	elseif kind == "Capsule" then
		Audio.Play("Achievement", 1.1)
		Moments.Capsule(payload.NanobotId)
	elseif kind == "Fuse" then
		Audio.Play("Achievement")
		local def = Nanobots.ById[payload.NanobotId]
		Toasts.Show("Milestone", `Fusion réussie : {if def then def.Name else "Nanobot"} doré !`)
		Dialogue.Say("Un Nanobot DORÉ ! Il est 50 % plus puissant. Bien joué !", 4)
	elseif kind == "Reward" then
		Audio.Play("Toast")
		local parts = {}
		if payload.Bits then
			table.insert(parts, `+{NumberFormat.Compact(payload.Bits)} Bits`)
		end
		if payload.Chips then
			table.insert(parts, `+{payload.Chips} Chips`)
		end
		Toasts.Show("Reward", table.concat(parts, "  ·  "))
	elseif kind == "Daily" then
		Audio.Play("Achievement")
		Toasts.Show("Reward", `Jour {payload.Day} : {payload.Label} !`)
	elseif kind == "Fragment" then
		Audio.Play("Unlock", 1.3)
		local data = Store.Data()
		local found = 0
		if data then
			for _, value in data.Fragments do
				if value then
					found += 1
				end
			end
		end
		Toasts.Show("Fragment", `Fragment de données trouvé (+1 % de Bits) · {found + 1}/{#Zones * 3}`)
	elseif kind == "Reboot" then
		Audio.Play("Whoosh")
		Audio.Duck(3)
		Moments.Reboot(payload.Firmware, payload.Generation)
		task.delay(3.5, function()
			Dialogue.Say(
				`Génération {payload.Generation} ! Tout recommence… mais avec +{payload.Firmware} Firmware, ça va aller BEAUCOUP plus vite.`,
				6
			)
		end)
	elseif kind == "SingularityPhase" then
		Audio.Play("Unlock")
		Toasts.Show("Milestone", `Singularité : phase {payload.Phase} terminée !`)
	elseif kind == "Singularity" then
		Audio.Play("Achievement")
		Audio.Duck(8)
		task.spawn(Moments.Singularity, payload.Count)
	end
	if Feedback.OnWorldFx then
		Feedback.OnWorldFx(kind, payload)
	end
end

function Feedback.Start()
	Net.On("Fx", onFx)
	Net.On("Notify", function(kind: string, text: string)
		if kind == "Error" then
			Audio.Play("Error")
		else
			Audio.Play("Toast")
		end
		Toasts.Show(kind, text)
	end)
	Net.On("Offline", function(bits: number, seconds: number)
		Audio.Play("Collect")
		Moments.Offline(bits, seconds)
	end)
end

return Feedback
