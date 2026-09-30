"""Minor — sbire du monde 5 (CPU) : mini-robot crypto-mineur, 6 studs de haut, regarde vers -Y.
Grosse tête-écran (yeux et sourire néon colériques), casque de chantier jaune avec lampe néon,
pièce crypto dorée sur le torse, bras articulés, pioche sur l'épaule (main droite = côté -X)."""
from char_common import *

new_scene()
kit = Kit()

BODY, DARK, METAL = "4A90B8", "2D3748", "A0AEC0"

# --- bottes + jambes
for sx in (-1, 1):
    boot = rbox((0.78, 1.1, 0.5), (0.62 * sx, -0.12, 0.25), radius=0.22, segments=4)
    toe = qsphere(0.39, (0.62 * sx, -0.5, 0.28), (1.0, 0.8, 0.72), level=3)
    deform(toe, lambda p: V((p.x, p.y, max(p.z, 0.0))))
    kit.add("Dark", "SmoothPlastic", DARK, boot, toe)
    leg = sweep([V((0.62 * sx, 0, 0.45)), V((0.6 * sx, 0, 1.35))], 0.2, ring=16, name="Leg")
    knee = qsphere(0.27, (0.61 * sx, 0, 0.9), level=3)
    kit.add("Metal", "Metal", METAL, leg, knee)

# --- torse (arrondi, un peu plus large en haut) + ceinture
torso = rbox((2.2, 1.7, 1.95), (0, 0, 2.27), radius=0.5, segments=5)
deform(torso, lambda p: V((p.x * (0.9 + 0.1 * smoothstep(1.3, 3.2, p.z)), p.y, p.z)))
subsurf(torso, 1)
kit.add("Body", "SmoothPlastic", BODY, torso)
belt = rbox((2.1, 1.62, 0.3), (0, 0, 1.45), radius=0.14, segments=3)
kit.add("Dark", "SmoothPlastic", DARK, belt)
for sx in (-1, 1):
    kit.add("Metal", "Metal", METAL, rbox((0.3, 0.12, 0.2), (0.62 * sx, -0.83, 1.45), radius=0.05, segments=2))

# --- pièce crypto sur le torse
coin_c = V((0, -0.9, 2.45))
coin = lathe([(0, -0.08), (0.52, -0.08), (0.6, -0.04), (0.6, 0.06), (0.5, 0.1), (0.44, 0.06), (0, 0.06)],
             segments=48)
xf(coin, coin_c, (math.pi / 2, 0, 0))
sym = text_mesh("B", size=0.62, extrude=0.05, bevel=0.012, loc=coin_c + V((0.02, -0.1, -0.02)))
bars = [rbox((0.06, 0.08, 0.2), coin_c + V((dx, -0.1, dz)), radius=0.02, segments=2)
        for dx in (-0.06, 0.08) for dz in (0.3, -0.33)]
kit.add("Coin", "Foil", "F2B01E", coin, sym, bars)
# coutures / rivets du torse
for sx in (-1, 1):
    for z in (1.85, 3.0):
        kit.add("Metal", "Metal", METAL, qsphere(0.07, (0.85 * sx, -0.86, z), (1, 0.6, 1), level=2))

# --- cou + tête-écran
neck = sweep([V((0, 0, 3.1)), V((0, 0, 3.45))], 0.36, ring=20, name="Neck")
kit.add("Metal", "Metal", METAL, neck)
HZ = 4.35
head = rbox((2.7, 2.1, 1.9), (0, 0, HZ), radius=0.62, segments=6)
kit.add("Body", "SmoothPlastic", BODY, head)
screen = rbox((2.15, 0.2, 1.3), (0, -1.0, HZ - 0.05), radius=0.34, segments=5)
kit.add("ScreenBack", "SmoothPlastic", "141A24", screen)
# oreilles-boulons
for sx in (-1, 1):
    ear = lathe([(0, 0), (0.34, 0), (0.36, 0.08), (0.36, 0.2), (0.24, 0.26), (0, 0.26)], segments=32)
    xf(ear, (1.3 * sx, 0, HZ), (0, math.pi / 2 * sx, 0))
    kit.add("Metal", "Metal", METAL, ear)

# yeux néon « en colère » (ellipses coupées en biais) + sourire en coin
scr_tree = bvh(screen)
glow = []
for sx in (-1, 1):
    pts = []
    for i in range(40):
        a = 2 * math.pi * i / 40
        x, z = 0.27 * math.cos(a), 0.34 * math.sin(a)
        z = min(z, 0.12 + 0.5 * x * sx)  # bord supérieur incliné : plus bas vers le centre (air fâché)
        pts.append((x, z))
    glow.append(patch(pts, scr_tree, (0.5 * sx, -5, HZ + 0.02), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.0,
                      thickness=0.05, cuts=1, name="EyeGlow"))
