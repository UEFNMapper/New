"""Desk — bureau assis-debout d'Anga : plateau noyer foncé 1200 × 500 × 20 (bords arrondis), tapis de
souris XXL en tissu avec surpiqûre violette, pieds télescopiques à 3 étages sur patins, traverse,
panneau de commande (écran néon + boutons), passe-câble, goulotte grillagée (vrai treillis) avec
câbles et multiprise, ruban LED RGB sous le plateau.

DESSUS DU PLATEAU : z = 720 (le tapis ajoute 1,5). Façade (côté joueur) vers −Y en modélisation,
tournée à l'export comme les autres modèles."""
from room_common import *

reset()
W, D, T = 1200.0, 500.0, 20.0
ZT = 720.0                       # dessus du plateau
wood, black, fabric, stitch, glow, metal, cables = [], [], [], [], [], [], []


def rr3(w, d, r, z, n=10, dy=0.0):
    return [(x, y + dy, z) for x, y in rounded_rect(w, d, r, n)]


# ---------------------------------------------------------------- plateau (bord avant en demi-rond)
secs = []
R0 = 30
for k, (inset, z) in enumerate([(7.0, ZT - T), (2.8, ZT - T + 1.2), (0.6, ZT - T + 4.0), (0.0, ZT - 10),
                                (0.6, ZT - 4.0), (2.8, ZT - 1.2), (7.0, ZT)]):
    secs.append(rr3(W - 2 * inset, D - 2 * inset, R0 - inset, z))
top = loft(secs, "Top", angle=40)
grommet_cut = cyl(22, 40, (0, D / 2 - 60, ZT - 30), verts=48)
boolean_diff(top, grommet_cut)
wood.append(top)
# passe-câble (bague + couvercle fendu)
black.append(lathe([(22.2, ZT - 20), (22.2, ZT + 0.2), (25.5, ZT + 0.4), (26, ZT + 1.2), (19.5, ZT + 1.2), (19.5, ZT - 3),
                    (21.0, ZT - 3), (21.0, ZT - 20)], 48, "Grommet"))
lid = cyl(19.4, 1.0, (0, D / 2 - 60, ZT + 0.2), verts=48, bev=0.3)
boolean_diff(lid, rbox((40, 5, 6), (0, D / 2 - 72, ZT), r=0))
black.append(lid)

# ---------------------------------------------------------------- tapis XXL + surpiqûre
MW, MD, MR = 920.0, 380.0, 18.0
MY = -45.0
mat = extrude(rounded_rect(MW, MD, MR, 8), ZT, ZT + 1.5, "Mat", angle=30)
xf(mat, loc=(0, MY, 0))
bevel_all(mat, 0.5, 2, angle=40)
fabric.append(mat)
border = [(x, y + MY, ZT + 1.0) for x, y in rounded_rect(MW - 0.6, MD - 0.6, MR - 0.3, 8)]
b = sweep(border, 1.05, 8, closed=True, name="Border")
stitch.append(b)
lg = text_mesh("AngAInOne", 22, 0.5, res=2)
xf(lg, loc=(MW / 2 - 130, MY - MD / 2 + 26, ZT + 1.4))
stitch.append(lg)

# ---------------------------------------------------------------- piètement assis-debout
LX, LY = 470.0, 40.0
for sx in (-1, 1):
    x = sx * LX
    # patin (profil galbé) + vérins de réglage
    foot = loft([rr3(70, 470, 30, 0.0 + 6, dy=LY - 30), rr3(74, 474, 32, 12, dy=LY - 30), rr3(64, 460, 28, 32, dy=LY - 30),
                 rr3(40, 380, 18, 40, dy=LY - 30)], "Foot", angle=35)
    xf(foot, loc=(x, 0, 0))
    black.append(foot)
    for yy in (LY - 30 - 210, LY - 30 + 210):
        metal.append(cyl(12, 6, (x, yy, 0), verts=24, bev=1.5))
    # colonne télescopique 3 étages (joints visibles)
    for (w, d, z0, z1) in ((90, 60, 36, 300), (82, 52, 300, 520), (74, 44, 520, 684)):
        black.append(rbox((w, d, z1 - z0), (x, LY, (z0 + z1) / 2), r=6, seg=3))
        black.append(rbox((w + 2, d + 2, 5), (x, LY, z1 - 3), r=2, seg=2))
    # console sous plateau
    black.append(rbox((70, 440, 18), (x, 0, ZT - T - 9), r=4, seg=3))
