# AngAInOne — Deathrun dans la tour PC · GDD v2

> Remplace le GDD tycoon v1 (trop compliqué pour les enfants). Le code du tycoon a été retiré.

## 1. Pitch

**Un virus a infecté le PC d'Anga.** Tu es miniaturisé à l'intérieur de sa tour géante et tu dois
la **grimper de bas en haut**, en traversant chaque composant (alimentation, RAM, SSD,
refroidissement, processeur, carte graphique, puce IA) en survivant aux pièges du virus :
décharges électriques, ventilateurs, barrettes qui écrasent, lasers, virus gardiens…
À la fin de chaque monde, un **terminal antivirus** : un mini-jeu 2D pour nettoyer le monde et
ouvrir la porte suivante. Tout en haut : le cœur du virus.

- **Genre** : deathrun / obby à pièges automatiques (PvE), solo ou à plusieurs sur la même tour.
- **Public** : 8–14 ans, cross-plateforme (mobile d'abord).
- **Règle d'or** : compréhensible en 5 secondes. *Cours, saute, n'touche pas ce qui brille en rouge.*

## 2. Boucle de jeu

1. **Lobby** (Salle de démarrage, au pied de la tour) : Anga raconte l'histoire, écran géant de
   l'app partenaire AngAInOne, boutique, classements, borne d'arcade. Pad **JOUER**.
2. **Étapes** : chaque monde = 5 étapes courtes (30–60 s), chacune finit par un **checkpoint**.
   On meurt → on réapparaît au dernier checkpoint. Aucun game over.
3. **Terminal antivirus** (5ᵉ étape du monde, salle sûre) : mini-jeu 2D de 20–40 s.
   Réussi → le portail s'ouvre + récompense. Raté → on peut réessayer tout de suite.
4. **Sommet** : la puce IA et le cœur du virus. Victoire → cinématique d'Anga, récompense,
   temps enregistré, retour au lobby. On peut recommencer pour battre son record.

Durée : ~25–40 min pour une première ascension, 8–12 min pour un bon speedrun.

## 3. Les 7 mondes (config : `src/shared/Config/Tower.luau`)

| # | Monde | Composant | Section AngAInOne | Pièges vedettes | Mini-jeu |
|---|---|---|---|---|---|
| 1 | La Centrale | Alimentation | Démarrage | Décharges, trampolines condensateurs, pales | Scan |
| 2 | Memory Lanes | RAM | Applications | Barrettes qui écrasent, tapis de données, plateformes mobiles | Memory |
| 3 | Data Vault | SSD | Nettoyage & réparation | Plateformes qui s'effacent, blocs, tapis | Dodge |
| 4 | Cryo Tower | Refroidissement | Diagnostic | Vent des ventilateurs, pales, plateformes gelées | Firewall |
| 5 | The Core | CPU | Optimisations | Lasers, bouches de chaleur, plateformes mobiles | Scan |
| 6 | Render Canyon | GPU | Gaming | Pales de ventilateurs géants, lasers, décharges | Memory |
| 7 | Neural Nexus | Puce IA | Réseau | Virus gardiens, lasers, plateformes mobiles | Firewall (boss) |

Pièges (tag `Trap`, attribut `Kind`) : Zapper, SpinBar, Crusher, Mover, Vanish, Wind, Laser,
Virus, Conveyor, Bounce, Heat. Tout ce qui tue est **rouge / violet glitch** et prévenu par un
signal (clignotement, son) avant de s'activer. Les pièges sont animés côté client avec l'heure du
serveur : tous les joueurs voient la même chose au même moment.

## 4. Mini-jeux 2D antivirus

| Mini-jeu | But | Contrôles |
|---|---|---|
| **Scan** | Tape les virus qui surgissent dans une grille avant qu'ils disparaissent (atteindre un score). | Tap / clic |
| **Firewall** | Déplace le pare-feu en bas de l'écran et tire sur les virus qui tombent. | Glisser / flèches / stick |
| **Memory** | Retrouve les paires de cartes (icônes de composants) en un nombre d'essais limité. | Tap / clic |
| **Dodge** | Guide le paquet de données vers le haut entre les virus. | Tap pour monter / espace |

Difficulté croissante avec le monde. Rejouables à la **borne d'arcade** du lobby (petites
récompenses, avec délai entre deux gains).

## 5. Features

- **Checkpoints**, bouton « Revenir au checkpoint », bouton « Lobby ».
- **Chrono** de l'ascension + record perso ; **classements** : victoires, meilleur temps, étape max.
- **Bits** : on les ramasse sur le parcours (orbes) et en réussissant les mini-jeux.
- **Boutique** : traînées lumineuses, effets de mort (glitch, pixels…), auras de victoire.
- **Récompenses quotidiennes** (calendrier 7 jours) et **missions du jour** (3).
- **Multijoueur** : les joueurs ne se bousculent pas (pas de collision entre eux), on voit la
  progression des autres (étape au-dessus de la tête), bonus d'amis.
- **Histoire** : intro d'Anga, une réplique à l'entrée de chaque monde, fin.
- **Réglages** : volumes, animations réduites.

## 6. Monétisation (éthique, rien d'obligatoire)

| Article | Type | Prix indicatif |
|---|---|---|
| Passer l'étape | Developer Product | 19 R$ |
| Bouclier 30 s (invincible) | Developer Product | 29 R$ |
| Packs de Bits | Developer Product | 49 / 149 / 399 R$ |
| VIP (x2 Bits, traînée VIP) | Game Pass | 249 R$ |
| Bottes anti-gravité (saut plus haut, activable) | Game Pass | 149 R$ |
| Puce de vitesse (+20 % vitesse, activable) | Game Pass | 149 R$ |

Pas de loot box. Les passes « avantage » sont activables/désactivables et n'affectent pas les
classements de temps (course marquée « assistée »).

## 7. Anti-triche (serveur)

Checkpoints validés dans l'ordre, temps minimum par étape, portail d'un monde franchissable
seulement après le mini-jeu, durée minimale d'un mini-jeu, orbes ramassées à proximité et une
seule fois par ascension. Les morts sont signalées par le client (pièges animés côté client) :
tricher ne fait qu'éviter de mourir soi-même, le serveur garde la main sur la progression.

## 8. Technique

- Luau `--!strict`, Rojo. Serveur : `Core/` (Session, événements, télémétrie), `Security/`
  (RemoteGuard), `Services/` (Data, State, Run, Minigame, Shop/Monetization, Daily/Missions,
  Leaderboard, Dev), `World/` (Build, Props, TowerBuilder).
- Client : `Controllers/` (Net, Store, Audio, TrapController, Story, Fx…), `UI/` (design
  system existant : StyleSheets, Keycap, Panel…), `UI/Minigames/` (mini-jeux 2D).
- Tests Lune : construction réelle de la tour (checkpoints, portails, budget pièces/lumières),
  contrats client/serveur, schéma de données.
