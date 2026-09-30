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
| Paramètres du jeu > Places > Nombre max. de joueurs | **6** | Une tour par joueur (6 tours). |
| Paramètres du jeu > Avatar | R15 | Animations modernes. |
| Paramètres du jeu > Sécurité | Allow HTTP Requests : OFF · Third Party Sales/Teleports : OFF | Rien n'en a besoin. |

L'éclairage (Future, Atmosphere, Bloom, ColorCorrection, SunRays) et le StreamingEnabled sont déjà réglés par `default.project.json`.

---

## 2. À configurer avant la publication

1. **Game Passes et Developer Products** : crée-les sur le [Creator Dashboard](https://create.roblox.com/dashboard/creations) avec les prix de la grille, puis colle leurs IDs dans [`src/shared/Config/Products.luau`](src/shared/Config/Products.luau). Un ID à `0` = article masqué et refusé par le serveur.
2. **Logo / mascotte Anga** : importe ton image (Asset Manager > Importer), copie l'ID et colle-le dans [`src/shared/Config/Branding.luau`](src/shared/Config/Branding.luau) (`AngaImageId = "rbxassetid://…"`). Sinon, un monogramme « A » rouge s'affiche.
3. **Groupe Roblox** (optionnel) : `GroupId` dans [`src/shared/Config/GameConfig.luau`](src/shared/Config/GameConfig.luau) pour le bonus de groupe (+5 %).
4. **Questionnaire de maturité** du contenu (Creator Dashboard) : « Minimal ».

---

## 3. Tester dans Studio (checklist)

Lance **Play** (F5). En Studio, un bouton **DEV** (ou **F8**) ouvre un panneau de test : ajouter des Bits ou des Chips, passer à l'étage suivant, finir le tutoriel, activer les virus, réinitialiser la sauvegarde. Le serveur ignore ces commandes en ligne.

| # | Action | Résultat attendu |
|---|---|---|
| 1 | Lancer Play | Tu apparais au rez-de-chaussée de ta tour (La Centrale, néons ambre). Une carte « ALLUMER LE PC » avec Anga apparaît au centre. Sortie : `[AngAInOne] Serveur prêt.` |
| 2 | Cliquer **ALLUMER LE PC** | Flash « SYSTEM ONLINE », son de démarrage, léger tremblement, les étages s'allument de bas en haut, la musique démarre. Bulle d'Anga : « Marche sur le collecteur doré ». Un faisceau lumineux te guide. |
| 3 | Marcher sur le pad doré | Particules de Bits qui volent vers le compteur, son de collecte, compteur qui défile. |
| 4 | Objectif « AMÉLIORER » (carte à droite) | Le panneau Composants s'ouvre sur la Cellule VoltCore. Acheter x1 : son, niveau +1, production/s augmente. |
| 5 | Encore une amélioration | L'objectif devient « Débloque Memory Lanes (25K) » avec une barre de progression. |
| 6 | DEV > « +10 min de Bits », puis **DÉBLOQUER** | Bannière « NOUVEL ÉTAGE · MEMORY LANES », bouton « Y ALLER » qui te téléporte à l'étage 2 (musique et teinte violette). |
| 7 | Terminal violet « Capsules » à l'étage 2 | Panneau Nanobots > Capsules avec les probabilités affichées. Ouvrir : révélation de la capsule avec halo de rareté. Le Nanobot est équipé automatiquement. |
| 8 | Dock **Étages** | Liste des étages. Les étages verrouillés sont grisés. Le hub te ramène sur la carte mère avec les classements. |
| 9 | DEV > « Étage suivant » jusqu'au SSD (3) | Jauge 🌡 visible. En achetant beaucoup de niveaux SSD, la chaleur monte, la bordure RGB des panneaux vire à l'ambre puis au rouge, et l'objectif affiche « SURCHAUFFE ». |
| 10 | Étage 4 (Cryo), terminal « Radiateurs » | La capacité thermique augmente, la jauge redescend, les bordures redeviennent RGB. |
| 11 | Étage 5 (CPU), terminal d'overclock | Mini-jeu : l'aiguille oscille. STOP (clic, Espace ou A manette) dans la zone dorée donne « PARFAIT ! x2 », et une pilule « OVERCLOCK x2 · 2:59 » apparaît sous le Benchmark. |
| 12 | DEV > « Activer les virus », attendre ~30 s | Une boule rouge glitchée apparaît. Prompt « Zapper » (F) : son électrique, « +X » flottant, tremblement. |
| 13 | Dock **Quêtes** | Calendrier de 7 jours, bouton « RÉCUPÉRER », 3 quêtes du jour et 4 de la semaine, téléchargements (dès le SSD). |
| 14 | Étage 6 (GPU), console BIOS | Aperçu du Firmware. **Maintenir** 1,5 s déclenche l'écran BIOS, puis la Génération 2 (Bits et étages réinitialisés, Chips et Nanobots conservés). |
| 15 | DEV > étage 7 + « +1e15 Bits » plusieurs fois, BIOS > Singularité | 5 phases. La dernière déclenche la cinématique de fin. |
| 16 | Quitter puis relancer Play | Tout est sauvegardé. Après plus d'une minute d'absence, la carte « CONTENT DE TE REVOIR » affiche les gains hors ligne. |
| 17 | Test > Clients et serveurs > 2 joueurs | Deux tours différentes. Menu > Tours : « LIKER » la tour de l'autre joueur, qui reçoit une notification. Les prompts de la tour d'un autre joueur sont inactifs. |
| 18 | Émulateur d'appareil (téléphone 19,5:9, tablette) | Le HUD tient à l'écran, les boutons restent confortables au doigt, les panneaux sont centrés. |

**Contrôles** :
- **Clavier** : C Composants · N Nanobots · Q Quêtes · B Boutique · T Étages · M Menu · Échap ferme · E interagir · F zapper un virus · Espace STOP à l'overclock.
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
│  ├─ Services/    Data, State, Economy, Plot, Upgrade, Overclock, Virus, Nanobot, Quest,
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
