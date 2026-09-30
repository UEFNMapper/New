# AngAInOne — Audit v2 et pistes pour la v3

Audit fait sur le code de la v2 « Opération Anti-Lag » (7 mondes uniques, 25 pièges, 6 incidents,
boss LAGZ, 6 mini-jeux, 55 modèles 3D). Chaque piste indique **pourquoi** et **comment elle met
AngAInOne en avant**. Priorités : **P1** = fort impact / effort raisonnable, **P2** = ensuite,
**P3** = bonus.

---

## 1. Constat

### Ce qui marche
- Enjeu clair et compréhensible par un enfant : « le live commence dans une heure, le PC rame ».
- Le scénario agit sur le jeu : incidents qui changent les pièges, mondes infectés → nettoyés,
  widget FPS / ping / °C qui s'améliore.
- 7 parcours reconnaissables (câbles du PSU, ville de RAM, grille NAND, watercooling, spirale du
  ventirad, canyon de la carte graphique, cerveau IA) et un vrai boss.

### Ce qui manque
| Domaine | Problème | Conséquence |
|---|---|---|
| **AngAInOne** | L'app n'est qu'un **décor** : l'écran du lobby, le nom du Miniaturiseur, des noms de section. Pendant l'ascension, **l'app ne fait rien pour le joueur**. | Le joueur ne comprend pas à quoi sert le logiciel ; le partenariat est peu visible. |
| **Scénario** | L'histoire passe presque entièrement par du **texte** (bulle d'Anga, cartes). LAGZ parle mais n'apparaît qu'à la fin. Pas de rebondissement au milieu. Le joueur est anonyme. | Les enfants lisent peu ; le milieu de l'ascension (mondes 3 à 6) est plat côté histoire. |
| **Gameplay** | Aucune raison de **rejouer un monde** (pas de médailles, pas de temps par monde). Pas de progression hors cosmétiques. Peu d'interaction entre joueurs. Le « feeling » des sauts est celui de Roblox par défaut. | Rétention faible après la première victoire. |
| **Design** | Tant que les modèles 3D ne sont pas importés, le jeu reste en blocs. Ambiance par monde = une simple teinte d'écran. Le vide sous les mondes est noir et vide. | La tour paraît moins « à l'intérieur d'un PC » qu'elle pourrait. |
| **Interface** | Le HUD cumule beaucoup d'éléments (carte de progression, pastille des clés, widget du PC, boutons, dock). | Chargé pour un enfant sur téléphone. |

---

## 2. Pistes

### A. La boîte à outils AngAInOne — **P1, pièce maîtresse**
Chaque monde nettoyé **débloque l'outil de l'app** qui correspond à sa section, utilisable
ensuite comme **capacité** (1 bouton, recharge). Le joueur apprend ce que fait vraiment l'app en
jouant :

