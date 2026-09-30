--!strict
--[[
	NumberFormat : affichage lisible des grands nombres et des durées (en français).
	1234 -> "1,23K" ; 2.5e12 -> "2,5T" ; 3725 s -> "1 h 02".
]]

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZeros(text: string): string
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- Format compact avec 3 chiffres significatifs et virgule décimale.
function NumberFormat.Compact(value: number): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	local n = math.abs(value)
	if n < 1000 then
		local text = if n < 10 and n ~= math.floor(n)
			then trimZeros(string.format("%.1f", n))
			else tostring(math.floor(n))
		text = string.gsub(text, "%.", ",")
		return (if negative then "-" else "") .. text
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	-- Évite "1000K" après arrondi.
	if scaled >= 999.5 and tier < #SUFFIXES - 1 then
		tier += 1
		scaled = n / 10 ^ (tier * 3)
	end
	local decimals = if scaled < 10 then 2 elseif scaled < 100 then 1 else 0
	local text = trimZeros(string.format(`%.{decimals}f`, scaled))
	text = string.gsub(text, "%.", ",")
	return (if negative then "-" else "") .. text .. SUFFIXES[tier + 1]
end

-- Nombre entier avec séparateurs de milliers (espaces fines), pour les petits montants.
function NumberFormat.Grouped(value: number): string
	local text = tostring(math.floor(math.abs(value)))
	local out = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1 ")))
	out = string.gsub(out, "^ ", "")
	return (if value < 0 then "-" else "") .. out
end

function NumberFormat.Percent(ratio: number): string
	return `{math.floor(ratio * 100 + 0.5)} %`
end

-- Durée : "45 s", "12 min", "1 h 05", "2 j 3 h".
function NumberFormat.Duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s < 60 then
		return `{s} s`
	elseif s < 3600 then
		local m = math.floor(s / 60)
		local rest = s % 60
		return if rest > 0 and m < 10 then `{m} min {rest} s` else `{m} min`
	elseif s < 86400 then
		local h = math.floor(s / 3600)
		local m = math.floor((s % 3600) / 60)
		return string.format("%d h %02d", h, m)
	end
	local d = math.floor(s / 86400)
	local h = math.floor((s % 86400) / 3600)
	return `{d} j {h} h`
end

-- Benchmark affiché en FLOPS (le score est déjà un nombre de "FLOPS").
function NumberFormat.Flops(score: number): string
	local units = { "", "K", "M", "G", "T", "P", "E", "Z", "Y" }
	if score < 1000 then
		return `{math.floor(score)} FLOPS`
	end
	local tier = math.min(math.floor(math.log10(score) / 3), #units - 1)
	local scaled = score / 10 ^ (tier * 3)
	local text = string.gsub(trimZeros(string.format("%.2f", scaled)), "%.", ",")
	return `{text} {units[tier + 1]}FLOPS`
end

return table.freeze(NumberFormat)
