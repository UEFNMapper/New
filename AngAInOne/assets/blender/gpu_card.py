"""GpuCard — carte graphique triple ventilateur (couchée : ventilateurs vers +Z, équerre I/O côté -X,
connecteur PCIe vers -Y, bord supérieur (caloducs, 8-pin, RGB) vers +Y).
En jeu : pour la monter « comme dans un PC » (ventilateurs vers le bas), la retourner ; les rotors
__Spin tournent autour de leur axe local Y (= Z Blender), perpendiculaire à la carte."""
from hw_common import *

reset()
L, H = 110.0, 45.0
X0, X1 = -55.0, 55.0                # longueur du refroidisseur
FANS = (-33.5, 0.5, 34.5)           # centres des ventilateurs
FR = 14.6                           # rayon des ouïes
Z_PCB0, Z_PCB1 = 0.9, 1.3
Z_FIN0, Z_FIN1 = 2.2, 13.2
Z_SH0, Z_SH1, Z_TOP = 12.6, 17.6, 19.4

# ------------------------------------------------------------------ coque (shroud)
W, HH = 108.0, 44.0
cx = 0.5
outline = crect(W, HH, (1.5, 7.0, 7.0, 1.5), (cx, 0))
inner = crect(W - 3.6, HH - 3.6, (0.8, 5.8, 5.8, 0.8), (cx, 0))
shroud = loft([(outline, Z_SH0), (outline, Z_SH1), (inner, Z_TOP)])
cut = [rprism(crect(W - 2.0, HH - 2.0, (1.0, 6.2, 6.2, 1.0), (cx, 0)), Z_SH0 - 1, Z_SH1 - 0.1)]
for fx in FANS:
    cut.append(rcyl(FR, 20, (fx, 0, 16), verts=96))
# fenêtres anguleuses entre les ventilateurs : on y voit les ailettes
for a, b in zip(FANS[:-1], FANS[1:]):
    m = (a + b) / 2
    for sy in (-1, 1):
        par = [(m - 2.4, sy * 13.5), (m + 2.4, sy * 13.5), (m + 1.2, sy * 19.0), (m - 1.2, sy * 19.0)]
        cut.append(rprism(par, 10, 25))
# grande prise d'air en chevron côté +X
for k in range(4):
    x = 52.5 - k * 1.6
    cut.append(rprism([(x - 0.5, -12), (x + 0.5, -12), (x + 2.5, 0), (x + 0.5, 12), (x - 0.5, 12), (x + 1.5, 0)], 10, 25))
# rainures sculptées sur le dessus
for sy in (-1, 1):
    for fx in FANS:
        g = [(fx - 9, sy * 20.2), (fx + 9, sy * 20.2), (fx + 7.5, sy * 19.3), (fx - 7.5, sy * 19.3)]
        cut.append(rprism(g, Z_TOP - 0.35, Z_TOP + 1))
bool_op(shroud, cut)
bev(shroud, 0.12, 2, 30)
shade(shroud, 30)

# stators (moteur + 3 bras) sous chaque rotor, fixés à la coque
stat = []
for fx in FANS:
    stat.append(lathe([(0, 13.3), (4.2, 13.3), (4.2, 14.1), (3.9, 14.3), (0, 14.3)], 48, (fx, 0, 0)))
    for k in range(3):
        a = math.pi / 2 + 2 * math.pi * k / 3
        path = [((3.5 + t * 11.8) * math.cos(a + 0.35 * t * t), (3.5 + t * 11.8) * math.sin(a + 0.35 * t * t))
                for t in [i / 6 for i in range(7)]]
        s = ribbon([(fx + x, y) for x, y in path], 1.1, 13.3, 14.0)
        bev(s, 0.2, 1, 40)
        stat.append(s)
# bagues des ouïes (biseau intérieur)
for fx in FANS:
    stat.append(lathe([(FR - 0.05, Z_SH1 - 0.2), (FR + 0.9, Z_SH1 - 0.2), (FR + 0.9, Z_TOP - 0.15),
                       (FR + 0.4, Z_TOP + 0.25), (FR - 0.05, Z_TOP + 0.25)], 96, (fx, 0, 0), closed=True, angle=40))

