# Steal a Kaiju — pack audio original

Tous les sons de ce dossier ont été **synthétisés de zéro** par `tools/audio/generate_audio.py` (oscillateurs, FM, bruit filtré, Karplus-Strong, réverbération synthétique…). Aucun échantillon externe, aucun téléchargement : le pack est 100 % original et libre de droits pour ce projet.

Format : OGG Vorbis, 44 100 Hz, crête normalisée à environ −1 dBFS. SFX en mono, musiques en stéréo. Les boucles (`alarm`, `music_*`) bouclent sans couture (longueur exacte en mesures, la queue est repliée sur le début).

Pour régénérer : `python3 tools/audio/generate_audio.py` (déterministe, dépendances : numpy, scipy, soundfile ; numba optionnel pour la vitesse).

## Fichiers

| Clé (fichier .ogg) | Durée (s) | Description |
|---|---|---|
| `ui_click` | 0.080 | Clic d'interface net et court (pop + transitoire). |
| `ui_hover` | 0.050 | Petit tic doux au survol d'un bouton. |
| `ui_open` | 0.250 | Ouverture de menu : souffle montant + pop final. |
| `ui_close` | 0.200 | Fermeture de menu : souffle descendant + petit toc. |
| `ui_error` | 0.300 | Erreur : double buzz grave « nuh-uh ». |
| `ui_tab` | 0.100 | Changement d'onglet : toc boisé. |
| `cash_collect` | 0.600 | Collecte d'argent : cascade de pièces + scintillement. |
| `coin_tick` | 0.060 | Minuscule tintement de pièce (compteur). |
| `purchase` | 0.500 | Achat : « cha-ching » de caisse enregistreuse. |
| `sell` | 0.400 | Vente : swoosh + deux pièces montantes. |
| `meteor_whistle` | 2.500 | Chute de météore : sifflement descendant, grondement et crépitements. |
| `meteor_impact` | 1.500 | Impact de météore : gros boom, sub-basse et débris. |
| `meteor_rare_alarm` | 1.200 | Alerte météore rare : carillon scintillant. |
| `egg_wobble` | 0.300 | Œuf qui bouge : toc-toc de coquille. |
| `egg_crack` | 0.500 | Œuf qui se fissure : craquements de coquille. |
| `hatch_common` | 1.000 | Éclosion commune : pop joyeux + petit arpège. |
| `hatch_epic` | 1.800 | Éclosion épique : grand arpège, accord et scintillement. |
| `hatch_legendary` | 3.000 | Éclosion légendaire : fanfare de cuivres, timbales et cymbales. |
| `hatch_secret` | 3.500 | Éclosion secrète : montée mystérieuse puis révélation explosive. |
| `stage_up` | 1.200 | Évolution du kaiju : montée « power-up » + carillon. |
| `roar_small` | 0.800 | Petit rugissement mignon de bébé kaiju. |
| `roar_big` | 2.000 | Énorme rugissement de kaiju (formants, grognement, distorsion). |
| `steal_grab` | 0.400 | Vol : pincement de corde furtif + swoosh. |
| `alarm` | 1.500 | Sirène d'alarme de base (boucle parfaite, à jouer en Looped). *(boucle)* |
| `bonk` | 0.350 | Coup de marteau cartoon « bonk » + boing. |
| `knockback_whoosh` | 0.400 | Souffle rapide de projection (knockback). |
| `shield_on` | 1.000 | Activation du bouclier : dôme d'énergie qui monte. |
| `shield_zap` | 0.400 | Décharge électrique du bouclier. |
| `drop` | 0.400 | Objet lâché : bruit sourd + petit rebond. |
| `heist_success` | 1.500 | Vol réussi : motif furtif puis accord triomphal. |
| `rebirth` | 3.000 | Renaissance : chœur ascendant épique + boom. |
| `fusion_charge` | 2.000 | Charge de fusion : montée d'énergie qui accélère. |
| `fusion_boom` | 1.500 | Explosion de fusion + accord brillant et étincelles. |
| `reward_claim` | 0.800 | Récompense réclamée : petit jingle brillant. |
| `quest_complete` | 1.000 | Quête terminée : « ta-da » marimba + cloches. |
| `level_jingle` | 1.500 | Montée de niveau : jingle chiptune ascendant. |
| `spin_tick` | 0.040 | Tic de la roue de la fortune. |
| `spin_win` | 1.500 | Gain à la roue : glissando, accord et pluie de pièces. |
| `event_horn` | 2.000 | Cor de guerre / sirène annonçant un événement. |
| `countdown_beep` | 0.150 | Bip de compte à rebours. |
| `boss_stomp` | 1.200 | Pas de boss géant : sub-basse, grondement et gravats. |
| `whoosh` | 0.500 | Souffle générique (whoosh). |
| `music_main` | 80.000 | Musique principale en boucle : funk/chiptune x synthwave, 120 BPM, Do majeur. *(boucle)* |
| `music_event` | 54.857 | Musique d'événement en boucle : intense, 140 BPM, Mi mineur harmonique. *(boucle)* |
| `music_boss` | 57.600 | Musique de boss en boucle : lourde et dramatique (taikos, cuivres, cordes), 100 BPM, Ré mineur. *(boucle)* |
| `music_lobby_calm` | 53.333 | Musique calme en boucle (lobby) : lo-fi/chill, piano électrique, 90 BPM. *(boucle)* |

## Import dans Roblox

1. Ouvrir le jeu dans **Roblox Studio**.
2. Ouvrir le **Gestionnaire de ressources** (onglet *Affichage* → *Asset Manager*), puis cliquer sur **Importation groupée** (*Bulk Import*) et sélectionner tous les fichiers `.ogg` de ce dossier. Alternative : **Creator Hub** → *Créations* → *Audio* → *Importer un fichier audio* (un par un).
3. Attendre la modération Roblox (quelques minutes). Chaque son reçoit un **ID d'asset** (`rbxassetid://123456789`).
4. Dans le Gestionnaire de ressources, clic droit sur chaque son → **Copier l'ID de l'asset**, puis le coller dans `src/shared/Config/Sounds.luau`, dans le champ `Uploaded` de la clé correspondante (la clé = le nom du fichier sans `.ogg`, par ex. `meteor_impact`).
5. Pour `alarm` et les `music_*`, activer `Looped = true` sur le `Sound`.
6. Tous les fichiers sont normalisés au même niveau de crête : régler l'équilibre final avec la propriété `Volume` de chaque `Sound` (ex. `ui_hover` ≈ 0.3, musiques ≈ 0.4–0.5, impacts ≈ 0.8).

Limites Roblox respectées : chaque fichier fait moins de 7 minutes et bien moins de 19 Mo.
