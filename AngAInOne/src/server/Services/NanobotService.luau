--!strict
--[[
	NanobotService : capsules, inventaire, équipement et fusion des Nanobots.
	Les tirages sont faits côté serveur avec les probabilités publiées dans Config/Nanobots.
	Les capsules "payantes" (Chips achetables en Robux) respectent PolicyService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Nanobots = require(Shared.Config.Nanobots)
local Formulas = require(Shared.Economy.Formulas)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)
local StateService = require(script.Parent.StateService)
local MonetizationService = require(script.Parent.MonetizationService)

local NanobotService = {}

local rng = Random.new()

local function slots(session: Session.Session): number
	return StateService.NanobotSlots(session)
end

-- Ajoute un Nanobot à l'inventaire (et l'équipe s'il reste une place). Renvoie son Uid.
function NanobotService.Grant(session: Session.Session, nanobotId: string, golden: boolean): string?
	local data = session.Data
	if not Nanobots.ById[nanobotId] or #data.Nanobots.Owned >= GameConfig.Nanobots.MaxInventory then
		return nil
	end
	local uid = tostring(data.Nanobots.NextUid)
	data.Nanobots.NextUid += 1
	table.insert(data.Nanobots.Owned, { Uid = uid, Id = nanobotId, Golden = golden })
	if #data.Nanobots.Equipped < slots(session) then
		table.insert(data.Nanobots.Equipped, uid)
	end
	return uid
end

local function roll(capsuleId: string): Nanobots.NanobotDef?
	local capsule = Nanobots.CapsuleById[capsuleId]
	if not capsule then
		return nil
	end
	local rarity = Formulas.WeightedPick(capsule.Odds, rng:NextNumber())
	local pool = Nanobots.Pool(capsuleId, rarity)
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

-- Meilleure capsule en Bits disponible (utilisée par les récompenses gratuites).
function NanobotService.BestFreeCapsule(session: Session.Session): string?
	local best: string? = nil
	for _, capsule in Nanobots.Capsules do
		if capsule.Currency == "Bits" and capsule.RequiredZone <= session.Data.Zone then
			best = capsule.Id
		end
	end
	return best
end

-- Ouvre une capsule sans la payer (récompense). Renvoie le Nanobot obtenu.
function NanobotService.OpenFree(session: Session.Session, capsuleId: string): Nanobots.NanobotDef?
	local def = roll(capsuleId)
	if not def then
		return nil
	end
	local uid = NanobotService.Grant(session, def.Id, false)
	if not uid then
		EconomyService.Notify(session, "Error", "Inventaire de Nanobots plein.")
		return nil
	end
	session.Data.Stats.CapsulesOpened += 1
	EconomyService.Fx(session, "Capsule", { NanobotId = def.Id, Uid = uid, CapsuleId = capsuleId })
	GameEvents.CapsuleOpened:Fire(session.Player, capsuleId)
	GameEvents.StateChanged:Fire(session.Player)
	return def
end

-- Donne un Nanobot aléatoire d'une rareté précise, parmi les capsules débloquées.
function NanobotService.GrantRandomOfRarity(session: Session.Session, rarity: string): Nanobots.NanobotDef?
	local candidates = {}
	for _, capsule in Nanobots.Capsules do
		if capsule.Currency == "Bits" and capsule.RequiredZone <= math.max(session.Data.Zone, 2) then
			for _, def in Nanobots.Pool(capsule.Id, rarity) do
				table.insert(candidates, def)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local def = candidates[rng:NextInteger(1, #candidates)]
	local uid = NanobotService.Grant(session, def.Id, false)
	if uid then
		EconomyService.Fx(session, "Capsule", { NanobotId = def.Id, Uid = uid, CapsuleId = def.Capsule })
		GameEvents.StateChanged:Fire(session.Player)
		return def
	end
	return nil
end

function NanobotService.OpenCapsule(session: Session.Session, capsuleId: string)
	local capsule = Nanobots.CapsuleById[capsuleId]
	local data = session.Data
	if not capsule or data.Zone < capsule.RequiredZone then
		return
	end
	if capsule.Paid and not session.PaidRandomAllowed then
		EconomyService.Notify(session, "Error", "Cette capsule n'est pas disponible dans ton pays.")
		return
	end
	if #data.Nanobots.Owned >= GameConfig.Nanobots.MaxInventory then
		EconomyService.Notify(session, "Error", "Inventaire plein : fusionne ou libère des Nanobots.")
		return
	end
	local cost = StateService.CapsuleCost(session, capsuleId)
	local paid = if capsule.Currency == "Chips"
		then EconomyService.SpendChips(session, cost, `Capsule_{capsuleId}`)
		else EconomyService.SpendBits(session, cost, `Capsule_{capsuleId}`)
	if not paid then
		EconomyService.Notify(
			session,
			"Error",
			if capsule.Currency == "Chips" then "Pas assez de Chips." else "Pas assez de Bits."
		)
		return
	end
	NanobotService.OpenFree(session, capsuleId)
end

function NanobotService.Equip(session: Session.Session, uid: string, equip: boolean)
	local nanobots = session.Data.Nanobots
	local owned = false
	for _, entry in nanobots.Owned do
		if entry.Uid == uid then
			owned = true
			break
		end
	end
	if not owned then
		return
	end
	local index = table.find(nanobots.Equipped, uid)
	if equip and not index then
		if #nanobots.Equipped >= slots(session) then
			EconomyService.Notify(session, "Error", "Tous tes slots sont occupés.")
			return
		end
		table.insert(nanobots.Equipped, uid)
	elseif not equip and index then
		table.remove(nanobots.Equipped, index)
	else
		return
	end
	GameEvents.StateChanged:Fire(session.Player)
end

-- Fusionne 5 exemplaires normaux d'un même Nanobot en 1 doré (x1,5).
function NanobotService.Fuse(session: Session.Session, nanobotId: string)
	local nanobots = session.Data.Nanobots
	local def = Nanobots.ById[nanobotId]
	if not def then
		return
	end
	local candidates = {}
	for _, entry in nanobots.Owned do
		if entry.Id == nanobotId and not entry.Golden then
			table.insert(candidates, entry.Uid)
		end
	end
	if #candidates < GameConfig.Nanobots.FuseCount then
		EconomyService.Notify(session, "Error", `Il faut {GameConfig.Nanobots.FuseCount} exemplaires identiques.`)
		return
	end
	-- Retire d'abord les exemplaires non équipés.
	table.sort(candidates, function(a: string, b: string): boolean
		local ea = table.find(nanobots.Equipped, a) ~= nil
		local eb = table.find(nanobots.Equipped, b) ~= nil
		if ea ~= eb then
			return not ea
		end
		return a < b
	end)
	local wasEquipped = false
	for i = 1, GameConfig.Nanobots.FuseCount do
		local uid = candidates[i]
		local equippedIndex = table.find(nanobots.Equipped, uid)
		if equippedIndex then
			table.remove(nanobots.Equipped, equippedIndex)
			wasEquipped = true
		end
		for index, entry in nanobots.Owned do
			if entry.Uid == uid then
				table.remove(nanobots.Owned, index)
				break
			end
		end
	end
	local newUid = NanobotService.Grant(session, nanobotId, true)
	if newUid and wasEquipped and not table.find(nanobots.Equipped, newUid) and #nanobots.Equipped < slots(session) then
		table.insert(nanobots.Equipped, newUid)
	end
	EconomyService.Fx(session, "Fuse", { NanobotId = nanobotId, Uid = newUid })
	GameEvents.StateChanged:Fire(session.Player)
end

function NanobotService.Start()
	RemoteGuard.On("OpenCapsule", { Args = { RemoteGuard.String(16) } }, NanobotService.OpenCapsule)
	RemoteGuard.On("EquipNanobot", {
		Args = { RemoteGuard.String(12), RemoteGuard.Bool() },
	}, NanobotService.Equip)
	RemoteGuard.On("FuseNanobots", { Args = { RemoteGuard.String(16) } }, NanobotService.Fuse)

	-- Starter Pack : Nanobot Rare + 300 Chips + 30 min de Bits x2 (une seule fois).
	MonetizationService.RegisterProduct("StarterPack", function(session, _product)
		local data = session.Data
		if data.StarterPackBought then
			-- Déjà acheté (ne devrait pas arriver : l'offre est masquée) -> on donne des Chips.
			EconomyService.AddChips(session, 300, "StarterPackDuplicate")
			return true
		end
		data.StarterPackBought = true
		NanobotService.GrantRandomOfRarity(session, "Rare")
		EconomyService.AddChips(session, 300, "StarterPack")
		data.Boosts.BitsX2Until = math.max(data.Boosts.BitsX2Until, os.time()) + GameConfig.BitsBoostPotionSeconds
		return true
	end)
end

return NanobotService
