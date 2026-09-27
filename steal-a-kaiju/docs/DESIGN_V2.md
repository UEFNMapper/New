# Steal a Kaiju V2 : « tes kaijus servent à quelque chose »

Ce document est la synthèse de 4 analyses menées en parallèle :

- recherche sur les jeux Roblox qui gardent le mieux leurs joueurs en 2025-2026 (Grow a Garden,
  Steal a Brainrot, Pet Simulator 99, Plants vs Brainrots, Bee Swarm, Fisch, 99 Nights…) ;
- critique minute par minute des 30 premières minutes en solo ;
- conception de modes de jeu actifs ;
- conception d'une progression solo sur le long terme.

## Le constat

En solo, la V1 est un simulateur de boutique : on marche jusqu'au cratère, on paie un œuf, on
attend. Le vol, qui fait le sel du genre, n'existe pas sans autres joueurs. Après 10 minutes,
86 % des œufs qui tombent ne servent plus à rien, et rien à l'écran ne dit quel est le prochain
objectif.

La leçon des tops Roblox : **ce qu'on collectionne doit aussi être ce avec quoi on joue**, et
il faut toujours un objectif visible à 1 minute, 5 minutes, 1 heure et 1 semaine.

## La boucle V2 (expliquée à un enfant de 10 ans)

> Attrape des œufs qui tombent du ciel. Tes kaijus grandissent et te rapportent de l'argent.
> Ils **défendent ton île** contre les monstres sauvages, et tu peux **devenir ton kaiju** pour
> écraser une ville en jouet. Monte de niveau pour ouvrir de **nouveaux mondes** remplis de
> kaijus plus rares.

| Échelle | Ce que fait le joueur |
|---|---|
| 10 secondes | Bonker des envahisseurs, écraser des immeubles, creuser un trésor avec son compagnon, attraper un œuf |
| 5 minutes | Tenir une vague de siège, faire 3 étoiles dans un quartier Rampage, monter d'un niveau |
| 1 heure | Ouvrir un nouveau monde, obtenir un Titan, première Évolution |
| 1 semaine | Compléter le Kaijudex (46 espèces), les 6 recettes secrètes, le monde Cosmic Rift |

## Les nouveautés

### 1. Niveau du joueur (la colonne vertébrale)

- Chaque action donne de l'XP : éclosion (selon la rareté), croissance, nouvelle espèce (x5),
  vague de siège, étoiles Rampage, trésor, quête, vol.
- Chaque niveau donne des gemmes, +1 % de cash, et parfois un déblocage : **les nids viennent
  des niveaux** (plus de menu d'achat), les mondes, la fusion, l'évolution.
- Une barre « NEXT GOAL » toujours visible dit ce que débloque le prochain niveau.

### 2. Cinq mondes

Le cratère reste le centre social. Des portails mènent à 4 îles-mondes visibles à l'horizon.

| Monde | Accès | Œufs | Mutation locale |
|---|---|---|---|
| Kaiju Crater | départ | surtout Common / Rare | Gold |
| Candy Coast | niveau 5 + péage | Rare / Epic | Rainbow |
| Frost Peaks | niveau 12 + péage | Epic / Legendary | Diamond |
| Volcano Core | niveau 18 + Évolution 1 | Legendary / Mythic | Blood Moon |
| Cosmic Rift | niveau 30 + Évolution 4 | Mythic / Celestial | Galaxy, Shadow |

Chaque monde a son décor, sa lumière, ses espèces (10 nouvelles espèces ajoutées) et sa
mutation. Le météore perso de l'île tombe depuis le meilleur monde débloqué.

### 3. Défense de l'île (Siege)

Toutes les 2 min 30, une vague de mini-kaijus sauvages entre par le portail de ton île et
serpente entre les nids vers le réacteur. **Tes kaijus tirent dessus** (portée et dégâts selon
leur taille et leur rareté) et tu bonkes ceux qui passent. Un envahisseur qui atteint le
réacteur vole une partie du cash stocké : bonke-le pour le récupérer. Les kaijus ne sont
jamais volés par les PNJ. Toutes les 5 vagues, un Alpha lâche un œuf sauvage.

### 4. RAMPAGE : deviens ton kaiju

Un portail sur l'île t'envoie dans une ville en jouet privée. Pendant 75 secondes, tu contrôles
une copie géante de ton kaiju : piétinement, rayon rugissant, combos, tanks-jouets à esquiver.
1 à 3 étoiles par quartier, 5 quartiers. Ça rapporte bien plus que l'attente, **fait grandir
le kaiju utilisé**, et les immeubles dorés peuvent cacher un œuf.

### 5. Compagnon (Buddy)

Un de tes kaijus te suit en version mini. Il attire les orbes et flaire un trésor toutes les
50 secondes : tu cours creuser (cash, gemmes, nourriture, parfois un œuf). Il gagne des niveaux
et aide pendant les sièges.

### 6. Simplifications

- Tutoriel : œuf, cash, météore, **défendre l'île**, **Rampage**, **trésor du compagnon**.
  Plus d'attente de 20 s pour « voler un kaiju » en serveur vide.
- Quêtes : toutes faisables en solo.
- Fusion : recette secrète exploitable dès la minute 6 corrigée (ingrédients plus rares,
  revenus des Secrets rééquilibrés).
- La mutation Shadow devient trouvable (Cosmic Rift).
- Le Colossal Raid fonctionne aussi en solo (PV adaptés au nombre de joueurs).
- Menus : récompenses regroupées dans un seul bouton REWARDS, nouveau bouton WORLDS.

## Le vol reste le piment multijoueur

Tout ce qui précède marche seul. Avec d'autres joueurs, on garde le vol, les boucliers,
le bonk entre joueurs et les Titans à porter à deux.
