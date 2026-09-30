--!strict
--[[
	GameEvents : bus d'événements de gameplay côté serveur.
	Les services émettent, d'autres écoutent (missions, analytics, classements) :
	ça évite les require circulaires entre services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared").Packages.Signal)

type Signal<T...> = Signal.Signal<T...>

return table.freeze({
	CheckpointReached = Signal.new() :: Signal<Player, number>, -- (joueur, étape)
	CoinCollected = Signal.new() :: Signal<Player>,
	WorldCleared = Signal.new() :: Signal<Player, number>, -- (joueur, monde) mini-jeu réussi
	Victory = Signal.new() :: Signal<Player, number>, -- (joueur, temps en secondes)
	ArcadeWon = Signal.new() :: Signal<Player>,
	Died = Signal.new() :: Signal<Player>,
	PlaytimeMinute = Signal.new() :: Signal<Player>,
	StateChanged = Signal.new() :: Signal<Player>, -- demande de réplication de l'état
	ClientReady = Signal.new() :: Signal<Player>, -- le client a chargé son UI
	PassesLoaded = Signal.new() :: Signal<Player>, -- Game Passes vérifiés pour ce joueur
})
