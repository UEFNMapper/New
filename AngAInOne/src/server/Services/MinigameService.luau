--!strict
--[[
	MinigameService : terminaux antivirus (fin de chaque monde) et borne d'arcade du lobby.
	Les mini-jeux se jouent côté client (2D) ; le serveur valide ce qui est vérifiable :
	- le joueur est au bon checkpoint (salle du terminal) et près du terminal
	- le monde précédent est nettoyé, la partie a été ouverte par MinigameStart
	- monde 7 : le bouclier de LAGZ est détruit (BossService, phase 3 du combat final)
	- la durée est plausible (minimum par type de jeu, maximum global)
	Réussite -> le portail du monde s'ouvre (ProgressService.ClearWorld) + Bits.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Tower = require(Shared.Config.Tower)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local Telemetry = require(script.Parent.Parent.Core.Telemetry)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local ProgressService = require(script.Parent.ProgressService)
local BossService = require(script.Parent.BossService)

local MinigameService = {}

local CFG = GameConfig.Minigame

local function durationOk(kind: string, startedAt: number): boolean
	local elapsed = os.clock() - startedAt
	local minimum = (CFG.MinSeconds :: any)[kind] or 8
	return elapsed >= minimum and elapsed <= CFG.MaxSeconds
end

local function onStart(session: Session.Session, world: number)
	local data = session.Data
	local def = Tower.Worlds[world]
	if not def or data.Stage ~= Tower.TerminalStage(world) or data.Cleared ~= world - 1 then
		return
	end
	local terminal = ProgressService.TerminalPosition(world)
	if not terminal or RemoteGuard.DistanceTo(session.Player, terminal) > CFG.TerminalDistance then
		return
	end
	-- Monde 7 : le terminal final (phase 3 du combat) n'ouvre qu'une fois le bouclier de LAGZ détruit.
	if world == Tower.WORLD_COUNT and not BossService.TerminalOpen(session) then
		Wallet.Notify(
			session,
			"Info",
			"Le bouclier de LAGZ protège ce terminal : branche d'abord les 3 prises antivirus !"
		)
		return
	end
	session.Minigame = { World = world, Kind = def.Minigame, StartedAt = os.clock() }
end

local function onEnd(session: Session.Session, world: number, success: boolean, score: number)
	local game_ = session.Minigame
	if not game_ or game_.World ~= world or world == 0 then
		return
	end
	session.Minigame = nil
	if not success then
		Telemetry.Custom(session.Player, `MinigameFail_{game_.Kind}`, world)
		return
	end
	if not durationOk(game_.Kind, game_.StartedAt) then
		Wallet.Notify(session, "Info", "Partie non validée : relance le terminal pour réessayer.")
		return
	end
	-- Monde 7 : le combat doit toujours être gagné (ex. partie ouverte, puis Lobby / Reprendre).
	if world == Tower.WORLD_COUNT and not BossService.TerminalOpen(session) then
		return
	end
	if not ProgressService.ClearWorld(session, world) then
		return -- déjà nettoyé (ex. étape passée pendant la partie) : pas de double récompense
	end
	session.Data.MinigamesWon += 1
	local bits = Wallet.Add(session, CFG.WorldBits + CFG.WorldBitsPerWorld * world, "Minigame", true)
	Wallet.Fx(session, "WorldCleared", { World = world, Bits = bits, Score = score })
	Telemetry.Custom(session.Player, `MinigameWin_{game_.Kind}`, world)
end

local function onArcadeStart(session: Session.Session, kind: string)
	if not ProgressService.NearArcade(session, CFG.TerminalDistance) then
		Wallet.Notify(session, "Info", "Va jouer à la borne d'arcade du lobby pour gagner des Bits !")
		return
	end
	session.Minigame = { World = 0, Kind = kind, StartedAt = os.clock() }
end

local function onArcadeEnd(session: Session.Session, kind: string, success: boolean, _score: number)
	local game_ = session.Minigame
	if not game_ or game_.World ~= 0 or game_.Kind ~= kind then
		return
	end
	session.Minigame = nil
	if not success or not durationOk(kind, game_.StartedAt) then
		return
	end
	GameEvents.ArcadeWon:Fire(session.Player)
	local now = os.time()
	if now - session.Data.ArcadeRewardAt < CFG.ArcadeCooldown then
		Wallet.Notify(session, "Info", "Bravo ! Prochaine récompense d'arcade dans un instant.")
		return
	end
	session.Data.ArcadeRewardAt = now
	local bits = Wallet.Add(session, CFG.ArcadeBits, "Arcade", true)
	Wallet.Fx(session, "Reward", { Bits = bits })
end

function MinigameService.Start()
	local kinds = Tower.MinigameKinds
	RemoteGuard.On("MinigameStart", { Args = { RemoteGuard.Int(1, Tower.WORLD_COUNT) } }, onStart)
	RemoteGuard.On("MinigameEnd", {
		Args = { RemoteGuard.Int(1, Tower.WORLD_COUNT), RemoteGuard.Bool(), RemoteGuard.Number(0, 1e6) },
	}, onEnd)
	RemoteGuard.On("ArcadeStart", { Args = { RemoteGuard.OneOf(kinds) } }, onArcadeStart)
	RemoteGuard.On("ArcadeEnd", {
		Args = { RemoteGuard.OneOf(kinds), RemoteGuard.Bool(), RemoteGuard.Number(0, 1e6) },
	}, onArcadeEnd)
	Session.Removing:Connect(function(session: Session.Session)
		session.Minigame = nil
	end)
end

return MinigameService
