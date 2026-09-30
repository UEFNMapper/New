"""DeskLamp — lampe d'architecte (≈180 studs) : socle lesté tourné, bras doubles articulés, ressorts
d'équilibrage apparents, molettes de serrage, abat-jour rouge AngaTV (intérieur blanc, ouïes), ampoule
néon, interrupteur, câble.
Modélisée façade vers −Y (la tête éclaire vers l'avant) puis tournée à l'export."""
from room_common import *

reset()
X = Vector((1, 0, 0))
body, alu, springs, red, white, glow = [], [], [], [], [], []

# ---------------------------------------------------------------- socle lesté
base = lathe([(0, 0), (21.0, 0), (22.2, 0.5), (22.6, 1.8), (22.0, 4.0), (20.2, 5.2), (12.0, 6.2), (9.0, 6.6),
              (8.6, 7.4), (0, 7.4)], 72, "Base", angle=35)
body.append(base)
alu.append(torus(21.2, 0.55, (0, 0, 4.9), maj=96, mnr=8))                     # jonc alu
alu.append(lathe([(0, 7.3), (7.4, 7.3), (7.8, 7.8), (7.4, 8.4), (0, 8.4)], 48, "Plate"))  # plateau de pivot
# interrupteur à bascule rouge + LED
red.append(rbox((5, 3.4, 1.8), (0, -15.5, 6.2), r=0.7, seg=2, rot=(math.radians(-8), 0, 0)))
body.append(rbox((7, 5, 1.0), (0, -15.5, 5.3), r=0.4, seg=2))

# ---------------------------------------------------------------- géométrie des bras
P0 = Vector((0, 4, 16))
P1 = P0 + Vector((0, 26, 106))
P2 = P1 + Vector((0, -92, 44))

# fourche de pivot sur le socle
body.append(cyl(3.2, 8, (0, 4, 8), verts=32, bev=0.6))
for sx in (-1, 1):
    body.append(rbox((1.6, 9, 12), (sx * 5.2, 4, 13), r=0.6, seg=2))
body.append(cyl(2.4, 13, (-6.5, 4, 16), rot=(0, math.pi / 2, 0), verts=24, bev=0.4))
alu.append(knurl_knob((7.2, 4, 16), (1, 0, 0), r=3.4, h=2.4))


def rods(A, B, sep, r=1.15):
    for sx in (-sep, sep):
        body.append(cyl_between(A + X * sx, B + X * sx, r, 16))


def joint(p, w=12, r=3.4):
    body.append(cyl(r, w, p - X * w / 2, rot=(0, math.pi / 2, 0), verts=32, bev=0.6))
    alu.append(knurl_knob(p + X * (w / 2), (1, 0, 0), r=3.6, h=2.4))
    alu.append(cyl(1.2, 1.0, p - X * (w / 2 + 1.0), rot=(0, math.pi / 2, 0), verts=16, bev=0.2))


# bras inférieur : 2 tiges + entretoises
rods(P0, P1, 4.3)
d1 = (P1 - P0).normalized()
for f in (0.35, 0.7):
    body.append(cyl_between(P0 + d1 * (P1 - P0).length * f - X * 4.3, P0 + d1 * (P1 - P0).length * f + X * 4.3, 0.8, 12))
# bras supérieur : 2 tiges + levier arrière (contrepoids) au-delà du coude
d2 = (P2 - P1).normalized()
BACK = P1 - d2 * 16
rods(BACK, P2, 2.6, r=1.0)
body.append(cyl_between(BACK - X * 2.6, BACK + X * 2.6, 1.3, 12))
joint(P0, w=8.5, r=3.0)
joint(P1, w=13, r=3.4)
joint(P2, w=9, r=2.8)

# ressorts d'équilibrage du bras inférieur (du pied de fourche jusqu'au premier tiers)
for sx in (-7.2, 7.2):
    a = Vector((sx, -3, 11))
    b = P0 + d1 * 42 + X * sx
    springs.append(spring_between(a + (b - a).normalized() * 3, b - (b - a).normalized() * 3, 1.5, 0.35, 22, sides=6))
    springs.append(cyl_between(a, a + (b - a).normalized() * 3.2, 0.4, 8))
    springs.append(cyl_between(b - (b - a).normalized() * 3.2, b, 0.4, 8))
    body.append(cyl_between(b - X * (1 if sx > 0 else -1) * 2.9, b, 0.7, 10))
    body.append(cyl_between(a, Vector((sx * 0.72, -3, 11)), 0.9, 10))
# ressort du levier arrière vers le bras inférieur
sa = BACK + Vector((0, 0, -1))
sb = P1 - d1 * 40
springs.append(spring_between(sa + (sb - sa).normalized() * 2, sb - (sb - sa).normalized() * 2, 1.3, 0.3, 18, sides=6))
body.append(cyl_between(sb - X * 4.3, sb + X * 4.3, 0.7, 10))

