"""
hw_common.py — outils de modélisation « matériel PC » (s'appuie sur common.py, sans le modifier).

    from hw_common import *
    reset()
    ... helpers ci-dessous ...
    done("NomDuModele", camera=(x, y, z))   # UV + contrôles + finish() de common.py

Ajouts par rapport à common.py :
- lathe()            : solide de révolution (bouchons, moyeux, condensateurs, réservoir…)
- rprism()           : prisme à coins arrondis (plaques, cadres, capots) à partir d'un contour 2D
- instances()        : duplique un maillage selon une liste de matrices en UN seul objet (ailettes, broches…)
- bool_op()          : booléen EXACT avec plusieurs outils joints d'un coup
- text_mesh()        : texte extrudé (logos, étiquettes en relief ou gravées)
- fan_rotor() / fan_frame() : kit de ventilateur réaliste (pales vrillées en faucille, stator, bague)
- crect/loft/ribbon/prism_x/prism_y/mirror/side_text/screw/pipe : formes de base « matériel »
- done()             : pose sur z = 0, projection UV cubique (les matériaux Roblox des MeshParts utilisent
                       les UV), rapport des triangles par pièce, vérif. des pièces __Spin, puis finish().
- hero() / qa_view() : rendus supplémentaires (cadrage libre, « haut » d'image choisi).
- reset()            : remplace common.reset() (vide aussi le cache de matériaux de common, voir plus bas).
- L'aperçu de finish() est rendu en « studio » (reflets gris doux, ombre au sol) via _studio_preview,
  substitué à common.render_preview sans modifier common.py.
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *  # noqa: F401,F403
from common import MODELS, PREVIEWS
import common as _common
import bpy, bmesh
from mathutils import Vector, Matrix, Euler

def reset():
    """common.reset() + vidage du cache de matériaux de common (sinon, après un reset, tag() réutilise des
    matériaux supprimés → ReferenceError quand un script génère plusieurs modèles)."""
    _common.reset()
    _common._mats.clear()


_FONTS = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
          "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
          "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"]
FONT_BOLD = next((f for f in _FONTS if os.path.exists(f)), None)

# Palette AngAInOne
GRAPHITE_0, GRAPHITE_1, GRAPHITE_2 = "16181E", "22252E", "2A2D38"
ALU_DARK, ALU = "9AA0AC", "B8BEC8"
PCB, PCB_TEAL = "1B1F24", "1F3A33"
GOLD, COPPER, NICKEL = "D4A64A", "C87533", "C9CDD4"
ACCENT = "8B7CFF"


# ----------------------------------------------------------------------------- bases

def deselect():
    for o in bpy.context.selected_objects:
        o.select_set(False)


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def obj_from_bm(bm, name="Obj", smooth_angle=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    if smooth_angle is not None:
        shade(o, smooth_angle)
    return o


def shade(o, angle=35):
    """Ombrage lisse + arêtes vives au-delà de `angle` (uniquement sur `o`)."""
    deselect()
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    o.select_set(False)
    return o


def xf(o, loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
    """Applique une transformation directement au maillage (origine laissée au monde 0)."""
    M = Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4()
    if scale is not None:
        s = scale if hasattr(scale, "__len__") else (scale, scale, scale)
        M = M @ Matrix.Diagonal((*s, 1))
    bake(o)
    o.data.transform(M)
    o.data.update()
    return o


def bake(o):
    """Grave la transformation objet dans le maillage (origine = monde 0)."""
    bpy.context.view_layer.update()
    if o.matrix_world != Matrix.Identity(4):
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    return o


def copy(o, loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
    n = o.copy()
    n.data = o.data.copy()
    link(n)
    return xf(n, loc, rot, scale)


def merge(objs, name=None):
    objs = [o for o in objs if o is not None]
    for o in objs:
        bake(o)
    if len(objs) == 1:
        return objs[0]
    o = join(objs)
    if name:
        o.name = name
    return o


def mod_apply(o, kind, **kw):
    m = o.modifiers.new(kind.title(), kind)
    for k, v in kw.items():
        setattr(m, k, v)
    apply_modifiers(o)
    return o


def bev(o, width, seg=2, angle=30, clamp=True, harden=False, only_verts=False):
    """Chanfrein (modificateur appliqué) limité par angle."""
    m = o.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = seg
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.use_clamp_overlap = clamp
    m.harden_normals = harden
    if only_verts:
        m.affect = "VERTICES"
    apply_modifiers(o)
    return o


def solidify(o, t, offset=0.0):
    return mod_apply(o, "SOLIDIFY", thickness=t, offset=offset, use_even_offset=True)


def bool_op(obj, cutters, op="DIFFERENCE", self_intersect=True, hole_tolerant=False, angle=35):
    """Booléen EXACT ; `cutters` peut être une liste (jointe en un seul outil).
    Les arêtes vives sont recalculées après coup (le booléen perd l'attribut sharp_edge)."""
    if not isinstance(cutters, (list, tuple)):
        cutters = [cutters]
    cutters = [c for c in cutters if c is not None]
    if not cutters:
        return obj
    tool = merge(cutters)
    bake(obj)
    m = obj.modifiers.new("Bool", "BOOLEAN")
    m.object = tool
    m.operation = op
    m.solver = "EXACT"
    m.use_self = self_intersect
    m.use_hole_tolerant = hole_tolerant
    apply_modifiers(obj)
    bpy.data.objects.remove(tool)
    shade(obj, angle)
    return obj


def weld(o, dist=1e-4):
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(o.data); bm.free()
    return o


def ngon_fix(o):
    """Triangule les n-gones (>4 côtés) : évite les artefacts d'ombrage après booléens."""
    bm = bmesh.new(); bm.from_mesh(o.data)
    ng = [f for f in bm.faces if len(f.verts) > 4]
    if ng:
        bmesh.ops.triangulate(bm, faces=ng, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(o.data); bm.free()
    return o


def set_origin(o, point):
    deselect()
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.context.scene.cursor.location = Vector(point)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)
    o.select_set(False)
    return o


# ----------------------------------------------------------------------------- primitives

def rbox(size, loc=(0, 0, 0), r=0.0, seg=3, angle=35, rot=(0, 0, 0)):
    """Boîte à arêtes chanfreinées (arrondies si seg ≥ 3)."""
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = active()
    o.data.transform(Matrix.Diagonal((*size, 1)))   # échelle gravée dans le maillage (biseau en studs)
    o.data.update()
    if r > 0:
        bev(o, r, seg, angle)
    shade(o, angle)
    return xf(o, loc, rot)


def rcyl(r, depth, loc=(0, 0, 0), verts=48, bevel_w=0.0, seg=2, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth)
    o = active()
    bake(o)
    if bevel_w > 0:
        bev(o, bevel_w, seg, 35)
    shade(o, 35)
    return xf(o, loc, rot)


def lathe(profile, segments=48, loc=(0, 0, 0), rot=(0, 0, 0), closed=False, angle=40, arc=None):
    """Solide de révolution autour de Z. profile = [(r, z), …] ; r = 0 → pôle.
    closed=True : profil fermé (anneau/tore quelconque)."""
    bm = bmesh.new()
    full = arc is None
    arc = arc or 2 * math.pi
    nseg = segments if full else segments + 1
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(arc * k / segments), r * math.sin(arc * k / segments), z))
                          for k in range(nseg)])
    pairs = list(zip(rings[:-1], rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for a, b in pairs:
        for k in range(segments):
            k2 = (k + 1) % nseg
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                bm.faces.new((a[0], b[k], b[k2]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[k2], b[0]))
            else:
                bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    o = obj_from_bm(bm, "Lathe")
    shade(o, angle)
    return xf(o, loc, rot)


def round_profile(pts, radius, steps=3):
    """Arrondit les coins d'un contour 2D fermé (liste de (x, y)) : renvoie un contour plus dense."""
    out = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        d0 = (p0 - p1); d2 = (p2 - p1)
        l0, l2 = d0.length, d2.length
        rr = min(radius, l0 * 0.49, l2 * 0.49)
        if rr < 1e-5 or steps == 0:
            out.append(tuple(p1)); continue
        a = p1 + d0.normalized() * rr
        b = p1 + d2.normalized() * rr
        for s in range(steps + 1):
            t = s / steps
            q = (1 - t) ** 2 * a + 2 * (1 - t) * t * p1 + t * t * b  # Bézier quadratique
            out.append(tuple(q))
    return out


def rprism(outline, z0, z1, radius=0.0, steps=3, bevel_w=0.0, seg=2, angle=35, holes=()):
    """Prisme vertical (z0→z1) d'un contour 2D (sens quelconque), coins arrondis optionnels."""
    pts = round_profile(outline, radius, steps) if radius > 0 else list(outline)
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in pts]
    top = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(bot)
    bm.faces.new(top)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(bm, "Prism")
    ngon_fix(o)
    if bevel_w > 0:
        bev(o, bevel_w, seg, angle)
    shade(o, angle)
    return o


def rrect(w, h, r):
    """Contour de rectangle centré (à arrondir avec rprism(radius=r))."""
    return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]


