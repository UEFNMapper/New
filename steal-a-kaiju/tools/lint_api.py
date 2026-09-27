"""Vérifie que chaque méthode Roblox appelée (`:Nom(`) existe dans l'API officielle
ou dans le code du projet (méthodes définies par nos modules)."""
import json, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parent.parent
api = json.load(open(root / "tests/sim/api.json"))
known = set()
for c in api.values():
    known.update(c["methods"])
src = root / "src"
ours = set()
for f in src.rglob("*.luau"):
    t = f.read_text()
    ours.update(re.findall(r"function\s+[\w\.]+[:\.](\w+)\s*\(", t))
    ours.update(re.findall(r"(\w+)\s*=\s*function", t))
# méthodes des types de données (Vector3, CFrame, Color3, Signal…) et de la lib standard
datatype = {"Lerp","Dot","Cross","ToHex","ToEulerAnglesYXZ","ToObjectSpace","ToWorldSpace","PointToObjectSpace","PointToWorldSpace","VectorToWorldSpace","VectorToObjectSpace","GetComponents","Inverse","FuzzyEq","Connect","Once","Wait","Disconnect","Fire","NextNumber","NextInteger","Clone","Max","Min","Abs","Floor","Ceil","Sign","format","sub","upper","lower","gsub","match","find","rep","reverse","byte","split","gmatch","len","ToHSV","GetCurrentPage","SetAsync","GetSortedAsync","GetAsync","UpdateAsync","RemoveAsync","IncrementAsync","StartSessionAsync","Reconcile","EndSession","AddUserId","IsActive","Save","Open","Close","Toggle","Set","SetEgg","SetSilhouette","Point","Hide","Destroy","_update","_frame","_replace","Loop","Play"}
bad = {}
for f in src.rglob("*.luau"):
    if "Vendor" in f.parts:
        continue
    for n, line in enumerate(f.read_text().splitlines(), 1):
        code = line.split("--")[0]
        for m in re.findall(r":(\w+)\s*\(", code):
            if m not in known and m not in ours and m not in datatype:
                bad.setdefault(m, []).append(f"{f.relative_to(root)}:{n}")
for m, where in sorted(bad.items()):
    print(f"méthode inconnue :{m}()  ->  {', '.join(where[:3])}")
print("api ok" if not bad else f"{len(bad)} méthode(s) à vérifier")
sys.exit(1 if bad else 0)
