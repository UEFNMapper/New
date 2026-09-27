--!strict
-- Roster des kaijus. Chaque espèce est décrite par des données : le KaijuBuilder
-- (partagé client/serveur) en fabrique le modèle 3D à partir de l'archétype,
-- des couleurs et des accessoires.

export type Species = {
	Id: string,
	Name: string,
	Rarity: string,
	Income: number, -- $/s au stade Bébé, sans multiplicateurs
	Price: number, -- prix du météore (0 = non achetable)
	Archetype: string, -- Rex | Quad | Serpent | Bird | Blob | Crab | Food | Mech | Squid
	Shape: string?, -- variante pour Food (Toast, Croissant, Kebab, Pizza, Donut, Sushi)
	Primary: Color3,
	Secondary: Color3,
	Accent: Color3,
	Accessories: { string },
	Flavor: string,
	Recipe: { string }?, -- pour les Secrets : les deux espèces à fusionner
	Hint: string?,
}

local rgb = Color3.fromRGB

local function S(
	id: string,
	name: string,
	rarity: string,
	income: number,
	payback: number,
	archetype: string,
	primary: Color3,
	secondary: Color3,
	accent: Color3,
	accessories: { string },
	flavor: string,
	shape: string?
): Species
	return {
		Id = id,
		Name = name,
		Rarity = rarity,
		Income = income,
		Price = math.floor(income * payback),
		Archetype = archetype,
		Shape = shape,
		Primary = primary,
		Secondary = secondary,
		Accent = accent,
		Accessories = accessories,
		Flavor = flavor,
	}
end