| Monde (section de l'app) | Outil débloqué | Effet en jeu |
|---|---|---|
| 1 · Démarrage | **Démarrage rapide** | Réapparition instantanée au point de restauration, 2 s d'invincibilité. |
| 2 · Applications | **Fermer les applis** | Ferme d'un coup toutes les pop-ups (contre POP-UP STORM). |
| 3 · Nettoyage & réparation | **Réparation** | Les dalles corrompues autour de toi redeviennent solides pendant 5 s. |
| 4 · Diagnostic | **Scan diagnostic** | Pendant 6 s : anneaux de compte à rebours sur les pièges (fenêtre sûre) et ping vers les clés USB. |
| 5 · Optimisations | **Mode performance** | +20 % de vitesse pendant 4 s. |
| 6 · Gaming | **Mode jeu** | Double saut pendant 6 s. |
| 7 · Réseau | **Pare-feu** | Bloque le prochain piège mortel. |

- **Roue d'outils** au style Fluent de l'app (gris + violet), une icône par section.
- Les outils restent débloqués d'une ascension à l'autre : c'est la **progression** qui manquait.
- Classement « Pur » (sans outils) et classement « Outils » pour garder la compétition juste.

### B. Le compagnon « AIO », assistant de l'app — **P1**
Un petit **drone holographique aux couleurs d'AngAInOne** suit le joueur :
- il dit les répliques dans une **bulle au-dessus de lui** (encore plus discret que la bulle en bas
  d'écran, et on ne quitte plus le jeu des yeux) ;
- il **montre la direction** du prochain checkpoint quand on hésite ;
- il lance les outils de la boîte à outils (animation de scan, de pare-feu…) ;
- il réagit : content au checkpoint, paniqué pendant un incident, sonné pendant un FREEZE.

C'est la mascotte du logiciel, présente **toute la partie**.

### C. Scénario v3 — **P1 / P2**
1. **Le joueur a un rôle** (P1) : « Technicien·ne AngAInOne n° 0427 », badge avec son pseudo.
   L'intro devient une **mission acceptée dans l'app** (fenêtre Fluent « Mode Intervention »).
2. **Raconter par l'image plutôt que par le texte** (P1) :
   - la **tour s'allume** monde par monde en RGB propre, visible depuis le lobby ;
   - la chambre d'Anga réagit : le chat du live s'emballe, la lumière revient ;
   - LAGZ **apparaît en 3D** dans chaque monde (tête géante dans un écran, rire, fuite) au lieu de
     seulement parler.
3. **Rapport d'optimisation final** (P1) : écran de fin au style de l'app — « 7 menaces supprimées,
   +141 FPS, 97 °C → 40 °C, temps 12:34, 18/21 clés ». Image à **partager / capturer**, donc de la
   visibilité pour l'app.
4. **Rebondissement au milieu** (P2) : après le monde 4, LAGZ pirate le Miniaturiseur. L'app passe
   en **« Mode sans échec »** : interface grise, outils coupés pendant les mondes 5 et 6, puis
   restaurés au terminal du monde 6. C'est un moment fort, et c'est une vraie fonction de ce genre
   de logiciel.
5. **Les sbires deviennent de mini-combats** (P2) : 20 secondes contre Sparky, Pop-Up… avant chaque
   terminal, au lieu d'un personnage posé en décor.
6. **Clés USB = journaux de LAGZ** (P3) : chaque clé débloque une courte note de LAGZ (humour),
   consultable dans l'app du lobby.

### D. Gameplay — **P1 / P2**
- **Sensations de saut** (P1, peu d'effort, gros effet) : « coyote time » (on peut encore sauter
  0,1 s après avoir quitté le bord) et saut mémorisé (appui juste avant d'atterrir).
- **Médailles par monde** (P1) : bronze / argent / or selon le temps, les morts et les clés ;
  classement par monde. Raison claire de rejouer.
- **Points de restauration** (P1) : les checkpoints prennent le nom et le style d'une fonction de
  l'app (fenêtre « Point de restauration créé ✓ »).
- **Mode Overclock** (P2) après la première victoire : pièges plus rapides, incidents plus fréquents,
  classement séparé.
- **Scan du jour** (P2) : un défi quotidien avec un modificateur (gravité basse, lag permanent,
  monde en blackout) et une récompense.
- **Coopération** (P3) : raccourcis à « double authentification » (deux plaques à activer à deux) ;
  en solo, le chemin normal reste disponible. Prises du boss partagées en groupe.
- **Course de diagnostic** (P3) : départ synchronisé de 2 à 8 joueurs depuis le lobby.

### E. Design — **P1 / P2**
- **Importer les 55 modèles 3D** (P1, bloqué côté Roblox : clé Open Cloud ou import Studio).
  C'est le plus gros gain visuel immédiat.
- **Ambiance par monde** (P1) : brouillard, Atmosphere, Bloom et lumière propres à chaque monde,
  plus des particules d'ambiance (étincelles au monde 1, bits de données au 2, givre au 4, chaleur
  au 5, pixels au 6, synapses au 7). Le vide sous chaque monde devient un fond de carte mère lumineux
  plutôt que du noir.
- **Salles du terminal façon app** (P2) : murs en fenêtres Fluent, barre de progression d'analyse
  pendant le mini-jeu.
- **HUD allégé** (P1) : fusionner le widget du PC dans la carte de progression, masquer les boutons
  inutiles pendant la course, tout au style de l'app.
- **Sons** (P2) : une ambiance sonore par monde et un son distinct par incident.

### F. Production — **P1**
- **Mesurer avant d'équilibrer** : carte des morts par étape à partir de la télémétrie déjà en place,
  pour savoir où les enfants abandonnent.
- **Performance mobile** avec les vrais modèles : fidélité de rendu automatique, limite de
  triangles par monde, test sur un téléphone d'entrée de gamme.

---

## 3. Lot recommandé pour la v3

Un premier lot cohérent, qui répond aux trois demandes (design, gameplay, AngAInOne en avant) :

1. **Boîte à outils AngAInOne** (A) + **compagnon AIO** (B), le cœur de la v3.
2. **Rapport d'optimisation final**, **rôle du joueur**, **tour qui s'allume** et **LAGZ visible en
   3D** (C1 à C3).
3. **Sensations de saut**, **médailles par monde**, **points de restauration** (D).
4. **Ambiances par monde** et **HUD allégé** (E).

Ensuite : Mode sans échec et mini-combats des sbires (C4, C5), Overclock et Scan du jour (D).
