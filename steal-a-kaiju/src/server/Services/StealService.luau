--!nonstrict
-- Le vol : attraper un kaiju chez un autre joueur, le ramener sur son île.
-- Plus il est gros, plus on est lent ; les Titans et Colosses se portent à deux.
-- Le « Bonker » (marteau gonflable) fait lâcher prise aux voleurs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Growth = require(Shared.Config.Growth)
local Economy = require(Shared.Config.Economy)
local Layout = require(Shared.Config.Layout)
local Theme = require(Shared.Config.Theme)
local Calc = require(Shared.Logic.Calc)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local StealService = {}

type Carry = {
	Uid: string,
	Victim: Player,
	Lead: Player,
	Helper: Player?,
	Stage: number,
	Started: number,
	Lifting: boolean,
	LiftUntil: number,
	LastPos: Vector3?,
	LastCheck: number,
	Strikes: number,
}

local carries: { [string]: Carry } = {} -- Uid -> vol en cours
local carrying: { [Player]: string } = {} -- joueur -> Uid porté (chef ou aide)
local bonkCooldown: { [Player]: number } = {}
local stealCooldown: { [Player]: number } = {}

local BASE_SPEED = 22

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function StealService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function StealService.RefreshSpeed(player: Player)
	local humanoid = humanoidOf(player)
	local data = DataService.Get(player)
	if not humanoid or not data then
		return
	end
	local speed = BASE_SPEED + data.Upgrades.Sneakers * Economy.UpgradesById.Sneakers.PerLevel
	local uid = carrying[player]
	local carry = uid and carries[uid]
	if carry then
		local stage = Growth.Get(carry.Stage)
		local strength = 1 + data.Upgrades.Muscles * Economy.UpgradesById.Muscles.PerLevel
		speed = math.min(speed, BASE_SPEED * stage.CarrySpeed * strength)
		if carry.Lifting then
			speed = 4
		end
	end
	humanoid.WalkSpeed = speed
	player:SetAttribute("Carrying", uid or "")
end

local function setAnchorState(carry: Carry)
	local anchor = Registry.KaijuService.Anchor(carry.Uid)
	if not anchor then
		return
	end
	anchor:SetAttribute("CarriedBy", carry.Lead.UserId)
	anchor:SetAttribute("Helper", if carry.Helper then carry.Helper.UserId else 0)
	anchor:SetAttribute("Lifting", carry.Lifting)
	anchor:SetAttribute("LiftUntil", carry.LiftUntil)
end

-- Termine un vol. reason : Delivered | Dropped | Timeout | Left
local function endCarry(uid: string, reason: string, by: Player?)
	local carry = carries[uid]
	if not carry then
		return
	end
	carries[uid] = nil
	carrying[carry.Lead] = nil
	if carry.Helper then
		carrying[carry.Helper] = nil
	end
	local anchor = Registry.KaijuService.Anchor(uid)
	if anchor then
		anchor:SetAttribute("CarriedBy", 0)
		anchor:SetAttribute("Helper", 0)
		anchor:SetAttribute("Lifting", false)
	end
	for _, p in { carry.Lead, carry.Helper } do
		if p and p.Parent == Players then
			StealService.RefreshSpeed(p)
		end
	end
	if reason ~= "Delivered" then
		Notify.FxAll("KaijuReturned", { Uid = uid, Reason = reason })
		if carry.Victim.Parent == Players then
			if reason == "Dropped" and by == carry.Victim then
				Notify.Toast(carry.Victim, "You saved your kaiju! 💪", "Good")
				Registry.RewardService.Track(carry.Victim, "Saves", 1)
			else
				Notify.Toast(carry.Victim, "Your kaiju came back home!", "Good")
			end
			Notify.Fx(carry.Victim, "AlarmStop", { Uid = uid })
			Registry.KaijuService.RefreshPlayer(carry.Victim)
		end
		if carry.Lead.Parent == Players then
			local msg = if reason == "Timeout" then "Too slow! The kaiju escaped." elseif reason == "HelperLost" then "Your partner let go!" else "You dropped the kaiju!"
			Notify.Toast(carry.Lead, msg, "Bad")
		end
	end
end

