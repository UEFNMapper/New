#!/usr/bin/env python3
"""
Upload des assets du jeu (icônes, sons, modèles) vers Roblox via l'API Open Cloud « Assets »,
puis écriture automatique des identifiants dans :
  - src/shared/Config/Icons.luau   (champ `Id` de chaque clé)
  - src/shared/Config/Sounds.luau  (table `Uploaded` entre les marqueurs BEGIN/END UPLOADED)

Usage :
  python3 tools/upload_assets.py --api-key XXXX --user-id 123456 [--only icons|audio|models] [--dry-run]
  ROBLOX_API_KEY=XXXX python3 tools/upload_assets.py --group-id 987654

Dépendances : Python 3.9+ uniquement (urllib, pas de `requests`). Voir docs/UPLOAD.md.

=====================================================================================
Contrat de l'API Open Cloud Assets — vérifié le 2026-09-27
-------------------------------------------------------------------------------------
Sources consultées :
  * https://create.roblox.com/docs/cloud/guides/usage-assets (guide officiel)
  * https://devforum.roblox.com/t/opencloud-assets-api/2298007 (tutoriel communautaire)
  * https://devforum.roblox.com/t/provide-a-stable-open-cloud-api-to-get-an-image-id-from-a-decal-id/3594046
  * https://devforum.roblox.com/t/open-cloud-upload-support-for-more-asset-types/4022082 (oct. 2025)
  * https://github.com/Vsad-Laboratories/Party-Panic/pull/22 (retour terrain : assetType "Image")
  (la page de référence https://create.roblox.com/docs/cloud/reference/Asset renvoyait 404 depuis ici)

Création :
  POST https://apis.roblox.com/assets/v1/assets
  En-tête : x-api-key: <clé>   (la clé doit avoir la permission « Assets » en lecture + écriture,
            i.e. scopes asset:read + asset:write, et l'IP autorisée)
  Corps multipart/form-data, 2 parties :
    - "request"     : JSON {"assetType": "...", "displayName": "...", "description": "...",
                            "creationContext": {"creator": {"userId": "..."}}}   (ou {"groupId": "..."})
                      Optionnel : "expectedPrice" (0 par défaut ; utile surtout pour Audio/Model payants).
    - "fileContent" : le fichier, avec son Content-Type.
  Types acceptés en upload (guide officiel) :
    Audio : .mp3 .ogg .wav .flac      -> audio/mpeg, audio/ogg, audio/wav, audio/flac
    Decal : .png .jpeg .bmp .tga      -> image/png, image/jpeg, image/bmp, image/tga
    Model : .fbx .gltf .glb .rbxm .rbxmx -> model/fbx, model/gltf+json, model/gltf-binary, model/x-rbxm
    Video : .mp4 .mov                 -> video/mp4, video/mov
    (donc OUI, un .fbx s'uploade avec assetType "Model" et Content-Type model/fbx ; c'est même le seul
     type dont le contenu peut être mis à jour par PATCH ensuite.)
  Limites : 20 Mo par fichier ; Audio : 100 uploads / mois (compte vérifié par pièce d'identité),
  10 / mois sinon ; image < 8000×8000 px ; les assets passent en modération (moderationState).
  Réponse : 200 {"path": "operations/<operationId>"}   (une « Operation », asynchrone)

Suivi :
  GET https://apis.roblox.com/assets/v1/operations/<operationId>   (x-api-key)
  Réponse : {"path": "...", "done": true/false,
             "response": {"path": "assets/<id>", "assetId": "<id>", "assetType": "...",
                          "revisionId": "1", "revisionCreateTime": "...", "displayName": "...",
                          "moderationResult": {"moderationState": "Approved|Reviewing|Rejected"},
                          "creationContext": {...}},
             "error": {"code": ..., "message": ...}}   (si échec)
  Tant que "done" est absent/false, on ré-interroge (ici toutes les 1,5 s, 2 min max).

Codes d'erreur utiles : 400 (JSON/type invalide), 401 (clé), 403 (permission/IP), 429 (trop de
requêtes -> en-tête Retry-After, on attend et on réessaie), 5xx (on réessaie).

⚠️  Le piège des images : Decal vs Image
  Historiquement, assetType "Decal" est le seul type image documenté. Or l'id renvoyé est alors celui du
  DECAL (asset enveloppe), et ImageLabel.Image / ImageButton.Image attendent l'id de l'IMAGE sous-jacente
  (asset distinct, id différent) : avec l'id du decal, l'image reste vide en jeu.
  Ce qui a été vérifié :
    1. Des projets récents (2025-2026) uploadent avec assetType "Image" et obtiennent directement un id
       utilisable dans ImageLabel (« Active + Approved »). Ce n'est pas encore dans le tableau officiel, et
       certaines bibliothèques (rblx-open-cloud) marquent encore Image comme « lecture seule ». Le script
       essaie donc "Image" D'ABORD ; si l'API répond 400 « invalid asset type », il retombe sur "Decal".
    2. Passage decal -> image : il n'existe pas d'endpoint Open Cloud stable. Solutions :
         a) GET https://apis.roblox.com/asset-delivery-api/v1/assetId/<decalId>  (x-api-key ; nécessite la
            permission « Legacy Asset Delivery / legacy-asset:manage » sur la clé, indisponible pour les
            groupes) -> {"location": "<url>"} -> télécharger le .rbxm (XML) et lire
            <Content name="Texture"><url>http://www.roblox.com/asset/?id=IMAGE_ID</url></Content>.
            Le script tente cette méthode automatiquement.
         b) https://assetdelivery.roblox.com/v1/asset?id=<decalId> : même chose mais réclame un cookie
            .ROBLOSECURITY -> pas utilisé ici.
         c) Manuel : dans Studio, coller "rbxassetid://<decalId>" dans la propriété Image d'un ImageLabel ;
            Studio le convertit tout seul en id d'image (puis recopier cet id dans Icons.luau).
  Le cache assets/upload_state.json conserve les deux ids (decalId / imageId) pour ne rien perdre.
=====================================================================================
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATIONS_URL = "https://apis.roblox.com/assets/v1/operations/{}"
ASSET_DELIVERY_URL = "https://apis.roblox.com/asset-delivery-api/v1/assetId/{}"

ICONS_DIR = os.path.join(ROOT, "assets", "icons")
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")
MODELS_DIR = os.path.join(ROOT, "assets", "models")
VFX_DIR = os.path.join(ROOT, "assets", "vfx")
STATE_PATH = os.path.join(ROOT, "assets", "upload_state.json")
ICONS_LUAU = os.path.join(ROOT, "src", "shared", "Config", "Icons.luau")
SOUNDS_LUAU = os.path.join(ROOT, "src", "shared", "Config", "Sounds.luau")
VFX_LUAU = os.path.join(ROOT, "src", "shared", "Config", "Vfx.luau")

CONTENT_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".bmp": "image/bmp",
    ".tga": "image/tga",
    ".ogg": "audio/ogg",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".flac": "audio/flac",
    ".fbx": "model/fbx",
    ".gltf": "model/gltf+json",
    ".glb": "model/gltf-binary",
    ".rbxm": "model/x-rbxm",
}

MIN_INTERVAL = 1.0  # secondes entre deux uploads (~1/s)


# ------------------------------------------------------------------ utilitaires


def log(msg: str) -> None:
    print(msg, flush=True)


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_state() -> dict:
    if os.path.exists(STATE_PATH):
        with open(STATE_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {"version": 1, "files": {}}


def save_state(state: dict) -> None:
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    os.replace(tmp, STATE_PATH)


class ApiError(Exception):
    def __init__(self, status: int, body: str):
        super().__init__(f"HTTP {status}: {body[:300]}")
        self.status = status
        self.body = body


def http(method: str, url: str, api_key: str, data: bytes | None = None, content_type: str | None = None,
         retries: int = 6) -> tuple[int, bytes, dict]:
    """Requête HTTP avec reprise automatique sur 429 / 5xx / erreurs réseau."""
    delay = 2.0
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("x-api-key", api_key)
        req.add_header("Accept", "application/json")
        if content_type:
            req.add_header("Content-Type", content_type)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.status, resp.read(), dict(resp.headers)
        except urllib.error.HTTPError as e:
            body = e.read()
            if e.code == 429 or 500 <= e.code < 600:
                wait = delay
                ra = e.headers.get("Retry-After")
                if ra and ra.isdigit():
                    wait = max(wait, float(ra))
                log(f"    ! HTTP {e.code}, nouvel essai dans {wait:.0f}s ({attempt + 1}/{retries})")
                time.sleep(wait)
                delay = min(delay * 2, 60)
                continue
            return e.code, body, dict(e.headers)
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            log(f"    ! erreur réseau {e}, nouvel essai dans {delay:.0f}s ({attempt + 1}/{retries})")
            time.sleep(delay)
            delay = min(delay * 2, 60)
    raise ApiError(0, "abandon après plusieurs essais")


def multipart(fields: dict[str, str], file_field: str, filename: str, content: bytes,
              content_type: str) -> tuple[bytes, str]:
    boundary = "----RobloxUpload" + uuid.uuid4().hex
    buf = io.BytesIO()
    for name, value in fields.items():
        buf.write(f"--{boundary}\r\n".encode())
        buf.write(f'Content-Disposition: form-data; name="{name}"\r\n'.encode())
        buf.write(b"Content-Type: application/json\r\n\r\n")
        buf.write(value.encode("utf-8"))
        buf.write(b"\r\n")
    buf.write(f"--{boundary}\r\n".encode())
    buf.write(f'Content-Disposition: form-data; name="{file_field}"; filename="{filename}"\r\n'.encode())
    buf.write(f"Content-Type: {content_type}\r\n\r\n".encode())
    buf.write(content)
    buf.write(f"\r\n--{boundary}--\r\n".encode())
    return buf.getvalue(), f"multipart/form-data; boundary={boundary}"


# ------------------------------------------------------------------ API Open Cloud


def create_asset(api_key: str, creator: dict, asset_type: str, path: str, display_name: str,
                 description: str) -> str:
    """Lance l'upload ; renvoie l'operationId."""
    ext = os.path.splitext(path)[1].lower()
    ctype = CONTENT_TYPES.get(ext) or mimetypes.guess_type(path)[0] or "application/octet-stream"
    with open(path, "rb") as f:
        content = f.read()
    request = {
        "assetType": asset_type,
        "displayName": display_name[:50],
        "description": description[:1000],
        "creationContext": {"creator": creator},
    }
    body, body_ctype = multipart({"request": json.dumps(request)}, "fileContent",
                                 os.path.basename(path), content, ctype)
    status, raw, _ = http("POST", ASSETS_URL, api_key, body, body_ctype)
    if status != 200:
        raise ApiError(status, raw.decode("utf-8", "replace"))
    data = json.loads(raw)
    op = data.get("operationId") or data.get("path", "").split("/")[-1]
    if not op:
        raise ApiError(status, "réponse sans operationId : " + raw.decode("utf-8", "replace"))
    return op


def wait_operation(api_key: str, operation_id: str, timeout: float = 120.0) -> dict:
    """Interroge l'opération jusqu'à done ; renvoie le champ `response`."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        status, raw, _ = http("GET", OPERATIONS_URL.format(operation_id), api_key)
        if status != 200:
            raise ApiError(status, raw.decode("utf-8", "replace"))
        data = json.loads(raw)
        if data.get("done"):
            if "error" in data:
                raise ApiError(200, json.dumps(data["error"]))
            return data.get("response", {})
        time.sleep(1.5)
    raise ApiError(0, f"opération {operation_id} toujours en cours après {timeout:.0f}s")


