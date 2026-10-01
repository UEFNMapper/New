# AngAInOne — Deathrun dans la tour PC · GDD v2

> Remplace le GDD tycoon v1 (trop compliqué pour les enfants). Le code du tycoon a été retiré.

## 1. Pitch

**Opération Anti-Lag** (scénario complet : [`SCENARIO.md`](SCENARIO.md)). Une heure avant le plus
gros live d'AngaTV, le PC d'Anga **rame** : 3 FPS, 999 ms de ping, freezes, pop-ups. Le coupable :
**LAGZ**, un virus qui se nourrit de la puissance des PC. L'app **AngAInOne** en « Mode
Intervention » te **miniaturise** et t'envoie dans la tour : tu la grimpes composant par composant
(alimentation, RAM, SSD, refroidissement, processeur, carte graphique, puce IA), tu survis aux
pièges et aux **incidents** que LAGZ déclenche, tu nettoies chaque monde au **terminal antivirus**
(mini-jeu 2D)… jusqu'au **combat contre LAGZ** tout en haut. Chaque monde nettoyé répare un
symptôme : le PC remonte à 144 FPS et **le live commence**.

- **Genre** : deathrun / obby à pièges automatiques (PvE), solo ou à plusieurs sur la même tour.
- **Public** : 8–14 ans, cross-plateforme (mobile d'abord).
- **Règle d'or** : compréhensible en 5 secondes. *Cours, saute, ne touche pas ce qui est rouge.*

## 2. Boucle de jeu

1. **Lobby = la chambre d'Anga** : on apparaît minuscule sur son bureau (clavier RGB praticable,
   écran du live « LIVE DANS 59:00 », micro, tasse…), devant la tour vitrée. Pad **JOUER** dans le
   **Miniaturiseur AngAInOne**. Boutique, classements, arcade, cadeaux.
2. **Étapes** : chaque monde = 5 étapes courtes, chacune finit par un **checkpoint** ; une idée
   de piège par étape, la 5ᵉ combine tout. On meurt → dernier checkpoint. Aucun game over.
3. **Incidents de LAGZ** (toutes les 60–120 s, annoncés 3 s avant) : FREEZE, LAG SPIKE, BLACKOUT,
   POP-UP STORM, CORRUPTION, SURCHAUFFE — ils changent vraiment les pièges du monde.
4. **Salle du terminal** (salle sûre, gardée par le sbire du monde) : une **épreuve 3D** tirée du
   guide (docs/SCENARIO.md §10). Réussie → le monde passe de « infecté » à « nettoyé », le portail
   s'ouvre, le PC gagne des FPS.
5. **Monde 7 → boss LAGZ** en 3 phases, puis la fin « LE LIVE COMMENCE ! ». Chrono, records.

## 3. Les 7 mondes (config : `src/shared/Config/Tower.luau`, construction : `World/Tower/Worlds/W{n}.luau`)

| # | Monde | Parcours | Pièges signature | Incident | Sbire | Épreuve de la salle |
|---|---|---|---|---|---|---|
| 1 | Alimentation (PSU) | câbles tressés, condensateurs, grille du ventilateur | Surtension, plateformes alimentées, décharges, trampolines | BLACKOUT | Sparky | Le Démarrage infecté |
| 2 | Memory Lanes (RAM) | ville de barrettes, canyon | barrettes qui écrasent, pluie d'onglets, fuite mémoire | POP-UP STORM | Pop-Up | La RAM saturée |
| 3 | Data Vault (SSD) | damier NAND, baie de disques | dalles corrompues, défragmenteur, tiroirs, pistons | CORRUPTION | Corrupto | L'invasion du Bloatware |
| 4 | Cryo Tower (refroidissement) | radiateur, tube de watercooling, ventilateurs | jets de vapeur, boules de poussière, vent, pales | SURCHAUFFE | Dusty | La surchauffe |
| 5 | The Core (CPU) | spirale du ventirad, broches du socket | pioches, plateformes en latence, roues de chargement | LAG SPIKE | Minor | Défense du CPU (3D) |
| 6 | Render Canyon (GPU) | canyon de la carte graphique, piste de pixels | pixels morts, ponts de chargement, pales géantes | FREEZE | Freezy | La carte graphique corrompue |
| 7 | Neural Nexus (puce IA) | cerveau holographique, arène | curseur géant, pare-feu mobiles, virus | tous | LAGZ | Enquête des Sessions, puis Firewall boss |

25 types de pièges (tag `Trap`, attribut `Kind`, liste dans `Tower.luau`). Tout ce qui tue est
**rouge / magenta** et prévenu avant de s'activer. Les pièges sont animés côté client avec l'horloge
du serveur **de leur monde** (`TrapClock` : le FREEZE la fige, le LAG SPIKE la fait avancer par
à-coups) : tous les joueurs voient la même chose au même moment.

**Difficulté** : écarts ≤ 6,5 studs, fenêtres sûres ≥ 1,2 s au monde 1 → ≥ 0,8 s au monde 7.

## 4. Mini-jeux 2D antivirus (arcade, et Firewall boss au monde 7)

