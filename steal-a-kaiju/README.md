# 🦖 STEAL A KAIJU

> **Tes monstres grandissent en temps réel. Plus ils sont gros, plus ils rapportent…
> et plus tout le serveur les voit.**

Jeu Roblox complet de type « Steal a … » : des œufs de kaiju tombent en météores, tu les
fais éclore et grandir sur ton île, ils rapportent du cash… et les autres joueurs peuvent
venir te les voler. Les Titans et les Colosses sont si lourds qu'il faut **être deux** pour
les porter.

Tout le jeu est écrit en code (Luau + Rojo) : carte, modèles 3D des 36 kaijus, interface,
effets, sons originaux.

![Île d'un joueur](docs/previews/island.png)

## Ce qu'il y a dans le jeu

| Système | Détail |
|---|---|
| **Pluie de météores** | Un œuf tombe toutes les ~14 s dans le cratère (premier arrivé, premier servi), plus un météore perso sur ton île toutes les 2 min 30 |
| **36 kaijus** | 7 raretés (Common → Celestial + 6 SECRETS obtenus uniquement par fusion), 9 archétypes, accessoires, animations |
| **Croissance** | 5 stades (Baby → Teen → Adult → Titan → Colossus), le modèle grandit physiquement, revenus x1 → x40, croissance même hors ligne |
| **Mutations** | Gold x2, Diamond x3, Blood Moon x4, Rainbow x5, Radioactive x6, Galaxy x8, Shadow x10 |
| **Vol** | Attraper un kaiju chez un autre, le ramener chez soi ; ralentissement selon la taille ; Titans/Colosses à deux avec partage du butin |
| **Défense** | Bouclier (dôme), protection des nouveaux joueurs, Bonker (marteau) qui fait lâcher prise, alarme |
| **Économie** | Réacteur à cash (collecte), nids à débloquer, 5 améliorations, nourriture, vente, gains hors ligne |
| **Évolution** | 25 niveaux de rebirth (multiplicateur, chance, gemmes, œuf offert) |
| **Labo de fusion** | 6 recettes secrètes + fusions aléatoires (probabilités affichées) |
| **Événements** | Meteor Shower, Blood Moon, Radioactive Storm, Golden Hour, Cosmic Aurora, Cash Stampede, **Colossal Raid** (boss à combattre ensemble) |
| **Rétention** | Série quotidienne (7 jours), 10 cadeaux de temps de jeu, 3 quêtes par jour, roue de la fortune, codes, Kaijudex (+1 % de cash par espèce), bonus amis / groupe / Premium, classements mondiaux |
| **Boutique Premium** | 9 Game Passes + 15 produits (packs, boosts de serveur, événements achetables) |
| **Conformité 2026** | Probabilités affichées pour tout le hasard payant ; achats aléatoires masqués si `PolicyService` l'impose |
| **Anti-triche** | Serveur autoritaire, validation de chaque requête, limitation de débit, anti-téléportation pendant un vol |

Captures d'interface (rendues depuis le vrai code client) : [`docs/previews/ui/`](docs/previews/ui/)

## Lancer le jeu dans Roblox Studio

1. Ouvre **`release/StealAKaiju.rbxlx`** dans Roblox Studio (Fichier → Ouvrir).
2. **Game Settings → Security → Enable Studio Access to API Services** : active-le pour que les
   sauvegardes fonctionnent (sinon le jeu tourne avec une sauvegarde simulée, sans erreur).
3. Appuie sur **Play**. Pour tester le vol à plusieurs : onglet **Test → Clients and Servers**,
   choisis 2 ou 3 joueurs, puis **Start**.
4. Dans Studio, les Game Passes et produits non configurés (`Id = 0`) sont **offerts
   gratuitement pour les tests**. En ligne, ils affichent « Coming soon ».

### Pour développer avec Rojo (optionnel)

```bash
rojo serve        # puis « Connect » dans le plugin Rojo de Studio
rojo build default.project.json -o release/StealAKaiju.rbxlx
```

## Avant de publier : ta checklist

1. **Game Settings → Places → Max Players = 8** (8 îles par serveur).
2. **Monétisation** : crée les Game Passes et Developer Products sur le Creator Hub, puis colle
   leurs identifiants dans `src/shared/Config/Monetization.luau` (champ `Id`). Les prix
   conseillés sont indiqués.
3. **Sons originaux** : importe les 46 fichiers de `assets/audio/` (Asset Manager → Bulk Import),
   puis colle chaque identifiant dans `src/shared/Config/Sounds.luau` (champ `Uploaded`).
   En attendant, le jeu utilise des sons publics de la bibliothèque Roblox. Voir
   `assets/audio/README.md`.
4. **Groupe Roblox** : mets l'identifiant de ton groupe dans `src/shared/Config/Rewards.luau`
   (`GroupId`) pour activer la récompense de groupe (+5 % de cash).
5. **Codes** : modifie la liste `Rewards.Codes` à chaque mise à jour.
6. **Questionnaire de maturité** : violence « cartoon » légère (bonk), pas de sang réaliste.
7. Remplis l'icône et les miniatures avec de vraies captures du jeu dans Studio.

Tous les réglages chiffrés (prix, temps, raretés, événements) sont regroupés dans
`src/shared/Config/`.

## Tests réalisés

Roblox Studio ne tourne pas sur Linux, donc j'ai construit un **simulateur Roblox headless**
(`tests/sim/`) qui exécute le **vrai code** du serveur et du client, avec une horloge
virtuelle et une validation de chaque propriété, méthode et événement contre l'API Roblox
officielle (919 classes).

```bash
./tools/test_all.sh   # environ 1 minute
```

| Test | Résultat |
|---|---|
| Analyse de types Luau (luau-lsp) + appels entre services + méthodes de l'API Roblox | ✅ 0 erreur |
| Tests unitaires (formules, tirages, croissance, quêtes, 36 modèles × 8 mutations) | ✅ 13/13 |
| Playtest serveur : 3 joueurs, éclosion, collecte, météores, vol, casse à deux, bonk, bouclier, boutique, récompenses, fusion, évolution, boss, événements, reconnexion, 2 h de jeu | ✅ 100/100 |
| Playtest client : vrai client contre vrai serveur, 10 écrans ouverts et tous leurs boutons cliqués, cinématiques, 7 événements, 30 min | ✅ 33/33, 0 erreur |
| Équilibrage : un bot joue 6 h | Évolution 1 vers 30 min, Légendaire vers 12 min, Évolution 5 vers 4 h |

Ces tests ont trouvé et fait corriger de vrais bugs qui auraient cassé le jeu dans Roblox,
notamment une propriété d'éclairage non modifiable par script (le serveur aurait planté au
démarrage) et un écran de chargement qui serait resté bloqué.

**Ce que seul un test dans Studio peut confirmer** : le ressenti des contrôles et de la
caméra, la physique du recul, les performances sur mobile, l'affichage réel des polices et
emojis, et le chargement des sons.

## Organisation du code

```
src/shared/   config (kaijus, économie, événements, boutique…), logique pure, KaijuBuilder
src/server/   12 services (données, îles, kaijus, météores, vol, événements, récompenses…)
src/client/   HUD, 10 fenêtres, cinématiques, rendu 3D des kaijus et météores, effets
src/first/    écran de chargement
assets/audio/ 42 effets + 4 musiques originaux (synthétisés, libres de droits)
tests/        tests unitaires + simulateur Roblox headless + playtests
tools/        vérifications, rendus d'aperçu, générateur audio
```

Le contrat client/serveur complet (actions, événements, attributs) est dans
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Crédits

- Sauvegarde : [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) (Apache 2.0).
- Sons et musiques : originaux, générés par `tools/audio/generate_audio.py`.
- Les polices de `tools/render/fonts/` (OFL / Apache) ne servent qu'aux rendus d'aperçu ; le
  jeu utilise les polices intégrées de Roblox.