# connecteurs 8-pin (boîtiers) sur le bord supérieur (+Y)
pw = []
for px in (22.0, 26.2):
    body = rbox((3.8, 2.4, 3.2), (px, 21.4, Z_PCB1 + 1.6), r=0.12)
    holes = [rbox((0.62, 3, 0.62), (px - 1.35 + i * 0.9, 22.0, Z_PCB1 + 0.95 + j * 1.1)) for i in range(4) for j in range(2)]
    bool_op(body, holes)
    latch = rbox((1.0, 1.2, 0.5), (px, 22.1, Z_PCB1 + 3.35), r=0.1)
    pw += [body, latch]
# intérieurs des ports vidéo (languettes plastique)
ports_y = (-14.5, -7.0, 0.5, 8.5)
for i, py in enumerate(ports_y):
    pw.append(rbox((3.2, 3.6 if i < 3 else 3.4, 0.45), (-54.3, py, 3.6), r=0.05))
shroud = merge([shroud] + stat + pw)
tag(shroud, "Shroud", "SmoothPlastic", GRAPHITE_0)

# ------------------------------------------------------------------ bloc d'ailettes
fins_src = None
mats = []
x = -49.6
fin_list = []
while x < 52.6:
    wave = 0.9 * math.sin(x * 0.28)
    yt = 19.8 + wave
    yb = 19.8 - wave
    prof = [(-yb, Z_FIN0), (yt, Z_FIN0), (yt, 4.5), (yt + 0.6, 5.5), (yt, 6.5), (yt, Z_FIN1 - 1.2),
            (yt - 1.2, Z_FIN1), (-yb + 1.2, Z_FIN1), (-yb, Z_FIN1 - 1.2), (-yb, 6.5), (-yb - 0.6, 5.5), (-yb, 4.5)]
    fin_list.append((x, prof))
    x += 0.82
fins = []
for x, prof in fin_list:
    fins.append(prism_x(prof, x - 0.07, x + 0.07))
fins = merge(fins)
tag(fins, "FinStack", "Metal", ALU_DARK)

# ------------------------------------------------------------------ caloducs cuivre (boucles en U au bord +Y)
pipes = []
for i, px in enumerate((-16.0, -12.4, -8.8, -5.2, -1.6)):
    lo, hi = 3.3 + (i % 2) * 0.4, 9.8 - (i % 2) * 0.9
    dx = 2.5 - i * 1.2
    pts = [(px - 18, 16.0, hi), (px - 2, 17.5, hi), (px, 20.2, hi), (px + dx * 0.3, 21.8, hi - 1.2),
           (px + dx * 0.5, 22.4, (hi + lo) / 2), (px + dx * 0.3, 21.8, lo + 1.2), (px, 20.2, lo),
           (px + 2, 17.5, lo), (px + 14, 12.0, lo)]
    pipes.append(pipe(pts, 0.62, 12, 5))
# bouts sertis visibles côté -Y
for i, px in enumerate((-14.0, -9.0, -4.0)):
    pipes.append(pipe([(px + 6, -12.0, 3.4), (px, -18.5, 3.4), (px - 0.5, -20.5, 3.4)], 0.62, 12, 5, cap=False))
    pipes.append(lathe([(0, 0), (0.62, 0), (0.62, 0.5), (0.3, 0.9), (0, 0.9)], 16, (px - 0.5, -20.5, 3.4),
                       (math.pi / 2, 0, 0)))
pipes = merge(pipes)
tag(pipes, "Heatpipes", "Metal", COPPER)

# ------------------------------------------------------------------ PCB + languette PCIe
pcb = rprism(crect(96.0, 42.5, 0.6, (-7.0, 0.0)), Z_PCB0, Z_PCB1)
tab = rprism([(-47.5, -21.0), (-11.0, -21.0), (-11.0, -23.6), (-11.6, -24.3), (-42.6, -24.3), (-42.6, -22.2),
              (-43.8, -22.2), (-43.8, -24.3), (-46.9, -24.3), (-47.5, -23.6)], Z_PCB0, Z_PCB1)
pcb = merge([pcb, tab])
weld(pcb, 1e-4)
# composants CMS visibles sous le radiateur (condensateurs, selfs) côté bord
smd = []
for k in range(14):
    smd.append(rbox((1.3, 0.8, 0.5), (-40 + k * 4.7, 19.6, Z_PCB1 + 0.25), r=0.08))
    smd.append(rbox((0.9, 0.6, 0.35), (-38.6 + k * 4.7, -19.4, Z_PCB1 + 0.18), r=0.06))
