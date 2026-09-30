"""Psu — alimentation ATX modulaire 40 × 35 × 20 (L × P × H) : grille nid d'abeille sur ventilateur 120
(__Spin, axe Z = face du dessus), panneau modulaire (24-pin, 8-pin, SATA) côté -Y, prise IEC + interrupteur
+ grille arrière côté +Y, plaque signalétique en alu brossé côté +X, ouïes latérales, vis, patins."""
from hw_common import *

reset()
W, D, H = 40.0, 35.0, 20.0
FR = 15.6                               # rayon de l'ouïe du ventilateur
FC = (0.0, 1.0)                         # centre du ventilateur

# ------------------------------------------------------------------ caisson
case = rbox((W, D, H), (0, 0, H / 2), r=0.45, seg=3)
cut = [rcyl(FR + 0.3, 12, (FC[0], FC[1], H - 6 + 6), verts=96)]
# ouïes latérales (côté -X et +X, bas)
for sx in (-1, 1):
    for k in range(9):
        y = -12.0 + k * 3.0
        cut.append(prism_x(round_profile([(y - 0.45, 2.2), (y + 0.45, 2.2), (y + 0.45, 7.0), (y - 0.45, 7.0)], 0.4, 2),
                           sx * W / 2 - 0.6, sx * W / 2 + 0.6))
# renfoncement du panneau modulaire (-Y) et de la grille arrière (+Y)
cut.append(rbox((W - 3.0, 1.6, H - 3.0), (0, -D / 2, H / 2), r=0.3))
# nervures du dessus
for sx in (-1, 1):
    cut.append(rprism([(sx * 17.2 - 0.15, -14.5), (sx * 17.2 + 0.15, -14.5), (sx * 17.2 + 0.15, 14.5),
                       (sx * 17.2 - 0.15, 14.5)], H - 0.2, H + 1))
# grille arrière nid d'abeille (+Y), zone gauche
for row in range(7):
    for col in range(9):
        x = -18.0 + col * 2.2 + (row % 2) * 1.1
        z = 3.5 + row * 1.9
        if x > -1.0:
            continue
        cut.append(rcyl(0.95, 3, (x, D / 2, z), verts=6, rot=(math.pi / 2, 0, 0)))
bool_op(case, cut)
# patins (même couleur)
feet = [rbox((4.0, 4.0, 0.5), (sx * 15, sy * 13, -0.2), r=0.2, seg=2) for sx in (-1, 1) for sy in (-1, 1)]
tag(merge([case] + feet), "Case", "Metal", GRAPHITE_1)

# ------------------------------------------------------------------ grille nid d'abeille (dessus)
gr = rcyl(FR + 0.3, 0.35, (FC[0], FC[1], H - 0.3), verts=96)
hexes = []
r_hex, pitch = 1.05, 2.3
for row in range(-8, 9):
    for col in range(-8, 9):
        x = col * pitch + (row % 2) * pitch / 2
        y = row * pitch * 0.866
        if math.hypot(x, y) > FR - 0.7:
            continue
        hexes.append(rcyl(r_hex, 2, (FC[0] + x, FC[1] + y, H - 0.3), verts=6, rot=(0, 0, math.pi / 6)))
bool_op(gr, hexes)
rim = lathe([(FR - 0.3, H - 0.55), (FR + 0.35, H - 0.55), (FR + 0.35, H + 0.05), (FR - 0.1, H + 0.12),
             (FR - 0.3, H + 0.05)], 96, (FC[0], FC[1], 0), closed=True)
hub_cap = lathe([(0, H - 0.4), (3.2, H - 0.4), (3.3, H - 0.1), (3.0, H + 0.1), (0, H + 0.12)], 48, (FC[0], FC[1], 0))
tag(merge([gr, rim, hub_cap]), "Grille", "Metal", GRAPHITE_2)

# ------------------------------------------------------------------ ventilateur : stator + rotor
stat = [lathe([(0, H - 6.0), (4.0, H - 6.0), (4.0, H - 4.7), (0, H - 4.7)], 48, (FC[0], FC[1], 0))]
for k in range(3):
    a = math.pi / 6 + 2 * math.pi * k / 3
    stat.append(ribbon([(FC[0] + r * math.cos(a), FC[1] + r * math.sin(a)) for r in (3.5, 9.0, FR + 0.3)], 1.0,
                       H - 5.9, H - 5.2))
# boîtiers modulaires (plastique noir) sur le panneau -Y
YP = -D / 2 + 0.8
socks = []


def socket(cx, cz, cols, rows, pitch=1.1, label=None):
    w, h = cols * pitch + 0.5, rows * pitch + 0.5
    s = rbox((w, 1.6, h), (cx, YP - 0.4, cz), r=0.12, seg=2)
    holes = [rbox((0.72, 2.0, 0.72), (cx - (cols - 1) * pitch / 2 + i * pitch, YP - 1.2,
                                      cz - (rows - 1) * pitch / 2 + j * pitch)) for i in range(cols) for j in range(rows)]
    bool_op(s, holes)
    socks.append(s)
    return s


