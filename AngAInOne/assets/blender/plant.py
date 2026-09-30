"""Plant — succulente (échévéria) en pot côtelé sur soucoupe en bois (≈60 studs).

Pot en céramique à côtes verticales et lèvre arrondie, soucoupe bois, terreau + graviers, rosette de
feuilles charnues disposées selon l'angle d'or (chaque feuille : section elliptique, pointe, courbure),
deux rejets, hampe florale arquée avec boutons.
Modélisée façade vers −Y puis tournée à l'export."""
from room_common import *

reset()
pot, saucer, soil, pebbles, leaves, stalk, buds = [], [], [], [], [], [], []
GOLD = math.pi * (3 - math.sqrt(5))

# ---------------------------------------------------------------- soucoupe + pot côtelé
saucer.append(lathe([(0, 0), (22.5, 0), (23.5, 0.6), (24.2, 3.2), (23.4, 3.6), (22.4, 1.6), (0, 1.6)], 72, "Saucer", angle=40))
RIBS = 24


def pot_fn(u, v):
    a = TAU * u
    z = 1.6 + 26.0 * v
    r = 15.5 + 4.2 * v ** 0.8
    r += 0.55 * abs(math.sin(RIBS * a / 2)) ** 0.6 * (0.3 + 0.7 * min(1, v * 5)) * min(1, (1 - v) * 8)
    return (r * math.cos(a), r * math.sin(a), z)


shell = grid_surface(pot_fn, RIBS * 6, 16, closed_u=True, name="Pot", angle=70)
rim = lathe([(20.2, 27.3), (20.9, 27.8), (21.2, 28.8), (20.7, 29.7), (19.8, 29.9), (19.0, 29.3), (18.9, 26.0), (0, 26.0)] ,
            96, "Rim", angle=50)
bottom = lathe([(0, 1.6), (15.5, 1.6)], 72, "Bottom")
pot += [shell, rim, bottom]
# terreau (bombé) + graviers
soil.append(lathe([(0, 28.4), (10, 28.3), (18.8, 27.6), (18.8, 26.5), (0, 26.5)], 48, "Soil", angle=60))
import random
random.seed(7)
for i in range(22):
    r = 6 + 12 * math.sqrt(random.random())
    a = random.random() * TAU
    p = uvsphere(0.9 + random.random() * 0.8, (0, 0, 0), 10, 6,
                 scale=(1.0 + random.random() * 0.4, 0.8 + random.random() * 0.3, 0.55))
    xf(p, rot=(0, 0, random.random() * TAU))
    xf(p, loc=(r * math.cos(a), r * math.sin(a), 28.4 - 0.02 * r * r / 18))
    pebbles.append(p)


# ---------------------------------------------------------------- feuille charnue paramétrique
def leaf(L, w, t, lift, curl, yaw, base=(0, 0, 28.5), r0=1.0):
    def fn(u, v):
        a = TAU * u
        prof = math.sin(math.pi * min(1.0, 0.25 + 0.75 * v) ** 0.75) ** 0.6 * (1 - v ** 7) ** 0.5 + 0.04
        hw, ht = w * prof, t * (0.5 + 0.5 * (1 - v)) * prof
        cx = r0 + L * v
        cz = curl * v * v
        # section : ellipse, dessus légèrement creusé (gouttière)
        y = hw * math.cos(a)
        zz = ht * math.sin(a)
        if zz > 0:
            zz *= 1 - 0.35 * (math.cos(a) ** 2 < 0.4)
        return (cx, y, cz + zz)
    o = grid_surface(fn, 10, 8, closed_u=True, name="Leaf", angle=70, cap_ends=True)
    o.data.transform(Matrix.Translation(base) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(-lift, 4, "Y"))
    o.data.update()
    return o


def rosette(n, scale, base, lift0=0.2, lift1=1.25):
    out = []
    for i in range(n):
        f = i / (n - 1)
        L = scale * (13.5 - 8.5 * f)
        w = scale * (5.8 - 3.2 * f)
        t = scale * (1.9 - 0.6 * f)
        lift = lift0 + (lift1 - lift0) * f ** 0.8          # jeunes feuilles au centre plus dressées
        out.append(leaf(L, w, t, lift, scale * (2.5 - 1.5 * f), i * GOLD, base, r0=scale * (0.4 + 1.2 * (1 - f))))
    return out


leaves += rosette(40, 1.35, (0, 0, 28.6), 0.08, 1.3)
leaves += rosette(13, 0.5, (13.0, -9.5, 28.2), 0.2, 1.2)
leaves += rosette(11, 0.42, (-14.0, 6.5, 28.2), 0.2, 1.2)
leaves.append(uvsphere(1.8, (0, 0, 30.2), 16, 8, scale=(1, 1, 1.4)))   # cœur

# ---------------------------------------------------------------- hampe florale + boutons
path = catmull([(1.5, 0.5, 29), (4, 1, 40), (8, 1.5, 50), (13, 2, 56), (17, 2.5, 58.5)], 10)
stalk.append(sweep(path, 0.55, 8, name="Stalk", radius_fn=lambda f: 0.6 - 0.25 * f))
for k, f in enumerate((0.45, 0.62, 0.76, 0.88)):
    p = Vector(path[int(f * (len(path) - 1))])
    stalk.append(leaf(2.4, 0.9, 0.4, 0.2, 0.3, k * 2.2, tuple(p), r0=0.2))    # bractées
for k in range(6):
    f = 0.9 + 0.1 * k / 5
    p = Vector(path[min(len(path) - 1, int(f * (len(path) - 1)))])
    d = Vector((math.cos(k * 2.1), math.sin(k * 2.1), -0.6)).normalized()
    stalk.append(cyl_between(p, p + d * 1.8, 0.18, 6))
    buds.append(uvsphere(0.75, p + d * 2.2, 12, 6, scale=(1, 1, 1.25)))

tagj(pot, "Pot", "SmoothPlastic", "F2F2F5")
tagj(saucer, "Saucer", "Wood", "5A3E2B")
tagj(soil, "Soil", "Pebble", "3B2A1E")
tagj(pebbles, "Pebbles", "Granite", "C9CED6")
tagj(leaves, "Leaves", "SmoothPlastic", "8FB9A8")
tagj(stalk, "Stalk", "SmoothPlastic", "6E9A7E")
tagj(buds, "Buds", "SmoothPlastic", "E53E3E")

done("Plant", direction=(0.8, -1.2, 0.75), lens=50)
