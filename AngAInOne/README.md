# AngAInOne — Deathrun dans la tour PC

**Un virus a infecté le PC d'Anga.** Tu es miniaturisé dans sa tour géante et tu dois la grimper de bas en haut en survivant aux pièges (décharges électriques, ventilateurs, barrettes qui écrasent, lasers, virus…). À la fin de chaque monde, un **terminal antivirus** : un mini-jeu 2D pour ouvrir la porte suivante. Solo ou à plusieurs.

- Game design complet : [`docs/GDD.md`](docs/GDD.md)
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
3. **Groupe Roblox** (optionnel) : `GroupId` dans [`src/shared/Config/GameConfig.luau`](src/shared/Config/GameConfig.luau) pour le bonus de groupe (+5 %).
4. **Questionnaire de maturité** du contenu (Creator Dashboard) : « Minimal ».

---

## 3. Tester dans Studio (checklist)

Lance **Play** (F5). En Studio, un bouton **DEV** (ou **F8**) ouvre un panneau de test : +1 000 Bits, étape suivante, monde suivant, réussir le terminal, aller au sommet, bouclier, RESET de la sauvegarde. Le serveur ignore ces commandes en ligne.

| # | Action | Résultat attendu |
|---|---|---|
| 1 | Lancer Play (première fois) | Tu apparais au **lobby**. Anga raconte l'histoire en 3 cartes (« SUITE », puis « C'EST PARTI ! »). Sortie : `[AngAInOne] Serveur prêt.` |
| 2 | Regarder le lobby | Titre holographique, écran géant de l'app **AngAInOne** (tes stats), 3 classements, bornes Boutique / Arcade / Cadeaux. En haut : « LOBBY · Salle de démarrage », barre de la tour, et un gros bouton **JOUER**. |
| 3 | Appuyer sur **JOUER**, passer la ligne de départ | Bannière « MONDE 1 · LA CENTRALE », Anga explique les pièges, le chrono ⏱ démarre. |
| 4 | Atteindre un checkpoint | « Checkpoint 1 ✓ », +Bits, la barre de la tour avance, le checkpoint suivant pulse en doré. |
| 5 | Toucher un piège ou tomber | Flash « OUPS ! », effet de mort, réapparition au dernier checkpoint en 1,5 s. |
| 6 | Ramasser des orbes | Son + étincelles dorées, +1 Bit ; l'orbe disparaît pour toi jusqu'à la fin de l'ascension. |
| 7 | Salle du terminal (étape 5) | But : « Élimine les virus au terminal 💻 ». Le portail est solide. Prompt **E** sur le terminal → mini-jeu 2D. Réussi : « VIRUS ÉLIMINÉS ! », le portail s'ouvre. |
| 8 | Boutons à droite | **Checkpoint** (revenir), **Passer l'étape** (Robux, visible si le produit est configuré), **Lobby** (la progression est gardée ; au lobby, le bouton devient **CONTINUER · Étape X**). |
| 9 | DEV > « Aller au sommet », DEV > « Réussir le terminal », toucher le cœur tout en haut | Écran **TU AS SAUVÉ LE PC !** avec ton temps (record ?), Bits, puis retour au lobby ; les classements se mettent à jour. |
| 10 | Dock **Boutique** | Onglets Traînées / Effets / Robux. Acheter une traînée avec des Bits l'équipe directement (visible par tous). |
| 11 | Dock **Missions** | Calendrier 7 jours (« RÉCUPÉRER ») + 3 missions du jour avec barres de progression. |
| 12 | Borne **Arcade** au lobby | 4 mini-jeux jouables pour quelques Bits (délai entre deux récompenses). |
| 13 | Quitter puis relancer Play | Tout est sauvegardé : tu reprends à ton étape (bouton CONTINUER), le chrono reprend là où il s'était arrêté. |
| 14 | Test > Clients et serveurs > 2 joueurs | Les deux joueurs grimpent la même tour sans se pousser ; « Étape X » s'affiche au-dessus de l'autre ; Menu > Joueurs liste son étape. |
| 15 | Émulateur d'appareil (téléphone, tablette) | Le HUD tient à l'écran, les boutons restent confortables au doigt. |

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
│  ├─ Config/      Tower (le contrat du deathrun), GameConfig, Cosmetics, Missions, Products,
│  │               Audio, Theme, Branding
│  ├─ Data/        DataSchema (schéma versionné + migrations)
│  ├─ Net/         Remotes (déclaration centralisée)
│  ├─ Util/        NumberFormat, Time
│  └─ Packages/    Signal, Trove (RbxUtil, MIT)
├─ server/  (ServerScriptService.Server)
│  ├─ Main.server.luau
│  ├─ Core/        Session, GameEvents, Telemetry, Wallet (Bits + messages)
│  ├─ Security/    RemoteGuard (types, cadence, session), RateLimiter
│  ├─ World/       TowerBuilder (la tour procédurale), Props (pièces de PC), Build
│  ├─ Services/    Data, State, Progress, Minigame, Shop, Monetization, Mission,
│  │               Leaderboard, Social, Dev
│  └─ Packages/    ProfileStore (loleris, Apache 2.0)
└─ client/  (StarterPlayerScripts.Client)
   ├─ Main.client.luau
   ├─ Controllers/ Net, Store, Audio, Feedback, WorldFx, TrapController, Interactions, AppScreen
   └─ UI/          App, Style (StyleSheets), Motion, Material, Components (Keycap, Panel, Icon,
                   Widgets), Screens (HUD, Boutique, Missions, Menu, Arcade, Moments…),
                   Minigames (Scan, Firewall, Memory, Dodge)
```

**Principes** : le serveur a toujours l'autorité. Chaque requête client passe par `RemoteGuard` : limite de fréquence, session chargée, type et nombre d'arguments. Côté données, les sauvegardes utilisent ProfileStore (verrouillage de session, sauvegarde auto et à l'arrêt), et les achats sont traités de façon idempotente avec confirmation de sauvegarde.

---

## 5. Vérifications automatiques

```bash
./scripts/verify.sh
```
Enchaîne : analyse de types **stricte** contre l'API Roblox (luau-lsp), lint (selene), format (StyLua), **tests Lune** et build Rojo. Les tests couvrent :
- la **tour réelle**, construite dans Lune : checkpoints dans l'ordre, terminaux, portails, arrivée, orbes, pièges valides, budget de pièces et de lumières ;
- les **mini-jeux** : difficulté, conditions de victoire ;
- le contrat de la tour (mondes, étapes), les configs, le schéma de données et ses migrations ;
- le limiteur de fréquence ;
- le **contrat client/serveur** : chaque requête du client existe côté serveur avec le bon nombre d'arguments, et chaque champ d'état lu par le client est bien envoyé ;
- la **validité de chaque nom de propriété** affectée dynamiquement, contrôlée contre l'API Roblox.

Tu as changé l'équilibrage ? `lune run tests/tools/pacing_report.luau` affiche la progression simulée génération par génération.

La même vérification tourne en CI GitHub Actions à chaque push.
