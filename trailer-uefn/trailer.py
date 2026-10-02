#!/usr/bin/env python3
"""Trailer UEFN automatique — ligne de commande.

Exemples :
  python trailer.py mes_clips/ --titre "Drone Mining" --code 6522-7216-3724
  python trailer.py gameplay.mp4 --musique son.mp3 --textes "MINE ORES|FIGHT BOSS|UNLOCK DRONES"
  python trailer.py mes_clips/ --titre "Drone Mining" --miniatures-seulement
"""

import argparse
import sys
from pathlib import Path

from trailer_uefn.ffmpeg_outils import verifier_ffmpeg
from trailer_uefn.montage import MENTIONS_EPIC, RYTHMES, Options, creer_trailer, lister_clips


def main():
    p = argparse.ArgumentParser(description="Cree un trailer UEFN a partir de gameplay.")
    p.add_argument("clips", nargs="+", help="videos ou dossiers de videos")
    p.add_argument("-o", "--sortie", default="trailer/trailer.mp4", help="fichier video produit")
    p.add_argument("--titre", default="", help="nom de la map (carte de fin + miniatures)")
    p.add_argument("--code", default="", help="code de l'ile, ex. 1234-5678-9012")
    p.add_argument("--textes", default="",
                   help="bandeaux des sections separes par |, ex. \"MINE ORES|FIGHT BOSS\"")
    p.add_argument("--accroche", default="", help="gros texte pendant l'ouverture")
    p.add_argument("--final", default="", help="gros texte avant la fin, ex. \"THE ADVENTURE BEGINS\"")
    p.add_argument("--appel", default="PLAY NOW", help="texte au-dessus du code (vide = aucun)")
    p.add_argument("--musique", default="", help="mp3/wav ; sans, une piste est generee")
    p.add_argument("--duree", type=float, default=30, help="duree visee en secondes (defaut 30)")
    p.add_argument("--rythme", choices=sorted(RYTHMES), default="normal")
    p.add_argument("--vertical", action="store_true", help="format 9:16 (TikTok, Shorts)")
    p.add_argument("--fps", type=int, default=60, choices=(30, 60))
    p.add_argument("--couleur", default="#FFD400", help="couleur des bandeaux (defaut jaune)")
    p.add_argument("--logo", default="", help="PNG affiche pendant l'ouverture")
    p.add_argument("--image-fin", default="", help="visuel de la carte de fin (key art)")
    p.add_argument("--mentions", default=MENTIONS_EPIC, help="mentions legales de l'ouverture")
    p.add_argument("--sans-mentions", action="store_true")
    p.add_argument("--volume-jeu", type=float, default=0.35, help="son du jeu sous la musique (0 a 1)")
    p.add_argument("--miniatures", type=int, default=3, help="nombre de miniatures (0 = aucune)")
    p.add_argument("--badge", default="", help="pastille sur les miniatures, ex. NEW ou UPDATE")
    p.add_argument("--miniatures-seulement", action="store_true",
                   help="ne fait que les miniatures, sans trailer")
    p.add_argument("--garder-travail", action="store_true", help="conserve les fichiers temporaires")
    a = p.parse_args()

    opts = Options(
        titre=a.titre, code=a.code.strip(),
        textes=[t.strip() for t in a.textes.split("|") if t.strip()],
        accroche=a.accroche, texte_final=a.final, appel=a.appel, musique=a.musique,
        duree=a.duree, rythme=a.rythme, format="vertical" if a.vertical else "horizontal",
        fps=a.fps, accent=a.couleur, logo=a.logo, image_fin=a.image_fin,
        mentions="" if a.sans_mentions else a.mentions, volume_jeu=a.volume_jeu,
        miniatures=a.miniatures, badge=a.badge,
    )
    try:
        if a.miniatures_seulement:
            verifier_ffmpeg()
            from trailer_uefn.analyse import analyser_clip, noter_clips
            from trailer_uefn.miniature import generer_miniatures
            clips = [analyser_clip(c.chemin) for c in lister_clips(a.clips)]
            noter_clips(clips)
            generer_miniatures(clips, Path(a.sortie).parent, opts.titre, opts.accent,
                               opts.badge or None, max(1, opts.miniatures), opts.image_fin or None)
        else:
            creer_trailer(a.clips, a.sortie, opts, garder_travail=a.garder_travail)
    except Exception as e:  # message lisible plutot qu'une pile d'appels
        print(f"\nErreur : {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
