--!strict
--[[
	Modules : les 21 composants améliorables (3 par zone).
	Coûts/production dérivés des formules du GDD :
		coûtBase(z, t) = 10 * 20^z * TIER_COST[t]
		prodBase(z, t) = 0.9 * 15^z * TIER_COST[t]
	avec z = index de zone - 1 et t = 1..3.
	Watts et chaleur par niveau : WATT_BASE * 1.9^z * TIER_LOAD[t] (idem chaleur).
]]

export type ModuleDef = {
	Id: string,
	Zone: number,
	Slot: number,
	Name: string,
	Description: string,
	BaseCost: number,
	BaseProd: number,
	WattsPerLevel: number,
	HeatPerLevel: number,
}

local ZONE_COST_SCALE = 20
local ZONE_PROD_SCALE = 15
local TIER_COST = { 1, 6, 36 }
local TIER_LOAD = { 1, 2, 3 }
local LOAD_GROWTH = 1.9
local WATT_BASE = 4
local HEAT_BASE = 3

local NAMES: { { { string } } } = {
	{
		{ "Cellule VoltCore", "Une cellule d'énergie qui ronronne doucement." },
		{ "Condensateur Titan", "Stocke l'énergie, la relâche en rafales." },
		{ "Transformateur Arc", "Des arcs électriques domptés." },
	},
	{
		{ "Barrette Kryo S", "Mémoire rapide, lumière violette." },
		{ "Barrette Kryo X", "Latence minuscule, débit géant." },
		{ "Kit Kryo Quad", "Quatre canaux, une seule vague RGB." },
	},
	{
		{ "Cellule NAND", "Des millions de bits bien rangés." },
		{ "Contrôleur NovaDrive", "Le chef d'orchestre du stockage." },
		{ "Array NovaDrive RAID", "Vitesse multipliée, données en miroir." },
	},
	{
		{ "Ventilateur Frostbyte", "Un souffle frais et silencieux." },
		{ "Pompe Cryo", "Fait circuler le liquide glacé." },
		{ "Radiateur Glacier", "Des ailettes givrées à perte de vue." },
	},
	{
		{ "Cœur Helion", "Un cœur de calcul brûlant d'énergie." },
		{ "Cluster Helion", "Des dizaines de cœurs en parfaite synchro." },
		{ "Die Helion Ultra", "Le silicium poussé à l'extrême." },
	},
	{
		{ "Shader Prism", "Chaque pixel, une œuvre d'art." },
		{ "Cœurs RT Prism", "La lumière calculée rayon par rayon." },
		{ "Tensor Prism", "L'IA au service de l'image." },
	},
	{
		{ "Neurone ANGA", "Une pensée électrique." },
		{ "Synapse ANGA", "Les idées circulent plus vite." },
		{ "Cortex ANGA", "Ton PC apprend… et rêve." },
	},
}

local list: { ModuleDef } = {}
local byId: { [string]: ModuleDef } = {}

for zoneIndex, zoneNames in NAMES do
	local z = zoneIndex - 1
	for slot, entry in zoneNames do
		local def: ModuleDef = table.freeze({
			Id = `Z{zoneIndex}M{slot}`,
			Zone = zoneIndex,
			Slot = slot,
			Name = entry[1],
			Description = entry[2],
			BaseCost = 10 * ZONE_COST_SCALE ^ z * TIER_COST[slot],
			BaseProd = 0.9 * ZONE_PROD_SCALE ^ z * TIER_COST[slot],
			WattsPerLevel = WATT_BASE * LOAD_GROWTH ^ z * TIER_LOAD[slot],
			HeatPerLevel = HEAT_BASE * LOAD_GROWTH ^ z * TIER_LOAD[slot],
		})
		table.insert(list, def)
		byId[def.Id] = def
	end
end

local Modules = {
	List = table.freeze(list),
	ById = table.freeze(byId),
	PerZone = 3,
}

function Modules.Get(id: string): ModuleDef?
	return byId[id]
end

function Modules.ForZone(zoneIndex: number): { ModuleDef }
	local out = {}
	for _, def in list do
		if def.Zone == zoneIndex then
			table.insert(out, def)
		end
	end
	return out
end

return table.freeze(Modules)
