"""
char_common.py — outils de modélisation « organique » pour les personnages et objets d'AngAInOne.

S'appuie sur common.py (conventions, export, rendu) SANS le modifier. Ajoute :
- new_scene()            : reset + vidage du cache de matériaux de common (voir note plus bas)
- qsphere / ellipsoïde   : sphère à quads réguliers (cube sphérifié) -> formes organiques propres
- rbox                   : boîte à coins arrondis (chanfrein multi-segments, faces lisses)
- sweep                  : tube à rayon variable le long d'une courbe lisse (bras, pics, sourcils, queue…)
- lathe                  : pièce de révolution à partir d'un profil (r, z)
- deform / displace      : sculpture par code (fonction sur les sommets, bruit le long des normales)
- subsurf                : subdivision appliquée
- raycast / patch        : formes 2D (bouche, logo) plaquées sur une surface puis épaissies
- text_mesh              : texte en relief (police intégrée de Blender)
- Kit                    : regroupe les morceaux par pièce Roblox (nom + matériau + couleur), joint et nomme

Tous les objets créés ici ont leur transformation appliquée (matrice identité) : coordonnées
locales = coordonnées monde, ce qui simplifie les raycasts et les jointures.

NOTE (bug contourné de common.py) : common.material() garde un cache `_mats` qui survit à reset()
alors que reset() détruit les matériaux -> un script qui génère plusieurs modèles de suite planterait
(ReferenceError). new_scene() vide ce cache après chaque reset.
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from common import *  # noqa: F401,F403  (reset, tag, finish, join, apply_modifiers, active, ...)
import bpy, bmesh
from mathutils import Vector, Matrix, Euler, noise
from mathutils.bvhtree import BVHTree

V = Vector
NEON_PREVIEW = 0.9  # force d'émission des néons dans les aperçus


# ---------------------------------------------------------------------------------------------
# Scène
# ---------------------------------------------------------------------------------------------
def new_scene():
    """Scène vide + cache de matériaux vidé (contourne le cache périmé de common.material)."""
    reset()
    common._mats.clear()
    sc = bpy.context.scene
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass


def _link(bm, name="Part"):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o


def xf(o, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Transforme directement les sommets (l'objet reste en matrice identité)."""
    if isinstance(scale, (int, float)):
        scale = (scale, scale, scale)
    m = Matrix.LocRotScale(V(loc), Euler(rot).to_quaternion(), V(scale))
    o.data.transform(m)
    o.data.update()
    return o


def xf_matrix(o, m):
    o.data.transform(m)
    o.data.update()
    return o


def freeze(o):
    """Applique la transformation objet dans les sommets (location/rotation/scale -> identité)."""
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    o.data.update()
    return o


def shade(o, flat_angle=None):
    """Ombrage lisse partout (formes organiques). flat_angle : arêtes plus vives que cet angle = nettes."""
    for p in o.data.polygons:
        p.use_smooth = True
    if "sharp_edge" in o.data.attributes:
        o.data.attributes.remove(o.data.attributes["sharp_edge"])
    if flat_angle is not None:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        lim = math.radians(flat_angle)
        for e in bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0) > lim:
                e.smooth = False
        bm.to_mesh(o.data)
        bm.free()
    o.data.update()
    return o


def copy(o):
    n = o.copy()
    n.data = o.data.copy()
    bpy.context.collection.objects.link(n)
    return n


