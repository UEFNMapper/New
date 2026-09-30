--!strict
--[[
	Motion : animations d'UI cohérentes (TweenService).
	- Durées et easings centralisés (Theme.Motion)
	- Respect de l'option "Réduire les animations" (durées quasi nulles)
	- Press (0,95) / hover (1,04) sur les boutons, compteurs qui défilent
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)

local Motion = {}

local reduced = false

function Motion.SetReduced(value: boolean)
	reduced = value
end

function Motion.IsReduced(): boolean
	return reduced
end

function Motion.Tween(
	instance: Instance,
	props: { [string]: any },
	duration: number?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local time = if reduced then 0.01 else (duration or Theme.Motion.Base)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Retourne (et crée si besoin) le UIScale d'un objet, utilisé pour press/hover/pop.
function Motion.ScaleOf(object: GuiObject): UIScale
	local existing = object:FindFirstChild("MotionScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "MotionScale"
	scale.Parent = object
	return scale
end

-- Branche les effets hover/press sur un bouton. Renvoie une fonction de nettoyage.
function Motion.Pressable(button: GuiButton, onPress: (() -> ())?): () -> ()
	local scale = Motion.ScaleOf(button)
	local hovering = false
	local connections = {
		button.MouseEnter:Connect(function()
			if UserInputService.MouseEnabled then
				hovering = true
				Motion.Tween(scale, { Scale = Theme.Motion.HoverScale }, Theme.Motion.Fast)
			end
		end),
		button.MouseLeave:Connect(function()
			hovering = false
			Motion.Tween(scale, { Scale = 1 }, Theme.Motion.Fast)
		end),
		button.MouseButton1Down:Connect(function()
			Motion.Tween(scale, { Scale = Theme.Motion.PressScale }, 0.08)
			if onPress then
				onPress()
			end
		end),
		button.MouseButton1Up:Connect(function()
			Motion.Tween(
				scale,
				{ Scale = if hovering then Theme.Motion.HoverScale else 1 },
				0.25,
				Enum.EasingStyle.Back
			)
		end),
	}
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

-- "Pop" : petit rebond d'attention (gain, badge, nouveau contenu).
function Motion.Pop(object: GuiObject, strength: number?)
	if reduced then
		return
	end
	local scale = Motion.ScaleOf(object)
	scale.Scale = 1 + (strength or 0.12)
	Motion.Tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
end

-- Compteur qui défile de `from` à `to` (formatage fourni), annulé si relancé.
local counters: { [TextLabel]: number } = {}
function Motion.CountTo(label: TextLabel, from: number, to: number, format: (number) -> string, duration: number?)
	local token = (counters[label] or 0) + 1
	counters[label] = token
	if reduced or from == to then
		label.Text = format(to)
		return
	end
	local total = duration or 0.6
	local start = os.clock()
	task.spawn(function()
		while counters[label] == token do
			local t = math.min((os.clock() - start) / total, 1)
			local eased = 1 - (1 - t) ^ 3
			label.Text = format(from + (to - from) * eased)
			if t >= 1 then
				break
			end
			task.wait()
		end
	end)
end

return Motion
