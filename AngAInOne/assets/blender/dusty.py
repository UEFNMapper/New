"""Dusty — sbire du monde 4 (refroidissement) : boule de poussière grise duveteuse, 5 studs, regarde vers -Y.
Corps en nuage de touffes (bosses de Voronoï + mèches), gros yeux endormis à paupières lourdes,
petite bouche qui bâille, petit nez, queue de « mouton de poussière » en spirale, pieds dodus,
grains de poussière qui flottent."""
from char_common import *

new_scene()
kit = Kit()
random.seed(11)

FUR, FUR_DARK = "B0AFA8", "8E8C85"
CZ, R = 2.45, 2.0
C = V((0, 0, CZ))

# --- corps : sphère + bosses « nuage » (cellules de Voronoï) + petit bruit
body = qsphere(R, C, (1.0, 0.95, 0.96), n=26, name="Body")


def fluff(co, nrm):
    p = (co - C) * 1.0
    d = noise.voronoi(p)[0]
    f1, f2 = d[0], d[1]
    bump = 0.42 * (1 - smoothstep(0.0, 0.85, f1)) ** 1.3
    crease = -0.08 * (1 - smoothstep(0.0, 0.15, f2 - f1))  # petits creux entre les touffes
    fine = 0.03 * noise.noise(p * 6.0)
    face = 1 - 0.75 * smoothstep(-0.2, -1.2, (co - C).y) * (1 - smoothstep(0.6, 1.3, abs(co.x))) \
        * (1 - smoothstep(0.3, 1.2, abs(co.z - CZ - 0.1)))  # visage plus lisse
    return (bump + crease + fine) * face


displace(body, fluff)
shade(body)
kit.add("Fur", "Fabric", FUR, body)
tree = bvh(body)

# --- mèches (touffes pointues) sur le dessus et les côtés
tufts = []
M = 34
for i in range(M):
    # répartition de Fibonacci
    zz = 1 - 2 * (i + 0.5) / M
    rr = math.sqrt(1 - zz * zz)
    a = i * math.pi * (3 - math.sqrt(5))
    d = V((rr * math.cos(a), rr * math.sin(a), zz))
    if d.z < -0.3:
        continue
    if d.y < -0.3 and abs(d.x) < 0.85 and -0.6 < d.z < 0.75:
        continue  # garde le visage dégagé
    loc, n = raycast(tree, C + d * 5, -d)
    if loc is None:
        continue
    tang = d.cross(V((0, 0, 1))).normalized() if abs(d.z) < 0.98 else V((1, 0, 0))
    sw = random.choice((-1, 1))
    L = random.uniform(0.3, 0.46)
    # mèche douce et bouclée : épaisse à la base, bout arrondi, recourbée sur le côté
    pts = [loc - d * 0.25, loc + d * L * 0.45 + tang * sw * 0.12,
           loc + d * L * 0.8 + tang * sw * 0.38, loc + d * L * 0.75 + tang * sw * 0.62 - d * 0.05]
    tufts.append(sweep(pts, [0.4, 0.3, 0.2, 0.13], ring=9, samples=3, cap_rings=3, name="Tuft"))
# mèche rebelle sur le sommet
top, _ = raycast(tree, (0, 0, 10), (0, 0, -1))
tufts.append(sweep([top - V((0, 0, 0.2)), top + V((0.05, 0, 0.55)), top + V((0.35, 0, 0.95)), top + V((0.72, 0, 0.9)),
                    top + V((0.8, 0, 0.62)), top + V((0.6, 0, 0.52))],
                   [0.3, 0.24, 0.18, 0.13, 0.1, 0.08], ring=10, samples=4, name="Cowlick"))
kit.add("Tufts", "Fabric", FUR, tufts)

# --- queue de « dust bunny » : pompon duveteux à l'arrière (grappe de boules bosselées + mèche bouclée)
tl, tn = raycast(tree, V((0, 10, CZ - 0.55)), (0, -1, 0))
tc = tl + V((0, 0.45, 0.05))
puffs = [qsphere(0.62, tc, level=3, name="Puff")]
for k in range(6):
    a = 2 * math.pi * k / 6
    puffs.append(qsphere(0.34, tc + V((0.42 * math.cos(a), 0.18, 0.42 * math.sin(a))), level=2, name="Puff"))