# ---------------------------------------------------------------- tête : étrier + abat-jour
AXIS = Vector((0, -0.42, -0.91)).normalized()          # direction de la lumière
HC = P2 + Vector((0, -4, -4))                           # origine de l'abat-jour (sommet du col)
for sx in (-1, 1):
    body.append(box_between(P2 + X * sx * 4.8, HC + X * sx * 4.8 + AXIS * 6, 1.2, 3.0, r=0.4, seg=2))
shade_out = lathe([(0, 0), (3.6, 0), (4.2, -0.6), (4.2, -6), (5.4, -7.5), (9, -12), (14.5, -22), (18.6, -31),
                   (19.2, -32.2), (18.2, -32.4)], 72, "ShadeOut", angle=40)
shade_in = lathe([(17.9, -32.1), (18.0, -31.5), (14.0, -22.4), (8.6, -12.6), (5.0, -8.2), (3.8, -7.2), (0, -7.1)],
                 72, "ShadeIn", angle=40)
bulb = lathe([(0, -7.2), (2.4, -7.4), (3.0, -9.0), (5.2, -13.5), (5.6, -16.0), (4.8, -18.6), (2.8, -20.3), (0, -20.8)],
             32, "Bulb", angle=60)
bezel = torus(18.8, 0.7, (0, 0, -32.1), maj=96, mnr=8)
# ouïes d'aération sur le col
vents = [rbox((1.2, 6, 3.0), (0, 0, -3.2), r=0.3, seg=2, rot=(0, 0, TAU * i / 12)) for i in range(12)]
for v, i in zip(vents, range(12)):
    xf(v, loc=(4.2 * math.cos(TAU * i / 12 + math.pi / 2) * 0, 0, 0))
cut_ring = []
for i in range(12):
    a = TAU * i / 12
    c = rbox((1.2, 3.0, 3.2), (4.6 * math.cos(a), 4.6 * math.sin(a), -3.3), r=0.35, seg=2, rot=(0, 0, a))
    cut_ring.append(c)
for v in vents:
    bpy.data.objects.remove(v)
boolean_diff(shade_out, cut_ring)
cap = cyl(3.9, 2.0, (0, 0, -0.5), verts=32, bev=0.5)
hinge = cyl(1.6, 11.0, (-5.5, 0, -2.5), rot=(0, math.pi / 2, 0), verts=16, bev=0.3)
q = AXIS.to_track_quat("-Z", "X")
Mh = Matrix.Translation(HC) @ q.to_matrix().to_4x4()
for o in (shade_out, shade_in, bulb, bezel, cap, hinge):
    o.data.transform(Mh); o.data.update()
red += [shade_out]
white += [shade_in]
glow += [bulb]
alu += [bezel, cap]
body += [hinge]

# ---------------------------------------------------------------- câble : descend le long du bras, sort du socle
route = [P1 + Vector((-5.5, 2, -6)), P0 + d1 * 70 + Vector((-5.6, 0, 0)), P0 + d1 * 30 + Vector((-5.6, 0, 0)),
         Vector((-5.5, 8, 10)), Vector((-4, 12, 6.8)), Vector((0, 18, 4)), Vector((0, 26, 1.0)), Vector((6, 42, 1.0))]
cable = sweep(catmull(route, 10), 0.8, 10, name="Cable")
body.append(cable)
# petits clips de câble
for f in (0.3, 0.7):
    c = P0 + d1 * (P1 - P0).length * f + Vector((-5.0, 0, 0))
    t_ = torus(1.4, 0.35, (0, 0, 0), maj=16, mnr=6)
    t_.data.transform(Matrix.Translation(c) @ d1.to_track_quat("Z", "Y").to_matrix().to_4x4())
    alu.append(t_)

tagj(body, "Body", "SmoothPlastic", "16181E")
tagj(alu, "Alu", "Metal", "B8BEC8")
tagj(springs, "Springs", "Metal", "D9DDE3")
tagj(red, "Shade", "SmoothPlastic", "E53E3E")
tagj(white, "ShadeInner", "SmoothPlastic", "F2F2F5")
tagj(glow, "Bulb", "Neon", "F2F2F5")

BULB = Mh @ Vector((0, 0, -22.5))


def lamp_light():
    # repère tourné de 180° à l'export : on retourne la position et la direction
    spot((-BULB.x, -BULB.y, BULB.z), (-AXIS.x, -AXIS.y, AXIS.z), 1.2e7, angle=95, size=4)


done("DeskLamp", direction=(1.1, -0.9, 0.35), lens=50, props=lamp_light)
