# Rendu isométrique de la map exportée (aperçu sans Studio).
# Usage : lune run tests/tools/ExportMap.luau map.json && python3 tests/tools/render_iso.py map.json map_iso.png 1.1  (nécessite Pillow)
# Options (gros plan sur un composant) :
#   --center x,y,z --radius r   cadre la vue sur une sphère (image de --size pixels)
#   --az 45 --el 35             azimut / élévation de la caméra (degrés ; 45/35 = vue d'origine)
#   --maxy y                    masque les pièces dont le centre est au-dessus de y (plafonds, caches)
#   --hide Nom,Nom              masque des pièces par nom
#   --ghost Nom,Nom             rend des pièces presque transparentes (défaut : cache du PSU)
# Les cylindres (axe X local), boules et coins (WedgePart) sont dessinés avec leur vraie forme.
import json, sys, math, argparse
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("out")
ap.add_argument("scale", nargs="?", type=float, default=1.1)
ap.add_argument("--center", default=None)
ap.add_argument("--radius", type=float, default=80)
ap.add_argument("--size", type=int, default=1400)
ap.add_argument("--az", type=float, default=45)
ap.add_argument("--el", type=float, default=35.26)
ap.add_argument("--maxy", type=float, default=1e9)
ap.add_argument("--hide", default="")
ap.add_argument("--ghost", default="PsuShroud,ShroudLip,ShroudRib")  # pièces rendues très transparentes (plafonds)
args = ap.parse_args()

parts = json.load(open(args.src))
FLOOR = {"Motherboard": -2e6, "TraceX": -1e6, "TraceZ": -1e6}  # le sol d'abord (tri du peintre)
GHOST = set(filter(None, args.ghost.split(",")))
SKIP = {"SideGlass", "Rear", "Bottom", "Beam"} | set(filter(None, args.hide.split(",")))

az, el = math.radians(args.az), math.radians(args.el)
V = (math.cos(el) * math.cos(az), math.sin(el), math.cos(el) * math.sin(az))  # vers la caméra
rn = math.hypot(V[2], V[0]); R = (V[2] / rn, 0.0, -V[0] / rn)                  # droite écran
U = (R[1]*V[2] - R[2]*V[1], R[2]*V[0] - R[0]*V[2], R[0]*V[1] - R[1]*V[0])     # bas écran
LIGHT = (0.35, 0.85, 0.4); ln = math.sqrt(sum(v*v for v in LIGHT)); LIGHT = tuple(v/ln for v in LIGHT)
def dot(a, b): return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
def proj(q): return (dot(q, R), dot(q, U))

center = tuple(float(v) for v in args.center.split(",")) if args.center else None
if center:
    cx0, cy0 = proj(center); rad = args.radius
    minx, maxx, miny, maxy = cx0 - rad, cx0 + rad, cy0 - rad, cy0 + rad
    S = args.size / (2 * rad); pad = 0
else:
    xs, ys = [], []
    for x in (-545, 545):
        for z in (-425, 425):
            for y in (0, 200):
                a, b = proj((x, y, z)); xs.append(a); ys.append(b)
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    S = args.scale * 1.2; pad = 20
W, H = int((maxx - minx) * S) + 2 * pad, int((maxy - miny) * S) + 2 * pad
img = Image.new("RGB", (W, H), (22, 24, 32))
glow = Image.new("RGB", (W, H), (0, 0, 0))
d = ImageDraw.Draw(img, "RGBA"); g = ImageDraw.Draw(glow, "RGBA")
def px(q):
    a, b = proj(q)
    return ((a - minx) * S + pad, (b - miny) * S + pad)