local function startCarry(player: Player, uid: string, victim: Player, stage: number): Carry
	local needed = Growth.Get(stage).Carriers
	local carry: Carry = {
		Uid = uid,
		Victim = victim,
		Lead = player,
		Helper = nil,
		Stage = stage,
		Started = os.clock(),
		Lifting = needed > 1,
		LiftUntil = if needed > 1 then Workspace:GetServerTimeNow() + Economy.LiftWaitTime else 0,
		LastPos = nil,
		LastCheck = os.clock(),
		Strikes = 0,
	}
	carries[uid] = carry
	carrying[player] = uid
	setAnchorState(carry)
	StealService.RefreshSpeed(player)
	return carry
end

local function steal(player: Player, payload: any): Router.Result
	local uid = Router.String(payload.Uid)
	local data = DataService.Get(player)
	if not uid or not data then
		return { ok = false }
	end
	if carrying[player] then
		return { ok = false, msg = "Your hands are full!" }
	end
	if (stealCooldown[player] or 0) > os.clock() then
		return { ok = false, msg = "Catch your breath..." }
	end
	local anchor = Registry.KaijuService.Anchor(uid)
	local victim = Registry.KaijuService.OwnerOf(uid)
	if not anchor or not victim then
		return { ok = false, msg = "It's gone!" }
	end
	if victim == player then
		return { ok = false, msg = "That's yours!" }
	end
	if anchor:GetAttribute("Egg") then
		return { ok = false, msg = "Eggs are too fragile to steal!" }
	end
	if (anchor:GetAttribute("CarriedBy") or 0) == -1 then
		return { ok = false, msg = "Someone is already stealing it!" }
	end
	if carries[uid] then
		local carry = carries[uid]
		if carry.Lifting and not carry.Helper then
			return StealService.Help(player, uid)
		end
		return { ok = false, msg = "Someone is already stealing it!" }
	end
	local plot = Registry.PlotService.Get(victim)
	if not plot or Registry.PlotService.IsShielded(plot) then
		return { ok = false, msg = "Their base is shielded!" }
	end
	local root = rootOf(player)
	local stage = anchor:GetAttribute("Stage") or 1
	local reach = 10 + Growth.Get(stage).Scale * 3
	if not root or (root.Position - anchor.Position).Magnitude > reach + 6 then
		return { ok = false, msg = "Get closer!" }
	end
	if not Registry.KaijuService.FreeNest(player) then
		return { ok = false, msg = "Your nests are full!" }
	end
	stealCooldown[player] = os.clock() + Economy.StealCooldown
	local carry = startCarry(player, uid, victim, stage)

	local species = Kaijus.Get(anchor:GetAttribute("Species") or "")
	Notify.Fx(victim, "Alarm", {
		Uid = uid,
		Thief = player.DisplayName,
		Species = if species then species.Name else "kaiju",
	})
	Notify.Fx(player, "Grabbed", { Uid = uid, Lifting = carry.Lifting })
	if carry.Lifting then
		Notify.FeedExcept(player, ("🆘 %s needs a hand lifting a %s! Help them!"):format(player.DisplayName, string.upper(Growth.Get(stage).Name)), "Help", Theme.Colors.Magma)
	end
	return { ok = true, lifting = carry.Lifting }
end

function StealService.Help(player: Player, uid: string): Router.Result
	local carry = carries[uid]
	if not carry or not carry.Lifting or carry.Helper then
		return { ok = false, msg = "No one needs help" }
	end
	if carrying[player] then
		return { ok = false, msg = "Your hands are full!" }
	end
	if player == carry.Victim then
		return { ok = false, msg = "Bonk them instead!" }
	end
	local root, leadRoot = rootOf(player), rootOf(carry.Lead)
	if not root or not leadRoot or (root.Position - leadRoot.Position).Magnitude > Economy.HelperMaxDistance then
		return { ok = false, msg = "Get closer to the thief!" }
	end
	carry.Helper = player
	carry.Lifting = false
	carry.Started = os.clock()
	carrying[player] = uid
	setAnchorState(carry)
	StealService.RefreshSpeed(carry.Lead)
	StealService.RefreshSpeed(player)
	Notify.Fx(carry.Lead, "HelperJoined", { Name = player.DisplayName })
	Notify.Fx(player, "Grabbed", { Uid = uid, Helper = true })
	return { ok = true }
end

