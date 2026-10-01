# AngAInOne — « Opération Anti-Lag » · Scénario v2

## 1. L'histoire en une minute

**Ce soir, Anga lance le plus gros live de l'histoire d'AngaTV.** Mais une heure avant, catastrophe :
son PC **rame**. 3 images par seconde, 999 ms de ping, des freezes, des pop-ups partout, un écran
bleu… Le coupable : **LAGZ**, un virus qui se nourrit de la puissance des PC.

Anga lance l'app **AngAInOne** en **« Mode Intervention »** : elle miniaturise des volontaires
(les joueurs) et les envoie **à l'intérieur de la tour**, composant par composant, pour chasser les
sbires de LAGZ… jusqu'à la puce IA, tout en haut, où LAGZ a installé son cœur.

Chaque monde nettoyé **répare un symptôme** : le PC redevient plus rapide, la lumière revient, les
ventilateurs tournent rond. Quand LAGZ est vaincu, le PC tourne à **144 FPS** : **le live peut
commencer !**

## 2. Personnages

| Personnage | Rôle | Look |
|---|---|---|
| **Anga** | Guide à la radio (boîte de dialogue), encourage, explique les pièges en une phrase. | Mascotte AngaTV (barbe blonde, t-shirt rouge « A »). |
| **LAGZ** | Grand méchant. Se moque, déclenche des **incidents**, boss final en 3 phases. | Blob violet glitché, couronne en roue de chargement, yeux pixelisés. |
| **Sparky** | Sbire du monde 1 : court-circuit. | Petite étincelle jaune colérique. |
| **Pop-Up** | Sbire du monde 2 : pub envahissante. | Fenêtre de pub avec des yeux et une croix ✕. |
| **Corrupto** | Sbire du monde 3 : fichiers corrompus. | Cube de pixels rose/noir « texture manquante ». |
| **Dusty** | Sbire du monde 4 : poussière qui bouche les ventilos. | Boule de poussière grise. |
| **Minor** | Sbire du monde 5 : crypto-mineur qui fait chauffer le CPU. | Mini-robot avec une pioche. |
| **Freezy** | Sbire du monde 6 : écran figé. | Glaçon cubique avec un sablier. |
| **L'app AngAInOne** | Le QG : écran géant du lobby ; chaque monde nettoyé coche une section de l'app. | Interface Fluent gris + violet. |

Ton : drôle, jamais effrayant (8–14 ans). Les sbires sont mignons-méchants. Aucun texte long :
une réplique = une phrase.

## 3. La « Performance du PC » (le fil rouge visible)

Un petit widget toujours visible (HUD) montre l'état du PC d'Anga **pour le joueur** :

| Mondes nettoyés | FPS | Ping | Température | Ambiance de la tour |
|---|---|---|---|---|
| 0 | 3 | 999 ms | 97 °C | Lumières qui clignotent, glitchs violets partout |
| 1 | 12 | 650 ms | 92 °C | Le courant revient (monde 1 éclairé) |
| 2 | 25 | 420 ms | 88 °C | |
| 3 | 40 | 250 ms | 80 °C | |
| 4 | 60 | 120 ms | 65 °C | Les ventilateurs tournent rond |
| 5 | 90 | 60 ms | 55 °C | |
| 6 | 120 | 25 ms | 48 °C | |
| 7 (LAGZ vaincu) | 144 | 8 ms | 40 °C | Tour entière en RGB propre, « LIVE » s'allume |

**Mondes infectés / nettoyés** : tant qu'un monde n'est pas nettoyé (pour ce joueur), il est
**infecté** : flaques de glitch violettes, fenêtres de pub flottantes, composant terne, néons rouges
d'alerte. Une fois le terminal réussi, le monde passe en **version propre** : le composant brille
à sa couleur, les ventilateurs tournent, le glitch disparaît. On le voit en regardant en bas.

## 4. Les incidents de LAGZ (le virus agit sur le décor et les épreuves)

Pendant une ascension, LAGZ déclenche des **incidents** dans le monde où se trouvent des joueurs
(toutes les 60 à 120 s, jamais pendant un mini-jeu). Chaque incident est **annoncé 3 s avant**
(« ⚠ LAGZ prépare un FREEZE ! ») et dure 5 à 8 s. Chaque monde a son incident vedette, et le monde 7
les mélange tous.

