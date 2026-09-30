"""
room_common.py — outils de modélisation des décors de la CHAMBRE D'ANGA (lobby : bureau du streamer).

S'appuie sur common.py (conventions, tag, finish) sans le modifier, et ajoute :
- maillages paramétriques : lathe (révolution d'un profil), extrude (profil 2D), sweep (tube le long
  d'une polyligne, avec torsion « tressée » optionnelle), helix (ressorts), text_mesh (légendes)
- transformations / booléens / subdivision / enroulement sur un cylindre
- tagj : fusion d'objets de même matériau+couleur en une seule MeshPart
- render : rendu « photo produit » (sol sombre, 3 lumières, cadrage serré) après finish(preview=False)
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *  # noqa: F401,F403
import bpy, bmesh
from mathutils import Vector, Matrix, Euler

TAU = 2 * math.pi
FONTS = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
         "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]


# ---------------------------------------------------------------- sélection / ombrage
def select_only(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    return o


def shade(o, angle=40):
    """Lissage par angle (sans toucher aux autres objets sélectionnés, contrairement à smooth())."""
    select_only(o)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    return o


def shade_flat(o):
    select_only(o)
    bpy.ops.object.shade_flat()
    return o


def mesh(name, verts, faces, angle=40, recalc=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate()
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    if recalc:
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
    if angle is not None:
        shade(o, angle)
    return o


def mod_apply(o):
    select_only(o)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o


# ---------------------------------------------------------------- transformations
def xf(o, loc=None, rot=None, scale=None):
    """Transforme ET applique (le maillage garde l'origine du monde)."""
    select_only(o)
    if scale is not None:
        o.scale = scale if hasattr(scale, "__len__") else (scale,) * 3
    if rot is not None:
        o.rotation_euler = rot
    if loc is not None:
        o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def rotz(o, a):
    return xf(o, rot=(0, 0, a))


def dup(o):
    select_only(o)
    bpy.ops.object.duplicate()
    return active()


def mirror_x(o, merge=True):
    """Duplique en miroir X et fusionne (pièces symétriques)."""
    d = dup(o)
    xf(d, scale=(-1, 1, 1))
    bm = bmesh.new(); bm.from_mesh(d.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(d.data); bm.free()
    return join([o, d]) if merge else d


def subsurf(o, levels=1):
    m = o.modifiers.new("Sub", "SUBSURF")
    m.levels = levels; m.render_levels = levels
    return mod_apply(o)


def solidify(o, thickness, offset=-1.0):
    m = o.modifiers.new("Solid", "SOLIDIFY")
    m.thickness = thickness; m.offset = offset
    m.use_even_offset = True
    return mod_apply(o)


def bevel_all(o, width, segments=3, angle=30, clamp=True):
    m = bevel(o, width, segments, angle)
    m.use_clamp_overlap = clamp
    m.harden_normals = False
    return mod_apply(o)


def boolean_diff(o, cutters, op="DIFFERENCE", solver="EXACT"):
    """Booléen avec plusieurs découpes réunies d'abord (plus rapide et plus robuste)."""
    if not isinstance(cutters, (list, tuple)):
        cutters = [cutters]
    c = join(list(cutters)) if len(cutters) > 1 else cutters[0]
    m = o.modifiers.new("Bool", "BOOLEAN")
    m.object = c; m.operation = op; m.solver = solver
    mod_apply(o)
    bpy.data.objects.remove(c)
    return o


def wireframe(o, thickness, offset=0.0):
    m = o.modifiers.new("Wire", "WIREFRAME")
    m.thickness = thickness; m.offset = offset
    m.use_even_offset = True
    m.use_replace = True
    return mod_apply(o)


def decimate(o, ratio):
    m = o.modifiers.new("Dec", "DECIMATE")
    m.ratio = ratio
    return mod_apply(o)


def tagj(objs, name, mat, col, spin=False, angle=None):
    """Fusionne des objets en UNE MeshPart nommée selon la convention."""
    objs = [o for o in (objs if isinstance(objs, (list, tuple)) else [objs]) if o is not None]
    o = join(objs) if len(objs) > 1 else objs[0]
    for p in o.data.polygons:
        p.material_index = 0
    if angle is not None:
        shade(o, angle)
    tag(o, name, mat, col, spin)
    o.data.name = o.name  # nom du maillage = nom de la pièce (lisible dans le .glb)
    return o


def set_origin(o, point):
    bpy.context.scene.cursor.location = point
    select_only(o)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)
    return o


# ---------------------------------------------------------------- courbes 2D
def arc(cx, cy, r, a0, a1, n):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def qbez(p0, p1, p2, n):
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * c for a, b, c in zip(p0, p1, p2)))
    return out


