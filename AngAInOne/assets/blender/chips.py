"""Puces : CpuChip (processeur avec IHS gravé), CpuSocket (socket LGA : cadre, plaque de maintien, levier,
champ de broches), NpuChip (puce IA futuriste à circuits lumineux). python3 chips.py [Nom…]"""
import sys
from hw_common import *

SUBSTRATE = "2F5D46"


def cpu_chip():
    reset()
    S, TS = 30.0, 0.9                                  # substrat
    sub = rbox((S, S, TS), (0, 0, TS / 2 + 0.05), r=0.12, seg=2)
    bool_op(sub, [rbox((1.2, 2.4, 3), (sx * S / 2, 5.0, 0)) for sx in (-1, 1)])   # encoches de détrompage
    smd = []
    for i in range(12):                                # condensateurs CMS autour de l'IHS
        for side in (-1, 1):
            smd.append(rbox((0.9, 0.5, 0.4), (-9.9 + i * 1.8, side * 13.6, TS + 0.25), r=0.05, seg=1))
    tag(merge([sub]), "Substrate", "SmoothPlastic", SUBSTRATE)
    # IHS nickelé : jupe + plateau chanfreiné, gravures (texte + lignes)
    skirt = rprism([(-12, -10.5), (-10.5, -12), (10.5, -12), (12, -10.5), (12, -3), (12.8, -2), (12.8, 2), (12, 3),
                    (12, 10.5), (10.5, 12), (-10.5, 12), (-12, 10.5), (-12, 3), (-12.8, 2), (-12.8, -2), (-12, -3)],
                   TS + 0.05, TS + 0.6)
    bev(skirt, 0.1, 2, 30)
    top = loft([(crect(21.5, 21.5, 1.6), TS + 0.5), (crect(21.5, 21.5, 1.6), TS + 1.75), (crect(20.3, 20.3, 1.1), TS + 2.1)])
    Z = TS + 2.1
    eng = [text_mesh("ANGAINONE", 2.3, 0.3, (0, 5.2, Z - 0.1)),
           text_mesh("CORE A9 9990X", 1.5, 0.3, (0, 1.6, Z - 0.1)),
           text_mesh("24C/48T  5.8GHZ", 1.2, 0.3, (0, -1.2, Z - 0.1)),
           text_mesh("X4A71B0  2026", 1.0, 0.3, (0, -3.6, Z - 0.1)),
           rbox((16.0, 0.18, 0.3), (0, -5.4, Z)), rbox((16.0, 0.18, 0.3), (0, 7.6, Z)),
           rcyl(1.2, 0.3, (-7.2, -7.3, Z), verts=24)]
    bool_op(top, eng)
    tag(merge([skirt, top]), "Ihs", "Metal", NICKEL)
    tag(merge(smd), "Smd", "SmoothPlastic", "8C6B4A")
    # pastilles dorées dessous (grille LGA) + triangle broche 1 dessus
    src = rbox((0.55, 0.55, 0.05), (0, 0, 0))
    mats = [T((-13.5 + i * 0.9, -13.5 + j * 0.9, 0.03)) for i in range(31) for j in range(31)
            if not (abs(-13.5 + i * 0.9) < 4 and abs(-13.5 + j * 0.9) < 4)]
    pads = instances(src, mats, "Pads")
    tri = rprism([(-14.4, -14.4), (-12.4, -14.4), (-14.4, -12.4)], TS + 0.05, TS + 0.12)
    tag(merge([pads, tri]), "Pads", "Foil", GOLD)
    done("CpuChip", camera=(0.9, -1.4, 1.5))


