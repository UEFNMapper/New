--!nonstrict
-- Niveau du joueur : XP gagnée par toutes les actions, récompense à chaque
-- niveau, déblocages (nids, mondes, menus). Jamais remis à zéro.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Levels = require(Shared.Config.Levels)
local Rarities = require(Shared.Config.Rarities)

local Registry = require(script.Parent.Registry)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Notify)

local LevelService = {}

function LevelService.Level(player: Player): number
	local data = DataService.Get(player)
	return if data then data.Level else 1
end

-- Ajoute de l'XP ; gère les passages de niveau (plusieurs d'un coup si besoin).
function LevelService.AddXp(player: Player, amount: number, reason: string?)
	local data = DataService.Get(player)
	if not data or amount <= 0 then
		return
	end
	amount = math.floor(amount + 0.5)
	data.Xp += amount
	local level = Levels.FromXp(data.Xp)
	local before = data.Level
	DataService.Replicate(player, "Xp")
	Notify.Fx(player, "Xp", { Amount = amount, Reason = reason })
	if level <= before then
		return
	end
	data.Level = level
	DataService.Replicate(player, "Level")
	player:SetAttribute("Level", level)
	for l = before + 1, level do
		local reward = Levels.Reward(l)
		DataService.AddGems(player, reward.Gems)
		if reward.Egg then
			Registry.KaijuService.GiveEgg(player, reward.Egg, "LevelUp")
		end
		local unlocks = {}
		for _, u in Levels.UnlocksAt(l) do
			table.insert(unlocks, { Kind = u.Kind, Id = u.Id, Text = u.Text, Icon = u.Icon })
		end
		Notify.Fx(player, "LevelUp", { Level = l, Gems = reward.Gems, Egg = reward.Egg, Unlocks = unlocks })
	end
	Registry.PlotService.RefreshNests(player)
	Registry.KaijuService.RefreshPlayer(player)
	Registry.KaijuService.PlacePending(player)
	Registry.LeaderboardService.Update(player)
end

-- XP d'une éclosion selon la rareté.
function LevelService.HatchXp(rarity: string): number
	return Levels.HatchXp[Rarities.Get(rarity).Id] or 10
end

function LevelService.Init()
	DataService.Loaded:Connect(function(player, data)
		-- Sauvegarde d'avant les niveaux : XP estimée d'après ce que le joueur a déjà fait
		if data.Xp == 0 and (data.TotalEarned or 0) > 0 then
			local species = 0
			for _ in data.Index do
				species += 1
			end
			data.Xp = data.Stats.Hatches * 15 + species * 80 + data.Rebirths * 1500
		end
		-- remet le niveau en cohérence avec l'XP (réglages modifiés entre deux versions)
		data.Level = Levels.FromXp(data.Xp)
		player:SetAttribute("Level", data.Level)
		DataService.Replicate(player, "Level", "Xp")
	end)
end

return LevelService
