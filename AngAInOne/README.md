# AngAInOne — Tycoon Roblox « à l'intérieur de ton PC »

Tu es rétréci dans ton PC gamer. Guidé par **Anga**, tu améliores chaque pièce (alimentation, RAM, SSD, refroidissement, CPU, GPU, AI Core) pour construire la machine la plus puissante… jusqu'à la **Singularité**.

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
| Paramètres du jeu > Places > Nombre max. de joueurs | **12** | Un seul PC géant partagé : 12 joueurs restent confortables. |
| Paramètres du jeu > Avatar | R15 | Animations modernes. |
| Paramètres du jeu > Sécurité | Allow HTTP Requests : OFF · Third Party Sales/Teleports : OFF | Rien n'en a besoin. |

L'éclairage (Future, lumière de jour à travers la vitre du boîtier, Atmosphere claire, Bloom, ColorCorrection, SunRays) et le StreamingEnabled sont déjà réglés par `default.project.json`. La map est construite au démarrage du serveur (`src/server/World/MapBuilder.luau`) : ne place rien à la main dans Workspace.

---

## 2. À configurer avant la publication

1. **Game Passes et Developer Products** : crée-les sur le [Creator Dashboard](https://create.roblox.com/dashboard/creations) avec les prix de la grille, puis colle leurs IDs dans [`src/shared/Config/Products.luau`](src/shared/Config/Products.luau). Un ID à `0` = article masqué et refusé par le serveur.
2. **Logo / mascotte Anga** : importe ton image (Asset Manager > Importer), copie l'ID et colle-le dans [`src/shared/Config/Branding.luau`](src/shared/Config/Branding.luau) (`AngaImageId = "rbxassetid://…"`). Sinon, un monogramme « A » rouge s'affiche.
3. **Groupe Roblox** (optionnel) : `GroupId` dans [`src/shared/Config/GameConfig.luau`](src/shared/Config/GameConfig.luau) pour le bonus de groupe (+5 %).
4. **Questionnaire de maturité** du contenu (Creator Dashboard) : « Minimal ».

---

## 3. Tester dans Studio (checklist)

Lance **Play** (F5). En Studio, un bouton **DEV** (ou **F8**) ouvre un panneau de test : ajouter des Bits ou des Chips, passer à la zone suivante, finir le tutoriel, activer les virus, réinitialiser la sauvegarde. Le serveur ignore ces commandes en ligne.

| # | Action | Résultat attendu |
|---|---|---|
| 1 | Lancer Play | Tu apparais au hub, au centre de la carte mère, en plein jour sous la vitre du boîtier. Face à toi : l'écran géant de l'app AngAInOne au-dessus du portail de The Core. Une carte « ALLUMER LE PC » avec Anga apparaît au centre. Sortie : `[AngAInOne] Serveur prêt.` |
| 2 | Cliquer **ALLUMER LE PC** | Flash « SYSTEM ONLINE », son de démarrage, léger tremblement, les néons des machines flashent, la musique démarre. Bulle d'Anga. Les chevrons au sol te guident vers le portail ambré de La Centrale (derrière toi), puis vers le collecteur doré. |
| 3 | Marcher sur le pad doré | Particules de Bits qui volent vers le compteur, son de collecte, compteur qui défile. |
| 4 | Objectif « AMÉLIORER » (carte « TON BUT » à droite) | Le panneau Améliorer s'ouvre sur la Cellule VoltCore : un gros bouton vert AMÉLIORER avec le prix, les étoiles de tier et une barre « Bonus x2 au niveau 10 ». |
| 5 | Encore une amélioration | L'objectif devient « Débloque Memory Lanes (25K) » avec une barre de progression. |
| 6 | DEV > « +10 min de Bits », puis le terminal « Débloquer » au portail violet du hub (est) | Bannière « MEMORY LANES », la barrière du portail s'ouvre (flash), bouton « Y ALLER » qui te téléporte dans la zone (musique et teinte violette). Un toast « Memory Lanes · Applications » s'affiche à l'entrée. |
| 7 | Terminal « Capsules » de Memory Lanes | Panneau Robots > Capsules avec les probabilités affichées. Ouvrir : révélation de la capsule avec halo de rareté. Le robot est équipé automatiquement. |
| 8 | Minimap (haut droite) ou dock **Carte** (ou un pad téléporteur) | Grande carte du PC vue de dessus : ta position (point + direction), ton objectif (étoile), zones fermées grisées avec cadenas et prix. Toucher une zone ouverte = téléportation ; une zone fermée explique où l'ouvrir. En jeu, un panneau flotte au-dessus de chaque zone et le nom de la zone actuelle s'affiche en haut à droite. Essaie aussi de traverser un portail verrouillé : il est solide, et le serveur te renvoie si tu forces. |
| 9 | DEV > « Zone suivante » jusqu'au SSD (3) | Jauge 🌡 visible. En achetant beaucoup de niveaux SSD, la chaleur monte, la bordure RGB des panneaux vire à l'ambre puis au rouge, et l'objectif affiche « SURCHAUFFE ». |
| 10 | Cryo Tower (4), terminal « Radiateurs » | La capacité thermique augmente, la jauge redescend, les bordures redeviennent RGB. |
| 11 | The Core (5), terminal d'overclock | Mini-jeu : l'aiguille oscille. STOP (clic, Espace ou A manette) dans la zone dorée donne « PARFAIT ! x2 », et une pilule « OVERCLOCK x2 · 2:59 » apparaît sous le Benchmark. |
| 12 | DEV > « Activer les virus », attendre ~30 s | Une boule rouge glitchée apparaît. Prompt « Zapper » (F) : son électrique, « +X » flottant, tremblement. |
| 13 | Dock **Missions** | Calendrier de 7 jours, bouton « RÉCUPÉRER », 3 quêtes du jour et 4 de la semaine, téléchargements (dès le SSD). |
| 14 | Render Canyon (6), console BIOS | Aperçu du Firmware. **Maintenir** 1,5 s déclenche l'écran BIOS, puis la Génération 2 (Bits et zones réinitialisés, Chips et robots conservés) et un retour au hub. |
| 15 | DEV > zone 7 + « +1e15 Bits » plusieurs fois, BIOS > Singularité | 5 phases. La dernière déclenche la cinématique de fin. |
| 16 | Quitter puis relancer Play | Tout est sauvegardé. Après plus d'une minute d'absence, la carte « CONTENT DE TE REVOIR » affiche les gains hors ligne. |
| 17 | Test > Clients et serveurs > 2 joueurs | Les deux joueurs sont dans le même PC. Chacun voit SES niveaux sur les machines, SES portails ouverts, SES virus (ceux de l'autre sont invisibles). Menu > Joueurs : « LIKER » le PC de l'autre joueur, qui reçoit une notification. |
| 18 | Émulateur d'appareil (téléphone 19,5:9, tablette) | Le HUD tient à l'écran, les boutons restent confortables au doigt, les panneaux sont centrés. |

**Contrôles** :
- **Clavier** : C Améliorer · N Robots · Q Missions · T Carte · B Boutique · M Menu (roue en haut à droite) · Échap ferme · E interagir · F zapper un virus · Espace STOP à l'overclock.
- **Manette** : Y donne le focus au dock (croix + A) · B ferme · X interagir · A STOP à l'overclock.
- **Tactile** : les boutons du dock et les prompts à l'écran.

**À surveiller dans la Sortie** : aucune erreur rouge. Un message `[Style] Le moteur UI Styling ne s'applique pas : bascule sur le mode direct` est normal si ta version de Studio n'applique pas les StyleSheets : le rendu reste identique.

---

## 4. Architecture

```
src/
├─ shared/  (ReplicatedStorage.Shared)
│  ├─ Config/      Zones, Modules, Nanobots, Products, Quests, Audio, Theme, Branding, GameConfig, WorldLayout
│  ├─ Economy/     Formulas, Production, Bonuses          ← purs, testés avec Lune
│  ├─ Data/        DataSchema (schéma versionné + migrations)
│  ├─ Net/         Remotes (déclaration centralisée)
│  ├─ Util/        NumberFormat
│  └─ Packages/    Signal, Trove (RbxUtil, MIT)
├─ server/  (ServerScriptService.Server)
│  ├─ Main.server.luau
│  ├─ Core/        Session, GameEvents, Telemetry, ServerState
│  ├─ Security/    RemoteGuard (types, cadence, session), RateLimiter
│  ├─ World/       MapBuilder (map procédurale), Build
│  ├─ Services/    Data, State, Economy, World, Upgrade, Overclock, Virus, Nanobot, Quest,
│  │               Download, Reboot, Monetization, Leaderboard, Social, Onboarding, Dev
│  └─ Packages/    ProfileStore (loleris, Apache 2.0)
└─ client/  (StarterPlayerScripts.Client)
   ├─ Main.client.luau
   ├─ Controllers/ Net, Store, Audio, Feedback, WorldFx, ZoneTracker, Interactions, Guide
   └─ UI/          App, Style (StyleSheets), Motion, Material (matériaux dynamiques),
                   Components (Keycap, Panel, Icon, Widgets), Screens (HUD, panneaux, moments)
```

**Principes** : le serveur a toujours l'autorité. Chaque requête client passe par `RemoteGuard` : limite de fréquence, session chargée, type et nombre d'arguments. Côté données, les sauvegardes utilisent ProfileStore (verrouillage de session, sauvegarde auto et à l'arrêt), et les achats sont traités de façon idempotente avec confirmation de sauvegarde.

---

## 5. Vérifications automatiques

```bash
./scripts/verify.sh
```
Enchaîne : analyse de types **stricte** contre l'API Roblox (luau-lsp), lint (selene), format (StyLua), **tests Lune** et build Rojo. Les tests couvrent :
- les formules d'économie ;
- le **rythme de progression** : une partie simulée avec la vraie config doit respecter les fenêtres du GDD ;
- le schéma de données et ses migrations ;
- le limiteur de fréquence ;
- le **contrat client/serveur** : chaque requête du client existe côté serveur avec le bon nombre d'arguments, et chaque champ d'état lu par le client est bien envoyé ;
- la **validité de chaque nom de propriété** affectée dynamiquement, contrôlée contre l'API Roblox.

Tu as changé l'équilibrage ? `lune run tests/tools/pacing_report.luau` affiche la progression simulée génération par génération.

La même vérification tourne en CI GitHub Actions à chaque push.