def cbez(p0, p1, p2, p3, n):
    out = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        out.append(tuple(u ** 3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t ** 3 * d
                         for a, b, c, d in zip(p0, p1, p2, p3)))
    return out


def chain(*parts):
    """Concatène des listes de points en supprimant les doublons aux jonctions."""
    out = []
    for p in parts:
        for q in p:
            if not out or (Vector(q) - Vector(out[-1])).length > 1e-6:
                out.append(tuple(q))
    return out


def catmull(points, n=8, closed=False):
    """Courbe Catmull-Rom lisse passant par les points de contrôle."""
    P = [Vector(p) for p in points]
    if closed:
        P = [P[-1]] + P + [P[0], P[1]]
    else:
        P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    if not closed:
        out.append(P[-2])
    return [tuple(v) for v in out]


def rounded_rect(w, h, r, n=6):
    """Rectangle arrondi (centré), sens trigonométrique."""
    r = min(r, w / 2 - 1e-4, h / 2 - 1e-4)
    x, y = w / 2 - r, h / 2 - r
    return chain(arc(x, -y, r, -math.pi / 2, 0, n), arc(x, y, r, 0, math.pi / 2, n),
                 arc(-x, y, r, math.pi / 2, math.pi, n), arc(-x, -y, r, math.pi, 1.5 * math.pi, n))


def circle2(r, n=32, cx=0, cy=0):
    return [(cx + r * math.cos(TAU * i / n), cy + r * math.sin(TAU * i / n)) for i in range(n)]


# ---------------------------------------------------------------- maillages paramétriques
def lathe(profile, segments=64, name="Lathe", angle=40, a0=0.0, a1=TAU):
    """Révolution autour de Z d'un profil [(rayon, z), ...]. Rayon 0 = pôle."""
    full = abs(a1 - a0 - TAU) < 1e-6
    nseg = segments if full else segments + 1
    verts, rings = [], []
    for r, z in profile:
        if r < 1e-6:
            verts.append((0, 0, z)); rings.append([len(verts) - 1])
        else:
            ring = []
            for i in range(nseg):
                a = a0 + (a1 - a0) * i / segments
                verts.append((r * math.cos(a), r * math.sin(a), z)); ring.append(len(verts) - 1)
            rings.append(ring)
    faces = []
    for A, B in zip(rings, rings[1:]):
        if len(A) == 1 and len(B) == 1:
            continue
        rng = range(segments)
        if len(A) == 1:
            faces += [(A[0], B[(i + 1) % nseg], B[i]) for i in rng]
        elif len(B) == 1:
            faces += [(A[i], A[(i + 1) % nseg], B[0]) for i in rng]
        else:
            faces += [(A[i], A[(i + 1) % nseg], B[(i + 1) % nseg], B[i]) for i in rng]
    return mesh(name, verts, faces, angle)


def extrude(poly, z0, z1, name="Extr", angle=40, cap_bottom=True, cap_top=True):
    """Prisme : polygone 2D [(x, y)] extrudé de z0 à z1 (n-gones triangulés par l'export)."""
    n = len(poly)
    verts = [(x, y, z0) for x, y in poly] + [(x, y, z1) for x, y in poly]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    if cap_bottom:
        faces.append(tuple(reversed(range(n))))
    if cap_top:
        faces.append(tuple(range(n, 2 * n)))
    o = mesh(name, verts, faces, angle)
    return o


def loft(sections, name="Loft", angle=40, closed=True, cap=True):
    """Relie des sections 3D (listes de même longueur) : coques, dossiers, profils variables."""
    n = len(sections[0])
    verts = [v for s in sections for v in s]
    faces = []
    for j in range(len(sections) - 1):
        a, b = j * n, (j + 1) * n
        for i in range(n if closed else n - 1):
            k = (i + 1) % n
            faces.append((a + i, a + k, b + k, b + i))
    if cap and closed:
        faces.append(tuple(reversed(range(n))))
        faces.append(tuple(range((len(sections) - 1) * n, len(sections) * n)))
    return mesh(name, verts, faces, angle)


