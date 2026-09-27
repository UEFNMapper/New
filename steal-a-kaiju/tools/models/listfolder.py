import sys, json, gdown
url = sys.argv[1]; out = sys.argv[2]
files = gdown.download_folder(url=url, skip_download=True, quiet=True)
rows = [{"id": f.id, "path": f.path} for f in files]
json.dump(rows, open(out, "w"), indent=0)
print(out, len(rows))
for r in rows[:400]:
    print(r["path"])
