"""Effets image par image (OpenCV) : courbes d'animation, zooms, flous, flashs, etalonnage."""

import math

import cv2
import numpy as np


# ------------------------------------------------------------------ courbes

def borne(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def sortie_cubique(t):
    t = borne(t)
    return 1 - (1 - t) ** 3


def entree_cubique(t):
    t = borne(t)
    return t ** 3


def entree_sortie(t):
    t = borne(t)
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def sortie_retour(t, s=1.9):
    """Depasse la cible puis revient (pop des textes) : 0 -> ~1.12 -> 1."""
    t = borne(t) - 1
    return 1 + (s + 1) * t ** 3 + s * t ** 2


def sortie_expo(t):
    t = borne(t)
    return 1 - 2 ** (-10 * t) if t < 1 else 1.0


# --------------------------------------------------------------- geometrie

def matrice(largeur, hauteur, zoom=1.0, dx=0.0, dy=0.0, angle=0.0, cx=None, cy=None):
    """Zoom + rotation autour de (cx, cy) puis translation, en une seule matrice affine."""
    cx = largeur / 2 if cx is None else cx
    cy = hauteur / 2 if cy is None else cy
    m = cv2.getRotationMatrix2D((cx, cy), angle, zoom)
    m[0, 2] += dx
    m[1, 2] += dy
    return m


def transformer(img, m):
    h, w = img.shape[:2]
    return cv2.warpAffine(img, m, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)


def flou_zoom(img, force, copies=7):
    """Flou radial facon transition zoom : moyenne de copies de plus en plus agrandies."""
    if force <= 0.004:
        return img
    h, w = img.shape[:2]
    acc = img.astype(np.float32)
    for i in range(1, copies):
        z = 1 + force * i / (copies - 1)
        acc += cv2.warpAffine(img, matrice(w, h, z), (w, h), flags=cv2.INTER_LINEAR,
                              borderMode=cv2.BORDER_REFLECT)
    return (acc / copies).astype(np.uint8)


def flou_direction(img, dx, dy=0.0):
    """Flou de bouge horizontal / vertical (whip pan)."""
    kx, ky = int(abs(dx)) | 1, int(abs(dy)) | 1
    if kx <= 1 and ky <= 1:
        return img
    return cv2.blur(img, (kx, ky))


def aberration(img, force):
    """Decalage des canaux rouge / bleu (aberration chromatique) en pixels."""
    if force < 0.6:
        return img
    h, w = img.shape[:2]
    b, g, r = cv2.split(img)
    z = force / w * 2
    r = cv2.warpAffine(r, matrice(w, h, 1 + z), (w, h), borderMode=cv2.BORDER_REFLECT)
    b = cv2.warpAffine(b, matrice(w, h, 1 - z), (w, h), borderMode=cv2.BORDER_REFLECT)
    return cv2.merge((b, g, r))


def flash(img, force):
    """Flash surexpose (pas un simple fondu au blanc : les hautes lumieres brulent d'abord)."""
    if force <= 0.01:
        return img
    surex = cv2.convertScaleAbs(img, alpha=1 + 1.8 * force, beta=90 * force)
    return cv2.addWeighted(surex, 1 - 0.75 * force, np.full_like(img, 255), 0.75 * force, 0)


def assombrir(img, force):
    if force <= 0.01:
        return img
    return cv2.convertScaleAbs(img, alpha=1 - force)


def fondu(a, b, t):
    return cv2.addWeighted(a, 1 - t, b, t, 0)


# ------------------------------------------------------------- etalonnage

class Etalonnage:
    """Contraste en S + saturation + vignette, precalcules pour une taille donnee."""

    def __init__(self, largeur, hauteur, saturation=1.22, contraste=0.16, vignette=0.32):
        x = np.arange(256) / 255.0
        courbe = x + contraste * np.sin(2 * np.pi * (x - 0.5)) / (2 * np.pi) * 2
        self.lut = np.clip(courbe * 255, 0, 255).astype(np.uint8)
        self.saturation = saturation
        yy, xx = np.mgrid[0:hauteur, 0:largeur].astype(np.float32)
        d = np.sqrt(((xx - largeur / 2) / (largeur / 2)) ** 2 + ((yy - hauteur / 2) / (hauteur / 2)) ** 2)
        masque = 1 - vignette * np.clip((d - 0.55) / 0.9, 0, 1) ** 1.6
        self.vignette = cv2.merge([(masque * 255).astype(np.uint8)] * 3)

    def appliquer(self, img):
        img = cv2.LUT(img, self.lut)
        gris = cv2.cvtColor(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), cv2.COLOR_GRAY2BGR)
        img = cv2.addWeighted(img, self.saturation, gris, 1 - self.saturation, 0)
        return cv2.multiply(img, self.vignette, scale=1 / 255)


