# Trailer UEFN automatique

Tu donnes tes vidéos de gameplay (une longue ou plusieurs petites), le logiciel fait le reste :

- il **repère les meilleurs moments** (action, couleurs, son du jeu) et écarte les écrans
  noirs, les chargements et les passages figés ;
- il **détecte le tempo de la musique** et coupe **pile sur les temps** ;
- il construit un trailer avec la structure des trailers UEFN qui marchent ;
- il ajoute **bandeaux jaunes, gros titres, flashs, zooms, secousses** ;
- il termine par une **carte de fin** : nom de la map, « PLAY NOW », code de l'île ;
- en bonus, il génère **3 miniatures 1920×1080** prêtes pour l'île.

Tout tourne sur ton PC, sans abonnement ni envoi de tes vidéos sur Internet.

## Ce que j'ai retenu des trailers de référence

J'ai analysé les 5 trailers que tu m'as envoyés (Survive The Disaster, Drone Mining Simulator,
Sprite Tower Defense, +1 Pickaxe a Pumpkin, Fortnitemares). Les quatre trailers de maps
suivent la même formule, que le logiciel reproduit :

| Moment | Durée | Ce qu'on voit |
|---|---|---|
| Ouverture | 2 à 4 s | Le plus beau plan, mentions légales, logo « Created in Fortnite » |
| Sections | 3 à 8 s chacune | Une fonctionnalité par section, avec son **bandeau jaune en bas à gauche** (« MINE ORES », « FIGHT BOSS », « UNLOCK ALL 22 TOOLS »...) et plusieurs plans de 1 à 2 s |
| Climax (optionnel) | 1 à 2 s | Gros texte central (« THE ADVENTURE BEGINS »), coupes très rapides |
| Fin | 3 à 5 s | Key art + nom de la map + **code de l'île en très gros** |

Durée totale : 20 à 40 secondes. Trois sur quatre finissent sur une **illustration** (key art)
plutôt que sur du gameplay : c'est ce qui fait la différence côté qualité perçue.

## Installation (Windows, une seule fois)

1. **Python** : <https://www.python.org/downloads/>. Pendant l'installation, coche
   **« Add python.exe to PATH »**.
2. **ffmpeg** : ouvre PowerShell et tape `winget install Gyan.FFmpeg`.
3. Télécharge ce dossier `trailer-uefn` (bouton **Code › Download ZIP** sur GitHub), puis dézippe-le.

Ensuite, double-clique sur **`lancer.bat`**. La première fois, il installe deux modules
Python (numpy et Pillow), puis la fenêtre s'ouvre.

Sur macOS ou Linux : installe ffmpeg (`brew install ffmpeg` ou `sudo apt install ffmpeg`),
puis lance `./lancer.sh`.

## Utilisation

### Avec la fenêtre

1. **Ajouter...** ou **Dossier...** pour charger tes vidéos.
2. Double-clique sur une vidéo pour écrire son bandeau (ex. `FIGHT BOSS`). Les vidéos qui ont
   le même bandeau forment une seule section. Les boutons Monter et Descendre règlent l'ordre.
3. Remplis le nom de la map et le code de l'île.
4. Choisis une musique (fortement conseillé, voir plus bas).
5. **Créer le trailer + miniatures**, puis choisis où enregistrer.

### En ligne de commande

```bash
# Un dossier de clips nommés "01_MINE ORES.mp4", "02_FIGHT BOSS.mp4"...
python trailer.py mes_clips/ --titre "Drone Mining Simulator" --code 6522-7216-3724 \
    --musique musique.mp3 --final "THE ADVENTURE BEGINS"

# Une seule longue vidéo, bandeaux répartis automatiquement
python trailer.py gameplay.mp4 --musique musique.mp3 \
    --textes "SURVIVE THE DISASTERS|USE ITEMS TO SURVIVE|MULTI DISASTERS"

# Version TikTok / Shorts (9:16)
python trailer.py mes_clips/ --titre "Ma Map" --code 1234-5678-9012 --vertical --duree 20

# Miniatures seulement
python trailer.py mes_clips/ --titre "Ma Map" --badge UPDATE --miniatures-seulement
```

Toutes les options : `python trailer.py --help`. Les principales :

| Option | Rôle |
|---|---|
| `--titre`, `--code` | Nom de la map et code de l'île (carte de fin, miniatures) |
| `--textes "A\|B\|C"` | Bandeaux des sections quand les fichiers ne sont pas nommés |
| `--accroche` | Gros texte pendant l'ouverture (« CAN YOU SURVIVE? ») |
| `--final` | Gros texte avant la fin (« THE ADVENTURE BEGINS ») |
| `--musique` | MP3 ou WAV. Sans musique, une piste de secours est générée |
| `--duree` | Durée visée en secondes (défaut : 30). Elle est arrondie à la mesure pour finir sur le temps |
| `--rythme lent\|normal\|rapide` | Longueur moyenne des plans : 2,6 s, 1,8 s ou 1,1 s |
| `--image-fin` | Ton key art pour la carte de fin (et la 1re miniature) |
| `--logo` | PNG affiché pendant l'ouverture (ex. badge officiel « Created in Fortnite ») |
| `--couleur` | Couleur des bandeaux (défaut `#FFD400`, le jaune des références) |
| `--vertical` | Format 9:16 : le gameplay est au centre, sur un fond flou |
| `--volume-jeu` | Son du jeu sous la musique, de 0 à 1 (défaut 0.35) |
| `--sans-mentions` | Retire la ligne « not affiliated with... Epic Games » |