def cpu_socket():
    reset()
    # corps plastique avec cavité
    body = rbox((40.0, 40.0, 3.0), (0, 0, 1.5), r=0.4, seg=2)
    bool_op(body, [rbox((31.5, 31.5, 3), (0, 0, 3.2), r=0.3), rbox((1.2, 2.4, 2), (-15.8, 5.0, 2.4)),
                   rbox((1.2, 2.4, 2), (15.8, 5.0, 2.4))])
    keys = [rbox((1.0, 2.2, 1.6), (sx * 15.9, 5.0, 2.0), r=0.1, seg=1) for sx in (-1, 1)]
    tag(merge([body] + keys), "Body", "SmoothPlastic", GRAPHITE_0)
    # champ de broches LGA (bosses pyramidales), un seul objet
    bm = bmesh.new()
    n, p = 48, 0.62
    for i in range(n):
        for j in range(n):
            x, y = -(n - 1) * p / 2 + i * p, -(n - 1) * p / 2 + j * p
            if abs(x) < 5.0 and abs(y) < 5.0:
                continue
            z = 1.55
            s = 0.2
            v = [bm.verts.new((x - s, y - s, z)), bm.verts.new((x + s, y - s, z)), bm.verts.new((x + s, y + s, z)),
                 bm.verts.new((x - s, y + s, z)), bm.verts.new((x + 0.05, y + 0.1, z + 0.32))]
            for a in range(4):
                bm.faces.new((v[a], v[(a + 1) % 4], v[4]))
    pins = obj_from_bm(bm, "Pins")
    mark = rprism([(-19.4, -19.4), (-16.8, -19.4), (-19.4, -16.8)], 3.0, 3.08)   # repère broche 1
    tag(merge([pins, mark]), "Pins", "Foil", GOLD)
    # plaque de maintien (acier) : cadre fenêtré avec nervures embouties, charnière, languette
    Z0 = 3.0
    plate = rprism(crect(43.0, 44.0, 2.0, (0, 0.5)), Z0, Z0 + 0.45)
    bool_op(plate, [rprism(crect(32.0, 32.0, 1.2), Z0 - 1, Z0 + 1),
                    rprism(crect(6.0, 1.5, 0.4, (0, 22.3)), Z0 - 1, Z0 + 1)])
    ribs = []
    for sx in (-1, 1):
        ribs.append(loft([(crect(1.6, 30.0, 0.6, (sx * 18.6, 0.5)), Z0 + 0.4), (crect(0.8, 29.0, 0.3, (sx * 18.6, 0.5)), Z0 + 0.8)]))
    tongue = rbox((8.0, 3.0, 0.4), (0, -22.7, Z0 + 0.62), r=0.15, seg=1, rot=(math.radians(-18), 0, 0))
    hinge = [rcyl(0.7, 6.0, (sx * 14.0, 22.8, Z0 + 0.2), verts=16, rot=(0, math.pi / 2, 0)) for sx in (-1, 1)]
    frame = rbox((46.0, 49.0, 3.0), (0, 0.5, 1.5), r=0.3, seg=2)          # cadre de maintien (ILM) autour du socket
    bool_op(frame, [rbox((40.3, 40.3, 4), (0, 0, 1.5)), rbox((30.0, 3.0, 4), (0, 24.0, 2.6))])
    # levier : tige le long du bord -X, came et poignée recourbée
    lever = [pipe([(-23.6, 22.5, Z0 + 0.3), (-23.6, -18.0, Z0 + 0.3), (-23.6, -22.0, Z0 + 0.5), (-26.0, -24.5, Z0 + 0.7),
                   (-28.5, -24.8, Z0 + 0.8)], 0.42, 10, 4),
             rcyl(0.9, 2.2, (-23.6, 21.5, Z0 + 0.3), verts=20, rot=(math.pi / 2, 0, 0)),
             rbox((3.0, 1.6, 1.4), (-22.3, -20.5, Z0 + 0.4), r=0.3, seg=2)]
    grip = rcyl(0.7, 3.2, (-30.2, -24.8, Z0 + 0.8), verts=16, rot=(0, math.pi / 2, 0), bevel_w=0.2)
    screws = [screw(1.0, 0.6, (sx * 21.0, sy * 21.5, Z0 - 2.6 + 0.4 + 2.2)) for sx in (-1, 1) for sy in (-1, 1)]
    tag(merge([plate, tongue, frame] + ribs + hinge + lever), "Retention", "Metal", ALU_DARK)
    tag(merge(screws), "Screws", "Metal", NICKEL)
    tag(grip, "Grip", "SmoothPlastic", GRAPHITE_1)
    done("CpuSocket", camera=(0.9, -1.3, 1.6))
    qa_view("CpuSocket_pins", (0.3, -0.5, 1.2), zoom=3.0, target=(-8, -8, 2))


