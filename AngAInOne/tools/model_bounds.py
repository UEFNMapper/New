"""Boîtes englobantes des modèles 3D : pour chaque assets/models/*.glb, la boîte de chaque noeud-maillage
(repère du fichier = axes Roblox), la boîte globale et le nombre de triangles.
Sortie : assets/models/bounds.json, lu par tests/lib/FakeModels.luau pour simuler les modèles importés
dans les tests Lune (placement, échelle, orientation) sans Roblox.
Usage : python3 tools/model_bounds.py   (depuis AngAInOne, après avoir régénéré un .glb)"""
import json, math, os, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")
OUT = os.path.join(MODELS, "bounds.json")

def mat_identity(): return [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
def mat_mul(a, b):
    return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def mat_from_node(n):
    if "matrix" in n:
        m = n["matrix"]  # column-major
        return [[m[c*4+r] for c in range(4)] for r in range(4)]
    t = n.get("translation", [0,0,0]); q = n.get("rotation", [0,0,0,1]); s = n.get("scale", [1,1,1])
    x,y,z,w = q
    R = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
         [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
         [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
    M = mat_identity()
    for i in range(3):
        for j in range(3):
            M[i][j] = R[i][j]*s[j]
        M[i][3] = t[i]
    return M
def apply(M, p):
    return [M[i][0]*p[0]+M[i][1]*p[1]+M[i][2]*p[2]+M[i][3] for i in range(3)]

def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67
    off = 12; gltf = None; binchunk = None
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off); off += 8
        chunk = data[off:off+clen]; off += clen
        if ctype == 0x4E4F534A: gltf = json.loads(chunk.decode())
        elif ctype == 0x004E4942: binchunk = chunk
    return gltf, binchunk

def accessor_minmax(gltf, binchunk, idx):
    acc = gltf["accessors"][idx]
    if "min" in acc and "max" in acc: return acc["min"], acc["max"], acc["count"]
    bv = gltf["bufferViews"][acc["bufferView"]]
    stride = bv.get("byteStride", 12)
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    mn = [math.inf]*3; mx = [-math.inf]*3
    for i in range(acc["count"]):
        x,y,z = struct.unpack_from("<fff", binchunk, base + i*stride)
        for k,v in enumerate((x,y,z)): mn[k]=min(mn[k],v); mx[k]=max(mx[k],v)
    return mn, mx, acc["count"]

def tri_count(gltf, prim):
    if "indices" in prim: n = gltf["accessors"][prim["indices"]]["count"]
    else: n = gltf["accessors"][prim["attributes"]["POSITION"]]["count"]
    return n // 3

def walk(gltf, binchunk, node_idx, parent_M, out):
    n = gltf["nodes"][node_idx]
    M = mat_mul(parent_M, mat_from_node(n))
    if "mesh" in n:
        mesh = gltf["meshes"][n["mesh"]]
        mn = [math.inf]*3; mx = [-math.inf]*3; tris = 0
        for prim in mesh["primitives"]:
            lmn, lmx, _ = accessor_minmax(gltf, binchunk, prim["attributes"]["POSITION"])
            for cx in (lmn[0], lmx[0]):
                for cy in (lmn[1], lmx[1]):
                    for cz in (lmn[2], lmx[2]):
                        p = apply(M, [cx,cy,cz])
                        for k in range(3): mn[k]=min(mn[k],p[k]); mx[k]=max(mx[k],p[k])
            tris += tri_count(gltf, prim)
        out.append({"name": n.get("name", mesh.get("name", "?")), "min": [round(v,3) for v in mn], "max": [round(v,3) for v in mx], "tris": tris})
    for c in n.get("children", []): walk(gltf, binchunk, c, M, out)

result = {}
for f in sorted(os.listdir(MODELS)):
    if not f.endswith(".glb"): continue
    gltf, binchunk = read_glb(os.path.join(MODELS, f))
    parts = []
    scene = gltf["scenes"][gltf.get("scene", 0)]
    for root in scene["nodes"]: walk(gltf, binchunk, root, mat_identity(), parts)
    mn = [min(p["min"][k] for p in parts) for k in range(3)]
    mx = [max(p["max"][k] for p in parts) for k in range(3)]
    result[f[:-4]] = {"min": [round(v,3) for v in mn], "max": [round(v,3) for v in mx],
                      "size": [round(mx[k]-mn[k],3) for k in range(3)],
                      "tris": sum(p["tris"] for p in parts), "parts": parts}
json.dump(result, open(OUT, "w"), indent=0, sort_keys=True)
print(f"{len(result)} modèles → {os.path.relpath(OUT, ROOT)}")
if "--list" in sys.argv:
    for k, v in result.items():
        print(f"{k:16s} {v['size'][0]:7.2f} x {v['size'][1]:7.2f} x {v['size'][2]:7.2f}  min y {v['min'][1]:7.2f}  pièces {len(v['parts']):2d}  tris {v['tris']:6d}")
