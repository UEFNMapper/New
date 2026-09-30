-- Tests de la géométrie du PC géant (WorldLayout) : zones, portails, routage du guide.
local WorldLayout = Shim.load("src/shared/Config/WorldLayout.luau")
local Zones = Shim.load("src/shared/Config/Zones.luau")
local Branding = Shim.load("src/shared/Config/Branding.luau")

local function inward(layout: any): any
	local delta = layout.Spawn - layout.Gate
	return Vector3.new(delta.X, 0, delta.Z).Unit
end

-- Zone atteinte en franchissant `gate` depuis la zone `from`.
local function cross(from: number, gate: any): number
	if from > 0 and WorldLayout.Zones[from].Gate == gate then
		return WorldLayout.Zones[from].Parent
	end
	for _, layout in WorldLayout.Zones do
		if layout.Gate == gate and layout.Parent == from then
			return layout.Zone
		end
	end
	error(`portail {gate} inaccessible depuis la zone {from}`)
end

return {
	["une zone par config, dans l'ordre"] = function()
		Expect.equal(#WorldLayout.Zones, #Zones)
		for index, layout in WorldLayout.Zones do
			Expect.equal(layout.Zone, index, "index de zone")
		end
	end,
	["les points d'arrivée sont dans leur zone"] = function()
		Expect.equal(WorldLayout.ZoneAt(WorldLayout.HubSpawn), 0, "spawn du hub")
		for _, layout in WorldLayout.Zones do
			Expect.equal(WorldLayout.ZoneAt(layout.Spawn), layout.Zone, `spawn de la zone {layout.Zone}`)
		end
		Expect.equal(WorldLayout.ZoneAt(Vector3.new(5000, 0, 0)), -1, "hors carte")
	end,
	["chaque portail relie la zone à sa parente"] = function()
		for _, layout in WorldLayout.Zones do
			local n = inward(layout)
			Expect.equal(WorldLayout.ZoneAt(layout.Gate + n * 6), layout.Zone, `côté zone du portail {layout.Zone}`)
			Expect.equal(
				WorldLayout.ZoneAt(layout.Gate - n * 6),
				layout.Parent,
				`côté parent du portail {layout.Zone}`
			)
			-- Déblocage séquentiel : la zone parente est toujours débloquée avant.
			Expect.truthy(layout.Parent < layout.Zone, `parent de {layout.Zone}`)
		end
	end,
	["le guide mène de n'importe quelle zone à n'importe quelle autre"] = function()
		for from = 0, #Zones do
			for to = 0, #Zones do
				local current, steps = from, 0
				while current ~= to do
					local gate = WorldLayout.NextGate(current, to)
					Expect.truthy(gate ~= nil, `pas de portail de {current} vers {to}`)
					current = cross(current, gate)
					steps += 1
					Expect.truthy(steps <= 6, `boucle de routage {from} -> {to}`)
				end
				Expect.equal(WorldLayout.NextGate(to, to), nil, "déjà arrivé")
			end
		end
	end,
	["chaque zone a sa section de l'app AngAInOne"] = function()
		local seen = {}
		for _, zone in Zones do
			Expect.truthy(type(zone.AppSection) == "string" and #zone.AppSection > 0, `section de {zone.Id}`)
			Expect.truthy(not seen[zone.AppSection], `section en double : {zone.AppSection}`)
			seen[zone.AppSection] = true
			Expect.truthy(
				table.find(Branding.PartnerApp.Sidebar, zone.AppSection) ~= nil,
				`{zone.AppSection} dans la barre latérale`
			)
		end
	end,
}
