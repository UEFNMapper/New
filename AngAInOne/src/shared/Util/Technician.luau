--!strict
--[[
	Technician : le rôle du joueur, « Technicien·ne AngAInOne n° XXXX » (docs/AUDIT_V3.md, C1).
	Logique PURE : le numéro est dérivé de l'UserId, stable d'une partie à l'autre (1 à 9999,
	affiché sur 4 chiffres). Les UserId négatifs des joueurs de test de Studio sont acceptés.
]]

local Technician = {}

-- Numéro stable (1..9999) : mélange des chiffres bas et hauts de l'UserId.
function Technician.Number(userId: number): number
	local id = math.abs(math.floor(userId))
	local low = id % 10000
	local high = math.floor(id / 10000) % 100000
	return (low * 7919 + high * 104729 + 427) % 9999 + 1
end

-- « 0427 »
function Technician.Code(userId: number): string
	return string.format("%04d", Technician.Number(userId))
end

-- « Technicien·ne n° 0427 » (badge court : sous le pseudo, dans la barre latérale de l'app)
function Technician.Short(userId: number): string
	return `Technicien·ne n° {Technician.Code(userId)}`
end

-- « Technicien·ne AngAInOne n° 0427 »
function Technician.Title(userId: number): string
	return `Technicien·ne AngAInOne n° {Technician.Code(userId)}`
end

return table.freeze(Technician)
