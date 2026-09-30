"""PumpReservoir — combo pompe D5 + réservoir tube : socle de pompe cannelé avec anneau RGB, bagues alu
moletées, cylindre de verre, colonne de liquide lumineuse, tirants nickelés, raccords à compression."""
from hw_common import *

reset()
RG_IN, RG_OUT = 4.0, 4.32
ZG0, ZG1 = 8.2, 22.2

# ------------------------------------------------------------------ socle de pompe (graphite)
body = []
plate = rprism(crect(14.0, 14.0, 2.2), 0.0, 1.0)
bev(plate, 0.15, 2, 30)
body.append(plate)
hous = lathe([(0, 0.9), (6.3, 0.9), (6.5, 1.3), (6.5, 5.2), (6.2, 5.7), (5.6, 5.9), (0, 5.9)], 64, angle=30)
bool_op(hous, [rbox((0.5, 1.4, 3.4), (6.55 * math.cos(a), 6.55 * math.sin(a), 3.3), rot=(0, 0, a))
               for a in [k * 2 * math.pi / 20 + 0.08 for k in range(20)] if abs(math.cos(a)) < 0.9 or math.cos(a) < 0])
body.append(hous)
boss = rcyl(1.9, 3.2, (6.6, 0, 3.2), verts=32, rot=(0, math.pi / 2, 0), bevel_w=0.15)
body.append(boss)
tag(merge(body), "PumpBody", "SmoothPlastic", GRAPHITE_1)

# anneau RGB entre le socle et la bague alu + filet lumineux en bas
ring = lathe([(5.55, 5.85), (6.35, 5.85), (6.35, 6.3), (5.55, 6.3)], 96, closed=True)
ring2 = lathe([(6.5, 1.25), (6.62, 1.25), (6.62, 1.55), (6.5, 1.55)], 96, closed=True)
tag(merge([ring, ring2]), "Rgb", "Neon", ACCENT)

# ------------------------------------------------------------------ bagues alu moletées (bas + haut)
alu = []
low = lathe([(0, 6.25), (5.4, 6.25), (5.5, 6.45), (5.5, 7.7), (5.2, 8.0), (4.6, 8.3), (0, 8.3)], 64, angle=30)
bool_op(low, [rbox((0.35, 0.5, 1.1), (5.55 * math.cos(a), 5.55 * math.sin(a), 7.05), rot=(0, 0, a))
              for a in [k * 2 * math.pi / 36 for k in range(36)]])
alu.append(low)
top = lathe([(0, 22.1), (4.6, 22.1), (5.2, 22.4), (5.5, 22.7), (5.5, 23.9), (5.2, 24.3), (1.6, 24.3), (1.6, 24.5),
             (0, 24.5)], 64, angle=30)
bool_op(top, [rbox((0.35, 0.5, 1.0), (5.55 * math.cos(a), 5.55 * math.sin(a), 23.3), rot=(0, 0, a))
              for a in [k * 2 * math.pi / 36 for k in range(36)]] +
        [rprism([(2.3, -0.12), (4.6, -0.12), (4.6, 0.12), (2.3, 0.12)], 24.1, 25)] +
        [text_mesh("A", 2.2, 0.3, (-2.9, 0, 24.12), (0, 0, math.pi / 2))])
alu.append(top)
tag(merge(alu), "Caps", "Metal", ALU)

# ------------------------------------------------------------------ verre + liquide
glass = lathe([(RG_IN, ZG0), (RG_OUT, ZG0), (RG_OUT, ZG1), (RG_IN, ZG1)], 64, closed=True, angle=50)
tag(glass, "Glass", "Glass", "63B3ED")
fluid = lathe([(0, ZG0 + 0.05), (RG_IN - 0.03, ZG0 + 0.05), (RG_IN - 0.03, 19.3), (RG_IN - 0.25, 19.55),
               (2.0, 19.45), (0, 19.4)], 64, angle=50)
tag(fluid, "Coolant", "Neon", "63B3ED")

# ------------------------------------------------------------------ nickel : tirants, écrous, raccords, vis
nk = []
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    x, y = 4.95 * math.cos(a), 4.95 * math.sin(a)
    nk.append(rcyl(0.2, ZG1 - ZG0 + 0.6, (x, y, (ZG0 + ZG1) / 2), verts=12))
    nk.append(rcyl(0.42, 0.35, (x, y, 24.45), verts=6, bevel_w=0.05))
    nk.append(rcyl(0.42, 0.35, (x, y, 6.1), verts=6, bevel_w=0.05))
# raccord de sortie (côté pompe) et raccord d'entrée (sur le bouchon)
nk.append(rcyl(1.55, 0.8, (8.6, 0, 3.2), verts=6, rot=(0, math.pi / 2, 0), bevel_w=0.08))
nk.append(rcyl(1.4, 2.0, (9.9, 0, 3.2), verts=24, rot=(0, math.pi / 2, 0), bevel_w=0.14))
nk.append(rcyl(1.15, 0.6, (11.2, 0, 3.2), verts=32, rot=(0, math.pi / 2, 0), bevel_w=0.14))
nk.append(rcyl(1.5, 0.7, (0, 0, 24.8), verts=6, bevel_w=0.08))
nk.append(rcyl(1.35, 1.9, (0, 0, 26.1), verts=24, bevel_w=0.14))
nk.append(rcyl(1.1, 0.6, (0, 0, 27.3), verts=32, bevel_w=0.14))
for sx in (-1, 1):
    for sy in (-1, 1):
        nk.append(screw(0.55, 0.35, (sx * 5.6, sy * 5.6, 1.0)))
tag(merge(nk), "Nickel", "Metal", NICKEL)

done("PumpReservoir", camera=(1.4, -1.6, 0.8))
