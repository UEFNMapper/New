--!strict
--[[
	Medals : médailles par monde (bronze / argent / or), autorité serveur (ProgressService).

	Temps d'un monde (« split ») : du moment où l'on ENTRE dans le monde (ligne de départ pour le
	monde 1, portail ouvert = terminal précédent réussi pour les suivants) jusqu'au terminal
	antivirus du monde réussi. Il comprend donc le parcours des 5 étapes, l'épreuve 3D de la salle du
	terminal (Config/Epreuves) et, au monde 7, l'enquête puis le combat contre LAGZ. Chrono de l'ascension (RunElapsed) : arrêté au lobby et
	hors connexion, comme le chrono principal.

	Règles (généreuses : public 8–14 ans) :
	- Bronze : monde nettoyé (toujours) ;
	- Argent : temps ≤ Silver ET au plus SilverMaxDeaths morts dans le monde ;
	- Or     : temps ≤ Gold   ET au plus GoldMaxDeaths morts dans le monde ;
	  (MinKeys : clés USB du monde possédées, 0 = pas de condition).

	Course assistée (étape passée, bouclier, bottes anti-gravité ou puce de vitesse activés PENDANT
	le monde) : au mieux l'ARGENT (l'or ne s'achète pas), gardé dans la collection ; le temps
	n'entre pas au record du monde (WorldBest.Time) et ne déclenche pas « Nouveau record ». Le
	marquage est immédiat dès l'activation (MedalLogic.MarkAssisted), pas seulement à la
	vérification périodique.

	Morts du monde : comptées par le serveur (Humanoid.Died, hors lobby). Les pièges sont détectés
	par le client (ReportDeath) ; en plus, un contrôle serveur compte une chute dans le vide d'un
	monde (racine plus de 0,5 s dans le vide, une fois par chute, sans doubler le Died qui suit) et
	ramène au checkpoint. Un client modifié peut encore ignorer un piège mobile : les médailles
	restent donc COSMÉTIQUES (collection, aucun gain de Bits ni d'avantage de jeu).

	Estimation des seuils : chemin des checkpoints mesuré sur la tour construite (≈ 475–570 studs en
	ligne droite par monde, ≈ 650 studs réels à 16 studs/s ≈ 40 s de course pure), plus l'attente
	des pièges (plus nombreux à partir du monde 3), l'épreuve de la salle (~30–50 s) et le terminal.
	À affiner avec la télémétrie en jeu réel (voir ROADMAP : équilibrage).
]]

export type WorldRule = {
	Gold: number, -- secondes max pour l'or
	Silver: number, -- secondes max pour l'argent
}

local Medals = {}

-- Du moins bon au meilleur.
Medals.Order = table.freeze({ "Bronze", "Silver", "Gold" })

Medals.Names = table.freeze({
	Bronze = "Bronze",
	Silver = "Argent",
	Gold = "Or",
})

-- Couleurs du médaillon (clair, base, ombre) : dégradé dessiné en Frames (aucune image).
Medals.Colors = table.freeze({
	Bronze = table.freeze({ "F3B98A", "C8814A", "7A4424" }),
	Silver = table.freeze({ "F4F7FB", "BCC6D3", "6E7A8C" }),
	Gold = table.freeze({ "FFF1A8", "F6C453", "B7791F" }),
})

Medals.GoldMaxDeaths = 2
Medals.SilverMaxDeaths = 6
Medals.GoldMinKeys = 0 -- clés USB du monde possédées pour l'or (0 = pas de condition)

-- Seuils par monde (secondes, épreuve de la salle du terminal comprise).
Medals.Worlds = table.freeze({
	-- 1 · Alimentation : ≈ 570 studs, 24 pièges lents (fenêtres ≥ 1,2 s), épreuve Démarrage.
	table.freeze({ Gold = 120, Silver = 205 }),
	-- 2 · Memory Lanes : ≈ 510 studs, barrettes qui écrasent (attente), épreuve RAM.
	table.freeze({ Gold = 120, Silver = 205 }),
	-- 3 · Data Vault : ≈ 485 studs mais 85 pièges (dalles corrompues, disparition), épreuve Bloatware.
	table.freeze({ Gold = 130, Silver = 215 }),
	-- 4 · Cryo Tower : ≈ 475 studs, vent et pales (on attend les rafales), épreuve Surchauffe.
	table.freeze({ Gold = 130, Silver = 215 }),
	-- 5 · The Core : ≈ 515 studs, plateformes en latence (lentes), Défense du CPU.
	table.freeze({ Gold = 135, Silver = 225 }),
	-- 6 · Render Canyon : ≈ 500 studs, 93 pièges (pixels morts, ponts de chargement), épreuve Pilote.
	table.freeze({ Gold = 140, Silver = 235 }),
	-- 7 · Neural Nexus : ≈ 525 studs + enquête + combat contre LAGZ (25 s de lasers, 3 prises,
	-- Firewall boss 36 PV) : bien plus long.
	table.freeze({ Gold = 260, Silver = 390 }),
} :: { WorldRule })

-- Règle d'un monde (seuils par défaut si le monde n'est pas listé).
function Medals.Rule(world: number): WorldRule
	return Medals.Worlds[world] or { Gold = 90, Silver = 150 }
end

return table.freeze(Medals)