def is_invalid_asset_type(err: ApiError) -> bool:
    if err.status != 400:
        return False
    b = err.body.lower()
    return "assettype" in b or "asset type" in b or "invalid" in b


def resolve_image_id(api_key: str, decal_id: int) -> int | None:
    """Tente de retrouver l'id d'IMAGE derrière un DECAL (voir docstring). None si impossible."""
    try:
        status, raw, _ = http("GET", ASSET_DELIVERY_URL.format(decal_id), api_key, retries=2)
        if status != 200:
            return None
        location = json.loads(raw).get("location")
        if not location:
            return None
        req = urllib.request.Request(location)
        with urllib.request.urlopen(req, timeout=60) as resp:
            xml = resp.read().decode("utf-8", "replace")
        m = re.search(r"<url>[^<]*[?&]id=(\d+)</url>", xml)
        return int(m.group(1)) if m else None
    except Exception:
        return None


# ------------------------------------------------------------------ collecte des fichiers


def collect(only: str | None) -> list[dict]:
    jobs = []
    if only in (None, "icons") and os.path.isdir(ICONS_DIR):
        for name in sorted(os.listdir(ICONS_DIR)):
            if name.lower().endswith(".png") and name != "contact_sheet.png":
                jobs.append({"kind": "icons", "path": os.path.join(ICONS_DIR, name),
                             "key": os.path.splitext(name)[0], "assetType": "Image"})
    if only in (None, "audio") and os.path.isdir(AUDIO_DIR):
        for name in sorted(os.listdir(AUDIO_DIR)):
            if name.lower().endswith((".ogg", ".mp3", ".wav", ".flac")):
                jobs.append({"kind": "audio", "path": os.path.join(AUDIO_DIR, name),
                             "key": os.path.splitext(name)[0], "assetType": "Audio"})
    if only in (None, "vfx") and os.path.isdir(VFX_DIR):
        for name in sorted(os.listdir(VFX_DIR)):
            if name.lower().endswith(".png") and name != "contact_sheet.png":
                jobs.append({"kind": "vfx", "path": os.path.join(VFX_DIR, name),
                             "key": os.path.splitext(name)[0], "assetType": "Image"})
    if only in (None, "models") and os.path.isdir(MODELS_DIR):
        # Un dossier par espèce : assets/models/<Espece>/<fichier>.fbx
        # NB : l'upload donne un identifiant de MODEL (pas un MeshId). Le MeshId se lit dans
        # Studio après insertion du modèle (voir Config/Models.luau). L'identifiant est gardé
        # dans upload_state.json et affiché en fin d'exécution.
        for species in sorted(os.listdir(MODELS_DIR)):
            folder = os.path.join(MODELS_DIR, species)
            if not os.path.isdir(folder):
                continue
            for name in sorted(os.listdir(folder)):
                if name.lower().endswith((".fbx", ".gltf", ".glb", ".rbxm")):
                    jobs.append({"kind": "models", "path": os.path.join(folder, name),
                                 "key": species, "assetType": "Model"})
                    break
    return jobs


