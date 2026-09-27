--!nonstrict
-- Évolution (rebirth) et Labo de fusion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kaijus = require(Shared.Config.Kaijus)
local Rarities = require(Shared.Config.Rarities)
local Economy = require(Shared.Config.Economy)
local Growth = require(Shared.Config.Growth)
local Levels = require(Shared.Config.Levels)
local Calc = require(Shared.Logic.Calc)
local Roll = require(Shared.Logic.Roll)
local Format = require(Shared.Logic.Format)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Router = require(script.Parent.Router)
local Notify = require(script.Parent.Notify)

local ProgressionService = {}

ProgressionService.FuseMinStage = 3 -- Adulte
ProgressionService.FuseUpgradeChance = 0.5

local function isBusy(uid: string): boolean
	local anchor = Registry.KaijuService.Anchor(uid)
	return anchor ~= nil and (anchor:GetAttribute("CarriedBy") or 0) ~= 0
end

----------------------------------------------------------------------------
-- Rebirth
----------------------------------------------------------------------------

-- Trouve le kaiju sacrifié : rareté >= requise, stade Adulte ou plus, le moins précieux.
local function findSacrifice(data: any, needRarity: string): Calc.KaijuRecord?
	local need = Rarities.Get(needRarity).Order
	local best: Calc.KaijuRecord? = nil
	for _, rec in data.Kaijus do
		if not rec.Egg and rec.Species and Rarities.Get(rec.Rarity).Order >= need and Calc.Stage(rec) >= 3 and not isBusy(rec.Uid) then
			if not best or Calc.BaseIncome(rec) < Calc.BaseIncome(best) then
				best = rec
			end
		end
	end
	return best
end

local function rebirth(player: Player): Router.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	local nextRebirth = Calc.NextRebirth(data.Rebirths)
	if not nextRebirth then
		return { ok = false, msg = "Max evolution reached!" }
	end
	if Registry.RampageService.IsActive(player) then
		return { ok = false, msg = "Finish your Rampage first!" }
	end
	if data.Level < (Levels.MenuLevels.Rebirth or 1) then
		return { ok = false, msg = ("Reach LEVEL %d first!"):format(Levels.MenuLevels.Rebirth) }
	end
	if data.Cash < nextRebirth.Cost then
		return { ok = false, msg = "Need " .. Format.Cash(nextRebirth.Cost) }
	end
	local sacrifice = findSacrifice(data, nextRebirth.NeedRarity)
	if not sacrifice then
		return { ok = false, msg = ("Need an ADULT %s kaiju (or better)"):format(string.upper(Rarities.Get(nextRebirth.NeedRarity).Name)) }
	end
	for _, rec in data.Kaijus do
		if isBusy(rec.Uid) then
			return { ok = false, msg = "One of your kaijus is being stolen!" }
		end
	end

	-- Réinitialisation
	for _, rec in table.clone(data.Kaijus) do
		Registry.KaijuService.RemoveRecord(player, rec.Uid)
	end
	data.Cash = Economy.StartCash
	data.Stored = 0
	data.Nests = Economy.StartNests
	data.PendingEggs = {}
	data.Rebirths += 1
	data.Gems += nextRebirth.Gems
	DataService.Replicate(player, "Cash", "Stored", "Nests", "PendingEggs", "Rebirths", "Gems", "Kaijus")
	Registry.PlotService.RefreshNests(player)
	Registry.KaijuService.RefreshPlayer(player)
	Registry.KaijuService.GiveEgg(player, nextRebirth.EggRarity, "Evolution")
	Registry.LevelService.AddXp(player, Levels.Xp.Rebirth * data.Rebirths, "Rebirth")
	Registry.LeaderboardService.Update(player)

	Notify.FxAll("Rebirth", { UserId = player.UserId, Level = data.Rebirths })
	Notify.Feed(("🧬 %s EVOLVED to level %d!"):format(player.DisplayName, data.Rebirths), "Rebirth")
	return { ok = true, level = data.Rebirths }
end

----------------------------------------------------------------------------
-- Fusion
----------------------------------------------------------------------------