Le trailer et les miniatures sont enregistrés dans le même dossier (par défaut `trailer/`).

## Les conseils qui changent tout

**1. Filme des clips courts, un par fonctionnalité.** C'est la meilleure méthode. Nomme-les avec
un numéro puis le bandeau : `01_MINE ORES.mp4`, `02_UPGRADE YOUR ARMY.mp4`, `03_FIGHT BOSS.mp4`.
Le logiciel en fait une section par bandeau, dans cet ordre. Prévois 10 à 20 secondes de
gameplay par fonctionnalité.

**2. Soigne la captation.** Enregistre en 1080p 60 ips (ou 1440p). Masque le HUD si tu peux,
et utilise le mode Replay de Fortnite ou une caméra cinématique UEFN (Sequencer) pour les
plans d'ouverture. Le logiciel choisit les meilleurs moments, mais il ne peut pas inventer
un beau plan.

**3. Prends une vraie musique libre de droits.** La piste générée sert seulement de secours.
Une musique sous droits peut faire bloquer ou couper le son de ta vidéo sur X, YouTube ou TikTok.
Où chercher :
- la bibliothèque audio de YouTube Studio (gratuite) ;
- [Pixabay Music](https://pixabay.com/music/) (gratuit, sans attribution) ;
- Epidemic Sound ou Artlist (payants, très utilisés par les créateurs).

Choisis un morceau énergique (trap, EDM, épique) avec un « drop » net. Le logiciel le repère
et le cale juste après l'ouverture.

**4. Fais un key art pour la fin.** Les meilleurs trailers finissent sur une illustration :
un personnage expressif et les éléments de la map, très saturés. Passe-la avec `--image-fin`,
elle sert aussi de première miniature.

**5. Teste plusieurs versions.** Change `--rythme`, `--duree` ou la musique : le rendu change
à chaque fois, et ça ne prend que quelques minutes.

## Miniatures

Le logiciel choisit les images les plus nettes et colorées, si possible dans des clips
différents. Il renforce les couleurs et le contraste, ajoute une vignette, un éclat lumineux,
le titre géant (contour noir, dégradé blanc vers jaune) et un badge optionnel (`--badge NEW`).
Le titre alterne entre le haut et le bas d'une miniature à l'autre : garde celle qui laisse
le mieux voir l'action.

Format produit : PNG 1920×1080, la taille demandée pour les îles Fortnite.

## Comment ça marche

```
vidéos ──► analyse image par image (6 ips) : mouvement, couleur, netteté, son, changements de plan
musique ─► flux spectral ► tempo (autocorrélation) ► grille des temps ► début des mesures ► drop
                │
                ▼
     plan de montage sur la grille musicale :
     ouverture (1-2 mesures) │ sections (coupes de 1, 2 ou 4 temps) │ climax │ carte de fin
                │
                ▼
     rendu ffmpeg plan par plan (zoom, flash, secousse, étalonnage)
     ► assemblage ► textes animés ► mixage musique + son du jeu ► normalisation à -14 LUFS
```

| Fichier | Rôle |
|---|---|
| `trailer_uefn/analyse.py` | Notation des moments de gameplay, détection du tempo et du drop |
| `trailer_uefn/montage.py` | Plan de montage et rendu final |
| `trailer_uefn/textes.py` | Bandeaux, titres, carte de fin |
| `trailer_uefn/miniature.py` | Miniatures |
| `trailer_uefn/musique_auto.py` | Piste de secours générée |
| `interface.py` / `trailer.py` | Fenêtre graphique / ligne de commande |

La police **Anton** (licence libre SIL OFL, fichier `polices/OFL-Anton.txt`) remplace la
police de Fortnite, qui n'est pas libre. Elle a la même allure : condensée, grasse, en majuscules.

## Limites

- Le logiciel ne « comprend » pas ce qui se passe à l'écran. Il mesure l'action et la beauté
  de l'image. C'est le nom des clips qui lui indique quelle fonctionnalité montrer, et quand.
- Le tempo est supposé constant, ce qui est le cas de presque toutes les musiques de trailer.
- Le rendu prend quelques minutes (compte environ 2 à 5 fois la durée du trailer en 60 ips
  sur un PC récent). L'option `--fps 30` va deux fois plus vite.