def _frames(P, closed):
    T = []
    for i in range(len(P)):
        if closed:
            t = P[(i + 1) % len(P)] - P[i - 1]
        else:
            t = P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]
        T.append(t.normalized())
    ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    N = [T[0].cross(ref).normalized()]
    for i in range(1, len(P)):
        n = N[-1] - T[i] * N[-1].dot(T[i])  # transport parallèle
        N.append(n.normalized() if n.length > 1e-8 else N[-1])
    return T, N


def sweep(points, radius, sides=12, closed=False, caps=True, name="Sweep", angle=60,
          braid=0.0, braid_freq=0.0, radius_fn=None):
    """Tube le long d'une polyligne 3D. braid>0 : relief torsadé (câble tressé / gaine)."""
    P = [Vector(p) for p in points]
    T, N = _frames(P, closed)
    verts = []
    s_acc = 0.0
    for i, p in enumerate(P):
        if i:
            s_acc += (P[i] - P[i - 1]).length
        t, n = T[i], N[i]
        b = t.cross(n)
        r0 = radius_fn(i / (len(P) - 1)) if radius_fn else radius
        for k in range(sides):
            a = TAU * k / sides
            r = r0 * (1 + braid * math.sin(2 * a + s_acc * braid_freq)) if braid else r0
            verts.append(p + (n * math.cos(a) + b * math.sin(a)) * r)
    faces = []
    m = len(P)
    for j in range(m if closed else m - 1):
        a, c = j * sides, ((j + 1) % m) * sides
        for k in range(sides):
            faces.append((a + k, a + (k + 1) % sides, c + (k + 1) % sides, c + k))
    if caps and not closed:
        faces.append(tuple(reversed(range(sides))))
        faces.append(tuple(range((m - 1) * sides, m * sides)))
    return mesh(name, verts, faces, angle)


def helix(radius, wire, turns, z0, z1, sides=8, per_turn=16, name="Spring", ends=True):
    """Ressort hélicoïdal le long de Z (spires fermées aux extrémités si ends)."""
    pts = []
    n = int(turns * per_turn)
    for i in range(n + 1):
        t = i / n
        # spires serrées aux bouts, comme un vrai ressort de traction
        tt = t
        if ends:
            e = 1.0 / turns
            tt = 0 if t < e * 0.5 else (1 if t > 1 - e * 0.5 else (t - e * 0.5) / (1 - e))
        a = TAU * turns * t
        pts.append((radius * math.cos(a), radius * math.sin(a), z0 + (z1 - z0) * tt))
    return sweep(pts, wire, sides, name=name)


def spring_between(p1, p2, radius, wire, turns, sides=8, name="Spring", per_turn=12):
    p1, p2 = Vector(p1), Vector(p2)
    L = (p2 - p1).length
    s = helix(radius, wire, turns, 0, L, sides, per_turn=per_turn, name=name)
    orient(s, p1, p2)
    return s


def orient(o, p1, p2):
    """Place un objet modélisé le long de +Z (de 0 à L) entre p1 et p2."""
    p1, p2 = Vector(p1), Vector(p2)
    d = (p2 - p1).normalized()
    q = d.to_track_quat("Z", "Y")
    select_only(o)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = q
    o.location = p1
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.rotation_mode = "XYZ"
    return o


def cyl_between(p1, p2, r, vertices=24, bevel_w=0.0, name="Rod"):
    L = (Vector(p2) - Vector(p1)).length
    o = cylinder(r, L, (0, 0, L / 2), vertices=vertices, bevel_width=bevel_w)
    xf(o)  # la base du cylindre à l'origine avant orientation
    return orient(o, p1, p2)


def box_between(p1, p2, w, h, r=0.0, seg=3):
    """Barre rectangulaire (largeur w selon X local, hauteur h selon Y local) entre deux points."""
    L = (Vector(p2) - Vector(p1)).length
    o = box((w, h, L), (0, 0, L / 2), bevel_width=r, segments=seg)
    xf(o)
    return orient(o, p1, p2)


def rbox(size, loc=(0, 0, 0), r=0.1, seg=3, rot=None):
    o = box(size, (0, 0, 0), bevel_width=r, segments=seg)
    return xf(o, loc=loc, rot=rot)