def crect(w, h, c=0.0, center=(0, 0)):
    """Rectangle centré à coins chanfreinés ; c = chanfrein unique ou (BG, BD, HD, HG)."""
    cs = c if hasattr(c, "__len__") else (c, c, c, c)
    x0, y0 = center
    hw, hh = w / 2, h / 2
    pts = []
    for (cx, cy), cc, (dx1, dy1), (dx2, dy2) in (
            ((-hw, -hh), cs[0], (0, 1), (1, 0)), ((hw, -hh), cs[1], (-1, 0), (0, 1)),
            ((hw, hh), cs[2], (0, -1), (-1, 0)), ((-hw, hh), cs[3], (1, 0), (0, -1))):
        if cc > 1e-6:
            pts += [(x0 + cx + dx1 * cc, y0 + cy + dy1 * cc), (x0 + cx + dx2 * cc, y0 + cy + dy2 * cc)]
        else:
            pts.append((x0 + cx, y0 + cy))
    return pts


def loft(sections, cap=True, angle=30):
    """Solide « loft » entre contours 2D de même nombre de points : sections = [(pts, z), …]."""
    bm = bmesh.new()
    rings = [[bm.verts.new((x, y, z)) for x, y in pts] for pts, z in sections]
    n = len(rings[0])
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap:
        bm.faces.new(rings[0])
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(bm, "Loft")
    ngon_fix(o)
    shade(o, angle)
    return o


