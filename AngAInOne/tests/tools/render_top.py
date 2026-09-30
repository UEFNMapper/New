# Rendu vu de dessus de la map exportée (vérifier la disposition).
# Usage : lune run tests/tools/ExportMap.luau map.json && python3 tests/tools/render_top.py map.json map_top.png  (nécessite Pillow)
import json, sys, math
from PIL import Image, ImageDraw, ImageFont
parts = json.load(open(sys.argv[1]))
S = 1.6
MINX, MAXX, MINZ, MAXZ = -545, 545, -425, 425
W, H = int((MAXX-MINX)*S), int((MAXZ-MINZ)*S)
img = Image.new("RGB", (W, H), (10, 10, 14))
d = ImageDraw.Draw(img, "RGBA")
def px(x, z): return ((x-MINX)*S, (z-MINZ)*S)
def top(p): 
    r = p["r"]; s = p["s"]
    ey = abs(r[3])*s[0] + abs(r[4])*s[1] + abs(r[5])*s[2]
    return p["p"][1] + ey/2
parts.sort(key=top)
maxy = float(sys.argv[3]) if len(sys.argv) > 3 else 1e9
for p in parts:
    if p["t"] >= 0.97: continue
    if p["n"] in ("SideGlass",): continue
    if top(p) - 0.0 > maxy and p["p"][1] > maxy: continue
    r = p["r"]; s = p["s"]; x, y, z = p["p"]
    # axes monde des axes locaux X et Z (colonnes de la matrice)
    ax = (r[0], r[6]); az = (r[2], r[8]); ay = (r[1], r[7])
    hx, hy, hz = s[0]/2, s[1]/2, s[2]/2
    # projection de l'OBB sur XZ : enveloppe des 8 coins
    pts = []
    for sx in (-1,1):
        for sy in (-1,1):
            for sz in (-1,1):
                wx = x + ax[0]*hx*sx + ay[0]*hy*sy + az[0]*hz*sz
                wz = z + ax[1]*hx*sx + ay[1]*hy*sy + az[1]*hz*sz
                pts.append((wx, wz))
    # enveloppe convexe
    pts = sorted(set((round(a,3), round(b,3)) for a,b in pts))
    def cross(o,a,b): return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lower=[];upper=[]
    for q in pts:
        while len(lower)>=2 and cross(lower[-2],lower[-1],q)<=0: lower.pop()
        lower.append(q)
    for q in reversed(pts):
        while len(upper)>=2 and cross(upper[-2],upper[-1],q)<=0: upper.pop()
        upper.append(q)
    hull = lower[:-1]+upper[:-1]
    c = p["c"]; col = [int(v*255) for v in c]
    shade = min(1.0, 0.55 + top(p)/250)
    if p["m"] != "Neon": col = [int(v*shade) for v in col]
    alpha = int(255*(1-p["t"]))
    if p["m"] == "Glass": alpha = min(alpha, 110)
    poly = [px(a,b) for a,b in hull]
    if len(poly) >= 3:
        d.polygon(poly, fill=(*col, alpha), outline=(0,0,0,60) if p["col"] else None)
img.save(sys.argv[2])
print("ok", W, H)
