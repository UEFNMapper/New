--!nonstrict
-- Boutique : Game Passes, Developer Products (Robux), améliorations, nids et
-- potions (monnaie du jeu). Respecte PolicyService pour le hasard payant.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Logic.Format)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local ShopService = {}

local owned: { [Player]: { [string]: boolean } } = {}
local restricted: { [Player]: boolean } = {}
local pendingTarget: { [Player]: string } = {} -- kaiju ciblé par « Instant Grow »

local IS_STUDIO = RunService:IsStudio()

function ShopService.HasPass(player: Player, key: string): boolean
	local o = owned[player]
	if o and o[key] then
		return true
	end
	local data = DataService.Get(player)
	return data ~= nil and data.StudioPasses[key] == true
end

function ShopService.IsRandomRestricted(player: Player): boolean
	return restricted[player] == true
end

local function sendPasses(player: Player)
	local list = {}
	for _, pass in Monetization.Passes do
		if ShopService.HasPass(player, pass.Key) then
			list[pass.Key] = true
		end
	end
	DataService.SendDerived(player, "Passes", list)
	DataService.SendDerived(player, "RandomRestricted", restricted[player] == true)
end

-- Effets à appliquer quand un pass devient actif.
local function onPassGranted(player: Player, key: string)
	sendPasses(player)
	local pass = Monetization.PassByKey[key]
	Notify.Fx(player, "PassUnlocked", { Key = key, Name = pass and pass.Name or key })
	Registry.KaijuService.RefreshPlayer(player)
	Registry.StealService.RefreshSpeed(player)
end

local function loadOwnership(player: Player)
	local o = {}
	for _, pass in Monetization.Passes do
		if pass.Id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and has then
				o[pass.Key] = true
			end
		end
	end
	owned[player] = o
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	restricted[player] = ok and info and (info :: any).ArePaidRandomItemsRestricted == true or false
	sendPasses(player)
end

----------------------------------------------------------------------------
-- Produits : effets
----------------------------------------------------------------------------

local ProductHandlers: { [string]: (player: Player, data: any, product: Monetization.Product) -> boolean } = {}

local function income(player: Player): number
	return Registry.KaijuService.IncomePerSecond(player)
end

ProductHandlers.StarterPack = function(player, data)
	if data.StarterPack then
		-- déjà acheté : on rembourse en gemmes pour ne rien perdre
		DataService.AddGems(player, 150)
		return true
	end
	data.StarterPack = true
	DataService.AddGems(player, 150)
	data.Potions.Luck += 2
	DataService.Replicate(player, "Potions", "StarterPack")
	Registry.KaijuService.GiveEgg(player, "Legendary", "Starter Pack")
	return true
end

local function cash(player: Player, _data: any, product: Monetization.Product): boolean
	local amount = math.max(1000, math.floor(income(player) * (product.Amount or 600)))
	DataService.AddCash(player, amount)
	Notify.Fx(player, "CashBurst", { Amount = amount })
	return true
end
ProductHandlers.CashS = cash
ProductHandlers.CashM = cash
ProductHandlers.CashL = cash

local function gems(player: Player, _data: any, product: Monetization.Product): boolean
	DataService.AddGems(player, product.Amount or 0)
	Notify.Fx(player, "GemBurst", { Amount = product.Amount })
	return true
end
ProductHandlers.Gems100 = gems
ProductHandlers.Gems550 = gems
ProductHandlers.Gems1400 = gems
ProductHandlers.Gems3500 = gems

ProductHandlers.InstantGrow = function(player)
	return Registry.KaijuService.InstantGrow(player, pendingTarget[player])
end

ProductHandlers.InstantHatch = function(player)
	return Registry.KaijuService.HatchAll(player)
end

ProductHandlers.ShieldNow = function(player)
	return Registry.PlotService.ForceShield(player, 180)
end

ProductHandlers.Spins3 = function(player, data, product)
	data.Spins += product.Amount or 3
	DataService.Replicate(player, "Spins")
	return true
end

ProductHandlers.ServerLuck = function(player)
	Registry.MeteorService.AddServerLuck(2, 900)
	Registry.Notify.Feed(("🍀 %s activated SERVER LUCK x2 for everyone!"):format(player.DisplayName), "Purchase")
	return true
end

ProductHandlers.MeteorShower = function(player)
	Registry.EventService.Force("MeteorShower", player)
	return true
end

ProductHandlers.BloodMoon = function(player)
	Registry.EventService.Force("BloodMoon", player)
	return true
end

