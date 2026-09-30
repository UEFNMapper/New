--!strict
--[[
	OverclockService : mini-jeu de timing à la station d'overclock (étage CPU).

	Anti-triche : la position de l'aiguille est une fonction déterministe du temps
	(Formulas.NeedlePosition). Le client l'affiche, mais c'est le SERVEUR qui calcule
	où elle se trouvait à la réception de "Stop", avec sa propre horloge
	(compensée par le ping du joueur). Un client ne peut donc pas "choisir" son résultat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Economy.Formulas)
local Remotes = require(Shared.Net.Remotes)
local Session = require(script.Parent.Parent.Core.Session)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)

local OverclockService = {}

local TARGET = 0.5
local MISS_COOLDOWN = 20
local overclockRemote: RemoteEvent

local function config(session: Session.Session): (number, number)
	local cfg = GameConfig.Overclock
	local pro = session.Passes.OverclockPro == true
	local duration = cfg.Duration * (if pro then cfg.ProPassDurationMult else 1)
	local cooldown = cfg.Cooldown * (if pro then cfg.ProPassCooldownMult else 1)
	return duration, cooldown
end

function OverclockService.Begin(session: Session.Session)
	local cfg = GameConfig.Overclock
	local now = os.time()
	if session.Data.Zone < cfg.RequiredZone or not session.Data.PoweredOn then
		return
	end
	if session.OverclockUntil > now then
		EconomyService.Notify(session, "Info", "Overclock déjà actif.")
		return
	end
	if session.OverclockCooldownUntil > now then
		EconomyService.Notify(session, "Info", "La station refroidit encore…")
		return
	end
	if PlotService.CurrentFloor(session) ~= cfg.RequiredZone then
		EconomyService.Notify(session, "Error", "Va à la station d'overclock (étage CPU).")
		return
	end
	local start = Workspace:GetServerTimeNow()
	session.OverclockAttemptStart = start
	overclockRemote:FireClient(session.Player, "Begin", {
		Start = start,
		Period = cfg.NeedlePeriod,
		Target = TARGET,
		Good = cfg.GoodHalfWidth,
		Perfect = cfg.PerfectHalfWidth,
		MaxSeconds = cfg.MaxAttemptSeconds,
	})
end

function OverclockService.Stop(session: Session.Session)
	local cfg = GameConfig.Overclock
	local start = session.OverclockAttemptStart
	if start == 0 then
		return
	end
	session.OverclockAttemptStart = 0
	-- Compense le trajet réseau du clic (latence aller estimée, bornée).
	local ping = math.clamp(session.Player:GetNetworkPing(), 0, 0.3)
	local elapsed = Workspace:GetServerTimeNow() - start - ping
	local grade
	if elapsed < 0 or elapsed > cfg.MaxAttemptSeconds then
		grade = "Miss"
	else
		local position = Formulas.NeedlePosition(elapsed, cfg.NeedlePeriod)
		grade = Formulas.OverclockGrade(position, TARGET, cfg.GoodHalfWidth, cfg.PerfectHalfWidth)
	end
	local now = os.time()
	local duration, cooldown = config(session)
	if grade == "Miss" then
		session.OverclockCooldownUntil = now + MISS_COOLDOWN
	else
		session.OverclockMult = if grade == "Perfect" then cfg.PerfectMult else cfg.GoodMult
		session.OverclockUntil = now + duration
		session.OverclockCooldownUntil = now + duration + cooldown
		session.Data.Stats.Overclocks += 1
	end
	overclockRemote:FireClient(
		session.Player,
		"Result",
		{ Grade = grade, Until = session.OverclockUntil, Mult = session.OverclockMult }
	)
	GameEvents.OverclockDone:Fire(session.Player, grade)
	EconomyService.Refresh(session)
end

function OverclockService.Start()
	overclockRemote = Remotes.Get("Overclock")
	RemoteGuard.On("OverclockStart", { Args = {} }, OverclockService.Begin)
	RemoteGuard.On("OverclockStop", { Args = {} }, OverclockService.Stop)
end

return OverclockService