| Mini-jeu | But |
|---|---|
| **Scan** | Tape les virus qui surgissent dans la grille avant qu'ils disparaissent. |
| **Pop-up Killer** | Ferme les pubs (✕) avant que la RAM sature ; les faux boutons en ouvrent d'autres. |
| **Défrag** | Échange des cases pour regrouper les fichiers de chaque couleur (toujours soluble). |
| **Firewall** | Déplace le pare-feu et tire sur les virus. Difficulté 8 = **combat contre LAGZ** (36 PV, bouclier). |
| **Memory** | Retrouve les paires de cartes mémoire. |
| **Dodge** | Guide le paquet de données entre les virus (arcade). |

Le sbire du monde apparaît sur les cartes d'intro et de résultat. Les 6 jeux sont rejouables à la
**borne d'arcade** du lobby (petites récompenses, délai entre deux gains).

## 5. Features

- **Performance du PC** (widget HUD : FPS / ping / °C) qui s'améliore à chaque monde nettoyé.
- **Mondes infectés / nettoyés** (décor différent pour chaque joueur selon sa progression).
- **Boss LAGZ** : survivre aux lasers et au curseur, brancher 3 prises antivirus, Firewall boss.
- **21 clés USB dorées** cachées sur des chemins difficiles (3 par monde) : Bits, compteur au HUD,
  toutes les clés → traînée USB.
- **Conseils « vraie vie »** par monde (panneau de la salle du terminal + bulle de l'assistant de l'app),
  **Test de perf** en hexagone à la fin (4 scores, emblème, pseudo en néon), **boss façon écran bleu**,
  incident **« Mise à jour »**, **badges** par monde et **easter eggs** de l'univers AngAinOne
  (câble HDMI, le Service, Corbeille, pâte thermique, RGB = +10 FPS, escargot Wi-Fi, dev caché) :
  voir `docs/SCENARIO.md` §8.
- **7 détours « Ventilo bonus »** (un par monde, panneau BONUS au pied d'un checkpoint) : une
  passerelle traverse un ventilateur de boîtier dont les pales mortelles balaient l'ouverture, et finit
  sur un **Méga-Bit** (5 Bits) + 2 Bits : 7 Bits pour un aller-retour risqué, contre 4 par étape.
- **Checkpoints**, bouton « Revenir au checkpoint », bouton « Lobby ».
- **Chrono** de l'ascension + record perso ; **classements** : victoires, meilleur temps, étape max.
- **Bits** : orbes du parcours, mini-jeux, clés USB. **Boutique** : traînées, effets de mort.
- **Récompenses quotidiennes** (calendrier 7 jours) et **missions du jour** (3).
- **Multijoueur** : pas de collision entre joueurs, étape au-dessus de la tête, bonus d'amis.
- **Histoire** : intro en 3 cartes (LAGZ apparaît), répliques d'Anga et de LAGZ, moniteur du live.
- **Vrais modèles 3D** (Blender → MeshParts) : matériel PC, chambre, personnages
  (voir [`../assets/README.md`](../assets/README.md)).
- **Réglages** : volumes, animations réduites (retire aussi les effets d'écran des incidents).

## 6. Monétisation (éthique, rien d'obligatoire)

| Article | Type | Prix indicatif |
|---|---|---|
| Passer l'étape | Developer Product | 19 R$ |
| Bouclier 30 s (invincible) | Developer Product | 29 R$ |
| Packs de Bits | Developer Product | 49 / 149 / 399 R$ |
| VIP (x2 Bits, traînée VIP) | Game Pass | 249 R$ |
| Bottes anti-gravité (saut plus haut, activable) | Game Pass | 149 R$ |
| Puce de vitesse (+20 % vitesse, activable) | Game Pass | 149 R$ |

Pas de loot box. Les passes « avantage » sont activables/désactivables et n'affectent pas les
classements de temps (course marquée « assistée »).

## 7. Anti-triche (serveur)

Checkpoints validés dans l'ordre, temps minimum par étape, portail d'un monde franchissable
seulement après le mini-jeu, durée minimale d'un mini-jeu, orbes ramassées à proximité et une
seule fois par ascension. Les morts sont signalées par le client (pièges animés côté client) :
tricher ne fait qu'éviter de mourir soi-même, le serveur garde la main sur la progression.

## 8. Technique

- Luau `--!strict`, Rojo. Serveur : `Core/`, `Security/` (RemoteGuard), `Services/` (Data, State,
  Progress, Incident, Boss, Minigame, Shop/Monetization, Mission, Leaderboard, Social, Dev),
  `World/` (TowerBuilder → `Tower/Common`, `Lobby`, `RoomProps`, `Shell`, `Worlds/W1..W7`,
  `ModelLibrary`).
- Client : `Controllers/` (TrapController + `Traps/*`, IncidentController, BossController,
  WorldState, Story, StreamMonitor, Feedback, WorldFx…), `UI/` (HUD, Moments, Dialogue…),
  `UI/Minigames/` (6 mini-jeux + logique pure testée).
- Tests Lune : construction réelle de la tour (checkpoints, graphe de sauts, budgets, pièges),
  simulation du vrai TrapController, incidents, boss, mini-jeux (bots), contrats client/serveur.