# traverse + moteur central
black.append(rbox((2 * LX - 70, 50, 44), (0, LY, 640), r=8, seg=3))
black.append(rbox((2 * LX - 60, 40, 16), (0, LY - 140, ZT - T - 8), r=4, seg=2))
black.append(rbox((2 * LX - 60, 40, 16), (0, LY + 140, ZT - T - 8), r=4, seg=2))

# panneau de commande (avant droit) : boîtier, afficheur, 4 boutons
cp = rbox((110, 34, 16), (380, -D / 2 + 30, ZT - T - 8), r=5, seg=3)
black.append(cp)
disp = rbox((34, 1.4, 8), (362, -D / 2 + 12.6, ZT - T - 8), r=0.6, seg=1)
glow.append(disp)
digits = text_mesh("72.0", 6.0, 0.6, res=1)
xf(digits, rot=(math.pi / 2, 0, 0))
xf(digits, loc=(362, -D / 2 + 11.8, ZT - T - 10.2))
metal.append(digits)
for k in range(4):
    metal.append(cyl(3.2, 2.0, (392 + k * 10, -D / 2 + 13.5, ZT - T - 8), rot=(math.pi / 2, 0, 0), verts=16, bev=0.5))

# ---------------------------------------------------------------- goulotte grillagée + câbles + multiprise
TL, TY, TZ0, TZ1 = 760.0, D / 2 - 70, 612.0, 670.0
basket = rbox((TL, 90, TZ1 - TZ0), (0, TY, (TZ0 + TZ1) / 2), r=0)
bm = bmesh.new(); bm.from_mesh(basket.data)
top_faces = [f for f in bm.faces if f.normal.z > 0.9]
bmesh.ops.delete(bm, geom=top_faces, context="FACES")                     # bac ouvert
bm.to_mesh(basket.data); bm.free()
bpy.ops.object.mode_set(mode="OBJECT")
select_only(basket)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.subdivide(number_cuts=3)
bpy.ops.object.mode_set(mode="OBJECT")
slice_x(basket, TL / 26, -TL / 2 + 1, TL / 2 - 1)
wireframe(basket, 1.4)
metal_basket = [basket]
for sx in (-1, 1):
    for sy in (-1, 1):
        black.append(rbox((6, 6, ZT - T - TZ1 + 4), (sx * (TL / 2 - 40), TY + sy * 40, (ZT - T + TZ1) / 2 - 2), r=1.5, seg=2))
power = rbox((300, 44, 26), (-120, TY, TZ0 + 14), r=6, seg=3)
black.append(power)
for k in range(5):
    black.append(rbox((26, 30, 3), (-240 + k * 58, TY, TZ0 + 28.5), r=2, seg=2))
    glow.append(rbox((4, 1.0, 3), (-240 + k * 58 + 18, TY - 22.2, TZ0 + 22), r=0.3, seg=1))
for k, (x0, col) in enumerate(((-240, 0), (-182, 1), (-124, 2), (-66, 3))):
    route = [(x0, TY, TZ0 + 30), (x0 + 10, TY - 6, TZ0 + 52), (x0 + 60, TY - 10 + k * 4, TZ0 + 30), (x0 + 200, TY - 12 + k * 6, TZ0 + 18),
             (x0 + 330 + k * 20, TY + 4, TZ0 + 22), (x0 + 360 + k * 20, TY + 12, ZT - T - 4), (x0 + 380 + k * 20, 0 + TY + 10, ZT + 30)]
    if k >= 2:
        route = route[:-2] + [(x0 + 330 + k * 20, TY + 10, TZ0 + 60), (0 + (k - 2) * 8 - 4, D / 2 - 60, ZT - 21)]
    cables.append(sweep(catmull(route[:-1] if k < 2 else route, 8), 3.2, 10, name="Cable"))

# ---------------------------------------------------------------- ruban LED sous le plateau (arrière)
glow.append(rbox((W - 120, 3, 3), (0, D / 2 - 18, ZT - T - 1.6), r=1.0, seg=2))
glow.append(rbox((W - 160, 3, 3), (0, -D / 2 + 20, ZT - T - 1.6), r=1.0, seg=2))

tagj(wood, "Top", "Wood", "3B2A1E")
tagj(fabric, "Deskmat", "Fabric", "22252E")
tagj(stitch, "Stitching", "SmoothPlastic", "8B7CFF")
tagj(black, "Frame", "SmoothPlastic", "16181E")
tagj(metal + metal_basket, "Metal", "Metal", "2A2D38")
tagj(glow, "Glow", "Neon", "8B7CFF")
tagj(cables, "Cables", "SmoothPlastic", "22252E")

done("Desk", direction=(0.9, -1.25, 0.6), lens=50)