def uvsphere(r, loc=(0, 0, 0), seg=32, rings=16, scale=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=(0, 0, 0))
    o = active()
    xf(o, loc=loc, scale=scale)
    return shade(o, 60)


def torus(R, r, loc=(0, 0, 0), rot=(0, 0, 0), maj=64, mnr=12):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=maj, minor_segments=mnr)
    o = active()
    xf(o, loc=loc, rot=rot)
    return shade(o, 60)


def cyl(r, h, loc=(0, 0, 0), rot=(0, 0, 0), verts=32, bev=0.0, seg=3):
    """Cylindre dont la base est à loc (axe Z local avant rotation)."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=(0, 0, h / 2))
    o = active()
    xf(o)  # applique la translation : base en z = 0, origine au monde (rotation autour de la base)
    if bev > 0:
        bevel(o, bev, seg); mod_apply(o)
    xf(o, rot=rot)
    xf(o, loc=loc)
    return shade(o, 40)


# ---------------------------------------------------------------- texte / logos
def text_mesh(body, size, depth, bevel_d=0.0, align=("CENTER", "CENTER"), res=3, name="Text", font=None):
    """Texte extrudé (légendes, logos) → maillage, posé sur le plan XY, de z=0 à z=depth."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    fnt = font
    if fnt is None:
        for f in FONTS:
            if os.path.exists(f):
                fnt = f; break
    if fnt:
        cu.font = bpy.data.fonts.load(fnt, check_existing=True)
    cu.size = size
    cu.extrude = depth / 2
    cu.bevel_depth = bevel_d
    cu.bevel_resolution = 1 if bevel_d else 0
    cu.align_x, cu.align_y = align
    cu.resolution_u = res
    o = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(o)
    select_only(o)
    bpy.ops.object.convert(target="MESH")
    o = active()
    xf(o, loc=(0, 0, depth / 2))
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=size * 1e-4)
    bm.to_mesh(o.data); bm.free()
    return shade(o, 30)


def slice_x(o, step, lo, hi, axis=0):
    """Coupe un maillage par des plans réguliers (avant un enroulement / une déformation)."""
    bm = bmesh.new(); bm.from_mesh(o.data)
    x = lo
    no = [0, 0, 0]; no[axis] = 1
    while x <= hi:
        co = [0, 0, 0]; co[axis] = x
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
        x += step
    bm.to_mesh(o.data); bm.free()
    return o


def wrap_cylinder(o, R):
    """Enroule un objet modélisé à plat (x = abscisse, y = épaisseur vers l'extérieur, z = hauteur)
    sur un cylindre vertical de rayon R, face vers -Y (angle -90°)."""
    for v in o.data.vertices:
        x, y, z = v.co
        a = -math.pi / 2 + x / R
        rr = R + y
        v.co = (rr * math.cos(a), rr * math.sin(a), z)
    o.data.update()
    return o


# ---------------------------------------------------------------- rendu « produit »
def _mat_floor(hexcol, rough):
    m = bpy.data.materials.new("Floor")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*hex_rgb(hexcol), 1)
    b.inputs["Roughness"].default_value = rough
    return m


def spot(loc, direction, energy, angle=60, color=(1, 0.95, 0.88), size=1.0):
    """Lumière de mise en scène (aperçu seulement), p. ex. dans un abat-jour."""
    bpy.ops.object.light_add(type="SPOT", location=loc)
    li = active()
    li.data.energy = energy
    li.data.spot_size = math.radians(angle)
    li.data.color = color
    li.data.shadow_soft_size = size
    li.rotation_mode = "QUATERNION"
    li.rotation_quaternion = Vector(direction).to_track_quat("-Z", "Y")
    return li


