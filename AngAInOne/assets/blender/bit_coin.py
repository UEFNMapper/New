"""BitCoin — l'orbe « Bit » à collectionner, 2.5 studs de diamètre, ORIGINE AU CENTRE de la sphère.
Sphère de verre violette, puce-cœur (plaque sombre + broches dorées + « 10 » néon sur chaque face) qui tourne
à l'intérieur (pièces __Spin, pivot = centre), anneau métal équatorial avec 4 petites perles."""
from char_common import *

new_scene()
kit = Kit()

R = 1.25
glass = qsphere(R, (0, 0, 0), level=4, name="Orb")
kit.add("Orb", "Glass", "8B7CFF", glass)

# --- puce-cœur (tourne autour de l'axe vertical)
chip = rbox((0.9, 0.2, 0.9), (0, 0, 0), radius=0.1, segments=4)
kit.add("Chip", "SmoothPlastic", "1E1B2E", chip, spin=True, pivot=(0, 0, 0))
pins = []
for k in range(4):
    t = -0.3 + 0.2 * k
    for sx in (-1, 1):
        pins.append(rbox((0.16, 0.08, 0.07), (sx * 0.52, 0, t), radius=0.025, segments=2))
        pins.append(rbox((0.07, 0.08, 0.16), (t, 0, sx * 0.52), radius=0.025, segments=2))
kit.add("Pins", "Foil", "E8C35A", pins, spin=True, pivot=(0, 0, 0))
glyphs = [text_mesh("10", size=0.52, extrude=0.03, bevel=0.012, loc=(0, -0.12, -0.01)),
          text_mesh("01", size=0.52, extrude=0.03, bevel=0.012, loc=(0, 0.12, -0.01), rot=(math.pi / 2, 0, math.pi))]
halo = torus(0.36, 0.03, (0, -0.105, 0), rot=(math.pi / 2, 0, 0), major=40, minor=6)
halo2 = torus(0.36, 0.03, (0, 0.105, 0), rot=(math.pi / 2, 0, 0), major=40, minor=6)
kit.add("Core", "Neon", "B9A8FF", glyphs, halo, halo2, spin=True, pivot=(0, 0, 0))

# --- anneau métal équatorial + perles
ring = lathe([(R + 0.02, -0.07), (R + 0.1, -0.06), (R + 0.13, 0.0), (R + 0.1, 0.06), (R + 0.02, 0.07)],
             segments=96, close_bottom=False, close_top=False)
bmr = bmesh.new(); bmr.from_mesh(ring.data)
bmesh.ops.bridge_loops(bmr, edges=[e for e in bmr.edges if e.is_boundary])
bmr.to_mesh(ring.data); bmr.free()
shade(ring)
beads = [qsphere(0.09, (math.cos(a) * (R + 0.13), math.sin(a) * (R + 0.13), 0), level=2)
         for a in (0.4, 0.4 + math.pi / 2, 0.4 + math.pi, 0.4 + 3 * math.pi / 2)]
kit.add("Ring", "Metal", "C9CED6", ring, beads)

kit.build()
finish("BitCoin", camera=cam((0.5, -2.2, 0.9)), samples=96)
