# AngAInOne — Game Design Document v0.1

> Statut : **proposition, en attente de validation**. Aucun code de jeu n'est écrit avant ton feu vert.
> Plateforme : Roblox, cross-plateforme équilibré (PC / mobile / console), 13+. Objectif : jeu monétisé sérieux.

---

## 1. Pitch

**Tu es rétréci à la taille d'un électron et tu vis à l'intérieur de ton propre PC gamer.**
Guidé par **Anga** (la mascotte : barbe blonde, t-shirt rouge « A »), tu remontes ta tour étage par étage : alimentation, RAM, SSD, refroidissement, CPU, GPU… jusqu'à l'**AI Core**, le cœur qui pulse tout en haut, visible dès la première seconde.
Chaque pièce améliorée fait monter ton **Benchmark**. Ton objectif : le PC le plus puissant du serveur, puis la **Singularité**.

**Fantasy** : « construire le setup de rêve » + « explorer l'intérieur de sa machine » + « voir sa tour s'illuminer de plus en plus ».

### Piliers
1. **Voir sa puissance** : chaque achat change visiblement la tour (lumière, vitesse des flux de données, taille des pièces).
2. **Toujours un prochain objectif à moins de 5 min** au début, moins de 20 min en milieu de partie.
3. **Une vraie décision de joueur PC** : puissance ↔ énergie (Watts) ↔ chaleur (°C).
4. **Beau et doux** : néon RGB tamisé, UI en verre sombre, musique lo-fi électronique.
5. **Jamais pay-to-win abusif**, pas de dark patterns.

---

## 2. Monde et structure

### 2.1 Le serveur
- **6 joueurs par serveur.** Le hub est une **carte mère géante** (« Motherboard Plaza »). Les pistes de cuivre lumineuses font office de routes.
- Chaque joueur reçoit **sa tour PC** (son plot), posée sur un des 6 slots autour du hub. Les panneaux en verre trempé laissent voir l'intérieur des tours des autres joueurs, ce qui crée de l'émulation.
- On entre dans sa tour par le panneau avant. On peut visiter la tour des autres (bouton *Visiter* + *Like*).

### 2.2 La tour : progression verticale
L'**AI Core** au sommet est le repère visible de partout : un faisceau blanc-violet qui pulse au rythme de la musique.

| Étage | Zone | Rôle gameplay | Repère visuel | Palette |
|---|---|---|---|---|
| 0 | **La Centrale** (PSU) | Départ, tutoriel ; définit la **capacité en Watts** | Condensateurs géants, arcs électriques doux | Ambre |
| 1 | **Memory Lanes** (RAM) | 1ʳᵉ zone débloquée ; production rapide | 4 barrettes de 120 studs, vague RGB | Violet |
| 2 | **Data Vault** (SSD NVMe) | Débloque les **Téléchargements** (rendez-vous) | Couloirs de cellules NAND, flux de particules | Teal |
| 3 | **Cryo Tower** (Refroidissement) | Introduit la **Chaleur** et le **refroidissement** | Ventilateur de 80 studs qui tourne lentement, brume froide | Cyan glacé |
| 4 | **The Core** (CPU) | Débloque l'**Overclock** ; grosse production | Temple de silicium, cœurs en forme d'immeubles | Or / blanc |
| 5 | **Render Canyon** (GPU) | Zone « boss » ; débloque le **Reboot** | Canyon entre 3 ventilateurs, sols réfléchissants | Vert-cyan / magenta |
| 6 | **Neural Nexus** (AI Core) | Fin du run : construire la **Singularité** | Cerveau holographique, Anga en forme finale | Blanc / violet |