pcb = merge([pcb] + smd)
tag(pcb, "Pcb", "SmoothPlastic", PCB)

gold = []
for side_z in (Z_PCB1 + 0.02, Z_PCB0 - 0.02):
    for k in range(66):
        gx = -46.6 + k * 0.54
        if -44.0 < gx < -42.4:
            continue
        gold.append(rbox((0.34, 2.4, 0.04), (gx, -22.95, side_z)))
for px in (22.0, 26.2):  # broches visibles dans les 8-pin
    for i in range(4):
        for j in range(2):
            gold.append(rbox((0.28, 1.2, 0.28), (px - 1.35 + i * 0.9, 21.6, Z_PCB1 + 0.95 + j * 1.1)))
gold = merge(gold)
tag(gold, "Contacts", "Foil", GOLD)

# ------------------------------------------------------------------ backplate
bp = rprism(crect(106.5, 43.4, (1.2, 5.5, 5.5, 1.2), (0.0, 0.0)), 0.0, 0.55)
bev(bp, 0.1, 2, 30)
cut = []
for r_ in range(7):  # ajourage traversant (flow-through) : lames inclinées
    for c in range(5):
        x0 = 31.5 + c * 4.3 + (r_ % 2) * 0.0
        y0 = -13.5 + r_ * 4.5
        cut.append(rprism([(x0, y0), (x0 + 3.2, y0), (x0 + 3.9, y0 + 2.8), (x0 + 0.7, y0 + 2.8)], -1, 2))
for k in range(9):  # lignes gravées anguleuses
    x0 = -30 + k * 2.2
    cut.append(rprism([(x0, 21.7), (x0 + 0.5, 21.7), (x0 - 6.5, 8.0), (x0 - 7.0, 8.0)], -0.2, 0.12))
bool_op(bp, cut)
logo = text_mesh("A", 16, 0.25, (-12.0, -3.0, 0.05), (math.pi, 0, 0))
word = text_mesh("ANGAINONE", 3.2, 0.12, (-12.0, -14.0, 0.03), (math.pi, 0, 0))
tag(bp, "Backplate", "Metal", GRAPHITE_2)

# ------------------------------------------------------------------ équerre I/O + garnitures alu + vis + badges
XB = -56.2
bracket = rbox((0.4, 46.0, 19.6), (XB, 0.0, 9.8), r=0.08, seg=1)
holes = []
for i, py in enumerate(ports_y):  # DisplayPort ×3 (coin chanfreiné) + HDMI
    w = 5.4 if i < 3 else 5.0
    if i < 3:
        prof = [(py - w / 2, 2.8), (py + w / 2, 2.8), (py + w / 2, 4.3), (py + w / 2 - 0.6, 4.9), (py - w / 2, 4.9)]
    else:
        prof = [(py - w / 2 + 0.5, 2.8), (py + w / 2 - 0.5, 2.8), (py + w / 2, 3.4), (py + w / 2, 4.9), (py - w / 2, 4.9),
                (py - w / 2, 3.4)]
    holes.append(prism_x(prof, XB - 2, XB + 2))
# nid d'abeille de ventilation
for row in range(6):
    for col in range(13):
        yy = -18.5 + col * 3.1 + (row % 2) * 1.55
        zz = 7.6 + row * 1.9
        if yy > 19.5:
            continue
        holes.append(rcyl(0.95, 3, (XB, yy, zz), verts=6, rot=(0, math.pi / 2, 0)))
bool_op(bracket, holes)
fold = rbox((2.6, 0.4, 19.6), (XB - 1.1, 23.2, 9.8), r=0.06, seg=1)
bool_op(fold, [rbox((1.6, 2, 1.2), (XB - 1.8, 23.2, z)) for z in (5.0, 14.6)])
tongue = rbox((0.4, 2.4, 2.6), (XB, -24.2, 10.2), r=0.05, seg=1)
# coques métalliques des ports
shells = []
for i, py in enumerate(ports_y):
    s = rbox((3.6, 5.3 if i < 3 else 4.9, 1.95), (XB + 1.9, py, 3.85), r=0.1)
    bool_op(s, rbox((5, 4.9 if i < 3 else 4.5, 1.55), (XB + 1.0, py, 3.85)))
    shells.append(s)
