--!strict
--[[
	GameConfig : constantes de gameplay et d'équilibrage du deathrun.
	La structure de la tour (mondes, étapes, pièges, mini-jeux) est dans Config/Tower.
]]

local GameConfig = {}

-- Nouveau jeu = nouvelle sauvegarde (les données du tycoon ne sont pas reprises).
GameConfig.DataStoreName = "AngAInOne_Deathrun_v1"
GameConfig.GroupId = 0 -- groupe Roblox pour le bonus de groupe (0 = désactivé)

-- Parcours
GameConfig.Run = table.freeze({
	RespawnSeconds = 1.5, -- délai de réapparition après une mort
	MinStageSeconds = 2.5, -- anti-triche : temps minimum entre deux checkpoints
	RespawnHeight = 4, -- hauteur au-dessus du checkpoint à la réapparition
	FallKillBelow = -80, -- sous cette hauteur (lobby compris), on réapparaît
	TeleportCooldown = 1.5, -- boutons « checkpoint » / « lobby »
	CheckpointBits = 2, -- récompense par nouveau checkpoint
	CoinBits = 1, -- récompense par orbe ramassée
	VictoryBits = 250, -- première victoire
	RepeatVictoryBits = 120, -- victoires suivantes
	CoinPickupDistance = 14, -- distance max (studs) entre le joueur et l'orbe
	UsbKeyBits = 25, -- clé USB dorée (chemins difficiles), une seule fois pour toujours
	UsbAllKeysCosmetic = "TrailUsb", -- récompense : toutes les clés USB de la tour
})

-- Mini-jeux
GameConfig.Minigame = table.freeze({
	-- Popup / Defrag : sous la victoire la plus rapide mesurée par les joueurs simulés
	-- (tests/minigames.spec : popup ~6,5 s avec l'astuce des faux boutons, défrag ~3,6 s).
	MinSeconds = table.freeze({ Scan = 8, Firewall = 8, Memory = 5, Dodge = 8, Popup = 5, Defrag = 3 }),
	MaxSeconds = 180, -- au-delà, la partie est considérée abandonnée
	TerminalDistance = 24, -- distance max au terminal pour lancer le mini-jeu
	WorldBits = 20, -- + 5 par monde
	WorldBitsPerWorld = 5,
	ArcadeBits = 10,
	ArcadeCooldown = 90, -- secondes entre deux récompenses d'arcade
})

-- Achats et passes
GameConfig.ShieldSeconds = 30
GameConfig.LowGravityJumpHeight = 10.5 -- hauteur de saut avec les bottes (défaut Roblox : 7.2)
GameConfig.SpeedChipWalkSpeed = 19.5 -- vitesse avec la puce (défaut Roblox : 16)
GameConfig.VipBitsMultiplier = 2
GameConfig.FriendBonusPerFriend = 0.1
GameConfig.FriendBonusMax = 0.3
GameConfig.GroupBonus = 0.05

-- Cadence des remotes (RemoteGuard) : requêtes/s et rafale max par joueur
GameConfig.RateLimits = table.freeze({
	Default = table.freeze({ Rate = 4, Burst = 8 }),
	Death = table.freeze({ Rate = 2, Burst = 4 }),
	Settings = table.freeze({ Rate = 1, Burst = 3 }),
})

-- Récompenses quotidiennes (calendrier de 7 jours, en boucle)
export type DailyReward = { Day: number, Bits: number, Cosmetic: string?, Label: string }
GameConfig.DailyRewards = table.freeze({
	{ Day = 1, Bits = 25, Label = "25 Bits" },
	{ Day = 2, Bits = 40, Label = "40 Bits" },
	{ Day = 3, Bits = 60, Label = "60 Bits" },
	{ Day = 4, Bits = 80, Label = "80 Bits" },
	{ Day = 5, Bits = 100, Label = "100 Bits" },
	{ Day = 6, Bits = 150, Label = "150 Bits" },
	{ Day = 7, Bits = 200, Cosmetic = "TrailCalendar", Label = "Traînée Calendrier + 200 Bits" },
} :: { DailyReward })

return table.freeze(GameConfig)
