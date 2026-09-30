-- Tests de l'ambiance par monde (v4) : presets complets et dans les bornes de Roblox, lobby
-- identique à default.project.json, choix du monde, cohabitation avec le BLACKOUT.
local serde = require("@lune/serde")

local AmbiencePresets = Shim.load("src/shared/Config/AmbiencePresets.luau")
local Tower = Shim.load("src/shared/Config/Tower.luau")

local function rgbOk(value: any, label: string)
	Expect.truthy(type(value) == "table" and #value == 3, `{label} : 3 composantes`)
	for index = 1, 3 do
		Expect.between(value[index], 0, 1, `{label}[{index}]`)
	end
end

-- Le rouge / magenta vif est réservé au danger (même règle que les dangers de la tour).
local function looksLethal(value: any): boolean
	return value[1] >= 0.45 and value[2] <= 0.45
end

local function state(atLobby: boolean, stage: number, cleared: number, started: boolean)
	return { AtLobby = atLobby, Stage = stage, Cleared = cleared, RunStarted = started }
end

return {
	["un preset par monde, lobby compris (0..7)"] = function()
		for world = 0, Tower.WORLD_COUNT do
			local preset = AmbiencePresets.Presets[world]
			Expect.truthy(preset ~= nil, `preset du monde {world}`)
			Expect.equal(AmbiencePresets.Get(world), preset, `Get({world})`)
			Expect.truthy(type(preset.Name) == "string" and #preset.Name > 0, `nom du preset {world}`)
		end
		Expect.equal(AmbiencePresets.Get(-1), AmbiencePresets.Presets[0], "monde inconnu -> lobby")
		Expect.equal(AmbiencePresets.Get(99), AmbiencePresets.Presets[0], "monde inconnu -> lobby")
	end,

	["valeurs dans les bornes (Lighting, Atmosphere, Bloom)"] = function()
		for world = 0, Tower.WORLD_COUNT do
			local p = AmbiencePresets.Presets[world]
			local label = `monde {world}`
			-- Bornes de Roblox, resserrées sur ce qui reste lisible pour un enfant.
			Expect.between(p.Brightness, 1.5, 4, `{label} Brightness`)
			rgbOk(p.Ambient, `{label} Ambient`)
			rgbOk(p.OutdoorAmbient, `{label} OutdoorAmbient`)
			local a = p.Atmosphere
			Expect.between(a.Density, 0.1, 0.4, `{label} Density (pas de brouillard qui cache le parcours)`)
			rgbOk(a.Color, `{label} Atmosphere.Color`)
			rgbOk(a.Decay, `{label} Atmosphere.Decay`)
			Expect.between(a.Glare, 0, 10, `{label} Glare`)
			Expect.between(a.Haze, 0, 3, `{label} Haze`)
			Expect.between(p.Bloom.Intensity, 0, 1, `{label} Bloom.Intensity`)
			Expect.between(p.Bloom.Threshold, 0.8, 4, `{label} Bloom.Threshold`)
		end
	end,

	["lobby = éclairage de default.project.json"] = function()
		local project = serde.decode("json", Fs.readFile("default.project.json"))
		local lighting = project.tree.Lighting
		local lobby = AmbiencePresets.Presets[0]
		local function same(a: { number }, b: { number }, label: string)
			for index = 1, 3 do
				Expect.near(a[index], b[index], 1e-6, label)
			end
		end
		Expect.near(lobby.Brightness, lighting["$properties"].Brightness, 1e-6, "Brightness")
		same(lobby.Ambient, lighting["$properties"].Ambient, "Ambient")
		same(lobby.OutdoorAmbient, lighting["$properties"].OutdoorAmbient, "OutdoorAmbient")
		local atmo = lighting.Atmosphere["$properties"]
		Expect.near(lobby.Atmosphere.Density, atmo.Density, 1e-6, "Density")
		same(lobby.Atmosphere.Color, atmo.Color, "Atmosphere.Color")
		same(lobby.Atmosphere.Decay, atmo.Decay, "Atmosphere.Decay")
		Expect.near(lobby.Atmosphere.Glare, atmo.Glare, 1e-6, "Glare")
		Expect.near(lobby.Atmosphere.Haze, atmo.Haze, 1e-6, "Haze")
		local bloom = lighting.Bloom["$properties"]
		Expect.near(lobby.Bloom.Intensity, bloom.Intensity, 1e-6, "Bloom.Intensity")
		Expect.near(lobby.Bloom.Threshold, bloom.Threshold, 1e-6, "Bloom.Threshold")
		Expect.equal(lobby.Particles, nil, "pas de particules au lobby")
	end,

	["particules : une par monde, discrètes, jamais rouges"] = function()
		local kinds = {}
		for world = 1, Tower.WORLD_COUNT do
			local spec = AmbiencePresets.Presets[world].Particles
			local label = `particules du monde {world}`
			Expect.truthy(spec ~= nil, label)
			Expect.truthy(not kinds[spec.Kind], `{label} : type {spec.Kind} déjà utilisé`)
			kinds[spec.Kind] = true
			Expect.truthy(string.sub(spec.Texture, 1, 10) == "rbxasset:/", `{label} : texture intégrée`)
			Expect.between(spec.Rate, 1, 8, `{label} : débit faible (mobile)`)
			Expect.truthy(spec.Lifetime[1] > 0 and spec.Lifetime[1] <= spec.Lifetime[2], `{label} : Lifetime`)
			Expect.truthy(spec.Lifetime[2] <= 6, `{label} : Lifetime ≤ 6 s`)
			-- Au plus ~50 particules vivantes à la fois.
			Expect.truthy(spec.Rate * spec.Lifetime[2] <= 50, `{label} : particules vivantes`)
			Expect.truthy(spec.Speed[1] >= 0 and spec.Speed[1] <= spec.Speed[2], `{label} : Speed`)
			Expect.between(spec.Size, 0.05, 0.5, `{label} : Size`)
			Expect.between(spec.LightEmission, 0, 1, `{label} : LightEmission`)
			Expect.between(spec.Spread, 0, 180, `{label} : Spread`)
			Expect.truthy(#spec.Acceleration == 3, `{label} : Acceleration`)
			Expect.truthy(#spec.Colors >= 1 and #spec.Colors <= 3, `{label} : 1 à 3 couleurs`)
			for index, color in spec.Colors do
				rgbOk(color, `{label} couleur {index}`)
				Expect.truthy(not looksLethal(color), `{label} couleur {index} : rouge réservé au danger`)
			end
		end
	end,

	["identité des mondes : teinte dominante de l'atmosphère"] = function()
		local presets = AmbiencePresets.Presets
		local function color(world: number): { number }
			return presets[world].Atmosphere.Color
		end
		-- W1 orange chaud : rouge > vert > bleu
		Expect.truthy(color(1)[1] > color(1)[2] and color(1)[2] > color(1)[3], "W1 orange")
		-- W2 violet : bleu dominant, rouge > vert
		Expect.truthy(color(2)[3] > color(2)[1] and color(2)[1] > color(2)[2], "W2 violet")
		-- W3 turquoise : vert et bleu > rouge
		Expect.truthy(color(3)[2] > color(3)[1] and color(3)[3] > color(3)[1], "W3 turquoise")
		-- W4 bleu glacé : bleu dominant, brume la plus dense des mondes
		Expect.truthy(color(4)[3] >= color(4)[2] and color(4)[2] > color(4)[1], "W4 bleu glacé")
		for world = 1, Tower.WORLD_COUNT do
			if world ~= 4 then
				Expect.truthy(
					presets[4].Atmosphere.Haze > presets[world].Atmosphere.Haze,
					`W4 plus brumeux que W{world}`
				)
			end
		end
		-- W5 jaune chaleur : rouge et vert hauts, bleu bas ; le plus éblouissant
		Expect.truthy(color(5)[2] > 0.8 and color(5)[3] < 0.7, "W5 jaune")
		-- W6 vert dominant ; W7 lilas (bleu dominant, clair)
		Expect.truthy(color(6)[2] > color(6)[1] and color(6)[2] > color(6)[3], "W6 vert")
		Expect.truthy(color(7)[3] >= color(7)[1] and color(7)[1] > color(7)[2] and color(7)[2] > 0.7, "W7 lilas")
	end,

	["monde affiché : lobby, départ, RunWorld"] = function()
		Expect.equal(AmbiencePresets.WorldFor(state(true, 0, 0, false)), 0, "lobby")
		Expect.equal(AmbiencePresets.WorldFor(state(true, 12, 2, true)), 0, "retour au lobby en cours de course")
		Expect.equal(AmbiencePresets.WorldFor(state(false, 0, 0, false)), 0, "avant la ligne de départ")
		Expect.equal(AmbiencePresets.WorldFor(state(false, 0, 0, true)), 1, "départ franchi : monde 1")
		for stage = 1, Tower.TOTAL_STAGES do
			local world = Tower.WorldOf(stage)
			for _, cleared in { world - 1, world } do
				local expected = Tower.RunWorld(stage, cleared)
				Expect.equal(
					AmbiencePresets.WorldFor(state(false, stage, cleared, true)),
					expected,
					`étape {stage}, {cleared} nettoyés`
				)
				Expect.between(expected, 1, Tower.WORLD_COUNT, "monde valide")
			end
		end
		-- Terminal du monde 2 nettoyé : on court déjà dans le monde 3.
		Expect.equal(AmbiencePresets.WorldFor(state(false, Tower.TerminalStage(2), 2, true)), 3, "monde suivant")
	end,

	["BLACKOUT : pas de fondu pendant l'annonce, l'incident et la restauration"] = function()
		local grace = AmbiencePresets.BLACKOUT_GRACE
		Expect.truthy(grace >= 1.2, "délai de restauration ≥ clignotement + fondu d'IncidentController")
		Expect.equal(AmbiencePresets.LightingFree("Blackout", math.huge), false, "pendant le BLACKOUT")
		Expect.equal(AmbiencePresets.LightingFree("", 0.2), false, "restauration en cours")
		Expect.equal(AmbiencePresets.LightingFree("", grace + 0.01), true, "après la restauration")
		Expect.equal(AmbiencePresets.LightingFree("", math.huge), true, "aucun BLACKOUT")
		for _, kind in { "Freeze", "Lag", "Popups", "Corruption", "Overheat" } do
			Expect.equal(AmbiencePresets.LightingFree(kind, math.huge), true, `{kind} ne touche pas à l'éclairage`)
		end
		-- Le fondu se termine avant la fin de l'annonce (3 s) : l'éclairage sauvegardé au début
		-- du BLACKOUT est bien celui du monde.
		local Incidents = Shim.load("src/shared/Config/Incidents.luau")
		Expect.truthy(AmbiencePresets.TWEEN < Incidents.WarningSeconds, "fondu plus court que l'annonce")
	end,
}
