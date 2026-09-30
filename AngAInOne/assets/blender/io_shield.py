"""IoShield — panneau I/O arrière pré-monté (debout, face visible vers -Y) : 2 connecteurs d'antenne Wi-Fi
(SMA dorés filetés), boutons BIOS/CMOS, USB-A ×10, USB-C ×4, HDMI, DisplayPort, RJ45 5G avec LED,
5 jacks audio + optique. Les ports sont de vrais volumes (coques métal, languettes, contacts)."""
from hw_common import *

reset()
PW, PH = 59.0, 16.0                  # plaque (x, z)
YP = 0.0                             # face avant de la plaque (les ports partent vers +Y)
plate = prism_y(round_profile(crect(PW, PH, 0.0, (0, PH / 2)), 1.2, 3), YP, YP + 0.45)
cut = []
shells, plastic, tongues, gold, leds, rings, labels = [], [], [], [], [], [], []


def opening(x, z, w, h, r=0.25):
    cut.append(prism_y(round_profile(crect(w + 0.3, h + 0.3, 0.0, (x, z)), r + 0.1, 2), YP - 1, YP + 1))


def shell(x, z, w, h, depth=5.0, r=0.25, t=0.12):
    s = prism_y(round_profile(crect(w, h, 0.0, (x, z)), r, 2), YP + 0.05, YP + depth)
    bool_op(s, prism_y(round_profile(crect(w - 2 * t, h - 2 * t, 0.0, (x, z)), max(r - t, 0.05), 2), YP - 1, YP + depth - 0.6))
    shells.append(s)
    opening(x, z, w, h, r)


def usb_a(x, z):
    w, h = 4.4, 1.75
    shell(x, z, w, h, r=0.12)
    tongues.append(rbox((w - 0.7, 3.6, 0.55), (x, YP + 2.7, z + 0.28), r=0.05, seg=1))
    for k in range(4):
        gold.append(rbox((0.45, 2.0, 0.04), (x - 1.2 + k * 0.8, YP + 2.2, z + 0.0)))
    plastic.append(rbox((w - 0.3, 0.3, h - 0.3), (x, YP + 4.6, z)))


def usb_c(x, z):
    w, h = 3.1, 1.05
    shell(x, z, w, h, r=0.5)
    plastic.append(rbox((w - 1.0, 3.2, 0.28), (x, YP + 2.6, z), r=0.1, seg=1))
    plastic.append(rbox((w - 0.3, 0.3, h - 0.2), (x, YP + 4.6, z)))


def hdmi(x, z):
    w, h = 5.2, 1.7
    out = [(x - w / 2 + 0.6, z - h / 2), (x + w / 2 - 0.6, z - h / 2), (x + w / 2, z - h / 2 + 0.55), (x + w / 2, z + h / 2),
           (x - w / 2, z + h / 2), (x - w / 2, z - h / 2 + 0.55)]
    s = prism_y(out, YP + 0.05, YP + 5.0)
    inner = [(px + (0.12 if px < x else -0.12), pz + (0.12 if pz < z else -0.12)) for px, pz in out]
    bool_op(s, prism_y(inner, YP - 1, YP + 4.4))
    shells.append(s)
    cut.append(prism_y([(px + (-0.15 if px < x else 0.15), pz + (-0.15 if pz < z else 0.15)) for px, pz in out], YP - 1, YP + 1))
    plastic.append(rbox((w - 1.2, 3.4, 0.45), (x, YP + 2.6, z + 0.1), r=0.05, seg=1))


def dp(x, z):
    w, h = 5.9, 1.8
    out = [(x - w / 2, z - h / 2), (x + w / 2, z - h / 2), (x + w / 2, z + h / 2 - 0.6), (x + w / 2 - 0.6, z + h / 2),
           (x - w / 2, z + h / 2)]
    s = prism_y(out, YP + 0.05, YP + 5.0)
    inner = [(px + (0.12 if px < x else -0.12), pz + (0.12 if pz < z else -0.12)) for px, pz in out]
    bool_op(s, prism_y(inner, YP - 1, YP + 4.4))
    shells.append(s)
    cut.append(prism_y([(px + (-0.15 if px < x else 0.15), pz + (-0.15 if pz < z else 0.15)) for px, pz in out], YP - 1, YP + 1))
    plastic.append(rbox((w - 1.4, 3.4, 0.45), (x, YP + 2.6, z), r=0.05, seg=1))


def rj45(x, z):
    w, h = 5.9, 4.8
    s = rbox((w + 0.4, 5.6, h + 0.4), (x, YP + 2.9, z), r=0.2, seg=1)
    hole = prism_y([(x - w / 2 + 0.2, z - h / 2 + 0.2), (x - 1.0, z - h / 2 + 0.2), (x - 1.0, z - h / 2 - 0.3),
                    (x + 1.0, z - h / 2 - 0.3), (x + 1.0, z - h / 2 + 0.2), (x + w / 2 - 0.2, z - h / 2 + 0.2),
                    (x + w / 2 - 0.2, z + h / 2 - 0.2), (x - w / 2 + 0.2, z + h / 2 - 0.2)], YP - 1, YP + 4.8)
    bool_op(s, hole)
    shells.append(s)
    cut.append(prism_y(crect(w + 0.6, h + 0.6, 0.3, (x, z)), YP - 1, YP + 1))
    plastic.append(rbox((w - 0.4, 0.4, h - 0.4), (x, YP + 4.9, z), r=0.1, seg=1))
    for k in range(8):
        gold.append(rbox((0.22, 2.2, 0.1), (x - 1.75 + k * 0.5, YP + 3.4, z + h / 2 - 0.45), rot=(math.radians(-25), 0, 0)))
    for sx in (-1, 1):
        leds.append(rbox((0.9, 0.3, 0.6), (x + sx * (w / 2 - 0.7), YP - 0.05, z + h / 2 - 0.5), r=0.08, seg=1))