smile = [V((x, -1.14, HZ - 0.38 + 0.5 * x * x + 0.06 * x)) for x in (-0.38, -0.12, 0.12, 0.34)]
glow.append(sweep(smile, 0.05, ring=8, name="Smile"))
kit.add("Screen", "Neon", "5EF2FF", glow)

# --- casque de chantier + lampe
HAT_Z = HZ + 0.72
dome = qsphere(1.0, (0, 0, HAT_Z), (1.5, 1.3, 1.12), level=4, name="Hat")
cut_below(dome, HAT_Z)
brim = lathe([(1.35, 0.0), (1.72, -0.02), (1.78, 0.04), (1.72, 0.1), (1.35, 0.12)], segments=64)
xf(brim, (0, 0, HAT_Z - 0.06), scale=(1.0, 0.88, 1.0))
ridge = sweep([V((0, 1.25, HAT_Z + 0.2)), V((0, 0.7, HAT_Z + 0.98)), V((0, 0.0, HAT_Z + 1.2)),
               V((0, -0.7, HAT_Z + 0.98)), V((0, -1.2, HAT_Z + 0.35))], 0.14, ring=12, flat=(1, 1.4),
              name="Ridge")
kit.add("Hat", "SmoothPlastic", "F6C90E", dome, brim, ridge)
lamp_c = V((0, -1.3, HAT_Z + 0.5))
housing = lathe([(0, -0.25), (0.3, -0.25), (0.36, -0.15), (0.36, 0.2), (0.3, 0.26), (0, 0.26)], segments=32)
xf(housing, lamp_c, (math.pi / 2, 0, 0))
kit.add("Dark", "SmoothPlastic", DARK, housing)
lens = qsphere(0.27, lamp_c + V((0, -0.24, 0)), (1, 0.45, 1), level=3, name="Lens")
kit.add("Lamp", "Neon", "FFF3B0", lens)

# --- bras (épaule rotule, avant-bras, pince)
def arm(sx, hand, elbow):
    sh = V((1.25 * sx, 0, 2.95))
    parts = [qsphere(0.36, sh, level=3), sweep([sh, elbow], 0.15, ring=12), qsphere(0.2, elbow, level=3),
             sweep([elbow, hand], 0.15, ring=12)]
    kit.add("Metal", "Metal", METAL, parts)
    mitt = qsphere(0.3, hand, (1.0, 0.9, 1.05), level=3, name="Mitt")
    kit.add("Dark", "SmoothPlastic", DARK, mitt)
    return hand

# bras droit (côté -X) : tient la pioche posée sur l'épaule
hand_r = arm(-1, V((-1.95, -0.7, 2.75)), V((-1.95, -0.25, 2.25)))
# bras gauche : poing sur la hanche
arm(1, V((1.62, -0.35, 1.75)), V((1.9, -0.05, 2.35)))

# --- pioche
a = hand_r + V((0.12, 0.0, -0.75))
b = V((-2.55, -0.72, 5.1))
axis = (b - a).normalized()
handle = sweep([a, b], [0.12, 0.1], ring=12, samples=2, name="Handle")
grip = [torus(0.13, 0.035, a + axis * (0.35 + 0.12 * k), rot=V((0, 0, 1)).rotation_difference(axis).to_euler(),
              major=16, minor=6) for k in range(4)]
kit.add("Wood", "Wood", "8B5A2B", handle)
kit.add("Dark", "SmoothPlastic", DARK, grip)
# tête de pioche : arc effilé perpendiculaire au manche
side = axis.cross(V((0, 1, 0))).normalized()
up = side.cross(axis).normalized()
hc = b - axis * 0.12
pick = sweep([hc - side * 1.25 - axis * 0.45, hc - side * 0.6 - axis * 0.05, hc, hc + side * 0.6 - axis * 0.05,
              hc + side * 1.25 - axis * 0.45], [0.04, 0.16, 0.22, 0.16, 0.04], ring=10, samples=5, flat=(1.0, 0.7),
             name="PickHead")
collar = sweep([hc - axis * 0.28, hc + axis * 0.15], 0.17, ring=12, name="Collar")
kit.add("Metal", "Metal", METAL, pick, collar)

kit.build()
finish("Minor", camera=cam((0.9, -2.4, 0.8)), samples=48)