def local_faces(shape, h):
    """Faces (normale locale, sommets locaux) d'une pièce de demi-taille h."""
    hx, hy, hz = h
    if shape == "Cylinder":
        n = 16; r = min(hy, hz); ring = []
        for i in range(n):
            a = 2 * math.pi * i / n
            ring.append((math.cos(a), math.sin(a)))
        faces = [((1, 0, 0), [(hx, r*c, r*s) for c, s in ring]),
                 ((-1, 0, 0), [(-hx, r*c, r*s) for c, s in reversed(ring)])]
        for i in range(n):
            (c0, s0), (c1, s1) = ring[i], ring[(i + 1) % n]
            cm, sm = (c0 + c1) / 2, (s0 + s1) / 2
            faces.append(((0, cm, sm), [(-hx, r*c0, r*s0), (hx, r*c0, r*s0), (hx, r*c1, r*s1), (-hx, r*c1, r*s1)]))
        return faces
    if shape == "Ball":
        r = min(h); faces = []; la, lo = 6, 10
        for i in range(la):
            t0, t1 = math.pi * i / la - math.pi/2, math.pi * (i + 1) / la - math.pi/2
            for j in range(lo):
                p0, p1 = 2*math.pi*j/lo, 2*math.pi*(j+1)/lo
                pts = [(math.cos(t)*math.cos(p), math.sin(t), math.cos(t)*math.sin(p)) for t, p in ((t0,p0),(t0,p1),(t1,p1),(t1,p0))]
                nm = tuple(sum(q[k] for q in pts)/4 for k in range(3))
                faces.append((nm, [(q[0]*r, q[1]*r, q[2]*r) for q in pts]))
        return faces
    if shape == "Wedge":
        # Coin Roblox : face arrière (+Z) pleine, pente montant de l'avant (-Z) vers l'arrière.
        a, b, c = (-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz)
        a2, b2, c2 = (hx, -hy, -hz), (hx, -hy, hz), (hx, hy, hz)
        sl = (0, 2*hz, -2*hy); sn = math.hypot(sl[1], sl[2]) or 1
        return [((-1, 0, 0), [a, b, c]), ((1, 0, 0), [a2, c2, b2]),
                ((0, -1, 0), [a, a2, b2, b]), ((0, 0, 1), [b, b2, c2, c]),
                ((0, sl[1]/sn, sl[2]/sn), [a, c, c2, a2])]
    faces = []
    for ax in range(3):
        for sg in (1, -1):
            nrm = [0, 0, 0]; nrm[ax] = sg
            o1, o2 = [k for k in range(3) if k != ax]
            quad = []
            for u, v in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                q = [0, 0, 0]; q[ax] = sg * h[ax]; q[o1] = u * h[o1]; q[o2] = v * h[o2]
                quad.append(tuple(q))
            faces.append((tuple(nrm), quad))
    return faces

TILE = args.radius / 18 if center else 45  # grandes faces découpées : tri du peintre plus juste
def lerp(a, b, t): return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))
def split(q):
    if len(q) != 4: return [q]
    nu = max(1, min(40, int(math.dist(q[0], q[1]) / TILE)))
    nv = max(1, min(40, int(math.dist(q[1], q[2]) / TILE)))
    if nu == 1 and nv == 1: return [q]
    out = []
    for i in range(nu):
        for j in range(nv):
            def at(u, v): return lerp(lerp(q[0], q[1], u), lerp(q[3], q[2], u), v)
            u0, u1, v0, v1 = i / nu, (i + 1) / nu, j / nv, (j + 1) / nv
            out.append([at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)])
    return out

faces = []
for p in parts:
    if p["n"] in SKIP or p["t"] >= 0.97 or p["p"][1] > args.maxy: continue
    r = p["r"]; s = p["s"]; cx, cy, cz = p["p"]
    ax = (r[0], r[3], r[6]); ay = (r[1], r[4], r[7]); az_ = (r[2], r[5], r[8])
    h = (s[0]/2, s[1]/2, s[2]/2)
    if center:
        ext = [abs(ax[k])*h[0] + abs(ay[k])*h[1] + abs(az_[k])*h[2] for k in range(3)]
        if any(abs(p["p"][k] - center[k]) - ext[k] > args.radius * 1.2 for k in range(3)): continue
    def world(q): return (cx + ax[0]*q[0] + ay[0]*q[1] + az_[0]*q[2],
                          cy + ax[1]*q[0] + ay[1]*q[1] + az_[1]*q[2],
                          cz + ax[2]*q[0] + ay[2]*q[1] + az_[2]*q[2])
    col = [int(v*255) for v in p["c"]]
    alpha = int(255*(1 - p["t"]))
    if p["m"] == "Glass": alpha = min(alpha, 80)
    if p["m"] == "ForceField": alpha = min(alpha, 110)
    if p["n"] in GHOST: alpha = min(alpha, 60)
    neon = p["m"] == "Neon"
    shape = p.get("sh", "Block")
    for nl, quad in local_faces(shape, h):
        n = (ax[0]*nl[0] + ay[0]*nl[1] + az_[0]*nl[2], ax[1]*nl[0] + ay[1]*nl[1] + az_[1]*nl[2], ax[2]*nl[0] + ay[2]*nl[1] + az_[2]*nl[2])
        nn = math.sqrt(dot(n, n)) or 1; n = (n[0]/nn, n[1]/nn, n[2]/nn)
        if dot(n, V) <= 0.001: continue
        wq = [world(q) for q in quad]
        light = 0.38 + 0.62 * max(0, dot(n, LIGHT))
        if p["m"] == "Metal" or p["m"] == "DiamondPlate": light = min(1.15, light + 0.08 * max(0, dot(n, V)))
        fc = col if neon else [min(255, int(v*light)) for v in col]
        for tile in split(wq):
            depth = sum(dot(q, V) for q in tile) / len(tile) + FLOOR.get(p["n"], 0)
            faces.append((depth, [px(q) for q in tile], (*fc, alpha), neon))
faces.sort(key=lambda f: f[0])
for depth, poly, color, neon in faces:
    d.polygon(poly, fill=color)
    if neon: g.polygon(poly, fill=color)
glow = glow.filter(ImageFilter.GaussianBlur(max(2, min(7, int(6 * S)))))
out = ImageChops.add(img, glow, scale=1.4)
out.save(args.out)
print("ok", W, H, len(faces))
