#!/usr/bin/env python3
"""Trailer Studio : interface web locale (http://127.0.0.1) qui pilote le moteur de montage.

Rien ne sort de ton PC : le serveur n'ecoute que sur ta machine, et tes videos
sont simplement copiees dans le dossier travail/ pour etre montees.
"""

import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import traceback
import uuid
import webbrowser
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

from trailer_uefn import ffmpeg_outils as ff
from trailer_uefn.analyse import analyser_musique
from trailer_uefn.montage import MENTIONS_EPIC, Clip, Options, creer_trailer, lister_clips

RACINE = Path(__file__).resolve().parent
WEB = RACINE / "web"
POLICES = RACINE / "polices"
TRAVAIL = RACINE / "travail"
SORTIES = RACINE / "trailers"
TYPES_ENVOI = {"clip", "musique", "image"}

envois = {}             # id -> {"type", "chemin", ...}
taches = {}             # id -> etat du rendu
verrou = threading.Lock()


def nom_sur(nom):
    """Nom de fichier sans chemin ni caracteres genants (garde lettres, chiffres, espaces)."""
    nom = Path(nom.replace("\\", "/")).name
    nom = re.sub(r"[^\w .()\-]+", "_", nom).strip(" .")
    return nom[:120] or "fichier"


def url_fichier(chemin):
    return "/fichiers/" + str(Path(chemin).resolve().relative_to(RACINE).as_posix())


# ------------------------------------------------------------------ envois

def traiter_envoi(type_, chemin):
    """Prepare la fiche d'un fichier recu (apercu, duree, tempo...)."""
    fiche = {"id": uuid.uuid4().hex[:12], "type": type_, "nom": chemin.name, "chemin": str(chemin)}
    if type_ == "clip":
        infos = ff.sonder(chemin)
        apercu = chemin.parent / "apercu.jpg"
        ff.executer(["ffmpeg", "-v", "error", "-y", "-ss", f"{infos['duree'] * 0.35:.2f}",
                     "-i", str(chemin), "-frames:v", "1", "-vf", "scale=480:-2", str(apercu)])
        fiche.update(duree=infos["duree"], largeur=infos["largeur"], hauteur=infos["hauteur"],
                     apercu=url_fichier(apercu), etiquette=lister_clips([chemin])[0].etiquette or "")
    elif type_ == "musique":
        m = analyser_musique(chemin, journal=lambda _m: None)
        fiche.update(duree=m.duree, bpm=round(float(m.bpm)), drop=round(float(m.drop), 1))
    else:
        fiche.update(url=url_fichier(chemin))
    envois[fiche["id"]] = fiche
    return {k: v for k, v in fiche.items() if k != "chemin"}


# ------------------------------------------------------------------- rendu

