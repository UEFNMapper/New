"""Composants de carte mère : Capacitor, CapacitorBig (condensateurs électrolytiques), Choke, ChokeRow (selfs).
Un seul script génère les 4 modèles (python3 passives.py [Nom…] pour n'en refaire qu'un)."""
import sys
from hw_common import *


def capacitor(name, R, Hh, sleeve_mat, sleeve_col, stripe_col):
    """Condensateur radial : gaine (liseré de polarité en relief avec « − »), sertissage, dôme alu gravé
    en K (évent de sécurité), joint caoutchouc, deux pattes."""
    reset()
    LEG = 0.7                      # pattes visibles sous le corps
    z0, z1 = LEG, LEG + Hh
    g = Hh * 0.13                  # position de la gorge de sertissage (près du haut)
    prof = [(0, z0 + 0.15), (R * 0.9, z0 + 0.15), (R * 0.97, z0 + 0.3), (R, z0 + 0.5), (R, z1 - g - 0.35),
            (R * 0.93, z1 - g - 0.15), (R * 0.93, z1 - g + 0.15), (R, z1 - g + 0.35), (R, z1 - 0.25),
            (R * 0.98, z1 - 0.08), (R * 0.93, z1), (R * 0.86, z1), (R * 0.86, z1 - 0.1), (0, z1 - 0.1)]
    sleeve = lathe(prof, 64, angle=35)
    tag(sleeve, "Sleeve", sleeve_mat, sleeve_col)
    # liseré de polarité : bande en relief sur ~55° avec des « − » découpés
    arc = math.radians(55)
    band = lathe([(p[0] + 0.015, p[1]) if p[0] > R * 0.9 else p for p in prof[3:11]], 16, arc=arc, angle=35)
    solidify(band, 0.03, 1.0)
    xf(band, (0, 0, 0), (0, 0, -arc / 2))
    minus = []
    for k in range(3):
        zc = z0 + 0.25 * Hh + k * 0.22 * Hh
        minus.append(rbox((0.4, R * 0.42, Hh * 0.028), (R + 0.02, 0, zc)))
    bool_op(band, minus)
    tag(band, "Stripe", "SmoothPlastic", stripe_col)
    # dôme alu avec évent en K
    # dessus parfaitement plan (ombrage net autour des rainures), petit chanfrein périphérique
    top = lathe([(0, z1 - 0.12), (R * 0.87, z1 - 0.12), (R * 0.87, z1 - 0.03), (R * 0.8, z1 + 0.03), (0, z1 + 0.03)],
                64, angle=20)
    w = R * 0.07
    k_cut = [rbox((w, R * 1.1, 0.2), (-R * 0.15, 0, z1 + 0.03)),
             rbox((w, R * 0.62, 0.2), (R * 0.05, R * 0.25, z1 + 0.03), rot=(0, 0, math.radians(-40))),
             rbox((w, R * 0.62, 0.2), (R * 0.05, -R * 0.25, z1 + 0.03), rot=(0, 0, math.radians(40)))]
    bool_op(top, k_cut)
    ngon_fix(top)
    shade(top, 20)
    legs = [pipe([(sx * R * 0.4, 0, 0.0), (sx * R * 0.4, 0, z0 + 0.3)], R * 0.06, 8, 1) for sx in (-1, 1)]
    tag(merge([top] + legs), "Top", "Metal", ALU)
    bung = lathe([(0, z0 - 0.02), (R * 0.88, z0 - 0.02), (R * 0.9, z0 + 0.2), (0, z0 + 0.2)], 48)
    tag(bung, "Seal", "Plastic", GRAPHITE_0)
    done(name, camera=(1.3, -1.7, 1.2))


