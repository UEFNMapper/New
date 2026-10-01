--!strict
--[[
	AwardsService : attribue les badges Roblox (Config/Badges) quand un monde est nettoyé ou que LAGZ
	est vaincu. Un ID à 0 est ignoré ; BadgeService est appelé hors du fil du jeu et ses erreurs
	(badge inexistant, service indisponible) ne cassent rien.
]]

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Badges = require(Shared.Config.Badges)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)

local AwardsService = {}

local function award(player: Player, badgeId: number)
	if badgeId <= 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, badgeId) then
				BadgeService:AwardBadge(player.UserId, badgeId)
			end
		end)
		if not ok then
			warn(`[AwardsService] badge {badgeId} pour {player.Name} :`, err)
		end
	end)
end

function AwardsService.Start()
	GameEvents.WorldCleared:Connect(function(player: Player, world: number)
		award(player, Badges.Worlds[world] or 0)
	end)
	GameEvents.Victory:Connect(function(player: Player)
		award(player, Badges.Victory)
	end)
end

return AwardsService