# ------------------------------------------------------------------ écriture des .luau


def patch_icons_luau(ids: dict[str, int]) -> int:
    if not os.path.exists(ICONS_LUAU) or not ids:
        return 0
    with open(ICONS_LUAU, encoding="utf-8") as f:
        src = f.read()
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        key = m.group(2)
        if key in ids and int(m.group(3)) != ids[key]:
            count += 1
            return f"{m.group(1)}{key} = {{ Id = {ids[key]}, Emoji = {m.group(4)} }},"
        return m.group(0)

    src = re.sub(r'^(\t)(\w+) = \{ Id = (\d+), Emoji = ("(?:[^"\\]|\\.)*") \},$', repl, src, flags=re.M)
    with open(ICONS_LUAU, "w", encoding="utf-8") as f:
        f.write(src)
    return count


def patch_vfx_luau(ids: dict[str, int]) -> int:
    if not os.path.exists(VFX_LUAU) or not ids:
        return 0
    with open(VFX_LUAU, encoding="utf-8") as f:
        src = f.read()
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        key = m.group(2)
        if key in ids and int(m.group(3)) != ids[key]:
            count += 1
            return f"{m.group(1)}{key} = {{ Id = {ids[key]}, Default = {m.group(4)} }},"
        return m.group(0)

    src = re.sub(r'^(\t)(\w+) = \{ Id = (\d+), Default = (.+?) \},$', repl, src, flags=re.M)
    with open(VFX_LUAU, "w", encoding="utf-8") as f:
        f.write(src)
    return count


