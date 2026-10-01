# AngAInOne v2 — « Opération Anti-Lag » · Feuille de route

Scénario : [`SCENARIO.md`](SCENARIO.md). Contrat de la tour : `src/shared/Config/Tower.luau`.

## To-do list

### Phase 0 — Conception et contrats (chef de projet)
- [x] Scénario complet (histoire, personnages, 7 mondes, incidents, boss, lobby, difficulté)
- [x] Contrats partagés : `Tower.luau` (nouveaux pièges, incidents, sbires), `Incidents.luau`,
      `Util/TrapClock.luau` (horloge des pièges qui tient compte des incidents), données (clés USB)
- [x] Découpage du travail entre agents (ci-dessous)

### Phase 1 — Fondations (4 agents en parallèle)
- [x] **A1 · Architecte de la tour** : découper `TowerBuilder` (2 100 lignes) en modules :
      `World/Tower/Common` (outils + contexte), `Shell`, `Lobby`, `Worlds/W1..W7`, salle de terminal
      standard, entrée/sortie fixes de chaque monde ; le rendu actuel est conservé, tests verts.
- [x] **A2 · Pièges** : `TrapController` — 14 nouveaux pièges (voir contrat), horloge `TrapClock`
      (FREEZE / LAG SPIKE), effets des incidents sur les pièges (BLACKOUT, CORRUPTION, SURCHAUFFE),
      tests de simulation.
- [x] **A3 · Scénario en jeu** : `IncidentService` (serveur) + incidents côté client (annonce,
      effets d'écran, tempête de pop-ups à fermer, blackout), widget « Performance du PC »
      (FPS / ping / °C), mondes infectés ↔ nettoyés (tags), répliques d'Anga et de LAGZ,
      moniteur du live dans le lobby, cinématique de fin « le live commence ».
- [x] **A4 · Mini-jeux** : 2 nouveaux mini-jeux (Pop-up Killer, Défrag) + variante boss du
      Firewall (LAGZ), tests.

### Phase 2 — Contenu 3D (5 agents en parallèle, sur la base de A1 + A2)
- [x] **B1 · Chambre d'Anga + tour** : lobby sur le bureau (écran du live, clavier RGB, souris,
      micro, tasse, lampe), Miniaturiseur AngAInOne (départ), tour vitrée plus réaliste.
- [x] **B2 · Mondes 1–2** (Alimentation, Memory Lanes) : parcours uniques, pièges signature, décor
      infecté/propre, sbires, clés USB.
- [x] **B3 · Mondes 3–4** (Data Vault, Cryo Tower).
- [x] **B4 · Mondes 5–6** (The Core, Render Canyon).
- [x] **B5 · Monde 7 + boss LAGZ** : arène, 3 phases (serveur `BossService` + client
      `BossController`), fin.

### Phase 2 bis — Vrais modèles 3D (Blender → glTF → MeshParts, voir `assets/README.md`)
- [x] Pipeline : `assets/blender/common.py`, `ModelLibrary` (décor de secours), `tools/upload_models.py`
- [x] **M1 · Matériel PC** (24) · **M2 · Chambre d'Anga** (16) · **M3 · Personnages et objets** (15)
- [x] Placement des modèles dans le lobby, les 7 mondes, les terminaux et les collectibles (décor de secours sinon)
- [x] Import sur Roblox (Open Cloud) : 58 modèles + portrait d'Anga, IDs dans `ModelAssets.luau`,
      `Branding.luau` et `assets/models/manifest.json`
- [ ] Vérification des orientations et des tailles en jeu (Studio)

### Phase 3 — Intégration (chef de projet)
- [x] Fusion, clés USB (serveur + HUD + récompenses), relecture indépendante (11 corrections),
      rendus, README, build `.rbxl`, envoi.
- [ ] Équilibrage en jeu réel (Studio) : temps par monde, difficulté des incidents.

## Contrats techniques

### Monde (A1 → B2..B5)
`src/server/World/Tower/Worlds/W{n}.luau` renvoie `function(ctx: Common.WorldContext)`.
Le contexte fournit : la définition du monde, le `Model` du monde, la bande de hauteur
(`ctx.Base` → `ctx.Base + BAND`), l'**entrée** (CFrame d'arrivée, fixe) et la **salle du terminal**
(fixe, construite par `ctx.TerminalRoom()`, avec terminal, portail, rampe vers le monde suivant),
et des outils : `ctx.Checkpoint(stage, cframe)`, `ctx.Coin(position)`, `ctx.UsbKey(position, i)`,
`ctx.Trap(kind, part, attributes)`, `ctx.Hazard(...)`, `ctx.Platform(...)`, palette du monde.
Un monde doit poser les checkpoints `Tower.FirstStage(n) .. Tower.TerminalStage(n) - 1` dans son
parcours ; le checkpoint `TerminalStage(n)` est dans la salle du terminal.

### Pièges (A2 ↔ mondes)
Tag `Trap`, attributs `Kind` (dans `Tower.TrapKinds`), **`World`** (numéro du monde, obligatoire)
et ceux listés dans `Tower.luau`. Le temps des pièges vient de `TrapClock.Now(world)`.