def mirror_x(o):
    """Copie miroir (gauche/droite) d'un objet, normales corrigées."""
    n = copy(o)
    xf_matrix(n, Matrix.Scale(-1, 4, V((1, 0, 0))))
    bm = bmesh.new(); bm.from_mesh(n.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(n.data); bm.free(); n.data.update()
    return n


def delete(o):
    bpy.data.objects.remove(o, do_unlink=True)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


# ---------------------------------------------------------------------------------------------
# Primitives organiques
# ---------------------------------------------------------------------------------------------
def qsphere(r=1.0, loc=(0, 0, 0), scale=(1, 1, 1), level=3, rot=(0, 0, 0), name="Sphere", n=None):
    """Sphère à quads réguliers : cube subdivisé, déformation tangente, projeté sur la sphère.
    level 2 = 96 quads, 3 = 384, 4 = 1536 ; n = subdivisions par face (remplace level)."""
    n = n or 2 ** level
    bm = bmesh.new()
    verts = {}

    def vid(key, co):
        if key not in verts:
            verts[key] = bm.verts.new(co)
        return verts[key]

    t = lambda i: math.tan((i / n * 2 - 1) * math.pi / 4)
    faces_def = [  # (axe fixe, signe, axe u, axe v)
        (0, 1, 1, 2), (0, -1, 2, 1), (1, 1, 2, 0), (1, -1, 0, 2), (2, 1, 0, 1), (2, -1, 1, 0)]
    for ax, sg, au, av in faces_def:
        grid = [[None] * (n + 1) for _ in range(n + 1)]
        for i in range(n + 1):
            for j in range(n + 1):
                c = [0, 0, 0]
                c[ax] = sg; c[au] = t(i); c[av] = t(j)
                cv = V(c).normalized()
                key = tuple(round(x, 5) for x in cv)
                grid[i][j] = vid(key, cv)
        for i in range(n):
            for j in range(n):
                q = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                if sg < 0:
                    q.reverse()
                try:
                    bm.faces.new(q)
                except ValueError:
                    pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _link(bm, name)
    xf(o, loc, rot, (scale[0] * r, scale[1] * r, scale[2] * r) if not isinstance(scale, (int, float)) else scale * r)
    shade(o)
    return o


def rbox(size, loc=(0, 0, 0), radius=0.1, segments=4, rot=(0, 0, 0), name="Box"):
    """Boîte aux arêtes arrondies (chanfrein rond), ombrage lisse : aspect jouet moulé."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    radius = min(radius, min(size) * 0.499)
    if radius > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=radius, segments=segments,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    o = _link(bm, name)
    xf(o, loc, rot)
    shade(o, flat_angle=None)
    return o


def _catmull(pts, samples):
    """Interpolation Catmull-Rom (passe par les points)."""
    pts = [V(p) if not isinstance(p, (int, float)) else p for p in pts]
    if len(pts) < 2:
        return pts
    out = []
    ext = [pts[0] + (pts[0] - pts[1]) if not isinstance(pts[0], (int, float)) else 2 * pts[0] - pts[1]] + pts + \
          [pts[-1] + (pts[-1] - pts[-2]) if not isinstance(pts[0], (int, float)) else 2 * pts[-1] - pts[-2]]
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                              (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def sweep(points, radii, ring=16, samples=6, cap_start=True, cap_end=True, cap_rings=4, flat=None,
          twist=0.0, name="Sweep", up=None):
    """Tube lisse à rayon variable. points : liste de positions ; radii : un rayon par point (ou nombre).
    flat : (sx, sy) aplatit la section (sourcils, lèvres). Extrémités fermées par des demi-sphères
    (rayon de l'extrémité) — un rayon ~0 donne une pointe arrondie."""
    if isinstance(radii, (int, float)):
        radii = [radii] * len(points)
    P = _catmull([V(p) for p in points], samples)
    R = _catmull(list(radii), samples)
    R = [max(r, 1e-3) for r in R]
    n = len(P)
    T = []
    for i in range(n):
        a = P[max(i - 1, 0)]; b = P[min(i + 1, n - 1)]
        T.append((b - a).normalized())
    # repère transporté parallèlement
    ref = V(up) if up else (V((0, 0, 1)) if abs(T[0].z) < 0.9 else V((1, 0, 0)))
    N = [(ref - T[0] * ref.dot(T[0])).normalized()]
    for i in range(1, n):
        v = N[-1] - T[i] * N[-1].dot(T[i])
        N.append(v.normalized() if v.length > 1e-6 else N[-1])
    sx, sy = flat if flat else (1, 1)
    bm = bmesh.new()
    rings = []

    def add_ring(c, t, nrm, r, k):
        b = t.cross(nrm)
        ang0 = twist * k
        rv = []
        for j in range(ring):
            a = 2 * math.pi * j / ring + ang0
            rv.append(bm.verts.new(c + nrm * (math.cos(a) * r * sx) + b * (math.sin(a) * r * sy)))
        rings.append(rv)

    # capuchon de départ
    if cap_start:
        for k in range(cap_rings, 0, -1):
            ang = (k / cap_rings) * math.pi / 2 * 0.999
            add_ring(P[0] - T[0] * R[0] * math.sin(ang), T[0], N[0], R[0] * math.cos(ang), 0)
    for i in range(n):
        add_ring(P[i], T[i], N[i], R[i], i / max(n - 1, 1))
    if cap_end:
        for k in range(1, cap_rings + 1):
            ang = (k / cap_rings) * math.pi / 2 * 0.999
            add_ring(P[-1] + T[-1] * R[-1] * math.sin(ang), T[-1], N[-1], R[-1] * math.cos(ang), 1)
    for a, b in zip(rings[:-1], rings[1:]):
        for j in range(ring):
            bm.faces.new((a[j], a[(j + 1) % ring], b[(j + 1) % ring], b[j]))
    # fermeture des bouts (éventail)
    if cap_start:
        c = bm.verts.new(P[0] - T[0] * R[0])
        for j in range(ring):
            bm.faces.new((c, rings[0][(j + 1) % ring], rings[0][j]))
    else:
        bm.faces.new(list(reversed(rings[0])))
    if cap_end:
        c = bm.verts.new(P[-1] + T[-1] * R[-1])
        for j in range(ring):
            bm.faces.new((rings[-1][j], rings[-1][(j + 1) % ring], c))
    else:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _link(bm, name)
    shade(o)
    return o


def lathe(profile, segments=48, loc=(0, 0, 0), rot=(0, 0, 0), name="Lathe", close_bottom=True, close_top=True):
    """Pièce de révolution autour de Z. profile = [(rayon, z), ...] de bas en haut."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-4:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * j / segments),
                                        r * math.sin(2 * math.pi * j / segments), z)) for j in range(segments)])
    for a, b in zip(rings[:-1], rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for j in range(segments):
                bm.faces.new((a[0], b[j], b[(j + 1) % segments]))
        elif len(b) == 1:
            for j in range(segments):
                bm.faces.new((a[j], b[0], a[(j + 1) % segments]))
        else:
            for j in range(segments):
                bm.faces.new((a[j], a[(j + 1) % segments], b[(j + 1) % segments], b[j]))
    if close_bottom and len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if close_top and len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _link(bm, name)
    xf(o, loc, rot)
    shade(o)
    return o


def torus(R, r, loc=(0, 0, 0), rot=(0, 0, 0), major=48, minor=12, name="Torus"):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=major,
                                     minor_segments=minor, location=loc, rotation=rot)
    o = active()
    o.name = name
    freeze(o)
    shade(o)
    return o


# ---------------------------------------------------------------------------------------------
# Sculpture par code
# ---------------------------------------------------------------------------------------------
def deform(o, fn):
    """fn(Vector) -> Vector appliqué à chaque sommet."""
    for v in o.data.vertices:
        v.co = fn(v.co.copy())
    o.data.update()
    return o


def displace(o, fn):
    """fn(co, normal) -> distance le long de la normale."""
    o.data.update()
    cos = [(v.co.copy(), v.normal.copy()) for v in o.data.vertices]
    for v, (c, nrm) in zip(o.data.vertices, cos):
        v.co = c + nrm * fn(c, nrm)
    o.data.update()
    return o


def subsurf(o, levels=1):
    m = o.modifiers.new("Sub", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    m.quality = 3
    apply_modifiers(o)
    shade(o)
    return o


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def fbm(p, octaves=3, seed=0):
    return noise.fractal(V(p) + V((seed * 17.3, seed * 5.1, seed * 9.7)), 0.5, 2.0, octaves, noise_basis="PERLIN_ORIGINAL")


# ---------------------------------------------------------------------------------------------
# Plaquage sur surface
# ---------------------------------------------------------------------------------------------
def bvh(o):
    o.data.update()
    bm = bmesh.new(); bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def bvh_multi(objs):
    bm = bmesh.new()
    for o in objs:
        tmp = bmesh.new(); tmp.from_mesh(o.data); tmp.transform(o.matrix_world)
        me = bpy.data.meshes.new("tmp"); tmp.to_mesh(me); tmp.free()
        bm.from_mesh(me); bpy.data.meshes.remove(me)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def align_matrix(loc, nrm, spin=0.0):
    """Matrice qui oriente l'axe -Y local sur la normale `nrm` (face avant d'un objet vers l'extérieur)."""
    q = V((0, -1, 0)).rotation_difference(V(nrm).normalized())
    return Matrix.Translation(V(loc)) @ q.to_matrix().to_4x4() @ Matrix.Rotation(spin, 4, "Y")


def raycast(target_or_tree, origin, direction, dist=1e4):
    tree = target_or_tree if isinstance(target_or_tree, BVHTree) else bvh(target_or_tree)
    loc, nrm, idx, d = tree.ray_cast(V(origin), V(direction).normalized(), dist)
    return loc, nrm


def surface_point(target_or_tree, x, z, y_from=-1e3, direction=(0, 1, 0)):
    """Point de la surface vu de face (depuis -Y) à la position (x, z)."""
    loc, nrm = raycast(target_or_tree, (x, y_from, z), direction)
    return loc, nrm


def patch(points2d, target, origin, u, v, direction, lift=0.02, thickness=0.1, cuts=3, name="Patch",
          sharp_rim=True):
    """Forme 2D (liste de (x, y) dans le repère origin+u*x+v*y) projetée selon `direction` sur `target`,
    décollée de `lift`, épaissie de `thickness` vers l'extérieur (ex. bouche, logo)."""
    origin, u, v, d = V(origin), V(u), V(v), V(direction).normalized()
    bm = bmesh.new()
    vs = [bm.verts.new(origin + u * x + v * y) for x, y in points2d]
    edges = [bm.edges.new((vs[i], vs[(i + 1) % len(vs)])) for i in range(len(vs))]
    bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=edges)
    if cuts:
        bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=cuts, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
    tree = target if isinstance(target, BVHTree) else bvh(target)
    missing = []
    for vert in bm.verts:
        loc, nrm = raycast(tree, vert.co - d * 50, d)
        if loc is None:
            missing.append(vert)
            continue
        vert.co = loc - d * lift
    # épaississement vers l'observateur (sens -direction)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.dot(d) > 0:
            f.normal_flip()
    ret = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    newv = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    for vert in newv:
        vert.co -= d * thickness
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _link(bm, name)
    shade(o, flat_angle=40 if sharp_rim else None)
    return o


def text_mesh(body, size=1.0, extrude=0.1, bevel=0.02, loc=(0, 0, 0), rot=(math.pi / 2, 0, 0), align="CENTER",
              name="Text", resolution=4):
    """Texte en relief. Par défaut : lisible de face (depuis -Y), relief vers -Y, centré sur loc."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = 2
    cu.resolution_u = resolution
    cu.align_x = align
    cu.align_y = "CENTER"
    o = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(o)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    o = active()
    freeze(o)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(o.data); bm.free()
    xf(o, loc, rot)
    shade(o, flat_angle=40)
    return o


# ---------------------------------------------------------------------------------------------
# Yeux « cartoon »
# ---------------------------------------------------------------------------------------------
def cartoon_eye(center, r, look=(0.0, 0.0), squash=(1.0, 0.55, 1.2), pupil=0.55, level=3, lid=None,
                highlight=True):
    """Œil de face (vers -Y) : blanc (ellipsoïde), pupille noire posée sur la surface, reflet.
    look = (dx, dz) décalage du regard (-1..1). lid = (angle_deg, hauteur 0..1) paupière (renvoyée à part).
    Renvoie dict(white=[...], pupil=[...], shine=[...], lid=[...])."""
    c = V(center)
    white = qsphere(r, c, squash, level=level, name="EyeWhite")
    tree = bvh(white)
    lx, lz = look
    target = c + V((lx * r * squash[0] * 0.55, 0, lz * r * squash[2] * 0.5))
    loc, nrm = raycast(tree, target - V((0, 10 * r, 0)), (0, 1, 0))
    pr = r * pupil
    pup = qsphere(1, (0, 0, 0), (pr * squash[0] * 0.95, pr * 0.3, pr * squash[2] * 0.95), level=level, name="Pupil")
    # oriente la pupille selon la normale de surface
    q = V((0, -1, 0)).rotation_difference(-nrm if nrm.y > 0 else nrm)
    xf_matrix(pup, Matrix.Translation(loc + nrm * (-pr * 0.12 if nrm.y > 0 else pr * 0.05)) @ q.to_matrix().to_4x4())
    out = dict(white=[white], pupil=[pup], shine=[], lid=[])
    if highlight:
        hl = qsphere(pr * 0.3, (0, 0, 0), (1, 0.5, 1), level=2, name="Shine")
        tp = bvh(pup)
        hloc, hn = raycast(tp, loc + V((-pr * 0.35, -5 * r, pr * 0.4)), (0, 1, 0))
        if hloc is None:
            hloc = loc + V((-pr * 0.35, -pr * 0.2, pr * 0.4))
        xf(hl, hloc + V((0, -pr * 0.02, 0)))
        hl2 = qsphere(pr * 0.13, hloc + V((pr * 0.55, -pr * 0.0, -pr * 0.55)), (1, 0.5, 1), level=2, name="Shine2")
        out["shine"] += [hl, hl2]
    if lid:
        ang, h = lid
        # paupière : coque un peu plus grande que le blanc, coupée par un plan incliné
        lidm = qsphere(r * 1.08, c, squash, level=level, name="Lid")
        bm = bmesh.new(); bm.from_mesh(lidm.data)
        a = math.radians(ang)
        pn = V((math.sin(a), 0, math.cos(a)))  # normale du plan (garde le dessus) ; a>0 : plus bas côté +X
        pc = c + V((0, 0, r * squash[2] * (1 - 2 * h)))
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=pc, plane_no=pn, clear_outer=False, clear_inner=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.edgeloop_fill(bm, edges=edges)
        bm.to_mesh(lidm.data); bm.free()
        shade(lidm, flat_angle=60)
        out["lid"].append(lidm)
    return out


# ---------------------------------------------------------------------------------------------
# Kit : regroupement en pièces Roblox
# ---------------------------------------------------------------------------------------------
class Kit:
    """Rassemble les morceaux par pièce Roblox puis les joint et les nomme selon la convention.
        kit.add("Body", "SmoothPlastic", "6B46C1", obj1, obj2)
        kit.build()   # avant finish()
    Pièce __Spin : kit.add(..., spin=True, pivot=(x, y, z)) -> origine placée sur le pivot."""

    def __init__(self):
        self.parts = {}

    def add(self, name, mat, color, *objs, spin=False, pivot=None):
        flat = []
        for o in objs:
            if isinstance(o, (list, tuple)):
                flat += list(o)
            else:
                flat.append(o)
        key = name
        if key not in self.parts:
            self.parts[key] = dict(mat=mat, color=color.upper(), spin=spin, pivot=pivot, objs=[])
        p = self.parts[key]
        assert p["mat"] == mat and p["color"] == color.upper(), f"{name}: matériau/couleur incohérents"
        p["objs"] += flat
        return flat

    def objects(self):
        return [o for p in self.parts.values() for o in p["objs"]]

    def fit_height(self, h):
        """Met le modèle à l'échelle (autour de l'origine) pour qu'il fasse `h` studs de haut."""
        objs = self.objects()
        zs = [v.co.z for o in objs for v in o.data.vertices]
        k = h / (max(zs) - min(zs))
        for o in objs:
            xf_matrix(o, Matrix.Scale(k, 4))
        for p in self.parts.values():
            if p["pivot"] is not None:
                p["pivot"] = V(p["pivot"]) * k
        return k

    def build(self):
        made = []
        for name, p in self.parts.items():
            objs = p["objs"]
            if not objs:
                continue
            o = join(objs) if len(objs) > 1 else objs[0]
            freeze(o)
            bm = bmesh.new(); bm.from_mesh(o.data)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            bm.to_mesh(o.data); bm.free()
            if p["spin"] and p["pivot"] is not None:
                pv = V(p["pivot"])
                o.data.transform(Matrix.Translation(-pv))
                o.location = pv
            tag(o, name, p["mat"], p["color"], spin=p["spin"])
            o.data.name = o.name  # nom du maillage = nom de la pièce (lisible à l'import)
            if p["mat"] == "Neon":
                # aperçu seulement : émission plus douce pour garder la teinte (le Neon Roblox reste saturé)
                b = o.data.materials[0].node_tree.nodes["Principled BSDF"]
                b.inputs["Emission Strength"].default_value = NEON_PREVIEW
            made.append(o)
            print(f"   - {o.name}: {tris(o)} tris")
        assert len(made) <= 12, f"{len(made)} pièces (> 12)"
        return made