local function deliver(carry: Carry)
	local lead, victim = carry.Lead, carry.Victim
	local anchor = Registry.KaijuService.Anchor(carry.Uid)
	local speciesId = anchor and anchor:GetAttribute("Species") or ""
	local victimData = DataService.Get(victim)
	local rec = victimData and Registry.KaijuService.FindRecord(victimData, carry.Uid)
	local baseIncome = if rec then Calc.BaseIncome(rec) else 0
	endCarry(carry.Uid, "Delivered")
	local moved = Registry.KaijuService.Transfer(victim, carry.Uid, lead)
	if not moved then
		Notify.Toast(lead, "No free nest! The kaiju ran home.", "Bad")
		Notify.FxAll("KaijuReturned", { Uid = carry.Uid, Reason = "Full" })
		return
	end
	local species = Kaijus.Get(speciesId)
	local rarity = Rarities.Get(moved.Rarity)
	local stageName = Growth.Get(Calc.Stage(moved)).Name
	Notify.Fx(lead, "HeistSuccess", { Uid = moved.Uid, Species = speciesId, Mutation = moved.Mutation, Stage = Calc.Stage(moved) })
	Notify.Fx(victim, "Robbed", { Thief = lead.DisplayName, Species = speciesId })
	Registry.RewardService.Track(lead, "Steals", 1)
	Registry.RewardService.Track(victim, "Stolen", 1)
	Registry.TutorialService.Notify(lead, "Steal")
	if carry.Helper and carry.Helper.Parent == Players then
		local cut = math.max(50, math.floor(baseIncome * 60 * Economy.HelperCut * Registry.KaijuService.Multiplier(carry.Helper)))
		DataService.AddCash(carry.Helper, cut)
		Notify.Fx(carry.Helper, "HeistCut", { Amount = cut, Leader = lead.DisplayName })
		Registry.RewardService.Track(carry.Helper, "Steals", 1)
	end
	local who = if carry.Helper then ("%s & %s"):format(lead.DisplayName, carry.Helper.DisplayName) else lead.DisplayName
	Notify.Feed(("🦹 %s stole %s's %s %s!"):format(who, victim.DisplayName, stageName, if species then species.Name else "kaiju"), "Heist", rarity.Color)
end

----------------------------------------------------------------------------
-- Bonk
----------------------------------------------------------------------------

local function bonk(player: Player)
	local data = DataService.Get(player)
	local root = rootOf(player)
	local humanoid = humanoidOf(player)
	if not data or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if carrying[player] then
		return -- mains prises
	end
	local level = data.Upgrades.Bonker
	local cooldown = math.max(0.4, Economy.BonkCooldown - level * 0.08)
	if (bonkCooldown[player] or 0) > os.clock() then
		return
	end
	bonkCooldown[player] = os.clock() + cooldown
	local superBonk = Registry.ShopService.HasPass(player, "SuperBonk")
	local range = Economy.BonkRange + level * Economy.UpgradesById.Bonker.PerLevel
	local power = Economy.BonkKnockback
	if superBonk then
		range *= 1.5
		power *= 1.6
	end
	Notify.FxAll("BonkSwing", { UserId = player.UserId, Super = superBonk })

	local look = root.CFrame.LookVector
	local hitAny = false
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = rootOf(other)
			if otherRoot then
				local offset = otherRoot.Position - root.Position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				if flat.Magnitude <= range and math.abs(offset.Y) < 8 and (flat.Magnitude < 3 or flat.Unit:Dot(look) > 0.2) then
					hitAny = true
					local dir = if flat.Magnitude > 0.1 then flat.Unit else look
					Notify.Fx(other, "Knockback", { Velocity = dir * power + Vector3.new(0, power * 0.55, 0), From = player.DisplayName })
					Notify.FxAll("BonkHit", { UserId = other.UserId, Position = otherRoot.Position })
					local uid = carrying[other]
					if uid then
						endCarry(uid, "Dropped", player)
					end
				end
			end
		end
	end
	if hitAny then
		Registry.RewardService.Track(player, "Bonks", 1)
	end
	Registry.EventService.TryBossHit(player, root.Position, range)
	if Registry.TutorialService.TryBonkThief(player, root.Position, range) then
		Registry.RewardService.Track(player, "Bonks", 1)
	end
end

----------------------------------------------------------------------------
-- Outil « Bonker »
----------------------------------------------------------------------------