def lancer_rendu(donnees):
    with verrou:
        if any(t["statut"] == "en_cours" for t in taches.values()):
            raise ValueError("Un trailer est deja en cours de creation.")
        clips = []
        for c in donnees.get("clips", []):
            fiche = envois.get(c.get("id"))
            if not fiche or fiche["type"] != "clip":
                raise ValueError("Une video a disparu : ajoute-la de nouveau.")
            clips.append(Clip(fiche["chemin"], (c.get("etiquette") or "").strip().upper() or None))
        if not clips:
            raise ValueError("Ajoute au moins une video de gameplay.")

        def chemin_envoi(cle):
            fiche = envois.get(donnees.get(cle) or "")
            return fiche["chemin"] if fiche else ""

        o = donnees.get("options", {})
        opts = Options(
            titre=o.get("titre", "").strip(), code=o.get("code", "").strip(),
            textes=[t.strip() for t in o.get("textes", []) if t.strip()],
            accroche=o.get("accroche", "").strip(), texte_final=o.get("final", "").strip(),
            musique=chemin_envoi("musique"), logo=chemin_envoi("logo"),
            image_fin=chemin_envoi("image_fin"),
            duree=float(o.get("duree", 30)), rythme=o.get("rythme", "normal"),
            format="vertical" if o.get("vertical") else "horizontal",
            fps=60 if o.get("fps60", True) else 30, accent=o.get("couleur", "#FFD400"),
            mentions=MENTIONS_EPIC if o.get("mentions", True) else "",
            volume_jeu=float(o.get("volume_jeu", 0.35)), badge=o.get("badge", "").strip(),
            miniatures=3,
        )
        horodatage = datetime.now().strftime("%Y-%m-%d_%Hh%M")
        dossier = SORTIES / nom_sur(f"{horodatage} {opts.titre or 'trailer'}")
        id_tache = uuid.uuid4().hex[:12]
        tache = {"id": id_tache, "statut": "en_cours", "progression": 0.0, "etape": "Preparation",
                 "journal": [], "debut": time.time(), "dossier": str(dossier)}
        taches[id_tache] = tache

    def travail():
        try:
            def progression(f, etape):
                tache["progression"], tache["etape"] = f, etape
            sortie = creer_trailer(clips, dossier / "trailer.mp4", opts,
                                   journal=tache["journal"].append, progression=progression)
            tache["video"] = url_fichier(sortie)
            tache["miniatures"] = [url_fichier(p) for p in sorted(dossier.glob("miniature_*.png"))]
            tache["statut"] = "termine"
        except Exception as e:
            tache["journal"].append(traceback.format_exc())
            tache["erreur"] = str(e)
            tache["statut"] = "erreur"
        tache["fin"] = time.time()

    threading.Thread(target=travail, daemon=True).start()
    return {"id": id_tache}


def ouvrir_dossier(chemin):
    if sys.platform == "win32":
        os.startfile(chemin)  # noqa: S606 - dossier local produit par l'appli
    else:
        subprocess.Popen(["open" if sys.platform == "darwin" else "xdg-open", chemin])


# ----------------------------------------------------------------- serveur