local List: { Species } = {
	-- COMMON ---------------------------------------------------------------
	S("Toastzilla", "Toastzilla", "Common", 1, 30, "Food", rgb(222, 164, 92), rgb(250, 226, 170), rgb(120, 70, 40), {}, "Slightly burnt. Extremely angry.", "Toast"),
	S("Gloop", "Gloop", "Common", 1.5, 30, "Blob", rgb(120, 230, 120), rgb(200, 255, 190), rgb(40, 120, 60), { "Antenna" }, "Eats everything. Mostly socks."),
	S("Pinchy", "Pinchy", "Common", 2, 30, "Crab", rgb(255, 110, 80), rgb(255, 190, 150), rgb(160, 40, 30), {}, "Pinches first, asks never."),
	S("DinoNugget", "Dino Nugget", "Common", 2.5, 30, "Rex", rgb(230, 170, 70), rgb(250, 215, 130), rgb(170, 100, 30), {}, "Crispy outside, fierce inside."),
	S("Wormzy", "Wormzy", "Common", 3, 30, "Serpent", rgb(255, 140, 190), rgb(255, 210, 230), rgb(200, 70, 120), { "Antenna" }, "Wiggles menacingly."),
	S("Pigeonator", "Pigeonator", "Common", 3.5, 30, "Bird", rgb(150, 160, 180), rgb(200, 205, 220), rgb(90, 200, 150), {}, "Has seen things on the rooftops."),

	-- RARE -----------------------------------------------------------------
	S("Sharkapillar", "Sharkapillar", "Rare", 6, 60, "Serpent", rgb(90, 130, 170), rgb(230, 235, 240), rgb(40, 60, 90), { "Fin", "Teeth" }, "Half shark. Half caterpillar. All bite."),
	S("Croissantosaurus", "Croissantosaurus", "Rare", 7, 60, "Food", rgb(230, 160, 60), rgb(250, 210, 120), rgb(150, 90, 30), { "Spikes" }, "Flaky. Buttery. Apex predator.", "Croissant"),
	S("Frostodon", "Frostodon", "Rare", 8, 60, "Quad", rgb(150, 220, 255), rgb(235, 250, 255), rgb(60, 140, 220), { "Spikes", "Horn" }, "Leaves a trail of tiny snowflakes."),
	S("ThunderSquid", "Thunder Squid", "Rare", 9, 60, "Squid", rgb(255, 225, 60), rgb(255, 245, 170), rgb(120, 90, 255), { "Bolt" }, "Charges up during storms."),
	S("Kebabzilla", "Kebabzilla", "Rare", 10, 60, "Food", rgb(190, 110, 60), rgb(240, 220, 170), rgb(80, 170, 60), {}, "Spins on its own axis. Constantly.", "Kebab"),
	S("BeepBoop", "Beep Boop", "Rare", 12, 60, "Mech", rgb(200, 205, 215), rgb(120, 130, 150), rgb(60, 220, 255), { "Antenna", "Visor" }, "Runs on vibes and AA batteries."),

	-- EPIC -----------------------------------------------------------------
	S("SushiRex", "Sushi Rex", "Epic", 30, 120, "Rex", rgb(250, 250, 245), rgb(255, 120, 80), rgb(30, 60, 40), { "Nori" }, "Fresh catch of the day. Bites back."),
	S("Robotank", "Robotank", "Epic", 35, 120, "Mech", rgb(90, 120, 80), rgb(60, 70, 60), rgb(255, 80, 60), { "Cannon", "Visor" }, "Treads? Legs? Why not both."),
	S("Magmadillo", "Magmadillo", "Epic", 40, 120, "Quad", rgb(60, 40, 40), rgb(255, 110, 30), rgb(255, 200, 60), { "Shell", "Glow" }, "Warm hugs. Very warm. Too warm."),
	S("Bananadon", "Bananadon", "Epic", 45, 120, "Rex", rgb(255, 225, 70), rgb(255, 245, 180), rgb(110, 80, 30), { "Spikes" }, "Slippery when defeated."),
	S("Crabzooka", "Crabzooka", "Epic", 50, 120, "Crab", rgb(80, 90, 110), rgb(255, 150, 60), rgb(255, 60, 60), { "Cannon" }, "Fires bubbles at 300 km/h."),
	S("Pizzapocalypse", "Pizzapocalypse", "Epic", 60, 120, "Food", rgb(255, 190, 70), rgb(255, 240, 150), rgb(210, 50, 40), { "Cheese" }, "The final slice.", "Pizza"),

	-- LEGENDARY ------------------------------------------------------------
	S("Rexplosion", "Rexplosion", "Legendary", 180, 240, "Rex", rgb(60, 110, 70), rgb(120, 170, 110), rgb(90, 255, 200), { "Spikes", "Glow" }, "Its roar has been measured on the Richter scale."),
	S("KawaiiKraken", "Kawaii Kraken", "Legendary", 200, 240, "Squid", rgb(255, 150, 210), rgb(255, 220, 240), rgb(255, 90, 160), { "Bow", "Blush" }, "Adorable. Has sunk 400 ships."),
	S("ThunderGoose", "Thunder Goose", "Legendary", 220, 240, "Bird", rgb(250, 250, 255), rgb(255, 170, 40), rgb(80, 180, 255), { "Bolt", "Glow" }, "HONK. (Thunder sounds.)"),
	S("Donutron", "Donutron", "Legendary", 250, 240, "Food", rgb(210, 140, 80), rgb(255, 120, 190), rgb(120, 230, 255), { "Sprinkles", "Visor" }, "Part donut, part war machine.", "Donut"),
	S("Drakonda", "Drakonda", "Legendary", 280, 240, "Serpent", rgb(170, 30, 50), rgb(255, 190, 80), rgb(255, 120, 30), { "Wings", "Horn", "Glow" }, "A dragon that refused to grow legs."),

	-- MYTHIC ---------------------------------------------------------------
	S("Kaijumbo", "Kaijumbo", "Mythic", 1000, 480, "Quad", rgb(140, 150, 200), rgb(200, 210, 240), rgb(255, 230, 120), { "Tusks", "Crown" }, "Never forgets who stole from it."),
	S("Nebulodon", "Nebulodon", "Mythic", 1200, 480, "Rex", rgb(40, 30, 90), rgb(120, 80, 220), rgb(255, 255, 255), { "Spikes", "Glow", "Stars" }, "Made of 30% dinosaur, 70% space."),
	S("Hydroblob", "Hydroblob", "Mythic", 1400, 480, "Blob", rgb(40, 170, 255), rgb(170, 230, 255), rgb(0, 90, 200), { "Crown", "Glow" }, "Three blobs in a trench coat."),
	S("Crabageddon", "Crabageddon", "Mythic", 1600, 480, "Crab", rgb(40, 20, 30), rgb(255, 60, 60), rgb(255, 200, 40), { "Spikes", "Glow", "Crown" }, "The end is near. And pinchy."),

	-- CELESTIAL ------------------------------------------------------------
	S("SolarisRex", "Solaris Rex", "Celestial", 7000, 900, "Rex", rgb(255, 170, 30), rgb(255, 240, 150), rgb(255, 90, 20), { "Halo", "Glow", "Spikes" }, "It rises in the east every morning."),
	S("LunarSquid", "Lunar Squid", "Celestial", 8000, 900, "Squid", rgb(200, 210, 255), rgb(250, 250, 255), rgb(120, 140, 255), { "Halo", "Glow", "Stars" }, "Controls the tides. And your wifi."),
	S("CosmoGoose", "Cosmo Goose", "Celestial", 9000, 900, "Bird", rgb(30, 20, 60), rgb(90, 60, 200), rgb(80, 255, 230), { "Halo", "Glow", "Stars", "Wings" }, "Honks in 11 dimensions."),
}

