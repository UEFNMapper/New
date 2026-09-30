"""CpuCooler — ventirad double tour : 2 × 40 ailettes sculptées, 6 caloducs cuivre en U depuis une base
nickelée (étrier + vis à ressort), capots supérieurs avec embouts de caloducs, ventilateur 120 clipsé au centre.

⚠ Orientation : un __Spin tourne autour de Z Blender, donc le ventirad est modélisé COUCHÉ :
   le haut du ventirad pointe vers +X, la semelle (contact CPU) vers -X, l'axe du ventilateur = Z.
   Pour le poser debout sur le CPU en jeu : tourner de +90° autour de l'axe Z Roblox
   (CFrame.Angles(0, 0, math.rad(90))) après le placement."""
from hw_common import *

reset()
# Tout est construit « debout » (Z = haut, flux d'air selon X), puis basculé par R à la fin.
R = Matrix(((0, 0, 1, 0), (0, -1, 0, 0), (1, 0, 0, 0), (0, 0, 0, 1)))   # (x, y, z) → (z, -y, x), R = R⁻¹

TX0, TX1 = 3.6, 15.6        # tour +X (la tour -X est symétrique)
TY = 17.5                   # demi-largeur des ailettes
Z_F0, NF, PITCH = 9.0, 40, 0.74
Z_TOP = Z_F0 + NF * PITCH + 0.2
FAN_Z = 23.5

# ------------------------------------------------------------------ ailettes (sculptées, dents de scie en entrée d'air)
fins = []
for side in (-1, 1):
    for k in range(NF):
        z = Z_F0 + k * PITCH
        a, b = TX0, TX1
        teeth = []
        n = 9
        for i in range(n + 1):  # bord extérieur en dents de scie
            y = -TY + 1.5 + (2 * TY - 3) * i / n
            teeth.append((b + (0.45 if i % 2 else 0.0), y))
        prof = [(a, -TY + 0.8), (a + 0.8, -TY), (b - 1.8, -TY), (b, -TY + 1.5)] + teeth[1:-1] + \
               [(b, TY - 1.5), (b - 1.8, TY), (a + 0.8, TY), (a, TY - 0.8)]
        if side < 0:
            prof = [(-x, y) for x, y in reversed(prof)]
        f = rprism(prof, z, z + 0.14)
        fins.append(f)
fins = merge(fins)

# clips du ventilateur (fil d'acier) : 4 coins
clips = []
for sy in (-1, 1):
    for zc in (FAN_Z - 14.2, FAN_Z + 14.2):
        d = -1 if zc < FAN_Z else 1
        clips.append(pipe([(-5.2, sy * 15.6, zc - d * 1.6), (-4.0, sy * 15.6, zc), (4.0, sy * 15.6, zc),
                           (5.2, sy * 15.6, zc - d * 1.6)], 0.16, 8, 6))

# ------------------------------------------------------------------ caloducs : 6 U, base → tours
pipes, caps = [], []
YB = [-3.9 + 1.56 * i for i in range(6)]
YT = [-13.8 + 5.52 * i for i in range(6)]
for i in range(6):
    xt = 6.4 if i % 2 == 0 else 12.6
    rb = 2.6
    pts = []
    for side in (-1, 1):
        leg = []
        # vertical, du haut vers le bas, avec étalement en Y dans la zone basse
        for z in (Z_TOP - 0.6, 30.0, 20.0, 12.0, 8.0, 5.8):
            t = min(1.0, max(0.0, (z - 4.0) / 6.0))
            leg.append((side * xt, YB[i] + (YT[i] - YB[i]) * t, z))
        for a in (0.25, 0.5, 0.75):  # quart de cercle
            ang = a * math.pi / 2
            leg.append((side * (xt - rb + rb * math.cos(ang)), YB[i], 1.3 + rb - rb * math.sin(ang)))
        leg.append((side * (xt - rb - 1.0), YB[i], 1.3))
        pts += leg if side < 0 else list(reversed(leg))
    pipes.append(pipe(pts, 0.72, 12, 3, cap=True))
    for side in (-1, 1):  # embouts nickelés qui dépassent du capot
        caps.append(lathe([(0, Z_TOP + 0.9), (0.74, Z_TOP + 0.9), (0.74, Z_TOP + 1.25), (0.55, Z_TOP + 1.5),
                           (0, Z_TOP + 1.58)], 20, (side * xt, YT[i], 0)))
pipes = merge(pipes)
tag(pipes, "Heatpipes", "Metal", COPPER)

# ------------------------------------------------------------------ semelle nickelée + étrier
base = rbox((10.5, 11.5, 2.4), (0, 0, 1.3), r=0.25, seg=2)
plate = rbox((9.6, 10.6, 0.5), (0, 0, 0.25), r=0.08, seg=2)          # face miroir de contact
grooves = [rbox((11, 0.12, 0.4), (0, y, 2.5)) for y in (-4.6, 4.6)]
bool_op(base, grooves)
nickel = merge([base, plate] + caps)
tag(nickel, "Base", "Metal", NICKEL)

