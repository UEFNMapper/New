"""Pop-Up — sbire du monde 2 (RAM) : fenêtre de pub envahissante, 6 studs de haut, regarde vers -Y.
Cadre de fenêtre arrondi, barre de titre bleue avec bouton ✕ rouge, gros yeux globuleux, pub « WIN!!! »
en relief néon sur une étoile rouge, barre de défilement, petites jambes à baskets et gants blancs."""
from char_common import *

new_scene()
kit = Kit()

W, H, D = 5.2, 4.0, 0.7
Z0 = 1.45                    # bas de la fenêtre
ZC = Z0 + H / 2
FY = -D / 2                  # face avant

# --- cadre
frame = rbox((W, D, H), (0, 0, ZC), radius=0.3, segments=5)
kit.add("Frame", "SmoothPlastic", "E2E8F0", frame)

# --- barre de titre + boutons
TB_Z = Z0 + H - 0.42
bar = rbox((W - 0.3, 0.2, 0.6), (0, FY - 0.02, TB_Z), radius=0.09, segments=3)
kit.add("TitleBar", "SmoothPlastic", "3B82F6", bar)
close = rbox((0.56, 0.24, 0.46), (W / 2 - 0.5, FY - 0.1, TB_Z), radius=0.1, segments=3)
kit.add("Red", "SmoothPlastic", "E53E3E", close)
glyphs = []
for a in (45, -45):
    g = rbox((0.36, 0.08, 0.08), (0, 0, 0), radius=0.035, segments=2)
    xf(g, (W / 2 - 0.5, FY - 0.23, TB_Z), (0, math.radians(a), 0))
    glyphs.append(g)
# réduire « _ » et agrandir « □ »
glyphs.append(rbox((0.3, 0.06, 0.07), (W / 2 - 1.55, FY - 0.14, TB_Z - 0.1), radius=0.03, segments=2))
sq = rbox((0.3, 0.06, 0.26), (W / 2 - 1.05, FY - 0.14, TB_Z), radius=0.04, segments=2)
hole = rbox((0.18, 0.3, 0.14), (W / 2 - 1.05, FY - 0.14, TB_Z - 0.01), radius=0.02, segments=1)
boolean(sq, hole)
glyphs.append(sq)
# petite icône + titre (3 traits) à gauche
glyphs.append(qsphere(0.14, (-W / 2 + 0.45, FY - 0.12, TB_Z), (1, 0.5, 1), level=2))
for i, L in enumerate((1.1, 0.7)):
    glyphs.append(rbox((L, 0.06, 0.08), (-W / 2 + 0.75 + L / 2, FY - 0.14, TB_Z + 0.08 - 0.17 * i), radius=0.035,
                       segments=2))
kit.add("White", "SmoothPlastic", "FFFFFF", glyphs)

# --- zone de contenu (crème) + barre de défilement
CZ0, CZ1 = Z0 + 0.14, TB_Z - 0.36
content = rbox((W - 0.3, 0.14, CZ1 - CZ0), (0, FY - 0.0, (CZ0 + CZ1) / 2), radius=0.08, segments=3)
kit.add("Content", "SmoothPlastic", "FFF7D6", content)
scroll = rbox((0.2, 0.1, CZ1 - CZ0 - 0.2), (W / 2 - 0.32, FY - 0.08, (CZ0 + CZ1) / 2), radius=0.09, segments=3)
thumb = rbox((0.22, 0.14, 0.8), (W / 2 - 0.32, FY - 0.1, CZ1 - 0.6), radius=0.1, segments=3)
kit.add("Frame", "SmoothPlastic", "E2E8F0", scroll)
kit.add("TitleBar", "SmoothPlastic", "3B82F6", thumb)
tree = bvh_multi([content])