def npu_chip():
    reset()
    S = 40.0
    sub = rbox((S, S, 1.0), (0, 0, 0.5), r=0.2, seg=2)
    tag(sub, "Substrate", "SmoothPlastic", GRAPHITE_0)
    # anneau raidisseur métallique + 4 piles HBM
    ring = rprism(crect(38.0, 38.0, 2.5), 1.0, 2.2)
    bool_op(ring, rprism(crect(34.0, 34.0, 1.8), 0.5, 3))
    bev(ring, 0.1, 2, 30)
    hbm = [rbox((5.2, 9.0, 1.5), (sx * 12.6, sy * 5.6, 1.75), r=0.15, seg=2) for sx in (-1, 1) for sy in (-1, 1)]
    edge = []
    for k in range(16):                                    # plots dorés sur le pourtour (dessus)
        for side in range(4):
            a = -17.5 + k * 2.33
            x, y = [(a, -19.3), (19.3, a), (-a, 19.3), (-19.3, -a)][side]
            edge.append(rbox((0.9 if side % 2 == 0 else 0.5, 0.5 if side % 2 == 0 else 0.9, 0.06), (x, y, 1.02)))
    tag(merge([ring] + hbm), "Frame", "Metal", GRAPHITE_2)
    tag(merge(edge), "Pads", "Foil", GOLD)
    # grande puce lilas
    die = loft([(crect(19.0, 19.0, 1.2), 1.0), (crect(19.0, 19.0, 1.2), 3.4), (crect(18.0, 18.0, 0.8), 3.9)])
    bev(die, 0.08, 1, 30)
    tag(die, "Die", "SmoothPlastic", "9F7AEA")
    # circuits lumineux : 4 bus de pistes parallèles à 45° depuis le cœur + vias, tuiles « tensor » gravées
    ZT = 3.9
    traces = []
    rot4 = [lambda x, y: (x, y), lambda x, y: (-y, x), lambda x, y: (-x, -y), lambda x, y: (y, -x)]
    for R_ in rot4:
        for i in range(-3, 4):
            y0 = i * 0.55
            jog = 1.4 if i >= 0 else -1.4
            pts = [(2.9, y0), (4.2 + abs(i) * 0.12, y0), (5.4 + abs(i) * 0.12, y0 + jog * (0.4 + abs(i) * 0.1)),
                   (8.0 - (abs(i) % 2) * 0.7, y0 + jog * (0.4 + abs(i) * 0.1))]
            pts = [R_(x, y) for x, y in pts]
            traces.append(ribbon(pts, 0.2, ZT - 0.05, ZT + 0.07))
            ex, ey = pts[-1]
            traces.append(rcyl(0.33, 0.14, (ex, ey, ZT + 0.02), verts=12))
    tiles = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for tx in (0, 1):
                for ty in (0, 1):
                    cx, cy = sx * (5.6 + tx * 1.9), sy * (5.6 + ty * 1.9)
                    tiles.append(rprism(crect(1.5, 1.5, 0.25, (cx, cy)), ZT - 0.12, ZT + 0.5))
                    traces.append(rcyl(0.2, 0.12, (cx, cy, ZT - 0.08), verts=8))
    bool_op(die, tiles)
    frame_ring = rprism(crect(17.2, 17.2, 0.9), ZT - 0.05, ZT + 0.06)
    bool_op(frame_ring, rprism(crect(16.8, 16.8, 0.8), ZT - 1, ZT + 1))
    traces.append(frame_ring)
    core = rprism(crect(5.6, 5.6, 0.8), ZT - 0.05, ZT + 0.12)
    bool_op(core, rprism(crect(4.6, 4.6, 0.5), ZT - 1, ZT + 1))
    core_in = rprism(crect(3.2, 3.2, 0.5), ZT - 0.05, ZT + 0.16)
    neon = merge(traces + [core, core_in])
    tag(neon, "Circuits", "Neon", "E9D8FD")
    logo = text_mesh("A", 2.4, 0.1, (0, 0.05, ZT + 0.14))
    tag(merge([logo]), "Logo", "Metal", GRAPHITE_0)
    done("NpuChip", camera=(0.8, -1.3, 1.7))


JOBS = {"CpuChip": cpu_chip, "CpuSocket": cpu_socket, "NpuChip": npu_chip}
if __name__ == "__main__":
    for key in (sys.argv[1:] or JOBS):
        JOBS[key]()
