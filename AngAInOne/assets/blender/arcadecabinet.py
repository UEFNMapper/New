"""ArcadeCabinet — borne d'arcade du lobby (échelle joueur, ≈10 studs).

Silhouette « upright » classique : flancs découpés avec T-molding néon, bandes graphiques violettes
et rouges en relief sur les flancs, fronton rétroéclairé AngAInOne, grilles de haut-parleurs,
écran incliné (`Screen`, face −Z Roblox) dans son cadre, panneau de commande (joystick à boule,
6 boutons, 2 boutons Start), porte à monnayeur lumineuse, plinthe, dos et dessus.
Modélisée façade vers −Y puis tournée à l'export."""
from room_common import *

reset()
body, purple, redp, white, metal, neon, neon_red = [], [], [], [], [], [], []
HW = 1.9            # demi-largeur hors tout
TH = 0.3            # épaisseur des flancs
IW = 2 * (HW - TH)  # largeur intérieure

# profil des flancs (y, z) — avant vers −y
SIDE = [(-1.25, 0.0), (2.3, 0.0), (2.3, 9.3), (1.95, 10.0), (-1.75, 10.0), (-1.75, 8.35), (-1.2, 8.05), (-1.95, 4.95),
        (-2.65, 4.62), (-2.6, 4.05), (-1.35, 3.8), (-1.35, 0.25)]


def yz_extrude(poly, x0, x1, name="Panel"):
    o = extrude([(y, z) for y, z in poly], x0, x1, name, angle=30)
    o.data.transform(Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))  # (y,z,x) → (x,y,z)
    o.data.update()
    return o