# garnitures alu sculptées sur le dessus (lames anguleuses le long des bords)
trims = []
for sy in (-1, 1):
    for a, b in zip((X0 + 2,) + tuple((p + q) / 2 + 2.6 for p, q in zip(FANS[:-1], FANS[1:])),
                    tuple((p + q) / 2 - 2.6 for p, q in zip(FANS[:-1], FANS[1:])) + (X1 - 8,)):
        pts = [(a, sy * 20.9), (b, sy * 20.9), (b - 1.2, sy * 20.0), (a + 1.2, sy * 20.0)]
        t_ = rprism(pts, Z_TOP - 0.9, Z_TOP - 0.25)
        trims.append(t_)
trims.append(rprism([(X1 - 6.5, -14.0), (X1 - 1.4, -9.0), (X1 - 1.4, 9.0), (X1 - 6.5, 14.0), (X1 - 7.4, 13.2),
                     (X1 - 2.6, 8.6), (X1 - 2.6, -8.6), (X1 - 7.4, -13.2)], Z_SH1 - 0.6, Z_TOP - 0.3))
for t_ in trims:
    bev(t_, 0.08, 1, 30)
# badges des moyeux (fixes) avec « A »
badges, logos = [], []
for fx in FANS:
    badges.append(lathe([(0, 18.25), (3.3, 18.25), (3.4, 18.4), (3.25, 18.55), (0, 18.6)], 48, (fx, 0, 0)))
    logos.append(text_mesh("A", 3.6, 0.14, (fx, 0.2, 18.53)))
# vis de backplate
screws = []
for sx, sy in ((-50, -18), (-50, 18), (-20, -19), (-20, 19), (8, -19.5), (8, 19.5), (28, -18), (28, 18),
               (-28, -6), (-28, 6), (-16, -6), (-16, 6)):
    screws.append(screw(0.75, 0.3, (sx, sy, 0.02), (math.pi, 0, 0)))
alu = merge([bracket, fold, tongue, logo, word] + shells + trims + badges + screws)
tag(alu, "Alu", "Metal", ALU)

# ------------------------------------------------------------------ rotors (11 pales + bague)
for i, fx in enumerate(FANS):
    r = fan_rotor(FR - 0.35, 4.6, 11, 14.4, 18.2, sweep=0.5, ring=True, thick=0.12, camber=0.2)
    r.location = (fx, 0, 16.3)
    bpy.context.view_layer.update()
    tag(r, f"Fan{i + 1}", "SmoothPlastic", GRAPHITE_2, spin=True)

# ------------------------------------------------------------------ RGB : bande verte + accents roses
rgb = []
rgb.append(rprism([(-44, 22.05), (30, 22.05), (33, 22.05), (36.0, 21.2), (36.0, 21.25), (-44, 21.3)], 14.6, 15.4))
rgb.append(rprism([(-44.0, 21.25), (-44.0, 22.05), (-46.5, 22.05), (-47.3, 21.25)], 14.6, 15.4))
for fx in FANS:  # fine bague lumineuse autour de chaque badge
    rgb.append(lathe([(3.45, 18.3), (3.75, 18.3), (3.75, 18.5), (3.45, 18.5)], 64, (fx, 0, 0), closed=True))
tag(merge(rgb + logos), "Rgb", "Neon", "48BB78")
pink = []
for k in range(3):  # chevrons roses dans l'extrémité +X
    x = 52.5 - k * 1.6 + 0.2
    pink.append(rprism([(x - 0.15, -11), (x + 0.15, -11), (x + 2.0, 0), (x + 0.15, 11), (x - 0.15, 11), (x + 1.7, 0)],
                       Z_SH1 - 1.4, Z_SH1 - 1.0))
pink.append(rprism([(X0 + 3, -21.9), (X0 + 18, -21.9), (X0 + 17.4, -22.25), (X0 + 3, -22.25)], 14.8, 15.3))
tag(merge(pink), "Accent", "Neon", "ED64A6")

done("GpuCard", camera=(0.55, 1.5, 1.35))
qa_view("GpuCard_bottom", (0.6, -1.2, -1.2))
qa_view("GpuCard_io", (-1.6, 0.9, 0.6), zoom=2.2, target=(-50, 0, 8))
qa_view("GpuCard_top", (0.9, 0.6, 1.2), zoom=2.0, target=(0, 15, 12))
