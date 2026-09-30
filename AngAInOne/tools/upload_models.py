#!/usr/bin/env python3
"""
upload_models.py — envoie assets/models/*.glb sur Roblox (Open Cloud) et remplit
src/shared/Config/ModelAssets.luau avec les IDs. Ne renvoie que les modèles modifiés.

Variables d'environnement :
  ROBLOX_API_KEY     clé Open Cloud (permission « Assets : read + write »)
  ROBLOX_CREATOR_ID  ID de l'utilisateur (ou du groupe) propriétaire du jeu
  ROBLOX_CREATOR_TYPE "User" (défaut) ou "Group"
Usage : python3 tools/upload_models.py [--dry-run]
"""
import hashlib, json, os, sys, time, urllib.request, uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")
MANIFEST = os.path.join(MODELS, "manifest.json")
CONFIG = os.path.join(ROOT, "src", "shared", "Config", "ModelAssets.luau")
API = "https://apis.roblox.com/assets/v1"


def request(method, url, key, body=None, headers=None):
    req = urllib.request.Request(url, data=body, method=method, headers={"x-api-key": key, **(headers or {})})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode() or "{}")


def upload(path, name, key, creator_id, creator_type, existing_id=None):
    boundary = uuid.uuid4().hex
    meta = {"assetType": "Model", "displayName": f"AngAInOne {name}", "description": "AngAInOne — modèle 3D"}
    creator = {"userId": creator_id} if creator_type == "User" else {"groupId": creator_id}
    if not existing_id:
        meta["creationContext"] = {"creator": creator}
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n{json.dumps(meta)}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{name}.glb\"\r\n"
        f"Content-Type: model/gltf-binary\r\n\r\n".encode(),
        open(path, "rb").read(),
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    if existing_id:
        op = request("PATCH", f"{API}/assets/{existing_id}", key, b"".join(parts), headers)
    else:
        op = request("POST", f"{API}/assets", key, b"".join(parts), headers)
    op_path = op.get("path") or f"operations/{op.get('operationId')}"
    for _ in range(60):
        status = request("GET", f"{API}/{op_path}", key)
        if status.get("done"):
            response = status.get("response") or {}
            if "assetId" not in response:
                raise RuntimeError(f"{name}: {status}")
            return int(response["assetId"])
        time.sleep(2)
    raise RuntimeError(f"{name}: délai dépassé")


def write_config(ids):
    lines = [f"\t{name} = {asset_id}," for name, asset_id in sorted(ids.items())]
    text = open(CONFIG, encoding="utf-8").read()
    start = text.index("-- BEGIN") + len("-- BEGIN")
    end = text.index("\t-- END")
    text = text[:start] + "\n" + "\n".join(lines) + "\n" + text[end:]
    open(CONFIG, "w", encoding="utf-8").write(text)


def main():
    dry = "--dry-run" in sys.argv
    key = os.environ.get("ROBLOX_API_KEY")
    creator = os.environ.get("ROBLOX_CREATOR_ID")
    creator_type = os.environ.get("ROBLOX_CREATOR_TYPE", "User")
    if not dry and (not key or not creator):
        sys.exit("ROBLOX_API_KEY et ROBLOX_CREATOR_ID sont nécessaires (ou --dry-run).")
    manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}
    ids = {name: entry["id"] for name, entry in manifest.items() if entry.get("id")}
    for file in sorted(os.listdir(MODELS)):
        if not file.endswith(".glb"):
            continue
        name = file[:-4]
        path = os.path.join(MODELS, file)
        digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
        entry = manifest.get(name, {})
        if entry.get("sha") == digest and entry.get("id"):
            continue
        print(f"→ {name}" + (" (mise à jour)" if entry.get("id") else ""))
        if dry:
            continue
        asset_id = upload(path, name, key, int(creator), creator_type, entry.get("id"))
        manifest[name] = {"id": asset_id, "sha": digest}
        ids[name] = asset_id
        json.dump(manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
    if not dry:
        write_config(ids)
        print(f"{len(ids)} modèles dans ModelAssets.luau")


if __name__ == "__main__":
    main()
