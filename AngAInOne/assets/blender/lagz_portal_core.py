"""LagzPortalCore — le cœur du virus au centre de l'arène du boss (25 studs de haut).
Socle octogonal à gradins, corrompu (tranches décalées, filets néon violets, câbles), 4 griffes métal qui
tiennent un cœur néon violet dans une coque de verre, anneau de chargement flottant (pièce __Spin, axe
vertical passant par l'origine), éclats de pixels magenta/noirs en orbite. Symétrique ; face « avant » -Y."""
from char_common import *

new_scene()
kit = Kit()
random.seed(5)

PED, TRIM, CLAW = "2D2A3E", "8B5CF6", "4A4458"
OZ, OR = 13.6, 4.6          # centre et rayon du cœur

# --- socle octogonal à gradins (segments=8), arêtes adoucies
ped = lathe([(0.0, 0.0), (9.0, 0.0), (9.2, 0.25), (9.2, 1.25), (8.9, 1.5), (7.2, 1.5), (7.3, 1.7), (7.3, 3.0),
             (7.0, 3.2), (5.2, 3.2), (4.6, 3.6), (4.2, 5.8), (4.6, 6.6), (5.4, 7.2), (5.4, 7.6), (0.0, 7.6)],
            segments=8, rot=(0, 0, math.pi / 8))
shade(ped, flat_angle=40)
# corruption : deux tranches décalées
slice_shift(ped, 1.8, 2.5, (0.7, 0.0, 0))
slice_shift(ped, 4.4, 5.0, (-0.5, 0.35, 0))
kit.add("Pedestal", "SmoothPlastic", PED, ped)
# filets néon aux gradins
trims = [lathe([(9.25, 0.6), (9.35, 0.7), (9.35, 0.85), (9.25, 0.95)], segments=8, rot=(0, 0, math.pi / 8),
               close_bottom=False, close_top=False),
         lathe([(7.35, 2.65), (7.45, 2.75), (7.45, 2.9), (7.35, 3.0)], segments=8, rot=(0, 0, math.pi / 8),
               close_bottom=False, close_top=False),
         lathe([(5.45, 7.2), (5.55, 7.3), (5.55, 7.45), (5.45, 7.55)], segments=8, rot=(0, 0, math.pi / 8),
               close_bottom=False, close_top=False)]
for t in trims:
    bm = bmesh.new(); bm.from_mesh(t.data)
    bmesh.ops.bridge_loops(bm, edges=[e for e in bm.edges if e.is_boundary])
    bm.to_mesh(t.data); bm.free()
    shade(t, flat_angle=40)
# fissures néon en zigzag sur 4 faces du fût
ptree = bvh(ped)
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    d = V((math.cos(a), math.sin(a), 0))
    side = V((-d.y, d.x, 0))
    pts = []
    for j, z in enumerate((3.8, 4.5, 5.1, 5.7, 6.3)):
        o = d * 12 + side * (0.45 if j % 2 else -0.45) + V((0, 0, z))
        loc, n = raycast(ptree, o, -d)
        if loc is not None:
            pts.append(loc + n * 0.02)
    if len(pts) >= 3:
        trims.append(sweep(pts, 0.12, ring=8, samples=2, name="Crack"))
kit.add("Trim", "Neon", TRIM, trims)

# --- câbles qui sortent du socle et montent vers le cœur
cables = []
for k in range(4):
    a = k * math.pi / 2 + 0.3
    d = V((math.cos(a), math.sin(a), 0))
    p0 = d * 8.2 + V((0, 0, 1.5))
    cables.append(sweep([p0, d * 9.3 + V((0, 0, 3.5)), d * 7.2 + V((0, 0, 6.8)), d * 5.0 + V((0, 0, 8.6)),
                         d * 3.2 + V((0, 0, OZ - OR + 0.8))], 0.42, ring=12, samples=6, name="Cable"))
    cables.append(lathe([(0.0, 0), (0.62, 0), (0.62, 0.5), (0.0, 0.5)], segments=16, loc=p0 - V((0, 0, 0.25))))
kit.add("Cables", "SmoothPlastic", "1E1B2E", cables)

# --- griffes qui tiennent le cœur
claws = []
for k in range(4):
    a = k * math.pi / 2 + math.pi / 4
    d = V((math.cos(a), math.sin(a), 0))
    pts = [d * 4.2 + V((0, 0, 7.2)), d * 5.4 + V((0, 0, 9.0)), d * 5.6 + V((0, 0, OZ)),
           d * 4.6 + V((0, 0, OZ + 3.4)), d * 3.0 + V((0, 0, OZ + 4.6))]
    claws.append(sweep(pts, [0.9, 0.8, 0.65, 0.45, 0.1], ring=14, samples=6, flat=(1.0, 0.6), up=d, name="Claw"))
    claws.append(qsphere(0.9, d * 5.45 + V((0, 0, 9.3)), level=3))
cup = lathe([(0.0, 7.2), (4.2, 7.2), (4.5, 7.6), (4.0, 8.2), (3.0, 8.5), (0.0, 8.5)], segments=48)
kit.add("Claws", "Metal", CLAW, claws, cup)

# --- cœur : noyau néon « pulsant » (bosses) + coque de verre
core = qsphere(OR * 0.78, (0, 0, OZ), n=20, name="Core")
displace(core, lambda co, n: 0.35 * noise.noise((co - V((0, 0, OZ))) * 0.45))
kit.add("Core", "Neon", "B794F4", core)
shell = qsphere(OR, (0, 0, OZ), n=26, name="Shell")
kit.add("Shell", "Glass", "6B46C1", shell)

# --- anneau de chargement flottant (tourne) : 8 points de taille croissante + fin anneau
RZ = OZ + OR + 1.7
ring = [torus(3.6, 0.28, (0, 0, RZ), major=64, minor=10)]
for i in range(8):
    a = 2 * math.pi * i / 8
    s = 0.55 + 0.75 * i / 7
    ring.append(qsphere(s, (3.6 * math.cos(a), 3.6 * math.sin(a), RZ), level=3))
kit.add("Ring", "Neon", "E9D8FD", ring, spin=True, pivot=(0, 0, RZ))

# --- éclats de pixels en orbite (magenta néon / noirs)
mag, blk = [], []
for i in range(14):
    a = 2 * math.pi * i / 14 + random.uniform(-0.2, 0.2)
    r = random.uniform(7.4, 9.0)
    z = OZ + random.uniform(-4.5, 4.5)
    s = random.uniform(0.5, 0.95)
    c = rbox((s, s, s), (r * math.cos(a), r * math.sin(a), z), radius=0.08, segments=2,
             rot=(random.random(), random.random(), random.random()))
    (mag if i % 2 else blk).append(c)
kit.add("ShardsGlow", "Neon", "FF00FF", mag)
kit.add("Shards", "SmoothPlastic", "141414", blk)

# mise à l'échelle : 25 studs de haut
allo = [o for p in kit.parts.values() for o in p["objs"]]
zmax = max(v.co.z for o in allo for v in o.data.vertices)
k = 25.0 / zmax
for o in allo:
    xf_matrix(o, Matrix.Scale(k, 4))
kit.parts["Ring"]["pivot"] = V((0, 0, RZ * k))
print("échelle", k)

kit.build()
finish_char("LagzPortalCore", camera=cam((0.9, -2.4, 0.8)), samples=64, zoom=1.1)
