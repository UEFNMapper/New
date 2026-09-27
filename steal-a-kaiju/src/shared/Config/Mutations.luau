--!strict
-- Mutations : tirées à l'éclosion (chances de base, boostées par la chance et
-- les événements), ou appliquées par les événements mondiaux.

export type Mutation = {
	Id: string,
	Name: string,
	Mult: number,
	Chance: number, -- chance de base à l'éclosion (0..1), 0 = uniquement événement/fusion
	Color: Color3,
	TextColor: Color3,
	Material: Enum.Material?,
	Tint: Color3?, -- teinte appliquée à tout le modèle
	Reflectance: number?,
	Particles: string?, -- clé d'effet visuel côté client
	Order: number,
}

local rgb = Color3.fromRGB

local List: { Mutation } = {
	{ Id = "Gold", Name = "Gold", Mult = 2, Chance = 0.04, Color = rgb(255, 200, 40), TextColor = rgb(255, 225, 90), Material = Enum.Material.Foil, Tint = rgb(255, 196, 40), Reflectance = 0.25, Particles = "Sparkle", Order = 1 },
	{ Id = "Diamond", Name = "Diamond", Mult = 3, Chance = 0.012, Color = rgb(120, 230, 255), TextColor = rgb(170, 245, 255), Material = Enum.Material.Glass, Tint = rgb(150, 235, 255), Reflectance = 0.3, Particles = "Shine", Order = 2 },
	{ Id = "Blood", Name = "Blood Moon", Mult = 4, Chance = 0, Color = rgb(200, 20, 40), TextColor = rgb(255, 70, 80), Material = Enum.Material.SmoothPlastic, Tint = rgb(150, 15, 30), Particles = "Drip", Order = 3 },
	{ Id = "Rainbow", Name = "Rainbow", Mult = 5, Chance = 0.004, Color = rgb(255, 90, 200), TextColor = rgb(255, 255, 255), Material = Enum.Material.SmoothPlastic, Particles = "Rainbow", Order = 4 },
	{ Id = "Radioactive", Name = "Radioactive", Mult = 6, Chance = 0, Color = rgb(110, 255, 60), TextColor = rgb(160, 255, 110), Material = Enum.Material.Neon, Tint = rgb(90, 255, 60), Particles = "Toxic", Order = 5 },
	{ Id = "Galaxy", Name = "Galaxy", Mult = 8, Chance = 0, Color = rgb(120, 60, 255), TextColor = rgb(200, 170, 255), Material = Enum.Material.SmoothPlastic, Tint = rgb(45, 25, 110), Particles = "Stars", Order = 6 },
	{ Id = "Shadow", Name = "Shadow", Mult = 10, Chance = 0, Color = rgb(30, 10, 50), TextColor = rgb(190, 120, 255), Material = Enum.Material.SmoothPlastic, Tint = rgb(18, 12, 28), Particles = "Void", Order = 7 },
}

local ById: { [string]: Mutation } = {}
for _, m in List do
	ById[m.Id] = m
end

local Mutations = {
	List = List,
	ById = ById,
}

function Mutations.Get(id: string?): Mutation?
	if id == nil or id == "" then
		return nil
	end
	return ById[id]
end

function Mutations.Mult(id: string?): number
	local m = Mutations.Get(id)
	return if m then m.Mult else 1
end

return Mutations
