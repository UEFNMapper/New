"""LAGZ — le grand méchant (boss) : blob violet glitché, ~40 studs de haut, regarde vers -Y.
- corps en goutte qui « fond » à la base, ventre plus clair (2e coque), petits bras trapus
- tranches « glitch » décalées horizontalement + franges RVB néon (cyan / magenta)
- gros yeux en pixels (néon), sourire en zigzag plein de dents
- couronne = roue de chargement de 8 points (pièce __Spin, origine sur son axe vertical)
Génère aussi LagzHead (12 studs) : tête + haut du corps, pour sortir des écrans.

    python3 lagz.py            # les deux
    python3 lagz.py Lagz       # un seul
"""
from char_common import *

BODY = "6B46C1"
BELLY = "9F7AEA"
EYE = "B8F5FF"
DARK = "1E0B33"
TOOTH = "F7F2FF"
CROWN = "E9D8FD"


def body_mesh():
    b = qsphere(1.0, n=26, name="Body")

    def shape(p):
        x, y, z = p
        ang = math.atan2(y, x)
        Z = 16.0 + 17.5 * z
        rx, ry = 14.0, 12.4
        # base plus large (goutte qui s'étale)
        w = 1.0 + 0.2 * smoothstep(14.0, 1.0, Z)
        # lobes « fondus » à la base
        w *= 1.0 + 0.11 * max(0.0, math.sin(6 * ang + 0.7)) ** 2 * smoothstep(8.0, 1.0, Z)
        # léger tremblement de gelée
        w *= 1.0 + 0.035 * noise.noise(V((x * 1.6, y * 1.6, z * 1.6 + 3.0)))
        X, Y = x * rx * w, y * ry * w
        # sol plat aux bords arrondis (softplus)
        floor, k = 0.8, 1.2
        Z = floor + math.log1p(math.exp(k * (Z - floor))) / k
        return V((X, Y, Z))

    deform(b, shape)
    shade(b)
    return b


def belly_of(body):
    bl = copy(body)
    bl.name = "Belly"

    def f(p):
        w = math.exp(-((p.x / 8.5) ** 2 + ((p.z - 7.0) / 6.0) ** 2) ** 1.5) * smoothstep(-2.0, -8.0, p.y)
        q = V((p.x * 0.985, p.y * 0.985, p.z))
        return q + V((0, -1.3 * w, 0.0))

    deform(bl, f)
    # ne garde que la partie visible (devant le corps) : économise des triangles
    bm = bmesh.new(); bm.from_mesh(bl.data)
    hidden = [fc for fc in bm.faces
              if all(math.exp(-((v.co.x / 8.5) ** 2 + ((v.co.z - 7.0) / 6.0) ** 2) ** 1.5)
                     * smoothstep(-2.0, -8.0, v.co.y) < 0.03 for v in fc.verts)]
    bmesh.ops.delete(bm, geom=hidden, context="FACES")
    bm.to_mesh(bl.data); bm.free(); bl.data.update()
    return bl


EYE_L = ["bb0000",
         "11bb00",
         "1111bb",
         "111221",
         "111221",
         "011110"]


def pixel_eyes(tree, kit, cx, cz, px):
    """Yeux en pixels : '1' pixel néon, '2' pupille sombre, 'b' sourcil sombre (plus saillant)."""
    ncol = len(EYE_L[0])
    for side in (-1, 1):
        rows = EYE_L if side < 0 else [r[::-1] for r in EYE_L]
        for ri, row in enumerate(rows):
            for ci, ch in enumerate(row):
                if ch == "0":
                    continue
                x = side * cx + (ci - (ncol - 1) / 2) * px
                z = cz + ((len(rows) - 1) / 2 - ri) * px
                loc, nrm = surface_point(tree, x, z)
                depth = {"1": 1.5, "2": 1.85, "b": 2.3}[ch]
                blk = rbox((px * 0.9, depth, px * 0.9), (0, 0, 0), radius=px * 0.17, segments=2)
                xf_matrix(blk, align_matrix(loc + nrm * (depth / 2 - 0.75), nrm))
                if ch == "1":
                    kit.add("Eyes", "Neon", EYE, blk)
                else:
                    kit.add("Dark", "SmoothPlastic", DARK, blk)
        # petit reflet carré sur la pupille (coin haut, côté extérieur)
        r, c = 3, 3 if side < 0 else ncol - 1 - 3
        x = side * cx + (c - (ncol - 1) / 2) * px - 0.22 * px * (-side)
        z = cz + ((len(EYE_L) - 1) / 2 - r) * px + 0.22 * px
        loc, nrm = surface_point(tree, x, z)
        hl = rbox((px * 0.36, 2.3, px * 0.36), (0, 0, 0), radius=px * 0.08, segments=2)
        xf_matrix(hl, align_matrix(loc + nrm * (2.3 / 2 - 0.75), nrm))
        kit.add("Eyes", "Neon", EYE, hl)


