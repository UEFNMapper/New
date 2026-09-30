--!strict
--[[
	Bonuses : agrège tous les bonus d'un joueur en multiplicateurs.
	Pur : le serveur l'utilise pour faire autorité, le client pour afficher le détail.
]]

local Formulas = require(script.Parent.Formulas)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Nanobots = require(script.Parent.Parent.Config.Nanobots)

local Bonuses = {}

export type Context = {
	Firmware: number,
	FragmentsFound: number,
	EquippedNanobots: { { Id: string, Golden: boolean } },
	HasDoubleBits: boolean,
	IsPremium: boolean,
	InGroup: boolean,
	FriendsInServer: number,
	ServerBoostActive: boolean,
	PersonalBoostActive: boolean,
	OverclockMult: number, -- 1 si inactif
}

export type Breakdown = {
	Total: number,
	WattsReduction: number,
	HeatReduction: number,
	SpeedBonus: number,
	Lines: { { Label: string, Value: number } }, -- pour l'affichage "x2", "+15 %"…
}

function Bonuses.Compute(ctx: Context): Breakdown
	local lines = {}
	local total = 1

	local firmwareMult = Formulas.FirmwareMultiplier(ctx.Firmware, GameConfig.Reboot.FirmwarePerPoint)
	if firmwareMult > 1 then
		table.insert(lines, { Label = "Firmware", Value = firmwareMult })
	end
	total *= firmwareMult

	-- Bonus additifs regroupés : nanobots + fragments + social + premium.
	local additive = 0
	local wattsReduction, heatReduction, speed = 0, 0, 0
	for _, owned in ctx.EquippedNanobots do
		local def = Nanobots.ById[owned.Id]
		if def then
			local value = def.Value * (if owned.Golden then GameConfig.Nanobots.GoldenMult else 1)
			if def.Bonus == "Bits" then
				additive += value
			elseif def.Bonus == "Power" then
				wattsReduction += value
			elseif def.Bonus == "Cooling" then
				heatReduction += value
			elseif def.Bonus == "Speed" then
				speed += value
			end
		end
	end
	if additive > 0 then
		table.insert(lines, { Label = "Nanobots", Value = 1 + additive })
	end

	local fragments = ctx.FragmentsFound * GameConfig.FragmentBonus
	if fragments > 0 then
		table.insert(lines, { Label = "Fragments", Value = 1 + fragments })
	end
	local friends = math.min(ctx.FriendsInServer * GameConfig.FriendBoostPer, GameConfig.FriendBoostMax)
	if friends > 0 then
		table.insert(lines, { Label = "Amis", Value = 1 + friends })
	end
	local premium = if ctx.IsPremium then GameConfig.PremiumBoost else 0
	if premium > 0 then
		table.insert(lines, { Label = "Premium", Value = 1 + premium })
	end
	local group = if ctx.InGroup then GameConfig.GroupBoost else 0
	if group > 0 then
		table.insert(lines, { Label = "Groupe", Value = 1 + group })
	end
	total *= 1 + additive + fragments + friends + premium + group

	if ctx.HasDoubleBits then
		table.insert(lines, { Label = "Pass Bits x2", Value = 2 })
		total *= 2
	end
	if ctx.ServerBoostActive then
		table.insert(lines, { Label = "Server Boost", Value = 2 })
		total *= 2
	end
	if ctx.PersonalBoostActive then
		table.insert(lines, { Label = "Boost x2", Value = 2 })
		total *= 2
	end
	if ctx.OverclockMult > 1 then
		table.insert(lines, { Label = "Overclock", Value = ctx.OverclockMult })
		total *= ctx.OverclockMult
	end

	return {
		Total = total,
		WattsReduction = math.min(wattsReduction, 0.75),
		HeatReduction = math.min(heatReduction, 0.75),
		SpeedBonus = math.min(speed, 16),
		Lines = lines,
	}
end

return table.freeze(Bonuses)