def render(name, direction=(1.0, -1.4, 0.9), lens=50, samples=48, margin=0.06, floor="101218",
           res=(800, 600), target=None, key=1.0, exposure=0.0, neon=1.4, props=None):
    """Rendu de contrôle cadré serré sur le modèle (appelé APRÈS finish(preview=False))."""
    scene = bpy.context.scene
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.visible_get()]
    # aperçu seulement : néon moins « brûlé » pour que la teinte reste lisible (Roblox la sature déjà)
    for m in bpy.data.materials:
        if m.name.startswith("Neon_") and m.use_nodes:
            m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = neon
        if m.name.startswith("ForceField_") and m.use_nodes:  # champ de force : voile lumineux translucide
            b = m.node_tree.nodes["Principled BSDF"]
            b.inputs["Alpha"].default_value = 0.22
            b.inputs["Emission Color"].default_value = b.inputs["Base Color"].default_value
            b.inputs["Emission Strength"].default_value = 1.5
        if m.name.startswith("Glass_") and m.use_nodes:
            b = m.node_tree.nodes["Principled BSDF"]
            b.inputs["Alpha"].default_value = 0.45
            b.inputs["Roughness"].default_value = 0.05
    corners = []
    for o in meshes:
        corners += [o.matrix_world @ Vector(c) for c in o.bound_box]
    mins = Vector([min(c[i] for c in corners) for i in range(3)])
    maxs = Vector([max(c[i] for c in corners) for i in range(3)])
    center = Vector(target) if target else (mins + maxs) / 2
    size = (maxs - mins).length / 2 or 1
    d = Vector(direction).normalized()

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (-d).to_track_quat("-Z", "Y")
    scene.render.resolution_x, scene.render.resolution_y = res
    aspect = res[0] / res[1]
    tan_x = 18 / lens  # capteur 36 mm
    tan_y = tan_x / aspect
    # distance minimale pour que les 8 coins de la boîte englobante tiennent dans l'image
    box8 = [Vector((x, y, z)) for x in (mins.x, maxs.x) for y in (mins.y, maxs.y) for z in (mins.z, maxs.z)]
    rot_inv = cam.rotation_quaternion.to_matrix().inverted()
    lo, hi = size * 0.2, size * 50
    for _ in range(60):
        mid = (lo + hi) / 2
        pos = center + d * mid
        ok = True
        for c in box8:
            v = rot_inv @ (c - pos)
            if -v.z <= 1e-3 or abs(v.x) / -v.z > tan_x * (1 - margin) or abs(v.y) / -v.z > tan_y * (1 - margin):
                ok = False; break
        if ok:
            hi = mid
        else:
            lo = mid
    cam.location = center + d * hi
    cam_data.clip_start = hi * 0.01
    cam_data.clip_end = hi * 200

    # accessoires de mise en scène (non exportés), p. ex. un bout de bureau sous une pince
    if props:
        props()
    # sol (non exporté : ajouté après finish)
    if floor:
        bpy.ops.mesh.primitive_plane_add(size=size * 400, location=(center.x, center.y, mins.z - size * 0.001))
        fl = active()
        fl.data.materials.append(_mat_floor(floor, 0.75))

    tgt = bpy.data.objects.new("Target", None)
    tgt.location = center
    bpy.context.collection.objects.link(tgt)
    right = d.cross(Vector((0, 0, 1))).normalized()
    lights = (  # (direction relative, énergie, taille)
        (d * 0.6 + right * -1.1 + Vector((0, 0, 1.3)), 1000 * key, 1.6),  # clé
        (d * 0.8 + right * 1.3 + Vector((0, 0, 0.4)), 320, 2.2),  # débouché
        (-d * 1.2 + Vector((0, 0, 1.0)), 650, 1.2),  # contre-jour (liserés)
    )
    for rel, energy, sz in lights:
        bpy.ops.object.light_add(type="AREA", location=center + rel.normalized() * size * 3.2)
        li = active()
        li.data.energy = energy * size * size / 4
        li.data.size = size * sz
        tc = li.constraints.new("TRACK_TO"); tc.target = tgt
    world = bpy.data.worlds.new("World"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.022, 0.03, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.device = "CPU"
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = exposure
    os.makedirs(PREVIEWS, exist_ok=True)
    scene.render.filepath = os.path.join(PREVIEWS, f"{name}.png")
    bpy.ops.render.render(write_still=True)


def report(name):
    for o in sorted(bpy.data.objects, key=lambda o: o.name):
        if o.type == "MESH" and "__" in o.name:
            print(f"   {o.name:48s} {triangles(o):6d} tris")


def _turn_all():
    """Les modèles sont construits façade vers −Y (pratique pour modéliser) puis tournés de 180° :
    façade exportée = +Y Blender = −Z Roblox (LookVector), comme une Part/un Model Roblox."""
    R = Matrix.Rotation(math.pi, 4, "Z")
    for o in bpy.data.objects:
        if o.type == "MESH":
            if o.get("keep_rot"):
                o.matrix_world = R @ o.matrix_world   # écran incliné : on garde son repère propre
                continue
            o.data.transform(R)            # rotation du maillage autour de sa propre origine
            o.location = R @ o.location    # puis de l'origine autour de l'axe Z du monde
            o.data.update()


def screen_part(w, h, center, normal, up, thick=0.03, name="Screen", mat="SmoothPlastic", col="0B0C10"):
    """Dalle d'écran (pièce `Screen`) dans SON repère : +Y local = face visible, +Z local = haut.
    Le nœud glTF garde cette rotation → la MeshPart Roblox a sa face Front (−Z Roblox = +Y Blender)
    sur la dalle, même inclinée : une SurfaceGui Face=Front s'y colle exactement."""
    n = Vector(normal).normalized()
    u = Vector(up) - n * Vector(up).dot(n)
    u.normalize()
    x = n.cross(u)
    rot = Matrix((x, n, u)).transposed().to_4x4()
    o = box((w, thick, h), (0, 0, 0))
    o.location = (0, 0, 0)
    xf(o)
    o.matrix_world = Matrix.Translation(Vector(center)) @ rot
    tag(o, name, mat, col)
    o.data.name = o.name
    o["keep_rot"] = 1
    return o


def done(name, direction=(1.0, -1.4, 0.9), turn=True, clip_floor=True, **kw):
    """finish() (conventions, budgets, export .glb) puis rendu produit.
    direction = direction caméra dans le repère de MODÉLISATION (façade −Y)."""
    if turn:
        _turn_all()
        direction = (-direction[0], -direction[1], direction[2])
        if kw.get("target"):
            t = kw["target"]; kw["target"] = (-t[0], -t[1], t[2])
    if clip_floor:
        # tout ce qui passe sous z = 0 (bouts de câbles, patins sphériques) est coupé : la base de la
        # boîte englobante = le sol, car ModelLibrary.Place pose le bas de la boîte sur la surface
        for o in [o for o in bpy.data.objects if o.type == "MESH"]:
            inv = o.matrix_world.inverted()
            bm = bmesh.new(); bm.from_mesh(o.data)
            if min((o.matrix_world @ v.co).z for v in bm.verts) < -1e-4:
                co = inv @ Vector((0, 0, 0))
                no = (inv.to_3x3() @ Vector((0, 0, 1))).normalized()
                bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no,
                                       clear_inner=True)
                bm.to_mesh(o.data); o.data.update()
            bm.free()
    total = finish(name, preview=False)
    report(name)
    path = os.path.join(MODELS, f"{name}.glb")
    print(f"   glb : {os.path.getsize(path) / 1e6:.2f} Mo")
    if os.environ.get("NORENDER") != "1":
        render(name, direction, **kw)
    return total