def grin(tree, kit, zm, w):
    """Sourire en croissant, dents en zigzag."""
    def centre(t):
        return zm + 2.3 * t * t

    def thick(t):
        return 3.6 * (1 - t * t) ** 0.75 + 0.35

    pts = []
    N = 48
    for i in range(N + 1):  # bord haut, de gauche à droite
        t = -1 + 2 * i / N
        pts.append((t * w / 2, centre(t) + thick(t) * 0.32))
    for i in range(N, -1, -1):  # bord bas
        t = -1 + 2 * i / N
        pts.append((t * w / 2, centre(t) - thick(t) * 0.68))
    pts = pts[:-1]
    m = patch(pts, tree, (0, -40, 0), (1, 0, 0), (0, 0, 1), (0, 1, 0), lift=0.0, thickness=0.25, cuts=4,
              name="Mouth")
    kit.add("Dark", "SmoothPlastic", DARK, m)
    # langue
    tl, tn = surface_point(tree, 1.2, centre(0.1) - thick(0.1) * 0.45)
    tongue = qsphere(1.0, (0, 0, 0), (1.9, 0.5, 1.0), level=3)
    xf_matrix(tongue, align_matrix(tl + tn * 0.05, tn))
    kit.add("Tongue", "SmoothPlastic", "E0529C", tongue)
    # dents : rangée du haut (pointes vers le bas) et du bas (pointes vers le haut), en quinconce
    teeth = []
    for row in ("top", "bot"):
        n = 5 if row == "top" else 4
        for i in range(n):
            t = (-0.72 + 1.44 * i / (n - 1)) if row == "top" else (-0.54 + 1.08 * i / (n - 1))
            x = t * w / 2
            if row == "top":
                z0 = centre(t) + thick(t) * 0.32 + 0.2
                z1 = z0 - (1.55 + 0.35 * (1 - abs(t)))
            else:
                z0 = centre(t) - thick(t) * 0.68 - 0.15
                z1 = z0 + (1.2 + 0.25 * (1 - abs(t)))
            l0, n0 = surface_point(tree, x, z0)
            l1, n1 = surface_point(tree, x, z1)
            base = l0 + n0 * 0.05
            tip = l1 + n1 * 0.2
            tooth = sweep([base, base * 0.55 + tip * 0.45, tip], [1.05, 0.72, 0.22], ring=14, samples=4,
                          flat=(1.0, 0.5), up=V((1, 0, 0)), cap_start=True, name="Tooth")
            teeth.append(tooth)
    kit.add("Teeth", "SmoothPlastic", TOOTH, teeth)


def arms(tree, kit):
    parts = []
    for sx in (-1, 1):
        sh = V((12.6 * sx, -2.5, 15.5))
        el = V((16.3 * sx, -4.8, 14.2 + (2.2 if sx < 0 else -0.6)))
        hand_c = V((17.6 * sx, -6.6, 15.8 + (3.6 if sx < 0 else -0.8)))
        parts.append(sweep([sh, el, hand_c], [2.5, 2.0, 1.7], ring=14, samples=6, name="Arm"))
        parts.append(qsphere(2.3, hand_c, (1.0, 0.95, 1.0), level=3, name="Hand"))
        # 3 griffes/doigts potelés vers l'avant
        for k in (-1, 0, 1):
            d = V((0.25 * sx + 0.35 * k * sx * 0.3, -1.0, 0.35 * k)).normalized()
            f0 = hand_c + d * 1.4
            parts.append(sweep([f0, f0 + d * 1.7 + V((0, 0, -0.3))], [0.85, 0.6], ring=12, name="Finger"))
    kit.add("Body", "SmoothPlastic", BODY, parts)