| Incident | Effet sur le jeu | Effet visuel / son |
|---|---|---|
| **FREEZE** | Tous les pièges du monde **se figent** : une fenêtre pour passer ! | Écran teinté bleu glace, bruit de disque rayé, sablier. |
| **LAG SPIKE** | Les pièges bougent **en saccades** (le temps avance par à-coups) : timing plus dur. | Ping du HUD qui monte en flèche, image qui « rame ». |
| **BLACKOUT** | Coupure de courant : l'éclairage s'éteint, seuls les **néons et les dangers** restent visibles ; les plateformes « alimentées » disparaissent. | Noir + grésillement, clignotement de reprise. |
| **POP-UP STORM** | 3 à 5 fenêtres de pub couvrent l'écran : il faut **toucher les ✕** pour les fermer. | Sons de notification, fenêtres qui rebondissent. |
| **CORRUPTION** | Les dalles corrompues **s'inversent** (solides ↔ traversables). | Flash rose/noir « texture manquante ». |
| **SURCHAUFFE** | Toutes les bouches de chaleur s'activent en même temps, le vent des ventilateurs double. | Teinte rouge, distorsion, alarme douce. |

## 5. Les 7 mondes

Chaque monde a **son propre parcours** (plus d'anneau identique partout), **2 pièges signature
nouveaux**, un **incident vedette**, un **sbire** qui garde le terminal, et une **épreuve finale**
(5ᵉ étape) qui combine tout. Les étapes 1 à 4 introduisent un piège à la fois, puis le combinent.

### Monde 1 · Alimentation (le bloc d'alimentation) — « Le PC s'éteint tout seul »
- **Parcours** : sous le carénage du bloc d'alimentation, on court **sur les câbles tressés
  géants**, on saute de condensateur en condensateur, puis on traverse la grille du ventilateur du PSU.
- **Pièges** : décharges (Zapper), condensateurs-trampolines, **Rails de surtension** (une
  impulsion électrique court le long des câbles : sauter au bon moment), **Plateformes alimentées**
  (solides seulement quand le courant passe, au rythme d'un voyant).
- **Incident vedette** : BLACKOUT. **Sbire** : Sparky.
- **Épreuve de la salle** : **Le Démarrage infecté** (portes du Démarrage + leviers, voir §10).
- Anga : « Le courant saute ! Marche sur les plateformes quand elles sont allumées. »

### Monde 2 · Memory Lanes (RAM) — « Mémoire saturée, 200 onglets ouverts »
- **Parcours** : un **canyon vertical** entre les barrettes de RAM ; on grimpe sur les puces
  mémoire, on traverse d'une barrette à l'autre.
- **Pièges** : barrettes qui écrasent (Crusher), tapis de données, **Pluie d'onglets** (des
  fenêtres de navigateur tombent en rafale et restent un instant comme plateformes), **Fuite
  mémoire** (un flot de données violet MONTE derrière toi : section de grimpe chronométrée).
- **Incident vedette** : POP-UP STORM. **Sbire** : Pop-Up.
- **Mécanique** : la **jauge de RAM** se remplit et ralentit la marche ; gros boutons « Libérer la RAM ».
- **Épreuve de la salle** : **La RAM saturée** (barrettes en A2 + B2, voir §10).

### Monde 3 · Data Vault (SSD) — « Fichiers corrompus »
- **Parcours** : une **grande grille de cellules NAND** (damier en hauteur), façon labyrinthe à
  étages, avec des tiroirs de SSD qui sortent du mur.
- **Pièges** : **Dalles corrompues** (texture manquante rose/noir qui clignote), **Défragmenteur**
  (blocs qui coulissent sur une grille comme un taquin), plateformes qui s'effacent, pistons.
- **Incident vedette** : CORRUPTION. **Sbire** : Corrupto.
- **Épreuve de la salle** : **L'invasion du Bloatware** (aspirer, puis vider la Corbeille, voir §10).

### Monde 4 · Cryo Tower (Refroidissement) — « Surchauffe, ventilos bouchés »
- **Parcours** : **à travers le radiateur** (couloirs entre les ailettes), puis **dans les tubes
  transparents** du watercooling, et entre les pales des gros ventilateurs.
- **Pièges** : vent des ventilateurs, glace glissante, **Boules de poussière** qui roulent,
  **Jets de vapeur** (bouches de chaleur), pales.
- **Incident vedette** : SURCHAUFFE. **Sbire** : Dusty.
- **Mécanique** : la **jauge de chaleur** (arrêt thermique à 100 °C), les ventilateurs à relancer et le
  **ventilo propulseur** qui fait décoller jusqu'à une corniche à Bits bonus.
- **Épreuve de la salle** : **La surchauffe** (sol de lave, socles, ventilateurs, voir §10).

### Monde 5 · The Core (CPU) — « Processeur à 100 %, un crypto-mineur ! »
- **Parcours** : une **spirale** qui monte autour du ventirad à caloducs, puis un sprint sur la
  **grille de broches** du socket.
- **Pièges** : lasers, **Pioches du mineur** (pendules géants), **Plateformes en latence**
  (elles se déplacent avec un temps de retard, par à-coups), **Roue de chargement** (anneau de
  plateformes qui tourne comme l'icône de chargement).
- **Incident vedette** : LAG SPIKE. **Sbire** : Minor.
- **Mécanique** : trois **processus inutiles** bloquent le chemin (« Fin de tâche »).
- **Épreuve de la salle** : **Défense du CPU**, la tour de défense du guide en 3D (voir §10).

### Monde 6 · Render Canyon (GPU) — « Écran figé, artefacts »
- **Parcours** : un canyon **le long de la carte graphique**, entre ses 3 ventilateurs géants,
  puis sur une **piste de pixels**.
- **Pièges** : pales géantes, lasers de rendu, **Pixels morts** (le sol s'éteint en vagues),
  **Pont de chargement** (un pont qui se remplit comme une barre de progression… et parfois bloque).
- **Incident vedette** : FREEZE. **Sbire** : Freezy.
- **Mécanique** : de brefs **artefacts graphiques** tant que la carte graphique est infectée.
- **Épreuve de la salle** : **La carte graphique corrompue** (pilote + écran à 170 Hz, voir §10).

### Monde 7 · Neural Nexus (Puce IA) — Le repaire de LAGZ
- **Parcours** : plateformes flottantes autour du cerveau holographique, puis l'**arène du boss**.
- **Pièges** : virus patrouilleurs, **Curseur géant** (une main-curseur qui vient cliquer là où tu
  te trouves), **Pare-feu mobiles** (murs percés qui avancent), un peu de tout.
- **Incidents** : tous, plus souvent.
- **Épreuve de la salle** : **L'enquête des Sessions de jeu**, avant le combat (voir §10).
- **BOSS LAGZ** (3 phases, 1 à 2 min) :
  1. LAGZ tire des lasers et envoie le curseur géant : survivre en courant autour de l'arène.
  2. Le sol se fragmente (plateformes qui s'effacent) et des virus sortent : atteindre les 3
     **prises antivirus** (boutons au sol) pour lui retirer son bouclier.
  3. Salle du terminal : l'**enquête** (remonter la chaîne jusqu'à LAGZ, le mettre en quarantaine),
     puis le **Firewall boss** (mini-jeu) pendant que LAGZ glitche l'écran.
- **Fin** : « Le PC tourne à 144 FPS ! » — le moniteur du bureau affiche le live d'AngaTV qui
  commence, le chat défile (« GG ! », « merci l'antivirus ! »), Anga remercie le joueur par son pseudo.

## 6. Le lobby : la chambre d'Anga

On apparaît **sur le bureau d'Anga**, minuscule, devant la tour PC géante à panneau vitré :
- l'**écran d'Anga** affiche « LIVE DANS 59:00 » et le chat qui s'impatiente ;
- le **Miniaturiseur AngAInOne** (le portail de départ, pad JOUER) ;
- l'écran de l'app AngAInOne (progression du joueur), les classements, la boutique, l'arcade ;
- décor : clavier mécanique RGB, souris, tasse, micro de stream, lampe, câbles ;
- le **Stream Deck** : trois touches font quelque chose (pet du mini-Anga, confettis, mode lent) ;
- la **touche Suppr** posée devant le portail : elle ouvre le **BIOS caché** (voir §8).

## 7. Difficulté et rejouabilité

- **Courbe** : monde 1 = tutoriel ; chaque étape n'introduit qu'une idée ; la 5ᵉ étape combine.
  Écarts ≤ 6,5 studs, fenêtres de sécurité ≥ 1,2 s au monde 1, ≥ 0,8 s au monde 7.
- **Clés USB dorées** : 3 par monde (21), cachées sur des **chemins difficiles** facultatifs.
  Toutes les clés d'un monde → une traînée ; les 21 → titre « Anti-Lag Légendaire ».
- **Chrono** et classements ; incidents différents à chaque passage.

## 8. Fidèle à la vraie app, et des clins d'œil (guide « AngAinOne × Roblox »)

Tout ce qui suit vient du guide de l'univers AngAinOne (vocabulaire, pages de l'app, easter eggs) ;
l'app **détecte, diagnostique et répare** : jamais « enlève les virus », jamais de faux lien.

- **Conseils « vraie vie »** : chaque monde porte un conseil d'une phrase (`Tower.Tip`) et le raccourci
  correspondant dans l'app (`Tower.AppTip`) : panneau « 💡 CONSEIL VRAIE VIE » dans la salle du
  terminal, puis dit par l'assistant de l'app (bulle « AIO ») après le nettoyage. La fin de l'ascension
  a le sien (`Tower.VictoryTip`).
- **Vocabulaire de l'app** dans les répliques : *le parc* (tous les PC des utilisateurs), *les à-coups*
  et le *1 % low* (pic de LAG), *le coupable* (analyse du boss), *le Service* (le PNJ du lobby).
- **Boss façon écran bleu** : les phases de LAGZ s'annoncent par des codes d'erreur
  (`IRQL_NOT_LESS_OR_EQUAL`, `MEMORY_MANAGEMENT`, `CRITICAL_PROCESS_DIED`) ; vaincu, il se « dumpe » et
  la page Plantages l'analyse (« coupable = LAGZ, quoi faire : nettoyé »).
- **Incident « Mise à jour »** (monde 7) : voile bleu, `:(`, pourcentage qui grimpe, « ne pas éteindre
  votre ordinateur » pendant 5 s ; les pièges continuent.
- **Écran de fin = Test de perf** : hexagone avec la mascotte, quatre petits hexagones (Processeur =
  vitesse, Carte graphique = chutes, Mémoire = Bits ramassés, Stockage = clés USB), score sur 100,
  emblème (Rodage, Solide, Élite, Titan) et le pseudo du joueur en néon ; puis le rapport.
- **Badges** (`Config/Badges.luau`, `AwardsService`) : un par monde nettoyé et un pour la victoire,
  IDs à créer sur le site puis à coller (0 = désactivé).

### Easter eggs (`World/Tower/EasterEggs.luau`, réactions dans `Controllers/Interactions`)
| Où | Quoi | Réaction |
|---|---|---|
| Lobby, derrière la tour | **Le câble HDMI débranché** (« Brancher ») | ding, « Avez-vous essayé de le rebrancher ? » |
| Lobby, près des bornes | **Le Service**, support qui ne dort jamais (« Parler ») | « Avez-vous essayé de redémarrer ? » ; à la 10e fois il redémarre lui-même |
| Lobby, derrière le spawn | **Le pseudo en néon** | ton pseudo Roblox en néon violet (`NeonName`) |
| Monde 3, salle du terminal | **La Corbeille** | `devoirs_finaux_VRAIMENT_FINAL_v3.docx`, `screenshot_win_ranked.png`, `RAM_download_2go.exe` (le virus) |
| Monde 4 | **0 °C** | immobile 2 minutes → bloc de glace, « idle = température minimale » |
| Monde 5, salle du terminal | **La pâte thermique** (« Appliquer ») | une fois : parfait ; deux fois : le processeur disparaît sous la pâte |
| Monde 6, salle du terminal | **RGB = +10 FPS** (« Activer ») | +10 de vitesse de marche pendant 10 s, levier arc-en-ciel |
| Monde 7, salle du terminal | **L'escargot « Wi-Fi de l'hôtel »** | transporte les paquets (ping 999), on peut monter dessus |
| Monde 7, toit de la salle | **AngATV, le dev caché** (« Parler ») | « Tu m'as trouvé. Le PC est entre de bonnes mains. » |
| Lobby, devant le portail | **La touche Suppr** (« Entrer dans le BIOS ») | salle bleue « Setup Utility » au-dessus de la chambre : note du BIOS, « À faire d'abord », QR code géant de l'app (anga.tv), F10 pour sortir |
| Lobby, Stream Deck | **Trois touches** | « Pet ! » (le mini-Anga est content), confettis, mode lent 6 s (« un PC sans SSD ») |

## 9. Les mécaniques « PC » et les rôles d'équipe

Sur le parcours, plusieurs mondes ont une mécanique qui reprend **un vrai problème de PC**.
Serveur : `World/Tower/Mechanics.luau` (et `PuzzleService` pour les processus du monde 5) ; client :
`Controllers/Mechanics.luau` ; logique pure testée : `Util/Gauges.luau`. Les salles du terminal
ont, elles, leur **épreuve 3D** (§10).

| Monde | Mécanique | Comment ça marche | Ce qu'on apprend |
|---|---|---|---|
| 2 · Memory Lanes | **RAM saturée** | La jauge se remplit en ≈ 45 s ; au-delà de 70 %, la marche **au sol** ralentit (jusqu'à × 0,6, les sauts gardent leur portée). Trois gros boutons « Libérer la RAM » la vident (12 s de recharge chacun). | Fermer ce qui tourne pour rien (onglets, applis) libère la mémoire. |
| 4 · Cryo Tower | **Surchauffe** | La chaleur monte en courant (40 → 100 °C en 30 s de course sans pause), baisse à l'arrêt, vite près d'un ventilateur qui tourne : les 3 géants, et 4 ventilateurs **encrassés à relancer**. À 100 °C : arrêt thermique, retour au checkpoint. Bonus : le **ventilo propulseur** près du checkpoint 17. | La poussière bouche les ventilos ; un PC qui chauffe se coupe pour se protéger. |
| 5 · The Core | **Processus en fond** | Trois processus inutiles (SuperRecherche_svc.exe, Optimiseur3000.exe, CouponsExpress.exe) bloquent le chemin : appui maintenu « Fin de tâche ». Ils reviennent à la prochaine ascension (c'est leur spécialité). | Ce qui tourne en fond sans qu'on l'ait choisi mange le processeur. |
| 6 · Render Canyon | **Artefacts GPU** | De brefs rectangles colorés et une teinte à l'écran tant que le monde est infecté (rien avec « Réduire les animations »). | Les artefacts sont un symptôme de carte graphique ou de pilote. |
| Arcade | **Tri des fichiers**, **Défense du CPU (2D)** | Garder / Corbeille / Quarantaine ; des processus remontent trois bus vers le processeur. | Lire l'extension complète (« photo.jpg.exe » n'est pas une photo) ; version 2D rapide de l'épreuve du monde 5. |

Les jauges sont propres à chaque joueur, en pause dans la salle du terminal, pendant une épreuve,
et une fois le monde nettoyé. Une jauge contextuelle s'affiche à gauche du HUD (« 💾 RAM 72 % »,
« 🌡 CPU 81 °C »).

**Rôles d'équipe** (`Config/Roles.luau`, `RoleService`, page « Rôle d'équipe » du menu) : chacun a
un seul passif, aucun n'est obligatoire et aucun ne rend une ascension « assistée ».

| Rôle | Passif |
|---|---|
| Technicien | Les jauges RAM et chaleur montent 25 % moins vite. |
| Nettoyeur | +10 % de Bits à chaque terminal antivirus nettoyé. |
| Enquêteur | Enquêtes et bloatware désinstallés rapportent le double. |
| Service | +1 Bit à chaque checkpoint atteint. |

**Pas encore fait** (idées du guide) : la coop à 4 rôles **obligatoires** avec objectifs partagés,
les jauges **partagées** entre joueurs, et des épreuves **synchronisées** entre joueurs (chacun joue
la sienne, en local). Ce qui existe : les rôles en version légère (passifs) et les épreuves 3D
en solo (§10).

## 10. Les épreuves des salles du terminal (le parcours du guide)

Chaque salle du terminal n'est plus une boîte vide : on y joue **une étape du guide**, en 3D, avec
des panneaux au style de l'app (fiche Constat / Pourquoi / Quoi faire sur l'écran du fond, lignes,
étapes cochées). Prompt **E** sur la borne → l'épreuve démarre (carte en haut de l'écran : étapes,
statut, barre, bouton « Abandonner »). Réussie : le monde est nettoyé, comme avant. Ratée (mort,
sortie de la salle, abandon) : on recommence quand on veut, sans pénalité.

