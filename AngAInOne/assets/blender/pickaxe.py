"""Pickaxe — pioche géante de mineur (visuel du piège pendule), manche 30 + fer 18 studs.
ORIGINE = HAUT DU MANCHE (le pivot) : le modèle pend vers -Z (Blender), le fer est en bas, orienté selon X,
les pointes remontent vers le pivot. Côté +X : pic pointu ; côté -X : panne plate (burin).
Manche en bois veiné légèrement fuselé, poignée gainée de cuir, virole et calotte métal, œil de pivot."""
from char_common import *

new_scene()
kit = Kit()

L = 30.0          # manche
HZ = -L + 1.6     # hauteur du centre du fer

# --- manche : fuselé, pommeau, veinage
def radius(z):  # z de 0 (haut) à -L
    t = -z / L
    return 0.85 + 0.25 * t + 0.25 * math.exp(-((t - 0.04) / 0.035) ** 2)

zs = [-L + L * k / 60 for k in range(61)]
handle = lathe([(0.0, -L - 0.35), (radius(-L) * 0.8, -L - 0.3)] + [(radius(z), z) for z in zs] + [(0.0, 0.0)],
               segments=32)
displace(handle, lambda co, n: 0.06 * noise.noise(V((co.x * 2.2, co.y * 2.2, co.z * 0.12))) * (abs(n.z) < 0.7))
kit.add("Handle", "Wood", "8B5A2B", handle)

# --- poignée gainée (spirale de cuir) près du pivot
zg0, zg1 = -1.6, -9.2
grip = [lathe([(0.0, zg1 - 0.1), (radius(zg1) + 0.12, zg1 - 0.1), (radius(zg1) + 0.2, zg1 + 0.1)] +
              [(radius(z) + 0.2 + 0.03 * math.sin(z * 9), z) for z in [zg1 + (zg0 - zg1) * k / 40 for k in range(1, 40)]] +
              [(radius(zg0) + 0.12, zg0 + 0.1), (0.0, zg0 + 0.1)], segments=32)]
for z in (zg0 - 0.35, (zg0 + zg1) / 2, zg1 + 0.35):
    grip.append(torus(radius(z) + 0.26, 0.13, (0, 0, z), major=40, minor=8))
kit.add("Grip", "Fabric", "3B2A20", grip)

# --- calotte + œil de pivot (axe du pivot selon Y)
fit = []
fit.append(lathe([(0.0, -1.3), (1.12, -1.3), (1.2, -1.1), (1.2, -0.3), (1.05, 0.0), (0.0, 0.0)], segments=40))
fit.append(torus(1.0, 0.32, (0, 0, 1.05), rot=(math.pi / 2, 0, 0), major=40, minor=12))
fit.append(rbox((0.9, 0.5, 0.8), (0, 0, 0.1), radius=0.2, segments=3))
# viroles du fer
fit.append(lathe([(0.0, 0), (1.45, 0), (1.55, 0.12), (1.55, 1.1), (1.45, 1.25), (0.0, 1.25)], segments=40,
                 loc=(0, 0, HZ + 1.1)))
fit.append(lathe([(0.0, 0), (1.35, 0), (1.45, 0.1), (1.45, 0.55), (1.3, 0.65), (0.0, 0.65)], segments=40,
                 loc=(0, 0, HZ - 1.75)))
# rivets
for sx in (-1, 1):
    fit.append(qsphere(0.32, (sx * 1.2, -1.5, HZ), (1, 0.6, 1), level=2))
    fit.append(qsphere(0.32, (sx * 1.2, 1.5, HZ), (1, 0.6, 1), level=2))
kit.add("Fittings", "Metal", "5A6372", fit)

# --- fer : arc dont les pointes remontent vers le pivot
def arc(x):
    return HZ + 2.6 * (x / 9.0) ** 2

pick = sweep([V((0, 0, arc(0))), V((3.0, 0, arc(3.0))), V((6.0, 0, arc(6.0))), V((8.2, 0, arc(8.2) + 0.2)),
              V((9.1, 0, arc(9.1) + 0.5))], [1.7, 1.45, 0.95, 0.45, 0.08], ring=20, samples=6,
             flat=(1.3, 1.0), up=(0, 0, 1), name="Pick")
adze = sweep([V((0, 0, arc(0))), V((-3.0, 0, arc(-3.0))), V((-6.0, 0, arc(-6.0))), V((-8.4, 0, arc(-8.4) + 0.15))],
             [1.7, 1.45, 1.25, 1.2], ring=20, samples=6, flat=(0.95, 1.25), up=(0, 0, 1), cap_rings=3,
             name="Adze")
# la panne s'aplatit en lame vers le bout
deform(adze, lambda p: V((p.x, p.y * (1 + 0.5 * smoothstep(-3, -8.5, p.x)),
                          arc(p.x) + (p.z - arc(p.x)) * (1 - 0.62 * smoothstep(-2.5, -8.5, p.x)))))
eye = rbox((3.6, 3.0, 3.6), (0, 0, HZ), radius=0.85, segments=4)
kit.add("Head", "Metal", "A9B3C1", pick, adze, eye)

# origine = centre de l'œil de pivot (axe de balancement), en haut du manche
for o in kit.objects():
    xf(o, (0, 0, -1.05))
kit.build()
finish_char("Pickaxe", camera=cam((0.8, -2.4, 0.5)), samples=48, zoom=1.3)
