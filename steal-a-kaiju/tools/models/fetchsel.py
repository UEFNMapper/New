import sys, json, os, re, time, gdown
listing, outdir = sys.argv[1], sys.argv[2]
pat = re.compile(sys.argv[3]) if len(sys.argv) > 3 else re.compile(r"(glTF/.*\.(gltf|glb|png|bin|jpg))$|(FBX/.*\.(fbx|png|jpg))$|License\.txt$|Preview\.jpg$|Color Guide\.png$|^[^/]*\.png$", re.I)
rows = json.load(open(listing))
todo = [r for r in rows if pat.search(r["path"]) and not any(x in r["path"] for x in ("/OBJ/", "/Blend/"))]
print("selected", len(todo), "of", len(rows))
for i, r in enumerate(todo):
    dst = os.path.join(outdir, r["path"])
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
        continue
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    for attempt in range(3):
        try:
            gdown.download(id=r["id"], output=dst, quiet=True)
            break
        except Exception as e:
            print("retry", r["path"], e); time.sleep(3)
    print(i, r["path"], os.path.getsize(dst) if os.path.exists(dst) else "FAIL", flush=True)
