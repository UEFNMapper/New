--!strict
--[[
	GameEvents : bus d'événements de gameplay côté serveur.
	Les services émettent, d'autres écoutent (quêtes, analytics, tutoriel) :
	ça évite les require circulaires entre services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared").Packages.Signal)

type Signal<T...> = Signal.Signal<T...>

return table.freeze({
	BitsCollected = Signal.new() :: Signal<Player, number>, -- (joueur, montant)
	BitsEarned = Signal.new() :: Signal<Player, number, string>, -- (joueur, montant, source)
	Upgraded = Signal.new() :: Signal<Player, number>, -- (joueur, nombre de niveaux)
	ZoneUnlocked = Signal.new() :: Signal<Player, number>,
	VirusZapped = Signal.new() :: Signal<Player>,
	OverclockDone = Signal.new() :: Signal<Player, string>, -- (joueur, "Perfect" | "Good" | "Miss")
	CapsuleOpened = Signal.new() :: Signal<Player, string>, -- (joueur, capsuleId)
	TowerLiked = Signal.new() :: Signal<Player, number>, -- (joueur, propriétaire)
	Rebooted = Signal.new() :: Signal<Player, number>, -- (joueur, firmware gagné)
	PoweredOn = Signal.new() :: Signal<Player>,
	PlaytimeMinute = Signal.new() :: Signal<Player>,
	StateChanged = Signal.new() :: Signal<Player>, -- demande de recalcul + réplication
	ClientReady = Signal.new() :: Signal<Player>, -- le client a chargé son UI
})
