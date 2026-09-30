"""WebcamLight — anneau lumineux de streaming sur trépied avec webcam au centre (≈122 studs).

Trépied pliant (pieds galbés, patins, rotule), mât télescopique à bague de serrage, fourche en U à
molettes, anneau (boîtier + diffuseur néon blanc), support central, webcam (verre de lentille, bague
alu, LED rouge d'activité, micros), câble.
Modélisé façade vers −Y (lumière vers le streamer) puis tourné à l'export."""
from room_common import *

reset()
black, metal, glow, lens, cam, red, rubber = [], [], [], [], [], [], []
RC = Vector((0, 0, 99))           # centre de l'anneau
R_IN, R_OUT = 18.0, 26.0

# ---------------------------------------------------------------- trépied
hub = lathe([(0, 13), (3.4, 13), (4.2, 14), (4.2, 20), (3.4, 21.5), (0, 21.5)], 32, "Hub")
black.append(hub)
for i in range(3):
    a = TAU * i / 3 + math.pi / 2 + math.pi / 3
    d = Vector((math.cos(a), math.sin(a), 0))
    pts = [Vector((0, 0, 17)) + d * 3, Vector((0, 0, 12)) + d * 14, Vector((0, 0, 4)) + d * 26, Vector((0, 0, 1.3)) + d * 31]
    leg = sweep(catmull(pts, 8), 1.2, 12, name="Leg", radius_fn=lambda f: 1.35 - 0.35 * f)
    black.append(leg)
    rubber.append(uvsphere(1.6, Vector((0, 0, 1.2)) + d * 31.5, 16, 8, scale=(1.2, 1.2, 0.8)))
    # entretoise
    black.append(cyl_between(Vector((0, 0, 9)) + d * 3.5, Vector((0, 0, 11)) + d * 14, 0.45, 8))
metal.append(cyl(1.9, 44, (0, 0, 21), verts=24))
metal.append(lathe([(1.8, 64), (2.6, 64), (2.9, 64.6), (2.9, 67.2), (2.6, 67.8), (1.8, 67.8)], 32, "Collar"))
metal.append(cyl(1.45, 13, (0, 0, 67), verts=24))
black.append(cyl(0.7, 4, (0, 0, 66), rot=(0, math.pi / 2, 0), verts=12))
metal.append(knurl_knob((4, 0, 66), (1, 0, 0), r=1.8, h=1.2, teeth=8))

# ---------------------------------------------------------------- fourche en U + rotules
U = catmull([(-R_OUT - 2.2, 0, RC.z), (-R_OUT - 2.2, 0, RC.z - 16), (-R_OUT + 2, 0, 80), (-6, 0, 80), (6, 0, 80),
             (R_OUT - 2, 0, 80), (R_OUT + 2.2, 0, RC.z - 16), (R_OUT + 2.2, 0, RC.z)], 8)
fork = sweep(U, 1.1, 12, name="Fork")
xf(fork, scale=(1, 1.8, 1))
black.append(fork)
black.append(cyl(2.4, 4, (0, 0, 78.2), verts=24, bev=0.6))
for sx in (-1, 1):
    black.append(cyl_between((sx * (R_OUT - 0.5), 0, RC.z), (sx * (R_OUT + 3.6), 0, RC.z), 1.8, 20))
    metal.append(knurl_knob((sx * (R_OUT + 3.6), 0, RC.z), (sx, 0, 0), r=2.6, h=1.6, teeth=10))

# ---------------------------------------------------------------- anneau : boîtier + diffuseur
prof = chain(arc(R_OUT - 1.4, 1.4, 1.4, 0, math.pi / 2, 4), arc(R_IN + 1.4, 1.4, 1.4, math.pi / 2, math.pi, 4),
             arc(R_IN + 1.4, -1.6, 1.4, math.pi, 1.5 * math.pi, 4), arc(R_OUT - 1.4, -1.6, 1.4, 1.5 * math.pi, TAU, 4))
housing = lathe(prof + [prof[0]], 96, "Ring", angle=50)
diff = lathe([(R_IN + 1.2, 2.2), (R_IN + 1.5, 2.95), (R_OUT - 1.5, 2.95), (R_OUT - 1.2, 2.2)], 128, "Diffuser")
# boutons de réglage (luminosité / température) sur le boîtier, en bas à droite
btns = []
for k in range(3):
    a = math.radians(-60 + k * 9)
    btns.append(cyl(0.9, 0.9, ((R_OUT - 0.8) * math.cos(a), (R_OUT - 0.8) * math.sin(a), -2.4), rot=(math.pi, 0, 0), verts=12))
for o in [housing, diff] + btns:
    o.data.transform(Matrix.Translation(RC) @ Matrix.Rotation(math.pi / 2, 4, "X"))
black.append(housing)
glow.append(diff)
metal += btns

# ---------------------------------------------------------------- support central + webcam
black.append(cyl_between(RC + Vector((0, 1.0, -R_IN - 1.0)), RC + Vector((0, 1.0, -4.5)), 0.8, 12))
black.append(uvsphere(1.5, RC + Vector((0, 1.0, -4.3)), 16, 8))
cam_body = rbox((15, 4.6, 4.8), (0, 0, 0), r=2.2, seg=5)
cam_front = rbox((12.6, 0.3, 3.6), (0, -2.3, 0), r=1.4, seg=3)
lens_ring = cyl(1.75, 0.6, (0, -2.25, 0), rot=(math.pi / 2, 0, 0), verts=32, bev=0.2)
lens_glass = lathe([(0, 0.0), (1.3, 0.0), (1.2, 0.35), (0.6, 0.55), (0, 0.6)], 32, "Lens")
xf(lens_glass, rot=(math.pi / 2, 0, 0))
xf(lens_glass, loc=(0, -2.75, 0))
led = cyl(0.3, 0.3, (3.0, -2.5, 0.5), rot=(math.pi / 2, 0, 0), verts=12)
mics = [cyl(0.18, 0.4, (sx * 5.2, -2.45, 0.2 * k), rot=(math.pi / 2, 0, 0), verts=6) for sx in (-1, 1) for k in (-1, 0, 1)]
logo = text_mesh("A", 1.6, 0.15, res=2)
xf(logo, rot=(math.pi / 2, 0, 0))
xf(logo, loc=(-3.4, -2.45, -0.6))
for o in [cam_body, cam_front, lens_ring, lens_glass, led, logo] + mics:
    xf(o, loc=RC + Vector((0, 0.2, 0)))
cam += [cam_body]
black += [cam_front] + mics
metal += [lens_ring, logo]
lens.append(lens_glass)
red.append(led)

# ---------------------------------------------------------------- câble
route = [RC + Vector((6, 1.5, -R_OUT + 0.5)), RC + Vector((5, 2.2, -R_OUT - 3)), Vector((2.4, 2.2, 74)), Vector((2.6, 2.3, 50)),
         Vector((2.8, 2.4, 24)), Vector((4, 5, 12)), Vector((6, 12, 1.0)), Vector((10, 30, 0.8))]
black.append(sweep(catmull(route, 8), 0.6, 8, name="Cable"))

tagj(black, "Body", "SmoothPlastic", "16181E")
tagj(metal, "Metal", "Metal", "B8BEC8")
tagj(glow, "Light", "Neon", "F2F2F5")
tagj(cam, "Webcam", "SmoothPlastic", "22252E")
tagj(lens, "Lens", "Glass", "0B0C10")
tagj(red, "Led", "Neon", "E53E3E")
tagj(rubber, "Feet", "Plastic", "22252E")

done("WebcamLight", direction=(0.8, -1.2, 0.4), lens=50)