local function grantProduct(player: Player, product: Monetization.Product): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local handler = ProductHandlers[product.Key]
	if not handler then
		warn("[Shop] Produit sans effet : " .. product.Key)
		return false
	end
	local ok = handler(player, data, product)
	if ok then
		Notify.Fx(player, "Purchased", { Key = product.Key, Name = product.Name })
	end
	return ok
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.WaitFor(player, 10)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(data.Receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Monetization.ProductById[receipt.ProductId]
	if not product then
		warn("[Shop] Produit inconnu : " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(grantProduct, player, product)
	if not ok or not granted then
		warn("[Shop] Échec d'attribution : " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > 50 do
		table.remove(data.Receipts, 1)
	end
	DataService.Save(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

local function buy(player: Player, payload: any): Router.Result
	local kind = Router.String(payload.Kind)
	local key = Router.String(payload.Key)
	if not kind or not key then
		return { ok = false, msg = "Bad request" }
	end
	if kind == "Pass" then
		local pass = Monetization.PassByKey[key]
		if not pass then
			return { ok = false, msg = "Unknown pass" }
		end
		if ShopService.HasPass(player, key) then
			return { ok = false, msg = "You already own this!" }
		end
		if pass.Random and restricted[player] then
			return { ok = false, msg = "Not available in your region" }
		end
		if pass.Id == 0 then
			if IS_STUDIO then
				local data = DataService.Get(player)
				data.StudioPasses[key] = true
				onPassGranted(player, key)
				return { ok = true, msg = "[Studio] Pass granted for testing" }
			end
			return { ok = false, msg = "Coming soon!" }
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		return { ok = true }
	elseif kind == "Product" then
		local product = Monetization.ProductByKey[key]
		if not product then
			return { ok = false, msg = "Unknown product" }
		end
		if product.Random and restricted[player] then
			return { ok = false, msg = "Not available in your region" }
		end
		local data = DataService.Get(player)
		if product.OneTime and data and data.StarterPack and product.Key == "StarterPack" then
			return { ok = false, msg = "Already claimed!" }
		end
		if type(payload.Target) == "string" then
			pendingTarget[player] = payload.Target
		end
		if product.Id == 0 then
			if IS_STUDIO then
				local ok = grantProduct(player, product)
				return { ok = ok, msg = if ok then "[Studio] Purchase simulated" else "Could not apply" }
			end
			return { ok = false, msg = "Coming soon!" }
		end
		MarketplaceService:PromptProductPurchase(player, product.Id)
		return { ok = true }
	end
	return { ok = false, msg = "Bad request" }
end

local function buyUpgrade(player: Player, payload: any): Router.Result
	local id = Router.String(payload.Id)
	local upgrade = id and Economy.UpgradesById[id]
	local data = DataService.Get(player)
	if not upgrade or not data then
		return { ok = false, msg = "Unknown upgrade" }
	end
	local level = data.Upgrades[upgrade.Id] or 0
	if level >= upgrade.MaxLevel then
		return { ok = false, msg = "Max level!" }
	end
	local price = Economy.UpgradePrice(upgrade.Id, level)
	if not DataService.Spend(player, "Cash", price) then
		return { ok = false, msg = "Not enough cash (" .. Format.Cash(price) .. ")" }
	end
	data.Upgrades[upgrade.Id] = level + 1
	DataService.Replicate(player, "Upgrades")
	Notify.Fx(player, "Upgraded", { Id = upgrade.Id, Level = level + 1 })
	Registry.StealService.RefreshSpeed(player)
	Registry.KaijuService.RefreshPlayer(player)
	return { ok = true }
end

local function buyNest(player: Player): Router.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	if data.Nests >= Economy.MaxNests then
		return { ok = false, msg = "All nests unlocked!" }
	end
	local price = Economy.NestPrice(data.Nests)
	if not DataService.Spend(player, "Cash", price) then
		return { ok = false, msg = "Not enough cash (" .. Format.Cash(price) .. ")" }
	end
	data.Nests += 1
	DataService.Replicate(player, "Nests")
	Registry.PlotService.RefreshNests(player)
	Registry.KaijuService.PlacePending(player)
	Notify.Fx(player, "NestUnlocked", { Count = data.Nests })
	return { ok = true }
end

local function buyPotion(player: Player, payload: any): Router.Result
	local id = Router.String(payload.Id)
	local potion = id and Economy.PotionsById[id]
	local data = DataService.Get(player)
	if not potion or not data then
		return { ok = false, msg = "Unknown potion" }
	end
	if not DataService.Spend(player, "Gems", potion.GemPrice) then
		return { ok = false, msg = "Not enough gems" }
	end
	data.Potions[potion.Id] += 1
	DataService.Replicate(player, "Potions")
	return { ok = true }
end

local function usePotion(player: Player, payload: any): Router.Result
	local id = Router.String(payload.Id)
	local potion = id and Economy.PotionsById[id]
	local data = DataService.Get(player)
	if not potion or not data then
		return { ok = false, msg = "Unknown potion" }
	end
	if data.Potions[potion.Id] <= 0 then
		return { ok = false, msg = "You don't have this potion" }
	end
	data.Potions[potion.Id] -= 1
	local now = os.time()
	data.Boosts[potion.Id] = math.max(data.Boosts[potion.Id], now) + potion.Duration
	DataService.Replicate(player, "Potions", "Boosts")
	Notify.Fx(player, "PotionUsed", { Id = potion.Id })
	Registry.KaijuService.RefreshPlayer(player)
	return { ok = true }
end

function ShopService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local pass = Monetization.PassById[passId]
		if pass then
			owned[player] = owned[player] or {}
			owned[player][pass.Key] = true
			onPassGranted(player, pass.Key)
		end
	end)

	Router.On("Buy", buy, 2)
	Router.On("BuyUpgrade", buyUpgrade, 6)
	Router.On("BuyNest", buyNest, 3)
	Router.On("BuyPotion", buyPotion, 4)
	Router.On("UsePotion", usePotion, 4)

	DataService.Loaded:Connect(function(player)
		loadOwnership(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		restricted[player] = nil
		pendingTarget[player] = nil
	end)
end

return ShopService
