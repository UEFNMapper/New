"""Appels a ffmpeg / ffprobe : sondage des fichiers, lecture d'images et d'audio."""

import json
import shutil
import subprocess
import sys

import numpy as np

# Sous Windows, evite qu'une console noire s'ouvre a chaque appel depuis l'interface.
_FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0) if sys.platform == "win32" else 0


class ErreurFFmpeg(RuntimeError):
    pass


def verifier_ffmpeg():
    manquants = [p for p in ("ffmpeg", "ffprobe") if shutil.which(p) is None]
    if manquants:
        raise ErreurFFmpeg(
            "ffmpeg est introuvable. Installe-le puis relance :\n"
            "  Windows : winget install Gyan.FFmpeg   (puis rouvre la fenetre)\n"
            "  macOS   : brew install ffmpeg\n"
            "  Linux   : sudo apt install ffmpeg"
        )


def executer(cmd):
    """Lance une commande ffmpeg ; en cas d'echec, remonte la fin du journal."""
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          creationflags=_FLAGS)
    if proc.returncode != 0:
        fin = proc.stderr.decode("utf-8", "replace").strip().splitlines()[-15:]
        raise ErreurFFmpeg("ffmpeg a echoue :\n" + "\n".join(fin))
    return proc


def sonder(chemin):
    proc = executer(["ffprobe", "-v", "error", "-print_format", "json",
                     "-show_format", "-show_streams", str(chemin)])
    data = json.loads(proc.stdout)
    video = next((s for s in data["streams"] if s["codec_type"] == "video"), None)
    if video is None:
        raise ErreurFFmpeg(f"{chemin} ne contient pas de piste video")
    audio = any(s["codec_type"] == "audio" for s in data["streams"])
    num, den = (video.get("avg_frame_rate") or "30/1").split("/")
    fps = float(num) / float(den) if float(den) else 30.0
    duree = float(data["format"].get("duration") or video.get("duration") or 0)
    return {"duree": duree, "largeur": int(video["width"]), "hauteur": int(video["height"]),
            "fps": fps, "audio": audio}


def iterer_images(chemin, fps, largeur, hauteur):
    """Rend chaque image (RGB uint8, hauteur x largeur) a la cadence demandee, en flux."""
    cmd = ["ffmpeg", "-v", "error", "-i", str(chemin), "-an",
           "-vf", f"fps={fps},scale={largeur}:{hauteur}:flags=area",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            creationflags=_FLAGS)
    taille = largeur * hauteur * 3
    try:
        while True:
            brut = proc.stdout.read(taille)
            if len(brut) < taille:
                break
            yield np.frombuffer(brut, np.uint8).reshape(hauteur, largeur, 3)
    finally:
        proc.stdout.close()
        proc.wait()


def lire_audio(chemin, frequence=22050):
    """Audio mono en float32 dans [-1, 1]. Tableau vide si le fichier n'a pas de son."""
    cmd = ["ffmpeg", "-v", "error", "-i", str(chemin), "-vn", "-ac", "1",
           "-ar", str(frequence), "-f", "f32le", "-"]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          creationflags=_FLAGS)
    return np.frombuffer(proc.stdout, np.float32).copy()


def extraire_image(chemin, temps, sortie):
    executer(["ffmpeg", "-v", "error", "-y", "-ss", f"{temps:.3f}", "-i", str(chemin),
              "-frames:v", "1", str(sortie)])
