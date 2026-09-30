"""CaseFrame — pilier d'angle de boîtier en aluminium (20 × 20 × 120) vu de l'intérieur de la tour :
cornière à rebords roulés, goussets ajourés, passe-câbles avec œillets caoutchouc à lamelles, perforations,
vis moletées, canal lumineux dans l'angle intérieur, embouts anodisés. Angle intérieur tourné vers (-X, -Y)."""
from hw_common import *

reset()
HZ = 120.0
T = 1.2
# ------------------------------------------------------------------ cornière (profil extrudé en Z)
prof = [(-10.0, 10.0), (-10.0, 7.2), (-9.0, 7.2), (-9.0, 8.8), (7.0, 8.8), (8.8, 7.0), (8.8, -9.0), (7.2, -9.0),
        (7.2, -10.0), (10.0, -10.0), (10.0, 7.5), (7.5, 10.0)]
frame = rprism(list(reversed(prof)), 0.0, HZ)
cut = []
SLOTS = (24.0, 60.0, 96.0)
for zc in SLOTS:  # passe-câbles dans l'aile arrière (plan y ≈ 9.4)
    cut.append(prism_y(round_profile(crect(11.0, 20.0, 0.0, (-0.8, zc)), 3.0, 4), 7.0, 12.0))
for zc in range(0, 11):  # perforations oblongues dans l'aile latérale (plan x ≈ 9.4)
    z = 7.0 + zc * 10.6
    for y in (-5.0, -1.0, 3.0):
        cut.append(prism_x(round_profile(crect(2.2, 6.0, 0.0, (y, z)), 1.0, 3), 7.0, 12.0))
bool_op(frame, cut)
bev(frame, 0.12, 2, 35)
shade(frame, 35)
# goussets triangulaires ajourés
gus = []
for zc in (42.0, 78.0):
    g = rprism([(-8.0, 8.8), (8.8, 8.8), (8.8, -8.0)], zc - 0.6, zc + 0.6)
    bool_op(g, rprism(round_profile([(-2.0, 7.4), (7.4, 7.4), (7.4, -2.0)], 1.2, 3), zc - 2, zc + 2))
    bev(g, 0.1, 1, 35)
    gus.append(g)
tag(merge([frame] + gus), "Frame", "Metal", ALU_DARK)

# ------------------------------------------------------------------ œillets caoutchouc à lamelles
gr = []
for zc in SLOTS:
    rim = prism_y(round_profile(crect(12.6, 21.6, 0.0, (-0.8, zc)), 3.6, 4), 8.5, 10.1)
    bool_op(rim, prism_y(round_profile(crect(10.2, 19.2, 0.0, (-0.8, zc)), 2.6, 4), 7.0, 12.0))
    flap = prism_y(round_profile(crect(10.6, 19.6, 0.0, (-0.8, zc)), 2.8, 4), 9.2, 9.5)
    slits = [rbox((0.35, 3, 17.0), (-0.8, 9.3, zc))]
    for k in range(7):
        z = zc - 7.2 + k * 2.4
        slits.append(rbox((3.6, 3, 0.22), (-0.8 - 2.4, 9.3, z)))
        slits.append(rbox((3.6, 3, 0.22), (-0.8 + 2.4, 9.3, z)))
    bool_op(flap, slits)
    gr += [rim, flap]
tag(merge(gr), "Grommets", "Plastic", GRAPHITE_0)

# ------------------------------------------------------------------ canal lumineux dans l'angle intérieur
chan = rprism([(5.2, 8.8), (8.8, 8.8), (8.8, 5.2), (8.0, 5.2), (5.2, 8.0)], 4.0, HZ - 4.0)
bool_op(chan, rbox((1.2, 1.2, HZ), (6.9, 6.9, HZ / 2), rot=(0, 0, math.pi / 4)))
light = rbox((0.8, 0.8, HZ - 10.0), (7.05, 7.05, HZ / 2), rot=(0, 0, math.pi / 4))
tag(light, "Light", "Neon", ACCENT)

# ------------------------------------------------------------------ embouts anodisés + vis moletées
caps = []
for z0, z1 in ((0.0, 3.0), (HZ - 3.0, HZ)):
    c = rprism(round_profile([(-10.3, 10.3), (-10.3, 7.0), (7.0, -10.3), (10.3, -10.3), (10.3, 10.3)], 0.8, 3), z0, z1)
    bev(c, 0.25, 2, 35)
    caps.append(c)
caps.append(chan)
tag(merge(caps), "Caps", "Metal", GRAPHITE_2)
screws = []
for z in (14.0, 50.0, 70.0, 106.0):
    head = lathe([(0, 0), (1.1, 0), (1.15, 0.9), (1.0, 1.1), (0, 1.15)], 24)
    bool_op(head, [rbox((0.6, 0.16, 0.7), (1.15 * math.cos(a), 1.15 * math.sin(a), 0.45), rot=(0, 0, a))
                   for a in [k * 2 * math.pi / 16 for k in range(16)]])
    xf(head, (8.8, -8.0, z), (0, -math.pi / 2, 0))
    screws.append(head)
tag(merge(screws), "Screws", "Metal", NICKEL)
done("CaseFrame", camera=(-1.3, -1.6, 0.6))
hero("CaseFrame", (-1.3, -1.6, 0.7), zoom=0.82)
