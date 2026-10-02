"""Miniatures automatiques (1920x1080) a partir des meilleures images du gameplay."""

import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

from . import ffmpeg_outils as ff
from .analyse import FPS_ANALYSE
from .textes import _couvrir, _ombre, couleur_rgb, police

LARGEUR, HAUTEUR = 1920, 1080


def meilleures_images(clips, nombre=3, ecart=4.0):
    """Choisit des instants varies parmi les plus beaux : un par clip d'abord, puis le reste."""
    candidats = sorted(((float(c.beaute[i]), c, i / FPS_ANALYSE)
                        for c in clips for i in np.argsort(c.beaute)[::-1][:300]),
                       key=lambda x: -x[0])
    choisis = []
    for un_par_clip in (True, False):
        for _note, clip, t in candidats:
            if len(choisis) == nombre:
                return choisis
            if un_par_clip and any(clip is c for c, _ in choisis):
                continue
            if all(clip is not c or abs(t - u) > ecart for c, u in choisis):
                choisis.append((clip, t))
    return choisis


def _vignette(img, force=0.55):
    w, h = img.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2) / 1.41
    masque = np.clip(1 - force * np.clip(d - 0.35, 0, 1) ** 1.5 * 1.8, 0, 1)
    arr = np.asarray(img).astype(np.float32) * masque[..., None]
    return Image.fromarray(arr.astype(np.uint8))


def _rayons(w, h, centre, couleur, nb=18):
    """Eclat lumineux derriere le titre (rayons de soleil facon miniature Fortnite)."""
    calque = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(calque)
    r = max(w, h) * 1.2
    for k in range(nb):
        a0 = 2 * np.pi * k / nb
        a1 = a0 + np.pi / nb * 0.8
        d.polygon([centre,
                   (centre[0] + r * np.cos(a0), centre[1] + r * np.sin(a0)),
                   (centre[0] + r * np.cos(a1), centre[1] + r * np.sin(a1))],
                  fill=couleur + (55,))
    return calque.filter(ImageFilter.GaussianBlur(6))


