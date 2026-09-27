--!nonstrict
-- Envoi de messages et d'effets aux clients.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Notify = {}

local notifyEvent = Net.Event("Notify")
local fxEvent = Net.Event("Fx")
local feedEvent = Net.Event("Feed")

-- Toast pour un joueur. kind : Info | Good | Bad | Cash | Gem | Rare
function Notify.Toast(player: Player, text: string, kind: string?)
	notifyEvent:FireClient(player, text, kind or "Info")
end

-- Effet pour un joueur.
function Notify.Fx(player: Player, name: string, args: any?)
	fxEvent:FireClient(player, name, args)
end

-- Effet pour tous.
function Notify.FxAll(name: string, args: any?)
	fxEvent:FireAllClients(name, args)
end

-- Annonce serveur (bandeau + fil d'actualité). style : Heist | Rare | Event | Boss | Purchase
function Notify.Feed(text: string, style: string?, color: Color3?)
	feedEvent:FireAllClients(text, style or "Info", color)
end

function Notify.FeedExcept(except: Player, text: string, style: string?, color: Color3?)
	for _, p in Players:GetPlayers() do
		if p ~= except then
			feedEvent:FireClient(p, text, style or "Info", color)
		end
	end
end

return Notify