dark = []
bar = rprism([(-1.8, -13.5), (1.8, -13.5), (1.8, -4.0), (1.3, -3.0), (1.3, 3.0), (1.8, 4.0), (1.8, 13.5), (-1.8, 13.5),
              (-1.8, 4.0), (-1.3, 3.0), (-1.3, -3.0), (-1.8, -4.0)], 2.5, 3.2)
bev(bar, 0.12, 2, 30)
dark.append(bar)
dark.append(rbox((3.4, 3.4, 0.9), (0, 0, 3.6), r=0.2, seg=2))  # bossage central
for sy in (-1, 1):  # vis à ressort
    dark.append(screw(0.9, 0.7, (0, sy * 12.2, 3.2), slot="cross"))
    coil = [(0.62 * math.cos(t), sy * 12.2 + 0.62 * math.sin(t), 0.2 + 3.0 * t / (2 * math.pi * 5)) for t in
            [j * 0.5 for j in range(int(2 * math.pi * 5 / 0.5) + 1)]]
    dark.append(pipe(coil, 0.1, 6, 2, cap=False))
    dark.append(rcyl(0.3, 3.0, (0, sy * 12.2, 1.2), verts=12))
# capots supérieurs (graphite) chanfreinés, avec rainures anguleuses
covers = []
for side in (-1, 1):
    out = crect(TX1 - TX0 + 1.2, 2 * TY + 1.0, 1.4, (side * (TX0 + TX1) / 2, 0))
    top = crect(TX1 - TX0 - 0.6, 2 * TY - 0.8, 0.8, (side * (TX0 + TX1) / 2, 0))
    c = loft([(out, Z_TOP), (out, Z_TOP + 0.6), (top, Z_TOP + 1.3)])
    cutters = [rcyl(0.78, 3, (side * (6.4 if i % 2 == 0 else 12.6), YT[i], Z_TOP + 1), verts=20) for i in range(6)]
    for k in range(3):
        xg = side * (TX0 + 2.5 + k * 3.8)
        cutters.append(rprism([(xg - 0.12, -TY + 2.5), (xg + 0.12, -TY + 2.5), (xg + 0.12, -TY + 6.5), (xg - 0.12, -TY + 6.5)],
                              Z_TOP + 1.05, Z_TOP + 2))
    bool_op(c, cutters)
    bev(c, 0.06, 1, 30)
    covers.append(c)
tag(merge(dark + covers), "Covers", "Metal", GRAPHITE_2)

# logos « A » en alu sur les capots, joints aux ailettes (même alu)
logos = [text_mesh("A", 5.0, 0.2, (side * (TX0 + TX1) / 2, 4.5, Z_TOP + 1.22)) for side in (-1, 1)]
tag(merge([fins] + clips + logos), "Fins", "Metal", ALU)

# liseré ARGB le long des capots
strips = []
for side in (-1, 1):
    x_out = side * (TX1 + 0.62)
    strips.append(rbox((0.18, 2 * TY - 2, 0.35), (x_out, 0, Z_TOP + 0.3)))
tag_later = strips

# ------------------------------------------------------------------ ventilateur 120 (construit axe Z puis placé)
S, D, BORE = 30.0, 6.4, 14.1
fr = fan_frame(S, D, BORE, corner_r=1.8, flange=1.0, shroud=14.6, struts=4, motor_r=4.2)
rot = fan_rotor(13.7, 4.6, 9, 1.8, 5.9, sweep=0.55, ring=True, thick=0.16)
bake(rot)
ring = lathe([(14.15, D - 0.1), (15.2, D - 0.1), (15.25, D + 0.08), (14.9, D + 0.18), (14.4, D + 0.18),
              (14.18, D + 0.08)], 128, closed=True)
band = lathe([(14.6, D * 0.45), (14.8, D * 0.45), (14.8, D * 0.55), (14.6, D * 0.55)], 128, closed=True)
pads = fan_pads(S, D, BORE, 0.0, t=0.35)
cable = pipe([(3.0, -2.2, 0.7), (7.0, -7.0, 0.9), (10.5, -10.5, 0.9), (13.2, -13.2, 1.8), (14.4, -14.2, 3.0)], 0.3, 8, 4)
fan_parts = [fr, rot, ring, band, pads, cable]
for o in fan_parts:
    xf(o, (0, 0, -D / 2))
    o.data.transform(R)
    xf(o, (0, 0, FAN_Z))
tag(merge([fr, cable]), "FanFrame", "SmoothPlastic", GRAPHITE_0)
tag(pads, "FanPads", "Plastic", "3D3566")
tag(merge([ring, band] + tag_later), "Argb", "Neon", ACCENT)
tag(rot, "Rotor", "SmoothPlastic", GRAPHITE_2, spin=True)

# ------------------------------------------------------------------ bascule finale : axe du ventilateur → Z
for o in [o for o in bpy.data.objects if o.type == "MESH"]:
    bake(o)
    o.data.transform(R)
    o.data.update()
bpy.context.view_layer.update()
bb = [Vector(v) for v in rot.bound_box]
set_origin(rot, [(max(v[i] for v in bb) + min(v[i] for v in bb)) / 2 for i in range(3)])

done("CpuCooler", camera=(1.4, -1.0, 1.1))
hero("CpuCooler", (0.6, 1.5, 0.8), up=(1, 0, 0), zoom=1.05)
