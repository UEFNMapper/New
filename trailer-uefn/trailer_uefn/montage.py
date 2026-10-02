"""Realisation du trailer : structure calee sur la musique, choix des plans, transitions,
textes et bruitages, puis rendu par le compositeur image par image."""

import json
import math
import re
import shutil
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

from . import ffmpeg_outils as ff
from . import musique_auto, textes
from .analyse import FPS_ANALYSE, analyser_clip, analyser_musique, noter_clips
from .miniature import generer_miniatures, meilleures_images, titre_miniature
from .rendu import Compositeur, Montage, Plan, Texte
from .sfx import Mixage

EXTENSIONS_VIDEO = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v"}
RYTHMES = {"lent": 2.4, "normal": 1.7, "rapide": 1.0}   # duree moyenne d'un plan (s)
# Formule demandee par les regles developpeurs d'Epic pour le materiel promotionnel
MENTIONS_EPIC = "This is not sponsored, endorsed, or administered by Epic Games, Inc."
AVANCE_VISUELLE = 0.025   # les images tombent un poil avant le temps : l'oeil percoit ca "pile"


@dataclass
class Options:
    titre: str = ""
    code: str = ""
    textes: list = field(default_factory=list)   # bandeaux des sections, dans l'ordre
    accroche: str = ""                           # texte pendant l'ouverture
    texte_final: str = ""                        # gros texte pendant le final
    appel: str = "PLAY NOW!"
    musique: str = ""                            # vide = musique generee
    duree: float = 30.0
    rythme: str = "normal"
    format: str = "horizontal"                   # ou "vertical" (TikTok / Shorts)
    fps: int = 60
    accent: str = "#FFD400"
    encre: str = "#111111"
    logo: str = ""
    image_fin: str = ""
    mentions: str = MENTIONS_EPIC
    volume_jeu: float = 0.3
    miniatures: int = 3
    badge: str = ""
    intensite: float = 1.0                       # 0.6 doux, 1 normal, 1.4 max
    bruitages: bool = True
    profil: str = "reseaux"                      # "reseaux" ou "ile" (sans textes ni effets forts)


@dataclass(eq=False)
class Clip:
    chemin: str
    etiquette: str = None
    analyse: object = None


# ---------------------------------------------------------------- chargement

def lister_clips(chemins):
    """Developpe les dossiers et lit l'etiquette dans le nom : '02_FIGHT BOSS.mp4'."""
    fichiers = []
    for chemin in map(Path, chemins):
        if chemin.is_dir():
            fichiers += sorted(p for p in chemin.iterdir() if p.suffix.lower() in EXTENSIONS_VIDEO)
        elif chemin.exists():
            fichiers.append(chemin)
        else:
            raise FileNotFoundError(f"Introuvable : {chemin}")
    if not fichiers:
        raise FileNotFoundError("Aucune video trouvee.")
    clips = []
    for f in fichiers:
        m = re.match(r"^\s*\d+\s*[-_.)]+\s*(.+)$", f.stem)
        etiquette = m.group(1).replace("_", " ").strip().upper() if m else None
        clips.append(Clip(str(f), etiquette or None))
    return clips


# ------------------------------------------------------------ choix des plans

class Selecteur:
    """Meilleur passage encore neuf des clips ; un passage deja montre est penalise."""

    def __init__(self, clips):
        self.usure = {id(c): np.zeros(len(c.analyse.score)) for c in clips}

    def choisir(self, candidats, duree, critere="score"):
        n = int(math.ceil(duree * FPS_ANALYSE)) + 1
        meilleur = None
        for c in candidats:
            a = c.analyse
            valeurs = getattr(a, critere)
            if len(valeurs) < n:
                continue
            cs = np.concatenate([[0], np.cumsum(valeurs)])
            moyenne = (cs[n:] - cs[:-n]) / n
            debuts = np.arange(len(moyenne))
            cc = np.concatenate([[0], np.cumsum(a.coupes)])
            interieur = cc[debuts + n - 1] - cc[np.minimum(debuts + 2, len(cc) - 1)]
            uc = np.concatenate([[0], np.cumsum(self.usure[id(c)])])
            usure = (uc[n:] - uc[:-n]) / n
            note = moyenne - 0.6 * (interieur > 0) - 1.5 * usure
            i = int(np.argmax(note))
            if meilleur is None or note[i] > meilleur[0]:
                meilleur = (note[i], c, i)
        if meilleur:
            _, c, i = meilleur
            marge = FPS_ANALYSE // 3
            self.usure[id(c)][max(0, i - marge): i + n + marge] += 1
            return c, i / FPS_ANALYSE
        c = max(candidats, key=lambda c: c.analyse.infos["duree"])   # clips tres courts
        return c, 0.0


