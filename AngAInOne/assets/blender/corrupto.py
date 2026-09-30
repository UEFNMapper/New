"""Corrupto — sbire du monde 3 (SSD) : cube de pixels « texture manquante » magenta/noir, 5 studs de haut,
regarde vers -Y. Voxels chanfreinés en damier, coins qui se détachent et flottent (certains en néon),
gros yeux carrés colériques, dents serrées en escalier, petits bras-voxels et pieds."""
from char_common import *

new_scene()
kit = Kit()
random.seed(7)

N = 6
S = 0.68                         # taille d'un voxel
G = 0.035                        # joint entre voxels
Z0 = 0.95                        # bas du cube (au-dessus des pieds)
HALF = N * S / 2
MAG, BLK = "FF00FF", "141414"


def vpos(i, j, k):
    return V(((i - (N - 1) / 2) * S, (j - (N - 1) / 2) * S, Z0 + (k + 0.5) * S))


def voxel(c, rot=(0, 0, 0), s=S):
    return rbox((s - G, s - G, s - G), c, radius=0.075, segments=2, rot=rot)


# voxels qui s'envolent : quelques coins/arêtes du haut + un voxel de face (non couvert par le visage)
flying = {(N - 1, 0, N - 1): V((0.45, -0.35, 0.75)), (0, N - 1, N - 1): V((-0.5, 0.35, 0.8)),
          (N - 1, N - 1, N - 1): V((0.55, 0.45, 1.35)), (2, N - 1, N - 1): V((0.1, 0.3, 0.6)),
          (N - 1, 3, N - 1): V((0.7, 0.0, 0.5)), (0, 0, N - 1): None,  # manquant (trou)
          (0, 2, N - 1): V((-0.4, 0.0, 0.55)), (N - 1, N - 1, 2): V((0.7, 0.2, -0.1))}
mag, blk, neon = [], [], []
for i in range(N):
    for j in range(N):
        for k in range(N):
            if 0 < i < N - 1 and 0 < j < N - 1 and 0 < k < N - 1:
                continue  # intérieur invisible
            if (i, j, k) in ((0, 0, 0), (N - 1, 0, 0), (0, N - 1, 0), (N - 1, N - 1, 0)):
                continue  # coins du bas arrondis
            c = vpos(i, j, k)
            is_mag = (i + j + k) % 2 == 0
            if (i, j, k) in flying:
                off = flying[(i, j, k)]
                if off is None:
                    continue
                rot = (random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(-0.6, 0.6))
                v = voxel(c + off, rot, S * 0.92)
                (neon if is_mag else blk).append(v)
                continue
            (mag if is_mag else blk).append(voxel(c))

# petits pixels « glitch » qui flottent autour
for p, s, isn in (((-2.9, -0.4, 4.2), 0.3, True), ((2.95, 0.3, 3.4), 0.24, False), ((-2.7, 0.6, 2.2), 0.2, True),
                  ((1.6, -0.9, 5.55), 0.26, True), ((-1.3, 1.1, 5.35), 0.2, False)):
    v = rbox((s, s, s), p, radius=0.04, segments=2, rot=(random.random(), random.random(), random.random()))
    (neon if isn else blk).append(v)

# petits bras-voxels (2 voxels + main)
for sx in (-1, 1):
    base = vpos(0 if sx < 0 else N - 1, 2, 2)
    for t in (1, 2):
        c = base + V((sx * S * 0.8 * t, -0.1 * t, -0.18 * t * t))
        ((mag if t % 2 else blk)).append(voxel(c, s=S * 0.72))
kit.add("Magenta", "SmoothPlastic", MAG, mag)
kit.add("Black", "SmoothPlastic", BLK, blk)
kit.add("Glitch", "Neon", MAG, neon)

FY = -HALF - S * 0 - 0.0   # face avant du cube
FRONT = -N * S / 2

# --- yeux carrés arrondis, pupilles carrées, reflets
white, dark = [], []
EZ = Z0 + S * 3.9
for sx in (-1, 1):
    ex = 0.82 * sx
    white.append(rbox((1.16, 0.34, 1.08), (ex, FRONT - 0.12, EZ), radius=0.24, segments=4))
    dark.append(rbox((0.58, 0.2, 0.6), (ex - 0.17 * sx, FRONT - 0.3, EZ - 0.12), radius=0.12, segments=3))
    white.append(rbox((0.16, 0.1, 0.16), (ex - 0.29 * sx, FRONT - 0.4, EZ + 0.02), radius=0.04, segments=2))
    # sourcil : barre inclinée, plus basse vers le centre
    brow = rbox((1.35, 0.4, 0.3), (0, 0, 0), radius=0.1, segments=3)
    xf(brow, (ex + 0.02 * sx, FRONT - 0.25, EZ + 0.62), (0, math.radians(-24 * sx), 0))
    dark.append(brow)

# --- bouche : rangée de dents carrées en escalier (grimace)
MZ = Z0 + S * 1.55
steps = [(-1.0, -0.14), (-0.6, 0.0), (-0.2, 0.08), (0.2, 0.08), (0.6, 0.0), (1.0, -0.14)]
lip = []
for x, dz in steps:
    white.append(rbox((0.36, 0.26, 0.42), (x, FRONT - 0.13, MZ + dz), radius=0.07, segments=2))
    lip.append((x, dz))
# contour sombre de la bouche derrière les dents
for x, dz in lip:
    dark.append(rbox((0.42, 0.18, 0.62), (x, FRONT - 0.05, MZ + dz), radius=0.06, segments=2))
kit.add("White", "SmoothPlastic", "FFFFFF", white)
kit.add("Dark", "SmoothPlastic", "1B0612", dark)

# --- jambes + pieds
for sx in (-1, 1):
    leg = sweep([V((0.9 * sx, 0, Z0 + 0.2)), V((0.95 * sx, -0.05, 0.3))], 0.2, ring=12, name="Leg")
    foot = rbox((0.75, 1.05, 0.34), (0.95 * sx, -0.22, 0.17), radius=0.14, segments=3)
    kit.add("Dark", "SmoothPlastic", "1B0612", leg)
    kit.add("Magenta", "SmoothPlastic", MAG, foot)

kit.build()
finish("Corrupto", camera=cam((0.9, -2.4, 0.9)), samples=48)