# --- yeux globuleux (qui regardent chacun ailleurs)
EZ = CZ1 - 0.78
for sx, look in ((-1, (0.55, 0.35)), (1, (-0.2, -0.45))):
    ctr = V((0.92 * sx - 0.25, FY - 0.25, EZ))
    e = cartoon_eye(ctr, 0.62, look=look, squash=(1.0, 0.75, 1.0), pupil=0.5, level=3)
    kit.add("White", "SmoothPlastic", "FFFFFF", e["white"], e["shine"])
    kit.add("Dark", "SmoothPlastic", "1A1A2E", e["pupil"])
    # sourcils moqueurs (un levé, un froncé)
    b = [V((ctr.x - 0.5, FY - 0.3, EZ + 0.62 + (0.12 if sx < 0 else -0.02))),
         V((ctr.x, FY - 0.32, EZ + 0.86 + (0.1 if sx < 0 else -0.08))),
         V((ctr.x + 0.5, FY - 0.3, EZ + 0.7 + (0.0 if sx < 0 else -0.2)))]
    kit.add("Dark", "SmoothPlastic", "1A1A2E", sweep(b, [0.07, 0.1, 0.07], ring=10, flat=(1, 0.7)))

# --- pub « WIN!!! » : étoile rouge + texte néon
SZ = CZ0 + 0.78
star = []
N = 18
for i in range(2 * N):
    a = math.pi * i / N
    r = 1.0 if i % 2 == 0 else 0.8
    star.append((math.cos(a) * r * 2.05, math.sin(a) * r * 0.78))
burst = patch(star, tree, (-0.25, -5, SZ), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.0, thickness=0.12, cuts=1,
              name="Burst")
kit.add("Red", "SmoothPlastic", "E53E3E", burst)
txt = text_mesh("WIN!!!", size=0.95, extrude=0.08, bevel=0.025, loc=(-0.25, FY - 0.28, SZ - 0.02))
kit.add("Text", "Neon", "FFD400", txt)

# --- jambes + baskets
for sx in (-1, 1):
    leg = sweep([V((0.95 * sx, 0, Z0 + 0.2)), V((1.0 * sx, -0.05, 0.75)), V((1.05 * sx, -0.1, 0.35))],
                [0.12, 0.11, 0.11], ring=10, name="Leg")
    kit.add("Dark", "SmoothPlastic", "1A1A2E", leg)
    shoe = qsphere(1, (1.05 * sx, -0.32, 0.26), (0.36, 0.62, 0.3), level=3, name="Shoe")
    deform(shoe, lambda p: V((p.x, p.y, max(p.z, 0.14))))
    sole = qsphere(1, (1.05 * sx, -0.34, 0.13), (0.39, 0.66, 0.16), level=3, name="Sole")
    deform(sole, lambda p: V((p.x, p.y, max(p.z, 0.0))))
    kit.add("Red", "SmoothPlastic", "E53E3E", shoe)
    kit.add("White", "SmoothPlastic", "FFFFFF", sole)

# --- bras + gants blancs (un bras qui fait coucou)
for sx in (-1, 1):
    s0 = V((W / 2 * sx - 0.05 * sx, 0, ZC - 0.1))
    if sx > 0:
        pts = [s0, s0 + V((0.55, -0.1, 0.35)), s0 + V((0.85, -0.2, 1.1))]
    else:
        pts = [s0, s0 + V((-0.5, -0.1, -0.3)), s0 + V((-0.75, -0.25, -0.95))]
    kit.add("Dark", "SmoothPlastic", "1A1A2E", sweep(pts, 0.1, ring=10, name="Arm"))
    hand = pts[-1] + (pts[-1] - pts[-2]).normalized() * 0.25
    glove = qsphere(0.3, hand, (1.0, 0.8, 1.05), level=3, name="Glove")
    thumb = qsphere(0.12, hand + V((-0.22 * sx, -0.12, 0.08)), (1, 1, 1.3), level=2)
    cuff = torus(0.2, 0.07, pts[-1] + (pts[-1] - pts[-2]).normalized() * 0.02,
                 rot=V((0, 0, 1)).rotation_difference(pts[-1] - pts[-2]).to_euler(), major=20, minor=8)
    kit.add("White", "SmoothPlastic", "FFFFFF", glove, thumb, cuff)

kit.fit_height(6.0)
kit.build()
finish("PopUp", camera=cam((0.9, -2.4, 0.8)), samples=48)
