"""Montage automatique : plan de coupe cale sur la musique, effets, textes, rendu final."""

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
from .miniature import generer_miniatures, meilleures_images

EXTENSIONS_VIDEO = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v"}
RYTHMES = {"lent": 2.6, "normal": 1.8, "rapide": 1.1}   # duree moyenne d'un plan (s)
MENTIONS_EPIC = "This content is not affiliated with, sponsored, or endorsed by Epic Games, Inc."


@dataclass
class Options:
    titre: str = ""
    code: str = ""
    textes: list = field(default_factory=list)   # bandeaux des sections, dans l'ordre
    accroche: str = ""                           # gros texte pendant l'ouverture
    texte_final: str = ""                        # gros texte juste avant la fin
    appel: str = "PLAY NOW"
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
    volume_jeu: float = 0.35
    miniatures: int = 3
    badge: str = ""


@dataclass(eq=False)
class Clip:
    chemin: str
    etiquette: str = None
    analyse: object = None


@dataclass(eq=False)
class Plan:
    debut: float
    duree: float
    clip: Clip = None
    source: float = 0.0
    vitesse: float = 1.0
    effets: tuple = ()
    image: str = None          # pour la carte de fin


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


# -------------------------------------------------------------- planification

class Selecteur:
    """Choisit, pour chaque plan, le meilleur passage des clips, en evitant les redites.

    Chaque passage deja montre est penalise selon le nombre de fois ou il a servi :
    tant qu'il reste du neuf on prend du neuf, et sinon le moins use.
    """

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
            # Eviter qu'un changement de plan de la source tombe au milieu du notre
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
            return c, i / FPS_ANALYSE, 1.0
        # Aucun clip assez long : on prend le plus long en le ralentissant un peu
        c = max(candidats, key=lambda c: c.analyse.infos["duree"])
        dispo = max(0.2, c.analyse.infos["duree"] - 0.2)
        return c, 0.0, max(0.5, min(1.0, dispo / duree))


def _beats_par_plan(periode, rythme):
    cible = RYTHMES.get(rythme, 1.8) / periode
    return min((1, 2, 4, 8), key=lambda b: abs(math.log(b / cible)))