# ---------------------------------------------------------------- utilitaires supplémentaires
def offset_copy(o, d):
    """Copie décalée le long des normales (d < 0 : vers l'intérieur) — sert à limiter la profondeur
    d'une gravure (rainures de boutons, joints de coque)."""
    c = dup(o)
    bm = bmesh.new(); bm.from_mesh(c.data)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * d
    bm.to_mesh(c.data); bm.free()
    return c


def groove(o, cutters, depth):
    """Rainure de profondeur ~depth : les découpes ne gardent que la partie hors de la coque rétrécie."""
    cutters = list(cutters) if isinstance(cutters, (list, tuple)) else [cutters]
    inner = offset_copy(o, -depth)
    c = join(cutters) if len(cutters) > 1 else cutters[0]
    boolean_diff(c, inner)
    return boolean_diff(o, c)


def cr1(keys, t):
    """Interpolation Catmull-Rom scalaire sur des clés [(t, v), ...] triées."""
    ts = [k[0] for k in keys]; vs = [k[1] for k in keys]
    if t <= ts[0]:
        return vs[0]
    if t >= ts[-1]:
        return vs[-1]
    i = max(j for j in range(len(ts) - 1) if ts[j] <= t)
    u = (t - ts[i]) / (ts[i + 1] - ts[i])
    p0 = vs[i - 1] if i > 0 else 2 * vs[i] - vs[i + 1]
    p1, p2 = vs[i], vs[i + 1]
    p3 = vs[i + 2] if i + 2 < len(vs) else 2 * vs[i + 1] - vs[i]
    return 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3)


