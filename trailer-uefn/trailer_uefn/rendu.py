"""Compositeur image par image : lecture des clips (avec rampes de vitesse), transitions,
mouvements de camera, textes animes, puis encodage par ffmpeg."""

import math
import subprocess
import sys
from dataclasses import dataclass, field

import cv2
import numpy as np

from . import effets as fx

_FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0) if sys.platform == "win32" else 0


# --------------------------------------------------------------- modele

@dataclass(eq=False)
class Plan:
    debut: float
    duree: float
    clip: object = None            # Clip (None pour une image fixe)
    source: float = 0.0
    vitesse: str = "constante"     # constante | rampe | ralenti
    entree: str = "coupe"          # coupe | zoom | glisse | flash | fondu
    sortie: str = "coupe"          # coupe | zoom | glisse | flash
    camera: str = "derive"         # derive | poussee | recul | fixe
    secousse: float = 0.0          # amplitude d'une secousse au debut du plan
    assombrir: float = 0.0
    flou: float = 0.0
    bandes: bool = False           # bandes cinema (ouverture)
    image: str = None
    lignes: bool = False           # lignes de vitesse par-dessus

    def temps_source(self, u):
        """Position dans la source (s) pour un instant u (s) du plan."""
        if self.vitesse == "ralenti":
            return 0.5 * u
        if self.vitesse == "rampe":
            # Demarre en accelere (~2.8x), se pose a 1x, re-accelere juste avant de sortir
            debut = u + 1.8 * 0.2 * (1 - math.exp(-u / 0.2))
            fin = 1.4 * 0.14 * (math.exp(-max(0.0, self.duree - u) / 0.14) - math.exp(-self.duree / 0.14))
            return debut + fin
        return u


@dataclass
class Texte:
    debut: float
    fin: float
    genre: str                     # bandeau | titre | appel | accroche | final | mentions | logo
    sprite: np.ndarray = None      # BGRA
    sprite_2: np.ndarray = None    # texte du bandeau (le fond est dans sprite)
    x: float = 0.0
    y: float = 0.0
    angle: float = 0.0


@dataclass
class Montage:
    largeur: int
    hauteur: int
    fps: int
    duree: float
    plans: list
    textes: list = field(default_factory=list)
    flashs: list = field(default_factory=list)       # (instant, force)
    secousses: list = field(default_factory=list)    # (instant, amplitude)
    lignes: list = field(default_factory=list)       # (debut, fin)
    periode: float = 0.5                             # duree d'un temps (pulsation des textes)
    intensite: float = 1.0


# -------------------------------------------------------------- lecture

