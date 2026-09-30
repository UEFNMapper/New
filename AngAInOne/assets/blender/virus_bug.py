"""VirusBug — virus qui patrouille : boule violette à pointes (boutons roses), 6 pattes d'insecte,
gros yeux rouges néon fâchés dans des orbites sombres, petits crocs. 4 studs de haut, regarde vers -Y.
Silhouette pensée pour se lire de loin (pointes régulières + pattes écartées + yeux qui brillent)."""
from char_common import *

new_scene()
kit = Kit()
random.seed(3)

BODY, KNOB, DARK = "7C3AED", "F472B6", "2A1446"
CZ, R = 1.8, 1.4
C = V((0, 0, CZ))

body = qsphere(R, C, (1.0, 0.96, 0.94), level=4, name="Body")
displace(body, lambda co, n: 0.035 * noise.noise((co - C) * 2.5))
kit.add("Body", "SmoothPlastic", BODY, body)
tree = bvh(body)

# --- pointes à boutons (couronne de virus), pas sur le visage ni dessous
stalks, knobs = [], []
M = 26
for i in range(M):
    zz = 1 - 2 * (i + 0.5) / M
    rr = math.sqrt(1 - zz * zz)
    a = i * math.pi * (3 - math.sqrt(5)) + 0.3
    d = V((rr * math.cos(a), rr * math.sin(a), zz))
    if d.z < -0.25:
        continue
    if d.y < -0.45 and abs(d.x) < 0.8 and d.z < 0.62:
        continue
    loc, n = raycast(tree, C + d * 5, -d)
    tip = loc + d * 0.5
    stalks.append(sweep([loc - d * 0.1, loc + d * 0.25, tip], [0.16, 0.1, 0.09], ring=10, samples=3,
                        cap_rings=2, name="Stalk"))
    knobs.append(qsphere(0.2, tip + d * 0.08, level=2, name="Knob"))
kit.add("Body", "SmoothPlastic", BODY, stalks)
kit.add("Knobs", "SmoothPlastic", KNOB, knobs)

# --- yeux : orbites sombres + yeux néon rouges coupés en biais (air méchant)
for sx in (-1, 1):
    def shape(rx, rz, cut, n=40):
        pts = []
        for k in range(n):
            t = 2 * math.pi * k / n
            x, z = rx * math.cos(t), rz * math.sin(t)
            z = min(z, cut + 0.55 * x * sx)
            pts.append((x, z))
        return pts
    o = (0.45 * sx, -5, CZ + 0.25)
    sock = patch(shape(0.42, 0.44, 0.24), tree, o, (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.0, thickness=0.07,
                 cuts=2, name="Socket")
    kit.add("Dark", "SmoothPlastic", DARK, sock)
    eye = patch(shape(0.33, 0.35, 0.16), tree, o, (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.05, thickness=0.07,
                cuts=2, name="Eye")
    # pupille-fente sombre au centre de l'œil (lecture « prédateur » mais mignonne)
    kit.add("Eyes", "Neon", "F0565B", eye)
    pl, pn = surface_point(tree, 0.45 * sx - 0.06 * sx, CZ + 0.18)
    pup = qsphere(1, (0, 0, 0), (0.08, 0.05, 0.16), level=2)
    xf_matrix(pup, align_matrix(pl + pn * 0.14, pn))
    kit.add("Dark", "SmoothPlastic", DARK, pup)

# --- bouche + crocs
MZ = CZ - 0.42
mouth = [(x, 0.07 * math.cos(x * 3) + 0.0) for x in [(-0.38 + 0.76 * k / 20) for k in range(21)]]
mpts = [(x, z + 0.06) for x, z in mouth] + [(x, z - 0.1 - 0.12 * (1 - (x / 0.38) ** 2)) for x, z in reversed(mouth)]
m = patch(mpts, tree, (0, -5, MZ), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.0, thickness=0.06, cuts=2, name="Mouth")
kit.add("Dark", "SmoothPlastic", DARK, m)
fangs = []
for sx in (-1, 1):
    l0, n0 = surface_point(tree, 0.17 * sx, MZ + 0.07)
    l1, n1 = surface_point(tree, 0.19 * sx, MZ - 0.17)
    fangs.append(sweep([l0 + n0 * 0.06, l1 + n1 * 0.08], [0.075, 0.015], ring=10, samples=3, name="Fang"))
kit.add("Fangs", "SmoothPlastic", "FFFFFF", fangs)

# --- 6 pattes d'insecte (coxa, genou haut, pied pointu au sol)
legs = []
for sx in (-1, 1):
    for k, ay in enumerate((-0.55, 0.0, 0.55)):
        root = C + V((0.95 * sx, ay * 1.0, -0.55))
        out = V((sx, ay * 1.1, 0)).normalized()
        knee = root + out * 0.62 + V((0, 0, 0.32))
        foot = root + out * 1.15 + V((0, 0, -root.z + 0.16))
        legs.append(sweep([root, root + out * 0.32 + V((0, 0, 0.22)), knee], [0.2, 0.18, 0.16], ring=10,
                          samples=4, cap_rings=2, name="Thigh"))
        legs.append(qsphere(0.19, knee, n=6, name="Knee"))
        legs.append(sweep([knee, knee + out * 0.3 + V((0, 0, -0.2)), foot], [0.16, 0.14, 0.13], ring=10,
                          samples=4, cap_rings=2, name="Shin"))
        shoe = qsphere(0.21, foot + out * 0.08 + V((0, 0, -0.02)), (1.0, 1.0, 0.75), n=6, name="Foot")
        legs.append(shoe)
kit.add("Legs", "SmoothPlastic", DARK, legs)

drop_to_ground()
kit.build()
finish("VirusBug", camera=cam((0.9, -2.4, 1.0)), samples=48)
