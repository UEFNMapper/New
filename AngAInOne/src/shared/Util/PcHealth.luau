--!strict
--[[
	PcHealth : la « Performance du PC » d'Anga (docs/SCENARIO.md §3), logique PURE.
	- Stats(cleared) : FPS / ping / température selon le nombre de mondes nettoyés
	- Grade(metric, value) : "Good" | "Warn" | "Bad" (couleur du widget)
	- LiveCountdown(stage, cleared) : secondes avant le live (60:00 -> 0 quand on progresse)
]]

local Tower = require(script.Parent.Parent.Config.Tower)

local PcHealth = {}

export type Stats = { Fps: number, Ping: number, Temp: number }

-- Index = mondes nettoyés + 1 (0 à 7).
local TABLE: { Stats } = {
	{ Fps = 3, Ping = 999, Temp = 97 },
	{ Fps = 12, Ping = 650, Temp = 92 },
	{ Fps = 25, Ping = 420, Temp = 88 },
	{ Fps = 40, Ping = 250, Temp = 80 },
	{ Fps = 60, Ping = 120, Temp = 65 },
	{ Fps = 90, Ping = 60, Temp = 55 },
	{ Fps = 120, Ping = 25, Temp = 48 },
	{ Fps = 144, Ping = 8, Temp = 40 },
}

PcHealth.LIVE_SECONDS = 3600 -- « LIVE DANS 60:00 » au tout début

function PcHealth.Stats(cleared: number): Stats
	local index = math.clamp(math.floor(cleared), 0, #TABLE - 1) + 1
	local row = TABLE[index]
	return { Fps = row.Fps, Ping = row.Ping, Temp = row.Temp }
end

function PcHealth.Grade(metric: string, value: number): string
	if metric == "Fps" then
		return if value >= 60 then "Good" elseif value >= 25 then "Warn" else "Bad"
	elseif metric == "Ping" then
		return if value <= 60 then "Good" elseif value <= 250 then "Warn" else "Bad"
	end
	return if value <= 55 then "Good" elseif value <= 80 then "Warn" else "Bad"
end

-- Progression 0..1 de la mission : les mondes nettoyés, plus les étapes du monde en cours
-- (au plus 90 % d'un monde : c'est le terminal qui le termine).
function PcHealth.Progress(stage: number, cleared: number): number
	local worlds = Tower.WORLD_COUNT
	local done = math.clamp(cleared, 0, worlds)
	if done >= worlds then
		return 1
	end
	local inWorld = math.clamp(stage - done * Tower.STAGES_PER_WORLD, 0, Tower.STAGES_PER_WORLD)
	local partial = math.min(inWorld / Tower.STAGES_PER_WORLD, 0.9)
	return math.clamp((done + partial) / worlds, 0, 1)
end

-- Secondes restantes avant le live (arrondies à la seconde).
function PcHealth.LiveCountdown(stage: number, cleared: number): number
	return math.floor(PcHealth.LIVE_SECONDS * (1 - PcHealth.Progress(stage, cleared)) + 0.5)
end

-- « mm:ss » (60:00 au maximum).
function PcHealth.Clock(seconds: number): string
	local total = math.max(math.floor(seconds), 0)
	return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

return table.freeze(PcHealth)