def ribbon(path, width, z0, z1, closed=False):
    """Bande extrudée verticalement le long d'une polyligne 2D (bras, nervures, traces)."""
    L, R = [], []
    n = len(path)
    for i, p in enumerate(path):
        p = Vector(p)
        q = Vector(path[min(i + 1, n - 1)]) - Vector(path[max(i - 1, 0)])
        nrm = Vector((-q.y, q.x)).normalized() * width / 2
        L.append(tuple(p + nrm)); R.append(tuple(p - nrm))
    return rprism(L + list(reversed(R)), z0, z1)


def prism_x(outline_yz, x0, x1, **kw):
    """Prisme dont le contour est donné dans le plan (y, z), extrudé le long de X de x0 à x1."""
    o = rprism(outline_yz, x0, x1, **kw)
    o.data.transform(Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    o.data.update()
    return o


def prism_y(outline_xz, y0, y1, **kw):
    """Prisme dont le contour est donné dans le plan (x, z), extrudé le long de Y de y0 à y1."""
    o = rprism(outline_xz, -y1, -y0, **kw)
    o.data.transform(Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    o.data.update()
    return o


def mirror(o, axis="Y", keep=True):
    """Copie miroir (normales recalculées) ; keep=False : miroir sur place."""
    n = copy(o) if keep else o
    sc = {"X": (-1, 1, 1), "Y": (1, -1, 1), "Z": (1, 1, -1)}[axis]
    n.data.transform(Matrix.Diagonal((*sc, 1)))
    bm = bmesh.new(); bm.from_mesh(n.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(n.data); bm.free()
    n.data.update()
    return n


def instances(src, mats, name="Inst", remove_src=True):
    """Un seul objet contenant `src` dupliqué pour chaque matrice (monde) de `mats`."""
    bake(src)
    bm = bmesh.new()
    for M in mats:
        n0 = len(bm.verts)
        bm.from_mesh(src.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts[n0:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    for mat in src.data.materials:
        me.materials.append(mat)
    o = link(bpy.data.objects.new(name, me))
    if remove_src:
        bpy.data.objects.remove(src)
    return o


def T(loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
    M = Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4()
    if scale is not None:
        s = scale if hasattr(scale, "__len__") else (scale, scale, scale)
        M = M @ Matrix.Diagonal((*s, 1))
    return M


def text_mesh(text, size, depth, loc=(0, 0, 0), rot=(0, 0, 0), font=FONT_BOLD, align="CENTER", bevel_d=0.0,
              spacing=1.0):
    """Texte extrudé (z de 0 à depth dans son repère), centré sur loc."""
    cu = bpy.data.curves.new("Txt", "FONT")
    cu.body = text
    if font:
        cu.font = bpy.data.fonts.load(font, check_existing=True)
    cu.size = size
    cu.extrude = depth / 2
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.space_character = spacing
    cu.resolution_u = 4
    if bevel_d > 0:
        cu.bevel_depth = bevel_d
        cu.bevel_resolution = 1
    o = link(bpy.data.objects.new("Txt", cu))
    deselect()
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    o = active()
    o.select_set(False)
    weld(o, 1e-5)
    ngon_fix(o)
    xf(o, (0, 0, depth / 2))
    shade(o, 30)
    return xf(o, loc, rot)


def side_text(text, size, depth, x, z, y_face, side=-1, **kw):
    """Texte en relief sur une face verticale : side=-1 → face tournée vers -Y (lisible depuis -Y),
    side=+1 → face tournée vers +Y. y_face = |y| de la surface de départ."""
    rot = (math.pi / 2, 0, 0) if side < 0 else (math.pi / 2, 0, math.pi)
    return text_mesh(text, size, depth, (x, side * y_face, z), rot, **kw)


def screw(r, h, loc=(0, 0, 0), rot=(0, 0, 0), head="pan", slot="cross", verts=20):
    """Vis à tête bombée + empreinte cruciforme (ou hexagonale)."""
    prof = [(0, 0), (r, 0), (r, h * 0.45), (r * 0.9, h * 0.8), (r * 0.6, h), (0, h * 1.02)]
    if head == "flat":
        prof = [(0, 0), (r, 0), (r, h * 0.7), (r * 0.85, h), (0, h)]
    o = lathe(prof, verts)
    if slot == "cross":
        c = [rbox((r * 1.3, r * 0.28, h), (0, 0, h * 0.95)), rbox((r * 0.28, r * 1.3, h), (0, 0, h * 0.95))]
        bool_op(o, c)
    elif slot == "hex":
        bool_op(o, rcyl(r * 0.45, h, (0, 0, h * 1.0), verts=6))
    shade(o, 35)
    return xf(o, loc, rot)


# ----------------------------------------------------------------------------- ventilateurs

def fan_blades(R, hub_r, n, zc, h_root, h_tip, sweep=0.55, c_root=None, c_tip=None, thick=0.08,
               camber=0.18, nu=10, nv=7, tip_round=True, phase=0.0):
    """Pales vrillées en faucille (surface paramétrique épaissie). Axe = Z, centre = (0, 0, zc)."""
    c_root = c_root if c_root is not None else hub_r * 2 * math.pi / n * 0.95
    c_tip = c_tip if c_tip is not None else R * 2 * math.pi / n * 0.75
    r0 = hub_r * 0.92
    bm = bmesh.new()
    for b in range(n):
        base = phase + 2 * math.pi * b / n
        grid = []
        for i in range(nu + 1):
            u = i / nu
            r = r0 + (R - r0) * u
            c = c_root + (c_tip - c_root) * u
            if tip_round and u > 0.7:
                c *= math.sqrt(max(0.0, 1 - ((u - 0.7) / 0.3) ** 2)) * 0.9 + 0.1
            h = h_root + (h_tip - h_root) * u
            tc = base + sweep * u ** 1.4
            row = []
            for j in range(nv + 1):
                v = j / nv - 0.5
                th = tc + v * c / r
                z = zc - v * h + camber * (0.25 - v * v) * h * 1.2
                row.append(bm.verts.new((r * math.cos(th), r * math.sin(th), z)))
            grid.append(row)
        for i in range(nu):
            for j in range(nv):
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    for f in bm.faces:
        f.smooth = True
    o = obj_from_bm(bm, "Blades")
    solidify(o, thick, 0)
    shade(o, 50)
    return o


def fan_rotor(R, hub_r, n, z0, z1, sweep=0.55, ring=True, thick=0.08, camber=0.18, hub_cap=True):
    """Rotor complet (pales + moyeu + bague de bout de pale). Origine sur l'axe, prêt pour __Spin.
    La bague rend la boîte englobante symétrique (pièce Roblox centrée sur l'axe), même avec 7 pales."""
    H = z1 - z0
    zc = z0 + H * 0.5
    parts = [fan_blades(R - (0.04 * R if ring else 0), hub_r, n, zc, H * 0.72, H * 0.42, sweep, thick=thick,
                        camber=camber, tip_round=not ring)]
    hr = hub_r
    hub = lathe([(0, z0 + H * 0.08), (hr * 0.97, z0 + H * 0.08), (hr, z0 + H * 0.14), (hr, z1 - H * 0.16),
                 (hr * 0.97, z1 - H * 0.06), (hr * 0.9, z1 - H * 0.01), (hr * 0.5, z1 + H * 0.02), (0, z1 + H * 0.025)],
                64, angle=30)
    parts.append(hub)
    if hub_cap:  # petit relief concentrique sur le chapeau
        parts.append(lathe([(hr * 0.62, z1 - H * 0.02), (hr * 0.66, z1 + H * 0.03), (hr * 0.7, z1 - H * 0.02)],
                           64, closed=True, angle=60))
    if ring:
        rr = R * 0.96
        parts.append(lathe([(rr, zc - H * 0.2), (rr + R * 0.035, zc - H * 0.22), (rr + R * 0.04, zc + H * 0.18),
                            (rr + R * 0.01, zc + H * 0.2)], 96, closed=True, angle=45))
    o = merge(parts)
    set_origin(o, (0, 0, zc))
    return o


def fan_frame(size, depth, bore, corner_r=None, flange=None, shroud=None, struts=4, motor_r=None, z0=0.0,
              holes=True, waist=True):
    """Cadre de ventilateur carré : flasques avant/arrière, jupe cylindrique visible sur les côtés,
    stator (moteur + bras) côté arrière (z0), trous de fixation. Axe Z, base à z0."""
    corner_r = corner_r or size * 0.07
    flange = flange or depth * 0.17
    shroud = shroud or bore + size * 0.025
    motor_r = motor_r or bore * 0.3
    z1 = z0 + depth
    frame = rprism(rrect(size, size, corner_r), z0, z1, radius=corner_r, steps=5)
    cut = [rcyl(bore, depth * 3, (0, 0, z0 + depth / 2), verts=96)]
    if waist:
        side = rprism(rrect(size * 1.2, size * 1.2, 0), z0 + flange, z1 - flange)
        keep = [rcyl(shroud, depth * 3, (0, 0, z0 + depth / 2), verts=96)]
        post = size * 0.17
        for sx in (-1, 1):
            for sy in (-1, 1):
                keep.append(rbox((post * 2, post * 2, depth * 3), (sx * size / 2, sy * size / 2, z0 + depth / 2)))
        bool_op(side, keep, "DIFFERENCE", self_intersect=True)
        cut.append(side)
    if holes:
        hp = size / 2 - size * 0.075
        for sx in (-1, 1):
            for sy in (-1, 1):
                cut.append(rcyl(size * 0.022, depth * 3, (sx * hp, sy * hp, z0 + depth / 2), verts=20))
    bool_op(frame, cut, self_intersect=True)
    ngon_fix(frame)
    bev(frame, size * 0.006, 2, 40)
    shade(frame, 40)
    parts = [frame]
    # stator arrière : moteur + bras incurvés
    mz = z0 + flange * 0.2
    parts.append(lathe([(0, mz), (motor_r, mz), (motor_r, mz + depth * 0.22), (motor_r * 0.92, mz + depth * 0.26),
                        (0, mz + depth * 0.26)], 64, angle=30))
    for k in range(struts):
        a = math.pi / 4 + 2 * math.pi * k / struts
        pts = []
        for i in range(7):
            t = i / 6
            r = motor_r * 0.9 + (shroud - motor_r * 0.9 + size * 0.01) * t
            th = a + 0.25 * t * t
            pts.append((r * math.cos(th), r * math.sin(th)))
        w = size * 0.022
        # bras = ruban extrudé
        bm = bmesh.new()
        L, Rr = [], []
        for i, (x, y) in enumerate(pts):
            p = Vector((x, y)); q = Vector(pts[min(i + 1, 6)]) - Vector(pts[max(i - 1, 0)])
            nrm = Vector((-q.y, q.x)).normalized() * w / 2
            L.append(p + nrm); Rr.append(p - nrm)
        outline = L + list(reversed(Rr))
        s = rprism(outline, mz, mz + depth * 0.14)
        bev(s, w * 0.2, 1, 40)
        parts.append(s)
    return merge(parts)


def fan_pads(size, depth, bore, z0=0.0, t=None):
    """Patins anti-vibration en caoutchouc aux 4 coins, faces avant et arrière."""
    t = t or depth * 0.07
    hp = size / 2 - size * 0.075
    pads = []
    L = size * 0.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            for zz, s in ((z0 - t * 0.6, 1), (z0 + depth - t * 0.4, 1)):
                cx, cy = sx * (size / 2 - L / 2 + 0.001), sy * (size / 2 - L / 2 + 0.001)
                out = [(-L / 2, -L / 2), (L / 2, -L / 2), (L / 2, L / 2), (-L / 2, L / 2)]
                p = rprism([(x + cx, y + cy) for x, y in out], zz, zz + t, radius=size * 0.06, steps=2)
                bool_op(p, [rcyl(size * 0.022, depth, (sx * hp, sy * hp, zz), verts=20),
                            rcyl(bore + size * 0.012, depth, (0, 0, zz), verts=64)])  # dégage l'ouïe
                bev(p, t * 0.3, 1, 40)
                pads.append(p)
    return merge(pads)


# ----------------------------------------------------------------------------- export

def cube_uv(o, size=8.0):
    """Projection UV cubique (échelle ~`size` studs par tuile) pour les textures de matériaux Roblox."""
    me = o.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            uv[li].uv = (u / size, v / size)


def check_spin(o):
    """Vérifie que la boîte englobante d'une pièce __Spin est centrée sur son axe (Z local)."""
    bb = [Vector(v) for v in o.bound_box]
    cx = (max(v.x for v in bb) + min(v.x for v in bb)) / 2
    cy = (max(v.y for v in bb) + min(v.y for v in bb)) / 2
    ext = max(max(v.x for v in bb) - min(v.x for v in bb), 1e-6)
    off = math.hypot(cx, cy)
    status = "OK" if off < ext * 0.01 else "DÉCENTRÉ"
    print(f"   spin {o.name}: décalage boîte/axe = {off:.3f} studs ({status})")
    return off


def done(name, camera=(1.6, -2.0, 1.3), samples=48, uv_size=8.0, ground=True, neon_strength=2.2):
    """Pose le modèle sur z = 0, projette les UV, affiche le budget puis appelle finish()."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.context.view_layer.update()
    zmin = min((o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices)
    print(f"== {name}  (z min = {zmin:.3f})")
    if ground and abs(zmin) > 1e-4:
        for o in meshes:
            o.location.z -= zmin
        bpy.context.view_layer.update()
    for o in meshes:
        if o.data.users > 1:
            o.data = o.data.copy()
        if not o.name.endswith("__Spin"):
            bake(o)
        cube_uv(o, uv_size)
        print(f"   {o.name:48s} {triangles(o):6d} tris")
        if o.name.endswith("__Spin"):
            check_spin(o)
    for m in bpy.data.materials:  # aperçu : néon moins « brûlé » (la teinte reste lisible)
        if m.name.startswith("Neon_") and m.use_nodes:
            m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = neon_strength
    total = finish(name, preview=True, camera=camera, samples=samples)
    path = os.path.join(MODELS, f"{name}.glb")
    print(f"   glb = {os.path.getsize(path) / 1e6:.2f} Mo, total {total} tris")
    return total


import tempfile
QA_DIR = os.environ.get("HW_QA_DIR", os.path.join(tempfile.gettempdir(), "angainone_hw_qa"))


def qa_view(name, camera, zoom=1.0, target=None, samples=32):
    """Rendu de contrôle supplémentaire (après done()) vers HW_QA_DIR — hors aperçus officiels."""
    scene = bpy.context.scene
    cam = scene.camera
    tgt = bpy.data.objects.get("Target")
    if cam is None or tgt is None:
        return
    if target is not None:
        tgt.location = Vector(target)
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and "__" in o.name]
    pts = [o.matrix_world @ Vector(v) for o in meshes for v in o.bound_box]
    mins = Vector([min(p[i] for p in pts) for i in range(3)])
    maxs = Vector([max(p[i] for p in pts) for i in range(3)])
    radius = (maxs - mins).length / 2
    cam.location = tgt.location + Vector(camera).normalized() * radius * 3.2 / zoom
    floor = bpy.data.objects.get("ShadowCatcher")
    if floor is not None:
        floor.hide_render = cam.location.z < floor.location.z
    scene.cycles.samples = samples
    os.makedirs(QA_DIR, exist_ok=True)
    scene.render.filepath = os.path.join(QA_DIR, f"{name}.png")
    bpy.ops.render.render(write_still=True)


# ----------------------------------------------------------------------------- aperçu « studio »
# common.render_preview rend sur fond quasi noir : les métaux (Metal, Foil) n'ont rien à refléter et
# paraissent noirs alors qu'en jeu ils sont clairs. On garde le même cadrage/format, mais le monde
# vu dans les reflets est un studio gris doux (le fond vu par la caméra reste sombre) et une ombre
# portée au sol. On remplace la fonction dans le module common (sans modifier le fichier).

def _studio_preview(model_name, meshes, camera, samples):
    scene = bpy.context.scene
    mins = Vector((1e9, 1e9, 1e9)); maxs = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for v in o.bound_box:
            w = o.matrix_world @ Vector(v)
            mins = Vector(map(min, mins, w)); maxs = Vector(map(max, maxs, w))
    center = (mins + maxs) / 2
    radius = (maxs - mins).length / 2 or 1
    target = bpy.data.objects.new("Target", None)
    target.location = center
    bpy.context.collection.objects.link(target)
    direction = Vector(camera).normalized()
    bpy.ops.object.camera_add(location=center + direction * radius * 3.2)
    cam = active()
    cam.data.lens = 50
    cam.data.clip_start = radius * 0.01
    cam.data.clip_end = radius * 20
    c = cam.constraints.new("TRACK_TO"); c.target = target
    scene.camera = cam
    for loc, energy, size in (((1, -1, 1.5), 900, 2.0), ((-1.5, 0.5, 1), 350, 2.0), ((0, 1.5, 0.5), 250, 2.0),
                              ((-0.4, -0.2, -1.2), 120, 3.0)):
        bpy.ops.object.light_add(type="AREA", location=center + Vector(loc) * radius * 3)
        light = active(); light.data.energy = energy * radius * radius / 4; light.data.size = radius * size
        t = light.constraints.new("TRACK_TO"); t.target = target
    world = bpy.data.worlds.new("World"); scene.world = world; world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]; bg.inputs[0].default_value = (0.02, 0.022, 0.03, 1)
    studio = nt.nodes.new("ShaderNodeBackground"); studio.inputs[0].default_value = (0.2, 0.21, 0.25, 1)
    grad = nt.nodes.new("ShaderNodeTexGradient")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeMapRange")  # plus clair en haut qu'en bas (softbox)
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    ramp.inputs[1].default_value = -0.2; ramp.inputs[2].default_value = 1.0
    ramp.inputs[3].default_value = 0.3; ramp.inputs[4].default_value = 2.0
    nt.links.new(ramp.outputs[0], studio.inputs[1])
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(studio.outputs[0], mix.inputs[1])
    nt.links.new(bg.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes["World Output"].inputs[0])
    del grad
    # sol attrape-ombre
    bpy.ops.mesh.primitive_plane_add(size=radius * 12, location=(center.x, center.y, mins.z - 0.001))
    floor = active(); floor.name = "ShadowCatcher"; floor.is_shadow_catcher = True
    scene.render.engine = "CYCLES"; scene.cycles.samples = samples; scene.cycles.device = "CPU"
    scene.render.resolution_x = 640; scene.render.resolution_y = 480
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    os.makedirs(PREVIEWS, exist_ok=True)
    scene.render.filepath = os.path.join(PREVIEWS, f"{model_name}.png")
    bpy.ops.render.render(write_still=True)


_common.render_preview = _studio_preview


def pipe(points, radius, sides=12, res=6, name="Pipe", cap=True):
    """Tube lisse (Bézier auto) à résolution maîtrisée ; extrémités bouchées."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    sp = curve.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for p, co in zip(sp.bezier_points, points):
        p.co = co
        p.handle_left_type = p.handle_right_type = "AUTO"
    curve.bevel_depth = radius
    curve.bevel_resolution = max(0, sides // 4 - 1)
    curve.resolution_u = res
    curve.use_fill_caps = cap
    o = link(bpy.data.objects.new(name, curve))
    deselect(); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    o = active(); o.select_set(False)
    shade(o, 60)
    return o


def hero(name, camera, up=(0, 0, 1), zoom=1.0, samples=48, official=True):
    """Re-rend l'aperçu avec un « haut » d'image choisi (ex. modèle couché qu'on veut voir debout).
    official=True : remplace assets/previews/<name>.png ; sinon rendu QA."""
    scene = bpy.context.scene
    cam = scene.camera
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and "__" in o.name]
    pts = [o.matrix_world @ Vector(v) for o in meshes for v in o.bound_box]
    mins = Vector([min(p[i] for p in pts) for i in range(3)])
    maxs = Vector([max(p[i] for p in pts) for i in range(3)])
    center = (mins + maxs) / 2
    radius = (maxs - mins).length / 2
    for c in list(cam.constraints):
        cam.constraints.remove(c)
    loc = center + Vector(camera).normalized() * radius * 3.2 / zoom
    f = (center - loc).normalized()
    right = f.cross(Vector(up)).normalized()
    tup = right.cross(f)
    cam.matrix_world = Matrix(((right.x, tup.x, -f.x, loc.x), (right.y, tup.y, -f.y, loc.y),
                               (right.z, tup.z, -f.z, loc.z), (0, 0, 0, 1)))
    floor = bpy.data.objects.get("ShadowCatcher")
    if floor is not None:
        floor.hide_render = True
    # le studio de lumières suit le « haut » choisi (sinon un modèle couché est éclairé par le côté)
    back = -f
    rig = [right * 0.9 + tup * 1.3 + back * 0.9, -right * 1.4 + tup * 0.3 + back * 0.7,
           tup * 0.9 - back * 1.3, -tup * 1.2 + back * 0.4]
    lights = sorted([o for o in bpy.data.objects if o.type == "LIGHT"], key=lambda o: o.name)
    for L, d in zip(lights, rig):
        L.location = center + d.normalized() * radius * 3.4
    scene.cycles.samples = samples
    path = os.path.join(PREVIEWS if official else QA_DIR, f"{name}.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
