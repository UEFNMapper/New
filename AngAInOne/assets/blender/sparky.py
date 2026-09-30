"""Sparky — sbire du monde 1 (alimentation) : petite étincelle jaune colérique, 5 studs de haut.
Coque orange lisse, cœur néon jaune qui jaillit en éclairs, gros sourcils froncés, dents serrées,
petits poings et petits pieds. Regarde vers -Y."""
from char_common import *

new_scene()
kit = Kit()

CZ, R = 2.45, 1.45           # centre et rayon de la coque
C = V((0, 0, CZ))

# --- coque : boule légèrement en poire, un peu écrasée
shell = qsphere(R, C, (1.0, 0.94, 0.97), level=4, name="Shell")
deform(shell, lambda p: p + V((0, 0, -0.10 * max(0.0, (CZ - p.z)) ** 1.5 * 0.3)))
kit.add("Shell", "SmoothPlastic", "F6AD55", shell)
tree = bvh(shell)

# --- cœur néon : éclairs en zigzag qui rayonnent (pas sur le visage ni vers le sol)
random.seed(4)
dirs = [(0.0, 0.15, 1.0), (-0.55, 0.2, 0.85), (0.55, 0.2, 0.85), (-0.95, 0.15, 0.35), (0.95, 0.15, 0.35),
        (-0.3, 0.85, 0.55), (0.3, 0.85, 0.55), (0.0, 1.0, 0.05), (-0.8, 0.55, -0.2), (0.8, 0.55, -0.2),
        (-0.25, -0.45, 0.95), (0.25, -0.45, 0.95)]
bolts = []
for i, d in enumerate(dirs):
    d = V(d).normalized()
    side = d.cross(V((0, 0, 1)) if abs(d.z) < 0.95 else V((1, 0, 0))).normalized()
    L = 2.05 if d.z > 0.8 else (1.85 if d.z > 0.3 else 1.6)
    k = 0.12 if i % 2 else -0.12
    # pic lisse légèrement recourbé (rayon d'étoile)
    pts = [C + d * R * 0.6, C + d * R * 1.0, C + d * R * 1.3 + side * k, C + d * R * L + side * k * 2.2]
    bolts.append(sweep(pts, [0.52, 0.4, 0.22, 0.03], ring=14, samples=6, name="Bolt"))
core = qsphere(R * 0.9, C, level=2, name="Core")  # cœur plein (lié aux éclairs)
kit.add("Core", "Neon", "F6E05E", bolts, core)

# --- yeux colériques
eyes = []
for sx in (-1, 1):
    x, z = 0.5 * sx, CZ + 0.28
    loc, nrm = surface_point(tree, x, z)
    ctr = loc + V((0, 0.2, 0))
    e = cartoon_eye(ctr, 0.4, look=(-0.3 * sx, -0.05), squash=(0.95, 0.6, 1.15), pupil=0.64,
                    lid=(24 * -sx, 0.36))
    kit.add("EyeWhite", "SmoothPlastic", "FFFFFF", e["white"], e["shine"])
    kit.add("Pupil", "SmoothPlastic", "1B1B2F", e["pupil"])
    kit.add("Shell", "SmoothPlastic", "F6AD55", e["lid"])
    # sourcil épais en biseau, plus bas vers le centre
    b0 = surface_point(tree, 0.92 * sx, CZ + 0.95)[0] + V((0, -0.08, 0))
    b1 = surface_point(tree, 0.5 * sx, CZ + 0.8)[0] + V((0, -0.12, 0))
    b2 = surface_point(tree, 0.1 * sx, CZ + 0.55)[0] + V((0, -0.1, 0))
    kit.add("Brow", "SmoothPlastic", "5A2E0E", sweep([b0, b1, b2], [0.1, 0.16, 0.13], ring=12, flat=(1, 0.75)))

# --- bouche : grimace, dents serrées
def superellipse(w, h, bend, n=64, e=6):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        x = w / 2 * math.copysign(abs(c) ** (2 / e), c)
        y = h / 2 * math.copysign(abs(s) ** (2 / 2.4), s)
        pts.append((x, y - bend * (2 * x / w) ** 2))
    return pts

MZ = CZ - 0.5
mouth = patch(superellipse(1.05, 0.42, 0.12), tree, (0, -5, MZ), (1, 0, 0), (0, 0, 1), (0, 1, 0),
              lift=0.0, thickness=0.05, cuts=3, name="Mouth")
kit.add("Brow", "SmoothPlastic", "5A2E0E", mouth)
teeth = []
for row, dz in ((0, 0.085), (1, -0.085)):
    for i in range(5):
        x = (i - 2) * 0.185
        z = MZ + dz - 0.12 * (2 * x / 1.05) ** 2
        loc, nrm = surface_point(tree, x, z)
        rz = math.atan2(nrm.x, -nrm.y)
        t = rbox((0.16, 0.12, 0.15), (0, 0, 0), radius=0.045, segments=3)
        xf(t, loc + V((0, -0.035, 0)), (0, 0, -rz))
        teeth.append(t)
kit.add("EyeWhite", "SmoothPlastic", "FFFFFF", teeth)

# --- petits bras (poings levés)
for sx in (-1, 1):
    a0 = C + V((1.25 * sx, -0.1, -0.35))
    arm = sweep([a0, a0 + V((0.35 * sx, -0.1, 0.05)), a0 + V((0.55 * sx, -0.25, 0.4))], [0.17, 0.15, 0.14],
                ring=12, name="Arm")
    fist = qsphere(0.27, a0 + V((0.6 * sx, -0.3, 0.55)), (1, 0.95, 1.05), level=3, name="Fist")
    thumb = qsphere(0.11, a0 + V((0.47 * sx, -0.5, 0.58)), level=2, name="Thumb")
    kit.add("Shell", "SmoothPlastic", "F6AD55", arm, fist, thumb)

# --- petits pieds
for sx in (-1, 1):
    leg = sweep([V((0.45 * sx, 0, 1.2)), V((0.5 * sx, -0.05, 0.45))], 0.16, ring=10, name="Leg")
    foot = qsphere(0.36, (0.52 * sx, -0.18, 0.22), (0.9, 1.25, 0.62), level=3, name="Foot")
    deform(foot, lambda p: V((p.x, p.y, max(p.z, 0.0))))
    kit.add("Feet", "SmoothPlastic", "C05621", leg, foot)

kit.build()
finish("Sparky", camera=(0.9, -2.4, 0.9), samples=48)
