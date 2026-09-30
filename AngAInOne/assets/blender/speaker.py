"""Speaker — enceinte de bureau (bibliothèque) ≈ 62 × 66 × 110 studs.

Caisson noyer arrondi, façade noire en retrait, boomer (bague alu vissée, suspension caoutchouc,
membrane à nervures, ogive alu), tweeter à dôme dans un guide d'ondes, évent frontal évasé,
anneau RGB autour du boomer, LED, logo, pieds découplants, borniers à l'arrière.
Modélisée façade vers −Y puis tournée à l'export."""
from room_common import *

reset()
W, D, H = 62.0, 66.0, 110.0
FEET = 1.6
YF = -D / 2                        # plan de façade
wood, baffle, metal, cone, rubber, glow = [], [], [], [], [], []

# ---------------------------------------------------------------- caisson + façade
cab = rbox((W, D - 2.0, H), (0, 1.0, FEET + H / 2), r=4.5, seg=5)
wood.append(cab)
front = rbox((W - 3.0, 4.0, H - 3.0), (0, YF + 1.2, FEET + H / 2), r=1.6, seg=3)
WZ, TZ = FEET + 40.0, FEET + 86.0
cut = [cyl(18.6, 20, (0, YF - 5, WZ), rot=(-math.pi / 2, 0, 0), verts=72),
       cyl(8.0, 20, (0, YF - 5, TZ), rot=(-math.pi / 2, 0, 0), verts=48)]
port = extrude(rounded_rect(34, 5.0, 2.5, 6), -12, 12, "Port")
xf(port, rot=(math.pi / 2, 0, 0))
xf(port, loc=(0, YF, FEET + 12.5))
cut.append(port)
boolean_diff(front, cut)
# même découpe dans le caisson (sinon on verrait le bois derrière les membranes)
cut2 = [cyl(18.2, 13, (0, YF - 1, WZ), rot=(-math.pi / 2, 0, 0), verts=72),
        cyl(7.6, 8, (0, YF - 1, TZ), rot=(-math.pi / 2, 0, 0), verts=48)]
p2 = extrude(rounded_rect(34, 5.0, 2.5, 6), -8, 8, "Port2")
xf(p2, rot=(math.pi / 2, 0, 0))
xf(p2, loc=(0, YF + 5, FEET + 12.5))
cut2.append(p2)
boolean_diff(cab, cut2)
bevel_all(front, 0.35, 2, angle=40)
baffle.append(front)
# fond sombre derrière les haut-parleurs et l'évent
baffle.append(cyl(18.4, 1.0, (0, YF + 11.0, WZ), rot=(-math.pi / 2, 0, 0), verts=48))
baffle.append(cyl(7.8, 1.0, (0, YF + 6.0, TZ), rot=(-math.pi / 2, 0, 0), verts=32))
baffle.append(rbox((35, 1.0, 6.0), (0, YF + 12.5, FEET + 12.5), r=0.4, seg=1))
# lèvres évasées de l'évent
lip = sweep([(x, 0, 0) for x in (-14.5, 14.5)], 1.0, 12, name="PortLip")
for sy in (-1, 1):
    l = dup(lip)
    xf(l, loc=(0, YF - 0.8, FEET + 12.5 + sy * 2.6))
    baffle.append(l)
bpy.data.objects.remove(lip)


def driver_part(profile, segs, z, name, angle=40):
    o = lathe(profile, segs, name, angle=angle)
    xf(o, rot=(math.pi / 2, 0, 0))          # axe du profil (+Z) → vers l'avant (−Y)
    xf(o, loc=(0, YF - 0.8, z))
    return o


# ---------------------------------------------------------------- boomer
metal.append(driver_part([(18.4, -1.2), (18.4, 0.5), (19.2, 1.3), (22.6, 1.3), (23.6, 0.7), (23.8, -0.6)], 96, WZ, "Trim"))
for k in range(6):
    a = TAU * k / 6 + math.pi / 6
    s = cyl(0.95, 0.8, (21.0 * math.cos(a), YF - 2.1, WZ + 21.0 * math.sin(a)), rot=(math.pi / 2, 0, 0), verts=16, bev=0.25)
    hexs = cyl(0.45, 2.0, (21.0 * math.cos(a), YF - 3.5, WZ + 21.0 * math.sin(a)), rot=(-math.pi / 2, 0, 0), verts=6)
    boolean_diff(s, hexs)
    metal.append(s)