def _beats_par_plan(periode, rythme):
    cible = RYTHMES.get(rythme, 1.7) / periode
    return min((1, 2, 4, 8), key=lambda b: abs(math.log(b / cible)))


# --------------------------------------------------------------- realisation

def _taille(opts):
    return (1080, 1920) if opts.format == "vertical" else (1920, 1080)


def _etiquettes(clips, opts):
    etiquettes = []
    for c in clips:
        if c.etiquette and c.etiquette not in etiquettes:
            etiquettes.append(c.etiquette)
    if etiquettes:
        return etiquettes, {e: [c for c in clips if c.etiquette == e] for e in etiquettes}
    if opts.textes:
        etiquettes = [t.upper() for t in opts.textes]
        if len(clips) == len(etiquettes):
            return etiquettes, {e: [c] for e, c in zip(etiquettes, clips)}
        return etiquettes, {e: clips for e in etiquettes}
    return [None], {None: clips}


def realiser(clips, musique, opts, dossier, journal=print):
    """Construit le Montage (plans, textes, effets) et la liste des bruitages."""
    W, H = _taille(opts)
    vertical = H > W
    ile = opts.profil == "ile"
    B = musique.periode
    M = 4 * B
    sons = []          # (nom, instant, gain, ancre)

    def mesures_pour(secondes, mini=1):
        return max(mini, round(secondes / M))

    # --- structure en mesures
    n_intro = 1 if M >= 1.4 else 2
    n_titre = (1 if M >= 1.5 else 2) if (opts.titre and not ile) else 0
    n_climax = 1 if M >= 1.6 else 2
    n_appel = (1 if M >= 1.5 else 2) if (opts.appel and not ile) else 0
    n_fin = 0 if ile else mesures_pour(3.4, 2 if M < 1.5 else 1)
    etiquettes, par_section = _etiquettes(clips, opts)
    n_total = max(round(opts.duree / M), n_intro + n_titre + n_fin + len(etiquettes))
    n_sections = n_total - (n_intro + n_titre + n_climax + n_appel + n_fin)
    for retirer in ("climax", "appel"):
        if n_sections >= len(etiquettes):
            break
        if retirer == "climax" and n_climax:
            n_sections += n_climax
            n_climax = 0
        elif retirer == "appel" and n_appel:
            n_sections += n_appel
            n_appel = 0
    if n_sections < len(etiquettes):
        journal(f"  attention : trop de sections pour {opts.duree:.0f} s, on garde les {max(1, n_sections)} premieres")
        etiquettes = etiquettes[:max(1, n_sections)]
        n_sections = max(1, n_sections)

    # --- debut de la musique : le drop tombe a la fin de l'ouverture
    drop = n_intro * M
    if musique.drop and musique.drop - drop >= 0:
        debut_musique = musique.drop - drop
    else:
        premieres = musique.mesures(0, 12)
        debut_musique = premieres[0] if premieres else musique.phase
    duree = n_total * M

    bpp = _beats_par_plan(B, opts.rythme)
    sel = Selecteur(clips)
    plans, txts = [], []
    flashs, secousses, lignes = [], [], []
    k = opts.intensite

    def nouveau_plan(debut, d, candidats, critere="score", **kw):
        plan = Plan(debut, d, **kw)
        besoin = plan.temps_source(d + 0.4)
        plan.clip, plan.source = sel.choisir(candidats, besoin, critere)
        plans.append(plan)
        return plan

    def lier(precedent, transition):
        """Une transition s'annonce sur la fin du plan precedent."""
        if precedent is not None and transition in ("zoom", "glisse", "flash"):
            precedent.sortie = transition

    def sprite(img):
        return textes.vers_bgra(img)

    # 1. Ouverture : le plan le plus spectaculaire, au ralenti si possible, bandes cinema
    ralenti = max(c.analyse.infos["fps"] for c in clips) >= 50
    nouveau_plan(0, drop, clips, "score", vitesse="ralenti" if ralenti else "constante",
                 camera="poussee", bandes=not ile, entree="coupe")
    if not ile:
        if opts.bruitages:
            sons.append(("montee", drop, 0.9, 1.0))
            sons.append(("impact", drop, 1.0, 0.0))
        flashs.append((drop, 1.0))
        secousses.append((drop, 26))
        if opts.mentions:
            img = sprite(textes.mentions(opts.mentions, W, H))
            txts.append(Texte(0, drop + 0.4, "mentions", img, x=W / 2, y=H * 0.965 - img.shape[0] / 2))
        if opts.logo:
            logo = Image.open(opts.logo).convert("RGBA")
            cible = int(W * (0.3 if vertical else 0.13))
            logo = logo.resize((cible, max(1, int(logo.height * cible / logo.width))), Image.LANCZOS)
            img = sprite(logo)
            txts.append(Texte(0, drop, "logo", img, x=W - img.shape[1] / 2 - W * 0.03,
                              y=H * 0.9 - img.shape[0] / 2))
        if opts.accroche:
            img = sprite(textes.titre(opts.accroche, H, W * 0.86, "contour", echelle=0.1))
            txts.append(Texte(max(0.15, drop - 2.0), drop, "accroche", img, x=W / 2, y=H * 0.5))

    t = drop
    # 2. Titre de la map, en plein drop
    if n_titre:
        d = n_titre * M
        p = nouveau_plan(t, d, clips, "score", vitesse="rampe", camera="poussee", entree="flash",
                         assombrir=0.32)
        img = sprite(titre_miniature(opts.titre, W * 0.84, H * (0.34 if not vertical else 0.24), opts.accent))
        txts.append(Texte(t + 0.02, t + d, "titre", img, x=W / 2, y=H * 0.5))
        lignes.append((t, t + d))
        p.sortie = "zoom"
        t += d

    # 3. Sections : une fonctionnalite par bandeau
    base, reste = divmod(n_sections, len(etiquettes))
    cycle = ["zoom", "glisse", "flash"]
    cameras = ["derive", "recul", "poussee"]
    for idx, e in enumerate(etiquettes):
        nb = base + (1 if idx < reste else 0)
        if nb <= 0:
            continue
        beats, total, i = [], nb * 4, 0
        while total > 0:
            b = min(bpp, total)
            if i % 3 == 2 and b >= 2:
                b //= 2
            beats.append(b)
            total -= b
            i += 1
        debut_section = t
        precedent = plans[-1] if plans else None
        transition = "fondu" if ile else ("flash" if (idx == 0 and not n_titre) else cycle[idx % 3])
        choix = []
        for j, b in enumerate(beats):
            vitesse = "rampe" if (j == 0 and not ile) else "constante"
            essai = Plan(0, b * B, vitesse=vitesse)
            c, src = sel.choisir(par_section[e], essai.temps_source(b * B + 0.4))
            choix.append((clips.index(c), src, c, b, vitesse))
        premier = choix[0]
        suite = sorted(choix[1:], key=lambda x: (x[0], x[1]))   # ordre chronologique
        for j, (_, src, c, b, vitesse) in enumerate([premier] + suite):
            d = b * B
            if j == 0:
                entree = transition
            else:
                entree = "fondu" if (j % 3 == 2) else "coupe"
            p = Plan(t, d, c, src, vitesse, entree, camera=cameras[(idx + j) % 3])
            plans.append(p)
            t += d
        lier(precedent, transition)
        if transition == "flash" and not ile:
            flashs.append((debut_section, 0.8))
        if e and not ile:
            fond, ecrit = textes.bandeau_morceaux(e, H if not vertical else int(H * 0.62), opts.accent, opts.encre)
            y = H * (0.74 if vertical else 0.865)
            txts.append(Texte(debut_section + 0.06, t - 0.02, "bandeau", sprite(fond), sprite(ecrit),
                              x=W * 0.035, y=y, angle=2.0))
            if opts.bruitages:
                sons.append(("swish", debut_section + 0.06, 0.8, 0.3))
        if opts.bruitages and not ile and transition in ("zoom", "glisse") and debut_section > drop + 0.01:
            sons.append(("whoosh", debut_section, 0.9, 0.75))

    # 4. Final nerveux : une coupe par temps, secousses
    if n_climax:
        debut_climax = t
        pas = 1 if B >= 0.33 else 2
        precedent = plans[-1]
        lier(precedent, "zoom")
        for j in range(0, n_climax * 4, pas):
            nouveau_plan(t, pas * B, clips, "score", entree="zoom" if j == 0 else "coupe",
                         camera="poussee", secousse=0 if ile else 14)
            if not ile and j % 2 == 0:
                flashs.append((t, 0.35))
            t += pas * B
        if opts.bruitages and not ile:
            sons.append(("whoosh", debut_climax, 0.9, 0.75))
        if opts.texte_final and not ile:
            img = sprite(titre_miniature(opts.texte_final, W * 0.8, H * 0.22, opts.accent))
            txts.append(Texte(debut_climax + 0.02, t, "final", img, x=W / 2, y=H * 0.5))
            if opts.bruitages:
                sons.append(("pop", debut_climax + 0.02, 0.8, 0.0))

    # 5. Appel a jouer sur fond de lignes de vitesse
    if n_appel:
        d = n_appel * M
        lier(plans[-1], "zoom")
        nouveau_plan(t, d, clips, "score", entree="zoom", camera="poussee", assombrir=0.35, flou=1.0)
        img = sprite(textes.titre(opts.appel, H, W * 0.6, "boite", opts.accent, opts.encre,
                                  echelle=0.15 if not vertical else 0.08))
        txts.append(Texte(t + 0.03, t + d, "appel", img, x=W / 2, y=H * 0.5, angle=3.0))
        lignes.append((t, t + d))
        secousses.append((t, 18))
        if opts.bruitages:
            sons.append(("whoosh", t, 0.9, 0.75))
            sons.append(("impact", t + 0.03, 0.8, 0.0))
        t += d

    # 6. Carte de fin : visuel, nom de la map, PLAY NOW, code
    if n_fin:
        d = duree - t
        fond = _image_fond_fin(clips, opts, dossier, W, H)
        lier(plans[-1], "flash")
        plans.append(Plan(t, d, image=fond, entree="flash", camera="poussee"))
        flashs.append((t, 0.9))
        secousses.append((t, 12))
        if opts.titre:
            img = sprite(titre_miniature(opts.titre, W * 0.86, H * (0.3 if not vertical else 0.2), opts.accent))
            txts.append(Texte(t, duree, "fin_titre", img, x=W / 2, y=H * (0.26 if vertical else 0.24)))
        if opts.appel:
            img = sprite(textes.titre(opts.appel, H, W * 0.5, "boite", opts.accent, opts.encre, echelle=0.055))
            txts.append(Texte(t + 0.3, duree, "fin_appel", img, x=W / 2, y=H * (0.66 if vertical else 0.64), angle=2.0))
        if opts.code:
            img = sprite(textes.titre(opts.code, H, W * 0.86, "contour", echelle=0.09 if vertical else 0.13))
            txts.append(Texte(t + 0.5, duree, "fin_code", img, x=W / 2, y=H * (0.76 if vertical else 0.8)))
        if opts.bruitages:
            sons.append(("impact", t, 1.0, 0.0))
            if opts.appel:
                sons.append(("pop", t + 0.3, 0.7, 0.0))
            if opts.code:
                sons.append(("pop", t + 0.5, 0.8, 0.0))
    elif plans:
        plans[-1].duree = duree - plans[-1].debut

    montage = Montage(W, H, opts.fps, duree, plans, txts, flashs, secousses, lignes, B,
                      0.6 if ile else k)
    return montage, sons, debut_musique - AVANCE_VISUELLE