def remesh(o, voxel, smooth_iter=0, smooth_factor=0.5):
    """Remaillage voxel (fusionne des volumes grossiers en une forme molle, type rembourrage)."""
    m = o.modifiers.new("Remesh", "REMESH")
    m.mode = "VOXEL"; m.voxel_size = voxel; m.use_smooth_shade = True
    mod_apply(o)
    if smooth_iter:
        s = o.modifiers.new("Smooth", "LAPLACIANSMOOTH")
        s.iterations = smooth_iter; s.lambda_factor = smooth_factor; s.use_volume_preserve = True
        mod_apply(o)
    return o


def split_faces(o, pred, name="Split"):
    """Sépare dans un nouvel objet les faces dont pred(centre, normale) est vrai."""
    c = dup(o)
    for obj, keep in ((o, False), (c, True)):
        bm = bmesh.new(); bm.from_mesh(obj.data)
        dele = [f for f in bm.faces if bool(pred(f.calc_center_median(), f.normal)) != keep]
        bmesh.ops.delete(bm, geom=dele, context="FACES")
        bm.to_mesh(obj.data); bm.free()
        obj.data.update()
    c.name = name
    return c


def bisect(o, co, no):
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    bm.to_mesh(o.data); bm.free()
    return o


class Surface:
    """Projection de points sur un maillage (lancer de rayons) pour poser coutures / passepoils."""

    def __init__(self, objs):
        from mathutils.bvhtree import BVHTree
        bm = bmesh.new()
        for o in (objs if isinstance(objs, (list, tuple)) else [objs]):
            tmp = bmesh.new(); tmp.from_mesh(o.data); tmp.transform(o.matrix_world)
            me = bpy.data.meshes.new("tmp"); tmp.to_mesh(me); tmp.free()
            bm.from_mesh(me); bpy.data.meshes.remove(me)
        self.bvh = BVHTree.FromBMesh(bm)
        bm.free()

    def hit(self, origin, direction):
        loc, nor, _, _ = self.bvh.ray_cast(Vector(origin), Vector(direction).normalized())
        return loc, nor

    def path(self, pts, direction, offset=0.0):
        out = []
        for p in pts:
            loc, nor = self.hit(p, direction)
            if loc is not None:
                out.append(loc + nor * offset)
        return out


def knurl_knob(p, axis=(1, 0, 0), r=3.2, h=2.6, teeth=12):
    """Molette moletée (dents) posée en p, épaisseur h le long de axis."""
    star = [((r if i % 2 else r * 0.88) * math.cos(TAU * i / (2 * teeth)),
             (r if i % 2 else r * 0.88) * math.sin(TAU * i / (2 * teeth))) for i in range(2 * teeth)]
    k = extrude(star, 0, h, "Knob", angle=30)
    bevel_all(k, min(0.3, h * 0.12), 2, angle=50)
    cap = cyl(r * 0.55, h + 0.4, (0, 0, 0), verts=24, bev=0.2)
    k = join([k, cap])
    return orient(k, Vector(p), Vector(p) + Vector(axis))


def grid_surface(fn, nu, nv, closed_u=False, name="Surf", angle=60, cap_ends=False):
    """Surface paramétrique fn(u, v) → (x, y, z), u,v ∈ [0,1] ; cap_ends ferme les deux bouts (u fermé)."""
    cols = nu if closed_u else nu + 1
    verts = [tuple(fn(i / nu, j / nv)) for j in range(nv + 1) for i in range(cols)]
    faces = []
    for j in range(nv):
        for i in range(nu):
            a = j * cols + i
            b = j * cols + (i + 1) % cols if closed_u else a + 1
            faces.append((a, b, b + cols, a + cols))
    if cap_ends and closed_u:
        c0 = len(verts); verts.append(tuple(sum((Vector(verts[i]) for i in range(cols)), Vector()) / cols))
        faces += [(c0, (i + 1) % cols, i) for i in range(cols)]
        base = nv * cols
        c1 = len(verts); verts.append(tuple(sum((Vector(verts[base + i]) for i in range(cols)), Vector()) / cols))
        faces += [(c1, base + i, base + (i + 1) % cols) for i in range(cols)]
    return mesh(name, verts, faces, angle)