L'app **détecte, diagnostique et répare** : elle ne « tue » pas les virus, elle ferme, désactive,
désinstalle, met en quarantaine. Aucune vraie marque ni vrai antivirus en méchant.

| Monde | Épreuve (étape du guide) | Ce qu'on fait | Ce qu'on apprend |
|---|---|---|---|
| 0 · Intro | **L'intrusion** | Sur le bureau du PC d'Anga, on rejoue le clic d'hier soir sur free_robux_generator.exe : LAGZ s'installe. Passable. | Un « générateur de Robux gratuits » est toujours un piège ; ne jamais lancer un fichier inconnu. |
| 1 · Alimentation | **Le Démarrage infecté** (étape 1) | Six portes = six programmes du Démarrage ; on lit chaque porte (éditeur, impact) et on baisse le levier des **2 intrus** (éditeur inconnu). Un programme utile : le levier se relève, avec un indice. | Regarder l'éditeur et l'impact avant de laisser un programme se lancer avec le PC. |
| 2 · Memory Lanes | **La RAM saturée** (étape 3) | Les barrettes sont en A1 + B1 : on les porte en **A2 + B2** (double canal), puis on appuie 3 fois sur « Libérer la RAM » pendant que des fichiers inutiles s'empilent. | L'emplacement des barrettes compte ; fermer ce qui tourne pour rien libère la mémoire. |
| 3 · Data Vault | **L'invasion du Bloatware** (étape 2) | Des bloatware (boîtes à yeux) errent et se copient ; « Debloat » les aspire dans la Corbeille, le pad « préréglage » (une fois) aspire tous ceux qui sont proches, puis on **vide la Corbeille**. | Désinstaller ce qu'on n'a pas choisi d'installer, et vider la Corbeille. |
| 4 · Cryo Tower | **La surchauffe** (étape 4) | Le sol devient de la lave ; on saute de socle en socle pour **relancer 3 ventilateurs**, puis on passe le plan d'alimentation sur **Équilibré**. Toucher la lave : retour au checkpoint, épreuve à refaire. | Des ventilos bouchés et un plan « à fond » font chauffer le PC. |
| 5 · The Core | **Défense du CPU** (tour de défense) | Des processus du virus descendent trois bus vers le processeur, en 3 vagues ; on pose des **optimisations** (Mode jeu, Plan Performances…) sur 6 emplacements avec l'énergie ⚡. Cercle de portée, tourelles qui visent, processus lourds en violet. 16 processus arrêtés = gagné. | Chaque réglage enlève un peu de charge au processeur. |
| 6 · Render Canyon | **La carte graphique corrompue** (étape 5) | Nettoyage complet de l'ancien pilote (4 fichiers à supprimer), téléchargement du nouveau (rester dans la zone), installation (brancher 3 câbles), puis l'écran resté à **60 Hz** passe à sa fréquence maximale (**170 Hz**). | Un pilote se réinstalle proprement ; un écran mal réglé reste bloqué à 60 Hz. |
| 7 · Neural Nexus | **L'enquête des Sessions de jeu** (étape 6) | On inspecte le programme qui rame, on remonte « qui l'a lancé » de capsule en capsule (les liens s'allument) jusqu'à LAGZ, caché ; quarantaine → le **Firewall boss** démarre. | Le programme qui rame n'est pas toujours le coupable : regarder qui l'a lancé. |

Code : décor serveur `World/Tower/Epreuves.luau` (+ `World/AppBoard.luau`) ; jeu client
`Controllers/Epreuves.luau` (socle : HUD, échec, abandon, restauration) et
`Controllers/EpreuveKinds/*` ; règles pures et testées `Shared/EpreuveLogic/*` ;
textes `Config/Epreuves.luau`. Validation serveur : `MinigameStart` / `MinigameEnd` avec la durée
minimale de l'épreuve (`MinSeconds`). Tests : `epreuves.spec` (bots qui jouent chaque épreuve) et
`epreuverooms.spec` (tout tient dans la salle, rien ne gêne la borne, la porte ni le portail).

Pour tester vite : menu **DEV** → « Nouveautés à tester » → « Épreuve 1 … 7 » (téléport devant la
borne, monde encore infecté, épreuve lancée) et « Étape 0 : l'intrusion + intro ».