def patch_sounds_luau(ids: dict[str, int]) -> int:
    if not os.path.exists(SOUNDS_LUAU) or not ids:
        return 0
    with open(SOUNDS_LUAU, encoding="utf-8") as f:
        src = f.read()
    begin = "-- BEGIN UPLOADED"
    end = "-- END UPLOADED"
    i = src.find(begin)
    j = src.find(end)
    if i < 0 or j < 0:
        log("  ! marqueurs BEGIN/END UPLOADED introuvables dans Sounds.luau, rien écrit")
        return 0
    block = src[i:j]
    existing: dict[str, int] = {}
    for m in re.finditer(r"^\t(\w+) = (\d+),$", block, flags=re.M):
        existing[m.group(1)] = int(m.group(2))
    merged = {**existing, **ids}
    header_line = block.split("\n", 1)[0]
    lines = [header_line, "local Uploaded: { [string]: number } = {"]
    for key in sorted(merged):
        lines.append(f"\t{key} = {merged[key]},")
    lines.append("}")
    new_block = "\n".join(lines) + "\n"
    src = src[:i] + new_block + src[j:]
    with open(SOUNDS_LUAU, "w", encoding="utf-8") as f:
        f.write(src)
    return sum(1 for k, v in ids.items() if existing.get(k) != v)