for pf in puffs:
    displace(pf, lambda co, n: 0.07 * noise.noise(co * 5.0))
curl = sweep([tc + V((0, 0.5, 0.3)), tc + V((0.1, 0.9, 0.55)), tc + V((0.35, 1.05, 0.4)), tc + V((0.3, 0.95, 0.2))],
             [0.16, 0.11, 0.08, 0.06], ring=8, samples=4, name="Curl")
kit.add("Tufts", "Fabric", FUR, puffs, curl)

# --- yeux endormis : gros blancs, pupilles vers le bas, paupières lourdes tombantes
for sx in (-1, 1):
    loc, n = surface_point(tree, 0.78 * sx, CZ + 0.32)
    ctr = loc + V((0, 0.3, 0))
    e = cartoon_eye(ctr, 0.7, look=(0.05 * -sx, -0.4), squash=(1.0, 0.62, 1.12), pupil=0.5,
                    lid=(-14 * sx, 0.5))
    kit.add("EyeWhite", "SmoothPlastic", "FFFFFF", e["white"], e["shine"])
    kit.add("Dark", "SmoothPlastic", "2B2A28", e["pupil"])
    kit.add("FurDark", "Fabric", FUR_DARK, e["lid"])
    # cils : petit trait sombre au bord de la paupière
    a = math.radians(-14 * sx)
    p0 = ctr + V((-0.6, -0.42, 0.02 + 0.6 * math.tan(a)))
    p2 = ctr + V((0.6, -0.42, 0.02 - 0.6 * math.tan(a)))
    kit.add("Dark", "SmoothPlastic", "2B2A28",
            sweep([p0, (p0 + p2) / 2 + V((0, -0.08, -0.03)), p2], 0.045, ring=8, name="Lash"))

# --- petit nez + bouche qui bâille
nl, nn = surface_point(tree, 0.0, CZ - 0.32)
kit.add("Dark", "SmoothPlastic", "2B2A28", qsphere(0.14, nl + nn * 0.05, (1.2, 0.8, 0.9), level=2, name="Nose"))
mouth_pts = [(0.2 * math.cos(2 * math.pi * i / 40), 0.26 * math.sin(2 * math.pi * i / 40)) for i in range(40)]
mouth = patch(mouth_pts, tree, (0, -10, CZ - 0.72), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=-0.02, thickness=0.06,
              cuts=2, name="Mouth")
kit.add("Mouth", "SmoothPlastic", "5A3A3A", mouth)
tl, tn = surface_point(tree, 0.0, CZ - 0.86)
kit.add("Tongue", "SmoothPlastic", "E88A9A", qsphere(0.12, tl + tn * 0.03, (1.1, 0.5, 0.7), level=2))

# --- pieds dodus
for sx in (-1, 1):
    f = qsphere(0.46, (0.8 * sx, -0.6, 0.3), (1.0, 1.2, 0.8), level=3, name="Foot")
    deform(f, lambda p: V((p.x, p.y, max(p.z, 0.0))))
    kit.add("FurDark", "Fabric", FUR_DARK, f)

# --- grains de poussière qui flottent
motes = []
for p, s in (((-2.6, -0.3, 3.9), 0.16), ((2.5, 0.2, 4.3), 0.12), ((2.7, -0.6, 1.8), 0.1), ((-2.4, 0.5, 1.2), 0.13),
             ((-1.4, -1.2, 4.7), 0.09)):
    m = qsphere(s, p, level=2, name="Mote")
    displace(m, lambda co, n: s * 0.25 * noise.noise(co * 12.0))
    motes.append(m)
kit.add("Motes", "Pebble", "9A988F", motes)

kit.build()
finish("Dusty", camera=cam((0.9, -2.4, 0.8)), samples=48)
