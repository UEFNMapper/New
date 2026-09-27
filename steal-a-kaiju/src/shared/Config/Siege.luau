--!strict
-- Défense de l'île (« Wild Kaijus Invade! ») : tous les réglages, le chemin des
-- envahisseurs et la composition des vagues. Partagé client/serveur : les deux
-- côtés calculent la même position à partir du temps (rien n'est envoyé par image).
--
-- Coordonnées LOCALES de l'île (voir Config/Layout et MapBuilder.buildPlot) :
--   portail (0,-58), clôture de la cour des nids x ∈ [-48,48], z ∈ [-34,42],
--   nids x ∈ {-36,-18,0,18,36} × z ∈ {-26,-6,14,34} (rayon 6), réacteur (0,50),
--   bouton de verrouillage (-30,50), pad du météore perso (30,50).
-- La clôture n'a pas d'ouverture : les envahisseurs la franchissent d'un bond
-- (« Hops ») dans les couloirs libres entre les nids et les murs (x = ±44,5).

local Siege = {}

----------------------------------------------------------------------------
-- Rythme
----------------------------------------------------------------------------

Siege.Countdown = 150 -- s entre deux vagues (ne s'écoule que chez soi)
Siege.FirstCountdown = 45 -- première vague après la fin du tutoriel
Siege.JoinCountdown = 90 -- à la connexion (joueur qui a déjà joué)
Siege.StartNowBonus = 0.1 -- +10 % de récompense avec « START NOW »
Siege.IslandMargin = 6 -- marge (studs) autour de l'île pour « être chez soi »
Siege.AfkSeconds = 120 -- sans bouger : compte à rebours en pause
Siege.Tick = 0.25 -- pas de simulation serveur (tirs, dégâts)
Siege.SpawnGap = 1.2 -- s entre deux apparitions
Siege.FailRatio = 0.5 -- à partir de 50 % de fuites, la vague est ratée
Siege.AudienceRadius = 220 -- studs : joueurs qui reçoivent les tirs d'une île

----------------------------------------------------------------------------
-- Chemins (coordonnées locales x, z)
----------------------------------------------------------------------------

export type Path = {
	Points: { Vector3 },
	Cum: { number }, -- distance cumulée à chaque point
	Length: number,
	Hops: { number }, -- distances où l'on franchit la clôture
}

local LANE = 44.5 -- couloir entre la colonne de nids extérieure (bord 42) et la clôture (48)
local BACK = 43.4 -- entre la clôture arrière (42) et le bouton de verrouillage (45)
local FENCE_Z = { -34, 42 }

local function build(points: { { number } }): Path
	local pts: { Vector3 } = {}
	for _, p in points do
		table.insert(pts, Vector3.new(p[1], 0, p[2]))
	end
	local cum = { 0 }
	local hops: { number } = {}
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local len = (b - a).Magnitude
		for _, z in FENCE_Z do
			if (a.Z - z) * (b.Z - z) < 0 then
				table.insert(hops, cum[i - 1] + len * (z - a.Z) / (b.Z - a.Z))
			end
		end
		cum[i] = cum[i - 1] + len
	end
	return { Points = pts, Cum = cum, Length = cum[#cum], Hops = hops }
end

-- Aller : du portail au réacteur, en serpentant entre les rangées de nids pour
-- que chaque nid ait sa chance de tirer (couloirs z = -16, 4, 24).
Siege.In = build({
	{ 0, -54 }, -- sortie du portail
	{ 0, -40 },
	{ LANE, -40 },
	{ LANE, -16 }, -- bond par-dessus la clôture avant (z = -34)
	{ -LANE, -16 },
	{ -LANE, 4 },
	{ LANE, 4 },
	{ LANE, 24 },
	{ -LANE, 24 },
	{ -LANE, BACK }, -- bond par-dessus la clôture arrière (z = 42)
	{ -7, BACK }, -- au pied du réacteur
})

-- Fuite avec un sac de cash : retour au portail par le couloir de gauche.
Siege.Out = build({
	{ -7, BACK },
	{ -LANE, BACK },
	{ -LANE, -40 }, -- deux bonds (clôtures arrière puis avant)
	{ 0, -40 },
	{ 0, -54 },
})

-- Vague d'entraînement : chemin court par l'allée entre les colonnes de nids
-- x = -18 et x = 0, qui passe à portée du tout premier nid (0, 34). Arrivés au
-- réacteur, ils rebroussent chemin jusqu'à (-9, 14) puis repartent : impossible de perdre.
Siege.TutorialPath = build({
	{ 0, -54 },
	{ 0, -40 },
	{ -9, -40 },
	{ -9, 14 }, -- bond par-dessus la clôture avant
	{ -9, BACK }, -- bond par-dessus la clôture arrière
	{ -7, BACK },
})
Siege.TutorialBounce = Siege.TutorialPath.Cum[4]

Siege.HopHeight = 3.5
Siege.HopHalfWidth = 2.5

function Siege.GetPath(name: string): Path
	if name == "Out" then
		return Siege.Out
	elseif name == "Tutorial" then
		return Siege.TutorialPath
	end
	return Siege.In
end

-- Position locale (x, hauteur de bond, z) et direction de marche à la distance d.
function Siege.PathAt(path: Path, d: number): (Vector3, Vector3)
	local dist = math.clamp(d, 0, path.Length)
	local pts, cum = path.Points, path.Cum
	local i = 2
	while i < #pts and cum[i] < dist do
		i += 1
	end
	local a, b = pts[i - 1], pts[i]
	local seg = cum[i] - cum[i - 1]
	local t = if seg > 0 then (dist - cum[i - 1]) / seg else 0
	local pos = a:Lerp(b, math.clamp(t, 0, 1))
	local y = 0
	for _, h in path.Hops do
		local k = math.abs(dist - h) / Siege.HopHalfWidth
		if k < 1 then
			y = math.max(y, Siege.HopHeight * (1 - k * k))
		end
	end
	local dir = if seg > 0 then (b - a) / seg else Vector3.new(0, 0, 1)
	return Vector3.new(pos.X, y, pos.Z), dir
end

-- Distance parcourue à l'instant `now` (attributs D0, T0, Speed, Dir de l'ancre).
function Siege.Distance(path: Path, d0: number, t0: number, speed: number, dir: number, now: number): number
	return math.clamp(d0 + dir * speed * math.max(0, now - t0), 0, path.Length)
end

----------------------------------------------------------------------------
-- Envahisseurs
----------------------------------------------------------------------------

export type InvaderType = {
	Id: string,
	Name: string,
	HP: number, -- multiplicateur des PV de base de la vague
	Speed: number, -- studs/s
	Scale: number,
	Radius: number, -- rayon de contact (bonk, éclaboussure)
	Species: { string }, -- espèces sauvages (Communes / Rares)
	Unlock: number, -- vague d'apparition
	Share: number, -- part de la vague une fois débloqué
	SplitInto: string?,
	SplitCount: number?,
}

Siege.Types = {
	Grunt = { Id = "Grunt", Name = "Grunt", HP = 1, Speed = 9, Scale = 1, Radius = 2, Species = { "Gloop", "DinoNugget" }, Unlock = 1, Share = 1 },
	Runner = { Id = "Runner", Name = "Runner", HP = 0.6, Speed = 13, Scale = 0.85, Radius = 1.8, Species = { "Pigeonator", "Wormzy" }, Unlock = 3, Share = 0.25 },
	Tank = { Id = "Tank", Name = "Tank", HP = 3, Speed = 6, Scale = 1.2, Radius = 2.6, Species = { "Pinchy", "BeepBoop" }, Unlock = 6, Share = 0.2 },
	Splitter = { Id = "Splitter", Name = "Splitter", HP = 1, Speed = 8, Scale = 1, Radius = 2.1, Species = { "ThunderSquid" }, Unlock = 9, Share = 0.15, SplitInto = "Runner", SplitCount = 2 },
} :: { [string]: InvaderType }

-- L'Alpha : toutes les 5 vagues, un gros envahisseur qui lâche un œuf sauvage.
Siege.Alpha = {
	Every = 5,
	HP = 12,
	Scale = 2,
	Speed = 5.5,
	Radius = 4.5,
	Species = { "Frostodon", "Kebabzilla", "Croissantosaurus", "Sharkapillar" },
}

-- Teinte « sauvage » appliquée aux modèles (mélange avec la couleur d'origine).
Siege.WildTint = Color3.fromRGB(96, 190, 70)
Siege.WildTintAmount = 0.35

-- Vague d'entraînement (tutoriel) : gagnable avec un seul bébé Commun.
Siege.Tutorial = {
	Count = 4,
	HP = 4, -- un seul tir d'un bébé (5 dégâts) ou un bonk
	Speed = 6,
	Gap = 2.5,
	Timeout = 120, -- s : sécurité, la vague se termine quoi qu'il arrive
}

function Siege.Count(wave: number): number
	return math.min(20, 6 + math.floor(wave / 2))
end

function Siege.BaseHP(wave: number): number
	return 18 * 1.2 ^ (wave - 1)
end

function Siege.HasAlpha(wave: number): boolean
	return wave > 0 and wave % Siege.Alpha.Every == 0
end

-- Composition déterministe d'une vague : liste ordonnée de types.
function Siege.Composition(wave: number): { string }
	local count = Siege.Count(wave)
	local list: { string } = {}
	for _, id in { "Runner", "Tank", "Splitter" } do
		local t = Siege.Types[id]
		if wave >= t.Unlock then
			for _ = 1, math.max(1, math.floor(count * t.Share + 0.5)) do
				if #list < count - 1 then
					table.insert(list, id)
				end
			end
		end
	end
	while #list < count do
		table.insert(list, "Grunt")
	end
	-- mélange stable (même vague = même ordre), les tanks jamais en premier
	local rng = Random.new(wave * 7919)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	if list[1] == "Tank" then
		for i = 2, #list do
			if list[i] ~= "Tank" then
				list[1], list[i] = list[i], list[1]
				break
			end
		end
	end
	return list
end

----------------------------------------------------------------------------
-- Tours (kaijus éclos sur un nid)
----------------------------------------------------------------------------

Siege.TowerRange = 14 -- + 4 × stade
Siege.TowerRangePerStage = 4
Siege.TowerDamage = 5 -- × Calc.Power(rec) par tir
Siege.TowerCooldown = 1 -- s entre deux tirs
Siege.SplashStage = 4 -- Titans et Colosses éclaboussent
Siege.SplashRadius = 6
Siege.SplashFactor = 0.6

function Siege.Range(stage: number): number
	return Siege.TowerRange + Siege.TowerRangePerStage * stage
end

----------------------------------------------------------------------------
-- Joueur
----------------------------------------------------------------------------

Siege.BonkDamage = 10 -- × (1 + 0.25 × niveau du Bonker)
Siege.BonkPerLevel = 0.25
Siege.SuperBonkMult = 1.5
Siege.BonkPush = 8 -- recul le long du chemin

----------------------------------------------------------------------------
-- Fuites et récompenses
----------------------------------------------------------------------------

Siege.BagShare = 0.05 -- part du cash stocké dans le réacteur
Siege.BagMaxSeconds = 60 -- plafond : 60 s de revenu
Siege.FleeSpeedMult = 0.5

Siege.OrbSeconds = 3 -- chaque kill : orbe de 3 s de revenu
Siege.OrbMinPerWave = 10 -- plancher : 10 $ × vague
Siege.OrbLifetime = 45
Siege.OrbPickup = 6 -- studs : ramassée en marchant dessus

Siege.WaveSeconds = 20 -- bonus de fin : 20 s de revenu × (1 + 0.05 × vague)
Siege.WavePerWave = 0.05
Siege.WaveMinPerWave = 50
Siege.GemsEvery = 10
Siege.Gems = 10

-- Œuf sauvage de l'Alpha selon la vague.
export type EggOdds = { { Rarity: string, Weight: number } }
local function odds(a: string, wa: number, b: string, wb: number): EggOdds
	return { { Rarity = a, Weight = wa }, { Rarity = b, Weight = wb } }
end
Siege.AlphaEggs = {
	{ From = 30, Odds = odds("Mythic", 90, "Celestial", 10) },
	{ From = 20, Odds = odds("Legendary", 75, "Mythic", 25) },
	{ From = 10, Odds = odds("Epic", 60, "Legendary", 40) },
	{ From = 0, Odds = odds("Rare", 70, "Epic", 30) },
}

function Siege.EggOdds(wave: number): EggOdds
	for _, row in Siege.AlphaEggs do
		if wave >= row.From then
			return row.Odds
		end
	end
	return Siege.AlphaEggs[#Siege.AlphaEggs].Odds
end

-- Étoiles de fin de vague (0 fuite = 3 étoiles).
function Siege.Stars(leaks: number, total: number): number
	if leaks <= 0 then
		return 3
	elseif leaks / math.max(total, 1) < 0.25 then
		return 2
	end
	return 1
end

return Siege
