"""Musique de secours generee par le programme (libre de droits, puisqu'elle est calculee).

Ce n'est pas du niveau d'un vrai morceau : elle sert a obtenir un trailer complet sans
fichier audio. Pour un rendu pro, fournis une musique libre de droits (voir README).
"""

import wave

import numpy as np

SR = 44100


def _note(freq):
    return 440.0 * 2 ** ((freq - 69) / 12)


def _passe_bas(signal, coupure):
    """Filtre passe-bas a un pole ; coupure en Hz (scalaire ou tableau)."""
    a = np.exp(-2 * np.pi * np.asarray(coupure, dtype=np.float64) / SR) * np.ones_like(signal)
    sortie = np.empty_like(signal)
    y = 0.0
    for i in range(signal.size):
        y = a[i] * y + (1 - a[i]) * signal[i]
        sortie[i] = y
    return sortie


def _scie(freq, duree, desaccord=0.0):
    t = np.arange(int(duree * SR)) / SR
    s = 2 * ((t * freq) % 1) - 1
    if desaccord:
        s = 0.5 * s + 0.5 * (2 * ((t * freq * (1 + desaccord)) % 1) - 1)
    return s


def _kick():
    t = np.arange(int(0.4 * SR)) / SR
    freq = 45 + 110 * np.exp(-t * 28)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t * 7) + 0.3 * np.exp(-t * 300) * np.random.randn(t.size) * 0.3


def _clap(rng):
    t = np.arange(int(0.25 * SR)) / SR
    bruit = rng.standard_normal(t.size)
    env = np.exp(-t * 18)
    for decal in (0.0, 0.011, 0.022):
        env += 0.6 * np.exp(-np.maximum(t - decal, 0) * 120) * (t >= decal)
    bruit = bruit - _passe_bas(bruit, 900)
    return bruit * env * 0.5


def _hat(rng, ouvert=False):
    t = np.arange(int((0.18 if ouvert else 0.05) * SR)) / SR
    bruit = np.diff(rng.standard_normal(t.size + 1))
    return bruit * np.exp(-t * (18 if ouvert else 90)) * 0.18


def generer(chemin, duree_min=40.0, bpm=128):
    rng = np.random.default_rng(7)
    temps = 60 / bpm
    mesure = 4 * temps
    intro = 4
    nb_mesures = intro + int(np.ceil((duree_min - intro * mesure) / mesure)) + 2
    n = int(nb_mesures * mesure * SR) + SR
    batterie, basse, nappe, melodie = (np.zeros(n) for _ in range(4))
    accords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]   # Am F C G

    def poser(piste, son, t, gain=1.0):
        i = int(t * SR)
        fin = min(n, i + son.size)
        piste[i:fin] += son[: fin - i] * gain

    kick, clap = _kick(), _clap(rng)
    ducking = np.ones(n)
    for m in range(nb_mesures):
        t0 = m * mesure
        racine, tierce, quinte = accords[m % 4]
        drop = m >= intro
        # Nappe d'accords (filtree pendant l'intro, plus ouverte ensuite)
        nap = sum(_scie(_note(x), mesure, 0.004) for x in (racine, tierce, quinte, racine + 12))
        poser(nappe, nap, t0, 0.07 if drop else 0.1)
        for b in range(4):
            tb = t0 + b * temps
            if drop:
                poser(batterie, kick, tb, 0.9)
                i = int(tb * SR)
                env = 1 - 0.75 * np.exp(-np.arange(int(temps * SR)) / SR * 9)
                ducking[i:i + env.size] = np.minimum(ducking[i:i + env.size], env[: n - i])
                if b in (1, 3):
                    poser(batterie, clap, tb, 0.8)
                poser(batterie, _hat(rng, ouvert=True), tb + temps / 2, 0.8)
                # Basse en croches decalees
                for c in (0.5, 1.5) if b % 2 == 0 else (0.5,):
                    son = _scie(_note(racine - 24), temps / 2 * 0.9)
                    son *= np.exp(-np.arange(son.size) / SR * 6)
                    poser(basse, son, tb + c * temps / 2, 0.5)
                # Arpege en doubles croches
                for d in range(4):
                    note = (racine, tierce, quinte, racine + 12)[(b * 4 + d) % 4] + 12
                    son = np.sign(np.sin(2 * np.pi * _note(note) * np.arange(int(temps / 4 * SR)) / SR))
                    son *= np.exp(-np.arange(son.size) / SR * 14)
                    poser(melodie, son, tb + d * temps / 4, 0.06)
            else:
                poser(batterie, _hat(rng), tb + temps / 2, 0.6 + 0.1 * m)
                if m == intro - 1:
                    for d in range(4):
                        poser(batterie, clap, tb + d * temps / 4, 0.15 + 0.12 * b)

    # Montee (riser) sur la derniere mesure de l'intro
    r0 = (intro - 1) * mesure
    t = np.arange(int(mesure * SR)) / SR
    riser = rng.standard_normal(t.size) * (t / mesure) ** 2 * 0.25
    riser += 0.15 * np.sin(2 * np.pi * np.cumsum(300 + 1500 * (t / mesure) ** 2) / SR) * (t / mesure)
    poser(nappe, riser - _passe_bas(riser, 400 + 6000 * t / mesure), r0)

    coupure = np.where(np.arange(n) < intro * mesure * SR,
                       400 + 1600 * np.arange(n) / (intro * mesure * SR), 2500)
    nappe = _passe_bas(nappe, coupure) * ducking
    basse = _passe_bas(basse, 700) * ducking
    gauche = batterie + basse + nappe + melodie
    retard = int(0.012 * SR)
    droite = batterie + basse + nappe + np.concatenate([np.zeros(retard), melodie[:-retard]])
    stereo = np.tanh(np.stack([gauche, droite], axis=1) * 1.3)
    stereo /= np.abs(stereo).max() / 0.89
    fin = int((nb_mesures * mesure) * SR)
    stereo = stereo[:fin]
    stereo[-SR:] *= np.linspace(1, 0, SR)[:, None]
    with wave.open(str(chemin), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((stereo * 32767).astype("<i2").tobytes())
    return chemin