class Gestionnaire(BaseHTTPRequestHandler):
    server_version = "TrailerStudio/1.0"

    def log_message(self, *_):
        pass

    def _json(self, donnees, statut=HTTPStatus.OK):
        corps = json.dumps(donnees).encode()
        self.send_response(statut)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(corps)

    def _fichier(self, chemin, racines):
        chemin = chemin.resolve()
        if not any(chemin.is_relative_to(r.resolve()) for r in racines) or not chemin.is_file():
            return self._json({"erreur": "introuvable"}, HTTPStatus.NOT_FOUND)
        taille = chemin.stat().st_size
        debut, fin = 0, taille - 1
        plage = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if plage and (plage.group(1) or plage.group(2)):   # lecture video avec avance rapide
            if plage.group(1):
                debut = int(plage.group(1))
                fin = min(int(plage.group(2)), taille - 1) if plage.group(2) else taille - 1
            else:
                debut = max(0, taille - int(plage.group(2)))
            self.send_response(HTTPStatus.PARTIAL_CONTENT)
            self.send_header("Content-Range", f"bytes {debut}-{fin}/{taille}")
        else:
            self.send_response(HTTPStatus.OK)
        type_ = mimetypes.guess_type(chemin.name)[0] or "application/octet-stream"
        if chemin.suffix == ".js":
            type_ = "text/javascript"
        self.send_header("Content-Type", type_)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(fin - debut + 1))
        self.send_header("Cache-Control", "no-cache")
        if "telecharger" in parse_qs(urlparse(self.path).query):
            self.send_header("Content-Disposition", f'attachment; filename="{chemin.name}"')
        self.end_headers()
        with open(chemin, "rb") as f:
            f.seek(debut)
            reste = fin - debut + 1
            try:
                while reste > 0:
                    bloc = f.read(min(1 << 20, reste))
                    if not bloc:
                        break
                    self.wfile.write(bloc)
                    reste -= len(bloc)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def do_GET(self):
        url = urlparse(self.path)
        chemin = unquote(url.path)
        if chemin == "/":
            return self._fichier(WEB / "index.html", [WEB])
        if chemin.startswith("/web/"):
            return self._fichier(WEB / chemin[5:], [WEB])
        if chemin.startswith("/polices/"):
            return self._fichier(POLICES / chemin[9:], [POLICES])
        if chemin.startswith("/fichiers/"):
            return self._fichier(RACINE / chemin[10:], [TRAVAIL, SORTIES])
        if chemin == "/api/etat":
            tache = taches.get(parse_qs(url.query).get("id", [""])[0])
            if not tache:
                return self._json({"erreur": "tache inconnue"}, HTTPStatus.NOT_FOUND)
            fin = tache.get("fin") or time.time()
            return self._json({**{k: v for k, v in tache.items() if k != "journal"},
                               "journal": tache["journal"][-60:], "ecoule": fin - tache["debut"]})
        if chemin == "/api/sante":
            try:
                ff.verifier_ffmpeg()
                return self._json({"ffmpeg": True})
            except ff.ErreurFFmpeg as e:
                return self._json({"ffmpeg": False, "message": str(e)})
        self._json({"erreur": "introuvable"}, HTTPStatus.NOT_FOUND)

    def do_POST(self):
        url = urlparse(self.path)
        try:
            if url.path == "/api/envoi":
                q = parse_qs(url.query)
                type_ = q.get("type", [""])[0]
                if type_ not in TYPES_ENVOI:
                    raise ValueError("type d'envoi inconnu")
                dossier = TRAVAIL / uuid.uuid4().hex[:12]
                dossier.mkdir(parents=True)
                chemin = dossier / nom_sur(q.get("nom", ["fichier"])[0])
                reste = int(self.headers.get("Content-Length", 0))
                with open(chemin, "wb") as f:      # copie en flux : pas de limite de taille
                    while reste > 0:
                        bloc = self.rfile.read(min(1 << 20, reste))
                        if not bloc:
                            break
                        f.write(bloc)
                        reste -= len(bloc)
                try:
                    return self._json(traiter_envoi(type_, chemin))
                except Exception:
                    shutil.rmtree(dossier, ignore_errors=True)
                    raise ValueError(f"Fichier illisible : {chemin.name}")
            longueur = int(self.headers.get("Content-Length", 0))
            donnees = json.loads(self.rfile.read(longueur) or b"{}")
            if url.path == "/api/creer":
                return self._json(lancer_rendu(donnees))
            if url.path == "/api/ouvrir":
                tache = taches.get(donnees.get("id", ""))
                if tache:
                    ouvrir_dossier(tache["dossier"])
                return self._json({"ok": bool(tache)})
            self._json({"erreur": "introuvable"}, HTTPStatus.NOT_FOUND)
        except Exception as e:
            self._json({"erreur": str(e)}, HTTPStatus.BAD_REQUEST)


def main():
    shutil.rmtree(TRAVAIL, ignore_errors=True)     # fichiers de la session precedente
    TRAVAIL.mkdir(parents=True, exist_ok=True)
    SORTIES.mkdir(parents=True, exist_ok=True)
    port = int(os.environ.get("PORT", "8765"))
    for essai in range(port, port + 20):
        try:
            serveur = ThreadingHTTPServer(("127.0.0.1", essai), Gestionnaire)
            break
        except OSError:
            continue
    else:
        sys.exit("Aucun port libre entre %d et %d" % (port, port + 19))
    adresse = f"http://127.0.0.1:{serveur.server_port}/"
    print(f"Trailer Studio est ouvert dans ton navigateur : {adresse}")
    print("Laisse cette fenetre ouverte pendant que tu travailles. Ctrl+C pour quitter.")
    if not os.environ.get("SANS_NAVIGATEUR"):
        threading.Timer(0.8, webbrowser.open, args=(adresse,)).start()
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