local function makeBonker(super: boolean): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Bonker"
	tool.ToolTip = "Bonk thieves to make them drop your kaiju!"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -1.6, 0) * CFrame.Angles(0, math.rad(90), 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 4, 0.5)
	handle.Color = Theme.Colors.Ink
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Cylinder
	head.Size = Vector3.new(3.4, 2.4, 2.4)
	head.Color = if super then Theme.Colors.Gold else Theme.Colors.Pink
	head.Material = if super then Enum.Material.Foil else Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, math.rad(90), 0)
	head.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head

	for _, side in { -1, 1 } do
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Shape = Enum.PartType.Cylinder
		cap.Size = Vector3.new(0.3, 2.6, 2.6)
		cap.Color = Theme.Colors.White
		cap.CanCollide = false
		cap.Massless = true
		cap.CFrame = head.CFrame * CFrame.new(side * 1.7, 0, 0)
		cap.Parent = tool
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = cap
		w.Parent = cap
	end
	return tool
end

local function giveTool(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	for _, container in { backpack, player.Character } do
		if container then
			local existing = container:FindFirstChild("Bonker")
			if existing then
				existing:Destroy()
			end
		end
	end
	local tool = makeBonker(Registry.ShopService.HasPass(player, "SuperBonk"))
	tool.Parent = backpack
end

----------------------------------------------------------------------------
-- Boucle des vols
----------------------------------------------------------------------------

local function step()
	local t = Workspace:GetServerTimeNow()
	for uid, carry in carries do
		local lead = carry.Lead
		local leadRoot = rootOf(lead)
		local humanoid = humanoidOf(lead)
		if lead.Parent ~= Players or not leadRoot or not humanoid or humanoid.Health <= 0 then
			endCarry(uid, "Left")
		elseif carry.Victim.Parent ~= Players then
			endCarry(uid, "Left")
		elseif carry.Lifting then
			if t > carry.LiftUntil then
				endCarry(uid, "Timeout")
			end
		elseif os.clock() - carry.Started > Economy.StealMaxCarryTime then
			endCarry(uid, "Timeout")
		else
			local helper = carry.Helper
			if helper then
				local helperRoot = rootOf(helper)
				if helper.Parent ~= Players or not helperRoot or (helperRoot.Position - leadRoot.Position).Magnitude > Economy.HelperMaxDistance then
					endCarry(uid, "HelperLost")
					continue
				end
			end
			-- Anti-téléportation : un porteur ne peut pas dépasser sa vitesse de marche
			local now = os.clock()
			local dt = now - carry.LastCheck
			local pos = leadRoot.Position
			if carry.LastPos and dt > 0 then
				local flat = Vector3.new(pos.X - carry.LastPos.X, 0, pos.Z - carry.LastPos.Z).Magnitude
				-- marge large : sauts, chutes, latence réseau
				local allowed = (humanoid.WalkSpeed * 1.5 + 16) * dt + 8
				if flat > allowed then
					carry.Strikes += 1
					warn(("[StealService] déplacement suspect de %s (%.0f studs en %.2fs)"):format(lead.Name, flat, dt))
					endCarry(uid, "Dropped")
					continue
				end
			end
			carry.LastPos = pos
			carry.LastCheck = now
			local plot = Registry.PlotService.Get(lead)
			if plot and Layout.InPlot(plot.CFrame, pos, -2) then
				deliver(carry)
			end
		end
	end
end

function StealService.Init()
	Router.On("Steal", steal, 3)
	Router.On("Help", function(player, payload)
		local uid = Router.String(payload.Uid)
		if not uid then
			return { ok = false }
		end
		return StealService.Help(player, uid)
	end, 3)
	Router.On("Drop", function(player)
		local uid = carrying[player]
		if uid then
			endCarry(uid, "Dropped", player)
		end
		return { ok = true }
	end, 2)
	Router.OnInput("Bonk", function(player)
		bonk(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local uid = carrying[player]
			if uid then
				endCarry(uid, "Left")
			end
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				StealService.RefreshSpeed(player)
				humanoid.Died:Connect(function()
					local current = carrying[player]
					if current then
						endCarry(current, "Left")
					end
				end)
			end
			task.wait(0.2)
			giveTool(player)
		end)
	end)

	DataService.Loaded:Connect(function(player)
		StealService.RefreshSpeed(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		for uid, carry in carries do
			if carry.Lead == player or carry.Helper == player or carry.Victim == player then
				endCarry(uid, "Left")
			end
		end
		bonkCooldown[player] = nil
		stealCooldown[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(step)
			if not ok then
				warn("[StealService] " .. tostring(err))
			end
		end
	end)
end

function StealService.GiveTool(player: Player)
	giveTool(player)
end

return StealService