def choke_parts(cx=0.0, cy=0.0, s=6.0, h=5.0, label="R22", sides=12, per_turn=28):
    """Self de puissance : noyau ferrite en tambour (plaques + fût), bobinage cuivre plat, bornes étamées."""
    zb = 0.25
    base = rbox((s, s, 0.9), (cx, cy, zb + 0.45), r=0.25, seg=2)
    topp = rbox((s, s, 1.0), (cx, cy, h - 0.5), r=0.3, seg=2, angle=20)
    # marquage imprimé (léger relief, gris clair) : pas de booléen sur la face → ombrage propre
    txt = text_mesh(label, s * 0.28, 0.04, (cx, cy - s * 0.12, h - 0.01))
    dot = rcyl(s * 0.05, 0.04, (cx - s * 0.32, cy + s * 0.32, h + 0.01), verts=12)
    core = rcyl(s * 0.27, h - 1.6, (cx, cy, h / 2 + 0.1), verts=32)
    ferrite = [base, topp, core]
    turns, zc0, zc1 = 5.5, zb + 1.05, h - 1.15
    n = int(turns * per_turn)
    coil = pipe([(cx + s * 0.36 * math.cos(2 * math.pi * turns * i / n), cy + s * 0.36 * math.sin(2 * math.pi * turns * i / n),
                  zc0 + (zc1 - zc0) * i / n) for i in range(n + 1)], s * 0.075, sides, 1, cap=True)
    # sorties du fil vers les bornes
    coil = merge([coil, pipe([(cx + s * 0.36, cy, zc0), (cx + s * 0.48, cy - s * 0.1, zb + 0.5)], s * 0.07, 8, 3),
                  pipe([(cx + s * 0.36 * math.cos(2 * math.pi * turns), cy + s * 0.36 * math.sin(2 * math.pi * turns), zc1),
                        (cx - s * 0.48, cy + s * 0.1, zb + 0.6)], s * 0.07, 8, 3)])
    pads = [rbox((s * 0.22, s * 0.8, 0.45), (cx + sx * s * 0.42, cy, 0.22), r=0.06, seg=1) for sx in (-1, 1)]
    return ferrite, [coil], pads + [txt, dot]


def choke():
    reset()
    f, c, p = choke_parts()
    tag(merge(f), "Ferrite", "Plastic", "2E3038")
    tag(merge(c), "Coil", "Metal", COPPER)
    tag(merge(p), "Pins", "Metal", NICKEL)
    done("Choke", camera=(1.3, -1.7, 1.3))


def choke_row():
    reset()
    N, pitch = 6, 7.2
    L = N * pitch + 2.0
    strip = rbox((L, 9.5, 0.6), (0, 0, 0.3), r=0.12, seg=2)
    fer, coi, pin, smd = [], [], [], []
    for i in range(N):
        x = -(N - 1) * pitch / 2 + i * pitch
        f, c, p = choke_parts(x, 0.6, label="R22", sides=8, per_turn=20)
        for o in f + c + p:
            xf(o, (0, 0, 0.6))
        fer += f; coi += c; pin += p
        # condensateurs CMS + MOSFET devant chaque self
        smd.append(rbox((1.6, 1.0, 0.55), (x - 1.4, -3.9, 0.85), r=0.08, seg=1))
        smd.append(rbox((1.1, 0.8, 0.5), (x + 1.5, -3.9, 0.85), r=0.08, seg=1))
    tag(merge([strip]), "Strip", "SmoothPlastic", PCB)
    tag(merge(fer + smd), "Ferrite", "Plastic", "2E3038")
    tag(merge(coi), "Coil", "Metal", COPPER)
    pads = [rbox((pitch - 1.0, 7.6, 0.06), (-(N - 1) * pitch / 2 + i * pitch, 0.6, 0.62)) for i in range(N)]
    tag(merge(pin + pads), "Pins", "Metal", NICKEL)
    done("ChokeRow", camera=(0.9, -1.6, 1.1))


JOBS = {
    "Capacitor": lambda: capacitor("Capacitor", 3.0, 9.3, "SmoothPlastic", GRAPHITE_2, "8A8F9C"),
    "CapacitorBig": lambda: capacitor("CapacitorBig", 5.0, 15.3, "SmoothPlastic", "F6AD55", GRAPHITE_1),
    "Choke": choke,
    "ChokeRow": choke_row,
}
if __name__ == "__main__":
    for key in (sys.argv[1:] or JOBS):
        JOBS[key]()
