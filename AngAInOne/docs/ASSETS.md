# Assets, licences et sécurité

## 1. Choix actuel : un monde 100 % procédural et cohérent

Toute la map (hub « carte mère », 6 tours de 7 étages, machines, terminaux, pads) est générée par le code (`src/server/World/MapBuilder.luau`) à partir d'une **palette unique** (`Config/Theme.luau` + couleurs des zones), de matériaux Roblox cohérents (Metal, DiamondPlate, Glass, Neon, Foil) et d'un éclairage Future.

**Pourquoi ce choix ?** J'ai interrogé l'API du Creator Store en filtrant : créateur vérifié, **0 script**, moins de 60 000 triangles, plus de 80 % de votes positifs. Constat :
- les résultats sont de styles très disparates (réaliste, cartoon, low-poly) : impossible d'obtenir un rendu « dernier cri » homogène en les mélangeant ;
- beaucoup reprennent des licences protégées (Star Wars, Ben 10, Murder Drones, Wheel of Fortune…), **à bannir absolument** (risque de modération et de retrait du jeu).

Le procédural garantit une échelle et une palette uniques, zéro backdoor, et des performances maîtrisées (≈ 250 pièces par tour, décor sans collision ni requêtes, lumières sans ombres sauf exception).

## 2. Remplacer une pièce procédurale par un modèle (sans casser le jeu)

Chaque machine est un `Model` nommé `Z{zone}M{slot}` avec l'attribut `ModuleId`, dans `Workspace.World.Towers.TowerN.Floors.FloorK.Modules`. Pour habiller une machine avec un vrai modèle :
1. Importe le modèle et **audite-le** (section 4).
2. Supprime tous ses scripts, passe ses pièces en `Anchored = true`, `CanCollide = false`, `CanTouch = false`, `CanQuery = false`.
3. Dans `MapBuilder.luau`, fonction `buildMachine`, remplace la silhouette de la zone par un clone de ton modèle, rangé dans `ServerStorage` (ex. `ServerStorage.Assets.CpuDie`), et garde la `Base`, le `LabelAnchor` et au moins une pièce taguée `TierGlow` : ce sont eux qui portent le prompt, l'étiquette de niveau et la couleur du tier.
4. Relance les tests : `./scripts/verify.sh`.

## 3. Sources d'assets

| Source | Licence / règle | Usage conseillé |
|---|---|---|
| **Roblox Creator Store** | Libre d'usage dans Roblox. Vérifier « créateur vérifié », **scripts = 0**, votes | Accessoires, décor |
| **Kenney.nl** | CC0 (aucun crédit requis) | Kits Space/Sci-fi, UI |
| **Quaternius** | CC0 | « Sci-Fi Essentials », « Modular Sci-Fi » |
| **Poly Haven** | CC0 | Textures PBR (métal brossé, fibre de carbone) pour SurfaceAppearance |
| **kitsblox.com/free** | Licence propre à chaque kit : **lire la page de chaque kit** avant usage commercial | Kits de construction |
| **itch.io (tag roblox, free)** | Licence propre à chaque pack : beaucoup sont « usage personnel uniquement » | Seulement si la page dit « commercial use allowed » |
| **BuiltByBit** | Ressources majoritairement **payantes**, licence d'utilisation (pas de redistribution) | Jamais dans un dépôt git public |
| **Sketchfab** | Uniquement CC0 ou CC-BY | CC-BY : crédit obligatoire de l'auteur (à ajouter dans Menu > Réglages > crédits) |

### Candidats propres trouvés dans le Creator Store (0 script, créateur vérifié)
| Zone | ID | Modèle | Tris | Votes |
|---|---|---|---|---|
| CPU (décor cristaux) | `157006174` | Awesome Crystal Cluster Mesh | 417 | 190 👍 / 10 👎 |
| CPU (décor) | `8147307625` | Light Blue Crystal Geode | 558 | 39 / 1 |
| Cryo Tower (tuyauterie) | `9370327334` | industrial pipes w/ valve | 33 648 | 46 / 4 |
| Nanobots (base visuelle) | `980213529` | Drone (créateur : **Roblox**) | 1 792 | 51 / 9 |
| Data Vault (porte) | `8166287648` | Bank Vault Door | 4 946 | 26 / 4 |

Insertion : Toolbox > recherche par ID, ou `game:GetService("InsertService"):LoadAsset(ID)` dans la barre de commande. **Toujours auditer avant usage.**

### Audio (déjà intégré, licences Roblox)
Musiques de la **bibliothèque APM Music** (compte APMOfficial) et effets **Pro Sound Effects**. Ce sont des catalogues sous licence pour toutes les expériences Roblox. Les IDs et titres sont dans `src/shared/Config/Audio.luau`. Pour changer une piste, remplace l'ID par un autre venant des mêmes catalogues. J'ai écarté les sons d'utilisateurs qui reprennent des jeux connus (Subway Surfers, Slime Rancher…).

## 4. Sécurité : auditer tout modèle gratuit

Un modèle gratuit peut contenir une **backdoor** : un script caché qui donne le contrôle de ton jeu à quelqu'un d'autre. Procédure :

1. **Avant d'importer** : dans le Creator Store, regarde « Contient des scripts ». Pour un décor, la réponse doit être **non**.
2. **Après import** : sélectionne le modèle, ouvre la barre de commande (Affichage > Barre de commande), colle le contenu de [`tools/AuditModels.luau`](../tools/AuditModels.luau) et appuie sur Entrée. Le rapport liste chaque script et signale :
   - `require(123456)` : chargement de code externe (**backdoor classique**) ;
   - `getfenv` / `setfenv` / `loadstring` / `string.reverse` / séquences `\x..` : obfuscation ;
   - `MarketplaceService`, `TeleportService`, `HttpService`, `InsertService`, `Kick(` : actions dangereuses ;
   - noms trompeurs (« Vaccine », « Anti-lag », « Weld », nom vide…).
3. **Supprime tout script** d'un modèle de décor. Dans l'Explorer, filtre avec `ClassName:Script` pour les repérer.
4. **Paramètres du jeu > Sécurité** : `LoadStringEnabled` désactivé (par défaut), HTTP et ventes/téléportations tierces désactivés.
5. Le code du jeu est lui-même protégé : aucune logique critique côté client, toutes les requêtes validées par `RemoteGuard`.
