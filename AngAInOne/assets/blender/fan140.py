"""Fan140 — ventilateur 140 mm premium : cadre à « taille » (jupe visible entre les coins), 7 pales en
faucille avec bague de bout de pale (__Spin), stator 4 bras, patins caoutchouc, diffuseur ARGB, câble gainé."""
from hw_common import *

reset()
S, D = 16.0, 3.0          # 16 studs de côté, 3 d'épaisseur
BORE = 7.3

frame = fan_frame(S, D, BORE, corner_r=1.0, flange=0.5, shroud=7.62, struts=4, motor_r=2.3)
# connecteur ARGB 3 broches au bout du câble (même plastique que le cadre)
plug = rbox((1.1, 0.6, 0.45), (S / 2 + 1.35, -S / 2 + 2.6, 0.45), r=0.08)
bool_op(plug, [rbox((0.14, 0.14, 0.3), (S / 2 + 1.95, -S / 2 + 2.6 + dy, 0.45)) for dy in (-0.2, 0, 0.2)])
frame = merge([frame, plug])
tag(frame, "Frame", "SmoothPlastic", GRAPHITE_0)

rotor = fan_rotor(7.05, 2.35, 7, 0.95, 2.8, sweep=0.62, ring=True, thick=0.09)
tag(rotor, "Rotor", "SmoothPlastic", GRAPHITE_2, spin=True)

# badge métal fixe sur le moyeu, logo « A » en relief
badge = lathe([(0, 2.84), (1.35, 2.84), (1.4, 2.9), (1.3, 2.95), (0, 2.96)], 64)
logo = text_mesh("A", 1.6, 0.09, (0, 0.05, 2.93))
tag(badge, "Badge", "Metal", ALU)

# diffuseur ARGB : anneau avant + bande sur la jupe (visible par la taille du cadre)
ring = lathe([(7.34, 2.93), (7.95, 2.93), (7.98, 3.03), (7.8, 3.09), (7.5, 3.09), (7.36, 3.03)], 128, closed=True)
band = lathe([(7.6, 1.35), (7.72, 1.35), (7.72, 1.65), (7.6, 1.65)], 128, closed=True)
tag(merge([ring, band, logo]), "Argb", "Neon", ACCENT)

pads = fan_pads(S, D, BORE, 0.0, t=0.22)
tag(pads, "Pads", "Plastic", "3D3566")

# câble gainé : sort du moteur le long d'un bras, passe dans la taille du cadre puis vers le connecteur
a = math.pi / 4 - math.pi / 2  # bras orienté vers (+x, -y)
pts = [(2.0 * math.cos(a), 2.0 * math.sin(a), 0.55)]
for t in (0.35, 0.7, 1.0):
    r = 2.3 + (7.65 - 2.3) * t
    th = a + 0.25 * t * t
    pts.append((r * math.cos(th), r * math.sin(th), 0.62))
pts += [(7.6, -5.3, 1.0), (S / 2 + 0.2, -S / 2 + 3.4, 0.9), (S / 2 + 0.75, -S / 2 + 2.6, 0.5)]
cable = tube(pts, 0.17, 12, "Cable")
tag(cable, "Cable", "Fabric", GRAPHITE_1)

done("Fan140", camera=(1.2, -1.5, 1.6))