-- SECRETS : uniquement par fusion (recette) ----------------------------------
local function Secret(
	id: string,
	name: string,
	income: number,
	archetype: string,
	primary: Color3,
	secondary: Color3,
	accent: Color3,
	accessories: { string },
	flavor: string,
	recipe: { string },
	hint: string,
	shape: string?
)
	local s = S(id, name, "Secret", income, 250, archetype, primary, secondary, accent, accessories, flavor, shape)
	s.Price = 0
	s.Recipe = recipe
	s.Hint = hint
	table.insert(List, s)
end

Secret("SharktoastSupreme", "Sharktoast Supreme", 40000, "Food", rgb(90, 130, 170), rgb(222, 164, 92), rgb(255, 255, 255), { "Fin", "Teeth", "Glow" }, "Breakfast has teeth now.", { "Toastzilla", "Sharkapillar" }, "Fuse bread with a fin.", "Toast")
Secret("CroissantKraken", "Croissant Kraken", 50000, "Squid", rgb(230, 160, 60), rgb(250, 210, 120), rgb(255, 90, 160), { "Crown", "Glow" }, "Unleash the pastry.", { "Croissantosaurus", "KawaiiKraken" }, "A flaky friend meets the deep.")
Secret("NuclearPigeon", "Nuclear Pigeon", 60000, "Bird", rgb(90, 255, 90), rgb(40, 80, 40), rgb(255, 255, 80), { "Glow", "Bolt", "Crown" }, "Do NOT feed it bread.", { "Pigeonator", "ThunderGoose" }, "Two birds, one storm.")
Secret("OmegaSushiMech", "Omega Sushi Mech", 70000, "Mech", rgb(250, 250, 245), rgb(255, 120, 80), rgb(60, 220, 255), { "Cannon", "Visor", "Nori", "Glow" }, "Sashimi-grade firepower.", { "SushiRex", "Robotank" }, "Raw fish, heavy metal.")
Secret("InfiniteBlob", "The Infinite Blob", 80000, "Blob", rgb(255, 255, 255), rgb(200, 120, 255), rgb(80, 255, 230), { "Halo", "Glow", "Stars" }, "It's blobs all the way down.", { "Gloop", "Hydroblob" }, "The smallest and the biggest goo.")
Secret("KingKaiju", "KING KAIJU", 120000, "Rex", rgb(20, 20, 30), rgb(255, 200, 40), rgb(255, 60, 60), { "Crown", "Spikes", "Glow", "Halo" }, "Bow before the king.", { "Rexplosion", "SolarisRex" }, "Two tyrants. One throne.")

local ById: { [string]: Species } = {}
local ByRarity: { [string]: { Species } } = {}
for index, s in List do
	assert(ById[s.Id] == nil, "Kaiju en double : " .. s.Id)
	ById[s.Id] = s
	ByRarity[s.Rarity] = ByRarity[s.Rarity] or {}
	table.insert(ByRarity[s.Rarity], s)
	;(s :: any).Index = index
end

local Kaijus = {
	List = List,
	ById = ById,
	ByRarity = ByRarity,
}

function Kaijus.Get(id: string): Species?
	return ById[id]
end

-- Renvoie l'espèce secrète produite par la fusion de a et b (dans n'importe quel ordre).
function Kaijus.FindRecipe(a: string, b: string): Species?
	for _, s in List do
		local r = s.Recipe
		if r and ((r[1] == a and r[2] == b) or (r[1] == b and r[2] == a)) then
			return s
		end
	end
	return nil
end

return Kaijus