Circulation : ascenseurs à câbles tressés (à privilégier sur mobile) + jump pads + escaliers lumineux. Chaque étage a une **zone de respiration** (balcon avec vue sur la tour et banc) et **10 Fragments de données cachés** (lore d'Anga, petit bonus permanent).

### 2.3 Composants (marques fictives, pour éviter tout problème de marque déposée)
Chaque zone contient **3 modules** améliorables de niv. 1 à 250 (ex. RAM : *Kryo DDR* ×3 barrettes). Tous les 10 niveaux, le module change de **tier visuel** : Bronze → Argent → Or → Diamant → RGB-Prisme.
Marques : VoltCore (PSU), Kryo (RAM), NovaDrive (SSD), Frostbyte (refroidissement), Helion (CPU), Prism (GPU), ANGA Neural Unit (AI).

---

## 3. Boucles de jeu

### 3.1 Core loop (en une phrase)
**Collecter les Bits produits par tes composants → améliorer les pièces → ton Benchmark grimpe → débloquer l'étage suivant.**

Les données sortent des composants sous forme de **paquets lumineux** qui voyagent sur les pistes (l'équivalent des convoyeurs d'un tycoon classique) jusqu'au **Collecteur** (le northbridge) de chaque étage. On marche dessus pour encaisser. Avec le pass Auto-Collect, l'encaissement est automatique.

### 3.2 Boucles secondaires
| Boucle | Fréquence | Récompense | Pourquoi |
|---|---|---|---|
| **Énergie et chaleur** : garder Watts ≤ capacité PSU et °C ≤ refroidissement | Continue | Production à 100 % | La vraie décision « builder de PC » |
| **Overclock** : mini-jeu de timing (jauge + zone verte) sur un composant | Cooldown de 5 min | ×2 production pendant 3 min, mais +30 % de chaleur | Jeu actif, skill |
| **Virus / Glitches** : petites créatures glitchées qui apparaissent dans ta tour ; on les zappe avec le **Debugger** | Toutes les 2 à 4 min | Bits + chance de Chips | Mouvement, action |
| **Nanobots** (« pets ») : capsules → compagnons qui donnent des bonus | En continu | +% Bits, vitesse, rayon de collecte, -chaleur | Collection, long terme |
| **Téléchargements** : lancer un DL de 30 min / 4 h / 8 h | Rendez-vous | Gros paquet de Bits / Chips / capsule | Raison de revenir |
| **Fragments de données** | Exploration | Lore + bonus permanent de +1 % | Exploration |
| **Reboot** (prestige) | Toutes les 2 à 7 h | Firmware (multiplicateur permanent) + Génération suivante | Rejouabilité |

### 3.3 Énergie et chaleur (système signature)
- Chaque module consomme des **Watts** et produit de la **Chaleur**.
- `efficacitéÉnergie = min(1, capacitéPSU / wattsConsommés)`
- `efficacitéThermique = min(1, capacitéRefroidissement / chaleurProduite)`
- `production = Σ prod(modules) × efficacitéÉnergie × efficacitéThermique × multiplicateurs`
- L'UI affiche deux jauges fines (⚡ et 🌡️) qui passent à l'ambre puis au rouge. Anga prévient : *« Ton CPU chauffe ! Passe à la Cryo Tower. »*
- Pas de punition cachée : le joueur voit exactement combien de % il perd.

---

## 4. Économie

### 4.1 Monnaies
| Monnaie | Type | Source | Utilisation |
|---|---|---|---|
| **Bits** | Soft, principale | Production, virus, téléchargements | Upgrades, zones, capsules standard |
| **Chips** 💠 | Premium gagnable | Quotidien, quêtes, succès, events, pass gratuit, Robux | Cosmétiques, boosts, capsules premium, skip de DL |
| **Firmware** | Prestige | Reboot | Multiplicateur permanent (+5 %/pt) + arbre de talents |

Un joueur F2P gagne **environ 120 à 180 Chips par jour** en jouant normalement : le premium est atteignable sans payer.

### 4.2 Formules (validées par simulation, voir `tools/economy_sim.py`)
```
coût(module, niveau)  = coûtBase × 1.12^niveau
prod(module, niveau)  = prodBase × niveau × 2^(nb de paliers atteints parmi 10, 25, 50, 100)
coûtBase(zone z)      = 10 × 20^z   (modules relatifs ×1, ×6, ×36)
prodBase(zone z)      = 0.9 × 15^z  (idem)
Firmware gagné        = floor( sqrt( BitsGagnésDuRun / 1e11 ) )
multFirmware          = 1 + 0.05 × Firmware
Benchmark (score)     = Σ niveaux × poidsZone, affiché en FLOPS (K, M, G, T, P)
```

| Déblocage | Coût (Bits) |
|---|---|
| RAM | 25 K |
| SSD | 25 M |
| Cryo Tower | 2,5 B |
| CPU | 75 B |
| GPU | 3 T |
| AI Core | 100 T |
| **Singularité** (fin) | **100 Qa (1e17)** |

### 4.3 Pacing mesuré (joueur optimal simulé ; un vrai joueur ≈ ×1,3 à 1,5)
| Moment | Temps simulé | Ce qui se passe |
|---|---|---|
| 0:00 → 0:30 | — | Allumer le PC (moment « waouh »), 1ʳᵉ collecte, 1ᵉʳ upgrade |
| 3 min | 3 min | RAM débloquée |
| ~6 min | — | 1ʳᵉ capsule de Nanobot (offerte par la quête du tutoriel) |
| 10 min | 10 min | SSD + 1ᵉʳ Téléchargement |
| ~30–45 min | 36 min | Cryo Tower : la chaleur entre en jeu (**fin de la 1ʳᵉ session visée**) |
| ~1 h 30–2 h | 91 min | CPU + Overclock |
| ~4–6 h | 240 min | GPU, puis 1ᵉʳ Reboot disponible |
| Génération 2 | +6,7 h | AI Core atteint pour la 1ʳᵉ fois |
| Génération 3 | +2,4 h | Runs rapides, plaisir du « speedrun » |
| **Génération 4** | **≈ 22 h cumulées** (≈ 30 h réelles) | **Singularité → cinématique de fin** |
| Après la fin | ∞ | Générations 5 à 10 (nouveaux skins de tiers), events, classements hebdo |

⚠️ **À corriger à l'étape Économie** : la Gen 2 (6,7 h) et le dernier run de la Gen 4 (7,7 h) sont trop longs. On ajoutera l'arbre de Firmware et des paliers intermédiaires dans l'AI Core pour garder un objectif toutes les 20 min maximum.

### 4.4 Gains hors ligne
50 % de la production, plafonnés à 2 h (upgradable à 4 h via Firmware ; 8 h à 100 % avec le Game Pass). Écran de retour : « Pendant ton absence, ton PC a produit… », avec un bouton ×2 via pub récompensée si elle est disponible.

### 4.5 Sinks (contrôle de l'inflation)
Upgrades, zones, capsules (coût indexé sur la production courante), fusion de Nanobots (5 identiques → 1 doré), cosmétiques en Chips, boosts temporaires.

---

## 5. Nanobots (collection)
- Capsules par zone. Coût en Bits indexé sur la production (≈ 5 min de prod), capsules premium en Chips.
- **Probabilités affichées en permanence** : Commun 60 % · Rare 28 % · Épique 9 % · Légendaire 2,7 % · Mythique 0,3 %.
- 3 slots équipés (+2 avec Game Pass). Fusion 5 → 1 doré (×1,5 stats). Index de collection avec récompenses par zone complétée.
- **Conformité** : `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` → si vrai, les capsules achetables en Robux (et en Chips achetés) sont masquées pour ce joueur ; seules les capsules en Bits restent.
- **Échanges (Trade)** : en V2 après le lancement, avec double confirmation, compte à rebours de 5 s, validation serveur et logs.

---

## 6. Rétention

| Levier | Détail | Vise |
|---|---|---|
| **Récompense quotidienne** | Calendrier de 7 jours à série croissante (J7 = capsule Épique garantie). Une série cassée recule d'un jour au lieu de revenir à zéro (pas de punition brutale). | J1, J7 |
| **Quêtes** | 3 quotidiennes + 5 hebdomadaires (collecter X, overclocker 3 fois, zapper 20 virus…), 1 reroll gratuit par jour | J1–J30 |
| **Téléchargements** | Rendez-vous de 30 min / 4 h / 8 h | J1 |
| **Gains hors ligne** | Voir 4.4 | J1 |
| **Patch Pass** (saison de 30 jours) | Piste gratuite + premium, 40 paliers, cosmétiques exclusifs | J30 |
| **Events limités (48 h)** | *Canicule* (chaleur ×1,5, récompenses cooling), *Épidémie de virus* (virus ×3 + Nanobot d'event), *Black Friday* (-30 % sur les upgrades en Bits), saisonniers (*Malware Manor* à Halloween, *Frost Cooling* à Noël) | J7–J30 |
| **Mises à jour** | Chaque samedi (compte à rebours dans le hub), nouveaux étages/tiers mensuels | J7–J30 |
| **Classements** | Benchmark (all-time), Bits hebdomadaires (reset le lundi, top 100 = badge + cosmétique), Génération | Compétition |
| **Social** | +10 % de Bits par ami dans le serveur (max +30 %), *Like* d'une tour (quotidien), « Setup du jour » affiché en hologramme dans le hub, bonus de groupe Roblox (+5 %), **LAN Party** : objectif coopératif de serveur (récompense pour tous) | Viralité |
| **Notifications** | Notifications d'expérience Roblox en opt-in (« Ton téléchargement est terminé ») — API à vérifier au moment de coder | J1 |

**KPIs visés** : J1 ≥ 30 %, J7 ≥ 10 %, J30 ≥ 3,5 %, session moyenne ≥ 25 min, 1ʳᵉ session ≥ 30 min, conversion payeurs de 2 à 4 %.

---

## 7. Monétisation (grille Robux)

### Game Passes (permanents)
| Pass | Prix | Justification |
|---|---|---|
| **Bits ×2** | 399 R$ | Standard du genre (300–500) ; le pass le plus vendu des tycoons |
| **VIP** (tag, lounge VIP du hub, thème RGB exclusif, +10 % de Chips quotidiens) | 249 R$ | Surtout statut et cosmétique |
| **Auto-Collect** | 149 R$ | Confort, pas de puissance brute |
| **+2 slots de Nanobots** | 199 R$ | Profondeur pour les collectionneurs |
| **Overclock Pro** (cooldown -50 %, durée +50 %) | 179 R$ | Récompense les joueurs actifs |
| **Hors ligne max** (8 h à 100 %) | 199 R$ | Rétention |
| **RGB Studio** (couleurs perso de la tour) | 99 R$ | Cosmétique pur, prix d'impulsion |

### Developer Products (consommables)
| Produit | Prix | Note |
|---|---|---|
| Pack de Bits S / M / L | 39 / 149 / 499 R$ | = 10 min / 1 h / 6 h de **ta** production actuelle (reste utile à tout stade) |
| Chips 100 / 550 / 1 200 / 2 600 | 49 / 249 / 499 / 999 R$ | Bonus de +0 / +10 / +20 / +30 % |
| Capsule premium ×1 / ×3 | 99 / 279 R$ | Probabilités affichées ; masquée si PolicyService l'interdit |
| **Server Boost** (×2 pour tout le serveur pendant 15 min) | 149 R$ | Achat social positif, annoncé dans le chat |
| Téléchargement instantané | 25 R$ | Petit confort |
| Reboot Boost (Firmware ×1,5 au prochain Reboot) | 149 R$ | |
| **Patch Pass premium** (saison) | 399 R$ | |
| **Starter Pack** (unique : Nanobot Rare + 300 Chips + 30 min de ×2) | 99 R$ | Proposé une fois après 10 min de jeu, sans faux timer |

### Autres
- **Premium Payouts** : les joueurs Premium ont +10 % de Bits et +20 Chips par jour. Le temps de jeu Premium est rémunéré par Roblox.
- **Pubs vidéo récompensées** (si l'expérience y est éligible ; vérifier la doc actuelle) : ×2 sur les gains hors ligne, 1 capsule gratuite par jour. Toujours facultatives.

### Règles éthiques (non négociables)
Pas de PvP, donc payer ne permet pas de battre qui que ce soit. Maximum **1 offre non sollicitée par session**, jamais pendant l'action. Aucun faux compte à rebours. Probabilités toujours visibles. Tout ce qui est payant reste atteignable en jouant (sauf les cosmétiques VIP). Achats traités de façon idempotente (`ProcessReceipt` + historique des `PurchaseId` dans le profil).

---

## 8. Direction artistique et UI

### 8.1 Palette (tokens, zéro couleur en dur)
| Token | Hex | Usage |
|---|---|---|
| `bg.base` | `#0B0F1A` | Fonds |
| `surface.glass` | `#141A2B` à 18 % de transparence | Panneaux en verre sombre |
| `stroke.soft` | `#FFFFFF` à 90 % de transparence | Contours 1 px |
| `text.primary` / `text.muted` | `#E8EBF4` / `#8A93A8` | Textes |
| `brand.anga` | `#F0565B` | **CTA principal** (rouge corail doux, repris du t-shirt de la mascotte) |
| `accent.cyan` | `#4FD1C5` | Info, énergie |
| `accent.violet` | `#8B7CFF` | Rareté, prestige |
| `currency.bits` | `#F6C453` | Bits |
| `currency.chips` | `#7FDBFF` | Chips |
| `state.success` / `state.warning` / `state.danger` | `#68D391` / `#F6AD55` / `#FC8181` | États |

Typo : **Builder Sans** (textes, lisible sur mobile) + une police display technologique pour les titres (Michroma si disponible dans l'enum Font, à vérifier). Espacements 4 / 8 / 12 / 16 / 24 / 32. Coins arrondis 12 (panneaux), 999 (pilules).

### 8.2 Écrans
- **HUD** (minimal) : haut gauche = Bits (compteur qui défile) + Chips ; haut centre = Benchmark ; bas = 3 boutons ronds (Boutique, Nanobots, Quêtes) + jauges ⚡/🌡️ ; toasts en haut à droite.
- **Menus** en panneau de verre coulissant (ease Quint Out, 0,28 s) avec fond flouté (DepthOfField désactivé sur mobile bas de gamme).
- **Écrans** : Upgrade de module (panneau contextuel en 3D au-dessus du pad, via BillboardGui/SurfaceGui), Boutique, Nanobots (inventaire + index), Quêtes / Pass, Quotidien, Reboot (arbre de Firmware), Classements, Paramètres (volumes, qualité graphique, reduced motion).
- **Transitions** : changement d'étage = « scanline » horizontale + teinte ColorCorrection qui glisse vers la palette de la zone (0,6 s) ; Reboot = écran BIOS stylisé avec barre de chargement (3 s, passable).
- **Game feel** : press scale 0,95 ; hover 1,04 ; compteurs qui roulent ; particules de Bits aspirées vers le compteur du HUD ; léger screen shake à l'achat d'un tier ; hitstop de 60 ms sur un virus zappé.
- **Mobile-first** : boutons ≥ 44 px, ScreenInsets CoreUISafeInsets, UIScale + UIAspectRatioConstraint, tests en 16:9, 19,5:9 et 4:3 (tablette). Système de style centralisé en **StyleSheets** (UI Styling) — vérifier l'état de l'API à l'étape 3.

### 8.3 Onboarding (le joueur s'amuse dans les 30 premières secondes)
1. **0 s** : spawn dans La Centrale, dans le noir. Seul un gros bouton POWER pulse. Bulle d'Anga : *« On est dans TON PC ! Allume-le ! »*
2. **5 s** : appui → son de boot, léger screen shake, **vague RGB qui monte toute la tour jusqu'à l'AI Core**, la musique entre en fondu.
3. **10 s** : les premiers paquets de données coulent vers le Collecteur. Un Beam lumineux guide au sol.
4. **15 s** : collecte → compteur qui roule + particules + son.
5. **25 s** : flèche vers le 1ᵉʳ upgrade (abordable tout de suite) → les paquets accélèrent.
6. **45 s** : 2ᵉ upgrade, puis la quête « Débloque la RAM » apparaît avec une barre de progression.
7. **~3 min** : la porte de la RAM s'ouvre (mini-cinématique caméra de 2 s, passable).

Chaque étape est loggée dans le funnel d'onboarding (AnalyticsService).

---

## 9. Audio
- **Musique adaptative** : un pad lo-fi / synthwave doux en boucle dans le hub + une couche (stem) par zone, en fondu enchaîné de 2,5 s au changement d'étage. Volume musique 0,35 par défaut. Sources : bibliothèque musicale sous licence du Creator Store (APM / Monstercat si toujours disponibles, à vérifier) ; mots-clés : « lofi », « chillwave », « ambient electronic », « synthwave calm ».
- **SoundGroups** Music / SFX / UI avec sliders séparés. Ducking de la musique (-4 dB) sur les gros gains.
- SFX doux : clic UI feutré, « blip » de collecte dont le pitch monte avec les combos, boot de PC, ventilateur ambiant (spatialisé), zap du Debugger.

---

## 10. Level design, éclairage, performance

### 10.1 Éclairage (valeurs de départ, ajustées zone par zone)
- **Lighting** : Technology = Future, ClockTime = 0, Brightness = 1, Ambient = (20, 22, 35), OutdoorAmbient = (30, 32, 50), EnvironmentDiffuseScale = 0,4, EnvironmentSpecularScale = 1, ExposureCompensation = 0,2, GlobalShadows = true.
- **Atmosphere** : Density = 0,35, Offset = 0,1, Color = (40, 35, 70), Decay = (15, 20, 40), Glare = 0, Haze = 1,2.
- **Bloom** (léger) : Intensity = 0,6, Size = 24, Threshold = 1,6.
- **ColorCorrection** : Brightness = 0,02, Contrast = 0,08, Saturation = 0,05, TintColor = (245, 245, 255) ; teinte tweenée par zone.
- **SunRays** : Intensity = 0,03, Spread = 0,6 (quasi invisible : on est dans un boîtier).
- Chemins guidés par des bandes de néon au sol vers le prochain objectif ; les zones verrouillées restent sombres et désaturées derrière une vitre.

### 10.2 Performance
- StreamingEnabled ; modèles de zone en ModelStreamingMode Atomic ; `Model:AddPersistentPlayer()` pour la tour du joueur.
- Pièces Anchored ; CanCollide / CanTouch / CanQuery désactivés sur le décor ; meshes réutilisés (instancing) ; RenderFidelity Automatic (LOD).
- Budget par étage : ≤ 150 k triangles visibles, ≤ 2 500 parts, ≤ 30 lumières dynamiques (Shadows seulement sur 3 ou 4 d'entre elles). Paquets de données et ventilateurs animés **côté client uniquement**.

---

## 11. Assets

Sources : **Creator Store** (créateurs vérifiés) → **Kenney / Quaternius / Poly Haven** (CC0) → les liens que tu m'as donnés → Sketchfab (CC0 / CC-BY seulement, avec crédit).
- **kitsblox.com/free**, **itch.io (tag roblox, free)** : vérifier la licence **de chaque pack** (tous ne sont pas autorisés en usage commercial).
- **BuiltByBit** : la plupart des ressources sont payantes, sous licence d'usage (utilisables dans ton jeu, **interdites de redistribution**). Ne jamais les committer dans un dépôt git.
- La liste précise par zone (mots-clés Creator Store, style visé, raison du choix) sera fournie à l'étape « Map ».

**Sécurité de tout modèle gratuit** (un script d'audit pour la barre de commande Studio sera fourni) : lister chaque Script / LocalScript / ModuleScript ; chercher `require(` suivi d'un ID numérique, `getfenv`, `setfenv`, `loadstring`, `string.reverse`, du code obfusqué (`\x`, longues chaînes), `MarketplaceService`, `TeleportService`, `HttpService` ; chercher les scripts cachés (noms vides ou trompeurs comme « Weld », « Vaccine »). Supprimer tout script inconnu. Laisser LoadStringEnabled désactivé et « Allow Third Party Sales / Teleports » désactivés dans les paramètres de sécurité.

---

## 12. Architecture technique

- **Rojo + git** dans ce dépôt (`AngAInOne/`), avec l'outillage **Rokit** : rojo, wally, selene, stylua, luau-lsp, lune.
- Packages : ProfileStore (sessions verrouillées), Trove (nettoyage), Signal.
- Luau `--!strict` partout, un module par responsabilité.

```
src/server/Services/   DataService, PlotService, EconomyService, ComponentService, PowerThermalService,
                       OverclockService, VirusService, NanobotService, DownloadService, QuestService,
                       DailyService, RebootService, LeaderboardService, MonetizationService,
                       AnalyticsService, SocialService
src/server/Security/   RateLimiter, RemoteGuard (types, distance, cooldown, fréquence)
src/shared/Config/     Zones, Components, Nanobots, Products, Quests (données pures)
src/shared/Economy/    EconomyFormulas (pures, testées avec Lune), NumberFormat
src/shared/Net/        Remotes (déclaration centralisée)
src/client/Controllers/ UI, HUD, Shop, Nanobots, Quests, Onboarding, Audio, ZoneTransition, Toast, Input
src/client/UI/Style/   StyleSheets + tokens
tests/                 Tests Lune (formules, pacing, validation des remotes)
```

**Schéma de données v1** : `{ Version, Bits, Chips, Firmware, Generation, UnlockedZones, ModuleLevels, Nanobots = { Owned, Equipped }, Daily = { Streak, LastClaim }, Quests, Downloads, Stats = { TotalBitsEarned, Playtime }, Tutorial, Settings, ProcessedReceipts, CreatedAt }`, avec des migrations versionnées.

**Ce que je peux vérifier moi-même ici** : typecheck strict, lint, format, tests unitaires Lune (économie, validation) et build Rojo du `.rbxl`, le tout en CI GitHub Actions.
**Ce que je ne peux pas faire ici** : lancer Roblox Studio ni un playtest. Le Studio MCP n'est pas connecté à cet environnement cloud. Chaque étape inclura donc une checklist de test Studio précise à dérouler de ton côté.

---

## 13. Analytics
- Funnel d'onboarding (`LogOnboardingStepEvent`) : les 7 étapes du §8.3 + 1ᵉʳ Nanobot + 1ʳᵉ quête.
- Économie (`LogEconomyEvent`) : chaque source et chaque sink de Bits et de Chips.
- Progression (`LogProgressionEvent`) : chaque zone, chaque Reboot, la Singularité.
- Événements custom : overclock réussi / raté, virus zappés, temps passé par zone, ouverture de la boutique → achat.

---

## 14. Roadmap (une fonctionnalité testable par étape)
1. Fondations : projet Rojo, outils, CI, DataService (ProfileStore), Remotes sécurisés, RateLimiter.
2. Économie de base : attribution des tours, modules, upgrades, collecteur, Bits, HUD minimal → **premier prototype jouable**.
3. Design system UI (StyleSheets, tokens), transitions, audio, onboarding de 30 s.
4. Zones et portes, Watts / Chaleur, éclairage par zone, **Map** (liste d'assets + script d'audit).
5. Overclock, virus, fragments.
6. Nanobots et capsules (probabilités + PolicyService).
7. Reboot / Générations / arbre de Firmware / Singularité et fin.
8. Rétention : quotidien, quêtes, téléchargements, hors ligne, classements, social.
9. Monétisation : passes, produits, ProcessReceipt, boutique.
10. Analytics, optimisation, QA multi-appareils, checklist de lancement.

## 15. Points ouverts
- Le logo et la mascotte : fichier à ajouter dans `AngAInOne/assets/branding/`, ou à uploader dans Studio en Decal (ID à me donner).
- À vérifier dans la doc officielle au moment de coder : UI Styling (StyleSheets), ombres UI natives, notifications d'expérience, pubs récompensées, disponibilité des polices, bibliothèque musicale.
