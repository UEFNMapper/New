"""UsbKey — clé USB dorée à collectionner (3 studs de long), ORIGINE AU CENTRE (elle flotte et tourne en jeu).
Corps doré chanfreiné et légèrement galbé, badge incrusté avec « A » AngAInOne en relief, diode néon violette,
embout USB-A métal (coque creuse, 2 trous carrés, languette noire), anneau porte-clés passé dans le corps.
Axe long = X (embout vers +X), dessus = +Z."""
from char_common import *

new_scene()
kit = Kit()

GOLD, METAL, DARK = "D4A64A", "D8DCE3", "1E1B2E"
BX0, BX1 = -1.2, 0.36          # corps
T = 0.4                        # épaisseur du corps
Wd = 0.86                      # largeur du corps

# --- corps doré (se resserre un peu vers l'embout, dessus bombé)
body = rbox((BX1 - BX0, Wd, T), ((BX0 + BX1) / 2, 0, 0), radius=0.15, segments=5)
deform(body, lambda p: V((p.x, p.y * (1 - 0.1 * smoothstep(-0.4, BX1, p.x)),
                          p.z * (1 + 0.12 * (1 - (p.y / (Wd / 2)) ** 2)))))
# trou du porte-clés
hole = lathe([(0.13, -1), (0.13, 1)], segments=32, loc=(BX0 + 0.24, 0, 0))
boolean(body, hole)
# badge incrusté sur le dessus
pocket = rbox((0.62, 0.58, 0.2), (-0.38, 0, T / 2 + 0.06), radius=0.12, segments=4)
boolean(body, pocket)
shade(body, flat_angle=50)
kit.add("Gold", "Foil", GOLD, body)
badge = rbox((0.58, 0.54, 0.1), (-0.38, 0, T / 2 - 0.06), radius=0.1, segments=4)
kit.add("Dark", "SmoothPlastic", DARK, badge)
logo = text_mesh("A", size=0.52, extrude=0.045, bevel=0.018, loc=(-0.38, 0, T / 2 + 0.01), rot=(0, 0, 0))
kit.add("Gold", "Foil", GOLD, logo)
# petite diode néon sur le côté + filet décoratif
led = rbox((0.22, 0.05, 0.07), (0.05, -Wd / 2 * 0.93 - 0.01, 0.0), radius=0.03, segments=2)
kit.add("Led", "Neon", "8B7CFF", led)

# --- embout USB-A (coque métal creuse, 2 trous carrés, languette)
CX0, CX1 = BX1 - 0.08, BX1 + 0.92
CW, CH = 0.62, 0.24
shell = rbox((CX1 - CX0, CW, CH), ((CX0 + CX1) / 2, 0, 0), radius=0.035, segments=3)
inner = rbox((CX1 - CX0, CW - 0.07, CH - 0.07), ((CX0 + CX1) / 2 + 0.06, 0, 0), radius=0.01, segments=1)
boolean(shell, inner)
for y in (-0.13, 0.13):
    boolean(shell, rbox((0.14, 0.12, 0.3), (CX1 - 0.3, y, 0.1), radius=0.0, segments=1))
shade(shell, flat_angle=40)
kit.add("Metal", "Metal", METAL, shell)
tongue = rbox((CX1 - CX0 - 0.12, CW - 0.2, 0.06), ((CX0 + CX1) / 2, 0, -0.03), radius=0.02, segments=2)
kit.add("Dark", "SmoothPlastic", DARK, tongue)
# pistes dorées sur la languette
for k in range(4):
    kit.add("Gold", "Foil", GOLD, rbox((0.22, 0.05, 0.02), (CX1 - 0.2, -0.11 + 0.073 * k, 0.003), radius=0.005,
                                        segments=1))

# --- anneau porte-clés (vertical, passe dans le trou)
ring = torus(0.33, 0.055, (BX0 + 0.24 - 0.33, 0, 0), rot=(math.pi / 2, 0, 0), major=48, minor=12)
kit.add("Gold", "Foil", GOLD, ring)

# centre la boîte englobante sur l'origine
objs = kit.objects()
co = [v.co for o in objs for v in o.data.vertices]
mn = V((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
mx = V((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
ctr = (mn + mx) / 2
k = 3.0 / (mx - mn).x  # 3 studs de long
for o in objs:
    xf_matrix(o, Matrix.Scale(k, 4) @ Matrix.Translation(-ctr))
print("taille", (mx - mn) * k)

kit.build()
finish("UsbKey", camera=cam((0.9, -1.8, 1.4)), samples=64)
