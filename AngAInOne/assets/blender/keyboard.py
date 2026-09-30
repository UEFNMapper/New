"""Keyboard — clavier mécanique TKL (≈181 × 70 × 12 studs à l'échelle miniaturisée).

Châssis aluminium chanfreiné sur coque noire, plaque noire, 87 touches sculptées (profil Cherry :
hauteur/inclinaison par rangée, dessus creusés), légendes « shine-through » violettes, halo RGB par
touche, logo AngAInOne gravé, câble USB-C spiralé avec connecteur aviation.
Construit façade vers −Y puis tourné (façade exportée vers +Y Blender = −Z Roblox)."""
from room_common import *

reset()
U = 9.5                     # pas d'une touche (19,05 mm à 0,5 stud/mm)
MARGIN = 4.2
W = 18.25 * U + 2 * MARGIN  # 181.8
D = 6.5 * U + 2 * MARGIN    # 70.2
Z_PLATE = 5.0               # dessus de la plaque (fond du puits)
Z_CAP = 6.3                 # bas des touches
Z_RIM = 7.2                 # dessus du cadre alu

# --- disposition ANSI TKL : (légende, largeur en u, groupe) ; légende None = espace
A, M, R_, W_ = "alpha", "mod", "red", "white"
F = [("Esc", 1, R_), (None, 1)] + [(f"F{i}", 1, M if i in (1, 2, 3, 4, 9, 10, 11, 12) else A) for i in range(1, 5)] + \
    [(None, .5)] + [(f"F{i}", 1, A) for i in range(5, 9)] + [(None, .5)] + [(f"F{i}", 1, M) for i in range(9, 13)] + \
    [(None, .25), ("PrtSc", 1, M), ("ScrLk", 1, M), ("Pause", 1, M)]
R1 = [(c, 1, A) for c in "`1234567890-="] + [("Back", 2, M), (None, .25), ("Ins", 1, M), ("Home", 1, M), ("PgUp", 1, M)]
R2 = [("Tab", 1.5, M)] + [(c, 1, W_ if c == "W" else A) for c in "QWERTYUIOP[]"] + [("\\", 1.5, A), (None, .25),
                                                                                   ("Del", 1, M), ("End", 1, M), ("PgDn", 1, M)]
R3 = [("Caps", 1.75, M)] + [(c, 1, W_ if c in "ASD" else A) for c in "ASDFGHJKL;'"] + [("Enter", 2.25, R_)]
R4 = [("Shift", 2.25, M)] + [(c, 1, A) for c in "ZXCVBNM,./"] + [("Shift", 2.75, M), (None, 1.25), ("↑", 1, W_)]
R5 = [("Ctrl", 1.25, M), ("A", 1.25, R_), ("Alt", 1.25, M), ("AngaTV", 6.25, W_), ("Alt", 1.25, M), ("Fn", 1.25, M),
      ("≡", 1.25, M), ("Ctrl", 1.25, M), (None, .25), ("←", 1, W_), ("↓", 1, W_), ("→", 1, W_)]
# (rangée, y du centre en u depuis le haut, hauteur de touche, inclinaison °)
ROWS = [(F, 0.5, 5.0, 9), (R1, 2.0, 5.0, 9), (R2, 3.0, 4.5, 5), (R3, 4.0, 4.2, 0), (R4, 5.0, 4.4, -6), (R5, 6.0, 4.4, -8)]
DISH = 0.38

caps = {A: [], M: [], R_: [], W_: []}
glow, stems = [], []


