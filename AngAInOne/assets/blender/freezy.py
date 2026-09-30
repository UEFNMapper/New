"""Freezy — sbire du monde 6 (GPU) : glaçon cubique, 5 studs de haut, regarde vers -Y.
Cube de glace translucide aux arêtes fondues, sablier doré figé À L'INTÉRIEUR (sable néon visible à travers),
calotte de givre qui coule sur les bords, sourcils de givre froncés, moue boudeuse, petits bras et pieds."""
from char_common import *

new_scene()
kit = Kit()

S = 3.6
Z0 = 0.62
ZC = Z0 + S / 2
SNOW = "F7FCFF"

# --- cube de glace (arêtes arrondies, surface légèrement irrégulière)
cube = rbox((S, S * 0.94, S), (0, 0, ZC), radius=0.62, segments=5)
subsurf(cube, 1)
deform(cube, lambda p: p + V((0.05 * noise.noise(p * 0.9), 0.05 * noise.noise(p * 0.9 + V((5, 0, 0))),
                               0.04 * noise.noise(p * 0.9 + V((0, 9, 0))))))
kit.add("Ice", "Glass", "9FD8F5", cube)
tree = bvh(cube)

# --- sablier figé à l'intérieur
HG_H = 2.1
hz0 = ZC - HG_H / 2
frame = [lathe([(0, 0), (0.62, 0), (0.66, 0.05), (0.66, 0.13), (0.62, 0.18), (0, 0.18)], segments=40,
               loc=(0, 0.25, hz0)),
         lathe([(0, 0), (0.62, 0), (0.66, 0.05), (0.66, 0.13), (0.62, 0.18), (0, 0.18)], segments=40,
               loc=(0, 0.25, hz0 + HG_H - 0.18))]
for k in range(3):
    a = 2 * math.pi * k / 3 + math.pi / 2
    x, y = 0.52 * math.cos(a), 0.25 + 0.52 * math.sin(a)
    frame.append(sweep([V((x, y, hz0 + 0.1)), V((x * 1.08, y, hz0 + HG_H / 2)), V((x, y, hz0 + HG_H - 0.1))],
                       0.05, ring=8, name="Post"))
kit.add("Frame", "Foil", "D4A64A", frame)
# sable : cône du haut (presque vide), filet figé, tas du bas
top_sand = lathe([(0.0, 0.0), (0.12, 0.0), (0.38, 0.28), (0.44, 0.42), (0.0, 0.46)], segments=32,
                 loc=(0, 0.25, ZC + 0.12))
stream = sweep([V((0, 0.25, ZC + 0.14)), V((0, 0.25, hz0 + 0.5))], 0.035, ring=8, name="Stream")
pile = lathe([(0.0, 0.0), (0.46, 0.0), (0.4, 0.14), (0.2, 0.34), (0.0, 0.42)], segments=32,
             loc=(0, 0.25, hz0 + 0.18))
kit.add("Sand", "Neon", "FFD27A", top_sand, stream, pile)

# --- calotte de givre avec coulures
cap = qsphere(1.0, (0, 0, ZC + S / 2 - 0.3), (S * 0.535, S * 0.505, 0.6), level=4, name="Cap")
displace(cap, lambda co, n: 0.04 * noise.noise(co * 3.0))
cut_below(cap, ZC + S / 2 - 0.62)

drops = []
for k, (ang, L) in enumerate(((-100, 0.55), (-68, 0.32), (-128, 0.3), (-20, 0.42), (15, 0.25), (60, 0.45),
                              (110, 0.32), (160, 0.42), (205, 0.3), (250, 0.38))):
    a = math.radians(ang)
    d = V((math.cos(a), math.sin(a), 0))
    # point sur la paroi du cube sous le bord de la calotte
    loc, nrm = raycast(tree, V((0, 0, ZC + S / 2 - 0.62)) + d * 5, -d)
    if loc is None:
        continue
    # coulure : fine au milieu, goutte ronde au bout
    drops.append(sweep([loc + V((0, 0, 0.12)) - nrm * 0.02, loc + V((0, 0, -L * 0.55)) + nrm * 0.02,
                        loc + V((0, 0, -L)) + nrm * 0.04],
                       [0.2, 0.1, 0.13], ring=12, samples=4, name="Drip"))
