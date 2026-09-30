-- Mini-assertions pour les specs Lune.
local Expect = {}

local function fmt(v: any): string
	if type(v) == "number" then
		return string.format("%.6g", v)
	end
	return tostring(v)
end

function Expect.equal(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(`{msg or "equal"} : attendu {fmt(expected)}, obtenu {fmt(actual)}`, 2)
	end
end

function Expect.near(actual: number, expected: number, tolerance: number, msg: string?)
	if math.abs(actual - expected) > tolerance then
		error(`{msg or "near"} : attendu {fmt(expected)} ± {fmt(tolerance)}, obtenu {fmt(actual)}`, 2)
	end
end

function Expect.between(actual: number, low: number, high: number, msg: string?)
	if actual < low or actual > high then
		error(`{msg or "between"} : attendu dans [{fmt(low)}, {fmt(high)}], obtenu {fmt(actual)}`, 2)
	end
end

function Expect.truthy(value: any, msg: string?)
	if not value then
		error(msg or "valeur attendue vraie", 2)
	end
end

return Expect