def keycap(cx, cy, w, h, tilt, spacebar=False):
    bw, bd = w * U - 1.1, U - 1.1
    tw, td = bw - 2.7, bd - 3.1
    base = rounded_rect(bw, bd, 1.0, 2)
    top = rounded_rect(tw, td, 1.7, 2)
    tt = math.tan(math.radians(tilt))
    dy = 0.35  # dessus décalé vers l'arrière (profil Cherry)
    dish = DISH * (0.35 if spacebar else 1.0)
    verts, rings = [], []

    def ring(poly, zf):
        rings.append(list(range(len(verts), len(verts) + len(poly))))
        verts.extend((cx + x, cy + y, zf(x, y)) for x, y in poly)

    ring(base, lambda x, y: Z_CAP)
    mid = [(bx + (tx - bx) * 0.3, by + (ty + dy - by) * 0.3) for (bx, by), (tx, ty) in zip(base, top)]
    ring(mid, lambda x, y: Z_CAP + h * 0.5 + tt * y * 0.5)
    ring([(x, y + dy) for x, y in top], lambda x, y: Z_CAP + h - 0.32 + tt * (y - dy))
    for s in (0.9, 0.62, 0.3):
        poly = [(x * s, y * s + dy) for x, y in top]
        ring(poly, lambda x, y, s=s: Z_CAP + h + tt * (y - dy) - dish * (1 - s * s) - (0.0 if s < 0.9 else 0.02))
    faces = []
    for ra, rb in zip(rings, rings[1:]):
        n = len(ra)
        faces += [(ra[i], ra[(i + 1) % n], rb[(i + 1) % n], rb[i]) for i in range(n)]
    c = len(verts)
    verts.append((cx, cy + dy, Z_CAP + h - dish))
    last = rings[-1]
    faces += [(last[i], last[(i + 1) % len(last)], c) for i in range(len(last))]
    o = mesh("Cap", verts, faces, angle=48)
    return o, (cx, cy + dy, Z_CAP + h - dish)


x0 = -W / 2 + MARGIN
y_top = D / 2 - MARGIN
for keys, yu, h, tilt in ROWS:
    x = x0
    cy = y_top - yu * U
    for k in keys:
        label, w = k[0], k[1]
        if label is None:
            x += w * U
            continue
        group = k[2]
        cx = x + w * U / 2
        cap, top_c = keycap(cx, cy, w, h, tilt, spacebar=(w > 6))
        caps[group].append(cap)
        # halo RGB : plaquette néon sous la touche, qui déborde entre les touches
        glow.append(rbox((w * U - 0.55, U - 0.55, 0.2), (cx, cy, Z_PLATE + 0.1), r=0.0))
        # tige + boîtier de switch (visibles en vue rasante)
        stems.append(rbox((5.6, 5.6, Z_CAP - Z_PLATE + 0.2), (cx, cy, (Z_PLATE + Z_CAP) / 2), r=0.0))
        # légende : texte fin qui affleure au fond du creux, incliné comme la touche
        single = len(label) == 1
        size = 3.3 if single else (2.35 if label.startswith("F") and len(label) <= 3 else 1.85)
        if label == "AngaTV":
            size = 3.0
        if label in "←↑→↓≡":
            size = 3.6
        t = text_mesh(label, size, 0.6, res=1)
        xf(t, loc=(0, 0, -0.48))
        xf(t, rot=(math.radians(tilt), 0, 0))
        xf(t, loc=top_c)
        glow.append(t)
        x += w * U

# LED d'état (Caps/Scroll/Num) au-dessus du pavé de navigation
for i in range(3):
    glow.append(cyl(0.55, 0.5, (W / 2 - MARGIN - 1.5 * U + (i - 1) * 3.2, D / 2 - 2.0, Z_RIM - 0.3), verts=12))

for g, (nm, col) in {A: ("Caps", "22252E"), R_: ("CapsRed", "E53E3E"), W_: ("CapsWhite", "F2F2F5")}.items():
    tagj(caps[g], nm, "SmoothPlastic", col)

# --- châssis aluminium : bord supérieur chanfreiné (effet diamant), angles arrondis
def rr3(w, d, r, z, n=6):
    return [(x, y, z) for x, y in rounded_rect(w, d, r, n)]


