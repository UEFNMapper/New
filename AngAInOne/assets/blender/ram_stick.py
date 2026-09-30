"""RamStick — barrette DDR5 debout (contacts en bas, z = 0) : PCB avec détrompeur et 2×144 contacts dorés,
dissipateur sculpté bicolore (armure graphite + inserts alu brossé, logo « A » en relief), diffuseur RGB."""
from hw_common import *

reset()
LX = 40.0
HX = LX / 2
T_PCB = 0.18                     # demi-épaisseur du PCB
Z_SP0, Z_SP1 = 2.5, 12.7         # dissipateur
KEY_X = -1.2                     # détrompeur DDR5 (légèrement décentré)

# ------------------------------------------------------------------ PCB
outline = [(-HX + 0.6, 0.0), (KEY_X - 0.22, 0.0), (KEY_X - 0.22, 1.3), (KEY_X + 0.22, 1.3), (KEY_X + 0.22, 0.0),
           (HX - 0.6, 0.0), (HX, 0.6), (HX, 1.8), (HX - 0.55, 2.2), (HX - 0.55, 2.8), (HX, 3.2), (HX, 12.2),
           (-HX, 12.2), (-HX, 3.2), (-HX + 0.55, 2.8), (-HX + 0.55, 2.2), (-HX, 1.8), (-HX, 0.6)]
pcb = prism_y(outline, -T_PCB, T_PCB)
bev(pcb, 0.04, 1, 30)
smd = []
for k in range(20):  # résistances / condensateurs CMS visibles sous le dissipateur
    x = -18.4 + k * 1.95
    if abs(x - KEY_X) < 0.8:
        continue
    for sy in (-1, 1):
        smd.append(rbox((0.5, 0.16, 0.26), (x, sy * (T_PCB + 0.08), 2.05), r=0.03, seg=1))
tag(merge([pcb] + smd), "Pcb", "SmoothPlastic", PCB)

# ------------------------------------------------------------------ contacts dorés (2 × 144)
pads = []
src = rbox((0.17, 0.03, 1.05), (0, 0, 0))
mats = []
pitch = (LX - 2.4) / 145
for k in range(145):
    x = -HX + 1.2 + k * pitch
    if abs(x - KEY_X) < 0.35:
        continue
    for sy in (-1, 1):
        mats.append(T((x, sy * (T_PCB + 0.012), 0.72)))
gold = instances(src, mats, "Gold")
tag(gold, "Contacts", "Foil", GOLD)

# ------------------------------------------------------------------ dissipateur (une face, puis miroir)
Y0, Y1, Y2 = T_PCB + 0.05, T_PCB + 0.42, T_PCB + 0.68
base = prism_y(crect(LX - 0.4, Z_SP1 - Z_SP0, (0.4, 0.4, 1.4, 1.4), (0, (Z_SP0 + Z_SP1) / 2)), Y0, Y1)
bev(base, 0.08, 2, 30)
# armure supérieure en relief avec marche anguleuse
arm = prism_y([(-HX + 0.2, 9.4), (-3.0, 9.4), (-1.2, 10.4), (HX - 0.2, 10.4), (HX - 0.2, Z_SP1 - 1.4),
               (HX - 1.6, Z_SP1), (-HX + 1.6, Z_SP1), (-HX + 0.2, Z_SP1 - 1.4)], Y1 - 0.02, Y2)
bev(arm, 0.1, 2, 30)
# coin inférieur droit sculpté + nervures verticales gravées
wedge = prism_y([(9.5, Z_SP0), (HX - 0.2, Z_SP0), (HX - 0.2, 7.6), (13.8, 7.6)], Y1 - 0.02, Y2 - 0.08)
bev(wedge, 0.08, 2, 30)
bool_op(wedge, [prism_y([(x, Z_SP0 - 1), (x + 0.28, Z_SP0 - 1), (x + 0.28, 9), (x, 9)], Y2 - 0.2, Y2 + 1)
                for x in (14.6, 15.6, 16.6, 17.6, 18.6)])
face = merge([base, arm, wedge])
texts = []
for side in (-1, 1):  # textes lisibles sur chaque face (pas de miroir)
    texts.append(side_text("ANGAINONE", 1.25, 0.12, -8.5 * -side, 5.2, Y1 - 0.02, side))
    texts.append(side_text("DDR5-8000", 0.8, 0.1, -11.0 * -side, 3.6, Y1 - 0.02, side))
# embouts du diffuseur (graphite) aux deux extrémités
caps = [rbox((0.9, 2 * Y2 + 0.1, 1.8), (sx * (HX - 0.6), 0, Z_SP1 + 0.55), r=0.18) for sx in (-1, 1)]
spreader = merge([face, mirror(face)] + caps + texts)
tag(spreader, "Spreader", "Metal", GRAPHITE_2)

# inserts alu brossé : liseré sous l'armure + logo « A »
ins = prism_y([(-HX + 0.4, 8.5), (-3.3, 8.5), (-1.5, 9.5), (HX - 0.4, 9.5), (HX - 0.4, 10.0), (-1.3, 10.0),
               (-3.1, 9.0), (-HX + 0.4, 9.0)], Y1 - 0.02, Y1 + 0.12)
bev(ins, 0.04, 1, 30)
logos = [side_text("A", 4.2, 0.18, 6.2 * -side, 5.4, Y1 - 0.04, side) for side in (-1, 1)]
tag(merge([ins, mirror(ins)] + logos), "Inserts", "Metal", ALU)

# ------------------------------------------------------------------ diffuseur RGB (profil arrondi extrudé en X)
prof = [(-Y2 + 0.05, Z_SP1 - 0.3), (Y2 - 0.05, Z_SP1 - 0.3), (Y2 - 0.05, Z_SP1 + 0.6), (Y2 - 0.25, Z_SP1 + 1.15),
        (0.35, Z_SP1 + 1.3), (-0.35, Z_SP1 + 1.3), (-Y2 + 0.25, Z_SP1 + 1.15), (-Y2 + 0.05, Z_SP1 + 0.6)]
diff = prism_x(round_profile(prof, 0.15, 2), -HX + 1.05, HX - 1.05)
tag(diff, "Diffuser", "Neon", "8B7CFF")
# fin liseré lumineux secondaire sur l'armure (les deux faces)
stripe = prism_y([(-HX + 1.8, Z_SP1 - 0.55), (HX - 1.8, Z_SP1 - 0.55), (HX - 2.1, Z_SP1 - 0.35),
                  (-HX + 2.1, Z_SP1 - 0.35)], Y2 - 0.05, Y2 + 0.04)
tag(merge([stripe, mirror(stripe)]), "Stripe", "Neon", "C084FC")

done("RamStick", camera=(0.9, -2.2, 0.9))
qa_view("RamStick_close", (1.0, -1.4, 0.4), zoom=2.4, target=(12, 0, 5))
