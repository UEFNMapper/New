"""Stockage : M2Ssd (M.2 2280 avec dissipateur amovible) et SataSsd (SSD 2,5" boîtier alu brossé).
python3 storage.py [M2Ssd|SataSsd]"""
import sys
from hw_common import *

TEAL = "38B2AC"


def m2():
    reset()
    L, Wd, T = 80.0, 22.0, 0.8
    X0 = -L / 2
    # ---------------------------------------------------------------- PCB : détrompeur M, encoche de vis
    y_key = 2.9                                            # encoche M (décalée)
    out = [(X0 + 4.2, -Wd / 2), (L / 2 - 0.6, -Wd / 2), (L / 2, -Wd / 2 + 0.6), (L / 2, -1.9), (L / 2 - 0.4, -1.75),
           (L / 2 - 1.7, -1.2), (L / 2 - 2.1, 0), (L / 2 - 1.7, 1.2), (L / 2 - 0.4, 1.75), (L / 2, 1.9),
           (L / 2, Wd / 2 - 0.6), (L / 2 - 0.6, Wd / 2), (X0 + 4.2, Wd / 2), (X0 + 4.2, Wd / 2 - 0.5),
           (X0 + 0.3, Wd / 2 - 0.5), (X0, Wd / 2 - 0.8), (X0, y_key + 0.6), (X0 + 4.0, y_key + 0.6), (X0 + 4.0, y_key - 0.6),
           (X0, y_key - 0.6), (X0, -Wd / 2 + 0.8), (X0 + 0.3, -Wd / 2 + 0.5), (X0 + 4.2, -Wd / 2 + 0.5)]
    pcb = rprism(out, 0.0, T)
    smd = []
    for i in range(10):  # condensateurs / résistances CMS
        smd.append(rbox((0.9, 0.5, 0.45), (X0 + 7.5 + (i % 5) * 1.3, -8.5 + (i // 5) * 1.2, T + 0.22), r=0.05, seg=1))
    for i in range(6):
        smd.append(rbox((0.5, 1.0, 0.4), (L / 2 - 6.0, -7.0 + i * 1.6, T + 0.2), r=0.05, seg=1))
    tag(merge([pcb] + smd), "Pcb", "SmoothPlastic", PCB)
    # ---------------------------------------------------------------- puces : contrôleur, DRAM, 2 NAND
    chips = []

    def chip(cx, cy, sx, sy, h, text=None, tsize=1.2):
        c = rbox((sx, sy, h), (cx, cy, T + h / 2), r=0.12, seg=2)
        cut = []
        if text:
            for k, line in enumerate(text):
                cut.append(text_mesh(line, tsize, 0.2, (cx, cy + (len(text) - 1) * tsize * 0.8 - k * tsize * 1.6,
                                                         T + h - 0.06), (0, 0, 0)))
        cut.append(rcyl(0.35, 0.2, (cx - sx / 2 + 1.0, cy - sy / 2 + 1.0, T + h), verts=12))  # repère broche 1
        bool_op(c, cut)
        chips.append(c)

    chip(-22.0, 0.0, 9.0, 9.0, 1.1, ["AI-NVMe", "G5 X4"], 1.1)
    chip(-11.5, 3.5, 5.0, 8.0, 0.9, ["LPDDR"], 0.8)
    chip(2.0, 0.0, 14.0, 18.0, 1.35, ["3D TLC", "2TB", "AngAInOne"], 1.4)
    chip(20.5, 0.0, 14.0, 18.0, 1.35, ["3D TLC", "2TB", "AngAInOne"], 1.4)
    tag(merge(chips), "Chips", "SmoothPlastic", GRAPHITE_0)
    # ---------------------------------------------------------------- contacts dorés (2 faces, 67 broches M)
    gold = []
    for side_z in (T + 0.015, -0.015):
        for k in range(33):
            y = -Wd / 2 + 1.3 + k * 0.6
            if abs(y - y_key) < 0.75:
                continue
            gold.append(rbox((3.4, 0.36, 0.03), (X0 + 2.0, y, side_z)))
    gold.append(rbox((5.0, 3.0, 0.04), (L / 2 - 1.4, 0, T + 0.02)))   # pastille de masse (vis)
    bool_op(gold[-1], rcyl(1.75, 2, (L / 2 - 2.1 + 1.7 - 1.7, 0, T), verts=32))
    tag(merge(gold), "Contacts", "Foil", GOLD)
    # ---------------------------------------------------------------- repères teal : logo + LED d'activité
    acc = [text_mesh("A", 3.0, 0.08, (-22.0 + 2.9, -2.9, T + 1.1 - 0.02)),
           rbox((0.9, 0.6, 0.35), (X0 + 10.5, 8.5, T + 0.17), r=0.08, seg=1)]
    tag(merge(acc), "Led", "Neon", TEAL)
    # ---------------------------------------------------------------- dissipateur amovible (un seul objet)
    zb = T + 1.35 + 0.35                                   # posé sur un pad thermique
    hs = rprism(crect(70.0, 21.0, 1.5, (4.5, 0)), zb, zb + 1.2)
    fins = []
    for k in range(9):  # ailettes longitudinales à nez biseauté ; zone plate côté connecteur pour le logo
        y = -8.8 + k * 2.2
        prof = [(-12.0, 0), (38.0, 0), (38.0, 1.0), (36.2, 3.0), (-9.5, 3.0), (-12.0, 1.2)]
        fins.append(prism_y(prof, y - 0.38, y + 0.38))
    for f in fins:
        xf(f, (0, 0, zb + 1.1))
    hs = merge([hs] + fins)
    bool_op(hs, [rprism([(x, -12), (x + 0.6, -12), (x + 0.6, 12), (x, 12)], zb + 2.3, zb + 6) for x in (6.0, 20.0)])
    pad = rprism(crect(66.0, 19.0, 0.8, (4.5, 0)), zb - 0.36, zb + 0.02)
    logo = text_mesh("A", 8.0, 0.25, (-21.0, 0, zb + 1.15), (0, 0, -math.pi / 2))
    word = text_mesh("GEN5", 2.2, 0.2, (-15.5, 0, zb + 1.15), (0, 0, -math.pi / 2))
    hs = merge([hs, pad, logo, word])
    bev(hs, 0.08, 1, 35)
    tag(hs, "Heatsink", "Metal", GRAPHITE_2)
    done("M2Ssd", camera=(0.9, -1.4, 1.2))
    hs.hide_render = True
    qa_view("M2Ssd_bare", (0.9, -1.4, 1.2))


def sata():
    reset()
    L, Wd, H = 100.0, 70.0, 7.0
    case = rbox((L, Wd, H), (0, 0, H / 2), r=0.9, seg=3)
    cut = [rbox((L - 12.0, Wd - 10.0, 2.0), (-3.0, 0, H + 0.6), r=1.2, seg=2),          # logement du panneau
           rbox((1.0, 30.0, 4.6), (L / 2, 12.0, H / 2), r=0.2),                         # ouverture connecteurs
           rbox((L + 2, 0.35, 0.35), (0, -Wd / 2, 2.6)), rbox((L + 2, 0.35, 0.35), (0, Wd / 2, 2.6))]  # joint de coque
    for sx in (-1, 1):
        for x in (-36.0, 25.0):
            cut.append(rcyl(1.4, 3, (x, sx * Wd / 2, 3.5), verts=24, rot=(math.pi / 2, 0, 0)))
    bool_op(case, cut)
    tag(case, "Case", "Metal", ALU)
    # panneau supérieur graphite sculpté
    panel = rprism(crect(L - 13.0, Wd - 11.0, (1.0, 6.0, 1.0, 6.0), (-3.0, 0)), H - 0.5, H + 0.2)
    bev(panel, 0.12, 2, 30)
    grooves = [rprism([(x, -30), (x + 0.5, -30), (x + 8.5, 30), (x + 8.0, 30)], H - 0.05, H + 1) for x in (22.0, 24.0, 26.0)]
    bool_op(panel, grooves)
    words = [text_mesh("ANGAINONE", 7.5, 0.25, (-10.0, 9.0, H + 0.15)),
             text_mesh("SSD  4TB  SATA III", 3.4, 0.2, (-10.0, -0.5, H + 0.15))]
    tag(merge([panel] + words), "Panel", "Metal", GRAPHITE_2)
    # connecteurs SATA (données 7 broches + alimentation 15 broches)
    plast, gold = [], []
    XE = L / 2 - 0.4
    for yc, w in ((20.0, 8.6), (5.0, 14.0)):
        hous = rbox((4.0, w + 1.6, 3.6), (XE - 1.2, yc, H / 2), r=0.2, seg=2)
        bool_op(hous, [rbox((4.0, w, 1.6), (XE, yc, H / 2 + 0.45)),
                       rbox((4.0, 1.2, 1.0), (XE, yc - w / 2 + 0.6, H / 2 - 0.6))])   # fente en L
        plast.append(hous)
        tongue = rbox((3.2, w - 0.4, 0.5), (XE - 0.6, yc + 0.2, H / 2 + 0.05))
        plast.append(tongue)
        n = 7 if w < 10 else 15
        for k in range(n):
            gold.append(rbox((2.4, (w - 1.2) / n * 0.55, 0.06), (XE - 0.4, yc - w / 2 + 0.8 + (k + 0.5) * (w - 1.2) / n,
                                                                H / 2 + 0.33)))
    tag(merge(plast), "Ports", "SmoothPlastic", GRAPHITE_0)
    tag(merge(gold), "Contacts", "Foil", GOLD)
    screws = [screw(1.3, 0.4, (sx * (L / 2 - 3.6), sy * (Wd / 2 - 3.6), H - 0.1)) for sx in (-1, 1) for sy in (-1, 1)]
    tag(merge(screws), "Screws", "Metal", NICKEL)
    acc = rprism([(-44.0, -29.5), (30.0, -29.5), (30.8, -30.3), (-44.0, -30.3)], H - 0.1, H + 0.25)
    tag(acc, "Accent", "Neon", TEAL)
    done("SataSsd", camera=(1.3, -1.5, 1.4))
    qa_view("SataSsd_ports", (1.5, 0.3, 0.4), zoom=2.5, target=(48, 12, 3))


JOBS = {"M2Ssd": m2, "SataSsd": sata}
if __name__ == "__main__":
    for key in (sys.argv[1:] or JOBS):
        JOBS[key]()
