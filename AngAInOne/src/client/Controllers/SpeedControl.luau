--!strict
--[[
	SpeedControl : la vitesse de marche du joueur local, calculée à partir d'une base et de
	modificateurs nommés. Le serveur fixe la base (16, ou 19,5 avec la puce de vitesse :
	ShopService.ApplyToggles) ; le client y applique ses effets locaux :
	- facteurs (RAM saturée au monde 2 : × 0,55 au pire),
	- bonus additifs (interrupteur « RGB = +10 FPS » : +10 pendant 10 s).
	Vitesse = base × produit des facteurs + somme des bonus.
	Toute valeur de WalkSpeed que nous n'avons pas écrite nous-mêmes est prise comme nouvelle base
	(le serveur l'a changée) : les effets locaux sont alors réappliqués par-dessus.
]]

local Players = game:GetService("Players")

local SpeedControl = {}

local DEFAULT_BASE = 16

local player = Players.LocalPlayer
local humanoid: Humanoid? = nil
local base = DEFAULT_BASE
local written = -1
local factors: { [string]: number } = {}
local bonuses: { [string]: number } = {}

local function apply()
	local hum = humanoid
	if not hum or not hum.Parent then
		return
	end
	local speed = base
	for _, factor in factors do
		speed *= factor
	end
	for _, bonus in bonuses do
		speed += bonus
	end
	speed = math.max(speed, 2)
	if math.abs(hum.WalkSpeed - speed) > 0.01 then
		written = speed
		hum.WalkSpeed = speed
	end
end

local function watch(character: Model)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	humanoid = hum
	base = hum.WalkSpeed
	written = -1
	hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if humanoid ~= hum then
			return
		end
		local value = hum.WalkSpeed
		if math.abs(value - written) > 0.01 then
			-- Valeur venue d'ailleurs (le serveur) : nouvelle base.
			base = value
			apply()
		end
	end)
	apply()
end

-- Facteur multiplicatif nommé (nil ou 1 = retiré).
function SpeedControl.SetFactor(key: string, factor: number?)
	if factor == nil or math.abs(factor - 1) < 0.001 then
		factors[key] = nil
	else
		factors[key] = math.clamp(factor, 0.1, 3)
	end
	apply()
end

-- Bonus additif nommé (nil ou 0 = retiré).
function SpeedControl.SetBonus(key: string, bonus: number?)
	if bonus == nil or bonus == 0 then
		bonuses[key] = nil
	else
		bonuses[key] = bonus
	end
	apply()
end

function SpeedControl.Base(): number
	return base
end

-- Vitesse actuelle calculée (pour les tests et le HUD).
function SpeedControl.Current(): number
	local speed = base
	for _, factor in factors do
		speed *= factor
	end
	for _, bonus in bonuses do
		speed += bonus
	end
	return math.max(speed, 2)
end

function SpeedControl.Start()
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return SpeedControl
