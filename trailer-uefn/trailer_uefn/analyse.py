"""Analyse automatique : moments forts du gameplay et rythme de la musique."""

from dataclasses import dataclass, field

import numpy as np

from . import ffmpeg_outils as ff

FPS_ANALYSE = 6          # images analysees par seconde de gameplay
TAILLE_ANALYSE = (160, 90)


# --------------------------------------------------------------------- video

@dataclass(eq=False)
class AnalyseClip:
    chemin: str
    infos: dict
    temps: np.ndarray            # instant de chaque echantillon (s)
    mouvement: np.ndarray        # 0..1, quantite d'action a l'ecran
    couleur: np.ndarray          # 0..1, image vive et coloree
    nettete: np.ndarray          # 0..1, image nette (pas de flou de mouvement)
    luminosite: np.ndarray       # 0..1
    son: np.ndarray              # 0..1, volume du jeu (explosions, tirs...)
    coupes: np.ndarray           # bool, changement de plan dans la source
    score: np.ndarray = field(default=None)       # interet pour une coupe du trailer
    beaute: np.ndarray = field(default=None)      # interet pour l'ouverture / la miniature


def analyser_clip(chemin, journal=print):
    infos = ff.sonder(chemin)
    w, h = TAILLE_ANALYSE
    mouv, coul, net, lum, diffs = [], [], [], [], []
    precedent = None
    for img in ff.iterer_images(chemin, FPS_ANALYSE, w, h):
        rgb = img.astype(np.float32)
        gris = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
        lum.append(gris.mean() / 255.0)
        # Indice de couleur de Hasler & Susstrunk
        rg = rgb[..., 0] - rgb[..., 1]
        yb = 0.5 * (rgb[..., 0] + rgb[..., 1]) - rgb[..., 2]
        coul.append((np.hypot(rg.std(), yb.std()) + 0.3 * np.hypot(rg.mean(), yb.mean())) / 255.0)
        # Nettete : energie du laplacien
        lap = (4 * gris[1:-1, 1:-1] - gris[:-2, 1:-1] - gris[2:, 1:-1]
               - gris[1:-1, :-2] - gris[1:-1, 2:])
        net.append(lap.var())
        if precedent is None:
            mouv.append(0.0)
            diffs.append(0.0)
        else:
            d = np.abs(gris - precedent)
            mouv.append(float(np.median(d)) + 0.5 * float(d.mean()))
            diffs.append(float(d.mean()))
        precedent = gris
    n = len(lum)
    if n < 3:
        raise ff.ErreurFFmpeg(f"{chemin} : video trop courte ou illisible")
    temps = np.arange(n) / FPS_ANALYSE

    # Changement de plan : la difference d'image explose par rapport a son voisinage
    diffs = np.array(diffs)
    voisinage = np.convolve(diffs, np.ones(9) / 9, mode="same") + 1e-3
    coupes = (diffs > 28) & (diffs > 3.0 * voisinage)

    son = np.zeros(n)
    if infos["audio"]:
        audio = ff.lire_audio(chemin, 8000)
        if audio.size:
            pas = 8000 // FPS_ANALYSE
            m = min(n, audio.size // pas)
            if m:
                blocs = audio[: m * pas].reshape(m, pas)
                son[:m] = np.sqrt((blocs ** 2).mean(axis=1))

    journal(f"  analyse : {chemin} ({infos['duree']:.1f} s)")
    return AnalyseClip(chemin, infos, temps, np.array(mouv), np.array(coul), np.array(net),
                       np.array(lum), son, coupes)


def _normaliser(valeurs):
    """Ramene chaque mesure dans [0, 1] sur l'ensemble des clips (percentiles robustes)."""
    tout = np.concatenate(valeurs)
    bas, haut = np.percentile(tout, 5), np.percentile(tout, 95)
    ecart = max(haut - bas, 1e-6)
    return [np.clip((v - bas) / ecart, 0, 1) for v in valeurs]


def noter_clips(clips):
    """Calcule les scores en comparant les clips entre eux."""
    for nom in ("mouvement", "couleur", "nettete", "son"):
        for clip, v in zip(clips, _normaliser([getattr(c, nom) for c in clips])):
            setattr(clip, nom, v)
    for c in clips:
        lissage = np.ones(3) / 3
        mouv = np.convolve(c.mouvement, lissage, mode="same")
        son = np.convolve(c.son, np.ones(5) / 5, mode="same")
        # Ecrans noirs, chargements, menus vides : on les evite.
        sombre = np.clip((c.luminosite - 0.06) / 0.10, 0, 1)
        fige = np.clip(mouv / 0.08, 0.25, 1)
        c.score = (0.45 * mouv + 0.30 * c.couleur + 0.25 * son) * sombre * fige
        # Plan d'ouverture / miniature : beau, net, de l'action moderee.
        moderation = 1 - np.abs(mouv - 0.45)
        c.beaute = (0.45 * c.couleur + 0.30 * c.nettete + 0.25 * moderation) * sombre
        # Les toutes premieres / dernieres images d'un enregistrement sont souvent ratees.
        bord = int(0.4 * FPS_ANALYSE)
        c.score[:bord] *= 0.3
        c.score[-bord:] *= 0.3
        c.beaute[:bord] *= 0.3
        c.beaute[-bord:] *= 0.3


# ------------------------------------------------------------------- musique

@dataclass
class AnalyseMusique:
    chemin: str
    duree: float
    bpm: float
    periode: float               # duree d'un temps (s)
    phase: float                 # instant du premier temps (s)
    phase_mesure: int            # quel temps (0..3) ouvre une mesure
    drop: float                  # instant ou la musique "explose" (s)

    def temps(self, debut, fin):
        """Instants des temps (beats) dans [debut, fin], tempo suppose constant."""
        k0 = int(np.ceil((debut - self.phase) / self.periode - 1e-6))
        k1 = int(np.floor((fin - self.phase) / self.periode + 1e-6))
        return [self.phase + k * self.periode for k in range(max(k0, 0), k1 + 1)]

    def mesures(self, debut, fin):
        """Instants des premiers temps de mesure dans [debut, fin]."""
        return [t for t in self.temps(debut, fin)
                if round((t - self.phase) / self.periode) % 4 == self.phase_mesure]


def analyser_musique(chemin, journal=print):
    sr, hop, n_fft = 22050, 512, 2048
    y = ff.lire_audio(chemin, sr)
    if y.size < sr * 4:
        raise ff.ErreurFFmpeg(f"{chemin} : musique trop courte ou illisible")
    duree = y.size / sr
    # Trames centrees : la trame i decrit l'instant i * hop / sr
    y = np.concatenate([np.zeros(n_fft // 2, np.float32), y])
    fps = sr / hop

    # Enveloppe d'attaques : flux spectral positif (montee d'energie par bande)
    nb = 1 + (y.size - n_fft) // hop
    trames = np.lib.stride_tricks.as_strided(
        y, shape=(nb, n_fft), strides=(y.strides[0] * hop, y.strides[0]))
    spectre = np.abs(np.fft.rfft(trames * np.hanning(n_fft).astype(np.float32), axis=1))
    spectre = np.log1p(100 * spectre)
    montee = np.maximum(np.diff(spectre, axis=0), 0)
    coupure_basses = int(250 * n_fft / sr)

    def enveloppe(flux):
        flux = np.concatenate([[0], flux])
        flux -= np.convolve(flux, np.ones(16) / 16, mode="same")
        flux = np.maximum(flux, 0)
        return flux / (np.percentile(flux, 99) + 1e-9)

    # Les charlestons sur les contretemps dominent le spectre complet : on donne autant
    # de poids aux basses (grosse caisse), qui tombent sur les temps.
    env = enveloppe(montee.sum(axis=1)) + enveloppe(montee[:, :coupure_basses].sum(axis=1))
    env /= env.max() + 1e-9

    # Tempo : autocorrelation de l'enveloppe, preference autour de 120 BPM
    ac = np.correlate(env, env, mode="full")[env.size - 1:]
    lags = np.arange(ac.size)
    valides = (lags >= fps * 60 / 185) & (lags <= fps * 60 / 68)
    bpm_lags = 60 * fps / np.maximum(lags, 1)
    poids = np.exp(-0.5 * (np.log2(bpm_lags / 120) / 0.9) ** 2)
    candidat = np.where(valides, ac * poids, -np.inf)
    periode0 = float(np.argmax(candidat))

    # Affinage periode + phase : maximise la somme de l'enveloppe sur une grille de temps
    idx = np.arange(env.size)

    def peigne(periode, phase):
        pos = np.arange(phase, env.size - 1, periode)
        return np.interp(pos, idx, env).mean()

    meilleur = (-1.0, periode0, 0.0)
    for periode in np.linspace(periode0 * 0.97, periode0 * 1.03, 61):
        for phase in np.linspace(0, periode, 24, endpoint=False):
            s = peigne(periode, phase)
            if s > meilleur[0]:
                meilleur = (s, periode, phase)
    _, periode, phase = meilleur
    for phase_fine in np.linspace(phase - periode / 24, phase + periode / 24, 9):
        if phase_fine >= 0 and peigne(periode, phase_fine) > meilleur[0]:
            meilleur = (peigne(periode, phase_fine), periode, phase_fine)
    _, periode, phase = meilleur
    periode_s, phase_s = periode / fps, phase / fps

    # Debut de mesure : le temps de la mesure ou les basses frappent le plus fort
    basses = spectre[:, : int(150 * n_fft / sr)].sum(axis=1)
    basses = np.maximum(np.diff(basses, prepend=basses[0]), 0)
    temps_idx = np.arange(phase, env.size - 1, periode)
    forces = np.interp(temps_idx, idx, basses)
    phase_mesure = int(np.argmax([forces[k::4].mean() if forces[k::4].size else 0
                                  for k in range(4)]))

    # Drop : la plus forte montee d'energie entre 4 s avant et 4 s apres un debut de mesure
    rms = np.sqrt((trames ** 2).mean(axis=1))
    lisse = np.convolve(rms, np.ones(int(fps)) / int(fps), mode="same")
    musique = AnalyseMusique(str(chemin), duree, 60 / periode_s, periode_s, phase_s,
                             phase_mesure, 0.0)
    fenetre = int(4 * fps)
    meilleur_drop, drop = -1.0, 0.0
    for t in musique.mesures(4.0, duree - 12.0):
        i = int(t * fps)
        apres, avant = lisse[i:i + fenetre].mean(), lisse[i - fenetre:i].mean()
        gain = (apres - avant) / (lisse.max() + 1e-9)
        if gain > meilleur_drop:
            meilleur_drop, drop = gain, t
    musique.drop = drop if meilleur_drop > 0.08 else 0.0

    journal(f"  musique : {musique.bpm:.0f} BPM"
            + (f", drop a {musique.drop:.1f} s" if musique.drop else ", pas de drop net"))
    return musique
