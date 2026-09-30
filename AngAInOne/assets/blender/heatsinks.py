"""Dissipateurs de carte mère : VrmHeatsink (en L, ailettes sculptées, pad thermique) et ChipsetHeatsink
(plaque facettée avec logo « A » RGB). python3 heatsinks.py [VrmHeatsink|ChipsetHeatsink]"""
import sys
from hw_common import *


def fin_profile(length, h, base, pitch=2.0, fin=1.1, slope=2.2):
    """Profil (u, z) d'une rangée d'ailettes : socle plein puis dents à sommet incliné (sculpté)."""
    pts = [(0, 0), (length, 0), (length, base)]
    n = int((length - fin) // pitch)
    u = length - (length - n * pitch - fin) / 2
    for i in range(n + 1):
        a = u - fin
        k = i / max(n, 1)
        top = h - slope * (0.5 - 0.5 * math.cos(k * math.pi * 2))  # vague douce sur la longueur
        pts += [(u, base), (u, top - 0.5), (u - 0.45, top), (a, top - 0.25), (a, base)]
        u -= pitch
    pts.append((0, base))
    # retire les doublons consécutifs
    clean = [pts[0]]
    for p in pts[1:]:
        if (Vector(p) - Vector(clean[-1])).length > 1e-4:
            clean.append(p)
    return clean


def vrm():
    reset()
    H, WA = 12.0, 10.0                 # hauteur, largeur des bras
    LX, LY = 60.0, 36.0                # bras long (X) et bras court (Y)
    X0, Y0 = -LX / 2, LY / 2           # coin extérieur du L : bras long vers +X, bras court vers -Y
    ZB = 3.6                           # socle plein
    body = []
    # socles
    body.append(rbox((LX - WA + 0.2, WA, ZB), (X0 + WA + (LX - WA) / 2 - 0.1, Y0 - WA / 2, ZB / 2), r=0.3, seg=2))
    body.append(rbox((WA, LY - WA + 0.2, ZB), (X0 + WA / 2, Y0 - WA - (LY - WA) / 2 + 0.1, ZB / 2), r=0.3, seg=2))
    # ailettes minces à sommet sculpté (plongent vers l'intérieur du L), profil transversal
    prof = [(0.4, ZB - 0.1), (WA - 0.4, ZB - 0.1), (WA - 0.4, H - 4.2), (4.4, H - 2.2), (3.4, H - 1.4), (0.4, H - 1.4)]
    fins = []
    x = X0 + WA + 0.9
    while x < X0 + LX - 0.6:
        fins.append(prism_x([(Y0 - u, z) for u, z in prof], x - 0.33, x + 0.33))
        x += 1.35
    y = Y0 - WA - 0.9
    while y > Y0 - LY + 0.6:
        fins.append(prism_y([(X0 + u, z) for u, z in prof], y - 0.33, y + 0.33))
        y -= 1.35
    # bloc d'angle plein, facetté
    out = crect(WA + 0.01, WA + 0.01, (0, 0, 2.2, 0), (X0 + WA / 2, Y0 - WA / 2))
    top = crect(WA - 1.6, WA - 1.6, (0, 0, 1.6, 0), (X0 + WA / 2 - 0.3, Y0 - WA / 2 + 0.3))
    corner = loft([(out, 0.0), (out, H - 0.8), (top, H + 0.6)])
    body = merge(body + fins + [corner])
    tag(body, "Body", "Metal", GRAPHITE_2)
    # capots alu brossé sur l'arête extérieure des bras (chanfreinés, rainurés)
    cov = [(-0.3, H - 1.6), (3.6, H - 1.6), (4.6, H - 0.9), (3.8, H - 0.1), (0.4, H - 0.1), (-0.3, H - 0.8)]
    c1 = prism_x([(Y0 - u, z) for u, z in cov], X0 + WA, X0 + LX - 0.2)
    c2 = prism_y([(X0 + u, z) for u, z in cov], Y0 - LY + 0.2, Y0 - WA)
    caps = []
    for c in (c1, c2):
        bev(c, 0.1, 2, 30)
        caps.append(c)
    bool_op(caps[0], [rbox((LX, 0.25, 0.4), (0, Y0 - 1.3 - k * 0.9, H - 0.1)) for k in range(2)])
    bool_op(caps[1], [rbox((0.25, LY, 0.4), (X0 + 1.3 + k * 0.9, 0, H - 0.1)) for k in range(2)])
    cap = rprism(crect(WA - 2.2, WA - 2.2, (0.3, 0.3, 1.3, 0.3), (X0 + WA / 2 - 0.3, Y0 - WA / 2 + 0.3)), H + 0.5, H + 0.95)
    bev(cap, 0.08, 1, 30)
    logo = text_mesh("A", 4.8, 0.25, (X0 + WA / 2 - 0.3, Y0 - WA / 2 + 0.2, H + 0.9))
    tag(merge(caps + [cap, logo]), "Alu", "Metal", ALU)
    # pad thermique (dépasse légèrement sous le dissipateur) + vis
    pad = merge([rbox((LX - 1.0, WA - 1.0, 0.5), (X0 + LX / 2 + 0.5, Y0 - WA / 2, -0.2), r=0.1, seg=1),
                 rbox((WA - 1.0, LY - WA, 0.5), (X0 + WA / 2, Y0 - WA - (LY - WA) / 2 + 0.5, -0.2), r=0.1, seg=1)])
    tag(pad, "ThermalPad", "SmoothPlastic", "8A8F9C")
    screws = [screw(0.9, 0.5, (X0 + LX - 1.2, Y0 - WA + 1.6, ZB)), screw(0.9, 0.5, (X0 + WA - 1.6, Y0 - LY + 1.2, ZB))]
    tag(merge(screws), "Screws", "Metal", NICKEL)
    done("VrmHeatsink", camera=(1.2, -1.5, 1.4))


def chipset():
    reset()
    W, Dp, H = 26.0, 22.0, 3.6
    out = crect(W, Dp, (1.0, 4.5, 1.0, 4.5))
    mid = crect(W, Dp, (1.0, 4.5, 1.0, 4.5))
    top = crect(W - 2.4, Dp - 2.4, (0.6, 3.6, 0.6, 3.6))
    plate = loft([(out, 0.0), (mid, H - 1.0), (top, H)])
    cut = [rprism([(-2.2, -Dp), (-1.2, -Dp), (6.8, Dp), (5.8, Dp)], H - 0.5, H + 1),
           rprism([(-4.2, -Dp), (-3.7, -Dp), (4.3, Dp), (3.8, Dp)], H - 0.35, H + 1),
           rprism(crect(9.6, 9.6, 2.0, (-6.5, 1.5)), H - 0.6, H + 1)]      # logement du logo
    bool_op(plate, cut)
    bev(plate, 0.1, 2, 30)
    shade(plate, 30)
    tag(plate, "Plate", "Metal", GRAPHITE_2)
    logo = text_mesh("A", 7.0, 0.5, (-6.5, 1.6, H - 0.6))
    ring = rprism(crect(9.0, 9.0, 1.8, (-6.5, 1.5)), H - 0.6, H - 0.45)
    bool_op(ring, rprism(crect(8.2, 8.2, 1.5, (-6.5, 1.5)), H - 1, H))
    tag(merge([logo, ring]), "Rgb", "Neon", ACCENT)
    trim = rprism([(5.0, -8.5), (11.5, -8.5), (11.5, -7.8), (5.6, -7.8)], H - 0.05, H + 0.25)
    txt = text_mesh("ANGAINONE", 1.3, 0.18, (7.0, -5.8, H - 0.02))
    tag(merge([trim, txt]), "Alu", "Metal", ALU)
    done("ChipsetHeatsink", camera=(1.0, -1.4, 1.6))


JOBS = {"VrmHeatsink": vrm, "ChipsetHeatsink": chipset}
if __name__ == "__main__":
    for key in (sys.argv[1:] or JOBS):
        JOBS[key]()
