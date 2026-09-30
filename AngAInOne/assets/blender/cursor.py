"""Curseurs géants (20 studs de haut), blancs avec contour noir en VOLUME (coque noire élargie sur la silhouette
et plus mince en profondeur : elle dessine le trait noir tout autour, vu de face comme de dos).
- GiantCursor : flèche de souris debout, pointe en haut à gauche, face avant vers -Y.
- Hand        : main « lien » (index levé, 3 doigts repliés, pouce), face avant vers -Y.

    python3 cursor.py              # les deux
    python3 cursor.py Hand
"""
from char_common import *

WHITE, BLACK = "F2F2F5", "111114"


def outline_of(o, d=0.45, yscale=0.7, yc=0.0):
    """Coque de contour : copie gonflée de `d` dans le plan XZ (le long des normales) et aplatie en Y."""
    n = copy(o)
    n.data.update()
    data = [(v.co.copy(), v.normal.copy()) for v in n.data.vertices]
    for v, (c, nr) in zip(n.data.vertices, data):
        nxz = V((nr.x, 0.0, nr.z))
        p = c + nxz * d
        p.y = yc + (p.y - yc) * yscale
        v.co = p
    n.data.update()
    return n


def prism(poly, depth, bevel_w=0.35, segs=3):
    """Polygone (x, z) extrudé en Y (centré sur y=0), arêtes avant/arrière arrondies."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, -depth / 2, z)) for x, z in poly]
    f = bm.faces.new(vs)
    ret = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.y += depth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rim = [e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) < 1e-6]
    bmesh.ops.bevel(bm, geom=rim, offset=bevel_w, segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    o = _link_bm(bm)
    shade(o, flat_angle=50)
    return o


def _link_bm(bm):
    from char_common import _link
    return _link(bm, "Prism")


def giant_cursor():
    new_scene()
    kit = Kit()
    # flèche classique (pixels, y vers le bas) -> (x, z)
    px = [(0, 0), (0, 15.6), (3.7, 12.3), (6.35, 18.3), (8.75, 17.25), (6.1, 11.35), (10.9, 11.35)]
    k = 1.0
    poly = [(x * k - 5.0, (19.0 - y) * k) for x, y in px]
    # contour noir : polygone décalé (onglets) extrudé moins épais
    off = 0.85
    n = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n)) / 2
    sgn = 1 if area > 0 else -1
    out = []
    for i in range(n):
        p0, p1, p2 = V((*poly[i - 1], 0)), V((*poly[i], 0)), V((*poly[(i + 1) % n], 0))
        e0 = (p1 - p0).normalized(); e1 = (p2 - p1).normalized()
        n0 = V((e0.y, -e0.x, 0)) * sgn; n1 = V((e1.y, -e1.x, 0)) * sgn
        bis = (n0 + n1).normalized()
        L = off / max(bis.dot(n1), 0.3)
        q = p1 + bis * L
        out.append((q.x, q.y))
    white = prism(poly, 2.2, bevel_w=0.5, segs=5)
    black = prism(out, 1.4, bevel_w=0.35, segs=4)
    kit.add("Arrow", "SmoothPlastic", WHITE, white)
    kit.add("Outline", "SmoothPlastic", BLACK, black)
    z = drop_to_ground()
    objs = [white, black]
    zmax = max(v.co.z for o in objs for v in o.data.vertices)
    for o in objs:
        xf_matrix(o, Matrix.Scale(20.0 / zmax, 4))
    center_x(objs)
    kit.build()
    finish_char("GiantCursor", camera=cam((0.8, -2.4, 0.6)), samples=48, zoom=1.25)


def center_x(objs):
    xs = [v.co.x for o in objs for v in o.data.vertices]
    for o in objs:
        xf(o, (-(min(xs) + max(xs)) / 2, 0, 0))


def capsule(a, b, r):
    return sweep([V(a), V(b)], r, ring=24, samples=2, cap_rings=6, name="Capsule")


def hand():
    new_scene()
    kit = Kit()
    shapes = []
    # poignet / manchette
    shapes.append(rbox((7.0, 3.2, 2.3), (1.3, 0, 1.25), radius=0.9, segments=5))
    # paume
    palm = rbox((8.0, 3.4, 7.0), (1.3, 0, 6.0), radius=1.6, segments=6)
    subsurf(palm, 1)
    shapes.append(palm)
    # index levé
    shapes.append(capsule((-1.45, 0, 8.0), (-1.45, 0, 18.6), 1.3))
    # 3 doigts repliés (bosses vues de face)
    for i, (x, z) in enumerate(((1.05, 9.75), (3.05, 9.55), (4.85, 9.0))):
        shapes.append(capsule((x, 0.25, z - 0.5), (x, -0.35, z), 1.08))
    # pouce
    shapes.append(capsule((-2.2, 0, 4.6), (-4.1, -0.2, 7.2), 1.15))
    whites, blacks = [], []
    for s in shapes:
        blacks.append(outline_of(s, d=0.5, yscale=0.62))
        whites.append(s)
    # traits de la manchette (2 rainures noires)
    for x in (-0.6, 3.2):
        blacks.append(rbox((0.28, 3.45, 1.7), (x, 0, 1.25), radius=0.12, segments=2))
    kit.add("Glove", "SmoothPlastic", WHITE, whites)
    kit.add("Outline", "SmoothPlastic", BLACK, blacks)
    objs = whites + blacks
    z = drop_to_ground(objs)
    zmax = max(v.co.z for o in objs for v in o.data.vertices)
    for o in objs:
        xf_matrix(o, Matrix.Scale(20.0 / zmax, 4))
    center_x(objs)
    kit.build()
    finish_char("Hand", camera=cam((0.8, -2.4, 0.6)), samples=48, zoom=1.25)


if __name__ == "__main__":
    which = sys.argv[1:] or ["GiantCursor", "Hand"]
    if "GiantCursor" in which:
        giant_cursor()
    if "Hand" in which:
        hand()