socket(-9.0, 13.0, 12, 2)                  # 24-pin carte mère
for i in range(3):
    socket(6.0 + i * 5.6, 13.0, 4, 2)      # 8-pin CPU / PCIe
for i in range(4):
    socket(-14.0 + i * 5.2, 5.8, 3, 2)     # périphériques / SATA
socket(9.5, 5.8, 6, 2)                     # 12VHPWR (approx.)
# interrupteur à bascule + prise IEC (+Y)
YB = D / 2
iec = rbox((6.0, 1.2, 4.6), (7.5, YB - 0.1, 9.0), r=0.3, seg=2)
bool_op(iec, prism_y([(5.4, 7.2), (9.6, 7.2), (9.6, 10.0), (8.9, 10.7), (6.1, 10.7), (5.4, 10.0)], YB - 0.2, YB + 1))
switch = rbox((3.0, 1.0, 4.0), (14.5, YB + 0.1, 9.0), r=0.25, seg=2)
rock = rbox((2.2, 0.8, 3.2), (14.5, YB + 0.55, 9.0), r=0.3, seg=2, rot=(0.22, 0, 0))
tag(merge(stat + socks + [iec, switch, rock]), "Plastics", "SmoothPlastic", GRAPHITE_0)

rot = fan_rotor(FR - 0.4, 4.2, 7, H - 4.6, H - 1.0, sweep=0.6, ring=True, thick=0.13)
rot.location.x += FC[0]; rot.location.y += FC[1]
tag(rot, "Rotor", "SmoothPlastic", GRAPHITE_2, spin=True)

# ------------------------------------------------------------------ plaque signalétique alu (+X) + étiquettes
XL = W / 2
plate = prism_x(crect(24.0, 9.0, 1.2, (2.0, 13.2)), XL - 0.1, XL + 0.35)
bev(plate, 0.08, 2, 30)
txt = []


def xtext(t, size, y, z, depth=0.12):
    # texte lisible depuis +X, collé sur la plaque
    o = text_mesh(t, size, depth, (0, 0, 0), (math.pi / 2, 0, math.pi / 2))
    return xf(o, (XL + 0.33, y, z))


txt.append(xtext("ANGAINONE", 1.7, 2.0, 15.0))
txt.append(xtext("1200W  80+ PLATINUM", 1.0, 2.0, 12.4))
txt.append(xtext("FULLY MODULAR", 0.8, 2.0, 10.6))
# repères du panneau modulaire (gravés en relief, alu)
for t, x, z in (("MB", -9.0, 16.0), ("CPU/PCIE", 11.6, 16.0), ("SATA/PERIF", -6.3, 3.0), ("12V-2x6", 9.5, 3.0)):
    o = text_mesh(t, 0.8, 0.08, (x, 0, z), (math.pi / 2, 0, 0))
    xf(o, (0, YP - 0.02 - 0.8 + 0.8, 0))
    txt.append(o)
tag(merge([plate] + txt), "Label", "Metal", ALU)

# ------------------------------------------------------------------ vis + broches IEC
nk = []
for sx in (-1, 1):
    for sz in (2.2, H - 2.2):
        nk.append(screw(0.55, 0.3, (sx * (W / 2 - 2.2), YB, sz), rot=(-math.pi / 2, 0, 0)))
        nk.append(screw(0.5, 0.25, (sx * W / 2, -D / 2 + 3.0 if sz < 5 else D / 2 - 3.0, sz),
                        rot=(0, sx * math.pi / 2, 0)))
for px, pz in ((6.4, 8.2), (8.6, 8.2), (7.5, 9.8)):
    nk.append(rbox((0.35, 1.2, 0.7), (px, YB - 0.1, pz)))
tag(merge(nk), "Screws", "Metal", NICKEL)

# ------------------------------------------------------------------ accents orange
acc = [lathe([(FR + 0.45, H - 0.08), (FR + 0.75, H - 0.08), (FR + 0.75, H + 0.04), (FR + 0.45, H + 0.04)], 96,
             (FC[0], FC[1], 0), closed=True)]
acc.append(text_mesh("A", 3.2, 0.12, (FC[0], FC[1] + 0.1, H + 0.08)))
a2 = text_mesh("A", 5.5, 0.16, (0, 0, 0), (math.pi / 2, 0, math.pi / 2))
acc.append(xf(a2, (XL + 0.33, -6.8, 13.2)))
acc.append(rbox((0.8, 0.3, 0.8), (18.0, YB + 0.05, 16.5), r=0.1))   # LED de mise sous tension
tag(merge(acc), "Accent", "Neon", "F6AD55")

done("Psu", camera=(1.3, -1.6, 1.3))
qa_view("Psu_back", (-0.9, 1.6, 0.7))
