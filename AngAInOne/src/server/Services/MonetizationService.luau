--!strict
--[[
	MonetizationService : Game Passes, Developer Products, Premium, règles de conformité.

	ProcessReceipt est idempotent et sûr :
	1. reçu déjà traité (PurchaseId dans le profil) -> PurchaseGranted, rien n'est redonné ;
	2. sinon on donne l'objet, on enregistre le PurchaseId, on force une sauvegarde
	   et on attend qu'elle soit confirmée avant de répondre PurchaseGranted ;
	3. si quoi que ce soit échoue -> NotProcessedYet (Roblox réessaiera plus tard).

	Les autres services enregistrent leurs produits via RegisterProduct(kind, handler).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Products = require(Shared.Config.Products)
local DataSchema = require(Shared.Data.DataSchema)
local Remotes = require(Shared.Net.Remotes)
local Session = require(script.Parent.Parent.Core.Session)
local ServerState = require(script.Parent.Parent.Core.ServerState)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local EconomyService = require(script.Parent.EconomyService)

export type ProductHandler = (session: Session.Session, product: Products.ProductDef) -> boolean

local MonetizationService = {}

local handlers: { [string]: ProductHandler } = {}
local SAVE_CONFIRM_TIMEOUT = 15

function MonetizationService.RegisterProduct(kind: string, handler: ProductHandler)
	handlers[kind] = handler
end

function MonetizationService.HasPass(session: Session.Session, key: string): boolean
	return session.Passes[key] == true
end

local function checkPasses(session: Session.Session)
	for _, pass in Products.Passes do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function(): boolean
				return MarketplaceService:UserOwnsGamePassAsync(session.UserId, pass.Id)
			end)
			if ok and owns then
				session.Passes[pass.Key] = true
			end
		end
	end
end

local function checkPolicy(session: Session.Session)
	local ok, info = pcall(function(): { [string]: any }
		return PolicyService:GetPolicyInfoForPlayerAsync(session.Player)
	end)
	-- En cas d'erreur, on applique la règle la plus stricte (objets aléatoires payants masqués).
	session.PaidRandomAllowed = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
end

local function checkGroup(session: Session.Session)
	if GameConfig.GroupId == 0 then
		return
	end
	local ok, inGroup = pcall(function(): boolean
		return session.Player:IsInGroupAsync(GameConfig.GroupId)
	end)
	session.InGroup = ok and inGroup == true
end

-- Attend que la dernière sauvegarde confirmée contienne ce reçu.
local function waitForSave(session: Session.Session, purchaseId: string): boolean
	local profile = session.Profile
	profile:Save()
	local deadline = os.clock() + SAVE_CONFIRM_TIMEOUT
	while os.clock() < deadline do
		if not profile:IsActive() then
			return false
		end
		local saved = profile.LastSavedData
		if saved and saved.Receipts and table.find(saved.Receipts, purchaseId) then
			return true
		end
		task.wait(0.5)
	end
	return false
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Le profil peut être encore en chargement : on patiente un peu.
	local session = Session.Get(player)
	local waited = 0
	while not session and waited < 10 and player.Parent do
		waited += task.wait(0.25)
		session = Session.Get(player)
	end
	if not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(info.PurchaseId)
	if DataSchema.HasReceipt(session.Data, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Products.ProductById[info.ProductId]
	local handler = product and handlers[product.Kind]
	if not product or not handler then
		warn(`[Monetization] Produit inconnu {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, session, product)
	if not ok or not granted then
		warn(`[Monetization] Échec d'attribution de {product.Key}`, granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataSchema.AddReceipt(session.Data, purchaseId)
	Telemetry.Custom(player, `Purchase_{product.Key}`, info.CurrencySpent)
	GameEvents.StateChanged:Fire(player)
	if waitForSave(session, purchaseId) then
		EconomyService.Notify(session, "Success", `Merci ! {product.Name} reçu.`)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.Start()
	local serverInfo = Remotes.Get("ServerInfo")

	-- Produits gérés directement ici
	MonetizationService.RegisterProduct("Bits", function(session, product)
		EconomyService.AddBits(session, EconomyService.ProductionValue(session, product.Amount), "Product")
		return true
	end)
	MonetizationService.RegisterProduct("Chips", function(session, product)
		EconomyService.AddChips(session, product.Amount, "Product")
		return true
	end)
	MonetizationService.RegisterProduct("ServerBoost", function(session, product)
		local now = os.time()
		ServerState.ServerBoostUntil = math.max(ServerState.ServerBoostUntil, now) + product.Amount
		ServerState.ServerBoostBy = session.Player.DisplayName
		serverInfo:FireAllClients({
			ServerBoostUntil = ServerState.ServerBoostUntil,
			ServerBoostBy = ServerState.ServerBoostBy,
		})
		for _, other in Session.All() do
			EconomyService.Refresh(other)
			EconomyService.Notify(other, "Boost", `{session.Player.DisplayName} offre x2 Bits à tout le serveur !`)
		end
		return true
	end)

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			local session = Session.Get(player)
			local pass = Products.PassById[passId]
			if session and pass then
				session.Passes[pass.Key] = true
				EconomyService.Notify(session, "Success", `Pass {pass.Name} activé !`)
				GameEvents.StateChanged:Fire(player)
			end
		end
	)

	Players.PlayerMembershipChanged:Connect(function(player: Player)
		local session = Session.Get(player)
		if session then
			session.IsPremium = player.MembershipType == Enum.MembershipType.Premium
			GameEvents.StateChanged:Fire(player)
		end
	end)

	Session.Added:Connect(function(session: Session.Session)
		task.spawn(function()
			checkPasses(session)
			session.PassesLoaded = true
			if Session.Get(session.Player) == session then
				GameEvents.PassesLoaded:Fire(session.Player)
			end
			checkPolicy(session)
			checkGroup(session)
			if Session.Get(session.Player) == session then
				GameEvents.StateChanged:Fire(session.Player)
			end
		end)
	end)

	GameEvents.ClientReady:Connect(function(player: Player)
		serverInfo:FireClient(player, {
			ServerBoostUntil = ServerState.ServerBoostUntil,
			ServerBoostBy = ServerState.ServerBoostBy,
		})
	end)
end

return MonetizationService
