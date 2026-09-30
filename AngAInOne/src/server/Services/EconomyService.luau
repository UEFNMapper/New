--!strict
--[[
	EconomyService : production, collecte et monnaies. Seul endroit où Bits et Chips changent.
	- Recalcule la production (Production.Compute + Bonuses.Compute) quand l'état change
	- Boucle d'1 s : production -> collecteur (ou directement avec Auto-Collect)
	- Gains hors ligne à la connexion
	- Classement hebdo (WeeklyBits) remis à zéro chaque lundi
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Economy.Formulas)
local Production = require(Shared.Economy.Production)
local Bonuses = require(Shared.Economy.Bonuses)
local Remotes = require(Shared.Net.Remotes)
local Session = require(script.Parent.Parent.Core.Session)
local ServerState = require(script.Parent.Parent.Core.ServerState)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local StateService = require(script.Parent.StateService)

local EconomyService = {}

local BASE_WALK_SPEED = 20
local fxRemote: RemoteEvent
local offlineRemote: RemoteEvent
local notifyRemote: RemoteEvent

local function equippedList(session: Session.Session): { { Id: string, Golden: boolean } }
	local byUid: { [string]: { Id: string, Golden: boolean } } = {}
	for _, owned in session.Data.Nanobots.Owned do
		byUid[owned.Uid] = { Id = owned.Id, Golden = owned.Golden }
	end
	local list = {}
	for _, uid in session.Data.Nanobots.Equipped do
		local entry = byUid[uid]
		if entry then
			table.insert(list, entry)
		end
	end
	return list
end

local function countFragments(session: Session.Session): number
	local count = 0
	for _, found in session.Data.Fragments do
		if found then
			count += 1
		end
	end
	return count
end

-- Signature des effets temporaires actifs : si elle change, il faut recalculer.
function EconomyService.EffectsKey(session: Session.Session, now: number): string
	local overclock = session.OverclockUntil > now
	local server = ServerState.ServerBoostUntil > now
	local personal = session.Data.Boosts.BitsX2Until > now
	return `{overclock}{server}{personal}`
end

-- Recalcule bonus + production, applique la vitesse de marche, et réplique l'état.
function EconomyService.Refresh(session: Session.Session)
	local data = session.Data
	local now = os.time()
	local overclockActive = session.OverclockUntil > now
	session.EffectsKey = EconomyService.EffectsKey(session, now)
	session.Bonus = Bonuses.Compute({
		Firmware = data.Firmware,
		FragmentsFound = countFragments(session),
		EquippedNanobots = equippedList(session),
		HasDoubleBits = session.Passes.DoubleBits == true,
		IsPremium = session.IsPremium,
		InGroup = session.InGroup,
		FriendsInServer = session.FriendsInServer,
		ServerBoostActive = ServerState.ServerBoostUntil > now,
		PersonalBoostActive = data.Boosts.BitsX2Until > now,
		OverclockMult = if overclockActive then session.OverclockMult else 1,
	})
	session.Snapshot = Production.Compute({
		Levels = data.Levels,
		Zone = data.Zone,
		PsuLevel = data.PsuLevel,
		CoolingLevel = data.CoolingLevel,
		Multiplier = session.Bonus.Total,
		HeatMultiplier = if overclockActive then GameConfig.Overclock.HeatMult else 1,
		WattsReduction = session.Bonus.WattsReduction,
		HeatReduction = session.Bonus.HeatReduction,
	})
	local character = session.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK_SPEED + session.Bonus.SpeedBonus
	end
	StateService.Push(session)
end

local function rollWeek(session: Session.Session)
	local week = Formulas.WeekIndex(os.time())
	if session.Data.WeeklyIndex ~= week then
		session.Data.WeeklyIndex = week
		session.Data.WeeklyBits = 0
	end
end

-- Crédite des Bits (source analytics : "Collect", "Virus", "Download", "Product"…).
function EconomyService.AddBits(session: Session.Session, amount: number, source: string)
	if amount <= 0 or amount ~= amount then
		return
	end
	local data = session.Data
	rollWeek(session)
	data.Bits += amount
	data.RunBitsEarned += amount
	data.TotalBitsEarned += amount
	data.WeeklyBits += amount
	GameEvents.BitsEarned:Fire(session.Player, amount, source)
	Telemetry.Economy(session.Player, "Source", "Bits", amount, data.Bits, source)
end

function EconomyService.SpendBits(session: Session.Session, amount: number, sku: string): boolean
	local data = session.Data
	if amount < 0 or amount ~= amount or data.Bits < amount then
		return false
	end
	data.Bits -= amount
	Telemetry.Economy(session.Player, "Sink", "Bits", amount, data.Bits, "Shop", sku)
	return true
end

function EconomyService.AddChips(session: Session.Session, amount: number, source: string)
	if amount <= 0 then
		return
	end
	local data = session.Data
	local bonus = if session.Passes.VIP and source == "Daily" then math.floor(amount * GameConfig.VipChipBonus) else 0
	data.Chips += amount + bonus
	Telemetry.Economy(session.Player, "Source", "Chips", amount + bonus, data.Chips, source)
	StateService.Push(session)
end

function EconomyService.SpendChips(session: Session.Session, amount: number, sku: string): boolean
	local data = session.Data
	if amount < 0 or data.Chips < amount then
		return false
	end
	data.Chips -= amount
	Telemetry.Economy(session.Player, "Sink", "Chips", amount, data.Chips, "Shop", sku)
	StateService.Push(session)
	return true
end

-- Montant équivalent à `seconds` de production actuelle (plancher pour les tout débuts).
function EconomyService.ProductionValue(session: Session.Session, seconds: number): number
	return math.max(session.Snapshot.Rate * seconds, 25 * math.sqrt(seconds))
end

function EconomyService.Collect(session: Session.Session): number
	local data = session.Data
	local amount = data.Pending
	if amount < 1 then
		return 0
	end
	data.Pending = 0
	EconomyService.AddBits(session, amount, "Collect")
	GameEvents.BitsCollected:Fire(session.Player, amount)
	fxRemote:FireClient(session.Player, "Collect", { Amount = amount })
	StateService.Push(session)
	return amount
end

function EconomyService.Notify(session: Session.Session, kind: string, text: string)
	notifyRemote:FireClient(session.Player, kind, text)
end

function EconomyService.Fx(session: Session.Session, kind: string, payload: any)
	fxRemote:FireClient(session.Player, kind, payload)
end

-- Production "de fond" pour le hors ligne : sans Server Boost, potion x2 ni overclock.
local function offlineRate(session: Session.Session): number
	local data = session.Data
	local bonus = Bonuses.Compute({
		Firmware = data.Firmware,
		FragmentsFound = countFragments(session),
		EquippedNanobots = equippedList(session),
		HasDoubleBits = session.Passes.DoubleBits == true,
		IsPremium = session.IsPremium,
		InGroup = session.InGroup,
		FriendsInServer = 0,
		ServerBoostActive = false,
		PersonalBoostActive = false,
		OverclockMult = 1,
	})
	return Production.Compute({
		Levels = data.Levels,
		Zone = data.Zone,
		PsuLevel = data.PsuLevel,
		CoolingLevel = data.CoolingLevel,
		Multiplier = bonus.Total,
		HeatMultiplier = 1,
		WattsReduction = bonus.WattsReduction,
		HeatReduction = bonus.HeatReduction,
	}).Rate
end

local function grantOffline(session: Session.Session, last: number)
	session.OfflineHandled = true
	local data = session.Data
	if last <= 0 or not data.PoweredOn then
		return
	end
	local elapsed = os.time() - last
	if elapsed < GameConfig.Offline.MinSecondsToReport then
		return
	end
	local hasPass = session.Passes.OfflineMax == true
	local cap = if hasPass then GameConfig.Offline.PassCapSeconds else GameConfig.Offline.BaseCapSeconds
	local ratio = if hasPass then GameConfig.Offline.PassRatio else GameConfig.Offline.BaseRatio
	local amount = Formulas.OfflineEarnings(offlineRate(session), elapsed, cap, ratio)
	if amount >= 1 then
		EconomyService.AddBits(session, amount, "Offline")
		offlineRemote:FireClient(session.Player, amount, math.min(elapsed, cap))
	end
end

local function tick(dt: number)
	local now = os.time()
	for _, session in Session.All() do
		local data = session.Data
		-- Début/fin d'un effet temporaire (overclock, boosts) -> recalcul
		if EconomyService.EffectsKey(session, now) ~= session.EffectsKey then
			EconomyService.Refresh(session)
		end
		if data.PoweredOn and session.Snapshot.Rate > 0 then
			local gain = session.Snapshot.Rate * dt
			if session.Passes.AutoCollect then
				EconomyService.AddBits(session, gain, "AutoCollect")
			else
				-- Le plafond limite les NOUVEAUX gains ; ce qui est déjà stocké n'est jamais détruit
				-- (ex. fin d'un boost qui fait baisser le plafond).
				local cap = session.Snapshot.Rate * GameConfig.CollectorCapSeconds
				if data.Pending < cap then
					data.Pending = math.min(data.Pending + gain, cap)
				end
			end
		end
		data.Stats.Playtime += dt
		session.PlaytimeCarry += dt
		if session.PlaytimeCarry >= 60 then
			session.PlaytimeCarry -= 60
			GameEvents.PlaytimeMinute:Fire(session.Player)
		end
		session.LastTick = Workspace:GetServerTimeNow()
		StateService.SendTick(session)
	end
end

function EconomyService.Start()
	fxRemote = Remotes.Get("Fx")
	offlineRemote = Remotes.Get("Offline")
	notifyRemote = Remotes.Get("Notify")

	GameEvents.StateChanged:Connect(function(player: Player)
		local session = Session.Get(player)
		if session then
			EconomyService.Refresh(session)
		end
	end)

	Session.Added:Connect(function(session: Session.Session)
		rollWeek(session)
		-- Lu tout de suite : la boucle de sauvegarde de LastOnline pourrait l'écraser avant le calcul.
		local lastOnline = session.Data.Stats.LastOnline
		EconomyService.Refresh(session)
		-- Les gains hors ligne dépendent du pass "Hors ligne max" : on attend que les pass soient
		-- vérifiés (MonetizationService), avec un délai maximum de 15 s.
		task.spawn(function()
			local deadline = os.clock() + 15
			while not session.PassesLoaded and os.clock() < deadline and Session.Get(session.Player) == session do
				task.wait(0.2)
			end
			if Session.Get(session.Player) == session then
				EconomyService.Refresh(session)
				grantOffline(session, lastOnline)
				session.Data.Stats.LastOnline = os.time()
			end
		end)
		session.Trove:Connect(session.Player.CharacterAdded, function(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.WalkSpeed = BASE_WALK_SPEED + session.Bonus.SpeedBonus
			end
		end)
	end)

	-- Sauvegarde régulière de LastOnline (au cas où le serveur plante)
	task.spawn(function()
		while true do
			task.wait(60)
			local now = os.time()
			for _, session in Session.All() do
				if session.OfflineHandled then
					session.Data.Stats.LastOnline = now
				end
			end
		end
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(GameConfig.TickSeconds)
			local now = os.clock()
			local dt = math.min(now - last, 5)
			last = now
			tick(dt)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local session = Session.Get(player)
		-- Reconnexion très rapide : si l'offline n'a pas encore été versé, on garde l'ancien
		-- LastOnline pour ne pas effacer l'absence précédente.
		if session and session.OfflineHandled then
			session.Data.Stats.LastOnline = os.time()
		end
	end)
end

return EconomyService
