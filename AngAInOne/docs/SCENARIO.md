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

### Monde 1 · La Centrale (Alimentation) — « Le PC s'éteint tout seul »
- **Parcours** : sous le carénage du bloc d'alimentation, on court **sur les câbles tressés
  géants**, on saute de condensateur en condensateur, puis on traverse la grille du ventilateur du PSU.
- **Pièges** : décharges (Zapper), condensateurs-trampolines, **Rails de surtension** (une
  impulsion électrique court le long des câbles : sauter au bon moment), **Plateformes alimentées**
  (solides seulement quand le courant passe, au rythme d'un voyant).
- **Incident vedette** : BLACKOUT. **Sbire** : Sparky. **Mini-jeu** : Scan.
- Anga : « Le courant saute ! Marche sur les plateformes quand elles sont allumées. »

### Monde 2 · Memory Lanes (RAM) — « Mémoire saturée, 200 onglets ouverts »
- **Parcours** : un **canyon vertical** entre les barrettes de RAM ; on grimpe sur les puces
  mémoire, on traverse d'une barrette à l'autre.
- **Pièges** : barrettes qui écrasent (Crusher), tapis de données, **Pluie d'onglets** (des
  fenêtres de navigateur tombent en rafale et restent un instant comme plateformes), **Fuite
  mémoire** (un flot de données violet MONTE derrière toi : section de grimpe chronométrée).
- **Incident vedette** : POP-UP STORM. **Sbire** : Pop-Up. **Mini-jeu** : Pop-up Killer (nouveau).

### Monde 3 · Data Vault (SSD) — « Fichiers corrompus »
- **Parcours** : une **grande grille de cellules NAND** (damier en hauteur), façon labyrinthe à
  étages, avec des tiroirs de SSD qui sortent du mur.
- **Pièges** : **Dalles corrompues** (texture manquante rose/noir qui clignote), **Défragmenteur**
  (blocs qui coulissent sur une grille comme un taquin), plateformes qui s'effacent, pistons.
- **Incident vedette** : CORRUPTION. **Sbire** : Corrupto. **Mini-jeu** : Défrag (nouveau).

### Monde 4 · Cryo Tower (Refroidissement) — « Surchauffe, ventilos bouchés »
- **Parcours** : **à travers le radiateur** (couloirs entre les ailettes), puis **dans les tubes
  transparents** du watercooling, et entre les pales des gros ventilateurs.
- **Pièges** : vent des ventilateurs, glace glissante, **Boules de poussière** qui roulent,
  **Jets de vapeur** (bouches de chaleur), pales.
- **Incident vedette** : SURCHAUFFE. **Sbire** : Dusty. **Mini-jeu** : Firewall.

### Monde 5 · The Core (CPU) — « Processeur à 100 %, un crypto-mineur ! »
- **Parcours** : une **spirale** qui monte autour du ventirad à caloducs, puis un sprint sur la
  **grille de broches** du socket.
- **Pièges** : lasers, **Pioches du mineur** (pendules géants), **Plateformes en latence**
  (elles se déplacent avec un temps de retard, par à-coups), **Roue de chargement** (anneau de
  plateformes qui tourne comme l'icône de chargement).
- **Incident vedette** : LAG SPIKE. **Sbire** : Minor. **Mini-jeu** : Scan (difficile).

### Monde 6 · Render Canyon (GPU) — « Écran figé, artefacts »
- **Parcours** : un canyon **le long de la carte graphique**, entre ses 3 ventilateurs géants,
  puis sur une **piste de pixels**.
- **Pièges** : pales géantes, lasers de rendu, **Pixels morts** (le sol s'éteint en vagues),
  **Pont de chargement** (un pont qui se remplit comme une barre de progression… et parfois bloque).
- **Incident vedette** : FREEZE. **Sbire** : Freezy. **Mini-jeu** : Memory.

### Monde 7 · Neural Nexus (Puce IA) — Le repaire de LAGZ
- **Parcours** : plateformes flottantes autour du cerveau holographique, puis l'**arène du boss**.
- **Pièges** : virus patrouilleurs, **Curseur géant** (une main-curseur qui vient cliquer là où tu
  te trouves), **Pare-feu mobiles** (murs percés qui avancent), un peu de tout.
- **Incidents** : tous, plus souvent.
- **BOSS LAGZ** (3 phases, 1 à 2 min) :
  1. LAGZ tire des lasers et envoie le curseur géant : survivre en courant autour de l'arène.
  2. Le sol se fragmente (plateformes qui s'effacent) et des virus sortent : atteindre les 3
     **prises antivirus** (boutons au sol) pour lui retirer son bouclier.
  3. Terminal final : **Firewall boss** (mini-jeu) pendant que LAGZ glitche l'écran.
- **Fin** : « Le PC tourne à 144 FPS ! » — le moniteur du bureau affiche le live d'AngaTV qui
  commence, le chat défile (« GG ! », « merci l'antivirus ! »), Anga remercie le joueur par son pseudo.

## 6. Le lobby : la chambre d'Anga

On apparaît **sur le bureau d'Anga**, minuscule, devant la tour PC géante à panneau vitré :
- l'**écran d'Anga** affiche « LIVE DANS 59:00 » et le chat qui s'impatiente ;
- le **Miniaturiseur AngAInOne** (le portail de départ, pad JOUER) ;
- l'écran de l'app AngAInOne (progression du joueur), les classements, la boutique, l'arcade ;
- décor : clavier mécanique RGB, souris, tasse, micro de stream, lampe, câbles.

## 7. Difficulté et rejouabilité

- **Courbe** : monde 1 = tutoriel ; chaque étape n'introduit qu'une idée ; la 5ᵉ étape combine.
  Écarts ≤ 6,5 studs, fenêtres de sécurité ≥ 1,2 s au monde 1, ≥ 0,8 s au monde 7.
- **Clés USB dorées** : 3 par monde (21), cachées sur des **chemins difficiles** facultatifs.
  Toutes les clés d'un monde → une traînée ; les 21 → titre « Anti-Lag Légendaire ».
- **Chrono** et classements ; incidents différents à chaque passage.