def planifier(clips, musique, opts, journal=print):
    temps = musique.periode
    mesure = 4 * temps

    # Ouverture : 1 a 2 mesures calmes avant le drop, puis le gros du trailer.
    k = max(1, round((3.6 if opts.accroche else 3.0) / mesure))
    while k * mesure < 1.6:
        k += 1
    if musique.drop and musique.drop - k * mesure >= 0:
        debut_musique = musique.drop - k * mesure
    else:
        premieres = musique.mesures(0, 12)
        debut_musique = premieres[0] if premieres else musique.phase
    if musique.duree - debut_musique < opts.duree:
        journal("  attention : musique plus courte que le trailer, elle sera bouclee")

    nb_fin = 1
    while nb_fin * mesure < 3.2:
        nb_fin += 1
    nb_climax = (1 if mesure >= 1.8 else 2) if opts.texte_final else 0
    nb_total = max(k + nb_fin + nb_climax + 2, round(opts.duree / mesure))
    debut_fin = nb_total - nb_fin
    fin_sections = debut_fin - nb_climax

    # Sections (une par bandeau)
    etiquettes = []
    for c in clips:
        if c.etiquette and c.etiquette not in etiquettes:
            etiquettes.append(c.etiquette)
    par_section = {}
    if etiquettes:
        for e in etiquettes:
            par_section[e] = [c for c in clips if c.etiquette == e]
    elif opts.textes:
        etiquettes = [t.upper() for t in opts.textes]
        if len(clips) == len(etiquettes):
            par_section = {e: [c] for e, c in zip(etiquettes, clips)}
        else:
            par_section = {e: clips for e in etiquettes}
    else:
        etiquettes = [None]
        par_section = {None: clips}
    dispo = fin_sections - k
    if len(etiquettes) > dispo:
        journal(f"  attention : trop de sections pour {opts.duree:.0f} s, "
                f"on garde les {dispo} premieres (augmente la duree pour tout afficher)")
        etiquettes = etiquettes[:dispo]

    bpp = _beats_par_plan(temps, opts.rythme)
    sel = Selecteur(clips)
    plans, sections = [], []

    # 1. Ouverture : le plus beau passage, en lente poussee de camera
    morceaux = [k] if k < 2 or k * mesure <= 4.5 else [k // 2, k - k // 2]
    t = 0
    for m in morceaux:
        c, src, v = sel.choisir(clips, m * mesure, "beaute")
        plans.append(Plan(t * mesure, m * mesure, c, src, v, ("poussee",)))
        t += m

    # 2. Sections : nombre de mesures reparti, coupes sur les temps
    base, reste = divmod(dispo, len(etiquettes))
    mesure_courante = k
    for idx, e in enumerate(etiquettes):
        nb = base + (1 if idx < reste else 0)
        beats = []
        total, i = nb * 4, 0
        while total > 0:
            b = min(bpp, total)
            if i % 3 == 2 and b >= 2:
                b //= 2                       # respiration : un plan plus court de temps en temps
            beats.append(b)
            total -= b
            i += 1
        choix = []
        for b in beats:
            c, src, v = sel.choisir(par_section[e], b * temps)
            choix.append((clips.index(c), src, c, v, b))
        choix.sort(key=lambda x: (x[0], x[1]))  # ordre chronologique dans la section
        beat = mesure_courante * 4
        for j, (_, src, c, v, b) in enumerate(choix):
            effets = ("flash", "punch") if j == 0 else (("derive",) if j % 2 else ())
            plans.append(Plan(beat * temps, b * temps, c, src, v, effets))
            beat += b
        sections.append((e, mesure_courante * mesure, (mesure_courante + nb) * mesure))
        mesure_courante += nb

    # 3. Climax : coupes sur chaque temps avec secousse
    if nb_climax:
        pas = 1 if temps >= 0.35 else 2
        debut = fin_sections * 4
        for beat in range(debut, debut + nb_climax * 4, pas):
            c, src, v = sel.choisir(clips, pas * temps)
            plans.append(Plan(beat * temps, pas * temps, c, src, v, ("punch", "secousse")))

    # 4. Carte de fin
    plans.append(Plan(debut_fin * mesure, nb_fin * mesure, effets=("flash", "derive")))
    duree = nb_total * mesure
    return {"plans": plans, "sections": sections, "debut_musique": debut_musique,
            "ouverture": k * mesure, "climax": (fin_sections * mesure, debut_fin * mesure),
            "duree": duree}


# --------------------------------------------------------------------- rendu

def _taille(opts):
    return (1080, 1920) if opts.format == "vertical" else (1920, 1080)


def _filtre_mouvement(effets, duree, largeur, hauteur):
    """Zoom / secousse image par image (scale en eval=frame puis recadrage)."""
    termes = []
    if "punch" in effets:
        termes.append("0.10*pow(max(0,1-t/0.32),2)")
    if "poussee" in effets:
        termes.append(f"0.08*t/{duree:.3f}")
    if "derive" in effets:
        termes.append(f"0.045*t/{duree:.3f}")
    if "secousse" in effets:
        termes.append("0.05")
    if not termes:
        return ""
    f = "(1+" + "+".join(termes) + ")"
    sx = sy = "0"
    if "secousse" in effets:
        amp = "max(0,1-t/0.35)"
        sx = f"{largeur * 0.012:.1f}*{amp}*sin(t*61)"
        sy = f"{hauteur * 0.012:.1f}*{amp}*cos(t*47)"
    return (f",scale=w='2*trunc({largeur}*{f}/2)':h='2*trunc({hauteur}*{f}/2)':eval=frame"
            f",crop={largeur}:{hauteur}:x='(iw-{largeur})/2+{sx}':y='(ih-{hauteur})/2+{sy}'")


def _cadrage(largeur, hauteur):
    if hauteur > largeur:   # vertical : gameplay au centre, fond flou derriere
        h_jeu = int(hauteur * 0.42) // 2 * 2
        # Flou calcule en petite taille puis agrandi : bien plus rapide qu'un flou en 1080x1920
        pl, ph = largeur // 8, hauteur // 8
        return (f"split[f][b];[b]scale={pl}:{ph}:force_original_aspect_ratio=increase,"
                f"crop={pl}:{ph},boxblur=6:2,scale={largeur}:{hauteur},eq=brightness=-0.12[fond];"
                f"[f]scale=-2:{h_jeu},crop='min(iw,{largeur})':{h_jeu}[jeu];"
                f"[fond][jeu]overlay=(W-w)/2:(H-h)/2")
    return (f"scale={largeur}:{hauteur}:force_original_aspect_ratio=increase,"
            f"crop={largeur}:{hauteur}")


def _encodage_intermediaire(fps):
    return ["-c:v", "libx264", "-preset", "veryfast", "-crf", "15", "-pix_fmt", "yuv420p",
            "-r", str(fps), "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2"]


def rendre_plan(plan, nb_images, sortie, opts):
    largeur, hauteur = _taille(opts)
    fps = opts.fps
    duree = nb_images / fps
    mouvement = _filtre_mouvement(plan.effets, duree, largeur, hauteur)
    finition = ",eq=saturation=1.12:contrast=1.04,unsharp=5:5:0.35"
    if "flash" in plan.effets:
        finition += ",fade=t=in:st=0:d=0.2:color=white"
    finition += ",setsar=1,format=yuv420p"

    if plan.image:
        # Entrees bornees par -t : sinon ffmpeg 6 ne s'arrete jamais (image en boucle + silence)
        cmd = ["ffmpeg", "-v", "error", "-y", "-loop", "1", "-framerate", str(fps),
               "-t", f"{duree + 0.1:.3f}", "-i", plan.image,
               "-f", "lavfi", "-t", f"{duree + 0.1:.3f}", "-i", "anullsrc=r=48000:cl=stereo",
               "-filter_complex",
               f"[0:v]setpts=PTS-STARTPTS{mouvement}{finition}[v];[1:a]atrim=duration={duree:.4f}[a]"]
    else:
        info = plan.clip.analyse.infos
        v = plan.vitesse
        lecture = duree * v + 0.15
        ralenti = f",setpts=PTS/{v:.4f}" if v != 1.0 else ""
        video = (f"[0:v]setpts=PTS-STARTPTS{ralenti},fps={fps},{_cadrage(largeur, hauteur)},"
                 f"tpad=stop_mode=clone:stop_duration={duree:.3f}{mouvement}{finition}[v]")
        if info["audio"]:
            tempo = f",atempo={v:.4f}" if v != 1.0 else ""
            audio = (f"[0:a]asetpts=PTS-STARTPTS{tempo},aresample=48000,"
                     f"aformat=channel_layouts=stereo,apad,atrim=duration={duree:.4f}[a]")
            entrees = ["-ss", f"{plan.source:.3f}", "-t", f"{lecture:.3f}", "-i", plan.clip.chemin]
        else:
            audio = f"[1:a]atrim=duration={duree:.4f}[a]"
            entrees = ["-ss", f"{plan.source:.3f}", "-t", f"{lecture:.3f}", "-i", plan.clip.chemin,
                       "-f", "lavfi", "-t", f"{duree + 0.1:.3f}", "-i", "anullsrc=r=48000:cl=stereo"]
        cmd = ["ffmpeg", "-v", "error", "-y", *entrees, "-filter_complex", f"{video};{audio}"]
    cmd += ["-map", "[v]", "-map", "[a]", "-frames:v", str(nb_images),
            *_encodage_intermediaire(fps), str(sortie)]
    ff.executer(cmd)


def _image_fond_fin(clips, opts, dossier):
    largeur, hauteur = _taille(opts)
    if opts.image_fin:
        fond = Image.open(opts.image_fin)
    else:
        clip, t = meilleures_images([c.analyse for c in clips], 1)[0]
        brut = Path(dossier) / "fond_fin.png"
        ff.extraire_image(clip.chemin, t, brut)
        fond = Image.open(brut)
        fond = ImageEnhance.Color(fond.convert("RGB")).enhance(1.3).filter(ImageFilter.GaussianBlur(5))
        fond = ImageEnhance.Brightness(fond).enhance(0.8)
    carte = textes.carte_fin(fond, largeur, hauteur, opts.titre, opts.code,
                             opts.accent, opts.encre, opts.appel)
    chemin = Path(dossier) / "carte_fin.png"
    carte.save(chemin)
    return str(chemin)


def _calques(plan_global, opts, dossier):
    """Textes poses par-dessus le montage : (png, debut, fin, x, y, animation)."""
    largeur, hauteur = _taille(opts)
    vertical = hauteur > largeur
    calques = []

    def sauver(img, nom):
        chemin = Path(dossier) / f"{nom}.png"
        img.save(chemin)
        return str(chemin), img.width, img.height

    ouverture = plan_global["ouverture"]
    if opts.mentions:
        p, w, h = sauver(textes.mentions(opts.mentions, largeur, hauteur), "mentions")
        calques.append((p, 0, ouverture, (largeur - w) // 2, int(hauteur * 0.965) - h, "fondu"))
    if opts.logo:
        logo = Image.open(opts.logo).convert("RGBA")
        cible = int(largeur * (0.30 if vertical else 0.14))
        logo = logo.resize((cible, max(1, int(logo.height * cible / logo.width))), Image.LANCZOS)
        p, w, h = sauver(logo, "logo")
        calques.append((p, 0, ouverture, largeur - w - int(largeur * 0.03),
                        int(hauteur * 0.93) - h, "fondu"))
    if opts.accroche:
        p, w, h = sauver(textes.titre(opts.accroche, hauteur, largeur * 0.88, "contour"), "accroche")
        calques.append((p, max(0.25, ouverture - 2.4), ouverture, (largeur - w) // 2,
                        (hauteur - h) // 2, "monte"))
    for idx, (etiquette, debut, fin) in enumerate(plan_global["sections"]):
        if not etiquette:
            continue
        img = textes.bandeau(etiquette, hauteur if not vertical else int(hauteur * 0.62),
                             opts.accent, opts.encre)
        p, w, h = sauver(img, f"bandeau_{idx}")
        y = int(hauteur * (0.70 if vertical else 0.88)) - h // 2
        calques.append((p, debut + 0.08, fin - 0.04, int(largeur * 0.035), y, "glisse"))
    if opts.texte_final:
        debut, fin = plan_global["climax"]
        p, w, h = sauver(textes.titre(opts.texte_final, hauteur, largeur * 0.88, "contour"), "final")
        calques.append((p, debut, fin, (largeur - w) // 2, (hauteur - h) // 2, "monte"))
    return calques


def _assembler(segments, calques, plan_global, opts, musique_chemin, sortie, dossier):
    liste = Path(dossier) / "segments.txt"
    liste.write_text("".join(f"file '{Path(s).as_posix()}'\n" for s in segments), encoding="utf-8")
    corps = Path(dossier) / "corps.mkv"
    ff.executer(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(liste),
                 "-c", "copy", str(corps)])

    duree = plan_global["duree"]
    fps = opts.fps
    entrees = ["-i", str(corps), "-stream_loop", "-1", "-ss", f"{plan_global['debut_musique']:.3f}",
               "-i", str(musique_chemin)]
    filtres, courant = [], "[0:v]"
    for j, (png, debut, fin, x, y, anim) in enumerate(calques):
        entrees += ["-loop", "1", "-framerate", str(fps), "-t", f"{duree:.3f}", "-i", png]
        e = j + 2
        filtres.append(f"[{e}:v]format=rgba,fade=t=in:st={debut:.3f}:d=0.14:alpha=1[c{j}]")
        p = f"min(1,max(0,(t-{debut:.3f})/0.22))"
        if anim == "glisse":
            px, py = f"{x}-({x}+w+30)*pow(1-{p},3)", str(y)
        elif anim == "monte":
            px, py = str(x), f"{y}+{int(_taille(opts)[1] * 0.05)}*pow(1-{p},3)"
        else:
            px, py = str(x), str(y)
        filtres.append(f"{courant}[c{j}]overlay=x='{px}':y='{py}':eval=frame:"
                       f"enable='between(t,{debut:.3f},{fin:.3f})'[v{j}]")
        courant = f"[v{j}]"
    filtres.append(f"{courant}format=yuv420p[vout]")

    fondu = min(1.5, duree * 0.1)
    musique = (f"[1:a]atrim=duration={duree:.3f},asetpts=PTS-STARTPTS,aresample=48000,"
               f"aformat=channel_layouts=stereo,afade=t=in:d=0.04,"
               f"afade=t=out:st={duree - fondu:.3f}:d={fondu:.3f}")
    if opts.volume_jeu > 0:
        filtres.append(musique + "[m]")
        filtres.append(f"[0:a]volume={opts.volume_jeu:.2f}[g]")
        filtres.append("[m][g]amix=inputs=2:duration=first:dropout_transition=0,volume=2[mix]")
        source_audio = "[mix]"
    else:
        filtres.append(musique + "[mix]")
        source_audio = "[mix]"
    filtres.append(f"{source_audio}loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[aout]")

    ff.executer(["ffmpeg", "-v", "error", "-y", *entrees, "-filter_complex", ";".join(filtres),
                 "-map", "[vout]", "-map", "[aout]", "-t", f"{duree:.3f}",
                 "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
                 "-r", str(fps), "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
                 str(sortie)])


def creer_trailer(chemins_clips, sortie, opts, journal=print, garder_travail=False):
    """Point d'entree : analyse, planifie et rend le trailer. Renvoie le chemin produit."""
    ff.verifier_ffmpeg()
    sortie = Path(sortie)
    sortie.parent.mkdir(parents=True, exist_ok=True)
    if opts.code and not re.fullmatch(r"\d{4}-\d{4}-\d{4}", opts.code):
        journal(f"  attention : le code '{opts.code}' n'a pas le format 1234-5678-9012")

    journal("1/5 Analyse du gameplay...")
    # On accepte des chemins (fichiers / dossiers) ou des Clip deja etiquetes (interface)
    clips = [c for c in chemins_clips if isinstance(c, Clip)] or lister_clips(chemins_clips)
    for c in clips:
        c.analyse = analyser_clip(c.chemin, journal)
    noter_clips([c.analyse for c in clips])

    dossier = Path(tempfile.mkdtemp(prefix="trailer_uefn_"))
    try:
        journal("2/5 Analyse de la musique...")
        chemin_musique = opts.musique
        if not chemin_musique:
            journal("  pas de musique fournie : generation d'une piste de secours")
            chemin_musique = musique_auto.generer(dossier / "musique.wav", opts.duree + 15)
        musique = analyser_musique(chemin_musique, journal)

        journal("3/5 Plan de montage...")
        plan_global = planifier(clips, musique, opts, journal)
        plans = plan_global["plans"]
        for p in plans:
            if p.clip:
                journal(f"  {p.debut:6.2f}s  {p.duree:4.2f}s  {Path(p.clip.chemin).name} "
                        f"@ {p.source:.1f}s  {' '.join(p.effets)}")
            else:
                journal(f"  {p.debut:6.2f}s  {p.duree:4.2f}s  carte de fin")

        journal(f"4/5 Rendu des {len(plans)} plans...")
        plans[-1].image = _image_fond_fin(clips, opts, dossier)
        segments = []
        for i, p in enumerate(plans):
            # Positions en images exactes pour ne pas deriver par rapport aux temps de la musique
            n = round((p.debut + p.duree) * opts.fps) - round(p.debut * opts.fps)
            seg = dossier / f"plan_{i:03d}.mkv"
            rendre_plan(p, n, seg, opts)
            segments.append(seg)
            journal(f"  plan {i + 1}/{len(plans)}")

        journal("5/5 Textes, musique et export final...")
        calques = _calques(plan_global, opts, dossier)
        _assembler(segments, calques, plan_global, opts, chemin_musique, sortie, dossier)
        journal(f"Trailer pret : {sortie} ({plan_global['duree']:.1f} s)")

        if opts.miniatures:
            journal("Bonus : miniatures...")
            generer_miniatures([c.analyse for c in clips], sortie.parent, opts.titre or "",
                               opts.accent, opts.badge or None, opts.miniatures,
                               opts.image_fin or None, journal)
    finally:
        if garder_travail:
            journal(f"  fichiers de travail conserves dans {dossier}")
        else:
            shutil.rmtree(dossier, ignore_errors=True)
    return sortie
