"""Bruitages de trailer generes par calcul (whoosh, impact, montee, swish) et mixage audio."""

import subprocess
import sys
import wave

import numpy as np

SR = 48000
_FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0) if sys.platform == "win32" else 0


def _passe_bande(signal, centre, q=1.2):
    """Filtre passe-bande a variable d'etat ; centre en Hz (tableau = balayage)."""
    centre = np.broadcast_to(np.asarray(centre, np.float64), signal.shape)
    f = 2 * np.sin(np.pi * np.clip(centre, 20, SR / 6) / SR)
    amort = 1.0 / q
    bas = bande = 0.0
    sortie = np.empty_like(signal)
    for i in range(signal.size):
        haut = signal[i] - bas - amort * bande
        bande += f[i] * haut
        bas += f[i] * bande
        sortie[i] = bande
    return sortie


def _stereo(mono, pan=None):
    """pan : -1 (gauche) .. 1 (droite), scalaire ou tableau (balayage)."""
    if pan is None:
        return np.stack([mono, mono], axis=1)
    pan = np.broadcast_to(np.asarray(pan, np.float64), mono.shape)
    angle = (pan + 1) * np.pi / 4
    return np.stack([mono * np.cos(angle), mono * np.sin(angle)], axis=1) * 1.41


def whoosh(duree=0.55, graine=0):
    """Souffle qui monte puis retombe ; le pic tombe a 75 % de la duree."""
    rng = np.random.default_rng(graine)
    n = int(duree * SR)
    t = np.linspace(0, 1, n)
    bruit = rng.standard_normal(n)
    pic = 0.75
    centre = np.where(t < pic, 250 + 3200 * (t / pic) ** 2, 3450 - 2600 * ((t - pic) / (1 - pic)))
    son = _passe_bande(bruit, centre, q=1.6)
    env = np.where(t < pic, (t / pic) ** 2.2, np.exp(-((t - pic) / (1 - pic)) * 4))
    return _stereo(son * env * 0.9, pan=np.linspace(-0.7, 0.7, n))


def swish(duree=0.22, graine=1):
    """Petit souffle aigu pour l'apparition d'un bandeau."""
    rng = np.random.default_rng(graine)
    n = int(duree * SR)
    t = np.linspace(0, 1, n)
    son = _passe_bande(rng.standard_normal(n), 2500 + 4000 * t, q=2.2)
    env = np.sin(np.pi * t) ** 1.5
    return _stereo(son * env * 0.45, pan=np.linspace(-0.5, 0.2, n))


def impact(duree=1.4, graine=2):
    """Coup grave cinematographique : chute de frequence + claquement + queue."""
    rng = np.random.default_rng(graine)
    n = int(duree * SR)
    t = np.arange(n) / SR
    freq = 32 + 120 * np.exp(-t * 14)
    grave = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 3.2)
    claque = rng.standard_normal(n) * np.exp(-t * 55)
    claque = claque - _passe_bande(claque, 6000, q=0.7) * 0.3
    queue = _passe_bande(rng.standard_normal(n), 900, q=0.6) * np.exp(-t * 4.5) * 0.25
    son = np.tanh((grave * 1.3 + claque * 0.45 + queue) * 1.6) * 0.85
    return _stereo(son)


def montee(duree=2.0, graine=3):
    """Riser : bruit et ton qui montent jusqu'au drop, coupe net a la fin."""
    rng = np.random.default_rng(graine)
    n = int(duree * SR)
    t = np.linspace(0, 1, n)
    bruit = _passe_bande(rng.standard_normal(n), 400 + 7000 * t ** 2, q=0.9)
    ton = np.sin(2 * np.pi * np.cumsum(220 + 1400 * t ** 2.2) / SR)
    son = (bruit * 0.6 + ton * 0.25) * t ** 2.4
    son[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
    return _stereo(son * 0.7)


def pop(duree=0.16):
    """Petit 'pop' arrondi pour un titre qui rebondit."""
    n = int(duree * SR)
    t = np.arange(n) / SR
    freq = 260 + 700 * np.exp(-t * 40)
    son = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 28)
    return _stereo(son * 0.6)


BRUITAGES = {"whoosh": whoosh, "swish": swish, "impact": impact, "montee": montee, "pop": pop}


# ------------------------------------------------------------------ mixage

def lire_stereo(chemin, debut=0.0, duree=None, boucle=False):
    cmd = ["ffmpeg", "-v", "error"]
    if boucle:
        cmd += ["-stream_loop", "-1"]
    cmd += ["-ss", f"{max(0.0, debut):.3f}", "-i", str(chemin)]
    if duree:
        cmd += ["-t", f"{duree:.3f}"]
    cmd += ["-vn", "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, creationflags=_FLAGS)
    return np.frombuffer(proc.stdout, np.float32).reshape(-1, 2).astype(np.float64)


class Mixage:
    def __init__(self, duree):
        self.n = int(duree * SR) + SR
        self.duree = duree
        self.musique = np.zeros((self.n, 2))
        self.effets = np.zeros((self.n, 2))
        self.jeu = np.zeros((self.n, 2))
        self.ducking = np.ones(self.n)

    def _poser(self, piste, son, t, gain=1.0):
        i = int(round(t * SR))
        if i < 0:
            son, i = son[-i:], 0
        fin = min(self.n, i + len(son))
        if fin > i:
            piste[i:fin] += son[:fin - i] * gain

    def poser_musique(self, chemin, debut, fondu_fin=1.6):
        audio = lire_stereo(chemin, debut, self.duree + 1, boucle=True)
        m = min(len(audio), self.n)
        self.musique[:m] = audio[:m]
        fin = int(self.duree * SR)
        f = int(fondu_fin * SR)
        self.musique[fin - f:fin] *= np.linspace(1, 0, f)[:, None] ** 1.5
        self.musique[fin:] = 0
        self.musique[: int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))[:, None]

    def bruitage(self, nom, t, gain=1.0, ancre=0.0):
        """Pose un bruitage ; ancre = instant du son qui doit tomber sur t (0..1 de sa duree)."""
        son = BRUITAGES[nom]()
        self._poser(self.effets, son, t - ancre * len(son) / SR, gain)
        if nom == "impact":   # la musique s'efface un instant sous l'impact
            i = int(t * SR)
            env = 1 - 0.45 * np.exp(-np.arange(int(0.6 * SR)) / SR / 0.18)
            fin = min(self.n, i + env.size)
            self.ducking[i:fin] = np.minimum(self.ducking[i:fin], env[:fin - i])

    def poser_jeu(self, chemin, source, t, duree, gain):
        audio = lire_stereo(chemin, source, duree)
        if not len(audio):
            return
        f = min(len(audio) // 2, int(0.02 * SR))
        if f:
            audio[:f] *= np.linspace(0, 1, f)[:, None]
            audio[-f:] *= np.linspace(1, 0, f)[:, None]
        self._poser(self.jeu, audio, t, gain)

    def ecrire(self, chemin):
        total = self.musique * self.ducking[:, None] * 0.9 + self.effets * 0.55 + self.jeu
        total = total[: int(self.duree * SR)]
        crete = np.abs(total).max() or 1.0
        total = np.tanh(total / max(crete, 1.0) * 1.15) * 0.92
        with wave.open(str(chemin), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((np.clip(total, -1, 1) * 32767).astype("<i2").tobytes())
        return chemin