def _normalisation(audio):
    """Loudnorm en deux passes : -14 LUFS precis (valeur demandee par Epic et les reseaux)."""
    cible = "I=-14:TP=-1.2:LRA=11"
    try:
        proc = ff.executer(["ffmpeg", "-hide_banner", "-nostats", "-i", str(audio), "-af",
                            f"loudnorm={cible}:print_format=json", "-f", "null", "-"])
        texte = proc.stderr.decode("utf-8", "replace")
        m = json.loads(texte[texte.rindex("{"):texte.rindex("}") + 1])
        return (f"loudnorm={cible}:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
                f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:"
                f"offset={m['target_offset']}:linear=true")
    except (ValueError, KeyError, ff.ErreurFFmpeg):
        return f"loudnorm={cible}"


def _image_fond_fin(clips, opts, dossier, largeur, hauteur):
    """Visuel de la carte de fin : key art fourni, sinon la plus belle image du gameplay."""
    if opts.image_fin:
        fond = Image.open(opts.image_fin).convert("RGB")
    else:
        clip, t = meilleures_images([c.analyse for c in clips], 1)[0]
        brut = Path(dossier) / "fond_fin_brut.png"
        ff.extraire_image(clip.chemin, t, brut)
        fond = Image.open(brut).convert("RGB")
        fond = ImageEnhance.Color(fond).enhance(1.35).filter(ImageFilter.GaussianBlur(4))
        fond = ImageEnhance.Brightness(fond).enhance(0.75)
    fond = textes._couvrir(fond, largeur, hauteur).convert("RGBA")
    degrade = Image.linear_gradient("L").resize((largeur, hauteur))
    noir = Image.new("RGBA", (largeur, hauteur), (0, 0, 0, 255))
    noir.putalpha(degrade.point(lambda v: int(190 * max(0, (v / 255 - 0.4) / 0.6) ** 1.3)))
    fond.alpha_composite(noir)
    chemin = Path(dossier) / "fond_fin.png"
    fond.convert("RGB").save(chemin)
    return str(chemin)