class Lecteur:
    """Decode un passage d'un clip en flux et fournit l'image a un instant source donne.

    Les instants demandes doivent croitre. Quand on avance vite (rampe), les images
    sautees sont moyennees : c'est un vrai flou de mouvement.
    """

    def __init__(self, chemin, debut, duree, largeur, hauteur, fps_source):
        self.fps = min(60.0, max(10.0, fps_source))
        self.taille = largeur * hauteur * 3
        self.forme = (hauteur, largeur, 3)
        filtre = _cadrage(largeur, hauteur, self.fps)
        cmd = ["ffmpeg", "-v", "error", "-ss", f"{max(0.0, debut):.3f}", "-t", f"{duree + 0.6:.3f}",
               "-i", str(chemin), "-an", "-vf", filtre, "-f", "rawvideo", "-pix_fmt", "bgr24", "-"]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     creationflags=_FLAGS, bufsize=self.taille * 4)
        self.index = -1
        self.courante = None
        self.suivante = self._lire()
        self.fini = False

    def _lire(self):
        brut = self.proc.stdout.read(self.taille)
        if len(brut) < self.taille:
            return None
        return np.frombuffer(brut, np.uint8).reshape(self.forme)

    def _avancer(self):
        if self.suivante is None:
            self.fini = True
            return False
        self.courante = self.suivante
        self.index += 1
        self.suivante = self._lire()
        return True

    def image(self, s):
        cible = s * self.fps
        sautees = []
        while self.index < 0 or (self.index + 1 <= cible and not self.fini):
            if not self._avancer():
                break
            if self.index <= cible:
                sautees.append(self.courante)
        if len(sautees) > 2:          # avance rapide : flou de mouvement
            pas = max(1, len(sautees) // 5)
            choix = sautees[::-1][::pas][:5]
            acc = np.zeros(self.forme, np.float32)
            for img in choix:
                acc += img
            return (acc / len(choix)).astype(np.uint8)
        if self.courante is None:     # clip illisible ou vide : image noire plutot qu'un plantage
            return np.zeros(self.forme, np.uint8)
        frac = cible - self.index
        if self.suivante is not None and 0.2 < frac < 0.98:   # ralenti : melange des voisines
            return fx.fondu(self.courante, self.suivante, frac)
        return self.courante.copy()

    def fermer(self):
        try:
            self.proc.stdout.close()
            self.proc.kill()
            self.proc.wait(timeout=2)
        except Exception:
            pass


def _cadrage(largeur, hauteur, fps):
    if hauteur > largeur:   # vertical : gameplay au centre sur fond flou
        h_jeu = int(hauteur * 0.56) // 2 * 2
        pl, ph = largeur // 8, hauteur // 8
        return (f"fps={fps},split[f][b];[b]scale={pl}:{ph}:force_original_aspect_ratio=increase,"
                f"crop={pl}:{ph},boxblur=6:2,scale={largeur}:{hauteur},eq=brightness=-0.15[fond];"
                f"[f]scale=-2:{h_jeu},crop='min(iw,{largeur})':{h_jeu}[jeu];"
                f"[fond][jeu]overlay=(W-w)/2:(H-h)/2")
    return (f"fps={fps},scale={largeur}:{hauteur}:force_original_aspect_ratio=increase,"
            f"crop={largeur}:{hauteur}")


class ImageFixe:
    def __init__(self, chemin, largeur, hauteur):
        img = cv2.imread(str(chemin), cv2.IMREAD_COLOR)
        self.img = cv2.resize(img, (largeur, hauteur), interpolation=cv2.INTER_AREA)

    def image(self, _s):
        return self.img.copy()

    def fermer(self):
        pass


# ---------------------------------------------------------------- rendu

class Compositeur:
    def __init__(self, montage, sortie_video, journal=print, progression=None):
        self.m = montage
        self.sortie = sortie_video
        self.journal = journal
        self.progression = progression
        self.etal = fx.Etalonnage(montage.largeur, montage.hauteur)
        self.lignes = [fx.lignes_vitesse(montage.largeur, montage.hauteur, g) for g in range(4)]
        self.lecteurs = {}

    # Lecteurs ouverts a la demande, fermes des qu'ils ne servent plus
    def _lecteur(self, plan):
        if id(plan) not in self.lecteurs:
            if plan.image:
                self.lecteurs[id(plan)] = ImageFixe(plan.image, self.m.largeur, self.m.hauteur)
            else:
                info = plan.clip.analyse.infos
                besoin = plan.temps_source(plan.duree + 0.4) + 0.2
                self.lecteurs[id(plan)] = Lecteur(plan.clip.chemin, plan.source, besoin,
                                                  self.m.largeur, self.m.hauteur, info["fps"])
        return self.lecteurs[id(plan)]

    def _liberer(self, garder):
        for cle in list(self.lecteurs):
            if cle not in garder:
                self.lecteurs.pop(cle).fermer()

    def _image_plan(self, plan, t):
        u = t - plan.debut
        img = self._lecteur(plan).image(max(0.0, plan.temps_source(u)))
        return self.etal.appliquer(img) if not plan.image else img

    def rendre(self):
        m = self.m
        W, H, fps = m.largeur, m.hauteur, m.fps
        k = m.intensite
        nb_images = int(round(m.duree * fps))
        enc = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{W}x{H}",
             "-r", str(fps), "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "17",
             "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(self.sortie)],
            stdin=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=_FLAGS)
        plans = m.plans
        ip = 0
        try:
            for f in range(nb_images):
                t = f / fps
                while ip + 1 < len(plans) and t >= plans[ip + 1].debut - 1e-6:
                    ip += 1
                p = plans[ip]
                prec = plans[ip - 1] if ip > 0 else None
                u, d = t - p.debut, p.duree
                img = self._image_plan(p, t)

                # --- camera de base
                zoom, dx, dy, angle = 1.0, 0.0, 0.0, 0.0
                avance = fx.borne(u / max(d, 1e-3))
                if p.camera == "derive":
                    zoom *= 1.0 + 0.045 * avance
                    dx += W * 0.012 * (avance - 0.5)
                elif p.camera == "poussee":
                    zoom *= 1.0 + 0.10 * fx.entree_sortie(avance)
                elif p.camera == "recul":
                    zoom *= 1.09 - 0.08 * fx.sortie_cubique(avance)

                flou_z = flou_d = aberr = 0.0
                eclair = 0.0
                # --- transition d'entree
                T = 0.14
                if p.entree == "coupe":
                    zoom *= 1 + 0.075 * k * (1 - fx.sortie_cubique(u / 0.2))
                elif p.entree == "zoom" and u < T:
                    r = 1 - fx.sortie_cubique(u / T)
                    zoom *= 1 + 0.38 * k * r
                    flou_z = max(flou_z, 0.22 * k * r)
                    aberr = max(aberr, 9 * k * r)
                elif p.entree == "glisse" and u < T:
                    r = 1 - fx.sortie_cubique(u / T)
                    dx += W * 0.6 * r
                    flou_d = max(flou_d, W * 0.09 * r * k)
                elif p.entree == "flash":
                    eclair = max(eclair, (1 - fx.borne(u / 0.22)) ** 2)
                # --- transition de sortie (fin du plan)
                reste = d - u
                if p.sortie == "zoom" and reste < T:
                    r = fx.entree_cubique(1 - reste / T)
                    zoom *= 1 + 0.45 * k * r
                    flou_z = max(flou_z, 0.25 * k * r)
                    aberr = max(aberr, 10 * k * r)
                elif p.sortie == "glisse" and reste < T:
                    r = fx.entree_cubique(1 - reste / T)
                    dx -= W * 0.6 * r
                    flou_d = max(flou_d, W * 0.09 * r * k)
                elif p.sortie == "flash" and reste < 0.07:
                    eclair = max(eclair, 0.6 * (1 - reste / 0.07))

                # --- secousses (impacts, plans nerveux)
                for (te, amp) in m.secousses + ([(p.debut, p.secousse)] if p.secousse else []):
                    sx, sy, sa = fx.secousse(t - te, amp * k, graine=int(te * 7))
                    dx, dy, angle = dx + sx, dy + sy, angle + sa
                if abs(dx) + abs(dy) > 0.5 or abs(angle) > 0.01:
                    zoom *= 1.04        # marge pour ne pas voir les bords pendant la secousse

                if abs(zoom - 1) > 1e-3 or abs(dx) + abs(dy) > 0.5 or abs(angle) > 0.01:
                    img = fx.transformer(img, fx.matrice(W, H, zoom, dx, dy, angle))
                img = fx.flou_zoom(img, flou_z)
                img = fx.flou_direction(img, flou_d)
                img = fx.aberration(img, aberr)

                # --- fondu avec le plan precedent
                if p.entree == "fondu" and prec is not None and u < 0.2:
                    img = fx.fondu(self._image_plan(prec, t), img, fx.entree_sortie(u / 0.2))

                if p.flou > 0:
                    petit = cv2.resize(img, (W // 8, H // 8), interpolation=cv2.INTER_AREA)
                    img = cv2.resize(cv2.GaussianBlur(petit, (0, 0), 2.2), (W, H))
                if p.assombrir:
                    img = fx.assombrir(img, p.assombrir * fx.sortie_cubique(u / 0.15))
                if p.bandes:
                    img = fx.bandes_cinema(img, 0.0)

                # --- lignes de vitesse
                for (a, b) in m.lignes:
                    if a <= t < b:
                        op = fx.sortie_cubique((t - a) / 0.12) * (1 - fx.entree_cubique((t - (b - 0.1)) / 0.1))
                        calque = self.lignes[(f // 2) % len(self.lignes)]
                        fx.coller(img, calque, W / 2, H / 2, 1.0, 0.0, 0.75 * op)

                # --- textes
                for txt in m.textes:
                    if txt.debut <= t < txt.fin:
                        self._texte(img, txt, t)

                # --- flashs
                for (te, force) in m.flashs:
                    if 0 <= t - te < 0.3:
                        eclair = max(eclair, force * (1 - (t - te) / 0.3) ** 2)
                img = fx.flash(img, min(1.0, eclair * min(1.0, k)))

                enc.stdin.write(np.ascontiguousarray(img).tobytes())
                garder = {id(p)}
                if ip + 1 < len(plans) and plans[ip + 1].entree == "fondu" and plans[ip + 1].debut - t < 0.05:
                    garder.add(id(plans[ip + 1]))
                if p.entree == "fondu" and prec is not None and u < 0.2:
                    garder.add(id(prec))
                self._liberer(garder)
                if self.progression and f % 15 == 0:
                    self.progression(f / nb_images)
        finally:
            self._liberer(set())
            enc.stdin.close()
            erreur = enc.stderr.read().decode("utf-8", "replace")
            enc.wait()
        if enc.returncode != 0:
            raise RuntimeError("Encodage video impossible :\n" + erreur[-800:])

    # ------------------------------------------------------------- textes
    def _texte(self, img, txt, t):
        tau, reste = t - txt.debut, txt.fin - t
        W, H = self.m.largeur, self.m.hauteur
        g = txt.genre
        if g == "bandeau":
            boite, texte = txt.sprite, txt.sprite_2
            ouverture = fx.sortie_cubique(tau / 0.2) * (1 - fx.entree_cubique((0.2 - reste) / 0.2))
            glisse = fx.sortie_cubique((tau - 0.05) / 0.24)
            bh, bw = boite.shape[:2]
            toile = np.zeros_like(boite)
            larg = int(bw * ouverture)
            if larg <= 2:
                return
            toile[:, :larg] = boite[:, :larg]
            th, tw = texte.shape[:2]
            tx = int((bw - tw) / 2 - (1 - glisse) * (tw + bw * 0.3))
            ty = (bh - th) // 2
            x0, x1 = max(0, tx), min(larg, tx + tw)
            if x1 > x0:
                morceau = texte[:, x0 - tx:x1 - tx]
                zone = toile[ty:ty + th, x0:x1].astype(np.float32)
                a = morceau[..., 3:4].astype(np.float32) / 255
                zone[..., :3] = zone[..., :3] * (1 - a) + morceau[..., :3] * a
                toile[ty:ty + th, x0:x1] = zone.astype(np.uint8)
            fx.coller(img, toile, txt.x + bw / 2, txt.y, 1.0, txt.angle)
        elif g in ("titre", "final", "fin_titre"):
            if g == "fin_titre":
                e = 1.0 + 0.6 * (1 - fx.sortie_cubique(tau / 0.32))
            else:
                e = 0.2 + 0.8 * fx.sortie_retour(tau / 0.3)
            sortie = fx.entree_cubique(fx.borne((0.16 - reste) / 0.16))
            e *= 1 + 0.35 * sortie
            op = fx.borne(tau / 0.06) * (1 - sortie)
            sx, sy, _ = fx.secousse(tau - 0.12, 10 * self.m.intensite, graine=3)
            fx.coller(img, txt.sprite, txt.x + sx, txt.y + sy, e, txt.angle, op)
        elif g in ("appel", "fin_appel"):
            e = fx.sortie_retour(tau / 0.26)
            battement = (t % self.m.periode) / self.m.periode
            e *= 1 + 0.045 * (1 - fx.sortie_cubique(battement / 0.5))
            angle = txt.angle - 6 * (1 - fx.sortie_cubique(tau / 0.3))
            fx.coller(img, txt.sprite, txt.x, txt.y, e, angle, fx.borne(tau / 0.05))
        elif g == "fin_code":
            r = fx.sortie_retour(tau / 0.3)
            fx.coller(img, txt.sprite, txt.x, txt.y + (1 - r) * H * 0.08, 0.85 + 0.15 * r, txt.angle,
                      fx.borne(tau / 0.08))
        elif g == "accroche":
            r = fx.sortie_cubique(tau / 0.35)
            op = r * (1 - fx.entree_cubique(fx.borne((0.2 - reste) / 0.2)))
            fx.coller(img, txt.sprite, txt.x, txt.y, 1.12 - 0.12 * r, txt.angle, op)
        else:   # mentions, logo : simple fondu
            op = fx.borne(tau / 0.3) * fx.borne(reste / 0.25)
            fx.coller(img, txt.sprite, txt.x, txt.y, 1.0, 0.0, op)
