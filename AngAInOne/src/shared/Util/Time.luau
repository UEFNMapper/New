--!strict
--[[
	Time : jours et semaines UTC (récompenses quotidiennes, missions, classements),
	et format « chrono » des temps d'ascension.
]]

local Time = {}

-- Jour UTC (nombre de jours depuis 1970).
function Time.DayIndex(unixTime: number): number
	return math.floor(unixTime / 86400)
end

-- Semaine (lundi 00:00 UTC). Le 1er janvier 1970 était un jeudi : décalage de 3 jours.
function Time.WeekIndex(unixTime: number): number
	return math.floor((unixTime / 86400 + 3) / 7)
end

-- Chrono lisible : "4:07.3" (moins d'une heure) ou "1:02:09".
function Time.Clock(seconds: number): string
	local total = math.max(seconds, 0)
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local secs = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, math.floor(secs))
	end
	return string.format("%d:%04.1f", minutes, math.floor(secs * 10) / 10)
end

return table.freeze(Time)