def jack(x, z, ring=True):
    plastic.append(lathe([(0.55, -0.6), (1.25, -0.6), (1.35, -0.4), (1.35, 5.0), (0.55, 5.0)], 32, closed=True,
                         loc=(x, YP, z), rot=(-math.pi / 2, 0, 0)))
    gold.append(lathe([(0.42, -0.62), (0.58, -0.62), (0.58, 2.0), (0.42, 2.0)], 24, closed=True, loc=(x, YP, z),
                      rot=(-math.pi / 2, 0, 0)))
    if ring:
        rings.append(lathe([(1.36, -0.45), (1.5, -0.45), (1.5, -0.15), (1.36, -0.15)], 32, closed=True, loc=(x, YP, z),
                           rot=(-math.pi / 2, 0, 0)))
    cut.append(rcyl(1.42, 2, (x, YP, z), verts=32, rot=(math.pi / 2, 0, 0)))


def sma(x, z):
    gold.append(rcyl(1.05, 0.6, (x, YP - 0.3, z), verts=6, rot=(math.pi / 2, 0, 0), bevel_w=0.08))
    prof = [(0, -3.0), (0.62, -3.0)]
    for k in range(9):  # filetage
        y = -2.8 + k * 0.28
        prof += [(0.72, y), (0.62, y + 0.14)]
    prof += [(0.62, -0.5), (0, -0.5)]
    thr = lathe([(r, zz) for r, zz in prof], 20, loc=(x, YP, z), rot=(-math.pi / 2, 0, 0))
    bool_op(thr, rcyl(0.3, 2, (x, YP - 3.0, z), verts=12, rot=(math.pi / 2, 0, 0)))
    gold.append(thr)
    plastic.append(rcyl(0.26, 0.4, (x, YP - 2.3, z), verts=12, rot=(math.pi / 2, 0, 0)))
    cut.append(rcyl(1.1, 2, (x, YP, z), verts=24, rot=(math.pi / 2, 0, 0)))


def button(x, z, label):
    plastic.append(lathe([(0, -0.4), (0.8, -0.4), (0.9, -0.2), (0.9, 1.0), (0, 1.0)], 24, loc=(x, YP, z),
                         rot=(-math.pi / 2, 0, 0)))
    cut.append(rcyl(1.0, 2, (x, YP, z), verts=24, rot=(math.pi / 2, 0, 0)))
    labels.append(text_mesh(label, 0.75, 0.1, (x, YP - 0.05, z - 1.6), (math.pi / 2, 0, 0)))


# --- disposition (x vers la droite vu de face, z vers le haut)
sma(-26.0, 4.0); sma(-26.0, 12.0)
button(-21.8, 11.4, "BIOS"); button(-21.8, 6.4, "CMOS")
dp(-15.8, 13.3); hdmi(-15.8, 9.6); usb_c(-15.8, 5.9); usb_c(-15.8, 3.0)
for x in (-9.2, -3.2):
    usb_a(x, 3.6); usb_a(x, 6.4); usb_c(x, 9.5); usb_a(x, 12.9)
rj45(3.4, 4.2); usb_a(3.4, 9.8); usb_a(3.4, 12.8)
usb_a(9.6, 3.6); usb_a(9.6, 6.4); usb_c(9.6, 9.5); usb_a(9.6, 12.9)
for zz in (3.6, 7.8, 12.0):
    jack(17.4, zz)
jack(22.0, 12.0); jack(22.0, 7.8)
opt = rbox((2.6, 5.0, 2.2), (22.0, YP + 2.4, 3.6), r=0.3, seg=2)       # S/PDIF optique
bool_op(opt, rbox((1.0, 2.0, 0.8), (22.0, YP, 3.6), r=0.2))
plastic.append(opt)
cut.append(prism_y(crect(2.8, 2.4, 0.3, (22.0, 3.6)), YP - 1, YP + 1))
# nervure de bord + libellés
bool_op(plate, cut)
bev(plate, 0.08, 1, 35)
ridge = prism_y(round_profile(crect(PW - 1.0, PH - 1.0, 0.0, (0, PH / 2)), 0.9, 3), YP - 0.25, YP + 0.05)
bool_op(ridge, prism_y(round_profile(crect(PW - 2.0, PH - 2.0, 0.0, (0, PH / 2)), 0.5, 3), YP - 1, YP + 1))
for t, x, z in (("WIFI", -26.0, 8.0), ("DP", -12.2, 13.3), ("10G", -6.2, 14.9), ("5G LAN", 3.4, 1.0), ("20G", 9.6, 14.9)):
    labels.append(text_mesh(t, 0.7, 0.1, (x, YP - 0.05, z), (math.pi / 2, 0, 0)))
tag(merge([plate, ridge]), "Plate", "Metal", GRAPHITE_2)
tag(merge(shells + labels), "Shells", "Metal", ALU)
tag(merge(plastic), "Plastic", "SmoothPlastic", GRAPHITE_0)
tag(merge(tongues), "Tongues", "SmoothPlastic", "63B3ED")
tag(merge(gold), "Gold", "Foil", GOLD)
tag(merge(leds), "LanLed", "Neon", "48BB78")
logo = text_mesh("A", 2.4, 0.12, (27.3, YP - 0.05, 12.8), (math.pi / 2, 0, 0))
tag(merge(rings + [logo]), "Accent", "Neon", ACCENT)
done("IoShield", camera=(0.7, -1.8, 0.6))
qa_view("IoShield_close", (0.5, -1.6, 0.5), zoom=2.4, target=(-10, 0, 8))