def titre_miniature(texte, largeur_max, hauteur_max, accent):
    """Titre geant : blanc vers jaune, gros contour noir, ombre, leger angle."""
    mots = texte.upper().split()
    lignes = [texte.upper()]
    if len(mots) >= 3 or len(texte) > 14:
        coupe = min(range(1, len(mots)),
                    key=lambda i: abs(len(" ".join(mots[:i])) - len(" ".join(mots[i:]))))
        lignes = [" ".join(mots[:coupe]), " ".join(mots[coupe:])]
    taille = int(hauteur_max / len(lignes) * 1.05)
    while taille > 30:
        f = police(taille)
        larg = max(f.getbbox(l)[2] - f.getbbox(l)[0] for l in lignes)
        haut = sum(f.getbbox(l)[3] - f.getbbox(l)[1] for l in lignes) * 1.08
        if larg <= largeur_max and haut <= hauteur_max:
            break
        taille = int(taille * 0.94)
    f = police(taille)
    trait = max(4, int(taille * 0.09))
    blocs = []
    for ligne in lignes:
        x0, y0, x1, y1 = f.getbbox(ligne)
        w, h = x1 - x0 + 2 * trait, y1 - y0 + 2 * trait
        masque = Image.new("L", (w, h), 0)
        ImageDraw.Draw(masque).text((trait - x0, trait - y0), ligne, font=f, fill=255)
        contour = Image.new("L", (w, h), 0)
        ImageDraw.Draw(contour).text((trait - x0, trait - y0), ligne, font=f, fill=255,
                                     stroke_width=trait, stroke_fill=255)
        # Remplissage en degrade vertical : blanc en haut, couleur d'accent en bas
        haut_c, bas_c = np.array([255, 255, 255]), np.array(couleur_rgb(accent))
        k = np.linspace(0, 1, h)[:, None, None] ** 1.3
        degrade = (haut_c * (1 - k) + bas_c * k).repeat(w, axis=1).astype(np.uint8)
        bloc = Image.new("RGBA", (w, h), (15, 15, 15, 0))
        bloc.putalpha(contour)
        rempli = Image.fromarray(degrade, "RGB").convert("RGBA")
        rempli.putalpha(masque)
        bloc.alpha_composite(rempli)
        blocs.append(bloc)
    w = max(b.width for b in blocs)
    h = sum(int(b.height * 0.92) for b in blocs)
    img = Image.new("RGBA", (w, h + blocs[-1].height), (0, 0, 0, 0))
    y = 0
    for b in blocs:
        img.alpha_composite(b, ((w - b.width) // 2, y))
        y += int(b.height * 0.92)
    img = img.crop(img.getbbox())
    img = img.rotate(3, resample=Image.BICUBIC, expand=True)
    return _ombre(img, (int(taille * 0.06), int(taille * 0.08)), int(taille * 0.06), 200)


def badge(texte, hauteur, couleur="#E8262A"):
    f = police(int(hauteur * 0.075))
    x0, y0, x1, y1 = f.getbbox(texte.upper())
    pad = int(hauteur * 0.022)
    img = Image.new("RGBA", (x1 - x0 + 3 * pad, y1 - y0 + 2 * pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=pad,
                        fill=couleur_rgb(couleur), outline="white", width=max(3, pad // 3))
    d.text((1.5 * pad - x0, pad - y0), texte.upper(), font=f, fill="white")
    return _ombre(img.rotate(-8, resample=Image.BICUBIC, expand=True), (6, 8), 8)


def composer(fond, titre, accent="#FFD400", texte_badge=None, position="haut"):
    img = _couvrir(fond.convert("RGB"), LARGEUR, HAUTEUR)
    # Leger zoom pour un cadrage plus serre et plus "punchy"
    zoom = 1.08
    img = img.resize((int(LARGEUR * zoom), int(HAUTEUR * zoom)), Image.LANCZOS)
    x, y = (img.width - LARGEUR) // 2, (img.height - HAUTEUR) // 2
    img = img.crop((x, y, x + LARGEUR, y + HAUTEUR))
    img = ImageEnhance.Color(img).enhance(1.45)
    img = ImageEnhance.Contrast(img).enhance(1.12)
    img = ImageEnhance.Sharpness(img).enhance(1.6)
    img = _vignette(img).convert("RGBA")

    if titre:
        t = titre_miniature(titre, LARGEUR * 0.86, HAUTEUR * 0.40, accent)
        cy = int(HAUTEUR * (0.25 if position == "haut" else 0.75))
        img.alpha_composite(_rayons(LARGEUR, HAUTEUR, (LARGEUR // 2, cy), couleur_rgb(accent)))
        img.alpha_composite(t, ((LARGEUR - t.width) // 2, cy - t.height // 2))
    if texte_badge:
        b = badge(texte_badge, HAUTEUR)
        img.alpha_composite(b, (LARGEUR - b.width - 40, HAUTEUR - b.height - 40)
                            if position == "haut" else (LARGEUR - b.width - 40, 30))
    return img.convert("RGB")


def generer_miniatures(clips, dossier, titre, accent="#FFD400", texte_badge=None,
                       nombre=3, image_perso=None, journal=print):
    """Ecrit miniature_1.png, miniature_2.png... et renvoie la liste des chemins."""
    dossier = Path(dossier)
    dossier.mkdir(parents=True, exist_ok=True)
    fonds = []
    if image_perso:
        fonds.append(Image.open(image_perso))
    with tempfile.TemporaryDirectory() as tmp:
        for k, (clip, t) in enumerate(meilleures_images(clips, nombre)):
            chemin = Path(tmp) / f"img{k}.png"
            ff.extraire_image(clip.chemin, t, chemin)
            fonds.append(Image.open(chemin).copy())
    sorties = []
    for k, fond in enumerate(fonds[:max(nombre, 1)]):
        position = "haut" if k % 2 == 0 else "bas"
        img = composer(fond, titre, accent, texte_badge, position)
        chemin = dossier / f"miniature_{k + 1}.png"
        img.save(chemin)
        sorties.append(chemin)
        journal(f"  miniature : {chemin}")
    return sorties