# --------------------------------------------------------------- point d'entree

def creer_trailer(chemins_clips, sortie, opts, journal=print, garder_travail=False,
                  progression=None):
    """Analyse, realise et rend le trailer. Renvoie le chemin produit.

    progression(fraction, etape) est appelee au fil du travail (fraction entre 0 et 1).
    """
    def avancer(fraction, etape):
        if progression:
            progression(min(1.0, fraction), etape)

    ff.verifier_ffmpeg()
    sortie = Path(sortie)
    sortie.parent.mkdir(parents=True, exist_ok=True)
    if opts.code and not re.fullmatch(r"\d{4}-\d{4}-\d{4}", opts.code):
        journal(f"  attention : le code '{opts.code}' n'a pas le format 1234-5678-9012")

    journal("1/5 Analyse du gameplay...")
    # On accepte des chemins (fichiers / dossiers) ou des Clip deja etiquetes (interface)
    clips = [c for c in chemins_clips if isinstance(c, Clip)] or lister_clips(chemins_clips)
    for i, c in enumerate(clips):
        avancer(0.12 * i / len(clips), "Analyse du gameplay")
        c.analyse = analyser_clip(c.chemin, journal)
    noter_clips([c.analyse for c in clips])

    dossier = Path(tempfile.mkdtemp(prefix="trailer_uefn_"))
    try:
        avancer(0.12, "Analyse de la musique")
        journal("2/5 Analyse de la musique...")
        chemin_musique = opts.musique
        if not chemin_musique:
            journal("  pas de musique fournie : generation d'une piste de secours")
            chemin_musique = musique_auto.generer(dossier / "musique.wav", opts.duree + 15)
        musique = analyser_musique(chemin_musique, journal)

        avancer(0.16, "Realisation du montage")
        journal("3/5 Realisation...")
        montage, sons, debut_musique = realiser(clips, musique, opts, dossier, journal)
        for p in montage.plans:
            nom = Path(p.clip.chemin).name if p.clip else "carte de fin"
            journal(f"  {p.debut:6.2f}s {p.duree:4.2f}s  {nom} @ {p.source:.1f}s  "
                    f"{p.entree}>{p.sortie} {p.vitesse} {p.camera}")

        journal("4/5 Rendu image par image...")
        video = dossier / "video.mp4"
        Compositeur(montage, video, journal,
                    lambda f: avancer(0.18 + 0.7 * f, "Rendu image par image")).rendre()

        avancer(0.89, "Musique et bruitages")
        journal("5/5 Musique, bruitages et export...")
        mix = Mixage(montage.duree)
        mix.poser_musique(chemin_musique, debut_musique)
        if opts.volume_jeu > 0:
            for p in montage.plans:
                if p.clip and p.vitesse == "constante" and p.clip.analyse.infos["audio"]:
                    mix.poser_jeu(p.clip.chemin, p.source, p.debut, p.duree, opts.volume_jeu)
        for nom, instant, gain, ancre in sons:
            mix.bruitage(nom, instant, gain, ancre)
        audio = mix.ecrire(dossier / "audio.wav")
        ff.executer(["ffmpeg", "-v", "error", "-y", "-i", str(video), "-i", str(audio),
                     "-map", "0:v", "-map", "1:a", "-c:v", "copy",
                     "-af", _normalisation(audio) + ",aresample=48000",
                     "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", str(sortie)])
        journal(f"Trailer pret : {sortie} ({montage.duree:.1f} s)")

        if opts.miniatures:
            avancer(0.95, "Miniatures")
            journal("Bonus : miniatures...")
            generer_miniatures([c.analyse for c in clips], sortie.parent, opts.titre or "",
                               opts.accent, opts.badge or None, opts.miniatures,
                               opts.image_fin or None, journal)
    finally:
        if garder_travail:
            journal(f"  fichiers de travail conserves dans {dossier}")
        else:
            shutil.rmtree(dossier, ignore_errors=True)
    avancer(1.0, "Termine")
    return sortie