def crown(tree, kit):
    """Roue de chargement : anneau + 8 points de taille croissante sur de petites tiges."""
    R = 6.2
    loc, nrm = raycast(tree, (R, 0, 60), (0, 0, -1))
    zc = loc.z + 0.2
    pieces = [torus(R, 0.6, (0, 0, zc), major=64, minor=12)]
    for i in range(8):
        a = 2 * math.pi * i / 8 + math.pi / 2
        s = 0.8 + 1.15 * (i / 7)  # du plus petit au plus gros : l'effet « chargement » en tournant
        base = V((R * math.cos(a), R * math.sin(a), zc))
        out = V((math.cos(a), math.sin(a), 0))
        top = base + out * 0.9 + V((0, 0, 2.6))
        pieces.append(sweep([base, base + out * 0.2 + V((0, 0, 1.1)), top], [0.5, 0.42, 0.36], ring=10,
                            name="Post"))
        pieces.append(qsphere(s, top + V((0, 0, s * 0.8)), n=7, name="Dot"))
    kit.add("Crown", "Neon", CROWN, pieces, spin=True, pivot=(0, 0, zc))


BANDS = [(7.5, 9.0, 1.4), (23.2, 24.6, 1.1), (30.6, 31.4, -0.8)]


def glitch(kit, body, bands):
    ghosts_c, ghosts_m = [], []
    for z0, z1, dx in bands:
        s = 1 if dx > 0 else -1
        sl = slab(body, z0 + 0.12, z1 - 0.12)
        g1 = copy(sl)
        deform(sl, lambda p, dx=dx, s=s: V((p.x * 0.995 + dx + 0.75 * s, p.y * 0.95, p.z)))
        deform(g1, lambda p, dx=dx, s=s: V((p.x * 0.995 + dx - 0.75 * s - 0.0, p.y * 0.95, p.z)))
        # magenta côté du décalage, cyan de l'autre
        (ghosts_m if s > 0 else ghosts_c).append(sl)
        (ghosts_c if s > 0 else ghosts_m).append(g1)
    for name, objs in kit.parts.items():
        if name == "Crown":
            continue
        for o in objs["objs"]:
            for z0, z1, dx in bands:
                slice_shift(o, z0, z1, (dx, 0, 0))
    kit.add("GlitchCyan", "Neon", "00E5FF", ghosts_c)
    kit.add("GlitchPink", "Neon", "FF3DF2", ghosts_m)


def build(head_only=False):
    new_scene()
    kit = Kit()
    body = body_mesh()
    belly = belly_of(body)
    kit.add("Body", "SmoothPlastic", BODY, body)
    kit.add("Belly", "SmoothPlastic", BELLY, belly)
    tree = bvh_multi([body, belly])
    pixel_eyes(tree, kit, 5.6, 23.2, 1.45)
    grin(tree, kit, 14.2, 15.5)
    if not head_only:
        arms(tree, kit)
    crown(tree, kit)
    bands = BANDS if not head_only else BANDS[1:]
    glitch(kit, body, bands)
    if head_only:
        zcut = 11.0
        for name, p in kit.parts.items():
            keep = []
            for o in p["objs"]:
                r = cut_below(o, zcut)
                if r is not None:
                    keep.append(r)
            p["objs"] = keep
        for o in kit.objects():
            xf(o, (0, 0, -zcut))
        pv = kit.parts["Crown"]["pivot"]
        kit.parts["Crown"]["pivot"] = V((0, 0, pv[2] - zcut))
        kit.fit_height(12.0)
    else:
        z = drop_to_ground()
        pv = kit.parts["Crown"]["pivot"]
        kit.parts["Crown"]["pivot"] = V((0, 0, pv[2] - z))
        kit.fit_height(40.0)
    kit.build()
    name = "LagzHead" if head_only else "Lagz"
    finish(name, camera=cam((0.8, -2.4, 0.7)), samples=48)


if __name__ == "__main__":
    which = sys.argv[1:] or ["Lagz", "LagzHead"]
    if "Lagz" in which:
        build(False)
    if "LagzHead" in which:
        build(True)