# ------------------------------------------------------------------ main


def main() -> int:
    ap = argparse.ArgumentParser(description="Upload des assets vers Roblox (Open Cloud) et écriture des ids.")
    ap.add_argument("--api-key", default=os.environ.get("ROBLOX_API_KEY"), help="clé Open Cloud (ou env ROBLOX_API_KEY)")
    who = ap.add_mutually_exclusive_group()
    who.add_argument("--user-id", type=int, help="uploader sur ton compte")
    who.add_argument("--group-id", type=int, help="uploader sur un groupe")
    ap.add_argument("--only", choices=["icons", "audio", "vfx", "models"], help="ne traiter qu'une catégorie")
    ap.add_argument("--image-type", choices=["Image", "Decal"], default="Image",
                    help="assetType envoyé pour les PNG (défaut : Image, repli automatique sur Decal)")
    ap.add_argument("--dry-run", action="store_true", help="liste ce qui serait uploadé, sans rien envoyer")
    ap.add_argument("--force", action="store_true", help="ré-uploade même les fichiers déjà dans le cache")
    args = ap.parse_args()

    jobs = collect(args.only)
    state = load_state()
    files = state.setdefault("files", {})

    todo = []
    for job in jobs:
        rel = os.path.relpath(job["path"], ROOT).replace(os.sep, "/")
        digest = sha256_of(job["path"])
        job["rel"], job["sha256"] = rel, digest
        cached = files.get(rel)
        if cached and cached.get("sha256") == digest and cached.get("assetId") and not args.force:
            continue
        todo.append(job)

    log(f"{len(jobs)} fichier(s) trouvé(s), {len(jobs) - len(todo)} déjà uploadé(s), {len(todo)} à envoyer.")
    if args.dry_run:
        for job in todo:
            log(f"  - {job['rel']}  ({job['assetType']})")
        return 0
    if not todo:
        write_back(files)
        return 0

    if not args.api_key:
        log("Erreur : --api-key manquant (ou variable ROBLOX_API_KEY).")
        return 2
    if not args.user_id and not args.group_id:
        log("Erreur : indique --user-id ou --group-id.")
        return 2
    creator = {"userId": str(args.user_id)} if args.user_id else {"groupId": str(args.group_id)}

    image_type = args.image_type
    failures = 0
    last_upload = 0.0
    for n, job in enumerate(todo, 1):
        asset_type = image_type if job["kind"] == "icons" else job["assetType"]
        log(f"[{n}/{len(todo)}] {job['rel']}  ->  {asset_type}")
        elapsed = time.time() - last_upload
        if elapsed < MIN_INTERVAL:
            time.sleep(MIN_INTERVAL - elapsed)
        display = f"SAK {job['key']}"
        desc = f"Steal a Kaiju - {job['kind']} - {job['key']} (sha256 {job['sha256'][:12]})"
        try:
            try:
                op = create_asset(args.api_key, creator, asset_type, job["path"], display, desc)
            except ApiError as e:
                if job["kind"] == "icons" and asset_type == "Image" and is_invalid_asset_type(e):
                    log("    ! assetType Image refusé par l'API, repli sur Decal pour la suite")
                    image_type = asset_type = "Decal"
                    op = create_asset(args.api_key, creator, asset_type, job["path"], display, desc)
                else:
                    raise
            last_upload = time.time()
            resp = wait_operation(args.api_key, op)
            asset_id = int(resp.get("assetId") or resp.get("path", "").split("/")[-1])
            entry = {
                "sha256": job["sha256"],
                "kind": job["kind"],
                "key": job["key"],
                "assetType": asset_type,
                "assetId": asset_id,
                "operationId": op,
                "moderation": (resp.get("moderationResult") or {}).get("moderationState"),
                "uploadedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            }
            if job["kind"] == "icons":
                if asset_type == "Decal":
                    entry["decalId"] = asset_id
                    image_id = resolve_image_id(args.api_key, asset_id)
                    if image_id:
                        entry["imageId"] = image_id
                        log(f"    decal {asset_id} -> image {image_id}")
                    else:
                        log(f"    ! decal {asset_id} : id d'image introuvable (voir docs/UPLOAD.md, "
                            "colle le decal dans Studio pour le convertir)")
                else:
                    entry["imageId"] = asset_id
            files[job["rel"]] = entry
            save_state(state)
            log(f"    ok  assetId={asset_id}  modération={entry['moderation']}")
        except ApiError as e:
            failures += 1
            log(f"    ÉCHEC : {e}")
            if e.status in (401, 403):
                log("    (clé invalide, permission Assets manquante ou IP non autorisée : arrêt)")
                break

    write_back(files)
    if failures:
        log(f"{failures} échec(s). Relance le script : les fichiers déjà envoyés sont ignorés.")
        return 1
    return 0


def write_back(files: dict) -> None:
    icon_ids: dict[str, int] = {}
    sound_ids: dict[str, int] = {}
    vfx_ids: dict[str, int] = {}
    model_ids: dict[str, int] = {}
    for entry in files.values():
        if not entry.get("assetId"):
            continue
        if entry.get("kind") == "icons" and entry.get("imageId"):
            icon_ids[entry["key"]] = int(entry["imageId"])
        elif entry.get("kind") == "vfx" and entry.get("imageId"):
            vfx_ids[entry["key"]] = int(entry["imageId"])
        elif entry.get("kind") == "audio":
            sound_ids[entry["key"]] = int(entry["assetId"])
        elif entry.get("kind") == "models":
            model_ids[entry["key"]] = int(entry["assetId"])
    a = patch_icons_luau(icon_ids)
    b = patch_sounds_luau(sound_ids)
    c = patch_vfx_luau(vfx_ids)
    log(f"Icons.luau : {a} id(s) ; Sounds.luau : {b} id(s) ; Vfx.luau : {c} id(s) mis à jour.")
    if model_ids:
        log("Modèles uploadés (identifiants de MODEL, pas de MeshId) — dans Studio : Toolbox → Inventaire →")
        log("Mes modèles → insère chaque modèle, lis MeshId/TextureID de sa MeshPart et colle-les dans Config/Models.luau :")
        for key, aid in sorted(model_ids.items()):
            log(f"  {key}: rbxassetid://{aid}")


if __name__ == "__main__":
    sys.exit(main())