frame = loft([rr3(W - 1.0, D - 1.0, 5.5, 1.6), rr3(W, D, 6.0, 2.2), rr3(W, D, 6.0, Z_RIM - 1.3),
              rr3(W - 2.6, D - 2.6, 4.7, Z_RIM)], "Frame", angle=30)
well = extrude(rounded_rect(18.25 * U + 1.4, 6.5 * U + 1.4, 1.6, 6), Z_PLATE, 20, "Well")
boolean_diff(frame, well)
bevel_all(frame, 0.28, 2, angle=30)
# logo AngAInOne gravé (après le biseau, pour des bords de gravure nets)
logo = text_mesh("AngAInOne", 2.6, 1.0, res=3)
xf(logo, rot=(math.pi / 2, 0, 0))          # texte debout sur la face avant
xf(logo, loc=(W / 2 - 24, -D / 2 + 0.45, 4.1))
boolean_diff(frame, logo)

# --- coque inférieure noire + plaque + boîtiers de switch
shell = loft([rr3(W - 2.4, D - 2.4, 5.0, 0.0), rr3(W - 1.2, D - 1.2, 5.4, 0.6), rr3(W - 1.2, D - 1.2, 5.4, 1.75)],
             "Shell", angle=40)
plate = extrude(rounded_rect(18.25 * U + 1.4, 6.5 * U + 1.4, 1.6, 6), Z_PLATE - 1.0, Z_PLATE, "Plate")

# --- câble USB-C spiralé avec connecteur « aviation » (à l'arrière, vers +Y en modélisation)
px = -W / 2 + 46
yb = D / 2
boot = rbox((7.0, 7.5, 3.4), (px, yb + 3.4, 3.8), r=1.2, seg=3)
plug_metal = [rbox((4.2, 1.6, 1.7), (px, yb + 0.3, 3.8), r=0.5, seg=2)]
# connecteur aviation (alu) : fût moletté + bague
av_y = yb + 16
av = cyl(2.5, 9.0, (px, av_y, 3.2), rot=(-math.pi / 2, 0, 0), verts=32, bev=0.35)
plug_metal.append(av)
for i in range(6):
    plug_metal.append(torus(2.55, 0.28, (px, av_y + 1.8 + i * 0.9, 3.2), rot=(math.pi / 2, 0, 0), maj=32, mnr=6))
plug_metal.append(cyl(2.1, 1.2, (px, av_y + 9.0, 3.2), rot=(-math.pi / 2, 0, 0), verts=24, bev=0.3))
cable = [sweep(catmull([(px, yb + 7, 3.8), (px, yb + 11, 3.4), (px, av_y, 3.2)], 6), 1.05, 12, name="C1",
               braid=0.07, braid_freq=2.5)]
# spirale couchée sur le bureau (axe Y)
coil = []
cy0, cy1, turns, rc = av_y + 10.5, av_y + 36, 13, 2.35
n = turns * 18
for i in range(n + 1):
    t = i / n
    a = TAU * turns * t
    coil.append((px + rc * math.sin(a), cy0 + (cy1 - cy0) * t, 3.2 - rc * math.cos(a) + rc))
coil = [(px, av_y + 9.6, 3.2)] + coil[1:]
cable.append(sweep(coil, 0.85, 10, name="Coil", braid=0.06, braid_freq=3.0))
cable.append(sweep(catmull([coil[-1], (px + 1, cy1 + 5, 1.2), (px - 6, cy1 + 16, 1.0), (px - 20, cy1 + 24, 1.0)], 8),
                   1.0, 12, name="C2", braid=0.07, braid_freq=2.5))
tagj(cable, "Cable", "Fabric", "22252E")

tagj([frame] + plug_metal, "Frame", "Metal", "B8BEC8")
tagj([shell, plate, boot] + stems + caps[M], "Body", "SmoothPlastic", "16181E")
tagj(glow, "Glow", "Neon", "8B7CFF")

done("Keyboard", direction=(0.5, -1.0, 0.7), lens=55)
