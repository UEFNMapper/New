"""Rendu des textes (bandeaux, titres, code de la map) en images PNG transparentes."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

POLICE = Path(__file__).resolve().parent.parent / "polices" / "Anton-Regular.ttf"


def police(taille):
    try:
        return ImageFont.truetype(str(POLICE), int(taille))
    except OSError:
        return ImageFont.load_default(int(taille))


def couleur_rgb(hexa):
    hexa = hexa.lstrip("#")
    return tuple(int(hexa[i:i + 2], 16) for i in (0, 2, 4))


def _ombre(img, decalage, flou, opacite=160):
    """Ajoute une ombre portee douce sous une image RGBA."""
    marge = flou * 3 + max(decalage)
    fond = Image.new("RGBA", (img.width + 2 * marge, img.height + 2 * marge), (0, 0, 0, 0))
    alpha = img.getchannel("A").point(lambda a: a * opacite // 255)
    ombre = Image.new("RGBA", img.size, (0, 0, 0, 255))
    ombre.putalpha(alpha)
    fond.paste(ombre, (marge + decalage[0], marge + decalage[1]), ombre)
    fond = fond.filter(ImageFilter.GaussianBlur(flou))
    fond.alpha_composite(img, (marge, marge))
    return fond


def bandeau(texte, hauteur_ecran, accent="#FFD400", encre="#111111", inclinaison=-1.5):
    """Bandeau facon trailers UEFN : boite jaune, texte noir condense en majuscules."""
    taille = int(hauteur_ecran * 0.052)
    f = police(taille)
    texte = texte.upper()
    x0, y0, x1, y1 = f.getbbox(texte)
    pad_x, pad_y = int(taille * 0.45), int(taille * 0.22)
    w, h = x1 - x0 + 2 * pad_x, y1 - y0 + 2 * pad_y
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=int(taille * 0.12), fill=couleur_rgb(accent))
    d.text((pad_x - x0, pad_y - y0), texte, font=f, fill=couleur_rgb(encre))
    img = img.rotate(-inclinaison, resample=Image.BICUBIC, expand=True)
    return _ombre(img, (int(taille * 0.08), int(taille * 0.1)), int(taille * 0.12))


def titre(texte, hauteur_ecran, largeur_max, style="contour", accent="#FFD400",
          encre="#111111", echelle=0.13):
    """Gros texte central. style = 'contour' (blanc cerne de noir) ou 'boite' (boite jaune)."""
    texte = texte.upper()
    taille = int(hauteur_ecran * echelle)
    f = police(taille)
    while f.getbbox(texte)[2] > largeur_max and taille > 20:
        taille = int(taille * 0.92)
        f = police(taille)
    x0, y0, x1, y1 = f.getbbox(texte)
    if style == "boite":
        pad_x, pad_y = int(taille * 0.4), int(taille * 0.18)
        w, h = x1 - x0 + 2 * pad_x, y1 - y0 + 2 * pad_y
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((0, 0, w - 1, h - 1), radius=int(taille * 0.1), fill=couleur_rgb(accent))
        d.text((pad_x - x0, pad_y - y0), texte, font=f, fill=couleur_rgb(encre))
        img = img.rotate(2, resample=Image.BICUBIC, expand=True)
    else:
        trait = max(3, int(taille * 0.07))
        w, h = x1 - x0 + 2 * trait, y1 - y0 + 2 * trait
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(img).text((trait - x0, trait - y0), texte, font=f, fill="white",
                                 stroke_width=trait, stroke_fill=(10, 10, 10))
    return _ombre(img, (int(taille * 0.05), int(taille * 0.07)), int(taille * 0.1))


def mentions(texte, largeur_ecran, hauteur_ecran):
    """Petite ligne de mentions legales, blanche semi-transparente."""
    f = police(max(12, int(hauteur_ecran * 0.016)))
    x0, y0, x1, y1 = f.getbbox(texte)
    img = Image.new("RGBA", (x1 - x0 + 8, y1 - y0 + 8), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((4 - x0, 4 - y0), texte, font=f, fill=(255, 255, 255, 170))
    if img.width > largeur_ecran * 0.9:
        r = largeur_ecran * 0.9 / img.width
        img = img.resize((int(img.width * r), max(1, int(img.height * r))), Image.LANCZOS)
    return _ombre(img, (1, 1), 2, 200)


def carte_fin(fond, largeur, hauteur, titre_map, code, accent="#FFD400", encre="#111111",
              appel="PLAY NOW"):
    """Image de fin : visuel + nom de la map + 'PLAY NOW' + code de l'ile."""
    img = fond.convert("RGB").copy()
    img = _couvrir(img, largeur, hauteur).convert("RGBA")
    # Degrade sombre en bas pour la lisibilite du code
    degrade = Image.new("L", (1, hauteur))
    for y in range(hauteur):
        degrade.putpixel((0, y), int(210 * max(0, (y / hauteur - 0.45) / 0.55) ** 1.4))
    noir = Image.new("RGBA", (largeur, hauteur), (0, 0, 0, 255))
    noir.putalpha(degrade.resize((largeur, hauteur)))
    img.alpha_composite(noir)

    vertical = hauteur > largeur
    bas = hauteur * (0.80 if vertical else 0.84)
    if code:
        code_img = titre(code, hauteur, largeur * 0.8, "contour", echelle=0.085 if vertical else 0.11)
        img.alpha_composite(code_img, ((largeur - code_img.width) // 2, int(bas - code_img.height / 2)))
        bas -= code_img.height * 0.62
    if appel:
        app = titre(appel, hauteur, largeur * 0.5, "boite", accent, encre, echelle=0.045)
        img.alpha_composite(app, ((largeur - app.width) // 2, int(bas - app.height / 2)))
        bas -= app.height * 0.8
    if titre_map:
        t = titre(titre_map, hauteur, largeur * 0.88, "contour", echelle=0.10 if vertical else 0.13)
        haut = hauteur * (0.12 if vertical else 0.06)
        img.alpha_composite(t, ((largeur - t.width) // 2, int(haut)))
    return img.convert("RGB")


def _couvrir(img, largeur, hauteur):
    """Redimensionne et recadre l'image pour remplir exactement largeur x hauteur."""
    r = max(largeur / img.width, hauteur / img.height)
    img = img.resize((max(largeur, round(img.width * r)), max(hauteur, round(img.height * r))),
                     Image.LANCZOS)
    x, y = (img.width - largeur) // 2, (img.height - hauteur) // 2
    return img.crop((x, y, x + largeur, y + hauteur))


# ------------------------------------------------- sprites pour le compositeur

def vers_bgra(img):
    """Image Pillow -> tableau BGRA pour OpenCV."""
    import numpy as np
    arr = np.asarray(img.convert("RGBA"))
    return np.ascontiguousarray(arr[..., [2, 1, 0, 3]])


def bandeau_morceaux(texte, hauteur_ecran, accent="#FFD400", encre="#111111"):
    """Fond et texte d'un bandeau, separes pour l'animation (la boite s'ouvre, le texte glisse)."""
    taille = int(hauteur_ecran * 0.056)
    f = police(taille)
    texte = texte.upper()
    x0, y0, x1, y1 = f.getbbox(texte)
    pad_x, pad_y = int(taille * 0.5), int(taille * 0.24)
    w, h = x1 - x0 + 2 * pad_x, y1 - y0 + 2 * pad_y
    ombre = max(4, int(taille * 0.1))
    boite = Image.new("RGBA", (w + ombre, h + ombre), (0, 0, 0, 0))
    d = ImageDraw.Draw(boite)
    rayon = int(taille * 0.12)
    d.rounded_rectangle((ombre, ombre, w + ombre - 1, h + ombre - 1), radius=rayon, fill=(0, 0, 0, 150))
    r, g, b = couleur_rgb(accent)
    # Liseré plus sombre en bas pour donner du relief
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=rayon,
                        fill=(int(r * 0.72), int(g * 0.72), int(b * 0.72), 255))
    d.rounded_rectangle((0, 0, w - 1, h - 1 - max(3, h // 10)), radius=rayon, fill=(r, g, b, 255))
    txt = Image.new("RGBA", (x1 - x0 + 4, y1 - y0 + 4), (0, 0, 0, 0))
    ImageDraw.Draw(txt).text((2 - x0, 2 - y0), texte, font=f, fill=couleur_rgb(encre))
    return boite, txt
