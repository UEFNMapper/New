--!strict
--[[
	JumpAssist : sensations de saut plus tolérantes (idée D de l'audit v3), côté client.
	- Coyote time : saut encore possible ~0,12 s après avoir quitté un bord en marchant.
	- Saut mémorisé : un appui ~0,12 s avant d'atterrir déclenche le saut à l'atterrissage.
	La logique de temps est pure (Shared/Util/JumpTiming, testée) ; ici on la branche sur :
	- UserInputService.JumpRequest (clavier, manette ET bouton tactile) ;
	- Humanoid.StateChanged (Jumping / Freefall / Landed…) et Humanoid.FloorMaterial.
	Le saut passe par Humanoid:ChangeState(Jumping) : il utilise le JumpHeight réglé par le
	serveur (bottes anti-gravité comprises). Jamais de double saut (voir JumpTiming).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JumpTiming = require(Shared.Util.JumpTiming)

local JumpAssist = {}

local player = Players.LocalPlayer
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local state = JumpTiming.new()
local connections: { RBXScriptConnection } = {}

local GROUNDED: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true,
}

-- Le personnage peut-il sauter maintenant (vivant, pas assis, saut non désactivé) ?
local function canJump(hum: Humanoid): boolean
	if hum.Health <= 0 or hum.Sit or hum.PlatformStand then
		return false
	end
	if not hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
		return false
	end
	local power = if hum.UseJumpPower then hum.JumpPower else hum.JumpHeight
	if power <= 0 then
		return false
	end
	local current = hum:GetState()
	return current ~= Enum.HumanoidStateType.Dead
		and current ~= Enum.HumanoidStateType.Climbing
		and current ~= Enum.HumanoidStateType.Swimming
end

local function jump(hum: Humanoid)
	if canJump(hum) then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

local function landed(hum: Humanoid)
	if JumpTiming.OnLanded(state, os.clock()) then
		-- Laisse le moteur finir l'atterrissage (sinon l'état Landed peut écraser le saut).
		task.defer(function()
			-- Bouton maintenu : le moteur a peut-être déjà sauté tout seul (pas de double impulsion).
			if hum.FloorMaterial ~= Enum.Material.Air and hum:GetState() ~= Enum.HumanoidStateType.Jumping then
				jump(hum)
			end
		end)
	end
end

local function onStateChanged(hum: Humanoid, _old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	local now = os.clock()
	if new == Enum.HumanoidStateType.Jumping then
		JumpTiming.OnJumped(state, now)
	elseif new == Enum.HumanoidStateType.Freefall then
		JumpTiming.OnAirborne(state, now)
	elseif GROUNDED[new] then
		landed(hum)
	end
end

local function unbind()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	humanoid = nil
	root = nil
end

local function bind(character: Model)
	unbind()
	local hum = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not (hum and hum:IsA("Humanoid") and rootPart and rootPart:IsA("BasePart")) then
		return
	end
	if player.Character ~= character then
		return -- un autre personnage est déjà apparu entre-temps
	end
	humanoid = hum
	root = rootPart
	state = JumpTiming.new()
	table.insert(
		connections,
		hum.StateChanged:Connect(function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			onStateChanged(hum, old, new)
		end)
	)
	-- Filet de sécurité : le sol détecté par le Humanoid (au cas où l'état arrive en retard).
	table.insert(
		connections,
		hum:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
			if hum.FloorMaterial ~= Enum.Material.Air and hum:GetState() ~= Enum.HumanoidStateType.Jumping then
				landed(hum)
			end
		end)
	)
	table.insert(
		connections,
		hum.Died:Connect(function()
			state = JumpTiming.new()
		end)
	)
end

local function onJumpRequest()
	local hum, rootPart = humanoid, root
	if not hum or not rootPart or hum.Parent == nil then
		return
	end
	-- Le sol réel prime : le moteur de Roblox gère lui-même le saut depuis le sol.
	if hum.FloorMaterial ~= Enum.Material.Air then
		return
	end
	local action = JumpTiming.OnRequest(state, os.clock(), rootPart.AssemblyLinearVelocity.Y)
	if action == "Coyote" then
		jump(hum)
	end
end

function JumpAssist.Start()
	UserInputService.JumpRequest:Connect(onJumpRequest)
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(bind, character)
	end)
	player.CharacterRemoving:Connect(function(character: Model)
		if humanoid and humanoid.Parent == character then
			unbind()
		end
	end)
	if player.Character then
		task.spawn(bind, player.Character)
	end
end

return JumpAssist