# ------------------------------------------------------------ superposition

def coller(img, sprite, cx, cy, echelle=1.0, angle=0.0, opacite=1.0):
    """Colle un sprite RGBA (BGRA) centre en (cx, cy), avec echelle, rotation et opacite."""
    if opacite <= 0.01 or echelle <= 0.01:
        return img
    sh, sw = sprite.shape[:2]
    rad = math.radians(angle)
    bw = int(abs(sw * math.cos(rad)) * echelle + abs(sh * math.sin(rad)) * echelle) + 4
    bh = int(abs(sw * math.sin(rad)) * echelle + abs(sh * math.cos(rad)) * echelle) + 4
    m = cv2.getRotationMatrix2D((sw / 2, sh / 2), angle, echelle)
    m[0, 2] += bw / 2 - sw / 2
    m[1, 2] += bh / 2 - sh / 2
    calque = cv2.warpAffine(sprite, m, (bw, bh), flags=cv2.INTER_LINEAR,
                            borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
    x0, y0 = int(round(cx - bw / 2)), int(round(cy - bh / 2))
    H, W = img.shape[:2]
    ax0, ay0, ax1, ay1 = max(0, x0), max(0, y0), min(W, x0 + bw), min(H, y0 + bh)
    if ax0 >= ax1 or ay0 >= ay1:
        return img
    morceau = calque[ay0 - y0:ay1 - y0, ax0 - x0:ax1 - x0]
    alpha = morceau[..., 3:4].astype(np.float32) * (opacite / 255.0)
    zone = img[ay0:ay1, ax0:ax1].astype(np.float32)
    img[ay0:ay1, ax0:ax1] = (zone * (1 - alpha) + morceau[..., :3].astype(np.float32) * alpha).astype(np.uint8)
    return img


def lignes_vitesse(largeur, hauteur, graine, nombre=110, couleur=(255, 255, 255)):
    """Lignes de vitesse facon manga qui convergent vers le centre (sprite BGRA)."""
    rng = np.random.default_rng(graine)
    calque = np.zeros((hauteur, largeur, 4), np.uint8)
    cx, cy = largeur / 2, hauteur / 2
    rayon = math.hypot(cx, cy) * 1.05
    for _ in range(nombre):
        a = rng.uniform(0, 2 * math.pi)
        interieur = rng.uniform(0.42, 0.75)
        epaisseur = rng.uniform(0.004, 0.018)
        da = epaisseur
        pts = np.array([
            (cx + rayon * math.cos(a - da), cy + rayon * math.sin(a - da) * 0.9),
            (cx + rayon * math.cos(a + da), cy + rayon * math.sin(a + da) * 0.9),
            (cx + rayon * interieur * math.cos(a), cy + rayon * interieur * math.sin(a) * 0.62),
        ], np.int32)
        cv2.fillConvexPoly(calque, pts, (*couleur, int(rng.uniform(120, 230))), cv2.LINE_AA)
    return calque


def bandes_cinema(img, ratio_ouvert):
    """Bandes noires 2.35:1 ; ratio_ouvert = 0 (bandes pleines) .. 1 (disparues)."""
    h, w = img.shape[:2]
    if w < h:
        return img
    bande = int((h - w / 2.35) / 2 * (1 - ratio_ouvert))
    if bande > 0:
        img[:bande] = 0
        img[h - bande:] = 0
    return img


def secousse(t, amplitude, graine=0, duree=0.35):
    """Decalage (dx, dy, angle) d'une secousse amortie, t en secondes depuis l'impact."""
    if t < 0 or t > duree:
        return 0.0, 0.0, 0.0
    amorti = math.exp(-t / (duree / 3.2))
    f = 38.0
    dx = amplitude * amorti * math.sin(t * f * 2.1 + graine)
    dy = amplitude * amorti * math.cos(t * f * 1.7 + graine * 1.3) * 0.8
    return dx, dy, amorti * amplitude * 0.03 * math.sin(t * f + graine)
