--!strict
--[[
	ShopService : cosmétiques (traînées, effets de mort) achetés avec des Bits, et avatar.
	- Achat / équipement validés côté serveur (prix, possession, source VIP/quotidien)
	- Traînée posée sur le personnage (visible par tous)
	- Passes activables (Bottes anti-gravité, Puce de vitesse) : appliqués au Humanoid ;
	  activer un avantage pendant une ascension la marque « assistée » (hors classement des temps)
	- Bouclier (produit Robux) : attribut Shielded sur le joueur, lu par les pièges côté client
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Cosmetics = require(Shared.Config.Cosmetics)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)

local ShopService = {}

local TOGGLES = { "LowGravity", "SpeedChip" }

local function owns(session: Session.Session, id: string): boolean
	local def = Cosmetics.ById[id]
	if not def then
		return false
	end
	if def.Source == "VIP" then
		return session.Passes.VIP == true
	end
	return def.Price == 0 and def.Source == nil or table.find(session.Data.Cosmetics.Owned, id) ~= nil
end

local function colorSequence(def: Cosmetics.CosmeticDef): ColorSequence
	local colors = def.Colors
	if #colors == 0 then
		return ColorSequence.new(Color3.new(1, 1, 1))
	elseif #colors == 1 then
		return ColorSequence.new(Color3.fromHex(colors[1]))
	end
	local points = {}
	for index, hex in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), Color3.fromHex(hex)))
	end
	return ColorSequence.new(points)
end

-- Pose (ou retire) la traînée équipée sur le personnage.
local function applyTrail(session: Session.Session)
	local character = session.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local old = root:FindFirstChild("AngaTrail")
	if old then
		old:Destroy()
	end
	local def = Cosmetics.ById[session.Data.Cosmetics.Trail]
	if not def or def.Kind ~= "Trail" or #def.Colors == 0 or not owns(session, def.Id) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "AngaTrail"
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.8, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.8, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.45
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Color = colorSequence(def)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail:SetAttribute("Rainbow", def.Rainbow == true)
	trail.Parent = folder
	top.Parent = root
	bottom.Parent = root
	folder.Parent = root
	-- Les attachements vivent sur la pièce ; on les range avec la traînée pour le nettoyage.
	folder.Destroying:Connect(function()
		top:Destroy()
		bottom:Destroy()
	end)
end

-- Applique les passes activables au Humanoid.
function ShopService.ApplyToggles(session: Session.Session)
	local character = session.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local toggles = session.Data.Toggles
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = if toggles.LowGravity and session.Passes.LowGravity
		then GameConfig.LowGravityJumpHeight
		else 7.2
	humanoid.WalkSpeed = if toggles.SpeedChip and session.Passes.SpeedChip then GameConfig.SpeedChipWalkSpeed else 16
end

-- Bouclier : invincible pendant `seconds` (produit Robux).
function ShopService.GrantShield(session: Session.Session, seconds: number)
	session.ShieldUntil = math.max(session.ShieldUntil, os.time()) + seconds
	session.Player:SetAttribute("Shielded", true)
	-- Invincible = course assistée (pas de record au classement des temps).
	if session.Data.RunStarted then
		session.Data.RunAssisted = true
	end
	Wallet.Fx(session, "Shield", { Until = session.ShieldUntil })
	GameEvents.StateChanged:Fire(session.Player)
	-- Fin du bouclier : on revérifie jusqu'à l'échéance réelle (plusieurs achats se cumulent).
	local function check()
		if not session.Player.Parent then
			return
		end
		local left = session.ShieldUntil - os.time()
		if left > 0 then
			task.delay(left + 0.5, check)
			return
		end
		if session.Player:GetAttribute("Shielded") then
			session.Player:SetAttribute("Shielded", false)
			GameEvents.StateChanged:Fire(session.Player)
		end
	end
	task.delay(seconds + 0.5, check)
end

-- Donne un cosmétique (récompense quotidienne…).
function ShopService.Grant(session: Session.Session, id: string)
	if Cosmetics.ById[id] and not table.find(session.Data.Cosmetics.Owned, id) then
		table.insert(session.Data.Cosmetics.Owned, id)
		GameEvents.StateChanged:Fire(session.Player)
	end
end

local function onBuy(session: Session.Session, id: string)
	local def = Cosmetics.ById[id]
	if not def or def.Source ~= nil or owns(session, id) then
		return
	end
	if not Wallet.Spend(session, def.Price, "Cosmetic", id) then
		Wallet.Notify(session, "Error", "Pas assez de Bits… Ramasse les orbes dans la tour !")
		return
	end
	table.insert(session.Data.Cosmetics.Owned, id)
	Wallet.Fx(session, "Bought", { Id = id })
	-- Équipe directement ce qu'on vient d'acheter.
	if def.Kind == "Trail" then
		session.Data.Cosmetics.Trail = id
		applyTrail(session)
	else
		session.Data.Cosmetics.DeathFx = id
	end
	GameEvents.StateChanged:Fire(session.Player)
end

local function onEquip(session: Session.Session, id: string)
	local def = Cosmetics.ById[id]
	if not def or not owns(session, id) then
		return
	end
	if def.Kind == "Trail" then
		session.Data.Cosmetics.Trail = id
		applyTrail(session)
	else
		session.Data.Cosmetics.DeathFx = id
	end
	GameEvents.StateChanged:Fire(session.Player)
end

local function onToggle(session: Session.Session, key: string, on: boolean)
	if not session.Passes[key] then
		return
	end
	local toggles = session.Data.Toggles :: any
	toggles[key] = on
	if on and session.Data.RunStarted then
		session.Data.RunAssisted = true
	end
	ShopService.ApplyToggles(session)
	GameEvents.StateChanged:Fire(session.Player)
end

function ShopService.Start()
	Session.Added:Connect(function(session: Session.Session)
		local function onCharacter(character: Model)
			character:WaitForChild("Humanoid", 10)
			character:WaitForChild("HumanoidRootPart", 10)
			if Session.Get(session.Player) == session then
				ShopService.ApplyToggles(session)
				applyTrail(session)
			end
		end
		session.Trove:Connect(session.Player.CharacterAdded, onCharacter)
		if session.Player.Character then
			task.spawn(onCharacter, session.Player.Character)
		end
	end)
	-- Les passes sont vérifiés après l'arrivée : on réapplique (traînée VIP, avantages).
	GameEvents.PassesLoaded:Connect(function(player: Player)
		local session = Session.Get(player)
		if session then
			ShopService.ApplyToggles(session)
			applyTrail(session)
		end
	end)
	RemoteGuard.On("BuyCosmetic", { Args = { RemoteGuard.String(32) } }, onBuy)
	RemoteGuard.On("EquipCosmetic", { Args = { RemoteGuard.String(32) } }, onEquip)
	RemoteGuard.On("ToggleAssist", { Args = { RemoteGuard.OneOf(TOGGLES), RemoteGuard.Bool() } }, onToggle)
end

return ShopService