def ground_check(objs=None, tol=0.02):
    """Vérifie que le modèle repose sur z=0 (renvoie zmin)."""
    zmin = 1e9
    for o in (objs or [o for o in bpy.data.objects if o.type == "MESH"]):
        for v in o.data.vertices:
            zmin = min(zmin, (o.matrix_world @ v.co).z)
    return zmin


def drop_to_ground(objs=None):
    """Translate tous les maillages pour que le point le plus bas soit en z = 0."""
    objs = objs or [o for o in bpy.data.objects if o.type == "MESH"]
    z = ground_check(objs)
    for o in objs:
        xf(o, (0, 0, -z))
    return z


# ---------------------------------------------------------------------------------------------
# Découpes
# ---------------------------------------------------------------------------------------------
def _fill_boundaries(bm, flat=True, zs=None):
    """Referme les bords ouverts (seulement ceux posés sur les plans z de `zs` si fourni)."""
    bnd = [e for e in bm.edges if e.is_boundary]
    if zs is not None:
        bnd = [e for e in bnd if any(abs(e.verts[0].co.z - z) < 1e-4 and abs(e.verts[1].co.z - z) < 1e-4
                                     for z in zs)]
    if not bnd:
        return []
    res = bmesh.ops.holes_fill(bm, edges=bnd, sides=0)
    for f in res["faces"]:
        f.smooth = False
        for e in f.edges:
            e.smooth = False
    return res["faces"]


