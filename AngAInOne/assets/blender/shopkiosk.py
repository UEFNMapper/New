"""ShopKiosk — kiosque boutique / terminal de vente (échelle joueur, ≈10 studs).

Comptoir noir à vitrine (verre, étagère, gemmes néon, piles de pièces d'or), plan de travail alu,
terminal de paiement, colonne arrière avec `Screen` (face −Z Roblox) et cadre néon, auvent bombé à
rayures violettes/blanches avec lambrequin festonné, jambes de force, enseigne « SHOP » néon.
Modélisé façade vers −Y puis tourné à l'export."""
from room_common import *

reset()
body, alu, glass, glow, glow_red, gold, stripe_p, stripe_w = [], [], [], [], [], [], [], []
W = 7.0

# ---------------------------------------------------------------- comptoir + vitrine
cab = rbox((W, 3.4, 4.6), (0, 0, 2.6), r=0.18, seg=3)
win = rbox((5.8, 1.4, 2.7), (0, -1.45, 2.9), r=0.15, seg=2)
boolean_diff(cab, win)
body.append(cab)
body.append(rbox((W - 0.4, 3.0, 0.32), (0, 0.05, 0.16), r=0.05, seg=1))
glass.append(rbox((5.9, 0.06, 2.8), (0, -1.66, 2.9), r=0.03, seg=1))
alu.append(rbox((5.7, 0.9, 0.08), (0, -1.1, 2.75), r=0.02, seg=1))                 # étagère
# gemmes (octaèdres) et piles de pièces
for k, x in enumerate((-2.2, -1.1, 0.0, 1.1, 2.2)):
    for (zs, tgt) in ((1.75, glow if k % 2 == 0 else glow_red), (3.1, glow_red if k % 2 == 0 else glow)):
        g = uvsphere(0.32, (0, 0, 0), 4, 2, scale=(1, 1, 1.4))
        xf(g, rot=(0, 0, math.pi / 4 + k * 0.3))
        xf(g, loc=(x, -1.05, zs + 0.34))
        shade_flat(g)
        tgt.append(g)
    for c in range(3 + k % 3):
        gold.append(cyl(0.26, 0.09, (x + 0.45, -0.95, 1.6 + c * 0.1), verts=12))
        gold.append(cyl(0.26, 0.09, (x + 0.45, -0.95, 2.95 + c * 0.1), verts=12))
# plan de travail + bandeau lumineux
alu.append(rbox((W + 0.4, 3.9, 0.22), (0, -0.2, 5.0), r=0.08, seg=2))
glow.append(rbox((W + 0.2, 0.06, 0.08), (0, -2.16, 4.93), r=0.02, seg=1))

# terminal de paiement (à droite)
tp = rbox((0.9, 1.3, 0.25), (0, 0, 0), r=0.08, seg=2)
tps = rbox((0.6, 0.02, 0.45), (0, 0.0, 0.0), r=0.02, seg=1)
xf(tp, rot=(math.radians(25), 0, 0)); xf(tp, loc=(2.6, -1.2, 5.35))
xf(tps, rot=(math.radians(25 - 90), 0, 0)); xf(tps, loc=(2.6, -1.25, 5.52))
body.append(tp); glow.append(tps)
body.append(rbox((0.4, 0.5, 0.3), (2.6, -0.95, 5.2), r=0.06, seg=1))

# ---------------------------------------------------------------- colonne écran
tower = rbox((W, 0.9, 4.2), (0, 1.2, 7.2), r=0.2, seg=3)
# (haut de colonne en z = 9.3, sous l'enseigne)
body.append(tower)
scr = box((5.4, 0.04, 3.1), (0, 0.73, 7.35))
tag(scr, "Screen", "SmoothPlastic", "0B0C10")
scr.data.name = scr.name
for z in (5.72, 8.98):
    glow.append(rbox((5.7, 0.05, 0.07), (0, 0.72, z), r=0.02, seg=1))
for x in (-2.83, 2.83):
    glow.append(rbox((0.07, 0.05, 3.33), (x, 0.72, 7.35), r=0.02, seg=1))

# ---------------------------------------------------------------- auvent rayé bombé + lambrequin
N = 8
Y0, Z0, Y1, Z1 = 1.6, 9.0, -2.7, 8.3
AW = W + 0.8
for i in range(N):
    x0 = -AW / 2 + AW * i / N
    x1 = x0 + AW / N

    def sheet(u, v, x0=x0, x1=x1):
        x = x0 + (x1 - x0) * u
        y = Y0 + (Y1 - Y0) * v
        z = Z0 + (Z1 - Z0) * v + 0.35 * math.sin(math.pi * v) + 0.06 * math.sin(math.pi * u)
        return (x, y, z)
    s = grid_surface(sheet, 4, 10, name="Stripe", angle=50)
    solidify(s, 0.05, 0.0)
    # feston : demi-disque qui pend au bord avant
    fl = [(x0 + (x1 - x0) * 0.5 + (x1 - x0) * 0.5 * math.cos(math.pi + math.pi * k / 10),
           -0.42 * math.sin(math.pi * k / 10)) for k in range(11)]
    flap = extrude([(p[0], p[1]) for p in fl], -0.025, 0.025, "Flap", angle=40)
    flap.data.transform(Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))  # plan XZ
    xf(flap, loc=(0, Y1 - 0.01, Z1 + 0.02))
    band = rbox((x1 - x0, 0.05, 0.35), ((x0 + x1) / 2, Y1 - 0.01, Z1 + 0.16), r=0.0)
    (stripe_p if i % 2 == 0 else stripe_w).extend([s, flap, band])
# barre d'auvent + jambes de force
alu.append(cyl_between((-AW / 2 - 0.1, Y1 + 0.03, Z1 + 0.33), (AW / 2 + 0.1, Y1 + 0.03, Z1 + 0.33), 0.07, 12))
alu.append(cyl_between((-AW / 2, Y0, Z0 - 0.05), (AW / 2, Y0, Z0 - 0.05), 0.1, 12))
for sx in (-1, 1):
    alu.append(cyl_between((sx * (W / 2 - 0.3), 1.2, 7.4), (sx * (AW / 2 - 0.2), Y1 + 0.4, Z1 + 0.12), 0.06, 10))
    alu.append(uvsphere(0.12, (sx * (W / 2 - 0.3), 0.75, 7.4), 12, 6))

# ---------------------------------------------------------------- enseigne SHOP
sign = rbox((3.2, 0.3, 0.72), (0, 1.1, 9.64), r=0.12, seg=2)
body.append(sign)
txt = text_mesh("SHOP", 0.62, 0.1, bevel_d=0.012, res=2)
xf(txt, rot=(math.pi / 2, 0, 0))
xf(txt, loc=(0, 0.94, 9.62))
glow.append(txt)

tagj(body, "Body", "SmoothPlastic", "16181E")
tagj(alu, "Alu", "Metal", "B8BEC8")
tagj(glass, "Glass", "Glass", "C9D6FF")
tagj(glow, "Glow", "Neon", "8B7CFF")
tagj(glow_red, "GemsRed", "Neon", "E53E3E")
tagj(gold, "Coins", "Foil", "E8B84A")
tagj(stripe_p, "AwningPurple", "Fabric", "8B7CFF")
tagj(stripe_w, "AwningWhite", "Fabric", "F2F2F5")

done("ShopKiosk", direction=(0.9, -1.2, 0.5), lens=50)