### Incidents (A3 → A2)
Le serveur publie l'état dans `ReplicatedStorage.IncidentState` (attributs par monde) :
`Kind{w}` ("" ou un type d'`Incidents.Kinds`), `Warn{w}` (annonce), `Start{w}`, `End{w}`
(heures `Workspace:GetServerTimeNow()`), `Offset{w}` (secondes de FREEZE déjà écoulées).
Fin d'un FREEZE : `Offset{w} += End - Start` et `Kind{w} = ""` dans la même frame.

### Décor infecté / propre (A3 ↔ mondes)
Tag `Infected` : visible seulement tant que le joueur n'a pas nettoyé le monde (`World`).
Tag `Cleaned` : visible seulement après. Les deux portent l'attribut `World`.

### Boss (A4 → B5)
Phase 3 du boss : `MinigamePanel.Play("Firewall", 8, …)` (Firewall contre LAGZ, 36 PV, bouclier).

### Clés USB (mondes → phase 3)
Tag `UsbKey`, attribut `KeyId` = `W{n}K{i}` (i = 1..3), non collidable, touchable.


## v3 — « AngAInOne en avant » (voir [`AUDIT_V3.md`](AUDIT_V3.md) ; boîte à outils écartée)
- [x] **V1 · Compagnon AIO** : drone de l'app qui suit le joueur, bulles de dialogue au-dessus de lui,
      indique le prochain checkpoint, réagit aux incidents (modèle 3D + secours).
- [x] **V2 · Scénario par l'image** : rôle « Technicien·ne AngAInOne », intro « mission acceptée »,
      tour qui s'allume monde par monde, apparitions de LAGZ en 3D, **Rapport d'optimisation** final.
- [x] **V3 · Gameplay** : sensations de saut (coyote time, saut mémorisé), médailles par monde,
      « points de restauration ».
- [x] **V4 · Design** : ambiance par monde (atmosphère, lumière, particules), fond de carte mère sous
      les mondes, HUD allégé.
- [x] **V5 · L'app AngAInOne partout** : mondes = pages de l'app, fenêtres de l'app sur les parois,
      morts = « Plantages », intros de terminal façon app, Anga géant ; compagnon = mini-Anga.
- [x] Relecture indépendante v3 (15 constats corrigés) + test anti-marques.

## v3.1 — Après le premier import des modèles 3D
- [x] Monde 1 renommé **Alimentation** (« La Centrale » partout : config, plaque, docs).
- [x] **Placement vérifiable sans Studio** : modèles simulés par leurs boîtes (`tools/model_bounds.py`,
      `tests/lib/FakeModels.luau`, `IsolatedTower`), `tests/placement.spec.luau`, `PlacementReport`,
      `ExportMap --models` ; option `Height` de `ModelLibrary.Place` ; plus aucune méthode `Model`
      réservée à Roblox dans la construction.
- [x] Corrections trouvées par ces outils : radiateur AIO du monde 4 debout, ventilateur-verrou du monde 6
      (110 → 22 studs), barrettes RAM au ras de leur slot, faisceaux gainés du monde 1 dans leur plan,
      ventilateur de l'alimentation à 88 studs.
- [x] **Détours « Ventilo bonus »** (`Tower/Bonus.luau`) : un par monde, Méga-Bit (5 Bits) + 2 Bits,
      pales SpinBar, emplacements choisis avec `tests/tools/BonusSpots.luau`.
- [x] **Orientation des modèles** : personnages, drone et alimentation retournés au chargement
      (`ORIENT`), ventilateur du ventirad vers -Z, pubs du monde 7 vers le parcours ; test « façades ».
- [x] **Guide AngAinOne × Roblox** (docs/SCENARIO.md §8) : conseils « vraie vie » + raccourcis app,
      vocabulaire, boss écran bleu, incident Mise à jour, écran Test de perf, badges, 9 easter eggs.
- [ ] Vérification en jeu (Studio) : traversée des pales, lisibilité des panneaux (BONUS, CONSEIL),
      écran Test de perf sur téléphone, easter eggs.
- [ ] IDs des badges à créer sur create.roblox.com et à coller dans `Config/Badges.luau`.

## v3.2 — Gameplay façon PC, menus de l'app (voir [`SCENARIO.md`](SCENARIO.md) §9)
- [x] **Menus refaits au style de l'app** : fenêtre plate, fil d'Ariane, pages à gauche (onglets sur
      téléphone), boutons plats, cartes à liseré, textes ≥ 18 px de conception.
- [x] **Mécaniques par monde** : enquêtes (1 et 7), RAM (2), chaleur + ventilateurs à relancer +
      ventilo propulseur (4), bloatware (5), artefacts GPU (6) ; jauge contextuelle du HUD.
- [x] **Mini-jeux** : Tri des fichiers (terminal du monde 5), Défense du CPU (arcade).
- [x] **Épreuves 3D des salles du terminal** (guide « AngAinOne × Roblox ») : Démarrage infecté
  (M1), RAM saturée (M2), Bloatware (M3), surchauffe (M4), Défense du CPU en 3D (M5), pilote GPU +
  écran (M6), enquête des Sessions avant le boss (M7) ; panneaux au style de l'app ; menu DEV.
- [x] **Étape 0 « L'intrusion »** : le bureau du PC, free_robux_generator.exe, prévention.
- [ ] Épreuves **en coop** (une épreuve partagée par la salle, rôles obligatoires) ; jauges partagées.
- [ ] Équilibrer les épreuves et les médailles avec la télémétrie (temps réels en jeu).
- [x] **BIOS caché** (touche Suppr, QR code anga.tv), **Stream Deck** interactif, **rôles d'équipe**
      (version légère : un passif chacun).
- [x] Tests : `mechanics.spec`, `gauges.spec`, `newgames.spec`, BIOS dans `tower.spec` ; outil
      `tests/tools/FreeBoxes.luau` (volumes libres pour une nouvelle mécanique).
- [ ] Vérification en jeu (Studio) : ressenti du ralentissement de RAM et de la chaleur, lisibilité des
      panneaux d'enquête, téléport du BIOS avec le streaming, menus sur téléphone.
- [ ] Coop à 4 rôles obligatoires avec objectifs partagés, jauges partagées, tour de défense 3D à
      plusieurs (idées du guide, pas encore faites).
