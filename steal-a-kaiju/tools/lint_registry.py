"""Vérifie que chaque appel Registry.Service.Methode(...) existe vraiment."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parent.parent / "src" / "server"
services = {}
for f in (root / "Services").glob("*.luau"):
    name = f.stem
    src = f.read_text()
    defined = set(re.findall(r"^function %s[.:](\w+)" % name, src, re.M))
    defined |= set(re.findall(r"^%s\.(\w+)\s*=" % name, src, re.M))
    services[name] = defined
errors = 0
for f in root.rglob("*.luau"):
    for n, line in enumerate(f.read_text().splitlines(), 1):
        for svc, meth in re.findall(r"Registry\.(\w+)\.(\w+)", line):
            if svc not in services:
                print(f"{f.relative_to(root)}:{n}: service inconnu {svc}"); errors += 1
            elif meth not in services[svc]:
                print(f"{f.relative_to(root)}:{n}: {svc}.{meth} n'existe pas"); errors += 1
print("registry ok" if errors == 0 else f"{errors} erreur(s)")
sys.exit(1 if errors else 0)