def slice_shift(o, z0, z1, offset):
    """Effet « glitch » : tranche horizontale [z0, z1] de l'objet décalée de `offset` (vecteur),
    tranches refermées par des faces planes. Renvoie True si l'objet a été touché."""
    zs = [v.co.z for v in o.data.vertices]
    if not zs or max(zs) < z0 or min(zs) > z1:
        return False
    bm = bmesh.new(); bm.from_mesh(o.data)
    for zc in (z0, z1):
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, zc), plane_no=(0, 0, 1))
        cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if cut:
            bmesh.ops.split_edges(bm, edges=cut)
    band = [f for f in bm.faces if z0 < f.calc_center_median().z < z1]
    verts = {v for f in band for v in f.verts}
    for v in verts:
        v.co += V(offset)
    _fill_boundaries(bm, zs=(z0, z1))
    bm.to_mesh(o.data); bm.free(); o.data.update()
    return True


def slab(o, z0, z1):
    """Copie fermée de la tranche [z0, z1] d'un objet."""
    n = copy(o)
    bm = bmesh.new(); bm.from_mesh(n.data)
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z0), plane_no=(0, 0, 1), clear_inner=True)
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z1), plane_no=(0, 0, 1), clear_outer=True)
    _fill_boundaries(bm)
    bm.to_mesh(n.data); bm.free(); n.data.update()
    return n


def cut_below(o, z):
    """Supprime tout ce qui est sous z et referme (plan). Renvoie None si l'objet disparaît."""
    bm = bmesh.new(); bm.from_mesh(o.data)
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_inner=True)
    _fill_boundaries(bm)
    empty = len(bm.faces) == 0
    bm.to_mesh(o.data); bm.free(); o.data.update()
    if empty:
        delete(o)
        return None
    return o


def cam(default):
    """Direction de caméra de l'aperçu ; surchargeable par la variable d'environnement CAM="x,y,z"."""
    c = os.environ.get("CAM")
    return tuple(float(x) for x in c.split(",")) if c else default


def finish_char(name, camera=(1.6, -2.0, 1.3), samples=48, zoom=1.0):
    """common.finish (export + aperçu) ; zoom > 1 recule la caméra puis refait l'aperçu
    (le cadrage de common.finish coupe les modèles très hauts et étroits)."""
    total = finish(name, preview=True, camera=camera, samples=samples)
    if zoom != 1.0:
        sc = bpy.context.scene
        camo = sc.camera
        tgt = bpy.data.objects["Target"].location
        camo.location = tgt + (camo.location - tgt) * zoom
        bpy.ops.render.render(write_still=True)
    return total