for sx in (-1, 1):
    side = yz_extrude(SIDE, -TH / 2, TH / 2, "Side")
    bevel_all(side, 0.06, 2, angle=30)
    xf(side, loc=(sx * (HW - TH / 2), 0, 0))
    body.append(side)
    # T-molding : jonc lumineux le long du chant avant/haut du flanc
    tm = [Vector((sx * (HW - TH / 2), y, z)) for y, z in SIDE[3:] + [SIDE[0]]]
    neon.append(sweep(catmull([tuple(p) for p in tm], 2), 0.1, 8, name="TMold"))
    # bandes graphiques en relief (diagonales violette / rouge / fine violette)
    for k, (w, col, off) in enumerate(((0.55, purple, 0.0), (0.3, redp, 0.75), (0.14, purple, 1.2))):
        z0 = 1.2 + off
        band = [(2.1, z0), (2.1, z0 + w), (-1.1, z0 + w + 2.2), (-1.1, z0 + 2.2)]
        b = yz_extrude(band, 0, 0.05, "Band")
        xf(b, loc=(sx * (HW + 0.0) if sx > 0 else -HW - 0.05, 0, 0))
        col.append(b)
    # logo « A » sur le flanc (haut)
    lg = text_mesh("A", 1.6, 0.06, res=2)
    lg.data.transform(Matrix.Rotation(sx * math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"))
    xf(lg, loc=(sx * (HW + 0.03), 0.6, 7.2))
    redp.append(lg)

# ---------------------------------------------------------------- caisson entre les flancs
X0, X1 = -HW + TH, HW - TH
def slab(p0, p1, t=0.12, inset=0.0):
    """Panneau entre les flancs, du point (y,z) p0 au point p1, épaisseur t vers l'intérieur."""
    a, b = Vector((0, *p0)), Vector((0, *p1))
    L = (b - a).length
    o = rbox((IW - 2 * inset, t, L), (0, 0, 0), r=0.03, seg=1)
    orient(o, a, b)
    xf(o, loc=None)
    o.data.transform(Matrix.Translation((0, 0, 0)))
    return o


# dessus, dos, plinthe, façade basse
body.append(rbox((IW, 3.68, 0.12), (0, 0.1, 9.93), r=0.03, seg=1))
body.append(rbox((IW, 0.12, 9.3), (0, 2.24, 4.65), r=0.03, seg=1))
body.append(rbox((IW, 0.2, 3.5), (0, -1.28, 2.05), r=0.03, seg=1))
kick = rbox((IW, 0.25, 0.3), (0, -1.15, 0.15), r=0.05, seg=1)
body.append(kick)

# porte à monnayeur (métal) + fentes lumineuses + ouïes
door = rbox((1.7, 0.08, 1.6), (0, -1.42, 2.2), r=0.08, seg=2)
metal.append(door)
for sxx in (-0.4, 0.4):
    neon_red.append(rbox((0.3, 0.06, 0.42), (sxx, -1.48, 2.45), r=0.05, seg=1))
    metal.append(rbox((0.06, 0.1, 0.28), (sxx, -1.52, 2.45), r=0.02, seg=1))
    metal.append(rbox((0.36, 0.1, 0.16), (sxx, -1.48, 1.9), r=0.03, seg=1))
metal.append(cyl(0.09, 0.1, (0.6, -1.46, 1.65), rot=(math.pi / 2, 0, 0), verts=8))
for k in range(6):
    body.append(rbox((1.8, 0.08, 0.06), (0, -1.42, 0.7 + k * 0.14), r=0.02, seg=1))

# ---------------------------------------------------------------- panneau de commande
cp_a, cp_b = Vector((0, -1.95, 4.95)), Vector((0, -2.65, 4.62))
cp_n = Vector((0, -(cp_b - cp_a).z, (cp_b - cp_a).y)).normalized() * -1
if cp_n.z < 0:
    cp_n = -cp_n
cp_top = extrude([(-1.95 + 0.0, 4.95), (-2.65, 4.62), (-2.6, 4.05), (-1.35, 3.8)], X0, X1, "CP")
cp_top.data.transform(Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
cp_top.data.update()
bevel_all(cp_top, 0.04, 2, angle=30)
body.append(cp_top)
# repère du plateau incliné
cp_t = (cp_b - cp_a).normalized()          # vers l'avant, en descendant
CPM = Matrix.Translation((cp_a + cp_b) / 2) @ Matrix((
    (1, 0, 0, 0), (0, cp_t.y, cp_n.y, 0), (0, cp_t.z, cp_n.z, 0), (0, 0, 0, 1)))


def on_cp(o, x, t, h=0.0):
    o.data.transform(Matrix.Translation(CPM @ Vector((x, t, h))) @ CPM.to_3x3().to_4x4())
    o.data.update()
    return o


# joystick : embase, soufflet, tige, boule rouge
metal.append(on_cp(cyl(0.22, 0.04, (0, 0, 0), verts=24), -0.95, 0.05))
body.append(on_cp(lathe([(0.2, 0), (0.16, 0.05), (0.19, 0.1), (0.13, 0.15), (0.16, 0.2), (0.08, 0.26)], 20, "Boot"), -0.95, 0.05))
metal.append(on_cp(cyl(0.05, 0.62, (0, 0, 0), verts=12), -0.95, 0.05))
redp.append(on_cp(uvsphere(0.2, (0, 0, 0.72), 24, 12), -0.95, 0.05))
# boutons d'action (2 rangées de 3) : couronne + chapeau bombé
for i in range(3):
    for j in range(2):
        x, t = 0.1 + i * 0.42 + j * 0.12, -0.12 + j * 0.34
        col = redp if (i + j) % 2 == 0 else purple
        body.append(on_cp(cyl(0.17, 0.06, (0, 0, 0), verts=20, bev=0.02), x, t))
        col.append(on_cp(lathe([(0, 0.05), (0.13, 0.05), (0.14, 0.1), (0.1, 0.15), (0, 0.16)], 20, "Btn"), x, t))
for x in (-0.35, 0.35):
    white.append(on_cp(rbox((0.2, 0.12, 0.08), (0, 0, 0.04), r=0.03, seg=2), x, -0.34 + 0.0))

# ---------------------------------------------------------------- écran incliné + cadre
sa, sb = Vector((0, -1.2, 8.05)), Vector((0, -1.95, 4.95))
s_t = (sb - sa).normalized()
s_n = Vector((0, -s_t.z, s_t.y))
if s_n.y > 0:
    s_n = -s_n
bezel = extrude([(-1.2, 8.05), (-1.95, 4.95), (-1.75, 4.9), (-1.0, 8.0)], X0, X1, "Bezel")
bezel.data.transform(Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
bezel.data.update()
L = (sb - sa).length
inner = rbox((IW - 0.5, 1.0, L - 0.55), (0, 0, 0), r=0.12, seg=2)
orient(inner, Vector((0, 0, 0)), Vector((0, 0, 1)))
inner.data.transform(Matrix.Translation((sa + sb) / 2) @ s_t.to_track_quat("Z", "Y").to_matrix().to_4x4())
inner.data.update()
boolean_diff(bezel, inner)
body.append(bezel)
scr = screen_part(IW - 0.62, L - 0.67, (sa + sb) / 2 - s_n * 0.05, s_n, sa - sb)

# ---------------------------------------------------------------- fronton rétroéclairé + haut-parleurs
neon.append(rbox((IW, 0.12, 1.45), (0, -1.72, 9.2), r=0.04, seg=1))
mq = text_mesh("AngAInOne", 0.72, 0.1, bevel_d=0.015, res=2)
xf(mq, rot=(math.pi / 2, 0, 0))
xf(mq, loc=(0, -1.79, 9.2))
body.append(mq)
body.append(rbox((IW, 0.1, 0.3), (0, -1.73, 8.35), r=0.02, seg=1))
spk = rbox((IW, 0.5, 0.35), (0, -1.45, 8.2), r=0.02, seg=1)
xf(spk, rot=None)
for sxx in (-0.85, 0.85):
    g = cyl(0.14, 0.2, (sxx, -1.7, 8.2), rot=(math.pi / 2, 0, 0), verts=16)
    for k in range(5):
        pass
    metal.append(g)
body.append(spk)

tagj(body, "Cabinet", "SmoothPlastic", "16181E")
tagj(purple, "ArtPurple", "SmoothPlastic", "8B7CFF")
tagj(redp, "ArtRed", "SmoothPlastic", "E53E3E")
tagj(white, "White", "SmoothPlastic", "F2F2F5")
tagj(metal, "Metal", "Metal", "B8BEC8")
tagj(neon, "Glow", "Neon", "8B7CFF")
tagj(neon_red, "CoinLights", "Neon", "E53E3E")

done("ArcadeCabinet", direction=(1.0, -1.1, 0.55), lens=50)
