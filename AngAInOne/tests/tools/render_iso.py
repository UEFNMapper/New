# Rendu isométrique de la map exportée (aperçu sans Studio).
# Usage : lune run tests/tools/ExportMap.luau map.json && python3 tests/tools/render_iso.py map.json map_iso.png 1.1  (nécessite Pillow)
import json, sys, math
from PIL import Image, ImageDraw, ImageFilter
parts = json.load(open(sys.argv[1]))
SKIP = {"SideGlass", "Rear", "Bottom", "Beam"}
S = float(sys.argv[3]) if len(sys.argv) > 3 else 1.1
c30, s30 = math.cos(math.radians(30)), math.sin(math.radians(30))
def proj(x, y, z):
    return ((x - z) * c30, (x + z) * s30 - y * 1.0)
# bornes
xs, ys = [], []
for x in (-545, 545):
    for z in (-425, 425):
        for y in (0, 200):
            a, b = proj(x, y, z); xs.append(a); ys.append(b)
minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
W, H = int((maxx - minx) * S) + 40, int((maxy - miny) * S) + 40
img = Image.new("RGB", (W, H), (22, 24, 32))
glow = Image.new("RGB", (W, H), (0, 0, 0))
d = ImageDraw.Draw(img, "RGBA"); g = ImageDraw.Draw(glow, "RGBA")
def px(p): return ((p[0] - minx) * S + 20, (p[1] - miny) * S + 20)
view = (1, 1, 1)  # direction vers la caméra (normalisée plus bas)
vn = math.sqrt(3); view = (1/vn, 1/vn, 1/vn)
faces = []
for p in parts:
    if p["n"] in SKIP or p["t"] >= 0.97: continue
    r = p["r"]; s = p["s"]; cx, cy, cz = p["p"]
    ax = (r[0], r[3], r[6]); ay = (r[1], r[4], r[7]); az = (r[2], r[5], r[8])
    h = (s[0]/2, s[1]/2, s[2]/2)
    def corner(i, j, k):
        return (cx + ax[0]*h[0]*i + ay[0]*h[1]*j + az[0]*h[2]*k,
                cy + ax[1]*h[0]*i + ay[1]*h[1]*j + az[1]*h[2]*k,
                cz + ax[2]*h[0]*i + ay[2]*h[1]*j + az[2]*h[2]*k)
    col = [int(v*255) for v in p["c"]]
    alpha = int(255*(1 - p["t"]))
    if p["m"] == "Glass": alpha = min(alpha, 70)
    if p["n"] == "Shroud": alpha = 90
    neon = p["m"] == "Neon"
    for axis, sign in ((ax,1),(ax,-1),(ay,1),(ay,-1),(az,1),(az,-1)):
        n = tuple(v*sign for v in axis)
        dot = n[0]*view[0] + n[1]*view[1] + n[2]*view[2]
        if dot <= 0.001: continue
        if axis is ax: quad = [corner(sign, j, k) for j, k in ((-1,-1),(1,-1),(1,1),(-1,1))]
        elif axis is ay: quad = [corner(i, sign, k) for i, k in ((-1,-1),(1,-1),(1,1),(-1,1))]
        else: quad = [corner(i, j, sign) for i, j in ((-1,-1),(1,-1),(1,1),(-1,1))]
        depth = sum(q[0] + q[2] + q[1]*0.8 for q in quad) / 4
        light = 0.45 + 0.55 * max(0, n[1]*0.8 + n[0]*0.35 + n[2]*0.15)
        fc = col if neon else [min(255, int(v*light)) for v in col]
        faces.append((depth, [px(proj(*q)) for q in quad], (*fc, alpha), neon))
faces.sort(key=lambda f: f[0])
for depth, poly, color, neon in faces:
    d.polygon(poly, fill=color)
    if neon: g.polygon(poly, fill=color)
glow = glow.filter(ImageFilter.GaussianBlur(6))
out = Image.blend(img, Image.eval(Image.composite(glow, img, glow.convert("L")), lambda v: v), 0.0)
from PIL import ImageChops
out = ImageChops.add(img, glow, scale=1.4)
out.save(sys.argv[2])
print("ok", W, H, len(faces))
