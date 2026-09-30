# AngAInOne — Deathrun dans la tour PC

**Opération Anti-Lag.** Une heure avant le live d'Anga, son PC rame : le virus **LAGZ** l'a infecté. L'app AngAInOne te miniaturise et tu grimpes la tour géante, composant par composant, en survivant aux pièges (câbles sous tension, barrettes qui écrasent, pioches du crypto-mineur, pixels morts…) et aux **incidents** de LAGZ (freeze, lag, blackout, pop-ups…). À la fin de chaque monde, un **terminal antivirus** (mini-jeu 2D) nettoie le monde ; tout en haut, le **combat contre LAGZ**. Solo ou à plusieurs.

- Scénario : [`docs/SCENARIO.md`](docs/SCENARIO.md) · Game design : [`docs/GDD.md`](docs/GDD.md) · Feuille de route : [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Vrais modèles 3D (Blender → Roblox) : [`assets/README.md`](assets/README.md)
- Assets, licences et sécurité : [`docs/ASSETS.md`](docs/ASSETS.md)

---

## 1. Ouvrir le jeu dans Roblox Studio

Le code est un projet **Rojo** : les fichiers `.luau` de `src/` deviennent les scripts du jeu.

### Option A — le plus simple : construire un fichier `.rbxl`
1. Installe [Rokit](https://github.com/rojo-rbx/rokit), puis dans ce dossier : `rokit install` (installe Rojo, Lune, selene, StyLua et luau-lsp aux bonnes versions).
2. `rojo build default.project.json -o AngAInOne.rbxl`
3. Double-clique sur `AngAInOne.rbxl` : Studio s'ouvre avec tout le jeu.

### Option B — développement en direct (recommandé pour itérer)
1. Installe le plugin Rojo dans Studio (Plugins > Gérer les plugins, ou `rojo plugin install`).
2. `rojo serve` dans ce dossier.
3. Dans Studio : ouvre une place vide, onglet Plugins > Rojo > **Connect**. Chaque sauvegarde de fichier est synchronisée.

### Réglages obligatoires dans Studio (une seule fois)
| Où | Réglage | Pourquoi |
|---|---|---|
| Accueil > Paramètres du jeu > Sécurité | **Enable Studio Access to API Services** : ON | Sauvegardes (DataStore) et classements en test. Sans ça, le jeu bascule automatiquement sur une sauvegarde simulée. |
| Paramètres du jeu > Places > Nombre max. de joueurs | **12** | Tout le monde grimpe la même tour (les joueurs ne se bousculent pas). |
| Paramètres du jeu > Avatar | R15 | Animations modernes. |
| Paramètres du jeu > Sécurité | Allow HTTP Requests : OFF · Third Party Sales/Teleports : OFF | Rien n'en a besoin. |

L'éclairage (Future, lumière de jour à travers la vitre du boîtier, Atmosphere claire, Bloom, ColorCorrection, SunRays) et le StreamingEnabled sont déjà réglés par `default.project.json`. La tour est construite au démarrage du serveur (`src/server/World/TowerBuilder.luau`) : ne place rien à la main dans Workspace.

---

## 2. À configurer avant la publication

1. **Game Passes et Developer Products** : crée-les sur le [Creator Dashboard](https://create.roblox.com/dashboard/creations) avec les prix de la grille, puis colle leurs IDs dans [`src/shared/Config/Products.luau`](src/shared/Config/Products.luau). Un ID à `0` = article masqué et refusé par le serveur.
2. **Logo / mascotte Anga** : importe ton image (Asset Manager > Importer), copie l'ID et colle-le dans [`src/shared/Config/Branding.luau`](src/shared/Config/Branding.luau) (`AngaImageId = "rbxassetid://…"`). Sinon, un monogramme « A » rouge s'affiche.
3. **Modèles 3D** : importe les `.glb` de `assets/models/` (automatique avec `tools/upload_models.py`, ou à la main dans Studio) — voir [`assets/README.md`](assets/README.md). Sans eux, le jeu affiche un décor de secours en blocs.
4. **Groupe Roblox** (optionnel) : `GroupId` dans [`src/shared/Config/GameConfig.luau`](src/shared/Config/GameConfig.luau) pour le bonus de groupe (+5 %).
5. **Questionnaire de maturité** du contenu (Creator Dashboard) : « Minimal ».

---

## 3. Tester dans Studio (checklist)

Lance **Play** (F5). En Studio, un bouton **DEV** (ou **F8**) ouvre un panneau de test : +1 000 Bits, étape suivante, monde suivant, réussir le terminal, aller au sommet, bouclier, RESET de la sauvegarde. Le serveur ignore ces commandes en ligne.

| # | Action | Résultat attendu |
|---|---|---|
| 1 | Lancer Play (première fois) | Tu apparais minuscule sur le **bureau d'Anga**. Intro en 3 cartes (LAGZ apparaît à la 2ᵉ). Sortie : `[AngAInOne] Serveur prêt.` |
| 2 | Regarder le lobby | Écran du live « LIVE DANS 59:00 » avec le chat, clavier RGB (on peut sauter sur les touches), tour vitrée, écran de l'app AngAInOne, 3 classements, bornes. En haut à gauche : widget **PC D'ANGA** (3 FPS, 999 ms, 97 °C). |
| 3 | **JOUER** → Miniaturiseur, passer la ligne de départ | Bannière « MONDE 1 · LA CENTRALE », Anga explique, le chrono ⏱ démarre. |
| 4 | Atteindre un checkpoint | « Checkpoint 1 ✓ », +Bits, le checkpoint suivant pulse en doré. |
| 5 | Toucher un piège (rouge) ou tomber | Flash « OUPS ! », réapparition au dernier checkpoint en 1,5 s. |
| 6 | Attendre 60–120 s dans un monde | Bandeau LAGZ « ⚠ … 3-2-1 », puis l'incident du monde (ex. BLACKOUT au monde 1 : lumière coupée, rails alimentés éteints). |
| 7 | Ramasser une **clé USB dorée** (chemin difficile) | Effet doré, « 🔑 Clé USB dorée 1/21 », +25 Bits, pastille sous la carte de progression. |
| 8 | Salle du terminal | Le sbire du monde garde le terminal. Prompt **E** → mini-jeu 2D. Réussi : le monde passe en version « nettoyée », le widget du PC gagne des FPS, le portail s'ouvre. |
| 9 | DEV > aller à l'étape 35 (monde 7) | Arène : LAGZ, phase 1 (lasers + curseur), phase 2 (3 prises à brancher), phase 3 (Firewall boss au terminal). Victoire → « LE LIVE COMMENCE ! », l'écran du lobby passe « EN DIRECT 🔴 ». |
| 10 | Boutons à droite | **Checkpoint**, **Passer l'étape** (Robux, si configuré), **Lobby** (le bouton devient **CONTINUER · Étape X**). |
| 11 | Dock **Boutique** / **Missions** | Traînées et effets (Bits) ; calendrier 7 jours + 3 missions du jour. |
| 12 | Borne **Arcade** | 6 mini-jeux (Scan, Pop-up Killer, Défrag, Firewall, Memory, Dodge). |
| 13 | Quitter puis relancer | Tout est sauvegardé (étape, chrono, clés USB, mondes nettoyés). |
| 14 | 2 joueurs (Test > Clients et serveurs) | Même tour, pas de bousculade ; chacun voit ses mondes infectés/nettoyés et son propre combat de boss. |
| 15 | Émulateur de téléphone | HUD lisible, ✕ des pop-ups et boutons confortables au doigt. |
| 16 | Menu > animations réduites | Plus de tremblements ni de flashs pendant les incidents. |

**Contrôles** :
- **Clavier** : B Boutique · Q Missions · M Menu · Échap ferme · E interagir.
- **Manette** : Y donne le focus au dock (croix + A) · B ferme · X interagir.
- **Tactile** : les boutons à l'écran et les prompts.

**À surveiller dans la Sortie** : aucune erreur rouge. Un message `[Style] Le moteur UI Styling ne s'applique pas : bascule sur le mode direct` est normal si ta version de Studio n'applique pas les StyleSheets : le rendu reste identique.

---

## 4. Architecture

```
src/
├─ shared/  (ReplicatedStorage.Shared)
│  ├─ Config/      Tower (le contrat : mondes, 25 pièges, mini-jeux), Incidents, GameConfig,
│  │               Cosmetics, Missions, Products, Audio, Theme, Branding, ModelAssets (IDs 3D)
│  ├─ Data/        DataSchema (schéma versionné + migrations)
│  ├─ Net/         Remotes (déclaration centralisée)
│  ├─ Util/        TrapClock, IncidentSchedule, PcHealth, BossLogic, NumberFormat, Time
│  └─ Packages/    Signal, Trove (RbxUtil, MIT)
├─ server/  (ServerScriptService.Server)
│  ├─ Main.server.luau
│  ├─ Core/        Session, GameEvents, Telemetry, Wallet (Bits + messages)
│  ├─ Security/    RemoteGuard (types, cadence, session), RateLimiter
│  ├─ World/       TowerBuilder → Tower/ (Common, Lobby, RoomProps, Shell, Worlds/W1..W7),
│  │               ModelLibrary (vrais modèles 3D + décor de secours), Props, Build
│  ├─ Services/    Data, State, Progress, Incident, Boss, Minigame, Shop, Monetization,
│  │               Mission, Leaderboard, Social, Dev
│  └─ Packages/    ProfileStore (loleris, Apache 2.0)
└─ client/  (StarterPlayerScripts.Client)
   ├─ Main.client.luau
   ├─ Controllers/ TrapController + Traps/ (25 pièges), IncidentController, BossController,
   │               WorldState, Story, StreamMonitor, Feedback, WorldFx, Interactions, AppScreen…
   └─ UI/          App, Style, Motion, Material, Components, Screens (HUD, Moments, Dialogue,
                   Boutique, Missions, Menu, Arcade…), Minigames (Scan, Popup, Defrag,
                   Firewall + boss, Memory, Dodge)
assets/            blender/ (scripts de modélisation), models/ (.glb), previews/ (rendus)
tools/             upload_models.py (envoi des modèles sur Roblox via Open Cloud)
```

**Principes** : le serveur a toujours l'autorité. Chaque requête client passe par `RemoteGuard` : limite de fréquence, session chargée, type et nombre d'arguments. Côté données, les sauvegardes utilisent ProfileStore (verrouillage de session, sauvegarde auto et à l'arrêt), et les achats sont traités de façon idempotente avec confirmation de sauvegarde.

---

## 5. Vérifications automatiques

```bash
./scripts/verify.sh
```
Enchaîne : analyse de types **stricte** contre l'API Roblox (luau-lsp), lint (selene), format (StyLua), **tests Lune** et build Rojo. Les tests couvrent :
- la **tour réelle**, construite dans Lune : checkpoints dans l'ordre, **graphe de sauts** (chaque étape est franchissable), terminaux, portails, orbes, clés USB, pièges valides et code couleur, budgets de pièces et de lumières ;
- le **vrai TrapController** simulé sur la tour (poses, transport, morts) et les 25 pièges (`traps.spec`) ;
- les **incidents** (planification, horloge FREEZE / LAG), le **boss** (phases, prises), les modèles 3D (convention de nom) ;
- les **mini-jeux** : difficulté, conditions de victoire, bots joueurs ;
- le contrat de la tour (mondes, étapes), les configs, le schéma de données et ses migrations ;
- le limiteur de fréquence ;
- le **contrat client/serveur** : chaque requête du client existe côté serveur avec le bon nombre d'arguments, et chaque champ d'état lu par le client est bien envoyé ;
- la **validité de chaque nom de propriété** affectée dynamiquement, contrôlée contre l'API Roblox.

Tu as changé l'équilibrage ? `lune run tests/tools/pacing_report.luau` affiche la progression simulée génération par génération.

La même vérification tourne en CI GitHub Actions à chaque push.