-- Probabilités d'une fusion (affichées au joueur avant de fusionner).
function ProgressionService.FuseOdds(a: Calc.KaijuRecord, b: Calc.KaijuRecord): { { Label: string, Chance: number } }
	local recipe = Kaijus.FindRecipe(a.Species or "", b.Species or "")
	if recipe then
		local need = recipe.RecipeStage or ProgressionService.FuseMinStage
		if Calc.Stage(a) < need or Calc.Stage(b) < need then
			return { { Label = ("SECRET recipe! Grow both to %s"):format(string.upper(Growth.Get(need).Name)), Chance = 0 } }
		end
		return { { Label = recipe.Name .. " (SECRET)", Chance = 1 } }
	end
	local ra, rb = Rarities.Get(a.Rarity), Rarities.Get(b.Rarity)
	local top = if ra.Order >= rb.Order then ra else rb
	local nextR = Rarities.Next(top.Id)
	if a.Species == b.Species then
		return {
			{ Label = "Same kaiju + guaranteed mutation", Chance = 1 },
		}
	end
	if nextR then
		return {
			{ Label = "Random " .. nextR.Name .. " kaiju", Chance = ProgressionService.FuseUpgradeChance },
			{ Label = "Random " .. top.Name .. " kaiju", Chance = 1 - ProgressionService.FuseUpgradeChance },
		}
	end
	return { { Label = "Random " .. top.Name .. " kaiju", Chance = 1 } }
end

local function fuse(player: Player, payload: any): Router.Result
	local ua, ub = Router.String(payload.A), Router.String(payload.B)
	local data = DataService.Get(player)
	if not ua or not ub or ua == ub or not data then
		return { ok = false, msg = "Pick two kaijus" }
	end
	if data.Level < (Levels.MenuLevels.Fusion or 1) then
		return { ok = false, msg = ("Reach LEVEL %d first!"):format(Levels.MenuLevels.Fusion) }
	end
	local a = Registry.KaijuService.FindRecord(data, ua)
	local b = Registry.KaijuService.FindRecord(data, ub)
	if not a or not b or a.Egg or b.Egg or not a.Species or not b.Species then
		return { ok = false, msg = "Pick two hatched kaijus" }
	end
	if Calc.Stage(a) < ProgressionService.FuseMinStage or Calc.Stage(b) < ProgressionService.FuseMinStage then
		return { ok = false, msg = "Both kaijus must be ADULT or bigger" }
	end
	if isBusy(ua) or isBusy(ub) then
		return { ok = false, msg = "One of them is being stolen!" }
	end

	local resultSpecies: string
	local resultMutation: string? = nil
	local recipe = Kaijus.FindRecipe(a.Species, b.Species)
	if recipe then
		-- les recettes secrètes demandent des ingrédients bien grandis
		local need = recipe.RecipeStage or ProgressionService.FuseMinStage
		if Calc.Stage(a) < need or Calc.Stage(b) < need then
			return { ok = false, msg = ("Secret recipe! Grow both to %s first"):format(string.upper(Growth.Get(need).Name)) }
		end
	end
	if recipe then
		resultSpecies = recipe.Id
		resultMutation = a.Mutation or b.Mutation
	elseif a.Species == b.Species then
		resultSpecies = a.Species
		-- Mutation garantie : tire avec une grosse chance, sinon Or au minimum
		resultMutation = Roll.Mutation(Registry.KaijuService.PersonalLuck(player) * 8) or "Gold"
	else
		local ra, rb = Rarities.Get(a.Rarity), Rarities.Get(b.Rarity)
		local top = if ra.Order >= rb.Order then ra else rb
		local nextR = Rarities.Next(top.Id)
		local rarity = if nextR and math.random() < ProgressionService.FuseUpgradeChance then nextR.Id else top.Id
		resultSpecies = Roll.Species(rarity)
	end

	Registry.KaijuService.RemoveRecord(player, ua)
	Registry.KaijuService.RemoveRecord(player, ub)
	local rec = Registry.KaijuService.AddHatched(player, resultSpecies, resultMutation, 0)
	Registry.RewardService.Track(player, "Fusions", 1)
	Registry.LevelService.AddXp(player, Levels.Xp.Fusion, "Fusion")
	local species = Kaijus.Get(resultSpecies)
	if rec and species then
		Notify.Fx(player, "Fused", { Uid = rec.Uid, Species = resultSpecies, Mutation = resultMutation, Secret = recipe ~= nil })
		if recipe then
			Notify.Feed(("🧪 %s DISCOVERED the SECRET kaiju %s!"):format(player.DisplayName, species.Name), "Rare", Rarities.Get("Secret").Glow)
		end
	end
	return { ok = true, species = resultSpecies, mutation = resultMutation }
end

local function fuseOdds(player: Player, payload: any): Router.Result
	local ua, ub = Router.String(payload.A), Router.String(payload.B)
	local data = DataService.Get(player)
	if not ua or not ub or not data then
		return { ok = false }
	end
	local a = Registry.KaijuService.FindRecord(data, ua)
	local b = Registry.KaijuService.FindRecord(data, ub)
	if not a or not b then
		return { ok = false }
	end
	return { ok = true, odds = ProgressionService.FuseOdds(a, b) }
end

function ProgressionService.Init()
	Router.On("Rebirth", rebirth, 1)
	Router.On("Fuse", fuse, 1)
	Router.On("FuseOdds", fuseOdds, 6)
end

return ProgressionService