rubber.append(driver_part([(18.6, -1.6)] + [(16.6 + 1.9 * math.cos(a), -1.6 + 1.9 * math.sin(a)) for a in
                                           [math.pi * k / 12 for k in range(13)]] + [(14.5, -1.9)], 96, WZ, "Surround", 60))
prof = [(14.9, -1.8)]
for k in range(1, 25):
    f = k / 24
    r = 14.9 - f * 9.2
    zz = -1.8 - 6.2 * f ** 0.9 + (0.18 if k % 4 == 2 else 0.0)   # nervures concentriques
    prof.append((r, zz))
prof += [(5.7, -8.2), (5.4, -8.6)]
cone.append(driver_part(prof, 96, WZ, "Cone", 50))
metal.append(driver_part([(5.6, -8.6), (5.5, -6.8), (4.6, -4.4), (3.0, -2.6), (1.2, -1.9), (0, -1.8)], 48, WZ, "Plug", 60))
glow.append(torus(25.3, 0.55, (0, YF - 0.5, WZ), rot=(math.pi / 2, 0, 0), maj=96, mnr=8))

# ---------------------------------------------------------------- tweeter
baffle.append(driver_part([(7.8, -1.0), (8.2, 0.4), (9.8, 1.0), (11.0, 0.9), (11.3, 0.0), (11.3, -1.0)], 64, TZ, "Flange"))
baffle.append(driver_part([(8.0, -0.6), (6.0, -1.6), (4.4, -2.4), (4.0, -2.8)], 64, TZ, "Waveguide"))
metal.append(driver_part([(4.1, -2.8), (3.9, -1.9), (3.2, -1.0), (2.0, -0.4), (0, -0.1)], 48, TZ, "Dome", 60))
metal.append(driver_part([(4.6, -2.8), (4.6, -2.3), (4.1, -2.3)], 48, TZ, "DomeRing"))
# grille de protection du dôme (3 barreaux)
for a in (0, math.pi / 3, 2 * math.pi / 3):
    metal.append(cyl_between((4.4 * math.cos(a), YF - 3.9, TZ + 4.4 * math.sin(a)),
                             (-4.4 * math.cos(a), YF - 3.9, TZ - 4.4 * math.sin(a)), 0.18, 6))

# ---------------------------------------------------------------- détails
led = cyl(0.6, 0.8, (W / 2 - 8.5, YF - 1.2, FEET + 4.8), rot=(math.pi / 2, 0, 0), verts=12)
glow.append(led)
lg = text_mesh("AngaTV", 3.2, 0.5, bevel_d=0.06, res=2)
xf(lg, rot=(math.pi / 2, 0, 0))
xf(lg, loc=(0, YF - 0.6, FEET + 4.2))
metal.append(lg)
# pieds découplants
for sx in (-1, 1):
    for sy in (-1, 1):
        rubber.append(cyl(3.2, FEET + 0.3, (sx * (W / 2 - 7), sy * (D / 2 - 8), 0), verts=24, bev=0.4))
# borniers + plaque arrière
baffle.append(rbox((22, 1.2, 26), (0, D / 2 + 0.4, FEET + 22), r=1.0, seg=2))
for sx, col in ((-5, "red"), (5, "black")):
    metal.append(cyl(1.8, 5.0, (sx, D / 2 + 0.8, FEET + 18), rot=(-math.pi / 2, 0, 0), verts=6 if False else 24, bev=0.3))
    metal.append(cyl(0.7, 2.0, (sx, D / 2 + 5.6, FEET + 18), rot=(-math.pi / 2, 0, 0), verts=12))
rear_port = lathe([(6.0, 0), (6.0, 0.8), (7.2, 1.6), (7.6, 1.2), (7.0, -0.2), (5.4, -1.0), (5.4, -8)], 48, "RearPort")
xf(rear_port, rot=(-math.pi / 2, 0, 0))
xf(rear_port, loc=(0, D / 2 + 0.1, FEET + 70))
baffle.append(rear_port)

tagj(wood, "Cabinet", "Wood", "5A3E2B")
tagj(baffle, "Baffle", "SmoothPlastic", "16181E")
tagj(metal, "Metal", "Metal", "B8BEC8")
tagj(cone, "Cone", "SmoothPlastic", "2A2D38")
tagj(rubber, "Rubber", "Plastic", "22252E")
tagj(glow, "Glow", "Neon", "8B7CFF")

done("Speaker", direction=(0.8, -1.2, 0.45), lens=50)
