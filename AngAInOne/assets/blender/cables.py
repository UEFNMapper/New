"""Câbles gainés : CableBraided24 (nappe ATX 24 brins en grand S, peignes alu, connecteurs) et
CableSleeved8 (câble PCIe 8 broches coudé). python3 cables.py [Nom…]"""
import sys
from hw_common import *


def frames(path_fn, n):
    """Repères (P, T, N, B) le long d'une courbe paramétrée (t ∈ [0, 1]), par transport parallèle
    (pas de vrille ni de dégénérescence quand la courbe devient verticale). Repère direct : N × T = B."""
    out = []
    N_prev = None
    for i in range(n + 1):
        t = i / n
        p = Vector(path_fn(t))
        d = Vector(path_fn(min(1, t + 1e-3))) - Vector(path_fn(max(0, t - 1e-3)))
        T_ = d.normalized()
        if N_prev is None:
            N_ = T_.cross(Vector((0, 0, 1)))
            if N_.length < 1e-4:
                N_ = T_.cross(Vector((0, 1, 0)))
        else:
            N_ = N_prev - T_ * N_prev.dot(T_)
        N_.normalize()
        B_ = N_.cross(T_)
        out.append((p, T_, N_, B_))
        N_prev = N_
    return out


def frame_at(path_fn, t, n=200):
    fr = frames(path_fn, n)
    return fr[min(n, max(0, round(t * n)))]


def bundle(path_fn, cols, rows, pitch, radius, colors, n=24, sides=8, res=3, t0=0.0, t1=1.0):
    """Nappe de brins gainés. colors(i, j) → clé de couleur ; renvoie {clé: [objets]}."""
    fr = frames(lambda t: path_fn(t0 + (t1 - t0) * t), n)
    groups = {}
    for i in range(cols):
        for j in range(rows):
            off_n = (i - (cols - 1) / 2) * pitch
            off_b = (j - (rows - 1) / 2) * pitch
            pts = [tuple(p + N_ * off_n + B_ * off_b) for p, T_, N_, B_ in fr]
            groups.setdefault(colors(i, j), []).append(pipe(pts, radius, sides, res, cap=True))
    return groups


def comb(path_fn, t, cols, rows, pitch, radius):
    """Peigne de câbles orienté selon la tangente en t."""
    p, T_, N_, B_ = frame_at(path_fn, t)
    w = cols * pitch + 0.9
    h = rows * pitch + 0.9
    c = rbox((w, 1.2, h), (0, 0, 0), r=0.35, seg=2)
    holes = [rcyl(radius + 0.05, 3, ((i - (cols - 1) / 2) * pitch, 0, (j - (rows - 1) / 2) * pitch), verts=12,
                  rot=(math.pi / 2, 0, 0)) for i in range(cols) for j in range(rows)]
    bool_op(c, holes)
    # repère local (x = N, y = T, z = B) → monde
    M = Matrix(((N_.x, T_.x, B_.x, p.x), (N_.y, T_.y, B_.y, p.y), (N_.z, T_.z, B_.z, p.z), (0, 0, 0, 1)))
    c.data.transform(M)
    c.data.update()
    return c


def connector(path_fn, t_end, cols, rows, pitch, length, outward, latch=True):
    """Boîtier de connecteur au bout de la nappe (outward = +1 si le connecteur prolonge la fin)."""
    p, T_, N_, B_ = frame_at(path_fn, t_end)
    T_ = T_ * outward
    N_ = N_ * outward        # garde un repère direct (N × T = B)
    w, h = cols * pitch + 0.8, rows * pitch + 0.8
    body = rbox((w, length, h), (0, length / 2 - 0.3, 0), r=0.3, seg=2)
    # alvéoles sur la face avant
    holes = [rbox((pitch * 0.62, 1.2, pitch * 0.62), ((i - (cols - 1) / 2) * pitch, length - 0.2,
                                                     (j - (rows - 1) / 2) * pitch)) for i in range(cols) for j in range(rows)]
    bool_op(body, holes)
    parts = [body]
    if latch:
        parts.append(rbox((1.6, length * 0.55, 0.5), (0, length * 0.55, h / 2 + 0.3), r=0.12, seg=1))
        parts.append(rbox((1.6, 0.6, 1.0), (0, length * 0.84, h / 2 + 0.55), r=0.1, seg=1))
    o = merge(parts)
    M = Matrix(((N_.x, T_.x, B_.x, p.x), (N_.y, T_.y, B_.y, p.y), (N_.z, T_.z, B_.z, p.z), (0, 0, 0, 1)))
    o.data.transform(M)
    o.data.update()
    return o


def braided24():
    reset()
    cols, rows, pitch, r = 12, 2, 1.12, 0.53

    def path(t):
        x = -36.0 + 72.0 * t
        y = 11.0 * math.sin(2 * math.pi * t) * (1 - 0.15 * math.cos(2 * math.pi * t))
        z = 1.7 + 4.5 * math.sin(math.pi * t) ** 2
        return (x, y, z)

    def color(i, j):
        if i in (0, 11):
            return "grey"
        return "violet" if (i + j) % 3 == 0 else "black"

    g = bundle(path, cols, rows, pitch, r, color, n=26)
    tag(merge(g["black"]), "SleeveBlack", "Fabric", GRAPHITE_0)
    tag(merge(g["violet"]), "SleeveViolet", "Fabric", ACCENT)
    tag(merge(g["grey"]), "SleeveGrey", "Fabric", "C9CDD4")
    combs = [comb(path, t, cols, rows, pitch, r) for t in (0.27, 0.5, 0.73)]
    tag(merge(combs), "Combs", "Metal", ALU)
    heads = [connector(path, 0.0, cols, rows, pitch, 5.2, -1), connector(path, 1.0, cols, rows, pitch, 5.2, +1)]
    tag(merge(heads), "Connectors", "SmoothPlastic", GRAPHITE_0)
    done("CableBraided24", camera=(0.6, -1.5, 1.6))


def sleeved8():
    reset()
    cols, rows, pitch, r = 4, 2, 1.12, 0.53

    def path(t):
        # départ horizontal, grand coude à 90° vers le haut puis retour (câble GPU)
        a = t * math.pi / 2
        if t < 0.45:
            return (-16.0 + 30.0 * t, 0.0, 2.0)
        u = (t - 0.45) / 0.55
        ang = u * math.pi / 2
        return (-2.5 + 9.0 * math.sin(ang), 0.0, 2.0 + 9.0 * (1 - math.cos(ang)) + 14.0 * u * u)

    def color(i, j):
        return "violet" if i in (1, 2) and j == 1 else "black"

    g = bundle(path, cols, rows, pitch, r, color, n=24)
    tag(merge(g["black"]), "SleeveBlack", "Fabric", GRAPHITE_0)
    tag(merge(g["violet"]), "SleeveViolet", "Fabric", ACCENT)
    tag(merge([comb(path, 0.3, cols, rows, pitch, r), comb(path, 0.75, cols, rows, pitch, r)]), "Combs", "Metal", ALU)
    heads = [connector(path, 0.0, cols, rows, pitch, 4.6, -1), connector(path, 1.0, cols, rows, pitch, 4.6, +1)]
    tag(merge(heads), "Connectors", "SmoothPlastic", GRAPHITE_0)
    done("CableSleeved8", camera=(0.9, -1.6, 0.8))


JOBS = {"CableBraided24": braided24, "CableSleeved8": sleeved8}
if __name__ == "__main__":
    for key in (sys.argv[1:] or JOBS):
        JOBS[key]()