kit.add("Snow", "SmoothPlastic", SNOW, cap, drops)

# --- yeux + sourcils de givre + moue
for sx in (-1, 1):
    loc, nrm = surface_point(tree, 0.75 * sx, ZC + 0.35)
    ctr = loc + V((0, 0.16, 0))
    e = cartoon_eye(ctr, 0.52, look=(-0.2 * sx, -0.1), squash=(0.95, 0.5, 1.1), pupil=0.58, lid=(20 * -sx, 0.3))
    kit.add("Snow", "SmoothPlastic", SNOW, e["white"], e["shine"])
    kit.add("Dark", "SmoothPlastic", "1C3D5A", e["pupil"])
    kit.add("Ice", "Glass", "9FD8F5", e["lid"])
    # sourcil de givre (grumeleux)
    b = [surface_point(tree, 1.25 * sx, ZC + 1.12)[0] + V((0, -0.14, 0)),
         surface_point(tree, 0.75 * sx, ZC + 0.98)[0] + V((0, -0.22, 0)),
         surface_point(tree, 0.2 * sx, ZC + 0.72)[0] + V((0, -0.16, 0))]
    brow = sweep(b, [0.16, 0.2, 0.15], ring=12, samples=6, flat=(1, 0.8), name="Brow")
    displace(brow, lambda co, n: 0.045 * noise.noise(co * 7.0))
    kit.add("Snow", "SmoothPlastic", SNOW, brow)

# moue (arc vers le bas) + petite dent
MZ = ZC - 0.75
mouth = [V((x, 0, MZ - 0.32 * (x / 0.55) ** 2 + 0.05)) for x in (-0.55, -0.25, 0.0, 0.25, 0.55)]
mouth = [surface_point(tree, p.x, p.z)[0] + V((0, -0.04, 0)) for p in mouth]
for i in (0, 4):
    mouth[i] = mouth[i] + V((0, 0, -0.26))
kit.add("Dark", "SmoothPlastic", "1C3D5A", sweep(mouth, 0.07, ring=10, samples=5, flat=(1, 0.7), name="Mouth"))
tl, tn = surface_point(tree, 0.18, MZ - 0.08)
tooth = rbox((0.16, 0.1, 0.16), (0, 0, 0), radius=0.05, segments=2)
xf(tooth, tl + V((0, -0.06, 0)))
kit.add("Snow", "SmoothPlastic", SNOW, tooth)

# --- petits bras et pieds en glace plus opaque
limbs = []
for sx in (-1, 1):
    sh = V((S / 2 * sx - 0.1 * sx, -0.1, ZC - 0.3))
    hand = sh + V((0.62 * sx, -0.25, -0.55))
    limbs.append(sweep([sh, sh + V((0.35 * sx, -0.1, -0.1)), hand], [0.2, 0.17, 0.16], ring=12, name="Arm"))
    limbs.append(qsphere(0.26, hand + V((0.05 * sx, -0.05, -0.12)), level=3, name="Hand"))
    foot = qsphere(0.44, (0.85 * sx, -0.25, 0.24), (1.0, 1.25, 0.65), level=3, name="Foot")
    deform(foot, lambda p: V((p.x, p.y, max(p.z, 0.0))))
    limbs.append(foot)
    limbs.append(sweep([V((0.85 * sx, 0, 0.3)), V((0.85 * sx, 0, Z0 + 0.12))], 0.2, ring=12, name="Leg"))
kit.add("Limbs", "Ice", "B8E6FA", limbs)

kit.fit_height(5.0)
kit.build()
finish("Freezy", camera=cam((0.9, -2.4, 0.8)), samples=64)
